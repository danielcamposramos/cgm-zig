//! C9 P2 fixture: the all-green member of `c9p2.alpha`. Every member
//! reference resolves through the graph edge "util" to util.zig and names a
//! public declaration there -- including `extfn`, an extern PROTOTYPE (the
//! BLOCKER 1 shape: a rung 2 collecting only `.fn_decl` would report this as
//! missing), and the inline `@import("util").answer` (shape (a)). `const
//! util` is a file-scope const bound directly to the @import call -- the one
//! followable alias shape (b).
//!
//! Expected: flagless ast-check exits 0 with no output; `--module-graph=
//! graph.json` alone exits 0 with "import sites seen 2: validated 2 (file 0,
//! named 2)"; `--check-decls` additionally reports "member refs seen 4:
//! validated 4" and "direct calls seen 2: arity-matched 2" (the two direct
//! calls, util.helper() and util.extfn(1), whose targets are exact_fn(0) and
//! exact_fn(1); the two `answer` references are not calls and contribute
//! nothing to the arity denominator) and exits 0; `--as-module=c9p2.alpha`
//! (this file IS inside lib_a, and alpha declares "util") stays green under
//! strict semantics.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
    _ = util.helper();
    _ = util.extfn(1);
    _ = @import("util").answer;
}