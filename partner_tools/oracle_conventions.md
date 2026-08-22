# Oracle conventions — how a change proves itself here

An *oracle* is a small, standalone check that re-derives an expected state
independently of the code under test, so agreement means something. The idiom,
in the order it must run:

1. **PRE.** Measure the current state with the oracle *before* touching
   anything, and record the numbers with their denominators
   (`disagreements: 7 of 111 rows`, never `some disagreements`). If PRE
   surprises you, your premise was stale — stop and re-ground; do not "fix"
   a state you have not understood.
2. **Anchored edit.** Every automated write asserts its anchor's occurrence
   count first (`oracle_lib.assert_anchor`). Zero hits = stale premise;
   surplus hits = an edit about to land somewhere you did not look. Both
   refuse by name instead of writing.
3. **POST.** Same oracle, same denominators. The claim you may make is
   exactly `PRE → POST` and nothing more.
4. **Negative control, fired.** Sabotage a *scratch copy* (never the tree)
   in the precise way your new guard should catch — then watch it go red,
   and quote the red. A guard never seen firing is a guard nobody has met;
   the sabotage that turns exactly the targeted row red (and no others) is
   also evidence your check is *specific*, not merely loud.
5. **Revert, sha-verified.** Restore the sabotaged copy and verify the
   restore byte-for-byte (`oracle_lib.revert_verified`). "I put it back"
   is a hope; a matching sha256 is a fact.

Two measured traps this repo has already paid for, so you don't:

- **Filter paths, not match text.** Piping matches through `grep -v <dir>`
  filters the *match text*, not the file path — an exclusion that excludes
  nothing while satisfying a reviewer's glance. Scope the search itself.
- **Silence is a datum.** A tool that exits nonzero with zero stderr bytes
  on a safety-checked build is reporting something (and on a stripped build,
  reporting nothing is exactly the disease). Always record stderr byte
  counts in receipts.

The receipt block from a full oracle pass belongs in the commit body. See
`CONTRIBUTING-AI.md` for what else travels with a landing.
