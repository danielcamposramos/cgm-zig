# Logging-fixed candidate verification — 2026-09-06

The logging-fixed candidate completes the bounded functional update checks and
emits live scheduler records for the requested scope. **This is not
index-versus-scan shadow agreement, OOM verification or a performance result.**

Direction: Daniel Campos Ramos. Candidate build and runtime executions: the
coordinating GPT 6 Astra (OpenAI Codex) partner. Independent raw-artifact review
and this receipt: a cooperating GPT-6 (OpenAI Codex) partner. The earlier
partners' design and source contributions remain credited in the existing
provenance. Upstream-Status: not-filed-policy.

This review created only this document. It executed the candidate's `version`
command once, but no compilation, Sema check or tests. The clean-shadow build
was active in another lane; no competing compiler work was started. Existing
source, logs, summary JSON, shadow, README/PLAN and receipts remain unchanged.

## Candidate and build

Candidate: [log-fixed-stage3/bin/zig](../../build-release-2026-09-06/log-fixed-stage3/bin/zig).
Fresh version result: `0.16.0+cgm.0399d2b19b`, exit 0. SHA-256:
`d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f`.
Recorded source: `0399d2b19b71ed865cc2e6d5e21224f124e373db`.

The raw [build time/exit record](../../build-release-2026-09-06/build-log-fixed.time)
reports **exit 0, wall 10:30.94, maximum RSS 6,430,960 KiB**. Build stdout is
0 bytes; [build stderr](../../build-release-2026-09-06/build-log-fixed.stderr)
is 615 bytes of existing topology/child-compiler/step-order informational output.
The exact timed argv is:

```sh
PROMOTED/zig build \
    --prefix /K3D/GitHub/cgm-zig/build-release-2026-09-06/log-fixed-stage3 \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib \
    -Dversion-string=0.16.0+cgm.0399d2b19b -Dtarget=native -Dcpu=baseline \
    -Denable-llvm -Dconfig_h=/K3D/GitHub/cgm-zig/build-release-2026-09-06/config.h \
    -Dno-langref -Ddebug-extensions -Dlog -Doptimize=ReleaseSafe
```

This is a real recorded ReleaseSafe compiler build, not a parse/Sema-only
receipt. The actual [generated options](../../build-release-2026-09-06/log-fixed-cache/c/4e919b7996dbf6fdef9b96d2077f0996/options.zig)
were read completely: `have_llvm=true`, `dev=.full`,
`enable_debug_extensions=true`, `enable_logging=true`, threaded I/O and direct
value interpretation. `file` identifies x86-64 Linux ELF, dynamically linked,
with debug information, not stripped. `readelf -d` identifies RUNPATH
`/usr/lib/llvm-21/lib` and dependencies on `libLLVM.so.21.1` and
`libclang-cpp.so.21.1`, plus system runtime/compression libraries. Thus this is
a baseline-CPU, system-LLVM-21 dynamic build, not a self-contained package.
The build cost is one observed build, not a comparative speed measurement.

## Independent counting correction

The raw [summary JSON](../../build-ready-runtime/log-fixed-summary.json) uses
the field name `selection_records` for **every** line anchored by:

```text
debug(zcu): findOutdatedToAnalyze:
```

That prefix also includes `all up-to-date` completion notices. Independent
streaming review found:

- Runner logs: **33,873 scheduler events = 33,826 selection-bearing records
  + 47 all-up-to-date notices**.
- Direct matching-scope log: **2,036 scheduler events = 2,035 selections
  + 1 all-up-to-date notice**.

Therefore neither 33,873 nor 2,036 is accurately labeled a pure selection
count. All eleven JSON `selection_records` values have this same definition
issue. Their raw event counts, stderr byte counts/hashes, updates, exit statuses
and wall times otherwise agree with the independently read artifacts. This
receipt distinguishes the quantities and leaves the historical JSON untouched.

Update labels were independently extracted only from anchored
`info(status): update: '<label>'` lines and compared, in order, to the complete
`#update=` lists in the actual five prepared fixtures. **47/47 labels match
exactly**, including deliberate-error updates. Selection counts exclude only
the exact anchored `all up-to-date` message, not arbitrary match text.

## Three direct logging controls

All three use the same
[public hello-world source](../../test/standalone/simple/hello_world/hello.zig),
SHA-256 `e29eeed5df701c00e7819366ff5f32dff860861a01be7200b1668cd642cb9912`.
They are Sema-only compilations performed by the coordinator, not executions
of the hello-world program. The retained outputs independently establish:

| Scope request | Raw stderr | `debug(zcu)` lines | Scheduler events | Actual selections |
| --- | ---: | ---: | ---: | ---: |
| [None](../../build-ready-runtime/log-fixed-none.stderr) | 421 bytes | 0 | 0 | 0 |
| [Nonmatching](../../build-ready-runtime/log-fixed-wrong.stderr), `ready_gate_unmatched_control` | 421 bytes | 0 | 0 | 0 |
| [Matching](../../build-ready-runtime/log-fixed-matching.stderr), `zcu` | 12,854,325 bytes | 158,583 | 2,036 | 2,035 |

None and nonmatching stderr are **byte-identical**, containing only the normal
thread-plan and layered-ranking informational lines. Their SHA-256 is
`1bb18591ddc32a4013dfeb03a265aea9a2b69bf6fb895507d2240380a0998e24`.
Matching stderr SHA-256 is
`d5b3ad53c1b9dd57966a1c5582d10bc68ada5c79d99ccc180b640cd345fb1bb0`.
All three stdout files are empty. This is a positive reached-scope control and
two scope-isolation controls, not a scratch-source sabotage.

The coordinator reports **3/3 direct commands exited 0** in execution session
47161, with an explicit per-command rc check. No local per-case rc/time
manifest was persisted; those exit codes are attributed to that execution
report, **not inferred from the stdout/stderr files**.

The coordinator preserved the following direct argv and output paths, from
the fork root, with `ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt`:

```sh
build-release-2026-09-06/log-fixed-stage3/bin/zig build-exe \
    -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib \
    --cache-dir build-ready-runtime/log-fixed-${case}-cache \
    --analysis-order=layered -j1 --intern-partitions=2 \
    <scope-arguments> test/standalone/simple/hello_world/hello.zig \
    > build-ready-runtime/log-fixed-${case}.stdout \
    2> build-ready-runtime/log-fixed-${case}.stderr
```

Here `case=none` has no scope arguments, `wrong` has
`--debug-log ready_gate_unmatched_control`, and `matching` has `--debug-log zcu`.
The exact historical global-cache environment path was not preserved and is
**UNKNOWN**; it is not reconstructed from an assumed default. For reproduction
use a newly named repo-local global cache and new output destinations, retaining
the historical logs. That is a reproduction choice, not historical provenance.

## Eleven incremental runner invocations

Every actual `.time` file was read, including its timed command and exit
status. **11/11 recorded invocations exited 0**. The five fixtures run under
both explicit orders, then temporary-parse-error runs with the order omitted:

| Mode / fixture | Expected updates matched | Scheduler events | Actual selections | Wall |
| --- | ---: | ---: | ---: | ---: |
| insertion / change_module | 4/4 | 3,045 | 3,041 | 5.78 s |
| insertion / type_dependency_loop | 5/5 | 3,052 | 3,046 | 5.73 s |
| insertion / temporary_parse_error | 3/3 | 3,032 | 3,029 | 5.71 s |
| insertion / analysis_error_and_syntax_error | 6/6 | 3,036 | 3,032 | 5.76 s |
| insertion / add_remove_struct_fields | 4/4 | 3,264 | 3,259 | 5.88 s |
| layered / change_module | 4/4 | 3,041 | 3,037 | 5.83 s |
| layered / type_dependency_loop | 5/5 | 3,048 | 3,042 | 5.74 s |
| layered / temporary_parse_error | 3/3 | 3,028 | 3,025 | 5.57 s |
| layered / analysis_error_and_syntax_error | 6/6 | 3,032 | 3,028 | 5.72 s |
| layered / add_remove_struct_fields | 4/4 | 3,263 | 3,258 | 6.15 s |
| omitted / temporary_parse_error | 3/3 | 3,032 | 3,029 | 5.72 s |
| Total | 47/47 | 33,873 | 33,826 | Not a timing comparison |

Of the selection-bearing records, 33,822 are ordinary ready-unit selections
and 4 explicitly name `dependency loop affecting ... selected ...` (2 in each
type-dependency-loop order). This is a narrow observed fallback trace, not a
claim of exhaustive cycle or tier coverage. Different insertion/layered event
totals are not forced into equality: these modes deliberately reorder work.

The runner validates expected diagnostics and successful-program outcomes;
47 matched update labels do **not** mean 47 compilations without errors.
These are functional/error-recovery and logging-reach results. Logs contain
standard-library work as well as fixture work; none of the selection totals
is presented as a fixture-only unit count. All eleven runner stdout files
are empty; expected program stdout is checked internally by the runner.

Exact argv retained in every explicit-mode `.time` file, with its fixture name:

```sh
timeout --kill-after=10s 180s ./incr-check ./zig-under-test fixtures/<fixture> \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
    --debug-log zcu --debug-log zcu_deps
```

Execution cwd was `build-ready-runtime/`; the explicit wrapper selects
`READY_INDEX_ORDER=insertion` or `layered` and passes the recorded candidate
through `READY_INDEX_CANDIDATE`. The omitted-mode command substitutes
`./zig-under-test-default` and `fixtures/temporary_parse_error`. The wrappers,
runner and fixture bodies are the existing prepared artifacts documented in
`READY_INDEX_RUNTIME_PREPARATION_2026-09-06.md`; no new implementation was used.
For reproduction preserve the timeout and `--preserve-tmp`, use the identified
candidate, and choose new output paths instead of overwriting this evidence.

## Exact raw-log links and checksums

The following table gives stderr SHA-256 and time/exit-log SHA-256. Each link
resolves the exact retained file. Independently hashed stderr sizes also match
all eleven summary rows.

| Run | Stderr SHA-256 | Time/exit SHA-256 |
| --- | --- | --- |
| insertion / change_module | [ea9562cfc502bff00456c129b0a6b93f5dc9a2a189e8f2da2ef696206d850c55](../../build-ready-runtime/log-fixed-insertion-change_module.stderr) | [d7b6dcc3b4c10d7d23fae07b44299815d64d2c68ae38cac25fcacd9d2aca89f1](../../build-ready-runtime/log-fixed-insertion-change_module.time) |
| insertion / type_dependency_loop | [c504657e8166bf31de8f2f587a0e8045ef94379aee8347088ded0c550176dfc1](../../build-ready-runtime/log-fixed-insertion-type_dependency_loop.stderr) | [03e3085ef4218174dfc68682d1856e98d90b97ca54c9f4d4796ce4ad0206167f](../../build-ready-runtime/log-fixed-insertion-type_dependency_loop.time) |
| insertion / temporary_parse_error | [aba4db54be8220749c79ce2bb6dba62b03fcfb11e1507a7d0da55061c6167b59](../../build-ready-runtime/log-fixed-insertion-temporary_parse_error.stderr) | [d59ddd41f2af6251c801c59a40a63a3eae153da18647977ad9c0d12ee6033b13](../../build-ready-runtime/log-fixed-insertion-temporary_parse_error.time) |
| insertion / analysis_error_and_syntax_error | [cdf9a4c44c3e261326a39f24ebce6b6429e5e4c0970a3a7b84b6596f21095abc](../../build-ready-runtime/log-fixed-insertion-analysis_error_and_syntax_error.stderr) | [699e1142b7ab0eb3af6aa531557a70d2c6d6a9186c885a61d279254ff3484231](../../build-ready-runtime/log-fixed-insertion-analysis_error_and_syntax_error.time) |
| insertion / add_remove_struct_fields | [b8274739243f665dc5ebe58afd9e2110e768b49d4d88c79175976ba5d7b08ae7](../../build-ready-runtime/log-fixed-insertion-add_remove_struct_fields.stderr) | [7f067338ab0bd4eef24a005e8a3f7de0fe5fa1e97c5d05e5f2754f6d5d6001b9](../../build-ready-runtime/log-fixed-insertion-add_remove_struct_fields.time) |
| layered / change_module | [59d0489698345999006a8e16325df52ea4575e306fdd12360bea718661b8b38f](../../build-ready-runtime/log-fixed-layered-change_module.stderr) | [fbb675410b6a92db4d0ddb3be83c7097e779367c8905d6a008719dceea9992f3](../../build-ready-runtime/log-fixed-layered-change_module.time) |
| layered / type_dependency_loop | [91d233e84403e6e4cbe1931d0c8dab4e6c67f3d2090439893d1cf131ba8da3d9](../../build-ready-runtime/log-fixed-layered-type_dependency_loop.stderr) | [6f7544ed864e390ee64aeba2c2cb3014e8e92ee6cb57f11d265abff9d45b7ec9](../../build-ready-runtime/log-fixed-layered-type_dependency_loop.time) |
| layered / temporary_parse_error | [e4dc415b673c034a0f69e7c1b7572819c097c70bbf62d1e13646093f0d5ed65c](../../build-ready-runtime/log-fixed-layered-temporary_parse_error.stderr) | [62343a3ee4ffe97a35b0ce6027fb489388acdaa3046b474bb2fed0d43aa6afe8](../../build-ready-runtime/log-fixed-layered-temporary_parse_error.time) |
| layered / analysis_error_and_syntax_error | [9fcae94b56e8aa31d63e2836254ec1086bb9e83fce1db7bd2e1b04de617a49b1](../../build-ready-runtime/log-fixed-layered-analysis_error_and_syntax_error.stderr) | [449c96a6409006eecc4287e668c0f2bc2ed472b78bf4155ee163125ea32fde9a](../../build-ready-runtime/log-fixed-layered-analysis_error_and_syntax_error.time) |
| layered / add_remove_struct_fields | [ec3109451adc5d9ef0d15ccd969f1c7a4835f20280dc145bc19e57033c84ebcc](../../build-ready-runtime/log-fixed-layered-add_remove_struct_fields.stderr) | [4282f6fee026e3d1cfc0b5b1471f41bb6add8bedbb23d6834decef2d992a69fb](../../build-ready-runtime/log-fixed-layered-add_remove_struct_fields.time) |
| omitted / temporary_parse_error | [b485866eade8d0a281340d9a5b243815d09aabd9829c0d4927f5661049c9c84c](../../build-ready-runtime/log-fixed-default-temporary_parse_error.stderr) | [c4939f6ea0952ae05ef3963db2ee70315de978c16ef329e0a3acae7643c104eb](../../build-ready-runtime/log-fixed-default-temporary_parse_error.time) |

Additional SHA-256 anchors:

- Build `.time`: `1868e529c1e5e901c5f916c00efb23b0f8f9c50c966544985f99dd14454ec641`.
- Build `.stderr`: `ad1803b38161f2e7e6981bc70029079d42ce31ba817c059cfb9468efd0138f22`.
- Generated options: `c7bf1c7cad3283ed522143c04cf866c73c9dac59698937f823747d5c28fe4899`.
- Unmodified summary JSON: `ced259bb875de5f09c98615749a38e4b2780bdb96dc967008d246f102d1fedfb`.
- All **15/15 inspected stdout files** (build + 3 direct + 11 runner files) are
  0 bytes, SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

## Boundary

This candidate demonstrates the logging-gate correction on one ReleaseSafe
build and bounded incremental functional checks under both selectable orders
and an omitted-order control. It does not prove shadow heap-versus-scan
agreement, optional OOM fallback, all tier/cycle transitions, default zero-index
allocation, race freedom, logging-disabled builds, other compiler-mode logging policies or optimization
speedup. Those remain named outstanding verification tasks. No claim here
promotes the binary or declares packaging/publication complete.

Review commands were bounded `sed`/`wc` reads, read-only streaming hash/count
and expected-label comparison, `sha256sum`, `file`, `readelf -d`, relevant
configuration searches, and the one allowed candidate `version` invocation.
Large logs were streamed and summarized rather than dumped. The count
discrepancy and absent direct rc/global-cache manifests were explicitly
reported to the coordinator instead of silently normalized.
