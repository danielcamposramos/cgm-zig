//! C9 P2 fixture: the null-dep_index case. The graph records the import name
//! "broken" (declared by c9p2.dupe_b) with dep_index null -- stage 0's own
//! "dependency module not found in module_roots" value. Rung 1 accepts the
//! name (it is in the union); rung 2 cannot resolve it to a concrete file, so
//! the member reference is counted target-unresolvable and the run stays
//! exit 0: an unresolvable resolution is a refused check, not a verdict
//! about the program.

const broken = @import("broken");

pub fn main() void {
    _ = broken.anything;
}