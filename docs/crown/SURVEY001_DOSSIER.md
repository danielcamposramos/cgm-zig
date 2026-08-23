# survey/001 — beyond the compiler: a ranked opportunity survey of `lib/std` and the build machinery

*2026-08-22. Survey lane: read + design only — no compiler build, no `zig`
invocation of any kind was made while authoring this (another process owned this
machine's execution window). Every run this survey would need is written down in
§8 as a command with its expected observation, and none of them were run.
Nothing outside `docs/crown/` is modified by this branch.*

**Anchor pin.** Every `file:line` below was read against commit `44e391fb`
(`main` at authoring time, and this branch's merge base). `PATCH005_DOSSIER.md`
pins to the same commit; where this survey and that dossier disagree on a line
number, §0.3 records the disagreement and this survey is the later read.
Identifiers are given alongside every line so a stale anchor is recoverable by
name.

**Charter.** One question from the project owner, near-verbatim:

> *"We are only messing with the compiler part of it — should we at least take a
> look at zig itself?"*

**The strategic fact that drives the entire ranking.** `lib/std` ships **inside
the binaries this toolchain produces**. An improvement to `src/` is a faster
build. An improvement to `lib/std` is a faster *product*, on every machine the
product ever runs on, forever. The compiler is a consumer of `lib/std` like any
other program — so a capability added to `lib/std` is delivered to the compiler
*and* to everything the compiler builds, from one implementation. That asymmetry
is worth roughly one full rank position in the table below, and it is applied
explicitly rather than felt.

**Relationship to `patch/005`.** This survey does **not** re-derive
`PATCH005_DOSSIER.md`. Its four falsified premises bind here as established
facts. Where scopes touch — the topology probe, `std.Build`, the build runner,
`Io.Threaded` — this survey **cites and extends**, and says which section it is
extending. Two of its findings (§0.2 items 4 and 5) retire open UNKNOWNs the
dossier carried; three (§0.3) correct its anchors. That is the intended
relationship: the dossier owns the compiler's threading, this survey owns
everything the compiler *links*.

---

## 0. Premise audit — what the brief carried in, and what the source says

Per the fork's receipt standard, corrections to the incoming brief are
first-class findings and are stated before anything is built on top of them.

### 0.1 The brief's premises, tested

| Incoming premise | Verdict | Evidence |
|---|---|---|
| Scope item 1 targets **`lib/std/Thread/Pool.zig`** | **FALSIFIED — the file does not exist, and neither does its directory** | `ls lib/std/Thread/` → no such directory. `find lib/std -name '*Pool*'` → **0 hits**. The only surviving mention of the type in the whole tree is a comment: `src/Zcu/PerThread.zig:67` *"a temporary workaround put in place to migrate from `std.Thread.Pool`"*. Upstream deleted it — see §6, row U1. **Scope item 1's named target is a NO-OP row; its *intent* survives and is re-pointed at `lib/std/Io/Threaded.zig`.** |
| `lib/std/Io/` (especially `Threaded`) holds the auto-hardware derivation opportunity | **HOLDS, and is the correct re-pointing of item 1** | `lib/std/Io/Threaded.zig:1634-1641` is the whole std-side derivation: `std.Thread.getCpuCount()` → `async_limit = .limited(n-1)`. 18,902 lines; the derivation is 8 of them. |
| The host is 6c/12t with split sibling pairing `(0,6)…(5,11)` | **HOLDS — carried from the dossier, owner-measured, not re-measured here** | `PATCH005_DOSSIER.md` §0 and V0a. This survey adds no independent measurement of the host. |
| SMT siblings share L1/L2 and execution ports, so the API should let callers distinguish physical from logical | **HOLDS as a design input; the API does not exist to distinguish with** | `lib/std/Thread.zig:290-292` — `getCpuCount` documents itself as *"the number of logical CPU cores"*. There is **no** physical-core, sibling-map, NUMA or cgroup-quota API anywhere in `lib/std`. Upstream has none either (§6, row U2). |
| Scope item 5, `lib/std/heap`, is **"host-side relevance only"** | **FALSIFIED — `SmpAllocator` ships in user binaries** | `lib/std/start.zig:704-713`: for a non-libc, non-wasm, non-single-threaded program using `std.start`'s managed entry, the default gpa **is** `std.heap.smp_allocator` (`:710-711`). It is also the compiler's own gpa on the same condition — `src/main.zig:179-181` returns `wasm_allocator` on wasi, `c_allocator` when linking libc, and `smp_allocator` otherwise. So item 5 is *both* host-side and product-side, and its ranking rises accordingly (S6). |
| Scope item 2: the build runner's randomized independent-step order at `build_runner.zig:1283` is open ground | **HOLDS as a fact; is NOT open ground — `patch/005` already owns it** | `PATCH005_DOSSIER.md` §4.3 Level 1 designs `--step-order=layered\|random\|declared` against exactly `build_runner.zig:1283`. This survey does not re-open it. What it adds instead is the *measured* input that dossier §4.3 says it lacks — see S5. |
| `Thread.Pool` usage *inside the compiler* is dossier scope | **HOLDS and is moot** | There is no `Thread.Pool` to use. `grep -rn 'Thread\.Pool' lib/ src/` → 1 hit, the comment at `src/Zcu/PerThread.zig:67`. |

### 0.2 Five premise corrections and extensions, volunteered

1. **`busy_count` is ONE counter serving TWO limits and FOUR admission gates.
   This is the std-level root cause of the dossier's R3.** The dossier
   (§2.2 H2, §7 R3) states the hazard — `io.concurrent` starvation silently
   re-serialises the linker via `link/Queue.zig:71-74` — and attributes it to
   "parked workers inflating `busy_count`". The mechanism is simpler and worse
   than that, and it needs no parked workers at all. `Threaded.busy_count`
   (`lib/std/Io/Threaded.zig:46`) is a single field. It is incremented at four
   sites — `:2107` (`async`), `:2156` (`concurrent`), `:2203` (`groupAsync`),
   `:2264` (`groupConcurrent`) — and decremented at exactly one (`:1799`). But
   it is tested against **two different limits**: `async_limit` at `:2100` and
   `:2197`, `concurrent_limit` at `:2153` and `:2261`. Its own doc comment
   (`:43-45`) concedes the coupling: *"To calculate available count, subtract
   this from **either** `async_limit` **or** `concurrent_limit`."*
   **Consequence:** ordinary `io.async` work consumes the budget that
   `io.concurrent` tests against. In the compiler, where
   `async_limit = concurrent_limit = n-1` (`src/main.zig:7912-7926`, per dossier
   §0 correction 1), `n-1` in-flight AstGen or codegen tasks are sufficient, on
   their own, to make the linker's `io.concurrent` call at `link/Queue.zig:67`
   return `error.ConcurrencyUnavailable`. **There is no reservation mechanism of
   any kind.** This is S2, and it is the cheapest high-value row in the table.

2. **`Threaded` and `SmpAllocator` read the same probe and fail in opposite
   directions, both silently.** `Io.Threaded.init` on probe failure sets
   `async_limit = .nothing` (`lib/std/Io/Threaded.zig:1639`) — **fully serial**,
   the most conservative possible answer. `SmpAllocator.getCpuCount` on the same
   failure returns `max_thread_count` (`lib/std/heap/SmpAllocator.zig:103`:
   `@min(std.Thread.getCpuCount() catch max_thread_count, max_thread_count)`) —
   **128**, the most *aggressive* possible answer, on a host whose core count is
   unknown and might be 2. Neither reports the failure. `std` has no doctrine
   for an absent instrument; it has two ad-hoc reflexes pointing opposite ways.
   Doctrine 2 ("an absent instrument reports UNKNOWN, never zero") has a direct
   application here, and it is additive.

3. **`cpu_count_error` is write-only in the entire tree.**
   `lib/std/Io/Threaded.zig:42` declares it; `:1622`, `:1641`, `:1680` assign
   it. `grep -rn 'cpu_count_error' lib/ src/` → **4 hits, all writes, zero
   reads.** The field is public-by-default so a caller *could* read it, but
   nothing in `lib/std`, nothing in `src/`, and no diagnostic path does. A
   compiler that silently dropped to serial because `sched_getaffinity` failed
   would look, from the outside, exactly like a slow compiler.

4. **The dossier's residual 3 and risk R4 can be retired.** Dossier §2.4 and
   §9 residual 3 record [issue #26027](https://github.com/ziglang/zig/issues/26027)
   (`std.Io.Group` hangs with more tasks than threads) as **UNKNOWN** — "we read
   the issue's opening report only". It is **CLOSED, milestone 0.16.0** (§6, row
   U4). Our base *is* 0.16.0. R4 therefore downgrades from an unquantified
   liveness risk to a probably-fixed one; V5 in the dossier's §8 remains worth
   firing, now as a *confirmation* rather than as a gate.

5. **The dossier's §2.4 hope for [#25757](https://github.com/ziglang/zig/issues/25757)
   did not land.** Dossier §2.4: *"If this lands upstream, H1 softens
   considerably and the admission gate could be simplified."* The issue is
   **CLOSED, milestone 0.16.0, with no evidence work-stealing was implemented**
   (§6, row U5) — and `lib/std/Io/Threaded.zig` in our base has a single global
   `run_queue` (`:34`) under a single `mutex` (`:32`), which is what
   threadlocal run queues would have replaced. **H1 does not soften. The
   dossier's admission gate stays necessary.**

### 0.3 Anchor corrections to `PATCH005_DOSSIER.md`

Recorded rather than quietly used, per `CONTRIBUTING-AI.md`. All four re-reads
were made against the same commit the dossier pins (`44e391fb`), so these are
transcription slips, not drift.

| Dossier cite | Says | Actually | Impact |
|---|---|---|---|
| §1.1 A6, `link/Queue.zig:31` | `buffer_size` = 512 | `:31` is the doc comment; the declaration is **`:32`** — `pub const buffer_size = 512;` | none — value confirmed |
| §2.2 H2, `link/Queue.zig:87-91` | `enqueuePrelink`'s else-branch | the else-branch is **`:89-93`** (`:87` is `error.Closed => unreachable`, `:88` is `};`) | none — behaviour confirmed: `:90-91` takes `prelink_mutex`, `:92` runs `link.doPrelinkTask` inline |
| §1.1 A8, `Zcu/PerThread.zig:4612` | LLVM one-codegen-at-a-time assert | the assert is **`:4611`**; `:4612` is the `updateFunc` call | none — assert confirmed, and its SPIR-V twin at `:4620` is cited **correctly** |
| §2.2 H2 / §7 R3, `link/Queue.zig:71-74` | the `ConcurrencyUnavailable` fallback | **exactly right.** `:70` opens `else \|err\| switch (err)`, `:71` is the arm, `:73-74` set both queues `undefined` | binding fact **CONFIRMED verbatim** |

Also **confirmed unchanged** by independent re-read: `Thread.zig:1133-1136`
(affinity-aware `getCpuCount`), `Io/Threaded.zig:2100-2105` (async past its
limit runs inline on the caller), `link/Queue.zig:67` and `:152-153`,
`src/main.zig:3483-3487`, `src/target.zig:933-943`.

---

## 1. The frame that produces the ranking

Two axes, applied to every candidate.

**Axis 1 — where does the improvement land?** Three classes, and the class is
decided by one mechanical question: *is the code linked into the products this
toolchain builds?*

| Class | Meaning | Members surveyed |
|---|---|---|
| **PRODUCT** | in `lib/std`, linked into every binary built with this toolchain | `Io/Threaded.zig`, `Thread.zig`, `heap/SmpAllocator.zig` |
| **HOST** | build-time only; never in a product | `lib/compiler/build_runner.zig`, `lib/std/Build*` (a product never links its own build script), `src/` |
| **BOTH** | in `lib/std`, and the compiler is itself a consumer | a new `std.Thread.Topology` — the reason S1 ranks first |

**Axis 2 — rebase burden.** This fork freezes at a future upstream-0.17 rebase
gate (`PROVENANCE.md`, "Version policy"). Every touched surface is a liability
at that gate, and the liability is not proportional to LOC — it is proportional
to *how hard upstream is pushing on the same lines*. Three classes:

- **ADDITIVE** — a new file, a new directory, a new flag, a new field with a
  stock-preserving default. Carries across a rebase for approximately free.
- **ADDITIVE⁺** — a new field plus a handful of modified predicate lines in a
  hot upstream file. Cheap, but not free: a conflict is a three-line
  reapplication, not a redesign.
- **INVASIVE** — restructures upstream logic. Expensive to carry, and if
  upstream is *actively* reworking the same file (§7), effectively unpayable.

**The criterion, stated once:** rank by value **over** rebase burden, and prefer
additive. An opportunity upstream has already fixed is a NO-OP row (§6).

---

## 2. The ranked opportunity table

Re-ranked on evidence from the brief's a-priori order. The two largest moves are
stated with their reasons immediately below the table.

| # | Opportunity | Value, in one sentence | Class | Rebase | Rough LOC | Queued verification |
|---|---|---|---|---|---|---|
| **S1** | **`std.Thread.Topology`** — host the dossier's topology probe in `lib/std/Thread/Topology.zig` instead of `src/Topology.zig` | Every program built with this toolchain — not only the compiler — can size its worker pools from **physical cores intersected with the affinity mask**, a capability neither `std` nor upstream has in any form. | BOTH | **ADDITIVE** (new directory; `lib/std/Thread/` does not exist) | ~230 + 2 | V-S1a, V-S1b; dossier V0a/V1/V14 already cover the algorithm |
| **S2** | **`Io.Threaded` concurrent reservation** — stop `io.async` from eating `io.concurrent`'s budget | Removes the std-level root cause of the compiler's silent linker re-serialisation (dossier R3) for ~10 lines, and fixes it for every `std.Io` user at the same time. | PRODUCT | **ADDITIVE⁺** (1 field ×2 + 2 predicate lines) | ~12 | V-S2a, V-S2b (negative control) |
| **S3** | **Derived-defaults self-report for `Io.Threaded`** — surface the probe result and its failure | A program that silently dropped to `async_limit = .nothing` because a syscall failed is indistinguishable from a slow program; doctrine 4 applied to `std`. | PRODUCT | **ADDITIVE** (accessor + doc; no behaviour change) | ~20 | V-S3a |
| **S4** | **Propagate `-j` to child compilers** — `graph.max_jobs` currently reaches exactly one consumer, and it is the fuzzer | `zig build -j4` bounds concurrent *steps*, but each spawned compiler re-derives 12 workers from `getCpuCount()`, so the host runs up to 48; sharpens dossier R2 from an RSS risk to a measured CPU one. | HOST | **ADDITIVE** (one argv element) | ~25 | V-S4a, V-S4b |
| **S5** | **Per-step resource ledger** — persist the `result_peak_rss` / `result_duration_ns` the runner already measures and throws away | Auto-populates `max_rss` (today `0` on every step, so the RSS gate is inert) **and** supplies the measured input dossier §4.3 says its fan-in tie-break lacks. | HOST | **ADDITIVE** (new file + cache entry + flag) | ~200 | V-S5a, V-S5b |
| **S6** | **`SmpAllocator` probe fallback** — 128 is the maximum, not an answer | On probe failure the process-wide allocator behaves as if the host had 128 cores; it ships in user binaries via `start.zig:710-711`. | PRODUCT | **ADDITIVE⁺** (1 predicate line, or a `std.options` knob) | ~12 | V-S6a |
| **S7a** | **Name the linker's silent fallback** — one warning at `link/Queue.zig:71-74` | The single most consequential silent degradation in the compiler is currently invisible; dossier V4 has to *infer* it from a time report. | HOST | **ADDITIVE** (one diagnostic) | ~10 | V-S7a |
| **S7b** | **Parallelise a self-hosted linker section** | Highest ceiling in the survey and the only untouched frontier upstream — and the wrong thing to start. **Recommended: DO NOT START.** See §5. | HOST | **INVASIVE** | ~600+ | not queued; §5 states the gate |
| **S8** | **Incremental / self-hosted backend census** | A census, per the brief. Produces no patch; produces the DO-NOT-TOUCH list in §7 and the NO-OP rows in §6. | — | — | 0 | — |

**Move 1 — item 1 of the brief's a-priori order split and both halves moved.**
`lib/std/Thread/Pool.zig` fell out entirely (§0.1); its *intent* re-pointed at
`Io/Threaded.zig` and then separated into three rows (S1 the probe, S2 the
starvation, S3 the report) because they have different rebase classes and can
land independently.

**Move 2 — item 5 (`heap`) rose from last to S6, and item 4 (linkers) fell.**
`heap` rose because the brief's "host-side relevance only" is false
(`start.zig:704-713`) — it is a PRODUCT surface. The linkers fell because the
census found the ceiling is real but the floor is bedrock: **one parallel
section in 68,874 lines of `src/link/`** (§5), a single-consumer design stated
as intent in the file header, and an upstream that is actively rewriting the
ELF linker (§7, D1).

---

## 3. S1 — `std.Thread.Topology`: the same probe, hosted where it ships

**This is an extension of `PATCH005_DOSSIER.md` §3.3, not a re-derivation.** The
dossier owns the algorithm, and its rulings bind unchanged:

- the per-OS probe table and the `/proc/cpuinfo` fallback modelled on
  `lib/std/zig/system/linux.zig:420-447` — dossier §3.3;
- **the affinity intersection is mandatory** — dossier §3.3 and R9. A `/sys`
  read not intersected with `sched_getaffinity` over-derives in exactly the
  environment where the operator was most careful;
- **`physical` is `?usize`; null means UNKNOWN, never `logical / 2`** — dossier
  §3.3, doctrine 2;
- cgroup CPU quota is **not** consulted and is a named residual, not an
  approximation — dossier R9.

**What this survey contributes is the placement argument, and it is the whole
point of the lane.**

The dossier places the probe at `src/Topology.zig` — compiler-private. Placed at
`lib/std/Thread/Topology.zig` instead, one implementation serves:

| Consumer | Site | What it gets |
|---|---|---|
| the compiler | `src/main.zig:3483-3486` | exactly what dossier §3.4 derives — `M_wide` from logical, `K` from physical. Nothing in the dossier's design changes; only the import path. |
| `Io.Threaded` | `lib/std/Io/Threaded.zig:1634-1639` | the option to derive `async_limit` from physical cores for cache-heavy workloads — the distinction the brief asks for, delivered as API rather than as a compiler-private constant. |
| `SmpAllocator` | `lib/std/heap/SmpAllocator.zig:103` | a real answer instead of `max_thread_count` (S6). |
| **every program built with this toolchain** | — | a topology API that neither `std` nor upstream provides in any form (§6, U2). |

**Why the rebase burden is near zero, precisely.** `lib/std/Thread/` **does not
exist** — `ls` errors, and `find lib/std -name '*Pool*'` returns 0 hits. Upstream
emptied it (§6, U1) and `std.Thread` is now a lean namespace of 20 public
declarations (`lib/std/Thread.zig`: `spawn` `:344`, `join` `:370`, `detach`
`:364`, `getCpuCount` `:293`, `Id` `:262`, `yield` `:380`, names, config) with
every synchronisation primitive migrated out — `WaitGroup` is now *private*
inside `Io/Threaded.zig:18592`. A brand-new directory beside a lean file is the
lowest-conflict addition available in this tree, and the `Thread.zig` +
`Thread/` shape is already the house convention (`Io.zig` + `Io/`, `Build.zig` +
`Build/`).

**The cost of the alternative, stated so the choice is visible.** Keeping the
probe at `src/Topology.zig` is *also* additive and *also* cheap. It is simply
worth less: it delivers the capability to one program. Since the algorithm is
identical either way, the placement is free value — which is the rare case where
the honest choice costs nothing, and it is the same shape of argument dossier
§3.4 makes for rounding `K` up to a power of two.

**Named residual.** `lib/std` has a public-API surface upstream may collide
with. If upstream ever adds its own `std.Thread.Topology` with different
semantics, this becomes a rename at the rebase gate, not a redesign. Cheap, and
named.

---

## 4. S2, S3, S4, S5, S6 — the rest of the patchable set

### 4.1 S2 — the reservation `Io.Threaded` does not have

**The finding is §0.2 item 1:** one `busy_count`, two limits, four gates, no
reservation. The design that follows is deliberately the smallest thing that
could work:

```
InitOptions gains:  concurrent_reserve: usize = 0
Threaded    gains:  concurrent_reserve: usize
the two async admission tests change from
    busy_count >= @intFromEnum(t.async_limit)                       (:2100, :2197)
to
    busy_count + t.concurrent_reserve >= @intFromEnum(t.async_limit)
```

`concurrent` (`:2153`) and `groupConcurrent` (`:2261`) are **not** touched: they
already test the correct limit, and the reserve exists to keep async from
reaching it.

- **Default `0` means stock invocations are byte-identical** — the fork's
  standing law (`PROVENANCE.md`, "Our commitments"), and the reason this is
  ADDITIVE⁺ rather than INVASIVE.
- **The compiler's use is one line:** `src/main.zig:7912-7926` sets both limits
  today; it would additionally set `concurrent_reserve = 1`, reserving the slot
  `link/Queue.zig:67` needs. That is the whole of dossier R3's mitigation, moved
  from "the admission gate prevents parked workers from inflating `busy_count`"
  (dossier §7 R3 — a *consequence* of a design) to a guarantee that holds
  regardless of what the compiler does above it.
- **Relationship to upstream [#25748](https://github.com/ziglang/zig/issues/25748)
  (OPEN):** adjacent, not the same. Upstream proposes shrinking an over-grown
  pool on idle; this reserves admission budget. Both can be true; neither
  subsumes the other. If upstream lands theirs, this row survives.

**Honest limit, stated before the run.** A reserve is a coarse instrument: it
does not distinguish which of `busy_count`'s occupants are concurrent tasks
(which legitimately consume the reserve) from async ones. A precise fix tracks
two counters — which is an INVASIVE change to a hot file, in a scheduler
upstream has already reworked once (§6, U3) and proposed reworking again (§6,
U5). The coarse form is the correct trade at this rebase posture, and V-S2b is
the negative control that proves it fires.

### 4.2 S3 — a probe that failed should say so

`Io.Threaded.init` derives `async_limit` at `lib/std/Io/Threaded.zig:1639`:

```zig
.async_limit = options.async_limit orelse if (cpu_count) |n| .limited(n - 1) else |_| .nothing,
```

The `else |_| .nothing` arm is a **silent, total** loss of parallelism, and the
reason is captured at `:1641` into `cpu_count_error` (`:42`) — a field that
**nothing in the tree ever reads** (§0.2 item 3; 4 hits, all writes). Doctrine 4
("the tool can state its own resolved reality on request") has an exactly
analogous application here to the one dossier §3.7 makes for the compiler's
print line, and it is cheaper, because `std` must not print anything on its own:

- an accessor pair — the derived `async_limit` and the `?CpuCountError` that
  produced it — so a caller can *ask*;
- doc-comment the `.nothing` fallback at `:1582` (which today says only
  *"Defaults to one less than the number of logical CPU cores"* and does not
  mention the failure arm at all);
- **no behaviour change, no output**. `std` reports; the *application* decides
  whether to print. That is what keeps this ADDITIVE.

The compiler is then the first consumer: dossier §3.7's print line gains a
truthful `probe:` field for the case where the probe failed, instead of
reporting a derived number it did not derive.

### 4.3 S4 — `-j` stops at the build runner

**Extends dossier R2, which frames the risk as residency only.** The CPU half is
worse and is measurable.

- `lib/compiler/build_runner.zig:422-427` — `-j<N>` does two things:
  `threaded.setAsyncLimit(.limited(n))` (`:426`) and `graph.max_jobs = n`
  (`:427`).
- `graph.max_jobs` (`lib/std/Build.zig:133`) has **exactly one consumer in the
  entire tree**: `lib/std/Build/Step/Run.zig:2058`, choosing the number of
  *fuzzer* instances. `grep -rn 'max_jobs' lib/ src/` → 3 hits total
  (declaration, assignment, that consumer).
- `grep -n 'jobs' lib/std/Build/Step/Compile.zig` → **0 hits**. No compile step
  passes `-j` to the compiler it spawns.
- So each spawned `zig build-exe` reaches `src/main.zig:3483-3486` and
  independently derives `@max(n_jobs orelse getCpuCount() catch 1, 1)` — **12 on
  the target host**, regardless of `-j`.

**On a 6c/12t host, `zig build -j4` authorises up to 4 × 12 = 48 compiler worker
threads over 12 logical CPUs.** The fix is one argv element in `Step.Compile`.
The *policy* is the interesting part and is deliberately left as a flag rather
than guessed: `-j` per step, or `max_jobs / n_steps`, or `M_wide` from S1
divided by the step width. V-S4b measures it; no default ships without that run.

**Second finding, same site, recorded because it is upstream #25748 live in our
base.** `build_runner.zig:33-36` initialises `Threaded` with only `.environ` and
`.argv0`. It never sets `concurrent_limit`, so it inherits `InitOptions`'
default `.unlimited` (`lib/std/Io/Threaded.zig:1592`). `-j<N>` at `:426` bounds
`async_limit` **only**. The build runner therefore has an unbounded
`io.concurrent` growth path — exactly [#25748](https://github.com/ziglang/zig/issues/25748),
which is still OPEN. S2's reserve does not fix this; setting
`concurrent_limit` at `:33-36` would, and it is one line. Folded into S4.

### 4.4 S5 — the runner measures what it needs, then discards it

The build runner already has the data:

- `lib/std/Build/Step.zig:455` and `:500` — `s.result_peak_rss =
  zp.child.resource_usage_statistics.getMaxRss() orelse 0;`
- `lib/std/Build/Step.zig:662` — `s.result_duration_ns = ...untilNow(...)`
- printed in `--summary` at `lib/compiler/build_runner.zig:1043` (duration) and
  `:1058` (peak RSS)
- and **discarded at process exit.** Nothing persists them; `Step.zig:984-985`
  resets both to `null` / `0` on re-run.

Meanwhile the gate that would use them is inert:

- `Step.max_rss` defaults to **0** at every construction site —
  `lib/std/Build/Step.zig:231`, and `lib/std/Build.zig:775, 805, 828, 861, 902`.
- `0` means "no claim": the admission gate at `build_runner.zig:1429-1437` and
  the pre-flight check at `:722` both `continue` past it.
- `run.available_rss` defaults to `process.totalSystemMemory()`
  (`build_runner.zig:530-533`) — the number dossier R2 cites.

**So the sharper statement of dossier R2 is not "the default is too high". It is
that no step makes a claim at all, so `--maxrss` gates nothing either.** A user
who reaches for `--maxrss` after an OOM gets no protection, because protection
requires per-step `max_rss` values that nobody authors by hand for 1,800
modules.

The ledger closes the loop: persist `(step name → peak_rss, duration_ns)` in the
local cache next to the manifests (`build_runner.zig:84`,
`local_cache_directory`), read it at startup, use it to populate `max_rss` where
the step declares none, and expose it behind a flag so the derived value is
visible and overridable (doctrine 1).

**And it answers a question the dossier explicitly leaves open.** Dossier §4.3
proposes `(depth ASC, fan_in DESC)` and states its own counter-claim: *"a
high-fan-in step may also be the longest, and starting it first can leave the
pool idle at the tail. §8 (V7) is the run that decides between them."* A
duration ledger turns that from a coin-flip into critical-path scheduling —
`(depth ASC, remaining_critical_path DESC)` — with the durations *measured* from
the previous build rather than guessed. **S5 is the input dossier §4.3 says it
needs; it should land before the dossier's `--step-order=layered` default flips.**

### 4.5 S6 — `SmpAllocator`'s fallback is the maximum

```zig
// lib/std/heap/SmpAllocator.zig:103
const n: u32 = @min(std.Thread.getCpuCount() catch max_thread_count, max_thread_count);
```

`max_thread_count = 128` (`:50`). On probe failure the allocator rotates thread
slots modulo 128 (`:86`, `:165` — `index = (index + 1) % cpu_count`) on a host
that may have two cores, scattering allocations across 128 cache-line-aligned
`Thread` records (`:42`, `:59-61`) that never needed to be distinct. It is the
exact inverse of `Io.Threaded`'s reflex (§0.2 item 2), in the same standard
library, from the same failed syscall.

It ships: `lib/std/start.zig:710-711` selects `std.heap.smp_allocator` as the
default gpa for non-libc, non-wasm, multi-threaded programs, and
`src/main.zig:179-181` selects it for the compiler itself on the same condition
(wasi → `wasm_allocator`, `link_libc` → `c_allocator`, otherwise
`smp_allocator`). **Named residual:** whether *this estate's* compiler build
links libc — and therefore which arm it takes — was not measured in this lane.

The minimal honest change is the fallback value, not the design. With S1
available, the fallback can be a *derived* number (physical cores, or logical,
or a declared conservative constant) instead of the array bound — and whichever
is chosen, it is one predicate line and the choice is declared rather than
implicit. `max_thread_count = 128` as the *array* bound is fine and stays.

**Named residual, not designed here.** The `cpu_count` memoisation at `:100-104`
is a one-shot `cmpxchg`; it never re-reads. That is a real staleness bug on
hosts that hot-plug CPUs, and upstream has it on file
([#23593](https://github.com/ziglang/zig/issues/23593), state **UNKNOWN** — §6,
U6). Out of scope; recorded so the next reader does not re-earn it.

---

## 5. S7 — the self-hosted linkers: the ceiling is real, the floor is bedrock

**Extends the dossier's `Queue.zig:71-74` finding rather than re-deriving it.**

**What the census found.** In **68,874 lines** across `src/link/`, exhaustive
greps for `async(`, `concurrent(`, `Group`, `spawn`, `WaitGroup` return exactly
**one** parallel work section: `src/link/MachO/hasher.zig:41`
(`group.async(io, worker, ...)`, group at `:32`, awaited at `:51`), reached only
from `src/link/MachO/uuid.zig:29` and `src/link/MachO/CodeSignature.zig:296`.
**The ELF linker — the one this estate uses — has zero.** The other
`Group` hits are the ELF *COMDAT group* type (`src/link/Elf.zig:3654`, `:4113`;
`src/link/Elf/Object.zig:50`; `src/link/Elf/file.zig:211`), and every `spawn` is
an LLD subprocess (`src/link/Lld.zig:1636`, `:1645`, `:1693`).

**Serial by design, and the design says so.** `src/link/Queue.zig:3-4`: *"The
compiler writes tasks to these queues, and **a single concurrent linker task**
receives and processes them."* `:6-7`: *"All prelink tasks must be queued and
completed before any ZCU tasks can be processed."* The worker body is two
strictly sequential `while (true)` loops (`:157` `prelink_tasks:`, `:186`
`zcu_tasks:`) with `lf.prelink()` serialised between them (`:174-184`). Tasks
are dequeued in batches of 128 (`:158`, `:187`) and then processed **one at a
time** (`:167`, `:196`) — batching exists; parallelism does not.

**The ELF phases, all serial**, each verified at its entry point: driver
`Elf.zig:746` `flush` → `:766` `flushInner`; `resolveSymbols` `:1221` (and run
*twice*, `:1271-1274`); `markLive` `:1282`; `scanRelocs` `:1331`; merge-section
handling `:1788`, `:1825`, `:1831`, `:1846`; sorting `:2188`, `:2317`, `:2419`;
relocation application `Elf/Atom.zig:619` and `:795`; output writing `:2992`,
`:3126`. These are the classic parallelisable phases in every other linker, and
here they are straight-line `for` loops.

**Why S7b is nonetheless the wrong thing to start, in three facts:**

1. **Upstream is mid-rewrite.** `src/link/Elf2.zig` (3,837 lines) already exists
   beside `src/link/Elf.zig` (4,505 lines + ~9.6k under `Elf/`), selected at
   `src/link.zig:1276` (`.elf => if (use_new_linker) .elf2 else .elf`). The
   upstream devlog entry *"ELF Linker Improvements"* (2026-05-30, **after**
   0.16.0) states the new linker *"was (and still is) disabled by default"*.
   Any work on either file is work on a file upstream is actively rewriting.
   **This is the single largest rebase liability found in the survey** (§7, D1).
2. **`-fincremental` silently selects it.** `src/Compilation/Config.zig:441-455`:
   after the LLD and object-format guards, `break :b options.incremental` —
   so enabling incremental compilation switches the ELF linker to `Elf2`
   *unless* `-fnew-linker` / `-fno-new-linker` is given explicitly (`:452`,
   parsed at `src/main.zig:1516-1519`). A linker patch and an incremental
   experiment are not independent variables at this base.
3. **Upstream has parallelised none of it, and that is not an oversight.** Three
   searches returned zero results (§6, U7); the ELF linker carries its own
   admission of a deeper problem at `src/link/Elf.zig:1246-1248`: *"TODO This
   loop has 2 major flaws: 1. It is O(N^2) which is never allowed in the
   codebase. 2. It mutates shared_objects, which is a non-starter for
   incremental compilation."* An O(N²) mutating loop is an algorithmic defect;
   parallelising it would hide it.

**S7a is what to do instead, and it costs ten lines.** The fallback at
`link/Queue.zig:70-76` sets both queues to `undefined` and returns, with no
diagnostic. The whole pipeline silently re-serialises and the only present
evidence is a shape in a `--time-report` — which is how dossier V4 has to detect
it (*"a run where `real_ns_decls` ≈ `real_ns` and link shows no overlap
means..."*). One warning naming `error.ConcurrencyUnavailable`, the `busy_count`
at the time, and the `concurrent_limit` it hit converts an inference into an
observation, and it is doctrine 2 exactly: *never a silent anything*.

**Also recorded, for the file that ordered it:** `src/target.zig:941-942` —
*"Please do not make any more exceptions. Backends must support being run in a
separate thread from now on."* — with two live exceptions immediately above,
`.stage2_llvm => false` (`:937`) and `.stage2_spirv => false` (`:940`). Upstream
appears to have retired the SPIR-V one after 0.16.0 (§6, U8).

---

## 6. Upstream-already-fixed and NO-OP rows

Rows where the correct action is *record the URL and move on*. Every state was
fetched; where a page did not resolve it says so.

| # | Row | URL | State | Consequence for this fork |
|---|---|---|---|---|
| **U1** | `std.Thread.Pool` removed, uses replaced by `std.Io` | [codeberg PR 30557](https://codeberg.org/ziglang/zig/pulls/30557) · [0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html) | **MERGED** 2025-12-22; shipped in 0.16.0 (released [2026-04-14](https://ziglang.org/news/0.16.0-released/)) | **NO-OP. The brief's scope item 1 target does not exist in this tree** (§0.1). The PR body itself warns of perf regressions from *"`std.Io.Threaded`'s constraints on queuing tasks beyond available CPU cores"* — which is this survey's S2/S3 and the dossier's ORDER 1, in upstream's own words. |
| **U2** | CPU topology in `std` — physical cores, SMT siblings, NUMA, cgroup quota | — | **DOES NOT EXIST**, upstream or here. 6 targeted searches, 0 hits | **S1 is genuinely novel, not a re-implementation.** No upstream issue was found even *requesting* that `getCpuCount` distinguish physical from logical. |
| **U3** | `std.Io.Threaded`: performance, bugfixes, Windows/NetBSD | [codeberg PR 30634](https://codeberg.org/ziglang/zig/pulls/30634) | **MERGED** 2026-01-03 — **pre-0.16.0, therefore already in our base** | Cancellation rework, group cleanup, userland futex redesign. Explicitly does **not** add work stealing, topology, or pool sizing. Does not overlap S2/S3. |
| **U4** | `std.Io.Group` hangs with more tasks than threads | [#26027](https://github.com/ziglang/zig/issues/26027) | **CLOSED**, milestone **0.16.0** | **Retires dossier §9 residual 3 and downgrades R4** (§0.2 item 4). Our base is 0.16.0. The fixing PR was not identified — likely U3 — so dossier V5 stays queued as confirmation, not as a gate. |
| **U5** | Threadlocal run queues + work stealing for `Io.Threaded` | [#25757](https://github.com/ziglang/zig/issues/25757) | **CLOSED**, milestone 0.16.0; close reason not visible on 2 fetches → **UNKNOWN** | **Did not land.** Our base still has one global `run_queue` (`Io/Threaded.zig:34`) under one `mutex` (`:32`). **Dossier §2.4's hope that H1 would soften is falsified** (§0.2 item 5); its admission gate remains necessary. |
| **U6** | `io.concurrent` inflates the pool past `cpu_count` | [#25748](https://github.com/ziglang/zig/issues/25748) | **OPEN**, milestone "Upcoming" | Live in our base, and **live in our build runner specifically**, which never sets `concurrent_limit` (`build_runner.zig:33-36`) — folded into S4. Adjacent to S2, not subsumed by it. |
| **U7** | Parallel self-hosted linking | — | **NOT FOUND.** 3 searches, 0 hits; the 2026-05-30 ELF devlog mentions no threading | S7b's frontier is genuinely open — and §5 says do not enter it. |
| **U8** | SPIR-V codegen scheduled on the thread pool | [ziglang devlog 2026](https://ziglang.org/devlog/2026/) (2026-06-26) | **LANDED upstream, post-0.16.0** | Our base still has `.stage2_spirv => false` at `src/target.zig:940`. **Do not patch this** — it is a free win at the 0.17 rebase gate. |
| **U9** | Incremental compilation with the LLVM backend | [ziglang devlog 2026](https://ziglang.org/devlog/2026/) (2026-04-08) | **LANDED**, just pre-0.16.0; called *"relatively stable"* | See §8: "stable" is true of *in-process* incremental only. Nothing to patch. |
| **U10** | Build system reworked | [ziglang devlog 2026](https://ziglang.org/devlog/2026/) (2026-05-26) | **LANDED upstream, post-0.16.0** | **The strongest DO-NOT-TOUCH signal in the survey** (§7, D2). Any invasive edit to `lib/std/Build*` or `build_runner.zig` is a guaranteed conflict at the rebase gate. S4/S5 are additive precisely because of this row. |
| **U11** | `SmpAllocator` cpu count goes stale on CPU hot-plug | [#23593](https://github.com/ziglang/zig/issues/23593) | **UNKNOWN** — search snippet only, page not fetched | S6's named residual. Not addressed here. |

**Search denominator, honestly.** 18 searches; 15 fetches — 11 fully successful,
3 partial (the 0.16.0 release-notes body would not render past its headings, ×2;
GitHub issue-close metadata would not render), 1 hard failure. The hard failure
was Codeberg's issue *listing*, which returned anti-scraper filler carrying the
literal string *"If you are an AI scraper, and wish to not receive garbage when
visiting Codeberg: stop visiting."* — **the dossier's §9 residual 2 warning is
CONFIRMED.** Individually-named Codeberg PR pages (30557, 30634) resolved
cleanly, so Codeberg is fetchable by exact URL but **not enumerable**.
**Therefore: any post-0.16.0 upstream change we did not learn of by name is
outside this survey's denominator. Upstream-master state is UNKNOWN, not
"unchanged."**

---

## 7. DO-NOT-TOUCH list, each with its reason

| # | Surface | Reason |
|---|---|---|
| **D1** | `src/link/Elf2.zig`, `src/link/Elf.zig`, and the `use_new_linker` path (`src/link.zig:1273-1284`, `src/Compilation/Config.zig:441-455`) | **Upstream is mid-rewrite.** Devlog 2026-05-30, post-0.16.0: the new ELF linker *"was (and still is) disabled by default"*. Two live implementations, 17,900+ lines between them, and `Config.zig:454` silently couples the choice to `-fincremental`. Maximum rebase liability in the tree. |
| **D2** | `lib/std/Build.zig`, `lib/std/Build/**`, `lib/compiler/build_runner.zig` — **internals** | **Upstream reworked the build system after our base** (devlog 2026-05-26, §6 U10). Additive flags and new files only. S4 and S5 are shaped to obey this: one argv element, one new file, one cache entry. |
| **D3** | `lib/std/Io/Threaded.zig` scheduler core — `run_queue` (`:34`), `mutex` (`:32`), `worker`, the cancellation machinery | Reworked by U3 pre-0.16 and proposed for rework again by U5/U6. Touch **only** the admission predicates (`:2100`, `:2197`) and add fields; never restructure the queue. This is exactly the ADDITIVE⁺ boundary. |
| **D4** | Compiler-core threading: `src/main.zig:3483-3487`, `setThreadLimit` (`:7912-7926`), `src/Zcu/PerThread.zig` tid pool (`:69-121`), `InternPool.zig:6293-6335` | **`patch/005` owns this.** This survey's S1 changes only where the probe *lives*; every derivation rule stays the dossier's. |
| **D5** | Language semantics — anything that changes which programs compile or which errors they produce | `PROVENANCE.md`, "Our commitments": *no language divergence*. The language contract is the reason this toolchain was chosen. Dossier §4.2 already refused an ordering change for exactly this reason; the same line binds here. |
| **D6** | `InternPool` index widening (`CaptureValue`, `Index` → `u32`) | `patch/002` refused it at 427 sites; dossier §5 prices the debt and designs around it. Not a `lib/std` question at all. |
| **D7** | `src/target.zig:940` (`.stage2_spirv => false`) | Upstream already fixed it post-0.16.0 (§6 U8). Patching it here converts a free rebase win into a merge conflict. |
| **D8** | `src/codegen/x86_64/CodeGen.zig`, `src/codegen/riscv64/CodeGen.zig` and peers | Six-figure line counts, heavy upstream churn, and no `lib/std` relevance. Out of this lane entirely. |
| **D9** | `lib/std/heap/SmpAllocator.zig` — the **design** (slab classes, freelist reclamation, the 128-entry array bound at `:50`) | S6 changes one fallback *value*. The allocator's structure is subtle, load-bearing for every product binary (`start.zig:710-711`), and has no reported defect. Fix the declared number; leave the machine alone. |

---

## 8. Census: incremental compilation and the self-hosted backends at this base

Per the brief: **a census, not a plan.** It produces no patch. It produced D1,
D7 and U8–U10.

### 8.1 Incremental

| Fact | Evidence |
|---|---|
| Flag and default | parse `src/main.zig:1409-1413` (`-fincremental` / `-fno-incremental`); help `:456-457`; **default `false`** at `src/Compilation/Config.zig:110`; resolved field `Config.zig:53`, assigned `:565`. There is no `comp.incremental` field — the runtime guard is `comp.config.incremental`. |
| **State is written and never read** | `saveState` defined `src/Compilation.zig:3707` (guarded `dev.check(.incremental)` at `:3708`), wrapper `src/main.zig:4246-4249`, called on exit at `src/main.zig:3809` and `:3816`. **`loadState`: 0 hits** across `src/` — denominator **172 `.zig` files / 504,111 lines**. There is no deserializer anywhere in the tree. |
| What that means | **Cross-process incremental is not wired at this base.** Reuse requires a live `Compilation` — the `--listen` server loop (`src/main.zig:4252` `serve`, `:4291` `while (true)`). Upstream's *"relatively stable"* (§6 U9) is true of in-process incremental; it is not a claim that the state file round-trips. |
| Guard sites | 6, complete: `src/Compilation.zig:4111`, `:4258`; `src/Zcu/PerThread.zig:273`; `src/Sema.zig:7299`, `:33846`; `src/link/Dwarf.zig:6464`. Note `Sema.zig:33846` — `declareDependency` early-returns when off, so **the whole dependency graph is inert without `-fincremental`**. |
| In-tree admissions | `src/main.zig:5578` *"Since incremental compilation isn't done yet, we use cache_mode = whole"*; `src/link/Dwarf.zig:6461` *"until `-fincremental` is functional"*; `src/Compilation.zig:1507-1509` *"incremental compilation is only supported with the `-fincremental` command line flag, so this mode is rarely used"*; `src/Zcu/PerThread.zig:3223-3226` *"TODO: incremental compilation! ... we'll end up with duplicates"*; `src/Type.zig:1658, 1681, 1708` *"will behave incorrectly under incremental compilation"*. |
| `--watch` | **Not in the compiler** — 0 hits in `src/`. Build-runner only: parse `lib/compiler/build_runner.zig:342`, guard `:548`, loop `:571` `rebuild: while (true)`, impl `lib/std/Build/Watch.zig`. |
| Coupling that matters | `src/Compilation/Config.zig:454` — `-fincremental` **implies the new ELF linker** unless `-fnew-linker`/`-fno-new-linker` is explicit. See D1. |
| Debug surface | `--debug-incremental` (`src/main.zig:1403-1408`, requires `-fincremental` at `:3548-3550`) spawns a REPL TCP server on port 7623 — `src/IncrementalDebugServer.zig:1-3`, `:35`. |

### 8.2 Self-hosted backends

| Fact | Evidence |
|---|---|
| No `src/arch/` | does not exist; all backends are under `src/codegen/`: `aarch64/ arm/ c/ llvm/ mips/ riscv64/ sparc64/ spirv/ wasm/ x86_64/`. No `powerpc/` despite the enum tag. |
| The enum | `lib/std/builtin.zig:1165` `CompilerBackend`, tags `:1176-1208` (`stage2_llvm=2 … stage2_powerpc=12`). |
| Backend choice | `src/target.zig:888-903` `zigBackend(target, use_llvm)`. |
| **LLVM-vs-self-hosted default** | `src/Compilation/Config.zig:330-374`, in order: no LLVM support → false (`:345`); backend `.other` → true (`:351`); explicit `-fllvm`/`-fno-llvm` wins (`:356`); **`if (root_optimize_mode != .Debug) break :b true;` (`:364`) — every release build is LLVM**; then `!selfHostedBackendIsAsRobustAsLlvm(target)` (`:373`). |
| Which targets are self-hosted by default | `src/target.zig:278-296`: big-endian → false (issue 25961); SPIR-V → true; x86_64 64-bit → false on illumos (25699) and BSD (24341), else `.elf, .macho => true`; **everything else `return false`**. Net: **x86_64 ELF/macOS, Debug only**, plus SPIR-V. |
| `-fllvm` default | `src/Compilation/Config.zig:103` — `use_llvm: ?bool = null`, i.e. **auto**. Parsed `src/main.zig:1504-1507`. |
| Feature matrix | `src/target.zig:905-946`. `error_return_trace` (`:917-920`) and `is_named_enum_value` (`:921-924`) are **llvm + x86_64 only**. `separate_thread` (`:933-943`) is *all except* `.stage2_llvm` (`:937`) and `.stage2_spirv` (`:940`), with the standing order at `:941-942`. |
| Single-codegen asserts | `src/Zcu/PerThread.zig:4611` (LLVM, inside `if (zcu.llvm_object)` at `:4610`) and `:4620` (SPIR-V, inside `if (lf.cast(.spirv))` at `:4619`), both *"only one codegen at a time"*, both returning `error.BackendDoesNotProduceMir` (`:4613`, `:4627`). Serialisation gate: `:281-287` calls `comp.link_queue.finishZcuQueue(comp)` early when `!backendSupportsFeature(.separate_thread)`. |

---

## 9. Queued verification — the exact runs, written as commands, **not run**

Fired after the machine's execution window frees, and **after** the dossier's V0
produces `$SAFE`. Every entry names its expected observation; anything that did
not run reports **UNKNOWN**, never green. These are *additional* to
`PATCH005_DOSSIER.md` §8, which is not restated here.

**V-S1a — the std topology probe agrees with the host's instruments.** Oracle is
the dossier's V0a, recorded first so the probe cannot be tuned to agree with
itself. A `std` unit test asserting `logical == 12`, `physical == 6`, and that
every sibling group intersects the affinity mask in exactly one CPU under
`taskset -c 0-3`. *Expect:* pass unrestricted; under the pin, `4 / 4`, **not
`6 / 4`**. A `6` is dossier R9 firing and blocks S1.

**V-S1b — S1 changes nothing for a program that does not ask.** Build a stock
hello-world with and without the patched `lib/std`, compare artifact digests.
*Expect:* **byte-identical.** A new file that nothing imports must not perturb
`lib/std`'s compiled output; if it does, the import is not as lazy as designed.

**V-S2a — the reservation keeps the linker's slot.**
`$SAFE build-exe -j12 --intern-partitions=8 --time-report -Mroot=<mid-size project>`
with `concurrent_reserve = 1` set, versus the same run with `0`. *Expect:* with
`1`, link work overlaps analysis in the time report; with `0`, dossier V4's
no-overlap signature appears at least once across three repeats. **If `0` never
starves, §0.2 item 1 overstates the frequency and this survey is corrected in
public** — the mechanism would still be real, the exposure would not.

**V-S2b — negative control for S2.** On a scratch copy, set
`concurrent_reserve` larger than `async_limit` and confirm `io.async` refuses to
admit *anything* (every task runs inline via `Threaded.zig:2100-2105`). Restore,
verify by checksum. **A guard never seen red is not a guard.**

**V-S3a — the probe failure is reportable.** On a scratch copy, sabotage
`Thread.zig:1133-1136` to return `error.Unexpected`; confirm the new accessor
reports the error and that `async_limit` is `.nothing`; confirm the compiler's
print line (dossier §3.7) says `probe: unknown` rather than a number. Restore,
verify by checksum.

**V-S4a — the oversubscription is real, measured before it is fixed.**
`zig build -j4` on a multi-step project while sampling
`ps -eLf | grep -c 'zig build-exe'` and the per-process thread count. *Predicted
before the run, and not adjusted afterward:* peak total compiler worker threads
> 12 on a 12-logical host, approaching 4 × 12. **If total threads never exceed
12, §4.3's central claim is wrong and S4 is withdrawn.**

**V-S4b — and the fix is not a pessimisation.** Three repeats each of
`zig build -j4` with and without `-j` propagation, wall time and peak system
RSS. *Expect:* propagated is at or below un-propagated on wall time. **If
propagation is slower, the policy is wrong and only the `concurrent_limit`
half of S4 ships.**

**V-S5a — the ledger's numbers match the summary's.** One `zig build
--summary all` run, then compare the persisted ledger entries against the
`--summary` output for the same steps. *Expect:* exact agreement on
`result_duration_ns` and `result_peak_rss` for every step, **with the
denominator stated** — *n of N steps matched* — never a bare count.

**V-S5b — derived `max_rss` actually gates.** With the ledger populated, run
under a `--maxrss` below the sum of the two largest steps' recorded peaks.
*Expect:* the runner parks a step into `memory_blocked_steps`
(`build_runner.zig:1434`) — observable because today it provably cannot, every
`max_rss` being `0`. Negative control: clear the ledger, rerun, confirm nothing
parks.

**V-S6a — the fallback is exercised at all.** On a scratch copy, sabotage
`getCpuCount` as in V-S3a and print `SmpAllocator.getCpuCount()`. *Expect:*
`128` **before** the change and the derived/declared value **after**. Restore,
verify by checksum.

**V-S7a — the silent fallback becomes loud.** Force
`error.ConcurrencyUnavailable` at `link/Queue.zig:67` on a scratch copy (set
`concurrent_limit = .nothing`), compile anything. *Expect:* the new warning
names the error, the `busy_count`, and the limit; the compile still succeeds
(the fallback is a degradation, not a failure, and must stay one). Restore,
verify by checksum.

**Not queued, and why — each is UNKNOWN, not passing:**
- **The macOS and Windows arms of S1** cannot be executed in this estate;
  read-verified only. Same residual as dossier §9 item 9.
- **cgroup CPU quota** — not consulted by S1 (inherited from dossier R9), and no
  container run is queued.
- **Every host other than 6c/12t.** All arithmetic in this survey outside the
  target row is arithmetic, not measurement.
- **S7b** has no verification because it has no design, deliberately (§5).
- **No fuzzing** of the reservation logic in S2.

---

## 10. Provenance

Survey, source census, and this dossier: **Claude Opus** (Anthropic, via Claude
Code), survey lane, read-only against `44e391fb`. Two read-only census
sub-lanes — the `src/link/` serialization census (§5) and the
incremental/backend census (§8) — and one web-research sub-lane (§6) were
dispatched and their findings independently spot-verified at the file:line level
before entry here; the four verifications that disagreed with their source are
recorded in §0.3 rather than silently corrected. Charter and the question that
opened the lane: **Daniel Campos Ramos**.

Binding prior findings, cited and extended, never re-derived:
`docs/crown/PATCH005_DOSSIER.md` (design: Claude Opus; charter and both orders:
Daniel Campos Ramos) — its four falsified premises are treated as established
fact throughout, and §0.2 items 4 and 5 return two retired UNKNOWNs to it.
`docs/crown/DOCTRINE.md` principles 1, 2, 4 and 7 are the design law every
opportunity above answers to.

**Named residuals, in full:**

1. **Nothing here is compiled.** Every claim is **read-verified only**; §9 is the
   list of what would make it measured. No PRE/POST pair exists for any claim in
   this survey. No `zig` invocation of any kind was made.
2. **Upstream-master state after 0.16.0 is UNKNOWN, not "unchanged."** Codeberg
   is fetchable by exact URL but not enumerable (§6 denominator). Any post-0.16.0
   change we did not learn of by name is outside the denominator.
3. **Two upstream issue states are UNKNOWN**: [#25757](https://github.com/ziglang/zig/issues/25757)'s
   close *reason* (the row is read as "closed without landing" on the strength of
   our own source read at `Io/Threaded.zig:32-34`, not on upstream's word), and
   [#23593](https://github.com/ziglang/zig/issues/23593) entirely (snippet only,
   page not fetched).
4. **The §5 linker census's "zero parallel sections in 68,874 lines" is a grep
   result**, over `async(`, `concurrent(`, `Group`, `spawn`, `WaitGroup`. A
   parallel section reached by some other spelling would not appear. The
   denominator is those five patterns over `src/link/`.
5. **S2's coarse reserve is designed, not measured.** It does not distinguish
   which of `busy_count`'s occupants are concurrent; the precise two-counter form
   is INVASIVE and was refused at this rebase posture, not disproven. V-S2a
   decides whether the coarse form suffices.
6. **S4's propagation *policy* is deliberately unchosen.** `-j` per step vs
   `max_jobs / n_steps` vs an S1-derived share is a measurement (V-S4b), not a
   taste. No default ships before that run.
7. **The "ships in products" claim is architectural, not measured.**
   `start.zig:704-713` and `src/main.zig:181` are reads; no binary was built or
   inspected to confirm `SmpAllocator` is present in a stripped product.
   V-S1b is the nearest instrument and it checks the converse.
8. **S5 assumes step identity is stable across builds.** A ledger keyed on step
   name is wrong if names collide or are generated; the keying scheme is not
   designed here and is a prerequisite, not a detail.

*Even in the lixão, a flower is born.*
