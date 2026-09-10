// Process B. Different file, different decl names, different surrounding
// shape, SAME type [97]u23. Nothing is shared but the structure itself.
fn helper(x: u23) u23 {
    return x +% 1;
}
pub const zeta: [97]u23 = @splat(@as(u23, 9));
pub export fn b_entry() u32 {
    return helper(zeta[96]);
}
