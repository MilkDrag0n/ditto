module control_unit(
	input  clk,
	input  reset,
	input  encode_fetch,
	output reg finish,
	output fetch,
	output reg [ 7:0] data_pst_addr,
	output reg [ 7:0] data_now_addr,
	output reg [ 7:0] weight_addr

);

	assign fetch = encode_fetch & ~finish;

	always@(posedge clk) begin
		if(reset) begin
			data_pst_addr <= 8'b0000_0000;
			data_now_addr <= 8'b0000_0000;
			weight_addr   <= 8'b0000_0000;
		end
		else if (fetch) begin
			data_pst_addr <= data_pst_addr + 2'b10;
			data_now_addr <= data_now_addr + 2'b10;
			weight_addr   <= weight_addr   + 2'b10;
		end
	end

	always@(posedge clk) begin
		if(reset) begin
			finish <= 1'b1;
		end
		else if(data_pst_addr == 8'b0000_1000) begin  // 计算 16 组数然后提交
			finish <= 1'b0;
		end
	end


endmodule
