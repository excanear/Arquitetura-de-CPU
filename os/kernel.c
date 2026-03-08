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

/* ---------------------------------------------------------------------------
 * Constantes do sistema
 * --------------------------------------------------------------------------- */
#define MAX_PROCS       8
#define STACK_SIZE      256        /* words por processo */
#define DMEM_BASE       0x0000
#define STACK_TOP       0xFFFF
#define UART_TXDATA     0xFF00     /* endereço do registrador UART TX */
#define TIMER_CMP_ADDR  0xFF10     /* endereço do comparador do timer */
#define TIMER_QUANTUM   10000      /* ciclos por quantum de tempo */

/* Endereços fixos em DMEM */
#define TICK_COUNTER    0x0FF0
#define PROC_TABLE      0x1000     /* início da tabela de processos */

/* ---------------------------------------------------------------------------
 * Tipos básicos
 * --------------------------------------------------------------------------- */
#define NULL  0
#define TRUE  1
#define FALSE 0

/* ---------------------------------------------------------------------------
 * Tabela de processos (armazenada em DMEM a partir de PROC_TABLE)
 * Cada entrada: [0]=pid [1]=estado [2]=pc_saved [3]=sp_saved [4..15]=regs
 * --------------------------------------------------------------------------- */
#define PROC_FREE    0
#define PROC_READY   1
#define PROC_RUNNING 2
#define PROC_BLOCKED 3

#define ENTRY_SIZE   16    /* words por entrada na tabela */

/* Variável global: índice do processo atual */
int current_pid;
int num_procs;

/* ---------------------------------------------------------------------------
 * uart_putchar: envia um caractere pela UART
 * --------------------------------------------------------------------------- */
void uart_putchar(int c) {
    int *uart;
    uart = UART_TXDATA;
    *uart = c;
}

/* ---------------------------------------------------------------------------
 * uart_puts: envia uma string (terminada em 0)
 * --------------------------------------------------------------------------- */
void uart_puts(int *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        uart_putchar(s[i]);
        i = i + 1;
    }
}

/* ---------------------------------------------------------------------------
 * uart_puthex: envia um número em hexadecimal (8 dígitos)
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
 * proc_alloc: aloca uma entrada livre na tabela de processos
 * Retorna: pid alocado, ou -1 se tabela cheia
 * --------------------------------------------------------------------------- */
int proc_alloc() {
    int i;
    int *entry;
    i = 0;
    while (i < MAX_PROCS) {
        entry = PROC_TABLE + i * ENTRY_SIZE;
        if (*entry == PROC_FREE) {
            *entry = PROC_READY;
            return i;
        }
        i = i + 1;
    }
    return -1;
}

/* ---------------------------------------------------------------------------
 * proc_create: cria um novo processo
 * entry_point: endereço de início do processo
 * --------------------------------------------------------------------------- */
int proc_create(int entry_point) {
    int pid;
    int *entry;
    pid = proc_alloc();
    if (pid < 0) {
        return -1;
    }
    entry = PROC_TABLE + pid * ENTRY_SIZE;
    entry[0] = pid;              /* pid */
    entry[1] = PROC_READY;      /* estado */
    entry[2] = entry_point;     /* PC inicial */
    /* SP inicial: topo da pilha deste processo */
    entry[3] = STACK_TOP - pid * STACK_SIZE;
    num_procs = num_procs + 1;
    return pid;
}

/* ---------------------------------------------------------------------------
 * schedule: seleciona o próximo processo pronto (round-robin)
 * --------------------------------------------------------------------------- */
int schedule() {
    int i;
    int next;
    int *entry;
    i = (current_pid + 1) & 7;   /* módulo MAX_PROCS */
    next = -1;
    while (i != current_pid) {
        entry = PROC_TABLE + i * ENTRY_SIZE;
        if (entry[1] == PROC_READY) {
            next = i;
            i = current_pid;    /* break */
        } else {
            i = (i + 1) & 7;
        }
    }
    if (next < 0) {
        next = current_pid;     /* manter se ninguém pronto */
    }
    return next;
}

/* ---------------------------------------------------------------------------
 * idle_task: processo ocioso (loop infinito de NOP)
 * --------------------------------------------------------------------------- */
void idle_task() {
    while (TRUE) {
        /* NOP — espera próxima interrupção de timer */
    }
}

/* ---------------------------------------------------------------------------
 * kernel_main: ponto de entrada do kernel (chamado pelo bootloader)
 * --------------------------------------------------------------------------- */
void kernel_main() {
    int *timer_cmp;

    /* Inicializar variáveis globais */
    current_pid = 0;
    num_procs   = 0;

    /* Exibir mensagem de boot */
    uart_puts("EduRISC-32v2 Kernel\n");
    uart_puts("Inicializando...\n");

    /* Inicializar tabela de processos */
    memory_init();

    /* Configurar timer para quantum de preempção */
    timer_cmp  = TIMER_CMP_ADDR;
    *timer_cmp = TIMER_QUANTUM;

    /* Criar processo idle (PID 0) */
    proc_create(idle_task);

    /* Criar processo de demonstração (PID 1) */
    proc_create(demo_process);

    uart_puts("Kernel pronto. Processos iniciados.\n");

    /* Loop principal do kernel: esperar interrupções */
    while (TRUE) {
        /* O timer irá preemptar e chamar schedule() */
    }
}
