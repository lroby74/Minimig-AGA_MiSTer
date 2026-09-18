#!/usr/bin/env python3
"""Work out what a stream of instructions costs, from the tables alone.

  python3 model.py trace.txt

The trace is one line per instruction: the opcode, the condition code of the
instruction before it, and the word after the opcode - opc_cond and opc_snd as
the RTL sees them. This applies
equations 11-1 and 11-2 in plain Python, so it is a second opinion on what
rtl/cpu_cycles.v should be charging. The two disagreeing means one of them is
wrong, which is the point.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_cycle_rom import Table, index
from gen_ea_rom import build as ea_build
import decode as dec


def entries(cpu='68030'):
    from gen_cycle_rom import build
    ins, _ = build(cpu)
    ea, _ = ea_build(cpu)
    return ins, ea


def unpack_ins(v):
    return dict(valid=bool(v >> 19 & 1), ea=v >> 16 & 7,
                tail=v >> 14 & 3, head=v >> 9 & 31, cc=v >> 1 & 255)


def unpack_ea(v):
    return dict(valid=bool(v >> 15 & 1), cc=v >> 8 & 127,
                head=v >> 3 & 31, tail=v >> 1 & 3, plus=v & 1)


def movem_n(op, snd):
    """(cc, head, tail) for a MOVEM, or None if this is not one.

    The register count is in the word after the opcode, so no table indexed by
    the opcode can hold the time. 11.6.7: 8+4n going to registers, 4+2n coming
    from them, head 2 and tail 0 either way.
    """
    if (op >> 12) != 4 or not (op >> 11) & 1 or (op >> 8) & 3 or not (op >> 7) & 1:
        return None
    if not (op >> 3) & 7:
        return None                   # mode 0 is EXT, not MOVEM
    n = bin(snd & 0xFFFF).count('1')
    return (8 + 4 * n if (op >> 10) & 1 else 4 + 2 * n), 2, 0


def run(trace, cpu='68030'):
    ins, ea = entries(cpu)
    prev_tail = 0
    total = 0
    pend = False                      # a byte branch is waiting on its outcome
    detail = []
    for n, (op, cond, snd) in enumerate(trace):
        i = unpack_ins(ins[index(op)])
        mv = movem_n(op, snd)
        if mv:
            i = dict(valid=True, ea=dec.CIEA, cc=mv[0], head=mv[1], tail=mv[2])
        if op & 0xFFF8 == 0x4E70:     # 4E70-4E77 has its own eight entries
            d = dec.decode(op)
            t = Table(cpu)
            cc, head, tail = t.get(d[0], d[1])
            i = dict(valid=True, ea=0, cc=min(cc, 255), head=min(head, 31), tail=min(tail, 3))
        # a MOVEM's register list is one word whatever the transfer size, so
        # its calculate-immediate-address time is always the word row
        sz = 1 if mv else (op >> 6 & 3)
        e = unpack_ea(ea[(i['ea'] << 8) | (sz << 6) | (op & 63)])
        ea_v = e['valid'] and i['ea'] != 0
        model = i['valid'] and (i['ea'] == 0 or e['valid'])

        ea_cc, ea_h, ea_t = (e['cc'], e['head'], e['tail']) if ea_v else (0, 0, 0)
        # 11.6.8: DIVU.L is 78 clocks and DIVS.L 90, and the sign is in the
        # word after the opcode, bit 11
        op_cc = i['cc'] + (12 if (op >> 6) == 0x131 and (snd >> 11) & 1 else 0)
        cc = op_cc + ea_cc - min(i['head'], ea_t)
        head = (ea_h + (i['head'] if e['plus'] else 0)) if ea_v else i['head']

        bcc_b = (op >> 12) == 6 and (op >> 8 & 15) > 1 and (op & 255) not in (0, 255)
        cost = cc - min(head, prev_tail)
        if model and bcc_b:
            cost -= 2
        if not model:
            cost = 2
        if pend and cond:             # the branch before this one was taken
            cost += 2
        pend = model and bcc_b
        total += cost
        prev_tail = i['tail'] if model else 0
        detail.append((op, cost))
    return total, detail


if __name__ == '__main__':
    tr = [tuple(int(x) for x in l.split()) for l in open(sys.argv[1]) if l.strip()]
    total, detail = run(tr)
    print(f'{len(tr)} instructions, {total} clocks, {total/len(tr):.3f} each')
    if '-v' in sys.argv:
        from collections import Counter
        c = Counter((op, cost) for op, cost in detail)
        for (op, cost), n in c.most_common(15):
            print(f'  {op:04X}  {cost:3d} clocks  x{n}')
