// ============================================================================
// cpu_tb.v  —  Testbench do EduRISC-32
//
// Testes executados:
//
//  TEST 1 — Operações básicas da ALU (ADD, SUB, AND, OR, XOR, NOT)
//  TEST 2 — Multiplicação e Divisão
//  TEST 3 — LOAD / STORE
//  TEST 4 — Loop com JNZ  (soma 1+2+3+4+5 = 15, igual ao Demo 1 Python)
//  TEST 5 — Forwarding: RAW imediato (sem stall)
//  TEST 6 — Load-use hazard (stall de 1 ciclo)
//  TEST 7 — CALL / RET
//
// Uso com Icarus Verilog:
//   iverilog -g2012 -I rtl_v -o sim.out testbench/cpu_tb.v rtl_v/*.v
//   vvp sim.out
//   gtkwave dump.vcd &
// ============================================================================
`timescale 1ns/1ps

module cpu_tb;

    // ------------------------------------------------------------------
    // DUT — cpu_top com arquivo hex injetado via parâmetro
    // ------------------------------------------------------------------
    parameter IMEM_INIT = "testbench/test_program.hex";

    reg clk, rst;
    wire [27:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire        dbg_halted;

    cpu_top #(
        .IMEM_INIT_FILE(IMEM_INIT)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .dbg_pc     (dbg_pc),
        .dbg_instr  (dbg_instr),
        .dbg_halted (dbg_halted)
    );

    // ------------------------------------------------------------------
    // Clock: período de 10 ns (100 MHz)
    // ------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Tarefa de reset
    // ------------------------------------------------------------------
    task do_reset;
        begin
            rst = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst = 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Espera pelo halt ou timeout
    // ------------------------------------------------------------------
    task wait_halt;
        input integer max_cycles;
        integer i;
        begin
            for (i = 0; i < max_cycles; i = i + 1) begin
                if (dbg_halted) disable wait_halt;
                @(posedge clk); #1;
            end
            $display("TIMEOUT: halt não atingido em %0d ciclos", max_cycles);
        end
    endtask

    // ------------------------------------------------------------------
    // Acesso ao register file do DUT
    // ------------------------------------------------------------------
    `define RF dut.u_rf.regs

    // ------------------------------------------------------------------
    // Geração de VCD para GTKWave
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("testbench/dump.vcd");
        $dumpvars(0, cpu_tb);
    end

    // ------------------------------------------------------------------
    // Sequência de testes
    // ------------------------------------------------------------------
    integer pass_count, fail_count;

    task check;
        input [63:0] name;
        input [31:0] got, expected;
        begin
            if (got === expected) begin
                $display("  PASS  %-20s got=0x%08X", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-20s got=0x%08X  expected=0x%08X",
                         name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Carga de programa inline via $readmemh dinâmico
    // ----------------------------------------------------------------
    // Os 7 programas de teste são codificados diretamente na IMEM
    // através de uma tarefa que escreve no array interno.
    // Formato de instrução EduRISC-32:
    //   ADD  rd rs1 rs2  → {4'hOP, rd, rs1, rs2, 16'b0}
    //   LOAD rd base off → {4'hOP, rd, base, off20}
    //   JNZ  addr28      → {4'hOP, addr28}
    //
    // Constantes de opcode (duplicadas aqui para o testbench)
    // ------------------------------------------------------------------
    `define TB_OP_ADD  4'h0
    `define TB_OP_SUB  4'h1
    `define TB_OP_MUL  4'h2
    `define TB_OP_DIV  4'h3
    `define TB_OP_AND  4'h4
    `define TB_OP_OR   4'h5
    `define TB_OP_XOR  4'h6
    `define TB_OP_NOT  4'h7
    `define TB_OP_LOAD 4'h8
    `define TB_OP_STOR 4'h9
    `define TB_OP_JMP  4'hA
    `define TB_OP_JZ   4'hB
    `define TB_OP_JNZ  4'hC
    `define TB_OP_CALL 4'hD
    `define TB_OP_RET  4'hE
    `define TB_OP_HLT  4'hF

    // Helper: instrução R-type
    function [31:0] R;
        input [3:0] op, rd, rs1, rs2;
        R = {op, rd, rs1, rs2, 16'b0};
    endfunction

    // Helper: instrução I-type (rs1+imm20 → rd)
    function [31:0] I;
        input [3:0] op, rd, rs1;
        input [19:0] imm;
        I = {op, rd, rs1, imm};
    endfunction

    // Helper: instrução J-type
    function [31:0] J;
        input [3:0] op;
        input [27:0] addr;
        J = {op, addr};
    endfunction

    // Helper: instrução M-type  (LOAD/STORE)
    function [31:0] M;
        input [3:0] op, rd, base;
        input [19:0] off;
        M = {op, rd, base, off};
    endfunction

    // Helper: NOT (usa apenas rs1, rd)
    function [31:0] NOT_I;
        input [3:0] rd, rs1;
        NOT_I = {`TB_OP_NOT, rd, rs1, 20'b0};
    endfunction

    // ----------------------------------------------------------------
    // Procedure: load imem com um programa
    // ----------------------------------------------------------------
    integer k;
    task load_program;
        input integer base_addr;
        input integer prog_len;
        input [31:0] prog [0:63];
        begin
            for (k = 0; k < prog_len; k = k + 1)
                dut.u_mem.imem[base_addr + k] = prog[k];
        end
    endtask

    // Programa compartilhado (array de trabalho)
    reg [31:0] prog [0:63];

    // ================================================================
    // MAIN
    // ================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("======================================================");
        $display("  EduRISC-32  —  Testbench Completo");
        $display("======================================================");

        // =============================================================
        // TEST 1 — Operações básicas da ALU
        // =============================================================
        $display("\n[TEST 1] Operações básicas da ALU");

        // Limpa imem
        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;

        // Programa:
        //  addr 0: ADD  R1  R0  R0      ; R1 = R0 + R0 = 0
        //  addr 1: imm  R1 ← 10        ; I-type ADD R1 = R0 + 10
        //  addr 2: imm  R2 ← 7         ; R2 = 7
        //  addr 3: ADD  R3 R1 R2        ; R3 = 17
        //  addr 4: SUB  R4 R1 R2        ; R4 = 3
        //  addr 5: AND  R5 R1 R2        ; R5 = 10&7 = 2
        //  addr 6: OR   R6 R1 R2        ; R6 = 10|7 = 15
        //  addr 7: XOR  R7 R1 R2        ; R7 = 10^7 = 13
        //  addr 8: NOT  R8 R1           ; R8 = ~10
        //  addr 9: HLT
        dut.u_mem.imem[0] = I(`TB_OP_ADD, 4'd1, 4'd0, 20'd10);
        dut.u_mem.imem[1] = I(`TB_OP_ADD, 4'd2, 4'd0, 20'd7);
        dut.u_mem.imem[2] = R(`TB_OP_ADD, 4'd3, 4'd1, 4'd2);
        dut.u_mem.imem[3] = R(`TB_OP_SUB, 4'd4, 4'd1, 4'd2);
        dut.u_mem.imem[4] = R(`TB_OP_AND, 4'd5, 4'd1, 4'd2);
        dut.u_mem.imem[5] = R(`TB_OP_OR,  4'd6, 4'd1, 4'd2);
        dut.u_mem.imem[6] = R(`TB_OP_XOR, 4'd7, 4'd1, 4'd2);
        dut.u_mem.imem[7] = NOT_I(4'd8, 4'd1);
        dut.u_mem.imem[8] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(50);
        #20;

        check("R1=10",  `RF[1],  32'd10);
        check("R2=7",   `RF[2],  32'd7);
        check("R3=17",  `RF[3],  32'd17);
        check("R4=3",   `RF[4],  32'd3);
        check("R5=AND", `RF[5],  32'd2);
        check("R6=OR",  `RF[6],  32'd15);
        check("R7=XOR", `RF[7],  32'd13);
        check("R8=NOT", `RF[8],  ~32'd10);

        // =============================================================
        // TEST 2 — MUL / DIV
        // =============================================================
        $display("\n[TEST 2] MUL / DIV");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;

        dut.u_mem.imem[0] = I(`TB_OP_ADD, 4'd1, 4'd0, 20'd6);
        dut.u_mem.imem[1] = I(`TB_OP_ADD, 4'd2, 4'd0, 20'd7);
        dut.u_mem.imem[2] = R(`TB_OP_MUL, 4'd3, 4'd1, 4'd2); // R3 = 42
        dut.u_mem.imem[3] = R(`TB_OP_DIV, 4'd4, 4'd3, 4'd2); // R4 = 42/7 = 6
        dut.u_mem.imem[4] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(40);
        #20;

        check("R3=42", `RF[3], 32'd42);
        check("R4=6",  `RF[4], 32'd6);

        // =============================================================
        // TEST 3 — LOAD / STORE
        // =============================================================
        $display("\n[TEST 3] LOAD / STORE");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;
        // Pré-inicializa dmem[5] = 0xDEAD_BEEF
        dut.u_mem.dmem[5] = 32'hDEAD_BEEF;

        // R1 = 5; LOAD R2, R1, 0  → R2 = dmem[5]
        // STORE dmem[6] = R2  (base=R1, off=1)
        // LOAD  R3, R1, 1    → R3 = dmem[6]
        // HLT
        dut.u_mem.imem[0] = I(`TB_OP_ADD,  4'd1, 4'd0, 20'd5);
        dut.u_mem.imem[1] = M(`TB_OP_LOAD, 4'd2, 4'd1, 20'd0);
        dut.u_mem.imem[2] = M(`TB_OP_STOR, 4'd2, 4'd1, 20'd1);
        dut.u_mem.imem[3] = M(`TB_OP_LOAD, 4'd3, 4'd1, 20'd1);
        dut.u_mem.imem[4] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(60);
        #20;

        check("R2=DEAD_BEEF", `RF[2], 32'hDEAD_BEEF);
        check("R3=DEAD_BEEF", `RF[3], 32'hDEAD_BEEF);

        // =============================================================
        // TEST 4 — Loop JNZ: soma 1..5 = 15  (mesmo resultado do Demo 1)
        // =============================================================
        $display("\n[TEST 4] Loop JNZ: sum(1..5)=15");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;

        // Registradores:
        //  R1 = acumulador (soma)
        //  R2 = contador (i)
        //  R3 = limite    (5)
        //  R4 = 1 (passo)
        //
        // Programa (PC em palavras):
        //  0: R1 = 0
        //  1: R2 = 1      ; i=1
        //  2: R3 = 5      ; limite
        //  3: R4 = 1
        //  4: R1 = R1 + R2  ; soma += i
        //  5: R2 = R2 + R4  ; i++
        //  6: R5 = R3 - R2  ; R5 = limite - i (CMP)
        //  7: JNZ 4         ; se R5 != 0 volta ao addr 4
        //  8: HLT
        dut.u_mem.imem[0] = I(`TB_OP_ADD, 4'd1, 4'd0, 20'd0);
        dut.u_mem.imem[1] = I(`TB_OP_ADD, 4'd2, 4'd0, 20'd1);
        dut.u_mem.imem[2] = I(`TB_OP_ADD, 4'd3, 4'd0, 20'd5);
        dut.u_mem.imem[3] = I(`TB_OP_ADD, 4'd4, 4'd0, 20'd1);
        dut.u_mem.imem[4] = R(`TB_OP_ADD, 4'd1, 4'd1, 4'd2);
        dut.u_mem.imem[5] = R(`TB_OP_ADD, 4'd2, 4'd2, 4'd4);
        dut.u_mem.imem[6] = R(`TB_OP_SUB, 4'd5, 4'd3, 4'd2);
        dut.u_mem.imem[7] = J(`TB_OP_JNZ, 28'd4);
        dut.u_mem.imem[8] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(150);
        #20;

        check("R1=15 (sum)", `RF[1], 32'd15);

        // =============================================================
        // TEST 5 — Forwarding RAW (resultado de ADD imediato usado no ciclo seguinte)
        // =============================================================
        $display("\n[TEST 5] Forwarding EX/MEM→EX");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;

        // R1 = 1
        // R2 = R1 + 1   (forward de R1 gerado pelo EX anterior)
        // R3 = R2 + R1  (forward dos dois)
        // HLT
        dut.u_mem.imem[0] = I(`TB_OP_ADD, 4'd1, 4'd0, 20'd1);
        dut.u_mem.imem[1] = I(`TB_OP_ADD, 4'd2, 4'd1, 20'd1);
        dut.u_mem.imem[2] = R(`TB_OP_ADD, 4'd3, 4'd2, 4'd1);
        dut.u_mem.imem[3] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(30);
        #20;

        check("R1=1",   `RF[1], 32'd1);
        check("R2=2",   `RF[2], 32'd2);
        check("R3=3",   `RF[3], 32'd3);

        // =============================================================
        // TEST 6 — Load-use hazard (stall automático de 1 ciclo)
        // =============================================================
        $display("\n[TEST 6] Load-use hazard");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;
        dut.u_mem.dmem[0] = 32'd99;

        // R1 = 0
        // LOAD R2, R1, 0   → R2 = dmem[0] = 99
        // ADD  R3, R2, R2  → R3 = 198  (load-use: hazard_unit insere stall)
        // HLT
        dut.u_mem.imem[0] = I(`TB_OP_ADD,  4'd1, 4'd0, 20'd0);
        dut.u_mem.imem[1] = M(`TB_OP_LOAD, 4'd2, 4'd1, 20'd0);
        dut.u_mem.imem[2] = R(`TB_OP_ADD,  4'd3, 4'd2, 4'd2);
        dut.u_mem.imem[3] = J(`TB_OP_HLT, 28'b0);

        do_reset;
        wait_halt(40);
        #20;

        check("R2=99",  `RF[2], 32'd99);
        check("R3=198", `RF[3], 32'd198);

        // =============================================================
        // TEST 7 — CALL / RET
        // =============================================================
        $display("\n[TEST 7] CALL / RET");

        for (k = 0; k < 64; k = k + 1) dut.u_mem.imem[k] = 32'h0;

        // addr 0: R1 = 10
        // addr 1: CALL func (addr 5)    ; R15 = 2
        // addr 2: ADD R2, R1, R1        ; R2 = 20 (executa após retorno)
        // addr 3: HLT
        // --- func @ addr 5 ---
        // addr 5: ADD R1, R1, R1        ; R1 = 20
        // addr 6: RET                   ; volta para addr 2
        dut.u_mem.imem[0] = I(`TB_OP_ADD, 4'd1, 4'd0, 20'd10);
        dut.u_mem.imem[1] = J(`TB_OP_CALL, 28'd5);
        dut.u_mem.imem[2] = R(`TB_OP_ADD, 4'd2, 4'd1, 4'd1);
        dut.u_mem.imem[3] = J(`TB_OP_HLT, 28'b0);
        dut.u_mem.imem[5] = R(`TB_OP_ADD, 4'd1, 4'd1, 4'd1);
        dut.u_mem.imem[6] = {`TB_OP_RET, 4'd0, 4'd15, 20'b0}; // RET usa R15

        do_reset;
        wait_halt(60);
        #20;

        check("R1=20 (after call)", `RF[1], 32'd20);
        check("R2=40 (after ret)",  `RF[2], 32'd40);

        // =============================================================
        // Resultado final
        // =============================================================
        $display("\n======================================================");
        $display("  Resultado: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("======================================================");

        if (fail_count == 0)
            $display("  *** TODOS OS TESTES PASSARAM ***");
        else
            $display("  !!! FALHAS DETECTADAS — verifique o log acima !!!");

        $finish;
    end

    // Timeout global de segurança
    initial begin
        #200000;
        $display("TIMEOUT GLOBAL: simulação abortada");
        $finish;
    end

endmodule
