/*
comm_reg:
    实现了32个32位的通用寄存器，同时可以对两个寄存器进行读操作，对一个寄存器进行写
    该模块是译码阶段的一部分
*/

`include "cpu_defs.vh"

module comm_reg(
    input  logic            clk,
    input  logic            rst,
	
    input  logic            we,
    input  reg_addr_t       waddr,
    input  word_t           wdata,
	
    input  reg_addr_t       raddr1,
    input  reg_addr_t       raddr2,
    
    output word_t           rdata1,
    output word_t           rdata2
);

word_t regs[0:`REG_NUM-1];

// 清零逻辑
genvar i;
generate
    for (i = 0; i < `REG_NUM; i = i + 1) begin
        always_ff @ (posedge clk) begin
            if (rst == 1'b1) begin
                regs[i] <= `ZeroWord;
            end
        end
    end
endgenerate

always_ff @ (posedge clk) begin
    if (rst == 1'b0) begin
        if ((we == 1'b1) && (waddr != 5'h0)) begin
            regs[waddr] <= wdata;
        end
    end
end

// 下面两个读是异步的组合逻辑，下面的数据前传解决了相隔2个指令的数据冲突
always_comb begin
    if (rst == 1'b1) begin
        rdata1 <= `ZeroWord;
    end else if (raddr1 == 5'h0) begin // 如果读0号寄存器
        rdata1 <= `ZeroWord;
    end else if ((raddr1 == waddr) && (we == 1'b1)) begin // 如果读的寄存器正准备被写，直接读即将被写的值（数据前传）
        rdata1 <= wdata;
    end else begin
        rdata1 <= regs[raddr1];
    end
end

always_comb begin
    if (rst == 1'b1) begin
        rdata2 <= `ZeroWord;
    end else if (raddr2 == 5'h0) begin // 如果读0号寄存器
        rdata2 <= `ZeroWord;
    end else if ((raddr2 == waddr) && (we == 1'b1)) begin // 如果读的寄存器正准备被写，直接读即将被写的值（数据前传）
        rdata2 <= wdata;
    end else begin
        rdata2 <= regs[raddr2];
    end
end

endmodule