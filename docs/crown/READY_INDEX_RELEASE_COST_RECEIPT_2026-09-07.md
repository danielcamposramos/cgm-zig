# Executed release-cost packet — 2026-09-07

**12/12 planned frontend compiles succeeded; the clean-machine acceptance
criterion remains UNFULFILLED.** These are valid, environment-qualified
descriptive measurements of two sealed compiler artifacts. They are not a
clean-machine performance certificate, equivalence proof or promotion clearance.
No additional sample or waiver is authorized by this receipt.

Execution: root orchestrator under Daniel's direction. Packet preparation and
independent source/record/hash/arithmetic review: GPT 6 Astra, senior compiler
partner. Root accepted that independent review at precisely this ceiling.
This document makes the completed execution durable; the
[original packet](READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md) preserves its
unexecuted-at-authoring status, and the earlier README/PLAN 0/12 notes remain
historical snapshots.

## 1. Evidence locality and publication boundary

Every link into `build-*` or `PROMOTED` below is **LOCAL retained evidence**,
not an artifact already published with this Markdown file. Path shorthand:

```text
R = /K3D/GitHub/cgm-zig
Q = R/build-ready-runtime/release-cost-2026-09-07
L = R/build-release-2026-09-06/log-fixed-stage3/lib/zig
```

The [LOCAL independent review](../../build-ready-runtime/release-cost-2026-09-07/ROOT_INDEPENDENT_REVIEW.md) records
the finite audit. The original LOCAL `ROOT_POST.json` remains sealed and
unchanged. Its ambient-monitor metadata contains an identifier unsuitable for
public distribution; this public receipt uses only generic descriptions.
Any future public sanitized derivative must be explicitly declared, retain a
mapping to the original seal and have its own checksum. Never silently replace
the original or ship unsanitized local evidence.

No package, evidence bundle, synchronization, release or default-promotion
verification is completed by these measurements. Candidate packaging may now
be staged and smoke-verified separately as an **unpromoted candidate**. That
permission is not evidence that those still-open gates have passed.

## 2. Exact workload, arms and invocation

The existing `stdpull` fixture calls `std.testing.refAllDecls` over fifteen
standard-library namespaces. It is one small frontend workload, not a maximum
ready-set or large-estate benchmark. Its source is the unchanged copy
`Q/stdpull.zig`, SHA-256
`0261fc36bd2cb5786a841b2f362dd970180ba3d25a4e42d6b65c4c4d8b645d81`.

| Arm | LOCAL compiler | Recorded version | SHA-256 |
|---|---|---|---|
| old, both modes | `R/PROMOTED/stage3-046d6833/bin/zig` | `0.16.0` | `046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11` |
| new, both modes | `R/build-release-2026-09-06/log-fixed-stage3/bin/zig` | `0.16.0+cgm.0399d2b19b` | `d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f` |

The candidate is the uninstrumented logging-fixed shipping artifact, not a
shadow or OOM-control compiler. Workload `-ODebug` does not rebuild either
safety-enabled compiler or change its build configuration. Old/new differences
are artifact differences, not an index-only causal isolation.

Each repetition ran old/default, new/default, old/layered, new/layered, in that
fixed order. There are exactly three repetitions and twelve retained run
directories; no retry, replacement or extra workload execution appears in the
sealed packet. Earlier version checks are identities, not workload samples.

The actual inner argv template, expanded for each named sample, was:

```text
taskset -c 4 /usr/bin/time -v -o Q/<sample>/time.txt
  <sealed old or new compiler> build-exe -j1 --intern-partitions=2
  [--analysis-order=layered, ONLY for layered samples]
  -fno-emit-bin -ODebug --color off --zig-lib-dir L -Mroot=Q/stdpull.zig
```

Square brackets explain the one conditional argument; they are not literal
argv members. Default omits the analysis-order argument. The recorded launcher
is `/usr/bin/python3 -B -c <retained inline body>`, invoking the existing
`vlib.run_cmd` with `mask="4"`, timeout 180 seconds and `rss=False`.
Each complete `ROOT_LAUNCH.json` retains that actual body and argv.
The [packet's full command body](READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md#5-exact-twelve-run-sequence)
remains the reproduction recipe; completed paths must not be overwritten.

The explicit launch environment has exactly these seven keys, with cwd `Q`:

```text
PATH=/usr/bin:/bin
LC_ALL=C
TZ=UTC
PYTHONPATH=R/partner_tools/vharness
ZIG_LIBC=R/build-p005/vwork/libc.txt
ZIG_LOCAL_CACHE_DIR=Q/<sample>/local-cache
ZIG_GLOBAL_CACHE_DIR=Q/<sample>/global-cache
```

Raw `run.json` independently retains the five locale/timezone/libc/cache keys
selected by the inline body, its cwd and timeout. Launch records supply PATH
and PYTHONPATH. This is not an independent full child-execve trace. The actual
argv, successful taskset invocation and one-logical-CPU compiler report agree;
no continuous affinity/process sample was collected inside the compile.

Every sample used its own new local/global compiler caches. Filesystem/page
caches were not flushed; hashing the common library read its files before the
batch. There was no hidden warmup. Automatic installed-library discovery was
not tested because all four arms explicitly pin `L`.

## 3. All twelve raw samples

Harness wall is elapsed monotonic time around the subprocess primitive.
GNU time measures the compiler beneath that wrapper and prints centisecond
wall resolution. Retain both; do not substitute one for the other. RSS below is
GNU-time peak RSS in KiB. `Run.peak_rss_kb` remains null in 12/12 raw records
because `rss=False`; that null is not a measured zero.

Each linked sample directory also retains `time.txt`, empty
`harness.stderr`, and `ROOT_LAUNCH.json`. Compiler stdout is empty in 12/12
samples; its complete stderr is inside `run.json`.

| LOCAL sample, actual order | Harness wall, s | GNU wall text / s | Peak RSS, KiB | Compiler / GNU-time exit |
|---|---:|---:|---:|---:|
| [r1-default-old](../../build-ready-runtime/release-cost-2026-09-07/r1-default-old/run.json) | 1.0459756520031078 | 0:01.04 / 1.04 | 238192 | 0 / 0 |
| [r1-default-new](../../build-ready-runtime/release-cost-2026-09-07/r1-default-new/run.json) | 1.063406456996745 | 0:01.06 / 1.06 | 238552 | 0 / 0 |
| [r1-layered-old](../../build-ready-runtime/release-cost-2026-09-07/r1-layered-old/run.json) | 1.1277708330017049 | 0:01.12 / 1.12 | 238548 | 0 / 0 |
| [r1-layered-new](../../build-ready-runtime/release-cost-2026-09-07/r1-layered-new/run.json) | 1.1066177720022097 | 0:01.10 / 1.1 | 238376 | 0 / 0 |
| [r2-default-old](../../build-ready-runtime/release-cost-2026-09-07/r2-default-old/run.json) | 1.0900564809999196 | 0:01.08 / 1.08 | 238328 | 0 / 0 |
| [r2-default-new](../../build-ready-runtime/release-cost-2026-09-07/r2-default-new/run.json) | 1.0943215799998143 | 0:01.09 / 1.09 | 238616 | 0 / 0 |
| [r2-layered-old](../../build-ready-runtime/release-cost-2026-09-07/r2-layered-old/run.json) | 1.101805844999035 | 0:01.10 / 1.1 | 238608 | 0 / 0 |
| [r2-layered-new](../../build-ready-runtime/release-cost-2026-09-07/r2-layered-new/run.json) | 1.1050723500011372 | 0:01.10 / 1.1 | 238548 | 0 / 0 |
| [r3-default-old](../../build-ready-runtime/release-cost-2026-09-07/r3-default-old/run.json) | 1.079172138001013 | 0:01.07 / 1.07 | 238196 | 0 / 0 |
| [r3-default-new](../../build-ready-runtime/release-cost-2026-09-07/r3-default-new/run.json) | 1.1173285719996784 | 0:01.11 / 1.11 | 238468 | 0 / 0 |
| [r3-layered-old](../../build-ready-runtime/release-cost-2026-09-07/r3-layered-old/run.json) | 1.0921537140020519 | 0:01.09 / 1.09 | 238592 | 0 / 0 |
| [r3-layered-new](../../build-ready-runtime/release-cost-2026-09-07/r3-layered-new/run.json) | 1.116155815001548 | 0:01.11 / 1.11 | 238480 | 0 / 0 |

All 12/12 wrapper processes also returned zero without signal or timeout.
All 12/12 stderr streams contain exactly their expected info reports and no
compiler error, debug/shadow/fault marker or unexpected diagnostic. Thread
reports state workers 1, partitions 2 and one visible logical CPU in 12/12.
All 6/6 layered samples report three ranked modules, maximum depth two and zero
import-cycle members; all 6/6 default samples lack a ranking report.
This report count does not measure the maximum ready-set size.

GNU time reports 99–100% CPU, zero major faults, zero swaps and zero filesystem
input blocks in each of 12/12 samples, with 2–8 involuntary context switches.
These per-process counters do not establish an idle host. Total harness wall
is 13.139837209007965 seconds; this is the sum of twelve samples, not elapsed
batch duration.

## 4. Independently reproduced statistics and full notes

The review read the complete relevant owners in
[vlib.py](../../partner_tools/vharness/vlib.py): `run_cmd` at line 177,
`Timing` at 366, `compare` at 442, thread parser at 605 and rank parser at 676.
Independent arithmetic from the raw samples matches every recorded statistic
and comparison field (floating arithmetic reconciled within 1e-12), including
the full explanatory notes.

All four arms have 3/3 samples, each with exit zero. SD is sample standard
deviation. IQR is unavailable for all 4/4 arms because this owner requires at
least four samples; it is not a zero-width interval.

| Arm | n | Harness median, s | Min / max, s | Spread, s | Sample SD, s | RSS min / median / max, KiB |
|---|---:|---:|---:|---:|---:|---:|
| old_default | 3/3 | 1.079172138001013 | 1.0459756520031078 / 1.0900564809999196 | 0.04408082899681176 | 0.02296227010472152 | 238192 / 238196 / 238328 |
| new_default | 3/3 | 1.0943215799998143 | 1.063406456996745 / 1.1173285719996784 | 0.053922115002933424 | 0.027057534371428767 | 238468 / 238552 / 238616 |
| old_layered | 3/3 | 1.101805844999035 | 1.0921537140020519 / 1.1277708330017049 | 0.03561711899965303 | 0.018420655980887157 | 238548 / 238592 / 238608 |
| new_layered | 3/3 | 1.1066177720022097 | 1.1050723500011372 / 1.116155815001548 | 0.011083465000410797 | 0.006002857511690541 | 238376 / 238480 / 238548 |

Exact comparison direction is B minus A; a positive delta is slower B.
`A wins` counts chronological repetition slots, not a randomized trial.

| A → B | Median delta, s | Delta, % | B/A | A wins | Inside existing heuristic |
|---|---:|---:|---:|---:|---|
| old_default → new_default | 0.015149441998801194 | 1.4038021799620417 | 1.0140380217996203 | 3/3 | true |
| old_layered → new_layered | 0.004811927003174787 | 0.4367309381244935 | 1.0043673093812449 | 2/3 | true |
| new_default → new_layered | 0.0122961920023954 | 1.1236360707057873 | 1.0112363607070578 | 2/3 | true |

The complete retained heuristic notes are:

> delta +0.015s (+1.40%), noise floor (max stdev) 0.027s, IQR overlap None, old_default won 3 of 3 paired slots — INSIDE the noise floor: this is a note, not a claim

> delta +0.005s (+0.44%), noise floor (max stdev) 0.018s, IQR overlap None, old_layered won 2 of 3 paired slots — INSIDE the noise floor: this is a note, not a claim

> delta +0.012s (+1.12%), noise floor (max stdev) 0.027s, IQR overlap None, new_default won 2 of 3 paired slots — INSIDE the noise floor: this is a note, not a claim

All 3/3 comparisons have `iqr_overlap=null` and
`complete_separation=false`. The heuristic uses the larger arm SD (or IQR
overlap when available); it is not a confidence interval, significance test
or causality proof. Here it distinguishes no wall-time regression under its
rule, but cannot certify uncontended or equivalent performance.

The consistent default direction matters: old/default beats new/default in
3/3 paired slots. Candidate-minus-old differences are 17.43080499363714,
4.26509899989469 and 38.15643399866531 milliseconds. Layered cross-artifact
differences are -21.15306099949521, 3.266505002102349 and 24.00210099949618 ms.
Candidate layered-minus-default differences are 43.21131500546471,
10.750770001322962 and -1.1727569981303532 ms. These directions are not erased
by the heuristic's inside-noise label.

All three new/default RSS observations exceed all three old/default
observations. Their median difference is **+356 KiB (+0.14945674990344088%)**.
Layered old→new median RSS changes by -112 KiB (-0.04694206008583691%);
candidate default→layered changes by -72 KiB (-0.03018209866192696%).
These are small descriptive differences, not an RSS hypothesis test or a
claim of zero memory cost. No new materiality threshold has been invented,
and the wall-time noise rule must not be applied to RSS.

## 5. Environment: why the clean-machine gate stays open

The [packet's quiet-machine criterion](READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md#6-analysis-acceptance-and-stopping)
requires observations supporting an uncontended interpretation. That
criterion is **UNFULFILLED**, not waived by twelve successful exits.

All 12/12 launches passed the recorded operational screen: CPU4 was allowed;
CPU4 and sibling10 each showed at least 90% idle in three one-second
prelaunch observations, with zero CPU4 I/O wait and steal. All 12/12 named
compiler-queue observations reported no match. These are prelaunch screens,
not continuous proof that every possible competing job was absent.

Public retained launch data independently demonstrates activity elsewhere:

- Before `r2-default-old`, CPU11's first observation has 5% idle and 83% I/O wait.
- Before `r2-default-new`, CPU6 has 0% idle in two observations: 100% user,
  then 99% user plus 1% system.
- Generic ambient workstation-monitor diagnostics reportedly identified one
  NVIDIA compute client retaining 43 MiB of GPU memory during the batch.
  The reviewer did not recollect that monitor observation. Memory residency
  alone is not a measurement of GPU compute utilization or CPU4 interference.

Neither the GPU observation nor another busy core proves the cause of a
particular timing delta. Conversely, no continuous in-sample monitoring was
collected to exclude transient interference. Global idleness, clean-machine
performance and an isolated index cost therefore remain unproved.

The first launch is 04:40:14.843Z and the final run receipt is 05:01:15.877Z.
The eleven prior-receipt-to-next-launch gaps are 23.703, 308.577, 13.770,
189.657, 27.180, 58.697, 11.591, 9.956, 543.772, 30.764 and 28.726 seconds.
Fixed order plus those variable gaps prevents treating paired slots as
guaranteed identical machine conditions. This was not a randomized trial.

All 13/13 retained holds fail the same admission screen. Their recorded
accepted-run count agrees with the preceding completed runs. They are
non-launches, not failed timing samples and not replacement opportunities:

| LOCAL hold | UTC | Accepted compiles at hold | Next planned run |
|---|---|---:|---:|
| [ACTIVITY_HOLD_01_1788754646878.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_01_1788754646878.json) | 2026-09-07T04:17:26.878Z | 0/12 | 1 |
| [ACTIVITY_HOLD_01_1788754715452.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_01_1788754715452.json) | 2026-09-07T04:18:35.452Z | 0/12 | 1 |
| [ACTIVITY_HOLD_01_1788755439923.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_01_1788755439923.json) | 2026-09-07T04:30:39.923Z | 0/12 | 1 |
| [ACTIVITY_HOLD_01_1788755714495.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_01_1788755714495.json) | 2026-09-07T04:35:14.495Z | 0/12 | 1 |
| [ACTIVITY_HOLD_03_1788756067420.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_03_1788756067420.json) | 2026-09-07T04:41:07.420Z | 2/12 | 3 |
| [ACTIVITY_HOLD_03_1788756136862.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_03_1788756136862.json) | 2026-09-07T04:42:16.862Z | 2/12 | 3 |
| [ACTIVITY_HOLD_03_1788756196673.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_03_1788756196673.json) | 2026-09-07T04:43:16.673Z | 2/12 | 3 |
| [ACTIVITY_HOLD_05_1788756374024.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_05_1788756374024.json) | 2026-09-07T04:46:14.024Z | 4/12 | 5 |
| [ACTIVITY_HOLD_05_1788756445489.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_05_1788756445489.json) | 2026-09-07T04:47:25.489Z | 4/12 | 5 |
| [ACTIVITY_HOLD_07_1788756593712.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_07_1788756593712.json) | 2026-09-07T04:49:53.712Z | 6/12 | 7 |
| [ACTIVITY_HOLD_10_1788756679811.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_10_1788756679811.json) | 2026-09-07T04:51:19.811Z | 9/12 | 10 |
| [ACTIVITY_HOLD_10_1788756758156.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_10_1788756758156.json) | 2026-09-07T04:52:38.156Z | 9/12 | 10 |
| [ACTIVITY_HOLD_11_1788757231125.json](../../build-ready-runtime/release-cost-2026-09-07/ACTIVITY_HOLD_11_1788757231125.json) | 2026-09-07T05:00:31.125Z | 10/12 | 11 |

No extra samples are requested, launched or silently added by this review.

## 6. Input reconciliation, interruption and seals

The full audit read and parsed 54/54 nonempty JSON records: PRE and POST, twelve
ROOT_RUN records, thirteen holds, two interruption records, corrected analysis,
twelve ROOT_LAUNCH records and twelve raw run records. It also reads all 12/12
complete GNU-time logs and all 12/12 harness streams. Raw compiler output is
inside those twelve run records; no successful subset replaces a failing run.

All 84/84 unique referenced retained file identities match their SHA-256
seals and recorded sizes where supplied. All 9/9 captured inputs match, and
all 19,543/19,543 pinned-library files match their full-path manifest with
zero duplicates, missing paths or extra paths. Complete post-check outputs
reconcile to 9/9 and 19,543/19,543 expected `: OK` lines respectively.
This is a bounded input seal, not a hash of every host dynamic dependency.

The nine captured inputs are the two compiler binaries, copied fixture,
libc descriptor, existing `vlib.py`, existing `oracle_lib.py`,
`/usr/bin/time`, `/usr/bin/taskset` and `/usr/bin/python3`.
The manifest preserves complete paths including spaces; a hash check alone
would not have detected additional library files, so the path set was checked
separately. Retained dynamic descriptors name the same LLVM21 runpath and
shared-library dependencies for both compilers, but this is neither a static
linkage nor portable-package test.

Two orchestration interruptions remain distinct from compiler results:

1. Preparation's overlarge single patch argument was rejected with E2BIG
   before creating the library manifest. Root retained the existing inputs,
   then captured the ordinary manifest-tool output. Zero timed compiles had
   executed at that interruption.
2. Finalization's inline Python had a missing closing brace. The retained
   interruption record reports a SyntaxError before any Python body execution.
   Original `analysis.json` is still zero bytes, SHA-256
   `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
   Correction went to the distinct `analysis.corrected.json`; no timing run
   changed or was repeated in the packet. The reviewer independently verifies
   the empty file, corrected arithmetic and raw-run seals, not by rerunning
   the failed command.

Primary LOCAL seals:

| LOCAL file | SHA-256 |
|---|---|
| [ROOT_PRE.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_PRE.json) | `f7233fc4e318d124af313105bc204c92b558fd359ba2dfd3cf40e0d4a1f1564e` |
| [ROOT_POST.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_POST.json) | `a95900a92d7b38a5ac830ddb4f1e0344943373dbffecb9892d33fafd2fa0a93e` |
| [analysis.corrected.json](../../build-ready-runtime/release-cost-2026-09-07/analysis.corrected.json) | `8f490627cd6ba70995ff9d8c9440cc9953d7ff917fc638b54ba1efa2c8ddf8f7` |
| [ROOT_FINALIZATION_INTERRUPTION.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_FINALIZATION_INTERRUPTION.json) | `25a7284f32ef9e59a3868415a200520c83af90a1fa0c19825f9f3f8c0eacf221` |
| [inputs.pre.sha256](../../build-ready-runtime/release-cost-2026-09-07/inputs.pre.sha256) | `7261badf67abc040a3abe395d8081969a9fddfbad9bf35bb27e68423ca1e2d81` |
| [library.pre.sha256](../../build-ready-runtime/release-cost-2026-09-07/library.pre.sha256) | `df972a29f43f7fb52560346deb5ece2cb5a54e20b17c9eae67462404d2f8de6f` |
| [inputs.post-check.txt](../../build-ready-runtime/release-cost-2026-09-07/inputs.post-check.txt) | `aea09fbaa8894ba9367fa4f8f49dfb26d609eebc7986990e648ae4ae27fdbc7a` |
| [library.post-check.txt](../../build-ready-runtime/release-cost-2026-09-07/library.post-check.txt) | `a25cec9ce396472cab732af9617751e14fbca090c7d2724f7de6ddf62e0552f8` |

Each ROOT_RUN seal below covers its raw `run.json`, `time.txt`,
`harness.stderr` and `ROOT_LAUNCH.json` through the record's `rawFiles`
identities; those four referenced files per run were also individually rehashed.

| LOCAL execution record | SHA-256 |
|---|---|
| [ROOT_RUN_01.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_01.json) | `6aa739657f0b3e397fc8fdfeb70c6f7eda69ae5dd64aaca460f1948e7ac72398` |
| [ROOT_RUN_02.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_02.json) | `ba3090d5b9d26e0355e6d0ae1fc24143f5e507da3c9c147b70993179ea5fb84c` |
| [ROOT_RUN_03.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_03.json) | `10908b940c7fb40c739e7aa1d6d412be05801637c0289b55e3feb1002764f19c` |
| [ROOT_RUN_04.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_04.json) | `f412d8625c81a4e7b75a9293604ecfe0385fd1cea5ff091be8fd87ec4e7a99c7` |
| [ROOT_RUN_05.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_05.json) | `82ecb0f291104bfd8672ad847c4fd6fa57aea0a9103131d2efe0d88f0ef1744c` |
| [ROOT_RUN_06.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_06.json) | `019a0782eb09aec7457e885a987398f4a016f938867c404acd14e90f55978ab1` |
| [ROOT_RUN_07.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_07.json) | `745b94df81a2d5f6775e0b9b43a699fd0feb62e4aeaaf1a639764fa377220fb5` |
| [ROOT_RUN_08.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_08.json) | `09899684bd5d709499ebdd33bbe413df7efe71e7e80cb9b975a31cfa3e0dde73` |
| [ROOT_RUN_09.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_09.json) | `441306ce9f1cfaafed7f583ac112149d892203766ce0eb96fcd8381442b24d57` |
| [ROOT_RUN_10.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_10.json) | `0a32b2a972b4b7a01dcf317f0e84f6824f80d949c5bdde45c7032eb636d39dc5` |
| [ROOT_RUN_11.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_11.json) | `4714aa1c01fd715dce920bdbbc88d75de13d2999129de4ac53708a705a6451e8` |
| [ROOT_RUN_12.json](../../build-ready-runtime/release-cost-2026-09-07/ROOT_RUN_12.json) | `3642b3c41a735ca6bb8c4813688dcb32ac8b1eda6e912e76e0686ab4036fbf8f` |

## 7. Remaining gates and handoff

This evidence supports only a finite, environment-qualified, serial frontend
comparison of the sealed artifacts. It establishes no index-only speedup,
equivalence, race freedom, wide-worker scaling, cold-I/O behavior, large-estate
capacity, cross-machine result, linking throughput or emitted-program execution.
No machine code was emitted by these `-fno-emit-bin` samples.

The independent repaired-runner, live-index/control and
[bounded preparation-OOM evidence](READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md)
remain separate. Broader OOM sites and post-abort OOM rearming remain unproved.
No crown stage or foundation is declared complete by this cost receipt.

At this handoff the package, public evidence bundle, publication/main
synchronization, release and system-default promotion gates are open and
unexecuted in this evidence packet. Separate candidate staging and smoke
verification may proceed without promoting the candidate or changing defaults;
no such outcome is claimed here. `PROMOTED/RECORD.md` remains the existing
promotion authority. The clean-machine item stays UNFULFILLED.

A future public evidence bundle must carry the fixture, pinned input/library
manifests and reconstruction or exact-artifact inputs, existing harness
owners, all twelve raw/launch/run records, thirteen holds, both interruption
records, original empty analysis and corrected analysis, this review and the
declared sanitized public derivatives/checksums where necessary. Ignored local
links do not discharge that obligation. Never overwrite original seals.

This documentation lease changes only this receipt, its LOCAL independent
review and additive README/PLAN status notes through native `apply_patch`.
No compiler, version/status probe, timing run, source/library change, helper,
Git mutation, network operation, cleanup or child agent is part of this lane.
Source is untouched; scope ends at handoff.
