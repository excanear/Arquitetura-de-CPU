/* ============================================================================
 * syscalls.c  —  Chamadas de Sistema EduRISC-32v2
 *
 * Despachadas pela instrução SYSCALL.
 * Número da chamada em R1; argumentos em R2–R5; resultado em R1.
 *
 * Tabela de syscalls:
 *   0  SYS_EXIT      — encerrar processo (R2=código)
 *   1  SYS_WRITE     — escrever em UART (R2=ptr, R3=len)
 *   2  SYS_READ      — ler da UART (R2=ptr, R3=len) com busy-wait real
 *   3  SYS_MALLOC    — alocar memória (R2=size → R1=ptr)
 *   4  SYS_FREE      — liberar memória (R2=ptr)
 *   5  SYS_YIELD     — ceder CPU voluntariamente
 *   6  SYS_GETPID    — retornar PID atual
 *   7  SYS_SLEEP     — bloquear por R2 ticks
 *   8  SYS_HEAPSTAT  — estatísticas do heap (R2=*free, R3=*used)
 *   9  SYS_UPTIME    — retornar tick counter atual
 * ============================================================================ */

#include "os_defs.h"

/* ---------------------------------------------------------------------------
 * sys_write: escreve 'len' words da área ptr na UART com busy-wait
 *
 * Valida ptr != NULL e len > 0 antes de acessar a memória.
 * Aguarda UART_TX_READY em UART_STATUS antes de cada escrita para não
 * perder bytes com FIFO cheia (comportamento correto em hardware real).
 * --------------------------------------------------------------------------- */
int sys_write(int *ptr, int len) {
    int  i;
    int *uart_status;
    int *uart_tx;

    if (ptr == (int *)0 || len <= 0) {
        return 0;
    }

    uart_status = (int *)UART_STATUS;
    uart_tx     = (int *)UART_TXDATA;

    i = 0;
    while (i < len) {
        /* Busy-wait: aguarda TX_READY antes de enviar cada byte */
        while ((*uart_status & UART_TX_READY) == 0) { }
        *uart_tx = ptr[i];
        i = i + 1;
    }
    return len;
}

/* ---------------------------------------------------------------------------
 * sys_read: lê até 'len' bytes da UART para ptr com busy-wait real
 *
 * Antes de ler cada byte, verifica o bit UART_RX_READY no UART_STATUS.
 * Bloqueia em busy-wait até um byte estar disponível (comportamento
 * equivalente ao getchar() com driver de polling em hardware real).
 * Valida ptr != NULL e len > 0.
 * --------------------------------------------------------------------------- */
int sys_read(int *ptr, int len) {
    int  i;
    int *uart_status;
    int *uart_rx;

    if (ptr == (int *)0 || len <= 0) {
        return 0;
    }

    uart_status = (int *)UART_STATUS;
    uart_rx     = (int *)UART_RXDATA;

    i = 0;
    while (i < len) {
        /* Busy-wait: aguarda byte disponível no RX */
        while ((*uart_status & UART_RX_READY) == 0) { }
        ptr[i] = *uart_rx;
        i = i + 1;
    }
    return len;
}

/* ---------------------------------------------------------------------------
 * sys_exit: encerra o processo atual
 *
 * Marca o processo como PROC_FREE, exibe código de saída pela UART
 * e transfere o controle para o escalonador via sys_yield().
 * --------------------------------------------------------------------------- */
void sys_exit(int code) {
    int *entry;
    /* Verifica limites de current_pid antes de acessar a tabela */
    if (current_pid < 0 || current_pid >= MAX_PROCS) {
        return;
    }
    entry = (int *)(PROC_TABLE + current_pid * ENTRY_SIZE);
    entry[FIELD_STATE] = PROC_FREE;

    /* Exibe código de saída pela UART */
    uart_putchar('X');
    uart_putchar('=');
    uart_puthex(code);
    uart_putchar('\n');

    /* Cede CPU — o escalonador nunca mais retornará a este processo */
    sys_yield();
}

/* ---------------------------------------------------------------------------
 * sys_yield: cede CPU voluntariamente (simula interrupção de timer)
 *
 * Em hardware real: a instrução SYSCALL dispara TRAP_SYSCALL → o handler
 * chama vm_schedule_next() que faz o context switch via ERET.
 * Aqui no simulador chamamos schedule() diretamente para manter a semântica.
 * --------------------------------------------------------------------------- */
void sys_yield() {
    int *entry;
    int  next;

    /* Verifica limites de current_pid */
    if (current_pid < 0 || current_pid >= MAX_PROCS) {
        return;
    }

    entry = (int *)(PROC_TABLE + current_pid * ENTRY_SIZE);
    if (entry[FIELD_STATE] == PROC_RUNNING) {
        entry[FIELD_STATE] = PROC_READY;
    }

    next = schedule();
    if (next < 0 || next >= MAX_PROCS) {
        next = PID_IDLE;
    }

    current_pid = next;
    entry = (int *)(PROC_TABLE + current_pid * ENTRY_SIZE);
    entry[FIELD_STATE] = PROC_RUNNING;
}

/* ---------------------------------------------------------------------------
 * sys_sleep: bloqueia o processo por 'ticks' ticks de timer
 *
 * Lê o tick_counter atual via MMIO e itera em sys_yield() até atingir
 * o tick alvo. Em hardware real, o processo seria colocado em PROC_BLOCKED
 * e acordado por um timer de wakeup no kernel; aqui usamos busy-wait com
 * yield para manter a simplicidade pedagógica.
 * --------------------------------------------------------------------------- */
void sys_sleep(int ticks) {
    int *tick_ptr;
    int  target;

    if (ticks <= 0) {
        return;
    }

    tick_ptr = (int *)TICK_COUNTER;
    target   = *tick_ptr + ticks;

    while (*tick_ptr < target) {
        sys_yield();
    }
}

/* ---------------------------------------------------------------------------
 * syscall_handler: despacha para a syscall correta
 *
 * Chamado pelo handler de exceção SYSCALL (cause=TRAP_SYSCALL).
 * Parâmetros passados pelo contexto salvo pelo handler assembly (R2–R5).
 * Retorna resultado que o handler colocará em R1 do processo retomado.
 * --------------------------------------------------------------------------- */
int syscall_handler(int num, int a1, int a2, int a3, int a4) {
    int  result;
    int *tick_ptr;

    result = 0;

    if (num == SYS_EXIT) {
        sys_exit(a1);

    } else if (num == SYS_WRITE) {
        result = sys_write((int *)a1, a2);

    } else if (num == SYS_READ) {
        result = sys_read((int *)a1, a2);

    } else if (num == SYS_MALLOC) {
        result = (int)kmalloc(a1);

    } else if (num == SYS_FREE) {
        kfree((int *)a1);
        result = 0;

    } else if (num == SYS_YIELD) {
        sys_yield();

    } else if (num == SYS_GETPID) {
        result = current_pid;

    } else if (num == SYS_SLEEP) {
        sys_sleep(a1);

    } else if (num == SYS_HEAPSTAT) {
        heap_stats((int *)a1, (int *)a2);

    } else if (num == SYS_UPTIME) {
        tick_ptr = (int *)TICK_COUNTER;
        result   = *tick_ptr;

    } else {
        /* Syscall inválida — retornar -1 (ENOSYS) */
        result = -1;
    }

    return result;
}
