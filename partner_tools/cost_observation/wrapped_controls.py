"""Explicit, once-only busy/idle instrument controls; caller banks stdout.

Only GNU time writes the two caller-owned logs. No new launcher, retries,
compiler invocation or clean/speed verdict. A returned direct child does not
prove all possible process-group descendants have gone. No child is designed
to spawn descendants. Pre/post launch and between-probe work stay UNKNOWN.
"""

import argparse
from collections import Counter
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

from partner_tools.vharness import vlib
from .launch import LaunchObservation
from .owned_process import file_identity

ROOT = Path(__file__).resolve().parents[2]
MODES = ("busy", "idle")


class ControlFailure(ValueError):
    """Only fixed public assertion names, never external exception text."""


def require(condition, name):
    if not condition:
        raise ControlFailure(name)


def fault(error):
    return {"kind": type(error).__name__, "errno": getattr(error, "errno", None),
            "check": str(error) if isinstance(error, ControlFailure) else None}


def stable_file(path):
    with Path(path).open("rb") as source:
        before = file_identity(os.fstat(source.fileno()))
        digest = hashlib.sha256(source.read()).hexdigest()
        require(before == file_identity(os.fstat(source.fileno())) == file_identity(os.stat(path)),
                "file_changed_while_sealing")
    return {"identity": before, "sha256": digest}


def seals():
    # All package .py files (including child entry point) plus imported local
    # module sources, notably vlib and its oracle_lib import. No capability list.
    paths = set(Path(__file__).parent.glob("*.py"))
    for module in tuple(sys.modules.values()):
        name = getattr(module, "__file__", None)
        if name and name.endswith(".py") and Path(name).resolve().is_relative_to(ROOT):
            paths.add(Path(name).resolve())
    tools = {"python": sys.executable, "time": "/usr/bin/time",
             "taskset": shutil.which("taskset"), "pgrep": shutil.which("pgrep")}
    require(all(path and os.access(path, os.X_OK) for path in tools.values()), "required_tool_missing")
    return {"sources": {str(p.relative_to(ROOT)): stable_file(p) for p in sorted(paths)},
            "tools": {name: {"path": path, **stable_file(path)} for name, path in tools.items()}}


def screen():
    require(sys.platform == "linux" and os.environ.get("LC_ALL") == "C", "linux_and_C_locale_required")
    allowed = sorted(os.sched_getaffinity(0))
    require(4 in allowed, "CPU4_not_allowed")
    busy, matches = vlib.machine_courtesy()
    return {"hold": busy, "compile_matches": len(matches), "allowed_affinity": allowed,
            "whole_host_idle": "UNKNOWN"}


def read_time(path):
    raw = path.read_bytes()
    return {"raw": raw.decode("ascii"), "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}


def analyze(record):
    """Pure first-failure assertions AFTER raw receipt emission; no host reads."""
    run, ev, child = record["run"], record["observation"], record["child"]
    require(run is not None and run["rc"] == 0 and not run["timed_out"], "run_not_successful")
    require(run["stderr"] == "" and child is not None, "child_output_invalid")
    require(re.findall(r"^\s*Exit status:\s*(\d+)\s*$", record["gnu_time"]["raw"], re.M) == ["0"],
            "gnu_time_exit_unknown")
    require(record["seals_before"] is not None and record["seals_before"] == record["seals_after"], "input_seal_drift")
    require(child["mode"] == record["mode"] and child["affinity"] == [4], "child_mode_or_affinity")
    pre, work, post = child["pre_hold_ns"], child["work_ns"], child["post_hold_ns"]
    require(pre[0] <= pre[1] <= work[0] <= work[1] <= post[0] <= post[1] and
            pre[1] - pre[0] >= 500_000_000 and post[1] - post[0] >= 500_000_000, "holds_insufficient")
    require(not child["deadline_reached_before_cpu_target"], "child_cpu_deadline")
    cpu = (child["cpu_ns"][1] - child["cpu_ns"][0]) / 1e9
    require(cpu >= 0 and cpu == child["cpu_seconds"], "child_cpu_payload_inconsistent")
    require(ev["observer_joined"] is True and not ev["errors"], "adapter_error_or_not_joined")
    obs = ev["observation"]
    require(obs is not None and obs["stop_reason"] == "caller_stop" and not obs["events"], "observer_error")
    require(ev["run_call_begin_ns"] <= pre[0] <= post[1] <= ev["run_return_or_raise_ns"], "run_window_unbracketed")
    wrapper = ev["notification"]["wrapper_identity"]
    require(wrapper is not None and wrapper["pid"] != child["child"]["pid"], "wrapper_is_not_child")
    joined = ev["identity_join"]["samples"]
    valid = [s for s in joined if s["target"] == child["child"] and
             s["status"] == "matched_target_at_snapshot_probes" and s["relation"] == "direct_child" and
             s["wrapper"] == wrapper and not s["snapshot_has_errors"]]
    left = [s for s in valid if pre[0] <= s["read_start_ns"] <= s["read_end_ns"] <= pre[1]]
    right = [s for s in valid if post[0] <= s["read_start_ns"] <= s["read_end_ns"] <= post[1]]
    require(left and right, "work_endpoints_unbracketed")
    a, b = max(left, key=lambda s: s["read_end_ns"]), min(right, key=lambda s: s["read_start_ns"])
    chain = [s for s in joined if a["sequence"] <= s["sequence"] <= b["sequence"]]
    require(len(chain) >= 3 and [s["sequence"] for s in chain] == list(range(a["sequence"], b["sequence"] + 1))
            and all(s in valid for s in chain), "middle_target_coverage_missing")
    samples = {s["sequence"]: s for s in obs["samples"]}
    for s in chain:
        snap = samples[s["sequence"]]["snapshot"]
        rows = [p for p in snap["processes"] if p["pid"] == child["child"]["pid"]]
        require(snap["stat"] is not None and snap["pid_coverage"]["mode"] == "custom_enumerator"
                and len(rows) == 1 and rows[0]["affinity"] == [4]
                and rows[0]["start_ticks"] == child["child"]["start_ticks"], "target_snapshot_invalid")
    intervals = [i for i in ev["identity_join"]["intervals"] if a["sequence"] <= i["from_sequence"] < b["sequence"]]
    require([(i["from_sequence"], i["to_sequence"]) for i in intervals] ==
            list(zip(range(a["sequence"], b["sequence"]), range(a["sequence"] + 1, b["sequence"] + 1)))
            and all(i["target"] == child["child"] and
            i["endpoint_cpu_delta_ticks"] is not None for i in intervals), "target_delta_missing")
    ticks = sum(sum(i["endpoint_cpu_delta_ticks"].values()) for i in intervals)
    hz = obs["clock_ticks_per_second"]
    require(hz > 0 and abs(ticks / hz - cpu) <= 3 / hz, "independent_cpu_disagrees")
    require((cpu >= 0.35 and ticks > 0) if record["mode"] == "busy" else ticks <= 3, "cpu_control_not_discriminated")
    errors = Counter((e["source"], e["kind"], e["errno"]) for s in obs["samples"] if s["snapshot"]
                     for e in s["snapshot"]["errors"])
    return {"status": "instrument_checks_passed", "samples": len(obs["samples"]), "chain_samples": len(chain),
            "chain_intervals": len(intervals), "cpu_ticks": ticks, "hz": hz, "child_cpu_seconds": cpu,
            "endpoints": [a, b], "error_sources": [{"source": k[0], "kind": k[1], "errno": k[2], "count": n}
             for k, n in errors.items()], "missed_deadlines": sum(s["missed_deadlines"] for s in obs["samples"]),
            "observer_thread_cpu_ns": obs["observer_thread_cpu_ns"], "duration_ns": obs["duration_ns"],
            "collection_wall_ns": sum(s["collection_wall_ns"] for s in obs["samples"]),
            "launch_gap_ns": a["read_end_ns"] - ev["run_call_begin_ns"],
            "exit_gap_ns": ev["run_return_or_raise_ns"] - b["read_start_ns"], "performance_verdict": "UNKNOWN"}


def emit(record):
    print(json.dumps(record, sort_keys=True), flush=True)


def run_pair(log_root):
    """Maximum busy then idle; never retry. Return 75 HOLD, 1 failure, or 0."""
    root = Path(log_root)
    pre = {"record": "wrapped_pair_pre", "modes": list(MODES), "error": None}
    try:
        require(root.is_dir() and not root.is_symlink() and not any(root.iterdir()), "existing_empty_log_directory_required")
        initial = pre["seals"] = seals()
    except Exception as error:
        pre["error"] = fault(error)
        emit(pre)
        return 1
    emit(pre)
    for mode in MODES:
        record = {"record": "wrapped_control_raw", "mode": mode, "run": None, "observation": None,
                  "child": None, "gnu_time": None, "seals_before": None, "seals_after": None,
                  "error": None, "stage": "prelaunch", "runner_called": False}
        adapter, result, interrupted = None, 0, None
        time_path = root / (mode + ".time.txt")
        try:
            record["courtesy_before"] = screen()
            if record["courtesy_before"]["hold"]:
                result = 75
            else:
                record["seals_before"] = seals()
                require(record["seals_before"] == initial and not time_path.exists(), "prelaunch_drift_or_existing_log")
                adapter = LaunchObservation(initial["tools"]["python"]["identity"], interval_seconds=0.05, max_samples=200)
                cmd = ["/usr/bin/time", "-v", "-o", str(time_path), sys.executable, "-B", "-m",
                       "partner_tools.cost_observation.control_workload", mode]
                record["stage"], record["runner_called"] = "runner", True
                record["run"] = asdict(adapter.run(cmd, cwd=str(ROOT), env=None, mask="4", timeout=10, rss=False))
                record["stage"] = "child_output"
                require(len(record["run"]["stdout"].splitlines()) == 1, "child_output_line_count")
                record["child"] = json.loads(record["run"]["stdout"])
        except BaseException as error:
            record["error"], result = fault(error), 1
            if not isinstance(error, Exception):
                interrupted = error
        finally:
            if adapter is not None:
                for key, action in (("observation", lambda: adapter.evidence), ("gnu_time", lambda: read_time(time_path)),
                                    ("seals_after", seals), ("courtesy_after", screen)):
                    try:
                        record[key] = action()
                    except BaseException as error:
                        record.setdefault("capture_errors", []).append({"field": key, **fault(error)})
                        result = 1
                        if not isinstance(error, Exception) and interrupted is None:
                            interrupted = error
            try:
                emit(record)  # Complete raw/partial evidence before result assertions.
            except BaseException:
                if interrupted is not None:
                    raise interrupted  # Broken evidence sink cannot mask interruption.
                raise
        if interrupted is not None:
            raise interrupted
        if result:
            return result
        try:
            summary = analyze(record)
            emit({"record": "wrapped_control_analysis", "mode": mode, **summary})
        except Exception as error:
            emit({"record": "wrapped_control_failure", "mode": mode, "error": fault(error)})
            return 1
        if record["courtesy_after"]["hold"]:
            return 75
    emit({"record": "wrapped_pair_complete", "intended": 2, "completed": 2, "performance_verdict": "UNKNOWN"})
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--log-root", required=True)
    args = parser.parse_args(argv)
    if not args.execute:
        emit({"record": "wrapped_pair_hold", "reason": "explicit_execute_required", "runner_calls": 0})
        return 75
    return run_pair(args.log_root)


if __name__ == "__main__":
    raise SystemExit(main())
