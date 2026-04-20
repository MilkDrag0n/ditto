`timescale 1ns/1ps

// 支持全位宽（8位）和低位宽（4位）操作
// 使用两个乘法器 (4bit * 8bit) 和移位逻辑来支持8位激活值 (可以在重排的时候把4和8分开/)
// 如果是8bit负数, 需要使用进位补偿: Value = 16 * H_signed + L_signed + 16 * b_3
// compensation_data = 16 * b_3 * weight
module compute_unit (
	input clk,
	input reset,
	input  [52:0] encoding_bus,  // {finish, carry_comps, meta_data, weight_queue, data_queue}
	input  encode_ready,
	output compute_fetch,
	output [31:0] result

`ifdef DEBUG
	,
	output debug_pe_result_valid,
	output [17:0] debug_pe_result,
	output debug_result_valid,
	output [31:0] debug_result
`endif

);
	reg finish; // 清空 partial sum
	reg [ 1:0] carry_comps;
	reg [ 1:0] meta_data;
	reg [31:0] weight_queue;
	reg [15:0] data_queue;

	wire [11:0] comp_data;

	wire signed [3:0] mul_src1;
	wire signed [3:0] mul_src2;
	wire signed [3:0] mul_src3;
	wire signed [3:0] mul_src4;
	wire signed [7:0] weight1;
	wire signed [7:0] weight2;
	wire signed [7:0] weight3;
	wire signed [7:0] weight4;

	wire signed [15:0] mul_res1;
	wire signed [15:0] mul_res2;
	wire signed [15:0] mul_res3;
	wire signed [15:0] mul_res4;

	wire [17:0] mul_res1_ext;
	wire [17:0] mul_res2_ext;
	wire [17:0] mul_res3_ext;
	wire [17:0] mul_res4_ext;

	wire [17:0] pe_res;
	reg  [31:0] res_reg;

	// control
	assign compute_fetch = 1'b1;

	// 流水线寄存器
	always @(posedge clk) begin
		if(reset) begin
			finish <= 1'b0;
			meta_data <= 2'b0;
			weight_queue <= 32'b0;
			data_queue <= 16'b0;
			carry_comps <= 2'b0;
		end
		else if(encode_ready & compute_fetch) begin
			{finish, carry_comps, meta_data, weight_queue, data_queue} <= encoding_bus;
		end
	end

	// PE计算单元
	assign {mul_src4, mul_src3, mul_src2, mul_src1} = data_queue;
	assign {weight4, weight3, weight2, weight1} = weight_queue;
	assign mul_res1 = mul_src1 * weight1;
	assign mul_res2 = mul_src2 * weight2;
	assign mul_res3 = mul_src3 * weight3;
	assign mul_res4 = mul_src4 * weight4;

	assign mul_res1_ext = {{2{mul_res1[15]}}, mul_res1};
	assign mul_res2_ext = {{2{mul_res2[15]}}, mul_res2};
	assign mul_res3_ext = {{2{mul_res3[15]}}, mul_res3};
	assign mul_res4_ext = {{2{mul_res4[15]}}, mul_res4};

	assign comp_data = (((carry_comps[0] & mul_src1[3]) ? weight1 : 0)
					 + ((carry_comps[1] & mul_src3[3]) ? weight3 : 0)) << 4;

	assign pe_res   = (meta_data[0] ? (mul_res2_ext << 4) : mul_res2_ext) + mul_res1_ext
					+ (meta_data[1] ? (mul_res4_ext << 4) : mul_res4_ext) + mul_res3_ext
					+ comp_data;

	// partial sum
	always @(posedge clk) begin
		if(reset | finish) begin
			res_reg <= 32'b0;
		end
		else if(encode_ready & compute_fetch) begin
			res_reg <= res_reg + {{14{pe_res[17]}}, pe_res};
		end
	end

	assign result = res_reg + pe_res;

`ifdef DEBUG
	reg pe_result_valid;
	always @(posedge clk) begin
		if(reset) begin
			pe_result_valid <= 1'b0;
		end
		else if(encode_ready & compute_fetch) begin
			pe_result_valid <= 1'b1;
		end
		else begin
			pe_result_valid <= 1'b0;
		end
	end

	reg have_finished;
	always @(posedge clk) begin
		if(reset | ~finish) begin
			have_finished <= 1'b0;
		end
		else if(finish) begin
			have_finished <= 1'b1;
		end
	end

	assign debug_pe_result_valid = pe_result_valid & ~have_finished;
	assign debug_pe_result = pe_res;

	assign debug_result_valid = finish & ~have_finished;
	assign debug_result = result;

`endif


endmodule
