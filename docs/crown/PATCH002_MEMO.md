# patch/002 — decision memo: the partition question, measured to its end

*2026-08-22. Measure phase: Claude Sonnet. Adversarial verify: Claude Opus (max
effort). Disposition: Claude Fable 5. No code lands from this cycle — that is the
finding, not a failure.*

## What the production incident was

First live firing of patch/001's named refusal, on a real ~1,800-module build at
`-j12`: *"item index 67,108,864 exceeds this thread's limit of 67,108,863 ...
split 16 ways (4 bits) ... comptime analysis of one unit is serial, so it all
lands in a single partition."* Missed by exactly one item. Interim lever deployed
and holding: the build now runs under `taskset` at 4 CPUs → 4-way split →
268M items per partition.

## Finding 1 — the "adaptive split" already ships upstream

`tid_width` / `tid_shift_30/31/32` are runtime `InternPool` fields computed once
in `init()` from the real thread count, which traces to `-j`/CPU count in
`main.zig`. There is no frozen 16-way constant to fix; the 16-way split on a
12-CPU host is the existing adaptive mechanism doing what it was designed to do
(round up to the next power of two).

## Finding 2 — adaptivity is orthogonal to the incident

The overflowing build was parallel (`-j12`). It overflowed because **one serial
comptime unit concentrates all interning into a single tid partition regardless
of how the split was derived**. No split policy keyed on thread count can close
a gap created by workload concentration. "More adaptive" was the wrong axis, and
we now know it by measurement rather than by argument.

## Finding 3 — the `-j1` floor (`@max(threads, 2)`) is load-bearing

The one genuine-looking gap — a true `-j1` run being denied the full 30-bit
space — was implemented as a one-line floor drop and **rejected in adversarial
review on three independent grounds**, each at exactly the edge the change
enables (`tid_width = 0`):

1. **Deadlock**: `Zcu.PerThread.Id.allocate(n)` fills the assignable-tid pool
   with `n-1` entries; at `n=1` the pool is empty, and the `evented` I/O mode's
   `acquire()` has no main-thread shortcut — it blocks forever on a condition
   nothing can signal. Silent hang, zero bytes on stderr: the exact failure
   class patch/001 exists to abolish.
2. **The proof breaks at width 0**: `tid_shift_32 = tid_shift_31 +| 1` saturates
   at 31 (`u5` field), so the "shift = 32 − width" claim is false precisely and
   only at `tid_width = 0` — the single case the patch adds — across six 32-bit
   encodings. (Verified by replica execution at thread counts 1, 2, 3, 5, 7, 8,
   12, 16, 17, 64, 127: the mismatch fires at 1 alone.)
3. **The remedy becomes impossible**: patch/001's message says "lower `-j` to
   widen each partition" — actionable while the floor guarantees travel below
   you, nonsense at `-j1`.

The review's collision hunt is itself a keeper: hand-executed encode/decode over
eleven thread counts × boundary tids × boundary indices found **zero collisions
and zero decode failures** in the shipped arithmetic. The non-overlap invariant
holds by disjoint bit-ranges — within the preconditions the floor protects.

## Finding 4 — the real lever, priced, awaiting the go-ahead

The only change that adds headroom on multi-CPU hosts is widening the confining
field: `CaptureValue.idx: u30` (`InternPool.zig:1925-1927`, packed `u32` with a
2-bit tag). Measured price: **48 pre-existing sites** (45 InternPool.zig,
5 Sema.zig, 1 Type.zig, minus patch/001's own 3 mentions), **6 documented
trailing-data encoding blocks** (one `u32` word per capture), and **3+ length
counters**. Bounded, real, and NOT the 427-site global-`u64`-Index rewrite,
which stays refused.

**New coupled finding, beyond what patch/001 knew**: the same widening path
touches captured `Nav.Index` truncation. Because that coupling is new
information, this memo requests an explicit go-ahead before any CaptureValue
work begins, notwithstanding the earlier general authorization — the scope
changed, so the authorization should be renewed against the true scope.

## Recommendation

Hold the taskset interim lever (proven sufficient for current builds). Take
shape (b) — the CaptureValue widening — as its own reviewed cycle once the
go-ahead lands. Do not touch the `-j1` floor unless someone wants that feature
badly enough to pay for all three edges above in one coherent patch; if so,
this memo is its requirements list.
