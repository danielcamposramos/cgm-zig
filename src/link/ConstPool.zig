/// Helper type for debug information implementations (such as `link.Dwarf`) to help them emit
/// information about comptime-known values (constants), including types.
///
/// Every constant with associated debug information is assigned an `Index` by calling `get`. The
/// pool will track which container types do and do not have a resolved layout, as well as which
/// constants in the pool depend on which types, and call into the implementation to emit debug
/// information for a constant only when all information is available.
///
/// Indices into the pool are dense, and constants are never removed from the pool, so the debug
/// info implementation can store information for each one with a simple `ArrayList`.
///
/// To use `ConstPool`, the debug info implementation is required to:
/// * forward `updateContainerType` calls to its `ConstPool`
/// * expose some callback functions---see functions in `User`
/// * ensure that any `get` call is eventually followed by a `flushPending` call
const ConstPool = @This();

values: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
pending: std.ArrayList(Index),
complete_containers: std.AutoArrayHashMapUnmanaged(InternPool.Index, void),
container_deps: std.AutoArrayHashMapUnmanaged(InternPool.Index, ContainerDepEntry.Index),
container_dep_entries: std.ArrayList(ContainerDepEntry),
/// Parallel to `values`: the CROSS-PROCESS content signature of each pooled
/// constant's type. Dense, same index space as `Index`, appended in `get`.
signatures: std.ArrayList(Signature),
/// Reverse index over complete signatures: signature -> the TYPE that produced
/// it, for the collision refusal in `recordSignature`. Keyed by type, NOT by
/// pool slot: `values` is keyed by VALUE, so `@as(u32, 1)` and `@as(u32, 2)`
/// are two pool entries that legitimately share one type signature.
signature_owners: std.AutoHashMapUnmanaged(u64, InternPool.Index),

pub const empty: ConstPool = .{
    .values = .empty,
    .pending = .empty,
    .complete_containers = .empty,
    .container_deps = .empty,
    .container_dep_entries = .empty,
    .signatures = .empty,
    .signature_owners = .empty,
};

pub fn deinit(pool: *ConstPool, gpa: Allocator) void {
    pool.values.deinit(gpa);
    pool.pending.deinit(gpa);
    pool.complete_containers.deinit(gpa);
    pool.container_deps.deinit(gpa);
    pool.container_dep_entries.deinit(gpa);
    pool.signatures.deinit(gpa);
    pool.signature_owners.deinit(gpa);
}

/// A signature that identifies a pooled constant's type by RESOLVED STRUCTURE,
/// so that two SEPARATE compiler processes derive the same value for the same
/// type. This is the identity the project-wide debug-sharing work needs and
/// which no existing key provides: `InternPool.Index` is `{tid, local_offset}`
/// over a worker-thread partition, `*Package.Module` is arena pointer identity,
/// and `Compilation.Path.digest()` hashes the PATH, not the content.
///
/// It signs NOTHING it cannot derive. Every non-derivable case is a NAMED
/// refusal rather than a hash of a placeholder, because a signature that
/// silently covered an unresolved layout would license sharing debug entries
/// between types that are not the same type.
pub const Signature = union(enum) {
    refused: Refusal,
    /// Valid across separate compiler processes for the same compiler version
    /// and target.
    complete: u64,

    pub const Refusal = enum {
        /// The type's layout is not resolved yet, so it has no stable structure.
        layout_unresolved,
        /// This kind's cross-process structure is not derivable by this
        /// increment. Containers, functions, error sets and pointers-to-those
        /// need declaration-site identity, which is the NEXT increment.
        kind_not_yet_derivable,
    };
};

/// Depth bound for the structural walk. A type that nests deeper than this
/// refuses by name rather than recursing without a bound.
const max_signature_depth: u8 = 16;

pub const Index = enum(u32) {
    _,
    pub fn val(i: Index, pool: *const ConstPool) InternPool.Index {
        return pool.values.keys()[@intFromEnum(i)];
    }
};

pub const User = union(enum) {
    dwarf: *@import("Dwarf.zig"),
    c: *@import("C.zig"),
    llvm: @import("../codegen/llvm.zig").Object.Ptr,

    /// Inform the debug info implementation that the new constant `val` was added to the pool at
    /// the given index (which equals the current pool length) due to a `get` call. It is guaranteed
    /// that there will eventually be a call to either `updateConst` or `updateConstIncomplete`
    /// following the `addConst` call, to actually populate the constant's debug info.
    fn addConst(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.addConst(pt, index, val),
        }
    }

    /// Tell the debug info implementation to emit information for the constant `val`, which is in
    /// the pool at the given index. `val` is "complete", which means:
    /// * If it is a type, its layout is known.
    /// * Otherwise, the layout of its type is known.
    fn updateConst(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.updateConst(pt, index, val),
        }
    }

    /// Tell the debug info implementation to emit information for the constant `val`, which is in
    /// the pool at the given index. `val` is "incomplete", meaning the implementation cannot emit
    /// full information for it (for instance, perhaps it is a struct type which was never actually
    /// initialized so never had its layout resolved). Instead, the implementation must emit some
    /// form of placeholder entry representing an incomplete/unknown constant.
    fn updateConstIncomplete(
        user: User,
        pt: Zcu.PerThread,
        index: Index,
        val: InternPool.Index,
    ) Allocator.Error!void {
        switch (user) {
            inline else => |impl| return impl.updateConstIncomplete(pt, index, val),
        }
    }
};

const ContainerDepEntry = extern struct {
    next: ContainerDepEntry.Index.Optional,
    depender: ConstPool.Index,
    const Index = enum(u32) {
        _,
        const Optional = enum(u32) {
            none = std.math.maxInt(u32),
            _,
            fn unwrap(o: Optional) ?ContainerDepEntry.Index {
                return switch (o) {
                    .none => null,
                    else => @enumFromInt(@intFromEnum(o)),
                };
            }
        };
        fn toOptional(i: ContainerDepEntry.Index) Optional {
            return @enumFromInt(@intFromEnum(i));
        }
        fn ptr(i: ContainerDepEntry.Index, pool: *ConstPool) *ContainerDepEntry {
            return &pool.container_dep_entries.items[@intFromEnum(i)];
        }
    };
};

/// Calls to `link.File.updateContainerType` must be forwarded to this function so that the debug
/// constant pool has up-to-date information about the resolution status of types.
pub fn updateContainerType(
    pool: *ConstPool,
    pt: Zcu.PerThread,
    user: User,
    container_ty: InternPool.Index,
    success: bool,
) Allocator.Error!void {
    if (success) {
        const gpa = pt.zcu.comp.gpa;
        try pool.complete_containers.put(gpa, container_ty, {});
    } else {
        _ = pool.complete_containers.fetchSwapRemove(container_ty);
    }
    var opt_dep = pool.container_deps.get(container_ty);
    while (opt_dep) |dep| : (opt_dep = dep.ptr(pool).next.unwrap()) {
        try pool.update(pt, user, dep.ptr(pool).depender);
    }
}

/// After this is called, there may be a constant for which debug information (complete or not) has
/// not yet been emitted, so the user must call `flushPending` at some point after this call.
pub fn get(pool: *ConstPool, pt: Zcu.PerThread, user: User, val: InternPool.Index) Allocator.Error!ConstPool.Index {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.comp.gpa;
    const gop = try pool.values.getOrPut(gpa, val);
    const index: ConstPool.Index = @enumFromInt(gop.index);
    if (!gop.found_existing) {
        const ty: Type = switch (ip.typeOf(val)) {
            .type_type => if (ip.isUndef(val)) .type else .fromInterned(val),
            else => |ty| .fromInterned(ty),
        };
        // Reserve the parallel signature slot BEFORE anything that can re-enter
        // `get` (a container's field types reach back through the user), so
        // `signatures` stays index-aligned with `values`.
        try pool.signatures.append(gpa, .{ .refused = .layout_unresolved });
        try pool.registerTypeDeps(index, ty, zcu);
        try pool.pending.append(gpa, index);
        try pool.recordSignature(zcu, index, ty);
        try user.addConst(pt, index, val);
    }
    return index;
}
pub fn flushPending(pool: *ConstPool, pt: Zcu.PerThread, user: User) Allocator.Error!void {
    while (pool.pending.pop()) |pending_ty| {
        try pool.update(pt, user, pending_ty);
    }
}

fn update(pool: *ConstPool, pt: Zcu.PerThread, user: User, index: ConstPool.Index) Allocator.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const val = index.val(pool);
    const ty: Type = switch (ip.typeOf(val)) {
        .type_type => if (ip.isUndef(val)) .type else .fromInterned(val),
        else => |ty| .fromInterned(ty),
    };
    if (pool.checkType(ty, zcu)) {
        // The layout that was unresolved at `get` time may be resolved now, so
        // a signature refused as `layout_unresolved` can become derivable here.
        try pool.recordSignature(zcu, index, ty);
        try user.updateConst(pt, index, val);
    } else {
        try user.updateConstIncomplete(pt, index, val);
    }
}

/// Compute and store the cross-process signature for `index`, refusing by name
/// when it is not derivable and REFUSING LOUDLY on collision. A signature is a
/// claim about a TYPE; since the intern pool already deduplicates types, two
/// DISTINCT type indices sharing one signature is a defect in the hash, not a
/// legitimate merge. Many pool slots sharing one signature is expected.
fn recordSignature(pool: *ConstPool, zcu: *const Zcu, index: Index, ty: Type) Allocator.Error!void {
    const gpa = zcu.comp.gpa;
    const sig = pool.signatureOf(zcu, ty);
    pool.signatures.items[@intFromEnum(index)] = sig;
    switch (sig) {
        .refused => |why| log.debug("const signature REFUSED ({t}) for pool index {d}", .{
            why, @intFromEnum(index),
        }),
        .complete => |hash| {
            const ty_ip = ty.toIntern();
            const gop = try pool.signature_owners.getOrPut(gpa, hash);
            if (gop.found_existing and gop.value_ptr.* != ty_ip) {
                std.debug.panic(
                    "const signature collision: 0x{x:0>16} claimed by types {d} and {d}",
                    .{ hash, @intFromEnum(gop.value_ptr.*), @intFromEnum(ty_ip) },
                );
            }
            gop.value_ptr.* = ty_ip;
            log.debug("const signature 0x{x:0>16} pool index {d} type {d}", .{
                hash, @intFromEnum(index), @intFromEnum(ty_ip),
            });
        },
    }
}

/// The cross-process signature of `ty`, or a named refusal.
fn signatureOf(pool: *const ConstPool, zcu: *const Zcu, ty: Type) Signature {
    if (!pool.checkType(ty, zcu)) return .{ .refused = .layout_unresolved };
    const target = &zcu.comp.root_mod.resolved_target.result;
    var hasher: std.hash.Wyhash = .init(0);
    // Two compiler versions, or two targets, are two different debug worlds.
    // A signature blind to them would license sharing between entries whose
    // layout or encoding genuinely differs.
    hasher.update(@import("build_options").version);
    std.hash.autoHash(&hasher, target.cpu.arch);
    std.hash.autoHash(&hasher, target.os.tag);
    std.hash.autoHash(&hasher, target.abi);
    std.hash.autoHash(&hasher, target.ofmt);
    if (!hashType(&hasher, ty, zcu, 0)) return .{ .refused = .kind_not_yet_derivable };
    return .{ .complete = hasher.final() };
}

/// Fold the DECLARED KEY of `ty` into `hasher`. Returns false — hashing nothing
/// further — when this kind's cross-process identity is not derivable from the
/// key alone.
///
/// It reads the intern pool's own key rather than restating derived layout,
/// because layout is NOT the identity a debug entry carries. `usize` and `u64`
/// have identical layout on x86_64 and are separate entries with separate
/// names; the pool already distinguishes them as `.simple_type` versus
/// `.int_type`, and the simple-type ordinals are compile-time constants, so
/// that distinction is stable across processes. This was not a design
/// preference: the collision refusal below caught the layout-only version
/// equating those two on the first fixture run.
fn hashType(hasher: *std.hash.Wyhash, ty: Type, zcu: *const Zcu, depth: u8) bool {
    if (depth > max_signature_depth) return false;
    const ip = &zcu.intern_pool;
    const key = ip.indexToKey(ty.toIntern());
    std.hash.autoHash(hasher, @as(std.meta.Tag(InternPool.Key), key));
    switch (key) {
        // A named scalar IS its name. Ordinals are compile-time, so stable.
        .simple_type => |simple| {
            std.hash.autoHash(hasher, @intFromEnum(simple));
            return true;
        },
        .int_type => |int| {
            std.hash.autoHash(hasher, int.signedness);
            std.hash.autoHash(hasher, int.bits);
            return true;
        },
        .array_type => |array| {
            // A sentinel is part of the type but its VALUE is an intern index,
            // which is thread-partitioned and not comparable across processes.
            if (array.sentinel != .none) return false;
            std.hash.autoHash(hasher, array.len);
            return hashType(hasher, .fromInterned(array.child), zcu, depth + 1);
        },
        .vector_type => |vector| {
            std.hash.autoHash(hasher, vector.len);
            return hashType(hasher, .fromInterned(vector.child), zcu, depth + 1);
        },
        .opt_type => |child| return hashType(hasher, .fromInterned(child), zcu, depth + 1),
        // Pointers, containers, functions and error sets need their full key
        // folded (a pointer's constness, alignment, address space and sentinel
        // all change the emitted entry) or declaration-site identity, which
        // this increment does not derive. Named, never silently hashed.
        else => return false,
    }
}

fn checkType(pool: *const ConstPool, ty: Type, zcu: *const Zcu) bool {
    if (ty.isGenericPoison()) return true;
    return switch (ty.zigTypeTag(zcu)) {
        .type,
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .pointer,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .error_set,
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        => true,

        .array, .vector => pool.checkType(ty.childType(zcu), zcu),
        .optional => pool.checkType(ty.optionalChild(zcu), zcu),
        .error_union => pool.checkType(ty.errorUnionPayload(zcu), zcu),
        .@"fn" => {
            const ip = &zcu.intern_pool;
            const func = ip.indexToKey(ty.toIntern()).func_type;
            for (func.param_types.get(ip)) |param_ty_ip| {
                if (!pool.checkType(.fromInterned(param_ty_ip), zcu)) return false;
            }
            return pool.checkType(.fromInterned(func.return_type), zcu);
        },
        .@"struct" => if (ty.isTuple(zcu)) {
            for (0..ty.structFieldCount(zcu)) |field_index| {
                if (!pool.checkType(ty.fieldType(field_index, zcu), zcu)) return false;
            }
            return true;
        } else {
            return pool.complete_containers.contains(ty.toIntern());
        },
        .@"union", .@"enum" => {
            return pool.complete_containers.contains(ty.toIntern());
        },
    };
}
fn registerTypeDeps(pool: *ConstPool, root: Index, ty: Type, zcu: *const Zcu) Allocator.Error!void {
    if (ty.isGenericPoison()) return;
    switch (ty.zigTypeTag(zcu)) {
        .type,
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .pointer,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .error_set,
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        => {},

        .array, .vector => try pool.registerTypeDeps(root, ty.childType(zcu), zcu),
        .optional => try pool.registerTypeDeps(root, ty.optionalChild(zcu), zcu),
        .error_union => try pool.registerTypeDeps(root, ty.errorUnionPayload(zcu), zcu),
        .@"fn" => {
            const ip = &zcu.intern_pool;
            const func = ip.indexToKey(ty.toIntern()).func_type;
            for (func.param_types.get(ip)) |param_ty_ip| {
                try pool.registerTypeDeps(root, .fromInterned(param_ty_ip), zcu);
            }
            try pool.registerTypeDeps(root, .fromInterned(func.return_type), zcu);
        },
        .@"struct", .@"union", .@"enum" => if (ty.isTuple(zcu)) {
            for (0..ty.structFieldCount(zcu)) |field_index| {
                try pool.registerTypeDeps(root, ty.fieldType(field_index, zcu), zcu);
            }
        } else {
            // `ty` is a container; register the dependency.

            const gpa = zcu.comp.gpa;
            try pool.container_deps.ensureUnusedCapacity(gpa, 1);
            try pool.container_dep_entries.ensureUnusedCapacity(gpa, 1);
            errdefer comptime unreachable;

            const gop = pool.container_deps.getOrPutAssumeCapacity(ty.toIntern());
            const entry: ContainerDepEntry.Index = @enumFromInt(pool.container_dep_entries.items.len);
            pool.container_dep_entries.appendAssumeCapacity(.{
                .next = if (gop.found_existing) gop.value_ptr.toOptional() else .none,
                .depender = root,
            });
            gop.value_ptr.* = entry;
        },
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
/// Observable with `--debug-log const_pool` on a compiler built with `-Dlog`.
const log = std.log.scoped(.const_pool);

const InternPool = @import("../InternPool.zig");
const Type = @import("../Type.zig");
const Zcu = @import("../Zcu.zig");
