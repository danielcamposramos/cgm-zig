# Executed ready-index preparation-OOM control — 2026-09-07

The finite allocation-fallback experiment is complete: **four of four planned
compiler builds succeeded, and five of five runtime phases produced their
specified outcome**—four successful fixture runs and one deliberately failing
tripwire run. Removing the tripwire restored success while OOM remained armed;
removing the OOM injection and rebuilding restored indexed/scan agreement.

This closes the first nodes-preparation-allocation control on one native
incremental fixture. It is not a universal OOM, correctness, speed, package or
promotion claim. The shipping compiler was never instrumented by these controls.

Execution: root orchestrator, under Daniel's direction. Preparation, independent
source/log/hash review and this receipt: GPT 6 Astra, senior compiler partner.
The reviewer ran no compiler, tests, probes or additional experiment. The
[preparation packet](READY_INDEX_PREPARE_OOM_CONTROL_PACKET_2026-09-07.md) remains
an unexecuted-at-authoring plan; this receipt records its later execution.

## Evidence locality and review boundary

**Every link below into `build-*` or `PROMOTED` is LOCAL retained evidence.**
Those directories are ignored build artifacts, not files made publicly
available by this Markdown receipt. Public reproduction requires the companion
inputs listed in the final section. No archive, upload or publication is
claimed here.

The [local independent review](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_SEQUENCE_INDEPENDENT_REVIEW.md)
preserves two distinct boundaries: the original read-only audit accepted
baseline/A/B/restored-A while clean-restored execution was still unavailable;
the present extension independently checks the completed clean-restored phase.
The earlier exclusion is not rewritten into an earlier pass.

For compact path notation in this receipt only:

```text
R = /K3D/GitHub/cgm-zig
S = R/build-ready-shadow-2026-09-06
Q = S/prepare-oom
T = R/build-ready-runtime
```

All 28 of 28 `Q/ROOT_*.json` records were read. All 57 of 57 unique referenced
file identities were independently rehashed, including recorded byte lengths
and resolved paths: zero mismatches and zero missing retained inputs. Five of
five runtime stderr logs were independently parsed, not accepted by their
DISCRIMINATION summaries alone. All nine of nine build/runtime GNU-time logs
agree with the recorded exits. Current clean source and all four phase
manifests were checked separately as described below.

## 1. What actually ran

The unchanged fixture [temporary_parse_error](../../build-ready-runtime/fixtures/temporary_parse_error)
declares one active target, `x86_64-linux-selfhosted`, and exactly three ordered
outcomes: initial program runs with empty stdout; an incomplete function gives
`main.zig:2:1: error: expected statement, found 'EOF'`; the repaired program
again runs with empty stdout. Commented target alternatives are not executions.
The [repaired runner](INCREMENTAL_RUNNER_COMPLETENESS_2026-09-07.md) checks those
outcomes; an update label alone is not success evidence.

| Phase and LOCAL run record | Source state | New build exit | Runner exit | Fixture outcomes | Measured discriminator |
|---|---|---:|---:|---:|---|
| [baseline](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_BASELINE_RUN.json) | frozen clean shadow | reused sealed compiler | 0 | 3/3 | 2083/2083 same-live-state pairs agree |
| [injected](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_INJECTED_RUN.json) | A | 0 | 0 | 3/3 | 2083/2083 fallback chains; two real catches |
| [tripwire](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_TRIPWIRE_RUN.json) | A+B | 0 | 1 | 0/3; abort in first update | 1/1 intended fallback tripwire fires |
| [injection-restored](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_INJECTION_RESTORED_RUN.json) | B inverse, still A | 0 | 0 | 3/3 | 2083/2083 fallback chains; two real catches |
| [clean-restored](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_CLEAN_RESTORED_RUN.json) | A inverse, frozen clean | 0 | 0 | 3/3 | 2083/2083 same-live-state pairs agree |

All four builds used separate output/cache roots and finished before their
corresponding run. All four BUILD_PRE/BUILD and five EXECUTION_PRE/RUN
command/environment pairs agree. These are recorded explicit launcher
overrides, **not an independently captured complete child execve environment**.

### Actual compiler identities

Every SHA-256 below was independently rechecked. Version strings come from
the execution records and retained generated options, not a new reviewer-run
`version` invocation.

| Phase | LOCAL binary path | SHA-256 |
|---|---|---|
| baseline | `S/clean-stage3/bin/zig` | `01d3b88dad37d11bcdcafe815095d5545d2cdd4af6ad467fc365d227ed43d1b2` |
| A | `Q/injected-stage3/bin/zig` | `d70509e19fd423ffc964da03dc004ed05677fa39c4860fcefc385a5154c0de44` |
| A+B | `Q/tripwire-stage3/bin/zig` | `e2f07ed759bba77104dc04f725f8f82f54b8d717e13b25ef597e9dbdd506d603` |
| restored A | `Q/injection-restored-stage3/bin/zig` | `5a9301268b7a56a8a9d157e5a42dd668830b15d3a77c37d78e2f2167d3bbc592` |
| clean-restored | `Q/clean-restored-stage3/bin/zig` | `5573efba82ea8ab97dd7690c0478b27ff6dc28baf01d6faf6c6fde5fce91011b` |

Baseline version: `0.16.0+cgm.0399d2b19b.shadow`. Each rebuilt phase has
`0.16.0+cgm.0399d2b19b.shadow-prepare-oom-<phase>`, where the exact phase
names are `injected`, `tripwire`, `injection-restored` and `clean-restored`.
These are control binaries, not release candidates.

### Fixed inputs and retained options

| Input | LOCAL path | SHA-256 |
|---|---|---|
| build compiler | `R/PROMOTED/stage3-046d6833/bin/zig` | `046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11` |
| configuration | `R/build-release-2026-09-06/config.h` | `a5bd5321ba297aaa4099b96b3d2d9b1831af4e5e0d9b695d15cc7ef38c922678` |
| C++ support archive | `R/build-release-2026-09-06/zigcpp/libzigcpp.a` | `a19e41135d40ac2b74e0e9cbcfa429cc711e2858fb0fb07bc2a80514f39a1676` |
| libc descriptor | `R/build-p005/vwork/libc.txt` | `783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5` |
| repaired runner | `T/runner-completeness/bin/repaired-restored` | `b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87` |
| runner source | `R/tools/incr-check.zig` | `35a5a0f1587fa798822fd864ba9e035d23a13d23626dd790de59d63901e21168` |
| wrapper | `T/zig-under-test` | `77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027` |
| fixture | `T/fixtures/temporary_parse_error` | `f7a3e2fe43b88dcb117a04b0380ca4b04b630572ed00f9d768e9c76efe2e0fa5` |

The four rebuilt options files remain under the respective build cache's
`c/<key>/options.zig`. Their full paths and text are retained in each
EXECUTION_PRE/RUN record. All four of four rehash and text comparisons pass:

```text
injected            c/3c3a6dba4a414033a626847b65fe21e6/options.zig  20ff18aadaf3f2c31d1a9124147aa81f4b04132a10b04e2cf410410bdb342aba
tripwire            c/b760c992cc894a38ac729cdd35f39f2b/options.zig  0775ad7517bd673009fec24e7a3a3eb4a3a584c201c84d910d9fb2760bf40baf
injection-restored  c/40c9098f65e89cf1753f14414eb8f168/options.zig  487a4d5f782929ae52695de49fc18ac04b605f22c126a37434fb10bc18f1ed86
clean-restored      c/e9759b038399283b08330214d2fe20bd/options.zig  7611ea0a95ac19336bc14a867630f7ba6022ebd219922e8958525c09b9d09290
```

They name LLVM enabled, full compiler development environment, threaded I/O,
direct value interpretation, debug extensions enabled and logging enabled.
The build argv explicitly selects ReleaseSafe and contains no strip option.
System LLVM and baseline CPU settings do not establish portable/static linkage.

## 2. Source state and exact mutation/restoration

The frozen bank [audit/post.sha256](../../build-ready-shadow-2026-09-06/audit/post.sha256)
has SHA-256 `5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`.
Read each hash plus its full path, preserving spaces. Removing only the exact
frozen-root prefix and sorting by complete relative path yields 21,931 entries,
2,444,976 bytes and the canonical clean digest below. Phase manifests remove
only their exact `./` prefix before the same canonical comparison.

| Source state | Canonical complete-path manifest SHA-256 |
|---|---|
| clean baseline/final clean | `a1647d5717228e98679ed566acc17da3474303c5e8b177801cf8026a8b130832` |
| A / restored A | `f280f192fe2e180ffee6d1a35540c4fb60937d2f026ee37774a6503fe7319f26` |
| A+B | `1dbdfeafe1172cca1611760d9cfc6bccbb12ade7259362faa5b95beb64ef9b3f` |

Only `src/Zcu.zig` and `src/Zcu/ReadyIndex.zig` change under A. B changes just
the actual fallback return in A's Zcu. In-memory reconstruction independently
verified all eight of eight exact hunk anchors across four native patches:

| LOCAL patch | Hunks | SHA-256 |
|---|---:|---|
| [A](../../build-ready-shadow-2026-09-06/prepare-oom/patch-a-inject.patch) | 3/3 | `d3fc967c872c31139f58e54c61decd2446dd362e3534a760b957fa37a011314b` |
| [B](../../build-ready-shadow-2026-09-06/prepare-oom/patch-b-tripwire.patch) | 1/1 | `993ccde38c41876702cdf8cd2981d56942e1d682b91ed8e988608cc805eb23cb` |
| [B inverse](../../build-ready-shadow-2026-09-06/prepare-oom/patch-b-restore-injection.patch) | 1/1 | `ae9f556ef7a7bd160fc081b143fbc853828df678a6482bafb4ca48c3aabd6cd7` |
| [A inverse](../../build-ready-shadow-2026-09-06/prepare-oom/patch-a-restore-clean.patch) | 3/3 | `62cb918b6d84c02574e41f037baa0fcc3750581725e00de0df18419e2600a0d5` |

The current control source independently matches **21,931 of 21,931** frozen
hashes, the exact path set and 21,931 independent inode pairs. All four of four
phase manifests match the bank plus their declared overrides. Final clean
owner hashes are Zcu `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e`
and ReadyIndex `ea21a609b71076d59ebc8268f46418e42233475f19f15a6a61b859ff21708e23`.
These are frozen **shadow** owners, not hashes of uninstrumented shipping source.

## 3. Why the failure is the real preparation-allocation path

A replaces only the allocator argument at the actual `index.prepare` call
with a zero-length FixedBufferAllocator. It requires a positive ready count,
inactive state and zero capacities. `Node` is not zero-sized. The real
`nodes.ensureTotalCapacity` therefore requests storage and reaches its
allocation-failure catch; the witness is inside that catch, before the
unchanged `disable()`/false return. There is no global memory starvation or
synthetic call to disable the index.

In each successful A run, all **2083 of 2083** adjacent chains validate:
BEFORE, ENTRY, actual catch only when invalid, AFTER, FALLBACK, SCAN and the
real selected unit. Two of two invalid preparations fail allocation: other
tier n=2 and function tier n=1. The remaining **2081 of 2081** calls begin
disabled and return without entering the allocation catch. Every AFTER has
disabled state, false result, zero lengths/capacities and zero allocator use;
every returned scan index is below its positive count. The original scan runs
once and supplies the returned index. There is no active-index shadow
comparison under forced OOM, and its absence is not counted as agreement.

In both A logs the catch chains start at lines **98741** and **101643**.
[B's log](../../build-ready-shadow-2026-09-06/prepare-oom/tripwire-logs/layered.stderr)
has its first complete catch/fallback/scan chain at lines 98741–98746,
`thread ... panic: READY_PREPARE_OOM fallback tripwire` at 98750, and the
runner's named compiler ABRT report at 98773. It is the intended panic after
the actual scan, not a compiler-build failure, timeout or precondition panic.
No fixture selection returns past B. Its 942 earlier choices belong to the
initial insertion-mode compiler_rt compilation and cannot be credited as
forced-OOM or completed fixture work.

Restored A independently repeats both catches, the 2081 disabled no-retry calls
and all three expected fixture outcomes. Restoring source alone was not used
as the negative control's recovery proof: a distinct compiler was built and run.

## 4. Final clean recovery and independent sequence comparison

[Clean-restored BUILD](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_CLEAN_RESTORED_BUILD.json)
runs from `03:34:43.697Z` to `03:45:07.189Z`, exit 0.
[Clean-restored RUN](../../build-ready-shadow-2026-09-06/prepare-oom/ROOT_CLEAN_RESTORED_RUN.json)
runs from `03:45:21.148Z` to `03:45:26.860Z`, exit 0.
The root discrimination record was written at `03:46:35.050Z`; its SHA-256 is
`d169de67e7eba40282573d2fe89c38b1059d785fc5d8d8c83c9f2c79d8623db1`.
This reviewer independently corroborated its claims from the retained source,
binary, options and full raw log.

The final log has 346,797 lines and three update labels at lines 2, 345683 and
346238. All **2083 of 2083** unnormalized same-live-state chosen/scan pairs
agree; the first is at 98742 and last at 345674. There are no OOM injection,
fallback-tripwire or panic/error records. The expected parse error is an
accepted fixture outcome in the runner protocol, not an omitted failure.

For the supplementary cross-process comparison, keep update grouping and
order. Compare `(tier,n,scan)` from A's `READY_OOM_SCAN` against baseline's
`READY_SHADOW` scan projection. In selected-unit strings only, replace the
exact `S/source/` and `Q/source/` prefixes with one common token and replace
space-prefixed bracketed decimal InternPool IDs with one common ID token
(pattern ` \[\d+\]`). Keep instruction numbers, names, ordering and results.
Exclude only `findOutdatedToAnalyze: all up-to-date` from actual-selection counts.

Both A runs and clean-restored match baseline for **2083 of 2083** ordered
scan tuples and **3025 of 3025** selected units; restored A also matches
initial A. The selected denominator is 942 insertion-mode compiler_rt choices
plus 2083 layered fixture choices. Cross-process agreement is not same-live-map
evidence and does not establish all-state equality: baseline/clean memo
occupancy before the parse-error update is 96; A's is 73.

### Raw log anchors

All runtime stdout captures have zero bytes, while stderr contains the actual
instrumented evidence. The paths below are LOCAL; all five stderr hashes were
independently verified.

| Under `Q/` | Bytes | SHA-256 |
|---|---:|---|
| `baseline-logs/layered.stderr` | 28636205 | `2fc0bd5758bfe87b5b0277f0a8e3208664c3422051d9c905517ed2ac9b2df492` |
| `injected-logs/layered.stderr` | 28589788 | `682d95f3baabb44cb580764191b0f92ea90fe4199472aff84e214b106c55051d` |
| `tripwire-logs/layered.stderr` | 8175114 | `d9cf859bba5775fe959ae576e131926d284c85b9c5fd6150d2c69376596fd353` |
| `injection-restored-logs/layered.stderr` | 28589788 | `e080ee2a9f377722749705c5f512579f6dccd1bfd17e38898eb8377675272a27` |
| `clean-restored-logs/layered.stderr` | 28699457 | `bff08fbfce12c3cae25d199bc7859a18e6522f2737edd41cab1810a72e727f8e` |

The corresponding `layered.time` and four `build.time` files are retained and
hashed in RUN/BUILD records. Their wall times are respectively 5.46, 5.64,
6.79, 5.61 and 5.70 seconds for runtime; build times are 10:36.70, 10:32.79,
10:26.34 and 10:23.48. These instrumented single runs are resource receipts,
not a benchmark or speed comparison.

## 5. Exact recorded invocation and reproduction boundary

The following expands the recorded command/environment pattern, not an
instruction to overwrite retained results or start another experiment. A new
reproducer must use fresh output/cache/log directories, retain a full path map
if relocating the inputs and reseal every phase. Never reuse these completed
paths. Respect machine courtesy: no concurrent compiler build. Native patch
application uses the exact named patch contents and verifies all source hashes
before each build; it is not a blind shell loop.

Actual sequence: fresh run of the sealed clean-shadow baseline; apply A and
build/run `injected`; apply B and build/run `tripwire`; apply B inverse and
build/run `injection-restored`; apply A inverse and build/run `clean-restored`.
Materialization and each resulting full source manifest are retained in the
phase's MATERIALIZATION and BUILD_PRE records.

For each of the four rebuilt phase names, the recorded build command was:

```bash
oom_root=/K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom
oom_phase=injected # then tripwire, injection-restored, clean-restored after each verified mutation
cd "$oom_root/source"
env ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt \
    ZIG_LOCAL_CACHE_DIR="$oom_root/$oom_phase-build-cache" \
    ZIG_GLOBAL_CACHE_DIR="$oom_root/$oom_phase-global-cache" \
    /usr/bin/time -v -o "$oom_root/$oom_phase-logs/build.time" \
    /K3D/GitHub/cgm-zig/PROMOTED/zig build \
    --prefix "$oom_root/$oom_phase-stage3" --zig-lib-dir "$oom_root/source/lib" \
    "-Dversion-string=0.16.0+cgm.0399d2b19b.shadow-prepare-oom-$oom_phase" \
    -Dtarget=native -Dcpu=baseline -Denable-llvm \
    -Dconfig_h=/K3D/GitHub/cgm-zig/build-release-2026-09-06/config.h \
    -Dno-langref -Ddebug-extensions -Dlog -Doptimize=ReleaseSafe
```

Raw stdout/stderr were captured as the phase's `build.stdout`/`build.stderr`.
Runtime command, with the candidate and library selected from the phase table:

```bash
cd /K3D/GitHub/cgm-zig/build-ready-runtime
env ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt \
    READY_INDEX_CANDIDATE="$oom_root/$oom_phase-stage3/bin/zig" \
    READY_INDEX_ORDER=layered \
    /usr/bin/time -v -o "$oom_root/$oom_phase-logs/layered.time" \
    timeout --kill-after=10s 180s \
    /K3D/GitHub/cgm-zig/build-ready-runtime/runner-completeness/bin/repaired-restored \
    ./zig-under-test fixtures/temporary_parse_error \
    --zig-lib-dir "$oom_root/source/lib" --preserve-tmp \
    --debug-log zcu --debug-log zcu_deps
```

For baseline only, `oom_phase=baseline`, the candidate is
`S/clean-stage3/bin/zig` and `--zig-lib-dir` is `S/source/lib`; there was no
new baseline build in this queue. Runtime stdout/stderr were captured as
`layered.stdout`/`layered.stderr`. The existing wrapper adds layered / `-j1` /
two partitions only to `build-exe` and preserves `--listen=-` framing. The
runner owns fresh temporary caches for each invocation, and updates within
that invocation share the real compiler child. The fixture has no `.case`
suffix. The instrumented compiler's initial compiler_rt sub-compilation still
uses insertion ordering; it is counted separately above.

## 6. Finite ceilings, cleanup and reproduction inputs

- This proves the first **nodes** preparation-allocation failure at the real
  call site. It does not prove positions allocation, active append, rank-memo
  or global allocator OOM. The two catches are two tier instances of one
  allocation site, not coverage of two distinct allocation sites.
- All 2083 forced-OOM calls in each A run occur in the first fixture update.
  Parse abort and recovery complete afterward, but neither later update makes
  a new ready selection. Rearming and another allocation failure after abort
  are **not exercised** by this fixture.
- Active-index structural observers are unarmed during forced OOM. Final clean
  same-live-state agreement is a separate restored-path result. The fallback
  scan is not duplicated as a purported independent oracle inside A.
- No all-state equivalence, universal correctness, concurrency/race freedom,
  other-target coverage, index-only performance, hardware portability or speed
  claim follows. No release, package, online synchronization or promotion was
  performed by the reviewer.

The user's authorized cleanup removed only selected regenerable AstGen `z`
and build/object buckets. See the [LOCAL cleanup record](../../build-cache-cleanup-2026-09-07/README.md).
Retained compiler binaries, source snapshots, `c/.../options.zig`, dependency
inputs and all logs/seals still pass the 57-reference hash audit. Removed
intermediate cache contents are not missing retained evidence and were not
recreated. This review did not repeat the cleanup audit or perform deletions.

For public replay, release packaging must carry a clearly labeled companion
reproduction/evidence bundle, not silently rely on ignored local paths:

1. The exact clean-shadow source snapshot and full-path bank, or the complete
   source at `0399d2b19b` plus
   [clean-shadow.patch](../../build-ready-shadow-2026-09-06/audit/clean-shadow.patch)
   (SHA-256 `4120b797d58e2307ae4198bddbb2e2b3d4eab5a400b5cd9d5c657fced0ead547`)
   and the resulting bank needed to verify the identical snapshot.
2. All four native A/B/inverse patches and the preparation packet; native
   absolute patch targets require an explicitly recorded relocation, not
   silently changed mutation bodies.
3. The exact wrapper and fixture, plus the corrected runner source/build
   recipe or sealed runner binary. A checkout of the old frozen snapshot alone
   contains the old runner and must not substitute it for the repaired runner.
4. The build compiler/library, configuration, C++ support archive or its exact
   reconstruction inputs, libc descriptor, generated options, and declared
   system LLVM/Clang dependencies. Carry the sealed control binaries for exact
   binary replay, or label newly rebuilt identities honestly; relocating debug
   paths/version strings is not a byte-identical rebuild claim.
5. All phase prestate/materialization/build/run/discrimination records, source
   manifests, raw logs and this independent review, with bundle checksums.

Control/mutant binaries belong only in that explicitly labeled evidence
bundle, never as the installed/default shipping compiler. Regenerable cache
intermediates are not required. This receipt identifies these packaging
obligations; it does **not** claim the bundle has been produced or published.

Only this public receipt and the LOCAL independent-review Markdown file were
authored through native `apply_patch`. No compiler/status probe, test, source
edit, helper file, Git mutation, network action, cleanup or child agent ran
in this documentation lane. No evidence mismatch required a repair. The
two-file scope ends at handoff.
