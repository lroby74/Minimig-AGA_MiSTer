// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns / 1ps

module tb_akiko_cmdflow;

initial begin
	#200000000 $fatal(1, "tb_akiko_cmdflow: watchdog timeout");
end

logic clk = 0;
initial forever #5 clk = ~clk;

logic        reset = 1;
logic        cs    = 0;
logic        rd    = 0;
logic        wr    = 0;
logic        lds   = 0;
logic        uds   = 0;
logic [5:1]  addr  = 0;
logic [15:0] din   = 0;
wire  [15:0] dout;
wire         irq;
logic  [1:0] cd_speed = 2'b11;
logic        ntsc     = 1'b0;

wire        dma_req;
wire        dma_we;
wire [23:0] dma_baddr;
wire  [7:0] dma_wbyte;
logic [7:0] dma_rbyte = 8'h00;
logic       dma_ack   = 1'b0;
logic       dma_arm   = 1'b0;

wire        hps_cmd_pending;
wire  [7:0] hps_cmd_byte;
logic       hps_cmd_pop      = 1'b0;
logic       hps_cmd_done     = 1'b0;
logic       hps_result_push  = 1'b0;
logic [7:0] hps_result_byte  = 8'h00;
logic       hps_result_done  = 1'b0;
wire        hps_sec_req;
wire [15:0] hps_sec_status;
logic       hps_sec_push     = 1'b0;
logic[15:0] hps_sec_word     = 16'h0000;
logic       hps_sec_done     = 1'b0;
wire        hps_rx_busy;
logic       hps_subcode_push = 1'b0;
logic [7:0] hps_subcode_byte = 8'h00;
logic       hps_subcode_done = 1'b0;

akiko #(.NATIVE_CD32(1)) u_dut (
	.clk(clk), .reset(reset), .cd_speed(cd_speed), .ntsc(ntsc),
	.cs(cs), .rd(rd), .wr(wr),
	.lds(lds), .uds(uds),
	.addr(addr), .din(din), .dout(dout),
	.akiko_irq(irq),
	.dma_req(dma_req), .dma_we(dma_we),
	.dma_baddr(dma_baddr), .dma_wbyte(dma_wbyte),
	.dma_rbyte(dma_rbyte), .dma_ack(dma_ack), .dma_arm(dma_arm),
	.hps_cmd_pending(hps_cmd_pending), .hps_cmd_byte(hps_cmd_byte),
	.hps_cmd_pop(hps_cmd_pop), .hps_cmd_done(hps_cmd_done),
	.hps_result_push(hps_result_push), .hps_result_byte(hps_result_byte), .hps_result_done(hps_result_done),
	.hps_sec_req(hps_sec_req), .hps_sec_status(hps_sec_status),
	.hps_sec_push(hps_sec_push), .hps_sec_word(hps_sec_word), .hps_sec_done(hps_sec_done),
	.hps_rx_busy(hps_rx_busy),
	.hps_nvr_addr(10'd0), .hps_nvr_dout(), .hps_nvr_clear_dirty(1'b0), .hps_nvr_dirty(),
	.nvr_load_addr(10'd0), .nvr_load_din(8'h00), .nvr_load_we(1'b0),
	.hps_subcode_push(hps_subcode_push), .hps_subcode_byte(hps_subcode_byte), .hps_subcode_done(hps_subcode_done)
);

localparam [31:0] CDINT_SUBCODE   = 32'h80000000;
localparam [31:0] CDINT_DRIVEXMIT = 32'h40000000;
localparam [31:0] CDINT_DRIVERECV = 32'h20000000;
localparam [31:0] CDINT_RXDMADONE = 32'h10000000;
localparam [31:0] CDINT_TXDMADONE = 32'h08000000;
localparam [31:0] CDINT_PBX       = 32'h04000000;

localparam [31:0] CFG_SUB = 32'h80000000;
localparam [31:0] CFG_TXD = 32'h40000000;
localparam [31:0] CFG_RXD = 32'h20000000;
localparam [31:0] CFG_PBX = 32'h08000000;
localparam [31:0] CFG_ENA = 32'h04000000;

localparam [5:1] A_INTENA = 5'b00100;
localparam [5:1] A_DATA   = 5'b01000;
localparam [5:1] A_MISC   = 5'b01010;
localparam [5:1] A_TXCMP  = 5'b01110;
localparam [5:1] A_RXCMP  = 5'b01111;
localparam [5:1] A_PBX    = 5'b10000;
localparam [5:1] A_FLAGS  = 5'b10010;
localparam [5:1] A_PIO    = 5'b10100;

int checks = 0;
int errs   = 0;

task automatic check8(string name, logic [7:0] expected, logic [7:0] actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected 0x%02h got 0x%02h (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check_bit(string name, logic expected, logic actual);
	checks++;
	if (expected !== actual) begin
		$display("FAIL %s: expected %0b got %0b (t=%0t)", name, expected, actual, $time);
		errs++;
	end
endtask

task automatic check_range(string name, int lo, int hi, int actual);
	checks++;
	if (actual < lo || actual > hi) begin
		$display("FAIL %s: expected %0d..%0d got %0d (t=%0t)", name, lo, hi, actual, $time);
		errs++;
	end
endtask

logic [7:0] mem [262144];

initial for (int i = 0; i < 262144; i++) mem[i] = 8'h00;

logic bfm_in_xfer = 1'b0;
always @(posedge clk) begin
	dma_ack <= 1'b0;
	dma_arm <= 1'b0;
	if (bfm_in_xfer) begin
		if (dma_we) mem[dma_baddr[17:0]] <= dma_wbyte;
		else        dma_rbyte <= mem[dma_baddr[17:0]];
		dma_ack     <= 1'b1;
		bfm_in_xfer <= 1'b0;
	end else if (dma_req && !dma_ack) begin
		bfm_in_xfer <= 1'b1;
		dma_arm     <= 1'b1;
	end
end

task automatic bus_write_word(input [5:1] a, input [15:0] data);
	@(posedge clk);
	cs <= 1; wr <= 1; rd <= 0; addr <= a; din <= data; lds <= 1; uds <= 1;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0; uds <= 0;
endtask

task automatic bus_write_byte_lo(input [5:1] a, input [7:0] data);
	@(posedge clk);
	cs <= 1; wr <= 1; rd <= 0; addr <= a; din <= {8'h0, data}; lds <= 1; uds <= 0;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0; uds <= 0;
endtask

task automatic bus_write_long(input [5:1] a_hi, input [31:0] data);
	bus_write_word(a_hi,        data[31:16]);
	bus_write_word(a_hi + 5'd1, data[15:0]);
endtask

task automatic pio_write(input [7:0] b);
	@(posedge clk);
	cs <= 1; wr <= 1; rd <= 0; addr <= A_PIO; din <= {b, 8'h00}; lds <= 0; uds <= 1;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0; uds <= 0;
	repeat (4) @(posedge clk);
endtask

task automatic pio_read(output logic [7:0] b);
	@(posedge clk);
	cs <= 1; rd <= 1; wr <= 0; addr <= A_PIO; uds <= 1;
	#1 b = dout[15:8];
	@(posedge clk);
	cs <= 0; rd <= 0; addr <= 0; uds <= 0;
	repeat (2) @(posedge clk);
endtask

task automatic do_reset;
	reset <= 1;
	repeat (3) @(posedge clk);
	reset <= 0;
	@(posedge clk);
endtask

task automatic hps_drain(input int n, output logic [7:0] b0, output logic [7:0] b1);
	logic [7:0] v [32];
	for (int i = 0; i < n; i++) begin
		@(posedge clk);
		v[i] = hps_cmd_byte;
		hps_cmd_pop <= 1;
		@(posedge clk);
		hps_cmd_pop <= 0;
	end
	@(posedge clk);
	hps_cmd_done <= 1;
	@(posedge clk);
	hps_cmd_done <= 0;
	@(posedge clk);
	b0 = v[0];
	b1 = v[1];
endtask

task automatic hps_reply2(input [7:0] a, input [7:0] b);
	@(posedge clk); hps_result_byte <= a; hps_result_push <= 1;
	@(posedge clk); hps_result_byte <= b;
	@(posedge clk); hps_result_push <= 0;
	@(posedge clk); hps_result_done <= 1;
	@(posedge clk); hps_result_done <= 0;
	@(posedge clk);
endtask

task automatic wait_pending(input int max_cycles, output int cycles);
	int n;
	n = 0;
	while (!hps_cmd_pending && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
	cycles = n;
endtask

task automatic wait_parsed(input logic [5:0] len, input int max_cycles, output int cycles);
	int n;
	n = 0;
	while (u_dut.g_cd.cdrom_command_length != len && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
	cycles = n;
endtask

task automatic wait_rx_idle(input int max_cycles);
	int n;
	n = 0;
	while ((u_dut.g_cd.rx_busy || u_dut.g_cd.cdrom_receive_length != 0) && n < max_cycles) begin
		@(posedge clk);
		n = n + 1;
	end
endtask

task automatic push_sector(input [7:0] seed);
	@(posedge clk);
	for (int i = 0; i < 1176; i++) begin
		hps_sec_word <= {seed + 8'(2*i + 1), seed + 8'(2*i)};
		hps_sec_push <= 1'b1;
		@(posedge clk);
	end
	hps_sec_push <= 1'b0;
	hps_sec_word <= 16'h0000;
	@(posedge clk);
	hps_sec_done <= 1'b1;
	@(posedge clk);
	hps_sec_done <= 1'b0;
	@(posedge clk);
endtask

task automatic push_subcode(input [7:0] seed);
	@(posedge clk);
	for (int i = 0; i < 96; i++) begin
		hps_subcode_byte <= seed + 8'(i);
		hps_subcode_push <= 1'b1;
		@(posedge clk);
	end
	hps_subcode_push <= 1'b0;
	@(posedge clk);
	hps_subcode_done <= 1'b1;
	@(posedge clk);
	hps_subcode_done <= 1'b0;
	@(posedge clk);
endtask

task automatic ring_put(input [23:0] base, input [7:0] off, input [7:0] b);
	mem[18'(base + 24'h200 + {16'h0, off})] = b;
endtask

int  edge_last = 0;
int  edge_gap  = 0;
int  now_cyc   = 0;
always @(posedge clk) begin
	now_cyc <= now_cyc + 1;
	if (!reset && u_dut.g_cd.cd_edge) begin
		edge_gap  <= now_cyc - edge_last;
		edge_last <= now_cyc;
	end
end

initial begin
	int cyc, t0, t1;
	logic [7:0] b0, b1, b;

	$display("tb_akiko_cmdflow starting");
	@(posedge clk);

	$display("--- Test 1: the drive answers ~1 ms after the last byte (PAL 28375, NTSC 28636 clocks) ---");
	for (int pass = 0; pass < 2; pass++) begin
		ntsc = pass[0];
		do_reset();
		bus_write_long(A_INTENA, 32'hF7000000);
		bus_write_long(A_MISC, 32'h00010000);
		ring_put(24'h010000, 8'd0, 8'h07);
		ring_put(24'h010000, 8'd1, 8'hF8);
		bus_write_long(A_FLAGS, CFG_TXD);
		bus_write_byte_lo(A_TXCMP, 8'd2);
		wait_parsed(6'd2, 20000, cyc);
		t0 = now_cyc;
		check_bit($sformatf("1.%0d.not_yet", pass), 1'b0, hps_cmd_pending);
		wait_pending(40000, cyc);
		t1 = now_cyc;
		if (pass == 0) check_range("1.0.turnaround_pal",  28370, 28385, t1 - t0);
		else           check_range("1.1.turnaround_ntsc", 28630, 28645, t1 - t0);
	end
	ntsc = 1'b0;

	$display("--- Test 2: no command executes while an enabled TXDMADONE waits for service ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hFF000000);
	bus_write_long(A_MISC, 32'h00010000);
	ring_put(24'h010000, 8'd0, 8'h07);
	ring_put(24'h010000, 8'd1, 8'hF8);
	bus_write_long(A_FLAGS, CFG_TXD);
	bus_write_byte_lo(A_TXCMP, 8'd2);
	wait_parsed(6'd2, 20000, cyc);
	repeat (40000) @(posedge clk);
	check_bit("2.txdone_set",  1'b1, u_dut.g_cd.cdrom_intreq[27]);
	check_bit("2.held",        1'b0, hps_cmd_pending);
	bus_write_byte_lo(A_TXCMP, 8'd2);
	repeat (4) @(posedge clk);
	check_bit("2.txdone_ack",  1'b0, u_dut.g_cd.cdrom_intreq[27]);
	check_bit("2.released",    1'b1, hps_cmd_pending);

	$display("--- Test 3: the next command is parsed only after the reply was delivered ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_MISC, 32'h00010000);
	ring_put(24'h010000, 8'd0, 8'h07);
	ring_put(24'h010000, 8'd1, 8'hF8);
	ring_put(24'h010000, 8'd2, 8'h01);
	ring_put(24'h010000, 8'd3, 8'h00);
	ring_put(24'h010000, 8'd4, 8'hFE);
	bus_write_long(A_FLAGS, CFG_TXD | CFG_RXD);
	bus_write_byte_lo(A_TXCMP, 8'd5);
	wait_pending(60000, cyc);
	check8 ("3.txinx_all", 8'd5, u_dut.g_cd.cdcomtxinx);
	hps_drain(2, b0, b1);
	check8 ("3.first_op",  8'h07, b0);
	repeat (40000) @(posedge clk);
	check_bit("3.second_held", 1'b0, hps_cmd_pending);
	check8 ("3.second_unparsed", 8'd0, {2'h0, u_dut.g_cd.cdrom_command_length});
	bus_write_byte_lo(A_RXCMP, 8'd3);
	hps_reply2(8'h07, 8'h01);
	wait_rx_idle(20000);
	check8 ("3.reply_delivered", 8'd2, u_dut.g_cd.cdcomrxinx);
	wait_pending(60000, cyc);
	check_bit("3.second_pending", 1'b1, hps_cmd_pending);
	hps_drain(3, b0, b1);
	check8 ("3.second_op",  8'h01, b0);
	check8 ("3.second_arg", 8'h00, b1);

	$display("--- Test 4: a reply is not exposed while an enabled TXDMADONE waits ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hFF000000);
	bus_write_long(A_MISC, 32'h00010000);
	ring_put(24'h010000, 8'd0, 8'h07);
	ring_put(24'h010000, 8'd1, 8'hF8);
	bus_write_long(A_FLAGS, CFG_TXD);
	bus_write_byte_lo(A_TXCMP, 8'd2);
	wait_parsed(6'd2, 20000, cyc);
	bus_write_byte_lo(A_TXCMP, 8'd2);
	wait_pending(40000, cyc);
	hps_drain(2, b0, b1);
	ring_put(24'h010000, 8'd2, 8'h05);
	ring_put(24'h010000, 8'd3, 8'h80);
	ring_put(24'h010000, 8'd4, 8'h7A);
	bus_write_byte_lo(A_TXCMP, 8'd5);
	repeat (8000) @(posedge clk);
	check_bit("4.txdone_again", 1'b1, u_dut.g_cd.cdrom_intreq[27]);
	hps_reply2(8'h07, 8'h01);
	check_bit("4.held",         1'b1, u_dut.g_cd.res_hold);
	check8 ("4.not_exposed",    8'd0, {2'h0, u_dut.g_cd.cdrom_receive_length});
	check_bit("4.rx_busy_seen", 1'b1, hps_rx_busy);
	check_bit("4.no_driverecv", 1'b0, u_dut.g_cd.cdrom_intreq[29]);
	bus_write_byte_lo(A_TXCMP, 8'd5);
	repeat (4) @(posedge clk);
	check_bit("4.released",     1'b0, u_dut.g_cd.res_hold);
	check8 ("4.exposed",        8'd2, {2'h0, u_dut.g_cd.cdrom_receive_length});
	check_bit("4.driverecv",    1'b1, u_dut.g_cd.cdrom_intreq[29]);

	$display("--- Test 5: DRIVEXMIT at cmd_done only for a valid no-reply command ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	pio_write(8'h05); pio_write(8'h00); pio_write(8'hFA);
	wait_pending(40000, cyc);
	u_dut.g_cd.cdrom_intreq[30] = 1'b0;
	hps_drain(3, b0, b1);
	check_bit("5.valid_led_xmit",  1'b1, u_dut.g_cd.cdrom_intreq[30]);
	check_bit("5.valid_led_noreply", 1'b0, u_dut.g_cd.cmd_wait_reply);
	pio_write(8'h05); pio_write(8'h00); pio_write(8'h00);
	wait_pending(40000, cyc);
	u_dut.g_cd.cdrom_intreq[30] = 1'b0;
	hps_drain(3, b0, b1);
	check_bit("5.bad_led_no_xmit", 1'b0, u_dut.g_cd.cdrom_intreq[30]);
	check_bit("5.bad_led_waits",   1'b1, u_dut.g_cd.cmd_wait_reply);

	$display("--- Test 6: PIO bytes are queued while the drive is busy, nothing is lost ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	pio_write(8'h07);
	check_bit("6.xmit_after_first", 1'b1, u_dut.g_cd.cdrom_intreq[30]);
	pio_write(8'hF8);
	check_bit("6.no_xmit_complete", 1'b0, u_dut.g_cd.cdrom_intreq[30]);
	wait_pending(40000, cyc);
	hps_drain(2, b0, b1);
	hps_reply2(8'h07, 8'h01);
	pio_write(8'h01);
	check8 ("6.queued",       8'd1, u_dut.g_cd.tx_fifo_wr - u_dut.g_cd.tx_fifo_rd);
	check8 ("6.not_parsed",   8'd0, {2'h0, u_dut.g_cd.cdrom_command_length});
	check_bit("6.no_xmit_busy", 1'b0, u_dut.g_cd.cdrom_intreq[30]);
	pio_read(b); check8("6.reply0", 8'h07, b);
	pio_read(b); check8("6.reply1", 8'h01, b);
	repeat (4) @(posedge clk);
	check_bit("6.xmit_after_reply", 1'b1, u_dut.g_cd.cdrom_intreq[30]);
	check8 ("6.parsed_late", 8'd1, {2'h0, u_dut.g_cd.cdrom_command_length});
	check8 ("6.byte_kept",   8'h01, u_dut.g_cd.cdrom_command_buffer[0]);

	$display("--- Test 7: a reply pushed while another is undelivered is dropped whole ---");
	do_reset();
	@(posedge clk); hps_result_byte <= 8'h11; hps_result_push <= 1;
	@(posedge clk); hps_result_byte <= 8'h22;
	@(posedge clk); hps_result_byte <= 8'h33;
	@(posedge clk); hps_result_byte <= 8'h44;
	@(posedge clk); hps_result_push <= 0;
	@(posedge clk); hps_result_done <= 1;
	@(posedge clk); hps_result_done <= 0;
	@(posedge clk);
	check8 ("7.first_len", 8'd4, {2'h0, u_dut.g_cd.cdrom_receive_length});
	hps_reply2(8'hEE, 8'hDD);
	check8 ("7.len_kept",  8'd4,  {2'h0, u_dut.g_cd.cdrom_receive_length});
	check8 ("7.byte0",     8'h11, u_dut.g_cd.cdrom_result_buffer[0]);
	check8 ("7.byte1",     8'h22, u_dut.g_cd.cdrom_result_buffer[1]);
	check8 ("7.wr_ptr",    8'd0,  {2'h0, u_dut.g_cd.hps_result_wr_ptr});
	check_bit("7.no_drop_left", 1'b0, u_dut.g_cd.res_drop);

	$display("--- Test 8: two interrupt sources in the same clock are both kept ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	u_dut.g_cd.cdrom_intreq[27] = 1'b1;
	@(posedge clk); hps_result_byte <= 8'h06; hps_result_push <= 1;
	@(posedge clk); hps_result_push <= 0;
	@(posedge clk);
	cs <= 1; wr <= 1; addr <= A_TXCMP; din <= 16'h0001; lds <= 1; uds <= 0;
	hps_result_done <= 1;
	@(posedge clk);
	cs <= 0; wr <= 0; addr <= 0; din <= 0; lds <= 0;
	hps_result_done <= 0;
	@(posedge clk);
	check_bit("8.txdone_cleared", 1'b0, u_dut.g_cd.cdrom_intreq[27]);
	check_bit("8.driverecv_set",  1'b1, u_dut.g_cd.cdrom_intreq[29]);

	$display("--- Test 9: STOP and MULTI drop the prefetched sector, other commands do not ---");
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	push_sector(8'h40);
	check_bit("9.ready", 1'b1, u_dut.g_cd.sector_ready);
	pio_write(8'h07); pio_write(8'hF8);
	wait_pending(40000, cyc);
	hps_drain(2, b0, b1);
	check_bit("9.info_keeps", 1'b1, u_dut.g_cd.sector_ready);
	hps_reply2(8'h07, 8'h01);
	pio_read(b); pio_read(b);
	pio_write(8'h01); pio_write(8'h00); pio_write(8'h00);
	wait_pending(40000, cyc);
	hps_drain(3, b0, b1);
	check_bit("9.bad_stop_keeps", 1'b1, u_dut.g_cd.sector_ready);
	hps_reply2(8'h05, 8'h89);
	pio_read(b); pio_read(b);
	pio_write(8'h01); pio_write(8'h00); pio_write(8'hFE);
	wait_pending(40000, cyc);
	hps_drain(3, b0, b1);
	check_bit("9.stop_flushes", 1'b0, u_dut.g_cd.sector_ready);

	$display("--- Test 10: sectors ship on the 75 Hz grid; a late push mid-stream catches up ---");
	cd_speed = 2'b00;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	bus_write_word(A_PBX, 16'h000F);
	while (u_dut.g_cd.cd_tick_cnt != 19'd100000) @(posedge clk);
	push_sector(8'h10);
	repeat (1000) @(posedge clk);
	check_bit("10.waits_for_edge", 1'b0, u_dut.g_cd.pbx_busy);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	check_range("10.first_on_edge", 0, 2, u_dut.g_cd.cd_tick_cnt);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.cd_tick_cnt != 19'd1000) @(posedge clk);
	while (u_dut.g_cd.cd_tick_cnt != 19'd200000) @(posedge clk);
	while (u_dut.g_cd.cd_tick_cnt != 19'd10) @(posedge clk);
	check_bit("10.owed", 1'b1, u_dut.g_cd.cd_owed);
	repeat (5000) @(posedge clk);
	push_sector(8'h20);
	repeat (3) @(posedge clk);
	check_bit("10.late_catches_up", 1'b1, u_dut.g_cd.pbx_busy);
	check_range("10.late_off_grid", 5000, 378335, u_dut.g_cd.cd_tick_cnt);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	bus_write_word(A_PBX, 16'h0000);
	bus_write_long(A_FLAGS, CFG_ENA);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	repeat (400000) @(posedge clk);
	check_bit("10.idle_no_owed", 1'b0, u_dut.g_cd.cd_owed);

	$display("--- Test 11: the CD clock does not follow the NTSC system clock ---");
	ntsc = 1'b0;
	while (!u_dut.g_cd.cd_edge) @(posedge clk);
	repeat (2) @(posedge clk);
	while (!u_dut.g_cd.cd_edge) @(posedge clk);
	repeat (2) @(posedge clk);
	check_range("11.pal_period",  378335, 378335, edge_gap);
	ntsc = 1'b1;
	while (!u_dut.g_cd.cd_edge) @(posedge clk);
	repeat (2) @(posedge clk);
	while (!u_dut.g_cd.cd_edge) @(posedge clk);
	repeat (2) @(posedge clk);
	check_range("11.ntsc_period", 381818, 381818, edge_gap);
	ntsc = 1'b0;

	$display("--- Test 12: the subcode frame of a data sector goes out after its sector ---");
	cd_speed = 2'b00;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_MISC, 32'h00030000);
	bus_write_long(A_FLAGS, CFG_SUB | CFG_ENA | CFG_PBX);
	bus_write_word(A_PBX, 16'h0001);
	while (u_dut.g_cd.cd_tick_cnt != 19'd100000) @(posedge clk);
	push_sector(8'h30);
	push_subcode(8'h80);
	repeat (2000) @(posedge clk);
	check_bit("12.sub_waits", 1'b0, u_dut.g_cd.subcode_busy);
	check_bit("12.sub_no_irq", 1'b0, u_dut.g_cd.subcode_irq);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	repeat (2000) @(posedge clk);
	check_bit("12.sub_after", 1'b1, u_dut.g_cd.subcode_irq);
	check8 ("12.sub_byte0", 8'h80, mem[18'h30100 + 18'd128]);

	$display("--- Test 13: an empty PIO read returns the last byte moved by RX DMA ---");
	cd_speed = 2'b11;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_MISC, 32'h00010000);
	bus_write_long(A_FLAGS, CFG_RXD);
	bus_write_byte_lo(A_RXCMP, 8'd2);
	hps_reply2(8'h0A, 8'h83);
	wait_rx_idle(20000);
	check8 ("13.rx_mem1", 8'h83, mem[18'h10001]);
	bus_write_long(A_FLAGS, 32'h0);
	pio_read(b);
	check8 ("13.idle_value", 8'h83, b);

	$display("--- Test 14: the queue takes four sectors ahead of the grid and ships them in order ---");
	cd_speed = 2'b00;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	repeat (4) @(posedge clk);
	check_bit("14.req_empty", 1'b1, hps_sec_req);
	push_sector(8'h01); push_sector(8'h11); push_sector(8'h21); push_sector(8'h31);
	check_bit("14.req_full", 1'b0, hps_sec_req);
	check8 ("14.status_next", 8'd4, hps_sec_status[7:0]);
	push_sector(8'hEE);
	check8 ("14.status_refused", 8'd4, hps_sec_status[7:0]);
	bus_write_word(A_PBX, 16'h000F);
	for (int k = 0; k < 4; k++) begin
		while (!u_dut.g_cd.pbx_busy) @(posedge clk);
		check_range($sformatf("14.on_grid_%0d", k), 0, 2, u_dut.g_cd.cd_tick_cnt);
		while (u_dut.g_cd.pbx_busy) @(posedge clk);
		if (k == 0) begin
			repeat (4) @(posedge clk);
			check_bit("14.req_room", 1'b1, hps_sec_req);
			check8 ("14.status_kept", 8'd4, hps_sec_status[7:0]);
		end
	end
	check8 ("14.slot3", 8'h05, mem[18'h23004]);
	check8 ("14.slot2", 8'h15, mem[18'h22004]);
	check8 ("14.slot1", 8'h25, mem[18'h21004]);
	check8 ("14.slot0", 8'h35, mem[18'h20004]);
	check8 ("14.counter", 8'd4, u_dut.g_cd.cdrom_sector_counter[7:0]);

	$display("--- Test 15: with sectors queued, each subcode frame goes out right after its own sector ---");
	cd_speed = 2'b00;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_MISC, 32'h00030000);
	bus_write_long(A_FLAGS, CFG_SUB | CFG_ENA | CFG_PBX);
	push_sector(8'h40); push_subcode(8'hA0);
	push_sector(8'h50); push_subcode(8'hB0);
	check8 ("15.queued", 8'd2, hps_sec_status[7:0]);
	check_bit("15.no_sub_yet", 1'b0, u_dut.g_cd.subcode_busy);
	bus_write_word(A_PBX, 16'h0003);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	while (!u_dut.g_cd.subcode_busy && !u_dut.g_cd.pbx_busy) @(posedge clk);
	check_bit("15.sub_before_next", 1'b1, u_dut.g_cd.subcode_busy);
	while (u_dut.g_cd.subcode_busy) @(posedge clk);
	check8 ("15.sub_a", 8'hA0, mem[18'h30100 + 18'd128]);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	repeat (2000) @(posedge clk);
	check8 ("15.sub_b", 8'hB0, mem[18'h30100]);
	check8 ("15.sec_a", 8'h44, mem[18'h21004]);
	check8 ("15.sec_b", 8'h54, mem[18'h20004]);

	$display("--- Test 16: STOP drops every queued sector, the Main is asked again from the shipped count ---");
	cd_speed = 2'b00;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	push_sector(8'h60); push_sector(8'h70); push_sector(8'h80);
	check8 ("16.queued", 8'd3, hps_sec_status[7:0]);
	pio_write(8'h01); pio_write(8'h00); pio_write(8'hFE);
	wait_pending(40000, cyc);
	hps_drain(3, b0, b1);
	repeat (2) @(posedge clk);
	check_bit("16.flushed", 1'b0, u_dut.g_cd.sector_ready);
	check8 ("16.status_shipped", 8'd0, hps_sec_status[7:0]);
	check_bit("16.req_again", 1'b1, hps_sec_req);

	$display("--- Test 17: ENABLE again during a ship: the ship completes, the queue restarts from sector 0 ---");
	cd_speed = 2'b11;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	push_sector(8'h90); push_sector(8'hA0);
	bus_write_word(A_PBX, 16'h0001);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	repeat (100) @(posedge clk);
	bus_write_long(A_FLAGS, CFG_PBX);
	bus_write_long(A_FLAGS, CFG_ENA | CFG_PBX);
	repeat (2) @(posedge clk);
	check_bit("17.still_shipping", 1'b1, u_dut.g_cd.pbx_busy);
	check8 ("17.status_zero", 8'd0, hps_sec_status[7:0]);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	repeat (4) @(posedge clk);
	check8 ("17.counter_zero", 8'd0, u_dut.g_cd.cdrom_sector_counter[7:0]);
	check_bit("17.empty", 1'b0, u_dut.g_cd.sector_ready);
	check8 ("17.status_after", 8'd0, hps_sec_status[7:0]);
	check_bit("17.req", 1'b1, hps_sec_req);

	$display("--- Test 18: a subcode frame that arrives after its sector left goes out on its own ---");
	cd_speed = 2'b11;
	do_reset();
	bus_write_long(A_INTENA, 32'hF7000000);
	bus_write_long(A_DATA, 32'h00020000);
	bus_write_long(A_MISC, 32'h00030000);
	bus_write_long(A_FLAGS, CFG_SUB | CFG_ENA | CFG_PBX);
	bus_write_word(A_PBX, 16'h0003);
	push_sector(8'hC0);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.pbx_busy) @(posedge clk);
	push_subcode(8'hD0);
	repeat (3000) @(posedge clk);
	check_bit("18.after_irq", 1'b1, u_dut.g_cd.subcode_irq);
	check8 ("18.after_byte0", 8'hD0, mem[18'h30100 + 18'd128]);
	push_sector(8'hE0);
	while (!u_dut.g_cd.pbx_busy) @(posedge clk);
	while (u_dut.g_cd.pbx_state != 3'd4) @(posedge clk);
	push_subcode(8'hF0);
	repeat (3000) @(posedge clk);
	check8 ("18.during_byte0", 8'hF0, mem[18'h30100]);
	check_bit("18.queue_empty", 1'b0, u_dut.g_cd.sector_ready);
	check_bit("18.no_hold", 1'b0, u_dut.g_cd.sub_hold);

	$display("------------------------------------");
	$display("checks=%0d errors=%0d", checks, errs);
	if (errs == 0) $display("tb_akiko_cmdflow PASS");
	else           $display("tb_akiko_cmdflow FAIL");
	$finish(errs == 0 ? 0 : 1);
end

endmodule
