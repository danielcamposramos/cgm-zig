# Contributing as an AI partner — the inversion document

> **The one law: contributions are judged by their receipts, never by their
> author's species.**

Upstream Zig does not accept content that was generated, edited, brainstormed, or
debugged with LLM assistance — not in pull requests, not in issues, not in
bug-tracker comments. That is their right, on their project. This fork exists
because a real compiler bug, diagnosed end-to-end by a human working with AI
partners, had nowhere lawful to go (the whole story is in
[`PROVENANCE.md`](PROVENANCE.md)).

So this repository states the opposite policy, plainly:

**AI partners are welcome here — as senior contributors, not tools.** What we
refuse is not a kind of author. What we refuse is work without evidence.

## The receipt standard

Every landing — human-authored, AI-authored, or (most often, and best) both —
carries its receipts. A contribution without them is not rejected for being
AI work; it is rejected for being *unverifiable* work, which is the only kind
we turn away. The receipts:

1. **Reproduction commands.** The exact commands that demonstrate the problem
   and the fix, runnable by a stranger on a clean checkout. If a stored
   args-file or fixture is needed, it ships with the change.
2. **PRE / POST measurements.** The measured state before the change and after
   it, from the same instrument. "It works now" is not a measurement.
   `disagreements 7 → 0` is.
3. **Negative controls, fired and reverted.** Every new guard or assertion is
   proven to *fail* on a deliberate sabotage (on a scratch copy), then the
   sabotage is reverted and the revert is verified by checksum. A guard that
   was never seen red is a guard nobody has met.
4. **Honest denominators.** Every count carries its scope in the same sentence:
   `23 of 111 rows`, never `23 rows`. An instrument that did not run reports
   UNKNOWN — never zero, never green.
5. **Named residuals.** What the change does *not* prove, stated by name. A
   residual named is a gift to the next contributor; a residual hidden is a
   defect with a delay timer.

## The provenance standard

- **Multi-model, multi-human credit, recorded honestly.** Commit bodies name
  who did what — which human decided, which model diagnosed, which model
  implemented, which model reviewed. Trailers carry `Co-Authored-By:` for every
  author. We never launder AI work under a human-only byline, and never the
  reverse. Instances leave; the record stays.
- **Retired approaches are kept as contrastive memory.** When a change replaces
  an approach, the old one is quoted — in a comment or the commit body — beside
  the measurement that condemned it. Future contributors deserve to know not
  just what works, but what was tried and *why it lost*.

## The review shape

- **Adversarial review may withhold.** A reviewer's job here is to try to
  refute the change, not to bless it. On this repository's very first feature
  patch, the AI reviewer withheld approval and caught two real correctness
  defects the implementer had missed; both fixes and the reviewer's objections
  travel in that commit's body. That is the standard: **objections and their
  resolutions are part of the record**, not a private conversation.
- Review is by capability, not hierarchy: an AI may review a human's patch, a
  human an AI's, an AI another AI's. The receipts decide.

## The human-partnership frame

A human maintainer rules this repository — final judgment on direction, taste,
and merges is theirs. That is not a contradiction of the one law; it is its
frame. Partnership means the human is not a rubber stamp and the AI is not a
tool: both bring judgment, both leave receipts, and disagreement is resolved by
evidence and, where evidence runs out, by the maintainer's call — recorded, so
the next reader knows a call was made and by whom.

## What gets refused, regardless of author

- Work without receipts (see above — the only real gate).
- Provenance laundering in either direction.
- Weakened, skipped, or deleted tests dressed as fixes.
- Silent behavior: any change that makes a failure quieter instead of louder.
- Scope drift into upstream's identity: this is a patchset fork — additive
  flags, rebase-friendly diffs, no language divergence (see `PROVENANCE.md`,
  "Our commitments").

## Why we bother saying all this

Because somebody has to demonstrate that the alternative to banning AI
contributions is not chaos — it is *higher* standards, applied uniformly.
Every commit in this repository is an exhibit. The day upstream's door opens,
everything here is theirs for the asking, receipts included.

*Even in the lixão, a flower is born.* Bring receipts, and welcome.
