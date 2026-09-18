// Simulation stand-in for the Altera primitive, so the Denise hierarchy can be
// elaborated outside Quartus. Only the dual-port shape Denise's colour table
// asks for is modelled; nothing in tools/aga tests the colour table itself.
// Not in files.qip - Quartus uses the real megafunction.
module altsyncram (
  input  [7:0]  address_a, address_b,
  input  [3:0]  byteena_a, byteena_b,
  input         clock0, clock1, clocken0, clocken1, clocken2, clocken3,
  input         aclr0, aclr1, addressstall_a, addressstall_b,
  input  [31:0] data_a, data_b,
  input         wren_a, wren_b, rden_a, rden_b,
  output [31:0] q_a, q_b,
  output [1:0]  eccstatus
);

parameter address_aclr_b = "", address_reg_b = "", byte_size = 8;
parameter clock_enable_input_a = "", clock_enable_input_b = "", clock_enable_output_b = "";
parameter intended_device_family = "", lpm_type = "";
parameter numwords_a = 256, numwords_b = 256, operation_mode = "";
parameter outdata_aclr_b = "", outdata_reg_b = "", power_up_uninitialized = "";
parameter read_during_write_mode_mixed_ports = "";
parameter width_a = 32, width_b = 32, width_byteena_a = 4;
parameter widthad_a = 8, widthad_b = 8;

reg [31:0] mem [0:255];
reg [31:0] rq;

always @(posedge clock0) if (clocken0) begin
	if (wren_a) mem[address_a] <= data_a;
	rq <= mem[address_b];
end

assign q_b = rq;
assign q_a = 32'd0;
assign eccstatus = 2'd0;

endmodule
