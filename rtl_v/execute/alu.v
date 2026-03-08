// ============================================================================
// alu.v  —  ALU completa (módulo separado em rtl_v/execute/)
//
// Idêntica à rtl_v/alu.v mas localizada em execute/ para uso independente.
// Ver rtl_v/alu.v para documentação completa.
// ============================================================================
`timescale 1ns/1ps
`include "../isa_pkg.vh"

module alu_unit (
    input  wire [4:0]  alu_op,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg  [31:0] result,
    output wire        flag_z,
    output wire        flag_c,
    output wire        flag_n,
    output wire        flag_v,
    output wire        flag_d
);

    wire [63:0] mul_s  = $signed(operand_a) * $signed(operand_b);
    wire [32:0] add_w  = {1'b0, operand_a} + {1'b0, operand_b};
    wire [32:0] sub_w  = {1'b0, operand_a} - {1'b0, operand_b};

    reg carry_out, div_zero;

    always @(*) begin
        result    = 32'b0;
        carry_out = 1'b0;
        div_zero  = 1'b0;
        case (alu_op)
            `ALU_ADD:  begin result = add_w[31:0]; carry_out = add_w[32]; end
            `ALU_SUB:  begin result = sub_w[31:0]; carry_out = sub_w[32]; end
            `ALU_MUL:  result = mul_s[31:0];
            `ALU_MULH: result = mul_s[63:32];
            `ALU_DIV:  begin
                if (operand_b == 0) begin result = 32'hFFFF_FFFF; div_zero = 1; end
                else result = $signed(operand_a) / $signed(operand_b);
            end
            `ALU_DIVU: begin
                if (operand_b == 0) begin result = 32'hFFFF_FFFF; div_zero = 1; end
                else result = operand_a / operand_b;
            end
            `ALU_REM:  begin
                if (operand_b == 0) begin result = operand_a; div_zero = 1; end
                else result = $signed(operand_a) % $signed(operand_b);
            end
            `ALU_AND:    result = operand_a & operand_b;
            `ALU_OR:     result = operand_a | operand_b;
            `ALU_XOR:    result = operand_a ^ operand_b;
            `ALU_NOT:    result = ~operand_a;
            `ALU_NEG:    result = -operand_a;
            `ALU_SHL:    result = operand_a << operand_b[4:0];
            `ALU_SHR:    result = operand_a >> operand_b[4:0];
            `ALU_SHRA:   result = $signed(operand_a) >>> operand_b[4:0];
            `ALU_SLT:    result = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU:   result = (operand_a < operand_b) ? 32'd1 : 32'd0;
            `ALU_PASS_A: result = operand_a;
            `ALU_PASS_B: result = operand_b;
            default:     result = 32'b0;
        endcase
    end

    assign flag_z = (result == 32'b0);
    assign flag_n = result[31];
    assign flag_c = carry_out;
    assign flag_d = div_zero;
    assign flag_v = (alu_op == `ALU_ADD) ?
                        (~operand_a[31] & ~operand_b[31] & result[31]) |
                        ( operand_a[31] &  operand_b[31] & ~result[31]) :
                    (alu_op == `ALU_SUB) ?
                        (~operand_a[31] &  operand_b[31] & result[31]) |
                        ( operand_a[31] & ~operand_b[31] & ~result[31]) :
                        1'b0;
endmodule
