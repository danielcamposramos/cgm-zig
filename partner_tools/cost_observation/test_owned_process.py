"""Only in-memory process graphs and numeric executable metadata; no host reads."""

import errno
import itertools
import json
from pathlib import Path
from types import SimpleNamespace
import unittest

from .owned_process import OwnedProcess, file_identity, parse_children, validate_file_identity
from .procfs import identity, parse_process
from .test_observe import process_text

SEALED = {"dev": 1, "ino": 20, "size": 1000, "mtime_ns": 30, "ctime_ns": 40}
OTHER = dict(SEALED, ino=21)
WRAPPER = {"pid": 100, "start_ticks": 10}
TARGET = {"pid": 200, "start_ticks": 20}


class Graph:
    root = Path("/proc")

    def __init__(self, files=None, executable=None):
        self.files = {"100/stat": process_text(100, 10),
                      "100/task/100/children": "200",
                      "200/stat": process_text(200, 20, parent=100)}
        self.files.update(files or {})
        self.executables = {100: OTHER, 200: SEALED}
        self.executables.update(executable or {})
        self.reads = []
        self.clock = itertools.count(1).__next__
        self.affinity = lambda pid: {4}

    def read(self, path):
        self.reads.append(path)
        value = self.files.get(path, FileNotFoundError(errno.ENOENT, "NOT_RETAINED"))
        if callable(value):
            value = value()
        if isinstance(value, BaseException):
            raise value
        return value

    def process_identity(self, pid):
        return identity(parse_process(self.read(f"{pid}/stat")))

    def stat(self, pid):
        self.reads.append(f"{pid}/exe")
        value = self.executables.get(pid, FileNotFoundError(errno.ENOENT, "NOT_RETAINED"))
        if callable(value):
            value = value()
        if isinstance(value, BaseException):
            raise value
        return SimpleNamespace(**{"st_" + key: data for key, data in value.items()})

    def finder(self, **kwargs):
        return OwnedProcess(self, executable_stat=self.stat, clock=self.clock, **kwargs)


class OwnedDiscoveryTests(unittest.TestCase):
    def test_capture_is_only_one_stat_not_discovery(self):
        graph = Graph()
        self.assertEqual(graph.finder().capture(100), WRAPPER)
        self.assertEqual(graph.reads, ["100/stat"])

    def test_wrapper_is_not_target_and_direct_child_matches_seal(self):
        value = Graph().finder().discover(WRAPPER, SEALED)
        self.assertEqual(value["target"], TARGET)
        self.assertEqual(value["relation"], "direct_child")
        self.assertFalse(value["candidates"][0]["executable_matches_seal"])
        self.assertEqual(value["errors"], [])

    def test_wrapper_only_negative_control_has_no_target(self):
        graph = Graph({"100/task/100/children": ""})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertEqual(value["status"], "no_target_observed")
        self.assertIsNone(value["target"])

    def test_exec_in_launched_pid_matches_without_child_scan(self):
        graph = Graph(executable={100: SEALED})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertEqual(value["target"], WRAPPER)
        self.assertEqual(value["relation"], "launched_process")
        self.assertFalse(any("children" in path for path in graph.reads))

    def test_wrapper_pid_reuse_refuses_before_executable_lookup(self):
        graph = Graph({"100/stat": process_text(100, 99)})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertFalse(value["wrapper_valid"])
        self.assertIsNone(value["target"])
        self.assertNotIn("100/exe", graph.reads)

    def test_child_pid_reuse_during_read_refuses(self):
        texts = iter([process_text(200, 20, parent=100), process_text(200, 99, parent=100)])
        graph = Graph({"200/stat": lambda: next(texts)})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertIsNone(value["target"])
        self.assertEqual(value["errors"][0]["stage"], "direct_child")

    def test_disappearing_child_and_permission_failure_are_unknown(self):
        for failure in (FileNotFoundError(errno.ENOENT, "NOT_RETAINED"),
                        PermissionError(errno.EACCES, "NOT_RETAINED")):
            value = Graph(executable={200: failure}).finder().discover(WRAPPER, SEALED)
            self.assertEqual(value["status"], "incomplete_discovery")
            self.assertIsNone(value["target"])
            self.assertEqual(value["errors"][0]["errno"], failure.errno)
            self.assertNotIn("NOT_RETAINED", json.dumps(value))

    def test_fast_exit_has_no_fabricated_wrapper(self):
        value = Graph({"100/stat": FileNotFoundError(errno.ENOENT, "gone")}).finder().discover(
            WRAPPER, SEALED)
        self.assertFalse(value["wrapper_valid"])
        self.assertIsNone(value["target"])

    def test_two_matching_siblings_are_ambiguous(self):
        graph = Graph({"100/task/100/children": "200 201",
                       "201/stat": process_text(201, 21, parent=100)}, {201: SEALED})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertEqual(value["status"], "ambiguous_matches")
        self.assertIsNone(value["target"])

    def test_unknown_sibling_does_not_allow_apparent_unique_match(self):
        graph = Graph({"100/task/100/children": "200 201"})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertEqual(value["status"], "incomplete_discovery")
        self.assertIsNone(value["target"])

    def test_grandchild_excluded_not_recursively_discovered(self):
        graph = Graph({"200/task/200/children": "300",
                       "300/stat": process_text(300, 30, parent=200)}, {200: OTHER, 300: SEALED})
        value = graph.finder().discover(WRAPPER, SEALED)
        self.assertIsNone(value["target"])
        self.assertEqual(value["grandchildren_and_other_thread_children"], "UNKNOWN")
        self.assertFalse(any(path.startswith("300/") or path == "200/task/200/children"
                             for path in graph.reads))

    def test_child_bound_and_bad_numeric_fields_refuse(self):
        graph = Graph({"100/task/100/children": "200 201"})
        value = graph.finder(max_children=1).discover(WRAPPER, SEALED)
        self.assertIsNone(value["target"])
        self.assertNotIn("200/stat", graph.reads)
        for text in ("0", "-1", "200 200", "name"):
            with self.assertRaises(ValueError):
                parse_children(text, 4)

    def test_wrong_parent_and_changing_executable_refuse(self):
        value = Graph({"200/stat": process_text(200, 20, parent=999)}).finder().discover(WRAPPER, SEALED)
        self.assertIsNone(value["target"])
        changes = iter([SEALED, OTHER])
        value = Graph(executable={200: lambda: next(changes)}).finder().discover(WRAPPER, SEALED)
        self.assertIsNone(value["target"])

    def test_wrapper_change_after_child_discovery_refuses(self):
        values = iter([process_text(100, 10), process_text(100, 10), process_text(100, 99)])
        value = Graph({"100/stat": lambda: next(values)}).finder().discover(WRAPPER, SEALED)
        self.assertFalse(value["wrapper_valid"])
        self.assertIsNone(value["target"])

    def test_executable_seal_is_numeric_exact_and_copied(self):
        original = dict(SEALED)
        copied = validate_file_identity(original)
        original["ino"] += 1
        self.assertEqual(copied, SEALED)
        self.assertEqual(file_identity(Graph().stat(200)), SEALED)
        for bad in ({}, dict(SEALED, path="NOT_RETAINED"), dict(SEALED, ino=True),
                    dict(SEALED, size=-1)):
            with self.assertRaises(ValueError):
                validate_file_identity(bad)


if __name__ == "__main__":
    unittest.main()
