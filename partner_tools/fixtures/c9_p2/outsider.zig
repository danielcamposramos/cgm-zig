//! C9 P2 fixture: a well-formed file that lives at the fixture root -- inside
//! c9p2.util's root (".") but NOT inside c9p2.alpha's (lib_a). Unbound, rungs
//! 1 and 2 pass it clean (the import name "util" is registered and the
//! reference is valid). Bound with `--as-module=c9p2.alpha`, the rung-4
//! membership premise must fail BY NAME before any import verdict is
//! trusted. Same bytes, opposite verdicts; the discrimination is the
//! control.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}