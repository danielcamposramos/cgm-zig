# Next enhancement wave — known-good compiler mechanisms to adopt, mapped to the fork's principles

*Research memo, 2026-09-10. Authored by the orchestrating partner (Claude Fable 5.1) at the
maintainer's request: "find other compiler enhancements we could adopt … those enhancements
were based on simple principles … add to a next enhancement wave … consider hyper-modularity
on the code we patch on top of zig, keeping the ease of adopt/migrate in mind for the upcoming
0.17 version." Public references only; every claim below is a pointer to a source, not a
measurement of this fork. Nothing here is implemented, promised or measured by this memo.*

## 0. How to read this

Each candidate is a CARD: the fork principle it serves (`DOCTRINE.md`), the crown stage it
belongs to (`PLAN.md`), the mechanism's origin with a reference, the PATCH SHAPE that keeps it
rebase-friendly (additive, behind a flag, new files preferred, minimal hunks in upstream files),
and its interaction with what upstream 0.17 is already doing. Cards are candidates for the
compiler partner's round-two CHALLENGE, not a queue: each must be reconciled against actual
bodies (`ENHANCEMENT_RECONCILIATION_2026-09-10.md`) before it becomes a packet.

Upstream's own direction, from its devlog (2025-06-14): incremental compilation "getting pretty
close to being turned on by default in some cases"; "decreasing the amount of work the compiler
does at the very end of compilation (its 'flush' phase)"; "(in the more distant future)
parallelizing semantic analysis"; codegen already runs "arbitrarily many threads" beside one
Sema thread and one link thread. The 0.17.0 milestone carries build-protocol serialization
items (#36387 dependencies, #36388 public modules of packages, #36389 configurer errors, #36403
generated-file notifications), a cache-manifest ordering fix (#36651) and a watch-plus-std
workflow fix (#36513). A fork card that overlaps upstream's direction is shaped so it can be
DROPPED at rebase (DEP-3 `Applied-Upstream`), never fought.

## 1. The cards

### C1 — Metadata-first ("pipelined") module artifacts
- Principle: module-as-tile; measured claims. Stage: 2c (the cache proper), enabling 0.5 rung 4.
- Origin: Cargo/rustc pipelined compilation — the compiler emits `.rmeta` (everything a
  dependent needs) "as soon as possible, even before having the final executable code
  available", so dependents start early; Go's per-package "export data" (Unified IR: "type
  information for all exported declarations, IR for bodies of functions that are candidates for
  inlining… with an index allowing lazy decoding").
- Fork shape: a per-module INTERFACE artifact (exported decls + comptime-visible bodies only),
  emitted before codegen, content-addressed; dependents' Sema starts against it. New file(s)
  under a fork-owned directory; one hook at the point where a module's analysis completes.
- 0.17: complements upstream's build-protocol "public modules" serialization (#36388); keep the
  artifact format versioned and off by default.

### C2 — Red-green re-verification for cross-session reuse
- Principle: correctness never rests on the cache. Stage: 2c's verification mode.
- Origin: rustc's dependency graph — nodes fingerprinted by "a fingerprint of the query key"
  (128-bit stable hashes), `try_mark_green` re-verifies a cached node by walking its
  dependencies and only re-computes when a dependency is red; `eval_always` for queries that
  read external inputs; the stated limitation "not able to update on-disk caches and the
  dependency graph in-place".
- Fork shape: the per-module artifact carries the fingerprints of its transitive inputs; a
  verification mode ("recompute and compare") is the fork's own doctrine already — make it the
  red-green walk rather than a full recompute. Zig's AnalUnit outdated-marking is the in-session
  half; this is the cross-session half.
- 0.17: upstream's incremental work owns in-session invalidation; the fork owns only the
  on-disk artifact and its verification. Keep them in separate files.

### C3 — Partitioning the module graph to a probed memory budget
- Principle: probe-first startup; residency bounds. Stage: 2d (tiles).
- Origin: GCC WHOPR — "the whole program is split into a given number of partitions of roughly
  the same size. The compiler tries to minimize the number of references which cross partition
  boundaries", "avoids the need to load the whole program into memory"; ThinLTO — per-module
  summaries, whole-program analysis over summaries, then parallel per-module backends.
- Fork shape: a partitioner over the emitted module graph (stage 0's JSON) that derives tile
  size from the probed host memory and the measured per-unit RSS, minimizing cross-tile
  imports; the scheduler evicts finished tiles to the artifact store. New files only.
- 0.17: independent of upstream; the module graph emitter is the seam.

### C4 — A resident compiler serving many compilation units
- Principle: residency; self-report. Stage: multitasking line.
- Origin: Bazel persistent workers — `--persistent_worker`, `WorkRequest`/`WorkResponse` over
  stdin/stdout (JSON or protobuf), "input file digests accompany each request, enabling
  compilers to validate cached data without rereading files"; measured: "Compiling Bazel is
  about 2.5 times as fast with workers", up to "a factor 6" on frequently-changed constants.
- Fork shape: a `zig` worker mode that keeps the intern pool and analysed shared closure warm
  and serves successive units (the hundreds of per-module test units that share most of one
  closure), with per-request input digests. Upstream's `--watch -fincremental` keeps ONE
  compilation warm; this serves MANY units from one warm frontend. One new entry point.
- 0.17: the build runner's protocol work (#36387–36403) is the natural transport; align the
  request shape with it so the patch shrinks at rebase.

### C5 — Content-addressed action cache keyed by input digests (local, then shared)
- Principle: correctness never rests on the cache; measured claims. Stage: 2c.
- Origin: Bazel's action cache ("a digest of the action's metadata and inputs") and CAS;
  ccache direct mode — a manifest keyed by the hash of input + compiler arguments listing the
  hashes of the files actually read, hit only when all still match; sccache's shared/remote
  variant of the same design.
- Fork shape: the key is `(module content hash, transitive-import content hashes, target,
  mode, flags)` as `PLAN.md` already states — this card fixes the manifest SHAPE to ccache's
  proven one (a manifest per key listing every input digest) and adds a shared store option
  behind a flag. Any entry droppable; verification mode from C2.
- 0.17: upstream's `std.Build.Cache` is the seam ("we extend an existing seam rather than
  invent a parallel one", `PLAN.md`); #36651 shows upstream is touching manifest ordering —
  rebase watch item.

### C6 — Debug bodies emitted once and REFERENCED (the debug-sharing stage)
- Principle: module-as-tile; measured size. Stage: 2b.
- Origin, three DWARF-standard reference mechanisms:
  (a) DWARF 5 type units (`-fdebug-types-section`): types keyed by a signature hash, deduplicated
      by reference; (b) dwz: duplicated DIEs moved into `DW_TAG_partial_unit` and imported by
      `DW_TAG_imported_unit` in every CU that needs them, and with `-m` a shared `.dwz` file
      referenced by `.gnu_debugaltlink` across executables — ONE shared debug body across many
      binaries; (c) Clang `-gmodules`: a module's types emitted once into the `.pcm`, compile
      units carrying skeleton references (`splitDebugFilename`, dwo id) instead of copies — the
      closest published precedent for "one shared debug artifact across a project's compilation
      units". The fork's current identity work parallels split-DWARF's dwo_id as a content hash.
- Fork shape: per-module debug bodies as supplementary objects (DWARF 5 supplementary object
  file / partial units), referenced from every unit by the identity already being measured;
  the linker side keeps `--gdb-index`-style indexing. Emission-side, behind a flag; the
  debugger controls (lines/types/locals on real consumers) are the acceptance, as in the
  existing controls.
- 0.17: LLVM-backend path only today (the consuming project compiles through LLVM + LLD, see
  `CGM_ACTUAL_BACKEND.md`); the self-hosted backends' `link/Dwarf.zig` is a second, later arm.

### C7 — A per-module analysis ledger as machine-readable self-report
- Principle: self-report; measured claims. Stage: 2a.
- Origin: rustc `-Zself-profile` ("Timing data and cache hits/misses are now recorded at the
  query level"); Clang `-ftime-trace` (Chrome-trace JSON per unit, per function/template);
  Swift `-driver-time-compilation` and `-debug-time-function-bodies`; Zig's own
  `zig build --time-report` (0.15+, web UI, per-step).
- Fork shape: extend the existing time report with per-MODULE attribution (units analysed,
  comptime evaluations, ZIR→AIR lowerings) and artifact-cache hit/miss counts, emitted as JSON
  beside the web UI. Additive flag; new emitter file.
- 0.17: upstream owns `--time-report`; keep the fork's fields in a separate JSON object so the
  patch is one hook.

### C8 — Resource-aware job admission from measured per-unit cost
- Principle: probe-first startup; present-or-refuse-by-name. Stage: multitasking line
  (extends patch/005).
- Origin: Bazel `--local_cpu_resources` / `--local_ram_resources` with host-derived defaults
  and per-action resource declarations; Ninja/Make load limits (`-l`).
- Fork shape: codegen/link job admission derived from the probed host and the ledger's measured
  per-unit RSS (C7), refusing by name with the measured number when a unit cannot fit, instead
  of the silent kill the fork was born from. New scheduler policy file; one hook.
- 0.17: independent.

### C9 — Typecheck-only and batch modes with honest denominators
- Principle: present-or-refuse-by-name; self-report. Stage: 0.5 rungs 2–4.
- Origin: `cargo check` (rmeta-only, no codegen), `swiftc -typecheck`, `clang -fsyntax-only`;
  Swift batch mode ("one frontend job per CPU … each subprocess will parse all inputs" — the
  quadratic parse cost the fork's batch rung must NOT reproduce: parse once, share).
- Fork shape: "sema-lite" as a metadata-only compile of a module against C1's interface
  artifacts (declaration existence and arity, no bodies); batch mode over stage 0's graph with
  checked / failed / skipped-with-reasons and JSON diagnostics; check-as-module by naming the
  module identity from the graph. Additive subcommands/flags.
- 0.17: upstream's import-aware AstGen already landed (README); this is the next rung.

### C10 — Linker-side references: ICF and parallel passes
- Principle: measured size. Stage: 2b's linker half, later.
- Origin: LLD `--icf=safe` (identical sections folded by content, address-significance aware);
  mold's data-parallel relocation scanning, GC, ICF and layout.
- Fork shape: nothing to patch in LLD; for the self-hosted linker, mold's pass structure is the
  reference when parallelising. Debug-info impact of ICF (folded functions share addresses) is a
  named cost, not hidden.
- 0.17: upstream Elf2 work (#36665) is the seam; wait for it.

## 2. Hyper-modularity of the patch layer itself (the 0.17 migration contract)

The fork's value is a patchset small enough to carry across stable upstream releases
(`PLAN.md` constraint 1). Make the patch layer obey the same modular law as the code:

1. **One series per enhancement**, stacked with quilt (`series` file; `quilt pop` to bare
   upstream, apply the new tarball, `quilt push` series by series; a failed hunk names its
   series). The primary output IS the patch series; the git history is the record of it.
2. **DEP-3 headers on every patch** — `Description`, `Origin: vendor`, `Forwarded: no` (the
   fork's standing no-upstream ruling), `Applied-Upstream: <version|commit>` when upstream lands
   the same thing (the rebase then DROPS the series instead of carrying a duplicate),
   `Last-Update`. DEP-3 now recommends the git-compatible header format.
3. **New files first, hunks last**: each enhancement lives under a fork-owned directory
   (`src/cgm/<enhancement>/`) with ONE registered hook per upstream seam, the seams listed in
   `INTERNALS_MAP.md`; an upstream file may gain a hook line, never a body.
4. **A drop-a-file test per series** (its red→green control on a rebuilt binary), so a rebase
   CI can `push` each series onto the 0.17 tarball and report per series: applied / hunk failed
   / test red — the honest denominator, never "the fork builds".
5. **Off by default, flag-gated** (constraint 2), so a series that fails to apply can be left out
   of a release without changing upstream behaviour.
6. **Chromium's convention as the reference**: a `patches/` directory beside the vendored tree
   with a README listing every local modification and its upstream status; the fork's `README`
   difference table already plays that role — keep it generated from the series headers.

## 3. What this memo does not claim

No candidate is measured, chosen or scheduled by this memo. The compiler partner reconciles
each card against the actual bodies and the 0.17 milestone, challenges it, and only then a card
becomes a packet with its own rebuilt-binary control. Upstream's incremental-by-default,
flush-phase reduction and future parallel Sema are upstream's; the fork's cards are the ones
upstream is not doing (multi-unit residency, per-module artifacts, debug bodies by reference,
memory-bounded tiles, the ledger), shaped to be dropped the day upstream does them.

## Sources

- Zig devlog 2025: https://ziglang.org/devlog/2025/
- Zig 0.17.0 milestone: https://codeberg.org/ziglang/zig/milestone/69474
- Zig incremental compilation internals (mlugg): https://mlugg.co.uk/posts/incremental-compilation-internals/
- Cargo pipelined compilation: https://github.com/rust-lang/cargo/pull/6883 · https://github.com/rust-lang/cargo/issues/6660
- rustc incremental compilation in detail: https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html · RFC 1298: https://rust-lang.github.io/rfcs/1298-incremental-compilation.html
- rustc `-Zself-profile`: https://doc.rust-lang.org/beta/unstable-book/compiler-flags/self-profile.html
- Go compiler export data / Unified IR: https://go.dev/src/cmd/compile/README
- GCC LTO / WHOPR overview: https://gcc.gnu.org/onlinedocs/gccint/LTO-Overview.html · ThinLTO (Johnson et al.): https://www.researchgate.net/publication/314105281_ThinLTO_Scalable_and_incremental_LTO
- Bazel remote caching (AC/CAS): https://bazel.build/remote/caching · persistent workers: https://bazel.build/remote/persistent
- ccache direct mode: https://ccache.dev/manual/4.12.html · sccache direct mode: https://github.com/mozilla/sccache/issues/219
- dwz partial units / multifile: https://www.mankier.com/1/dwz · DWZ + DWARF-5 supplementary files RFC: https://discourse.llvm.org/t/rfc-for-dwz-dw-tag-imported-unit-dwarf-5-supplementary-files/46052
- DWARF type units in split DWARF: https://reviews.llvm.org/D54350 · Clang module debug info test: https://github.com/llvm-mirror/llvm/blob/master/test/DebugInfo/X86/clang-module.ll · Clang users manual (debug info flags): https://clang.llvm.org/docs/UsersManual.html#controlling-debug-information
- Swift compiler performance (batch mode, timing flags): https://github.com/swiftlang/swift/blob/main/docs/CompilerPerformance.md
- LLD ICF and GNU linker options: https://maskray.me/blog/2020-11-15-explain-gnu-linker-options · mold: https://arxiv.org/html/2608.23228v1
- Zig `--time-report`: https://github.com/ziglang/zig/issues/24658
- DEP-3 patch tagging guidelines: https://dep-team.pages.debian.net/deps/dep3/ · quilt: https://manpages.org/quilt
- Chromium third_party patches convention: https://chromium.googlesource.com/chromium/src.git/+/refs/heads/main/third_party/zlib/patches/README · https://chromium.googlesource.com/chromium/src/+/HEAD/docs/adding_to_third_party.md
