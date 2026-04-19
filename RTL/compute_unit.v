// 使用基于加法树的乘法与累加（MAC）单元, 支持全位宽（8位）和低位宽（4位）操作
// 基准乘法器: 4-bit * weight
// 使用两个乘法器和移位逻辑来支持 8 位激活值 (可以在重排的时候把4和8分开/)
// 需要使用多个计算单元以计算最大吞吐量(感觉可以根据文章数据来计算)
module compute_unit (
	input clk,
	input reset,
	input flush, // 清空 partial sum
	input  [49:0] encoding_bus  // {meta_data, weight_queue, data_queue}
	input  encode_ready,
	output compute_fetch,
	output [31:0] result
);
	reg [1:0] meta_data;
	reg [31:0] weight_queue;
	reg [15:0] data_queue;

	wire [3:0] mul_src1;
	wire [3:0] mul_src2;
	wire [3:0] mul_src3;
	wire [3:0] mul_src4;
	wire [7:0] weight1;
	wire [7:0] weight2;
	wire [7:0] weight3;
	wire [7:0] weight4;

	wire [15:0] mul_res1;
	wire [15:0] mul_res2;
	wire [15:0] mul_res3;
	wire [15:0] mul_res4;

	wire [31:0] pe_res;
	reg  [31:0] res_reg;

	always @(posedge clk) begin
		if(reset) begin
			meta_data <= 0;
			weight_queue <= 0;
			data_queue <= 0;
		end
		else if(encode_ready & compute_fetch) begin
			{meta_data, weight_queue, data_queue} <= encoding_bus;
		end
	end
	// PE计算单元
	assign {mul_src4, mul_src3, mul_src2, mul_src1} = data_queue;
	assign {weight4, weight3, weight2, weight1} = weight_queue;
	assign mul_res1 = mul_src1 * weight1;
	assign mul_res2 = mul_src2 * weight2;
	assign mul_res3 = mul_src3 * weight3;
	assign mul_res4 = mul_src4 * weight4;
	assign pe_res   = (meta_data[0] ? (mul_res1 << 4) : mul_res1) + mul_res2
					+ (meta_data[1] ? (mul_res3 << 4) : mul_res3) + mul_res4;

	// partial sum
	always @(posedge clk) begin
		if(reset | flush) begin
			res_reg <= 32'b0;
		end
		else if(encode_ready & compute_fetch) begin
			res_reg <= res_reg + pe_res;
		end
	end




endmodule
