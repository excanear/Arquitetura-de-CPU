// ============================================================================
// alu.v  —  Arithmetic Logic Unit — EduRISC-32
//
// Realiza todas as operações aritméticas e lógicas da CPU.
// Gera flags ZERO, CARRY, NEGATIVE, OVERFLOW após cada operação.
//
// Interface:
//   Entradas:  alu_op[3:0], a[31:0], b[31:0]
//   Saídas:    result[31:0], flag_z, flag_c, flag_n, flag_v
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module alu (
    input  wire [3:0]  alu_op,   // código da operação (ALU_*)
    input  wire [31:0] a,        // operando A (rs1)
    input  wire [31:0] b,        // operando B (rs2 ou imediato)
    output reg  [31:0] result,   // resultado
    output wire        flag_z,   // Zero
    output wire        flag_c,   // Carry / Borrow
    output wire        flag_n,   // Negative
    output reg         flag_v    // Overflow (apenas ADD/SUB)
);

    // ------------------------------------------------------------------
    // Cálculo principal
    // ------------------------------------------------------------------
    reg [32:0] wide;   // 33 bits para capturar carry-out

    always @(*) begin
        flag_v = 1'b0;
        wide   = 33'b0;

        case (alu_op)
            `ALU_ADD: begin
                wide   = {1'b0, a} + {1'b0, b};
                result = wide[31:0];
                // overflow: sinais iguais de entrada → sinal diferente na saída
                flag_v = (~a[31] & ~b[31] & result[31]) |
                         ( a[31] &  b[31] & ~result[31]);
            end

            `ALU_SUB, `ALU_CMP: begin
                wide   = {1'b0, a} - {1'b0, b};
                result = (alu_op == `ALU_CMP) ? 32'b0 : wide[31:0];
                flag_v = ( a[31] & ~b[31] & ~result[31]) |
                         (~a[31] &  b[31] &  result[31]);
            end

            `ALU_MUL: begin
                result = a * b;           // 32 bits inferiores
            end

            `ALU_DIV: begin
                result = (b != 0) ? (a / b) : 32'hFFFF_FFFF;  // div by zero → max
            end

            `ALU_AND: result = a & b;
            `ALU_OR:  result = a | b;
            `ALU_XOR: result = a ^ b;
            `ALU_NOT: result = ~a;

            `ALU_SHL: begin
                result = a << b[4:0];     // shift por [4:0] (0-31)
                wide   = {1'b0, a} << b[4:0];
            end

            `ALU_SHR: begin
                result = a >> b[4:0];     // shift lógico à direita
            end

            `ALU_SHRS: begin
                result = $signed(a) >>> b[4:0];  // shift aritmético
            end

            `ALU_PASS: result = a;

            default:   result = 32'h0;
        endcase
    end

    // ------------------------------------------------------------------
    // Flags derivadas
    // ------------------------------------------------------------------
    assign flag_z = (result == 32'b0);
    assign flag_n = result[31];
    assign flag_c = wide[32];   // carry-out (válido para ADD/SUB/SHL)

endmodule
