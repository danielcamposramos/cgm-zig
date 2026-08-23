#!/usr/bin/env python3
"""generate.py — every workload the V-list needs, built from nothing.

**Why generated and not committed.** The previous verification lane kept its
fixtures under `build-p005/vwork/`; an external cleaner destroyed one set
*between two commands* mid-run (PATCH005_VERIFICATION_RUN_2026-08-23.md,
"Estate conditions"). A harness that depends on surviving scratch is a harness
that reports UNKNOWN for reasons that have nothing to do with the compiler. So
every workload here is regenerated on demand, deterministically, from this file.
Nothing under `fixtures/` is committed except this generator and its `.gitignore`
— the fan-out alone is 1,201 files.

The workloads, and what each is for:

| name       | shape                                        | rows that use it |
|------------|----------------------------------------------|------------------|
| `hello`    | 3-line program, `std.debug.print`            | V2, V-S1b, V1    |
| `stdpull`  | `refAllDecls` over 15 std namespaces, ~10 MB | V11, V12 (.text) |
| `fanout`   | 1,200 leaf files imported by one root        | V5, V12 part 1a  |
| `modgraph` | cyclic (root->a->b->a) + acyclic (root->a)   | V9               |
| `multistep`| 6 executables, 13 build steps                | V10, V-S4a/b, V-BR |
| `topo`     | `std.Thread.Topology.detect` probe program   | V-S1a            |
| `selfhost` | `git archive HEAD src lib` — frozen snapshot | V7-SUB, V8, V13, V15 |

`selfhost` is a **frozen** snapshot on purpose. The live tree is shared with
other lanes: during this harness's own authoring, `src/main.zig` was mid-edit
and did not parse. Measuring an A/B against a workload that changes underneath
the arms is not an A/B. The snapshot is taken from `HEAD` (committed state) so
both arms compile byte-identical source.

Stdlib only. Run directly to (re)generate:  `python3 generate.py --all`
"""

import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
DEFAULT_ROOT = os.path.join(REPO, "build-vharness", "fixtures")

FANOUT_N = 1200
MULTISTEP_N = 6

HELLO = """\
const std = @import("std");
pub fn main() void {
    std.debug.print("hello\\n", .{});
}
"""

# Fifteen namespaces, chosen because `refAllDecls` over them analyses and codegens
# a large, stable slice of std without using any API whose shape moved in 0.16.
# Measured on the promoted 0.16.0 binary: rc=0, ~0.8 s, 10.2 MB artifact, and it
# reproduces the whole-file nondeterminism that invalidated V12's first criterion.
STDPULL = """\
const std = @import("std");
comptime {
    std.testing.refAllDecls(std.mem);
    std.testing.refAllDecls(std.fmt);
    std.testing.refAllDecls(std.hash);
    std.testing.refAllDecls(std.unicode);
    std.testing.refAllDecls(std.ascii);
    std.testing.refAllDecls(std.sort);
    std.testing.refAllDecls(std.math);
    std.testing.refAllDecls(std.base64);
    std.testing.refAllDecls(std.json);
    std.testing.refAllDecls(std.fs);
    std.testing.refAllDecls(std.process);
    std.testing.refAllDecls(std.Thread);
    std.testing.refAllDecls(std.compress);
    std.testing.refAllDecls(std.crypto);
    std.testing.refAllDecls(std.heap);
}
pub fn main() void {
    std.debug.print("stdpull {d}\\n", .{@sizeOf(usize)});
}
"""

TOPO_PROBE = """\
const std = @import("std");
pub fn main() !void {
    const t = try std.Thread.Topology.detect(.{});
    std.debug.print("logical={d} physical={?d} tpc={?d} source={t}\\n", .{
        t.logical, t.physical, t.threads_per_core, t.source,
    });
}
"""

MULTISTEP_BUILD = """\
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    inline for (.{ %s }) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(exe);
    }
}
"""

MULTISTEP_SRC = """\
const std = @import("std");
pub fn main() !void {
    var acc: u64 = %d;
    for (0..64) |k| acc +%%= @as(u64, @intCast(k)) *%% %d;
    std.debug.print("%s {d}\\n", .{acc});
}
"""


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    return path


def _fresh(d):
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d, exist_ok=True)
    return d


# ------------------------------------------------------------------ hello --

def gen_hello(root):
    d = _fresh(os.path.join(root, "hello"))
    _write(os.path.join(d, "hello.zig"), HELLO)
    return {"dir": d, "root_src": "hello.zig", "files": 1}


def gen_stdpull(root):
    d = _fresh(os.path.join(root, "stdpull"))
    _write(os.path.join(d, "stdpull.zig"), STDPULL)
    return {"dir": d, "root_src": "stdpull.zig", "files": 1}


def gen_topo(root):
    d = _fresh(os.path.join(root, "topo"))
    _write(os.path.join(d, "topo_probe.zig"), TOPO_PROBE)
    return {"dir": d, "root_src": "topo_probe.zig", "files": 1}


# ----------------------------------------------------------------- fanout --

def gen_fanout(root, n=FANOUT_N):
    """`n` leaf files, all imported by one root, all AstGen'd, minimal Sema.

    `comptime { _ = @import(...) }` is what makes this an AstGen fan-out rather
    than a Sema benchmark: the import resolves and the file is parsed + AstGen'd,
    and almost nothing else happens. That is precisely the phase 005b's A1 lane
    split rewrote, which is why V12's re-instrumented criterion runs here.
    """
    d = _fresh(os.path.join(root, "fanout"))
    for i in range(n):
        _write(os.path.join(d, f"f{i:05d}.zig"),
               f"pub const v: u64 = {i};\npub const name = \"f{i:05d}\";\n")
    lines = ["// Generated by partner_tools/vharness/fixtures/generate.py",
             f"// {n} leaf modules, each AstGen'd exactly once.",
             "comptime {"]
    lines += [f'    _ = @import("f{i:05d}.zig");' for i in range(n)]
    lines += ["}", "pub const marker: u64 = %d;" % n, ""]
    _write(os.path.join(d, "root.zig"), "\n".join(lines))
    return {"dir": d, "root_src": "root.zig", "files": n + 1, "leaves": n}


# --------------------------------------------------------------- modgraph --

def gen_modgraph(root):
    """The cyclic / acyclic PAIR. The acyclic half is V9's own control.

    A cycle counter that is stuck at a constant would pass a cyclic-only test.
    The pair is what proves the counter moves in both directions.
    """
    cyc = _fresh(os.path.join(root, "modgraph", "cyclic"))
    _write(os.path.join(cyc, "root.zig"),
           'const a = @import("a");\npub const v = a.v;\n')
    _write(os.path.join(cyc, "a.zig"),
           'const b = @import("b");\npub const v: u64 = b.w + 1;\n')
    _write(os.path.join(cyc, "b.zig"),
           'const a = @import("a");\npub const w: u64 = 1;\npub const back = @TypeOf(a);\n')

    acy = _fresh(os.path.join(root, "modgraph", "acyclic"))
    _write(os.path.join(acy, "root.zig"),
           'const a = @import("a");\npub const v = a.v;\n')
    _write(os.path.join(acy, "a.zig"), "pub const v: u64 = 1;\n")
    return {
        "cyclic": {"dir": cyc,
                   "args": ["--dep", "a", "-Mroot=root.zig",
                            "--dep", "b", "-Ma=a.zig",
                            "--dep", "a", "-Mb=b.zig"]},
        "acyclic": {"dir": acy,
                    "args": ["--dep", "a", "-Mroot=root.zig", "-Ma=a.zig"]},
    }


# -------------------------------------------------------------- multistep --

def gen_multistep(root, n=MULTISTEP_N):
    """`n` executables through `zig build` — the only fixture with real steps.

    n=6 gives 13 steps (6 compile + 6 install + the top-level install), which is
    the shape the previous lane measured V10, V-S4a/b and V-BR against; keeping
    it identical is what makes those numbers comparable across lanes.
    """
    d = _fresh(os.path.join(root, "multistep"))
    names = [f"m{i + 1}" for i in range(n)]
    _write(os.path.join(d, "build.zig"),
           MULTISTEP_BUILD % ", ".join(f'"{x}"' for x in names))
    for i, name in enumerate(names):
        _write(os.path.join(d, "src", f"{name}.zig"), MULTISTEP_SRC % (i + 1, i + 1, name))
    return {"dir": d, "executables": n, "expected_steps": 2 * n + 1, "names": names}


# --------------------------------------------------------------- selfhost --

def gen_selfhost(root, config_src=None):
    """Frozen `HEAD` snapshot of `src/` + `lib/` — the largest LAWFUL workload here.

    ~780 modules of real compiler front-end. It is the substitute the previous
    lane used for the V-list's private ~1,800-module product, and it is NOT a
    stand-in for V7a/V7b — see the V7-SUB row, which says so in its own verdict.
    """
    d = os.path.join(root, "selfhost")
    _fresh(d)
    tar = subprocess.run(f"git archive HEAD src lib | tar -x -C {d!r}",
                         shell=True, cwd=REPO, stderr=subprocess.PIPE)
    if tar.returncode != 0:
        return {"dir": d, "error": f"git archive failed: {tar.stderr.decode()[:300]}"}
    # `build_options` is a generated module, not source; take it from a build dir.
    cand = [config_src] if config_src else []
    cand += [os.path.join(REPO, "build-safe", "config.zig"),
             os.path.join(REPO, "build-p005", "config.zig")]
    chosen = next((c for c in cand if c and os.path.isfile(c)), None)
    if chosen is None:
        return {"dir": d, "error": "no config.zig (build_options module) found in any build dir"}
    shutil.copy2(chosen, os.path.join(d, "config.zig"))
    rev = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                         stdout=subprocess.PIPE, text=True).stdout.strip()
    return {"dir": d, "frozen_at": rev, "config_from": chosen,
            "args": ["-fno-emit-bin", "-OReleaseSafe", "-lc", "--zig-lib-dir", "lib/",
                     "--dep", "aro", "--dep", "build_options",
                     "-Mroot=src/main.zig", "-Maro=lib/compiler/aro/aro.zig",
                     "-Mbuild_options=config.zig"]}


# ------------------------------------------------------------------ driver --

GENERATORS = {
    "hello": gen_hello,
    "stdpull": gen_stdpull,
    "topo": gen_topo,
    "fanout": gen_fanout,
    "modgraph": gen_modgraph,
    "multistep": gen_multistep,
    "selfhost": gen_selfhost,
}


def manifest(root=DEFAULT_ROOT):
    """Manifests for fixtures ALREADY on disk, without rewriting a byte.

    `--no-regen` exists because the self-host snapshot is 268 MB and regenerating
    it between two rows of the same pass would change the workload underneath the
    arms. A fixture that is absent is simply absent from the result — an absent
    fixture must reach the row as a missing key, so the row can report UNKNOWN
    with a reason rather than silently measuring a stale tree.
    """
    out = {}
    for name in GENERATORS:
        d = os.path.join(root, name)
        if not os.path.isdir(d):
            continue
        if name == "fanout":
            leaves = len([f for f in os.listdir(d) if f.startswith("f") and f.endswith(".zig")])
            out[name] = {"dir": d, "root_src": "root.zig", "files": leaves + 1, "leaves": leaves}
        elif name == "modgraph":
            out[name] = {
                "cyclic": {"dir": os.path.join(d, "cyclic"),
                           "args": ["--dep", "a", "-Mroot=root.zig", "--dep", "b", "-Ma=a.zig",
                                    "--dep", "a", "-Mb=b.zig"]},
                "acyclic": {"dir": os.path.join(d, "acyclic"),
                            "args": ["--dep", "a", "-Mroot=root.zig", "-Ma=a.zig"]},
            }
        elif name == "multistep":
            src = os.path.join(d, "src")
            names = sorted(f[:-4] for f in os.listdir(src)) if os.path.isdir(src) else []
            out[name] = {"dir": d, "executables": len(names),
                         "expected_steps": 2 * len(names) + 1, "names": names}
        elif name == "selfhost":
            out[name] = {"dir": d, "frozen_at": "REUSED (--no-regen; not re-derived)",
                         "config_from": os.path.join(d, "config.zig"),
                         "args": ["-fno-emit-bin", "-OReleaseSafe", "-lc", "--zig-lib-dir", "lib/",
                                  "--dep", "aro", "--dep", "build_options",
                                  "-Mroot=src/main.zig", "-Maro=lib/compiler/aro/aro.zig",
                                  "-Mbuild_options=config.zig"]}
        else:
            root_src = {"hello": "hello.zig", "stdpull": "stdpull.zig",
                        "topo": "topo_probe.zig"}[name]
            out[name] = {"dir": d, "root_src": root_src, "files": 1}
    return out


def generate(root=DEFAULT_ROOT, which=None, quiet=True):
    """Generate the named fixtures (default: all). Returns {name: manifest}."""
    os.makedirs(root, exist_ok=True)
    names = which or list(GENERATORS)
    out = {}
    for name in names:
        if name not in GENERATORS:
            raise SystemExit(f"REFUSE: unknown fixture {name!r}; known: {sorted(GENERATORS)}")
        out[name] = GENERATORS[name](root)
        if not quiet:
            print(f"  {name}: {out[name]}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--only", default=None, help="comma-separated fixture names")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    which = a.only.split(",") if a.only else None
    print(f"generating fixtures under {a.root}")
    man = generate(a.root, which, quiet=False)
    total = sum(v.get("files", 0) for v in man.values() if isinstance(v, dict))
    print(f"OK: {len(man)} of {len(GENERATORS)} fixture sets generated "
          f"({total} leaf source files counted where a file count applies)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
