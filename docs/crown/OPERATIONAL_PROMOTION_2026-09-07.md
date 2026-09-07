# Operational compiler promotion — 2026-09-07

**Executed:** at `2026-09-07T15:48:17.019Z`, the coordinating partner atomically
repointed the station's `PROMOTED/zig` from `stage3-046d6833/bin/zig` to durable
`stage3-d6b4168f/bin/zig`. The user's local `zig` entry resolves through that
pointer. The old compiler remains preserved for rollback.

Daniel Campos Ramos explicitly directed promotion of the latest verified
compiler if ready and evaluation through the real project. Root made the
verification-backed operational judgment and executed it. GPT 6 Astra's
cooperating compiler reviewer recommended promotion at the stated evidence
ceiling, then authored this public-safe receipt. The reviewer did not inspect
private project source or execute the project runs, staging or repoint.

## Identity and actual station change

| Item | Recorded value |
|---|---|
| Compiler version | `0.16.0+cgm.0399d2b19b` |
| Compiled source | `0399d2b19b71ed865cc2e6d5e21224f124e373db` |
| Compiler SHA-256 | `d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f` |
| Durable executable | `PROMOTED/stage3-d6b4168f/bin/zig` |
| Automatically discovered library | `PROMOTED/stage3-d6b4168f/lib/zig` |
| Preserved rollback executable | `PROMOTED/stage3-046d6833/bin/zig` |

This is the previously verified, uninstrumented ReleaseSafe compiler with
full LLVM, baseline CPU, debug extensions and logging enabled, not stripped.
It was not rebuilt for promotion. Its system LLVM/Clang 21 and host-runtime
dependencies remain; promotion does not make the binary generally portable.

Root staged **19,544/19,544 compiler-plus-installed-library files**, totaling
**324,106,662 bytes**, from the previously verified frozen package extraction
into the new durable tree. The recorded byte-hash comparison is identical:
one compiler plus all 19,543 installed-library files, not a substituted source
library or a copy of the package's documentation. The recorded inventory SHA-256
is `f183fd6ffd5b5fab8bf18141c985ea49ced07f199fb91b30d75bbd4b4b46c721`.

After the atomic repoint, POST retains the original combined version/environment
capture with exit zero, but without separate per-command exit-code fields.
Root subsequently recorded distinct, non-compiling version and environment
commands in POST_COMMANDS at **2026-09-07 15:53:43 UTC**: **2/2 commands have
their own recorded exit zero**. Version is `0.16.0+cgm.0399d2b19b`; the
environment's executable, library and standard-library paths resolve inside
the durable new tree. `ZIG_LIB_DIR` is null: library discovery was not supplied
by an override. These later observations provide separate successful-command
records; they do not retroactively add exit fields to the original combined
capture or constitute a new compilation/runtime workload.

## Verification basis, not a successful project-build claim

The primary basis is the existing compiler verification, not merely a new
pointer or a compiler build that exited zero:

- The [logging-fixed candidate](LOG_FIXED_CANDIDATE_VERIFICATION_2026-09-06.md)
  has an actual ReleaseSafe build, logging-scope controls and 47/47 expected
  incremental update labels across 11/11 successful runner invocations, with
  that historical runner's limits preserved.
- The later [repaired runner](INCREMENTAL_RUNNER_COMPLETENESS_2026-09-07.md)
  discriminates its three completeness defects and passes 47/47 native plus
  3/3 sema update expectations after a fresh repaired build.
- The [live shadow](READY_INDEX_LIVE_SHADOW_2026-09-06.md) records
  10,678/10,678 same-state index/scan agreements. Its selection, lost-hook,
  invalidation and default-entry controls retain their named failures and
  separately rebuilt restorations. The
  [preparation-OOM control](READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md)
  completes its bounded first-allocation fallback experiment, not universal OOM
  or race coverage. Those instrumented control compilers are not the promoted
  executable.
- The [package verification](CANDIDATE_PACKAGE_VERIFICATION_2026-09-07.md)
  includes complete payload checks and 4/4 relocated functional smoke commands.

Root then compared the same canonical three-root real-project command using
the candidate and old046d. **Both attempts exited 1** at the same project
build-script graph refusals; **0/3 selected product roots newly succeeded in
either attempt**. Root compared **131/131 selected diagnostic rows**, normalizing
thread PIDs only; the resulting rows are exactly equal at SHA-256
`1a42c28d05d9d65db5abe5f168600ce2c1d5d41c845b7947c349707ac2d1d9e3`.
This is equality of that selected diagnostic projection, not a claim that
entire raw streams or all execution behavior are identical. Private source,
paths and diagnostic details are deliberately absent from this public receipt.

No candidate-specific internal compiler failure was identified in the paired
attempts; the matched refusals support the project-guard diagnosis. They do not prove
universal compiler correctness, successful product compilation or product
runtime behavior. Neither failed attempt is relabeled as a pass or used as a
speed measurement.

Root reports source-edit leases closed through both runs. A bounded census of
**23,817 source/configuration paths** in the selected compiled/tool/script trees
found **0/23,817 modification timestamps within**
`2026-09-07T15:34:50.159Z` through `2026-09-07T15:44:41.437Z`, with
**0/23,817 missing reads**. This is an mtime observation plus authoring-lease
closure, **not an estate-wide before/after byte seal**. It does not establish
immutable contents at every instant, unobserved-path stability or equivalent
caches/environment. This author did not independently inspect that private
source census; the safe aggregate is root-attributed evidence.

## Operational disposition and retained limits

The [contribution contract](../../CONTRIBUTING-AI.md) requires receipts,
provenance, honest denominators and named residuals, with the maintainer's
judgment recorded where evidence runs out. The station's promotion rule is
latest verified, with evidence and a recoverable prior compiler.

Under Daniel's explicit direction, root accepted the existing functional,
control and package verification as the primary operational basis. The paired
project refusals provide a baseline discriminator; demanding success on the
same invalid project graph would not distinguish the two compilers. This is
not a waiver of correctness or a claim that no other compiler defect exists.

The historical [clean-machine cost criterion](READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
remains **UNFULFILLED**. The two
[observed-cost attempts](READY_INDEX_OBSERVED_COST_RECEIPT_2026-09-07.md) stay
stopped and unpooled. Their earlier default-pending disposition is superseded
by this later recorded operational judgment, not by a retroactive measurement
pass. There is no speedup, performance-equivalence, Crown-stage or foundation
completion claim. Insertion remains the analysis default; this does not
parallelize Sema.

Public prerelease/latest-release metadata and both frozen archive byte streams
are unchanged. Station promotion does not rewrite the
[publication record](CANDIDATE_RELEASE_2026-09-07.md), change the released tag,
or silently add later evidence to either archive. Original and continuing
human/AI authorship remains credited in [PROVENANCE](../../PROVENANCE.md).

## LOCAL receipts and this review's scope

These are ignored **LOCAL** receipts, not tracked Git files or newly published
archive members:

| Retained record | SHA-256 |
|---|---|
| [PRE](../../build-promotion-2026-09-07/PRE.json), `2026-09-07T15:47:41.216Z` | `e471aa27c04c5f3dc6fa1cbb409d91ddb41934e7c6d27470c4c59f155b40d0ec` |
| [POST](../../build-promotion-2026-09-07/POST.json), repoint `2026-09-07T15:48:17.019Z` | `3898bee0a6f7502ed9ea0990c4e6dde5e336efa41a1363fc4f60f9eb4a1b0426` |
| [POST_COMMANDS](../../build-promotion-2026-09-07/POST_COMMANDS.json), separate observations `2026-09-07 15:53:43 UTC` | `b144b44211c90eebb6684c83bd07d701af8e9fcd4f7efe0b5a80085deea5d5ed` |

The author read all three complete records and checked their file hashes. Staging,
the 19,544-file byte comparison, actual project runs, normalized diagnostics,
source census and post-repoint probes are root-executed evidence, not reruns
by this documentation lane. No whole-library or archive hash audit was repeated.

Authoring is limited to this new receipt, a current-default/historical-inventory
note in README and a dated crown PLAN successor, all through `apply_patch`.
No compiler/test/workload, Git/network, archive, symlink or cleanup action was
performed here. Root separately owns `PROMOTED/RECORD.md` and source synchronization.
