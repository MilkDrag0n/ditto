module mini_cache (
	input  clk,
	input  reset,
	input  fetch,
	input  [7:0] data_pst_addr,
	input  [7:0] data_now_addr,
	input  [7:0] weight_addr,
	output reg input_data_valid,
	output reg [7:0] input_data_pst,
	output reg [7:0] input_data_now,
	output reg [7:0] input_weight
);

	localparam DEPTH = 256;

	reg [7:0] data_pst_mem [0:DEPTH-1];
	reg [7:0] data_now_mem [0:DEPTH-1];
	reg [7:0] weight_mem   [0:DEPTH-1];

	integer i;
	initial begin
		data_pst_mem[15:0] = {
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4
		};
		data_now_mem[15:0] = {
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4
		};
		weight[15:0] = {
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4,
			8'd1, 8'd2, 8'd3, 8'd4
		};

		for (i = 16; i < DEPTH; i = i + 1) begin
			data_pst_mem[i] = i[7:0];
			data_now_mem[i] = i[7:0] + 8'd1;
			weight_mem[i]   = 8'h01;
		end
	end

	always @(posedge clk) begin
		if (reset) begin
			input_data_valid <= 1'b0;
			input_data_pst <= 8'b0;
			input_data_now <= 8'b0;
			input_weight <= 8'b0;
		end
		else begin
			input_data_valid <= fetch;
			if (fetch) begin
				input_data_pst <= data_pst_mem[data_pst_addr];
				input_data_now <= data_now_mem[data_now_addr];
				input_weight <= weight_mem[weight_addr];
			end
		end
	end

endmodule
