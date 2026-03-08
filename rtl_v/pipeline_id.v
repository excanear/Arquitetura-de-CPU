// ============================================================================
// pipeline_id.v  —  Registrador de Pipeline ID/EX
//
// Captura todas as saídas do estágio ID (valores de registradores, imediatos,
// sinais de controle) e as propaga para EX.
// Quando stall ou flush: injeta NOP (zerando os sinais de controle).
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_id (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // ---- Dados do estágio ID ----
    input  wire [25:0] id_pc,
    input  wire [4:0]  id_rd,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire [31:0] id_imm,         // imediato selecionado (sext/zext/upper)
    input  wire [25:0] id_addr26,      // para J-type
    input  wire [5:0]  id_op,

    // ---- Sinais de controle do estágio ID ----
    input  wire        id_reg_write,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire        id_mem_to_reg,
    input  wire [1:0]  id_mem_size,
    input  wire        id_mem_signed,
    input  wire        id_alu_src_b,
    input  wire        id_is_branch,
    input  wire        id_is_jump,
    input  wire        id_is_call,
    input  wire        id_is_ret,
    input  wire        id_is_push,
    input  wire        id_is_pop,
    input  wire        id_is_system,
    input  wire        id_halt,
    input  wire        id_trap_valid,
    input  wire [4:0]  id_trap_cause,
    input  wire [4:0]  id_alu_op,

    // ---- Saídas para o estágio EX ----
    output reg  [25:0] ex_pc,
    output reg  [4:0]  ex_rd,
    output reg  [4:0]  ex_rs1,
    output reg  [4:0]  ex_rs2,
    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg  [31:0] ex_imm,
    output reg  [25:0] ex_addr26,
    output reg  [5:0]  ex_op,

    output reg         ex_reg_write,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg         ex_mem_to_reg,
    output reg  [1:0]  ex_mem_size,
    output reg         ex_mem_signed,
    output reg         ex_alu_src_b,
    output reg         ex_is_branch,
    output reg         ex_is_jump,
    output reg         ex_is_call,
    output reg         ex_is_ret,
    output reg         ex_is_push,
    output reg         ex_is_pop,
    output reg         ex_is_system,
    output reg         ex_halt,
    output reg         ex_trap_valid,
    output reg  [4:0]  ex_trap_cause,
    output reg  [4:0]  ex_alu_op
);

    task inject_nop;
        begin
            ex_pc        <= 26'b0;
            ex_rd        <= 5'b0;
            ex_rs1       <= 5'b0;
            ex_rs2       <= 5'b0;
            ex_rs1_data  <= 32'b0;
            ex_rs2_data  <= 32'b0;
            ex_imm       <= 32'b0;
            ex_addr26    <= 26'b0;
            ex_op        <= `OP_NOP;
            ex_reg_write <= 1'b0;
            ex_mem_read  <= 1'b0;
            ex_mem_write <= 1'b0;
            ex_mem_to_reg<= 1'b0;
            ex_mem_size  <= 2'b00;
            ex_mem_signed<= 1'b0;
            ex_alu_src_b <= 1'b0;
            ex_is_branch <= 1'b0;
            ex_is_jump   <= 1'b0;
            ex_is_call   <= 1'b0;
            ex_is_ret    <= 1'b0;
            ex_is_push   <= 1'b0;
            ex_is_pop    <= 1'b0;
            ex_is_system <= 1'b0;
            ex_halt      <= 1'b0;
            ex_trap_valid<= 1'b0;
            ex_trap_cause<= 5'b0;
            ex_alu_op    <= `ALU_ADD;
        end
    endtask

    always @(posedge clk) begin
        if (rst || flush || stall) begin
            inject_nop;
        end else begin
            ex_pc        <= id_pc;
            ex_rd        <= id_rd;
            ex_rs1       <= id_rs1;
            ex_rs2       <= id_rs2;
            ex_rs1_data  <= id_rs1_data;
            ex_rs2_data  <= id_rs2_data;
            ex_imm       <= id_imm;
            ex_addr26    <= id_addr26;
            ex_op        <= id_op;
            ex_reg_write <= id_reg_write;
            ex_mem_read  <= id_mem_read;
            ex_mem_write <= id_mem_write;
            ex_mem_to_reg<= id_mem_to_reg;
            ex_mem_size  <= id_mem_size;
            ex_mem_signed<= id_mem_signed;
            ex_alu_src_b <= id_alu_src_b;
            ex_is_branch <= id_is_branch;
            ex_is_jump   <= id_is_jump;
            ex_is_call   <= id_is_call;
            ex_is_ret    <= id_is_ret;
            ex_is_push   <= id_is_push;
            ex_is_pop    <= id_is_pop;
            ex_is_system <= id_is_system;
            ex_halt      <= id_halt;
            ex_trap_valid<= id_trap_valid;
            ex_trap_cause<= id_trap_cause;
            ex_alu_op    <= id_alu_op;
        end
    end

endmodule
