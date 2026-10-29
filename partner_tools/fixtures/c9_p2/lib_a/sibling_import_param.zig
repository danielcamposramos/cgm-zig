//! C9 P2 fixture: identical spelling, two sibling scopes, two different
//! owners (retained correction 8). `importer` binds `m` to a direct
//! `@import("util")` -- the one newly followable local shape; `takes` has a
//! PARAMETER named `m` (exercised form: `m: anytype`) whose member access is
//! the same spelling and the same member name. AstGen's sidecar records the
//! EXACT owner of each use -- the local's declaration token for one, the
//! parameter's token for the other -- so the import member is followed and
//! the parameter member is ignored despite byte-identical spelling. A
//! file-global spelling match could not tell them apart; that is the retired
//! approach this control discriminates against.
//! Expected, `--check-decls`: "import sites seen 2: validated 2 (file 0,
//! named 2)", "member refs seen 2: validated 2" (util.answer root contrast +
//! importer's m.helper call), "direct calls seen 1: arity-matched 1"
//! (helper is exact_fn(0), called with 0), exit 0 -- the parameter access
//! lands in no bucket and no diagnostic, and its call would never have
//! entered the arity population either.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}

pub fn importer() void {
    const m = @import("util");
    _ = m.helper();
}

pub fn takes(m: anytype) void {
    _ = m.helper;
}