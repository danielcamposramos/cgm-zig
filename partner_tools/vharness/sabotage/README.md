# Sabotage patches — the four V-rows that need a guard seen RED

> *A guard never seen red is a guard nobody has met.*
> — `CONTRIBUTING-AI.md`, receipt 3

Four rows of the patch/005 V-list (**V3, V14, V-S2a, V-S2b**) are negative
controls: they do not test that the compiler works, they test that a specific
guard **fails loudly** when the thing it guards is broken. Each therefore needs
a *sabotage rebuild* — a deliberately broken compiler, built, watched go red,
and reverted.

**The harness cannot fire them.** `run_vlist.py` is not authorised to build a
compiler, and a stage3 step is ≈21 minutes on this host. So these rows report
**UNKNOWN with the exact reason**, and the preparation that a later builder
needs is here: one reviewed `.patch` per row, the guard it targets, the red text
to expect, the stop rule, and the revert.

What `run_vlist.py` *does* verify, live, on every pass: that each patch still
applies to the current tree (`git apply --check`). That receipt proves the
recipe is not stale. It is **not** the guard going red, and the rows say so in
their own verdicts.

## Firing one, mechanically

The build must happen in a directory that is **not** `build-p005` and **not**
`build-safe` — a sabotaged binary that overwrites a promoted one is a defect
with a delay timer.

```bash
cd /K3D/GitHub/cgm-zig
ROW=V14                                   # or V3, V-S2a, V-S2b
PATCH=partner_tools/vharness/sabotage/<the .patch for $ROW>

# 0. Machine courtesy, and the pristine checksum you will revert against.
pgrep -fa 'zig build-exe|ninja'           # if a long build owns the host, queue this
git stash list && git status --porcelain  # know what was dirty BEFORE you touch anything
sha256sum <the file the patch touches>    # PRE sha -- write it down

# 1. Apply.
git apply --check "$PATCH" && git apply "$PATCH"

# 2. Build the sabotaged compiler into its own directory.
cmake -B build-sabotage-$ROW \
    -DCMAKE_BUILD_TYPE=ReleaseSafe \
    -DZIG_STATIC_LLVM=OFF \
    -DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions
taskset -c 4-11 ninja -C build-sabotage-$ROW      # ~20 min to zig2 + ~21 min stage3

# 3. Fire the row's command (below) and QUOTE THE RED.

# 4. Revert, and verify the revert by checksum -- "I put it back" is a hope.
git apply -R "$PATCH"
sha256sum <the same file>                 # must equal the PRE sha, byte for byte
```

Then re-run the row through the harness so the receipt lands in the JSON
sidecar:

```bash
python3 partner_tools/vharness/run_vlist.py --only $ROW --zig build-sabotage-$ROW/stage3/bin/zig
```

(The row will still print UNKNOWN — it reports the *prepared* state. The red you
quote from step 3 is the evidence; paste it into the verification document
beside the row.)

---

## V14 — the affinity intersection (R9)

| | |
|---|---|
| **Patch** | `V14_affinity_intersection.patch` |
| **File** | `lib/std/Thread/Topology.zig` |
| **Guard** | the affinity intersection inside `sysTopology`: `if (!maskIsSet(affinity, sib)) continue;` — the one line the file's own comment calls "the finding" |
| **Sabotage** | delete that line, so sibling CPUs outside the mask are counted as members of a core the process cannot use |

**Fire:**

```bash
taskset -c 0-3 build-sabotage-V14/stage3/bin/zig build-obj -fno-emit-bin \
    -Mroot=build-vharness/fixtures/hello/hello.zig 2>&1 | head -1
```

**Expected RED:** the report line says **`6 physical / 4 logical`** — more
physical cores than logical CPUs, which is visibly impossible and is exactly
what makes it a usable control. (The unsabotaged compiler reports
`4 physical / 4 logical` under this pin; measured 2026-08-23, V1 row 3.)

**Stop rule:** if the sabotaged build *still* reports `4 physical / 4 logical`,
the intersection is not what produces the masked answer and V-S1a's seven-mask
agreement is coincidence. Do not proceed on 005a until that is explained.

**Revert check:** `4 physical / 4 logical` returns, and the file's sha256 equals
the PRE sha.

---

## V3 — the process-global partition invariant (R1)

| | |
|---|---|
| **Patch** | `V3_intern_partitions_invariant.patch` |
| **File** | `src/Compilation.zig` (the `buildOutputFromZig` sub-compilation site — the one that builds `compiler_rt`) |
| **Guard** | the named panic in `Zcu.init` (`src/Zcu.zig`), which refuses a partition count smaller than the process-global thread-id pool and reports **both** numbers plus the remedy |
| **Sabotage** | add `.intern_partitions = 2` to that one sub-compilation's options, while the parent derives 8 |

Why this site: thread ids are handed out process-wide and used as direct indices
into whichever `InternPool` is active, so a pool with fewer partitions than the
tid pool can issue is an out-of-bounds read waiting for the first worker handed
a high tid. The default (`options.intern_partitions orelse
Zcu.PerThread.Id.poolLen()`) makes the invariant structural; this row proves the
backstop still bites when someone overrides it.

**Fire** — anything that needs `compiler_rt`:

```bash
build-sabotage-V3/stage3/bin/zig build-exe \
    -Mroot=build-vharness/fixtures/hello/hello.zig -femit-bin=/tmp/v3_hello 2>&1 | head -20
```

**Expected RED:** a panic from `Zcu.init` naming **both** counts, of the shape

```
InternPool: partition count 2 is smaller than the process-global thread-id pool (8 ids).
... Either raise this compilation's partition count or lower `--intern-partitions` for the
whole process; the two are not independently choosable.
```

**Stop rule:** if the compile *succeeds*, the guard did not fire on the exact
condition it was written for, and R1 is unguarded regardless of how the source
reads.

**Revert check:** the same command exits 0, and `src/Compilation.zig`'s sha256
equals the PRE sha.

---

## V-S2a — the `io.concurrent` reservation, forced to 0

| | |
|---|---|
| **Patch** | `VS2a_concurrent_reserve_zero.patch` |
| **File** | `src/main.zig` (`setThreadLimit`) |
| **Guard** | rider 1: `io_impl_ptr.concurrent_reserve = if (@intFromEnum(limit) >= 2) 1 else 0;` — the reserve that keeps one admission slot for the linker's `io.concurrent` |
| **Sabotage** | force the reserve to `0`, i.e. restore the stock predicate |

This is the **A/B arm**, not a crash control: the row asks whether removing the
reserve actually starves the linker, and it is written so that a null result
retracts the claim rather than the mechanism.

**Fire** — three repeats, alternated against the unsabotaged binary:

```bash
python3 partner_tools/vharness/run_vlist.py --only V4 --repeats 3 \
    --zig build-sabotage-VS2a/stage3/bin/zig --ref build-p005/stage3/bin/zig
```

**Expected RED (for the reserve-0 arm):** V4's no-overlap signature — link work
not overlapping analysis — appears **at least once** across the three repeats,
while the shipped reserve=1 binary overlaps in every repeat.

**Stop rule / public correction:** if reserve 0 never starves across three
repeats, **the exposure is overstated and this rider is corrected in public** —
the mechanism is still real, the frequency is not. Say so; do not quietly keep
the claim.

**Note the dependency:** V4's instrument is a machine-readable time report. If
`--time-report-json` is not available on the binaries under test, this row
degrades to UNKNOWN for the same reason V4 does, and the sabotage build buys
nothing until that instrument exists. Check first:

```bash
build-p005/stage3/bin/zig build-obj -fno-emit-bin --time-report \
    --time-report-json /tmp/tr.json -Mroot=build-vharness/fixtures/hello/hello.zig
```

---

## V-S2b — the reservation raised ABOVE `async_limit`

| | |
|---|---|
| **Patch** | `VS2b_reserve_exceeds_async_limit.patch` |
| **File** | `src/main.zig` (`setThreadLimit`) |
| **Guard** | the admission predicate `busy_count + t.concurrent_reserve >= @intFromEnum(t.async_limit)` in `lib/std/Io/Threaded.zig` |
| **Sabotage** | set `concurrent_reserve = @intFromEnum(limit) + 1`, i.e. a reserve larger than the entire async lane |

**Fire:**

```bash
/usr/bin/time -v build-sabotage-VS2b/stage3/bin/zig build-exe \
    -Mroot=build-vharness/fixtures/stdpull/stdpull.zig -femit-bin=/tmp/v2b.bin
```

**Expected RED:** `io.async` admits **nothing**. Every task runs inline on the
caller, observable as a **fully serial compile** — a single busy CPU, and a wall
time close to the sum of the phases rather than their overlap. Compare against
the same command on the unsabotaged binary; a useful quantitative form is
`--only V13-MM --repeats 3` against both, where the sabotaged arm should lose
badly and identically at every `-j`.

**Stop rule:** if the sabotaged binary is *not* materially slower and not
single-threaded, the reserve is not reaching the predicate at all, and rider 1's
shipped `= 1` is equally inert — which would make V-S2a's result meaningless
too.

**Revert check:** wall time returns to the unsabotaged band and `src/main.zig`'s
sha256 equals the PRE sha.

---

## Not here, and why

**V12's own negative control** (deleting the `.acquire`/`release` pair from the
import-discovery tail to prove ThreadSanitizer goes red) has no patch in this
directory. It would be unfireable: TSan does not build in this estate
(`libtsan` needs `linux/scc.h`, an obsolete kernel header Debian no longer
ships, and fabricating the structs whose sizes TSan asserts on is forbidden
here). A sabotage patch for an instrument that cannot be built would be
preparation theatre. The row `V12-P2-NC` reports that by name instead.

---

*Even in the lixão, a flower is born.*
