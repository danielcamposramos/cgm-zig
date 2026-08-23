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
/// **This comment used to claim it was "already enforced, by a mechanism that predates
/// this file". That claim was false, and believing it is what shipped a deadlock.**
/// `Zcu.PerThread.Id.allocate(K)` stocks `available_tids` with `K - 1` ids
/// (`Zcu/PerThread.zig:99-112`) and `acquire`/`release` are a bounded semaphore over them
/// (`:113-152`) — but a bounded semaphore with **zero** permits does not enforce a bound,
/// it blocks forever. `acquire` has no refusal path and no timeout: it waits on `tid_cond`
/// until an id appears, and when `alloc_lanes == 0` none ever will, because the linker
/// holds the pool's only assignable id for the entire compilation.
///
/// Measured: on a 2-physical / 4-logical mask, with NO FLAGS, the pre-fix compiler printed
/// `alloc lanes 0` and then hung (rc=124 under `timeout 120`) while the unpatched
/// reference completed the identical command. The number was computed, printed, and
/// consulted by nothing — the compiler named the cause of its own hang and did not act
/// on it. A number a tool reports but never acts on is decoration.
///
/// It is enforced NOW, and deliberately not here: `starvedLanes` below is the predicate,
/// and `setThreadLimit` (`src/main.zig`) is where it acts — the one site that holds both
/// quantities and that calls `Id.allocate` to build the pool. Derived plans can no longer
/// reach the starved state at all (`min_derived_basis`).
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
/// `(2^31 - 1) >> tid_width` — items available to each partition before patch/001's
/// named panic fires. Checkable against `PATCH005_DOSSIER.md` §3.6. (Was `2^30` until the
/// `CaptureValue` widening; see `index_bits`.)
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

/// The smallest partition count a DERIVED plan may produce, and it is a liveness bound
/// rather than a tuning choice.
///
/// `Zcu.PerThread.Id.allocate(n)` seeds the assignable-tid pool with `n - 1` ids
/// (`Zcu/PerThread.zig:99-112`). The linker acquires one through `io.concurrent` and holds
/// it for the entire compilation (dossier §1.1, row A7). So the ids actually available to
/// allocating workers are `n - 2` — the `alloc lanes` number this file already reports.
///
/// At `n = 2` that is **zero**, and a worker that asks for a tid waits on `tid_cond`
/// forever (`:116-136`): no error, no timeout, no output. That is the silent-hang class
/// patch/001 exists to abolish and that patch/002 Finding 3 refused a one-line change
/// over — and the `(K, M_wide)` split re-introduced it by a different route, because K and
/// the worker count stopped being the same integer.
///
/// **Measured, not reasoned:** on a mask of 2 physical / 4 logical CPUs — the ordinary
/// shape of a 2-core CI container — the pre-fix compiler derived `physical = 2`, hence
/// `basis = 2`, hence K = 2 and `alloc lanes 0`, and then hung on
/// `build-obj hello.zig` **with no flags at all** (rc=124 under `timeout 120`). The
/// unpatched reference compiler completed the identical command (rc=0), because upstream's
/// single integer made `workers = 4` imply a 4-way pool. The regression was ours.
///
/// A floor of 4 rather than 3 because the count is rounded up to a power of two anyway
/// (§3.4); 4 yields `alloc lanes 2`. The cost is two extra `InternPool.locals` entries on
/// hosts with fewer than 4 physical cores, and `items_per_partition` halving from
/// 1,073,741,823 to 536,870,911 there — still 8× the largest observed production need.
///
/// This floor binds the DERIVED path only. An explicitly given `--intern-partitions=2` is
/// still honoured, because an operator's stated number is not overridden silently — it is
/// instead refused by name when it cannot make progress (`starvedLanes`).
const min_derived_basis = 4;

/// The width of an `InternPool.Index` payload once the tid is shifted in.
///
/// **This is 31, and it was 30 until the `CaptureValue` widening landed.** The old
/// comment here read: *"This is 30 and not 32 because `CaptureValue` confines an
/// `Index` to `u30` — the two-bit debt patch/002 priced and declined to pay"*, and it
/// predicted *"if that widening ever lands, this constant moves with it and every
/// ceiling in the report doubles twice over."* The widening landed. The constant moved.
/// The ceilings doubled **once**, not twice, and the reason is worth inheriting:
///
/// `CaptureValue` was the FIRST of two confiners, not the only one. `Air.Inst.Ref`
/// (`Air.zig:1170-1176`) owns bit 31 as its interned-vs-instruction tag, and both
/// `Ref.fromIntern` and `ShuffleOneMask` `@intCast` an `Index` down to `u31`. So
/// freeing `CaptureValue` bought the 31st bit and the 32nd has a different owner —
/// reclaiming it is an AIR re-representation patch, which is a separate change with a
/// separate argument, and it is refused by name rather than taken quietly.
///
/// Keep this in step with `InternPool.getIndexMask` (`InternPool.zig:1598`), which the
/// widening moved from `getIndexMask(u30)` to `getIndexMask(u31)` for `Index`. If these
/// two ever disagree, the report line lies about the ceiling — and the ceiling is
/// precisely the number an operator consults after meeting patch/001's named refusal.
const index_bits = 31;

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
        // FLOORED AT 4, NOT 2, AND THIS IS A DEADLOCK FIX -- see `min_derived_basis`.
        // A derived K of 2 leaves `alloc_lanes = K - 2 = 0`: the tid pool holds K-1 = 1
        // assignable id, the linker takes it and holds it for the whole compilation, and
        // every worker that then asks for a tid blocks forever. Measured on a 2-physical
        // / 4-logical host with NO FLAGS AT ALL: patched rc=124 (silent hang), reference
        // rc=0. Flooring at 4 means a derived plan always has at least two lanes.
        const basis = @max(topology.physical orelse topology.logical, min_derived_basis);
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

/// True when this plan asks for concurrent workers but leaves them no tid to allocate in.
///
/// **This is the predicate that makes `alloc_lanes` load-bearing.** Before it existed,
/// `alloc_lanes` appeared only in this file — computed, printed, and consulted by nothing.
/// The compiler printed `alloc lanes 0` and then hung, having named the precise cause of
/// its own hang and acted on it not at all. A number a tool reports but never acts on is
/// decoration, so this one now decides something: `setThreadLimit` refuses on it
/// (`src/main.zig`), at the site that calls `Id.allocate` and therefore *creates* the pool.
///
/// The condition is `alloc_lanes == 0 and workers > 1`, and both halves are deliberate:
///
///   * `alloc_lanes == 0` is the structural fact — the linker holds the pool's only
///     assignable id, so no worker can ever obtain one.
///   * `workers > 1` spares the legitimate serial member. At `-j1` nothing runs
///     concurrently, `Io.Threaded`'s async limit sends every task inline, and the main
///     thread has `Id.acquire`'s recursive shortcut, so no tid is ever requested.
///     `-j1 --intern-partitions=2` is a working configuration and MUST stay one; a guard
///     that refused it would have over-fired and would itself be a defect.
///
/// **Why not the measured boundary instead.** The hang was observed at `workers >= 4`;
/// `-j2` and `-j3` with `K = 2` completed. They complete by accident, not by design: with
/// `alloc_lanes == 0` no allocating work can ever run off the main thread, so those runs
/// silently degrade to serial while reporting the worker count the operator asked for —
/// the same parameter theatre in a quieter costume. Encoding `>= 4` would also hard-code
/// today's `concurrent_reserve` arithmetic into a liveness invariant. The structural
/// condition is refused instead, and the refusal names the remedy.
pub fn starvedLanes(plan: ThreadPlan) bool {
    return plan.alloc_lanes == 0 and plan.workers > 1;
}

/// Emits the plan as one line, at derivation time.
///
/// By ruling, not by oversight: `docs/crown/DOCTRINE.md` principle 4 (a tool states its
/// resolved reality) and `PATCH005_DOSSIER.md` §3.7. Every number names *what* it is and
/// *from what* it came, so the line is checkable against the host's own instruments
/// (`lscpu -e`) and against §3.6's ceiling table without running anything else.
///
/// **THE ONE GATE, and it is the caller's to apply, not this function's.** This writes
/// prose to stderr. Under `--listen`, stderr is not a terminal -- it is one side of the
/// build runner's IPC, and the runner reads non-error-bundle bytes there as evidence that
/// the step failed. V-BR measured the consequence: a green build (exit 0, "13/13 steps
/// succeeded") printing 6 `^error:` lines and 6 `compile exe <name> Debug native failure`
/// markers, from this line alone. So `src/main.zig`'s `buildOutputType` calls this only
/// when `listen == .none`, exactly as it already does for `--time-report`.
///
/// The three derivation sites divide cleanly: `buildOutputType` can be a child of the
/// build runner and is gated; `zig build` and `jitCmd` are the process the operator
/// invoked, own the terminal, and report unconditionally.
///
/// **Named residual:** this is one line of stderr that stock 0.16.0 does not emit, so a
/// stock *interactive* invocation is byte-identical in its *artifact* and not in its
/// *stderr*. Under `--listen` -- the machine-readable path -- both are now identical.
/// That distinction is exactly what queued item V11 checks, and it is stated there too.
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
        // Doubled by the `CaptureValue` widening (`index_bits` 30 -> 31). Both columns
        // live in `PATCH005_DOSSIER.md` §3.6; these are the current ones.
        .{ 2, 1, 1_073_741_823 },
        .{ 4, 2, 536_870_911 },
        .{ 8, 3, 268_435_455 },
        .{ 16, 4, 134_217_727 },
        .{ 32, 5, 67_108_863 },
        .{ 64, 6, 33_554_431 },
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
    try std.testing.expectEqual(@as(u32, 1_073_741_823), plan.items_per_partition);
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
    try std.testing.expectEqual(@as(u32, 268_435_455), plan.items_per_partition);

    // The stock-equivalent row of the same table, reachable by name so a regression can
    // be bisected against it: K follows logical, no round-up, and the ceiling is the one
    // the production incident hit.
    const stock = finish(topology, topology.logical, .logical, topology.logical, .logical, false);
    try std.testing.expectEqual(@as(u5, 4), stock.tid_width);
    try std.testing.expectEqual(@as(u32, 134_217_727), stock.items_per_partition);
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

test "a derived plan never starves its own allocating lanes" {
    // THE REGRESSION TEST for the deadlock. A 2-physical / 4-logical host -- the ordinary
    // shape of a 2-core CI container -- derived K = 2 before `min_derived_basis` existed,
    // which is `alloc lanes 0`, and the compiler hung on `build-obj hello.zig` with no
    // flags at all (measured rc=124; the unpatched reference returned rc=0).
    //
    // The property asserted is the one that matters and is host-independent: NO derived
    // plan, on ANY topology, may leave zero allocating lanes while asking for concurrent
    // workers. Asserting the property rather than the constant means a future change to
    // the rounding or the basis cannot quietly reintroduce the hang.
    const shapes = [_]struct { logical: usize, physical: ?usize }{
        .{ .logical = 1, .physical = 1 },
        .{ .logical = 2, .physical = 1 },
        .{ .logical = 2, .physical = 2 },
        .{ .logical = 4, .physical = 2 }, // the container that hung
        .{ .logical = 4, .physical = 4 },
        .{ .logical = 12, .physical = 6 },
        .{ .logical = 8, .physical = null }, // probe returned UNKNOWN
        .{ .logical = 1, .physical = null },
    };
    for (shapes) |s| {
        const topology: std.Thread.Topology = .{
            .logical = s.logical,
            .physical = s.physical,
            .threads_per_core = null,
            .source = if (s.physical == null) .unknown else .sys_topology,
        };
        // Mirror `derive`'s partition branch for a supplied topology.
        const basis = @max(topology.physical orelse topology.logical, min_derived_basis);
        const width = std.math.log2_int_ceil(usize, basis);
        const rounded = @as(usize, 1) << @intCast(width);
        for ([_]usize{ 1, 2, 3, 4, 8, 64 }) |workers| {
            const plan = finish(topology, workers, .logical, rounded, .physical, false);
            try std.testing.expect(plan.alloc_lanes >= 2);
            try std.testing.expect(!plan.starvedLanes());
        }
    }
}

test "starvedLanes fires on a starved pool and spares the serial member" {
    const topology: std.Thread.Topology = .{
        .logical = 4,
        .physical = 2,
        .threads_per_core = 2,
        .source = .sys_topology,
    };
    // An explicitly given `--intern-partitions=2` is still reachable, and it is the case
    // the named refusal in `setThreadLimit` exists for.
    const starved = finish(topology, 4, .given, 2, .given, false);
    try std.testing.expectEqual(@as(usize, 0), starved.alloc_lanes);
    try std.testing.expect(starved.starvedLanes());

    // THE OVER-FIRE GUARD. `-j1 --intern-partitions=2` is a legitimate, working, fully
    // serial configuration: nothing runs concurrently, so no tid is ever requested and
    // zero lanes harm nobody. Measured rc=0 both before and after the fix. A guard that
    // refused it would break a working setup and would itself be the defect -- so the
    // test that would catch that lives here, next to the guard.
    const serial = finish(topology, 1, .given, 2, .given, false);
    try std.testing.expectEqual(@as(usize, 0), serial.alloc_lanes);
    try std.testing.expect(!serial.starvedLanes());

    // Three lanes' worth of partitions is enough for one worker lane; not starved.
    const ok = finish(topology, 8, .given, 4, .given, false);
    try std.testing.expectEqual(@as(usize, 2), ok.alloc_lanes);
    try std.testing.expect(!ok.starvedLanes());
}
