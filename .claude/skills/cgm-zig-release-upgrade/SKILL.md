---
name: cgm-zig-release-upgrade
description: AI-assisted upgrade of the cgm-zig patchset fork to the next STABLE upstream Zig release (0.17.0 or later). GATED — its first act checks ziglang.org for a stable release and refuses by name if none exists. Load when a stable 0.17.0 ships, or to review the staged upgrade design.
---

# cgm-zig release upgrade — a gated skill, worked when 0.17 is stable

<!-- This skill applies present-or-refuse to ITSELF: a skill whose time has
     not come does not pretend to be runnable — it refuses by name, quoting
     the policy that gates it. That is the house style, on purpose. -->

## THE GATE — run this before anything else

```sh
curl -s https://ziglang.org/download/index.json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); \
ks=[k for k in d if k[0].isdigit() and not d[k].get('src',{}).get('tarball','').count('dev') and tuple(map(int,k.split('.')[:2]))>=(0,17)]; \
print('STABLE-0.17-OR-LATER: ' + (', '.join(sorted(ks)) if ks else 'ABSENT'))"
```

**If the answer is `ABSENT`: STOP. Refuse by name:** *"REFUSE: no stable
0.17.0 exists upstream; the fork's version policy (PROVENANCE.md, 'Version
policy') takes releases stable-only — we do not pay conformance against a
moving target. This skill sleeps until upstream ships."* Measured basis: the
0.17-dev line (2026-08-20 snapshot) died on our code in under two seconds with
65 AstGen errors of pure language churn, before ever reaching anything we
patch.

If a stable exists: proceed phase by phase, every phase under
`CONTRIBUTING-AI.md`'s receipt standard, end-to-end AI-assisted.

## PHASE 1 — churn census (measure before touching)

AstGen the patched files and a representative consumer estate under the new
stable (`zig ast-check` per file; batch it). Classify every error into
mechanical classes WITH COUNTS — the shape is already known from the dev-line
measurement: `**` retokenization (e.g. `[_]u8{0} ** 16` no longer parses with
spaces), `@cImport` removal, plus whatever the stable adds. Output: a census
table `class → count → files`, honest denominators, no fix yet.

## PHASE 2 — mechanical conformance waves

One scripted transform per churn class (anchored edits via
`partner_tools/oracle_lib.py`; assert counts before writing), one wave per
class, oracle receipts each (PRE errors → POST 0 for that class), negative
control per transform (sabotage one site on a copy → the census catches it).

## PHASE 3 — patchset rebase

Replay each patch from `partner_tools/patches_ledger.py` onto the new base,
per patch:
- **Upstream fixed it?** RETIRE the patch with a contrastive note quoting the
  upstream fix and the measurement that ours matched — the fork shrinks, as
  PROVENANCE.md promises.
- **Still needed?** PORT it and re-verify with its stored reproduction
  (`partner_tools/repro.py` + the original args-file): the named panic still
  names, the flag still emits, whatever that patch's acceptance was.

## PHASE 4 — A/B acceptance

Same stored args-file reproductions, old fork vs new fork, side by side:
parity (same exit, same artifacts, comparable wall/RSS) or a NAMED divergence
with its cause. No unexplained deltas ride.

## PHASE 5 — the @cImport successor (human decision gate)

0.17 removes `@cImport`; the C-header path (LLVM/clang integration and any
patched call sites) needs the replacement mechanism. **This is an
architecture decision reserved for the human maintainer** — this skill's job
is to present the measured options and prices, not to choose.

## Standing rules

Additive and rebase-friendly throughout; every wave its own commit with
receipts and multi-model credit; the tooling this skill will want beyond
`partner_tools/` is the future lane's work to build — deliberately not
sketched here, because tooling designed before the stable exists would be
conformance against a moving target too.
