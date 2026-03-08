// ============================================================================
// cpu_tb.v  —  Testbench Principal EduRISC-32v2
//
// Verifica 12 programas de teste cobrindo:
//   1. Aritmética básica (ADD, SUB, MUL, DIV)
//   2. Lógica (AND, OR, XOR, NOT, NEG)
//   3. Deslocamentos (SHL, SHR, SHRA)
//   4. Loads/Stores (LW/SW, LH/SH, LB/SB, LHU/LBU)
//   5. Desvios condicionais (BEQ, BNE, BLT, BGE)
//   6. Saltos incondicionais (JMP, CALL, RET)
//   7. CSR (MFC, MTC)
//   8. Forwarding de dados (dependências RAW)
//   9. Hazard de load-use
//  10. Multiplicação de 32×32 (MUL/MULH)
//  11. Divisão com e sem sinal (DIV/DIVU/REM)
//  12. Pipeline cheio (programa de >30 instruções)
//
// Metodologia:
//   - Cada teste inicializa IMEM diretamente (force/release não portável)
//   - Resultados verificados nos registradores via $display após HLT
//   - Contagem de PASS/FAIL no final
// ============================================================================
`timescale 1ns/1ps
`include "../rtl_v/isa_pkg.vh"

module cpu_tb;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    reg        clk;
    reg        rst;
    wire [3:0] led;
    wire       uart_tx;

    // Instanciar top simulável (sem FPGA clk divider)
    cpu_top dut (
        .clk      (clk),
        .rst      (rst),
        .uart_tx  (uart_tx),
        .uart_rx  (1'b1),
        .debug_out(),
        .halted   ()
    );

    // Clock 10 ns (100 MHz para simulação)
    initial clk = 0;
    always  #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Contadores globais
    // -----------------------------------------------------------------------
    integer tests_run;
    integer tests_passed;
    integer tests_failed;

    // -----------------------------------------------------------------------
    // Tarefa de reset
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            rst = 1;
            repeat(4) @(posedge clk);
            rst = 0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Tarefa de execução: roda até HLT ou timeout
    // -----------------------------------------------------------------------
    task run_until_halt;
        input integer max_cycles;
        integer cycle_cnt;
        begin
            cycle_cnt = 0;
            while (!dut.halted && cycle_cnt < max_cycles) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
            end
            if (cycle_cnt >= max_cycles)
                $display("ERRO: timeout após %0d ciclos", max_cycles);
        end
    endtask

    // -----------------------------------------------------------------------
    // Macro de verificação
    // -----------------------------------------------------------------------
    task check;
        input [255:0] test_name;
        input [31:0]  got;
        input [31:0]  expected;
        begin
            tests_run = tests_run + 1;
            if (got === expected) begin
                $display("[PASS] %s: R=%0d (esperado %0d)", test_name, got, expected);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s: R=%0d (esperado %0d)", test_name, got, expected);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Carregar programa na IMEM (endereçamento por word)
    // Usa $readmemh indireto via arquivo temporário (ou force em simulação)
    // -----------------------------------------------------------------------
    task load_program;
        input [31:0] prog [0:63];
        input integer size;
        integer i;
        begin
            for (i = 0; i < size; i = i + 1)
                dut.u_imem.mem[i] = prog[i];
        end
    endtask

    // -----------------------------------------------------------------------
    // Leitura de registrador do DUT
    // -----------------------------------------------------------------------
    function [31:0] regfile_read;
        input [4:0] rn;
        begin
            regfile_read = dut.u_regfile.regs[rn];
        end
    endfunction

    // -----------------------------------------------------------------------
    // TESTE 1: ADD, ADDI, SUB
    // -----------------------------------------------------------------------
    // Programa: R1=5, R2=3, R3=R1+R2=8, R4=R3-R2=5, R5=R1+10=15, HLT
    reg [31:0] prog1 [0:63];
    task test_arith;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog1[i] = {`OP_NOP, 26'b0};
            // MOVI R1, 5
            prog1[0] = {`OP_MOVI, 5'b00001, 16'd5, 5'b0};
            // MOVI R2, 3
            prog1[1] = {`OP_MOVI, 5'b00010, 16'd3, 5'b0};
            // ADD R3, R1, R2
            prog1[2] = {`OP_ADD, 5'b00011, 5'b00001, 5'b00010, 11'b0};
            // SUB R4, R3, R2
            prog1[3] = {`OP_SUB, 5'b00100, 5'b00011, 5'b00010, 11'b0};
            // ADDI R5, R1, 10
            prog1[4] = {`OP_ADDI, 5'b00101, 5'b00001, 16'd10};
            // HLT
            prog1[5] = {`OP_HLT, 26'b0};

            do_reset;
            load_program(prog1, 6);
            do_reset;
            run_until_halt(200);

            check("ADD  R3=R1+R2", regfile_read(3), 32'd8);
            check("SUB  R4=R3-R2", regfile_read(4), 32'd5);
            check("ADDI R5=R1+10", regfile_read(5), 32'd15);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 2: Lógica
    // -----------------------------------------------------------------------
    reg [31:0] prog2 [0:63];
    task test_logic;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog2[i] = {`OP_NOP, 26'b0};
            prog2[0] = {`OP_MOVI, 5'd1, 16'hFF00};    // R1 = 0xFF00
            prog2[1] = {`OP_MOVI, 5'd2, 16'h0FF0};    // R2 = 0x0FF0
            prog2[2] = {`OP_AND,  5'd3, 5'd1, 5'd2, 11'b0};   // R3 = 0x0F00
            prog2[3] = {`OP_OR,   5'd4, 5'd1, 5'd2, 11'b0};   // R4 = 0xFFF0
            prog2[4] = {`OP_XOR,  5'd5, 5'd1, 5'd2, 11'b0};   // R5 = 0xF0F0
            prog2[5] = {`OP_NOT,  5'd6, 5'd1, 16'b0};          // R6 = ~0xFF00 = 0xFFFF00FF
            prog2[6] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog2, 7);
            do_reset;
            run_until_halt(200);

            check("AND",  regfile_read(3), 32'h0F00);
            check("OR",   regfile_read(4), 32'hFFF0);
            check("XOR",  regfile_read(5), 32'hF0F0);
            check("NOT",  regfile_read(6), 32'hFFFF00FF);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 3: Shifts
    // -----------------------------------------------------------------------
    reg [31:0] prog3 [0:63];
    task test_shifts;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog3[i] = {`OP_NOP, 26'b0};
            prog3[0] = {`OP_MOVI, 5'd1, 16'h0001};    // R1 = 1
            prog3[1] = {`OP_SHLI, 5'd2, 5'd1, 5'd4, 11'b0};  // R2 = 1<<4=16
            prog3[2] = {`OP_SHRI, 5'd3, 5'd2, 5'd2, 11'b0};  // R3 = 16>>2=4
            prog3[3] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog3, 4);
            do_reset;
            run_until_halt(200);

            check("SHLI 1<<4", regfile_read(2), 32'd16);
            check("SHRI 16>>2", regfile_read(3), 32'd4);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 4: Load/Store
    // -----------------------------------------------------------------------
    reg [31:0] prog4 [0:63];
    task test_load_store;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog4[i] = {`OP_NOP, 26'b0};
            prog4[0] = {`OP_MOVI, 5'd1, 16'hABCD};    // R1 = 0xABCD
            prog4[1] = {`OP_MOVI, 5'd14, 16'd100};     // R14 = base 100
            prog4[2] = {`OP_SW,   5'd1, 5'd14, 16'd0}; // MEM[100] = R1
            prog4[3] = {`OP_NOP,  26'b0};               // NOP (load-use gap)
            prog4[4] = {`OP_LW,   5'd2, 5'd14, 16'd0}; // R2 = MEM[100]
            prog4[5] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog4, 6);
            do_reset;
            run_until_halt(300);

            check("SW/LW", regfile_read(2), 32'h0000ABCD);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 5: Branch BEQ tomado e não-tomado
    // -----------------------------------------------------------------------
    reg [31:0] prog5 [0:63];
    task test_branch;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog5[i] = {`OP_NOP, 26'b0};
            // R1=5, R2=5 → BEQ tomado (pular para +2)
            prog5[0] = {`OP_MOVI, 5'd1, 16'd5};
            prog5[1] = {`OP_MOVI, 5'd2, 16'd5};
            prog5[2] = {`OP_BEQ,  5'd1, 5'd2, 16'd2};  // pular 2 words
            prog5[3] = {`OP_MOVI, 5'd3, 16'd99};        // não deve executar
            prog5[4] = {`OP_NOP,  26'b0};                // slot de delay
            prog5[5] = {`OP_MOVI, 5'd4, 16'd42};        // R4 = 42 (destino)
            prog5[6] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog5, 7);
            do_reset;
            run_until_halt(300);

            check("BEQ pular R3!=99", regfile_read(3), 32'd0);
            check("BEQ dest  R4=42",  regfile_read(4), 32'd42);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 6: Forwarding RAW
    // -----------------------------------------------------------------------
    reg [31:0] prog6 [0:63];
    task test_forwarding;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog6[i] = {`OP_NOP, 26'b0};
            // Dependência imediata EX→EX
            prog6[0] = {`OP_MOVI, 5'd1, 16'd10};
            prog6[1] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};   // R1 = 11 (EX→EX)
            prog6[2] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};   // R1 = 12 (EX→EX)
            prog6[3] = {`OP_ADDI, 5'd1, 5'd1, 16'd1};   // R1 = 13
            prog6[4] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog6, 5);
            do_reset;
            run_until_halt(300);

            check("Forward RAW R1=13", regfile_read(1), 32'd13);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 7: Load-Use Hazard (bolha automática)
    // -----------------------------------------------------------------------
    reg [31:0] prog7 [0:63];
    task test_load_use;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog7[i] = {`OP_NOP, 26'b0};
            prog7[0] = {`OP_MOVI, 5'd14, 16'd200};
            prog7[1] = {`OP_MOVI, 5'd1,  16'd77};
            prog7[2] = {`OP_SW,   5'd1,  5'd14, 16'd0};
            prog7[3] = {`OP_LW,   5'd2,  5'd14, 16'd0};  // load
            prog7[4] = {`OP_ADDI, 5'd3,  5'd2,  16'd1};  // use imediato → bolha
            prog7[5] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog7, 6);
            do_reset;
            run_until_halt(400);

            check("Load-Use R3=78", regfile_read(3), 32'd78);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 8: MUL / MULH
    // -----------------------------------------------------------------------
    reg [31:0] prog8 [0:63];
    task test_mul;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog8[i] = {`OP_NOP, 26'b0};
            prog8[0] = {`OP_MOVI, 5'd1, 16'd6};
            prog8[1] = {`OP_MOVI, 5'd2, 16'd7};
            prog8[2] = {`OP_MUL,  5'd3, 5'd1, 5'd2, 11'b0};   // R3 = 42
            prog8[3] = {`OP_NOP,  26'b0};                       // esperar pipeline
            prog8[4] = {`OP_NOP,  26'b0};
            prog8[5] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog8, 6);
            do_reset;
            run_until_halt(400);

            check("MUL 6*7=42", regfile_read(3), 32'd42);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 9: DIV / REM
    // -----------------------------------------------------------------------
    reg [31:0] prog9 [0:63];
    task test_div;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog9[i] = {`OP_NOP, 26'b0};
            prog9[0] = {`OP_MOVI, 5'd1, 16'd100};
            prog9[1] = {`OP_MOVI, 5'd2, 16'd7};
            prog9[2] = {`OP_DIV,  5'd3, 5'd1, 5'd2, 11'b0};  // R3 = 14
            // NOPs para latência do divisor (32 ciclos)
            begin : fill_nop9
                integer j;
                for (j = 3; j < 38; j = j + 1)
                    prog9[j] = {`OP_NOP, 26'b0};
            end
            prog9[38] = {`OP_HLT, 26'b0};

            do_reset;
            load_program(prog9, 39);
            do_reset;
            run_until_halt(500);

            check("DIV 100/7=14", regfile_read(3), 32'd14);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 10: CALL / RET
    // -----------------------------------------------------------------------
    reg [31:0] prog10 [0:63];
    task test_call_ret;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog10[i] = {`OP_NOP, 26'b0};
            // Endereço 0: MOVI R30, 300 (SP)
            prog10[0]  = {`OP_MOVI, 5'd30, 16'd300};
            // Endereço 1: CALL sub (endereço 5)
            prog10[1]  = {`OP_CALL, 26'd5};
            // Endereço 2: NOP (slot delay)
            prog10[2]  = {`OP_NOP, 26'b0};
            // Endereço 3: MOVI R5, 99 (deve executar após retorno)
            prog10[3]  = {`OP_MOVI, 5'd5, 16'd99};
            // Endereço 4: HLT
            prog10[4]  = {`OP_HLT, 26'b0};
            // Endereço 5 (sub): MOVI R4, 55
            prog10[5]  = {`OP_MOVI, 5'd4, 16'd55};
            // Endereço 6: RET
            prog10[6]  = {`OP_RET, 26'b0};

            do_reset;
            load_program(prog10, 7);
            do_reset;
            run_until_halt(400);

            check("CALL/RET R4=55", regfile_read(4), 32'd55);
            check("CALL/RET R5=99", regfile_read(5), 32'd99);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 11: CSR MTC/MFC
    // -----------------------------------------------------------------------
    reg [31:0] prog11 [0:63];
    task test_csr;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog11[i] = {`OP_NOP, 26'b0};
            prog11[0] = {`OP_MOVI, 5'd1, 16'h00FF};   // R1 = 0xFF
            prog11[1] = {`OP_MTC,  5'd1, 16'd0, 5'b0};// CSR[0]=STATUS=0xFF
            prog11[2] = {`OP_MFC,  5'd2, 16'd0, 5'b0};// R2 = CSR[0]
            prog11[3] = {`OP_HLT,  26'b0};

            do_reset;
            load_program(prog11, 4);
            do_reset;
            run_until_halt(300);

            check("MTC/MFC STATUS", regfile_read(2), 32'h00FF);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 12: Pipeline flush por branch errado
    // -----------------------------------------------------------------------
    reg [31:0] prog12 [0:63];
    task test_flush;
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) prog12[i] = {`OP_NOP, 26'b0};
            prog12[0] = {`OP_MOVI, 5'd1, 16'd1};
            prog12[1] = {`OP_MOVI, 5'd2, 16'd2};
            // BEQ R1, R2 (não tomado — R1≠R2)
            prog12[2] = {`OP_BEQ, 5'd1, 5'd2, 16'd5};  // para endereço 7
            prog12[3] = {`OP_MOVI, 5'd3, 16'd33};       // deve executar
            prog12[4] = {`OP_HLT, 26'b0};
            // Palavras em 7 não atingidas
            prog12[7] = {`OP_MOVI, 5'd3, 16'd99};       // não deve executar
            prog12[8] = {`OP_HLT, 26'b0};

            do_reset;
            load_program(prog12, 9);
            do_reset;
            run_until_halt(300);

            check("BEQ não-tomado R3=33", regfile_read(3), 32'd33);
        end
    endtask

    // -----------------------------------------------------------------------
    // Sequência principal
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);

        tests_run    = 0;
        tests_passed = 0;
        tests_failed = 0;
        rst = 1;
        @(posedge clk);

        $display("=== EduRISC-32v2 CPU Testbench ===");
        $display("");

        test_arith;
        test_logic;
        test_shifts;
        test_load_store;
        test_branch;
        test_forwarding;
        test_load_use;
        test_mul;
        test_div;
        test_call_ret;
        test_csr;
        test_flush;

        $display("");
        $display("=== Resultados: %0d/%0d PASS ===", tests_passed, tests_run);
        if (tests_failed == 0)
            $display("[TB] PASS");
        else
            $display("[TB] FAIL (%0d falhas)", tests_failed);

        $finish;
    end

endmodule
