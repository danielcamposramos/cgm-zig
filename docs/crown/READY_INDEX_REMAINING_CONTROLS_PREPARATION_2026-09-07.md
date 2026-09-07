# Remaining live-shadow controls — bounded preparation, 2026-09-07

Three source-only control overlays are ready for root review: lost ordinary
append hook, lost update invalidation, and default helper-entry tripwire.
**All three mutant builds/runs and their restored execution are UNRUN.** No
compiler, formatter, AstGen, Sema or test was invoked by this wave. No OOM
variant, fixture, protocol driver or replacement oracle was authored.

Direction: Daniel Campos Ramos. Preparation: a cooperating OpenAI Codex senior
partner under the root coordinator's finite grant. Root owns the subsequent
serial build/run queue. The governing
[runtime packet](READY_INDEX_RUNTIME_VERIFICATION_PACKET_2026-09-06.md) was read
completely, including section 3 and its stopping rules. The completed
[selection self-control](READY_INDEX_SELECTION_SELF_CONTROL_2026-09-07.md)
remains separate evidence; its RED does not discharge these remaining controls.

## Minimal overlays, frozen authority and disk courtesy

The authority is `build-ready-shadow-2026-09-06/source/`: commit
`0399d2b19b71ed865cc2e6d5e21224f124e373db` plus the already-built clean shadow
instrumentation. All 21,931/21,931 source hashes still match
`build-ready-shadow-2026-09-06/audit/post.sha256`, whose SHA-256 is
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
The original source tree also still contains exactly 21,931 files.

Headroom was checked before copying: approximately 14 GB available, 95% used;
a later byte-valued reading was 14,000,369,664 available bytes. The frozen source
alone occupies about 287 MiB. Therefore this preparation created only three
independent-inode owner-file copies, not three complete trees or build caches.
The final overlays contain 466,239 source bytes, about 455 KiB. The scratch
packet including patches/metadata occupies 589,824 allocated bytes at sealing.
Full source materializations: **0/3**; actual compiler outputs: **0/3**.

The [scratch README](../../build-ready-shadow-2026-09-06/remaining-controls/README.md)
contains exact future materialization, build, run and restore commands.
`cp -a --reflink=auto` copied only the three selected original files into their
new overlay directories. All 3/3 copies initially matched their full originals;
all 3/3 clean/copy device-inode pairs are distinct, before and after editing.
No hardlinks were used. Original files and all old receipts remain unchanged.

## Actual clean reach selecting the smallest armed fixtures

The finite search was only the five existing prepared fixtures. Recounting their
layered raw logs gives the following ordinary-put discriminator:

| Fixture | Updates | Active-growing ordinary puts / layered ordinary puts |
| --- | ---: | ---: |
| change_module | 4 | 2/11 |
| type_dependency_loop | 5 | 6/15 |
| temporary_parse_error | 3 | 0/0; not armed for lost ordinary append |
| analysis_error_and_syntax_error | 6 | 1/4 |
| add_remove_struct_fields | 4 | 3/15 |

For lost append, `change_module` is a minimum-update armed fixture; among the
two four-update candidates it also has fewer indexed picks (2,095 versus 2,316).
Its two exact positive records are at lines 346354 and 346359 of
[layered change_module stderr](../../build-ready-runtime/shadow-clean-v2-layered-change_module.stderr):

```text
debug(zcu): READY_PUT mode=layered tier=InternPool.AnalUnit active_before=true active_after=true old=1 new=2
debug(zcu): READY_PUT mode=layered tier=InternPool.AnalUnit active_before=true active_after=true old=2 new=3
```

The real helper append entries are between each before/after pair. The first
is in the second update, `change module of other.zig`. Removing the hook leaves
the defer's after-record and independent membership check intact; the intended
first RED is `READY_INDEX membership length mismatch` after that active-growing
record, not a generic compile failure.

Lost invalidation also selects `change_module`, because section 3 requires
actual ownership change plus abort/recovery, not merely a nonzero memo in a
shorter unrelated fixture. Its later memo counts are 98 at line 345726 and 3
at line 346438: 2/4 fixture update entries have nonzero memo. There are five
epoch entries in the whole log, including the initial compiler_rt update.
The independent reset checks follow the two nonzero entries. Double ownership
produces `READY_ABORT fatal_files=false multi_module=true ...` at line 346993,
and `put other.zig in no modules` begins at line 346995. All four labels and
exit 0 are retained in the clean log/time record. The targeted negative should
fail at the second update with `READY_EPOCH invalidation missing`, after the
memo-98 before-record.

Default entry selects the minimum-update fixture `temporary_parse_error`:

| Actual clean scope | Updates | Helper prepare / append entries | Zero-capacity exits | Ordinary selections |
| --- | ---: | ---: | ---: | ---: |
| Layered | 3 | 2,083 / 9,447 | 1, from compiler_rt | 3,025 = 2,083 fixture + 942 compiler_rt |
| Explicit insertion | 3 | 0 / 0 | 4 = 3 fixture + 1 compiler_rt | 3,029 = 2,087 fixture + 942 compiler_rt |
| Omitted/default | 3 | 0 / 0 | 4 = 3 fixture + 1 compiler_rt | 3,029 = 2,087 fixture + 942 compiler_rt |

The first layered helper entry is line 98741 of
[layered temporary_parse_error stderr](../../build-ready-runtime/shadow-clean-v2-layered-temporary_parse_error.stderr):
`READY_ENTRY prepare count=2 state=invalid nodes_capacity=0 positions_capacity=0`.
The first append entry is line 98750. Explicit-insertion and omitted traces
have positive selection/update denominators and all four capacities plus memo
count zero at each exit; absence of helper entries is therefore scoped live
evidence, not an uninstrumented zero. The default mutant must fire
`READY_DEFAULT_ENTRY prepare` under layered and retain all three valid outcomes
under both explicit insertion and omitted order. Its earlier prepare panic
masks later append entry: **an independently fired append tripwire is not
proved or promised by this combined variant**.

The four selected clean `.time` records were read completely and all have exit
0, agreeing with the existing V2 execution manifest. These positive traces used
the old runner and retain its outcome-completeness ceiling; they arm the actual
compiler paths, not every expected diagnostic. Future commands use the now
verified `runner-completeness/bin/repaired-restored`, SHA-256
`b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87`,
and exactly the existing fixtures/wrappers with `--preserve-tmp`.

## Exact mutations and two necessary source adaptations

The prepared owners live below
`build-ready-shadow-2026-09-06/remaining-controls/<variant>/overlay/`:

| Variant | Owner | Whole-file unified delta |
| --- | --- | --- |
| lost-append | src/Zcu.zig | One hunk, +1/-1 line: hook statement → `_ = old_count;` |
| lost-invalidation | src/Zcu/PerThread.zig | One hunk, +0/-1 line: remove only update's invalidation call |
| default-entry | src/Zcu/ReadyIndex.zig | Two hunks, +12/-6 lines: two entry logs → two named local void-thunk panics |

The packet's literal hook deletion would leave `old_count` unused. Retaining
the already-existing local and discarding it preserves its evaluation while
removing the hook's only effect. Likewise, a bare unconditional entry `@panic`
would make the preserved following helper body unreachable. Each marker is
instead replaced with a local `EntryTripwire` struct whose `fn hit() void`
contains the named panic, followed by `EntryTripwire.hit()`. The call has void
type, keeping following source semantically reachable while the called body
always panics. Both narrow scratch-only adaptations were explicitly reviewed
and approved by root; they are not byte-exact copies of the original packet
text. Their compilation is still UNRUN here.

The original scan, ordinary map mutation, no-clobber paths, independent wrapper
defer checks, epoch before/after checks and computeAliveFiles invalidation are
unchanged. The four exact source anchors were checked at 1/1 each with the
existing `oracle_lib.assert_anchor` before native absolute-path `apply_patch`.
Full-file diffs confirm no other bytes changed. Forward applicability against
the frozen clean source passed 3/3 GNU `patch --dry-run --batch` checks; reverse
applicability against the overlays passed 3/3. These did not apply patches or
restore source and are not parsing/type checking or runtime evidence.

Each variant also has native `forward.patch` and `reverse.patch` packets with
the exact future full-clone owner path. Root must materialize a clean independent
tree, apply the forward packet, check the complete derived 21,931-file manifest,
then build with ReleaseSafe, baseline CPU, LLVM, debug extensions and logging.
There are distinct mutant/restored output prefixes and cache roots for each of
the three controls; none points to PROMOTED. After the named negative, apply
the reverse packet, verify all 21,931 clean hashes and exact path set, build a
separately named restored compiler, and rerun the same fixture/order(s).
Source-only restoration or running the old mutant binary is insufficient.

## Restoration identities and manifest bank

| Owner | Exact clean/restoration SHA-256 | Prepared mutant SHA-256 |
| --- | --- | --- |
| src/Zcu.zig | `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e` | `21f71276ad9f82c0ce219971a36a648dceb4592e4831b4795dfc973aa8d655f7` |
| src/Zcu/PerThread.zig | `cd64130f322746898888216d3f809b77c831b996a4c9cc6481b8c1a8e69fb50b` | `efdaa4efad9c00ff2bc14c724e7fa2753e8762ad50b836879193a7aaa0d02f43` |
| src/Zcu/ReadyIndex.zig | `ea21a609b71076d59ebc8268f46418e42233475f19f15a6a61b859ff21708e23` | `cb1adde9972238f2289c28702e7045326cec06745a28949efcef37523d295008` |

[manifest.json](../../build-ready-shadow-2026-09-06/remaining-controls/manifest.json)
records exact inodes, patch deltas, future roots, selected reach and complete
virtual source-list derivation. Each variant uses the frozen bank with exactly
one hash override; these complete lists are derived, not materialized full
clone claims. Their canonical digests are:

```text
a1647d5717228e98679ed566acc17da3474303c5e8b177801cf8026a8b130832  clean/restored
87c619d92929ba942bd6a8648d1208bdb8674e8b8bb521824791c9cf987f909e  lost-append
71e197c94f05b2768e2a2248c9e3c156b32bbf8fab67fc2c4cf14bd46c909b18  lost-invalidation
33b0fcecc4712a6b91d07899b93599cd1b54844b9a9c8328108857c4e9096a2a  default-entry
```

[SHA256SUMS](../../build-ready-shadow-2026-09-06/remaining-controls/SHA256SUMS)
was checked at 36/36 paths: all three overlays, nine patch files, manifest,
scratch instructions, frozen bank/owners, seven inspected clean stderr logs,
four selected time records, V2 execution manifest, repaired runner, two wrappers,
two selected fixtures and the incidental cache artifact below. Bank SHA-256:
`f3c3d6c94286891e2ab43aa4782d9dcef8ef2a132ff53c20bde3ce9c8e8221bb`.
Manifest SHA-256:
`b1eec9f85e94f8805da38abab60373b9cfe8bd129e38f467ed8b682729def43e`.
Scratch README SHA-256:
`858b20db84f98702aed9c3aab889d49e523ec7d112d6e26c01cc916b371a4bca`.

## Actual commands, deviation and handoff ceiling

Actual commands were bounded `sed`/`rg` reads, `awk` clean-log recounts,
`sha256sum`/`--check`, `wc`, `stat`, `df`, `du`, `ls`, `date`, three explicit
`cp -a --reflink=auto` owner copies after creating new directories, full-file
`diff -u`, six read-only patch applicability checks, and the existing Python
anchor helper import. All manual source, patch and metadata edits used native
`apply_patch`; no shell/Python source rewrite was used.

Incidental deviation, disclosed to and acknowledged by root: the anchor-helper
import omitted Python's `-B` and appears to have emitted
`partner_tools/__pycache__/oracle_lib.cpython-314.pyc` outside the preparation
folder. Its timestamp matches that call; SHA-256 is
`f9eb92820f43c74b20dbe56f07291743d9db860a39b7615f4dfc877086f7b44f`.
It was preserved, not removed. No source file outside the three overlays was
changed; any subsequent helper import must use `-B`.

The new control variants remain source preparation only: no dynamic RED,
restored GREEN, compile cost, OOM behavior, wide-worker safety, performance,
promotion or release claim. No production source, existing document, Git state
or station binary was edited, and no network, child agent or cleanup was used.
Root owns review and the nonoverlapping execution queue; no further fixture
search or OOM preparation is included in this handoff.

## 2026-09-07 — record correction: preserve complete checksum paths

The three canonical POST digests and the README/manifest/bank hash block above
are **superseded by this dated correction**. Their historical text is retained,
and the complete original receipt, README, manifest and checksum bank were
preserved byte-for-byte before edits in
[record-correction-2026-09-07](../../build-ready-shadow-2026-09-06/remaining-controls/record-correction-2026-09-07/CORRECTION.md).
This fixes preparation metadata and its verifier, not any source or control.
Original preparation counts and UNRUN statements above retain their original
time scope; they do not describe the coordinator's later execution state.

Independent audit correctly identified `path=$2` as lossy: it splits filenames
at whitespace. This correction independently reproduced 96/21,931 truncated
paths, 3,000 discarded bytes, and all three erroneous POST digests. For example,
`doc/langref/Assembly Syntax Explained.zig` became `doc/langref/Assembly`.
The old mapped verifier exited 1 with
`WARNING: 96 listed files could not be read`. Its relative lists contained
21,931 rows but only 2,441,976 bytes. This is a negative record-format witness,
not a compiler/control RED.

The fixed verifier reads `value=substr($0,1,64)`, validates the exact two-space
separator, and keeps the whole `path=substr($0,67)`. It removes only the exact
source-root prefix and applies exactly one owner-hash override. Canonical
rows are checksum, two spaces, complete relative path and LF, sorted by the
complete path under `LC_ALL=C`. The actual edited README body was extracted
and exercised read-only against the frozen source using each clean owner hash:
all 3/3 mappings validated all 21,931 entries, without accessing a materialized
control tree. The same parser, with relative-path output, reproduced these
correct complete POST lists, each **21,931 rows / 2,444,976 bytes**:

```text
8dfe6ca9e65b83b42354946381e2a3bf10b6201f0d45bd5883e8de3a932ff948  lost-append
da879c29501f8ec111e6c610fe9be9bfbe604744bb1c39823f5ebf7874068020  lost-invalidation
3dd19c70ac3defbcd2755cc7e532c2bf7944f208446a1575f1ddf89ccdd58556  default-entry
```

The correct PRE remains
`a1647d5717228e98679ed566acc17da3474303c5e8b177801cf8026a8b130832`.
The three overlay hashes, all forward/reverse patches and the 21,931-file
frozen source bank remain unchanged. Current manifest fields hold the complete
POST digests and retain the old values explicitly as `superseded_lossy` fields.

Refreshed record SHA-256 values:

```text
0e1189a1846520d15c282712613b976327eb7fb776c07a0cfa4f93b57b78753e  remaining-controls/README.md
6df93aeeba1e258ccd8b2ab7d6099ff6edc299d4bdcbd733d1b8b22517d5f5a2  remaining-controls/manifest.json
743bd6dab0f088f161a1fa669bfa1fa54cf762d1e4d6c3bf947ee1ef7db15024  remaining-controls/SHA256SUMS
```

These paths are below `build-ready-shadow-2026-09-06/`. The updated bank passes
41/41 entries: the previous 36 entries with only two live record hashes updated,
plus four preserved historical copies and the detailed correction record.

Future execution receipts should also seal the resolved `PROMOTED/zig`, actual
`config.h`, linked `libzigcpp.a`, and `libc.txt` paths and hashes consumed by
each build. The source bank does not already seal these build inputs. This
record-only correction provides no execution or build-closure proof and did
not touch compiler sources, overlays, patches, materialized trees, execution
records, build artifacts or caches. No compiler, test, generator, Git, network,
child agent or cleanup operation was used. All authorized record edits and
historical copies used `apply_patch`.
