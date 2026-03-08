// ============================================================================
// pipeline_mem.v  —  Registrador de Pipeline MEM/WB — EduRISC-32
//
// Captura os resultados do estágio MEM (acesso à memória de dados) e os
// propaga para o estágio WB.
//
// O acesso real à memória é feito em cpu_top (dmem array).
// Este módulo registra: resultado ALU, dado lido da memória e controles WB.
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_mem (
    input  wire        clk,
    input  wire        rst,

    // -- Entradas do resultado MEM --
    input  wire [3:0]  rd_in,
    input  wire [31:0] alu_result_in,   // endereço calculado (passa adiante)
    input  wire [31:0] mem_data_in,     // dado lido da dmem (para LOAD)
    input  wire        halt_in,

    // Sinais de controle WB
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,

    // -- Saídas do registrador MEM/WB --
    output reg  [3:0]  memwb_rd,
    output reg  [31:0] memwb_alu_result,
    output reg  [31:0] memwb_mem_data,
    output reg         memwb_halt,
    output reg         memwb_reg_write,
    output reg         memwb_mem_to_reg
);

    always @(posedge clk) begin
        if (rst) begin
            memwb_rd          <= 4'b0;
            memwb_alu_result  <= 32'b0;
            memwb_mem_data    <= 32'b0;
            memwb_halt        <= 1'b0;
            memwb_reg_write   <= 1'b0;
            memwb_mem_to_reg  <= 1'b0;
        end else begin
            memwb_rd          <= rd_in;
            memwb_alu_result  <= alu_result_in;
            memwb_mem_data    <= mem_data_in;
            memwb_halt        <= halt_in;
            memwb_reg_write   <= reg_write_in;
            memwb_mem_to_reg  <= mem_to_reg_in;
        end
    end

endmodule
