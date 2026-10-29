//! C9 P2 fixture: the parameter namesake (retained correction 3; its
//! refusal kept by retained correction 8). A function parameter is spelled
//! EXACTLY like an unrelated function-local import alias in a different
//! scope:
//!   * `importer` binds `m` to `@import("util")` -- the one followable
//!     local shape since correction 8 (AstGen's sidecar names the exact
//!     declaration), so its `m.answer` is VALIDATED;
//!   * `takes` has a PARAMETER named `m` (exercised form: `m: anytype`)
//!     and reads `m.helper` off it.
//! Parameters bind with NO var-decl node, so the retired var-decl-scoped
//! binding sets never saw them -- and the earlier file-global name sets
//! falsely counted `takes`'s ordinary field access as alias-too-deep.
//! Correction 3 retired attributing non-root bindings AT ALL; correction 8
//! restored the one followable local shape by OWNERSHIP, and this file now
//! discriminates the two same-spelled uses apart: the sidecar records the
//! parameter's own token and category `function_parameter` for `takes`'s
//! use -- a known LEXICAL owner whose value provenance no syntactic walk
//! can know -- so it stays ignored while the import binding beside it is
//! followed. Adding parameter spellings to a file-wide set remains the
//! retired blacklist wearing a new bucket. Expected, `--check-decls`:
//! "member refs seen 2: validated 2" and "direct calls seen 0", exit 0 --
//! the parameter access is ignored, not counted, and not failed.
//!
//! Exercised discrimination, EXACTLY: the `m: anytype` parameter form
//! beside a followed same-spelling import. Other parameter forms are
//! unsupported by the same rule and UNPROVEN; nothing here generalizes to
//! them. See capture_namesake.zig for the one exercised capture form,
//! sibling_scopes.zig for the sibling-var form.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
}

pub fn takes(m: anytype) void {
    _ = m.helper;
}

pub fn importer() void {
    const m = @import("util");
    _ = m.answer;
}