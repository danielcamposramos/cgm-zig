# Real preparation-OOM fallback — scratch control packet, 2026-09-07

**PREPARATION ONLY.** Source materializations 0; compiler builds/runs 0. All new
OOM, negative and restored-runtime outcomes are UNRUN / UNKNOWN. This document
is a proposal for root review, not authority to execute it while another compiler
occupies the build lane.

Direction: Daniel Campos Ramos. Prepared by a cooperating OpenAI Codex senior
partner, continuing the original GPT-6 runtime packet's authorship and root's
execution discipline. Upstream-Status: not-filed-policy. The complete
[governing packet](READY_INDEX_RUNTIME_VERIFICATION_PACKET_2026-09-06.md),
including section 4, was read. Reuse its existing repaired runner, native fixture,
wrapper, original scan and complete-path manifest convention; no new scheduler,
fixture or IPC evaluator is proposed.

## 1. Smallest existing armed fixture and exact scope

Use only `build-ready-runtime/fixtures/temporary_parse_error`, the minimum
three-update fixture in the already bounded five-fixture set. Its single active
target is `x86_64-linux-selfhosted`; it has no `#rm_file`. The ordered outcomes
are `initial version` (empty stdout), `introduce parse error` (the exact existing
EOF diagnostic), and `fix parse error` (empty stdout). No expectation is weakened.

The existing
[layered clean stderr](../../build-ready-runtime/shadow-clean-v2-layered-temporary_parse_error.stderr)
was independently streamed and selected context read. It has:

| Actual existing clean witness | Count / scope |
| --- | --- |
| Fixture update labels | 3/3, lines 2, 345683, 346238 |
| Invalid prepare with both capacities zero | 2/2,083 prepare entries, lines 98741 and 101935 |
| First eligible allocation attempt | count=2, state=invalid, both capacities=0; other tier |
| Same-live-state comparisons | 2,083/2,083 equal |
| Helper append entries | 9,447 |
| Optional-index fallback records | 0; no existing OOM evidence |
| Parse-error abort | 1, line 346236; followed by the recovery update |
| Ordinary selection records | 3,025 = 2,083 fixture + 942 insertion-mode compiler_rt |

The broader `findOutdatedToAnalyze:` prefix count is 3,028, including three
`all up-to-date` notices; these are not selections. Semantic-cycle selections
in this fixture are 0. The existing time file and V2 execution row both say
exit 0. Those historical traces used the old runner: they arm the compiler path
but retain that runner's completeness ceiling. Future runs must use the repaired
runner `runner-completeness/bin/repaired-restored`, not rebuild or replace it.
A fresh baseline run with that runner is included below.

This arm forces **the first nodes-array preparation allocation** only. It does
not exercise the second preparation allocation, active-index append OOM,
file-rank-memo OOM, global/compiler OOM, or wider-worker behavior. The existing
helper tests separately cover two preparation and two append allocation-failure
arms; their direct helper evidence is not integration evidence.

## 2. Why this is a real allocation failure, and the observer amendment

Frozen `src/Zcu/ReadyIndex.zig:53–94` checks state first, then reserves nodes,
then positions, then calls the rank callback. A nodes reservation error invokes
the unchanged `disable()`, which clears lengths and sets `.disabled`.
Disabled calls return false without retry; only normal epoch invalidation
permits another attempt. `array_list.zig:1209–1240` must request capacity for
a nonempty array of nonzero-sized nodes. The existing zero-length
`FixedBufferAllocator` cannot satisfy that request and returns allocation
failure. No global allocator, OS memory limit, synthetic ready member or direct
test call to `disable()` is involved.

Only the allocator argument of the real `index.prepare` call is substituted.
A precondition observer rejects an active index or any retained capacity before
using that allocator, preventing accidental allocator-ownership mixing. With
a fresh process and zero storage, no allocation can succeed or escape the local
allocator lifetime. Unrelated compiler and rank-memo allocations keep `zcu.gpa`.
The first failed reservation occurs before the rank callback.

The frozen observer is semantically valid on the disabled fallback:
`readyAuditIndex` returns for inactive indexes; append hooks likewise skip
inactive indexes; swap-removal's helper returns without touching its arrays.
The existing epoch checker invalidates disabled state normally. No observer
must be relaxed or removed.

There is nevertheless an **observational gap**: `READY_SHADOW` compares only
the successful-prepare branch. A forced-OOM run must not claim that zero such
records are zero-disagreement evidence. The following scratch-only amendments
are proposed explicitly, not silently substituted for that checker:

- In `Zcu.zig`, log preparation before/after facts and retain the entire existing
  indexed comparison branch. After the existing `READY_FALLBACK`, call the
  unchanged original scan exactly once, log its returned map index, and return it.
  This is a return-value observation, not a second scan or independent comparator.
- In `Zcu/ReadyIndex.zig`, add one log inside the **existing first allocation
  failure catch**, before the existing disable/return. This is the direct
  allocation-failure witness; disabled state alone would not distinguish OOM
  from transient rank failure.

These two scratch owners require root's later source grant. No PerThread,
allocator implementation, production owner or shipping knob changes are proposed.

## 3. Exact future source packets

Future root: `/K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/`.
It did not exist when checked. Refuse an existing/conflicting destination; never
overwrite another control tree. Materialize one independent-inode copy of the
frozen `build-ready-shadow-2026-09-06/source/` only after disk and process checks.
Never hardlink. All paths below target that future copy, not frozen/production.

### A — injection plus the explicitly named observations

Use native `apply_patch` with this exact packet, not a shell rewrite:

```text
*** Begin Patch
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu.zig
@@
     const index = zcu.readyIndexForKey(@typeInfo(@TypeOf(keys)).pointer.child);
-    if (index.prepare(zcu.gpa, keys.len, Context{ .owner = zcu, .items = keys }, Context.rank)) {
+    const audit_state_before = index.state;
+    log.debug("READY_PREPARE_OOM_BEFORE tier={s} n={d} state={t} nodes_capacity={d} positions_capacity={d}", .{
+        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_state_before, index.nodes.capacity, index.positions.capacity,
+    });
+    if (keys.len == 0 or index.isActive() or index.nodes.capacity != 0 or index.positions.capacity != 0)
+        @panic("READY_PREPARE_OOM invalid precondition");
+    var audit_empty_storage: [0]u8 = .{};
+    var audit_fba = std.heap.FixedBufferAllocator.init(&audit_empty_storage);
+    const audit_prepared = index.prepare(audit_fba.allocator(), keys.len, Context{ .owner = zcu, .items = keys }, Context.rank);
+    log.debug("READY_PREPARE_OOM_AFTER tier={s} n={d} before={t} after={t} prepared={} nodes_len={d} positions_len={d} nodes_capacity={d} positions_capacity={d} allocator_used={d}", .{
+        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_state_before, index.state, audit_prepared,
+        index.nodes.items.len, index.positions.items.len, index.nodes.capacity, index.positions.capacity, audit_fba.end_index,
+    });
+    if (audit_prepared or index.state != .disabled or index.nodes.items.len != 0 or index.positions.items.len != 0 or
+        index.nodes.capacity != 0 or index.positions.capacity != 0 or audit_fba.end_index != 0)
+        @panic("READY_PREPARE_OOM invalid disabled state");
+    if (audit_prepared) {
@@
     log.debug("READY_FALLBACK tier={s} n={d}", .{
         @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len,
     });
-    return zcu.readyPickScan(keys);
+    const audit_scanned = zcu.readyPickScan(keys);
+    log.debug("READY_OOM_SCAN tier={s} n={d} scan={d}", .{
+        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_scanned,
+    });
+    return audit_scanned;
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu/ReadyIndex.zig
@@
             self.nodes.ensureTotalCapacity(gpa, count) catch {
+                std.log.scoped(.zcu).debug("READY_PREPARE_OOM_NODES_FAILURE count={d} state={t} nodes_capacity={d} positions_capacity={d}", .{
+                    count, self.state, self.nodes.capacity, self.positions.capacity,
+                });
                 self.disable();
*** End Patch
```

### B — armed negative on the actual fallback return

Apply only after A has built and passed with the full witness chain below.
This changes exactly one return to a named panic; it leaves allocator failure,
the original scan call and its before-panic record intact. The panic is the
terminal statement in that path, so no void-thunk accommodation is needed.

```text
*** Begin Patch
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu.zig
@@
     log.debug("READY_OOM_SCAN tier={s} n={d} scan={d}", .{
         @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_scanned,
     });
-    return audit_scanned;
+    @panic("READY_PREPARE_OOM fallback tripwire");
*** End Patch
```

### B inverse — restore the forced-OOM path before rebuilding it

```text
*** Begin Patch
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu.zig
@@
     log.debug("READY_OOM_SCAN tier={s} n={d} scan={d}", .{
         @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_scanned,
     });
-    @panic("READY_PREPARE_OOM fallback tripwire");
+    return audit_scanned;
*** End Patch
```

### A inverse — restore every proposed owner to the frozen clean bytes

Apply only after B inverse has been rebuilt and rerun while OOM remains armed.

```text
*** Begin Patch
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu.zig
@@
     const index = zcu.readyIndexForKey(@typeInfo(@TypeOf(keys)).pointer.child);
-    const audit_state_before = index.state;
-    log.debug("READY_PREPARE_OOM_BEFORE tier={s} n={d} state={t} nodes_capacity={d} positions_capacity={d}", .{
-        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_state_before, index.nodes.capacity, index.positions.capacity,
-    });
-    if (keys.len == 0 or index.isActive() or index.nodes.capacity != 0 or index.positions.capacity != 0)
-        @panic("READY_PREPARE_OOM invalid precondition");
-    var audit_empty_storage: [0]u8 = .{};
-    var audit_fba = std.heap.FixedBufferAllocator.init(&audit_empty_storage);
-    const audit_prepared = index.prepare(audit_fba.allocator(), keys.len, Context{ .owner = zcu, .items = keys }, Context.rank);
-    log.debug("READY_PREPARE_OOM_AFTER tier={s} n={d} before={t} after={t} prepared={} nodes_len={d} positions_len={d} nodes_capacity={d} positions_capacity={d} allocator_used={d}", .{
-        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_state_before, index.state, audit_prepared,
-        index.nodes.items.len, index.positions.items.len, index.nodes.capacity, index.positions.capacity, audit_fba.end_index,
-    });
-    if (audit_prepared or index.state != .disabled or index.nodes.items.len != 0 or index.positions.items.len != 0 or
-        index.nodes.capacity != 0 or index.positions.capacity != 0 or audit_fba.end_index != 0)
-        @panic("READY_PREPARE_OOM invalid disabled state");
-    if (audit_prepared) {
+    if (index.prepare(zcu.gpa, keys.len, Context{ .owner = zcu, .items = keys }, Context.rank)) {
@@
     log.debug("READY_FALLBACK tier={s} n={d}", .{
         @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len,
     });
-    const audit_scanned = zcu.readyPickScan(keys);
-    log.debug("READY_OOM_SCAN tier={s} n={d} scan={d}", .{
-        @typeName(@typeInfo(@TypeOf(keys)).pointer.child), keys.len, audit_scanned,
-    });
-    return audit_scanned;
+    return zcu.readyPickScan(keys);
*** Update File: /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom/source/src/Zcu/ReadyIndex.zig
@@
             self.nodes.ensureTotalCapacity(gpa, count) catch {
-                std.log.scoped(.zcu).debug("READY_PREPARE_OOM_NODES_FAILURE count={d} state={t} nodes_capacity={d} positions_capacity={d}", .{
-                    count, self.state, self.nodes.capacity, self.positions.capacity,
-                });
                 self.disable();
*** End Patch
```

The three A anchors and one B anchor were checked once each in memory against
the actual full frozen owners. Both inverse transformations recover their exact
input bytes. The following are **virtual proposed-source** hashes, not hashes
of materialized or compiled variants:

| Owner | Clean / A inverse | A / B inverse | B |
| --- | --- | --- | --- |
| src/Zcu.zig | `852dbc99c87543ff7d752e9aeae03119c33494b4d0037905d4fe2f88ec8c9d4e` | `98634dbfb2590d4f907f2899d63bcd74655739293d0a9dad7ce213f4ed9b0f92` | `29c02dd34b11f23c59dadb08ee0b1341cc892cfe6f97784e8b90afbd1f061c1f` |
| src/Zcu/ReadyIndex.zig | `ea21a609b71076d59ebc8268f46418e42233475f19f15a6a61b859ff21708e23` | `5b52293ba2333056b7ecf823c1531d8a9adcfe7d119df8003311ecc1e0802e58` | same as A |

A has three hunks across two owners; B and its inverse each change one line in
one owner. No parse, formatting or type-check result exists for these proposed
bytes. Any later necessary formatting must be reviewed and resealed explicitly,
not silently accepted against these hashes.

## 4. Finite execution order and acceptance

| Phase | Source / binary | Required result |
| --- | --- | --- |
| baseline | Existing sealed clean shadow; fresh repaired-runner invocation | 3/3 outcomes, positive indexed comparisons |
| injected | A; new `injected-stage3` | 3/3 outcomes, real preparation OOM followed by original-scan fallback |
| tripwire | A+B; new `tripwire-stage3` | Named panic below, compiler abnormal termination and runner nonzero |
| injection-restored | B inverse; new `injection-restored-stage3` | 3/3 outcomes with OOM still armed; exact A source hashes |
| clean-restored | A inverse; new `clean-restored-stage3` | Full clean bank, separate rebuild, 3/3 outcomes and positive indexed comparisons |

This is four deferred whole-compiler builds and five runner invocations, not a
helper-test budget. The four GREEN arms would cover 12 expected updates; the
negative reaches only as far as its actual panic and must not be credited with
three completed updates. Whole-build time/RSS and every new dynamic count are
UNKNOWN. The negative cannot be discharged by a source-only reverse or by an
unarmed clean run: the B-inverse rebuild must prove fallback recovery with A
still present. The final clean rebuild separately restores the full authority.

For injected and injection-restored, require at least one complete ordered
chain in one real layered `readyPick`:

1. `READY_PREPARE_OOM_BEFORE`: n>0, state=invalid, both capacities zero.
2. Existing `READY_ENTRY prepare`, then `READY_PREPARE_OOM_NODES_FAILURE`
   from the actual catch, with matching count and invalid/zero-capacity state.
3. `READY_PREPARE_OOM_AFTER`: before=invalid, after=disabled, prepared=false;
   both lengths/capacities and allocator_used zero.
4. Existing `READY_FALLBACK`, then `READY_OOM_SCAN`, then the existing
   real selected-unit log. Every returned scan index must be less than n.

Reconcile every BEFORE/AFTER pair by tier and update. Disabled-state subsequent
calls must produce no nodes-failure catch marker until a normal epoch reset.
Report invalid attempts, actual failure-catch records, disabled returns and
fallback/scan returns separately; do not count every disabled return as a new
allocation failure. The parse-error update must still return its expected
diagnostic, and its subsequent success must execute in the same child.

The tripwire must show steps 1–4 through `READY_OOM_SCAN`, then exactly
`READY_PREPARE_OOM fallback tripwire`. A precondition panic, unexpected disabled
state, generic crash, compiler build failure or timeout is **not** the intended
RED. It should stop in the first fixture update at the first real forced fallback;
actual label/count must be retained rather than assumed.

Keep clean baseline `READY_SHADOW` comparisons as same-live-state evidence.
Compare its ordered (tier,n,scan) projection with A's `READY_OOM_SCAN` records
and the selected-unit sequence by update. Also compare B-inverse to A and final
clean to baseline. Cross-process comparisons are supplementary: they are not a
same-live-map comparison and may not silently normalize a discrepancy away.
Use existing anchored logs; exclude `all up-to-date` from selection counts and
record semantic-cycle selections separately. Retain raw stderr. Normalize only
the exact recorded source/scratch-root prefixes and space-prefixed bracketed
numeric InternPool IDs, never names, instruction numbers, ordering or outcomes.
If cache/identity drift prevents agreement, report it and stop for review;
passing expected outcomes alone does not close the sequence row.

Structural observer checks remain conditional on active state and will be
unarmed in A; unchanged source plus clean baseline/restored reach is their
evidence, not invented active-index OOM coverage.

## 5. Inputs, full-path manifest and future commands

The frozen bank was independently checked at 21,931/21,931 hashes during this
packet authoring. Its SHA-256 is
`5a34e9da152645b2da9f69c1af8b79bed9be0be0b304fe956b681a24ea678e44`;
the complete canonical clean relative-path digest is
`a1647d5717228e98679ed566acc17da3474303c5e8b177801cf8026a8b130832`
as recorded in the corrected preparation convention. Reuse the
[full-path verifier](../../build-ready-shadow-2026-09-06/remaining-controls/README.md):
read checksum bytes 1–64, require the two-space separator, retain the complete
path from byte 67 onward. No `$2` path extraction. For A/B, override exactly
the two owner hashes above (each anchor once), leaving 21,929 other bank entries
unchanged; verify all 21,931 hashes, exact path set and independent inode pairs.
B inverse must match all A hashes; final A inverse must match the full clean bank.
Canonical complete lists are 21,931 rows / 2,444,976 bytes, sorted by complete
relative path. Seal the actual materialized manifests before each build.

Rechecked current input SHA-256 values:

```text
01d3b88dad37d11bcdcafe815095d5545d2cdd4af6ad467fc365d227ed43d1b2  build-ready-shadow-2026-09-06/clean-stage3/bin/zig
046d6833e17c32856223572bdab65ce24e98cda3df8f8156ae700022e79dcb11  PROMOTED/zig
a5bd5321ba297aaa4099b96b3d2d9b1831af4e5e0d9b695d15cc7ef38c922678  build-release-2026-09-06/config.h
a19e41135d40ac2b74e0e9cbcfa429cc711e2858fb0fb07bc2a80514f39a1676  build-release-2026-09-06/zigcpp/libzigcpp.a
783e15c02022f6315cdea9be4a16275ccb39eef974df91e51d67f6221c3551d5  build-p005/vwork/libc.txt
b9745d6a60c46a7f93bf64ad8f033c9d3e3781fc52331ac1fece882fe1897a87  build-ready-runtime/runner-completeness/bin/repaired-restored
77b0d3adc3fb3b1ecf7973605519f745f5b871fa05226af731776abd1dcdf027  build-ready-runtime/zig-under-test
f7a3e2fe43b88dcb117a04b0380ca4b04b630572ed00f9d768e9c76efe2e0fa5  build-ready-runtime/fixtures/temporary_parse_error
589a4a12f9ad31b31197d269b876cc8cf29b69fa4acb639a7ef322203469aa43  build-ready-runtime/shadow-clean-v2-layered-temporary_parse_error.stderr
da3cf9963acc7d419011144c645b9ebc616f199d7540db2c81fac73136d26df3  build-ready-runtime/shadow-clean-v2-layered-temporary_parse_error.time
6547e5a35012cced854783124da8a7ea45b87d161c8567088d91af410de8b68b  build-ready-shadow-2026-09-06/audit/clean-runtime-executions-v2.json
```

Before **each** future build, seal resolved PROMOTED, config, actual
`zigcpp/libzigcpp.a` and libc descriptor again; these current readings are not
future pre-build seals. Preserve full options/command, source bank, binary
hash/version and logs. Baseline CPU and system LLVM do not imply portability.
Runtime receipts must directly record explicit candidate/order/libc overrides,
rather than require later launcher transcription; distinguish supplied overrides
from a separately captured child argv/environment if that capture is absent.

The following commands are future root execution only. No automatic phase loop:
verify the source and preceding result before choosing the next phase. Use new,
distinct cache/prefix/log roots and refuse existing outputs. No evidence deletion.

```sh
cd /K3D/GitHub/cgm-zig
oom_root=/K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/prepare-oom
oom_phase=injected
case "$oom_phase" in injected|tripwire|injection-restored|clean-restored) ;; *) exit 2 ;; esac
df -h /K3D/GitHub/cgm-zig
ps -eo pid,ppid,etime,pcpu,rss,args
# STOP if any other whole compiler build is running, or headroom is insufficient.
for oom_output in "$oom_root/$oom_phase-stage3" "$oom_root/$oom_phase-build-cache" "$oom_root/$oom_phase-global-cache" "$oom_root/$oom_phase-logs"; do
    if [ -e "$oom_output" ] || [ -L "$oom_output" ]; then exit 2; fi
done
mkdir "$oom_root/$oom_phase-logs" || exit 2
export ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
export ZIG_LOCAL_CACHE_DIR="$oom_root/$oom_phase-build-cache"
export ZIG_GLOBAL_CACHE_DIR="$oom_root/$oom_phase-global-cache"
cd "$oom_root/source"
/usr/bin/time -v -o "$oom_root/$oom_phase-logs/build.time" \
    /K3D/GitHub/cgm-zig/PROMOTED/zig build \
    --prefix "$oom_root/$oom_phase-stage3" --zig-lib-dir "$oom_root/source/lib" \
    "-Dversion-string=0.16.0+cgm.0399d2b19b.shadow-prepare-oom-$oom_phase" \
    -Dtarget=native -Dcpu=baseline -Denable-llvm \
    -Dconfig_h=/K3D/GitHub/cgm-zig/build-release-2026-09-06/config.h \
    -Dno-langref -Ddebug-extensions -Dlog -Doptimize=ReleaseSafe \
    > "$oom_root/$oom_phase-logs/build.stdout" \
    2> "$oom_root/$oom_phase-logs/build.stderr"
oom_rc=$?
printf '%s\n' "$oom_rc"
if [ "$oom_rc" -ne 0 ]; then exit "$oom_rc"; fi
# Seal rc, full command/env/options/source and binary in the root execution record.
```

After successful build, source/binary/options checks and machine courtesy:

```sh
cd /K3D/GitHub/cgm-zig/build-ready-runtime
export READY_INDEX_CANDIDATE="$oom_root/$oom_phase-stage3/bin/zig"
export READY_INDEX_ORDER=layered
export ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
/usr/bin/time -v -o "$oom_root/$oom_phase-logs/layered.time" \
    timeout --kill-after=10s 180s runner-completeness/bin/repaired-restored \
    ./zig-under-test fixtures/temporary_parse_error \
    --zig-lib-dir "$oom_root/source/lib" --preserve-tmp \
    --debug-log zcu --debug-log zcu_deps \
    > "$oom_root/$oom_phase-logs/layered.stdout" \
    2> "$oom_root/$oom_phase-logs/layered.stderr"
oom_rc=$?
printf '%s\n' "$oom_rc"
# Preserve and classify rc/signal/timeout plus the complete marker chain.
```

For baseline, use the same run command with the sealed absolute
`/K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/clean-stage3/bin/zig`,
`--zig-lib-dir /K3D/GitHub/cgm-zig/build-ready-shadow-2026-09-06/source/lib`, and
new `$oom_root/baseline-logs/`; no compiler rebuild is needed. For all phases,
the wrapper keeps `--listen=-` framing intact and supplies layered / -j1 /
two partitions only to the runner's intended build-exe command. The runner's
fresh temporary directory owns its explicit local/global caches; updates within
a run share the real compiler child. No `.case` suffix is added to the fixture.

## 6. Authoring verification and limits

Actual work was read-only `sed`, `rg`, `awk` raw-log recounts, `jq`,
`sha256sum` / `--check`, and a Node in-memory exact-anchor replacement/hash
calculation over the two full frozen owners. That calculation wrote no source,
patch, cache or variant file; it is not a Zig parse/type/behavior check. Only this
new Markdown packet was authored through `apply_patch`. Existing receipts,
source trees, runner, fixture, manifest banks, control execution facts and build
artifacts were not changed. No compiler, test, Git, network or child agent ran.

Stop after this one proposed preparation-failure arm and its finite controls.
Missing allocation-catch/fallback reach is UNKNOWN; do not substitute append
OOM, direct disablement, global starvation, a module-graph cycle or a performance
claim. No promotion, release, station repoint or parallel-Sema claim is included.
