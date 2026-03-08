// ============================================================================
// memory_interface.v  —  Interface de Memória Interna (BRAM)
//
// IMEM: instrução (somente leitura, inicializado via $readmemh)
// DMEM: dados (leitura/escrita com suporte a byte, halfword, word)
//
// Ambas as memórias são endereçadas em palavras de 32 bits (byte_addr >> 2).
// Suporte a acesso por byte e halfword usando byte-enable.
//
// Layout de endereço:
//   [19:0] = índice na memória (word-addressed, depth=1M)
//
// Byte lanes (para DMEM):
//   mem_size=WORD (2'b00): be=4'b1111
//   mem_size=HALF (2'b01): be=4'b0011 (half inferior) ou 4'b1100 (half superior)
//   mem_size=BYTE (2'b10): be=4'b0001/0010/0100/1000 conforme addr[1:0]
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module memory_interface #(
    parameter IMEM_INIT_FILE = "",
    parameter MEM_DEPTH      = `MEM_DEPTH
) (
    input  wire        clk,
    input  wire        rst,

    // Porta IMEM (somente leitura)
    input  wire [25:0] imem_addr,       // word address
    output wire [31:0] imem_data,

    // Porta DMEM — leitura
    input  wire        dmem_rd_en,
    input  wire [31:0] dmem_rd_addr,    // byte address
    input  wire [1:0]  dmem_rd_size,    // MEM_WORD / MEM_HALF / MEM_BYTE
    input  wire        dmem_rd_signed,
    output reg  [31:0] dmem_rd_data,

    // Porta DMEM — escrita (síncrona)
    input  wire        dmem_wr_en,
    input  wire [31:0] dmem_wr_addr,    // byte address
    input  wire [1:0]  dmem_wr_size,
    input  wire [31:0] dmem_wr_data
);

    // ------------------------------------------------------------------
    // IMEM — somente leitura, inicializado por $readmemh
    // ------------------------------------------------------------------
    (* rom_style = "block" *)
    reg [31:0] imem [0:MEM_DEPTH-1];

    initial begin
        if (IMEM_INIT_FILE != "") begin
            $readmemh(IMEM_INIT_FILE, imem);
        end
    end

    assign imem_data = imem[imem_addr[19:0]];

    // ------------------------------------------------------------------
    // DMEM — leitura/escrita com suporte a tamanho variável
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] dmem [0:MEM_DEPTH-1];

    wire [19:0] wr_word_addr = dmem_wr_addr[21:2];
    wire [1:0]  wr_byte_off  = dmem_wr_addr[1:0];
    wire [19:0] rd_word_addr = dmem_rd_addr[21:2];
    wire [1:0]  rd_byte_off  = dmem_rd_addr[1:0];

    // ---- Escrita síncrona ----
    always @(posedge clk) begin
        if (dmem_wr_en) begin
            case (dmem_wr_size)
                `MEM_WORD: dmem[wr_word_addr] <= dmem_wr_data;
                `MEM_HALF: begin
                    case (wr_byte_off[1])
                        1'b0: dmem[wr_word_addr][15:0]  <= dmem_wr_data[15:0];
                        1'b1: dmem[wr_word_addr][31:16] <= dmem_wr_data[15:0];
                    endcase
                end
                `MEM_BYTE: begin
                    case (wr_byte_off)
                        2'b00: dmem[wr_word_addr][7:0]   <= dmem_wr_data[7:0];
                        2'b01: dmem[wr_word_addr][15:8]  <= dmem_wr_data[7:0];
                        2'b10: dmem[wr_word_addr][23:16] <= dmem_wr_data[7:0];
                        2'b11: dmem[wr_word_addr][31:24] <= dmem_wr_data[7:0];
                    endcase
                end
                default: dmem[wr_word_addr] <= dmem_wr_data;
            endcase
        end
    end

    // ---- Leitura combinacional ----
    wire [31:0] raw_word = dmem[rd_word_addr];

    always @(*) begin
        if (!dmem_rd_en) begin
            dmem_rd_data = 32'b0;
        end else begin
            case (dmem_rd_size)
                `MEM_WORD: dmem_rd_data = raw_word;
                `MEM_HALF: begin
                    case (rd_byte_off[1])
                        1'b0: dmem_rd_data = dmem_rd_signed ?
                                  {{16{raw_word[15]}}, raw_word[15:0]} :
                                  {16'b0, raw_word[15:0]};
                        1'b1: dmem_rd_data = dmem_rd_signed ?
                                  {{16{raw_word[31]}}, raw_word[31:16]} :
                                  {16'b0, raw_word[31:16]};
                    endcase
                end
                `MEM_BYTE: begin
                    case (rd_byte_off)
                        2'b00: dmem_rd_data = dmem_rd_signed ?
                                   {{24{raw_word[7]}},  raw_word[7:0]}   :
                                   {24'b0, raw_word[7:0]};
                        2'b01: dmem_rd_data = dmem_rd_signed ?
                                   {{24{raw_word[15]}}, raw_word[15:8]}  :
                                   {24'b0, raw_word[15:8]};
                        2'b10: dmem_rd_data = dmem_rd_signed ?
                                   {{24{raw_word[23]}}, raw_word[23:16]} :
                                   {24'b0, raw_word[23:16]};
                        2'b11: dmem_rd_data = dmem_rd_signed ?
                                   {{24{raw_word[31]}}, raw_word[31:24]} :
                                   {24'b0, raw_word[31:24]};
                    endcase
                end
                default: dmem_rd_data = raw_word;
            endcase
        end
    end

endmodule
