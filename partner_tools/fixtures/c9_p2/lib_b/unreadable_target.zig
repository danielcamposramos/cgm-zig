//! C9 P2 fixture: the unreadable-target case. "ghost_mod" resolves through
//! the graph to lib_g/ghost_src.zig, which deliberately does NOT exist on
//! disk. The check was requested and cannot honestly run, so rung 2 refuses
//! it as an ERROR (target-unreadable, exit 1) -- deliberately distinct from
//! `missing`, which says the declaration was looked for and is not there.
//! "missing 0" in this file's summary is half the control: an unreadable
//! target must never masquerade as a checked-and-not-found declaration.

const ghost = @import("ghost_mod");

pub fn main() void {
    _ = ghost.thing;
}