#!/usr/bin/env python3
"""c9_p2_controls.py -- offline preflight + control manifest for Crown stage
0.5 rungs 2 (--check-decls) and 4 (--as-module), the C9/P2 packet
(docs/crown/C9_P2_PACKET_2026-09-12.md).

HONESTLY UNEXECUTED. No control in this manifest has been run against any
compiler binary. This file was authored under a work order that prohibited
running the compiler; every `exit`, `stderr_has` and expected count below is
a PREDICTION derived from reading the integrated source (src/AstCheckImports.zig,
src/AstCheckBatch.zig, src/main.zig), not an observation. A prediction that
is wrong is a finding about the code, and that is the point of writing the
control down before running it.

Two modes:

  default      run the OFFLINE PREFLIGHT and print the manifest. The
               preflight verifies the fixture estate's INTERNAL consistency
               (the graph parses, every edge resolves, every asserted-present
               public declaration is spelled in its target file, every
               referenced file exists). It is deliberately NOT a re-
               implementation of the checker: preflight passing says the
               fixtures can support the controls, nothing more. PREFLIGHT IS
               NOT PROOF.

  --run ZIG    execute every control with ZIG (cwd is forced to the fixture
               directory -- the same-cwd contract). For the retained
               reviewer, on a rebuilt binary, after review. PASS/FAIL is
               decided only here, never by source reading. Controls that
               name a rendered fixture materialize it first (see
               ABS_OPERAND_TEMPLATE: an absolute operand varies by checkout).

The same-cwd contract: graph.json records module roots relative to this
fixture directory, the way -femit-module-graph renders them relative to the
emitting process's cwd. Every control runs with cwd = fixtures/c9_p2/.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures", "c9_p2")

# ---------------------------------------------------------------------------
# Expected-output helpers. These reproduce, field for field, the format
# strings in src/AstCheckImports.zig (printSummary / printDeclSummary) so the
# expected text cannot drift from the real format by transcription error.
# Changing one side without the other is a review finding, by design.
# ---------------------------------------------------------------------------


def import_line(seen, file_imports, named_imports, exempt=0, skipped=0):
    return (
        "import sites seen %d: validated %d (file %d, named %d), "
        "exempt(std/builtin/root) %d, skipped-unchecked %d"
        % (seen, file_imports + named_imports, file_imports, named_imports, exempt, skipped)
    )


def strict_line(seen, file_imports, named_imports, sandbox_unresolvable, module_name, module_index,
                exempt=0, skipped=0):
    return (
        import_line(seen, file_imports, named_imports, exempt, skipped)
        + ", sandbox-unresolvable %d; semantics strict (as module '%s', graph index %d: "
        "named imports checked against that module's own deps, file imports sandboxed to its root)"
        % (sandbox_unresolvable, module_name, module_index)
    )


def decl_line(seen, validated=0, missing=0, opaque=0, deep=0, unres=0, unread=0,
              unparsable=0, exempt=0):
    return (
        "member refs seen %d: validated %d, missing %d, opaque-skipped %d, alias-too-deep %d, "
        "target-unresolvable %d, target-unreadable %d, "
        "operand-unparsable %d, exempt %d"
        % (seen, validated, missing, opaque, deep, unres, unread, unparsable, exempt)
    )


def arity_line(seen, matched=0, mismatch=0, dynamic=0, nonfn=0, unavailable=0):
    return (
        "direct calls seen %d: arity-matched %d, arity-mismatch %d, arity-skipped-dynamic %d, "
        "arity-skipped-non-fn %d, arity-unavailable %d; arity: syntactic fixed-parameter counts "
        "only -- no types, no comptime, no implicit receiver"
        % (seen, matched, mismatch, dynamic, nonfn, unavailable)
    )


# ---------------------------------------------------------------------------
# JSON-document assertions (rung-3 --json consumers). Each takes the parsed
# stdout document and returns a list of failure strings (empty == pass).
# ---------------------------------------------------------------------------


def _row(doc, path):
    for r in doc["files"]:
        if r["path"] == path:
            return r
    return None


def _stats_want(want, got, label, fails):
    for k, v in want.items():
        if got.get(k) != v:
            fails.append("%s: %s == %r, want %r" % (label, k, got.get(k), v))


def _check_union_batch(doc):
    """Control C9P2-28: the 5-file union-semantics batch as one JSON document."""
    # The arity pins below include ZEROS deliberately: the additive `arity_*` fields must be
    # present and zero on rows whose files hold no qualifying direct calls, not merely
    # tolerated as absent or unknown.
    fails = []
    s = doc["summary"]
    _stats_want(
        {"requested": 5, "checked": 2, "failed": 1, "skipped": 1, "graph_not_applicable": 1},
        s, "summary", fails,
    )
    _stats_want(
        {"file_imports": 0, "named_imports": 5, "exempt": 0, "skipped_nonliteral": 0,
         "sandbox_unresolvable": 0},
        s["import_stats"], "summary.import_stats", fails,
    )
    _stats_want(
        {"validated": 4, "missing": 3, "opaque_skipped": 0, "alias_too_deep": 0,
         "target_unresolvable": 1, "target_unreadable": 0,
         "operand_unparsable": 0, "exempt": 0,
         "arity_matched": 2, "arity_mismatch": 0, "arity_skipped_dynamic": 0,
         "arity_skipped_non_fn": 0, "arity_unavailable": 0},
        s["decl_stats"], "summary.decl_stats", fails,
    )

    r = _row(doc, "lib_a/checked_ok.zig")
    if r is None:
        fails.append("no row for lib_a/checked_ok.zig")
    else:
        _stats_want({"status": "ok", "check_semantics": "union", "as_module_name": None},
                    r, "checked_ok", fails)
        _stats_want({"file_imports": 0, "named_imports": 2}, r["import_stats"],
                    "checked_ok.import_stats", fails)
        _stats_want({"validated": 4, "arity_matched": 2, "arity_mismatch": 0,
                     "arity_skipped_dynamic": 0, "arity_skipped_non_fn": 0,
                     "arity_unavailable": 0},
                    r["decl_stats"], "checked_ok.decl_stats", fails)

    r = _row(doc, "lib_a/missing_decl.zig")
    if r is None:
        fails.append("no row for lib_a/missing_decl.zig")
    else:
        _stats_want({"status": "failed", "check_semantics": "union"}, r, "missing_decl", fails)
        _stats_want({"missing": 3, "arity_matched": 0, "arity_mismatch": 0,
                     "arity_skipped_dynamic": 0, "arity_skipped_non_fn": 0,
                     "arity_unavailable": 0},
                    r["decl_stats"], "missing_decl.decl_stats", fails)
        msgs = [e["msg"] for e in r["errors"]]
        for want in ("nope_missing", "also_missing", "hidden"):
            if not any(want in m for m in msgs):
                fails.append("missing_decl errors lack '%s' (msgs: %r)" % (want, msgs))

    r = _row(doc, "lib_b/wrong_binding.zig")
    if r is None:
        fails.append("no row for lib_b/wrong_binding.zig")
    else:
        _stats_want({"status": "ok", "check_semantics": "union"}, r, "wrong_binding", fails)
        _stats_want({"target_unresolvable": 1, "arity_matched": 0, "arity_mismatch": 0,
                     "arity_skipped_dynamic": 0, "arity_skipped_non_fn": 0,
                     "arity_unavailable": 0},
                    r["decl_stats"], "wrong_binding.decl_stats", fails)

    r = _row(doc, "missing_on_disk.zig")
    if r is None:
        fails.append("no row for missing_on_disk.zig")
    else:
        _stats_want({"status": "skipped"}, r, "missing_on_disk", fails)
        if "unable to open" not in (r.get("reason") or ""):
            fails.append("missing_on_disk reason lacks 'unable to open': %r" % r.get("reason"))

    r = _row(doc, "lib_a/data.zon")
    if r is None:
        fails.append("no row for lib_a/data.zon")
    else:
        _stats_want({"status": "ok", "graph_check": "not_applicable_zon", "import_stats": None,
                     "decl_stats": None, "check_semantics": None, "as_module_name": None},
                    r, "data.zon", fails)
    return fails


def _check_strict_batch(doc):
    """Control C9P2-30: strict binding + decl check across a 2-file batch."""
    fails = []
    s = doc["summary"]
    _stats_want({"requested": 2, "checked": 2, "failed": 0, "skipped": 0, "graph_not_applicable": 0},
                s, "summary", fails)
    _stats_want({"file_imports": 1, "named_imports": 4, "sandbox_unresolvable": 0},
                s["import_stats"], "summary.import_stats", fails)
    _stats_want({"validated": 5, "opaque_skipped": 2,
                 "arity_matched": 2, "arity_mismatch": 0, "arity_skipped_dynamic": 0,
                 "arity_skipped_non_fn": 0, "arity_unavailable": 0},
                s["decl_stats"], "summary.decl_stats", fails)

    for path, want_stats, want_decl in (
        ("lib_a/checked_ok.zig", {"file_imports": 0, "named_imports": 2},
         {"validated": 4, "arity_matched": 2, "arity_mismatch": 0,
          "arity_skipped_dynamic": 0, "arity_skipped_non_fn": 0, "arity_unavailable": 0}),
        ("lib_a/opacity.zig", {"file_imports": 1, "named_imports": 2},
         {"validated": 1, "opaque_skipped": 2, "arity_matched": 0, "arity_mismatch": 0,
          "arity_skipped_dynamic": 0, "arity_skipped_non_fn": 0, "arity_unavailable": 0}),
    ):
        r = _row(doc, path)
        if r is None:
            fails.append("no row for %s" % path)
            continue
        _stats_want({"status": "ok", "check_semantics": "strict", "as_module_name": "c9p2.alpha"},
                    r, path, fails)
        _stats_want(want_stats, r["import_stats"], "%s.import_stats" % path, fails)
        _stats_want(want_decl, r["decl_stats"], "%s.decl_stats" % path, fails)
    return fails


# ---------------------------------------------------------------------------
# The control manifest. Every entry is UNEXECUTED. argv is relative to the
# fixture directory; expected exit codes and output fragments are predictions
# from the integrated source, cross-checked by preflight against the graph.
# ---------------------------------------------------------------------------

BATCH_DENOM_FILES = [
    "lib_a/checked_ok.zig",
    "lib_a/missing_decl.zig",
    "lib_b/wrong_binding.zig",
    "missing_on_disk.zig",
    "lib_a/data.zon",
]

# C9P2-32's checked file is RENDERED at run time, not hand-authored: the discriminating
# operand is an ABSOLUTE path to this checkout's util.zig, and no static fixture can spell
# one portably (it varies by checkout; a path outside the repository varies by machine).
# The rendered input is valid for this checker through its real gate: a string-literal
# operand parses AND passes AstGen (import-path resolution is Sema's job, not AstGen's),
# so both shipped drivers proceed to the graph and decl checks on it -- which is why the
# control is expressible rather than documented as infeasible. --run writes it into the
# fixture directory; the default manifest mode never writes anything.
ABS_OPERAND_TEMPLATE = '''//! abs_operand.zig -- RENDERED by c9_p2_controls.py --run (control C9P2-32), never
//! a hand-authored fixture: the discriminating operand is an ABSOLUTE path to this
//! checkout's util.zig, which no static file can spell portably. Both member refs go
//! through inline shape (a). With the one resolution seam (resolveImportPath) an
//! absolute operand is treated as absolute: rung 1 validates both file imports and
//! rung 2 checks both members against the real util.zig -- helper validated,
//! nope_missing missing. A bare std.fs.path.join -- the senior-review BLOCKER this
//! control discriminates against -- does not reset on an absolute component, so it
//! resolved each operand to a path inside the fixture directory and failed rung 1
//! with "does not exist on disk" (and rung 2 reported both members target-unreadable).

pub fn main() void {
    _ = @import("{abs_util}").helper();
    _ = @import("{abs_util}").nope_missing;
}
'''

# Fixture files the CONTROLS reference that --run renders first (see ABS_OPERAND_TEMPLATE).
RENDERED_FILES = {"abs_operand.zig"}

CONTROLS = [
    # ---------------- rung 2 (--check-decls) ----------------
    {
        "id": "C9P2-01",
        "rung": 2,
        "desc": "missing-decl red: three member refs through a lawful import name "
                "declarations the target does not expose; rung 1 alone stays green",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_a/missing_decl.zig"],
        "exit": 1,
        "stderr_has": [
            "referenced declaration not found: 'nope_missing' is not a public top-level declaration of",
            "referenced declaration not found: 'also_missing' is not a public top-level declaration of",
            "referenced declaration not found: 'hidden' is not a public top-level declaration of",
            import_line(2, 0, 2),
            decl_line(3, missing=3),
            arity_line(0),
        ],
    },
    {
        "id": "C9P2-02",
        "rung": 2,
        "desc": "validated green: shapes (a) and (b) plus the extern PROTOTYPE "
                "(BLOCKER 1: fn_proto* collection); byte-exact three summary lines. The "
                "arity line pins the two exact matches the file already held -- "
                "util.helper() and util.extfn(1) are direct calls through the root alias "
                "whose targets are exact_fn(0)/exact_fn(1) -- while the two `answer` "
                "references are not direct calls and contribute nothing to the arity "
                "denominator",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_a/checked_ok.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(4, validated=4) + "\n"
                     + arity_line(2, matched=2),
    },
    {
        "id": "C9P2-03",
        "rung": 2,
        "desc": "alias discrimination after retained corrections 3 and 8: the root "
                "simple alias and the function-LOCAL direct-const import both validated "
                "and the root identifier chain counted alias-too-deep. Succession "
                "(doctrine 7): correction 3 first predicted 'member refs seen 2: "
                "validated 1 ... alias-too-deep 1' and 'direct calls seen 0' here, "
                "because 'name-level analysis cannot lexically own a non-root "
                "binding'; correction 8 ended that stance by exporting AstGen's own "
                "binding decisions (the sidecar), so the local binding is judged by "
                "its exact declaration -- validated, and its one direct call "
                "local_import.helper() enters the arity population with a match "
                "(helper is exact_fn(0), called with 0). Exit stays 0",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_a/alias_too_deep.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(3, validated=2, deep=1) + "\n"
                     + arity_line(1, matched=1),
    },
    {
        "id": "C9P2-04",
        "rung": 2,
        "desc": "ambiguous import name ('shared' -> two distinct targets): counted "
                "target-unresolvable, exit 0; rung 1's union accepted the same name",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_b/wrong_binding.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(1, unres=1) + "\n" + arity_line(0),
    },
    {
        "id": "C9P2-05",
        "rung": 2,
        "desc": "null dep_index ('broken'): counted target-unresolvable, exit 0",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_b/unresolved_target.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(1, unres=1) + "\n" + arity_line(0),
    },
    {
        "id": "C9P2-06",
        "rung": 2,
        "desc": "unreadable target (lib_g/ghost_src.zig absent): an ERROR distinct from "
                "'missing' -- missing must stay 0",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_b/unreadable_target.zig"],
        "exit": 1,
        "stderr_has": [
            "cannot check member 'thing': target file",
            "could not be read or parsed as Zig source",
            "this run resolved against base",
            import_line(1, 0, 1),
            decl_line(1, unread=1),
            arity_line(0),
        ],
        "stderr_lacks": ["referenced declaration not found"],
    },
    {
        "id": "C9P2-07",
        "rung": 2,
        "desc": "opacity: comptime target and .zon target counted opaque-skipped "
                "beside one real validated ref",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "lib_a/opacity.zig"],
        "exit": 0,
        "stderr_eq": import_line(3, 1, 2) + "\n" + decl_line(3, validated=1, opaque=2) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-08",
        "rung": 2,
        "desc": "rung-2 schema gate: a document without index/root/root_src_path is "
                "refused by name; no summary line is printed",
        "argv": ["ast-check", "--module-graph=graph_missing_fields.json", "--check-decls",
                 "lib_a/checked_ok.zig"],
        "exit": 1,
        "stderr_has": [
            "module graph 'graph_missing_fields.json' cannot satisfy --check-decls: "
            "module at array position 0 has no 'index' field",
            "Re-emit the graph with a compiler that includes Crown stage 0",
        ],
        "stderr_lacks": ["import sites seen", "member refs"],
    },
    {
        "id": "C9P2-09",
        "rung": 2,
        "desc": "BLOCKER 2 additive contract: rung 1 ALONE accepts the same field-less "
                "document unchanged (byte-exact rung-1 summary line)",
        "argv": ["ast-check", "--module-graph=graph_missing_fields.json", "lib_a/checked_ok.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2),
    },
    {
        "id": "C9P2-10",
        "rung": 2,
        "desc": "--check-decls without --module-graph refuses by name",
        "argv": ["ast-check", "--check-decls", "lib_a/checked_ok.zig"],
        "exit": 1,
        "stderr_has": ["--check-decls requires --module-graph=<path>"],
        "stderr_lacks": ["import sites seen"],
    },

    # ---------------- rung 4 (--as-module) ----------------
    {
        "id": "C9P2-11",
        "rung": 4,
        "desc": "correct binding green: strict summary clause names the module and index",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "lib_a/checked_ok.zig"],
        "exit": 0,
        "stderr_eq": strict_line(2, 0, 2, 0, "c9p2.alpha", 1),
    },
    {
        "id": "C9P2-12",
        "rung": 4,
        "desc": "wrong binding red: beta does not declare 'shared' even though the "
                "graph-wide union accepts it",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.beta",
                 "lib_b/wrong_binding.zig"],
        "exit": 1,
        "stderr_has": [
            "module 'c9p2.beta' does not declare import 'shared' (rung-4 --as-module strict semantics",
            strict_line(1, 0, 1, 0, "c9p2.beta", 2),
        ],
    },
    {
        "id": "C9P2-13",
        "rung": 4,
        "desc": "sandbox control, rung-1 half: both file imports exist and validate "
                "without a binding (the code --as-module will refuse is legal today)",
        "argv": ["ast-check", "--module-graph=graph.json", "lib_a/escape.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 2, 0),
    },
    {
        "id": "C9P2-14",
        "rung": 4,
        "desc": "sandbox control, strict half: '../util.zig' leaves alpha's root; the "
                "violation says it is a chosen strictness, not a compiler rule",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "lib_a/escape.zig"],
        "exit": 1,
        "stderr_has": [
            "@import leaves module 'c9p2.alpha''s root directory",
            "This is a strictness --as-module CHOOSES, not a compiler rule",
            strict_line(2, 2, 0, 0, "c9p2.alpha", 1),
        ],
    },
    {
        "id": "C9P2-15",
        "rung": 4,
        "desc": "membership premise: binding a file that is not inside the module's "
                "root fails by name before any import verdict is trusted",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "outsider.zig"],
        "exit": 1,
        "stderr_has": [
            "--as-module premise fails: 'outsider.zig' resolves to",
            "not inside module 'c9p2.alpha''s root",
            strict_line(1, 0, 1, 0, "c9p2.alpha", 1),
        ],
    },
    {
        "id": "C9P2-16",
        "rung": 4,
        "desc": "ambiguous fully_qualified_name: 'c9p2.twin' refuses, listing both indices",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.twin",
                 "lib_t1/checked_twin.zig"],
        "exit": 1,
        "stderr_has": [
            "--as-module value 'c9p2.twin' is ambiguous: 2 modules share this "
            "fully_qualified_name (indices: 6, 7)",
        ],
        "stderr_lacks": ["import sites seen"],
    },
    {
        "id": "C9P2-17",
        "rung": 4,
        "desc": "index fallback, correct twin: --as-module=6 binds lib_t1's twin; strict green",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=6",
                 "lib_t1/checked_twin.zig"],
        "exit": 0,
        "stderr_eq": strict_line(1, 0, 1, 0, "c9p2.twin", 6),
    },
    {
        "id": "C9P2-18",
        "rung": 4,
        "desc": "index fallback, wrong twin: --as-module=7 binds lib_t2's twin; the "
                "membership premise fails by name",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=7",
                 "lib_t1/checked_twin.zig"],
        "exit": 1,
        "stderr_has": [
            "--as-module premise fails: 'lib_t1/checked_twin.zig' resolves to",
            "not inside module 'c9p2.twin''s root",
        ],
    },
    {
        "id": "C9P2-19",
        "rung": 4,
        "desc": "unknown name refusal: names how many modules the graph actually has",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.ghost",
                 "outsider.zig"],
        "exit": 1,
        "stderr_has": [
            "--as-module value 'c9p2.ghost' does not match any module's fully_qualified_name "
            "and is not a numeric index (9 module(s) available",
        ],
        "stderr_lacks": ["import sites seen"],
    },
    {
        "id": "C9P2-20",
        "rung": 4,
        "desc": "out-of-range index refusal",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=99", "outsider.zig"],
        "exit": 1,
        "stderr_has": ["--as-module index 99 does not exist in the module graph (9 module(s) available)"],
        "stderr_lacks": ["import sites seen"],
    },
    {
        "id": "C9P2-21",
        "rung": 4,
        "desc": "rung-4 schema gate: the same field-less document is refused for "
                "--as-module, naming flag and field",
        "argv": ["ast-check", "--module-graph=graph_missing_fields.json",
                 "--as-module=c9p2.alpha", "lib_a/checked_ok.zig"],
        "exit": 1,
        "stderr_has": [
            "module graph cannot satisfy --as-module: module at array position 0 "
            "has no 'index' field",
        ],
        "stderr_lacks": ["import sites seen"],
    },
    {
        "id": "C9P2-22",
        "rung": 4,
        "desc": "--as-module without --module-graph refuses by name",
        "argv": ["ast-check", "--as-module=c9p2.alpha", "lib_a/checked_ok.zig"],
        "exit": 1,
        "stderr_has": ["--as-module requires --module-graph=<path>"],
        "stderr_lacks": ["import sites seen"],
    },
    {
        "id": "C9P2-23",
        "rung": "2+4",
        "desc": "flags compose: strict binding + decl check on the opacity file; strict "
                "green with opaque-skipped accounted",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "--check-decls", "lib_a/opacity.zig"],
        "exit": 0,
        "stderr_eq": strict_line(3, 1, 2, 0, "c9p2.alpha", 1) + "\n"
                     + decl_line(3, validated=1, opaque=2) + "\n"
                     + arity_line(0),
    },

    # ---------------- rung 3 contracts retained (flagless / rung-1 / batch / JSON) ----------------
    {
        "id": "C9P2-24",
        "rung": 3,
        "desc": "flagless ast-check unchanged: no output at all",
        "argv": ["ast-check", "lib_a/checked_ok.zig"],
        "exit": 0,
        "stdout_eq": "",
        "stderr_eq": "",
    },
    {
        "id": "C9P2-25",
        "rung": 3,
        "desc": "rung-1-only summary byte-exact and unchanged: no strict clause, no decl line",
        "argv": ["ast-check", "--module-graph=graph.json", "lib_a/checked_ok.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2),
    },
    {
        "id": "C9P2-26",
        "rung": 3,
        "desc": "rung-3 plain batch unchanged: per-file path-attributed lines, one "
                "summary line, nothing new",
        "argv": ["ast-check", "--module-graph=graph.json", "lib_a/checked_ok.zig",
                 "lib_b/wrong_binding.zig"],
        "exit": 0,
        "stderr_has": [
            "lib_a/checked_ok.zig: " + import_line(2, 0, 2),
            "lib_b/wrong_binding.zig: " + import_line(1, 0, 1),
            "files: requested 2, checked 2, failed 0, skipped 0",
        ],
        "stderr_lacks": ["semantics strict", "member refs", "sandbox-unresolvable",
                         "skips are not passes"],
    },
    {
        "id": "C9P2-27",
        "rung": 3,
        "desc": "batch denominator: requested 5 = checked 2 + failed 1 + skipped 1; the "
                "skip is listed with its reason; the .zon member is named not-applicable; "
                "per-file decl lines carry path attribution",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls"] + BATCH_DENOM_FILES,
        "exit": 1,
        "stderr_has": [
            "files: requested 5, checked 2, failed 1, skipped 1 (skips are not passes) "
            "(1 .zon file(s) not checked against --module-graph: ZON has no imports)",
            "skipped: missing_on_disk.zig: unable to open",
            "lib_a/checked_ok.zig: " + decl_line(4, validated=4),
            "lib_b/wrong_binding.zig: " + decl_line(1, unres=1),
            "lib_a/missing_decl.zig: " + decl_line(3, missing=3),
            "lib_a/checked_ok.zig: " + arity_line(2, matched=2),
            "lib_b/wrong_binding.zig: " + arity_line(0),
            "lib_a/missing_decl.zig: " + arity_line(0),
        ],
        "stderr_lacks": ["lib_a/data.zon"],
    },
    {
        "id": "C9P2-28",
        "rung": 3,
        "desc": "batch JSON schema: union rows carry check_semantics/as_module_name and "
                "decl_stats; summary aggregates every stats field; the skipped and "
                "not-applicable rows state their conditions",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "--json"]
                + BATCH_DENOM_FILES,
        "exit": 1,
        "json": _check_union_batch,
    },
    {
        "id": "C9P2-29",
        "rung": "3+4",
        "desc": "one --as-module binds ALL .zig members of a batch: the member passes "
                "strict, the non-member fails the premise, the batch continues",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "lib_a/checked_ok.zig", "lib_b/wrong_binding.zig"],
        "exit": 1,
        "stderr_has": [
            "files: requested 2, checked 1, failed 1, skipped 0",
            "--as-module premise fails: 'lib_b/wrong_binding.zig' resolves to",
            "module 'c9p2.alpha' does not declare import 'shared'",
            "lib_a/checked_ok.zig: " + strict_line(2, 0, 2, 0, "c9p2.alpha", 1),
        ],
    },
    {
        "id": "C9P2-30",
        "rung": "3+2+4",
        "desc": "batch JSON, strict + decls composed: every row reports strict "
                "semantics and the bound module name; summary decl_stats aggregates",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "--check-decls", "--json", "lib_a/checked_ok.zig", "lib_a/opacity.zig"],
        "exit": 0,
        "json": _check_strict_batch,
    },
    {
        "id": "C9P2-31",
        "rung": "all",
        "desc": "the help text states both flags' honest scope: name existence plus the "
                "exact arity syntax boundary (retired: 'NAME EXISTENCE ONLY'), the "
                "same-cwd contract, and the sandbox DIVERGENCE",
        "argv": ["ast-check", "--help"],
        "exit": 0,
        "stdout_has": [
            "--check-decls",
            "--as-module=<name-or-index>",
            "the SYNTACTIC argument count of",
            "fixed syntactic parameter count",
            "counted skipped, never compared",
            "outside the population, never guessed",
            "Named-import member targets resolve through the graph-wide",
            "they resolve through exactly that module's own",
            "Must be run from the same",
            "working directory the graph was emitted from",
            "DIVERGENCE, stated: the sandbox check is a strictness this",
        ],
        "stdout_lacks": ["NAME EXISTENCE ONLY", "DEFERRED"],
    },

    # ---------------- senior-review corrections on this packet's own first delivery ----------------
    {
        "id": "C9P2-32",
        "rung": "1+2",
        "desc": "absolute-operand seam (senior-review BLOCKER): an ABSOLUTE @import operand "
                "resets at the one resolution seam, so rung 1 validates both file imports "
                "and rung 2 checks both members against the real target; the bare join the "
                "first delivery kept in classifyMemberRef resolved the operand INTO the "
                "fixture directory and failed rung 1 with 'does not exist on disk' "
                "instead. The checked file is RENDERED at run time -- an absolute path "
                "varies by checkout -- so preflight can only check its template statically",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls", "abs_operand.zig"],
        "exit": 1,
        # A SEQUENCE of (path, template) pairs -- run_control unpacks each element as a
        # pair, so a bare 2-tuple here would iterate its two strings and fail the harness
        # before Zig ever runs (final readback on the first delivery of this control).
        "render": [("abs_operand.zig", ABS_OPERAND_TEMPLATE)],
        "stderr_has": [
            import_line(2, 2, 0),
            decl_line(2, validated=1, missing=1),
            arity_line(1, matched=1),
        ],
        "stderr_lacks": [
            "does not exist on disk",
            "could not be read or parsed as Zig source",
        ],
    },
    {
        "id": "C9P2-33",
        "rung": 2,
        "desc": "sibling-scope name collision (retained correction 3, its refusal "
                "boundary kept for one shape by retained correction 8): two function "
                "scopes lawfully reuse one local name -- one bound to @import, one to "
                "a plain value. The first delivery's per-name local sets counted both "
                "accesses alias-name-conflict; correction 3 retired that bucket "
                "entirely because a file-wide spelling set is not lexical ownership -- "
                "it could not tell the accesses apart, it only renamed the guess. "
                "Correction 8 splits the two same-spelled uses by EXACT OWNER: the "
                "import binding is now followed (its m.helper() call validated and "
                "arity-matched, helper exact_fn(0) called with 0) while the "
                "plain-value binding stays ignored (no bucket, no diagnostic) -- a "
                "verdict no name-level treatment could ever produce. seen 2, exit 0",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/sibling_scopes.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(1, matched=1),
    },
    {
        "id": "C9P2-34",
        "rung": 2,
        "desc": "parameter namesake (retained correction 3, its refusal kept by "
                "retained correction 8): a function parameter spelled like an "
                "UNRELATED function-local import alias. Parameters bind with NO "
                "var-decl node, so the retired var-decl-scoped sets never saw them and "
                "the former file-global sets falsely counted m.helper alias-too-deep. "
                "Correction 8 splits the same-spelled uses by EXACT OWNER: the import "
                "binding is followed (m.answer validated) while the parameter's "
                "access -- sidecar category function_parameter, a known lexical owner "
                "with unknown value provenance -- lands in NO bucket and NO "
                "diagnostic. Exercised parameter form exactly: `m: anytype` -- other "
                "parameter forms are unsupported by the same rule and UNPROVEN",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/param_namesake.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-35",
        "rung": 2,
        "desc": "capture-payload namesake (retained correction 3, its refusal kept by "
                "retained correction 8): a capture payload spelled like an UNRELATED "
                "function-local import alias. Captures bind with NO var-decl node, "
                "same as parameters, and were falsely counted alias-too-deep before "
                "correction 3. Correction 8 splits the same-spelled uses by EXACT "
                "OWNER: the import binding is followed (m.answer validated) while the "
                "capture's access -- sidecar category capture, a known lexical owner "
                "with unknown value provenance -- lands in NO bucket and NO "
                "diagnostic. Exercised capture form exactly: `if (<optional>) |m|` -- "
                "the other capture forms get their own correction-8 controls "
                "(C9P2-48/49) as ignored shapes; nothing generalizes beyond them",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/capture_namesake.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },

    # ---------------- retained arity dispatch: direct-call syntactic argument counts ----------------
    {
        "id": "C9P2-36",
        "rung": 2,
        "desc": "arity mismatch, BOTH directions (retained arity dispatch): "
                "util.helper(1) supplies too many (helper is exact_fn(0)) and "
                "util.extfn() too few (extfn is exact_fn(1)) -- both calls are STILL "
                "name-validated (validated 3, no 'referenced declaration not found'), "
                "proving the arity verdict is additive to the name verdict, and each "
                "produces its own argument-count diagnostic. The INLINE "
                "@import(\"util\").helper() contrast exact-matches in the same file, so "
                "shape (a) and shape (b) callees are pinned by one control",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/arity_mismatch.zig"],
        "exit": 1,
        "stderr_has": [
            "direct call argument-count mismatch: member 'helper' of",
            "declares 0 fixed syntactic parameter(s) (shape only -- no types, no "
            "comptime, no implicit receiver), but this call supplies 1 argument(s)",
            "direct call argument-count mismatch: member 'extfn' of",
            "declares 1 fixed syntactic parameter(s) (shape only -- no types, no "
            "comptime, no implicit receiver), but this call supplies 0 argument(s)",
            import_line(2, 0, 2),
            decl_line(3, validated=3),
            arity_line(3, matched=1, mismatch=2),
        ],
        "stderr_lacks": ["referenced declaration not found"],
    },
    {
        "id": "C9P2-37",
        "rung": 2,
        "desc": "arity skipped-dynamic, all three dynamic syntaxes (retained arity "
                "dispatch; extended by Sol correction 5): util.generic(u32, 1) hits a "
                "comptime-parameter declaration whose parameter count COINCIDENTALLY "
                "equals its argument count, util.varargs('fmt', 1, 2) hits an extern "
                "variadic whose count does not, and util.anyfn(1) hits an anytype "
                "parameter -- the distinct FnProto.Iterator.Param .anytype_ellipsis3 "
                "branch the first two never touch. All three are dynamic_fn, counted "
                "skipped, NEVER compared. A naive equality check would produce one "
                "false match and one false mismatch on the first two alone; the anytype "
                "call proves the third branch is exercised too. No arity error, no "
                "type or generic correctness claimed -- counted skips -- exit 0",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/arity_dynamic.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(3, validated=3) + "\n"
                     + arity_line(3, dynamic=3),
        "stderr_lacks": ["argument-count mismatch"],
    },
    {
        "id": "C9P2-38",
        "rung": 2,
        "desc": "arity skipped-non-fn (retained arity dispatch): util.fnval is a public "
                "const of function type -- syntactically a non-fn declaration that may "
                "be function-valued after Sema. Called directly, it is counted "
                "arity-skipped-non-fn: never called non-callable, never compared, no "
                "arity error, while the name verdict stays validated",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/arity_nonfn.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(1, validated=1) + "\n"
                     + arity_line(1, nonfn=1),
        "stderr_lacks": ["argument-count mismatch"],
    },
    {
        "id": "C9P2-39",
        "rung": 2,
        "desc": "arity unavailable on a missing member (retained arity dispatch): "
                "util.nope_missing(1) names a declaration that does not exist. The "
                "primary verdict is the missing error; the arity verdict is "
                "arity-unavailable -- no target shape exists to compare, so NO "
                "argument-count mismatch diagnostic is stacked on top. Half the control "
                "is the absence",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/arity_missing.zig"],
        "exit": 1,
        "stderr_has": [
            "referenced declaration not found: 'nope_missing' is not a public "
            "top-level declaration of",
            import_line(1, 0, 1),
            decl_line(1, missing=1),
            arity_line(1, unavailable=1),
        ],
        "stderr_lacks": ["argument-count mismatch"],
    },
    {
        "id": "C9P2-40",
        "rung": 2,
        "desc": "receiver-sugar and deeper-qualified negative control (retained arity "
                "dispatch; reshaped by Sol correction 5 -- the earlier shape "
                "util.Thing.method() was a type-namespace call falsely named a bound "
                "method; it never had a receiver). TWO discriminators: "
                "util.Thing.staticCall() is a deeper QUALIFIED call whose callee is the "
                "OUTER two-hop field access, and thing.method() is an ACTUAL "
                "receiver-sugar call on a local value whose type is spelled through "
                "util.Thing -- method takes an explicit self: Thing -- whose callee "
                "field access has a non-import identifier LHS. Neither callee is a "
                "supported member reference: neither enters the arity population, and "
                "no implicit receiver is inferred or compared, while the INNER "
                "util.Thing and the util.Thing type annotation are BOTH name-validated "
                "(validated 2). This is a syntactic population boundary control, NOT "
                "Sema validation of method calls or receivers, which stay the "
                "compiler's job",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/arity_bound_method.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },

    # ---------------- retained correction 6: binding-strict rung-2 target selection ----------------
    {
        "id": "C9P2-41",
        "rung": 2,
        "desc": "unbound baseline (retained correction 6): --check-decls on "
                "lib_a/strict_target_selection.zig with NO --as-module keeps the "
                "graph-wide conservative union -- the spelling 'shared' maps to TWO "
                "distinct targets (alpha's edge 'shared' -> index 4 / lib_d1/same.zig "
                "and dupe_a's edge 'shared' -> index 5 / lib_d2/same.zig), so BOTH "
                "member refs (onlyD1, onlyD2) are counted target-unresolvable: a "
                "counted refusal, never a guess, exit 0. Import line stays union-green; "
                "arity denominator zero (plain references, not calls)",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/strict_target_selection.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(2, unres=2) + "\n"
                     + arity_line(0),
        "stderr_lacks": ["referenced declaration not found", "argument-count mismatch"],
    },
    {
        "id": "C9P2-42",
        "rung": "2+4",
        "desc": "binding-strict target selection (retained correction 6): the SAME file "
                "plus --as-module=c9p2.alpha -- the strict import check stays green "
                "(alpha declares 'shared'), and rung 2 selects named member targets "
                "through exactly alpha's own dependency table, whose 'shared' edge is "
                "index 4 ONLY: onlyD1 (declared in lib_d1/same.zig) is VALIDATED while "
                "onlyD2 (declared only in lib_d2/same.zig, a module alpha does not "
                "reach under this name) is MISSING. One file gives positive and "
                "negative target-selection discrimination and proves the checker did "
                "not scan both target files for whichever spelling exists. Exit 1 from "
                "exactly the one missing-declaration diagnostic -- not a "
                "target-unresolvable refusal; the strict import line is green; arity "
                "denominator zero",
        "argv": ["ast-check", "--module-graph=graph.json", "--as-module=c9p2.alpha",
                 "--check-decls", "lib_a/strict_target_selection.zig"],
        "exit": 1,
        "stderr_has": [
            "referenced declaration not found: 'onlyD2' is not a public "
            "top-level declaration of",
            strict_line(1, 0, 1, 0, "c9p2.alpha", 1),
            decl_line(2, validated=1, missing=1),
            arity_line(0),
        ],
        "stderr_lacks": ["target-unresolvable 1", "'onlyD1' is not a public",
                         "argument-count mismatch", "does not declare import"],
    },

    # ---------------- retained correction 8: AstGen-owned lexical binding sidecar ----------------
    {
        "id": "C9P2-43",
        "rung": 2,
        "desc": "local direct-const import, valid + missing (retained correction 8): a "
                "FUNCTION-LOCAL const bound directly to @import(\"util\") is shape (b) "
                "now -- AstGen's own localVarRef sidecar names the exact declaration "
                "each use resolved to, and rung 2 inspects THAT declaration's "
                "initializer, never a file-wide spelling match. m.answer validates; "
                "m.hidden is declared in util.zig but NOT public, so it is MISSING and "
                "the exit is 1 -- the local alias is judged by the same public-decl "
                "owner the root alias always had",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/local_direct_import.zig"],
        "exit": 1,
        "stderr_has": [
            "referenced declaration not found: 'hidden' is not a public "
            "top-level declaration of",
            import_line(1, 0, 1),
            decl_line(2, validated=1, missing=1),
            arity_line(0),
        ],
        "stderr_lacks": ["'answer' is not a public"],
    },
    {
        "id": "C9P2-44",
        "rung": 2,
        "desc": "local direct-import call sites, one match and one mismatch (retained "
                "correction 8): m.helper() exact-matches (helper is exact_fn(0), "
                "called with 0) and m.extfn() mismatches (extfn is exact_fn(1), called "
                "with 0). BOTH member names stay validated -- the arity verdict is "
                "additive to the name verdict -- so the name denominator and the arity "
                "denominator remain separate populations on the newly supported local "
                "shape, and the mismatch produces exactly one argument-count diagnostic",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/local_arity.zig"],
        "exit": 1,
        "stderr_has": [
            "direct call argument-count mismatch: member 'extfn' of",
            "declares 1 fixed syntactic parameter(s) (shape only -- no types, no "
            "comptime, no implicit receiver), but this call supplies 0 argument(s)",
            import_line(1, 0, 1),
            decl_line(2, validated=2),
            arity_line(2, matched=1, mismatch=1),
        ],
        "stderr_lacks": ["referenced declaration not found"],
    },
    {
        "id": "C9P2-45",
        "rung": 2,
        "desc": "sibling same spelling, import binding versus anytype parameter "
                "(retained correction 8): two sibling functions reuse `m`; one binds it "
                "to a direct local import (m.helper() VALIDATED and arity-MATCHED, "
                "helper exact_fn(0) called with 0), one takes it as an `m: anytype` "
                "parameter with the same spelling and the same member name -- IGNORED, "
                "sidecar category function_parameter: a known lexical owner whose value "
                "provenance no syntactic walk can know. A spelling-level treatment "
                "cannot tell the two uses apart; the fact-keyed walk gives the "
                "byte-identical spellings different verdicts",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/sibling_import_param.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(1, matched=1),
    },
    {
        "id": "C9P2-46",
        "rung": 2,
        "desc": "two sibling local constants reuse `m` but import different modules "
                "(retained correction 8): one binds it to the named import 'util', the "
                "other to the FILE import 'nested_ok.zig' -- distinct targets "
                "exposing distinct public names (helper / nestedFn). Each access must "
                "follow its own declaration's target: both validate and both calls "
                "match. A file-global spelling entry -- one set slot for 'm', whichever "
                "declaration wrote it last -- would resolve one of the two through the "
                "wrong file and report a false missing; that retired behavior is what "
                "this control discriminates against",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/sibling_two_imports.zig"],
        "exit": 0,
        "stderr_eq": import_line(3, 1, 2) + "\n" + decl_line(3, validated=3) + "\n"
                     + arity_line(2, matched=2),
        "stderr_lacks": ["referenced declaration not found"],
    },
    {
        "id": "C9P2-47",
        "rung": 2,
        "desc": "ordinary, mutable, and chained local unknowns (retained correction 8): "
                "a local const of an ordinary value, a local var initialized from an "
                "import AND genuinely reassigned to a different module mid-function, "
                "and a local const chained to the root alias's NAME -- all three are "
                "known lexical owners (the sidecar says so) with unknown value "
                "provenance for the follow, so all three accesses stay unsupported: "
                "zero invented name results, zero invented arity results, no bucket, "
                "no diagnostic. Only the root simple alias contrast validates",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/local_unknowns.zig"],
        "exit": 0,
        "stderr_eq": import_line(3, 1, 2) + "\n" + decl_line(1, validated=1) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-48",
        "rung": 2,
        "desc": "if/while/for/pointer payload captures sharing an import-alias spelling "
                "elsewhere (retained correction 8): four capture forms bind `m` beside "
                "a sibling function-local direct import of the same spelling; every "
                "capture access is authoritatively classified (sidecar category "
                "capture) but value provenance stays unknown, so all four are ignored "
                "with zero attribution, while the sibling import binding and the root "
                "contrast validate. Retained correction 9 reshaped the while and "
                "pointer forms to be unambiguously AstGen-admissible -- the by-value "
                "while capture reads a CONST optional, the pointer capture reads a "
                "separate MUTABLE optional lvalue so the payload write is a real "
                "mutation -- with the denominators unchanged",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/capture_forms.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-49",
        "rung": 2,
        "desc": "switch payload/tag, catch/error, and errdefer captures (retained "
                "correction 8): the remaining Scope.IdCat capture producers -- a "
                "switch prong's payload and tag captures, a second prong's payload, a "
                "catch error capture, an if-error's success and error captures, and an "
                "errdefer capture -- all spelled `m`/`m2` beside a followed "
                "same-spelling import. Every one is ignored under the same "
                "zero-attribution rule, each through its own sidecar fact",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/capture_forms2.zig"],
        "exit": 0,
        "stderr_eq": import_line(2, 0, 2) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-50",
        "rung": 2,
        "desc": "nested namespace declaration and closure-tunneled root reference "
                "(retained correction 8): a function-local container's own member "
                "(`S.x`) is NOT promoted to root by spelling -- its exact declaration "
                "is a local const initialized by a struct declaration, not an import, "
                "so it is ignored -- while a ROOT declaration referenced from inside a "
                "generic namespace nested in a function (`util.answer` in "
                "Inner.method, the tunnelThroughClosure shape) remains exact: the fact "
                "is recorded before tunneling, so the reference validates and "
                "Inner.method() never enters the arity population",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/nested_and_tunnel.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1) + "\n" + decl_line(2, validated=2) + "\n"
                     + arity_line(0),
    },
    {
        "id": "C9P2-51",
        "rung": 2,
        "desc": "malformed/AnalysisFail source under --check-decls (retained "
                "correction 8): an undeclared identifier makes lowering fatal; the "
                "driver renders the normal AstGen diagnostic and exits 1, and NO "
                "graph summary appears at all -- the file holds a lawful @import site "
                "whose 'import sites seen' line would print if any rung ran, so its "
                "absence pins the gate. The sidecar is cleared before publication "
                "whenever a ZIR carries ANY diagnostic (retained correction 9 widened "
                "the trigger from fatal parse/AnalysisFail to every diagnostic "
                "lowering), so rung 2 never consumes partial facts. Under "
                "--check-decls this path is requested-then-cleared, not "
                "zero-allocation -- only the flagless and graph-only paths never "
                "request the sidecar",
        "argv": ["ast-check", "--module-graph=graph.json", "--check-decls",
                 "lib_a/astgen_fails.zig"],
        "exit": 1,
        "stderr_has": ["use of undeclared identifier 'no_such_root'"],
        "stderr_lacks": ["import sites seen", "member refs", "direct calls"],
    },
    {
        "id": "C9P2-52",
        "rung": "2+3",
        "desc": "flagless / graph-only / --check-decls path split (retained "
                "correction 8): graph-only ast-check over the very file C9P2-43 "
                "newly follows under --check-decls prints the byte-exact rung-1 "
                "summary and NO decl line -- rung 1 never consults binding facts, "
                "and the function-local @import site is an ordinary rung-1 site. With "
                "C9P2-24 (flagless: no output) and C9P2-25 (graph-only over "
                "checked_ok), this pins the split's observable half; the allocation "
                "half -- only the --check-decls invocation requests and threads the "
                "sidecar -- is a static claim of the correction's source, not an "
                "output observation",
        "argv": ["ast-check", "--module-graph=graph.json", "lib_a/local_direct_import.zig"],
        "exit": 0,
        "stderr_eq": import_line(1, 0, 1),
    },
    {
        "id": "C9P2-53",
        "rung": 2,
        "desc": "AstGen allocation-failure control (retained correction 13 "
                "retires the correction-8 debt row; UNEXECUTED, like every row): "
                "`zig test astgen_allocation_failures.zig --zig-lib-dir "
                "../../../lib --test-filter C9P2-53`, run from the fixture "
                "directory, must run the fixture's two named tests ('C9P2-53: "
                "generate survives every injected allocation failure' and "
                "'C9P2-53: generateWithIdentifierBindings survives every "
                "injected allocation failure'), exit 0, and print none of the "
                "three native red outcomes MemoryLeakDetected, "
                "SwallowedOutOfMemoryError, or NondeterministicMemoryUsage. "
                "Both tests wrap one AstGen entry point in "
                "std.testing.checkAllAllocationFailures -- the native "
                "exhaustive helper, never a fake allocator -- over one fixed "
                "clean source carrying a function-local direct const @import "
                "with a member use, parsed once by std.testing.allocator "
                "OUTSIDE the injected-allocator loop: the ordinary test "
                "covers `generate` and demands a nonempty ZIR instruction "
                "slice on the unlimited pass; the opt-in test covers "
                "`generateWithIdentifierBindings` and additionally demands the "
                "member-use node's exact binding fact (local/local_constant, "
                "naming the declaration's own token) beside its nonempty ZIR. "
                "--zig-lib-dir selects THIS checkout's authored stdlib "
                "(correction 8's sidecar plus correction 13's staged final "
                "transfer in AstGen.generateInner, which repairs the "
                "pre-existing toOwnedSlice moved-instruction-slice leak), but "
                "does not by itself prove which compiler binary was built from "
                "it -- rebuilt-compiler identity stays the supervising "
                "reviewer's canonical build-lock window. Required future "
                "evidence before any green is accepted: a pre-repair red "
                "receipt from this IDENTICAL control shape; source predicts "
                "the ordinary helper trips MemoryLeakDetected on the "
                "unrepaired body (instructions moved out before the "
                "string_bytes/extra tries), but NO pre-repair red was measured "
                "in this wave. Retired debt history (correction 8, doctrine "
                "7): the row was NAMED PROOF DEBT because no "
                "checkAllAllocationFailures harness reached generation in this "
                "tree's test surface and the moved-slice leak blocked an "
                "honest no-leak assertion; correction 13 repaired that owner "
                "and authored the control's fixture, closing both missing "
                "joins at source",
        "argv": ["test", "astgen_allocation_failures.zig",
                 "--zig-lib-dir", "../../../lib", "--test-filter", "C9P2-53"],
        "exit": 0,
        "stdout_lacks": ["MemoryLeakDetected", "SwallowedOutOfMemoryError",
                         "NondeterministicMemoryUsage"],
        "stderr_lacks": ["MemoryLeakDetected", "SwallowedOutOfMemoryError",
                         "NondeterministicMemoryUsage"],
    },
]


# ---------------------------------------------------------------------------
# Offline preflight. INTERNAL CONSISTENCY ONLY -- see the module docstring.
# ---------------------------------------------------------------------------


def _read(path):
    with open(os.path.join(FIXTURES, path)) as f:
        return f.read()


def preflight():
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    graph = json.loads(_read("graph.json"))
    graph_mf = json.loads(_read("graph_missing_fields.json"))
    mods = graph["modules"]

    # --- graph.json shape ---
    check(len(mods) == 9, "graph.json: expected 9 modules, found %d" % len(mods))
    by_index = {}
    for i, m in enumerate(mods):
        check(m["index"] == i,
              "graph.json: module at array position %d has index %r (positions and indices "
              "must agree for the index-fallback controls)" % (i, m["index"]))
        for field in ("fully_qualified_name", "root", "root_src_path", "deps"):
            check(field in m, "graph.json: module %d lacks '%s'" % (i, field))
        by_index[m["index"]] = m
    check([r["role"] for r in graph["roots"]] == ["std", "root"],
          "graph.json: roots roles must be ['std', 'root']")

    # --- dependency edges resolve, and the union is what the controls assume ---
    union = set()
    for m in mods:
        for d in m["deps"]:
            union.add(d["import_name"])
            if d["dep_index"] is not None:
                dm = by_index.get(d["dep_index"])
                check(dm is not None,
                      "graph.json: %s's dep '%s' points at index %r, which no module carries"
                      % (m["fully_qualified_name"], d["import_name"], d["dep_index"]))
                if dm is not None and d.get("dep_fully_qualified_name") is not None:
                    check(d["dep_fully_qualified_name"] == dm["fully_qualified_name"],
                          "graph.json: dep '%s' names %r but index %d is %r"
                          % (d["import_name"], d["dep_fully_qualified_name"],
                             d["dep_index"], dm["fully_qualified_name"]))
    check(union == {"util", "shared", "opaque_mod", "ghost_mod", "broken"},
          "graph.json: union import names are %r" % sorted(union))

    # --- the ambiguous name collapses, the unique names do not (mirrors
    #     checkDeclExistence's named_targets collapse, Python-side, for
    #     fixture consistency only) ---
    targets = {}
    for m in mods:
        for d in m["deps"]:
            t = None
            if d["dep_index"] is not None:
                dm = by_index.get(d["dep_index"])
                t = (dm["root"], dm["root_src_path"]) if dm else None
            prev = targets.setdefault(d["import_name"], t)
            if prev != t:
                targets[d["import_name"]] = None
    check(targets.get("util") == (".", "util.zig"), "'util' must resolve to ./util.zig uniquely")
    check(targets.get("opaque_mod") == ("lib_o", "opaque.zig"),
          "'opaque_mod' must resolve to lib_o/opaque.zig uniquely")
    check(targets.get("ghost_mod") == ("lib_g", "ghost_src.zig"),
          "'ghost_mod' must resolve to lib_g/ghost_src.zig uniquely")
    check(targets.get("shared") is None,
          "'shared' must be ambiguous by construction (two distinct targets)")
    shared_declarers = sorted(d["dep_index"] for m in mods for d in m["deps"]
                              if d["import_name"] == "shared")
    check(shared_declarers == [4, 5],
          "'shared' must be declared by exactly modules 4 and 5, found %r" % shared_declarers)
    # --- retained correction 6's discriminating pair: alpha's OWN edge and dupe_a's OWN
    #     edge under the SAME spelling -- the union conflict (C9P2-41) and the strict
    #     selection (C9P2-42) both hinge on exactly these two facts ---
    alpha_shared = [d["dep_index"] for m in mods if m["index"] == 1 for d in m["deps"]
                    if d["import_name"] == "shared"]
    check(alpha_shared == [4],
          "module 1 (c9p2.alpha) must declare 'shared' -> index 4 ONLY "
          "(C9P2-42's strict-selection premise)")
    dupe_a_shared = [d["dep_index"] for m in mods if m["index"] == 4 for d in m["deps"]
                     if d["import_name"] == "shared"]
    check(dupe_a_shared == [5],
          "module 4 (c9p2.dupe_a) must declare 'shared' -> index 5 ONLY "
          "(the other half of C9P2-41's union conflict)")
    check(any(d["import_name"] == "broken" and d["dep_index"] is None
              for m in mods for d in m["deps"]),
          "'broken' must carry dep_index null (stage 0's unresolved-dependency value)")

    # --- the twin pair ---
    twins = [m["index"] for m in mods if m["fully_qualified_name"] == "c9p2.twin"]
    check(twins == [6, 7],
          "the two 'c9p2.twin' modules must sit at indices 6 and 7, found %r" % twins)

    # --- graph_missing_fields.json: rung-1-loadable, rung-2/4-refusable ---
    mods_mf = graph_mf["modules"]
    check(len(mods_mf) == len(mods),
          "graph_missing_fields.json: expected %d modules, found %d" % (len(mods), len(mods_mf)))
    for i, (m, mm) in enumerate(zip(mods, mods_mf)):
        for field in ("index", "root", "root_src_path"):
            check(field not in mm,
                  "graph_missing_fields.json: module %d must lack '%s'" % (i, field))
        check(m["deps"] == mm["deps"],
              "graph_missing_fields.json: module %d deps must be identical to graph.json's "
              "(rung 1's union must be unchanged -- the BLOCKER 2 control depends on it)" % i)
    check(graph_mf["roots"] == graph["roots"],
          "graph_missing_fields.json: roots must be identical to graph.json's")

    # --- fixture files referenced by the controls exist (or are deliberately absent) ---
    referenced = set()
    for ctl in CONTROLS:
        for a in ctl["argv"]:
            if a.endswith((".zig", ".zon", ".json")):
                referenced.add(a)
    for path in sorted(referenced):
        if path == "missing_on_disk.zig":
            check(not os.path.exists(os.path.join(FIXTURES, path)),
                  "%s must NOT exist (the batch denominator's skip row)" % path)
        elif path in RENDERED_FILES:
            # Rendered by --run at execution time (an absolute operand varies by checkout).
            # Preflight verifies what CAN be verified statically: the template's placeholder
            # and the declarations its expected outcome claims, just below.
            continue
        else:
            check(os.path.exists(os.path.join(FIXTURES, path)),
                  "%s does not exist (a control references it)" % path)
    check(not os.path.exists(os.path.join(FIXTURES, "lib_g")),
          "lib_g/ must NOT exist (module 8's root_src_path is the unreadable-target control)")
    check(os.path.exists(os.path.normpath(os.path.join(FIXTURES, "lib_a", "..", "util.zig"))),
          "lib_a/../util.zig must exist (the sandbox-escape import is legal rung-1 code)")

    # --- module root directories exist on disk (module 8's root is the deliberate absence) ---
    for m in mods:
        if m["root"] == "lib_g":
            continue
        check(os.path.isdir(os.path.join(FIXTURES, m["root"])),
              "module %s's root directory '%s' does not exist"
              % (m["fully_qualified_name"], m["root"]))

    # --- asserted-present public declarations are really spelled in the targets ---
    def check_decl(path, needle, must_be_public):
        text = _read(path)
        check(needle in text, "%s must contain '%s'" % (path, needle))
        if must_be_public:
            check(("pub " + needle) in text, "%s: '%s' must be public" % (path, needle))

    for needle in ("fn helper", "const answer", "extern fn extfn"):
        check_decl("util.zig", needle, must_be_public=True)
    check("pub fn hidden" not in _read("util.zig") and "pub const hidden" not in _read("util.zig"),
          "util.zig: 'hidden' must NOT be public (the not-a-public-declaration control)")
    check("nope_missing" not in _read("util.zig") and "also_missing" not in _read("util.zig"),
          "util.zig: 'nope_missing'/'also_missing' must NOT exist "
          "(the missing-declaration controls)")

    # --- the run-time-rendered fixture (C9P2-32): its absolute operand can only be spelled
    #     at run time, so preflight checks the template's statics ---
    check("{abs_util}" in ABS_OPERAND_TEMPLATE,
          "ABS_OPERAND_TEMPLATE must carry the {abs_util} placeholder c9_p2_controls "
          "substitutes with this checkout's absolute util.zig path")
    check(ABS_OPERAND_TEMPLATE.count("@import") == 2,
          "ABS_OPERAND_TEMPLATE must hold exactly two @import sites "
          "(C9P2-32 expects 'import sites seen 2')")

    # --- the sibling-scope collision fixture (C9P2-33): one spelling, two bindings ---
    sibling = _read("lib_a/sibling_scopes.zig")
    check(sibling.count("const m = @import") == 1 and "const m = Point" in sibling,
          "sibling_scopes.zig must hold exactly the two collided bindings of 'm' "
          "(one @import, one plain value -- C9P2-33's premise)")
    check("const util = @import" in sibling and "util.answer" in sibling,
          "sibling_scopes.zig must keep one root simple alias with no local namesake "
          "(C9P2-33's validated contrast)")

    # --- the parameter-namesake fixture (C9P2-34) ---
    param = _read("lib_a/param_namesake.zig")
    check(param.count("const m = @import") == 1,
          "param_namesake.zig must hold exactly one function-local 'const m = @import' "
          "(the unrelated import alias -- C9P2-34's premise)")
    check("m: anytype" in param and "m.helper" in param,
          "param_namesake.zig must use the parameter spelled like the local alias, in the "
          "exercised form `m: anytype` (C9P2-34's ignored access)")
    check("const util = @import" in param and "util.answer" in param,
          "param_namesake.zig must keep one root simple alias contrast "
          "(C9P2-34's validated access)")

    # --- the capture-namesake fixture (C9P2-35): the ONE exercised capture form ---
    capture = _read("lib_a/capture_namesake.zig")
    check(capture.count("const m = @import") == 1,
          "capture_namesake.zig must hold exactly one function-local 'const m = @import' "
          "(the unrelated import alias -- C9P2-35's premise)")
    check("if (maybePoint()) |m|" in capture and "m.helper" in capture,
          "capture_namesake.zig must use the capture payload spelled like the local "
          "alias, in the exercised form `if (<optional>) |m|` ONLY (C9P2-35's ignored "
          "access; the other capture forms are outside C9P2-35 SPECIFICALLY and are "
          "now source-authored as the separate C9P2-48/49 predicted controls -- all "
          "unexecuted)")
    check("const util = @import" in capture and "util.answer" in capture,
          "capture_namesake.zig must keep one root simple alias contrast "
          "(C9P2-35's validated access)")

    # --- retained correction 8's own fixtures (the AstGen-sidecar shapes) ---
    ldi = _read("lib_a/local_direct_import.zig")
    check("const m = @import(\"util\")" in ldi and "_ = m.answer;" in ldi
          and "_ = m.hidden;" in ldi,
          "local_direct_import.zig must hold one function-local const import with one "
          "valid member and one NOT-public member (C9P2-43's validated+missing premise)")

    lar = _read("lib_a/local_arity.zig")
    check("const m = @import(\"util\")" in lar and "m.helper()" in lar
          and "m.extfn()" in lar,
          "local_arity.zig must hold the two direct calls through one function-local "
          "const import -- helper (exact_fn(0) called 0) and extfn (exact_fn(1) called "
          "0) -- C9P2-44's match+mismatch premise")

    sip = _read("lib_a/sibling_import_param.zig")
    check(sip.count("const m = @import") == 1 and "m.helper()" in sip,
          "sibling_import_param.zig must hold one function-local const import with a "
          "direct call (C9P2-45's followed sibling)")
    check("m: anytype" in sip and "m.helper;" in sip,
          "sibling_import_param.zig must hold the anytype parameter spelled like the "
          "local alias, reading a member (C9P2-45's ignored sibling)")
    check("const util = @import" in sip and "util.answer" in sip,
          "sibling_import_param.zig must keep one root simple alias contrast "
          "(C9P2-45's validated access)")

    sti = _read("lib_a/sibling_two_imports.zig")
    check('const m = @import("util")' in sti and 'const m = @import("nested_ok.zig")' in sti,
          "sibling_two_imports.zig must hold TWO sibling locals spelled 'm' bound to "
          "DIFFERENT targets (util and nested_ok.zig) -- C9P2-46's premise")
    check("m.helper()" in sti and "m.nestedFn()" in sti,
          "sibling_two_imports.zig must access each target's own member through its "
          "own binding (C9P2-46's two discriminating accesses)")
    nested_ok = _read("lib_a/nested_ok.zig")
    check("pub fn nestedFn" in nested_ok and "fn helper" not in nested_ok,
          "nested_ok.zig must declare public 'nestedFn' and NOT 'helper' -- a "
          "file-global spelling entry for 'm' would resolve one access through the "
          "wrong file and report a false missing (C9P2-46's discrimination)")

    luk = _read("lib_a/local_unknowns.zig")
    check("const m = Point;" in luk and "m.helper();" in luk,
          "local_unknowns.zig must hold the ordinary local const of a plain value "
          "(C9P2-47's first ignored shape)")
    check("var m = @import(\"util\")" in luk and 'm = @import("nested_ok.zig")' in luk,
          "local_unknowns.zig must hold the genuinely REASSIGNED local var import "
          "(the reassignment is what makes AstGen accept the var and what makes the "
          "value unknowable -- C9P2-47's second ignored shape)")
    check("const m = util;" in luk and "m.answer;" in luk,
          "local_unknowns.zig must hold the local const chained to the root alias "
          "NAME (C9P2-47's third ignored shape)")

    cf1 = _read("lib_a/capture_forms.zig")
    check(cf1.count("const m = @import") == 1 and "_ = m.answer;" in cf1,
          "capture_forms.zig must hold one function-local const import with a member "
          "access (C9P2-48's followed sibling)")
    check("const opt = maybePoint();" in cf1 and "while (opt) |m|" in cf1,
          "capture_forms.zig must hold the while by-value capture reading a CONST "
          "optional (retained correction 9's unambiguously AstGen-admissible shape -- "
          "never a never-mutated var) -- C9P2-48's while form")
    check("var opt = maybePoint();" in cf1 and "if (opt) |*m|" in cf1
          and "m.helper = 2;" in cf1,
          "capture_forms.zig must hold the pointer payload capture from a separate "
          "MUTABLE optional lvalue with a real payload write (retained correction 9: "
          "never a pointer capture from a call-result temporary) -- C9P2-48's pointer "
          "form")
    for form in ("if (maybePoint()) |m|", "for (list) |m|"):
        check(form in cf1, "capture_forms.zig must hold the capture form %r "
              "(C9P2-48's exercised forms)" % form)

    cf2 = _read("lib_a/capture_forms2.zig")
    check(cf2.count("const m = @import") == 1 and "_ = m.answer;" in cf2,
          "capture_forms2.zig must hold one function-local const import with a member "
          "access (C9P2-49's followed sibling)")
    for form in ("|m, t|", "|m2|", "catch |m|", "else |m|", "errdefer |m|"):
        check(form in cf2, "capture_forms2.zig must hold the capture form %r "
              "(C9P2-49's exercised forms)" % form)

    nat = _read("lib_a/nested_and_tunnel.zig")
    check("const S = struct" in nat and "S.x;" in nat,
          "nested_and_tunnel.zig must hold the function-local container declaration "
          "with its own member access (C9P2-50's ignored nested namespace)")
    check("util.answer;" in nat and "Inner.method();" in nat,
          "nested_and_tunnel.zig must hold the root reference from inside the "
          "function-nested namespace and the call on that namespace's local "
          "(C9P2-50's tunneled-valid premise and never-enters-arity call)")

    fail = _read("lib_a/astgen_fails.zig")
    check("no_such_root.member" in fail,
          "astgen_fails.zig must hold the undeclared-identifier use that makes "
          "lowering fatal (C9P2-51's premise)")
    check("const util = @import(\"util\");" in fail and "util.answer;" in fail,
          "astgen_fails.zig must hold a lawful import site and access whose "
          "'import sites seen' line WOULD print if any rung ran -- its absence is "
          "C9P2-51's gate pin")

    # --- the arity pass's target shapes (retained arity dispatch): every declaration the
    #     arity controls call into must be spelled in util.zig with the shape the control
    #     claims, and each is deliberately unsuitable for naive equality ---
    util_src = _read("util.zig")
    check("pub fn helper() void" in util_src and "pub extern fn extfn(x: u32) u32" in util_src,
          "util.zig must keep the two exact_fn shapes: helper (0 fixed parameters) and "
          "extfn (1 fixed parameter) -- C9P2-36's mismatch premise")
    check("comptime T: type" in util_src,
          "util.zig must declare `generic` with a comptime parameter "
          "(C9P2-37's skipped-dynamic premise)")
    check("pub extern fn varargs(fmt: [*:0]const u8, ...) void" in util_src,
          "util.zig must declare `varargs` with an extern `...` marker "
          "(C9P2-37's skipped-dynamic premise)")
    check("pub fn anyfn(value: anytype) void" in util_src,
          "util.zig must declare `anyfn` with an `anytype` parameter -- the distinct "
          "FnProto.Iterator.Param .anytype_ellipsis3 branch "
          "(C9P2-37's skipped-dynamic premise, added by Sol correction 5)")
    check("pub const fnval: fn (u32) u32" in util_src,
          "util.zig must declare `fnval`, a public const of function type "
          "(C9P2-38's skipped-non-fn premise)")
    check("pub const Thing = struct" in util_src and "pub fn staticCall() void" in util_src,
          "util.zig must declare public `Thing` with receiverless `staticCall` "
          "(C9P2-40's deeper-qualified premise)")
    check("pub fn method(self: Thing) void" in util_src,
          "util.zig must declare `Thing.method` taking an explicit `self: Thing` "
          "receiver (C9P2-40's receiver-sugar premise, added by Sol correction 5)")

    # --- the arity fixtures' call premises (retained arity dispatch) ---
    arity_mm = _read("lib_a/arity_mismatch.zig")
    check("util.helper(1)" in arity_mm and "util.extfn()" in arity_mm,
          "arity_mismatch.zig must hold the too-many and too-few calls "
          "(C9P2-36's premise)")
    check('@import("util").helper()' in arity_mm,
          "arity_mismatch.zig must hold the inline exact-match contrast "
          "(C9P2-36's shape-(a) premise)")
    arity_dyn = _read("lib_a/arity_dynamic.zig")
    check("util.generic(u32, 1)" in arity_dyn and 'util.varargs("fmt", 1, 2)' in arity_dyn,
          "arity_dynamic.zig must hold the comptime-generic and variadic calls, in the "
          "counts that make naive equality wrong both ways (C9P2-37's premise)")
    check("util.anyfn(1)" in arity_dyn,
          "arity_dynamic.zig must hold the anytype direct call, so all three dynamic "
          "syntaxes are exercised (C9P2-37's premise, added by Sol correction 5)")
    check("util.fnval(1)" in _read("lib_a/arity_nonfn.zig"),
          "arity_nonfn.zig must call the function-valued const directly "
          "(C9P2-38's premise)")
    check("util.nope_missing(1)" in _read("lib_a/arity_missing.zig"),
          "arity_missing.zig must hold the missing-member direct call "
          "(C9P2-39's premise)")
    arity_bm = _read("lib_a/arity_bound_method.zig")
    check("util.Thing.staticCall()" in arity_bm,
          "arity_bound_method.zig must hold the deeper-qualified type-namespace call "
          "(C9P2-40's premise)")
    check("const thing: util.Thing = undefined" in arity_bm and "thing.method()" in arity_bm,
          "arity_bound_method.zig must construct a local value whose type is spelled "
          "through util.Thing and call the receiver-sugar method on it "
          "(C9P2-40's premise, added by Sol correction 5)")

    # --- the manifest itself: the arity controls are part of the estate's contract ---
    check(len(CONTROLS) == 53,
          "the control manifest must hold exactly 53 controls (found %d)" % len(CONTROLS))
    # --- retained correction 13: C9P2-53 is now the executable allocation-failure
    #     control; the correction-8 debt row is retired, but the control stays
    #     UNEXECUTED like every other row ---
    c53 = [c for c in CONTROLS if c["id"] == "C9P2-53"]
    check(len(c53) == 1, "exactly one C9P2-53 row (found %d)" % len(c53))
    c53 = c53[0]
    check(not [c for c in CONTROLS if "debt" in c],
          "no control may carry a debt row: correction 13 closed C9P2-53's two "
          "missing joins at source, so the manifest holds 53 executable rows; "
          "name any NEW proof gap in prose instead, never as a silent row")
    check(c53.get("argv") == ["test", "astgen_allocation_failures.zig",
                              "--zig-lib-dir", "../../../lib",
                              "--test-filter", "C9P2-53"],
          "C9P2-53 must carry correction 13's command verbatim: zig test "
          "astgen_allocation_failures.zig --zig-lib-dir ../../../lib "
          "--test-filter C9P2-53, run from the fixture directory")
    check(c53.get("exit") == 0,
          "C9P2-53 must demand exit 0 (both named tests surviving every "
          "injected allocation index)")
    for red_error in ("MemoryLeakDetected", "SwallowedOutOfMemoryError",
                      "NondeterministicMemoryUsage"):
        check("stdout_lacks" in c53 and red_error in c53["stdout_lacks"] and
              "stderr_lacks" in c53 and red_error in c53["stderr_lacks"],
              "C9P2-53 must demand absence of the native red error %r on both "
              "streams" % red_error)
    for needle in ("two named tests", "pre-repair red receipt",
                   "--zig-lib-dir", "NO pre-repair red was measured",
                   "MemoryLeakDetected", "checkAllAllocationFailures"):
        check(needle in c53["desc"],
              "C9P2-53's description must name %r (the correction's claim)" % needle)
    c53_src = _read("astgen_allocation_failures.zig")
    check(c53_src.count('test "C9P2-53') == 2,
          "the C9P2-53 fixture must hold exactly two tests named C9P2-53 "
          "(the --test-filter selects both)")
    for needle in ("std.testing.checkAllAllocationFailures",
                   "AstGen.generate(",
                   "AstGen.generateWithIdentifierBindings(",
                   "std.testing.allocator",
                   "Ast.parse(gpa, fixed_source, .zig)",
                   "IdentifierBindingCategory.local_constant",
                   "MemoryLeakDetected",
                   "pre-repair red receipt",
                   "tree.fullVarDecl(node)",
                   "vd.ast.mut_token + 1",
                   "keyword_const"):
        check(needle in c53_src,
              "the C9P2-53 fixture must name %r (the control's proof shape)" % needle)
    # --- retained correction 14: the declaration-name join must stay the
    #     authoritative one. Var-decl names are TOKENS at vd.ast.mut_token + 1
    #     (fullVarDecl), never identifier nodes; a locator that guesses the
    #     declaration by punctuation is the exact false-green correction 14
    #     repaired (the opt-in test would return DeclNotFound before the
    #     native allocator loop ever exercised the sidecar entry). ---
    check(".equal" not in c53_src,
          "the C9P2-53 fixture must not regress to the rejected identifier/"
          ".equal declaration-token guess: var-declaration names are tokens "
          "at vd.ast.mut_token + 1 (fullVarDecl), so the guess never matches "
          "and the opt-in test would die on DeclNotFound before exercising "
          "the sidecar entry")
    for path in ("lib_d1/same.zig", "lib_d2/same.zig"):
        check_decl(path, "fn sameFn", must_be_public=True)
    # --- retained correction 6's per-target discriminators: each ambiguous target owns
    #     one spelling the other does NOT declare ---
    check_decl("lib_d1/same.zig", "fn onlyD1", must_be_public=True)
    check_decl("lib_d2/same.zig", "fn onlyD2", must_be_public=True)
    sts = _read("lib_a/strict_target_selection.zig")
    check('const shared = @import("shared");' in sts,
          "strict_target_selection.zig must bind the root alias 'shared' DIRECTLY to "
          "the named import -- shape (b), C9P2-41/42's premise")
    check("shared.onlyD1" in sts and "shared.onlyD2" in sts,
          "strict_target_selection.zig must reference both onlyD1 and onlyD2 through "
          "that alias -- the positive and negative selection discriminators")
    for path in ("lib_t1/twin.zig", "lib_t2/twin.zig"):
        check_decl(path, "fn twinFn", must_be_public=True)
    check("comptime" in _read("lib_o/opaque.zig"),
          "lib_o/opaque.zig must contain a top-level comptime block (the opacity control)")

    # --- the fixture graph facts must equal the counts the expected strings claim ---
    for ctl in CONTROLS:
        texts = list(ctl.get("stderr_has", [])) + list(ctl.get("stderr_eq", "").split("\n")) \
            + list(ctl.get("stdout_has", []))
        for t in texts:
            for m in re.finditer(r"(\d+) module\(s\) available", t):
                check(int(m.group(1)) == len(mods),
                      "%s: expected text claims %s module(s), graph has %d"
                      % (ctl["id"], m.group(1), len(mods)))
            for m in re.finditer(r"indices: ([0-9, ]+)", t):
                claimed = [int(x) for x in m.group(1).split(",")]
                check(claimed == twins,
                      "%s: expected text claims twin indices %r, graph has %r"
                      % (ctl["id"], claimed, twins))

    return fails


# ---------------------------------------------------------------------------
# Execution (the reviewer's act, not the author's).
# ---------------------------------------------------------------------------


def run_control(zig, ctl):
    # Controls carrying a "render" list name fixture files that must be materialized first
    # (an absolute operand varies by checkout; see ABS_OPERAND_TEMPLATE). Writing them is
    # part of the reviewer's --run act, never something the offline manifest mode does.
    for path, template in ctl.get("render", []):
        rendered = template.replace(
            "{abs_util}", os.path.abspath(os.path.join(FIXTURES, "util.zig"))
        )
        with open(os.path.join(FIXTURES, path), "w") as f:
            f.write(rendered)
    argv = [zig] + ctl["argv"]
    try:
        p = subprocess.run(argv, cwd=FIXTURES, capture_output=True, text=True, timeout=300)
    except OSError as e:
        return ["could not run %r: %s" % (argv, e)]
    fails = []
    if p.returncode != ctl["exit"]:
        fails.append("exit %d, want %d" % (p.returncode, ctl["exit"]))
    for key, stream in (("stdout_has", p.stdout), ("stderr_has", p.stderr)):
        for sub in ctl.get(key, []):
            if sub not in stream:
                fails.append("%s lacks %r" % (key, sub))
    for key, stream in (("stdout_lacks", p.stdout), ("stderr_lacks", p.stderr)):
        for sub in ctl.get(key, []):
            if sub in stream:
                fails.append("%s unexpectedly contains %r" % (key, sub))
    for key, stream in (("stdout_eq", p.stdout), ("stderr_eq", p.stderr)):
        if key in ctl and stream.strip() != ctl[key]:
            fails.append("%s is %r, want exactly %r" % (key, stream, ctl[key]))
    if "json" in ctl:
        try:
            doc = json.loads(p.stdout)
        except ValueError as e:
            fails.append("stdout is not one JSON document: %s" % e)
        else:
            fails.extend(ctl["json"](doc))
    return fails


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--run", metavar="ZIG",
                    help="execute every control with this zig binary (cwd is forced to the "
                         "fixture directory). The author has NOT done this; see the header.")
    ap.add_argument("--only", metavar="IDS",
                    help="comma-separated control ids to run/list (default: all)")
    args = ap.parse_args()

    controls = CONTROLS
    if args.only:
        wanted = {x.strip() for x in args.only.split(",")}
        controls = [c for c in CONTROLS if c["id"] in wanted]
        missing = wanted - {c["id"] for c in controls}
        if missing:
            print("unknown control id(s): %s" % ", ".join(sorted(missing)))
            return 2

    pf = preflight()
    for f in pf:
        print("PREFLIGHT FAIL: %s" % f)
    print("preflight: %d failure(s) -- preflight is internal consistency only, NOT proof"
          % len(pf))

    if args.run:
        bad = 0
        debt = 0
        executed = 0
        for ctl in controls:
            if "debt" in ctl:
                # A debt row is NAMED proof debt by design: --run must not execute it
                # and must not silently convert it into a pass or a fail -- either
                # would misreport it as resolved.
                debt += 1
                print("DEBT %s (%s): %s" % (ctl["id"], ctl["rung"], ctl["debt"]))
                continue
            executed += 1
            fails = run_control(args.run, ctl)
            if fails:
                bad += 1
                print("FAIL %s (%s)" % (ctl["id"], ctl["rung"]))
                for f in fails:
                    print("     %s" % f)
            else:
                print("PASS %s (%s)" % (ctl["id"], ctl["rung"]))
        print("controls: %d/%d passed, %d named proof debt (UNEXECUTED by design, "
              "not passed and not failed)" % (executed - bad, executed, debt))
        return 1 if (bad or pf) else 0

    print("\nmanifest: %d controls, ALL UNEXECUTED -- no exit code or output fragment "
          "below has been observed" % len(controls))
    for ctl in controls:
        print("  %s (rung %s): %s" % (ctl["id"], ctl["rung"], ctl["desc"]))
        if "debt" in ctl:
            print("      named proof debt -- no command exists for this control: %s"
                  % ctl["debt"])
            continue
        print("      future command: zig %s" % " ".join(ctl["argv"]))
        if "render" in ctl:
            print("      rendered first by --run: %s (an absolute path varies by checkout; "
                  "the default manifest mode writes nothing)" % ctl["render"][0][0])
        print("      expected exit: %d" % ctl["exit"])
    return 1 if pf else 0


if __name__ == "__main__":
    sys.exit(main())