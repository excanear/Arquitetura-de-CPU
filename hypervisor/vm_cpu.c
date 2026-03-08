/*
 * vm_cpu.c — vCPU Context Save / Restore
 *
 * Manages saving and restoring the complete CPU state (GPRs + CSRs) when
 * switching between guest VMs.  Also implements the trampoline that issues
 * ERET to start or resume executing a guest.
 *
 * Context switch sequence (hypervisor → guest):
 *   1. vcpu_restore_state(vm_id)  – copy saved GPRs to scratch buffer
 *   2. Restore guest CSRs (EPC ← guest PC, IVT ← guest IVT, …)
 *   3. ERET                       – atomically: jump to EPC, raise privilege
 *
 * Context switch sequence (guest trap → hypervisor):
 *   1. Hardware: save PC → CSR_EPC; set CSR_CAUSE; jump to IVT[cause]
 *   2. IVT stub:  push all GPRs onto a per-VM scratch area
 *   3. C call:    trap_handle(cause, epc, badvaddr)
 *   4. Handler:   calls vcpu_save_state(vm_id) to copy scratch → VM struct
 *   5. Dispatcher decides: resume same VM or call vm_schedule_next()
 *
 * Scratch buffer (s_scratch_regs[]) is a flat 32-word area.  The assembly
 * IVT stubs save all registers here before calling any C function, and the
 * vcpu_run() trampoline reads from here before issuing ERET.
 */

#include "hypervisor.h"

extern hv_state_t g_hv;

/* One 32-word scratch buffer shared among all VMs (only one VM can trap
 * at a time on a single-core machine, so no locking is needed). */
static volatile uint32_t s_scratch_regs[32];

/* ═══════════════════════════════════════════════════════════════════
 *  vcpu_init() — set up initial vCPU register state
 * ═══════════════════════════════════════════════════════════════════ */
void vcpu_init(vcpu_state_t *vcpu, uint32_t entry_pc, uint32_t sp)
{
    uint32_t i;

    for (i = 0; i < 32u; i++) vcpu->regs[i] = 0u;

    /* EduRISC-32v2 calling convention */
    vcpu->regs[0]  = 0u;           /* R0 = zero (hardware-wired, never written)*/
    vcpu->regs[30] = sp;           /* R30 = SP (stack pointer)                 */
    vcpu->regs[31] = entry_pc;     /* R31 = LR (link register; entry caller)   */

    vcpu->pc       = entry_pc;
    vcpu->status   = 0x0001u;      /* IE=1: guest starts with interrupts on    */
    vcpu->epc      = 0u;
    vcpu->cause    = 0u;
    vcpu->ivt      = entry_pc + 0x100u;  /* Guest IVT just above its code      */
    vcpu->ptbase   = 0u;           /* Guest page tables not configured yet     */
    vcpu->im       = 0xFFu;        /* All interrupt sources enabled in guest   */
}

/* ═══════════════════════════════════════════════════════════════════
 *  vcpu_save_state() — snapshot guest GPRs + CSRs → VM struct
 *
 *  The IVT assembly stub has already stored all 32 GPRs into
 *  s_scratch_regs[] before calling this function.  We copy them out.
 * ═══════════════════════════════════════════════════════════════════ */
void vcpu_save_state(uint8_t vm_id)
{
    vcpu_state_t *vcpu;
    uint32_t      i, v;

    if (vm_id >= HV_MAX_VMS) return;
    vcpu = &g_hv.vms[vm_id].vcpu;

    /* Copy GPRs from scratch area */
    for (i = 0; i < 32u; i++)
        vcpu->regs[i] = s_scratch_regs[i];

    /* Read volatile CSRs (hardware may have updated them on trap entry) */
    __asm__ volatile ("CSRR %0, epc"    : "=r"(v)); vcpu->epc    = v;
    __asm__ volatile ("CSRR %0, cause"  : "=r"(v)); vcpu->cause  = v;
    __asm__ volatile ("CSRR %0, status" : "=r"(v)); vcpu->status = v;
    __asm__ volatile ("CSRR %0, ivt"    : "=r"(v)); vcpu->ivt    = v;
    __asm__ volatile ("CSRR %0, ptbase" : "=r"(v)); vcpu->ptbase = v;

    /* Saved PC is the faulting instruction address (from EPC) */
    vcpu->pc = vcpu->epc;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vcpu_restore_state() — load guest GPRs from VM struct → scratch
 *
 *  Before issuing ERET, the assembly trampoline reads GPRs from
 *  s_scratch_regs[].  This function fills that buffer from the VM struct
 *  and also restores all guest CSRs.
 * ═══════════════════════════════════════════════════════════════════ */
void vcpu_restore_state(uint8_t vm_id)
{
    vcpu_state_t *vcpu;
    uint32_t      i;

    if (vm_id >= HV_MAX_VMS) return;
    vcpu = &g_hv.vms[vm_id].vcpu;

    /* Copy GPRs to scratch (assembly trampoline reads from here) */
    for (i = 0; i < 32u; i++)
        s_scratch_regs[i] = vcpu->regs[i];

    /* Restore guest CSRs */
    __asm__ volatile ("CSRW epc,    %0" : : "r"(vcpu->pc));
    __asm__ volatile ("CSRW ivt,    %0" : : "r"(vcpu->ivt));
    __asm__ volatile ("CSRW ptbase, %0" : : "r"(vcpu->ptbase));
    __asm__ volatile ("CSRW im,     %0" : : "r"(vcpu->im));

    /* Restore guest STATUS but always keep IE=1 so interrupts can fire
     * while the guest runs (the timer needs to be able to preempt it). */
    __asm__ volatile ("CSRW status, %0" : : "r"(vcpu->status | 0x0001u));
}

/* ═══════════════════════════════════════════════════════════════════
 *  vcpu_run() — enter guest execution (never returns)
 *
 *  1. Calls vcpu_restore_state() to fill s_scratch_regs[] + CSRs.
 *  2. Assembly trampoline loads R1..R31 from s_scratch_regs[].
 *  3. ERET — jumps to CSR_EPC (= guest PC) and drops to guest mode.
 *
 *  The next C code that executes after this is trap_handle() when the
 *  guest hits a trap or interrupt.
 * ═══════════════════════════════════════════════════════════════════ */
void vcpu_run(uint8_t vm_id)
{
    vcpu_restore_state(vm_id);

    /*
     * Assembly trampoline:
     *   - Load address of s_scratch_regs into a temporary register.
     *   - LW R2..R31 from scratch[2..31] * 4.
     *   - LW R1 last (it held the scratch base address).
     *   - ERET: atomically restore privilege + jump to EPC.
     *
     * Note: R0 is always 0 and is never loaded.
     */
    __asm__ volatile (
        /* Load scratch_regs base address into R1 */
        "MOVHI R1, %%hi(%[scratch])     \n\t"
        "ORI   R1, R1, %%lo(%[scratch]) \n\t"
        /* Load R2..R31 from scratch[2]..scratch[31] */
        "LW  R2,   8(R1)  \n\t"
        "LW  R3,  12(R1)  \n\t"
        "LW  R4,  16(R1)  \n\t"
        "LW  R5,  20(R1)  \n\t"
        "LW  R6,  24(R1)  \n\t"
        "LW  R7,  28(R1)  \n\t"
        "LW  R8,  32(R1)  \n\t"
        "LW  R9,  36(R1)  \n\t"
        "LW  R10, 40(R1)  \n\t"
        "LW  R11, 44(R1)  \n\t"
        "LW  R12, 48(R1)  \n\t"
        "LW  R13, 52(R1)  \n\t"
        "LW  R14, 56(R1)  \n\t"
        "LW  R15, 60(R1)  \n\t"
        "LW  R16, 64(R1)  \n\t"
        "LW  R17, 68(R1)  \n\t"
        "LW  R18, 72(R1)  \n\t"
        "LW  R19, 76(R1)  \n\t"
        "LW  R20, 80(R1)  \n\t"
        "LW  R21, 84(R1)  \n\t"
        "LW  R22, 88(R1)  \n\t"
        "LW  R23, 92(R1)  \n\t"
        "LW  R24, 96(R1)  \n\t"
        "LW  R25,100(R1)  \n\t"
        "LW  R26,104(R1)  \n\t"
        "LW  R27,108(R1)  \n\t"
        "LW  R28,112(R1)  \n\t"
        "LW  R29,116(R1)  \n\t"
        "LW  R30,120(R1)  \n\t"
        "LW  R31,124(R1)  \n\t"
        "LW  R1,   4(R1)  \n\t"   /* Load R1 itself last                   */
        "ERET             \n\t"    /* Jump to EPC; restore privilege level  */
        :                          /* No outputs (execution doesn't return) */
        : [scratch] "i" (s_scratch_regs)
        : /* All GPRs are clobbered — the whole point of ERET */
    );

    __builtin_unreachable();
}
