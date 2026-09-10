//! Build glue for the machine tree: it resolves the two declared options, wires
//! the renderer as a build step, and hands back the paths the FINAL compiler
//! executable is built from.
//!
//! SCOPE, and it is deliberately narrow: only the final `zig` executable is
//! compiled from the MR tree. Development builds, the unit tests, the autodoc
//! object and every tool keep compiling the commented sources exactly as they do
//! today. Without `-Dmachine-tree` this module contributes nothing at all and the
//! build graph is byte-identical to upstream's.
//!
//! Everything here lives in this file so the 0.17 rebase carries it unchanged
//! and re-applies only the small hunk in `build.zig`.

const std = @import("std");

pub const Tree = struct {
    /// Destination root given by `-Dmachine-tree=<dir>`.
    out: []const u8,
    /// `keep` or `compact`, from `-Dmachine-lines=`.
    mode: []const u8,
    /// The render step every consumer of the tree must depend on.
    render: *std.Build.Step,

    /// A path inside the rendered tree. `-Dmachine-tree` is routinely an
    /// absolute path outside the build root, which `b.path` refuses by design
    /// (it panics on absolute paths), so this is the documented `cwd_relative`
    /// escape rather than a workaround.
    pub fn rootSource(t: Tree, b: *std.Build, sub: []const u8) std.Build.LazyPath {
        return .{ .cwd_relative = b.pathJoin(&.{ t.out, sub }) };
    }

    pub fn libDir(t: Tree, b: *std.Build) std.Build.LazyPath {
        return .{ .cwd_relative = b.pathJoin(&.{ t.out, "lib" }) };
    }
};

/// Returns null when `-Dmachine-tree` was not given, which is the default and
/// changes nothing. When it IS given, `-Dmachine-lines` is REQUIRED and refused
/// by name if absent: the line mode decides whether a compiler diagnostic's line
/// number maps onto the commented source, and that is never a silent default.
pub fn resolve(b: *std.Build) ?Tree {
    const out = b.option(
        []const u8,
        "machine-tree",
        "Compile the FINAL zig executable from a comment-stripped (MR) rendering of src/ and lib/ written to this directory. Development builds, tests and tooling are unaffected.",
    );
    const lines = b.option(
        []const u8,
        "machine-lines",
        "REQUIRED with -Dmachine-tree. 'keep' removes comment bytes but keeps every newline, so file:line in every diagnostic maps 1:1 onto the commented source. 'compact' also drops lines that became blank.",
    );

    const out_dir = out orelse {
        if (lines != null) std.debug.panic(
            "-Dmachine-lines was given without -Dmachine-tree. Refusing: on its own it would silently do nothing.",
            .{},
        );
        return null;
    };

    const mode = lines orelse std.debug.panic(
        "-Dmachine-tree requires -Dmachine-lines=keep|compact. Refusing to choose a line mode for you: it decides whether compiler diagnostics map 1:1 onto the commented sources.",
        .{},
    );
    if (!std.mem.eql(u8, mode, "keep") and !std.mem.eql(u8, mode, "compact")) std.debug.panic(
        "-Dmachine-lines must be 'keep' or 'compact', got '{s}'",
        .{mode},
    );

    const tool = b.addExecutable(.{
        .name = "machine_tree",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/machine_tree.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });

    const run = b.addRunArtifact(tool);
    run.addArgs(&.{
        "--root", b.build_root.path orelse ".",
        "--out",  out_dir,
        "--mode", mode,
        // The token-stream identity check runs as part of every render, so a
        // rendering that would change what the compiler sees fails the build
        // instead of reaching it. This is the control, not a diagnostic.
        "--verify",
        "--quiet",
    });
    // The renderer writes outside the cache and decides for itself, by content
    // hash, which files actually need rewriting; the build system cannot model
    // that, so it must not skip the step.
    run.has_side_effects = true;

    const step = b.step("machine-tree", "Render src/ and lib/ into the MR tree used by the final executable");
    step.dependOn(&run.step);

    return .{ .out = out_dir, .mode = mode, .render = &run.step };
}
