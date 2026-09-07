# Default helper entry — executed discrimination / restored GREEN, 2026-09-07

The same deliberately instrumented compiler fails with
`READY_DEFAULT_ENTRY prepare` under explicit layered order, but passes the
three-update native fixture under both explicit insertion and omitted order.
After exact source restoration and a separate compiler rebuild, layered order
passes all three expected outcomes with 2,083/2,083 same-live-state index/scan
agreements, 2,083 prepare entries and 9,447 append entries.

This establishes the bounded default-entry control, not an independently armed
append-entry negative control: the earlier prepare panic masks that tripwire.
The corrected distinction between selection attempts and completed selections,
the optimized stack-frame limitation, and two launcher corrections are retained
below. No performance, OOM, release or promotion claim follows.

Direction: Daniel Campos Ramos. Root coordinator performed materialization,
native patch/restoration, builds and runs. A cooperating OpenAI Codex senior
partner independently inspected source, records, hashes and full-stream log
counts for this receipt, without invoking a compiler or test. The
[preparation and dated full-path correction](READY_INDEX_REMAINING_CONTROLS_PREPARATION_2026-09-07.md)
and all execution records remain unchanged. This is a separate control from
[lost append](READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md) and
[lost update invalidation](READY_INDEX_LOST_INVALIDATION_CONTROL_2026-09-07.md).

## Source identity and exact discrimination

`CONTROL` denotes the repository-relative directory
`build-ready-shadow-2026-09-06/remaining-controls/default-entry/`.
The frozen authority is `build-ready-shadow-2026-09-06/source/`: commit
`0399d2b19b71ed865cc2e6d5e21224f124e373db` plus the existing clean-shadow
instrumentation. Only `src/Zcu/ReadyIndex.zig` differs in the mutant:
two hunks, +12/-6 lines. Its prepare and append entry debug records are replaced
by local void thunks that panic with the corresponding named message:

```zig
const EntryTripwire = struct {
    fn hit() void {
        @panic("READY_DEFAULT_ENTRY prepare");
    }
};
EntryTripwire.hit();
```

The append replacement uses `READY_DEFAULT_ENTRY append`. This is the
previously approved compile-valid implementation adaptation; the void thunk
leaves the following body syntactically reachable. There is no new production
knob, allocator change, fabricated ready member or copied scheduler.

The complete helper and relevant wrapper/observer bodies were read.
Frozen `Zcu.zig:3491` returns immediately for insertion before calling
`prepare`; `findOutdatedToAnalyze` logs `READY_TIER` **before** selection and
logs the ordinary selected unit **after** it returns. The independent deferred
observer at frozen `Zcu/PerThread.zig:183` checks all four auxiliary index
capacities and the rank-memo count on insertion exits, including early returns.
Those observer placements are unchanged in the mutant.

The full clean-to-overlay diff agrees byte-for-byte with
[source.diff](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/source.diff).
The exact native
[forward](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/forward.patch)
and [reverse](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/reverse.patch)
packets, independent overlay, mutant binary and logs remain preserved.

```text
ea21a609b71076d59ebc8268f46418e42233475f19f15a6a61b859ff21708e23  clean/restored src/Zcu/ReadyIndex.zig
cb1adde9972238f2289c28702e7045326cec06745a28949efcef37523d295008  mutant overlay src/Zcu/ReadyIndex.zig
16ba1007e9200cbccae8ad76253f43aac1662dd3df17c32ced4d23dc5d168d41  CONTROL/source.diff
5c9ed9b0f91c8eecc98c4b7cb186518c0a06acf7931ac35bba29e9e43ae9ec4a  CONTROL/forward.patch
9ca926f48b36407acd30ca1ac2cf252c4c93996e41b096a0b77f03f9779c7e82  CONTROL/reverse.patch
```

Root recorded 21,931 independent-inode files, exact path-set equality and one
changed owner at materialization. The native reverse patch restored that owner.
This audit independently rechecked **21,931/21,931 current restored hashes,
21,931/21,931 independent frozen/restored inode pairs, and zero path-set
differences**. Both copies match the frozen bank. Whole filenames after the
checksum's two-space separator were retained, including spaces. The frozen,
overlay and restored helper inode identities are respectively `2049:566648`,
`2049:1049577` and `2049:1356792`; the clean/restored file is 7,784 bytes,
the preserved overlay 7,721 bytes. The bank
`build-ready-shadow-2026-09-06/audit/post.sha256` hashes to
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
No source copy, patch or restoration was performed during this documentation audit.

## Actual raw-log recount

All four runs use the unchanged native `temporary_parse_error` fixture:
initial empty-stdout success, expected EOF parse error, then repaired empty-stdout
success. Its other five target directives remain commented; no remove-file
directive or foreign-target skip is involved.

| Observed scope | Mutant layered | Mutant insertion | Mutant omitted | Rebuilt restored layered |
| --- | ---: | ---: | ---: | ---: |
| Runner exit / compiler failure | 1 / ABRT | 0 / none | 0 / none | 0 / none |
| Ordered labels reached / expected | 1/3 | 3/3 | 3/3 | 3/3 |
| Ready-tier selection attempts | 943 | 3,029 | 3,029 | 3,025 |
| Completed ordinary selections | 942 | 3,029 | 3,029 | 3,025 |
| Of those: fixture / compiler_rt | 0 / 942 | 2,087 / 942 | 2,087 / 942 | 2,083 / 942 |
| Same-state agreements / comparisons | 0/0 | 0/0 | 0/0 | 2,083/2,083 |
| Prepare / append entry debug records | 0 / 0 | 0 / 0 | 0 / 0 | 2,083 / 9,447 |
| Zero-capacity/memo exit records | 1 | 4 | 4 | 1 |
| Parse-abort / named panic records | 0 / 1 | 1 / 0 | 1 / 0 | 1 / 0 |
| Optional-index fallback records | 0 | 0 | 0 | 0 |

In [mutant layered stderr](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/mutant-logs/layered.stderr),
line 98740 is the first fixture attempt (`funcs=0 other=2 selected=other`),
line 98744 is the named prepare panic, and line 98764 reports compiler ABRT.
The 942 earlier completed selections belong to compiler_rt. No fixture choice
returns and no fixture outcome completes. The single zero-capacity exit at
96825 also belongs to compiler_rt; it is not a completed fixture update.

The original `ROOT_MUTANT_DISCRIMINATION.json` field `ordinarySelections`
counted `READY_TIER` attempts. Its layered value 943 is **superseded as a
completed-selection count**, not silently corrected in that immutable file.
[ROOT_MUTANT_COUNT_CORRECTION.json](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/ROOT_MUTANT_COUNT_CORRECTION.json)
preserves this independent audit finding. The original 943 is valid only as
an attempt count. The ordinary-log recount excludes the separate all-up-to-date
notice (one in failing layered, three in each passing run); all four runs have
zero dependency-cycle fallback records.

The optimized panic's top frame names `Compilation.zig:695:27` while attributing
it to `findOutdatedToAnalyze`; the displayed source line belongs elsewhere.
It is **not reliable helper line attribution**. The exact source mutation,
named panic and preceding real ready-tier attempt identify the control.
This is the intended instrumented compiler failure, not an expected parse
diagnostic or a runner-checker failure.

Explicit insertion and omitted order each reach labels at lines 2, 332087 and
332643 and four zero-capacity/memo exits at 96824, 332085, 332641 and 333202.
The denominator is one compiler_rt exit plus three fixture exits, not four
fixture updates. All five observed values are zero in every such record.
The parse abort at 332640 is followed by the successful repaired update.
Zero old helper-entry logs alone is **not** isolation proof: their emitting
sites were replaced by the tripwires. Successful complete runs, the unchanged
early-return source path and independent zero-capacity observations together
support the bounded default-mode result.

In [restored layered stderr](../../build-ready-shadow-2026-09-06/remaining-controls/default-entry/restored-logs/layered.stderr),
the three labels occur at lines 2, 345683 and 346238. The expected parse abort
at 346236 has `fatal_files=true`, `multi_module=false`,
`failed_imports=0` and `alloc_failure=false`. Recovery completes afterward.
There are zero unequal comparisons, panics, warnings or skipped-target records.
The one default-empty exit at 96825 is compiler_rt, not evidence that the
layered fixture avoided the index. Its 2,083 prepare and 9,447 append records
positively establish live helper reach after restoration. Prepare's earlier
mutant panic still leaves the append tripwire **not independently armed RED**.

## Builds, input seals and launcher corrections

Both full builds returned 0 using `-Doptimize=ReleaseSafe -Dtarget=native
-Dcpu=baseline -Denable-llvm -Ddebug-extensions -Dlog`, the existing release
config and scratch source/lib, with distinct mutant/restored prefixes and
local/global build caches. Complete generated options confirm `.full`, LLVM,
debug extensions and logging. The config selects shared system LLVM 21;
its older header version does not override the explicit build version argument.
This is not a hermetic build or portable-package proof.

| Root-executed stage | 2026-09-07 UTC interval | Exit | GNU time wall / peak RSS KiB |
| --- | --- | ---: | --- |
| Mutant build | 02:17:33.992–02:28:11.236 | 0 | 10:37.22 / 6,525,232 |
| Mutant layered | 02:33:56.178–02:34:02.863 | 1 | 0:06.67 / 677,204 |
| Mutant insertion | 02:34:02.883–02:34:08.727 | 0 | 0:05.83 / 383,936 |
| Mutant omitted | 02:34:08.764–02:34:14.331 | 0 | 0:05.56 / 380,648 |
| Restored build | 02:36:36.642–02:46:26.322 | 0 | 9:49.67 / 6,542,552 |
| Restored layered | 02:47:52.851–02:47:58.300 | 0 | 0:05.44 / 382,004 |

All timings are functional observations under concurrent orchestration, not
benchmarks. Recorded launcher intervals and GNU time durations are distinct
measurements. The four external inputs below were sealed **before both builds**:
mutant materialization at 02:17:33.981 and source restoration at 02:36:36.618.
The restored build uses restored source, not the preserved mutant binary.

```text
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/zig -> PROMOTED/stage3-046d6833/bin/zig
a5bd5321ba297aaa4099b96b3d2d9b1831af4e5e0d9b695d15cc7ef38c922678  build-release-2026-09-06/config.h
a19e41135d40ac2b74e0e9cbcfa429cc711e2858fb0fb07bc2a80514f39a1676  build-release-2026-09-06/zigcpp/libzigcpp.a
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
4a667929acc1d24ab6a9124a199f85fa046c65ea46cf16dfc72a9f2dab494d70  CONTROL/mutant-stage3/bin/zig
0ed3a27e18c66e01e9bf520bd5f48b8725023df035c6c2784cbe11d812f6934f  CONTROL/restored-stage3/bin/zig
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  build-ready-runtime/runner-completeness/bin/repaired-restored
77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027  build-ready-runtime/zig-under-test
3a71bc702bc3b9b548f182b68d4d335ea6427bb6fc9f8107982669679b81bad1  build-ready-runtime/zig-under-test-default
f7a3e2fe43b88dcb117a04b0380ca4b04b630572ed00f9d768e9c76efe2e0fa5  build-ready-runtime/fixtures/temporary_parse_error
a7ba59c73391931ee783f2e9306319bdb3f45816201f75a30174afbe6f1c1663  CONTROL/mutant-build-cache/c/1cac8bfd87a19bc5770f122a54da16e2/options.zig
3b21c5a0a780a576dec46bd1abc2c073692ca7738bd52891fa0d3daf8adc25d0  CONTROL/restored-build-cache/c/bd0179e7320a629a1db5ab62dc86a25c/options.zig
```

Recorded versions are
`0.16.0+cgm.0399d2b19b.shadow-default-entry-mutant` and
`0.16.0+cgm.0399d2b19b.shadow-default-entry-restored`. The binaries were hashed,
not invoked by this audit. All runs use the same repaired runner and fixture,
from `/K3D/GitHub/cgm-zig/build-ready-runtime`, with
`--zig-lib-dir CONTROL/source/lib --preserve-tmp --debug-log zcu --debug-log zcu_deps`
and `timeout --kill-after=10s 180s`. No run timed out. The actual full absolute
cwd/argv and explicit environment settings are in the sealed build/run JSONs.
These are **launcher settings, not independent raw child execve or /proc
environment captures**; the complete inherited environment is not recorded.

Layered/insertion use `./zig-under-test`, their corresponding
`READY_INDEX_ORDER`, and the recorded absolute `READY_INDEX_CANDIDATE`.
Omitted uses `./zig-under-test-default` and explicitly removes
`READY_INDEX_ORDER`. Both wrappers append `-j1 --intern-partitions=2` only for
`build-exe`; only the first adds the selected analysis-order argument.
All runs explicitly set `ZIG_LIBC` to the sealed file. Probe/IPC behavior is
unchanged. The build records separately specify their local/global cache roots.

Two launcher mistakes are preserved, not described as compiler defects:

- `ROOT_PREFLIGHT_PATH_CORRECTION.json`: the first checksum command ran from
  the wrong cwd, so all 41 bank reads failed before copy, patch or build.
  Rechecking the unchanged bank from the fork root passed 41/41.
- `ROOT_RESTORATION_ARGV_CORRECTION.json`: the first restoration launcher had
  already saved discrimination evidence and applied the native reverse patch
  when Node rejected a literal NUL in a `find` argument, before invoking
  `find`. No restoration receipt or compiler was started by that failed
  launcher. The corrected `find -print0` pass rechecked all 21,931 hashes,
  independent inodes and the path set; it did not apply a second source patch.

## Evidence seals and read ceiling

All 17 `ROOT_*` records were read completely across the initial read-only audit
and this restored-result follow-up. Both complete generated options files,
both build stderrs and all six time files were read. Four entire runtime
stderrs were streamed for anchored counts and hashed; relevant failure,
update and recovery contexts were inspected, not every debug line manually.
All 13 unique recorded artifact/input facts and 12/12 recorded runtime log
hashes match; all 18 raw build/run logs were independently hashed.
The JSON paths below are relative to `CONTROL`.

```text
c59871df87c2bebd3ea1e5ea1a857202574b95bf69e1cd6e7c45eb42ce5d7503  ROOT_MATERIALIZATION.json
a39220253aa14a99f92cc07390a4d2dbe4a3003b0ee3d157ebc779beb884306e  ROOT_MUTANT_BUILD.json
b24f0e564f0f8331c99ec9b53f8331807f777148ca61cd2df32c0444c2243358  ROOT_MUTANT_BUILD_PRE.json
82c58b97cc73cbfa6569ed840888481bef87887589849705b1910e2ff065bceb  ROOT_MUTANT_COUNT_CORRECTION.json
63c10bee3509b2593a787c7ca3de75f866787db5d55fcdba4120722e1642dd7c  ROOT_MUTANT_DISCRIMINATION.json
9c50cb30aad8d9638a054926c953f9a75373ce952b4b3ad7384bd8f9682da537  ROOT_MUTANT_EXECUTION_PRE.json
eb9072eb36954e50588b8b9e6d6a246cb6a7eec1a5410d55ee48208109e2f5ed  ROOT_MUTANT_INSERTION_RUN.json
2d6afcdc8718217540658b952e4eac695612227551ec18aeb2b33e8de8b68ea9  ROOT_MUTANT_LAYERED_RUN.json
a99ecc061e6c38b18147bcf7ac0d1468d17b01709cf092140347385cfaa36d54  ROOT_MUTANT_OMITTED_RUN.json
708de5828c0a5c1e564135e045f5428d0788c54361d9e3a514cf3491c8e762fb  ROOT_PREFLIGHT_PATH_CORRECTION.json
fef4c597562ad71cc482f25b84308ea21a63c0be733eef44547a4555c2fc3282  ROOT_RESTORATION_ARGV_CORRECTION.json
2bf84b938142e3db2b475840779bc91b9445ae4ba3f2fa93e816cf51bb40c759  ROOT_RESTORED_BUILD.json
7e13313be7f40c71c39b41bfebdf683b19e40221b5832d325874d1420e8e7c95  ROOT_RESTORED_BUILD_PRE.json
64c5a5df805eb487ced2f14d6c7b14d121b0d73b9910b8452db58a69a21dff85  ROOT_RESTORED_DISCRIMINATION.json
727dadd5bb5a5b27fb64affeec89186315fd5ff40fb76c562731f58f7bec83b8  ROOT_RESTORED_EXECUTION_PRE.json
4310487e9ff616be08692dfdc4e9986ae1dedb423c3f9e3be414a7bcbea51a9e  ROOT_RESTORED_RUN.json
e1224a05ffabd040210d1373b59a4348a320471b1a73346d46c43efb27058630  ROOT_SOURCE_RESTORATION.json
```

All six stdout files are empty, SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Both build stderrs are three lines / 615 bytes, SHA-256
`ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22`.
Remaining raw hashes, relative to `CONTROL`:

```text
6e65f95d588e9efcbacd7dc567c79354104455f766fe64f92b3721efa51f88b5  mutant-logs/build.time
3355bf4de7479f734a7274c89a09a28b5603ca1e5939b8c9dece32127bdc323d  mutant-logs/layered.time
96a92ef10227eea350aa44f5fc5a668372c5802171edd9f80006600a02139985  mutant-logs/layered.stderr
dc684bad8660f46022a0e483b3fa11bdb2980b81e18e2ae1739bdc1a3d678dba  mutant-logs/insertion.time
cd6793a544f791f4d5228ee8a0033829d23788deeec69a9990f631fe94d1e979  mutant-logs/insertion.stderr
f19186b2f93e85f3cf882afa1d3708cd990944295239792d026b841bfb8f7fef  mutant-logs/omitted.time
7e24e71174a7999cf74e9d0e52a6fcb243ca187c55e36a7cb53ba617b51cb0cc  mutant-logs/omitted.stderr
63cb450be95b98a0c0351cb2783c7f2750ae128d12b82fefefc67e6d4f067992  restored-logs/build.time
7ef667e73fee686cf2902605cab3deead9c30c4b0a3f43d2f4d670dcd0984951  restored-logs/layered.time
c344159ab07bffd7484ffb7decfd565fc5f28f9882c913d3b3f45530058c2bb9  restored-logs/layered.stderr
```

Runtime stderrs have respectively 8,261,105 / 27,683,116 / 27,683,116 /
28,810,148 bytes and 98,764 / 333,203 / 333,203 / 346,797 lines (mutant
layered, insertion, omitted, restored layered). All 18 raw logs total
92,445,435 bytes. Read-only recount example from the fork root:

```sh
default_dir=build-ready-shadow-2026-09-06/remaining-controls/default-entry
awk '
/^info\(status\): update:/ {updates++}
/^debug\(zcu\): READY_TIER / {attempts++}
/^debug\(zcu\): findOutdatedToAnalyze:/ {
    if($0 !~ /all up-to-date$/ && $0 !~ /dependency loop affecting/) completed++;
}
/^debug\(zcu\): READY_SHADOW / {
    comparisons++; split($5,a,"="); split($6,b,"=");
    if(a[2]!=b[2]) unequal++;
}
ENDFILE {
    printf "%s updates=%d attempts=%d completed=%d comparisons=%d unequal=%d\n",FILENAME,updates,attempts,completed,comparisons,unequal;
    updates=attempts=completed=comparisons=unequal=0;
}' "$default_dir/mutant-logs/layered.stderr" "$default_dir/mutant-logs/insertion.stderr" "$default_dir/mutant-logs/omitted.stderr" "$default_dir/restored-logs/layered.stderr"
```

Other actual audit commands were bounded `sed`/`rg`/`jq` reads,
`sha256sum`, `cmp` and full-file `diff`; read-only in-memory Node filesystem/
crypto checks verified recorded facts, full-path source hashes/path sets and
independent inodes. Only this receipt and additive root README/crown PLAN status
paragraphs were authored via `apply_patch`. No source, prior receipt, scratch
record/bank/artifact, Git state or station pointer changed; no compiler, test,
network, child agent or cleanup operation ran in this documentation task.

Remaining ceilings: append's tripwire is not independently armed; default-mode
isolation is bounded to this one native three-update fixture and these observed
exits, not every compiler allocation. OOM/failure fallback, exhaustive tier or
semantic-cycle behavior, wider concurrency, performance and portable release
remain unestablished here. Zero fallback records are not an OOM witness.
The separate OOM/cost packets are unchanged. Nothing here promotes a compiler,
changes the default or establishes parallel Sema.

