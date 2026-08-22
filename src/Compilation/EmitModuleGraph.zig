//! Serializes the resolved module graph (the Crown's stage 0) to JSON.
//!
//! See `docs/crown/PLAN.md` (the stage table) and `docs/crown/INTERNALS_MAP.md` section 5
//! ("Stage-0 landing sites") for the design this file implements; the map's citations are
//! the source of truth for *why* this hooks where it does.
//!
//! This is called from `Compilation.create`, right after `pt.populateModuleRootTable()`
//! returns ("Site A" in INTERNALS_MAP.md 5.3): at that instant `zcu.module_roots` holds
//! every module, including builtins, and no analysis has run yet. That makes it the
//! cheapest possible hook for a pure *declared graph* dump -- with one caveat: this point
//! is strictly pre-AstGen, so per-module file membership (which files besides the root a
//! module ends up pulling in) is not yet knowable here. This emitter therefore reports
//! only what `module_roots` and each `Package.Module` already carry -- module identity,
//! declared root/root_src_path, dependency edges, and the per-module knobs that matter for
//! caching -- and does not attempt to enumerate files. A later stage needing file-level
//! data will need a different, post-AstGen hook.
//!
//! Schema caveat, known and accepted for stage 0: `std.json.Stringify` gates string
//! encoding on UTF-8 validity (`lib/std/json/Stringify.zig`, the
//! `utf8ValidateSlice` check) and falls back to emitting invalid-UTF-8 byte slices as
//! JSON arrays of integers. POSIX paths are arbitrary bytes, so on a non-UTF-8 module
//! root the `root`/`root_src_path` fields change JSON type from string to int-array.
//! Consumers must tolerate that shape; a later stage may normalize instead.
//!
//! `buildJson` only touches `arena`-allocated memory, so it can only fail with
//! `error.OutOfMemory`, matching `Compilation.create`'s `CreateError`. Note that
//! `comp.cache_use` is still `undefined` at this point in `create()` (it is populated a
//! little later -- see the `comp.cache_use = .{ ... }` assignments further down in
//! `Compilation.zig`), so `Compilation.resolveEmitPath` is not safe to call yet and the
//! actual file write is deferred to `worker`, dispatched later from `performAllTheWork`
//! the same way `-femit-docs` dispatches `workerDocsCopy`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Compilation = @import("../Compilation.zig");
const Zcu = @import("../Zcu.zig");
const Package = @import("../Package.zig");

/// One node in the emitted graph: a single resolved `Package.Module`.
const ModuleNode = struct {
    /// Index into `zcu.module_roots` at serialization time. Stable within this document
    /// only. Deliberately not keyed by `fully_qualified_name`, which is a caller
    /// convention, not a guaranteed-unique identity (INTERNALS_MAP.md 5.4).
    index: usize,
    fully_qualified_name: []const u8,
    /// Rendered with `Compilation.Path.fmt`, the same formatter the compiler uses for
    /// diagnostics involving module roots.
    root: []const u8,
    root_src_path: []const u8,
    optimize_mode: std.builtin.OptimizeMode,
    strip: bool,
    single_threaded: bool,
    code_model: std.builtin.CodeModel,
    deps: []const DepEdge,
};

/// One entry of `Package.Module.deps`: the import name the *importing* module uses,
/// resolved to the dependency module.
const DepEdge = struct {
    import_name: []const u8,
    /// Null only if the dependency module was not found in `module_roots` at this hook.
    /// `Package.Module.deps` never stores the std/root/builtin shortcuts (see
    /// `Package/Module.zig`'s doc comment on `deps`), and `module_roots` is documented to
    /// contain all modules including builtins (`Zcu.zig`'s doc comment on
    /// `module_roots`) -- but INTERNALS_MAP.md open question 2 flags that the exact
    /// window in which builtins are present was not empirically pinned down. Recording
    /// `null` here rather than asserting means a violated assumption shows up in the
    /// JSON instead of a panic.
    dep_index: ?usize,
    dep_fully_qualified_name: []const u8,
};

/// A module that seeds analysis reachability. Mirrors the `analysis_roots_buffer`
/// construction in `Compilation.update` (`Compilation.zig`, roughly lines 3038-3077),
/// reproduced here because the data it reads (`zcu.std_mod`, `zcu.main_mod`,
/// `zcu.root_mod.deps`) is already populated by this hook's call site -- well before
/// `update()` ever runs.
const GraphRoot = struct {
    role: []const u8,
    /// Null if the role's module was not found in `module_roots`; see `DepEdge.dep_index`.
    index: ?usize,
};

const Graph = struct {
    modules: []const ModuleNode,
    roots: []const GraphRoot,
};

/// Builds the module-graph JSON document. Called once, synchronously, from
/// `Compilation.create`.
pub fn buildJson(arena: Allocator, comp: *Compilation, zcu: *Zcu) Allocator.Error![]const u8 {
    const mods = zcu.module_roots.keys();

    var index_of: std.AutoHashMapUnmanaged(*Package.Module, usize) = .empty;
    try index_of.ensureTotalCapacity(arena, @intCast(mods.len));
    for (mods, 0..) |mod, i| index_of.putAssumeCapacity(mod, i);

    const nodes = try arena.alloc(ModuleNode, mods.len);
    for (mods, 0..) |mod, i| {
        const dep_names = mod.deps.keys();
        const dep_mods = mod.deps.values();
        const edges = try arena.alloc(DepEdge, dep_names.len);
        for (dep_names, dep_mods, 0..) |name, dep_mod, j| {
            edges[j] = .{
                .import_name = name,
                .dep_index = index_of.get(dep_mod),
                .dep_fully_qualified_name = dep_mod.fully_qualified_name,
            };
        }
        nodes[i] = .{
            .index = i,
            .fully_qualified_name = mod.fully_qualified_name,
            .root = try std.fmt.allocPrint(arena, "{f}", .{mod.root.fmt(comp)}),
            .root_src_path = mod.root_src_path,
            .optimize_mode = mod.optimize_mode,
            .strip = mod.strip,
            .single_threaded = mod.single_threaded,
            .code_model = mod.code_model,
            .deps = edges,
        };
    }

    var roots: std.ArrayList(GraphRoot) = .empty;
    try roots.append(arena, .{ .role = "std", .index = index_of.get(zcu.std_mod) });
    // The main module seeds reachability separately from `std` only for tests, where it
    // differs from `std_mod` -- mirrors `Compilation.update`'s identical condition.
    if (comp.config.is_test and zcu.main_mod != zcu.std_mod) {
        try roots.append(arena, .{ .role = "main", .index = index_of.get(zcu.main_mod) });
    }
    for ([_][]const u8{ "compiler_rt", "ubsan_rt", "zigc" }) |dep_name| {
        if (zcu.root_mod.deps.get(dep_name)) |dep_mod| {
            try roots.append(arena, .{ .role = dep_name, .index = index_of.get(dep_mod) });
        }
    }

    const graph: Graph = .{ .modules = nodes, .roots = roots.items };

    var aw: std.Io.Writer.Allocating = .init(arena);
    std.json.Stringify.value(graph, .{ .whitespace = .indent_2 }, &aw.writer) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    return try aw.toOwnedSlice();
}

/// Dispatched from `performAllTheWork`, mirroring `workerDocsCopy`
/// (`Compilation.zig:4508-4512`). By now `comp.cache_use` is populated, so
/// `comp.resolveEmitPath` is safe to call, unlike at the `buildJson` call site.
pub fn worker(comp: *Compilation) void {
    // An explicitly requested emission must never silently no-op: `module_graph_json`
    // is null here iff there was no `Zcu` at the `create()` hook site (e.g.
    // `zig build-obj foo.c -femit-module-graph`). Diagnose, mirroring
    // `workerDocsCopy`'s "no Zig code to document" precedent, rather than writing
    // nothing and exiting 0.
    if (comp.module_graph_json == null) return comp.lockAndSetMiscFailure(
        .module_graph_emit,
        "no Zig modules to graph: -femit-module-graph requires Zig code in the compilation",
        .{},
    );
    writeFallible(comp) catch |err| return comp.lockAndSetMiscFailure(
        .module_graph_emit,
        "unable to write module graph: {t}",
        .{err},
    );
}

fn writeFallible(comp: *Compilation) !void {
    const io = comp.io;
    // Non-null: `worker` diagnosed the null case before calling us.
    const json = comp.module_graph_json.?;
    const emit_path = comp.resolveEmitPath(comp.emit_module_graph.?);
    var file = try emit_path.root_dir.handle.createFile(io, emit_path.sub_path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    try file_writer.interface.writeAll(json);
    try file_writer.end();
}
