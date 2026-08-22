# CGM Crown — Zig Compiler Internals Map

> **Mapped by:** Sonnet readers (7 parallel file passes, verified line citations) + Opus synthesis.
> **Date:** 2026-08-22.
> **Subject:** `/K3D/GitHub/cgm-zig` — fork of Zig 0.16.0, verbatim public source at time of read.
> **Purpose:** anchor document for the module-artifact cache work. Stages referenced throughout:
> **stage 0** = emit the resolved module graph as JSON; **stage 2a** = attribute analysis work to its owning module; **stage 2b** = DWARF dedup-by-reference across compile units; **stage 2c** = per-module content-addressed artifact cache.
> Every `file:line` below was produced by a reader against this tree and spot-checked during synthesis. Where two readers disagreed, the disagreement is called out explicitly rather than averaged away (see §3.4 and §4.3).
> **Anchor pin:** all line citations are valid as of commit `16f5299f` (the tree the readers walked). Later patches shift anchors below their insertion points — first instance: patch/003's comment inserts move `Zcu.zig` anchors above line 150 by +4 and `Zcu/PerThread.zig` anchors above 2701 by +9 (~30 rows affected; the pre-merge review enumerated them). Resolve a stale anchor by reading the cited identifier at `16f5299f`, or re-anchor rows as they are consumed.

---

## 1. How a compilation flows through these files

One `zig build-exe` invocation moves through seven files in a fixed order. Nothing later in the chain ever looks back at `argv`.

**Phase A — CLI to typed options (`src/main.zig`).**
`buildOutputType()` declares one mutable local per user-facing knob at the top of the function (`src/main.zig:868-877` for the `emit_*` family), then runs a single giant sequential `if/else-if` chain that maps flag strings onto those locals (`src/main.zig:1554-1577` for `-femit-asm` / `-femit-llvm-ir` / `-femit-llvm-bc` / `-femit-docs`). After the loop, a resolution stage converts each three-state CLI `Emit` (`src/main.zig:736`) into the two-state `Compilation.CreateOptions.Emit` (`src/main.zig:3424-3436`). All of it converges into one ~100-field struct literal handed to `Compilation.create` (`src/main.zig:3559`, emit fields at `3572-3578`).

**Phase B — module graph construction (`src/Package/Module.zig`, called from `main.zig`).**
Before `Compilation.create` runs, `main.zig` has already built every `*Package.Module`: CLI `-M` modules via `Package.Module.create` (`src/main.zig:4190-4199`), and `build.zig` dependency modules with parent-prefixed names (`src/main.zig:5482-5486`, `"root.@dependencies.{s}"`). Each `Module` carries its own `deps: StringArrayHashMapUnmanaged(*Module)` (`src/Package/Module.zig:15,38`) — the module graph exists as fully-resolved compiler state *before any source file is read*.

**Phase C — `Compilation` construction (`src/Compilation.zig`).**
`Compilation.create` (`src/Compilation.zig:1856`) resolves each `Emit` to a final `?[]const u8` (`2292-2297`), builds the optional `Zcu`, then makes exactly one call — `pt.populateModuleRootTable()` at `src/Compilation.zig:2316-2324` — which BFS-walks `Module.deps` from `{std_mod, root_mod, main_mod}` and fills `zcu.module_roots` (`src/Zcu.zig:113`). Immediately after, it switches on `cache_mode` to build the `CacheUse` union (`src/Compilation.zig:1521`, modes at `1481`).

**Phase D — the update driver (`src/Compilation.zig:2879` `update()`).**
Cache-mode dispatch (whole-mode obtains one `Cache.Manifest`, `2924-2926`) → `analysis_roots_buffer` seeded with `std_mod`, optionally `main_mod`, and `compiler_rt`/`ubsan_rt`/`zigc` from `root_mod.deps` (`3038-3077`) → `performAllTheWork` (`4477`) → error gate → `flush` → whole-mode rename + `man.writeManifest()` + lock handoff (`3229-3247`).

**Phase E — analysis (`src/Zcu/PerThread.zig:140` `pt.update`).**
Parallel AstGen over all files (`196`) → `computeAliveFiles` (`219` call site, body `2591`) which BFS-walks ZIR import edges and *stamps* `file.mod` (`2615`, `2732`) → `updateZirRefs` → the central work loop `while (try zcu.findOutdatedToAnalyze()) |unit|` (`324`) dispatching each `AnalUnit` to its `ensureXUpToDate` / `analyzeX` pair, which builds a `Sema` + `Sema.Block` and eventually hands AIR to codegen (`2313`).

**Phase F — interning (`src/InternPool.zig`).**
Every type and comptime value from every module lands in one flat 32-bit `Index` space, structurally deduplicated compilation-wide. Storage is partitioned by *worker thread* (`Local`, `src/InternPool.zig:960`) and lock-striped by *thread count* (`Shard`, `1454`; sizing proof in `init()` at `6247-6304`). The incremental dependency graph (`AnalUnit` → `Dependee` via `DepEntry`, `422-958`) lives directly on this struct.

**Phase G — debug info (`src/link/Dwarf.zig` + `src/link/ConstPool.zig`).**
One DWARF compile Unit per `*Package.Module` (`src/link/Dwarf.zig:30`, lazily created in `getUnit` at `2526`), one Entry per Nav (`33`), and global type/value dedup already handled by `link.ConstPool` keyed on `InternPool.Index` (`src/link/ConstPool.zig:146`), with a general deferred cross-unit / cross-section relocation system (`src/link/Dwarf.zig:1139-1156`) making "emit once, reference many" already-working machinery.

**The single most important structural fact of the whole flow:** the module graph is known and complete at the *end of Phase C* — before AstGen, before Sema, before codegen. Everything stage 0 needs already exists at `src/Compilation.zig:2324`.

---

## 2. Per-file sections

### 2.1 `src/Package.zig` + `src/Package/Module.zig` — the module node

**Purpose.** `Package.zig` owns package/project identity primitives for the fetch system: `Fingerprint` (author-declared id + CRC32), `Hash` (filesystem-safe SHA-256 content hash of a fetched snapshot), and `ProjectId` (a small, renaming-tolerant, genuinely hashable identity). `Module.zig` owns the `Module` struct — "corresponds to something that Zig source code can `@import`" (`src/Package/Module.zig:1`).

| Structure | Line | Role |
|---|---|---|
| `root: Compilation.Path` | `Module.zig:4` | Module filesystem root. "Only files inside this directory can be imported" (`:3`) — a real import sandbox boundary. |
| `root_src_path` | `Module.zig:6` | Root source file, relative to `root`. |
| `fully_qualified_name` | `Module.zig:8` | Display name, `"root.foo.bar"`. Built by callers, not by `Module.zig`. |
| `deps: Deps` | `Module.zig:15` | Import-name → `*Module` edge table. **Excludes `std`/`root`/`builtin` by design** (`:9-14`). |
| `Deps` | `Module.zig:38` | `std.StringArrayHashMapUnmanaged(*Module)` — the adjacency type. |
| `Tree.build_module_table` | `Module.zig:42` | `MultiHashHexDigest` → `*Module` exposing that package's `build.zig`. |
| per-module compile knobs | `Module.zig:17-36` | `resolved_target`, `optimize_mode`, `code_model`, `single_threaded`, `sanitize_c/thread`, `fuzz`, `pic`, `strip`, `stack_protector`, `red_zone`, `unwind_tables`, `cc_argv`, `structured_cfg`, `no_builtin`. All flat, all resolved. |
| `CreateOptions.Inherited` | `Module.zig:61` | Every knob as `?T`: null = inherit from parent, set = override. |
| `create()` | `Module.zig:110` | Full constructor; resolves Inherited + parent + global `Config`; asserts per-module flags against global `any_*` flags (`110-116`). |
| `createLimited()` | `Module.zig:420` | AstGen-only cheap variant. Leaves Sema-relevant scalars `undefined`; "Illegal behavior occurs if a limited module touches Sema" (`:418-419`). |
| `createBuiltin()` | `Module.zig:451` | Synthesizes `@import("builtin")`, on-disk at `"b/" ++ Cache.binToHex(opts.hash())` (`:452`). Lives outside `deps`. |
| `getBuiltinOptions()` | `Module.zig:490-514` | Mixes per-module fields with **global** `Compilation.Config` fields (`use_llvm`, `link_libc`, `pie`, `output_mode`, `is_test`, `wasi_exec_model`). |
| `Package.Hash` | `Package.zig:44` | SHA-256 content hash of an exact fetched-package snapshot. |
| `Package.ProjectId` | `Package.zig:174-196` | `padded_name[32]` + `fingerprint_id`, with real `.eql()` (`188`) and `.hash()` (`192`). |

**The headline.** A `*Package.Module` is **not a hashable value type**. It is arena-allocated and compared purely by pointer identity everywhere in-tree — the only de-dup mechanism actually exercised is `std.AutoArrayHashMapUnmanaged(*Package.Module, []const u8)` at `src/Compilation.zig:4849`, which hashes pointer bits. `Module.zig` defines no `.hash`/`.eql`. Pointer identity is valid only for one compiler process's arena lifetime; it cannot cross processes.

The one genuinely value-typed hashable identity in this pair of files is `Package.ProjectId` (`Package.zig:174-196`) — but it is *project*-scoped (build.zig.zon level), not module-scoped.

### 2.2 `src/Compilation.zig` — scheduler and cache-lifecycle owner

**Purpose.** Owns the `Compilation` struct (gpa/arena/io, one `root_mod`, one `Config`, one `CacheUse`, an optional `*Zcu`, `bin_file`, C/RC object queues, all `emit_*` paths), the cache machinery threading `std.Build.Cache` through none/incremental/whole strategies, `create()`, and `update()`/`flush()`/`performAllTheWork()`.

| Structure | Line | Role |
|---|---|---|
| `emit_bin` … `emit_docs` fields | `272-292` | Final resolved `?[]const u8` per artifact. "Non-`null` iff we are emitting X. Does not change for the lifetime of this `Compilation`. Cwd-relative if `cache_use == .none`. Otherwise, relative to our subdirectory in the cache." |
| `Path.addToHasher` / `Path.digest` | `430-440` | "Relocatable across any compiler process using the same lib and cache directories; it does not depend on cwd" (`428-429`). Hashes `{root enum tag, sub_path}`. |
| `cache_helpers.addModule` | `1395-1414` | Hashes one module's *settings* into a `Cache.HashHelper`: resolved target, optimize, code model, single_threaded, error_tracing, valgrind, pic, strip, omit_frame_pointer, stack_check, red_zone, sanitize_c, sanitize_thread, fuzz, unwind_tables, structured_cfg, no_builtin, cc_argv. |
| `CacheMode` | `1481` | `enum{none, incremental, whole}`, semantics documented inline. |
| `CacheUse` | `1521` | `union(CacheMode)`; `Whole` (`1540`) owns `cache_manifest: ?*Cache.Manifest` + `Lock`. |
| `CreateOptions` | `1583` | The one struct crossing the CLI boundary; emit fields at `1604-1610`. |
| `CreateOptions.Emit` | `1745` | `union(enum){no, yes_cache, yes_path}`; `.resolve()` at `1755-1773` (`yes_cache` asserts `cache_mode != .none`; `yes_path` asserts `== .none`). |
| `addModuleTableToCacheHash` | `1777-1799` | Iterates `zcu.module_roots`, **skipping `std_mod` and builtin roots as "redundant"**, folding each module via `cache_helpers.addModule` into ONE shared `HashHelper`. |
| `create()` | `1856` | Emit resolution (`2292-2297`), then `pt.populateModuleRootTable()` (`2316-2324`), then `CacheUse` construction. |
| `update()` | `2879` | Cache dispatch (`2918-2930`) → analysis roots (`3038-3077`) → `performAllTheWork` → gate → `flush` → whole-mode rename + `writeManifest` (`3229-3247`). |
| `flush()` | `3322` | Terminal step of every update. |
| `performAllTheWork()` | `4477` | Prelink concurrently; **docs emission dispatched as an independent `misc_group.async` task at `4508-4512`, gated on `comp.emit_docs != null` + `dev.check(.docs_emit)`**; then all Zcu work through one `pt.update` at `4522`. |
| `docsCopyModule` seen_table | `4849` | `AutoArrayHashMapUnmanaged(*Package.Module, []const u8)`, seeded with `main_mod` + `std_mod` (`4852-4853`), then BFS over `mod.deps.values()`. |

**The headline.** The resolved module set is **not a `Compilation` field**. It lives on `Zcu.module_roots`. `Compilation.zig` is the scheduler and cache-lifecycle owner; there is currently **no per-module cache granularity anywhere in this file** — every module's settings are hashed, but all into one stream feeding one `Cache.Manifest`.

### 2.3 `src/Zcu.zig` — the semantic core

**Purpose.** "Each `Compilation` has exactly one or zero `Zcu`" (`:1-6`). Holds ONE `InternPool` (`178`) and a family of `AnalUnit`-keyed tables (`analysis_in_progress`, `failed_analysis`, `outdated`, `potentially_outdated`, `reference_table`, exports — `180-333`) spanning every module. There is no per-module partition at this layer.

| Structure | Line | Role |
|---|---|---|
| `module_roots` | `113` | `AutoArrayHashMapUnmanaged(*Package.Module, File.Index.Optional)`. "Populated as soon as the `Compilation` is created. Guaranteed to contain all modules, even builtin ones." Modules whose root isn't Zig/ZON get `.none`. |
| `import_table` | `128` | Compilation-wide file dedup. |
| `alive_files` | `144` | `File.Index` → `File.Reference` (the edge that discovered it). |
| `multi_module_err` | `150-154` | At most ONE global conflict record. |
| `analysis_roots_buffer` | `296` | Fixed `[5]*Package.Module` seed set for whole-program reachability. |
| `Namespace` | `844` | `parent`, `file_scope: File.Index` (`846`), decl lists. |
| `Reference` / `InlineReferenceFrame` / `TypeReference` | `787` / `802` / `833` | Whole-program adjacency ledger: AnalUnit→AnalUnit, inline-call frames (kept distinct from real references), AnalUnit→Type. All module-agnostic. |
| `File` | `937` | Per-file record; `mod: ?*Package.Module` at `985`; `module_changed: bool` at `995` for incremental invalidation when a file changes owner. |
| `File.Reference` | `1027-1036` | `union{analysis_root: *Module, import: {importer, tok, module: ?*Module}}` — *why* a file is alive. |
| `resolveReferences` | `4172` | Single BFS worklist over `types` + `units` from `analysis_roots_buffer`. |
| `navFileScope` / `navFileScopeIndex` | `4431` / `4436` | Nav → owning File shortcut via `srcInst().resolveFile()`. |
| `trackUnitSema` | `5197` | `(name, zir_inst: ?TrackedInst.Index)` — the existing begin/end instrumentation wrapper around every AnalUnit's real work. |
| `CodegenTaskPool` | `5219` | `task_funcs`/`task_air_bytes`/`task_futures` (`5241-5243`) are ONE global array keyed only by `InternPool.Index`; `max_air_bytes_in_flight` (`5225`) is one global budget. |

### 2.4 `src/Zcu/PerThread.zig` — the work engine

**Purpose.** Implements `Zcu.PerThread`, the per-thread-tagged wrapper owning every operation that mutates InternPool state during ZIR-driven analysis and codegen dispatch.

| Structure | Line | Role |
|---|---|---|
| `pt.update` | `140` | Once per incremental pass: AstGen all files → `computeAliveFiles` → `updateZirRefs` → main analysis loop. |
| worker AstGen dispatch | `196` | One `Io.Group.async` worker per `(File.Index, *File)`. Work is file-scoped; module not yet resolved. |
| `computeAliveFiles` call site | `219` | The choke point where `zcu.alive_files` and every `file.mod` become valid — the earliest full file↔module snapshot. |
| main analysis loop | `324` | `while (try zcu.findOutdatedToAnalyze()) |unit|` then `switch (unit.unwrap())` — the single consumption point for every `AnalUnit`. |
| `ensureTypeLayoutUpToDate` | `1332` | Resolves owning file via `namespacePtr(...).fileScope(zcu)` at `1400`; enqueues `.debug_update_container_type` at `1449`. |
| `analyzeNavVal` | `1668` | Resolves file via `old_nav.analysis.?.zir_index.resolveFull(ip)` at `1684-1685`. |
| `ensureFuncBodyUpToDate` | `2177` | Public entry for func AnalUnits. |
| `analyzeFuncBody` | `2266` | Runs inner, enqueues AIR onto codegen/link queue (`2313`). |
| `discoverImport` / `doImport` | `2367` / `2438` | Where an `@import` string becomes a module root or a plain file — the only place module walls are enforced. |
| `populateModuleRootTable` | `2487` | "Called once during `Compilation.create` and never again" (`2485-2486`). BFS over `Module.deps` filling `module_roots`. Note: builtin modules don't exist yet here and are added at creation time. |
| `computeAliveFiles` | `2591` | BFS from analysis roots through ZIR import edges; `file.mod = mod` at `2615`, `imported_file.mod = imported_mod` at `2732`. |
| `analyzeFuncBodyInner` | `3246` | Builds Sema + Block; resolves owning file at `3269` (`zcu.fileByIndex(decl_analysis.zir_index.resolveFile(ip))`); calls `sema.analyzeFnBody` at `3454`. |
| `runCodegen` / `runCodegenInner` | `4487` / `4542` | Sole codegen entry keyed by `func_index`; already resolves `owner_nav`'s TrackedInst at `4501-4502` for time-report keys. |

### 2.5 `src/InternPool.zig` — one flat pool, sharded by thread

**Purpose.** Structural dedup of every type and comptime value across the entire build into one 32-bit `Index` space; hosts the incremental dependency graph and the ZIR-instruction tracking layer.

| Structure | Line | Role |
|---|---|---|
| top-level fields | `22` | `locals[]`/`shards[]` sized by worker-thread count, plus 10 dependency hashmaps and `dep_entries`. |
| `src_hash_deps` | `44` | `TrackedInst.Index` → `DepEntry.Index`. The per-declaration source-hash invalidation channel. |
| `TrackedInst` | `137` | Stable per-ZIR-instruction handle; `file: FileIndex` (`138`) — the finest attribution InternPool natively has. |
| `TrackedInst.Index.resolveFile` | `179-184` | The hop from a tracked instruction to a `FileIndex`. |
| `AnalUnit` | `422` | `packed struct(u64){kind, id}`. "This is the 'source' of an incremental dependency edge" (`421`). Kinds at `426`. **No module field.** |
| `MemoizedStateStage` | `486` | `main`/`panic`/`va_list`/`assembly` — no owning Nav, namespace, or file at all. |
| `Nav` | `544` | Named Addressable Value; `analysis.zir_index` (`554`) is its TrackedInst link. |
| `Dependee` | `746` | The 10 dependency-sink kinds. |
| `DepEntry` | `925` | Doubly-linked per-dependee, singly-linked per-depender. `addDependency` at `828`. |
| `Local` | `960` | Per-WORKER-THREAD partition (`Local.Shared` at `991-1012`). |
| `FileIndex` / `File` | `1688` / `1723-1727` | `File{bin_digest: Cache.BinDigest, file: *Zcu.File, root_type}`. |
| `Shard` | `1454` | Lock-striped hashmap bucket, sized `1 << tid_width` (`6292`). |
| `Index.Unwrapped` | `4110` | `{tid, index}` via `tid_shift_30`. Nav `645`, FileIndex `1692`, TrackedInst `205`, ComptimeUnit `508` all use `tid_shift_32`. |
| `init()` | `6247-6324` | `ip.locals = gpa.alloc(Local, used_threads)` (`6253`), `ip.shards = gpa.alloc(Shard, 1 << tid_width)` (`6292`). |
| `GlobalErrorSet` | `12244` | One flat compilation-wide error-name→tag table. |
| `debug_state` / activate / deactivate | `6394-6398` / `6372-6391` | Threadlocal singleton guard: exactly one InternPool active at a time. |

**Verified negative result:** zero occurrences of the word "module" (case-insensitive) across all 12,791 lines of `InternPool.zig`. The pool has no first-class module concept whatsoever.

### 2.6 `src/link/Dwarf.zig` (+ `src/link/ConstPool.zig`) — where "emit once, reference many" already works

**Purpose.** DWARF backend shared by ELF and Mach-O. Owns a three-level intrusive byte arena (Section→Unit→Entry), the mapping of Zig concepts onto it, DIE-content generation (`WipNav`), and a deferred relocation system resolved at flush.

| Structure | Line | Role |
|---|---|---|
| `const_pool` | `28` | `link.ConstPool` — global `InternPool.Index`-keyed dedup registry for all comptime values incl. types. |
| `mods` | `30` | `AutoArrayHashMapUnmanaged(*Module, ModInfo)` — array index doubles as `Unit.Index` in all 6 module-scoped sections. |
| `values` | `32` | `ArrayList(struct{Unit.Index, Entry.Index})` indexed by `link.ConstPool.Index`. |
| `navs` | `33` | `Nav.Index` → `Entry.Index`, one DIE per function/global. |
| `decls` | `34` | `TrackedInst.Index` → `Entry.Index` for non-Nav declaration sites. |
| `ModInfo` | `76-86` | `root_dir_path`, `dirs`, `files: AutoArrayHashMapUnmanaged(Zcu.File.Index, void)` — per-module file/dir dedup. |
| `Unit` | `532` | One DWARF compile unit per source Module, index shared across aranges/frame/info/line/loclists/rnglists. |
| `Entry` | `817` | One DIE-equivalent slot per Nav / named type / anonymous const. |
| `CrossEntryReloc` … `ExternalReloc` | `1139-1156` | The deferred-reference mechanism; resolved in `resolveRelocs` (`785-813`, `1058-1131`). |
| `WipNav` | `1502` | Per-Nav accumulator carrying `.unit`/`.entry` and separate per-section writers. |
| `getValueEntry` | `2078-2085` | Single funnel for all type/value references (`refType`/`refValue` at `2069-2076`). |
| `getUnit(mod)` | `2526` | Lazy per-Module compile-unit creation; `getOrPut` on `mods`, allocating a Unit slot in all six sections with errdefer rollback. |
| `addConstInner` | `3304-3332` | **Ownership policy** for deduped constants: `.func`/`.@"extern"` → `owner_nav`'s Unit; named containers → `name_nav`'s Unit; anonymous containers → declaring file's module Unit; everything else → the global `.main` Unit (`3308`). |
| `flush()` debug_info loop | `4848-4931` | Walks `dwarf.mods.keys()` 1:1 with units, emitting `DW_TAG_compile_unit` + `DW_TAG_module` per module, embedding `mod.fully_qualified_name` (`4924`) and `mod.root_src_path` (`4896`). |
| `ConstPool.get` | `ConstPool.zig:146` | `(pool, pt, user, val: InternPool.Index) -> ConstPool.Index` — the emit-once registry. |
| `ConstPool.updateContainerType` | `ConstPool.zig:118-131` | Push-based fan-out: one type's layout resolution triggers callbacks into every dependent constant, across whatever units they live in. |

**Consequence for stage 2b:** dedup-by-reference across CUs is **not new work**. The dedup key (`InternPool.Index`), the registry (`ConstPool`), the ownership policy (`addConstInner`), and the cross-unit reference plumbing (`CrossUnitReloc`) all exist and function today. Stage 2b is adoption and *scheduling*, not invention.

### 2.7 `src/main.zig` — the flag boundary

**Purpose.** The sole place user-facing strings become typed compiler options.

| Structure | Line | Role |
|---|---|---|
| `EmitBin` | `729` | Like `Emit` plus `.yes_a_out` for `zig run`. |
| `Emit` (CLI, 3-state) | `736` | `union(enum){no, yes_default_path, yes: []const u8}`; `.resolve(io, default_basename, output_to_cache)` at `742`. |
| `var emit_*` block | `868-877` | `emit_bin`, `emit_asm`, `emit_llvm_ir`, `emit_llvm_bc`, `emit_docs`, `emit_implib`, `emit_h`. **This block IS the flag registry** — there is no declarative table. |
| `-femit-asm` parse arms | `1554-1559` | Three arms: bare → `.yes_default_path`; `mem.cutPrefix(u8, arg, "-femit-asm=")` → `.{.yes = rest}`; `-fno-emit-asm` → `.no`. |
| `-femit-docs` parse arms | `1572-1577` | Same three arms. **The cleanest template** — docs is the only existing non-object single-artifact emit. |
| `--verbose-llvm-ir` arms | `1739` | Different, simpler pattern: plain `?[]const u8`, no 3-state union, no `.resolve()`, no negation form. |
| resolution block | `3424-3436` | `default_asm_basename` via `allocPrint`, then `.resolve(...)`. `emit_docs_resolved = emit_docs.resolve(io, "docs", output_to_cache)` at `3436` — literal basename, no root_name concatenation. |
| `Compilation.create` literal | `3559` | Emit fields at `3572-3578`; verbose fields at `3645-3654`. |
| `-femit-*` help block | `456-469` | `-femit-docs[=path]` at `466`, `-fno-emit-docs` at `467`. |
| Debug Options help block | `702-719` | Where `--verbose-*` flags are documented. |

---

## 3. THE ANSWER SECTION — Where module boundaries exist, where they blur

### 3.1 Where the boundary is real and load-bearing

Five places in the compiler treat "which module" as first-class, and they are consistent with each other:

1. **The graph itself.** `Package.Module.deps` (`Module.zig:15,38`) is an explicit, enumerable, *named*-edge adjacency map. Edges are labeled by import name, not anonymous — a JSON emission can and should preserve labels.
2. **The filesystem sandbox.** `Module.root` with "Only files inside this directory can be imported" (`Module.zig:3`) is enforced at import-resolution time in `doImport` (`PerThread.zig:2438`).
3. **The resolved table.** `Zcu.module_roots` (`Zcu.zig:113`) — every module → its optional root file, complete before any file is read, built once at `Compilation.zig:2316-2324`.
4. **Per-file ownership.** `Zcu.File.mod: ?*Package.Module` (`Zcu.zig:985`), stamped at `PerThread.zig:2615` and `:2732`, non-null for every alive file during analysis, with `module_changed` (`Zcu.zig:995`) as the incremental invalidation flag — *because* "changing your module changes things like your optimization mode and codegen flags, so everything needs to be re-done" (`Zcu.zig:991-994`).
5. **Per-unit decisions during Sema.** `Sema.Block.ownerModule()` (`Sema.zig:856-859`, `zcu.namespacePtr(block.namespace).fileScope(zcu).mod.?`) is used pervasively — `strip` at `5942`/`5968`/`5991`, `error_tracing` at `6168`/`6361`/`18151`/`18225`, `pic` at `8652`. The compiler already makes codegen decisions module-relative.

And in the backend: DWARF partitions per module by construction (`Dwarf.zig:30`, `getUnit` at `2526`), literally emitting `mod.fully_qualified_name` into the debug info (`Dwarf.zig:4924`).

**Consequence:** stage 0 and stage 2a are *tapping existing joins*, not inventing state. Both readers who touched PerThread and Compilation independently reached this conclusion.

### 3.2 Where the boundary blurs — the honest list

| Blur | Citation | Why it matters |
|---|---|---|
| `deps` is not the whole graph | `Module.zig:9-14` | `std`, `root`, and `builtin` are **deliberately absent** from every `deps` table; "the rest of the compiler must detect these special names." A naive stage-0 dumper reading only `mod.deps` silently omits these edges. `module_roots` does contain them (`Zcu.zig:111-113`), so **emit from `module_roots` keys, cross-referenced with `deps` for edge labels** — not from `deps` alone. |
| `AnalUnit` carries no module tag | `InternPool.zig:422-434` | The universal work item is `{kind, id}` with an opaque id. Module identity is *always* a live multi-hop walk, never a stored field. |
| The dispatch queue is unpartitioned | `PerThread.zig:324-346` | One flat interleaved loop over all modules. Attribution cannot be read off the scheduler; it must be reconstructed per item. |
| Import module inheritance is BFS-order-dependent | `PerThread.zig:2681` (`const imported_mod = res.module_root orelse file.mod.?;`) | A plain-path import inherits the *importer's* module. Which module owns a shared file is first-discoverer-wins (conflict handling at `2694-2711`), not derivable from the path. |
| Sema does not check boundaries during body analysis | `PerThread.zig:3454` + Sema generally | Module walls are enforced only at import resolution. Once analyzing, a unit reaches into another module's Navs/types through plain InternPool indirection with no crossing marker at the touch site. |
| `MemoizedStateStage` has no owner at all | `InternPool.zig:486`, `PerThread.zig:1062` | `main`/`panic`/`va_list`/`assembly` are synthesized global state, unattributable by construction. Four singleton compilation-wide dependency chains (`InternPool.zig:79-84`). |
| Two AnalUnit kinds already drop attribution | `PerThread.zig:1388`, `:1511` | `ensureTypeLayoutUpToDate`/`ensureStructDefaultsUpToDate` call `zcu.trackUnitSema(name, null)` — passing no TrackedInst even though one is resolvable at `:1400`. The existing instrumentation seam is already lossy for these two kinds. |
| One global error set | `InternPool.zig:28`, `12244` | Error values from all modules interleave in one flat table, untagged. |
| One global codegen budget | `Zcu.zig:5225`, `5241` | `max_air_bytes_in_flight` is a single compilation-wide throttle; `task_funcs` is one array keyed only by `InternPool.Index`. |
| One global conflict record | `Zcu.zig:150-154` | `multi_module_err` stores at most one conflict, not a per-module diagnostic list. |
| DWARF's `.main` catch-all | `Dwarf.zig:3308` | Every value that isn't a func/extern/container collapses into one global compile unit mixing provenance from all modules. |
| DWARF anonymous-type placement is source-site keyed | `Dwarf.zig:3308-3327` | Generic instantiations without a `name_nav` are owned by the *declaring file's* module. Two unrelated modules sharing an instantiation both point at an entry owned by whoever declared it first. |
| `dwarf.mods` is observed-usage, not the graph | `Dwarf.zig:4762-4766`, populated lazily by `getUnit` | Only modules that actually emitted something appear. Not a substitute for `module_roots` for stage 0. |
| Whole-compilation atomicity | `Compilation.zig:3225-3247` | Flush → error gate → rename → `writeManifest` → lock is one sequence gated on a single comp-wide `anyErrors(comp)`. **Module-level partial success/failure is not representable today.** |
| `create()` validity is set-dependent | `Module.zig:110-116` | `assert(options.inherited.sanitize_thread == true → global.any_sanitize_thread)`. The `any_*` flags are pre-accumulated across ALL modules (`main.zig:3113-3133`) before any Module is built. A module's *construction* is only valid in the context of the full set. |
| "Context-free per-module" isn't | `Module.zig:490-514` | `getBuiltinOptions` mixes per-module fields with global `Config` (`use_llvm`, `link_libc`, `pie`, `output_mode`, `is_test`, `wasi_exec_model`). Anything reaching `@import("builtin")` is a function of (module, whole-compilation Config). |
| `*Module` has no completeness tag | `Module.zig:412-448` | `createLimited()` leaves most scalars `undefined`, but the type carries no marker distinguishing limited from full. Any code reading those fields for cache keys must track completeness out-of-band. |
| `fully_qualified_name` uniqueness is a caller convention | `main.zig:4195` vs `:5482-5486` | CLI `-M` modules get the raw key verbatim; build.zig deps get `"root.@dependencies.{hash}"`. The dotted convention documented at `Module.zig:8` is enforced by callers, not structurally. **Do not use the name as a stage-0 node key** — use it as a label and key on something else. |

### 3.3 The one-sentence join

**Module boundaries are real and complete *before* analysis (the graph, the sandbox, `module_roots`, `File.mod`) and real again *after* analysis (DWARF units, per-module codegen flags via `ownerModule()`); they blur precisely in the middle — the analysis engine's work queue, work-item type, intern pool, error set, dependency graph, and success/failure granularity are all compilation-global.** Stage 0 lives entirely in the "before" region and is therefore cheap. Stage 2a lives in the blur and is a matter of instrumentation. Stage 2c lives in the blur *and* needs the "after" region to become per-module-atomic, which it currently is not.

### 3.4 One reader disagreement, resolved

Reader 1 characterized `Compilation.Path.digest()` (`Compilation.zig:436-440`) as "the only stable, cross-process **content** hash" available for cache keys. Reader 5, working from `InternPool.File.bin_digest` (`InternPool.zig:1724`, set from `path.digest()` at `PerThread.zig:2409`/`2554`/`2800`), showed it is a hash of `{root enum tag, sub_path}` — a **path-identity** hash, not a content hash.

**Reader 5 is correct; verified at `Compilation.zig:430-434`.** `Path.digest()` hashes the path bytes and the root enum tag only. It is the right primitive for "is this the same file across two runs" (already serialized for exactly that at `Compilation.zig:3782`) and the **wrong** primitive for "has this file's content changed." Using it as a stage-2c content key would be a silent, real bug: it does not change when the source text changes.

---

## 4. The InternPool question

*How does per-file ZIR caching compose with a single global intern pool, and what does that mean for stage 2c's feasibility ordering?*

### 4.1 The honest current answer: they compose only in one direction

Per-file ZIR caching already works and is genuinely per-file. AstGen runs per file in parallel (`PerThread.zig:196`), producing ZIR that carries a real 128-bit content hash per declaration (`lib/std/zig/Zir.zig:2740-2743`, `src_hash_0..3`, documented as "should be concatenated and reinterpreted as a `std.zig.SrcHash`"). InternPool consumes that hash as the invalidation key via `src_hash_deps` (`InternPool.zig:42-44`, `.src_hash` arm of `addDependency` at `877`). **This is genuine, already-wired content-addressing machinery** and stage 2c should reuse it rather than compute a new hash over declaration bytes.

But everything downstream of ZIR — the interned types and values, the Navs, the dependency edges — lands in one pool whose only partition axis is **worker thread count**, proven by `init()` (`InternPool.zig:6250-6253`: `ip.locals = gpa.alloc(Local, used_threads)`; `6292`: `ip.shards = gpa.alloc(Shard, 1 << tid_width)`). Every handle type packs `{tid, local_offset}` (`Index.Unwrapped:4110` shift_30; `Nav.Index:645`, `FileIndex:1692`, `TrackedInst.Index:205`, `ComptimeUnit.Id:508` all shift_32). And a `tid` is a worker slot reused across the whole build — it says nothing stable about which module was being analyzed. **There is no raw module-keyed index variant to substitute.**

So: **ZIR caching composes upward into the pool fine (the pool consumes ZIR hashes as invalidation keys); the pool does not compose downward into per-module artifacts (it cannot be sliced by module).**

### 4.2 Why a per-module slice of the pool is not merely missing but structurally contradicted

Three independent facts, each verified:

1. **Interning is *global structural* dedup by design.** The whole point of `getOrPutKey` (`~7024-7193`) is that a structurally identical type has ONE canonical `Index` compilation-wide. A struct's `field_types` (`~3206`) may point at Indexes interned by any thread on behalf of any module. "Which module owns this Index" is not decidable from the Index — only the *declaration site* is recoverable, and only transitively, and never the uses.
2. **The dependency graph crosses modules untagged.** `markDependeeOutdated` / `markTransitiveDependersPotentiallyOutdated` (`Zcu.zig:3114-3273`) operate on one global `AnalUnit` graph (`outdated`/`potentially_outdated`, `274-287`). PO-cascades and dependency loops (`199-205`) cross module boundaries with no marker. A cross-module reference in `resolveReferencesInner` (`Zcu.zig:4178-4373`) looks identical to an intra-module one.
3. **The singleton is enforced.** `debug_state` (`InternPool.zig:6394-6398`) is a threadlocal `?*const InternPool` and `activate`/`deactivate` (`6372-6391`) assert exactly one pool is active at a time, compilation-wide.

**Therefore: any per-module view of the pool must be a projection/filter over the single pool, not a natural sub-object of it.** That is a design constraint, not a TODO.

### 4.3 What "attribution" actually costs

The chase from any interned entity to its module, with no helper existing today:

```
Nav / LoadedStructType / LoadedUnionType / LoadedEnumType / AnalUnit
  → TrackedInst.Index        (Nav.analysis.zir_index, InternPool.zig:554;
                              LoadedStructType.zir_index, :3177)
  → TrackedInst.Index.resolveFile(ip)                    InternPool.zig:179-184
  → FileIndex
  → ip.getLocalShared(tid).files.acquire().view()[idx].file : *Zcu.File
                                                          InternPool.zig:1723-1727
  → .mod : ?*Package.Module                               Zcu.zig:985
```

Alternative 3-hop route from any live analysis context, allocation-free: `Sema.Block.namespace` → `Namespace.file_scope` (`Zcu.zig:846`) → `File.mod` (`Zcu.zig:985`), already packaged as `Sema.Block.ownerModule()` (`Sema.zig:856-859`).

`TrackedInst` is per-**file** (`InternPool.zig:138`), not per-module — module is always one hop further out and always a live walk.

### 4.4 Feasibility ordering for stage 2c — the ruling this section exists to produce

**Ordering, easiest to hardest:**

| Rank | Stage | Why |
|---|---|---|
| 1 | **Stage 0** | All state exists at `Compilation.zig:2324`, before any analysis. Pure read + serialize. No pool involvement whatsoever. |
| 2 | **Stage 2b** | The dedup key (`InternPool.Index`), registry (`ConstPool.zig:146`), ownership policy (`Dwarf.zig:3304-3332`), and cross-unit reference plumbing (`Dwarf.zig:1139-1156`) all already exist and work. This is adoption + scheduling. A second working precedent exists in abbrev-code dedup (`Dwarf.zig:4691-4709`, single shared `.main` unit). |
| 3 | **Stage 2a** | One instrumentation seam already wraps every analysis unit (`trackUnitSema`, `Zcu.zig:5197`, 7 call sites in PerThread at `1215, 1388, 1511, 1618, 1980, 2222, 3040`). Work: thread the two currently-`null` `zir_inst` args (`1388`, `1511`), then resolve. Real but bounded. |
| 4 | **Stage 2c** | Blocked on three things none of the other stages need. |

**The three specific blockers for 2c, stated plainly:**

- **B1 — no per-module cache scope exists.** `cache_helpers.addModule` (`Compilation.zig:1395`) already hashes exactly the right per-module settings, but every caller folds it into ONE `HashHelper` feeding ONE `Cache.Manifest` (`addModuleTableToCacheHash`, `1777-1799`; manifest obtained at `2924-2926`). A per-module cache needs one `Cache.Manifest` per module. That plumbing does not exist.
- **B2 — the key is not context-free.** A module's effective semantics depend on the global `Compilation.Config` through `getBuiltinOptions` (`Module.zig:490-514`) and on the whole module set through the `any_*` assertions (`Module.zig:110-116`). So the 2c key is `hash(cache_helpers.addModule(mod)) + hash(module's file set via ZIR src_hash) + hash(the Config fields that reach @import("builtin"))`. It is not `hash(module)`.
- **B3 — no per-module atomicity.** Success/failure and artifact commit are whole-compilation (`Compilation.zig:3225-3247`), and DWARF's `freeNav()` is a no-op stub (`Dwarf.zig:4686-4689`) meaning debug entries are never reclaimed on invalidation. A 2c cache cannot piggyback on any existing lifecycle; it must own its own invalidation.

**Ruling: 2c is feasible but is the *last* stage, and it should be attempted only after 2a exists** — because 2a's attribution is precisely the projection function 2c needs to know which pool entries belong to which module's artifact. Attempting 2c before 2a means building attribution twice.

**And one guardrail, restated because it is the cheapest possible mistake to make:** the content key comes from ZIR `src_hash` (`Zir.zig:2740-2743`), never from `File.bin_digest` (`InternPool.zig:1724`), which is `path.digest()` and does not change when source text changes.

---

## 5. Stage-0 landing sites

Everything below is a verbatim-copyable anchor. The flesh stage should not need to re-explore.

### 5.1 The pattern to copy: `-femit-docs`

`-femit-docs` is the correct template — it is the only existing single-artifact, non-object emit, and its resolution uses a literal basename rather than `root_name` concatenation. Do **not** copy the `--verbose-llvm-ir` pattern (`main.zig:1739`): it is a plain optional string with no three-state union, no `.resolve()`, and no negation form.

### 5.2 The seven edits, in order

**(1) Declare the variable.** `src/main.zig`, in the block at `868-877`, adjacent to `var emit_docs: Emit = .no;` (line `872`):

```zig
var emit_module_graph: Emit = .no;
```

**(2) Add three parse arms.** `src/main.zig`, cloning `1572-1577` verbatim:

```zig
} else if (mem.eql(u8, arg, "-femit-module-graph")) {
    emit_module_graph = .yes_default_path;
} else if (mem.cutPrefix(u8, arg, "-femit-module-graph=")) |rest| {
    emit_module_graph = .{ .yes = rest };
} else if (mem.eql(u8, arg, "-fno-emit-module-graph")) {
    emit_module_graph = .no;
```

**(3) Resolve after the loop.** `src/main.zig`, adjacent to line `3436`:

```zig
const emit_module_graph_resolved = emit_module_graph.resolve(io, "module-graph.json", output_to_cache);
```

**(4) Pass it across the boundary.** `src/main.zig`, in the `Compilation.create` literal, next to `.emit_docs = emit_docs_resolved,` at line `3577`:

```zig
.emit_module_graph = emit_module_graph_resolved,
```

**(5) Add the option field and the final field.** `src/Compilation.zig`:
- `CreateOptions` field beside `emit_docs: Emit = .no,` at `1610`: `emit_module_graph: Emit = .no,`
- Resolve it in the struct literal beside `2297`: `.emit_module_graph = try options.emit_module_graph.resolve(arena, &options, .module_graph),`
- Final `?[]const u8` field beside `emit_docs` at `292`, with the same three-line doc comment convention used at `289-291`.

**(6) Register the artifact kind (do not miss this one).** `lib/std/zig.zig:980-1010` — `EmitArtifact` is an enum (`bin, @"asm", implib, llvm_ir, llvm_bc, docs, pdb, h, compiler_rt_dyn_lib`) whose `cacheName` (`994-1009`) maps each to a suffix (`docs => "-docs"` at `1003`). A new `.module_graph` variant plus its suffix is required, because `Emit.resolve`'s `.yes_cache` arm calls `ea.cacheName(...)` (`Compilation.zig:1760-1766`).

**(7) Register the dev feature flag.** `src/dev.zig` — `docs_emit` is a `Feature` (`:258`) listed in an environment support set (`:124`). `Compilation.zig:4509` calls `dev.check(.docs_emit)` before dispatching. Add the analogous feature or reuse an existing always-supported one; `dev.check` panics at comptime-guarded runtime if the environment lacks it (`dev.zig:297-300`).

**Plus, for a real upstream-shaped change:** help text. `src/main.zig:466-467` is the `-femit-docs[=path]` / `-fno-emit-docs` pair inside the General Options block (`450-470`). Omitting a matching pair is a review point.

### 5.3 The post-resolution hook site in `src/Compilation.zig`

Two candidate sites; they differ in what data is available.

**Site A — inside `create()`, at `src/Compilation.zig:2324`, immediately after `pt.populateModuleRootTable()` returns.** At this instant `zcu.module_roots` is fully populated with **every** module including builtins, and no analysis has run. This is the right site for a pure *declared graph* dump: nodes = every module, edges = every `deps` entry. Cheapest possible hook, zero interaction with analysis, deterministic output.

**Site B — inside `performAllTheWork()`, cloning the docs precedent at `src/Compilation.zig:4508-4512`:**

```zig
if (comp.emit_docs != null) {
    dev.check(.docs_emit);
    misc_group.async(io, workerDocsCopy, .{comp});
    misc_group.async(io, workerDocsWasm, .{ comp, main_progress_node });
}
```

This dispatch sits *before* the Zcu block at `4515-4523`, is fully decoupled from AIR/codegen, and is a genuine per-artifact isolation boundary. Use this site if the JSON should carry anything computed during analysis (alive-file lists, observed usage).

**Recommendation: Site A for the graph, with the writer dispatched Site-B-style if it must do I/O off the main path.** The graph content is already final at Site A; deferring buys nothing but exposure to analysis failures.

### 5.4 The traversal to emit

Do **not** hand-roll a `deps`-only walk (it silently drops `std`/`root`/`builtin`, `Module.zig:9-14`). Two correct options:

- **Preferred:** iterate `zcu.module_roots.keys()` and `.values()` — the pattern used verbatim at `Compilation.zig:1786-1788` — which is guaranteed complete (`Zcu.zig:111-112`). For each module emit `{fully_qualified_name (Module.zig:8), root.root enum + root.sub_path (Module.zig:4), root_src_path (Module.zig:6), per-module config from Module.zig:17-36}`, then emit labeled edges from `mod.deps` (`Module.zig:15,38`) preserving import-name labels.
- **Existing BFS to mirror:** `Compilation.zig:4849-4863` (`docsCopyModule`'s `seen_table` pattern — seed with `main_mod` + `std_mod`, pop `mod.deps.values()`). Swapping the tar-writing body for a JSON node emitter is a mechanical transformation.

**Node keys:** do not key on `fully_qualified_name` (caller convention only, `main.zig:4195` vs `:5482-5486`). Key on array index into `module_roots`, or on `root.digest()` + `root_src_path` if cross-process stability is wanted — with the §3.4 caveat that `digest()` is a *path* hash.

**Mark the roots distinctly.** `Compilation.zig:3038-3077` shows exactly which modules seed reachability each update: `std_mod`, `main_mod` (tests only, when `main_mod != std_mod`), and `compiler_rt`/`ubsan_rt`/`zigc` fetched from `root_mod.deps`. A useful graph distinguishes these from transitively-discovered nodes.

**Note the existing exclusion convention.** `addModuleTableToCacheHash` (`Compilation.zig:1786-1790`) skips `zcu.std_mod` and builtin root files as "redundant" for hashing purposes. That is a hashing decision, not a graph decision — stage 0 should probably *include* them and tag them, but the precedent is worth matching deliberately rather than accidentally.

### 5.5 The one constraint that binds stage 0's flag

`CreateOptions.Emit` (`Compilation.zig:1745-1753`) asserts `yes_cache` requires `cache_mode != .none` and `yes_path` requires `cache_mode == .none`. A module-graph JSON requested during a cached build therefore gets a **cache-relative synthesized name** via `ea.cacheName` (`1760-1766`), not an arbitrary user path — unless caching is off. Plan the artifact-retrieval story accordingly; this is why edit (6) above is mandatory, not cosmetic.

---

## 6. Open questions the map could not settle

1. **Ordering of a Site-B module-graph write relative to analysis.** `main.zig` alone cannot resolve whether the JSON should be emitted before, during, or after `pt.update`. Site A sidesteps this, but if the graph must carry analysis-derived data (alive files, observed usage), the phasing question returns and needs a decision, not a read.

2. **Whether builtin modules belong in the stage-0 output.** `populateModuleRootTable`'s own doc comment says builtin modules "don't yet exist" when it runs and "must be added when they are created" (`PerThread.zig:2485-2486`), while `Zcu.zig:111` claims `module_roots` is "guaranteed to contain all modules, even builtin ones." These are reconcilable (builtins are added later, before use) but the exact window in which the table is complete-including-builtins was not pinned down. **If Site A is chosen, verify empirically that builtins are present at `Compilation.zig:2324`, or accept that they are not and document the omission.**

3. **How stage 2c represents per-module partial failure.** Today success is whole-compilation (`Compilation.zig:3233`) and there is no representation of "module A cached fine, module B failed." Whether this requires restructuring `update()`'s flush/rename/manifest sequence or can be layered beside it is a design question the read could not answer.

4. **Whether `dwarf.mods`' observed-usage subset is a problem or a feature for 2b.** `getUnit` fires on demand (`Dwarf.zig:2526`), so `mods` contains only modules that emitted something. For dedup this may be exactly right; for cross-run cache validity it may be a gap. Unresolved.

5. **What invalidates a 2c entry when the global `Config` changes.** Per B2 above, `getBuiltinOptions` (`Module.zig:490-514`) makes eight global fields part of a module's effective semantics. Whether to fold all of `Config` into every module's key (safe, over-invalidating) or only the eight (precise, fragile against future Config growth) is a judgment call.

6. **Whether `ProjectId` (`Package.zig:174-196`) can serve as the durable cross-process module identity.** It is the only real value-typed hashable identity found in the whole read, with genuine `.eql()`/`.hash()`, but it is package-scoped, not module-scoped, and a package can expose multiple modules. Whether `(ProjectId, module sub-name)` is a sound composite key was not tested.

7. **`createLimited` completeness tracking.** `Module.zig:412-448` produces modules with `undefined` scalars and no tag distinguishing them. If any stage-0/2c code path can observe a limited module, it will read garbage. Whether such a path exists in practice was not traced.

8. **The two lossy `trackUnitSema(name, null)` call sites** (`PerThread.zig:1388`, `:1511`). A TrackedInst is resolvable at `:1400`; whether the same is true at `:1511` for `ensureStructDefaultsUpToDate` was not verified. Stage 2a must confirm before relying on that seam being uniformly extensible.