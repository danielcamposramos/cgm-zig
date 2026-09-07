# Ready-index selection checker — actual RED → restored source → rebuilt GREEN

Date: 2026-09-07. The first selection-checker self-control is now closed for the
bounded layered `change_module` run: the inverted checker reached its named
failure, the complete source bank was restored, and a separately rebuilt
restored compiler completed the same four-update fixture with 2,095/2,095
indexed choices equal to the original scan. This is checker-sensitivity and
restoration evidence, not release acceptance or a performance claim.

Direction: Daniel Campos Ramos. Build/run coordination and source restoration:
the root OpenAI Codex partner. Independent scratch preparation and this
read-only evidence audit: a cooperating OpenAI Codex senior partner. Existing
design/authorship credits remain in PROVENANCE.md; Upstream-Status: not-filed-policy.

## Exact intervention and preserved history

The [preparation receipt](../../build-ready-shadow-2026-09-06/audit/self-control-preparation/README.md)
and [manifest](../../build-ready-shadow-2026-09-06/audit/self-control-preparation/manifest.json)
record an independent-inode copy of all 21,931 frozen clean-shadow files, followed
by one exact source replacement in scratch `src/Zcu.zig:3508`:

```diff
-        if (chosen != scanned) @panic("READY_SHADOW selection mismatch");
+        if (chosen == scanned) @panic("READY_SHADOW selection mismatch");
```

The [preserved patch](../../build-ready-shadow-2026-09-06/audit/self-control-preparation/selection-self-control.patch)
is one hunk, one line added and one removed. No ready-set member, scheduler
result, scan implementation or protocol reply was manufactured. The clean
shadow compares the indexed and original-scan positions in the same live state;
the self-control deliberately rejects agreement at that existing checker.

The original preparation JSON still says runtime UNRUN, correctly describing
its time of writing. Likewise,
[self-control-red-and-source-restore.json](../../build-ready-shadow-2026-09-06/audit/self-control-red-and-source-restore.json)
records the actual RED and source restoration, but says the restored binary was
not yet built. Neither historical record was rewritten. This new receipt adds
the later rebuilt-artifact and execution evidence. The mutant binary, exact
patch, earlier outputs and clean reference source remain preserved.

## Two actual compiler artifacts

Both build `.time` files retain exit 0 and the full build argv: the promoted
compiler builds the isolated scratch source with system-LLVM configuration,
`-Dtarget=native -Dcpu=baseline -Denable-llvm -Ddebug-extensions -Dlog
-Doptimize=ReleaseSafe`, separate output prefixes and version strings. Both
generated `options.zig` files were read completely: LLVM true, dev `.full`,
threaded I/O, logging true and debug extensions true.

| Artifact | Recorded version string | Build wall / maximum RSS |
| --- | --- | --- |
| [Inverted compiler](../../build-ready-shadow-2026-09-06/self-control-stage3/bin/zig) | `0.16.0+cgm.0399d2b19b.shadow-self-control` | 9:45.23 / 6,466,696 KiB |
| [Separately rebuilt restored compiler](../../build-ready-shadow-2026-09-06/self-control-restored-stage3/bin/zig) | `0.16.0+cgm.0399d2b19b.shadow-self-control-restored` | 9:29.71 / 6,445,692 KiB |

Inverted binary SHA-256:
`c23bf7572e9e47f03d7818d4ff085e5af47a1097f3493e1226be9ca1e780379a`.
Restored binary SHA-256:
`8f6cc92019614abe64789fb3e4c53aa3bbad6c8a708134ffb5ebef7052f87154`.
These hashes were independently read from the current artifacts. Version strings
are corroborated by generated options and the coordinator's version reports;
this audit invoked neither compiler, including no `version` command.

Build evidence:
[inverted time](../../build-ready-shadow-2026-09-06/audit/build-self-control.time),
[restored time](../../build-ready-shadow-2026-09-06/audit/build-self-control-restored.time),
[inverted options](../../build-ready-shadow-2026-09-06/self-control-build-cache/c/ecd447d9287e5cc81899269adeb856b3/options.zig),
[restored options](../../build-ready-shadow-2026-09-06/self-control-restored-build-cache/c/a733343530f4703207ea34ef773ad874/options.zig).
Both build stdout files are empty. The two 615-byte build stderr files are
byte-identical topology/thread-plan/step-order information, not failed builds.
Build timing is observational and not a comparison of compiler performance.

## Actual RED

The [inverted-run stderr](../../build-ready-runtime/shadow-selection-self-control-layered-change_module.stderr)
contains exactly one anchored indexed comparison:

```text
debug(zcu): READY_SHADOW tier=InternPool.AnalUnit n=2 chosen=0 scan=0
```

It is followed by exactly one `thread ... panic: READY_SHADOW selection mismatch`
and a runner diagnostic that the compiler terminated with signal `ABRT`.
The [time record](../../build-ready-runtime/shadow-selection-self-control-layered-change_module.time)
has runner exit 1, wall 0:06.10 and maximum RSS 675,224 KiB. Only the first of
the fixture's four update labels was reached. The failure is therefore the
deliberately inverted live checker, not an unexplained nonzero exit or timeout.

Trace caveat: the first stack source location printed by this optimized artifact
is `src/Zcu.zig:3618`, beside the different function-priority guard, whereas the
selection comparison is at line 3508. The log is preserved as printed. This
receipt attributes the control using the one-line mutation, the immediately
preceding equal-choice record and the exact named panic; it does not treat that
stack source location as an exact checker-placement witness.

## Current source restoration, independently rechecked

The coordinator restored only `==` back to `!=` with `apply_patch`. The changed
file's source SHA-256 sequence is:

- Clean: `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e`.
- Inverted: `4763060bf98bee5194b0e55969c20828a23cd7d56ed6eaeeb2457c74e89a1303`.
- Restored: `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e`.

This audit checked all 21,931/21,931 hashes in the original clean bank, then
all 21,931/21,931 hashes after mapping that bank to `self-control-source/`.
Both commands exited 0. A separate sorted path-list comparison also exited 0,
so the restored clone has exactly the bank's 21,931 paths, not merely matching
known files with unexamined extras. The clean source tree also has 21,931 files.
The source-bank path and current SHA-256 are
`build-ready-shadow-2026-09-06/audit/post.sha256` and
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
The normalized restored full-list digest is
`a1647d5717228e98679ed566acc17da3474303c5e8b177801cf8026a8b130832`,
matching the preparation's canonical PRE digest. No source was changed by this
audit; the inode independence of the original copy is prior preparation evidence,
not a newly repeated full-inode audit here.

## Actual separately rebuilt GREEN and its ceiling

The [restored-run stderr](../../build-ready-runtime/shadow-selection-self-control-restored-layered-change_module.stderr)
was scanned independently in full, together with the inverted stderr:
36,979,986 bytes across these two files. The restored
[time record](../../build-ready-runtime/shadow-selection-self-control-restored-layered-change_module.time)
has exit 0, wall 0:05.49 and maximum RSS 380,832 KiB, agreeing with the
coordinator's reported successful invocation. Both runner stdout files are empty.

| Precisely scoped raw evidence | Inverted run | Restored run |
| --- | ---: | ---: |
| Anchored `READY_SHADOW` comparisons | 1 | 2,095 |
| Equal chosen/scan positions | 1/1 | 2,095/2,095 |
| More than one ready member | 1/1 | 2,080/2,095 |
| Nonzero chosen position | 0/1 | 52/2,095 |
| Function-tier comparisons (`InternPool.Index`) | 0/1 | 1,672/2,095 |
| Other-tier comparisons (`InternPool.AnalUnit`) | 1/1 | 423/2,095 |
| Named selection-mismatch panics | 1 | 0 |
| Anchored fallback-marker records | 0 | 0 |
| Exact fixture update labels reached | 1/4 | 4/4 |

These comparison markers are in `readyPick` after its insertion-mode early
return; they are layered indexed events, not initial insertion-mode compiler_rt
work. Counts are events, not distinct units. The restored four ordered labels
match the existing fixture byte-for-byte: `initial version`, `change module of
other.zig`, `put other.zig in both modules`, `put other.zig in no modules`.
Their order was checked with `diff`, not just a total count.

The existing runner binary was used unchanged, SHA-256
`a3636dc5d5aa53415757ca588672701400d6151c845a15ffc80dd0cff0966967`.
Its known trailing-diagnostic and empty-terminal completeness gaps still bound
the outcome claim: four runner-accepted updates, not independent proof of every
expected diagnostic. The named panic/ABRT control is not disarmed by those
gaps. The separately prepared runner repair is not retroactive evidence for
these runs.

This closes 1/1 selection-checker inversion control with restored execution.
It does not close missing-append, invalidation, default-entry or OOM controls;
there were no fallback-marker events in either observed log. No new claim about
all tiers, semantic-cycle paths, concurrent workers, speed, promotion or release
acceptance follows from this narrow restoration fixture.

## Reproduction anchors and actual read-only commands

Both runner time records preserve this exact argv from `build-ready-runtime/`:

```sh
timeout --kill-after=10s 180s ./incr-check ./zig-under-test fixtures/change_module \
    --zig-lib-dir /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/self-control-source/lib \
    --preserve-tmp --debug-log zcu --debug-log zcu_deps
```

The existing wrapper receives `READY_INDEX_ORDER=layered` and the respective
identified absolute candidate via `READY_INDEX_CANDIDATE`; it adds `-j1` and
`--intern-partitions=2` only to the compiler `build-exe` invocation. The time
record stores argv, not environment; candidate attribution also uses the
coordinator's run record/report and hashes above. This audit does not invent
unrecorded historical cache environment settings or rerun the commands.

Actual current source checks, from the fork root:

```sh
sha256sum --check --quiet build-ready-shadow-2026-09-06/audit/post.sha256
sed 's|  build-ready-shadow-2026-09-06/source/|  build-ready-shadow-2026-09-06/self-control-source/|' \
    build-ready-shadow-2026-09-06/audit/post.sha256 | sha256sum --check --quiet
diff -u \
    <(sed 's|^................................................................  build-ready-shadow-2026-09-06/source/||' build-ready-shadow-2026-09-06/audit/post.sha256 | LC_ALL=C sort) \
    <(rg --files --hidden --no-ignore build-ready-shadow-2026-09-06/self-control-source | sed 's|^build-ready-shadow-2026-09-06/self-control-source/||' | LC_ALL=C sort)
diff -u <(sed -n 's/^#update=//p' build-ready-runtime/fixtures/change_module) \
    <(sed -n "s/^info(status): update: '\(.*\)'$/\1/p" build-ready-runtime/shadow-selection-self-control-restored-layered-change_module.stderr)
```

The raw marker recount used `awk` anchored at
`^debug\(zcu\): READY_SHADOW tier=`; fields 4, 5 and 6 carry `n=`, `chosen=` and
`scan=`. It counted equality, multi-member choices, nonzero positions and tier
names separately per input file. Panic and fallback counts used anchored actual
log records, not source snippets in backtraces. `sed`, `rg`, `wc` and
`sha256sum` read the named source/evidence files and complete options/time files.
No compiler, formatter, Sema, runner, test, Git mutation, child agent or cleanup
was invoked by this receipt-only wave.

## Exact evidence checksums

All paths below are relative to the fork root; binaries/source bank and restored
Zcu are hashed above. The `.stdout` files for both builds and both runs are empty
and each hashes to
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

```text
3ddb78b7f3d1ff505fe635b1ecd78a589f81c34609bee946d37aadf37f9a5def  build-ready-shadow-2026-09-06/audit/self-control-preparation/README.md
c776145a8c50443668e3d8ffb8b407fae6fe2cf1c9a0e45db30a7369f05b978b  build-ready-shadow-2026-09-06/audit/self-control-preparation/manifest.json
f15a616443c3539c8958e9de5b0db6475375766c0631564435298c2f2536632b  build-ready-shadow-2026-09-06/audit/self-control-preparation/selection-self-control.patch
13d19105f30785817acce6ce88c03da7093833c6c89c91371daf95159cc6093e  build-ready-shadow-2026-09-06/audit/self-control-red-and-source-restore.json
c5ad6bbd5b3d19d0fd1f5f10c49fab2bfb16f3339f7305f76917360667ba5e3b  build-ready-shadow-2026-09-06/audit/build-self-control.time
1850068e63678852baf2d9ee6869c3e38ca430fd3866aea571b77035f4294071  build-ready-shadow-2026-09-06/audit/build-self-control-restored.time
ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22  build-ready-shadow-2026-09-06/audit/build-self-control.stderr
ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22  build-ready-shadow-2026-09-06/audit/build-self-control-restored.stderr
0adb93e14c6beb41f3a44b9da0a6fae3651b47bf5903071d900e9b85a0332a0e  build-ready-shadow-2026-09-06/self-control-build-cache/c/ecd447d9287e5cc81899269adeb856b3/options.zig
4cba962eb6b7462cbbc272c60b437dcb001672688f7a4fbaf7200d35ea7b228e  build-ready-shadow-2026-09-06/self-control-restored-build-cache/c/a733343530f4703207ea34ef773ad874/options.zig
b3da65a84985078f3ad8e6530e2fdc51e8e488bfa1a5ddc3f38b807990c30d7a  build-ready-runtime/shadow-selection-self-control-layered-change_module.stderr
da2ddc54c832c63784f046f6524e4da2056c25398b7d6af8381caac5432a7911  build-ready-runtime/shadow-selection-self-control-layered-change_module.time
3edff2934c19c053f42ad8ff024de5f32d2efe6038bcfe1222b9d162ffb25a8c  build-ready-runtime/shadow-selection-self-control-restored-layered-change_module.stderr
8995d6842c405ad21863054b696bbdc6d798bd5d05f7f80daf4a55dd107749ee  build-ready-runtime/shadow-selection-self-control-restored-layered-change_module.time
7a5c30ad5e38e61f013ba86872846f1749dc42729f0a7b3e63df34a0f003ce56  build-ready-runtime/fixtures/change_module
77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027  build-ready-runtime/zig-under-test
```

The only existing document edit in this wave is an 11-line append to
[the live-shadow receipt](READY_INDEX_LIVE_SHADOW_2026-09-06.md); its complete
prior content was checked unchanged as a prefix. That file's PRE SHA-256 was
`880a1309207417108b4ebd46b41663ba82e0b1363f7fffa35f6f2bc9b975d699`;
POST SHA-256 is
`e7bce08a05e737d4eec464f2b7681ff791f7a11939944d887be78f8c64f14406`.
This new receipt and that append were authored with absolute-path `apply_patch`.
