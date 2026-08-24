#!/usr/bin/env python3
"""rows_005b.py — the lane split (commit 016d8987), including the HARD GATE.

Rows: V2, V2-EXP, V3, V4, V5, V6, V7a, V7b, V7-SUB,
      V12-P1-OLD, V12-P1A, V12-P1B, V12-P2-TSAN, V12-P2-NC, V13, V13-MM, V15.

**V12 is three rows, not one, and that is the point.** The criterion the V-list
wrote — whole-file byte identity of `zig build-exe` output across runs at
default `-j` — was PROVEN INVALID on 2026-08-23: the *unpatched* reference
compiler fails it identically (3 of 3 distinct digests), so it measures upstream
nondeterminism, not the patch. A criterion the negative control also fails is
not a race detector.

So the old criterion ships here as its own row (`V12-P1-OLD`) fired against
BOTH binaries, which makes the harness reproduce the invalidity proof instead of
asking the reader to trust a previous lane's paragraph. The valid
re-instrumented criterion is `V12-P1A` (whole-file identity on a 1,200-file
AstGen fan-out, N runs plus its own `-j1` output) and `V12-P1B` (`.text` section
identity on a std-pulling workload). Default N = 5.
"""

import json
import os
import re
import subprocess
import threading
import time

import vlib
from vlib import (Verdict, GREEN, RED, UNKNOWN, INCONCLUSIVE, unknown, run_cmd,
                  section_digest, sha256_file, cold_local_cache, Timing,
                  alternate_ab, compare)
from rows_005a import sabotage_row


# ---------------------------------------------------------------------- V2 --

@vlib.row("V2", "005b", "the -j1 member still works (patch/002 Finding 3 regression guard)",
          "exit code + hang timeout on hello.zig")
def v2(ctx):
    fx = ctx.fixtures.get("hello")
    out = os.path.join(ctx.scratch("V2"), "hello_j1")
    r = run_cmd([ctx.zig, "build-exe", "-j1", "-Mroot=hello.zig", f"-femit-bin={out}"],
                cwd=fx["dir"], env=ctx.env_zig, mask=ctx.mask, timeout=300)
    rep = vlib.parse_report_line(r.stderr)
    if r.timed_out:
        return Verdict("V2", RED, "TIMED OUT at -j1 — patch/002 Finding 3 edge 1 (evented tid "
                                  "starvation) has resurfaced", "1 of 1 runs", {"rc": 124})
    ran = run_cmd([out], mask=ctx.mask, timeout=60) if os.path.isfile(out) else None
    ok = r.rc == 0 and rep is not None and rep["workers"] == 1
    ev = (f"rc={r.rc}, no hang, workers {rep['workers'] if rep else 'UNKNOWN'} "
          f"({rep['workers_source'] if rep else '-'}), artifact "
          f"{'runs and prints ' + repr(ran.stderr.strip()[:20]) if ran and ran.rc == 0 else 'not executed'}")
    return Verdict("V2", GREEN if ok else RED, ev, "1 of 1 runs", {"report": rep, "rc": r.rc})


@vlib.row("V2-EXP", "005b", "-j1 changes WORKERS ONLY -- the decoupling, pinned",
          "report line with -j1 vs the same host with no -j at all")
def v2_exp(ctx):
    """Split out from V2 because behaviour and expectation gave different answers.

    HISTORY, kept because the correction is the finding. This row was written to check
    the V-list's stated expectation that `-j1` forces `intern partitions 2` and
    `536,870,911` items. It measured `partitions 8` instead, and the SHIPPED CODE WAS
    RIGHT: `ThreadPlan.derive` takes `partitions` from `partitions_arg orelse topology`
    and `n_jobs` never touches it. The expectation came from dossier 3.8's flag table,
    written before the (K, M_wide) split and carrying the pre-split world where one
    integer meant both quantities. The dossier, the V-list and this row were corrected
    to match the code; the superseded numbers stay quoted below so a reader of an old
    log can tell a version difference from a defect.

    WHAT IT PINS NOW is the property, not a constant, so it is host-independent: `-j1`
    sets workers to 1 and leaves the partition count exactly where the same host derives
    it with no `-j` at all. If `-j` ever starts moving K again, the decoupling this whole
    patch exists for has regressed, and this row goes red.
    """
    fx = ctx.fixtures.get("hello")
    base = ["build-exe", "-fno-emit-bin", "-Mroot=hello.zig"]
    r_j1 = run_cmd([ctx.zig] + base + ["-j1"], cwd=fx["dir"], env=ctx.env_zig,
                   mask=ctx.mask, timeout=300)
    r_free = run_cmd([ctx.zig] + base, cwd=fx["dir"], env=ctx.env_zig,
                     mask=ctx.mask, timeout=300)
    rep_j1 = vlib.parse_report_line(r_j1.stderr)
    rep_free = vlib.parse_report_line(r_free.stderr)
    if rep_j1 is None or rep_free is None:
        return unknown("V2-EXP",
                       f"no report line to compare (rc {r_j1.rc}/{r_free.rc})",
                       "0 of 3 expectations checkable")
    checks = {
        "-j1 sets workers to 1": rep_j1["workers"] == 1,
        "-j1 leaves K where the host derived it":
            rep_j1["partitions"] == rep_free["partitions"],
        "-j1 leaves the item ceiling untouched":
            rep_j1["items"] == rep_free["items"],
    }
    good = sum(1 for v in checks.values() if v)
    ev = (f"-j1 -> workers {rep_j1['workers']}, partitions {rep_j1['partitions']}, "
          f"{rep_j1['items']:,} items; no -j -> workers {rep_free['workers']}, "
          f"partitions {rep_free['partitions']}, {rep_free['items']:,} items. "
          + ("-j1 moved workers and left K alone: the decoupling holds."
             if good == 3 else
             "-j1 MOVED THE PARTITION COUNT -- the (K, M_wide) decoupling has regressed.")
          + " SUPERSEDED EXPECTATION, quoted for old logs: the V-list originally demanded "
            "workers 1 / partitions 2 / 536,870,911 items. That was wrong -- it predated "
            "the split -- and the dossier 3.8 correction records it.")
    return Verdict("V2-EXP", GREEN if good == 3 else RED, ev,
                   f"{good} of 3 properties", {"j1": rep_j1, "free": rep_free,
                                               "checks": checks})


# ---------------------------------------------------------------------- V3 --

@vlib.row("V3", "005b", "negative control for R1, the process-global partition invariant",
          "SABOTAGE REBUILD — prepared patch, not fired")
def v3(ctx):
    return sabotage_row(ctx, "V3")


# --------------------------------------------------- the time-report rows ---

def _time_report_run(ctx, binary, args, cwd, tag, extra=(), timeout=1800):
    """Run a workload and return (Run, time-report dict or None, reason).

    The ONE place that knows how to obtain a machine-readable time report:
      * `--time-report-json <path>` if the binary supports it (probed, not assumed);
      * a caller-supplied `--time-report-json <path>` file if the harness cannot
        produce one itself;
      * otherwise None, with the exact reason as a string.
    """
    probe = ctx.tr_probe.get(binary) or {"status": "absent", "detail": "not probed"}
    if probe["status"] == "json":
        out = os.path.join(ctx.scratch("timereport"), f"{tag}.json")
        r = run_cmd([binary] + list(args) + ["--time-report", "--time-report-json", out] + list(extra),
                    cwd=cwd, env=ctx.env_for(binary), mask=ctx.mask, timeout=timeout, rss=True)
        data = vlib.read_time_report(out)
        if data is None:
            return r, None, f"--time-report-json accepted but no parseable file at {out}"
        return r, data, None
    if ctx.time_report_json:
        data = vlib.read_time_report(ctx.time_report_json)
        if data is not None:
            r = run_cmd([binary] + list(args) + list(extra), cwd=cwd, env=ctx.env_for(binary),
                        mask=ctx.mask, timeout=timeout, rss=True)
            return r, data, ("caller-supplied report (--time-report-json) — it was NOT produced by "
                             "this run and its provenance is the caller's to state")
        return None, None, f"--time-report-json {ctx.time_report_json} is absent or unparseable"
    return None, None, (f"no machine-readable time report from this binary: {probe['detail']}. "
                        f"Pass --time-report-json <path> with a pre-collected report, or run against "
                        f"a compiler that accepts `--time-report-json <path>`.")


@vlib.row("V4", "005b", "the linker kept its concurrent slot (R3)",
          "time report: phase reals vs wall (overlap signature)")
def v4(ctx):
    """Overlap criterion, stated so it can be argued with.

    The row says a run where `real_ns_decls` approx `real_ns` with no link
    overlap means `error.ConcurrencyUnavailable` was hit and `link/Queue.zig`
    took the serial path. The JSON carries per-phase reals but no grand total,
    so the criterion implemented here is:

        sum(real_ns_files, real_ns_decls, real_ns_llvm_emit, real_ns_link_flush)
        > wall_ns  ==> phases overlapped

    with the link-specific form requiring the excess to be at least
    `real_ns_link_flush` — i.e. the link phase's own time is accounted for
    somewhere other than the end of the wall clock. This is a DERIVED criterion,
    not the row's original wording, and it is labelled as such in the verdict.
    """
    wl = vlib.workload(ctx, "stdpull")
    if wl is None:
        return unknown("V4", "mid-size workload fixture missing", "0 of 1 workloads")
    cwd, args, desc = wl
    # THE WORKLOAD MUST ACTUALLY LINK. This row asks whether the LINKER kept its
    # `io.concurrent` slot, and the shared `stdpull` workload carries `-fno-emit-bin`,
    # which skips linking entirely -- so `real_ns_link_flush` came back 0.000s and the
    # criterion below read that zero as "the linker did not overlap" and returned RED.
    # It was measuring a linker that never ran. Verified by hand: the same workload with
    # `-femit-bin` reports real_ns_link_flush = 40,900,663 ns, so the timer is fine and
    # the row's own arguments were the defect.
    link_args = [a for a in args if a != "-fno-emit-bin"]
    emit_to = os.path.join(ctx.scratch("V4"), "v4bin")
    r, tr, reason = _time_report_run(ctx, ctx.zig, ["build-exe"] + link_args, cwd, "V4",
                                     extra=["-j12", "--intern-partitions=8",
                                            f"-femit-bin={emit_to}"])
    if tr is None:
        return unknown("V4", f"NOT RUN — the instrument does not exist here. {reason}",
                       "0 of 1 instruments available")
    keys = ("real_ns_files", "real_ns_decls", "real_ns_llvm_emit", "real_ns_link_flush")
    if not all(k in tr for k in keys):
        return unknown("V4", f"time report present but lacks {[k for k in keys if k not in tr]} "
                             f"(schema {tr.get('schema', 'UNKNOWN')})", "0 of 4 required fields")
    total = sum(tr[k] for k in keys)
    wall_ns = r.wall * 1e9
    excess = total - wall_ns
    # An absent instrument reports UNKNOWN, never zero, and never a negative result.
    # `real_ns_link_flush == 0` means no link work was TIMED -- which is indistinguishable
    # from no link work having HAPPENED. Concluding "the linker did not overlap" from it
    # would be a verdict drawn from a missing measurement.
    if tr["real_ns_link_flush"] == 0:
        return unknown("V4",
                       f"no link work was measured (real_ns_link_flush = 0) on a run that "
                       f"exited rc={r.rc}, so the overlap question is unanswerable here rather "
                       f"than answered negatively. Workload: {desc}",
                       "0 of 1 link phases timed")
    # TWO POSITIVE SIGNATURES, and a refusal to draw a negative from either's absence.
    #
    # (a) sum-of-phase-reals exceeding the wall clock proves phases overlapped. But the
    #     FOUR timed phases do not span the whole run -- startup, arg parsing, cache
    #     lookup and codegen scheduling are outside them -- so `sum < wall` is the normal
    #     case even when everything overlapped. It can prove overlap; it CANNOT disprove
    #     it, and the earlier version of this row returned RED on exactly that
    #     non-evidence.
    #
    # (b) `cpu_ns_link` against `real_ns_link_flush` is the sharper instrument. The flush
    #     is the tail the linker spends alone at the end; `cpu_ns_link` is all CPU the
    #     link phase consumed. If the linker held its `io.concurrent` slot, link work ran
    #     BESIDE analysis and its CPU total dwarfs that tail. If it had fallen back to the
    #     main thread (`error.ConcurrencyUnavailable`, `link/Queue.zig:67-76`), link work
    #     would sit inside the wall clock serially and the two numbers would converge.
    #     Measured here: 459.0 ms CPU against a 40.9 ms flush, a ratio of 11.2.
    link_cpu = tr.get("cpu_ns_link", 0)
    link_real = tr["real_ns_link_flush"]
    overlap_by_sum = excess >= link_real
    ratio = link_cpu / link_real if link_real else None
    overlap_by_cpu = ratio is not None and ratio >= 2.0
    serialised = ratio is not None and ratio <= 1.0
    base = (f"phase reals sum {total / 1e9:.3f}s vs wall {r.wall:.3f}s (excess {excess / 1e9:+.3f}s); "
            f"real_ns_link_flush {link_real / 1e9:.3f}s, cpu_ns_link {link_cpu / 1e9:.3f}s "
            f"(ratio {ratio:.2f}x), real_ns_decls {tr['real_ns_decls'] / 1e9:.3f}s. ")
    if overlap_by_sum or overlap_by_cpu:
        v, why = GREEN, ("link work OVERLAPS analysis: "
                         + ("phase reals exceed the wall clock" if overlap_by_sum else
                            f"link CPU is {ratio:.1f}x its own flush tail, so it ran beside "
                            f"analysis rather than after it"))
    elif serialised:
        v, why = RED, ("link CPU fits inside its own flush window -- the linker ran serially, "
                       "which is the error.ConcurrencyUnavailable signature R3 names")
    else:
        v, why = INCONCLUSIVE, ("neither positive signature fired and the serial signature did "
                                "not either. The four timed phases do not span the wall clock, so "
                                "their sum falling short is not evidence of anything")
    ev = (base + why + ". DERIVED criterion (see this row's docstring), not the V-list's original "
          f"wording; workload: {desc}")
    return Verdict("V4", v, ev, "1 of 1 runs, 4 of 4 report fields",
                   {"time_report": tr, "wall_s": r.wall, "rc": r.rc, "link_ratio": ratio})


@vlib.row("V6", "005b", "is partition 0 really the whole story?",
          "time report + per-partition local.mutate.items.len (absent)")
def v6(ctx):
    """Two instruments, both probed; absent ones are named individually.

    `InternPool.dump` (behind `--verbose-intern-pool`, and behind
    `enable_debug_extensions`) SUMS `local.mutate.items.len` across partitions;
    it does not break the number down per partition. The census claim this row
    tests therefore has no instrument, and the harness says which piece is
    missing rather than reporting one composite UNKNOWN.
    """
    missing = []
    probe = ctx.tr_probe.get(ctx.zig, {"status": "absent", "detail": "not probed"})
    if probe["status"] != "json" and not ctx.time_report_json:
        missing.append(f"machine-readable time report ({probe['detail']})")

    fx = ctx.fixtures.get("hello")
    r = run_cmd([ctx.zig, "build-obj", "-fno-emit-bin", "--verbose-intern-pool", "-Mroot=hello.zig"],
                cwd=fx["dir"], env=ctx.env_zig, mask=ctx.mask, timeout=300)
    blob = r.stdout + r.stderr
    per_partition = re.search(r"partition\s+\d+[^\n]*items", blob, re.I)
    dumped = "intern pool stats" in blob
    if per_partition is None:
        missing.append("per-partition `local.mutate.items.len` output — "
                       + ("`--verbose-intern-pool` dumps a SUM across partitions, not a breakdown "
                          "(src/InternPool.zig dumpStatsFallible)" if dumped else
                          "`--verbose-intern-pool` produced no intern-pool dump at all "
                          "(is this binary built with -Ddebug-extensions?)"))
    if missing:
        return unknown("V6", "NOT RUN — " + "; and ".join(missing) +
                            ". Both are compiler-side additions; when either lands, this row "
                            "picks it up automatically (it probes rather than assumes).",
                       f"0 of 2 required instruments available",
                       verbose_intern_pool_dumped=dumped, probe=probe)
    return unknown("V6", "instruments now present but the lopsidedness comparison is not implemented — "
                         "refusing to invent a verdict from a half-built row",
                   "2 of 2 instruments available, 0 of 1 comparisons implemented")


# ---------------------------------------------------------------------- V5 --

@vlib.row("V5", "005b", "the Io.Group fan-out probe (R4, ziglang/zig#26027)",
          "1,200-file fan-out at -j64: liveness + digest vs -j1")
def v5(ctx):
    """Queued in the dossier at 8, absent from the V-list. Recorded as a V-list defect.

    R4 is a named liveness risk with no acceptance row, so the harness carries
    one rather than inheriting the omission.
    """
    fx = ctx.fixtures.get("fanout")
    d = ctx.scratch("V5")
    outs = {}
    for tag, extra in (("j64", ["-j64", "--intern-partitions=8"]), ("j1", ["-j1"]), ("default", [])):
        e = cold_local_cache(ctx.env_zig, f"V5_{tag}")
        out = os.path.join(d, f"fanout_{tag}.o")
        r = run_cmd([ctx.zig, "build-obj", "-Mroot=root.zig", f"-femit-bin={out}"] + extra,
                    cwd=fx["dir"], env=e, mask=ctx.mask, timeout=600)
        outs[tag] = {"rc": 124 if r.timed_out else r.rc, "wall": r.wall,
                     "sha": sha256_file(out) if os.path.isfile(out) else "UNKNOWN"}
    ok = all(v["rc"] == 0 for v in outs.values())
    same = len({v["sha"] for v in outs.values()}) == 1 and outs["j64"]["sha"] != "UNKNOWN"
    ev = (f"{fx['leaves']} files, -j64 rc={outs['j64']['rc']} in {outs['j64']['wall']:.3f}s "
          f"(no hang); digests -j64/-j1/default "
          f"{'IDENTICAL ' + outs['j64']['sha'][:16] + '…' if same else 'DIFFER: ' + str({k: v['sha'][:12] for k, v in outs.items()})}. "
          f"Denominator honesty: one host, one fixture shape — this does not clear #26027 in general.")
    return Verdict("V5", GREEN if ok and same else RED, ev, "3 of 3 arms (-j64, -j1, default)", outs)


# ------------------------------------------------------------- V7a / V7b ----

def _charter_blocked(rid, what):
    return unknown(
        rid,
        f"BLOCKED BY CHARTER — {what} names a private ~1,800-module product that lives outside "
        f"this repository. This lane is chartered to touch no other project's tree, so the row "
        f"cannot be executed here, and NO lawful substitute reproduces it: the expected "
        f"`--intern-partitions=logical` panic needs 67,108,864 items on one partition and no "
        f"in-repo workload approaches that ceiling. See row V7-SUB for the largest lawful in-repo "
        f"workload — which is a DIFFERENT measurement, not a stand-in for this one.",
        "0 of 1 workloads lawfully available")


@vlib.row("V7a", "005b", "THE worked example on the product that hit the cliff",
          "BLOCKED BY CHARTER — private workload, no lawful substitute")
def v7a(ctx):
    return _charter_blocked("V7a", "the derived-configuration worked example")


@vlib.row("V7b", "005b", "the other two rows of the same table, same compiler",
          "BLOCKED BY CHARTER — private workload, no lawful substitute")
def v7b(ctx):
    return _charter_blocked("V7b", "the --intern-partitions=logical panic reproduction")


@vlib.row("V7-SUB", "005b", "largest LAWFUL in-repo workload — NOT a stand-in for V7a/V7b",
          "/usr/bin/time -v over a frozen self-host front-end pass", cost="~50 s per arm")
def v7_sub(ctx):
    """The honest neighbour of V7a/V7b, labelled so nobody can quote it as V7.

    It exercises the same code paths at ~780 modules. It does not approach the
    67,108,864-item ceiling, so it cannot reproduce the incident, cannot fire
    the patch/001 panic, and proves nothing about the 2x margin V7a claims.
    """
    wl = vlib.workload(ctx, "selfhost")
    if wl is None:
        return unknown("V7-SUB", "self-host snapshot fixture missing or failed to generate "
                                 "(git archive HEAD src lib)", "0 of 1 workloads")
    cwd, args, desc = wl
    res = {}
    for label, binary in (("patched", ctx.zig), ("reference", ctx.ref)):
        e = cold_local_cache(ctx.env_for(binary), f"V7SUB_{label}")
        r = run_cmd([binary, "build-exe"] + args, cwd=cwd, env=e, mask=ctx.mask,
                    timeout=3600, rss=True)
        rep = vlib.parse_report_line(r.stderr)
        res[label] = {"rc": 124 if r.timed_out else r.rc, "wall": r.wall,
                      "peak_rss_kb": r.peak_rss_kb, "report": rep}
    ok = all(v["rc"] == 0 for v in res.values())
    p = res["patched"]
    rss_txt = "{:,} KB".format(p["peak_rss_kb"]) if p["peak_rss_kb"] else "UNKNOWN"
    ev = (f"{desc}; patched rc={p['rc']} wall {p['wall']:.3f}s peak RSS {rss_txt}; reference rc="
          f"{res['reference']['rc']} wall {res['reference']['wall']:.3f}s. "
          f"THIS IS NOT V7a/V7b: no in-repo workload approaches the 67,108,864-item ceiling, so "
          f"the 2x margin and the panic reproduction remain UNMEASURED.")
    return Verdict("V7-SUB", GREEN if ok else RED, ev, "2 of 2 arms, 1 run each", res)


# ------------------------------------------------------------------- V12 ----

@vlib.row("V12-P1-OLD", "005b", "V12 part 1 AS WRITTEN — and the proof it is invalid",
          "whole-file sha256 of build-exe output, N runs, BOTH binaries")
def v12_p1_old(ctx):
    """Fires the invalidated criterion on both arms, which is the invalidity proof.

    Decision rule, fixed before the run:
      * reference produces >1 distinct digest  -> the criterion cannot discriminate.
        The row is GREEN *as an invalidity proof*, and says so in those words.
      * reference produces 1 and patched >1    -> RED. That would be a genuine,
        patch-specific nondeterminism and the strongest finding this harness can make.
      * both produce 1                         -> INCONCLUSIVE: the criterion did
        not fail today, which contradicts the 2026-08-23 measurement and must be
        re-grounded before anything is concluded from it.
    """
    fx = ctx.fixtures.get("stdpull")
    n = ctx.det_runs
    arms = {}
    for label, binary in (("patched", ctx.zig), ("reference", ctx.ref)):
        digs, rcs = [], []
        for i in range(n):
            e = cold_local_cache(ctx.env_for(binary), f"V12old_{label}_{i}")
            out = os.path.join(ctx.scratch("V12old"), f"{label}_{i}.bin")
            r = run_cmd([binary, "build-exe", "-Mroot=stdpull.zig", f"-femit-bin={out}"],
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=900)
            rcs.append(r.rc)
            if r.rc == 0 and os.path.isfile(out):
                digs.append(sha256_file(out))
        arms[label] = {"digests": digs, "unique": len(set(digs)), "rcs": rcs, "n": n}
    p, s = arms["patched"], arms["reference"]
    if not p["digests"] or not s["digests"]:
        return unknown("V12-P1-OLD", f"an arm produced no artifact (patched rc={p['rcs']}, "
                                     f"reference rc={s['rcs']})", "0 of 2 arms measurable", arms=arms)
    if s["unique"] > 1:
        v, verdict_word = GREEN, ("criterion INVALID and the invalidity is REPRODUCED here")
    elif p["unique"] > 1:
        v, verdict_word = RED, ("criterion discriminates and the PATCHED arm fails it — "
                                "patch-specific nondeterminism")
    else:
        v, verdict_word = INCONCLUSIVE, ("both arms passed today, which contradicts the "
                                         "2026-08-23 measurement — re-ground before concluding")
    ev = (f"{verdict_word}: reference {s['unique']} distinct digests of {len(s['digests'])} runs, "
          f"patched {p['unique']} of {len(p['digests'])}. A criterion the unpatched negative control "
          f"also fails is not a race detector — it measures upstream nondeterminism at -j>1. "
          f"The valid re-instrumented criterion is V12-P1A + V12-P1B.")
    return Verdict("V12-P1-OLD", v, ev, f"{n} runs per arm, 2 of 2 arms", arms)


@vlib.row("V12-P1A", "005b", "V12 part 1 (valid, a): fan-out whole-file identity + its own -j1",
          "whole-file sha256, N runs at default -j, plus the -j1 output")
def v12_p1a(ctx):
    """The workload is the one the A1 lane split actually rewrote: AstGen fan-out.

    Whole-file identity is measurable HERE (unlike on a std-pulling build-exe)
    because a `build-obj` of a 1,200-file fan-out has no linker stage to inject
    the run-to-run variation V12-P1-OLD exhibits.
    """
    fx = ctx.fixtures.get("fanout")
    n = ctx.det_runs
    arms = {}
    for label, binary in (("patched", ctx.zig), ("reference", ctx.ref)):
        digs, rcs = [], []
        for i in range(n):
            e = cold_local_cache(ctx.env_for(binary), f"V12a_{label}_{i}")
            out = os.path.join(ctx.scratch("V12a"), f"{label}_{i}.o")
            r = run_cmd([binary, "build-obj", "-Mroot=root.zig", f"-femit-bin={out}"],
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=900)
            rcs.append(r.rc)
            if r.rc == 0 and os.path.isfile(out):
                digs.append(sha256_file(out))
        e1 = cold_local_cache(ctx.env_for(binary), f"V12a_{label}_j1")
        out1 = os.path.join(ctx.scratch("V12a"), f"{label}_j1.o")
        r1 = run_cmd([binary, "build-obj", "-j1", "-Mroot=root.zig", f"-femit-bin={out1}"],
                     cwd=fx["dir"], env=e1, mask=ctx.mask, timeout=900)
        j1 = sha256_file(out1) if r1.rc == 0 and os.path.isfile(out1) else "UNKNOWN"
        arms[label] = {"digests": digs, "unique": len(set(digs)), "rcs": rcs,
                       "j1": j1, "matches_j1": bool(digs) and j1 != "UNKNOWN" and digs[0] == j1}
    p, s = arms["patched"], arms["reference"]
    if not p["digests"]:
        return unknown("V12-P1A", f"patched arm produced no artifact (rc={p['rcs']})",
                       "0 of 2 arms measurable", arms=arms)
    ok = p["unique"] == 1 and p["matches_j1"]
    ev = (f"patched: {p['unique']} distinct of {len(p['digests'])} runs at default -j "
          f"({p['digests'][0][:16]}…), vs its own -j1 output: "
          f"{'IDENTICAL' if p['matches_j1'] else 'DIFFERS'}; reference control: "
          f"{s['unique']} distinct of {len(s['digests'])}, -j1 match {s['matches_j1']}. "
          f"Workload: {fx['leaves']}-file AstGen fan-out via build-obj — the phase the A1 lane split rewrote.")
    return Verdict("V12-P1A", GREEN if ok else RED, ev,
                   f"{n} runs + 1 -j1 run per arm, 2 of 2 arms", arms)


@vlib.row("V12-P1B", "005b", "V12 part 1 (valid, b): .text section identity, std-pulling workload",
          "objcopy -O binary --only-section=.text, N runs")
def v12_p1b(ctx):
    fx = ctx.fixtures.get("stdpull")
    n = ctx.det_runs
    arms, tool = {}, None
    for label, binary in (("patched", ctx.zig), ("reference", ctx.ref)):
        texts, wholes, rcs = [], [], []
        for i in range(n):
            e = cold_local_cache(ctx.env_for(binary), f"V12b_{label}_{i}")
            out = os.path.join(ctx.scratch("V12b"), f"{label}_{i}.bin")
            r = run_cmd([binary, "build-exe", "-Mroot=stdpull.zig", f"-femit-bin={out}"],
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=900)
            rcs.append(r.rc)
            if r.rc == 0 and os.path.isfile(out):
                d, tool = section_digest(out, ".text")
                texts.append(d)
                wholes.append(sha256_file(out))
        arms[label] = {"text": texts, "text_unique": len(set(texts)),
                       "whole_unique": len(set(wholes)), "rcs": rcs}
    p, s = arms["patched"], arms["reference"]
    if not p["text"]:
        return unknown("V12-P1B", f"patched arm produced no artifact (rc={p['rcs']})",
                       "0 of 2 arms measurable", arms=arms)
    if p["text"][0] == "UNKNOWN":
        return unknown("V12-P1B", "no section-extraction tool (objcopy / llvm-objcopy) on this host",
                       "0 of 1 instruments available", arms=arms)
    ok = p["text_unique"] == 1
    ev = (f"patched .text: {p['text_unique']} distinct of {len(p['text'])} runs "
          f"({p['text'][0][:16]}…); reference control: {s['text_unique']} of {len(s['text'])} "
          f"({s['text'][0][:16] if s['text'] else 'UNKNOWN'}…). Same runs' WHOLE-file digests: "
          f"patched {p['whole_unique']} distinct, reference {s['whole_unique']} distinct — the "
          f"run-to-run variation lives entirely outside .text and is present without the patch. "
          f"Extractor: {tool} -O binary --only-section=.text")
    return Verdict("V12-P1B", GREEN if ok else RED, ev, f"{n} runs per arm, 2 of 2 arms",
                   dict(arms, tool=tool))


@vlib.row("V12-P2-TSAN", "005b", "V12 part 2 — ThreadSanitizer over a mid-size closure",
          "a TSan-instrumented stage3 (probed for)")
def v12_p2(ctx):
    """The DIRECT instrument for R12. Probed for; never assumed absent or present."""
    tsan = os.path.join(vlib.REPO, "build-tsan", "stage3", "bin", "zig")
    if not os.path.isfile(tsan):
        return unknown(
            "V12-P2-TSAN",
            "NOT RUN — no TSan-instrumented compiler exists at build-tsan/stage3/bin/zig. "
            "Measured cause (2026-08-23): `ninja -C build-tsan` fails at `sub-compilation of "
            "libtsan failed / lib/libtsan/sanitizer_common/sanitizer_platform_limits_posix.cpp: "
            "'linux/scc.h' file not found`. `linux/scc.h` is an obsolete kernel header Debian's "
            "linux-libc-dev no longer ships; zig 0.16 bundles a compiler-rt vintage that still "
            "includes it, for sizeof(struct scc_modem)/sizeof(struct scc_stat). Satisfying it "
            "would mean FABRICATING struct definitions whose sizes TSan asserts on, which this "
            "repository's rules forbid. This is the half of the HARD GATE that is the direct "
            "instrument for R12, and it remains UNMEASURED.",
            "0 of 1 instruments available", expected_binary=tsan)
    wl = vlib.workload(ctx, "stdpull")
    cwd, args, desc = wl
    e = cold_local_cache(ctx.env_zig, "V12tsan")
    r = run_cmd([tsan, "build-exe"] + args, cwd=cwd, env=e, mask=ctx.mask, timeout=3600)
    blob = r.stderr + r.stdout
    reports = re.findall(r"WARNING: ThreadSanitizer: ([^\n]+)", blob)
    named = [x for x in reports if "InternPool" in blob or "Zcu" in blob]
    ok = r.rc == 0 and not reports
    ev = (f"TSan stage3 present; rc={r.rc}, {len(reports)} ThreadSanitizer reports "
          f"({len(named)} naming InternPool/Zcu.File) over {desc}")
    return Verdict("V12-P2-TSAN", GREEN if ok else RED, ev,
                   f"1 of 1 runs, {len(reports)} reports", {"reports": reports[:20], "rc": r.rc})


@vlib.row("V12-P2-NC", "005b", "V12's own negative control — TSan must be seen RED",
          "sabotage of the .acquire/release pair + a TSan build")
def v12_p2_nc(ctx):
    tsan = os.path.join(vlib.REPO, "build-tsan", "stage3", "bin", "zig")
    return unknown(
        "V12-P2-NC",
        "NOT RUN — unreachable while V12-P2-TSAN is unreachable: proving the sanitizer goes red "
        "requires (a) a TSan-instrumented compiler, which does not build in this estate, and "
        "(b) a sabotage rebuild of it, which this harness is not authorised to perform. "
        "A sanitizer that never reported anything has not been met, so V12 part 2 has no "
        "instrument control either. "
        + (f"(build-tsan stage3 IS present at {tsan} — re-run V12-P2-TSAN first.)"
           if os.path.isfile(tsan) else ""),
        "0 of 2 preconditions (TSan build; sabotage rebuild)")


# ------------------------------------------------------------------- V13 ----

def _wall_arm(ctx, binary, args, cwd, extra, tag):
    def fn(i):
        e = cold_local_cache(ctx.env_for(binary), f"{tag}_{i}")
        return run_cmd([binary, "build-exe"] + args + list(extra), cwd=cwd, env=e,
                       mask=ctx.mask, timeout=3600, rss=True)
    return fn


def _v13(ctx, rid, j_a, j_b, note):
    wl = vlib.workload(ctx)
    if wl is None:
        return unknown(rid, f"workload {ctx.workload!r} unavailable", "0 of 2 arms")
    cwd, args, desc = wl
    ta, tb = alternate_ab(
        _wall_arm(ctx, ctx.zig, args, cwd, [f"-j{j_a}", "--intern-partitions=8"], f"{rid}a"),
        _wall_arm(ctx, ctx.zig, args, cwd, [f"-j{j_b}", "--intern-partitions=8"], f"{rid}b"),
        ctx.repeats, f"-j{j_a}", f"-j{j_b}")
    cmp_ = compare(ta, tb)
    tr_probe = ctx.tr_probe.get(ctx.zig, {"status": "absent", "detail": "not probed"})
    have_tr = tr_probe["status"] == "json"
    astgen = ""
    if have_tr:
        rows = {}
        for j in (j_a, j_b):
            r, tr, reason = _time_report_run(ctx, ctx.zig, ["build-exe"] + args, cwd, f"{rid}_j{j}",
                                             extra=[f"-j{j}", "--intern-partitions=8"])
            rows[j] = tr.get("real_ns_files") if tr else None
        if rows[j_a] and rows[j_b]:
            delta = 100.0 * (rows[j_a] - rows[j_b]) / rows[j_a]
            astgen = (f"; real_ns_files (THE number the design claims): -j{j_a} {rows[j_a] / 1e9:.3f}s vs "
                      f"-j{j_b} {rows[j_b] / 1e9:.3f}s -> -j{j_b} "
                      f"{'wins' if delta > 0 else 'loses'} by {abs(delta):.1f}% "
                      f"(predicted 20-40% win for the wider lane)")
        else:
            astgen = "; real_ns_files UNKNOWN (report obtained but field absent)"
    else:
        astgen = (f"; real_ns_files UNMEASURED — {tr_probe['detail']}. Wall time cannot isolate the "
                  f"AstGen phase, so the predicted 20-40% AstGen win is neither confirmed nor refuted")
    ev = f"{note} on {desc}. {ta.line()} | {tb.line()} | {cmp_['note']}{astgen}"
    wider_loses = tb.median is not None and ta.median is not None and tb.median > ta.median
    verdict = INCONCLUSIVE if cmp_.get("inside_noise") in (True, None) else (RED if wider_loses else GREEN)
    return Verdict(rid, verdict, ev, f"{ctx.repeats} runs per arm, 2 of 2 arms, alternated",
                   {"a": ta.to_json(), "b": tb.to_json(), "compare": cmp_,
                    "time_report_available": have_tr})


@vlib.row("V13", "005b", "does SMT pay on the wide lane? (R10) — AS WRITTEN",
          "wall clock (+ real_ns_files when a time report exists)", cost="~50 s per run")
def v13(ctx):
    return _v13(ctx, "V13", 6, 12,
                "CONFOUNDED FORM, kept because the V-list wrote it: -j12 oversubscribes an "
                "8-CPU mask, which biases against the wider arm")


@vlib.row("V13-MM", "005b", "SMT on the wide lane — MASK-MATCHED (the row's actual question)",
          "wall clock (+ real_ns_files when a time report exists)", cost="~50 s per run")
def v13_mm(ctx):
    topo = ctx.topology or vlib.host_topology()
    exp = vlib.expected_for_mask(topo, ctx.mask) if topo else None
    if not exp:
        return unknown("V13-MM", "no topology oracle — the mask-matched arms cannot be derived",
                       "0 of 2 arms")
    return _v13(ctx, "V13-MM", exp["physical"], exp["logical"],
                f"MASK-MATCHED: {exp['physical']} physical vs {exp['logical']} logical WITHIN the "
                f"affinity mask {ctx.mask} — confound-free")


# ------------------------------------------------------------------- V15 ----

@vlib.row("V15", "005b", "is the admission gate worth building?",
          "eu-stack sampling of every thread during a real compile", cost="~60 s")
def v15(ctx):
    """Counts threads parked in `Id.acquire`'s condition wait, with an INSTRUMENT CONTROL.

    A silent instrument looks exactly like a clean result. The control asserts
    that Zig frames resolve at all in the sampled backtraces; a near-zero parked
    count is only a measurement if the sampler can see anything.
    """
    if not vlib.which("eu-stack"):
        return unknown("V15", "eu-stack absent (elfutils) — no thread-state sampler on this host; "
                              "`perf record -g -p <pid>` or `gdb -p <pid> -batch -ex 'thread apply "
                              "all bt'` are the row's named alternatives and neither is wired here",
                       "0 of 1 instruments available")
    wl = vlib.workload(ctx)
    if wl is None:
        return unknown("V15", f"workload {ctx.workload!r} unavailable", "0 of 1 workloads")
    cwd, args, desc = wl
    e = cold_local_cache(ctx.env_zig, "V15")
    cmd = ["taskset", "-c", ctx.mask, ctx.zig, "build-exe"] + args + ["-j12", "--intern-partitions=8"]
    proc = subprocess.Popen(cmd, cwd=cwd, env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    samples, parked, threads_seen, zig_frames = 0, 0, [], 0
    max_parked = 0
    PARK = re.compile(r"acquire|waitUncancelable|tid_cond")
    KNOWN = re.compile(r"Compilation|Zcu|Sema|codegen|main\.|Thread")
    try:
        while proc.poll() is None:
            p = subprocess.run(["eu-stack", "-p", str(proc.pid)], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=30)
            txt = p.stdout.decode("utf-8", "replace")
            if not txt.strip():
                time.sleep(0.5)
                continue
            samples += 1
            n_thr = len(re.findall(r"^TID \d+", txt, re.M))
            threads_seen.append(n_thr)
            hits = len(PARK.findall(txt))
            parked += hits
            max_parked = max(max_parked, hits)
            zig_frames += len(KNOWN.findall(txt))
            time.sleep(0.5)
    finally:
        proc.wait()

    if samples == 0:
        return unknown("V15", "eu-stack produced no usable samples during the run — the sampler "
                              "saw nothing, which is not the same as seeing zero parked threads",
                       "0 of 1 instruments produced samples")
    denom = sum(threads_seen)
    if zig_frames == 0:
        return unknown("V15", f"INSTRUMENT CONTROL FAILED: {samples} samples, {denom} thread-samples, "
                              f"but ZERO frames resolved to Zig symbols. A near-zero parked count "
                              f"from a symbolisation failure is not a measurement.",
                       f"{samples} samples, 0 of {denom} thread-samples symbolised")
    frac = 100.0 * parked / denom if denom else None
    retire = frac is not None and frac < 1.0
    ev = (f"samples {samples}, threads observed {max(threads_seen)} peak, thread-samples {denom}; "
          f"frames matching acquire/waitUncancelable/tid_cond: {parked} total, max {max_parked} in "
          f"any one sample -> parked fraction {frac:.2f}%. INSTRUMENT CONTROL: {zig_frames} Zig "
          f"frames resolved, so the near-zero count is a measurement, not a symbolisation failure. "
          f"Row's own rule: "
          + ("parked count is near zero -> the admission gate has nothing to buy and dossier 2.3 "
             "edit 3 is retired." if retire else
             "parked count is materially above zero -> the gate becomes worth building.")
          + f" Workload: {desc}")
    return Verdict("V15", GREEN if retire else RED, ev,
                   f"{parked} of {denom} thread-samples across {samples} samples",
                   {"samples": samples, "thread_samples": denom, "parked": parked,
                    "max_parked": max_parked, "zig_frames": zig_frames, "parked_pct": frac})


# --------------------------------------------------------------------- V16 --

@vlib.row("V16", "005b", "THE HANG CLASS — a starved tid pool must complete or refuse, never hang",
          "timeout(120) over four small-K configurations; rc=124 is the forbidden outcome")
def v16(ctx):
    """V16 is a REGRESSION PIN for a failure class, not a check on one flag.

    `Zcu.PerThread.Id.allocate(n)` seeds the assignable-tid pool with n-1 entries; the
    linker acquires one tid and holds it for the whole compilation (dossier 1.1, A7).
    Lanes left for allocating workers are therefore K-2 -- exactly the `alloc lanes`
    number the report line prints. At K=2 that is ZERO and every worker asking for a
    tid blocks forever in `tid_cond.waitUncancelable`. No error, no timeout, no bytes.

    K=2 IS REACHABLE WITH NO FLAG: `basis = max(physical orelse logical, 2)`, so a
    1- or 2-physical-core host derives it, as does any taskset onto <=2 CPUs. Stock
    0.16.0 cannot reach it (one integer set both quantities), so the (K, M_wide)
    decoupling introduced it.

    TWO OUTCOMES ARE GREEN -- completion, or a NAMED REFUSAL. Exactly one is RED:
    rc=124, the timeout firing. The row forbids silence, not any particular policy.

    The `-j1` row must stay rc=0: the serial member is legitimate and a guard that
    refuses it has OVER-FIRED and is itself a defect. That is asserted here so the
    fix cannot pass by being too loud.
    """
    fx = ctx.fixtures.get("hello")
    if not fx:
        return unknown("V16", "hello fixture unavailable", "0 of 6 configurations")

    # Two sibling-free CPUs = 2 distinct physical cores on this host (siblings are
    # (0,6)(1,7)(2,8)(3,9)(4,10)(5,11)), which is what makes the derived K=2 case
    # reachable without any flag. A sibling PAIR (4,10) is 1 physical core.
    # `may_refuse=False` means the row demands rc=0: refusing there is an OVER-FIRE.
    # Masks exploit this host's sibling map (0,6)(1,7)(2,8)(3,9)(4,10)(5,11):
    #   4,10,5,11 -> 2 physical / 4 logical  == the ordinary 2-core CI container, and the
    #                only configuration measured to hang with NO FLAGS AT ALL.
    #   4,5       -> 2 physical / 2 logical
    #   4,10      -> 1 physical / 2 logical
    cases = [
        ("given-K2-j4", ["-j4", "--intern-partitions=2"], None, True),
        ("derived-2phys-4logical-NOFLAGS", [], "4,10,5,11", False),
        ("derived-2-physical", [], "4,5", False),
        ("derived-1-physical", [], "4,10", False),
        ("given-K2-j2-silently-serial", ["-j2", "--intern-partitions=2"], None, True),
        ("j1-K2-must-work", ["-j1", "--intern-partitions=2"], None, False),
    ]

    rows, hangs, refusals, completions = [], [], [], []
    for tag, extra, mask, may_refuse in cases:
        e = cold_local_cache(ctx.env_zig, f"V16_{tag}")
        r = run_cmd([ctx.zig, "build-obj", "-fno-emit-bin", "-Mroot=hello.zig"] + extra,
                    cwd=fx["dir"], env=e, mask=mask or ctx.mask, timeout=120)
        text = (r.stderr or "") + (r.stdout or "")
        # A refusal is a NAMED one: it must terminate non-zero AND say something about
        # the lanes/partitions. An exit(1) with no explanation is not a refusal, it is
        # a crash, and this row must not accept it as one.
        named = (not r.timed_out and r.rc != 0
                 and any(k in text for k in ("alloc lane", "intern-partitions",
                                             "partition", "lane")))
        if r.timed_out:
            state = "HANG (rc=124)"
            hangs.append(tag)
        elif r.rc == 0:
            state = "completed rc=0"
            completions.append(tag)
        elif named:
            state = f"refused by name rc={r.rc}"
            refusals.append(tag)
        else:
            state = f"exited rc={r.rc} WITHOUT naming the cause"
            hangs.append(tag + "(unnamed-exit)")
        rows.append(f"{tag} [{'|'.join(extra) or 'no flags'}"
                    + (f", taskset {mask}" if mask else "") + f"] -> {state}"
                    + ("" if may_refuse else "  (MUST be rc=0)"))

    # Every `may_refuse=False` case must COMPLETE. Refusing one of them is an over-fire:
    # the derived cases are ordinary hosts that must simply work, and `-j1` is the
    # legitimate serial member. A guard that refuses any of them is itself the defect.
    must_complete = [t for t, _, _, may in cases if not may]
    overfired = [t for t in must_complete if t not in completions]
    verdict = RED if (hangs or overfired) else GREEN
    ev = "; ".join(rows)
    if hangs:
        ev += (f". RED: {len(hangs)} of 4 configurations produced a silent hang or an "
               f"unnamed exit -- the exact failure class patch/001 exists to abolish.")
    elif overfired:
        ev += (f". RED: the guard OVER-FIRED on {overfired} -- these are ordinary working "
               f"configurations (plain derived hosts, and the legitimate `-j1` serial "
               f"member). Refusing them breaks setups that worked; a guard that over-fires "
               f"is itself the defect.")
    else:
        ev += (f". GREEN: 0 of 4 hung; {len(completions)} completed, {len(refusals)} refused "
               f"by name. Both outcomes are acceptable; only silence is not.")
    return Verdict("V16", verdict, ev, f"{len(hangs)} hangs of {len(cases)} configurations",
                   {"hangs": hangs, "refusals": refusals, "completions": completions})
