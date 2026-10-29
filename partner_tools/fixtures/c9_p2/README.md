# C9 P2 fixture estate — stage 0.5 rungs 2 and 4

Hand-authored estate for the rung-2 (`--check-decls`) and rung-4
(`--as-module`) proof set. The controls that consume it live in
`partner_tools/c9_p2_controls.py`; the packet is
`docs/crown/C9_P2_PACKET_2026-09-12.md`. **No control in this estate has
been executed** — the estate and the manifest are authored UNEXECUTED, per
the packet's contract.

## The same-cwd contract

`graph.json` records module roots the way `-femit-module-graph` renders
them: relative to the directory the graph was "emitted" from. For this
estate that directory is **this one** — every control must run with
`cwd = partner_tools/fixtures/c9_p2`. Rung 2 joins relative roots against
the process cwd (`resolveGraphBase`) and rung 4 sandbox-checks against the
cwd-joined root (`resolveAsModule`); running from anywhere else makes the
named-module targets unreadable and the sandbox wrong, by design and with
named refusals, not silently.

## The graph

| index | fully_qualified_name | root | root_src_path | deps (import_name -> dep_index) |
|---|---|---|---|---|
| 0 | `c9p2.util` | `.` | `util.zig` | — |
| 1 | `c9p2.alpha` | `lib_a` | `alpha.zig` | util→0, shared→4, opaque_mod→3 |
| 2 | `c9p2.beta` | `lib_b` | `beta.zig` | util→0 |
| 3 | `c9p2.opaque_mod` | `lib_o` | `opaque.zig` | — |
| 4 | `c9p2.dupe_a` | `lib_d1` | `same.zig` | shared→5, ghost_mod→8 |
| 5 | `c9p2.dupe_b` | `lib_d2` | `same.zig` | broken→**null** |
| 6 | `c9p2.twin` | `lib_t1` | `twin.zig` | util→0 |
| 7 | `c9p2.twin` | `lib_t2` | `twin.zig` | util→0 |
| 8 | `c9p2.ghost_mod` | `lib_g` | `ghost_src.zig` | — |

Deliberate irregularities, each feeding a named control:

- **`shared` is declared twice with distinct targets** (alpha→dupe_a,
  dupe_a→dupe_b): rung 1's union accepts the name, unbound rung 2 collapses
  it to `target-unresolvable`, and beta's strict table rejects it — three
  verdicts for one import name. Retained correction 6 adds the fourth:
  bound as alpha, rung 2 resolves `shared` through alpha's OWN edge (index
  4, `lib_d1/same.zig`) alone, so the two targets' distinct spellings
  (`onlyD1`/`onlyD2`) discriminate strict selection on
  `lib_a/strict_target_selection.zig` (C9P2-41/42).
- **`broken` carries `dep_index: null`** — stage 0's own "dependency module
  not found" value: counted `target-unresolvable`, exit 0.
- **`c9p2.twin` appears at indices 6 and 7** — `fully_qualified_name` is
  convention, not identity: `--as-module=c9p2.twin` must refuse as
  ambiguous and list both indices; only `--as-module=6` / `--as-module=7`
  disambiguate.
- **`lib_g/ghost_src.zig` does not exist** (module 8): a resolvable target
  that cannot be read is an ERROR (`target-unreadable`), never a `missing`.
- **`graph_missing_fields.json`** is the same document without
  `index`/`root`/`root_src_path` on any module — an old or hand-written
  document rung 1 must still accept (the BLOCKER 2 additive contract) and
  rungs 2/4 must refuse by name.

## Files

Targets (read and parsed by the checker, never checked directly):

- `util.zig` — public surface: `helper` (fn), `answer` (const), `extfn`
  (extern **prototype** — the BLOCKER 1 shape), plus non-public `hidden`.
  Arity-shape surface (retained arity dispatch): `generic` (comptime
  parameter), `varargs` (extern `...`), and `anyfn` (`anytype` parameter —
  the distinct `.anytype_ellipsis3` iterator branch, added by Sol
  correction 5) — all three dynamic_fn, never compared; `fnval` (public
  const of function type) — other_decl, never called non-callable;
  `Thing` (container with receiverless `staticCall` and instance
  `method(self: Thing)`) — for the deeper-qualified and receiver-sugar
  negative control.
- `lib_o/opaque.zig` — top-level `comptime` block: opaque target.
- `lib_d1/same.zig`, `lib_d2/same.zig` — the ambiguous `shared` targets,
  each carrying one distinct public spelling the other does not declare
  (`onlyD1` in lib_d1, `onlyD2` in lib_d2) for correction 6's
  binding-strict selection control.
- `lib_t1/twin.zig`, `lib_t2/twin.zig`, `lib_a/alpha.zig`, `lib_b/beta.zig`,
  `lib_a/nested_ok.zig` — real root sources so every graph path resolves.
- `lib_a/data.zon` — the ZON-opacity target.

Checked files (the controls run `ast-check` on these):

- `lib_a/checked_ok.zig` — all green: shapes (a) and (b), extern prototype.
- `lib_a/missing_decl.zig` — rung-2 red: three missing members.
- `lib_a/alias_too_deep.zig` — alias discrimination: validated 1,
  alias-too-deep 1 (the root identifier chain), and one function-local
  import binding FOLLOWED since retained correction 8 (AstGen's binding
  sidecar names the exact declaration, so the local direct-import shape
  is judged by its own declaration's initializer, never a file-wide
  spelling): validated, and its call enters the arity population with a
  match — "member refs seen 3: validated 2, alias-too-deep 1", "direct
  calls seen 1: arity-matched 1" (see its header for the AstGen
  shadowing premise correction and the succession through corrections 3
  and 8).
- `lib_a/sibling_scopes.zig` — sibling-scope name collision (senior-review
  MAJOR, retired by retained correction 3; one shape restored by retained
  correction 8): one spelling reused by an import binding and a plain
  value in sibling scopes. The import binding is followed through its
  exact declaration (validated, its call arity-matched); the plain-value
  access stays IGNORED — no bucket, no diagnostic — and the root simple
  alias with no namesake stays validated: "member refs seen 2: validated
  2", "direct calls seen 1: arity-matched 1".
- `lib_a/param_namesake.zig` — parameter namesake (retained correction 3;
  refusal boundary kept for the shape by retained correction 8): a
  parameter (`m: anytype`, the one exercised form) spelled like an
  unrelated function-local import alias; the parameter access ignored
  (known lexical owner, unknown value provenance), the import binding
  beside it followed, and the root alias contrast validated: "member refs
  seen 2: validated 2", "direct calls seen 0".
- `lib_a/capture_namesake.zig` — capture-payload namesake (retained
  correction 3; refusal boundary kept for the shape by retained
  correction 8): the ONE exercised capture form (`if (<optional>) |m|`)
  spelled like an unrelated function-local import alias; the capture
  access ignored (known lexical owner, unknown value provenance), the
  import binding beside it followed, and the root alias contrast
  validated: "member refs seen 2: validated 2", "direct calls seen 0".
  Other capture forms are exercised as ignored shapes by correction 8's
  own fixtures below.
- `lib_a/local_direct_import.zig` — the one newly supported non-root shape
  (retained correction 8): a function-local const bound DIRECTLY to
  `@import("util")`, with one public member (`answer`, validated) and one
  declared-but-not-public member (`hidden`, MISSING — the exit-1
  diagnostic). AstGen's own `localVarRef` sidecar names the exact
  declaration each use resolved to, so rung 2 follows the local alias
  through the same target/public-decl owners the root alias always had:
  "member refs seen 2: validated 1, missing 1" (C9P2-43).
- `lib_a/local_arity.zig` — arity over the newly supported local shape
  (retained correction 8): two direct calls through one function-local
  const import — `helper()` matched (exact_fn(0), called 0) and
  `extfn()` mismatched (exact_fn(1), called 0). Both member names stay
  validated (arity is additive to existence): "member refs seen 2:
  validated 2", "direct calls seen 2: arity-matched 1, arity-mismatch 1",
  exit 1 from the one mismatch (C9P2-44).
- `lib_a/sibling_import_param.zig` — same spelling, two sibling scopes,
  two owners (retained correction 8): one sibling's local import binding
  is followed (validated, arity-matched), the other sibling's `m: anytype`
  parameter is ignored — byte-identical spellings, different verdicts,
  which no file-global spelling match could ever produce (C9P2-45).
- `lib_a/sibling_two_imports.zig` — one spelling, two sibling locals, two
  DIFFERENT targets (retained correction 8): `m` bound to `util` in one
  scope and to `nested_ok.zig` in another; each access follows its own
  declaration's target and validates — where a file-global spelling entry
  would resolve one access through the wrong file and report a false
  missing (C9P2-46).
- `lib_a/local_unknowns.zig` — the known-owner/unknown-provenance boundary
  (retained correction 8): an ordinary local const, a genuinely reassigned
  local `var` import, and a local const chained to the root alias's NAME —
  all three known lexical owners, all three ignored: zero invented name or
  arity results; only the root contrast validates (C9P2-47).
- `lib_a/capture_forms.zig` — if/while/for/pointer payload captures sharing
  an import-alias spelling elsewhere (retained correction 8; the while and
  pointer forms reshaped by retained correction 9 to be unambiguously
  AstGen-admissible: the by-value while capture reads a `const` optional, the
  pointer capture reads a separate mutable optional lvalue so the payload
  write is a real mutation — denominators unchanged): every capture
  is a known lexical owner (sidecar category `capture`) with unknown value
  provenance — all four ignored — while the same-spelled import binding
  beside them is followed (C9P2-48).
- `lib_a/capture_forms2.zig` — the remaining capture producers (retained
  correction 8): switch payload AND tag captures, a second prong's
  payload, catch, if-error success and error captures, and errdefer —
  each recorded with its own sidecar fact and each ignored under the same
  zero-attribution rule (C9P2-49).
- `lib_a/nested_and_tunnel.zig` — nested namespace vs closure-tunneled root
  (retained correction 8): a function-local container's own member (`S.x`)
  is ignored — its exact declaration is a local const of a struct literal,
  never an import — while a ROOT declaration referenced from inside a
  generic namespace nested in a function (the `tunnelThroughClosure`
  shape) stays validated: the sidecar records the binding BEFORE the
  tunnel transforms it (C9P2-50).
- `lib_a/astgen_fails.zig` — a source AstGen refuses, under `--check-decls`
  (retained correction 8): an undeclared identifier makes lowering fatal;
  the driver renders the normal diagnostic and exits 1, and NO graph
  summary appears — the file holds a lawful import site whose
  "import sites seen" line would print if any rung ran, so its absence
  pins the clean-AstGen gate. The sidecar is cleared before publication
  whenever the produced ZIR carries ANY diagnostic (retained correction 9
  widened the trigger from fatal-only), so no partial binding observation
  is ever consumable — and under `--check-decls` this path is
  requested-then-cleared, never zero-allocation (C9P2-51).
- `lib_a/arity_mismatch.zig` — arity mismatch, both directions (retained
  arity dispatch): `util.helper(1)` too many, `util.extfn()` too few, and
  the inline `@import("util").helper()` exact-match contrast; both
  mismatched calls stay name-validated — arity is additive to existence.
- `lib_a/arity_dynamic.zig` — arity skipped-dynamic (retained arity
  dispatch; extended by Sol correction 5): a comptime-generic call whose
  count coincidentally matches, a variadic call whose does not, and an
  `anytype` call exercising the distinct iterator branch — all three
  skipped, never compared; naive equality would be wrong both ways on
  the first two alone.
- `lib_a/arity_nonfn.zig` — arity skipped-non-fn (retained arity
  dispatch): a direct call on a public const of function type; never
  called non-callable, never compared.
- `lib_a/arity_missing.zig` — arity unavailable on a missing member
  (retained arity dispatch): the missing error is the only diagnostic; no
  argument-count mismatch is stacked on top.
- `lib_a/strict_target_selection.zig` — binding-strict rung-2 target
  selection (retained correction 6): two member refs through the one
  supported alias shape bound to the ambiguous name `shared`. Unbound:
  both `target-unresolvable` (the union conflict), exit 0. Bound as
  `c9p2.alpha`: alpha's own `shared` edge (index 4) selects
  `lib_d1/same.zig`, so `onlyD1` validates and `onlyD2` is missing —
  positive and negative discrimination from one file, exit 1. Arity
  denominator zero in both runs; no call, no guess.
- `lib_a/arity_bound_method.zig` — receiver-sugar and deeper-qualified
  negative control (retained arity dispatch; reshaped by Sol correction 5,
  which found the old `util.Thing.method()` shape was a type-namespace
  call falsely named a bound method — it never had a receiver): the
  deeper qualified `util.Thing.staticCall()` whose outer callee is a
  two-hop field access, plus an actual receiver-sugar `thing.method()` on
  a local value typed through `util.Thing` — neither callee is a
  supported member reference, so the arity denominator stays zero while
  both `util.Thing` member refs are name-validated. Syntactic population
  boundary controls, NOT Sema validation.
- `abs_operand.zig` — **rendered by `c9_p2_controls.py --run` only** (control
  C9P2-32, senior-review BLOCKER): an absolute `@import` operand resets at
  the one resolution seam. No static file can spell the discriminating
  absolute path portably, so the script materializes it at run time; the
  default manifest mode writes nothing.
- `lib_a/opacity.zig` — opaque-skipped 2 vs validated 1.
- `lib_a/escape.zig` — rung-4 sandbox: one import inside lib_a, one escaping.
- `lib_b/wrong_binding.zig` — union green / strict red / ambiguous name.
- `lib_b/unresolved_target.zig` — null `dep_index`: counted refusal.
- `lib_b/unreadable_target.zig` — absent target file: error, not `missing`.
- `lib_t1/checked_twin.zig` — index-fallback green / wrong-twin premise
  red / ambiguous-name refusal.
- `outsider.zig` — membership-premise red when bound to alpha, green unbound.
- `missing_on_disk.zig` — **intentionally absent**: the batch denominator's
  skip-with-reason row.