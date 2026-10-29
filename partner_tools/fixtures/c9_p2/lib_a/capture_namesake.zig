//! C9 P2 fixture: the capture-payload namesake (retained correction 3; its
//! refusal kept by retained correction 8). A capture payload is spelled
//! EXACTLY like an unrelated function-local import alias in a different
//! scope:
//!   * `importer` binds `m` to `@import("util")` -- the one followable
//!     local shape since correction 8 (AstGen's sidecar names the exact
//!     declaration), so its `m.answer` is VALIDATED;
//!   * `captures` reads `m.helper` off the payload of
//!     `if (maybePoint()) |m|` -- the ONE capture form this file exercises.
//! Captures bind with NO var-decl node, exactly like parameters, so the
//! retired var-decl-scoped binding sets never saw them -- and the earlier
//! file-global name sets falsely counted `captures`'s ordinary field
//! access as alias-too-deep. Correction 3 retired attributing non-root
//! bindings AT ALL; correction 8 restored the one followable local shape
//! by OWNERSHIP, and the sidecar now records the capture's own token and
//! category `capture` for this use -- a known LEXICAL owner whose value
//! provenance no syntactic walk can know -- so it stays ignored while the
//! same-spelled import binding beside it is followed. A file-wide spelling
//! set is still not ownership whichever bucket it feeds. Expected,
//! `--check-decls`: "member refs seen 2: validated 2" and "direct calls
//! seen 0", exit 0 -- the capture access is ignored, not counted, and not
//! failed.
//!
//! Exercised discrimination, EXACTLY: the `if (<optional>) |m|` capture
//! form beside a followed same-spelling import. The other capture forms
//! are exercised as ignored shapes by correction 8's own controls
//! (capture_forms.zig: if/while/for/pointer; capture_forms2.zig: switch
//! payload/tag, catch/error, errdefer) -- unsupported by the same rule,
//! each with its own control. See param_namesake.zig for the parameter
//! form, sibling_scopes.zig for the sibling-var form.

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

pub fn captures() void {
    if (maybePoint()) |m| {
        _ = m.helper;
    }
}

pub fn importer() void {
    const m = @import("util");
    _ = m.answer;
}