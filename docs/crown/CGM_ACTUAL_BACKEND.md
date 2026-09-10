# Which backend actually emits the consuming project's debug information

Measured 2026-09-08 from existing cache outputs, read-only. Nothing was
recompiled and no consuming-project cache was modified.

## The finding

**The consuming project builds through LLVM + LLD. `src/link/Dwarf.zig` is not
on that path at all.**

This matters because the prior Crown increment (shared `const_type` entries)
lives entirely in `src/link/Dwarf.zig`, the SELF-HOSTED emitter. It therefore
has **no effect** on the build it was meant to serve. That is recorded here so
the 0.35% fixture reduction is never read as a project-level improvement.

## Evidence

Two separately compiled consumers, both from their stable per-owner
`current/.zig-cache`:

| | tokenizer test | registry-walker test |
|---|---|---|
| `.comment` | `Linker: Debian LLD 21.1.8` | `Linker: Debian LLD 21.1.8` |
| DWARF version | **4** | **4** |
| compile units | 1 | 2 |
| `DW_AT_language` | `DW_LANG_C99` | `DW_LANG_C99` |
| `DW_AT_producer` | `zig 0.16.0` | `zig 0.16.0` |
| `DW_TAG_ZIG_padding` (`0xfdb1`) | **0** | **0** |
| sections | `.debug_loc`, `.debug_ranges`, `.debug_pubnames`, `.debug_pubtypes` | same |

Four independent discriminators, each decisive on its own:

1. **DWARF version 4.** The self-hosted emitter writes 5 unconditionally
   (`src/link/Dwarf.zig`, `hw.writeInt(u16, 5, ...)`).
2. **Section set.** `.debug_loc` / `.debug_ranges` / `.debug_pubnames` /
   `.debug_pubtypes` are DWARF-4 and GNU pubnames shapes. The self-hosted
   emitter produces `.debug_loclists`, `.debug_rnglists`, `.debug_line_str` and
   no pubnames at all.
3. **Zero `ZIG_padding` DIEs.** That vendor tag is the self-hosted emitter's own
   entry-gap filler (`src/link/Dwarf.zig`, `AbbrevCode.ZIG_padding`). Its
   objects are full of them; these binaries have none.
4. **`DW_AT_language (DW_LANG_C99)` and `DW_AT_producer ("zig 0.16.0")`.** Both
   come from the LLVM path and are traceable to source: the producer string is
   built at `src/codegen/llvm.zig` (`"zig {d}.{d}.{d}"`, deliberately without
   the git revision), and the language is frozen at
   `lib/std/zig/llvm/ir.zig` in the compile-unit record
   (`.{ .literal = std.dwarf.LANG.C99 }`).

The compile commands recorded in `args/` confirm the configuration:
`-OReleaseSafe`, with **no** `-fno-llvm` and **no** `-fllvm`, i.e. ordinary
default backend selection. The backend was NOT inferred from any filename.

## What is actually duplicated between the two consumers

`.debug_str`, extracted by section offset and compared as NUL-separated
strings:

| | distinct strings | bytes |
|---|---|---|
| tokenizer | 21,059 | 928,630 |
| registry walker | 8,372 | 299,829 |
| **present in both** | **6,249** | **212,470** |

Both sections already carry `SHF_MERGE｜SHF_STRINGS` (`MS`), so a linker
deduplicates them WITHIN one link; nothing shares them ACROSS links, because
those are separate output files.

Note the shape: the tokenizer binary has exactly ONE compile unit covering the
whole program. Cross-binary reuse at CU granularity is therefore not available
here --- each binary's single CU is unique to that compilation. Whatever is
reusable is BELOW the CU.

## Facilities that do not exist here

A grep over `src/` for `split_dwarf｜SplitDwarf｜gsplit-dwarf｜\.dwo｜dwo_name｜
DwoId｜debuglink｜only-keep-debug｜separate.debug` returns only unrelated
`.dword` operand names. The declared debug options are `-fstrip`, `-gdwarf32`
and `-gdwarf64` (`src/main.zig:1689-1695`). The C++ shim sets only
`opt.MCOptions.ABIName` (`src/zig_llvm.cpp:146`); `EmitOptions`
(`src/codegen/llvm/bindings.zig:88`) has no split-debug member.

So there is no existing split-debug or packaging facility to reuse. That is a
measured absence, named with the greps that produced it.

## The increment landed on this path: the compile unit can carry an identity

The compile-unit bitcode record froze the two fields split debug needs:

```
.{ .literal = std.dwarf.LANG.C99 },  // source language
.{ .literal = 0 },                   // split debug file name
.{ .literal = 0 },                   // DWO ID
```

A frozen literal cannot express an identity, so nothing downstream could ever
reference a shared unit. The DWO ID position is now a real operand fed from
`Builder.dwo_id`, derived in `src/codegen/llvm.zig` at emit time.

`splitDebugFilename` was deliberately NOT set. Measured with `llc-21` on a
hand-written CU: setting it emits `DW_AT_GNU_dwo_name("a.dwo")` but **no**
`.dwo` sections, because the actual split needs an emit stream that lives in
the C++ shim. That would be a dangling reference to a file that does not exist
--- exactly the debugger breakage this must not introduce. Setting `dwoId`
alone emits `DW_AT_GNU_dwo_id` and nothing else, which the same probe
confirmed.

### Verified on real binaries, on this backend

Two separately compiled substantive consumers, both `-OReleaseSafe`, both
`Linker: Debian LLD 21.1.8`, both DWARF 4 --- the same shape as the consuming
project's own binaries:

| Artifact | `DW_AT_GNU_dwo_id` | |
|---|---|---|
| consumer 1 (two modules) | `0xd4f663650c72cd8c` | distinct |
| consumer 2 (different program) | `0x1750d47c1de65194` | distinct |
| consumer 1, musl ABI | differs | distinct |
| consumer 1, `-ODebug` | differs | distinct |
| `-fstrip` | **absent**, 0 debug sections | fail-closed |

`gdb` resolves BOTH binaries through the emitted debug information: source
line, `ptype` struct layouts, args and locals.

### RESIDUAL --- repeated-build equality holds at Debug, NOT at ReleaseSafe

| Configuration | 3 repeated builds of one program |
|---|---|
| `-ODebug` | `0xf972a57cf4b15d23` x3 --- **stable** |
| `-OReleaseSafe` | three different values --- **unstable** |

Two `-OReleaseSafe` binaries of identical input differ in **exactly 8 bytes**:
the identity itself. The rest of the compilation is byte-identical, so the
instability is in the derivation, not in the compiler's output.

Bisected: hashing ONLY `sub_file_path` per file --- no ZIR content at all ---
is also unstable. So the varying input is the **membership of
`Object.debug_file_map`**, which codegen populates non-deterministically under
ReleaseSafe, while the line-table file set that reaches the artifact is
identical (293 files in both runs).

The failure direction is FALSE-DISTINCT: identical compilations may be given
different identities, so reuse is MISSED. It can never mark two different
compilations as interchangeable. That is the safe direction, but it means the
value is not yet dependable for reuse under the configuration the consuming
project actually uses.

**Still missing, named:** a deterministic contributing-file set under
ReleaseSafe; any actual sharing of debug bodies between consumers; any size
reduction; and the `.dwo` emit stream (C++ shim) without which no shared unit
can be referenced. A stable whole-compilation identity is a PREREQUISITE, not
sharing --- and with one compile unit per binary, whole-CU reuse between two
different programs is not available regardless.
