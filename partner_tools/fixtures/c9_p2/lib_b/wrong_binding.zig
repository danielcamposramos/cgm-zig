//! C9 P2 fixture: the union-vs-strict discriminator. "shared" IS declared
//! somewhere in the graph (c9p2.alpha declares it as dupe_a; c9p2.dupe_a
//! declares it as dupe_b), so rung 1's graph-wide union accepts the import
//! -- but c9p2.beta declares no such dependency, so `--as-module=c9p2.beta`
//! must refuse it by name under strict semantics. The file is ALSO the
//! ambiguous-name case for rung 2: "shared" maps to two distinct targets
//! across the graph, so `--check-decls` (no binding) counts `shared.sameFn`
//! as target-unresolvable -- counted, exit 0, never a guess. Same bytes,
//! three different verdicts depending on which flags are set; that is the
//! point.

const shared = @import("shared");

pub fn main() void {
    _ = shared.sameFn;
}