# What the TG68K costs per instruction

The cycle model in `rtl/cpu_cycles.v` can hold the CPU to stretch an
instruction out to what a 68030 would take. It cannot shorten one. So an
instruction costs `max(what the core needs, what the tables say)`, and it is
worth knowing which of the two is binding before trusting the model.

    VASM=/path/to/vasmm68k_mot sh run_cpi.sh

`tb_cpi.vhd` runs the real kernel with memory that answers in the cycle it is
asked, so what comes out is the pipeline on its own with no bus wait in it -
the best the core can do. `mkprog.sh` builds the program: a long unrolled run
of one instruction, so the measurement is that instruction and nothing else.

The two count columns are in different units - the core's are sysclk at
113.5MHz, the 68030's are its own clocks at whatever the OSD selects - so the
last column turns the comparison into the highest 68030 clock the instruction
could be held to: `68030 clocks / core cycles * 113.5`.

    instruction                 TG68K      68030    max MHz
    nop                         1.008          2        225
    add.l d1,d0                 1.008          2        225
    add.l (a0),d0               3.000          5        189
    move.l d1,d0                1.008          2        225
    move.l d1,(a0)              3.000          3        114
    move.l (a0),(a1)            4.992          6        136
    moveq #1,d0                 1.008          2        225
    lsl.l #4,d0                 1.008          4        450
    muls.w d1,d0                1.008         28       3153
    divu.w d1,d0               17.940         44        278
    bra.w *+4                   3.000          6        227
    cmp.l d1,d0                 1.008          2        225
    swap d0                     1.008          4        450
    and.l #1,d0                 3.000          2         76
    tst.l (a0)                  3.000          2         76

The core is faster than the part it is imitating almost everywhere, by a long
way on anything the TG68K does with hardware the 68030 did not have -
`muls.w` is 28 times faster, which is exactly the sort of thing that makes
timing-sensitive code misbehave without the model. Two forms are slower than
silicon: an immediate operand and `tst.l (a0)` both cost a cycle more than a
68030 clock, which caps them at 76MHz.

76MHz is the binding number, and every clock the core offers - 25, 40, 50 - is
below it. The model has margin at all three, so lowering the core's cycles per
instruction would buy nothing for fidelity. It would only matter if a faster
68030 than 50MHz were wanted.

Memory here answers instantly, so these are upper bounds on the core. Real
SDRAM and cache misses add cycles on top, and those come out of the same
margin.

## Checking the model against a real instruction stream

    VASM=/path/to/vasmm68k_mot sh run_trace.sh

`run_cpi.sh` above measures the core. This measures the model, and it does it
on real instructions rather than on pulses made up by a testbench.

`mixed.s` is a small loop of ordinary work - a load, an add, a shift, a store,
an immediate to memory, two conditional branches, a multiply. It runs through
the real TG68K kernel, and every instruction the kernel starts is recorded
along with the outcome of the branch before it, which is what the model sees on
`opc_cond`. That stream is then charged two ways:

    rtl    : 1000 instructions, 5633.5 clocks, 5.634 each
    python : 1000 instructions, 5634 clocks, 5.634 each

`rtl` is `cpu_cycles.v` doing it in hardware. `python` is `model.py`, which
works equations 11-1 and 11-2 from the same tables in a few lines of Python.
They are independent implementations, so agreeing is evidence and disagreeing
names a bug. The half clock between them is the fractional rate accumulator,
which carries a remainder the integer model does not.
