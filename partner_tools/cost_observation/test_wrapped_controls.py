"""Deterministic in-memory control receipts; never execute the child or launcher."""

import copy
from contextlib import ExitStack
import io
import json
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from . import wrapped_controls as controls
from .control_workload import work
from partner_tools.vharness import vlib


def fixture(mode="busy"):
    child, wrapper = {"pid": 200, "start_ticks": 20}, {"pid": 100, "start_ticks": 10}
    end = 850_000_000 if mode == "busy" else 1_000_000_000
    cpu, ticks = (350_000_000, [0, 20, 35]) if mode == "busy" else (0, [0, 0, 0])
    samples, joined, intervals = [], [], []
    for seq, point in enumerate([400_000_000, 700_000_000, end + 100_000_000]):
        row = {**child, "affinity": [4]}
        samples.append({"sequence": seq, "snapshot": {"stat": {}, "errors": [], "processes": [row],
            "pid_coverage": {"mode": "custom_enumerator"}}, "missed_deadlines": 0, "collection_wall_ns": 10})
        joined.append({"sequence": seq, "target": child, "wrapper": wrapper, "relation": "direct_child",
            "status": "matched_target_at_snapshot_probes", "snapshot_has_errors": False,
            "read_start_ns": point, "read_end_ns": point + 1})
        if seq:
            intervals.append({"from_sequence": seq - 1, "to_sequence": seq, "target": child,
                "endpoint_cpu_delta_ticks": {"utime_ticks": ticks[seq] - ticks[seq - 1], "stime_ticks": 0}})
    return {"mode": mode, "run": {"rc": 0, "timed_out": False, "stderr": ""},
        "gnu_time": {"raw": "\tExit status: 0\n"}, "seals_before": {"sealed": True}, "seals_after": {"sealed": True},
        "child": {"mode": mode, "child": child, "affinity": [4], "pre_hold_ns": [0, 500_000_000],
            "work_ns": [500_000_000, end], "post_hold_ns": [end, end + 500_000_000],
            "cpu_ns": [0, cpu], "cpu_seconds": cpu / 1e9, "deadline_reached_before_cpu_target": False},
        "observation": {"observer_joined": True, "errors": [], "notification": {"wrapper_identity": wrapper},
            "run_call_begin_ns": -1, "run_return_or_raise_ns": end + 500_000_001,
            "identity_join": {"samples": joined, "intervals": intervals}, "observation": {
                "stop_reason": "caller_stop", "events": [], "samples": samples, "clock_ticks_per_second": 100,
                "observer_thread_cpu_ns": 1000, "duration_ns": end + 500_000_000}}}


class AnalysisTests(unittest.TestCase):
    def test_valid_busy_and_idle(self):
        for mode, ticks in (("busy", 35), ("idle", 0)):
            value = controls.analyze(fixture(mode))
            self.assertEqual((value["cpu_ticks"], value["chain_samples"], value["chain_intervals"]), (ticks, 3, 2))
            self.assertEqual(value["performance_verdict"], "UNKNOWN")

    def test_named_negative_controls(self):
        changes = [
            (lambda r: r["child"].update(child={"pid": 100, "start_ticks": 10}), "wrapper_is_not_child"),
            (lambda r: r["child"].update(child={"pid": 201, "start_ticks": 21}), "work_endpoints_unbracketed"),
            (lambda r: r["observation"]["identity_join"]["samples"][1].update(target=None), "middle_target_coverage_missing"),
            (lambda r: r["observation"]["identity_join"]["samples"].pop(1), "middle_target_coverage_missing"),
            (lambda r: r["observation"]["identity_join"]["samples"][0].update(read_end_ns=600_000_000), "work_endpoints_unbracketed"),
            (lambda r: r["child"].update(post_hold_ns=[850_000_000, 900_000_000]), "holds_insufficient"),
            (lambda r: r["child"].update(deadline_reached_before_cpu_target=True), "child_cpu_deadline"),
            (lambda r: r.update(seals_after={"sealed": False}), "input_seal_drift"),
            (lambda r: r["run"].update(rc=124, timed_out=True), "run_not_successful"),
            (lambda r: r["observation"]["errors"].append({"kind": "OSError"}), "adapter_error_or_not_joined"),
            (lambda r: r["observation"].update(run_call_begin_ns=1), "run_window_unbracketed"),
            (lambda r: r["observation"]["identity_join"]["intervals"][0].update(endpoint_cpu_delta_ticks=None), "target_delta_missing"),
            (lambda r: r["observation"]["identity_join"]["intervals"].reverse(), "target_delta_missing"),
            (lambda r: r["observation"]["observation"]["samples"][1]["snapshot"]["processes"][0].update(start_ticks=99), "target_snapshot_invalid"),
            (lambda r: r["gnu_time"].update(raw="missing"), "gnu_time_exit_unknown"),
        ]
        for change, expected in changes:
            with self.subTest(check=expected):
                record = fixture()
                change(record)
                with self.assertRaisesRegex(controls.ControlFailure, expected):
                    controls.analyze(record)

    def test_wrapper_only_rows_cannot_supply_cpu(self):
        value = fixture()
        for sample in value["observation"]["observation"]["samples"]:
            sample["snapshot"]["processes"] = [{"pid": 100, "start_ticks": 10, "affinity": [4]}]
        with self.assertRaisesRegex(controls.ControlFailure, "target_snapshot_invalid"):
            controls.analyze(value)

    def test_misses_are_reported_not_a_speed_verdict(self):
        value = fixture()
        value["observation"]["observation"]["samples"][1]["missed_deadlines"] = 2
        self.assertEqual(controls.analyze(value)["missed_deadlines"], 2)


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.records, self.calls = [], []
        self.stack.enter_context(patch.object(vlib.subprocess, "Popen", side_effect=AssertionError("HOST_LAUNCH_FORBIDDEN")))
        for method, value in (("is_dir", True), ("is_symlink", False), ("iterdir", ()), ("exists", False)):
            self.stack.enter_context(patch.object(controls.Path, method, return_value=value))
        self.bank = {"tools": {"python": {"identity": {"ino": 1}}}}
        self.seals = self.stack.enter_context(patch.object(controls, "seals", return_value=self.bank))
        self.screen = self.stack.enter_context(patch.object(controls, "screen", return_value={"hold": False}))
        self.stack.enter_context(patch.object(controls, "read_time", return_value={"raw": "Exit status: 0\n"}))
        self.stack.enter_context(patch.object(controls, "emit", side_effect=lambda r: self.records.append(copy.deepcopy(r))))
        self.factory = self.stack.enter_context(patch.object(controls, "LaunchObservation", side_effect=self.adapter))

    def adapter(self, *args, **kwargs):
        value = Mock()
        def run(cmd, **options):
            self.calls.append((cmd, options))
            record = fixture(cmd[-1])
            value.evidence = record["observation"]
            return vlib.Run(["taskset", "-c", "4"] + cmd, 0, 1.5, json.dumps(record["child"]), "", 0)
        value.run.side_effect = run
        return value

    def test_pair_exact_order_configuration_and_raw_before_analysis(self):
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 0)
        self.assertEqual([c[0][-1] for c in self.calls], ["busy", "idle"])
        for cmd, options in self.calls:
            self.assertEqual(cmd[:3], ["/usr/bin/time", "-v", "-o"])
            self.assertEqual(options, {"cwd": str(controls.ROOT), "env": None, "mask": "4", "timeout": 10, "rss": False})
        self.assertEqual([r["record"] for r in self.records], ["wrapped_pair_pre", "wrapped_control_raw",
            "wrapped_control_analysis", "wrapped_control_raw", "wrapped_control_analysis", "wrapped_pair_complete"])
        self.assertTrue(all(c.kwargs == {"interval_seconds": 0.05, "max_samples": 200} for c in self.factory.call_args_list))

    def test_hold_has_no_launch_and_nonzero_status(self):
        self.screen.return_value = {"hold": True}
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 75)
        self.assertEqual(self.calls, [])
        self.assertFalse(self.records[-1]["runner_called"])

    def test_drift_failure_preserves_raw_and_suppresses_second(self):
        self.seals.side_effect = [self.bank, self.bank, {"changed": True}]
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
        self.assertEqual(len(self.calls), 1)
        self.assertIsNotNone(self.records[-2]["run"])
        self.assertEqual(self.records[-1]["error"]["check"], "input_seal_drift")

    def test_launch_error_preserves_partial_evidence_and_suppresses_second(self):
        self.factory.side_effect = lambda *a, **k: Mock(run=Mock(side_effect=OSError("NOT_RETAINED")), evidence={"partial": True})
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
        self.assertEqual(self.factory.call_count, 1)
        self.assertEqual(self.records[-1]["observation"], {"partial": True})
        self.assertNotIn("NOT_RETAINED", json.dumps(self.records))

    def test_capture_error_preserves_actual_run_and_suppresses_second(self):
        with patch.object(controls, "read_time", side_effect=FileNotFoundError("NOT_RETAINED")):
            self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
        self.assertEqual(len(self.calls), 1)
        self.assertIsNotNone(self.records[-1]["run"])
        self.assertEqual(self.records[-1]["capture_errors"][0]["field"], "gnu_time")

    def test_post_courtesy_hold_suppresses_second(self):
        self.screen.side_effect = [{"hold": False}, {"hold": True}]
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 75)
        self.assertEqual(len(self.calls), 1)

    def test_without_execute_never_enters_pair(self):
        with patch.object(controls, "run_pair") as pair:
            self.assertEqual(controls.main(["--log-root", "/PUBLIC_CONTROL_LOGS"]), 75)
        pair.assert_not_called()

    def test_missing_directory_and_prelaunch_seal_guard_names(self):
        with patch.object(controls.Path, "is_dir", return_value=False):
            self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
        self.assertEqual(self.records[-1]["error"]["check"], "existing_empty_log_directory_required")
        self.seals.side_effect = [self.bank, {"changed": True}]
        self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
        self.assertEqual(self.records[-1]["error"]["check"], "prelaunch_drift_or_existing_log")
        self.factory.assert_not_called()

    def test_child_line_guard_and_timeout_each_suppress_second_launch(self):
        for timeout in (False, True):
            self.calls.clear()
            def adapter(*args, **kwargs):
                value = self.adapter()
                original = value.run.side_effect
                def run(*args, **kwargs):
                    result = original(*args, **kwargs)
                    result.rc, result.timed_out = (124, True) if timeout else (0, False)
                    result.stdout += "" if timeout else "\nextra"
                    return result
                value.run.side_effect = run
                return value
            self.factory.side_effect = adapter
            self.assertEqual(controls.run_pair("/PUBLIC_CONTROL_LOGS"), 1)
            self.assertEqual(len(self.calls), 1)
            self.assertEqual(self.records[-1]["error"]["check"],
                             "run_not_successful" if timeout else "child_output_line_count")

    def test_capture_interruption_identity_and_partial_evidence_survive(self):
        original = KeyboardInterrupt()
        with patch.object(controls, "read_time", side_effect=original):
            with self.assertRaises(KeyboardInterrupt) as caught:
                controls.run_pair("/PUBLIC_CONTROL_LOGS")
        self.assertIs(caught.exception, original)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.records[-1]["capture_errors"][0]["field"], "gnu_time")
        self.assertIsNotNone(self.records[-1]["run"])


class PureChildAndSealTests(unittest.TestCase):
    def test_idle_protocol_with_mocked_clocks_and_sleep(self):
        sleep = Mock()
        value = work("idle", clock=iter([0, 500_000_000, 500_000_001, 1_000_000_001, 1_000_000_002, 1_500_000_002]).__next__,
                     cpu=iter([10, 10]).__next__, sleep=sleep)
        self.assertEqual(sleep.call_args_list, [unittest.mock.call(0.5)] * 3)
        self.assertEqual(value["cpu_seconds"], 0)

    def test_busy_deadline_without_running_work(self):
        value = work("busy", clock=iter([0, 500_000_000, 500_000_001, 2_500_000_001, 2_500_000_002,
                    2_500_000_003, 3_000_000_003]).__next__, cpu=iter([0, 0, 0]).__next__, sleep=Mock())
        self.assertTrue(value["deadline_reached_before_cpu_target"])

    def test_stable_seal_and_changed_metadata_are_discriminated(self):
        meta = SimpleNamespace(st_dev=1, st_ino=2, st_size=3, st_mtime_ns=4, st_ctime_ns=5)
        for changed in (False, True):
            source = io.BytesIO(b"abc")
            source.fileno = lambda: 99
            after = SimpleNamespace(**{**vars(meta), "st_ino": 3}) if changed else meta
            with patch.object(controls.Path, "open", return_value=source), patch.object(controls.os, "fstat", return_value=meta), \
                 patch.object(controls.os, "stat", return_value=after):
                if changed:
                    with self.assertRaisesRegex(controls.ControlFailure, "file_changed_while_sealing"):
                        controls.stable_file("/PUBLIC_FIXTURE")
                else:
                    self.assertEqual(controls.stable_file("/PUBLIC_FIXTURE")["sha256"],
                                     "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


if __name__ == "__main__":
    unittest.main()
