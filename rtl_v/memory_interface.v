// ============================================================================
// memory_interface.v  —  Interface de Memória — EduRISC-32
//
// Provê duas memórias independentes de porta única:
//
//  IMEM — Memória de Instrução (read-only durante operação normal)
//    • 2^20 palavras × 32 bits (4 MB)
//    • Leitura combinacional (address → data no mesmo ciclo)
//    • Inicialização via $readmemh (arquivo hex) ou parâmetro
//
//  DMEM — Memória de Dados (leitura/escrita)
//    • 2^20 palavras × 32 bits (4 MB)
//    • Escrita síncrona (posedge clk, when mem_write)
//    • Leitura combinacional (address → data no mesmo ciclo)
//
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module memory_interface #(
    parameter IMEM_INIT_FILE = "",   // caminho para .hex de instrução (opcional)
    parameter DMEM_DEPTH     = `MEM_DEPTH,
    parameter IMEM_DEPTH     = `MEM_DEPTH
) (
    input  wire        clk,
    input  wire        rst,

    // Porta da IMEM (somente leitura)
    input  wire [27:0] imem_addr,          // endereço de instrução (de PC)
    output wire [31:0] imem_data,          // instrução lida

    // Porta da DMEM — leitura
    input  wire [27:0] dmem_addr,          // endereço de dado
    input  wire        dmem_read,
    output wire [31:0] dmem_rdata,         // dado lido

    // Porta da DMEM — escrita
    input  wire        dmem_write,
    input  wire [31:0] dmem_wdata          // dado a escrever
);

    // ------------------------------------------------------------------
    // Memória de Instrução
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] imem [0:IMEM_DEPTH-1];

    initial begin
        if (IMEM_INIT_FILE != "")
            $readmemh(IMEM_INIT_FILE, imem);
    end

    // Leitura combinacional — trunca para a profundidade disponível
    assign imem_data = imem[imem_addr[19:0]];

    // ------------------------------------------------------------------
    // Memória de Dados
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] dmem [0:DMEM_DEPTH-1];

    // Escrita síncrona
    always @(posedge clk) begin
        if (dmem_write)
            dmem[dmem_addr[19:0]] <= dmem_wdata;
    end

    // Leitura combinacional
    assign dmem_rdata = dmem_read ? dmem[dmem_addr[19:0]] : 32'b0;

endmodule
