// ============================================================================
// top.v  —  FPGA Top-Level para EduRISC-32v2
// Alvo: Digilent Arty A7-35T  (xc7a35ticsg324-1L)
// Clock de entrada: 100 MHz  →  CPU roda a 25 MHz (divisor por 4)
//
// Mapeamento de pinos externos:
//   clk100      → E3   (CLK100MHZ)
//   rst_btn     → C2   (BTN0, ativo alto)
//   led[3:0]    → H5,J5,T9,T10  (LD0-LD3)
//   uart_tx     → D10  (UART_TXD_IN)
//   uart_rx     → A9   (UART_RXD_OUT)
//
// LEDs:
//   led[3:0]  — exibe os 4 bits inferiores do resultado final após HALT
//   led[3]    — pisca a ~1 Hz enquanto a CPU está executando
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module fpga_top (
    input  wire       clk100,    // 100 MHz on-board
    input  wire       rst_btn,   // push-button reset (ativo alto)
    output wire [3:0] led,
    output wire       uart_tx,
    input  wire       uart_rx
);

    // -----------------------------------------------------------------------
    // Divisor de clock  100 MHz → 25 MHz
    // -----------------------------------------------------------------------
    reg [1:0] clk_div;
    reg       cpu_clk;

    always @(posedge clk100) begin
        clk_div <= clk_div + 1;
    end
    always @(posedge clk100) begin
        if (clk_div == 2'd1) cpu_clk <= 1;
        if (clk_div == 2'd3) cpu_clk <= 0;
    end

    // -----------------------------------------------------------------------
    // Reset sincronizado para domínio 25 MHz
    // -----------------------------------------------------------------------
    reg [2:0] rst_sync;
    wire      cpu_rst = rst_sync[2];

    always @(posedge cpu_clk) begin
        rst_sync <= {rst_sync[1:0], rst_btn};
    end

    // -----------------------------------------------------------------------
    // Instâncias da CPU
    // -----------------------------------------------------------------------
    wire [31:0] debug_reg;    // resultado para LEDs
    wire        halted;

    cpu_top u_cpu (
        .clk       (cpu_clk),
        .rst       (cpu_rst),
        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx),
        .debug_out (debug_reg),
        .halted    (halted)
    );

    // -----------------------------------------------------------------------
    // LED blink (≈1 Hz em 25 MHz) e display de resultado
    // -----------------------------------------------------------------------
    reg [24:0] blink_cnt;
    reg        blink;

    always @(posedge cpu_clk) begin
        blink_cnt <= blink_cnt + 1;
        if (blink_cnt == 25'd12_500_000) begin
            blink_cnt <= 0;
            blink     <= ~blink;
        end
    end

    // Enquanto executa → led[3] pisca; ao parar → mostra resultado
    assign led[3]   = halted ? debug_reg[3] : blink;
    assign led[2:0] = halted ? debug_reg[2:0] : 3'b000;

endmodule
`default_nettype wire
