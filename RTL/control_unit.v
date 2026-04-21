`timescale 1ns/1ps

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

	reg need_finish;
	assign fetch = encode_fetch & ~finish;

	always@(posedge clk) begin
		if(reset | finish) begin
			finish <= 1'b0;
			need_finish <= 1'b0;
		end
		else if(fetch) begin
			if(weight_addr[3:0] == 4'b1111) begin
				need_finish   <= 1'b1;
			end
			if(need_finish) begin
				need_finish   <= 1'b0;
				finish <= 1'b1;
			end
		end
	end

	always@(posedge clk) begin
		if(reset) begin
			data_pst_addr <= 8'b0000_0000;
			data_now_addr <= 8'b0000_0000;
			weight_addr   <= 8'b0000_0000;
		end
		else if (fetch & ~need_finish) begin
			data_pst_addr <= data_pst_addr + 1'b1;
			data_now_addr <= data_now_addr + 1'b1;
			weight_addr   <= weight_addr   + 1'b1;
		end
	end

endmodule
