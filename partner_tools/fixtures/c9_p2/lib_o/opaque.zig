//! C9 P2 fixture: the comptime-opaque target (graph.json index 3, reached by
//! the import name "opaque_mod"). Its top level holds a comptime block, so
//! rung 2 must treat the whole module as opaque to name-level analysis:
//! every member reference into it is counted `opaque-skipped`, nothing
//! guessed -- even though `opFn` is right there and public.

comptime {
    // The block need only exist and parse; its body is irrelevant here.
}

pub fn opFn() void {}