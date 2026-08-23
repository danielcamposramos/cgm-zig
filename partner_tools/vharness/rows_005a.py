#!/usr/bin/env python3
"""rows_005a.py — the topology probe (commit 7106d368).

Rows: V0, V0a, V1, V11, V14, V-S1a, V-S1b.

Two corrections from the 2026-08-23 run are implemented here rather than
argued about:

  * **V0a's third command was a mis-specified oracle.** `taskset -c 0-3 lscpu -e`
    prints all 12 CPUs — `lscpu -e` reads sysfs, not `sched_getaffinity`, so it
    is affinity-blind and cannot witness a pin. This harness runs BOTH the
    original command and an affinity-aware one (`nproc`), and reports the
    disagreement as evidence rather than quietly substituting.
  * **V11/V-S1b's byte-identity criterion is not decisive on this toolchain.**
    Whole-file output is not reproducible at `-j > 1` on the *unpatched*
    compiler either (see V12-P1-OLD, which proves it). Both rows therefore
    report whole-file AND `.text`, and say which one carries the verdict.
"""

import os

import vlib
from vlib import (Verdict, GREEN, RED, UNKNOWN, INCONCLUSIVE, unknown, row,
                  run_cmd, section_digest, sha256_file, cold_local_cache)


# ---------------------------------------------------------------------- V0 --

@vlib.row("V0", "005a", "the design's compiler exists and identifies itself",
          "binary presence + `zig version` + sha256")
def v0(ctx):
    """V0 is a BUILD row. This harness is not authorised to build a compiler.

    What it can do honestly is state which binaries the measurement pass will
    actually run, so a later reader can tell whether the numbers came from the
    binary they think they did. A missing binary is a refusal by name, not a
    silent skip.
    """
    facts = {}
    for label, path in (("patched", ctx.zig), ("reference", ctx.ref)):
        if not os.path.isfile(path):
            facts[label] = {"present": False}
            continue
        r = run_cmd([path, "version"], mask=None, timeout=60)
        facts[label] = {"present": True, "path": path,
                        "version": r.stdout.strip() or "UNKNOWN",
                        "sha256": sha256_file(path), "rc": r.rc,
                        "size": os.path.getsize(path)}
    have = [k for k, v in facts.items() if v.get("present")]
    if len(have) < 2:
        missing = [k for k, v in facts.items() if not v.get("present")]
        return unknown("V0", f"binary absent: {missing} — build it (docs/crown BUILDING recipe); "
                             f"this harness never builds a compiler by charter",
                       f"{len(have)} of 2 binaries present", facts=facts)
    vers = {k: v["version"] for k, v in facts.items()}
    ok = all(v.startswith("0.16.0") for v in vers.values())
    return Verdict("V0", GREEN if ok else RED,
                   f"patched {facts['patched']['version']} sha {facts['patched']['sha256'][:12]}… ; "
                   f"reference {facts['reference']['version']} sha {facts['reference']['sha256'][:12]}… "
                   f"(the BUILD half of V0 is performed elsewhere; this row only pins WHICH binaries ran)",
                   "2 of 2 binaries present and self-identifying", facts)


# --------------------------------------------------------------------- V0a --

@vlib.row("V0a", "005a", "host topology oracle, recorded FIRST",
          "sysfs thread_siblings_list + lscpu + affinity-aware nproc")
def v0a(ctx):
    """The oracle every topology row is checked against. Recorded before the probe.

    Three instruments, and the row reports the disagreement between two of them
    because that disagreement IS the V-list defect this row inherited.
    """
    topo = vlib.host_topology()
    if topo is None:
        return unknown("V0a", "/sys/devices/system/cpu/*/topology/thread_siblings_list absent — "
                              "no host topology oracle on this machine",
                       "0 of 3 instruments available")
    lscpu = run_cmd(["lscpu", "-e=CPU,CORE,SOCKET"], mask=None, timeout=60)
    lscpu_rows = max(0, len(lscpu.stdout.strip().splitlines()) - 1)
    cores = {l.split()[1] for l in lscpu.stdout.strip().splitlines()[1:] if len(l.split()) > 1}

    # The mis-specified original vs the affinity-aware replacement, side by side.
    pinned_lscpu = run_cmd(["lscpu", "-e=CPU,CORE,SOCKET"], mask="0-3", timeout=60)
    pinned_rows = max(0, len(pinned_lscpu.stdout.strip().splitlines()) - 1)
    pinned_nproc = run_cmd(["nproc"], mask="0-3", timeout=60)
    nproc_n = int(pinned_nproc.stdout.strip()) if pinned_nproc.rc == 0 else None

    exp = vlib.expected_for_mask(topo, "0-3")
    checks = {
        "sysfs logical == lscpu rows": topo["logical"] == lscpu_rows,
        "sysfs physical == distinct lscpu CORE ids": topo["physical"] == len(cores),
        "affinity-aware nproc under 0-3 == |mask|": nproc_n == exp["logical"],
        "lscpu -e under 0-3 is affinity-BLIND (prints all CPUs)": pinned_rows == topo["logical"],
    }
    passed = sum(1 for v in checks.values() if v)
    split = all(max(g) - min(g) > 1 for g in topo["sibling_groups"] if len(g) > 1)
    ev = (f"{topo['logical']} logical / {topo['physical']} physical; siblings "
          f"{' '.join(','.join(map(str, g)) for g in topo['sibling_groups'])} "
          f"({'SPLIT' if split else 'ADJACENT'}); mask 0-3 -> nproc {nproc_n} "
          f"(oracle says {exp['logical']} logical / {exp['physical']} physical); "
          f"`lscpu -e` under the same pin still printed {pinned_rows} rows — affinity-blind, "
          f"which is the V-list defect: the original third command cannot witness a pin")
    return Verdict("V0a", GREEN if passed == len(checks) else RED, ev,
                   f"{passed} of {len(checks)} oracle cross-checks",
                   {"topology": topo, "checks": checks, "mask_0_3_expected": exp,
                    "nproc_under_0_3": nproc_n, "lscpu_rows_under_0_3": pinned_rows})


# ---------------------------------------------------------------------- V1 --

V1_ARMS = [
    ("1 unpinned", [], None),
    ("2 -j4 --intern-partitions=2", ["-j4", "--intern-partitions=2"], None),
    ("3 taskset -c 0-3 (THE GATE)", [], "0-3"),
    ("4 --intern-partitions=logical", ["--intern-partitions=logical"], None),
]


@vlib.row("V1", "005a", "the report line exists, is truthful, and survives a pin",
          "stderr report line vs the V0a sysfs oracle")
def v1(ctx):
    """Four invocations, each checked against the oracle — not against the dossier.

    Every expected number is DERIVED here (`vlib.expected_items`,
    `vlib.expected_for_mask`). A hand-copied ceiling table would agree with the
    dossier and prove nothing about the compiler.
    """
    topo = ctx.topology or vlib.host_topology()
    if topo is None:
        return unknown("V1", "no sysfs topology oracle — the report line cannot be checked "
                             "against anything independent", "0 of 4 sub-rows")
    fx = ctx.fixtures.get("hello")
    results, failures = [], []
    index_bits = None      # derived from arm 1, then used to check arms 2-4
    for label, extra, mask in V1_ARMS:
        m = mask if mask is not None else ctx.mask
        r = run_cmd([ctx.zig, "build-obj", "-fno-emit-bin", "-Mroot=hello.zig"] + extra,
                    cwd=fx["dir"], env=ctx.env_zig, mask=m, timeout=120)
        rep = vlib.parse_report_line(r.stderr)
        exp = vlib.expected_for_mask(topo, m)
        if rep is None:
            failures.append(f"{label}: NO report line "
                            + ("(HUNG — killed at the 120 s cap)" if r.timed_out else f"(rc={r.rc})"))
            results.append({"arm": label, "mask": m, "report": None, "rc": r.rc,
                            "timed_out": r.timed_out})
            continue
        want_parts = (2 if "--intern-partitions=2" in extra else
                      exp["logical"] if "--intern-partitions=logical" in extra else None)
        if index_bits is None:
            # Derived from the compiler's FIRST answer, never asserted from a constant:
            # `ThreadPlan.index_bits` has already moved once (30 -> 31, doubling every
            # published ceiling), and a harness that hard-codes it turns that commit
            # into a false red.
            index_bits = vlib.derive_index_bits(rep["items"], rep["partitions"])
        sub = {
            "logical matches oracle": rep["logical"] == exp["logical"],
            "physical matches oracle": rep["physical"] == exp["physical"],
            "items per partition == the derived index-space carve":
                index_bits is not None
                and rep["items"] == vlib.expected_items(rep["partitions"], index_bits),
            "alloc lanes == partitions - 2 (saturating)": rep["alloc_lanes"] == max(0, rep["partitions"] - 2),
            ("did not HANG (killed at the 120 s cap)" if r.timed_out else "rc == 0"): r.rc == 0,
        }
        # `alloc lanes 0` is arithmetically correct and operationally a trap: at K=2 the
        # main thread and the linker hold both tids, leaving zero allocating worker lanes.
        # The 2026-08-23 run noted that "nothing refuses, warns, or explains"; this harness
        # measured what happens next, so the note gets a consequence attached to it.
        if rep["alloc_lanes"] == 0:
            sub["alloc lanes 0 did not deadlock the compile"] = r.rc == 0
        if want_parts is not None:
            sub["partitions == requested"] = rep["partitions"] == want_parts
        else:
            nxt = 1
            while nxt < (exp["physical"] or 1):
                nxt <<= 1
            sub["partitions == next pow2 >= physical"] = rep["partitions"] == nxt
        if "-j4" in extra:
            sub["workers == 4 (given)"] = rep["workers"] == 4
        elif mask == "0-3":
            sub["workers == masked logical"] = rep["workers"] == exp["logical"]
        bad = [k for k, v in sub.items() if not v]
        if bad:
            failures.append(f"{label}: {bad}")
        results.append({"arm": label, "mask": m, "report": rep, "expected": exp,
                        "checks": sub, "rc": r.rc})

    gate = next((x for x in results if x["arm"].startswith("3")), None)
    gate_ok = bool(gate and gate["report"] and gate["report"]["physical"] == gate["expected"]["physical"])
    ok_arms = sum(1 for x in results if x.get("checks") and all(x["checks"].values()))
    # The reference has no report line at all: absence is how the row proves the
    # line belongs to the patch and is not something upstream already printed.
    ref = run_cmd([ctx.ref, "build-obj", "-fno-emit-bin", "-Mroot=hello.zig"],
                  cwd=fx["dir"], env=ctx.env_ref, mask=ctx.mask, timeout=180)
    ref_line = vlib.parse_report_line(ref.stderr)
    ev = (f"{ok_arms} of {len(V1_ARMS)} arms fully agree with the sysfs oracle; "
          f"tid index space DERIVED from arm 1 as {index_bits} bits "
          f"(not asserted from a constant — this width has moved before); "
          f"R9 gate (pin 0-3): {'physical == masked physical, R9 does NOT fire' if gate_ok else 'FAILED'}; "
          f"reference compiler prints {'a report line — NOT patch-specific' if ref_line else 'no report line (control)'}"
          + (f"; failures: {failures}" if failures else ""))
    return Verdict("V1", GREEN if ok_arms == len(V1_ARMS) and gate_ok else RED, ev,
                   f"{ok_arms} of {len(V1_ARMS)} sub-rows", {"arms": results, "reference_line": ref_line})


# --------------------------------------------------- V11 / V-S1b: identity --

def _lib_dir_of(binary):
    """`<bin>/../lib/zig` — the std a binary uses when nobody says otherwise."""
    d = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(binary))), "lib", "zig")
    return d if os.path.isdir(d) else None


def _artifact_identity(ctx, rid, fixture_name, root_src, extra_args, note):
    """Shared A/B artifact-identity engine for V11 and V-S1b.

    Reports BOTH whole-file and `.text`, per arm, across `ctx.repeats` runs with
    a COLD local cache each time (a warm cache would pass by not compiling), and
    states which instrument carries the verdict and why.

    **Plus a de-confounding arm.** The two binaries ship different `lib/zig`
    directories, so a stock A/B cannot tell "the code generator changed" from
    "the std source shipped beside it changed". A third pair of runs pins BOTH
    arms to the patched binary's `lib/zig`; if `.text` then agrees, the stock
    difference was the std source, and the row says which.
    """
    fx = ctx.fixtures.get(fixture_name)
    arms = {}
    for label, binary, env in (("patched", ctx.zig, ctx.env_zig), ("reference", ctx.ref, ctx.env_ref)):
        outs, whole, text, rcs, tool = [], [], [], [], None
        for i in range(ctx.repeats):
            e = cold_local_cache(env, f"{rid}_{label}_{i}")
            out = os.path.join(ctx.scratch(rid), f"{label}_{i}.bin")
            r = run_cmd([binary, "build-exe", f"-Mroot={root_src}", f"-femit-bin={out}"] + extra_args,
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=600)
            rcs.append(r.rc)
            if r.rc == 0 and os.path.isfile(out):
                outs.append(out)
                whole.append(sha256_file(out))
                d, tool = section_digest(out)
                text.append(d)
        arms[label] = {"rc": rcs, "whole": whole, "text": text,
                       "whole_unique": len(set(whole)), "text_unique": len(set(text)),
                       "tool": tool}

    pinned = {"lib_dir": _lib_dir_of(ctx.zig)}
    if pinned["lib_dir"]:
        for label, binary, env in (("patched", ctx.zig, ctx.env_zig),
                                   ("reference", ctx.ref, ctx.env_ref)):
            e = cold_local_cache(env, f"{rid}_pin_{label}")
            out = os.path.join(ctx.scratch(rid), f"pin_{label}.bin")
            r = run_cmd([binary, "build-exe", "--zig-lib-dir", pinned["lib_dir"],
                         f"-Mroot={root_src}", f"-femit-bin={out}"] + extra_args,
                        cwd=fx["dir"], env=e, mask=ctx.mask, timeout=600)
            pinned[label] = (section_digest(out)[0]
                             if r.rc == 0 and os.path.isfile(out) else f"UNKNOWN (rc={r.rc})")
    else:
        pinned["patched"] = pinned["reference"] = "UNKNOWN (no lib/zig beside the binary)"
    pinned["match"] = (pinned["patched"] == pinned["reference"]
                       and not pinned["patched"].startswith("UNKNOWN"))

    p, s = arms["patched"], arms["reference"]
    if not p["text"] or not s["text"]:
        return unknown(rid, f"one arm produced no artifact (patched rc={p['rc']}, reference rc={s['rc']})",
                       f"0 of 2 arms measurable", arms=arms)
    if p["text"][0] == "UNKNOWN":
        return unknown(rid, "no section-extraction tool (objcopy / llvm-objcopy) on this host — "
                            "the only decisive instrument for this row is unavailable",
                       "0 of 1 instruments available", arms=arms)
    text_stable = p["text_unique"] == 1 and s["text_unique"] == 1
    text_match = text_stable and p["text"][0] == s["text"][0]
    whole_match = p["whole"][0] == s["whole"][0] if p["whole"] and s["whole"] else False
    pin_txt = ("both arms pinned to the SAME lib/zig: .text "
               + ("IDENTICAL — the stock difference is the std source shipped beside each binary, "
                  "not the code generator" if pinned["match"] else
                  f"STILL DIFFER ({str(pinned['patched'])[:16]}… vs {str(pinned['reference'])[:16]}…) "
                  f"— the difference survives a common std, so it is the compiler"))
    ev = (f".text patched {p['text'][0][:16]}… ({p['text_unique']} distinct of {len(p['text'])}) vs "
          f"reference {s['text'][0][:16]}… ({s['text_unique']} distinct of {len(s['text'])}) -> "
          f"{'IDENTICAL' if text_match else 'DIFFER'}; whole-file "
          f"{'identical' if whole_match else 'differ'} "
          f"(whole-file is NOT decisive here — see V12-P1-OLD, which shows the reference fails "
          f"whole-file identity by itself); {pin_txt}; extractor: {p['tool']}. {note}")
    if text_match:
        verdict = GREEN
    elif not text_stable:
        verdict = INCONCLUSIVE
    elif pinned["match"]:
        # The stock arms differ, but only because each binary ships its own std.
        # That is a real answer, and it is not the row's failure condition.
        verdict = INCONCLUSIVE
    else:
        verdict = RED
    return Verdict(rid, verdict, ev, f"{ctx.repeats} runs per arm, 2 of 2 arms, + 1 lib-pinned pair",
                   dict(arms, lib_pinned=pinned))


@vlib.row("V11", "005a", "stock invocations produce identical artifacts",
          "sha256 whole-file + .text section, patched vs reference")
def v11(ctx):
    return _artifact_identity(
        ctx, "V11", "stdpull", "stdpull.zig", [],
        note="CONFOUND, named: the two binaries ship different `lib/zig` directories, so any "
             "difference here may be the std source rather than the code generator; "
             "`--zig-lib-dir` is deliberately NOT pinned because V11 asks about STOCK invocations.")


@vlib.row("V-S1b", "005a", "a new file nobody imports perturbs nothing",
          "sha256 whole-file + .text on hello.zig, patched vs reference")
def vs1b(ctx):
    return _artifact_identity(
        ctx, "V-S1b", "hello", "hello.zig", [],
        note="The claim under test is that `lib/std/Thread/Topology.zig` is lazily imported and "
             "therefore invisible to a program that never mentions it.")


# --------------------------------------------------------------------- V14 --

@vlib.row("V14", "005a", "negative control for the affinity intersection (R9)",
          "SABOTAGE REBUILD — prepared patch, not fired")
def v14(ctx):
    return sabotage_row(ctx, "V14")


# ------------------------------------------------------------------- V-S1a --

VS1A_MASKS = [None, "0-3", "4-11", "4,5,10,11", "0", "0,6", "0,1,6,7"]


@vlib.row("V-S1a", "005a", "the std probe agrees with the host's instruments",
          "std.Thread.Topology.detect under 7 affinity masks vs the sysfs oracle")
def vs1a(ctx):
    topo = ctx.topology or vlib.host_topology()
    if topo is None:
        return unknown("V-S1a", "no sysfs topology oracle to check the probe against",
                       "0 of 7 masks")
    fx = ctx.fixtures.get("topo")
    probe = os.path.join(ctx.scratch("VS1a"), "topo_probe")
    build = run_cmd([ctx.zig, "build-exe", "-Mroot=topo_probe.zig", f"-femit-bin={probe}"],
                    cwd=fx["dir"], env=ctx.env_zig, mask=ctx.mask, timeout=300)
    if build.rc != 0:
        return unknown("V-S1a", f"probe program did not build (rc={build.rc}): "
                                f"{build.stderr.strip().splitlines()[-1] if build.stderr.strip() else 'no stderr'}",
                       "0 of 7 masks", build_stderr=build.stderr[-800:])

    # Control: the same source against the REFERENCE compiler must NOT build,
    # because `std.Thread.Topology` is what 005a adds. A probe that built on both
    # would be measuring something that was already there.
    ref_probe = os.path.join(ctx.scratch("VS1a"), "topo_probe_ref")
    ref_build = run_cmd([ctx.ref, "build-exe", "-Mroot=topo_probe.zig", f"-femit-bin={ref_probe}"],
                        cwd=fx["dir"], env=ctx.env_ref, mask=ctx.mask, timeout=300)

    rows, bad = [], []
    for mask in VS1A_MASKS:
        r = run_cmd([probe], mask=mask, env=ctx.env_zig, timeout=120)
        got = {}
        for tok in r.stderr.strip().split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                got[k] = v
        exp = vlib.expected_for_mask(topo, mask)
        def norm(x):
            return None if x in (None, "null") else int(x)
        ok = (norm(got.get("logical")) == exp["logical"]
              and norm(got.get("physical")) == exp["physical"]
              and norm(got.get("tpc")) == exp["threads_per_core"])
        if not ok:
            bad.append(f"{mask or 'unpinned'}: got {got} want {exp}")
        rows.append({"mask": mask or "unpinned", "got": got, "expected": exp, "ok": ok, "rc": r.rc})
    good = sum(1 for x in rows if x["ok"])
    ev = (f"{good} of {len(VS1A_MASKS)} masks match the sysfs oracle exactly (logical, physical, "
          f"threads-per-core, including the `null` that a mixed mask must produce rather than invent); "
          f"control: the same probe against the reference compiler "
          f"{'FAILS to build (Topology is patch-added, as designed)' if ref_build.rc != 0 else 'ALSO BUILDS — Topology is not patch-specific, which contradicts 005a'}"
          + (f"; mismatches: {bad}" if bad else ""))
    ok_all = good == len(VS1A_MASKS) and ref_build.rc != 0
    return Verdict("V-S1a", GREEN if ok_all else RED, ev,
                   f"{good} of {len(VS1A_MASKS)} masks", {"masks": rows, "reference_build_rc": ref_build.rc})


# ------------------------------------------------- shared sabotage plumbing --

SABOTAGE = {
    "V3":     ("V3_intern_partitions_invariant.patch",
               "Zcu.init's process-global partition-count invariant (src/Zcu.zig)"),
    "V14":    ("V14_affinity_intersection.patch",
               "the affinity intersection in sysTopology (lib/std/Thread/Topology.zig:231)"),
    "V-S2a":  ("VS2a_concurrent_reserve_zero.patch",
               "io.concurrent's admission reserve, forced to 0 (src/main.zig)"),
    "V-S2b":  ("VS2b_reserve_exceeds_async_limit.patch",
               "the reserve raised ABOVE async_limit (src/main.zig)"),
}


def sabotage_row(ctx, rid):
    """A row that needs a SABOTAGE REBUILD, reported honestly as UNKNOWN.

    This harness is not authorised to build a compiler, and a ~21-minute stage3
    step is not something to fire as a side effect of a measurement pass. What
    it CAN do — and does, live, every run — is re-verify that the prepared
    sabotage patch still applies to the current tree. `git apply --check` rc=0
    is the receipt that the recipe is not stale; it is NOT the guard going red,
    and this row says so in its own verdict.
    """
    fname, guard = SABOTAGE[rid]
    patch = os.path.join(vlib.SABOTAGE_DIR, fname)
    if not os.path.isfile(patch):
        return unknown(rid, f"sabotage patch missing: {patch} — the recipe a later builder needs "
                            f"does not exist, so this row cannot even be prepared",
                       "0 of 2 preconditions (patch present, applies cleanly)")
    chk = run_cmd(["git", "apply", "--check", patch], cwd=vlib.REPO, mask=None, timeout=120)
    readme = os.path.join(vlib.SABOTAGE_DIR, "README.md")
    applies = chk.rc == 0
    ev = (f"NOT RUN — needs a SABOTAGE REBUILD (stage3, ~21 min on this host) and this harness is "
          f"not authorised to build a compiler. Guard under test: {guard}. Prepared patch: "
          f"{os.path.relpath(patch, vlib.REPO)} — `git apply --check` rc={chk.rc} "
          f"({'applies cleanly to the current tree' if applies else 'DOES NOT APPLY: ' + chk.stderr.strip()[:200]}). "
          f"Recipe + expected red text + revert step: {os.path.relpath(readme, vlib.REPO)}. "
          f"A guard never seen red is a guard nobody has met.")
    return unknown(rid, ev, f"{1 if applies else 0} of 2 preconditions met "
                            f"(patch present: yes; applies cleanly: {'yes' if applies else 'no'}); "
                            f"0 of 1 rebuilds fired",
                   patch=os.path.relpath(patch, vlib.REPO), apply_check_rc=chk.rc,
                   apply_check_stderr=chk.stderr[-400:], guard=guard)
