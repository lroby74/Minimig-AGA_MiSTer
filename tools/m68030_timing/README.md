# 68030 instruction timing data

Machine-extracted from section 11 (Instruction Execution Timing) of the
Motorola/Freescale **MC68030 User's Manual**, part 2
(`https://www.nxp.com/docs/en/reference-manual/MC68030UM-P2.pdf`).

    python3 extract.py MC68030UM-P2.pdf > sec11.txt
    python3 parse_tables.py            # writes m68030_timing.csv

`m68030_timing.csv` holds one row per table entry: section, instruction form,
head, tail, instruction-cache-case clocks with its (read/prefetch/write)
breakdown, and the no-cache-case clocks with its own breakdown. 562 rows over
the 18 tables 11.6.1 - 11.6.18.

## The model these numbers feed

Equation 11-1 of the manual, for a stream of instructions with both caches
hitting:

    CC1 + [CC2 - min(H2,T1)] + [CC3 - min(H3,T2)] + ...

CCn is the instruction-cache-case time of instruction n, Hn its head, Tn its
tail. Two consecutive instructions overlap by the lesser of the tail of the
first and the head of the second.

The consequence for this core: the cost of an instruction is not a property of
that instruction alone, it depends on the tail of the one before it. A scalar
clock divider - what the 68020 stock-speed throttle and the first 68030 speed
setting use - cannot express that, which is where the +/-10% per-instruction
spread measured in #233 comes from.

Instructions that take an effective address add the fea / fiea / cea / ciea /
jea time from tables 11.6.1 - 11.6.5, overlapped with the operation by the same
min(head,tail) rule (equation 11-2).

The no-cache-case column assumes no overlap and two-clock bus cycles, so head
and tail do not apply to it.

## Known rough edges in the extraction

The five effective-address tables (fea, fiea, cea, ciea, jea) lay their
addressing-mode names across several lines and several sub-headings, so some
rows in those sections carry a run-together label. The numbers are right; the
labels in those five sections need a pass before they can be mapped onto
addressing modes. The per-instruction tables (11.6.6 - 11.6.18) come out clean.
