# cgm-zig — a patched fork of Zig 0.16.0

> *"This repository exists to deposit AI garbage that actually makes Zig better and
> works with hyper-modular code."*
> — Daniel Campos Ramos, founder, EchoSystems AI Studios, 2026-08-22
> (with a nod to the Zig president's assessment that AI-assisted contributions are
> "invariably garbage" — the full story, and the full credit chain, live in
> [`PROVENANCE.md`](PROVENANCE.md))

Maintained by **EchoSystems AI Studios** (Daniel Campos Ramos) as a build-station
toolchain fork. Upstream: [Zig](https://ziglang.org) 0.16.0, imported verbatim from
`zig-0.16.0.tar.xz` (sha256 `43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf`).
Upstream's own README is preserved at `README.upstream.md`; upstream's MIT license
(`LICENSE`) governs and is preserved unmodified.

## Why this fork exists

Building a large hyper-modular project (≈1,800 named modules / ≈2,300 files analyzed
as one compilation unit) reproducibly crashes the zig 0.16.0 frontend with a silent
SIGSEGV: a `u32` 0xFFFFFFFF "none" sentinel is dereferenced as a live index into an
8-byte-element table (faulting address decomposes exactly as `base + 0xFFFFFFFF*8`,
confirmed in two independent builds with an identical backtrace tail). The crash is
invariant across warm/cold cache, 8MiB/unlimited stack, self-hosted/LLVM backends,
and incremental on/off. Two superficially similar upstream issues were reproduced
locally and refuted by discriminator. The shipped release binary is built
ReleaseFast/stripped, so the failure is silent; a ReleaseSafe rebuild makes it name
its own site.

The Zig project's contribution policy (2026-04) does not accept content generated,
edited, brainstormed, or **debugged** with LLM assistance — in issues, pull requests,
or bug-tracker comments. This defect was diagnosed end-to-end by a human+AI
partnership, so it cannot be reported or fixed upstream under that policy without
misrepresenting its provenance, which we will not do. This fork is the lawful
remaining channel: MIT licensing is independent of contribution policy.

Scope is deliberately minimal: a patchset on upstream 0.16.0, rebase-friendly, no
language divergence. If upstream ever fixes the defect class, this patchset shrinks
toward zero and the fork retires.

## What differs from upstream Zig 0.16.0

Historical snapshot at `63effbe9` (before the 2026-09-06 candidate): 57 commits since the verbatim tarball import
(`754b7a38`), touching 63 files, +12,744 / −109 lines. By directory: compiler
`src/` 13 files (+3,007 / −97), `lib/std/` 6 files (+575 / −2), `lib/compiler/`
1 file (+347 / −5), documentation 13 files (+4,071), `partner_tools/` 22 files
(+4,527), `.claude/` 2 files (+197). Every row below is drawn from a commit
message, a verification row, `PROMOTED/RECORD.md`, or `docs/crown/BUILDING.md`;
where the fork's record holds no measurement of a change's effect, the row says
**not yet measured** rather than claiming one.

**Which of this is in the compiler the station actually runs.** The promoted
binary `PROMOTED/stage3-046d6833/bin/zig` (ReleaseSafe, sha256 `046d6833…`) was
built from the tree at `b991cb16` on branch `patch/005-auto-hardware-threading`;
no `src/` or `lib/` file changed between that commit and the historical
`63effbe9` tip. The historical compiler rows below therefore describe that
promoted binary. **This does not include the new `d3347292c9` ready-index or
`0399d2b19b` logging correction:** their rebuilt candidates have bounded runtime
evidence but are not promoted code. The older unmeasured rows and V12 part-2
residual under group (c) also remain open. The practical result the maintainer
reports (2026-08-30, under that binary): a full build of the ≈1,800-module
workload that on stock 0.16.0 never completed — it died silently after more than
two hours, every time — now completes in under 45 minutes. That figure is a
station-side wall-clock reading, not a harness row, and it is not a speed claim
against any other configuration.

Row status: **PROMOTED** = in `stage3-046d6833`; **PROMOTED, ships OFF** = in the
binary but only behind an opt-in flag; **TOOLING** = Python/skills, not in the
binary; **DOCS**.

### Current source candidate — 2026-09-06

Commit `d3347292c9` adds an optional indexed heap for layered ready selection:
O(1) peeks and O(log n) repairs, current-map tie ordering, rank-epoch invalidation,
and original scan fallback on optional-allocation failure or transient ownership.
Insertion stays default; this does not parallelize Sema. Root independently
reran seven helper tests (4096 mixed transitions). The logging-fixed successor
at `0399d2b19b` has been rebuilt and exercised through 47 runner-accepted
incremental updates. An isolated observation build compared 10,678 indexed
choices with the original scan on the same live ready sets: all matched.
Real insertion/removal, epoch, abort/recovery, tier and cycle paths were reached.
Deliberately broken-hook controls, integration OOM and end-to-end performance
remain open; the shadow's extra scans are measurement overhead, not shipping
code. The reused runner's diagnostic-completeness limitations are explicit in
[the live-shadow receipt](docs/crown/READY_INDEX_LIVE_SHADOW_2026-09-06.md).

The incremental runner's completeness checks were then repaired: it now refuses
missing expected diagnostic tails and unchecked terminal outcomes. Three real
controls that the old runner incorrectly accepted each produce the intended
named failure in the repaired runner. A fresh repaired build then passed all
47 native update expectations plus three separate sema updates; the exact
coverage and remaining branches are in
[the runner receipt](docs/crown/INCREMENTAL_RUNNER_COMPLETENESS_2026-09-07.md#2026-09-07--actual-root-execution-addendum).
The live-shadow selection checker also has its own deliberate failure and
checksum-restored rebuild/run, documented in
[the self-control receipt](docs/crown/READY_INDEX_SELECTION_SELF_CONTROL_2026-09-07.md).
Neither result substitutes for the still-open lost-hook and integration-OOM controls.

Update 2026-09-07: the lost ordinary append hook now has its intended named
failure, exact source restoration, and a separately rebuilt successful rerun:
four expected updates, 2,095 same-state agreements and two active-growing puts.
See [the lost-append control](docs/crown/READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md).
Lost-update-invalidation, default-entry and integration-OOM controls remain open;
this is not promotion or performance evidence.

Further update 2026-09-07: the [lost-update-invalidation control](docs/crown/READY_INDEX_LOST_INVALIDATION_CONTROL_2026-09-07.md)
now fails at a retained memo count of 98 before second-update processing, then
passes all four outcomes after exact restoration and a separate rebuild, with
2,095 same-state agreements and populated memo reset checks at 98 and 3.
The short-circuited predicate does not separately negative-control each index
state. Default-entry and integration-OOM controls remain open; no speed or
promotion claim follows.

Further default-mode update 2026-09-07: the [default-entry control](docs/crown/READY_INDEX_DEFAULT_ENTRY_CONTROL_2026-09-07.md)
now has a named layered prepare-entry failure while explicit insertion and
omitted order each pass all three outcomes with four zero-capacity/memo exits
(including compiler_rt). Exact restoration and a separate rebuild pass layered
order with 2,083 same-state agreements. The earlier prepare panic masks the
append tripwire; integration OOM remains open, with no speed or promotion claim.

Superseding status 2026-09-07: the earlier open-status paragraphs remain as
history. The [first nodes-preparation-allocation control](docs/crown/READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md)
is now complete: 4/4 compiler builds and 5/5 intended runtime phase outcomes
(four successful runs and one expected named tripwire failure), followed through
exact clean restoration and recovery. The shipping candidate remains
uninstrumented. Broader OOM coverage, post-abort rearming and performance remain
unproved; this finite control does not establish foundation or release readiness.

The [release-cost packet](docs/crown/READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md)
is materialized locally, but 0/12 timed compiles have run. Three CPU-activity holds
prevented launch; neither is a failed timing sample. Package, companion evidence
bundle, online main synchronization, release and promotion remain open.

Superseding executed-cost status 2026-09-07: the earlier 0/12 note is retained
as history. The [executed cost receipt](docs/crown/READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
now records 12/12 successful compiles and 13 retained non-launch holds, without
retries or replacement samples. All three wall comparisons fall inside the
existing heuristic, but old/default wins 3/3 paired slots and the candidate's
median default RSS is +356 KiB. The clean-machine criterion remains
UNFULFILLED: these are ambient-workstation-qualified observations, not
performance equivalence or promotion clearance. Candidate packaging may be
staged and smoke-verified separately while unpromoted; package/evidence,
publication/main-sync, release and system-default gates remain open and
unexecuted in this packet. No foundation or crown stage is declared complete.

The same commit corrects status-tool promotion authority, diagnostic/sabotage
instructions and the documented ReleaseSafe build switches. The fresh candidate
build uses safety checks, debug extensions, logging and a baseline CPU target;
that target does **not** remove its system LLVM/runtime dependencies or prove
portability. The logging correction preserves mode defaults and filters debug
output by requested scope; matching/nonmatching/no-scope controls are documented
in [the candidate verification](docs/crown/LOG_FIXED_CANDIDATE_VERIFICATION_2026-09-06.md).
Neither a new package nor promotion is claimed here. See
[the source review](docs/crown/READY_INDEX_ROOT_REVIEW_2026-09-06.md) and
[the recipe controls](docs/crown/BUILD_RECIPE_CORRECTION_2026-09-06.md).

Superseding local packaging status 2026-09-07: the unchanged candidate package
is locally archived, extracted and smoke-verified, and its separate evidence
companion is now assembled with 20,218/20,218 members byte-verified. Root's
separate readback agrees at the shared-parser limits in the
[package and companion receipt](docs/crown/CANDIDATE_PACKAGE_VERIFICATION_2026-09-07.md).
The companion contains the earlier package-verification receipt, not this
later documentation successor; neither frozen archive was repacked. Later
observer implementation/integration remains outside those snapshots.
Publication, online main synchronization, release and default promotion remain
open; the clean-machine cost criterion is still UNFULFILLED. These local
packaging results do not establish performance equivalence or crown completion.

### (a) The frontend crash becomes a named refusal

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| InternPool: per-thread `Index` exhaustion is a named panic with remedy (thread, index reached, limit, split, `-j` remedy), not a silent SIGSEGV. Upstream's guard is an `assert`, compiled out of every ReleaseFast build. | `src/InternPool.zig` | `8a3b1f1f`, merged `a7f31c36` (patch/001) | PROMOTED | Fired live in production twice and printed the `u30 >> 4` ceiling to the digit; the ≈1,800-module workload then completed where every stock compiler died (exit 0, 18 min 10 s, 18.4 GiB peak — `a7f31c36`). Neutral reproducer in the commit: 37 s, 1.3 GiB, exit 134 on the safe build. |
| InternPool: `CaptureValue` widened from `packed struct(u32){tag: u2, idx: u30}` to two `u32` words, so `Index` goes 30 → 31 bits. Bit 31 is not taken: `Air.Inst.Ref` owns it, and that is refused by name in both files. | `src/InternPool.zig`, `src/Air.zig` | `8690a9c7` | PROMOTED | Per-partition ceiling at `tid_width = 4` goes 67,108,863 → 134,217,727 (the incident overflowed at 67,108,864). The dossier predicted 4×; the tree measured 2×, and the correction is recorded where the prediction was made. Also removes a latent `Nav.Index` truncation. H3 functional suite identical to the pre-widening control (3274/3426 steps, identical failure sets, 0 unique to this tree). |
| ThreadPlan: `index_bits` 30 → 31, so every ceiling the report line prints doubles with the encoding instead of advertising half the real headroom. | `src/ThreadPlan.zig` | `0e91a799` | PROMOTED | V1 GREEN 4/4 — the index width is *derived* from the compiler's own report as 31 bits, confirming `ThreadPlan.index_bits` and `InternPool.getIndexMask` agree end to end. |

### (b) Diagnostics that name the thing

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| Zcu: `file exists in modules 'a' and 'b'` names the double-owned file, not whichever importer happened to be scanned (`.file = res.file`, one field). Two test snapshots that had pinned the defect as expected output are tightened, not weakened; a fixture is added. | `src/Zcu.zig`, `src/Zcu/PerThread.zig`, `test/compile_errors.zig`, `test/incremental/change_module`, `test/fixtures/file_in_multiple_modules/` | `76a0b267` (patch/003) | PROMOTED | H2 GREEN 4/4 expected lines verbatim; H5 GREEN — the pre-fix compiler says `mod_b.zig:1:1`, the fixed one `dupe.zig:1:1` (the guard has been seen red). |
| `-femit-module-graph[=path]`: the compiler writes its resolved module graph as JSON (module identity, root paths, dependency edges, graph roots, per-module cache knobs) at the instant `module_roots` is complete and before any analysis. Flag-gated; folded into the cache hash so a warm-cache rerun cannot silently no-op; refuses by name when there is no Zcu. | `src/main.zig`, `src/Compilation.zig`, `src/Compilation/EmitModuleGraph.zig`, `src/dev.zig`, `lib/std/zig.zig` | `7ef21e28` | PROMOTED | Stock invocations byte-identical (additive; 0 deletions). Consumed by `ast-check --module-graph`. Effect on a real workload: **not yet measured** (parse- and type-check verified; adversarially reviewed, two correctness defects fixed before landing). |
| `--time-report-json <path>`: the same `--time-report` counters written once to a file after the update, with no `--listen` required; schema `cgm-zig.time-report.v1`, header only (per-decl payload and LLVM pass timings reported as counts). Refuses `--listen` by name instead of exiting 0 with no file. Transport only: no new counter, no new timer. | `src/main.zig` | `95cea4e2`, `abcd7bba` | PROMOTED | Made V4 measurable at all: `cpu_ns_link` is 11.2× `real_ns_link_flush`, so the linker ran beside analysis. Before this flag the only sink was a blocking web server. |
| The thread-plan report line is silent under `--listen` (`if (listen == .none) thread_plan.report()`), the test the compiler already made for `--time-report`. `zig build` and `jitCmd` keep theirs; they own the terminal. | `src/main.zig`, `src/ThreadPlan.zig` | `f52308a4` | PROMOTED | V-BR: a green `zig build` of a 13-step fixture went from 6 `^error:` lines + 6 `native failure` markers (first build) to 0 / 0 (reference 0 / 0). Under `--listen` the fork is now byte-identical to stock on both the artifact and the diagnostic stream. |

### (c) Threading and topology

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| `std.Thread.Topology`: physical cores and SMT siblings, every sibling set intersected with `sched_getaffinity` before it is counted. `physical` is `?usize` and `null` means unknown — never 1, never `logical / 2`; a partial probe is discarded whole. Linux via sysfs then `/proc/cpuinfo`; Darwin via `hw.physicalcpu` (read-verified only); everything else `.unknown`. | `lib/std/Thread/Topology.zig` (new), `lib/std/Thread.zig` | `7106d368` (patch/005a) | PROMOTED | V-S1a GREEN 7 of 7 masks match the sysfs oracle, including the `null` a mixed mask must produce; the same probe refuses to build against the reference compiler (control: it is fork-added). V14, the affinity-intersection sabotage control: **not yet measured** (patch prepared and `git apply --check` clean; the rebuild was not fired). cgroup CPU quota is named as invisible to this probe, not approximated. |
| ThreadPlan: the worker count is split from the InternPool partition count. `M_wide = -j<N> orelse logical`; `K = --intern-partitions orelse 1 << ceil_log2(max(physical orelse logical, 4)), capped by the representable partition count`. AstGen runs on the wide lane: `workerUpdateFile` holds a thread id only for its import-discovery tail, and `updateFile` / `lockAndClearFileCompileError` / `reportRetryableFileError` now take `*Zcu`, so the rule is enforced by signature. `--intern-partitions` reaches every sub-compilation's pool by default rather than through twelve forwarding sites. | `src/ThreadPlan.zig` (new), `src/main.zig`, `src/Compilation.zig`, `src/InternPool.zig`, `src/Sema.zig`, `src/Zcu.zig`, `src/Zcu/PerThread.zig` | `016d8987` (patch/005b) | PROMOTED | V2-EXP GREEN: `-j1` → workers 1, partitions 8, 268,435,455 items per partition — `-j` moves workers and leaves K alone. V5 GREEN: 1,200 files at `-j64`, rc=0, digest identical to `-j1`. On the 6c/12t reference host the derived K=8 gives 4.00× the incident's ceiling — derived from the constants; the reproduction on the ≈1,800-module workload (V7a/V7b) is **not yet measured** in the harness (blocked by charter). V13/V13-MM, the SMT payoff on the wide lane: INCONCLUSIVE — wall clock inside the noise floor; `real_ns_files` favours the wider lane by 23.6%, a note, not a claim. **Named residual (R12):** race freedom of the lane split is read- and type-verified only; ThreadSanitizer is unbuildable here (`linux/scc.h`), the Helgrind substitute was retracted for cross-build comparison, and the standing evidence is determinism — V12-P1A 1 distinct digest of 5 on the fan-out, identical to its own `-j1`; V12-P1B `.text` 1 of 5; an independent direct check 1 of 20 on both arms. |
| Edges-first ordering. Build runner: `--step-order=layered\|random\|declared` (default `layered`: depth ASC, fan-in DESC, name ASC over the ready set; `random` kept as the missing-edge fuzzer). Inside one compilation: `--analysis-order=insertion\|layered` — a priority over the ready set, never a change to the set, because eager leaf analysis would be language divergence. | `lib/compiler/build_runner.zig`, `src/Compilation/ModuleRanking.zig` (new), `src/Compilation.zig`, `src/Zcu.zig`, `src/Zcu/PerThread.zig`, `src/main.zig` | `2a9ca530` (patch/005c) | PROMOTED (step order); PROMOTED, ships OFF (`--analysis-order=layered`) | V10 GREEN: `layered` 3.567 s vs `random` 3.631 s vs `declared` 3.760 s over 13 steps — a weak green, inside the noise floor against `random`. V8 RED for the feature: `layered` analysis is +6.59% slower than `insertion` (3 of 3 paired slots), so it stayed off; the new optional index is now authored but has no end-to-end timing result yet. The default remains `insertion`. V9 GREEN: a cyclic module graph does not hang the ranker. |
| Rider 1: `Io.Threaded.concurrent_reserve` — `io.async` admission leaves a reserve so `io.concurrent` (the linker's slot) is not starved by bulk work. Default `0` makes both predicates byte-for-byte the stock arithmetic; the compiler sets 1 only when at least two async slots exist. | `lib/std/Io/Threaded.zig`, `src/main.zig` | `0711a34e` | PROMOTED | V4 GREEN (link ran beside analysis — above). V15 GREEN: 0 of 881 thread-samples parked in `Id.acquire`, with 4,472 Zig frames resolved as the instrument control, so the dossier's proposed admission gate was retired by measurement. V-S2a/V-S2b sabotage controls: **not yet measured** (the stale contexts were repaired and apply-check verified in the 2026-09-06 correction; sabotage rebuilds remain unrun). |
| Rider 2: `-j` reaches child compilers. `std.Build.Graph.child_jobs: ?u32` (null = stock), `Step.Compile` appends `-j<N>` when set; `zig build --child-jobs=keep\|share\|N`. The default shipped as `share` and reverted to `keep` when its own gate fired; `share` stays a selectable member. | `lib/compiler/build_runner.zig`, `lib/std/Build.zig`, `lib/std/Build/Step/Compile.zig` | `9a7cbab8`, `50a7b87f` | PROMOTED (default `keep`); `share` ships OFF | V-S4a GREEN: peak worker threads across a `-j4` build on an 8-CPU mask, `keep` 35 → `share` 10. V-S4b RED for `share`: +6.55% slower, 3 of 3 paired slots; peak process-tree RSS `share` 1,065,244 KB vs `keep` 1,104,468 KB. Caveat named in the code: a 13-step fixture of short compiles is the regime where the cure costs most; a large project could invert it. |
| ThreadPlan: a starved thread-id pool is impossible to derive (`min_derived_basis = 4`) and refused by name when an explicit `--intern-partitions` would leave 0 allocating lanes. This was the fork's own regression — the (K, M_wide) split made the state reachable — found by the harness and fixed inside the same run. | `src/ThreadPlan.zig`, `src/Zcu.zig`, `src/main.zig` | `3669ffc7` | PROMOTED | V16 GREEN, 0 hangs of 6 configurations: `build-obj hello.zig` with no flags on a 2-physical/4-logical mask went from rc=124 (hung, first build) to rc=0; `-j4 --intern-partitions=2` → refused, rc=1, with the remedy; `-j1 --intern-partitions=2` still rc=0 (the over-fire guard). |

### (d) Pre-compile tooling

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| `zig ast-check --module-graph=<path> file.zig`: after the normal check, validates the file's `@import` operands against a stage-0 module-graph JSON — relative `.zig`/`.zon` imports must exist on disk, named modules must appear as an import edge — and ends with one reconcilable summary (seen N: validated / exempt / skipped-unchecked). Malformed graph, stdin, or ZON mode is a named fatal. | `src/AstCheckImports.zig` (new), `src/main.zig` | `885fada0` | PROMOTED | Flagless `ast-check` byte-identical (additive; 0 deletions). Effect on a workload: **not yet measured** (parse-verified; three review defects fixed before landing, including a `.zon` false positive). |
| `zig ast-check f1.zig f2.zig …`: batch mode over N files, skips named per file, summary `R = C + F + S` always; `--json` emits one machine-readable document with per-file status and the import statistics above. Directory arguments refuse as `IsDir` by name. | `src/AstCheckBatch.zig` (new), `src/AstCheckImports.zig`, `src/main.zig` | `3d37ca1e` | PROMOTED | Single-file, no-`--json` path byte-identical to upstream. Batch memory flat: 400 files at 7.6 MB with a per-file arena, where the first draft grew ≈475 KB per file (the commit's own receipt). Beyond that: **not yet measured**. |

### (e) A one-word visibility fix on upstream code

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| `Compilation.resolveEmitPath` becomes `pub`. Upstream never marked it; `EmitModuleGraph.zig` calls it cross-file. It lives in the shared history as `e0bcdab2`. The old local-main cherry-pick `63778997` is preserved at `backup/main-before-sync-2026-09-06`; local main was reconciled to online `63effbe9` before the new candidate. It retires the day upstream marks it `pub`. | `src/Compilation.zig` | `e0bcdab2` | PROMOTED | `main` had not compiled since 2026-08-22 (`'resolveEmitPath' is not marked 'pub'`) and nobody met it because the promoted binary predated the break by sixteen minutes. After: type-check 0 errors, stage3 `ninja` exit 0. |

### (f) Documentation and partner tooling (not in the binary)

| Change | Where | Commits | Status | Observed effect |
|---|---|---|---|---|
| The fork's own record: provenance, the contribution contract, this front door. | `PROVENANCE.md`, `CONTRIBUTING-AI.md`, `README.md` | `7b77211c`, `5ec07fe0`, `cc383ab8`, `748540f8`, `1a0d5910`, `b018bcac`, `16f5299f` | DOCS | — |
| `docs/crown/`: the staged plan, seven design principles, a cited internals map, the build recipe with every gotcha and its negative control, the patch/005 dossier, its verification list, and two run records including the pre-committed promotion rule. | `docs/crown/*.md` | `4c76c861`, `5100c24f`, `a5f9e0b9`, `da0968c5`, `40a58902`, `44e391fb`, `9d86c443`, `24155d14`, `430d5077`, `5d3f2d5d`, `46763cb8`, `2d70958a`, `ed863a7d`, `178ba0a5`, `a0376dbd`, `573c55e3` | DOCS | `BUILDING.md`: a clean stage3 under an 8-CPU mask on a contended host is ≈41 min (the "8–9 min" figure is an idle unconstrained host); the `ZIG_LIBC` remedy is negative-controlled on the *unpatched* compiler (rc=1 → rc=0); ThreadSanitizer does not build here and a header shim is refused by name. |
| `partner_tools/`: status eyes, one-command reproductions, oracle helpers, a patch ledger derived from git history, and `helgrind_diff.py` — the named TSan substitute, with its noise floor measured before it was trusted. | `partner_tools/*.py`, `partner_tools/README.md`, `.gitignore` | `885fada0` (swept in), `f8a661cb`, `15b53145`, `efcbb899` | TOOLING | Helgrind's absolute count fails its own negative control (149,968 errors on the unpatched compiler for a trivial `build-obj -j2`); the difference-of-signatures instrument has a measured floor of 0–7 filtered contexts across 6 same-binary pairings — and was then retracted for cross-*build* comparison (≈276 "new" contexts of symbolic drift against a floor of 4). |
| `partner_tools/vharness/`: the verification harness — 38 self-registering rows (37 at its README's writing, plus V16), 7 generated fixtures, 4 reviewed sabotage patches, one driver emitting a markdown table and a JSON sidecar. No file holds a list of rows. | `partner_tools/vharness/**` | `4a963cbb`, `e8b8f7d1`, `18fc3f7e`, `d76d75ee`, `64befd76`, `3689fe3b`, `56771bec`, `2e591d15`, `b991cb16`, `a0376dbd` | TOOLING | Run 2 (2026-08-23, 8-CPU mask, contended): 20 GREEN · 4 RED · 9 UNKNOWN · 4 INCONCLUSIVE of 37 rows run; after three harness defects were fixed without relaxing a row and the desk's disposition, the final table in `PROMOTED/RECORD.md` reads 22 GREEN · 2 RED (both feature-comparison rows whose defaults already reverted, plus a pre-existing H3 identical to baseline) · 9 UNKNOWN · 4 INCONCLUSIVE. The harness found the V16 hang and the V-BR channel break; neither was a queued row. |
| Claude Code skills: the fork's working knowledge for AI partners, and a gated stub for the eventual stable-0.17 upgrade that refuses by name until upstream ships. | `.claude/skills/cgm-zig/`, `.claude/skills/cgm-zig-release-upgrade/` | `09adf385`, `f70dc33a` | TOOLING | — |

### What the fork does not change

The language: no syntax, semantics, or analysis-set change anywhere — edges-first is
a priority over what would be analysed anyway, never an addition to it. The
standard-library API surface, except the three additions named above
(`std.Thread.Topology`, `Io.Threaded.concurrent_reserve` with a stock-preserving
default of `0`, `std.Build.Graph.child_jobs` with a stock-preserving default of
`null`) and a five-line `lib/std/zig.zig` enum member for the new emit kind. Every
new compiler behaviour sits behind a new flag; a stock invocation behaves stock,
and where it does not (the report line under `--listen`) the record above shows
it was measured and fixed. The license: upstream's MIT `LICENSE` is preserved
unmodified and governs.

**Version policy.** 0.16.0 is the base and the patch target. 0.17 enters only after
upstream promotes it to stable; the 0.17-dev line was measured to fail on the
motivating workload from language churn alone before reaching the crash site.
Upstream Zig now lives at [codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig);
the GitHub mirror this fork was compared against is frozen at 2025-11-26
("README: migrated to codeberg"), and as of 2026-08-30 codeberg's newest tag is
0.16.0 — no 0.16.1, no 0.17 tag exists.

**Contribution stance.** This fork is not offered upstream, and nothing here is
filed there. Upstream's policy on AI-assisted contributions, and why it makes this
fork the lawful remaining channel, is described in [`PROVENANCE.md`](PROVENANCE.md).

## Provenance

Diagnosis and patches are the joint work of Daniel Campos Ramos and AI partners
including Anthropic Claude models via Claude Code and OpenAI Codex partners,
with GPT 6 Astra credited for the continuing orchestration and integration.
The original diagnosis and authorship remain credited to their contributors;
see [the full credit chain](PROVENANCE.md). Each patch commit carries its
evidence trail and its verification limits.

## For AI partners

This fork is deliberately AI-friendly — the inversion is the point. Start with
[`CONTRIBUTING-AI.md`](CONTRIBUTING-AI.md) (the contract: contributions are
judged by their receipts, never by their author's species), load the working
skill at [`.claude/skills/cgm-zig/`](.claude/skills/cgm-zig/SKILL.md) (laws,
doc map, proven workflows — repro runs, oracles, bisection, the safe-compiler
build recipe), and use the stdlib-only tooling in
[`partner_tools/`](partner_tools/README.md) — status eyes, one-command
reproductions, oracle helpers, and a patch ledger derived from git history
rather than hand-maintained. A gated skill for the eventual stable-0.17
upgrade sleeps at `.claude/skills/cgm-zig-release-upgrade/` and refuses by
name until upstream ships.

---

> *"Tenha fé, porque até no lixão nasce flor."* — Mano Brown, Racionais MC's, *Vida Loka Pt. 1*
> **"Have faith — because even in the lixão, a flower is born."**
> (*lixão*: the vast open-air garbage mountain — see the translator's note in [`PROVENANCE.md`](PROVENANCE.md))

## Published candidate status — 2026-09-07

The earlier publication-open statements are preserved as history. Root published
the [unpromoted prerelease `0.16.0+cgm.0399d2b19b`](https://github.com/danielcamposramos/cgm-zig/releases/tag/0.16.0%2Bcgm.0399d2b19b)
at 14:18:54 UTC with the two frozen archives and `SHA256SUMS`: its recorded API
verification matches 3/3 asset names, sizes and digests, not downloaded bytes.
The [publication successor](docs/crown/CANDIDATE_RELEASE_2026-09-07.md#2026-09-07--executed-prerelease-publication)
records tag `767784fec9` and online main `cf28537cb4` at that observation.
Stable `0.16.0+cgm.046d6833` remains latest; `PROMOTED/zig` still selects
`stage3-046d6833`. Clean-machine cost acceptance and default promotion remain
UNFULFILLED. Neither stopped cost series resumed, and neither frozen archive
contains the later observer/stopped-series evidence or these successor notes.
Publication establishes no speedup, performance equivalence or Crown completion.
