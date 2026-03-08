// ============================================================================
// pipeline_id.v  —  Registrador de Pipeline ID/EX — EduRISC-32
//
// Captura todos os sinais gerados no estágio ID (decode) e os propaga
// para o estágio EX.
//
// Dados propagados:
//  • PC, opcode, rd, rs1, rs2
//  • rs1_data, rs2_data  (lidos do banco de registradores)
//  • imm20, offset20, addr28
//  • Sinais de controle: reg_write, mem_read, mem_write, mem_to_reg,
//    alu_src, branch, jump, is_call, is_ret, halt, alu_op
//
// Controle:
//  stall — injeta bolha (NOP): zera todos os sinais de controle
//  flush — igual ao stall (NOP após branch taken)
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_id (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // -- Entradas do estágio ID --
    input  wire [27:0] pc_in,
    input  wire [3:0]  opcode_in,
    input  wire [3:0]  rd_in,
    input  wire [3:0]  rs1_in,
    input  wire [3:0]  rs2_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm20_in,
    input  wire [31:0] offset20_in,
    input  wire [27:0] addr28_in,

    // Sinais de controle vindos da control_unit
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        alu_src_in,
    input  wire        branch_in,
    input  wire        jump_in,
    input  wire        is_call_in,
    input  wire        is_ret_in,
    input  wire        halt_in,
    input  wire [3:0]  alu_op_in,

    // -- Saídas do registrador ID/EX --
    output reg  [27:0] idex_pc,
    output reg  [3:0]  idex_opcode,
    output reg  [3:0]  idex_rd,
    output reg  [3:0]  idex_rs1,
    output reg  [3:0]  idex_rs2,
    output reg  [31:0] idex_rs1_data,
    output reg  [31:0] idex_rs2_data,
    output reg  [31:0] idex_imm20,
    output reg  [31:0] idex_offset20,
    output reg  [27:0] idex_addr28,

    output reg         idex_reg_write,
    output reg         idex_mem_read,
    output reg         idex_mem_write,
    output reg         idex_mem_to_reg,
    output reg         idex_alu_src,
    output reg         idex_branch,
    output reg         idex_jump,
    output reg         idex_is_call,
    output reg         idex_is_ret,
    output reg         idex_halt,
    output reg  [3:0]  idex_alu_op
);

    task inject_nop;
        begin
            idex_pc        <= 28'b0;
            idex_opcode    <= 4'b0;
            idex_rd        <= 4'b0;
            idex_rs1       <= 4'b0;
            idex_rs2       <= 4'b0;
            idex_rs1_data  <= 32'b0;
            idex_rs2_data  <= 32'b0;
            idex_imm20     <= 32'b0;
            idex_offset20  <= 32'b0;
            idex_addr28    <= 28'b0;
            idex_reg_write  <= 1'b0;
            idex_mem_read   <= 1'b0;
            idex_mem_write  <= 1'b0;
            idex_mem_to_reg <= 1'b0;
            idex_alu_src    <= 1'b0;
            idex_branch     <= 1'b0;
            idex_jump       <= 1'b0;
            idex_is_call    <= 1'b0;
            idex_is_ret     <= 1'b0;
            idex_halt       <= 1'b0;
            idex_alu_op     <= `ALU_ADD;
        end
    endtask

    always @(posedge clk) begin
        if (rst || stall || flush) begin
            inject_nop;
        end else begin
            idex_pc        <= pc_in;
            idex_opcode    <= opcode_in;
            idex_rd        <= rd_in;
            idex_rs1       <= rs1_in;
            idex_rs2       <= rs2_in;
            idex_rs1_data  <= rs1_data_in;
            idex_rs2_data  <= rs2_data_in;
            idex_imm20     <= imm20_in;
            idex_offset20  <= offset20_in;
            idex_addr28    <= addr28_in;
            idex_reg_write  <= reg_write_in;
            idex_mem_read   <= mem_read_in;
            idex_mem_write  <= mem_write_in;
            idex_mem_to_reg <= mem_to_reg_in;
            idex_alu_src    <= alu_src_in;
            idex_branch     <= branch_in;
            idex_jump       <= jump_in;
            idex_is_call    <= is_call_in;
            idex_is_ret     <= is_ret_in;
            idex_halt       <= halt_in;
            idex_alu_op     <= alu_op_in;
        end
    end

endmodule
