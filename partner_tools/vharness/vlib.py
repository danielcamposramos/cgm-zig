#!/usr/bin/env python3
"""vlib.py — primitives for the patch/005 V-list harness.

Everything in `rows_*.py` is written against these four ideas:

  1. **A row is a function that returns a `Verdict`.** GREEN / RED / UNKNOWN /
     INCONCLUSIVE, an evidence line, and a denominator — never a bare boolean.
     A row whose instrument is absent returns UNKNOWN *with the exact reason*.
     There is no code path in this file that can turn a missing instrument
     into a pass.
  2. **Rows register themselves.** `@vlib.row(...)` fills `ROWS`; nothing
     anywhere holds a hand-maintained list of rows. Adding a row is one
     decorator, and the driver, the `--list` output and the README table all
     see it immediately.
  3. **Timing is reported, not summarised.** `Timing` carries every raw sample,
     its rc, the median, min, max, IQR, stdev — and `compare()` states in words
     when a delta is inside the noise floor. `n = 1` reports stdev **UNKNOWN**,
     never `0.0`: one sample has no spread, and printing `0.0` would be a lie
     with a decimal point.
  4. **A/B is one code path.** Every timing comparison runs its two arms
     *alternated* (a, b, a, b, …) so a machine that gets busier during the run
     penalises both arms equally, and `paired_wins` counts slot-by-slot.

Stdlib only, per `partner_tools/README.md`. `--self-test` exercises the
statistics, the registry and the UNKNOWN discipline without touching a compiler.
"""

import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field, asdict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PARTNER_TOOLS = os.path.join(REPO, "partner_tools")
VHARNESS = os.path.join(PARTNER_TOOLS, "vharness")
SABOTAGE_DIR = os.path.join(VHARNESS, "sabotage")

# Everything the harness writes lands under a gitignored `build-*/` directory.
# Measured history (PATCH005_VERIFICATION_RUN_2026-08-23.md, "Estate conditions"):
# an external cleaner wiped `~/.cache/cgmzig-p005` and a scratchpad worktree
# mid-run and destroyed a lane's fixtures. Repo-local survived; $HOME did not.
WORK = os.path.join(REPO, "build-vharness")

DEFAULT_ZIG = os.path.join(REPO, "build-p005", "stage3", "bin", "zig")
DEFAULT_REF = os.path.join(REPO, "build-safe", "stage3", "bin", "zig")
DEFAULT_MASK = "4-11"

sys.path.insert(0, PARTNER_TOOLS)
import oracle_lib  # noqa: E402  — sha256_file / assert_anchor / revert_verified live there

sha256_file = oracle_lib.sha256_file

GREEN, RED, UNKNOWN, INCONCLUSIVE = "GREEN", "RED", "UNKNOWN", "INCONCLUSIVE"


# ---------------------------------------------------------------- verdicts --

@dataclass
class Verdict:
    """One row's answer. `denominator` is mandatory prose, not a number.

    House rule (`CONTRIBUTING-AI.md` receipt 4): every count carries its scope
    in the same sentence. `denominator` is where that scope goes — "4 of 4
    sub-rows", "5 runs of 5", "0 of 3 arms measurable".
    """
    row: str
    verdict: str
    evidence: str
    denominator: str
    detail: dict = field(default_factory=dict)

    def to_json(self):
        return asdict(self)


def unknown(row, reason, denominator="0 of 1 instruments available", **detail):
    """The only way this harness produces UNKNOWN — and it demands a reason."""
    if not reason or not reason.strip():
        raise ValueError("unknown() without a reason is exactly the thing this harness forbids")
    return Verdict(row, UNKNOWN, reason, denominator, detail)


# --------------------------------------------------------------- run context --

@dataclass
class Ctx:
    """Everything a row is allowed to know. Rows never read globals or argv.

    `zig` is the binary UNDER TEST; `ref` is the promoted/reference binary. Every
    A/B row uses the same two fields, which is why an A/B is one code path here
    and not two near-copies that drift.
    """
    zig: str
    ref: str
    repeats: int = 3
    det_runs: int = 5          # N for the determinism rows (V12); default 5 per the row
    mask: str = DEFAULT_MASK
    slow: bool = False
    workload: str = "selfhost"
    fixtures: dict = field(default_factory=dict)
    fixtures_root: str = ""
    time_report_json: str = None   # a pre-collected report supplied by the caller
    tr_probe: dict = field(default_factory=dict)   # {zig: probe result, ref: probe result}
    outdir: str = ""
    topology: dict = None
    env_zig: dict = field(default_factory=dict)
    env_ref: dict = field(default_factory=dict)

    def env_for(self, binary):
        return self.env_zig if binary == self.zig else self.env_ref

    def arm_label(self, binary):
        return "patched" if binary == self.zig else "reference"

    def scratch(self, *parts):
        d = os.path.join(self.outdir, *parts)
        os.makedirs(d, exist_ok=True)
        return d


# ---------------------------------------------------------------- registry --

@dataclass
class RowSpec:
    rid: str
    group: str
    title: str
    instrument: str
    fn: object
    slow: bool = False
    cost: str = "seconds"


ROWS = {}
ROW_ORDER = []


def row(rid, group, title, instrument, slow=False, cost="seconds"):
    """Self-registering row decorator. No hand list exists anywhere."""
    def deco(fn):
        if rid in ROWS:
            raise SystemExit(f"REFUSE: duplicate row id {rid!r} — two rows cannot share an id")
        ROWS[rid] = RowSpec(rid, group, title, instrument, fn, slow, cost)
        ROW_ORDER.append(rid)
        return fn
    return deco


# ------------------------------------------------------------- subprocesses --

@dataclass
class Run:
    cmd: list
    rc: int
    wall: float
    stdout: str
    stderr: str
    stderr_bytes: int
    timed_out: bool = False
    peak_rss_kb: int = None   # None means UNKNOWN, not zero

    @property
    def ok(self):
        return self.rc == 0 and not self.timed_out


def _decode(b):
    return b.decode("utf-8", errors="replace") if b is not None else ""


def run_cmd(cmd, cwd=None, env=None, mask=DEFAULT_MASK, timeout=300, rss=False):
    """Run `cmd`, always under `taskset -c <mask>` unless mask is None.

    `rss=True` wraps in `/usr/bin/time -v` to obtain peak RSS; if GNU time is
    absent the field stays None (UNKNOWN) rather than becoming 0.
    """
    full = list(cmd)
    time_out_file = None
    if rss:
        if os.path.isfile("/usr/bin/time"):
            time_out_file = os.path.join(WORK, "runs", f"time_{os.getpid()}_{time.time_ns()}.txt")
            os.makedirs(os.path.dirname(time_out_file), exist_ok=True)
            full = ["/usr/bin/time", "-v", "-o", time_out_file] + full
        # else: peak_rss_kb stays None — UNKNOWN, never 0
    if mask:
        full = ["taskset", "-c", mask] + full

    # `start_new_session` puts the child in its own process GROUP so a timeout can
    # kill the compiler AND its workers. Without it, `subprocess.run` kills only
    # `taskset` and a hung `zig` survives as an orphan — which is both a leak and a
    # charter violation waiting to happen (the next lane's courtesy check would see
    # a zig process nobody admits to starting). This harness only ever signals
    # process groups it created itself.
    t0 = time.monotonic()
    p = subprocess.Popen(full, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
        rc, to = p.returncode, False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(p.pid), 15)
            time.sleep(2)
            os.killpg(os.getpgid(p.pid), 9)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            out, err = p.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            out, err = b"", b""
        rc, to = 124, True
    wall = time.monotonic() - t0

    peak = None
    if time_out_file and os.path.isfile(time_out_file):
        m = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", open(time_out_file).read())
        if m:
            peak = int(m.group(1))
        os.remove(time_out_file)

    err_txt = _decode(err)
    return Run(full, rc, wall, _decode(out), err_txt, len(err or b""), to, peak)


def which(name):
    return shutil.which(name)


def machine_courtesy():
    """Report competing compile activity. Reports; never kills, never refuses.

    Charter: never kill a zig process this harness did not start. Contention is
    a fact that belongs on every timing row, not a reason to touch someone
    else's work.
    """
    p = subprocess.run(["pgrep", "-fa", r"ninja|zig build-exe|zig2 |cmake --build"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    lines = [l for l in _decode(p.stdout).splitlines() if "vharness" not in l and "pgrep" not in l]
    return (len(lines) > 0, lines)


# --------------------------------------------------------------- environment --

def multiarch_triple():
    """The Debian multiarch include dir, discovered rather than assumed."""
    for cand in sorted(os.listdir("/usr/include")) if os.path.isdir("/usr/include") else []:
        d = os.path.join("/usr/include", cand)
        if os.path.isdir(d) and os.path.isfile(os.path.join(d, "asm", "types.h")):
            return cand
    return None


LIBC_TEMPLATE = """\
# Generated by partner_tools/vharness — Debian multiarch remedy.
# `zig libc` reports sys_include_dir=/usr/include, but on Debian multiarch
# `asm/types.h` lives under /usr/include/<triple>/, so any -lc sub-compilation
# (libunwind first) fails with "'asm/types.h' file not found".
include_dir={inc}
sys_include_dir={sysinc}
crt_dir={crt}
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
"""


def ensure_libc_file(zig):
    """Return (path, provenance). Never silently absent: it is generated if lost.

    An external cleaner destroyed a previous lane's libc paths file *between two
    commands*. Depending on a surviving scratch file is therefore a known defect;
    this regenerates one when it is gone.
    """
    env_path = os.environ.get("ZIG_LIBC")
    if env_path and os.path.isfile(env_path):
        return env_path, f"$ZIG_LIBC (pre-existing) {env_path}"
    legacy = os.path.join(REPO, "build-p005", "vwork", "libc.txt")
    if os.path.isfile(legacy):
        return legacy, f"previous lane's file (survived) {legacy}"

    gen = os.path.join(WORK, "libc.txt")
    os.makedirs(WORK, exist_ok=True)
    triple = multiarch_triple()
    crt = ""
    p = subprocess.run([zig, "libc"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    for line in _decode(p.stdout).splitlines():
        if line.startswith("crt_dir="):
            crt = line.split("=", 1)[1]
    sysinc = f"/usr/include/{triple}" if triple else "/usr/include"
    with open(gen, "w") as f:
        f.write(LIBC_TEMPLATE.format(inc="/usr/include", sysinc=sysinc, crt=crt))
    return gen, f"GENERATED (multiarch triple: {triple or 'UNKNOWN — none found'})"


def harness_env(zig, local_cache=None, global_cache=None):
    """The environment every compiler invocation runs under.

    `ZIG_GLOBAL_CACHE_DIR` is forced repo-local: the default `~/.cache/zig` is a
    symlink into another project's tree on this station and lost artifacts
    mid-build (measured, PATCH005_VERIFICATION_RUN_2026-08-23.md).
    """
    env = os.environ.copy()
    libc, prov = ensure_libc_file(zig)
    env["ZIG_LIBC"] = libc
    env["ZIG_GLOBAL_CACHE_DIR"] = global_cache or os.path.join(WORK, "gcache")
    env["ZIG_LOCAL_CACHE_DIR"] = local_cache or os.path.join(WORK, "lcache")
    os.makedirs(env["ZIG_GLOBAL_CACHE_DIR"], exist_ok=True)
    os.makedirs(env["ZIG_LOCAL_CACHE_DIR"], exist_ok=True)
    env["_VH_LIBC_PROVENANCE"] = prov
    return env


def cold_local_cache(env, tag):
    """A fresh, empty local cache — the only way a determinism row means anything.

    A warm local cache makes run 2 a copy of run 1's artifact, which passes any
    identity test by not compiling. Returns a NEW env dict; the caller's is
    untouched.
    """
    d = os.path.join(WORK, "lcache_cold", f"{tag}_{time.time_ns()}")
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d, exist_ok=True)
    e = dict(env)
    e["ZIG_LOCAL_CACHE_DIR"] = d
    return e


# ----------------------------------------------------------------- digests --

def section_digest(path, section=".text"):
    """(digest, tool) for one ELF section. Returns ("UNKNOWN", None) if no tool.

    Tool identity is returned, not assumed: V12's re-instrumented criterion is
    only reproducible if the next reader knows which extractor produced the
    number.
    """
    for tool in ("objcopy", "llvm-objcopy"):
        exe = which(tool)
        if not exe:
            continue
        p = subprocess.run([exe, "-O", "binary", f"--only-section={section}", path, "/dev/stdout"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode == 0 and p.stdout:
            return hashlib.sha256(p.stdout).hexdigest(), tool
    return "UNKNOWN", None


def digest_set(paths):
    """{digest: [paths]} — the shape every identity row reports."""
    out = {}
    for p in paths:
        out.setdefault(sha256_file(p), []).append(os.path.basename(p))
    return out


# -------------------------------------------------------------- statistics --

@dataclass
class Timing:
    """Every raw sample survives into the report. Summaries never replace them."""
    label: str
    samples: list          # wall seconds, in run order
    rcs: list              # exit codes, same order
    peak_rss_kb: list = field(default_factory=list)

    @property
    def n(self):
        return len(self.samples)

    @property
    def median(self):
        return statistics.median(self.samples) if self.samples else None

    @property
    def lo(self):
        return min(self.samples) if self.samples else None

    @property
    def hi(self):
        return max(self.samples) if self.samples else None

    @property
    def spread(self):
        return (self.hi - self.lo) if self.samples else None

    @property
    def stdev(self):
        # n == 1 has NO spread. Reporting 0.0 would claim a precision that a
        # single sample cannot possibly carry.
        return statistics.stdev(self.samples) if self.n >= 2 else None

    @property
    def iqr(self):
        """(q1, q3) or None. Below n=4 the quartiles are not defined here."""
        if self.n < 4:
            return None
        qs = statistics.quantiles(self.samples, n=4, method="inclusive")
        return (qs[0], qs[2])

    @property
    def all_ok(self):
        return all(rc == 0 for rc in self.rcs) and bool(self.rcs)

    def line(self):
        def f(x):
            return "UNKNOWN" if x is None else f"{x:.3f}"
        iqr = self.iqr
        iqr_txt = f"[{iqr[0]:.3f}, {iqr[1]:.3f}]" if iqr else f"UNKNOWN (n={self.n} < 4)"
        rss = (f"; peak RSS {max(self.peak_rss_kb):,} KB" if self.peak_rss_kb
               else "; peak RSS UNKNOWN")
        return (f"{self.label}: n={self.n} median {f(self.median)}s "
                f"[{f(self.lo)}..{f(self.hi)}] spread {f(self.spread)}s "
                f"stdev {f(self.stdev)} IQR {iqr_txt} "
                f"rc {sorted(set(self.rcs))} raw {[round(s, 3) for s in self.samples]}{rss}")

    def to_json(self):
        return {
            "label": self.label, "n": self.n, "samples": self.samples, "rcs": self.rcs,
            "median": self.median, "min": self.lo, "max": self.hi, "spread": self.spread,
            "stdev": self.stdev, "iqr": list(self.iqr) if self.iqr else None,
            "peak_rss_kb": self.peak_rss_kb or None,
        }


def paired_wins(a: Timing, b: Timing):
    """How often arm A beat arm B in the SAME alternation slot.

    Slot-paired, because the arms were alternated: slot i of both arms saw the
    same machine weather. Returns (a_wins, pairs).
    """
    pairs = min(a.n, b.n)
    return sum(1 for i in range(pairs) if a.samples[i] < b.samples[i]), pairs


def compare(a: Timing, b: Timing):
    """A/B verdict material with the noise floor stated in words.

    Returns a dict; `inside_noise` is True when the median delta is no larger
    than the larger arm's stdev, or when the IQRs overlap. A caller that ignores
    `note` and quotes only `delta_pct` is misreporting, and the note says so.
    """
    d = {"a": a.label, "b": b.label}
    if not a.samples or not b.samples:
        d["note"] = "UNKNOWN — one arm produced no samples"
        d["inside_noise"] = None
        return d
    delta = b.median - a.median
    d["delta_s"] = delta
    d["delta_pct"] = 100.0 * delta / a.median if a.median else None
    d["ratio"] = (b.median / a.median) if a.median else None
    wins, pairs = paired_wins(a, b)
    d["a_paired_wins"] = wins
    d["pairs"] = pairs

    floors = [x for x in (a.stdev, b.stdev) if x is not None]
    floor = max(floors) if floors else None
    ia, ib = a.iqr, b.iqr
    overlap = None
    if ia and ib:
        overlap = not (ia[1] < ib[0] or ib[1] < ia[0])
    d["iqr_overlap"] = overlap

    if floor is None:
        d["inside_noise"] = None
        d["note"] = (f"noise floor UNKNOWN (n={min(a.n, b.n)}; a single sample has no spread) "
                     f"— the delta of {delta:+.3f}s is NOT yet a measurement")
    else:
        inside = abs(delta) <= floor or bool(overlap)
        d["inside_noise"] = inside
        d["note"] = (
            f"delta {delta:+.3f}s ({d['delta_pct']:+.2f}%), noise floor (max stdev) {floor:.3f}s, "
            f"IQR overlap {overlap}, {a.label} won {wins} of {pairs} paired slots — "
            + ("INSIDE the noise floor: this is a note, not a claim"
               if inside else "OUTSIDE the noise floor on this host"))
    # Complete separation is the one cheap non-parametric fact worth stating.
    if a.samples and b.samples:
        d["complete_separation"] = (max(a.samples) < min(b.samples)) or (max(b.samples) < min(a.samples))
    return d


def alternate_ab(fn_a, fn_b, repeats, label_a="A", label_b="B", rss=False):
    """Run A and B alternated, `repeats` times each. One code path for every row.

    `fn_x(i)` must return a `Run`. Alternation is the entire defence against a
    machine whose load drifts during the pass.
    """
    ta = Timing(label_a, [], [], [])
    tb = Timing(label_b, [], [], [])
    for i in range(repeats):
        for fn, t in ((fn_a, ta), (fn_b, tb)):
            r = fn(i)
            t.samples.append(r.wall)
            t.rcs.append(r.rc if not r.timed_out else 124)
            if r.peak_rss_kb is not None:
                t.peak_rss_kb.append(r.peak_rss_kb)
    return ta, tb


# --------------------------------------------------------------- workloads --

def workload(ctx, name=None):
    """(cwd, args, description) for a compiler-side workload, by name.

    One place decides what "the workload" means, so V7-SUB, V8, V13 and V15 are
    all measuring the same thing and their numbers can be compared.
    """
    name = name or ctx.workload
    fx = ctx.fixtures.get(name)
    if not fx:
        return None
    if name == "selfhost":
        if "error" in fx:
            return None
        return (fx["dir"], list(fx["args"]),
                f"self-hosted front-end pass over a FROZEN snapshot of this repo's own "
                f"src/ + lib/ at {fx.get('frozen_at', 'UNKNOWN')[:12]} (~780 modules)")
    if name == "stdpull":
        return (fx["dir"], ["-fno-emit-bin", "-Mroot=stdpull.zig"],
                "refAllDecls over 15 std namespaces (a std-pulling front-end pass)")
    if name == "fanout":
        return (fx["dir"], ["-fno-emit-bin", "-Mroot=root.zig"],
                f"{fx.get('leaves', '?')}-file AstGen fan-out")
    return None


# ------------------------------------------------------------------ probes --

TIME_REPORT_SCHEMA = "cgm-zig.time-report.v1"


def probe_time_report(zig, env, workdir):
    """Is a machine-readable time report obtainable from THIS binary?

    Three honest answers, never a guess:
      * "json"            — `--time-report-json <path>` exists and wrote the file
      * "listen-required" — `--time-report` exists but is refused without --listen
                            (`src/main.zig:3106`), i.e. unobtainable in batch
      * "absent"          — the flag is not recognised at all
    """
    os.makedirs(workdir, exist_ok=True)
    src = os.path.join(workdir, "probe_tr.zig")
    with open(src, "w") as f:
        f.write("pub fn main() void {}\n")
    out = os.path.join(workdir, "probe_tr.json")
    if os.path.exists(out):
        os.remove(out)
    r = run_cmd([zig, "build-obj", "-fno-emit-bin", "--time-report",
                 "--time-report-json", out, "-Mroot=probe_tr.zig"],
                cwd=workdir, env=env, timeout=120)
    if os.path.isfile(out):
        try:
            data = json.load(open(out))
        except Exception as e:
            return {"status": "absent", "detail": f"--time-report-json wrote unparseable JSON: {e}"}
        schema = data.get("schema", "UNKNOWN")
        return {"status": "json", "detail": f"schema {schema}", "keys": sorted(data.keys())}
    blob = (r.stderr + r.stdout)
    if "--time-report requires --listen" in blob:
        return {"status": "listen-required",
                "detail": "`--time-report requires --listen` (src/main.zig:3106) — the report is "
                          "IPC-only on this binary, and `zig build --time-report` starts a "
                          "blocking web server, so no batch run can collect it"}
    if "unrecognized" in blob.lower() or "unknown command" in blob.lower():
        return {"status": "absent", "detail": f"flag not recognised: {blob.strip().splitlines()[:1]}"}
    return {"status": "absent", "detail": f"no JSON written, rc={r.rc}, stderr[:200]={blob[:200]!r}"}


def read_time_report(path):
    """Parse a time-report JSON, or return None. Schema is checked, not assumed."""
    if not path or not os.path.isfile(path):
        return None
    try:
        data = json.load(open(path))
    except Exception:
        return None
    return data if isinstance(data, dict) else None


# --------------------------------------------------- report-line parsing ----

REPORT_RE = re.compile(
    r"threads: topology (?P<phys>\d+|UNKNOWN) physical / (?P<log>\d+) logical"
    r"(?:, (?P<tpc>\d+) threads per core)?"
    r" \(probe: (?P<probe>[^)]+)\); "
    r"workers (?P<workers>\d+) \((?P<workers_src>[^)]+)\); "
    r"intern partitions (?P<parts>\d+) \((?P<parts_src>[^)]+)\); "
    r"alloc lanes (?P<lanes>\d+)[^;]*; "
    r"(?P<items>[\d,]+) items per partition"
)


def parse_report_line(stderr):
    """The ThreadPlan report line as a dict, or None if the line is absent.

    Absence is a datum: the reference compiler has no such line, and that is how
    a row proves the line belongs to the patch.
    """
    m = REPORT_RE.search(stderr)
    if not m:
        return None
    d = m.groupdict()
    out = {
        "physical": None if d["phys"] == "UNKNOWN" else int(d["phys"]),
        "logical": int(d["log"]),
        "threads_per_core": int(d["tpc"]) if d["tpc"] else None,
        "probe": d["probe"],
        "workers": int(d["workers"]),
        "workers_source": d["workers_src"],
        "partitions": int(d["parts"]),
        "partitions_source": d["parts_src"],
        "alloc_lanes": int(d["lanes"]),
        "items": int(d["items"].replace(",", "")),
        "raw": m.group(0),
    }
    return out


DEFAULT_INDEX_BITS = 30
"""The tid index-space width at the time of writing. **Not trusted.**

`ThreadPlan` owns this number and it has already moved once (`index_bits`
30 -> 31, which doubles every published ceiling). So V1 DERIVES the width from
the compiler's own unpinned report line via `derive_index_bits` and checks the
other arms against that, instead of asserting a constant that a future commit
turns into a false red.
"""


def ceil_log2(n):
    bits = 0
    while (1 << bits) < n:
        bits += 1
    return bits


def expected_items(partitions, index_bits=DEFAULT_INDEX_BITS):
    """Items per partition: the index space carved by the next power of two >= partitions.

    At `index_bits = 30`: 8 -> 134,217,727; 2 -> 536,870,911; 4 -> 268,435,455;
    12 -> 67,108,863. Deriving it is the point — a hand-copied table agrees with
    itself, not with the compiler.
    """
    return (1 << (index_bits - ceil_log2(partitions))) - 1


def derive_index_bits(items, partitions):
    """Recover the index-space width from one observed (items, partitions) pair.

    Returns None when the numbers are not of the form `2^k - 1` for an exact
    carve — which is itself a finding, not a reason to guess.
    """
    total = (items + 1) * (1 << ceil_log2(partitions))
    if total <= 0 or (total & (total - 1)) != 0:
        return None
    return total.bit_length() - 1


RANK_RE = re.compile(
    r"analysis order (?P<order>\w+) \([^)]*\): (?P<mods>\d+) modules ranked, "
    r"max depth (?P<depth>\d+), (?P<cycles>\d+) in import cycles")


def parse_rank_line(stderr):
    m = RANK_RE.search(stderr)
    if not m:
        return None
    return {"order": m.group("order"), "modules": int(m.group("mods")),
            "max_depth": int(m.group("depth")), "cycles": int(m.group("cycles")),
            "raw": m.group(0)}


# --------------------------------------------------------- host topology ----

def host_topology():
    """Sibling groups from sysfs — the oracle every topology row is checked against."""
    base = "/sys/devices/system/cpu"
    groups = {}
    if not os.path.isdir(base):
        return None
    for name in os.listdir(base):
        m = re.fullmatch(r"cpu(\d+)", name)
        if not m:
            continue
        f = os.path.join(base, name, "topology", "thread_siblings_list")
        if not os.path.isfile(f):
            continue
        groups.setdefault(open(f).read().strip(), set()).add(int(m.group(1)))
    if not groups:
        return None
    sib = sorted(tuple(sorted(v)) for v in groups.values())
    logical = sum(len(g) for g in sib)
    return {"logical": logical, "physical": len(sib), "sibling_groups": [list(g) for g in sib]}


def parse_mask(spec, logical):
    """`taskset` mask spec -> set of CPU ids. None means unpinned (all)."""
    if spec is None:
        return set(range(logical))
    out = set()
    for part in spec.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            out.update(range(int(lo), int(hi) + 1))
        else:
            out.add(int(part))
    return out


def expected_for_mask(topo, mask_spec):
    """What a correct affinity-masked probe MUST answer for this mask.

    Derived from sysfs, independently of the compiler under test — which is the
    whole definition of an oracle (`partner_tools/oracle_conventions.md`).
    """
    cpus = parse_mask(mask_spec, topo["logical"])
    groups = [set(g) & cpus for g in topo["sibling_groups"]]
    groups = [g for g in groups if g]
    sizes = {len(g) for g in groups}
    return {
        "logical": len(cpus),
        "physical": len(groups),
        "threads_per_core": sizes.pop() if len(sizes) == 1 else None,
    }


# --------------------------------------------------------------- self-test --

def self_test():
    checks = []

    t1 = Timing("A", [1.0, 2.0, 3.0], [0, 0, 0])
    checks.append(("median of 3", t1.median == 2.0))
    checks.append(("stdev present at n=3", t1.stdev is not None))
    checks.append(("IQR UNKNOWN at n=3 (never fabricated)", t1.iqr is None))

    t2 = Timing("B", [5.0], [0])
    checks.append(("stdev UNKNOWN at n=1, NOT 0.0", t2.stdev is None))
    checks.append(("n=1 line says UNKNOWN", "UNKNOWN" in t2.line()))

    t4 = Timing("C", [1.0, 2.0, 3.0, 4.0], [0] * 4)
    checks.append(("IQR defined at n=4", t4.iqr is not None))

    a = Timing("a", [10.0, 10.1, 9.9], [0, 0, 0])
    b = Timing("b", [10.05, 10.2, 9.95], [0, 0, 0])
    c = compare(a, b)
    checks.append(("tiny delta flagged inside noise", c["inside_noise"] is True))
    checks.append(("compare states the noise floor in words", "noise floor" in c["note"]))
    w, n = paired_wins(a, b)
    checks.append(("paired wins carry a denominator", n == 3 and 0 <= w <= 3))

    big_a = Timing("a", [10.0, 10.0, 10.0], [0, 0, 0])
    big_b = Timing("b", [20.0, 20.0, 20.0], [0, 0, 0])
    cb = compare(big_a, big_b)
    checks.append(("complete separation detected", cb["complete_separation"] is True))

    c1 = compare(Timing("a", [1.0], [0]), Timing("b", [2.0], [0]))
    checks.append(("n=1 comparison refuses to claim", c1["inside_noise"] is None and "NOT yet a measurement" in c1["note"]))

    fired = False
    try:
        unknown("Vx", "")
    except ValueError:
        fired = True
    checks.append(("UNKNOWN without a reason REFUSED", fired))

    checks.append(("expected_items(8) == 134,217,727", expected_items(8) == 134_217_727))
    checks.append(("expected_items(2) == 536,870,911", expected_items(2) == 536_870_911))
    checks.append(("expected_items(4) == 268,435,455", expected_items(4) == 268_435_455))
    checks.append(("expected_items(12) == 67,108,863", expected_items(12) == 67_108_863))

    line = ("info: threads: topology 6 physical / 8 logical (probe: sys_topology); "
            "workers 8 (derived: logical); intern partitions 8 (derived: physical, rounded up "
            "to a power of two); alloc lanes 6 (= partitions - 2, main + linker reserved); "
            "134,217,727 items per partition; override with -j<N> --intern-partitions=<N|logical>")
    p = parse_report_line(line)
    checks.append(("report line parses", p is not None and p["partitions"] == 8 and p["logical"] == 8))
    checks.append(("absent report line -> None (a datum, not a crash)", parse_report_line("nothing here") is None))

    rk = parse_rank_line("info: analysis order layered (given): 4 modules ranked, max depth 3, 1 in import cycles")
    checks.append(("rank line parses", rk is not None and rk["cycles"] == 1))

    topo = {"logical": 12, "physical": 6,
            "sibling_groups": [[0, 6], [1, 7], [2, 8], [3, 9], [4, 10], [5, 11]]}
    e = expected_for_mask(topo, "0-3")
    checks.append(("oracle: mask 0-3 is 4 logical / 4 physical", e["logical"] == 4 and e["physical"] == 4))
    e2 = expected_for_mask(topo, "4-11")
    checks.append(("oracle: mask 4-11 is 8 logical / 6 physical, tpc UNKNOWN",
                   e2["logical"] == 8 and e2["physical"] == 6 and e2["threads_per_core"] is None))

    passed = sum(1 for _, ok in checks if ok)
    for name, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    print(f"SELF-TEST: {passed}/{len(checks)} checks passed")
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    print(__doc__)
