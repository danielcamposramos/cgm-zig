# Ready index: bounded shipping-artifact cost packet — 2026-09-07

Status: **UNEXECUTED PREPARATION**. This packet records one public workload and
twelve future serial frontend compiles. It contains no timing result, speed
evidence, promotion decision or release-completion claim. Root accepted the
finite selection; execution belongs to root after the compiler-control queue
has finished and the launch conditions below are satisfied.

Prepared by GPT 6 Astra, independent compiler review partner, in cooperation
with the root orchestrator under Daniel's direction. The authoring lease is
this document only: no compiler source, harness, script, fixture, README, PLAN,
release pointer or settings change.

## 1. Workload and the four arms

Reuse the existing [stdpull workload](../../partner_tools/vharness/vlib.py),
`workload`'s `stdpull` branch. Its
[existing generator](../../partner_tools/vharness/fixtures/generate.py) defines
one source using `std.testing.refAllDecls` over fifteen standard-library
namespaces. No generator execution or new fixture design is needed:

```text
build-vharness/fixtures/stdpull/stdpull.zig
0261fc36bd2cb5786a841b2f362dd970180ba3d25a4e42d6b65c4c4d8b645d81
```

This is the smallest suitable existing named frontend timing workload in this
harness. The larger self-host snapshot is unnecessary for this bounded packet;
the fanout fixture principally targets AstGen rather than substantive semantic
analysis. This choice does not claim that one small workload represents every
compiler workload or stresses the ready index maximally.

| Arm | Compiler | Analysis-order argument |
|---|---|---|
| old/default | sealed promoted `046d6833…` | omitted |
| new/default | sealed candidate `d6b4168f…` | omitted |
| old/layered | sealed promoted `046d6833…` | `--analysis-order=layered` |
| new/layered | sealed candidate `d6b4168f…` | `--analysis-order=layered` |

Three repetitions of each arm give **12 planned compiles, 0 executed by this
packet's author**. Within each repetition the order is old/default,
new/default, old/layered, new/layered. This is a fixed four-arm interleaving,
not a randomized trial. Both cross-artifact comparisons are interleaved in
paired slots. Do not add repetitions or substitute workloads automatically.

Every arm uses `-j1 --intern-partitions=2`, CPU affinity `4`, `-ODebug` for the
workload and `-fno-emit-bin`. Default means omitting the **ordering** option,
not leaving worker or partition counts uncontrolled. Compiler binaries retain
their own sealed build configurations; the workload's `-ODebug` does not
rebuild or change either compiler. There is no `--debug-log`, shadow binary,
fault injection, machine-code output or linked-program execution in this row.

## 2. Existing owners and inspected identities

The preparation review read the complete `run_vlist.py` invocation body,
`rows_005c.v8`, the relevant fixture-generator and manifest bodies, and the
`vlib` environment, subprocess, timing, comparison, workload and report-parser
bodies. It also inspected `repro.py`'s existing GNU-time invocation.

Stock `run_vlist.py --only V8` is **not** this packet's release-cost verdict:

- V8 times modes within `ctx.zig`, not old versus new through `ctx.ref`.
- It does not request RSS measurement or expose worker/partition arguments.
- Its driver uses shared fixed global-cache roots.
- Its final GREEN depends on the capability check, not successful timing
  samples. The driver also returns zero when selected rows are UNKNOWN.

The packet instead invokes the existing `vlib.run_cmd` primitive, with explicit
arguments, environment and isolated caches. GNU time is explicitly in its
command list and writes its ordinary raw log through `-o`. Passing
`rss=False` to `run_cmd` is intentional: the helper's `rss=True` path removes
its temporary GNU-time file after extracting RSS. Here the raw file survives,
and root reads RSS from that retained file. The `Run.peak_rss_kb` field remains
null and must not be misreported as a measured zero.

The promoted source identity recorded in `PROMOTED/RECORD.md` is `b991cb16`.
Its `src/main.zig` parses `-j`, `--intern-partitions` and
`--analysis-order`, with insertion as the default. Support for layered is also
grounded by an actual prior run, not only source interpretation:
`build-vharness/runs/2026-08-23T223030/vlist.json` names the `046d6833…`
binary and records three insertion plus three layered timing executions with
return code zero. Those old measurements are not measurements of this packet.
`ThreadPlan.starvedLanes` preserves the legitimate `-j1` / two-partition member.

Preparation-time binary identities, to be checked again before launch:

```text
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/stage3-046d6833/bin/zig
d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f  build-release-2026-09-06/log-fixed-stage3/bin/zig
```

Recorded versions are respectively `0.16.0` and
`0.16.0+cgm.0399d2b19b`. The author did not invoke either compiler to obtain a
fresh version. Current candidate options contain the latter version string.

Preparation-time input hashes:

```text
19c4c18bd4447085426014a6d85541df876e3d8ad78d3b8396ceb4cda66933f9  partner_tools/vharness/vlib.py
5c65c3cf9ad7bb8a264fb7b6700978eda1cf8775544458f8dc8e98ec81473062  partner_tools/oracle_lib.py
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
```

An independent read-only comparison found **19,543 of 19,543 installed library
files byte-identical**, with identical relative path sets, between
`PROMOTED/stage3-046d6833/lib/zig` and
`build-release-2026-09-06/log-fixed-stage3/lib/zig`. All four arms pin the latter
installed library. This excludes a standard-library source mismatch from this
comparison; it does not test automatic library discovery. Keep that separate
in the package/promotion verification.

## 3. Launch gates and receipt ownership

Root must first verify that the entire compiler-control/build queue is idle.
**No benchmark runs concurrently with another compiler build or control run.**
Do not kill, reprioritize or reconfigure another lane to obtain quiet timing.

CPU 4 is a fixed setting for this finite experiment, not a newly established
hardware capability. It must actually be online, allowed to the launching
process, and currently available/idle before launch. The earlier inspection
found the audit process allowed on CPUs `0-11`; that is historical inspection,
not authorization or evidence of CPU 4 being idle at a future launch. Root must
use current allowed-affinity and CPU-activity observations, not assume idleness
from a single static listing. If CPU 4 is unavailable or contended, stop; do
not silently choose another CPU or overlap the compiler queue. Record current
observations and review contention again during the batch.

The process, capacity and allowed-affinity commands below are necessary launch
information, but **do not by themselves establish current per-CPU idleness**.
Root records that separately from its existing activity observation mechanism.
No benchmark executes in this document-authoring lane.

Root owns prestate, execution results and analysis receipts. Author them with
native `apply_patch`, or preserve structured results through normal tool-output
capture. Do not author scripts or receipt prose/JSON by shell `cat`, heredoc
writes, `echo` or `printf` redirections. The redirections in the commands below
only capture the unmodified stdout/stderr of the named tools; they are normal
tool-output capture, not shell-authored document contents. Existing-fixture
copying is materialization, and GNU time's `-o` file is ordinary raw output.
The short inline Python command only invokes and serializes existing harness
primitives; it creates no new script or compiler source file.

Before launching, use `apply_patch` or normal tool capture for a prestate
receipt containing this packet identity, the explicit four-arm order and
three-repeat limit, input hashes/versions, common library manifest, CPU and
contention observations, compiler queue state and the exact commands/environment.
Afterward, retain every run and the analysis, including stopped/failed runs.
No cleanup or overwrite of an existing measurement directory is permitted.

## 4. Exact future preparation commands

Execute only after the launch gates above are satisfied. The commands below
are a future root packet, not a record of commands executed by the author.

```bash
cd /K3D/GitHub/cgm-zig
perf_repo=/K3D/GitHub/cgm-zig
perf_root="$perf_repo/build-ready-runtime/release-cost-2026-09-07"
perf_old="$perf_repo/PROMOTED/stage3-046d6833/bin/zig"
perf_new="$perf_repo/build-release-2026-09-06/log-fixed-stage3/bin/zig"
perf_lib="$perf_repo/build-release-2026-09-06/log-fixed-stage3/lib/zig"
perf_libc="$perf_repo/build-p005/vwork/libc.txt"

ps -eo pid,ppid,comm,etime,pcpu,rss
df -h "$perf_repo"
rg '^Cpus_allowed_list:' /proc/self/status
# STOP until CPU 4's current availability/idleness and the idle queue are recorded.

test ! -e "$perf_root" && test ! -L "$perf_root" || exit 2
mkdir "$perf_root" || exit 2
cp -p "$perf_repo/build-vharness/fixtures/stdpull/stdpull.zig" \
    "$perf_root/stdpull.zig" || exit 2

sha256sum "$perf_old" "$perf_new" "$perf_root/stdpull.zig" \
    "$perf_libc" "$perf_repo/partner_tools/vharness/vlib.py" \
    "$perf_repo/partner_tools/oracle_lib.py" \
    /usr/bin/time /usr/bin/taskset /usr/bin/python3 \
    > "$perf_root/inputs.pre.sha256" || exit 2

set -o pipefail
rg --files --hidden --no-ignore -0 "$perf_lib" |
    LC_ALL=C sort -z |
    xargs -0 sha256sum > "$perf_root/library.pre.sha256" || exit 2

"$perf_old" version > "$perf_root/old.version" || exit 2
"$perf_new" version > "$perf_root/new.version" || exit 2
readelf -d "$perf_old" "$perf_new" \
    > "$perf_root/dynamic-inputs.txt" || exit 2
```

Before proceeding, root must compare the captured hashes with section 2,
including the copied fixture hash in section 1, and inspect both actual version
outputs. Missing tools, changed identities or an unexpected version stop this
packet for review. The library manifest retains complete filenames, including
spaces; do not reduce paths to a whitespace-delimited `$2`. Its expected count
is 19,543 regular files, derived by the preparation inspection and checked
again at launch. The compiler and library prefixes must remain frozen through
the batch. Root must retain/reconcile the exact library path set as well as
checking hashes; `sha256sum --check` alone does not detect an added file.

## 5. Exact twelve-run sequence

Continue in the same root shell after prestate review. Both cache directories
are new for every run. All subprocesses are synchronous and serial.

```bash
cd "$perf_root" || exit 2
for perf_rep in 1 2 3; do
    for perf_mode in default layered; do
        for perf_arm in old new; do
            perf_run="$perf_root/r${perf_rep}-${perf_mode}-${perf_arm}"
            mkdir "$perf_run" || exit 2
            mkdir "$perf_run/local-cache" "$perf_run/global-cache" || exit 2
            if [ "$perf_arm" = old ]; then
                perf_bin="$perf_old"
            else
                perf_bin="$perf_new"
            fi
            perf_order=()
            if [ "$perf_mode" = layered ]; then
                perf_order=(--analysis-order=layered)
            fi

            if env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
                PYTHONPATH="$perf_repo/partner_tools/vharness" \
                ZIG_LIBC="$perf_libc" \
                ZIG_LOCAL_CACHE_DIR="$perf_run/local-cache" \
                ZIG_GLOBAL_CACHE_DIR="$perf_run/global-cache" \
                python3 -B -c '
import dataclasses,json,os,sys,vlib
r=vlib.run_cmd(sys.argv[1:],cwd=os.getcwd(),env=os.environ.copy(),
               mask="4",timeout=180,rss=False)
keys=("LC_ALL","TZ","ZIG_LIBC","ZIG_LOCAL_CACHE_DIR","ZIG_GLOBAL_CACHE_DIR")
print(json.dumps({"run":dataclasses.asdict(r),"cwd":os.getcwd(),
                  "timeout_seconds":180,"env":{k:os.environ[k] for k in keys}}))
sys.exit(0 if r.ok else 1)
' /usr/bin/time -v -o "$perf_run/time.txt" \
                "$perf_bin" build-exe -j1 --intern-partitions=2 \
                "${perf_order[@]}" -fno-emit-bin -ODebug \
                --color off --zig-lib-dir "$perf_lib" \
                "-Mroot=$perf_root/stdpull.zig" \
                > "$perf_run/run.json" 2> "$perf_run/harness.stderr"; then
                :
            else
                # Preserve everything; review this exact stopped run before any continuation.
                exit 1
            fi
        done
    done
done

sha256sum --check "$perf_root/inputs.pre.sha256" \
    > "$perf_root/inputs.post-check.txt" || exit 2
sha256sum --check "$perf_root/library.pre.sha256" \
    > "$perf_root/library.post-check.txt" || exit 2
```

The existing `vlib.run_cmd` starts a process group, applies `taskset -c 4`,
and enforces the 180-second timeout with its existing owned-process-group
termination handling. It returns elapsed monotonic wall time and complete
decoded stdout/stderr, stderr byte count, return code and timeout status.
The outer invocation returns one on failure, but the original return code and
timeout status survive in `run.json`; do not replace them with that wrapper
status. GNU time separately retains signal/exit, wall, RSS and other resource
information in `time.txt`. Capture missing/partial output as missing/partial,
not as a zero measurement.

No compiler cache is shared between runs. Filesystem/page caches are **not**
flushed, and hashing the library before timing itself reads those files. The
packet does not claim cold storage I/O or a cold machine. No automatic warmup
or extra compile is hidden in these twelve invocations. The two earlier
`version` commands are identity checks, not timed workload runs.

The loop stops automatically for a failed launch/compile. Root must additionally
stop on observed contention or invalid evidence; the loop is not an automatic
CPU-idleness guard. If a run is interrupted for those reasons, preserve all its
outputs and report the actual denominator. Do not quietly restart under the
same directory or replace a losing/failed sample.

## 6. Analysis, acceptance and stopping

Root uses the existing `vlib.Timing`, `compare`, `parse_report_line` and
`parse_rank_line` bodies. No new statistics implementation or benchmark script
is requested. For each arm, construct `Timing(label, samples, rcs, peak_rss_kb)`
from the three chronological `run.wall` values, three actual return codes and
three RSS values parsed from the retained GNU-time records. Require exact
counts and successful runs before interpreting a cost delta; `compare` does
not itself reject failed timing samples. Use `Timing.to_json()` and retain the
full `compare` result, particularly its `note` and `inside_noise` fields.

The exact comparison pairs, in argument order, are:

1. `compare(old_default, new_default)`: shipping-artifact default-path delta.
2. `compare(old_layered, new_layered)`: shipping-artifact opt-in delta.
3. `compare(new_default, new_layered)`: the candidate's opt-in cost.

This measures differences between the sealed shipping artifacts, including
their build/configuration differences. It is **not an index-only causal
experiment**. The old-versus-new comparisons do not isolate a source line from
all other compiler-build changes.

Require the following before calling the finite measurement complete:

- **12 of 12** compiles return zero without timeout, with all expected raw
  records present, readable and matched to their named arm/repetition.
- Both actual compiler identities/versions and all pinned input hashes remain
  correct. Reconcile the library's exact path set as well as existing hashes.
- Parsed thread reports state workers 1 and partitions 2 in every arm.
  Layered ranking reports occur in layered arms and not in default arms.
- Full stderr contains no compiler error, shadow/fault/debug marker or
  unexpected diagnostic. The normal info-level thread/ranking reports are
  expected and are not a requirement for silence.
- GNU-time records supply real wall/RSS/exit data, and their outcome agrees
  with `run.json`. Keep both wall measurements: the harness wall includes its
  subprocess wrapper overhead; GNU time times the compiler command beneath it.
- Current quiet-machine observations support interpreting the timing as
  uncontended. An absent activity instrument is UNKNOWN, not a quiet machine.

Stop and review a failed run, timeout, missing record, drifted input, wrong
mode/worker setting, unexpected diagnostic or competing build activity. A
candidate-only default-path slowdown outside the existing harness's noise
heuristic requires review before promotion; do not silently waive it. A delta
inside the heuristic means **no regression distinguished here**, not proof of
equivalent performance. Report paired outcomes, all samples, median, spread
and standard deviation. With three repeats, IQR is unavailable. The heuristic
is not a statistical confidence interval or proof of causation.

RSS remains three raw observations per arm plus descriptive summaries; do not
reinterpret `Timing.compare`'s wall-time noise rule as an RSS hypothesis test.
An unexplained material RSS regression also requires review. No percentage
threshold or universal speed requirement is invented here. Layered remains
opt-in; an unfavorable opt-in cost is reported, not hidden or used to change
the default automatically.

## 7. Scope ceiling and handoff

This is **one serial frontend workload**. `-fno-emit-bin` makes it inappropriate
to claim link throughput, emitted-program correctness or execution results.
It is not a wide-worker scaling, race-freedom, maximum-ready-set, universal-OOM,
large-estate, cold-storage or cross-machine benchmark. Existing repaired-runner
and ready-index integration-control evidence remains separate and is not
replaced by these cost samples. Package extraction, automatic library
discovery, smoke compilation/execution, online synchronization and system
default promotion remain their own verification/actions.

The preparation author performed read-only source/receipt inspection and
identity/library comparison; this documentation follow-up used `apply_patch`
for this file only. No compiler, version command, compiler probe, test, timing,
Git mutation, network action, child agent or cleanup ran in the authoring
lane. Future commands above are not execution receipts. Root receives this
unexecuted packet, reviews the indicated existing harness owners, and owns
any subsequent materialization/execution. The documentation lease ends at
handoff.
