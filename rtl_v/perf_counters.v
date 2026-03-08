// ============================================================================
// perf_counters.v  —  Contadores de Desempenho EduRISC-32v2
//
// Contadores arquiteturais mapeados em CSRs:
//   CSR 7/8  (CYCLE/CYCLEH)  — ciclos totais de clock (64 bits)
//   CSR 9    (INSTRET)       — instruções completadas (aposentadas)
//   CSR 10   (ICOUNT)        — número de bolhas/stalls
//   CSR 11   (DCMISS)        — faltas no D-cache
//   CSR 12   (ICMISS)        — faltas no I-cache
//   CSR 13   (BRMISS)        — predições de desvio erradas (flushes)
//
// Interface de controle:
//   reset_counters=1 → zera todos os contadores imediatamente
//   read_sel[3:0]     → índice do contador para leitura por CSR MFC
//   read_data[31:0]   → valor retornado
// ============================================================================
`timescale 1ns/1ps

module perf_counters (
    input  wire        clk,
    input  wire        rst,

    // Eventos do pipeline
    input  wire        stall,           // ciclo com stall ativo
    input  wire        pipeline_flush,  // flush por desvio errado
    input  wire        inst_retired,    // instrução chegou ao WB sem bolha
    input  wire        icache_miss,     // leitura de I-cache foi miss
    input  wire        dcache_miss,     // leitura/escrita D-cache foi miss

    // Controle por software (instrução MTC)
    input  wire        reset_counters,  // pulso → zera todos

    // Interface de leitura
    input  wire [3:0]  read_sel,        // 0=CYCLE_LO 1=CYCLE_HI 2=INSTRET
                                        // 3=ICOUNT(stalls) 4=DCMISS
                                        // 5=ICMISS 6=BRMISS
    output reg  [31:0] read_data,

    // Saídas diretas para csr_regfile
    output wire [31:0] cycle_lo,
    output wire [31:0] cycle_hi,
    output wire [31:0] instret,
    output wire [31:0] icount,
    output wire [31:0] dcmiss,
    output wire [31:0] icmiss,
    output wire [31:0] brmiss
);

    // -----------------------------------------------------------------------
    // Registradores internos
    // -----------------------------------------------------------------------
    reg [63:0] r_cycle;
    reg [31:0] r_instret;
    reg [31:0] r_icount;
    reg [31:0] r_dcmiss;
    reg [31:0] r_icmiss;
    reg [31:0] r_brmiss;

    // -----------------------------------------------------------------------
    // Lógica de atualização
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || reset_counters) begin
            r_cycle   <= 64'd0;
            r_instret <= 32'd0;
            r_icount  <= 32'd0;
            r_dcmiss  <= 32'd0;
            r_icmiss  <= 32'd0;
            r_brmiss  <= 32'd0;
        end else begin
            r_cycle   <= r_cycle + 64'd1;
            if (inst_retired)    r_instret <= r_instret + 1;
            if (stall)           r_icount  <= r_icount  + 1;
            if (dcache_miss)     r_dcmiss  <= r_dcmiss  + 1;
            if (icache_miss)     r_icmiss  <= r_icmiss  + 1;
            if (pipeline_flush)  r_brmiss  <= r_brmiss  + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Saídas diretas
    // -----------------------------------------------------------------------
    assign cycle_lo = r_cycle[31:0];
    assign cycle_hi = r_cycle[63:32];
    assign instret  = r_instret;
    assign icount   = r_icount;
    assign dcmiss   = r_dcmiss;
    assign icmiss   = r_icmiss;
    assign brmiss   = r_brmiss;

    // -----------------------------------------------------------------------
    // Leitura multiplexada (para instrução MFC)
    // -----------------------------------------------------------------------
    always @(*) begin
        case (read_sel)
            4'd0:    read_data = r_cycle[31:0];
            4'd1:    read_data = r_cycle[63:32];
            4'd2:    read_data = r_instret;
            4'd3:    read_data = r_icount;
            4'd4:    read_data = r_dcmiss;
            4'd5:    read_data = r_icmiss;
            4'd6:    read_data = r_brmiss;
            default: read_data = 32'd0;
        endcase
    end

endmodule
