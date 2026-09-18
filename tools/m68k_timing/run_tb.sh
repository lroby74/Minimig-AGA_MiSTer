#!/bin/sh
# Check the cycle model against the numbers in the Motorola tables.
#
#   sh run_tb.sh
#
# Needs iverilog. Regenerates the ROM images, builds the model with them and
# runs a stream of each instruction form through it, comparing the clocks it
# charges against what section 11 of the MC68030 manual says they cost.
set -e
cd "$(dirname "$0")"
python3 gen_cycle_rom.py 68030 --split
python3 gen_ea_rom.py    68030 --split
mv ../../rtl/tg68k/m68k_cyc_idx.hex ../../rtl/tg68k/m68k_ea_idx.hex .
iverilog -g2005 -I../../rtl -o tb_cycles tb_cycles.v ../../rtl/cpu_cycles.v 2>&1 \
	| grep -v 'SystemVerilog \[size\]' || true
./tb_cycles
rm -f tb_cycles m68k_cyc_idx.hex m68k_ea_idx.hex
