# Ready-index runtime preparation — 2026-09-06

This wave prepared only section 1 of
`READY_INDEX_RUNTIME_VERIFICATION_PACKET_2026-09-06.md`: five isolated fixture
copies and two executable wrappers. **No compiler, runner, wrapper or fixture
was executed.** Shadow instrumentation remains withheld and was not authored.

Direction: Daniel Campos Ramos, through the coordinating maintainer's bounded
grant. Preparation: GPT-6 (OpenAI Codex), working as an AI partner. Existing
upstream fixture bodies and authorship are preserved; the only fixture edits
select one existing native target. Upstream-Status: not-filed-policy.

## Starting state and exact scope

The coordinator identified candidate source commit
`d3347292c997c286cdd9dd5af037bf545ff9212a` and an active compiler build. The
expected candidate path is
`/K3D/GitHub/cgm-zig/build-release-2026-09-06/stage3/bin/zig`; it was **not
treated as verified or invoked**. No Git command was run in this wave.

Read-only existence checks found **8/8 intended destinations absent**: the five
fixtures, two wrappers and this receipt. All were created through `apply_patch`;
no existing destination was overwritten. Only these exact wrapper paths had
their executable permission enabled:

```sh
chmod +x build-ready-runtime/zig-under-test build-ready-runtime/zig-under-test-default
```

Final permissions were **775 / 775 for the two wrappers**. There was no cleanup,
no unrelated source copy, no runner implementation, no build/test execution,
and no production, existing-test, README or previous-receipt edit.

## Fixture preservation

Each original full file was read before copying. Its first active target,
`#target=x86_64-linux-selfhosted`, remains active. Exactly three other active
target directives per file were commented: x86_64-linux-cbe,
x86_64-windows-cbe and x86_64-linux-llvm. Existing commented targets remain
unchanged. No source body, expected error, stdout expectation, module directive
or update label changed.

| Fixture under `build-ready-runtime/fixtures/` | Active selected targets / active targets | Update directives | `rm_file` directives |
| --- | ---: | ---: | ---: |
| `change_module` | 1/1 | 4 | 0 |
| `type_dependency_loop` | 1/1 | 5 | 0 |
| `temporary_parse_error` | 1/1 | 3 | 0 |
| `analysis_error_and_syntax_error` | 1/1 | 6 | 0 |
| `add_remove_struct_fields` | 1/1 | 4 | 0 |

The selected target exists in **5/5 original files and 5/5 copies**.
`uname -sm` returned `Linux x86_64`, matching the selected native architecture
and OS. The runner's parser splits the final target component as backend
(`tools/incr-check.zig:744`); `.selfhosted` is an existing accepted backend.
Actual target compilation remains UNRUN, not inferred from the host name.

The parser recognizes `#update=` directives outside file bodies. Inspection
and the same nonempty directive syntax counted **22 updates / 5 fixtures**;
both selectable modes therefore plan **44 update evaluations**, some of which
deliberately expect compilation errors. An omitted-mode control is additional,
not part of that 44-update denominator. No `#rm_file=` occurs in the five files.

Body-preservation check: reverse **only** the three target-comment changes in
memory and compare to each original. **5/5 byte comparisons matched**, exit 0.
No temporary reverse-copy file was written:

```sh
for ready_fixture in change_module type_dependency_loop temporary_parse_error analysis_error_and_syntax_error add_remove_struct_fields; do
    cmp -s "test/incremental/$ready_fixture" <(sed \
        -e 's@^//#target=x86_64-linux-cbe$@#target=x86_64-linux-cbe@' \
        -e 's@^//#target=x86_64-windows-cbe$@#target=x86_64-windows-cbe@' \
        -e 's@^//#target=x86_64-linux-llvm$@#target=x86_64-linux-llvm@' \
        "build-ready-runtime/fixtures/$ready_fixture") || exit 1
done
```

The source and destination hashes were independently read with `sha256sum`.
All five original hashes match their PRE values:

| Fixture | Original SHA-256 (PRE = POST) | Prepared copy SHA-256 |
| --- | --- | --- |
| `change_module` | `0b111aac27d218a05e3484cdd6f1c0652dc554f1343803de98715106a224dc18` | `7a5c30ad5e38e61f013ba86872846f1749dc42729f0a7b3e63df34a0f003ce56` |
| `type_dependency_loop` | `095064870f9ebff279d79ae6c0fdbec5bf49348b5c68f324a9fa2100365976be` | `82475f2fd51b0a9890843af8259726dba3b30ee4a1b7588de51c4f53114e6f68` |
| `temporary_parse_error` | `f64592033fdf531c0325618e95f890d803713c09c65f6834f21baa796bf3dc89` | `f7a3e2fe43b88dcb117a04b0380ca4b04b630572ed00f9d768e9c76efe2e0fa5` |
| `analysis_error_and_syntax_error` | `c7787c772e1394b40610eaa81da63ea9a5fd0e132001ca6caa6105881bc8c0c7` | `a05862a973c6e656df69e981d950202badd99903aa70b483332ca6bd53781760` |
| `add_remove_struct_fields` | `fe2073c3c9897c983be87570ecb97bbaa1fb4cedf6d8b4946ec83232d3ba6408` | `c464378418e4ca3ce40b84bb9fce5795cb5f777335f53fc3c832f171e53487b0` |

## Wrapper call-flow review

The runner launches `[explicit_binary, "build-exe", ...]` at lines 139-151,
including `-fincremental`, cache paths and `--listen=-`, then retains that one
child across the fixture's updates (lines 195-246). It uses piped stdin/stdout
for IPC and separately captures stderr. The native self-hosted backend adds
`-fno-llvm -fno-lld` to that same command; no C-compiler subprocess is selected.

Both wrappers pass the original argument vector as quoted `"$@"` through
`exec`, with no stdout output. Only when the first argument is `build-exe` do
they append `-j1 --intern-partitions=2`. The explicit-mode wrapper additionally
validates `READY_INDEX_ORDER` as insertion or layered and appends that exact
analysis-order flag. The default wrapper never appends an analysis-order flag.
Version, environment, help and other probe commands are passed untouched and
do not require `READY_INDEX_ORDER`. Both require an explicit
`READY_INDEX_CANDIDATE`; neither substitutes the promoted or old reference
compiler. Invalid mode reports to stderr and exits 2 before compiler execution.
These are source-backed call-flow conclusions, not executed wrapper tests.

Wrapper SHA-256:

- `zig-under-test`: `77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027`.
- `zig-under-test-default`: `3a71bc702bc3b9b548f182b68d4d335ea6427bb6fc9f8107982669679b81bad1`.

## Exact queued commands — NOT RUN

Only after the coordinating maintainer confirms the candidate build, verifies
its identity/configuration, checks machine courtesy and grants execution:

```sh
cd /K3D/GitHub/cgm-zig
export READY_INDEX_CANDIDATE=/K3D/GitHub/cgm-zig/build-release-2026-09-06/stage3/bin/zig
export ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/gcache
export ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/tool-cache
export ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
PROMOTED/zig build-exe tools/incr-check.zig -OReleaseSafe \
    -femit-bin=build-ready-runtime/incr-check

cd /K3D/GitHub/cgm-zig/build-ready-runtime
./zig-under-test version
./zig-under-test-default version
for READY_INDEX_ORDER in insertion layered; do
    export READY_INDEX_ORDER
    for ready_fixture in change_module type_dependency_loop temporary_parse_error analysis_error_and_syntax_error add_remove_struct_fields; do
        /usr/bin/time -v -o "${READY_INDEX_ORDER}-${ready_fixture}.time" \
            ./incr-check ./zig-under-test "fixtures/${ready_fixture}" \
            --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
            --debug-log zcu --debug-log zcu_deps \
            > "${READY_INDEX_ORDER}-${ready_fixture}.stdout" \
            2> "${READY_INDEX_ORDER}-${ready_fixture}.stderr"
        ready_rc=$?
        printf '%s %s rc=%s\n' "$READY_INDEX_ORDER" "$ready_fixture" "$ready_rc"
        if [ "$ready_rc" -ne 0 ]; then exit "$ready_rc"; fi
    done
done
./incr-check ./zig-under-test-default fixtures/temporary_parse_error \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
    --debug-log zcu --debug-log zcu_deps \
    > default-temporary_parse_error.stdout 2> default-temporary_parse_error.stderr
```

Before these commands, refuse if the intended output/log paths already exist;
allocate a separately named run location rather than overwrite earlier evidence.
Keep `--preserve-tmp` on every invocation to prevent the runner's default scratch
deletion. The final omitted-mode control plans 3 additional updates, separately
reported from 44 explicit-mode updates. Runtime results, actual index/wrapper
reach, shadow agreement, negative controls, timing/RSS and default-allocation
behavior are all **UNRUN / UNKNOWN**. The preparation checks above are not a
promotion verdict and do not extend the shadow-authoring grant.

Commands actually run in this wave were read-only destination existence checks,
`sed`/`rg` over runner and fixtures, `uname -sm`, `cmp` with the bounded `sed`
reversal above, an `awk` directive counter, `sha256sum`, `stat`, and the single
explicit two-path `chmod +x`. Raw file creation used `apply_patch` only. No Git,
compiler process, runner, wrapper or test program was invoked.
