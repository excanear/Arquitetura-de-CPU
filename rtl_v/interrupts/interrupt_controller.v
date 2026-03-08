// ============================================================================
// interrupt_controller.v  —  Controlador de Interrupções EduRISC-32v2
//
// Gerencia 8 fontes de interrupção:
//   Fonte 0: Timer (gerado internamente quando cycle >= timer_compare)
//   Fontes 1–7: Externas (saídas de periféricos)
//
// Funciona com interrupções vetorizadas:
//   IVT (Interrupt Vector Table) base endereço = CSR IVT
//   Cada entrada na IVT tem 1 palavra de 32 bits (endereço do handler)
//   Vetor de interrupção para fonte N: IVT_BASE + N
//
// Saídas para o pipeline:
//   irq_pending — 1=existe interrupção pendente e habilitada
//   irq_cause   — índice da interrupção mais prioritária (0=maior prioridade)
//   irq_vec_pc  — PC do handler da interrupção
//
// Integração com CSR STATUS:
//   STATUS[0] = IE  (global interrupt enable)
//   STATUS[7:4] = IM (interrupt mask, bit N habilita fonte N)
// ============================================================================
`timescale 1ns/1ps
`include "../isa_pkg.vh"

module interrupt_controller (
    input  wire        clk,
    input  wire        rst,

    // Fontes de interrupção
    input  wire        timer_irq,       // fonte 0 (timer)
    input  wire [6:0]  ext_irq,         // fontes 1..7

    // Configuração via CSR
    input  wire [31:0] csr_status,      // STATUS CSR
    input  wire [31:0] csr_ivt,         // IVT base address

    // Pipeline em qual estágio se encontra
    input  wire        in_exception,    // 1=já estamos no handler (mascara novas)

    // Saídas para o pipeline
    output wire        irq_pending,     // interrupção deve ser atendida agora
    output wire [4:0]  irq_cause,       // código INT_* (para CAUSE CSR)
    output wire [25:0] irq_vector_pc,   // PC do handler

    // Confirmação de atendimento (pipeline aceita a interrupção)
    input  wire        irq_ack
);

    wire        ie  = csr_status[0];
    wire [7:0]  im  = csr_status[7:0];  // im[0]=timer, im[7:1]=ext[6:0]

    // Conjunto de pedidos
    wire [7:0] irq_requests = {ext_irq, timer_irq} & im;

    // Prioridade fixa: menor índice = maior prioridade
    wire [7:0] irq_masked = irq_requests & ~{8{in_exception}};

    reg  [2:0] highest;         // índice da interrupção mais prioritária
    reg        any_pending;

    always @(*) begin
        highest     = 3'b0;
        any_pending = 1'b0;
        if (irq_masked[0]) begin highest = 3'd0; any_pending = 1; end
        else if (irq_masked[1]) begin highest = 3'd1; any_pending = 1; end
        else if (irq_masked[2]) begin highest = 3'd2; any_pending = 1; end
        else if (irq_masked[3]) begin highest = 3'd3; any_pending = 1; end
        else if (irq_masked[4]) begin highest = 3'd4; any_pending = 1; end
        else if (irq_masked[5]) begin highest = 3'd5; any_pending = 1; end
        else if (irq_masked[6]) begin highest = 3'd6; any_pending = 1; end
        else if (irq_masked[7]) begin highest = 3'd7; any_pending = 1; end
    end

    assign irq_pending   = ie && any_pending;
    assign irq_cause     = {2'b0, highest};            // INT_TIMER=0, INT_EXT0..6=1..7
    assign irq_vector_pc = csr_ivt[25:0] + {23'b0, highest}; // IVT_BASE + cause

endmodule
