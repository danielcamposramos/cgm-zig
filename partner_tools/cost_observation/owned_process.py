"""Bounded numeric discovery under one captured, caller-owned launch identity.

No census, command-line/name matching, recursive scan or signaling. This reads
only the launch PID and its main thread's direct children. It cannot discover
grandchildren or children spawned by another thread; those remain UNKNOWN.
"""

import os
import time

from .procfs import Procfs, identity, parse_process

FILE_FIELDS = ("dev", "ino", "size", "mtime_ns", "ctime_ns")


def file_identity(value):
    return {key: getattr(value, "st_" + key) for key in FILE_FIELDS}


def validate_file_identity(value):
    if not isinstance(value, dict) or set(value) != set(FILE_FIELDS):
        raise ValueError("sealed_file_identity_fields")
    if any(isinstance(x, bool) or not isinstance(x, int) for x in value.values()):
        raise ValueError("sealed_file_identity_numeric")
    if any(value[key] < 0 for key in ("dev", "ino", "size")):
        raise ValueError("sealed_file_identity_negative")
    return dict(value)


def parse_children(text, limit):
    fields = text.split()
    if len(fields) > limit:
        raise ValueError("direct_child_limit")
    values = [int(field) for field in fields]
    if any(pid <= 0 for pid in values) or len(set(values)) != len(values):
        raise ValueError("direct_child_identity_shape")
    return sorted(values)


def validate_process_identity(value):
    if not isinstance(value, dict) or set(value) != {"pid", "start_ticks"} or any(
            isinstance(x, bool) or not isinstance(x, int) for x in value.values()):
        raise ValueError("process_identity_numeric_fields")
    if value["pid"] <= 0 or value["start_ticks"] < 0:
        raise ValueError("process_identity_range")
    return dict(value)


class OwnedProcess:
    def __init__(self, reader=None, executable_stat=None, max_children=4,
                 clock=time.monotonic_ns):
        if isinstance(max_children, bool) or not isinstance(max_children, int) or max_children < 1:
            raise ValueError("max_children_must_be_positive_integer")
        self.reader = reader or Procfs()
        self.executable_stat = executable_stat or (
            lambda pid: os.stat(self.reader.root / f"{pid}/exe"))
        self.max_children = max_children
        self.clock = clock

    def capture(self, pid):
        """One stat read, suitable for the post-Popen notification; no discovery."""
        validate_process_identity({"pid": pid, "start_ticks": 0})
        value = validate_process_identity(self.reader.process_identity(pid))
        if value["pid"] != pid:
            raise ValueError("captured_pid_mismatch")
        return value

    def _process(self, pid):
        value = parse_process(self.reader.read(f"{pid}/stat"))
        if value["pid"] != pid:
            raise ValueError("process_pid_mismatch")
        return value

    def _candidate(self, pid, sealed, expected=None, parent=None):
        before = self._process(pid)
        if expected is not None and identity(before) != expected:
            raise ValueError("captured_identity_changed")
        if parent is not None and (before["ppid"] != parent["pid"] or
                                   before["start_ticks"] < parent["start_ticks"]):
            raise ValueError("direct_parent_identity_mismatch")
        executable = file_identity(self.executable_stat(pid))
        again = file_identity(self.executable_stat(pid))
        after = self._process(pid)
        if identity(before) != identity(after) or before["ppid"] != after["ppid"]:
            raise ValueError("candidate_changed_during_read")
        if executable != again:
            raise ValueError("executable_changed_during_read")
        return {"identity": identity(after), "executable": executable,
                "executable_matches_seal": executable == sealed}

    def discover(self, wrapper, sealed):
        sealed = validate_file_identity(sealed)
        wrapper = validate_process_identity(wrapper)
        result = {"begin_ns": self.clock(), "wrapper": dict(wrapper),
                  "wrapper_valid": False, "target": None, "relation": None,
                  "status": "UNKNOWN", "candidates": [], "errors": [],
                  "direct_children": None, "max_children": self.max_children,
                  "grandchildren_and_other_thread_children": "UNKNOWN"}
        stage, pid = "wrapper", wrapper["pid"]
        try:
            root = self._candidate(pid, sealed, expected=wrapper)
            result["wrapper_valid"] = True
            result["candidates"].append(root)
            if root["executable_matches_seal"]:
                result.update(target=dict(wrapper), relation="launched_process",
                              status="matched_launched_process")
            else:
                stage = "direct_children"
                children = parse_children(self.reader.read(f"{pid}/task/{pid}/children"),
                                          self.max_children)
                result["direct_children"] = children
                for child in children:
                    stage, pid = "direct_child", child
                    result["candidates"].append(self._candidate(child, sealed, parent=wrapper))
                stage, pid = "wrapper_recheck", wrapper["pid"]
                if identity(self._process(pid)) != wrapper:
                    result["wrapper_valid"] = False
                    raise ValueError("wrapper_changed_during_discovery")
                matching = [p for p in result["candidates"][1:] if p["executable_matches_seal"]]
                if len(matching) == 1:
                    result.update(target=matching[0]["identity"], relation="direct_child",
                                  status="matched_direct_child")
                else:
                    result["status"] = "ambiguous_matches" if matching else "no_target_observed"
        except (OSError, ValueError, TypeError, IndexError) as error:
            result["errors"].append({"stage": stage, "pid": pid, "kind": type(error).__name__,
                                     "errno": getattr(error, "errno", None)})
            result["status"] = "incomplete_discovery"
            result["target"] = None
            result["relation"] = None
        result["end_ns"] = self.clock()
        return result
