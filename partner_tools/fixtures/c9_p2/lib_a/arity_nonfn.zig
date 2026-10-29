//! C9 P2 fixture: the non-fn-declaration file (retained arity dispatch).
//! `util.fnval` is a public const of function type in the target --
//! syntactically a NON-fn root declaration, but it may be function-valued
//! after Sema, so the arity pass never calls it non-callable and never
//! compares a count: `other_decl`, counted arity-skipped-non-fn, no arity
//! error. The name verdict is unaffected: `fnval` exists and is public, so
//! the member ref is validated. Expected, `--check-decls`: "member refs
//! seen 1: validated 1" and "direct calls seen 1: arity-skipped-non-fn 1",
//! exit 0 -- a skipped outcome is never a failure.

const util = @import("util");

pub fn main() void {
    _ = util.fnval(1);
}