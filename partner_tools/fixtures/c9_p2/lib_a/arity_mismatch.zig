//! C9 P2 fixture: the arity-mismatch file (retained arity dispatch). Two
//! direct calls through the root alias, one in each direction:
//!   * `util.helper(1)` -- helper is exact_fn(0), the call supplies 1:
//!     too many;
//!   * `util.extfn()` -- extfn is exact_fn(1), the call supplies 0: too few.
//! Both members EXIST, so both calls are still name-validated (validated 3;
//! no "referenced declaration not found"): arity is ADDITIVE to existence,
//! and each mismatch produces its own argument-count diagnostic while the
//! name verdict stays green. The third call is the INLINE contrast
//! `@import("util").helper()` -- exact match -- so the same control pins
//! shape (a) and shape (b) callees in one file.
//! Expected, `--check-decls`: "member refs seen 3: validated 3" and
//! "direct calls seen 3: arity-matched 1, arity-mismatch 2", exit 1 -- the
//! two arity errors are the only failures.

const util = @import("util");

pub fn main() void {
    _ = util.helper(1);
    _ = util.extfn();
    _ = @import("util").helper();
}