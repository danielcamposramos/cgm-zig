---
name: cgm-zig
description: Working in the cgm-zig fork — the AI-friendly patchset fork of Zig 0.16.0. Load this before editing, patching, verifying, or committing anything in this repository. Carries the fork's laws, the doc map, the receipt standard, and the proven workflows (repro runs, oracles, bisection, building the safe compiler).
---

# cgm-zig — working in the fork

This repository is a patchset fork of Zig 0.16.0, maintained by EchoSystems AI
Studios. It exists because a real frontend bug had no lawful upstream channel
for AI-diagnosed work — read `PROVENANCE.md` first if you are new; it is the
why of everything here. AI partners are welcome as senior contributors:
`CONTRIBUTING-AI.md` is the contract, and its one law governs you too —
**receipts, always.**

## The laws (paste-block — carry these into any sub-task you brief)

- **git is lawful in THIS repository only.** If you also work in a private
  parent project, its no-git law is untouched — never run git outside this
  repo's root.
- **Zero private-project identifiers.** No names, paths, or code from any
  private estate in any file, commit message, or prompt here. Describe
  motivating workloads generically ("a ~1,800-module hyper-modular project").
- **Rebase-friendly, additive-only.** Patches are minimal diffs against the
  verbatim upstream base (the repo's root commit, checksum-anchored). New
  behavior hides behind new flags; stock invocations behave stock. No language
  divergence. If upstream fixes a defect we patched, our patch retires.
- **ReleaseSafe posture.** The working compiler is built with safety checks ON
  (`build-safe/stage3/bin/zig`). Failures must name themselves; a silent crash
  is itself a bug to fix.
- **Machine courtesy.** Never rebuild the compiler or fire a whole-closure
  compile while another long build owns the machine. Check first:
  `pgrep -fa 'zig build-exe|ninja|cgm build'` — if a long-running compile is
  live, author and parse only; queue compile-verification.
- **Sequential pushes.** `git pull --ff-only origin main` before every push;
  on a race, pull and retry. Never force-push.
- **No `rm`.** Move aside (`mv foo foo.aside-<date>`) instead of deleting;
  scratch included.
- **Every count carries its denominator; absent instruments report UNKNOWN,
  never zero.** (The partner tools below already behave this way — compose
  them instead of hand-rolling status checks.)

## Doc map

| File | What it is |
|---|---|
| `PROVENANCE.md` | The full story, credit chain, version policy, commitments |
| `CONTRIBUTING-AI.md` | The receipt/provenance/review standard — the contract |
| `README.md` / `README.upstream.md` | Fork front door / upstream's original |
| `docs/crown/PLAN.md` | The staged roadmap (observability → tooling → cache → tiles) |
| `docs/crown/DOCTRINE.md` | Seven design principles the fork builds by |
| `docs/crown/INTERNALS_MAP.md` | Compiler internals map with file:line citations |
| `docs/crown/BUILDING.md` | **Build recipe + every gotcha with its negative control. Read before any build.** |
| `partner_tools/` | Python tooling for status, repro, oracles, patch ledger |

## Workflows (each proven in this repo's history — see the commits they cite)

**Check the fork's state (always first):**
`python3 partner_tools/fork_status.py` — toolchain presence/version/sha,
patchset-vs-base summary, tree cleanliness. UNKNOWN is an answer; trust it
over assumptions.

**Run a reproduction:**
`python3 partner_tools/repro.py <args-file> [--zig <binary>] [--subcommand build-exe]`
— fires the compile under `/usr/bin/time -v`, captures full stderr, prints the
receipt block (wall / peak RSS / exit / signal / stderr bytes). Stored
args-files from `zig build` live in the target project's `.zig-cache/args/`;
`--listen=-` is stripped automatically on a temp copy (the flag binds the
compiler to build-runner IPC and hangs a standalone run).

**Verify with oracles:** read `partner_tools/oracle_conventions.md` and
compose `partner_tools/oracle_lib.py`. The idiom, always: measure PRE →
change → measure POST → fire a negative control (sabotage a scratch copy,
watch the check go red) → revert, sha-verified. A guard never seen red is
untrusted.

**Bisect a scale-dependent crash:** do not delete `-M` modules from an
args-file (dependency resolution dies in seconds — measured). Use the
stub-root shape: swap the root module for a generated stub whose `--dep` list
names the subset, keeping all declarations resolvable. Expect saturation if
the cause is accumulation rather than one construct — an isolation ladder
(tiny / medium / full closure) distinguishes the two cheaply.

**Build the safe compiler — read `docs/crown/BUILDING.md` FIRST.** It carries the
full recipe and every gotcha with its negative control. The short form:
- Plain source tarball + system LLVM (Debian: `llvm-21`, `liblld-21-dev`,
  `libclang-21-dev` — the runtime `libclang-cpp.so` alone is NOT enough),
  cmake + ninja, `-DCMAKE_BUILD_TYPE=ReleaseSafe`.
- **`-Ddebug-extensions` is not optional** — the crash-report machinery
  ("Analyzing <file>") is compiled out without it, and that machinery is the
  point of a diagnostic build.
- **`ZIG_LIBC` is mandatory on Debian multiarch.** `zig libc` reports
  `sys_include_dir=/usr/include`, but `asm/types.h` lives in
  `/usr/include/x86_64-linux-gnu`, so the bundled libunwind sub-compilation
  fails with `'asm/types.h' file not found`. Write a libc paths file with
  `sys_include_dir=/usr/include/x86_64-linux-gnu` and export `ZIG_LIBC` — it is
  read at `main.zig:1049` and reaches every sub-compilation. Proven by negative
  control on the *unpatched* compiler: without it `rc=1`, with it `rc=0`.
- **Set `ZIG_GLOBAL_CACHE_DIR` / `ZIG_LOCAL_CACHE_DIR` to repo-local `build-*/`
  paths.** The default `~/.cache/zig` may be a symlink into another tree, and an
  external cleaner has destroyed a lane's `/tmp` scratch mid-run. Never `/tmp`.
- Wall time: ~8–9 min unconstrained on an idle 12-core host; **≈41 min under an
  8-CPU `taskset` mask on a contended one.** Quote the mask with the number.
  Respect machine courtesy.
- **ThreadSanitizer does not build here** — `linux/scc.h` is no longer shipped by
  Debian, and TSan asserts on the struct sizes that header provides, so a shim is
  not lawful. Any TSan-instrumented row is UNRUNNABLE; say so by name.

**Type-check without building (~45 s — the cheap oracle):**
`zig build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ --dep aro
--dep build_options -Mroot=src/main.zig -Maro=lib/compiler/aro/aro.zig
-Mbuild_options=<build-*/config.zig>`. Runs on the promoted binary, works on any
branch via `git worktree`. It proves the tree compiles and **nothing about
behaviour**. This is how `main` was found to have been un-buildable for a full
day without anyone meeting it.

**Land a change:** receipts per `CONTRIBUTING-AI.md`, commit body carries
who-did-what and any reviewer objections + resolutions,
`Co-Authored-By:` trailers for every author, `Upstream-Status:` line for
patches to upstream code (`not-filed-policy` / `filed:<url>` / `fixed-upstream`).
