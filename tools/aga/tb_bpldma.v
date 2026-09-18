`timescale 1ns/1ns
//
// The bitplane DMA pointer write delay.
//
// From TODO, Toni Wilen: "Writing to BPLxPT when exactly next cycle has DMA to
// matching BPLxDAT: write goes nowhere." The DMA channel has the address a
// cycle ahead of the fetch, so it reads the old pointer and writes back the old
// one plus the increment, and the write never reaches the register.
//
// This runs one bitplane in lores with the display DMA going and drops a write
// to BPL1PTL at a chosen point relative to a known fetch cycle: one cycle
// before it, which must be swallowed, and two cycles before it, which must
// take. The modulo rule from the same note - a write to BPLxMOD one cycle
// before a modulo add uses the old value, but is still accepted - is checked at
// the end of the line.
//
module tb_bpldma;

reg clk = 0, reset_n = 0;
always #17 clk = ~clk;

wire clk7_en, clk7n_en, c1, c3, cck;
wire [9:0] eclk;
amiga_clk clkgen (.clk_28(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en),
                  .c1(c1), .c3(c3), .cck(cck), .eclk(eclk), .reset_n(reset_n));

reg        reset = 1, sof = 0, dmaena = 0;
reg [10:0] vpos = 0;
reg  [8:0] hpos = 0;
reg  [8:1] ra = 9'h1fe >> 1;
reg [15:0] di = 0;

wire        dma, hde;
wire [8:1]  rao;
wire [20:1] ao;

agnus_bitplanedma dut (
	.clk(clk), .clk7_en(clk7_en), .reset(reset), .harddis(1'b0),
	.aga(1'b1), .ecs(1'b1), .a1k(1'b0), .sof(sof), .dmaena(dmaena),
	.vpos(vpos), .hpos(hpos), .hde(hde), .dma(dma),
	.reg_address_in(ra), .reg_address_out(rao), .data_in(di), .address_out(ao));

always @(posedge clk) if (clk7_en) begin
	if (hpos == 9'd453) begin hpos <= 0; vpos <= vpos + 1'b1; end
	else hpos <= hpos + 1'b1;
	sof <= (hpos == 9'd452) && (vpos == 11'd524);
end

// the address each fetch went out with, by the hpos it happened at
reg [20:1] fetch [0:511];
always @(posedge clk) if (clk7_en && dma) fetch[hpos] <= ao;

// where in the line the modulo gets added, and the pointer it produced
reg [8:0] mod_at = 0;
reg [20:1] mod_pt = 0;
always @(posedge clk) if (clk7_en && dma && dut.mod) begin
	mod_at <= hpos; mod_pt <= dut.newpt;
end

// present a register write so that the module samples it at exactly hpos = at
task wr_at(input [8:0] at, input [8:0] a, input [15:0] d);
begin
	while (!(clk7_en && hpos == at - 9'd1)) @(posedge clk);
	ra <= a[8:1]; di <= d;
	@(posedge clk); while (!clk7_en) @(posedge clk);
	ra <= 9'h1fe >> 1; di <= 16'd0;
end
endtask

task wr(input [8:0] a, input [15:0] d);
begin
	@(posedge clk); while (!clk7_en) @(posedge clk);
	ra <= a[8:1]; di <= d;
	@(posedge clk); while (!clk7_en) @(posedge clk);
	ra <= 9'h1fe >> 1; di <= 16'd0;
end
endtask

integer fail = 0;

task chk(input [46*8-1:0] what, input [31:0] got, input [31:0] want);
begin
	$write("  %-46s %06X  want %06X   %s\n", what, got, want, got === want ? "OK" : "FAIL");
	if (got !== want) fail = fail + 1;
end
endtask

// one scan line: reload BPL1PT at the top, then optionally write BPL1PTL so
// that the module sees it at hpos = at
task line(input do_wr, input [8:0] at, input [15:0] val);
begin
	while (!(clk7_en && hpos == 9'd10)) @(posedge clk);
	wr(9'h0e0, 16'h0001);                       // BPL1PTH -> $1xxxx
	wr(9'h0e2, 16'h0800);                       // BPL1PTL -> $10400
	if (do_wr) wr_at(at, 9'h0e2, val);
	while (!(clk7_en && hpos == 9'd450)) @(posedge clk);
end
endtask

// one scan line that reloads the pointer and writes BPL1MOD, either early in
// the line or so that the module sees it at hpos = at
task mline(input do_wr, input [8:0] at, input [15:0] m);
begin
	while (!(clk7_en && hpos == 9'd10)) @(posedge clk);
	wr(9'h0e0, 16'h0001);
	wr(9'h0e2, 16'h0800);
	if (do_wr) wr_at(at, 9'h108, m);
	while (!(clk7_en && hpos == 9'd450)) @(posedge clk);
end
endtask

reg [20:1] p0;

initial begin
	repeat (8) @(posedge clk); reset_n = 1;
	repeat (8) @(posedge clk); reset = 0;
	wr(9'h08e, 16'h2c81);   // DIWSTRT, vertical start $2c
	wr(9'h090, 16'hf4c1);   // DIWSTOP
	wr(9'h092, 16'h0038);   // DDFSTRT
	wr(9'h094, 16'h00d0);   // DDFSTOP
	wr(9'h100, 16'h1000);   // BPLCON0, one bitplane, lores
	wr(9'h108, 16'h0000);   // BPL1MOD
	dmaena = 1;
	while (vpos < 11'h2e) @(posedge clk);

	// one bitplane in lores fetches every 8 CCKs from hpos $89; $99 is the
	// second fetch of the line and the one the writes are aimed at
	line(1'b0, 9'd0, 16'h0000);
	$display("\nplain line: fetch at $89 %05X, at $99 %05X, at $a9 %05X",
	         fetch[9'h89], fetch[9'h99], fetch[9'ha9]);
	chk("the pointer is reloaded and then increments",
	    fetch[9'h99], fetch[9'h89] + 20'd1);

	// a write the module sees one cycle before the fetch goes nowhere: the
	// fetch uses the old pointer and the one after it carries on from there
	line(1'b1, 9'h98, 16'h2000);
	chk("write one cycle before the fetch is swallowed", fetch[9'h99], 20'h08401);
	chk("and the fetch after it carries on regardless", fetch[9'ha9], 20'h08402);

	// two cycles before, it lands
	line(1'b1, 9'h97, 16'h2000);
	chk("write two cycles before the fetch takes",       fetch[9'h99], 20'h09000);
	chk("and the fetch after it follows from there",     fetch[9'ha9], 20'h09001);

	// the same write far from any fetch also takes, which says the rule is
	// about the cycle and not about writes being dropped in general
	line(1'b1, 9'h90, 16'h2000);
	chk("write in a free cycle takes",                   fetch[9'h99], 20'h09000);
	$display("modulo added at hpos %03X, pointer became %05X", mod_at, mod_pt);

	// The modulo rule from the same note: a write to BPLxMOD one cycle before
	// the add uses the old value, and is still accepted for next time.
	mline(1'b1, 9'd20, 16'h0000);
	p0 = mod_pt;
	$display("\nmodulo added at hpos %03X; with BPL1MOD 0 the pointer became %05X",
	         mod_at, p0);

	mline(1'b1, 9'd20, 16'h0004);
	chk("BPL1MOD 4 written early adds two words", mod_pt, p0 + 20'd2);

	// 8 arriving one cycle before the add: the add still uses the 4
	mline(1'b1, mod_at, 16'h0008);
	chk("BPL1MOD 8 one cycle before the add is not used", mod_pt, p0 + 20'd2);

	// but it was accepted, so the next line uses it
	mline(1'b0, 9'd0, 16'h0000);
	chk("and it is used on the line after",       mod_pt, p0 + 20'd4);

	$display("\n%0s", fail ? "FAILURES" : "all cases OK");
	$finish;
end

endmodule
