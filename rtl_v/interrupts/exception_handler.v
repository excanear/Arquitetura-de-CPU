// ============================================================================
// exception_handler.v  —  Gerenciador de Exceções e Traps
//
// Centraliza toda a lógica de despacho de exceções e interrupções.
// Gera o novo PC (trap target) e os valores de EPC / CAUSE para salvar no CSR.
//
// Prioridade (da mais alta para a mais baixa):
//   1. NMI (Non-Maskable Interrupt) — não implementado, reservado
//   2. Instrução ilegal (decode)
//   3. Page fault em IF
//   4. Divisão por zero (EX)
//   5. Overflow aritmético (EX)
//   6. SYSCALL / BREAK (EX)
//   7. Page fault em MEM (LOAD/STORE)
//   8. Interrupção de timer
//   9. Interrupções externas (prioridade pelo índice do IRQ)
//
// Saídas:
//   take_trap     — 1=redirecionar PC para trap_target
//   trap_target   — novo PC (IVT[cause] ou IVT[irq_cause])
//   save_pc       — valor a salvar em EPC
//   save_cause    — valor a salvar em CAUSE
// ============================================================================
`timescale 1ns/1ps
`include "../isa_pkg.vh"

module exception_handler (
    // Exceções do pipeline
    input  wire        exc_illegal,      // instrução ilegal (decode)
    input  wire        exc_div_zero,     // divisão por zero (EX)
    input  wire        exc_syscall,      // SYSCALL (EX)
    input  wire        exc_break,        // BREAK (EX)
    input  wire        exc_if_pf,        // page fault instrução
    input  wire        exc_load_pf,      // page fault carga
    input  wire        exc_store_pf,     // page fault armazenamento
    input  wire [25:0] faulting_pc,      // PC da instrução que causou a exceção

    // Interrupções
    input  wire        irq_pending,      // interrupção pendente
    input  wire [4:0]  irq_cause,        // código INT_*
    input  wire [25:0] irq_vector_pc,    // PC do handler da interrupção

    // Controle global
    input  wire        int_enable,       // STATUS.IE
    input  wire [31:0] csr_ivt,          // IVT base

    // Saídas
    output wire        take_trap,
    output wire [25:0] trap_target,
    output wire [25:0] save_epc,
    output wire [31:0] save_cause
);

    // ------------------------------------------------------------------
    // Qualquer exceção síncrona?
    // ------------------------------------------------------------------
    wire any_exc = exc_illegal | exc_div_zero | exc_syscall | exc_break |
                   exc_if_pf   | exc_load_pf  | exc_store_pf;

    // ------------------------------------------------------------------
    // Código de causa (CAUSE CSR)
    // Bit 31 = 0 → exceção síncrona
    // Bit 31 = 1 → interrupção assíncrona
    // ------------------------------------------------------------------
    wire [4:0] exc_code =
        exc_illegal   ? `EXC_ILLEGAL   :
        exc_if_pf     ? `EXC_IFETCH_PF :
        exc_div_zero  ? `EXC_DIV_ZERO  :
        exc_syscall   ? `EXC_SYSCALL   :
        exc_break     ? `EXC_BREAKPOINT:
        exc_load_pf   ? `EXC_LOAD_PF   :
        exc_store_pf  ? `EXC_STORE_PF  :
                        5'b0;

    // ------------------------------------------------------------------
    // Endereço de despacho (entrada na IVT)
    // IVT[exc_code] para exceções, IVT[irq_cause] para interrupções
    // ------------------------------------------------------------------
    wire [25:0] exc_vector_pc = csr_ivt[25:0] + {21'b0, exc_code};
    wire [25:0] int_vector_pc = irq_vector_pc;

    // ------------------------------------------------------------------
    // Saídas
    // ------------------------------------------------------------------
    // Exceções têm prioridade sobre interrupções
    assign take_trap   = any_exc | (irq_pending & int_enable);
    assign trap_target = any_exc ? exc_vector_pc : int_vector_pc;
    assign save_epc    = faulting_pc;
    assign save_cause  = any_exc ? {27'b0, exc_code} :
                                   {1'b1, 26'b0, irq_cause};   // bit31=1 para interrupção

endmodule
