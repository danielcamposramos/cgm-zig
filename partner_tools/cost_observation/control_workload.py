"""Finite noninteractive instrument child; never a compiler or speed benchmark.

Adapt the old test_observe.CHILD computation, not its stdin handshake. Fixed
holds permit endpoint observations without consulting or synchronizing with the
observer. Only the parent wrapper launches this child; it launches no children.
"""

import json
import os
import sys
import time

from .procfs import Procfs


def work(mode, clock=time.monotonic_ns, cpu=time.process_time_ns, sleep=time.sleep):
    """Return raw clock endpoints; injectable clocks permit no-work unit tests."""
    if mode not in ("busy", "idle"):
        raise ValueError("unknown_control_mode")
    pre_begin = clock()
    sleep(0.5)
    pre_end = clock()
    begin = clock()
    cpu_begin = cpu()
    if mode == "busy":
        while cpu() - cpu_begin < 350_000_000 and clock() - begin < 2_000_000_000:
            sum(range(2000))
    else:
        sleep(0.5)
    cpu_end = cpu()
    end = clock()
    post_begin = clock()
    sleep(0.5)
    post_end = clock()
    return {"mode": mode, "pre_hold_ns": [pre_begin, pre_end],
            "work_ns": [begin, end], "post_hold_ns": [post_begin, post_end],
            "cpu_ns": [cpu_begin, cpu_end], "cpu_seconds": (cpu_end - cpu_begin) / 1e9,
            "deadline_reached_before_cpu_target": mode == "busy" and cpu_end - cpu_begin < 350_000_000}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("busy", "idle"):
        raise SystemExit("expected_busy_or_idle")
    child = Procfs().process_identity(os.getpid())
    affinity = sorted(os.sched_getaffinity(0))
    value = work(sys.argv[1])
    print(json.dumps({"schema": 1, "child": child, "affinity": affinity, **value}), flush=True)


if __name__ == "__main__":
    main()
