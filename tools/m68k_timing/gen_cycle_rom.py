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
Indexed by fourteen bits:

    mode 7   ->  {opcode[15:6], 1'b1, opcode[2:0]}
    otherwise->  {opcode[15:6], 1'b0, opcode[5:3]}

opcode[2:0] is a register number, and a register number never changes a time -
except under mode 7, where it selects the addressing mode and sometimes the
instruction itself: ORI to CCR against ORI to memory, TRAPcc against Scc, and
the whole of 4E70-4E77, where RESET, NOP, STOP, RTE, RTD, RTS, TRAPV and RTR
share everything above bit 2 and run from two clocks to five hundred eighteen.
So mode 7 gets its own half of the ROM. `collisions()` walks all eight low
values of every slot and reports any that disagree, so this is checked rather
than asserted.

Entry, 20 bits:

    [19]    valid       0 -> not modelled, charged the architectural minimum
    [18:16] ea_class    0 none, 1 fea, 2 fiea, 3 cea, 4 ciea, 5 jea
    [15:14] tail        clocks of this instruction the next one can absorb
    [13:9]  head        clocks of this instruction the previous tail can cover
    [8:1]   cc          instruction-cache-case clocks
    [0]     spare

The RTL charges  cc - min(head, tail_of_previous)  clocks per instruction and
keeps tail for the next one, which is equation 11-1 of the 68030 manual.
"""
import csv, sys, os, re, io

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


def index(op):
    """The ROM slot an opcode reads."""
    if (op >> 3) & 7 == 7:
        return ((op >> 6) << 4) | 8 | (op & 7)
    return ((op >> 6) << 4) | ((op >> 3) & 7)


def unindex(idx):
    """A representative opcode for a slot."""
    hi = (idx >> 4) << 6
    return hi | (0x38 | (idx & 7)) if idx & 8 else hi | ((idx & 7) << 3)


def collisions():
    """Indices where opcode[2:0] changes the instruction, not just a register.

    The ROM is indexed by thirteen bits on the claim that the low three are
    always a register number. That holds everywhere except 4E70-4E77, where
    they select between RESET, NOP, STOP, RTE, RTD, RTS, TRAPV and RTR - two
    clocks to five hundred and eighteen. This walks all eight and reports any
    index whose eight opcodes do not agree, so the claim is checked rather
    than trusted.
    """
    bad = {}
    for idx in range(16384):
        base = unindex(idx)
        if idx & 8:
            continue                       # mode 7 slots carry opcode[2:0]
        if idx & 7 == 7:
            continue                       # a mode-7 opcode never lands here
        forms = {dec.decode(base | r) for r in range(8)}
        if len(forms) > 1:
            bad[idx] = sorted(str(f) for f in forms)
    return bad


def build(cpu):
    """Return (entries, stats). entries is 8192 ints of 20 bits."""
    t = Table(cpu)
    entries = [0] * 16384
    hit = miss = unmapped = 0
    missing = {}
    for idx in range(16384):
        op = unindex(idx)
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
    d = (width + 3) // 4
    out = [f'-- generated by tools/m68k_timing/gen_cycle_rom.py, do not edit',
           f'DEPTH = {len(entries)};', f'WIDTH = {width};',
           'ADDRESS_RADIX = HEX;', 'DATA_RADIX = HEX;', 'CONTENT', 'BEGIN']
    run_start, run_val = 0, entries[0]
    for i in range(1, len(entries) + 1):
        v = entries[i] if i < len(entries) else None
        if v != run_val:
            if i - 1 == run_start:
                out.append(f'  {run_start:04X} : {run_val:0{d}X};')
            else:
                out.append(f'  [{run_start:04X}..{i-1:04X}] : {run_val:0{d}X};')
            run_start, run_val = i, v
    out += ['END;']
    return '\n'.join(out) + '\n'


def hexdump(entries, digits):
    return ''.join(f'{v:0{digits}X}\n' for v in entries)


def palette(entries):
    """Split a ROM image into an index image and the distinct entries.

    The tables repeat heavily - a 68030 has far fewer distinct (cc, head,
    tail, ea class) combinations than it has opcode forms - so storing an
    index into the distinct set costs a third of the memory the raw image
    would. 16384 twenty-bit entries is 32 M10K; 16384 six-bit indices is 10.
    """
    vals = sorted(set(entries))
    pos = {v: i for i, v in enumerate(vals)}
    return [pos[v] for v in entries], vals


def emit_palette(entries, width, name, sig, out, comment):
    """Write <name>_idx.mif and <name>_pal.vh, return the index width."""
    idx, vals = palette(entries)
    w = max(1, (len(vals) - 1).bit_length())
    io.open(f'{name}_idx.mif', 'w').write(mif(idx, w))
    io.open(f'{name}_idx.hex', 'w').write(hexdump(idx, (w + 3) // 4))
    with io.open(f'{name}_pal.vh', 'w') as f:
        f.write(f'// generated by tools/m68k_timing/gen_cycle_rom.py, do not edit\n')
        f.write(f'// {comment}\n')
        f.write(f'always @* case({sig})\n')
        for i, v in enumerate(vals):
            f.write(f"\t{w}'d{i}: {out} = {width}'h{v:0{(width+3)//4}X};\n")
        f.write(f"\tdefault: {out} = {width}'d0;\n")
        f.write('endcase\n')
    return w, len(vals)


if __name__ == '__main__':
    cpu = sys.argv[1] if len(sys.argv) > 1 else '68030'
    bad = collisions()
    if bad:
        print(f'{cpu}: {len(bad)} index slots where opcode[2:0] changes the '
              f'instruction - these need the misc ROM:', file=sys.stderr)
        for k, v in sorted(bad.items()):
            print(f'    idx {k:04X} (opcode {unindex(k):04X}..{unindex(k)|7:04X}): '
                  f'{len(v)} different forms', file=sys.stderr)
    if '--misc' in sys.argv:
        # 4E70-4E77 is the one slot where opcode[2:0] picks the instruction and
        # mode is not 7, so it cannot ride the mode-7 half of the ROM. Eight
        # entries, emitted as a case the RTL includes.
        t = Table(cpu)
        print('// generated by tools/m68k_timing/gen_cycle_rom.py --misc, do not edit')
        print('// 4E70-4E77: opcode[2:0] selects the instruction, not a register')
        print('always @* case(opc_l[2:0])')
        for r in range(8):
            d = dec.decode(0x4E70 | r)
            cc, head, tail = t.get(d[0], d[1])
            w = (1 << 19) | (d[2] << 16) | (min(tail, 3) << 14) | (min(head, 31) << 9) | (min(cc, 255) << 1)
            print(f"\t3'd{r}: misc_e = 20'h{w:05X};   // {d[1]}  cc {cc} head {head} tail {tail}")
        print('endcase')
        sys.exit(0)
    entries, st = build(cpu)
    n = len(entries)
    print(f'{cpu}: {st["hit"]} of {n} index slots tied to a table row '
          f'({100*st["hit"]/n:.1f}%), {st["unmapped"]} not decoded, '
          f'{st["miss"]} decoded but no matching row', file=sys.stderr)
    for k, v in sorted(st['missing'].items(), key=lambda x: -x[1])[:25]:
        print(f'    missing row {k[0]}/{k[1]!r}  ({v} slots)', file=sys.stderr)
    if '--split' in sys.argv:
        w, n = emit_palette(entries, 20, '../../rtl/tg68k/m68k_cyc', 'cyc_i', 'cyc_e',
                            'instruction timing, indexed by m68k_cyc_idx.mif')
        print(f'{cpu}: {n} distinct entries, index {w} bits '
              f'({16384*w} bit, {(16384*w+10239)//10240} M10K instead of '
              f'{(16384*20+10239)//10240})', file=sys.stderr)
        sys.exit(0)
    sys.stdout.write(hexdump(entries, 5) if '--hex' in sys.argv else mif(entries))
