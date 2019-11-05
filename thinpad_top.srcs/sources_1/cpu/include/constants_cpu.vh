/*
一些定义：
    TODO：拆成多个文件增强可读性
*/

`ifndef _CPU_CONSTANTS_VH_
`define _CPU_CONSTANTS_VH_

`define RstEnable           1'b1
`define RstDisable          1'b0
`define ZeroWord            32'h00000000
`define WriteEnable         1'b1
`define WriteDisable        1'b0
`define ReadEnable          1'b1
`define ReadDisable         1'b0
`define AluOpBus            7:0
`define AluSelBus           2:0
`define InstValid           1'b0
`define InstInvalid         1'b1
`define Stop                1'b1
`define NoStop              1'b0
`define InDelaySlot         1'b1
`define NotInDelaySlot      1'b0
`define Branch              1'b1
`define NotBranch           1'b0
`define InterruptAssert     1'b1
`define InterruptNotAssert  1'b0
`define TrapAssert          1'b1
`define TrapNotAssert       1'b0
`define True_v              1'b1
`define False_v             1'b0
`define ChipEnable          1'b1
`define ChipDisable         1'b0

/*
指令码和功能码：
    对于一条指令inst：
    inst[31:26]为指令码，如果是EXE_SPECIAL类型，继续判断后面，否则直接执行（ori, andi, lui, pref）
    inst[10:6]暂时默认为0，TODO：读一下手册
    inst[5:0]是功能码，可以是（or, and, xor, nor, sllv, srlv, srav, sync）

    如果inst[31:21]直接是0，根据inst[5:0]判断是（sll, srl, sra）中的一个
    见动手造CPU一书的121页

TODO: 改成enum，但是问题是现在有重复的
*/
`define EXE_NOP             6'b000000
`define EXE_SPECIAL         6'b000000

`define EXE_AND             6'b100100
`define EXE_OR              6'b100101
`define EXE_XOR             6'b100110
`define EXE_NOR             6'b100111
`define EXE_ANDI            6'b001100
`define EXE_ORI             6'b001101
`define EXE_XORI            6'b001110
`define EXE_LUI             6'b001111
`define EXE_ADDU            6'b100001
`define EXE_ADDIU           6'b001001

`define EXE_SLL             6'b000000
`define EXE_SLLV            6'b000100
`define EXE_SRL             6'b000010
`define EXE_SRLV            6'b000110
`define EXE_SRA             6'b000011
`define EXE_SRAV            6'b000111

`define EXE_SYNC            6'b001111
`define EXE_PREF            6'b110011

typedef enum logic[`AluOpBus] {
    EXE_NOP_OP,
    EXE_OR_OP,
    EXE_AND_OP,
    EXE_XOR_OP,
    EXE_NOR_OP,
    EXE_SLL_OP,
    EXE_SRL_OP,
    EXE_SRA_OP
} aluop_t;

// 指令ROM
`define InstAddrBus         31:0
`define InstBus             31:0
`define InstMemNum          131071
`define InstMemNumLog2      17

// 寄存器
`define RegAddrBus          4:0
`define RegBus              31:0
`define RegWidth            32
`define DoubleRegWidth      64
`define DoubleRegBus        63:0
`define RegNum              32
`define RegNumLog2          5
`define NOPRegAddr          5'b00000

`endif
