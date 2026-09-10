// Control: element width differs ([97]u24). Must NOT share A's signature.
pub const gamma: [97]u24 = @splat(@as(u24, 3));
pub export fn c_entry() u32 {
    return gamma[0];
}
