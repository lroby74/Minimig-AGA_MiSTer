`timescale 1ns/1ns
//
// The AA display window comparator, at 35ns.
//
// Drives the real Denise with the real Amiga clock generator, sets the display
// window through DIWSTRT/DIWSTOP/DIWHIGH the way a copper list would, and
// times the window edges against the horizontal strobe. Three things have to
// hold: with the two new DIWHIGH bits clear the edges land where they always
// did, each step of those bits moves an edge by exactly one 35ns tick, and
// window_ena stays one 140ns lores pixel behind window.
//
module tb_hwindow;

reg clk = 0, reset_n = 0;
always #17 clk = ~clk;             // 28.375160 MHz, near enough for counting

wire clk7_en, clk7n_en, c1, c3, cck;
wire [9:0] eclk;
amiga_clk clkgen (.clk_28(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en),
                  .c1(c1), .c3(c3), .cck(cck), .eclk(eclk), .reset_n(reset_n));

reg        reset = 1, strhor = 0, aga = 1;
reg  [8:1] reg_address_in = 9'h1fe >> 1;
reg [15:0] data_in = 0;

denise dut (
	.clk(clk), .clk7_en(clk7_en), .c1(c1), .c3(c3), .cck(cck), .reset(reset),
	.strhor(strhor), .reg_address_in(reg_address_in), .data_in(data_in),
	.chip48(48'd0), .data_out(), .blank(1'b0), .red(), .green(), .blue(),
	.a1k(1'b0), .ecs(1'b1), .aga(aga), .hires(), .shres());

// tick counter, zeroed by the strobe, so an edge can be given a time in 35ns ticks
integer tick = 0;
always @(posedge clk) tick <= (strhor && clk7_en) ? 0 : tick + 1;

// edge times, cleared by the same strobe that zeroes the tick counter so that
// nothing outside this block ever writes them
reg  w_d = 0, e_d = 0;
integer t_rise = -1, t_fall = -1, t_ena = -1;
always @(posedge clk) begin
	w_d <= dut.window;
	e_d <= dut.window_ena;
	if (strhor && clk7_en) begin
		t_rise <= -1; t_fall <= -1; t_ena <= -1;
	end else begin
		if ( dut.window && !w_d) t_rise <= tick;
		if (!dut.window &&  w_d) t_fall <= tick;
		if ( dut.window_ena && !e_d) t_ena <= tick;
	end
end

task wr(input [8:0] a, input [15:0] d);
begin
	@(posedge clk); while (!clk7_en) @(posedge clk);
	reg_address_in <= a[8:1]; data_in <= d;
	@(posedge clk); while (!clk7_en) @(posedge clk);
	reg_address_in <= 9'h1fe >> 1; data_in <= 16'd0;
end
endtask

// one scan line: set the window up, strobe, and let the beam run past both edges
task line(input [7:0] hs, input [7:0] he, input use_high, input [1:0] fs, input [1:0] fe);
begin
	wr(9'h08e, {8'h2c, hs});                                  // DIWSTRT
	wr(9'h090, {8'h2c, he});                                  // DIWSTOP
	if (use_high) wr(9'h1e4, 16'h2000 | (fe << 11) | (fs << 3));   // DIWHIGH last
	@(posedge clk); while (!clk7_en) @(posedge clk);
	strhor <= 1; @(posedge clk); while (!clk7_en) @(posedge clk); strhor <= 0;
	repeat (2400) @(posedge clk);
end
endtask

integer i, base_r, base_f, fail = 0;
integer r0, f0;

task chk(input [50*8-1:0] what, input signed [31:0] got, input signed [31:0] want);
begin
	$write("  %-50s %5d  want %5d   %s\n", what, got, want, got === want ? "OK" : "FAIL");
	if (got !== want) fail = fail + 1;
end
endtask

initial begin
	repeat (8) @(posedge clk); reset_n = 1;
	repeat (8) @(posedge clk); reset = 0;
	repeat (8) @(posedge clk);

	// the 140ns behaviour, with no DIWHIGH written at all
	line(8'h81, 8'hc1, 0, 0, 0);   // settle: window comes out of reset unknown
	line(8'h81, 8'hc1, 0, 0, 0);
	base_r = t_rise; base_f = t_fall;
	$display("\nno DIWHIGH, DIWSTRT $81 DIWSTOP $c1: rise %0d, fall %0d, window_ena %0d",
	         base_r, base_f, t_ena);
	chk("window_ena trails window by one lores pixel", t_ena - base_r, 4);

	// moving the start one lores pixel moves the edge four 35ns ticks
	line(8'h82, 8'hc1, 0, 0, 0);
	chk("DIWSTRT +1 lores moves the rise 4 ticks", t_rise - base_r, 4);
	line(8'h81, 8'hc3, 0, 0, 0);
	chk("DIWSTOP +2 lores moves the fall 8 ticks", t_fall - base_f, 8);

	// writing DIWHIGH with both fine fields clear must not move anything
	line(8'h81, 8'hc1, 1, 0, 0);
	chk("DIWHIGH with H1,H0 clear leaves the rise", t_rise, base_r);
	chk("DIWHIGH with H1,H0 clear leaves the fall", t_fall, base_f);

	// and each step of the new bits is one 35ns tick
	for (i = 0; i < 4; i = i + 1) begin
		line(8'h81, 8'hc1, 1, i[1:0], 2'd0);
		chk({"DIWHIGH start H1,H0 = ", 8'h30 + i[7:0], " moves the rise"},
		       t_rise - base_r, i);
	end
	for (i = 0; i < 4; i = i + 1) begin
		line(8'h81, 8'hc1, 1, 2'd0, i[1:0]);
		chk({"DIWHIGH stop  H1,H0 = ", 8'h30 + i[7:0], " moves the fall"},
		       t_fall - base_f, i);
	end

	// both at once, and the pixel they belong to is still the one that matched
	line(8'h81, 8'hc1, 1, 2'd3, 2'd2);
	chk("start +3 and stop +2 together, rise", t_rise - base_r, 3);
	chk("start +3 and stop +2 together, fall", t_fall - base_f, 2);

	// a write to DIWSTRT or DIWSTOP puts DIWHIGH back, as it does on ECS Denise
	wr(9'h1e4, 16'h2000 | (2'd3 << 11) | (2'd3 << 3));
	line(8'h81, 8'hc1, 0, 0, 0);
	chk("DIWSTRT/DIWSTOP write puts DIWHIGH back, rise", t_rise, base_r);
	chk("DIWSTRT/DIWSTOP write puts DIWHIGH back, fall", t_fall, base_f);

	// on ECS Denise the two bits do not exist, so they cannot move anything
	aga = 0;
	line(8'h81, 8'hc1, 1, 2'd3, 2'd3);
	chk("ECS ignores H1,H0 in DIWHIGH, rise", t_rise, base_r);
	chk("ECS ignores H1,H0 in DIWHIGH, fall", t_fall, base_f);
	aga = 1;

	$display("\n%0s", fail ? "FAILURES" : "all cases OK");
	$finish;
end

endmodule
