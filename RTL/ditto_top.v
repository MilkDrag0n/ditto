`timescale 1ns/1ps

module ditto_top (
	input  clk,
	input  reset

`ifdef DEBUG
	,
	output debug_queue_valid,
	output [15:0] debug_data_queue,
	output [31:0] debug_weight_queue,
	output [ 1:0] debug_meta_data,
	output debug_pe_result_valid,
	output [17:0] debug_pe_result,
	output debug_result_valid,
	output [31:0] debug_result
`endif

);

	wire finish;
	wire encode_fetch;
	wire encode_ready;
	wire compute_fetch;
	wire fetch;
	wire input_data_valid;
	wire [ 7:0] data_pst_addr;
	wire [ 7:0] data_now_addr;
	wire [ 7:0] weight_addr;
	wire [ 7:0] input_data_pst;
	wire [ 7:0] input_data_now;
	wire [ 7:0] input_weight;
	wire [23:0] fetch_data;
	wire [50:0] encoding_bus;
	wire [31:0] result;

	control_unit u_control_unit (
		.clk(clk),
		.reset(reset),
		.encode_fetch(encode_fetch),
		.finish(finish),
		.fetch(fetch),
		.data_pst_addr(data_pst_addr),
		.data_now_addr(data_now_addr),
		.weight_addr(weight_addr)
	);

	mini_cache u_mini_cache (
		.clk(clk),
		.reset(reset),
		.fetch(fetch),
		.data_pst_addr(data_pst_addr),
		.data_now_addr(data_now_addr),
		.weight_addr(weight_addr),
		.input_data_valid(input_data_valid),
		.input_data_pst(input_data_pst),
		.input_data_now(input_data_now),
		.input_weight(input_weight)
	);

	assign fetch_data = {input_data_pst, input_data_now, input_weight};

	encoding_unit u_encoding_unit (
		.clk(clk),
		.reset(reset),
		.finish(finish),
		.input_data_valid(input_data_valid),
		.fetch_data(fetch_data),
		.encode_fetch(encode_fetch),
		.encode_ready(encode_ready),
		.compute_fetch(compute_fetch),
		.encoding_bus(encoding_bus)

	`ifdef DEBUG
		,
		.debug_queue_valid(debug_queue_valid),
		.debug_data_queue(debug_data_queue),
		.debug_weight_queue(debug_weight_queue),
		.debug_meta_data(debug_meta_data)
	`endif

	);

	compute_unit u_compute_unit (
		.clk(clk),
		.reset(reset),
		.encoding_bus(encoding_bus),
		.encode_ready(encode_ready),
		.compute_fetch(compute_fetch),
		.result(result)

	`ifdef DEBUG
		,
		.debug_pe_result_valid(debug_pe_result_valid),
		.debug_pe_result(debug_pe_result),
		.debug_result_valid(debug_result_valid),
		.debug_result(debug_result)
	`endif

	);


endmodule
