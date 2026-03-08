// ============================================================================
// dcache.v  —  D-Cache L1 Direct-Mapped Write-Back (Data Cache)
//
// Configuração:
//   • 256 conjuntos (sets)
//   • 4 palavras por linha (linha = 16 bytes)
//   • Mapeamento direto
//   • Política: Write-Back + Write-Allocate
//   • Dirty bit por linha (para write-back ao evictar)
//
// Endereço de byte (32 bits):
//   [31:12] = tag (20 bits — mas só usamos [21:12] para tamanho físico)
//   [11:4]  = index (8 bits → 256 linhas)
//   [3:2]   = word offset (0..3)
//   [1:0]   = byte offset (não usado no cache, tratado pelo pipeline)
//
// Hit: 0 ciclos de latência
// Miss: 4-8 ciclos (eviction write-back + fill)
// ============================================================================
`timescale 1ns/1ps

module dcache #(
    parameter SETS       = 256,
    parameter LINE_WORDS = 4
) (
    input  wire        clk,
    input  wire        rst,

    // Interface com pipeline MEM
    input  wire        cpu_req,
    input  wire        cpu_wr,           // 0=read  1=write
    input  wire [31:0] cpu_addr,         // byte address
    input  wire [31:0] cpu_wr_data,
    input  wire [1:0]  cpu_wr_size,      // WORD/HALF/BYTE
    output wire [31:0] cpu_rd_data,
    output wire        cpu_hit,
    output wire        cpu_stall,

    // Interface com memória principal
    output wire [31:0] mem_rd_addr,
    output wire        mem_rd_req,
    input  wire [31:0] mem_rd_data,
    input  wire        mem_rd_valid,

    output wire [31:0] mem_wr_addr,
    output wire        mem_wr_req,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ack,

    // Flush (FENCE instrução)
    input  wire        flush_req,
    output wire        flush_done,

    // Monitoramento
    output wire        miss_event
);

    localparam INDEX_W = 8;
    localparam TAG_W   = 20;

    // ------------------------------------------------------------------
    // Arrays do cache
    // ------------------------------------------------------------------
    reg [TAG_W-1:0]          tag_array  [0:SETS-1];
    reg [LINE_WORDS*32-1:0]  data_array [0:SETS-1];
    reg                      valid_array[0:SETS-1];
    reg                      dirty_array[0:SETS-1];

    // Decomposição de endereço
    wire [TAG_W-1:0]   req_tag   = cpu_addr[31:12];
    wire [INDEX_W-1:0] req_index = cpu_addr[11:4];
    wire [1:0]         req_woff  = cpu_addr[3:2];

    wire tag_match = valid_array[req_index] && (tag_array[req_index] == req_tag);
    assign cpu_hit   = cpu_req && tag_match;
    assign cpu_stall = cpu_req && !tag_match;

    // Palavra selecionada
    wire [127:0] cur_line = data_array[req_index];
    assign cpu_rd_data = (req_woff == 2'd0) ? cur_line[31:0]   :
                         (req_woff == 2'd1) ? cur_line[63:32]  :
                         (req_woff == 2'd2) ? cur_line[95:64]  :
                                              cur_line[127:96];

    // ------------------------------------------------------------------
    // FSM: IDLE → (EVICT →) FILL → UPDATE
    // ------------------------------------------------------------------
    localparam IDLE   = 3'd0;
    localparam EVICT  = 3'd1;
    localparam FILL   = 3'd2;
    localparam UPDATE = 3'd3;
    localparam FLUSH  = 3'd4;

    reg [2:0]   state;
    reg [1:0]   fill_cnt;
    reg [1:0]   evict_cnt;
    reg [127:0] fill_buf;
    reg [31:0]  miss_addr_latch;
    reg [INDEX_W-1:0] flush_idx;

    assign miss_event = (state == IDLE) && cpu_req && !tag_match;

    // Endereço de eviction (reconstituir da tag + index)
    wire [31:0] evict_addr = {tag_array[req_index], req_index, 4'b0};

    reg  evict_word_sel;
    wire [31:0] evict_word = (evict_cnt == 2'd0) ? cur_line[31:0]   :
                              (evict_cnt == 2'd1) ? cur_line[63:32]  :
                              (evict_cnt == 2'd2) ? cur_line[95:64]  :
                                                    cur_line[127:96];

    assign mem_wr_addr = {evict_addr[31:4], evict_cnt, 2'b00};
    assign mem_wr_data = evict_word;
    assign mem_wr_req  = (state == EVICT);

    assign mem_rd_addr = {miss_addr_latch[31:4], fill_cnt, 2'b00};
    assign mem_rd_req  = (state == FILL);

    assign flush_done  = (state == IDLE) && flush_req; // single-cycle flush for simplicity

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            for (i = 0; i < SETS; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (flush_req) begin
                        flush_idx <= 8'b0;
                        state <= FLUSH;
                    end else if (cpu_req && !tag_match) begin
                        miss_addr_latch <= cpu_addr;
                        fill_cnt  <= 2'b0;
                        evict_cnt <= 2'b0;
                        // Se dirty, precisa evictar primeiro
                        state <= (valid_array[req_index] && dirty_array[req_index]) ? EVICT : FILL;
                    end else if (cpu_req && tag_match && cpu_wr) begin
                        // Write hit — atualiza linha e marca dirty
                        dirty_array[req_index] <= 1'b1;
                        case (req_woff)
                            2'd0: data_array[req_index][31:0]   <= cpu_wr_data;
                            2'd1: data_array[req_index][63:32]  <= cpu_wr_data;
                            2'd2: data_array[req_index][95:64]  <= cpu_wr_data;
                            2'd3: data_array[req_index][127:96] <= cpu_wr_data;
                        endcase
                    end
                end
                EVICT: begin
                    if (mem_wr_ack) begin
                        if (evict_cnt == 2'd3) begin
                            dirty_array[req_index] <= 1'b0;
                            state <= FILL;
                            fill_cnt <= 2'b0;
                        end else
                            evict_cnt <= evict_cnt + 1;
                    end
                end
                FILL: begin
                    if (mem_rd_valid) begin
                        case (fill_cnt)
                            2'd0: fill_buf[31:0]   <= mem_rd_data;
                            2'd1: fill_buf[63:32]  <= mem_rd_data;
                            2'd2: fill_buf[95:64]  <= mem_rd_data;
                            2'd3: fill_buf[127:96] <= mem_rd_data;
                        endcase
                        if (fill_cnt == 2'd3)
                            state <= UPDATE;
                        else
                            fill_cnt <= fill_cnt + 1;
                    end
                end
                UPDATE: begin
                    data_array [miss_addr_latch[11:4]] <= fill_buf;
                    tag_array  [miss_addr_latch[11:4]] <= miss_addr_latch[31:12];
                    valid_array[miss_addr_latch[11:4]] <= 1'b1;
                    dirty_array[miss_addr_latch[11:4]] <= cpu_wr; // se era write-miss, vai escrever agora
                    state <= IDLE;
                end
                FLUSH: begin
                    // Invalidar todas as linhas (non-writeback flush para simplicidade)
                    valid_array[flush_idx] <= 1'b0;
                    dirty_array[flush_idx] <= 1'b0;
                    if (flush_idx == 8'hFF)
                        state <= IDLE;
                    else
                        flush_idx <= flush_idx + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
