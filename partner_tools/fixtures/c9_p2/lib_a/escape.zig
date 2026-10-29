//! C9 P2 fixture: the rung-4 sandbox file. Both imports EXIST on disk and
//! are perfectly legal code: `nested_ok.zig` sits inside c9p2.alpha's root
//! (lib_a); `../util.zig` escapes it into the fixture root. Rung 1 alone
//! validates both ("file 2"). Under `--as-module=c9p2.alpha` the second must
//! be refused as leaving the module's root -- a strictness that flag CHOOSES,
//! not a compiler rule (the compiler enforces no @import sandbox today; only
//! @embedFile refuses an outside-package path), and the violation text says
//! so rather than implying parity.

pub fn main() void {
    _ = @import("nested_ok.zig");
    _ = @import("../util.zig");
}