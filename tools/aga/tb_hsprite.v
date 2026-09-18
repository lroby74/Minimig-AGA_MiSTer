`timescale 1ns/1ns
//
// The AA sprite horizontal start, at 35ns.
//
// Sets sprite 0 up through the register bus the way a copper list or the
// sprite DMA channel would, and times when its data first reaches the serial
// output. SPRxPOS carries SH10-SH3 and SPRxCTL bit 0 carries SH2, which is
// where OCS stopped; AA added SH1 at 70ns in bit 4 and SH0 at 35ns in bit 3.
//
module tb_hsprite;

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

integer tick = 0;
always @(posedge clk) tick <= (strhor && clk7_en) ? 0 : tick + 1;

wire [1:0] sprdata = dut.sprm0.sps0.sprdata;
integer t_spr = -1;
always @(posedge clk) begin
	if (strhor && clk7_en) t_spr <= -1;
	else if (|sprdata && t_spr < 0) t_spr <= tick;
end

task wr(input [8:0] a, input [15:0] d);
begin
	@(posedge clk); while (!clk7_en) @(posedge clk);
	reg_address_in <= a[8:1]; data_in <= d;
	@(posedge clk); while (!clk7_en) @(posedge clk);
	reg_address_in <= 9'h1fe >> 1; data_in <= 16'd0;
end
endtask

// one scan line with sprite 0 armed at SH10-SH3 = hi, SH2 = h2, SH1,SH0 = f
task line(input [7:0] hi, input h2, input [1:0] f);
begin
	wr(9'h140, {8'h2c, hi});                       // SPR0POS  SV7-SV0, SH10-SH3
	wr(9'h142, 16'h2c00 | (f << 3) | {15'd0, h2}); // SPR0CTL  SH1,SH0 and SH2
	wr(9'h146, 16'hffff);                          // SPR0DATB
	wr(9'h144, 16'hffff);                          // SPR0DATA arms the sprite
	@(posedge clk); while (!clk7_en) @(posedge clk);
	strhor <= 1; @(posedge clk); while (!clk7_en) @(posedge clk); strhor <= 0;
	repeat (1200) @(posedge clk);
end
endtask

integer i, base, fail = 0;

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

	line(8'h40, 1'b0, 2'd0);        // settle
	line(8'h40, 1'b0, 2'd0);
	base = t_spr;
	$display("\nSPR0 at SH10-SH3 $40, SH2 0, no SH1/SH0: data out at tick %0d", base);
	chk("the sprite comes out at all", base >= 0, 1);

	// SPRxPOS carries SH10-SH3, so its lowest bit is 280ns - two lores pixels
	line(8'h41, 1'b0, 2'd0);
	chk("SPRxPOS +1 is SH3, 280ns, 8 ticks", t_spr - base, 8);

	// SH2 is the 140ns bit OCS already had
	line(8'h40, 1'b1, 2'd0);
	chk("SPRxCTL SH2 is 140ns, 4 ticks", t_spr - base, 4);

	for (i = 0; i < 4; i = i + 1) begin
		line(8'h40, 1'b0, i[1:0]);
		chk({"SPRxCTL SH1,SH0 = ", 8'h30 + i[7:0], " moves the start"}, t_spr - base, i);
	end

	// and the three together add up
	line(8'h41, 1'b1, 2'd3);
	chk("SH3 + SH2 + SH1 + SH0 together", t_spr - base, 8 + 4 + 3);

	// on ECS Denise those two bits are something else, so they cannot move it
	aga = 0;
	line(8'h40, 1'b0, 2'd3);
	chk("ECS ignores SH1,SH0 in SPRxCTL", t_spr, base);
	aga = 1;

	$display("\n%0s", fail ? "FAILURES" : "all cases OK");
	$finish;
end

endmodule
