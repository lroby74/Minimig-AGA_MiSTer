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

for tb in tb_hwindow; do
	iverilog -g2005-sv -o "$W/$tb" -s $tb \
		$R/denise*.v $R/amiga_clk.v altsyncram.v $tb.v 2>&1 | grep -i error && exit 1
	"$W/$tb"
done
