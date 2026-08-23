# patch/005 — queued verification

*Every row below is a command and the observation that decides it. **None of them have
run.** The branch that carries them was authored while another process owned this
machine's execution window: `zig build`, `zig test`, and any stage2/stage3 rebuild were
forbidden, and the only `zig` invocation made was `zig ast-check`, which needs no build
cache and contends with nothing.*

**The one rule this file exists to enforce:** a row that did not run reports **UNKNOWN**.
Never zero, never green, never "should be fine". A guard nobody has seen go red is a guard
nobody has met.

**Status of every row: UNKNOWN.**

> **SUPERSEDED 2026-08-23 — this batch has RUN.** Per-row verdicts, their evidence lines,
> and four defects in the list itself (V0a's affinity-blind oracle; V2's `-j1` expectation
> contradicting the code; the `--time-report` instrument being unobtainable, which sinks
> V4/V6/V13/V15 as written; V11/V-S1b's byte-identity criterion, which the *unpatched*
> compiler fails identically) are recorded in
> [`PATCH005_VERIFICATION_RUN_2026-08-23.md`](PATCH005_VERIFICATION_RUN_2026-08-23.md).
> The dossier's **V5** (the `Io.Group` fan-out probe for R4) is missing from this file
> entirely and was run from the dossier instead. **Outcome: promotion REFUSED** — V12 is
> not passed, and the report line breaks the `zig build` diagnostic channel.
> Rows still UNKNOWN after that run: V3, V4, V6, V7a, V7b, V14, V-S2a, V-S2b, and HELD H3.

## What is implemented, and what each piece is worth until its rows fire

| Commit | Piece | Verified today | Gated on |
|---|---|---|---|
| `7106d368` | 005a — `std.Thread.Topology`, compiler seam, report line | `ast-check` only | V0a, V1, V11, V14, V-S1a, V-S1b |
| `016d8987` | 005b — the (M_wide, K, M_alloc) split and the A1 lane split | `ast-check` + one type-system proof (below) | **V12 (HARD)**, V1–V4, V6, V7a, V7b, V13 |
| `2a9ca530` | 005c — edges-first, both levels | `ast-check` only | V8, V9, V10 |
| `0711a34e` | rider 1 — `Io.Threaded` concurrent reserve | `ast-check` only | V-S2a, V-S2b |
| `9a7cbab8` | rider 2 — `-j` reaches child compilers | `ast-check` only | V-S4a, V-S4b |

`ast-check` tally: **14 of 14** touched or added `.zig` files parse and pass AstGen clean
— `lib/compiler/build_runner.zig`, `lib/std/Build.zig`, `lib/std/Build/Step/Compile.zig`,
`lib/std/Io/Threaded.zig`, `lib/std/Thread.zig`, `lib/std/Thread/Topology.zig`,
`src/Compilation.zig`, `src/Compilation/ModuleRanking.zig`, `src/InternPool.zig`,
`src/Sema.zig`, `src/ThreadPlan.zig`, `src/Zcu.zig`, `src/Zcu/PerThread.zig`,
`src/main.zig`. Denominator: the complete set of `.zig` files this branch touches, from
`git diff --name-only`. `ast-check` proves syntax and AstGen. It proves nothing about
types, linkage, or behaviour — which is the entire reason this file exists.

**The one claim that IS stronger than a read.** 005b's A1 lane split moved `updateFile`,
`lockAndClearFileCompileError` and `reportRetryableFileError` from taking a
`Zcu.PerThread` to taking a `*Zcu`. Once the compiler builds, that is a compile-time proof
that the AstGen body reaches no `InternPool` entry point taking a `tid` **by parameter** —
there is no tid in scope to pass. It does not cover mutation reached through a global, and
it is not yet a proof at all, because nothing has been compiled. V12 remains the gate.

---

## Prerequisite

**V0 — build the design's compiler.**
```
pgrep -fa 'zig build-exe|ninja|cgm build'          # machine courtesy: must be empty
cmake -B build-safe -DCMAKE_BUILD_TYPE=ReleaseSafe -DZIG_STATIC_LLVM=OFF -Ddebug-extensions ...
ninja -C build-safe
```
*Expect:* `build-safe/stage3/bin/zig version` → `0.16.0`. ~8–9 min, ~7.6 GiB peak on a
12-core host. `$SAFE` below means that binary.

`-Ddebug-extensions` is not optional: the crash-report machinery is compiled out without
it, and that machinery is the point of a diagnostic build.

---

## 005a — the topology probe

**V0a — the host oracle. Recorded FIRST, so the probe cannot be tuned to agree with
itself.**
```
lscpu -e=CPU,CORE,SOCKET
cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -u
taskset -c 0-3 lscpu -e=CPU,CORE,SOCKET
```
*Expect (owner-measured, 2026-08-22):* 12 logical, 6 physical, sibling pairs
`(0,6)(1,7)(2,8)(3,9)(4,10)(5,11)` — **split**, not adjacent. Consequence to confirm in
the third command: `taskset -c 0-3` selects CPUs whose siblings are 6,7,8,9, so the pin
covers **four distinct physical cores with no cache-sharing siblings at all**. The
existing production mitigation is already, accidentally, a physical-core pin.

**V1 — the report line exists, is truthful, and survives a pin.**
```
$SAFE build-obj -Mroot=test/fixtures/file_in_multiple_modules/main.zig 2>&1 | head -3
$SAFE build-obj -j4 --intern-partitions=2 -Mroot=<same> 2>&1 | head -3
taskset -c 0-3 $SAFE build-obj -Mroot=<same> 2>&1 | head -3
$SAFE build-obj --intern-partitions=logical -Mroot=<same> 2>&1 | head -3
```
*Expect:*
1. `topology 6 physical / 12 logical, 2 threads per core (probe: sys_topology)`,
   `workers 12 (derived: logical)`,
   `intern partitions 8 (derived: physical, rounded up to a power of two)`,
   `alloc lanes 6`, `134,217,727 items per partition` — matching V0a's oracle and the
   dossier §3.6 ceiling table **to the digit**.
2. `workers 4 (given)`, `intern partitions 2 (given)`, `536,870,911 items per partition`.
3. **The affinity check, and it blocks 005a if it fails:** `4 physical / 4 logical`,
   `intern partitions 4`, `268,435,455`. A `6 physical` there is risk R9 firing.
4. `intern partitions 12 (derived: logical)`, `67,108,863` — the stock-equivalent row.

**V11 — stock invocations produce identical artifacts.**
```
$SAFE build-exe <stock args, no new flags>       vs   <stock 0.16.0> build-exe <same>
sha256sum <both outputs>
```
*Expect:* identical digests. **The honest caveat this patch introduces, stated here rather
than discovered later:** the ARTIFACT must be identical; stderr will not be, because the
report line is unconditional by ruling (DOCTRINE.md principle 4, dossier §3.7), and wall
time will not be, because the derived `(M_wide, K)` deliberately differ from stock. This
row checks the artifact half and says so.

**V14 — negative control for the affinity intersection (R9).**
On a scratch copy only: delete the `if (!maskIsSet(affinity, sib)) continue;` line from
`sysTopology` in `lib/std/Thread/Topology.zig`, rebuild, and run under `taskset -c 0-3`.
*Expect:* the line reports `6 physical / 4 logical` — visibly impossible, which is what
makes it a usable control. Restore, verify by checksum, confirm `4 physical / 4 logical`
returns.

**V-S1a — the std probe agrees with the host's instruments.** A `std` unit test asserting
`logical == 12`, `physical == 6`, and that under `taskset -c 0-3` every sibling group
intersects the mask in exactly one CPU. *Expect:* pass unrestricted; `4 / 4` under the
pin, **not `6 / 4`**.

**V-S1b — a new file nobody imports perturbs nothing.**
```
$SAFE build-exe hello.zig     vs    <stock 0.16.0> build-exe hello.zig
```
*Expect:* **byte-identical** artifacts. If a new lazily-imported file changes `lib/std`'s
compiled output, the import is not as lazy as designed.

---

## 005b — the lane split

**V2 — the `-j1` member still works (patch/002 Finding 3 regression guard).**
```
$SAFE build-exe -j1 -Mroot=<small hello world>; echo "exit=$?"
```
*Expect:* exit 0, no hang, report line shows `workers 1`, `intern partitions 2`,
`536,870,911`. A hang is patch/002 Finding 3 edge 1 (evented tid starvation) resurfacing.

**V3 — negative control for R1, the process-global partition invariant.**
On a scratch copy only: make one sub-compilation site pass `.intern_partitions = 2`
explicitly while the parent derives 8 (`src/Compilation.zig:5066` region, or any of the
nine `src/libs/` sites), rebuild, compile anything needing compiler_rt.
*Expect:* the named panic in `Zcu.init` fires, reporting **both** numbers and the remedy.
Then revert and verify by checksum. **This row is why the guard exists**: the default
(`intern_partitions orelse Id.poolLen()`) makes the invariant structural, and this proves
the backstop still bites when someone overrides it.

**V4 — the linker kept its concurrent slot (R3).**
```
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<mid-size project>
```
*Expect:* the time report shows link work overlapping analysis. A run where
`real_ns_decls` ≈ `real_ns` with no link overlap means `error.ConcurrencyUnavailable` was
hit and `link/Queue.zig:70-76` took the serial path. Compare against V-S2a, which tests
the same thing from the `std` side.

**V6 — is partition 0 really the whole story?**
```
$SAFE build-exe -j12 --intern-partitions=2 --time-report -Mroot=<~1,800-module product>
```
with the compiler additionally printing final `local.mutate.items.len` per partition at
exit (the numbers `saveState` already computes at `Compilation.zig:3745-3752`).
*Expect, predicted before the run:* partition 0 holds **≥ 90%** of all interned items and
the rest are near-empty — the direct consequence of the census finding that five of eight
allocating phases are serial and four run on `.main`. **If the partitions are not
lopsided, the census is wrong and the dossier is corrected in public**, not quietly
amended.

**V7a — THE worked example: the derived configuration on the product that hit the cliff.**
```
/usr/bin/time -v $SAFE build-exe -Mroot=<the ~1,800-module product>
```
*Expect, predicted before the run and not adjusted afterward:* the line reports
`6 physical / 12 logical · workers 12 · intern partitions 8 · alloc lanes 6 ·
134,217,727 items per partition`; the compile exits 0 with **no patch/001 panic** — the
incident needed 67,108,864 items on one partition and 134,217,727 is 2.00× that, so the
margin under test is 2×, not "some"; all six physical cores busy during Sema+codegen and
all twelve logical during AstGen. **The band, fixed now:** wall time at or below the
recorded `taskset -c 0-3` PRE, peak RSS within 15% of it.

**V7b — the other two rows of the same table, on the same compiler.**
```
/usr/bin/time -v $SAFE build-exe --intern-partitions=logical -Mroot=<same>   # K=12
/usr/bin/time -v taskset -c 0-3 $SAFE build-exe -Mroot=<same>                # K=4
```
*Expect:* the first **panics by name** with patch/001's message at 67,108,863 —
reproducing the production incident on demand, which is the entire reason
`--intern-partitions=logical` is kept as a member. Confirm the panic's remedy text now
names `--intern-partitions` and not `-j`. The second completes and reproduces the current
mitigation's wall/RSS.

**V12 — HARD GATE for the A1 lane split (R12).**

> **THE CRITERION WAS REPLACED ON 2026-08-23.** The original is preserved verbatim
> below as V12-OLD together with the measurement that invalidated it; V12-NEW is
> **operative**. The gate itself is unchanged and is still a gate — what changed is
> the instrument, because the original instrument was measured to be incapable of
> discriminating the thing it was pointed at.

**What the gate is actually asking**, stated once so no instrument can drift from it:
*does the A1 lane split introduce nondeterminism or a data race that the unpatched
compiler does not already have?* Note the last clause. R12 is a claim about **the
patch**, so every criterion for it must be **differential** against the unpatched
compiler. A criterion that the reference compiler also fails measures the toolchain,
not the change.

---

#### V12-OLD — the original criterion, and its invalidity proof

```
# 1. ReleaseSafe, the full closure, five times -- nondeterministic corruption shows as flakiness
for i in $(seq 5); do $SAFE build-exe -Mroot=<~1,800-module product>; \
    echo "run $i exit=$?"; sha256sum <output>; done
# 2. ThreadSanitizer build of the compiler over a mid-size closure
<tsan stage3> build-exe -Mroot=<mid-size project>
```
*Expected:* 5/5 exit 0 with identical artifact digests, and zero TSan reports naming
`InternPool` or `Zcu.File`.

**Part 1 is INVALID, and this is the measurement that says so:**

```
promoted (UNPATCHED) compiler, build-obj of a std-pulling file, cold cache, default -j
  3 runs -> 3 DIFFERENT whole-file digests
promoted (UNPATCHED) compiler, same workload, -j1
  3 runs -> 3 IDENTICAL digests
```

**Zig 0.16.0 in this tree is not byte-reproducible at `-j > 1`, and the unpatched
compiler fails this row identically.** The row therefore cannot distinguish "the
patch introduced nondeterminism" from "this toolchain is not byte-reproducible in
parallel" — it returns RED for both. A criterion the negative control also fails is
not a race detector; it is a thermometer that reads the room.

The variation was located rather than assumed: it lives **entirely outside `.text`**
(link-time metadata), and `.text` is stable 5/5 on the same workload. That is what
V12-NEW measures instead.

---

#### V12-NEW — OPERATIVE. Deterministic semantic output, differentially.

Two instruments, both run on **patched and reference** binaries so every number has
its control beside it. `N = 5`.

```
# (a) whole-file digest on a 1,200-file AstGen fan-out -- the path 005b changes
for i in $(seq 5); do $ZIG build-obj -Mroot=<generated 1200-file fixture>; sha256sum <out>; done
$ZIG build-obj -j1 -Mroot=<same fixture>; sha256sum <out>   # and compare to the above

# (b) .text SECTION digest on a std-pulling workload, where whole-file is known unstable
for i in $(seq 5); do $ZIG build-obj -Mroot=<std-pulling file>; \
    objcopy -O binary --only-section=.text <out> - | sha256sum; done
```

*Expect:* **(a)** 5/5 identical to each other **and** identical to the `-j1` output;
**(b)** 5/5 identical `.text`. Both must hold for the patched binary, and the
reference binary must be run alongside so the comparison is visible rather than
assumed.

Why this is the right instrument and not merely a weaker one: the fan-out fixture
exercises **exactly the code path the A1 lane split touches** (concurrent AstGen
across many files), where the original workload exercised the whole compiler and
was dominated by an unrelated instability. Narrower, and pointed at the claim.

Measured 2026-08-23, and this is the evidence the criterion was adopted on:

| Instrument | Patched | Reference (unpatched) |
|---|---|---|
| (a) 1,200-file fan-out, whole file, 5 runs | **5/5 identical** `5b9beb3d…` | 3/3 identical `9d2e3692…` |
| (a) vs its own `-j1` output | **identical** | identical |
| (b) std-pulling workload, `.text`, 5 runs | **5/5 identical** `e4d82b55…` | 5/5 identical `5dd21ed9…` |
| V12-OLD part 1 (whole file, std workload) | 5/5 **different** | 5/5 **different** ← the invalidity proof |

**Stop rule (unchanged in force):** any digest mismatch under (a) or (b) on the
patched binary that the reference does not also show **stops the split**. The remedy
is to move `.acquire` back to the top of `workerUpdateFile` and forfeit the wide-lane
win. Not negotiable by argument; only by a clean run.

---

#### V12-NEW part 2 — the race detector. TSan is UNRUNNABLE; the substitute is named.

**ThreadSanitizer cannot be built in this estate**, and the reason is a header, not a
policy:

```
error: sub-compilation of libtsan failed
  lib/libtsan/sanitizer_common/sanitizer_platform_limits_posix.cpp:160:10:
    note: 'linux/scc.h' file not found
```

`linux/scc.h` is an obsolete kernel header Debian's `linux-libc-dev` no longer ships;
zig 0.16 bundles a compiler-rt vintage that still includes it, at
`sanitizer_platform_limits_posix.cpp:535-536`, for `sizeof(struct scc_modem)` and
`sizeof(struct scc_stat)`. **A shim is not lawful here** — TSan asserts on those
sizes, so shimming means fabricating struct definitions a sanitizer trusts. One was
built and deliberately not used. Searched the host: no `linux/scc.h` anywhere.

**NAMED SUBSTITUTE: Valgrind Helgrind / DRD, differentially.** Both are present
(`valgrind-3.27.1`, `helgrind-amd64-linux`, `drd-amd64-linux`) and need **no rebuild**,
which is what makes them reachable where TSan is not.

**Its limitation, measured before it was adopted, not after:** Helgrind does not model
Zig's futex-based `Io.Threaded` primitives, so it cannot see most happens-before edges
and reports enormous false-positive volume. On a trivial `build-obj -j2` with the
**unpatched promoted** compiler:

```
ERROR SUMMARY: 146356 errors from 357 contexts (suppressed: 0 from 0)
   ... at fetchAdd (atomic.zig:53) / Io.Threaded.Future.start (Threaded.zig:761)
```

So the **absolute count is meaningless** — it fails its own negative control exactly
as V12-OLD did, and must never be reported as a pass or a fail on its own.

**The instrument is therefore the DIFFERENCE, never the count.** Run patched and
reference on the identical workload and compare the *set of distinct stack contexts*,
filtered to frames naming `InternPool`, `Zcu`, or `PerThread` — the structures R12 is
actually about. A context present for the patched binary and absent for the reference,
in those files, is the signal. Equal sets are the expected result.

*Expect:* zero `InternPool`/`Zcu`/`PerThread` contexts present in the patched run and
absent from the reference run.

**Honest statement of strength, owed because this substitutes for a hard gate: this is
weaker than TSan and does not become TSan by being run.** Helgrind's blindness to the
synchronisation primitives means it can miss real races, so a clean differential is
*evidence of absence of new races in the covered paths*, not proof. The positive
control that would calibrate it is the sabotage build (delete the `.acquire`/`release`
pair and confirm the differential goes red); until that has been fired, **the
discrimination of this instrument is UNPROVEN and the row reports so.** A guard never
seen red is a guard nobody has met.

**V13 — does SMT actually pay on the wide lane, and does `K−2` oversubscription hurt?
(R10.)**
```
$SAFE build-exe -j6  --intern-partitions=8 --time-report -Mroot=<same product>
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<same product>
```
Three repeats each, alternating. *Predicted before the run:* `-j12` wins on
`real_ns_files` (the AstGen timer, `Zcu/PerThread.zig:157-161`) by **20–40%** and is
within noise on `cpu_ns_sema`. **If `-j12` loses on either, `M_wide` becomes physical and
the wide-lane assignment is corrected in public.**

**V15 — is the admission gate worth building? (NEW — the row that replaces a shipped
mechanism.)**
The dossier's §2.3 edit 3 admission gate is **not shipped**; `M_alloc = K − 2` is enforced
by the pre-existing `available_tids` semaphore instead. This row decides whether the extra
mechanism earns its risk.
```
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<same product>
# while sampling: how many threads sit in Id.acquire's condition wait
perf record -g -p <pid>   # or: repeated `gdb -p <pid> -batch -ex 'thread apply all bt'`
```
*Expect:* count the threads parked in `tid_cond.waitUncancelable` across the run. **If the
parked count is consistently near zero, the gate has nothing to buy and the dossier's
edit 3 is retired.** If it is materially above zero, the gate becomes worth building — and
it must then be built with a permit that cannot leak on a cancellation path, because a
leaked permit hangs the main thread. Note before running: the gate could never have fixed
the inline-async trap (`Io/Threaded.zig:2100-2105` runs past-limit tasks on the caller
whatever an in-flight counter says), so this row measures parking cost and nothing else.

---

## 005c — edges-first

**V8 — the selection overhead, measured before the default could ever flip (R6).**
```
for i in 1 2 3; do $SAFE build-exe --analysis-order=insertion --time-report -Mroot=<same product>; done
for i in 1 2 3; do $SAFE build-exe --analysis-order=layered   --time-report -Mroot=<same product>; done
```
*Expect:* `cpu_ns_sema` differs by less than the run-to-run variance of the three repeats.
**`layered` ships OFF precisely because this has not run.** If it is slower, the O(n)
argmin needs the bucket index the dossier designed and this branch does not carry; if it
is faster, the default flips and that flip is its own commit.

**V9 — negative control for ranking-pass cycles (R5).**
Build a two-module fixture where each `-M` module imports the other, then:
```
$SAFE build-obj --analysis-order=layered -Mroot=<cyclic fixture> 2>&1 | head -3
```
*Expect:* completes, and the ranking line reports a non-zero `in import cycles` count. A
hang or an assert is a hard stop — a legal graph must never hang the ranker.

**V10 — edges-first at the step level does what it claims.**
```
for s in 1 2 3; do $SAFE build --step-order=random --seed $s --summary all -j12; done
for i in 1 2 3; do $SAFE build --step-order=layered --summary all -j12; done
for i in 1 2 3; do $SAFE build --step-order=declared --summary all -j12; done
```
*Expect:* `layered` has lower variance across repeats (it is deterministic) and its wall
time is at or below the random median. `declared` is the control that separates "layered
helped" from "any deterministic order helped". **If layered is slower than random, the
fan-in-descending tie-break is wrong and the counter-claim recorded beside it wins** —
which is why the flag exists rather than the behaviour being hard-coded.

---

## Riders

**V-S2a — the reservation keeps the linker's slot.**
```
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<mid-size project>   # reserve = 1 (shipped)
# and, on a scratch copy with the reserve forced to 0:
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<same>                # reserve = 0
```
Three repeats each. *Expect:* with the reserve, link work overlaps analysis in every
repeat; without it, V4's no-overlap signature appears **at least once** across the three.
**If reserve 0 never starves, the exposure is overstated and this rider is corrected in
public** — the mechanism would still be real, the frequency would not.

**V-S2b — negative control for the reservation.**
On a scratch copy, set `concurrent_reserve` above `async_limit` and run anything.
*Expect:* `io.async` admits **nothing** — every task runs inline via
`Io/Threaded.zig:2100-2105`, observable as a fully serial compile. Restore, verify by
checksum. A guard never seen red is not a guard.

**V-S4a — the oversubscription is real, measured BEFORE the fix.**
```
$SAFE build --child-jobs=keep -j4 <multi-step project> &
while kill -0 $!; do ps -eLf | grep -c 'zig build-exe'; sleep 0.5; done
```
*Predicted before the run and not adjusted afterward:* peak total compiler worker threads
**> 12** on a 12-logical host, approaching 4 × 12 = 48. **If total threads never exceed
12, the central claim is wrong and rider 2 is withdrawn.**

**V-S4b — and the fix is not a pessimisation. THE GATE ON RIDER 2's DEFAULT.**
```
for i in 1 2 3; do /usr/bin/time -v $SAFE build --child-jobs=share -j4 <same project>; done
for i in 1 2 3; do /usr/bin/time -v $SAFE build --child-jobs=keep  -j4 <same project>; done
```
*Expect:* `share` at or below `keep` on wall time, and below it on peak system RSS.
**If propagation is slower, the derived default reverts to `keep`** — the survey lane ruled
that no default ships before this run, the owner's charter ruled that the forwarding
member is the default, and this row is how both are honoured: the default ships and this
run can retract it.

---

## Not queued, and why — each is UNKNOWN, not passing

- **cgroup CPU quota.** `/sys/fs/cgroup/cpu.max` is invisible to `sched_getaffinity` and
  the probe does not consult it, so a container limited to a fraction of a CPU still sees
  whole physical cores. Named in R9; the `probe:` field in the report line is the
  operator's only warning. No container run is queued.
- **The Windows and Darwin arms of the topology probe.** Read-verified only; neither can
  be executed in this estate. Windows returns `.unknown` by construction because there is
  no `GetLogicalProcessorInformationEx` binding in this `lib/std`.
- **Every host other than 6c/12t.** Every number outside the reference row is arithmetic,
  not measurement — including the claim that a 16-physical-core host lands back on the
  cliff.
- **The build runner's `concurrent_limit`.** Left `.unlimited` deliberately (rider 2's
  commit body has the reasoning: its `io.concurrent` users are per-connection web-UI
  tasks). No cap is proposed, so no row tests one.
- **No fuzzing** of the reservation logic or of the ranking pass.
- **The per-step resource ledger** that R2 and the fan-in tie-break both need is not
  implemented and therefore not tested. It is a prerequisite, named, not a detail.

---

*Even in the lixão, a flower is born.*
