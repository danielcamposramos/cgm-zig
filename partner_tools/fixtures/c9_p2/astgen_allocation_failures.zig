//! C9P2-53 — the bounded AstGen allocation-failure control (retained
//! correction 13; C9 P2 packet, `docs/crown/C9_P2_PACKET_2026-09-12.md`).
//! SOURCE-AUTHORED AND UNEXECUTED: this file is the control's body; its
//! author has not run it, and its two tests are future evidence for the
//! retained reviewer. The future command, run from THIS directory
//! (`partner_tools/fixtures/c9_p2`, the estate's same-cwd contract):
//!
//!     zig test astgen_allocation_failures.zig --zig-lib-dir ../../../lib --test-filter C9P2-53
//!
//! `--zig-lib-dir ../../../lib` selects THIS checkout's authored stdlib — the
//! one carrying retained correction 8's identifier-binding sidecar and
//! correction 13's staged final transfer in `AstGen.generateInner` (the
//! moved-instruction-slice leak the control would otherwise trip on). That
//! flag alone does NOT prove the compiler binary was rebuilt from this
//! checkout: the `zig` on PATH may be any binary, so rebuilt-compiler
//! identity stays the supervising reviewer's canonical build-lock window,
//! not something this control can establish.
//!
//! Proof shape: `std.testing.checkAllAllocationFailures`, the native
//! exhaustive helper — never a fake allocator. It first runs the helper once
//! with unlimited memory (recording the deterministic allocation count),
//! then once per allocation index with exactly that allocation induced to
//! fail. Every induced failure must surface as `error.OutOfMemory` with
//! COMPLETE cleanup through the entry point under test; `error.MemoryLeakDetected`,
//! `error.SwallowedOutOfMemoryError`, and `error.NondeterministicMemoryUsage`
//! are this control's explicit RED outcomes — never caught, mapped, or
//! skipped. The pre-repair prediction, by source reasoning over the
//! pre-correction-13 body, is that the ordinary helper trips
//! `MemoryLeakDetected` (the `instructions` slice moves out before the
//! `string_bytes`/`extra` tries, so a failure after that move leaks it); NO
//! pre-repair red was measured in this wave, and a pre-repair red receipt
//! from this IDENTICAL control shape is required future evidence before any
//! post-repair green is accepted, on an identified rebuilt candidate in the
//! reviewer's canonical build-lock window.
//!
//! The fixed source below is parsed ONCE per test, by
//! `std.testing.allocator`, OUTSIDE the injected-allocator loop: parsing
//! under the failing allocator would exercise parser ownership instead of
//! the AstGen join this control measures. The tree (and every node/token
//! index derived from it) outlives both allocation-failure loops and is
//! released by its authoritative owner, `tree.deinit`.

const std = @import("std");
const Ast = std.zig.Ast;
const AstGen = std.zig.AstGen;

/// One fixed, clean, AstGen-admissible source (no parse errors, no compile
/// errors) carrying the one shape retained correction 8 made observable: a
/// function-local `const` bound DIRECTLY to an `@import` call, plus a
/// meaningful member use of it. `@import("util")` is intentionally
/// unresolved here — AstGen only records the import string; resolving it is
/// Sema's job, and this control never runs Sema.
const fixed_source =
    \\fn usesLocalImport() u32 {
    \\    const m = @import("util");
    \\    return m.answer;
    \\}
    \\
;

/// The ordinary helper: `AstGen.generate` (the null binding observer; zero
/// sidecar bytes requested) under the injected allocator. `tree` arrives as
/// an extra argument, already parsed and owned outside the loop, so every
/// allocation under this helper belongs to the AstGen join under test.
fn c9p2_53OrdinaryGeneration(allocator: std.mem.Allocator, tree: Ast) !void {
    var zir = try AstGen.generate(allocator, tree);
    defer zir.deinit(allocator);

    // The successful unlimited pass must be a real lowering: a merely
    // returned empty `Zir` would make this a vacuous control.
    try std.testing.expect(zir.instructions.len != 0);
}

/// The opt-in helper: `AstGen.generateWithIdentifierBindings` under the
/// injected allocator — the same shared lowering body with the sidecar
/// observer installed, so the allocation-failure sweep must also clean up
/// every sidecar fact on every failure index.
fn c9p2_53OptInGeneration(
    allocator: std.mem.Allocator,
    tree: Ast,
    use_node: Ast.Node.Index,
    decl_token: Ast.TokenIndex,
) !void {
    const generated = try AstGen.generateWithIdentifierBindings(allocator, tree);
    var zir = generated.zir;
    var bindings = generated.bindings;
    defer bindings.deinit(allocator);
    defer zir.deinit(allocator);

    // A real lowering, exactly as in the ordinary helper.
    try std.testing.expect(zir.instructions.len != 0);

    // The sidecar must carry the member-use node's EXACT binding: the use of
    // `m` resolved to the function-local `const` declaration, classified
    // `local_constant` (a `const` bound directly to the `@import` call), with
    // the fact naming that declaration's own token. A valid-but-empty
    // sidecar, an absent fact, a different variant, a different category, or
    // a different declaration token all fail here — this is the control's
    // discrimination, not a mere non-empty assertion.
    const fact = bindings.get(use_node) orelse return error.TestUnexpectedResult;
    switch (fact) {
        .local => |payload| {
            try std.testing.expectEqual(AstGen.IdentifierBindingCategory.local_constant, payload.category);
            try std.testing.expectEqual(decl_token, payload.declaration_token);
        },
        else => return error.TestUnexpectedResult,
    }
}

/// Locate the member-use identifier node for the local import alias `m` in
/// the fixed tree, and the declaration's own NAME token, both indices of
/// the one parsed tree. The member use is an `.identifier` node — the `m`
/// of `m.answer`, its token immediately followed by `.period`. The
/// declaration's name is NOT an identifier node at all: a var declaration
/// stores its mut token, and the name token is `vd.ast.mut_token + 1` —
/// the authoritative structural join `src/AstCheckImports.zig` itself uses
/// (`fullVarDecl` + the token after the mut token), never a guess from
/// punctuation. The fixed source declares exactly one `const m`, so a
/// duplicate or missing join refuses by name instead of guessing.
fn locateLocalImportUse(tree: Ast) !struct {
    use_node: Ast.Node.Index,
    decl_token: Ast.TokenIndex,
} {
    var use_node: ?Ast.Node.Index = null;
    var decl_token: ?Ast.TokenIndex = null;
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @enumFromInt(i);
        switch (tree.nodeTag(node)) {
            .identifier => {
                const tok = tree.nodeMainToken(node);
                if (!std.mem.eql(u8, tree.tokenSlice(tok), "m")) continue;
                if (tree.tokenTag(tok + 1) != .period) continue;
                if (use_node != null) return error.DuplicateUseSpelling;
                use_node = node;
            },
            // The declaration owner: `fullVarDecl` accepts the four var-decl
            // node shapes and exposes the mut token; require `const` (the
            // sidecar's `local_constant` category is the const-bound local)
            // and take the token right after it as the declaration name.
            // This is the same join the rung-2 checker trusts for name
            // ownership — no second parser, no punctuation inference.
            else => {
                const vd = tree.fullVarDecl(node) orelse continue;
                if (tree.tokenTag(vd.ast.mut_token) != .keyword_const) continue;
                const name_tok = vd.ast.mut_token + 1;
                if (!std.mem.eql(u8, tree.tokenSlice(name_tok), "m")) continue;
                if (decl_token != null) return error.DuplicateDeclSpelling;
                decl_token = name_tok;
            },
        }
    }
    return .{
        .use_node = use_node orelse return error.UseNotFound,
        .decl_token = decl_token orelse return error.DeclNotFound,
    };
}

test "C9P2-53: generate survives every injected allocation failure" {
    // Parse once, by the leak-checked testing allocator, outside the
    // injected-allocator loop; the tree's lifetime ends at this scope's
    // `deinit`, after both of the helper's loops have finished.
    const gpa = std.testing.allocator;
    var tree = try Ast.parse(gpa, fixed_source, .zig);
    defer tree.deinit(gpa);

    try std.testing.checkAllAllocationFailures(gpa, c9p2_53OrdinaryGeneration, .{tree});
}

test "C9P2-53: generateWithIdentifierBindings survives every injected allocation failure" {
    // Same parse-once discipline as the ordinary test; the located node and
    // declaration token are indices of this same tree and outlive the loop.
    const gpa = std.testing.allocator;
    var tree = try Ast.parse(gpa, fixed_source, .zig);
    defer tree.deinit(gpa);

    const located = try locateLocalImportUse(tree);
    try std.testing.checkAllAllocationFailures(
        gpa,
        c9p2_53OptInGeneration,
        .{ tree, located.use_node, located.decl_token },
    );
}