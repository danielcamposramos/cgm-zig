#!/usr/bin/env python3
"""Compare the debug-identity fold's INPUT SET against the artifact's EMITTED file set.

The compiler's `debugContentIdentity` (`src/codegen/llvm.zig`) folds one digest per
entry of `Object.debug_file_map` into the compile unit's `DW_AT_GNU_dwo_id`. This
tool answers one question and refuses to answer any other:

    Is there a file that shaped the emitted debug information but was NOT folded?

It computes BOTH set differences and reports both in full:

    ARTIFACT-ONLY  = a real omission.  The identity is blind to content it claims
                     to identify.  This is the defect direction and it is FATAL.
    MAP-ONLY       = expected, and must be EXPLAINED member by member, never
                     netted away.  `Builder.debugFile` performs no dedup, so two
                     `Zcu.File.Index` values resolving to one path give two
                     admissions; and a file may be admitted yet emit no DIE.
                     Over-hashing is conservative: it can only MISS reuse, never
                     license an unsound one.

Refusals, by name, never a quiet misparse (doctrine principle 2):
  * zero or multiple compile units matching the requested `DW_AT_name`
  * a unit name containing a single quote (the trace's `unit='...'` field would
    misparse; the trace author recorded this rather than engineering around it)
  * a quoted dwarfdump value that is not cleanly terminated on its own line
  * a relative path with no `DW_AT_comp_dir` to resolve it against
  * a `kind=file` trace row whose `idx` has no `kind=abspath` partner
  * more than one complete fold for the selected unit
  * a `kind=refused` row for the selected unit (the compiler failed closed; there
    is no identity to check completeness of)

A `kind=abspath` row is a CORRELATION, not proof of admission: it is emitted
before metadata creation finishes. Only `kind=file` rows terminated by a
`kind=final` row for the same unit count as admitted input. `abspath` is used
here solely as the index->absolute-path join table, which is what it is for.

Usage:
    dwoid_completeness.py --binary <artifact> --trace <stderr log> --unit root
        [--dwarfdump llvm-dwarfdump-21] [--json <path>]

Exit codes: 0 = artifact-only empty (pass) · 1 = artifact-only non-empty
(omission found) · 2 = a named refusal.
"""

import argparse
import json
import os
import re
import subprocess
import sys

class Refusal(Exception):
    """A named refusal. Never raised for a condition the tool could guess through."""

# --- dwarfdump value parsing -------------------------------------------------

_QUOTED = re.compile(r'^\("(.*)"\)$')

def parse_quoted(raw, what, lineno):
    """Parse a dwarfdump `("...")` value. Refuses anything it cannot read exactly."""
    raw = raw.strip()
    m = _QUOTED.match(raw)
    if not m:
        raise Refusal(
            f'unsupported {what} rendering at dump line {lineno}: {raw!r} is not a '
            f'cleanly quoted ("...") value on one line. A path holding a newline or '
            f'an embedded quote would land here; this tool refuses rather than '
            f'misparsing it.')
    val = m.group(1)
    if '"' in val or '\n' in val:
        raise Refusal(
            f'unsupported {what} at dump line {lineno}: {val!r} contains a quote or '
            f'newline. Refusing; a comparator must never misparse quietly.')
    return val

# --- .debug_info -------------------------------------------------------------

CU_HEADER = re.compile(r'^0x[0-9a-f]+:\s+Compile Unit:')
ATTR = re.compile(r'^\s+(DW_AT_\w+)\s+(.*)$')

def parse_debug_info(text):
    """Split the dump into compile units, each with its attributes and decl_files."""
    units, cur = [], None
    for lineno, line in enumerate(text.splitlines(), 1):
        if CU_HEADER.match(line):
            cur = {'name': None, 'comp_dir': None, 'stmt_list': None,
                   'decl_files': set(), 'header_line': lineno, 'seen_root_die': False}
            units.append(cur)
            continue
        if cur is None:
            continue
        m = ATTR.match(line)
        if not m:
            if line.startswith('0x') and 'DW_TAG_compile_unit' in line:
                cur['seen_root_die'] = True
            continue
        attr, raw = m.group(1), m.group(2)
        if attr == 'DW_AT_decl_file':
            cur['decl_files'].add(parse_quoted(raw, 'DW_AT_decl_file', lineno))
        elif cur['name'] is None and attr == 'DW_AT_name':
            # The FIRST DW_AT_name in a unit belongs to its root DW_TAG_compile_unit DIE.
            cur['name'] = parse_quoted(raw, 'DW_AT_name', lineno)
        elif cur['comp_dir'] is None and attr == 'DW_AT_comp_dir':
            cur['comp_dir'] = parse_quoted(raw, 'DW_AT_comp_dir', lineno)
        elif cur['stmt_list'] is None and attr == 'DW_AT_stmt_list':
            sm = re.match(r'^\((0x[0-9a-f]+)\)$', raw.strip())
            if not sm:
                raise Refusal(f'unsupported DW_AT_stmt_list rendering at dump line '
                              f'{lineno}: {raw!r}')
            cur['stmt_list'] = int(sm.group(1), 16)
    return units

def select_unit(units, want):
    """Select the PROGRAM compile unit by name. Refuses zero or multiple matches."""
    hits = [u for u in units if u['name'] == want]
    if len(hits) == 0:
        raise Refusal(
            f'no compile unit has DW_AT_name {want!r}. Present: '
            f'{sorted(u["name"] for u in units)!r}. Refusing to guess a unit; '
            f'selecting compiler_rt instead of the program is exactly the error '
            f'that voided an earlier "stable 3/3" result.')
    if len(hits) > 1:
        raise Refusal(
            f'{len(hits)} compile units have DW_AT_name {want!r} (at dump lines '
            f'{[u["header_line"] for u in hits]}). Refusing: this tool cannot know '
            f'which one the trace folded.')
    u = hits[0]
    if u['stmt_list'] is None:
        raise Refusal(f'compile unit {want!r} has no DW_AT_stmt_list, so its '
                      f'line-table file set cannot be read. Refusing.')
    return u

# --- .debug_line -------------------------------------------------------------

TABLE = re.compile(r'^debug_line\[(0x[0-9a-f]+)\]')
INCDIR = re.compile(r'^include_directories\[\s*(\d+)\]\s*=\s*(.*)$')
FILEENT = re.compile(r'^file_names\[\s*(\d+)\]:')
NAMEF = re.compile(r'^\s+name:\s*(.*)$')
DIRF = re.compile(r'^\s+dir_index:\s*(\d+)\s*$')

def parse_debug_line(text, want_offset):
    """Return (include_directories, file_names) for the table at `want_offset`."""
    in_table, dirs, files, cur_idx, cur_name = False, {}, [], None, None
    for lineno, line in enumerate(text.splitlines(), 1):
        m = TABLE.match(line)
        if m:
            if in_table:
                break
            in_table = int(m.group(1), 16) == want_offset
            continue
        if not in_table:
            continue
        m = INCDIR.match(line)
        if m:
            dirs[int(m.group(1))] = parse_quoted(f'({m.group(2).strip()})'
                                                 if not m.group(2).strip().startswith('(')
                                                 else m.group(2), 'include_directory', lineno)
            continue
        m = FILEENT.match(line)
        if m:
            if cur_name is not None:
                files.append((cur_idx, cur_name))
            cur_idx, cur_name = int(m.group(1)), None
            continue
        if cur_idx is not None:
            m = NAMEF.match(line)
            if m:
                cur_name = (parse_quoted(f'({m.group(1).strip()})', 'file name', lineno), None)
                continue
            m = DIRF.match(line)
            if m and cur_name is not None:
                cur_name = (cur_name[0], int(m.group(1)))
    if cur_name is not None:
        files.append((cur_idx, cur_name))
    if in_table is False and not files:
        raise Refusal(f'no line table at offset {want_offset:#x}; the unit\'s '
                      f'DW_AT_stmt_list points at nothing this dump contains.')
    return dirs, files

def render_line_files(dirs, files, comp_dir, unit_name):
    """Render each line-table file entry to an absolute, normalized path."""
    out = set()
    for _idx, (name, dir_index) in files:
        if dir_index is None:
            raise Refusal(f'line-table entry {name!r} in unit {unit_name!r} has no '
                          f'dir_index. Refusing to assume one.')
        if os.path.isabs(name):
            out.add(os.path.normpath(name))
            continue
        base = dirs.get(dir_index) if dir_index != 0 else comp_dir
        if base is None:
            raise Refusal(f'line-table entry {name!r} needs include_directories'
                          f'[{dir_index}] and this dump has no such entry. Refusing.')
        if not os.path.isabs(base):
            if comp_dir is None:
                raise Refusal(f'relative include directory {base!r} and unit '
                              f'{unit_name!r} has no DW_AT_comp_dir to resolve it '
                              f'against. Refusing.')
            base = os.path.join(comp_dir, base)
        out.add(os.path.normpath(os.path.join(base, name)))
    return out

# --- the compiler trace ------------------------------------------------------

TRACE = re.compile(r"cgm-dwoid unit='(?P<unit>[^']*)' kind=(?P<kind>\w+)(?P<rest>.*)$")

def parse_trace(text, want_unit):
    """Extract this unit's folds. `path=` is the one free-text field and is last."""
    if "'" in want_unit:
        raise Refusal(f'requested unit name {want_unit!r} contains a single quote; '
                      f"the trace's unit='...' field cannot represent it unambiguously. "
                      f'Refusing rather than misparsing.')
    folds, cur, abspath, refusals, other_units = [], [], {}, [], set()
    for line in text.splitlines():
        m = TRACE.search(line)
        if not m:
            continue
        unit, kind, rest = m.group('unit'), m.group('kind'), m.group('rest')
        if unit != want_unit:
            other_units.add(unit)
            continue
        fields, path = {}, None
        if ' path=' in rest:
            head, path = rest.split(' path=', 1)
        else:
            head = rest
        for tok in head.split():
            if '=' in tok:
                k, v = tok.split('=', 1)
                fields[k] = v
        if kind == 'file':
            cur.append({'idx': int(fields['idx']), 'digest': fields['digest'],
                        'sub_path': path})
        elif kind == 'final':
            folds.append({'rows': cur, 'identity': fields['identity'],
                          'folded': int(fields['folded'])})
            cur = []
        elif kind == 'abspath':
            abspath[int(fields['idx'])] = path
        elif kind == 'refused':
            refusals.append(fields.get('why', '?'))
    if refusals:
        raise Refusal(
            f'unit {want_unit!r} emitted kind=refused ({", ".join(refusals)}) and no '
            f'final identity. The compiler failed CLOSED, which is correct; there is '
            f'no identity whose completeness could be checked. Refusing.')
    if not folds:
        raise Refusal(f'no complete fold for unit {want_unit!r}: found '
                      f'{len(cur)} kind=file rows with no terminating kind=final. '
                      f'Other units seen: {sorted(other_units)!r}.')
    if len(folds) > 1:
        raise Refusal(f'{len(folds)} complete folds for unit {want_unit!r}. Refusing: '
                      f'this tool cannot know which one produced the artifact.')
    fold = folds[0]
    if fold['folded'] != len(fold['rows']):
        raise Refusal(f"kind=final says folded={fold['folded']} but "
                      f"{len(fold['rows'])} kind=file rows were seen for unit "
                      f'{want_unit!r}. The trace is not self-consistent; refusing.')
    return fold, abspath

def join_map_paths(fold, abspath, unit):
    """Join kind=file rows to absolute paths via kind=abspath. Refuses orphans."""
    paths, multiplicity, orphans = set(), {}, []
    for row in fold['rows']:
        ap = abspath.get(row['idx'])
        if ap is None:
            orphans.append((row['idx'], row['sub_path']))
            continue
        p = os.path.normpath(ap)
        paths.add(p)
        multiplicity.setdefault(p, []).append(row['idx'])
    if orphans:
        raise Refusal(
            f'{len(orphans)} folded file(s) in unit {unit!r} have no kind=abspath '
            f'partner and cannot be resolved to an absolute path: '
            f'{orphans[:5]!r}{" ..." if len(orphans) > 5 else ""}. Refusing to drop '
            f'them silently -- an unjoined row is exactly what a completeness check '
            f'must not lose.')
    return paths, multiplicity

# --- main --------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--binary', required=True)
    ap.add_argument('--trace', required=True)
    ap.add_argument('--unit', required=True, help='DW_AT_name of the PROGRAM CU')
    ap.add_argument('--dwarfdump', default='llvm-dwarfdump-21')
    ap.add_argument('--json')
    ap.add_argument('--drop-path', metavar='SUBSTR',
                    help="COMPARATOR NEGATIVE CONTROL ONLY. Delete every folded path "
                         "containing SUBSTR from the map set before comparing, so the "
                         "ARTIFACT-ONLY detector is forced to fire. A run that reports "
                         "'artifact-only empty' proves nothing until this flag has been "
                         "seen to produce a non-empty artifact-only set on the same "
                         "inputs (doctrine principle 5: a guard that has never fired is "
                         "a hope, not a guard). NEVER use it to produce a passing result.")
    a = ap.parse_args()

    def dump(*args):
        r = subprocess.run([a.dwarfdump, *args, a.binary], capture_output=True, text=True)
        if r.returncode != 0:
            raise Refusal(f'{a.dwarfdump} {" ".join(args)} exited {r.returncode}: '
                          f'{r.stderr.strip()[:400]}')
        return r.stdout

    units = parse_debug_info(dump('--debug-info'))
    unit = select_unit(units, a.unit)
    dirs, files = parse_debug_line(dump('--debug-line'), unit['stmt_list'])
    line_paths = render_line_files(dirs, files, unit['comp_dir'], a.unit)

    decl_paths = set()
    for p in unit['decl_files']:
        if not os.path.isabs(p):
            if unit['comp_dir'] is None:
                raise Refusal(f'relative DW_AT_decl_file {p!r} and unit {a.unit!r} '
                              f'has no DW_AT_comp_dir. Refusing.')
            p = os.path.join(unit['comp_dir'], p)
        decl_paths.add(os.path.normpath(p))

    artifact = decl_paths | line_paths
    fold, abspath = parse_trace(open(a.trace, errors='replace').read(), a.unit)
    mapped, multiplicity = join_map_paths(fold, abspath, a.unit)

    dropped = []
    if a.drop_path:
        dropped = sorted(p for p in mapped if a.drop_path in p)
        if not dropped:
            raise Refusal(
                f'--drop-path {a.drop_path!r} matched no folded path, so the negative '
                f'control could not fire. Refusing: a control that silently does '
                f'nothing is worse than no control.')
        mapped = mapped - set(dropped)

    artifact_only = sorted(artifact - mapped)
    map_only = sorted(mapped - artifact)
    dupes = {p: ix for p, ix in multiplicity.items() if len(ix) > 1}

    print(f'unit                : {a.unit!r}  (DW_AT_GNU_dwo_id from the trace: '
          f"{fold['identity']})")
    print(f'binary              : {a.binary}')
    if dropped:
        print(f'*** NEGATIVE CONTROL ACTIVE: {len(dropped)} path(s) deleted from the '
              f'map set via --drop-path {a.drop_path!r}. This run is a control, NOT a '
              f'completeness result. ***')
        for p in dropped:
            print(f'    dropped  {p}')
        print()
    print(f'artifact file set   : {len(artifact)} '
          f'(decl_file {len(decl_paths)} u line-table {len(line_paths)})')
    print(f'folded input set    : {len(mapped)} distinct paths from '
          f"{fold['folded']} kind=file rows")
    print()
    print(f'ARTIFACT-ONLY (omission -- must be empty): {len(artifact_only)}')
    for p in artifact_only:
        print(f'    OMITTED  {p}')
    print()
    print(f'MAP-ONLY (expected; explain each, never net away): {len(map_only)}')
    for p in map_only:
        print(f'    over-hashed  {p}')
    if dupes:
        print()
        print(f'one path admitted under several File.Index values '
              f'(Builder.debugFile does no dedup): {len(dupes)}')
        for p, ix in sorted(dupes.items()):
            print(f'    idx {ix} -> {p}')

    if a.json:
        with open(a.json, 'w') as f:
            json.dump({'unit': a.unit, 'binary': a.binary,
                       'identity': fold['identity'], 'folded_rows': fold['folded'],
                       'artifact_count': len(artifact), 'mapped_count': len(mapped),
                       'artifact_only': artifact_only, 'map_only': map_only,
                       'duplicate_index_paths': {p: ix for p, ix in dupes.items()}},
                      f, indent=2)

    print()
    if artifact_only:
        if dropped:
            print(f'RESULT: CONTROL FIRED -- {len(artifact_only)} artifact-only path(s) '
                  f'appeared once --drop-path removed known input. The detector works. '
                  f'This is NOT an omission in the compiler.')
            return 0
        print(f'RESULT: FAIL -- {len(artifact_only)} file(s) shaped the emitted debug '
              f'information and were NOT folded into the identity.')
        return 1
    if dropped:
        print('RESULT: CONTROL FAILED -- --drop-path removed real input and the '
              'artifact-only set is STILL empty. The detector does not fire; no '
              'completeness result from this comparator can be trusted.')
        return 1
    print('RESULT: PASS -- every file in the emitted debug information was folded.')
    print('        This proves INPUT COVERAGE only. It is not shared debug bodies, '
          'not size reduction, not .dwo emission.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Refusal as e:
        print(f'REFUSED: {e}', file=sys.stderr)
        sys.exit(2)
