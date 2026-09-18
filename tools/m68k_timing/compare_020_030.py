#!/usr/bin/env python3
"""Set the 68020 timing tables against the 68030 ones, form by form.

    python3 compare_020_030.py            what the two manuals disagree about
    python3 compare_020_030.py -v         every shared form, side by side
    python3 compare_020_030.py trace.txt  what the missing tails would cost

The 68030 manual publishes, for each instruction, a head and a tail: how many
clocks of it the instruction before can cover, and how many it leaves for the
instruction after. Equation 11-1 is written in those terms and rtl/cpu_cycles.v
implements it directly.

The 68020 manual publishes a best, a cache and a worst case instead. Best case
is defined as the instruction in cache "and benefiting from maximum overlap due
to other instructions", so cache minus best is a head. There is no tail: what
an instruction leaves for its successor is never stated, and section 8.1.5's
worked examples show it is real - the same four instructions come out 6/0/9/1
at one alignment and 4/3/6/3 at another.

This prints what that costs. It is the evidence behind the note in README.md
about why the 68020 mode is not on the tables.
"""
import csv, re, sys, collections
from gen_cycle_rom import Table

N = Table.norm


def load(path, keyfn):
    out = {}
    for r in csv.DictReader(open(path)):
        out.setdefault((r['section'], N(r['instruction'])), r)
    return out


def num(s, d=None):
    m = re.match(r'(\d+)', s or '')
    return int(m.group(1)) if m else d


def main():
    r30 = load('m68030_timing.csv', None)
    r20 = load('m68020_timing.csv', None)
    shared = sorted(set(r30) & set(r20))
    rows, agree = [], 0
    for k in shared:
        a, b = r30[k], r20[k]
        cc30, h30, t30 = num(a['cc']), num(a['head']), num(a['tail'])
        cc20, bc20 = num(b['cache']), num(b['best'])
        if None in (cc30, h30, cc20, bc20):
            continue
        h20 = cc20 - bc20
        rows.append((k, cc30, h30, t30, cc20, h20))
        agree += h30 == h20
    if '-v' in sys.argv:
        print('%-9s %-30s %11s %8s' % ('section', 'form', '030 cc/h/t', '020 cc/h'))
        for k, cc30, h30, t30, cc20, h20 in rows:
            print('%-9s %-30s %4d/%2d/%d %5d/%2d %s' %
                  (k[0], k[1][:30], cc30, h30, t30, cc20, h20,
                   '' if h30 == h20 else '<-'))
    print('\nhead: the 68030 head and the 68020 cache-minus-best agree on '
          '%d of %d shared forms (%d%%)' % (agree, len(rows), 100 * agree // len(rows)))
    d30 = collections.Counter(h for _, _, h, _, _, _ in rows)
    d20 = collections.Counter(h for *_, h in rows)
    print('      68030 head reaches %d; 68020 cache-minus-best reaches %d'
          % (max(d30), max(d20)))
    full = sum(1 for _, cc, h, _, _, _ in rows if h == cc and h)
    print('      the 68030 lets %d of these forms be absorbed whole; the 68020\'s '
          'best case\n      is bounded by what a real predecessor offers, so it '
          'never says that' % full)
    t = collections.Counter(num(r['tail'], 0) for r in csv.DictReader(open('m68030_timing.csv')))
    print('\ntail: 68030 %s, 68020 not published' % dict(sorted(t.items())))
    for a in sys.argv[1:]:
        if not a.startswith('-'):
            print('      %s' % cost_of_no_tail(a))


def cost_of_no_tail(path):
    """What a whole instruction stream costs if no instruction lends a tail.

    That is the 68020's position: the heads are published, the tails are not,
    so the only honest thing the tables can charge is the cache case of every
    instruction with nothing taken off. Run against a trace captured from the
    real kernel, this says how far that lands from the 68030, which does
    publish them.
    """
    import model, gen_cycle_rom as g
    tr = [tuple(int(x) for x in l.split()) for l in open(path) if l.strip()]
    keep = g.build
    with_tails, _ = model.run(tr)
    g.build = model.entries.__globals__['build'] = \
        lambda cpu: ([v & ~(3 << 14) for v in keep(cpu)[0]], keep(cpu)[1])
    without, _ = model.run(tr)
    g.build = model.entries.__globals__['build'] = keep
    return ('%d instructions: %d clocks with the tails, %d without (+%.2f%%)'
            % (len(tr), with_tails, without, 100 * (without - with_tails) / with_tails))


if __name__ == '__main__':
    main()
