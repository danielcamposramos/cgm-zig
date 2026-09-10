# Building the fork — the recipe that worked, and every gotcha that cost a lane time

This file exists so nobody rediscovers the same three obstacles. Each entry below
was met by an actual build, has a negative control where one was possible, and
names the file:line or command that proves it.

The fork's working compiler is **ReleaseSafe** by posture (`README.md`,
`CONTRIBUTING-AI.md`): safety checks ON, so a failure names itself instead of
producing a silent wrong answer. A stripped ReleaseFast build is not the working
compiler and must not become the promoted one.

---

## 1. The recipe

```bash
cmake -B build-safe \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DZIG_RELEASE_SAFE=ON \
    -DZIG_STATIC_LLVM=OFF \
    -DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions
ninja -C build-safe
```

Result: `build-safe/stage3/bin/zig`.

For a new release candidate, choose a fresh repo-local `build-*` directory;
do not overwrite a promoted compiler's build tree. The directory name is not
evidence of its build mode.

**The two build-mode switches are not interchangeable.** `CMAKE_BUILD_TYPE`
controls the C/C++ bootstrap and stripping policy; `ZIG_RELEASE_SAFE=ON`
selects `-Doptimize=ReleaseSafe` for the self-hosted compiler. The previous
recipe used only `-DCMAKE_BUILD_TYPE=ReleaseSafe`, which this project's
`CMakeLists.txt` does not recognize as a safety selector. On a fresh cache it
generates a **ReleaseFast, stripped** stage3 command. Use `RelWithDebInfo` plus
`ZIG_RELEASE_SAFE=ON` and inspect the generated stage3 command before building.
The existing station build caches already used that correct pair; this finding
does not reclassify their promoted binaries. The configure-only negative and
positive controls are recorded in `BUILD_RECIPE_CORRECTION_2026-09-06.md`.

- **System LLVM** on Debian needs `llvm-21`, `liblld-21-dev`, `libclang-21-dev`.
  The runtime `libclang-cpp.so` **alone is not enough** — the `-dev` packages
  carry the headers the C++ side compiles against.
- **`-Ddebug-extensions` is not optional.** Without it the crash-report machinery
  (the `Analyzing <file>` breadcrumbs) is compiled out, and that machinery is the
  entire point of a diagnostic build.
- **Machine courtesy first.** `pgrep -fa 'zig build-exe|ninja'` — if a long build
  owns the host, author and parse only, and queue the compile.

### Wall time — restated with its conditions

The often-quoted "~8–9 min, ~7.6 GiB peak on a 12-core host" is a figure from an
**unconstrained** build on an idle machine. It is **not reproducible under an
affinity mask on a contended host**, and quoting it as if it were has already
misled one lane's planning. Measured on 2026-08-23, `taskset -c 4-11`
(8 logical / 6 physical) with another lane holding cores 0–3:

| Phase | Wall |
|---|---|
| full: zigcpp → zig1 → zig2 | ≈ 20 min |
| the self-hosted stage3 step alone | ≈ 21 min |
| **clean single pass, contended, 8-CPU mask** | **≈ 41 min** |

Peak RSS on the failing full attempt: 7,134,956 KB (6.80 GiB).

State the mask and the contention with any build time you record. A wall time
without its conditions is not a measurement.

---

## 2. Debian multiarch defeats `zig libc` auto-detection — `ZIG_LIBC` is the remedy

**Symptom.** The bundled libunwind sub-compilation fails, and the error points at
a kernel header rather than at anything you wrote:

```
error: sub-compilation of libunwind failed
    /usr/include/linux/types.h:5:10: note: 'asm/types.h' file not found
```

**Cause.** `zig libc` reports `sys_include_dir=/usr/include`. On Debian multiarch
the header actually lives at `/usr/include/x86_64-linux-gnu/asm/types.h`. Nothing
is wrong with the compiler or the patchset; the auto-detected path is simply
incomplete for this distribution layout.

**Proof it is the environment and not the fork — negative control, fired with the
promoted (unpatched) compiler** so the cause cannot be attributed to any patch:

```
zig build-exe t.zig -lc -lunwind                       -> rc=1, 'asm/types.h' file not found
ZIG_LIBC=<corrected> zig build-exe t.zig -lc -lunwind  -> rc=0
```

**Remedy.** Write a libc paths file and export it:

```bash
zig libc > libc.txt            # start from the auto-detected file
# then correct exactly one line:
#   sys_include_dir=/usr/include/x86_64-linux-gnu
export ZIG_LIBC=/absolute/path/to/libc.txt
```

The two lines that matter:

```
include_dir=/usr/include
sys_include_dir=/usr/include/x86_64-linux-gnu
```

`ZIG_LIBC` is read at `src/main.zig:1049` into `create_module.libc_paths_file`,
so it **reaches every sub-compilation** — which is the property that matters,
because the failure is in a sub-compilation you never invoked yourself.

A working file is kept at `build-p005/vwork/libc.txt` (gitignored, so it can be
destroyed at any time — regenerate rather than depend on it).

---

## 3. `ZIG_GLOBAL_CACHE_DIR` — point it somewhere you control

The default `~/.cache/zig` may be a symlink into another tree. One lane lost
build artifacts mid-run to exactly that. Set it explicitly, repo-local:

```bash
export ZIG_GLOBAL_CACHE_DIR=/path/to/repo/build-<name>/gcache
export ZIG_LOCAL_CACHE_DIR=/path/to/repo/build-<name>/cache
```

`build-*/` is gitignored, so repo-local scratch stays out of `git status`.

**Do not use `/tmp` for build scratch.** An external cleaner has deleted a lane's
`/tmp` scratch *mid-run*, destroying fixtures between two commands. Repo-local
`build-*/` survived the same event.

---

## 4. ThreadSanitizer does not build here, and the reason is not ours

```
cmake -DZIG_EXTRA_BUILD_ARGS=-Dsanitize-thread ... ; ninja -C build-tsan
error: sub-compilation of libtsan failed
  lib/libtsan/sanitizer_common/sanitizer_platform_limits_posix.cpp:160:10:
    note: 'linux/scc.h' file not found
```

`linux/scc.h` is an obsolete kernel header modern Debian `linux-libc-dev` no
longer ships. Zig 0.16 bundles a compiler-rt vintage that still includes it, and
uses it for `sizeof(struct scc_modem)` / `sizeof(struct scc_stat)` at
`sanitizer_platform_limits_posix.cpp:535-536`.

**An include shim is NOT an acceptable workaround here** and one was built and
then deliberately not used: TSan *asserts on those struct sizes*, so a shim means
fabricating struct definitions whose sizes a sanitizer trusts. Searched the whole
host: no `linux/scc.h` anywhere.

Consequence to plan around: **any verification row whose instrument is TSan is
UNRUNNABLE in this estate until the toolchain changes** — say so by name, never
silently substitute a weaker check for it. See
`PATCH005_VERIFICATION_RUN_2026-08-23.md` V12.

---

## 5. The cheap oracle — type-check without building a compiler

A full stage3 costs ~40 min under a mask. Most edits only need to know whether
the tree still type-checks, and that costs **~45 seconds**:

```bash
zig build-exe -fno-emit-bin -OReleaseSafe -lc --zig-lib-dir lib/ \
    --dep aro --dep build_options \
    -Mroot=src/main.zig \
    -Maro=lib/compiler/aro/aro.zig \
    -Mbuild_options=<a generated build options .zig>
```

Any 0.16.0-era compiler can run it, including the currently promoted binary, and
it works on a `git worktree` of any branch. The generated build-options module
from an existing cmake build directory (`build-*/config.zig`) serves fine.

This is how `main` was found to have been un-buildable for a day without anyone
meeting it, and it is the receipt every source commit here should carry when a
full build is not being fired. **It proves the tree compiles. It proves nothing
about behaviour** — do not write it up as if it did.

---

## 6. Promotion

`PROMOTED/zig` is a symlink to the stage3 binary the station uses, with
`PROMOTED/RECORD.md` carrying the evidence for why that binary and not another.
It is station-local. Promotion follows a verification batch, never a build alone:
a compiler that builds is not a compiler that was checked.

---

## 7. The machine tree — building the final compiler from comment-stripped sources

*Added 2026-09-10.*

The fork's own sources can be rendered into two projections and the **final**
`zig` executable built from one of them:

- **MR** (machine readable) — the code with every comment removed. This is what
  the final executable compiles from.
- **HR** (human readable) — the comments only, as `<out>/hr/<path>.md`, each
  block labelled with the line it starts on **in the original file**, so
  `src/dev.zig:2` addresses a comment in the human tree. It never enters a
  compile.

The commented sources in `src/` and `lib/` stay exactly as they are. Nothing is
renamed and there is no parallel source convention: the renderer takes the
commented tree as input and derives both projections from it.

**The output is a COMPLETE mirror, not a Zig-only projection.** `src/` and `lib/`
hold 19,851 files and only 1,145 of them are `.zig`: `lib/` is a whole sysroot
(13,266 C headers, 1,878 `.c`, 206 `.cpp` including libunwind and libcxx, 2,653
`.def`) and `src/` `@import`s four `.zon` data files. Zig sources are rendered;
**every other file is mirrored byte-for-byte**, so the tree the compiler is
pointed at is self-sufficient. This is not a precaution — a Zig-only tree was
built first and the stage3 build failed with four `FileNotFound` errors naming
`clang_options.zon`, `instructions.zon`, `encodings.zon` and
`lib/libunwind/src/libunwind.cpp`. `.zon` files are mirrored rather than
rendered: they are imported as values, their comments cannot reach an artifact,
and `ast-check` checks them under a different mode, so rendering them would add
a class the controls cover only partly for no gain.

**Scope is deliberately narrow.** Only the final executable is built from MR.
Development builds, the unit tests, the autodoc object and every tool keep
compiling the commented sources. Without `-Dmachine-tree` the build graph is
unchanged.

### The two options — both declared, neither defaulted

```
-Dmachine-tree=<dir>          render src/ and lib/ into <dir> and build the final zig from it
-Dmachine-lines=keep|compact  REQUIRED whenever -Dmachine-tree is given
```

`-Dmachine-lines` is refused by name if absent, and `-Dmachine-lines` on its own
is refused too. The mode is never chosen for you because it decides what a
compiler diagnostic's line number means:

| mode | what it does | why it matters |
|---|---|---|
| `keep` | removes comment BYTES, keeps every newline | `file:line` in every diagnostic maps **1:1** onto the commented file — no line map anywhere |
| `compact` | also drops lines that BECAME blank (a line already blank in the source is kept — that spacing is authored) | smaller tree, but line numbers no longer correspond |

Measured on this tree, 1,145 files, 61,680,821 source bytes:

| mode | MR bytes | removed | lines dropped |
|---|---|---|---|
| `keep` | 57,569,208 | 4,111,613 (**6.67%**) | 0 |
| `compact` | 57,100,636 | 4,580,185 (**7.43%**) | 73,683 |

Alongside those, 18,706 non-Zig files (161,213,995 bytes) are mirrored unchanged.

**Use `keep`.** `compact` buys a further 468,572 bytes — 0.76 percentage points —
and pays for it with the 1:1 line correspondence that makes every diagnostic,
backtrace and debug-info line number from the final compiler directly readable
against the commented sources. That trade is not worth making.

### The complete producer command

Three separate corrections landed against the previously recorded command on
2026-09-10; this is the whole thing in one place, and it is the version that
works on this station:

```bash
export ZIG_GLOBAL_CACHE_DIR=<cache>/zig_global
export ZIG_LOCAL_CACHE_DIR=<cache>/zig_project
export ZIG_LIBC=<evidence>/libc.txt          # correction 2, see section 2

<cmakebuild>/zig2 build \
    --prefix <evidence>/stage3 \
    --zig-lib-dir /path/to/cgm-zig/lib \
    -Dversion-string=0.16.0 \
    -Dtarget=native -Dcpu=native \
    -Denable-llvm \
    -Dconfig_h=<cmakebuild>/config.h \
    -Dno-langref \
    -Ddebug-extensions \
    -Dlog \                                   # correction 1: without it --debug-log is inert
    -Dmachine-tree=<evidence>/mtree_keep \    # correction 3: the machine tree
    -Dmachine-lines=keep \
    -Doptimize=ReleaseSafe
```

- **`-Dlog`** is a distinct option from `-Ddebug-extensions` (`build.zig`, the
  two adjacent `b.option` lines) and defaults to `is_debug`, i.e. **false** at
  ReleaseSafe. Without it the compiler refuses `--debug-log` by name and no
  `--debug-log` scope produces anything.
- **`ZIG_LIBC`** is section 2 above. Without it the build dies in the libunwind
  sub-compilation with `'asm/types.h' file not found`.
- **`--zig-lib-dir`** here is the lib used to compile the build script and the
  tools. The final executable's own std comes from `<machine-tree>/lib`, set by
  the build glue on the compile step — that separation is the whole point.

### Which `lib/` the final compiler ships and uses at run time

Two different things, and they are independent:

1. **What the executable was compiled against** — `<machine-tree>/lib`, set as
   `exe.zig_lib_dir`. This is the MR std, baked in at build time.
2. **What the executable hands to user compilations at run time** — the
   installed `lib/` beside the binary. The install step is **unchanged** and
   still installs the **commented** `lib/`.

Shipping the commented `lib/` is the deliberate choice: a user of this compiler
gets real source with comments in their own error messages and debug info, which
is what they want, and `lib/` continues to ship exactly as upstream ships it. The
MR tree is a build-time input, not a distribution format.

Both are exercisable without rebuilding: the installed default is what the
probes use, and `--zig-lib-dir <machine-tree>/lib` points the same binary at the
MR std for comparison.

### The renderer

`tools/machine_tree.zig`, built and run by `tools/machine_tree_build.zig` as the
`machine-tree` step. It is **token-aware** via `std.zig.Tokenizer` and a regex or
line-prefix stripper is refused as a design, not as a preference: `\\` multiline
string lines carrying `//` are string CONTENT, and `"https://…"` literals contain
`//` too. Both are tokens and are copied byte-exact. What is dropped is exactly
the `doc_comment` and `container_doc_comment` tokens plus the plain `//` runs the
tokenizer skips between tokens. (`////` is a plain comment, not a doc comment;
the renderer inherits that from the tokenizer rather than restating it.)

Every render runs the token-stream identity check, so a rendering that would
change what the compiler sees fails the build instead of reaching it:

```bash
# verify an already-rendered tree without writing anything
zig run tools/machine_tree.zig -- --root . --out <dir> --mode keep --check
```

The tree is content-hashed per file in `<out>/MANIFEST.json` and only files whose
rendered bytes actually changed are rewritten, so an unchanged render leaves
mtimes alone and the zig cache stays warm.
