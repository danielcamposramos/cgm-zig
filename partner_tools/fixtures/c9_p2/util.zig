//! C9 P2 fixture: the target module every checked file reaches through the
//! graph edge named "util" (graph.json index 0, root "."). Its public surface
//! is the rung-2 assertion surface: `helper` (pub fn with a body, 0 fixed
//! parameters -- an exact_fn(0) arity target), `answer` (pub const), and
//! `extfn` (pub extern fn PROTOTYPE -- the BLOCKER 1 shape: a body-less
//! prototype wears a `fn_proto*` tag, not `fn_decl`, and a rung 2 that
//! collected only `.fn_decl` would report every legal reference to it as a
//! MISSING declaration; 1 fixed parameter -- an exact_fn(1) target).
//! `hidden` is deliberately NOT public: a reference to it must be reported
//! as missing, never silently resolved to a private declaration.
//!
//! Arity-shape surface (retained arity dispatch), each declaration
//! deliberately unsuitable for naive equality: `generic` carries a
//! `comptime` parameter, `varargs` an extern `...` marker, and `anyfn` an
//! `anytype` parameter (the distinct `FnProto.Iterator.Param`
//! `.anytype_ellipsis3` branch) -- all three dynamic_fn, counted
//! skipped-dynamic, never compared. `fnval` is a public const of
//! function type -- other_decl, counted skipped-non-fn (may be
//! function-valued after Sema; never called non-callable, never
//! compared). `Thing` is a public container type with TWO function
//! shapes for the correction-5 negative control: `staticCall` (no
//! receiver -- the deeper-qualified `util.Thing.staticCall()` call's
//! outer callee is a two-hop field access, outside the arity population,
//! while its inner `util.Thing` is name-validated) and `method` (an
//! INSTANCE method taking an explicit `self: Thing`, so a value-receiver
//! call `thing.method()` is actual receiver sugar -- its callee field
//! access has a non-import identifier LHS, an ignored unsupported shape;
//! no implicit receiver is ever inferred or compared).

pub fn helper() void {}

pub const answer: usize = 42;

pub extern fn extfn(x: u32) u32;

pub fn generic(comptime T: type, value: T) T {
    return value;
}

pub extern fn varargs(fmt: [*:0]const u8, ...) void;

pub fn anyfn(value: anytype) void {
    _ = value;
}

pub const fnval: fn (u32) u32 = undefined;

pub const Thing = struct {
    pub fn staticCall() void {}

    pub fn method(self: Thing) void {
        _ = self;
    }
};

fn hidden() void {}