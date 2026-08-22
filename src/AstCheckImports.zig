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
//! Stage 0.5 rung 2 ("decl-existence pass", `docs/crown/PLAN.md` Stage 0.5 item 2) lives
//! in this same file, gated by the additive `--check-decls` flag (valid only alongside
//! `--module-graph`; see the fatal in `cmdAstCheck`). It is implemented by
//! `checkDeclExistence`, called from `checkAgainstGraph` only when requested, sharing that
//! function's already-loaded graph document and `ErrorBundle.Wip` so rung 1 and rung 2
//! violations render as one coherent bundle. See `checkDeclExistence`'s doc comment for the
//! honest scope (name existence only; no types, no comptime) and the exact alias-detection
//! and opacity rules.
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
const Color = std.zig.Color;
const ErrorBundle = std.zig.ErrorBundle;
const fatal = std.process.fatal;

/// The subset of `Compilation/EmitModuleGraph.zig`'s `Graph` schema that rungs 1 and 2
/// read. Deliberately not the full schema: `std.json`'s default `ignore_unknown_fields =
/// false` would otherwise reject every other field that schema emits (`optimize_mode`,
/// `strip`, `single_threaded`, `code_model`, `dep_fully_qualified_name`); we instead pass
/// `.ignore_unknown_fields = true` and only declare what we use. `index`, `root`, and
/// `root_src_path` on `ModuleDoc`, and `dep_index` on `DepDoc`, are rung-2-only fields --
/// rung 1 only ever reads `deps[].import_name` and `roots[].role`.
const GraphDoc = struct {
    modules: []const ModuleDoc,
    roots: []const RootDoc,
};
const ModuleDoc = struct {
    /// Stage 0's `ModuleNode.index` -- rung 2 resolves a `DepDoc.dep_index` back to a
    /// concrete module by searching for this field rather than assuming JSON array
    /// position equals index (doctrine 2: verify, don't assume).
    index: usize,
    /// Rendered module-root directory (`EmitModuleGraph.zig`'s `ModuleNode.root`,
    /// `Compilation.Path.fmt`-formatted -- already a filesystem-openable path, absolute or
    /// cwd-relative). Joined with `root_src_path` to locate the module's root file.
    root: []const u8,
    root_src_path: []const u8,
    deps: []const DepDoc,
};
const DepDoc = struct {
    import_name: []const u8,
    /// Index into `GraphDoc.modules[].index`, or null if stage 0 could not resolve the
    /// dependency module (see `EmitModuleGraph.zig`'s `DepEdge.dep_index` doc comment).
    /// Rung 1 does not read this field.
    dep_index: ?usize,
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
const Stats = struct {
    file_imports: usize = 0,
    named_imports: usize = 0,
    exempt: usize = 0,
    skipped_nonliteral: usize = 0,
};

/// True iff `import_path` denotes a relative FILE import rather than a named module.
/// Mirrors the compiler's own classification (`src/Zcu/PerThread.zig:2384`): a file import
/// is any operand ending in ".zig" or ".zon". Shared by rung 1's import-validity walk and
/// rung 2's decl-existence target resolution (`checkDeclExistence`) so the two rungs can
/// never drift apart on this question -- see this file's top doc comment.
fn isFileImport(import_path: []const u8) bool {
    return mem.endsWith(u8, import_path, ".zig") or mem.endsWith(u8, import_path, ".zon");
}

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
/// `check_decls` is rung 2 (stage 0.5 item 2, "decl-existence pass"), additive on top of
/// the above: `false` reproduces rung 1's behavior byte-identically (the hard constraint
/// `docs/crown/PLAN.md`'s design constraints and both prior reviews established); `true`
/// additionally runs `checkDeclExistence` against the same loaded `graph` and the same
/// `wip_errors`/`had_error` so both rungs' violations render as one bundle, and prints one
/// further summary line. See `checkDeclExistence`'s doc comment for its scope and rules.
pub fn checkAgainstGraph(
    arena: Allocator,
    io: Io,
    tree: Ast,
    zig_source_path: []const u8,
    display_path: []const u8,
    graph_path: []const u8,
    color: Color,
    check_decls: bool,
) !void {
    const graph = loadGraph(arena, io, graph_path);

    // The union of every declared import-edge name in the graph, plus the root roles
    // (`std`, and on test builds `main`, plus the `compiler_rt`/`ubsan_rt`/`zigc` runtime
    // roots -- see `EmitModuleGraph.zig`'s `GraphRoot` construction). This is rung 1's
    // graph-wide semantics, documented above and in the per-violation error text.
    var allowed_names: std.StringHashMapUnmanaged(void) = .empty;
    for (graph.modules) |m| for (m.deps) |d| try allowed_names.put(arena, d.import_name, {});
    for (graph.roots) |r| try allowed_names.put(arena, r.role, {});

    const checked_dir = std.fs.path.dirname(zig_source_path) orelse ".";

    var stats: Stats = .{};
    var wip_errors: ErrorBundle.Wip = undefined;
    try wip_errors.init(arena);
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

        // File-vs-module classification mirrors the compiler's own via `isFileImport`
        // (src/Zcu/PerThread.zig:2384); everything else is a named module. Diverging from
        // that rule here produced a hard false positive on legal @import("x.zon") in
        // review -- keep the two (and rung 2, which reuses the same helper) in lockstep.
        if (isFileImport(import_path)) {
            stats.file_imports += 1;
            const resolved = try std.fs.path.join(arena, &.{ checked_dir, import_path });
            Io.Dir.cwd().access(io, resolved, .{}) catch {
                had_error = true;
                try addImportError(&wip_errors, tree, display_path, operand, "@import of relative file that does not exist on disk: '{s}' (resolved path: '{s}')", .{ import_path, resolved });
            };
        } else if (mem.eql(u8, import_path, "std") or mem.eql(u8, import_path, "builtin") or mem.eql(u8, import_path, "root")) {
            // Special-cased shortcuts: never present in `Package.Module.deps` (see
            // `EmitModuleGraph.zig`'s `DepEdge` doc comment), so there is nothing in the
            // graph to look them up against. Counted as `exempt` so the summary's total
            // reconciles against every @import site in the source.
            stats.exempt += 1;
        } else {
            stats.named_imports += 1;
            if (!allowed_names.contains(import_path)) {
                had_error = true;
                try addImportError(&wip_errors, tree, display_path, operand, "unregistered module import name: '{s}' is not declared as an import edge anywhere in the module graph (rung-1 semantics: this checks the graph-wide union of every module's import names, not the specific module this file belongs to -- per-module strict matching arrives with --as-module, stage 0.5 rung 4)", .{import_path});
            }
        }
    }

    // Rung 2 (additive, off unless --check-decls): shares this call's already-loaded
    // `graph` and `wip_errors`/`had_error` rather than reloading or re-rendering, so a file
    // with both an unregistered import name (rung 1) and a missing-declaration reference
    // (rung 2) reports both in one bundle instead of the operator needing two invocations.
    var decl_stats: DeclStats = .{};
    if (check_decls) {
        try checkDeclExistence(arena, io, tree, display_path, checked_dir, graph, &wip_errors, &had_error, &decl_stats);
    }

    if (had_error) {
        var eb = try wip_errors.toOwnedBundle("");
        try eb.renderToStderr(io, .{}, color);
    }

    try printSummary(io, stats);
    if (check_decls) try printDeclSummary(io, decl_stats);

    if (had_error) process.exit(1);
}

/// Adds one error, pinned to `operand`'s source span, to `wip`. Despite the name (rung 1's
/// only caller need), this is generic over any node -- rung 2 (`checkDeclExistence`) reuses
/// it unchanged to pin its own violations to a member-access node instead of an `@import`
/// operand.
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
fn printSummary(io: Io, stats: Stats) !void {
    var buffer: [256]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
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

/// Reads and parses the stage-0 module-graph JSON document. Any failure here -- the file
/// cannot be opened, or its contents are not the expected JSON shape -- is a named fatal
/// error: the check the operator asked for cannot run at all, so it must never look like a
/// silent pass (doctrine 2, present-or-refuse-by-name).
fn loadGraph(arena: Allocator, io: Io, graph_path: []const u8) GraphDoc {
    var f = Io.Dir.cwd().openFile(io, graph_path, .{}) catch |err| {
        fatal("unable to open module graph '{s}' for --module-graph: {t}", .{ graph_path, err });
    };
    defer f.close(io);
    var read_buffer: [4096]u8 = undefined;
    var file_reader: Io.File.Reader = f.reader(io, &read_buffer);
    const json = std.zig.readSourceFileToEndAlloc(arena, &file_reader) catch |err| {
        fatal("unable to read module graph '{s}' for --module-graph: {t}", .{ graph_path, err });
    };
    // `ignore_unknown_fields`: see `GraphDoc`'s doc comment. Note also the inherited
    // caveat from `EmitModuleGraph.zig`'s doc comment -- a non-UTF-8 name anywhere in the
    // document changes that field's JSON type from string to an int-array, which this
    // subset schema does not special-case; such a document fails to parse here and is
    // reported through this same named-fatal path rather than silently mis-decoded.
    return std.json.parseFromSliceLeaky(GraphDoc, arena, json, .{ .ignore_unknown_fields = true }) catch |err| {
        fatal("malformed module-graph JSON '{s}' for --module-graph: {t}", .{ graph_path, err });
    };
}

// ===========================================================================================
// Stage 0.5 rung 2 -- the decl-existence pass ("sema-lite", `docs/crown/PLAN.md` Stage 0.5
// item 2). Honest scope, restated from the plan: name existence and single-level alias
// resolution only -- no types, no comptime, no multi-hop or dynamic aliasing. Two shapes of
// member access are resolved:
//
//   (a) inline:        `@import("x").foo`
//   (b) single alias:  `const m = @import("x"); ... m.foo`  (`m` a file-scope `const` bound
//                       *directly* to the `@import` call -- nothing else qualifies)
//
// Every other flow that could plausibly reach an import's namespace -- a file-scope `var`
// bound to `@import`, a file-scope `const` bound to another name (a chain, however deep), or
// *any* such binding inside a function body rather than at file scope -- is deliberately
// never followed. This is name-matched, not scope-resolved: a local variable that happens to
// share a name with a file-scope alias is not distinguished from it (no binder here, per the
// plan's "no types, no comptime" honest-scope line). These un-followed flows are recorded in
// `alias_too_deep` rather than silently ignored, per doctrine 2 (every "cannot honestly
// check" case is counted, never silent).
//
// Once a member access resolves to an import, the target is located exactly as rung 1 does
// (`isFileImport`: relative `.zig`/`.zon` file vs. named module looked up in the graph) and
// parsed with `Ast.parse` only -- no `AstGen`, matching the plan's honest scope. The target
// is OPAQUE -- every member reference into it counted `opaque_skipped`, nothing guessed --
// if its top level contains a `comptime` block. (`usingnamespace` is the plan's other named
// opacity trigger; it does not exist in this fork's Zig 0.16 language at all -- confirmed
// absent from the whole `lib/` and `src/` tree -- so there is no corresponding case to write
// here; a future rebase that reintroduces the keyword would need to add one.) A `.zon` file
// import is also treated as opaque: ZON is data, not declarations, so "public top-level
// declaration" does not apply to it.
// ===========================================================================================

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

/// The outcome of resolving one target file, cached by resolved path so a target referenced
/// by many member accesses is read and parsed at most once.
const TargetOutcome = union(enum) {
    opaque_target,
    /// Covers both "could not be read/opened" and "did not parse cleanly" -- see the
    /// section comment above `checkDeclExistence`: both are the plan's "unreadable /
    /// unparsable target file = NAMED error" case. Not distinguishing I/O failure from a
    /// syntax-error file mirrors `loadGraph`'s own established convention just above.
    unreadable,
    decls: std.StringHashMapUnmanaged(void),
};

/// Honest denominators for rung 2's summary line, matching rung 1's `Stats` idiom:
/// `validated + missing + opaque_skipped + alias_too_deep + target_unresolvable + exempt`
/// equals every import-derived member reference found in the checked file, so the operator
/// can reconcile the summary against the source exactly as with rung 1's line.
const DeclStats = struct {
    validated: usize = 0,
    missing: usize = 0,
    opaque_skipped: usize = 0,
    alias_too_deep: usize = 0,
    target_unresolvable: usize = 0,
    exempt: usize = 0,
};

/// Entry point for rung 2, called from `checkAgainstGraph` only when `--check-decls` was
/// given. `graph` is the same document `checkAgainstGraph` already loaded; `wip_errors` and
/// `had_error` are shared with rung 1 so both rungs' violations render as one bundle. See
/// the section comment above for the exact scope and alias/opacity rules.
fn checkDeclExistence(
    arena: Allocator,
    io: Io,
    tree: Ast,
    display_path: []const u8,
    checked_dir: []const u8,
    graph: GraphDoc,
    wip_errors: *ErrorBundle.Wip,
    had_error: *bool,
    stats: *DeclStats,
) !void {
    // Resolve every named import edge in the graph to its concrete target module, by
    // stage-0 index (`ModuleDoc.index`, not JSON array position -- doctrine 2, verify
    // rather than assume). A name that maps to more than one distinct target across the
    // graph-wide union (rung 1's own semantics: names are checked graph-wide, not
    // per-module) cannot be honestly resolved to one file here, so it collapses to `null`
    // -- reported at use as `target_unresolvable` rather than picking one target
    // arbitrarily.
    var module_by_index: std.AutoHashMapUnmanaged(usize, ModuleDoc) = .empty;
    for (graph.modules) |m| try module_by_index.put(arena, m.index, m);

    var named_targets: std.StringHashMapUnmanaged(?ModuleTarget) = .empty;
    for (graph.modules) |m| {
        for (m.deps) |d| {
            const target: ?ModuleTarget = if (d.dep_index) |di| dep_blk: {
                const dep_mod = module_by_index.get(di) orelse break :dep_blk null;
                break :dep_blk ModuleTarget{ .root = dep_mod.root, .root_src_path = dep_mod.root_src_path };
            } else null;
            const gop = try named_targets.getOrPut(arena, d.import_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = target;
            } else if (!targetEqlOpt(gop.value_ptr.*, target)) {
                gop.value_ptr.* = null;
            }
        }
    }

    // --- Pass 1: file-scope (root) const/var bindings, resolved into `simple_aliases` (the
    // one followable shape, (b) above) and `deep_alias_names` (every other flow, see the
    // section comment above). Root decls can forward-reference each other, so this is
    // collect-then-fixpoint rather than a single linear scan.
    const RootBindingKind = union(enum) {
        direct_import: []const u8,
        identifier_ref: []const u8,
        other,
    };
    const RootBinding = struct { kind: RootBindingKind, is_const: bool };
    var root_bindings: std.StringHashMapUnmanaged(RootBinding) = .empty;
    for (tree.rootDecls()) |decl| {
        switch (tree.nodeTag(decl)) {
            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {
                const vd = tree.fullVarDecl(decl).?;
                const name = tree.tokenSlice(vd.ast.mut_token + 1);
                const is_const = tree.tokenTag(vd.ast.mut_token) == .keyword_const;
                const init_node = vd.ast.init_node.unwrap() orelse continue;
                const kind: RootBindingKind = k: {
                    if (try directImportPath(arena, tree, init_node)) |p| break :k .{ .direct_import = p };
                    if (tree.nodeTag(init_node) == .identifier) {
                        break :k .{ .identifier_ref = tree.tokenSlice(tree.nodeMainToken(init_node)) };
                    }
                    break :k .other;
                };
                try root_bindings.put(arena, name, .{ .kind = kind, .is_const = is_const });
            },
            else => {},
        }
    }

    var simple_aliases: std.StringHashMapUnmanaged([]const u8) = .empty;
    var deep_alias_names: std.StringHashMapUnmanaged(void) = .empty;
    {
        var it = root_bindings.iterator();
        while (it.next()) |entry| switch (entry.value_ptr.kind) {
            .direct_import => |p| if (entry.value_ptr.is_const)
                try simple_aliases.put(arena, entry.key_ptr.*, p)
            else
                // `var`, not `const`: reassignable, so not the single-level shape (b)
                // above documents as followable -- "any other flow" in the section comment.
                try deep_alias_names.put(arena, entry.key_ptr.*, {}),
            else => {},
        };
        // Fixpoint: `const n = m;` where `m` is (transitively) import-derived makes `n`
        // import-derived too, but never a *simple* alias (deeper than one hop) -- so it
        // only ever joins `deep_alias_names`, never `simple_aliases`.
        var changed = true;
        while (changed) {
            changed = false;
            var it2 = root_bindings.iterator();
            while (it2.next()) |entry| {
                const name = entry.key_ptr.*;
                if (deep_alias_names.contains(name)) continue;
                switch (entry.value_ptr.kind) {
                    .identifier_ref => |target| {
                        if (simple_aliases.contains(target) or deep_alias_names.contains(target)) {
                            try deep_alias_names.put(arena, name, {});
                            changed = true;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    var root_decl_set: std.AutoHashMapUnmanaged(Ast.Node.Index, void) = .empty;
    for (tree.rootDecls()) |d| try root_decl_set.put(arena, d, {});

    var target_cache: std.StringHashMapUnmanaged(TargetOutcome) = .empty;

    // --- Pass 2: one walk of every node for (1) local (non-root) const/var bindings bound
    // directly to `@import` -- the "locals" case from the section comment above, folded
    // into `deep_alias_names` by name (relies on Zig's declare-before-use rule for locals to
    // land before any use in this single forward pass; a miss here only ever *undercounts*
    // `alias_too_deep`, never misclassifies a reference as validated) -- and (2) every
    // `field_access` node, classified per the section comment above.
    const node_count: u32 = @intCast(tree.nodes.len);
    var node_idx: u32 = 0;
    while (node_idx < node_count) : (node_idx += 1) {
        const node: Ast.Node.Index = @enumFromInt(node_idx);
        switch (tree.nodeTag(node)) {
            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {
                if (root_decl_set.contains(node)) continue; // already resolved in pass 1
                const vd = tree.fullVarDecl(node).?;
                const init_node = vd.ast.init_node.unwrap() orelse continue;
                if (try directImportPath(arena, tree, init_node)) |_| {
                    try deep_alias_names.put(arena, tree.tokenSlice(vd.ast.mut_token + 1), {});
                }
            },
            .field_access => {
                const lhs, const member_tok = tree.nodeData(node).node_and_token;
                const member_name = tree.tokenSlice(member_tok);

                if (try directImportPath(arena, tree, lhs)) |import_path| {
                    try classifyMemberRef(arena, io, tree, display_path, checked_dir, &named_targets, &target_cache, wip_errors, had_error, stats, import_path, member_name, node);
                    continue;
                }
                if (tree.nodeTag(lhs) == .identifier) {
                    const base_name = tree.tokenSlice(tree.nodeMainToken(lhs));
                    if (deep_alias_names.contains(base_name)) {
                        stats.alias_too_deep += 1;
                        continue;
                    }
                    if (simple_aliases.get(base_name)) |import_path| {
                        try classifyMemberRef(arena, io, tree, display_path, checked_dir, &named_targets, &target_cache, wip_errors, had_error, stats, import_path, member_name, node);
                        continue;
                    }
                }
                // Neither shape (a) nor (b): an ordinary field access unrelated to an
                // import (or a deeper chain like `m.sub.foo`, out of scope by design) -- not
                // a member ref on an import result, so not counted in any bucket.
            },
            else => {},
        }
    }
}

/// If `node` is exactly `@import("literal")`, returns the parsed import path; otherwise
/// null. A small, standalone counterpart to rung 1's own inline `@import`-node parsing
/// (embedded in `checkAgainstGraph`'s error-emitting walk, where extracting a shared helper
/// would cost more churn than it saves) -- kept deliberately separate per minimal-hunks.
fn directImportPath(arena: Allocator, tree: Ast, node: Ast.Node.Index) !?[]const u8 {
    switch (tree.nodeTag(node)) {
        .builtin_call, .builtin_call_comma, .builtin_call_two, .builtin_call_two_comma => {},
        else => return null,
    }
    const builtin_token = tree.nodeMainToken(node);
    if (!mem.eql(u8, tree.tokenSlice(builtin_token), "@import")) return null;

    var params_buf: [2]Ast.Node.Index = undefined;
    const params = tree.builtinCallParams(&params_buf, node) orelse return null;
    if (params.len != 1) return null;
    const operand = params[0];
    if (tree.nodeTag(operand) != .string_literal) return null;

    const str_token = tree.nodeMainToken(operand);
    const raw = tree.tokenSlice(str_token);
    return std.zig.string_literal.parseAlloc(arena, raw) catch null;
}

/// Resolves one member reference (`import_path`.`member_name`, referenced at `ref_node` in
/// the checked file) into its bucket in `stats`, resolving and (via `target_cache`) caching
/// the target file at most once regardless of how many member references land on it.
fn classifyMemberRef(
    arena: Allocator,
    io: Io,
    tree: Ast,
    display_path: []const u8,
    checked_dir: []const u8,
    named_targets: *const std.StringHashMapUnmanaged(?ModuleTarget),
    target_cache: *std.StringHashMapUnmanaged(TargetOutcome),
    wip: *ErrorBundle.Wip,
    had_error: *bool,
    stats: *DeclStats,
    import_path: []const u8,
    member_name: []const u8,
    ref_node: Ast.Node.Index,
) !void {
    // std/builtin/root: exempt, exactly as rung 1 treats them -- nothing in the graph to
    // resolve them against (see `EmitModuleGraph.zig`'s `DepEdge` doc comment).
    if (mem.eql(u8, import_path, "std") or mem.eql(u8, import_path, "builtin") or mem.eql(u8, import_path, "root")) {
        stats.exempt += 1;
        return;
    }

    const resolved_path: []const u8 = if (isFileImport(import_path))
        try std.fs.path.join(arena, &.{ checked_dir, import_path })
    else named_blk: {
        const mt = (named_targets.get(import_path) orelse null) orelse {
            // Registered somewhere in the graph-wide union (rung 1 already required this,
            // or `cmdAstCheck` would have exited before rung 2 ever ran) but not resolvable
            // to one concrete module node here -- see `checkDeclExistence`'s doc comment.
            stats.target_unresolvable += 1;
            return;
        };
        break :named_blk try std.fs.path.join(arena, &.{ mt.root, mt.root_src_path });
    };

    const outcome = target_cache.get(resolved_path) orelse resolve_blk: {
        const is_zon = mem.endsWith(u8, resolved_path, ".zon");
        const computed = try resolveTarget(arena, io, resolved_path, is_zon);
        try target_cache.put(arena, resolved_path, computed);
        break :resolve_blk computed;
    };

    switch (outcome) {
        .opaque_target => stats.opaque_skipped += 1,
        .unreadable => {
            had_error.* = true;
            try addImportError(wip, tree, display_path, ref_node, "cannot check member '{s}': target file '{s}' could not be read or parsed as Zig source -- the check was requested and cannot honestly pass", .{ member_name, resolved_path });
            stats.missing += 1;
        },
        .decls => |names| if (names.contains(member_name)) {
            stats.validated += 1;
        } else {
            had_error.* = true;
            try addImportError(wip, tree, display_path, ref_node, "referenced declaration not found: '{s}' is not a public top-level declaration of '{s}'", .{ member_name, resolved_path });
            stats.missing += 1;
        },
    }
}

/// Reads and parses `resolved_path` (unless `is_zon`, which is opaque by construction: ZON
/// is data, not Zig declarations) and returns its public top-level declaration names, or
/// `.opaque_target` if a `comptime` block sits at its top level (name-level analysis cannot
/// see through it -- see the section comment above `checkDeclExistence`), or `.unreadable`
/// if it cannot be opened, read, or parsed without errors.
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

    var names: std.StringHashMapUnmanaged(void) = .empty;
    for (tree.rootDecls()) |decl| {
        switch (tree.nodeTag(decl)) {
            .fn_decl => {
                var buf: [1]Ast.Node.Index = undefined;
                const proto = tree.fullFnProto(&buf, decl).?;
                if (proto.visib_token != null) {
                    if (proto.name_token) |nt| try names.put(arena, tree.tokenSlice(nt), {});
                }
            },
            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {
                const vd = tree.fullVarDecl(decl).?;
                if (vd.visib_token != null) try names.put(arena, tree.tokenSlice(vd.ast.mut_token + 1), {});
            },
            else => {},
        }
    }
    return .{ .decls = names };
}

/// Rung 2's one summary line, matching rung 1's `printSummary` idiom (doctrine 4,
/// self-report): printed whenever `--check-decls` was requested, pass or fail.
fn printDeclSummary(io: Io, stats: DeclStats) !void {
    var buffer: [256]u8 = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;
    try w.print(
        "member refs seen {d}: validated {d}, missing {d}, opaque-skipped {d}, alias-too-deep {d}, target-unresolvable {d}, exempt {d}\n",
        .{
            stats.validated + stats.missing + stats.opaque_skipped + stats.alias_too_deep + stats.target_unresolvable + stats.exempt,
            stats.validated,
            stats.missing,
            stats.opaque_skipped,
            stats.alias_too_deep,
            stats.target_unresolvable,
            stats.exempt,
        },
    );
    try w.flush();
}
