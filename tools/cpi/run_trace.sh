#!/bin/sh
# End to end check of the cycle model.
#
#   VASM=/path/to/vasmm68k_mot sh run_trace.sh [program.s]
#
# Runs a real program through the real TG68K kernel, records every instruction
# it starts along with the outcome of the branch before it, then charges that
# stream two ways: through rtl/cpu_cycles.v, and through model.py, which works
# the same equations in Python from the same tables. The two are independent
# implementations, so agreement is evidence and disagreement names a bug.
#
# Needs ghdl, iverilog and vasmm68k_mot.
set -e
cd "$(dirname "$0")"
prog=${1:-mixed.s}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

vasm=${VASM:-vasmm68k_mot}
"$vasm" -m68020 -Fbin -o "$W/p.bin" "$prog" > /dev/null
python3 -c "
import struct, sys
d = open('$W/p.bin','rb').read()
if len(d) % 2: d += b'\0'
print('\n'.join(str(struct.unpack('>H', d[i:i+2])[0]) for i in range(0, len(d), 2)))
" > "$W/p.hex"

ghdl -a --workdir="$W" --std=93c -fsynopsys -fexplicit -frelaxed \
	../../rtl/tg68k/TG68K_Pack.vhd ../../rtl/tg68k/TG68K_ALU.vhd \
	../../rtl/tg68k/TG68KdotC_Kernel.vhd tb_cpi.vhd
ghdl -e --workdir="$W" --std=93c -fsynopsys -fexplicit -frelaxed tb_cpi
( cd "$W" && ghdl -r --workdir=. --std=93c -fsynopsys -fexplicit -frelaxed tb_cpi \
	-gPROG=p.hex -gWARMUP=100 -gCOUNT=1000 -gTRACE=trace.txt >/dev/null 2>&1 ) || true

cd ../m68k_timing
python3 gen_cycle_rom.py 68030 --split 2>/dev/null
python3 gen_ea_rom.py    68030 --split 2>/dev/null
mv ../../rtl/tg68k/m68k_cyc_idx.hex ../../rtl/tg68k/m68k_ea_idx.hex .
cp "$W/trace.txt" .
iverilog -g2005 -I../../rtl -o "$W/tb_trace" tb_trace.v ../../rtl/cpu_cycles.v 2>&1 \
	| grep -v 'SystemVerilog \[size\]' || true
printf 'rtl    : '; "$W/tb_trace" | head -1
printf 'python : '; python3 model.py trace.txt 2>/dev/null
rm -f trace.txt m68k_cyc_idx.hex m68k_ea_idx.hex
