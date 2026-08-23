//! Ranks the resolved module graph by composition order: how deep a module sits above the
//! leaves, and how much of the build is waiting on it.
//!
//! This is ORDER 2's input — *"it must compile from the smallest to the most composed
//! part, so it starts with edges"* — reduced to two numbers per module.
//!
//! ## What "edges first" can and cannot mean inside a compilation
//!
//! It cannot mean "analyse the leaf modules first", and that limit is a language
//! property, not a scheduling choice. A fresh Zig build is DEMAND-DRIVEN: analysis is
//! seeded with only the analysis roots' own files, and the comment at
//! `Zcu/PerThread.zig:315-321` states the seeding rule exactly — declarations that want
//! eager analysis (`comptime` declarations, `export`s, and `test`s in the main module of
//! a test compilation) become referenced, and everything else is analysed only when
//! something references it. Eagerly analysing a leaf module's declarations would analyse
//! code the program never references, which changes which errors the program produces.
//! That is language divergence, and `PROVENANCE.md`'s commitments forbid it.
//!
//! What it CAN mean, and what this ranking is for:
//!
//! > Edges-first is a PRIORITY over the ready set, never a change to the set. The same
//! > units get analysed; the ones nearest the leaves and most depended-upon get analysed
//! > sooner.
//!
//! That is free of semantic consequence — `Zcu.findOutdatedToAnalyze` already documents
//! itself as a priority function whose choice is a performance decision
//! (`Zcu.zig:3285-3289`) — and it is what the charter asks for functionally: unblock the
//! most downstream work earliest.
//!
//! ## Where this runs, and why it is cheap
//!
//! At "Site A" in `Compilation.create`, immediately after `pt.populateModuleRootTable()`
//! returns: `zcu.module_roots` holds every module and no analysis has run. One O(V+E)
//! walk over `Package.Module.deps`, into the compilation's arena, never touched again.
//! `EmitModuleGraph.buildJson` already walks the same structure at the same instant.
//!
//! ## Two approximations, declared rather than hidden
//!
//! 1. **The implicit `std` edge is included; `builtin` and `root` are not.**
//!    `Package.Module.deps` deliberately omits all three (`Package/Module.zig:9-14`).
//!    `std` is added back because it is a real, universal dependency and
//!    `zcu.std_mod` names it unambiguously. `builtin` is not, because a `builtin` module
//!    has no dependencies of its own: adding those edges cannot change any other module's
//!    depth, only the `builtin` modules' own, and those are generated files that never
//!    compete for analysis priority. `root` is a self-referential alias rather than a
//!    structural edge. The dossier asks for all three; this ships one and states why the
//!    other two are inconsequential rather than merely omitted.
//! 2. **Module import graphs may legally contain cycles.** Two modules can import each
//!    other, and while a `-M` dependency table usually does not, "usually" is not a
//!    guarantee, and a ranking pass that hangs or asserts on a legal graph is a worse bug
//!    than a bad order. The walk below is cycle-tolerant: a back-edge to an in-progress
//!    module contributes depth 0 and the module is recorded in `cyclic`, which the caller
//!    reports.

const ModuleRanking = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Zcu = @import("../Zcu.zig");
const Package = @import("../Package.zig");
const Module = Package.Module;

/// Composition position of one module. Eight bytes, arena-allocated, immutable after
/// `build` returns.
pub const Rank = struct {
    /// Longest path down to a leaf over the dependency edges. Leaves are 0. Ascending
    /// depth is the composition order the charter names: everything at depth `d` is
    /// built out of things at depths below `d`.
    depth: u32,
    /// In-degree — how many modules depend on this one. `Package.Module.deps` is
    /// out-edges only and nothing in the compiler inverts it, so this table is genuinely
    /// new state.
    fan_in: u32,

    /// Sorts last. Used for anything whose module could not be determined; guessing that
    /// an unknown unit is a leaf would promote it past units that were actually ranked.
    pub const unknown: Rank = .{ .depth = std.math.maxInt(u32), .fan_in = 0 };
};

/// `*Module -> Rank`, complete over `zcu.module_roots`.
map: std.AutoHashMapUnmanaged(*Module, Rank),
/// Number of modules that took part in an import cycle. Reported, never silently
/// tolerated: a cyclic module's depth is a floor, not a measurement.
cyclic_count: u32,
/// Deepest module found. Reported so the ranking's shape is visible in one line.
max_depth: u32,

const Progress = enum { in_progress, done };

/// Builds the ranking. `arena` is the compilation's arena, so the result lives exactly as
/// long as the `Zcu` that reads it.
pub fn build(arena: Allocator, zcu: *Zcu) Allocator.Error!ModuleRanking {
    const mods = zcu.module_roots.keys();

    var map: std.AutoHashMapUnmanaged(*Module, Rank) = .empty;
    try map.ensureTotalCapacity(arena, @intCast(mods.len));

    var state: std.AutoHashMapUnmanaged(*Module, Progress) = .empty;
    defer state.deinit(arena);
    try state.ensureTotalCapacity(arena, @intCast(mods.len));

    var cyclic: std.AutoHashMapUnmanaged(*Module, void) = .empty;
    defer cyclic.deinit(arena);

    var max_depth: u32 = 0;
    for (mods) |mod| {
        const d = try depthOf(arena, zcu, mod, &map, &state, &cyclic);
        max_depth = @max(max_depth, d);
    }

    // Fan-in inverts the edge set, so it needs a second pass: no module's in-degree is
    // final until every module's out-edges have been walked.
    for (mods) |mod| {
        var it = edges(zcu, mod);
        while (it.next()) |dep| {
            if (map.getPtr(dep)) |r| r.fan_in += 1;
        }
    }

    return .{
        .map = map,
        .cyclic_count = cyclic.count(),
        .max_depth = max_depth,
    };
}

/// Memoised, cycle-tolerant longest-path-to-leaf.
fn depthOf(
    arena: Allocator,
    zcu: *Zcu,
    mod: *Module,
    map: *std.AutoHashMapUnmanaged(*Module, Rank),
    state: *std.AutoHashMapUnmanaged(*Module, Progress),
    cyclic: *std.AutoHashMapUnmanaged(*Module, void),
) Allocator.Error!u32 {
    if (state.get(mod)) |p| switch (p) {
        .done => return map.get(mod).?.depth,
        // A back-edge into a module we are still resolving. Contribute 0 rather than
        // recursing forever, and record that this module's depth is a floor.
        .in_progress => {
            try cyclic.put(arena, mod, {});
            return 0;
        },
    };
    try state.put(arena, mod, .in_progress);

    var depth: u32 = 0;
    var it = edges(zcu, mod);
    while (it.next()) |dep| {
        depth = @max(depth, try depthOf(arena, zcu, dep, map, state, cyclic) + 1);
    }

    // `fan_in` is filled by `build`'s second pass.
    try map.put(arena, mod, .{ .depth = depth, .fan_in = 0 });
    state.putAssumeCapacity(mod, .done);
    return depth;
}

/// Iterates a module's dependency edges: its declared `deps`, plus the implicit `std`
/// edge that `deps` never stores. See approximation 1 in this file's header.
fn edges(zcu: *Zcu, mod: *Module) EdgeIterator {
    return .{
        .deps = mod.deps.values(),
        .index = 0,
        .implicit_std = if (mod == zcu.std_mod) null else zcu.std_mod,
    };
}

const EdgeIterator = struct {
    deps: []const *Module,
    index: usize,
    implicit_std: ?*Module,

    fn next(it: *EdgeIterator) ?*Module {
        if (it.index < it.deps.len) {
            defer it.index += 1;
            const dep = it.deps[it.index];
            // A module may name `std` explicitly too; do not count the edge twice.
            if (dep == it.implicit_std) it.implicit_std = null;
            return dep;
        }
        if (it.implicit_std) |std_mod| {
            it.implicit_std = null;
            return std_mod;
        }
        return null;
    }
};

/// A rank plus the "internal before facade" bit, memoised per source file by
/// `Zcu.file_rank_memo`.
pub const FileRank = struct {
    rank: Rank,
    /// 0 for a module's internal files, 1 for its public root file.
    ///
    /// This is the cheapest faithful reading of the charter's "a module's internals
    /// before its facade" that does not require inventing a visibility model Zig does not
    /// have: a module's root source file (`zcu.module_roots`' value) is its public face,
    /// and every other file of that module is reached only through it. It is an
    /// APPROXIMATION and is declared as one — it does not model `pub`, and a root file
    /// full of implementation detail ranks as a facade anyway.
    facade: u1,

    pub const unknown: FileRank = .{ .rank = .unknown, .facade = 1 };
};

pub fn get(r: ModuleRanking, mod: *Module) Rank {
    return r.map.get(mod) orelse .unknown;
}

/// `(depth ASC, fan_in DESC)`, with `facade` (0 = a module's internal file, 1 = its
/// public root file) as the last structural tie-break. Callers scan in insertion order
/// and replace only on a strict `true`, so insertion order remains the final tie-break
/// without being encoded here.
pub fn before(a: Rank, a_facade: u1, b: Rank, b_facade: u1) bool {
    if (a.depth != b.depth) return a.depth < b.depth;
    if (a.fan_in != b.fan_in) return a.fan_in > b.fan_in;
    return a_facade < b_facade;
}
