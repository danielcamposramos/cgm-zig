//! C9 P2 fixture: the remaining capture producers, same spelling, same
//! zero-attribution rule (retained correction 8). Every capture below is
//! spelled like a value-carrying local and accessed through a member
//! reference, so the walk must DECIDE about each one; AstGen's sidecar
//! records the exact owner (category `capture`, or `switch tag capture` for
//! the tag), so each is ignored as known-owner/unknown-provenance, never
//! attributed by spelling. The exercised forms:
//!   * `switch (v) { .a => |m, t| ... }` -- switch PAYLOAD capture (`m`) and
//!     the TAG capture (`t`) in this tree's one combined prong-capture
//!     syntax;
//!   * `.b => |m2|` -- a second prong's payload capture, sibling scope;
//!   * `mightFailPoint() catch |m|` -- catch (error) capture;
//!   * `if (mightFailPoint()) |m| ... else |m|` -- the success payload and
//!     the error capture of the if-error form, one spelling twice;
//!   * `errdefer |m|` -- the errdefer error capture.
//! Expected, `--check-decls`: "import sites seen 2: validated 2 (file 0,
//! named 2)" (root util + importer's local util), "member refs seen 2:
//! validated 2" (root util.answer + importer's m.answer), "direct calls seen
//! 0", exit 0. Every captured access -- m.helper, t.whatever, m2.whatever,
//! and all four error-side accesses -- lands in NO bucket and NO diagnostic.

const util = @import("util");

const Point = struct {
    helper: u8,
};

const Val = union(enum) {
    a: Point,
    b: u8,
};

const E = error{Boom};

fn mightFailPoint() E!Point {
    return Point{ .helper = 1 };
}

pub fn main() void {
    _ = util.answer;
}

pub fn importer() void {
    const m = @import("util");
    _ = m.answer;
}

pub fn switch_caps() void {
    const v: Val = .{ .a = Point{ .helper = 1 } };
    switch (v) {
        .a => |m, t| {
            _ = m.helper;
            _ = t.whatever;
        },
        .b => |m2| {
            _ = m2.whatever;
        },
    }
}

pub fn catch_cap() void {
    mightFailPoint() catch |m| {
        _ = m.helper;
        return;
    };
}

pub fn if_err_cap() void {
    if (mightFailPoint()) |m| {
        _ = m.helper;
    } else |m| {
        _ = m.helper;
    }
}

pub fn errdefer_cap() E!void {
    errdefer |m| {
        _ = m.helper;
    };
    return;
}