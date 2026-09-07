"""Mocked launch/clock/signals/files only. No subprocess or host workload runs."""

from contextlib import ExitStack
import errno
import itertools
import json
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, call, mock_open, patch

from partner_tools.vharness import vlib
from .launch import LaunchObservation, join_discoveries
from .test_owned_process import Graph, SEALED


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.process = Mock(pid=12345, returncode=None, stdin=None)
        self.process.stdout, self.process.stderr = Mock(), Mock()
        self.process.communicate.side_effect = self.success
        self.process.wait.side_effect = self.reap
        self.popen = self.stack.enter_context(patch.object(vlib.subprocess, "Popen", return_value=self.process))
        self.clock = self.stack.enter_context(patch.object(vlib.time, "monotonic", side_effect=[10.0, 12.0]))
        self.sleep = self.stack.enter_context(patch.object(vlib.time, "sleep"))
        self.waitid = self.stack.enter_context(patch.object(vlib.os, "waitid", return_value=None))
        self.getpgid = self.stack.enter_context(patch.object(vlib.os, "getpgid", return_value=12345))
        self.killpg = self.stack.enter_context(patch.object(vlib.os, "killpg"))

    def success(self, timeout):
        self.process.returncode = 0
        return b"out\xff", b"err\xff"

    def reap(self, timeout):
        self.process.returncode = -9
        return -9

    def test_default_command_environment_wall_and_output_unchanged(self):
        cmd, env = ["program", "argument"], {"ONLY": "value"}
        value = vlib.run_cmd(cmd, cwd="declared-cwd", env=env, mask="4", timeout=17)
        self.popen.assert_called_once_with(["taskset", "-c", "4"] + cmd,
            cwd="declared-cwd", env=env, stdout=vlib.subprocess.PIPE,
            stderr=vlib.subprocess.PIPE, start_new_session=True)
        self.process.communicate.assert_called_once_with(timeout=17)
        self.assertEqual((value.wall, value.rc, value.timed_out), (2.0, 0, False))
        self.assertEqual((value.stdout, value.stderr, value.stderr_bytes), ("out\ufffd", "err\ufffd", 4))
        self.assertEqual(cmd, ["program", "argument"])
        self.assertIsNone(value.peak_rss_kb)
        self.waitid.assert_not_called()
        self.killpg.assert_not_called()

    def test_notification_is_between_popen_and_communicate_inside_clock(self):
        order = []
        ticks = iter([10.0, 12.0])
        self.clock.side_effect = lambda: (order.append("clock"), next(ticks))[1]
        self.popen.side_effect = lambda *args, **kwargs: (order.append("popen"), self.process)[1]
        self.process.communicate.side_effect = lambda **kwargs: (order.append("communicate"), self.success(1))[1]
        notified = []
        def notification(process):
            order.append("notification")
            notified.append(process)
        value = vlib.run_cmd(["program"], mask=None, on_spawn=notification)
        self.assertEqual(order, ["clock", "popen", "notification", "communicate", "clock"])
        self.assertEqual(notified, [self.process])
        self.assertEqual(value.cmd, ["program"])

    def test_nonzero_result_is_not_an_exception_cleanup(self):
        self.process.returncode = 7
        self.process.communicate.side_effect = None
        self.process.communicate.return_value = (b"", b"failure")
        value = vlib.run_cmd(["program"])
        self.assertEqual(value.rc, 7)
        self.assertFalse(value.ok)
        self.killpg.assert_not_called()

    def test_popen_failure_preserves_exception_without_notification_or_signals(self):
        original = OSError(errno.ENOENT, "missing")
        self.popen.side_effect = original
        hook = Mock()
        with self.assertRaises(OSError) as caught:
            vlib.run_cmd(["program"], on_spawn=hook)
        self.assertIs(caught.exception, original)
        hook.assert_not_called()
        self.killpg.assert_not_called()

    def test_rss_wrapping_parsing_and_old_cleanup_unchanged(self):
        with patch.object(vlib.os.path, "isfile", return_value=True), \
             patch.object(vlib.os, "makedirs") as mkdir, \
             patch.object(vlib.os, "remove") as remove, \
             patch("builtins.open", mock_open(read_data="Maximum resident set size (kbytes): 42\n")):
            value = vlib.run_cmd(["program"], mask="4", rss=True)
        args = self.popen.call_args.args[0]
        self.assertEqual(args[:6], ["taskset", "-c", "4", "/usr/bin/time", "-v", "-o"])
        self.assertEqual(args[-1], "program")
        self.assertEqual(value.peak_rss_kb, 42)
        mkdir.assert_called_once()
        remove.assert_called_once_with(args[6])

    def test_missing_time_keeps_rss_unknown(self):
        with patch.object(vlib.os.path, "isfile", return_value=False):
            value = vlib.run_cmd(["program"], mask=None, rss=True)
        self.assertEqual(value.cmd, ["program"])
        self.assertIsNone(value.peak_rss_kb)

    def test_historical_timeout_signal_and_drain_path_unchanged(self):
        self.process.communicate.side_effect = [vlib.subprocess.TimeoutExpired("test", 5),
                                                (b"partial", b"diagnostic")]
        value = vlib.run_cmd(["program"], timeout=5)
        self.assertEqual(self.killpg.call_args_list, [call(12345, 15), call(12345, 9)])
        self.assertEqual(self.process.communicate.call_args_list, [call(timeout=5), call(timeout=30)])
        self.sleep.assert_called_once_with(2)
        self.waitid.assert_not_called()  # deliberate preservation, not the new exception path
        self.assertEqual((value.rc, value.timed_out, value.stdout), (124, True, "partial"))

    def test_second_historical_timeout_preserves_empty_outputs(self):
        self.process.communicate.side_effect = [vlib.subprocess.TimeoutExpired("test", 5),
                                                vlib.subprocess.TimeoutExpired("test", 30)]
        value = vlib.run_cmd(["program"], timeout=5)
        self.assertEqual((value.rc, value.timed_out, value.stdout, value.stderr), (124, True, "", ""))
        self.waitid.assert_not_called()

    def test_unexpected_communicate_error_cleans_owned_group_and_reraises(self):
        original = RuntimeError("original")
        self.process.communicate.side_effect = original
        with self.assertRaises(RuntimeError) as caught:
            vlib.run_cmd(["program"])
        self.assertIs(caught.exception, original)
        self.assertEqual(self.killpg.call_args_list, [call(12345, 15), call(12345, 9)])
        flags = vlib.os.WEXITED | vlib.os.WNOHANG | vlib.os.WNOWAIT
        self.assertEqual(self.waitid.call_args_list, [call(vlib.os.P_PID, 12345, flags)] * 2)
        self.process.wait.assert_called_once_with(timeout=30)
        self.assertTrue(original.cgm_run_cmd_cleanup["reaped"])
        self.process.stdout.close.assert_called_once()
        self.process.stderr.close.assert_called_once()

    def test_keyboard_interrupt_keeps_original_identity(self):
        original = KeyboardInterrupt()
        self.process.communicate.side_effect = original
        with self.assertRaises(KeyboardInterrupt) as caught:
            vlib.run_cmd(["program"])
        self.assertIs(caught.exception, original)
        self.assertTrue(original.cgm_run_cmd_cleanup["reaped"])

    def test_arbitrary_callback_failure_is_explicit_and_communicate_never_runs(self):
        original = ValueError("hook failure")
        with self.assertRaises(ValueError) as caught:
            vlib.run_cmd(["program"], on_spawn=Mock(side_effect=original))
        self.assertIs(caught.exception, original)
        self.process.communicate.assert_not_called()
        self.assertTrue(original.cgm_run_cmd_cleanup["reaped"])

    def test_reaped_child_never_signals_reusable_pid_or_group(self):
        self.process.returncode = 0
        original = RuntimeError("after child reaped")
        self.process.communicate.side_effect = original
        with self.assertRaises(RuntimeError):
            vlib.run_cmd(["program"])
        self.waitid.assert_not_called()
        self.getpgid.assert_not_called()
        self.killpg.assert_not_called()
        self.assertEqual(original.cgm_run_cmd_cleanup["term_action"], "already_reaped_no_signal")

    def test_lost_child_ownership_refuses_signals_and_reports_reap_failure(self):
        original = RuntimeError("original")
        self.process.communicate.side_effect = original
        self.waitid.side_effect = ChildProcessError(errno.ECHILD, "lost")
        self.process.wait.side_effect = ChildProcessError(errno.ECHILD, "lost")
        with self.assertRaises(RuntimeError) as caught:
            vlib.run_cmd(["program"])
        self.assertIs(caught.exception, original)
        self.killpg.assert_not_called()
        self.getpgid.assert_not_called()
        self.assertFalse(original.cgm_run_cmd_cleanup["reaped"])

    def test_changed_group_refuses_signals(self):
        original = RuntimeError("original")
        self.process.communicate.side_effect = original
        self.getpgid.return_value = 777
        with self.assertRaises(RuntimeError):
            vlib.run_cmd(["program"])
        self.killpg.assert_not_called()
        self.assertEqual(original.cgm_run_cmd_cleanup["ownership_refusal"], "process_group_identity_mismatch")

    def test_cleanup_failure_never_masks_original(self):
        original = RuntimeError("original")
        self.process.communicate.side_effect = original
        self.killpg.side_effect = PermissionError(errno.EPERM, "private text")
        self.process.wait.side_effect = vlib.subprocess.TimeoutExpired("not retained", 30)
        with self.assertRaises(RuntimeError) as caught:
            vlib.run_cmd(["program"])
        self.assertIs(caught.exception, original)
        report = original.cgm_run_cmd_cleanup
        self.assertFalse(report["reaped"])
        self.assertNotIn("private text", json.dumps(report))
        self.assertEqual(sum(s["status"] == "UNKNOWN" for s in report["stages"]), 3)

    def test_unreportable_exception_and_broken_stderr_still_do_not_mask(self):
        class ExoticError(Exception):
            def __setattr__(self, name, value):
                if name == "cgm_run_cmd_cleanup":
                    raise RuntimeError("attribute blocked")
                super().__setattr__(name, value)
            def add_note(self, note):
                raise RuntimeError("note blocked")
        original = ExoticError()
        self.process.communicate.side_effect = original
        with patch.object(vlib.sys, "stderr", Mock(write=Mock(side_effect=OSError("closed")))):
            with self.assertRaises(ExoticError) as caught:
                vlib.run_cmd(["program"])
        self.assertIs(caught.exception, original)


class FakeObserver:
    def __init__(self, **kwargs):
        self.reader = kwargs["reader"]
        self.running = False
        self.events = []
    def start(self):
        self.running = True
        self.events.append(self.reader.enumerate_pids())
    def stop(self):
        self.running = False
        return {"events": self.events, "pid_scope": self.reader.pid_scope}


class AdapterTests(unittest.TestCase):
    def make(self, **kwargs):
        graph = Graph()
        self.graph = graph
        self.adapter = LaunchObservation(SEALED, reader=graph, finder=graph.finder(),
            observer_factory=kwargs.pop("observer_factory", FakeObserver),
            runner=kwargs.pop("runner", self.runner), clock=itertools.count(100).__next__,
            cpu_clock=itertools.count(10).__next__, **kwargs)
        return self.adapter

    def runner(self, cmd, **kwargs):
        self.called_cmd, self.called_kwargs = cmd, kwargs
        self.assertEqual(self.adapter._observer.events, [[self.adapter._owner_pid]])
        kwargs["on_spawn"](SimpleNamespace(pid=100))
        self.assertFalse(any("children" in path for path in self.graph.reads))
        self.targets = self.adapter._observer.reader.enumerate_pids()
        return self.expected

    def setUp(self):
        self.expected = vlib.Run(["unchanged"], 7, 0.2, "actual output", "actual error", 12)

    def test_real_run_object_and_inputs_unchanged_with_separate_evidence(self):
        adapter = self.make()
        cmd, env = ["NOT_RETAINED_ARGV"], {"private": "NOT_RETAINED_ENV"}
        value = adapter.run(cmd, env=env, mask="4", timeout=180, rss=False)
        self.assertIs(value, self.expected)
        self.assertIs(self.called_cmd, cmd)
        self.assertIs(self.called_kwargs["env"], env)
        self.assertEqual(self.targets, sorted([adapter._owner_pid, 100, 200]))
        record = adapter.evidence
        self.assertTrue(record["observer_joined"])
        self.assertEqual(record["observation"]["pid_scope"], "custom_enumerator")
        self.assertEqual(record["discoveries"][-1]["target"], {"pid": 200, "start_ticks": 20})
        self.assertIsNone(record["compiler_cpu_summary"])
        self.assertNotIn("NOT_RETAINED", json.dumps(record))
        self.assertNotIn("actual output", json.dumps(record))
        self.assertLessEqual(record["begin_ns"], record["run_call_begin_ns"])
        self.assertLessEqual(record["run_call_begin_ns"], record["notification"]["begin_ns"])
        self.assertLessEqual(record["notification"]["end_ns"], record["run_return_or_raise_ns"])
        self.assertLessEqual(record["run_return_or_raise_ns"], record["end_ns"])

    def test_missing_wrapper_identity_keeps_actual_run_and_unknown(self):
        adapter = self.make()
        adapter.finder.capture = Mock(side_effect=FileNotFoundError(errno.ENOENT, "NOT_RETAINED"))
        self.assertIs(adapter.run(["program"]), self.expected)
        self.assertEqual(self.targets, [adapter._owner_pid])
        self.assertIsNone(adapter.evidence["notification"]["wrapper_identity"])
        self.assertEqual(adapter.evidence["errors"][0]["stage"], "launch_identity")

    def test_discovery_error_stays_in_side_channel(self):
        adapter = self.make()
        adapter.finder.discover = Mock(side_effect=RuntimeError("NOT_RETAINED"))
        self.assertIs(adapter.run(["program"]), self.expected)
        self.assertEqual(adapter.evidence["errors"][0]["stage"], "target_discovery")
        self.assertEqual(self.targets, [adapter._owner_pid])

    def test_wrapper_only_never_becomes_compiler_cpu(self):
        adapter = self.make()
        self.graph.files["100/task/100/children"] = ""
        adapter.run(["program"])
        self.assertEqual(self.targets, sorted([adapter._owner_pid, 100]))
        self.assertIsNone(adapter.evidence["discoveries"][0]["target"])
        self.assertIsNone(adapter.evidence["compiler_cpu_summary"])

    def test_launch_exception_retained_and_observer_joined(self):
        original = OSError(errno.ENOENT, "original")
        adapter = self.make(runner=Mock(side_effect=original))
        with self.assertRaises(OSError) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)
        self.assertTrue(adapter.evidence["observer_joined"])
        self.assertIsNone(adapter.evidence["notification"])
        self.assertLessEqual(adapter.evidence["run_call_begin_ns"], adapter.evidence["run_return_or_raise_ns"])

    def test_interruption_and_cleanup_receipt_retained(self):
        original = KeyboardInterrupt()
        original.cgm_run_cmd_cleanup = {"pid": 100, "reaped": True}
        adapter = self.make(runner=Mock(side_effect=original))
        with self.assertRaises(KeyboardInterrupt) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)
        self.assertEqual(adapter.evidence["run_exception"]["owned_cleanup"], original.cgm_run_cmd_cleanup)
        self.assertTrue(adapter.evidence["observer_joined"])

    def test_start_failure_does_not_replace_actual_run(self):
        def runner(cmd, **kwargs):
            kwargs["on_spawn"](SimpleNamespace(pid=100))
            return self.expected
        adapter = self.make(observer_factory=Mock(side_effect=RuntimeError("unavailable")), runner=runner)
        self.assertIs(adapter.run(["program"]), self.expected)
        self.assertEqual(adapter.evidence["errors"][0]["stage"], "observer_start")
        self.assertIsNone(adapter.evidence["observation"])

    def test_stop_failure_does_not_mask_run_exception(self):
        class StopError(FakeObserver):
            def stop(self):
                self.running = False
                raise RuntimeError("instrument stop error")
        original = ValueError("original")
        adapter = self.make(observer_factory=StopError, runner=Mock(side_effect=original))
        with self.assertRaises(ValueError) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)
        self.assertTrue(adapter.evidence["observer_joined"])
        self.assertEqual(adapter.evidence["errors"][-1]["stage"], "observer_stop")

    def test_timeout_run_is_not_replaced_by_observation(self):
        self.expected = vlib.Run(["unchanged"], 124, 0.2, "", "", 0, True)
        adapter = self.make()
        self.assertIs(adapter.run(["program"]), self.expected)
        self.assertTrue(adapter.evidence["observer_joined"])

    def test_stop_keyboard_interrupt_after_success_is_not_swallowed(self):
        original = KeyboardInterrupt()
        class InterruptedStop(FakeObserver):
            def stop(self):
                self.running = False
                raise original
        adapter = self.make(observer_factory=InterruptedStop)
        with self.assertRaises(KeyboardInterrupt) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)
        self.assertTrue(adapter.evidence["observer_joined"])

    def test_stop_system_exit_after_success_is_not_swallowed(self):
        original = SystemExit(12)
        class InterruptedStop(FakeObserver):
            def stop(self):
                self.running = False
                raise original
        adapter = self.make(observer_factory=InterruptedStop)
        with self.assertRaises(SystemExit) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)

    def test_pending_run_exception_has_priority_over_stop_interrupt(self):
        original = ValueError("run failure")
        class InterruptedStop(FakeObserver):
            def stop(self):
                self.running = False
                raise KeyboardInterrupt()
        adapter = self.make(observer_factory=InterruptedStop, runner=Mock(side_effect=original))
        with self.assertRaises(ValueError) as caught:
            adapter.run(["program"])
        self.assertIs(caught.exception, original)
        self.assertEqual(adapter.evidence["errors"][-1]["kind"], "KeyboardInterrupt")

    def test_one_use_and_notification_ownership_are_explicit(self):
        adapter = self.make()
        with self.assertRaises(ValueError):
            adapter.run(["program"], on_spawn=lambda p: None)
        adapter.run(["program"])
        with self.assertRaises(RuntimeError):
            adapter.run(["program"])


class IdentityJoinTests(unittest.TestCase):
    def fixture(self, count=2):
        calls, samples = [], []
        for index in range(count):
            base = index * 100
            target = {"pid": 200, "start_ticks": 20}
            wrapper = {"pid": 100, "start_ticks": 10}
            for offset in (10, 70):
                calls.append({"call_index": len(calls), "enumeration_begin_ns": base + offset,
                    "enumeration_end_ns": base + offset + 10, "target": dict(target),
                    "wrapper": dict(wrapper), "wrapper_valid": True, "relation": "direct_child",
                    "status": "matched_direct_child", "errors": []})
            samples.append({"sequence": index, "snapshot": {
                "begin_ns": base, "end_ns": base + 90, "errors": [], "processes": [
                    {**wrapper, "read_start_ns": base + 25, "read_end_ns": base + 30,
                     "utime_ticks": 1000 + index * 100, "stime_ticks": 1000, "role": "other"},
                    {**target, "read_start_ns": base + 35, "read_end_ns": base + 55,
                     "utime_ticks": 3 + index * 10, "stime_ticks": 2 + index * 3, "role": "other"}]}})
        return calls, {"samples": samples}

    def test_bracketed_identity_matches_only_target_rows_and_keeps_raw_roles(self):
        calls, observation = self.fixture()
        value = join_discoveries(calls, observation)
        self.assertEqual([row["status"] for row in value["samples"]],
                         ["matched_target_at_snapshot_probes"] * 2)
        self.assertEqual(value["intervals"][0]["endpoint_cpu_delta_ticks"],
                         {"utime_ticks": 10, "stime_ticks": 3})
        self.assertEqual([row["raw_role"] for row in value["samples"]], ["other", "other"])
        self.assertEqual(observation["samples"][0]["snapshot"]["processes"][1]["role"], "other")
        self.assertEqual(value["intervals"][0]["between_probes"], "UNKNOWN")

    def test_wrapper_only_negative_control_cannot_supply_target_counters(self):
        calls, observation = self.fixture()
        observation["samples"][0]["snapshot"]["processes"].pop()
        value = join_discoveries(calls, observation)
        self.assertIsNone(value["samples"][0]["cpu_counters"])
        self.assertIsNone(value["intervals"][0]["endpoint_cpu_delta_ticks"])

    def test_pid_reuse_between_discovery_and_row_is_unknown(self):
        calls, observation = self.fixture()
        observation["samples"][0]["snapshot"]["processes"][1]["start_ticks"] = 99
        value = join_discoveries(calls, observation)
        self.assertEqual(value["samples"][0]["status"], "target_row_missing_or_identity_changed")
        self.assertIsNone(value["intervals"][0]["endpoint_cpu_delta_ticks"])

    def test_independently_changing_before_after_discoveries_never_merge(self):
        calls, observation = self.fixture()
        calls[1]["target"] = {"pid": 201, "start_ticks": 21}
        value = join_discoveries(calls, observation)
        self.assertEqual((value["samples"][0]["before_call"], value["samples"][0]["after_call"]), (0, 1))
        self.assertIsNone(value["samples"][0]["target"])
        self.assertEqual(calls[1]["target"]["pid"], 201)

    def test_unbracketed_row_is_unknown(self):
        calls, observation = self.fixture()
        observation["samples"][0]["snapshot"]["processes"][1]["read_end_ns"] = 75
        value = join_discoveries(calls, observation)
        self.assertEqual(value["samples"][0]["status"], "target_read_not_bracketed")
        self.assertIsNone(value["samples"][0]["target"])

    def test_missing_enumeration_call_is_not_reconstructed(self):
        calls, observation = self.fixture()
        del calls[1]
        value = join_discoveries(calls, observation)
        self.assertEqual(value["samples"][0]["status"], "enumeration_window_unknown")
        self.assertIsNone(value["intervals"][0]["endpoint_cpu_delta_ticks"])

    def test_bad_status_and_errors_never_imply_executable_match(self):
        calls, observation = self.fixture()
        calls[0]["status"] = "no_target_observed"
        calls[3]["errors"] = [{"kind": "PermissionError"}]
        value = join_discoveries(calls, observation)
        self.assertTrue(all(row["target"] is None for row in value["samples"]))

    def test_missing_snapshot_does_not_bridge_cpu_interval(self):
        calls, observation = self.fixture(count=3)
        observation["samples"][1]["snapshot"] = None
        value = join_discoveries(calls, observation)
        self.assertEqual(value["unassigned_calls"], [2, 3])
        self.assertTrue(all(row["endpoint_cpu_delta_ticks"] is None for row in value["intervals"]))

    def test_bad_clock_order_and_counter_regression_are_unknown(self):
        calls, observation = self.fixture()
        calls[1]["enumeration_begin_ns"] = 15
        self.assertEqual(join_discoveries(calls, observation)["status"], "enumeration_clock_order_unknown")
        calls, observation = self.fixture()
        observation["samples"][1]["snapshot"]["processes"][1]["utime_ticks"] = 1
        self.assertIsNone(join_discoveries(calls, observation)["intervals"][0]["endpoint_cpu_delta_ticks"])


if __name__ == "__main__":
    unittest.main()
