// ============================================================================
// instruction_decoder.v  —  Decodificador de Instrução — EduRISC-32
//
// Extrai campos da instrução de 32 bits de acordo com o tipo:
//
//   Tipo-R:  [31:28]=op [27:24]=rd [23:20]=rs1 [19:16]=rs2 [15:0]=unused
//   Tipo-I:  [31:28]=op [27:24]=rd [23:20]=rs1 [19:0 ]=imm20
//   Tipo-J:  [31:28]=op [27:0 ]=addr28
//   Tipo-M:  [31:28]=op [27:24]=rd [23:20]=base [19:0]=offset20
//
// Saídas são combinacionais (sem registradores).
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module instruction_decoder (
    input  wire [31:0] instr,      // instrução bruta

    // Campos extraídos
    output wire [3:0]  opcode,
    output wire [3:0]  rd,
    output wire [3:0]  rs1,
    output wire [3:0]  rs2,
    output wire [31:0] imm20,      // imediato sinalizado (sign-extended de 20b)
    output wire [31:0] offset20,   // offset de memória sinalizado (sign-extended)
    output wire [27:0] addr28,     // alvo de desvio/call/jump

    // Tipo da instrução
    output wire        is_r_type,
    output wire        is_m_type,
    output wire        is_j_type,

    // Instrução especial
    output wire        is_load,
    output wire        is_store,
    output wire        is_jump,    // JMP / JZ / JNZ / CALL
    output wire        is_branch,  // JZ / JNZ (branch condicional)
    output wire        is_call,
    output wire        is_ret,
    output wire        is_hlt
);

    // ------------------------------------------------------------------
    // Extração dos campos brutos
    // ------------------------------------------------------------------
    assign opcode  = instr[31:28];
    assign rd      = instr[27:24];
    assign rs1     = instr[23:20];
    assign rs2     = instr[19:16];
    assign addr28  = instr[27:0];

    // imm20: extensão de sinal do campo [19:0] para 32 bits
    assign imm20   = {{12{instr[19]}}, instr[19:0]};

    // offset20: mesmo campo que imm20 mas semântica de offset de memória
    assign offset20 = {{12{instr[19]}}, instr[19:0]};

    // ------------------------------------------------------------------
    // Classificação do tipo
    // ------------------------------------------------------------------
    assign is_r_type = (opcode <= `OP_NOT) || (opcode == `OP_RET) || (opcode == `OP_HLT);
    assign is_m_type = (opcode == `OP_LOAD) || (opcode == `OP_STORE);
    assign is_j_type = (opcode == `OP_JMP)  || (opcode == `OP_JZ)  ||
                       (opcode == `OP_JNZ)  || (opcode == `OP_CALL);

    // ------------------------------------------------------------------
    // Instruções especiais
    // ------------------------------------------------------------------
    assign is_load   = (opcode == `OP_LOAD);
    assign is_store  = (opcode == `OP_STORE);
    assign is_jump   = (opcode == `OP_JMP)  || (opcode == `OP_JZ)  ||
                       (opcode == `OP_JNZ)  || (opcode == `OP_CALL);
    assign is_branch = (opcode == `OP_JZ)   || (opcode == `OP_JNZ);
    assign is_call   = (opcode == `OP_CALL);
    assign is_ret    = (opcode == `OP_RET);
    assign is_hlt    = (opcode == `OP_HLT);

endmodule
