// ============================================================================
// fpga/top_module.v  —  Wrapper FPGA para EduRISC-32 — Arty A7-35T
//
// • Divisor de clock:  100 MHz externo → ~25 MHz para a CPU
//   (permite observar o pipeline pelo olho; altere o parâmetro CLK_DIV)
// • Reset:  ativo alto, conectado a BTN0
// • LEDs:   exibem R0[3:0] quando a CPU faz halt (útil como "saída")
// • IMEM:   carregada via constante  IMEM_HEX (ajuste antes de sintetizar)
//
// Para usar a CPU em velocidade máxima (100 MHz) mude CLK_DIV a 1.
// ============================================================================
`timescale 1ns/1ps
`include "../rtl_v/isa_pkg.vh"

module top_module #(
    parameter CLK_DIV    = 4,           // factor de divisão do clock
    parameter IMEM_HEX   = "prog.hex"   // arquivo hex carregado na IMEM
) (
    input  wire        sys_clk,
    input  wire        sys_rst,

    output wire [3:0]  led
);

    // ------------------------------------------------------------------
    // Divisor de Clock simples (power-of-2)
    // ------------------------------------------------------------------
    reg [$clog2(CLK_DIV)-1:0] clk_cnt;
    reg cpu_clk;

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            clk_cnt <= 0;
            cpu_clk <= 1'b0;
        end else begin
            if (clk_cnt == CLK_DIV/2 - 1) begin
                clk_cnt <= 0;
                cpu_clk <= ~cpu_clk;
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    wire [27:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire        dbg_halted;

    cpu_top #(
        .IMEM_INIT_FILE(IMEM_HEX)
    ) u_cpu (
        .clk        (cpu_clk),
        .rst        (sys_rst),
        .dbg_pc     (dbg_pc),
        .dbg_instr  (dbg_instr),
        .dbg_halted (dbg_halted)
    );

    // ------------------------------------------------------------------
    // LEDs: mostram R0[3:0] quando halted; piscam durante execução
    // ------------------------------------------------------------------
    // Acesso ao register file do DUT (read-only, síntese só lê ports)
    wire [31:0] r0_val = u_cpu.u_rf.regs[0];

    // Contador lento para piscar (divide cpu_clk por ~2^22)
    reg [22:0] blink_cnt;
    always @(posedge cpu_clk or posedge sys_rst)
        if (sys_rst) blink_cnt <= 0;
        else         blink_cnt <= blink_cnt + 1;

    assign led = dbg_halted ? r0_val[3:0] : {4{blink_cnt[22]}};

endmodule
