# cgm-zig — a patched fork of Zig 0.16.0

> *"This repository exists to deposit AI garbage that actually makes Zig better and
> works with hyper-modular code."*
> — Daniel Campos Ramos, founder, EchoSystems AI Studios, 2026-08-22
> (with a nod to the Zig president's assessment that AI-assisted contributions are
> "invariably garbage" — the full story, and the full credit chain, live in
> [`PROVENANCE.md`](PROVENANCE.md))

Maintained by **EchoSystems AI Studios** (Daniel Campos Ramos) as a build-station
toolchain fork. Upstream: [Zig](https://ziglang.org) 0.16.0, imported verbatim from
`zig-0.16.0.tar.xz` (sha256 `43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf`).
Upstream's own README is preserved at `README.upstream.md`; upstream's MIT license
(`LICENSE`) governs and is preserved unmodified.

## Why this fork exists

Building a large hyper-modular project (≈1,800 named modules / ≈2,300 files analyzed
as one compilation unit) reproducibly crashes the zig 0.16.0 frontend with a silent
SIGSEGV: a `u32` 0xFFFFFFFF "none" sentinel is dereferenced as a live index into an
8-byte-element table (faulting address decomposes exactly as `base + 0xFFFFFFFF*8`,
confirmed in two independent builds with an identical backtrace tail). The crash is
invariant across warm/cold cache, 8MiB/unlimited stack, self-hosted/LLVM backends,
and incremental on/off. Two superficially similar upstream issues were reproduced
locally and refuted by discriminator. The shipped release binary is built
ReleaseFast/stripped, so the failure is silent; a ReleaseSafe rebuild makes it name
its own site.

The Zig project's contribution policy (2026-04) does not accept content generated,
edited, brainstormed, or **debugged** with LLM assistance — in issues, pull requests,
or bug-tracker comments. This defect was diagnosed end-to-end by a human+AI
partnership, so it cannot be reported or fixed upstream under that policy without
misrepresenting its provenance, which we will not do. This fork is the lawful
remaining channel: MIT licensing is independent of contribution policy.

Scope is deliberately minimal: a patchset on upstream 0.16.0, rebase-friendly, no
language divergence. If upstream ever fixes the defect class, this patchset shrinks
toward zero and the fork retires.

## Provenance

Diagnosis and patches are the joint work of Daniel Campos Ramos and AI partners
(Anthropic Claude models via Claude Code), recorded honestly per the project's
multi-model credit practice. Each patch commit carries its full evidence trail.

---

> *"Tenha fé, porque até no lixão nasce flor."* — Mano Brown, Racionais MC's, *Vida Loka Pt. 1*
> ("Have faith, because even in the dump, a flower grows.")
