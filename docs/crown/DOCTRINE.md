# Design doctrine of the fork

*These principles were not invented for this repository. They were proven over
months of human+AI engineering on a large hyper-modular estate (~1,800 modules,
thousands of generated-and-verified files) — the same estate whose compiles exposed
the crash this fork exists to fix. They are transplanted here, stated generically,
as the design law every patch in this fork answers to.*

## 1. Probe-first startup

At startup, probe the host — available memory, core count, free space on the cache
volume — and **derive** capacities from what was measured: pool pre-sizing, shard
counts, parallelism, spill thresholds. A hardcoded scale assumption (a table that
can only ever be indexed by a `u32`, a shard count frozen at build time) is a
default in disguise, and defaults age into crashes on hardware their author never
saw. Where a capacity genuinely cannot be derived, it is declared, visible, and
overridable — never buried.

## 2. Present-or-refuse-by-name

When the tool approaches any internal limit, the outcome is a **named refusal**:
which limit, the measured number that hit it, and the remedy (a flag, a split, a
budget) — never `unreachable`, never a silent SIGSEGV four gigabytes later. A
sentinel is never dereferenceable: if `0xFFFFFFFF` means "none," then indexing
with it must be impossible by construction or fatal by name. And an absent
instrument reports **UNKNOWN — never zero**: a measurement that didn't run is not
a measurement that returned nothing.

## 3. Safety-on for tools

A developer tool's safety checks are part of its product. The compiler people
trust with their programs should not ship with its own bounds checks compiled
out; a crash that names its own file, line, and index is a bug report, while a
stripped SIGSEGV is a week of forensics. This fork ships ReleaseSafe-class
checking on its own internals, and treats the release-binary performance delta as
a number to measure and publish, not a reason assumed in advance.

## 4. Self-report

The tool can state its own resolved reality on request: its module graph, its
capacity and limit state, what it derived at startup and from what probe. Stage 0
of the crown (`-femit-module-graph`) is the first member of this family. The
principle: any state the tool resolved internally is state an operator — human or
AI — can ask for, in a machine-readable form, without archaeology.

## 5. Parse the output; fire the negative control

Code that emits code is tested by **parsing what it emitted**, not by grepping
for substrings — a substring-only test once sat green over an emitter whose
output was invalid in 111 of 111 cases. And every guard is proven to **fire**
before it is trusted: sabotage the input, watch the check go red, restore, watch
it go green. A guard that has never fired is a hope, not a guard.

## 6. Cadence — bounded phases, module-boundary commit points

Long work proceeds in bounded phases with durable commit points at module
boundaries — the tiles. Each tile's artifact is complete and re-derivable before
the next tile is taken; the resident set stays inside the declared budget from
principle 1; an interruption costs at most one tile, never the run. Crash-safety
is a property of the cadence, not of luck.

## 7. Succession comments

Every non-obvious decision is explained in place for the next contributor —
human or AI — who was not present: what the code does, why this shape, what was
measured. Retired approaches are quoted alongside the measurement that retired
them, so the next reader inherits the negative result instead of re-earning it.
Contributors leave; the record stays.

---

*Applied together: 1 sizes it, 2 makes its edges honest, 3 keeps its checks on,
4 lets it testify, 5 proves the proofs, 6 bounds its appetite, 7 hands it on.*
