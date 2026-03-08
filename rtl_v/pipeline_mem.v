// ============================================================================
// pipeline_mem.v  —  Registrador de Pipeline MEM/WB
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_mem (
    input  wire        clk,
    input  wire        rst,

    // Entradas do estágio MEM
    input  wire [4:0]  mem_rd,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_read_data,    // dado lido da memória
    input  wire [5:0]  mem_op,
    input  wire        mem_reg_write,
    input  wire        mem_mem_to_reg,
    input  wire        mem_halt,
    input  wire        mem_trap_valid,
    input  wire [4:0]  mem_trap_cause,

    // Saídas para WB
    output reg  [4:0]  wb_rd,
    output reg  [31:0] wb_alu_result,
    output reg  [31:0] wb_read_data,
    output reg  [5:0]  wb_op,
    output reg         wb_reg_write,
    output reg         wb_mem_to_reg,
    output reg         wb_halt,
    output reg         wb_trap_valid,
    output reg  [4:0]  wb_trap_cause
);

    always @(posedge clk) begin
        if (rst) begin
            wb_rd         <= 5'b0;
            wb_alu_result <= 32'b0;
            wb_read_data  <= 32'b0;
            wb_op         <= `OP_NOP;
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= 1'b0;
            wb_halt       <= 1'b0;
            wb_trap_valid <= 1'b0;
            wb_trap_cause <= 5'b0;
        end else begin
            wb_rd         <= mem_rd;
            wb_alu_result <= mem_alu_result;
            wb_read_data  <= mem_read_data;
            wb_op         <= mem_op;
            wb_reg_write  <= mem_reg_write;
            wb_mem_to_reg <= mem_mem_to_reg;
            wb_halt       <= mem_halt;
            wb_trap_valid <= mem_trap_valid;
            wb_trap_cause <= mem_trap_cause;
        end
    end

endmodule
