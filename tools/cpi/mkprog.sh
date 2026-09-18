#!/bin/sh
# Build a test program: a long unrolled run of one instruction, so the
# measurement is that instruction and nothing else.
#
#   sh mkprog.sh "nop" prog.hex
#   sh mkprog.sh "add.l d1,d0" prog.hex
#
# Needs vasmm68k_mot on PATH (VASM=/path/to/vasmm68k_mot to point at it).
set -e
instr=$1
out=${2:-prog.hex}
n=${3:-256}
vasm=${VASM:-vasmm68k_mot}
tmp=$(mktemp -d)

{
	echo "	section code,code"
	echo "	dc.l	\$00010000"
	echo "	dc.l	start"
	echo "start:"
	echo "	lea	\$8000,a0"
	echo "	lea	\$8100,a1"
	echo "	lea	\$8200,a2"
	echo "	moveq	#1,d0"
	echo "	moveq	#1,d1"
	echo "	moveq	#1,d2"
	echo "loop:"
	i=0
	while [ $i -lt "$n" ]; do echo "	$instr"; i=$((i+1)); done
	echo "	bra.w	loop"
} > "$tmp/p.s"

"$vasm" -m68020 -Fbin -o "$tmp/p.bin" "$tmp/p.s" > "$tmp/log" 2>&1 || { cat "$tmp/log"; exit 1; }
python3 - "$tmp/p.bin" > "$out" <<'PY'
import sys, struct
d = open(sys.argv[1], 'rb').read()
if len(d) % 2: d += b'\0'
for i in range(0, len(d), 2):
    print(struct.unpack('>H', d[i:i+2])[0])
PY
rm -rf "$tmp"
