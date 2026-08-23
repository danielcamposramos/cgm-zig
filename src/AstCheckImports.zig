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
//!
//! Stage 0.5 rung 4 (`docs/crown/PLAN.md`, "Stage 0.5" item 4): check-as-module. `--as-
//! module=<fully_qualified_name-or-index>` (parsed in `main.zig`, valid only alongside
//! `--module-graph`) binds the checked file to exactly one `ModuleNode` from the graph via
//! `resolveAsModule` below, producing a `ModuleBinding` that upgrades two of this file's
//! checks from rung 1's advisory, graph-wide semantics to the compiler's own strict,
//! per-module semantics: named imports are checked against that module's own `deps[].
//! import_name` set (not the union every other module contributes to), and file imports
//! (`.zig`/`.zon`) are additionally sandbox-checked against the module's own root directory.
//! Absent `--as-module`, `binding` below is `null` everywhere and both checks fall back to
//! rung 1's original union/no-sandbox behavior byte-for-byte -- see
//! `collectGraphViolations`.
//!
//! THE SANDBOX CHECK IS A CHOSEN STRICTNESS, NOT PARITY WITH THE COMPILER (review finding
//! V7). The head commit cited `Package/Module.zig`'s doc comment ("Only files inside this
//! directory can be imported") as though the compiler enforced it for `@import`. It does
//! not, verified in this tree: `Zcu/PerThread.zig`'s `discoverImport` (the `@import` path)
//! calls `upJoin` and performs no containment check at all, and the only
//! `error.ImportOutsideModulePath` in the tree is raised inside `pub fn embedFile`
//! (`Zcu/PerThread.zig:2881`, surfaced at `Sema.zig:13063`) -- i.e. `@embedFile` alone
//! refuses an outside-package path. So `--as-module` can and will reject an `@import` that
//! builds today. That is defensible as a pre-build discipline -- Module.zig's line is the
//! documented intent, and a hyper-modular estate wants it enforced -- but it is a
//! divergence, and the flag says so in its own help text and in the violation it emits,
//! rather than implying a rule the compiler already applies.

const std = @import("std");
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const Io = std.Io;
const Ast = std.zig.Ast;
const Color = std.zig.Color;
const ErrorBundle = std.zig.ErrorBundle;
const fatal = std.process.fatal;
const introspect = @import("introspect.zig");

/// The subset of `Compilation/EmitModuleGraph.zig`'s `Graph` schema that rung 1 reads.
/// Deliberately not the full schema: `std.json`'s default `ignore_unknown_fields = false`
/// would otherwise reject every other field that schema emits (`index`,
/// `fully_qualified_name`, `root`, `root_src_path`, `optimize_mode`, `strip`,
/// `single_threaded`, `code_model`, `dep_index`, `dep_fully_qualified_name`); we instead
/// pass `.ignore_unknown_fields = true` and only declare what we use.
const GraphDoc = struct {
    modules: []const ModuleDoc,
    roots: []const RootDoc,
};
const ModuleDoc = struct {
    /// Rung 4 fields (docs/crown/PLAN.md, "Stage 0.5" item 4): read only by
    /// `resolveAsModule` below -- rung 1's/rung 3's own walk never touches them. Free to
    /// decode alongside `deps`: `std.json` fills every declared field from the one
    /// document already being parsed, not a second read of `graph_path`.
    index: usize,
    fully_qualified_name: []const u8,
    root: []const u8,
    deps: []const DepDoc,
};
const DepDoc = struct {
    import_name: []const u8,
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
    /// Rung 4, review finding V4: a file-import site whose containment in the bound
    /// module's root could not be DETERMINED -- distinct from one determined to be outside
    /// (that is an error and stays in `file_imports`, because it was checked) and distinct
    /// from one checked clean. It was previously folded into `file_imports` and therefore
    /// into the summary's "validated" figure, which claimed a check that had not happened.
    ///
    /// Always zero without `--as-module`, so rung 1's and rung 3's own runs are unaffected;
    /// defaulted so the `--json` `import_stats` object gains the field additively.
    sandbox_unresolvable: usize = 0,

    /// Every `@import` site walked lands in exactly one field above; this is the
    /// denominator `printSummary` prints, computed from them so the two cannot drift.
    pub fn total(s: Stats) usize {
        return s.file_imports + s.named_imports + s.exempt + s.skipped_nonliteral + s.sandbox_unresolvable;
    }
};

/// The graph-derived lookup table `collectGraphViolations` checks names against. Split out
/// from `checkAgainstGraph` (see this file's top comment) so a rung-3 batch run loads and
/// builds this once, not once per file -- the graph document is invariant across an entire
/// `--module-graph=... f1.zig f2.zig ...` invocation.
pub const LoadedGraph = struct {
    /// Defaulted per rung-3 review item 7: a public type crossing a module boundary should
    /// stay forward compatible without forcing every construction site to name every field.
    allowed_names: std.StringHashMapUnmanaged(void) = .empty,
    /// Rung 4: the full per-module list, read only by `resolveAsModule` (rung 1's/rung 3's
    /// own `collectGraphViolations` walk never reads this). Defaulted empty for the same
    /// forward-compat reason as `allowed_names` above.
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
pub fn checkAgainstGraph(
    arena: Allocator,
    io: Io,
    tree: Ast,
    zig_source_path: []const u8,
    display_path: []const u8,
    graph_path: []const u8,
    as_module_spec: ?[]const u8,
    color: Color,
) !void {
    const loaded = try loadAllowedNames(arena, io, graph_path);

    // Crown stage 0.5 rung 4: resolved once, mirroring `loaded` immediately above --
    // `fatal` here has the same shape and precedent as an unopenable graph document
    // (doctrine 2: the requested check could not run at all). `as_module_spec` is null
    // whenever the operator did not pass `--as-module`, so `binding` stays null and
    // `collectGraphViolations` below falls back to rung 1's original behavior untouched.
    const binding: ?ModuleBinding = if (as_module_spec) |spec|
        switch (try resolveAsModule(arena, io, loaded, spec)) {
            .ok => |b| b,
            .err => |msg| fatal("{s}", .{msg}),
        }
    else
        null;

    var wip_errors: ErrorBundle.Wip = undefined;
    try wip_errors.init(arena);
    const result = try collectGraphViolations(arena, io, tree, zig_source_path, display_path, loaded, binding, &wip_errors);

    if (result.had_error) {
        var eb = try wip_errors.toOwnedBundle("");
        try eb.renderToStderr(io, .{}, color);
    }

    try printSummary(io, result.stats, null, binding);

    if (result.had_error) process.exit(1);
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

// --- Crown stage 0.5 rung 4: --as-module resolution (docs/crown/PLAN.md, "Stage 0.5" item 4) ---

/// The result of successfully binding `--as-module` to one graph node: everything
/// `collectGraphViolations` needs to apply rung 4's strict, per-module semantics instead of
/// rung 1's graph-wide union. Built once per invocation by `resolveAsModule` (single-file:
/// once in `checkAgainstGraph`; batch: once in `AstCheckBatch.run`, reused across every
/// `.zig` member per this rung's own "one --as-module binds ALL .zig members" scope) and
/// reused unchanged across every `@import` site it validates.
pub const ModuleBinding = struct {
    /// `ModuleNode.index` of the bound module, carried through for error messages.
    index: usize = 0,
    fully_qualified_name: []const u8 = "",
    /// Rung 4's strict named-import lookup: exactly the bound module's own `deps[].
    /// import_name` set -- the compiler's real resolution rule (`Package.Module.deps` is
    /// per-module, not shared graph-wide, unlike rung 1's `LoadedGraph.allowed_names`
    /// union). Defaulted per this file's established forward-compat convention.
    own_names: std.StringHashMapUnmanaged(void) = .empty,
    /// The bound module's root directory (`Package/Module.zig`'s sandbox boundary),
    /// resolved to an absolute, lexically-normalized path -- the base every file-import
    /// site is prefix-compared against in `sandboxCheck`. Always valid on a successfully
    /// constructed `ModuleBinding`: an unresolvable root refuses the whole `--as-module`
    /// request at `resolveAsModule` time instead of being carried as an optional here (see
    /// that function's doc comment).
    root_abs: []const u8 = "",
    /// The current process's cwd, resolved once for the whole invocation and reused by
    /// every per-file `sandboxCheck` call rather than re-fetched per file. Null iff
    /// `introspect.getResolvedCwd` failed *and* `root_abs` did not itself need it (i.e. the
    /// graph's `root` was already absolute) -- carried through so a per-file sandbox check
    /// that turns out to need it (the checked file's own resolved import path is relative)
    /// can fail closed on that one site instead of guessing.
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
/// spelling fall back to a `ModuleNode.index` lookup -- `fully_qualified_name` is documented
/// convention, not guaranteed-unique identity (`EmitModuleGraph.zig`'s `ModuleNode.index`
/// doc comment: "Deliberately not keyed by fully_qualified_name"), so two nodes can
/// legitimately share one name; that case is reported as ambiguous (listing every candidate
/// index) rather than silently picking the first match. A spec matching nothing at all is
/// reported as unknown, naming how many modules the graph actually has.
///
/// Also resolves the sandbox base here, once: `matched.root`, made absolute via
/// `introspect.getResolvedCwd` when it is not already absolute. `EmitModuleGraph.zig`'s own
/// doc comment records the caveat this inherits -- a `.none`-root `Package.Module` is
/// rendered *relative to the compiler process's cwd at the time the graph was emitted* when
/// that cwd is a prefix of the path, and absolute otherwise (`Compilation.zig`'s
/// `Path.Formatter`/`absToCwdRelative`). This function has no way to confirm `--as-module`
/// is being run from that same cwd -- it can only join a relative `root` against *this*
/// process's own cwd and trust the operator invoked `ast-check` from where the graph was
/// emitted, exactly as a relative `--module-graph=<path>` argument already requires. When
/// even that join is impossible (`getResolvedCwd` itself fails -- e.g. the cwd was removed
/// out from under the process), there is no honest base to sandbox-check against at all, so
/// the whole `--as-module` request is refused by name here rather than silently skipping
/// the sandbox check or flagging every file import as an escape.
pub fn resolveAsModule(arena: Allocator, io: Io, loaded: LoadedGraph, spec: []const u8) Allocator.Error!AsModuleOutcome {
    var name_match_indices: std.ArrayList(usize) = .empty;
    for (loaded.modules, 0..) |m, i| {
        if (mem.eql(u8, m.fully_qualified_name, spec)) try name_match_indices.append(arena, i);
    }

    const matched_i: usize = switch (name_match_indices.items.len) {
        0 => resolve_by_index: {
            if (spec.len == 0 or !isAllDigits(spec)) {
                return .{ .err = try std.fmt.allocPrint(
                    arena,
                    "--as-module value '{s}' does not match any module's fully_qualified_name and is not a numeric index ({d} module(s) available in the graph -- pass a fully_qualified_name or an index in [0, {d}))",
                    .{ spec, loaded.modules.len, loaded.modules.len },
                ) };
            }
            const idx = std.fmt.parseInt(usize, spec, 10) catch {
                return .{ .err = try std.fmt.allocPrint(arena, "--as-module value '{s}' is all-digits but does not parse as a module index", .{spec}) };
            };
            for (loaded.modules, 0..) |m, i| {
                if (m.index == idx) break :resolve_by_index i;
            }
            return .{ .err = try std.fmt.allocPrint(arena, "--as-module index {d} does not exist in the module graph ({d} module(s) available)", .{ idx, loaded.modules.len }) };
        },
        1 => name_match_indices.items[0],
        else => {
            var indices_list: std.ArrayList(u8) = .empty;
            for (name_match_indices.items, 0..) |i, k| {
                if (k != 0) try indices_list.appendSlice(arena, ", ");
                try indices_list.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{loaded.modules[i].index}));
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

    // Fetched at most once, and only if actually needed below -- an absolute `root` never
    // needs it, matching this function's doc comment.
    const cwd_abs: ?[]const u8 = introspect.getResolvedCwd(io, arena) catch null;
    const root_abs: []const u8 = if (std.fs.path.isAbsolute(matched.root))
        try std.fs.path.resolve(arena, &.{matched.root})
    else if (cwd_abs) |c|
        try std.fs.path.resolve(arena, &.{ c, matched.root })
    else
        return .{ .err = try std.fmt.allocPrint(
            arena,
            "--as-module cannot sandbox-check module '{s}': its graph-recorded root ('{s}') is not an absolute path, and the current working directory could not be resolved to join against it -- refusing rather than guessing a base (Package/Module.zig's sandbox contract: \"Only files inside this directory can be imported\")",
            .{ matched.fully_qualified_name, matched.root },
        ) };

    return .{ .ok = .{
        .index = matched.index,
        .fully_qualified_name = matched.fully_qualified_name,
        .own_names = own_names,
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
/// sandbox check must agree on. THE one place that resolution happens (review finding
/// REJECT 1); the two consumers reading different paths is precisely how an absolute
/// operand walked out of the sandbox unnoticed.
///
/// `std.fs.path.join` does NOT reset on an absolute component -- measured on the promoted
/// 0.16.0 compiler:
///
///     join("/proj/root/sub", "/etc/passwd.zig") == "/proj/root/sub/etc/passwd.zig"
///
/// so `@import("/etc/passwd.zig")` from a file in the module was being resolved to a path
/// *inside* the module and passed the sandbox clean. The compiler's own resolution does
/// reset: `discoverImport` -> `Compilation.Path.upJoin` -> `introspect.resolvePath` ->
/// `std.fs.path.resolve`. This function restores that behavior at the one seam that feeds
/// both checks, exactly as the review prescribed.
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

/// Small formatting helper for the V6 membership diagnostic: the absolute path when we
/// managed to compute one, else the path as the operator wrote it. Never a placeholder that
/// looks like a real path.
fn fa_or(abs: ?[]const u8, fallback: []const u8) []const u8 {
    return abs orelse fallback;
}

/// Three-valued on purpose (review finding V5): `undecidable` is not `outside`. A boolean
/// here forced every "we cannot tell" into a verdict, and both directions were wrong in
/// practice -- an empty root made every absolute child look inside, and a root of "/" made
/// every child look outside.
const WithinRoot = enum { inside, outside, undecidable };

/// Whether `child_abs` names a path lexically inside the directory `root_abs` -- not equal
/// to it (a directory is not "inside" itself) and not merely string-prefixed by it (e.g.
/// `/root-extra` must not count as inside `/root`): the byte after the shared prefix must
/// be a path separator.
///
/// The head commit assumed both arguments were "already absolute and normalized ... by
/// their respective callers" and returned a bool. Review finding V5 measured two boundary
/// classes where that assumption does not hold and the bool therefore lied:
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
/// succeeded), upgrades both import checks below from rung 1's advisory semantics to the
/// compiler's own strict, per-module semantics -- see this file's top comment. `binding ==
/// null` reproduces rung 1's exact prior behavior; every rung-1/rung-3 call site that never
/// knew about `--as-module` need only pass `null` here to stay byte-identical.
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

    // Review finding V6 (scope premise unenforced). This rung's whole claim is "this file,
    // AS module X" -- and the head commit never checked the first half. A file outside X's
    // root passed clean while its ordinary, entirely legal local imports were accused of
    // escaping X's sandbox: the accusation was backwards, and the operator had no way to see
    // that the premise, not the code, was what failed. `Package/Module.zig:3` is explicit
    // that a module's files live under its root, so membership is checkable here.
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

        // File-vs-module classification mirrors the compiler's own: an import is a FILE
        // import iff it ends in ".zig" or ".zon" (src/Zcu/PerThread.zig:2384); everything
        // else is a named module. Diverging from that rule here produced a hard false
        // positive on legal @import("x.zon") in review -- keep the two in lockstep.
        if (mem.endsWith(u8, import_path, ".zig") or mem.endsWith(u8, import_path, ".zon")) {
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
                // this fork CHOOSES; the compiler does not enforce it -- see the
                // `sandbox_unresolvable` doc comment on `Stats` and the error text below.
                switch (try sandboxCheck(arena, b, resolved)) {
                    .inside => stats.file_imports += 1,
                    .outside => |abs| {
                        stats.file_imports += 1;
                        had_error = true;
                        try addImportError(wip_errors, tree, display_path, operand, "@import leaves module '{s}''s root directory: '{s}' resolves to '{s}', which lies outside '{s}'. This is a strictness --as-module CHOOSES, not a compiler rule: today the compiler enforces no @import sandbox at all (only @embedFile refuses an outside-package path, Sema.zig:13063 via Zcu/PerThread.zig:2881), so this code may well build. Package/Module.zig:3 states the intended contract (\"Only files inside this directory can be imported\") and --as-module checks it before a build", .{ b.fully_qualified_name, import_path, abs, b.root_abs });
                    },
                    .unresolvable => |reason| {
                        // Its OWN counted category (review finding V4): folding a site we
                        // could not check into `validated` claimed a check that did not
                        // happen. An absent instrument reports UNKNOWN, never a verdict.
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
pub fn printSummary(io: Io, stats: Stats, path_prefix: ?[]const u8, binding: ?ModuleBinding) !void {
    var buffer: [512]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
    if (path_prefix) |p| try w.print("{s}: ", .{p});
    try w.print(
        "import sites seen {d}: validated {d} (file {d}, named {d}), exempt(std/builtin/root) {d}, skipped-unchecked {d}, sandbox-unresolvable {d}",
        .{
            stats.total(),
            stats.file_imports + stats.named_imports,
            stats.file_imports,
            stats.named_imports,
            stats.exempt,
            stats.skipped_nonliteral,
            stats.sandbox_unresolvable,
        },
    );
    // Review finding REJECT 3 (doctrine 4, self-report): without this clause a passing
    // strict run and a passing union run were byte-identical in human output, so the line
    // could not testify to which semantics produced it.
    //
    // The clause is appended ONLY when a binding exists, and that is a deliberate choice,
    // not an omission: rung 1's and rung 3's summary format is a contract their own reviews
    // ratified, and rung 4 is an additive flag that must not move it. `--as-module` absent
    // therefore prints exactly what it always printed; `--as-module` present says so, names
    // the module, and names the rule it applied. The `--json` surface, which has no
    // byte-identity contract to keep, reports `check_semantics` on BOTH paths.
    if (binding) |b| {
        try w.print("; semantics strict (as module '{s}', graph index {d}: named imports checked against that module's own deps, file imports sandboxed to its root)\n", .{ b.fully_qualified_name, b.index });
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
