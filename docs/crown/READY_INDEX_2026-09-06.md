# Optional ranked ready index — 2026-09-06

This is the finite implementation of the auxiliary ready-set index proposed in
`PATCH005_DOSSIER.md` §4.3. It removes repeated layered ready-set scans when the
optional index is usable. It does not introduce parallel Sema, change readiness,
change the default order, or promote a compiler. The existing single-threaded
Sema loop still feeds the existing codegen/linker work.

Maintainer direction: Daniel Campos Ramos requested continuation of the existing
compiler multitasking work. Implementation and bounded verification: GPT-6
(OpenAI Codex), working as an AI partner. Upstream-Status: not-filed-policy.

## Scope and authority

Starting HEAD: `63effbe93c276735c56c6d8ab1cb3f2149365c19` on
`patch/005-auto-hardware-threading`. The seven first-wave paths documented in
`TOOLCHAIN_CORRECTION_2026-09-06.md` were already dirty and accepted at
source/tooling level; they were frozen during this wave. Their diagnostic and
status corrections are not part of this index's test denominator.

This wave changes `src/Zcu.zig` and `src/Zcu/PerThread.zig`, adds
`src/Zcu/ReadyIndex.zig`, its single sibling test, and this receipt. It does not
change `src/Compilation.zig`. The coordinating maintainer is separately editing
build-recipe documentation; those changes are not this wave's authorship.
No git mutation, compiler rebuild, station repoint, package, or publication was
performed by this wave. The coordinator separately reported preserving the old
local main as `backup/main-before-sync-2026-09-06` and reconciling the clean
inactive main worktree to `63effbe9`; no remote push was part of this wave.

The compiler used for all checks was the existing `PROMOTED/zig`, resolving to
`PROMOTED/stage3-046d6833/bin/zig`, version `0.16.0`, SHA-256
`046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11`.
Its existing record identifies source `b991cb16` and ReleaseSafe. That binary
is unchanged and does not contain the new index.

## Mechanism and complete mutation surface

Prior-art inspection covered the existing scan, `ModuleRanking`, dossier §4.3,
the WIP preflight material, `std.PriorityQueue`, and existing partner oracle
patterns. `std.PriorityQueue` has no reverse map-position table or relocation
callback; arbitrary removal would need a lookup scan. The new bounded helper is
therefore an indexed binary heap, not a replacement scheduler or general queue
framework. Tests instantiate the production helper and production comparator;
there is no second heap implementation or new capability flag.

The authoritative `AutoArrayHashMapUnmanaged` maps still own all membership.
Each optional heap stores only a rank and its current map position, plus a
reverse map-position-to-heap-position table. Comparison is the unchanged
`ModuleRanking.before`: depth ascending, fan-in descending, internal before
facade; equal ranks use current authoritative map position. This is not FIFO:
`swapRemoveAt` moves the last map key into the removed slot. The helper repairs
both the displaced heap node and that moved map key's tie priority.

An invalid epoch builds a tier once using O(n) Floyd heapification. A usable
index peeks in O(1); ordinary heap append/removal repairs take O(log n).
Array growth is amortized: an occasional capacity increase can move O(n) bytes.
There is no ordinary insert/remove-triggered whole-ready-set rebuild. The
index adds O(n) auxiliary memory per indexed tier, a cost still requiring
end-to-end compiler measurement.

The integration audit enumerated every direct ready-map membership mutation:

| Existing owner/path | Integration |
| --- | --- |
| `markDependeeOutdated`, two puts | `readyPut`, append only when count increases |
| `markPoDependeeUpToDateInner`, one put | Same; duplicate puts do not duplicate heap entries |
| `markTransitiveDependersPotentiallyOutdated`, remove | `readySwapRemove`, old map position captured before removal |
| `clearOutdatedState`, remove | Same, retaining original membership assertions |
| `ensureFuncBodyAnalysisQueued`, one capacity/no-clobber put | Original map reservations preserved, then optional append hook |
| `ensureNavValAnalysisQueued`, two capacity/no-clobber puts | Both original reservations and nav-val/nav-ty membership preserved |
| `queueComptimeUnitAnalysis`, one capacity/no-clobber put | Same |
| `PerThread.ensureTypeLayoutUpToDate`, external struct-defaults put | Same public no-clobber wrapper |
| `Zcu.deinit` | Both auxiliary arrays in both tiers deinitialized |

Relevant source entry points: `Zcu.zig:3358` invalidation,
`Zcu.zig:3373` append hook, `Zcu.zig:3383` authoritative put wrapper,
`Zcu.zig:3400` preallocated put wrapper, `Zcu.zig:3413` removal wrapper,
`Zcu.zig:3433` indexed pick, `Zcu.zig:3451` original scan fallback,
`PerThread.zig:182` update invalidation, and `PerThread.zig:1496` external
struct-defaults insertion. Source line numbers refer to the POST hashes below.

`findOutdatedToAnalyze` retains the function-before-other branches and the
unchanged no-ready dependency-cycle fallback. Insertion mode returns key zero,
uses the original map operations, and allocates/maintains no auxiliary index.
Both modes remain selectable; insertion remains the default.

## Rank lifetime and failure atomicity

`PerThread.update` invalidates both indexes and clears `file_rank_memo` before
any update work, including paths which later abort. `computeAliveFiles` is the
existing single-threaded pass which can reassign an existing file's `mod`.
Previously the memo had no matching update reset. The immutable `ModuleRanking`
is installed once in `Compilation.create` after the initial module-root table
is populated and before analysis; no replacement hook in Compilation is needed.
Later builtin creation adds a new file/root rather than replacing an existing
file's ranked ownership. This audit covered file initializers, both existing
ownership assignments in `computeAliveFiles`, and builtin-root insertion.

Source-less unit kinds retain the stable `.unknown` rank and can be indexed.
A file with absent `File.mod` instead yields an internal transient-null rank.
Encountering it disables that tier's index for the rest of the epoch. The old
scan still maps it to `.unknown`, then observes its live rank if ownership
becomes known; a heap never freezes that transient value. The next update can
try a fresh build. Known-file memo allocation remains best effort as before.

Authoritative map allocation failures retain their original error behavior.
Optional index preparation reserves both arrays before filling; append reserves
both before changing their lengths. An auxiliary allocation failure clears
partial lengths and disables the index, preserving committed map membership.
Disabled epochs do not retry allocation on every pick. Removal allocates
nothing. The old strict-argmin scan is retained as the live production fallback
and as the independent selection rule used by the standalone sequence oracle.

## Bounded verification

All raw source edits and scratch source copies/mutations/restoration used
`apply_patch`. Generated test binaries, caches, and logs remain under ignored
`build-ready-index/`; none were deleted. Real process inspection preceded the
single whole-compiler check; no other compiler build was running then.

### Parse and standalone production-helper tests

```sh
PROMOTED/zig ast-check src/Zcu.zig src/Zcu/PerThread.zig src/Zcu/ReadyIndex.zig src/Zcu/ReadyIndex.test.zig

ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/gcache \
ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/cache \
PROMOTED/zig test -OReleaseSafe --dep ranking \
-Mroot=src/Zcu/ReadyIndex.test.zig -Mranking=src/Zcu.zig \
-femit-bin=build-ready-index/helper-tests
```

Parse: **4/4 requested touched Zig files checked, 0 failed, 0 skipped**, exit 0.
Final standalone suite: **7/7 tests passed**, exit 0:

1. Tied-rank swap removal selects moved key 8, not chronological key 1; drains
   through empty state while checking the reverse-position invariant.
2. All production rank fields, exact ties, and stable unknown ranks match the
   scan during draining.
3. **4096/4096** deterministic mixed transitions agree with the scan (seed
   `0xcea17ed`, at most 128 live keys): insertion, arbitrary removal, duplicate
   put, requeue, and rank-epoch resets every 127 steps. Every live node's map
   position, reverse position, and priority is checked at each transition.
4. Transient unknown disables the heap until invalidation; ownership becoming
   known still changes the live scan's winner; an epoch rebuild sees rank changes.
5. **2/2 preparation allocation sites** deliberately fail; the disabled empty
   index does not retry and recovers after invalidation.
6. **2/2 append allocation sites** deliberately fail after the authoritative map
   commits its fifth key; all five keys remain, and fallback selects new key 99.
7. A finite structural-work check over 2048 keys counts calls to the production
   comparator: heapify **4540**, **2048 peeks / 0 comparisons**, then
   append/remove/drain **45779**. The old drain scan's **2,096,128** is the
   derived `n*(n-1)/2` comparison count, not a measured compiler execution.

These are real helper executions, not new-compiler runtime measurements.
They do not establish wall-time speedup, whole-compiler allocation behavior,
parallel Sema, or race freedom.

Two initial test-module wiring attempts failed before a valid test executable:
using `Compilation/ModuleRanking.zig` directly as its module root rejected its
relative imports outside that root; separately importing the helper while
using `Zcu.zig` as ranking root assigned the same file two module owners. The
final test imports both through Zcu's exports, retaining the actual production
module root and avoiding duplicate ownership. These setup failures are not
counted as passing tests or compiler defects. They also mean any older WIP
claim about unrestricted import roots needs fresh, properly wired controls.

### Negative control and restoration

Scratch files `build-ready-index/negative-control/ReadyIndex.zig` and its sibling
test were created through `apply_patch`. The helper was an exact production
copy. The test differs only by importing its heap factory from a separate
`heap` module; `ranking` still supplies the real production comparator.

Run shape (the actual three output names were `pristine-tests`,
`sabotaged-tests`, and `restored-tests` respectively):

```sh
ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/gcache \
ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/cache \
PROMOTED/zig test -OReleaseSafe --test-filter 'swap removal' \
--dep ranking --dep heap \
-Mroot=build-ready-index/negative-control/ReadyIndex.test.zig \
-Mranking=src/Zcu.zig \
-Mheap=build-ready-index/negative-control/ReadyIndex.zig \
-femit-bin=build-ready-index/negative-control/pristine-tests
```

PRE pristine: **1/1 passed**, exit 0. The scratch-only sabotage replaced
`self.nodes.items[moved_heap_index].map_index = map_index;` with retention of
`last_map_index`. RED: **0/1 passed**, exit 1, `expected 0, found 1` and
`TestExpectedEqual`. Thus the test detects a lost current-map tie repair.
After restoring that exact line with `apply_patch`, the production and scratch
helper SHA-256 both equal
`ea0f1fd7852b79fc2711d43b1aa0650a832e0a6b966086bc69830a8f524070ea`.
RESTORED: **1/1 passed**, exit 0. All three binaries remain available; no
sabotage was ever applied to production source.

### One whole-compiler Sema-only check

```sh
ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/gcache \
ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/sema-cache \
ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt \
/usr/bin/time -v -o build-ready-index/sema-only.time \
PROMOTED/zig build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ \
--dep aro --dep build_options \
-Mroot=src/main.zig -Maro=lib/compiler/aro/aro.zig \
-Mbuild_options=build-p005/config.zig \
> build-ready-index/sema-only.stdout 2> build-ready-index/sema-only.stderr
```

Result: **1/1 authorized Sema-only command exited 0**. Wall **39.82 s**,
maximum RSS **1,389,468 KiB**; stdout **0 bytes**, stderr **336 bytes**, consisting
only of the existing thread-topology informational report. No compiler binary
was emitted. Logs and `/usr/bin/time` output remain at the named paths.

This uses the real existing `build-p005/config.zig`, SHA-256
`c6439728291a516712ea8b4884cdc50b467438c9748a91c064677cf9acad04d8`:
`have_llvm=true`, `dev=.core`, threaded I/O, direct value interpretation,
and **`enable_debug_extensions=false`**. It is a bounded source type-check,
not evidence of the required debug-extensions configuration for a newly built
working/release compiler. The safe full build recipe and its independent
verification remain the coordinating maintainer's next step.

## PRE -> POST SHA-256

| Source | PRE | POST |
| --- | --- | --- |
| `src/Zcu.zig` | `0769ce6d13b132043321de83a8bdbd77a8f456c9f913aaa8a046127422a647fe` | `d9e93263637ae4bde3c433df20ad4a3de35aa2a35d4334a84d1ca9a0b6fb6709` |
| `src/Zcu/PerThread.zig` | `946f0daa3c103ff913749d55e7dce6bb61ea7dc95b284857a4f3bae2243c5f87` | `0dd3bebfef5820e436f5dc53e9aa5110378ea03bc3481a901f56d02de3c325b8` |
| `src/Zcu/ReadyIndex.zig` | absent | `ea0f1fd7852b79fc2711d43b1aa0650a832e0a6b966086bc69830a8f524070ea` |
| `src/Zcu/ReadyIndex.test.zig` | absent | `f41de8bae113784b0215acba8d8b9f8f27b6abad5d4878368aa69f86d4b7b12e` |
| `src/Compilation.zig` | `dae1cb62149c21fc0b783992b799dcfeb6e3ff4b48ac76b723e5cd04ae497d76` | unchanged |

Final read-only audit commands included `git diff -- src/Zcu.zig
src/Zcu/PerThread.zig`, `git diff --check`, `git status --short`, `sha256sum`
over these owners and the promoted binary, and `rg -n` over ready-map mutation,
file-rank memo, module-ranking assignment, file ownership assignment and
module-root insertion sites. The tracked changes in this wave are Zcu
**134 added / 49 removed lines** and PerThread **6 added / 1 removed line**;
the new helper/test/receipt are additional untracked paths, not included in
those two tracked-file counts. No unrelated dirty work was overwritten.

## Remaining verification boundary

Source review, helper behavior, and one existing-config Sema-only check are
complete for this finite wave. End-to-end indexed compiler sequence equivalence,
incremental update behavior, both-mode compiler execution, function-tier/cycle
runtime coverage, real workload time/RSS, full compiler build and harness,
race detection, promotion, packaging and publication remain **UNRUN / UNKNOWN
in this wave**. The tier/default/cycle preservation claims above are source
inspection, not substitutes for those executions. No result here changes the
default to layered or claims completion of the full compiler enhancement.
