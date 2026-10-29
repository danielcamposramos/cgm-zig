//! C9 P2 fixture: capture forms sharing an import alias's spelling
//! elsewhere (retained correction 8; the while and pointer forms made
//! unambiguously AstGen-admissible by retained correction 9). Every capture
//! below is spelled `m` EXACTLY like the function-local import binding in
//! the sibling `importer` scope, and each member access goes through the
//! capture: AstGen's sidecar records each use's exact owner -- category
//! `capture`, the capture's declaration token -- so every one of them is a
//! known LEXICAL owner with UNKNOWN value provenance and is ignored, never
//! attributed to the sibling import by spelling. The exercised forms:
//!   * `if (maybePoint()) |m|` -- optional payload capture;
//!   * `const opt = maybePoint(); while (opt) |m|` -- while payload capture
//!     reading a CONST optional, so no mutable local is involved at all
//!     (correction 9: the admissible shape, never a never-mutated `var`);
//!   * `for (list) |m|` -- for payload capture;
//!   * `var opt = maybePoint(); if (opt) |*m| { m.helper = 2; }` -- pointer
//!     payload capture from a separate MUTABLE optional lvalue, so the
//!     payload write is a real mutation of that var (correction 9: never a
//!     pointer capture from a call-result temporary).
//! Expected, `--check-decls`: "import sites seen 2: validated 2 (file 0,
//! named 2)" (root util + importer's local util), "member refs seen 2:
//! validated 2" (the root util.answer contrast and importer's m.answer --
//! the one followable local shape), "direct calls seen 0", exit 0. All four
//! captured `m.helper` accesses land in NO bucket and NO diagnostic; a
//! file-global spelling match would have counted all of them.

const util = @import("util");

const Point = struct {
    helper: u8,
};

fn maybePoint() ?Point {
    return Point{ .helper = 1 };
}

pub fn main() void {
    _ = util.answer;
}

pub fn importer() void {
    const m = @import("util");
    _ = m.answer;
}

pub fn if_cap() void {
    if (maybePoint()) |m| {
        _ = m.helper;
    }
}

pub fn while_cap() void {
    const opt = maybePoint();
    while (opt) |m| {
        _ = m.helper;
        break;
    }
}

pub fn for_cap() void {
    const list = [_]Point{.{ .helper = 1 }};
    for (list) |m| {
        _ = m.helper;
    }
}

pub fn ptr_cap() void {
    var opt = maybePoint();
    if (opt) |*m| {
        m.helper = 2;
    }
}