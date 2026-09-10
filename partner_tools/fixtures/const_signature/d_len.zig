// Control: length differs ([96]u23). Must NOT share A's signature.
pub const delta: [96]u23 = @splat(@as(u23, 3));
pub export fn d_entry() u32 {
    return delta[0];
}
