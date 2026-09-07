# Lost ordinary append hook — executed RED / restored GREEN, 2026-09-07

The live production-wrapper observer detects the deliberately missing ordinary
append hook. The mutant builds successfully, then fails at the first active
map growth with `READY_INDEX membership length mismatch`. After exact source
restoration, a separately rebuilt compiler passes the same four-update fixture
with 2,095/2,095 same-live-state index/scan agreements and both active-growing
ordinary puts intact. This is one completed broken-hook control, not promotion,
performance, integration-OOM or general scheduler-correctness proof.

Direction: Daniel Campos Ramos. Root coordinator performed all builds, native
patch/restoration and runs. A cooperating OpenAI Codex senior partner prepared
this receipt by read-only source, record, hash and raw-log inspection; no compiler
or test was executed during this documentation task. The earlier
[preparation receipt](READY_INDEX_REMAINING_CONTROLS_PREPARATION_2026-09-07.md)
and its dated complete-path correction remain immutable historical records.
The [selection self-control](READY_INDEX_SELECTION_SELF_CONTROL_2026-09-07.md)
is separate evidence.

## Source identity and the independent failure mechanism

The frozen authority is `build-ready-shadow-2026-09-06/source/`, source commit
`0399d2b19b71ed865cc2e6d5e21224f124e373db` plus the previously prepared three-owner
clean shadow instrumentation. Below, `CONTROL` denotes the exact repository-relative
directory `build-ready-shadow-2026-09-06/remaining-controls/lost-append/`.

The complete relevant bodies were read in frozen `src/Zcu.zig:3373–3413`:
`readyKeyAppended` updates an active optional index; `readyPutKey` commits the
authoritative map insertion, then invokes that hook only when membership grew.
Its scratch-only defer logs the before/after membership and calls
`readyAuditIndex`, independently checking both heap/position lengths against
the map and the reverse-position relation. The observer neither creates ready
members nor changes their priorities. The same-state picker and original scan
at `src/Zcu.zig:3490–3530` remain unchanged.

The entire mutant delta is one hunk, +1/-1 line, at the ordinary hook:

```diff
-    if (map.count() != old_count) zcu.readyKeyAppended(key);
+    _ = old_count;
```

The discard is the approved unused-local accommodation; it is not another
algorithm. The real map mutation, defer, membership checker, no-clobber hooks,
scan and other owners are unchanged. The actual full-file diff matches
[source.diff](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/source.diff)
byte-for-byte. Native [forward.patch](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/forward.patch)
and [reverse.patch](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/reverse.patch)
are preserved, as are the mutant overlay, binary and logs.

```text
852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e  clean/restored src/Zcu.zig
21f71276ad9f82c0ce219971a36a648dceb4592e4831b4795dfc973aa8d655f7  mutant overlay src/Zcu.zig
dbd7606fde7f655b57d1b2018d3b63750701d161bed3329f5e54af0f36743738  CONTROL/source.diff
929cb23851cffb60f78a7139e23b3c0ce02c7304ad3da0494c6e5219c068e953  CONTROL/forward.patch
8a52ccff3d43c2205343ac13338e8cb13464d06b28761b79a8b4d2d5530aa42e  CONTROL/reverse.patch
```

Root's [materialization record](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/ROOT_MATERIALIZATION.json)
records 21,931 independent-inode files and exactly one changed owner. Root then
applied the exact native reverse patch. The
[restoration record](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/ROOT_SOURCE_RESTORATION.json)
records 21,931 clean hashes, the exact path set and zero changed owners before
the restored build. This receipt independently rechecked **21,931/21,931 frozen
hashes and 21,931/21,931 current restored hashes**, plus zero restored path-set
differences, retaining every complete filename after the checksum separator.
The source bank SHA-256 remains
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
The preparation bank also still passes 41/41 entries. The frozen, overlay and
restored `Zcu.zig` device/inode pairs are distinct; no new copy or restoration
was performed by this audit.

## Build and launch provenance, with temporal limits

Both actual builds used `PROMOTED/zig build`, `-Doptimize=ReleaseSafe`,
`-Dtarget=native -Dcpu=baseline -Denable-llvm -Ddebug-extensions -Dlog`,
`-Dno-langref`, the explicit source `lib` and existing release `config.h`.
Both complete generated options files confirm `.full`, LLVM, debug extensions
and logging enabled. The config selects system LLVM 21 with shared linking;
baseline CPU is not a portability or hermetic-build claim.

| Root-executed stage | UTC interval / observation | Exit | Wall time / maximum RSS KiB |
| --- | --- | ---: | --- |
| Mutant build | 01:14:27.550–01:24:37.415 | 0 | 10:09.86 / 6,527,508 |
| Mutant input/artifact seal | 01:30:06.242, after build and before runtime | — | — |
| Mutant fixture | 01:30:06.253–01:30:14.306 | runner 1; compiler ABRT | 0:08.04 / 681,240 |
| Source restore and external-input seal | 01:31:28.826, before restored build | — | — |
| Restored build | 01:31:28.838–01:41:46.887 | 0 | 10:18.04 / 6,548,948 |
| Restored fixture | 01:42:29.737–01:42:35.608 | 0 | 0:05.86 / 380,680 |

All times are 2026-09-07 UTC. These are functional observations under concurrent
orchestration, **not benchmarks**. The mutant's external inputs were sealed
**after** its build, not retrospectively before it. The restored build has a
real pre-build seal. The first mutant capture attempt used the wrong archive
path and stopped before emitting its receipt or running the fixture. The actual
owner is `build-release-2026-09-06/zigcpp/libzigcpp.a`; this capture-path mistake
was not a compiler source defect or another build.

Current hashes independently agree with the recorded seals:

```text
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/zig -> PROMOTED/stage3-046d6833/bin/zig
a5bd5321ba297aaa4099b96b3d2d9b1831af4e5e0d9b695d15cc7ef38c922678  build-release-2026-09-06/config.h
a19e41135d40ac2b74e0e9cbcfa429cc711e2858fb0fb07bc2a80514f39a1676  build-release-2026-09-06/zigcpp/libzigcpp.a
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
cad1cf5438604646e6ceb2054ecb471134ff31682515342bc242ade2bb84be4f  CONTROL/mutant-stage3/bin/zig
f1d01e7169308bc259b25a0e11a4309c7a7ef533537761dab311ff78f2443e96  CONTROL/restored-stage3/bin/zig
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  build-ready-runtime/runner-completeness/bin/repaired-restored
77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027  build-ready-runtime/zig-under-test
7a5c30ad5e38e61f013ba86872846f1749dc42729f0a7b3e63df34a0f003ce56  build-ready-runtime/fixtures/change_module
24b5a381eacdd9cc207a73267e93558ced2929d228294b99f3874e9c69686cd2  CONTROL/mutant-build-cache/c/37fb2abd08489191773fc681c3971cc1/options.zig
11ac0cced5f3bc3153006fa45d93f66c6b98f0e1bbdb184cdc45d0677539df8c  CONTROL/restored-build-cache/c/5af6342821c3232609755ea510ea6fca/options.zig
```

The recorded versions are `0.16.0+cgm.0399d2b19b.shadow-lost-append-mutant` and
`0.16.0+cgm.0399d2b19b.shadow-lost-append-restored`; this audit read the records
and options and hashed the binaries, without invoking them.

The original run JSON omitted environment overrides. Root's immutable
[launch addendum](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/ROOT_LAUNCH_ENVIRONMENT_ADDENDUM.json)
later transcribes explicit overrides from the original launchers, sessions 3203
and 95191: the respective absolute candidate path, `READY_INDEX_ORDER=layered`
and the sealed `ZIG_LIBC` path. Its qualified `recorded_utc_approximate` is a
manually rounded record label, not a measured timestamp; the timeline above
uses the original build/run records. It is **not** an independent raw child `execve`
or `/proc` environment capture; those remain unavailable. Layered mode is also
independently visible in the runtime logs. The sealed wrapper appends
`--analysis-order=layered -j1 --intern-partitions=2` only to `build-exe`, leaving
probe commands unchanged. The runner uses its existing IPC and per-temporary-
directory `.local-cache` / `.global-cache`; `--preserve-tmp` was passed.

## Independently recounted RED and restored GREEN

The fixture has one active native self-hosted target and exactly four updates:
`initial version`, `change module of other.zig`, `put other.zig in both modules`,
and `put other.zig in no modules`. The first three expect compiler diagnostics
(including two compile-log comparisons); the last expects successful execution
with empty stdout. Expected compile errors are not failures of the restored run.

| Raw-log scope | Mutant | Separately rebuilt restored |
| --- | ---: | ---: |
| Ordered fixture update labels reached / expected | 2/4 | 4/4 |
| Same-state index/scan agreements / comparisons | 2,088/2,088 before panic | 2,095/2,095 |
| Function / other comparison records | 1,670 / 418 | 1,672 / 423 |
| Active-growing ordinary puts / ordinary put records | 1/6 | 2/11 |
| Named membership panic records | 1 | 0 |
| Logged optional-index fallback records | 0 | 0 |

In [mutant stderr](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/mutant-logs/layered.stderr),
update 2 starts at line 345724. Line 346353 reports the active `InternPool.AnalUnit`
map growing `old=1 new=2`; there is no helper append between its before/after
pair. Line 346357 is the intended `READY_INDEX membership length mismatch`
panic, and line 346386 explicitly reports compiler signal ABRT. The stack names
the preserved defer observer at `Zcu.zig:3406`. This is the intended mutant
compiler assertion, not a runner-checker failure or a build error. Earlier equal
selection records do not make the aborted run GREEN.

In [restored stderr](../../build-ready-shadow-2026-09-06/remaining-controls/lost-append/restored-logs/layered.stderr),
the four labels occur at lines 2, 345724, 346436 and 346995, in fixture order.
The two active-growing after-records at 346354 and 346359 report `1→2` and `2→3`,
each preceded by its real helper append entry. There are zero unequal selected/
scanned positions in all 2,095 comparisons, zero panic records, and no warning
or skipped-target record. The repaired runner exits 0 after the four expected
outcomes. The restored evidence uses the repaired runner, not the older runner
whose diagnostic-completeness ceiling applies to the original clean-V2 traces.
This does not enlarge the repaired runner's separately documented branch coverage.

## Immutable evidence and read-only reproduction

All ten execution/provenance JSON files below were read completely; their paths
are under `CONTROL`. Build stdout/stderr and all four time files were read
completely. Both full runtime stderrs were streamed with anchored marker parsing
and hashed, with selected failure/recovery context inspected; they were not
manually read line by line. No disagreement with the root counts was found.

```text
e8e3a801c258c83c65918b2c87fb50779cc12e443b603d5e81fd527b5c066358  ROOT_MUTANT_BUILD.json
1af8c97758b03be48d1adc024d34970d3c1ff30bd05daaf0f5c9c955fa18b2d9  ROOT_MUTANT_EXECUTION_PRE.json
b83a2c111bdba59c38f9e1bfb4a2450e39f067675c0ab897305218575e2dc664  ROOT_MUTANT_RUN.json
0180f51f1faea9ebf7449dc3a8c0dc91c101640c9b7794a18759cdea101f924f  ROOT_MUTANT_DISCRIMINATION.json
989523a2eabbe53c48e760a9d7c23e30a924a61ad5163f33b46fdb198db8cdd5  ROOT_SOURCE_RESTORATION.json
b0b24c23cd5f5dae8f8b43967bbed3e4ede88a879235f0bdc3fc611186c7a72c  ROOT_RESTORED_BUILD.json
2cb45292ffb3ec3084338a45037ebd95de90d84122953b8d9958e557a392b063  ROOT_RESTORED_EXECUTION_PRE.json
a669e11a82374310bd41ce7d333323ea3bc21a1678b21e2c7401ccddb3054acb  ROOT_RESTORED_RUN.json
9d9767a5a5f80eaf2a04fdac3c5c7fdaad39b40379c089f4ba8e1d75b24ded98  ROOT_RESTORED_DISCRIMINATION.json
d3b11e7cd5b79e00c58ec6ce8079f640decaff5017a951cdb571fe6f805aa73a  ROOT_LAUNCH_ENVIRONMENT_ADDENDUM.json
```

All 12 raw logs were independently hashed, agreeing with both discrimination
records. All four stdout files are empty, SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Both three-line build stderrs are 615 bytes, SHA-256
`ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22`.
The remaining hashes, under `CONTROL`, are:

```text
be492d675d7e1a885ff82ece9c472fc1a43dddcf8e65f7340a566ceb52a28cb6  mutant-logs/build.time
0322ff31858d408ea135e25695a3d62ade35e0815e837ffba22787e8799baecf  mutant-logs/layered.time
1c636f476489545439e68561c53df675fdc393a1a465794986d1739306a65ea8  mutant-logs/layered.stderr
17079e32a43bcd724681dc810404dad1fe2b452be1a3cf2668313b0a0c80c14b  restored-logs/build.time
1bc97ae835367b49bbbd6ccec65e26e3322fd79cbc7cf564bb54cf03eda849c6  restored-logs/layered.time
e08458d35269789d40725a4c11f2806f6c4dc6e7529f782fdee9884c58b12c35  restored-logs/layered.stderr
```

Runtime stderr sizes are 28,725,158 bytes / 346,386 lines (mutant) and 28,905,536
bytes / 347,601 lines (restored). The four stdout, four stderr and four time files
total 57,636,502 bytes. Exact build/runner argv and working directories are in
the respective `ROOT_*_BUILD.json` / `ROOT_*_RUN.json` and `.time` records;
launch overrides have the distinct later-transcription authority stated above.
The following are read-only recount commands, not another execution:

```sh
cd /K3D/GitHub/cgm-zig
lost_append_dir=build-ready-shadow-2026-09-06/remaining-controls/lost-append
awk '
/^info\(status\): update:/ { updates++; print FILENAME ":" FNR ":" $0 }
/^debug\(zcu\): READY_SHADOW / {
    comparisons++; split($5,a,"="); split($6,b,"=");
    if (a[2] != b[2]) mismatch++;
}
/^debug\(zcu\): READY_PUT / {
    puts++; split($7,a,"="); split($8,b,"=");
    if ($5 == "active_before=true" && $6 == "active_after=true" && b[2] > a[2]) grows++;
}
/^thread [0-9]+ panic:/ { panics++ }
ENDFILE {
    printf "%s updates=%d comparisons=%d mismatches=%d puts=%d grows=%d panics=%d\n", FILENAME,updates,comparisons,mismatch,puts,grows,panics;
    updates=comparisons=mismatch=puts=grows=panics=0;
}' "$lost_append_dir/mutant-logs/layered.stderr" "$lost_append_dir/restored-logs/layered.stderr"
sha256sum "$lost_append_dir"/mutant-logs/* "$lost_append_dir"/restored-logs/*
```

Other actual audit commands were bounded `sed`, `rg`, `jq`, `sha256sum --check`,
`wc`, `stat`, full-file `diff`/`cmp`, and `awk` complete-path mapping plus
NUL-separated `find`/`sort`/`comm` path-set comparison. Only this new receipt and
additive entries in the existing root README and crown PLAN were authored,
using `apply_patch`. No source, scratch manifest/bank, old receipt, execution
record, build artifact, station pointer or Git state was modified.

Lost-update-invalidation and default-entry controls remain outside this result.
Integration OOM, wider-worker safety, exhaustive tier/cycle coverage and
end-to-end performance remain UNKNOWN here. Zero fallback records are no OOM
witness. The shadow's scans/observers are nonshipping measurement overhead;
this receipt claims neither parallel Sema, a changed default, release nor promotion.
