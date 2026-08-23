# vharness — run the whole patch/005 V-list in one pass

`docs/crown/PATCH005_VERIFICATION.md` queues the rows. The 2026-08-23 run
executed most of them and left nine **NOT RUN**, several for the same reason:
*nobody had prepared a script*. This directory is that preparation. It exists so
that a later single measurement pass can fire **every** row, and so that a row
that still cannot run says **exactly why** instead of being missing from the
table.

> A row that did not run reports **UNKNOWN** — never zero, never green,
> never "should be fine".

## Run it

```bash
# what exists
python3 partner_tools/vharness/run_vlist.py --list

# the real measurement pass
python3 partner_tools/vharness/run_vlist.py \
    --zig build-p005/stage3/bin/zig \
    --ref build-safe/stage3/bin/zig \
    --repeats 7 --det-runs 5 --slow \
    > docs/crown/PATCH005_VERIFICATION_RUN_<date>.md

# one row, or a few
python3 partner_tools/vharness/run_vlist.py --only V8,V10 --repeats 3
python3 partner_tools/vharness/run_vlist.py --group 005c
```

A markdown table goes to **stdout** (paste-ready into a verification document);
progress goes to **stderr**; a JSON sidecar with every raw sample, exit code and
digest lands in `build-vharness/runs/<timestamp>/vlist.json`.

Exit code: `1` if any row is RED, else `0`. **UNKNOWN never fails the run** — an
absent instrument is not a defect in the thing under test.

### Flags that matter

| Flag | Why |
|---|---|
| `--zig` / `--ref` | the two arms. Every A/B row is one code path over these two fields |
| `--repeats N` | repeats per timing arm. Default 3; **7 is supported and is what the promotion benchmark used** |
| `--det-runs N` | N for the determinism rows (V12). Default **5**, per the row |
| `--mask` | CPU mask for every compile. Default `4-11` |
| `--workload` | `selfhost` (default, ~780 modules, ~50 s/run), `stdpull` (~1 s/run), `fanout` |
| `--slow` | also run rows marked slow (H3 — it rebuilds the compiler, ≈40 min) |
| `--time-report-json PATH` | consume a **pre-collected** machine-readable time report when the compiler cannot produce one |
| `--no-regen` | reuse fixtures already on disk instead of regenerating (the self-host snapshot is 268 MB) |

### Environment — handled for you, and why each piece exists

The harness sets these itself; you do not export anything.

- **`ZIG_LIBC`** — Debian multiarch puts `asm/types.h` under
  `/usr/include/<triple>/`, so any `-lc` sub-compilation (libunwind first) fails
  with `'asm/types.h' file not found`. The harness reuses
  `build-p005/vwork/libc.txt` if it survives and **generates a replacement if it
  does not** — an external cleaner destroyed that exact file between two commands
  during the previous lane's run, and a harness that depends on surviving scratch
  reports UNKNOWN for reasons that have nothing to do with the compiler.
- **`ZIG_GLOBAL_CACHE_DIR` / `ZIG_LOCAL_CACHE_DIR`** — forced repo-local under
  `build-vharness/` (gitignored by `build-*/`). The default `~/.cache/zig` is a
  symlink into another project's tree on this station and lost artifacts
  mid-build.
- **Cold local cache per run** on every determinism and timing row. A warm local
  cache makes run 2 a copy of run 1's artifact, which passes any identity test by
  *not compiling*.

### Snapshot your binaries before a long pass

Measured the hard way while authoring this: a concurrent lane's `ninja -C
build-p005` moved `build-p005/stage3/bin/zig` aside **mid-pass**, and every
subsequent row reported `rc=127`. The harness degraded honestly (UNKNOWN and RED
with the missing-file text in the evidence), but the pass was wasted. Copy the
tree you intend to measure:

```bash
cp -a build-p005/stage3 build-vharness/bin/p005-stage3
python3 partner_tools/vharness/run_vlist.py --zig build-vharness/bin/p005-stage3/bin/zig ...
```

## Machine courtesy

The header line of every pass records whether a competing build was running at
the start, and every timing row is then to be read as **CONTENDED**. The harness
**never kills a process it did not start**. It does kill its own: `run_cmd`
starts each child in its own process group and, on timeout, signals that group —
so a hung compiler the harness launched cannot survive as an orphan that the
next lane's courtesy check would find and nobody would admit to.

## Fixtures — generated, never committed

`fixtures/generate.py` builds every workload from nothing:

| Fixture | Shape | Used by |
|---|---|---|
| `hello` | 3-line program | V1, V2, V2-EXP, V-S1b |
| `stdpull` | `refAllDecls` over 15 std namespaces, ~10 MB artifact | V11, V12-P1-OLD, V12-P1B, V4 |
| `fanout` | **1,200** leaf files, one root, AstGen-dominated | V5, V12-P1A |
| `modgraph` | cyclic (`root→a→b→a`) **and** acyclic (`root→a`) pair | V9 |
| `multistep` | 6 executables → 13 build steps | V10, V-S4a, V-S4b, V-BR |
| `topo` | `std.Thread.Topology.detect` probe program | V-S1a |
| `selfhost` | `git archive HEAD src lib` — a **frozen** 268 MB snapshot | V7-SUB, V8, V13, V13-MM, V15 |

Two decisions worth their reasons:

- **Generated, not committed.** The fan-out alone is 1,201 files. The previous
  lane's fixtures lived under `build-p005/vwork/` and an external cleaner
  destroyed one set mid-run — so the answer is not "keep them safer", it is
  "regenerate them".
- **`selfhost` is frozen at `HEAD`, not the live tree.** While this harness was
  being written, a concurrent lane's in-flight edit left `src/main.zig`
  unparseable. Measuring an A/B against a workload that changes underneath the
  arms is not an A/B.

## The V12 criterion — old and new, both implemented

The V-list's part 1 said: whole-file byte identity of `zig build-exe` output
across N runs at default `-j`. **That criterion is invalid**, and the harness
proves it rather than asserting it:

| Row | Criterion | What it is for |
|---|---|---|
| `V12-P1-OLD` | whole-file sha256, N runs, **fired against BOTH binaries** | reproduces the invalidity: the *unpatched* reference fails it identically, and a criterion the negative control also fails is not a race detector |
| `V12-P1A` | whole-file sha256 across N runs on the **1,200-file AstGen fan-out**, plus identity against that fixture's own `-j1` output | the valid instrument, on the phase the A1 lane split actually rewrote |
| `V12-P1B` | **`.text` section** sha256 across N runs on the std-pulling workload, extracted with `objcopy -O binary --only-section=.text` (the tool used is recorded in the evidence line) | the valid instrument for a linked artifact: the run-to-run variation lives entirely outside `.text` |
| `V12-P2-TSAN` | a ThreadSanitizer stage3, probed for | the **direct** instrument for R12 — unbuildable here, reported UNKNOWN with the exact header that blocks it |
| `V12-P2-NC` | sabotage + TSan red | V12's own instrument control, unreachable while P2 is |

`V12-P1-OLD`'s decision rule is fixed in its docstring *before* the run: if the
reference produces one digest and the patched arm many, that is **RED** and the
strongest finding the harness can make.

Confirmed while authoring, on the promoted (unpatched) 0.16.0 binary, 3 runs,
cold local cache each: **3 distinct whole-file digests, 1 `.text` digest.**

## Row → harness → instrument

37 rows. `--list` prints this table from the registry, so it cannot drift from
the code; the columns below add what each row is *for*.

| Row | Function | Instrument | Runs today? |
|---|---|---|---|
| `V0` | `rows_005a.v0` | binary presence, `zig version`, sha256 | yes (the BUILD half is performed elsewhere) |
| `V0a` | `rows_005a.v0a` | sysfs `thread_siblings_list` + `lscpu` + affinity-aware `nproc` | yes |
| `V1` | `rows_005a.v1` | report line vs the V0a oracle, 4 arms | yes |
| `V11` | `rows_005a.v11` | whole-file + `.text` sha256, patched vs reference | yes |
| `V-S1b` | `rows_005a.vs1b` | same, on `hello.zig` | yes |
| `V14` | `rows_005a.v14` | **sabotage rebuild** | no — patch prepared, `git apply --check` verified live |
| `V-S1a` | `rows_005a.vs1a` | `Topology.detect` under 7 masks vs the oracle | yes |
| `V2` | `rows_005b.v2` | exit code + hang timeout at `-j1` | yes |
| `V2-EXP` | `rows_005b.v2_exp` | the V-list's own stated numbers for `-j1` | yes |
| `V3` | `rows_005b.v3` | **sabotage rebuild** | no — patch prepared |
| `V4` | `rows_005b.v4` | time report: phase reals vs wall | only with `--time-report-json` |
| `V5` | `rows_005b.v5` | 1,200 files at `-j64`: liveness + digest vs `-j1` | yes |
| `V6` | `rows_005b.v6` | time report **+** per-partition `items.len` | no — both instruments absent, named separately |
| `V7a` / `V7b` | `rows_005b.v7a` / `.v7b` | private ~1,800-module product | no — **BLOCKED BY CHARTER** |
| `V7-SUB` | `rows_005b.v7_sub` | frozen self-host pass, `/usr/bin/time -v` | yes — a *different* row, never a stand-in for V7 |
| `V12-P1-OLD` | `rows_005b.v12_p1_old` | whole-file sha256, both binaries | yes |
| `V12-P1A` | `rows_005b.v12_p1a` | fan-out whole-file + `-j1` | yes |
| `V12-P1B` | `rows_005b.v12_p1b` | `.text` section sha256 | yes |
| `V12-P2-TSAN` | `rows_005b.v12_p2` | TSan stage3 | no — `libtsan` needs `linux/scc.h` |
| `V12-P2-NC` | `rows_005b.v12_p2_nc` | sabotage + TSan | no — unreachable while P2 is |
| `V13` | `rows_005b.v13` | wall clock, `-j6` vs `-j12`, alternated | yes (confounded form, labelled) |
| `V13-MM` | `rows_005b.v13_mm` | wall clock, physical vs logical **within the mask** | yes |
| `V15` | `rows_005b.v15` | `eu-stack` thread sampling + instrument control | yes |
| `V8` | `rows_005c.v8` | wall clock, `insertion` vs `layered`, alternated | yes |
| `V9` | `rows_005c.v9` | ranking line's cycle counter, cyclic **+ acyclic control** | yes |
| `V10` | `rows_005c.v10` | wall clock over 13 steps, 3 orders incl. the `declared` control | yes |
| `V-S2a` / `V-S2b` | `rows_riders.vs2a` / `.vs2b` | **sabotage rebuilds** | no — patches prepared |
| `V-S4a` | `rows_riders.vs4a` | `ps -eLf` thread census every 150 ms | yes |
| `V-S4b` | `rows_riders.vs4b` | wall clock alternated **+ peak process-tree RSS** | yes |
| `V-BR` | `rows_riders.vbr` | count of `^error:` / `native failure` on a green build | yes |
| `H1` | `rows_held.h1` | binary presence + version + sha | yes |
| `H2` | `rows_held.h2` | four diagnostic lines vs the fixture README's own block | yes |
| `H3` | `rows_held.h3` | `zig build test-cases` / `test-incremental` | only with `--slow` |
| `H4` | `rows_held.h4` | `zig fmt --check`, denominator from `git diff` | yes |
| `H5` | `rows_held.h5` | PRE/POST anchor move, reference vs patched | yes |

**Coverage: 26 of 37 rows execute a measurement with no extra work.** One more
(`H3`) runs on `--slow`. Two more (`V4`, `V6`) light up the moment a compiler
that accepts `--time-report-json <path>` is available — the harness *probes*, it
does not assume. Four (`V3`, `V14`, `V-S2a`, `V-S2b`) have prepared, verified
sabotage patches and an exact recipe in `sabotage/README.md`. Four are
un-harnessable here for reasons no script can fix: `V7a`/`V7b` (charter),
`V12-P2-TSAN`/`V12-P2-NC` (`linux/scc.h`).

## Timing statistics

`vlib.Timing` / `vlib.compare` / `vlib.paired_wins`, used by every timing row —
there is one implementation, not one per row.

- **Every raw sample survives** into the evidence line and the JSON: samples in
  run order, exit codes, peak RSS where measured.
- median, min, max, spread, stdev, IQR.
- **`n = 1` reports stdev UNKNOWN, not `0.0`.** A single sample has no spread;
  printing `0.0` would be a lie with a decimal point. IQR is UNKNOWN below n=4.
- **Arms are alternated** (a, b, a, b, …) so a machine whose load drifts
  penalises both equally, and `paired_wins` counts slot by slot with its
  denominator.
- **The noise floor is stated in words.** `compare()` flags `inside_noise` when
  the median delta is no larger than the larger arm's stdev, or when the IQRs
  overlap, and writes *"INSIDE the noise floor: this is a note, not a claim"*
  into the evidence. At `n = 1` it refuses outright: *"the delta is NOT yet a
  measurement"*.
- **Complete separation** (no overlap between the two arms' ranges) is reported
  as its own fact, because it is the one cheap non-parametric statement worth
  making on three repeats.

`partner_tools/oracle_lib.py` is reused for `sha256_file`, `assert_anchor` and
`revert_verified`; nothing is duplicated from it.

## Files

| File | Contents |
|---|---|
| `run_vlist.py` | the driver: selection, context, markdown + JSON emission |
| `vlib.py` | `Verdict`, the row registry, `run_cmd`, timing statistics, digests, probes, the topology oracle, report-line parsing |
| `rows_005a.py` | V0, V0a, V1, V11, V-S1b, V14, V-S1a + the shared sabotage-row plumbing |
| `rows_005b.py` | V2, V2-EXP, V3, V4, V5, V6, V7a, V7b, V7-SUB, the five V12 rows, V13, V13-MM, V15 |
| `rows_005c.py` | V8, V9, V10 |
| `rows_riders.py` | V-S2a, V-S2b, V-S4a, V-S4b, V-BR |
| `rows_held.py` | H1–H5 |
| `fixtures/generate.py` | every workload, generated |
| `sabotage/` | four reviewed `.patch` files + the recipe, expected red text and revert step for each |

Rows register themselves with `@vlib.row(...)`. **No file anywhere holds a list
of rows** — `--list`, the driver and this README's coverage claim all read the
same registry.

## Self-test receipts

Every row function below was executed at least once. Where a row genuinely
cannot execute, **the receipt is the UNKNOWN line it printed** — that is the
harness working, not the harness failing.

Conditions for these receipts: `--repeats 1`, another lane's `ninja -C
build-p005` stage3 rebuild running for part of the window (so every wall time
here is CONTENDED and none of these numbers is a measurement of the patch — they
are receipts that the code paths run).

```
python3 partner_tools/vharness/vlib.py --self-test
  -> SELF-TEST: 21/21 checks passed

python3 partner_tools/vharness/fixtures/generate.py --all
  -> OK: 7 of 7 fixture sets generated (1204 leaf source files where a file
     count applies), 1.34 s

python3 partner_tools/vharness/run_vlist.py --list
  -> 37 rows registered

# refusals, both fired
run_vlist.py --only NOSUCHROW,V8   -> REFUSE: unknown row id(s) ['NOSUCHROW']; run --list   (rc=2)
run_vlist.py (absent --zig)        -> REFUSE: --zig binary not found at <path>              (rc=2)
```

`--zig` = a `cp -a` snapshot of `build-p005/stage3` (sha `1f77637cb45d4c42…`),
`--ref` = `build-safe/stage3/bin/zig` (sha `60fad8a75bb23803…`).

| Pass | Rows | Result |
|---|---|---|
| `--only V0,V0a,V1,V2,V2-EXP,V9 --repeats 1` | 6 | 6 of 6 executed, rc=0 |
| `--only <21 cheap + UNKNOWN rows> --repeats 1` | 21 | 21 of 21 executed, rc=0 |
| `--only V11,V-S1b,V12-P1-OLD,V12-P1A,V12-P1B --det-runs 2` | 5 | 5 of 5 executed, rc=0 |
| `--only V10,V-S4a,V-S4b,V-BR --repeats 1` | 4 | 4 of 4 executed, rc=1 (V-BR is a real RED) |
| `--only V10,V8,V13,V13-MM --repeats 1 --workload stdpull` | 4 | 4 of 4 executed, rc=0 |
| `--only V15,V7-SUB --repeats 1` (self-host workload) | 2 | 2 of 2 executed, rc=0 |
| `--only H3` (no `--slow`) | 1 | the UNKNOWN line, with the exact invocation |

**37 of 37 rows have at least one execution receipt** in
`build-vharness/runs/*/vlist.json`.

Selected evidence lines, so the receipts are checkable and not merely counted:

| Row | Verdict | Evidence (abridged) |
|---|---|---|
| `V0a` | GREEN | 12 logical / 6 physical, siblings `0,6 1,7 2,8 3,9 4,10 5,11` (SPLIT); mask `0-3` → `nproc` 4; `lscpu -e` under the same pin still printed 12 rows — affinity-blind, the V-list defect this row inherited |
| `V1` | RED | 3 of 4 arms agree with the oracle; index space **derived** as 30 bits from arm 1; R9 does not fire. **Arm 2 hangs** — see below |
| `V-S1a` | GREEN | 7 of 7 masks match the sysfs oracle including the `null` a mixed mask must produce; the same probe **refuses to build** against the reference — the control that proves `Topology` is patch-added |
| `V5` | GREEN | 1,200 files, `-j64`, rc=0 in 0.132 s, digest identical across `-j64` / `-j1` / default |
| `V9` | GREEN | cyclic 4 modules / depth 3 / **1** in import cycles; acyclic control 3 / 2 / **0** |
| `V12-P1-OLD` | GREEN *(as an invalidity proof)* | reference 2 distinct digests of 2 runs, patched 2 of 2 — the negative control fails the criterion identically |
| `V12-P1A` | GREEN | patched 1 distinct of 2 at default `-j`, **identical to its own `-j1` output**; reference control likewise |
| `V12-P1B` | GREEN | patched `.text` 1 distinct of 2; the *same runs'* whole-file digests: 2 distinct on both arms |
| `V11` / `V-S1b` | INCONCLUSIVE | stock `.text` differs, but with **both arms pinned to one `lib/zig` it is identical** — the stock difference is the std source each binary ships, not the code generator |
| `V-S4a` | GREEN | `--child-jobs=keep` peaks at **35** worker threads on an 8-CPU mask (4.38×); `share` at 10 |
| `V-S4b` | INCONCLUSIVE (n=1) | peak process-tree RSS **share 1,078,148 KB vs keep 1,083,628 KB** — the half the previous run left UNKNOWN |
| `V-BR` | RED | both arms exit 0 with `13/13 steps succeeded`; patched stderr **6** `^error:` and **6** `native failure`, reference **0** and **0** |
| `V15` | GREEN | 96 samples, 1,046 thread-samples, **0** parked; instrument control **5,307** Zig frames resolved, so near-zero is a measurement, not a symbolisation failure |
| `V7-SUB` | GREEN | patched rc=0 wall 51.410 s peak RSS 1,391,676 KB; reference rc=0 wall 50.254 s — **and it says in its own evidence that it is not V7a/V7b** |
| `H2` / `H4` / `H5` | GREEN | 4 of 4 expected lines; `zig fmt --check` rc=0 over 15 of 15 branch-touched files; PRE `mod_b.zig` → POST `dupe.zig` |
| `V3` / `V14` / `V-S2a` / `V-S2b` | UNKNOWN | *the receipt is the UNKNOWN line*: "needs a SABOTAGE REBUILD … prepared patch … `git apply --check` rc=0 (applies cleanly to the current tree)". 4 of 4 |
| `V4` / `V6` | UNKNOWN | *the receipt is the UNKNOWN line*: `--time-report-json` not recognised by either binary today; V6 additionally names its second missing instrument separately |
| `V7a` / `V7b` | UNKNOWN | *the receipt is the UNKNOWN line*: "BLOCKED BY CHARTER — names a private ~1,800-module product … no lawful substitute reproduces the 67,108,864-item ceiling" |
| `V12-P2-TSAN` / `-NC` | UNKNOWN | *the receipt is the UNKNOWN line*, carrying the `linux/scc.h` cause verbatim |

### Two things the self-test itself found

1. **A hang the V-list never saw.** `build-obj -j4 --intern-partitions=2` on a
   trivial `hello.zig` **does not terminate** (killed at the harness's 120 s
   cap); the same command without `--intern-partitions=2` finishes in 0.226 s.
   The 2026-08-23 run observed that `--intern-partitions=2` reports
   `alloc lanes 0` and that "nothing refuses, warns, or explains" — but its
   fixture errored out before compiling anything, so the consequence went
   unseen. V1 now carries an explicit
   `alloc lanes 0 did not deadlock the compile` check and reports RED.
2. **A rule fired on an unknown noise floor.** At `--repeats 1`, V10 fired its
   retraction rule off a single sample. Fixed: a rule may only fire when
   `inside_noise is False`, never when the floor is UNKNOWN. All five timing
   rows now return INCONCLUSIVE at n=1 with *"the delta is NOT yet a
   measurement"*.

Conditions, so none of the numbers above is mistaken for a result: **every one
was taken at `--repeats 1` while a concurrent lane's stage3 rebuild held the
machine** (load average ≈ 8 on a 12-thread host, harness masked to `4-11`).
They are receipts that the code paths run and produce plausible output. The
measurement pass is `--repeats 7 --det-runs 5` on a quiet machine.

## Named residuals

- **Wall time is not `cpu_ns_sema` and is not `real_ns_files`.** V8 and V13 name
  compiler-internal counters; until `--time-report-json` exists, those rows
  measure a superset and say so in every evidence line.
- **The `.text`-identity rows do not prove absence of a race.** They prove the
  semantic output was stable across N runs on this host with this fixture. R12's
  direct instrument is a race detector, and it is still unbuilt.
- **`V7-SUB` is not `V7a`.** No in-repo workload approaches 67,108,864 items on
  one partition, so the 2× margin and the panic reproduction stay UNMEASURED.
- **One host, one topology.** Every mask-derived expectation is checked against
  *this* machine's sysfs. Nothing here says anything about a 16-physical-core
  host, a cgroup CPU quota (invisible to `sched_getaffinity`), Windows or Darwin.
- **`V-S4b`'s RSS half is now measured, but by sampling.** Peak process-tree RSS
  from `ps` at a 150 ms interval can miss a spike between samples; it is a floor
  on the true peak, not the peak.
- **The sabotage patches are context-matched.** They are re-checked with `git
  apply --check` on every pass precisely because concurrent lanes edit these
  files; a patch that stops applying reports so instead of pretending.

---

*Even in the lixão, a flower is born.*
