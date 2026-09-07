# Ready index: prospective observed-cost successor — 2026-09-07

Status: **PREPARATION ONLY; 0 of 16 compiles executed by this packet.**
Execution requires root's acceptance of the actual, separately authorized
wrapped noncompiler controls and a separate final input/policy seal. Neither
mocked tests nor this document authorize a workload launch. Prepared by GPT 6
Astra, independent compiler partner, cooperating with the root orchestrator
under Daniel's direction.

The [original packet](READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md) and
[executed twelve-sample receipt](READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
remain immutable. This is a **new series**, not a retry, replacement, correction
of individual samples or pooled extension of those twelve observations. Their
environmental qualification remains in force. No compiler, library, default,
package or archive changes are part of this successor.

## 1. Finite design and unchanged inputs

Use the original `stdpull` frontend workload, the same two sealed compiler
artifacts and the same installed library. The original packet explains the
workload and artifact provenance; these are the exact successor bindings:

| Arm | Artifact, relative to the public repository | Ordering argument |
|---|---|---|
| A: old/default | `PROMOTED/stage3-046d6833/bin/zig` | omitted |
| B: new/default | `build-release-2026-09-06/log-fixed-stage3/bin/zig` | omitted |
| C: old/layered | the same old artifact | `--analysis-order=layered` |
| D: new/layered | the same new artifact | `--analysis-order=layered` |

| Block | Slots, in mandatory chronological order |
|---|---|
| 1 | 01 A, 02 B, 03 D, 04 C |
| 2 | 05 B, 06 C, 07 A, 08 D |
| 3 | 09 C, 10 D, 11 B, 12 A |
| 4 | 13 D, 14 A, 15 C, 16 B |

There are four observations per arm. Each arm occupies each within-block
position once. The twelve **within-block** transitions cover the twelve ordered
pairs of different arms once each. The three cross-block transitions are
additional and unbalanced. This is a fixed, not randomized, sequence. Retain
all launch gaps and block boundaries; position balancing does not erase
interference, storage/page-cache history or time drift.

Every invocation uses CPU4, `-j1 --intern-partitions=2 -fno-emit-bin -ODebug
--color off`, with the ordering flag only in C/D. Pin
`--zig-lib-dir /K3D/GitHub/cgm-zig/build-release-2026-09-06/log-fixed-stage3/lib/zig`.
Set `ZIG_LIBC` to the existing `build-p005/vwork/libc.txt`. Both local and global
compiler caches are fresh per slot. There is no debug-log flag, warmup,
capability probe, compiler-version invocation, emitted executable or program run.
`-ODebug` applies to the workload, not either compiler's sealed build mode.

Required unchanged identities:

```text
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/stage3-046d6833/bin/zig
d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f  build-release-2026-09-06/log-fixed-stage3/bin/zig
0261fc36bd2cb5786a841b2f362dd970180ba3d25a4e42d6b65c4c4d8b645d81  build-vharness/fixtures/stdpull/stdpull.zig
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
```

Recorded compiler versions remain `0.16.0` and `0.16.0+cgm.0399d2b19b`, grounded
by the unchanged binaries and retained original `old.version` / `new.version`.
The common library's sealed inventory is **19,543 regular files / 184,297,278
bytes**. Reconcile its full relative path set and every hash, not just the hashes
of whatever files happen to remain. Its original absolute-path bank is
`build-ready-runtime/release-cost-2026-09-07/library.pre.sha256`, SHA-256
`df972a29f43f7fb52560346deb5ece2cb5a54e20b17c9eae67462404d2f8de6f`.

## 2. Reviewed source closure and final seal

Use the existing [LaunchObservation](../../partner_tools/cost_observation/launch.py)
adapter around [vlib.run_cmd](../../partner_tools/vharness/vlib.py), not a second
process launcher. The [observer README](../../partner_tools/cost_observation/README.md)
defines the numeric schema, limits, mock evidence and ownership contract.
Root supplied integration commit `ea6cfeb53897270f8a1780d3e272b09c153d66c7`;
this packet does not assert that commit has been published. Runtime import
closure, exactly seven repository Python files:

```text
7f760e627eadce63b48fa4d13fb8fd87b9dd617d52670fa1ecae256314f40a80  partner_tools/cost_observation/__init__.py
5fde51779ad52b01b025adf3fa6a4ab7e868a0a2b997ed873f0ec4602f8d4d20  partner_tools/cost_observation/launch.py
9a45a8fd2201deae787dafa80badd18b652fa9e3a13dc3ab42e79dd12b1e6cbf  partner_tools/cost_observation/observe.py
3eaf4a4e3da01600d23eeb9e56b00ddda56b2d1513cc252c2b66491de5a14caa  partner_tools/cost_observation/owned_process.py
68fda1dce5fc3d8e6321c47fcbaa0e57d54c884870406fb6cd7968c7bcb9afcc  partner_tools/cost_observation/procfs.py
5c65c3cf9ad7bb8a264fb7b6700978eda1cf8775544458f8dc8e98ec81473062  partner_tools/oracle_lib.py
c4cd16f49d19d7cc7886ae8ef9135634dc96ff5bb311c939970091b69888dcd3  partner_tools/vharness/vlib.py
```

Do not substitute the original twelve-run helper hash. Root's final seal must
record this exact closure/path set, the fixture and library inventory, both
compiler hashes and numeric file identities (`dev`, `ino`, `size`, `mtime_ns`,
`ctime_ns`), libc file, Python executable, GNU time and taskset identities,
this packet hash and exact accepted live-control source/receipt hashes.
`partner_tools` and `partner_tools/vharness` currently use namespace packages:
their absent `__init__.py` files are part of the import-resolution prestate.
Unexpected package initializers, import shadowing or source drift stop review.
The Python standard library and system dynamic dependencies remain external
runtime inputs, not a hermetically sealed operating system. Retain the original
dynamic-input record and disclose any runtime environment change.

The reported 80/80 mocked tests, two skipped host methods and 21/21 vlib checks
are not live-wrapper acceptance. Live control authoring/execution was still
pending when this packet was written. The final seal must name the actual
control artifacts and acceptance, rather than invent their paths or results.
No new calibration field is required for this plan: the reviewed adapter has a
conservative enclosing call window. Record the final admission observation's
monotonic endpoint separately to expose admission-to-call delay.

## 3. Admission, holds and prospective decision still required

Before **each** slot, root checks that the compiler/build/control queue is idle
and records three consecutive one-second activity observations. Reuse the
original numeric admission method (`psutil.cpu_times_percent(interval=1,
percpu=True)`) and existing `vlib.host_topology` / `vlib.parse_mask` APIs. Derive
the current CPU4 sibling list from
`/sys/devices/system/cpu/cpu4/topology/thread_siblings_list`, reconcile it with
the topology result and `/sys/devices/system/cpu/online`, and record the raw
numeric lists. CPU4 must be online and in `os.sched_getaffinity(0)`.

Apply the [original ROOT_PRE policy](../../build-ready-runtime/release-cost-2026-09-07/ROOT_PRE.json):
CPU4 and **every currently online SMT sibling** must each be at least 90% idle
in **all three** one-second observations; CPU4 iowait and steal must each be
zero in all three. Do not hardcode CPU10. Do not exclude an online sibling
merely because the launching process cannot use it; other processes can.
Record any offline sibling separately. Missing/contradictory topology, unavailable
required counters, an unavailable fixed CPU or competing compiler means HOLD.
The queue check needs root's actual lane review; `vlib.machine_courtesy()` alone
is a pattern-based hint, not proof that every competing activity was discovered.
Do not preserve unrelated command lines or identifying process names in a
public receipt; retain numeric findings and the declared coverage limitation.

Save every attempt as a distinct `ADMISSION_<slot>_<attempt>.json`, including
topology, allowed CPUs, all three complete numeric samples, timestamps,
queue-check result/limits and next slot. A failed admission leaves that slot
**unlaunched**. It is not a timing sample or a reason to skip/reorder that arm.
There is no automatic hold-polling loop or automatic resume. Root must make a
fresh recorded continuation decision without changing the predeclared sequence.
Do not perform substantial hashing or other work between the accepted screen
and launch without recording the gap and reconsidering the screen's freshness.

**Separate prospective decision, not yet an accepted rejection rule:** root must
explicitly accept or decline the following stricter in-sample screen in the
final `ROOT_PRE.json`. For each overlapping interval defined in section 5,
stop after retaining a sample if any derived online sibling has positive
execution ticks (`user + nice + system + irq + softirq`), or CPU4/any such
sibling has positive iowait or steal. Do not double-count guest fields.
This is a conservative operational proposal, not the historical admission
specification, a measured slowdown boundary or a release tolerance. Coarse,
non-atomic counters and bracket spillover can reject a sample without proving
that interference occurred inside its exact compiler execution interval.
Iowait is not itself proof of CPU scheduling contention. If root declines this
proposal, raw values still survive and no automatic quietness verdict replaces it.

Aggregate other-core execution, VM and PSI observations are retained whichever
choice root makes. They cannot be attributed to unseen identities or converted
into compiler contention by subtracting asynchronously sampled process totals.
No threshold for release slowdown, acceptable observer cost or whole-host
activity is invented. These decisions must be fixed before results are seen.

## 4. Exact future setup and one-slot invocation

All commands below are **conditional future root actions**, not actions taken
by the author. There is no automatic sixteen-run loop: root advances exactly
one slot only after its saved evidence and gate decision. Use one persistent
shell with no-clobber output capture. Any existing destination is a stop, not
permission to overwrite or clean it.

```bash
cd /K3D/GitHub/cgm-zig
set -o noclobber
set -o pipefail
cost_repo=/K3D/GitHub/cgm-zig
cost_root="$cost_repo/build-ready-runtime/observed-cost-2026-09-07"
cost_old="$cost_repo/PROMOTED/stage3-046d6833/bin/zig"
cost_new="$cost_repo/build-release-2026-09-06/log-fixed-stage3/bin/zig"
cost_lib="$cost_repo/build-release-2026-09-06/log-fixed-stage3/lib/zig"
cost_libc="$cost_repo/build-p005/vwork/libc.txt"
test ! -e "$cost_root" && test ! -L "$cost_root" || exit 2
mkdir "$cost_root" || exit 2
cp -p "$cost_repo/build-vharness/fixtures/stdpull/stdpull.zig" "$cost_root/stdpull.zig" || exit 2
sha256sum "$cost_old" "$cost_new" "$cost_root/stdpull.zig" "$cost_libc" \
  "$cost_repo/partner_tools/cost_observation/"{__init__,launch,observe,owned_process,procfs}.py \
  "$cost_repo/partner_tools/vharness/vlib.py" "$cost_repo/partner_tools/oracle_lib.py" \
  /usr/bin/python3 /usr/bin/time /usr/bin/taskset > "$cost_root/inputs.pre.sha256" || exit 2
rg --files --hidden --no-ignore -0 "$cost_lib" | LC_ALL=C sort -z | \
  xargs -0 sha256sum > "$cost_root/library.pre.sha256" || exit 2
cmp "$cost_root/library.pre.sha256" \
  "$cost_repo/build-ready-runtime/release-cost-2026-09-07/library.pre.sha256" || exit 2
```

Root reviews the captured identities/counts/path set against sections 1–2,
not merely whether commands returned zero. Keep paths after the checksum's
two-space separator intact; never parse a checksum row as whitespace field 2.
Before any slot, root creates and seals `ROOT_PRE.json` with the final decision,
all prerequisite evidence and `execution_authorized: true`. It includes
`binary_metadata.old` and `.new`, each with the five exact numeric identity
fields above. Manual receipts use `apply_patch`; generated records/manifests
use ordinary tool-output capture. No Python source file is authored here.

For the next authorized slot, set only `cost_slot` to its prescribed two-digit
ordinal. The exact label and arm are derived below; do not supply an independent
arm that could disagree with the ordinal. Record its accepted admission before
this command. The example starts slot 01; later invocations change only that
ordinal after root's prior-slot review.

```bash
cost_slot=01
case "$cost_slot" in 0[1-9]|1[0-6]) ;; *) exit 2 ;; esac
cost_run="$cost_root/slot-$cost_slot"
test ! -e "$cost_run" && test ! -L "$cost_run" || exit 2
mkdir "$cost_run" || exit 2
mkdir "$cost_run/local-cache" "$cost_run/global-cache" || exit 2
env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
  PYTHONPATH="$cost_repo" ZIG_LIBC="$cost_libc" \
  ZIG_LOCAL_CACHE_DIR="$cost_run/local-cache" \
  ZIG_GLOBAL_CACHE_DIR="$cost_run/global-cache" \
  /usr/bin/python3 -B -c '
import dataclasses, json, os, sys
from pathlib import Path
from partner_tools.cost_observation.launch import LaunchObservation
from partner_tools.cost_observation.owned_process import file_identity

repo, root, output = map(Path, sys.argv[1:4])
slot = int(sys.argv[4])
assert 1 <= slot <= 16, "slot_outside_finite_sequence"
arm = "ABDCBCADCDBADACB"[slot - 1]
block = (slot - 1) // 4 + 1
pre = json.loads((root / "ROOT_PRE.json").read_text())
assert pre["execution_authorized"] is True, "root_final_seal_required"
old = arm in "AC"
binary = repo / ("PROMOTED/stage3-046d6833/bin/zig" if old else
                 "build-release-2026-09-06/log-fixed-stage3/bin/zig")
sealed = pre["binary_metadata"]["old" if old else "new"]
assert file_identity(binary.stat()) == sealed, "compiler_metadata_drift"
command = ["/usr/bin/time", "-v", "-o", str(output / "time.txt"),
           str(binary), "build-exe", "-j1", "--intern-partitions=2"]
if arm in "CD":
    command += ["--analysis-order=layered"]
command += ["-fno-emit-bin", "-ODebug", "--color", "off", "--zig-lib-dir",
            str(repo / "build-release-2026-09-06/log-fixed-stage3/lib/zig"),
            "-Mroot=" + str(root / "stdpull.zig")]
observer = LaunchObservation(sealed, interval_seconds=0.05,
                             max_samples=10000, max_children=4)
run, failure = None, None
try:
    run = observer.run(command, cwd=str(root), env=os.environ.copy(),
                       mask="4", timeout=180, rss=False)
except BaseException as error:
    failure = {"kind": type(error).__name__, "errno": getattr(error, "errno", None),
               "owned_cleanup": getattr(error, "cgm_run_cmd_cleanup", None)}
    raise
finally:
    print(json.dumps({"slot": slot, "block": block, "arm": arm,
          "cwd": str(root), "env": dict(os.environ), "timeout_seconds": 180,
          "command_before_taskset": command,
          "run": dataclasses.asdict(run) if run is not None else None,
          "exception": failure}), flush=True)
    with os.fdopen(3, "w") as stream:
        print(json.dumps(observer.evidence), file=stream, flush=True)
sys.exit(0 if run.ok else 1)
' "$cost_repo" "$cost_root" "$cost_run" "$cost_slot" \
  > "$cost_run/run.json" 3> "$cost_run/observation.json" \
  2> "$cost_run/harness.stderr"
cost_launcher_rc=$?
# STOP HERE. Record this rc and review both saved JSON records and time.txt.
# A zero launcher rc is not the observation/admission acceptance decision.
```

`run.json` retains the actual Run, including full decoded compiler stdout/stderr,
or an explicit missing Run and exception record. `observation.json` retains the
**entire** adapter result, including all raw snapshots, intervals, errors,
discoveries and identity joins. Both are emitted before a post-run gate decision;
a failure to serialize/save either is itself a stop with partial files preserved.
`time.txt` is GNU time's unmodified output. `harness.stderr` preserves the outer
Python stream, including exceptions. Root separately records the launcher exit
status and exact command, and never overwrites these four raw members.
No gate decision, summary or filtered interval set substitutes for either JSON.

The original vlib adds `taskset -c 4` outside GNU time and owns its process group
and timeout. `rss=False` avoids its temporary-file removal path; the returned
`Run.peak_rss_kb` is null, while GNU time supplies the retained RSS measurement.
The callback performs only the reviewed identity capture; no waiting for target
discovery is inserted before `communicate`. Neither sampling nor notification
cost is subtracted. A reaped wrapper does not prove every descendant has exited;
the reviewed cleanup is best-effort and refuses signaling without ownership.

## 5. Per-slot evidence review and stop rule

After every launch, save a separate `DECISION_<slot>.json` referencing the hashes
of the raw files, its admission record and final seal. Retain outcomes even if
the current slot or whole series is disqualified. Before launching the next slot:

- Require the actual Run, successful rc/no timeout, corresponding GNU-time
  wall/RSS/exit record and consistent outer rc. Inspect full stderr; use
  `vlib.parse_report_line(run["stderr"])` for workers=1/partitions=2 and
  `vlib.parse_rank_line(...)` for ranking only in C/D. Reject unexpected errors,
  debug/shadow/fault markers or wrong settings; expected info reports are valid.
- Let `lo=run_call_begin_ns`, `hi=run_return_or_raise_ns`. Require ordered,
  present monotonic boundaries, normal caller stop and a joined observer.
  Preserve every raw adjacent interval whose enclosing span from its left
  sample's `entered_ns` through its right sample's `finished_ns` intersects
  `[lo, hi]`, including both bracketing samples. Preserve the full record as well.
  This broad window is deliberate: no fractional counter proration or invented
  exact exec timestamps. Include missing-snapshot intervals in the denominator.
- Require usable, nondecreasing aggregate CPU and CPU4/current-online-sibling
  state deltas in every overlapping interval; absent mandatory counters are
  UNKNOWN, not zero. Require zero missed deadlines in overlapping collections,
  no failed collection/lifecycle error and no sample-cap truncation. Record
  other-core, VM and PSI availability/errors explicitly; optional unsupported
  fields such as an absent PSI `full` scope do not become fabricated zeros.
- From `identity_join`, require at least one adjacent
  `same_target_at_observed_endpoints` interval with the same sealed target
  PID/start identity and both endpoint read windows inside `[lo, hi]`.
  Reconcile the join's discovery indexes against the preserved before/after
  probes and raw rows. Do not use the raw `other` role or wrapper CPU as target
  evidence. Report matched/total overlapping intervals and complete discovery
  status/error denominators. Startup, final-exit gaps, unobserved descendants
  and execution between probes remain UNKNOWN; expected terminal disappearance
  is not retroactively continuous target coverage.
- Record admission-to-call delay, discovery delay, matched-read coverage,
  collection wall/CPU cost, sampling-thread CPU, notification wall/CPU cost,
  lag, misses and stop latency. Discovery cost occurs inside collection cost;
  do not double-count it. Compare no timing after subtracting these quantities.
  Apply the stricter activity proposal only if the final preseal accepted it.

Any failed launch/compile, mandatory UNKNOWN/missing evidence, counter/source
drift, incorrect settings or observed competing compiler **preserves the slot
and stops all remaining launches**. There is no automatic retry, resume,
replacement or reranking by speed. Any later continuation needs a separately
recorded root decision; it cannot silently turn an interrupted series into the
original complete sixteen-slot experiment. Report actual launched/successful/
quality-supported counts separately against the planned denominator 16.

## 6. Read-only analysis, postseals and claim ceiling

After the last permitted slot, check `inputs.pre.sha256` with `sha256sum --check`;
recreate the complete sorted library manifest as `library.post.sha256` and
compare it byte-for-byte with `library.pre.sha256`. Recheck the seven-file
source closure/path set and namespace-initializer absences. Retain check output,
not just exit status. Root seals every raw slot/admission/decision record, the
source/control prerequisites and a final `ROOT_POST.json`; no cleanup follows.
Hashing reads files and can warm storage caches, so bulk seals belong outside
timed slots and their launch screens. Fresh compiler caches are not cold page
caches; no page-cache flush is authorized.

Analysis reuses existing APIs without invoking a workload:

```python
from partner_tools.vharness import vlib

# Populate from retained slot records in BLOCK order, four values per arm.
# Validate all actual counts/rcs/gates first: compare() is not that validator.
a = vlib.Timing("old_default", walls_A, rcs_A, rss_A)
b = vlib.Timing("new_default", walls_B, rcs_B, rss_B)
c = vlib.Timing("old_layered", walls_C, rcs_C, rss_C)
d = vlib.Timing("new_layered", walls_D, rcs_D, rss_D)
summaries = [value.to_json() for value in (a, b, c, d)]
comparisons = [vlib.compare(a, b), vlib.compare(c, d), vlib.compare(b, d)]
```

`walls_*` and `rcs_*` come from actual Run objects; `rss_*` are the exact
`Maximum resident set size (kbytes)` values in their corresponding GNU-time
logs. Save GNU wall/user/system/exit observations too. Retain all values, paired
outcomes, median/min/max/spread/SD, IQR and every compare field including `note`.
Pairing is by the same block, not a claim of identical machine weather or
adjacent launches. Four observations make this helper's IQR available; neither
IQR overlap nor `inside_noise` proves equivalence. Its noise heuristic is
descriptive, not a confidence interval, and is not an RSS acceptance test.
A candidate-default slowdown outside that heuristic or unexplained material
RSS increase requires review; no numeric release tolerance is invented here.

An environment-supported narrow interpretation must state its actual observed
coverage and cost. Selected/custom PID coverage does not establish whole-host
cleanliness, continuous process identity, all-thread affinity, cache/bandwidth/
thermal isolation or equal observer perturbation. This is an artifact-level
frontend comparison on one small workload, **not causal index speed**, linking,
wide-worker scaling, race-freedom or universal performance evidence. A completed
observed series can remain environmentally qualified. It neither closes the
original clean-machine release gate automatically nor authorizes publication,
online synchronization or default promotion.

Authoring receipt: the destination was absent. Only this document was added
with `apply_patch`, after reading the governing skill/doctrine, original packet
and admission policy, current observer contract and invocation/statistics owners.
The seven runtime source hashes and fixture/libc identities were read-checked;
compiler/library identities here retain their cited prior seals pending root's
fresh final check. No helper, source, fixture, cache, host observation, test,
compiler/version command, network, Git action, archive or default change was
performed. Future commands and API examples above are not execution receipts.
