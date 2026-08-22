//! Stage 0.5 rung 3 of the crown (`docs/crown/PLAN.md`, "Stage 0.5" item 3): batch mode
//! with honest denominators. `zig ast-check f1.zig f2.zig ...` runs the same per-file
//! pipeline `cmdAstCheck` (in `main.zig`) already runs for a single file -- parse, AstGen
//! (or ZonGen for `.zon`), error render, plus rung 1's `--module-graph` import validation
//! when requested -- independently over every requested file, and never lets one file's
//! failure hide another's: a file that cannot be opened or read is SKIPPED WITH ITS REASON
//! (named, per doctrine 2), never silently dropped, and never aborts the rest of the batch.
//!
//! `cmdAstCheck` only reaches this file for 2+ files, or exactly 1 file with `--json` (see
//! its dispatch comment): the single-file, non-`--json` case keeps running its own
//! untouched, pre-existing code path so that contract stays byte-identical to upstream --
//! see that function's dispatch logic for the exact three-way split and how it is proved.
//! A duplicate path in argv is not deduplicated: it is opened, checked, and counted again
//! each time it appears, so `requested` counts *occurrences*, not unique files (rung-3
//! review item 5) -- also stated in `usage_ast_check` (`main.zig`).
//!
//! `--json`: when set, replaces ALL human-readable stderr/stdout rendering (per-file error
//! text, rung 1's per-file import-stats line, the batch summary line) with ONE JSON
//! document on stdout, a documented SUBSET of `ErrorBundle` (rung-3 review item 13) --
//! deliberately omitted: `compile_log_text`, `source_line`, `span_start`/`span_main`/
//! `span_end`, `reference_trace`, and each note's own `src_path`; none of these can occur
//! in ast-check's own diagnostics today, so their absence is not a loss of information for
//! this command, only for a hypothetical future one:
//! `{files:[{path,status,reason?,errors:[{msg,line,column,count,notes}],import_stats?,
//! graph_check?}],summary:{requested,checked,failed,skipped,graph_not_applicable,
//! import_stats}}`. `import_stats` (both per-file and the summary's aggregate total) is
//! rung 1's honest-denominator `AstCheckImports.Stats`, carried into `--json` rather than
//! discarded (rung-3 review item 2: PLAN.md's own charter for this rung is "diagnostics
//! available as machine-readable JSON... without scraping"). `graph_check`, present only
//! on a `.zon` file's row when `--module-graph` was requested, is the string
//! `"not_applicable_zon"` -- see `checkZonFile` below and rung-3 review item 3(b): a `.zon`
//! member of a batch has nothing to check on that axis, and this says so rather than
//! silently doing nothing. Diagnostics are read directly off `ErrorBundle`'s own accessors
//! (`getMessages`/`getErrorMessage`/`getSourceLocation`/`getNotes`/`nullTerminatedString`
//! -- see `lib/std/zig/ErrorBundle.zig`) rather than scraped from `renderToStderr`'s text
//! output, per doctrine 5 ("parse the output" applies doubly to code that itself emits
//! machine-readable output: read the structured source of truth, don't scrape a rendering
//! meant for humans).
//!
//! Schema caveat inherited from `Compilation/EmitModuleGraph.zig`'s own JSON emitter (its
//! doc comment, lines 18-23): `std.json.Stringify` gates string encoding on UTF-8 validity
//! and falls back to emitting invalid-UTF-8 byte slices as a JSON array of integers. The
//! exposure here is wider than that emitter's: `path` comes straight from argv (arbitrary
//! bytes on POSIX -- batch mode is exactly the `find | xargs` use case), and `msg`/`reason`
//! carry source-derived and errno-derived text. Consumers must tolerate a `path`, `msg`, or
//! `reason` field silently changing JSON type from string to an array of integers on
//! non-UTF-8 input, exactly as `EmitModuleGraph.zig`'s consumers must (rung-3 review item
//! 1); also stated in `usage_ast_check` (`main.zig`).
//!
//! Honest denominators (the plan's own phrase for this rung): `requested = checked + failed
//! + skipped` always. `checked` counts only files that ran the full pipeline AND came back
//! clean; a file that ran and produced diagnostics is `failed`, not folded into `checked`
//! bucket with an asterisk. Exit is nonzero iff `failed > 0 or skipped > 0` -- a skip is
//! never a pass, and the human summary line says so explicitly whenever `skipped > 0`.

const std = @import("std");
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const Io = std.Io;
const Ast = std.zig.Ast;
const AstGen = std.zig.AstGen;
const ZonGen = std.zig.ZonGen;
const Color = std.zig.Color;
const ErrorBundle = std.zig.ErrorBundle;
const cleanExit = std.process.cleanExit;
const AstCheckImports = @import("AstCheckImports.zig");

/// One file's outcome after the batch pipeline. `ok`/`failed` both mean the file's pipeline
/// ran to completion (parse + AstGen/ZonGen, plus the graph check when requested); `skipped`
/// means it never got that far because it could not be opened or read.
const FileStatus = enum { ok, failed, skipped };

/// A single extracted `ErrorBundle` message, faithfully mirroring the fields
/// `ErrorBundle.getErrorMessage`/`getSourceLocation` expose (see this file's top comment).
/// `line`/`column` are rendered 1-based to match `ErrorBundle.renderToTerminal`'s own
/// `+ 1` convention, so a JSON consumer's coordinates agree with what a human would see in
/// the non-`--json` rendering of the same diagnostic. `notes` recurses because
/// `ErrorBundle` notes can themselves carry notes (`renderErrorMessage` recurses on
/// `getNotes` without a depth limit); defaulted to empty so this type stays forward
/// compatible if a future rung adds fields (rung 2's schema lesson: new fields need
/// defaults so existing consumers of this shape are untouched).
const JsonError = struct {
    msg: []const u8,
    line: u32 = 0,
    column: u32 = 0,
    count: u32 = 1,
    notes: []const JsonError = &.{},
};

/// One file's row in the JSON document's `files` array. `reason` is populated only for
/// `status == "skipped"`; `errors` is populated only for `status == "failed"`;
/// `import_stats` only when `--module-graph` was requested and this file is a `.zig` file
/// (rung-3 review item 2); `graph_check` only when `--module-graph` was requested and this
/// file is `.zon` (item 3(b)). All four default to their empty/null form so a JSON consumer
/// never needs a presence check that isn't implied by `status` (or, for the latter two, by
/// whether `--module-graph` was requested at all) alone.
const JsonFile = struct {
    path: []const u8,
    status: []const u8,
    reason: ?[]const u8 = null,
    errors: []const JsonError = &.{},
    import_stats: ?AstCheckImports.Stats = null,
    graph_check: ?[]const u8 = null,
};

/// Defaulted throughout (rung-3 review item 7): the four counters have the obvious correct
/// default of 0, `graph_not_applicable` (the count of `.zon` files a requested
/// `--module-graph` check did not apply to, item 3(b)) likewise, and `import_stats` (the
/// summed `AstCheckImports.Stats` across every graph-checked `.zig` file, item 2) is
/// all-zero when no file was graph-checked.
const JsonSummary = struct {
    requested: usize = 0,
    checked: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    graph_not_applicable: usize = 0,
    import_stats: AstCheckImports.Stats = .{},
};

/// Defaulted per rung-3 review item 7.
const JsonDoc = struct {
    files: []const JsonFile = &.{},
    summary: JsonSummary = .{},
};

/// Minimal valid JSON document emitted to stdout when a `--json` invocation cannot even
/// begin (its `--module-graph` document could not be loaded): doctrine 4 requires a
/// `--json` consumer reading only stdout to never see zero bytes on a fatal condition it
/// could otherwise only detect by falling back to the exit code (rung-3 review item 10).
/// Deliberately not shaped like `JsonDoc` -- there is no per-file data to report yet.
const JsonErrorDoc = struct {
    @"error": []const u8,
};

/// Internal per-file bookkeeping: `status` drives the batch's requested/checked/failed/
/// skipped counters and the human-mode skip listing; `json` is that same file's row in the
/// `--json` document. Keeping both on one value (rather than deriving `status` back out of
/// `json.status` string comparisons downstream) keeps the counting path a plain enum switch.
const CheckOutcome = struct {
    /// Defaulted per rung-3 review item 7; `json` names its two required fields (`path`,
    /// `status`) explicitly since `JsonFile` itself deliberately does not default them --
    /// they are always known at construction, unlike the forward-compat fields.
    status: FileStatus = .skipped,
    json: JsonFile = .{ .path = "", .status = "skipped" },
};

/// Entry point dispatched from `cmdAstCheck` for batch mode (`main.zig`). `file_paths` is
/// never empty and `-t` has already been refused by the caller -- see its dispatch comment.
pub fn run(
    arena: Allocator,
    io: Io,
    file_paths: []const []const u8,
    color: Color,
    force_zon: bool,
    module_graph_path: ?[]const u8,
    want_json: bool,
) !void {
    // Loaded once and shared by every file below: the graph document is invariant across
    // the whole invocation, so re-reading and re-parsing its JSON per file (as the
    // single-file `checkAgainstGraph` path does, correctly, since it only ever runs once)
    // would be wasted work that grows with batch size for no benefit. See
    // `AstCheckImports.zig`'s `LoadedGraph` doc comment.
    const loaded_graph: ?AstCheckImports.LoadedGraph = if (module_graph_path) |p| lg: {
        switch (try AstCheckImports.loadAllowedNamesOrErr(arena, io, p)) {
            .ok => |loaded| break :lg loaded,
            .err => |msg| {
                // Doctrine 4 / rung-3 review item 10: `--json` must not leave stdout empty
                // on a fatal here. Non-`--json` mode reproduces the exact text and exit
                // code `fatal` would have printed directly before this rung-3 fix moved
                // graph-loading's failure path out of `AstCheckImports.loadGraph` and into
                // data (see that file's `loadAllowedNamesOrErr`).
                if (want_json) {
                    emitJsonError(arena, io, msg);
                    process.exit(1);
                }
                process.fatal("{s}", .{msg});
            },
        }
    } else null;

    const outcomes = try arena.alloc(CheckOutcome, file_paths.len);
    var checked: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var graph_not_applicable: usize = 0;
    var import_totals: AstCheckImports.Stats = .{};

    // Reused across every iteration (sequential, single-threaded): each file's read
    // completes -- source fully copied into `child_arena` by `readSourceFileToEndAlloc` --
    // before the next iteration touches this buffer again, the same reuse pattern
    // `main.zig` already relies on for its own module-level scratch buffer across unrelated
    // call sites.
    var read_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

    // Per-file scratch: `checkOneFile` and everything it calls allocate the source bytes,
    // `Ast`, `Zir`/`Zoir`, and any `ErrorBundle.Wip` from `child_arena`, reset at the top of
    // every iteration, rather than from the outer, process-lifetime `arena` -- measured at
    // ~475 KB/file, unbounded, when they shared `arena` (rung-3 review item 4). Only `path`
    // (already owned by the caller's `file_paths` slice, never allocated here), the
    // formatted skip `reason`, and the extracted `JsonError` strings -- via `arena.dupe`,
    // not `child_arena` -- are meant to outlive an iteration, and are allocated straight
    // from `arena` for exactly that reason.
    var child_arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer child_arena_state.deinit();

    for (file_paths, 0..) |path, i| {
        _ = child_arena_state.reset(.retain_capacity);
        const child_arena = child_arena_state.allocator();

        const outcome = try checkOneFile(arena, child_arena, io, path, color, force_zon, loaded_graph, want_json, &read_buffer);
        outcomes[i] = outcome;
        switch (outcome.status) {
            .ok => checked += 1,
            .failed => failed += 1,
            .skipped => skipped += 1,
        }
        if (outcome.json.graph_check != null) graph_not_applicable += 1;
        if (outcome.json.import_stats) |s| {
            import_totals.file_imports += s.file_imports;
            import_totals.named_imports += s.named_imports;
            import_totals.exempt += s.exempt;
            import_totals.skipped_nonliteral += s.skipped_nonliteral;
        }
    }

    const summary: JsonSummary = .{
        .requested = file_paths.len,
        .checked = checked,
        .failed = failed,
        .skipped = skipped,
        .graph_not_applicable = graph_not_applicable,
        .import_stats = import_totals,
    };

    if (want_json) {
        const files = try arena.alloc(JsonFile, outcomes.len);
        for (outcomes, 0..) |o, i| files[i] = o.json;
        try emitJson(arena, io, files, summary);
    } else {
        try printBatchSummary(io, summary, outcomes);
    }

    // A skip is not a pass (the plan's own words): exit nonzero whenever either bucket is
    // nonzero, not only on an outright compile failure.
    if (failed > 0 or skipped > 0) process.exit(1);
    return cleanExit(io);
}

/// Runs the full per-file pipeline for one path: open, read, parse, AstGen/ZonGen, and
/// (zig mode only, when requested) the rung-1 graph check. Never fails the batch on this
/// file's own account -- open/read failure becomes a `skipped` outcome with a named reason
/// (doctrine 2); everything past that point becomes `ok` or `failed`. Only genuine
/// allocation failure (`error.OutOfMemory`, propagated from `arena`/`child_arena`) aborts
/// the whole run, matching the single-file path's existing assumption that `Ast.parse`/
/// `AstGen.generate`/`ZonGen.generate` cannot otherwise fail (see their signatures: all
/// `Allocator.Error!_`).
fn checkOneFile(
    arena: Allocator,
    child_arena: Allocator,
    io: Io,
    path: []const u8,
    color: Color,
    force_zon: bool,
    loaded_graph: ?AstCheckImports.LoadedGraph,
    want_json: bool,
    read_buffer: []u8,
) !CheckOutcome {
    // `allow_directory = false`: without it, opening a directory SUCCEEDS (POSIX `open()`
    // on a directory is legal), and the failure only surfaces at the read below as the
    // generic `ReadFailed` -- the symptom, not the reason (rung-3 review item 9). With it,
    // `openFile` performs the extra `fstat` this option's own doc comment describes and
    // returns `error.IsDir` directly, so the existing `unable to open: {t}` reason below
    // already names a directory argument correctly with no new branch.
    var file = Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false }) catch |err| {
        const reason = try std.fmt.allocPrint(arena, "unable to open: {t}", .{err});
        return .{ .status = .skipped, .json = .{ .path = path, .status = "skipped", .reason = reason } };
    };
    defer file.close(io);

    var file_reader: Io.File.Reader = file.reader(io, read_buffer);
    const source: [:0]const u8 = std.zig.readSourceFileToEndAlloc(child_arena, &file_reader) catch |err| {
        const reason = try std.fmt.allocPrint(arena, "unable to read: {t}", .{err});
        return .{ .status = .skipped, .json = .{ .path = path, .status = "skipped", .reason = reason } };
    };

    const mode = resolveMode(force_zon, path);
    const tree = try Ast.parse(child_arena, source, mode);

    return switch (mode) {
        .zig => checkZigFile(arena, child_arena, io, tree, source, path, color, loaded_graph, want_json),
        .zon => checkZonFile(arena, child_arena, io, tree, source, path, color, want_json, loaded_graph != null),
    };
}

/// Mode resolution mirrors `cmdAstCheck`'s single-file logic exactly (`--zon` forces every
/// file in the batch, same as it forces the one file in single-file mode; otherwise the
/// `.zon` extension decides per file) -- "the existing per-file mode resolution," as the
/// plan's guardrail names it, applied per file rather than once.
fn resolveMode(force_zon: bool, path: []const u8) Ast.Mode {
    if (force_zon) return .zon;
    if (mem.endsWith(u8, path, ".zon")) return .zon;
    return .zig;
}

/// Zig-mode pipeline for one file: AstGen, then -- only on a clean AstGen pass, exactly the
/// precondition rung 1 already requires -- the graph check, when `--module-graph` was given.
/// A `.zon` file inside a mixed batch never reaches here at all (see `checkZonFile`): the
/// module graph simply has nothing to check on a document that cannot contain `@import`.
/// `arena` is the outer, whole-run allocator (only values that must outlive this file's
/// iteration go there); `child_arena` is this file's per-iteration scratch, reset by the
/// caller once this returns (rung-3 review item 4).
fn checkZigFile(
    arena: Allocator,
    child_arena: Allocator,
    io: Io,
    tree: Ast,
    source: [:0]const u8,
    path: []const u8,
    color: Color,
    loaded_graph: ?AstCheckImports.LoadedGraph,
    want_json: bool,
) !CheckOutcome {
    const zir = try AstGen.generate(child_arena, tree);

    if (zir.hasCompileErrors()) {
        var wip_errors: ErrorBundle.Wip = undefined;
        try wip_errors.init(child_arena);
        try wip_errors.addZirErrorMessages(zir, tree, source, path);
        const bundle = try wip_errors.toOwnedBundle("");

        // A render failure (e.g. EPIPE from `zig ast-check *.zig | head`) must not abort
        // the rest of the batch -- this file's own top-comment guarantee. Mirrors the
        // `.zon` arm's `catch {}` below, extended here to the `.zig` arm (rung-3 review
        // item 8: this arm previously used `try` and so could lose files k+1..N on exactly
        // this failure).
        if (!want_json) bundle.renderToStderr(io, .{}, color) catch {};

        return .{
            .status = .failed,
            .json = .{ .path = path, .status = "failed", .errors = try extractErrors(arena, bundle) },
        };
    }

    if (loaded_graph) |loaded| {
        var wip_errors: ErrorBundle.Wip = undefined;
        try wip_errors.init(child_arena);
        // `zig_source_path` and `display_path` are the same value here, exactly as they are
        // at the single-file call site once `zig_source_path.?` is known non-null (see
        // `cmdAstCheck`): every batch entry is a real path, never stdin.
        const result = try AstCheckImports.collectGraphViolations(child_arena, io, tree, path, path, loaded, &wip_errors);
        // `Stats` is plain numbers (no slices), so it survives `child_arena`'s reset by
        // value with no dup needed -- unlike the `ErrorBundle`-derived strings below
        // (rung-3 review item 2, item 7).
        const import_stats = result.stats;

        if (result.had_error) {
            const bundle = try wip_errors.toOwnedBundle("");
            // Same order as the single-file path (`AstCheckImports.checkAgainstGraph`):
            // render the violations, then the one honest-denominator summary line. Same
            // `catch {}` reasoning as the AstGen-error render above (rung-3 review item 8).
            if (!want_json) {
                bundle.renderToStderr(io, .{}, color) catch {};
                try AstCheckImports.printSummary(io, result.stats, path);
            }
            return .{
                .status = .failed,
                .json = .{
                    .path = path,
                    .status = "failed",
                    .errors = try extractErrors(arena, bundle),
                    .import_stats = import_stats,
                },
            };
        }

        if (!want_json) try AstCheckImports.printSummary(io, result.stats, path);
        return .{ .status = .ok, .json = .{ .path = path, .status = "ok", .import_stats = import_stats } };
    }

    return .{ .status = .ok, .json = .{ .path = path, .status = "ok" } };
}

/// ZON-mode pipeline for one file: ZonGen only. `--module-graph` never applies to `.zon`
/// (`AstCheckImports.zig`'s top comment: ZON documents cannot contain `@import`), so unlike
/// the single-file path -- which hard-refuses `--module-graph` on a `.zon` input because
/// that is the *only* thing the invocation would otherwise have to do -- a `.zon` file
/// inside a batch simply has nothing to check on that axis and is never a fatal condition
/// for the batch: the plan's "never aborts the batch" guarantee takes priority once other
/// files are also in play. `graph_requested` (true iff `--module-graph` was given at all)
/// drives `JsonFile.graph_check`, so this non-applicability is stated in `--json` output
/// rather than silently doing nothing (rung-3 review item 3(b); the human-mode equivalent
/// is the batch summary's `graph_not_applicable` count, in `printBatchSummary` below). It
/// still runs ZonGen and can still fail on its own ZON errors.
fn checkZonFile(
    arena: Allocator,
    child_arena: Allocator,
    io: Io,
    tree: Ast,
    source: [:0]const u8,
    path: []const u8,
    color: Color,
    want_json: bool,
    graph_requested: bool,
) !CheckOutcome {
    const zoir = try ZonGen.generate(child_arena, tree, .{});
    const graph_check: ?[]const u8 = if (graph_requested) "not_applicable_zon" else null;

    if (zoir.hasCompileErrors()) {
        var wip_errors: ErrorBundle.Wip = undefined;
        try wip_errors.init(child_arena);
        try wip_errors.addZoirErrorMessages(zoir, tree, source, path);
        const bundle = try wip_errors.toOwnedBundle("");

        // Mirrors the single-file zon branch's own `catch {}` on the render call
        // (`cmdAstCheck`'s `.zon` switch arm): a render failure must not stop diagnostics
        // extraction below, in either output mode.
        if (!want_json) bundle.renderToStderr(io, .{}, color) catch {};

        return .{
            .status = .failed,
            .json = .{
                .path = path,
                .status = "failed",
                .errors = try extractErrors(arena, bundle),
                .graph_check = graph_check,
            },
        };
    }

    return .{
        .status = .ok,
        .json = .{ .path = path, .status = "ok", .graph_check = graph_check },
    };
}

/// Extracts every top-level message in `eb` into JSON-shaped values, reading `ErrorBundle`'s
/// own accessors rather than its rendered text (this file's top comment, doctrine 5).
/// `eb.extra.len == 0` is `ErrorBundle`'s own "no errors" encoding (see its doc comment).
fn extractErrors(arena: Allocator, eb: ErrorBundle) Allocator.Error![]JsonError {
    if (eb.extra.len == 0) return &.{};
    const messages = eb.getMessages();
    const out = try arena.alloc(JsonError, messages.len);
    for (messages, 0..) |m, i| out[i] = try extractMessage(arena, eb, m);
    return out;
}

/// Extracts one message (and, recursively, its notes) from `eb`. `line`/`column` are left at
/// their zero default when the message has no source location (`src_loc == .none`, e.g. a
/// bare compile-log-style message) -- absent-not-zero would be more honest per doctrine 2,
/// but `line`/`column` are `u32` here (matching `ErrorBundle.SourceLocation`'s own field
/// types) rather than optional, so a JSON consumer must already treat a message with no
/// accompanying source excerpt as the caller's cue: check `ErrorBundle.getErrorMessage`'s
/// `src_loc` before trusting `line`/`column` on the human-rendering path too.
fn extractMessage(arena: Allocator, eb: ErrorBundle, index: ErrorBundle.MessageIndex) Allocator.Error!JsonError {
    const msg = eb.getErrorMessage(index);
    var line: u32 = 0;
    var column: u32 = 0;
    if (msg.src_loc != .none) {
        const loc = eb.getSourceLocation(msg.src_loc);
        // ErrorBundle stores 0-based line/column; +1 to match renderErrorMessage's own
        // human-facing convention (ErrorBundle.zig), so JSON and text output agree.
        line = loc.line + 1;
        column = loc.column + 1;
    }

    const note_indices = eb.getNotes(index);
    const notes = try arena.alloc(JsonError, note_indices.len);
    for (note_indices, 0..) |note_index, i| notes[i] = try extractMessage(arena, eb, note_index);

    return .{
        // `eb` (and the string bytes `nullTerminatedString` points into) is owned by the
        // per-file `child_arena` and is reset next iteration; `arena` here is the outer,
        // whole-run arena this `JsonError` tree must survive into -- so the text is copied,
        // not merely referenced (rung-3 review item 4).
        .msg = try arena.dupe(u8, eb.nullTerminatedString(msg.msg)),
        .line = line,
        .column = column,
        .count = msg.count,
        .notes = notes,
    };
}

/// Writes the one `--json` document to stdout: `files` (already status-classified) plus the
/// batch `summary`. Built into an arena-backed buffer first (mirroring
/// `Compilation/EmitModuleGraph.zig`'s `buildJson`, the fork's other JSON emitter) so a
/// `std.json.Stringify` failure can only ever be `error.OutOfMemory`, never a partial write.
fn emitJson(arena: Allocator, io: Io, files: []const JsonFile, summary: JsonSummary) !void {
    const doc: JsonDoc = .{ .files = files, .summary = summary };

    var aw: std.Io.Writer.Allocating = .init(arena);
    std.json.Stringify.value(doc, .{ .whitespace = .indent_2 }, &aw.writer) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    const json = try aw.toOwnedSlice();

    var buffer: [4096]u8 align(std.heap.page_size_min) = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout_writer.interface;
    try w.writeAll(json);
    try w.writeByte('\n');
    try w.flush();
}

/// Writes the minimal `{"error": "..."}` document described in this file's top comment.
/// Best-effort: this only runs on a path that is about to `process.exit(1)` regardless, so
/// a failure writing the error document itself is swallowed rather than propagated (mirrors
/// this file's own `.zon` render-failure handling elsewhere).
fn emitJsonError(arena: Allocator, io: Io, msg: []const u8) void {
    const doc: JsonErrorDoc = .{ .@"error" = msg };
    var aw: std.Io.Writer.Allocating = .init(arena);
    std.json.Stringify.value(doc, .{ .whitespace = .indent_2 }, &aw.writer) catch return;
    const json = aw.toOwnedSlice() catch return;

    var buffer: [4096]u8 align(std.heap.page_size_min) = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout_writer.interface;
    w.writeAll(json) catch return;
    w.writeByte('\n') catch return;
    w.flush() catch return;
}

/// The one batch summary line the plan requires (doctrine 4, self-report), printed to
/// stderr after every file has run -- pass, fail, or skip -- so `requested = checked +
/// failed + skipped` is always visible and reconcilable, never inferred from silence.
fn printBatchSummary(io: Io, summary: JsonSummary, outcomes: []const CheckOutcome) !void {
    var buffer: [512]u8 align(std.heap.page_size_min) = undefined;
    const locked = try io.lockStderr(&buffer, null);
    defer io.unlockStderr();
    const w = &locked.file_writer.interface;

    try w.print("files: requested {d}, checked {d}, failed {d}, skipped {d}", .{
        summary.requested, summary.checked, summary.failed, summary.skipped,
    });
    // "a skip is not a pass": say so plainly whenever the denominator includes one, rather
    // than making the reader notice `skipped > 0` themselves in a wall of numbers.
    if (summary.skipped > 0) try w.writeAll(" (skips are not passes)");
    // --module-graph requested but not applicable to every file in the batch (rung-3
    // review item 3(b)): named here rather than silently doing nothing on those files.
    if (summary.graph_not_applicable > 0) {
        try w.print(" ({d} .zon file(s) not checked against --module-graph: ZON has no imports)", .{summary.graph_not_applicable});
    }
    try w.writeByte('\n');

    for (outcomes) |o| {
        if (o.status != .skipped) continue;
        try w.print("skipped: {s}: {s}\n", .{ o.json.path, o.json.reason orelse "unknown reason" });
    }

    try w.flush();
}
