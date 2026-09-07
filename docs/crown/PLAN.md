# The Crown — a module-artifact cache for Zig

*Plan authored 2026-08-22 by Claude Fable 5 (Anthropic, via Claude Code) with Daniel
Campos Ramos. This is the staged design for the fork's flagship feature: attacking
"every module has its debug copy" at its source.*

## Current-state note — 2026-09-06

The stage table below preserves the original design sequence, not today's
implementation status. Module-graph emission, import-aware AstGen and batch
AstGen subsequently landed; their individual capabilities and evidence are
listed in the current README. That does not establish every field or every
rung promised by this plan.

The new optional ready-set index at `d3347292c9` addresses repeated layered
selection scans. It is not the module-artifact cache, the analysis-reuse
ledger, DWARF deduplication, residency-bounded tiling, or parallel Sema. Those
remain distinct work with the comptime/context constraints below intact.
The index now has bounded rebuilt-candidate integration evidence, including
10,678 same-live-state index/scan agreements and actual update/wrapper reach.
Broken-hook controls and production OOM remain open; see the live-shadow
receipt. This is not end-to-end speedup evidence or a new default.

Update 2026-09-07: the [lost ordinary append-hook control](READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md)
now fails by the intended membership assertion and passes after exact source
restoration plus a separate compiler rebuild: all four fixture updates and
2,095 same-state agreements. Lost-update-invalidation, default-entry and
integration-OOM controls remain open. This closes one bounded control, not a
crown stage, a new default, promotion or end-to-end speedup evidence.

Further update 2026-09-07: the [lost-update-invalidation control](READY_INDEX_LOST_INVALIDATION_CONTROL_2026-09-07.md)
has its intended populated-memo failure, exact source restoration and separately
rebuilt four-outcome pass with 2,095 same-state agreements. The failure precedes
stale selection and does not independently test each index-state predicate.
Default-entry and integration-OOM controls remain open; no crown-stage completion,
default change, speedup or promotion is implied.

Further default-mode update 2026-09-07: the [default-entry control](READY_INDEX_DEFAULT_ENTRY_CONTROL_2026-09-07.md)
discriminates layered helper entry from explicit insertion and omitted order:
the two default-mode runs pass three outcomes each, and a separately rebuilt
restoration passes layered order with 2,083 same-state agreements. Prepare's
panic masks independent append-tripwire activation. Integration OOM remains
open; this closes no crown stage and implies no speedup or promotion.

Superseding status 2026-09-07: the earlier open-status notes are preserved as
history. The [first nodes-preparation-allocation control](READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md)
is complete: 4/4 compiler builds and 5/5 intended runtime phase outcomes (four
successful runs and one expected named tripwire failure), including exact clean
restoration and recovery. The shipping candidate remains uninstrumented.
Broader OOM coverage, post-abort rearming and performance remain unproved;
this closes no crown stage and does not establish foundation or release readiness.

The [release-cost packet](READY_INDEX_RELEASE_COST_PACKET_2026-09-07.md) is
materialized locally, with 0/12 timed compiles run. Three CPU-activity holds
prevented launch, not failed timing samples. Package, companion evidence bundle,
online main synchronization, release and promotion remain open.

Superseding executed-cost status 2026-09-07: preserve the earlier 0/12 note
as history. The [executed cost receipt](READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
records 12/12 successful compiles, 13 non-launch holds and no retry/replacement.
All three wall comparisons are inside the existing heuristic; old/default
still wins 3/3 slots and candidate default median RSS is +356 KiB. The
clean-machine criterion is UNFULFILLED, not waived: this is environment-qualified
descriptive evidence, not promotion clearance. Unpromoted candidate staging
and smoke verification may proceed separately; package/evidence,
publication/main-sync, release and system-default gates remain open and
unexecuted in this packet. No crown stage or foundation completion is implied.

Superseding local packaging status 2026-09-07: the candidate package is locally
archive/extraction/smoke-verified, and the separate companion has
20,218/20,218 members reconciled by assembly readback and Root's later traversal.
See the [package and companion receipt](CANDIDATE_PACKAGE_VERIFICATION_2026-09-07.md)
for checksums, exact snapshot boundaries and shared-parser review limits.
Neither frozen archive includes these later readiness notes or the later
observer implementation/integration. Publication, online main synchronization,
release and system-default promotion remain open; clean-machine cost acceptance
is still UNFULFILLED. This closes no crown stage and proves no speedup.

## The problem, measured

Zig performs whole-closure semantic analysis per compilation unit: one `build-exe`
invocation re-analyzes and re-emits code **and debug info** for every module in its
import closure, from scratch, every time. For small programs this is invisible. For
a hyper-modular estate (~1,800 named modules / ~2,300 files per product unit, plus
hundreds of small per-module test units that share most of that closure), the bill
is:

- each product compile re-analyzes the full closure (measured: ~13 min, ~16.5 GB
  peak RSS, 99–100% of a single core dominating the wall);
- every test unit re-analyzes its shared closure — the same modules, hundreds of
  times across a build sweep;
- every unit re-emits its own private copy of DWARF for the same shared modules —
  gigabytes of duplicated debug info that downstream tooling then compresses after
  the fact, because the compiler offered no way to not duplicate it.

There is no per-module compiled artifact — nothing at module granularity playing
the role a C object file or a Rust `rlib` plays. That absence is a deliberate
upstream simplification, and for most projects it is the right trade. For
hyper-modular estates it is the single largest cost in the toolchain.

And the cost is not only time — it is a **hard residency wall**: because the whole
closure must be resident in one analysis, peak memory scales with closure size,
and a large-enough closure simply cannot be compiled on a given machine, at any
patience. The crown therefore has two goals, not one: **reuse** (don't redo work
that hasn't changed) and **residency bounds** (don't require the whole closure in
memory at once). The second goal borrows a law every mature large-workload system
converges on — a renderer processes frames in tiles, a database pages, a streaming
engine keeps a working set and seeks the rest: total size becomes a streaming
question; the resident set becomes a bounded question. Here the **module is the
tile**, the content-addressed cache is the tile buffer, and eviction is the
residency ladder (stage 2d).

## Why this design must confront comptime honestly

A Zig module is not compiled in a vacuum. Its analysis can depend on the importing
context: generic instantiation happens at the use site, comptime values flow across
module boundaries, and `usingnamespace`/mixin idioms blur ownership further. So a
naive "hash the file, cache the codegen" design is wrong at exit zero. The honest
frame is a **two-class split**:

- **Context-free work** — parse, AstGen (already cached upstream as ZIR),
  non-generic function bodies whose transitive comptime inputs resolve entirely
  inside the module's own closure slice, type layouts that do not capture
  instantiation-site values. Cacheable under a key of
  `(module content hash, transitive-import content hashes, target, mode, flags)`.
- **Context-sensitive work** — generic instantiations, comptime evaluation seeded
  by importer-provided values, inline calls crossing the module edge. These either
  carry the instantiation context in the key (finer-grained, later stage) or stay
  uncached (correct-by-default fallback).

Anything not provably context-free is treated as context-sensitive. Correctness
never depends on the cache; the cache is only ever a shortcut to a result the
compiler could recompute.

## The stages

| Stage | Deliverable | Divergence cost | Status |
|---|---|---|---|
| 0 | **Module-graph observability**: a flag that emits the fully-resolved module graph (module name, root path, file membership, import edges, per-module file content digests) as JSON. Zero behavior change without the flag. | One flag + one walk + one emitter; trivially rebase-friendly | fleshing now |
| 0.5 | **Pre-compile tooling** (four rungs, each consuming stage 0's emitted graph — see the section below): import-aware `ast-check` · decl-existence pass ("sema-lite") · batch mode with honest denominators · check-as-module. | additive flags on existing tools; no changed defaults | after 0 |
| 1 | **Internals map**: a cited map of where per-module boundaries already exist in the compiler and where they blur (`docs/crown/INTERNALS_MAP.md`). Documentation only. | none | done |
| 2a | **Analysis-reuse ledger**: instrument `Zcu` to attribute analysis work (units analyzed, ZIR→AIR lowering, comptime evaluations) to the module that owns it, and report per-module totals + the context-free/context-sensitive split *measured, not asserted*. Read-only accounting. | small, additive | after 0+1 |
| 2b | **DWARF dedup-by-reference**: shared modules' debug info emitted once per build sweep and referenced (type units / `DW_AT_dwo`-style separation as fits `link/Dwarf.zig`'s structure), instead of copied per unit. | medium; confined to link/ | after 2a |
| 2c | **The cache proper**: content-addressed per-module artifacts for the context-free class, keyed as above, stored via the existing `std.Build.Cache` machinery (`Compilation.zig` already threads `CacheUse` — we extend an existing seam rather than invent a parallel one). Context-sensitive work recomputes as today. | the crown; largest patch, staged behind a flag, off by default | last |
| 2d | **Residency-bounded compilation (tiles)**: the module is the tile; the content-addressed cache is the tile buffer. The frontend processes module-granular tiles under a declared memory budget, spilling finished per-module artifacts to the cache and evicting them from the resident set, so closures larger than available memory compile instead of dying. Eviction policy is the residency ladder: hot working set resident → warm artifacts cached on disk → everything re-derivable. | builds directly on 2c's artifacts; the scheduler/eviction layer is new code behind the same flag | with/after 2c |

Stage order is dependency order: you cannot cache what you cannot name (0), you
should not design against structure you have not mapped (1), and you must not
claim savings you have not measured (2a) before building the machinery that
banks them (2b, 2c).

## Stage 0.5 — pre-compile tooling

Motivation: a large estate ran months of zero-build verification on `ast-check`
and measured exactly four gaps in what can be known before a compile; closing
them upgrades pre-compilation verification from syntax-only to **graph-aware**,
shrinking the "only a build can prove" class dramatically. Every rung feeds on
stage 0's emitted module graph, stays seconds-fast, and lands as an additive
flag — never a changed default.

1. **Import-aware `ast-check`.** `ast-check` accepting a module-graph input
   (stage 0's own JSON) so `@import("name")` resolves against the real graph:
   missing module, missing file, unregistered import name — caught in seconds,
   no build. Today an unresolvable named import is invisible until full
   compilation.
2. **Decl-existence pass ("sema-lite").** After AstGen, resolve top-level
   declaration references across the graph *without* full semantic analysis:
   catches call-to-nonexistent-symbol — the class syntax checking is provably
   blind to (a build-graph change that introduced a reference to a symbol that
   exists nowhere passes `ast-check` today and dies minutes later in the
   compile). This is the missing middle rung between seconds-fast syntax and
   the multi-minute full compile. Honest scope: name existence and arity-level
   shape only — no types, no comptime; anything deeper is the compiler's job
   and this rung says so rather than approximating it.
3. **Batch mode with honest denominators.** N files in one invocation; summary
   reports checked / failed / **skipped-with-reasons** so the denominator is
   never silently smaller than the request; diagnostics available as
   machine-readable JSON so external harnesses compose it without scraping.
4. **Check-as-module.** Check a file *under a named module identity* from the
   graph. The same file can lawfully live as different modules in different
   compilations; today that duality is unverifiable before a build. This rung
   makes "this file, as module X" a checkable claim.

## Design constraints (standing, all stages)

1. **Rebase-friendly.** Every stage is an additive patch behind a flag or confined
   to a new file where possible. No reformatting of upstream code, no drive-by
   cleanups, minimal hunks. The fork's value is the patchset staying small enough
   to carry forward across upstream releases (stable releases only, per the
   version policy).
2. **Off by default.** Upstream behavior byte-identical unless the operator opts
   in. The fork must remain a strict superset.
3. **Correctness never rests on the cache.** Any cache entry can be dropped at any
   time; the result is only slower, never different. A verification mode
   recomputes and compares.
4. **Measured claims only.** Each stage lands with its own measurement (what got
   faster/smaller, on what workload) or it lands as explicitly unmeasured.

## Risks, stated plainly

- **Upstream flux**: `Zcu`/`InternPool` internals move between releases; stage 2c
  code will need real porting work at each rebase. Mitigation: stages 0–2a touch
  stable seams; 2b/2c are the only rebase-heavy pieces and stay flag-gated.
- **The intern pool is global**: types and values are interned compilation-wide,
  so "per-module artifact" requires a serialization boundary the pool does not
  naturally offer. Stage 1's map must answer how ZIR-level caching (per-file,
  already content-addressed upstream) composes with pool-level reuse before 2c is
  designed in detail. This is the hardest open question and we say so.
- **Key subtlety**: a stale-key bug produces wrong programs silently — the worst
  failure class. Hence constraint 3 and the verification mode.

## Provenance

Diagnosis of the motivating failure, this plan, and the staged implementation are
joint human+AI work (Daniel Campos Ramos with Anthropic Claude models — Fable
planning/orchestration; Opus, Sonnet, Haiku in the implementation workflows),
credited per commit. See `PROVENANCE.md`.

## Observed-cost successor status — 2026-09-07

The [observed-cost receipt](READY_INDEX_OBSERVED_COST_RECEIPT_2026-09-07.md)
records two separately stopped attempts, each 1/16 launched with 15 unlaunched:
first a root empty-libc launch-binding error; then a corrected successful
old/default compile rejected by one CPU10 user tick under the preaccepted
zero-sibling-execution rule. Neither produced a quality-supported timing.
The original 12/12 successful, environment-qualified samples remain unchanged
and unpooled. The real wrapped busy/idle controls passed 2/2 for instrument
correctness only. The full observed matrix and clean-machine cost gate remain
UNFULFILLED; no further workload is authorized by these receipts. Both existing
archives remain frozen without this later implementation/evidence. This status
claims no comparison, speedup, online-main push, release, default promotion or
crown-stage completion.

## Published candidate successor — 2026-09-07

Superseding only the historical publication-open status: root published the
[unpromoted candidate prerelease](https://github.com/danielcamposramos/cgm-zig/releases/tag/0.16.0%2Bcgm.0399d2b19b)
at 14:18:54 UTC, with 3/3 uploaded assets matched by recorded API names,
sizes and digests. The [execution successor](CANDIDATE_RELEASE_2026-09-07.md#2026-09-07--executed-prerelease-publication)
retains the full identities, source-main synchronization and API-only ceiling;
no downloaded-byte readback was performed. Stable046d remains latest and the
station default remains `stage3-046d6833`. Clean-machine cost acceptance and
default promotion are still UNFULFILLED; both observed series stay stopped.
No frozen archive was updated with later evidence or these notes. This closes
bounded prerelease publication, not a Crown stage, performance or foundation gate.

## Operational promotion successor — 2026-09-07

The [operational promotion receipt](OPERATIONAL_PROMOTION_2026-09-07.md)
supersedes earlier default-pending statements: at 15:48:17.019 UTC, root
repointed the station to durable `stage3-d6b4168f`, preserving old046d.
Daniel's direction and the existing functional/control/package evidence are
the primary verification basis. Both real-project attempts failed at matching
project graph guards; 131/131 selected diagnostic rows agree after thread-PID
normalization, not product-build or runtime success. The bounded source mtime
census is not an estate-wide before/after byte seal. Historical clean-machine
cost acceptance remains UNFULFILLED, without a retroactive pass or speed claim.
This is a recorded operational judgment, not completion of the Crown roadmap.
The stopped cost series, public release designations and frozen archives remain
unchanged; no new workload or broader verification is implied by this note.
