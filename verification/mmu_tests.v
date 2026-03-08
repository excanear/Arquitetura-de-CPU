// ============================================================================
// mmu_tests.v  —  Testes da MMU EduRISC-32v2
//
// Testa as unidades de MMU separadamente:
//   1. TLB hit (endereço previamente mapeado)
//   2. TLB miss → page table walk → hit
//   3. Proteção: acesso de escrita a página read-only → fault
//   4. Proteção: user acessa página kernel → fault
//   5. Flush do TLB (tlb_flush → todas as entradas invalidadas)
//   6. Mapeamento de identidade (vm_enable=0)
// ============================================================================
`timescale 1ns/1ps

module mmu_tests;

    reg        clk;
    reg        rst;

    initial clk = 0;
    always  #5 clk = ~clk;

    integer tests_run;
    integer tests_passed;
    integer tests_failed;

    task check;
        input [255:0] name;
        input [31:0] got, expected;
        begin
            tests_run = tests_run + 1;
            if (got === expected) begin
                $display("[PASS] %s", name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s: got=0x%08X expected=0x%08X", name, got, expected);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // MMU DUT
    // -----------------------------------------------------------------------
    reg  [31:0] vaddr;
    reg         req;
    reg         is_write;
    reg         is_exec;
    reg         user_mode;
    reg         vm_enable;
    reg         tlb_flush;

    // Interface page table walker → memória física simulada
    wire [25:0] ptw_paddr;
    wire        ptw_req;
    reg  [31:0] ptw_data;
    reg         ptw_valid;

    wire [31:0] paddr_out;
    wire        mmu_done;
    wire        page_fault;

    mmu u_mmu (
        .clk        (clk),
        .rst        (rst),
        .vaddr      (vaddr),
        .req        (req),
        .is_write   (is_write),
        .is_exec    (is_exec),
        .user_mode  (user_mode),
        .vm_enable  (vm_enable),
        .tlb_flush  (tlb_flush),
        .ptw_data   (ptw_data),
        .ptw_valid  (ptw_valid),
        .ptw_addr   (ptw_paddr),
        .ptw_req    (ptw_req),
        .paddr      (paddr_out),
        .done       (mmu_done),
        .fault      (page_fault)
    );

    // -----------------------------------------------------------------------
    // Memória de tabela de páginas simulada (4 páginas mapeadas)
    // Página 0x00000 → frame 0x001 (R/W/V)
    // Página 0x00001 → frame 0x002 (R/X/V, read-only exec)
    // Página 0x00002 → frame 0x003 (R/W/X/V/U — user)
    // PTBR em 0x00010
    // -----------------------------------------------------------------------
    localparam PTBR = 32'h00000040;   // addr der L1 page table (word addr 0x40)

    // Memória de PTE simulada
    reg [31:0] pte_mem [0:255];

    initial begin
        // Zerar tudo
        integer i;
        for (i = 0; i < 256; i = i + 1) pte_mem[i] = 0;

        // L1 PTE [0] → L2 table em frame 0x050
        pte_mem[8'h40] = {20'h00050, 12'b000000000001};  // V=1

        // L2 PTE [0] → página 0x001 (R/W)
        pte_mem[8'h50] = {20'h00001, 12'b000000000111};  // V=1,R=1,W=1

        // L2 PTE [1] → página 0x002 (R/X, sem W)
        pte_mem[8'h51] = {20'h00002, 12'b000000001011};  // V=1,R=1,X=1

        // L2 PTE [2] → página 0x003 (R/W/X/U)
        pte_mem[8'h52] = {20'h00003, 12'b000000011111};  // V=1,R=1,W=1,X=1,U=1
    end

    // Responder ao PTW
    always @(posedge clk) begin
        if (ptw_req) begin
            ptw_data  <= pte_mem[ptw_paddr[7:0]];
            ptw_valid <= 1;
        end else begin
            ptw_valid <= 0;
        end
    end

    // -----------------------------------------------------------------------
    // Helper: realizar uma tradução e esperar conclusão
    // -----------------------------------------------------------------------
    task do_translate;
        input [31:0] va;
        input        wr, ex, usr;
        output [31:0] pa;
        output        fault_out;
        integer timeout;
        begin
            vaddr    = va;
            is_write = wr;
            is_exec  = ex;
            user_mode= usr;
            req      = 1;
            timeout  = 0;
            @(posedge clk);
            while (!mmu_done && timeout < 20) begin
                @(posedge clk); timeout = timeout + 1;
            end
            pa        = paddr_out;
            fault_out = page_fault;
            req       = 0;
            @(posedge clk);
        end
    endtask

    reg [31:0] pa;
    reg        fault_out;

    // -----------------------------------------------------------------------
    // TESTE 1: Mapeamento de identidade (vm_enable=0)
    // -----------------------------------------------------------------------
    task test_identity_map;
        begin
            $display("-- Identity Mapping --");
            vm_enable = 0; tlb_flush = 0;
            do_translate(32'hABCD_1234, 0, 0, 0, pa, fault_out);
            check("Identity PA=VA", pa[31:0], 32'hABCD_1234);
            check("Identity no fault", {31'b0, fault_out}, 32'd0);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 2: TLB miss → walk → tradução correta
    // -----------------------------------------------------------------------
    task test_tlb_miss_walk;
        begin
            $display("-- TLB Miss → Walk --");
            vm_enable = 1;
            // VA page 0: VPN[21:12]=0 → L2[0] → PFN 0x001
            do_translate(32'h00000ABC, 0, 0, 0, pa, fault_out);
            // PFN=0x001, offset=0xABC → PA = 0x001ABC
            check("Walk PA", pa[19:0], 20'h1ABC);
            check("Walk no fault", {31'b0, fault_out}, 32'd0);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 3: TLB hit (mesmo endereço de novo)
    // -----------------------------------------------------------------------
    task test_tlb_hit;
        begin
            $display("-- TLB Hit --");
            // Mesma VA → deve usar TLB (sem novo walk)
            do_translate(32'h00000DEF, 0, 0, 0, pa, fault_out);
            check("TLB hit PA", pa[19:0], 20'h1DEF);
            check("TLB hit no fault", {31'b0, fault_out}, 32'd0);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 4: Escrita em página read-only → fault
    // -----------------------------------------------------------------------
    task test_write_readonly;
        begin
            $display("-- Write to Readonly --");
            // VA page 1: L2[1] → PFN 0x002, sem W
            do_translate(32'h00001000, 1, 0, 0, pa, fault_out);
            check("Write RO → fault", {31'b0, fault_out}, 32'd1);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 5: User acessando página kernel → fault
    // -----------------------------------------------------------------------
    task test_user_kernel;
        begin
            $display("-- User Access to Kernel Page --");
            // Páginas 0 e 1 não têm U bit → user_mode=1 deve dar fault
            do_translate(32'h00000100, 0, 0, 1, pa, fault_out);
            check("User→Kernel fault", {31'b0, fault_out}, 32'd1);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 6: Flush do TLB
    // -----------------------------------------------------------------------
    task test_flush;
        begin
            $display("-- TLB Flush --");
            tlb_flush = 1; @(posedge clk); tlb_flush = 0; @(posedge clk);
            // Após flush: mesma VA deveria causar miss novamente
            // (verificamos indiretamente que o ciclo completa sem erro)
            do_translate(32'h00000000, 0, 0, 0, pa, fault_out);
            check("Post-flush walk OK", {31'b0, fault_out}, 32'd0);
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("mmu_tests.vcd");
        $dumpvars(0, mmu_tests);

        tests_run = 0; tests_passed = 0; tests_failed = 0;
        rst = 1; req = 0; vm_enable = 0; tlb_flush = 0;
        is_write = 0; is_exec = 0; user_mode = 0;
        ptw_valid = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Configurar PTBR no MMU
        // (na prática via MTC CSR[5]=PTBR; aqui forçamos via u_mmu)
        force u_mmu.u_ptw.ptbr = PTBR[25:0];
        @(posedge clk);

        $display("=== MMU Tests ===");
        test_identity_map;
        test_tlb_miss_walk;
        test_tlb_hit;
        test_write_readonly;
        test_user_kernel;
        test_flush;

        $display("=== %0d/%0d PASS ===", tests_passed, tests_run);
        if (tests_failed == 0) $display("[TB] PASS"); else $display("[TB] FAIL");
        $finish;
    end

endmodule
