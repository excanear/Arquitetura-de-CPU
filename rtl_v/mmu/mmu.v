// ============================================================================
// mmu.v  —  Memory Management Unit (MMU) Top-Level
//
// Integra TLB + Page Table Walker.
// Recebe endereço virtual do pipeline e entrega endereço físico.
//
// Quando o modo de endereçamento virtual está desabilitado (STATUS.KU=0
// e PTBR=0), passa o endereço diretamente (identity mapping).
//
// Latência de tradução:
//   TLB hit:  0 ciclos (combinacional)
//   TLB miss: 2 ciclos (PTW) + 1 para fill do TLB
//
// Exceções geradas:
//   IFETCH_PAGE_FAULT (5): busca de instrução em página inválida/sem X
//   LOAD_PAGE_FAULT   (6): leitura em página inválida/sem R
//   STORE_PAGE_FAULT  (7): escrita em página inválida/sem W
// ============================================================================
`timescale 1ns/1ps
`include "../isa_pkg.vh"

module mmu (
    input  wire        clk,
    input  wire        rst,

    // Controle de habilitação
    input  wire        vm_enable,    // 1=modo virtual ativo (PTBR != 0)
    input  wire        user_mode,    // 0=kernel 1=user
    input  wire [31:0] ptbr,         // CSR PTBR

    // Interface para busca de instrução (IF)
    input  wire [31:0] if_vaddr,
    input  wire        if_req,
    output wire [31:0] if_paddr,
    output wire        if_ready,
    output wire        if_page_fault,

    // Interface para acesso a dados (MEM)
    input  wire [31:0] mem_vaddr,
    input  wire        mem_req,
    input  wire        mem_wr,
    output wire [31:0] mem_paddr,
    output wire        mem_ready,
    output wire        mem_page_fault,
    output wire [4:0]  mem_fault_cause,  // LOAD_PF ou STORE_PF

    // Interface com memória física (para PTW)
    output wire [25:0] ptw_mem_addr,
    output wire        ptw_mem_req,
    input  wire [31:0] ptw_mem_data,
    input  wire        ptw_mem_valid,

    // Flush do TLB (FENCE instruction)
    input  wire        tlb_flush
);

    // ------------------------------------------------------------------
    // TLB — compartilhado entre IF e MEM (um acesso por vez; prioridade MEM)
    // ------------------------------------------------------------------
    wire [19:0] tlb_if_pfn,   tlb_mem_pfn;
    wire        tlb_if_hit,   tlb_mem_hit;
    wire        tlb_if_fault, tlb_mem_fault;

    wire [19:0] active_vpn   = mem_req ? mem_vaddr[31:12] : if_vaddr[31:12];
    wire        active_req   = mem_req | if_req;
    wire        active_wr    = mem_req & mem_wr;
    wire        active_exec  = if_req & !mem_req;

    wire [19:0] tlb_pfn_out;
    wire        tlb_hit_out, tlb_prot_fault_out;

    tlb #(.ENTRIES(32)) u_tlb (
        .clk          (clk),
        .rst          (rst),
        .virt_vpn     (active_vpn),
        .lookup_req   (active_req && vm_enable),
        .phys_pfn     (tlb_pfn_out),
        .hit          (tlb_hit_out),
        .prot_fault   (tlb_prot_fault_out),
        .access_write (active_wr),
        .access_exec  (active_exec),
        .user_mode    (user_mode),
        .fill_valid   (ptw_fill_valid),
        .fill_vpn     (ptw_fill_vpn),
        .fill_pfn     (ptw_fill_pfn),
        .fill_flags   (ptw_fill_flags),
        .flush        (tlb_flush)
    );

    // ------------------------------------------------------------------
    // Page Table Walker
    // ------------------------------------------------------------------
    wire        ptw_done, ptw_fault;
    wire [19:0] ptw_pfn;
    wire [7:0]  ptw_flags;
    wire        ptw_fill_valid;
    wire [19:0] ptw_fill_vpn, ptw_fill_pfn;
    wire [7:0]  ptw_fill_flags;

    reg         ptw_req_r;
    reg  [31:0] ptw_vaddr_r;

    page_table_walker u_ptw (
        .clk       (clk),
        .rst       (rst),
        .virt_addr (ptw_vaddr_r),
        .req       (ptw_req_r),
        .ptbr      (ptbr),
        .phys_pfn  (ptw_pfn),
        .pte_flags (ptw_flags),
        .done      (ptw_done),
        .fault     (ptw_fault),
        .mem_addr  (ptw_mem_addr),
        .mem_req   (ptw_mem_req),
        .mem_data  (ptw_mem_data),
        .mem_valid (ptw_mem_valid)
    );

    assign ptw_fill_valid = ptw_done;
    assign ptw_fill_vpn   = ptw_vaddr_r[31:12];
    assign ptw_fill_pfn   = ptw_pfn;
    assign ptw_fill_flags = ptw_flags;

    // ------------------------------------------------------------------
    // Lógica de request para PTW quando TLB miss
    // ------------------------------------------------------------------
    reg     ptw_pending;
    always @(posedge clk) begin
        if (rst) begin
            ptw_req_r   <= 1'b0;
            ptw_pending <= 1'b0;
        end else begin
            ptw_req_r <= 1'b0;
            if (active_req && vm_enable && !tlb_hit_out && !ptw_pending) begin
                ptw_vaddr_r <= mem_req ? mem_vaddr : if_vaddr;
                ptw_req_r   <= 1'b1;
                ptw_pending <= 1'b1;
            end
            if (ptw_done || ptw_fault) ptw_pending <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Montagem do endereço físico
    // ------------------------------------------------------------------
    wire [31:0] if_phys_calc  = vm_enable ? {tlb_pfn_out, if_vaddr[11:0]}  : if_vaddr;
    wire [31:0] mem_phys_calc = vm_enable ? {tlb_pfn_out, mem_vaddr[11:0]} : mem_vaddr;

    assign if_paddr   = if_phys_calc;
    assign mem_paddr  = mem_phys_calc;

    assign if_ready   = !vm_enable || tlb_hit_out;
    assign mem_ready  = !vm_enable || (tlb_hit_out && mem_req);

    assign if_page_fault  = vm_enable && if_req  && (ptw_fault || tlb_prot_fault_out);
    assign mem_page_fault = vm_enable && mem_req && (ptw_fault || tlb_prot_fault_out);
    assign mem_fault_cause= mem_wr ? `EXC_STORE_PF : `EXC_LOAD_PF;

endmodule
