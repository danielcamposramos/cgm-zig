//! C9 P2 fixture: the missing-member direct call (retained arity dispatch).
//! `util.nope_missing(1)` names a declaration that does not exist: the
//! primary verdict is the missing error, and the arity verdict is
//! `arity-unavailable` -- there is no target shape to compare, so NO
//! argument-count mismatch diagnostic is stacked on top of the missing
//! error. Half the control is the absence: "direct calls seen 1:
//! arity-unavailable 1" with no "argument-count mismatch" anywhere.
//! Expected, `--check-decls`: "member refs seen 1: missing 1", exit 1 --
//! the missing diagnostic is the failure, the only one.

const util = @import("util");

pub fn main() void {
    _ = util.nope_missing(1);
}