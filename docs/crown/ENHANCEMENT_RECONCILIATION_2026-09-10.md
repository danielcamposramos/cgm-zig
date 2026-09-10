# Enhancement reconciliation — every requested enhancement against the actual bodies

*Authored 2026-09-10 by the Opus compiler partner (Anthropic Claude, via Claude
Code) at Daniel Campos Ramos's direction. This is an audit, not an announcement:
it claims nothing that a named receipt does not already carry, and it says "not
yet measured" wherever the record holds nothing.*

The request being reconciled is the whole set, not a subset: **"ALL requested
enhancements: not just syntax checks or topology defaults, but hyper-modular
compilation behavior, debug sharing and multitasking improvements."** In the
roadmap's terms that is stage 0, stage 0.5's four rungs, stage 1, stage 2a, 2b,
2c, 2d and the multitasking line. Each is a row below.

## How to read the columns

No row is "done" because of a promotion, a README line, or a documentation note.
The columns are cumulative and each has a single, checkable meaning:

| Column | Means | Does NOT mean |
|---|---|---|
| **DECLARED** | Named as a requested enhancement in `PLAN.md`, the README, or Daniel's own ask. | That any code exists. |
| **AUTHORED** | Source bodies exist in the working tree at `289ff31b24`(dirty), cited `file:line`. | That anything calls them. |
| **CONNECTED** | Reachable from a real entry point — a parsed flag or a call site on a live path, cited. | That it was ever built. |
| **COMPILED** | Present in a **named binary with its sha256**. A source edit that has never been through a producer command is NOT compiled, whatever `ast-check` says. | That it ever ran. |
| **EXERCISED** | A recorded run drove it and produced output that was read. | That the output was checked against a guard that can fail. |
| **PROVEN** | A control was **seen red**, restored, and **seen green on a rebuilt binary** — doctrine principle 5. | Anything about performance, size, or promotion. |

### Binary keys used in the COMPILED column

| Key | Path | sha256 (first 20) | Source |
|---|---|---|---|
| **P046** | `PROMOTED/stage3-046d6833/bin/zig` | `046d6833e17c32856223` | `b991cb16` |
| **P-D6** | `PROMOTED/stage3-d6b4168f/bin/zig` — today's station default | `d6b4168f368b95e83d2a` | `0399d2b19b` |
| **I-C6** | `/K3D/CGM_Forge.local/crown_sig_2026_09_08/cmakebuild/stage3/bin/zig` | `c6db06a078b5a7702a1b` | dirty tree, 2026-09-08 17:42 |
| **none** | in no built binary | — | — |

`git diff --stat 0399d2b19b HEAD -- src/ lib/` is **empty**: every committed
compiler change at HEAD is inside **P-D6**. The five dirty owners are not.

---

## The ledger

### Group A — pre-compile tooling (stage 0.5, four rungs)

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| A1 | **Import-aware `ast-check`** (rung 1) | yes — PLAN §0.5.1 | yes — `src/AstCheckImports.zig:120` `checkAgainstGraph` | yes — `src/main.zig:6573` parses `--module-graph=` | **P046, P-D6** | yes — parse-verified; flagless path byte-identical | **no** | README row `885fada0`. Three review defects fixed pre-landing, including a `.zon` false positive. Effect on a workload: **not yet measured**. No red→green control on record. |
| A2 | **Decl-existence pass ("sema-lite")** (rung 2) | yes — PLAN §0.5.2 | **no** | no | **none** | no | no | Grep for `sema-lite｜sema_lite｜decl-existence｜decl_existence` over `src/` returns **0 hits**. This rung is the "missing middle" the plan names and it does not exist. |
| A3 | **Batch mode, honest denominators** (rung 3) | yes — PLAN §0.5.3 | yes — `src/AstCheckBatch.zig:150` `run` | yes — `src/main.zig` batch dispatch; `--json` | **P046, P-D6** | yes — 400 files at 7.6 MB with a per-file arena | **no** | README row `3d37ca1e`. `R = C + F + S` always; `IsDir` refused by name. Beyond the arena figure: **not yet measured**. |
| A4 | **Check-as-module** (rung 4) | yes — PLAN §0.5.4 | **no** | no | **none** | no | no | `src/AstCheckImports.zig:27` names it in a comment as *not* knowable there ("rung 4, `check-as-module`"). No body anywhere. |

### Group B — module-graph observability (stage 0) and the internals map (stage 1)

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| B1 | **`-femit-module-graph[=path]`** | yes — PLAN stage 0 | yes — `src/Compilation/EmitModuleGraph.zig:91` `buildJson`, `:148` `worker` | yes — `src/main.zig:1659` parses the flag; folded into the cache hash | **P046, P-D6** | yes — emitted JSON parsed; consumed by A1 | **no** | README row `7ef21e28`. Stock invocations byte-identical (additive, 0 deletions). Refuses by name with no Zcu. Effect on a workload: **not yet measured**. |
| B2 | **Internals map** (stage 1) | yes — PLAN stage 1 | n/a — documentation | n/a | n/a | n/a | n/a | `docs/crown/INTERNALS_MAP.md`. PLAN marks it **done**; it is a cited map, and this ledger does not upgrade a document into a capability. |

### Group C — multitasking / auto-hardware threading

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| C1 | **`std.Thread.Topology`** — physical cores + SMT siblings, every set intersected with `sched_getaffinity`; `physical: ?usize`, `null` = unknown | yes | yes — `lib/std/Thread/Topology.zig:139` `detect` | yes — `lib/std/Thread.zig` re-export; consumed by C2 | **P046, P-D6** | yes — 7 masks | **partial** | **V-S1a GREEN 7/7** masks match the sysfs oracle, including the `null` a mixed mask must produce; the probe refuses to build against the reference compiler (control: fork-added). **V14, the affinity-intersection sabotage control, is UNKNOWN** — patch `partner_tools/vharness/sabotage/V14_affinity_intersection.patch` is `git apply --check` clean and **was never fired**. Darwin arm: read-verified only. |
| C2 | **ThreadPlan (K, M_wide) split** — `M_wide = -j<N> orelse logical`; `K = --intern-partitions orelse 1<<ceil_log2(max(physical orelse logical,4))`; AstGen on the wide lane | yes | yes — `src/ThreadPlan.zig:285` `derive` | yes — `src/main.zig`, `src/Compilation.zig`, signature-enforced (`*Zcu` params) | **P046, P-D6** | yes | **partial** | **V2-EXP GREEN** (`-j1` → workers 1, partitions 8, 268,435,455/partition — `-j` moves workers, leaves K alone). **V5 GREEN** (1,200 files at `-j64`, rc=0, digest identical to `-j1`). **V7a/V7b, the reproduction on the ~1,800-module workload, UNKNOWN** — never run. **R12 named residual:** race freedom is read- and type-verified only; ThreadSanitizer is unbuildable here (`linux/scc.h`); the standing evidence is determinism, not freedom from races. |
| C3 | **`--intern-partitions` reaches every sub-compilation** | yes | yes — `src/ThreadPlan.zig`, `src/InternPool.zig` | yes — `src/main.zig:477` | **P046, P-D6** | yes | **no** | Covered by C2's greens. **V3, its own sabotage control (`V3_intern_partitions_invariant.patch`), is UNKNOWN** — prepared, never fired. |
| C4 | **Edges-first step ordering** — `--step-order=layered｜random｜declared` | yes | yes — `lib/compiler/build_runner.zig:303` | yes — default `layered` | **P046, P-D6** | yes — 13-step fixture | **no** | **V10 GREEN but weak:** `layered` 3.567 s vs `random` 3.631 s vs `declared` 3.760 s — inside the noise floor against `random`. **V9 GREEN**: a cyclic module graph does not hang the ranker. |
| C5 | **`--analysis-order=layered` + the ready-set index** | yes | yes — `src/Compilation/ModuleRanking.zig:92`; `src/Zcu/ReadyIndex.zig`; `src/Zcu.zig:314` | yes — but **gated**: `src/Zcu.zig:3359` returns early unless `analysis_order == .layered`; **default is `.insertion`** (`src/Zcu.zig:133`) | **P-D6** (index); P046 has the ordering, not the index | yes — 10,678 index/scan agreements on the same live ready sets; 47 runner-accepted incremental updates | **yes, for four bounded controls** | **Ships OFF and stays off by measurement: V8 RED for the feature** — `layered` analysis is +6.59% slower than `insertion`, 3 of 3 paired slots. Four controls went red→green on separately rebuilt binaries: [lost append](READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md), [lost-update invalidation](READY_INDEX_LOST_INVALIDATION_CONTROL_2026-09-07.md), [default entry](READY_INDEX_DEFAULT_ENTRY_CONTROL_2026-09-07.md), [prepare OOM](READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md) (4/4 builds, 5/5 phase outcomes). **Integration OOM and end-to-end speedup remain open.** |
| C6 | **`Io.Threaded.concurrent_reserve`** — `io.async` admission leaves a reserve so the linker's `io.concurrent` slot is not starved | yes | yes — `lib/std/Io/Threaded.zig:51`+ | yes — `src/main.zig` sets 1 only when ≥2 async slots exist; default `0` is byte-for-byte stock arithmetic | **P046, P-D6** | yes | **no** | **V4 GREEN** — link ran beside analysis (`cpu_ns_link` = 11.2× `real_ns_link_flush`). **V15 GREEN** — 0 of 881 thread-samples parked in `Id.acquire`, with 4,472 Zig frames resolved as the instrument control; this retired the dossier's proposed admission gate by measurement. **V-S2a and V-S2b, both sabotage controls, are UNKNOWN** — patches prepared and apply-check clean, rebuilds never fired. |
| C7 | **`-j` reaches child compilers** — `--child-jobs=keep｜share｜N` | yes | yes — `lib/compiler/build_runner.zig:292`, `lib/std/Build.zig`, `Build/Step/Compile.zig` | yes | **P046, P-D6** | yes | **no** | **V-S4a GREEN**: peak worker threads across a `-j4` build on an 8-CPU mask, `keep` 35 → `share` 10. **V-S4b RED for `share`**: +6.55% slower, 3 of 3 paired slots ⇒ the default reverted to `keep`; `share` stays selectable. Caveat named in-code: a 13-step fixture of short compiles is the regime where the cure costs most. |
| C8 | **Starved thread-id pool refused by name** (`min_derived_basis = 4`) | yes | yes — `src/ThreadPlan.zig:209`, `:381` `starvedLanes` | yes — `src/main.zig`, `src/Zcu.zig` | **P046, P-D6** | yes | **yes** | **V16 GREEN, 0 hangs of 6 configurations.** The guard was seen red: `build-obj hello.zig` with no flags on a 2-physical/4-logical mask went **rc=124 (hung)** on the first build → **rc=0** after the fix; `-j4 --intern-partitions=2` → refused, rc=1, with the remedy; `-j1 --intern-partitions=2` still rc=0 (the over-fire guard). This was the fork's own regression, found by the harness and fixed inside the same run. |

### Group D — the crash the fork exists to fix

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| D1 | **InternPool per-thread `Index` exhaustion is a named panic with remedy** | yes | yes — `src/InternPool.zig` | yes | **P046, P-D6** | yes — **fired live in production twice** | **yes** | Printed the `u30 >> 4` ceiling to the digit. The ~1,800-module workload then completed where every stock compiler died: exit 0, 18 min 10 s, 18.4 GiB peak (`a7f31c36`). Neutral reproducer in the commit: 37 s, 1.3 GiB, exit 134 on the safe build. Upstream's guard is an `assert`, compiled out of every ReleaseFast build. |
| D2 | **`CaptureValue` widened → `Index` 30 → 31 bits** | yes | yes — `src/InternPool.zig`, `src/Air.zig` | yes | **P046, P-D6** | yes | **yes** | Per-partition ceiling at `tid_width = 4`: 67,108,863 → 134,217,727 (the incident overflowed at 67,108,864). **The dossier predicted 4×; the tree measured 2×, and the correction is recorded where the prediction was made.** H3 functional suite identical to the pre-widening control (3274/3426 steps, identical failure sets, 0 unique to this tree). Bit 31 is refused by name in both files (`Air.Inst.Ref` owns it). |
| D3 | **Double-owned file names the file, not the importer** | yes | yes — `src/Zcu.zig`, `src/Zcu/PerThread.zig` | yes | **P046, P-D6** | yes | **yes** | **H2 GREEN 4/4** expected lines verbatim. **H5 GREEN — the guard was seen red:** the pre-fix compiler says `mod_b.zig:1:1`, the fixed one `dupe.zig:1:1`. Two test snapshots that had pinned the defect as expected output were tightened, not weakened. |

### Group E — observability transport

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| E1 | **`--time-report-json <path>`** | yes | yes — `src/main.zig:540` | yes — refuses `--listen` by name | **P046, P-D6** | yes | **no** | Transport only: no new counter, no new timer. **It made V4 measurable at all** — before this flag the only sink was a blocking web server. |
| E2 | **Thread-plan report silent under `--listen`** | yes | yes — `src/main.zig`, `src/ThreadPlan.zig:412` | yes | **P046, P-D6** | yes | **yes** | **V-BR GREEN — seen red first:** a green `zig build` of a 13-step fixture went from 6 `^error:` lines + 6 `native failure` markers to **0 / 0** (reference 0 / 0). Under `--listen` the fork is byte-identical to stock on both the artifact and the diagnostic stream. The harness found this; it was not a queued row. |

### Group F — hyper-modular compilation behavior (stage 2c) and residency (stage 2d)

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| F1 | **Content-addressed per-module artifact cache** (stage 2c — "the crown") | yes — PLAN stage 2c | **no** | no | **none** | no | no | Grep for `module-artifact｜module_artifact｜ModuleArtifact｜per-module cache` over `src/` returns **0 hits**. The plan's own dependency rule blocks it: it comes after 2a, and 2a does not exist either (H1). |
| F2 | **Residency-bounded tiles** (stage 2d) | yes — PLAN stage 2d | **no** | no | **none** | no | no | Grep for `residency｜tile_budget｜TileBudget｜evict` over `src/` returns only `ThreadPlan.zig:42` (a comment saying it does **not** derive a residency guard), the SPIR-V spec's `sparse_residency` enum, and `Package/Fetch/git.zig`'s unrelated object-cache LRU. No scheduler, no eviction, no budget. |

### Group G — debug sharing (stage 2b) and its opening (stage 2a identity)

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| G1 | **One shared debug artifact across a build sweep** — DWARF dedup-by-reference (stage 2b; *this is the enhancement Daniel actually asked for*) | yes — PLAN stage 2b | **no** | no | **none** | no | no | **NOT IMPLEMENTED.** The 2026-09-08 scope correction at the top of `PLAN.md` is binding and this ledger re-affirms it. The blocker is cited in `CROSS_PROCESS_SIGNATURE.md`: unit indices are asserted lockstep across five sections (`src/link/Dwarf.zig:2538-2555`) and the `.debug_info` header writer hardcodes `DW.UT.compile` (`:4866`). Decoupling the per-section unit index spaces is a refactor, not a packet-sized edit. |
| G2 | **Intra-emitter qualifier-DIE sharing** (`const_type` entries shared per unit/target/kind) | yes — a sub-part of 2b | yes — `src/link/Dwarf.zig` `getQualifiedEntry` (dirty, preserved) | yes — three former inline sites now reference the shared entry | **I-C6** (the `const signature collision` string is present in that binary) — **not in P-D6** | yes | **yes** | **520 duplicate DIEs removed, 7,723 bytes = 0.35%** on the two-module scale probe. `llvm-dwarfdump --verify`: 120 errors before, 120 after, **error sets identical** (pre-existing). All 2,515 distinct named type descriptions present before and after. `gdb` reads the qualifier correctly through the shared DIE. **Negative control seen red:** bypassing the shared entry in `finishForwardToConst` **aborts** the compiler — `index out of bounds: index 40, len 19` at `src/link/Elf/ZigObject.zig:633`; restored and verified with `sha256sum -c`. **Standing limit, restated: this has NO effect on the consuming project's build** — that build goes through LLVM + LLD, not `src/link/Dwarf.zig` (`CGM_ACTUAL_BACKEND.md`). |
| G3 | **Cross-process constant-type signature** | yes — a primitive for 2b | yes — `src/link/ConstPool.zig` (dirty, preserved) | yes — `--debug-log const_pool` on a `-Dlog` build | **I-C6** | yes — oracle **5/5**, shared signature `0xd0a652b0234af326` derived by two separate processes | **yes** | Element-width/length and target controls proven distinct. **Collision refusal proven red then green:** the layout-only draft fired in production — `const signature collision: 0x49823ab0dc97fa51 claimed by types 10 and 16` (`u64_type` vs `usize_type`) — and the key-based fix silences it. **Absent and refused by name:** pointers, sentinel arrays, containers, functions, error sets. **Emission is byte-identical** — the signature changes what the compiler knows, not what it writes; no reduction is claimed for it. |
| G4 | **Whole-compilation debug identity** — real `DW_AT_GNU_dwo_id` fed from `Builder.dwo_id` (stage 2a's opening) | yes | yes — `src/codegen/llvm.zig:789` `debugContentIdentity`; `lib/std/zig/llvm/Builder.zig:24` `dwo_id`; `lib/std/zig/llvm/ir.zig:1657` (frozen literal → real operand) | yes — `src/codegen/llvm.zig:911`, after `flushTypePool` and both `resolveDebugForwardReference` calls | **I-C6** — **but the five `cgm-dwoid` trace sites are NOT** (`strings … | grep -c cgm-dwoid` = **0** on that binary) | yes | **partial — see the gap** | **PASSED on I-C6:** repeated ReleaseSafe equality, consumer 1 `0x42ccd13bb162ca8e` ×3 and consumer 2 `0x61d78abd44beec1f` ×3. ABI (gnu→musl), arch (x86_64→aarch64), optimize (ReleaseSafe→ReleaseFast) and content (non-root module `scale_modb.zig`) all **DISTINCT**, and **restore returns to baseline** — that is a red→green content control. `gdb` lines/types/locals read on both consumers. `DW_AT_GNU_dwo_name` count = **0** in all six artifacts; `find -name '*.dwo'` = 0 — nothing points at an absent split file. **THE GAP: numeric completeness of the admitted input set is NOT proven.** Establishing it requires the trace sites to be in a rebuilt binary, and they are in no binary. The hard-coded "expect 299" is **withdrawn**; the expected set must be derived from the fold and compared as two set differences. |
| G5 | **`.dwo` emit stream / split-DWARF packaging** | yes — the mechanism 2b would reference | **no** | no | **none** | no | no | A grep over `src/` for `split_dwarf｜SplitDwarf｜gsplit-dwarf｜.dwo｜dwo_name｜DwoId｜debuglink｜separate.debug` returns **0 hits** (only unrelated `.dword` operand names). Declared debug options are `-fstrip`, `-gdwarf32`, `-gdwarf64` (`src/main.zig:1689-1695`); `EmitOptions` (`src/codegen/llvm/bindings.zig:88`) has **no** split-debug member. `splitDebugFilename` was deliberately **not** set: an `llc-21` probe measured that setting it emits `DW_AT_GNU_dwo_name("a.dwo")` with **no** `.dwo` sections — a dangling reference, exactly the debugger breakage this must not introduce. |

### Group H — analysis-reuse ledger (stage 2a)

| # | Enhancement | DECLARED | AUTHORED | CONNECTED | COMPILED | EXERCISED | PROVEN | Receipt / gap |
|---|---|---|---|---|---|---|---|---|
| H1 | **Per-module attribution of analysis work** — units analyzed, ZIR→AIR lowering, comptime evaluations, with the context-free/context-sensitive split *measured, not asserted* | yes — PLAN stage 2a | **no** | no | **none** | no | no | Grep for `analysis-reuse｜analysis_reuse｜per-module totals｜context_free｜context-free` over `src/` returns **0 hits**. G4's identity is stage 2a's *opening* — a whole-compilation value — not the per-module ledger the stage names. Stage 2c (F1) is blocked behind this. |

---

## What the ledger shows, stated plainly

**Fully proven (a control was seen red and came back green on a rebuilt binary):
C8, D1, D2, D3, E2, G2, G3.** Seven rows. Every one of them is a robustness,
correctness or intra-emitter result — none of them is the requested
debug-sharing, hyper-modular-cache or residency behaviour.

**Compiled and exercised but never negative-controlled: A1, A3, B1, C1, C3, C4,
C6, C7, E1.** Nine rows. Four prepared sabotage patches — **V3, V14, V-S2a,
V-S2b** — are `git apply --check` clean and have **never been fired**. Under
doctrine principle 5 a guard that has never fired is a hope, not a guard; these
four are the cheapest outstanding proof debt in the repository.

**Ships OFF by its own measurement: C5** (`--analysis-order=layered`, V8 RED at
+6.59%). The ready index has four genuine red→green controls, and it is still
switched off because the feature it accelerates is slower than the default.

**Authored, never compiled: the five `cgm-dwoid` trace sites** in
`src/codegen/llvm.zig`. `ast-check` exit 0 is AstGen only — it proves syntax, not
that a `log.debug` format string matches its argument types. That is the single
largest risk in the current dirty tree and it is discharged only by a rebuild.

**Not authored at all: A2, A4, F1, F2, G1, G5, H1.** Seven rows — and they
include **the enhancement Daniel actually asked for.** Stage 2b (G1) is not
implemented; stage 2c (F1) and 2d (F2) are not implemented; stage 2a's ledger
(H1) is not implemented; two of stage 0.5's four rungs are not implemented.

**A 64-bit identity is a reuse CANDIDATE. It is not shared debug bodies, not
size reduction, not `.dwo` emission.** G4 is real and measured; it is the key a
sharing mechanism would use, and the sharing mechanism does not exist.

## Corrections of record this audit makes

1. **`CGM_ACTUAL_BACKEND.md`'s RESIDUAL section is stale and must not be read
   forward.** It states repeated-build equality "holds at Debug, NOT at
   ReleaseSafe" and reports a bisect concluding `debug_file_map` membership is
   nondeterministic. Both are **void**: the Debug figure `0xf972a57cf4b15d23`
   was `compiler_rt`'s identity, not the program's (Debug uses the self-hosted
   backend, which sets no `dwo_id` — so Debug is not a valid axis for this
   mechanism at all), and the bisect ran on a **stale binary**: only the first
   cmake build ever regenerated stage3. ReleaseSafe equality **passes** on
   `I-C6`. The document is preserved unedited as history in this packet and is
   corrected here; the edit belongs in the same commit as the G4 completeness
   work, not before it.
2. **Two comments in `debugContentIdentity` cite those voided numbers**
   (`src/codegen/llvm.zig:800-807` "ordering by that index gave ONE program two
   DIFFERENT identities"; `:832-837` "293 files both runs … Debug was stable
   3/3"). They are in the dirty tree and must be corrected — packet 2, item 7.
3. **`CROSS_PROCESS_SIGNATURE.md` names the instrumented compiler as
   `0.16.0+cgm.289ff31b24-crownsig`.** `I-C6` reports `0.16.0` — it was built
   with `-Dversion-string=0.16.0`. Those are two different builds; the
   emission-identical table in that document was measured against the earlier
   one, not against `I-C6`. Neither result is withdrawn; the binary attribution
   is.
4. **The 2026-08-23 V-table was run against `P046`, not `P-D6`.** No V row has
   been re-run against today's station default. The rows remain valid evidence
   for the code they exercised — `git diff 0399d2b19b HEAD -- src/ lib/` is
   empty, and the `b991cb16 → 0399d2b19b` range added the ready index — but
   "GREEN on the promoted binary" is only literally true of `P046`.

## What this ledger does not claim

No performance result, no size reduction, no promotion clearance, no release
readiness, no crown-stage completion. Population counts here are dated
measurements, not acceptance laws. The clean-machine cost criterion remains
UNFULFILLED and is not waived by anything above.
