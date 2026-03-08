/*
 * process.c — Process Control Block Management
 *
 * Provides process creation, termination, and PCB lookup on top of
 * the EduRISC-32v2 kernel.  Works in concert with:
 *   scheduler.c  — decides which READY process runs next
 *   memory.c     — provides kmalloc/kfree for stack allocation
 *   syscalls.c   — SYS_EXIT calls process_exit()
 *   interrupts.c — timer IRQ triggers scheduler_tick() which reads PCBs
 *
 * Process lifecycle:
 *   process_create()  → PROC_READY    ← scheduler_add() informed
 *   context switch    → PROC_RUNNING  ← scheduler makes it current
 *   process_block()   → PROC_BLOCKED  ← waiting for I/O / semaphore
 *   process_unblock() → PROC_READY    ← event fired, back in queue
 *   process_exit()    → PROC_ZOMBIE   ← resources held until waited
 *   process_wait()    → PROC_FREE     ← parent reaps, stack freed
 */

#include <stdint.h>
#include <stddef.h>

/* ─── Configuration ──────────────────────────── */
#define MAX_PROCESSES   8u
#define STACK_SIZE      1024u       /* bytes per kernel stack                */
#define PROC_NAME_LEN   16u

/* ─── Process states ─────────────────────────── */
#define PROC_FREE       0u
#define PROC_READY      1u
#define PROC_RUNNING    2u
#define PROC_BLOCKED    3u
#define PROC_ZOMBIE     4u

/* ─── Process Control Block ──────────────────── */
typedef struct pcb {
    uint8_t   pid;              /* Unique process ID (0 = idle)              */
    uint8_t   state;            /* PROC_* constant                           */
    uint8_t   parent_pid;       /* PID of creating process                   */
    uint8_t   priority;         /* 0 = highest priority, 255 = lowest        */

    /* Saved CPU context (written / read by context_switch in scheduler.c)   */
    uint32_t  regs[32];         /* R0..R31 general-purpose registers         */
    uint32_t  pc;               /* Program counter                           */
    uint32_t  sp;               /* Stack pointer (= regs[30])                */
    uint32_t  status_csr;       /* CSR_STATUS at last switch-out             */

    /* Memory */
    uint32_t  stack_base;       /* Low address (kmalloc'd)                   */
    uint32_t  stack_size;       /* Stack allocation in bytes                 */
    uint32_t  heap_ptr;         /* Top of brk heap (grow upward)             */

    /* Statistics */
    uint64_t  ticks;            /* Total CPU timer ticks consumed            */
    uint32_t  voluntary_yields; /* Times the process yielded voluntarily     */

    /* Exit status */
    int32_t   exit_code;
    char      name[PROC_NAME_LEN];
} pcb_t;

/* ─── External linkage ───────────────────────── */
extern void *kmalloc(uint32_t size);
extern void  kfree(void *ptr);
extern void  scheduler_add(pcb_t *proc);
extern void  scheduler_remove(uint8_t pid);
extern pcb_t *scheduler_current(void);

/* ─── Module state ───────────────────────────── */
static pcb_t  s_table[MAX_PROCESSES];
static uint8_t s_next_pid = 1u;   /* PID 0 reserved for idle              */
static uint8_t s_count    = 0u;

/* ─── Internal helpers ───────────────────────── */
static void mem_zero(void *p, uint32_t n)
{
    uint8_t *b = (uint8_t *)p;
    uint32_t i;
    for (i = 0; i < n; i++) b[i] = 0;
}

static void str_copy(char *dst, const char *src, uint32_t max)
{
    uint32_t i;
    for (i = 0; i + 1u < max && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_init() — set up process subsystem + idle process (PID 0)
 * ═══════════════════════════════════════════════════════════════════ */
void process_init(void)
{
    uint32_t i;
    pcb_t   *idle;

    for (i = 0; i < MAX_PROCESSES; i++)
        s_table[i].state = PROC_FREE;

    /* PID 0: kernel idle process — runs when no other process is READY */
    idle            = &s_table[0];
    idle->pid       = 0u;
    idle->state     = PROC_READY;
    idle->priority  = 255u;   /* Lowest: only runs if nothing else can       */
    idle->stack_base = 0u;    /* Runs on the boot stack, never swapped out   */
    str_copy(idle->name, "idle", PROC_NAME_LEN);

    s_count = 1u;
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_create() — fork a new runnable process
 *
 *  entry_pc  — address of the function the process will start in
 *  priority  — scheduling priority (0 = highest)
 *  name      — label (truncated to 15 characters)
 *
 *  Returns the new PID (≥ 1) or a negative error code.
 * ═══════════════════════════════════════════════════════════════════ */
int process_create(uint32_t entry_pc, uint8_t priority, const char *name)
{
    uint8_t   slot;
    pcb_t    *proc;
    uint32_t  stack;
    uint32_t  i;

    /* Guard: PID 0 and table slots 1..MAX_PROCESSES-1 */
    if (s_count >= MAX_PROCESSES) return -1;

    /* Find a free slot (skip slot 0 = idle) */
    for (slot = 1u; slot < MAX_PROCESSES; slot++) {
        if (s_table[slot].state == PROC_FREE) break;
    }
    if (slot == MAX_PROCESSES) return -2;

    /* Allocate stack from kernel heap */
    stack = (uint32_t)kmalloc(STACK_SIZE);
    if (!stack) return -3;

    proc = &s_table[slot];
    mem_zero(proc, sizeof(pcb_t));

    proc->pid        = s_next_pid++;
    proc->state      = PROC_READY;
    proc->parent_pid = scheduler_current() ? scheduler_current()->pid : 0u;
    proc->priority   = priority;
    proc->pc         = entry_pc;
    proc->stack_base = stack;
    proc->stack_size = STACK_SIZE;
    proc->sp         = stack + STACK_SIZE - 4u;  /* Stack grows downward    */
    proc->status_csr = 0x0001u;                  /* IE=1 at first dispatch   */
    proc->exit_code  = 0;
    proc->heap_ptr   = 0u;

    /* Set up initial register file */
    for (i = 0u; i < 32u; i++) proc->regs[i] = 0u;
    proc->regs[30] = proc->sp;           /* R30 = SP                        */
    proc->regs[31] = entry_pc;           /* R31 = LR (return addr = entry)  */

    str_copy(proc->name, name ? name : "proc", PROC_NAME_LEN);

    s_count++;
    scheduler_add(proc);

    return (int)proc->pid;
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_exit() — terminate the calling process
 *
 *  Marks the current process PROC_ZOMBIE so the parent can wait().
 *  Issues a yield so the scheduler immediately picks the next process.
 *  The stack is freed by process_wait() to avoid use-after-free.
 * ═══════════════════════════════════════════════════════════════════ */
void process_exit(int exit_code)
{
    pcb_t   *self = scheduler_current();
    if (!self || self->pid == 0u) return;  /* idle never exits */

    global_irq_disable();
    self->state     = PROC_ZOMBIE;
    self->exit_code = exit_code;
    scheduler_remove(self->pid);
    global_irq_enable();

    /* Yield CPU — context switch to next READY process */
    __asm__ volatile ("SYSCALL");   /* SYS_YIELD handled by syscalls.c      */
    __builtin_unreachable();
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_block() — move process to BLOCKED state (waiting for event)
 * ═══════════════════════════════════════════════════════════════════ */
void process_block(uint8_t pid)
{
    uint32_t i;
    for (i = 0; i < MAX_PROCESSES; i++) {
        if (s_table[i].pid == pid && s_table[i].state == PROC_RUNNING) {
            s_table[i].state = PROC_BLOCKED;
            scheduler_remove(pid);
            return;
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_unblock() — move process from BLOCKED back to READY
 * ═══════════════════════════════════════════════════════════════════ */
void process_unblock(uint8_t pid)
{
    uint32_t i;
    for (i = 0; i < MAX_PROCESSES; i++) {
        if (s_table[i].pid == pid && s_table[i].state == PROC_BLOCKED) {
            s_table[i].state = PROC_READY;
            scheduler_add(&s_table[i]);
            return;
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_wait() — reap a zombie child and release its stack
 *
 *  Returns 0 on success, -1 if child not in ZOMBIE state,
 *  -2 if PID not found.
 * ═══════════════════════════════════════════════════════════════════ */
int process_wait(uint8_t pid, int *exit_code_out)
{
    uint32_t i;
    for (i = 0; i < MAX_PROCESSES; i++) {
        if (s_table[i].pid != pid) continue;
        if (s_table[i].state != PROC_ZOMBIE) return -1;

        if (exit_code_out)
            *exit_code_out = s_table[i].exit_code;

        /* Free the process stack */
        if (s_table[i].stack_base)
            kfree((void *)s_table[i].stack_base);

        s_table[i].state = PROC_FREE;
        s_count--;
        return 0;
    }
    return -2;
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_get() — look up a PCB by PID
 * ═══════════════════════════════════════════════════════════════════ */
pcb_t *process_get(uint8_t pid)
{
    uint32_t i;
    for (i = 0; i < MAX_PROCESSES; i++) {
        if (s_table[i].pid == pid && s_table[i].state != PROC_FREE)
            return &s_table[i];
    }
    return (pcb_t *)0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  process_count() — number of live (non-FREE) processes
 * ═══════════════════════════════════════════════════════════════════ */
uint8_t process_count(void) { return s_count; }

/* Expose global_irq helpers for use within this file */
static inline void global_irq_disable(void) {
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0000u));
}
static inline void global_irq_enable(void) {
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0001u));
}
