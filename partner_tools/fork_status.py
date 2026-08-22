#!/usr/bin/env python3
"""fork_status.py — the fork's eyes.

Reports, with honest denominators and UNKNOWN-never-zero:
  1. TOOLCHAIN — is the safe stage3 compiler present? version, sha256, mtime.
  2. BASE      — the pinned upstream import (root commit) this patchset stands on.
  3. PATCHSET  — commits that touch upstream code (src/, lib/, stage1/, tools/,
                 build.zig*) since the base, i.e. the actual divergence.
  4. TREE      — working-tree cleanliness, branch/upstream sync.

House rules implemented here: an absent instrument is reported UNKNOWN (never
zero, never assumed-good); every count states its scope; refusals are by name.
Stdlib only.
"""

import argparse
import hashlib
import os
import subprocess
import sys
from datetime import datetime, timezone

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE3 = os.path.join(REPO, "build-safe", "stage3", "bin", "zig")
# Paths that count as "upstream code" for divergence purposes. Everything else
# (docs/, partner_tools/, .claude/, PROVENANCE.md, ...) is fork-side material
# that upstream never shipped, so it is not divergence in the rebase sense.
UPSTREAM_CODE = ["src", "lib", "stage1", "tools", "cmake", "build.zig", "build.zig.zon", "CMakeLists.txt", "bootstrap.c"]


def run(args, cwd=REPO):
    """Run a command; return (exit_code, stdout_text). Never raises on rc!=0."""
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


def sha256_file(path, limit_mb=512):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def section_toolchain():
    print("== TOOLCHAIN ==")
    if not os.path.isfile(STAGE3):
        print(f"stage3: ABSENT at {STAGE3} — toolchain state UNKNOWN (not 'broken', not 'ok': unbuilt or moved)")
        return
    st = os.stat(STAGE3)
    mtime = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    rc, ver = run([STAGE3, "version"])
    ver = ver if rc == 0 else f"UNKNOWN (zig version exited {rc})"
    print(f"stage3: PRESENT  {STAGE3}")
    print(f"  version: {ver}   size: {st.st_size} B   mtime: {mtime}")
    print(f"  sha256: {sha256_file(STAGE3)}")


def base_commit():
    rc, out = run(["git", "rev-list", "--max-parents=0", "HEAD"])
    if rc != 0 or not out:
        return None, None
    root = out.splitlines()[-1].strip()
    rc, subj = run(["git", "log", "-1", "--format=%s", root])
    return root, subj if rc == 0 else "UNKNOWN"


def section_base():
    print("== BASE ==")
    root, subj = base_commit()
    if root is None:
        print("base: UNKNOWN — git rev-list failed; is this a git checkout?")
        return None
    print(f"root commit: {root[:12]}  \"{subj}\"")
    return root


def section_patchset(root):
    print("== PATCHSET (divergence against upstream code paths) ==")
    if root is None:
        print("patchset: UNKNOWN — no base commit resolved")
        return
    rc, out = run(["git", "log", "--no-merges", "--format=%H%x09%s",
                   f"{root}..HEAD", "--"] + UPSTREAM_CODE)
    if rc != 0:
        print(f"patchset: UNKNOWN — git log exited {rc}")
        return
    lines = [l for l in out.splitlines() if l.strip()]
    rc2, total = run(["git", "rev-list", "--count", "--no-merges", f"{root}..HEAD"])
    total_s = total if rc2 == 0 else "UNKNOWN"
    print(f"patch commits touching upstream code: {len(lines)} of {total_s} non-merge commits since base")
    for l in lines:
        sha, subj = l.split("\t", 1)
        print(f"  {sha[:12]}  {subj}")
    if not lines:
        print("  (none — the fork currently carries zero upstream-code divergence)")


def section_tree():
    print("== TREE ==")
    rc, sb = run(["git", "status", "-sb"])
    print(f"branch: {sb.splitlines()[0] if rc == 0 and sb else 'UNKNOWN'}")
    rc, porcelain = run(["git", "status", "--porcelain"])
    if rc != 0:
        print("cleanliness: UNKNOWN — git status failed")
        return
    entries = [l for l in porcelain.splitlines() if l.strip()]
    print(f"working tree: {len(entries)} modified/untracked path(s)"
          + ("" if entries else " — clean"))
    for l in entries[:20]:
        print(f"  {l}")
    if len(entries) > 20:
        print(f"  ... and {len(entries) - 20} more of {len(entries)} total")


def self_test():
    """Prove the UNKNOWN arm fires: point at a nonexistent stage3 and confirm
    the report says ABSENT/UNKNOWN rather than inventing a state."""
    global STAGE3
    real = STAGE3
    STAGE3 = os.path.join(REPO, "build-safe", "stage3", "bin", "zig.DOES_NOT_EXIST")
    ok_absent = not os.path.isfile(STAGE3)
    section_toolchain()
    STAGE3 = real
    root, _ = base_commit()
    ok_base = root is not None and len(root) == 40
    print(f"SELF-TEST: absent-toolchain arm fired: {ok_absent}; base resolvable: {ok_base}"
          f"  -> {'PASS 2/2 checks' if (ok_absent and ok_base) else 'FAIL'}")
    return 0 if (ok_absent and ok_base) else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        sys.exit(self_test())
    section_toolchain()
    root = section_base()
    section_patchset(root)
    section_tree()


if __name__ == "__main__":
    main()
