#!/usr/bin/env python3
"""repro.py — fire a stored args-file compile and print the receipt block.

One command reproduces a compiler run the way this fork's own investigations
did: verbatim args-file, /usr/bin/time -v, full stderr captured to a file,
and a receipt block you can paste into a commit body.

  python3 partner_tools/repro.py <args-file> [--zig BIN] [--subcommand build-exe]
                                 [--out DIR] [--extra ...]

Notes baked in from measured history:
  * `--listen=-` is stripped (on a temp copy, disclosed in the receipt) — that
    flag binds the compiler to the build-runner IPC and hangs a standalone run.
  * stderr is captured IN FULL; its byte count is part of the receipt because
    "0 bytes where words were expected" is itself a finding.
  * Exit vs signal is reported explicitly (a shell's 139 is SIGSEGV, 134 is
    SIGABRT; we decode rather than make the reader remember).
Stdlib only.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ZIG = os.path.join(REPO, "build-safe", "stage3", "bin", "zig")
TIME_BIN = "/usr/bin/time"


def parse_time_v(text):
    keep = ("Elapsed (wall clock)", "Maximum resident set size",
            "Exit status", "Major (requiring I/O) page faults", "Swaps")
    return [l.strip() for l in text.splitlines() if any(k in l for k in keep)]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("args_file", help="stored @args file from a zig build (found under .zig-cache/args/)")
    ap.add_argument("--zig", default=DEFAULT_ZIG)
    ap.add_argument("--subcommand", default="build-exe")
    ap.add_argument("--out", default=None, help="run dir (default: mkdtemp)")
    ap.add_argument("--extra", nargs="*", default=[], help="extra compiler flags, e.g. -j2")
    a = ap.parse_args()

    if not os.path.isfile(a.zig):
        print(f"REFUSE: zig binary not found at {a.zig} — build the safe stage3 first "
              f"(recipe in .claude/skills/cgm-zig/SKILL.md) or pass --zig")
        return 2
    if not os.path.isfile(a.args_file):
        print(f"REFUSE: args-file not found: {a.args_file}")
        return 2
    if not os.path.isfile(TIME_BIN):
        print(f"REFUSE: {TIME_BIN} missing — receipts need GNU time, not the shell builtin")
        return 2

    run_dir = a.out or tempfile.mkdtemp(prefix="repro_")
    os.makedirs(run_dir, exist_ok=True)

    raw = open(a.args_file, "r", encoding="utf-8", errors="replace").read()
    stripped = re.sub(r"(?m)^--listen=-\n?|(?<=\s)--listen=-(?=\s|$)", "", raw)
    listen_stripped = stripped != raw
    fired = os.path.join(run_dir, "fired.args")
    with open(fired, "w", encoding="utf-8") as f:
        f.write(stripped)

    stderr_path = os.path.join(run_dir, "stderr.txt")
    time_path = os.path.join(run_dir, "time_v.txt")
    cmd = [TIME_BIN, "-v", "-o", time_path,
           a.zig, a.subcommand, f"@{fired}"] + a.extra
    print(f"firing: {' '.join(cmd)}\n(cwd={run_dir}; stderr -> {stderr_path})")
    with open(stderr_path, "wb") as errf:
        p = subprocess.run(cmd, cwd=run_dir, stdout=subprocess.DEVNULL, stderr=errf)

    stderr_bytes = os.path.getsize(stderr_path)
    sig = -p.returncode if p.returncode < 0 else None
    print("\n== RECEIPT ==")
    print(f"command      : {a.subcommand} @{os.path.basename(a.args_file)}"
          + (f" {' '.join(a.extra)}" if a.extra else ""))
    print(f"zig          : {a.zig}")
    print(f"listen strip : {'yes (temp copy; original untouched)' if listen_stripped else 'no --listen=- present'}")
    print(f"exit         : rc={p.returncode}" + (f" (signal {sig})" if sig else ""))
    print(f"stderr bytes : {stderr_bytes}"
          + ("  <- silence; on a safe build that is itself a finding" if stderr_bytes == 0 else ""))
    tv = parse_time_v(open(time_path).read()) if os.path.isfile(time_path) else []
    for line in tv or ["time -v receipt: UNKNOWN (no output file)"]:
        print(f"  {line}")
    if stderr_bytes:
        tail = open(stderr_path, "r", errors="replace").read()[-600:]
        print("-- stderr tail --")
        print(tail)
    print(f"run dir kept : {run_dir}")
    return 0 if p.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
