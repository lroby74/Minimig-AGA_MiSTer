#!/usr/bin/env python3
"""Extract section 11 (Instruction Execution Timing) of the MC68030 User's Manual.

Source: Motorola/Freescale MC68030UM, part 2, section 11.
        https://www.nxp.com/docs/en/reference-manual/MC68030UM-P2.pdf

  python3 extract.py MC68030UM-P2.pdf > sec11.txt

Then run parse_tables.py to turn sec11.txt into m68030_timing.csv.

The timing model the tables feed (equations 11-1 and 11-2 of the manual):

  instruction-cache case for a stream of instructions
      CC1 + [CC2 - min(H2,T1)] + [CC3 - min(H3,T2)] + ...

  where CCn is the instruction-cache-case time, Hn its head and Tn its tail.
  The overlap between two instructions is the lesser of the tail of the first
  and the head of the second, so a per-instruction cost needs the tail of the
  previous instruction - a scalar clock divider cannot express this.

  Instructions that take an effective address add the fea/fiea/cea/ciea/jea
  time from tables 11.6.1 - 11.6.5, and those are overlapped with the
  operation by the same min(head,tail) rule (equation 11-2).

  The no-cache-case column assumes no overlap and two-clock bus cycles, so
  head and tail do not apply to it.
"""
import sys
import pymupdf

def main(path):
    doc = pymupdf.open(path)
    first = next(i for i in range(doc.page_count)
                 if 'SECTION 11' in doc[i].get_text() and 'INSTRUCTION EXECUTION TIMING' in doc[i].get_text())
    out = []
    for i in range(first, doc.page_count):
        text = doc[i].get_text("text")
        if i > first and 'SECTION 12' in text:
            break
        out.append(f"\n===== PDFPAGE {i} =====\n" + text)
    sys.stdout.write(''.join(out))

if __name__ == '__main__':
    main(sys.argv[1])
