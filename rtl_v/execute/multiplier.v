// ============================================================================
// multiplier.v  —  Multiplicador de 32×32 bits (pipelined, 3 estágios)
//
// Implementado como pipeline de 3 estágios para atingir alta frequência (>100MHz).
// A síntese infere automaticamente blocos DSP48E (Xilinx) ou 18×18 (Intel).
//
// Latência: 3 ciclos de clock
// Throughput: 1 resultado por ciclo após pipeline cheio
//
// Modos:
//   signed_mode=0 → multiplicação sem sinal (MULU)
//   signed_mode=1 → multiplicação com sinal (MUL, MULH)
//   upper=0       → 32 bits inferiores do produto (MUL)
//   upper=1       → 32 bits superiores do produto (MULH)
// ============================================================================
`timescale 1ns/1ps

module multiplier (
    input  wire        clk,
    input  wire        rst,
    input  wire        valid_in,
    input  wire        signed_mode,
    input  wire        upper,        // 0=inferiores 1=superiores
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result,
    output reg         valid_out
);

    // Estágio 1: registrar operandos
    reg [31:0] a_s1, b_s1;
    reg        signed_s1, upper_s1, valid_s1;

    // Estágio 2: multiplicação (inferência de DSP)
    reg [63:0] product_s2;
    reg        upper_s2, valid_s2;

    // Estágio 3: seleção de metade
    always @(posedge clk) begin
        if (rst) begin
            valid_s1 <= 0; valid_s2 <= 0; valid_out <= 0;
        end else begin
            // S1
            a_s1      <= a;
            b_s1      <= b;
            signed_s1 <= signed_mode;
            upper_s1  <= upper;
            valid_s1  <= valid_in;

            // S2
            if (signed_s1)
                product_s2 <= $signed(a_s1) * $signed(b_s1);
            else
                product_s2 <= a_s1 * b_s1;
            upper_s2  <= upper_s1;
            valid_s2  <= valid_s1;

            // S3
            result    <= upper_s2 ? product_s2[63:32] : product_s2[31:0];
            valid_out <= valid_s2;
        end
    end

endmodule
