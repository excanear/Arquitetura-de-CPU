/* ============================================================================
 * syscalls.c  —  Chamadas de Sistema EduRISC-32v2
 *
 * Despachadas pela instrução SYSCALL.
 * Número da chamada em R1; argumentos em R2–R5; resultado em R1.
 *
 * Tabela de syscalls:
 *   0  SYS_EXIT      — encerrar processo (R2=código)
 *   1  SYS_WRITE     — escrever em UART (R2=ptr, R3=len)
 *   2  SYS_READ      — ler da UART (R2=ptr, R3=len)
 *   3  SYS_MALLOC    — alocar memória (R2=size → R1=ptr)
 *   4  SYS_FREE      — liberar memória (R2=ptr)
 *   5  SYS_YIELD     — ceder CPU voluntariamente
 *   6  SYS_GETPID    — retornar PID atual
 *   7  SYS_SLEEP     — bloquear por R2 ticks
 *   8  SYS_HEAPSTAT  — estatísticas do heap (R2=*free, R3=*used)
 *   9  SYS_UPTIME    — retornar tick counter atual
 * ============================================================================ */

/* Números de syscall */
#define SYS_EXIT      0
#define SYS_WRITE     1
#define SYS_READ      2
#define SYS_MALLOC    3
#define SYS_FREE      4
#define SYS_YIELD     5
#define SYS_GETPID    6
#define SYS_SLEEP     7
#define SYS_HEAPSTAT  8
#define SYS_UPTIME    9

/* Endereços MMIO */
#define UART_RXDATA   0xFF01
#define TICK_COUNTER  0x0FF0

/* Declarações de funções externas (definidas em outros módulos) */
/* kmalloc, kfree, heap_stats — de memory.c  */
/* uart_putchar — de kernel.c */

/* ---------------------------------------------------------------------------
 * sys_write: escreve 'len' words da área ptr na UART
 * --------------------------------------------------------------------------- */
int sys_write(int *ptr, int len) {
    int i;
    i = 0;
    while (i < len) {
        uart_putchar(ptr[i]);
        i = i + 1;
    }
    return len;
}

/* ---------------------------------------------------------------------------
 * sys_read: lê até 'len' bytes da UART para ptr
 * Retorna: número de bytes lidos
 * --------------------------------------------------------------------------- */
int sys_read(int *ptr, int len) {
    int i;
    int *uart_rx;
    uart_rx = UART_RXDATA;
    i = 0;
    while (i < len) {
        ptr[i] = *uart_rx;
        i = i + 1;
    }
    return len;
}

/* ---------------------------------------------------------------------------
 * sys_exit: encerra o processo atual
 * --------------------------------------------------------------------------- */
void sys_exit(int code) {
    int *entry;
    /* Marcar processo como FREE */
    entry = PROC_TABLE + current_pid * ENTRY_SIZE;
    entry[1] = PROC_FREE;
    /* Mostrar código de saída */
    uart_putchar('X');
    uart_putchar('=');
    uart_puthex(code);
    uart_putchar('\n');
    /* Forçar reschedule via yield */
    sys_yield();
}

/* ---------------------------------------------------------------------------
 * sys_yield: cede CPU voluntariamente (simula interrupção de timer)
 * --------------------------------------------------------------------------- */
void sys_yield() {
    /* Em hardware real: SYSCALL + handler de ERET dispara reschedule */
    /* Aqui: marcar como READY e chamar diretamente */
    int *entry;
    entry = PROC_TABLE + current_pid * ENTRY_SIZE;
    entry[1] = PROC_READY;
    current_pid = schedule();
    entry = PROC_TABLE + current_pid * ENTRY_SIZE;
    entry[1] = PROC_RUNNING;
}

/* ---------------------------------------------------------------------------
 * sys_sleep: bloqueia por 'ticks' ticks de timer
 * --------------------------------------------------------------------------- */
void sys_sleep(int ticks) {
    int *tick;
    int  target;
    tick   = TICK_COUNTER;
    target = *tick + ticks;
    while (*tick < target) {
        sys_yield();
    }
}

/* ---------------------------------------------------------------------------
 * syscall_handler: despacha para a syscall correta
 * Chamado pelo handler de exceção SYSCALL (cause=3)
 * Parâmetros passados como argumentos (do contexto salvo pelo handler asm)
 * --------------------------------------------------------------------------- */
int syscall_handler(int num, int a1, int a2, int a3, int a4) {
    int result;
    result = 0;

    if (num == SYS_EXIT) {
        sys_exit(a1);
    } else if (num == SYS_WRITE) {
        result = sys_write(a1, a2);
    } else if (num == SYS_READ) {
        result = sys_read(a1, a2);
    } else if (num == SYS_MALLOC) {
        result = kmalloc(a1);
    } else if (num == SYS_FREE) {
        kfree(a1);
        result = 0;
    } else if (num == SYS_YIELD) {
        sys_yield();
    } else if (num == SYS_GETPID) {
        result = current_pid;
    } else if (num == SYS_SLEEP) {
        sys_sleep(a1);
    } else if (num == SYS_HEAPSTAT) {
        heap_stats(a1, a2);
    } else if (num == SYS_UPTIME) {
        int *tick;
        tick   = TICK_COUNTER;
        result = *tick;
    } else {
        /* Syscall inválida — retornar -1 */
        result = -1;
    }

    return result;
}
