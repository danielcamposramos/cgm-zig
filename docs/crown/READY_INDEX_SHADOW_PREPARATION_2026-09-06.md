# Clean ready-index shadow preparation — 2026-09-06

Status: **scratch source prepared; runtime reach UNRUN / UNKNOWN**. This wave
implements only the clean instrumentation in section 2 of
`READY_INDEX_RUNTIME_VERIFICATION_PACKET_2026-09-06.md`. No mutant, forced-OOM
variant, compiler build, Sema check, fixture execution or promotion occurred.

Direction: Daniel Campos Ramos through the coordinating maintainer's bounded
grant. Preparation: GPT-6 (OpenAI Codex), working as an AI partner.
Upstream-Status: not-filed-policy. Production source, existing fixtures/wrappers,
prior receipts and concurrent maintainer work were not edited.

## Snapshot identity and isolation

The source snapshot is
`build-ready-shadow-2026-09-06/source/`; its generated evidence lives in sibling
`build-ready-shadow-2026-09-06/audit/`. Both the new root and this receipt were
absent before preparation. Read-only Git inspection resolved the requested
commit as `0399d2b19b71ed865cc2e6d5e21224f124e373db` and showed no difference
between that commit and tracked production `src`, `lib`, `build.zig` or
`CMakeLists.txt`. The snapshot therefore includes the committed logging-gate
correction; it does not depend on unrelated dirty documentation or untracked
receipts. It contains no `.git` directory.

Exact extraction and initial manifest commands, from the fork root:

```sh
mkdir -p build-ready-shadow-2026-09-06/source build-ready-shadow-2026-09-06/audit
git archive --format=tar --output=build-ready-shadow-2026-09-06/audit/source.tar \
    0399d2b19b71ed865cc2e6d5e21224f124e373db
tar --extract --file=build-ready-shadow-2026-09-06/audit/source.tar \
    --directory=build-ready-shadow-2026-09-06/source
git ls-tree -r --full-tree 0399d2b19b71ed865cc2e6d5e21224f124e373db \
    > build-ready-shadow-2026-09-06/audit/git-tree.txt
rg --files --hidden --no-ignore -0 build-ready-shadow-2026-09-06/source \
    | sort -z | xargs -0 sha256sum > build-ready-shadow-2026-09-06/audit/pre.sha256
```

The archive, Git tree and extracted snapshot each contain **21,931/21,931
regular files**. A read-only inline Python audit verified every archived file
against its Git blob ID using SHA-1 of `blob <byte-length>\0<contents>`, then
compared each extracted file's bytes to the archive and checked exact path-set
equality. Final result: **21,928/21,931 files byte-unchanged**, with exactly the
three authorized scratch Zig owners changed. There are no symlink or missing
file exceptions. This audit did not write source; its JSON output is retained
as `audit/snapshot-validation.json`.

`stat` comparison proved **21,931/21,931 scratch files have different
device/inode pairs from their production counterparts**, with 0 shared-inode
files in that denominator. The edited owners' pairs were:

| Owner | Production device:inode | Scratch device:inode |
| --- | --- | --- |
| `src/Zcu.zig` | `2049:14065450` | `2049:566644` |
| `src/Zcu/PerThread.zig` | `2049:14062624` | `2049:566646` |
| `src/Zcu/ReadyIndex.zig` | `2049:14071211` | `2049:566648` |

## Clean instrumentation and limits

The complete runtime packet and preparation receipt were read before action.
Raw ready-map/index fields, helper state/arrays, wrapper bodies, update abort,
external struct-default insertion, tagged AnalUnit and its formatting inputs
were inspected. `oracle_lib.assert_anchor` verified **12/12 named source
anchors occurred exactly once** before editing. All instrumentation and the
one formatting correction were applied with `apply_patch` only.

The following records all use existing `.zcu` logging, so the existing
`--debug-log zcu` argument suffices. No scope roster, flag or shipping logger
change was introduced:

| Instrument | Scratch source seam and assertion |
| --- | --- |
| `READY_SHADOW` | `Zcu.zig:3505`: compare the real prepared index's selected map position to the original `readyPickScan` in the same live state; panic on mismatch |
| `READY_FALLBACK` | `Zcu.zig:3511`: record real fallback, then call the unchanged original scan |
| `READY_PUT_BEGIN` / `READY_PUT` | `Zcu.zig:3399`: capture active state and old count independently of the append hook; record mode/tier and actual post count/state |
| `READY_NOCLOBBER_BEGIN` / `READY_NOCLOBBER` | Both branches at `Zcu.zig:3430,3444`: same observation around the unchanged reserved-capacity insert and hook; include actual unit tag |
| `READY_REMOVE_BEGIN` / `READY_REMOVE` | `Zcu.zig:3461`: old optional map index, non-last status, membership presence, count and state, before/after original removal |
| `READY_TIER` | `Zcu.zig:3605,3615`: both ready counts at actual function/other selection; panic if other is selected with ready functions |
| `READY_CYCLE` | `Zcu.zig:3647`: actual semantic no-ready fallback, assert both ready counts zero and outdated nonzero; keep `outdated.keys()[0]` unchanged |
| `READY_EPOCH` | `PerThread.zig:195,205`: memo/active-state observation before the unchanged invalidation call; check layered memo empty and both states invalid after it |
| `READY_ABORT` | `PerThread.zig:355`: exact early-abort branch, before setting skip-analysis and returning |
| `READY_DEFAULT_EMPTY` | `PerThread.zig:184`: deferred insertion-mode check at update exit, including early return/error paths; all four index array capacities must be zero and rank memo count empty |
| `READY_EXTERNAL_STRUCT_DEFAULTS` | `PerThread.zig:1522`: immediately before the actual external no-clobber wrapper call, after original map reservations |
| `READY_ENTRY prepare/append` | `ReadyIndex.zig:60,99`: entry before helper guards/allocations, with real state, count and capacities |

The scratch-only `readyAuditIndex` at `Zcu.zig:3385` checks active index lengths
against the authoritative map and verifies each live node's reverse position.
It does not create a second heap, change priorities or modify either structure.
Its short-circuit bounds check precedes reading the reverse table. Disabled or
invalid indexes are not interpreted as complete mirrors.

The packet's seams required no architecture change. Two concrete implementation
details prevent blind spots without changing compiler decisions: before-records
precede original operations, and normal-put/removal after-records use `defer`
so insertion-mode early returns and allocation-error returns are also visible.
An after-record is therefore an observed attempt outcome, **not automatically
a successful insertion**; consumers must use count change and active-before/
after fields. No-clobber checks remain after the committed insertion. Every
new assertion has a preceding path record. No ready members or rank epochs were
manufactured to claim coverage.

The shadow deliberately adds O(n) scan/structural observation work and log I/O.
It is not a benchmark compiler or shipping change. `READY_DEFAULT_EMPTY`
checks heap capacities and memo **count**, not total compiler allocations or
memo allocator history. A type-cycle diagnostic is not a `READY_CYCLE` hit;
a generic layout event is not an external struct-default insertion hit.

## Exact patch and source hashes

`audit/clean-shadow.patch` is the full three-owner unified delta, generated
against `git show 0399d2b19b71ed865cc2e6d5e21224f124e373db:<owner>` with labels
`a/<owner>` and `b/<owner>`. It contains **79 added / 1 removed lines in Zcu,
29 added / 0 removed in PerThread, and 6 added / 0 removed in ReadyIndex**.
The only replaced production statement is the indexed return expanded into
observe/compare/return; the original scan, wrappers' mutations and guards stay.

```sh
git apply --reverse --check --directory=build-ready-shadow-2026-09-06/source \
    build-ready-shadow-2026-09-06/audit/clean-shadow.patch
```

Result: exit 0, no output. This is reverse applicability only: no reverse patch,
mutant or rollback was applied, and no negative-control execution is claimed.

| Owner | Committed PRE / production POST SHA-256 | Clean-shadow POST SHA-256 |
| --- | --- | --- |
| `src/Zcu.zig` | `d9e93263637ae4bde3c433df20ad4a3de35aa2a35d4334a84d1ca9a0b6fb6709` | `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e` |
| `src/Zcu/PerThread.zig` | `0dd3bebfef5820e436f5dc53e9aa5110378ea03bc3481a901f56d02de3c325b8` | `cd64130f322746898888216d3f809b77c831b996a4c9cc6481b8c1a8e69fb50b` |
| `src/Zcu/ReadyIndex.zig` | `ea0f1fd7852b79fc2711d43b1aa0650a832e0a6b966086bc69830a8f524070ea` | `ea21a609b71076d59ebc8268f46418e42233475f19f15a6a61b859ff21708e23` |

Production and snapshot `src/main.zig` both remain
`a9d0b4ad425d333271edcd88dd4359bcfec4885ef2545f796b1fee298b6024a5`.
The five prepared fixture hashes and two wrapper hashes were rechecked and
match the prior preparation receipt; none were copied again or modified.

| Retained artifact in `audit/` | SHA-256 |
| --- | --- |
| `source.tar` | `e2b4ed9508236c681db397ffd91167dccf9949ca5ac17d427210c7b1dd0e554d` |
| `git-tree.txt` | `c0e63764bb9c22698d620b83686d86903d4de87e4b3aa1d9a85cfad0df0bfd06` |
| `pre.sha256` | `a1c710216ea9a0312a9204621eef66350ea44394ae063e452d60857b66ea4bf3` |
| `post.sha256` | `5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44` |
| `clean-shadow.patch` | `4120b797d58e2307ae4198bddbb2e2b3d4eab5a400b5cd9d5c657fced0ead547` |
| `snapshot-validation.json` | `82ff70a324caf1d91f73fe98f8ab08063daeb80567b187858221d14a38d01eab` |

## Permitted checks and handoff

```sh
PROMOTED/zig ast-check \
    build-ready-shadow-2026-09-06/source/src/Zcu.zig \
    build-ready-shadow-2026-09-06/source/src/Zcu/PerThread.zig \
    build-ready-shadow-2026-09-06/source/src/Zcu/ReadyIndex.zig
PROMOTED/zig fmt --check \
    build-ready-shadow-2026-09-06/source/src/Zcu.zig \
    build-ready-shadow-2026-09-06/source/src/Zcu/PerThread.zig \
    build-ready-shadow-2026-09-06/source/src/Zcu/ReadyIndex.zig
```

Final result: **3/3 requested files parsed, 0 failed, 0 skipped; 3/3 format
checks passed**, exit 0. The first format check named Zcu only; one tuple's
spacing was compared against `fmt --stdin`, corrected via `apply_patch`, and
the exact checks rerun. No broader formatting sweep occurred.

Sema/type compatibility of the new observer expressions, emitted logs, actual
wrapper/index/default/epoch/tier/cycle reach, selection agreement, negative
controls and OOM behavior remain **UNRUN / UNKNOWN**. Parse is not type-checking.
The coordinator's candidate build occupied the compiler lane throughout this
preparation; no compiler build or Sema work overlapped it.

For a later authorized build, use `source/` as the compiler source root, retain
the coordinator's ReleaseSafe/debug-extensions/logging/baseline-CPU recipe,
explicitly supply the shadow version string (the archive has no Git metadata),
and use separate repo-local outputs/caches. Reuse the existing
`build-ready-runtime/incr-check`, fixtures and wrappers, setting the explicit
candidate environment variable to the subsequently verified shadow binary.
Use new log destinations and `--preserve-tmp`. Those commands are deliberately
not executed by this source-preparation handoff. No mutant/OOM preparation,
deletion, Git mutation, production patch, promotion or publication occurred.
