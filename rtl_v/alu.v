// ============================================================================
// alu.v  —  Unidade Lógica e Aritmética (ALU) EduRISC-32v2
//
// Operações: ADD SUB MUL MULH DIV DIVU REM AND OR XOR NOT NEG
//            SHL SHR SHRA SLT SLTU PASS_A PASS_B
//
// Flags: ZERO(Z), CARRY(C), NEGATIVE(N), OVERFLOW(V), DIV_BY_ZERO(D)
//
// Notas:
//  • MUL/MULH usam multiplicador de 64 bits (síntese infere DSP48E)
//  • DIV/DIVU/REM: divisão por zero retorna 0xFFFFFFFF e levanta D
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module alu (
    input  wire [4:0]  alu_op,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,

    output reg  [31:0] result,
    output wire        flag_z,
    output wire        flag_c,
    output wire        flag_n,
    output wire        flag_v,
    output wire        flag_d     // divide by zero
);

    // Auxiliares de 64 bits para multiplicação e carry
    wire [63:0] mul_wide   = $signed(operand_a) * $signed(operand_b);
    wire [63:0] mulu_wide  = operand_a * operand_b;
    wire [32:0] add_wide   = {1'b0, operand_a} + {1'b0, operand_b};
    wire [32:0] sub_wide   = {1'b0, operand_a} - {1'b0, operand_b};

    reg [31:0] r_next;
    reg        carry_out;
    reg        div_zero;

    always @(*) begin
        r_next    = 32'b0;
        carry_out = 1'b0;
        div_zero  = 1'b0;

        case (alu_op)
            `ALU_ADD:  begin r_next = add_wide[31:0]; carry_out = add_wide[32]; end
            `ALU_SUB:  begin r_next = sub_wide[31:0]; carry_out = sub_wide[32]; end
            `ALU_MUL:  r_next = mul_wide[31:0];
            `ALU_MULH: r_next = mul_wide[63:32];
            `ALU_DIV:  begin
                           if (operand_b == 0) begin r_next = 32'hFFFFFFFF; div_zero = 1; end
                           else r_next = $signed(operand_a) / $signed(operand_b);
                       end
            `ALU_DIVU: begin
                           if (operand_b == 0) begin r_next = 32'hFFFFFFFF; div_zero = 1; end
                           else r_next = operand_a / operand_b;
                       end
            `ALU_REM:  begin
                           if (operand_b == 0) begin r_next = operand_a; div_zero = 1; end
                           else r_next = $signed(operand_a) % $signed(operand_b);
                       end
            `ALU_AND:  r_next = operand_a & operand_b;
            `ALU_OR:   r_next = operand_a | operand_b;
            `ALU_XOR:  r_next = operand_a ^ operand_b;
            `ALU_NOT:  r_next = ~operand_a;
            `ALU_NEG:  r_next = (~operand_a) + 32'd1;
            `ALU_SHL:  r_next = operand_a << operand_b[4:0];
            `ALU_SHR:  r_next = operand_a >> operand_b[4:0];
            `ALU_SHRA: r_next = $signed(operand_a) >>> operand_b[4:0];
            `ALU_SLT:  r_next = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU: r_next = (operand_a < operand_b) ? 32'd1 : 32'd0;
            `ALU_PASS_A: r_next = operand_a;
            `ALU_PASS_B: r_next = operand_b;
            default:   r_next = 32'b0;
        endcase
    end

    always @(*) result = r_next;

    // Flags
    assign flag_z = (r_next == 32'b0);
    assign flag_n = r_next[31];
    assign flag_c = carry_out;
    assign flag_d = div_zero;
    // Overflow: válido apenas para ADD/SUB (dois complementos)
    assign flag_v = (alu_op == `ALU_ADD) ?
                        (~operand_a[31] & ~operand_b[31] & r_next[31]) |
                        ( operand_a[31] &  operand_b[31] & ~r_next[31]) :
                    (alu_op == `ALU_SUB) ?
                        (~operand_a[31] &  operand_b[31] & r_next[31]) |
                        ( operand_a[31] & ~operand_b[31] & ~r_next[31]) :
                        1'b0;

endmodule
