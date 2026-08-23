# patch/005 — design dossier: auto-hardware threading and edges-first build order

*2026-08-22. Design lane: read + design only — no compiler build, no `zig`
invocation of any kind was made while authoring this (another process owned this
machine's execution window). Every compile this design needs is written down in
§8 as a command with its expected observation, and none of them were run.
Nothing in `src/` is modified by this branch.*

**Anchor pin.** Every `file:line` below was read against commit `44e391fb` (this
branch's merge base, `main` at authoring time). `docs/crown/INTERNALS_MAP.md`
pins its own citations to the earlier `16f5299f`; where this dossier and the map
disagree on a line number, this dossier is the later read. Identifiers are given
alongside every line so a stale anchor is recoverable by name.

**Charter.** Two orders from the project owner, near-verbatim:

- **ORDER 1 — auto-hardware multi-core.** "Enable auto-hardware multi-core usage
  — sync and async where needed, so not a single core is 100% doing serialized
  coordination where it could spawn more parallel ones — we keep both because
  both are useful." The serial path stays a selectable member; the parallel path
  becomes the derived default where lawful.
- **ORDER 1, amendment — the probe is TOPOLOGY aware, not core-count aware.**
  "This cpu for example is 6 cores, but 2 threads per core, so 12 threads."
  Physical cores and SMT siblings are *distinct inputs*: capacity-constrained,
  cache-heavy phases derive from **physical cores**; wide, I/O-tolerant fan-out
  derives from **all logical threads**. The distinction is first-class and is
  printed. The host this design targets, **measured** by the owner
  (`lscpu -e` plus `/sys/.../topology/thread_siblings_list`): **6 physical cores
  × 2 threads = 12 logical CPUs, sibling pairing SPLIT — (0,6)(1,7)(2,8)(3,9)(4,10)(5,11)**,
  not adjacent. Consequence recorded immediately, because it changes how the
  current mitigation should be read: `taskset -c 0-3` selects CPUs 0,1,2,3, whose
  siblings are 6,7,8,9 — so the pin covers **four distinct physical cores with no
  cache-sharing siblings at all**. The existing production lever is already,
  accidentally, a physical-core pin.
- **ORDER 2 — edges-first full-build order.** "It must compile from the smallest
  to the most composed part — so it starts with edges, when doing a full build."
  Clarified: edges are the *smallest parts, the ones that compose the bigger
  ones*; the scheduler must *respect common and internal layers* — within a
  topological level the shared / most-depended-upon modules go first (highest
  fan-in first), and a module's internal pieces before its public facade. Both
  orders stay coded members: the current order remains selectable, layer-aware
  edges-first becomes the derived default for full builds.

---

## 0. Premise audit — what the brief carried in, and what the source says

Per the fork's receipt standard, corrections to the incoming brief are
first-class findings and are stated before anything is built on top of them.

| Incoming premise | Verdict | Evidence |
|---|---|---|
| `InternPool.Index` is `u30`; capacity splits per-thread as `2^30 >> ceil(log2(threads))` | **HOLDS** | `InternPool.zig:6331` `ip.tid_width = @intCast(std.math.log2_int_ceil(usize, used_threads))`; `:1591-1592` `getIndexMask` returns `maxInt(BackingInt) >> ip.tid_width`; the `u30` confinement is named at `:4139` in patch/001's comment and originates at `CaptureValue` |
| A 12-core host rounds up to a 16-way split = 67,108,863 items/thread | **HOLDS** | `used_threads = @max(available_threads, 2)` (`:6295`) → `tid_width = 4` for 9..16 → `(2^30-1) >> 4 = 67,108,863` |
| "A wider host compiles less" | **HOLDS, and is worse than stated** | The shrinking ceiling is only half of it. `Io.Threaded.async` does **not** queue past its limit — at `lib/std/Io/Threaded.zig:2100-2105` it runs the task **inline on the calling thread**. Inline-run AstGen on the main thread re-acquires tid `.main` through the threadlocal recursion shortcut (`Zcu/PerThread.zig:87-95`), so overflow work piles into **partition 0** — the same partition Sema already monopolises. Raising `-j` therefore shrinks partition 0's ceiling *and* can add load to it. |
| Pinning to 4 CPUs idles 8 of 12 cores, and that idling is what ORDER 1 exists to end | **HOLDS as a description of the symptom; the cause is one level down** | The idling is not caused by the pin alone. Semantic analysis is *architecturally serial*: `Zcu/PerThread.zig:324` is one `while (try zcu.findOutdatedToAnalyze()) |unit|` loop running on the main thread under `.activate(zcu, .main)` (`Compilation.zig:4548`). Upstream states this as the design: "1 semantic analysis thread … / N codegen threads … / 1 linker thread" ([PR #24124](https://github.com/ziglang/zig/pull/24124), merged 2025-06-13). On a Sema-dominated compile, unpinning to 12 cores does **not** fill 12 cores — it enlarges the codegen/linker/prelink lanes while Sema stays at one. ORDER 1's honest ceiling is stated in §1. |
| patch/002's `-j1` floor finding binds; keep the serial member | **HOLDS and is honoured** | `docs/crown/PATCH002_MEMO.md` (branch `patch/002-adaptive-partition`, commit `dd07c864`), Finding 3. This design never lowers `@max(available_threads, 2)` (`InternPool.zig:6295`) and never lets `tid_width` reach 0. |
| CaptureValue widening is deferred; design around `u30` | **HONOURED** | §6 states exactly where widening would delete parts of this design. |

**Two further premise corrections, volunteered:**

1. **M and K are not merely coupled — they are literally the same integer.**
   `src/main.zig:3483-3487` computes one `thread_limit` and feeds it to *both*
   the I/O concurrency limits and the InternPool partition count:
   `setThreadLimit` (`main.zig:7912-7926`) sets `io_impl_ptr.setAsyncLimit(.limited(n-1))`
   and `io_impl_ptr.concurrent_limit = .limited(n-1)`, then
   `Zcu.PerThread.Id.allocate(arena, @max(n, 2))`; the same `n` travels as
   `CreateOptions.thread_limit` (`Compilation.zig:1596`) into
   `zcu.init(gpa, io, options.thread_limit)` (`Compilation.zig:2232`) →
   `ip.init(..., thread_count)` (`Zcu.zig:2827`). There is no second knob to
   turn. That single funnel is both the disease and the cure: decoupling is a
   *two-variable* change at one site, not a refactor.

2. **The compiler has no topology probe at all, and its one core probe is
   affinity-aware.** `std.Thread.getCpuCount()` (`lib/std/Thread.zig:293`)
   returns **logical** CPUs only; on Linux it is
   `posix.CPU_COUNT(try posix.sched_getaffinity(0))` (`Thread.zig:1133-1136`).
   Nothing anywhere in `lib/std/` reads
   `/sys/devices/system/cpu/*/topology/` — grep for `thread_siblings`,
   `core_id`, `topology` across `lib/std/`: zero hits in any CPU-topology sense.
   **This makes the production `taskset` lever legible for the first time:** it
   is not merely an OS scheduling restriction bolted on from outside — because
   `getCpuCount` reads the affinity mask, pinning to 4 CPUs makes the compiler
   *itself derive* `thread_limit = 4` → `tid_width = 2` → 268,435,455 items per
   partition. The pin works by feeding the derivation, not by fighting it. That
   is also the sharpest constraint on the new probe: **any topology read must be
   intersected with the affinity mask**, or a pinned or cgroup-confined compiler
   will derive a physical-core count it is not allowed to use — silently
   over-deriving in exactly the environment where the operator was most careful.

3. **The tid pool is process-global, so K is process-global.**
   `available_tids` is a namespace-scope `var` on the `Id` enum
   (`Zcu/PerThread.zig:69`), not a field of any `Compilation`. Every
   sub-compilation created during prelink inherits `.thread_limit = comp.thread_limit`
   (`Compilation.zig:5066`, `:7508`, `:7646`) and allocates its **own**
   `ip.locals` of that size. A tid handed out by the global pool is used as a
   direct index into whichever pool is active (`getLocal`, `InternPool.zig:1446-1448`).
   Therefore **every InternPool alive in the process must have `locals.len` ≥ the
   largest tid the global pool can issue.** K cannot be chosen per-compilation.
   This is a hard invariant the (K, M_wide) design must respect and it is not
   documented anywhere upstream.

---

## 1. Phase census — who allocates into the sharded index space, and who does not

**Criterion, single and mechanical:** does the unit of work obtain a
`Zcu.PerThread.Id` and reach an `InternPool` entry point that takes `tid`
(`get`, `getReified*Type`, `getGeneratedEnumTagType`, `getDeclaredOpaqueType`,
`addMap`, `createFile`, `createNav`, …)? If yes it consumes per-partition index
space and **constrains K**. If no, it can run on as many cores as the host has,
regardless of K.

The criterion is not invented here: `src/Zcu/PerThread.zig:1-2` states it —
*"Any operation which mutates `InternPool` state lives here rather than on
`Zcu`."* Needing a `pt` **is** the allocation marker.

### 1.1 Allocating work — 8 phases, these are the K-constrained set

| # | Phase | Spawn / entry | Tid acquisition | Proof it allocates | Concurrency today |
|---|---|---|---|---|---|
| A1 | **AstGen per-file fan-out** (incl. recursive import discovery) | `Zcu/PerThread.zig:197` `astgen_group.async(io, workerUpdateFile, …)`; re-spawn at `:413` | `:371-372` `.acquire(io)` / `defer tid.release(io)` | `pt.discoverImport` → `zcu.intern_pool.createFile(gpa, io, pt.tid, …)` at `:2408` | up to `async_limit`, then **inline on the spawner** |
| A2 | **`@embedFile` workers** | `Zcu/PerThread.zig:207` `astgen_group.async(io, workerUpdateEmbedFile, …)` | `:429-430` | `pt.intern(.{ .aggregate = …})` at `:2968` and `.ptr` at `:2972` — the **whole file body** becomes interned items | same as A1 |
| A3 | **`computeAliveFiles`** | called at `Zcu/PerThread.zig:219`, body `:2591` | inherits caller's `pt` = `.main` | `createFile` at `:2553` and `:2808` | **serial, tid `.main`** |
| A4 | **`updateZirRefs`** (incremental only) | `Zcu/PerThread.zig:818` | `assert(pt.tid == .main)` at `:819` | mutates tracked-inst state on `.main`'s partition | **serial, tid `.main`**, asserted |
| A5 | **The main semantic-analysis loop** | `Zcu/PerThread.zig:324` `while (try zcu.findOutdatedToAnalyze()) |unit|`, entered under `.activate(zcu, .main)` at `Compilation.zig:4548` | `.main`, unconditionally | `Sema.zig` holds 100 `pt.intern`-family call sites — the largest allocator in the compiler | **serial, tid `.main`** |
| A6 | **Codegen workers** | `Zcu.zig:5325` / `:5328` `io.async(workerCodegenOwnedAir/ExternalAir, …)` | `Zcu.zig:5373-5374` and `:5388-5389` | `Air/Legalize.zig:1340,1348`; `codegen.zig:394,459,556,582,1114`; `codegen/x86_64/CodeGen.zig:180518,188799-188914`; `codegen/c.zig:1174,1208`; `codegen/wasm/CodeGen.zig:4476` | bounded by `max_funcs_in_flight = link.Queue.buffer_size` = 512 (`Zcu.zig:5231`, `link/Queue.zig:31`) **and** 10 MiB of AIR in flight (`Zcu.zig:5229`) |
| A7 | **The linker task** | `link/Queue.zig:67` `comp.io.concurrent(runLinkTasks, …)` | `link/Queue.zig:152-153` — acquired once and **held for the entire compilation** | `link.doZcuTask` activates a `pt` (`link.zig:1528`); DWARF interns at `link/Dwarf.zig:3687, 3757, 4247, 4748` | **exactly one**, always |
| A8 | **LLVM object emission** | `Compilation.zig:3365` `llvm_object.emit(pt, …)` inside `flush(comp, arena, tid)` (`:3346`) | inherits `flush`'s tid | `Object.emit` takes a `pt`; `flushTypePool(pt)` at `codegen/llvm.zig:1689`, `getDebugType(o, pt, ty)` at `:1948` | **serial, one**; the LLVM and SPIR-V backends additionally assert one codegen at a time (`Zcu/PerThread.zig:4612`, `:4620`) |

**The headline of the allocating column:** five of the eight (A3, A4, A5, A7,
A8) are structurally single-threaded, and four of those five run on tid `.main`.
A5 alone dominates a large frontend-bound compile. **K's job is therefore not to
spread allocation across partitions — allocation does not spread. K's only job is
to make partition 0 big enough.** Every increment of K makes partition 0 smaller
for no allocation-throughput gain, because the work that fills it is serial by
construction. This is the same conclusion patch/002 reached from the incident
side (memo Finding 2) — reached here independently from the pipeline side, and
generalised: it is not only comptime, it is all of Sema.

### 1.2 Non-allocating work — 10 phases, these can use every logical thread

| # | Phase | Spawn site | Why it never touches the parent pool |
|---|---|---|---|
| N1 | **`builtin.zig` on-disk refresh** | `Zcu/PerThread.zig:186` `workerUpdateBuiltinFile` | body at `:353-362` calls `Builtin.updateFileOnDisk(file, comp)` — **no `.acquire`, no `pt`**. A pure file write already sitting inside the AstGen group. |
| N2 | **Prelink sub-compilations** (compiler_rt, ubsan_rt, zigc, libunwind, libc++, libc++abi, TSan, glibc/FreeBSD/NetBSD/OpenBSD shared objects, 7 CRT-file families) | `Compilation.zig:4600, 4617, 4635, 4652, 4666, 4682, 4698, 4702, 4706, 4710, 4714, 4718, 4722, 4726, 4730, 4736, 4743, 4750, 4757, 4764, 4771, 4778` — 22 sites in `dispatchPrelinkWork` | each is a **separate `Compilation` with its own `InternPool`** (`Compilation.zig:5066` etc.). Work done here consumes the *sub*-pool's partition 0, never the parent's. |
| N3 | **C / C++ / assembly objects** | `Compilation.zig:4783` `workerUpdateCObject` | `:5371-5387` → `updateCObject` (`:5656`): clang, no `Zcu`, no tid. |
| N4 | **Win32 resource compilation** | `Compilation.zig:4789` `workerUpdateWin32Resource` | same shape as N3. |
| N5 | **Autodoc emission** | `Compilation.zig:4534-4535` `workerDocsCopy`, `workerDocsWasm` | tar-writing and a wasm sub-compile; the docs walk uses `*Package.Module` pointers only (`:4849`). |
| N6 | **Module-graph emission (this fork's stage 0)** | `Compilation.zig:4543` `EmitModuleGraph.worker` | JSON already built at `create()` (`:2346`); the worker only resolves a path and writes bytes. |
| N7 | **Mach-O code-signature hashing** | `link/MachO/hasher.zig:41` `group.async(io, worker, …)` | chunked SHA over the finished output file. Pure compute + positional reads. |
| N8 | **Package fetch / verify / recompress** | `Package/Fetch.zig:787, 1022, 1743, 1771`; `main.zig:5434` | runs before any `Compilation` exists. |
| N9 | **Package fork loading** | `main.zig:5290` `Fork.load` | same window as N8. |
| N10 | **Build-runner step scheduling** | `lib/compiler/build_runner.zig:1409, 1439` `group.async(io, makeStep, …)` | each step is a *separate process*. Out of the pool's universe entirely. |

**Census headline: 8 allocating phases, 10 non-allocating phases — and after the
§1.3 split, 8 allocating (one of them, A1, only in a per-file-once tail) against
11 non-allocating work bodies.** Of the 8 allocating, 5 are single-threaded by
construction and 4 of those run on tid `.main`. Of the non-allocating set, 6
(N2, N3, N4, N5, N7, and A1's body) are genuinely CPU- or I/O-heavy on a stock
build and are today throttled by a limit derived from a number that exists only
to size the intern pool.

### 1.3 A1 is not one phase — it is a wide non-allocating body with a narrow allocating tail

The charter amendment asks that "file-level AstGen class" work use **all**
logical threads. The census as written puts A1 in the allocating column, because
`workerUpdateFile` acquires a tid (`Zcu/PerThread.zig:371-372`). Both are true,
and the resolution matters enough to be its own finding:

- **The body is tid-free.** `pt.updateFile` (`Zcu/PerThread.zig:483`, body
  through `:750`) reads the source, parses, runs AstGen, and writes the ZIR
  cache entry (`zir_dir.createFile` at `:577` and `:603` — an *`Io.Dir`* file
  creation, not `InternPool.createFile`). Scanning its whole body, the only
  `pt`-qualified call is `pt.lockAndClearFileCompileError` (`:552`), whose
  implementation (`:3552-3585`) uses `pt.zcu` and a mutex and **never reads
  `pt.tid`**. No `InternPool` entry point taking `tid` is reached.
- **The tail allocates.** The import-discovery loop at `:397-425` calls
  `pt.discoverImport`, which reaches
  `zcu.intern_pool.createFile(gpa, io, pt.tid, …)` at `:2408` — but only for a
  **newly discovered** file, i.e. once per file in the closure, not once per
  import.

So A1 decomposes cleanly: parse + ZIR + cache I/O is **non-allocating and
I/O-heavy** — the exact profile the amendment marks for all logical threads —
while a short, per-file-once interning tail needs a tid. The design in §2.3
therefore treats A1 as **split**, not as allocating-throughout. This is the
single largest practical consequence of the amendment: the widest phase in the
compiler moves from the K-lane to the M_wide lane.

**Named residual, with its denominator:** the split is derived by *reading*
`updateFile`'s body, not by executing it. The scan covered lines 483–750 and
found exactly one `pt.`-qualified call (`:552`); that callee was then read from
`:3552` and uses `pt.zcu` and a mutex only. What the read does **not** cover is
indirect reachability — a helper called with `zcu` that later reaches an
`InternPool` allocator would not appear as a `pt.` token. Verification item V12
in §8 is the negative control that converts this from read to measured, and the
split must not ship before it fires.

### 1.4 One sub-phase worth separating later, named now

`Air.Liveness.analyze` (`Zcu/PerThread.zig:4573`) and the runtime-safety
`Air.Liveness.Verify` pass (`:4586-4605`) run **inside** the allocating codegen
worker but are themselves pure over AIR. Upstream deliberately put them there
("it's more efficient to do this work here instead of blocking the main thread"
— [PR #24124](https://github.com/ziglang/zig/pull/24124)). They are a candidate
for the M-pool in a later cycle; this dossier does **not** propose moving them,
because doing so trades a tid-holding worker for two hand-offs and the trade is
unmeasured. Named as a residual, not designed.

---

## 2. Decoupling verdict — can worker count be decoupled from partition count?

### 2.1 The verdict

**YES for the allocation invariant; the full form is safe. What blocks it is not
correctness but a thread-parking hazard, and the safe design is a partial form
that never parks.**

The lock-free per-thread allocation invariant is *"at most one running task holds
a given tid at a time."* It is enforced by a semaphore, not by thread identity:
`available_tids` is a stack of ids, `acquire` pops or waits on a condition
variable, `release` pushes and signals (`Zcu/PerThread.zig:69-121`). Nothing in
that mechanism knows or cares how many OS threads exist. Setting the pool to K
entries while the I/O layer runs M_wide > K workers keeps the invariant exactly:
K tasks allocate, the rest block in `acquire`.

**Strongest single cite:** `Zcu/PerThread.zig:87-121`. `acquire` is
`while (true) { if (available_tids.pop()) |tid| return tid; tid_cond.waitUncancelable(io, &tid_mutex); }`
and `release` is `available_tids.appendAssumeCapacity(tid); tid_cond.signal(io);`
— a bounded-resource semaphore whose bound is a startup parameter and whose
correctness is independent of worker count. The *only* coupling between M_wide and K
in the whole compiler is that `main.zig:7912-7926` passes the same `n` to both.

Today the two numbers are pinned equal and the pool can never starve: async limit
`n-1` + main = `n` runners, tid pool `n-1` + `.main` = `n` ids. Decoupling breaks
that exact balance deliberately.

### 2.2 What actually blocks the naive full form

Two hazards, both real, neither a correctness violation:

- **H1 — parked workers hold runner slots.** `Io.Threaded` has no work-stealing
  and no re-entrant scheduling: a worker blocked in `tid_cond.wait` occupies one
  of the M_wide runner slots doing nothing (`lib/std/Io/Threaded.zig:2074-2127`).
  If a naive design spawns M_wide AstGen tasks against K tids, M_wide−K threads
  park. That is not faster than M_wide = K; it is the same throughput plus
  context switches.
- **H2 — `io.concurrent` can fail, and one of its failures is load-bearing.**
  `link/Queue.zig:67` obtains the linker task via `io.concurrent`, which returns
  `error.ConcurrencyUnavailable` once `busy_count >= concurrent_limit`
  (`Threaded.zig:2153-2154`). The fallback path runs link tasks on the main
  thread (`Queue.zig:71-74`, `enqueuePrelink`'s else-branch at `:87-91`) — i.e.
  it re-serialises the pipeline. If a decoupled design lets M parked workers
  inflate `busy_count`, the linker can lose its concurrency slot and the whole
  build silently degrades to the serial path. Upstream has this hazard on file
  from the other direction: [`io.concurrent` can grow the pool past `cpu_count`](https://github.com/ziglang/zig/issues/25748)
  (open, 2025-10-29), and [`std.Io.Group` hangs with more tasks than threads](https://github.com/ziglang/zig/issues/26027)
  (opened 2025-11-23, milestone 0.16.0).

**Therefore the safe form is not "M_wide workers against a K semaphore". It is
partitioning the work by the census:** non-allocating phases get the full M-wide
pool and never call `acquire`; allocating phases keep a K-wide lane. No task ever
parks on a tid it cannot get, because the tasks that need tids are never
oversubscribed relative to K.

### 2.3 The design: two lanes, one pool

The compiler has exactly one `Io` implementation and one async limit, so "two
lanes" is not two thread pools — it is one pool, sized by **logical** threads,
with a **tid-admission gate sized by physical cores** in front of the allocating
work:

```
        Io.Threaded, async_limit = M_wide-1, concurrent_limit = M_wide-1
        M_wide = LOGICAL cpus  (12 on the target host)
                                   │
        ┌──────────────────────────┴──────────────────────────────────┐
        │                                                             │
  ALLOCATING LANE                                          NON-ALLOCATING LANE
  admission gate: M_alloc permits                          spawns freely to M_wide-1,
  M_alloc = K - 2, K from PHYSICAL cores                   never calls Id.acquire
  ─ A1 tail (per newly-discovered file)                    ─ A1 body: parse+ZIR+cache I/O
  ─ A2 @embedFile interning                                ─ N1 builtin.zig write
  ─ A6 codegen workers                                     ─ N2 prelink sub-compilations
  (A3,A4,A5 serial on .main; A7 holds one                  ─ N3/N4 C objects, resources
   tid for the whole run; A8 serial —                      ─ N5 docs · N6 module graph
   none of these are gated)                                ─ N7 Mach-O signing hash
```

Concretely, four edits carry it:

1. `setThreadLimit(arena, n)` becomes `setThreadLimit(arena, m_wide, k)`.
   `setAsyncLimit(.limited(m_wide - 1))` and
   `concurrent_limit = .limited(m_wide - 1)` (up from `k - 1`);
   `Zcu.PerThread.Id.allocate(arena, @max(k, 2))` — unchanged shape, new source.
2. `CreateOptions` gains `intern_partitions: usize` beside `thread_limit`
   (`Compilation.zig:1596`); `Compilation.create` passes it to
   `zcu.init(gpa, io, options.intern_partitions)` (`:2232`) instead of
   `options.thread_limit`. `comp.thread_limit` (the field at `:60`) keeps its
   present meaning — it is already only ever forwarded to sub-compilations and
   to `translateC` (`:5258`), never to the pool.
3. The allocating spawn sites (`Zcu/PerThread.zig:207` for A2 and
   `Zcu.zig:5325/5328` for A6) gate on an `M_alloc`-permit `Io.Semaphore`
   acquired **before** `group.async`, released in the worker's `defer` beside
   `tid.release`. The gate makes H1 unreachable: a task is only spawned when a
   tid is already reserved for it, so `acquire` never blocks and no runner slot
   ever parks.
4. **A1 spawns ungated** (`Zcu/PerThread.zig:197`, `:413`) up to the full
   `M_wide`, and takes its permit + tid **inside** the worker, around the
   import-discovery tail only — moving the `.acquire`/`release` pair from
   `:371-372` down to wrap `:397-425`. Per §1.3 the body needs neither. This is
   the amendment's "file-level AstGen may use all logical threads", implemented
   as a scope reduction rather than an exemption.

### 2.3.1 The third number collapses — a finding, not a shortcut

The amendment asks for `(K, M_alloc, M_wide)`. The source says **K and M_alloc
are one quantity, not two**, and presenting them as independent knobs would be a
false degree of freedom:

- A gate permit exists precisely to reserve a tid (edit 3 above), so permits and
  tids are one-to-one.
- Two tids are permanently spoken for: `.main` is held by the main thread for
  the whole compilation (`Compilation.zig:4548`), and the linker task acquires
  one at `link/Queue.zig:152` and **releases it only on return** (`:153`).
- Therefore `M_alloc = K − 2`, exactly, and there is nothing left to choose.

So the derived triple is really a derived **pair** plus one subtraction:
`(M_wide from logical, K from physical)`, with `M_alloc = K − 2` printed
alongside because it is the number an operator reasons about. If a future
measurement ever shows the two should diverge — e.g. permits below `K − 2` to
leave cache headroom — the flag `--intern-partitions` and a new
`--alloc-workers` can separate them without redesign. Until such a measurement
exists, inventing the knob would be inventing a default.

**Because K must be process-global (§0, correction 2), `intern_partitions` is
threaded to sub-compilations unchanged** — the existing `.thread_limit = comp.thread_limit`
lines at `Compilation.zig:5066`, `:7508`, `:7646` gain a sibling
`.intern_partitions = comp.intern_partitions`. Sub-compilations then get M-wide
I/O (they are N2, non-allocating in the parent's pool, and internally they are
ordinary compiles) and the same K-wide partition geometry, so a tid issued by the
global pool is in range for every pool in the process.

### 2.4 What upstream has done about this since 0.16

- **[PR #30557](https://codeberg.org/ziglang/zig/pulls/30557)** — "Replace uses
  of `std.Thread.Pool` with `std.Io`, and remove `std.Thread.Pool`", merged
  2025-12-22. This is the *origin* of the code in our base, not a change after
  it: the `available_tids` mechanism carries its own confession at
  `Zcu/PerThread.zig:66-68` — *"This is a temporary workaround put in place to
  migrate from `std.Thread.Pool` to `std.Io.Threaded` for asynchronous/concurrent
  work. The eventual solution will likely involve significant changes to the
  `InternPool` implementation."* The PR author additionally warned that
  `std.Io.Threaded`'s unwillingness to queue more tasks than CPU cores could
  regress compiler performance. That warning is precisely ORDER 1's target, and
  it is upstream's own words.
- **[PR #24124](https://github.com/ziglang/zig/pull/24124)** — "compiler:
  threaded codegen (and more goodies)", merged 2025-06-13. Establishes the
  present shape: *"1 semantic analysis thread, which generates AIR / N codegen
  threads, which process AIR into MIR / 1 linker thread, which emits MIR to the
  binary"*, and states that legalize/liveness live on the codegen threads. This
  is the architecture our census measured independently.
- **[Issue #25748](https://github.com/ziglang/zig/issues/25748)** (open,
  2025-10-29) — `io.concurrent` inflates the pool past `cpu_count`; proposal is
  to downsize on idle. Directly relevant to H2.
- **[Issue #25757](https://github.com/ziglang/zig/issues/25757)** (open) —
  threadlocal run queues and work stealing for `std.Io.Threaded`. If this lands
  upstream, H1 softens considerably and the admission gate could be simplified.
- **[Issue #26027](https://github.com/ziglang/zig/issues/26027)** (opened
  2025-11-23, milestone 0.16.0) — `std.Io.Group` hangs with more tasks than
  threads. **Honest denominator: we read the issue's opening report only; the
  comment thread and any fix were not retrievable in this lane, so its
  resolution status is UNKNOWN.** It is carried in §7 as a named risk rather
  than as a settled fact.
- **Searched and not found:** any upstream work decoupling worker count from
  InternPool partition count, any flag separating the two, or any change to
  `tid_width` derivation after 0.16.0. Denominator: five web searches plus three
  page fetches, listed above. Codeberg (upstream's new home) serves deliberate
  garbage to automated fetchers, so upstream's *issue and PR listings* could not
  be enumerated — only individually-named pages resolved. **Upstream-master state
  after 0.16.0 is therefore UNKNOWN, not "unchanged".**

---

## 3. Auto-derivation of (K, M_wide) at startup, from topology

### 3.1 The principle it answers to

Doctrine 1 (probe-first startup) and doctrine 2 (present-or-refuse-by-name):
derive from what was measured; where a capacity cannot be derived, declare it
visibly. Doctrine 4 (self-report): the derived choice is printed, once, so an
operator always knows what was chosen and why.

### 3.2 The signals that actually exist at startup

Measured against the source, not assumed:

| Signal | Available at | Cite | Usable for |
|---|---|---|---|
| logical CPU count, **affinity-masked** | before `Compilation.create` | `main.zig:3484` `std.Thread.getCpuCount()` → `posix.CPU_COUNT(sched_getaffinity(0))` (`lib/std/Thread.zig:1133-1136`) | **M_wide** |
| **physical core count / SMT sibling map** | **does not exist — must be added** | zero topology readers anywhere in `lib/std/`; the nearest precedent is the `/proc/cpuinfo` parser at `lib/std/zig/system/linux.zig:420-447`, which opens the file with `Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{})` at `:447` and streams it with a `[4096]u8` buffer | **K** |
| explicit `-j<N>` | argv parse | `main.zig:1171-1180` (`n_jobs`), help at `:455` | override |
| module count of the resolved graph | end of `Compilation.create` | `zcu.module_roots` is complete at `Compilation.zig:2334`; the fork already reads it there (`:2346`) | **K estimate** |
| import-closure file count | *not available at startup* | `zcu.import_table` is populated during AstGen (`Zcu.zig:126-128`: "reconstructed during the first call to `Compilation.update`") | — |
| prior-build item counts | **not available** | `Compilation.saveState` writes `thread_count` and per-partition lengths (`Compilation.zig:3675, 3725, 3742`) but **there is no `loadState` in this tree** (grep for `loadState` across `src/`: 0 hits) | future |

**The honest position: K cannot be derived from an *index-consumption*
measurement at startup, because the only quantity that predicts index
consumption — items interned — is knowable only after the compile that consumes
them.** But it *can* be derived from a hardware measurement that did not exist
before this amendment: the physical core count. That is the amendment's real
contribution — it replaces a heuristic over module count with a probe over
silicon.

### 3.3 The topology probe

New file, `src/Topology.zig`, modelled on `lib/std/zig/system/linux.zig`'s
`/proc` reader. Returns one struct and never guesses:

```zig
pub const Topology = struct {
    /// Logical CPUs we are ALLOWED to run on. Never the machine's total.
    logical: usize,
    /// Distinct physical cores among `logical`, or null when unprobeable.
    /// null means UNKNOWN — never 1, never `logical / 2`.
    physical: ?usize,
    source: enum { sys_topology, proc_cpuinfo, sysctl, unknown },
};
```

Per-OS probes, each with its fallback stated:

| OS | Probe | Fallback |
|---|---|---|
| Linux | for each CPU in the affinity mask, read `/sys/devices/system/cpu/cpu<N>/topology/thread_siblings_list` (or `core_cpus_list` on newer kernels), **intersect each sibling set with the affinity mask**, count distinct non-empty groups | `/proc/cpuinfo` `physical id` + `core id` pairs, using the existing parser shape at `lib/std/zig/system/linux.zig:420-447` |
| macOS | `sysctlbyname("hw.physicalcpu")` alongside the `hw.logicalcpu` the tree already reads (`lib/std/Thread.zig` `getCpuCount`'s darwin arm) | `.unknown` |
| Windows | `GetLogicalProcessorInformationEx(RelationProcessorCore)` — note `peb().NumberOfProcessors` (`Thread.zig:504-506`) is logical **and not affinity-aware** | `.unknown` |
| other | — | `.unknown` |

**The affinity intersection is the load-bearing part**, and §0 correction 2 is
why. On the target host the sibling map is `(0,6)(1,7)(2,8)(3,9)(4,10)(5,11)`.
Unrestricted: 6 distinct groups → `physical = 6`, `logical = 12`. Under
`taskset -c 0-3`: the mask is `{0,1,2,3}`, each sibling set intersects it in
exactly one CPU, so 4 distinct groups → `physical = 4`, `logical = 4`, SMT ratio
1.0 — correctly reporting that the pin bought four *whole* cores. A probe that
skipped the intersection would report `physical = 6` on a machine allowed 4
CPUs, and over-derive K by 50% in precisely the environment an operator reached
for because they were being careful.

**When `physical` is null, the derivation uses `logical` and prints UNKNOWN.**
It does **not** assume an SMT ratio of 2. Doctrine 2: an absent instrument
reports UNKNOWN, never a number it did not measure — and falling back to
`logical` is also the no-regression choice, since `logical` is what the compiler
uses today.

### 3.4 The derivation, in three lines

```
M_wide  = n_jobs orelse topology.logical                       — all threads; NOT capped by IdBacking
K       = intern_partitions orelse (1 << ceil_log2(max(topology.physical orelse topology.logical, 2)))
M_alloc = K - 2                                                — main + linker are permanent tid holders
```

Rationale for each part, each traceable:

- **M_wide is no longer capped at `maxInt(Zcu.PerThread.IdBacking)` = 127.**
  Today `main.zig:3483-3486` clamps the *worker* count by the *tid* backing
  type. That clamp belongs to K, not M_wide — it exists because
  `IdBacking = u7` (`Zcu/PerThread.zig:45`) and because `ip.init` asserts
  `available_threads <= maxInt(u8)` (`InternPool.zig:6293`). Moving it to K is
  one of the cleanest wins of the decoupling: a 192-thread host gets 192 workers
  on the non-allocating phases where today it gets 127.
- **K derives from PHYSICAL cores, not logical.** This is the amendment's
  central instruction and it is also, independently, what §1 argues for: the
  allocating class is cache-heavy (Sema chasing `InternPool` items through
  pointer-dense structures, codegen over AIR/MIR). SMT siblings share L1, L2 and
  execution ports; their gain on this class is **measured-not-assumed and may be
  negative**, so the derivation refuses to spend index-space headroom on it.
  The wide class — parse, ZIR, file I/O, clang sub-processes, hashing — is where
  SMT genuinely pays, and that class gets all logical threads.
- **K is rounded UP to the power of two its own `tid_width` already implies.**
  `tid_width = ceil(log2(K))` and `shards = 1 << tid_width`
  (`InternPool.zig:6331, 6335`), while `locals` is sized K (`:6296`). So any K
  below `2^tid_width` leaves `2^w − K` shard slots allocated and unusable while
  paying the *full* ceiling penalty of `2^w`. K = 6 and K = 8 have **identical**
  per-partition ceilings; K = 8 simply has two more usable lanes. Rounding up to
  `2^w` is therefore free capacity — the rare case where the honest choice costs
  nothing. (An earlier draft of this dossier proposed rounding *down*; that is
  wrong, and it is recorded here rather than quietly deleted, per
  `CONTRIBUTING-AI.md`: rounding down trades two real worker lanes for a
  doubling of a ceiling the operator can already reach directly with
  `--intern-partitions=<N>`.)
- **K's floor is 2**, never 1 — patch/002 Finding 3 binds; all three edges
  (evented-mode tid starvation, the saturating `tid_shift_32 = tid_shift_31 +| 1`
  at `InternPool.zig:6334`, and the remedy text) fire at `tid_width = 0`.
- **K's ceiling is 128** (`1 << 7`), from `IdBacking = u7` and the `ip.init`
  assert. On hosts with more than 126 physical cores the derivation saturates
  and the print line says so by name.
- **`M_alloc = K − 2` is oversubscribed on purpose, and that is a claim to
  measure.** On the target host it means 6 gated workers plus main (Sema) plus
  the linker = 8 allocating-capable tasks over 6 physical cores, ≈1.33×. The
  justification is that two of the eight are usually blocked, not running: main
  blocks in `CodegenTaskPool.start` on `free_cond.wait` waiting for the linker
  to drain (`Zcu.zig:5311`), and the linker blocks in `q.zcu_queue.get`
  (`link/Queue.zig:189`). If V13 in §8 shows the oversubscription hurts,
  `M_alloc` becomes `K − 2` clamped to `physical`, which is a one-line change —
  the flag shape already allows it.

### 3.5 The worked example — this host, predicted before it is run

Owner-supplied and carried as a queued verification item (V7a), **predicted, not
asserted**:

Item counts below are stated in **both** index widths, because the `CaptureValue`
widening landed after this table was written and doubled every one of them (§3.6).

| Configuration | `physical`/`logical` seen | K | `tid_width` | items/partition (31-bit) | *(30-bit, as measured at the incident)* | allocating lanes | wide lanes |
|---|---|---|---|---|---|---|---|
| **stock 0.16.0, unpinned** | — (12 logical) | 12 | 4 | 134,217,727 | **67,108,863** ← the measured cliff, missed by ONE item | 10 | 11 |
| **current mitigation, `taskset -c 0-3`** | 4 / 4 | 4 | 2 | 536,870,911 | 268,435,455 | 2 | 3 |
| **this design, derived** | **6 / 12** | **8** | **3** | **268,435,455** | 134,217,727 | **6** | **11** |

The derived row is strictly better than *both* existing rows on the axes that
matter: **2× the capacity headroom of stock and 3× the allocating parallelism of
the pin, while employing all six physical cores and leaving all twelve logical
threads available to the wide class.** That is the amendment's claim, and V7a is
the run that decides whether it survives contact with a real compile.

**And the honest limit of it — now measurably softer than when this was written.**
The topology probe helps decisively in the 4–14 physical-core band. Beyond it, the
probe merely postpones the wall: a 16-physical-core machine derives K = 16 →
`tid_width = 4` → **134,217,727** (was 67,108,863, i.e. exactly the incident's cliff);
a 32-physical machine derives **67,108,863** — which is now the cliff the incident hit,
one host-size later. So the widening bought **one doubling, and therefore roughly one
octave of host width**, not a general fix.

The original sentence here read *"Beyond roughly 14 physical cores, only widening
`CaptureValue` (§6) adds headroom."* That widening has now landed and the band moved
out by a factor of two; the next constraint is `Air.Inst.Ref`'s ownership of bit 31
(§3.6), and after that there is no bit left in a `u32` — the following lever is a wider
`Index` type, which is the 427-site rewrite patch/002 refused. **Stating this now still
prevents the design from being sold as a general fix**, and now also prevents the
widening from being sold as one.

### 3.6 The ceiling table, so the print line is checkable

**Every number in this table doubled when the `CaptureValue` widening landed.** Both
tables are kept, because the pre-widening column is what patch/001's production
refusal was measured against and a reader comparing an old log to a new one needs to
see why the same K now prints a different ceiling.

| K (rounded) | `tid_width` | items/partition **(current, 31-bit Index)** | items/partition *(pre-widening, 30-bit)* |
|---|---|---|---|
| 2 | 1 | **1,073,741,823** | 536,870,911 |
| 4 | 2 | **536,870,911** | 268,435,455 |
| 8 | 3 | **268,435,455** | 134,217,727 |
| 16 | 4 | **134,217,727** | 67,108,863 ← the cliff a 12-core host landed on |
| 32 | 5 | **67,108,863** | 33,554,431 |
| 64 | 6 | **33,554,431** | 16,777,215 |

Derived from `getIndexMask` (`InternPool.zig:1598`), which the widening moved from
`getIndexMask(u30)` to `getIndexMask(u31)` for `Index`: **`(2^31 − 1) >> tid_width`**.
`src/ThreadPlan.zig`'s `index_bits` constant carries the same 31 and must be kept in
step with it — if the two disagree, the print line lies about the ceiling, and the
ceiling is exactly the number an operator reads after meeting patch/001's refusal.

**Only ONE doubling, not two.** §5 predicted the widening would move the ceilings "twice
over". It moved them once: `CaptureValue` was the first of two confiners, and
`Air.Inst.Ref` (`Air.zig:1170-1176`) owns bit 31 as its interned-vs-instruction tag, so
the 32nd bit is an AIR re-representation change and is refused by name rather than taken
quietly. §5's estimate was made before that second owner was known; it is corrected here
rather than in place, so the reasoning that produced the wrong number stays legible.

**What this does to the production incident.** The 16-way split that overflowed at
67,108,864 items now has 134,217,727 available at the same `tid_width = 4` — the
incident's own workload has **2× headroom on the exact configuration that failed**, and
the `taskset` interim lever is no longer the only thing standing between this station
and the refusal. That is the widening's payoff, stated in the units of the incident that
motivated it rather than in bits.

### 3.7 The print line — no silent default, ever, and topology on its face

One line to stderr at `Compilation.create`, after `ip.init` returns, gated on
nothing (doctrine 4 — the tool states its resolved reality). On the target host,
derived:

```
zig: topology 6 physical / 12 logical (probe: sys_topology, affinity-masked)
     workers 12 (derived: logical) · intern partitions 8 (derived: 6 physical -> 2^3)
     · alloc lanes 6 (= K-2: main + linker reserved) · 134,217,727 items per partition
     · override: -j<N> --intern-partitions=<N>
```

Under the current pin (`taskset -c 0-3`) the same line reads
`topology 4 physical / 4 logical`, `intern partitions 4`, `268,435,455 items per
partition` — the operator's proof that the pin was seen for what it is. Where
topology cannot be probed:

```
zig: topology UNKNOWN physical / 12 logical (probe: unknown - falling back to logical)
```

Every number names **what** and **from what**. When a value is overridden the
word `derived` becomes `given`. The line is the operator's whole diagnosis when
patch/001's named panic fires: the panic reports the partition that overflowed;
this line reports what chose the partition count, and from which probe.

### 3.8 Flags — the existing intent becomes explicit

| Flag | Meaning | Status |
|---|---|---|
| `-j<N>` | worker count **M_wide** | existing (`main.zig:1171-1180`); meaning narrows from "both" to "workers", which is what its help text at `:455` already says: *"Limit concurrent jobs"* |
| `--intern-partitions=<N>` | partition count **K**; also fixes `M_alloc = N − 2` | new; the knob that never existed |
| `--intern-partitions=logical` | opt back in to today's coupling (K derived from logical CPUs) | new; keeps the pre-amendment behaviour reachable by name |
| `-j1` | full serial member: M_wide = 1, **K unchanged by `-j`** (K = 8 on this host), async limit `.nothing` → every `group.async` runs inline (`Threaded.zig:2100-2105`) | preserved verbatim |

`--intern-partitions=logical` earns its place for the same reason
`--step-order=random` does: it keeps the old behaviour reachable by name, so a
regression can be bisected against it without building a second compiler.

#### Correction — this table said `-j1` gives K = 2. The code says otherwise, and the code is right.

The row above originally read *"`-j1` | full serial member: M_wide = 1, **K = 2
(floor)**"*. **V2 measured it false.**

```
$SAFE build-exe -j1 -Mroot=hello.zig
  expected by this table:  workers 1; intern partitions 2;   536,870,911 items
  MEASURED:                workers 1 (given); intern partitions 8
                           (derived: physical, rounded up to a power of two);
                           134,217,727 items per partition
```

`ThreadPlan.derive` (`src/ThreadPlan.zig:227`) computes the two numbers from two
independent inputs and they never meet: `workers` comes from `n_jobs` at `:237`,
`partitions` from `partitions_arg orelse topology` at `:241-255`. **`n_jobs`
never touches `partitions`.** The `@max(…, 2)` floor exists — in `finish` at
`:270-272`, mirroring `InternPool.zig:6295` — but it is a floor, and 8 is above
it, so it never engages. K = 2 would require `--intern-partitions=2`, typed
explicitly.

**This is the decoupling working exactly as §2 designed it**, so the defect was
in the prose, not the design: the table was written before the split and carried
forward the pre-split world in which one integer meant both things. That is the
whole error, and it is worth naming because the same sentence appeared in the
verification list, which means a row was queued against a claim no code made.

**Effect on behaviour: none, and better than the table promised.** K = 8 gives
134,217,727 items per partition where K = 2 would give 536,870,911 — less
headroom, but four times what the production incident needed, and `tid_width = 3`
so none of patch/002 Finding 3's three `-j1` edges (all of which fire at
`tid_width == 0`) come near. **R8 does not fire.** V2's behavioural half is
GREEN: `-j1` exits 0, does not hang, and the binary runs.

**Residual, stated rather than resolved:** whether `-j1` *should* narrow K is a
real question this correction does not answer. It would buy 4x headroom on a
genuinely serial build, and it would cost a second coupling between two numbers
this patch just spent its whole design decoupling. Unmeasured either way; not
changed here; named so the next lane can decide it deliberately instead of
inheriting it from a stale table.

The patch/002 ruling itself is untouched and still honoured: `@max(available_threads, 2)`
at `InternPool.zig:6295` stays exactly as upstream wrote it, and `ThreadPlan.finish`
mirrors rather than assumes it — which is precisely why the measured line could be
compared against the table at all.

---

## 4. Edges-first scheduling (ORDER 2)

### 4.1 How work is ordered today — measured at both levels

**(a) The build system's step DAG — `lib/compiler/build_runner.zig`.**

The DAG is walked depth-first from the requested targets, and **independent steps
are deliberately randomised**:

- `constructGraphAndCheckForDependencyLoop` (`:1261`) duplicates each step's
  `dependencies` and calls `rand.shuffle(*Step, deps)` at `:1283`.
- Its doc comment (`:1254-1259`) states the intent: *"Each step has its
  dependencies traversed in random order, this accomplishes two things: …
  `step_stack` will be in randomized-depth-first order, so the build runner
  spawns initial steps in a random order [and] each step's `dependants` list is
  also filled in a random order, so that when it finishes executing in
  `makeStep`, it spawns next steps to run in random order."*
- The seed is `graph.random_seed` (`lib/std/Build.zig:128`), settable by
  `--seed` (`build_runner.zig:270-274`, documented at `:1678` as *"For shuffling
  dependency traversal order (default: random)"*).
- Ready steps are launched by `stepReady` (`:1420`) → `group.async(io, makeStep, …)`
  (`:1439`), with an RSS admission gate (`:1429-1437`) that parks steps into
  `memory_blocked_steps` when `available_rss` is short, releasing them in
  `makeStep` (`:1391-1409`).
- Parallel width is `-j<N>` → `threaded.setAsyncLimit(.limited(n))` (`:426`).

So at level (a) the *topological* constraint is already enforced (a step cannot
start until `pending_deps` hits zero, `:1413-1417`) and the *only* remaining
freedom — the order among independent ready steps — is currently spent on
randomisation. That randomisation is not noise: it is a deliberate fuzzer for
missing dependency edges. **It must stay a member.**

**(b) Within one compilation.**

Three orderings, in pipeline order:

1. **AstGen fan-out order** — `for (zcu.import_table.keys())` at
   `Zcu/PerThread.zig:179`, i.e. discovery order of an
   `ArrayHashMapUnmanaged` (`Zcu.zig:128`). All items are spawned into one group
   before any await, so order only decides who starts first, and beyond
   `async_limit` it decides *who runs inline on the spawner*.
2. **Alive-file / module-stamping order** — `computeAliveFiles`
   (`Zcu/PerThread.zig:2591`) is a BFS from `zcu.analysisRoots()`
   (`Zcu.zig:4380`, a `[5]*Package.Module` buffer at `:296`) through ZIR import
   edges. **Top-down from the roots.**
3. **The analysis order** — `findOutdatedToAnalyze` (`Zcu.zig:3284`). Its policy
   is explicit in its own comment (`:3285-3289`): *"We prioritize functions,
   because the sooner they get analyzed, the sooner they can be sent to the
   codegen backend and linker, which are usually running in parallel (so this
   can increase parallelism)."* Implementation: `outdated_ready.funcs.keys()[0]`
   (`:3292`), else `outdated_ready.other.keys()[0]` (`:3298`), else
   `outdated.keys()[0]` (`:3327`) as the dependency-loop fallback. `[0]` of an
   `AutoArrayHashMapUnmanaged` is **insertion order** — units enter at
   `Zcu.zig:3141-3142, 3167-3168, 3199-3200, 3592-3594, 3608-3612`.

### 4.2 The constraint that shapes the whole ORDER 2 design

**A fresh full build in Zig is demand-driven, and that is a language property,
not a scheduling choice.** Analysis begins by populating only the analysis
roots' own files (`Zcu/PerThread.zig:315-321`), and the comment there states the
seeding rule exactly: *"Declarations in these files which want eager analysis —
those being `comptime` declarations, any declarations marked `export`, and
`test` declarations in the main module if this is a test compilation — become
referenced, and so will be picked up by the main semantic analysis loop below."*
Everything else is analysed only when something references it.

Therefore **"analyse the leaf modules first" is not implementable as written.**
Eagerly analysing a leaf module's declarations would analyse code the program
never references — changing which errors a program produces, which is exactly the
"no language divergence" line in `PROVENANCE.md`'s commitments. Reporting this
rather than quietly implementing a semantics change is the honest move, and it is
the single most important finding in §4.

**What IS lawful, and delivers what ORDER 2 asks for:**

> Edges-first is a **priority order over the ready set**, never a change to the
> set. The same units get analysed; the ones nearest the leaves and most
> depended-upon get analysed *sooner*.

That is exactly what the owner asked for functionally — "start with edges … so
it unblocks the most downstream work earliest" — and it is free of semantic
consequence, because `findOutdatedToAnalyze` already documents itself as a
*priority* function whose choice is a performance decision (`Zcu.zig:3285-3289`).

### 4.3 The design — layer-aware edges-first, three levels

**Level 0 — the module ranking (computed once, cheap, at a site that exists).**

At `Compilation.zig:2334`, immediately after `pt.populateModuleRootTable()`
returns, `zcu.module_roots` holds every module and no analysis has run. This is
the fork's "Site A" and the fork already runs a walk there
(`Compilation.zig:2346`, `EmitModuleGraph.buildJson`). Add one more O(V+E) pass
producing, per module:

- `depth` — longest path to a leaf in the `Module.deps` DAG
  (`Package/Module.zig:15, 38`). Leaves = 0. **Ascending depth is the
  composition order the owner named.** Computed by memoised DFS; `deps` is
  acyclic by construction (`build_runner.zig:1261` proves loops are refused at
  the step level, and module cycles are legal in Zig imports — see the residual
  below).
- `fan_in` — in-degree, obtained by inverting `deps`. **No fan-in table exists
  anywhere in the compiler today**; `Module.deps` is out-edges only
  (`Package/Module.zig:15`) and nothing inverts it. This is genuinely new state,
  and it is 8 bytes per module.
- Both must include the edges `deps` deliberately omits: `std`, `root` and
  `builtin` are excluded from every `deps` table by design
  (`Package/Module.zig:9-14`) — the trap `INTERNALS_MAP.md` §3.2 names. The
  ranking iterates `module_roots.keys()` (complete, `Zcu.zig:111-113`) and
  cross-references `deps` for edges, exactly as `EmitModuleGraph` already does.

*Residual, named:* module import graphs **can** contain cycles in Zig (two
modules may import each other), while `Package.Module.deps` as declared on the
command line usually does not. The depth computation must therefore be
cycle-tolerant: on revisiting a node in progress, treat the back-edge as depth 0
and record the module in a `cyclic` set that the print line reports. A ranking
pass that hangs or asserts on a legal graph is a worse bug than a bad order.

**Level 1 — the build-system member (ORDER 2, level (a)).**

Replace the shuffle at `build_runner.zig:1283` with a comparator selected by a
new flag, and make the ready-set launch order match it:

```
--step-order=layered   (new default for a full build)  sort by (depth ASC, fan_in DESC, name ASC)
--step-order=random    (today's behaviour)             rand.shuffle, seeded by --seed
--step-order=declared  (deterministic, no ranking)     dependencies.items order as written
```

`fan_in` at the step level is `dependants.items.len` — already computed, at
`build_runner.zig:1287` (`dep.dependants.append(b.allocator, s)`), so the
tie-break costs one field read. The comparator applies in two places: the
`initial_set` loop (`:766-770`) and the `dependants` loop that spawns newly-ready
steps (`:1413-1417`).

**Why fan-in descending is the right tie-break, stated as a claim to be
measured, not as a fact:** among steps at the same depth, finishing the one with
the most dependants converts the most `pending_deps` counters to zero
(`:1414-1416`), which makes the most new steps eligible, which keeps the widest
part of the M-wide pool fed. The counter-claim is real too — a high-fan-in step
may also be the longest, and starting it first can leave the pool idle at the
tail. §8 (V7) is the run that decides between them; the flag exists so the
decision is data, not taste.

**Level 2 — the in-compilation member (ORDER 2, level (b)), and "internal before
facade".**

`findOutdatedToAnalyze` (`Zcu.zig:3284`) keeps its two-tier shape — functions
first, then others, because that tier exists to feed codegen and the linker
(`:3285-3289`) and ORDER 1 wants that lane fed harder, not less. What changes is
`[0]`:

```
funcs  ready:  argmin over outdated_ready.funcs by (module_depth ASC, module_fan_in DESC, insertion ASC)
others ready:  argmin over outdated_ready.other by (module_depth ASC, module_fan_in DESC,
                                                    facade_rank ASC, insertion ASC)
```

- `module_depth` / `module_fan_in` come from the level-0 ranking. The
  `AnalUnit → module` chase is the 5-hop walk `INTERNALS_MAP.md` §4.3 prices
  (`TrackedInst.Index` → `resolveFile` at `InternPool.zig:179-184` → `FileIndex`
  → `File` at `:1723-1727` → `.mod` at `Zcu.zig:985`). It must be **memoised per
  file**, not walked per selection, or the selection becomes the bottleneck it
  was meant to relieve — a small `File.Index → rank` side table, filled lazily.
- **`facade_rank` is "internal before facade"**, made mechanical: a module's
  *root* source file (`module_roots`' value, `Zcu.zig:113`) is its public facade;
  every other alive file of that module is internal. Rank internal = 0, root = 1.
  This is the cheapest faithful reading of the owner's clarification that does
  not require inventing a visibility model Zig does not have; it is stated as an
  approximation in the code comment, with the exact claim it does and does not
  support.
- The selection is `argmin` over an array-hash-map's keys — O(n) per pick where
  today it is O(1). **That is the cost centre of ORDER 2 and it must not be
  hand-waved.** Mitigation designed in: keep `outdated_ready` as-is and add a
  small ranked bucket index (`depth` bucket → list), so the pick is
  O(first non-empty bucket). §8 (V8) measures the selection overhead against the
  current `[0]` before this is considered landed.
- **Fallback untouched:** the dependency-loop arm at `Zcu.zig:3327` keeps
  `outdated.keys()[0]`. That arm exists to break a cycle, and imposing an order
  on a cycle is meaningless.

**Level 3 — the AstGen spawn order (a freebie, and the one place leaf-first is
literally true).**

`Zcu/PerThread.zig:179-199` spawns AstGen per file with no ordering. AstGen has
**no cross-file dependencies** — it is pure per file — so reordering is
semantically free. Sorting the spawn list by (module depth ASC, fan-in DESC)
means the files most likely to be needed first by `computeAliveFiles` and Sema
finish first. Small, safe, and it is the only level at which "smallest parts
first" is unqualifiedly true.

### 4.4 The interaction with K — the question the brief asked, answered

**The concern:** leaf-first front-loads the widest phase, and the widest phase
(A1 AstGen) is InternPool-allocating. Does edges-first make the K-cliff worse?

**Answer: no at level (b), mildly yes at level 3, and level 1 helps.** In detail:

1. **Level 2 cannot change total allocation.** It reorders a ready set; the same
   `AnalUnit`s are analysed, on the same single thread (A5, tid `.main`). Peak
   partition-0 occupancy is the sum over the same units. Order changes *when*
   items are interned, never *how many*. **ORDER 2 at level (b) is K-neutral by
   construction** — which is a direct consequence of the §4.2 finding, and one of
   the reasons that finding is load-bearing rather than merely honest.
2. **Level 3 is now almost entirely on the wide lane**, which is where the
   topology amendment lands hardest. Per §1.3, AstGen's body is tid-free and
   runs at `M_wide` (12 logical threads on the target host); only the
   per-newly-discovered-file interning tail (`Zcu/PerThread.zig:2408`) takes a
   permit from the `M_alloc` gate, and that tail spreads across partitions
   rather than concentrating in partition 0 — the *good* direction for K.
   Ordering the spawn list makes the early window denser on a lane that is
   12-wide instead of 6-wide, and denser on the tail only in proportion to newly
   discovered files. **Net: positive for wall time, neutral-to-positive for K,
   and the phase where SMT siblings are most likely to actually pay** (parse and
   ZIR lowering are branchy and I/O-interleaved, not cache-resident streaming) —
   which is exactly the class the amendment assigns to all logical threads.
3. **Level 1 reduces peak K pressure across a full build.** Independent steps are
   separate processes with separate pools. Finishing high-fan-in library steps
   early means the steps that follow have *fewer* modules left to resolve — and
   in the fork's destination (stage 2c, the module-artifact cache) it means the
   most-reused artifacts are cached before the compiles that would reuse them.
   **ORDER 2 at level (a) and the crown's stage 2c point in the same direction**;
   that alignment is not a coincidence and should be recorded as a reason to do
   level 1 first.
4. **The one genuine adverse interaction, named:** ORDER 1 raises `M_wide`,
   which for `zig build` raises the number of *concurrent compiler processes*,
   each with its own full closure resident. `PLAN.md` calls peak residency "a
   hard residency wall"; the build runner's only defence is the `max_rss` gate
   (`build_runner.zig:1429-1437`), and `max_rss` defaults to *total system
   memory* (`:530-533`), which is not a defence at all for compiles that peak in
   the tens of GiB. **Raising `M_wide` without a residency story converts a CPU
   win into an OOM**, and the topology amendment makes this sharper rather than
   softer: `M_wide` = logical, so a 6c/12t host now doubles the step-level
   concurrency the pre-amendment design would have chosen from physical cores.
   §7 carries this as risk R2, and §3.7's print line reports `M_wide` so the
   operator can see it coming.

### 4.5 Both members preserved — the selectable table

Nothing in this design removes a behaviour. Every current behaviour keeps a name:

| Axis | Current behaviour, kept as a member | New derived default | Selector |
|---|---|---|---|
| worker count | one number for both roles | `M_wide` from **logical** CPUs, `K` from **physical** cores, `M_alloc = K − 2` | `-j<N>`, `--intern-partitions=<N>` |
| topology input | logical CPUs only (`getCpuCount`) | physical + logical + sibling map, affinity-masked; UNKNOWN falls back to logical | `--intern-partitions=logical` restores the old input |
| serial compile | `-j1` — inline execution, K = 2 floor | unchanged | `-j1` |
| partition count | `ceil(log2(M))` from logical | `1 << ceil(log2(physical))` | `--intern-partitions=<N>` |
| step order | randomised DFS, `--seed` | layered (depth ASC, fan-in DESC) | `--step-order=random\|layered\|declared` |
| analysis order | funcs-first, insertion order | funcs-first, layer-ranked | `--analysis-order=insertion\|layered` |
| AstGen spawn order | `import_table` discovery order | layer-ranked | folded into `--analysis-order` |

The randomised step order in particular is **not** deprecated: it is a working
fuzzer for missing dependency edges, and a project that only ever runs
`--step-order=layered` will stop finding those. The recommendation that ships
with this design is that CI keeps a `--step-order=random` lane.

---

## 5. Where CaptureValue widening would simplify this design

Deferred by the owner ("will do later"), priced by patch/002 at 48 sites +
6 trailing-data blocks + 3 length counters, plus the newly-found `Nav.Index`
truncation coupling. Designing around it, but naming the debt precisely:

1. **§3's K derivation collapses to `K = M_wide`.** With `Index` at a full
   `u32`, `tid_width = 4` costs 268,435,455 items per partition instead of
   67,108,863 — more than the largest observed real build needs. K could then
   simply equal `M_wide`, the admission gate in §2.3 could be deleted, and
   `--intern-partitions` would never need to exist. **The entire (K, M_wide)
   decoupling is a workaround for 2 bits.**
2. **The physical/logical split would stop being a *capacity* question and
   become purely a *performance* one.** Post-amendment, deriving K from physical
   cores does two jobs at once: it buys index headroom *and* it declines to
   spend cache-heavy parallelism on SMT siblings. Widening retires the first
   job. The second survives — but it becomes a tuning decision backed by
   measurement (V13), not a capacity constraint, and it could then be answered
   by simply raising `M_alloc` if siblings turn out to help.
3. **The power-of-two round-up (§3.4) stops mattering.** It exists to reclaim
   lanes that the ceiling penalty already charges for. With headroom, K = 12 on
   a 12-thread host is fine and the printed line gets shorter.
4. **The 4–14-physical-core band limit (§3.5) disappears.** A 32-physical-core
   host currently derives 33,554,431 items per partition — under half the
   observed production need. Widening is the *only* thing that makes this design
   work on wide hardware; the topology probe merely postpones the wall.
5. **`IdBacking = u7` (`Zcu/PerThread.zig:45`) could widen with it**, removing
   the 128-partition ceiling and with it the
   `assert(available_threads <= maxInt(u8))` at `InternPool.zig:6293` as a
   scaling limit.
6. **What widening would *not* fix:** none of §1's five serial phases become
   parallel, no SMT question is answered, and ORDER 2 is untouched. Widening
   buys headroom; it does not buy cores. **Both orders remain worth doing after
   widening lands** — which is the argument for not blocking this design on it.

---

## 6. Cost

Estimated by counting the sites read, not by feel. Every number is a count of
things located in this tree.

| Piece | Files touched | Rough LOC | Confidence |
|---|---|---|---|
| **Topology probe** (Linux `/sys` + `/proc/cpuinfo` fallback, macOS sysctl, Windows `GetLogicalProcessorInformationEx`, affinity intersection, UNKNOWN path) | new `src/Topology.zig` | ~230 | medium — three OS arms, and only the Linux one can be tested in this estate |
| (K, M_wide) split: two params, one struct field, three sub-compilation forwards | `src/main.zig`, `src/Compilation.zig`, `src/Zcu.zig` | ~60 | high — 8 call sites located exactly |
| `--intern-partitions` flag + help + derivation + the topology print line | `src/main.zig` | ~110 | high |
| Admission gate at the allocating spawn sites (A2, A6) | `src/Zcu/PerThread.zig`, `src/Zcu.zig` | ~50 | medium — depends on `Io.Semaphore` fitting `Io.Group`'s cancellation shape |
| A1 scope reduction: move `.acquire`/`release` from `:371-372` to wrap the import-discovery tail `:397-425` | `src/Zcu/PerThread.zig` | ~25 | medium — small diff, but it is the one hunk that can introduce a data race, and V12 gates it |
| Module ranking pass (depth + fan-in + cycle tolerance) at Site A | new `src/Compilation/ModuleRanking.zig` | ~180 | high — mirrors `EmitModuleGraph.zig` (177 lines) almost exactly |
| Per-file rank memo + `findOutdatedToAnalyze` bucket index | `src/Zcu.zig` | ~140 | **low** — the O(n)→O(1) mitigation is the risky part |
| AstGen spawn ordering | `src/Zcu/PerThread.zig` | ~30 | high |
| Build-runner `--step-order` + comparator | `lib/compiler/build_runner.zig`, `lib/std/Build.zig` | ~110 | high |
| Docs: this dossier's landing note, help text, `PLAN.md` row | `docs/crown/`, help blocks | ~60 | high |
| **Total** | **8 source files + 2 new** | **~1,005** | |

For scale: this is roughly 5–6× patch/003 and still well under the 427-site
global-`u64` rewrite patch/002 refused. It is **three** independent patches and
should land as three, in this order:

1. **patch/005a — topology probe + (K, M_wide) derivation.** The piece with a
   production incident behind it and a predicted, checkable outcome (§3.5).
   Lands with V0, V0a, V1–V3, V6, V7a, V7b, V11, V13, V14.
2. **patch/005b — the A1 lane split.** Small diff, largest wall-time payoff,
   but it is the only hunk that can introduce a data race. Gated on V12.
3. **patch/005c — edges-first ordering.** The piece whose payoff is entirely
   unmeasured. Gated on V8 and V10; does not land if either goes the wrong way.

Splitting 005b out of 005a is a change from this dossier's first draft, forced
by the amendment: before the topology work, A1's lane assignment was not
load-bearing; after it, A1 is the single biggest beneficiary *and* the single
biggest risk, and it deserves to be bisectable on its own.

---

## 7. Risks, each named with the invariant it threatens

| # | Risk | Invariant at stake | Mitigation designed in |
|---|---|---|---|
| **R1** | **Process-global K violated by a sub-compilation.** If any `Compilation` is created with a smaller K than the global tid pool can issue, `getLocal(tid)` (`InternPool.zig:1446-1448`) indexes `ip.locals` out of bounds — a wild pointer of exactly the class patch/001 exists to abolish. | `∀ pools P: P.locals.len ≥ max(available_tids) + 1` | `intern_partitions` forwarded at all three sub-compilation sites (`Compilation.zig:5066, 7508, 7646`); a `ip.init` assert that names the violation; V3 in §8 is the negative control. |
| **R2** | **Higher M → higher peak RSS → OOM.** `max_rss` defaults to total system memory (`build_runner.zig:530-533`), so the build runner will happily run M large compiles at once. | residency bound (`PLAN.md`, "hard residency wall") | print M in the startup line; recommend `--maxrss`; **do not** raise the build-runner default in this patch. Explicitly out of scope and stated as such. |
| **R3** | **`io.concurrent` starvation re-serialises the linker.** If `busy_count` reaches `concurrent_limit`, `link/Queue.zig:67` falls back to running link tasks on the main thread. | pipeline concurrency | the admission gate prevents parked workers from inflating `busy_count`; V4 in §8 asserts the linker got its concurrent slot. Upstream context: [#25748](https://github.com/ziglang/zig/issues/25748). |
| **R4** | **`Io.Group` fan-out hazard.** [#26027](https://github.com/ziglang/zig/issues/26027) reports `std.Io.Group` hanging with more tasks than threads; resolution status **UNKNOWN** to this lane. ORDER 2 level 3 and higher M both widen fan-out. | liveness | V5 in §8 is a deliberate 1024-task fan-out probe against the built compiler before either default flips. |
| **R5** | **Ranking-pass cycles.** A legal cyclic module import graph must not hang or assert the depth pass. | "never a silent anything" | cycle-tolerant DFS with a `cyclic` set reported in the print line; V9 in §8 is its negative control. |
| **R6** | **Selection cost eats the win.** `findOutdatedToAnalyze` goes O(1) → O(n) per pick and is called once per AnalUnit — potentially millions of times. | Sema throughput | bucket index; V8 measures before/after on the same workload and the feature does not ship if it is net-negative. |
| **R7** | **K becomes an incremental-cache key.** `Compilation.saveState` writes `thread_count = ip.locals.len` (`Compilation.zig:3725`) and sizes per-partition headers from it (`:3742`). Deriving K from module count means K can change between runs. | incremental state validity | Today this is inert: **there is no `loadState` in this tree** (grep: 0 hits in `src/`), so the field is write-only. Recorded here so the first `loadState` author validates it instead of rediscovering it. |
| **R8** | **The `-j1` edges stay sharp.** patch/002's three edges all fire at `tid_width = 0`. | the `@max(_, 2)` floor | this design never lowers the floor; V2 in §8 is the regression guard. |
| **R9** | **Topology probe over-derives under confinement.** A `/sys` read not intersected with `sched_getaffinity` reports the machine's physical cores, not the ones we may use; cgroup CPU quota (`/sys/fs/cgroup/cpu.max`) is invisible to affinity entirely, so a container limited to 2.5 CPUs still sees 6 physical. | K ≤ usable cores | intersection is mandatory (§3.3) and V14 is its negative control. **cgroup quota is NOT handled and is named as a residual, not silently approximated** — the print line reports the probe source so an operator in a container can see that quota was not consulted. |
| **R10** | **SMT gain is assumed, in one direction, for the wide lane.** The design asserts siblings pay on parse/ZIR/clang/hashing. That is a hypothesis. If it is false, `M_wide = logical` costs cache thrash for nothing. | wall time | V13 is the A/B (`-j6` vs `-j12` at fixed K) that measures it. The claim is written down before the run and the band is not adjusted afterward. |
| **R11** | **Windows and the BSDs get UNKNOWN, and UNKNOWN is a behaviour change on those hosts only if we let it be.** `peb().NumberOfProcessors` (`Thread.zig:504-506`) is not affinity-aware, so Windows already over-derives today. | no-regression on unprobeable hosts | UNKNOWN falls back to `logical`, i.e. **exactly today's derivation**. No host gets worse; some get better. Verified by V11's byte-identity check, which cannot run on those hosts in this lane and is therefore UNKNOWN there. |
| **R12** | **A1's lane split could introduce a data race.** Moving `.acquire` down means `pt.updateFile` runs without a tid; if anything it reaches mutates `InternPool`, that is unsynchronised mutation of a lock-free structure — the worst failure class in this repository. | lock-free per-thread allocation | §1.3 read the body and found no `tid` path, but the read cannot see indirect reachability. **V12 is a hard gate: 005b does not land until a ReleaseSafe + TSan run is clean.** Until then the split is read-verified only. |

---

## 8. Queued verification — the exact runs, written as commands, **not run**

Fired in this order, after the machine's execution window frees. Every entry
names its expected observation; anything that did not run reports **UNKNOWN**,
never green. `$SAFE` is the ReleaseSafe stage3 built per the fork's recipe
(`-Ddebug-extensions`, system LLVM).

**V0 — build the design's compiler (prerequisite).**
```
cmake -B build-safe -DCMAKE_BUILD_TYPE=ReleaseSafe -DZIG_STATIC_LLVM=OFF ... && ninja -C build-safe
```
*Expect:* stage3 present, `$SAFE version` → `0.16.0`. ~8–9 min, ~7.6 GiB peak on a
12-core host. **Machine courtesy: check `pgrep -fa 'zig build-exe|ninja'` first.**

**V0a — the topology probe agrees with the host's own instruments (PRE, no
compiler needed for the oracle side).**
```
lscpu -e=CPU,CORE,SOCKET
cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -u
```
*Expect (already measured by the owner):* 12 logical, 6 cores, sibling pairs
`(0,6)(1,7)(2,8)(3,9)(4,10)(5,11)`. This is the oracle V1 is checked against —
recorded first so the probe cannot be tuned to agree with itself.

**V1 — the print line exists, is truthful, and reports topology (doctrine 4).**
```
$SAFE build-obj -Mroot=test/fixtures/file_in_multiple_modules/main.zig 2>&1 | head -4
$SAFE build-obj -j4 --intern-partitions=2 -Mroot=... 2>&1 | head -4
taskset -c 0-3 $SAFE build-obj -Mroot=... 2>&1 | head -4
```
*Expect:* run 1 reports `6 physical / 12 logical`, `probe: sys_topology`,
`workers 12`, `intern partitions 8`, `alloc lanes 6`, `134,217,727` — matching
V0a's oracle and §3.6's table to the digit. Run 2 says `given` for both,
K = 2, ceiling 536,870,911. **Run 3 is the affinity check: it must report
`4 physical / 4 logical`, not `6 physical / 4 logical`.** A `6` there is R9
firing and blocks 005a.

**V2 — the `-j1` member still works (patch/002 regression guard).**
```
$SAFE build-exe -j1 -Mroot=<small hello world>; echo "exit=$?"
```
*Expect:* exit 0, no hang, print line reports M = 1 / K = 2 / `tid_width` 1.
A hang here is patch/002 Finding 3, edge 1 (evented tid starvation) resurfacing.

**V3 — negative control for R1 (the sub-compilation K mismatch).**
On a scratch copy only: sabotage one sub-compilation site
(`Compilation.zig:5066` region) to pass `.intern_partitions = 2` while the
parent derives 8, rebuild, compile anything needing compiler_rt.
*Expect:* the new named assert fires with both numbers in the message. Then
revert and verify by checksum. **A guard never seen red is not a guard.**

**V4 — the linker kept its concurrent slot (R3).**
```
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<mid-size project>
```
*Expect:* the time report shows link work overlapping analysis. A run where
`real_ns_decls` ≈ `real_ns` and link shows no overlap means
`error.ConcurrencyUnavailable` was hit and `Queue.zig:71-74` took the serial path.

**V5 — the `Io.Group` fan-out probe (R4), before any default flips.**
```
$SAFE build-obj -j64 --intern-partitions=8 -Mroot=<project with >1024 files>
```
*Expect:* completes. A hang reproduces [#26027](https://github.com/ziglang/zig/issues/26027)
in the compiler and **blocks any `M_wide` > 32 default** until upstream's status is known.

**V6 — §1's census gets its measurement: is partition 0 really the whole story?**
```
$SAFE build-exe -j12 --intern-partitions=2 --time-report -Mroot=<~1,800-module product>
```
with the compiler additionally printing final `local.mutate.items.len` per
partition at exit (the numbers `saveState` already computes at
`Compilation.zig:3745-3752`).
*Expect, predicted before the run:* partition 0 holds ≥ 90% of all interned
items, the rest near-empty — the direct consequence of §1.1's finding that five
of eight allocating phases are serial and four run on `.main`. This is also the
number that tells us how much of §3's headroom the design actually needs. **If
partitions are *not* lopsided, §1's census is wrong and this dossier is
corrected in public**, not quietly amended.

**V7a — THE worked example: the amendment's configuration, on the product that
hit the cliff.** This is the run the charter amendment names.
```
/usr/bin/time -v $SAFE build-exe -Mroot=<the ~1,800-module product>   # fully derived: M_wide=12, K=8
```
*Expect, predicted before the run:* the print line reports
`6 physical / 12 logical · workers 12 · intern partitions 8 · alloc lanes 6 ·
134,217,727 items per partition`; the compile exits 0 with **no patch/001
panic** (the incident needed 67,108,864 items on one partition; 134,217,727 is
2.00× that, so the margin under test is 2×, not "some"); all six physical cores
are busy during Sema+codegen and all twelve logical during AstGen. **The band,
fixed now:** wall time at or below the recorded `taskset -c 0-3` PRE, and peak
RSS within 15% of it. Not adjusted afterward.

**V7b — the two existing rows, re-measured on the same compiler, for the §3.5
table's other two lines.**
```
/usr/bin/time -v $SAFE build-exe --intern-partitions=logical -Mroot=<same>   # stock-equivalent: K=16
/usr/bin/time -v taskset -c 0-3 $SAFE build-exe -Mroot=<same>                # pin-equivalent: K=4
```
*Expect:* the first **panics by name** with patch/001's message at
67,108,863 — reproducing the production incident on demand, which is the whole
point of keeping `--intern-partitions=logical` as a member. The second completes
and reproduces the current mitigation's wall/RSS. Together with V7a these are
the three rows of §3.5, measured rather than predicted.

**V8 — ORDER 2's selection overhead (R6), measured before it ships.**
```
$SAFE build-exe --analysis-order=insertion --time-report -Mroot=<same product>
$SAFE build-exe --analysis-order=layered   --time-report -Mroot=<same product>
```
*Expect:* `cpu_ns_sema` differs by less than the run-to-run variance of three
repeats. If `layered` is slower, the bucket index is insufficient and 005b does
not land.

**V9 — negative control for R5 (ranking-pass cycles).**
Build a two-module fixture where each `-M` module imports the other, run the
ranking pass.
*Expect:* completes, and the print line names the cyclic modules. A hang or an
assert is a hard stop.

**V10 — edges-first at the step level does what it claims.**
```
$SAFE build --step-order=random  --summary all -j12   # ×3, different --seed
$SAFE build --step-order=layered --summary all -j12   # ×3
```
*Expect:* `layered` has lower variance across repeats (it is deterministic) and
its wall time is at or below the random median. **If layered is slower, the
fan-in-descending tie-break is wrong and §4.3's stated counter-claim wins** —
which is why the flag exists.

**V11 — stock invocations are byte-identical (the fork's standing law).**
```
$SAFE build-exe <stock args, no new flags>  vs  <stock 0.16.0> build-exe <same>
```
*Expect:* identical output artifact digests. **Note the honest caveat this
patch introduces:** the *artifact* must be identical, but the derived
`(M_wide, K)` deliberately differ from stock, so wall time and the stderr print
line will not match. Constraint 2 in `PLAN.md` is about behaviour of the
produced program, and this run states which half it is checking.

**V12 — HARD GATE for 005b: the A1 lane split is race-free (R12).**
```
# 1. ReleaseSafe, the full closure, repeated 5x — nondeterministic corruption shows as flakiness
for i in $(seq 5); do $SAFE build-exe -Mroot=<~1,800-module product>; echo "run $i exit=$?"; done
# 2. ThreadSanitizer build of the compiler over a mid-size closure
<tsan stage3> build-exe -Mroot=<mid-size project>
```
*Expect:* 5/5 exit 0 with identical artifact digests, and zero TSan reports
naming `InternPool` or `Zcu.File`. **Any race report, or any digest mismatch
across the five, stops 005b — the split reverts to taking the tid for the whole
worker (today's shape) and the wide-lane win is forfeited rather than risked.**
Negative control for the instrument itself: on a scratch copy, delete the
`.acquire` from the *tail* too and confirm TSan goes red — a sanitizer that
never reported anything has not been met.

**V13 — does SMT actually pay on the wide lane, and does K−2 oversubscription
hurt? (R10, and §3.4's `M_alloc` claim.)**
```
$SAFE build-exe -j6  --intern-partitions=8 --time-report -Mroot=<same product>   # physical only
$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<same product>   # all logical
```
Three repeats each, alternating. *Predicted before the run:* `-j12` wins on
`real_ns_files` (the AstGen timer, set at `Zcu/PerThread.zig:157-161`) by 20–40%
and is within noise on `cpu_ns_sema`. **If `-j12` loses on either, `M_wide`
becomes physical and the amendment's wide-lane assignment is corrected in
public.**

**V14 — negative control for R9 (the affinity intersection).**
On a scratch copy, remove the affinity intersection from the topology probe,
rebuild, and run under `taskset -c 0-3`.
*Expect:* the print line reports `6 physical / 4 logical` — visibly impossible,
which is what makes it a usable control. Restore, verify by checksum, confirm
`4 physical / 4 logical` returns. **A probe whose guard was never seen red is a
probe nobody has met.**

**Not queued, and why — each is UNKNOWN, not passing:**
- **cgroup CPU quota** (`/sys/fs/cgroup/cpu.max`) is not consulted by the probe
  and no container run is queued. A quota-limited container will over-derive.
  Named in R9; the print line's `probe:` field is the operator's only warning.
- **Windows and macOS/BSD arms** of the topology probe cannot be executed here;
  their fallback to `logical` is read-verified only.
- **Hosts above 12 logical / 6 physical.** Every number in §3.5 outside the
  target row is arithmetic, not measurement. The 16-physical cliff claim in
  §3.5 is derived from `getIndexMask`, not observed.
- No fuzzing of the admission gate.

---

## 9. Provenance

Design, source census, and this dossier: Claude Opus (Anthropic, via Claude
Code), design lane, read-only against `44e391fb`. Charter, both orders, and the
ruling that both members stay selectable: Daniel Campos Ramos. Binding prior
findings: `docs/crown/PATCH002_MEMO.md` (measure: Claude Sonnet; adversarial
verify: Claude Opus; disposition: Claude Fable 5) and
`docs/crown/INTERNALS_MAP.md` (7 Sonnet readers + Opus synthesis).

The charter amendment (topology awareness, the 6c/12t measurement, the split
sibling map, and the per-phase physical/logical derivation) was ruled mid-lane
by Daniel Campos Ramos and is integrated in §0, §1.3, §2.3, §3.3–§3.8, §4.4,
§5, §6, §7 (R9–R12) and §8 (V0a, V1, V7a/V7b, V12–V14). The one place the
amendment's requested shape was **not** adopted literally is §2.3.1: it asked
for `(K, M_alloc, M_wide)` and the source says `M_alloc = K − 2` identically, so
the dossier reports two derived numbers and one subtraction rather than
inventing a third knob. That is a stated disagreement resolved by evidence, per
`CONTRIBUTING-AI.md`, and it is the maintainer's to overrule.

**Named residuals, in full:**

1. Nothing here is compiled. Every claim is **read-verified only**; §8 is the
   list of what would make it measured. No PRE/POST pair exists yet for any
   claim in this dossier. The one exception is the host topology itself
   (6 physical / 12 logical, split siblings), which the owner measured with
   `lscpu -e` and `/sys/.../thread_siblings_list` and which V0a records as the
   oracle.
2. Upstream-master state after 0.16.0 is **UNKNOWN** — Codeberg serves
   deliberate garbage to automated fetchers and its issue/PR listings could not
   be enumerated. Only individually-named pages resolved; the denominator of
   that search is in §2.4.
3. The resolution status of [#26027](https://github.com/ziglang/zig/issues/26027)
   is **UNKNOWN**; only the opening report was retrievable.
4. `Air.Liveness` / `Air.Liveness.Verify` are pure work inside an allocating
   worker (§1.3) and are a real M-lane candidate. Not designed here.
5. `facade_rank` (§4.3) approximates "internal before facade" as
   "non-root file before root file". Zig has no visibility model that would
   support a stricter reading; the approximation is declared, not hidden.
6. **The module-count heuristic is retired.** An earlier draft derived K from
   `ceil(module_roots.count() / 128)` — a declared constant awaiting a
   measurement. The amendment replaced it with a hardware probe, which is
   strictly better provenance: physical cores are *measured*, module-per-
   partition ratios were *guessed*. The retired approach is recorded here
   rather than deleted, per `CONTRIBUTING-AI.md`, alongside what retired it.
7. **`M_alloc = K − 2` oversubscribes physical cores by ≈1.33× on the target
   host** (8 allocating-capable tasks over 6 cores). Justified by two of the
   eight being usually blocked (`Zcu.zig:5311`, `link/Queue.zig:189`) — a
   *reading*, not a measurement. V13 decides it.
8. **cgroup CPU quota is not consulted.** Affinity is; quota is not. A
   container limited to a fraction of a CPU will still see whole physical
   cores. Named, not approximated.
9. Windows and macOS tid/`Io.Threaded` behaviour, the non-Linux topology probe
   arms, and any host wider than the 6c/12t target are outside this lane's
   reach. Every number in §3.5 outside the target row is arithmetic.

*Even in the lixão, a flower is born.*
