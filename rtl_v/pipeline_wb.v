// ============================================================================
// pipeline_wb.v  —  Estágio WB: Write-Back — EduRISC-32
//
// Seleciona entre o resultado da ALU e o dado lido da memória para
// escrever no banco de registradores.
//
// Este módulo é puramente combinacional: o mux final antes da porta de
// escrita do register_file.
//
// A escrita em si é feita pelo register_file instanciado em cpu_top.
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_wb (
    // -- Entradas do registrador MEM/WB --
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_data,
    input  wire        mem_to_reg,

    // -- Dado a escrever (saída combinacional) --
    output wire [31:0] wb_data
);

    // 0 = resultado da ALU; 1 = dado da memória (LOAD)
    assign wb_data = mem_to_reg ? mem_data : alu_result;

endmodule
