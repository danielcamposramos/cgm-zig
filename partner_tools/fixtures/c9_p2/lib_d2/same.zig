//! C9 P2 fixture: the other half of the ambiguous "shared" pair -- same
//! declaration surface plus a distinct spelling, DIFFERENT module root
//! (lib_d2 vs lib_d1), which is what makes the import name "shared" map to
//! two distinct targets across the graph-wide union. Retained correction 6:
//! under `--as-module=c9p2.alpha` rung 2 selects alpha's own edge (index 4,
//! lib_d1/same.zig), so THIS module is never read for the "shared" spelling
//! and `onlyD2` below is the deliberately MISSING member of the strict
//! selection control. See lib_d1/same.zig's header for the pairing.

pub fn sameFn() void {}

pub fn onlyD2() void {}