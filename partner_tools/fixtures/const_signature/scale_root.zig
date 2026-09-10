//! Scale probe: two modules that independently use the SAME std generics.
//! If the emitter duplicates type DIEs per module, it shows here and not in
//! the tiny fixtures.
const std = @import("std");
const modb = @import("modb");

pub fn main() !void {
    var buf: [64 * 1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const a = fba.allocator();
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.append(a, 7);
    var map: std.StringHashMap(u32) = .init(a);
    defer map.deinit();
    try map.put("k", 1);
    std.debug.print("{d} {d} {d}\n", .{ list.items.len, map.count(), modb.work(a) catch 0 });
}
