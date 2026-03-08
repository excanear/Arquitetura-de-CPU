// ============================================================================
// branch_unit.v  —  Unidade de desvio e cálculo de alvo
//
// Garante comparação correta para todos os 6 tipos de desvio EduRISC-32v2:
//   BEQ, BNE, BLT, BGE, BLTU, BGEU
//
// Alvo:
//   Branches: PC + sign_extend(off16)   (relativo ao PC)
//   JMP:      {PC[25:26], addr26}       (absoluto na página)
//   JMPR:     rs1[25:0]                 (registrador)
//   CALL:     mesmo que JMP
//   CALLR:    mesmo que JMPR
//   RET:      lr_val[25:0]              (R31)
//
// Nota: a decisão final de saltar é feita no execute stage do pipeline,
//       onde os dados de rs1/rs2 já estão disponíveis após forwarding.
// ============================================================================
`timescale 1ns/1ps
`include "../isa_pkg.vh"

module branch_unit (
    input  wire [5:0]  op,
    input  wire [31:0] rs1_val,      // valor de rs1 (após forwarding)
    input  wire [31:0] rs2_val,      // valor de rs2 (após forwarding)
    input  wire [25:0] pc,
    input  wire [15:0] imm16,        // offset bruto (signed)
    input  wire [25:0] addr26,       // destino absoluto para JMP/CALL
    input  wire [25:0] lr_val,       // R31 para RET
    output wire        taken,
    output wire [25:0] target
);

    // -----------------------------------------------------------------------
    // Cálculo de condição
    // -----------------------------------------------------------------------
    wire eq  = (rs1_val == rs2_val);
    wire lts = ($signed(rs1_val) < $signed(rs2_val));
    wire ltu = (rs1_val < rs2_val);

    reg cond;
    always @(*) begin
        case (op)
            `OP_BEQ:  cond = eq;
            `OP_BNE:  cond = ~eq;
            `OP_BLT:  cond = lts;
            `OP_BGE:  cond = ~lts;
            `OP_BLTU: cond = ltu;
            `OP_BGEU: cond = ~ltu;
            default:  cond = 1'b0;
        endcase
    end

    // -----------------------------------------------------------------------
    // taken para jumpls incondicionais vs. branches condicionais
    // -----------------------------------------------------------------------
    wire is_jump  = (op == `OP_JMP)  || (op == `OP_JMPR) ||
                    (op == `OP_CALL) || (op == `OP_CALLR) || (op == `OP_RET);
    wire is_branch = (op == `OP_BEQ) || (op == `OP_BNE) ||
                     (op == `OP_BLT) || (op == `OP_BGE) ||
                     (op == `OP_BLTU)|| (op == `OP_BGEU);

    assign taken = (is_branch && cond) || is_jump;

    // -----------------------------------------------------------------------
    // Cálculo de alvo
    // -----------------------------------------------------------------------
    wire [25:0] pc_imm  = pc + {{10{imm16[15]}}, imm16};   // PC + sext(off16)

    reg [25:0] tgt;
    always @(*) begin
        case (op)
            // Desvios condicionais: PC-relativo
            `OP_BEQ,
            `OP_BNE,
            `OP_BLT,
            `OP_BGE,
            `OP_BLTU,
            `OP_BGEU: tgt = pc_imm;

            // Saltos absolutos (formato J)
            `OP_JMP,
            `OP_CALL: tgt = addr26;

            // Saltos via registrador
            `OP_JMPR,
            `OP_CALLR:tgt = rs1_val[25:0];

            // Retorno de sub-rotina
            `OP_RET:  tgt = lr_val;

            default:  tgt = pc_imm;
        endcase
    end

    assign target = tgt;

endmodule
