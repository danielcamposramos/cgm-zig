# Sample-local Linux cost observation

Additive, Python-stdlib diagnostic tooling by GPT 6 Astra, 2026-09-07. This is
an observation prerequisite, not a compiler change or permission to benchmark.
It never declares a machine clean, a compiler fast, or a release acceptable.
The caller owns workload launch/timing, exact argv/env/input seals, saving the
returned data and any prospective acceptance policy.

## API and ownership

From the repository root, import `Observer` from `partner_tools.cost_observation`.
Use `with Observer(workload_pids=[pid], interval_seconds=0.1) as observer:` around
the caller's already-owned workload activity, then `observer.result()` after
exit. Alternatively use `start()`, `bind_workload(pid)` and `stop()`. Binding
captures PID plus Linux start ticks, not just a reusable PID. Binding an already
running workload cannot recover its earlier activity; preserve the launch/bind
gap. The API deliberately does not alter or wrap compiler argv, environment,
flags, affinity, workers or output. Existing `vlib.run_cmd` still owns timing
and its process-group timeout; it currently exposes no PID callback. Integrating
that launcher requires a separately reviewed seam, not a silent substitution
with this package's instrument-control child launcher.

Each Observer is one-use. Context exit joins its non-daemon sampling thread,
including when caller code raises. `stop()` is idempotent and requests a final
snapshot beginning after the request, unless the sample cap or an observer
failure already stopped collection. It touches no unrelated processes. It
creates no files, helper processes or temporary directories. The caller owns
serialization; `result()` and `stop()` return JSON-serializable dictionaries.

The default 10,000-snapshot cap bounds sample count, not duration or total bytes:
each snapshot scales with visible process/core count. Reaching the cap is an
explicit `sample_limit`, not successful full-workload coverage. `stop()` waits
for the current procfs collection; individual text reads are limited to 1 MiB,
but this thread-based implementation cannot impose a hard timeout on a kernel
read or a caller-supplied test reader that blocks indefinitely.

## Schema 1 and UNKNOWN discipline

- Top level: numeric observer PID/start-tick identity and native thread identity,
  workload-root identities/binding timestamps, requested interval/sample cap,
  monotonic start/stop/end/duration nanoseconds, observer thread CPU nanoseconds,
  stop reason, samples, consecutive intervals and lifecycle errors.
- Each sample: scheduled/entered/finished monotonic nanoseconds, collection wall
  and sampling-thread CPU cost, start lag, skipped deadline count, raw numeric
  snapshot or collection exception class. No exception message is retained.
- Snapshot: per-core and aggregate `/proc/stat` CPU tick states, runnable/blocked
  counts, load averages, VM paging/swap counters, CPU/I/O/memory pressure numeric
  averages and totals; before/after PID enumerations and observed scan changes.
- Each process: PID/start ticks, numeric PPID, user/system CPU ticks, thread
  count, last CPU, leader's current allowed affinity, I/O counters and its own
  read-window timestamps. Stat is read on both sides of affinity/I/O reads;
  identity disagreement refuses the combined observation. Roles are neutral:
  `observer_process`, `workload_root`, `workload_descendant_observed`, `other`.
- Consecutive intervals retain CPU/process/VM/pressure-total deltas, elapsed
  times, PID-reuse/new/not-observed transitions and endpoint/enumeration errors.
  Missing or decreasing counters produce `null`, never zero or wrapped values.
  `not_observed` does not claim exit: permission errors or incomplete scans may
  hide a surviving process. Never bridge a failed sample to claim a contiguous
  valid interval. Check raw error lists and raw nullable fields, not only counts.

CPU fields use `SC_CLK_TCK`, pressure totals use microseconds, pressure averages
are percentages; VM/process I/O units follow their named Linux counters. Guest
CPU ticks overlap user/nice ticks: do not blindly sum all ten CPU fields. No CPU
percentages or contention/performance thresholds are manufactured here.
`performance_verdict` and `between_observations` are always `UNKNOWN`.

## Privacy, interpretation and sampling limits

No process command line, cwd, environment, source path, executable link, UID or
identifying comm string is returned. Parsing stat necessarily reads its comm
field, then discards it; even exception strings are excluded. PID/start identities
are local observations, not cross-boot identities. The reader does not inventory
GPU clients or their command lines. It never kills, renices or reaffinitizes an
unrelated process. Instrument controls may terminate only their own child on
failure; the observer itself never sends signals.

Enumeration errors, permission failures, vanished PIDs and detected PID reuse
are explicit. A process born and gone entirely between snapshots is unobservable;
matching before/after PID lists do not close that gap. Procfs namespaces and
access controls may hide processes without reporting per-process errors. A
last-CPU value is not scheduling history; affinity is the leader's mask, not a
proof of every thread's mask or where it executed. Descendant roles infer current
parentage and retain previously observed identities; unobserved/reparented early
children cannot be reconstructed. CPU/I/O/process reads are successive, not
atomic. Other-core activity, pressure, and the observer's own measured CPU cost
matter; this package cannot establish globally idle hardware or isolate cache,
memory-bandwidth, thermal/frequency, device or interrupt causality. Sampling
itself has cost. Apply identical observation machinery to every compared arm.

## Verification commands and receipt

Run deterministic in-memory tests without generating bytecode:

```sh
python3 -B -m unittest partner_tools.cost_observation.test_observe -v
```

The default invocation skips the host-control test. Only with current machine
courtesy and explicit authority, run one busy and one idle non-compiler child:

```sh
COST_OBSERVATION_HOST_CONTROLS=1 python3 -B -m unittest partner_tools.cost_observation.test_observe.HostControls -v
```

That test reuses public `vlib.machine_courtesy` before each child and after each
observation. Matching activity holds the controls; command lines from courtesy
are not printed or saved. The busy child requests 0.35 CPU seconds with a
two-second wall ceiling; idle sleeps 0.5 seconds. Both are held alive across the
final observation. The independent child `process_time()` result is compared
with observed CPU ticks, allowing three ticks of endpoint/quantization slack.
That allowance validates this instrument only; it is not a release tolerance.
Numeric result rows include actual sample/interval counts, errors, deadlines,
CPU ticks, observer cost and stopped-thread status. The caller retains tool
output; no extra receipt files are authored by the tests.

PRE: this package directory was absent. The first default test command returned
0: 18/18 in-memory tests passed, with the 1/1 host test deliberately skipped.
The explicit host command then returned 0: its 1/1 test exercised exactly 2/2
children, one busy and one idle, without retries. A separate preflight courtesy
check and all four checks inside the host test returned zero matching compiler
processes. These are snapshots, not a claim of whole-host idleness.

Actual control receipts, 2026-09-07, at 100 clock ticks/second and a requested
50 ms observation interval:

| Observation | Busy child | Idle child |
|---|---:|---:|
| Child PID / start ticks | 1878434 / 3668442 | 1878491 / 3668514 |
| Observer PID / start ticks | 1878411 / 3668428 | 1878411 / 3668428 |
| Observer TID / start ticks | 1878435 / 3668444 | 1878492 / 3668516 |
| Snapshots / adjacent intervals | 6 / 5 | 7 / 6 |
| Valid child CPU deltas / adjacent intervals | 5 / 5 | 6 / 6 |
| Child CPU ticks observed | 35 | 0 |
| Independent child CPU seconds | 0.35001480999999995 | 0.00003136000000000111 |
| Observation duration, ns | 516680128 | 614191527 |
| Sampling-thread CPU time, ns | 356226503 | 407913689 |
| Skipped scheduled deadlines | 5 during 6 collections | 6 during 7 collections |
| Explicit read errors | 2310 across 6 snapshots | 2695 across 7 snapshots |
| Child exit / observer joined | 0 / yes | 0 / yes |
| Automatic performance verdict | UNKNOWN | UNKNOWN |

Both controls checked known child identity across every adjacent interval,
non-null CPU deltas, independent child CPU time agreement, non-null system CPU
observations in every snapshot, a final collection beginning after stop request,
and observer-thread termination. The emitted numeric control summaries were
retained in orchestration tool output, not a separately saved full-snapshot
archive. Error-source breakdown and every unrelated-process snapshot from these
two controls were not retained; their aggregate error counts are not evidence
that all process instruments were usable. The public unit fixtures separately
exercise named read/permission/identity failures and their UNKNOWN outputs.

**Measured limitation:** full visible-process scanning consumed approximately
356 ms of sampling-thread CPU during 517 ms elapsed, and 408 ms during 614 ms
elapsed, in these two short controls, and missed scheduled deadlines in both. This is successful
activity/idle discrimination and lifecycle verification, **not low-perturbation
qualification for approximately one-second compiler timings**. Choosing a
different observation cadence/coverage or integrating a launcher PID seam
requires a separately reviewed prospective decision; this package does neither
automatically. Broad host read errors remain explicit, not a clean-machine pass.

After these host checks, two additional in-memory cases were added for affinity
failure and numeric I/O/pressure deltas, and duplicate pressure fields were
made an explicit parse error. The final default command returned 0: **20/20
in-memory tests passed**, with the 1/1 host-control test deliberately skipped
(21 discovered tests total). The observer lifecycle/collection implementation
and host-control body were unchanged after the host run; the stricter pressure
parser and extra unit fixtures were unit-verified, not given another host run.
The original 2/2 host controls are neither silently repeated nor replaced.

The existing twelve compiler timing samples remain untouched and environmentally
qualified. No prospective compiler-cost series, performance acceptance, package
update, publication or promotion is performed by this prerequisite.

## Successor: explicit selected-PID scope (2026-09-07)

The full visible-procfs census remains the default, with its existing process
reads and original 2/2 control receipt above preserved. A new explicit opt-in
bounds only periodic per-process reads; **all aggregate/per-core CPU, system,
load, VM and pressure observations are retained**:

```python
import os
from partner_tools.cost_observation import Observer
from partner_tools.cost_observation.procfs import Procfs

# owned_pid is supplied by the caller's existing, separately authorized launcher.
reader = Procfs(selected_pids={os.getpid(), owned_pid})
with Observer([owned_pid], interval_seconds=0.05, reader=reader) as observer:
    pass  # caller owns and waits for the already-bound workload here
numeric_record = observer.result()
```

The selection is a copied, nonempty list/tuple/set/frozenset of unique positive
integer PIDs. Booleans, strings, non-integers, nonpositive or duplicate IDs,
generators, empty selections and simultaneous `enumerate_pids=` configuration
are named refusals. Selected roots/descendants are not added automatically.
One-time explicit `process_identity()` reads used to bind the owned workload
and identify the observer/native sampling thread are separate from the periodic
selection; the sampling thread's TID need not be in the process-selection set.
No compiler launcher or PID-callback integration was added.

Every produced snapshot carries `pid_coverage.mode`: `visible_procfs`,
`custom_enumerator`, or `selected_ids`. Its coverage record includes the explicit
request where applicable, attempted PIDs/count and successfully captured identity
count. Every computed interval retains both endpoint coverage records, so a scope
change cannot masquerade as continuous full-process coverage. A wholly failed
snapshot/interval remains `null`/UNKNOWN under the unchanged observer API.

In selected mode the request list is **not observed existence**. `pids_before`,
`pids_after`, `appeared_during_scan` and `disappeared_during_scan` stay `null`:
no directory enumeration took place. Consequently interval `enumeration_unknown`
is true even when all selected reads succeeded. Consult `pid_coverage`, actual
captured identities and errors; never reinterpret that request as a successful
whole-host census. A missing selected PID still yields a named read error and
zero capture for that request. Permission and PID-reuse safeguards are shared
with full mode. `unselected_process_activity`, `unselected_descendants` and
interval `outside_recorded_identities` remain UNKNOWN in the coverage metadata.
Aggregate activity outside the selected identities remains observable but is not
attributable to particular unselected processes by this mode.

The separate, explicitly authorized host command is:

```sh
COST_OBSERVATION_SELECTED_CONTROLS=1 python3 -B -m unittest partner_tools.cost_observation.test_observe.SelectedHostControls -v
```

It does not enable the original full-scope host test. It requests exactly one
new busy and one new idle owned child, the same child workload as before, and
selection `{observer process PID, child PID}` at 50 ms cadence. It prints exact
Python source hashes, full bounded returned numeric observations and summaries
including error-source counts, requested/captured PID denominators, cost,
missed deadlines, independent CPU-time agreement and stopped-thread status.
Root owns banking that stdout without truncation. Neither the test nor observer
writes evidence files. No retries or replacement of the original controls are
authorized by this successor.

Successor unit/host execution is pending at this preparation point. Scope labels
are not performance thresholds, quiet-machine judgments or release clearance.

### Executed successor receipt

The preparation status above is superseded by this executed, finite receipt;
the original full-scope measurements remain unchanged. The default unit command
returned 0: **27/27 in-memory tests passed**, with both 2/2 host-test methods
deliberately skipped (29 discovered tests). The seven new selected-scope cases
exercise request-versus-existence labeling, custom/default scope labels,
invalid/ambiguous selection, visible nonzero aggregate activity outside the
selection, missing/denied reads and both between-snapshot and within-read PID
reuse. They do not invoke a compiler or collect host workload samples.

Root executed the distinct selected command once, with its pre-record dated
2026-09-07T06:20:06Z and post-record 2026-09-07T06:21:04.991Z. It returned 0:
1/1 selected host test exercised exactly 2/2 new children, busy then idle, with
zero retries. No original full-scope control was rerun. The observer author then
read all 3/3 complete JSONL records, the full 273-byte stderr and both PRE/POST
records, rehashed all 4/4 tested Python sources and corroborated the reported
results from raw observations, rather than accepting summary counts alone.

| Selected observation | Busy child | Idle child |
|---|---:|---:|
| Child PID / start ticks | 1912735 / 3735969 | 1912763 / 3736014 |
| Observer PID / start ticks | 1912729 / 3735959 | 1912729 / 3735959 |
| Observer TID / start ticks | 1912736 / 3735971 | 1912764 / 3736016 |
| Snapshots / adjacent intervals | 9 / 8 | 12 / 11 |
| Valid child CPU deltas / adjacent intervals | 8 / 8 | 11 / 11 |
| Captured / requested PID observations | 18 / 18 | 24 / 24 |
| Per-core CPU observations in every snapshot | 12 / 12 | 12 / 12 |
| Child CPU ticks at 100 Hz | 35 | 0 |
| Independent child CPU seconds | 0.35001589899999996 | 0.000030960000000000015 |
| Observation duration, ns | 352032183 | 501655734 |
| Collection wall time summed, ns | 7904517 | 9946681 |
| Sampling-thread CPU time, ns | 8235795 | 10533718 |
| Sampling CPU / elapsed, one-CPU fraction | 0.023395005904900464 | 0.020997902119065583 |
| Missed deadlines / collections | 0 / 9 | 0 / 12 |
| Explicit read errors / snapshots | 0 / 9 | 0 / 12 |
| Child exit / observer joined | 0 / yes | 0 / yes |
| Courtesy matches, before / after | 0 / 0 | 0 / 0 |

Both error-source breakdowns are empty, corroborated by every raw error list.
All 42/42 requested PID observations across 21/21 snapshots contain the two
declared numeric identities; request lists remain distinct from null observed
enumerations. All 19/19 adjacent intervals retain selected scope at both
endpoints. Raw per-core and aggregate CPU deltas were independently recomputed
for every interval, as were the child's 35/0 total ticks and the cost/miss/error
counts. Both final collections began after their recorded stop requests. Load,
VM and CPU/I/O/memory pressure sections remained present in 21/21 snapshots.
No assertion converts these observations into coverage of unselected processes.

The full records are retained **LOCAL evidence**, not already published release
artifacts. Root banked the original untruncated stdout and stderr; the tests
themselves authored no evidence files:

| LOCAL record | Bytes | SHA-256 |
|---|---:|---|
| [PRE](../../build-ready-runtime/cost-observer-selected-2026-09-07/ROOT_PRE.json) | 1072 | `869a19b0594bb709d94e02958c72c8404f1aa32eecd3b0b582af71f085ba3cd5` |
| [Full numeric stdout](../../build-ready-runtime/cost-observer-selected-2026-09-07/selected-controls.stdout.jsonl) | 159961 | `3f028f549787dffa39a72a4a8bed3e0670516ecb207a9628db861c8d7174ee16` |
| [Test stderr](../../build-ready-runtime/cost-observer-selected-2026-09-07/selected-controls.stderr) | 273 | `981dff54bbe9e6108cfb692518f074a0911965e3d0358599e5e4674a2e85586b` |
| [POST](../../build-ready-runtime/cost-observer-selected-2026-09-07/ROOT_POST.json) | 2425 | `93f3acee24f4c8c1868e66e3b55a20e66b5e2bd48d09caece93663b5775b5ba9` |

Exact tested source identities, unchanged across the selected host controls:

| Source | SHA-256 |
|---|---|
| `__init__.py` | `7f760e627eadce63b48fa4d13fb8fd87b9dd617d52670fa1ecae256314f40a80` |
| `procfs.py` | `68fda1dce5fc3d8e6321c47fcbaa0e57d54c884870406fb6cd7968c7bcb9afcc` |
| `observe.py` | `9a45a8fd2201deae787dafa80badd18b652fa9e3a13dc3ab42e79dd12b1e6cbf` |
| `test_observe.py` | `d88f3f1b9a5bbb1487e9fa284e8b7f56c16287330c362a91767a018a445d2bd1` |

`__init__.py` and `observe.py` are byte-identical to the original implementation.
Only this README receipt was completed after the selected controls; no tested
Python source was changed or new host run added afterward.

**Remaining boundary:** the selected controls have materially lower observed
collection cost than the earlier full census, under different short control
runs, not a paired causal benchmark. Approximately 2.34%/2.10% of one CPU's
elapsed capacity is still measured observer cost, not a generic low-perturbation
guarantee. No numeric performance acceptance threshold was introduced. Full
unselected identity/activity attribution, unobserved descendants, short-lived
between-sample work and whole-host idleness remain UNKNOWN. All earlier sampling
and resource-pressure limitations remain. This successor does not close the
compiler cost packet's environmental gate, integrate the compiler launcher,
run the prospective cost series, or authorize publication/promotion.

## Launcher binding and owned-exception cleanup (2026-09-07)

This additive successor supplies a **mock-verified integration**, not an actual
wrapped compiler or non-compiler execution. It supersedes the earlier statement
that no launcher seam exists, without rewriting any earlier control receipt or
claiming those controls exercised this new code. No host controls, timing samples,
compiler builds, archive work, release or default changes ran in this lease.

### Ownership and API

`vlib.run_cmd(..., on_spawn=None)` now has exactly one optional notification,
after successful `Popen` and before `communicate`. Its default command/mask/env,
Popen session/pipes, RSS wrapping/parsing, wall-clock boundaries, returned `Run`
fields and historical `TimeoutExpired` path remain intact. Notification cost is
inside the original wall interval and is never subtracted. The callback must not
wait for a snapshot, scan descendants, poll/wait/reap the child or modify it.
An arbitrary callback exception is explicit: cleanup then the **same exception**
is re-raised. It is not silently converted into a successful Run.

`LaunchObservation` in [launch.py](launch.py) is an adapter, not a second launcher:

```python
from partner_tools.cost_observation.launch import LaunchObservation

# The caller already owns/seals these inputs and has separate run authority.
observer = LaunchObservation(sealed_executable=sealed_numeric_file_identity)
try:
    actual_run = observer.run(existing_cmd, cwd=existing_cwd, env=existing_env,
                              mask="4", timeout=180, rss=False)
finally:
    numeric_side_channel = observer.evidence
```

The caller owns saving both records. The adapter retains no command line, cwd,
environment, executable-path string or process name. Make the public package
importable in the caller's Python `sys.path` before timing; do not change the
child's environment merely to import this adapter. `sealed_numeric_file_identity`
is the caller's already-sealed executable metadata with exact integer fields
`dev`, `ino`, `size`, `mtime_ns`, `ctime_ns`. The caller must associate that seal
with the intended immutable artifact; this metadata comparison does not hash
the running executable or prove bytes against malicious metadata manipulation.

The observer starts and takes its initial aggregate snapshot before `run_cmd`.
`run_call_begin_ns` immediately precedes calling the existing runner, and
`run_return_or_raise_ns` is recorded when it returns or raises. This is a
**conservative enclosing call window**, not a replacement for vlib's exact
internal `t0`/`t1` or `Run.wall`. Startup and stop/join/identity-join work remain
outside `Run.wall`; notification and concurrent sampling perturbation remain
inside it. The side channel preserves notification wall/CPU cost and discovery
delay; none is deducted to manufacture an unobserved compiler timing.

### Wrapper identity, bounded discovery and CPU-row joins

The notification performs one numeric stat-identity capture, without descendant
discovery or waiting. A taskset/GNU-time launch PID is labeled a captured
**launched wrapper identity**, not presumed to be the compiler. Discovery in
[owned_process.py](owned_process.py) checks that identity and its main thread's
direct children, bounded by the explicit `max_children` setting (default 4).
It compares numeric `/proc/PID/exe` stat metadata with the supplied seal, with
process-identity and executable rechecks. It can recognize the target after exec
in the launch PID or as one matching direct child. Multiple matching siblings,
inaccessible candidates, changed identity, over-limit child lists or no match
produce explicit absent/ambiguous/incomplete results; no arbitrary PID wins.

The adapter reuses `Procfs(enumerate_pids=...)` with bounded dynamic targets;
records correctly say `custom_enumerator`, not `selected_ids` or a whole-host
census. Targets are the observer plus the currently validated wrapper and target,
not a recursively discovered process tree. Every before/after enumeration call,
including prelaunch calls with no target, is retained independently with its
index and monotonic window. Its result can change within a single snapshot.

Raw Observer roles remain unchanged (`other` for these unbound process rows).
They are **not** the compiler-identity authority. The separate `identity_join`
requires exactly two temporally enclosed enumeration calls for each snapshot:
both must report the same valid wrapper/target identity, matching-executable
status and relation without discovery errors. The target's raw PID/start ticks
must match, and its read window must lie between those two probes. Otherwise
the snapshot's target CPU association remains UNKNOWN. Wrapper-only CPU rows,
PID reuse, mismatched before/after probes, missing calls or improperly bracketed
rows cannot supply target counters. Raw rows and raw roles are never rewritten.

Adjacent matched samples may expose `endpoint_cpu_delta_ticks` for the same
target identity; missing samples and decreasing counters are not bridged. These
are **endpoint observations**, not continuous proof that every intervening tick
executed that image. Exec away-and-back between probes, initial work before the
first match and work after the final match remain UNKNOWN. Accordingly no whole
compiler CPU aggregate is manufactured: `compiler_cpu_summary` stays null.
All clocks supplied to the adapter/reader/finder must share one monotonic domain;
the production defaults do, while incompatible injected clocks cannot establish
a valid identity/time join.

### Deliberate exception-lifecycle correction

Old `run_cmd` cleaned its process group for `TimeoutExpired`, but had no general
cleanup for unexpected communication exceptions/interruption. That is explicitly
corrected, not described as pre-existing behavior. On an unexpected exception
(including `KeyboardInterrupt`) or arbitrary hook failure, it checks unreaped
direct-child ownership using `waitid(..., WNOWAIT)` and requires the still-owned
process-group ID to equal the launched session leader before signaling. It does
not poll/reap between ownership verification and group signaling. Already-reaped
children, lost ownership, changed groups and unsupported/failed ownership checks
cannot authorize a signal. The callback/caller must not concurrently reap this
Popen child; protection against an independent concurrent reaper is not claimed.

Best-effort TERM, two-second grace, KILL and bounded reap/owned-pipe closure are
recorded separately. Cleanup failure never replaces the original exception.
Numeric stage results are attached as `cgm_run_cmd_cleanup` and an exception
note. If an exotic exception rejects attachment/notes, numeric stderr reporting
is attempted; if that also fails, retaining that receipt is impossible and is
UNKNOWN, while the original exception still wins. Linux ownership verification
and cleanup failure paths have mocked evidence only, not new live-kernel proof.
The historical timeout branch is intentionally unchanged by this correction.

The adapter catches its own **ordinary** instrument errors into the UNKNOWN
side channel, preserving the actual Run or original launcher exception. It
stops/joins in `finally`, with at most one recovery stop attempt. A newly arriving
`KeyboardInterrupt`/`SystemExit` during stop is propagated after bounded recovery
if no original exception is pending; otherwise the pending original exception
remains primary and the cleanup interruption remains recorded. `observer_joined`
reports the actual stop state; an inability to stop is not silently made true.
Blocking kernel reads/custom readers and shared-resource/sampling limits stated
earlier still apply. No clean/fast verdict or performance tolerance is added.

### Executed mocked-test receipt and source boundaries

Exact final verification commands (no host controls enabled):

```sh
COST_OBSERVATION_HOST_CONTROLS=0 COST_OBSERVATION_SELECTED_CONTROLS=0 python3 -B -m unittest partner_tools.cost_observation.test_launch partner_tools.cost_observation.test_owned_process partner_tools.cost_observation.test_observe -q
python3 -B partner_tools/vharness/vlib.py --self-test
```

Both returned 0. **80/80 tests passed**, with both 2/2 host-test methods skipped
(82 discovered tests): 16 launcher, 13 adapter, 9 identity/time-join, 15 owned
discovery and 27 unchanged existing observer tests. The existing vlib self-test
passed **21/21 checks**. Popen, filesystem graphs, clocks and signals in the new
tests are mocked; no shell child, compiler or workload was launched by them.
The existing observer unit fixtures exercise actual in-process thread lifecycle,
not host workload execution.

An intermediate review caught two gaps after an initial 68/68 test pass:
target discovery needed an explicit snapshot CPU identity/time join, and stop
could swallow a newly arriving interruption. Two focused mocked tests then
returned 1 with **2/2 named failures**, `KeyboardInterrupt not raised` and
`SystemExit not raised`. After correction, both are included in the final pass;
the pending-original-exception priority also has its own discriminator. Wrapper-
only, identity reuse, disappearance, ambiguity, excluded grandchildren, missing
or changing enumeration probes, callback/instrument errors and cleanup failures
are exercised as explicit non-success/UNKNOWN cases, not live process claims.

Opening source identities: `vlib.py`
`19c4c18bd4447085426014a6d85541df876e3d8ad78d3b8396ceb4cda66933f9`;
this README `875fccec41dccf1172f7dc1a48f2b5c387e6915eb91e6e699fb91d486efe9693`.
The four launcher/discovery/test files were absent. Only `run_cmd` changed in
vlib; every other body remains frozen. `__init__.py`, `procfs.py`, `observe.py`
and `test_observe.py` remain byte-identical to the prior successor's seals.

| Final tested source | SHA-256 |
|---|---|
| `vlib.py` | `c4cd16f49d19d7cc7886ae8ef9135634dc96ff5bb311c939970091b69888dcd3` |
| `launch.py` | `5fde51779ad52b01b025adf3fa6a4ab7e868a0a2b997ed873f0ec4602f8d4d20` |
| `owned_process.py` | `3eaf4a4e3da01600d23eeb9e56b00ddda56b2d1513cc252c2b66491de5a14caa` |
| `test_launch.py` | `6eb5624471be305b55cfa749835484e81e8ae054e74e4aef3ac921eb991cea93` |
| `test_owned_process.py` | `a1dcbf8cc0f0ac374d7004d7a9dd9339cde33ef3c4adbe2a0c6626c62e394cbb` |

This is not yet a verified actual GNU-time/target-process integration, an
environmentally accepted compiler sample, or promotion clearance. The original
four non-compiler controls and twelve compiler samples were not rerun or replaced.

## Executed wrapped busy/idle pair — 2026-09-07

This additive receipt supersedes only the preceding **not yet live-verified**
integration status. Root executed exactly **one** invocation of
[wrapped_controls.py](wrapped_controls.py), completing **2/2 new noncompiler
children**, busy then idle, through the real `LaunchObservation` → `vlib.run_cmd`
→ taskset → GNU time → Python-child path. The invocation returned 0 with zero
retries. The original four controls and twelve compiler samples remain separate,
unchanged observations. This is not execution of the prospective sixteen-run
compiler packet or acceptance of its policy.

The [root PRE](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/ROOT_PRE.json)
is dated `2026-09-07 07:30:18 UTC`; the
[root POST](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/ROOT_POST.json)
is dated `2026-09-07T07:33:05.649Z`. They identify integration commit
`ea6cfeb53897270f8a1780d3e272b09c153d66c7` and three additional frozen control
files, not part of that commit at execution. These are local source/run
identities, not a publication statement.

Before this live pair, the control author reported **17/17 new mocked test
methods passed**, including fifteen named negative-analysis subcases within the
tests, plus **80/80 existing regression tests passed with 2/2 host methods
skipped**. Those are author-run results recorded in ROOT_PRE, not tests rerun by
root or by this receipt's author. The live pair below is a distinct root-run
instrument check; it is not a replacement for the mocked failure cases.

### Actual command, work and measured coverage

Root invoked, from `/K3D/GitHub/cgm-zig`:

```sh
LC_ALL=C python3 -B -m partner_tools.cost_observation.wrapped_controls --execute --log-root /K3D/GitHub/cgm-zig/build-ready-runtime/cost-observer-wrapped-2026-09-07/gnu-time
```

The caller banked stdout/stderr separately. The driver used the inherited
environment with `LC_ALL=C` and child `env=None`; no full environment or raw
execve capture is claimed. The sealed actual interpreter was `/usr/bin/python3`.
Each child had affinity `[4]`, a 50 ms observer interval, a 200-snapshot cap and
a ten-second existing-runner timeout. Root's earlier preflight and all 4/4
in-driver before/after screens found zero matching compiler processes; these
are pattern/queue observations, not whole-host idleness.

[control_workload.py](control_workload.py) reused the earlier `sum(range(2000))`
work, targeting 0.35 process-CPU seconds with a two-second wall ceiling for busy;
idle slept 0.5 seconds. Fixed 0.5-second pre/post holds replaced the old stdin
handshake. Both actual holds in each child were at least 0.5 seconds. The
independent child `process_time_ns()` endpoints were compared with the observed
`/proc` CPU-tick differences across a contiguous matched chain enclosing the
work. The existing three-tick allowance at 100 Hz is **instrument endpoint/
quantization slack**, not a compiler-performance tolerance.

| Actual observation | Busy | Idle |
|---|---:|---:|
| Child PID / start ticks | 2124719 / 4153985 | 2124807 / 4154134 |
| Launched wrapper PID / start ticks | 2124718 / 4153985 | 2124806 / 4154134 |
| Raw snapshots / adjacent intervals | 29 / 28 | 32 / 31 |
| Matched target snapshots / all snapshots | 27 / 29 | 30 / 32 |
| Work-chain sample indexes, inclusive | 10–18 | 10–21 |
| Work-chain samples / intervals | 9 / 8 | 12 / 11 |
| Requested / captured PID observations | 83 / 83 | 92 / 92 |
| Discovery probes | 58 | 64 |
| Work-chain CPU ticks / independent CPU seconds | 36 / 0.350012889 | 0 / 0.000015920 |
| Collection/snapshot errors | 0 / 29 snapshots | 0 / 32 snapshots |
| Adapter errors / lifecycle events | 0 / 0 | 0 / 0 |
| Discovery errors / probes | 2 / 58 | 2 / 64 |
| Missed deadlines / collections | 0 / 29 | 0 / 32 |
| Sampling-thread CPU, ns | 44085219 | 44176731 |
| Observation duration, ns | 1384397659 | 1534281969 |
| Sampling CPU / elapsed, one-CPU fraction | 0.03184433223604577 | 0.028793097939352762 |
| Collection wall time summed, ns | 42694525 | 42844883 |
| Existing Run wall, seconds | 1.3827837299977546 | 1.5327403519986547 |
| GNU time wall / peak RSS, KiB | 1.38 s / 13468 | 1.53 s / 13524 |
| Child/GNU-time exit / observer joined | 0 / 0 / yes | 0 / 0 / yes |

The complete output has **6/6 JSONL records**: pair PRE, busy raw, busy analysis,
idle raw, idle analysis, pair completion. Together they retain **61 snapshots,
122 discovery probes, 59 adjacent intervals and 175/175 requested PID captures**.
Each raw record precedes its analysis result. The receipt author parsed every
JSONL record, re-derived all 7,670 aggregate/per-core CPU-state deltas across the
59 intervals, checked all 57 matched snapshot joins against their two discovery
probes and raw child rows, and independently recovered the 36/0 work-chain ticks
and child-clock values. This did not invoke the production analyzer or launch a
child. Both final collections began after their recorded stop requests.

Zero snapshot/adapter errors must not conceal the discovery errors. Busy probes
56/57 and idle probes 62/63 each report `FileNotFoundError`, errno 2, at the
wrapper stage: **four expected final wrapper ENOENT observations in total**.
The discovery status counts are busy `2 not_launched + 54 matched_direct_child
+ 2 incomplete_discovery`, idle `2 + 60 + 2` respectively. The first and final
snapshots of each control therefore have no matched target association.
Startup/exit coverage and between-probe execution remain UNKNOWN. A returned
or reaped direct wrapper does not prove all possible group descendants exited.

The sampling CPU measurements are **44.085219 ms / 1.384397659 s ≈ 3.1844%**
and **44.176731 ms / 1.534281969 s ≈ 2.8793%** of one CPU's elapsed capacity.
They are actual instrument cost during these held controls, not a general
low-perturbation bound or a paired cost comparison with earlier controls.
Notification cost is separately retained; discovery occurs inside collection
cost. Nothing is subtracted. Run wall includes the existing wrapper/launch path,
GNU-time overhead and child startup/holds/work; GNU time retains its own child
resource interval. The adapter's monotonic call window is conservatively
enclosing, not an exact exec interval. The analysis fields named `launch_gap_ns`
and `exit_gap_ns` reference the chosen **work-chain** endpoints inside the holds,
not necessarily the first or last discovered target observation.

### Seals and immutable evidence

All **13/13 source** and **4/4 tool** identities/hashes agree between the pair
PRE, both controls' before/after banks, and this receipt's read-only check.
The JSONL preserves their full numeric file identities and complete source path
set. The source rows below are relative to the public repository; these are
exact input seals, not a claim to seal the Python standard library or host OS.

```text
7f760e627eadce63b48fa4d13fb8fd87b9dd617d52670fa1ecae256314f40a80  partner_tools/cost_observation/__init__.py
419f96bf12e416c70cb8f691c930aebf0e6bf5cd1a03aace8f7ce3bc279e4c70  partner_tools/cost_observation/control_workload.py
5fde51779ad52b01b025adf3fa6a4ab7e868a0a2b997ed873f0ec4602f8d4d20  partner_tools/cost_observation/launch.py
9a45a8fd2201deae787dafa80badd18b652fa9e3a13dc3ab42e79dd12b1e6cbf  partner_tools/cost_observation/observe.py
3eaf4a4e3da01600d23eeb9e56b00ddda56b2d1513cc252c2b66491de5a14caa  partner_tools/cost_observation/owned_process.py
68fda1dce5fc3d8e6321c47fcbaa0e57d54c884870406fb6cd7968c7bcb9afcc  partner_tools/cost_observation/procfs.py
6eb5624471be305b55cfa749835484e81e8ae054e74e4aef3ac921eb991cea93  partner_tools/cost_observation/test_launch.py
d88f3f1b9a5bbb1487e9fa284e8b7f56c16287330c362a91767a018a445d2bd1  partner_tools/cost_observation/test_observe.py
a1dcbf8cc0f0ac374d7004d7a9dd9339cde33ef3c4adbe2a0c6626c62e394cbb  partner_tools/cost_observation/test_owned_process.py
48629a8f81ddf9da79fec85bfb175a27d2cf9212a7d8bd801627ed3cfa469388  partner_tools/cost_observation/test_wrapped_controls.py
f9a4c28b891b251a3172810491441295a9ffe187c0bb12e1e7a2d2a58aa997b9  partner_tools/cost_observation/wrapped_controls.py
5c65c3cf9ad7bb8a264fb7b6700978eda1cf8775544458f8dc8e98ec81473062  partner_tools/oracle_lib.py
c4cd16f49d19d7cc7886ae8ef9135634dc96ff5bb311c939970091b69888dcd3  partner_tools/vharness/vlib.py
b942f1aa7cd611419e4c08ae2f0985a7f7c89502ce635811661df87ee902fee0  /usr/bin/pgrep
4b30993b48ddd48bd4ee1b06c9ba4cdcf010bb06253ee518d8961b214231de41  /usr/bin/python3
46d4e1a683dc33209232e738afed6bce4c64de60f90e89d245273aa1dad2ed50  /usr/bin/taskset
6a1994aecdf6bbabe1f220965f5b5c3c5845d04d93afaeed6368b9edac1d9a0a  /usr/bin/time
```

These are retained **LOCAL** records, not newly published artifacts. Every
listed file was read completely and its bytes/hash checked; both raw GNU-time
files also match the embedded raw output and hash in the JSONL.

| LOCAL evidence | Bytes | SHA-256 |
|---|---:|---|
| [ROOT_PRE.json](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/ROOT_PRE.json) | 2487 | `fa51eb7004600d136fe3ed939c90e93cae9e66122e456e384e715d19888b6733` |
| [ROOT_POST.json](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/ROOT_POST.json) | 3365 | `36fead3ba365d010942833aa35bd220151260cf9daa3cae34518cd4ed772f4cf` |
| [Full stdout JSONL](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/wrapped-controls.stdout.jsonl) | 688260 | `63fe3370cd4053e83f1ca5e40851e9f2305f72deddc884aa4741b8675f271130` |
| [Outer stderr](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/wrapped-controls.stderr) | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| [Busy GNU time](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/gnu-time/busy.time.txt) | 790 | `e3bdd3417f7676117f2678a55f1158f64ebebdbd4cc6a2cd3fcde0a70925d76a` |
| [Idle GNU time](../../build-ready-runtime/cost-observer-wrapped-2026-09-07/gnu-time/idle.time.txt) | 789 | `61b64760a67ae6057db9ab877628f03325882a0ed597c2b2372e76a6a9b4a107` |

### Replay boundary and remaining scope

For a future separately authorized reproduction, use a **new, absent bank**;
never rerun into the evidence above. The driver requires its GNU-time directory
to exist and be empty. Example only, not an additional execution request:

```bash
cd /K3D/GitHub/cgm-zig
set -o noclobber
wrapped_replay=/K3D/GitHub/cgm-zig/build-ready-runtime/cost-observer-wrapped-replay-01
test ! -e "$wrapped_replay" && test ! -L "$wrapped_replay" || exit 2
mkdir "$wrapped_replay" || exit 2
mkdir "$wrapped_replay/gnu-time" || exit 2
LC_ALL=C /usr/bin/python3 -B -m partner_tools.cost_observation.wrapped_controls \
  --execute --log-root "$wrapped_replay/gnu-time" \
  > "$wrapped_replay/wrapped-controls.stdout.jsonl" \
  2> "$wrapped_replay/wrapped-controls.stderr"
wrapped_replay_rc=$?
# Retain the exit code and all outputs. No automatic retry after HOLD/failure.
```

Root owns any such authorization, fresh preseal/environment review and subsequent
readback; new observations must not replace this pair. Permission/identity gaps,
unselected processes and descendants, between-sample work, all-thread residency,
blocking reads, and shared-cache/bandwidth/thermal effects retain their earlier
limits. Neither zero snapshot errors nor the matched work chains prove a whole
host clean, a compiler unaffected or two compiler artifacts equivalent. No
timeout/cancellation signal path was fired by this successful live pair; those
paths retain their mocked verification ceiling. No overhead subtraction,
sixteen-run acceptance, release, publication or promotion verdict follows.

This receipt was appended by GPT 6 Astra after read-only raw-data reconciliation.
The previous **30,348 bytes / 491 lines**, SHA-256
`3a437233adb4ec87f5faa971d3fe4a747d159ddc1172bdc0c69f102b9fc96813`,
remain an exact unchanged prefix. Only this README was edited, with `apply_patch`;
no test, workload, compiler, host observation, source, archive or default action
was performed by this documentation lease.
