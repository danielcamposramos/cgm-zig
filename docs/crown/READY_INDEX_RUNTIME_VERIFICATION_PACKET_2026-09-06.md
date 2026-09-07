# Ready-index runtime verification packet — 2026-09-06

Status: **PLAN ONLY; 0 compiler runs in this packet-authoring wave.** Every
runtime row below is UNRUN / UNKNOWN until its required instrument is observed.
Daniel Campos Ramos requested the continuing compiler enhancement. This packet
was prepared by GPT-6 (OpenAI Codex), working as an AI partner; the coordinating
maintainer owns candidate builds, review, promotion and publication.
Upstream-Status: not-filed-policy.

## What this adds to the existing evidence

The seven helper tests exercise the real heap and comparator, but could remain
green if the production `readyPutKey` append hook or `PerThread.update`
invalidation call were removed. A rebuilt compiler needs integration evidence.
The production binary must remain free of shadow scans and test switches.

Source anchors inspected for this packet:

- `src/Zcu.zig:3358-3517`: index wrappers, original scan and file-rank memo.
- `src/Zcu.zig:3538-3579`: functions-first, other tier and semantic dependency
  cycle fallback. Existing `.zcu` debug logs identify actual selections.
- `src/Zcu/PerThread.zig:182`, `:294`, `:324-333`: update invalidation,
  ownership/liveness pass and early abort before updating ZIR references.
- `tools/incr-check.zig:138-246`: one live compiler child per target, binary
  `--listen=-` protocol and repeated update requests. The runner already
  forwards `--debug-log` and tags captured stderr by update.
- `test/tests.zig:2914`: the existing runner build/invocation recipe.
- `partner_tools/vharness/rows_005c.py`: V8 checks the ranking announcement and
  records cost; it does not compare picks. V9 checks **module graph** cycles,
  not the semantic no-ready dependency-cycle branch. Neither closes these rows.

The production hashes at preparation are Zcu
`d9e93263637ae4bde3c433df20ad4a3de35aa2a35d4334a84d1ca9a0b6fb6709`,
PerThread `0dd3bebfef5820e436f5dc53e9aa5110378ea03bc3481a901f56d02de3c325b8`,
and ReadyIndex `ea0f1fd7852b79fc2711d43b1aa0650a832e0a6b966086bc69830a8f524070ea`.
The coordinator subsequently formatted only the sibling test; its current hash
is `2527467d547d052ab10c904f885f84dfc50efa804f938ebb6abcbbb6a768715e`.
The earlier sealed receipt retains its historical pre-format test hash.

## 1. Reuse the runner and five existing fixtures

Do not write a second incremental protocol implementation. Build the existing
small `incr-check` executable directly with the promoted compiler; it accepts
an explicit candidate path and does not require rebuilding the compiler under
test. Always pass `--preserve-tmp`: otherwise the runner deletes its scratch
tree on exit. Run it from a repo-local `build-*` working directory. These five
fixtures have no `#rm_file` directives.

Create scratch fixture copies with `apply_patch`, retaining the complete update
bodies and expectations. Retain **only** the first active
`#target=x86_64-linux-selfhosted` directive; comment the other active target
directives. Do not edit `test/incremental/` itself. This bounds execution to one
native target without weakening diagnostic or stdout expectations.

| Fixture | Updates / target | Intended discriminator, not an assumed reach claim |
| --- | ---: | --- |
| `change_module` | 4 | Same `other.zig` changes ownership foo -> root, then double ownership abort, then no ownership; compile-log module names are existing independent expectations |
| `type_dependency_loop` | 5 | Semantic type dependency error, removal of demand, changed cycle, renewed demand, repair |
| `temporary_parse_error` | 3 | Successful update -> parse-error abort -> successful recovery in one child |
| `analysis_error_and_syntax_error` | 6 | Semantic error survives alternating parse-error aborts, then successful recovery |
| `add_remove_struct_fields` | 4 | Real function, nav/type and struct-default dependency mutations, including invalid field recovery |

Total: **22 planned updates per order / 44 planned updates for two orders**, not
44 successful compilations: some updates deliberately expect diagnostics.
Record the runner's exact matched expectations, executable stdout and exit
status. A sema-only target can be an initial cheaper triage arm, but ignores
stdout execution expectations (`incr-check.zig:452`) and cannot replace this
native-target row.

The runner does not accept arbitrary compiler arguments. Create this small
repo-local executable wrapper via `apply_patch` at
`build-ready-runtime/zig-under-test` (then `chmod +x` that exact file):

```sh
#!/bin/sh
exec "${READY_INDEX_CANDIDATE:?set the recorded absolute binary path}" "$@" \
    "--analysis-order=${READY_INDEX_ORDER:?set insertion or layered}" \
    -j1 --intern-partitions=2
```

This preserves the runner's IPC arguments and selects a deterministic serial
configuration for sequence comparisons. It is not a shipping option, station
repoint, or a test of wide-worker scheduling. An omitted/default mode control
uses a sibling scratch wrapper with only the analysis-order argument omitted.
Record each wrapper's bytes and SHA; no silent fallback to another compiler.

Exact commands after the fixture copies and wrapper exist:

```sh
cd /K3D/GitHub/cgm-zig
export ZIG_GLOBAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/gcache
export ZIG_LOCAL_CACHE_DIR=/K3D/GitHub/cgm-zig/build-ready-runtime/tool-cache
export ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
PROMOTED/zig build-exe tools/incr-check.zig -OReleaseSafe \
    -femit-bin=build-ready-runtime/incr-check

cd /K3D/GitHub/cgm-zig/build-ready-runtime
for READY_INDEX_ORDER in insertion layered; do
    export READY_INDEX_ORDER
    for ready_fixture in change_module type_dependency_loop temporary_parse_error analysis_error_and_syntax_error add_remove_struct_fields; do
        /usr/bin/time -v -o "${READY_INDEX_ORDER}-${ready_fixture}.time" \
            ./incr-check ./zig-under-test "fixtures/${ready_fixture}" \
            --zig-lib-dir /K3D/GitHub/cgm-zig/lib --preserve-tmp \
            --debug-log zcu --debug-log zcu_deps \
            > "${READY_INDEX_ORDER}-${ready_fixture}.stdout" \
            2> "${READY_INDEX_ORDER}-${ready_fixture}.stderr"
        ready_rc=$?
        printf '%s %s rc=%s\n' "$READY_INDEX_ORDER" "$ready_fixture" "$ready_rc"
        if [ "$ready_rc" -ne 0 ]; then exit "$ready_rc"; fi
    done
done
```

Set/export `READY_INDEX_CANDIDATE` to the coordinator's recorded absolute
candidate path before this block. Record its resolved path, version, SHA,
source manifest and generated build command, plus the wrapper hash. A logging
candidate requires `-Dlog` **as well as** ReleaseSafe and debug extensions.
Reject the warning that `--debug-log has no effect`. Zero selection lines is
UNKNOWN reach, not proof of zero disagreements. The runner creates a fresh
`tmp_*` directory and explicit `.local-cache`/`.global-cache` below it per
invocation, while updates within that invocation share the live process/state.

Use `vlib.run_cmd`/`Verdict` to retain full rc/signal/timeout/stdout/stderr and
`oracle_lib.sha256_file`/`assert_anchor` for manifests and patch anchors. If a
small result driver is authored later, it must consume these same commands;
no rewrite of the fixture evaluator. `oracle_lib`'s shell/Python write helpers
do not override the manual-`apply_patch` constraint for raw source.

## 2. Scratch shadow assertion compiler: exact core patch

Existing logs show the selected unit but cannot show what the original scan
would have selected from the same live map at that instant. Build one isolated
shadow compiler from the exact candidate source manifest, with the following
scratch-only instrumentation. Do not instrument production or share writable
hardlinks with it. Use repo-local copies with independent inodes; retain all
artifacts. Do not use `git archive HEAD` as the sole copy source while the
candidate has uncommitted new files: that would silently omit this wave.

Assert each source anchor occurs exactly once before applying these edits.
Replace the successful prepare branch in scratch `Zcu.readyPick`:

```zig
if (index.prepare(zcu.gpa, keys.len, Context{ .owner = zcu, .items = keys }, Context.rank)) {
    const chosen = index.peek().?;
    const scanned = zcu.readyPickScan(keys);
    log.debug("READY_SHADOW tier={s} n={d} chosen={d} scan={d}", .{
        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, chosen, scanned,
    });
    if (chosen != scanned) @panic("READY_SHADOW selection mismatch");
    return chosen;
}
log.debug("READY_FALLBACK tier={s} n={d}", .{
    @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len,
});
return zcu.readyPickScan(keys);
```

Do not change the original scan. These extra scans are oracle overhead, not a
shipping optimization or a timing sample. Every `READY_SHADOW` record must
have equal selected and scanned **map indexes**, not merely equal ranks or
names; this detects current-map tie mistakes. The comparison is inside the
same process/map state and does not depend on cross-process InternPool IDs.

In scratch `PerThread.update`, surround the existing invalidation call with:

```zig
const audit_memo_before = zcu.file_rank_memo.count();
std.log.scoped(.zcu).debug("READY_EPOCH before_memo={d} funcs_active={} other_active={}", .{
    audit_memo_before, zcu.ready_indexes.funcs.isActive(), zcu.ready_indexes.other.isActive(),
});
zcu.invalidateReadyRanks();
if (zcu.analysis_order == .layered) {
    if (zcu.file_rank_memo.count() != 0 or
        zcu.ready_indexes.funcs.state != .invalid or
        zcu.ready_indexes.other.state != .invalid)
        @panic("READY_EPOCH invalidation missing");
}
std.log.scoped(.zcu).debug("READY_EPOCH reset_checked before_memo={d}", .{audit_memo_before});
```

Emit `READY_ABORT` immediately inside the existing early-abort branch before
`skip_analysis_this_update = true`. The runner's update labels distinguish a
compile-error result from process termination; a returned parse-error update
followed by successful recovery is required. Existing `change_module`
compile-log expectations independently witness foo -> root ownership, while
the reset check must be **armed with nonzero before_memo** on a later update.
Deleting an already-no-op invalidation call on an empty initial epoch proves
nothing, even if the fixture compiles.

### Required small reach checks around real wrappers

Add these only to the same scratch overlay; they must not manufacture ready
members or call wrappers merely to obtain coverage. Emit records before any
assertion so a failure identifies the path. No logging counter belongs in the
production helper. A future patch must preserve these exact placements:

1. In `readyPutKey`, capture `was_active` and old map count **outside** the
   `readyKeyAppended` call. After the original put/append block, log
   `READY_PUT active_before={} active_after={} old={} new={}`. If it was active, the count
   grew, and the index remains active, assert its two lengths equal the map
   count. Count active-growing normal puts separately from duplicate puts.
2. In `readyPutAssumeCapacityNoClobber`, use the same before/after check in
   both branches, record `READY_NOCLOBBER` and the unit tag. In PerThread's
   external struct-defaults call site, additionally log
   `READY_EXTERNAL_STRUCT_DEFAULTS`; a generic type-layout log is not this
   integration path. Preserve all authoritative capacity reservations.
3. In `readySwapRemoveKey`, log old map index, old count and active status
   before mutation; after removal, check both index lengths and every live
   node's reverse position. Record non-last removal separately. Do not
   require heap-node indexes to match map indexes; only their reverse mapping.
4. At each function/other branch in `findOutdatedToAnalyze`, emit
   `READY_TIER funcs={d} other={d} selected=func|other`; assert other selections
   have zero ready funcs. A positive funcs-first witness needs **both counts
   nonzero** at a function selection, not just one function selected sometime.
5. At the existing `dependency loop affecting ...` fallback, emit
   `READY_CYCLE funcs={d} other={d} outdated={d}` and assert both ready counts
   zero and outdated nonzero. Preserve `outdated.keys()[0]` exactly. A type
   cycle diagnostic alone is not evidence that this branch was reached.
6. At update exit (`defer`, including aborts) under insertion, assert both
   indexes' node and position **capacities**, not just lengths, are zero and
   the rank memo is empty; emit `READY_DEFAULT_EMPTY`. Also emit an entry
   marker in `ReadyIndex.prepare` and `.append` in the scratch copy. Default
   tests require no entry markers, with nonzero update/selection coverage.

The indexed branch, wrapper, epoch and tier records form one finite integration
coverage table. Log parsing may group runner update labels, but must not strip
raw stderr. Existing `fmtAnalUnit` prints unstable numeric IDs; when comparing
the clean candidate and shadow's selected-unit logs across processes, retain
raw output and normalize only those bracketed IDs and recorded scratch-root
prefixes. Do not compare insertion's sequence to layered's sequence: their
ordering difference is intentional. Cross-process agreement is supplementary;
the same-state shadow assertion is the primary ordering oracle.

## 3. PRE -> negatives -> restored, with armed denominators

Run the candidate's 44 planned update cases, then the clean shadow on the same
44 cases. Before building a mutant, require its target reach row below to have
a positive count. If absent, report that row UNKNOWN and stop that mutant's
queue; do not call a never-reached mutation a passing control. This is a finite
fixture set, not an open-ended workload search.

| Control | Exact scratch mutation | Required clean witness | Required RED |
| --- | --- | --- | --- |
| Selection checker self-control | In indexed branch change `if (chosen != scanned)` to `if (chosen == scanned)` | At least one successful indexed pick | Named `READY_SHADOW selection mismatch`, nonzero process/runner exit |
| Lost ordinary append hook | Remove only `if (map.count() != old_count) zcu.readyKeyAppended(key);` from scratch `readyPutKey` | `READY_PUT` active-before, active-after and old+1=new at least once | Length assertion or subsequent production prepare assertion / selection mismatch; retain target path record |
| Lost update invalidation | Remove only `zcu.invalidateReadyRanks();` from scratch PerThread, leave independent before/after checker | Later update with `before_memo > 0`, plus actual ownership-change and abort/recovery labels in the clean run | `READY_EPOCH invalidation missing`, not an unrelated expected compile error |
| Default entry tripwire | Replace scratch helper prepare/append entry markers with named panics | Insertion update/selection markers positive | Layered run must fire; omitted/default and explicit insertion must still pass without entry |

The self-control is a check of the measurement, not a substitute for the two
lost-hook controls. Report each negative as its own numerator/denominator.
After each mutation restore with `apply_patch`, verify the exact clean-shadow
source SHA, and rerun the rebuilt restored-shadow binary on the same targeted
fixture/order. Merely restoring source while executing the mutant binary is
not restoration. Every binary has a distinct output path and manifest; no
promoted path is reused. The earlier helper-only tie-repair negative remains
valid but does not discharge these production-wrapper controls.

## 4. Optional-index OOM: narrow injection, not global memory starvation

The four helper allocation-failure arms are already evidenced. The minimal
additional integration arm is a separate scratch shadow variant which changes
**only the allocator argument at the real `index.prepare` call**:

```zig
var audit_empty_storage: [0]u8 = .{};
var audit_fba = std.heap.FixedBufferAllocator.init(&audit_empty_storage);
// At the existing call, replace zcu.gpa with audit_fba.allocator().
```

Use a fresh compiler process so index capacity starts at zero; require a
nonempty ready set, an invalid index before prepare, and a disabled index after
the attempt. Emit those facts plus `READY_FALLBACK`, not just a selected-unit
log. The zero-capacity allocator forces a real optional allocation failure
without starving unrelated compiler work. Compare the runner expectations and
selected sequence with the clean shadow's same-state old scan; the integration
claim is **preparation OOM fallback**, not append OOM or global OOM recovery.
To test the fallback oracle negatively, scratch-replace the fallback return
with a named panic; the armed forced-OOM run must then fail by that name.
Restore source and verify/rebuild/rerun as above.

Real production-wrapper append-OOM reach remains UNKNOWN until a separately
instrumented active-growing append is forced through an actually exhausted
optional allocator. Do not repurpose `zcu.gpa`, use an OS memory limit, or call
a forced `disable()` an allocation-failure test. Default zero-index capacity
and zero helper-entry observations do not establish zero total compiler
allocation; the claim is scoped to the two auxiliary indexes and rank memo.

## 5. Acceptance, cost and stopping boundary

For each candidate/shadow arm report actual matched fixture updates out of the
planned 22/order, checker comparisons with their total selected units, armed
normal/no-clobber/external/removal counts, ownership epochs, abort/recovery
updates, both-tiers-ready selections, semantic-cycle fallback hits and optional
OOM hits. Missing any required instrument yields a named UNKNOWN row, never
zero mismatches treated as green. Existing fixtures are intended witnesses,
not a claim that all internal paths have already been reached.

A complete integration result needs positive real wrapper/tier/cycle reach,
zero same-state selection disagreements over a stated nonzero denominator,
both-mode fixture expectations, armed negatives red, and checksum-restored
reruns green. Semantic-cycle fallback and external struct-defaults insertion
may remain unreached by this bounded suite; if so, record the precise gap and
stop for a focused next fixture decision, not a module-graph-cycle substitute.

Machine courtesy precedes every compiler build and test batch. The runner is
one small tool build; candidate tests are small incremental compilations.
Shadow variants require real compiler codegen/link passes and cannot be priced
as the earlier ~40-second Sema-only check. Actual wall/RSS are UNKNOWN until
measured. Reuse the coordinator's generated ReleaseSafe/debug-extensions/log
build command, changing only validated source/output/cache roots for each
shadow; inspect `ninja -t commands`/config before execution. The existing
BUILDING receipt's ~8-41 minute whole-build range depends strongly on mask and
contention and is not a guaranteed duration for these incremental rebuilds.
All variants run sequentially, no rebuild during another long build, and no
shadow timing is published as optimization speedup. One clean shadow, the
armed targeted mutants, and checksum-restored rebuilds form a finite queue;
do not build unreached mutants speculatively.

This authoring wave read laws, oracle conventions/library, the harness rows,
runner/parser, five fixtures and relevant compiler source; it ran read-only
`rg`, `sed`, `sha256sum` and `git diff --check`. It authored only this packet.
No fixture copy, wrapper, instrumentation, tool build, compiler build, test,
git mutation, promotion or publication was executed here. No production source,
existing fixture or sealed prior receipt was edited.
