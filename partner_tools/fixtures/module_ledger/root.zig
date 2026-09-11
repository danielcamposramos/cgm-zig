//! C7 fixture, root module. Deliberately does LITTLE work of its own so the
//! ledger has something to be wrong about: if attribution were per-compilation
//! rather than per-module, root and heavy would not be distinguishable.
const std = @import("std");
const heavy = @import("heavy");

pub fn main() !void {
    var buf: [4096]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    std.debug.print("{d}\n", .{heavy.total(fba.allocator())});
}
