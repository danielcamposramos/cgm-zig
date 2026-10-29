//! C9 P2 fixture: one half of the ambiguous "shared" pair. The graph records
//! TWO distinct modules reached under the same import name by different
//! importers: c9p2.alpha declares "shared" -> c9p2.dupe_a (this file,
//! lib_d1/same.zig) while c9p2.dupe_a declares "shared" -> c9p2.dupe_b
//! (lib_d2/same.zig). Name-level resolution cannot pick one, so UNBOUND rung 2
//! must collapse the name and count every reference through it
//! `target-unresolvable` -- never guess. Retained correction 6 adds the
//! binding-strict counterpart: when the checked file is bound as alpha
//! (`--as-module=c9p2.alpha`), rung 2 selects exactly THIS module (graph index
//! 4) through alpha's own dep table, so `onlyD1` below is VALIDATED while
//! lib_d2's `onlyD2` is MISSING -- positive and negative target-selection
//! discrimination from one file. `sameFn` stays for the pre-existing
//! union-verdict controls.

pub fn sameFn() void {}

pub fn onlyD1() void {}