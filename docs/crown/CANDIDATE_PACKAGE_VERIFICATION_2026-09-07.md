# Candidate package verification — 2026-09-07

The frozen unpromoted candidate archive, its existing extraction and all
**4/4 functional smoke commands** are independently verified at the boundary
below. No blocking package-content or smoke defect was found. This is not
performance acceptance, a self-contained public evidence bundle, publication,
release clearance or system-default promotion.

Root performed packaging and the original smoke commands under Daniel's
direction. GPT 6 Astra, cooperating senior compiler partner, independently
reviewed their records, file contents, hashes, archive stream and raw results.
The read-only review was accepted at its stated ceiling. This documentation
follow-up executes nothing and changes no existing file or package bytes.

## Identity: compiler, packaged documents and this later receipt

These three identities are intentionally different:

| What | Recorded identity / independently checked bytes |
|---|---|
| Compiler source | `0399d2b19b71ed865cc2e6d5e21224f124e373db` |
| Compiler version | `0.16.0+cgm.0399d2b19b`, from the actual extracted-binary version output |
| Compiler SHA-256 | `d6b4168f368b95e83d2a6af8022e6ac19e41efbe9b3b04f664c0333ebfa5e34f` |
| Frozen packaged documentation | `159122d7bb35231b27b6de0c5f4474b381a3428d` |
| This verification receipt | Authored afterward; not part of that documentation snapshot or archive. Its later documentation identity must not be substituted for either identity above. |

The source/document commit association is recorded provenance; this review
independently checked the binary and document hashes, without invoking Git or
rebuilding the compiler. The new receipt's eventual documentation commit is
not claimed here. The package is **not repacked to add this receipt**.

The compiler is the uninstrumented logging-fixed candidate, not any shadow,
fault-injection or restored-control executable. The included candidate records
identify ReleaseSafe, full LLVM, native target/baseline CPU, debug extensions
and logging enabled, without stripping. Passive packaging did not rebuild or
strip it.

## Exact archive and complete payload

All links into `build-*` below are **LOCAL evidence available in this
workspace**, not artifacts published alongside this Markdown file.

```text
Q = /K3D/GitHub/cgm-zig/build-package-2026-09-07
NAME = cgm-zig-0.16.0+cgm.0399d2b19b-x86_64-linux-system-llvm21
STAGE = Q/NAME
EXTRACTED = Q/extracted/NAME
SMOKE = Q/smoke
```

[LOCAL archive](../../build-package-2026-09-07/cgm-zig-0.16.0+cgm.0399d2b19b-x86_64-linux-system-llvm21.tar.xz):

- Exact filename: `cgm-zig-0.16.0+cgm.0399d2b19b-x86_64-linux-system-llvm21.tar.xz`.
- Size: **52,849,160 bytes**.
- SHA-256: `3f82e9bb94ae116a844b38472e09d520fc898fc0f2b2665ac360fc5cf29ac1e4`.

| Regular-file class | Independently checked files |
|---|---:|
| Complete installed library, `lib/zig` | 19,543/19,543 |
| Candidate compiler, `bin/zig` | 1/1 |
| Static documents: LICENSE, upstream README, provenance, contribution contract | 4/4 |
| Frozen public README and crown documents | 31/31 |
| Package-specific `PACKAGE.md` | 1/1 |
| `SHA256SUMS` | 1/1 |
| Total regular files | **19,581/19,581** |

The library contains 184,297,278 bytes and matches the original installed
library, not a substituted repository-source tree. All 19,581/19,581 extracted
file hashes match the stage and exact file path set. Both trees contain the
same 1,290/1,290 directories, including the package root.

The archive stream lists 19,581 file members and 1,290 directory members.
No duplicate or unsafe absolute/traversal member was found among those
20,871 entries. Read-only GNU tar comparison against the stage returned zero
with no output. That streamed existing archive bytes; it did not perform a
second extraction.

Internal `SHA256SUMS` covers exactly **19,580/19,580 non-self regular files**
with distinct full paths. Its SHA-256 is
`2cd96a1cf2f856b22132beda5cc9de0ee996c6c6e48a0e2ff9252b20da02cb81`,
also the SHA-256 of retained `Q/payload.sha256`. Every member hash was checked;
the file/path-set check also excludes missing or additional members.
The retained extraction manifest checker has exit zero and exactly
19,580/19,580 expected OK lines; its output hash is
`ddd628c951ff39ed025ce1187dd95138da53f9bd99c76125f4211b8131c0549d`.

All 35/35 copied documents match their sealed copy records, current source
files at review and extracted copies. LICENSE remains the unchanged upstream
MIT text; original and continuing human/AI partner provenance are preserved.

## Recorded creation and extraction commands

These describe completed root operations, not permission to run them again:

```text
tar -I "xz -T1 -3" -C Q -cf Q/NAME.tar.xz NAME
tar -C Q/extracted -xf Q/NAME.tar.xz
```

The actual expanded argv is retained in
[ARCHIVE_PRE](../../build-package-2026-09-07/ROOT_ARCHIVE_PRE.json),
[ARCHIVE_RESULT](../../build-package-2026-09-07/ROOT_ARCHIVE_RESULT.json) and
[EXTRACT_PRE](../../build-package-2026-09-07/ROOT_EXTRACT_PRE.json).
Archive creation ran from 05:23:15.757Z to 05:23:50.786Z, exit zero, no signal;
its stdout/stderr are empty. Extraction's stdout/stderr are also empty,
and [EXTRACT_POST](../../build-package-2026-09-07/ROOT_EXTRACT_POST.json) seals its complete content
and manifest-check success at 05:24:54.140Z. That POST does not separately
record the extraction subprocess return code; this receipt does not invent
one. Exact extracted contents are independently verified.

## Actual relocated functional smoke

The [LOCAL smoke prestate](../../build-package-2026-09-07/ROOT_SMOKE_PRE.json) fixes cwd `SMOKE`,
timeout 180 seconds and this seven-key explicit environment:

```text
PATH=/usr/bin:/bin
LC_ALL=C
TZ=UTC
PYTHONPATH=/K3D/GitHub/cgm-zig/partner_tools/vharness
ZIG_LIBC=/K3D/GitHub/cgm-zig/build-p005/vwork/libc.txt
ZIG_LOCAL_CACHE_DIR=SMOKE/local-cache
ZIG_GLOBAL_CACHE_DIR=SMOKE/global-cache
```

The four raw records agree with those exact keys/cwd. Each actual command
has the existing harness prefix `taskset -c 4-11`; this is **not** the CPU4-only
cost packet and must not be presented as another paired timing experiment.
The compile uses workers one and partitions two. Its normal diagnostic reports
six physical / eight logical CPUs visible under that affinity.

| Check | Recorded argv after `taskset -c 4-11` | Outcome |
|---|---|---|
| version | `EXTRACTED/bin/zig version` | Exit 0; no timeout |
| env | `EXTRACTED/bin/zig env` | Exit 0; no timeout |
| compile | `EXTRACTED/bin/zig build-exe -j1 --intern-partitions=2 -OReleaseSafe --color off -femit-bin=SMOKE/hello SMOKE/hello.zig` | Exit 0; no timeout |
| run | `SMOKE/hello` | Exit 0; no timeout |

All 4/4 commands return zero without timeout; all four outer harness stderr
files are empty. Version/env/run compiler stderr is empty; compile stderr is
one expected info-level thread report, with no error or fault marker. The
helper's elapsed values are functional-run metadata, not new cost evidence.

The actual version output is `0.16.0+cgm.0399d2b19b` plus LF.
The environment output is ZON, not JSON: `zig_exe` names
`EXTRACTED/bin/zig`, `lib_dir` names **`EXTRACTED/lib/zig`**, and
`std_dir` names its `std` child. Its `ZIG_LIB_DIR` field is null.
Neither the explicit environment nor any smoke argv supplies
`ZIG_LIB_DIR` / `--zig-lib-dir`. This proves relocated automatic installed-
library discovery in the recorded host configuration, not by injecting a
library path.

The 151-byte hello source uses `@import("std")` and the normal
`std.Io.File.stdout().writeStreamingAll` path. Fixture SHA-256:
`e29eeed5df701c00e7819366ff5f32dff860861a01be7200b1668cd642cb9912`.
The compile emits and links `SMOKE/hello`; actual subsequent execution returns
zero and writes the expected output. Executable SHA-256:
`b51d450104f46c9c7721d18616041a428f0a4a635e163010b68af8c011dc70b4`.
Both extracted compiler and emitted hello have executable mode 0775.
The extracted compiler retains the exact d6b4168f… hash after the smoke.

### Correct stdout bytes and preserved metadata defect

Actual stdout is **14 bytes**: thirteen printable ASCII characters
`Hello, World!`, followed by LF. Exact hex:

```text
48656c6c6f2c20576f726c64210a
```

The original [ROOT_SMOKE_POST](../../build-package-2026-09-07/ROOT_SMOKE_POST.json), SHA-256
`3586be88adc9c639690636277f5aa7966bfa982ef5783a7aca7a9e8aef11cbc7`,
mistakenly put a literal backslash-plus-n display string in
`executedProgram.stdout`. Parsed literally, that summary string is 15 bytes,
not the actual LF-terminated 14 bytes.

The immutable successor
[ROOT_SMOKE_OUTPUT_CORRECTION](../../build-package-2026-09-07/ROOT_SMOKE_OUTPUT_CORRECTION.json), SHA-256
`71c05eb5e71c6b40963b9365be64c9dda12074d163287ff94b90a9c1e9a8892e`,
names the original seal and [raw run record](../../build-package-2026-09-07/smoke/run.json),
provides the correct text/hex/14-byte count, and records zero compiler/runtime
reruns. The reviewer independently checks the raw string bytes against the
correction; the original defect is not silently rewritten. The wrong display
field does not invalidate the actual successful execution.

## Runtime dependencies and evidence boundary

The included [LOCAL PACKAGE.md](../../build-package-2026-09-07/cgm-zig-0.16.0+cgm.0399d2b19b-x86_64-linux-system-llvm21/PACKAGE.md)
explicitly identifies this as an **unpromoted x86-64 Linux system-LLVM21
candidate**, not a static or generally portable Linux distribution. Its
SHA-256 is `9ab3d5c119e812a9ac956eea73d3ad697d0ca80c3039b8ebcad79daf61cc9f3b`.

The recorded ELF RUNPATH is `/usr/lib/llvm-21/lib`. Direct dependencies are
`libclang-cpp.so.21.1`, `libLLVM.so.21.1`, `libz.so.1`, `libzstd.so.1`,
`libstdc++.so.6`, `libc.so.6` and `ld-linux-x86-64.so.2`, plus compatible
transitive dependencies. Those system libraries are not bundled. The smoke
uses the external `ZIG_LIBC` descriptor stated above, also not a self-contained
package member. Automatic package-library discovery therefore does not prove
independence from system LLVM or host libc configuration.

The package's 36 documents were scanned for file-target links: 46/205
nonempty non-web Markdown link occurrences resolve inside the package;
153/205 refer to unshipped development evidence and 6/205 to unshipped
repository source/tooling. Counts are occurrences, not distinct targets.
`PACKAGE.md` expressly explains that LOCAL historical links do not mean
the raw artifacts ship in the binary package. This is not a self-contained
reproduction/evidence distribution.

A separately declared public companion remains owed. It must provide the
selected reproduction inputs, raw records, seals and any explicitly declared
sanitized derivatives required by their receipts. Original local records
remain immutable. Another partner owns evidence selection; this review neither
assesses that in-progress work nor claims its completion.

## Finite verdict and later documentation

The review covers 15/15 ROOT package records, 4/4 raw smoke JSONs, associated
streams, the full package file/path/hash inventory and existing archive stream.
All 14/14 structured referenced retained identities reconcile, in addition to
the full payload and document checks above. No blocking package-content or
smoke objection remains.

The result is **locally packaged, extracted and functionally smoke-verified,
still unpromoted**. The cost packet's clean-machine acceptance criterion remains
**UNFULFILLED**; packaging cannot waive it. This establishes no broad target
coverage, general portability, performance equivalence, new OOM coverage or
foundation/crown completion. Public evidence, synchronization/publication,
release and system-default promotion remain separate open gates.

The frozen archive and its docs159122 payload do not contain this later
receipt or its [LOCAL independent review](../../build-package-2026-09-07/ROOT_PACKAGE_INDEPENDENT_REVIEW.md).
No archive, source, library, existing document or default pointer is changed
to add them. This lease authors only those two new Markdown files through
native `apply_patch`; no compiler/probe, timing, archive/extraction operation,
Git, network, promotion, cleanup, helper or child agent runs in the
documentation lane. Scope ends at handoff.

## 2026-09-07 — local companion completion and root readback

This dated successor preserves the complete earlier 12,241-byte receipt above,
SHA-256 `a81e0a3563c2bcdf84cac12a608f89f9e9fddc016e93055e185f57753605ab7a`.
Its earlier companion-open statements are history: the separately selected
companion is now **locally assembled and byte-verified**, not published.
Daniel directed the work; GPT 6 Astra, cooperating senior compiler partner,
performed the finite assembly/readback and this documentation follow-up.
Root separately reviewed the completed archive at the limits below.

### Two distinct frozen archives

The candidate package remains the unchanged 52,849,160-byte archive described
above, SHA-256
`3f82e9bb94ae116a844b38472e09d520fc898fc0f2b2665ac360fc5cf29ac1e4`.
It still contains the uninstrumented source0399 compiler and docs159122
package snapshot; no compiler, library or package member was rebuilt or replaced.

The separate [LOCAL companion archive](../../build-package-2026-09-07/cgm-zig-evidence-2026-09-07.tar.xz)
is **605,160,156 bytes**, SHA-256
`38fbf22e748d049ee5582e6a32671f46b8668a546390d29b46c6dfc9a93f84ec`.
Under the explicit `cgm-zig-evidence-2026-09-07/` prefix, it contains:

- **20,215/20,215 selected payload files**, totaling 4,190,805,844 bytes.
- **3/3 externally sealed assembly controls**, totaling 3,772,625 bytes.
- **20,218/20,218 regular members in total**, totaling 4,194,578,469 bytes.
  PAX path metadata is not an additional evidence-file denominator.

The complete sorted member-path-set SHA-256 is
`2df755255ef8d390772ef304fc2a955dea074e52d2d4254fceec4e70c2365f88`.
The [public payload manifest](../../build-package-2026-09-07/public-evidence-inputs.sha256)
has SHA-256
`6c6b8d359d28c4bd01f536f4d7697c7ef6c1a825abf23ecd050c9db6db887ea4`;
its 20,215 rows deliberately exclude the three separately sealed controls.
The external control seal and archive PRE/POST receipts are retained sidecars,
not silently added companion members.

### Actual assembly and verification

The exact inline command and method are retained in
[LOCAL archive PRE](../../build-package-2026-09-07/ROOT_PUBLIC_EVIDENCE_ARCHIVE_PRE.json),
SHA-256 `dfed2b3c660d90ab7397f08bf1a57d91704fb4e6d54b8a68dbdc726ae3bab5f8`,
and [LOCAL archive POST](../../build-package-2026-09-07/ROOT_PUBLIC_EVIDENCE_ARCHIVE_POST.json),
SHA-256 `b5eb6897cafd0977222a83ecd48a1ab99bcb7540913348448a30b93ee61205e2`.
The command text agrees in both records; its SHA-256 is
`c840b773ad8737216cc7cc16b09efc4d3a0e5efbe6934a150d71e027fc090f32`.

One assembly attempt completed with exit zero, no retry. Python's stdlib
streamed PAX tar through single-thread xz preset 3 at own niceness 10.
Compression took **325.872064 seconds**; the subsequent strict compressed
readback took **23.745935 seconds**, completing at 06:35:42 UTC.
These are archive-operation observations, not compiler benchmarks.

All 20,218/20,218 input hashes and streamed member hashes reconciled, with
input stat identities stable through readback. The check covered exact paths,
order, sizes and permission bits; uid/gid zero, empty user/group names and
mtime zero; and complete compressed-stream consumption. No extra, duplicate,
unsafe, link or special member was accepted. Only after readback succeeded was
the partial renamed without replacement to its final name. No loose evidence
tree or filesystem extraction was created.

Root reports a separate complete `tarfile` `r|xz` traversal at
**2026-09-07 06:41:47 UTC**, taking **22.117855 seconds**. It matched all
20,218/20,218 member hashes, the exact 4,194,578,469-byte total, the archive
checksum and the same complete path-set checksum, plus normalized metadata
and all three controls. This is attributed to Root's readback, not another
execution by this documentation follow-up. The traversals share the stdlib
parser: this is not an independent parser implementation. Root did not
independently recheck original payload-file modes, and neither traversal
fired a deliberately corrupted-archive control. Those limits remain explicit.

### Derivatives, later work and remaining gates

The companion uses exactly the two
[declared public derivatives](../../build-package-2026-09-07/PUBLIC_DERIVATIVES_REVIEW.md)
at their original logical slots: the reviewed monitor-label substitution in
the cost post-record and the cache-only cleanup rendering. Their original
local records were not altered. The included historical raw manifest is
therefore not the checksum authority for those two transformed slots; use the
public manifest and transformation ledger. This establishes no general
secrets/IP clearance.

Snapshot boundaries are unchanged. The original package-verification receipt
at the a81e0a35… hash above **was selected into the companion**, but was never
part of the source0399 compiler or docs159122 candidate package. This new
addendum and the new README/PLAN readiness notes are later working documents:
neither frozen archive was repacked to contain them. Frozen manifest hashes
apply to the archived versions, not these later working-file successors.
Later observer implementation/integration is also outside the source0399
candidate and this frozen companion; it was not among the selected inputs.
No coverage or performance credit is transferred from that later work.

The local candidate package and companion are complete only at their recorded
byte/functional boundaries. Publication, online main synchronization, release
and system-default promotion remain open and unfulfilled. The clean-machine
cost acceptance criterion remains **UNFULFILLED**. System LLVM/runtime
dependencies, nonshipping control-executable labels, and all earlier runtime
coverage limits still apply. No crown stage or foundation completion follows.

This follow-up changes only this receipt and additive readiness notes in the
existing README and crown PLAN. It performs no archive write, compiler/run,
benchmark, host control, compiler-source or default-pointer change, Git
mutation, network, helper creation or cleanup.
