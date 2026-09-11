//! Crown stage 2a — per-module attribution of analysis work.
//!
//! `PLAN.md` makes stage 2a the gate for stage 2c: savings may not be banked
//! before they are measured. This is the measuring.
//!
//! ## Why this adds no counter to any hot path
//!
//! The per-declaration attribution already exists. `Compilation.TimeReport`
//! carries `decl_sema_info` (nanoseconds AND instance count), `decl_codegen_ns`
//! and `decl_link_ns`, each keyed by a ZIR declaration. A declaration resolves
//! to its module in two hops that the compiler already supports:
//!
//!     TrackedInst.Index -> resolveFile -> Zcu.fileByIndex -> File.mod
//!
//! So this file is a ROLLUP, not instrumentation. Nothing here runs during
//! analysis, so the accounting cannot perturb what it accounts for — which is
//! the property that makes a measurement worth trusting.
//!
//! ## The context-free / context-sensitive split
//!
//! `decl_sema_info.count` is the number of times a declaration was analyzed,
//! across generic instances of it and of its parent namespace. So:
//!
//!   count == 1  the compiler analyzed it once -> CONTEXT-FREE CANDIDATE
//!   count >  1  the compiler re-analyzed it per instantiation -> CONTEXT-SENSITIVE
//!
//! This reports what the compiler DID. It is evidence for stage 2c's key, never
//! a licence for it: `count == 1` does not prove a declaration is cacheable, only
//! that it was analyzed once in THIS compilation, and `PLAN.md`'s standing law —
//! anything not provably context-free is treated as context-sensitive — is
//! untouched by it.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Compilation = @import("Compilation.zig");
const Zcu = @import("Zcu.zig");
const InternPool = @import("InternPool.zig");

pub const schema = "cgm-zig.module-ledger.v1";

pub const Row = struct {
    name: []const u8,
    decls_total: u32 = 0,
    /// Analyzed exactly once.
    context_free: u32 = 0,
    /// Analyzed more than once — re-analyzed per instantiation.
    context_sensitive: u32 = 0,
    /// Total analyses, i.e. the sum of every declaration's instance count. The
    /// difference between this and `decls_total` is the re-analysis the crown
    /// exists to attack.
    analyses: u64 = 0,
    sema_ns: u64 = 0,
    codegen_ns: u64 = 0,
    link_ns: u64 = 0,
};

pub const Ledger = struct {
    rows: []Row,
    /// Declarations whose module could not be resolved. Reported, never folded
    /// into another module's total and never silently dropped: an unattributed
    /// declaration is a gap in the measurement and has to look like one.
    unattributed_decls: u32,
    unattributed_sema_ns: u64,

    pub fn deinit(l: *Ledger, gpa: Allocator) void {
        for (l.rows) |r| gpa.free(r.name);
        gpa.free(l.rows);
    }
};

pub const Error = error{NoTimeReport} || Allocator.Error;

/// Fold the existing per-declaration attribution up to per-module totals.
/// Refuses by name when the data source is absent rather than emitting zeroes.
pub fn collect(gpa: Allocator, comp: *Compilation) Error!Ledger {
    const tr = if (comp.time_report) |*t| t else return error.NoTimeReport;
    const zcu = comp.zcu orelse return error.NoTimeReport;
    const ip = &zcu.intern_pool;

    // Keyed by module pointer: module identity is the pointer here, and the
    // fully qualified name is carried for the report.
    var by_mod: std.AutoArrayHashMapUnmanaged(*@import("Package.zig").Module, Row) = .empty;
    defer by_mod.deinit(gpa);

    var unattributed: u32 = 0;
    var unattributed_ns: u64 = 0;

    var it = tr.decl_sema_info.iterator();
    while (it.next()) |entry| {
        const tracked = entry.key_ptr.*;
        const info = entry.value_ptr.*;

        const file_index = tracked.resolveFile(ip);
        const file = zcu.fileByIndex(file_index);
        const mod = file.mod orelse {
            unattributed += 1;
            unattributed_ns += info.ns;
            continue;
        };

        const gop = try by_mod.getOrPut(gpa, mod);
        if (!gop.found_existing) gop.value_ptr.* = .{ .name = mod.fully_qualified_name };

        const row = gop.value_ptr;
        row.decls_total += 1;
        if (info.count <= 1) row.context_free += 1 else row.context_sensitive += 1;
        row.analyses += info.count;
        row.sema_ns += info.ns;
        if (tr.decl_codegen_ns.get(tracked)) |ns| row.codegen_ns += ns;
        if (tr.decl_link_ns.get(tracked)) |ns| row.link_ns += ns;
    }

    var rows = try gpa.alloc(Row, by_mod.count());
    errdefer gpa.free(rows);
    for (by_mod.values(), 0..) |row, i| {
        rows[i] = row;
        rows[i].name = try gpa.dupe(u8, row.name);
    }
    // Heaviest first: the report's first line should be the module that cost the
    // most, because that is the one a reader is looking for.
    std.mem.sort(Row, rows, {}, struct {
        fn gt(_: void, a: Row, b: Row) bool {
            return a.sema_ns > b.sema_ns;
        }
    }.gt);

    return .{
        .rows = rows,
        .unattributed_decls = unattributed,
        .unattributed_sema_ns = unattributed_ns,
    };
}

fn writeJsonString(w: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

pub fn writeJson(l: Ledger, w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{{\n  \"schema\": \"{s}\",\n  \"modules\": [\n", .{schema});
    for (l.rows, 0..) |r, i| {
        try w.writeAll("    {\"name\": ");
        try writeJsonString(w, r.name);
        try w.print(
            ", \"decls_total\": {d}, \"context_free\": {d}, \"context_sensitive\": {d}," ++
                " \"analyses\": {d}, \"sema_ns\": {d}, \"codegen_ns\": {d}, \"link_ns\": {d}}}{s}\n",
            .{ r.decls_total, r.context_free, r.context_sensitive, r.analyses,
               r.sema_ns, r.codegen_ns, r.link_ns, if (i + 1 == l.rows.len) "" else "," },
        );
    }
    try w.print(
        "  ],\n  \"unattributed_decls\": {d},\n  \"unattributed_sema_ns\": {d}\n}}\n",
        .{ l.unattributed_decls, l.unattributed_sema_ns },
    );
}
