`timescale 1ns/1ps

module ditto_tb;

	localparam integer EXPECTED_RESULT_COUNT = 16;
	localparam integer TIMEOUT_CYCLES = 2000;

	reg clk;
	reg reset;

`ifdef DEBUG
	wire debug_queue_valid;
	wire [15:0] debug_data_queue;
	wire [31:0] debug_weight_queue;
	wire [ 1:0] debug_meta_data;
	wire [ 1:0] debug_carry_comps;
	wire debug_pe_result_valid;
	wire [17:0] debug_pe_result;
	wire debug_result_valid;
	wire [31:0] debug_result;
`endif

	integer cycle_count;
	integer result_count;
	reg compute_finish_d;

	ditto_top dut (
		.clk(clk),
		.reset(reset)

`ifdef DEBUG
		,
		.debug_queue_valid(debug_queue_valid),
		.debug_data_queue(debug_data_queue),
		.debug_weight_queue(debug_weight_queue),
		.debug_meta_data(debug_meta_data),
		.debug_carry_comps(debug_carry_comps),
		.debug_pe_result_valid(debug_pe_result_valid),
		.debug_pe_result(debug_pe_result),
		.debug_result_valid(debug_result_valid),
		.debug_result(debug_result)
`endif
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	initial begin
		reset = 1'b1;
		cycle_count = 0;
		result_count = 0;
		compute_finish_d = 1'b0;

`ifdef DEBUG
		$dumpfile("build/ditto_tb.vcd");
		$dumpvars(0, ditto_tb);
`endif

		repeat (4) @(posedge clk);
		reset = 1'b0;
	end

	always @(posedge clk) begin
		cycle_count <= cycle_count + 1;
		if (reset) begin
			compute_finish_d <= 1'b0;
			result_count <= 0;
		end
		else begin
			compute_finish_d <= dut.u_compute_unit.finish;
		end

`ifdef DEBUG
		if (debug_pe_result_valid) begin
			$display("[%0t] pe result=%h", $time, debug_pe_result);
		end

		if (debug_queue_valid) begin
			$display("[%0t] queue commit meta=%b carry_comps=%b data=%h weight=%h", $time, debug_meta_data, debug_carry_comps, debug_data_queue, debug_weight_queue);
		end
`endif

		if (!reset && dut.u_compute_unit.finish && !compute_finish_d) begin
			result_count <= result_count + 1;
`ifdef DEBUG
			$display("[%0t] debug result=%h full=%h", $time, debug_result, dut.result);
`else
			$display("[%0t] result=%h", $time, dut.result);
`endif
			if (result_count + 1 == EXPECTED_RESULT_COUNT) begin
				$display("[%0t] finish simulation", $time);
				$finish;
			end
		end

		if (!reset && cycle_count > TIMEOUT_CYCLES && result_count < EXPECTED_RESULT_COUNT) begin
			$display("[%0t] ERROR: simulation timeout", $time);
			$finish;
		end
	end

endmodule
