//! Second module, same std generics, different decl names.
const std = @import("std");

pub fn work(a: std.mem.Allocator) !usize {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.append(a, 9);
    var map: std.StringHashMap(u32) = .init(a);
    defer map.deinit();
    try map.put("z", 2);
    return list.items.len + map.count();
}
