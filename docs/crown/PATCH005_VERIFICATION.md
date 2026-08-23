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
*Expect:* **(item counts UPDATED for the 31-bit `Index`; the `CaptureValue` widening
doubled every one of them. The pre-widening value is kept in brackets, because a log
from before the widening is still a valid log and a reader must be able to tell a
version difference from a defect.)*

1. `topology 6 physical / 12 logical, 2 threads per core (probe: sys_topology)`,
   `workers 12 (derived: logical)`,
   `intern partitions 8 (derived: physical, rounded up to a power of two)`,
   `alloc lanes 6`, **`268,435,455 items per partition`** *(was 134,217,727)* — matching
   V0a's oracle and the dossier §3.6 ceiling table **to the digit**.
2. `workers 4 (given)`, `intern partitions 2 (given)`, **`1,073,741,823 items per
   partition`** *(was 536,870,911)*.
3. **The affinity check, and it blocks 005a if it fails:** `4 physical / 4 logical`,
   `intern partitions 4`, **`536,870,911`** *(was 268,435,455)*. A `6 physical` there is
   risk R9 firing.
4. `intern partitions 12 (derived: logical)`, **`134,217,727`** *(was 67,108,863)* — the
   stock-equivalent row.

**This row is now doing a second job**, and it is worth naming: it is the only cheap,
end-to-end check that `ThreadPlan.index_bits` and `InternPool.getIndexMask` agree after
the widening. If they ever drift apart, the print line reports a ceiling the allocator
does not honour — and that line is exactly what an operator consults after meeting
patch/001's named refusal. A wrong ceiling there sends them to the wrong remedy.

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
*Expect:* exit 0, no hang, report line shows `workers 1 (given)`, **`intern partitions 8
(derived: physical…)`**, **`268,435,455`**. A hang is patch/002 Finding 3 edge 1 (evented
tid starvation) resurfacing.

**CORRECTED TWICE, and both corrections are the row being wrong rather than the code.**
This row originally expected `intern partitions 2` and `536,870,911`.
1. **`-j1` does not set K = 2.** V2 measured K = 8; `ThreadPlan.derive` takes `partitions`
   from `partitions_arg orelse topology` and `n_jobs` never touches it. The expectation
   was copied from dossier §3.8's pre-split flag table. See §3.8's own correction note.
2. **The item count then doubled** with the `CaptureValue` widening (31-bit `Index`).

The behavioural half of the row — *does `-j1` still work* — was GREEN throughout and is
what the row exists for. `tid_width = 3`, so none of Finding 3's three edges (all at
`tid_width == 0`) come near. **R8 does not fire.**

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
268,435,455 items per partition` *(was 134,217,727 before the `CaptureValue` widening)*;
the compile exits 0 with **no patch/001 panic** — the incident needed 67,108,864 items on
one partition, so the margin under test is now **4.00×**, up from the 2.00× this row was
written against. Both numbers are stated because the change in margin is a *result*, not
a restatement: the topology derivation bought the first 2×, the widening bought the
second. All six physical cores busy during Sema+codegen and all twelve logical during
AstGen. **The band, fixed now:** wall time at or below the recorded `taskset -c 0-3` PRE,
peak RSS within 15% of it.

**This row remains BLOCKED BY CHARTER** — it names a private product this lane may not
touch — and the margin above is therefore *derived arithmetic*, not a measurement. It is
UNKNOWN whether the real workload exits 0, and nothing in this file may report otherwise.

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

**THE NOISE FLOOR, MEASURED — because a difference is only a signal above the noise.**
The signature set is not stable run to run even for a *single unchanged binary*, so
"any new context is a race" would be a false-positive generator. Measured with
`partner_tools/helgrind_diff.py`: the **promoted (unpatched) compiler against itself**,
4 runs of the identical workload, all 6 pairings, counting filtered
(`InternPool|Zcu|PerThread`) contexts present in one run and absent from the other:

| pairing | filtered A-only | filtered B-only |
|---|---|---|
| cal1 vs cal2 | 7 | 5 |
| cal1 vs cal3 | 3 | 5 |
| cal1 vs cal4 | 6 | 5 |
| cal2 vs cal3 | 3 | 7 |
| cal2 vs cal4 | 3 | 4 |
| cal3 vs cal4 | 3 | 0 |
| **range** | **3–7** | **0–7** |

Total context counts across those runs: 343, 339, 353, 343 — themselves varying by 14
with nothing changed.

**DETECTION THRESHOLD, set from that floor and fixed before the comparison is run: a
patched-vs-reference filtered difference of ≤ 7 contexts is INDISTINGUISHABLE FROM
NOISE and must be reported as such, never as a pass and never as a finding.** Only a
difference materially above 7 — and reproducible across repeats — is signal, and even
then it is a lead to be read by a human, not a verdict.

**Honest statement of strength, owed because this substitutes for a hard gate: this is
weaker than TSan and does not become TSan by being run.** Two limits, both measured
rather than supposed:

1. Helgrind's blindness to Zig's futex primitives means it can **miss** real races
   (false negatives), so a clean differential is *evidence of absence of new races in
   the covered paths*, not proof of absence.
2. The 0–7 noise floor means it cannot **see** a small number of new race sites
   (limited resolution). A single genuinely new race would very likely hide inside it.

**The positive control has NOT been fired.** It is the sabotage build — delete the
`.acquire`/`release` pair from the import-discovery tail, rebuild, and confirm the
differential rises decisively above the floor. That needs a stage3 rebuild this lane's
build budget did not include; the patch and its recipe are prepared under
`partner_tools/vharness/sabotage/`. **Until it is fired, this instrument's
discrimination is UNPROVEN and every V12 part-2 result reports so beside its number.**
A guard never seen red is a guard nobody has met — and this one has now at least been
measured for how quietly it whispers.

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

**V16 — THE HANG CLASS. A starved tid pool must COMPLETE or REFUSE BY NAME, never hang.**
*(Added 2026-08-23 after the harness measured the hang. This is a REGRESSION PIN for a
whole failure class, not a check on one flag.)*

**What it pins, and why it is a class.** patch/001 exists to abolish silent failures in
the InternPool; patch/002 Finding 3 refused a one-line change specifically because it
re-introduced one ("*a silent hang, zero bytes on stderr: the exact failure class
patch/001 exists to abolish*"). patch/005's `(K, M_wide)` decoupling **re-introduced it
by a different route**: `K` and the worker count are now independent, so a configuration
can exist with workers but no lane for them to allocate in.

The mechanism, traced rather than inferred:
`Zcu.PerThread.Id.allocate(n)` seeds the assignable-tid pool with **`n − 1`** entries
(`src/Zcu/PerThread.zig:99-112`). The linker acquires one tid through `io.concurrent` and
**holds it for the entire compilation** (dossier §1.1 row A7). So the lanes actually
available to allocating workers are **`K − 2`** — which is exactly the `alloc lanes`
number the report line already prints. At `K = 2` it is **zero**, and every worker that
asks for a tid blocks forever in `tid_cond.waitUncancelable`
(`src/Zcu/PerThread.zig:116-136`). No error, no timeout, no output.

**`K = 2` IS REACHABLE WITHOUT ANY FLAG**, which is what makes this a release blocker
rather than a footgun:

**This table was CORRECTED after measurement.** The first version of this row predicted
hangs on two configurations that in fact completed. The wrong predictions are kept beside
the measurements rather than silently edited out — a row that quietly rewrites its own
prediction is worth nothing as a pin.

| Configuration | Derivation | Predicted | **MEASURED** |
|---|---|---|---|
| `-j4 --intern-partitions=2` | given K = 2, workers 4 | hang | **rc=124 hang** ✓ |
| `taskset -c 4,10,5,11` = **2 phys / 4 logical**, **NO FLAGS** | K = 2, workers 4 | hang | **rc=124 hang** ✓ |
| `taskset -c 4,5` = 2 phys / 2 logical, no flags | K = 2, workers 2 | hang | **rc=0 — PREDICTION WRONG** |
| `taskset -c 4,10` = 1 phys / 2 logical, no flags | K = 2, workers 2 | hang | **rc=0 — PREDICTION WRONG** |
| `-j2` / `-j3 --intern-partitions=2` | K = 2 | — | **rc=0** (see below) |
| `-j1 --intern-partitions=2` | K = 2, workers 1 | rc=0 | **rc=0** ✓ |

**The true condition is `alloc_lanes == 0` AND `workers ≥ 4`**, not `workers > 1`: below
four workers the async budget keeps allocating work on the main thread, which holds
`Id.acquire`'s recursive shortcut and never touches the pool.

**`-j2`/`-j3` completing is not a reprieve — it is the same defect in a quieter costume.**
With zero lanes, no allocating work can *ever* leave the main thread, so those runs
**silently degrade to serial** while reporting the worker count the operator asked for.
That is why the shipped guard refuses the *structural* condition
(`alloc_lanes == 0 and workers > 1`) and not the measured one: refusing only `≥ 4` would
bless a configuration that cannot deliver what it advertises, and would hard-code today's
`concurrent_reserve` arithmetic into a liveness invariant.

**The decisive row is the second.** 2 physical / 4 logical is the ordinary shape of a
2-core CI container, and it hung on `build-obj hello.zig` with **no flags at all**, having
first printed `intern partitions 2 (derived: physical...); alloc lanes 0`. The control is
unambiguous: the unpatched reference completed the identical command on the identical mask
(rc=0), and also completed `-j4` on two physical cores. Stock 0.16.0 cannot reach the
state, because one integer set both quantities. **The `(K, M_wide)` decoupling introduced
it.**

```
# every row must terminate. none may hang.
timeout 120 $SAFE build-obj -j4 --intern-partitions=2 -Mroot=<hello>;  echo "rc=$?"
timeout 120 taskset -c <2 physical cpus> $SAFE build-obj -Mroot=<hello>; echo "rc=$?"
timeout 120 taskset -c <1 cpu>           $SAFE build-obj -Mroot=<hello>; echo "rc=$?"
timeout 120 $SAFE build-obj -j1 --intern-partitions=2 -Mroot=<hello>;  echo "rc=$?"
```

*Expect, and BOTH outcomes are green — the row forbids one specific thing:*
- **rc = 0** (the configuration was derived into something workable and says so), **or**
- **a named refusal** naming the partition count, the lane count, and the remedy.
- **`rc = 124` (the `timeout` firing) is RED for every row above.** A silent hang is the
  one outcome this row exists to make impossible.

The `-j1` row must stay **rc = 0**: the full serial member is legitimate, `alloc lanes 0`
is harmless when nothing runs concurrently, and a refusal there would break a working
configuration. **A guard that refuses `-j1` has over-fired and is itself a defect.**

**Negative control (fired, not assumed):** the pre-fix binary must produce `rc=124` on
row 1. A guard whose red has never been seen is a guard nobody has met — and here the
red is measurable without a sabotage rebuild, because the defect shipped.

**Why `alloc lanes` had to become load-bearing.** Before this row, `alloc_lanes` appeared
**only** in `src/ThreadPlan.zig` — computed, printed, and enforced nowhere. The compiler
printed `alloc lanes 0` and then hung, having stated the exact cause of its own hang and
done nothing about it. **A number a tool reports but never acts on is decoration**, and
this row exists to keep it acting.

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
