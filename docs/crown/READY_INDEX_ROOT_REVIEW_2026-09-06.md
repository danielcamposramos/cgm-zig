# Ready-index integration review — 2026-09-06

Daniel Campos Ramos directed continuation of the compiler enhancements. GPT 6
Astra coordinated this wave; a cooperating Codex implementation lane authored
the index, and a separate Codex reviewer independently challenged it. This is
source acceptance, not release acceptance.

## Decision

Accept the four source/test owners identified in
`READY_INDEX_2026-09-06.md` for the candidate-build workflow. The independent
review found no blocking correctness defect in its bounded source audit. Root
also read the tracked integration diff, complete new helper and test, and the
complete 254-line implementation receipt. No default-order change or parallel
Sema is being introduced.

The authoritative maps retain membership. All three ordinary puts, four
preallocated insertion groups (five units), and two removal sites reach the new
wrappers. The index repairs both heap relocation and the moved map key's tie
priority. Its optional allocation failures disable only the index. Rank memo
and indexes are invalidated before the update can change file ownership; a
transiently absent owner uses live scan fallback for that epoch. Insertion,
function-first scheduling, and dependency-cycle fallback remain in place by
source inspection.

The implementation lane records four parse checks, seven helper tests including
4096 mixed transitions, four allocation-failure arms, a scratch negative
control with checksum-verified restoration, and one whole-compiler Sema-only
check. Root is not relabeling those author-run checks as independent executions.
The reviewer ran no builds or tests. Root independently checked the diff's
whitespace and read the evidence; first-wave status-tool tests were separately
rerun by root, as recorded in the coordinating work.

## Objection retained for release verification

The seven tests instantiate the production heap and comparator, but operate a
separate test map. They do not call the real `readyPutKey`,
`readySwapRemoveKey`, `readyPick`, `invalidateReadyRanks`, or update loop.
Removing a production append hook or update invalidation could leave all seven
tests green. No helper-only result closes that integration gap.

The candidate still needs actual compiler scheduling and incremental-update
verification, including indexed/scan selection agreement, aborted update and
recovery, tier/cycle execution, and allocation fallback. Actual workload time
and RSS remain unknown. Comparison counts in the helper receipt are not a
compiler speed measurement, and cannot justify changing the default.

## Frozen identities and next boundary

The source identities accepted are the POST values in the implementation
receipt: Zcu `d9e93263637ae4bde3c433df20ad4a3de35aa2a35d4334a84d1ca9a0b6fb6709`,
PerThread `0dd3bebfef5820e436f5dc53e9aa5110378ea03bc3481a901f56d02de3c325b8`,
helper `ea0f1fd7852b79fc2711d43b1aa0650a832e0a6b966086bc69830a8f524070ea`,
test `f41de8bae113784b0215acba8d8b9f8f27b6abad5d4878368aa69f86d4b7b12e`.
Compilation remains unchanged. The implementation receipt SHA-256 is
`e6ea2828b7ef226a3382e78c17dc4c7079c4869bc6ab278f56cc2c75255370ea`.

The existing promoted compiler is unchanged. The candidate must use the
corrected ReleaseSafe/unstripped/debug-extensions recipe and a fresh output
prefix. Packaging, promotion, and online synchronization follow verification;
this source acceptance does not claim any of them already happened.

## Root formatting and independent helper rerun

Root's `PROMOTED/zig fmt --check` over the four touched Zig files returned 1,
naming only `ReadyIndex.test.zig`. Root applied standard `zig fmt` to that one
test, then the same four-file check returned 0. Production source stayed at the
accepted hashes; the mechanically formatted test now has SHA-256
`2527467d547d052ab10c904f885f84dfc50efa804f938ebb6abcbbb6a768715e`.
The sealed author receipt remains unchanged and refers to its earlier bytes.

Root independently reran the complete seven-test suite on the formatted test:

```sh
ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/gcache \
ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-index/root-test-cache \
PROMOTED/zig test -OReleaseSafe --dep ranking \
  -Mroot=src/Zcu/ReadyIndex.test.zig -Mranking=src/Zcu.zig \
  -femit-bin=build-ready-index/root-helper-tests
```

Exit 0, 7/7 tests passed, 4096/4096 mixed transitions agreed with the scan.
Comparator counts reproduced 4540 for heapify, zero for 2048 peeks, and 45779
for append/remove/drain. This is an independent helper rerun, not the missing
actual-compiler integration evidence. No production-source change or second
whole-compiler Sema-only run was needed for whitespace in a sister test.
