// 在这种同样利用空间差异的硬件中，只需要一个偏移寄存器来存储空间偏移量，以及一个多路复用器来将前一时间步的输入切换为空间偏移量。
module encoding_unit(
	input clk,
	input reset,
	input [ 7:0] input_data_pst,
	input [ 7:0] input_data_now,
	input [ 7:0] input_weight,
	input input_data_valid,
	output encode_fetch, // 取数据, {input_data_valid, encode_fetch} = 01->11->11->...->00
	output encode_ready, // full
	input compute_fetch,
	output [49:0] encoding_bus  // {meta_data, weight_queue, data_queue}
);

	reg 		diff_ready;  // 第一拍差分完成
	reg  [ 1:0] control_signal;
	wire [ 7:0] data_diff;
	reg  [ 7:0] data_diff_reg;
	reg  [ 7:0] weight_reg;
	reg  [31:0] weight_queue;
	reg  [ 7:0] weight_buffer;
	reg  [15:0] data_queue;  //
	reg  [ 3:0] data_buffer; // 溢出的只会是低位
	reg  [ 3:0] data_queue_status;
	reg  [ 1:0] meta_data;
	reg         buffer_valid;
	wire 		queue_full;
	wire 		commit_buffer;
	
	// control
	assign encode_fetch = ~queue_full;
	assign encode_ready = queue_full;
	assign queue_full = &data_queue_status;
	assign encoding_bus = {meta_data, weight_queue, data_queue};
	assign commit_buffer = encode_ready & compute_fetch & buffer_valid;

	// 计算差分, 比较分类 00: 0bit, 01: 4bit, 1x:8bit
	// 文章图片显示的是无符号的处理方法,但是实际上得是有符号的
	assign data_diff = input_data_now - input_data_pst;

	always @(posedge clk) begin
		if(reset) begin
			control_signal <= 2'b0;
			diff_ready <= 1'b0;
			weight_reg <= 8'b0;
			data_diff_reg <= 8'b0;
		end
		else if(input_data_valid) begin
			control_signal[1] <= (data_diff[7:4] != {4{data_diff[3]}});
			control_signal[0] <= (data_diff[3:0] != 4'b0);
			diff_ready <= (data_diff != 8'b0);
			weight_reg <= input_weight;
			data_diff_reg <= data_diff;
		end else begin
			diff_ready <= 1'b0;
		end
	end


	// 重排入队
	// 需要写一个队列, 4条4bit, 第1、3条可以表示高位,用meta_data记录
	always @(posedge clk) begin 
		if(reset) begin
			data_queue_status <= 4'b0;
			meta_data <= 2'b0;
			data_queue <= 16'b0;
			weight_queue <= 32'b0;
			buffer_valid <= 1'b0;
			data_buffer <= 4'b0;
			weight_buffer <= 8'b0;
		end
		else begin
			if(encode_ready & compute_fetch & ~diff_ready) begin
				if(buffer_valid) begin
					data_queue_status <= 4'b0001;
					data_queue <= {12'b0, data_buffer};
					weight_queue <= {24'b0, weight_buffer};
				end
				else begin
					data_queue_status <= 4'b0;
					data_queue <= 16'b0;
					weight_queue <= 32'b0;
				end
				meta_data <= 2'b0;
				buffer_valid <= 1'b0;
				data_buffer <= 4'b0;
				weight_buffer <= 8'b0;
			end
			else if (diff_ready) begin
				if(encode_ready & compute_fetch) begin
					if(buffer_valid) begin
						casex(control_signal)
							2'b01: begin
								data_queue_status <= 4'b0011;
								data_queue <= {8'b0, data_diff_reg[3:0], data_buffer};
								meta_data <= 2'b00;
								weight_queue <= {16'b0, weight_reg, weight_buffer};
								buffer_valid <= 1'b0;
								data_buffer <= 4'b0;
								weight_buffer <= 8'b0;
							end
							2'b1x: begin
								// 0001填成0111
								data_queue_status <= 4'b0111;
								data_queue <={4'b0, data_diff_reg[3:0], data_diff_reg[7:4], data_buffer};
								meta_data <= 2'b01;
								weight_queue <= {8'b0, {2{weight_reg}}, weight_buffer};
								buffer_valid <= 1'b0;
								data_buffer <= 4'b0;
								weight_buffer <= 8'b0;
							end
						endcase						
					end
					else begin
						casex(control_signal)
							2'b01: begin
								data_queue_status <= 4'b0001;
								data_queue <= {12'b0, data_diff_reg[3:0]};
								meta_data <= 2'b00;
								weight_queue <= {24'b0, weight_reg};
								buffer_valid <= 1'b0;
								data_buffer <= 4'b0;
								weight_buffer <= 8'b0;
							end
							2'b1x: begin
								// 0000填成0011
								data_queue_status <= 4'b0011;
								data_queue <={8'b0, data_diff_reg};
								meta_data <= 2'b01;
								weight_queue <= {16'b0, {2{weight_reg}}};
								buffer_valid <= 1'b0;
								data_buffer <= 4'b0;
								weight_buffer <= 8'b0;
							end
						endcase	
					end
				end
				else begin
					casex(control_signal) 
						2'b01: begin
							if(~data_queue_status[0]) begin
								data_queue_status[0] <= 1'b1;
								data_queue[3:0] <= data_diff_reg[3:0];
								weight_queue[7:0] <= weight_reg;
							end
							else if(~data_queue_status[1]) begin
								data_queue_status[1] <= 1'b1;
								data_queue[7:4] <= data_diff_reg[3:0];
								weight_queue[15:8] <= weight_reg;
							end
							else if(~data_queue_status[2]) begin
								data_queue_status[2] <= 1'b1;
								data_queue[11:8] <= data_diff_reg[3:0];
								weight_queue[23:16] <= weight_reg;
							end
							else if (~data_queue_status[3]) begin
								data_queue_status[3] <= 1'b1;
								data_queue[15:12] <= data_diff_reg[3:0];
								weight_queue[31:24] <= weight_reg;
							end
							// 满了, 不允许这种情况
						end
						2'b1x: begin
							// 0000填成0011
							if(data_queue_status == 4'b0000) begin
								data_queue_status[1:0] <= 2'b11;
								data_queue[7:0] <= data_diff_reg;
								meta_data[0] <= 1'b1;
								weight_queue[15:0] <= {2{weight_reg}};
							end
							// 0001填成0111
							else if(data_queue_status == 4'b0001) begin
								data_queue_status[2:1] <= 2'b11;
								data_queue[7:4] <= data_diff_reg[7:4];
								data_queue[11:8] <= data_diff_reg[3:0];
								meta_data[0] <= 1'b1;
								weight_queue[23:8] <= {2{weight_reg}};
							end
							// 0010规定不存在,因为我的设计不会有溢出高8位
							// 0011填成1111
							else if(data_queue_status == 4'b0011) begin
								data_queue_status[3:2] <= 2'b11;
								data_queue[15:8] <= data_diff_reg;
								meta_data[1] <= 1'b1;
								weight_queue[31:16] <= {2{weight_reg}};
							end
							// 0100, 0101, 0110不存在,溢出优先填低处
							// 0111填高4位,溢出低4位
							else if(data_queue_status == 4'b0111) begin
								data_queue_status[3] <= 1'b1;
								data_queue[15:12] <= data_diff_reg[7:4];
								buffer_valid <= 1'b1;
								data_buffer <= data_diff_reg[3:0];
								meta_data[1] <= 1'b1;
								weight_queue[31:24] <= weight_reg;
								weight_buffer <= weight_reg;
							end
							// 1000,1001,1010,1011,1100,1101,1110不存在,溢出优先填低处
						end
					endcase					
				end

			end
		end
	end

endmodule
