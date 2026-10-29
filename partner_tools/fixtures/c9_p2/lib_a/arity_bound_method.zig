//! C9 P2 fixture: the receiver-sugar and deeper-qualified negative control
//! (retained arity dispatch; reshaped by Sol review correction 5). Two
//! syntactic discriminators, both OUTSIDE the arity population:
//!   * `util.Thing.staticCall()` -- a DEEPER QUALIFIED (type-namespace)
//!     call: its callee is the OUTER two-hop field access
//!     `util.Thing.staticCall`, never a supported member reference, so
//!     nothing from this call enters the arity denominator; the INNER
//!     `util.Thing` is a plain member reference and is name-validated
//!     (Thing is public).
//!   * `thing.method()` -- an ACTUAL receiver-sugar method call:
//!     `method` takes an explicit `self: Thing` in the target, and
//!     `thing` is a local value whose type is spelled through
//!     `util.Thing` (so THAT member reference is name-validated too).
//!     The callee field access `thing.method` has a NON-import
//!     identifier LHS -- an ignored unsupported shape: no bucket, no
//!     diagnostic, and no implicit receiver ever inferred or compared.
//!     The value-receiver question is outside this pass by rule, not
//!     approximated.
//! Correction 5 note: the earlier body of this control called the
//! `util.Thing.method()` type-namespace expression a "bound method" -- a
//! false name; it never had a receiver. Both discriminators now live in
//! this one control.
//! Expected, `--check-decls`: "member refs seen 2: validated 2" (the
//! inner `util.Thing` of the deeper-qualified chain, and the
//! `util.Thing` type annotation that spells the value's type) and
//! "direct calls seen 0" with every arity bucket zero, exit 0. This is
//! a SYNTACTIC negative control -- it pins the population boundary, not
//! any Sema claim about method calls or receivers, which stay the
//! compiler's job. No Sema behavior was executed or is claimed.

const util = @import("util");

pub fn main() void {
    util.Thing.staticCall();
    const thing: util.Thing = undefined;
    thing.method();
}