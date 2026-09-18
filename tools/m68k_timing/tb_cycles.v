`timescale 1ns/1ns
module tb_cycles;

reg clk = 0, reset = 0, ntsc = 0, ena = 1;
reg  [1:0] speed = 2'b00;             // 25MHz
reg [15:0] opc;
reg        opc_start = 0;
reg        opc_cond  = 0;
reg [15:0] snd       = 0;   // the word after the opcode
reg        dbx       = 0;   // a DBcc whose counter has run out
wire       hold;
wire       cpu_ena = ~hold;

cpu_cycles dut (.clk(clk), .reset(reset), .ntsc(ntsc), .ena(ena), .speed(speed),
                .opc_start(opc_start), .opc(opc), .opc_cond(opc_cond),
                .opc_snd(snd), .opc_dbx(dbx), .cpu_ena(cpu_ena), .hold(hold));

always #5 clk = ~clk;

integer t0, t1, n;
real RATE; initial RATE = 902.0;

task issue(input [15:0] o);
begin
	while (hold) @(negedge clk);
	opc = o; opc_start = 1; @(negedge clk); opc_start = 0;
end
endtask

task start_run; begin while (hold) @(negedge clk); t0 = $time; n = 0; end endtask
task end_run;   begin while (hold) @(negedge clk); t1 = $time; end endtask

function real clocks; input integer dt; clocks = (dt/10.0) * RATE / 4096.0; endfunction

task report(input [38*8:1] name, input real expect);
	real got;
begin
	got = clocks(t1 - t0) / n;
	$display("%-38s %7.3f clocks/instr   tables %6.2f   %s",
	         name, got, expect, (got > expect-0.05 && got < expect+0.05) ? "OK" : "MISMATCH");
end
endtask

integer i;
initial begin
	$readmemh("m68k_cyc_idx.hex", dut.cyc_rom);
	$readmemh("m68k_ea_idx.hex",  dut.ea_rom);
	repeat (4) @(negedge clk); reset = 1; repeat (8) @(negedge clk);

	start_run; for (i=0;i<500;i=i+1) begin issue(16'h4E71); n=n+1; end end_run;
	report("NOP", 2.0);

	start_run; for (i=0;i<500;i=i+1) begin issue(16'hD289); n=n+1; end end_run;
	report("ADD.L A1,D1", 2.0);

	start_run; for (i=0;i<200;i=i+1) begin issue(16'hC1C1); n=n+1; end end_run;
	report("MULS.W D1,D0", 28.0);

	start_run; for (i=0;i<100;i=i+1) begin issue(16'h4C41); n=n+1; end end_run;
	report("DIVU.L D1,D0", 78.0);

	start_run; for (i=0;i<500;i=i+1) begin issue(16'hD090); n=n+1; end end_run;
	report("ADD.L (A0),D0  (2 + fea 3)", 5.0);

	start_run; for (i=0;i<500;i=i+1) begin issue(16'h4E75); n=n+1; end end_run;
	report("RTS", 9.0);

	// the overlap: MOVE.L D0,(A0) has tail 1, ADD.L A1,D1 has head 2, so the
	// pair costs 3 + [2 - min(2,1)] = 4, not 5.  Equation 11-1 at work.
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h2080); issue(16'hD289); n=n+2; end end_run;
	report("MOVE.L D0,(A0) ; ADD.L A1,D1", 2.0);

	// same two without the overlap, each after a zero-tail instruction
	start_run; for (i=0;i<500;i=i+1) begin issue(16'hD289); issue(16'hD289); n=n+2; end end_run;
	report("ADD.L A1,D1 x2 (no tail)", 2.0);

	// ADDI.L #x,(A0): the operation is 3/0/1 and the immediate fetch with an
	// (An) destination is 4/1/0, so composed it is 7 with head 1 and tail 1,
	// and back to back each one absorbs 1 of the previous tail: 6 apiece.
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h0690); n=n+1; end end_run;
	report("ADDI.L #x,(A0)  (3 + fiea 4)", 6.0);

	// JSR (A0): the operation is 4/0/0 and the jump address is 2 with a head
	// that takes in the operation's, so composed it is 6 with head 2.
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h4E90); n=n+1; end end_run;
	report("JSR (A0)  (4 + jea 2)", 6.0);

	// Bcc.B: 4 clocks when not taken, 6 when taken. opc_cond carries the
	// outcome of the instruction before, so it is set for the taken case.
	opc_cond = 0;
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h6604); n=n+1; end end_run;
	report("Bcc.B not taken", 4.0);

	opc_cond = 1;
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h6604); n=n+1; end end_run;
	report("Bcc.B taken", 6.0);

	opc_cond = 0;
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h6600); n=n+1; end end_run;
	report("Bcc.W (6 either way)", 6.0);

	// MOVEM takes its register count from the word after the opcode, so the
	// ROM cannot hold its time and the model counts the mask instead.
	// MOVEM.L D0-D7/A0-A6,-(A7): fifteen registers, 4+2n = 34, and the
	// calculate-immediate-address time for -(An) is 2 with head 2, which the
	// operation's own head is added to - 36, and tail 0 leaves the next one
	// nothing to absorb.
	snd = 16'hFFFE;
	start_run; for (i=0;i<200;i=i+1) begin issue(16'h48E7); n=n+1; end end_run;
	report("MOVEM.L D0-D7/A0-A6,-(A7)  15 regs", 36.0);

	// the other direction is 8+4n, and (An)+ costs 4: 68 + 4
	snd = 16'h7FFF;
	start_run; for (i=0;i<200;i=i+1) begin issue(16'h4CDF); n=n+1; end end_run;
	report("MOVEM.L (A7)+,D0-D7/A0-A6  15 regs", 72.0);

	// and a short one, to show n is read and not assumed: 4+2*2 = 8, (An) is 2
	snd = 16'h0003;
	start_run; for (i=0;i<200;i=i+1) begin issue(16'h4890); n=n+1; end end_run;
	report("MOVEM.W D0/D1,(A0)  2 regs", 10.0);

	// DBcc is 6 clocks while the loop runs and 10 on the iteration the counter
	// runs out on. Which it was is not known when the charge is made, so the 6
	// is charged and the 4 goes on at the next instruction, the way the two
	// clocks of a taken byte branch do.
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h51C8); n=n+1; end end_run;
	report("DBcc looping", 6.0);

	// every iteration expiring is not a real loop, but it is the arithmetic:
	// each one costs its own 6 plus the 4 the one before it ran out by
	start_run;
	for (i=0;i<500;i=i+1) begin
		issue(16'h51C8); n=n+1;
		dbx = 1; @(negedge clk); dbx = 0;
	end
	end_run;
	report("DBcc expiring every time", 10.0);

	// the sign of a long divide is in that same word, bit 11: 78 becomes 90
	snd = 16'h0800;
	start_run; for (i=0;i<100;i=i+1) begin issue(16'h4C41); n=n+1; end end_run;
	report("DIVS.L D1,D0", 90.0);
	snd = 16'h0000;

	// The indexed addressing modes come in two shapes and only the extension
	// word says which. Brief format first, the one the ROM holds: ADD EA,Dn is
	// 2 clocks and fea (d8,An,Xn) is 6 with a tail of 2 the operation's head of
	// 0 cannot take, so 8.
	snd = 16'h0000;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L (d8,A0,Xn),D0  brief", 8.0);

	// full format, no base displacement and no indirection: 11.6.1 gives that
	// 6 as well, so the same 8 - the shapes only part company further down
	snd = 16'h0110;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L ([B]-less full format),D0", 8.0);

	// a word base displacement is 8, a long one 12
	snd = 16'h0120;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L (d16,B),D0", 10.0);
	snd = 16'h0130;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L (d32,B),D0", 14.0);

	// memory indirect: 10 with no base displacement, 12 with a word one, and
	// an outer displacement puts two on top whatever its size
	snd = 16'h0111;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L ([B],I),D0", 12.0);
	snd = 16'h0121;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L ([d16,B],I),D0", 14.0);
	snd = 16'h0133;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hD0B0); n=n+1; end end_run;
	report("ADD.L ([d32,B],I,d32),D0", 20.0);

	// the jump table has its own numbers: JSR is 4 and jea full format 18
	snd = 16'h0133;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'h4EB0); n=n+1; end end_run;
	report("JSR ([d32,B],I,d32)", 22.0);

	// and the calculate table's plain (B) is the one row of the three that
	// differs: head 6, and it takes in the operation's head as well
	snd = 16'h0110;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'h41F0); n=n+1; end end_run;
	report("LEA (B),A0", 8.0);
	snd = 16'h0111;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'h41F0); n=n+1; end end_run;
	report("LEA ([B],I),A0", 12.0);

	// a bit field instruction puts its own word in that slot, so bit 8 of it
	// means nothing about the address and the brief format entry stands
	snd = 16'h0000;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hE8F0); n=n+1; end end_run;
	report("BFTST (d8,A0,Xn) ext bit 8 clear", 14.0);
	snd = 16'h0133;
	start_run; for (i=0;i<300;i=i+1) begin issue(16'hE8F0); n=n+1; end end_run;
	report("BFTST (d8,A0,Xn) ext bit 8 set", 14.0);
	snd = 16'h0000;

	speed = 2'b10; RATE = 1804.0;       // 50MHz
	start_run; for (i=0;i<500;i=i+1) begin issue(16'h4E71); n=n+1; end end_run;
	report("NOP at 50MHz", 2.0);

	$finish;
end
endmodule
