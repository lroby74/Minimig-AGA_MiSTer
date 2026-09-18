# 68020 and 68030 instruction timing data

Machine-extracted from section 11 (Instruction Execution Timing) of the
Motorola/Freescale **MC68030 User's Manual**, part 2
(`https://www.nxp.com/docs/en/reference-manual/MC68030UM-P2.pdf`).

    python3 extract.py MC68030UM-P2.pdf > sec11.txt
    python3 parse_68030.py                       # writes m68030_timing.csv

    python3 extract.py MC68020UM.pdf > sec8.txt
    python3 parse_68020.py sec8.txt > m68020_timing.csv

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

**The instruction ROM** is indexed by `{opcode[15:6], opcode[5:3]}` - 8192
entries of 20 bits, 16 M10K. Those thirteen bits are what the timing turns on:
`opcode[2:0]` is always a register number, except through mode 7 where it picks
the addressing mode, and that goes to the effective-address ROM instead.

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

### Coverage today

| ROM | state |
|---|---|
| 68030 instructions | 7601 of 8192 slots on a table row (92.8%), no unresolved rows |
| 68030 effective addresses | fea and the transcribed cea and jea rows resolve; ciea and part of jea still open |
| 68020 instructions | 58%: the 68020 manual names the same forms differently and its MOVE table is a matrix |

### What is still open

* **ciea, and the rest of jea.** The five effective-address tables are laid out
  in the PDF in a way the text extraction interleaves wrongly. cea and the
  first page of jea are transcribed from the page images into `gen_ea_rom.py`
  with the page cited; ciea and jea's continuation need the same treatment.
* **The 68020 label aliases.** Its tables call the same form by another name -
  `ADD Rn,Dn` is `ADD EA,Dn` there, `MULU.W` is `MUL.W`, `TST Dn`/`TST Mem` is
  one `TST EA` row, the shifts are spelled out per direction. A per-CPU alias
  map closes this.
* **The 68020 MOVE table** is a 414-cell source-by-destination matrix. A
  line-based parse cannot read it; it needs a coordinate-aware pass.
* **MOVEM** costs 4+2n clocks with n in the extension word, and **DIVS.L vs
  DIVU.L** is decided by the extension word too. Neither is in the ROM index.
  MOVEM is left to the fallback; a signed long divide is charged 12 clocks light.
* **Bcc** is charged as taken. Not-taken byte branches are 2 clocks less, and
  whether a branch is taken is not something the ROM can know - the RTL has the
  signal and can correct it.
