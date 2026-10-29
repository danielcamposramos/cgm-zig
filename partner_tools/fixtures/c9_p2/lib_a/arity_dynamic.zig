//! C9 P2 fixture: the dynamic-shape file (retained arity dispatch;
//! extended by Sol review correction 5 to exercise all THREE dynamic
//! syntaxes). Every callee is a declaration whose parameter count is NOT
//! a fixed syntactic fact, each deliberately unsuitable for naive
//! equality:
//!   * `util.generic(u32, 1)` -- generic declares `comptime T: type,
//!     value: T`, TWO parameters, and the call supplies TWO arguments:
//!     a naive count would call this a match;
//!   * `util.varargs("fmt", 1, 2)` -- varargs declares one fixed
//!     parameter plus `...`: a naive count would call this a mismatch
//!     (3 arguments vs a "count" of 1 or 2, depending on the guess);
//!   * `util.anyfn(1)` -- anyfn declares `value: anytype`, the distinct
//!     `FnProto.Iterator.Param` `.anytype_ellipsis3` branch, which the
//!     comptime and variadic calls above never touch: one argument
//!     against an `anytype` parameter that is not even in the params
//!     slice. Correction 5's gap: the earlier body of this file left
//!     that branch unexercised.
//! All three are dynamic_fn -- counted arity-skipped-dynamic, NEVER
//! compared -- so this file would produce one false match and one false
//! mismatch under naive equality, and produces neither here. All three
//! members are name-validated. Expected, `--check-decls`: "member refs
//! seen 3: validated 3" and "direct calls seen 3: arity-skipped-dynamic
//! 3", exit 0 -- no arity error anywhere, and no type or generic
//! correctness claimed: these remain counted skips.

const util = @import("util");

pub fn main() void {
    _ = util.generic(u32, 1);
    _ = util.varargs("fmt", 1, 2);
    _ = util.anyfn(1);
}