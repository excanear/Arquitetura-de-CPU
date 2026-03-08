// ============================================================================
// forwarding_unit.v  —  Unidade de Forwarding EduRISC-32v2
//
// Resolve hazards RAW sem stall para instruções não-load/não-muldiv.
//
// Fontes de forwarding:
//   EX/MEM (1 ciclo atrás): maior prioridade
//   MEM/WB (2 ciclos atrás): menor prioridade
//
// Codificação de fwd_sel:
//   2'b00 = sem forwarding (usa dado do banco de registradores)
//   2'b01 = forwarding de MEM/WB
//   2'b10 = forwarding de EX/MEM
// ============================================================================
`timescale 1ns/1ps

module forwarding_unit (
    // Registradores fonte da instrução EX
    input  wire [4:0]  ex_rs1,
    input  wire [4:0]  ex_rs2,

    // Destino e habilita escrita de EX/MEM
    input  wire [4:0]  mem_rd,
    input  wire        mem_reg_write,

    // Destino e habilita escrita de MEM/WB
    input  wire [4:0]  wb_rd,
    input  wire        wb_reg_write,

    // Seleção de forwarding (para os muxes na entrada da ALU)
    output reg  [1:0]  fwd_a,  // operando A (rs1)
    output reg  [1:0]  fwd_b   // operando B (rs2)
);

    always @(*) begin
        // ---- Operando A (rs1) ----
        if (mem_reg_write && (mem_rd != 5'b0) && (mem_rd == ex_rs1))
            fwd_a = 2'b10;   // EX/MEM tem prioridade
        else if (wb_reg_write && (wb_rd != 5'b0) && (wb_rd == ex_rs1))
            fwd_a = 2'b01;   // MEM/WB
        else
            fwd_a = 2'b00;   // banco de registradores

        // ---- Operando B (rs2) ----
        if (mem_reg_write && (mem_rd != 5'b0) && (mem_rd == ex_rs2))
            fwd_b = 2'b10;
        else if (wb_reg_write && (wb_rd != 5'b0) && (wb_rd == ex_rs2))
            fwd_b = 2'b01;
        else
            fwd_b = 2'b00;
    end

endmodule
