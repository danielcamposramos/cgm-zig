//! CPU **topology** — physical cores and SMT siblings, intersected with this process's
//! affinity mask.
//!
//! `std.Thread.getCpuCount` answers one question: how many *logical* CPUs may we run on
//! (`Thread.zig`, the `LinuxThreadImpl` arm is `posix.CPU_COUNT(sched_getaffinity(0))`).
//! That is the right input for wide, I/O-tolerant fan-out, and the wrong input for
//! cache-heavy work: SMT siblings share L1, L2 and execution ports, so two siblings are
//! not two cores. Nothing else in `std` distinguishes them — there is no physical-core,
//! sibling-map, NUMA or cgroup-quota API anywhere in the standard library. This file adds
//! the first half of that: physical cores and the sibling grouping, measured, never
//! inferred from a logical count.
//!
//! ## The three rules this file obeys
//!
//! 1. **Affinity is intersected, always.** Every sibling set read from the kernel is
//!    intersected with `sched_getaffinity` before it is counted. Without that step a
//!    process pinned with `taskset -c 0-3` on a host whose siblings pair as
//!    `(0,6)(1,7)(2,8)(3,9)(4,10)(5,11)` would report the machine's 6 physical cores while
//!    being allowed only 4 CPUs — over-deriving by 50% in exactly the environment where
//!    the operator was most careful. With the intersection it reports 4 physical / 4
//!    logical, which is the truth: that pin bought four *whole* cores.
//! 2. **`physical` is `?usize` and `null` means UNKNOWN.** Never `1`, never
//!    `logical / 2`, never "probably SMT". A caller that cannot get a measurement is told
//!    so and decides for itself; the honest fallback is `logical`, which is what every
//!    caller uses today anyway, so an unprobeable host is never made worse.
//! 3. **A partial probe is not a probe.** If the sibling list for any allowed CPU cannot
//!    be read, the whole `/sys` result is discarded rather than reported as a smaller
//!    core count. Half a topology is a wrong topology.
//!
//! ## What this does NOT measure — named, not approximated
//!
//! * **cgroup CPU quota** (`/sys/fs/cgroup/cpu.max`) is invisible to `sched_getaffinity`.
//!   A container limited to 2.5 CPUs still sees whole physical cores here. Callers that
//!   care must consult the quota themselves; `source` is reported so an operator can see
//!   which instrument answered.
//! * **Heterogeneous cores** (P/E, big.LITTLE) are counted, not classified. A P-core and
//!   an E-core both count as one physical core. `threads_per_core` reports `null` when
//!   the probed cores do not all have the same number of siblings, which is the only
//!   heterogeneity this file can honestly detect.
//! * **Windows** has no binding for `GetLogicalProcessorInformationEx` in this standard
//!   library, so Windows reports `.unknown` rather than an invented number. Note that
//!   `Thread.zig`'s Windows `getCpuCount` (`peb().NumberOfProcessors`) is not
//!   affinity-aware either, so Windows already over-derives its *logical* count today;
//!   this file does not make that worse and does not pretend to fix it.
//!
//! ## Why this takes no `Io` and no `Allocator`
//!
//! Deliberately: the natural consumers of a topology probe are the things that size
//! thread pools and per-CPU data structures, and those run *before* an `Io` exists
//! (`Io.Threaded.init` derives its own `async_limit` from `std.Thread.getCpuCount`, and
//! `heap.SmpAllocator` sizes itself from the same call). A probe that required an `Io`
//! could not serve either of them. So this file uses raw syscalls and fixed buffers, the
//! same shape as `getCpuCount` itself, and is callable from anywhere including startup
//! paths that have no allocator.

const Topology = @This();

const std = @import("../std.zig");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const posix = std.posix;
const mem = std.mem;

/// Logical CPUs this process is ALLOWED to run on — never the machine's total.
/// Same quantity, same syscall, as `std.Thread.getCpuCount`.
logical: usize,
/// Distinct physical cores among `logical`, or `null` when unprobeable.
/// `null` means UNKNOWN. It never means 1, and it never means `logical / 2`.
physical: ?usize,
/// Siblings per physical core, non-null **only** when every physical core found in the
/// affinity mask has the same number of siblings. This is a measurement of the sibling
/// groups, not `logical / physical`: on a machine with mixed core kinds, or when a pin
/// covers some cores wholly and others partially, it is `null` rather than an average
/// nobody can act on.
threads_per_core: ?usize,
/// Which instrument answered. `.unknown` iff `physical == null`.
source: Source,

/// The count to size cache-heavy, capacity-constrained work from: physical cores when
/// they were measured, otherwise the logical count. The fallback is deliberate and is
/// the no-regression choice — `logical` is what callers use today.
pub fn physicalOrLogical(t: Topology) usize {
    return t.physical orelse t.logical;
}

/// The largest logical CPU index this file can represent. Matches the bit width of
/// `posix.cpu_set_t` on Linux (`CPU_SETSIZE` bytes → 1024 bits on both 32- and 64-bit),
/// so the affinity mask is never truncated by this file's own limits.
pub const max_cpus = 1024;

/// Identifies one physical core among the cores discovered in the affinity mask. Ids are
/// dense (`0..physical`) and are assigned in ascending CPU-index order; they are *not*
/// kernel core ids and mean nothing outside one `detect` call.
pub const CoreId = u16;

/// `sibling_map` entry for a CPU that is outside the affinity mask, or whose core could
/// not be determined.
pub const core_none: CoreId = std.math.maxInt(CoreId);

/// Which instrument produced `Topology.physical`. Reported so a caller can print it: an
/// operator diagnosing a bad worker count needs to know not just what was derived but
/// from what.
pub const Source = enum {
    /// Linux `/sys/devices/system/cpu/cpu<N>/topology/{thread_siblings_list,core_cpus_list}`.
    /// The only source that yields a sibling map.
    sys_topology,
    /// Linux `/proc/cpuinfo` `physical id` + `core id` pairs. Present on x86; absent on
    /// most other architectures, where it degrades to `.unknown`.
    proc_cpuinfo,
    /// Darwin `sysctlbyname("hw.physicalcpu")`. Yields counts only, no sibling map, and
    /// is not affinity-aware.
    sysctl,
    /// No instrument answered. `physical` is `null` and callers must fall back to
    /// `logical` — which is exactly what they do today, so this is a no-regression path.
    unknown,
};

/// Errors are exactly `std.Thread.getCpuCount`'s, and for the same reason: the only
/// failure this file *raises* is a failure to learn the logical count. Every topology
/// failure below that degrades to `physical = null` instead, because a missing topology
/// is a known-unknown, not an error.
pub const Error = std.Thread.CpuCountError;

pub const DetectOptions = struct {
    /// Optional out-buffer receiving, for each logical CPU index, the `CoreId` of the
    /// physical core it belongs to — `core_none` for CPUs outside the affinity mask or
    /// when no sibling map could be measured. Only `.sys_topology` and `.proc_cpuinfo`
    /// fill it. It is fully reset to `core_none` whenever the probe degrades, so a
    /// caller can never read a half-filled map and mistake it for a complete one.
    sibling_map: ?*[max_cpus]CoreId = null,
};

/// Probes the host's CPU topology, intersected with this process's affinity mask.
///
/// Cheap enough to call once at startup (one `sched_getaffinity`, then at most one small
/// `/sys` read per *physical core*, since siblings are resolved in one read). Not
/// memoized: this file has no global state, and a caller that wants memoization owns
/// that decision, including whether a stale answer is acceptable across CPU hot-plug.
pub fn detect(options: DetectOptions) Error!Topology {
    if (options.sibling_map) |map| @memset(map, core_none);
    switch (native_os) {
        .linux => return detectLinux(options),
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => return detectDarwin(),
        else => return .{
            .logical = try std.Thread.getCpuCount(),
            .physical = null,
            .threads_per_core = null,
            .source = .unknown,
        },
    }
}

// ----------------------------------------------------------------------------------
// Linux
// ----------------------------------------------------------------------------------

fn detectLinux(options: DetectOptions) Error!Topology {
    // This is the same call `getCpuCount` makes, and the reason `logical` here and
    // `getCpuCount()` elsewhere can never disagree.
    const affinity = try posix.sched_getaffinity(0);
    const logical: usize = @intCast(posix.CPU_COUNT(affinity));

    if (sysTopology(affinity, options)) |t| return .{
        .logical = logical,
        .physical = t.physical,
        .threads_per_core = t.threads_per_core,
        .source = .sys_topology,
    };

    // `/sys` did not answer completely. Discard whatever partial map it left before
    // trying the older instrument: rule 3, a partial probe is not a probe.
    if (options.sibling_map) |map| @memset(map, core_none);

    if (procCpuinfo(affinity, options)) |t| return .{
        .logical = logical,
        .physical = t.physical,
        .threads_per_core = t.threads_per_core,
        .source = .proc_cpuinfo,
    };

    if (options.sibling_map) |map| @memset(map, core_none);
    return .{
        .logical = logical,
        .physical = null,
        .threads_per_core = null,
        .source = .unknown,
    };
}

const Grouping = struct {
    physical: usize,
    threads_per_core: ?usize,
};

/// Reads `/sys/devices/system/cpu/cpu<N>/topology/thread_siblings_list` for every CPU in
/// the affinity mask, intersecting each sibling set with that mask.
///
/// Returns `null` — not a partial answer — if any allowed CPU's topology cannot be read.
fn sysTopology(affinity: posix.cpu_set_t, options: DetectOptions) ?Grouping {
    var core_of: [max_cpus]CoreId = @splat(core_none);
    var core_size: [max_cpus]u32 = @splat(0);
    var next_core: CoreId = 0;

    var cpu: usize = 0;
    while (cpu < max_cpus) : (cpu += 1) {
        if (!maskIsSet(affinity, cpu)) continue;
        if (core_of[cpu] != core_none) continue; // already claimed by an earlier sibling

        var path_buf: [96]u8 = undefined;
        var data_buf: [4096]u8 = undefined;
        const list = readSiblingList(cpu, &path_buf, &data_buf) orelse return null;

        const id = next_core;
        // Saturating in practice: `next_core` cannot exceed `max_cpus`, which is far
        // below `core_none`. Checked anyway so a future `max_cpus` bump cannot silently
        // collide with the sentinel.
        if (id == core_none) return null;
        next_core += 1;

        var members: u32 = 0;
        var it = mem.splitScalar(u8, list, ',');
        while (it.next()) |raw_range| {
            const range = mem.trim(u8, raw_range, " \t\r\n");
            if (range.len == 0) continue;
            const lo, const hi = parseRange(range) orelse return null;
            var sib = lo;
            while (sib <= hi) : (sib += 1) {
                if (sib >= max_cpus) break;
                // RULE 1: the affinity intersection. Everything else in this file is
                // bookkeeping; this line is the finding.
                if (!maskIsSet(affinity, sib)) continue;
                if (core_of[sib] != core_none) continue;
                core_of[sib] = id;
                members += 1;
            }
        }
        // Defensive: every kernel lists a CPU among its own siblings, but a topology file
        // that did not would otherwise leave this CPU uncounted and shrink the answer.
        if (core_of[cpu] == core_none) {
            core_of[cpu] = id;
            members += 1;
        }
        core_size[id] = members;
    }

    if (next_core == 0) return null;
    if (options.sibling_map) |map| map.* = core_of;
    return .{
        .physical = next_core,
        .threads_per_core = uniformGroupSize(core_size[0..next_core]),
    };
}

/// Opens `thread_siblings_list`, falling back to `core_cpus_list` (the newer kernel
/// spelling). Returns the file's contents, trimmed.
fn readSiblingList(cpu: usize, path_buf: []u8, data_buf: []u8) ?[]const u8 {
    const names = [_][]const u8{ "thread_siblings_list", "core_cpus_list" };
    for (names) |name| {
        const path = std.fmt.bufPrint(
            path_buf,
            "/sys/devices/system/cpu/cpu{d}/topology/{s}",
            .{ cpu, name },
        ) catch return null;
        if (readWholeFile(path, data_buf)) |bytes| {
            const text = mem.trim(u8, bytes, " \t\r\n");
            if (text.len != 0) return text;
        }
    }
    return null;
}

/// Parses `"6"` or `"0-3"` into an inclusive bound pair.
fn parseRange(range: []const u8) ?struct { usize, usize } {
    if (mem.findScalar(u8, range, '-')) |dash| {
        const lo = std.fmt.parseUnsigned(usize, mem.trim(u8, range[0..dash], " \t"), 10) catch return null;
        const hi = std.fmt.parseUnsigned(usize, mem.trim(u8, range[dash + 1 ..], " \t"), 10) catch return null;
        if (hi < lo) return null;
        return .{ lo, hi };
    }
    const only = std.fmt.parseUnsigned(usize, range, 10) catch return null;
    return .{ only, only };
}

/// `/proc/cpuinfo` fallback, modelled on the parser shape already used by
/// `lib/std/zig/system/linux.zig`, but streamed with fixed buffers so it needs no `Io`.
///
/// Distinct `(physical id, core id)` pairs among the CPUs in the affinity mask are the
/// physical cores. Architectures whose `/proc/cpuinfo` omits those keys (most non-x86)
/// yield `null` here, which is correct: absent instrument, UNKNOWN answer.
fn procCpuinfo(affinity: posix.cpu_set_t, options: DetectOptions) ?Grouping {
    const unset = std.math.maxInt(u32);
    var phys_id: [max_cpus]u32 = @splat(unset);
    var core_id: [max_cpus]u32 = @splat(unset);

    if (!scanCpuinfo(&phys_id, &core_id)) return null;

    var keys: [max_cpus]u64 = undefined;
    var key_core: [max_cpus]CoreId = undefined;
    var key_count: usize = 0;

    var core_of: [max_cpus]CoreId = @splat(core_none);
    var core_size: [max_cpus]u32 = @splat(0);
    var next_core: CoreId = 0;

    var cpu: usize = 0;
    while (cpu < max_cpus) : (cpu += 1) {
        if (!maskIsSet(affinity, cpu)) continue;
        // A CPU we are allowed to run on whose core we cannot name means the answer is
        // incomplete, and an incomplete core count is a wrong core count.
        if (phys_id[cpu] == unset or core_id[cpu] == unset) return null;

        const key: u64 = (@as(u64, phys_id[cpu]) << 32) | core_id[cpu];
        const id = id: {
            for (keys[0..key_count], key_core[0..key_count]) |k, c| {
                if (k == key) break :id c;
            }
            const fresh = next_core;
            if (fresh == core_none) return null;
            next_core += 1;
            keys[key_count] = key;
            key_core[key_count] = fresh;
            key_count += 1;
            break :id fresh;
        };
        core_of[cpu] = id;
        core_size[id] += 1;
    }

    if (next_core == 0) return null;
    if (options.sibling_map) |map| map.* = core_of;
    return .{
        .physical = next_core,
        .threads_per_core = uniformGroupSize(core_size[0..next_core]),
    };
}

/// Streams `/proc/cpuinfo` a chunk at a time, filling `phys_id` / `core_id` indexed by
/// the `processor` number. Returns false if the file could not be read at all.
///
/// Lines longer than `line_buf` are skipped whole rather than split, so an oversized
/// `flags` line can never be mistaken for a `core id` line.
fn scanCpuinfo(phys_id: *[max_cpus]u32, core_id: *[max_cpus]u32) bool {
    const fd = openRead("/proc/cpuinfo") orelse return false;
    defer closeFd(fd);

    var chunk: [4096]u8 = undefined;
    var line_buf: [128]u8 = undefined;
    var line_len: usize = 0;
    var line_overflow = false;
    var current: ?usize = null;
    var any = false;

    while (true) {
        const n = posix.read(fd, &chunk) catch return false;
        if (n == 0) break;
        for (chunk[0..n]) |byte| {
            if (byte != '\n') {
                if (line_len < line_buf.len) {
                    line_buf[line_len] = byte;
                    line_len += 1;
                } else {
                    line_overflow = true;
                }
                continue;
            }
            if (!line_overflow) {
                if (cpuinfoLine(line_buf[0..line_len], &current, phys_id, core_id)) any = true;
            }
            line_len = 0;
            line_overflow = false;
        }
    }
    if (!line_overflow and line_len != 0) {
        if (cpuinfoLine(line_buf[0..line_len], &current, phys_id, core_id)) any = true;
    }
    return any;
}

/// Handles one `key : value` line. Returns true if the line carried topology data.
fn cpuinfoLine(
    line: []const u8,
    current: *?usize,
    phys_id: *[max_cpus]u32,
    core_id: *[max_cpus]u32,
) bool {
    const colon = mem.findScalar(u8, line, ':') orelse return false;
    const key = mem.trim(u8, line[0..colon], " \t");
    const value = mem.trim(u8, line[colon + 1 ..], " \t\r");
    if (mem.eql(u8, key, "processor")) {
        const n = std.fmt.parseUnsigned(usize, value, 10) catch {
            current.* = null;
            return false;
        };
        current.* = if (n < max_cpus) n else null;
        return true;
    }
    const cpu = current.* orelse return false;
    const n = std.fmt.parseUnsigned(u32, value, 10) catch return false;
    if (mem.eql(u8, key, "physical id")) {
        phys_id[cpu] = n;
        return true;
    }
    if (mem.eql(u8, key, "core id")) {
        core_id[cpu] = n;
        return true;
    }
    return false;
}

// ----------------------------------------------------------------------------------
// Darwin
// ----------------------------------------------------------------------------------

/// `hw.physicalcpu` is the counterpart of the `hw.logicalcpu` that `Thread.zig`'s
/// `getCpuCount` already reads on Darwin.
///
/// Named residual: neither sysctl is affinity-aware, and Darwin exposes no affinity mask
/// to intersect with. So rule 1 cannot be applied here; `source` reports `.sysctl` so a
/// caller can tell that this answer has weaker provenance than a `.sys_topology` one.
/// Read-verified only — no Darwin host executed this.
fn detectDarwin() Error!Topology {
    const logical = try std.Thread.getCpuCount();
    var count: c_int = undefined;
    var count_len: usize = @sizeOf(c_int);
    const physical: ?usize = switch (posix.errno(posix.system.sysctlbyname(
        "hw.physicalcpu",
        &count,
        &count_len,
        null,
        0,
    ))) {
        .SUCCESS => if (count > 0) @intCast(count) else null,
        else => null,
    };
    return .{
        .logical = logical,
        .physical = physical,
        .threads_per_core = null,
        .source = if (physical != null) .sysctl else .unknown,
    };
}

// ----------------------------------------------------------------------------------
// Shared helpers
// ----------------------------------------------------------------------------------

fn uniformGroupSize(sizes: []const u32) ?usize {
    if (sizes.len == 0) return null;
    const first = sizes[0];
    if (first == 0) return null;
    for (sizes[1..]) |s| if (s != first) return null;
    return first;
}

fn maskIsSet(set: posix.cpu_set_t, cpu: usize) bool {
    const Elem = @typeInfo(posix.cpu_set_t).array.child;
    const elem_bits = @bitSizeOf(Elem);
    const index = cpu / elem_bits;
    if (index >= set.len) return false;
    const shift: std.math.Log2Int(Elem) = @intCast(cpu % elem_bits);
    return (set[index] >> shift) & 1 != 0;
}

fn openRead(path: []const u8) ?posix.fd_t {
    return posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0) catch null;
}

fn closeFd(fd: posix.fd_t) void {
    _ = posix.system.close(fd);
}

/// `/sys` and `/proc` files report a size of 0, so this reads until EOF rather than
/// trusting `stat`.
fn readWholeFile(path: []const u8, buf: []u8) ?[]const u8 {
    const fd = openRead(path) orelse return null;
    defer closeFd(fd);
    var used: usize = 0;
    while (used < buf.len) {
        const n = posix.read(fd, buf[used..]) catch return null;
        if (n == 0) break;
        used += n;
    }
    return buf[0..used];
}

test "detect agrees with getCpuCount on the logical count" {
    // Oracle-free half of the check: whatever else the probe reports, the logical count
    // is the same syscall `getCpuCount` makes, so a disagreement is a bug in this file.
    // The topology half needs a host oracle (`lscpu -e`) and is a queued verification
    // item, not a unit test — a test that asserts "6 physical" would only be asserting
    // the machine it happened to run on.
    const t = detect(.{}) catch return error.SkipZigTest;
    const logical = std.Thread.getCpuCount() catch return error.SkipZigTest;
    try std.testing.expectEqual(logical, t.logical);
    if (t.physical) |p| {
        try std.testing.expect(p >= 1);
        try std.testing.expect(p <= t.logical);
        try std.testing.expect(t.source != .unknown);
    } else {
        try std.testing.expectEqual(Source.unknown, t.source);
        try std.testing.expectEqual(@as(?usize, null), t.threads_per_core);
    }
}
