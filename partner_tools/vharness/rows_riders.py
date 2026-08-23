#!/usr/bin/env python3
"""rows_riders.py — the two riders, plus the red the V-list never queued.

Rows: V-S2a, V-S2b, V-S4a, V-S4b, V-BR.

`V-BR` is here because the 2026-08-23 run found it by *running the thing*: the
unconditional `ThreadPlan.report()` line goes to stderr through `std.log.info`,
and under `zig build` the child compiler runs with `--listen=-`, so the build
runner treats that stderr as step-failure evidence and prints `error:` plus
`native failure` for every compile step on a green build. A row nobody queued
became an independent promotion blocker, so it is queued now.

`V-S4b` also fills a named residual from that run: the peak-system-RSS half of
the row was never measured, so `share`'s claimed RSS win stayed UNKNOWN while
its wall-time arm lost. This harness samples RSS across the whole compiler
process tree, so the trade-off can be judged on both axes.
"""

import os
import re
import subprocess
import time

import vlib
from vlib import (Verdict, GREEN, RED, UNKNOWN, INCONCLUSIVE, unknown, run_cmd,
                  cold_local_cache, Timing, compare)
from rows_005a import sabotage_row


# ------------------------------------------------------------ V-S2a / V-S2b --

@vlib.row("V-S2a", "riders", "the reservation keeps the linker's slot",
          "SABOTAGE REBUILD (reserve forced to 0) — prepared patch, not fired")
def vs2a(ctx):
    return sabotage_row(ctx, "V-S2a")


@vlib.row("V-S2b", "riders", "negative control for the reservation",
          "SABOTAGE REBUILD (reserve above async_limit) — prepared patch, not fired")
def vs2b(ctx):
    return sabotage_row(ctx, "V-S2b")


# --------------------------------------------------------- process sampling --

def _sample_tree(binary_path):
    """(worker_threads, child_processes, total_rss_kb) for one instant.

    `ps -eLf` lists one row per THREAD, which is the unit rider 2's claim is
    about: `--child-jobs=keep` hands every child compiler the whole host, so the
    thread count — not the process count — is what oversubscribes.
    """
    needle = os.path.basename(binary_path)
    p = subprocess.run(["ps", "-eLf"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    txt = p.stdout.decode("utf-8", "replace")
    threads = sum(1 for l in txt.splitlines() if binary_path in l and "build-exe" in l)
    q = subprocess.run(["ps", "-eo", "rss=,args="], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rss, procs = 0, 0
    for line in q.stdout.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line or binary_path not in line:
            continue
        parts = line.split(None, 1)
        try:
            rss += int(parts[0])
        except (ValueError, IndexError):
            continue
        if "build-exe" in line:
            procs += 1
    return threads, procs, rss


def _build_sampled(ctx, extra, tag, interval=0.15):
    """Run `zig build` while sampling the process tree. Returns a dict of peaks."""
    fx = ctx.fixtures["multistep"]
    e = cold_local_cache(ctx.env_zig, tag)
    prefix = os.path.join(ctx.scratch("riders"), tag)
    cmd = (["taskset", "-c", ctx.mask, ctx.zig, "build", "--summary", "all", "--prefix", prefix]
           + list(extra))
    t0 = time.monotonic()
    proc = subprocess.Popen(cmd, cwd=fx["dir"], env=e,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    peak_thr = peak_proc = peak_rss = 0
    samples = 0
    while proc.poll() is None:
        thr, prc, rss = _sample_tree(ctx.zig)
        peak_thr, peak_proc, peak_rss = max(peak_thr, thr), max(peak_proc, prc), max(peak_rss, rss)
        samples += 1
        time.sleep(interval)
    out, err = proc.communicate()
    wall = time.monotonic() - t0
    return {"rc": proc.returncode, "wall": wall, "peak_threads": peak_thr,
            "peak_child_processes": peak_proc, "peak_tree_rss_kb": peak_rss,
            "samples": samples, "stdout": out.decode("utf-8", "replace"),
            "stderr": err.decode("utf-8", "replace")}


# -------------------------------------------------------------------- V-S4a --

@vlib.row("V-S4a", "riders", "the oversubscription is real, measured BEFORE the fix",
          "ps -eLf thread census sampled every 150 ms across a 13-step build",
          cost="~10 s per arm")
def vs4a(ctx):
    if "multistep" not in ctx.fixtures:
        return unknown("V-S4a", "multistep fixture missing", "0 of 2 arms")
    arms = {}
    for mode in ("keep", "share"):
        arms[mode] = _build_sampled(ctx, [f"--child-jobs={mode}", "-j4"], f"s4a_{mode}")
    topo = ctx.topology or vlib.host_topology()
    exp = vlib.expected_for_mask(topo, ctx.mask) if topo else None
    cpus = exp["logical"] if exp else None
    keep, share = arms["keep"], arms["share"]
    if keep["rc"] != 0 or share["rc"] != 0:
        return unknown("V-S4a", f"an arm did not exit 0 (keep={keep['rc']}, share={share['rc']})",
                       "0 of 2 arms usable", arms=arms)
    claim = cpus is not None and keep["peak_threads"] > cpus
    ratio = (keep["peak_threads"] / cpus) if cpus else None
    ev = (f"--child-jobs=keep peaked at {keep['peak_threads']} worker THREADS "
          f"({keep['peak_child_processes']} child processes) against a {cpus}-CPU mask "
          f"({ratio:.2f}x the CPUs the process may use) over {keep['samples']} samples; "
          f"--child-jobs=share peaked at {share['peak_threads']} threads "
          f"({share['peak_child_processes']} processes) over {share['samples']} samples. "
          f"Row's own retraction rule: if total threads never exceed the CPU count the central "
          f"claim is wrong and rider 2 is withdrawn — "
          + ("NOT triggered; the claim stands." if claim else "TRIGGERED."))
    return Verdict("V-S4a", GREEN if claim else RED, ev,
                   f"2 of 2 arms, {keep['samples']} + {share['samples']} samples", arms)


# -------------------------------------------------------------------- V-S4b --

@vlib.row("V-S4b", "riders", "THE GATE ON RIDER 2's DEFAULT — share vs keep",
          "wall clock alternated + peak process-tree RSS (the half never measured)",
          cost="~5 s per run")
def vs4b(ctx):
    if "multistep" not in ctx.fixtures:
        return unknown("V-S4b", "multistep fixture missing", "0 of 2 arms")
    ts = Timing("share", [], [], [])
    tk = Timing("keep", [], [], [])
    raw = {"share": [], "keep": []}
    for i in range(ctx.repeats):
        for mode, t in (("share", ts), ("keep", tk)):
            res = _build_sampled(ctx, [f"--child-jobs={mode}", "-j4"], f"s4b_{mode}_{i}")
            t.samples.append(res["wall"])
            t.rcs.append(res["rc"])
            t.peak_rss_kb.append(res["peak_tree_rss_kb"])
            raw[mode].append(res)
    if not (ts.all_ok and tk.all_ok):
        return unknown("V-S4b", f"an arm did not exit 0 (share={ts.rcs}, keep={tk.rcs})",
                       "0 of 2 arms usable", share=ts.to_json(), keep=tk.to_json())
    cmp_ = compare(tk, ts)   # A = keep (the fallback), B = share (the shipped default)
    share_rss = max(ts.peak_rss_kb) if ts.peak_rss_kb else None
    keep_rss = max(tk.peak_rss_kb) if tk.peak_rss_kb else None
    rss_note = ("peak process-tree RSS: share {:,} KB vs keep {:,} KB -> share {}".format(
        share_rss, keep_rss, "WINS the RSS half" if share_rss < keep_rss else "loses the RSS half")
        if share_rss and keep_rss else "peak process-tree RSS UNKNOWN (sampler produced nothing)")
    share_slower = ts.median > tk.median
    if cmp_.get("inside_noise") in (True, None):
        verdict, rule = INCONCLUSIVE, ("wall-time delta is inside the noise floor, so the row's "
                                       "unconditional rule cannot fire on this evidence")
    elif share_slower:
        verdict, rule = RED, ("share is slower OUTSIDE the noise floor -> the row's rule fires: "
                              "'If propagation is slower, the derived default reverts to keep'")
    else:
        verdict, rule = GREEN, "share is at or below keep on wall time"
    ev = (f"{ts.line()} | {tk.line()} | {cmp_['note']} | {rss_note}. {rule}. "
          f"Fixture caveat, owed: 13 steps of short compiles is the regime where cutting each "
          f"child from -j8 to -j2 hurts most and where oversubscription costs least; a large "
          f"project could invert this.")
    return Verdict("V-S4b", verdict, ev,
                   f"{ctx.repeats} runs per arm, 2 of 2 arms, alternated",
                   {"share": ts.to_json(), "keep": tk.to_json(), "compare": cmp_,
                    "peak_tree_rss_kb": {"share": share_rss, "keep": keep_rss}})


# --------------------------------------------------------------------- V-BR --

ERR_RE = re.compile(r"^error:", re.M)
FAIL_RE = re.compile(r"native failure", re.M)


@vlib.row("V-BR", "riders", "the report line breaks `zig build`'s diagnostic channel",
          "count of `^error:` and `native failure` lines on a GREEN build, A/B",
          cost="~10 s per arm")
def vbr(ctx):
    """Not in the V-list. Found by running the thing, and an independent blocker.

    Artifacts are correct and the exit code is 0, so this is not a functional
    break — it is a diagnostic-channel break, which on a station where every
    consuming project greps stderr for `error:` is worse than it sounds.
    """
    fx = ctx.fixtures.get("multistep")
    if not fx:
        return unknown("V-BR", "multistep fixture missing", "0 of 2 arms")
    arms = {}
    for label, binary, env in (("patched", ctx.zig, ctx.env_zig), ("reference", ctx.ref, ctx.env_ref)):
        e = cold_local_cache(env, f"vbr_{label}")
        prefix = os.path.join(ctx.scratch("VBR"), label)
        r = run_cmd([binary, "build", "--summary", "all", "--prefix", prefix, "-j4"],
                    cwd=fx["dir"], env=e, mask=ctx.mask, timeout=1800)
        blob = r.stderr
        summary = re.search(r"Build Summary: ([^\n]+)", r.stdout + r.stderr)
        arms[label] = {"rc": r.rc, "errors": len(ERR_RE.findall(blob)),
                       "native_failure": len(FAIL_RE.findall(blob)),
                       "stderr_bytes": r.stderr_bytes,
                       "build_summary": summary.group(1) if summary else "UNKNOWN"}
    p, s = arms["patched"], arms["reference"]
    if p["rc"] != 0 or s["rc"] != 0:
        return unknown("V-BR", f"an arm did not exit 0 (patched={p['rc']}, reference={s['rc']}) — "
                               f"this row only means anything on a GREEN build",
                       "0 of 2 arms usable", arms=arms)
    broken = p["errors"] > s["errors"] or p["native_failure"] > s["native_failure"]
    ev = (f"both arms exit 0 and report `{p['build_summary']}` / `{s['build_summary']}`. "
          f"patched stderr: {p['errors']} lines matching ^error:, {p['native_failure']} matching "
          f"`native failure`, {p['stderr_bytes']} bytes | reference stderr: {s['errors']} / "
          f"{s['native_failure']} / {s['stderr_bytes']} bytes. "
          + ("DIAGNOSTIC-CHANNEL BREAK: a green build now prints `error:` and marks compile steps "
             "`native failure`. Remedy the compiler already has the test for: suppress the line "
             "when `listen != .none` (src/main.zig tests exactly that for --time-report), or send "
             "it through the IPC as a diagnostic."
             if broken else "no channel break: the patched arm adds no error-shaped lines."))
    return Verdict("V-BR", RED if broken else GREEN, ev, "2 of 2 arms, 1 build each", arms)
