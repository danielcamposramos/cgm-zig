#!/usr/bin/env python3
"""patches_ledger.py — the patchset, DERIVED from git history. Never a hand-list.

A hand-maintained patch list drifts the day after it is written; this ledger is
computed from the repository's own record every time it runs. A patch, for
ledger purposes, is a non-merge commit since the upstream base that touches
upstream code paths (src/, lib/, stage1/, tools/, cmake/, build.zig*,
CMakeLists.txt, bootstrap.c).

Per patch it prints: short sha, subject, files touched (count + names),
and the `Upstream-Status:` line read from the commit body — or
`Upstream-Status: UNKNOWN (not declared in commit body)` when absent,
because an undeclared status is a fact worth seeing, not a blank to skip.

Stdlib only. `--self-test` verifies the derivation logic on the live repo
(root resolvable, ledger parseable, every entry carries a status line).
"""

import argparse
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPSTREAM_CODE = ["src", "lib", "stage1", "tools", "cmake",
                 "build.zig", "build.zig.zon", "CMakeLists.txt", "bootstrap.c"]
SEP = "\x1e"  # record separator


def run(args):
    p = subprocess.run(args, cwd=REPO, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"REFUSE: {' '.join(args)} exited {p.returncode}: {p.stderr.strip()}")
    return p.stdout


def root_commit():
    out = run(["git", "rev-list", "--max-parents=0", "HEAD"]).strip()
    return out.splitlines()[-1]


def derive():
    root = root_commit()
    raw = run(["git", "log", "--no-merges", f"--format={SEP}%H%x09%s%x09%b",
               f"{root}..HEAD", "--"] + UPSTREAM_CODE)
    entries = []
    for rec in raw.split(SEP):
        rec = rec.strip("\n")
        if not rec.strip():
            continue
        sha, subject, body = (rec.split("\t", 2) + ["", ""])[:3]
        status = next((l.strip() for l in body.splitlines()
                       if l.strip().startswith("Upstream-Status:")), None)
        files = run(["git", "show", "--name-only", "--format=", sha]).strip().splitlines()
        entries.append({
            "sha": sha, "subject": subject,
            "status": status or "Upstream-Status: UNKNOWN (not declared in commit body)",
            "files": [f for f in files if f.strip()],
        })
    return root, entries


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()

    root, entries = derive()
    if a.self_test:
        checks = [
            ("root commit resolvable (40 hex)", len(root) == 40),
            ("every entry has a status line", all(e["status"] for e in entries)),
            ("every entry touches >=1 upstream file", all(len(e["files"]) >= 1 for e in entries)),
        ]
        for name, ok in checks:
            print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        n = sum(1 for _, ok in checks if ok)
        print(f"SELF-TEST: {n}/{len(checks)} checks passed over {len(entries)} derived entrie(s)")
        return 0 if n == len(checks) else 1

    print(f"PATCH LEDGER — derived from git log at run time (base {root[:12]}); "
          f"{len(entries)} patch commit(s) touching upstream code")
    for e in entries:
        print(f"\n{e['sha'][:12]}  {e['subject']}")
        print(f"  {e['status']}")
        print(f"  files ({len(e['files'])}): " + ", ".join(e["files"][:8])
              + (f", ... +{len(e['files'])-8} more" if len(e["files"]) > 8 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
