#!/bin/sh
# Check the AA chipset work against the behaviour Commodore's specification
# describes. Needs iverilog.
#
#   sh run_tb.sh
#
# altsyncram.v is a simulation stand-in for the Altera primitive Denise's
# colour table instantiates, so the hierarchy elaborates outside Quartus. It
# is not in files.qip.
set -e
cd "$(dirname "$0")"
R=../../rtl
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# The testbench goes first on the command line so its `timescale reaches the
# modules under it: several of them carry #1 delays, and without a timescale
# those are a second long and never land inside a simulation.
for tb in tb_hwindow tb_hsprite tb_bpldma tb_hblank; do
	iverilog -g2005-sv -o "$W/$tb" -s $tb \
		$tb.v $R/denise*.v $R/agnus_bitplanedma.v $R/agnus_beamcounter.v $R/amiga_clk.v altsyncram.v \
		2>&1 | grep -i error && exit 1
	"$W/$tb"
done
