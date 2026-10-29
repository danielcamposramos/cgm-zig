//! C9 P2 fixture: the known-owner/unknown-provenance boundary (retained
//! correction 8). Three local shapes that share nothing followable:
//!   * `ordinary`: a local `const` whose initializer is an ordinary value
//!     (the root container `Point`) -- the owner is known (a local constant)
//!     but the value is not an import: IGNORED.
//!   * `mutable`: a local `var` initialized from an import and genuinely
//!     reassigned to a DIFFERENT module mid-function -- reassignable, so
//!     which module it holds at a given use is exactly what a syntactic walk
//!     cannot know: IGNORED (and its call never enters the arity population).
//!   * `chained`: a local `const` bound to the root alias NAME (`util`) -- a
//!     local alias chain, deeper than the direct shape: IGNORED.
//! All three spellings are distinct from any root alias, so nothing here
//! discriminates by spelling; the point is the boundary. The root simple
//! alias contrast stays validated.
//! Expected, `--check-decls`: "import sites seen 3: validated 3 (file 1,
//! named 2)" (root util, the var's "util", and the reassignment's
//! "nested_ok.zig" file import -- rung 1 counts every @import site), "member
//! refs seen 1: validated 1" (only util.answer; ordinary's m.helper(),
//! mutable's m.helper(), and chained's m.answer all land in NO bucket), "direct
//! calls seen 0", exit 0 -- zero invented name or arity results.

const util = @import("util");

const Point = struct {
    pub fn helper() void {},
};

pub fn main() void {
    _ = util.answer;
}

pub fn ordinary() void {
    const m = Point;
    _ = m.helper();
}

pub fn mutable() void {
    var m = @import("util");
    m.helper();
    m = @import("nested_ok.zig");
}

pub fn chained() void {
    const m = util;
    _ = m.answer;
}