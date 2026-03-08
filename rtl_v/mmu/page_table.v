// ============================================================================
// page_table.v  —  Page Table Walker (PTW) — 2 níveis, páginas de 4 KB
//
// Estrutura da tabela de páginas:
//   Nível 1: Page Directory — 1024 entradas de 32-bit (PDE)
//             Endereço físico base: PTBR << 12
//   Nível 2: Page Table     — 1024 entradas de 32-bit (PTE) por PDE
//
// Endereço virtual 32-bit:
//   [31:22] = idx L1 (10 bits) — índice no page directory
//   [21:12] = idx L2 (10 bits) — índice na page table
//   [11:0]  = page offset (4 KB)
//
// PTE/PDE formato:
//   [31:12] = PFN ou next-level physical base >> 12
//   [7]     = D (dirty)
//   [6]     = A (accessed)
//   [4]     = U (user)
//   [3]     = X (execute)
//   [2]     = W (write)
//   [1]     = R (read)
//   [0]     = V (valid)
//
// Latência: 2 ciclos de memória (1 para PDE + 1 para PTE)
// ============================================================================
`timescale 1ns/1ps

module page_table_walker (
    input  wire        clk,
    input  wire        rst,

    // Pedido de tradução
    input  wire [31:0] virt_addr,    // endereço virtual a traduzir
    input  wire        req,          // início de walk
    input  wire [31:0] ptbr,         // CSR PTBR: frame base da L1 table

    // Resultado
    output reg  [19:0] phys_pfn,
    output reg  [7:0]  pte_flags,
    output reg         done,         // 1 ciclo: tradução concluída
    output reg         fault,        // 1 ciclo: page fault (V=0 em algum nível)

    // Interface com a memória física (BRAM)
    output reg  [25:0] mem_addr,     // word address para leitura
    output reg         mem_req,
    input  wire [31:0] mem_data,
    input  wire        mem_valid
);

    localparam IDLE   = 2'd0;
    localparam L1     = 2'd1;   // lendo PDE
    localparam L2     = 2'd2;   // lendo PTE
    localparam DONE   = 2'd3;

    reg [1:0]  state;
    reg [31:0] saved_vaddr;
    reg [31:0] pde_data;

    wire [9:0] l1_idx = virt_addr[31:22];
    wire [9:0] l2_idx = saved_vaddr[21:12];

    // Base frame da L1 table (PTBR holds PFN, page size 4KB = 1K words)
    wire [25:0] l1_base = ptbr[25:0];  // já é endereço físico em palavras >> 2

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            done     <= 1'b0;
            fault    <= 1'b0;
            mem_req  <= 1'b0;
        end else begin
            done    <= 1'b0;
            fault   <= 1'b0;
            mem_req <= 1'b0;

            case (state)
                IDLE: begin
                    if (req) begin
                        saved_vaddr <= virt_addr;
                        // Endereço da PDE: L1_base * 1024 + l1_idx (em palavras)
                        mem_addr <= l1_base + {16'b0, l1_idx};
                        mem_req  <= 1'b1;
                        state    <= L1;
                    end
                end

                L1: begin
                    if (mem_valid) begin
                        pde_data <= mem_data;
                        if (!mem_data[0]) begin   // PDE.V == 0 → page fault
                            fault <= 1'b1;
                            state <= IDLE;
                        end else begin
                            // Endereço da PTE: PDE[31:12] * 1024 + l2_idx
                            mem_addr <= {mem_data[31:12], 6'b0} + {16'b0, l2_idx};
                            mem_req  <= 1'b1;
                            state    <= L2;
                        end
                    end
                end

                L2: begin
                    if (mem_valid) begin
                        if (!mem_data[0]) begin   // PTE.V == 0 → page fault
                            fault <= 1'b1;
                        end else begin
                            phys_pfn  <= mem_data[31:12];
                            pte_flags <= mem_data[7:0];
                            done      <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
