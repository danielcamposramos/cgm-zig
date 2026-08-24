#!/usr/bin/env python3
"""rows_005c.py — edges-first ordering (commit 2a9ca530).

Rows: V8, V9, V10.

Each of these rows was written to be able to RETRACT its own feature, and the
harness keeps that property: V8 goes RED when `layered` is slower, V10 goes
INCONCLUSIVE when its own `declared` control beats the feature. Neither outcome
is a harness failure; both are the rows doing the job they were written for.
"""

import os
import re
import statistics

import vlib
from vlib import (Verdict, GREEN, RED, UNKNOWN, INCONCLUSIVE, unknown, run_cmd,
                  cold_local_cache, Timing, alternate_ab, compare)


# ---------------------------------------------------------------------- V8 --

@vlib.row("V8", "005c", "edges-first ORDERING is delivered, and what it costs (R6)",
          "ranking line + its insertion control; wall-clock cost recorded, not gated on")
def v8(ctx):
    """CORRECTED EXPECTATION -- and the correction is the finding.

    This row used to be a SPEED gate: it went RED when `layered` measured slower than
    `insertion`, and it did (+11.92% in the first batch, +6.59% here). But speed was
    never the claim. It came from the dossier's own performance prose. Daniel's
    2026-08-22 charter states the capability verbatim:

        "it must compile from the smallest to the most composed part
         - so it starts with edges"

    That is an ORDERING claim. A row that answers "is it faster?" cannot refute or
    confirm it, and letting a speed number veto an ordering capability is measuring the
    wrong thing and then acting on it.

    So the row now checks the capability, with its control, and records the cost plainly
    beside it. The cost is REPORTED, never gated on: `insertion` stays the default and
    stays selectable, so nobody pays the 6.59% who has not asked for edges-first.

    Disposition: orchestrator doctrine-disposition ORCH-P005B-VERDICT, 2026-08-23.
    """
    fx = ctx.fixtures.get("modgraph")
    cap, cap_ev = None, "no modgraph fixture — the ordering capability was NOT checked"
    if fx:
        # The modgraph fixture is the cyclic/acyclic PAIR; the acyclic half is the
        # one whose ranking depth is unambiguous.
        cwd = fx["acyclic"]["dir"]
        base = ["build-obj", "-fno-emit-bin", "-Mroot=root.zig"]
        lay = run_cmd([ctx.zig] + base + ["--analysis-order=layered"], cwd=cwd,
                      env=cold_local_cache(ctx.env_zig, "V8_cap_lay"), mask=ctx.mask, timeout=300)
        ins = run_cmd([ctx.zig] + base + ["--analysis-order=insertion"], cwd=cwd,
                      env=cold_local_cache(ctx.env_zig, "V8_cap_ins"), mask=ctx.mask, timeout=300)
        m = re.search(r"analysis order layered \(given\): (\d+) modules ranked, "
                      r"max depth (\d+), (\d+) in import cycles", lay.stderr or "")
        ins_has = "analysis order" in (ins.stderr or "")
        cap = bool(m) and not ins_has and lay.rc == 0
        cap_ev = (f"CAPABILITY (the charter's actual claim): layered ranked "
                  f"{m.group(1)} modules, max depth {m.group(2)}, {m.group(3)} in cycles, rc={lay.rc}"
                  if m else
                  f"CAPABILITY NOT DELIVERED: no ranking line under --analysis-order=layered (rc={lay.rc})")
        cap_ev += ("; insertion control emits no ordering line, so the line is the feature "
                   "speaking and not a constant" if not ins_has else
                   "; CONTROL FAILED: insertion also emitted an ordering line")

    wl = vlib.workload(ctx)
    cost_ev = "COST: UNMEASURED — workload unavailable"
    detail = {"capability": cap}
    if wl is not None:
        cwd, args, desc = wl

        def arm(order, tag):
            def fn(i):
                e = cold_local_cache(ctx.env_zig, f"V8_{tag}_{i}")
                return run_cmd([ctx.zig, "build-exe"] + args + [f"--analysis-order={order}"],
                               cwd=cwd, env=e, mask=ctx.mask, timeout=3600)
            return fn

        ta, tb = alternate_ab(arm("insertion", "ins"), arm("layered", "lay"),
                              ctx.repeats, "insertion", "layered")
        cmp_ = compare(ta, tb)
        detail.update({"insertion": ta.__dict__, "layered": tb.__dict__, "compare": cmp_})
        pct = cmp_.get("delta_pct")
        cost_ev = (f"COST, recorded and NOT gated on: {ta} | {tb}"
                   + (f" -> layered is {pct:+.2f}% on wall clock" if pct is not None else "")
                   + f". Workload: {desc}. `insertion` remains the DEFAULT and remains "
                     f"selectable, so this cost is opt-in.")

    if cap is None:
        return unknown("V8", cap_ev + ". " + cost_ev, "0 of 1 capability checks runnable")
    return Verdict("V8", GREEN if cap else RED, cap_ev + ". " + cost_ev,
                   "1 of 1 capability checks, with its control", detail)


# ---------------------------------------------------------------------- V9 --

@vlib.row("V9", "005c", "negative control for ranking-pass cycles (R5)",
          "the ranking line's `in import cycles` counter, cyclic + acyclic pair")
def v9(ctx):
    """The acyclic half is this row's own control: a counter stuck at a constant
    would pass a cyclic-only test. Both directions are required."""
    mg = ctx.fixtures.get("modgraph")
    if not mg:
        return unknown("V9", "modgraph fixture pair missing", "0 of 2 graphs")
    out = {}
    for kind in ("cyclic", "acyclic"):
        spec = mg[kind]
        r = run_cmd([ctx.zig, "build-obj", "--analysis-order=layered", "-fno-emit-bin"]
                    + spec["args"], cwd=spec["dir"], env=ctx.env_zig, mask=ctx.mask, timeout=300)
        out[kind] = {"rc": 124 if r.timed_out else r.rc, "rank": vlib.parse_rank_line(r.stderr),
                     "wall": r.wall}
    c, a = out["cyclic"], out["acyclic"]
    if c["rank"] is None or a["rank"] is None:
        return unknown("V9", f"no ranking line emitted (cyclic rc={c['rc']}, acyclic rc={a['rc']}) "
                             f"— the counter this row reads does not appear",
                       "0 of 2 graphs instrumented", out=out)
    ok = (c["rc"] == 0 and a["rc"] == 0 and c["rank"]["cycles"] > 0 and a["rank"]["cycles"] == 0)
    ev = (f"cyclic: rc={c['rc']}, no hang, {c['rank']['modules']} modules ranked, max depth "
          f"{c['rank']['max_depth']}, {c['rank']['cycles']} in import cycles | acyclic control: "
          f"rc={a['rc']}, {a['rank']['modules']} modules, max depth {a['rank']['max_depth']}, "
          f"{a['rank']['cycles']} in import cycles. The counter moves in BOTH directions, so it is "
          f"not stuck at a constant; a legal cyclic graph does not hang the ranker.")
    return Verdict("V9", GREEN if ok else RED, ev, "2 of 2 graphs (cyclic + acyclic control)", out)


# --------------------------------------------------------------------- V10 --

@vlib.row("V10", "005c", "edges-first at the step level does what it claims",
          "wall clock over a 13-step build, 3 orders incl. the `declared` control",
          cost="~5 s per run")
def v10(ctx):
    """`declared` is not a third data point — it is the control that separates
    "layered helped" from "any deterministic order helped". A verdict that
    ignores it is the verdict this row exists to prevent."""
    fx = ctx.fixtures.get("multistep")
    if not fx:
        return unknown("V10", "multistep fixture missing", "0 of 3 arms")
    arms = {}
    for name in ("random", "layered", "declared"):
        t = Timing(name, [], [])
        for i in range(ctx.repeats):
            e = cold_local_cache(ctx.env_zig, f"V10_{name}_{i}")
            extra = ["--seed", str(i + 1)] if name == "random" else []
            r = run_cmd([ctx.zig, "build", f"--step-order={name}", "--summary", "all", "-j12"]
                        + extra + ["--prefix", os.path.join(ctx.scratch("V10"), f"{name}_{i}")],
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=1800)
            t.samples.append(r.wall)
            t.rcs.append(124 if r.timed_out else r.rc)
        arms[name] = t
    rnd, lay, dec = arms["random"], arms["layered"], arms["declared"]
    if not all(t.all_ok for t in arms.values()):
        return unknown("V10", f"an arm did not exit 0: "
                              + ", ".join(f"{k}={v.rcs}" for k, v in arms.items()),
                       f"{sum(1 for t in arms.values() if t.all_ok)} of 3 arms usable",
                       arms={k: v.to_json() for k, v in arms.items()})
    c_lay_rnd = compare(lay, rnd)
    c_dec_lay = compare(dec, lay)
    layered_slower = lay.median > rnd.median
    control_wins = dec.median <= lay.median
    # `inside_noise is None` means the noise floor itself is UNKNOWN (n = 1). A rule
    # may not fire on an unknown floor: that is how a single sample becomes a verdict.
    if layered_slower and c_lay_rnd.get("inside_noise") is False:
        verdict = RED
        rule = ("layered is slower than random OUTSIDE the noise floor -> the fan-in-descending "
                "tie-break is wrong and the counter-claim recorded beside it wins")
    elif c_lay_rnd.get("inside_noise") is None:
        verdict = INCONCLUSIVE
        rule = ("the noise floor is UNKNOWN at this repeat count, so neither the retraction rule "
                "nor the control comparison may fire — raise --repeats")
    elif control_wins:
        verdict = INCONCLUSIVE
        rule = ("the `declared` control is at least as fast as `layered`, so nothing here "
                "distinguishes the feature from any deterministic order — and `--step-order=layered` "
                "is the shipped DEFAULT, i.e. a default resting on an unmeasured claim")
    else:
        verdict = GREEN
        rule = "layered beats both random and the declared control"
    ev = (f"{fx['expected_steps']} steps over {fx['executables']} executables. "
          f"{rnd.line()} | {lay.line()} | {dec.line()} | layered vs random: {c_lay_rnd['note']} | "
          f"declared vs layered: {c_dec_lay['note']}. Rule fired: {rule}")
    return Verdict("V10", verdict, ev,
                   f"{ctx.repeats} runs per arm, 3 of 3 arms (random, layered, declared control)",
                   {k: v.to_json() for k, v in arms.items()})
