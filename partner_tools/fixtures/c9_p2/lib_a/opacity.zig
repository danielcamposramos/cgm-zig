//! C9 P2 fixture: the opacity file. `op.anything` reaches opaque.zig, whose
//! top level holds a comptime block -- name-level analysis cannot see through
//! it, so every member ref into it is counted opaque-skipped, nothing
//! guessed. `data.anything` reaches a .zon file -- data, not declarations:
//! opaque the same way. `util.answer` is the honest contrast: a real,
//! validated reference in the same file. Expected, `--check-decls` (with or
//! without `--as-module=c9p2.alpha`, which declares all three imports and
//! contains this file): "member refs seen 3: validated 1, opaque-skipped 2"
//! and "direct calls seen 0" (no direct calls in this file), exit 0; strict
//! import summary "file 1, named 2".

const op = @import("opaque_mod");
const util = @import("util");
const data = @import("data.zon");

pub fn main() void {
    _ = op.anything;
    _ = data.anything;
    _ = util.answer;
}