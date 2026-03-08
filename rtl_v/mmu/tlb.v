// ============================================================================
// tlb.v  —  TLB (Translation Lookaside Buffer) — 32 entradas, fully associative
//
// Traduz Virtual Page Number → Physical Page Number em 1 ciclo.
// Substituição: pseudo-LRU com contador round-robin (FIFO simplificado).
//
// Endereço virtual: 32-bit
//   [31:12] = VPN (20 bits)
//   [11:0]  = page offset (4 KB)
//
// Endereço físico: 32-bit
//   [31:12] = PFN (20 bits)
//   [11:0]  = page offset (idêntico)
//
// Atributos de página (flags PTE):
//   V=valid  R=read  W=write  X=execute  U=user  D=dirty  A=accessed
// ============================================================================
`timescale 1ns/1ps

module tlb #(
    parameter ENTRIES = 32
) (
    input  wire        clk,
    input  wire        rst,

    // Lookup (combinacional)
    input  wire [19:0] virt_vpn,    // [31:12] do endereço virtual
    input  wire        lookup_req,
    output wire [19:0] phys_pfn,    // [31:12] do endereço físico
    output wire        hit,
    output wire        prot_fault,  // violação de proteção

    // Modo de acesso
    input  wire        access_write, // 0=leitura 1=escrita
    input  wire        access_exec,  // 1=busca de instrução
    input  wire        user_mode,    // 0=kernel 1=user

    // Fill de nova entrada (da page table walk)
    input  wire        fill_valid,
    input  wire [19:0] fill_vpn,
    input  wire [19:0] fill_pfn,
    input  wire [7:0]  fill_flags,   // {D,A,G,U,X,W,R,V}

    // Flush (SFENCE / context switch)
    input  wire        flush
);

    localparam V_BIT = 0;
    localparam R_BIT = 1;
    localparam W_BIT = 2;
    localparam X_BIT = 3;
    localparam U_BIT = 4;
    localparam A_BIT = 5;
    localparam D_BIT = 6;

    reg [19:0] tlb_vpn   [0:ENTRIES-1];
    reg [19:0] tlb_pfn   [0:ENTRIES-1];
    reg [7:0]  tlb_flags [0:ENTRIES-1];
    reg        tlb_valid [0:ENTRIES-1];

    // FIFO replacement pointer
    reg [$clog2(ENTRIES)-1:0] next_victim;

    // ------------------------------------------------------------------
    // Lookup — combinacional (all-entries parallel comparação)
    // ------------------------------------------------------------------
    reg  [ENTRIES-1:0] match;
    wire hit_idx_oh;
    integer k;

    always @(*) begin
        for (k = 0; k < ENTRIES; k = k + 1)
            match[k] = tlb_valid[k] && (tlb_vpn[k] == virt_vpn);
    end

    // Priority encoder para índice do hit
    reg [$clog2(ENTRIES)-1:0] hit_idx;
    always @(*) begin
        hit_idx = 0;
        for (k = ENTRIES-1; k >= 0; k = k - 1)
            if (match[k]) hit_idx = k[$clog2(ENTRIES)-1:0];
    end

    assign hit       = lookup_req && |match;
    assign phys_pfn  = tlb_pfn[hit_idx];

    // Verificação de proteção
    wire entry_v = tlb_flags[hit_idx][V_BIT];
    wire entry_r = tlb_flags[hit_idx][R_BIT];
    wire entry_w = tlb_flags[hit_idx][W_BIT];
    wire entry_x = tlb_flags[hit_idx][X_BIT];
    wire entry_u = tlb_flags[hit_idx][U_BIT];

    assign prot_fault = hit && (
        (access_exec  && !entry_x)                ||  // execute sem X
        (access_write && !entry_w)                ||  // escrita sem W
        (!access_write && !access_exec && !entry_r)|| // leitura sem R
        (user_mode && !entry_u)                   ||  // user vs kernel page
        (!user_mode && entry_u && access_exec)        // supervisor exec no user page
    );

    // ------------------------------------------------------------------
    // Fill e Flush
    // ------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst || flush) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                tlb_valid[i] <= 1'b0;
            next_victim <= 0;
        end else if (fill_valid) begin
            tlb_vpn   [next_victim] <= fill_vpn;
            tlb_pfn   [next_victim] <= fill_pfn;
            tlb_flags [next_victim] <= fill_flags;
            tlb_valid [next_victim] <= 1'b1;
            next_victim <= next_victim + 1;
        end
    end

endmodule
