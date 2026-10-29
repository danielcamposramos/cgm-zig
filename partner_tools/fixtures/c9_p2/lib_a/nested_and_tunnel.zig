//! C9 P2 fixture: nested namespace declaration versus closure-tunneled
//! root reference (retained correction 8). Two facts about one spelling of
//! ownership:
//!   * `S.x` -- `S` is a FUNCTION-LOCAL container declaration. AstGen
//!     resolved the use to that exact local constant; its initializer is a
//!     struct declaration, not a direct `@import`, so the reference is
//!     IGNORED -- a nested namespace's own declaration is never promoted to
//!     root by its spelling.
//!   * `util.answer` inside `Inner.method` -- a ROOT declaration referenced
//!     from within a generic namespace nested inside a function, the shape
//!     AstGen routes through `tunnelThroughClosure`. The sidecar records the
//!     binding BEFORE the tunnel transforms it, so the fact stays the exact
//!     root declaration node and the reference is VALIDATED -- tunneling
//!     cannot erase lexical ownership.
//! Expected, `--check-decls`: "import sites seen 1: validated 1 (file 0,
//! named 1)", "member refs seen 2: validated 2" (main's util.answer and the
//! tunneled one), "direct calls seen 0" (`Inner.method()` goes through the
//! ignored nested-namespace local, so it never enters the arity population),
//! exit 0.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}

pub fn nester() void {
    const S = struct {
        pub const x: u8 = 1;
    };
    _ = S.x;
}

pub fn tunnel() void {
    const Inner = struct {
        pub fn method() void {
            _ = util.answer;
        }
    };
    Inner.method();
}