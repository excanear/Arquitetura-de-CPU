/*
 * trap_handler.c — Hypervisor Trap and Interrupt Dispatcher
 *
 * All synchronous exceptions (illegal instruction, page fault, syscall,
 * BREAK) and asynchronous interrupts (timer, external IRQ) are routed
 * here after the hardware IVT assembly stubs save the GPR state.
 *
 * Dispatch policy:
 *  ┌─────────────────────────────────────────────────────────────────┐
 *  │ TRAP_TIMER        → preempt current VM, schedule next           │
 *  │ TRAP_SYSCALL      → inspect syscall #:                          │
 *  │                     ≥ 0x80 → handle as hypercall (HV-native)    │
 *  │                     <  0x80 → inject into guest OS IVT          │
 *  │ TRAP_PAGE_FAULT   → try SPT translation; inject if unresolvable │
 *  │ TRAP_ILLEGAL_INSTR→ attempt privileged-instr emulation;         │
 *  │                      inject into guest if not emulable          │
 *  │ TRAP_DIV_ZERO /   → inject into guest fault handler             │
 *  │ TRAP_OVERFLOW /   │                                             │
 *  │ TRAP_MISALIGNED   │                                             │
 *  │ TRAP_BREAK        → handle as hypercall debugging hook          │
 *  └─────────────────────────────────────────────────────────────────┘
 */

#include "hypervisor.h"

extern hv_state_t g_hv;

/* ─── Minimal UART for diagnostic output ──────── */
#define UART_DR     (*((volatile uint32_t *)0x40000000u))
#define UART_STAT   (*((volatile uint32_t *)0x40000004u))
#define UART_TXRDY  (UART_STAT & 0x01u)

static void tp_putchar(char c)   { while (!UART_TXRDY) {} UART_DR = (uint32_t)(uint8_t)c; }
static void tp_puts(const char *s) { while (*s) tp_putchar(*s++); tp_putchar('\n'); }
static void tp_puthex(uint32_t v)
{
    int i; tp_putchar('0'); tp_putchar('x');
    for (i = 28; i >= 0; i -= 4) {
        uint8_t n = (v >> i) & 0xFu;
        tp_putchar(n < 10u ? (char)('0' + n) : (char)('A' + n - 10u));
    }
}
static void tp_putdec(uint8_t v) { tp_putchar((char)('0' + v / 10)); tp_putchar((char)('0' + v % 10)); }

/* ═══════════════════════════════════════════════════════════════════
 *  trap_inject_to_guest() — deliver a trap into the guest OS
 *
 *  Sets up the guest's CSR state so that when vcpu_run() issues ERET,
 *  execution jumps to the guest's own IVT handler for this cause code.
 *  This is how the HV forwards faults/exceptions that belong to the OS.
 * ═══════════════════════════════════════════════════════════════════ */
static void trap_inject_to_guest(uint8_t vm_id, uint32_t cause, uint32_t epc)
{
    vcpu_state_t *vcpu = &g_hv.vms[vm_id].vcpu;

    /* Save faulting instruction address for guest ERET */
    vcpu->epc   = epc;
    vcpu->cause = cause;

    /* Redirect guest PC to its IVT slot for this cause
     * (guest IVT format: 4-byte slots, each a JMP to handler) */
    vcpu->pc = vcpu->ivt + (cause * 4u);

    /* Disable interrupts inside the guest during its fault handling */
    vcpu->status &= ~0x0001u;
}

/* ═══════════════════════════════════════════════════════════════════
 *  trap_handle() — main dispatcher, called by IVT assembly stubs
 *
 *  Parameters are read from CSRs by the caller before the C call:
 *    cause    — CSR_CAUSE value (trap/interrupt source)
 *    epc      — CSR_EPC  value (faulting instruction address)
 *    badvaddr — faulting virtual address (only meaningful for page faults)
 * ═══════════════════════════════════════════════════════════════════ */
void trap_handle(uint32_t cause, uint32_t epc, uint32_t badvaddr)
{
    uint8_t cur = g_hv.current_vm;

    g_hv.vms[cur].total_traps++;

    switch (cause) {

    /* ── Asynchronous: Timer interrupt ──────────────────────────── */
    case TRAP_TIMER:
        trap_timer();
        /* trap_timer() calls vm_schedule_next() → hv_main() → vcpu_run()
         * and never returns here. */
        break;

    /* ── Synchronous: SYSCALL / hypercall ───────────────────────── */
    case TRAP_SYSCALL:
        trap_syscall(cur, epc);
        break;

    /* ── Synchronous: MMU page fault ────────────────────────────── */
    case TRAP_PAGE_FAULT:
        trap_page_fault(cur, badvaddr, epc);
        break;

    /* ── Synchronous: Illegal instruction ───────────────────────── */
    case TRAP_ILLEGAL_INSTR:
        trap_illegal_instr(cur, epc);
        break;

    /* ── Synchronous: BREAK (debug / hypercall hook) ────────────── */
    case TRAP_BREAK:
        tp_puts("[HV] BREAK/hypercall in VM");
        tp_putdec(cur);
        /* Advance EPC past the BREAK instruction (+4 bytes) and resume */
        g_hv.vms[cur].vcpu.pc = epc + 4u;
        vcpu_run(cur);
        break;

    /* ── Synchronous: Arithmetic faults — inject to guest ──────── */
    case TRAP_DIV_ZERO:
    case TRAP_OVERFLOW:
    case TRAP_MISALIGNED:
        trap_inject_to_guest(cur, cause, epc);
        vcpu_run(cur);
        break;

    /* ── External IRQ (causes 0x20..0x27) ───────────────────────── */
    default:
        if (cause >= TRAP_EXT_IRQ_BASE && cause < (TRAP_EXT_IRQ_BASE + 8u)) {
            /* Forward external interrupt to the currently-running VM */
            trap_inject_to_guest(cur, cause, epc);
            vcpu_run(cur);
        } else {
            /* Unknown cause: log and forward to guest */
            tp_puts("[HV] Unknown trap cause: ");
            tp_puthex(cause);
            tp_puts(" in VM");
            tp_putdec(cur);
            trap_inject_to_guest(cur, cause, epc);
            vcpu_run(cur);
        }
        break;
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  trap_timer() — preemptive scheduling on timer interrupt
 * ═══════════════════════════════════════════════════════════════════ */
void trap_timer(void)
{
    uint32_t next_cmp;

    g_hv.tick_counter++;
    g_hv.vms[g_hv.current_vm].total_ticks++;

    /* Reprogram the hardware timer for the next quantum */
    __asm__ volatile ("CSRR %0, time" : "=r"(next_cmp));
    next_cmp += (uint32_t)HV_TICK_INTERVAL;
    __asm__ volatile ("CSRW timecmp, %0" : : "r"(next_cmp));

    /* Context switch: save current VM state, pick next VM */
    vm_schedule_next();   /* → hv_main() → vcpu_run() — never returns */
}

/* ═══════════════════════════════════════════════════════════════════
 *  trap_syscall() — handle SYSCALL instruction from a guest
 *
 *  R1 = syscall number (ABI convention: first argument register).
 *  Numbers ≥ 0x80 are hypervisor-native hypercalls.
 *  Numbers  < 0x80 are OS-level syscalls forwarded to the guest kernel.
 * ═══════════════════════════════════════════════════════════════════ */
void trap_syscall(uint8_t vm_id, uint32_t epc)
{
    vcpu_state_t *vcpu = &g_hv.vms[vm_id].vcpu;
    uint32_t      call = vcpu->regs[1];   /* R1 = syscall / hypercall number */

    if (call >= 0x80u) {
        /* ── Hypervisor-native hypercall ────────────────────────── */
        switch (call) {

        case HV_CALL_VERSION:
            /* Return hypervisor version in R1 */
            vcpu->regs[1] = (uint32_t)HV_VERSION;
            vcpu->pc = epc + 4u;
            vcpu_run(vm_id);
            break;

        case HV_CALL_VM_ID:
            /* Return the calling VM's ID in R1 */
            vcpu->regs[1] = (uint32_t)vm_id;
            vcpu->pc = epc + 4u;
            vcpu_run(vm_id);
            break;

        case HV_CALL_VM_YIELD:
            /* Voluntarily yield the CPU to the next VM */
            g_hv.vms[vm_id].vcpu.pc = epc + 4u;
            vm_schedule_next();         /* Never returns */
            break;

        case HV_CALL_VM_EXIT:
            /* Terminate this VM (R2 = exit code) */
            g_hv.vms[vm_id].exit_code = (int32_t)vcpu->regs[2];
            g_hv.vms[vm_id].state     = VM_STATE_HALTED;
            tp_puts("[HV] VM halted via HV_CALL_VM_EXIT: ");
            tp_putdec(vm_id);
            vm_schedule_next();         /* Never returns */
            break;

        case HV_CALL_CONSOLE_PUT:
            /* Write one character (R2) to the HV console */
            tp_putchar((char)(vcpu->regs[2] & 0xFFu));
            vcpu->regs[1] = 0u;
            vcpu->pc = epc + 4u;
            vcpu_run(vm_id);
            break;

        default:
            /* Unknown hypercall: return -1 in R1, resume */
            vcpu->regs[1] = (uint32_t)(-1);
            vcpu->pc = epc + 4u;
            vcpu_run(vm_id);
            break;
        }
        return; /* Unreachable, but for clarity */
    }

    /* ── Guest OS-level syscall: forward to guest kernel handler ── */
    trap_inject_to_guest(vm_id, TRAP_SYSCALL, epc);
    vcpu_run(vm_id);
}

/* ═══════════════════════════════════════════════════════════════════
 *  trap_page_fault() — handle a guest page fault
 *
 *  1. Attempt to resolve via the hypervisor shadow page table.
 *  2. If translation succeeds (TLB miss → HPA known): retry the instruction.
 *  3. If translation fails: inject the page fault into the guest OS so
 *     its page table walker (PTW) can handle it (demand paging, CoW, etc.).
 * ═══════════════════════════════════════════════════════════════════ */
void trap_page_fault(uint8_t vm_id, uint32_t fault_gpa, uint32_t epc)
{
    uint32_t hpa;

    if (vm_translate(vm_id, fault_gpa, &hpa) == 0) {
        /* Mapping present — likely a TLB miss resolved by SPT.
         * Retry the faulting instruction (PC unchanged). */
        g_hv.vms[vm_id].vcpu.pc = epc;
        vcpu_run(vm_id);
        return;
    }

    /* No valid mapping — let the guest OS handle it */
    tp_puts("[HV] PAGE FAULT: VM ");
    tp_putdec(vm_id);
    tp_puts(" at GPA ");
    tp_puthex(fault_gpa);

    trap_inject_to_guest(vm_id, TRAP_PAGE_FAULT, epc);
    vcpu_run(vm_id);
}

/* ═══════════════════════════════════════════════════════════════════
 *  trap_illegal_instr() — handle an illegal / privileged instruction
 *
 *  The HV can choose to emulate certain privileged operations (e.g.,
 *  a guest trying to read/write an HV-managed CSR) and return results
 *  transparently.  Unrecognized instructions are injected as faults.
 * ═══════════════════════════════════════════════════════════════════ */
void trap_illegal_instr(uint8_t vm_id, uint32_t epc)
{
    /* Fetch the faulting instruction from guest memory for inspection */
    uint32_t hpa;
    uint32_t instr = 0u;

    if (vm_translate(vm_id, epc, &hpa) == 0) {
        instr = *((volatile uint32_t *)hpa);
    }

    /* Detect CSRR/CSRW targeting time/cycle counters and emulate them.
     * Opcode pattern for CSRR: bits[6:0] = 7'b1110011 (EduRISC-32v2 CSR op)
     * This is a simplified check; a full decoder would handle all CSRs. */
    if ((instr & 0x7Fu) == 0x73u) {
        /* CSR instruction: emulate by returning 0 and advancing PC */
        g_hv.vms[vm_id].vcpu.regs[(instr >> 7u) & 0x1Fu] = 0u;
        g_hv.vms[vm_id].vcpu.pc = epc + 4u;
        vcpu_run(vm_id);
        return;
    }

    /* Not emulable — inject SIGILL equivalent into guest OS */
    tp_puts("[HV] ILLEGAL INSTR: VM ");
    tp_putdec(vm_id);
    tp_puts(" instr=");
    tp_puthex(instr);
    tp_puts(" epc=");
    tp_puthex(epc);

    trap_inject_to_guest(vm_id, TRAP_ILLEGAL_INSTR, epc);
    vcpu_run(vm_id);
}
