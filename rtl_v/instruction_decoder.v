// ============================================================================
// instruction_decoder.v  —  Extrator de Campos de Instrução EduRISC-32v2
//
// Extração puramente combinacional dos campos de cada formato.
// Não há lógica de controle aqui — apenas wire assignments.
//
// Formatos:
//  R:  [31:26]=op [25:21]=rd  [20:16]=rs1 [15:11]=rs2 [10:6]=shamt [5:0]=unused
//  I:  [31:26]=op [25:21]=rd  [20:16]=rs1 [15:0]=imm16
//  S:  [31:26]=op [25:21]=rs2 [20:16]=rs1 [15:0]=off16
//  B:  [31:26]=op [25:21]=rs1 [20:16]=rs2 [15:0]=off16
//  J:  [31:26]=op [25:0]=addr26
//  U:  [31:26]=op [25:21]=rd  [20:0]=imm21
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module instruction_decoder (
    input  wire [31:0] instr,

    // Campos comuns
    output wire [5:0]  op,
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  shamt,

    // Imediatos estendidos para 32 bits
    output wire [31:0] imm16_sext,    // I-type / S-type / B-type: sext(imm[15:0])
    output wire [31:0] imm16_zext,    // Zero-extended (ANDI, ORI, XORI)
    output wire [31:0] addr26_ext,    // J-type: zero-extended addr26
    output wire [31:0] imm21_upper,   // U-type: imm21 << 11
    output wire [31:0] imm5_zext,     // shift immediates: zero-ext instr[10:6] (=shamt)

    // Classificações booleanas (para control_unit e hazard_unit)
    output wire        is_r_type,
    output wire        is_i_type,
    output wire        is_s_type,
    output wire        is_b_type,
    output wire        is_j_type,
    output wire        is_u_type,

    output wire        is_load,       // LW LH LHU LB LBU
    output wire        is_store,      // SW SH SB
    output wire        is_branch,     // BEQ BNE BLT BGE BLTU BGEU
    output wire        is_jump,       // JMP JMPR CALL CALLR RET
    output wire        is_call,       // CALL CALLR (escrevem R31)
    output wire        is_ret,        // RET ERET
    output wire        is_mul_div,    // MUL MULH DIV DIVU REM (multi-ciclo)
    output wire        is_csr,        // MFC MTC
    output wire        is_system      // SYSCALL ERET FENCE BREAK HLT NOP
);

    // ------------------------------------------------------------------
    // Extração de campos brutos
    // ------------------------------------------------------------------
    assign op    = instr[31:26];
    assign rd    = instr[25:21];   // também rs2 em S-type
    assign rs1   = instr[20:16];
    assign rs2   = instr[15:11];
    assign shamt = instr[10:6];

    // ------------------------------------------------------------------
    // Imediatos
    // ------------------------------------------------------------------
    // I / B / S share the same 16-bit field [15:0], sign extended
    assign imm16_sext  = {{16{instr[15]}}, instr[15:0]};
    assign imm16_zext  = {16'b0, instr[15:0]};
    assign addr26_ext  = {6'b0,  instr[25:0]};
    assign imm21_upper = {instr[20:0], 11'b0};           // MOVHI: rd = imm21 << 11
    assign imm5_zext   = {27'b0, instr[10:6]};           // shamt for SHLI/SHRI/SHRAI

    // ------------------------------------------------------------------
    // Tipos de formato
    // ------------------------------------------------------------------
    // R-type opcodes (sem immediate de dados)
    assign is_r_type = (op == `OP_ADD)  | (op == `OP_SUB)  | (op == `OP_MUL)  |
                       (op == `OP_MULH) | (op == `OP_DIV)  | (op == `OP_DIVU) |
                       (op == `OP_REM)  | (op == `OP_AND)  | (op == `OP_OR)   |
                       (op == `OP_XOR)  | (op == `OP_NOT)  | (op == `OP_NEG)  |
                       (op == `OP_SHL)  | (op == `OP_SHR)  | (op == `OP_SHRA) |
                       (op == `OP_MOV)  | (op == `OP_SLT)  | (op == `OP_SLTU) |
                       (op == `OP_CALLR)| (op == `OP_RET)  | (op == `OP_PUSH) |
                       (op == `OP_POP)  | (op == `OP_NOP)  | (op == `OP_HLT)  |
                       (op == `OP_ERET) | (op == `OP_FENCE)| (op == `OP_BREAK);

    // I-type opcodes (rd, rs1, imm16)
    assign is_i_type = (op == `OP_ADDI) | (op == `OP_ANDI) | (op == `OP_ORI)  |
                       (op == `OP_XORI) | (op == `OP_SHLI) | (op == `OP_SHRI) |
                       (op == `OP_SHRAI)| (op == `OP_MOVI) | (op == `OP_SLTI) |
                       (op == `OP_LW)   | (op == `OP_LH)   | (op == `OP_LHU)  |
                       (op == `OP_LB)   | (op == `OP_LBU)  | (op == `OP_JMPR) |
                       (op == `OP_SYSCALL)|(op == `OP_MFC) | (op == `OP_MTC);

    // S-type: [25:21]=rs2, [20:16]=rs1, [15:0]=offset
    assign is_s_type = (op == `OP_SW) | (op == `OP_SH) | (op == `OP_SB);

    // B-type: [25:21]=rs1, [20:16]=rs2, [15:0]=offset
    assign is_b_type = (op == `OP_BEQ) | (op == `OP_BNE) | (op == `OP_BLT) |
                       (op == `OP_BGE) | (op == `OP_BLTU)| (op == `OP_BGEU);

    // J-type: [25:0]=addr26
    assign is_j_type = (op == `OP_JMP) | (op == `OP_CALL);

    // U-type: [25:21]=rd, [20:0]=imm21
    assign is_u_type = (op == `OP_MOVHI);

    // ------------------------------------------------------------------
    // Classificações funcionais
    // ------------------------------------------------------------------
    assign is_load    = (op == `OP_LW)  | (op == `OP_LH)  | (op == `OP_LHU) |
                        (op == `OP_LB)  | (op == `OP_LBU);

    assign is_store   = (op == `OP_SW)  | (op == `OP_SH)  | (op == `OP_SB);

    assign is_branch  = is_b_type;

    assign is_jump    = (op == `OP_JMP) | (op == `OP_JMPR)| (op == `OP_CALL)|
                        (op == `OP_CALLR)|(op == `OP_RET) | (op == `OP_ERET)|
                        (op == `OP_PUSH)| (op == `OP_POP);   // PUSH/POP tocam SP

    assign is_call    = (op == `OP_CALL) | (op == `OP_CALLR) | (op == `OP_JMPR);

    assign is_ret     = (op == `OP_RET) | (op == `OP_ERET);

    assign is_mul_div = (op == `OP_MUL) | (op == `OP_MULH) | (op == `OP_DIV) |
                        (op == `OP_DIVU)| (op == `OP_REM);

    assign is_csr     = (op == `OP_MFC) | (op == `OP_MTC);

    assign is_system  = (op == `OP_SYSCALL) | (op == `OP_ERET) | (op == `OP_FENCE) |
                        (op == `OP_BREAK)   | (op == `OP_HLT)  | (op == `OP_NOP);

endmodule
