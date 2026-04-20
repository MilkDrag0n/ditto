`timescale 1ns/1ps

module ditto_tb;

	reg clk;
	reg reset;

`ifdef DEBUG
	wire debug_queue_valid;
	wire [15:0] debug_data_queue;
	wire [31:0] debug_weight_queue;
	wire debug_result_valid;
	wire [15:0] debug_result;
`endif

	integer cycle_count;
	reg compute_finish_d;
	reg seen_result;

	ditto_top dut (
		.clk(clk),
		.reset(reset)

`ifdef DEBUG
		,
		.debug_queue_valid(debug_queue_valid),
		.debug_data_queue(debug_data_queue),
		.debug_weight_queue(debug_weight_queue),
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
		compute_finish_d = 1'b0;
		seen_result = 1'b0;

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
		end
		else begin
			compute_finish_d <= dut.u_compute_unit.finish;
		end

`ifdef DEBUG
		if (debug_queue_valid) begin
			$display("[%0t] queue commit data=%h weight=%h", $time, debug_data_queue, debug_weight_queue);
		end
`endif

		if (!reset && dut.u_compute_unit.finish && !compute_finish_d) begin
			seen_result <= 1'b1;
`ifdef DEBUG
			$display("[%0t] result valid debug=%h full=%h", $time, debug_result, dut.result);
`else
			$display("[%0t] result valid full=%h", $time, dut.result);
`endif
		end

		if (!reset && cycle_count > 200 && !seen_result) begin
			$display("[%0t] ERROR: simulation timeout", $time);
			$finish;
		end

		if (seen_result) begin
			$display("[%0t] finish simulation", $time);
			$finish;
		end
	end

endmodule
