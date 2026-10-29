//! C9 P2 fixture: one of the two modules that share the fully_qualified_name
//! "c9p2.twin" (graph.json index 6, root lib_t1) -- the --as-module name
//! ambiguity pair. `fully_qualified_name` is documented convention, not
//! guaranteed-unique identity, and this pair makes that claim checkable.

pub fn twinFn() void {}