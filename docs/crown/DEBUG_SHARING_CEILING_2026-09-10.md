# What "one shared debug artifact" is actually worth — measured before building it

*Measured 2026-09-10 by the Opus compiler partner. Packet P3a of
`NEXT_WAVE_PLAN_2026-09-10.md`: price the requested enhancement with an existing
tool before writing any compiler code. **No compiler change, no rebuild, no new
fixture.** Read-only on copies; the source artifacts are untouched and verified.*

## Why this measurement exists

Stage 2b — one shared debug artifact across a build sweep — is the enhancement
the maintainer asked for and the one `PLAN.md`'s 2026-09-08 scope correction says
is **not implemented**. Everything written about its value so far has been an
estimate. `dwz` 0.17 is installed on this station and its `-m` mode does exactly
the thing 2b describes — duplicated DIEs moved into one file that every binary
references through `.gnu_debugaltlink` — so the prize can be measured today,
at zero risk, before a design commits to a mechanism.

This does **not** implement stage 2b, and dwz is **not** proposed as the
mechanism: `PLAN.md` is explicit that "compression after emission is not
deduplication before emission." dwz is used here strictly as an **oracle**.

## Method

Two separately compiled substantive consumers from the existing evidence root,
both `-OReleaseSafe`, both through LLVM + LLD (the backend the consuming project
actually uses):

- `R9_c1_1` — the two-module consumer (`scale_root.zig` + `scale_modb.zig`)
- `R9_c2_1` — a different program sharing most of `std`

Both were **copied** into a working directory; dwz never saw an original. Verified
after the run: source sha256 `d3a41085cddfe6a8…` and `4a7836c48e2e8bff…`,
unchanged. Sizes are the sum of every `.debug*` section from
`size --format=sysv -A`.

Three arms:

1. **baseline** — as emitted.
2. **`dwz <file>`** — per-binary dedup only. No sharing between binaries. This is
   the part a project gets today with no compiler work at all.
3. **`dwz -m shared.debug c1 c2`** — one shared debug body, both binaries
   referencing it. This is the shape stage 2b describes.

## Result

| Arm | combined `.debug*` | vs baseline |
|---|---|---|
| baseline | 6,025,640 | — |
| `dwz` per-file (no sharing) | 5,500,680 | **−8.71%** |
| `dwz -m` (one shared body) | 5,254,357 | **−12.80%** |
| ↳ of which the shared body itself | 308,478 | paid once |

The shared reference is real and present, not inferred:
`readelf -x .gnu_debugaltlink c1_m` → `shared.debug`, and the file exists at
309,135 bytes on disk.

**Separate the two effects, because they need very different work:**

- **8.71 points need no sharing at all** — that is one binary deduplicating
  against itself. A project can have it today from an existing tool.
- **4.09 points at N=2 are what sharing between binaries actually bought.**

## Extrapolation, and its limit

The per-binary cost stays; the shared body is paid once. For N binaries over this
same closure:

| N | per-file total | multifile total | saving from sharing |
|---|---|---|---|
| 2 | 5,501,230 | 5,255,464 | 4.47% |
| 10 | 27,506,150 | 25,043,408 | 8.95% |
| 100 | 275,061,500 | 247,657,778 | 9.96% |
| 1000 | 2,750,615,000 | 2,473,801,478 | 10.06% |
| ∞ | — | — | **10.07%** |

Against **raw** baseline debug bytes the asymptote for all dwz-class work
together is **17.91%**.

So the honest headline: **on this fixture pair, sharing debug bodies between
binaries is worth about ten percent of debug bytes, and it saturates by N≈100.**

## The number that matters most, and why it is not larger

`CROSS_PROCESS_SIGNATURE.md` measured the **self-hosted** emitter's linked output
and found a duplicated `std` compile unit worth 2.6% of `.debug_info`, alongside
the observation that "every binary a project links carries its own ~1.46 MB `std`
CU". It is tempting to read that as a very large shareable fraction.

On the backend that actually matters it is not available in that form.
Re-measured here: `R9_c1_1` and `R9_c2_1` each have exactly **2 compile units**
(the program and `compiler_rt`). The LLVM path emits **one CU covering the whole
program**, so there is no separate `std` CU to share, and — as
`CGM_ACTUAL_BACKEND.md` already stated — "each binary's single CU is unique to
that compilation. Whatever is reusable is BELOW the CU."

Below the CU is exactly where dwz works, and dwz found 10.07%. That is the
measured value of **post-emission** reference-based sharing on the real backend.

**This bounds one mechanism, not the stage.** A before-emission shared module —
C6's arm (c), the `-gmodules` / split-DWARF shape where a module's types are
emitted **once** into a shared artifact and every consumer carries a skeleton
reference — is a different mechanism with a different ceiling, because it makes
the shared bodies identical by construction instead of hoping a deduper finds
them identical after the fact. Nothing here measures that ceiling. What this
measurement does establish is that **the post-emission route cannot be the
answer**: if 2b is built as "emit as today, deduplicate afterwards", roughly ten
percent is all it can return, and an existing packaged tool already returns it.

## Named limits

1. **N=2, and small programs.** Both consumers are small and dominated by `std`.
   The estate's product units (~1,800 modules) may share a very different
   fraction. This is not a project-level measurement and must not be quoted as
   one.
2. **Post-emission only.** Every number here is what a deduper finds in already
   emitted DWARF. It is silent about what an emitter that shares before emission
   could do.
3. **Size only.** No build-time, link-time, memory or debugger-behaviour effect
   was measured. dwz itself costs time that is not accounted here.
4. **Debugger fidelity unverified.** The dwz outputs were measured, not debugged.
   `.gnu_debugaltlink` requires the shared file to be findable at debug time; a
   missing shared file is a broken debug experience, which is the failure class
   the fork's split-debug work already refuses by design.
5. `dwz` 0.17 (Red Hat), the packaged build on this station. Not vendored, not
   proposed as a dependency.

## What this changes in the plan

`NEXT_WAVE_PLAN_2026-09-10.md` ordered C6 as P3a (measure) then P3b (the C++ shim
+ `EmitOptions` split-debug member). That order is confirmed, and P3b's
justification is now stronger and narrower:

- Do **not** build a post-emission deduplicator. It is worth ~10% and a packaged
  tool already does it.
- P3b's before-emission shared module is the only arm whose ceiling is still
  open, and it must state its own expected saving **before** it is built, the way
  this packet did.
- A cheap, honest intermediate the maintainer can act on today: run `dwz` (not
  `-m`) over shipped binaries for **8.71%** with no compiler change and no fork
  patch at all.

No promotion, no default change, no stage completion is claimed. Stage 2b remains
unimplemented.
