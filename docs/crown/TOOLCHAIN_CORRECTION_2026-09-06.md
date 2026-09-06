# Toolchain correction — 2026-09-06

This finite wave corrects production identity reporting, one exhaustion remedy,
and prepared negative-control recipes. It does not change the worker/partition
derivation, ready ordering, admission predicates, language, or promoted binary.
The multitasking enhancement remains a separate implementation and verification
task; the concrete next packet is below.

Maintainer direction: Daniel Campos Ramos requested correction and continuation
of the existing compiler multitasking work. Diagnosis and this implementation:
GPT-6 (OpenAI Codex), working as an AI partner. Source review/build/promotion and
publication belong to the coordinating maintainer workflow, not this receipt.
Upstream-Status: not-filed-policy.

## Measured starting state and synchronization handoff

- HEAD: `63effbe93c276735c56c6d8ab1cb3f2149365c19`, branch
  `patch/005-auto-hardware-threading`, initially clean.
- Fresh `git ls-remote origin refs/heads/main
  refs/heads/patch/005-auto-hardware-threading` returned that same SHA for
  both requested refs. Cached refs agree; this was not inferred from them.
- Local `main`: `6377899732bbccaa3cdab0c686169c903a880de3`, checked out in
  `build-p005/vwork2/wt_main`, clean. `git rev-list --left-right --count
  main...HEAD` returned `1 36`; `git cherry HEAD main` returned
  `- 6377899732bbccaa3cdab0c686169c903a880de3`. The local-only visibility fix is
  patch-equivalent to `e0bcdab2`, already on HEAD. It is not a missing fix.
- Safe local-main reconciliation after the source review: recheck its worktree
  is clean and inactive, preserve a backup branch at its old tip, then rebase
  local `main` onto the freshly verified `origin/main`. The duplicate patch
  should be skipped. Verify the resulting ref and worktree; do not force-reset
  or overwrite the checked-out branch. A fast-forward alone cannot resolve
  the initial divergence. No remote push is needed merely to repair that
  local reference; pushing subsequent reviewed changes is a separate action.
  No git mutation was performed in this wave.
- The station command resolves through `PROMOTED/zig` to
  `PROMOTED/stage3-046d6833/bin/zig`. Fresh version: `0.16.0`; SHA-256:
  `046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11`.
  `PROMOTED/RECORD.md` records the ReleaseSafe build and its source at
  `b991cb16`. Before this correction, the committed `src/` and `lib/` diff
  from that source to HEAD was empty. This wave's diagnostic edit is SOURCE
  ONLY and is not in that promoted binary.
- `fork_status.py` counted 18 upstream-code-touching commits of 57 non-merge
  commits since imported root `754b7a387248`. This is a history count, not a
  test or promotion score.
- The official stable-release gate returned `STABLE-0.17-OR-LATER: ABSENT`.
  [The upstream index](https://ziglang.org/download/index.json) listed stable
  `0.16.0` and development `0.17.0-dev.2018+ab30a0b9a`. Codeberg `ls-remote`
  returned master `8839d95005bff0742ba9cd75b069b4967c35c04c` and tag
  `0.16.0` at `44d9672fed001115e674fd5ddb32747ef43a7af4`; neither requested
  `0.16.1` nor `0.17.0` tag was present. No stable upgrade was attempted.
  The tarball-import fork has no merge base against cached upstream/master;
  merging development history is not this synchronization operation.

## Corrections and receipts

### Production identity

PRE: `fork_status.py` hard-coded `build-safe/stage3/bin/zig` and reported
SHA `60fad8a75bb238039bdf310bb9b3bfbd2f7ec2818404ca8ddbb6f1b7ca4378c5`
as the toolchain, despite the production pointer resolving to `046d6833…`.
POST: production is resolved from `PROMOTED/zig` on each invocation. The old
build-safe compiler is labeled `reference`. Both reports include the authority,
resolved path, version and digest; no fallback substitutes the reference for a
missing production authority. PRESENT means a regular file was hashed and
answered the bounded version probe, not that build mode or correctness was
independently verified.

The same first eight output tests measured **0/8 passing PRE -> 8/8 POST**.
They exercise distinct production/reference bytes, missing authority, broken
pointer, directory target, an unexecutable file, nonzero version exit, empty
version output and multiline version output. Fixtures are shell version stubs,
not compiler builds. Failure paths explicitly report UNKNOWN.

A ninth test sabotages the report emitter in memory to print a false
`production: PRESENT` for the absent input. The self-test returns **1** and
prints `-> FAIL` despite the input's absence predicate remaining true. The mock
is restored on leaving its context and the source SHA is verified unchanged.
Thus the guard has been seen red on the output it promises to validate.
Final suite: **9/9 pass**, exit 0. The ordinary `--self-test`: **2/2 pass**
(emitted UNKNOWN arm plus resolvable git base), exit 0.

Exact test commands:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s partner_tools -p test_fork_status.py -v
PYTHONDONTWRITEBYTECODE=1 python3 partner_tools/fork_status.py --self-test
PYTHONDONTWRITEBYTECODE=1 python3 partner_tools/fork_status.py
```

All fixture directories remain under ignored `build-toolchain-correction/`.
PRE: `status-z605lfgr`; first POST: `status-e3agko8b`; final suite:
`status-g6c5t6gh`. No cleanup deleted them. Test/oracle patterns were searched
before authoring the single sibling test file; it reuses `oracle_lib.sha256_file`.

### Exhaustion remedy

PRE: `InternPool.Index.wrap` offered `--intern-partitions=2`, but
`ThreadPlan.starvedLanes` rejects two partitions when `workers > 1`.
POST: the same diagnostic explicitly gives `-j1 --intern-partitions=2` and
names the cost of fully serial compilation. Its immediate comment explains
the liveness constraint. Encoding, masks, numeric arguments and guards are
unchanged.

```sh
PROMOTED/zig ast-check src/InternPool.zig
```

Result: exit 0, stdout/stderr 0 bytes, **1/1 touched Zig files passed
parse/AstGen checking**. This is not Sema or a rebuilt diagnostic observation.
New diagnostic behavior: **UNRUN**. Historical V16 evidence establishes the
serial configuration's previous viability, not this new message's execution.

### Prepared controls

PRE: V-S2a and V-S2b both failed `git apply --check` because context after the
reserve assignment predated the starvation guard. POST: **2/2 patches apply**;
their only intended mutations remain reserve=0 and reserve=limit+1.

V14 already applied before this wave and still applies. Its old expected
`6 physical / 4 logical` result was invalid: the outer affinity-filtered loop
still bounds the number of cores. The corrected recipe derives a singleton
partial-SMT mask and compares sibling membership and `threads_per_core` against
sysfs. It describes the minimal library witness: the unchanged promoted compiler
compiles the same small probe against isolated pristine/sabotaged library
copies; the excluded sibling must appear only in the sabotaged map. Restoration
requires matching SHA-256 and a passing rerun. No stage3 rebuild is needed to
exercise that library primitive, but this does not prove compiler-startup
integration. Probe builds and all dynamic controls remain **UNRUN / UNKNOWN**.

```sh
git apply --check partner_tools/vharness/sabotage/V14_affinity_intersection.patch
git apply --check partner_tools/vharness/sabotage/VS2a_concurrent_reserve_zero.patch
git apply --check partner_tools/vharness/sabotage/VS2b_reserve_exceeds_async_limit.patch
git diff --check
```

Each patch check exited 0 with no output; no sabotage was applied to SOURCE.
`git diff --check` was clean. Applicability is not the control going red.

## PRE / POST SHA-256

| File | PRE | POST |
|---|---|---|
| `partner_tools/fork_status.py` | `4eae176976e22b979a643290322731e1615cf5b009302a798fcc54e86cb05651` | `abd4d2c07ce679a122cbb59f24847dd01f5b28bb6e52f810947ec1208ef24f2c` |
| `partner_tools/test_fork_status.py` | ABSENT | `3f3a9c137195431c9c85444e3e681233e3b12d28cea75a05f5a6efe4ee417c92` |
| `partner_tools/vharness/sabotage/README.md` | `fbb916c946db81d2e8f43410e9557c7e423e763cfea6c77e6d4e455dbc61b93c` | `d5ae895b8e798d80d4faf1dbf006081f3af79c08f86cb70e3ffc7187bf15b3ba` |
| `partner_tools/vharness/sabotage/VS2a_concurrent_reserve_zero.patch` | `0cea3c1ff0e315efe387a80f5fc77346e7952e17ba536eb787d32150bd3fb4eb` | `61f6b834d01b64729a2e858cde7117da2a7d2747d9743251dcb63821f4c06a0d` |
| `partner_tools/vharness/sabotage/VS2b_reserve_exceeds_async_limit.patch` | `1f8e7506cc2262e5d64aa4b491e7338e58f7c71797a2ec1dbaa2d03519b83263` | `69adc3d1c8d0cd55e974583506cad28e7cefa7db1ca31d61c41f8c57463bef89` |
| `src/InternPool.zig` | `e7aab03df42496938b2c6cc971aa5008ff9749d56676a1bf6fa1ed05cac0a0eb` | `0e58ffa85362a869d29cb262c0543e365032c4e859f0272eef77d63bd2d1a0b5` |

Hashes were captured with `sha256sum` over the exact six paths in this table.
This new receipt has no PRE file and does not embed its own digest.

## NEXT — complete the designed ranked ready index

**Existing intent, not a new scheduler:** `PATCH005_DOSSIER.md` §4.3 explicitly
proposes keeping `outdated_ready` authoritative and adding ranked depth buckets
to reduce selection overhead. `src/Zcu.zig:3369` still scans every ready key on
every layered pick. `ModuleRanking.zig` already supplies depth/fan-in/facade
comparison; `Zcu.file_rank_memo` already resolves each file once. Reuse them.

The shipped layers are distinct: build-runner step ordering is implemented;
AstGen's initial module-root spawn ordering is implemented at
`src/Zcu/PerThread.zig:224`, while files whose module ownership is not yet known
retain discovery order. Wide AstGen and the narrow import-allocation tail are
implemented at `:491`/`:514`. Sema still runs through the main-thread update in
`src/Compilation.zig:4587`. The next index reduces ordering overhead; it does
not turn Sema into parallel analysis or add eager work.

**Finite proposed scope:** auxiliary ready-index ownership in `src/Zcu.zig`,
using the existing comparator and `.layered` switch, plus routing the external
`struct_defaults` ready insertion at `src/Zcu/PerThread.zig:1491` through the
same index-update seam. Preserve functions before
other units, the exact eligible unit set, unknown-rank fallback, dependency-cycle
fallback, and `.insertion` default. Integrate with existing insertions/removals
at `Zcu.zig:3214`, `:3240`, `:3272`, `:3332`, `:3755`, `:3772`, `:3789`,
`:3800`. Tie, lifetime and allocation rules must be concrete before authoring:

- Ties must
match the current scan's key order: array-map `swapRemove` means a naive FIFO
  bucket would change that order. Update the moved last key's priority position
  as part of each removal, and compare against the existing scan oracle.
- The ready maps start empty at `Zcu.zig:305` and are deinitialized at `:2968`;
  the auxiliary index needs the same lifetime. Module ranking is established
  at `Compilation.zig:2380`; file ownership is assigned by `computeAliveFiles`
  before Sema, and memoized at `Zcu.zig:3412`. Invalidate/rebuild the index at
  update/generation boundaries or rank-source changes; never retain a stale
  rank merely because a unit stayed ready. No direct map mutation, including
  the PerThread site, may bypass the index contract.
- Index allocation is optional optimization, like the existing rank memo's
  `catch {}` at `Zcu.zig:3427`. If an auxiliary update cannot allocate, discard
  or disable that index and use the original scan for the authoritative maps.
  Never leave a partially updated index eligible for selection, and never
  drop ready work on OOM. Authoritative-map allocation errors keep their existing
  behavior. Exercise this fallback with allocation-failure injection.

No worker-count, pool-encoding or admission rewrite belongs in this packet.

**Discriminating acceptance:** compare selected-unit sequences against the
existing scan through insert/remove/requeue, tied ranks, unknown ranks,
functions-first and cycle fallback; then preserve artifact/diagnostic parity
on bounded compiler fixtures. Add a deliberate index sabotage to prove the
sequence oracle detects drift, restore and hash-check. Use paired old/new
layered measurements plus insertion control on the same fixture, affinity,
cache state and library tree; report Sema CPU time, wall/RSS and per-pick work.
The recorded run-2 layered penalty was +6.59% on its fixture; eliminating that
overhead is a hypothesis until measured. Current V8 checks a ranking report and
records wall cost; it does not independently prove selected-unit sequence or
make a speed claim. Preserve its capability meaning and add the needed oracle.

**Verification cost:** read/parse is cheap; Sema-only checking was recorded at
about 45 s. A ReleaseSafe stage3 rebuild was recorded at 8–9 min on an idle
unconstrained host or about 41 min on a contended 8-CPU mask. Exact cost and
current machine availability are UNKNOWN until measured. Queue builds under
machine courtesy; keep the current promoted compiler until separate acceptance.

**WIP reuse findings:** rung-2 at `f968af045d` branches from `16f5299f` and
already implements direct/import-alias declaration-name checks in
`AstCheckImports.zig`; arity is explicitly deferred, opaque targets/skips are
counted, and lexical shadowing is not resolved. Rung-4 at `7c0ee97568` branches
from `3d37ca1e` and already threads `ModuleBinding` through batch/import checking.
Its chosen path sandbox is stricter than actual compiler `@import` behavior.
These are old-base, separately reviewed bodies to reconcile selectively; they
are neither completed on main nor prerequisites for the ready index. Wholesale
branch-tree replacement would discard newer batch/diagnostic work.

**Packaging reuse:** the existing release's asset layout, digest and tag are
recorded in ignored `PROMOTED/RECORD.md` (2026-08-30): bin + lib + docs from the
durable stage3 directory, excluding aside binaries, with a `.sha256` sidecar.
No dedicated release-packaging tool was found in the inspected `partner_tools/`
and crown docs. Those records are reuse pointers, not a new package verification.

## Residuals

No Sema/build, full harness, benchmark, dynamic V14/V-S2 control, race detector,
toolchain repoint, commit, synchronization, package or release ran in this wave.
The previous V12 race-proof limitation remains unchanged. Stable 0.17 remains
gated by the release-upgrade skill. All manual edits used `apply_patch`.

The bounded private-reference lookup returned three general Zig excerpts using
2,160 of a 3,200-character budget; three compiler-IR excerpts were dropped by
the chunk limit. It did not establish compiler-concurrency facts; the cited
local source and stored negative-control receipts did.
