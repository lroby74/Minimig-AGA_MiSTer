`timescale 1ns/1ps
// tb_cache_gap: cpu_cache_new with LINE_TAKE=1 (as in ddram_ctrl) against a pause of cpu_cs that falls in the
// clocks of a long write hitting the instruction cache. Part A moves the pause by hand around the write (d clocks
// after the ready, g clocks long) and follows it with each kind of access; part B drives the cache like the 68030
// (CPU on the 28 MHz edges, ram_cs of Minimig.sv on 114 MHz) with random accesses, checking every read.
// iverilog -g2005 -o tb dpram_sim.v ../../cpu_cache_new.v tb_cache_gap.v && vvp -n tb +seed=1 +nb=200000
module tb_cache_gap;

reg clk = 0;
always #5 clk = ~clk;

reg         rst = 1, rst_b = 0;
reg         mode = 0;
reg         cs_a = 0, rsel = 0, cs_b = 0;
reg         we = 0, ir = 0, lng = 0;
reg  [12:0] wa = 0;
reg   [1:0] bs = 2'b11;
reg  [15:0] dw = 0, dwl = 0;
wire        cs = mode ? cs_b : cs_a;
wire [15:0] dr, drh;
wire        ack, ackl, wb, idle, rreq;
reg         rack = 0;
reg  [15:0] rdat = 0;

cpu_cache_new #(.LINE_TAKE(1)) dut
(
	.clk(clk), .rst(rst | rst_b), .cpu_cache_ctrl(4'b0001), .dcache_sw_en(1'b1), .cache_inhibit(1'b0),
	.cpu_cs(cs), .cpu_adr({15'h0009, wa}), .cpu_bs(bs), .cpu_we(we), .cpu_ir(ir), .cpu_dr(~ir & ~we),
	.cpu_dat_w(dw), .cpu_dat_r(dr), .cpu_ack(ack), .wb_en(wb), .cpu_idle(idle),
	.sdr_dat_r(rdat), .sdr_read_req(rreq), .sdr_read_ack(rack),
	.snoop_act(1'b0), .snoop_adr(28'd0), .snoop_dat_w(16'd0), .snoop_bs(2'b00),
	.buf_ok(1'b0), .buf_dat(64'd0), .buf_take(),
	.cpu_long(lng), .cpu_dat_w_lo(dwl), .cpu_dat_hi(drh), .cpu_ack_l(ackl)
);

// memory behind the write buffer of ddram_ctrl: a write is taken on (cache_ack | cache_idle) & ~write_ena
reg  [15:0] mem[0:8191];
reg         wena = 0, wl1 = 0, room = 1;
wire        wnew = cs & we & (wb | idle) & ~wena & room;
wire        rdy  = ack | wena;
wire        rdyl = ackl | (wena & wl1);
always @(posedge clk) begin
	if(wnew) begin
		mem[wa] <= {bs[1] ? dw[15:8] : mem[wa][15:8], bs[0] ? dw[7:0] : mem[wa][7:0]};
		if(lng) mem[wa | 13'd1] <= dwl;
		wena <= 1;
		wl1  <= lng;
	end
	if(~cs) {wena, wl1} <= 0;
end

// line fill: four beats after a random latency, critical word first
integer     seed = 1;
reg   [2:0] fb = 0;
reg         fbusy = 0;
reg  [12:0] fa = 0;
reg   [3:0] flat = 0, maxlat = 0;
always @(posedge clk) begin
	rack <= 0;
	if(rst | rst_b) fbusy <= 0;
	else if(~fbusy) begin
		if(rreq) begin fbusy <= 1; fa <= wa; fb <= 0; flat <= maxlat ? {$random(seed)} % (maxlat + 1) : 4'd0; end
	end
	else if(flat) flat <= flat - 1'd1;
	else begin
		rack <= 1;
		rdat <= mem[{fa[12:2], fa[1:0] + fb[1:0]}];
		fb   <= fb + 1'd1;
		if(fb == 3) fbusy <= 0;
	end
end

integer     errs = 0, stalls = 0, stales = 0;
reg  [15:0] r, rh;
reg         rl, ok;

task tick; begin @(posedge clk); #1; end endtask

task do_rst; begin cs_a = 0; tick; rst = 1; repeat(4) tick; rst = 0; repeat(300) tick; end endtask

// part A access: cpu_cs drops d clocks after the ready (0 = in the clock of the ready) and stays low g clocks
task acc(input w, input i, input l, input [11:0] a, input [1:0] b, input [15:0] h, input [15:0] lo, input integer d, input integer g);
	integer t;
	begin
		we = w; ir = i; lng = l; wa = a; bs = b; dw = h; dwl = lo; cs_a = 1;
		t = 0;
		tick;
		while(~rdy && t < 300) begin tick; t = t + 1; end
		ok = (t < 300);
		r = dr; rh = drh; rl = rdyl;
		if(ok) repeat(d) tick;
		cs_a = 0;
		repeat(g) tick;
	end
endtask

// safe access with check (pause long enough for every state)
reg bad;
task chk(input i, input [11:0] a, input [15:0] e);
	begin
		acc(0, i, 0, a, 2'b11, 0, 0, 1, 3);
		if(~ok) bad = 1;
		else if(r !== e) begin
			bad = 1;
			if(stales < 12) $display("  STALE %s %04x: %04x, expected %04x", i ? "fetch" : "read ", a, r, e);
		end
	end
endtask

task fill(input [11:0] l, input [15:0] b);
	integer k;
	begin for(k = 0; k < 4; k = k + 1) mem[{l[9:0], k[1:0]}] = b + k; end
endtask

integer     d, g, n, c;
reg   [9:0] L, M, Z;
reg  [15:0] h, lo;
reg   [5:0] fl;

// part A
task part_a;
	begin
		$display("A: long write into an instruction cache line, cpu_cs low d clocks after the ready, for g clocks");
		c = 0;
		for(d = 0; d <= 4; d = d + 1) for(g = 1; g <= 3; g = g + 1) begin
			fl = 0;
			for(n = 0; n <= 5; n = n + 1) begin
				L = {2'd0, c[7:0]}; M = {2'd1, c[7:0] + 8'd128}; Z = {2'd2, c[7:0]};
				h = 16'hA000 | c; lo = 16'hB000 | c;
				fill(L, 16'h1000 + 16 * c); fill(M, 16'h2000 + 16 * c); fill(Z, 16'h3000 + 16 * c);
				bad = 0;
				chk(1, {L, 2'd0}, mem[{L, 2'd0}]);                  // line L in the instruction cache
				chk(0, {L, 2'd1}, mem[{L, 2'd1}]);                  // and in the data cache
				chk(0, {M, 2'd0}, mem[{M, 2'd0}]);                  // line M in the data cache
				acc(1, 0, 1, {L, 2'd0}, 2'b11, h, lo, d, g);       // the long write, with the pause
				if(~ok) bad = 1;
				case(n)
					0: chk(1, {L, 2'd2}, mem[{L, 2'd2}]);
					1: chk(0, {M, 2'd1}, mem[{M, 2'd1}]);
					2: chk(0, {Z, 2'd0}, mem[{Z, 2'd0}]);
					3: acc(1, 0, 0, {M, 2'd2}, 2'b11, 16'hC000 | c, 0, 1, 3);
					4: acc(1, 0, 1, {M, 2'd0}, 2'b11, 16'hD000 | c, 16'hE000 | c, 1, 3);
					5: acc(1, 0, 1, {L, 2'd2}, 2'b11, 16'hF000 | c, 16'h9000 | c, d, g);
				endcase
				if(~ok) bad = 1;
				if(~bad) begin
					chk(1, {L, 2'd0}, h); chk(1, {L, 2'd1}, lo); chk(0, {L, 2'd0}, h); chk(0, {L, 2'd1}, lo);
					if(n == 3) chk(0, {M, 2'd2}, 16'hC000 | c);
					if(n == 4) begin chk(0, {M, 2'd0}, 16'hD000 | c); chk(0, {M, 2'd1}, 16'hE000 | c); end
					if(n == 5) begin chk(1, {L, 2'd2}, 16'hF000 | c); chk(1, {L, 2'd3}, 16'h9000 | c);
					                 chk(0, {L, 2'd2}, 16'hF000 | c); chk(0, {L, 2'd3}, 16'h9000 | c); end
				end
				if(bad) begin
					fl[n] = 1;
					if(~ok) stalls = stalls + 1; else stales = stales + 1;
					do_rst;
				end
				c = c + 1;
			end
			$display("  d=%0d g=%0d: %s  (then: fetch %s, read %s, read miss %s, write %s, long write %s, long I write %s)",
			         d, g, fl ? "FAIL" : "ok  ", fl[0] ? "X" : ".", fl[1] ? "X" : ".", fl[2] ? "X" : ".",
			         fl[3] ? "X" : ".", fl[4] ? "X" : ".", fl[5] ? "X" : ".");
			if(fl) errs = errs + 1;
		end
		$display("A: %0d of 15 cases failed (stalls %0d, stale data %0d)", errs, stalls, stales);
	end
endtask

// part B: CPU on the 28 MHz edges, ram_cs <= ~(ram_ready & cyc & cpu_type) & ram_sel as in Minimig.sv
reg   [1:0] ph = 0;
wire        cyc = (ph == 3);
always @(posedge clk) begin ph <= ph + 1'd1; cs_b <= ~(rdy & cyc) & rsel; end

integer     nb = 200000, nacc = 0, wait_n = 0, idle_n = 0, bad_b = 0, stall_b = 0, kind = 0, rcnt = 0;
reg         half = 0;
reg  [12:0] ha;
reg  [12:0] hot[0:23];
reg   [2:0] ht;
reg   [7:0] hi8;

task next;
	integer x;
	reg [12:0] a;
	begin
		x = {$random(seed)} % 100;
		a = {hot[{$random(seed)} % 24][12:2], 2'd0} | ({$random(seed)} % 4);
		if(half) begin kind = 1; a = ha; half = 0; end
		else if(x < 25) begin rsel <= 0; idle_n = {$random(seed)} % 4; kind = 9; end
		else if(x < 50) kind = 0;
		else if(x < 62) kind = 1;
		else if(x < 70) kind = 2;
		else if(x < 82) kind = 3;
		else kind = 4;
		if(kind == 2 || kind == 4) a[0] = 0;
		if(kind != 9) begin
			rsel <= 1; wa <= a; ir <= (kind == 0); we <= (kind >= 3); lng <= (kind == 2 || kind == 4);
			bs <= (kind == 3) ? 2'd1 + {$random(seed)} % 3 : 2'b11;
			dw <= $random(seed); dwl <= $random(seed);
		end
		wait_n = 0;
	end
endtask

always @(posedge clk) if(mode & ~rst) begin
	room <= ({$random(seed)} % 10) != 0;
	if(rcnt) begin
		rcnt = rcnt - 1;
		rst_b <= (rcnt > 396);
		if(rcnt == 0) begin half = 0; idle_n = 0; end
	end
	else if(cyc) begin
		if(rsel & rdy) begin
			if(kind == 0 || kind == 1) begin
				if(dr !== mem[wa]) begin
					bad_b = bad_b + 1;
					if(bad_b <= 10) $display("  STALE access %0d %s %04x: %04x, expected %04x", nacc, kind ? "read " : "fetch", wa, dr, mem[wa]);
				end
			end
			else if(kind == 2) begin
				if(rdyl ? (drh !== mem[wa] || dr !== mem[wa | 13'd1]) : (dr !== mem[wa])) begin
					bad_b = bad_b + 1;
					if(bad_b <= 10) $display("  STALE access %0d long %04x", nacc, wa);
				end
				if(~rdyl) begin half = 1; ha = wa | 13'd1; end
			end
			nacc = nacc + 1;
			next;
		end
		else if(~rsel) begin
			if(idle_n) idle_n = idle_n - 1; else next;
		end
	end
	if(rsel & (rcnt == 0)) begin
		wait_n = wait_n + 1;
		if(wait_n > 600) begin
			stall_b = stall_b + 1;
			rsel <= 0;
			rcnt = 400;
			if(stall_b <= 10) $display("  STALL at access %0d (kind %0d, %04x): state %0d, w2 %b, wb_en %b, cs %b", nacc, kind, wa,
			         dut.cpu_sm_state, dut.cpu_sm_w2, wb, cs);
		end
	end
end

task part_b;
	integer k;
	begin
		$display("B: 68030 on 28 MHz, ram_cs as in Minimig.sv, %0d random accesses, seed %0d", nb, seed);
		for(k = 0; k < 24; k = k + 1) begin
			ht = k % 6;
			hi8 = (k / 6 == 0) ? 8'h05 : (k / 6 == 1) ? 8'h3A : (k / 6 == 2) ? 8'h77 : 8'hC1;
			hot[k] = {ht, hi8, 2'd0};
		end
		for(k = 0; k < 8192; k = k + 1) mem[k] = $random(seed);
		maxlat = 7;
		do_rst;
		mode = 1;
		@(posedge clk); next;
		while(nacc < nb && stall_b < 100) @(posedge clk);
		mode = 0; rsel = 0;
		$display("B: %0d accesses, wrong reads %0d, stalls %0d", nacc, bad_b, stall_b);
	end
endtask

integer k0;
initial begin
	if(!$value$plusargs("seed=%d", seed)) seed = 1;
	if(!$value$plusargs("nb=%d", nb)) nb = 200000;
	for(k0 = 0; k0 < 8192; k0 = k0 + 1) mem[k0] = 0;
	do_rst;
	part_a;
	part_b;
	$display("RUN: %s", (errs == 0 && bad_b == 0 && stall_b == 0) ? "PASS" : "FAIL");
	$finish;
end

endmodule
