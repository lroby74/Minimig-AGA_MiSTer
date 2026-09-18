# AA chipset checks

Testbenches for the AGA work, run against Commodore's own specification rather
than against another implementation. `doc/amiga/aga/SOURCES.md` quotes the
paragraphs each one is built from.

    sh run_tb.sh

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

## Cost

Whole Denise, Yosys ALM mapping for Cyclone V, as the two went in:

    before          ALUTs 4766 (~2383 ALM)  FFs 8158
    display window  ALUTs 4780 (~2390 ALM)  FFs 8184
    sprites         ALUTs 4792 (~2396 ALM)  FFs 8264

Thirteen ALMs and a hundred and six flip-flops for both, on a device with
41910 ALMs. The sprite flip-flops are eight sprites' worth.
