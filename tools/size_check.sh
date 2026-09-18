#!/bin/sh
# Rough Cyclone V cost of a module, to watch as the core grows.
#
#   sh tools/size_check.sh rtl/cpu_cycles.v [top]
#
# Logic comes from a Yosys ALM mapping: an order of magnitude and a trend, not
# the fitter's answer. Memory is counted from the .mif headers instead, because
# Yosys does not read them and would optimise an uninitialised ROM away.
#
# The DE10-Nano's 5CSEBA6 has 41910 ALMs, 553 M10K blocks and 112 DSPs.
set -e
cd "$(dirname "$0")/.."
f=$1
top=${2:-$(basename "$f" .v)}

echo "== logic ($top) =="
yosys -p "read_verilog -I rtl -I rtl/tg68k $f; hierarchy -top $top; synth_intel_alm -family cyclonev -top $top; stat" 2>&1 | awk '
	/Printing statistics/ { delete a }
	/MISTRAL_/            { a[$1] += $2 }
	END {
		alut = 0
		for (k in a) if (k ~ /ALUT/) alut += a[k]
		printf "  ALUTs %d  (about %d ALMs)\n", alut, int((alut + 1) / 2)
		printf "  FFs   %d\n", a["MISTRAL_FF"] + 0
		dsp = a["MISTRAL_MUL27X27"] + a["MISTRAL_MUL18X18"]
		if (dsp > 0) printf "  DSPs  %d\n", dsp
	}'

echo "== memory declared in $top =="
grep -o 'ram_init_file = "[^"]*"' "$f" | sed 's/.*"\(.*\)"/\1/' | while read -r m; do
	if [ -f "$m" ]; then
		awk -v f="$m" '
			/DEPTH/ { gsub(/[^0-9]/, ""); d = $0 }
			/WIDTH/ { gsub(/[^0-9]/, ""); w = $0 }
			END { b = d * w
			      printf "  %-34s %5d x %2d = %7d bit -> %3d M10K\n", f, d, w, b, int((b + 10239) / 10240) }
		' "$m"
	else
		echo "  $m  MISSING"
	fi
done
