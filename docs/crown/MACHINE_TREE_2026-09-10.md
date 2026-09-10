# The machine tree — MR/HR projections, and a final compiler built from MR

*Measured 2026-09-10 by the Opus compiler partner. Every number below carries the
command that produced it and the binary it was produced with. No promotion, no
default change, no release.*

## What was asked, and what was built

The fork's sources stay exactly as they are — no renames, no parallel source
convention. A renderer takes the commented tree as input and derives two
projections; the **final** `zig` executable is built from one of them.

| | |
|---|---|
| **MR** | code with every comment removed, mirrored 1:1 into `<out>` — what the final executable compiles from |
| **HR** | comments only, `<out>/hr/<path>.md`, each block labelled with the line it starts on **in the original file** — never enters a compile |

**Scope, stated precisely.** Only the final executable is built from MR.
Development builds, the unit tests, the autodoc object and every tool keep
compiling the commented sources, and without `-Dmachine-tree` the build graph is
unchanged. Within the bootstrap chain the scope is narrower still and this is a
correction worth stating: `zig1` and `zig2` are generated from the **commented**
tree by the wasm bootstrap (`CMakeLists.txt` builds `zig1.c`/`zig2.c` into the
cmake binary dir). **Only stage3 is built from MR.** "The final binaries are MR"
is true of stage3 and false of the two bootstrap binaries.

## Files

| Path | Role |
|---|---|
| `tools/machine_tree.zig` | the renderer — Zig only, no external dependency |
| `tools/machine_tree_build.zig` | the build glue, one file, carried unchanged across a rebase |
| `build.zig` | **+23 / −2** across 6 hunks |
| `docs/crown/BUILDING.md` | new section 7 |

The `build.zig` hunks, exactly: one `@import` beside the existing
`test/tests.zig` and `src/dev.zig` imports; one `resolve(b)` call; one
`.machine_tree` field on `AddCompilerModOptions`; the root-source and `aro` path
choice in `addCompilerMod`; and `zig_lib_dir` + `dependOn` on the Compile step in
`addCompilerStep`. Everything else lives in the two new files, so a 0.17 rebase
re-applies a small hunk and carries the module.

## The options — declared, required, refused by name

```
-Dmachine-tree=<dir>          enables the tree and builds the final zig from it
-Dmachine-lines=keep|compact  REQUIRED whenever -Dmachine-tree is given
```

All three refusals were fired:

| Input | Result |
|---|---|
| `-Dmachine-lines=keep` alone | `panic: -Dmachine-lines was given without -Dmachine-tree. Refusing: on its own it would silently do nothing.` |
| `-Dmachine-tree=…` alone | `panic: -Dmachine-tree requires -Dmachine-lines=keep\|compact. Refusing to choose a line mode for you…` |
| `-Dmachine-lines=loose` | `panic: -Dmachine-lines must be 'keep' or 'compact', got 'loose'` |

## Why token-aware, and why a line stripper is refused

`std.zig.Tokenizer` is the only thing that classifies these correctly:

- `\\ // not a comment` on a multiline string line is string **content**;
- `"https://ziglang.org"` and `"scheme://host//path"` contain `//`;
- `///` and `//!` are **tokens** (`doc_comment`, `container_doc_comment`);
- `//` and `////` are **not** tokens — the tokenizer skips them between tokens,
  and `////` reaching `line_comment` rather than `doc_comment` is inherited from
  the tokenizer rather than restated here.

Dropped is exactly the two comment token kinds plus the plain `//` runs in the
gaps. A byte in a gap that is neither whitespace nor a comment is a **named
refusal** (`UnexpectedByteBetweenTokens`), not a silent drop.

## The tree is a complete mirror — found by a failed build, not by foresight

`src/` and `lib/` hold **19,851 files** and only **1,145** are `.zig`. `lib/` is a
whole sysroot: 13,266 `.h`, 2,653 `.def`, 1,878 `.c`, 206 `.cpp` (libunwind,
libcxx), and `src/` `@import`s four `.zon` data files.

The first stage3 build from a **Zig-only** tree **FAILED** with four
`FileNotFound` errors naming `src/clang_options.zon`,
`src/codegen/aarch64/instructions.zon`, `src/codegen/x86_64/encodings.zon` and
`lib/libunwind/src/libunwind.cpp`. Non-Zig files are now mirrored byte-for-byte.
**19,851 files in, 19,851 out.** P5 earned its place in the packet.

`.zon` is mirrored, not rendered: it is imported as a value, its comments cannot
reach an artifact, and `ast-check` checks it under a different mode, so rendering
it would add a class the controls cover only partly for no gain. Named, not
hidden.

## P1–P4 — the controls

| Control | Result |
|---|---|
| **P1** token-stream identity, per file | **10,827,495 tokens compared, 0 mismatches** |
| **P2** `ast-check` every MR `.zig` | **1145 requested, 1145 checked, 0 failed, 0 skipped** |
| **P3** `keep` line law | **0 line mismatches** across 1,145 files |
| **P3** `compact` | 73,683 lines dropped |
| **P4a** `\\` lines carrying `//`, `///`, `//!` | byte-exact |
| **P4b** `"https://ziglang.org"`, `"scheme://host//path"` | preserved |
| **P4c** corrupt one rendered file | **RED** — `MISMATCH src/dev.zig: token #2 src=identifier 'Env' mr=identifier 'Enw'`; restored → md5 `8d7f68d6…` identical → **green** |

P4c required a `--check` mode that verifies the tree **on disk**. Re-rendering
would have silently healed the corruption and the control would have passed while
proving nothing — the guard had to be built so it *could* fail.

## P5 — the compiler built from the machine tree

| | |
|---|---|
| binary | `<evidence>/stage3_mr/bin/zig` |
| sha256 | `f2f86724c3e01ed05767705155cf92846615752f1969bd5a27dd696d9efeb75e` |
| exit / wall / peak RSS | **0** · 1,743.27 s · 6,473,864 kB |
| `zig version` | `0.16.0` |

Compared against today's commented-tree compiler
`ab62ba330cc2f93b00f72d34b2ae5747b3b4bd3954755a70dd8e17c7949b8dde`:

**Both pointed at the same lib dir — this isolates the compiler binary itself:**

| Probe | Result |
|---|---|
| `build-exe` hello, exit + output | **IDENTICAL** |
| `build-exe` hello, emitted **binary sha256** | **IDENTICAL** |
| `zig test lib/std/base64.zig` | **IDENTICAL** |

**Each with its own installed lib (the shipping configuration):**

| Probe | Result |
|---|---|
| `ast-check` of `lib/std/Target.zig` | IDENTICAL |
| diagnostic text on a broken file | IDENTICAL |
| `build-exe` exit + output | IDENTICAL |
| hello runtime output | IDENTICAL |
| emitted binary sha256 | **DIFFERS — named below** |

The difference is the install path embedded in debug info, and that was
**proven, not assumed**: 24 strings appear only in each binary, and filtering
them for the differing path leaves **0 strings unexplained**. The size delta is
**72 bytes = 24 × 3**, the three characters of `_mr`.

## Which `lib/` the final compiler uses at run time — both measured

Two independent things:

1. **What the executable was compiled against** — `<machine-tree>/lib`, set as
   `exe.zig_lib_dir`. The MR std, baked in at build time.
2. **What it hands to user compilations at run time** — the installed `lib/`.
   The install step is **unchanged** and still installs the **commented** `lib/`.

Both were exercised on the same binary without rebuilding. Pointing the MR
compiler at the MR lib produces a third, different artifact hash
(`6b357599…` vs `815fdcad…`) — again the path prefix.

**The choice, and why:** ship the **commented** `lib/`. A user of this compiler
gets real source with comments in their own error messages and debug info, `lib/`
continues to ship exactly as upstream ships it, and the MR tree stays what it is
— a build-time input, not a distribution format.

## P6 — measurements, dated, three runs each, medians

| Measurement | Median | Runs |
|---|---|---|
| renderer, cold (tree removed first) | **1.25 s** | 1.27 / 1.23 / 1.25 |
| renderer, warm (incremental no-op, `rewritten=0`) | **0.89 s** | 0.90 / 0.89 / 0.88 |
| tokenizer pass, commented tree | **0.62 s** | 1.00 / 0.62 / 0.61 |
| tokenizer pass, MR tree | **0.59 s** | 0.59 / 0.60 / 0.58 |

Peak RSS of the renderer: 24,584 kB over the full 222 MB tree.

Comment share, `src/` + `lib/`, 1,145 Zig files:

| | bytes | removed |
|---|---|---|
| source | 61,680,821 | — |
| `keep` | 57,569,208 | 4,111,613 (**6.67%**) |
| `compact` | 57,100,636 | 4,580,185 (**7.43%**) |

Plus 18,706 non-Zig files (161,213,995 bytes) mirrored unchanged.

A consistency check falls out of the tokenizer arms: 10,874,638 tokens on the
commented tree against 10,827,495 on MR — a difference of **47,143**, exactly the
`doc_comment` and `container_doc_comment` tokens removed.

**The tokenizer arm is a weak green and is not a performance claim.** 0.62 → 0.59
is ~4.8%, on a measurement whose own spread is 2–3% and whose first commented-tree
run was a 1.00 s cold-cache outlier.

**The two stage3 wall times are NOT a controlled comparison and must not be read
as one.** 1,657 s (commented, earlier today) against 1,743 s (MR) differ in cache
state and time of day, and the MR build additionally compiled and ran the
renderer. No speedup or slowdown is claimed in either direction.

## Recommendation: `keep`

`compact` buys a further 468,572 bytes — **0.76 percentage points** — and pays
with the 1:1 line correspondence that makes every diagnostic, backtrace and
debug-info line number from the final compiler directly readable against the
commented sources. On a 6.67% base that trade is not worth making, and `keep` is
what the P5 build used.

## Residuals, named

1. **The bootstrap chain is not MR.** `zig1`/`zig2` come from the commented tree
   via the wasm bootstrap; only stage3 is built from MR.
2. **`build.zig` and its imports are not MR.** `build.zig` imports
   `test/tests.zig` and `src/dev.zig` from the commented tree at configure time,
   so `src/dev.zig` is compiled from two trees in one build. Harmless, and named.
3. **`.zon` is mirrored, not rendered** (4 files), for the reason above.
4. **No file was refused by the tokenizer**: 0 `UnexpectedByteBetweenTokens`
   across 1,145 files. `lib/compiler/aro` (72 files) and `lib/std` (551 files)
   both render clean.
5. **`zig build` in this repo fails a version check without `-Dversion-string`**
   (`Zig version '0.16.0' must be greater than tagged ancestor
   '0.16.0+cgm.046d6833'`). Verified **pre-existing** by re-running the same
   command against the stashed original `build.zig`; unrelated to this work.
6. **The MR tree is addressed by absolute path.** `-Dmachine-tree` is routinely
   outside the build root, and `b.path` panics on absolute paths, so the glue
   uses the documented `cwd_relative` LazyPath. Whether the zig cache keys on
   that absolute path in a way that would defeat incremental builds across
   different `<out>` locations was **not measured** and is not claimed either
   way. Per the packet's stop rule, that is named and stopped at, not reshaped.
7. **`compact` mode has no P5 build.** Only `keep` was built and probed.
