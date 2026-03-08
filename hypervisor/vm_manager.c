/*
 * vm_manager.c — Virtual Machine Lifecycle Management
 *
 * Handles creation, destruction, and state transitions for guest VMs.
 * Each VM receives an isolated 64 KB guest physical memory window and
 * a single vCPU initialized to a caller-supplied entry point.
 *
 * VM lifecycle:
 *   vm_create()   → VM_STATE_CREATED
 *   vm_start()    → VM_STATE_READY      (enters scheduler)
 *   (scheduler)   → VM_STATE_RUNNING    (on physical CPU)
 *   vm_pause()    → VM_STATE_BLOCKED    (removed from scheduler)
 *   vm_destroy()  → VM_STATE_FREE       (resources released)
 */

#include "hypervisor.h"

extern hv_state_t g_hv;

/* ═══════════════════════════════════════════════════════════════════
 *  Internal helpers
 * ═══════════════════════════════════════════════════════════════════ */

/* Zero a memory region without relying on libc memset */
static void vm_zero(void *ptr, uint32_t size)
{
    uint8_t *p = (uint8_t *)ptr;
    uint32_t i;
    for (i = 0; i < size; i++) p[i] = 0;
}

/* Copy a string (up to max-1 chars + NUL) */
static void vm_strncpy(char *dst, const char *src, uint32_t max)
{
    uint32_t i;
    for (i = 0; i < max - 1u && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_create() — allocate and configure a new guest VM
 *
 *  Parameters:
 *    mem_base  – host physical address where the VM's memory starts.
 *                Must be HV_SIZE-aligned (caller computes this).
 *                Pass 0 to auto-assign from the standard guest layout:
 *                  VM 0 → 0x00010000, VM 1 → 0x00020000, ...
 *    mem_size  – size of guest physical memory (≤ GUEST_MEM_PER_VM)
 *    entry_pc  – guest PC at first execution (GPA, typically 0)
 *    name      – human-readable label (truncated to 15 chars)
 *
 *  Returns: VM ID on success, negative error code on failure.
 * ═══════════════════════════════════════════════════════════════════ */
int vm_create(uint32_t mem_base, uint32_t mem_size,
              uint32_t entry_pc, const char *name)
{
    uint8_t  slot;
    vm_t    *vm;

    /* Validate arguments */
    if (mem_size == 0 || mem_size > GUEST_MEM_PER_VM) return -1;
    if (entry_pc >= mem_size)                          return -2;

    /* Find a free PCB slot */
    for (slot = 0; slot < HV_MAX_VMS; slot++) {
        if (g_hv.vms[slot].state == VM_STATE_FREE) break;
    }
    if (slot == HV_MAX_VMS) return -3;  /* No free VM slots */

    vm = &g_hv.vms[slot];
    vm_zero(vm, sizeof(vm_t));

    vm->id       = slot;
    vm->state    = VM_STATE_CREATED;
    vm->quantum  = HV_TICK_INTERVAL;
    vm->mem_size = mem_size;

    /* Auto-assign guest physical memory if caller passed 0 */
    vm->mem_base = mem_base ? mem_base
                            : (GUEST_MEM_BASE + (uint32_t)slot * GUEST_MEM_PER_VM);

    /* Safety check: guest memory must not overlap the hypervisor */
    if (vm->mem_base < HV_SIZE) return -4;
    if ((vm->mem_base + vm->mem_size) > TOTAL_MEM_SIZE) return -5;

    vm_strncpy(vm->name, name ? name : "vm", 16);

    /* Set up shadow page table and zero guest memory */
    if (vm_alloc_memory(slot) < 0) {
        vm->state = VM_STATE_FREE;
        return -6;
    }

    /* Initialize the vCPU: entry PC in guest address space (GPA),
     * stack at the top of guest memory */
    vcpu_init(&vm->vcpu, entry_pc, vm->mem_size - 16u);

    g_hv.vm_count++;
    return (int)slot;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_destroy() — release a VM's resources
 * ═══════════════════════════════════════════════════════════════════ */
int vm_destroy(uint8_t vm_id)
{
    vm_t *vm;
    if (vm_id >= HV_MAX_VMS)           return -1;
    vm = &g_hv.vms[vm_id];
    if (vm->state == VM_STATE_FREE)    return -2;
    if (vm->state == VM_STATE_RUNNING) return -3;  /* Cannot destroy running VM */

    /* Zero guest memory (security: wipe before slot reuse) */
    {
        volatile uint8_t *p = (volatile uint8_t *)vm->mem_base;
        uint32_t i;
        for (i = 0; i < vm->mem_size; i++) p[i] = 0;
    }

    vm->state = VM_STATE_FREE;
    g_hv.vm_count--;
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_start() — mark a VM as ready-to-run (enters the scheduler)
 * ═══════════════════════════════════════════════════════════════════ */
int vm_start(uint8_t vm_id)
{
    if (vm_id >= HV_MAX_VMS)                          return -1;
    if (g_hv.vms[vm_id].state == VM_STATE_FREE)       return -2;
    if (g_hv.vms[vm_id].state == VM_STATE_RUNNING)    return -3;

    g_hv.vms[vm_id].state = VM_STATE_READY;
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_pause() — suspend a running or ready VM
 * ═══════════════════════════════════════════════════════════════════ */
int vm_pause(uint8_t vm_id)
{
    vm_state_t st;
    if (vm_id >= HV_MAX_VMS)                    return -1;
    st = g_hv.vms[vm_id].state;
    if (st == VM_STATE_FREE)                    return -2;
    if (st == VM_STATE_RUNNING || st == VM_STATE_READY) {
        g_hv.vms[vm_id].state = VM_STATE_BLOCKED;
        return 0;
    }
    return -3;  /* Already blocked or halted */
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_get() — return a pointer to a VM descriptor (NULL if invalid)
 * ═══════════════════════════════════════════════════════════════════ */
vm_t *vm_get(uint8_t vm_id)
{
    if (vm_id >= HV_MAX_VMS)                    return (vm_t *)0;
    if (g_hv.vms[vm_id].state == VM_STATE_FREE) return (vm_t *)0;
    return &g_hv.vms[vm_id];
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_schedule_next() — preempt current VM and hand off to hv_main()
 *
 *  Called from trap_timer() after saving any necessary CPU state.
 *  Transitions the current VM back to READY, then tail-calls hv_main()
 *  which selects the next runnable VM.
 * ═══════════════════════════════════════════════════════════════════ */
void vm_schedule_next(void)
{
    uint8_t cur = g_hv.current_vm;

    /* Save the current vCPU context before we leave it */
    vcpu_save_state(cur);

    /* Demote: RUNNING → READY (unless it halted or was externally paused) */
    if (g_hv.vms[cur].state == VM_STATE_RUNNING)
        g_hv.vms[cur].state = VM_STATE_READY;

    /* Tail-call back into the main scheduling loop.
     * This is intentionally a direct call (not a return); the ABI call
     * depth stays bounded because hv_main() only calls vcpu_run() which
     * issues ERET and resets the trap stack. */
    hv_main();
}
