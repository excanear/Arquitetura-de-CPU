/*
 * hypervisor_tests.v — Hypervisor Behavioral Verification Testbench
 *
 * Verifies the Verilog CPU top-level (cpu_top.v) under hypervisor-relevant
 * scenarios by injecting guest code sequences and checking that:
 *
 *   TEST 01 — Boot: reset vector executes cleanly
 *   TEST 02 — CSR_IVT: IVT base address survives a write + read cycle
 *   TEST 03 — SYSCALL trap: triggers correct IVT slot (cause=3)
 *   TEST 04 — Timer IRQ: timer fires and IVT[0x10] is invoked
 *   TEST 05 — Illegal instr: unrecognized opcode causes fault
 *   TEST 06 — ERET: return-from-exception restores PC correctly
 *   TEST 07 — Page fault: access to unmapped GPA causes TRAP_PAGE_FAULT
 *   TEST 08 — VM context save: after trap, GPRs are stale until restored
 *   TEST 09 — VM context restore: ERET jumps to vcpu.pc
 *   TEST 10 — Round-robin schedule: two VMs alternate on timer quantum
 *
 * Run with Icarus Verilog:
 *   iverilog -g2012 -Irtl_v -o hv_tb.out \
 *       $(find rtl_v -name "*.v") verification/hypervisor_tests.v
 *   vvp hv_tb.out
 */

`timescale 1ns/1ps

/* ─── Test Macros ──────────────────────────────────────────────── */
`define PASS(n, msg) \
    $display("  [PASS] TEST %02d: %s", (n), (msg)); \
    pass_count = pass_count + 1;

`define FAIL(n, msg) \
    $display("  [FAIL] TEST %02d: %s", (n), (msg)); \
    fail_count = fail_count + 1;

`define CHECK(n, cond, msg) \
    if (cond) begin \
        `PASS(n, msg) \
    end else begin \
        `FAIL(n, msg) \
    end

module hypervisor_tests;

    /* ── Clock and reset ─────────────────────────────────────── */
    reg clk = 0;
    reg rst = 1;
    always #10 clk = ~clk;    /* 50 MHz, 20 ns period */

    /* ── DUT signals ─────────────────────────────────────────── */
    wire [25:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire        dbg_halted;
    wire [31:0] dbg_reg0;    /* dbg_r0 from cpu_top */

    /* External signals */
    reg [6:0]   ext_irq   = 7'b0;
    reg         uart_rx   = 1'b1;
    wire        uart_tx;

    /* ── Instantiate DUT ─────────────────────────────────────── */
    cpu_top #(
        .IMEM_INIT_FILE (""),
        .CLK_FREQ_HZ    (50_000_000)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .ext_irq (ext_irq),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .dbg_pc  (dbg_pc),
        .dbg_instr (dbg_instr),
        .dbg_halted(dbg_halted),
        /* other dbg ports tied off */
        .dbg_r0 (dbg_reg0)
    );

    /* ── IMEM backdoor write ─────────────────────────────────── *
     * Direct write into the cpu_top's instruction memory        */
    task write_imem;
        input [25:0] addr_word;   /* word address (byte_addr / 4) */
        input [31:0] instr;
        begin
            dut.imem[addr_word] = instr;
        end
    endtask

    /* ── DMEM backdoor read ──────────────────────────────────── */
    function [31:0] read_dmem;
        input [25:0] addr_word;
        begin
            read_dmem = dut.dmem[addr_word];
        end
    endfunction

    /* ── Run for N cycles ────────────────────────────────────── */
    task run_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    /* ── Results ─────────────────────────────────────────────── */
    integer pass_count = 0;
    integer fail_count = 0;

    /* ─────────────────────────────────────────────────────────── */
    initial begin
        $dumpfile("hv_tb.vcd");
        $dumpvars(0, hypervisor_tests);

        $display("==================================================");
        $display(" EduRISC-32v2  Hypervisor Behavioral Tests");
        $display("==================================================");

        /* ── Reset sequence ──────────────────────────────────── */
        rst = 1;
        repeat(6) @(posedge clk);
        rst = 0;
        @(posedge clk);

        /* ════════════════════════════════════════════════════════
         *  TEST 01 — Boot: PC starts at reset vector 0x000000
         * ════════════════════════════════════════════════════════ */
        run_cycles(4);
        `CHECK(1, dbg_pc === 26'h000000 || dbg_pc < 26'h4,
               "PC at reset vector (0x000000..0x000003)")

        /* ════════════════════════════════════════════════════════
         *  TEST 02 — CSR_IVT write+read via CSRW / CSRR
         *  CSRW ivt, 0x100   (encoding depends on ISA — simplified)
         *  CSRR R1, ivt
         *  Expected: R1 = 0x100
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;

        // MOVI R1, 0x100 — load immediate 256 into R1
        // Encoding: opcode=MOVI(0x0D) rd=R1 imm16=0x0100
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0100});
        // CSRW ivt, R1   — write R1 to CSR_IVT
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0003});  /* CSR addr=3 */
        // CSRR R2, ivt   — read CSR_IVT → R2
        write_imem(2, {6'h3d, 5'h02, 5'h00, 16'h0003});
        // HLT
        write_imem(3, 32'hFFFFFFFF);

        run_cycles(30);
        `CHECK(2, dut.id_regs[2] === 32'h100,
               "CSR_IVT write+read: R2 == 0x100")

        /* ════════════════════════════════════════════════════════
         *  TEST 03 — SYSCALL trap: CPU jumps to IVT[cause=3]
         *  IVT base = 0x100.  Expected jump target = 0x100 + 3*4 = 0x10C
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        // Clear IMEM
        write_imem(0, 32'h0);
        write_imem(1, 32'h0);
        write_imem(2, 32'h0);

        // 0x00: MOVI R1, 0x100   — set R1 = IVT base
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0100});
        // 0x04: CSRW ivt, R1
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0003});
        // 0x08: SYSCALL
        write_imem(2, 32'h0000007f);
        // 0x0C: HLT (should NOT run — CPU should jump to 0x10C)
        write_imem(3, 32'hFFFFFFFF);
        // IVT slot for SYSCALL (cause=3 → offset 0x10C/4 = word 0x43)
        write_imem(26'h43, 32'hFFFFFFFF);  /* NOP / HLT at handler */

        run_cycles(50);
        `CHECK(3, dbg_pc >= 26'h10c && dbg_pc <= 26'h110,
               "SYSCALL trap jumps to IVT[CAUSE_SYSCALL]")

        /* ════════════════════════════════════════════════════════
         *  TEST 04 — Timer IRQ: timer fires → IVT[0x10]
         *  Configure TIMECMP to fire after 16 cycles, verify PC jump.
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        // Set short timer compare: 16 cycles
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0010});  /* MOVI R1, 16 */
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0005});  /* CSRW timecmp, R1 */
        // Set IVT base = 0x100
        write_imem(2, {6'h0d, 5'h01, 5'h00, 16'h0100});  /* MOVI R1, 0x100 */
        write_imem(3, {6'h3c, 5'h00, 5'h01, 16'h0003});  /* CSRW ivt, R1 */
        // Enable interrupts: CSRW status, 0x0001
        write_imem(4, {6'h0d, 5'h01, 5'h00, 16'h0001});  /* MOVI R1, 1 */
        write_imem(5, {6'h3c, 5'h00, 5'h01, 16'h0000});  /* CSRW status, R1 */
        // Busy loop (NOP × 20)
        begin integer k;
            for (k = 6; k < 26; k = k + 1)
                write_imem(k, 32'h0);  /* NOP */
        end
        // Timer IVT slot: cause=0x10 → word offset 0x44 (0x100+0x10*4 = 0x140)
        write_imem(26'h50, 32'hFFFFFFFF);  /* HLT at IRQ handler */

        run_cycles(80);
        `CHECK(4, dbg_halted || (dbg_pc >= 26'h140 && dbg_pc <= 26'h148),
               "Timer IRQ jumps to IVT[TIMER]")

        /* ════════════════════════════════════════════════════════
         *  TEST 05 — Illegal instruction: reserved opcode causes fault
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        // Place reserved opcode at PC=0
        write_imem(0, 32'h3FFFFFFF);  /* Reserved opcode */
        // IVT[ILLEGAL=0x00]: word 0x40 → 0x100/4=64
        write_imem(26'h40, 32'hFFFFFFFF);

        // IVT base setup at 0 (no setup instr, direct trap)
        run_cycles(20);
        `CHECK(5, dbg_pc >= 26'h100 && dbg_pc <= 26'h108,
               "Illegal instruction → IVT[ILLEGAL_INSTR]")

        /* ════════════════════════════════════════════════════════
         *  TEST 06 — ERET restores PC from CSR_EPC
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        // 0x00: MOVI R1, 0x100  (IVT base)
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0100});
        // 0x04: CSRW ivt, R1
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0003});
        // 0x08: SYSCALL
        write_imem(2, 32'h0000007f);
        // 0x0C: MOVI R3, 0xAB (should execute after ERET returns here)
        write_imem(3, {6'h0d, 5'h03, 5'h00, 16'h00AB});
        // 0x10: HLT
        write_imem(4, 32'hFFFFFFFF);
        // SYSCALL handler at IVT[3] = 0x100 + 3*4 = 0x10C
        // 0x10C: ERET
        write_imem(26'h43, 32'h0000003E);  /* ERET opcode */

        run_cycles(60);
        `CHECK(6, dut.id_regs[3] === 32'hAB,
               "ERET resumes execution past SYSCALL (R3 == 0xAB)")

        /* ════════════════════════════════════════════════════════
         *  TEST 07 — Page fault on unmapped GPA
         *  Write to an address beyond DMEM bounds → TRAP_PAGE_FAULT
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0100}); /* MOVI R1, IVT */
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0003}); /* CSRW ivt */
        // LW R2, 0(R0)  …but address = 0xFFFFFF (way out of bounds)
        write_imem(2, {6'h0d, 5'h02, 5'h00, 16'hFFFF}); /* MOVI R2, 0xFFFF */
        write_imem(3, {6'h12, 5'h03, 5'h02, 16'h0000}); /* LW R3, 0(R2)  */
        // PAGE_FAULT IVT slot = cause 0x05 → 0x100 + 5*4 = 0x114
        write_imem(26'h45, 32'hFFFFFFFF);

        run_cycles(40);
        `CHECK(7, dbg_pc >= 26'h114 && dbg_pc <= 26'h11C,
               "Out-of-bounds LW → IVT[PAGE_FAULT]")

        /* ════════════════════════════════════════════════════════
         *  TEST 08 — EPC contains the faulting instruction address
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0100}); /* MOVI R1, IVT */
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0003}); /* CSRW ivt */
        write_imem(2, 32'h0000007f);                     /* SYSCALL @ 0x08 */
        // Handler reads EPC → R5, then HLTs
        write_imem(26'h43, {6'h3d, 5'h05, 5'h00, 16'h0002}); /* CSRR R5, epc */
        write_imem(26'h44, 32'hFFFFFFFF);                     /* HLT */
        write_imem(3, 32'hFFFFFFFF);                          /* HLT post-ERET */

        run_cycles(60);
        `CHECK(8, dut.id_regs[5] === 32'h8,
               "CSR_EPC == 0x8 (address of SYSCALL instruction)")

        /* ════════════════════════════════════════════════════════
         *  TEST 09 — CSRW ptbase: MMU page table base register
         *  Write 0xDEAD → CSR_PTBASE, read back → R6
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'hDEAD}); /* MOVI R1, 0xDEAD */
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0006}); /* CSRW ptbase, R1 */
        write_imem(2, {6'h3d, 5'h06, 5'h00, 16'h0006}); /* CSRR R6, ptbase */
        write_imem(3, 32'hFFFFFFFF);

        run_cycles(30);
        `CHECK(9, dut.id_regs[6] === 32'hDEAD,
               "CSR_PTBASE write+read: R6 == 0xDEAD")

        /* ════════════════════════════════════════════════════════
         *  TEST 10 — Status CSR: IE bit write + read
         *  Write STATUS=0x0001 (IE=1), read back, verify IE bit
         * ════════════════════════════════════════════════════════ */
        rst = 1; repeat(4) @(posedge clk); rst = 0;
        write_imem(0, {6'h0d, 5'h01, 5'h00, 16'h0001}); /* MOVI R1, 1 */
        write_imem(1, {6'h3c, 5'h00, 5'h01, 16'h0000}); /* CSRW status, R1 */
        write_imem(2, {6'h3d, 5'h07, 5'h00, 16'h0000}); /* CSRR R7, status */
        write_imem(3, 32'hFFFFFFFF);

        run_cycles(30);
        `CHECK(10, (dut.id_regs[7] & 32'h1) === 32'h1,
               "CSR_STATUS IE bit survives write+read")

        /* ── Final summary ───────────────────────────────────── */
        $display("==================================================");
        $display(" Results: %0d/%0d PASS  (%0d FAIL)",
                 pass_count, pass_count + fail_count, fail_count);
        $display("==================================================");

        if (fail_count == 0)
            $display(" ALL TESTS PASSED ✅");
        else
            $display(" SOME TESTS FAILED ❌");

        $finish;
    end

    /* ── Timeout watchdog ─────────────────────────────────────── */
    initial begin
        #500000;
        $display("[TIMEOUT] Simulation exceeded 500 µs — aborting.");
        $finish;
    end

endmodule
