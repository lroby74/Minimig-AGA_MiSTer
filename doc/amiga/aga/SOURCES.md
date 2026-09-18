# Reference documents

What each document is authoritative for, and where it came from. Nothing here
is a rewrite of somebody's emulator: these are the chip vendors' own papers,
plus the one piece of community documentation that fills a gap Commodore left.

## CPU timing

| Document | Covers | URL |
|---|---|---|
| MC68020/MC68EC020 User's Manual, section 8 | 68020 and 68EC020 instruction execution timing | https://www.nxp.com/docs/en/data-sheet/MC68020UM.pdf |
| MC68030 User's Manual part 2, section 11 | 68030 instruction execution timing | https://www.nxp.com/docs/en/reference-manual/MC68030UM-P2.pdf |

Extracted into `tools/m68k_timing/` as CSV, with the extractor and parsers so
they can be regenerated and checked against the manuals.

## Chipset

| Document | Covers | URL |
|---|---|---|
| Commodore AA chipset specification | AGA-specific behaviour, straight from Commodore | https://www.valoroso.it/file-share/documenti-manuali/Commodore-Amiga-AA-chipset-specification.pdf |
| Amiga Hardware Reference Manual, 3rd edition | DMA time slot allocation, blitter, copper, OCS/ECS baseline | https://archive.org/details/amiga-hardware-reference-manual-3rd-edition |
| AGA coding reference | Register bit layouts as programmers use them, fills gaps the AA spec leaves implicit | https://jvaltane.kapsi.fi/amiga/howtocode/aga.html |

Two copies of the AA specification are OCR'd here; both are scans with no text
layer, so check anything surprising against a scan.

* `AA_chipset_spec.txt` - the copy hosted at the URL above.
* `AA_chipset_spec_rev_19910508.txt` - the 8 May 1991 revision, carrying
  R. Raible's editing and Spence's handwritten corrections. The two run 90%
  word-identical; this one has the fuller register list and the bitplane
  scroll paragraph quoted below.

Commodore's 1991 confidentiality notice is on the title page. The company has
been gone since 1994 and the document has circulated publicly for decades; it
is kept here as the reference for a hardware-compatible implementation.

`AHRM_dma_time_slots.txt` is the slot budget prose. The per-slot chart is
figure 6-9 and is a scanned diagram, so it has to be read from the scan.

## What the AA specification settles

Two of the open AGA items in `TODO` are specified outright by Commodore.

**Horizontal comparators at 35 ns.** From the AA specification, section
"Horizontal Comparators":

> All programmable comparators with the exception of VHPOSW have 35nSec
> resolution: DIWHIGH, HBSTRT, HBSTOP, SPRCTL, BPLCON1. BPLCON1 has additional
> high-order bits as well. Note that horizontal bit position representing
> 140nSec resolution has been changed to 3rd least significant bit, where
> before it used to be a field's LSB. For example, bit 00 in BPLCON1 used to be
> named PF1H0 and now it's called PF1H2.

So the ECS scroll field did not grow at the top, it grew at the bottom: what
was the LSB is now the 140 ns bit, and two finer bits sit below it. The coding
reference places those two in BPLCON1 bits 8 and 9 for playfield 1 and bits 12
and 13 for playfield 2, with bits 10-11 and 14-15 extending the range to 64
lo-res pixels. The two views agree.

The register that carries those two bits for the display window is DIWHIGH,
and the specification gives its layout outright:

> DIWHIGH p 1E4 W AD Display Window upper bits for start,stop
>
>     Bit# 15 14 13  12 11 10 09 08   07 06 05  04 03 02 01 00
>           x  x H10 H1 H0 V10 V9 V8   x  x H10 H1 H0 V10 V9 V8
>              (stop)                     (start)
>
> H1 and H0 values define 70nS and 35nS increments respectively, and are new
> LISA bits.
>
> NOTE: In all 3 display window registers, horizontal bit positions have been
> renamed to reflect HIRES pixel increments, e.g. what used be called H0 is
> now referred to as H2.

and states the interlock that goes with it:

> DIWHIGH is reset by writes to DIWSTRT or DIWSTOP. This interlock is
> inherited from ECS Denise.

For sprites the same two bits are in SPRxCTL, bit 04 SH1 at 70 ns and bit 03
SH0 at 35 ns, with bit 00 SH2 the 140 ns bit that ECS already had.

**Sprite resolution.** BPLCON3 bits 6-7 set it independently of the bitplane
resolution: 00 ECS default, 01 lo-res 140 ns, 10 hi-res 70 ns, 11 super-hires
35 ns. The AA specification also states sprites can now be positioned at 35 ns
and are available attached in all resolutions.


**Bitplane scroll.** The `TODO` asks whether the AGA bitplane shifter is 64
bits plus a super-hires stage. The AA specification answers it directly:

> BPLCON1 now contains an 8 bit scroll value for each of the playfields.
> Granularity of scroll now extends down to 35nSec (1 SHRES pixel), and scroll
> can delay playfield thru 32 bus cycles. Bits BPAGEM and BPL32 in new
> register FMODE control size of bitplane fetch.

Eight bits of scroll per playfield, 35 ns granularity, and a delay reaching 32
bus cycles - which is the number the shifter has to be able to hold.
