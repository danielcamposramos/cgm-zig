"""Bounded procfs reads and pure numeric parsers. Never retain process names.

An absent counter is None, not zero. Reads are successive observations, not an
atomic system snapshot. Process stat is bracketed around the other PID reads
so detected PID reuse cannot silently attach old I/O/affinity to a new process.
"""

import math
import os
import time
from pathlib import Path

CPU_FIELDS = ("user", "nice", "system", "idle", "iowait", "irq", "softirq",
              "steal", "guest", "guest_nice")
VM_FIELDS = ("pgpgin", "pgpgout", "pswpin", "pswpout", "pgfault", "pgmajfault")
IO_FIELDS = ("rchar", "wchar", "syscr", "syscw", "read_bytes", "write_bytes",
             "cancelled_write_bytes")


def natural(text):
    value = int(text)
    if value < 0:
        raise ValueError("negative_counter")
    return value


def parse_process(text):
    # comm may contain spaces and ')'. It is discarded, never returned/logged.
    left, right = text.find("("), text.rfind(")")
    if left < 1 or right <= left:
        raise ValueError("process_stat_shape")
    pid = natural(text[:left].strip())
    fields = text[right + 1:].split()
    if len(fields) < 37 or len(fields[0]) != 1:
        raise ValueError("process_stat_truncated")
    return {"pid": pid, "ppid": natural(fields[1]),
            "utime_ticks": natural(fields[11]), "stime_ticks": natural(fields[12]),
            "threads": natural(fields[17]), "start_ticks": natural(fields[19]),
            "last_cpu": natural(fields[36])}


def parse_stat(text):
    cpus, system = {}, {}
    for line in text.splitlines():
        fields = line.split()
        if not fields:
            continue
        key = fields[0]
        if key == "cpu" or (key.startswith("cpu") and key[3:].isdigit()):
            if len(fields) < 5 or key in cpus:
                raise ValueError("cpu_stat_truncated_or_duplicate")
            values = [natural(x) for x in fields[1:]]
            cpus[key] = {name: values[i] if i < len(values) else None
                         for i, name in enumerate(CPU_FIELDS)}
        elif key in ("ctxt", "processes", "procs_running", "procs_blocked"):
            if len(fields) != 2 or key in system:
                raise ValueError("system_stat_shape")
            system[key] = natural(fields[1])
    if "cpu" not in cpus or not any(key != "cpu" for key in cpus):
        raise ValueError("cpu_observation_missing")
    return {"cpus": cpus, "system": {key: system.get(key) for key in
            ("ctxt", "processes", "procs_running", "procs_blocked")}}


def parse_load(text):
    fields = text.split()
    if len(fields) != 5:
        raise ValueError("load_shape")
    loads = [float(x) for x in fields[:3]]
    if any(not math.isfinite(x) or x < 0 for x in loads):
        raise ValueError("load_value")
    counts = fields[3].split("/")
    if len(counts) != 2:
        raise ValueError("load_counts")
    return {"load1": loads[0], "load5": loads[1], "load15": loads[2],
            "runnable": natural(counts[0]), "entities": natural(counts[1]),
            "last_pid": natural(fields[4])}


def parse_counters(text, wanted):
    found = {}
    for line in text.splitlines():
        fields = line.replace(":", " ").split()
        if fields and fields[0] in wanted:
            if len(fields) != 2 or fields[0] in found:
                raise ValueError("counter_shape")
            found[fields[0]] = natural(fields[1])
    if not found:
        raise ValueError("counters_missing")
    return {key: found.get(key) for key in wanted}


def parse_pressure(text):
    result = {"some": None, "full": None}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) != 5 or fields[0] not in result:
            raise ValueError("pressure_shape")
        if result[fields[0]] is not None:
            raise ValueError("pressure_duplicate")
        values = dict(item.split("=", 1) for item in fields[1:])
        if set(values) != {"avg10", "avg60", "avg300", "total"}:
            raise ValueError("pressure_fields")
        row = {key: (natural(value) if key == "total" else float(value))
               for key, value in values.items()}
        if any(not math.isfinite(value) or value < 0 for value in row.values()):
            raise ValueError("pressure_value")
        result[fields[0]] = row
    if result["some"] is None:
        raise ValueError("pressure_missing")
    return result


def identity(process):
    return {"pid": process["pid"], "start_ticks": process["start_ticks"]}


class Procfs:
    """Reader dependencies may be replaced with in-memory fixtures in tests."""

    def __init__(self, root="/proc", read=None, enumerate_pids=None, affinity=None,
                 clock=time.monotonic_ns, selected_pids=None):
        if selected_pids is not None:
            if enumerate_pids is not None:
                raise ValueError("selected_pids_and_custom_enumerator_are_ambiguous")
            if not isinstance(selected_pids, (list, tuple, set, frozenset)) or not selected_pids:
                raise ValueError("selected_pids_must_be_nonempty_collection")
            if any(isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0
                   for pid in selected_pids):
                raise ValueError("selected_pids_must_be_positive_integers")
            if len(set(selected_pids)) != len(selected_pids):
                raise ValueError("selected_pids_must_be_unique")
        self.selected_pids = tuple(sorted(selected_pids)) if selected_pids is not None else None
        self.pid_scope = ("selected_ids" if self.selected_pids is not None else
                          "custom_enumerator" if enumerate_pids is not None else "visible_procfs")
        self.root = Path(root)
        self.read = read or self._read
        # Reuse the enumeration seam as a request provider, not an existence test.
        self.enumerate_pids = ((lambda: list(self.selected_pids)) if self.selected_pids is not None
                               else enumerate_pids or self._enumerate)
        self.affinity = affinity or os.sched_getaffinity
        self.clock = clock
        self.clock_ticks_per_second = os.sysconf("SC_CLK_TCK")

    def _read(self, relative):
        with (self.root / relative).open("r", encoding="ascii", errors="replace") as f:
            text = f.read(1048577)
        if len(text) > 1048576:
            raise ValueError("read_limit")
        return text

    def _enumerate(self):
        with os.scandir(self.root) as entries:
            return sorted(int(entry.name) for entry in entries if entry.name.isdigit())

    def process_identity(self, pid):
        value = parse_process(self.read(f"{int(pid)}/stat"))
        if value["pid"] != pid:
            raise ValueError("pid_mismatch")
        return identity(value)

    def snapshot(self):
        start = self.clock()
        errors = []

        def attempt(source, operation, pid=None):
            try:
                return operation()
            except (OSError, ValueError, TypeError, IndexError) as error:
                # Exception strings can expose paths or process text. Never retain them.
                errors.append({"source": source, "pid": pid,
                               "kind": type(error).__name__,
                               "errno": getattr(error, "errno", None)})
                return None

        stat = attempt("stat", lambda: parse_stat(self.read("stat")))
        load = attempt("loadavg", lambda: parse_load(self.read("loadavg")))
        vm = attempt("vmstat", lambda: parse_counters(self.read("vmstat"), VM_FIELDS))
        pressure = {key: attempt("pressure_" + key,
                                lambda key=key: parse_pressure(self.read("pressure/" + key)))
                    for key in ("cpu", "io", "memory")}
        selected = self.selected_pids is not None
        targets = attempt("selected_requests" if selected else "enumeration_before", self.enumerate_pids)
        before = None if selected else targets
        processes = []
        for pid in targets if targets is not None else []:
            begin = self.clock()
            first = attempt("process_stat_before",
                            lambda: parse_process(self.read(f"{pid}/stat")), pid)
            if first is None:
                continue
            affinity = attempt("affinity", lambda: sorted(self.affinity(pid)), pid)
            io = attempt("process_io",
                         lambda: parse_counters(self.read(f"{pid}/io"), IO_FIELDS), pid)
            last = attempt("process_stat_after",
                           lambda: parse_process(self.read(f"{pid}/stat")), pid)
            if last is None:
                continue
            if first["pid"] != pid or last["pid"] != pid or identity(first) != identity(last):
                errors.append({"source": "process_identity", "pid": pid,
                               "kind": "identity_changed_during_read", "errno": None})
                continue
            processes.append({**last, "affinity": affinity, "io": io,
                              "read_start_ns": begin, "read_end_ns": self.clock()})
        after = None if selected else attempt("enumeration_after", self.enumerate_pids)
        return {"begin_ns": start, "end_ns": self.clock(), "stat": stat,
                "load": load, "vm": vm, "pressure": pressure,
                "pid_coverage": {"mode": self.pid_scope,
                    "requested_pids": list(self.selected_pids) if selected else None,
                    "attempted_pids": targets,
                    "attempted_count": len(targets) if targets is not None else None,
                    "captured_count": len(processes),
                    "unselected_process_activity": "UNKNOWN",
                    "unselected_descendants": "UNKNOWN"},
                "pids_before": before, "pids_after": after,
                "appeared_during_scan": None if before is None or after is None else
                    sorted(set(after) - set(before)),
                "disappeared_during_scan": None if before is None or after is None else
                    sorted(set(before) - set(after)),
                "processes": processes, "errors": errors}


def counter_delta(before, after):
    """Never turn a missing/decreased counter into zero or a wrapped delta."""
    if before is None or after is None or after < before:
        return None
    return after - before


def interval(previous, current):
    """Numeric deltas plus explicit transitions; not a contention classifier."""
    old_stat, new_stat = previous.get("stat"), current.get("stat")
    old_cpus = old_stat["cpus"] if old_stat else {}
    new_cpus = new_stat["cpus"] if new_stat else {}
    cpus = {cpu: {field: counter_delta(old_cpus.get(cpu, {}).get(field),
                                      new_cpus.get(cpu, {}).get(field))
                  for field in CPU_FIELDS} for cpu in sorted(old_cpus.keys() | new_cpus.keys())}
    old = {p["pid"]: p for p in previous["processes"]}
    new = {p["pid"]: p for p in current["processes"]}
    rows = []
    for pid in sorted(old.keys() | new.keys()):
        a, b = old.get(pid), new.get(pid)
        state = "continued"
        if a is None:
            state = "newly_observed"
        elif b is None:
            state = "not_observed"  # exit, permissions and incomplete enumeration differ
        elif identity(a) != identity(b):
            state = "pid_reused"
        same = state == "continued"
        rows.append({"pid": pid, "state": state,
                     "before_identity": identity(a) if a else None,
                     "after_identity": identity(b) if b else None,
                     "elapsed_ns": b["read_end_ns"] - a["read_end_ns"] if same else None,
                     "utime_ticks": counter_delta(a["utime_ticks"], b["utime_ticks"]) if same else None,
                     "stime_ticks": counter_delta(a["stime_ticks"], b["stime_ticks"]) if same else None,
                     "io": {key: counter_delta((a.get("io") or {}).get(key),
                                                (b.get("io") or {}).get(key)) if same else None
                            for key in IO_FIELDS},
                     "role": b.get("role") if b else a.get("role")})
    return {"elapsed_ns": current["begin_ns"] - previous["begin_ns"],
            "pid_coverage": {"before": previous.get("pid_coverage"),
                             "after": current.get("pid_coverage"),
                             "outside_recorded_identities": "UNKNOWN"},
            "cpus": cpus if old_stat is not None and new_stat is not None else None,
            "processes": rows,
            "vm": {key: counter_delta((previous.get("vm") or {}).get(key),
                                       (current.get("vm") or {}).get(key)) for key in VM_FIELDS},
            "pressure_total_us": {key: {scope: counter_delta(
                ((previous["pressure"].get(key) or {}).get(scope) or {}).get("total"),
                ((current["pressure"].get(key) or {}).get(scope) or {}).get("total"))
                for scope in ("some", "full")} for key in ("cpu", "io", "memory")},
            "endpoint_errors": bool(previous["errors"] or current["errors"]),
            "enumeration_unknown": any(s.get(key) is None for s in (previous, current)
                                       for key in ("pids_before", "pids_after")),
            "between_observations": "UNKNOWN"}
