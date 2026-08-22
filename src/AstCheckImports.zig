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
const Stats = struct {
    file_imports: usize = 0,
    named_imports: usize = 0,
    exempt: usize = 0,
    skipped_nonliteral: usize = 0,
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
    color: Color,
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

        // File-vs-module classification mirrors the compiler's own: an import is a FILE
        // import iff it ends in ".zig" or ".zon" (src/Zcu/PerThread.zig:2384); everything
        // else is a named module. Diverging from that rule here produced a hard false
        // positive on legal @import("x.zon") in review -- keep the two in lockstep.
        if (mem.endsWith(u8, import_path, ".zig") or mem.endsWith(u8, import_path, ".zon")) {
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

    if (had_error) {
        var eb = try wip_errors.toOwnedBundle("");
        try eb.renderToStderr(io, .{}, color);
    }

    try printSummary(io, stats);

    if (had_error) process.exit(1);
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
