/*
ID/EX模块：
    把ID的输出连接到EX执行阶段
*/

`include "cpu_defs.vh"

module id_ex(
    input  logic            clk,
    input  logic            rst,

    input  stall_t          stall,      // 暂停状态

    input  aluop_t          id_aluop,   // id要执行的alu操作
    input  word_t           id_reg1,    // id拿到的源操作数1
    input  word_t           id_reg2,    // id拿到的源操作数2
    input  reg_addr_t       id_wd,      // id要写入的寄存器编号
    input  logic            id_wreg,    // id是否要写入寄存器

    output aluop_t          ex_aluop,   // 传给ex要执行的alu操作
    output word_t           ex_reg1,    // 传给ex源操作数1
    output word_t           ex_reg2,    // 传给ex源操作数2
    output reg_addr_t       ex_wd,      // 传给ex要写入的寄存器编号
    output logic            ex_wreg     // 传给ex是否要写入寄存器
);

// 同步写入
always_ff @ (posedge clk) begin
    if ((rst == 1) || (stall[2] == 1 && stall[3] == 0)) begin // id暂停ex阶段没暂停就给ex空指令
        ex_aluop <= EXE_NOP_OP;
        ex_wd    <= `NOP_REG_ADDR;
        {ex_reg1, ex_reg2, ex_wreg} <= 0;
    end else if (stall[2] == 0) begin
        ex_aluop <= id_aluop;
        ex_reg1  <= id_reg1;
        ex_reg2  <= id_reg2;
        ex_wd    <= id_wd;
        ex_wreg  <= id_wreg;
    end
end

endmodule