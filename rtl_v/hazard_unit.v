// ============================================================================
// hazard_unit.v  —  Unidade de Detecção de Hazards — EduRISC-32
//
// Detecta dois tipos de hazard:
//
//  1. Load-Use hazard (bolha de 1 ciclo):
//       Se a instrução EX lê memória (mem_read) e o registrador destino
//       coincide com rs1 ou rs2 da instrução ID, é necessário um stall.
//
//  2. Branch/Jump hazard (flush de 1 ciclo):
//       Quando um desvio/jump é confirmado, a instrução que entrou em IF
//       deve ser descartada (flush do registrador IF/ID).
//
// Saídas:
//  stall   — congela PC e registrador IF/ID por 1 ciclo; injeta bolha em ID/EX
//  flush   — descarta o registrador IF/ID (substitui por NOP)
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module hazard_unit (
    // Campos da instrução em ID (instrução sendo decodificada)
    input  wire [3:0] id_rs1,
    input  wire [3:0] id_rs2,

    // Campos/controle da instrução em EX
    input  wire [3:0] ex_rd,
    input  wire       ex_mem_read,   // LOAD no estágio EX

    // Sinalização de desvio resolvido (gerada no estágio EX)
    input  wire       branch_taken,

    // Saídas de controle do pipeline
    output wire       stall,
    output wire       flush
);

    // Load-use: stall quando LOAD em EX escreve em registrador lido em ID
    wire load_use_hazard;
    assign load_use_hazard = ex_mem_read &&
                             ((ex_rd == id_rs1) || (ex_rd == id_rs2));

    assign stall = load_use_hazard;
    assign flush = branch_taken;

endmodule
