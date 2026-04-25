/* ============================================================================
 * scheduler.c  —  Escalonador Round-Robin EduRISC-32v2
 *
 * Funções exportadas:
 *   scheduler_tick()   — chamada pelo ISR do timer (a cada TIMER_QUANTUM ciclos)
 *   context_save()     — salva contexto do processo (chamada pelo assembly ISR)
 *   context_restore_pc() / context_restore_sp() — restauração de contexto
 *   demo_process()     — processo de demonstração
 * ============================================================================ */

#include "os_defs.h"

/* ---------------------------------------------------------------------------
 * context_save: salva os regs do processo atual na tabela de processos
 *
 * Chamada pelo assembly do ISR do timer antes de chamar scheduler_tick().
 * A tabela de processos começa em PROC_TABLE; cada entrada ocupa ENTRY_SIZE words.
 *
 * Validação: se cur_pid estiver fora de [0, MAX_PROCS), a função retorna
 * imediatamente sem acessar memória inválida.
 * --------------------------------------------------------------------------- */
void context_save(int pid, int saved_pc, int saved_sp,
                  int r1,  int r2,  int r3,  int r4,
                  int r5,  int r6,  int r7,  int r8,
                  int r9,  int r10, int r11, int r12) {
    int *entry;

    /* Verificação de limites: evita escrita em memória arbitrária */
    if (pid < 0 || pid >= MAX_PROCS) {
        return;
    }

    entry = (int *)(PROC_TABLE + pid * ENTRY_SIZE);
    entry[FIELD_PC]  = saved_pc;
    entry[FIELD_SP]  = saved_sp;
    entry[FIELD_R1]  = r1;
    entry[5]         = r2;
    entry[6]         = r3;
    entry[7]         = r4;
    entry[8]         = r5;
    entry[9]         = r6;
    entry[10]        = r7;
    entry[11]        = r8;
    entry[12]        = r9;
    entry[13]        = r10;
    entry[14]        = r11;
    entry[15]        = r12;
}

/* ---------------------------------------------------------------------------
 * context_restore_pc: retorna o PC salvo do processo pid
 *
 * Retorna 0 se pid for inválido (proteção contra leitura fora dos limites).
 * --------------------------------------------------------------------------- */
int context_restore_pc(int pid) {
    int *entry;
    if (pid < 0 || pid >= MAX_PROCS) {
        return 0;
    }
    entry = (int *)(PROC_TABLE + pid * ENTRY_SIZE);
    return entry[FIELD_PC];
}

/* ---------------------------------------------------------------------------
 * context_restore_sp: retorna o SP salvo do processo pid
 *
 * Retorna STACK_TOP se pid for inválido (garante SP válido para o hardware).
 * --------------------------------------------------------------------------- */
int context_restore_sp(int pid) {
    int *entry;
    if (pid < 0 || pid >= MAX_PROCS) {
        return STACK_TOP;
    }
    entry = (int *)(PROC_TABLE + pid * ENTRY_SIZE);
    return entry[FIELD_SP];
}

/* ---------------------------------------------------------------------------
 * scheduler_tick: chamado a cada interrupção de timer
 *
 *   1. Valida cur_pid (limites da tabela de processos).
 *   2. Marca processo atual como READY se estava RUNNING.
 *   3. Seleciona próximo processo com schedule() (definido em kernel.c).
 *   4. Marca novo processo como RUNNING.
 *   5. Retorna novo PID para que o assembly ISR carregue o contexto correto.
 * --------------------------------------------------------------------------- */
int scheduler_tick(int cur_pid) {
    int *cur_entry;
    int  next_pid;
    int *next_entry;

    /* ── Verificação de limites: PID inválido → forçar PID 0 (idle) ── */
    if (cur_pid < 0 || cur_pid >= MAX_PROCS) {
        cur_pid = PID_IDLE;
    }

    cur_entry = (int *)(PROC_TABLE + cur_pid * ENTRY_SIZE);
    if (cur_entry[FIELD_STATE] == PROC_RUNNING) {
        cur_entry[FIELD_STATE] = PROC_READY;
    }

    /* schedule() é definida em kernel.c — implementa round-robin */
    next_pid = schedule();

    /* Verificação de limites para o PID retornado por schedule() */
    if (next_pid < 0 || next_pid >= MAX_PROCS) {
        next_pid = PID_IDLE;
    }

    next_entry = (int *)(PROC_TABLE + next_pid * ENTRY_SIZE);
    next_entry[FIELD_STATE] = PROC_RUNNING;

    return next_pid;
}

/* ---------------------------------------------------------------------------
 * demo_process: processo de demonstração
 *
 *   Calcula a soma 1+2+…+10 = 55 e envia o resultado pela UART.
 *   Após completar, marca a própria entrada na tabela como PROC_FREE
 *   e entra em loop infinito até o próximo scheduler_tick() removê-lo.
 * --------------------------------------------------------------------------- */
void demo_process() {
    int  sum;
    int  i;
    int *entry;

    sum = 0;
    i   = 1;
    while (i <= 10) {
        sum = sum + i;
        i   = i + 1;
    }

    /* Envia "S=0x00000037\n" pela UART (55 = 0x37) */
    uart_putchar('S');
    uart_putchar('=');
    uart_puthex(sum);
    uart_putchar('\n');

    /* Marca este processo (PID 1) como PROC_FREE para liberar a entrada */
    entry = (int *)(PROC_TABLE + 1 * ENTRY_SIZE);
    entry[FIELD_STATE] = PROC_FREE;

    /* Loop de espera — o escalonador não voltará a ativar este PID */
    while (1) { }
}
