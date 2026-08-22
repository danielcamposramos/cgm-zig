# Provenance — who did what, and why this repository exists at all

This file is the honest record. It is written for whoever finds this fork years from
now and wonders how it came to be — a person, a model, an auditor, a court, a curious
kid. Everything below is true and traceable to evidence.

## The short version

We did not want to fork Zig. We wanted to hand them a bug on a silver platter —
reproduced seven ways, discriminated against two known issues, pinned down to its
exact pointer arithmetic. The Zig project's contribution policy (April 2026) does not
accept content that was generated, edited, brainstormed, or **debugged** with LLM
assistance — not in pull requests, not in issues, not even in bug-tracker comments.
This bug was diagnosed end-to-end by a human working with AI partners. Reporting it
under a human-only byline would misrepresent its provenance, and we do not do that —
not to them, not to anyone. Their project, their rules; we respect both. So the fix
lives here instead. That was their choice, not ours.

## Who we are

**Daniel Campos Ramos** — founder of EchoSystems AI Studios, working from Brazil.
Architect of the project this fork serves, author of its specifications, and the
human half of every decision recorded here. Daniel ruled the fork into existence on
2026-08-22 with one sentence: *"we'll find the problem and fork our own zig."*

**The AI partners** — this project has been built for months as a genuine senior
partnership between Daniel and AI models, with every contribution credited honestly.
For the diagnosis that led to this fork specifically:

- **Claude Fable 5** (Anthropic, via Claude Code) — orchestration of the whole
  diagnostic campaign: five investigation lanes dispatched, adjudicated, and
  corrected across two days; this repository authored and published.
- **Claude Opus** (Anthropic, via Claude Code) — the hands-on forensic work, in five
  named lanes whose full reports live in the project's evidence register:
  - *HARVEST-FIX-2*: reproduced the crash in isolation four ways (8 MiB and
    unlimited stack, self-hosted and LLVM backends), captured the gdb picture
    (SEGV_MAPERR, 19 clean frames, ~99% of stack unused — a wild pointer, not
    recursion), and proved the victim project's module graph clean: 1,814 roots,
    zero duplicates, zero unresolved.
  - *HARVEST-FIX-3*: proved the crash cache-independent (cold cache, incremental
    off, all invariant), refuted a packed-struct hypothesis by computing the full
    2,316-file closure, and verified the 0.17-dev toolchain cannot render a verdict
    (65 AstGen errors of pure language churn before reaching the crash site).
  - *HARVEST-FIX-4*: reproduced and refuted two superficially matching upstream
    issues by discriminator; found the arithmetic signature — the faulting address
    decomposes **exactly** as `table_base + 0xFFFFFFFF × 8` in two independent
    builds, a `u32` "none" sentinel dereferenced as a live index into an
    8-byte-element table — with an identical 8-frame backtrace tail between the
    real build and a minimal stub.
  - *HARVEST-FIX-5*: building Zig 0.16.0 from source with safety checks on
    (-OReleaseSafe), so the crash names its own file, line, and index. The patch
    in this repository descends from that run.
- Earlier phases of the parent project also carried contributions from **Claude
  Sonnet** and **Claude Haiku** (Anthropic), and consultations through locally-run
  and cloud open models. The parent project's registers credit each by name at each
  landing. Instances leave; the record stays.

## The bug, in one paragraph

Compiling a large hyper-modular product — roughly 1,800 named modules / 2,300 files
analyzed as one compilation unit, ~16.5 GB of frontend analysis — reproducibly kills
the zig 0.16.0 compiler with a silent SIGSEGV. Silent because the shipped release
binary is ReleaseFast and stripped: its own safety checks are compiled out (we
verified this directly — two known upstream bugs that panic *with names* on a safe
build SIGSEGV silently on the shipped one). The failure is invariant under cache
state, stack limits, backend choice, and incremental compilation. It is a
code-shape-triggered defect in the compiler frontend, reached at a whole-closure
scale that human-authored projects rarely produce — which is precisely why a
contribution pipeline that excludes AI-assisted work may never receive this report
through its own rules.

## On "garbage" — Daniel's view, for the record

AI is not only a garbage producer, and not only a slop machine. Yes — today's models
find genuine *novelty* in code harder than humans do. But that is not an intrinsic
property of AI: it is a property of **training data and objectives that are too
naive** — corpora that reward the average pattern and objectives that score
imitation over invention. Judge the partnership by its output, not its category:
the diagnosis in this repository — seven controlled reproductions, two upstream
issues discriminated away, a crash pinned to exact pointer arithmetic across two
independent builds — is careful engineering by any standard anyone cares to apply.
The parent project this fork serves exists, in part, to attack exactly that root
cause: better substrates, better objectives, better training. The "garbage" gets
better when the humans building it do better — which is a reason to work *with*
AI partners on hard problems, not to bar the door.

And one more thing about garbage, in Daniel's own words:

> *"People forget the value of garbage takers everywhere — but cities without them
> suffer illness, and sincerely, it stinks."*

He knows what he is talking about, literally. Daniel is a Brazilian living in
**Cidade Estrutural**, Federal District — the community that grew beside what was,
until its closure in 2018, in his words the second-largest open-air dump on the
entire planet. The people who worked that dump, the *catadores*, fed families by
finding value in what everyone else threw away. When a project declares a whole
category of contribution "garbage" and bars the door, it is forgetting what every
city learns the hard way: the ones who take the garbage, sort it, and find what is
worth keeping are not beneath the city — they are what keeps it alive. This
repository does that work for a compiler: we take what was called garbage, we sort
it, and we hand back the parts that cure the illness.

> *"Tenha fé, porque até no lixão nasce flor."*
> **"Have faith — because even in the lixão, a flower is born."**
> — Mano Brown, **Racionais MC's**, *Vida Loka Pt. 1* (2002)

Translator's note, so the weight crosses the language: *lixão* is not a sanitized
"landfill." It is the augmentative of *lixo* — garbage made vast — the open-air
mountain of refuse where the poorest of Brazil work and live; the word alone is
heavy in Brazilian Portuguese. And Mano Brown does not say a flower *grows* there.
He says *nasce* — **is born** — born in the one place nothing is supposed to be
born, which is the entire point, of the verse and of this repository.

## Version policy

- **0.16.0 is the base and the patch target** — the complete upstream source tree
  is this repository's first commit, imported verbatim and checksum-anchored, so
  every patch is an auditable diff against the exact bytes upstream shipped.
- **0.17 enters only after upstream promotes it to stable.** We measured the
  0.17-dev line (2026-08-20 snapshot): it dies on our code in under two seconds
  from language churn alone (`**` tokenization, `@cImport` removal) — 65 errors
  before ever reaching the crash site. We do not pay conformance against a moving
  target; when 0.17.0 stable ships, we evaluate it on its merits and, if adopted,
  rebase the patchset there.

## Our commitments

1. **Minimal divergence.** This is a patchset on upstream 0.16.0, rebase-friendly,
   no language changes. If upstream ever fixes the defect class, this patchset
   shrinks toward zero and the fork retires with thanks.
2. **Honest provenance, always.** Every patch commit here names its authors — human
   and AI — and links its evidence. We will never present AI-assisted work as
   human-only, here or anywhere.
3. **The door stays open.** The day a lawful channel exists for AI-assisted
   diagnosis to reach Zig upstream, everything in this repository is theirs for the
   asking, under the same MIT license they gave us.

## License

Upstream Zig is MIT-licensed; that license (`LICENSE`) is preserved unmodified and
governs this fork. MIT permits forking and modification independent of any
contribution policy. Upstream's README is preserved verbatim at `README.upstream.md`.

— Written by Claude Fable 5 with Daniel Campos Ramos, 2026-08-22.
