#!/bin/sh
# What the TG68K pipeline costs per instruction, against what a 68030 costs.
#
#   sh run_cpi.sh
#
# Memory answers in the cycle it is asked, so this is the pipeline on its own,
# with no bus wait in it - the best the core can do. The cycle model can hold
# the CPU to stretch an instruction out to the 68030's time but cannot shorten
# one, so wherever this column is above the 68030's, that instruction cannot
# reach the selected clock and the core is what sets the pace.
#
# Needs ghdl, and vasmm68k_mot (VASM=... to point at it).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

ghdl -a --workdir="$W" --std=93c -fsynopsys -fexplicit -frelaxed \
	../../rtl/tg68k/TG68K_Pack.vhd ../../rtl/tg68k/TG68K_ALU.vhd \
	../../rtl/tg68k/TG68KdotC_Kernel.vhd tb_cpi.vhd
ghdl -e --workdir="$W" --std=93c -fsynopsys -fexplicit -frelaxed tb_cpi

# The two columns are in different units: the core's are sysclk at 113.5MHz,
# the 68030's are its own clocks at whatever the OSD selects. What matters is
# whether the core can finish inside the budget, so the last column turns that
# into the highest 68030 clock this instruction could be held to:
#
#     max MHz = 68030 clocks / core cycles * 113.5
#
# Anything above 50 has margin at every setting the core offers.
printf '%-22s %10s %10s %10s\n' instruction "TG68K" "68030" "max MHz"
while IFS='|' read -r instr want; do
	[ -z "$instr" ] && continue
	sh mkprog.sh "$instr" "$W/p.hex" 256
	got=$(cd "$W" && ghdl -r --workdir=. --std=93c -fsynopsys -fexplicit -frelaxed \
		tb_cpi -gPROG=p.hex 2>/dev/null | sed -n 's/.*cycles\/instruction *//p')
	printf '%-22s %10s %10s %10s\n' "$instr" "$got" "$want" \
		"$(awk -v g="$got" -v w="$want" 'BEGIN{printf "%.0f", w/g*113.5}')"
done <<'LIST'
nop|2
add.l d1,d0|2
add.l (a0),d0|5
move.l d1,d0|2
move.l d1,(a0)|3
move.l (a0),(a1)|6
moveq #1,d0|2
lsl.l #4,d0|4
muls.w d1,d0|28
divu.w d1,d0|44
bra.w *+4|6
cmp.l d1,d0|2
swap d0|4
and.l #1,d0|2
tst.l (a0)|2
LIST
