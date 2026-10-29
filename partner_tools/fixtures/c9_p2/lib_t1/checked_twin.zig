//! C9 P2 fixture: a member of the FIRST twin (graph index 6, root lib_t1).
//! `--as-module=6` binds it correctly and passes strict (index fallback:
//! "c9p2.twin" is ambiguous, so only the index disambiguates);
//! `--as-module=7` binds the OTHER twin (root lib_t2), and the membership
//! premise must fail by name; `--as-module=c9p2.twin` must refuse as
//! ambiguous, listing both indices. Three flag spellings, three distinct
//! named outcomes.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}