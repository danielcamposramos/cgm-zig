"""Stoppable sample-local observation. Does not launch or modify workloads."""

import copy
import math
import os
import threading
import time

from .procfs import Procfs, identity, interval


class Observer:
    """One-use observer. Caller owns launch, timing, identities and serialization.

    bind_workload() captures PID+start_ticks; a PID alone never owns subsequent
    reuse. Descendants are inferred only from currently observed parent links,
    and that numeric identity stays known if the child is later reparented.
    """

    def __init__(self, workload_pids=(), interval_seconds=0.1, max_samples=10000,
                 reader=None):
        if not math.isfinite(interval_seconds) or interval_seconds <= 0:
            raise ValueError("interval_must_be_positive_finite")
        if isinstance(max_samples, bool) or not isinstance(max_samples, int) or max_samples < 2:
            raise ValueError("max_samples_must_be_at_least_two")
        self.reader = reader or Procfs()
        self.interval_ns = max(1, int(interval_seconds * 1000000000))
        self.max_samples = max_samples
        self._stop = threading.Event()
        self._ready = threading.Event()
        self._lock = threading.Lock()
        self._thread = None
        self._roots = []
        self._known = set()
        self._samples = []
        self._events = []
        self._observer = self.reader.process_identity(os.getpid())
        self._thread_identity = None
        self._thread_cpu_ns = None
        self._begin_ns = None
        self._end_ns = None
        self._stop_reason = None
        self._stop_requested_ns = None
        for pid in workload_pids:
            self.bind_workload(pid)

    def bind_workload(self, pid):
        if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
            raise ValueError("pid_must_be_positive_integer")
        value = self.reader.process_identity(pid)
        with self._lock:
            if self._end_ns is not None:
                raise RuntimeError("observer_already_stopped")
            self._roots.append({**value, "bound_ns": time.monotonic_ns()})
            self._known.add((value["pid"], value["start_ticks"]))
        return dict(value)

    def _roles(self, snapshot):
        processes = snapshot["processes"]
        with self._lock:
            roots = {(p["pid"], p["start_ticks"]) for p in self._roots}
            # Repeated closure handles a child whose row precedes its parent.
            changed = True
            by_pid = {p["pid"]: p for p in processes}
            while changed:
                changed = False
                for p in processes:
                    parent = by_pid.get(p["ppid"])
                    key = (p["pid"], p["start_ticks"])
                    if parent and (parent["pid"], parent["start_ticks"]) in self._known and \
                            parent["start_ticks"] <= p["start_ticks"] and key not in self._known:
                        self._known.add(key)
                        changed = True
            for p in processes:
                key = (p["pid"], p["start_ticks"])
                p["role"] = ("observer_process" if identity(p) == self._observer else
                             "workload_root" if key in roots else
                             "workload_descendant_observed" if key in self._known else "other")

    def _run(self):
        cpu_begin = time.thread_time_ns()
        self._begin_ns = time.monotonic_ns()
        due = self._begin_ns
        try:
            tid = threading.get_native_id()
            try:
                self._thread_identity = self.reader.process_identity(tid)
            except (OSError, ValueError):
                self._events.append({"kind": "observer_thread_identity_unknown", "tid": tid})
            while True:
                entered, cpu_start = time.monotonic_ns(), time.thread_time_ns()
                try:
                    snapshot = self.reader.snapshot()
                    self._roles(snapshot)
                    error = None
                except Exception as exc:
                    snapshot = None
                    error = {"kind": type(exc).__name__}  # no private exception text
                finished = time.monotonic_ns()
                next_due = due + self.interval_ns
                missed = max(0, (finished - next_due) // self.interval_ns + 1)
                self._samples.append({"sequence": len(self._samples), "scheduled_ns": due,
                                      "entered_ns": entered, "finished_ns": finished,
                                      "lag_ns": max(0, entered - due),
                                      "collection_wall_ns": finished - entered,
                                      "collection_thread_cpu_ns": time.thread_time_ns() - cpu_start,
                                      "missed_deadlines": missed,
                                      "snapshot": snapshot, "error": error})
                self._ready.set()
                if self._stop.is_set() and entered >= self._stop_requested_ns:
                    break
                if len(self._samples) >= self.max_samples:
                    self._stop_reason = "sample_limit"
                    break
                due = next_due + missed * self.interval_ns
                self._stop.wait(max(0, (due - time.monotonic_ns()) / 1000000000))
            if self._stop_reason is None:
                self._stop_reason = "caller_stop"
        except BaseException as exc:
            self._events.append({"kind": "observer_terminated", "exception": type(exc).__name__})
            self._stop_reason = "observer_error"
        finally:
            self._thread_cpu_ns = time.thread_time_ns() - cpu_begin
            self._end_ns = time.monotonic_ns()
            self._ready.set()

    def start(self):
        if self._thread is not None:
            raise RuntimeError("observer_is_one_use")
        self._thread = threading.Thread(target=self._run, name="cost-observation", daemon=False)
        try:
            self._thread.start()
            self._ready.wait()
        except BaseException:
            self._stop_requested_ns = time.monotonic_ns()
            self._stop.set()
            if self._thread.ident is not None:
                self._thread.join()
            raise
        return self

    def stop(self):
        if self._thread is None:
            raise RuntimeError("observer_not_started")
        if self._stop_requested_ns is None:
            self._stop_requested_ns = time.monotonic_ns()
        self._stop.set()
        self._thread.join()
        return self.result()

    @property
    def running(self):
        return self._thread is not None and self._thread.is_alive()

    def result(self):
        if self._thread is None or self._end_ns is None or self.running:
            raise RuntimeError("stop_before_reading_result")
        transitions = []
        for left, right in zip(self._samples, self._samples[1:]):
            a, b = left["snapshot"], right["snapshot"]
            transitions.append({"from_sequence": left["sequence"], "to_sequence": right["sequence"],
                                "delta": interval(a, b) if a is not None and b is not None else None})
        return copy.deepcopy({"schema": 1, "platform": "linux_procfs",
            "clock_ticks_per_second": self.reader.clock_ticks_per_second,
            "observer_process": self._observer, "observer_thread": self._thread_identity,
            "workload_roots": self._roots, "interval_ns": self.interval_ns,
            "max_samples": self.max_samples, "begin_ns": self._begin_ns, "end_ns": self._end_ns,
            "stop_requested_ns": self._stop_requested_ns,
            "duration_ns": self._end_ns - self._begin_ns,
            "observer_thread_cpu_ns": self._thread_cpu_ns, "stop_reason": self._stop_reason,
            "samples": self._samples, "intervals": transitions, "events": self._events,
            "performance_verdict": "UNKNOWN", "between_observations": "UNKNOWN"})

    def __enter__(self):
        return self.start()

    def __exit__(self, exc_type, exc_value, traceback):
        self.stop()
        return False
