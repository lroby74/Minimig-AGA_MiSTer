#!/usr/bin/env python3
"""Parse section 8 (Instruction Execution Timing) of the MC68020/EC020 User's Manual.

  python3 extract.py MC68020UM.pdf > sec8_020.txt      (auto-detects the section)
  python3 parse_68020.py sec8_020.txt > m68020_timing.csv

The 68020 tables carry three columns - best case, cache case and worst case -
instead of the 68030's head/tail pair. They express the same overlap: the best
case is the fully overlapped time, so the overlap an instruction can absorb is
cache_case - best_case (section 8.1.4 of the manual).
"""
import re, sys, csv

SECTS = [('8.2.1','fea'),('8.2.2','fiea'),('8.2.3','cea'),('8.2.4','ciea'),('8.2.5','jea'),
         ('8.2.6','move'),('8.2.7','spmove'),('8.2.8','arith'),('8.2.9','immarith'),
         ('8.2.10','bcd'),('8.2.11','single'),('8.2.12','shift'),('8.2.13','bit'),
         ('8.2.14','bitfield'),('8.2.15','bcc'),('8.2.16','ctrl'),('8.2.17','exc'),
         ('8.2.18','saverest')]

CC = re.compile(r'^(\d+)\+?\((\d+)/(\d+)/(\d+)\)\+?$')
NOISE = re.compile(r'^(MOTOROLA|M68020 USER.S MANUAL|8-\d+|=====.*|\s*|Instruction|Best Case|'
                   r'Cache Case|Worst Case|Address Mode|Operand|Instruction Timings.*|\*+|\++|#+)$')

def main(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    # section start line numbers
    starts = []
    for num, tag in SECTS:
        for i, l in enumerate(lines):
            if l.strip().startswith(num + ' '):
                starts.append((i, tag)); break
    starts.append((len(lines), 'END'))

    w = csv.writer(sys.stdout)
    w.writerow(['section','instruction','best','best_r','best_p','best_w',
                'cache','cache_r','cache_p','cache_w','worst','worst_r','worst_p','worst_w'])
    total = 0
    for (lo, tag), (hi, _) in zip(starts, starts[1:]):
        buf, i = [], lo
        while i < hi:
            ln = lines[i].strip()
            if NOISE.match(ln):
                if ln in ('Worst Case','Instruction','Best Case','Cache Case'): buf = []
                i += 1; continue
            if i + 2 < hi:
                a, b, c = lines[i].strip(), lines[i+1].strip(), lines[i+2].strip()
                if CC.match(a) and CC.match(b) and CC.match(c):
                    w.writerow([tag, ' '.join(buf).strip(),
                                *CC.match(a).groups(), *CC.match(b).groups(), *CC.match(c).groups()])
                    total += 1; buf = []; i += 3; continue
            buf.append(ln)
            if len(buf) > 6: buf = buf[-6:]
            i += 1
    print(f'# {total} rows', file=sys.stderr)

if __name__ == '__main__':
    main(sys.argv[1])
