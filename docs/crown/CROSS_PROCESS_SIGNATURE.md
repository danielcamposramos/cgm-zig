# Cross-process constant-type signature — state matrix

Working revision `289ff31b24` (dirty), 2026-09-08. Owner file
`src/link/ConstPool.zig`. Instrument observable with
`--debug-log const_pool` on a compiler built with `-Dlog`.

## Two things live here

1. A cross-process **type signature** in `src/link/ConstPool.zig` --- an identity
   layer. It changes what the compiler knows, not what it writes; the emission
   measurement below is byte-identical, and no reduction is claimed for it.
2. A **qualifier-DIE deduplicating consumer** in `src/link/Dwarf.zig` --- this
   one does change what is written, and its reduction is measured below.

## The consumer: shared `const_type` entries

Three sites emitted a `const_type` DIE inline --- one per pointer type
(`ptr_type` path) and one per `const` declaration (two Nav paths). `*const T`,
`[*]const T`, `?*const T` and every `const x: T` each wrote their own
`const_type -> T`. They now share one entry per (unit, target, kind), created on
first use by `getQualifiedEntry` and referenced by relocation.

Measured on the two-module scale probe, `build-obj`, identical flags:

| Compiler | `.debug_info` | delta | `DW_TAG_const_type` |
|---|---|---|---|
| baseline | 2,230,145 | --- | 866 |
| ptr path only | 2,229,407 | -738 | 854 |
| **all three sites** | **2,222,422** | **-7,723** | **346** |

**520 duplicate DIEs removed, 7,723 bytes (0.35%).**

Semantic identity and debugger behavior, verified:

- `llvm-dwarfdump --verify`: 120 errors before, 120 after, **error sets
  identical** --- the 120 are pre-existing in the unmodified compiler.
- All **2515** distinct named type descriptions present before and after; the
  only textual difference is the serial number in compiler-generated anonymous
  type names (`__struct_21662` vs `__struct_21664`), which shifts because the
  emitter now interns the type entry at a slightly different point.
- `gdb` reads the qualifier correctly through the shared DIE: `ptype` still
  reports `const struct VTable *vtable`, and `ptype`/`info locals` output is
  identical apart from stack addresses.
- The signature oracle still passes 5/5 on the deduplicating compiler.

Negative control: bypass the shared entry in `finishForwardToConst` and point
the forward reference straight at the child type. The compiler **aborts** ---
`index out of bounds: index 40, len 19` at `src/link/Elf/ZigObject.zig:633`.
Restored and verified with `sha256sum -c`.

This is intra-emitter sharing. It does not touch the cross-compilation
duplication described below.

## Matrix

| Capability | State | Evidence |
|---|---|---|
| Cross-process identity for named scalars, sized ints, arrays, vectors, optionals | **implemented and proven** | oracle 5/5; shared signature `0xd0a652b0234af326` derived by two separate processes |
| Different element width / length yields a different signature | **proven** | `c_elem` `[97]u24`, `d_len` `[96]u23` controls |
| Different target yields a different signature | **proven** | `x86_64-linux-gnu` vs `-musl`: zero set overlap |
| Collision refusal names both colliding types | **proven red then green** | fired in production on the layout-only draft (`u64` vs `usize`); silent after the key-based fix |
| Pointers | **absent, refused by name** | `kind_not_yet_derivable`: constness, alignment, address space and sentinel all change the emitted entry |
| Sentinel arrays | **absent, refused by name** | sentinel is an intern index, thread-partitioned, not comparable across processes |
| Containers, functions, error sets | **absent, refused by name** | need declaration-site identity, not layout |
| Reuse of a debug entry between compilations | **absent** | nothing consumes the signature yet |
| Artifact-size reduction FROM THE SIGNATURE ALONE | **absent** | the signature changes what the compiler knows, not what it writes; sections measured identical |
| Artifact-size reduction from the qualifier-sharing consumer | **present, intra-emitter only** | -7,723 bytes on the scale probe; see the consumer section above |
| Any effect on CGM's ACTUAL build | **none** | CGM compiles through LLVM + LLD, not `src/link/Dwarf.zig`; see CGM_ACTUAL_BACKEND.md |

## Why layout is not identity

The first draft hashed resolved layout (`zigTypeTag` + `abiSize` +
`abiAlignment` + kind bits). It aborted the compiler on the first fixture:

```
thread 3994674 panic: const signature collision: 0x49823ab0dc97fa51 claimed by types 10 and 16
```

`InternPool.Index` ordinal 10 is `u64_type` and 16 is `usize_type`
(`src/InternPool.zig:3984+`). They share layout on x86_64 and are separate
DWARF entries with separate names. The refusal caught this; a version that
merely logged would have shipped a signature licensing an unsound merge.

The fix reads the intern pool key instead of restating derived layout:
`usize` is `.simple_type`, `u64` is `.int_type`. The pool already carries the
distinction, and `SimpleType` ordinals are compile-time constants, so the
distinction is stable across processes.

## Reproduce

```bash
python3 partner_tools/const_signature_oracle.py \
    --zig <compiler built with -Dlog> --out <evidence dir>
```

Five compiles, each its own process. Expected: `5/5 checks passed`.

Negative control: change `[97]u23` to `[95]u23` in
`partner_tools/fixtures/const_signature/b.zig`. Expected: the shared-signature
check FAILs and the oracle exits 1. Restore and re-run to green.

## Emission is unchanged — measured

Same fixture, same flags, promoted `0.16.0+cgm.0399d2b19b` versus instrumented
`0.16.0+cgm.289ff31b24-crownsig`, `build-obj -fno-llvm -fno-lld -ODebug`:

| Section | a.o promoted | a.o instrumented |
|---|---|---|
| `.debug_info` | 0x28ce | 0x28ce |
| `.debug_abbrev` | 0x1d5 | 0x1d5 |
| `.debug_str` | 0x11a2 | 0x11a2 |
| `.debug_line` | 0x3bf | 0x3bf |
| `.debug_aranges` | 0x90 | 0x90 |
| `.debug_loclists` | 0x30 | 0x30 |
| `.debug_rnglists` | 0x64 | 0x64 |
| `.debug_line_str` | 0x9d2 | 0x9e4 |
| `.comment` | 0xb | 0x1a |

The two that differ hold version provenance only: the `DW_AT_producer` string
and the builtin-module cache digest that the version participates in. Every
section carrying type or line content is byte-identical. `b.o` behaves the
same.

## Why no reusing consumer exists yet — measured, not assumed

The obvious next step is "an emitter that looks the signature up before
allocating an entry." Inside one compilation there is nothing for it to find.
Four independent measurements on `run2/a.o`:

1. `ConstPool.get` keys on the interned value, and `Dwarf.addConstInner`
   asserts one entry per pool index (`Dwarf.zig:3330`) --- one entry per
   interned value by construction.
2. Three compile units in the object, 12 `DW_TAG_base_type` DIEs, **all names
   distinct**. `usize` and `u64` are separate DIEs, which is why the
   layout-only signature was unsound.
3. The type names that do repeat are different types: `"builtin"` at
   `0x276` is the generated `builtin.zig`, at `0x3ef` it is
   `lib/std/builtin.zig`.
4. The remaining repeats are `DW_TAG_imported_declaration` nodes carrying
   `DW_AT_import` offsets --- the emitter already shares by reference within an
   object.

### Scale probe --- the tiny fixture was not enough to conclude from

The four checks above run on a 93-DIE object. That is too small a sample, so
the same question was put to a two-module program using real `std` generics
(`scale_root.zig` + `scale_modb.zig`, `ArrayList`, `StringHashMap`, `fmt`).

| Artifact | CUs | `.debug_info` | named type DIEs | distinct | redundant instances |
|---|---|---|---|---|---|
| `build-obj` (ONE emitter) | 4 | 2,230,145 | 1756 | 1755 | **1** |
| `build-exe` (linked) | 8 | 2,157,830 | 2296 | 2124 | **172** |

One emitter produces one redundant instance in 1756 NAMED type DIEs --- and
that one (`debug.ElfFile.searchSymtab.SearchContext`) has no `decl_line`, so it
is not even established as a true duplicate. The linked artifact carries 172,
and they resolve to **separate sub-compilations**: `DW_TAG_base_type "u64"` appears
at `0x13fce` in the `std.zig` CU at `0x13ed5` and again at `0x201768` in a
SECOND `std.zig` CU at `0x201371`, alongside two `builtin.zig` CUs. Those extra
CUs come from the `compiler_rt` and `ubsan_rt` objects, which a `-fno-compiler-rt`
control confirms are required (removing them fails the link on `__divti3`).

### Correction: counting only NAMED type DIEs understated the duplication

"Named type DIEs" excludes the derived kinds, and those DO duplicate inside one
emitter. Same `build-obj` object, counting `pointer_type`, `array_type`,
`const_type`, `volatile_type`, `subrange_type`, `subroutine_type`, `typedef` by
their full attribute tuple:

| Tag | total | redundant |
|---|---|---|
| `DW_TAG_const_type` | 866 | **522** |
| `DW_TAG_subrange_type` | 134 | **84** |
| `DW_TAG_subroutine_type` | 139 | 1 |
| `DW_TAG_pointer_type` | 566 | 0 |
| `DW_TAG_array_type` | 134 | 0 |
| `DW_TAG_typedef` | 114 | 0 |

**607 redundant DIE instances inside ONE emitter.** So an intra-emitter
deduplicating consumer IS possible, contrary to what this document said before
this measurement.

The cause is at `Dwarf.zig:3600-3608`: a `*const T` emits its own `const_type`
DIE inline, so `*const u8`, `[*]const u8`, `[*:0]const u8` and `?*const u8` each
emit `const_type -> u8`.

**The payoff is small.** An `is_const` DIE is one uleb abbrev code plus one
4-byte `ref_addr` = 5 bytes; the two `subrange` shapes are ~6. So
522x5 + 84x6 = **~3.1 KB of 2,230,145 = 0.14%**.

The design that would collect it: a `AutoHashMapUnmanaged(InternPool.Index,
struct { Unit.Index, Entry.Index })` from child type to a dedicated shared entry
holding the qualifier DIE, referenced via `infoSectionOffset` instead of emitted
inline. It must be a dedicated entry, not an offset into an existing one ---
entry contents are rewritten incrementally, so a recorded interior offset would
not stay valid.

So: intra-emitter sharing is available and worth 0.14%; cross-compilation type
sharing is worth 2.6% and is blocked; the request itself is 97.4% and CU-level.

The same holds for separately compiled objects:

| Artifact | `.debug_info` |
|---|---|
| `a.o` | 10446 |
| `b.o` | 10446 |
| `ld -r` of both | 20892 |

Zero dedup on link, and 92 of 93 type DIE names appear in both. For N objects
the duplicate share is (N-1)/N. That is the reported symptom exactly: one copy
per module/test build.

## The blocker for cross-object sharing, with citations

The DWARF mechanism for this is type units (`DW.UT.type`) referenced by
`DW_FORM_ref_sig8` --- a 64-bit type signature, which is what this increment
produces. This emitter cannot host one yet:

- Unit indices are asserted **lockstep across five sections**
  (`Dwarf.zig:2538-2555`): every `getUnit(mod)` adds the same index to
  `.debug_aranges`, `.debug_frame`, `.debug_info`, `.debug_line` and
  `.debug_rnglists`. A type unit exists only in `.debug_info`, and
  `getUnitModule` (`:2586`) resolves any unit back to a `*Module`, which a type
  unit has not got.
- The `.debug_info` header writer hardcodes `DW.UT.compile` and writes the
  `compile_unit` root DIE inline (`Dwarf.zig:4866` onward). `Unit.header_len`
  is per-unit (`:540`), so the size is not the obstacle; the single hardcoded
  header shape is.
- Every type reference would have to become `DW_FORM_ref_sig8` instead of a
  within-unit offset.

Decoupling the per-section unit index spaces is therefore the true next
increment, and it is a refactor, not a packet-sized edit. Emitting type units
half-way would produce invalid debug info, which is a worse outcome than
emitting none.

## Correction to the roadmap: type units are not where the cost is

Per-CU sizes of the linked scale probe (`.debug_info` 2,157,830):

| CU | bytes |
|---|---|
| `std` #1 | 1,463,881 |
| `compiler_rt` | 346,668 |
| `builtin` #2 | 195,453 |
| `scale_root` | 81,621 |
| `std` #2 (the duplicate) | 55,701 |
| `ubsan_rt` | 12,765 |
| `builtin` #1 | 1,308 |
| `scale_modb` | 433 |

The duplicated `std` CU is **55,701 bytes, 2.6%** of the section. Full
cross-object type sharing inside one link therefore recovers a few percent ---
worth having, but it is NOT the reported symptom.

The reported symptom is one copy per module/test build. The dominant cost is
that **every binary a project links carries its own ~1.46 MB `std` CU**. Sharing
that is CU-level, not type-level: split DWARF (`.dwo` + `.dwp`) or a debug
package, keyed by a per-CU id (`DW_AT_dwo_id`), not by a per-type signature.

This corrects an earlier claim in this document that type units were the next
required increment. They are the next increment for *type* sharing; they are
not the shortest path to the request. A per-type signature remains a correct
and reusable primitive --- it is simply not the key that CU-level sharing uses.

A third mechanism was checked and needs nothing: `.debug_str` and
`.debug_line_str` are already emitted `SHF_MERGE|SHF_STRINGS` (`MS`), matching
gcc, so linkers already dedup debug strings across objects.

## Also still absent

Pointers (fold the whole `ptr_type` key) and containers (declaration-site
identity) must be signed before any sharing is worth having: 54 of the 93 type
DIEs above are `DW_TAG_structure_type`.
