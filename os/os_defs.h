/* ============================================================================
 * os_defs.h — Definições compartilhadas do Sistema Operacional EduRISC-32v2
 *
 * Inclua este header em todos os módulos do OS (kernel.c, scheduler.c,
 * memory.c, syscalls.c, interrupts.c, process.c) para garantir consistência
 * de constantes, endereços MMIO e estados de processo.
 *
 * NÃO inclua stdint.h aqui — os módulos do OS usam o compilador C-like
 * simplificado que não fornece esses tipos. Para código com GCC/Clang real
 * (process.c, interrupts.c) inclua stdint.h diretamente no .c.
 * ============================================================================ */

#ifndef OS_DEFS_H
#define OS_DEFS_H

/* ---------------------------------------------------------------------------
 * Configuração geral do sistema
 * --------------------------------------------------------------------------- */
#define MAX_PROCS       8           /* Número máximo de processos simultâneos */
#define STACK_SIZE      256         /* Tamanho de pilha por processo (words)   */
#define PROC_NAME_LEN   16          /* Tamanho do campo name na tabela        */

/* ---------------------------------------------------------------------------
 * Layout de memória (espaço de endereços de dados — DMEM)
 *
 *   0x0000 – 0x0FFF  : Área de variáveis globais do kernel e pilhas de ISR
 *   0x0FF0            : Registrador tick_counter (1 word)
 *   0x1000 – 0x1FFF  : Tabela de processos (MAX_PROCS × ENTRY_SIZE words)
 *   0x2000 – 0xEFFF  : HEAP gerenciado pelo kmalloc/kfree
 *   0xF000 – 0xFEFF  : Área de pilha inicial do bootloader / ISR
 *   0xFF00 – 0xFFFF  : MMIO (UART, Timer, GPIO …)
 * --------------------------------------------------------------------------- */
#define DMEM_BASE       0x0000
#define TICK_COUNTER    0x0FF0      /* Endereço do contador de ticks (1 word)  */
#define PROC_TABLE      0x1000      /* Base da tabela de processos em DMEM     */
#define STACK_TOP       0xFFFF      /* Topo da pilha (palavra mais alta da RAM) */

/* ---------------------------------------------------------------------------
 * MMIO — Memory-Mapped I/O
 * --------------------------------------------------------------------------- */
#define UART_TXDATA     0xFF00      /* Registrador de transmissão UART TX      */
#define UART_RXDATA     0xFF01      /* Registrador de recepção UART RX         */
#define UART_STATUS     0xFF02      /* Status: bit0=TX_READY, bit1=RX_READY    */
#define TIMER_CMP_ADDR  0xFF10      /* Comparador do timer (quantum preemptivo) */
#define TIMER_CNT_ADDR  0xFF11      /* Contador do timer (somente leitura)     */

/* Bits do registrador UART_STATUS */
#define UART_TX_READY   0x01        /* UART pode aceitar novo byte TX          */
#define UART_RX_READY   0x02        /* UART tem byte RX disponível             */

/* Quantum do timer em ciclos de clock */
#define TIMER_QUANTUM   10000

/* ---------------------------------------------------------------------------
 * Tabela de processos — formato de cada entrada
 *
 * Cada entrada ocupa ENTRY_SIZE words a partir de PROC_TABLE + pid*ENTRY_SIZE.
 *
 *   [0]  = pid
 *   [1]  = estado (PROC_FREE / PROC_READY / PROC_RUNNING / PROC_BLOCKED)
 *   [2]  = PC salvo
 *   [3]  = SP salvo
 *   [4–15] = R1–R12 salvos
 * --------------------------------------------------------------------------- */
#define ENTRY_SIZE      16          /* Words por entrada na tabela             */

/* Offsets dos campos dentro de cada entrada */
#define FIELD_PID       0
#define FIELD_STATE     1
#define FIELD_PC        2
#define FIELD_SP        3
#define FIELD_R1        4           /* R1..R12 salvos nos slots 4..15          */

/* Estados de processo */
#define PROC_FREE       0
#define PROC_READY      1
#define PROC_RUNNING    2
#define PROC_BLOCKED    3
#define PROC_ZOMBIE     4

/* Valores especiais de PID */
#define PID_IDLE        0           /* PID do processo idle (nunca termina)    */
#define PID_INVALID     (-1)        /* PID de retorno de erro                  */

/* ---------------------------------------------------------------------------
 * Heap (gerenciado por memory.c)
 * --------------------------------------------------------------------------- */
#define HEAP_START      0x2000
#define HEAP_END        0xF000
#define HEAP_SIZE       (HEAP_END - HEAP_START)
#define BLOCK_FREE      0
#define BLOCK_USED      1
#define HEADER_WORDS    2           /* Tamanho do header de cada bloco (words) */

/* ---------------------------------------------------------------------------
 * Syscalls — números de chamada de sistema
 * --------------------------------------------------------------------------- */
#define SYS_EXIT        0
#define SYS_WRITE       1
#define SYS_READ        2
#define SYS_MALLOC      3
#define SYS_FREE        4
#define SYS_YIELD       5
#define SYS_GETPID      6
#define SYS_SLEEP       7
#define SYS_HEAPSTAT    8
#define SYS_UPTIME      9

/* ---------------------------------------------------------------------------
 * Protótipos de funções exportadas entre módulos C-like
 * (sem #include de cabeçalhos externos — compatível com o compilador simples)
 * --------------------------------------------------------------------------- */
void uart_putchar(int c);
void uart_puts(int *s);
void uart_puthex(int val);
int  kmalloc(int size);
void kfree(int *ptr);
void kmemset(int *ptr, int val, int n);
void kmemcpy(int *dst, int *src, int n);
void heap_stats(int *free_blocks, int *used_blocks);
int  schedule(void);
void memory_init(void);
void process_exit(int code);

#endif /* OS_DEFS_H */
