/*
 * hv_core.c — EduRISC-32v2 Hypervisor Core
 *
 * Entry point and main scheduling loop for the bare-metal Type-1 hypervisor.
 * Called by the bootloader right after hardware initialization — before any
 * guest OS image is loaded or executed.
 *
 * Execution flow:
 *   bootloader_main()
 *     → hv_init()          – install IVT, configure timer, zero state
 *     → vm_create(...)     – register one or more guest VMs
 *     → vm_start(vm_id)    – mark VMs as READY
 *     → hv_main()          – enter the scheduling loop (never returns)
 *
 * Scheduling policy: cooperative + preemptive round-robin.
 *   • VMs can voluntarily yield via the HV_CALL_VM_YIELD hypercall.
 *   • The timer fires every HV_TICK_INTERVAL cycles and forces a switch.
 */

#include "hypervisor.h"

/* ═══════════════════════════════════════════════════════════════════
 *  Global hypervisor state (one instance, lives in BSS)
 * ═══════════════════════════════════════════════════════════════════ */
hv_state_t g_hv;

/* ═══════════════════════════════════════════════════════════════════
 *  MMIO helpers — minimal UART console for HV diagnostics
 * ═══════════════════════════════════════════════════════════════════ */
#define UART_DR     (*((volatile uint32_t *)0x40000000u))
#define UART_STAT   (*((volatile uint32_t *)0x40000004u))
#define UART_TXRDY  (UART_STAT & 0x01u)

static void hv_putchar(char c)
{
    while (!UART_TXRDY) {}
    UART_DR = (uint32_t)(uint8_t)c;
}

static void hv_puts(const char *s)
{
    while (*s) hv_putchar(*s++);
    hv_putchar('\r');
    hv_putchar('\n');
}

static void hv_puthex(uint32_t v)
{
    int i;
    hv_putchar('0'); hv_putchar('x');
    for (i = 28; i >= 0; i -= 4) {
        uint8_t nib = (v >> i) & 0xFu;
        hv_putchar(nib < 10u ? (char)('0' + nib) : (char)('A' + nib - 10u));
    }
}

static void hv_putdec(uint32_t v)
{
    char buf[11];
    int  i = 10;
    buf[i] = '\0';
    if (v == 0) { hv_putchar('0'); return; }
    while (v && i > 0) { buf[--i] = (char)('0' + v % 10); v /= 10; }
    while (buf[i]) hv_putchar(buf[i++]);
}

/* ═══════════════════════════════════════════════════════════════════
 *  Round-robin scheduler state
 * ═══════════════════════════════════════════════════════════════════ */
static uint8_t s_rr_next = 0;   /* Next VM index to consider in round-robin  */

/*
 * hv_pick_next_vm() — find the next runnable VM using round-robin.
 * Returns VM ID (0-3) or -1 if no VM is runnable.
 */
static int hv_pick_next_vm(void)
{
    uint8_t i, candidate;
    for (i = 0; i < HV_MAX_VMS; i++) {
        candidate = (uint8_t)((s_rr_next + i) % HV_MAX_VMS);
        if (g_hv.vms[candidate].state == VM_STATE_READY ||
            g_hv.vms[candidate].state == VM_STATE_RUNNING) {
            s_rr_next = (uint8_t)((candidate + 1u) % HV_MAX_VMS);
            return (int)candidate;
        }
    }
    return -1;
}

/* ═══════════════════════════════════════════════════════════════════
 *  hv_init() — One-time hypervisor initialization
 * ═══════════════════════════════════════════════════════════════════ */
void hv_init(void)
{
    uint32_t i;

    /* Zero out entire HV state */
    for (i = 0; i < sizeof(hv_state_t); i++)
        ((uint8_t *)&g_hv)[i] = 0;

    /* Install the HV's IVT — all traps land in the HV trap stubs first.
     * CSRW ivt, HV_IVT_BASE */
    __asm__ volatile ("CSRW ivt, %0" : : "r"((uint32_t)HV_IVT_BASE));

    /* Disable interrupts at the hypervisor level during setup */
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0000u));

    /* Program timer for first VM quantum */
    __asm__ volatile ("CSRW timecmp, %0" : : "r"((uint32_t)HV_TICK_INTERVAL));

    g_hv.initialized = 1;

    hv_puts("===========================================");
    hv_puts(" EduRISC-32v2 Hypervisor v1.0 — Type 1");
    hv_puts("===========================================");
    hv_puts("[HV] Initialization complete.");
}

/* ═══════════════════════════════════════════════════════════════════
 *  hv_main() — Hypervisor scheduling loop (never returns)
 * ═══════════════════════════════════════════════════════════════════
 *
 * This function is re-entered every time a VM context switch occurs.
 * It is also the target of the tail-call from vm_schedule_next() and
 * vcpu_run() exits.  The call stack depth stays constant.
 */
void hv_main(void)
{
    int next_id;

    hv_puts("[HV] Entering scheduling loop.");

    while (1) {
        /* Disable interrupts while we inspect and modify VM states */
        __asm__ volatile ("CSRW status, %0" : : "r"(0x0000u));

        next_id = hv_pick_next_vm();

        if (next_id < 0) {
            /* No runnable VMs — idle: re-enable IRQs and wait */
            __asm__ volatile ("CSRW status, %0" : : "r"(0x0001u));
            __asm__ volatile ("WFI");   /* Wait-For-Interrupt (power-saving)  */
            continue;
        }

        /* Transition the chosen VM to RUNNING */
        if (g_hv.vms[next_id].state == VM_STATE_READY)
            g_hv.vms[next_id].state = VM_STATE_RUNNING;

        g_hv.vms[next_id].ticks_remaining = g_hv.vms[next_id].quantum
                                          ? g_hv.vms[next_id].quantum
                                          : HV_TICK_INTERVAL;
        g_hv.current_vm = (uint8_t)next_id;
        g_hv.context_switches++;

        /* Re-enable interrupts (timer must fire to preempt the guest) */
        __asm__ volatile ("CSRW status, %0" : : "r"(0x0001u));

        /* Restore guest context and execute until next trap.
         * vcpu_run() issues ERET and never returns — the next return
         * to C code happens through the HV IVT → trap_handle(). */
        hv_puts("[HV] Dispatching VM ");
        hv_putdec((uint32_t)next_id);
        vcpu_run((uint8_t)next_id);

        /* Unreachable — vcpu_run() never returns */
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  hv_panic() — Unrecoverable hypervisor error
 * ═══════════════════════════════════════════════════════════════════ */
void hv_panic(const char *msg)
{
    uint32_t i;

    /* Disable all interrupts immediately */
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0000u));

    hv_puts("\n[HV PANIC] *** UNRECOVERABLE ERROR ***");
    hv_puts(msg);
    hv_puts("[HV PANIC] Context switches: ");
    hv_putdec(g_hv.context_switches);
    hv_puts("[HV PANIC] Active VMs: ");
    hv_putdec((uint32_t)g_hv.vm_count);
    hv_puts("[HV PANIC] Halting all VMs and spinning.");

    /* Halt every VM */
    for (i = 0; i < HV_MAX_VMS; i++) {
        if (g_hv.vms[i].state != VM_STATE_FREE)
            g_hv.vms[i].state = VM_STATE_HALTED;
    }

    /* Spin with LED pattern to visually indicate panic on FPGA */
    {
        volatile uint32_t *gpio_out = (volatile uint32_t *)0x40002004u;
        uint32_t pattern = 0;
        uint32_t delay;
        while (1) {
            *gpio_out = pattern & 0xFu;
            pattern++;
            for (delay = 0; delay < 250000u; delay++)
                __asm__ volatile ("NOP");
        }
    }
}
