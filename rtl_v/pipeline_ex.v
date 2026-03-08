// ============================================================================
// pipeline_ex.v  —  Registrador de Pipeline EX/MEM
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_ex (
    input  wire        clk,
    input  wire        rst,

    // Entradas do estágio EX
    input  wire [4:0]  ex_rd,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rs2_data,    // dado a armazenar em stores
    input  wire [25:0] ex_branch_target,
    input  wire        ex_branch_taken,
    input  wire [5:0]  ex_op,

    // Controles WB
    input  wire        ex_reg_write,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire        ex_mem_to_reg,
    input  wire [1:0]  ex_mem_size,
    input  wire        ex_mem_signed,
    input  wire        ex_halt,
    input  wire        ex_trap_valid,
    input  wire [4:0]  ex_trap_cause,

    // Saídas para MEM
    output reg  [4:0]  mem_rd,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_rs2_data,
    output reg  [25:0] mem_branch_target,
    output reg         mem_branch_taken,
    output reg  [5:0]  mem_op,
    output reg         mem_reg_write,
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg         mem_mem_to_reg,
    output reg  [1:0]  mem_mem_size,
    output reg         mem_mem_signed,
    output reg         mem_halt,
    output reg         mem_trap_valid,
    output reg  [4:0]  mem_trap_cause
);

    always @(posedge clk) begin
        if (rst) begin
            mem_rd           <= 5'b0;
            mem_alu_result   <= 32'b0;
            mem_rs2_data     <= 32'b0;
            mem_branch_target<= 26'b0;
            mem_branch_taken <= 1'b0;
            mem_op           <= `OP_NOP;
            mem_reg_write    <= 1'b0;
            mem_mem_read     <= 1'b0;
            mem_mem_write    <= 1'b0;
            mem_mem_to_reg   <= 1'b0;
            mem_mem_size     <= 2'b0;
            mem_mem_signed   <= 1'b0;
            mem_halt         <= 1'b0;
            mem_trap_valid   <= 1'b0;
            mem_trap_cause   <= 5'b0;
        end else begin
            mem_rd           <= ex_rd;
            mem_alu_result   <= ex_alu_result;
            mem_rs2_data     <= ex_rs2_data;
            mem_branch_target<= ex_branch_target;
            mem_branch_taken <= ex_branch_taken;
            mem_op           <= ex_op;
            mem_reg_write    <= ex_reg_write;
            mem_mem_read     <= ex_mem_read;
            mem_mem_write    <= ex_mem_write;
            mem_mem_to_reg   <= ex_mem_to_reg;
            mem_mem_size     <= ex_mem_size;
            mem_mem_signed   <= ex_mem_signed;
            mem_halt         <= ex_halt;
            mem_trap_valid   <= ex_trap_valid;
            mem_trap_cause   <= ex_trap_cause;
        end
    end

endmodule
