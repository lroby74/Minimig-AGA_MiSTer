#!/usr/bin/env python3
"""Read the 68020 MOVE source x destination matrix out of MC68020UM.pdf.

    python3 parse_move_020.py MC68020UM.pdf > m68020_move.csv

The 68030 manual tabulates MOVE by destination, with one row for a register
source and one for everything else, and leaves the source addressing cost to a
separate fetch-effective-address table. The 68020 manual does not: section
8.2.6 is a full matrix whose cell already contains both effective address
calculations, so there is nothing to add to it. Three pages per case, best /
cache / worst, twelve source rows against twenty-three destination columns.

The text layer keeps the cells but not the grid, so the columns are recovered
from the x coordinate: every cell is assigned to the destination whose header
it sits closest to. A source label that wraps over two lines - '(d16,An) or'
above '(d16,PC)' - is joined back onto the row that carries the numbers.
"""
import sys, re, collections
import pymupdf

CELL = re.compile(r'^(\d+)\((\d+)/(\d+)/(\d+)\)$')
PAGES = {'best': (233, 234, 235), 'cache': (236, 237, 238), 'worst': (239, 240, 241)}


def rows_of(page):
    """Words grouped into rows, each row sorted left to right."""
    band = collections.defaultdict(list)
    for x0, y0, x1, y1, t, *_ in page.get_text('words'):
        if y0 < 80 or y0 > 700 or x0 < 50:
            continue
        band[y0].append((x0, t))
    out, ys = [], sorted(band)
    for y in ys:
        if out and y - out[-1][0] <= 8:
            out[-1][1].extend(band[y])
        else:
            out.append((y, list(band[y])))
    return [(y, sorted(ws)) for y, ws in out]


def parse_page(page):
    """{(source, destination): total clocks} for one page of one case."""
    rows = rows_of(page)
    head = next((ws for _, ws in rows
                 if any(t == 'Mode' for _, t in ws) and sum(1 for _, t in ws if t not in
                        ('Address', 'Mode', 'Source', 'Destination')) >= 4), None)
    if head is None:
        return {}
    cols = [(x, t) for x, t in head if t not in ('Address', 'Mode', 'Source', 'Destination')]
    cells = {}
    for _, ws in rows[rows.index(next(r for r in rows if r[1] is head)) + 1:]:
        nums = [(x, m) for x, t in ws if (m := CELL.match(t))]
        if not nums:
            continue          # a wrapped row label; its first line carries the numbers
        src = norm(' '.join(t for x, t in ws if not CELL.match(t)))
        for x, m in nums:
            dst = min(cols, key=lambda c: abs(c[0] - x))[1]
            cells[(src, norm(dst))] = int(m.group(1))
    return cells


def norm(s):
    """One spelling per row and column.

    A label naming two equivalent modes - "(d16,An) or (d16,PC)" - wraps over
    two lines, and the worst case pages capitalise the displacement, so only
    the part before "or" is kept and the case is dropped.
    """
    s = re.sub('[\u2010-\u2015\u2212]', '-', s)
    s = re.split(r'\s+or\b', s)[0]
    s = re.sub(r'\s+', ' ', s).strip().lower()
    return TYPO.get(s, s)


# The first page of each case, 8-21, 8-23 and 8-26, prints the nineteenth source
# row as ([d16,B],d32); the two continuation pages of all three cases print it
# as ([d16,B],I,d32), and the surrounding rows run ([B],I) ([B],I,d16)
# ([B],I,d32) ([d16,B],I) ([d16,B],I,d16) _ ([d32,B],I), so the index is
# dropped in printing on one page, not a twenty-fourth row.
TYPO = {'([d16,b],d32)': '([d16,b],i,d32)'}


if __name__ == '__main__':
    doc = pymupdf.open(sys.argv[1] if len(sys.argv) > 1 else 'MC68020UM.pdf')
    case = {}
    for name, pages in PAGES.items():
        for p in pages:
            case.setdefault(name, {}).update(parse_page(doc[p]))
    keys = sorted(set(case['best']) & set(case['cache']) & set(case['worst']))
    w = sys.stdout
    w.write('# MC68020UM.pdf section 8.2.6, MOVE instruction, %d cells\n' % len(keys))
    w.write('source,destination,best,cache,worst\n')
    for k in keys:
        w.write('"%s","%s",%d,%d,%d\n' % (k[0], k[1], case['best'][k], case['cache'][k], case['worst'][k]))
    for name in PAGES:
        miss = sorted(set(case[name]) - set(keys))
        if miss:
            print('%s: %d cells with no counterpart: %s' % (name, len(miss), miss[:6]), file=sys.stderr)
