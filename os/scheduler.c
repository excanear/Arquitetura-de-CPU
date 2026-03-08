/* ============================================================================
 * scheduler.c  —  Escalonador Round-Robin EduRISC-32v2
 *
 * Funções exportadas:
 *   scheduler_tick()   — chamada pelo ISR do timer (a cada TIMER_QUANTUM ciclos)
 *   context_switch()   — salva/restaura contexto de processo
 *   demo_process()     — processo de demonstração
 * ============================================================================ */

/* Reutiliza constantes de kernel.c */
#define MAX_PROCS    8
#define PROC_FREE    0
#define PROC_READY   1
#define PROC_RUNNING 2
#define PROC_BLOCKED 3

#define PROC_TABLE   0x1000
#define ENTRY_SIZE   16

/* Offset dos campos em cada entrada */
#define FIELD_STATE   1
#define FIELD_PC      2
#define FIELD_SP      3
#define FIELD_R1      4    /* R1..R12 salvos nos slots 4..15 */

/* ---------------------------------------------------------------------------
 * context_save: salva os regs do processo atual na tabela
 * (na prática chamada pela rotina de assembly no handler do timer)
 * --------------------------------------------------------------------------- */
void context_save(int pid, int saved_pc, int saved_sp,
                  int r1,  int r2,  int r3,  int r4,
                  int r5,  int r6,  int r7,  int r8,
                  int r9,  int r10, int r11, int r12) {
    int *entry;
    entry = PROC_TABLE + pid * ENTRY_SIZE;
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
 * --------------------------------------------------------------------------- */
int context_restore_pc(int pid) {
    int *entry;
    entry = PROC_TABLE + pid * ENTRY_SIZE;
    return entry[FIELD_PC];
}

/* ---------------------------------------------------------------------------
 * context_restore_sp: retorna o SP salvo do processo pid
 * --------------------------------------------------------------------------- */
int context_restore_sp(int pid) {
    int *entry;
    entry = PROC_TABLE + pid * ENTRY_SIZE;
    return entry[FIELD_SP];
}

/* ---------------------------------------------------------------------------
 * scheduler_tick: chamado a cada interrupção de timer
 *   1. Marca processo atual como READY
 *   2. Seleciona próximo com schedule()
 *   3. Marca novo como RUNNING
 *   4. Retorna novo PID (assembly usa para carregar contexto)
 * --------------------------------------------------------------------------- */
int scheduler_tick(int cur_pid) {
    int *cur_entry;
    int  next_pid;
    int *next_entry;

    cur_entry = PROC_TABLE + cur_pid * ENTRY_SIZE;
    if (cur_entry[FIELD_STATE] == PROC_RUNNING) {
        cur_entry[FIELD_STATE] = PROC_READY;
    }

    /* schedule() definida em kernel.c */
    next_pid  = schedule();

    next_entry = PROC_TABLE + next_pid * ENTRY_SIZE;
    next_entry[FIELD_STATE] = PROC_RUNNING;

    return next_pid;
}

/* ---------------------------------------------------------------------------
 * demo_process: processo de demonstração
 *   Calcula a soma 1+2+…+10 e exibe via UART
 * --------------------------------------------------------------------------- */
void demo_process() {
    int sum;
    int i;

    sum = 0;
    i   = 1;
    while (i <= 10) {
        sum = sum + i;
        i   = i + 1;
    }

    /* sum == 55 */
    /* uart_puthex(sum) é definida em kernel.c */
    uart_putchar('S');
    uart_putchar('=');
    uart_puthex(sum);
    uart_putchar('\n');

    /* Encerrar processo: marcar como FREE e aguardar reschedule */
    int *entry;
    entry = PROC_TABLE + 1 * ENTRY_SIZE;   /* PID=1 */
    entry[FIELD_STATE] = PROC_FREE;

    while (1) { }    /* não retornar */
}
