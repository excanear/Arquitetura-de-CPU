// ============================================================================
// pipeline_tests.v  —  Testes de Hazards e Pipeline EduRISC-32v2
//
// Foco: verificar comportamento correto do pipeline em situações críticas:
//   - Forwarding EX/MEM → EX (3 casos)
//   - Forwarding MEM/WB → EX
//   - Load-use stall (1 ciclo)
//   - MUL/DIV stall (latência variável)
//   - Branch flush (pipeline flushed na bolha)
//   - Instrução NOP (sem efeitos colaterais)
//   - PUSH/POP (SP decrementado/incrementado corretamente)
// ============================================================================
`timescale 1ns/1ps
`include "../rtl_v/isa_pkg.vh"

module pipeline_tests;

    reg        clk;
    reg        rst;
    wire       uart_tx;

    cpu_top dut (
        .clk      (clk),
        .rst      (rst),
        .uart_tx  (uart_tx),
        .uart_rx  (1'b1),
        .debug_out(),
        .halted   ()
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    integer tests_run;
    integer tests_passed;
    integer tests_failed;

    task do_reset;
        begin rst = 1; repeat(4) @(posedge clk); rst = 0; end
    endtask

    task run_until_halt;
        input integer max_cycles;
        integer n;
        begin
            n = 0;
            while (!dut.halted && n < max_cycles) begin
                @(posedge clk); n = n + 1;
            end
        end
    endtask

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

    function [31:0] reg_rd;
        input [4:0] n;
        reg_rd = dut.u_regfile.regs[n];
    endfunction

    // ------------------------------------------------------------------
    // TEST: Forwarding EX/MEM→EX (cadeia de 4 instruções)
    // ------------------------------------------------------------------
    reg [31:0] p [0:31];
    task test_forward_chain;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) p[i] = {`OP_NOP, 26'b0};
            p[0] = {`OP_MOVI, 5'd1, 16'd1};
            p[1] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};  // R1=2
            p[2] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};  // R1=3
            p[3] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};  // R1=4
            p[4] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};  // R1=5
            p[5] = {`OP_HLT, 26'b0};
            for (i = 0; i < 32; i = i + 1) dut.u_imem.mem[i] = p[i];
            do_reset; run_until_halt(200);
            check("Forward chain R1=5", reg_rd(1), 32'd5);
        end
    endtask

    // ------------------------------------------------------------------
    // TEST: Load-use stall — hardware deve inserir 1 bolha
    // ------------------------------------------------------------------
    task test_load_use_stall;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) p[i] = {`OP_NOP, 26'b0};
            p[0] = {`OP_MOVI,  5'd14, 16'd50};
            p[1] = {`OP_MOVI,  5'd1,  16'd255};
            p[2] = {`OP_SW,    5'd1,  5'd14, 16'd0};
            p[3] = {`OP_LW,    5'd2,  5'd14, 16'd0};   // load
            p[4] = {`OP_ADD,   5'd3,  5'd2,  5'd2, 11'b0}; // dep imediata
            p[5] = {`OP_HLT,   26'b0};
            for (i = 0; i < 32; i = i + 1) dut.u_imem.mem[i] = p[i];
            do_reset; run_until_halt(300);
            check("Load-use R3=510", reg_rd(3), 32'd510);
        end
    endtask

    // ------------------------------------------------------------------
    // TEST: Forwarding MEM/WB→EX (dois ciclos de distância)
    // ------------------------------------------------------------------
    task test_memwb_forward;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) p[i] = {`OP_NOP, 26'b0};
            p[0] = {`OP_MOVI, 5'd1, 16'd100};
            p[1] = {`OP_MOVI, 5'd2, 16'd0};     // independente
            p[2] = {`OP_ADD,  5'd3, 5'd1, 5'd2, 11'b0}; // R3 = 100+0 (MEM/WB→EX)
            p[3] = {`OP_HLT, 26'b0};
            for (i = 0; i < 32; i = i + 1) dut.u_imem.mem[i] = p[i];
            do_reset; run_until_halt(200);
            check("MEM/WB forward R3=100", reg_rd(3), 32'd100);
        end
    endtask

    // ------------------------------------------------------------------
    // TEST: Branch taken — flush de 2 instruções após o branch
    // ------------------------------------------------------------------
    task test_branch_flush;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) p[i] = {`OP_NOP, 26'b0};
            p[0] = {`OP_MOVI, 5'd1, 16'd5};
            p[1] = {`OP_MOVI, 5'd2, 16'd5};
            p[2] = {`OP_BEQ,  5'd1, 5'd2, 16'd3};  // saltar para 2+1+3=6
            p[3] = {`OP_MOVI, 5'd5, 16'd11};  // não executar (flush)
            p[4] = {`OP_MOVI, 5'd5, 16'd22};  // não executar (flush)
            p[5] = {`OP_NOP,  26'b0};          // slot
            p[6] = {`OP_MOVI, 5'd4, 16'd77};  // destino
            p[7] = {`OP_HLT,  26'b0};
            for (i = 0; i < 32; i = i + 1) dut.u_imem.mem[i] = p[i];
            do_reset; run_until_halt(300);
            check("BEQ flush R5=0",  reg_rd(5), 32'd0);
            check("BEQ flush R4=77", reg_rd(4), 32'd77);
        end
    endtask

    // ------------------------------------------------------------------
    // TEST: PUSH / POP
    // ------------------------------------------------------------------
    task test_push_pop;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) p[i] = {`OP_NOP, 26'b0};
            p[0] = {`OP_MOVI, 5'd30, 16'd400};  // SP=400
            p[1] = {`OP_MOVI, 5'd1,  16'd0xAA};
            p[2] = {`OP_MOVI, 5'd2,  16'd0xBB};
            p[3] = {`OP_PUSH, 5'd1,  21'b0};    // push R1; SP-=1
            p[4] = {`OP_PUSH, 5'd2,  21'b0};    // push R2; SP-=1
            p[5] = {`OP_POP,  5'd3,  21'b0};    // pop  R3=R2; SP+=1
            p[6] = {`OP_POP,  5'd4,  21'b0};    // pop  R4=R1; SP+=1
            p[7] = {`OP_HLT,  26'b0};
            for (i = 0; i < 32; i = i + 1) dut.u_imem.mem[i] = p[i];
            do_reset; run_until_halt(300);
            check("POP R3=0xBB", reg_rd(3), 32'hBB);
            check("POP R4=0xAA", reg_rd(4), 32'hAA);
            check("SP restaurado", reg_rd(30), 32'd400);
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        $dumpfile("pipeline_tests.vcd");
        $dumpvars(0, pipeline_tests);

        tests_run = 0; tests_passed = 0; tests_failed = 0;
        rst = 1; @(posedge clk);

        $display("=== Pipeline Tests ===");
        test_forward_chain;
        test_load_use_stall;
        test_memwb_forward;
        test_branch_flush;
        test_push_pop;

        $display("=== %0d/%0d PASS ===", tests_passed, tests_run);
        if (tests_failed == 0) $display("[TB] PASS"); else $display("[TB] FAIL");
        $finish;
    end

endmodule
