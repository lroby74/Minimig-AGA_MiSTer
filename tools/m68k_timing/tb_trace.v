`timescale 1ns/1ns
//
// Replay a trace captured from the real TG68K kernel through the cycle model
// and report what it charged, so it can be set against what model.py works out
// from the tables for the same stream. Two implementations of equations 11-1
// and 11-2, one in Verilog and one in Python, fed the same real instructions.
//
module tb_trace;

reg clk = 0, reset = 0;
reg [15:0] opc;
reg        opc_cond = 0, opc_start = 0;
wire       hold;
wire       cpu_ena = ~hold;

cpu_cycles dut (.clk(clk), .reset(reset), .ntsc(1'b0), .ena(1'b1), .speed(2'b00),
                .opc_start(opc_start), .opc(opc), .opc_cond(opc_cond),
                .cpu_ena(cpu_ena), .hold(hold));

always #5 clk = ~clk;

integer fd, r, n, t0, t1, i;
integer o, c;
reg [31:0] ops [0:100000];
reg [31:0] cnd [0:100000];

initial begin
	$readmemh("m68k_cyc_idx.hex", dut.cyc_rom);
	$readmemh("m68k_ea_idx.hex",  dut.ea_rom);

	fd = $fopen("trace.txt", "r");
	if (!fd) begin $display("no trace.txt"); $finish; end
	n = 0;
	r = $fscanf(fd, "%d %d\n", o, c);
	while (r == 2) begin
		ops[n] = o; cnd[n] = c; n = n + 1;
		r = $fscanf(fd, "%d %d\n", o, c);
	end
	$fclose(fd);

	repeat (4) @(negedge clk); reset = 1; repeat (8) @(negedge clk);
	while (hold) @(negedge clk);
	t0 = $time;
	for (i = 0; i < n; i = i + 1) begin
		while (hold) @(negedge clk);
		opc = ops[i][15:0]; opc_cond = cnd[i][0];
		opc_start = 1; @(negedge clk); opc_start = 0;
	end
	while (hold) @(negedge clk);
	t1 = $time;
	$display("%0d instructions, %0.1f clocks, %0.3f each",
	         n, ((t1-t0)/10.0)*902.0/4096.0, ((t1-t0)/10.0)*902.0/4096.0/n);
	$finish;
end
endmodule
