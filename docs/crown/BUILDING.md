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
    -DCMAKE_BUILD_TYPE=ReleaseSafe \
    -DZIG_STATIC_LLVM=OFF \
    -DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions
ninja -C build-safe
```

Result: `build-safe/stage3/bin/zig`.

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
