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
//! graph_check?,check_semantics?,as_module_name?,decl_stats?}],summary:{requested,checked,
//! failed,skipped,graph_not_applicable,import_stats,decl_stats}}`. `import_stats` (both
//! per-file and the summary's aggregate total) is rung 1's honest-denominator
//! `AstCheckImports.Stats`, carried into `--json` rather than discarded (rung-3 review item
//! 2: PLAN.md's own charter for this rung is "diagnostics available as machine-readable
//! JSON... without scraping"). `check_semantics`/`as_module_name` are Crown stage 0.5 rung
//! 4 (`docs/crown/PLAN.md` "Stage 0.5" item 4): present under the same condition as
//! `import_stats` (`--module-graph` requested, `.zig` file), naming whether this file's
//! named imports were validated under rung 1's graph-wide "union" semantics (default) or
//! rung 4's per-module "strict" semantics (once `--as-module` is bound -- see `main.zig`'s
//! `usage_ast_check`: one `--as-module` binds every `.zig` member of a batch, there is no
//! per-file binding). `decl_stats` (per-file and the summary's aggregate) is rung 2's
//! honest-denominator `AstCheckImports.DeclStats`, present only when `--check-decls` was
//! requested and this file is a `.zig` file; absent on a `.zon` row for the same reason
//! `import_stats` is -- ZON has no imports and no declarations, so the field's absence on
//! a `.zon` row (paired with `graph_check`'s `"not_applicable_zon"`) is the statement of
//! non-applicability, never a silent skip. `graph_check`, present only
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
    /// Rung 4: "union" or "strict" -- see this file's top comment. Non-null under exactly
    /// the same condition as `import_stats` above (`--module-graph` requested, `.zig`
    /// file); null on any row where no import check ran at all, so its presence is never
    /// ambiguous with "checked, and it happened to be rung 1's default."
    check_semantics: ?[]const u8 = null,
    /// The bound module's `fully_qualified_name` -- set only when `check_semantics ==
    /// "strict"`, i.e. only once `--as-module` resolved successfully.
    as_module_name: ?[]const u8 = null,
    /// Rung 2: `--check-decls`' honest-denominator stats for this file, present only when
    /// `--check-decls` was requested and this is a `.zig` file that ran the full pipeline.
    /// The strings `check_semantics`/`as_module_name` point into are whole-run `arena`
    /// allocations (the graph and binding are loaded/resolved once, before the per-file
    /// loop), so they outlive `child_arena`'s reset with no dup; `DeclStats` is plain
    /// numbers, like `Stats`, so it survives by value.
    decl_stats: ?AstCheckImports.DeclStats = null,
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
    /// Rung 2: the summed `AstCheckImports.DeclStats` across every decl-checked `.zig`
    /// file -- all-zero when `--check-decls` was not requested, the same all-zero
    /// convention `import_stats` keeps when no file was graph-checked.
    decl_stats: AstCheckImports.DeclStats = .{},
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
/// never empty, `-t` has already been refused by the caller, and `as_module_spec` /
/// `check_decls` are non-default only alongside `module_graph_path` (the caller refuses
/// both by name otherwise -- see its dispatch comment) -- see its dispatch comment.
pub fn run(
    arena: Allocator,
    io: Io,
    file_paths: []const []const u8,
    color: Color,
    force_zon: bool,
    module_graph_path: ?[]const u8,
    /// Crown stage 0.5 rung 4: `--as-module`'s value. Resolved once below and reused for
    /// every `.zig` member of the batch -- "one `--as-module` binds ALL `.zig` members";
    /// there is no per-file binding.
    as_module_spec: ?[]const u8,
    /// Crown stage 0.5 rung 2: `--check-decls`. Its two preconditions (the document's
    /// rung-2 fields, and the resolution base) are gated once below for the whole batch,
    /// refusing the run by name rather than failing per file.
    check_decls: bool,
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

    // Crown stage 0.5 rung 4: resolved once and reused for every `.zig` member of the
    // batch. `loaded_graph.?` is guarded by the caller, not assumed: `cmdAstCheck`
    // (`main.zig`) refuses `--as-module` without `--module-graph` before ever dispatching
    // here, so the graph is loaded whenever a binding is requested -- the same
    // caller-guards-the-invariant shape the single-file path's `zig_source_path.?` already
    // relies on. A failed resolution refuses the whole run by name (doctrine 2: the
    // requested check could not run at all), through this output mode's own shape.
    const binding: ?AstCheckImports.ModuleBinding = if (as_module_spec) |spec| bnd: {
        switch (try AstCheckImports.resolveAsModule(arena, io, loaded_graph.?, spec)) {
            .ok => |b| break :bnd b,
            .err => |msg| {
                // Same doctrine-4 reasoning as the graph-load failure above.
                if (want_json) {
                    emitJsonError(arena, io, msg);
                    process.exit(1);
                }
                process.fatal("{s}", .{msg});
            },
        }
    } else null;

    // Crown stage 0.5 rung 2's two preconditions, gated once for the whole batch (a
    // document that cannot support `--check-decls`, or an unresolvable base, is a property
    // of the invocation, not of any one file): the schema gate refuses through
    // `AstCheckImports.checkDeclsRefusal` -- the same single owner the single-file driver
    // surfaces -- and `resolveGraphBase` declares the same-cwd contract. `module_graph.?`
    // is guarded exactly like `loaded_graph.?` above.
    var graph_base: []const u8 = "";
    if (check_decls) {
        if (try AstCheckImports.checkDeclsRefusal(arena, module_graph_path.?, loaded_graph.?)) |msg| {
            if (want_json) {
                emitJsonError(arena, io, msg);
                process.exit(1);
            }
            process.fatal("{s}", .{msg});
        }
        graph_base = switch (try AstCheckImports.resolveGraphBase(arena, io)) {
            .ok => |b| b,
            .err => |msg| {
                if (want_json) {
                    emitJsonError(arena, io, msg);
                    process.exit(1);
                }
                process.fatal("{s}", .{msg});
            },
        };
    }

    const outcomes = try arena.alloc(CheckOutcome, file_paths.len);
    var checked: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var graph_not_applicable: usize = 0;
    var import_totals: AstCheckImports.Stats = .{};
    var decl_totals: AstCheckImports.DeclStats = .{};

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

        const outcome = try checkOneFile(arena, child_arena, io, path, color, force_zon, loaded_graph, binding, check_decls, graph_base, want_json, &read_buffer);
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
            // Rung 4's fifth field, summed like the other four so the aggregate's
            // `Stats.total()` reconciles against the per-file rows' totals -- an honest
            // denominator must not silently drop a counted category at the summation
            // seam, even though the field is zero on every rung-1/rung-3-shaped run.
            import_totals.sandbox_unresolvable += s.sandbox_unresolvable;
        }
        if (outcome.json.decl_stats) |s| addDeclStats(&decl_totals, s);
    }

    const summary: JsonSummary = .{
        .requested = file_paths.len,
        .checked = checked,
        .failed = failed,
        .skipped = skipped,
        .graph_not_applicable = graph_not_applicable,
        .import_stats = import_totals,
        .decl_stats = decl_totals,
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
    binding: ?AstCheckImports.ModuleBinding,
    check_decls: bool,
    graph_base: []const u8,
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
        .zig => checkZigFile(arena, child_arena, io, tree, source, path, color, loaded_graph, binding, check_decls, graph_base, want_json),
        .zon => checkZonFile(arena, child_arena, io, tree, source, path, color, want_json, loaded_graph != null),
    };
}

/// Sums rung 2's per-file `DeclStats` into the batch aggregate -- the same field-by-field
/// accumulation `run`'s loop does inline for rung 1's `Stats`, factored out only because
/// `DeclStats` has thirteen counters rather than four (eight member-reference, five
/// direct-call arity -- two populations, both summed, so both of `total()` and
/// `arityTotal()` reconcile against the per-file rows). Plain numbers, no slices, so no
/// lifetime concerns (rung-3 review item 4's boundary does not apply here).
fn addDeclStats(total: *AstCheckImports.DeclStats, s: AstCheckImports.DeclStats) void {
    total.validated += s.validated;
    total.missing += s.missing;
    total.opaque_skipped += s.opaque_skipped;
    total.alias_too_deep += s.alias_too_deep;
    total.target_unresolvable += s.target_unresolvable;
    total.target_unreadable += s.target_unreadable;
    total.operand_unparsable += s.operand_unparsable;
    total.exempt += s.exempt;
    total.arity_matched += s.arity_matched;
    total.arity_mismatch += s.arity_mismatch;
    total.arity_skipped_dynamic += s.arity_skipped_dynamic;
    total.arity_skipped_non_fn += s.arity_skipped_non_fn;
    total.arity_unavailable += s.arity_unavailable;
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
/// precondition rung 1 already requires -- the graph check, when `--module-graph` was given,
/// composed with rung 2's decl check (`--check-decls`) into the same per-file bundle, under
/// rung 4's strict semantics when `--as-module` bound this run (`binding`, resolved once by
/// `run`).
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
    binding: ?AstCheckImports.ModuleBinding,
    check_decls: bool,
    graph_base: []const u8,
    want_json: bool,
) !CheckOutcome {
    // Retained correction 8 (allocation honesty per retained correction 9): AstGen's
    // identifier-binding sidecar is requested ONLY when rung 2 will run (`check_decls`
    // -- which `cmdAstCheck` already refused without `--module-graph`, so this is
    // exactly the rung-2 population); every other batch shape never REQUESTS it and
    // stays on the ordinary `generate` path with zero sidecar allocations. A
    // `check_decls` file whose lowering produces diagnostics is DIFFERENT: the sidecar
    // was requested before lowering and may have allocated facts on the way to the
    // failure -- the lowering clears them before publication -- so that path is
    // requested-then-cleared, never zero-allocation. The sidecar is owned here for
    // this file's iteration and released by the `defer` immediately below on every
    // path out of this function -- render failures, early `failed` returns, and
    // success alike (the AstGen-error return included, where the facts were cleared
    // by the lowering itself and this merely frees the storage).
    var generated: ?AstGen.GeneratedWithIdentifierBindings = if (check_decls)
        try AstGen.generateWithIdentifierBindings(child_arena, tree)
    else
        null;
    defer if (generated) |*g| g.bindings.deinit(child_arena);
    const bindings: ?*const AstGen.IdentifierBindings = if (generated) |*g| &g.bindings else null;
    const zir = if (generated) |*g| g.zir else try AstGen.generate(child_arena, tree);

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
        const result = try AstCheckImports.collectGraphViolations(child_arena, io, tree, path, path, loaded, binding, &wip_errors);
        var had_error = result.had_error;
        // `Stats` is plain numbers (no slices), so it survives `child_arena`'s reset by
        // value with no dup needed -- unlike the `ErrorBundle`-derived strings below
        // (rung-3 review item 2, item 7).
        const import_stats = result.stats;
        // Rung 4: "strict" once --as-module bound this run, else rung 1's original
        // "union" -- see `JsonFile.check_semantics`'s doc comment. `binding.
        // fully_qualified_name` is a whole-run `arena` string (the binding is resolved
        // once, before the per-file loop), so it survives `child_arena`'s reset like
        // `import_stats` above; no dup is needed here either.
        const check_semantics: []const u8 = if (binding != null) "strict" else "union";
        const as_module_name: ?[]const u8 = if (binding) |b| b.fully_qualified_name else null;

        // Rung 2 (`--check-decls`), composed into the SAME `wip_errors`/`had_error` rung 1
        // just used -- one bundle per file carrying both rungs' violations, exactly as the
        // single-file driver composes them (`AstCheckImports.checkAgainstGraph`). Only
        // ever reached with a loaded graph: `cmdAstCheck` refuses `--check-decls` without
        // `--module-graph` before dispatching here. `graph_base` is the whole-run value
        // `run` established above. `binding` threads rung 4's binding into rung 2's
        // named-target selection (retained correction 6): null keeps the graph-wide
        // union, non-null selects through the bound module's own dep table -- the same
        // strict/union split `check_semantics` states for the import check. `bindings.?`
        // is retained correction 8's sidecar, non-null by the same `check_decls` key
        // that both the opt-in above and this block hinge on.
        var decl_stats: AstCheckImports.DeclStats = .{};
        if (check_decls) {
            const checked_dir = std.fs.path.dirname(path) orelse ".";
            try AstCheckImports.checkDeclExistence(child_arena, io, tree, path, checked_dir, graph_base, loaded, binding, bindings.?, &wip_errors, &had_error, &decl_stats);
        }
        const decl_stats_json: ?AstCheckImports.DeclStats = if (check_decls) decl_stats else null;

        if (had_error) {
            const bundle = try wip_errors.toOwnedBundle("");
            // Same order as the single-file path (`AstCheckImports.checkAgainstGraph`):
            // render the violations, then the honest-denominator summary lines (rung 1's,
            // then rung 2's when it ran). Same `catch {}` reasoning as the AstGen-error
            // render above (rung-3 review item 8).
            if (!want_json) {
                bundle.renderToStderr(io, .{}, color) catch {};
                try AstCheckImports.printSummary(io, result.stats, path, binding);
                if (check_decls) try AstCheckImports.printDeclSummary(io, decl_stats, path);
            }
            return .{
                .status = .failed,
                .json = .{
                    .path = path,
                    .status = "failed",
                    .errors = try extractErrors(arena, bundle),
                    .import_stats = import_stats,
                    .check_semantics = check_semantics,
                    .as_module_name = as_module_name,
                    .decl_stats = decl_stats_json,
                },
            };
        }

        if (!want_json) {
            try AstCheckImports.printSummary(io, result.stats, path, binding);
            if (check_decls) try AstCheckImports.printDeclSummary(io, decl_stats, path);
        }
        return .{ .status = .ok, .json = .{
            .path = path,
            .status = "ok",
            .import_stats = import_stats,
            .check_semantics = check_semantics,
            .as_module_name = as_module_name,
            .decl_stats = decl_stats_json,
        } };
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
