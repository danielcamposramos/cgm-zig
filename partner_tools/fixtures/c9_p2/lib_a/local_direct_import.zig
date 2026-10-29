//! C9 P2 fixture: the one newly supported non-root shape (retained
//! correction 8 -- AstGen-owned lexical binding sidecar). A FUNCTION-LOCAL
//! `const` bound directly to a parseable `@import` is shape (b) now: AstGen's
//! own `localVarRef` records which exact declaration each use resolved to,
//! and rung 2 inspects THAT declaration's initializer -- never a file-wide
//! spelling match -- so this binding is followed exactly like the root alias
//! always was, while every other local shape stays ignored.
//!   * `m.answer` -- public const in util.zig: VALIDATED.
//!   * `m.hidden` -- declared in util.zig but NOT public: MISSING, the
//!     diagnostic that makes the exit 1.
//! Expected, `--check-decls`: "import sites seen 1: validated 1 (file 0,
//! named 1)" (the local @import("util") is a rung-1 site like any other),
//! "member refs seen 2: validated 1, missing 1", "direct calls seen 0" (both
//! references are plain, never calls), exit 1. Under the retired
//! correction-3 rule this whole file's member refs were ignored -- the
//! succession is quoted in the packet, not denied.

pub fn main() void {
    const m = @import("util");
    _ = m.answer;
    _ = m.hidden;
}