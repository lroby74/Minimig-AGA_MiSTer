# AA chipset checks

Testbenches for the AGA work, run against Commodore's own specification rather
than against another implementation. `doc/amiga/aga/SOURCES.md` quotes the
paragraphs each one is built from.

    sh run_tb.sh

The testbench goes first on the iverilog command line so that its `timescale
reaches the modules under it. Several of them carry `#1` delays, and a module
compiled without a timescale gets the default one, where `#1` is a second and
never lands inside a simulation - the registers simply never take their values.

`altsyncram.v` is a simulation stand-in for the Altera primitive that Denise's
colour table instantiates, so the hierarchy elaborates outside Quartus. It is
not in `files.qip`; Quartus uses the real megafunction.

## tb_hwindow - the display window at 35 ns

The AA specification puts two bits below the 140 ns one in every horizontal
comparator. For the display window they live in DIWHIGH: bits 4 and 3 for the
start, bits 12 and 11 for the stop, 70 ns and 35 ns respectively, and they are
cleared again by any write to DIWSTRT or DIWSTOP.

Denise counts `hpos` in 140 ns lores pixels, so the comparator takes the match
where it always took it and then delays it by those two bits - zero to three
35 ns ticks inside the pixel that matched. Written that way nothing moves on
OCS, on ECS, or on any AGA program that leaves the new bits clear, which is
what the first cases check.

Nineteen cases, all of which have to come back OK:

    no DIWHIGH, DIWSTRT $81 DIWSTOP $c1: rise 512, fall 1792, window_ena 516
      window_ena trails window by one lores pixel            4  want     4  OK
      DIWSTRT +1 lores moves the rise 4 ticks                4  want     4  OK
      DIWHIGH with H1,H0 clear leaves the rise             512  want   512  OK
      DIWHIGH start H1,H0 = 3 moves the rise                 3  want     3  OK
      DIWHIGH stop  H1,H0 = 2 moves the fall                 2  want     2  OK
      DIWSTRT/DIWSTOP write puts DIWHIGH back, rise        512  want   512  OK
      ECS ignores H1,H0 in DIWHIGH, rise                   512  want   512  OK

The times are in 35 ns ticks from the horizontal strobe, measured on the real
Denise driven by the real `amiga_clk`, with the window set up through the
register bus the way a copper list would set it up.

`window_ena` is `window` one lores pixel later. That was a clock-enabled
register sampling at 7 MHz, which would have thrown away the 35 ns edge as
soon as it was made; it is now a four-deep shift register at 28 MHz, which is
the same 140 ns and keeps the edge.

## tb_hsprite - the sprite start at 35 ns

The same two bits, in SPRxCTL: bit 4 is SH1 at 70 ns and bit 3 is SH0 at 35
ns. Bit 0 is SH2, the 140 ns bit OCS already had, and SPRxPOS carries SH10-SH3
above it - so its own lowest bit is 280 ns, two lores pixels.

The shift register loaded on the 7 MHz enable, so the two new bits had nowhere
to land here either. It now loads on the same match delayed by them, and with
both clear that is the clk7_en load it always was.

Nine cases. The test arms sprite 0 through the register bus, exactly as the
sprite DMA channel would, and times when its data first reaches the serial
output:

    SPR0 at SH10-SH3 $40, SH2 0, no SH1/SH0: data out at tick 516
      SPRxPOS +1 is SH3, 280ns, 8 ticks                      8  want     8  OK
      SPRxCTL SH2 is 140ns, 4 ticks                          4  want     4  OK
      SPRxCTL SH1,SH0 = 3 moves the start                    3  want     3  OK
      SH3 + SH2 + SH1 + SH0 together                        15  want    15  OK
      ECS ignores SH1,SH0 in SPRxCTL                       516  want   516  OK

The whole ladder, 280 down to 35 ns, comes out in the right proportion, which
is the thing worth checking: each bit is worth half the one above it.

## tb_bpldma - the bitplane DMA register delays

Two rules from `TODO`, quoted there from Toni Wilen:

> Writing to BPLxPT when exactly next cycle has DMA to matching BPLxDAT: write
> goes nowhere.

> Writing to BPLxMOD when exactly next cycle is matching BPLxDAT write and it
> also does modulo add, _old_ modulo value is used! (Write to BPLxMOD is still
> accepted, next time BPLxMOD value is needed it is used normally)

The DMA channel has the address a cycle ahead of the fetch, so it reads the old
pointer and writes back the old one plus the increment, and the write never
reaches the register. The bus write now waits a cycle, and a DMA cycle to the
same plane in the meantime takes it with it. The banks keep their single write
port, so this costs almost nothing.

The modulo rule was already there - `bpl1mod_bscan` is the modulo one cycle
late and the adder uses that - but nothing checked it. Now something does.

The test runs one bitplane in lores with the display DMA going and drops a
write at a chosen point relative to a known fetch. Nine cases:

    plain line: fetch at $89 08400, at $99 08401, at $a9 08402
      write one cycle before the fetch is swallowed  008401  want 008401  OK
      and the fetch after it carries on regardless   008402  want 008402  OK
      write two cycles before the fetch takes        009000  want 009000  OK
      write in a free cycle takes                    009000  want 009000  OK
      BPL1MOD 4 written early adds two words         008416  want 008416  OK
      BPL1MOD 8 one cycle before the add is not used 008416  want 008416  OK
      and it is used on the line after               008418  want 008418  OK

The last three are the rule in one line each: the old value is used, and the
write was still accepted.

## tb_hblank - the programmable blanking at 35 ns

HBSTRT and HBSTOP hold an eleven bit position and the AGA register reference
gives the layout outright: bits 7-0 are the 280 ns field ECS already had, bit
10 is 140 ns, bits 9 and 8 are 70 ns and 35 ns. Minimig read only bits 7-0 and
shifted them up by one, which threw away all three of the new ones - there was
a `TODO fix this` on the line. The same delayed-match treatment applies, and
these only do anything with VARBEAMEN set in BEAMCON0.

Fourteen cases, the whole ladder again:

    HBSTRT $40 HBSTOP $60, no fine bits: blank on at tick 512, off at 768
      HBSTRT +1 is 280ns, 8 ticks                            8  want     8  OK
      HBSTRT bit 10 is 140ns, 4 ticks                        4  want     4  OK
      HBSTRT bits 9,8 = 3 move the start                     3  want     3  OK
      HBSTOP bits 9,8 = 2 move the end                       2  want     2  OK
      bit 10 and bits 9,8 together                           7  want     7  OK
      ECS ignores bits 10-8, start                         512  want   512  OK

## Cost

Yosys ALM mapping for Cyclone V, as each piece went in.

Whole Denise:

    before          ALUTs 4766 (~2383 ALM)  FFs 8158
    display window  ALUTs 4780 (~2390 ALM)  FFs 8184
    sprites         ALUTs 4792 (~2396 ALM)  FFs 8264

Bitplane DMA:

    before          ALUTs  708 (~ 354 ALM)  FFs  416  MLAB 40
    pointer delay   ALUTs  732 (~ 366 ALM)  FFs  472  MLAB 40

Beam counter:

    before          ALUTs  564 (~ 282 ALM)  FFs  310
    blanking at 35ns ALUTs 580 (~ 290 ALM)  FFs  332

Thirty-three ALMs and a hundred and eighty-two flip-flops for all four, on a
device with 41910 ALMs. The sprite flip-flops are eight sprites' worth. Writing the
pointer banks per plane instead would have cost 273 ALMs and thrown away the
40 distributed-memory blocks they infer, which is why the write waits for the
port rather than getting one of its own.
