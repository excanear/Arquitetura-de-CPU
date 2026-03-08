// ============================================================================
// pipeline_if.v  —  Estágio IF: Instruction Fetch — EduRISC-32
//
// Responsabilidades:
//  • Apresentar o endereço PC à memória de instrução
//  • Registrar o par (PC, instrução) no registrador de pipeline IF/ID
//
// Controle:
//  stall  — congela o registrador IF/ID (mantém valores atuais)
//  flush  — injeta um NOP (0x00000000) no registrador IF/ID
//
// O módulo não instancia a memória de instrução — recebe a instrução já
// lida combinacionalmente por cpu_top (imem é array externo).
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module pipeline_if (
    input  wire        clk,
    input  wire        rst,

    // Controle de fluxo
    input  wire        stall,
    input  wire        flush,

    // Entradas funcionais
    input  wire [27:0] pc_in,          // PC atual (saída do program_counter)
    input  wire [31:0] instr_in,       // instrução lida da imem

    // Saídas do registrador IF/ID
    output reg  [27:0] ifid_pc,
    output reg  [31:0] ifid_instr
);

    always @(posedge clk) begin
        if (rst) begin
            ifid_pc    <= 28'b0;
            ifid_instr <= 32'b0;
        end else if (flush) begin
            // Flush: injeta NOP
            ifid_pc    <= 28'b0;
            ifid_instr <= 32'b0;
        end else if (!stall) begin
            ifid_pc    <= pc_in;
            ifid_instr <= instr_in;
        end
        // stall && !flush: nenhuma ação — mantém valores
    end

endmodule
