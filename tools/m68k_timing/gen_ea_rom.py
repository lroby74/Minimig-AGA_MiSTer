#!/usr/bin/env python3
"""Build the effective-address timing ROM.

  python3 gen_ea_rom.py 68030 > ../../rtl/tg68k/m68k_ea_030.mif

Equation 11-2 of the 68030 manual composes an instruction out of the effective
address and the operation, overlapping them by the same min(head,tail) rule
that joins consecutive instructions:

    CCea + [CCop - min(Hop, Tea)]

So the RTL needs the effective address's own cc, head and tail, not just a
number of clocks to add.

Indexed by {ea_class[2:0], size[1:0], mode[2:0], reg[2:0]} - 2048 entries.
Size is opcode[7:6] and only matters for the immediate forms, where the table
gives .B/.W and .L their own rows.

Entry, 16 bits:  [15] valid  [14:8] cc  [7:3] head  [2:1] tail  [0] spare
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_cycle_rom import Table
import decode as dec

# mode/reg -> the label the manual's effective-address tables use.
# Dn and An are the rows marked '%' - no clock cycles incurred - so they are
# entered directly as zero rather than looked up.
MODE_LABEL = {
    2: '(An)',
    3: '(An)+',
    4: '-(An)',
    5: '(d16,An) or (d16,PC)',
    6: '( d8,An,Xn) or ( d8,PC,Xn)',
}
MODE7_LABEL = {
    0: '(xxx).W',
    1: '(xxx).L',
    2: '(d16,An) or (d16,PC)',
    3: '( d8,An,Xn) or ( d8,PC,Xn)',
}

# The first row of the fea table is merged with the header above it by the PDF
# text layer; this is that row, read off the scan.
ALIAS = {
    ('fea', '(An)'): '0(0/0/0) 0(0/0/0) % An - - 0(0/0/0) 0(0/0/0) (An)',
}

SIZE_SUFFIX = {0: '.B', 1: '.W', 2: '.L'}

# 11.6.3 Calculate Effective Address (cea), page 11-31 of the manual. The PDF
# lays this table out in a way the text extraction interleaves wrongly, so the
# simple modes are transcribed here from the page itself, as (cc, head, tail).
# "X + op head" in the head column means the total head runs through the
# address calculation and takes in the operation's head as well (11.5), which
# the RTL adds on top; the number here is X.
CEA = {
    (0, 0): (0, 0, 0),   # Dn  - marked %, no cycles
    (1, 0): (0, 0, 0),   # An  - marked %, no cycles
    (2, 0): (2, 2, 0),   # (An)              2 + op head
    (3, 0): (2, 0, 0),   # (An)+             0
    (4, 0): (2, 2, 0),   # -(An)             2 + op head
    (5, 0): (2, 2, 0),   # (d16,An)          2 + op head
    (6, 0): (4, 4, 0),   # (d8,An,Xn) brief  4 + op head
    (7, 0): (2, 2, 0),   # (xxx).W           2 + op head
    (7, 1): (4, 4, 0),   # (xxx).L           4 + op head
    (7, 2): (2, 2, 0),   # (d16,PC)          2 + op head
    (7, 3): (4, 4, 0),   # (d8,PC,Xn) brief  4 + op head
}


# 11.6.5 Jump Effective Address, page 11-35. Same story as cea: transcribed
# from the page. Only the modes JMP and JSR accept appear here; the rest of
# the table runs onto the following page and is not yet transcribed.
JEA = {
    (7, 0): (2, 2, 0),   # (xxx).W            2 + op head
    (7, 1): (2, 2, 0),   # (xxx).L            2 + op head
    (6, 0): (6, 6, 0),   # (d8,An,Xn) brief   6 + op head
    (7, 3): (6, 6, 0),   # (d8,PC,Xn) brief   6 + op head
}


def ea_label(section, size, mode, reg):
    """The table row for one addressing mode, or None when there is no row."""
    if mode in (0, 1):
        return 'ZERO'
    if section == 'fiea':
        # immediate source plus a destination: rows are '#<data>.W,<dest>'
        w = '.L' if size == 2 else '.W'
        if mode == 0:
            return f'#<data>{w}, Dn'
        dest = MODE_LABEL.get(mode) if mode != 7 else MODE7_LABEL.get(reg)
        if dest is None:
            return None
        dest = {'(xxx).W': '$XXX.W', '(xxx).L': '$XXX.L',
                '( d8,An,Xn) or ( d8,PC,Xn)': '(d8,An,Xn) or (d8,PC,Xn)'}.get(dest, dest)
        return f'#<data>{w},{dest}'
    if mode == 7 and reg == 4:                       # immediate operand
        if section != 'fea':
            return None
        return f'#<data>{SIZE_SUFFIX.get(size, ".W")}'
    lbl = MODE_LABEL.get(mode) if mode != 7 else MODE7_LABEL.get(reg)
    return lbl


def build(cpu):
    t = Table(cpu)
    entries = [0] * 2048
    hit = zero = miss = 0
    missing = {}
    for idx in range(2048):
        cls, size, mode, reg = (idx >> 8) & 7, (idx >> 6) & 3, (idx >> 3) & 7, idx & 7
        section = {dec.FEA: 'fea', dec.FIEA: 'fiea', dec.CEA: 'cea',
                   dec.CIEA: 'ciea', dec.JEA: 'jea'}.get(cls)
        if section is None:
            continue
        if section == 'jea':
            v = JEA.get((mode, reg if mode == 7 else 0))
            if v is None:
                continue
            cc, head, tail = v
            entries[idx] = (1 << 15) | (cc << 8) | (head << 3) | (tail << 1)
            hit += 1
            continue
        if section == 'cea':
            v = CEA.get((mode, reg if mode == 7 else 0))
            if v is None:
                continue
            cc, head, tail = v
            entries[idx] = (1 << 15) | (min(cc, 127) << 8) | (min(head, 31) << 3) | (tail << 1)
            hit += 1
            continue
        lbl = ea_label(section, size, mode, reg)
        if lbl is None:
            continue
        if lbl == 'ZERO':
            entries[idx] = 1 << 15                    # valid, cc/head/tail all zero
            zero += 1
            continue
        lbl = ALIAS.get((section, lbl), lbl)
        try:
            cc, head, tail = t.get(section, lbl)
        except KeyError:
            miss += 1
            missing[(section, lbl)] = missing.get((section, lbl), 0) + 1
            continue
        hit += 1
        entries[idx] = (1 << 15) | (min(cc, 127) << 8) | (min(head, 31) << 3) | (min(tail, 3) << 1)
    return entries, dict(hit=hit, zero=zero, miss=miss, missing=missing)


if __name__ == '__main__':
    from gen_cycle_rom import mif
    cpu = sys.argv[1] if len(sys.argv) > 1 else '68030'
    e, st = build(cpu)
    print(f'{cpu} ea: {st["hit"]} rows resolved, {st["zero"]} register modes (zero cost), '
          f'{st["miss"]} with no matching row', file=sys.stderr)
    for k, v in sorted(st['missing'].items(), key=lambda x: -x[1])[:20]:
        print(f'    missing {k[0]}/{k[1]!r} ({v})', file=sys.stderr)
    sys.stdout.write(mif(e, 16))
