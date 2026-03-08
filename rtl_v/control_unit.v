// ============================================================================
// control_unit.v  —  Unidade de Controle — EduRISC-32
//
// Decodifica o opcode e gera todos os sinais de controle para o pipeline.
//
// Tabela de sinais:
//  reg_write  — habilita escrita no banco de registradores no estágio WB
//  mem_read   — habilita leitura da memória de dados (LOAD)
//  mem_write  — habilita escrita  na memória de dados (STORE)
//  mem_to_reg — 0=ALU result  1=dado da memória vai para rd
//  alu_src    — 0=rs2  1=imediato/offset
//  branch     — sinaliza instrução de desvio condicional
//  jump       — sinaliza desvio incondicional (JMP / CALL)
//  is_call    — salva PC+1 em R15
//  is_ret     — busca endereço de retorno em R15
//  halt       — pipeline deve parar
//  alu_op     — operação ALU a executar
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module control_unit (
    input  wire [3:0]  opcode,

    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,
    output reg         alu_src,
    output reg         branch,
    output reg         jump,
    output reg         is_call,
    output reg         is_ret,
    output reg         halt,
    output reg  [3:0]  alu_op
);

    always @(*) begin
        // Defaults seguros — NOP
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        is_call    = 1'b0;
        is_ret     = 1'b0;
        halt       = 1'b0;
        alu_op     = `ALU_ADD;

        case (opcode)
            `OP_ADD: begin
                reg_write = 1'b1;
                alu_op    = `ALU_ADD;
            end
            `OP_SUB: begin
                reg_write = 1'b1;
                alu_op    = `ALU_SUB;
            end
            `OP_MUL: begin
                reg_write = 1'b1;
                alu_op    = `ALU_MUL;
            end
            `OP_DIV: begin
                reg_write = 1'b1;
                alu_op    = `ALU_DIV;
            end
            `OP_AND: begin
                reg_write = 1'b1;
                alu_op    = `ALU_AND;
            end
            `OP_OR: begin
                reg_write = 1'b1;
                alu_op    = `ALU_OR;
            end
            `OP_XOR: begin
                reg_write = 1'b1;
                alu_op    = `ALU_XOR;
            end
            `OP_NOT: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;   // NOT usa apenas rs1
                alu_op    = `ALU_NOT;
            end
            `OP_LOAD: begin
                // rd = Mem[base + offset20]
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_src    = 1'b1;   // ALU calcula endereço: base + offset20
                alu_op     = `ALU_ADD;
            end
            `OP_STORE: begin
                // Mem[base + offset20] = rs1
                mem_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = `ALU_ADD;
            end
            `OP_JMP: begin
                jump   = 1'b1;
                alu_op = `ALU_PASS;
            end
            `OP_JZ: begin
                branch = 1'b1;
                alu_op = `ALU_CMP;  // flag Z avalia condição
            end
            `OP_JNZ: begin
                branch = 1'b1;
                alu_op = `ALU_CMP;
            end
            `OP_CALL: begin
                jump    = 1'b1;
                is_call = 1'b1;
                reg_write = 1'b1;   // escreve PC+1 em R15
                alu_op  = `ALU_PASS;
            end
            `OP_RET: begin
                is_ret = 1'b1;
                jump   = 1'b1;
                alu_op = `ALU_PASS;
            end
            `OP_HLT: begin
                halt = 1'b1;
            end
            default: begin
                // NOP — instrução desconhecida, todos defaults
            end
        endcase
    end

endmodule
