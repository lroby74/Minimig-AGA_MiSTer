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

## Cost

Whole Denise, Yosys ALM mapping for Cyclone V, before and after:

    old  ALUTs 4766 (~2383 ALM)  FFs 8158
    new  ALUTs 4780 (~2390 ALM)  FFs 8184

Seven ALMs and twenty-six flip-flops, on a device with 41910.
