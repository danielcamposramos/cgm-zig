//! C9 P2 fixture: the rung-2 red. Three member references through a lawfully
//! imported module, each naming a declaration util.zig does not expose as
//! public: `nope_missing` and `also_missing` exist nowhere; `hidden` exists
//! but is not public. Rung 1 is green here (the import name "util" is
//! registered in the graph's union), and that is the point: this file is the
//! "syntax clean, dies minutes later in the compile" class PLAN.md charters
//! rung 2 to catch in seconds. Expected, `--check-decls`: "member refs seen
//! 3: validated 0, missing 3" and "direct calls seen 0" (no direct calls in
//! this file), exit 1.

const util = @import("util");

pub fn main() void {
    _ = util.nope_missing;
    _ = @import("util").also_missing;
    _ = util.hidden;
}