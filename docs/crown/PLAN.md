# The Crown — a module-artifact cache for Zig

*Plan authored 2026-08-22 by Claude Fable 5 (Anthropic, via Claude Code) with Daniel
Campos Ramos. This is the staged design for the fork's flagship feature: attacking
"every module has its debug copy" at its source.*

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
| 1 | **Internals map**: a cited map of where per-module boundaries already exist in the compiler and where they blur (`docs/crown/INTERNALS_MAP.md`). Documentation only. | none | workflow running |
| 2a | **Analysis-reuse ledger**: instrument `Zcu` to attribute analysis work (units analyzed, ZIR→AIR lowering, comptime evaluations) to the module that owns it, and report per-module totals + the context-free/context-sensitive split *measured, not asserted*. Read-only accounting. | small, additive | after 0+1 |
| 2b | **DWARF dedup-by-reference**: shared modules' debug info emitted once per build sweep and referenced (type units / `DW_AT_dwo`-style separation as fits `link/Dwarf.zig`'s structure), instead of copied per unit. | medium; confined to link/ | after 2a |
| 2c | **The cache proper**: content-addressed per-module artifacts for the context-free class, keyed as above, stored via the existing `std.Build.Cache` machinery (`Compilation.zig` already threads `CacheUse` — we extend an existing seam rather than invent a parallel one). Context-sensitive work recomputes as today. | the crown; largest patch, staged behind a flag, off by default | last |

Stage order is dependency order: you cannot cache what you cannot name (0), you
should not design against structure you have not mapped (1), and you must not
claim savings you have not measured (2a) before building the machinery that
banks them (2b, 2c).

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
