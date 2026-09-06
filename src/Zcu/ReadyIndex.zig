//! Optional priority index for an authoritative array-map's current key order.
//!
//! The map owns membership. This heap owns only (priority, map position), with a
//! reverse position table so swap-removal repairs both displaced keys in O(log n).
//! Equal priorities use CURRENT map position, not chronological insertion order.
//! std.PriorityQueue has no relocation hook/reverse table, so finding an arbitrary
//! map member there would reintroduce the scan this helper removes.
//!
//! A rank epoch builds once in O(n); ordinary append/remove is O(log n), peek O(1).
//! Allocation failure or a transient unknown rank disables the index until the
//! caller invalidates the epoch. The caller then uses its original scan. Never
//! retry a failed optional allocation or rebuild the whole set on every pick.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn ReadyIndex(comptime Priority: type, comptime before: fn (Priority, Priority) bool) type {
    return struct {
        const Self = @This();
        const Node = struct { priority: Priority, map_index: usize };
        const State = enum { invalid, active, disabled };

        nodes: std.ArrayList(Node) = .empty,
        positions: std.ArrayList(usize) = .empty,
        state: State = .invalid,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.nodes.deinit(gpa);
            self.positions.deinit(gpa);
            self.* = .{};
        }

        /// Call before ownership/ranks can change, even if the update later fails.
        pub fn invalidate(self: *Self) void {
            self.nodes.clearRetainingCapacity();
            self.positions.clearRetainingCapacity();
            self.state = .invalid;
        }

        /// Abandon partial work; retained capacity is never treated as valid data.
        pub fn disable(self: *Self) void {
            self.invalidate();
            self.state = .disabled;
        }

        pub fn isActive(self: *const Self) bool {
            return self.state == .active;
        }

        /// `rank` returns null only for a priority whose lifetime is not stable.
        /// A stable "unknown sorts last" value is an ordinary Priority.
        pub fn prepare(
            self: *Self,
            gpa: Allocator,
            count: usize,
            context: anytype,
            comptime rank: fn (@TypeOf(context), usize) ?Priority,
        ) bool {
            switch (self.state) {
                .active => {
                    assert(self.nodes.items.len == count);
                    return true;
                },
                .disabled => return false,
                .invalid => {},
            }
            self.nodes.ensureTotalCapacity(gpa, count) catch {
                self.disable();
                return false;
            };
            self.positions.ensureTotalCapacity(gpa, count) catch {
                self.disable();
                return false;
            };
            for (0..count) |map_index| {
                const priority = rank(context, map_index) orelse {
                    self.disable();
                    return false;
                };
                self.nodes.appendAssumeCapacity(.{ .priority = priority, .map_index = map_index });
                self.positions.appendAssumeCapacity(map_index);
            }
            var i = count / 2;
            while (i > 0) {
                i -= 1;
                self.siftDown(i);
            }
            self.state = .active;
            return true;
        }

        /// Mirror a NEW key appended to the authoritative map. Existing-key puts
        /// must not call this. Both capacity reservations precede length changes.
        pub fn append(self: *Self, gpa: Allocator, priority: Priority) void {
            assert(self.isActive());
            self.nodes.ensureUnusedCapacity(gpa, 1) catch return self.disable();
            self.positions.ensureUnusedCapacity(gpa, 1) catch return self.disable();
            const index = self.nodes.items.len;
            self.nodes.appendAssumeCapacity(.{ .priority = priority, .map_index = index });
            self.positions.appendAssumeCapacity(index);
            self.siftUp(index);
        }

        /// Mirror map.swapRemoveAt BEFORE or AFTER the map operation, using the
        /// removed key's OLD position. This operation allocates nothing.
        pub fn swapRemoveAt(self: *Self, map_index: usize) void {
            if (!self.isActive()) return;
            const last_map_index = self.positions.items.len - 1;
            const heap_index = self.positions.items[map_index];
            const last_node = self.nodes.pop().?;
            if (heap_index < self.nodes.items.len) {
                self.nodes.items[heap_index] = last_node;
                self.positions.items[last_node.map_index] = heap_index;
                self.repair(heap_index);
            }
            if (map_index != last_map_index) {
                // Array-map moves its last key into the removed position. That
                // changes the final tie-break even when both ranks are equal.
                const moved_heap_index = self.positions.items[last_map_index];
                self.nodes.items[moved_heap_index].map_index = map_index;
                self.positions.items[map_index] = moved_heap_index;
                self.repair(moved_heap_index);
            }
            self.positions.items.len -= 1;
        }

        pub fn peek(self: *const Self) ?usize {
            if (!self.isActive() or self.nodes.items.len == 0) return null;
            return self.nodes.items[0].map_index;
        }

        fn less(a: Node, b: Node) bool {
            if (before(a.priority, b.priority)) return true;
            if (before(b.priority, a.priority)) return false;
            return a.map_index < b.map_index;
        }

        fn swap(self: *Self, a: usize, b: usize) void {
            std.mem.swap(Node, &self.nodes.items[a], &self.nodes.items[b]);
            self.positions.items[self.nodes.items[a].map_index] = a;
            self.positions.items[self.nodes.items[b].map_index] = b;
        }

        fn repair(self: *Self, index: usize) void {
            if (index > 0 and less(self.nodes.items[index], self.nodes.items[(index - 1) / 2])) {
                self.siftUp(index);
            } else {
                self.siftDown(index);
            }
        }

        fn siftUp(self: *Self, start: usize) void {
            var index = start;
            while (index > 0) {
                const parent = (index - 1) / 2;
                if (!less(self.nodes.items[index], self.nodes.items[parent])) break;
                self.swap(index, parent);
                index = parent;
            }
        }

        fn siftDown(self: *Self, start: usize) void {
            var index = start;
            while (index < self.nodes.items.len / 2) {
                var child = index * 2 + 1;
                if (child + 1 < self.nodes.items.len and less(self.nodes.items[child + 1], self.nodes.items[child])) {
                    child += 1;
                }
                if (!less(self.nodes.items[child], self.nodes.items[index])) break;
                self.swap(index, child);
                index = child;
            }
        }
    };
}
