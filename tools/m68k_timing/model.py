#!/usr/bin/env python3
"""Work out what a stream of instructions costs, from the tables alone.

  python3 model.py trace.txt

The trace is one line per instruction: the opcode, and the condition code of
the instruction before it, which is what the RTL sees on opc_cond. This applies
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


def run(trace, cpu='68030'):
    ins, ea = entries(cpu)
    prev_tail = 0
    total = 0
    pend = False                      # a byte branch is waiting on its outcome
    detail = []
    for n, (op, cond) in enumerate(trace):
        i = unpack_ins(ins[index(op)])
        if op & 0xFFF8 == 0x4E70:     # 4E70-4E77 has its own eight entries
            d = dec.decode(op)
            t = Table(cpu)
            cc, head, tail = t.get(d[0], d[1])
            i = dict(valid=True, ea=0, cc=min(cc, 255), head=min(head, 31), tail=min(tail, 3))
        e = unpack_ea(ea[(i['ea'] << 8) | ((op >> 6 & 3) << 6) | (op & 63)])
        ea_v = e['valid'] and i['ea'] != 0
        model = i['valid'] and (i['ea'] == 0 or e['valid'])

        ea_cc, ea_h, ea_t = (e['cc'], e['head'], e['tail']) if ea_v else (0, 0, 0)
        cc = i['cc'] + ea_cc - min(i['head'], ea_t)
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
