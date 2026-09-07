# Lost update invalidation — executed RED / restored GREEN, 2026-09-07

The omitted update-entry invalidation is detected with retained memo count 98,
before the second update processes or selects work. The mutant builds, then
panics with `READY_EPOCH invalidation missing` (compiler ABRT / runner 1).
After exact source restoration and a separate rebuild, the same fixture passes
all four expected outcomes, with 2,095/2,095 same-live-state index/scan agreements
and successful reset checks for populated memo counts 98 and 3.

This closes one missing-reset control. It does **not** demonstrate stale-rank
selection or independently negative-control each index-state predicate.

Direction: Daniel Campos Ramos. Root coordinator performed materialization,
native patch/restoration, builds and runs. A cooperating OpenAI Codex senior
partner prepared this receipt by read-only source/record/hash/log inspection;
no compiler or test was invoked during this documentation task. The
[original preparation](READY_INDEX_REMAINING_CONTROLS_PREPARATION_2026-09-07.md)
and its dated manifest correction remain historical, unchanged records.
The [lost-append receipt](READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md) is a
separate control, not the source of this run's measurements.

## Source identity and precise observer reach

`CONTROL` below denotes the exact repository-relative directory
`build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/`.
Its authority is the frozen `build-ready-shadow-2026-09-06/source/`: commit
`0399d2b19b71ed865cc2e6d5e21224f124e373db` plus the existing clean-shadow
instrumentation. The only mutant delta is one hunk, +0/-1 line, deleting
`zcu.invalidateReadyRanks();` from `src/Zcu/PerThread.zig:198` at update entry.
The independent before-record, combined predicate, panic and after-record remain.

The complete relevant update-entry body and `Zcu.invalidateReadyRanks` were read.
The latter normally clears the file-rank memo and invalidates both auxiliary
indexes. The retained observer checks, in order:

```zig
if (zcu.file_rank_memo.count() != 0 or
    zcu.ready_indexes.funcs.state != .invalid or
    zcu.ready_indexes.other.state != .invalid)
    @panic("READY_EPOCH invalidation missing");
```

At the actual mutant failure, the first operand is true: memo count is 98.
The `or` expression short-circuits. Both index-active values were logged true,
but **neither index-state operand was independently evaluated to cause this RED**.
Conversely, reaching `reset_checked` in the restored layered update means the
combined check passed; `before_memo=98` in that after-record is the saved pre-reset
count, not a claim that 98 entries remain afterward.

The failure occurs before this update's AstGen/liveness processing and before
any new selection. Thus it catches the missing reset at its seam; it does not
prove that a stale-rank selection would otherwise have occurred. The rest of
the ownership/liveness code and the original selection scan are unchanged.

The complete clean-to-overlay diff matches preserved
[source.diff](../../build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/source.diff)
byte-for-byte. The exact native
[forward](../../build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/forward.patch)
and [reverse](../../build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/reverse.patch)
packets are retained with the mutant artifact/logs; the coordinator restored
the original line using the native reverse patch, not a destructive rollback.

```text
cd64130f322746898888216d3f809b77c831b996a4c9cc6481b8c1a8e69fb50b  clean/restored src/Zcu/PerThread.zig
efdaa4efad9c00ff2bc14c724e7fa2753e8762ad50b836879193a7aaa0d02f43  mutant overlay src/Zcu/PerThread.zig
2fc8246827c0861b3441070a0b740a753be9dc0e36b3653d69e54fa5d26d54c9  CONTROL/source.diff
9ed78c107f0471938423933aec36e42545e214c8f8a0cb3162b231782b23a49f  CONTROL/forward.patch
563dc4d94ec3c905558f3482756435a6b4e0cf9a65fe169ed6acd649ee001251  CONTROL/reverse.patch
```

Root recorded 21,931 independent-inode files, exact path-set equality and one
changed owner at materialization; restoration records zero changed owners.
This receipt independently verified **21,931/21,931 current restored hashes and
zero path-set differences**, retaining whole filenames after the checksum's
two-space separator. The frozen, overlay and restored owner inode pairs are
distinct. The full clean bank's SHA-256 is
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
No new source copy, mutation or restoration was performed by this audit.

## Builds, input seals and launch limits

Both builds returned 0 with `-Doptimize=ReleaseSafe`, `-Dtarget=native`,
`-Dcpu=baseline`, LLVM, debug extensions and logging enabled. Complete generated
options files confirm `.full`, LLVM and both debug/log booleans true. They use
the existing release config and system LLVM 21; baseline CPU is not portable
packaging or a hermetic build. Both binaries were hashed without invoking them.

| Root-executed stage | 2026-09-07 UTC | Exit | GNU time wall / peak RSS KiB |
| --- | --- | ---: | --- |
| Mutant source/input seal | 01:46:24.874, before build | — | — |
| Mutant build | 01:46:24.885–01:56:52.206 | 0 | 10:27.31 / 6,518,080 |
| Mutant fixture | 01:58:22.323–01:58:30.641 | runner 1; compiler ABRT | 0:08.17 / 681,044 |
| Source restoration/input seal | 02:00:17.822, before restored build | — | — |
| Restored build | 02:00:17.837–02:10:57.405 | 0 | 10:39.54 / 6,538,340 |
| Restored fixture | 02:12:41.774–02:12:47.673 | 0 | 0:05.76 / 382,360 |

Unlike the earlier lost-append capture, **both builds here have pre-build
external-input seals**. The mutant seal is in `ROOT_MATERIALIZATION.json`;
the restored seal is in `ROOT_SOURCE_RESTORATION.json` and
`ROOT_RESTORED_BUILD_PRE.json`. All four sealed inputs still match. Launcher
intervals and GNU time durations are distinct recorded measurements, not
normalized to each other. All timings are functional observations under
concurrent orchestration, not performance comparisons.

```text
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/zig -> PROMOTED/stage3-046d6833/bin/zig
a5bd5321ba297aaa4099b96b3d2d9b1831af4e5e0d9b695d15cc7ef38c922678  build-release-2026-09-06/config.h
a19e41135d40ac2b74e0e9cbcfa429cc711e2858fb0fb07bc2a80514f39a1676  build-release-2026-09-06/zigcpp/libzigcpp.a
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
8d6e14fb9983662aa1d19ebf5b40f4fed5f0fc635166bdb405d4a076f323cc8d  CONTROL/mutant-stage3/bin/zig
be43cd539ca81841f30d5f2d727a8b1d54222a7d1f3562398c42757bbaff82cd  CONTROL/restored-stage3/bin/zig
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  build-ready-runtime/runner-completeness/bin/repaired-restored
77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027  build-ready-runtime/zig-under-test
7a5c30ad5e38e61f013ba86872846f1749dc42729f0a7b3e63df34a0f003ce56  build-ready-runtime/fixtures/change_module
7a7f844a96c0deef3871360c6d40db25da017614db2ee302bcc94f7ce3b50f5d  CONTROL/mutant-build-cache/c/12c379110e1eb5aa6865eb9df67b1779/options.zig
32ef0b3b646e1086a708e4471a2b2a981c3c7f7b8ab0005d7659d4e0b01d5a5b  CONTROL/restored-build-cache/c/301c85d3544c949f99bbce07de044146/options.zig
```

Recorded versions are `0.16.0+cgm.0399d2b19b.shadow-lost-invalidation-mutant`
and `0.16.0+cgm.0399d2b19b.shadow-lost-invalidation-restored`. Run records
directly include the respective absolute candidate, `READY_INDEX_ORDER=layered`
and sealed `ZIG_LIBC` overrides. These are explicit launcher settings, **not raw
child execve or /proc environment captures**; inherited environment is not dumped.
The sealed wrapper appends `--analysis-order=layered -j1 --intern-partitions=2`
only to `build-exe`, preserving probe behavior and the runner's IPC. Both runs
use the same repaired runner, unchanged native `change_module` fixture,
`--preserve-tmp`, and `--debug-log zcu --debug-log zcu_deps`, with a 180-second
timeout and 10-second kill-after. Neither actually timed out. Full cwd/argv
are in the build/run JSON and time records; no missing environment is guessed.

## Independent raw-log recount

| Observed scope | Mutant | Rebuilt restored |
| --- | ---: | ---: |
| Ordered fixture labels reached / expected | 2/4 | 4/4 |
| Before / reset-checked records, including compiler_rt | 3 / 2 | 5 / 5 |
| Populated-memo before / successful reset checks | 1 / 0 | 2 / 2 |
| Same-state agreements / comparisons | 2,086/2,086 before failure | 2,095/2,095 |
| Function / other comparison records | 1,670 / 416 | 1,672 / 423 |
| Non-singleton / nonzero-chosen comparisons | 2,076 / 48 | 2,080 / 52 |
| Named panic / optional-index fallback records | 1 / 0 | 0 / 0 |
| Returned ownership-abort records | 0 | 1 |

In [mutant stderr](../../build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/mutant-logs/layered.stderr),
the second label is at line 345724; line 345726 logs memo=98 and both indexes
active. The named panic follows at 345730, with compiler ABRT reported at
345750. There is no second-update reset-checked or selection record. The stack
points to the preserved observer in mutant `PerThread.zig:202`. Earlier equal
comparisons do not make this aborted fixture GREEN. This is the intended
instrumented compiler failure, not a runner-checker failure or expected diagnostic.

In [restored stderr](../../build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation/restored-logs/layered.stderr),
all four labels occur in order at lines 2, 345724, 346436 and 346995. Populated
before/reset pairs are 345726/345727 (98) and 346438/346439 (3). The five total
epoch pairs include one initial compiler_rt update plus four fixture updates;
do not claim five fixture updates. The double-ownership abort at 346993 is
followed by the final successful no-ownership update. The repaired runner
accepts three expected diagnostic outcomes (including the existing module-name
compile logs) and one successful empty-stdout outcome. There are zero unequal
comparisons, panic records, warnings or skipped-target records in this run.

## Sealed evidence and audit commands

All 11 `ROOT_*` records below were read completely. Both generated options
files, build stderrs and four time files were read completely. Empty stdout
files were confirmed. Both entire runtime stderrs were streamed for anchored
markers and hashed, with relevant failure/recovery context inspected; this is
not a claim of manually reading every debug line. All 12 unique artifact/input
facts and 12/12 raw log hashes agree with their records; no count disagreement
was found. The following JSON paths are relative to `CONTROL`:

```text
979266d1047a479d8ec4724ae06bc7ff33dea11dc1443a1770355c75bfc35289  ROOT_MATERIALIZATION.json
255accdf6c374a5450670a852b9367ff64f8c165f24046d7a7b62b2ab25acac6  ROOT_MUTANT_BUILD.json
dd766eedbd8ddc4c8d79af9a44696083b7d9ca4e57fbf7a3496a1d2dfe7a7107  ROOT_MUTANT_EXECUTION_PRE.json
afed6349a121842c032130e1dd0d1ff0344ca96eee63d8491d3e1f44230112bb  ROOT_MUTANT_RUN.json
19c2ce3242e22ba6f31a024beb38e2acc9c971d681a23be0388bc86761157778  ROOT_MUTANT_DISCRIMINATION.json
3c1276f3cb3c5b9f16c268153c6f3a56b75ace06183d8a3359d2cf8f69ec8b69  ROOT_SOURCE_RESTORATION.json
69a7404af678fda1eea162176069c09a2192d7e902ba1688c0667bfe30d2b9b8  ROOT_RESTORED_BUILD_PRE.json
18b49d8481985e5d0d32a7499b1499c1bb7f93ee4d7fb0b2515fd6b1f0e0abd6  ROOT_RESTORED_BUILD.json
239b96209538abdf8b70ef08b1574196f74b202daf271d860d214a0ee5e6807f  ROOT_RESTORED_EXECUTION_PRE.json
b3ea51b77e06d8ac1b4edae462fb4b736f9954c68556f5b96132c852a2b3fd76  ROOT_RESTORED_RUN.json
015696e8dc164e7a2bf6626feb6568697cca48e07970c9c4672de8dbb9501567  ROOT_RESTORED_DISCRIMINATION.json
```

The four stdout files are empty, SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Both build stderrs are three lines / 615 bytes, SHA-256
`ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22`.
The remaining six raw-log hashes, relative to `CONTROL`, are:

```text
9e32cbeaae523303e77bb18c4763c94a8cbb1c588c417836fa146d1aeb8a47ad  mutant-logs/build.time
9e377d86020e1bdbe48c6609159941768a176be573fea9ca940357356944afb3  mutant-logs/layered.time
7601f5db37d138610d5833e5a0b8301a0e6d0ef46b1ffe0573c95cb735afa28c  mutant-logs/layered.stderr
1b7b74d0eeb80abd5a3fc5c4089d87c9f6a4c14727ccf19f3cc35c4cb379ae86  restored-logs/build.time
a8e1486483cc2308c96fb99fb6ac443149e48b19a89609a0467be13c590724dc  restored-logs/layered.time
1d30e9ebb779c51892e82a9b1a141a275cbc5cd559b86135174a8473280e5777  restored-logs/layered.stderr
```

Runtime stderrs are 28,657,725 bytes / 345,750 lines (mutant) and 28,940,438
bytes / 347,601 lines (restored). All 12 raw logs total 57,604,019 bytes.
Read-only recount example from the fork root:

```sh
invalidation_dir=build-ready-shadow-2026-09-06/remaining-controls/lost-invalidation
awk '
/^info\(status\): update:/ {updates++; print FILENAME ":" FNR ":" $0}
/^debug\(zcu\): READY_EPOCH / {print FILENAME ":" FNR ":" $0}
/^debug\(zcu\): READY_SHADOW / {
    comparisons++; split($5,a,"="); split($6,b,"=");
    if(a[2]!=b[2]) mismatch++;
}
/^thread [0-9]+ panic:/ {panics++; print FILENAME ":" FNR ":" $0}
ENDFILE {
    printf "%s updates=%d comparisons=%d mismatches=%d panics=%d\n",FILENAME,updates,comparisons,mismatch,panics;
    updates=comparisons=mismatch=panics=0;
}' "$invalidation_dir/mutant-logs/layered.stderr" "$invalidation_dir/restored-logs/layered.stderr"
```

Other actual commands were bounded `sed`/`rg`/`jq` reads, `sha256sum --check`,
`wc`, `stat`, full-file `diff`/`cmp`, complete-path `awk` manifest mapping and
NUL-separated `find`/`sort`/`comm` path-set comparison. Only this new receipt
and additive root README/crown PLAN status entries were authored via `apply_patch`.
No source, prior receipt, scratch evidence/manifest, artifact, Git state or
station pointer was changed; no compiler, test, network, child agent or cleanup
operation ran. The separate OOM preparation packet remains unchanged.

Remaining ceilings: independently broken index-state predicates, preparation/
append integration OOM, default-entry control, wider concurrency, exhaustive
tier/cycle coverage and performance are not established here. Zero fallback
records are no OOM witness. This is neither a new default nor release/promotion
evidence, and it makes no parallel-Sema claim.
