// Process A. The discriminating type is [97]u23 — deliberately odd so its
// signature cannot be confused with an incidental primitive.
pub const alpha: [97]u23 = @splat(@as(u23, 3));
pub export fn a_entry() u32 {
    return alpha[0];
}
