# cgm-zig 0.16.0+cgm.0399d2b19b — candidate prerelease notes

**Prepared for an UNPROMOTED PRERELEASE. Publication has not been performed
by this document.** Keep stable `0.16.0+cgm.046d6833` marked latest. This
candidate is for explicit-path evaluation, not replacement of the station's
default compiler. Its clean-machine cost acceptance remains **UNFULFILLED**.

Proposed tag: `0.16.0+cgm.0399d2b19b`, targeting the published reviewed source
tip `767784fec9872c354da9e2b13a54312cb149eda1` so its source view includes the
later tooling and receipts. The compiled source0399 identity remains separate.
Prospective publication must explicitly use `--prerelease --latest=false`;
the version in the tag name does not claim the binary was built from that tip.
The coordinating partner reports that no matching remote tag was observed
before preparation. Tag creation, prerelease publication, asset upload and
remote verification remain subsequent root actions; no existing tag or stable
release is to be replaced. Before any push, the fork requires a sequential
`git pull --ff-only origin main`; never force-push.

## Distinct identities

| Component | Identity |
|---|---|
| Compiler source | `0399d2b19b71ed865cc2e6d5e21224f124e373db` |
| Actual compiler version | `0.16.0+cgm.0399d2b19b` |
| Compiler SHA-256 | `d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f` |
| Frozen candidate-package documentation | `159122d7bb35231b27b6de0c5f4474b381a3428d` |
| Source main published before these notes / proposed prerelease tag target | `767784fec9872c354da9e2b13a54312cb149eda1` |

The compiler is the uninstrumented ReleaseSafe build, with full LLVM, baseline
CPU, debug extensions and logging enabled, without stripping. A later source
or documentation commit is not a new identity for that existing binary.

The coordinating partner reports the completed source-only synchronization:
from the clean existing main worktree, `git pull --ff-only origin main`,
`git merge --ff-only 767784fec9872c354da9e2b13a54312cb149eda1` and
`git push origin main:main` each returned zero; subsequent live `ls-remote`
confirmed that full main SHA. No compiler or default pointer changed.
This is attribution to root's observed transaction, not a transaction or
network check performed by the author of these notes. It does not establish
that the proposed prerelease or assets have been published.

## Exact candidate and separate evidence assets

| Archive filename | Bytes | SHA-256 |
|---|---:|---|
| `cgm-zig-0.16.0+cgm.0399d2b19b-x86_64-linux-system-llvm21.tar.xz` | 52,849,160 | `3f82e9bb94ae116a844b38472e09d520fc898fc0f2b2665ac360fc5cf29ac1e4` |
| `cgm-zig-evidence-2026-09-07.tar.xz` | 605,160,156 | `38fbf22e748d049ee5582e6a32671f46b8668a546390d29b46c6dfc9a93f84ec` |

These are the existing frozen archives, not instructions to rebuild them.
The [package and companion verification receipt](CANDIDATE_PACKAGE_VERIFICATION_2026-09-07.md)
records their actual assembly and checks:

- Candidate package: **19,581/19,581 regular files**, including the complete
  **19,543-file / 184,297,278-byte** installed library, compiler, unchanged MIT
  license, provenance, documents and checksums. Its internal `SHA256SUMS`
  covers 19,580/19,580 non-self files.
- Separate companion: **20,218/20,218 regular members**, totaling
  **4,194,578,469 uncompressed file bytes**. It supplies selected source0399,
  patches, source banks, fixtures, build options, raw controls, binaries,
  logs and reviews. Control/mutant compilers and test runners are explicitly
  **NONSHIPPING evidence**, never substitutes for the candidate's `bin/zig`.
- Candidate extraction and all **4/4 relocated functional smoke commands**
  passed: version, environment, compilation and execution. Installed-library
  discovery worked without an injected library path on the recorded host.
  This is not cross-distribution or performance verification.

The companion uses exactly two declared public derivatives at their original
logical slots: a generic monitor-label substitution in the historical cost
post-record, and a cache-only rendering of the cleanup summary. Original
sealed local evidence remains unchanged. The public payload manifest and
transformation ledger identify the two intentional differences from the
included historical raw manifest. These bounded reviews do not constitute
universal secrets/IP clearance.

Snapshot limits are deliberate. The companion includes the earlier package
verification receipt, but not its later completion addendum. Neither archive
contains these release notes, the later observer/launcher implementation and
wrapped controls, or the two later stopped observed-cost banks. Their source
and public summaries are separate later repository content; their raw records
remain LOCAL evidence, not newly included release assets. No archive was
silently updated to match current main.

## What this candidate changes and what was checked

This remains an additive patchset on Zig 0.16.0, without language divergence.
The earlier fork's hyper-modular compilation fixes and threading work retain
their authorship and evidence; this candidate continues that work with:

- An optional ranked ready index for `--analysis-order=layered`: constant-time
  peeks and logarithmic repairs replace repeated eligible-ready-set scans,
  preserving current-map tie order, function priority and scan fallback.
  **Insertion remains default. This does not parallelize Sema.**
- A logging-gate correction that lets enabled debug logging reach requested
  scopes while retaining mode-default output and scope filtering.
- An explicit serial remedy in the exhausted-index diagnostic, preserving
  the thread-starvation guard.

The [logging-fixed candidate receipt](LOG_FIXED_CANDIDATE_VERIFICATION_2026-09-06.md)
records a successful actual compiler build, requested/nonmatching/no-scope
logging controls and **47/47 expected incremental update labels** across
11/11 successful runner invocations, including intentional errors. Its
historical runner-checker ceiling remains attached to that evidence.

Later [repaired-runner verification](INCREMENTAL_RUNNER_COMPLETENESS_2026-09-07.md)
discriminates 3/3 old false successes from 3/3 repaired named failures,
then passes 47/47 native and 3/3 sema update expectations after a fresh repaired
build. The runner is verification tooling, not a replacement shipping compiler.

The [live shadow](READY_INDEX_LIVE_SHADOW_2026-09-06.md) records
**10,678/10,678 same-live-state indexed/scan agreements**. Separate
[selection-checker](READY_INDEX_SELECTION_SELF_CONTROL_2026-09-07.md),
[lost-append](READY_INDEX_LOST_APPEND_CONTROL_2026-09-07.md),
[lost-invalidation](READY_INDEX_LOST_INVALIDATION_CONTROL_2026-09-07.md) and
[default-entry](READY_INDEX_DEFAULT_ENTRY_CONTROL_2026-09-07.md) controls have
their named discriminators and separately rebuilt restorations. The
[preparation-OOM control](READY_INDEX_PREPARE_OOM_RECEIPT_2026-09-07.md)
completed 4/4 compiler builds and 5/5 intended runtime phase outcomes, including
the expected failing tripwire. These are isolated instrumented builds, not
the distributed candidate. OOM evidence covers the first nodes-preparation
allocation only; broader OOM, post-abort rearming, full race coverage and the
other receipts' masking/coverage limits remain unproved.

## Cost and default-promotion boundary

The [original cost receipt](READY_INDEX_RELEASE_COST_RECEIPT_2026-09-07.md)
retains **12/12 successful compiles** with sealed inputs. Its 3/3 wall
comparisons fall inside the existing descriptive noise heuristic, but
old/default wins 3/3 paired slots and candidate default median RSS is +356 KiB.
Ambient activity and incomplete in-sample coverage leave the declared
clean-machine criterion unfulfilled. This proves neither performance
equivalence nor an index speedup.

The [later observed-cost receipt](READY_INDEX_OBSERVED_COST_RECEIPT_2026-09-07.md)
keeps two distinct stopped attempts: a root empty-libc launch-binding error,
then one successful old/default compile rejected by one sibling CPU user tick
under the preaccepted rule. Each launched 1/16 slots and left 15 unlaunched;
together they produced zero quality-supported timings. They are not pooled
with the original twelve. The 2/2 live noncompiler wrapped controls validate
the instrument only. Neither stopped series authorizes another launch.

An unpromoted prerelease makes the bounded candidate available for evaluation;
it does not waive the existing cost criterion or install it as default.
Preserve `PROMOTED/stage3-046d6833` and the existing pointer. No new numeric
slowdown threshold, universal speed requirement or Crown-stage completion is
claimed. Default promotion remains a separate verification-backed decision.

## Runtime requirements and explicit-path use

This is **x86-64 Linux with system LLVM/Clang 21**, not a static or generally
portable Linux distribution. Recorded RUNPATH is `/usr/lib/llvm-21/lib`.
Direct dependencies are `libclang-cpp.so.21.1`, `libLLVM.so.21.1`, `libz.so.1`,
`libzstd.so.1`, `libstdc++.so.6`, `libc.so.6` and `ld-linux-x86-64.so.2`, plus
compatible transitive dependencies. Those libraries are not bundled.

Keep the extracted `bin/zig` and `lib/zig` together, verify the package's
`SHA256SUMS`, and invoke its compiler by explicit path. Do not replace PATH
links or `PROMOTED/zig` merely to try this candidate. The recorded smoke used
an external libc descriptor; Debian multiarch compilation involving system
headers may require the `ZIG_LIBC` configuration in
[BUILDING](BUILDING.md). Baseline CPU selection does not remove those system
dependencies or prove compatibility on another distribution.

## Partnership, provenance and preparation scope

Daniel Campos Ramos directs EchoSystems AI Studios and this fork. Claude
Fable's original orchestration and the Opus, Sonnet and Haiku partners'
diagnostic/design/implementation contributions retain their original credit.
Continuing GPT 6 Astra partners contributed compiler corrections, the optional
ready index, independent source/evidence review, orchestration and packaging
under Daniel's direction. Responsibilities and review limits remain recorded
in the individual receipts and [PROVENANCE](../../PROVENANCE.md); no later
credit replaces the earlier partners' authorship. The upstream MIT license
remains unchanged.

These notes were prepared by GPT 6 Astra through a one-file additive
`apply_patch` lease after reading the governing fork laws and existing
package/evidence records. The destination was absent. No compiler, test,
workload, archive operation, Git/network action, upload, tag creation, cleanup
or pointer change was performed. Prerelease execution and verification are
still root-owned future actions; this document is not their completion receipt.

## 2026-09-07 — executed prerelease publication

This successor preserves the complete 10,812-byte preparation above, SHA-256
`934f6965740a93f7066408f2efaf5210b4bad3288dcc8b9c25edb0dc5334dd7a`.
Its earlier proposed/unexecuted publication statements are now historical:
the coordinating partner actually published the
[unpromoted candidate prerelease](https://github.com/danielcamposramos/cgm-zig/releases/tag/0.16.0%2Bcgm.0399d2b19b)
at **2026-09-07 14:18:54 UTC**, release ID **384140388**.
Execution was by the root coordinating partner under Daniel's direction;
this documentation follow-up reads the retained evidence, not the network.

The complete [LOCAL RELEASE_POST](../../build-publication-2026-09-07/RELEASE_POST.json),
recorded at `2026-09-07T14:20:23.313Z`, has SHA-256
`3d21d10091b31deb0abb38e605899f58ca712174710a09c289aac365e77ced17`.
Root's API verification records:

- `draft=false`, `prerelease=true`; stable `0.16.0+cgm.046d6833` remains latest.
- **3/3 expected assets** have state `uploaded`, with exact matching names,
  byte sizes and API-reported SHA-256 digests. The two archives retain the
  names, sizes and checksums in the asset table above. The third asset is
  `SHA256SUMS`, **231 bytes**, SHA-256
  `2b003b7a5459769006ce7d96b532c7de197ad1aa7b797a16187fa7cd841db838`.
  Its two rows identify exactly those two archives.
- The remote body exactly matches the separately submitted
  [LOCAL RELEASE_NOTES.md](../../build-publication-2026-09-07/RELEASE_NOTES.md),
  **3,645 bytes**, SHA-256
  `15c6c5913fb1804a925d37aa4a6391b781a8f7f0f1c0ecfd418eada58aabe706`.
  That submitted body is not this longer, evolving repository document.
- Retained live remote refs identify tag `0.16.0+cgm.0399d2b19b` at
  `767784fec9872c354da9e2b13a54312cb149eda1` and main at
  `cf28537cb443f345faba643e85d94acf6ac06fb5` at the recorded observation.
  The compiler remains source0399 and the packaged documents remain
  docs159122; neither is relabeled as built from the tag or later main.
- The default pointer still resolves to
  `PROMOTED/stage3-046d6833/bin/zig`; no binary promotion occurred.

The author independently read all three local publication files, checked the
submitted notes and checksum-file identities against POST, and reconciled its
3/3 asset rows. **Remote asset verification is root's API-reported size/digest
evidence, not downloaded-byte readback.** No asset download, new archive audit,
compiler/test/cost run, or independent API query was performed here.

Publication does not alter the two frozen archives or their two declared
derivatives. The later observer implementation, stopped-series raw records,
these publication records and this successor were not silently inserted into
either archive. Original raw evidence remains retained with its existing
LOCAL/replay boundaries. The published source and bounded prerelease are now
available; **clean-machine cost acceptance and system-default promotion remain
UNFULFILLED**. Neither stopped series is resumed, and no speedup, equivalence,
general portability or Crown/foundation completion follows.

This additive follow-up changes only this document and ending status notes in
README and crown PLAN, through `apply_patch`. Existing text prefixes and all
publication inputs remain unchanged. It performs no publication, Git/network,
workload, archive, source, cleanup or default-pointer action.
