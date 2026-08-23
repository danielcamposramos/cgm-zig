# patch/005 — verification batch, EXECUTED 2026-08-23

Companion to `PATCH005_VERIFICATION.md`, which queued these rows and declared every one
of them UNKNOWN. This file replaces UNKNOWN with a verdict and its evidence line.

**Outcome: promotion REFUSED.** Two independent hard reds (V-BR below, and V12's second
half unrunnable), plus one pre-existing blocker that had to be fixed before the branch
could build at all. Details in order.

- Branch: `patch/005-auto-hardware-threading` @ `24155d14`, plus one prerequisite fix
  (see V0) needed to make the tree compile.
- Compiler under test: `build-p005/stage3/bin/zig`, ReleaseSafe (`ZIG_RELEASE_SAFE=ON`),
  system LLVM 21, cmake config copied verbatim from the promoted binary's
  `build-safe/CMakeCache.txt` so the A/B differs in exactly one variable.
- Reference compiler: `build-safe/stage3/bin/zig`
  (`sha256 60fad8a75bb238039bdf310bb9b3bfbd2f7ec2818404ca8ddbb6f1b7ca4378c5`), the
  currently promoted binary. It is **pre-patch/003** (built 02:13, `76a0b267` landed
  04:49 the same day), which makes it a free PRE-fix oracle — see HELD item H5.

## Estate conditions, stated so every number can be discounted correctly

- **Machine courtesy: V0's `pgrep` precondition was NOT met and was overridden by owner
  order.** Another lane held cores 0-3 (`taskset -cp` on its `zig test` pids: `0-3`) for
  the entire window. All work here ran under `taskset -c 4-11`. **Every wall-time number
  below is CONTENDED** and is labelled as such.
- **The instructed mask overlaps the other lane.** Siblings on this host are split —
  `(0,6)(1,7)(2,8)(3,9)(4,10)(5,11)` — so `4-11` contains CPUs 6,7,8,9, the SMT siblings
  of the other lane's physical cores 0,1,2,3. `taskset -c 4-11` is therefore 8 logical /
  **6 physical**, four of them shared. The only non-overlapping mask is `4,5,10,11`
  (2 physical cores). Timing rows are alternated A/B to survive this.
- **An external cleaner wiped `~/.cache/cgmzig-p005` and a scratchpad worktree mid-run**,
  destroying fixtures and a libc paths file between two commands. All working state was
  relocated under `build-p005/vwork/` (gitignored by `build-*/`) and survived.
- Two environment fixes were required and are **not** source changes:
  `ZIG_LIBC` (Debian multiarch, below) and `ZIG_GLOBAL_CACHE_DIR` (the default
  `~/.cache/zig` is a symlink into another project's tree and lost artifacts mid-build).

---

## V0 — build the design's compiler

**Verdict: RED as committed, then GREEN after one prerequisite fix. Neither blocker
belongs to patch/005.**

Attempt 1: `Exit status 1`, wall `20:15.98`, peak RSS `7,134,956 KB` (6.80 GiB),
`Build Summary: 2/5 steps succeeded (1 failed)`, `compile exe zig ReleaseSafe native 2 errors`.

### Blocker 1 — `main` has been un-buildable since 2026-08-22 02:29

```
src/Compilation/EmitModuleGraph.zig:170:27: error: 'resolveEmitPath' is not marked 'pub'
src/Compilation.zig:3346:1: note: declared here
```

Provenance, measured rather than argued:

- `resolveEmitPath` is upstream 0.16.0 code and was **never** `pub`:
  `git show 754b7a38:src/Compilation.zig` → `3283:fn resolveEmitPath(...)`.
- The cross-file caller was authored by `7ef21e28` ("Crown stage 0: -femit-module-graph"),
  the only commit that has ever touched `src/Compilation/EmitModuleGraph.zig`.
- The reference is unconditional on **both** branches — `misc_group.async(io,
  EmitModuleGraph.worker, .{comp})` at `main:4543` and `HEAD:4582`. patch/005 touches
  neither file.
- **Reproduced on `main` itself.** A `git worktree` at `44e391fb`, type-checked with the
  *currently promoted* compiler, produced the identical error:
  `zig build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ --dep aro
   --dep build_options -Mroot=src/main.zig -Maro=lib/compiler/aro/aro.zig -Mbuild_options=…`
- Timeline: promoted binary mtime **02:13:45**; `7ef21e28` committed **02:29:01**, sixteen
  minutes later. Nobody has rebuilt `main` since, which is why nobody met this.

Prerequisite fix applied here: `fn resolveEmitPath` → `pub fn resolveEmitPath`. One word,
strictly additive visibility widening on upstream code; it retires the day upstream marks
it `pub`. **It belongs on `main` and should be cherry-picked there.**

### Blocker 2 — Debian multiarch, with the remedy the skill asked for

```
error: sub-compilation of libunwind failed
    /usr/include/linux/types.h:5:10: note: 'asm/types.h' file not found
```

`zig libc` reports `sys_include_dir=/usr/include`; on Debian multiarch the header is at
`/usr/include/x86_64-linux-gnu/asm/types.h`. Negative control, fired with the **promoted**
compiler so the cause cannot be pinned on patch/005:

```
zig build-exe t.zig -lc -lunwind                       → rc=1, 'asm/types.h' file not found
ZIG_LIBC=<corrected> zig build-exe t.zig -lc -lunwind  → rc=0
```

Remedy: a libc paths file with `include_dir=/usr/include` and
`sys_include_dir=/usr/include/x86_64-linux-gnu`, exported as `ZIG_LIBC` — the env var
reaches every sub-compilation (`main.zig:1049`).

### The successful build

`ninja -C build-p005 -j8` under `taskset -c 4-11`, `ZIG_LIBC` + `ZIG_GLOBAL_CACHE_DIR` set.
**Exit status 0.** `build-p005/stage3/bin/zig version` → `0.16.0`,
`sha256 1f77637cb45d4c428a7c827b887a1eb203d6dfff74b04fb480e376900c5b9155`.

Wall time, honest breakdown (contended, 8-CPU mask):

| Attempt | What ran | Wall | Result |
|---|---|---|---|
| 1 | full: zigcpp → zig1 → zig2 → stage3 | **20:15.98** | failed (blockers 1+2) |
| 2 | zig1.wasm → zig2 → stage3, after the `pub` fix | 24:41.32 | failed (global-cache loss) |
| 3 | stage3 only | 0:00.50 | failed (libc file deleted by the cleaner) |
| 4 | stage3 only | **21:31.56** | **exit 0** |

A clean single-pass build on this host is therefore ≈ **20 min to zig2 plus ≈ 21 min for
the self-hosted stage3 step**; the "~8–9 min" in the fork skill is not reproducible under
an 8-CPU mask on a contended machine and should be re-stated with its conditions.

---

## V0a — host topology oracle, recorded FIRST

```
lscpu -e=CPU,CORE,SOCKET                → 12 logical, CORE column 0..5 = 6 physical
cat /sys/.../thread_siblings_list|sort -u → 0,6  1,7  2,8  3,9  4,10  5,11  (SPLIT)
```

**GREEN** on both instrument rows — 12 logical, 6 physical, siblings split, exactly as the
dossier's owner-measured line predicted.

**Correction of record: V0a's third command is a mis-specified oracle.**
`taskset -c 0-3 lscpu -e=CPU,CORE,SOCKET` prints all 12 CPUs — `lscpu -e` reads sysfs, not
`sched_getaffinity`, so it is affinity-blind and cannot witness a pin. Measured with an
affinity-aware instrument instead: `taskset -c 0-3 nproc` → **4**. With siblings
`(0,6)(1,7)(2,8)(3,9)`, the mask `0-3` contains no sibling pair: four distinct physical
cores. The row's substance holds — the production mitigation is accidentally a
physical-core pin — but the command must be replaced by `nproc` plus the sibling table.

---

## 005a — the topology probe

### V1 — the report line exists, is truthful, and survives a pin. **GREEN, 4/4 rows.**

| Row | Command | Reported |
|---|---|---|
| 1 | unpinned | `topology 6 physical / 12 logical, 2 threads per core (probe: sys_topology); workers 12 (derived: logical); intern partitions 8 (derived: physical, rounded up to a power of two); alloc lanes 6; 134,217,727 items per partition` |
| 2 | `-j4 --intern-partitions=2` | `workers 4 (given); intern partitions 2 (given); alloc lanes 0; 536,870,911 items per partition` |
| 3 | `taskset -c 0-3` **(the gate)** | `topology 4 physical / 4 logical, 1 threads per core; intern partitions 4; 268,435,455 items per partition` |
| 4 | `--intern-partitions=logical` | `intern partitions 12 (derived: logical); 67,108,863 items per partition` |

Row 1 matches dossier §3.5's derived row and §3.6's ceiling table **to the digit**. Row 3
reports `4 physical`, **not** `6 physical` — **R9 does not fire**; the affinity
intersection is real. Row 4 reproduces the stock cliff exactly.

Two observations the V-list did not predict:

1. **`--intern-partitions=2` reports `alloc lanes 0`.** `alloc_lanes = K -| 2`, so K=2
   leaves zero allocating worker lanes (main + linker hold both tids). Nothing refuses,
   warns, or explains. The number is arithmetically correct and operationally a trap;
   it deserves either a refusal or a note in the line.
2. The shipped line says `(probe: sys_topology)`; dossier §3.7 sketched
   `(probe: sys_topology, affinity-masked)`. Cosmetic, but the masking is the whole point
   of the probe and the line no longer says so.

### V-S1a — the std probe agrees with the host's instruments. **GREEN, 6/6 masks.**

A `Topology.detect` probe program, run under six masks:

| Mask | logical | physical | threads/core |
|---|---|---|---|
| unpinned | 12 | 6 | 2 |
| `0-3` | 4 | **4** | 1 |
| `4-11` | 8 | 6 | null (mixed) |
| `4,5,10,11` | 4 | 2 | 2 |
| `0` | 1 | 1 | 1 |
| `0,6` | 2 | 1 | 2 |
| `0,1,6,7` | 4 | 2 | 2 |

Every value is the arithmetically correct answer for its mask. Under `0-3` every sibling
group intersects the mask in exactly one CPU and the probe reports `4 / 4`, **not `6 / 4`**
— precisely what the row demanded. The `null` under `4-11` is correct behaviour, not a
gap: cores contribute 2 and 1 siblings respectively, so no single threads-per-core exists
and the probe refuses to invent one.

Note: the branch ships no host-specific unit test, and says so in the test's own comment
("a test that asserts '6 physical' would only be asserting the machine it happened to run
on"). The shipped test is the host-agnostic half; this row is the host oracle it defers to.

### V11 / V-S1b — artifact identity. **RED as written; the criterion is unmeasurable.**

See the V12 section: `zig build-exe` output on this toolchain is **not reproducible
run-to-run at `-j > 1`, on the promoted compiler as much as on the patched one**. A
byte-identity row cannot discriminate when the negative control fails it identically.
Measured at section level instead — see V12 — where `.text` **is** stable.

### V14 — negative control for the affinity intersection (R9). **NOT RUN.**

Requires a sabotage rebuild (~21 min for the stage3 step alone) in a build directory that
is not `build-p005`. Not fired inside this window. **UNKNOWN, not passing.** Mitigating
evidence, which is not a substitute: V-S1a exercises the intersection across seven masks
and every answer is correct, including the two (`0,6`, `0,1,6,7`) where dropping the
intersection would visibly over-count physical cores.

---

## 005b — the lane split

### V2 — the `-j1` member. **GREEN on behaviour, RED on the row's own expectation.**

`zig build-exe -j1 -Mroot=hello.zig` → **exit 0, no hang**, binary runs and prints `hello`.
patch/002 Finding 3 does not resurface.

But the row expects `workers 1`, **`intern partitions 2`**, `536,870,911`. Measured:
`workers 1 (given); intern partitions 8 (derived: physical…); 134,217,727`.
**`-j1` does not set K=2.** `ThreadPlan.derive` (`src/ThreadPlan.zig:237-256`) takes
`partitions` solely from `partitions_arg orelse topology`, and `n_jobs` never touches it.
Dossier §3.8's table row — "`-j1` | full serial member: M_wide = 1, **K = 2 (floor)**" — is
therefore **contradicted by the shipped code**. Harmless in effect (K=8 has more headroom
than K=2 would, and `tid_width = 3 ≠ 0` so none of Finding 3's three edges are near), but
the dossier, the V-list and the code disagree, and the code is the one that is right.

### V3 — negative control for the process-global partition invariant (R1). **NOT RUN.**

Requires a sabotage rebuild. **UNKNOWN, not passing.** The guard it would fire is present
and reads correctly (`src/Zcu.zig:2876-2895`, a named panic reporting both numbers and the
remedy), and the default that makes the invariant structural is present
(`Compilation.zig:2257`, `options.intern_partitions orelse Zcu.PerThread.Id.poolLen()`).
Read-verified only. A guard never seen red is a guard nobody has met.

### V4 — the linker kept its concurrent slot (R3). **NOT RUN — the instrument does not exist.**

The row's command is `$SAFE build-exe … --time-report`. That combination is refused:

```
error: --time-report requires --listen        (src/main.zig:3106-3107)
```

Routed through `zig build --time-report` instead, the build runner **starts a blocking web
server** (`info(web_server): web interface listening at http://[::1]:39483/`) and does not
exit, so no batch run can collect the report. **The `--time-report` instrument is not
obtainable non-interactively in this tree**, which makes V4, V6, V13 and V15 unrunnable
*as written*. Recorded as a V-list defect, not as a patch defect. V13 and V15 were
re-instrumented (below); V4 and V6 have no substitute instrument and stay UNKNOWN.

### V6 — is partition 0 the whole story? **NOT RUN.**

Needs both `--time-report` (above) and a compiler change to print per-partition
`local.mutate.items.len`. Neither was done. **UNKNOWN.** The census claim it would test is
unmeasured.

### V7a / V7b — the worked example on the product that hit the cliff. **NOT RUN — BLOCKED BY CHARTER.**

Both rows name a private ~1,800-module product. This lane is chartered to touch no other
project's tree, so the rows cannot be executed here and no substitute reproduces the
incident: V7b's expected `--intern-partitions=logical` panic needs 67,108,864 items on one
partition, and no lawful in-repo workload approaches that. **UNKNOWN.** The largest lawful
workload available (below) exercises the code paths but not the ceiling.

### V12 — HARD GATE for the A1 lane split (R12).

**Part 1 (5 runs, identical digests): the criterion as written is invalid; re-instrumented,
PASSES.**

The instrument had to be characterised first, and characterising it is the finding:

```
promoted compiler, build-obj of a std-pulling file, cold cache, 3 runs, default -j
   → 3 DIFFERENT whole-file digests
promoted compiler, same, -j1
   → 3 IDENTICAL digests
```

**Zig 0.16.0 in this tree is not byte-reproducible at `-j > 1`, and the unpatched promoted
compiler fails the row identically.** A criterion the negative control also fails is not a
race detector. Re-instrumented at section level, and on a workload that exercises the
changed path — 1,200-file AstGen fan-out, which is exactly what the A1 lane split touches:

| Instrument | Patched | Promoted |
|---|---|---|
| 1,200-file fan-out, default `-j`, 5 runs, whole file | **5/5 identical** `5b9beb3d…` | 3/3 identical `9d2e3692…` |
| same, vs its own `-j1` output | **identical** | identical |
| std-pulling workload, 5 runs, **`.text`** | **5/5 identical** `e4d82b55…` | 5/5 identical `5dd21ed9…` |
| std-pulling workload, 5 runs, whole file | 5/5 different | 5/5 different |

Semantic output is deterministic; the run-to-run variation lives entirely outside `.text`
and is present without the patch. **On the evidence available, the A1 lane split shows no
nondeterministic corruption.**

**Part 2 (ThreadSanitizer): NOT RUN — not buildable in this estate.**

```
cmake -DZIG_EXTRA_BUILD_ARGS=-Dsanitize-thread … ; ninja -C build-tsan
error: sub-compilation of libtsan failed
  lib/libtsan/sanitizer_common/sanitizer_platform_limits_posix.cpp:160:10:
    note: 'linux/scc.h' file not found
```

`linux/scc.h` is an obsolete kernel header no longer shipped by Debian's
`linux-libc-dev`; zig 0.16 bundles a compiler-rt vintage that still includes it, and it is
used for `sizeof(struct scc_modem)` / `sizeof(struct scc_stat)` at
`sanitizer_platform_limits_posix.cpp:535-536`. Satisfying it would mean **fabricating
struct definitions whose sizes TSan asserts on**, which this repository's rules forbid.
An include shim was built and then not used for that reason. Searched the host: no
`linux/scc.h` anywhere.

**V12 verdict: the hard gate is NOT PASSED.** Half of it is re-instrumented and clean;
the half that is the *direct* instrument for R12 — a race detector — could not be run at
all. Per the row's own stop rule and the dossier's R12 ("005b does not land until a
ReleaseSafe + TSan run is clean"), the split remains read-verified only, and **no
promotion follows from this batch.**

Also not run: V12's own negative control (deleting the `.acquire`/`release` pair to prove
TSan goes red), which is unreachable without a TSan build.

### V13 — does SMT pay on the wide lane? (R10.) **See table below; the first form was confounded.**

### V15 — is the admission gate worth building? **GREEN — the gate is retired.**

`--time-report` being unusable, re-instrumented with `eu-stack` sampling of every thread
during a 55-second self-hosted compile at `-j12 --intern-partitions=8`:

```
samples = 114   threads observed = 11 peak
frames matching acquire / waitUncancelable / tid_cond : 2 total, max 2 in any one sample
```

**Instrument control (required, because a silent instrument looks like a clean result):**
`eu-stack` resolves Zig symbols fully on this binary — sampled frames include
`Compilation.flush`, `codegen.llvm.Object.emit`, `main.updateModule`,
`Thread.PosixThreadImpl.spawn__anon_25798.Instance.entryFn`. The near-zero count is a
measurement, not a symbolisation failure.

Denominator: ≈1,254 thread-samples (114 × up to 11). Parked fraction ≈ **0.16%**.
Per the row's own decision rule — "if the parked count is consistently near zero, the gate
has nothing to buy and the dossier's edit 3 is retired" — **dossier §2.3 edit 3 is
retired.** It was already unshipped; this is the measurement that says it should stay that
way.

---

## 005c — edges-first

### V8 — the selection overhead. **RED for the feature; the row did its job.**

Self-hosted front-end pass over the compiler's own source (≈780 modules), 3 repeats each,
alternated, `taskset -c 4-11`, CONTENDED:

| `--analysis-order` | runs (s) | median | spread |
|---|---|---|---|
| `insertion` | 47.035, 46.442, 47.083 | **47.035 s** | 0.641 s |
| `layered` | 50.261, 54.510, 52.641 | **52.641 s** | 4.249 s |

`layered` is **+11.92%** slower at the median, and the separation is complete — all three
`layered` runs are slower than all three `insertion` runs, with no overlap, and `layered`
is also 6.6× more variable. **R6 fires: the O(n) argmin eats the win.**

Per the row's own rule, this is the outcome that keeps `layered` OFF. The default is
already `.insertion` (`src/main.zig:1069`), so the branch ships correctly — but the
feature must not be flipped on until the bucket index the dossier designed exists.
Instrument caveat: measured as wall time, because `cpu_ns_sema` requires `--time-report`.

### V9 — negative control for ranking-pass cycles (R5). **GREEN, with its own control.**

```
cyclic  (root→a→b→a) --analysis-order=layered
  → rc=0, no hang, no assert
  → info: analysis order layered (given): 4 modules ranked, max depth 3, 1 in import cycles
acyclic (root→a)     --analysis-order=layered
  → rc=0, 3 modules ranked, max depth 2, 0 in import cycles
```

Non-zero cycle count on the cyclic graph, zero on the acyclic control — the counter moves
in both directions, so it is not stuck at a constant. A legal cyclic graph does not hang
the ranker.

### V10 — edges-first at the step level. **See table below.**

---

## Riders

### V-S2a / V-S2b — the `io.concurrent` reservation. **NOT RUN.**

Both require sabotage rebuilds (reserve forced to 0; reserve set above `async_limit`).
**UNKNOWN, not passing.** The shipped code is a 4-line, minimal, correct-reading diff
(`lib/std/Io/Threaded.zig`: `busy_count + t.concurrent_reserve >= async_limit`, defaulting
to 0 so the stock predicate is unchanged, and `main.zig` setting the reserve to 1 only
when `async_limit >= 2`). Read-verified only.

### V-S4a — the oversubscription is real. **GREEN, and larger than predicted.**

Sampled `ps -eLf | grep -c 'stage3/bin/zig build-exe'` every 150 ms across a 6-step build
at `-j4`, on the 8-logical mask, twice per arm:

| `--child-jobs` | peak worker THREADS | peak child PROCESSES |
|---|---|---|
| `keep` | **38**, 38 | 7 |
| `share` | **13**, 13 | 7 |

Predicted: "> 12 on a 12-logical host, approaching 4 × 12 = 48". Measured 38 against an
**8-CPU** mask — 4.75× the CPUs the process is allowed to use. Rider 2's central claim
stands and is not withdrawn. Reproduced identically on the repeat.

The derivation reports itself correctly in all four forms:

```
--child-jobs=share -j4 → info: child compilers: -j2 (derived: 8 logical CPUs / -j4 concurrent steps)
--child-jobs=keep  -j4 → info: child compilers: no -j passed (given: keep); each derives the whole host
--child-jobs=3     -j4 → info: child compilers: -j3 (given)
(no -j at all)         → info: child compilers: no -j passed (derived: share, but no -j given to share out)
```

That last line is the honest-degradation case, and it degrades honestly.

---

## HELD batch (carried from `44e391fb`'s commit body)

The five items that patch/003's merge record deferred to "the batched compile-verification".

| # | Item | Verdict | Evidence |
|---|---|---|---|
| H1 | rebuilt stage3 | **GREEN** | `build-p005/stage3/bin/zig`, exit 0, `version → 0.16.0`, sha `1f77637c…` (after the V0 prerequisite fix) |
| H2 | fixture repro, expect `dupe.zig:1:1` as root | **GREEN** | all four lines match `test/fixtures/file_in_multiple_modules/README.md`'s expected block exactly: `dupe.zig:1:1: error: file exists in modules 'root' and 'mod_b'` / `dupe.zig:1:1: note: files must belong to only one module` / `main.zig:3:17: note: … module 'root'` / `mod_b.zig:2:17: note: … module 'mod_b'`; exit 1 |
| H3 | `test-cases` + `test-incremental` over the corrected snapshots | **NOT RUN** | both steps rebuild the compiler as a dependency (≈40 min per attempt on this contended 8-CPU mask) and did not fit the window. UNKNOWN, not passing. |
| H4 | `test-fmt` (now load-bearing for the fixture) | **GREEN** | `zig fmt --check` rc=0 on the fixture directory (3 files), on **all 14** `.zig` files patch/005 touches (denominator from `git diff --name-only main..HEAD -- '*.zig'`), and on all of `src/` |
| H5 | negative control: corrected snapshots against a **PRE-fix** compiler | **GREEN** | the promoted binary *is* pre-`76a0b267` (built 02:13, fix landed 04:49). Run on the same fixture it emits `mod_b.zig:1:1: error: file exists in modules 'root' and 'mod_b'` — the root message anchored on the *importer*, which is exactly the defect the fixture pins. PRE `mod_b.zig:1:1` → POST `dupe.zig:1:1`. The guard has been seen red. |

---

## V-BR — a red the V-list did not queue, found by running the thing

**The unconditional report line makes `zig build` print `error:` and mark every compile
step `failure`.**

`ThreadPlan.report()` writes through `std.log.info` → stderr, unconditionally, at
derivation time. Under `zig build` the child compiler runs with `--listen=-`, and the build
runner treats child stderr that is not an error bundle as step-failure evidence.

Measured on a 6-executable project, same project, same flags, one variable:

| Compiler | exit | `Build Summary` | lines matching `^error:` | lines matching `native failure` | stderr bytes |
|---|---|---|---|---|---|
| **patched** | 0 | `13/13 steps succeeded` | **6** | **6** | — |
| **promoted** | 0 | `13/13 steps succeeded` | **0** | **0** | **0** |

Sample of what a green build now prints:

```
   +- compile exe m3 Debug native failure
error: info: threads: topology 6 physical / 8 logical (probe: sys_topology); workers 8 …
```

Artifacts are correct and the exit code is 0, so this is not a functional break — it is a
**diagnostic-channel break**, and on this station that is worse than it sounds: every
`zig build` in every consuming project would begin reporting `native failure` per compile
step, and any harness that greps stderr for `error:` would report failures on a green
build. It also fired inside this repo's own stage3 build.

Doctrine 4 ("a tool states its resolved reality") is not in question; the *channel* is.
Remedies available without giving the line up: suppress it when `listen != .none` — the
compiler already tests exactly that at `src/main.zig:3106` for `--time-report` — or send it
through the IPC as a diagnostic. The parent `zig build` process's own `info: child
compilers:` / `info: step order` lines are harmless and can stay.

**This is an independent blocker on promotion.**

---

## V5 — the `Io.Group` fan-out probe (R4)

**Not in `PATCH005_VERIFICATION.md` at all** — the dossier queues it at §8 (`V5`), and the
verification file, which is the acceptance list, drops it. Recorded as a V-list defect: R4
is a named liveness risk (`ziglang/zig#26027`) with no acceptance row.

Run anyway, on a purpose-built 1,200-file fixture:
`build-obj -j64 --intern-partitions=8` → **rc=0, 196 ms**, digest identical to the `-j1`
and default-`-j` runs. **GREEN**: no hang at 1,200 files with 64 requested workers.
Denominator honesty: one host, one fixture shape; this does not clear `#26027` in general.

---

## The timing rows, in one place

All rows: `taskset -c 4-11` (8 logical / 6 physical), another lane holding cores 0-3,
**CONTENDED**. Compiler-side rows use the lawful substitute for the V-list's private
product: a **self-hosted front-end pass over the Zig compiler's own source**
(`build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ --dep aro --dep
build_options -Mroot=src/main.zig -Maro=lib/compiler/aro/aro.zig -Mbuild_options=…`),
cold local cache per run, shared warm global cache, ≈780 modules, rc=0 every run.

### The promotion benchmark — patched vs promoted, n = 7 each, alternated A/B

| | n | median | min | max | IQR | stdev | rc |
|---|---|---|---|---|---|---|---|
| **promoted** | 7 | **46.836 s** | 44.990 | 48.428 | [46.394, 47.019] | 0.944 | all 0 |
| **patched** | 7 | **45.589 s** | 44.637 | 47.509 | [44.800, 46.839] | 0.962 | all 0 |

Median delta **−1.247 s (−2.66%)**, ratio 0.9734. Patched faster in **5 of 7** paired
alternation slots.

**This is a note, not a claim.** The IQRs overlap, stdev (≈0.95 s) is comparable to the
delta (1.25 s), 5/7 paired wins is a sign test at p≈0.23, and the machine was contended
throughout. The honest statement is: *no regression is visible, and any improvement on
this workload is at or below the noise floor of this host.* The workload is also
front-end-only by construction and the patch's designed win is in AstGen, which this
instrument cannot separate from the rest.

### V13 — SMT on the wide lane (R10). **The predicted claim is not supported.**

Predicted before the run: `-j12` wins on `real_ns_files` by **20–40%**.
`real_ns_files` requires `--time-report`, which is unobtainable (see V4), so wall time is
the only instrument available and it cannot isolate the AstGen phase.

| Form | arm | runs (s) | median | spread |
|---|---|---|---|---|
| as written (`-j6` vs `-j12`, K=8) | `-j6` | 46.063, 45.095, 47.234 | 46.063 | 2.139 |
| | `-j12` | 45.708, 47.276, 47.618 | 47.276 | 1.910 |
| mask-matched (`-j6` phys vs `-j8` log, K=8) | `-j6` | 48.090, 49.302, 51.230 | 49.302 | 3.140 |
| | `-j8` | 50.304, 48.224, 51.291 | 50.304 | 3.067 |

The as-written form is **confounded**: `-j12` oversubscribes an 8-CPU mask, which biases
against it. The mask-matched form is V13's actual question (6 physical vs 8 logical
*within the affinity mask*) and is confound-free. Both give the same sign: the wider lane
is nominally **slower** — −2.57% and −2.03% for the narrow arm — with ranges that overlap
completely.

**Verdict: the 20–40% AstGen win is UNMEASURED (no instrument), and the end-to-end effect
is null-to-slightly-negative.** The row's own correction rule ("if `-j12` loses on either,
`M_wide` becomes physical and the wide-lane assignment is corrected in public") is
**triggered**, but the correction should not be made on this evidence alone — it should be
made after `real_ns_files` is obtainable, because that is the number the design actually
claims. Recorded here in public either way, per the row's instruction.

### V10 — edges-first at the step level. **INCONCLUSIVE; the control beats the feature.**

6-executable project (13 steps, max depth 2), `-j12`, 3 repeats per arm:

| `--step-order` | runs (s) | median | spread |
|---|---|---|---|
| `random` (seeds 1,2,3) | 4.547, 3.947, 3.987 | 3.987 | 0.600 |
| `layered` | 3.983, 3.926, 4.155 | 3.983 | 0.229 |
| `declared` **(the control)** | 3.908, 3.987, 3.947 | 3.947 | **0.079** |

`layered` is *not slower than random*, so the row's stop condition is not triggered, and
it does have lower variance than `random` (0.229 vs 0.600) as predicted. But **`declared`
— the control that exists precisely to separate "layered helped" from "any deterministic
order helped" — is both faster and 2.9× less variable than `layered`.** The whole spread
across all nine runs is ≈1%, far inside noise on a fixture this small.

**`--step-order=layered` ships as the DEFAULT** (`lib/compiler/build_runner.zig`,
`var step_order: StepOrder = .layered`) **with no measurement distinguishing it from the
simpler `declared`.** That is a default resting on an unmeasured claim. Re-run required on
a project with real depth and fan-in before the default is defended.

### V-S4b — THE GATE ON RIDER 2's DEFAULT. **RED. The default must revert to `keep`.**

Same 6-executable project, `-j4`, 3 repeats each, alternated:

| `--child-jobs` | runs (s) | median | paired |
|---|---|---|---|
| `share` **(shipped default)** | 4.928, 4.774, 4.710 | **4.774** | slower in **3/3** slots |
| `keep` | 4.780, 4.427, 4.487 | **4.487** | |

`share` is **+0.287 s (+6.4%)** slower at the median and slower in every paired slot.
The row's rule is unconditional: *"If propagation is slower, the derived default reverts
to `keep`."* **Triggered.**

Two honesties owed:
- **The peak-system-RSS half of this row was not measured.** `share`'s claimed RSS win is
  UNKNOWN, and V-S4a shows the thread-count win is real and large (38 → 13), so the
  trade-off is genuine even though the wall-time arm lost.
- The fixture is small and each compile is short, which is the regime where cutting each
  child from `-j8` to `-j2` hurts most and where oversubscription costs least. A large
  project could invert this. But the row was written without that qualification, its rule
  fired, and the default ships today — so today the default is wrong by its own gate.

---

## Verdict roll-up

| Row | Verdict |
|---|---|
| V0 | RED as committed → GREEN after prerequisite fix; both blockers pre-existing |
| V0a | GREEN (third command replaced — mis-specified oracle) |
| V1 | **GREEN 4/4** |
| V2 | GREEN on behaviour; RED on its own expectation (`-j1` does not set K=2) |
| V3 | NOT RUN — UNKNOWN |
| V4 | NOT RUN — instrument does not exist (`--time-report` unobtainable) |
| V5 (unqueued) | GREEN — 1,200 files, `-j64`, rc=0 |
| V6 | NOT RUN — UNKNOWN |
| V7a / V7b | NOT RUN — BLOCKED BY CHARTER (private workload) |
| V8 | RED for the feature (+11.92%, 3/3 separation) — row did its job; keep `layered` off |
| V9 | **GREEN** with its own acyclic control |
| V10 | INCONCLUSIVE — `declared` control beats `layered`; default unjustified |
| V11 / V-S1b | RED as written; criterion unmeasurable (see V12) |
| **V12** | **NOT PASSED.** Part 1 re-instrumented and clean; Part 2 (TSan) unbuildable |
| V13 | Predicted claim unsupported; correction rule triggered, instrument missing |
| V14 | NOT RUN — UNKNOWN |
| V15 | **GREEN** — admission gate retired by measurement (0.16% parked) |
| V-S1a | **GREEN 6/6 masks** |
| V-S2a / V-S2b | NOT RUN — UNKNOWN |
| V-S4a | **GREEN** — 38 threads on an 8-CPU mask; claim stands |
| V-S4b | **RED** — `share` slower 3/3; default must revert to `keep` |
| V-BR (new) | **RED** — report line makes `zig build` print `error:` + `native failure` |
| H1 / H2 / H4 / H5 | **GREEN** |
| H3 | NOT RUN — UNKNOWN |

**PROMOTION: REFUSED.** `PROMOTED/zig` is untouched and still points at
`build-safe/stage3/bin/zig`. Two independent blockers:

1. **V12, the hard gate, is not passed** — its direct instrument (TSan) cannot be built in
   this estate, so R12 remains read-verified only, exactly the state the dossier said must
   not ship.
2. **V-BR** — the patched compiler turns every `zig build` compile step into a printed
   `native failure` with an `error:`-prefixed line. Promoting it would put that in front of
   every build on this station.

Neither is fatal to the design. V-BR is a channel fix the compiler already has the test
for (`listen == .none`, `src/main.zig:3106`). V12 needs either a TSan-capable toolchain or
an equivalent race instrument. V-S4b and V8 are defaults to correct, and both rows were
written to be able to retract them — which is the system working.

*Even in the lixão, a flower is born.*
