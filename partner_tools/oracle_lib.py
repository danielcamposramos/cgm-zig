#!/usr/bin/env python3
"""oracle_lib.py — the anchored-edit / negative-control / revert-verified idiom.

The convention these helpers enforce (full prose: oracle_conventions.md):
  * every automated edit ASSERTS its anchor's occurrence count before writing
    (a 0-count anchor means your premise is stale; a >expected count means
    your edit is about to land somewhere you did not look);
  * every guard is proven to FIRE via a sabotage on a scratch copy;
  * every sabotage is REVERTED and the revert verified by sha256.

Stdlib only. Run `--self-test` to see all three protections fire.
"""

import hashlib
import shutil
import sys
import tempfile
import os


class AnchorError(AssertionError):
    pass


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def assert_anchor(path, anchor, expected=1):
    """Refuse-by-name unless `anchor` occurs exactly `expected` times."""
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    n = text.count(anchor)
    if n != expected:
        raise AnchorError(
            f"anchor count mismatch in {path}: found {n}, expected {expected} "
            f"for anchor {anchor!r} — premise stale or edit under-scoped; refusing to write")
    return n


def replace_anchored(path, old, new, expected=1):
    """Assert-then-edit. Returns (pre_sha, post_sha, sites_changed)."""
    assert_anchor(path, old, expected)
    pre = sha256_file(path)
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(old, new))
    return pre, sha256_file(path), expected


def sabotage_copy(path, old, new, expected=1, workdir=None):
    """Copy `path` to scratch, apply the sabotage there, return the copy path.
    The original is never touched — that is the whole point."""
    d = workdir or tempfile.mkdtemp(prefix="sabotage_")
    cp = os.path.join(d, os.path.basename(path))
    shutil.copy2(path, cp)
    replace_anchored(cp, old, new, expected)
    return cp


def revert_verified(path, pre_sha, pristine_bytes):
    """Restore `path` from held bytes and verify the restore byte-for-byte."""
    with open(path, "wb") as f:
        f.write(pristine_bytes)
    post = sha256_file(path)
    if post != pre_sha:
        raise AnchorError(f"revert FAILED for {path}: sha {post[:12]} != pre {pre_sha[:12]}")
    return post


def self_test():
    checks = []
    d = tempfile.mkdtemp(prefix="oracle_selftest_")
    p = os.path.join(d, "specimen.txt")
    with open(p, "w") as f:
        f.write("alpha\nBETA_ANCHOR\ngamma\n")
    pristine = open(p, "rb").read()
    pre = sha256_file(p)

    # 1) anchored replace works and reports shas
    a, b, n = replace_anchored(p, "BETA_ANCHOR", "BETA_EDITED", 1)
    checks.append(("anchored replace (1 site, sha moved)", a == pre and b != pre and n == 1))

    # 2) revert restores byte-identical
    post = revert_verified(p, pre, pristine)
    checks.append(("revert sha-verified", post == pre))

    # 3) NEGATIVE CONTROL: a stale anchor refuses by name
    fired = False
    try:
        assert_anchor(p, "ANCHOR_THAT_NEVER_EXISTED", 1)
    except AnchorError:
        fired = True
    checks.append(("stale-anchor refusal FIRED", fired))

    # 4) NEGATIVE CONTROL: over-count anchor refuses
    with open(p, "a") as f:
        f.write("BETA_ANCHOR\nBETA_ANCHOR\n")
    fired2 = False
    try:
        assert_anchor(p, "BETA_ANCHOR", 1)
    except AnchorError:
        fired2 = True
    checks.append(("over-count refusal FIRED", fired2))

    passed = sum(1 for _, ok in checks if ok)
    for name, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    print(f"SELF-TEST: {passed}/{len(checks)} checks passed")
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    print(__doc__)
