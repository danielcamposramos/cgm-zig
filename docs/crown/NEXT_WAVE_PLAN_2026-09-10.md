# Next enhancement wave — the challenged plan

*Round-two return, 2026-09-10, by the Opus compiler partner. This CHALLENGES
`NEXT_WAVE_CANDIDATES_2026-09-10.md` card by card against the actual bodies
(`ENHANCEMENT_RECONCILIATION_2026-09-10.md`), against what the memo says upstream
0.17 is doing, and against the patch-layer contract in its §2. It does not extend
the memo. Cards are kept, struck or reshaped with the reason that decided them,
and a card struck here can be re-argued with a measurement.*

## 0. What was actually checked, and how

Every verdict below rests on one of three things, never on preference:

| Check | Command / anchor | Result |
|---|---|---|
| Is the card's deliverable already in the tree? | the reconciliation ledger's AUTHORED column | see per-card rows |
| Is the mechanism's tooling available here? | `which dwz` · `which quilt` | dwz **0.17 present** · quilt present but **unused** |
| Is the seam the card assumes real? | greps cited per card | three card premises failed |

Three premises in the memo did not survive contact with the tree, and they change
the plan rather than decorate it:

1. **`--icf` is not reachable through this compiler.** `zig build-exe --help`
   offers `--gc-sections` / `--no-gc-sections` and **no** `--icf`; a grep over
   `src/link/Elf.zig`, `src/link.zig` and `src/main.zig` finds only
   `--print-icf-sections` (`src/main.zig:2705`), a *diagnostic*, with no `--icf=`
   parsing anywhere. C10's "nothing to patch in LLD" is true of LLD and false of
   the driver: enabling ICF needs a fork patch, so it is not the free measurement
   the card implies.
2. **The repository does not use quilt and has no patch directory.** `quilt` is
   installed, but there is no `patches/`, no `debian/`, no `.pc/`. The fork's
   patch layer is git branches (`patch/001`, `patch/003`, `patch/005a`–`005c`).
   §2's "the primary output IS the patch series; the git history is the record of
   it" inverts what this fork actually is.
3. **`src/cgm/` does not exist.** Every fork-added compiler file lives in
   upstream's own topology: `src/ThreadPlan.zig`, `src/AstCheckImports.zig`,
   `src/AstCheckBatch.zig`, `src/Compilation/EmitModuleGraph.zig`,
   `src/Compilation/ModuleRanking.zig`, `src/Zcu/ReadyIndex.zig`.

And one correction of attribution: **C9 credits upstream with the fork's own
work.** "0.17: upstream's import-aware AstGen already landed (README)" — the
README row it points at is `885fada0`, `src/AstCheckImports.zig`, a **fork**
file, PROMOTED in this fork. Upstream did not land it. C9 also lists batch mode
as something to build; batch mode is **already PROMOTED** (`3d37ca1e`,
`src/AstCheckBatch.zig:150`, ledger row A3).

A fourth finding, and it is about this repository's own record rather than the
memo: **the fork's two primary records disagree on two published figures.** V8's
magnitude is +6.59% in the README and +11.92% in `PROMOTED/RECORD.md:143`; V15's
parked-sample figure is "0 of 881" in the README and "0.16% of ~1,254" in
`PROMOTED/RECORD.md:147`. Both rows keep their sign and their disposition in both
documents, so no verdict here turns on them, but a number that appears twice with
two values is a drift with a delay fuse and neither should be quoted again until
one is re-derived. Recorded, not resolved.

I could not verify the 0.17 milestone item numbers (#36387, #36388, #36389,
#36403, #36513, #36651, #36665) or the milestone's host: the memo cites
`codeberg.org/ziglang/zig/milestone/69474` for the milestone but
`github.com/ziglang/zig/issues/24658` for `--time-report`. **Mixed hosts, not
reconciled here.** Every verdict below is therefore independent of those numbers;
where a card's fate would turn on an upstream item, I say so instead of assuming.

---

## 1. Verdicts

| Card | Verdict | The reason that decided it |
|---|---|---|
| **C1** metadata-first interface artifacts | **STRIKE as a card · FOLD into 2c** | It is not a route around the blocker, it **is** the blocker. `PLAN.md`'s stage-1 risk names it: "the intern pool is global … 'per-module artifact' requires a serialization boundary the pool does not naturally offer. This is the hardest open question and we say so." An interface artifact of "exported decls + comptime-visible bodies" is exactly that boundary. Worse, the rmeta analogy does not carry into Zig: in Rust the metadata boundary is defined and generics are the only cross-crate laziness, whereas here **any `pub fn` may be comptime-called by an importer**, so "everything a dependent needs" has no bound short of the whole module. `PLAN.md` already states the honest version of this as the context-free/context-sensitive split. Keep that framing; drop the separate card. |
| **C2** red-green re-verification | **KEEP as a REQUIREMENT of 2c, not a packet** | It restates `PLAN.md` constraint 3 ("Correctness never rests on the cache … A verification mode recomputes and compares") in rustc's vocabulary. That is useful — `try_mark_green`'s walk is a better implementation shape than a blind full recompute — but it has nothing to verify until 2c stores something. No independent packet, no independent measurement. |
| **C3** partition to a probed budget | **RESHAPE: strike the in-compiler half, keep an offline partitioner as TOOLING** | The in-compiler half is stage 2d, and `PLAN.md` puts 2d after 2c because a tile scheduler with no artifact store can only **order**, not bound residency. Ordering already exists and already measured **RED**: `--analysis-order=layered` is slower than `insertion` with 3 of 3 paired-slot separation (V8), which is why it ships OFF. **The magnitude is not agreed inside this repository** — the README row says **+6.59%**, `PROMOTED/RECORD.md:143` says **+11.92%** — and this plan does not pick between them; see §0's finding. Either way the sign is RED, and re-deriving an order under a memory name would repeat a measured loss. What survives is genuinely cheap and genuinely useful: a partitioner run **offline over stage 0's emitted graph** that reports cross-tile import counts for a given tile size. That produces the number 2d needs before 2d is designed, needs no compiler change, and can be struck if the number is bad. |
| **C4** resident compiler serving many units | **KEEP · demote behind 2c · re-seam** | The workload is real and observable: the estate's own product test run on this station is `zig build test -Doptimize=ReleaseSafe -j1 --child-jobs=2` over many per-module test units sharing one closure. But "One new entry point" is wrong — the seam exists. `--listen` appears **37 times** in `src/main.zig`, and the fork already interacts with it in two shipped rows (`--time-report-json` refuses `--listen` by name; the thread-plan report is silent under it). The blocker is C1's blocker again: keeping a pool warm **across units** needs the serialization boundary the pool does not offer, and this fork's own `InternPool` work shows the pool is thread-partitioned and compilation-scoped. Not a packet until 2c's key exists. |
| **C5** content-addressed action cache | **KEEP the manifest-shape refinement · STRIKE the shared/remote store** | The refinement is a real upgrade over `PLAN.md`'s stated key and should be adopted: PLAN keys on *transitive-import content hashes*, which **over-approximates** — any change anywhere in the closure misses the entry even when the module never read the changed file. ccache's direct mode records the files **actually read** and hits only when all still match. That is strictly more hits at equal safety, and it composes with C2's verification. The shared/remote store is struck for now: it adds a network trust boundary to a cache whose governing doctrine is that correctness never rests on it, with no measurement yet arguing for it. |
| **C6** debug bodies emitted once and referenced | **KEEP — this is the requested enhancement — but re-order its arms by measured evidence, and name the packet the memo omits** | See §2 below. This is the card the maintainer actually asked for and the one the memo gets least right. |
| **C7** per-module analysis ledger | **KEEP · PROMOTE TO PACKET 1** | The only card that is (i) genuinely absent — ledger row H1, grep for `analysis-reuse｜context_free｜per-module totals` over `src/` returns **0 hits**; (ii) `PLAN.md`'s own named dependency for 2c ("you must not claim savings you have not measured (2a) before building the machinery that banks them"); (iii) read-only accounting, the smallest divergence cost in the wave; and (iv) already has its transport shipped — `--time-report-json` is PROMOTED (`95cea4e2`, `abcd7bba`) and was the flag that made V4 measurable at all. Nothing else in the wave is this cheap or this load-bearing. |
| **C8** resource-aware job admission | **KEEP · demote behind C7 · must answer V15 first** | The probe-and-refuse half already exists and is proven: ThreadPlan derives from `std.Thread.Topology`, and a starved thread-id pool is refused by name with V16 GREEN (0 hangs of 6 configurations, rc=124 → rc=0). The new half is per-unit-RSS admission, which cannot exist before C7 measures per-unit RSS. And it must answer an existing negative result before it is written: **V15 already retired a proposed admission gate by measurement.** Here too the two records disagree on the number: the README says **0 of 881** thread-samples parked in `Id.acquire` (4,472 Zig frames resolved as the instrument control), while `PROMOTED/RECORD.md:147` says **0.16% of ~1,254** — which is not zero. The retirement stands in both; the figure must be re-derived before it is quoted again. A new admission card that does not say why V15 does not apply to it is re-proposing something the harness already killed. |
| **C9** typecheck-only and batch | **KEEP rungs 2 and 4 · STRIKE the C1 dependency · correct the card** | Two corrections first: rung 3 is **already PROMOTED**, and the import-aware rung is the **fork's**, not upstream's (both above). The substantive challenge is the dependency: the card makes "sema-lite" a "metadata-only compile against C1's interface artifacts", which chains the cheapest rung in the roadmap to the hardest open question in it. `PLAN.md` deliberately scopes rung 2 far below that — "name existence and arity-level shape only — no types, no comptime; anything deeper is the compiler's job and this rung says so rather than approximating it." That is answerable from stage 0's graph plus AstGen, both of which are PROMOTED and shipping. Unchained, rungs 2 and 4 are the **cheapest real user value in the entire memo**. |
| **C10** ICF and parallel link passes | **STRIKE for now** | Premise 1 above: `--icf` is not reachable, so this is a driver patch, not a free measurement. On top of that, ICF folds identical functions so they share addresses, which **changes debug information** — a cost this fork must measure, not inherit, and one that points the wrong way while 2b's whole purpose is debug fidelity. For the self-hosted linker, `CROSS_PROCESS_SIGNATURE.md`'s blocker is prior: unit indices are asserted lockstep across five sections (`src/link/Dwarf.zig:2538-2555`). Revisit after 2b. |

---

## 2. C6 in detail — the card the memo gets least right

C6 is the requested enhancement (ledger row G1, stage 2b, **not implemented**). It
offers three mechanisms. The tree already measured two of them, and the memo does
not carry those measurements forward.

**(a) DWARF 5 type units — NOT first, by this fork's own measurement.**
`CROSS_PROCESS_SIGNATURE.md` measured the per-CU sizes of the linked scale probe
and concluded, in its own words: "intra-emitter sharing is available and worth
0.14%; cross-compilation type sharing is worth 2.6% and is blocked; the request
itself is 97.4% and CU-level." Type units are the mechanism for the 2.6%. They
are worth having and they are not the shortest path to what was asked for.

**(b) dwz — STRIKE as the mechanism, KEEP as an oracle available today.**
`PLAN.md`'s own scope correction is binding here: "Compression after emission is
not deduplication before emission." dwz is a post-link tool; adopting it as the
mechanism would satisfy the letter of "one shared debug artifact" while missing
the request. **But dwz 0.17 is installed on this station**, and `dwz -m` produces
exactly the number nobody has: the achievable ceiling for one shared debug body
across two real consumer binaries, measured with **zero compiler change**. That
is the correct first move of this card — measure the prize before building the
machine. If `dwz -m` over the two existing consumers recovers little, the whole
of C6 is re-priced before a line is written.

**(c) split-DWARF / `-gmodules` — the real path, and the memo omits its first
packet.** The fork's identity work is already the dwo-id half of this mechanism
and it is measured: `DW_AT_GNU_dwo_id` is a real operand fed from
`Builder.dwo_id`, equal across repeated ReleaseSafe builds and distinct across
ABI, arch, optimize and content. What the memo does not name is that the next
step is **not a Zig patch**. `CGM_ACTUAL_BACKEND.md` measured with `llc-21` that
setting `splitDebugFilename` emits `DW_AT_GNU_dwo_name("a.dwo")` and **no `.dwo`
sections** — a dangling reference to a file that does not exist, "exactly the
debugger breakage this must not introduce". The emit stream lives in the C++
shim, and the boundary is closed: `EmitOptions`
(`src/codegen/llvm/bindings.zig:88`) has **no split-debug member**, and
`src/zig_llvm.cpp` sets only `opt.MCOptions.ABIName`. So C6's first code packet
is a **C++ shim change plus an `EmitOptions` field**, and any plan that starts in
Zig starts in the wrong file.

---

## 3. §2, the patch-layer contract — challenged

The contract's goal is right (`PLAN.md` constraint 1: the patchset must stay
small enough to carry across stable releases). Four of its six rules do not
survive as written.

| Rule | Verdict | Reason |
|---|---|---|
| 1. One quilt series per enhancement, series file as the primary output | **STRIKE quilt · KEEP "one series per enhancement" as a git convention** | The repo has no `patches/`, `debian/` or `.pc/`, and its patch layer is already one branch per enhancement (`patch/001`, `/003`, `/005a`–`/005c`). Introducing quilt creates a **second source of truth** beside git that a human must keep in step — the hand-maintained-list rot class this estate has been bitten by before. The rule's real content (one reviewable, droppable unit per enhancement) is already satisfied by the branch convention. |
| 2. DEP-3 headers, `Forwarded: no` | **STRIKE the headers · KEEP `Applied-Upstream` tracking** | DEP-3 is a Debian **packaging** convention for files under `debian/patches/`. This fork ships as a git fork plus GitHub releases; there is no packaging layer to carry the headers. One idea inside it is load-bearing and must be kept in some form: knowing when upstream has landed the same thing so the series is **DROPPED at rebase instead of carried as a duplicate**. Implement it where the fork already tracks status — the README difference table's Status column — by adding an `UPSTREAMED` value beside PROMOTED / ships-OFF / TOOLING / DOCS. |
| 3. New files under `src/cgm/<enhancement>/`, one hook per seam | **STRIKE the migration · KEEP the rule for NEW files, weakly** | Moving the six existing fork files rewrites paths in every doc, receipt and commit message that cites them, for a collision benefit that is speculative: a new file in an upstream directory conflicts only if upstream adds a file of the same name. The rebase cost that actually hurts is **hunks in upstream files**, and this rule does not reduce those. Where upstream's own topology is the natural home — `src/Zcu/ReadyIndex.zig` beside `Zcu` — that placement is better, not worse. Keep "new files first, hunks last"; drop the directory mandate. |
| 4. A drop-a-file red→green test per series | **KEEP · but with a precondition** | This is doctrine principle 5 and it is not negotiable. The precondition: **four prepared sabotage patches have never been fired** — `V3_intern_partitions_invariant`, `V14_affinity_intersection`, `VS2a_concurrent_reserve_zero`, `VS2b_reserve_exceeds_async_limit` — and all four still `git apply --check` **clean against today's tree** (verified 2026-09-10). Mandating new controls for new series while four existing controls sit unfired inverts the priority. Fire them first; see P0. |
| 5. Off by default, flag-gated | **KEEP unchanged** | Already `PLAN.md` constraint 2. |
| 6. Chromium-style generated patch README | **KEEP, reduced** | The README difference table already plays this role and is already the fork's front door. Generating it from series headers requires the headers struck in rule 2; generate it from the git branch convention plus the Status column instead. |

### The 0.17 rebase layout this plan proposes instead

One branch per enhancement, rebased in dependency order, each carrying its own
red→green control, each independently droppable:

The fork's existing unit is a **branch per patch family**, with sub-patches as
labelled commits inside it. The branches that actually exist are
`patch/002-adaptive-partition`, `patch/003-multimodule-file-diagnostic` and
`patch/005-auto-hardware-threading`; `patch/005a`/`005b`/`005c` are commit labels
within the last of those (e.g. `7106d368` (patch/005a)), **not branches**. The
proposal keeps that unit rather than inventing a new one:

```
main (verbatim upstream 0.17 import)
 |-- patch/003-multimodule-file-diagnostic   [control: H5, seen red]
 |-- patch/005-auto-hardware-threading       [005a topology  : V-S1a  + V14      <- P0]
 |                                           [005b threadplan: V2-EXP, V5, V3    <- P0]
 |                                           [005c ordering  : 4 fired, ships OFF]
 |                                           [riders         : V4, V15, VS2a/b   <- P0]
 |-- patch/006-pre-compile-tooling           [stage 0 graph + 0.5 rungs 1,3; no control on record]
 |-- patch/007-decl-existence-and-as-module  [0.5 rungs 2,4        (P2); control per rung]
 |-- patch/008-analysis-ledger               [stage 2a             (P1); control per counter]
 |-- patch/009-split-debug-emit              [2b shim + EmitOptions (P3b); control: gdb lines/types/locals]
 |-- patch/010-module-artifact-cache         [2c                   (P4); control: drop-any-entry equivalence]
```

The interned-index exhaustion refusal and the widening (ledger D1, D2) are
already on `main` through the shared history and need no series of their own.

Each row's rebase report is one of: **applied / hunk failed / control red /
UPSTREAMED (dropped)**. That is the honest denominator §2 rule 4 asks for, and it
is reportable without adopting a second patch system.

---

## 4. Packet order

Dependency order, not preference order. Each packet lands with its own
rebuilt-binary control or lands explicitly unmeasured.

| # | Packet | Depends on | Why here | Build cost |
|---|---|---|---|---|
| **P0** | **Fire the four unfired sabotage controls** (V3, V14, V-S2a, V-S2b) | nothing — all four apply clean today | The cheapest proof debt in the repository, and it converts four ledger rows from "exercised" to "proven". Doing it before new cards is what principle 5 means. | 4 rebuilds |
| **P1** | **C7 — per-module analysis ledger** (stage 2a) | nothing; transport already PROMOTED | `PLAN.md`'s own gate for 2c: do not bank savings you have not measured. Read-only, smallest divergence. | 1 rebuild |
| **P2** | **C9 — 0.5 rungs 2 and 4**, unchained from C1 | stage 0 graph (PROMOTED) | Cheapest real user value; independent of the crown; catches call-to-nonexistent-symbol before a multi-minute compile. | 1–2 rebuilds |
| **P3a** | **C6 measurement — `dwz -m` ceiling oracle** | nothing; dwz 0.17 installed | Measures the prize with **zero compiler change** and re-prices all of C6 before a line is written. | none |
| **P3b** | **C6 code — `EmitOptions` split-debug member + C++ shim emit stream** | P3a's number justifying it | The memo's omitted first packet; any Zig-first plan starts in the wrong file. | 1 rebuild + shim |
| **P4** | **2c — C5's manifest shape + C2's verification walk + C1 folded in** | P1's ledger | The crown. The pool serialization boundary is faced here, once, not three times under three card names. | staged |
| **P5** | **C3 offline partitioner (tooling), then C4 / C8** | P4's artifacts | Residency and multi-unit residency only mean something once artifacts exist to evict and reuse. | staged |
| — | C10 | deferred | Struck above; revisit after 2b. |

**Standing gate on every packet, restated:** the completeness work in flight
(`G4`) is still open — the `cgm-dwoid` trace sites are authored and in no built
binary, so exact input attribution is unproven. No packet above may be reported
as landed while its own control has not gone red and come back green on a
rebuilt binary.

## 5. What this plan does not claim

It schedules nothing on a date, promises no performance, size or memory result,
and authorizes no promotion, push, release or default change. Stage 2b remains
unimplemented; a 64-bit identity remains a reuse candidate and not shared debug
bodies. Every card struck here can be re-argued with a measurement, and the three
failed premises in §0 are corrections to the memo, not defects in it — a research
memo that survives contact with the tree in seven cards out of ten did its job.
