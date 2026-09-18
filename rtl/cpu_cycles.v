//--------------------------------------------------------------------------//
// Per-instruction cycle cost for the 68030 mode.                           //
//                                                                          //
// The 68030 manual gives each instruction a head, a tail and an            //
// instruction-cache-case time, and composes a stream of them (11-1):       //
//                                                                          //
//     CC1 + [CC2 - min(H2,T1)] + [CC3 - min(H3,T2)] + ...                  //
//                                                                          //
// so what an instruction costs depends on the one before it, and no scalar //
// clock divider can express that. An instruction taking an effective       //
// address composes the two the same way (11-2):                            //
//                                                                          //
//     CCea + [CCop - min(Hop,Tea)]                                         //
//                                                                          //
// The two ROMs are built by tools/m68k_timing straight from the tables in  //
// section 11 of the manual. An entry with its valid bit clear has no table //
// row behind it and is charged the architectural minimum of two clocks     //
// rather than a made-up number.                                            //
//--------------------------------------------------------------------------//

module cpu_cycles
(
	input             clk,
	input             reset,

	input             ntsc,
	input             ena,          // 68030 mode with a clock target selected
	input       [1:0] speed,        // 00 25MHz, 01 40MHz, 10 50MHz, 11 unthrottled

	input             opc_start,    // one clkena as an instruction begins
	input      [15:0] opc,
	input             opc_cond,     // condition of the instruction before it
	input      [15:0] opc_snd,      // the word after it, settled one clock later
	input             cpu_ena,      // the enable the CPU is actually getting

	output            hold          // hold the CPU: it has not paid for the last one
);

// rate/4096 CPU clocks are earned per sysclk, so rate is 4096*f_cpu/f_sys,
// f_sys being 113.5006MHz on PAL and 114.5454MHz on NTSC.
reg [11:0] rate;
always @* case({ena, speed})
	3'b100:  rate = ntsc ? 12'd894  : 12'd902;
	3'b101:  rate = ntsc ? 12'd1430 : 12'd1444;
	3'b110:  rate = ntsc ? 12'd1788 : 12'd1804;
	default: rate = 12'd0;
endcase

wire run = |rate;

// The tables repeat: a 68030 has only sixty distinct (cc, head, tail, ea
// class) combinations across every opcode form, and twenty for the effective
// addresses. So the memories hold an index into those and the entries live in
// logic - 11 M10K rather than 36 for the raw images.
(* ram_init_file = "rtl/tg68k/m68k_cyc_idx.mif" *) reg [5:0] cyc_rom[16384];
(* ram_init_file = "rtl/tg68k/m68k_ea_idx.mif"  *) reg [4:0] ea_rom[2048];

reg [15:0] opc_l;
reg [15:0] snd_l;
reg  [2:0] st;
always @(posedge clk) begin
	if (~reset) st <= 0;
	else begin
		st <= {st[1:0], opc_start & cpu_ena & run};
		if (opc_start & cpu_ena) opc_l <= opc;
		if (st[0]) snd_l <= opc_snd;
	end
end

// Two instructions take a number from the word after the opcode, so no ROM
// indexed by the opcode can hold their time. MOVEM takes the register list,
// and a long divide takes the bit that makes it signed. Both are read out of
// snd_l, which the kernel has settled by the time st[0] samples it.
//
// 11.6.7: MOVEM EA,RL is 8+4n clocks and MOVEM RL,EA is 4+2n, both head 2 and
// tail 0, with the calculate-immediate-address time on top - always the word
// row, because the register list is one word whatever the transfer size. The
// table's two footnotes print those formulas under swapped labels; the
// (r/p/w) column settles which is which, the 8+4n row being the one that does
// n reads and so the one that loads registers.
wire movem = (opc_l[15:12] == 4'h4) & opc_l[11] & ~opc_l[9] & ~opc_l[8]
           & opc_l[7] & |opc_l[5:3];

reg [4:0] rn;
integer i;
always @* begin
	rn = 5'd0;
	for (i = 0; i < 16; i = i + 1) rn = rn + {4'd0, snd_l[i]};
end

wire  [7:0] mv_cc   = opc_l[10] ? (8'd8 + {1'b0, rn, 2'b00}) : (8'd4 + {2'b00, rn, 1'b0});
wire [19:0] movem_e = {1'b1, 3'd4, 2'd0, 5'd2, mv_cc, 1'b0};

// 11.6.8 gives DIVU.L 78 clocks and DIVS.L 90, alike in head, tail and
// address class. The sign is extension word bit 11.
wire divsl = (opc_l[15:6] == 10'h131) & snd_l[11];

// A register number never changes a time, so the low three bits of the opcode
// stay out of the index - except under mode 7, where they select the
// addressing mode and sometimes the instruction, so mode 7 gets its own half.
wire [13:0] cyc_a = (opc_l[5:3] == 3'b111) ? {opc_l[15:6], 1'b1, opc_l[2:0]}
                                           : {opc_l[15:6], 1'b0, opc_l[5:3]};

// 4E70-4E77 is the one group that needs opcode[2:0] without being mode 7.
wire misc = (opc_l[15:3] == 13'h09CE);

reg [5:0] cyc_i;
reg [4:0] ea_i;
always @(posedge clk) begin
	cyc_i <= cyc_rom[cyc_a];
	ea_i  <= ea_rom[{op_e[18:16], movem ? 2'b01 : opc_l[7:6], opc_l[5:0]}];
end

reg [19:0] cyc_e;
reg [19:0] misc_e;
reg [15:0] ea_e;
`include "tg68k/m68k_cyc_pal.vh"
`include "tg68k/m68k_ea_pal.vh"
`include "tg68k/m68k_misc_030.vh"

wire [19:0] op_e = misc ? misc_e : movem ? movem_e : cyc_e;

wire [2:0] eacl  = op_e[18:16];
wire [1:0] op_t  = op_e[15:14];
wire [4:0] op_h  = op_e[13:9];
wire [7:0] op_cc = op_e[8:1] + (divsl ? 8'd12 : 8'd0);

wire       ea_v  = ea_e[15] & |eacl;
wire [6:0] ea_cc = ea_v ? ea_e[14:8] : 7'd0;
wire [4:0] ea_h  = ea_v ? ea_e[7:3]  : 5'd0;
wire [1:0] ea_t  = ea_v ? ea_e[2:1]  : 2'd0;
wire       ea_ph = ea_v & ea_e[0];
wire       model = op_e[19] & (~|eacl | ea_e[15]);

// A conditional branch with a byte displacement costs 4 clocks when it is not
// taken and 6 when it is, and the tables hold the taken figure. Which it will
// be is not known when the charge is made - the CPU is held and has not run
// the branch yet - so the not-taken figure is charged and the two clocks are
// added at the next instruction's start, where exe_condition has settled on
// this branch's outcome. A word or long displacement is 6 either way, and BRA
// and BSR are always taken, so neither is touched.
wire bcc_b = (opc_l[15:12] == 4'h6) && (opc_l[11:8] > 4'h1)
          && (opc_l[7:0] != 8'h00) && (opc_l[7:0] != 8'hFF);

wire [4:0] ov1  = (op_h < {3'b0, ea_t}) ? op_h : {3'b0, ea_t};
wire [8:0] cc   = {1'b0, op_cc} + {2'b0, ea_cc} - {4'b0, ov1};
wire [5:0] head = ea_v ? ({1'b0, ea_h} + (ea_ph ? {1'b0, op_h} : 6'd0)) : {1'b0, op_h};
wire [5:0] ov2  = (head < {4'b0, prev_t}) ? head : {4'b0, prev_t};
// After the overlap an instruction can cost less than two clocks, and the
// manual says outright that a net of zero is possible, so nothing is clamped
// here. The two-clock floor is only for a form with no table row behind it.
wire [8:0] net  = cc - {3'b0, ov2};
wire [8:0] cost = model ? (bcc_b ? net - 9'd2 : net) : 9'd2;
// what this instruction owes: its own cost, plus the two clocks a taken byte
// branch before it turned out to need
wire [8:0] due  = cost + (bcc_add ? 9'd2 : 9'd0);

// The two ROM reads take three clocks and the CPU is held through them, so
// those clocks would land on top of every instruction. They do not: whatever
// the accumulator earns while a lookup is in flight is banked in cred and
// comes off the charge at the end of it, so over a stream the lookup costs
// nothing and an instruction costs what the tables say.
reg [12:0] acc;
reg  [8:0] debt;
reg  [1:0] cred;
reg  [1:0] prev_t;
reg        bcc_pend;
reg        bcc_add;
wire       spend = acc[12];
wire [8:0] pay   = {7'd0, cred} + {8'd0, spend};
always @(posedge clk) begin
	if (~reset) begin
		acc      <= 0;
		debt     <= 0;
		cred     <= 0;
		prev_t   <= 0;
		bcc_pend <= 0;
		bcc_add  <= 0;
	end
	else begin
		acc <= {1'b0, acc[11:0]} + rate;
		if (opc_start & cpu_ena & run) begin
			bcc_add  <= bcc_pend & opc_cond;   // the branch before was taken
			bcc_pend <= 0;
		end
		if (st[2]) begin
			debt     <= (due > pay) ? due - pay : 9'd0;
			cred     <= 0;
			prev_t   <= model ? op_t : 2'd0;
			bcc_pend <= model & bcc_b;
			bcc_add  <= 0;
		end
		else if (|st) begin
			if (spend & ~&cred) cred <= cred + 1'd1;
		end
		else begin
			cred <= 0;
			if (spend & |debt) debt <= debt - 1'd1;
		end
	end
end

assign hold = run & (|debt | |st);

endmodule
