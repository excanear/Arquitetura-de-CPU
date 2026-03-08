// ============================================================================
// program_counter.v  —  Program Counter de 26 bits
//
// • PC current: saída registrada
// • pc_plus1: PC+1 (próxima instrução sequencial)
// • Entradas: stall congela PC; load_en escreve pc_load_val
// • Reset: PC = 0 (endereço do bootloader/rstvec)
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module program_counter (
    input  wire        clk,
    input  wire        rst,

    // Controle
    input  wire        stall,       // 1=congela PC (load-use hazard)
    input  wire        load_en,     // 1=carrega pc_load_val
    input  wire [25:0] pc_load_val, // novo PC (desvio/salto/trap)

    // Saídas
    output reg  [25:0] pc,
    output wire [25:0] pc_plus1
);

    assign pc_plus1 = pc + 26'd1;

    always @(posedge clk) begin
        if (rst)
            pc <= 26'b0;
        else if (load_en)
            pc <= pc_load_val;
        else if (!stall)
            pc <= pc_plus1;
    end

endmodule
