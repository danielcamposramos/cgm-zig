#!/usr/bin/env python3
"""rows_held.py — the HELD batch carried from patch/003's merge record.

Rows: H1, H2, H3, H4, H5.

H2 and H5 are a PRE/POST pair on the same fixture: H2 asserts the corrected
diagnostic anchors on the double-owned file, H5 fires the same fixture against a
compiler that predates the fix and shows the old, wrong anchor. A guard that was
never seen red is a guard nobody has met — H5 is where this one was met, and it
costs nothing because the promoted binary happens to predate the fix.

H2's expected block is READ FROM THE FIXTURE'S OWN README, never hand-copied
here: a hand-copy agrees with itself the day someone edits the fixture.
"""

import os
import re

import vlib
from vlib import Verdict, GREEN, RED, UNKNOWN, INCONCLUSIVE, unknown, run_cmd, sha256_file

FIXTURE = os.path.join(vlib.REPO, "test", "fixtures", "file_in_multiple_modules")
FIXTURE_ARGS = ["build-obj", "-fno-emit-bin", "--dep", "mod_b", "-Mroot=main.zig", "-Mmod_b=mod_b.zig"]


# ---------------------------------------------------------------------- H1 --

@vlib.row("H1", "held", "rebuilt stage3 exists and identifies itself",
          "binary presence + `zig version` + sha256")
def h1(ctx):
    if not os.path.isfile(ctx.zig):
        return unknown("H1", f"no stage3 at {ctx.zig} — nothing was rebuilt, or it was moved",
                       "0 of 1 binaries present")
    r = run_cmd([ctx.zig, "version"], mask=None, timeout=60)
    ver = r.stdout.strip() or "UNKNOWN"
    ok = r.rc == 0 and ver.startswith("0.16.0")
    st = os.stat(ctx.zig)
    return Verdict("H1", GREEN if ok else RED,
                   f"{ctx.zig}: rc={r.rc}, version {ver}, sha256 {sha256_file(ctx.zig)[:16]}…, "
                   f"{st.st_size:,} B, mtime {int(st.st_mtime)}",
                   "1 of 1 binaries", {"version": ver, "rc": r.rc, "sha256": sha256_file(ctx.zig)})


# ------------------------------------------------------- H2 / H5 expectations --

def _expected_block():
    """The four diagnostic lines, read out of the fixture's README fenced block."""
    readme = os.path.join(FIXTURE, "README.md")
    if not os.path.isfile(readme):
        return None, f"fixture README absent at {readme}"
    text = open(readme, encoding="utf-8", errors="replace").read()
    m = re.search(r"## Expected\s*\n+```\n(.*?)```", text, re.S)
    if not m:
        return None, "fixture README has no '## Expected' fenced block to read the expectation from"
    lines = [l.strip() for l in m.group(1).strip().splitlines() if l.strip()]
    return lines, None


@vlib.row("H2", "held", "fixture repro — the root message anchors on the double-owned file",
          "four diagnostic lines vs the fixture README's own Expected block")
def h2(ctx):
    exp, why = _expected_block()
    if exp is None:
        return unknown("H2", why, "0 of 1 expectations readable")
    if not os.path.isdir(FIXTURE):
        return unknown("H2", f"fixture directory absent: {FIXTURE}", "0 of 1 fixtures present")
    r = run_cmd([ctx.zig] + FIXTURE_ARGS, cwd=FIXTURE, env=ctx.env_zig, mask=ctx.mask, timeout=300)
    got = r.stderr
    matched = [l for l in exp if l in got]
    ok = len(matched) == len(exp) and r.rc == 1
    ev = (f"exit={r.rc} (expected 1); {len(matched)} of {len(exp)} expected diagnostic lines present "
          f"verbatim; root message: "
          f"{next((l for l in got.splitlines() if ': error: file exists in modules' in l), 'ABSENT')}"
          + (f"; missing: {[l for l in exp if l not in got]}" if len(matched) != len(exp) else ""))
    return Verdict("H2", GREEN if ok else RED, ev,
                   f"{len(matched)} of {len(exp)} expected lines", {"rc": r.rc, "expected": exp})


# ---------------------------------------------------------------------- H3 --

H3_STEPS = ["test-cases", "test-incremental"]


@vlib.row("H3", "held", "test-cases + test-incremental over the corrected snapshots",
          "`zig build test-cases` / `test-incremental` (--slow only)", slow=True,
          cost="~40 min per attempt")
def h3(ctx):
    """Both steps rebuild the compiler as a dependency. Gated behind --slow.

    The invocation is stated in full whether or not it runs, so this row is
    never blocked on somebody working out the command again.
    """
    cmds = [f"(cd {vlib.REPO} && taskset -c {ctx.mask} zig build {s})" for s in H3_STEPS]
    if not ctx.slow:
        return unknown("H3", "NOT RUN — gated behind --slow. Both steps rebuild the compiler as a "
                             "dependency (~40 min per attempt on a contended 8-CPU mask). Exact "
                             "invocation, ready to fire: " + " ; ".join(cmds),
                       f"0 of {len(H3_STEPS)} steps run", commands=cmds)
    results = {}
    for step in H3_STEPS:
        r = run_cmd(["zig", "build", step], cwd=vlib.REPO, env=ctx.env_zig,
                    mask=ctx.mask, timeout=7200)
        results[step] = {"rc": 124 if r.timed_out else r.rc, "wall": r.wall,
                         "stderr_tail": r.stderr[-800:]}
    good = sum(1 for v in results.values() if v["rc"] == 0)
    ev = "; ".join(f"{k}: rc={v['rc']} in {v['wall']:.1f}s" for k, v in results.items())
    return Verdict("H3", GREEN if good == len(H3_STEPS) else RED, ev,
                   f"{good} of {len(H3_STEPS)} steps", results)


# ---------------------------------------------------------------------- H4 --

@vlib.row("H4", "held", "zig fmt --check over everything the branch touches",
          "`zig fmt --check`, denominator from `git diff --name-only`")
def h4(ctx):
    """Denominator is DERIVED from git, never a hand list of fourteen files.

    Honest scope note: this checks the WORKING TREE, which on this station may
    carry other lanes' uncommitted edits. Those files are counted and named so a
    red can be attributed to the right lane.
    """
    base = run_cmd(["git", "merge-base", "HEAD", "main"], cwd=vlib.REPO, mask=None, timeout=60)
    ref = base.stdout.strip() or "main"
    diff = run_cmd(["git", "diff", "--name-only", f"{ref}..HEAD", "--", "*.zig"],
                   cwd=vlib.REPO, mask=None, timeout=60)
    files = [f for f in diff.stdout.split() if f.endswith(".zig")]
    dirty = run_cmd(["git", "status", "--porcelain", "--", "*.zig"], cwd=vlib.REPO, mask=None, timeout=60)
    dirty_files = [l[3:] for l in dirty.stdout.splitlines() if l.strip()]
    if not files:
        return unknown("H4", f"no touched .zig files found from `git diff --name-only {ref}..HEAD` "
                             f"— the denominator this row needs cannot be derived",
                       "0 of 0 files (denominator underivable)")
    present = [f for f in files if os.path.isfile(os.path.join(vlib.REPO, f))]
    r = run_cmd([ctx.zig, "fmt", "--check"] + present, cwd=vlib.REPO, env=ctx.env_zig,
                mask=ctx.mask, timeout=600)
    offenders = [l.strip() for l in r.stdout.splitlines() if l.strip()]
    ok = r.rc == 0
    ev = (f"`zig fmt --check` rc={r.rc} over {len(present)} of {len(files)} branch-touched .zig files "
          f"(denominator: `git diff --name-only {ref[:12]}..HEAD -- '*.zig'`)"
          + (f"; unformatted: {offenders}" if offenders else "")
          + (f". SCOPE: the working tree carries {len(dirty_files)} uncommitted .zig file(s) "
             f"({dirty_files}) belonging to concurrent lanes — a red here may be theirs, not this branch's."
             if dirty_files else ""))
    return Verdict("H4", GREEN if ok else RED, ev, f"{len(present)} of {len(files)} touched .zig files",
                   {"files": files, "offenders": offenders, "dirty": dirty_files, "rc": r.rc})


# ---------------------------------------------------------------------- H5 --

@vlib.row("H5", "held", "negative control: the same fixture against a PRE-fix compiler",
          "the fixture's root message anchor, reference vs patched")
def h5(ctx):
    """The promoted binary predates the anchor fix, which makes it a free PRE oracle.

    PRE must anchor on the IMPORTER (`mod_b.zig:1:1`) and POST on the
    double-owned file (`dupe.zig:1:1`). Same fixture, same command, one variable.
    """
    if not os.path.isdir(FIXTURE):
        return unknown("H5", f"fixture directory absent: {FIXTURE}", "0 of 2 arms")
    out = {}
    for label, binary, env in (("PRE (reference)", ctx.ref, ctx.env_ref),
                               ("POST (patched)", ctx.zig, ctx.env_zig)):
        r = run_cmd([binary] + FIXTURE_ARGS, cwd=FIXTURE, env=env, mask=ctx.mask, timeout=300)
        root = next((l for l in r.stderr.splitlines() if ": error: file exists in modules" in l), None)
        anchor = root.split(":")[0] if root else None
        out[label] = {"rc": r.rc, "root_line": root, "anchor": anchor}
    pre, post = out["PRE (reference)"], out["POST (patched)"]
    moved = (pre["anchor"] and post["anchor"] and pre["anchor"] != post["anchor"]
             and post["anchor"] == "dupe.zig")
    ev = (f"PRE  {pre['anchor']}  ->  POST {post['anchor']}. "
          f"PRE root line: {pre['root_line']!r} | POST root line: {post['root_line']!r}. "
          + ("The guard has been seen red: the pre-fix compiler sends the reader into the "
             "importer, which is exactly the defect this fixture pins."
             if moved else
             "The anchor did NOT move between the two compilers — either the reference is not "
             "pre-fix, or the fix is not in the binary under test. Either way this row proves "
             "nothing until that is resolved."))
    return Verdict("H5", GREEN if moved else RED, ev, "2 of 2 arms (PRE + POST)", out)
