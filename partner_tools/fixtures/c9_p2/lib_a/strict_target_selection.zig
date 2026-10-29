//! C9 P2 fixture: binding-strict rung-2 target selection (retained
//! correction 6). Two member references through the one supported alias
//! shape (b) -- a root/file-scope const bound DIRECTLY to the named
//! import "shared", the spelling the graph maps to TWO distinct targets:
//!   * UNBOUND `--check-decls` (C9P2-41): the graph-wide conservative
//!     union sees alpha's edge "shared" -> index 4 (lib_d1/same.zig) and
//!     dupe_a's edge "shared" -> index 5 (lib_d2/same.zig) -- a conflict,
//!     so BOTH references are counted `target-unresolvable`: exit 0, a
//!     counted refusal, never a guess.
//!   * BOUND `--as-module=c9p2.alpha` + `--check-decls` (C9P2-42): rung
//!     2 selects named targets through exactly alpha's own dependency
//!     table, whose "shared" edge is index 4 ONLY -- so `onlyD1`
//!     (declared in lib_d1/same.zig) is VALIDATED and `onlyD2` (declared
//!     only in lib_d2/same.zig, a module alpha does not reach under this
//!     name) is MISSING: one file gives positive and negative
//!     target-selection discrimination and proves the checker did not
//!     scan both target files for whichever spelling exists.
//! Expected counts: "import sites seen 1: validated 1 (file 0, named 1)"
//! in both runs (the union accepts "shared"; alpha declares it);
//! "member refs seen 2" in both runs; unbound: validated 0, missing 0,
//! target-unresolvable 2; bound: validated 1, missing 1,
//! target-unresolvable 0, exit 1 from exactly the one missing-declaration
//! diagnostic. "direct calls seen 0" in both runs -- these are plain
//! references, never calls, so the arity denominator stays zero and no
//! unresolved or missing target ever becomes an arity mismatch.

const shared = @import("shared");

pub fn main() void {
    _ = shared.onlyD1;
    _ = shared.onlyD2;
}