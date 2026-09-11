//! C7 fixture, the heavy module. One generic instantiated at MANY distinct
//! types, so `decl_sema_info.count` for `Box` must exceed 1 and the
//! context-sensitive column must be non-zero. A second declaration is used
//! exactly once, so the context-free column must also be non-zero: a split that
//! can only ever land in one column proves nothing.
const std = @import("std");

/// Instantiated once per type below -> analyzed repeatedly -> CONTEXT-SENSITIVE.
pub fn Box(comptime T: type) type {
    return struct {
        v: T,
        pub fn get(self: @This()) usize {
            return @intCast(@as(u64, @intCast(self.v)) & 0xff);
        }
    };
}

/// Used from exactly one site -> analyzed once -> CONTEXT-FREE candidate.
pub fn onlyOnce(x: usize) usize {
    return x +% 1;
}

pub fn total(a: std.mem.Allocator) usize {
    _ = a;
    var n: usize = 0;
    inline for (.{ u8, u16, u32, u64, i8, i16, i32, i64, usize, isize }) |T| {
        const b: Box(T) = .{ .v = 1 };
        n += b.get();
    }
    return onlyOnce(n);
}
