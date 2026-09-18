import re, json, sys

SECTS = [
 (1861,'fea','11.6.1 Fetch Effective Address'),
 (2147,'fiea','11.6.2 Fetch Immediate Effective Address'),
 (2482,'cea','11.6.3 Calculate Effective Address'),
 (2790,'ciea','11.6.4 Calculate Immediate Effective Address'),
 (3265,'jea','11.6.5 Jump Effective Address'),
 (3525,'move','11.6.6 MOVE Instruction'),
 (3795,'spmove','11.6.7 Special-Purpose Move'),
 (3986,'arith','11.6.8 Arithmetical/Logical'),
 (4292,'immarith','11.6.9 Immediate Arithmetical/Logical'),
 (4427,'bcd','11.6.10 BCD and Extended'),
 (4534,'single','11.6.11 Single Operand'),
 (4668,'shift','11.6.12 Shift/Rotate'),
 (4810,'bit','11.6.13 Bit Manipulation'),
 (4944,'bitfield','11.6.14 Bit Field Manipulation'),
 (5137,'bcc','11.6.15 Conditional Branch'),
 (5209,'ctrl','11.6.16 Control'),
 (5415,'exc','11.6.17 Exception-Related'),
 (5539,'saverest','11.6.18 Save and Restore'),
 (6262,'END','')
]

L = open('sec11.txt', encoding='utf-8').read().split('\n')

NOISE = re.compile(r'^(MOTOROLA|MC68030 USER.S MANUAL|Instruction Execution Timing|Freescale.*|For More Information.*|Go to:.*|nc\.\.\.|\s*|11-\d+|=====.*|Instruction|Head|Tail|I-Cache Case|No-Cache Case|Operand|Operation|Address Mode|\*.*|\+.*|All timing data.*)$')
CC = re.compile(r'^(\d+)\+?\((\d+)/(\d+)/(\d+)\)\+?$')
NUM = re.compile(r'^(\d+)$')
HEADX = re.compile(r'^(\d+)\+op head$|^(\d+)\(op head\)$|^op head$')

def parse(lo, hi, tag):
    rows, buf, i = [], [], lo
    while i < hi:
        ln = L[i].strip()
        if NOISE.match(ln):
            if ln in ('No-Cache Case','Instruction','Head','Tail','I-Cache Case'): buf = []
            i += 1; continue
        # candidate row: head, tail, cc, ncc
        if i+3 < hi:
            a,b,c,d = (L[i].strip(), L[i+1].strip(), L[i+2].strip(), L[i+3].strip())
            hm = NUM.match(a) or HEADX.match(a)
            if hm and NUM.match(b) and CC.match(c) and CC.match(d):
                rows.append(dict(sect=tag, label=' '.join(buf).strip(),
                                 head=a, tail=int(b),
                                 cc=int(CC.match(c).group(1)), cc_rpw=CC.match(c).groups()[1:],
                                 ncc=int(CC.match(d).group(1)), ncc_rpw=CC.match(d).groups()[1:]))
                buf = []; i += 4; continue
        buf.append(ln)
        if len(buf) > 8: buf = buf[-8:]
        i += 1
    return rows

allrows=[]
for (lo,tag,name),(hi,_,_) in zip(SECTS, SECTS[1:]):
    r = parse(lo-1, hi-1, tag)
    allrows += r
    print(f'{tag:10s} {len(r):4d} rows   {name}')
print('TOTAL', len(allrows))
json.dump(allrows, open('work/timing.json','w'), indent=1)
