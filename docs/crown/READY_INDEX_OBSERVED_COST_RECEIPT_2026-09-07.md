# Ready index: two stopped observed-cost attempts — 2026-09-07

Status: **both attempts stopped; zero quality-supported timings from two actual
compiler invocations**. Neither sixteen-slot matrix completed. No further
workload is authorized by these records. This receipt documents root execution
and independent read-only corroboration by GPT 6 Astra; it performs no run.

The [prospective packet](READY_INDEX_OBSERVED_COST_PACKET_2026-09-07.md), SHA-256
`7f05f63203f112a8dcf257359ce26d0f732da6f9383ce7158f851613127e1237`, remains
unchanged with its historical PREPARATION ONLY status. Root's separate PRE
records supplied actual launch authority and accepted the stricter zero-sibling-
execution/zero-wait rule **before results**, without changing the packet.

## 1. Separate attempts, not replacement samples

Both attempts retained the same `ABDC / BCAD / CDBA / DACB` planned order and
stopped after A, old/default. All paths below are repository-relative.

| Distinct LOCAL bank | Launched / planned | Compiler / outer exit | Quality-supported | Unlaunched | Reason |
|---|---:|---|---:|---:|---|
| `build-ready-runtime/observed-cost-2026-09-07` | 1 / 16 | 1 / 1 | 0 / 1 | 15 / 16 | Root omitted the libc environment binding |
| `build-ready-runtime/observed-cost-bound-2026-09-07` | 1 / 16 | 0 / 0 | 0 / 1 | 15 / 16 | Positive sibling execution violated the preaccepted rule |

The second bank was separately authorized after a declared orchestration
correction; it did not replace the first bank's slot. There were **two actual
invocations**, not 32, and neither abandoned plan authorizes its remaining
slots. No sample is retried, overwritten, pooled or promoted into another series.
The [original twelve-run receipt](READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
still records 12/12 successful compiles with environmental qualification. Those
twelve are not pooled with either observed attempt.

The [live wrapped controls](../../partner_tools/cost_observation/README.md#executed-wrapped-busyidle-pair--2026-09-07)
had completed 2/2 noncompiler children, busy then idle. Their acceptance was
instrument correctness only, not quiet-machine or compiler-cost acceptance.
Root identifies local integration/control commits `ea6cfeb53897270f8a1780d3e272b09c153d66c7`
and `9a483732f8`; this is not a claim of online synchronization or publication.

## 2. First attempt: root launch-binding error

Root split the packet's required persistent-shell setup into separate shells.
The retained `ROOT_LAUNCH_01.sh` referenced `cost_libc` without rebinding it;
the actual saved child environment contains `ZIG_LIBC=""`. The old compiler
returned 1, with 62 stderr bytes:

```text
error: unable to parse libc paths file at path : FileNotFound
```

GNU time also records exit 1. Run wall was 0.016558420000365004 seconds, but
this failed setup invocation is **not a valid performance sample**. The two
observer snapshots and joined stop do not repair the missing workload result.
Root's decision and POST name its orchestration error, not a compiler regression.
The command, admission, decision and all four raw slot files remain preserved.

The corrected bank's `ROOT_SLOT_LAUNCH.sh` is self-contained per invocation:
it enables `nounset`, binds the libc path, checks readability, verifies the
actual Python-process `ZIG_LIBC` before workload Popen, and requires the prior
accepted decision before later slots. Its source was independently compared
with the frozen packet before launch; artifact/flags/observer settings remained
unchanged. Root's `ENV_BINDING_CHECK.json` is explicitly a no-workload check.

## 3. Corrected attempt: successful compile, failed quality gate

The corrected bank derived current online siblings `[4, 10]`, not an assumed
permanent CPU10 binding. Its first three-observation admission attempt held:
the second observation had CPU4 **84% idle / 8% iowait**. That was a non-launch.
A separately recorded continuation allowed one fresh admission attempt, which
passed all three observations. The accepted admission endpoint preceded the
runner-call window by **13.738519465 seconds**. That gap remains visible;
root's statement that no heavy hashing occurred inside it is not an independent
continuous process-history observation.

Root then invoked the sealed script once through Bash for slot 01. The actual
environment contains the correct existing libc path. The old/default compiler
and GNU time returned 0; full stderr contains the expected workers=1,
partitions=2 report and no ranking report. Run wall is **1.053263188994606 s**;
GNU time records **1.05 s**, user **0.93 s**, system **0.11 s**, peak RSS
**238,240 KiB**, zero major faults/swaps and nine involuntary context switches.
These are retained observations of one old/default invocation, not comparative
or accepted performance results. `Run.peak_rss_kb` remains null because raw GNU
time was explicitly retained with `rss=False`.

The preaccepted stricter rule fails at raw sample interval **8→9**: CPU10 user
ticks change **152133→152134**, while its other execution counters are unchanged.
That is one positive sibling-execution tick. The decision names it
`sibling_execution_9_cpu10`: 9 is the one-based interval counter, not a different
pair of samples. CPU4/CPU10 iowait and steal deltas remain zero across the
22 overlapping intervals. The single positive execution interval is sufficient
to stop the series under the rule already sealed; no threshold was relaxed.

The interval's enclosing observation span is monotonic nanoseconds
`43163772982393` through `43163824409478`, inside the conservative runner-call
window `43163373710414` through `43164426993213`. Counter sampling is not an
atomic scheduling trace. This failure does **not** identify the executing
process, prove a causal slowdown, or turn iowait into CPU contention evidence.

The independent raw review reconciled **23 snapshots / 22 overlapping adjacent
intervals**, including all **2,860 CPU-state deltas**. Target snapshots 1–20
form **19 contiguous matched target intervals**, with matching PID/start
identity, affinity `[4]`, executable-discovery brackets and raw counter rows.
Snapshot 0 has no initial target match; 21 and 22 lose target coverage at exit.
Discovery probes 42/43 report direct-child ENOENT and 44/45 wrapper ENOENT:
four explicit discovery errors, despite zero snapshot/adapter/lifecycle errors
and zero missed deadlines. The observer joined with `caller_stop`. None of
these zero-error counts establishes full identity coverage or a clean host.

All CPU/I/O/memory pressure `some` and `full` totals were available across
22/22 intervals. Summed deltas include CPU-some **4,161 µs**, I/O-some
**4,051 µs** and I/O-full **3,597 µs**. They are aggregate observations without
attribution to the unselected processes or to a particular timing effect.
Sampling-thread CPU was **33,142,033 ns / 1,054,709,507 ns ≈ 3.1423%** of one
CPU's elapsed capacity. No observer, notification, discovery, GNU-time or
wrapper cost was subtracted. Startup/exit gaps, between-probe work, unobserved
descendants and all-thread scheduling history remain UNKNOWN.

## 4. LOCAL evidence and input seals

The records linked here are **LOCAL files, not tracked Git payloads or already
published evidence**. Root's first POST is dated `2026-09-07T07:54:09.925Z`;
the corrected POST is dated `2026-09-07T08:01:36.262993+00:00`. Their complete
file lists seal the commands, admissions, decisions, manifests and raw outputs.
This receipt independently verified **12/12 file rows in the first POST and
16/16 in the corrected POST**, including each recorded byte count and hash.

| Major LOCAL record | SHA-256 |
|---|---|
| [First ROOT_POST](../../build-ready-runtime/observed-cost-2026-09-07/ROOT_POST.json) | `51b1b16a2260b96a169f72c7d88b5a69e1402949b57ffd3515b80610b28d46bf` |
| [First raw Run](../../build-ready-runtime/observed-cost-2026-09-07/slot-01/run.json) | `91003570837c02f0c2a824df5ab0094507695a24399115d60fdffb54c457850b` |
| [First raw observation](../../build-ready-runtime/observed-cost-2026-09-07/slot-01/observation.json) | `e11a86098cdbc29df96214469d93098a8aabdd5d8363a2b0cf682319eeb76db1` |
| [Corrected ROOT_PRE](../../build-ready-runtime/observed-cost-bound-2026-09-07/ROOT_PRE.json) | `4229303d1c0ac5fc587793111144a560dedf71d6db4f6d57932150f995a70610` |
| [Corrected launcher](../../build-ready-runtime/observed-cost-bound-2026-09-07/ROOT_SLOT_LAUNCH.sh) | `74b05c55dbdbe0716a2e06ab3fce0c6fc589aacf594a46bb76a9ddafb237d1e7` |
| [Corrected decision](../../build-ready-runtime/observed-cost-bound-2026-09-07/DECISION_01.json) | `70a3d463b6670dc9632de8cdff4e5b0a90087d90ae403044c45c22703e45b691` |
| [Corrected ROOT_POST](../../build-ready-runtime/observed-cost-bound-2026-09-07/ROOT_POST.json) | `12029af8a78634dc9e7724632f0165bc9f908dbd5062b21ed034ea37287874aa` |
| [Corrected raw Run](../../build-ready-runtime/observed-cost-bound-2026-09-07/slot-01/run.json) | `46e102a4e255d3b3f0c24334a31accb78b11c17af6f518abb10a8301bdf80f8d` |
| [Corrected raw observation](../../build-ready-runtime/observed-cost-bound-2026-09-07/slot-01/observation.json) | `91ca22dc0d7da64e47b6e3ac21d70ccff11c7761b8f73214ce09945fa59f39e6` |

Both PRE records contain fourteen input entries: two compilers, fixture, libc
file, seven repository Python runtime sources and three executable tools.
Current hashes and recorded device/inode/size/mtime/ctime metadata match
**14/14 entries in each bank**; these are two bank checks, not 28 unique inputs.
Old compiler SHA-256 remains
`046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11`;
candidate remains
`d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f`.
The unchanged vlib identity is
`c4cd16f49d19d7cc7886ae8ef9135634dc96ff5bb311c939970091b69888dcd3`.

Root's postchecks also seal the unchanged **19,543-file / 184,297,278-byte**
common library. All four before/after full-path manifests agree at
`df972a29f43f7fb52560346deb5ece2cb5a54e20b17c9eae67462404d2f8de6f`.
This documentation review verified those complete manifest files; it did not
independently rehash all library bodies. OS/shared-library/Python-stdlib state
is not hermetically sealed, and neither source hashes nor process-pattern
checks establish continuous host isolation.

## 5. Remaining boundary

No new-versus-old, default-versus-layered or index-speed comparison follows
from a single old/default compile, especially one rejected by its predeclared
quality screen. The full observed sixteen-run matrix and clean-machine cost
acceptance remain **UNFULFILLED**. No further launch, new series or retry is
authorized by this receipt; the original twelve observations stay qualified
and separate.

The [existing package/companion receipt](CANDIDATE_PACKAGE_VERIFICATION_2026-09-07.md)
retains candidate archive SHA-256
`3f82e9bb94ae116a844b38472e09d520fc898fc0f2b2665ac360fc5cf29ac1e4`
and separate evidence archive SHA-256
`38fbf22e748d049ee5582e6a32671f46b8668a546390d29b46c6dfc9a93f84ec`.
Those archives remain frozen: the later observer/control implementation, these
new attempt records and this receipt were **not silently added** to either.
This lease did not rehash or repack the archives. It implies no publication,
online-main push, release, default promotion, crown-stage or foundation completion.

Authoring scope: this new receipt and an ending status section in PLAN only,
using `apply_patch`. PLAN's original 15,088 bytes / 217 lines, SHA-256
`67e9232e65b4ea11648cffdb2a870649a26ccf6b95a267a7c3d8e54cc202245b`,
remain its exact unchanged prefix. No compiler/test/host observation, helper,
Git/network action, source/input edit or archive/default change was performed.
