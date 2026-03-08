// ============================================================================
// pipeline_if.v  —  Registrador de Pipeline IF/ID
//
// Captura saídas do estágio IF (PC, instrução) e as propaga para ID.
// Suporta:
//  stall  — congela o conteúdo (hazard de load-use)
//  flush  — injeta NOP (bolha por desvio tomado)
//
// Previsão de desvio: preditor estático "não tomado" (branch not taken).
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_if (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Entradas do estágio IF
    input  wire [25:0] if_pc,
    input  wire [31:0] if_instr,

    // Saídas para estágio ID
    output reg  [25:0] id_pc,
    output reg  [31:0] id_instr
);

    // NOP codificado: opcode = OP_NOP (6'h31), todos os outros bits = 0
    localparam [31:0] NOP_WORD = {`OP_NOP, 26'b0};

    always @(posedge clk) begin
        if (rst || flush) begin
            id_pc    <= 26'b0;
            id_instr <= NOP_WORD;
        end else if (!stall) begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
        // stall: manter valores atuais (sem modificação)
    end

endmodule
