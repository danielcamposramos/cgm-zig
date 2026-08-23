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
//! ## R2, and why this file does not fix it — a refusal, stated rather than skipped
//!
//! Raising `M_wide` raises the number of concurrent *compiler processes* under
//! `zig build`, each with its own full closure resident. The build runner's only defence
//! is its RSS admission gate (`lib/compiler/build_runner.zig:1429-1437`), and that gate
//! is inert at this base — not because its budget is too generous but because **no step
//! makes a claim at all**: `Step.max_rss` is `0` at every construction site
//! (`lib/std/Build/Step.zig:231`; `lib/std/Build.zig:775, 805, 828, 861, 902`), and `0`
//! means "no claim", so both the gate and the pre-flight check skip past it. A user who
//! reaches for `--maxrss` after an OOM therefore gets no protection either.
//!
//! This patch does NOT raise the build-runner default, does NOT invent per-step RSS
//! numbers, and does NOT derive a residency-vs-`M_wide` interplay guard, because every
//! form of such a guard needs a measured per-step peak and no measurement exists in this
//! lane. What it does instead: `M_wide` is printed, so an operator can see the
//! concurrency coming; the child-compiler cap rider bounds the *CPU* half of the same
//! problem with a derived number; and the missing input — a persisted per-step
//! `(peak_rss, duration_ns)` ledger built from data the runner already measures and
//! throws away (`lib/std/Build/Step.zig:455`, `:500`, `:662`) — is written down as the
//! prerequisite it is. Naming the refusal is the honest move; a guard derived from
//! numbers nobody measured would be a default in disguise.
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
/// permanently spoken for. Two always are: tid `.main` is held by the main thread for the
/// whole compilation (`Compilation.zig:4548`), and the linker task acquires one at
/// `link/Queue.zig:152` and releases it only on return (`:153`). So this is
/// `partitions - 2` exactly — a derived consequence, never a knob.
///
/// **It is already enforced, by a mechanism that predates this file.**
/// `Zcu.PerThread.Id.allocate(K)` stocks `available_tids` with `K - 1` ids
/// (`Zcu/PerThread.zig:99-112`) and `acquire`/`release` are a bounded semaphore over
/// them (`:113-152`). The linker holds one for the whole run, so at most `K - 2`
/// allocating workers can hold a tid at the same instant. Reported because it is the
/// number an operator reasons about, not because anything new counts it.
///
/// NAMED RESIDUAL — the separate admission gate the dossier designed (§2.3 edit 3) is
/// NOT shipped here, and the reason is not oversight. Its purpose was hazard H1: with
/// `M_wide > K`, allocating workers beyond `K - 2` park inside `Id.acquire` while holding
/// a runner slot. That is real, but (a) after the A1 lane split the parking exposure is
/// codegen and `@embedFile` only — AstGen, the widest phase, no longer takes a tid for
/// its body at all; (b) the consequential harm of parked workers was
/// `busy_count` inflation starving the linker's `io.concurrent` slot (dossier R3), and
/// that is closed independently and more robustly by the `concurrent_reserve` rider,
/// which holds regardless of what the compiler does above it; and (c) the gate cannot
/// address the inline-async trap it is sometimes assumed to, because
/// `Io.Threaded.async` past its limit runs the task on the CALLING thread
/// (`Io/Threaded.zig:2100-2105`) whatever an in-flight counter says. What remains is
/// wasted context switches, whose cost is unmeasured — and a permit that leaks on a
/// cancellation path hangs the main thread, a failure this lane could not test for
/// because no compiler could be built. Shipping an untestable blocking mechanism to buy
/// an unmeasured saving is the wrong trade; the gate is queued behind V15 instead.
alloc_lanes: usize,
/// `ceil(log2(max(partitions, 2)))`, the same expression `InternPool.init` uses
/// (`InternPool.zig:6331`) on the same input.
tid_width: u5,
/// `(2^30 - 1) >> tid_width` — items available to each partition before patch/001's
/// named panic fires. Checkable against `PATCH005_DOSSIER.md` §3.6.
items_per_partition: u32,

/// True when the power-of-two round-up hit the 128-partition ceiling imposed by
/// `Zcu.PerThread.IdBacking` being `u7`. Reported by name rather than silently clamped:
/// on such a host the derivation stopped tracking the hardware and the operator needs to
/// know that before reading anything else in the line.
partitions_saturated: bool,

pub const Source = enum {
    /// Derived from the probed logical CPU count.
    logical,
    /// Derived from the probed PHYSICAL core count, rounded up to the power of two its
    /// own `tid_width` already implies.
    physical,
    /// Derived from logical CPUs because the topology probe returned UNKNOWN. Distinct
    /// from `.logical` (which is a request) so the line cannot make a fallback look
    /// like a choice.
    logical_fallback,
    /// Given explicitly on the command line.
    given,

    /// Reads as the parenthetical in the report line. Every derived number states the
    /// instrument it derived from; a given number says so and names nothing, because a
    /// number the operator supplied has no provenance to report.
    pub fn word(s: Source) []const u8 {
        return switch (s) {
            .logical => "derived: logical",
            .physical => "derived: physical, rounded up to a power of two",
            .logical_fallback => "derived: logical, topology UNKNOWN",
            .given => "given",
        };
    }
};

/// What `--intern-partitions` asked for, when it was given at all.
pub const PartitionsArg = union(enum) {
    /// `--intern-partitions=<N>`.
    count: u32,
    /// `--intern-partitions=logical` — opt back in to the pre-split coupling, where the
    /// partition count follows logical CPUs. Kept reachable by name for the same reason
    /// `--step-order=random` is: a regression can then be bisected against the old
    /// behaviour without building a second compiler, and queued item V7b uses it to
    /// reproduce the production incident on demand.
    logical,
};

/// `1 << 7`, from `Zcu.PerThread.IdBacking` being `u7`: `Id.allocate(n)` hands out tids
/// `1..n-1` as `@enumFromInt`, so `n - 1` must fit in the backing type.
/// `InternPool.init`'s own `assert(available_threads <= maxInt(u8))`
/// (`InternPool.zig:6293`) is looser and is therefore not the binding limit.
const max_partitions = @as(usize, std.math.maxInt(Zcu.PerThread.IdBacking)) + 1;

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
///
/// THE SPLIT, in three lines and then the reasons:
///
/// ```
/// M_wide  = -j<N>               orelse topology.logical
/// K       = --intern-partitions orelse 1 << ceil_log2(max(physical orelse logical, 2))
/// M_alloc = K - 2
/// ```
///
/// * **`M_wide` comes from LOGICAL CPUs and is no longer clamped by
///   `maxInt(IdBacking)`.** That clamp is a *partition* constraint wearing a worker's
///   clothes — it exists because `Zcu.PerThread.IdBacking` is `u7` — and moving it to
///   `K` is one of the cleanest wins here: a 192-thread host now gets 192 workers on the
///   non-allocating phases where it used to get 127. The wide lane is parse, ZIR
///   lowering, file I/O, clang sub-processes and hashing, which is where SMT siblings
///   plausibly pay.
/// * **`K` comes from PHYSICAL cores.** The allocating class is cache-heavy — Sema
///   chasing `InternPool` items through pointer-dense structures, codegen over AIR/MIR —
///   and SMT siblings share L1, L2 and execution ports. Their gain on that class is
///   unmeasured and may be negative, so the derivation declines to spend index-space
///   headroom on it. That siblings pay on the wide lane is a hypothesis, not a fact; it
///   is dossier R10 and queued item V13 is the A/B that decides it.
/// * **`K` is rounded UP to a power of two.** `tid_width = ceil(log2(K))` and the shard
///   array is `1 << tid_width` (`InternPool.zig:6331`, `:6335`) while `locals` is sized
///   `K` (`:6296`). Any `K` below `2^tid_width` therefore pays the *full* ceiling
///   penalty of `2^tid_width` while leaving `2^tid_width - K` lanes allocated and
///   unusable. `K = 6` and `K = 8` have identical per-partition ceilings; `K = 8` simply
///   has two more usable lanes. The round-up is free capacity.
///   (An earlier draft of the dossier proposed rounding *down*. It is recorded here
///   rather than deleted, per `CONTRIBUTING-AI.md`: rounding down traded two real worker
///   lanes for a doubling of a ceiling the operator can already reach directly with
///   `--intern-partitions=<N>`.)
/// * **`K`'s floor is 2, never 1.** patch/002 Finding 3 binds: all three of its edges
///   fire at `tid_width == 0`. The floor lives in `finish` so it is reported, not just
///   applied.
/// * **`M_alloc = K - 2` is not a third knob.** A gate permit exists precisely to
///   reserve a tid, and two tids are permanently spoken for (`.main` for the whole
///   compilation, one held by the linker task from `link/Queue.zig:152` until it
///   returns). So the derived triple is a derived *pair* plus one subtraction. The
///   number is oversubscribed against physical cores by design (on a 6c/12t host: 6
///   gated workers + main + linker = 8 allocating-capable tasks over 6 cores, ~1.33x),
///   justified by two of the eight usually being blocked rather than running
///   (`Zcu.zig:5311`, `link/Queue.zig:189`) — a reading, not a measurement. V13 decides
///   it; if it is wrong, `M_alloc` clamps to `physical` in one line.
///
/// **The honest limit of all of this**, stated so the design is not oversold: the
/// topology probe helps decisively in the 4-14 physical-core band and does not save wide
/// hosts. A 16-physical-core machine derives `K = 16` -> `tid_width = 4` ->
/// 67,108,863 items per partition, back at the cliff. Beyond roughly 14 physical cores
/// only widening `CaptureValue` (dossier §5) adds headroom.
pub fn derive(n_jobs: ?u32, partitions_arg: ?PartitionsArg) ThreadPlan {
    const topology: std.Thread.Topology = std.Thread.Topology.detect(.{}) catch .{
        // `Topology.detect` fails only where `getCpuCount` fails, and the pre-split code
        // spelled that failure `catch 1`. Same fallback, now visible in the report.
        .logical = 1,
        .physical = null,
        .threads_per_core = null,
        .source = .unknown,
    };

    const workers: usize = @max(n_jobs orelse topology.logical, 1);
    const workers_source: Source = if (n_jobs != null) .given else .logical;

    var saturated = false;
    const partitions: usize, const partitions_source: Source = p: {
        if (partitions_arg) |arg| switch (arg) {
            .count => |n| break :p .{ @max(n, 1), .given },
            // Literally today's coupling: the partition count follows the logical CPU
            // count with no round-up, which is what reproduces stock `tid_width`.
            .logical => break :p .{ @max(topology.logical, 1), .logical },
        };
        const basis = @max(topology.physical orelse topology.logical, 2);
        const width = std.math.log2_int_ceil(usize, basis);
        const rounded = @as(usize, 1) << @intCast(width);
        if (rounded > max_partitions) saturated = true;
        break :p .{
            @min(rounded, max_partitions),
            if (topology.physical != null) .physical else .logical_fallback,
        };
    };

    return finish(topology, workers, workers_source, @min(partitions, max_partitions), partitions_source, saturated);
}

/// Fills in the quantities that are consequences rather than choices. Shared by `derive`
/// so the report can never disagree with the arithmetic `InternPool` will actually do.
fn finish(
    topology: std.Thread.Topology,
    workers: usize,
    workers_source: Source,
    partitions: usize,
    partitions_source: Source,
    partitions_saturated: bool,
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
        .partitions_saturated = partitions_saturated,
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
            "workers {d} ({s}); intern partitions {d} ({s}{s}{s}); " ++
            "alloc lanes {d} (= partitions - 2, main + linker reserved); " ++
            "{s} items per partition; override with -j<N> --intern-partitions=<N|logical>",
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
            // A host wide enough to saturate has stopped tracking its own hardware, and
            // a number that stopped tracking must say so where it is read.
            if (plan.partitions_saturated) ", SATURATED at the u7 tid ceiling" else "",
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
        const plan = finish(topology, partitions, .logical, partitions, .logical, false);
        try std.testing.expectEqual(want_width, plan.tid_width);
        try std.testing.expectEqual(want_items, plan.items_per_partition);
        try std.testing.expectEqual(partitions - 2, plan.alloc_lanes);
    }
}

test "the -j1 floor is honoured, not lowered" {
    // patch/002 Finding 3: all three `-j1` edges fire at `tid_width == 0`, so the floor
    // of 2 partitions must survive every derivation. A regression here is that finding
    // resurfacing. `-j1` sets workers, not partitions, so partitions still derive from
    // the host and must be pinned separately to make this test host-independent.
    const plan = derive(1, .{ .count = 1 });
    try std.testing.expectEqual(@as(usize, 1), plan.workers);
    try std.testing.expectEqual(@as(usize, 2), plan.partitions);
    try std.testing.expect(plan.partitions_floored);
    try std.testing.expectEqual(@as(u5, 1), plan.tid_width);
    try std.testing.expectEqual(@as(u32, 536_870_911), plan.items_per_partition);
}

test "the worked example: 6 physical / 12 logical derives K=8" {
    // `PATCH005_DOSSIER.md` §3.5's derived row, predicted before it is run and asserted
    // here so the derivation cannot drift away from the prediction V7a will check.
    //
    // This exercises the arithmetic, not the host: the topology is supplied, because a
    // test that asserted "6 physical" would only be asserting the machine it happened to
    // run on. The host half is queued item V0a's oracle.
    const topology: std.Thread.Topology = .{
        .logical = 12,
        .physical = 6,
        .threads_per_core = 2,
        .source = .sys_topology,
    };
    const basis = @max(topology.physical.?, 2);
    const rounded = @as(usize, 1) << @intCast(std.math.log2_int_ceil(usize, basis));
    try std.testing.expectEqual(@as(usize, 8), rounded);

    const plan = finish(topology, topology.logical, .logical, rounded, .physical, false);
    try std.testing.expectEqual(@as(usize, 12), plan.workers);
    try std.testing.expectEqual(@as(usize, 8), plan.partitions);
    try std.testing.expectEqual(@as(usize, 6), plan.alloc_lanes);
    try std.testing.expectEqual(@as(u5, 3), plan.tid_width);
    try std.testing.expectEqual(@as(u32, 134_217_727), plan.items_per_partition);

    // The stock-equivalent row of the same table, reachable by name so a regression can
    // be bisected against it: K follows logical, no round-up, and the ceiling is the one
    // the production incident hit.
    const stock = finish(topology, topology.logical, .logical, topology.logical, .logical, false);
    try std.testing.expectEqual(@as(u5, 4), stock.tid_width);
    try std.testing.expectEqual(@as(u32, 67_108_863), stock.items_per_partition);
}

test "the partition count saturates by name, never silently" {
    const topology: std.Thread.Topology = .{
        .logical = 512,
        .physical = 256,
        .threads_per_core = 2,
        .source = .sys_topology,
    };
    const plan = finish(topology, 512, .logical, max_partitions, .physical, true);
    try std.testing.expectEqual(max_partitions, plan.partitions);
    try std.testing.expect(plan.partitions_saturated);
    // The wide lane is NOT clamped by the tid backing type — that clamp belongs to K.
    try std.testing.expectEqual(@as(usize, 512), plan.workers);
}

test "digit grouping" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("134,217,727", groupDigits(134_217_727, &buf));
    try std.testing.expectEqualStrings("0", groupDigits(0, &buf));
    try std.testing.expectEqualStrings("1,000", groupDigits(1000, &buf));
    try std.testing.expectEqualStrings("999", groupDigits(999, &buf));
}
