// ============================================================================
// register_file.v  —  Banco de 32 registradores × 32 bits
//
// • R0 hardwired = 0 (escrita para R0 é descartada)
// • R30 = SP (Stack Pointer), R31 = LR (Link Register) por convenção
// • Leitura: combinacional (2 portas de leitura independentes)
// • Escrita: síncrona na subida do clock
// • Reset síncrono: zera todos os registradores
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module register_file (
    input  wire        clk,
    input  wire        rst,

    // Porta de leitura A
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    // Porta de leitura B
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // Porta de escrita (WB)
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [31:0] wr_data,

    // Acesso direto para debug / FPGA top
    output wire [31:0] sp_out,   // R30
    output wire [31:0] lr_out    // R31
);

    reg [31:0] regs [0:31];
    integer i;

    // ------------------------------------------------------------------
    // Escrita síncrona (R0 protegido contra escrita)
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (wr_en && wr_addr != 5'b0) begin
            regs[wr_addr] <= wr_data;
        end
    end

    // ------------------------------------------------------------------
    // Leitura combinacional (R0 sempre retorna 0)
    // ------------------------------------------------------------------
    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];

    // Saídas especiais para monitoramento
    assign sp_out = regs[30];
    assign lr_out = regs[31];

endmodule
