// ============================================================================
// cache_controller.v  —  Controlador de Cache (árbitro I$/D$ ↔ BRAM)
//
// Arbitra acesso entre I-cache e D-cache para a memória principal (BRAM).
// Prioridade: D-cache eviction > D-cache fill > I-cache fill.
//
// Fornece interface uniforme para ambas as caches:
//   - I-cache: somente leitura
//   - D-cache: leitura (fill) e escrita (eviction write-back)
//
// A BRAM interna tem latência de 1 ciclo para leitura.
// O controlador insere o ciclo de latência e gera o sinal mem_valid.
// ============================================================================
`timescale 1ns/1ps

module cache_controller #(
    parameter MEM_DEPTH = (1 << 20)
) (
    input  wire        clk,
    input  wire        rst,

    // Interface I-cache
    input  wire [25:0] ic_req_addr,
    input  wire        ic_req,
    output reg  [31:0] ic_rd_data,
    output reg         ic_rd_valid,

    // Interface D-cache (leitura)
    input  wire [31:0] dc_rd_addr,
    input  wire        dc_rd_req,
    output reg  [31:0] dc_rd_data,
    output reg         dc_rd_valid,

    // Interface D-cache (escrita/eviction)
    input  wire [31:0] dc_wr_addr,
    input  wire [31:0] dc_wr_data,
    input  wire        dc_wr_req,
    output reg         dc_wr_ack
);

    // ------------------------------------------------------------------
    // BRAM compartilhada (mesmo bloco da memória principal)
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] mem [0:MEM_DEPTH-1];

    // ------------------------------------------------------------------
    // Árbitro simples de round-robin com prioridade
    // ------------------------------------------------------------------
    // Ciclos ímpares: D-cache tem prioridade
    // Ciclos pares:   I-cache

    reg pending_ic, pending_dc_rd, pending_dc_wr;
    reg [25:0] ic_lat_addr;
    reg [21:0] dc_rd_lat_addr;
    reg [21:0] dc_wr_lat_addr;
    reg [31:0] dc_wr_lat_data;

    always @(posedge clk) begin
        if (rst) begin
            ic_rd_valid  <= 1'b0;
            dc_rd_valid  <= 1'b0;
            dc_wr_ack    <= 1'b0;
            pending_ic   <= 1'b0;
            pending_dc_rd<= 1'b0;
            pending_dc_wr<= 1'b0;
        end else begin
            // Clear one-cycle pulses
            ic_rd_valid  <= 1'b0;
            dc_rd_valid  <= 1'b0;
            dc_wr_ack    <= 1'b0;

            // Register new requests
            if (ic_req && !pending_ic) begin
                pending_ic  <= 1'b1;
                ic_lat_addr <= ic_req_addr;
            end
            if (dc_rd_req && !pending_dc_rd) begin
                pending_dc_rd  <= 1'b1;
                dc_rd_lat_addr <= dc_rd_addr[21:0];
            end
            if (dc_wr_req && !pending_dc_wr) begin
                pending_dc_wr    <= 1'b1;
                dc_wr_lat_addr   <= dc_wr_addr[21:0];
                dc_wr_lat_data   <= dc_wr_data;
            end

            // Service write first (eviction has priority)
            if (pending_dc_wr) begin
                mem[dc_wr_lat_addr] <= dc_wr_lat_data;
                dc_wr_ack    <= 1'b1;
                pending_dc_wr <= 1'b0;
            end
            // Then D-cache fill
            else if (pending_dc_rd) begin
                dc_rd_data  <= mem[dc_rd_lat_addr];
                dc_rd_valid <= 1'b1;
                pending_dc_rd <= 1'b0;
            end
            // Then I-cache fill
            else if (pending_ic) begin
                ic_rd_data  <= mem[ic_lat_addr[19:0]];
                ic_rd_valid <= 1'b1;
                pending_ic  <= 1'b0;
            end
        end
    end

endmodule
