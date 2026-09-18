#!/usr/bin/env python3
"""Build the per-instruction cycle ROM for the TG68K pipeline budget.

  python3 gen_cycle_rom.py 68030 > ../../rtl/tg68k/m68k_cycles_030.mif
  python3 gen_cycle_rom.py 68020 > ../../rtl/tg68k/m68k_cycles_020.mif

Every number comes from a row of m68030_timing.csv / m68020_timing.csv, which
are machine-extracted from the Motorola manuals (see README.md). Nothing is
estimated: a form this script cannot tie to a table row is emitted with its
valid bit clear, and the RTL falls back to the averaged clock divider for it.
That way the table improves fidelity where it is filled and never makes a form
worse than it is today.

ROM shape
---------
Indexed by {opcode[15:6], opcode[5:3]} - 8192 entries. Those thirteen bits are
what the timing depends on: opcode[2:0] is always a register number and never
changes the time, except through mode 7, where it picks the addressing mode -
and that is handled by the separate effective-address table, indexed by the
full opcode[5:0].

Entry, 20 bits:

    [19]    valid       0 -> not modelled, use the averaged divider
    [18:16] ea_class    0 none, 1 fea, 2 fiea, 3 cea, 4 ciea, 5 jea
    [15:14] tail        clocks of this instruction the next one can absorb
    [13:9]  head        clocks of this instruction the previous tail can cover
    [8:1]   cc          instruction-cache-case clocks
    [0]     spare

The RTL charges  cc - min(head, tail_of_previous)  clocks per instruction and
keeps tail for the next one, which is equation 11-1 of the 68030 manual.
"""
import csv, sys, os, re

HERE = os.path.dirname(os.path.abspath(__file__))

class Table:
    def __init__(self, cpu):
        self.cpu = cpu
        self.rows = {}
        self.used = set()
        path = os.path.join(HERE, f'm{cpu}_timing.csv')
        for r in csv.DictReader(open(path)):
            key = (r['section'], self.norm(r['instruction']))
            if key not in self.rows:
                self.rows[key] = r

    @staticmethod
    def norm(s):
        if not s:
            return ''
        """Canonical form of a table label, so a lookup and a CSV row agree.

        The manuals use typographic characters the PDF text layer keeps
        (angle brackets round <data>, an en dash for -(An)), and the first row
        of each table inherits the header above it. Footnote markers lead a
        label. Everything here is about making those agree; '+' is kept
        because (An)+ is a different row from (An).
        """
        s = s.lower()
        s = re.sub(r'^[*#%+\s]+', '', s)
        s = re.sub(r'[\u2010-\u2015\u2212]', '-', s)          # dashes
        s = re.sub(r'[^\x00-\x7f]', '', s)                    # <data> brackets etc
        s = s.replace('<', '').replace('>', '').replace('#', '')
        s = re.sub(r'\s+', ' ', s).strip()
        s = re.sub(r'\s*,\s*', ',', s)
        s = re.sub(r'^(no-cache case|i-cache case|worst case|cache case|best case)\s+', '', s)
        s = re.sub(r'^.*?(single effective address instruction format|'
                   r'brief format extension word|full format extension word\(s\))\s+', '', s)
        return s.strip()

    def get(self, section, label):
        """(cc, head, tail) for one table row, or raise if the row is missing."""
        key = (section, self.norm(label))
        r = self.rows.get(key)
        if r is None:
            raise KeyError(f'{self.cpu}: no row {key!r}')
        self.used.add(key)
        if self.cpu == '68030':
            head = r['head']
            head = int(head) if head.isdigit() else int(re.match(r'(\d+)', head).group(1))
            return int(r['cc']), head, int(r['tail'])
        # 68020: best case is the fully overlapped time, so cache-best is what
        # an instruction can absorb from the previous tail (section 8.1.4).
        cc, best = int(r['cache']), int(r['best'])
        return cc, max(0, cc - best), max(0, cc - best)

    def has(self, section, label):
        return (section, self.norm(label)) in self.rows


# --------------------------------------------------------------------------
# ROM generation
# --------------------------------------------------------------------------
import decode as dec

EA_SECTION = {dec.FEA: 'fea', dec.FIEA: 'fiea', dec.CEA: 'cea',
              dec.CIEA: 'ciea', dec.JEA: 'jea'}


def build(cpu):
    """Return (entries, stats). entries is 8192 ints of 20 bits."""
    t = Table(cpu)
    entries = [0] * 8192
    hit = miss = unmapped = 0
    missing = {}
    for idx in range(8192):
        op = ((idx >> 3) << 6) | ((idx & 7) << 3)
        d = dec.decode(op)
        if d is None:
            unmapped += 1
            continue
        section, label, ea = d
        try:
            cc, head, tail = t.get(section, label)
        except KeyError:
            miss += 1
            missing[(section, label)] = missing.get((section, label), 0) + 1
            continue
        hit += 1
        cc = min(cc, 255)
        head = min(head, 31)
        tail = min(tail, 3)
        entries[idx] = (1 << 19) | (ea << 16) | (tail << 14) | (head << 9) | (cc << 1)
    return entries, dict(hit=hit, miss=miss, unmapped=unmapped, missing=missing)


def mif(entries, width=20):
    out = [f'-- generated by tools/m68k_timing/gen_cycle_rom.py, do not edit',
           f'DEPTH = {len(entries)};', f'WIDTH = {width};',
           'ADDRESS_RADIX = HEX;', 'DATA_RADIX = HEX;', 'CONTENT', 'BEGIN']
    run_start, run_val = 0, entries[0]
    for i in range(1, len(entries) + 1):
        v = entries[i] if i < len(entries) else None
        if v != run_val:
            if i - 1 == run_start:
                out.append(f'  {run_start:04X} : {run_val:05X};')
            else:
                out.append(f'  [{run_start:04X}..{i-1:04X}] : {run_val:05X};')
            run_start, run_val = i, v
    out += ['END;']
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    cpu = sys.argv[1] if len(sys.argv) > 1 else '68030'
    entries, st = build(cpu)
    n = len(entries)
    print(f'{cpu}: {st["hit"]} of {n} index slots tied to a table row '
          f'({100*st["hit"]/n:.1f}%), {st["unmapped"]} not decoded, '
          f'{st["miss"]} decoded but no matching row', file=sys.stderr)
    for k, v in sorted(st['missing'].items(), key=lambda x: -x[1])[:25]:
        print(f'    missing row {k[0]}/{k[1]!r}  ({v} slots)', file=sys.stderr)
    sys.stdout.write(mif(entries))
