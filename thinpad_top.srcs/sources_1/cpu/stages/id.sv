/*
ID(Decode)模块：
    对指令进行译码，得到最终运算的类型、子类型和两个源操作数
*/

`include "cpu_defs.vh"

module id(
    input  logic                    rst,
    
    input  addr_t                   pc_i,                   // PC
    input  word_t                   inst_i,                 // 指令

    input  word_t                   reg1_data_i,            // 读寄存器
    input  word_t                   reg2_data_i,            // 读寄存器

    // 执行阶段传来的前传数据（解决相邻指令的冲突）
    input  logic                    ex_wreg_i,              // ex是否写目的寄存器
    input  word_t                   ex_wdata_i,             // ex需写入的数据
    input  reg_addr_t               ex_wd_i,                // ex需写入的寄存器

    // 访存阶段传来的前传数据（解决相隔1条指令的冲突）
    input  logic                    mem_wreg_i,             // mem是否写目的寄存器
    input  word_t                   mem_wdata_i,            // mem需写入的数据
    input  reg_addr_t               mem_wd_i,               // mem需写入的寄存器

    input  logic                    in_delayslot_i,         // 当前指令在不在延迟槽，因为是组合逻辑所以只能把用id_ex把next传回来

    input  aluop_t                  ex_aluop_i,             // 把ex阶段的aluop引过来，用于判断是否有访存冲突

    output word_t                   inst_o,                 // 把指令原样输出到下一阶段，用于仿存计算地址

    output reg_addr_t               reg1_addr_o,            // 要读的寄存器1的编号
    output reg_addr_t               reg2_addr_o,            // 要读的寄存器2的编号

    output logic                    in_delayslot_o,         // 当前指令在不在延迟槽
    output logic                    next_in_delayslot_o,    // 下一条在不在延迟槽
    output logic                    jump_flag_o,            // 是否跳转
    output addr_t                   target_addr_o,          // 跳转地址
    output addr_t                   return_addr_o,          // 返回地址

    output word_t                   except_type_o,          // 异常类型
    output word_t                   current_inst_addr_o,    // 当前指令地址

    output aluop_t                  aluop_o,                // 要ex执行的alu操作
    output word_t                   reg1_o,                 // 寄存器或者立即数的值（源操作数1）
    output word_t                   reg2_o,                 // 寄存器或者立即数的值（源操作数2）
    output reg_addr_t               wd_o,                   // 需要被写入的寄存器编号
    output logic                    wreg_o,                 // 是否需要写入

    output logic                    stallreq_o              // 暂停请求
);

// 上条指令是否是访存指令
logic pre_inst_is_load;

// 是否是syscall/eret
logic except_type_is_syscall, except_type_is_eret;

assign except_type_o = {19'b0, except_type_is_eret, 2'b0, 1'b0, except_type_is_syscall, 8'b0};
assign current_inst_addr_o = pc_i;

always_comb 
    case (ex_aluop_i)
        EXE_LB_OP, EXE_LBU_OP, EXE_LH_OP, EXE_LHU_OP, EXE_LW_OP:
            pre_inst_is_load <= 1;
        default:
            pre_inst_is_load <= 0;
    endcase

logic stallreq_for_reg1_loadrelate; // 寄存器1是否数据相关
logic stallreq_for_reg2_loadrelate; // 寄存器2是否数据相关

// 暂停请求
assign stallreq_o = stallreq_for_reg1_loadrelate | stallreq_for_reg2_loadrelate;

// 输入的指令原样输出到下一阶段
assign inst_o = inst_i; 

// 当前指令是否在延迟槽
assign in_delayslot_o = rst ? 0 : in_delayslot_i;

// 四段码，参见书的121页，需要根据这个来判断指令类型
wire [5:0] op1 = inst_i[31:26];
wire [4:0] op2 = inst_i[10:6];
wire [5:0] op3 = inst_i[5:0];
wire [4:0] op4 = inst_i[20:16];

// 指令中的立即数
word_t imm;

// 是否读寄存器
logic reg1_read_o; 
logic reg2_read_o;

// 下一二条PC以及偏移跳转的结果
addr_t pc_next, pc_next_2, pc_plus_offset;
assign pc_next = pc_i + 4;
assign pc_next_2 = pc_i + 8;
assign pc_plus_offset = pc_next + {{14{inst_i[15]}}, inst_i[15:0], 2'b00}; // 地址偏移要乘4

// 把指令划分为3类，可以归纳出这样的宏函数，下面每个指令一行，可读性就好一些，其实下面那个跳转部分也能搞成表，我觉得一行可能太长了就暂时没弄
// 备注：sll, sllv的区别是sll是用立即数，sllv用寄存器
// 第一类：逻辑/算术/移动（不涉及立即数和移位）
`define INST_KIND_1_COMMON(e,w,r1,r2)       aluop_o <= e; \
                                            wreg_o <= w; \
                                            reg1_read_o <= r1; \
                                            reg2_read_o <= r2

// 第二类：涉及立即数（不涉及移位）
`define INST_KIND_2_COMMON(e,i,w,r1,r2)     `INST_KIND_1_COMMON(e,w,r1,r2); \
                                            imm <= i; \
                                            wd_o <= inst_i[20:16]

// 第三类：涉及移位和立即数，立即数只有5位
`define INST_KIND_3_COMMON(e,w,r1,r2)       `INST_KIND_1_COMMON(e,w,r1,r2); \
                                            imm[4:0] <= inst_i[10:6]

// 第四类：涉及访存，不涉及立即数
`define INST_KIND_4_COMMON(e,w,r1,r2)       `INST_KIND_1_COMMON(e,w,r1,r2); \
                                            wd_o <= inst_i[20:16]

// 第五类：涉及移位和立即数，立即数有32位
`define INST_KIND_5_COMMON(e,w,r1,r2,i)     `INST_KIND_1_COMMON(e,w,r1,r2); \
                                            imm <= i

// 把四个有关分支跳转的都设置好
`define BRANCH_ALL(r,t,f,n)                 return_addr_o <= r; \
                                            target_addr_o <= t; \
                                            jump_flag_o <= f; \
                                            next_in_delayslot_o <= n

`define BRANCH_CONDITION(c,r,t,f,n)         if (c) begin \
                                                `BRANCH_ALL(r,t,f,n); \
                                            end // Trick: 分号应该会被注释掉

always_comb begin
    if (rst == 1) begin
        {aluop_o,wd_o, reg1_addr_o, reg2_addr_o, wreg_o, reg1_read_o, reg2_read_o, imm, next_in_delayslot_o, jump_flag_o, target_addr_o, return_addr_o, except_type_is_syscall, except_type_is_eret} <= 0;
    end else begin
        // 默认情况
        aluop_o     <= EXE_NOP_OP;
        wd_o        <= inst_i[15:11];
        reg1_addr_o <= inst_i[25:21];
        reg2_addr_o <= inst_i[20:16];
        {wreg_o, reg1_read_o, reg2_read_o, imm, next_in_delayslot_o, jump_flag_o, target_addr_o, return_addr_o} <= 0;
        {except_type_is_syscall, except_type_is_eret} <= 0;
        // 下面这部分判断详情见造CPU一书的121页
        case (op1) // 指令码
            `EXE_SPECIAL_INST: begin
                case (op2)
                    5'b00000: begin
                        case (op3) //                                 ALUOP             是否写入寄存器    是否读取寄存器1/2
                            `EXE_OR:        begin `INST_KIND_1_COMMON(EXE_OR_OP,        1,              1, 1);  end
                            `EXE_AND:       begin `INST_KIND_1_COMMON(EXE_AND_OP,       1,              1, 1);  end
                            `EXE_XOR:       begin `INST_KIND_1_COMMON(EXE_XOR_OP,       1,              1, 1);  end
                            `EXE_NOR:       begin `INST_KIND_1_COMMON(EXE_NOR_OP,       1,              1, 1);  end
                            `EXE_SLLV:      begin `INST_KIND_1_COMMON(EXE_SLL_OP,       1,              1, 1);  end
                            `EXE_SRLV:      begin `INST_KIND_1_COMMON(EXE_SRL_OP,       1,              1, 1);  end
                            `EXE_SRAV:      begin `INST_KIND_1_COMMON(EXE_SRA_OP,       1,              1, 1);  end
                            `EXE_SYNC:      begin `INST_KIND_1_COMMON(EXE_NOP_OP,       0,              0, 0);  end // 书上这里写了读第二个寄存器，暂时先不读
                            `EXE_SLT:       begin `INST_KIND_1_COMMON(EXE_SLT_OP,       1,              1, 1);  end
                            `EXE_SLTU:      begin `INST_KIND_1_COMMON(EXE_SLTU_OP,      1,              1, 1);  end
                            `EXE_ADD:       begin `INST_KIND_1_COMMON(EXE_ADD_OP,       1,              1, 1);  end
                            `EXE_ADDU:      begin `INST_KIND_1_COMMON(EXE_ADDU_OP,      1,              1, 1);  end
                            `EXE_SUB:       begin `INST_KIND_1_COMMON(EXE_SUB_OP,       1,              1, 1);  end
                            `EXE_SUBU:      begin `INST_KIND_1_COMMON(EXE_SUBU_OP,      1,              1, 1);  end
                        `ifdef MUL_ON 
                            `EXE_MULT:      begin `INST_KIND_1_COMMON(EXE_MULT_OP,      0,              1, 1);  end // 这里写到hilo寄存器，不写通用
                            `EXE_MULTU:     begin `INST_KIND_1_COMMON(EXE_MULTU_OP,     0,              1, 1);  end // 这里写到hilo寄存器，不写通用
                        `endif
                            `EXE_MFHI:      begin `INST_KIND_1_COMMON(EXE_MFHI_OP,      1,              0, 0);  end // 从hi读并写到寄存器
                            `EXE_MFLO:      begin `INST_KIND_1_COMMON(EXE_MFLO_OP,      1,              0, 0);  end // 从lo读并写到寄存器
                            `EXE_MTHI:      begin `INST_KIND_1_COMMON(EXE_MTHI_OP,      0,              1, 0);  end // 从寄存器读并写到hi
                            `EXE_MTLO:      begin `INST_KIND_1_COMMON(EXE_MTLO_OP,      0,              1, 0);  end // 从寄存器读并写到lo
                            `EXE_MOVN:      begin `INST_KIND_1_COMMON(EXE_MOVN_OP,      (reg2_o != 0),  1, 1);  end // 如果非0就写
                            `EXE_MOVZ:      begin `INST_KIND_1_COMMON(EXE_MOVZ_OP,      (reg2_o == 0),  1, 1);  end // 如果是0就写
                        `ifdef TRAP_ON
                            `EXE_TEQ:       begin `INST_KIND_1_COMMON(EXE_TEQ_OP,       0,              1, 1);  end
                            `EXE_TGE:       begin `INST_KIND_1_COMMON(EXE_TGE_OP,       0,              1, 1);  end
                            `EXE_TGEU:      begin `INST_KIND_1_COMMON(EXE_TGEU_OP,      0,              1, 1);  end
                            `EXE_TLT:       begin `INST_KIND_1_COMMON(EXE_TLT_OP,       0,              1, 1);  end
                            `EXE_TLTU:      begin `INST_KIND_1_COMMON(EXE_TLTU_OP,      0,              1, 1);  end
                            `EXE_TNE:       begin `INST_KIND_1_COMMON(EXE_TNE_OP,       0,              1, 1);  end
                        `endif
                            `EXE_SYSCALL:   begin `INST_KIND_1_COMMON(EXE_SYSCALL_OP,   0,              0, 0); except_type_is_syscall <= 1; end
                            `EXE_JR: begin
                                `INST_KIND_1_COMMON(EXE_JR_OP, 0, 1, 0);
                                `BRANCH_ALL(0, reg1_o, 1, 1);
                            end
                            `EXE_JALR: begin // 书上还有一句wd_o <= inst_i[15:11] 这里直接归为默认情况
                                `INST_KIND_1_COMMON(EXE_JALR_OP, 1, 1, 0);
                                `BRANCH_ALL(pc_next_2, reg1_o, 1, 1);
                            end
                            default: begin end
                        endcase
                    end
                    default: begin end
                endcase
            end //                                ALUOP         立即数                             是否写入寄存器/是否读1/2
            `EXE_ORI:   begin `INST_KIND_2_COMMON(EXE_OR_OP,    {16'h0, inst_i[15:0]},            1, 1, 0);   end // 高位补0
            `EXE_ANDI:  begin `INST_KIND_2_COMMON(EXE_AND_OP,   {16'h0, inst_i[15:0]},            1, 1, 0);   end // 高位补0
            `EXE_XORI:  begin `INST_KIND_2_COMMON(EXE_XOR_OP,   {16'h0, inst_i[15:0]},            1, 1, 0);   end // 高位补0
            `EXE_LUI:   begin `INST_KIND_2_COMMON(EXE_OR_OP,    {inst_i[15:0], 16'h0},            1, 1, 0);   end // 高位load，低位保持
            `EXE_PREF:  begin `INST_KIND_2_COMMON(EXE_NOP_OP,   0,                                0, 0, 0);   end
            `EXE_SLTI:  begin `INST_KIND_2_COMMON(EXE_SLT_OP,   {{16{inst_i[15]}}, inst_i[15:0]}, 1, 1, 0);   end // 符号扩展
            `EXE_SLTIU: begin `INST_KIND_2_COMMON(EXE_SLTU_OP,  {{16{inst_i[15]}}, inst_i[15:0]}, 1, 1, 0);   end // 符号扩展（并不是0扩展，参见MIPS32文档）
            `EXE_ADDI:  begin `INST_KIND_2_COMMON(EXE_ADDI_OP,  {{16{inst_i[15]}}, inst_i[15:0]}, 1, 1, 0);   end // 符号扩展
            `EXE_ADDIU: begin `INST_KIND_2_COMMON(EXE_ADDIU_OP, {{16{inst_i[15]}}, inst_i[15:0]}, 1, 1, 0);   end // 符号扩展（并不是0扩展，参见MIPS32文档）
            `EXE_LB:    begin `INST_KIND_4_COMMON(EXE_LB_OP,                                      1, 1, 0);   end
            `EXE_LBU:   begin `INST_KIND_4_COMMON(EXE_LBU_OP,                                     1, 1, 0);   end
            `EXE_LH:    begin `INST_KIND_4_COMMON(EXE_LH_OP,                                      1, 1, 0);   end
            `EXE_LHU:   begin `INST_KIND_4_COMMON(EXE_LHU_OP,                                     1, 1, 0);   end
            `EXE_LW:    begin `INST_KIND_4_COMMON(EXE_LW_OP,                                      1, 1, 0);   end
            `EXE_SB:    begin `INST_KIND_1_COMMON(EXE_SB_OP,                                      0, 1, 1);   end
            `EXE_SH:    begin `INST_KIND_1_COMMON(EXE_SH_OP,                                      0, 1, 1);   end
            `EXE_SW:    begin `INST_KIND_1_COMMON(EXE_SW_OP,                                      0, 1, 1);   end
            `EXE_J: begin
                `INST_KIND_1_COMMON(EXE_J_OP, 0, 0, 0);
                `BRANCH_ALL(0, {pc_next[31:28], inst_i[25:0], 2'b00}, 1, 1);
            end
            `EXE_JAL: begin
                wd_o <= 31; // 31号寄存器
                `INST_KIND_1_COMMON(EXE_JAL_OP, 1, 0, 0);
                `BRANCH_ALL(pc_next_2, {pc_next[31:28], inst_i[25:0], 2'b00}, 1, 1);
            end
            `EXE_BEQ: begin
                `INST_KIND_1_COMMON(EXE_BEQ_OP, 0, 1, 1);
                `BRANCH_CONDITION((reg1_o == reg2_o), 0, pc_plus_offset, 1, 1);
            end
            `EXE_BGTZ: begin
                `INST_KIND_1_COMMON(EXE_BGTZ_OP, 0, 1, 0);
                `BRANCH_CONDITION((reg1_o[31] == 0 && reg1_o != 0), 0, pc_plus_offset, 1, 1);
            end
            `EXE_BLEZ: begin
                `INST_KIND_1_COMMON(EXE_BLEZ_OP, 0, 1, 0);
                `BRANCH_CONDITION((reg1_o[31] == 1 || reg1_o == 0), 0, pc_plus_offset, 1, 1);
            end
            `EXE_BNE: begin
                `INST_KIND_1_COMMON(EXE_BNE_OP, 0, 1, 1);
                `BRANCH_CONDITION((reg1_o != reg2_o), 0, pc_plus_offset, 1, 1);
            end
            `EXE_REGIMM_INST: begin
                case (op4)
                    `EXE_BGEZ: begin
                        `INST_KIND_1_COMMON(EXE_BGEZ_OP, 0, 1, 0);
                        `BRANCH_CONDITION((reg1_o[31] == 0), 0, pc_plus_offset, 1, 1);
                    end
                    `EXE_BGEZAL: begin
                        wd_o <= 31;
                        `INST_KIND_1_COMMON(EXE_BGEZAL_OP, 1, 1, 0);
                        `BRANCH_CONDITION((reg1_o[31] == 0), pc_next_2, pc_plus_offset, 1, 1); // 书上的返回地址写在了if外面我觉得是等价的
                    end
                    `EXE_BLTZ: begin
                        `INST_KIND_1_COMMON(EXE_BLTZ_OP, 0, 1, 0);
                        `BRANCH_CONDITION((reg1_o[31] == 1), 0, pc_plus_offset, 1, 1);
                    end
                    `EXE_BLTZAL: begin
                        wd_o <= 31;
                        `INST_KIND_1_COMMON(EXE_BLTZAL_OP, 1, 1, 0);
                        `BRANCH_CONDITION((reg1_o[31] == 1), pc_next_2, pc_plus_offset, 1, 1); // 书上的返回地址写在了if外面我觉得是等价的
                    end
                `ifdef TRAP_ON
                    `EXE_TEQI:  begin `INST_KIND_5_COMMON(EXE_TEQI_OP,  0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                    `EXE_TGEI:  begin `INST_KIND_5_COMMON(EXE_TGEI_OP,  0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                    `EXE_TGEIU: begin `INST_KIND_5_COMMON(EXE_TGEIU_OP, 0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                    `EXE_TLTI:  begin `INST_KIND_5_COMMON(EXE_TLTI_OP,  0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                    `EXE_TLTIU: begin `INST_KIND_5_COMMON(EXE_TLTIU_OP, 0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                    `EXE_TNEI:  begin `INST_KIND_5_COMMON(EXE_TNEI_OP,  0, 1, 0, {{16{inst_i[15]}}, inst_i[15:0]}); end
                `endif
                    default: begin end
                endcase
            end
            `EXE_SPECIAL2_INST: begin
                case (op3) //                              ALUOP        是否写入寄存器/是否读1/2
                    `EXE_CLZ:    begin `INST_KIND_1_COMMON(EXE_CLZ_OP,  1, 1, 0);  end
                    `EXE_CLO:    begin `INST_KIND_1_COMMON(EXE_CLO_OP,  1, 1, 0);  end
                `ifdef MUL_ON
                    `EXE_MUL:    begin `INST_KIND_1_COMMON(EXE_MUL_OP,  1, 1, 1);  end
                `endif
                    default: begin end
                endcase
            end
            default: begin end
        endcase
        if (inst_i == `EXE_ERET) begin
            `INST_KIND_1_COMMON(EXE_ERET_OP, 0, 0, 0);
            except_type_is_eret <= 1;
        end else if (inst_i[31:21] == 11'b00000000000) begin
            case (op3) //                             ALUOP       是否写入寄存器/是否读1/2
                `EXE_SLL:   begin `INST_KIND_3_COMMON(EXE_SLL_OP, 1, 0, 1);     end
                `EXE_SRL:   begin `INST_KIND_3_COMMON(EXE_SRL_OP, 1, 0, 1);     end
                `EXE_SRA:   begin `INST_KIND_3_COMMON(EXE_SRA_OP, 1, 0, 1);     end
                default: begin end
            endcase
        end else if (inst_i[31:21] == 11'b01000000000 && inst_i[10:0] == 0) begin
            `INST_KIND_4_COMMON(EXE_MFC0_OP, 1, 0, 0);
        end else if (inst_i[31:21] == 11'b01000000100 && inst_i[10:0] == 0) begin
            `INST_KIND_1_COMMON(EXE_MTC0_OP, 0, 1, 0);
            reg1_addr_o <= inst_i[20:16];
        end
    end
end

// 下面两段是传递什么数据给ex阶段，如果不读寄存器就用立即数
always_comb begin
    stallreq_for_reg1_loadrelate <= 0;
    if (rst) begin
        reg1_o <= '0;
    end else if (reg1_read_o) begin
        if (pre_inst_is_load && ex_wd_i == reg1_addr_o) begin
            // 如果前一条指令是访存，而且当前要读的 reg1 就是正在访存的寄存器，则要求暂停
            reg1_o <= '0;
            stallreq_for_reg1_loadrelate <= 1;
        end else if (ex_wreg_i && ex_wd_i == reg1_addr_o) begin
            // 如果要读的寄存器1与EX阶段要写的寄存器相同，则直接读入要写的值（先看近的指令）
            reg1_o = ex_wdata_i;
        end else if (mem_wreg_i && mem_wd_i == reg1_addr_o) begin
            // 如果要读的寄存器1与MEM阶段要写的寄存器相同，则直接读入要写的值（相隔1条指令）
            reg1_o <= mem_wdata_i;
        end else begin
            reg1_o <= reg1_data_i;
        end
    end else begin
        reg1_o <= imm;
    end
end

always_comb begin
    stallreq_for_reg2_loadrelate <= 0;
    if (rst) begin
        reg2_o <= '0;
    end else if (reg2_read_o) begin
        if (pre_inst_is_load && ex_wd_i == reg2_addr_o) begin
            // 如果前一条指令是访存，而且当前要读的 reg2 就是正在访存的寄存器，则要求暂停
            reg2_o <= '0;
            stallreq_for_reg2_loadrelate <= 1;
        end else if (ex_wreg_i && ex_wd_i == reg2_addr_o) begin
            // 如果要读的寄存器2与EX阶段要写的寄存器相同，则直接读入要写的值（先看近的指令）
            reg2_o <= ex_wdata_i;
        end else if (mem_wreg_i && mem_wd_i == reg2_addr_o) begin
            // 如果要读的寄存器2与MEM阶段要写的寄存器相同，则直接读入要写的值（相隔1条指令）
            reg2_o <= mem_wdata_i;
        end else begin
            reg2_o <= reg2_data_i;
        end
    end else begin
        reg2_o <= imm;
    end
end

endmodule