/* ============================================================================
 * kernel.c  —  Kernel mínimo EduRISC-32v2
 *
 * Compilado pelo compilador EduRISC-32 (compiler/compiler.py).
 * Estilo de C simplificado: sem libc, sem tipos complexos além de int/char.
 *
 * Funcionalidades:
 *   - Inicialização do sistema
 *   - Tabela de processos (máximo 8 processos)
 *   - Dispatcher (round-robin preemptivo via timer)
 *   - Chamadas de sistema (via SYSCALL)
 *   - UART para output de debug
 * ============================================================================ */

#include "os_defs.h"

/* ---------------------------------------------------------------------------
 * Variável global: índice do processo atual e contagem total de processos
 * --------------------------------------------------------------------------- */
int current_pid;
int num_procs;

/* ---------------------------------------------------------------------------
 * Declaração antecipada de funções definidas em outros módulos
 * (necessária para que kernel_main() possa referenciar demo_process e
 *  a função de escalonamento do scheduler.c)
 * --------------------------------------------------------------------------- */
void demo_process(void);   /* definida em scheduler.c */

/* ---------------------------------------------------------------------------
 * uart_putchar: envia um caractere pela UART (busy-wait no TX_READY)
 * --------------------------------------------------------------------------- */
void uart_putchar(int c) {
    int *uart_status;
    int *uart_tx;
    uart_status = (int *)UART_STATUS;
    uart_tx     = (int *)UART_TXDATA;
    /* Aguarda UART pronta para transmitir (bit UART_TX_READY) */
    while ((*uart_status & UART_TX_READY) == 0) { }
    *uart_tx = c;
}

/* ---------------------------------------------------------------------------
 * uart_puts: envia uma string (terminada em 0)
 * --------------------------------------------------------------------------- */
void uart_puts(int *s) {
    int i;
    if (s == (int *)0) {
        return;
    }
    i = 0;
    while (s[i] != 0) {
        uart_putchar(s[i]);
        i = i + 1;
    }
}

/* ---------------------------------------------------------------------------
 * uart_puthex: envia um número em hexadecimal (8 dígitos, prefixo 0x)
 * --------------------------------------------------------------------------- */
void uart_puthex(int val) {
    int i;
    int nibble;
    int digit;
    uart_putchar('0');
    uart_putchar('x');
    i = 28;
    while (i >= 0) {
        nibble = (val >> i) & 0xF;
        if (nibble < 10) {
            digit = '0' + nibble;
        } else {
            digit = 'A' + nibble - 10;
        }
        uart_putchar(digit);
        i = i - 4;
    }
}

/* ---------------------------------------------------------------------------
 * uart_putdec: envia um inteiro sem sinal em decimal (até 10 dígitos)
 * --------------------------------------------------------------------------- */
void uart_putdec(int val) {
    int  buf[10];
    int  len;
    int  i;
    int  uval;

    if (val < 0) {
        uart_putchar('-');
        uval = -val;
    } else {
        uval = val;
    }

    if (uval == 0) {
        uart_putchar('0');
        return;
    }

    len = 0;
    while (uval > 0 && len < 10) {
        buf[len] = '0' + (uval % 10);
        uval = uval / 10;
        len = len + 1;
    }
    /* Imprime dígitos em ordem inversa */
    i = len - 1;
    while (i >= 0) {
        uart_putchar(buf[i]);
        i = i - 1;
    }
}

/* ---------------------------------------------------------------------------
 * proc_alloc: aloca uma entrada livre na tabela de processos
 * Retorna: pid alocado, ou -1 se tabela cheia
 * --------------------------------------------------------------------------- */
int proc_alloc() {
    int i;
    int *entry;
    i = 0;
    while (i < MAX_PROCS) {
        entry = (int *)(PROC_TABLE + i * ENTRY_SIZE);
        if (entry[FIELD_STATE] == PROC_FREE) {
            entry[FIELD_STATE] = PROC_READY;
            return i;
        }
        i = i + 1;
    }
    return PID_INVALID;
}

/* ---------------------------------------------------------------------------
 * proc_create: cria um novo processo a partir de um endereço de entrada
 * entry_point: endereço de início do código do processo
 * Retorna: pid criado, ou -1 se falha
 * --------------------------------------------------------------------------- */
int proc_create(int entry_point) {
    int pid;
    int *entry;
    pid = proc_alloc();
    if (pid < 0) {
        return PID_INVALID;
    }
    entry = (int *)(PROC_TABLE + pid * ENTRY_SIZE);
    entry[FIELD_PID]   = pid;
    entry[FIELD_STATE] = PROC_READY;
    entry[FIELD_PC]    = entry_point;
    /* SP inicial: topo da pilha deste processo (não sobrepõe outros processos) */
    entry[FIELD_SP]    = STACK_TOP - pid * STACK_SIZE;
    num_procs = num_procs + 1;
    return pid;
}

/* ---------------------------------------------------------------------------
 * schedule: seleciona o próximo processo pronto para rodar (round-robin)
 * Retorna: pid do próximo processo READY; retorna current_pid se nenhum
 * --------------------------------------------------------------------------- */
int schedule() {
    int i;
    int next;
    int *entry;
    i = (current_pid + 1) & (MAX_PROCS - 1);   /* módulo MAX_PROCS (potência de 2) */
    next = PID_INVALID;
    while (i != current_pid) {
        entry = (int *)(PROC_TABLE + i * ENTRY_SIZE);
        if (entry[FIELD_STATE] == PROC_READY) {
            next = i;
            break;
        }
        i = (i + 1) & (MAX_PROCS - 1);
    }
    if (next < 0) {
        next = current_pid;     /* manter processo atual se nenhum pronto */
    }
    return next;
}

/* ---------------------------------------------------------------------------
 * idle_task: processo ocioso — roda quando não há nada a fazer
 * --------------------------------------------------------------------------- */
void idle_task() {
    while (1) {
        /* Aguarda interrupção do timer sem consumir recursos úteis.
         * Em hardware real seria substituído por HLT/WFI. */
    }
}

/* ---------------------------------------------------------------------------
 * kernel_main: ponto de entrada do kernel (chamado pelo bootloader)
 * --------------------------------------------------------------------------- */
void kernel_main() {
    int *timer_cmp;
    int *tick_ptr;

    /* Inicializar variáveis globais */
    current_pid = 0;
    num_procs   = 0;

    /* Zerar contador de ticks */
    tick_ptr  = (int *)TICK_COUNTER;
    *tick_ptr = 0;

    /* Exibir mensagem de boot */
    uart_puts("EduRISC-32v2 Kernel v1.0\n");
    uart_puts("Inicializando subsistemas...\n");

    /* Inicializar heap de memória */
    memory_init();
    uart_puts("  [OK] Memoria: heap inicializado\n");

    /* Configurar timer para quantum de preempção */
    timer_cmp  = (int *)TIMER_CMP_ADDR;
    *timer_cmp = TIMER_QUANTUM;
    uart_puts("  [OK] Timer: quantum=");
    uart_putdec(TIMER_QUANTUM);
    uart_puts(" ciclos\n");

    /* Criar processo idle (PID 0) — sempre pronto */
    proc_create(idle_task);
    uart_puts("  [OK] Processo idle criado (PID 0)\n");

    /* Criar processo de demonstração (PID 1) */
    proc_create(demo_process);
    uart_puts("  [OK] Processo demo criado (PID 1)\n");

    uart_puts("Kernel pronto. Aguardando interrupcoes...\n");

    /* Loop principal: o timer interrompe e chama o escalonador */
    while (1) { }
}
