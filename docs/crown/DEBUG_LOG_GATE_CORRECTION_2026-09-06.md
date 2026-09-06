# Compiler debug-log admission correction — 2026-09-06

This finite correction changes only the compiler's logging configuration and
filter in `src/main.zig`. It does not change the standard library, ready-index
algorithm, flags, scope names, fixtures or previous receipts. No compiler was
rebuilt or promoted in this wave.

Direction: Daniel Campos Ramos, through the coordinating maintainer's bounded
grant. Source correction and bounded verification: GPT-6 (OpenAI Codex),
working as an AI partner. Upstream-Status: not-filed-policy.

## Measured PRE and cause

The coordinator built the first candidate from
`d3347292c997c286cdd9dd5af037bf545ff9212a`, with ReleaseSafe, debug extensions,
logging enabled, baseline CPU and no stripping. Its SHA-256 is
`7803c128bb4319f9b5958e3104ad6b879b9310171da996ee612d5224ac740008`.
The coordinator then reported:

- **10/10 fixture/order invocations exited 0**, covering 44 update labels.
- The omitted-order temporary-parse-error control exited 0, adding 3 labels.
- **47/47 expected update labels appeared**, but **0 selected-unit log lines**
  containing `findOutdatedToAnalyze` appeared despite requesting `.zcu` and
  `.zcu_deps` debug logs.

Those 47 updates remain functional evidence from the first candidate. They
provide **UNKNOWN trace/index reach**, not zero selection disagreements. This
wave did not rerun or reinterpret the fixture successes as trace coverage.

Source inspection established the missing instrument's cause:

1. PRE `main.zig:48-56` set `std_options.log_level` to `.info` in ReleaseSafe,
   independent of `build_options.enable_logging`.
2. `lib/std/log.zig:64-83` checks `logEnabled` at comptime and returns before
   calling the custom `std.options.logFn` when the level is above that limit.
3. Therefore `.debug` messages never reached `main.log`'s existing runtime
   `-Dlog`/`--debug-log` scope filter. `-Dlog` alone could not enable them.

Prior-art inspection covered the actual std.log gate, the compiler's existing
mode switch and runtime filter, both debug-log argument handlers, and
`build.zig:250-251,362` where the existing logging option is defined/emitted.
No per-scope compile-time roster is configured by main. No standard-library
change or new flag is needed.

## POST policy and source invariants

The old mode-derived threshold is now the local `default_log_level` constant.
`std_options.log_level` serves only compile-time admission:

- With `enable_logging=true`, admit through `.debug` so the custom runtime
  scope filter can receive those calls.
- With `enable_logging=false`, admit through `.info` in Debug/ReleaseSafe/
  ReleaseFast and `.err` in ReleaseSmall. Debug log bodies are thus excluded
  at the standard-library comptime gate even for a Debug compiler explicitly
  built with logging disabled.

The runtime filter still requires enabled logging **and an exact requested
scope** for any level above the original mode threshold **or above `.info`**.
It now compares against `default_log_level`, not the widened admission gate.
The original scope-list loop and default logger remain unchanged.

| Compiler mode | No requested scope, logging either enabled or disabled | Additional levels permitted for an exact requested scope when logging enabled |
| --- | --- | --- |
| Debug | error, warning, info | debug |
| ReleaseSafe | error, warning, info | debug |
| ReleaseFast | error, warning, info | debug |
| ReleaseSmall | error only | warning, info, debug |

This is a source-derived policy table, not four-mode runtime test evidence.
Debug has always required an explicit scope for debug output because the
existing filter separately checks `level > .info`. ReleaseSmall's `.err`
default is intentionally retained; merely setting the admission limit to
`.debug` and continuing to use it as the runtime default would leak unrequested
warning/info output in that mode. Requested above-default messages can now
reach the existing scope filter instead of being silently compiled out.

Error/default output, logging-disabled warnings in the argument handlers, and
exact scope-name matching are unchanged. In ReleaseSmall, the existing `.warn`
diagnostic about disabled logging is itself excluded by the error-only policy;
this correction does not silently widen that mode's default just to show it.
No `.zcu` special case or global enable-all debug behavior was added.

## Bounded verification

Read-only process inspection found no live compiler build before the one
Sema-only check. The coordinator was notified while that check owned the lane
and again when it completed. All manual edits used `apply_patch`.

```sh
PROMOTED/zig ast-check src/main.zig && PROMOTED/zig fmt --check src/main.zig
```

Result: exit 0, no stdout/stderr; **1/1 touched Zig file parsed and 1/1 passed
format checking**. These checks do not observe emitted compiler logging.

The actual first candidate's generated options were read completely from
`build-release-2026-09-06/cache/c/d811353a716a46a74138d2ac82ce2df9/options.zig`.
They set `dev=.full`, `enable_logging=true`,
`enable_debug_extensions=true`, threaded I/O and direct value interpretation.
The similarly named `build-release-2026-09-06/config.zig` is bootstrap
configuration with logging disabled and was **not** used for this check.

Exact single Sema-only command:

```sh
ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/gcache \
ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/debug-log-gate-cache \
ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt \
/usr/bin/time -v -o build-ready-runtime/debug-log-gate-sema.time \
PROMOTED/zig build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ \
    --dep aro --dep build_options \
    -Mroot=src/main.zig -Maro=lib/compiler/aro/aro.zig \
    -Mbuild_options=build-release-2026-09-06/cache/c/d811353a716a46a74138d2ac82ce2df9/options.zig \
    > build-ready-runtime/debug-log-gate-sema.stdout \
    2> build-ready-runtime/debug-log-gate-sema.stderr
```

**1/1 authorized Sema-only invocation exited 0**: wall **51.75 s**, peak RSS
**1,571,504 KiB**, stdout **0 bytes**, stderr **336 bytes** containing only the
unchanged promoted compiler's thread-topology informational line. Newly
admitted debug bodies type-check with the actual full/logging-enabled options.
No compiler executable was emitted; these measurements are check cost, not
compiler-performance or runtime logging evidence. Logs and caches remain at
the named repo-local paths. All three log destinations were checked absent
before this invocation; existing shared cache content was retained.

## SHA-256 anchors

| Owner/artifact | PRE | POST |
| --- | --- | --- |
| `src/main.zig` | `6ab974698ebfb9faed9900da66e72d931a845532f809f1630efdf813c12181ad` | `a9d0b4ad425d333271edcd88dd4359bcfec4885ef2545f796b1fee298b6024a5` |
| `lib/std/log.zig` | `cbdb8541c466901541570eed140dc1a652f3d186728a3b3017b441c3bb79d118` | unchanged |
| Actual generated candidate options | `603eaf8f237b9a6858ead7ad7de8385ddca58e0b4ddc238568b8fbe8f894e9d9` | unchanged |
| Promoted compiler | `046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11` | unchanged |
| First candidate compiler | `7803c128bb4319f9b5958e3104ad6b879b9310171da996ee612d5224ac740008` | unchanged |

## Required next controls and residuals

The coordinator owns the next full candidate build and runtime controls on the
same bounded input with no requested scope, a different requested scope, and
the matching requested scope. Required evidence: unchanged default diagnostics,
no debug lines for unrequested scopes, and a positive count for a known reached
matching scope. A logging-disabled compiler must retain the named warning
where its mode permits warnings and produce no requested debug output.

Only after positive log reach may a `findOutdatedToAnalyze` trace count support
ready-set coverage; general `.zcu` logs alone do not prove that specific path
ran. Shadow selection agreement, missing-hook controls, actual index-allocation
reach, semantic-cycle fallback, new-binary mode comparisons, negative/positive
logging controls, compiler rebuild, promotion and release remain **UNRUN /
UNKNOWN in this correction wave**. The observed first-candidate trace absence
is a real PRE failure of the instrument, not a fired scratch sabotage. No
unrun negative is presented as green or checksum-restored behavior.

This wave ran only source/option reads, `rg`, `sha256sum`, process inspection,
the exact main parse/format checks, one no-artifact Sema check and receipt reads.
It performed no Git mutation, standard-library edit, full compiler build,
fixture batch, cleanup, toolchain repoint or publication.
