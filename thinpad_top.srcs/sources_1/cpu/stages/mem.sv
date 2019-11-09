/*
MEM模块：
    访存阶段，现在还涉及不到RAM，只是把执行阶段的结果向回写阶段传递
*/

`include "cpu_defs.vh"

module mem(
    input  logic            rst,

    input  reg_addr_t       wd_i,       // 要写入的寄存器编号
    input  logic            wreg_i,     // 是否要写入寄存器
    input  word_t           wdata_i,    // 要写入的数据
    input  word_t           hi_i,       // 要写入的hi值
    input  word_t           lo_i,       // 要写入的lo值
    input  logic            whilo_i,    // 是否要写入hilo寄存器
    input  aluop_t          aluop_i,    // aluop的值
    input  word_t           mem_addr_i, // 想要存入内存的地址
    input  word_t           reg2_i,     // 欲写入内存的值

    input  word_t           mem_data_i, // RAM读出来的数

    output reg_addr_t       wd_o,       // 要写入的寄存器编号
    output logic            wreg_o,     // 是否要写入寄存器
    output word_t           wdata_o,    // 要写入的数据
    output word_t           hi_o,       // 要写入的hi值
    output word_t           lo_o,       // 要写入的lo值
    output logic            whilo_o,    // 是否要写入hilo寄存器

    output word_t           mem_addr_o, // 送到RAM中的信号，RAM的地址
    output logic            mem_we_o,   // 送到RAM中的信号，写使能
    output logic[3:0]       mem_sel_o,  // 送到RAM中的信号，从一个word中四个字节选取若干个
    output word_t           mem_data_o, // 送到RAM中的信号
    output logic            mem_ce_o    // 送到RAM中的信号
);

always_comb begin
    if (rst == 1) begin
        wd_o <= `NOP_REG_ADDR;
        wreg_o <= 0;
        wdata_o <= 0;
        {hi_o, lo_o} <= 0;
        whilo_o <= 0;
        {mem_addr_o, mem_we_o, mem_sel_o, mem_data_o, mem_ce_o} <= 0;
    end else begin
        wd_o <= wd_i;
        wreg_o <= wreg_i;
        wdata_o <= wdata_i;
        {hi_o, lo_o} <= {hi_i, lo_i};
        whilo_o <= whilo_i;
        {mem_we_o, mem_addr_o, mem_ce_o} <= 0;
        mem_sel_o <= 4'b1111; // 默认四个字节都读/写
        case (aluop_i)
            // TODO: 见书的P250~P257，我认为这里需要一些宏定义来优化代码风格
            // 先简单加两条指令测试一下有没有bug
            EXE_LW_OP: begin
                mem_addr_o <= mem_addr_i;
                mem_we_o <= 0;
                wdata_o <= mem_data_i;
                mem_sel_o <= 4'b1111;
                mem_ce_o <= 1;
            end
            EXE_SW_OP: begin
                mem_addr_o <= mem_addr_i;
                mem_we_o <= 1;
                mem_data_o <= reg2_i;
                mem_sel_o <= 4'b1111;
                mem_ce_o <= 1;                
            end
        endcase
    end
end

endmodule