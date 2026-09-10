//! A second, substantively different consumer that shares most of `std` with
//! the first. Used to show that two separately compiled programs get DISTINCT
//! debug identities even though their debug information overlaps heavily.
const std = @import("std");

pub fn main() !void {
    var buf: [64 * 1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const a = fba.allocator();

    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(a);
    for ([_][]const u8{ "delta", "alpha", "charlie", "bravo" }) |n| try names.append(a, n);
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lessThan);

    var counts: std.StringHashMap(usize) = .init(a);
    defer counts.deinit();
    for (names.items) |n| try counts.put(n, n.len);

    var total: usize = 0;
    var it = counts.valueIterator();
    while (it.next()) |v| total += v.*;
    std.debug.print("{s} {d}\n", .{ names.items[0], total });
}
