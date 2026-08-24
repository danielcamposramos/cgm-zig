#!/usr/bin/env python3
"""Normalise a Helgrind log into a set of address-free stack-context signatures.

WHY THIS EXISTS. V12's direct instrument (ThreadSanitizer) cannot be built in this
estate (`linux/scc.h`, see docs/crown/BUILDING.md). Helgrind is the named substitute.
But Helgrind does not model Zig's futex-based `Io.Threaded` primitives, so it cannot
see most happens-before edges and its ABSOLUTE COUNT IS MEANINGLESS: measured on the
UNPATCHED promoted compiler, a trivial `build-obj -j2` produced

    ERROR SUMMARY: 146356 errors from 357 contexts (suppressed: 0 from 0)

with 1,171 frames naming InternPool.zig. It fails its own negative control exactly as
V12-OLD's byte-repro criterion did. So the count is not the instrument.

THE INSTRUMENT IS THE DIFFERENCE: the set of distinct stack-context signatures the
PATCHED binary produces that the REFERENCE binary does not, on an identical workload.
That requires signatures that are stable run to run, which means stripping everything
that varies by construction: pids, hex addresses, thread numbers, and the object
offsets Helgrind prints. What is left is the ordered list of `symbol (file:line)`
frames -- which is what actually identifies a race site.

CALIBRATION IS MANDATORY BEFORE USE. Run the reference against ITSELF first
(`--calibrate`). Whatever set difference two runs of the same binary produce is this
instrument's noise floor, and any patched-vs-reference difference at or below that
floor means nothing. An instrument whose noise floor has not been measured is not an
instrument; it is a number.
"""
import re
import sys
import hashlib
from collections import OrderedDict

PID = re.compile(r"^==\d+==\s?")
HEX = re.compile(r"0x[0-9A-Fa-f]+")
THREADNUM = re.compile(r"thread #\d+")
# `by 0xABC: symbol (file.zig:123)` -> we keep `symbol (file.zig:123)`
FRAME = re.compile(r"^\s*(?:at|by)\s+0x[0-9A-Fa-f]+:\s+(.*)$")
ERR_START = re.compile(
    r"^(Possible data race|Thread #\d+|---Thread-Announcement|"
    r"Lock at|Observed \(incorrect\)|.*conflicts with a previous)"
)


# `foo (bar.zig:123)` -> `foo (bar.zig)` when comparing across builds.
LINENO = re.compile(r"\(([^():]+):\d+\)")


def normalise_frame(text: str, fn_only: bool = False) -> str:
    text = HEX.sub("0xADDR", text)
    text = THREADNUM.sub("thread #N", text)
    # Drop the `(in /path/to/binary)` tail -- the path differs between the two
    # binaries under comparison BY CONSTRUCTION, and letting it into the signature
    # would make every context differ and report a fake 100% divergence.
    text = re.sub(r"\s*\(in [^)]*\)", "", text)
    if fn_only:
        # Anonymous-decl indices (`async__anon_1349146`, `spawn__anon_25805`) are assigned
        # per COMPILATION, so they differ between any two builds -- including two builds of
        # the same source. Measured: leaving them in held `shared` at 12 of ~450 across
        # builds where two runs of ONE binary shared 145-151. They carry no identity across
        # builds and must go before anything can be compared.
        text = re.sub(r"__anon_\d+", "__anon_N", text)
        # STRIP LINE NUMBERS when comparing two DIFFERENT BUILDS.
        #
        # Measured the hard way: comparing the patched compiler against the reference
        # with line numbers in the signature produced `shared: 0` out of 689 vs 674
        # contexts -- a fake 100% divergence, because the patch adds and moves source
        # lines and every frame therefore reports a different `file:line`. The
        # instrument was measuring the diff, not the runtime.
        #
        # Function+file granularity is coarser and says so: two distinct race sites
        # inside one function collapse to one signature. It is the finest granularity
        # that survives a source edit, which is the comparison actually being asked for.
        text = LINENO.sub(r"(\1)", text)
    return text.strip()


def contexts(path, fn_only=False):
    """Yield one signature per error block. A block is a run of lines between blank
    `==PID==` separators; its signature is the hash of its ordered frame list."""
    out = OrderedDict()
    cur = []
    with open(path, "r", errors="replace") as fh:
        for raw in fh:
            line = PID.sub("", raw.rstrip("\n"))
            if line.strip() == "":
                if cur:
                    sig = _sig(cur)
                    if sig:
                        out.setdefault(sig, cur[:6])
                    cur = []
                continue
            m = FRAME.match(line)
            if m:
                cur.append(normalise_frame(m.group(1), fn_only))
    if cur:
        sig = _sig(cur)
        if sig:
            out.setdefault(sig, cur[:6])
    return out


def _sig(frames):
    if not frames:
        return None
    joined = "\n".join(frames)
    return hashlib.sha256(joined.encode()).hexdigest()[:16]


def interesting(frames, pat):
    return any(pat.search(f) for f in frames)


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        print("usage: hgdiff.py <A.log> <B.log> [--filter REGEX]")
        return 2
    a_path, b_path = args[0], args[1]
    pat = re.compile(r"InternPool|Zcu|PerThread")
    if "--filter" in args:
        pat = re.compile(args[args.index("--filter") + 1])

    fn_only = "--fn-only" in args
    A = contexts(a_path, fn_only)
    B = contexts(b_path, fn_only)
    if fn_only:
        print("MODE: fn-only (line numbers stripped) — required when the two logs come "
              "from DIFFERENT BUILDS, because a source edit shifts every file:line.")
    only_a = [s for s in A if s not in B]
    only_b = [s for s in B if s not in A]
    fa = [s for s in only_a if interesting(A[s], pat)]
    fb = [s for s in only_b if interesting(B[s], pat)]

    print(f"A = {a_path}")
    print(f"B = {b_path}")
    print(f"contexts in A                 : {len(A)}")
    print(f"contexts in B                 : {len(B)}")
    print(f"shared                        : {len(set(A) & set(B))}")
    print(f"ONLY IN A (all)               : {len(only_a)}  of {len(A)}")
    print(f"ONLY IN B (all)               : {len(only_b)}  of {len(B)}")
    print(f"ONLY IN A matching filter     : {len(fa)}  of {len(only_a)}")
    print(f"ONLY IN B matching filter     : {len(fb)}  of {len(only_b)}")
    for s in fb[:10]:
        print(f"  [B-only] {s}")
        for fr in B[s][:4]:
            print(f"      {fr}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
