//! Stage 0.5 rung 1 of the crown (`docs/crown/PLAN.md`, "Stage 0.5" item 1):
//! import-aware `ast-check`. Given the `Ast` that `cmdAstCheck` (in `main.zig`) already
//! parsed and already ran successfully through `AstGen`, walk its `@import` operands and
//! validate them against a stage-0 module-graph JSON document -- the same document
//! `-femit-module-graph` produces, whose schema is defined and emitted by
//! `Compilation/EmitModuleGraph.zig` (`ModuleNode` / `DepEdge` / `GraphRoot` / `Graph`).
//! That file is the schema source; this file decodes only the subset of fields rung 1
//! needs (`deps[].import_name` and `roots[].role`) rather than duplicating the whole shape.
//!
//! Kept in its own file per the fork's rebase-friendliness constraint (`docs/crown/
//! PLAN.md`, "Design constraints" #1): `cmdAstCheck` gains only the `--module-graph=`
//! flag parse and one call into `checkAgainstGraph` below.
//!
//! Stage 0.5 rung 3 (batch mode, `AstCheckBatch.zig`) reuses this file's walk instead of
//! duplicating it: `checkAgainstGraph` here renders-and-exits on the first violation, which
//! is correct for the single-file contract but wrong for a batch (it must keep checking the
//! rest of the files). So the walk is split into `loadAllowedNames` (graph loading, done
//! once and shared across every file in a batch rather than re-read per file) and
//! `collectGraphViolations` (pure data collection into a caller-owned `ErrorBundle.Wip`, no
//! rendering, no `process.exit`); `checkAgainstGraph` below is now a thin wrapper composing
//! both exactly as it always did, so its behavior -- and therefore rung 1's and the
//! single-file rung-3 byte-identity contract -- is unchanged.
//!
//! Stage 0.5 rung 2 ("decl-existence pass", `docs/crown/PLAN.md` Stage 0.5 item 2) also
//! lives in this file, gated by the additive `--check-decls` flag (valid only alongside
//! `--module-graph`; refused by name in `cmdAstCheck`, `main.zig`). It is implemented by
//! `checkDeclExistence` below -- a data-collecting twin of `collectGraphViolations` (same
//! caller-owned `ErrorBundle.Wip`, same no-render/no-exit contract) so the single-file,
//! batch and `--json` consumers compose this one owner rather than growing parallel
//! schemas. See its section comment for the honest scope (name existence, plus syntactic
//! arity shape for direct calls through the two supported import shapes) and the exact
//! alias-detection and opacity rules.
//!
//! Stage 0.5 rung 4 (check-as-module, `docs/crown/PLAN.md` "Stage 0.5" item 4) likewise:
//! `--as-module=<fully_qualified_name-or-index>` (parsed in `main.zig`, valid only
//! alongside `--module-graph`) binds the checked file to exactly one `ModuleNode` from the
//! graph via `resolveAsModule` below, producing a `ModuleBinding` that upgrades two of
//! `collectGraphViolations`' checks from rung 1's advisory, graph-wide semantics to
//! strict, per-module ones. THE SANDBOX CHECK IS A CHOSEN STRICTNESS, NOT PARITY WITH THE
//! COMPILER -- see the rung-4 section comment below for the measured evidence and the
//! wording both the help text and the violation itself carry.
//!
//! Honest scope, rung 1 (see `docs/crown/PLAN.md` "Stage 0.5" items 1 and 4): a named
//! import is checked against the *graph-wide union* of every module's declared import
//! names plus the graph's root roles -- not against the specific module the checked file
//! belongs to, because that identity is not yet knowable here (rung 4, "check-as-module",
//! is the flag that supplies it). A name valid *somewhere* in the graph therefore passes
//! here even if the checked file's own module never declares that dependency; the error
//! text for the opposite case (name valid nowhere) says this explicitly so a pass here is
//! never mistaken for the stricter rung-4 guarantee.
//!
//! Ast-walking note: this walks every node in the already-parsed `Ast` looking for
//! `@import` builtin-call nodes, rather than trusting `Zir`'s own `imports` table (which
//! `AstGen` already builds). That is deliberate, not an oversight: `AstGen` only reaches
//! its `.import` case -- and only accepts a string-literal operand there -- for a file that
//! type-checks as valid ZIR (see `AstGen.zig`'s `.import` case, which fails the whole file
//! with "@import operand must be a string literal" otherwise). By the time `cmdAstCheck`
//! calls us, that has already been enforced, so in practice every `@import` found here
//! already has exactly one string-literal operand. Re-deriving from the `Ast` instead of
//! reusing `Zir.imports` keeps this checker correct even if a future caller (e.g. a rung-3
//! batch mode) invokes it on an `Ast` that never went through a successful `AstGen` pass --
//! the non-literal-operand and skipped-nonliteral bookkeeping below is what makes that
//! degrade honestly instead of assuming an invariant it did not itself verify.

const std = @import("std");
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const Io = std.Io;
const Ast = std.zig.Ast;
/// Retained correction 8: the rung-2 walk consumes the one semantic binding
/// owner's own exported observations (`localVarRef`'s sidecar) rather than
/// re-deriving lexical ownership here.
const AstGen = std.zig.AstGen;
const Color = std.zig.Color;
const ErrorBundle = std.zig.ErrorBundle;
const fatal = std.process.fatal;
const introspect = @import("introspect.zig");

/// The subset of `Compilation/EmitModuleGraph.zig`'s `Graph` schema that rungs 1, 2 and 4
/// read. Deliberately not the full schema: `std.json`'s default `ignore_unknown_fields =
/// false` would otherwise reject every other field that schema emits (`optimize_mode`,
/// `strip`, `single_threaded`, `code_model`, `dep_fully_qualified_name`); we instead pass
/// `.ignore_unknown_fields = true` and only declare what we use. `index`,
/// `fully_qualified_name`, `root`, and `root_src_path` on `ModuleDoc`, and `dep_index` on
/// `DepDoc`, are rung-2/rung-4-only fields -- rung 1 only ever reads `deps[].import_name`
/// and `roots[].role`.
///
/// Every rung-2/rung-4-only field is `?T = null`, never a bare required field. The rung-2
/// body this file integrates measured why (its review finding BLOCKER 2):
/// `std.json`'s decoder raises `error.MissingField` for a declared field that a document
/// omits, so declaring these fields as required made *rung 1's own flagless
/// `--module-graph` run* hard-fail on documents rung 1 had previously accepted -- an
/// additive flag silently breaking the rung below it, the exact opposite of
/// `docs/crown/PLAN.md`'s "Design constraints" #2 (off by default, strict superset). (A
/// sibling WIP body for rung 4, on its own older base, declared them required; that shape
/// is corrected here rather than repeated, per that same finding.) Defaulting instead
/// means an old or hand-written document still loads for rung 1, and `--check-decls` /
/// `--as-module` refuse it *by name* (`rung2FieldGap` / `resolveAsModule` below) instead
/// of dying in the JSON decoder with a message that names neither the flag nor the field
/// (doctrine 2).
///
/// The cost of the default, stated: for `index`/`fully_qualified_name`/`root`/
/// `root_src_path`, an explicit JSON `null` is indistinguishable from an absent field.
/// Stage 0 always emits all four as non-null, so the two cases only ever co-occur on a
/// malformed document, and the gap refusals' wording says "missing, or present as JSON
/// null" rather than claiming to know which. `dep_index` is the one field where `null` is
/// stage 0's own meaningful value ("dependency module not found in `module_roots`"), and
/// there it keeps that meaning.
const GraphDoc = struct {
    modules: []const ModuleDoc,
    roots: []const RootDoc,
};
const ModuleDoc = struct {
    /// Stage 0's `ModuleNode.index` -- rungs 2 and 4 resolve a dependency/binding back to
    /// a concrete module by searching for this field rather than assuming JSON array
    /// position equals index (doctrine 2: verify, don't assume).
    index: ?usize = null,
    /// Rung 4 (`--as-module`) matches by this name first; it is documented convention,
    /// not guaranteed-unique identity (see `EmitModuleGraph.zig`'s `ModuleNode.index` doc
    /// comment).
    fully_qualified_name: ?[]const u8 = null,
    /// Rendered module-root directory (`EmitModuleGraph.zig`'s `ModuleNode.root`,
    /// `Compilation.Path.fmt`-formatted). Rung 2 joins it with `root_src_path` to locate a
    /// dependency's root source file; rung 4 prefix-compares file imports against it as
    /// the module's own sandbox boundary.
    root: ?[]const u8 = null,
    root_src_path: ?[]const u8 = null,
    deps: []const DepDoc,
};
const DepDoc = struct {
    import_name: []const u8,
    /// Index into the graph's modules, matched by `ModuleDoc.index` -- or null if stage 0
    /// could not resolve the dependency module (see `EmitModuleGraph.zig`'s `DepEdge.
    /// dep_index` doc comment). Rung 1 does not read this field. Defaulted for the reason
    /// `GraphDoc`'s doc comment gives; here the default coincides with stage 0's own
    /// "unresolved" value, so an absent field degrades into exactly the `target_unresolvable`
    /// bucket a null one does.
    dep_index: ?usize = null,
};
const RootDoc = struct {
    role: []const u8,
};

/// Honest denominators for the end-of-run summary line (doctrine 5 / plan rung 3 spirit):
/// `file_imports + named_imports + exempt + skipped_nonliteral` equals the total number
/// of `@import` sites walked, so the operator can reconcile the summary against the
/// source. `file_imports` and `named_imports` were VALIDATED; `exempt` is the
/// std/builtin/root shortcuts (nothing in the graph to check them against);
/// `skipped_nonliteral` is sites this rung could not honestly check (non-literal or
/// unparsable operands, wrong arity) -- reported as skipped, never folded into "checked".
pub const Stats = struct {
    file_imports: usize = 0,
    named_imports: usize = 0,
    exempt: usize = 0,
    skipped_nonliteral: usize = 0,
    /// Rung 4: a file-import site whose containment in the bound module's root could not
    /// be DETERMINED -- distinct from one determined to be outside (that is an error and
    /// stays in `file_imports`, because it was checked) and distinct from one checked
    /// clean. Folding it into `file_imports` would have claimed, inside the summary's
    /// "validated" figure, a check that did not happen. Always zero without `--as-module`,
    /// so rung 1's and rung 3's own runs are unaffected; defaulted so the `--json`
    /// `import_stats` object gains the field additively.
    sandbox_unresolvable: usize = 0,

    /// Every `@import` site walked lands in exactly one field above; this is the
    /// denominator `printSummary` prints, computed from the fields so the two cannot
    /// drift.
    pub fn total(s: Stats) usize {
        return s.file_imports + s.named_imports + s.exempt + s.skipped_nonliteral +
            s.sandbox_unresolvable;
    }
};

/// True iff `path` names a ZON document. The one place this extension rule is spelled, so
/// rung 1's import classification and rung 2's target-opacity decision can never drift
/// apart on what a ZON file is.
fn isZonPath(path: []const u8) bool {
    return mem.endsWith(u8, path, ".zon");
}

/// True iff `import_path` denotes a relative FILE import rather than a named module.
/// Mirrors the compiler's own classification (`src/Zcu/PerThread.zig:2384`): a file import
/// is any operand ending in ".zig" or ".zon". Shared by rung 1's import-validity walk and
/// rung 2's decl-existence target resolution so the two rungs can never disagree on the
/// file-vs-module question.
fn isFileImport(import_path: []const u8) bool {
    return mem.endsWith(u8, import_path, ".zig") or isZonPath(import_path);
}

/// The graph-derived lookup table `collectGraphViolations` checks names against. Split out
/// from `checkAgainstGraph` (see this file's top comment) so a rung-3 batch run loads and
/// builds this once, not once per file -- the graph document is invariant across an entire
/// `--module-graph=... f1.zig f2.zig ...` invocation.
pub const LoadedGraph = struct {
    /// Defaulted per rung-3 review item 7: a public type crossing a module boundary should
    /// stay forward compatible without forcing every construction site to name every field.
    allowed_names: std.StringHashMapUnmanaged(void) = .empty,
    /// Rungs 2 and 4: the full per-module nodes, read only by `checkDeclExistence` and
    /// `resolveAsModule` (rung 1's own `collectGraphViolations` walk never reads this).
    /// Defaulted empty for the same forward-compat reason as `allowed_names` above.
    modules: []const ModuleDoc = &.{},
};

/// Return value of `collectGraphViolations`: the honest-denominator `Stats` plus whether any
/// violation was recorded into the caller's `ErrorBundle.Wip`. Defaulted per rung-3 review
/// item 7, same reasoning as `LoadedGraph` above.
pub const GraphCheckResult = struct {
    stats: Stats = .{},
    had_error: bool = false,
};

/// Loads `graph_path` and validates every `@import` in `tree` against it, then prints the
/// one honest summary line the plan requires. On success, returns normally so the caller's
/// existing `cleanExit` path runs unchanged. On any violation, renders the violations in
/// `ast-check`'s own `ErrorBundle` style to stderr (same call shape `cmdAstCheck` already
/// uses for its own compile errors) and terminates with `process.exit(1)`, exactly like
/// `ast-check`'s own error path -- so `cmdAstCheck` needs no second error-handling branch
/// for graph violations.
///
/// A graph document that cannot be opened or parsed is a distinct failure class from "the
/// file has bad imports": it means the requested check could not run *at all*. Per doctrine
/// 2 (present-or-refuse-by-name), that is a named fatal error, never a silent skip of the
/// check the operator asked for.
///
/// `as_module_spec` is rung 4 (stage 0.5 item 4, "check-as-module"): `--as-module`'s value,
/// or null when the flag was not given. Resolved against the same `loaded` graph below; a
/// failed resolution is a named `fatal` here, with the same shape and precedent as an
/// unopenable graph document.
///
/// `check_decls` is rung 2 (stage 0.5 item 2, "decl-existence pass"): additive on top of
/// the above -- `false` reproduces rung 1's behavior byte-identically; `true` additionally
/// runs `checkDeclExistence` against the same loaded graph and the same `wip_errors`, so
/// both rungs' violations render as one bundle, and prints one further summary line. Its
/// two preconditions are refused by name before any checking runs: the document must carry
/// the fields rung 2 resolves through (`rung2FieldGap`), and the base that relative
/// module roots join against must be resolvable (`resolveGraphBase`).
pub fn checkAgainstGraph(
    arena: Allocator,
    io: Io,
    tree: Ast,
    zig_source_path: []const u8,
    display_path: []const u8,
    graph_path: []const u8,
    as_module_spec: ?[]const u8,
    check_decls: bool,
    /// AstGen's identifier-binding sidecar for THIS tree (retained correction
    /// 8), produced by the calling driver's opt-in lowering. Non-null whenever
    /// `check_decls` -- the two flags are keyed together at the driver -- and
    /// null exactly when rung 2 is unreachable, so the `.?` below is guarded by
    /// control flow, not by assumption.
    bindings: ?*const AstGen.IdentifierBindings,
    color: Color,
) !void {
    const loaded = try loadAllowedNames(arena, io, graph_path);

    // Rung 4: resolved once, mirroring `loaded` immediately above -- `fatal` here has the
    // same shape and precedent as an unopenable graph document (doctrine 2: the requested
    // check could not run at all). `as_module_spec` is null whenever the operator did not
    // pass `--as-module`, so `binding` stays null and the walk below falls back to rung
    // 1's original behavior untouched.
    const binding: ?ModuleBinding = if (as_module_spec) |spec| switch (try resolveAsModule(arena, io, loaded, spec)) {
        .ok => |b| b,
        .err => |msg| fatal("{s}", .{msg}),
    } else null;

    // Rung 2's two preconditions, established (and thereby declared -- see
    // `resolveGraphBase`) before any checking runs: without them, every named module
    // target would silently report unreadable and the operator would blame a correct
    // graph for a base this checker never had.
    var graph_base: []const u8 = "";
    if (check_decls) {
        if (try checkDeclsRefusal(arena, graph_path, loaded)) |msg| fatal("{s}", .{msg});
        graph_base = switch (try resolveGraphBase(arena, io)) {
            .ok => |b| b,
            .err => |msg| fatal("{s}", .{msg}),
        };
    }

    var wip_errors: ErrorBundle.Wip = undefined;
    try wip_errors.init(arena);
    const result = try collectGraphViolations(arena, io, tree, zig_source_path, display_path, loaded, binding, &wip_errors);
    var had_error = result.had_error;

    // Rung 2 (additive, off unless --check-decls): shares rung 1's already-loaded graph and
    // `wip_errors`/`had_error` rather than reloading or re-rendering, so a file with both
    // an unregistered import name (rung 1) and a missing-declaration reference (rung 2)
    // reports both in one bundle instead of the operator needing two invocations.
    // `binding` threads rung 4's binding into rung 2's named-target selection (retained
    // correction 6): null keeps the graph-wide union, non-null selects through the bound
    // module's own dep table. `bindings.?` is the correction-8 sidecar: non-null by the
    // same `check_decls` key that gates this block.
    var decl_stats: DeclStats = .{};
    if (check_decls) {
        const checked_dir = std.fs.path.dirname(zig_source_path) orelse ".";
        try checkDeclExistence(arena, io, tree, display_path, checked_dir, graph_base, loaded, binding, bindings.?, &wip_errors, &had_error, &decl_stats);
    }

    if (had_error) {
        var eb = try wip_errors.toOwnedBundle("");
        try eb.renderToStderr(io, .{}, color);
    }

    try printSummary(io, result.stats, null, binding);
    if (check_decls) try printDeclSummary(io, decl_stats, null);

    if (had_error) process.exit(1);
}

/// Loads `graph_path` and builds the union-of-names lookup table rung 1's semantics check
/// against: every declared import-edge name in the graph, plus the root roles (`std`, and
/// on test builds `main`, plus the `compiler_rt`/`ubsan_rt`/`zigc` runtime roots -- see
/// `EmitModuleGraph.zig`'s `GraphRoot` construction). This is rung 1's graph-wide semantics,
/// documented in `collectGraphViolations` and in the per-violation error text it emits.
pub fn loadAllowedNames(arena: Allocator, io: Io, graph_path: []const u8) !LoadedGraph {
    return switch (try loadAllowedNamesOrErr(arena, io, graph_path)) {
        .ok => |loaded| loaded,
        // Byte-identical to this function's own pre-rung-3-fix behavior: `msg` is already
        // the exact text `fatal` used to format inline before `loadGraph` stopped calling
        // `fatal` itself (see `loadGraph`'s doc comment below) -- this is that same call,
        // one level up.
        .err => |msg| fatal("{s}", .{msg}),
    };
}

/// Result of `loadAllowedNamesOrErr`: either the loaded, ready-to-use graph, or the failure
/// message a caller should surface (in whatever shape its own output mode requires).
pub const LoadedGraphOutcome = union(enum) {
    ok: LoadedGraph,
    err: []const u8,
};

/// Same as `loadAllowedNames`, but returns the failure message instead of calling `fatal`
/// directly -- for a caller (rung-3 batch mode, `AstCheckBatch.zig`) whose failure-reporting
/// shape depends on its own output mode (plain-text `fatal` when human-readable, a JSON
/// error document when `--json`; rung-3 review item 10) rather than always being a `fatal`.
pub fn loadAllowedNamesOrErr(arena: Allocator, io: Io, graph_path: []const u8) !LoadedGraphOutcome {
    return switch (try loadGraph(arena, io, graph_path)) {
        .ok => |graph| .{ .ok = try buildLoadedGraph(arena, graph) },
        .err => |msg| .{ .err = msg },
    };
}

fn buildLoadedGraph(arena: Allocator, graph: GraphDoc) Allocator.Error!LoadedGraph {
    var allowed_names: std.StringHashMapUnmanaged(void) = .empty;
    for (graph.modules) |m| for (m.deps) |d| try allowed_names.put(arena, d.import_name, {});
    for (graph.roots) |r| try allowed_names.put(arena, r.role, {});
    return .{ .allowed_names = allowed_names, .modules = graph.modules };
}

// ===========================================================================================
// Stage 0.5 rung 4 -- check-as-module (`docs/crown/PLAN.md` Stage 0.5 item 4).
//
// THE SANDBOX CHECK IS A CHOSEN STRICTNESS, NOT PARITY WITH THE COMPILER (the integrated
// WIP body's review finding V7, evidence verified in this tree rather than assumed).
// `Package/Module.zig`'s doc comment says "Only files inside this directory can be
// imported", but the compiler does not enforce that line for `@import`:
// `Zcu/PerThread.zig`'s `discoverImport` (the `@import` path) calls `upJoin` and performs
// no containment check at all, and the only `error.ImportOutsideModulePath` in the tree
// is raised inside `pub fn embedFile` (`Zcu/PerThread.zig`, surfaced through `Sema.zig`)
// -- i.e. `@embedFile` alone refuses an outside-package path. So `--as-module` can and
// will reject an `@import` that builds today. That is defensible as a pre-build discipline
// -- Module.zig's line is the documented intent, and a hyper-modular estate wants it
// enforced before a multi-minute compile -- but it is a divergence, and the flag says so
// in its own help text (`usage_ast_check`, `main.zig`) and in the violation it emits,
// rather than implying a rule the compiler already applies.
// ===========================================================================================

/// The result of successfully binding `--as-module` to one graph node: everything
/// `collectGraphViolations` needs to apply rung 4's strict, per-module semantics instead
/// of rung 1's graph-wide union. Built once per invocation by `resolveAsModule`
/// (single-file: once in `checkAgainstGraph`; batch: once in `AstCheckBatch.run`, reused
/// across every `.zig` member per this rung's "one `--as-module` binds ALL `.zig` members"
/// scope) and reused unchanged across every `@import` site it validates.
pub const ModuleBinding = struct {
    /// `ModuleNode.index` of the bound module, carried through for error messages.
    index: usize = 0,
    fully_qualified_name: []const u8 = "",
    /// Rung 4's strict named-import lookup: exactly the bound module's own `deps[].
    /// import_name` set -- the compiler's real resolution rule (`Package.Module.deps` is
    /// per-module, not shared graph-wide, unlike rung 1's `LoadedGraph.allowed_names`
    /// union). Defaulted per this file's established forward-compat convention.
    own_names: std.StringHashMapUnmanaged(void) = .empty,
    /// Rung 2's binding-strict named-target lookup (retained correction 6): the SAME one
    /// matched module's `deps[].import_name -> deps[].dep_index`, retained here instead
    /// of being discarded after `own_names` is built. A null value is an unresolved
    /// spelling -- stage 0 recorded `dep_index: null` for that edge, or the bound module
    /// itself declares the spelling twice with conflicting targets, collapsed to
    /// unresolved at build time rather than last-write-wins (an identical duplicate keeps
    /// its one target). `checkDeclExistence` selects named member targets from exactly
    /// this table when a binding is present -- rung 4's own per-module rule
    /// (`own_names`), applied to target selection one rung over. Defaulted per this
    /// file's established forward-compat convention.
    own_dep_indices: std.StringHashMapUnmanaged(?usize) = .empty,
    /// The bound module's root directory (`Package/Module.zig`'s sandbox boundary),
    /// resolved to an absolute, lexically-normalized path -- the base every file-import
    /// site is prefix-compared against in `sandboxCheck`. Always valid on a successfully
    /// constructed `ModuleBinding`: an unresolvable root refuses the whole `--as-module`
    /// request at `resolveAsModule` time instead of being carried as an optional here (see
    /// that function's doc comment).
    root_abs: []const u8 = "",
    /// The current process's cwd, resolved once for the whole invocation and reused by
    /// every per-file `sandboxCheck` call rather than re-fetched per file. Null iff
    /// `introspect.getResolvedCwd` failed *and* `root_abs` did not itself need it (i.e.
    /// the graph's `root` was already absolute) -- carried through so a per-file sandbox
    /// check that turns out to need it (the checked file's own resolved import path is
    /// relative) can fail closed on that one site instead of guessing.
    cwd_abs: ?[]const u8 = null,
};

/// Result of `resolveAsModule`: either a ready-to-use `ModuleBinding`, or the failure
/// message a caller should surface (in whatever shape its own output mode requires) --
/// same `.ok`/`.err` shape as `LoadedGraphOutcome` above, for the same reason (rung-3
/// review item 10: a `--json` caller must report this as a JSON document, not unconditional
/// stderr text).
pub const AsModuleOutcome = union(enum) {
    ok: ModuleBinding,
    err: []const u8,
};

/// Resolves `--as-module`'s value against `loaded.modules` and builds the `ModuleBinding`
/// `collectGraphViolations` needs to apply rung 4's strict semantics. Resolution order,
/// per the plan: an exact `fully_qualified_name` match is tried first (`Package/Module.zig`:
/// "Name used in compile errors"); only when that finds *nothing* does an all-digits
/// spelling fall back to a `ModuleNode.index` lookup -- `fully_qualified_name` is
/// documented convention, not guaranteed-unique identity (`EmitModuleGraph.zig`'s
/// `ModuleNode.index` doc comment: "Deliberately not keyed by fully_qualified_name"), so
/// two nodes can legitimately share one name; that case is reported as ambiguous (listing
/// every candidate index) rather than silently picking the first match. A spec matching
/// nothing at all is reported as unknown, naming how many modules the graph actually has.
///
/// Rung 4's schema gate runs first, inside this function rather than at each caller, so
/// both drivers (single-file `checkAgainstGraph` and batch `AstCheckBatch.run`) inherit it
/// once: every module node must carry `index`, `fully_qualified_name` and `root` -- the
/// name-or-index resolution scans all modules for the first two, and the sandbox needs
/// the matched one's `root`. A document missing any of them is refused by name, naming the
/// module and the field (mirroring `rung2FieldGap`'s reasoning below; see `GraphDoc`'s doc
/// comment for why these fields are optional in the schema rather than required in the
/// first place).
///
/// Also resolves the sandbox base here, once: `matched.root`, made absolute via
/// `introspect.getResolvedCwd` when it is not already absolute. `EmitModuleGraph.zig`'s
/// own doc comment records the caveat this inherits -- a `.none`-rooted `Package.Module`
/// is rendered *relative to the compiler process's cwd at the time the graph was emitted*
/// when that cwd is a prefix of the path, and absolute otherwise (`Compilation.zig`'s
/// `Path.Formatter`/`absToCwdRelative`). This function has no way to confirm `--as-module`
/// is being run from that same cwd -- it can only join a relative `root` against *this*
/// process's own cwd and trust the operator invoked `ast-check` from where the graph was
/// emitted, exactly as a relative `--module-graph=<path>` argument already requires (and
/// exactly as rung 2's `resolveGraphBase` below declares the same contract for its own
/// joins). When even that join is impossible (`getResolvedCwd` itself fails -- e.g. the
/// cwd was removed out from under the process), there is no honest base to sandbox-check
/// against, so the whole `--as-module` request is refused by name here rather than
/// silently skipping the sandbox check or flagging every file import as an escape.
pub fn resolveAsModule(arena: Allocator, io: Io, loaded: LoadedGraph, spec: []const u8) Allocator.Error!AsModuleOutcome {
    // The schema gate. First-gap-only, not a census: this is a refusal, not a report --
    // a document missing one of these fields on one node is a document from the wrong
    // emitter, and naming every node would bury the one fact that matters. The `.?`
    // unwraps further down are guarded by this gate, not assumed (doctrine 2).
    for (loaded.modules, 0..) |m, i| {
        const missing: []const u8 = if (m.index == null)
            "index"
        else if (m.fully_qualified_name == null)
            "fully_qualified_name"
        else if (m.root == null)
            "root"
        else
            continue;
        return .{ .err = try std.fmt.allocPrint(
            arena,
            "module graph cannot satisfy --as-module: module at array position {d} has no '{s}' field (missing, or present as JSON null) -- --as-module resolves its value by fully_qualified_name or index and sandbox-checks file imports against root, and cannot do so without it. Re-emit the graph with a compiler that includes Crown stage 0 (-femit-module-graph emits all three on every module)",
            .{ i, missing },
        ) };
    }

    var name_match_indices: std.ArrayList(usize) = .empty;
    for (loaded.modules, 0..) |m, i| {
        if (mem.eql(u8, m.fully_qualified_name.?, spec)) try name_match_indices.append(arena, i);
    }

    const matched_i: usize = switch (name_match_indices.items.len) {
        0 => resolve_by_index: {
            if (spec.len == 0 or !isAllDigits(spec)) {
                return .{ .err = try std.fmt.allocPrint(
                    arena,
                    "--as-module value '{s}' does not match any module's fully_qualified_name and is not a numeric index ({d} module(s) available in the graph -- pass a fully_qualified_name or a module index)",
                    .{ spec, loaded.modules.len },
                ) };
            }
            const idx = std.fmt.parseInt(usize, spec, 10) catch {
                return .{ .err = try std.fmt.allocPrint(arena, "--as-module value '{s}' is all-digits but does not parse as a module index", .{spec}) };
            };
            for (loaded.modules, 0..) |m, i| {
                if (m.index.? == idx) break :resolve_by_index i;
            }
            return .{ .err = try std.fmt.allocPrint(arena, "--as-module index {d} does not exist in the module graph ({d} module(s) available)", .{ idx, loaded.modules.len }) };
        },
        1 => name_match_indices.items[0],
        else => {
            var indices_list: std.ArrayList(u8) = .empty;
            for (name_match_indices.items, 0..) |i, k| {
                if (k != 0) try indices_list.appendSlice(arena, ", ");
                try indices_list.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{loaded.modules[i].index.?}));
            }
            return .{ .err = try std.fmt.allocPrint(
                arena,
                "--as-module value '{s}' is ambiguous: {d} modules share this fully_qualified_name (indices: {s}) -- fully_qualified_name is documented convention, not guaranteed-unique identity; use --as-module=<index> to disambiguate",
                .{ spec, name_match_indices.items.len, indices_list.items },
            ) };
        },
    };
    const matched = loaded.modules[matched_i];

    var own_names: std.StringHashMapUnmanaged(void) = .empty;
    for (matched.deps) |d| try own_names.put(arena, d.import_name, {});

    // Rung 2's binding-strict target lookup (retained correction 6), from the SAME one
    // matched module's `deps` -- no other module is scanned for this. A duplicate spelling
    // whose edges disagree (two distinct target indices, or one resolved edge alongside an
    // unresolved `dep_index: null` one) collapses to null: unresolved, never
    // last-write-wins and never one target picked; an identical duplicate keeps its
    // single target. `checkDeclExistence` refuses an unresolved spelling at use as
    // `target_unresolvable`, exactly as it already does for the unbound union's conflicts.
    var own_dep_indices: std.StringHashMapUnmanaged(?usize) = .empty;
    for (matched.deps) |d| {
        const gop = try own_dep_indices.getOrPut(arena, d.import_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = d.dep_index;
        } else if (gop.value_ptr.* != d.dep_index) {
            gop.value_ptr.* = null;
        }
    }

    // Fetched at most once, and only if actually needed below -- an absolute `root` never
    // needs it, matching this function's doc comment.
    const cwd_abs: ?[]const u8 = introspect.getResolvedCwd(io, arena) catch null;
    const root_abs: []const u8 = if (std.fs.path.isAbsolute(matched.root.?))
        try std.fs.path.resolve(arena, &.{matched.root.?})
    else if (cwd_abs) |c|
        try std.fs.path.resolve(arena, &.{ c, matched.root.? })
    else
        return .{ .err = try std.fmt.allocPrint(
            arena,
            "--as-module cannot sandbox-check module '{s}': its graph-recorded root ('{s}') is not an absolute path, and the current working directory could not be resolved to join against it -- refusing rather than guessing a base (Package/Module.zig's sandbox contract: \"Only files inside this directory can be imported\")",
            .{ matched.fully_qualified_name.?, matched.root.? },
        ) };

    return .{ .ok = .{
        .index = matched.index.?,
        .fully_qualified_name = matched.fully_qualified_name.?,
        .own_names = own_names,
        .own_dep_indices = own_dep_indices,
        .root_abs = root_abs,
        .cwd_abs = cwd_abs,
    } };
}

fn isAllDigits(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// Outcome of sandbox-checking one resolved file-import path against a `ModuleBinding`'s
/// root. `outside` and `unresolvable` carry their own message payload so the call site can
/// report the exact reason without recomputing it.
const SandboxOutcome = union(enum) {
    inside,
    /// The import's absolute, normalized path -- outside the module root -- for the error
    /// message.
    outside: []const u8,
    /// Why containment could not be determined at all (distinct from "checked and found
    /// outside"): reported as its own error rather than folded into `outside`, so an
    /// operator never mistakes "we couldn't tell" for "we checked and it escaped."
    unresolvable: []const u8,
};

/// Resolves one `@import` file operand to the path both the existence check and the
/// sandbox check must agree on. THE one place that resolution happens (the integrated WIP
/// body's review finding REJECT 1); the two consumers reading different paths is
/// precisely how an absolute operand walked out of the sandbox unnoticed.
///
/// `std.fs.path.join` does NOT reset on an absolute component -- measured on the promoted
/// 0.16.0 compiler:
///
///     join("/proj/root/sub", "/etc/passwd.zig") == "/proj/root/sub/etc/passwd.zig"
///
/// so an absolute operand was being resolved to a path *inside* the checked file's
/// directory (and, on the rung-1 existence check alone, falsely reported missing for any
/// absolute operand that does in fact exist on disk). The compiler's own resolution does
/// reset: `discoverImport` -> `Compilation.Path.upJoin` -> `introspect.resolvePath` ->
/// `std.fs.path.resolve`. This function restores that behavior at the one seam that feeds
/// both checks, exactly as that review prescribed. This is the one rung-1-visible change
/// integrating rung 4 makes, and it only changes output for inputs where the old output
/// was already wrong (a false "does not exist" red on an absolute operand).
fn resolveImportPath(arena: Allocator, checked_dir: []const u8, import_path: []const u8) Allocator.Error![]const u8 {
    if (std.fs.path.isAbsolute(import_path)) return import_path;
    return std.fs.path.join(arena, &.{ checked_dir, import_path });
}

/// Prefix-compares `resolved` (the file-import path from `resolveImportPath`, the same
/// value the existence check consumed) against `binding.root_abs`, after making `resolved`
/// itself absolute and lexically normalized the same way `resolveAsModule` normalized
/// `root_abs`. Lexical only -- like `resolveAsModule`, this does not follow symlinks
/// (`std.fs.path.resolve`'s own documented limitation), which is the same honest scope the
/// plan's "std.fs.path resolution + prefix comparison on normalized paths" instruction
/// calls for.
///
/// Every path out of here that is not `.inside` says WHICH question failed: "we checked and
/// it escaped" and "we could not tell" are different facts and must not read alike
/// (doctrine 2).
fn sandboxCheck(arena: Allocator, binding: ModuleBinding, resolved: []const u8) Allocator.Error!SandboxOutcome {
    const abs = if (std.fs.path.isAbsolute(resolved))
        try std.fs.path.resolve(arena, &.{resolved})
    else if (binding.cwd_abs) |c|
        try std.fs.path.resolve(arena, &.{ c, resolved })
    else
        return .{ .unresolvable = "the checked file's own path is relative and the current working directory could not be resolved to make its import path absolute for comparison against the module root" };

    return switch (pathIsWithinRoot(abs, binding.root_abs)) {
        .inside => .inside,
        .outside => .{ .outside = abs },
        // Measured, not hypothetical: `std.fs.path.resolve(arena, &.{ "", "sub/x.zig" })`
        // returns "sub/x.zig" -- still relative. So an empty `cwd_abs` (the WASI class:
        // `introspect.getResolvedCwd` returns "" there by contract) leaves `abs` relative,
        // and a lexical prefix comparison between a relative path and a root cannot mean
        // containment. Say so, rather than return whichever verdict the bytes happen to
        // produce.
        .undecidable => .{ .unresolvable = try std.fmt.allocPrint(
            arena,
            "containment is undecidable by lexical comparison: the import resolved to '{s}' and the module root is '{s}', and a prefix comparison only means containment when BOTH are absolute paths (an empty or relative value on either side is the WASI/unresolved-cwd class)",
            .{ abs, binding.root_abs },
        ) },
    };
}

/// Small formatting helper for the membership diagnostic: the absolute path when we
/// managed to compute one, else the path as the operator wrote it. Never a placeholder that
/// looks like a real path.
fn fa_or(abs: ?[]const u8, fallback: []const u8) []const u8 {
    return abs orelse fallback;
}

/// Three-valued on purpose (the integrated WIP body's review finding V5): `undecidable`
/// is not `outside`. A boolean here forced every "we cannot tell" into a verdict, and both
/// directions were wrong in practice -- an empty root made every absolute child look
/// inside, and a root of "/" made every child look outside.
const WithinRoot = enum { inside, outside, undecidable };

/// Whether `child_abs` names a path lexically inside the directory `root_abs` -- not equal
/// to it (a directory is not "inside" itself) and not merely string-prefixed by it (e.g.
/// `/root-extra` must not count as inside `/root`): the byte after the shared prefix must
/// be a path separator.
///
/// An earlier body assumed both arguments were "already absolute and normalized ... by
/// their respective callers" and returned a bool. Review measured two boundary classes
/// where that assumption does not hold and the bool therefore lied:
///
///   * root normalizes to bare "/" (reachable: `std.fs.path.resolve(&.{"/a/.."})` == "/").
///     Then the byte after the shared prefix is the first byte of the child's own first
///     component, never a separator, so EVERY child was reported outside -- a false
///     violation on every import in such a module.
///   * root is "" (the WASI class -- `introspect.getResolvedCwd` returns "" there). Then
///     `startsWith` is vacuously true and `child_abs[0]` is the leading separator, so
///     EVERY absolute child was reported inside -- a false pass, the worse direction.
///
/// So the assumption is now checked instead of assumed, and the unmet case has its own
/// answer.
fn pathIsWithinRoot(child_abs: []const u8, root_abs: []const u8) WithinRoot {
    const sep = std.fs.path.sep;
    // A lexical prefix comparison means containment only between two absolute paths.
    // Anything else -- empty, relative -- is undecidable here, not a verdict.
    if (!std.fs.path.isAbsolute(root_abs)) return .undecidable;
    if (!std.fs.path.isAbsolute(child_abs)) return .undecidable;

    // Tolerate a trailing separator on the root rather than trusting a caller to have
    // stripped it; "/proj/root/" and "/proj/root" name the same directory.
    const root = if (root_abs.len > 1 and root_abs[root_abs.len - 1] == sep)
        root_abs[0 .. root_abs.len - 1]
    else
        root_abs;

    // The filesystem root is the one directory whose children are not separated from it by
    // an extra separator: "/" + "x" is "/x", not "//x". Every absolute path except "/"
    // itself is inside it.
    if (root.len == 1) return if (child_abs.len > 1) .inside else .outside;

    if (!mem.startsWith(u8, child_abs, root)) return .outside;
    if (child_abs.len == root.len) return .outside;
    return if (child_abs[root.len] == sep) .inside else .outside;
}

/// Walks every `@import` site in `tree` and validates it against `loaded`, recording any
/// violation into the caller-owned, already-`init`ed `wip_errors` -- no rendering, no
/// `process.exit`, so a caller that must keep going after a violation (the rung-3 batch
/// path) can. `checkAgainstGraph` above is the single-file caller that renders+exits to
/// preserve its established byte-identical contract.
///
/// `binding`, when non-null (rung 4: `--as-module` was given and `resolveAsModule`
/// succeeded), upgrades both import checks below from rung 1's advisory semantics to
/// strict, per-module semantics -- see the rung-4 section comment above. `binding == null`
/// reproduces rung 1's exact prior behavior; every rung-1/rung-3 call site that never
/// knew about `--as-module` passes `null` here and stays byte-identical.
pub fn collectGraphViolations(
    arena: Allocator,
    io: Io,
    tree: Ast,
    zig_source_path: []const u8,
    display_path: []const u8,
    loaded: LoadedGraph,
    binding: ?ModuleBinding,
    wip_errors: *ErrorBundle.Wip,
) !GraphCheckResult {
    const allowed_names = loaded.allowed_names;
    const checked_dir = std.fs.path.dirname(zig_source_path) orelse ".";

    var stats: Stats = .{};
    var had_error = false;

    // The rung-4 membership premise (the integrated WIP body's review finding V6). This
    // rung's whole claim is "this file, AS module X" -- so the first thing checked is the
    // first half of that claim. A file outside X's root passed clean while its ordinary,
    // entirely legal local imports were accused of escaping X's sandbox: the accusation
    // was backwards, and the operator had no way to see that the premise, not the code,
    // was what failed. `Package/Module.zig` is explicit that a module's files live under
    // its root, so membership is checkable here.
    //
    // Reported as a per-file bundle error rather than a `fatal`: in batch mode one
    // mis-bound member must not kill the other N-1 files (rung 3's whole contract is that
    // the denominator never silently shrinks). It has no source span -- it is a fact about
    // the file, not about a line in it -- so it goes in with `src_loc = .none`.
    if (binding) |b| {
        const file_abs = if (std.fs.path.isAbsolute(zig_source_path))
            try std.fs.path.resolve(arena, &.{zig_source_path})
        else if (b.cwd_abs) |c|
            try std.fs.path.resolve(arena, &.{ c, zig_source_path })
        else
            null;
        const membership: WithinRoot = if (file_abs) |fa| pathIsWithinRoot(fa, b.root_abs) else .undecidable;
        switch (membership) {
            .inside => {},
            .outside => {
                had_error = true;
                try wip_errors.addRootErrorMessage(.{ .msg = try wip_errors.printString(
                    "--as-module premise fails: '{s}' resolves to '{s}', which is not inside module '{s}''s root '{s}', so this file is not a member of that module and \"this file, as module '{s}'\" is not a claim that can hold. Every import check below is being applied under a binding this file does not satisfy",
                    .{ display_path, fa_or(file_abs, zig_source_path), b.fully_qualified_name, b.root_abs, b.fully_qualified_name },
                ) });
            },
            .undecidable => {
                had_error = true;
                try wip_errors.addRootErrorMessage(.{ .msg = try wip_errors.printString(
                    "--as-module premise could not be checked: '{s}' could not be resolved to an absolute path to test membership in module '{s}''s root '{s}'. Refusing to check imports under a binding whose premise is unverified",
                    .{ display_path, b.fully_qualified_name, b.root_abs },
                ) });
            },
        }
    }

    const node_count: u32 = @intCast(tree.nodes.len);
    var node_idx: u32 = 0;
    while (node_idx < node_count) : (node_idx += 1) {
        const node: Ast.Node.Index = @enumFromInt(node_idx);
        switch (tree.nodeTag(node)) {
            .builtin_call, .builtin_call_comma, .builtin_call_two, .builtin_call_two_comma => {},
            else => continue,
        }
        const builtin_token = tree.nodeMainToken(node);
        if (!mem.eql(u8, tree.tokenSlice(builtin_token), "@import")) continue;

        var params_buf: [2]Ast.Node.Index = undefined;
        const params = tree.builtinCallParams(&params_buf, node) orelse continue;
        if (params.len != 1) {
            // Wrong arity for @import cannot survive a successful AstGen (see this file's
            // top comment); folded into the same "could not honestly check" bucket as a
            // non-literal operand rather than inventing an unrequested fifth category.
            stats.skipped_nonliteral += 1;
            continue;
        }
        const operand = params[0];
        if (tree.nodeTag(operand) != .string_literal) {
            stats.skipped_nonliteral += 1;
            continue;
        }

        const str_token = tree.nodeMainToken(operand);
        const raw = tree.tokenSlice(str_token);
        const import_path = std.zig.string_literal.parseAlloc(arena, raw) catch {
            // Malformed escape sequence: a real compile already diagnoses this via AstGen.
            // We cannot honestly resolve a name we cannot parse, so it is skipped, not
            // silently treated as valid.
            stats.skipped_nonliteral += 1;
            continue;
        };

        // File-vs-module classification mirrors the compiler's own via `isFileImport`
        // (src/Zcu/PerThread.zig:2384); everything else is a named module. Diverging from
        // that rule here produced a hard false positive on legal @import("x.zon") in
        // review -- keep the two (and rung 2, which shares the helper) in lockstep.
        if (isFileImport(import_path)) {
            // ONE resolution, consumed by both the existence check and the sandbox check
            // (review finding REJECT 1). `resolveImportPath` -- not a bare `join` -- so an
            // absolute operand resets the path instead of being appended to the checked
            // file's directory.
            const resolved = try resolveImportPath(arena, checked_dir, import_path);
            const exists = if (Io.Dir.cwd().access(io, resolved, .{})) |_| true else |_| false;
            if (!exists) {
                stats.file_imports += 1;
                had_error = true;
                try addImportError(wip_errors, tree, display_path, operand, "@import of relative file that does not exist on disk: '{s}' (resolved path: '{s}')", .{ import_path, resolved });
            } else if (binding) |b| {
                // Rung 4 sandbox check, gated on `exists` above so a nonexistent import
                // gets exactly one error, not two, on the same site. This is a strictness
                // this fork CHOOSES; the compiler does not enforce it -- see the rung-4
                // section comment above and the error text below.
                switch (try sandboxCheck(arena, b, resolved)) {
                    .inside => stats.file_imports += 1,
                    .outside => |abs| {
                        stats.file_imports += 1;
                        had_error = true;
                        try addImportError(wip_errors, tree, display_path, operand, "@import leaves module '{s}''s root directory: '{s}' resolves to '{s}', which lies outside '{s}'. This is a strictness --as-module CHOOSES, not a compiler rule: today the compiler enforces no @import sandbox at all (only @embedFile refuses an outside-package path), so this code may well build. Package/Module.zig states the intended contract (\"Only files inside this directory can be imported\") and --as-module checks it before a build", .{ b.fully_qualified_name, import_path, abs, b.root_abs });
                    },
                    .unresolvable => |reason| {
                        // Its OWN counted category (review finding V4): folding a site we
                        // could not check into `file_imports`' "validated" figure claimed
                        // a check that did not happen. An absent instrument reports
                        // UNKNOWN, never a verdict (doctrine 2).
                        stats.sandbox_unresolvable += 1;
                        had_error = true;
                        try addImportError(wip_errors, tree, display_path, operand, "@import '{s}' could not be sandbox-checked against module '{s}': {s}", .{ import_path, b.fully_qualified_name, reason });
                    },
                }
            } else stats.file_imports += 1;
        } else if (mem.eql(u8, import_path, "std") or mem.eql(u8, import_path, "builtin") or mem.eql(u8, import_path, "root")) {
            // Special-cased shortcuts: never present in `Package.Module.deps` (see
            // `EmitModuleGraph.zig`'s `DepEdge` doc comment), so there is nothing in the
            // graph to look them up against. Counted as `exempt` so the summary's total
            // reconciles against every @import site in the source. Exempt regardless of
            // `binding` -- rung 4 does not change this axis, only named/file imports.
            stats.exempt += 1;
        } else {
            stats.named_imports += 1;
            if (binding) |b| {
                // Rung 4 strict semantics: checked against exactly this module's own
                // `deps[].import_name` set, not the graph-wide union `allowed_names` below
                // represents -- the compiler's own resolution rule (`Package.Module.deps`
                // is per-module, not shared).
                if (!b.own_names.contains(import_path)) {
                    had_error = true;
                    try addImportError(wip_errors, tree, display_path, operand, "module '{s}' does not declare import '{s}' (rung-4 --as-module strict semantics: checked against exactly this module's own dependency table, not the graph-wide union rung 1 uses without --as-module)", .{ b.fully_qualified_name, import_path });
                }
            } else if (!allowed_names.contains(import_path)) {
                had_error = true;
                try addImportError(wip_errors, tree, display_path, operand, "unregistered module import name: '{s}' is not declared as an import edge anywhere in the module graph (rung-1 semantics: this checks the graph-wide union of every module's import names, not the specific module this file belongs to -- per-module strict matching arrives with --as-module, stage 0.5 rung 4)", .{import_path});
            }
        }
    }

    return .{ .stats = stats, .had_error = had_error };
}

fn addImportError(
    wip: *ErrorBundle.Wip,
    tree: Ast,
    display_path: []const u8,
    operand: Ast.Node.Index,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const span = tree.nodeToSpan(operand);
    const loc = std.zig.findLineColumn(tree.source, span.main);
    const src_loc = try wip.addSourceLocation(.{
        .src_path = try wip.addString(display_path),
        .span_start = span.start,
        .span_main = span.main,
        .span_end = span.end,
        .line = @intCast(loc.line),
        .column = @intCast(loc.column),
        .source_line = try wip.addString(loc.source_line),
    });
    try wip.addRootErrorMessage(.{
        .msg = try wip.printString(fmt, args),
        .src_loc = src_loc,
    });
}

/// The one summary line the plan requires (doctrine 4, self-report): printed at the end of
/// every graph-checked run, pass or fail, so the operator never has to infer what was
/// actually checked from the presence or absence of errors alone.
///
/// `pub` since rung 3 (`AstCheckBatch.zig`) reuses it verbatim for each graph-checked file
/// in a batch's human-readable (non-`--json`) output, instead of re-deriving the same
/// format string a second time.
///
/// `path_prefix`, when non-null, prefixes the line with `"<path>: "` -- rung-3 batch mode
/// passes its own file path here so this line is attributable at N>1 files (rung-3 review
/// item 6: bare, this was the one line in batch output with no path attribution at all,
/// unlike every other batch-mode line). The single-file caller (`checkAgainstGraph` above)
/// passes `null`, preserving its own byte-identical output exactly.
///
/// `binding`, when non-null (rung 4), appends the sandbox-unresolvable count and a
/// semantics clause naming the bound module and the rule it applied -- a passing strict
/// run and a passing union run must not be byte-identical, or the line cannot testify to
/// which semantics produced it (the integrated WIP body's review finding REJECT 3,
/// doctrine 4). The clause is appended ONLY when a binding exists, and that is a
/// deliberate choice, not an omission: rung 1's and rung 3's summary format is a contract
/// their own reviews ratified, and rung 4 is an additive flag that must not move it.
/// Without `--as-module`, `sandbox_unresolvable` is zero by construction, so printing it
/// would move a ratified format for no information; `--as-module` absent therefore prints
/// exactly what it always printed. The `--json` surface, which has no byte-identity
/// contract to keep, reports `check_semantics` on BOTH paths.
pub fn printSummary(io: Io, stats: Stats, path_prefix: ?[]const u8, binding: ?ModuleBinding) !void {
    var buffer: [512]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
    if (path_prefix) |p| try w.print("{s}: ", .{p});
    try w.print(
        "import sites seen {d}: validated {d} (file {d}, named {d}), exempt(std/builtin/root) {d}, skipped-unchecked {d}",
        .{
            stats.total(),
            stats.file_imports + stats.named_imports,
            stats.file_imports,
            stats.named_imports,
            stats.exempt,
            stats.skipped_nonliteral,
        },
    );
    if (binding) |b| {
        try w.print(", sandbox-unresolvable {d}; semantics strict (as module '{s}', graph index {d}: named imports checked against that module's own deps, file imports sandboxed to its root)\n", .{ stats.sandbox_unresolvable, b.fully_qualified_name, b.index });
    } else {
        try w.writeAll("\n");
    }
    try w.flush();
}

/// Result of the low-level graph read+parse: either the decoded document, or an
/// already-formatted failure message. Returning the message as data rather than calling
/// `fatal` (as this function did before the rung-3 fix) keeps the three distinct wordings
/// (open/read/parse) in this one place, so every caller -- the byte-identical single-file
/// `fatal` path and the `--json`-aware batch path alike -- reports the exact same text for
/// the exact same failure (rung-3 review item 10).
const GraphLoadResult = union(enum) {
    ok: GraphDoc,
    err: []const u8,
};

/// Reads and parses the stage-0 module-graph JSON document. Any failure here -- the file
/// cannot be opened, or its contents are not the expected JSON shape -- is a named failure
/// (doctrine 2, present-or-refuse-by-name): the check the operator asked for cannot run at
/// all, so it must never look like a silent pass. Returns the failure as data (`.err`)
/// rather than calling `process.fatal` itself, so a `--json` caller can report it as a JSON
/// document instead of unconditional stderr text; see `loadAllowedNames`/
/// `loadAllowedNamesOrErr` above for the two ways a caller turns this back into the
/// byte-identical `fatal` behavior this function used to provide directly.
fn loadGraph(arena: Allocator, io: Io, graph_path: []const u8) Allocator.Error!GraphLoadResult {
    var f = Io.Dir.cwd().openFile(io, graph_path, .{}) catch |err| {
        return .{ .err = try std.fmt.allocPrint(arena, "unable to open module graph '{s}' for --module-graph: {t}", .{ graph_path, err }) };
    };
    defer f.close(io);
    var read_buffer: [4096]u8 = undefined;
    var file_reader: Io.File.Reader = f.reader(io, &read_buffer);
    const json = std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch |err| {
        return .{ .err = try std.fmt.allocPrint(arena, "unable to read module graph '{s}' for --module-graph: {t}", .{ graph_path, err }) };
    };
    // `ignore_unknown_fields`: see `GraphDoc`'s doc comment. Note also the inherited
    // caveat from `EmitModuleGraph.zig`'s doc comment -- a non-UTF-8 name anywhere in the
    // document changes that field's JSON type from string to an int-array, which this
    // subset schema does not special-case; such a document fails to parse here and is
    // reported through this same named-failure path rather than silently mis-decoded.
    const doc = std.json.parseFromSliceLeaky(GraphDoc, arena, json, .{ .ignore_unknown_fields = true }) catch |err| {
        return .{ .err = try std.fmt.allocPrint(arena, "malformed module-graph JSON '{s}' for --module-graph: {t}", .{ graph_path, err }) };
    };
    return .{ .ok = doc };
}

// ===========================================================================================
// Stage 0.5 rung 2 -- the decl-existence pass ("sema-lite", `docs/crown/PLAN.md` Stage 0.5
// item 2).
//
// SCOPE, DELIVERED IN TWO POPULATIONS (the arity half lands per the retained C9 P2 arity
// dispatch). PLAN.md charters this rung as "name existence and arity-level shape only,"
// and both halves are implemented -- each for the exact population it can honestly own.
//
// Succession note (doctrine 7: quote the retired approach): the earlier bodies of this
// rung implemented NAME EXISTENCE ONLY and stated "arity: DEFERRED" here, in the help
// text, and on every summary line. Their deferral rationale -- an honest arity check is
// not a parameter count; it "has to survive method-call sugar (`m.f(x)` may pass the
// receiver, or may not, depending on what `m.f` resolves to -- a question this rung has
// no types to answer), variadic and `anytype` parameters, comptime-generic parameters
// that change the callable shape, and default-carrying call shapes" -- is answered
// below not by guessing any of those but by refusing to compare them, counted:
//
//   * method-call sugar: the arity pass measures ONLY direct calls whose callee is
//     EXACTLY a member reference of a supported import shape -- inline
//     `@import("x").f`, or a const import alias bound *directly* to the `@import` call
//     at root/file scope OR function-local (shape (b), function-local added by
//     retained correction 8) -- which name
//     a MODULE NAMESPACE member, so a direct call has NO implicit receiver to guess.
//     An `obj.method(...)` or `m.Type.method(...)` callee never qualifies (its LHS is a
//     field access, not a supported shape), so the old receiver question is not
//     approximated -- it is outside the population.
//   * variadic / `anytype` / `comptime`-generic callees: the target's declaration shape
//     is `dynamic_fn`, counted `arity_skipped_dynamic`, never compared.
//   * a function-valued public const: `other_decl`, counted `arity_skipped_non_fn` --
//     syntactically a non-fn declaration that MAY be function-valued after Sema; never
//     called non-callable, never compared.
//   * a duplicate public spelling in a parse-only target: `ambiguous_decl`, counted
//     `arity_unavailable`; no arity is ever chosen between duplicates.
//
// What is compared, exactly: the callee's FIXED SYNTACTIC PARAMETER COUNT against the
// call's written argument count. Nothing else -- no types, no comptime, no implicit
// receiver, no default arguments, no minimum variadic arity, no inferred callable
// values, no generic instantiation. Each of those is an explicit unsupported/dynamic
// outcome above, never an approximation. `Sema`'s `checkCallArgumentCount` is the
// compiler's type-driven truth and stays the compiler's job; this pass claims no parity
// with it, only a cheaper syntactic verdict.
//
// Where the boundary is stated so it reaches an operator and not only a reader of this
// file: `zig ast-check --help` (`usage_ast_check` in main.zig) and the rung-2 summary's
// SECOND line, printed on every run, pass or fail.
//
// Honest scope, restated from the plan: name existence and single-level alias resolution
// only -- no types, no comptime, no multi-hop or dynamic aliasing. Two shapes of member
// access are resolved:
//
//   (a) inline:        `@import("x").foo`
//   (b) single alias:  `const m = @import("x"); ... m.foo`  (`m` a `const` -- root/file-scope
//                       OR function-local, retained correction 8 -- bound *directly* to the
//                       `@import` call; nothing else qualifies)
//
// Every other flow that could plausibly reach an import's namespace is OUTSIDE this rung's
// supported population, and an unsupported shape is ignored honestly -- never followed,
// never counted, never diagnosed. The exact boundary:
//
//   * a FILE-SCOPE `var` bound to `@import` (reassignable, so not shape (b)) is a ROOT
//     import binding the walk CAN see -- counted `alias_too_deep`, a counted refusal, not a
//     guess: the binding IS import-derived and only the follow is too deep;
//   * a file-scope `const` bound to another name (a chain, however deep) -- the same
//     root-level counted refusal, `alias_too_deep`;
//   * a file-scope binding whose `@import` literal does not parse -- `operand_unparsable`;
//   * a FUNCTION-LOCAL `const` bound directly to a parseable `@import` -- shape (b) as of
//     retained correction 8: AstGen's own `localVarRef` sidecar names the exact declaration
//     this use resolved to, and its initializer is inspected (never a spelling match), so
//     the same authority the root alias always had now reaches the local one. Its
//     unparsable-operand case is the same `operand_unparsable` counted refusal;
//   * EVERY other non-root binding -- a function-local `var` from an import (reassignable),
//     a local `const` bound to another name (an alias chain), a function PARAMETER, a
//     capture payload of any form, a nested container's own declaration -- IGNORED: no
//     bucket, no diagnostic. Retained correction 3 retired the former treatment of these
//     (see the succession note in `checkDeclExistence`), and correction 8 keeps that
//     refusal for every one of them: known LEXICAL ownership (the sidecar states exactly
//     which parameter, capture, or local owns the spelling) is still not known VALUE
//     provenance -- establishing what a parameter or capture carries needs types or
//     dataflow, outside this rung's "no types, no comptime" charter. What cannot be
//     owned is not attributed at all.
//
// What this rung therefore claims -- and no more: the two supported shapes above, plus the
// root-level counted refusals. It does NOT claim to find every import-derived member
// reference in the file; references through the unsupported shapes are simply not its
// population. The exercised discrimination is what the proof-set controls run: a
// sibling-scope var collision, one function-parameter form (`m: anytype`), the `if`,
// `while`, `for`, and pointer capture forms, the switch payload/tag and `catch`/error/
// `errdefer` capture forms, two sibling locals of one spelling bound to different targets,
// and a closure-tunneled root reference beside a nested namespace declaration.
//
// One precondition this inherits from the drivers rather than enforces itself: shape (b)
// presumes the checked file passed AstGen, which both shipped drivers require before this
// walk runs (a diagnostic ZIR publishes a CLEARED sidecar, and both drivers refuse rung 2
// on compile errors before reaching here). AstGen rejects a local that shadows a container
// declaration (`detectLocalShadowing`, lib/std/zig/AstGen.zig), so a spelling that is BOTH
// a file-scope alias and a local binding cannot reach this walk through them; a caller
// handing this data-collecting owner a tree whose sidecar facts do not name a declaration
// gets the unknown/absent treatment for every such use -- named here rather than silently
// fixed. Succession note (doctrine 7): before retained correction 8 this paragraph ended
// "a caller ... gets name-matched root attribution for such a spelling" -- the spelling
// sets are gone; the fact-keyed walk has no name match left to mis-attribute.
//
// Once a member access resolves to an import, the target is located through the ONE
// resolution seam every rung shares: `resolveImportPath` for file imports (`isFileImport`:
// relative `.zig`/`.zon` file vs. named module looked up in the graph) and the same
// declared-base join rung 1 uses for named ones. The TARGET file is then
// parsed with `Ast.parse` only -- no `AstGen`, matching the plan's honest scope. (The
// CHECKED file's binding facts, retained correction 8, come from the AstGen lowering the
// drivers already run for every `ast-check` -- observed in passing, not a new pass.) The target
// is OPAQUE -- every member reference into it counted `opaque_skipped`, nothing guessed --
// if its top level contains a `comptime` block. (`usingnamespace` is the plan's other named
// opacity trigger; it does not exist in this fork's Zig language at all -- confirmed absent
// from the whole `lib/` and `src/` tree -- so there is no corresponding case to write here;
// a future rebase that reintroduces the keyword would need to add one.) A `.zon` file
// import is also treated as opaque: ZON is data, not declarations, so "public top-level
// declaration" does not apply to it.
//
// Composition with rung 4 (`--as-module` + `--check-decls` in one invocation), per the
// retained correction-6 policy split -- succession note (doctrine 7: quote the retired
// approach): the first body of this composition read "rung 2's member-TARGET resolution
// stays graph-wide, exactly as documented below ... the two WIP bodies that this file
// integrates never composed their stricter halves, and inventing a binding-scoped target
// resolution here would be unreviewed new semantics." Retained review overturned that
// stance as a named residual that the plan never required: the plan's check-as-module
// claim and Zig's per-module import-table model (`Package.Module.deps` is per-module;
// `Build.Module.import_table` maps a bound module's import name to exactly one module)
// specify the policy -- once a file is bound as module X, a named import resolves through
// X's own dependency edge, not the graph-wide union. So:
//   * UNBOUND `--check-decls` keeps the graph-wide conservative union, byte-for-behavior
//     the construction this rung has always had (a name mapping to more than one
//     distinct target collapses to `target_unresolvable`, never a guess);
//   * BOUND `--as-module` + `--check-decls` selects named member targets from exactly
//     the bound module's own retained `own_dep_indices` table -- a name the bound module
//     does not declare, a null/unresolved index, or a spelling its own table collapsed
//     as conflicting reports the SAME `target_unresolvable` outcome at use, never a
//     graph-wide target, never an invented `missing`, never an arity mismatch.
// File imports and the std/builtin/root exemptions read neither table -- unchanged by
// the split. Rung 4's import validation (`own_names`) is unchanged too: rung 4 still
// refuses, strictly and by name, a named import the bound module does not declare.
// ===========================================================================================

/// Rung 2's schema gate (the integrated WIP body's review finding BLOCKER 2). Returns
/// `null` when every module node carries the three rung-2-only fields, or an
/// already-formatted description of the *first* gap otherwise -- naming the module by
/// whatever identity the document still offers and the exact field that is missing, so the
/// operator is told what to re-emit rather than being handed `error.MissingField` from a
/// JSON decoder.
///
/// Deliberately first-gap-only, not a census: this is a refusal, not a report. A document
/// missing one of these fields on one node is a document from the wrong emitter, and naming
/// every node would bury the one fact that matters. `checkDeclExistence`'s `.?` unwraps of
/// these three fields are sound exactly because a driver ran this first and refused by
/// name otherwise -- the unwraps are guarded by control flow, not by assumption (doctrine
/// 2). `pub` because batch mode (`AstCheckBatch.zig`) runs the same gate once for the
/// whole batch, refusing the run by name before any per-file work.
pub fn rung2FieldGap(arena: Allocator, loaded: LoadedGraph) Allocator.Error!?[]const u8 {
    for (loaded.modules, 0..) |m, i| {
        const missing: []const u8 = if (m.index == null)
            "index"
        else if (m.root == null)
            "root"
        else if (m.root_src_path == null)
            "root_src_path"
        else
            continue;
        return try std.fmt.allocPrint(
            arena,
            "module at array position {d} has no '{s}' field (missing, or present as JSON null) -- --check-decls resolves a named import to a concrete file through index/root/root_src_path and cannot do so without it",
            .{ i, missing },
        );
    }
    return null;
}

/// The complete, ready-to-surface named refusal for a graph document that cannot satisfy
/// `--check-decls` -- one owner for the wording, so the single-file driver (`fatal`) and
/// the batch driver (`--json` error document or `fatal`, per its own output mode) report
/// the exact same text for the exact same failure (rung-3 review item 10's reasoning,
/// applied to rung 2's gate). Returns null when the document satisfies rung 2's schema.
pub fn checkDeclsRefusal(arena: Allocator, graph_path: []const u8, loaded: LoadedGraph) Allocator.Error!?[]const u8 {
    const gap = (try rung2FieldGap(arena, loaded)) orelse return null;
    return try std.fmt.allocPrint(
        arena,
        "module graph '{s}' cannot satisfy --check-decls: {s}. Re-emit the graph with a compiler that includes Crown stage 0 (-femit-module-graph emits index/root/root_src_path on every module), or drop --check-decls to run the rung-1 import check alone",
        .{ graph_path, gap },
    );
}

/// Result of establishing rung 2's resolution base: the absolute directory a relative
/// `ModuleNode.root` is joined against, or the failure message to refuse with. `pub` with
/// the same reasoning as `rung2FieldGap`: the batch driver surfaces the failure through its
/// own output mode (plain `fatal` or a JSON error document), so it must travel as data.
pub const GraphBaseOutcome = union(enum) {
    ok: []const u8,
    err: []const u8,
};

/// Establishes -- and thereby DECLARES -- the base that a relative `ModuleNode.root` is
/// resolved against. The integrated WIP body's review finding MAJOR 4:
///
///   "graph root paths are rendered cwd-relative to the EMITTING process
///   (Compilation.Path.Formatter -> absToCwdRelative; '.' for zig_lib) -- running from any
///   other directory makes every named-module target 'unreadable'; resolution premise needs
///   a declared base or a documented same-cwd contract with a named refusal."
///
/// The mechanism, verified in this tree rather than assumed: `Compilation.zig`'s
/// `Path.Formatter.format` renders a `.none`-rooted path through `absToCwdRelative`, which
/// strips the emitting process's own cwd prefix and returns "." when the path IS the cwd; a
/// `.zig_lib`-rooted path renders as `dirs.zig_lib.path orelse "."`. So a graph document's
/// `root` strings are meaningful only relative to the directory the compiler was run from
/// when `-femit-module-graph` fired. Nothing in the document records what that directory
/// was.
///
/// This fork takes the review's second branch -- a documented same-cwd contract with a
/// named refusal -- and NOT the first (a `--graph-base=<dir>` flag), because that would be
/// a new user-visible interface on a rung whose flag surface is still under review, and
/// because it matches the precedent rung 4 sets one rung over: `resolveAsModule` resolves
/// the very same `root` field against this process's cwd and documents the same inherited
/// caveat. The alternative is named as a residual in the packet that lands this, for the
/// desk, rather than decided here.
///
/// THE CONTRACT, stated so an operator can meet it: run `ast-check --check-decls` from the
/// same working directory the graph was emitted from. It is the same requirement a relative
/// `--module-graph=<path>` argument already imposes, made explicit instead of implicit.
///
/// What this function buys beyond the status quo: the base becomes one named value resolved
/// once, so when it cannot be established at all (`getResolvedCwd` fails -- e.g. the cwd was
/// removed out from under the process) the whole `--check-decls` request is refused BY NAME
/// here, instead of every named module silently reporting `target_unreadable` and the
/// operator concluding their graph was wrong when in fact the checker had no base.
pub fn resolveGraphBase(arena: Allocator, io: Io) Allocator.Error!GraphBaseOutcome {
    const cwd = introspect.getResolvedCwd(io, arena) catch |err| return .{ .err = try std.fmt.allocPrint(
        arena,
        "--check-decls cannot resolve module roots: the module graph records each module's root relative to the directory the graph was EMITTED from (Compilation.zig's Path.Formatter/absToCwdRelative), so this process's own working directory is the base they must be joined against -- and it could not be resolved ({t}). Refusing rather than guessing a base, which would report every named module's target as unreadable and blame the graph",
        .{err},
    ) };
    return .{ .ok = cwd };
}

/// Target module/file identified for a named import: the graph's `ModuleNode.root` and
/// `root_src_path`, joined to locate the module's root source file on disk.
const ModuleTarget = struct {
    root: []const u8,
    root_src_path: []const u8,
};

fn targetEqlOpt(a: ?ModuleTarget, b: ?ModuleTarget) bool {
    const av = a orelse return b == null;
    const bv = b orelse return false;
    return mem.eql(u8, av.root, bv.root) and mem.eql(u8, av.root_src_path, bv.root_src_path);
}

/// One public root declaration of a parsed target, enriched from name-only to the shape
/// the arity pass needs (the retained arity dispatch). ALL FOUR SHAPES MEAN THE NAME
/// EXISTS: name-existence behavior is unchanged by this enrichment; only what a direct
/// CALL through the member can honestly compare changes. `exact_fn` carries the fixed
/// syntactic parameter count; the other three are never compared -- see the section
/// comment above `checkDeclExistence`.
const TargetDeclShape = union(enum) {
    /// A syntactic `fn_decl` or body-less `fn_proto*` whose every parameter is ordinary
    /// fixed syntax (`noalias` included -- it names an alias guarantee, not a dynamic
    /// parameter). The payload is the fixed parameter count.
    exact_fn: usize,
    /// Any `comptime` parameter, `anytype`, or `...` variadic marker: the count is not a
    /// fixed syntactic fact. Never compared, never an error.
    dynamic_fn,
    /// A public var/const or other non-function root declaration. It may be
    /// function-valued after Sema; never called non-callable, never compared.
    other_decl,
    /// A duplicate public spelling in this parse-only target. No arity is ever chosen
    /// between duplicates.
    ambiguous_decl,
};

/// A call node whose callee is EXACTLY a member reference -- keyed by that callee
/// (`field_access`) node index, so a member reference that is not itself the callee (the
/// `util.Thing` inside `util.Thing.method(...)`, or an argument expression) carries no
/// entry and never enters the arity population.
const CallSite = struct {
    /// The call node itself: the arity-mismatch diagnostic points here, not at the
    /// member reference.
    call_node: Ast.Node.Index,
    /// `full.Call.ast.params.len`, the argument count as written.
    args_len: usize,
};

/// The outcome of resolving one target file, cached by resolved path so a target referenced
/// by many member accesses is read and parsed at most once.
const TargetOutcome = union(enum) {
    opaque_target,
    /// Covers both "could not be read/opened" and "did not parse cleanly" -- see
    /// `resolveTarget`'s doc comment: both are the plan's "unreadable / unparsable target
    /// file = NAMED error" case. Not distinguishing I/O failure from a syntax-error file
    /// mirrors `loadGraph`'s own established convention above.
    unreadable,
    /// Public root declarations keyed by name, carrying their arity shape. `contains`
    /// is exactly the old name-existence verdict.
    decls: std.StringHashMapUnmanaged(TargetDeclShape),
};

/// Honest denominators for rung 2's TWO summary lines, matching rung 1's `Stats` idiom:
/// the sum of the eight member-reference fields below equals every member reference the
/// rung ATTRIBUTES to an import binding under its supported shapes -- followed (inline,
/// or a const import alias bound *directly* to the `@import` call at root/file scope OR
/// function-local, retained correction 8) or counted as a root-level refusal
/// (`alias_too_deep` for a root `var`/chain binding, `operand_unparsable` for a root
/// binding whose literal does not parse) -- per the rules the section comment above
/// `checkDeclExistence` states. `printDeclSummary` prints that sum as the denominator,
/// computed from the fields rather than tracked separately, so the two can never disagree.
///
/// What the sum is deliberately NOT claimed to be: every import-derived member reference in
/// the file. The exact current split (retained corrections 3 then 8): a function-local
/// `const` bound DIRECTLY to a parseable `@import` is followed exactly like the root
/// alias, because AstGen's sidecar names the exact declaration its use resolved to;
/// every OTHER local/parameter/capture shape -- a function-local `var` from an import,
/// an ordinary or chained local `const`, a function parameter, a capture payload of any
/// form, a nested container's own declaration -- is ignored by rule, not counted
/// (retained correction 3: they were formerly guessed into `alias_too_deep`, which
/// attributed parameter and capture accesses to an import alias of the same spelling
/// they never touched; correction 8 restored the one followable local shape by
/// ownership, and kept this refusal for all the others). Unsupported references are
/// outside this rung's population; the buckets establish what they establish, and
/// nothing more is claimed.
///
/// The five `arity_*` fields are a SEPARATE denominator over a different population:
/// direct calls whose callee is exactly a supported member reference (see the section
/// comment). A called member reference belongs to BOTH populations -- once here as a
/// member ref, once in the arity fields as a call -- and neither population's count feeds
/// the other. `arityTotal()` sums the five, the arity line's denominator, exactly as
/// `total()` serves the member-reference line.
///
/// `pub` because batch mode (`AstCheckBatch.zig`) carries it into `--json` per file and
/// aggregates it into the batch summary, the same way rung 1's `Stats` already rides
/// `import_stats`; its fields keep `Stats`' non-`pub` style since this std.json serializes
/// every declared field, `pub` or not.
pub const DeclStats = struct {
    validated: usize = 0,
    missing: usize = 0,
    opaque_skipped: usize = 0,
    /// Root-level non-followable import bindings only, per the section comment: a
    /// file-scope `var` bound to `@import`, or a file-scope `const` bound to another name
    /// (a chain). Retained correction 3 narrowed this to the root level: the two prior
    /// bodies also folded NON-ROOT spellings in by file-wide name match, which counted a
    /// sibling-scope value, a parameter, or a capture of the same spelling as
    /// import-derived -- false attribution, retired. Retained correction 8 superseded
    /// the blanket "all non-root ignored" for exactly one shape: a function-local const
    /// bound directly to a parseable `@import` is followed and lands in
    /// `validated`/`missing` like the root alias, never here; every other non-root
    /// binding keeps correction 3's refusal -- ignored, no bucket, no diagnostic --
    /// and this counted-refusal bucket itself remains ROOT-ONLY.
    alias_too_deep: usize = 0,
    target_unresolvable: usize = 0,
    /// A target that could not be READ or PARSED is not the same answer as "the declaration
    /// is not there," and folding the two lost the difference between a failed instrument
    /// and a failed program (the integrated WIP body's review finding MAJOR 5). An absent
    /// instrument reports UNKNOWN, never a verdict (doctrine 2). Still an error -- the
    /// requested check could not run -- but counted apart from `missing`, which now means
    /// only what it says.
    target_unreadable: usize = 0,
    /// A member reference through an `@import` whose string literal does not parse (the
    /// integrated WIP body's review finding MINOR 9). Rung 1 counts the import SITE as
    /// `skipped_nonliteral`; this is rung 2's counterpart for the member REFERENCES through
    /// it -- a different denominator over a different population, which is why it is its
    /// own field and not a shared one.
    operand_unparsable: usize = 0,
    exempt: usize = 0,

    // --- direct-call arity (the second population; see the doc comment above) ---
    /// Callee is a supported member reference resolving to an `exact_fn(n)` target and
    /// the call supplies exactly `n` arguments.
    arity_matched: usize = 0,
    /// Callee is a supported member reference resolving to an `exact_fn(n)` target and
    /// the call supplies a different count: the one arity ERROR, diagnosed at the call
    /// node. Additive to the name verdict -- a mismatched call is still name-validated.
    arity_mismatch: usize = 0,
    /// The target declaration is `dynamic_fn` (comptime/anytype/variadic syntax):
    /// counted skipped, never compared, never an error.
    arity_skipped_dynamic: usize = 0,
    /// The target declaration is `other_decl`: syntactically a non-fn declaration that
    /// may be function-valued after Sema. Counted skipped, never called non-callable,
    /// never an error.
    arity_skipped_non_fn: usize = 0,
    /// The call's callee resolved, but no arity verdict exists to report: missing member,
    /// ambiguous declaration, opaque/unreadable/unresolvable target, exempt import,
    /// unparsable operand, or a root-level alias refusal. Counted, never diagnosed --
    /// no arity error where there is no arity fact.
    arity_unavailable: usize = 0,

    pub fn total(s: DeclStats) usize {
        return s.validated + s.missing + s.opaque_skipped + s.alias_too_deep +
            s.target_unresolvable + s.target_unreadable + s.operand_unparsable + s.exempt;
    }

    /// The arity line's denominator: every direct call through a supported member
    /// reference. Deliberately separate from `total()` so the two populations -- member
    /// references and direct calls, which overlap -- can never silently feed each other.
    pub fn arityTotal(s: DeclStats) usize {
        return s.arity_matched + s.arity_mismatch + s.arity_skipped_dynamic +
            s.arity_skipped_non_fn + s.arity_unavailable;
    }
};

/// Entry point for rung 2, called by the single-file driver (`checkAgainstGraph` above) and
/// the batch driver (`AstCheckBatch.checkZigFile`) only when `--check-decls` was given --
/// after that driver ran `rung2FieldGap` and `resolveGraphBase` and refused by name on
/// failure, which is what guards the `.?` unwraps below. `loaded` is the same graph rung 1
/// already loaded; `wip_errors` and `had_error` are shared with rung 1 so both rungs'
/// violations render as one bundle. `pub` and data-collecting (no render, no exit) for the
/// same reason `collectGraphViolations` is: the single, batch and `--json` consumers
/// compose this one owner. See the section comment above for the exact scope and
/// alias/opacity rules.
pub fn checkDeclExistence(
    arena: Allocator,
    io: Io,
    tree: Ast,
    display_path: []const u8,
    checked_dir: []const u8,
    /// The declared base a relative `ModuleNode.root` is joined against -- see
    /// `resolveGraphBase`. Always a resolved absolute directory on a call that got here: the
    /// calling driver refused by name otherwise.
    graph_base: []const u8,
    loaded: LoadedGraph,
    /// Rung 4's binding, threaded in by both calling drivers (retained correction 6) so
    /// named member targets resolve through exactly the bound module's own dependency
    /// table when one exists. `null` -- `--check-decls` given without `--as-module` -- keeps
    /// the graph-wide conservative union, byte-for-behavior the construction this rung has
    /// always had. See the named_targets policy split below.
    binding: ?ModuleBinding,
    /// AstGen's identifier-binding sidecar for this tree (retained correction 8), the
    /// one semantic binding owner's own observations. Threaded by both calling drivers,
    /// which request it from `AstGen.generateWithIdentifierBindings` under exactly the
    /// `--check-decls` flag that gates this function, and only on a tree whose AstGen
    /// pass was clean (a diagnostic ZIR publishes a cleared sidecar, and both drivers
    /// refuse rung 2 on compile errors before reaching here). The walk below consults
    /// it at every member reference whose immediate LHS is an identifier; a fact names
    /// the exact declaration or local AstGen selected, never a file-wide spelling.
    bindings: *const AstGen.IdentifierBindings,
    wip_errors: *ErrorBundle.Wip,
    had_error: *bool,
    stats: *DeclStats,
) !void {
    // Resolve every named import edge to its concrete target module, by stage-0 index
    // (`ModuleDoc.index`, not JSON array position -- doctrine 2, verify rather than
    // assume). WHICH edges resolve is the correction-6 policy split:
    //   * `binding == null`: the GRAPH-WIDE conservative union, rung 1's own semantics --
    //     a name that maps to more than one distinct target across the union cannot be
    //     honestly resolved to one file, so it collapses to `null`, reported at use as
    //     `target_unresolvable` rather than picking one target arbitrarily.
    //   * `binding != null`: exactly the bound module's OWN dependency table
    //     (`ModuleBinding.own_dep_indices`, built by `resolveAsModule` from the matched
    //     module's `deps` alone) -- the same per-module rule rung 4 applies to import
    //     validation one rung over. A name the bound module does not declare, a
    //     null/unresolved index, or a spelling its own table collapsed as conflicting
    //     simply has NO entry in `named_targets`, so it reports the same
    //     `target_unresolvable` outcome at use -- never a graph-wide target, never an
    //     invented `missing`, never an arity mismatch.
    var module_by_index: std.AutoHashMapUnmanaged(usize, ModuleDoc) = .empty;
    for (loaded.modules) |m| try module_by_index.put(arena, m.index.?, m);

    var named_targets: std.StringHashMapUnmanaged(?ModuleTarget) = .empty;
    if (binding) |b| {
        var dep_it = b.own_dep_indices.iterator();
        while (dep_it.next()) |entry| {
            const target: ?ModuleTarget = if (entry.value_ptr.*) |di| dep_blk: {
                const dep_mod = module_by_index.get(di) orelse break :dep_blk null;
                break :dep_blk ModuleTarget{ .root = dep_mod.root.?, .root_src_path = dep_mod.root_src_path.? };
            } else null;
            try named_targets.put(arena, entry.key_ptr.*, target);
        }
    } else {
        for (loaded.modules) |m| {
            for (m.deps) |d| {
                const target: ?ModuleTarget = if (d.dep_index) |di| dep_blk: {
                    const dep_mod = module_by_index.get(di) orelse break :dep_blk null;
                    break :dep_blk ModuleTarget{ .root = dep_mod.root.?, .root_src_path = dep_mod.root_src_path.? };
                } else null;
                const gop = try named_targets.getOrPut(arena, d.import_name);
                if (!gop.found_existing) {
                    gop.value_ptr.* = target;
                } else if (!targetEqlOpt(gop.value_ptr.*, target)) {
                    gop.value_ptr.* = null;
                }
            }
        }
    }

    // --- Pass 1 (retained correction 8): import-provenance classification of the
    // declarations AstGen's sidecar can name, keyed by exact declaration NODE, never
    // by file-wide spelling. Succession note (doctrine 7: quote the retired
    // approach): this pass first collected root bindings into SPELLING-keyed sets
    // (`simple_aliases` / `deep_alias_names` / `unparsable_alias_names`) and the
    // classification walk matched a member reference's LHS against them by name --
    // "collect-then-fixpoint rather than a single linear scan" over
    // `root_bindings: std.StringHashMapUnmanaged(RootBinding)`. That was honest about
    // ROOT bindings (a root decl's spelling IS its scope) but the walk's name match
    // could not tell a use of the root declaration from any other use that merely
    // shared the spelling, and correction 3 had to retire ALL non-root attribution
    // because "there is no binder here ... AstGen's own private Scope map is
    // authoritative while lowering, but it is not exported to this owner." Retained
    // correction 8 exports that owner's own observations: `bindings` facts name the
    // exact declaration node or local token `localVarRef` selected, and this pass
    // classifies exactly those nodes. Two indexes are built here, both
    // inspection-only joins, NOT scope resolution -- the scope walk already happened,
    // in AstGen, at the owner:
    //   * `root_class`: every root var-decl's import-provenance class, so a
    //     `.declaration` fact naming a root node keeps exactly the follow/refusal
    //     behavior the spelling sets used to give it (root counted refusals are
    //     preserved), while a fact naming anything else -- a nested namespace's
    //     declaration, a non-var decl -- simply has no class here and is ignored,
    //     never promoted to root by spelling.
    //   * `var_decl_by_name_token`: every var-decl in the whole tree, keyed by its
    //     unique name token, so a `.local` fact's `declaration_token` can be looked up
    //     and that exact declaration's initializer inspected: only a `const` (category
    //     `local_constant`) directly initialized by a parseable `@import` is newly
    //     followed; every other local shape is a known lexical owner with UNKNOWN
    //     value provenance and is ignored, never attributed by spelling.
    const RootClass = union(enum) {
        /// Root `const` bound directly to a parseable `@import` -- the one
        /// followable root shape, (b) above.
        simple_import: []const u8,
        /// Every other import-derived root flow: a root `var` bound directly to an
        /// import (reassignable, so not shape (b)), or a root `const` chain that
        /// transitively reaches one -- deeper than one hop. Counted refusal at use.
        deep_import,
        /// Bound to an `@import` whose string literal does not parse (review finding
        // MINOR 9, carried over from the integrated body). Import-derived, but its
        // target is unknowable here -- counted `operand_unparsable`, never silently
        // dropped and never guessed.
        unparsable_import,
        /// Not import-derived: ignored at use.
        other,
    };
    var root_class: std.AutoHashMapUnmanaged(Ast.Node.Index, RootClass) = .empty;
    // Root var-decl spellings, for the chain fixpoint below. Root declarations cannot
    // lawfully share a name (AstGen refuses redeclaration, and both drivers only reach
    // here on a clean AstGen pass), so name -> node is exact; a duplicate nevertheless
    // collapses to null here rather than guessing which node a chain refers to.
    var root_var_by_name: std.StringHashMapUnmanaged(?Ast.Node.Index) = .empty;
    {
        for (tree.rootDecls()) |decl| {
            switch (tree.nodeTag(decl)) {
                .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {},
                else => continue,
            }
            const vd = tree.fullVarDecl(decl).?;
            const name = tree.tokenSlice(vd.ast.mut_token + 1);
            const gop = try root_var_by_name.getOrPut(arena, name);
            if (!gop.found_existing) {
                gop.value_ptr.* = decl;
            } else if (gop.value_ptr.* != decl) {
                gop.value_ptr.* = null;
            }
            const is_const = tree.tokenTag(vd.ast.mut_token) == .keyword_const;
            const init_node = vd.ast.init_node.unwrap() orelse continue;
            const class: RootClass = c: {
                switch (try directImportPath(arena, tree, init_node)) {
                    .path => |p| break :c if (is_const)
                        (RootClass{ .simple_import = p })
                    else
                        // `var`, not `const`: reassignable, so not the single-level shape (b)
                        // above documents as followable -- "any other flow" in the section comment.
                        RootClass.deep_import,
                    .operand_unparsable => break :c .unparsable_import,
                    .not_import => {},
                }
                // Not a direct import: an identifier chain is classified by the
                // fixpoint below (still never `simple_import` -- deeper than one hop
                // by construction); anything else is not import-derived.
                break :c .other;
            };
            try root_class.put(arena, decl, class);
        }
        // Fixpoint: a root `const n = m;` is import-derived iff `m` names a root
        // var-decl classified `simple_import` or `deep_import` -- exactly the
        // spelling sets' old transitive rule, now per exact node. It only ever
        // becomes `deep_import`, never `simple_import`.
        var changed = true;
        while (changed) {
            changed = false;
            var it = root_class.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* != .other) continue;
                const vd = tree.fullVarDecl(entry.key_ptr.*) orelse continue;
                const init_node = vd.ast.init_node.unwrap() orelse continue;
                if (tree.nodeTag(init_node) != .identifier) continue;
                const target_name = tree.tokenSlice(tree.nodeMainToken(init_node));
                const target_node = (root_var_by_name.get(target_name) orelse continue) orelse continue;
                switch (root_class.get(target_node) orelse continue) {
                    .simple_import, .deep_import => {
                        entry.value_ptr.* = .deep_import;
                        changed = true;
                    },
                    .unparsable_import, .other => {},
                }
            }
        }
    }

    // Structural index: every var-decl in the tree by its unique NAME token. A
    // `.local` fact carries the token of the declaration AstGen bound the use to;
    // this join looks THAT declaration up so its initializer can be inspected. It
    // is not a scope lookup -- AstGen already selected the binding, and parameters
    // and captures bind with no var-decl node at all, so their tokens simply have
    // no entry here and stay unknown by construction.
    var var_decl_by_name_token: std.AutoHashMapUnmanaged(Ast.TokenIndex, Ast.Node.Index) = .empty;
    {
        var scan_idx: u32 = 0;
        const total: u32 = @intCast(tree.nodes.len);
        while (scan_idx < total) : (scan_idx += 1) {
            const node: Ast.Node.Index = @enumFromInt(scan_idx);
            switch (tree.nodeTag(node)) {
                .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {},
                else => continue,
            }
            const vd = tree.fullVarDecl(node).?;
            try var_decl_by_name_token.put(arena, vd.ast.mut_token + 1, node);
        }
    }

    var target_cache: std.StringHashMapUnmanaged(TargetOutcome) = .empty;

    const node_count: u32 = @intCast(tree.nodes.len);

    // --- Succession note (doctrine 7: quote the retired approach): two earlier bodies of
    // this rung collected non-root bindings in a second pass here. The first folded every
    // local name bound to `@import` into the FILE-GLOBAL root sets and counted every
    // same-spelling field access anywhere as `alias_too_deep`/`operand_unparsable` -- so a
    // sibling-scope value, a function parameter, or a capture payload that merely shared a
    // spelling with a local import alias was attributed to an import it never touched. The
    // second added per-name local sets and an `alias_name_conflict` bucket to refuse
    // collided var-decl spellings -- but parameters and captures bind with NO var-decl
    // node, so their accesses were still falsely counted; and adding their spellings to yet
    // another file-wide set is the same defect wearing a different bucket: a file-wide
    // spelling blacklist is not lexical ownership, whichever bucket it feeds. Retained
    // correction 3 then refused to attribute non-root shapes AT ALL, stating: "There is no
    // lexical-owner map at this owner -- AstGen's private Scope is authoritative while
    // lowering but does not reach here -- so the only honest options were a complete
    // binder (a rung's worth of work; a partial one is a guess with more steps) or refusing
    // to attribute non-root shapes AT ALL," and took the refusal. Retained correction 8
    // ends that stance the only way it could honestly end: not a consumer-side binder, but
    // the owner exporting its own decisions -- `localVarRef` records the exact binding it
    // selects into the opt-in sidecar threaded into this function, and the classification
    // above consumes facts, never spellings. That newly supports exactly ONE local shape,
    // the `const` directly initialized by a parseable `@import` (authoritative for the
    // same reason the root shape (b) is: the same lexical resolver names the exact
    // declaration and its initializer is the supported syntactic import shape). Every
    // other non-root shape keeps correction 3's refusal verbatim: parameters and captures
    // still bind with no var-decl node, and known lexical ownership is still not known
    // value provenance. The retired file-global name sets are gone; nothing here consults
    // a spelling across scopes.

    // --- Call pre-scan (the arity pass's population, per the section comment): every call
    // node whose callee is EXACTLY a `field_access`, keyed by that callee node. Keying by
    // the CALLEE is what keeps the population honest: the `util.Thing` inside
    // `util.Thing.method(...)` is nobody's callee, an argument expression is nobody's
    // callee, and neither enters the arity denominator. `fullCall` covers the same four
    // call tags AstGen itself lowers (`callExpr`, lib/std/zig/AstGen.zig), so the scanned
    // population is the compiler's own call population, read parse-only.
    var call_sites: std.AutoHashMapUnmanaged(Ast.Node.Index, CallSite) = .empty;
    {
        var scan_idx: u32 = 0;
        while (scan_idx < node_count) : (scan_idx += 1) {
            const node: Ast.Node.Index = @enumFromInt(scan_idx);
            var call_buf: [1]Ast.Node.Index = undefined;
            const call = tree.fullCall(&call_buf, node) orelse continue;
            if (tree.nodeTag(call.ast.fn_expr) != .field_access) continue;
            try call_sites.put(arena, call.ast.fn_expr, .{ .call_node = node, .args_len = call.ast.params.len });
        }
    }

    // --- Classification: every `field_access` node, per the section comment above. One
    // walk, no binding pre-pass: the only followable bindings are the ROOT ones pass 1
    // already resolved, every non-root shape is ignored by rule (see the succession note
    // above), and so there is nothing a pre-pass could collect that this needs. The call
    // pre-scan above is not a binding pass -- it records SYNTAX facts (which field access
    // is a callee, how many arguments it was given), never an ownership claim.
    var node_idx: u32 = 0;
    while (node_idx < node_count) : (node_idx += 1) {
        const node: Ast.Node.Index = @enumFromInt(node_idx);
        if (tree.nodeTag(node) != .field_access) continue;
        const lhs, const member_tok = tree.nodeData(node).node_and_token;
        const member_name = tree.tokenSlice(member_tok);

        switch (try directImportPath(arena, tree, lhs)) {
            .path => |import_path| {
                try classifyMemberRef(arena, io, tree, display_path, checked_dir, graph_base, &named_targets, &target_cache, &call_sites, wip_errors, had_error, stats, import_path, member_name, node);
                continue;
            },
            // Shape (a) on an import whose operand does not parse: the reference IS
            // import-derived, so it belongs in the denominator -- in its own bucket, not
            // dropped (review finding MINOR 9). A direct call through it has no arity
            // fact to report either, so a callee here counts `arity_unavailable`, never a
            // guessed count.
            .operand_unparsable => {
                stats.operand_unparsable += 1;
                if (call_sites.get(node) != null) stats.arity_unavailable += 1;
                continue;
            },
            .not_import => {},
        }
        if (tree.nodeTag(lhs) == .identifier) {
            // Fact-keyed lexical ownership (retained correction 8): the LHS
            // identifier's binding is whatever AstGen's `localVarRef` resolved it to
            // at this exact use node -- the fact names the exact declaration node or
            // local declaration token that owns the use, never a file-wide spelling
            // match. A fact ABSENT from the sidecar means unknown/not observed (a
            // primitive or builtin early return, or a node this lowering never
            // resolved); `unavailable` is the sidecar's own conflict refusal. Both are
            // ignored here, as two distinct facts with the same honest treatment.
            if (bindings.get(lhs)) |fact| switch (fact) {
                .declaration => |decl_node| {
                    // A declaration AstGen selected. Only a ROOT var-decl has an
                    // import-provenance class in `root_class`; a nested namespace's
                    // declaration (a container inside a function, or a container
                    // member) or any non-var decl falls to the ignore arm -- never
                    // promoted to root by spelling.
                    switch (root_class.get(decl_node) orelse continue) {
                        .simple_import => |import_path| {
                            try classifyMemberRef(arena, io, tree, display_path, checked_dir, graph_base, &named_targets, &target_cache, &call_sites, wip_errors, had_error, stats, import_path, member_name, node);
                        },
                        .deep_import => {
                            // A root-level refusal still reaches the arity population
                            // when it is a callee: the call exists, but no target shape
                            // exists to compare against -- `arity_unavailable`, the
                            // same no-guessing rule the member side already follows.
                            stats.alias_too_deep += 1;
                            if (call_sites.get(node) != null) stats.arity_unavailable += 1;
                        },
                        .unparsable_import => {
                            stats.operand_unparsable += 1;
                            if (call_sites.get(node) != null) stats.arity_unavailable += 1;
                        },
                        .other => {},
                    }
                },
                .local => |loc| {
                    // A local binding AstGen selected. Exactly one shape is
                    // followable (newly supported by retained correction 8):
                    // category `local_constant` -- so not a parameter, a mutable
                    // local, or a capture, all known lexical owners whose VALUE
                    // provenance is unknowable here without types or dataflow --
                    // whose exact declaration, found by its unique name token, is a
                    // `const` directly initialized by a parseable `@import`. Every
                    // other local shape is ignored: no bucket, no diagnostic, no
                    // arity verdict, never an attribution by spelling.
                    if (loc.category != .local_constant) continue;
                    if (var_decl_by_name_token.get(loc.declaration_token)) |decl_node| {
                        const vd = tree.fullVarDecl(decl_node) orelse continue;
                        if (tree.tokenTag(vd.ast.mut_token) != .keyword_const) continue;
                        const init_node = vd.ast.init_node.unwrap() orelse continue;
                        switch (try directImportPath(arena, tree, init_node)) {
                            .path => |import_path| {
                                try classifyMemberRef(arena, io, tree, display_path, checked_dir, graph_base, &named_targets, &target_cache, &call_sites, wip_errors, had_error, stats, import_path, member_name, node);
                            },
                            // Import-derived but unknowable: the counted refusal the
                            // root shape already had, on the local shape too.
                            .operand_unparsable => {
                                stats.operand_unparsable += 1;
                                if (call_sites.get(node) != null) stats.arity_unavailable += 1;
                            },
                            // An ordinary local const, or a local alias chain: not a
                            // direct import -- ignored.
                            .not_import => {},
                        }
                    }
                },
                .unavailable => {},
            };
        }
        // Not one of the supported shapes: either an ordinary field access unrelated
        // to any import, or a reference through an UNSUPPORTED binding shape -- a
        // parameter, a capture, an ordinary or mutable or chained local, a nested
        // namespace's own declaration, or the second hop of a chain like
        // `m.sub.foo` (whose first hop WAS classified). None of these is counted in
        // any bucket and none produces a diagnostic: an unsupported shape is
        // ignored honestly, never guessed import-derived (retained correction 3,
        // its refusal boundary kept by retained correction 8 for every shape
        // except the one followable local const import).
    }

    // Proof debt this correction leaves OPEN, named rather than hidden (retained
    // corrections 3 and 8): the unsupported shapes above are ignored, which stops the
    // false attribution but does not make this rung see them. Retained correction 8
    // retired the "no lexical-owner mechanism" premise -- AstGen now exports its own
    // partial authoritative binding facts, so the sidecar states exactly which
    // declaration, parameter, capture, or local owns each spelling -- and that
    // authority is what follows the one function-local direct-const import. What the
    // facts do NOT carry is VALUE provenance: whether a parameter, capture, ordinary,
    // mutable, or chained local actually holds a module value is a types/dataflow
    // question, outside this rung's "no types, no comptime" charter; a nested
    // namespace's own declaration and the second hop of a chain are the same refusal;
    // and absent/unavailable facts stay unknown by construction. Those are the actual
    // remaining dependencies, not a missing binder. The proof set exercises the
    // ignored families by ownership now -- the sibling-scope plain-value collision and
    // the `m: anytype` parameter (C9P2-33/34), the one exercised `if (<optional>) |m|`
    // capture beside its import namesake (C9P2-35), the ordinary/mutable/chained
    // locals (C9P2-47), the if/while/for/pointer capture forms (C9P2-48), the switch
    // payload/tag and catch/error/errdefer captures (C9P2-49), the two-sibling
    // different-target locals (C9P2-46), and the nested-declaration versus
    // closure-tunneled-root pair (C9P2-50) -- every one UNEXECUTED, so nothing here
    // generalizes beyond them and none of this is a completeness claim.
}

/// What `directImportPath` found at a node. Three outcomes, not two (the integrated WIP
/// body's review finding MINOR 9): `not_import` and `operand_unparsable` were previously
/// both spelled `null`, so a reference through an `@import` whose string literal did not
/// parse was indistinguishable from an ordinary field access and fell into NO bucket at all
/// -- silent, where rung 1 counts the very same site as `skipped_nonliteral`. Rung 2 now
/// has its own counterpart.
const DirectImport = union(enum) {
    /// The node is not an `@import("<literal>")` call at all.
    not_import,
    /// The node IS `@import(<string literal>)`, but the literal does not parse (a malformed
    /// escape sequence, which a real compile diagnoses via AstGen). The import exists; its
    /// path is unknowable here. Never guessed, never silently dropped -- counted.
    operand_unparsable,
    path: []const u8,
};

/// If `node` is exactly `@import("literal")`, returns the parsed import path. A small,
/// standalone counterpart to rung 1's own inline `@import`-node parsing (embedded in
/// `collectGraphViolations`' walk, where extracting a shared helper would cost more churn
/// than it saves) -- kept deliberately separate per minimal-hunks.
fn directImportPath(arena: Allocator, tree: Ast, node: Ast.Node.Index) Allocator.Error!DirectImport {
    switch (tree.nodeTag(node)) {
        .builtin_call, .builtin_call_comma, .builtin_call_two, .builtin_call_two_comma => {},
        else => return .not_import,
    }
    const builtin_token = tree.nodeMainToken(node);
    if (!mem.eql(u8, tree.tokenSlice(builtin_token), "@import")) return .not_import;

    var params_buf: [2]Ast.Node.Index = undefined;
    const params = tree.builtinCallParams(&params_buf, node) orelse return .not_import;
    if (params.len != 1) return .not_import;
    const operand = params[0];
    if (tree.nodeTag(operand) != .string_literal) return .not_import;

    const str_token = tree.nodeMainToken(operand);
    const raw = tree.tokenSlice(str_token);
    // `parseAlloc` fails only on a malformed escape; `error.OutOfMemory` must NOT be
    // laundered into "unparsable operand", so the two are separated here rather than both
    // swallowed by one `catch` (which is what the integrated body's `catch null` did).
    return if (std.zig.string_literal.parseAlloc(arena, raw)) |p| .{ .path = p } else |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidLiteral => .operand_unparsable,
    };
}

/// Resolves one member reference (`import_path`.`member_name`, referenced at `ref_node` in
/// the checked file) into its bucket in `stats`, resolving and (via `target_cache`) caching
/// the target file at most once regardless of how many member references land on it. When
/// `ref_node` is the exact callee of a direct call (`call_sites`, the arity population),
/// this ALSO records exactly one secondary arity outcome, independent of the primary name
/// bucket: the two populations are counted separately per `DeclStats`' doc comment.
fn classifyMemberRef(
    arena: Allocator,
    io: Io,
    tree: Ast,
    display_path: []const u8,
    checked_dir: []const u8,
    /// See `resolveGraphBase`.
    graph_base: []const u8,
    named_targets: *const std.StringHashMapUnmanaged(?ModuleTarget),
    target_cache: *std.StringHashMapUnmanaged(TargetOutcome),
    /// The arity population: callee `field_access` node -> call facts. `ref_node` is a
    /// member of this map exactly when the reference is itself a direct callee.
    call_sites: *const std.AutoHashMapUnmanaged(Ast.Node.Index, CallSite),
    wip: *ErrorBundle.Wip,
    had_error: *bool,
    stats: *DeclStats,
    import_path: []const u8,
    member_name: []const u8,
    ref_node: Ast.Node.Index,
) !void {
    const call_site = call_sites.get(ref_node);

    // std/builtin/root: exempt, exactly as rung 1 treats them -- nothing in the graph to
    // resolve them against (see `EmitModuleGraph.zig`'s `DepEdge` doc comment). A direct
    // call into them has no graph-resolved target shape to compare -- unavailable, never
    // guessed.
    if (mem.eql(u8, import_path, "std") or mem.eql(u8, import_path, "builtin") or mem.eql(u8, import_path, "root")) {
        stats.exempt += 1;
        if (call_site != null) stats.arity_unavailable += 1;
        return;
    }

    // The FILE-IMPORT branch goes through `resolveImportPath` -- the ONE resolution seam
    // rung 1's existence check and rung 4's sandbox check already consume -- so rung 2
    // locates a file target exactly the way rung 1 does. The first integration of this
    // rung used a bare `std.fs.path.join` here (senior review BLOCKER on that delivery):
    // `join` does not reset on an absolute component, so an absolute operand was resolved
    // to a path INSIDE the checked file's directory -- the exact failure the seam exists
    // to fix, reintroduced one call site away from the fix.
    const resolved_path: []const u8 = if (isFileImport(import_path))
        try resolveImportPath(arena, checked_dir, import_path)
    else named_blk: {
        const mt = (named_targets.get(import_path) orelse null) orelse {
            // Not resolvable to one concrete module node -- see `checkDeclExistence`'s doc
            // comment for when a name collapses to null (two modules disagree about what it
            // points at, or stage 0 recorded no `dep_index` for it), and, under a
            // correction-6 binding, the bound module's own table does not carry the name
            // or carries it unresolved. Refused either way -- never a graph-wide target
            // picked, never an invented `missing`.
            //
            // An earlier body's comment here claimed rung 1 "would have exited before rung
            // 2 ever ran," so an unregistered name could not reach here. FALSE, and the
            // integrated body's review finding MODERATE 6 caught it: the drivers collect
            // rung 1's violations into a shared `ErrorBundle.Wip`, then run rung 2 into the
            // SAME bundle, and only render and `process.exit(1)` after both. That is
            // deliberate -- one invocation should report both rungs' findings, not make the
            // operator run twice -- but it means rung 2 does see names rung 1 rejected, and
            // the count below must be correct on its own rather than by appeal to an exit
            // that has not happened yet. A comment asserting control flow the code does not
            // have is worse than no comment: it is a false proof (doctrine 7).
            stats.target_unresolvable += 1;
            if (call_site != null) stats.arity_unavailable += 1;
            return;
        };
        // Joined against the DECLARED base, not against whatever cwd the later `openFile`
        // would have inherited (review finding MAJOR 4). `mt.root` is meaningful only
        // relative to the directory the graph was emitted from; `graph_base` is this
        // process's resolved cwd, established and refused-by-name once by the calling
        // driver. An already-absolute `root` is used as-is -- `std.fs.path.resolve` resets
        // on an absolute component, unlike `join`, which does not.
        break :named_blk try std.fs.path.resolve(arena, &.{ graph_base, mt.root, mt.root_src_path });
    };

    const outcome = target_cache.get(resolved_path) orelse resolve_blk: {
        // `isZonPath`, not a second inline spelling of the extension rule (the integrated
        // body's review finding MINOR 8) -- one rule, one place, so rung 1's classification
        // and rung 2's opacity decision can never disagree about what a ZON file is.
        const computed = try resolveTarget(arena, io, resolved_path, isZonPath(resolved_path));
        try target_cache.put(arena, resolved_path, computed);
        break :resolve_blk computed;
    };

    switch (outcome) {
        .opaque_target => {
            stats.opaque_skipped += 1;
            if (call_site != null) stats.arity_unavailable += 1;
        },
        .unreadable => {
            had_error.* = true;
            try addImportError(wip, tree, display_path, ref_node, "cannot check member '{s}': target file '{s}' could not be read or parsed as Zig source -- the check was requested and cannot honestly pass (if this is a NAMED module: the graph records module roots relative to the directory -femit-module-graph ran in, so --check-decls must run from that same directory; this run resolved against base '{s}')", .{ member_name, resolved_path, graph_base });
            // `target_unreadable`, NOT `missing` (review finding MAJOR 5). Both are errors,
            // but they are different facts: `missing` says the compiler will reject this
            // program, `target_unreadable` says this checker could not look. Folding the
            // second into the first told the operator we had checked when we had not.
            stats.target_unreadable += 1;
            if (call_site != null) stats.arity_unavailable += 1;
        },
        .decls => |shapes| {
            if (shapes.get(member_name)) |shape| {
                // The member exists: the name verdict is VALIDATED regardless of shape
                // (all four shapes mean the name exists -- `TargetDeclShape`'s doc
                // comment). The arity verdict is the separate, shape-driven outcome.
                stats.validated += 1;
                if (call_site) |cs| try recordCallArity(wip, tree, display_path, had_error, stats, shape, member_name, resolved_path, cs);
            } else {
                had_error.* = true;
                try addImportError(wip, tree, display_path, ref_node, "referenced declaration not found: '{s}' is not a public top-level declaration of '{s}'", .{ member_name, resolved_path });
                stats.missing += 1;
                // No arity fact exists for a name that is not there: counted unavailable,
                // never a mismatch -- the missing diagnostic is the error, and stacking
                // an arity guess on top of it would claim a shape was known.
                if (call_site != null) stats.arity_unavailable += 1;
            }
        },
    }
}

/// Records the secondary arity outcome for one direct call whose callee is a supported
/// member reference that name-validated against a target shape (the caller has already
/// counted the primary bucket). Exactly one bucket per call; the ONLY arity error is
/// `arity_mismatch`, diagnosed at the call node -- every shape that is not an
/// `exact_fn` comparison is a counted skip, never an error (the section comment above
/// `checkDeclExistence` states the no-guessing boundary in full).
fn recordCallArity(
    wip: *ErrorBundle.Wip,
    tree: Ast,
    display_path: []const u8,
    had_error: *bool,
    stats: *DeclStats,
    shape: TargetDeclShape,
    member_name: []const u8,
    resolved_path: []const u8,
    call_site: CallSite,
) !void {
    switch (shape) {
        .exact_fn => |fixed| if (fixed == call_site.args_len) {
            stats.arity_matched += 1;
        } else {
            had_error.* = true;
            // Syntactic shape only, worded so: no types, no comptime, no implicit
            // receiver is assumed or claimed known, and no Sema parity is implied --
            // the compiler's `checkCallArgumentCount` answers all of those with types.
            try addImportError(wip, tree, display_path, call_site.call_node, "direct call argument-count mismatch: member '{s}' of '{s}' declares {d} fixed syntactic parameter(s) (shape only -- no types, no comptime, no implicit receiver), but this call supplies {d} argument(s)", .{ member_name, resolved_path, fixed, call_site.args_len });
            stats.arity_mismatch += 1;
        },
        .dynamic_fn => stats.arity_skipped_dynamic += 1,
        .other_decl => stats.arity_skipped_non_fn += 1,
        .ambiguous_decl => stats.arity_unavailable += 1,
    }
}

/// The arity shape of one parsed function declaration: `exact_fn(n)` when every parameter
/// is ordinary fixed syntax (`noalias` included -- it names an alias guarantee, not a
/// dynamic parameter, so it stays fixed and countable), `dynamic_fn` at the FIRST parameter
/// this rung cannot honestly count (`comptime`, `anytype`, or the `...` variadic marker) --
/// never a partial count from the parameters seen so far, so no caller can fire a
/// comparison on half a generic signature. `FnProto.Iterator` is used precisely because it
/// abstracts what `fullFnProto`'s params slice cannot see: `anytype` and `...` are not
/// sub-expressions and never appear in that slice.
fn fnProtoShape(tree: *const Ast, proto: *const Ast.full.FnProto) TargetDeclShape {
    var fixed: usize = 0;
    var it = proto.iterate(tree);
    while (it.next()) |param| {
        if (param.anytype_ellipsis3 != null) return .dynamic_fn;
        if (param.comptime_noalias) |tok| {
            // One field carries BOTH keywords (`Param.comptime_noalias`); only `comptime`
            // makes the parameter un-countable. `noalias` stays fixed.
            if (tree.tokenTag(tok) == .keyword_comptime) return .dynamic_fn;
        }
        fixed += 1;
    }
    return .{ .exact_fn = fixed };
}

/// Reads and parses `resolved_path` (unless `is_zon`, which is opaque by construction: ZON
/// is data, not Zig declarations) and returns its public top-level declarations with their
/// arity shapes (`TargetDeclShape`; `contains` on the map is exactly the old name-only
/// verdict), or `.opaque_target` if a `comptime` block sits at its top level (name-level
/// analysis cannot see through it -- see the section comment above `checkDeclExistence`),
/// or `.unreadable` if it cannot be opened, read, or parsed without errors.
fn resolveTarget(arena: Allocator, io: Io, resolved_path: []const u8, is_zon: bool) !TargetOutcome {
    if (is_zon) return .opaque_target;

    var f = Io.Dir.cwd().openFile(io, resolved_path, .{}) catch return .unreadable;
    defer f.close(io);
    var read_buffer: [4096]u8 = undefined;
    var file_reader: Io.File.Reader = f.reader(io, &read_buffer);
    const source = std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch return .unreadable;
    const tree = Ast.parse(arena, source, .zig) catch return .unreadable;
    if (tree.errors.len != 0) return .unreadable;

    for (tree.rootDecls()) |decl| {
        if (tree.nodeTag(decl) == .@"comptime") return .opaque_target;
    }

    var shapes: std.StringHashMapUnmanaged(TargetDeclShape) = .empty;
    for (tree.rootDecls()) |decl| {
        switch (tree.nodeTag(decl)) {
            // `.fn_decl` is a function WITH a body. A body-less prototype -- `pub extern fn
            // malloc(...) ?*anyopaque;`, `pub extern "c" fn free(...) void;` -- never wears
            // that tag; the parser gives it `fn_proto_simple`/`_multi`/`_one`/`fn_proto`
            // directly, with no `fn_decl` wrapper. Collecting only `.fn_decl` therefore
            // drops every prototype from the target's public surface and reports each legal
            // reference to one as a MISSING declaration -- the exact false positive this
            // rung exists to not produce (the integrated body's review finding BLOCKER 1,
            // the no-guessing gate).
            //
            // Measured on this fork's tree with std.zig.Ast (the same parser this
            // production path uses -- doctrine 5, parse don't grep; the measurement is
            // inherited from the integrated body, whose census corrected the review's own
            // 566 figure): lib/std alone holds 676 public root `fn_proto*` decls across 15
            // of 550 files, against 10,351 collected before this fix and 11,027 after.
            //
            // `fullFnProto` accepts all five tags, so the two arms differ only in which
            // tags reach them; the body of the collection is identical, which is why they
            // are one arm here rather than two.
            .fn_decl, .fn_proto, .fn_proto_simple, .fn_proto_multi, .fn_proto_one => {
                var buf: [1]Ast.Node.Index = undefined;
                const proto = tree.fullFnProto(&buf, decl).?;
                if (proto.visib_token != null) {
                    if (proto.name_token) |nt| {
                        const gop = try shapes.getOrPut(arena, tree.tokenSlice(nt));
                        // A duplicate public spelling: parse-only, no body is ever chosen
                        // between, so no arity is either -- collapse to `ambiguous_decl`,
                        // which the arity pass counts unavailable. Name existence is
                        // unaffected: the spelling is in the map either way.
                        gop.value_ptr.* = if (gop.found_existing) .ambiguous_decl else fnProtoShape(&tree, &proto);
                    }
                }
            },
            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {
                const vd = tree.fullVarDecl(decl).?;
                if (vd.visib_token != null) {
                    // A public var/const: `other_decl` -- syntactically not a function
                    // declaration, but it MAY be function-valued after Sema, so the arity
                    // pass counts it skipped and never calls it non-callable.
                    const gop = try shapes.getOrPut(arena, tree.tokenSlice(vd.ast.mut_token + 1));
                    gop.value_ptr.* = if (gop.found_existing) .ambiguous_decl else .other_decl;
                }
            },
            else => {},
        }
    }
    return .{ .decls = shapes };
}

/// Rung 2's TWO summary lines, matching rung 1's `printSummary` idiom (doctrine 4,
/// self-report): printed whenever `--check-decls` was requested, pass or fail. `pub` since
/// batch mode (`AstCheckBatch.zig`) reuses it verbatim for each decl-checked file in a
/// batch's human-readable output, passing its own file path as `path_prefix` for the same
/// attribution reason rung-3 review item 6 established for rung 1's line; the single-file
/// driver passes `null`. The SECOND line is the arity population's own honest denominator,
/// ending in the syntax boundary (not the retired "arity: DEFERRED") so an operator never
/// has to infer what was compared -- see the section comment above `checkDeclExistence`.
pub fn printDeclSummary(io: Io, stats: DeclStats, path_prefix: ?[]const u8) !void {
    var buffer: [512]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
    if (path_prefix) |p| try w.print("{s}: ", .{p});
    try w.print(
        "member refs seen {d}: validated {d}, missing {d}, opaque-skipped {d}, alias-too-deep {d}, target-unresolvable {d}, target-unreadable {d}, operand-unparsable {d}, exempt {d}\n",
        .{
            stats.total(),
            stats.validated,
            stats.missing,
            stats.opaque_skipped,
            stats.alias_too_deep,
            stats.target_unresolvable,
            stats.target_unreadable,
            stats.operand_unparsable,
            stats.exempt,
        },
    );
    if (path_prefix) |p| try w.print("{s}: ", .{p});
    try w.print(
        "direct calls seen {d}: arity-matched {d}, arity-mismatch {d}, arity-skipped-dynamic {d}, arity-skipped-non-fn {d}, arity-unavailable {d}; arity: syntactic fixed-parameter counts only -- no types, no comptime, no implicit receiver\n",
        .{
            stats.arityTotal(),
            stats.arity_matched,
            stats.arity_mismatch,
            stats.arity_skipped_dynamic,
            stats.arity_skipped_non_fn,
            stats.arity_unavailable,
        },
    );
    try w.flush();
}
