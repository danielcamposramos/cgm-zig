"""Observation adapter around vlib.run_cmd, never a second process launcher."""

import copy
import os
import threading
import time

from partner_tools.vharness import vlib
from .observe import Observer
from .owned_process import OwnedProcess, validate_file_identity
from .procfs import Procfs, counter_delta, identity


def join_discoveries(calls, observation):
    """Join the two independent enumeration probes around each raw PID read.

    Endpoint deltas are not a claim about execution between probes. Never edit
    the frozen observer's raw 'other' role or infer executable ownership by PID
    alone. An incomplete, differently timed or reused identity stays UNKNOWN.
    """
    output = {"samples": [], "intervals": [], "unassigned_calls": [],
              "between_probes": "UNKNOWN", "before_first_and_after_last_match": "UNKNOWN"}
    if observation is None:
        output["status"] = "observation_unavailable"
        return output
    if any(c["enumeration_begin_ns"] > c["enumeration_end_ns"] for c in calls) or any(
            a["enumeration_end_ns"] > b["enumeration_begin_ns"] for a, b in zip(calls, calls[1:])):
        output["status"] = "enumeration_clock_order_unknown"
        return output
    cursor = 0
    for sample in observation.get("samples", []):
        joined = {"sequence": sample["sequence"], "status": "snapshot_unavailable",
                  "before_call": None, "after_call": None, "target": None, "cpu_counters": None}
        output["samples"].append(joined)
        snapshot = sample.get("snapshot")
        if snapshot is None:
            continue
        begin, end = snapshot["begin_ns"], snapshot["end_ns"]
        while cursor < len(calls) and calls[cursor]["enumeration_end_ns"] < begin:
            output["unassigned_calls"].append(calls[cursor]["call_index"])
            cursor += 1
        members = []
        while cursor < len(calls) and calls[cursor]["enumeration_begin_ns"] <= end:
            members.append(calls[cursor])
            cursor += 1
        joined["status"] = "enumeration_window_unknown"
        if len(members) != 2 or any(c["enumeration_begin_ns"] < begin or
                                    c["enumeration_end_ns"] > end for c in members):
            continue
        before, after = members
        joined.update(before_call=before["call_index"], after_call=after["call_index"],
                      status="target_discovery_disagrees_or_missing")
        target = before["target"]
        if target is None or target != after["target"] or before["wrapper"] != after["wrapper"] or \
                before["relation"] != after["relation"] or before["errors"] or after["errors"] or \
                not before["wrapper_valid"] or not after["wrapper_valid"] or any(
                    c["status"] not in ("matched_direct_child", "matched_launched_process") for c in members):
            continue
        rows = [p for p in snapshot["processes"] if p["pid"] == target["pid"]]
        joined["status"] = "target_row_missing_or_identity_changed"
        if len(rows) != 1 or identity(rows[0]) != target:
            continue
        row = rows[0]
        joined["status"] = "target_read_not_bracketed"
        if not (before["enumeration_end_ns"] <= row["read_start_ns"] <= row["read_end_ns"] <=
                after["enumeration_begin_ns"]):
            continue
        joined.update(status="matched_target_at_snapshot_probes", target=dict(target),
            wrapper=before["wrapper"], relation=before["relation"], raw_role=row.get("role"),
            read_start_ns=row["read_start_ns"], read_end_ns=row["read_end_ns"],
            snapshot_has_errors=bool(snapshot["errors"]),
            cpu_counters={"utime_ticks": row["utime_ticks"], "stime_ticks": row["stime_ticks"]})
    output["unassigned_calls"].extend(c["call_index"] for c in calls[cursor:])
    for a, b in zip(output["samples"], output["samples"][1:]):
        row = {"from_sequence": a["sequence"], "to_sequence": b["sequence"],
               "status": "target_endpoint_coverage_unknown", "target": None,
               "endpoint_cpu_delta_ticks": None, "between_probes": "UNKNOWN"}
        if a["target"] is not None and a["target"] == b["target"] and \
                b["read_end_ns"] > a["read_end_ns"]:
            deltas = {key: counter_delta(a["cpu_counters"][key], b["cpu_counters"][key])
                      for key in ("utime_ticks", "stime_ticks")}
            if all(value is not None for value in deltas.values()):
                row.update(status="same_target_at_observed_endpoints", target=a["target"],
                           endpoint_cpu_delta_ticks=deltas,
                           elapsed_ns=b["read_end_ns"] - a["read_end_ns"])
        output["intervals"].append(row)
    output["status"] = "finite_identity_time_join"
    return output


class LaunchObservation:
    """One-use adapter; run() returns the original Run or raises its exception.

    evidence is separate, JSON-serializable, and available after return/raise.
    Caller supplies sealed numeric executable metadata and owns saving evidence.
    No argv, environment, cwd, executable path, or process name is retained here.
    """

    def __init__(self, sealed_executable, *, interval_seconds=0.05, max_samples=10000,
                 max_children=4, reader=None, finder=None, observer_factory=Observer,
                 runner=vlib.run_cmd, clock=time.monotonic_ns,
                 cpu_clock=time.thread_time_ns):
        self.sealed = validate_file_identity(sealed_executable)
        self.reader = reader
        self.finder = finder
        self.observer_factory = observer_factory
        self.runner, self.clock, self.cpu_clock = runner, clock, cpu_clock
        self.interval_seconds, self.max_samples = interval_seconds, max_samples
        self.max_children = max_children
        self._lock = threading.Lock()
        self._observer = None
        self._used = False
        self._wrapper = None
        self._owner_pid = os.getpid()
        self._evidence = {"schema": 1, "sealed_executable": self.sealed,
            "pid_scope": "custom_enumerator", "notification": None, "discoveries": [],
            "errors": [], "observation": None, "observer_joined": None,
            "identity_join": None,
            "compiler_cpu_summary": None, "performance_verdict": "UNKNOWN",
            "before_target_discovery": "UNKNOWN", "unselected_activity": "UNKNOWN"}

    def _error(self, stage, error):
        with self._lock:
            self._evidence["errors"].append({"stage": stage, "kind": type(error).__name__,
                "errno": getattr(error, "errno", None), "at_ns": self.clock()})

    def _notify(self, process):
        begin, cpu_begin = self.clock(), self.cpu_clock()
        captured = None
        try:
            if self.finder is None:
                raise RuntimeError("identity_instrument_unavailable")
            captured = self.finder.capture(process.pid)  # no scan or wait here
        except Exception as error:
            self._error("launch_identity", error)
        finally:
            with self._lock:
                self._wrapper = captured
                self._evidence["notification"] = {"launched_pid": process.pid,
                    "wrapper_identity": captured, "begin_ns": begin, "end_ns": self.clock(),
                    "thread_cpu_ns": self.cpu_clock() - cpu_begin}

    def _targets(self):
        entered = self.clock()
        with self._lock:
            wrapper = copy.copy(self._wrapper)
        found = {"wrapper": wrapper, "wrapper_valid": False, "target": None, "relation": None,
                 "status": "not_launched", "errors": []}
        try:
            if wrapper is not None:
                found = self.finder.discover(wrapper, self.sealed)
            targets = {self._owner_pid}
            if found["wrapper_valid"]:
                targets.add(wrapper["pid"])
            if found["target"] is not None:
                targets.add(found["target"]["pid"])
            return sorted(targets)
        except Exception as error:
            self._error("target_discovery", error)
            found.update(status="discovery_error", target=None, relation=None,
                         errors=[{"kind": type(error).__name__, "errno": getattr(error, "errno", None)}])
            return [self._owner_pid]
        finally:
            with self._lock:
                notification = self._evidence["notification"]
                found.update(call_index=len(self._evidence["discoveries"]),
                             enumeration_begin_ns=entered, enumeration_end_ns=self.clock(),
                             since_notification_ns=entered - notification["begin_ns"]
                             if notification is not None else None)
                self._evidence["discoveries"].append(found)

    def run(self, cmd, **kwargs):
        if self._used:
            raise RuntimeError("launch_observation_is_one_use")
        if "on_spawn" in kwargs:
            raise ValueError("launch_observation_owns_notification")
        self._used = True
        primary = None
        self._evidence["begin_ns"] = self.clock()
        try:
            try:
                self.reader = self.reader or Procfs()
                self.finder = self.finder or OwnedProcess(self.reader, max_children=self.max_children)
                # Separate reader instance: no mutation of a caller's reader or
                # the frozen selected-PID set. Both use the same supplied reads.
                collecting = Procfs(root=self.reader.root, read=self.reader.read,
                    affinity=self.reader.affinity, clock=self.reader.clock,
                    enumerate_pids=self._targets)
                self._observer = self.observer_factory(reader=collecting,
                    interval_seconds=self.interval_seconds, max_samples=self.max_samples)
                self._observer.start()  # initial aggregate observation BEFORE run_cmd's t0
            except Exception as error:
                self._error("observer_start", error)
            try:
                self._evidence["run_call_begin_ns"] = self.clock()
                return self.runner(cmd, on_spawn=self._notify, **kwargs)
            except BaseException as original:
                self._evidence["run_exception"] = {"kind": type(original).__name__,
                    "errno": getattr(original, "errno", None),
                    "owned_cleanup": getattr(original, "cgm_run_cmd_cleanup", None)}
                raise
            finally:
                self._evidence["run_return_or_raise_ns"] = self.clock()
        except BaseException as original:
            primary = original
            self._evidence["adapter_exception"] = {"kind": type(original).__name__}
            raise
        finally:
            interruption = None
            if self._observer is not None:
                for attempt in range(2):
                    try:
                        self._evidence["observation"] = self._observer.stop()
                        break
                    except BaseException as error:
                        self._error("observer_stop" if attempt == 0 else "observer_stop_recovery", error)
                        if not isinstance(error, Exception) and interruption is None:
                            interruption = error
                        # Ordinary result-construction failure happens after
                        # join. An interruption gets one bounded recovery join.
                        if isinstance(error, Exception) and not self._observer.running:
                            break
                self._evidence["observer_joined"] = not self._observer.running
            try:
                self._evidence["identity_join"] = join_discoveries(
                    self._evidence["discoveries"], self._evidence["observation"])
            except BaseException as error:
                self._error("identity_time_join", error)
                if not isinstance(error, Exception) and interruption is None:
                    interruption = error
            self._evidence["end_ns"] = self.clock()
            if primary is None and interruption is not None:
                self._evidence["adapter_exception"] = {"kind": type(interruption).__name__}
                raise interruption

    @property
    def evidence(self):
        if not self._used or "end_ns" not in self._evidence:
            raise RuntimeError("run_must_finish_before_reading_evidence")
        with self._lock:
            return copy.deepcopy(self._evidence)
