`timescale 1ns/1ns
//
// The AA programmable horizontal blanking, at 35ns.
//
// HBSTRT and HBSTOP hold an eleven bit position: bits 7-0 are the 280ns field
// ECS already had, bit 10 is 140ns, and bits 9 and 8 are 70ns and 35ns - the
// three that AA added. (AGA register reference, quoted in
// doc/amiga/aga/SOURCES.md.) The beam counter compares at 140ns, so the match
// is taken there and delayed by the bottom two.
//
// These only do anything with VARBEAMEN set in BEAMCON0, which is what this
// sets up before timing the blanking edges against the start of the line.
//
module tb_hblank;

reg clk = 0, reset_n = 0;
always #17 clk = ~clk;

wire clk7_en, clk7n_en, c1, c3, cck;
wire [9:0] eclk;
amiga_clk clkgen (.clk_28(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en),
                  .c1(c1), .c3(c3), .cck(cck), .eclk(eclk), .reset_n(reset_n));

reg        reset = 1, aga = 1;
reg  [8:1] ra = 9'h1fe >> 1;
reg [15:0] di = 0;

wire [8:0] hpos;
wire [10:0] vpos;
wire hblank, vblank;

agnus_beamcounter dut (
	.clk(clk), .clk7_en(clk7_en), .reset(reset), .cck(cck), .ntsc(1'b0),
	.aga(aga), .ecs(1'b1), .a1k(1'b0), .data_in(di), .data_out(),
	.reg_address_in(ra), .hpos(hpos), .vpos(vpos), ._hsync(), ._vsync(),
	.field1(), .lace(), ._csync(), .hblank(hblank), .vblank(vblank),
	.vbl(), .vblend(), .eol(), .eof(), .vbl_int(), .htotal_out(),
	.harddis_out(), .varbeamen_out());

// 35ns ticks since the start of the line
integer tick = 0;
always @(posedge clk) tick <= (clk7_en && hpos == 9'd0) ? 0 : tick + 1;

reg hb_d = 0;
integer t_on = -1, t_off = -1;
always @(posedge clk) begin
	hb_d <= hblank;
	if (clk7_en && hpos == 9'd0) begin t_on <= -1; t_off <= -1; end
	else begin
		if ( hblank && !hb_d && t_on  < 0) t_on  <= tick;
		if (!hblank &&  hb_d && t_off < 0) t_off <= tick;
	end
end

task wr(input [8:0] a, input [15:0] d);
begin
	@(posedge clk); while (!clk7_en) @(posedge clk);
	ra <= a[8:1]; di <= d;
	@(posedge clk); while (!clk7_en) @(posedge clk);
	ra <= 9'h1fe >> 1; di <= 16'd0;
end
endtask

// set the blanking window and let a whole line go by
task line(input [7:0] hi, input h2, input [1:0] f, input [7:0] hio, input ho2, input [1:0] fo);
begin
	wr(9'h1c4, {5'd0, h2, f, hi});    // HBSTRT  H10-H3 in 7-0, H2 in 10, H1,H0 in 9-8
	wr(9'h1c6, {5'd0, ho2, fo, hio}); // HBSTOP
	while (!(clk7_en && hpos == 9'd0)) @(posedge clk);
	while (!(clk7_en && hpos == 9'd400)) @(posedge clk);
end
endtask

integer i, base_on, base_off, fail = 0;

task chk(input [50*8-1:0] what, input signed [31:0] got, input signed [31:0] want);
begin
	$write("  %-50s %5d  want %5d   %s\n", what, got, want, got === want ? "OK" : "FAIL");
	if (got !== want) fail = fail + 1;
end
endtask

initial begin
	repeat (8) @(posedge clk); reset_n = 1;
	repeat (8) @(posedge clk); reset = 0;
	wr(9'h1dc, 16'h0080);   // BEAMCON0, VARBEAMEN
	wr(9'h02c, 16'h0000);   // VHPOSW, so the beam counter starts from a known place
	wr(9'h1c0, 16'h00e2);   // HTOTAL  227 CCKs
	wr(9'h1c2, 16'h0010);   // HSSTOP
	wr(9'h1de, 16'h000a);   // HSSTRT
	wr(9'h1e2, 16'h0078);   // HCENTER
	wr(9'h1ce, 16'h001a);   // VBSTOP
	wr(9'h1c8, 16'h0138);   // VTOTAL
	wr(9'h1dc, 16'h0080);   // BEAMCON0, VARBEAMEN

	line(8'h40, 1'b0, 2'd0, 8'h60, 1'b0, 2'd0);  // settle
	line(8'h40, 1'b0, 2'd0, 8'h60, 1'b0, 2'd0);
	base_on = t_on; base_off = t_off;
	$display("\nHBSTRT $40 HBSTOP $60, no fine bits: blank on at tick %0d, off at %0d",
	         base_on, base_off);
	chk("blanking happens at all", base_on >= 0 && base_off > base_on, 1);

	// the 280ns field is two lores pixels, so one step is eight 35ns ticks
	line(8'h41, 1'b0, 2'd0, 8'h60, 1'b0, 2'd0);
	chk("HBSTRT +1 is 280ns, 8 ticks", t_on - base_on, 8);

	// bit 10 is the 140ns one AA put under it
	line(8'h40, 1'b1, 2'd0, 8'h60, 1'b0, 2'd0);
	chk("HBSTRT bit 10 is 140ns, 4 ticks", t_on - base_on, 4);

	for (i = 0; i < 4; i = i + 1) begin
		line(8'h40, 1'b0, i[1:0], 8'h60, 1'b0, 2'd0);
		chk({"HBSTRT bits 9,8 = ", 8'h30 + i[7:0], " move the start"}, t_on - base_on, i);
	end
	for (i = 0; i < 4; i = i + 1) begin
		line(8'h40, 1'b0, 2'd0, 8'h60, 1'b0, i[1:0]);
		chk({"HBSTOP bits 9,8 = ", 8'h30 + i[7:0], " move the end"}, t_off - base_off, i);
	end

	// all three of the new bits at once
	line(8'h40, 1'b1, 2'd3, 8'h60, 1'b0, 2'd0);
	chk("bit 10 and bits 9,8 together", t_on - base_on, 4 + 3);

	// ECS Denise has none of them
	aga = 0;
	line(8'h40, 1'b1, 2'd3, 8'h60, 1'b0, 2'd3);
	chk("ECS ignores bits 10-8, start", t_on,  base_on);
	chk("ECS ignores bits 10-8, end",   t_off, base_off);
	aga = 1;

	$display("\n%0s", fail ? "FAILURES" : "all cases OK");
	$finish;
end

endmodule
