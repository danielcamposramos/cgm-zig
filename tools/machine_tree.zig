//! Renders the fork's own sources into two projections, and mirrors everything
//! else, so the output is a COMPLETE, self-sufficient tree the compiler can be
//! pointed at. That completeness is not cosmetic: `lib/` is a whole sysroot --
//! 13k C headers, libunwind and libcxx sources, `.def` files -- and `src/`
//! `@import`s `.zon` data files. A Zig-only projection is missing all of it and
//! the compiler fails with `FileNotFound`, which is exactly how this was found.
//!
//!
//!   MR ("machine readable") -- the code with every comment removed. This is
//!       what the compiler compiles FROM. It is byte-for-byte equivalent to the
//!       source as far as the tokenizer is concerned, which is the property the
//!       `--verify` control proves rather than assumes.
//!   HR ("human readable") -- the comments only, in source order, each block
//!       carrying the source line it starts on, so a reader can address any
//!       comment by `file:line` of the ORIGINAL file. Never enters a compile.
//!
//! The renderer is TOKEN-AWARE, and it has to be. A line-prefix or regex
//! stripper corrupts two constructs that occur throughout this tree:
//!
//!   * multiline string lines -- `\\ // not a comment` is STRING CONTENT and a
//!     `//`-stripper would silently truncate it;
//!   * string literals containing `//`, e.g. `"https://ziglang.org"`.
//!
//! Both are tokens here and are copied byte-exact. What is dropped is exactly:
//! `doc_comment` and `container_doc_comment` TOKENS (`///` and `//!`), and the
//! plain `//` comment runs that the tokenizer skips BETWEEN tokens and which
//! therefore never appear as tokens at all. Note that `////` is a plain comment,
//! not a doc comment -- `tokenizer.zig`'s `doc_comment_start` state falls back to
//! `line_comment` on a third slash -- and this renderer inherits that
//! classification by construction instead of restating it.
//!
//! Line modes (see `--mode`), both measured before either was recommended:
//!   keep    -- remove comment BYTES, keep every newline. Line numbers in every
//!              compiler diagnostic then map 1:1 onto the commented file, so no
//!              line map is needed anywhere.
//!   compact -- also remove lines that BECAME blank. A line that was already
//!              blank in the source is preserved: that is the author's spacing,
//!              not an artifact of comment removal.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Tokenizer = std.zig.Tokenizer;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// Bumped whenever rendering output could change for unchanged input. It is a
/// manifest field so a stale tree re-renders instead of being trusted.
pub const renderer_version = "1";

const Mode = enum { keep, compact };

const usage =
    \\usage: machine_tree --out <dir> --mode keep|compact [options]
    \\
    \\  --root <dir>     source root (default ".")
    \\  --out <dir>      destination root; <out>/src/... <out>/lib/... <out>/hr/...
    \\  --mode <mode>    keep | compact   (REQUIRED -- never defaulted)
    \\  --dir <name>     subtree to render, repeatable (default: src, lib)
    \\  --verify         token-stream identity check per file (control P1)
    \\  --check          verify the EXISTING rendered tree against the source and
    \\                   write NOTHING. Names the first mismatching token per file.
    \\  --quiet          only the summary line
    \\  --tokenize-only  walk and tokenize only; write nothing. The instrument for
    \\                   comparing a tokenizer pass over the commented tree with one
    \\                   over the MR tree.
    \\
;

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("machine_tree: " ++ fmt ++ "\n", args);
    std.process.exit(2);
}

// ---------------------------------------------------------------- rendering

const Comment = struct { line: usize, text: []const u8 };

const Rendered = struct {
    mr: [:0]u8,
    comments: []Comment,
    /// keep mode: always 0. compact mode: lines dropped because they became blank.
    lines_dropped: usize,
};

/// A byte between two tokens that is neither whitespace nor the start of a
/// comment. The tokenizer's own grammar says this cannot happen -- anything else
/// becomes a token, including `invalid`. If it ever does happen, this renderer
/// REFUSES BY NAME rather than dropping bytes it does not understand.
const RenderError = error{UnexpectedByteBetweenTokens} || Allocator.Error;

fn render(gpa: Allocator, src: [:0]const u8, mode: Mode) RenderError!Rendered {
    var mr: std.ArrayList(u8) = .empty;
    errdefer mr.deinit(gpa);
    var comments: std.ArrayList(Comment) = .empty;
    errdefer comments.deinit(gpa);

    var pos: usize = 0;
    var line: usize = 1;

    // `Tokenizer.init` skips a UTF-8 BOM, so the first token starts past it and
    // the BOM would land in the leading gap. Copy it through explicitly; it is
    // not whitespace and the gap walker would (correctly) refuse it.
    if (std.mem.startsWith(u8, src, "\xEF\xBB\xBF")) {
        try mr.appendSlice(gpa, src[0..3]);
        pos = 3;
    }

    var tk: Tokenizer = .init(src);
    while (true) {
        const t = tk.next();
        try emitGap(gpa, &mr, &comments, src[pos..t.loc.start], &line);
        if (t.tag == .eof) break;
        const text = src[t.loc.start..t.loc.end];
        switch (t.tag) {
            .doc_comment, .container_doc_comment => {
                // A TOKEN, so it never reaches the gap walker. Its bytes stop
                // before the newline, which stays in the following gap and is
                // therefore preserved in keep mode without special handling.
                try comments.append(gpa, .{ .line = line, .text = text });
            },
            else => try mr.appendSlice(gpa, text),
        }
        line += std.mem.count(u8, text, "\n");
        pos = t.loc.end;
    }

    var dropped: usize = 0;
    if (mode == .compact) {
        const compacted = try compact(gpa, src, mr.items, &dropped);
        mr.deinit(gpa);
        return .{
            .mr = compacted,
            .comments = try comments.toOwnedSlice(gpa),
            .lines_dropped = dropped,
        };
    }
    return .{
        .mr = try mr.toOwnedSliceSentinel(gpa, 0),
        .comments = try comments.toOwnedSlice(gpa),
        .lines_dropped = 0,
    };
}

fn emitGap(
    gpa: Allocator,
    mr: *std.ArrayList(u8),
    comments: *std.ArrayList(Comment),
    gap: []const u8,
    line: *usize,
) RenderError!void {
    var i: usize = 0;
    while (i < gap.len) {
        const c = gap[i];
        if (c == '/' and i + 1 < gap.len and gap[i + 1] == '/') {
            var j = i;
            while (j < gap.len and gap[j] != '\n') j += 1;
            try comments.append(gpa, .{ .line = line.*, .text = gap[i..j] });
            i = j; // the newline itself is whitespace and is copied below
            continue;
        }
        if (c == '\n') line.* += 1;
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            try mr.append(gpa, c);
            i += 1;
            continue;
        }
        return error.UnexpectedByteBetweenTokens;
    }
}

fn isBlank(s: []const u8) bool {
    for (s) |c| if (c != ' ' and c != '\t' and c != '\r') return false;
    return true;
}

/// Drop only the lines that comment removal EMPTIED. A line blank in the source
/// stays blank in the output: that spacing is authored, and deleting it would
/// make `compact` a reformatter rather than a comment stripper.
fn compact(gpa: Allocator, src: []const u8, keep_bytes: []const u8, dropped: *usize) Allocator.Error![:0]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var src_it = std.mem.splitScalar(u8, src, '\n');
    var keep_it = std.mem.splitScalar(u8, keep_bytes, '\n');
    var first = true;
    while (keep_it.next()) |kl| {
        const sl = src_it.next() orelse "";
        if (isBlank(kl) and !isBlank(sl)) {
            dropped.* += 1;
            continue;
        }
        if (!first) try out.append(gpa, '\n');
        first = false;
        try out.appendSlice(gpa, kl);
    }
    return out.toOwnedSliceSentinel(gpa, 0);
}

// ------------------------------------------------------- the P1 control

const Mismatch = struct {
    index: usize,
    src_tag: []const u8,
    mr_tag: []const u8,
    src_text: []const u8,
    mr_text: []const u8,
};

/// The load-bearing control: the token stream of the SOURCE with doc-comment
/// tokens removed must equal the token stream of the MR, tag and bytes, in
/// order. If this holds for a file, the renderer changed nothing the compiler
/// can see in that file. Returns the first mismatch, or null.
fn verifyTokens(src: [:0]const u8, mr: [:0]const u8) ?Mismatch {
    var a: Tokenizer = .init(src);
    var b: Tokenizer = .init(mr);
    var n: usize = 0;
    while (true) : (n += 1) {
        var ta = a.next();
        while (ta.tag == .doc_comment or ta.tag == .container_doc_comment) ta = a.next();
        const tb = b.next();
        const sa = src[ta.loc.start..ta.loc.end];
        const sb = mr[tb.loc.start..tb.loc.end];
        if (ta.tag != tb.tag or !std.mem.eql(u8, sa, sb)) return .{
            .index = n,
            .src_tag = @tagName(ta.tag),
            .mr_tag = @tagName(tb.tag),
            .src_text = sa,
            .mr_text = sb,
        };
        if (ta.tag == .eof) return null;
    }
}

fn countTokens(s: [:0]const u8) usize {
    var t: Tokenizer = .init(s);
    var n: usize = 0;
    while (true) : (n += 1) if (t.next().tag == .eof) return n;
}

// ---------------------------------------------------------------- hashing

fn hashHex(bytes: []const u8) [64]u8 {
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&digest}) catch unreachable;
    return hex;
}

// ---------------------------------------------------------------- HR output

/// `std.ArrayList` is unmanaged here and carries no `writer`, so formatted
/// appends go through one small helper rather than a version-specific adapter.
fn ap(gpa: Allocator, list: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) Allocator.Error!void {
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try list.appendSlice(gpa, s);
}

fn writeHr(gpa: Allocator, rel: []const u8, comments: []const Comment) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try ap(gpa, &out, "# {s}\n\nComments only, in source order. Each block is labelled with the\nline it starts on IN THE ORIGINAL FILE, so `{s}:<line>` addresses it.\n", .{ rel, rel });
    if (comments.len == 0) {
        try out.appendSlice(gpa, "\n_No comments in this file._\n");
        return out.toOwnedSlice(gpa);
    }
    var i: usize = 0;
    while (i < comments.len) {
        // group physically consecutive comment lines into one block
        var j = i + 1;
        while (j < comments.len and comments[j].line == comments[j - 1].line + 1) j += 1;
        try ap(gpa, &out, "\n## L{d}\n\n```zig\n", .{comments[i].line});
        for (comments[i..j]) |c| try ap(gpa, &out, "{s}\n", .{c.text});
        try out.appendSlice(gpa, "```\n");
        i = j;
    }
    return out.toOwnedSlice(gpa);
}

// ---------------------------------------------------------------- driver

const Row = struct {
    path: []const u8,
    src_sha: [64]u8,
    mr_sha: [64]u8,
    hr_sha: [64]u8,
    src_bytes: usize,
    mr_bytes: usize,
    src_lines: usize,
    mr_lines: usize,
    tokens: usize,
    rewritten: bool,
};

fn countLines(s: []const u8) usize {
    return std.mem.count(u8, s, "\n") + 1;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var root: []const u8 = ".";
    var out_dir_path: ?[]const u8 = null;
    var mode: ?Mode = null;
    var verify = false;
    var check_only = false;
    var tokenize_only = false;
    var quiet = false;
    var dirs: std.ArrayList([]const u8) = .empty;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--root")) {
            i += 1;
            if (i >= args.len) fatal("--root needs a value", .{});
            root = args[i];
        } else if (std.mem.eql(u8, a, "--out")) {
            i += 1;
            if (i >= args.len) fatal("--out needs a value", .{});
            out_dir_path = args[i];
        } else if (std.mem.eql(u8, a, "--mode")) {
            i += 1;
            if (i >= args.len) fatal("--mode needs a value", .{});
            mode = std.meta.stringToEnum(Mode, args[i]) orelse
                fatal("--mode must be 'keep' or 'compact', got '{s}'", .{args[i]});
        } else if (std.mem.eql(u8, a, "--dir")) {
            i += 1;
            if (i >= args.len) fatal("--dir needs a value", .{});
            try dirs.append(arena, args[i]);
        } else if (std.mem.eql(u8, a, "--verify")) {
            verify = true;
        } else if (std.mem.eql(u8, a, "--check")) {
            check_only = true;
            verify = true;
        } else if (std.mem.eql(u8, a, "--tokenize-only")) {
            tokenize_only = true;
        } else if (std.mem.eql(u8, a, "--quiet")) {
            quiet = true;
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            std.debug.print("{s}", .{usage});
            return;
        } else fatal("unrecognized argument '{s}'\n{s}", .{ a, usage });
    }

    // Both are REQUIRED and refused by name. `--mode` in particular is never
    // defaulted: which line mode a tree was rendered in changes what every
    // compiler diagnostic's line number means, and that must be a stated choice.
    const out_path = out_dir_path orelse fatal("--out is required\n{s}", .{usage});
    const line_mode = mode orelse fatal("--mode is required (keep|compact); refusing to pick one for you\n{s}", .{usage});
    if (dirs.items.len == 0) {
        try dirs.append(arena, "src");
        try dirs.append(arena, "lib");
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;

    var root_dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer root_dir.close(io);
    try Io.Dir.cwd().createDirPath(io, out_path);
    var dest = try Io.Dir.cwd().openDir(io, out_path, .{});
    defer dest.close(io);

    var rows: std.ArrayList(Row) = .empty;
    defer rows.deinit(gpa);

    var total_src: usize = 0;
    var total_mr: usize = 0;
    var total_tokens: usize = 0;
    var total_dropped: usize = 0;
    var mismatches: usize = 0;
    var rewritten: usize = 0;
    var mirrored: usize = 0;
    var zig_seen: usize = 0;
    var mirrored_bytes: usize = 0;
    var line_mismatches: usize = 0;

    for (dirs.items) |sub| {
        var sd = root_dir.openDir(io, sub, .{ .iterate = true }) catch |err|
            fatal("cannot open '{s}/{s}': {s}", .{ root, sub, @errorName(err) });
        defer sd.close(io);
        var walker = try sd.walk(gpa);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;

            const rel = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ sub, entry.path });
            defer gpa.free(rel);

            // Everything that is not Zig source is MIRRORED byte-for-byte. The
            // renderer has no opinion about a C header or a `.zon` value and must
            // not acquire one; it only has to make the tree complete.
            if (!std.mem.endsWith(u8, entry.basename, ".zig")) {
                const blob = try root_dir.readFileAlloc(io, rel, gpa, .limited(1 << 31));
                defer gpa.free(blob);
                mirrored += 1;
                mirrored_bytes += blob.len;
                if (!check_only) {
                    if (try writeIfDifferent(io, dest, gpa, rel, blob)) rewritten += 1;
                } else {
                    const there = dest.readFileAlloc(io, rel, gpa, .limited(1 << 31)) catch |err|
                        fatal("--check: mirrored file missing from the rendered tree: '{s}': {s}", .{ rel, @errorName(err) });
                    defer gpa.free(there);
                    if (!std.mem.eql(u8, there, blob)) {
                        mismatches += 1;
                        try out.print("MIRROR MISMATCH {s}: rendered copy differs from source\n", .{rel});
                    }
                }
                continue;
            }

            const src = try root_dir.readFileAllocOptions(
                io,
                rel,
                gpa,
                .limited(1 << 30),
                .of(u8),
                0,
            );
            defer gpa.free(src);

            if (tokenize_only) {
                total_tokens += countTokens(src);
                total_src += src.len;
                zig_seen += 1;
                continue;
            }

            const r = render(gpa, src, line_mode) catch |err| switch (err) {
                error.UnexpectedByteBetweenTokens => fatal(
                    "REFUSED: {s} has a byte between two tokens that is neither whitespace nor a comment. " ++
                        "This renderer will not drop bytes it does not understand.",
                    .{rel},
                ),
                else => |e| return e,
            };
            defer gpa.free(r.mr);
            defer gpa.free(r.comments);

            // In --check mode the thing under test is the tree ON DISK, not the
            // bytes we just produced: a rendered file that was corrupted after
            // the fact must be caught, and re-rendering it would silently heal it.
            const subject: [:0]const u8 = if (check_only)
                dest.readFileAllocOptions(io, rel, gpa, .limited(1 << 30), .of(u8), 0) catch |err|
                    fatal("--check: cannot read rendered '{s}': {s}", .{ rel, @errorName(err) })
            else
                r.mr;
            defer if (check_only) gpa.free(@constCast(subject));

            if (verify) {
                total_tokens += countTokens(subject);
                if (verifyTokens(src, subject)) |m| {
                    mismatches += 1;
                    try out.print(
                        "MISMATCH {s}: token #{d} src={s} '{s}' mr={s} '{s}'\n",
                        .{ rel, m.index, m.src_tag, m.src_text, m.mr_tag, m.mr_text },
                    );
                }
            }

            const src_lines = countLines(src);
            const mr_lines = countLines(subject);
            if (line_mode == .keep and src_lines != mr_lines) {
                line_mismatches += 1;
                try out.print("LINE MISMATCH {s}: src {d} vs mr {d}\n", .{ rel, src_lines, mr_lines });
            }

            const hr = try writeHr(gpa, rel, r.comments);
            defer gpa.free(hr);

            var did = false;
            if (!check_only) {
                did = try writeIfDifferent(io, dest, gpa, rel, r.mr);
                const hr_rel = try std.fmt.allocPrint(gpa, "hr/{s}.md", .{rel});
                defer gpa.free(hr_rel);
                _ = try writeIfDifferent(io, dest, gpa, hr_rel, hr);
                if (did) rewritten += 1;
            }

            total_src += src.len;
            total_mr += subject.len;
            total_dropped += r.lines_dropped;

            try rows.append(gpa, .{
                .path = try gpa.dupe(u8, rel),
                .src_sha = hashHex(src),
                .mr_sha = hashHex(r.mr),
                .hr_sha = hashHex(hr),
                .src_bytes = src.len,
                .mr_bytes = subject.len,
                .src_lines = src_lines,
                .mr_lines = mr_lines,
                .tokens = if (verify) countTokens(subject) else 0,
                .rewritten = did,
            });
        }
    }

    if (tokenize_only) {
        try out.print("tokenize_only files={d} bytes={d} tokens={d}\n", .{ zig_seen, total_src, total_tokens });
        try out.flush();
        return;
    }
    if (!check_only) try writeManifest(io, dest, gpa, rows.items, line_mode, out_path);

    if (!quiet) {
        try out.print("zig_files={d} mirrored={d} ({d} bytes) rewritten={d} src_bytes={d} mr_bytes={d} removed={d} ({d:.2}%)\n", .{
            rows.items.len, mirrored, mirrored_bytes, rewritten, total_src, total_mr,
            total_src - total_mr,
            @as(f64, @floatFromInt(total_src - total_mr)) * 100.0 / @as(f64, @floatFromInt(total_src)),
        });
        if (line_mode == .compact) try out.print("lines_dropped={d}\n", .{total_dropped});
        if (line_mode == .keep) try out.print("line_mismatches={d}\n", .{line_mismatches});
        if (verify) try out.print("tokens_compared={d} mismatches={d}\n", .{ total_tokens, mismatches });
    }
    try out.flush();

    if (mismatches != 0 or line_mismatches != 0) std.process.exit(1);
}

/// Write only when the bytes actually differ, so an unchanged render leaves the
/// mtime alone and the zig cache stays warm.
fn writeIfDifferent(io: Io, dest: Io.Dir, gpa: Allocator, rel: []const u8, bytes: []const u8) !bool {
    if (std.fs.path.dirname(rel)) |d| try dest.createDirPath(io, d);
    if (dest.readFileAlloc(io, rel, gpa, .limited(1 << 30))) |old| {
        defer gpa.free(old);
        if (std.mem.eql(u8, old, bytes)) return false;
    } else |_| {}
    try dest.writeFile(io, .{ .sub_path = rel, .data = bytes });
    return true;
}

fn writeManifest(io: Io, dest: Io.Dir, gpa: Allocator, rows: []const Row, mode: Mode, out_path: []const u8) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try ap(gpa, &buf, 
        "{{\n  \"renderer_version\": \"{s}\",\n  \"mode\": \"{s}\",\n  \"out\": \"{s}\",\n  \"files\": [\n",
        .{ renderer_version, @tagName(mode), out_path },
    );
    for (rows, 0..) |r, n| {
        try ap(gpa, &buf,
            "    {{\"path\":\"{s}\",\"src_sha256\":\"{s}\",\"mr_sha256\":\"{s}\",\"hr_sha256\":\"{s}\"," ++
                "\"src_bytes\":{d},\"mr_bytes\":{d},\"src_lines\":{d},\"mr_lines\":{d},\"rewritten\":{}}}{s}\n",
            .{
                r.path,       &r.src_sha,   &r.mr_sha, &r.hr_sha, r.src_bytes,
                r.mr_bytes,   r.src_lines,  r.mr_lines, r.rewritten,
                if (n + 1 == rows.len) "" else ",",
            },
        );
    }
    try buf.appendSlice(gpa, "  ]\n}\n");
    try dest.writeFile(io, .{ .sub_path = "MANIFEST.json", .data = buf.items });
}
