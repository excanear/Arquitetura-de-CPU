// ============================================================================
// pipeline_wb.v  —  Estágio WB (Write-Back) — puramente combinacional
//
// Seleciona entre resultado da ALU e dado lido da memória.
// ============================================================================
`timescale 1ns/1ps

module pipeline_wb (
    input  wire        mem_to_reg,
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_read_data,
    output wire [31:0] wb_data
);

    assign wb_data = mem_to_reg ? mem_read_data : alu_result;

endmodule
