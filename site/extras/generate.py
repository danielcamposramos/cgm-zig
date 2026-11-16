#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fill the two generated figures of the site from the repository's own record.

  python3 site/extras/generate.py            rewrite site/index.html and site/changes.html in place
  python3 site/extras/generate.py --check    exit 1 if the pages are not what this script would write

patch-files (changes.html): every commit of main that changes the compiler's source (src/, lib/) since the
upstream import, read from git: its date, its subject, the files it touches and the lines it adds and removes.
build-timings (index.html): the runs the README and BUILDING.md record, each with its workload and its source.
The runs are written here as data, each with the line it comes from; nothing is measured by this script.
"""
import html
import re
import subprocess
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
REPO = SITE.parent
IMPORT = '754b7a3872'           # "Import upstream Zig 0.16.0 verbatim"
MAIN = 'origin/main'
GH = 'https://github.com/danielcamposramos/cgm-zig'

# The recorded runs. Different workloads: never one scale, never compared with each other.
RUNS = [
    ('Stock Zig 0.16.0', 'The full build of about 1,800 modules, as one compilation unit',
     'Died silently after more than two hours, every time', f'{GH}/blob/main/README.md#why-this-fork-exists', 'README'),
    ('cgm-zig 0.16.0+cgm.046d6833', 'The same full build',
     'Completed in under 45 minutes, six full builds in a row without running out of memory',
     f'{GH}/blob/main/README.md#why-this-fork-exists', 'README'),
    ('cgm-zig at commit a7f31c36', 'The same workload, the run in which the named message fired twice',
     'Completed, exit 0, in 18 min 10 s with an 18.4 GiB peak',
     f'{GH}/blob/main/README.md#a-the-frontend-crash-becomes-a-named-refusal', 'README, (a)'),
    ('Building cgm-zig itself', 'A clean build of the compiler under an 8-CPU mask on a busy host',
     'About 41 minutes; 8 to 9 minutes on an idle, unconstrained host',
     f'{GH}/blob/main/docs/crown/BUILDING.md', 'BUILDING.md'),
]


def git(*args):
    return subprocess.run(['git', '-C', str(REPO), *args], check=True, capture_output=True, text=True).stdout


def commits():
    out = git('log', '--reverse', '--no-merges', '--numstat', '--format=%x01%H%x02%cs%x02%s', f'{IMPORT}..{MAIN}', '--', 'src', 'lib')
    rows = []
    for block in out.split('\x01')[1:]:
        head, _, rest = block.partition('\n')
        sha, date, subject = head.split('\x02')
        files, added, removed = [], 0, 0
        for line in rest.splitlines():
            parts = line.split('\t')
            if len(parts) == 3 and parts[0].isdigit():
                added += int(parts[0])
                removed += int(parts[1])
                files.append(parts[2])
        rows.append((sha, date, subject, files, added, removed))
    return rows


def e(text):
    return html.escape(text, quote=True)


def patch_files():
    rows = commits()
    files = sorted({f for r in rows for f in r[3]})
    added, removed = sum(r[4] for r in rows), sum(r[5] for r in rows)
    body = []
    for sha, date, subject, fs, a, r in rows:
        names = ', '.join(f'<code>{e(f)}</code>' for f in fs[:3]) + (f' and {len(fs) - 3} more' if len(fs) > 3 else '')
        body.append(f'<tr><td data-label="Date">{date}</td>'
                    f'<td data-label="Change"><a href="{GH}/commit/{sha}">{e(subject)}</a></td>'
                    f'<td data-label="Files">{names}</td>'
                    f'<td data-label="Lines">+{a:,} &minus;{r:,}</td></tr>')
    return (f'<figcaption>Every change to the compiler&rsquo;s source since Zig 0.16.0 was imported: {len(rows)} commits, '
            f'{len(files)} files, {added:,} lines added and {removed:,} removed across those commits. Read from the repository&rsquo;s history by '
            f'<a href="{GH}/blob/main/site/extras/generate.py">a script</a>, not typed by hand.</figcaption>\n'
            '<div class="table-wrap" role="region" aria-label="Commits that change the compiler" tabindex="0"><table>'
            '<caption>Commits that change the compiler</caption><thead><tr><th scope="col">Date</th><th scope="col">Change</th>'
            '<th scope="col">Files</th><th scope="col">Lines</th></tr></thead><tbody>\n' + '\n'.join(body) + '\n</tbody></table></div>')


def build_timings():
    body = '\n'.join(f'<tr><td data-label="Compiler">{e(c)}</td><td data-label="Workload">{e(w)}</td>'
                     f'<td data-label="What the record shows">{e(r)}</td>'
                     f'<td data-label="Source"><a href="{u}">{e(s)}</a></td></tr>' for c, w, r, u, s in RUNS)
    return ('<figcaption>The runs the repository records, each with its workload. They are wall-clock readings on the '
            'maintainer&rsquo;s build station; the rows are different workloads and are not compared with each other.</figcaption>\n'
            '<div class="table-wrap" role="region" aria-label="Recorded runs" tabindex="0"><table><caption>Recorded runs</caption>'
            '<thead><tr><th scope="col">Compiler</th><th scope="col">Workload</th><th scope="col">What the record shows</th>'
            '<th scope="col">Source</th></tr></thead><tbody>\n' + body + '\n</tbody></table></div>')


def fill(page, name, content):
    path = SITE / page
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(r'(<figure data-extra="' + name + r'">)(.*?)(</figure>)', re.S)
    match = pattern.search(text)
    if not match:
        sys.exit(f'{page}: no <figure data-extra="{name}">')
    comment = re.match(r'\s*<!--.*?-->', match.group(2), re.S)
    new = pattern.sub(lambda m: m.group(1) + (comment.group(0) if comment else '') + '\n' + content + '\n' + m.group(3), text, count=1)
    return path, text, new


def main():
    check = '--check' in sys.argv[1:]
    stale = []
    for page, name, make in (('changes.html', 'patch-files', patch_files), ('index.html', 'build-timings', build_timings)):
        path, old, new = fill(page, name, make())
        if old != new:
            stale.append(page)
            if not check:
                path.write_text(new, encoding='utf-8')
    if check and stale:
        sys.exit('not up to date: ' + ', '.join(stale) + ' (run site/extras/generate.py)')
    print('checked' if check else 'written', ', '.join(stale) or 'nothing to change')


if __name__ == '__main__':
    main()
