//! C9 P2 fixture: one spelling, two sibling locals, two DIFFERENT targets
//! (retained correction 8). `first` binds `m` to the named import "util"
//! (graph edge to util.zig); `second` binds `m` to the FILE import
//! "nested_ok.zig" (lib_a/nested_ok.zig, exposing only `nestedFn`). Each
//! member access must follow exactly its own declaration's target: `m.helper`
//! validates against util.zig, `m.nestedFn` against nested_ok.zig. A
//! file-global spelling behavior -- one set entry for `m`, whichever
//! declaration wrote last -- would resolve one of the two through the wrong
//! file and report a false missing; this control fails under that retired
//! approach and passes only under per-use facts.
//! Expected, `--check-decls`: "import sites seen 3: validated 3 (file 1,
//! named 2)" (root util, local util -- named -- and local nested_ok.zig --
//! a file import), "member refs seen 3: validated 3" (root util.answer
//! contrast plus both local accesses), "direct calls seen 2: arity-matched 2"
//! (helper exact_fn(0) called 0, nestedFn exact_fn(0) called 0), exit 0.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}

pub fn first() void {
    const m = @import("util");
    _ = m.helper();
}

pub fn second() void {
    const m = @import("nested_ok.zig");
    _ = m.nestedFn();
}