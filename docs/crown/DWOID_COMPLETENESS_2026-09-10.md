# Exact input attribution for the debug identity — proven on a rebuilt instrumented compiler

*Measured 2026-09-10 by the Opus compiler partner. This closes the completeness
residual carried since 2026-09-09: whether the file set folded into
`DW_AT_GNU_dwo_id` covers everything that shaped the emitted debug information.
It proves INPUT COVERAGE and nothing beyond it. Stage 2b remains unimplemented.*

## The binary — built for this, and verified to contain the instrument

| | |
|---|---|
| path | `/K3D/CGM_Forge.local/crown_sig_2026_09_10/stage3/bin/zig` |
| sha256 | `ab62ba330cc2f93b00f72d34b2ae5747b3b4bd3954755a70dd8e17c7949b8dde` |
| exit / wall / peak RSS | **0** · 1,657.25 s · 6,310,164 kB |
| `strings ... | grep -c cgm-dwoid` | **1** (the merged format prefix) — the prior binary `c6db06a0…` has **0** |
| `--debug-log` warning | none (the binary carries `-Dlog`) |

The output path did not exist before the build, so the binary cannot be a stale
artifact; and the trace strings are present, which no earlier build's binary had.
That is the answer to the "Built target stage3 without rebuilding" trap: it is
checked by content, not by a build-system message.

### The producer command — corrected in two places the record did not carry

```
<cmakebuild>/zig2 build --prefix <evidence>/stage3 \
    --zig-lib-dir /K3D/GitHub/cgm-zig/lib \
    -Dversion-string=0.16.0 -Dtarget=native -Dcpu=native -Denable-llvm \
    -Dconfig_h=<cmakebuild>/config.h -Dno-langref -Ddebug-extensions \
    -Dlog \
    -Doptimize=ReleaseSafe
```
with `ZIG_LIBC=<evidence>/libc.txt`, `ZIG_GLOBAL_CACHE_DIR` and
`ZIG_LOCAL_CACHE_DIR` at the existing NVMe caches. No new cache root.

Both additions were **necessary, and neither is in the recorded command**:

1. **`-Dlog`.** Without it `--debug-log` is inert and the compiler says so by
   name — `warning: Zig was compiled without logging enabled (-Dlog).
   --debug-log has no effect.` `-Dlog` is a distinct option from
   `-Ddebug-extensions` (`build.zig:250-251`) and defaults to `is_debug`, false
   at ReleaseSafe.
2. **`ZIG_LIBC`.** The first attempt with the command exactly as recorded failed
   after 1,008 s: `error: sub-compilation of libunwind failed` /
   `'asm/types.h' file not found`. This is `BUILDING.md` §2 — `zig libc` reports
   `sys_include_dir=/usr/include` while `/usr/include/asm` **does not exist** on
   this Debian multiarch station and the header lives at
   `/usr/include/x86_64-linux-gnu/asm/types.h`. BUILDING.md's own negative
   control was re-fired **on the promoted, unpatched compiler**, so the cause
   cannot be attributed to any patch: `zig build-exe t.zig -lc -lunwind` → rc=1
   with that error; the same command under the corrected `ZIG_LIBC` → rc=0.

The consumer compiles below were run **without** `ZIG_LIBC`, matching how the
baselines were produced, so the comparison stays like-for-like.

## Method

The comparator is `partner_tools/dwoid_completeness.py`. It selects the PROGRAM
compile unit by `DW_AT_name`, refusing zero or multiple matches; derives the
ARTIFACT set as that CU's `DW_AT_decl_file` values ∪ its line-table file names,
joined to `DW_AT_comp_dir` when relative, normalized and sorted unique; derives
the MAP set from the `kind=file` trace rows for the same unit that end in a
`kind=final` row, joined to absolute paths through `kind=abspath` on the shared
`Zcu.File.Index`; and reports **both** set differences in full.

A `kind=abspath` row is used only as that join table. It is emitted before
metadata creation finishes, so it is a correlation and never counted as
admission proof — only `kind=file` rows terminated by a `kind=final` count.

## Results

### 1. Completeness — both consumers, both directions

| Consumer | CU | artifact set | folded set | **ARTIFACT-ONLY** | MAP-ONLY |
|---|---|---|---|---|---|
| 1 (`scale_root` + `scale_modb`) | `root` | 85 (decl_file 85 ∪ line-table 85) | 85 from 85 rows | **0** | 0 |
| 2 (`consumer2`) | `consumer2` | 84 (decl_file 84 ∪ line-table 84) | 84 from 84 rows | **0** | 0 |

**Exact set equality in both directions, on both consumers.** Every file that
shaped the emitted debug information was folded into the identity.

### 2. The comparator's own negative control — the detector fires

An empty artifact-only set proves nothing unless the detector can produce a
non-empty one. Forced with `--drop-path scale_modb.zig` on the same inputs:

```
ARTIFACT-ONLY (omission -- must be empty): 1
    OMITTED  .../partner_tools/fixtures/const_signature/scale_modb.zig
RESULT: CONTROL FIRED
```

The tool also refuses by name, each verified: zero or multiple CU name matches,
a unit name containing a quote, a `kind=refused` row, a folded row with no
`abspath` partner, and `folded=` disagreeing with the row count. A synthetic run
with interleaved `compiler_rt` decoy rows kept the folded set at 85, not 86.

### 3. Inclusion control — RED then GREEN, on the compiler's own per-file digest

Mutating the existing non-root fixture `scale_modb.zig` (`append(a, 9)` →
`append(a, 11)`):

| | `scale_modb.zig` digest | identity |
|---|---|---|
| baseline | `0x7e88a85c3d8c5aa0` | `0x42ccd13bb162ca8e` |
| mutated | **`0x370678e5421aeb96`** | **`0xea4b8d724870a713`** |
| restored | `0x7e88a85c3d8c5aa0` | `0x42ccd13bb162ca8e` |

Both the per-file digest and the final identity moved and came back. This
discriminates admission of that input rather than comparator behaviour, because
the evidence is the compiler's own digest line. `sha256sum -c
fixtures_pre_2026_09_09.sha256` → **7/7 OK** after restore. The mutated identity
`0xea4b8d724870a713` reproduces the value recorded for the same mutation on
2026-09-09 **exactly**.

### 4. The instrument does not change the measurement

`--debug-log codegen` present vs absent, same inputs, same binary:
`0x42ccd13bb162ca8e` **both**.

### 5. No dangling split reference

`DW_AT_GNU_dwo_name` count = **0** in all three artifacts (`N_c1`, `N_c2`,
`N_c1_nolog`). Nothing points at an absent `.dwo` file.

### 6. New result — the identity is a property of the input, not of the compiler binary

Both consumers reproduce, on this **different compiler build**, the identities
recorded on `c6db06a0…`:

| Consumer | recorded on `c6db06a0…` | measured on `ab62ba33…` | |
|---|---|---|---|
| 1 (`root`) | `0x42ccd13bb162ca8e` | `0x42ccd13bb162ca8e` | **reproduces** |
| 2 (`consumer2`) | `0x61d78abd44beec1f` | `0x61d78abd44beec1f` | **reproduces** |

This was not previously established and it is the property a reuse key needs:
the fold hashes `file.sub_file_path` (relative) and `build_options.version`,
neither of which differs between the two builds, so two independently built
compilers of the same source agree on the identity of the same program.

## Findings the packet did not predict

**MAP-ONLY is empty, on both consumers.** The packet expected a non-empty
map-only set and required every member be explained one by one, on two stated
grounds: `Builder.debugFile` performs no dedup, so two `Zcu.File.Index` values
resolving to one path would give two admissions; and files may be admitted that
emit no DIE. **Neither occurs here.** Every admitted file emitted a DIE, and no
path was admitted under two indices. The anticipated conservative over-hashing
does not happen on these programs. It may still happen on larger ones; the
comparator reports it if it does, and will name each member.

**The omission control of packet step 5 is therefore not constructible**, exactly
as that step allowed for. Stated honestly, unchanged: the remaining uncovered
route is a file forced into emitted debug info **without** passing
`getDebugFile` — the plausible path being cross-module inlining
(`DILocation.inlinedAt`) — and no fixture forces that. **That fixture is not
authored, and this receipt does not claim coverage of that route.**

## What this does and does not establish

**Does:** the hashed input set exactly covers the emitted file set of the program
compile unit, on two substantively different consumers, on an explicitly rebuilt
instrumented compiler, with the detector proven to fire and the inclusion control
seen red and returned green.

**Does not:** shared debug bodies, size reduction, `.dwo` emission, any
performance or memory result, or coverage of a file that reaches debug info
without `getDebugFile`. **A 64-bit identity match remains a reuse CANDIDATE, not
proof that two debug bodies are interchangeable.** No promotion, no default
change, no release. **Stage 2b remains unimplemented.**

## Hygiene

Fixtures restored, 7/7 OK. `src/link/Dwarf.zig` and `src/link/ConstPool.zig`
still verify against `pre_nc_dwarf.sha256`. `zig`, `zig2`, `make`, `cmake`,
`ninja` all 0 at handback. Every build ran under the one canonical build lock;
the rebuild queued behind an estate product build and fired when it cleared.

---

## Addendum — the first candidate re-verified on this same binary

`ab62ba33…` was built from the whole dirty tree, so it also carries the FIRST
candidate (`src/link/ConstPool.zig` + `src/link/Dwarf.zig`), and — unlike
`c6db06a0…` — it carries `-Dlog`. `CROSS_PROCESS_SIGNATURE.md`'s reproduce block
requires "a compiler built with `-Dlog`", which `c6db06a0…` is not. So the oracle
could be run, for the first time, against a compiler with a recorded sha256 that
this packet produced:

```
python3 partner_tools/const_signature_oracle.py --zig <ab62ba33...> --out <evidence>/oracle
```

| Check | Result |
|---|---|
| every fixture compiles without a collision refusal | PASS — nonzero exits: none |
| `a` and `b` share a signature neither control has | PASS — `0x4f337c2ccde54fe5` |
| changing element width changes the signature set | PASS |
| changing array length changes the signature set | PASS |
| changing target changes every signature | PASS — overlap: none |

**5/5 passed.** All five fixtures produced 22 signatures each, exit 0.

### The shared signature differs from the recorded one, and that is by design

`CROSS_PROCESS_SIGNATURE.md` records the shared signature as
`0xd0a652b0234af326`; this run gives `0x4f337c2ccde54fe5`. Not a discrepancy —
the mechanism explains it exactly. `src/link/ConstPool.zig:273` folds
`@import("build_options").version` into the signature, under the comment at
`:270` "Two compiler versions, or two targets, are two different debug worlds",
and the type's own doc comment at `:65` says the signature is "Valid across
separate compiler processes **for the same compiler version**". The document's
compiler reported `0.16.0+cgm.289ff31b24-crownsig`; this one is built
`-Dversion-string=0.16.0`. Different version string, different signature, as
designed.

This closes by mechanism what was previously an inference: **the binary that
produced `0xd0a652b0234af326` was neither `c6db06a0…` nor `ab62ba33…`** — both
report `0.16.0` — but one of the earlier `-Dlog` builds in the 2026-09-08
evidence root. The result is not withdrawn; only its binary attribution was, and
it is now replaced by a fresh 5/5 against a named binary.

### A property worth stating alongside the identity result

The two values behave differently across builds, and both behaviours are correct
for what they key:

- `DW_AT_GNU_dwo_id` **reproduced exactly** across `c6db06a0…` and `ab62ba33…`
  (§6 above) — because both were built `-Dversion-string=0.16.0` and the fold's
  other inputs are the program's own relative paths and ZIR.
- The const signature **changed** across compiler builds with different version
  strings — deliberately, because a different compiler emits different debug
  entries and must not be offered as interchangeable.

Neither is stable across a compiler *version* change, and neither should be.
