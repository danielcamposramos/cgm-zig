#!/usr/bin/env python3
"""run_vlist.py — run the whole patch/005 V-list in one pass.

    python3 partner_tools/vharness/run_vlist.py --list
    python3 partner_tools/vharness/run_vlist.py --only V9,V12-P1A --repeats 1
    python3 partner_tools/vharness/run_vlist.py --repeats 7 --slow \\
        --zig build-p005/stage3/bin/zig --ref build-safe/stage3/bin/zig

Every row is a named function returning a structured verdict — GREEN, RED,
UNKNOWN or INCONCLUSIVE, with an evidence line and a denominator. A row whose
instrument is absent reports UNKNOWN **with the exact reason**; nothing in this
harness can turn a missing instrument into a pass, and no row is left UNKNOWN
merely because nobody prepared a script.

Output: a markdown table on stdout (paste-ready into a verification document)
and a JSON sidecar carrying every raw sample, exit code and digest.

House rules this driver enforces, from `CONTRIBUTING-AI.md`:
  * every count carries its denominator in the same sentence;
  * an instrument that did not run reports UNKNOWN, never zero, never green;
  * timing rows alternate their A/B arms and report median, spread, IQR, stdev,
    all raw runs, rc, and an explicit note when the delta is inside the noise;
  * machine courtesy is reported, never enforced by killing somebody's build.

Stdlib only.
"""

import argparse
import json
import os
import platform
import subprocess
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import vlib  # noqa: E402
from vlib import GREEN, RED, UNKNOWN, INCONCLUSIVE  # noqa: E402

# Importing a rows module is what registers its rows. Nothing holds a list.
import rows_005a   # noqa: F401,E402
import rows_005b   # noqa: F401,E402
import rows_005c   # noqa: F401,E402
import rows_riders  # noqa: F401,E402
import rows_held   # noqa: F401,E402

sys.path.insert(0, os.path.join(HERE, "fixtures"))
import generate as fixgen  # noqa: E402

MARK = {GREEN: "GREEN", RED: "RED", UNKNOWN: "UNKNOWN", INCONCLUSIVE: "INCONCL"}


def md_escape(s):
    return s.replace("|", "\\|").replace("\n", " ")


def emit_markdown(verdicts, header):
    print(f"# patch/005 V-list — harness pass {header['started']}\n")
    print(f"- patched: `{header['zig']}` sha `{header['zig_sha'][:16]}…`")
    print(f"- reference: `{header['ref']}` sha `{header['ref_sha'][:16]}…`")
    print(f"- mask: `taskset -c {header['mask']}` · repeats: {header['repeats']} · "
          f"determinism N: {header['det_runs']} · workload: `{header['workload']}`")
    print(f"- libc paths file: {header['libc']}")
    print(f"- time-report instrument: patched = {header['tr_patched']}, reference = {header['tr_ref']}")
    busy, lines = header["courtesy"]
    print(f"- machine courtesy: {'CONTENDED — ' + str(len(lines)) + ' competing build process(es); every timing row below is CONTENDED' if busy else 'clear at start of pass'}")
    print()
    print("| Row | Group | Verdict | Denominator | Evidence |")
    print("|---|---|---|---|---|")
    for v in verdicts:
        spec = vlib.ROWS[v.row]
        print(f"| `{v.row}` | {spec.group} | **{MARK.get(v.verdict, v.verdict)}** | "
              f"{md_escape(v.denominator)} | {md_escape(v.evidence)} |")
    print()
    tally = {}
    for v in verdicts:
        tally[v.verdict] = tally.get(v.verdict, 0) + 1
    n = len(verdicts)
    print("**Roll-up:** " + ", ".join(f"{tally.get(k, 0)} {k} of {n} rows run"
                                     for k in (GREEN, RED, UNKNOWN, INCONCLUSIVE)))
    print(f"  (registry holds {len(vlib.ROWS)} rows in total; {n} selected this pass)")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zig", default=vlib.DEFAULT_ZIG, help="the patched binary under test")
    ap.add_argument("--ref", default=vlib.DEFAULT_REF, help="the reference / promoted binary")
    ap.add_argument("--only", default=None, help="comma-separated row ids, e.g. V8,V10")
    ap.add_argument("--group", default=None, help="comma-separated groups: 005a,005b,005c,riders,held")
    ap.add_argument("--repeats", type=int, default=3, help="repeats per timing arm (default 3; 7 supported)")
    ap.add_argument("--det-runs", type=int, default=5, help="N for the determinism rows (default 5)")
    ap.add_argument("--mask", default=vlib.DEFAULT_MASK, help="taskset CPU mask for every compile")
    ap.add_argument("--slow", action="store_true", help="also run rows marked slow (H3)")
    ap.add_argument("--workload", default="selfhost", choices=["selfhost", "stdpull", "fanout"],
                    help="compiler-side timing workload (default: the frozen self-host snapshot)")
    ap.add_argument("--time-report-json", default=None,
                    help="path to a PRE-COLLECTED machine-readable time report to consume when the "
                         "compiler cannot produce one")
    ap.add_argument("--fixtures-root", default=fixgen.DEFAULT_ROOT)
    ap.add_argument("--no-regen", action="store_true", help="reuse existing fixtures (faster; riskier)")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--json", dest="json_path", default=None, help="JSON sidecar path")
    ap.add_argument("--list", action="store_true", help="print the row registry and exit")
    a = ap.parse_args()

    if a.list:
        print(f"{len(vlib.ROWS)} rows registered\n")
        print("| Row | Group | Slow | Instrument | What it measures |")
        print("|---|---|---|---|---|")
        for rid in vlib.ROW_ORDER:
            s = vlib.ROWS[rid]
            print(f"| `{rid}` | {s.group} | {'yes' if s.slow else ''} | {s.instrument} | {s.title} |")
        return 0

    for label, path in (("--zig", a.zig), ("--ref", a.ref)):
        if not os.path.isfile(path):
            print(f"REFUSE: {label} binary not found at {path}", file=sys.stderr)
            return 2

    started = time.strftime("%Y-%m-%dT%H:%M:%S")
    outdir = a.outdir or os.path.join(vlib.WORK, "runs", started.replace(":", ""))
    os.makedirs(outdir, exist_ok=True)

    fixtures_raw = (fixgen.manifest(a.fixtures_root) if a.no_regen
                    else fixgen.generate(a.fixtures_root))
    if a.no_regen:
        missing = [n for n in fixgen.GENERATORS if n not in fixtures_raw]
        if missing:
            print(f"note: --no-regen and these fixtures are absent: {missing} — the rows that "
                  f"need them will report UNKNOWN with that reason", file=sys.stderr)

    env_zig = vlib.harness_env(a.zig, global_cache=os.path.join(vlib.WORK, "gcache"))
    env_ref = vlib.harness_env(a.ref, global_cache=os.path.join(vlib.WORK, "gcache_ref"))

    probe_dir = os.path.join(outdir, "probe")
    tr_probe = {a.zig: vlib.probe_time_report(a.zig, env_zig, probe_dir),
                a.ref: vlib.probe_time_report(a.ref, env_ref, probe_dir)}

    ctx = vlib.Ctx(zig=a.zig, ref=a.ref, repeats=a.repeats, det_runs=a.det_runs, mask=a.mask,
                   slow=a.slow, workload=a.workload, fixtures=fixtures_raw,
                   fixtures_root=a.fixtures_root, time_report_json=a.time_report_json,
                   tr_probe=tr_probe, outdir=outdir, topology=vlib.host_topology(),
                   env_zig=env_zig, env_ref=env_ref)

    selected = list(vlib.ROW_ORDER)
    explicit = set()
    if a.group:
        groups = set(a.group.split(","))
        selected = [r for r in selected if vlib.ROWS[r].group in groups]
    if a.only:
        explicit = {x.strip() for x in a.only.split(",") if x.strip()}
        unknown_ids = sorted(x for x in explicit if x not in vlib.ROWS)
        if unknown_ids:
            print(f"REFUSE: unknown row id(s) {unknown_ids}; run --list", file=sys.stderr)
            return 2
        selected = [r for r in vlib.ROW_ORDER if r in explicit]
    # A slow row is skipped unless --slow, EXCEPT when it was named by id: asking
    # for H3 by name and being silently given nothing is the kind of quiet skip
    # this harness exists to abolish. Named-but-not-slow still runs the row, which
    # then prints its own UNKNOWN-with-the-exact-invocation line.
    if not a.slow:
        selected = [r for r in selected if not vlib.ROWS[r].slow or r in explicit]

    courtesy = vlib.machine_courtesy()
    header = {
        "started": started, "zig": a.zig, "ref": a.ref,
        "zig_sha": vlib.sha256_file(a.zig), "ref_sha": vlib.sha256_file(a.ref),
        "mask": a.mask, "repeats": a.repeats, "det_runs": a.det_runs, "workload": a.workload,
        "libc": env_zig.get("_VH_LIBC_PROVENANCE", "UNKNOWN"),
        "global_cache": env_zig["ZIG_GLOBAL_CACHE_DIR"],
        "tr_patched": tr_probe[a.zig]["status"] + " — " + tr_probe[a.zig]["detail"],
        "tr_ref": tr_probe[a.ref]["status"] + " — " + tr_probe[a.ref]["detail"],
        "courtesy": courtesy, "host": platform.uname()._asdict(),
        "topology": ctx.topology, "outdir": outdir,
        "registry_size": len(vlib.ROWS), "selected": selected,
    }

    verdicts = []
    for rid in selected:
        spec = vlib.ROWS[rid]
        t0 = time.monotonic()
        print(f"[{len(verdicts) + 1}/{len(selected)}] {rid} — {spec.title}", file=sys.stderr)
        try:
            v = spec.fn(ctx)
        except Exception:
            v = vlib.Verdict(rid, UNKNOWN,
                             "HARNESS ERROR (not a compiler verdict): "
                             + traceback.format_exc().strip().splitlines()[-1],
                             "0 of 1 rows executed",
                             {"traceback": traceback.format_exc()[-3000:]})
        v.detail["_wall_s"] = round(time.monotonic() - t0, 3)
        verdicts.append(v)
        print(f"      -> {v.verdict}  ({v.denominator})", file=sys.stderr)

    emit_markdown(verdicts, header)

    json_path = a.json_path or os.path.join(outdir, "vlist.json")
    with open(json_path, "w") as f:
        json.dump({"header": header, "verdicts": [v.to_json() for v in verdicts]},
                  f, indent=2, default=str)
    print(f"\nJSON sidecar: {json_path}", file=sys.stderr)

    # Exit code carries information, not judgement: 0 = no RED among the rows
    # that ran. UNKNOWN never turns into a failing exit, because an absent
    # instrument is not a defect in the thing under test.
    return 1 if any(v.verdict == RED for v in verdicts) else 0


if __name__ == "__main__":
    sys.exit(main())
