# Fixture: file in multiple modules

A synthetic three-file reproduction for the "file exists in modules" diagnostic.

`dupe.zig` is reached two ways: directly from the root (`main.zig`), which puts
it in module `root`, and from `mod_b.zig`, which puts it in module `mod_b`.
`dupe.zig` is therefore the double-owned file — the one the user has to fix —
while `mod_b.zig` is merely the importer being scanned when the conflict
surfaced.

## Run

From this directory:

```
zig build-obj --dep mod_b -Mroot=main.zig -Mmod_b=mod_b.zig
```

Exits 1 and prints four diagnostic lines (plus the quoted source line and caret
under each note that has one).

## Expected

```
dupe.zig:1:1: error: file exists in modules 'root' and 'mod_b'
dupe.zig:1:1: note: files must belong to only one module
main.zig:3:17: note: file is imported here by the root of module 'root'
mod_b.zig:2:17: note: file is imported here by the root of module 'mod_b'
```

The root message and its first note name **`dupe.zig`** — the double-owned file.
The two remaining notes keep each module's claim with the import site that
established it, which is the information needed to decide *which* of the two
imports to remove.

## The behavior this fixture pins

A compiler that anchors the root message on `mod_b.zig` is exhibiting the defect
this fixture exists for: the reader is sent into an importer, and `dupe.zig` is
named nowhere in the report except incidentally, inside the quoted `@import`
strings of other files. On a large hyper-modular build — where the import string
is a short alias and the real path is deep — that leaves the culprit recoverable
only by hand-parsing the compilation's `-M` module definitions.

The `--dep`/`-M` form above is deliberate: it is the shape a build system emits,
so the fixture reproduces without a `build.zig` of its own.
