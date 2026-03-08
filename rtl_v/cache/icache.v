// ============================================================================
// icache.v  —  I-Cache L1 Direct-Mapped (Instruction Cache)
//
// Configuração:
//   • 256 conjuntos (sets)
//   • 4 palavras por linha (cache line = 16 bytes)
//   • Mapeamento direto (1 via)
//   • Substituição: automática (direct-mapped não precisa de LRU)
//   • Política: read-only (instruções não são alteradas pelo pipeline)
//
// Endereço de palavra (26 bits):
//   [25:10] = tag (16 bits)
//   [9:2]   = index (8 bits → 256 linhas)
//   [1:0]   = word offset dentro da linha (0..3)
//
// Hit: 0 ciclos de latência (combinacional)
// Miss: 4 ciclos (busca 4 palavras consecutivas da BRAM)
// ============================================================================
`timescale 1ns/1ps

module icache #(
    parameter SETS      = 256,    // 2^8
    parameter WAYS      = 1,      // direct-mapped
    parameter LINE_WORDS= 4       // palavras de 32-bit por linha
) (
    input  wire        clk,
    input  wire        rst,

    // Interface com o pipeline (IF stage)
    input  wire [25:0] cpu_addr,       // word address pedido pelo IF
    input  wire        cpu_req,        // pedido de instrução válido
    output wire [31:0] cpu_data,       // instrução entregue
    output wire        cpu_hit,        // 1=hit (dado válido neste ciclo)
    output wire        cpu_stall,      // 1=cache miss, stall o pipeline

    // Interface com a memória principal (BRAM)
    output wire [25:0] mem_addr,       // endereço da linha (alinhado)
    output wire        mem_req,        // pedido de fill
    input  wire [31:0] mem_data,       // palavra entregue pela BRAM
    input  wire        mem_valid,      // BRAM resposta válida

    // Monitoramento
    output wire        miss_event      // pulso em miss (para perf counter)
);

    localparam INDEX_W = 8;
    localparam TAG_W   = 16;
    localparam OFF_W   = 2;

    // ------------------------------------------------------------------
    // Arrays do cache
    // ------------------------------------------------------------------
    reg [TAG_W-1:0]              tag_array  [0:SETS-1];
    reg [LINE_WORDS*32-1:0]      data_array [0:SETS-1]; // 128 bits por linha
    reg                          valid_array[0:SETS-1];

    // Decomposição de endereço
    wire [TAG_W-1:0]   req_tag   = cpu_addr[25:10];
    wire [INDEX_W-1:0] req_index = cpu_addr[9:2];
    wire [OFF_W-1:0]   req_off   = cpu_addr[1:0];

    // Hit?
    wire tag_match = valid_array[req_index] && (tag_array[req_index] == req_tag);
    assign cpu_hit  = cpu_req && tag_match;
    assign cpu_stall= cpu_req && !tag_match;

    // Palavra selecionada da linha
    wire [127:0] line_data = data_array[req_index];
    assign cpu_data = (req_off == 2'd0) ? line_data[31:0]   :
                      (req_off == 2'd1) ? line_data[63:32]  :
                      (req_off == 2'd2) ? line_data[95:64]  :
                                          line_data[127:96];

    // ------------------------------------------------------------------
    // Cache fill FSM
    // ------------------------------------------------------------------
    localparam IDLE   = 2'd0;
    localparam FILL   = 2'd1;
    localparam UPDATE = 2'd2;

    reg [1:0]   state;
    reg [1:0]   fill_cnt;
    reg [127:0] fill_buf;
    reg [25:0]  miss_addr_latch;

    assign mem_req  = (state == FILL);
    assign mem_addr = {miss_addr_latch[25:2], fill_cnt}; // word 0..3

    assign miss_event = (state == IDLE) && cpu_req && !tag_match;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            fill_cnt  <= 2'b0;
            for (i = 0; i < SETS; i = i + 1) valid_array[i] <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req && !tag_match) begin
                        miss_addr_latch <= cpu_addr;
                        fill_cnt        <= 2'b0;
                        state           <= FILL;
                    end
                end
                FILL: begin
                    if (mem_valid) begin
                        case (fill_cnt)
                            2'd0: fill_buf[31:0]   <= mem_data;
                            2'd1: fill_buf[63:32]  <= mem_data;
                            2'd2: fill_buf[95:64]  <= mem_data;
                            2'd3: fill_buf[127:96] <= mem_data;
                        endcase
                        if (fill_cnt == 2'd3)
                            state <= UPDATE;
                        else
                            fill_cnt <= fill_cnt + 1;
                    end
                end
                UPDATE: begin
                    data_array [miss_addr_latch[9:2]] <= fill_buf;
                    tag_array  [miss_addr_latch[9:2]] <= miss_addr_latch[25:10];
                    valid_array[miss_addr_latch[9:2]] <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
