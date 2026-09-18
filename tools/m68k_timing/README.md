# 68020 and 68030 instruction timing data

Machine-extracted from section 11 (Instruction Execution Timing) of the
Motorola/Freescale **MC68030 User's Manual**, part 2
(`https://www.nxp.com/docs/en/reference-manual/MC68030UM-P2.pdf`).

    python3 extract.py MC68030UM-P2.pdf > sec11.txt
    python3 parse_68030.py                       # writes m68030_timing.csv

    python3 extract.py MC68020UM.pdf > sec8.txt
    python3 parse_68020.py sec8.txt > m68020_timing.csv
    python3 parse_move_020.py MC68020UM.pdf > m68020_move.csv

The 68020 numbers come from section 8 of the **MC68020/MC68EC020 User's
Manual** (`https://www.nxp.com/docs/en/data-sheet/MC68020UM.pdf`), 767 rows
over its 18 tables. Its tables carry three columns - best case, cache case
and worst case - rather than the 68030's head/tail pair, which expresses the
same overlap differently: the best case is the fully overlapped time, so the
overlap an instruction can absorb is cache_case - best_case (section 8.1.4).
The 68EC020 is a 68020 with a 24-bit address bus and the same core timing.

The two parts are not interchangeable. The 68020 has only an instruction
cache; the 68030 adds a data cache, so every form with a memory operand has
different numbers. The 68020 mode and the 68030 mode need their own table.

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

## From tables to ROM images

`decode.py` maps an opcode onto the table row that describes it, and
`gen_cycle_rom.py` / `gen_ea_rom.py` turn the result into M10K images:

    python3 gen_cycle_rom.py 68030 > ../../rtl/tg68k/m68k_cycles_030.mif
    python3 gen_ea_rom.py    68030 > ../../rtl/tg68k/m68k_ea_030.mif

Both report their coverage on stderr and name every row they could not find,
so a gap is visible rather than silent.

**The instruction ROM** is indexed by fourteen bits - `{opcode[15:6], 1,
opcode[2:0]}` through mode 7 and `{opcode[15:6], 0, opcode[5:3]}` otherwise -
16384 entries of 20 bits. `opcode[2:0]` is a register number and never changes
a time, except under mode 7 where it picks the addressing mode and sometimes
the instruction, so mode 7 gets its own half. `collisions()` walks all eight
low values of every slot and reports any that disagree, so that claim is
checked rather than trusted.

    [19] valid  [18:16] ea_class  [15:14] tail  [13:9] head  [8:1] cc

A form with no table row behind it is emitted with `valid` clear and the RTL
keeps using the averaged divider for it. Nothing in these images is estimated.

**The effective-address ROM** is indexed by
`{ea_class, opcode[7:6], opcode[5:0]}` - 2048 entries of 16 bits, 4 M10K.

    [15] valid  [14:8] cc  [7:3] head  [2:1] tail

The RTL composes the two by equation 11-2:

    cc    = ea_cc + op_cc - min(op_head, ea_tail)
    head  = ea_head (plus op_head where the table says "X + op head")
    tail  = op_tail

and then charges `cc - min(head, tail_of_previous_instruction)` clocks.

### The three things no opcode ROM can hold

MOVEM's register count and the bit that makes a long divide signed are both in
the word *after* the opcode, so nothing indexed by the opcode can carry their
time. The kernel puts that word on `opc_snd`, and `cpu_cycles` reads it one
clock after the start, which is where `sndOPC` has settled.

* **MOVEM** - 11.6.7 gives 8+4n clocks going to registers and 4+2n coming from
  them, head 2 and tail 0 either way, with the calculate-immediate-address time
  on top. That is always the word row, because the register list is one word
  whatever the transfer size. The model counts the bits of the mask.
* **DIVS.L** - 11.6.8 gives DIVU.L 78 clocks and DIVS.L 90, alike in head, tail
  and address class, so the entry carries the 78 and twelve are added when
  extension word bit 11 is set.

A note on the MOVEM row: the table's two footnotes print the 8+4n and 4+2n
formulas under swapped labels. The (r/p/w) column settles it - the 8+4n row
does n reads and no writes, so it is the one that loads registers.

**DBcc** is the third, and it is not in any word of the instruction: 11.6.13
charges a looping iteration 6 clocks and the one the counter runs out on 10,
and which it was depends on the count reaching -1. The kernel decides it in
its `dbcc1` state, where it loops on `exe_condition = '0' and c_out(1) = '1'`,
so `opc_dbx` says when both the condition is false and the counter is spent.
The 6 is charged at the DBcc and the 4 goes on at the next instruction, the
same way the two clocks of a taken byte branch do - neither is known when the
charge has to be made.

### Coverage today

| ROM | state |
|---|---|
| 68030 instructions | 15203 of 16384 slots on a table row (92.8%), no unresolved rows |
| 68030 effective addresses | every row resolves - no gaps |
| 68020 instructions | 12419 of 16384 (75.8%); everything still open is MOVE |
| 68020 MOVE | the whole 23 x 22 matrix, 506 cells, best/cache/worst |

The 1181 slots neither CPU covers are opcodes `decode.py` does not map: the
coprocessor and MMU space, and encodings TG68K does not implement.

### What is still open

* **The full-format addressing modes.** The memory-indirect forms of every
  effective-address table are still on the text extraction rather than
  transcribed. TG68K's support for them is partial anyway.
* Nothing else from section 11 is knowingly wrong. What is left is the
  coverage gap above: opcodes `decode.py` does not map, which are the
  coprocessor and MMU space and encodings TG68K does not implement, and the
  full-format addressing modes in the first bullet.

## In the core

`rtl/cpu_cycles.v` holds the model. `cpu_wrapper` instantiates it and lets it
gate the CPU's clock enable:

    hold = a lookup is in flight, or this instruction has not been paid for

The RTL charges `cc - min(head, tail_of_previous)` clocks per instruction,
which is equation 11-1, and composes the address with the operation by
equation 11-2 before that. Nothing is clamped on the way: after the overlap an
instruction can cost less than two clocks, and the manual says outright that a
net of zero is possible. The two-clock floor applies only to a form with no
table row behind it.

The two ROM reads take three clocks and the CPU is held through them. Those
clocks do not land on top of the instruction: what the rate accumulator earns
during the hold is banked and comes off the charge at the end of it, so over a
stream the lookup is free.

### Memory

The tables repeat heavily - across all 16384 opcode slots there are only **60**
distinct (cc, head, tail, ea class) combinations, and 20 for the effective
addresses. So the memories hold a 6-bit and a 5-bit index and the entries sit
in logic:

| | raw | as index + palette |
|---|---|---|
| instruction | 16384 x 20 = 32 M10K | 16384 x 6 = **10 M10K** |
| effective address | 2048 x 16 = 4 M10K | 2048 x 5 = **1 M10K** |

11 M10K out of the 553 on the DE10-Nano's Cyclone V, plus about eighty logic
cells for the palettes and the arithmetic.

### Checking it

    sh run_tb.sh

Regenerates the images, builds `cpu_cycles` with them, runs a stream of each
instruction form through it and compares the clocks it charges against the
manual. Every case has to come back OK:

    NOP                                  1.999   tables   2.00   OK
    MOVEM.L D0-D7/A0-A6,-(A7) 15 regs   36.001   tables  36.00   OK
    DBcc looping                         6.000   tables   6.00   OK
    DBcc expiring every time             9.992   tables  10.00   OK
    DIVS.L D1,D0                        90.000   tables  90.00   OK
    MULS.W D1,D0                        28.000   tables  28.00   OK
    DIVU.L D1,D0                        78.000   tables  78.00   OK
    ADD.L (A0),D0  (2 + fea 3)           5.000   tables   5.00   OK
    RTS                                  9.000   tables   9.00   OK
    MOVE.L D0,(A0) ; ADD.L A1,D1         2.000   tables   2.00   OK

The last one is the overlap: MOVE.L D0,(A0) has a tail of 1 and ADD.L A1,D1 a
head of 2, so the pair costs 3 + [2 - min(2,1)] = 4 rather than 5. Getting that
wrong shows up as 2.5 clocks each, which is how the two bugs in the first cut
of this were found.

### A correction to the manual

Section 11.5's first worked example gives `SUBA.L D1,A2` a head of 4 and a
cache case of 4, and totals the example at 6 clocks. The table in 11.6.8 gives
`SUBA.L Rn,An` 2/0/2 - the 4 belongs to the `.W` row - so the example totals 4.
The tables are what this implementation follows.


## The 68020 manual as a second opinion

The 68030 is a 68020 with an MMU and a data cache, so the two share their
instruction set and their tables share their shape - but not their numbers.
Comparing the forms that appear in both:

| form | 68030 | 68020 |
|---|---|---|
| `ADD Dn,EA` | 3 | 4 |
| `CLR Mem` | 3 | 4 |
| `ADDQ #x,Mem` | 3 | 4 |
| `RTS` | 9 | 10 |
| `JSR` | 4 | 5 |
| `fea (An)+` | 3 | 4 |
| `ADD EA,Dn` | 2 | 2 |
| `TST` | 2 | 2 |
| `LEA` | 2 | 2 |

Seven of twelve differ: anything with a memory operand is a clock cheaper on
the 68030, which is the data cache the 68020 does not have. So the 68020
numbers cannot stand in for the 68030's, and each mode needs its own table.

What the 68020 manual is good for is checking the 68030's. Page 11-35 prints
the first two rows of the jump table as `Dn` and `An`, which JMP and JSR
cannot take. The 68020's jump table carries the same values in the same order
- 2, 4, 2, 2, 6 - and labels those rows `(An)` and `(d16,An)`. That is what
they are, on the strength of a second document rather than a guess, and it is
how `JSR (A0)` came to be charged 6 clocks instead of falling back to 2.

## Why the 68020 mode is not on these tables

The tables are extracted and complete, and the 68020 mode still runs on the
averaged divider. The reason is one missing column.

Equation 11-1 needs two numbers per instruction: a head, and a tail. The 68030
manual prints both. The 68020 manual prints a best, a cache and a worst case,
and defines the best case as the instruction in cache "and benefiting from
maximum overlap due to other instructions" (section 8.2), so cache minus best
is a head. **There is no tail.** What an instruction leaves for its successor
is never stated anywhere in section 8, and section 8.1.5 shows it is real and
it varies: the same four instructions come out 6/0/9/1 at one alignment and
4/3/6/3 at another.

Nor are the two manuals' heads the same quantity:

    python3 compare_020_030.py

    head: the 68030 head and the 68020 cache-minus-best agree on 76 of 235
          shared forms (32%)
          68030 head reaches 20; 68020 cache-minus-best reaches 6
          the 68030 lets 62 of these forms be absorbed whole; the 68020's best
          case is bounded by what a real predecessor offers, so it never says
          that

    tail: 68030 {0: 519, 1: 32, 2: 11}, 68020 not published

So the 68030's tails cannot be borrowed for the 68020. Charging every 68020
instruction its cache case with nothing taken off is the only reading the
manual supports, and that costs:

    python3 compare_020_030.py trace.txt
    1000 instructions: 5634 clocks with the tails, 5776 without (+2.52%)

2.5% on a mixed stream. But the manual's own Example 3 - two register
operations between two memory MOVEs, cache enabled, no wait states - sums to
15 clocks that way against the 12 Table 8-1 gives it. Amiga code that moves
memory around lives at that end, and 25% is not a faithful 68EC020.

The same tables would also be the wrong tables for a stock A1200. They assume
a 32-bit bus with no wait states; an unexpanded A1200 has 2 MB of chip RAM on
a 16-bit bus, and the chip bus, which Minimig already models, is what decides
the timing there rather than the instruction.

If a tail column for the 68020 ever turns up - a Motorola errata, an
application note, measurements off real silicon - the mode is one generator
run away. Everything else it needs is in `m68020_timing.csv` and
`m68020_move.csv`.

## The 68020 MOVE matrix

The 68030 tabulates MOVE by destination, with one row for a register source
and one for everything else, and leaves the source addressing cost to the
fetch-effective-address table. The 68020 does not: section 8.2.6 is a full
source-by-destination matrix, 23 sources against 22 destinations, and each
cell already contains both effective address calculations. `parse_move_020.py`
reads it off the page coordinates - the text layer keeps the cells but not the
grid - and assigns every cell to the destination whose heading it sits closest
to. All 506 cells resolve in all three cases.

One printing slip: the first page of each case, 8-21, 8-23 and 8-26, prints the
nineteenth source row as `([d16,B],d32)`, where the continuation pages of all
three cases print `([d16,B],I,d32)`. The rows around it run `([B],I)`,
`([B],I,d16)`, `([B],I,d32)`, `([d16,B],I)`, `([d16,B],I,d16)`, _,
`([d32,B],I)`, so the index is dropped in printing on one page rather than
there being a twenty-fourth row. The parser says so where it corrects it.
