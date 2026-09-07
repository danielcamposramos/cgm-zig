# Incremental runner completeness — source correction and prepared controls

Date: 2026-09-07. Scope: `tools/incr-check.zig`, this receipt, and isolated
`build-ready-runtime/runner-completeness/` preparation. No compiler, runner,
formatter, AstGen, Sema, test, Git mutation, promotion or cleanup was executed
in this wave. The compiler lane belonged to another build. Runtime outcomes,
negative-control reach and restored execution below are **UNRUN / UNKNOWN**.

## Source finding and PRE → POST

The runner is the existing owner built by `test/tests.zig:2914`:
`addIncrementalTests` adds `tools/incr-check.zig` as its executable root.
`Case` is inline, and the complete runner has one import, `std`; there is no
relative `Case.zig` closure to copy or new protocol harness to implement.

Before editing, the 40,013 original bytes were preserved at
[`original/incr-check.zig`](../../build-ready-runtime/runner-completeness/original/incr-check.zig).
Original SHA-256:
`26cae5d79fc4d05ceed6f5a0ccb0fbaa9126a14297984d761c706573bc58c5fc`.
The 41,234-byte corrected owner and frozen `repaired/incr-check.zig` both hash to
`35a5a0f1587fa798822fd864ba9e035d23a13d23626dd790de59d63901e21168`.
The [production patch](../../build-ready-runtime/runner-completeness/audit/production.patch)
contains 21 added lines, zero removed lines, in five unified-diff hunks.

Two existing checks were incomplete:

1. `Eval.checkErrorOutcome` consumed actual messages and notes, rejecting
   excess/mismatched diagnostics, but did not reject an unconsumed expected
   suffix. It now checks the final index before the unchanged compile-log
   comparison and reports `insufficient diagnostic count: received {d}, expected {d}`.
2. `Eval.check` previously accepted every empty terminating error bundle.
   Its new per-call `success_result_handled` starts false and is set only after
   successful `checkSuccessOutcome` calls. An empty terminal bundle now rejects
   `.compile_errors` with `expected compile errors but received empty terminal error_bundle`.
   For `.stdout`/`.exit_code`, executable backends require a handled emit result
   or report `empty terminal error_bundle without handled success result`.
   Sema may use the existing success checker with a null emitted path; it does
   not require an executable artifact. `.unknown` remains unconstrained.

The flag deliberately does not assert execution: the existing foreign-executor
selection may intentionally skip a target after handling its success result.
A normal empty terminator after a handled emit remains valid. The flag is local
to each update, so success in an earlier update cannot satisfy a later update.
Framing, full body consumption, error decoding, compile-log comparison, success
checking, foreign-target policy and the compiler protocol are otherwise unchanged.

## Prepared source controls, not execution evidence

All paths in this section are relative to
`build-ready-runtime/runner-completeness/`. Every control is a complete copy of
the real runner or an existing prepared fixture, with only the listed delta.
The four runner mutants are isolated from both frozen originals and production.

| Artifact / comparison | Exact isolated delta | Expected later discriminator; not observed |
| --- | --- | --- |
| `fixtures/change_module_extra_note` vs prepared `change_module` | One added trailing `#expect_error=:note: runner completeness fictitious trailing note` in the first update, before its unchanged compile-log directive | Original accepts 4 updates incorrectly; repaired fails first update with the insufficient-count diagnostic |
| `original-skip-emit/incr-check.zig` vs original | One hunk: +2/-1 lines; discard the decoded native emitted path instead of handling its success | Original accepts all 3 `temporary_parse_error` updates despite not handling either native success |
| `repaired-skip-emit/incr-check.zig` vs repaired | One hunk: +2/-2 lines; same discard, without setting the handled flag | Repaired fails first success update with the missing-handled-success diagnostic |
| `original-empty-errors/incr-check.zig` vs original | One hunk: +8/-1 lines; decode the actual bundle, replace only a nonempty decoded bundle with `std.zig.ErrorBundle.empty` | Original accepts all 6 `analysis_error_and_syntax_error` updates incorrectly |
| `repaired-empty-errors/incr-check.zig` vs repaired | Identical replacement, one hunk: +8/-1 lines | Repaired fails first expected-error update with the empty-terminal diagnostic |
| `fixtures/temporary_parse_error_sema` vs prepared `temporary_parse_error` | One target-line replacement: `x86_64-linux-selfhosted` → `x86_64-linux-sema` | Repaired accepts 3 semantic updates, including the expected parse error; does not prove executable behavior |

The emit controls still consume `header.bytes_len`, decode `EmitDigest` and its
native digest, drain compiler stderr and resolve the native emitted path. Only
the native success-result handoff is deliberately discarded; the sema branch
and terminal completeness checker remain live. They log
`RUNNER_CONTROL dropped native emit success result` at the discarded result.
Returning early from `Eval.check`, setting a false success flag, or skipping the
terminal checker would defeat this test and was not implemented.

The bundle controls likewise consume and decode the complete actual message
before substituting the checker input. They log
`RUNNER_CONTROL replaced nonempty error_bundle with empty (root errors: {d})`
only when the decoded root-error count is nonzero. An unchanged already-empty
bundle is not a reached mutation. No fabricated framing or compiler reply is used.

For each paired runner mutation, its source anchor count was exactly 1/1.
Both fixture changes were reversed independently in memory and matched every
original byte (2/2); their active target counts are 1/1 each, update counts 4
and 3, and deletion directives 0/2 prepared controls. All six runner copies
retain the inline `Case` and subsequent source bytes exactly. All seven
production/copy `(device,inode)` pairs are distinct; none is a hardlink.
These are source-content checks, not Zig parsing, type checking or behavior.

## Evidence bank

- [SHA256SUMS](../../build-ready-runtime/runner-completeness/audit/SHA256SUMS):
  28/28 recorded paths verified with `sha256sum -c`; covers the owner, six runner
  copies, two fixture controls, five original prepared fixtures, two wrappers,
  old runner binary, candidate binary, libc descriptor, seven exact patches and
  two static-audit outputs. Manifest SHA-256:
  `0c9349e469290537de54ad258a38d98722f8702bef383ead214b0b5af5f85100`.
- [source-checks.json](../../build-ready-runtime/runner-completeness/audit/source-checks.json):
  full-content checks, fixture reversal, import closure, exact seven `diff -u`
  commands and their actual +/−/hunk counts. `diff` exit 1 means the expected
  differences were present, not a failing runtime control.
- [independent-inodes.txt](../../build-ready-runtime/runner-completeness/audit/independent-inodes.txt):
  exact `stat -c '%d:%i %s %n'` command and observed identities.
- All seven exact patches are siblings of the manifest, named `production`,
  `original-skip-emit`, `repaired-skip-emit`, `original-empty-errors`,
  `repaired-empty-errors`, `extra-note`, and `sema-target`, each with `.patch`.

The old runner binary remains
`a3636dc5d5aa53415757ca588672701400d6151c845a15ffc80dd0cff0966967`.
The selected future test candidate remains the logging-fixed compiler
`build-release-2026-09-06/log-fixed-stage3/bin/zig`, SHA-256
`d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f`.
Existing candidate/runner logs and receipts were not changed. Previously
reported 47 update labels and successful old-runner exits are retained as those
observations; these newly identified acceptance holes prevent treating them as
complete diagnostic/outcome validation by the repaired runner.

## Deferred exact build and control commands

These commands are a future execution packet, not this wave's command history.
Wait for an empty compiler lane, review the source, and verify all manifests
before executing. Refuse existing output/log destinations; preserve evidence
and select a new run bank if these names have already been used. Do not run in
parallel. The new binary paths do not replace the existing runner or compiler.
The runner has no additional build-option imports; this reuses the earlier
standalone ReleaseSafe build recipe with explicit repo-local caches.

```sh
cd /K3D/GitHub/cgm-zig
sha256sum -c build-ready-runtime/runner-completeness/audit/SHA256SUMS
PROMOTED/zig fmt --check tools/incr-check.zig
PROMOTED/zig ast-check tools/incr-check.zig
for runner_output in build-ready-runtime/runner-completeness/bin build-ready-runtime/runner-completeness/logs; do
    if [ -e "$runner_output" ] || [ -L "$runner_output" ]; then
        printf 'refusing existing output bank: %s\n' "$runner_output" >&2
        exit 2
    fi
done
mkdir build-ready-runtime/runner-completeness/bin build-ready-runtime/runner-completeness/logs || exit 2
export ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
for runner_variant in original repaired original-skip-emit repaired-skip-emit original-empty-errors repaired-empty-errors; do
    /usr/bin/time -v -o "build-ready-runtime/runner-completeness/logs/build-${runner_variant}.time" \
        PROMOTED/zig build-exe "build-ready-runtime/runner-completeness/${runner_variant}/incr-check.zig" \
        -OReleaseSafe --zig-lib-dir lib \
        --cache-dir "build-ready-runtime/runner-completeness/tool-cache-${runner_variant}" \
        --global-cache-dir build-ready-runtime/runner-completeness/tool-global-cache \
        "-femit-bin=build-ready-runtime/runner-completeness/bin/${runner_variant}" \
        > "build-ready-runtime/runner-completeness/logs/build-${runner_variant}.stdout" \
        2> "build-ready-runtime/runner-completeness/logs/build-${runner_variant}.stderr"
    runner_rc=$?
    printf '%s\n' "$runner_rc" > "build-ready-runtime/runner-completeness/logs/build-${runner_variant}.exit"
    if [ "$runner_rc" -ne 0 ]; then exit "$runner_rc"; fi
done

cd /K3D/GitHub/cgm-zig/build-ready-runtime
export READY_INDEX_CANDIDATE=/K3D/GitHub/cgm-zig/build-release-2026-09-06/log-fixed-stage3/bin/zig
export READY_INDEX_ORDER=layered
for runner_revision in original repaired; do
    for runner_control in extra-note skip-emit empty-errors; do
        case "$runner_control" in
            extra-note)
                runner_binary="runner-completeness/bin/${runner_revision}"
                runner_fixture=runner-completeness/fixtures/change_module_extra_note ;;
            skip-emit)
                runner_binary="runner-completeness/bin/${runner_revision}-skip-emit"
                runner_fixture=fixtures/temporary_parse_error ;;
            empty-errors)
                runner_binary="runner-completeness/bin/${runner_revision}-empty-errors"
                runner_fixture=fixtures/analysis_error_and_syntax_error ;;
        esac
        /usr/bin/time -v -o "runner-completeness/logs/control-${runner_revision}-${runner_control}.time" \
            timeout --kill-after=10s 180s "$runner_binary" ./zig-under-test "$runner_fixture" \
            --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
            --debug-log zcu --debug-log zcu_deps \
            > "runner-completeness/logs/control-${runner_revision}-${runner_control}.stdout" \
            2> "runner-completeness/logs/control-${runner_revision}-${runner_control}.stderr"
        runner_rc=$?
        printf '%s\n' "$runner_rc" > "runner-completeness/logs/control-${runner_revision}-${runner_control}.exit"
    done
done
```

For six planned control invocations, require original rc 0 with all expected
ordered update labels, repaired nonzero with the precise first-update diagnostic,
and the applicable `RUNNER_CONTROL` marker. A timeout, unrelated compile error,
missing marker or failure before the intended checker is not RED. Expected
native-discard marker totals are 2 for original and 1 before repaired failure;
nonempty-bundle replacement totals are 5 for original and 1 before repaired
failure. These are prospective expectations, not recorded reach counts.

## Restoration and normal matrix, also deferred

Mutants never alter the frozen repaired source or production owner. Restoration
therefore means checksum-confirming the untouched repaired input and building
a separately named nonmutant executable after the controls, not erasing evidence
or applying a reverse patch to production. Keep all mutant binaries and logs.

```sh
cd /K3D/GitHub/cgm-zig
sha256sum -c build-ready-runtime/runner-completeness/audit/SHA256SUMS
/usr/bin/time -v -o build-ready-runtime/runner-completeness/logs/build-repaired-restored.time \
    PROMOTED/zig build-exe build-ready-runtime/runner-completeness/repaired/incr-check.zig \
    -OReleaseSafe --zig-lib-dir lib \
    --cache-dir build-ready-runtime/runner-completeness/tool-cache-restored \
    --global-cache-dir build-ready-runtime/runner-completeness/tool-global-cache \
    -femit-bin=build-ready-runtime/runner-completeness/bin/repaired-restored \
    > build-ready-runtime/runner-completeness/logs/build-repaired-restored.stdout \
    2> build-ready-runtime/runner-completeness/logs/build-repaired-restored.stderr
runner_rc=$?
printf '%s\n' "$runner_rc" > build-ready-runtime/runner-completeness/logs/build-repaired-restored.exit
if [ "$runner_rc" -ne 0 ]; then exit "$runner_rc"; fi

cd /K3D/GitHub/cgm-zig/build-ready-runtime
for READY_INDEX_ORDER in insertion layered; do
    export READY_INDEX_ORDER
    for runner_fixture in change_module type_dependency_loop temporary_parse_error analysis_error_and_syntax_error add_remove_struct_fields; do
        /usr/bin/time -v -o "runner-completeness/logs/restored-${READY_INDEX_ORDER}-${runner_fixture}.time" \
            timeout --kill-after=10s 180s runner-completeness/bin/repaired-restored ./zig-under-test "fixtures/${runner_fixture}" \
            --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
            --debug-log zcu --debug-log zcu_deps \
            > "runner-completeness/logs/restored-${READY_INDEX_ORDER}-${runner_fixture}.stdout" \
            2> "runner-completeness/logs/restored-${READY_INDEX_ORDER}-${runner_fixture}.stderr"
        runner_rc=$?
        printf '%s\n' "$runner_rc" > "runner-completeness/logs/restored-${READY_INDEX_ORDER}-${runner_fixture}.exit"
        if [ "$runner_rc" -ne 0 ]; then exit "$runner_rc"; fi
    done
done
/usr/bin/time -v -o runner-completeness/logs/restored-default-temporary_parse_error.time \
    timeout --kill-after=10s 180s runner-completeness/bin/repaired-restored ./zig-under-test-default fixtures/temporary_parse_error \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp --debug-log zcu --debug-log zcu_deps \
    > runner-completeness/logs/restored-default-temporary_parse_error.stdout \
    2> runner-completeness/logs/restored-default-temporary_parse_error.stderr
runner_rc=$?
printf '%s\n' "$runner_rc" > runner-completeness/logs/restored-default-temporary_parse_error.exit
if [ "$runner_rc" -ne 0 ]; then exit "$runner_rc"; fi

export READY_INDEX_ORDER=layered
/usr/bin/time -v -o runner-completeness/logs/restored-sema-temporary_parse_error.time \
    timeout --kill-after=10s 180s runner-completeness/bin/repaired-restored ./zig-under-test runner-completeness/fixtures/temporary_parse_error_sema \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp --debug-log zcu --debug-log zcu_deps \
    > runner-completeness/logs/restored-sema-temporary_parse_error.stdout \
    2> runner-completeness/logs/restored-sema-temporary_parse_error.stderr
runner_rc=$?
printf '%s\n' "$runner_rc" > runner-completeness/logs/restored-sema-temporary_parse_error.exit
if [ "$runner_rc" -ne 0 ]; then exit "$runner_rc"; fi
```

Require rc 0 plus ordered, exact `info(status): update: '...'` labels against
each fixture's `#update=` directives. The normal denominator is
`(4 + 5 + 3 + 6 + 4) × 2 + 3 = 47` updates in 11 invocations. The separate sema
control adds 3 semantic updates in one invocation; it is not part of 47 and
does not validate stdout execution. Normal restored runs must contain none of
the mutation markers or new completeness failures. Afterward recheck the
28-path manifest and record fresh binary/log checksums, exits and timings.
Do not require deterministic binary hashes across separately located builds;
source restoration is checked against the exact frozen source hash.

## Actual preparation commands and residuals

Actual reads used `sed` over the complete runner, selected main/parser/error
bundle prior art, prepared fixtures, wrappers and prior receipts; `rg` located
the build owner, imports, directives and existing log labels. Exact `diff -u`
commands are recorded in `audit/source-checks.json`. `sha256sum`,
`sha256sum -c`, `stat -c '%d:%i %s %n'` and bounded `ls` checked bytes, identities
and absent destinations. All source/fixture/patch/audit/receipt writes used
`apply_patch` with absolute paths. In-memory string checks asserted unique
mutation anchors, complete written-source equality and fixture reversal.

No dynamic control ran. Parsing, formatting, Sema, runner compilation,
positive/negative execution, restored execution and timing remain UNKNOWN.
The selected fixtures do not claim dedicated `.exit_code`, `.unknown`, foreign
executor or every backend coverage; those existing policies were preserved by
source inspection. This correction repairs the evidence runner, not compiler
scheduling, and does not establish index-vs-scan, OOM, promotion or performance
claims. Root owns source review and the subsequent nonoverlapping build/run queue.

## 2026-09-07 — ACTUAL ROOT EXECUTION addendum

The coordinating root partner subsequently executed the bounded runner builds,
controls and restored matrix. This addendum is a separate read-only audit of
those outputs, not a rerun. The complete 270-line preparation receipt above is
retained unchanged; its earlier UNRUN statements describe the evidence available
then. Its pre-append SHA-256 is
`a0f55574f0aa42b1b3c7a185048d148a2c7bca83cf4347e12642170c039a3a5e`.

### Actual builds and attribution

The root reports `fmt --check` and `ast-check` on the production runner both
exited 0 before building. Those standalone checks were not repeated by this
auditor, and their exits are attributed to the root tool execution, not invented
local check logs. Actual build evidence is separately retained in
[root-builds.json](../../build-ready-runtime/runner-completeness/audit/root-builds.json)
and the `build` entry of
[root-restored-matrix.json](../../build-ready-runtime/runner-completeness/audit/root-restored-matrix.json).
All seven ReleaseSafe standalone runner builds exited 0: six original/repaired
and mutant binaries, followed by a fresh clean-copy restored build.

Every one of the 25 `.time` records was read completely and matched the exact
argv and exit status in its root manifest: seven builds, six controls and twelve
restored runtime invocations. The seven build stderr files each contain only
the same 336-byte topology/thread-plan information. All 25 stdout files are empty.
No build time is presented as a performance comparison.

The restored build used the frozen `repaired/incr-check.zig`, SHA-256
`35a5a0f1587fa798822fd864ba9e035d23a13d23626dd790de59d63901e21168`,
with a separately named local cache and output binary. It took 0:22.16 with
maximum RSS 445,904 KiB, exit 0. This was a clean-copy rebuild, **not** a reversal
of the four preserved mutant source files. The independently hashed
[repaired-restored binary](../../build-ready-runtime/runner-completeness/bin/repaired-restored)
is `b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87`.
It happens to match the initial clean repaired binary byte-for-byte; equality
was observed, not assumed as a general reproducible-build requirement.

### Three actual old false-GREEN → repaired named-RED pairs

[root-controls.json](../../build-ready-runtime/runner-completeness/audit/root-controls.json)
records all six exact invocations, runner exits, raw stderr hashes, ordered
labels and markers. This audit independently scanned those raw logs and matched
them against the recorded values.

| Real-runner control | Original result | Repaired result and exact discriminating diagnostic |
| --- | --- | --- |
| Fictitious trailing expected note | Exit 0, all 4 updates accepted incorrectly | Exit 1 at first update: `insufficient diagnostic count: received 1, expected 2` |
| Consumed native emit, discarded success handoff | Exit 0, all 3 updates; 2 reached discard markers | Exit 1 at first update after 1 discard marker: `empty terminal error_bundle without handled success result` |
| Decoded nonempty bundle replaced with empty | Exit 0, all 6 updates; 5 reached replacement markers | Exit 1 at first update after 1 replacement marker: `expected compile errors but received empty terminal error_bundle` |

The named failures are in
[extra-note stderr](../../build-ready-runtime/runner-completeness/logs/control-repaired-extra-note.stderr),
[skip-emit stderr](../../build-ready-runtime/runner-completeness/logs/control-repaired-skip-emit.stderr)
and [empty-errors stderr](../../build-ready-runtime/runner-completeness/logs/control-repaired-empty-errors.stderr).
All six runner signal fields are null, with matching `.time` exits. These three
REDs are intentional **runner-checker failures**, not compiler failures, compiler
ABRTs, malformed transport or timeouts. The compiler still generated the normal
fixture responses; the isolated runner controls supplied the wrong completeness
state to the live checks after preserving framed message consumption. The
trailing-note case instead supplied one extra fixture expectation.

### Restored matrix: 47 native outcomes plus 3 separate semantic outcomes

The restored binary completed all 12/12 planned invocations with exit 0 and
null runner signal. For every update, this audit matched the ordered raw
`info(status): update:` label directly to the existing fixture directive and
checked its `emit_digest stderr:` or `error_bundle stderr:` result header.
The expected outcome kind was derived from the source fixture, not inferred
from a successful exit alone.

| Restored scope | Invocations | Updates | Native stdout-success expectations | Expected-error outcomes |
| --- | ---: | ---: | ---: | ---: |
| Explicit insertion, five fixtures | 5 | 22 | 10 | 12 |
| Explicit layered, five fixtures | 5 | 22 | 10 | 12 |
| Omitted analysis order, temporary_parse_error | 1 | 3 | 2 | 1 |
| Native total | 11 | 47 | 22 | 25 |

The separate sema `temporary_parse_error` invocation completed 3/3 updates:
two semantic success outcomes and one expected parse error. It does not add
executable stdout coverage. All 12 restored stderr files contain no mutation
marker, runner error, warning or execution-skip diagnostic. The 22 native
stdout expectations therefore took the existing success checks without the
runner's logged foreign-target skip paths. Expected compile errors are valid
test outcomes, not failed compiler processes or 25 failed tests.

The native runs reused the five original prepared fixtures and existing wrappers.
The root identified the logging-fixed candidate from the preparation receipt;
its binary remains in the unchanged 28-path bank. The exact runtime argv,
wrapper choice and ordering are in `root-restored-matrix.json`. These are
runner-checker results, not new index-shadow or scheduler-performance evidence.

The sema log actually has `emit_digest stderr:` at lines 3 and 194633, with its
expected-error result at line 194081. Consequently, both successes already
passed the sema emit branch before terminal handling. The newly added sema
**no-prior-emit fallback is still UNPROVEN**. There are also no dedicated
`.unknown`, `.exit_code`, foreign-executor, or stale-success-flag negative
controls in this finite run. Nothing here establishes every backend, OOM
recovery, promotion, publication or release acceptance.

### Audited evidence scope and exact hashes

The full raw scan covered 387,428,163 stderr bytes across all 25 logsets:
387,425,811 bytes from 18 runtime stderr files plus 2,352 bytes from seven build
stderr files. All 18/18 runtime stderr hashes match their respective root JSON
records. The original preparation bank was independently rechecked at 28/28
paths, including original/repaired source, all preserved mutants, fixture
controls, existing wrappers, old runner and candidate. No source-bank member
was changed during this audit.

The three root manifests are the exact-path index for the evidence:

```text
1d0e0450ac84d6304ce10f75dd9331cebb8f7138807231753adf6a8bcabab82e  build-ready-runtime/runner-completeness/audit/root-builds.json
34193b3961128767c30d2ee2be3aa56c50c6f1cf78d4ac7999b4d9f0b8ecd55e  build-ready-runtime/runner-completeness/audit/root-controls.json
e92265ff99a36789b30c8e823e7c1073b76819c9ed33a5f03e8de021ef3ea8cd  build-ready-runtime/runner-completeness/audit/root-restored-matrix.json
0c9349e469290537de54ad258a38d98722f8702bef383ead214b0b5af5f85100  build-ready-runtime/runner-completeness/audit/SHA256SUMS
```

For all 75 raw log files, the canonical current SHA-256 list hashes to
`e36008153b07bab4c0f378aa722e331ba643231d9f32e76830bb283c5d96a1f1`.
Its exact derivation is: take each `args[2]` time path from the six build records,
six control records, restored `build`, and twelve restored records; derive its
`.stdout` and `.stderr` siblings; remove `/K3D/GitHub/cgm-zig/` from each path;
hash those 75/75 files; sort by relative path under `LC_ALL=C`; encode each row
as lowercase SHA-256, two spaces, relative path and LF. This binds the raw time
and empty-output files as well as the 18 stderr hashes already listed in JSON.

Current binary hashes, all independently checked, with paths relative to
`build-ready-runtime/runner-completeness/bin/`:

```text
12ab3ae529b45482529c1119e64819b94533c391cd9088b0c8935165b0f0a164  original
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  repaired
06c1dbba167784eb0a34bef415212e583024562f4e48497ba0b8f7d1715c0ae2  original-skip-emit
b588809e0c011073727b5228c6412caea6f0ea25b3a96ade90f459f410ea7d05  repaired-skip-emit
3f4f31de64aa9fff80a86dd59a345dd3320892dd6c01841afebac15c638efe71  original-empty-errors
8e853da92b96a3478f1fe7ac1b968d75575b44c7139a9ce678c3b4030a9f1471  repaired-empty-errors
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  repaired-restored
```

This addendum's commands were read-only `sed`, `rg`, `awk`, `wc`, `ls`,
`sha256sum` and the preparation bank's `sha256sum -c`. In-memory comparisons
checked every manifest/time argv and exit, every runtime stderr hash, exact
fixture labels and per-update result-header shape. The cooperating auditor
invoked no compiler, formatter, Sema, runner, test or child agent, and made no
Git mutation or cleanup. Only this dated addendum was written, with `apply_patch`.
