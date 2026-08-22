# partner_tools — the fork's eyes and hands, our style

Python 3 stdlib-only tooling for anyone (human or AI) working this fork.

**Why this directory is not `tools/`:** upstream Zig owns `tools/` and we never
put our files inside upstream-owned paths — a rebase must never have to
negotiate our additions against their tree. `partner_tools/` is ours alone,
top-level, collision-proof by name.

**The house style these tools implement:**

- Every count carries its denominator in the same line.
- An instrument that did not run reports **UNKNOWN — never zero, never green**.
- Refusals are by name: a tool that cannot answer says exactly what is missing.
- Derived, never hand-maintained: the patch ledger is computed from git
  history; nothing here holds a list a registry already knows.
- Receipts: measurement tools print blocks you can paste into a commit body.

| Tool | One line |
|---|---|
| `fork_status.py` | Toolchain, patchset-vs-base, tree state — the eyes |
| `repro.py` | Fire a stored args-file compile under `/usr/bin/time -v`, print the receipt block |
| `oracle_lib.py` | Anchored-edit / negative-control / revert-sha-verified helpers |
| `oracle_conventions.md` | The PRE/POST + fired-control idiom, written down |
| `patches_ledger.py` | The patchset, derived from git log, with Upstream-Status per patch |

All tools accept `--help`; `fork_status.py`, `oracle_lib.py` and
`patches_ledger.py` accept `--self-test`.

---
*Provenance note (2026-08-22): this directory was authored by the AIF track
(Claude Fable 5) but first landed inside commit `885fada0` — the crown track's
rung-1 commit — because both tracks share one working tree and its commit swept
these then-untracked files along. Nobody's work was lost; the attribution just
needed this correction, which is itself the house style: the record gets fixed
in the open, never rewritten.*
