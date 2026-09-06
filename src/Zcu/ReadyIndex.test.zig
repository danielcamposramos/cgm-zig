//! Standalone sequence oracle for the production helper and ModuleRanking
//! comparator. Run with --dep ranking -Mroot=this-file
//! -Mranking=src/Zcu.zig; no compiler rebuild is needed. Using Zcu's existing
//! export keeps ModuleRanking's relative imports inside their real module root.
const std = @import("std");
const testing = std.testing;
const Ranking = @import("ranking").ModuleRanking;
const HeapFactory = @import("ranking").ReadyIndex;
const Rank = Ranking.FileRank;
const Index = HeapFactory(Rank, before);
const Map = std.AutoArrayHashMapUnmanaged(u32, Rank);

fn before(a: Rank, b: Rank) bool {
    return Ranking.before(a.rank, a.facade, b.rank, b.facade);
}

fn rank(depth: u32, fan_in: u32, facade: u1) Rank {
    return .{ .rank = .{ .depth = depth, .fan_in = fan_in }, .facade = facade };
}

const Context = struct {
    values: []const Rank,
    transient: ?usize = null,

    fn get(ctx: Context, i: usize) ?Rank {
        return if (ctx.transient == i) null else ctx.values[i];
    }
};

/// The old strict argmin over authoritative map order, independent of the heap.
fn scan(values: []const Rank) ?usize {
    if (values.len == 0) return null;
    var best: usize = 0;
    for (values[1..], 1..) |value, i| {
        if (before(value, values[best])) best = i;
    }
    return best;
}

fn expectSequenceHead(index: *Index, map: Map) !void {
    try testing.expect(index.prepare(testing.allocator, map.count(), Context{ .values = map.values() }, Context.get));
    try testing.expectEqual(scan(map.values()), index.peek());
    try testing.expectEqual(map.count(), index.positions.items.len);
    for (index.nodes.items, 0..) |node, heap_index| {
        try testing.expect(node.map_index < map.count());
        try testing.expectEqual(heap_index, index.positions.items[node.map_index]);
        try testing.expectEqualDeep(map.values()[node.map_index], node.priority);
    }
}

test "swap removal keeps current map order for tied ranks" {
    var map: Map = .empty;
    defer map.deinit(testing.allocator);
    var index: Index = .{};
    defer index.deinit(testing.allocator);
    for (0..9) |i| try map.put(testing.allocator, @intCast(i), rank(1, 2, 0));
    try expectSequenceHead(&index, map);
    // A FIFO would next choose key 1. The current array-map chooses moved key 8.
    index.swapRemoveAt(0);
    map.swapRemoveAt(0);
    try expectSequenceHead(&index, map);
    try testing.expectEqual(@as(u32, 8), map.keys()[index.peek().?]);
    while (map.count() > 0) {
        try expectSequenceHead(&index, map);
        index.swapRemoveAt(0);
        map.swapRemoveAt(0);
    }
    try expectSequenceHead(&index, map);
}

test "all ranking fields and stable unknown use the production comparator" {
    const values = [_]Rank{
        .unknown,      rank(2, 99, 0), rank(1, 2, 1), rank(1, 3, 1),
        rank(1, 3, 0), rank(1, 3, 0),  rank(0, 0, 1), .unknown,
    };
    var map: Map = .empty;
    defer map.deinit(testing.allocator);
    var index: Index = .{};
    defer index.deinit(testing.allocator);
    for (values, 0..) |value, i| try map.put(testing.allocator, @intCast(i), value);
    while (map.count() > 0) {
        try expectSequenceHead(&index, map);
        const pick = index.peek().?;
        index.swapRemoveAt(pick);
        map.swapRemoveAt(pick);
    }
}

test "mixed insert remove duplicate requeue and rank epochs match scan" {
    var map: Map = .empty;
    defer map.deinit(testing.allocator);
    var index: Index = .{};
    defer index.deinit(testing.allocator);
    var rng = std.Random.DefaultPrng.init(0xcea17ed);
    const random = rng.random();
    var next_key: u32 = 0;
    for (0..4096) |step| {
        if (step % 127 == 0) {
            // Same ready keys, changed module ownership/ranks in a new update.
            index.invalidate();
            for (map.values()) |*value| value.* = rank(random.uintLessThan(u32, 7), random.uintLessThan(u32, 5), random.int(u1));
        }
        if (map.count() == 0 or (map.count() < 128 and random.boolean())) {
            const value: Rank = if (step % 11 == 0) .unknown else rank(random.uintLessThan(u32, 7), random.uintLessThan(u32, 5), random.int(u1));
            try map.put(testing.allocator, next_key, value);
            next_key += 1;
            if (index.isActive()) index.append(testing.allocator, value);
        } else if (step % 5 == 0) {
            // Existing-key put must not duplicate a heap member.
            const i = random.uintLessThan(usize, map.count());
            const count = map.count();
            try map.put(testing.allocator, map.keys()[i], map.values()[i]);
            try testing.expectEqual(count, map.count());
        } else {
            // Remove any member, not just the winner; sometimes requeue it.
            const i = random.uintLessThan(usize, map.count());
            const key = map.keys()[i];
            const value = map.values()[i];
            index.swapRemoveAt(i);
            map.swapRemoveAt(i);
            if (step % 3 == 0) {
                try map.put(testing.allocator, key, value);
                if (index.isActive()) index.append(testing.allocator, value);
            }
        }
        try expectSequenceHead(&index, map);
    }
    std.debug.print("sequence oracle: 4096/4096 transitions agree with scan\n", .{});
}

test "transient unknown disables until explicit rank epoch invalidation" {
    var values = [_]Rank{ rank(2, 1, 0), rank(0, 1, 0) };
    var index: Index = .{};
    defer index.deinit(testing.allocator);
    try testing.expect(!index.prepare(testing.allocator, values.len, Context{ .values = &values, .transient = 1 }, Context.get));
    try testing.expectEqual(@as(?usize, null), index.peek());
    // Ownership becomes known; stay on the live scan, not a stale unknown heap.
    try testing.expect(!index.prepare(testing.allocator, values.len, Context{ .values = &values }, Context.get));
    try testing.expectEqual(@as(?usize, 1), scan(&values));
    index.invalidate();
    try testing.expect(index.prepare(testing.allocator, values.len, Context{ .values = &values }, Context.get));
    try testing.expectEqual(scan(&values), index.peek());
    values[0] = rank(0, 9, 0);
    index.invalidate();
    try testing.expect(index.prepare(testing.allocator, values.len, Context{ .values = &values }, Context.get));
    try testing.expectEqual(@as(?usize, 0), index.peek());
}

test "each preparation allocation failure leaves a disabled empty index" {
    const values = [_]Rank{ rank(1, 0, 0), rank(0, 0, 0), .unknown };
    for (0..2) |fail_index| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        const allocator = failing.allocator();
        var index: Index = .{};
        defer index.deinit(allocator);
        try testing.expect(!index.prepare(allocator, values.len, Context{ .values = &values }, Context.get));
        try testing.expect(failing.has_induced_failure);
        try testing.expectEqual(@as(usize, 0), index.nodes.items.len);
        try testing.expectEqual(@as(usize, 0), index.positions.items.len);
        const allocations = failing.allocations;
        try testing.expect(!index.prepare(allocator, values.len, Context{ .values = &values }, Context.get));
        try testing.expectEqual(allocations, failing.allocations);
        failing.fail_index = std.math.maxInt(usize);
        index.invalidate();
        try testing.expect(index.prepare(allocator, values.len, Context{ .values = &values }, Context.get));
        try testing.expectEqual(scan(&values), index.peek());
    }
}

test "each append allocation failure preserves committed ready membership" {
    for (0..2) |fail_index| {
        var map: Map = .empty;
        defer map.deinit(testing.allocator);
        for (0..4) |i| try map.put(testing.allocator, @intCast(i), rank(2, 0, 0));
        var index: Index = .{};
        defer index.deinit(testing.allocator);
        try expectSequenceHead(&index, map);
        // Force both arrays to grow on the next append; no allocator-specific
        // growth factor is assumed. Disable resize/remap to exercise each alloc.
        index.nodes.shrinkAndFree(testing.allocator, map.count());
        index.positions.shrinkAndFree(testing.allocator, map.count());
        var failing = testing.FailingAllocator.init(testing.allocator, .{
            .fail_index = fail_index,
            .resize_fail_index = 0,
        });
        const winner = rank(0, 9, 0);
        try map.put(testing.allocator, 99, winner);
        index.append(failing.allocator(), winner);
        try testing.expect(failing.has_induced_failure);
        try testing.expect(!index.isActive());
        try testing.expectEqual(@as(usize, 5), map.count());
        try testing.expectEqual(@as(u32, 99), map.keys()[scan(map.values()).?]);
        try testing.expectEqual(@as(?usize, null), index.peek());
    }
}

var comparisons: usize = 0;
fn countedBefore(a: Rank, b: Rank) bool {
    comparisons += 1;
    return before(a, b);
}

test "ordinary operations stay logarithmic and peeks do not rescan" {
    const CountedIndex = HeapFactory(Rank, countedBefore);
    const count = 2048;
    var values: [count]Rank = undefined;
    for (&values, 0..) |*value, i| value.* = rank(@intCast(count - i), 0, 0);
    var index: CountedIndex = .{};
    defer index.deinit(testing.allocator);
    comparisons = 0;
    try testing.expect(index.prepare(testing.allocator, count, Context{ .values = &values }, Context.get));
    const build_comparisons = comparisons;
    try testing.expect(build_comparisons < count * 8);
    for (0..count) |_| _ = index.peek();
    try testing.expectEqual(build_comparisons, comparisons);
    // The insertion is a new best value and must traverse the heap height.
    index.append(testing.allocator, rank(0, 0, 0));
    try testing.expect(comparisons - build_comparisons < 64);
    index.swapRemoveAt(count);
    for (0..count) |_| index.swapRemoveAt(index.peek().?);
    const mutations = comparisons - build_comparisons;
    try testing.expect(mutations < count * 128);
    std.debug.print("comparison receipt: heapify {d}; 2048 peeks 0; append/remove/drain {d}; old drain scan {d}\n", .{
        build_comparisons, mutations, count * (count - 1) / 2,
    });
}
