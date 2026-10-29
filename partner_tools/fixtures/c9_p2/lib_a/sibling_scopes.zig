//! C9 P2 fixture: the sibling-scope name collision (senior review MAJOR on
//! the first integration; retired by retained correction 3; its refusal
//! boundary kept for one shape by retained correction 8). Two function
//! scopes LAWFULLY reuse the local name `m` -- sibling scopes have no
//! shadow relation, so AstGen permits both:
//!   * `importer` binds `m` to `@import("util")` -- import-derived, and
//!     since correction 8 (AstGen's own binding sidecar naming the exact
//!     declaration each use resolved to) FOLLOWED: its `m.helper()` is
//!     validated and its arity compared, exactly like the root alias;
//!   * `unrelated` binds `m` to `Point`, a plain value -- not an import:
//!     the owner is a known local constant but the value is not
//!     import-derived, so its `m.helper` is IGNORED, no bucket, no
//!     diagnostic, never attributed by spelling.
//! The first integration collected local import aliases into file-global
//! sets by name, so BOTH `m.helper` accesses were counted `alias-too-deep`
//! -- attributing an ordinary field access to an import alias. The second
//! refused them into an `alias-name-conflict` bucket, which only renamed
//! the guess: a file-wide spelling set still cannot tell the two accesses
//! apart. Retained correction 3 retired non-root attribution AT ALL;
//! correction 8 restored exactly the one followable local shape by
//! ownership, not by spelling -- the two same-spelled uses now get
//! DIFFERENT verdicts from different exact owners, which no name-level
//! treatment could ever do. `util.answer` (a root simple alias with no
//! local namesake) is the honest contrast: still validated. Expected,
//! `--check-decls`: "member refs seen 2: validated 2" and "direct calls
//! seen 1: arity-matched 1" (importer's call -- helper is exact_fn(0),
//! called with 0; unrelated's call never enters the arity population),
//! exit 0. Compare param_namesake.zig and capture_namesake.zig for the
//! parameter and capture shapes that never had a var-decl node for ANY
//! treatment to see, and alias_too_deep.zig for the counted root-level
//! refusal shapes.

const util = @import("util");

const Point = struct {
    fn helper() void {}
};

pub fn main() void {
    _ = util.answer;
}

pub fn importer() void {
    const m = @import("util");
    _ = m.helper();
}

pub fn unrelated() void {
    const m = Point;
    _ = m.helper;
}