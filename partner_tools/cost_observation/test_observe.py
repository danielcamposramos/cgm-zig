"""In-memory unit fixtures; explicitly opt-in, bounded non-compiler controls."""

import copy
from collections import Counter
import errno
import hashlib
import itertools
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import unittest

from .observe import Observer
from .procfs import (CPU_FIELDS, IO_FIELDS, Procfs, counter_delta, interval,
                     parse_load, parse_pressure, parse_process, parse_stat)


def process_text(pid=100, start=10, user=3, system=2, parent=1):
    fields = ["0"] * 37
    for index, value in {0: "S", 1: parent, 11: user, 12: system,
                         17: 1, 19: start, 36: 4}.items():
        fields[index] = str(value)
    return f"{pid} (DO_NOT_RETAIN a) b) " + " ".join(fields)


def memory_reader(overrides=None, pids=None, affinity=None, selected_pids=None):
    files = {"stat": "cpu 1 2 3 4 5 6 7 8 9 10\ncpu4 1 2 3 4 5 6 7 8 9 10\n"
                     "ctxt 20\nprocesses 30\nprocs_running 1\nprocs_blocked 0\n",
             "loadavg": "0.1 0.2 0.3 1/30 100\n", "vmstat": "pgpgin 10\npgpgout 20\n",
             "100/stat": process_text(),
             "100/io": "".join(f"{key}: 4\n" for key in IO_FIELDS)}
    files.update({"pressure/" + key: "some avg10=0.1 avg60=0.2 avg300=0.3 total=5\n"
                  for key in ("cpu", "io", "memory")})
    files.update(overrides or {})

    def read(path):
        value = files[path]
        if isinstance(value, BaseException):
            raise value
        return value() if callable(value) else value

    enumerator = pids if selected_pids is not None else pids or (lambda: [100])
    return Procfs(read=read, enumerate_pids=enumerator, selected_pids=selected_pids,
                  affinity=affinity or (lambda pid: {4}), clock=itertools.count(100).__next__)


def sample(user=3, start=10):
    result = memory_reader({"100/stat": process_text(user=user, start=start)}).snapshot()
    for p in result["processes"]:
        p["role"] = "other"
    return result


class ParserTests(unittest.TestCase):
    def test_process_discards_comm_with_parentheses(self):
        parsed = parse_process(process_text())
        self.assertEqual(parsed, {"pid": 100, "ppid": 1, "utime_ticks": 3,
                                  "stime_ticks": 2, "threads": 1,
                                  "start_ticks": 10, "last_cpu": 4})
        self.assertNotIn("DO_NOT_RETAIN", json.dumps(parsed))

    def test_truncated_process_refused(self):
        with self.assertRaises(ValueError):
            parse_process("100 (name) S 1 2")

    def test_missing_cpu_fields_are_unknown_not_zero(self):
        value = parse_stat("cpu 1 2 3 4\ncpu4 1 2 3 4\n")
        self.assertIsNone(value["cpus"]["cpu4"]["steal"])
        self.assertIsNone(value["system"]["procs_running"])
        with self.assertRaises(ValueError):
            parse_stat("cpu 1 2 3 4\n")

    def test_bad_load_and_pressure_refused(self):
        for text in ("nan 0 0 1/2 3", "0 0 0 1 3", "0 0"):
            with self.assertRaises(ValueError):
                parse_load(text)
        with self.assertRaises(ValueError):
            parse_pressure("some avg10=0 total=1")
        with self.assertRaises(ValueError):
            parse_pressure("some avg10=0 avg10=1 avg60=0 avg300=0 total=1")


class SnapshotTests(unittest.TestCase):
    def test_complete_numeric_snapshot(self):
        value = sample()
        self.assertEqual(value["errors"], [])
        self.assertEqual(value["pids_before"], [100])
        self.assertEqual(value["processes"][0]["affinity"], [4])
        self.assertEqual(value["processes"][0]["last_cpu"], 4)
        self.assertIsNone(value["pressure"]["cpu"]["full"])
        self.assertNotIn("DO_NOT_RETAIN", json.dumps(value, allow_nan=False))

    def test_permissions_preserve_unknown_and_suppress_exception_text(self):
        error = PermissionError(errno.EACCES, "DO_NOT_RETAIN")
        value = memory_reader({"100/io": error, "pressure/io": error}).snapshot()
        self.assertEqual(len(value["errors"]), 2)
        self.assertIsNone(value["processes"][0]["io"])
        self.assertIsNone(value["pressure"]["io"])
        self.assertNotIn("DO_NOT_RETAIN", json.dumps(value))

    def test_affinity_failure_is_explicit(self):
        def failure(pid):
            raise ProcessLookupError(errno.ESRCH, "DO_NOT_RETAIN")
        value = memory_reader(affinity=failure).snapshot()
        self.assertIsNone(value["processes"][0]["affinity"])
        self.assertEqual(value["errors"][0]["source"], "affinity")
        self.assertEqual(value["errors"][0]["errno"], errno.ESRCH)

    def test_missing_stat_and_truncated_stat_are_explicit(self):
        for bad in (FileNotFoundError(errno.ENOENT, "private"), "cpu 1"):
            value = memory_reader({"stat": bad}).snapshot()
            self.assertIsNone(value["stat"])
            self.assertEqual(value["errors"][0]["source"], "stat")

    def test_enumeration_failure_not_empty_success(self):
        def failure():
            raise PermissionError(errno.EACCES, "private")
        value = memory_reader(pids=failure).snapshot()
        self.assertIsNone(value["pids_before"])
        self.assertIsNone(value["pids_after"])
        self.assertEqual(len(value["errors"]), 2)
        self.assertTrue(interval(sample(), value)["enumeration_unknown"])

    def test_pid_reuse_during_capture_refused(self):
        texts = iter([process_text(), process_text(start=99)])
        value = memory_reader({"100/stat": lambda: next(texts)}).snapshot()
        self.assertEqual(value["processes"], [])
        self.assertEqual(value["errors"][0]["kind"], "identity_changed_during_read")

    def test_disappeared_mid_capture_and_enumeration_changes(self):
        values = iter([process_text(), FileNotFoundError(errno.ENOENT, "private")])
        def read():
            value = next(values)
            if isinstance(value, BaseException):
                raise value
            return value
        lists = iter([[100], [101]])
        value = memory_reader({"100/stat": read}, pids=lambda: next(lists)).snapshot()
        self.assertEqual(value["processes"], [])
        self.assertEqual(value["appeared_during_scan"], [101])
        self.assertEqual(value["disappeared_during_scan"], [100])
        self.assertEqual(value["errors"][0]["errno"], errno.ENOENT)


class DeltaTests(unittest.TestCase):
    def test_nonzero_other_activity_is_not_lost(self):
        before, after = sample(), sample(user=13)
        after["stat"]["cpus"]["cpu4"]["user"] += 12
        value = interval(before, after)
        self.assertEqual(value["processes"][0]["role"], "other")
        self.assertEqual(value["processes"][0]["utime_ticks"], 10)
        self.assertEqual(value["cpus"]["cpu4"]["user"], 12)
        self.assertEqual(value["between_observations"], "UNKNOWN")

    def test_pid_reuse_has_no_cpu_delta(self):
        value = interval(sample(user=100), sample(user=300, start=99))
        self.assertEqual(value["processes"][0]["state"], "pid_reused")
        self.assertIsNone(value["processes"][0]["utime_ticks"])

    def test_unknown_or_decreased_counters_not_zero(self):
        self.assertIsNone(counter_delta(None, 10))
        self.assertIsNone(counter_delta(20, 10))
        before, after = sample(), sample()
        after["stat"] = None
        after["errors"] = [{"source": "stat"}]
        value = interval(before, after)
        self.assertIsNone(value["cpus"])
        self.assertTrue(value["endpoint_errors"])

    def test_pressure_and_io_deltas_keep_numeric_units(self):
        before, after = sample(), sample()
        after["pressure"]["io"]["some"]["total"] += 17
        after["processes"][0]["io"]["read_bytes"] += 4096
        value = interval(before, after)
        self.assertEqual(value["pressure_total_us"]["io"]["some"], 17)
        self.assertIsNone(value["pressure_total_us"]["io"]["full"])
        self.assertEqual(value["processes"][0]["io"]["read_bytes"], 4096)

    def test_new_and_disappeared_process_have_unknown_deltas(self):
        before, after = sample(), sample()
        after["processes"][0]["pid"] = 101
        rows = interval(before, after)["processes"]
        self.assertEqual([p["state"] for p in rows], ["not_observed", "newly_observed"])
        self.assertTrue(all(p["utime_ticks"] is None for p in rows))


class SelectedScopeTests(unittest.TestCase):
    def test_selection_is_not_observed_enumeration(self):
        requests = [100]
        reader = memory_reader(selected_pids=requests)
        requests.append(101)  # construction seals a copy of the declared set
        value = reader.snapshot()
        self.assertEqual(value["pid_coverage"], {
            "mode": "selected_ids", "requested_pids": [100], "attempted_pids": [100],
            "attempted_count": 1, "captured_count": 1,
            "unselected_process_activity": "UNKNOWN", "unselected_descendants": "UNKNOWN"})
        self.assertIsNone(value["pids_before"])
        self.assertIsNone(value["pids_after"])
        self.assertIsNone(value["appeared_during_scan"])
        self.assertIsNone(value["disappeared_during_scan"])
        self.assertEqual(value["errors"], [])

    def test_modes_are_explicit_without_extra_host_reads(self):
        self.assertEqual(Procfs().pid_scope, "visible_procfs")
        custom = sample()
        self.assertEqual(custom["pid_coverage"]["mode"], "custom_enumerator")
        selected = memory_reader(selected_pids={100}).snapshot()
        delta = interval(custom, selected)
        self.assertEqual(delta["pid_coverage"]["before"]["mode"], "custom_enumerator")
        self.assertEqual(delta["pid_coverage"]["after"]["mode"], "selected_ids")
        self.assertTrue(delta["enumeration_unknown"])

    def test_invalid_or_ambiguous_selection_refused(self):
        for bad in ([], (), set(), [0], [-1], [True], [1.5], ["100"], "100", 100,
                    [100, 100], {"pid": 100}, iter([100])):
            with self.assertRaises(ValueError):
                Procfs(selected_pids=bad)
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            Procfs(selected_pids={100}, enumerate_pids=lambda: [100])

    def test_unselected_activity_remains_in_aggregate_counters(self):
        before = memory_reader(selected_pids={100}).snapshot()
        after = memory_reader(selected_pids={100}).snapshot()
        # CPU 9 does work even though the selected process does not accrue ticks.
        before["stat"]["cpus"]["cpu9"] = dict(before["stat"]["cpus"]["cpu4"])
        after["stat"]["cpus"]["cpu9"] = dict(before["stat"]["cpus"]["cpu9"], user=41)
        after["stat"]["cpus"]["cpu"]["user"] += 40
        value = interval(before, after)
        self.assertEqual(value["cpus"]["cpu9"]["user"], 40)
        self.assertEqual(value["cpus"]["cpu"]["user"], 40)
        self.assertEqual(value["processes"][0]["utime_ticks"], 0)
        self.assertEqual(value["pid_coverage"]["after"]["requested_pids"], [100])
        self.assertEqual(value["pid_coverage"]["outside_recorded_identities"], "UNKNOWN")

    def test_selected_permission_and_disappearance_errors(self):
        bad = {"100/stat": FileNotFoundError(errno.ENOENT, "DO_NOT_RETAIN")}
        missing = memory_reader(bad, selected_pids={100}).snapshot()
        self.assertEqual(missing["pid_coverage"]["attempted_count"], 1)
        self.assertEqual(missing["pid_coverage"]["captured_count"], 0)
        self.assertEqual(missing["pid_coverage"]["requested_pids"], [100])
        self.assertEqual(missing["errors"][0]["errno"], errno.ENOENT)
        denied = memory_reader({"100/io": PermissionError(errno.EACCES, "DO_NOT_RETAIN")},
                               selected_pids={100}).snapshot()
        self.assertIsNone(denied["processes"][0]["io"])
        self.assertEqual(denied["errors"][0]["errno"], errno.EACCES)
        self.assertNotIn("DO_NOT_RETAIN", json.dumps([missing, denied]))

    def test_selected_reuse_and_disappearance_have_no_invented_deltas(self):
        before = memory_reader(selected_pids={100}).snapshot()
        after = memory_reader({"100/stat": process_text(start=99)}, selected_pids={100}).snapshot()
        value = interval(before, after)
        self.assertEqual(value["processes"][0]["state"], "pid_reused")
        self.assertIsNone(value["processes"][0]["utime_ticks"])
        after = memory_reader({"100/stat": FileNotFoundError(errno.ENOENT, "missing")},
                              selected_pids={100}).snapshot()
        value = interval(before, after)
        self.assertEqual(value["processes"][0]["state"], "not_observed")
        self.assertIsNone(value["processes"][0]["utime_ticks"])
        self.assertTrue(value["endpoint_errors"])

    def test_selected_identity_changes_inside_read_are_refused(self):
        texts = iter([process_text(), process_text(start=99)])
        value = memory_reader({"100/stat": lambda: next(texts)}, selected_pids={100}).snapshot()
        self.assertEqual(value["processes"], [])
        self.assertEqual(value["errors"][0]["kind"], "identity_changed_during_read")
        self.assertEqual(value["pid_coverage"]["captured_count"], 0)


class SequenceReader:
    clock_ticks_per_second = 100

    def __init__(self, values):
        self.values = iter(values)

    def process_identity(self, pid):
        return {"pid": pid, "start_ticks": 10}

    def snapshot(self):
        value = next(self.values)
        if isinstance(value, BaseException):
            raise value
        return copy.deepcopy(value)


class LifecycleTests(unittest.TestCase):
    def test_collector_failure_is_unknown_and_sample_limit_stops(self):
        obs = Observer(reader=SequenceReader([RuntimeError("DO_NOT_RETAIN"), sample()]),
                       interval_seconds=1e-9, max_samples=2)
        obs.start()
        obs._thread.join()  # deterministic cap, not a wall-clock assertion
        value = obs.stop()
        self.assertFalse(obs.running)
        self.assertEqual(value["stop_reason"], "sample_limit")
        self.assertEqual(len(value["samples"]), 2)
        self.assertIsNone(value["intervals"][0]["delta"])
        self.assertEqual(value["performance_verdict"], "UNKNOWN")
        self.assertNotIn("DO_NOT_RETAIN", json.dumps(value))

    def test_context_exception_joins_and_one_use_refuses(self):
        obs = Observer(reader=SequenceReader([sample(), sample()]), interval_seconds=10)
        with self.assertRaisesRegex(RuntimeError, "caller_failure"):
            with obs:
                raise RuntimeError("caller_failure")
        self.assertFalse(obs.running)
        value = obs.result()
        self.assertEqual(value["stop_reason"], "caller_stop")
        self.assertEqual(len(value["samples"]), 2)
        self.assertGreaterEqual(value["samples"][-1]["entered_ns"], value["stop_requested_ns"])
        with self.assertRaises(RuntimeError):
            obs.start()
        with self.assertRaises(RuntimeError):
            obs.bind_workload(100)

    def test_roles_follow_identities_not_reused_pid(self):
        before, after = sample(), sample(start=99)
        child = dict(before["processes"][0], pid=101, ppid=100, start_ticks=11)
        before["processes"].append(child)
        after["processes"].append(dict(child, ppid=1))
        obs = Observer(workload_pids=[100], reader=SequenceReader([before, after]),
                       interval_seconds=1e-9, max_samples=2)
        obs.start()
        obs._thread.join()
        value = obs.stop()
        rows = [s["snapshot"]["processes"] for s in value["samples"]]
        self.assertEqual(rows[0][0]["role"], "workload_root")
        self.assertEqual(rows[1][0]["role"], "other")
        self.assertEqual(rows[1][1]["role"], "workload_descendant_observed")

    def test_invalid_settings_refused_before_collection(self):
        for kwargs in ({"interval_seconds": 0}, {"interval_seconds": float("nan")},
                       {"max_samples": 1}):
            with self.assertRaises(ValueError):
                Observer(reader=SequenceReader([]), **kwargs)


CHILD = """
import json, sys, time
print('READY', flush=True)
sys.stdin.readline()
begin = time.process_time()
deadline = time.monotonic() + 2.0
if sys.argv[1] == 'busy':
    while time.process_time() - begin < 0.35 and time.monotonic() < deadline:
        sum(range(2000))
else:
    time.sleep(0.5)
print(json.dumps({'cpu_seconds': time.process_time() - begin}), flush=True)
sys.stdin.readline()
"""


def control_line(child, timeout=5):
    """Only one protocol line is outstanding; never wait forever for a child."""
    ready, _, _ = select.select([child.stdout], [], [], timeout)
    if not ready:
        raise TimeoutError("owned_control_output_timeout")
    # The controlled child emits each small newline-terminated line in one flush.
    line = child.stdout.readline()
    if not line:
        raise RuntimeError("owned_control_unexpected_eof")
    return line


@unittest.skipUnless(os.environ.get("COST_OBSERVATION_HOST_CONTROLS") == "1",
                     "host controls require explicit opt-in and current courtesy")
class HostControls(unittest.TestCase):
    def test_one_busy_and_one_idle_owned_child(self):
        from partner_tools.vharness.vlib import machine_courtesy
        for mode in ("busy", "idle"):
            busy, matches = machine_courtesy()
            if busy:
                self.skipTest(f"HOLD: {len(matches)} competing compiler matches; no child launched")
            child = subprocess.Popen([sys.executable, "-B", "-c", CHILD, mode],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, start_new_session=True)
            obs = None
            try:
                self.assertEqual(control_line(child).strip(), "READY")
                obs = Observer([child.pid], interval_seconds=0.05, max_samples=100)
                with obs:
                    child.stdin.write("go\n")
                    child.stdin.flush()
                    payload = json.loads(control_line(child))
                value = obs.result()
                child.stdin.write("exit\n")
                child.stdin.flush()
                out, err = child.communicate(timeout=5)
                self.assertEqual((child.returncode, out, err), (0, "", ""))
                self.assertFalse(obs.running)
                self.assertEqual(value["stop_reason"], "caller_stop")
                deltas = [p for item in value["intervals"] if item["delta"] is not None
                          for p in item["delta"]["processes"] if p["pid"] == child.pid]
                self.assertGreaterEqual(len(deltas), 2)
                self.assertTrue(all(p["state"] == "continued" for p in deltas))
                self.assertTrue(all(p["utime_ticks"] is not None and p["stime_ticks"] is not None
                                    for p in deltas))
                ticks = sum(p["utime_ticks"] + p["stime_ticks"] for p in deltas)
                hz = value["clock_ticks_per_second"]
                # Independent child process_time is not derived from procfs ticks.
                self.assertLessEqual(abs(ticks / hz - payload["cpu_seconds"]), 3 / hz)
                if mode == "busy":
                    self.assertGreaterEqual(payload["cpu_seconds"], 0.35)
                    self.assertGreater(ticks, 0)
                else:
                    self.assertLessEqual(ticks, 3)  # resolution allowance, not quiet-host proof
                self.assertTrue(all(s["snapshot"] is not None and s["snapshot"]["stat"] is not None
                                    for s in value["samples"]))
                self.assertGreaterEqual(value["samples"][-1]["entered_ns"], value["stop_requested_ns"])
                busy_after, matches_after = machine_courtesy()
                print(json.dumps({"control": mode, "child": value["workload_roots"][0],
                      "observer": value["observer_process"], "thread": value["observer_thread"],
                      "samples": len(value["samples"]), "intervals": len(deltas),
                      "cpu_ticks": ticks, "hz": hz, "child_cpu_seconds": payload["cpu_seconds"],
                      "missed_deadlines": sum(s["missed_deadlines"] for s in value["samples"]),
                      "read_errors": sum(len(s["snapshot"]["errors"]) for s in value["samples"]),
                      "observer_thread_cpu_ns": value["observer_thread_cpu_ns"],
                      "duration_ns": value["duration_ns"], "observer_stopped": not obs.running,
                      "courtesy_after_matches": len(matches_after),
                      "performance_verdict": value["performance_verdict"]}), flush=True)
                self.assertFalse(busy_after, "HOLD: competing compile appeared; do not launch next control")
            finally:
                if obs is not None and obs.running:
                    obs.stop()
                if child.poll() is None:
                    # Only this test's own child, never an unrelated process.
                    child.terminate()
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait(timeout=5)
                for stream in (child.stdin, child.stdout, child.stderr):
                    stream.close()


@unittest.skipUnless(os.environ.get("COST_OBSERVATION_SELECTED_CONTROLS") == "1",
                     "selected controls require distinct opt-in and current courtesy")
class SelectedHostControls(unittest.TestCase):
    def test_one_selected_busy_and_one_selected_idle_child(self):
        from partner_tools.vharness.vlib import machine_courtesy
        sources = {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                   for name in ("__init__.py", "procfs.py", "observe.py", "test_observe.py")}
        print(json.dumps({"record": "selected_controls_pre", "source_sha256": sources,
                          "modes": ["busy", "idle"], "interval_seconds": 0.05,
                          "max_samples": 100}), flush=True)
        for mode in ("busy", "idle"):
            busy, matches = machine_courtesy()
            if busy:
                self.skipTest(f"HOLD: {len(matches)} competing compiler matches; no next child launched")
            child = subprocess.Popen([sys.executable, "-B", "-c", CHILD, mode],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, start_new_session=True)
            obs = None
            try:
                self.assertEqual(control_line(child).strip(), "READY")
                requested = sorted({os.getpid(), child.pid})
                obs = Observer([child.pid], interval_seconds=0.05, max_samples=100,
                               reader=Procfs(selected_pids=requested))
                with obs:
                    child.stdin.write("go\n")
                    child.stdin.flush()
                    payload = json.loads(control_line(child))
                value = obs.result()
                child.stdin.write("exit\n")
                child.stdin.flush()
                out, err = child.communicate(timeout=5)
                errors = Counter((e["source"], e["kind"], e["errno"])
                                 for s in value["samples"] if s["snapshot"] is not None
                                 for e in s["snapshot"]["errors"])
                deltas = [p for item in value["intervals"] if item["delta"] is not None
                          for p in item["delta"]["processes"] if p["pid"] == child.pid]
                valid = [p for p in deltas if p["utime_ticks"] is not None
                         and p["stime_ticks"] is not None]
                ticks = sum(p["utime_ticks"] + p["stime_ticks"] for p in valid)
                busy_after, matches_after = machine_courtesy()
                print(json.dumps({"record": "selected_control", "control": mode,
                    "source_sha256": sources, "observation": value,
                    "summary": {"requested_pids": requested,
                        "requested_pid_count": len(requested), "samples": len(value["samples"]),
                        "adjacent_intervals": len(value["intervals"]),
                        "child_intervals": len(deltas), "valid_child_intervals": len(valid),
                        "cpu_ticks": ticks, "child_cpu_seconds": payload["cpu_seconds"],
                        "error_sources": [{"source": key[0], "kind": key[1], "errno": key[2],
                                           "count": count} for key, count in
                                          sorted(errors.items(), key=lambda item: (item[0][0], item[0][1],
                                                                                   str(item[0][2])))],
                        "read_errors": sum(errors.values()),
                        "missed_deadlines": sum(s["missed_deadlines"] for s in value["samples"]),
                        "collection_wall_ns": sum(s["collection_wall_ns"] for s in value["samples"]),
                        "observer_thread_cpu_ns": value["observer_thread_cpu_ns"],
                        "duration_ns": value["duration_ns"], "child_exit": child.returncode,
                        "child_stdout_bytes_after_protocol": len(out.encode()),
                        "child_stderr_bytes": len(err.encode()),
                        "observer_stopped": not obs.running,
                        "courtesy_before_matches": len(matches),
                        "courtesy_after_matches": len(matches_after)}}), flush=True)
                self.assertEqual((child.returncode, out, err), (0, "", ""))
                self.assertFalse(obs.running)
                self.assertEqual(value["stop_reason"], "caller_stop")
                self.assertEqual(len(deltas), len(value["intervals"]))
                self.assertGreaterEqual(len(deltas), 2)
                self.assertEqual(len(valid), len(deltas))
                self.assertTrue(all(p["state"] == "continued" for p in deltas))
                hz = value["clock_ticks_per_second"]
                self.assertLessEqual(abs(ticks / hz - payload["cpu_seconds"]), 3 / hz)
                if mode == "busy":
                    self.assertGreaterEqual(payload["cpu_seconds"], 0.35)
                    self.assertGreater(ticks, 0)
                else:
                    self.assertLessEqual(ticks, 3)
                for sample_record in value["samples"]:
                    snapshot = sample_record["snapshot"]
                    self.assertIsNotNone(snapshot)
                    self.assertIsNotNone(snapshot["stat"])
                    self.assertEqual(snapshot["pid_coverage"]["mode"], "selected_ids")
                    self.assertEqual(snapshot["pid_coverage"]["requested_pids"], requested)
                    self.assertEqual(snapshot["pid_coverage"]["captured_count"], 2)
                    self.assertEqual(sorted(p["pid"] for p in snapshot["processes"]), requested)
                    self.assertIsNone(snapshot["pids_before"])
                    self.assertIsNone(snapshot["pids_after"])
                self.assertGreaterEqual(value["samples"][-1]["entered_ns"], value["stop_requested_ns"])
                self.assertEqual(value["performance_verdict"], "UNKNOWN")
                self.assertFalse(busy_after, "HOLD: competing compile appeared; no next control")
            finally:
                if obs is not None and obs.running:
                    obs.stop()
                if child.poll() is None:
                    child.terminate()  # only this test's own non-compiler child
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait(timeout=5)
                for stream in (child.stdin, child.stdout, child.stderr):
                    stream.close()


if __name__ == "__main__":
    unittest.main()
