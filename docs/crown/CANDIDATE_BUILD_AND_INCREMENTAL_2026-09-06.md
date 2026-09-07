# Candidate build and first incremental run — 2026-09-06

Root coordinating partner GPT 6 Astra, under Daniel Campos Ramos's direction.
This is a real build and bounded functional test receipt, NOT promotion.

## Built identity

Source commit: d3347292c997c286cdd9dd5af037bf545ff9212a. Root's post-build
comparison found no src/lib/build.zig/CMakeLists changes against that commit.
Candidate: build-release-2026-09-06/stage3/bin/zig.
Version: 0.16.0+cgm.d3347292c9.
SHA256: 7803c128bb4319f9b5958e3104ad6b879b9310171da996ee612d5224ac740008.
Promoted SHA remains046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11.

Fresh configure command, exit0:

```sh
cmake -S . -B build-release-2026-09-06 -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DZIG_RELEASE_SAFE=ON -DZIG_STATIC_LLVM=OFF '-DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions;-Dlog' -DZIG_TARGET_MCPU=baseline -DZIG_VERSION=0.16.0+cgm.d3347292c9
```

Root inspected its unique stage3 command for ReleaseSafe, debug extensions,
logging, baseline CPU and no strip. It then self-hosted with PROMOTED/zig using
the same build graph/configuration and fresh prefix, instead of rebuilding
bootstrap zig1/zig2.

First attempt exited1: root omitted the fresh configuration's required
zigcpp/libzigcpp.a. Original build.stdout/stderr/time retain the missing-file
failure. This was a root preparation error, not a compiler defect. The explicit
prerequisite `ninja -C build-release-2026-09-06 zigcpp` then succeeded6/6 steps.
No prior artifact or log was overwritten/deleted.

Successful second attempt:

```sh
ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-release-2026-09-06/gcache ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-release-2026-09-06/cache /usr/bin/time -v -o build-release-2026-09-06/build-attempt2.time PROMOTED/zig build --prefix /K3D/GitHub/cgm-zig/build-release-2026-09-06/stage3 --zig-lib-dir /K3D/GitHub/cgm-zig/lib -Dversion-string=0.16.0+cgm.d3347292c9 -Dtarget=native -Dcpu=baseline -Denable-llvm -Dconfig_h=/K3D/GitHub/cgm-zig/build-release-2026-09-06/config.h -Dno-langref -Ddebug-extensions -Dlog -Doptimize=ReleaseSafe > build-release-2026-09-06/build-attempt2.stdout 2> build-release-2026-09-06/build-attempt2.stderr
```

Exit0; wall8:52.04; peakRSS5,948,652KiB; CPU100%. No imposed affinity mask
(0-11 available); no competing compiler build was found before execution.
This is a build cost, not an optimization benchmark. Actual generated options
declare have_llvm=true, enable_debug_extensions=true, enable_logging=true and
the version above. readelf shows .debug_info/.debug_line/.symtab. These establish
configuration/unstripped output, not working debug-log visibility (see below).

Linkage is dynamic: libclang-cpp.so.21.1, libLLVM.so.21.1, libz.so.1,
libzstd.so.1, libstdc++.so.6, libc.so.6 and ld-linux-x86-64.so.2;
RUNPATH /usr/lib/llvm-21/lib. Baseline CPU is not standalone-portability proof.
Package compatibility/dependency disclosure remains required.

## Fixture review and actual runs

Root read all324 runtime-packet lines, all162 preparation-receipt lines, both
wrappers and the actual runner argument/update flow. Root's first reversal
regex mistakenly required a space after // and restored no directives; its
five false comparisons were an instrument error. Reversing exactly the three
named target comments matched original bytes5/5. Copies preserve22 updates per
mode; omitted/default recovery adds3. The five original bodies remain intact.

Root built tools/incr-check.zig with PROMOTED/zig -OReleaseSafe and the
preparation receipt's repo-local caches/libc, exit0. Both wrapper version
probes exited0 with the candidate version and no mode requirement. Root checked
32 planned log destinations absent before running.

Actual runner shape, sequential from build-ready-runtime, with the environment
and five fixture names in the preparation receipt:

```sh
/usr/bin/time -v -o "${READY_INDEX_ORDER}-${ready_fixture}.time" timeout --kill-after=10s 180s ./incr-check ./zig-under-test "fixtures/${ready_fixture}" --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp --debug-log zcu --debug-log zcu_deps > "${READY_INDEX_ORDER}-${ready_fixture}.stdout" 2> "${READY_INDEX_ORDER}-${ready_fixture}.stderr"
```

READY_INDEX_CANDIDATE was the exact candidate path above. Modes were insertion
and layered; the loop stopped on any nonzero exit. None occurred. Default used
zig-under-test-default and temporary_parse_error with the same180secondtimeout
and flags, exit0. All scratch remains through --preserve-tmp.

| Fixture | Insertion updates / exit | Layered updates / exit |
|---|---:|---:|
| change_module | 4 / 0 | 4 / 0 |
| type_dependency_loop | 5 / 0 | 5 / 0 |
| temporary_parse_error | 3 / 0 | 3 / 0 |
| analysis_error_and_syntax_error | 6 / 0 | 6 / 0 |
| add_remove_struct_fields | 4 / 0 | 4 / 0 |

Ten of ten explicit-mode runner invocations accepted44/44 scheduled update
expectations, plus one default invocation accepted3/3. Some updates deliberately
expect compilation errors; this is not47 successful compilations. Eleven logs
contain47 update labels and ZERO findOutdatedToAnalyze lines.

## First-class defect: diagnostic calls are compiled away

Despite enable_logging=true, src/main.zig selects std_options.log_level=.info
in ReleaseSafe. lib/std/log.zig:64-83 checks logEnabled at comptime and returns
before the custom runtime main.log filter. Thus --debug-log cannot expose
debug calls in this configuration. Missing traces mean UNKNOWN scheduler
reach/agreement, not zero disagreements. Functional fixture results do not
close actual indexed/scan, OOM/tier/cycle or negative-control obligations.

Root granted a narrow main logging configuration/filter repair and its own new
receipt, not an index redesign, public knob or hand-maintained scope list.
The repair must retain mode-derived defaults (especially ReleaseSmall) and
requested-scope behavior. A corrected candidate and actual logging controls
are required before relying on traces. All old artifacts/logs/seals remain.
No promotion, package, push or release occurred here.

Receipt-authoring correction: root's first Node assembly command had an escaped
template-string syntax error and exited before writing any file. This receipt
was then authored directly with apply_patch; the failed command changed no
compiler source or evidence artifact.
