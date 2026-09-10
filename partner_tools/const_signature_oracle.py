#!/usr/bin/env python3
"""Cross-process oracle for `src/link/ConstPool.zig` type signatures.

The claim under test is narrow and stated as such: for the kinds the pool signs
today, TWO SEPARATE COMPILER PROCESSES derive the SAME signature for the SAME
type, and DIFFERENT signatures for types that differ in element width, length,
or target. It proves nothing about shared debug emission and nothing about
artifact size --- see docs/crown/CROSS_PROCESS_SIGNATURE.md for that ceiling.

Usage:
    python3 partner_tools/const_signature_oracle.py --zig <compiler> --out <dir>

The compiler must be built with `-Dlog` (otherwise `--debug-log` is inert and
every set comes back empty, which this script reports as UNKNOWN, not as pass).
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = REPO / "partner_tools" / "fixtures" / "const_signature"
SIGNATURE_RE = re.compile(r"const signature (0x[0-9a-f]{16})")

# name -> (fixture file, target triple)
RUNS = {
    "a": ("a.zig", "x86_64-linux-gnu"),
    "b": ("b.zig", "x86_64-linux-gnu"),
    "c_elem": ("c_elem.zig", "x86_64-linux-gnu"),
    "d_len": ("d_len.zig", "x86_64-linux-gnu"),
    "a_musl": ("a.zig", "x86_64-linux-musl"),
}


def compile_one(zig: pathlib.Path, out: pathlib.Path, name: str) -> tuple[int, set[str]]:
    """Compile one fixture in its own process; return (exit code, signature set)."""
    source, target = RUNS[name]
    log_path = out / f"log_{name}.txt"
    cmd = [
        str(zig), "build-obj",
        "--zig-lib-dir", str(REPO / "lib"),
        "-fno-llvm", "-fno-lld", "-ODebug",
        "-target", target,
        "--debug-log", "const_pool",
        "-femit-bin=" + str(out / f"{name}.o"),
        str(FIXTURES / source),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    log_path.write_text(proc.stderr)
    return proc.returncode, set(SIGNATURE_RE.findall(proc.stderr))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    codes: dict[str, int] = {}
    sets: dict[str, set[str]] = {}
    for name in RUNS:
        codes[name], sets[name] = compile_one(args.zig, args.out, name)
        print(f"{name:8s} exit={codes[name]} signatures={len(sets[name])}")

    checks: list[tuple[str, bool | None, str]] = []

    crashed = [n for n, c in codes.items() if c != 0]
    checks.append(("every fixture compiles without a collision refusal",
                   not crashed, f"nonzero exits: {crashed or None}"))

    if not any(sets.values()):
        # An absent instrument reports UNKNOWN, never a pass.
        checks.append(("instrument present (compiler built with -Dlog)", None,
                       "no signature lines in any log"))
        shared = set()
    else:
        shared = (sets["a"] & sets["b"]) - sets["c_elem"] - sets["d_len"]
        checks.append(("a and b share a signature that neither control has",
                       bool(shared), f"discriminating signatures: {sorted(shared)}"))
        checks.append(("changing element width changes the signature set",
                       sets["a"] != sets["c_elem"], ""))
        checks.append(("changing array length changes the signature set",
                       sets["a"] != sets["d_len"], ""))
        overlap = sets["a"] & sets["a_musl"]
        checks.append(("changing target changes every signature",
                       not overlap, f"overlap: {sorted(overlap)}"))

    print()
    failed = 0
    for label, ok, detail in checks:
        mark = "UNKNOWN" if ok is None else ("PASS" if ok else "FAIL")
        if ok is not True:
            failed += 1
        print(f"[{mark}] {label}" + (f" -- {detail}" if detail else ""))

    print(f"\n{len(checks) - failed}/{len(checks)} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
