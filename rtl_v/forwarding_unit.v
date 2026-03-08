// ============================================================================
// forwarding_unit.v  —  Unidade de Forwarding — EduRISC-32
//
// Resolve hazards de dados por forwarding sem stalls quando possível.
//
// Hierarquia de forwarding (prioridade: EX/MEM > MEM/WB):
//
//  fwd_a[1:0]:
//    2'b00 — sem forwarding     (usa rs1_data do banco de registradores)
//    2'b01 — MEM/WB forwarding  (usa resultado do estágio MEM)
//    2'b10 — EX/MEM forwarding  (usa resultado do estágio EX)
//
//  fwd_b[1:0]:  igual mas para rs2
//
// Condição de forwarding:
//   - O estágio doador escreve no banco (reg_write = 1)
//   - O registrador destino é diferente de R0 (não há R0 zero, mas boa prática)
//   - O registrador destino coincide com o operando fonte
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module forwarding_unit (
    // Operandos da instrução em EX
    input  wire [3:0] ex_rs1,
    input  wire [3:0] ex_rs2,

    // Informações do estágio EX/MEM
    input  wire [3:0] exmem_rd,
    input  wire       exmem_reg_write,

    // Informações do estágio MEM/WB
    input  wire [3:0] memwb_rd,
    input  wire       memwb_reg_write,

    // Seleção do mux de forwarding
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);

    always @(*) begin
        // ---- Forwarding para operando A (rs1) ----
        if (exmem_reg_write && (exmem_rd == ex_rs1))
            fwd_a = 2'b10;          // EX/MEM forwarding
        else if (memwb_reg_write && (memwb_rd == ex_rs1))
            fwd_a = 2'b01;          // MEM/WB forwarding
        else
            fwd_a = 2'b00;          // sem forwarding

        // ---- Forwarding para operando B (rs2) ----
        if (exmem_reg_write && (exmem_rd == ex_rs2))
            fwd_b = 2'b10;
        else if (memwb_reg_write && (memwb_rd == ex_rs2))
            fwd_b = 2'b01;
        else
            fwd_b = 2'b00;
    end

endmodule
