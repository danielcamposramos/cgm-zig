//! Where the compiler decides how much of the host it will use — and says so out loud.
//!
//! Before this file existed, that decision was three lines in `main.zig` and nothing
//! reported it:
//!
//! ```zig
//! const thread_limit = @min(
//!     @max(n_jobs orelse std.Thread.getCpuCount() catch 1, 1),
//!     std.math.maxInt(Zcu.PerThread.IdBacking),
//! );
//! try setThreadLimit(arena, thread_limit);
//! ```
//!
//! One integer travelled from there to *two* unrelated consumers — the `Io.Threaded`
//! async/concurrency limits, and the `InternPool` partition count (`setThreadLimit` in
//! `main.zig`, then `Zcu.init` → `InternPool.init`). That single funnel is why a *wider*
//! host compiles *less*: `InternPool.init` derives
//! `tid_width = ceil(log2(threads))` (`InternPool.zig:6331`) and `getIndexMask` hands
//! each partition `(2^30 - 1) >> tid_width` items (`InternPool.zig:1591-1592`), so every
//! extra worker halves — for a power-of-two crossing — the index space available to the
//! partition that does nearly all the allocating.
//!
//! This file does not yet split those two roles apart; it names the quantities, derives
//! them exactly as the three lines above did, and reports the result. Reporting comes
//! first on purpose: a derivation nobody can see is a derivation nobody can debug, and
//! the numbers reported here are precisely the ones an operator needs when patch/001's
//! named partition-exhaustion panic fires. The panic says which partition overflowed;
//! this line says what chose the partition count, and from which instrument.
//!
//! See `docs/crown/PATCH005_DOSSIER.md` §3 for the design this file implements and §3.6
//! for the ceiling table the report is checkable against.

const ThreadPlan = @This();

const std = @import("std");
const builtin = @import("builtin");
const Zcu = @import("Zcu.zig");

/// The host as measured, affinity-masked. `physical` is `null` when unprobeable —
/// UNKNOWN, never a guessed SMT ratio.
topology: std.Thread.Topology,
/// Worker count. Feeds `Io.Threaded`'s async and concurrency limits.
workers: usize,
/// Where `workers` came from.
workers_source: Source,
/// `InternPool` partition count, as `InternPool.init` will actually use it — the
/// `@max(_, 2)` floor at `InternPool.zig:6295` is already applied, so this field never
/// disagrees with the pool that gets allocated. Sizes `ip.locals` and, through
/// `tid_width = ceil(log2(partitions))`, the per-partition index ceiling.
partitions: usize,
/// Where `partitions` came from.
partitions_source: Source,
/// True when the request was below the floor of 2 and the floor won. Reported rather
/// than silently applied: `-j1` asking for one partition and getting two is exactly the
/// kind of quiet adjustment that makes a later measurement inexplicable.
partitions_floored: bool,
/// How many partitions are reachable by *worker* allocation, as opposed to being
/// permanently spoken for. Two always are: tid `.main` is held by the main thread for
/// the whole compilation (`Compilation.zig:4548`), and the linker task acquires one at
/// `link/Queue.zig:152` and releases it only on return (`:153`). So this is
/// `partitions - 2` exactly — a derived consequence of the existing tid pool, never a
/// knob. It is reported because it is the number an operator reasons about.
alloc_lanes: usize,
/// `ceil(log2(max(partitions, 2)))`, the same expression `InternPool.init` uses
/// (`InternPool.zig:6331`) on the same input.
tid_width: u5,
/// `(2^30 - 1) >> tid_width` — items available to each partition before patch/001's
/// named panic fires. Checkable against `PATCH005_DOSSIER.md` §3.6.
items_per_partition: u32,

pub const Source = enum {
    /// Derived from the probed logical CPU count.
    logical,
    /// Given explicitly on the command line.
    given,

    /// Reads as the parenthetical in the report line. Every derived number states the
    /// instrument it derived from; a given number says so and names nothing, because a
    /// number the operator supplied has no provenance to report.
    pub fn word(s: Source) []const u8 {
        return switch (s) {
            .logical => "derived: logical",
            .given => "given",
        };
    }
};

/// The width of an `InternPool.Index` payload once the tid is shifted in.
///
/// This is 30 and not 32 because `CaptureValue` confines an `Index` to `u30` — the
/// two-bit debt patch/002 priced at 427 sites and declined to pay, and which
/// `PATCH005_DOSSIER.md` §5 designs around. If that widening ever lands, this constant
/// moves with it and every ceiling in the report doubles twice over.
/// Cite: `InternPool.zig:1591-1592` (`getIndexMask`), and patch/001's comment at `:4139`.
const index_bits = 30;

/// Derives the plan from the host and the command line. Never fails: an unprobeable host
/// falls back to exactly what the compiler did before this file existed.
pub fn derive(n_jobs: ?u32) ThreadPlan {
    const topology: std.Thread.Topology = std.Thread.Topology.detect(.{}) catch .{
        // `Topology.detect` fails only where `getCpuCount` fails, and the previous code
        // spelled that failure `catch 1`. Same fallback, now visible in the report.
        .logical = 1,
        .physical = null,
        .threads_per_core = null,
        .source = .unknown,
    };

    // Verbatim reproduction of the pre-existing derivation, kept in one place so the
    // split designed in `PATCH005_DOSSIER.md` §3.4 is a change to *this function* rather
    // than a change scattered across `main.zig`.
    //
    // The `maxInt(IdBacking)` clamp is a *partition* constraint wearing a worker's
    // clothes: it exists because `Zcu.PerThread.IdBacking` is `u7` and because
    // `InternPool.init` asserts `available_threads <= maxInt(u8)`
    // (`InternPool.zig:6293`). It is applied to both quantities here only because they
    // are still the same quantity.
    const requested: usize = @max(n_jobs orelse topology.logical, 1);
    const limit = @min(requested, std.math.maxInt(Zcu.PerThread.IdBacking));
    const source: Source = if (n_jobs != null) .given else .logical;

    return finish(topology, limit, source, limit, source);
}

/// Fills in the quantities that are consequences rather than choices. Shared by `derive`
/// so the report can never disagree with the arithmetic `InternPool` will actually do.
fn finish(
    topology: std.Thread.Topology,
    workers: usize,
    workers_source: Source,
    partitions: usize,
    partitions_source: Source,
) ThreadPlan {
    // `InternPool.init` floors its input at 2 (`InternPool.zig:6295`,
    // `@max(available_threads, 2)`), and patch/002 Finding 3 binds us never to lower
    // that floor: all three of its `-j1` edges fire at `tid_width == 0`. Mirroring the
    // floor here — rather than assuming it — is what keeps the report honest for `-j1`.
    const used = @max(partitions, 2);
    const tid_width: u5 = @intCast(std.math.log2_int_ceil(usize, used));
    return .{
        .topology = topology,
        .workers = workers,
        .workers_source = workers_source,
        .partitions = used,
        .partitions_source = partitions_source,
        .partitions_floored = used != partitions,
        .alloc_lanes = used -| 2,
        .tid_width = tid_width,
        .items_per_partition = @as(u32, (1 << index_bits) - 1) >> tid_width,
    };
}

/// Emits the plan as one line, at derivation time, gated on nothing.
///
/// Unconditional by ruling, not by oversight: `docs/crown/DOCTRINE.md` principle 4 (a
/// tool states its resolved reality) and `PATCH005_DOSSIER.md` §3.7. Every number names
/// *what* it is and *from what* it came, so the line is checkable against the host's own
/// instruments (`lscpu -e`) and against §3.6's ceiling table without running anything
/// else.
///
/// **Named residual:** this is one line of stderr that stock 0.16.0 does not emit, so a
/// stock invocation is byte-identical in its *artifact* and not in its *stderr*. That
/// distinction is exactly what queued item V11 checks, and it is stated there too.
///
/// Emitted once per process, at the derivation site, rather than at `Compilation.create`
/// as the dossier's §3.7 sketch proposed: sub-compilations inherit the plan rather than
/// deriving one, so `create` would print the same line ~20 times for a single build.
pub fn report(plan: ThreadPlan) void {
    var items_buf: [24]u8 = undefined;
    var physical_buf: [40]u8 = undefined;
    var per_core_buf: [40]u8 = undefined;

    // Not `logical / 2`, not `1`. If the instrument did not answer, the line says so, and
    // an operator reading it knows the fallback to `logical` was a fallback.
    const physical_text: []const u8 = if (plan.topology.physical) |p|
        std.fmt.bufPrint(&physical_buf, "{d} physical", .{p}) catch unreachable
    else
        "UNKNOWN physical";

    const per_core_text: []const u8 = if (plan.topology.threads_per_core) |n|
        std.fmt.bufPrint(&per_core_buf, ", {d} threads per core", .{n}) catch unreachable
    else
        "";

    std.log.info(
        "threads: topology {s} / {d} logical{s} (probe: {t}); " ++
            "workers {d} ({s}); intern partitions {d} ({s}{s}); " ++
            "alloc lanes {d} (= partitions - 2, main + linker reserved); " ++
            "{s} items per partition; override with -j<N>",
        .{
            physical_text,
            plan.topology.logical,
            per_core_text,
            plan.topology.source,
            plan.workers,
            plan.workers_source.word(),
            plan.partitions,
            plan.partitions_source.word(),
            if (plan.partitions_floored) ", floored to 2" else "",
            plan.alloc_lanes,
            groupDigits(plan.items_per_partition, &items_buf),
        },
    );
}

/// Formats an integer with thousands separators, so a reported ceiling can be compared
/// against `PATCH005_DOSSIER.md` §3.6 by eye without miscounting digits. Returns a slice
/// of `buf`, which must be at least 24 bytes.
fn groupDigits(value: u32, buf: []u8) []const u8 {
    var digits: [10]u8 = undefined;
    var n_digits: usize = 0;
    var v = value;
    while (true) {
        digits[n_digits] = @intCast('0' + (v % 10));
        n_digits += 1;
        v /= 10;
        if (v == 0) break;
    }
    var out: usize = 0;
    var i = n_digits;
    while (i > 0) {
        i -= 1;
        buf[out] = digits[i];
        out += 1;
        if (i != 0 and i % 3 == 0) {
            buf[out] = ',';
            out += 1;
        }
    }
    return buf[0..out];
}

test "ceiling table matches PATCH005_DOSSIER.md 3.6" {
    // The dossier's §3.6 table, transcribed. If this ever disagrees, one of the two is
    // wrong and the disagreement is visible instead of silent.
    const cases = [_]struct { usize, u5, u32 }{
        .{ 2, 1, 536_870_911 },
        .{ 4, 2, 268_435_455 },
        .{ 8, 3, 134_217_727 },
        .{ 16, 4, 67_108_863 },
        .{ 32, 5, 33_554_431 },
        .{ 64, 6, 16_777_215 },
    };
    const topology: std.Thread.Topology = .{
        .logical = 12,
        .physical = 6,
        .threads_per_core = 2,
        .source = .sys_topology,
    };
    for (cases) |case| {
        const partitions, const want_width, const want_items = case;
        const plan = finish(topology, partitions, .logical, partitions, .logical);
        try std.testing.expectEqual(want_width, plan.tid_width);
        try std.testing.expectEqual(want_items, plan.items_per_partition);
        try std.testing.expectEqual(partitions - 2, plan.alloc_lanes);
    }
}

test "the -j1 floor is honoured, not lowered" {
    // patch/002 Finding 3: all three `-j1` edges fire at `tid_width == 0`, so the floor
    // of 2 partitions must survive every derivation. A regression here is that finding
    // resurfacing.
    const plan = derive(1);
    try std.testing.expectEqual(@as(usize, 1), plan.workers);
    try std.testing.expectEqual(@as(u5, 1), plan.tid_width);
    try std.testing.expectEqual(@as(u32, 536_870_911), plan.items_per_partition);
}

test "digit grouping" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("134,217,727", groupDigits(134_217_727, &buf));
    try std.testing.expectEqualStrings("0", groupDigits(0, &buf));
    try std.testing.expectEqualStrings("1,000", groupDigits(1000, &buf));
    try std.testing.expectEqualStrings("999", groupDigits(999, &buf));
}
