// ============================================================================
// pipeline_ex.v  —  Registrador de Pipeline EX/MEM — EduRISC-32
//
// Captura os resultados do estágio EX (execução ALU) e os propaga para
// o estágio MEM.
//
// O estágio EX em si (muxes de forwarding, ALU, cálculo de branch) é
// implementado diretamente em cpu_top; este módulo apenas registra as
// saídas.
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_ex (
    input  wire        clk,
    input  wire        rst,

    // -- Entradas do resultado EX --
    input  wire [3:0]  rd_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_data_in,    // dado a escrever em STORE
    input  wire [27:0] branch_target_in,
    input  wire        branch_taken_in,

    // Sinais de controle propagados de ID/EX
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        halt_in,

    // -- Saídas do registrador EX/MEM --
    output reg  [3:0]  exmem_rd,
    output reg  [31:0] exmem_alu_result,
    output reg  [31:0] exmem_rs2_data,
    output reg  [27:0] exmem_branch_target,
    output reg         exmem_branch_taken,

    output reg         exmem_reg_write,
    output reg         exmem_mem_read,
    output reg         exmem_mem_write,
    output reg         exmem_mem_to_reg,
    output reg         exmem_halt
);

    always @(posedge clk) begin
        if (rst) begin
            exmem_rd            <= 4'b0;
            exmem_alu_result    <= 32'b0;
            exmem_rs2_data      <= 32'b0;
            exmem_branch_target <= 28'b0;
            exmem_branch_taken  <= 1'b0;
            exmem_reg_write     <= 1'b0;
            exmem_mem_read      <= 1'b0;
            exmem_mem_write     <= 1'b0;
            exmem_mem_to_reg    <= 1'b0;
            exmem_halt          <= 1'b0;
        end else begin
            exmem_rd            <= rd_in;
            exmem_alu_result    <= alu_result_in;
            exmem_rs2_data      <= rs2_data_in;
            exmem_branch_target <= branch_target_in;
            exmem_branch_taken  <= branch_taken_in;
            exmem_reg_write     <= reg_write_in;
            exmem_mem_read      <= mem_read_in;
            exmem_mem_write     <= mem_write_in;
            exmem_mem_to_reg    <= mem_to_reg_in;
            exmem_halt          <= halt_in;
        end
    end

endmodule
