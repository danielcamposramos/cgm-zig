//! The line map that makes a rendered (comment-stripped) tree report SOURCE
//! locations.
//!
//! When the compiler compiles a machine-tree file, every diagnostic it produces
//! names a path and a line in that tree. Neither is what a human wants to read.
//! This module is the single place that knows how to turn one into the other,
//! and the single place that declares the on-disk format: `tools/machine_tree.zig`
//! imports THIS file to write maps, and `Zcu` imports it to read them, so the
//! format has exactly one spelling.
//!
//! ## Why a sidecar and not one table in the manifest
//!
//! At error time the reporter already holds the rendered file's absolute path.
//! A sidecar means one `open` + one `read` of a small file to answer one
//! question. A single manifest table would mean loading and parsing an index
//! covering every rendered file in the tree (1,145 of them here) to resolve a
//! single diagnostic, and diagnostics must not pay tree-scale cost. The sidecar
//! also travels with the file it describes, so a partially copied tree cannot
//! silently pair a map with the wrong source.
//!
//! ## Why the column needs no mapping
//!
//! A Zig line comment runs to the end of its line, so no code can follow a
//! comment on the same line. Rendering therefore only ever removes a SUFFIX of a
//! line, never a prefix, and `compact` additionally removes whole lines and
//! never parts of them. The code prefix of any surviving line is byte-exact,
//! so a column is already correct and is passed through untouched. This is a
//! structural consequence of the tokenizer's grammar, and it is also checked
//! empirically by the renderer's column law control.
//!
//! ## Failure policy
//!
//! A map that exists but cannot be trusted is a NAMED failure, never a guess.
//! Returning a plausible-looking wrong line would put a reader at the wrong
//! place in the wrong file with no indication anything went wrong, which is
//! worse than no mapping at all.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const extension = ".linemap";

/// `magic`, `version`, `kind`, `digest`, then `source_path_len` bytes of path,
/// then for `.explicit` a `u32` per rendered line holding that line's 1-based
/// source line. Little-endian throughout. Fixed header, no parsing, O(1) lookup.
///
/// `digest` covers the path and the table. It is not decoration: without it, a
/// single flipped entry that happens to stay in range is UNDETECTABLE by the
/// reader, and the result is a diagnostic pointing at a real file on a
/// plausible wrong line with nothing to indicate anything went wrong. That is
/// precisely the failure this whole mechanism exists to prevent, so corruption
/// has to be a named refusal rather than a wrong answer.
pub const magic = "CGMLMAP\x00".*;
pub const version: u32 = 1;

pub const Kind = enum(u32) {
    /// Line numbers are unchanged; only the path differs. This is `keep` mode,
    /// where every newline survives, so no table is stored at all.
    identity = 0,
    /// A table is stored: entry[i] is the source line of rendered line i+1.
    explicit = 1,
    _,
};

pub const Header = extern struct {
    magic: [8]u8,
    version: u32,
    kind: u32,
    source_path_len: u32,
    line_count: u32,
    digest: u64,
};

fn digestOf(source_path: []const u8, line_bytes: []const u8) u64 {
    var h: std.hash.Wyhash = .init(0);
    h.update(source_path);
    h.update(line_bytes);
    return h.final();
}

pub const Error = error{
    NotAMap,
    UnsupportedVersion,
    Truncated,
    /// The header is intact but the path or the table does not match the
    /// recorded digest: the map has been altered or damaged since it was
    /// written, and no line it claims can be trusted.
    Corrupt,
    LineOutOfRange,
};

/// Serialize a map. `lines[i]` is the 1-based source line of rendered line i+1;
/// pass an empty slice together with `.identity` when the mapping is the
/// identity. `source_path` is stored verbatim and is what diagnostics will name.
pub fn serialize(
    gpa: Allocator,
    kind: Kind,
    source_path: []const u8,
    lines: []const u32,
) Allocator.Error![]u8 {
    const header: Header = .{
        .magic = magic,
        .version = version,
        .kind = @intFromEnum(kind),
        .source_path_len = @intCast(source_path.len),
        .line_count = @intCast(lines.len),
        .digest = digestOf(source_path, std.mem.sliceAsBytes(lines)),
    };
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, std.mem.asBytes(&header));
    try out.appendSlice(gpa, source_path);
    try out.appendSlice(gpa, std.mem.sliceAsBytes(lines));
    return out.toOwnedSlice(gpa);
}

pub const Map = struct {
    kind: Kind,
    source_path: []const u8,
    lines: []align(1) const u32,
    /// The bytes `source_path` and `lines` point into.
    bytes: []const u8,

    pub fn deinit(m: Map, gpa: Allocator) void {
        gpa.free(m.bytes);
    }

    /// Resolve a 1-based rendered line to its 1-based source line.
    pub fn sourceLine(m: Map, rendered_line: u32) Error!u32 {
        if (m.kind == .identity) return rendered_line;
        // Line 0 is the compiler's "whole file, no particular line" convention
        // and maps to itself.
        if (rendered_line == 0) return 0;
        if (rendered_line > m.lines.len) return error.LineOutOfRange;
        return m.lines[rendered_line - 1];
    }
};

/// Parse a serialized map. Every field is validated before anything is trusted.
pub fn parse(bytes: []const u8) Error!Map {
    if (bytes.len < @sizeOf(Header)) return error.Truncated;
    const header = std.mem.bytesAsValue(Header, bytes[0..@sizeOf(Header)]);
    if (!std.mem.eql(u8, &header.magic, &magic)) return error.NotAMap;
    if (header.version != version) return error.UnsupportedVersion;
    const path_start = @sizeOf(Header);
    const path_end = path_start + header.source_path_len;
    if (path_end > bytes.len) return error.Truncated;
    const table_end = path_end + header.line_count * @sizeOf(u32);
    if (table_end > bytes.len) return error.Truncated;
    if (digestOf(bytes[path_start..path_end], bytes[path_end..table_end]) != header.digest)
        return error.Corrupt;
    return .{
        .kind = @enumFromInt(header.kind),
        .source_path = bytes[path_start..path_end],
        .lines = std.mem.bytesAsSlice(u32, bytes[path_end..table_end]),
        .bytes = bytes,
    };
}

/// Load the map beside `rendered_abs_path`, or null when there is none — which
/// is the ordinary case for a tree that was never rendered. A map that is
/// PRESENT but unusable is refused by name rather than ignored: silently
/// falling back would print a rendered-tree location as if it were source.
pub fn load(gpa: Allocator, io: Io, rendered_abs_path: []const u8) ?Map {
    const side = std.fmt.allocPrint(gpa, "{s}{s}", .{ rendered_abs_path, extension }) catch return null;
    defer gpa.free(side);

    const bytes = Io.Dir.cwd().readFileAlloc(io, side, gpa, .limited(1 << 30)) catch return null;
    errdefer gpa.free(bytes);

    return parse(bytes) catch |err| std.debug.panic(
        "line map '{s}' is present but unusable ({s}). Refusing to report a source " ++
            "location from it: a wrong line in the wrong file is worse than none. " ++
            "Re-render the machine tree, or remove the map to report rendered locations.",
        .{ side, @errorName(err) },
    );
}
