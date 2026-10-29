//! C9 P2 fixture: the arity pass over the newly supported local shape
//! (retained correction 8). Two DIRECT calls through one function-local
//! const import alias, one fixed-arity match and one mismatch:
//!   * `m.helper()` -- helper is exact_fn(0) in util.zig, called with 0:
//!     arity-MATCHED.
//!   * `m.extfn()` -- extfn is exact_fn(1), called with 0: arity-MISMATCH,
//!     its own argument-count diagnostic.
//! Expected, `--check-decls`: "import sites seen 1: validated 1 (file 0,
//! named 1)", "member refs seen 2: validated 2" (BOTH member names exist and
//! are public -- the arity verdict is additive to the name verdict, exactly
//! as for the root alias shape), "direct calls seen 2: arity-matched 1,
//! arity-mismatch 1", exit 1 from exactly the one mismatch diagnostic. The
//! two populations stay separate denominators: the mismatch never becomes a
//! missing, and no name verdict is affected by an argument count.

pub fn main() void {
    const m = @import("util");
    _ = m.helper();
    _ = m.extfn();
}