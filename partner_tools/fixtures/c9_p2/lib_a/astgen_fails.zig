//! C9 P2 fixture: a source that AstGen refuses, under `--check-decls`
//! (retained correction 8; the clearing condition widened by retained
//! correction 9). `no_such_root` is never declared anywhere, so
//! `localVarRef` fails with "use of undeclared identifier" and lowering is
//! fatal: the driver renders the normal AstGen diagnostic and exits 1, and
//! rung 2 never runs -- BOTH drivers gate on a clean AstGen pass, and the
//! lowering clears the sidecar before publication whenever the produced ZIR
//! carries ANY diagnostic (correction 9 widened the trigger from fatal-only,
//! because `structDeclInner` may return successfully with compile errors
//! appended), so no partial binding observation made before the failure is
//! ever consumable as a scope census. Under `--check-decls` this path is
//! REQUESTED-THEN-CLEARED, not zero-allocation: the sidecar was requested
//! before lowering and may have allocated facts on the way to the failure;
//! only the flagless and graph-only paths never request it at all.
//! Expected with `--module-graph --check-decls`: exit 1, stderr carries the
//! undeclared-identifier diagnostic, and NO summary line at all -- the file
//! DOES hold a lawful `@import("util")` site whose "import sites seen" line
//! would print if any graph check ran, so its absence pins the gate: no
//! "import sites seen", no "member refs seen", no "direct calls seen". This
//! file is a precondition control: it pins that the facts-consuming rung
//! cannot even be reached on a file whose facts were cleared.

const util = @import("util");

pub fn main() void {
    _ = util.answer;
    _ = no_such_root.member;
}