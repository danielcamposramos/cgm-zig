# Ready-index live shadow — clean runtime evidence, 2026-09-06

The bounded clean run agrees with the original scan on all **10,678 indexed
selection events**. All four planned broken-checker/hook controls are armed;
none is proven red by this receipt. This is integration evidence, not compiler
release acceptance, a speedup measurement, or broad concurrency verification.

Direction: Daniel Campos Ramos. Builds, runtime orchestration and integration:
GPT 6 Astra (OpenAI Codex). Shadow source preparation and independent read-only
runtime audit: cooperating OpenAI Codex partners. Original design and partner
authorship remain credited in PROVENANCE.md. Upstream-Status: not-filed-policy.

## Rebuilt artifact, not a helper-only test

The independently archived source at commit
0399d2b19b71ed865cc2e6d5e21224f124e373db plus the three-owner scratch observation
patch is described in READY_INDEX_SHADOW_PREPARATION_2026-09-06.md. Root read the
entire 212-line patch and checked the 21,931-file post-state bank. The observers
read the same live ready maps as production and compare selected map positions,
not just rank equality. They also observe actual wrappers and update epochs.

Full/log-enabled Sema-only checking exited0, wall56.32s/RSS1,570,264KiB. That
produced no compiler artifact. The subsequent actual Safe/baseline/debug/log
build exited0, wall10:24.47/RSS6,484,960KiB, separately recorded in
[build-clean.time](../../build-ready-shadow-2026-09-06/audit/build-clean.time).
The original validated system-LLVM21 bridge/configuration was reused; source,
cache and output were isolated. The build was not simultaneous with another
compiler build, but ordinary orchestration continued; timing is not a clean
performance benchmark.

Binary: [clean-stage3/bin/zig](../../build-ready-shadow-2026-09-06/clean-stage3/bin/zig).
Root-invoked version: 0.16.0+cgm.0399d2b19b.shadow, exit0. SHA256:
01d3b88dad37d11bcdcafe815095d5545d2cdd4af6ad467fc365d227ed43d1b2.
Actual generated options, read completely:
[options.zig](../../build-ready-shadow-2026-09-06/build-cache/c/46d511a14bc6db7f673a37511030fc76/options.zig):
LLVM enabled, dev full, logging true, debug extensions true, version as above.

## Executed finite fixture set

The existing incremental runner and prepared extensionless fixtures were used
unchanged: change_module, type_dependency_loop, temporary_parse_error,
analysis_error_and_syntax_error, add_remove_struct_fields, each under insertion
and layered; temporary_parse_error also with the order omitted. Each invocation
uses the existing wrapper, a180-second timeout, preserved temporary tree and
zcu/zcu_deps logs. Exact argv/exit/signal are retained in the
[V2 execution manifest](../../build-ready-shadow-2026-09-06/audit/clean-runtime-executions-v2.json).
The manifest also identifies the actual candidate by full hash.

The first attempt incorrectly added .case to an existing extensionless fixture
path. It returned FileNotFound before compiler launch. Its
[V1 manifest](../../build-ready-shadow-2026-09-06/audit/clean-runtime-executions.json)
and outputs are preserved. That was a root orchestration error, not a compiler
negative control. V2 uses the resolved actual paths and new output filenames.

Independent audit read all11 stderr/time pairs (320,829,115 stderr bytes),
matched both recorded exit sources at0, and counted47 runner-accepted update
labels:22 insertion,22 layered,3 omitted/default. Per-update outcome shapes
are22 emit-result and25 error-result updates. This is not47 error-free compiles.

Every invocation's first update also builds compiler_rt in insertion mode,
contributing942 ordinary selections. Do not credit that work to layered mode:

| Actual selection scope | Ordinary selections |
| --- | ---: |
| Layered fixture compilations | 10,678 |
| Explicit-insertion fixture compilations | 10,695 |
| Omitted/default fixture compilation | 2,087 |
| Initial insertion-mode compiler_rt compilations | 10,362 |
| Total | 33,822 |

Four further semantic-cycle fallback selections are separate from the ordinary
tier branches. The raw findOutdatedToAnalyze prefix also includes completion
notices; it must not be counted as a pure selection denominator. The earlier
logging-fixed receipt records that terminology correction explicitly.

## Live reach and armed control denominators

All10,678 indexed picks compare equal to the scan, including10,598 with more
than one ready member and380 choosing a nonzero map position. Counts are events,
not distinct units. The following observations are for layered fixture work:

| Actual integration path | Observed reach |
| --- | ---: |
| Active-growing ordinary puts | 12:10 other-tier,2 function-tier |
| Active-growing no-clobber puts | 47,970 |
| Active external struct-default insertions paired with actual no-clobber calls | 2,376 |
| Successful active removals | 48,021 |
| Active non-last removals | 27,776:8,512 function-tier,19,264 other-tier |
| Function selections while both tiers ready | 8,551 |
| Function selections with only functions ready | 12 |
| Other selections with zero ready functions | 2,115 |
| Actual semantic-cycle fallback,ready counts0/outdated1 | 2 |
| Later layered epochs with nonzero memo | 11 |
| Actual early-abort events | 5 |

No-clobber breakdown:9,055 functions,18,229 nav-value,18,229 nav-type,
81 comptime,2,376 struct-defaults. Two additional active removal attempts
found no member. No ordinary duplicate put was observed. Across the whole
run the auditor matched307,582 wrapper before/after pairs with none unmatched.

In [layered change_module](../../build-ready-runtime/shadow-clean-v2-layered-change_module.stderr),
active-growing ordinary puts occur at lines346354/346359. Its ownership-change
epoch has memo98 at345726, and the following double-ownership abort starts with
memo3 at346438. The actual semantic fallback is visible in
[layered type_dependency_loop](../../build-ready-runtime/shadow-clean-v2-layered-type_dependency_loop.stderr).

Thus selection-check inversion, removal of the ordinary append hook, and removal
of update invalidation all have positive clean prerequisites. Default-entry
tripwires also have positive denominators: layered fixtures enter prepare10,678
times and append47,982 times; insertion/default have no helper-entry records.
Explicit insertion has27 zero-capacity exit checks (22fixture+5compiler_rt),
omitted/default has4 (3fixture+1compiler_rt). All four heap capacities and memo
count are zero. This does not prove zero historical memo allocations or zero
total compiler allocation.

## Remaining proof boundaries

There are zero READY_FALLBACK events. Production preparation-OOM and append-OOM
recovery are not established. The helper's earlier allocation-failure tests
remain valid but do not substitute for these wrapper paths. No lost-hook or
checker-inversion variant has yet executed in the evidence covered here. Every
negative must retain its named failure, then restore source by hash, rebuild
a distinct restored binary and rerun the targeted fixture. Restored source
alone is not restored executable evidence.

The mature runner itself has two pre-existing diagnostic-completeness gaps:
checkErrorOutcome does not check that every expected trailing diagnostic was
consumed; its empty terminal error-bundle branch can return without proving an
outcome was observed. Therefore47 runner-accepted updates is the defensible
claim, not independent proof of every trailing diagnostic. The recorded result
shapes agree with expectations, and the gaps do not disarm named panic controls.
A bounded existing-owner repair is under review separately.

Replacing both helper-entry markers with panics will normally hit prepare
first: it is not independent coverage of the append panic. The added scans and
structural checks are deliberate measurement overhead, not shipping code.
Serial -j1 experiments do not prove wide-worker safety. No promotion, package,
online synchronization or full release acceptance is claimed by this receipt.

## 2026-09-07 addendum — selection-checker self-control closed

The [selection self-control receipt](READY_INDEX_SELECTION_SELF_CONTROL_2026-09-07.md)
now records the inverted checker reaching its named RED, all 21,931 source files
restored to the clean bank, and a separately rebuilt restored compiler completing
the four-update layered `change_module` run with 2,095/2,095 indexed comparisons
equal. Earlier UNRUN statements above describe their original evidence boundary
and are retained unchanged. This closes only the selection-checker self-control;
missing-append, invalidation, default-entry and OOM controls are not established
by it. The old runner's outcome-completeness ceiling still applies to these runs.
