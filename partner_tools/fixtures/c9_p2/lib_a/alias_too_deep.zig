//! C9 P2 fixture: the alias-discrimination file. Three flows into util's
//! namespace, each judged by its exact owner (retained correction 8):
//!   * `util.answer` -- a file-scope const bound DIRECTLY to @import, the
//!     root followable alias shape -> validated.
//!   * `chained.answer` -- a file-scope const bound to another NAME (a
//!     chain, however short): deeper than one hop -> alias-too-deep.
//!   * `local_import.helper()` -- a FUNCTION-LOCAL const bound directly to
//!     @import: since retained correction 8 (AstGen's own binding sidecar)
//!     this is the one newly followable local shape -> validated, and its
//!     call enters the arity population with a match.
//! Expected, `--check-decls`: "import sites seen 2: validated 2 (file 0,
//! named 2)", "member refs seen 3: validated 2, ... alias-too-deep 1" and
//! "direct calls seen 1: arity-matched 1", exit 0 -- a counted refusal
//! is not a failure, the chain stays in the denominator rather than
//! silently becoming validated (false green) or vanishing (short
//! denominator), and the local binding is judged by its own declaration,
//! not a file-wide name.
//!
//! Design note, measured against this tree: the shape first sketched for
//! this control -- a function-local binding sharing the file-scope alias's
//! NAME -- cannot reach rung 2 at all. `detectLocalShadowing` fails such a
//! file at AstGen with "local shadows declaration" (lib/std/zig/AstGen.zig,
//! reached from localVarDecl), so ast-check would report the compile error
//! and never run the decl check. The shapes above are the reachable ones;
//! see the C9 P2 packet for the premise correction.
//!
//! Succession (doctrine 7): this file's local binding was first counted
//! alias-too-deep (file-global name sets), then was the unambiguous
//! conflict-free local case of the var-decl-scoped sets, and then -- after
//! retained correction 3 retired non-root attribution AT ALL, stating there
//! was "no binder here" and that "AstGen's own private Scope map is
//! authoritative while lowering, but it is not exported to this owner" --
//! was IGNORED entirely. Retained correction 8 ended that stance by
//! exporting the owner's own decisions, so the local direct-const import is
//! now followed through exactly the same target/arity owners as the root
//! alias. The still-ignored shapes -- sibling-scope var, parameter,
//! capture, ordinary and mutable and chained locals -- live in
//! sibling_scopes.zig, param_namesake.zig, capture_namesake.zig, and
//! local_unknowns.zig.

const util = @import("util");
const chained = util;

pub fn main() void {
    _ = util.answer;
}

pub fn deep() void {
    const local_import = @import("util");
    _ = local_import.helper();
}

pub fn chain() void {
    _ = chained.answer;
}