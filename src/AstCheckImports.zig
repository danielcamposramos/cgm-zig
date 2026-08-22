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
//! (`.zig`/`.zon`) are additionally sandbox-checked against the module's own root directory
//! -- `Package/Module.zig`'s own contract ("Only files inside this directory can be
//! imported"), enforced here *before* a build, not merely observed by one. Absent
//! `--as-module`, `binding` below is `null` everywhere and both checks fall back to rung
//! 1's original union/no-sandbox behavior byte-for-byte -- see `collectGraphViolations`.

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

    try printSummary(io, result.stats, null);

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

/// Prefix-compares `resolved` (the file-import path already joined against the checked
/// file's own directory, exactly as rung 1 computed it for the existence check) against
/// `binding.root_abs`, after making `resolved` itself absolute and lexically normalized the
/// same way `resolveAsModule` normalized `root_abs`. Lexical only -- like `resolveAsModule`,
/// this does not follow symlinks (`std.fs.path.resolve`'s own documented limitation), which
/// is the same honest scope the plan's "std.fs.path resolution + prefix comparison on
/// normalized paths" instruction calls for.
fn sandboxCheck(arena: Allocator, binding: ModuleBinding, resolved: []const u8) Allocator.Error!SandboxOutcome {
    const abs = if (std.fs.path.isAbsolute(resolved))
        try std.fs.path.resolve(arena, &.{resolved})
    else if (binding.cwd_abs) |c|
        try std.fs.path.resolve(arena, &.{ c, resolved })
    else
        return .{ .unresolvable = "the checked file's own path is relative and the current working directory could not be resolved to make its import path absolute for comparison against the module root" };

    if (pathIsWithinRoot(abs, binding.root_abs)) return .inside;
    return .{ .outside = abs };
}

/// True iff `child_abs` names a path lexically inside the directory `root_abs` -- not equal
/// to it (a directory is not "inside" itself) and not merely string-prefixed by it (e.g.
/// `/root-extra` must not count as inside `/root`): the byte after the shared prefix must
/// be a path separator. Both arguments are assumed already absolute and normalized (no
/// trailing separator, no `.`/`..` components) by their respective callers.
fn pathIsWithinRoot(child_abs: []const u8, root_abs: []const u8) bool {
    if (!mem.startsWith(u8, child_abs, root_abs)) return false;
    if (child_abs.len == root_abs.len) return false;
    return child_abs[root_abs.len] == std.fs.path.sep;
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
            stats.file_imports += 1;
            const resolved = try std.fs.path.join(arena, &.{ checked_dir, import_path });
            const exists = if (Io.Dir.cwd().access(io, resolved, .{})) |_| true else |_| false;
            if (!exists) {
                had_error = true;
                try addImportError(wip_errors, tree, display_path, operand, "@import of relative file that does not exist on disk: '{s}' (resolved path: '{s}')", .{ import_path, resolved });
            } else if (binding) |b| {
                // Rung 4 sandbox check (`Package/Module.zig`'s own contract: "Only files
                // inside this directory can be imported"), gated on `exists` above so a
                // nonexistent import gets exactly one error, not two, on the same site.
                switch (try sandboxCheck(arena, b, resolved)) {
                    .inside => {},
                    .outside => |abs| {
                        had_error = true;
                        try addImportError(wip_errors, tree, display_path, operand, "@import escapes module '{s}''s sandboxed root: '{s}' resolves to '{s}', which lies outside '{s}' (Package/Module.zig's own contract: \"Only files inside this directory can be imported\")", .{ b.fully_qualified_name, import_path, abs, b.root_abs });
                    },
                    .unresolvable => |reason| {
                        had_error = true;
                        try addImportError(wip_errors, tree, display_path, operand, "@import '{s}' could not be sandbox-checked against module '{s}': {s}", .{ import_path, b.fully_qualified_name, reason });
                    },
                }
            }
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
pub fn printSummary(io: Io, stats: Stats, path_prefix: ?[]const u8) !void {
    var buffer: [256]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
    if (path_prefix) |p| try w.print("{s}: ", .{p});
    try w.print(
        "import sites seen {d}: validated {d} (file {d}, named {d}), exempt(std/builtin/root) {d}, skipped-unchecked {d}\n",
        .{
            stats.file_imports + stats.named_imports + stats.exempt + stats.skipped_nonliteral,
            stats.file_imports + stats.named_imports,
            stats.file_imports,
            stats.named_imports,
            stats.exempt,
            stats.skipped_nonliteral,
        },
    );
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
