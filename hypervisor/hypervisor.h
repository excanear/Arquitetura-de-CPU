/*
 * hypervisor.h — EduRISC-32v2 Type-1 Bare-Metal Hypervisor
 *
 * Shared header for all hypervisor modules. Defines the VM descriptor,
 * vCPU state, memory layout constants, trap codes, and public API.
 *
 * Privilege model:
 *   Hypervisor  — highest privilege (ring -1 equivalent)
 *   Guest OS    — reduced privilege (guest supervisor)
 *   User App    — lowest privilege (user mode)
 *
 * Hardware → Hypervisor → Guest OS → Application
 */

#ifndef HYPERVISOR_H
#define HYPERVISOR_H

#include <stdint.h>
#include <stddef.h>

/* ═══════════════════════════════════════════════════════════════════
 *  Configuration
 * ═══════════════════════════════════════════════════════════════════ */
#define HV_MAX_VMS          4           /* Maximum concurrent guest VMs       */
#define HV_MAX_VCPUS        1           /* vCPUs per VM (single-core)         */
#define HV_TICK_INTERVAL    10000       /* CPU cycles per VM scheduling quantum*/
#define HV_VERSION          0x00010000  /* Version 1.0 (major:16, minor:16)   */

/* ═══════════════════════════════════════════════════════════════════
 *  Physical Memory Layout
 * ═══════════════════════════════════════════════════════════════════
 *
 *  0x00000000 ──── HV code + data (64 KB)  ──── 0x0000FFFF
 *  0x00010000 ──── VM 0 guest memory (64KB)──── 0x0001FFFF
 *  0x00020000 ──── VM 1 guest memory (64KB)──── 0x0002FFFF
 *  0x00030000 ──── VM 2 guest memory (64KB)──── 0x0003FFFF
 *  0x00040000 ──── VM 3 guest memory (64KB)──── 0x0004FFFF
 *  0x00050000 ──── Shared/MMIO region      ──── 0x0005FFFF
 *  0x40000000 ──── UART MMIO
 *  0x40001000 ──── Timer MMIO
 *  0x40002000 ──── GPIO MMIO
 */
#define HV_BASE_ADDR        0x00000000u
#define HV_SIZE             0x00010000u  /* 64 KB — hypervisor reserves this  */
#define GUEST_MEM_BASE      0x00010000u  /* First VM's memory starts here     */
#define GUEST_MEM_PER_VM    0x00010000u  /* 64 KB dedicated per VM            */
#define HV_SHARED_BASE      0x00050000u  /* Shared inter-VM region            */
#define TOTAL_MEM_SIZE      0x00060000u  /* 384 KB total physical RAM         */
#define HV_IVT_BASE         0x00000100u  /* Hypervisor Interrupt Vector Table */

/* ═══════════════════════════════════════════════════════════════════
 *  Trap / Exception Cause Codes  (written to CSR_CAUSE by hardware)
 * ═══════════════════════════════════════════════════════════════════ */
#define TRAP_ILLEGAL_INSTR  0x00u   /* Illegal / undefined instruction        */
#define TRAP_DIV_ZERO       0x01u   /* Division by zero                       */
#define TRAP_OVERFLOW       0x02u   /* Signed arithmetic overflow             */
#define TRAP_SYSCALL        0x03u   /* SYSCALL instruction                    */
#define TRAP_BREAK          0x04u   /* BREAK (debug / hypercall)              */
#define TRAP_PAGE_FAULT     0x05u   /* MMU page fault (access violation)      */
#define TRAP_MISALIGNED     0x06u   /* Misaligned memory access               */
#define TRAP_TIMER          0x10u   /* Timer interrupt (async)                */
#define TRAP_EXT_IRQ_BASE   0x20u   /* External IRQ n → TRAP_EXT_IRQ_BASE + n */

/* ═══════════════════════════════════════════════════════════════════
 *  Hypercall Numbers  (syscall number >= 0x80 → hypervisor handles)
 * ═══════════════════════════════════════════════════════════════════ */
#define HV_CALL_VERSION     0x80u   /* R1 ← HV_VERSION                       */
#define HV_CALL_VM_ID       0x81u   /* R1 ← current VM ID (0-3)              */
#define HV_CALL_VM_CREATE   0x82u   /* Create child VM (R2=entry, R3=name_ptr)*/
#define HV_CALL_VM_YIELD    0x83u   /* Voluntarily yield CPU to next VM       */
#define HV_CALL_VM_EXIT     0x84u   /* Terminate this VM                      */
#define HV_CALL_CONSOLE_PUT 0x85u   /* R2=char → write to HV console          */

/* ═══════════════════════════════════════════════════════════════════
 *  VM States
 * ═══════════════════════════════════════════════════════════════════ */
typedef enum {
    VM_STATE_FREE    = 0,   /* PCB slot is unused                             */
    VM_STATE_CREATED = 1,   /* Allocated but not yet started                  */
    VM_STATE_READY   = 2,   /* Runnable, waiting for CPU                      */
    VM_STATE_RUNNING = 3,   /* Currently executing on the physical CPU        */
    VM_STATE_BLOCKED = 4,   /* Waiting for an event (I/O, sleep, etc.)        */
    VM_STATE_HALTED  = 5,   /* Execution ended (HLT or crash)                 */
} vm_state_t;

/* ═══════════════════════════════════════════════════════════════════
 *  vCPU Register State  (saved / restored on every context switch)
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    uint32_t regs[32];      /* R0..R31  (R0 is always 0, not written)         */
    uint32_t pc;            /* Program counter                                */
    uint32_t status;        /* CSR_STATUS: IE[0], IM[7:1], priv[9:8]          */
    uint32_t epc;           /* CSR_EPC: exception return address              */
    uint32_t cause;         /* CSR_CAUSE: last trap/interrupt cause           */
    uint32_t ivt;           /* CSR_IVT: guest interrupt vector table base     */
    uint32_t ptbase;        /* CSR_PTBASE: guest page table base              */
    uint32_t im;            /* CSR_IM: guest interrupt mask                   */
} vcpu_state_t;

/* ═══════════════════════════════════════════════════════════════════
 *  VM Descriptor  (one per guest virtual machine)
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    /* Identity */
    uint8_t      id;                    /* VM index in g_hv.vms[] (0-3)       */
    char         name[16];              /* Human-readable label                */

    /* Lifecycle */
    vm_state_t   state;                 /* Current VM state                    */
    int32_t      exit_code;             /* Set on VM_STATE_HALTED              */

    /* vCPU (saved CPU context between switches) */
    vcpu_state_t vcpu;

    /* Guest physical memory */
    uint32_t     mem_base;              /* HPA where guest memory starts       */
    uint32_t     mem_size;              /* Guest memory size (bytes)           */

    /* Scheduling */
    uint32_t     ticks_remaining;       /* Cycles left in current quantum      */
    uint64_t     total_ticks;           /* Cumulative CPU cycles consumed      */
    uint64_t     total_traps;           /* Cumulative traps handled            */
    uint32_t     quantum;               /* Quantum size (may differ per VM)    */
} vm_t;

/* ═══════════════════════════════════════════════════════════════════
 *  Hypervisor Global State
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    vm_t     vms[HV_MAX_VMS];   /* VM descriptor table                        */
    uint8_t  current_vm;        /* ID of the VM currently on the CPU          */
    uint8_t  vm_count;          /* Number of non-FREE VMs                     */
    uint32_t tick_counter;      /* Global timer tick counter                  */
    uint32_t context_switches;  /* Number of VM context switches performed    */
    uint8_t  initialized;       /* 1 after hv_init() completes                */
} hv_state_t;

/* ═══════════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════════ */

/* hv_core.c */
void  hv_init(void);
void  hv_main(void)            __attribute__((noreturn));
void  hv_panic(const char *msg) __attribute__((noreturn));

/* vm_manager.c */
int   vm_create(uint32_t mem_base, uint32_t mem_size,
                uint32_t entry_pc, const char *name);
int   vm_destroy(uint8_t vm_id);
int   vm_start(uint8_t vm_id);
int   vm_pause(uint8_t vm_id);
vm_t *vm_get(uint8_t vm_id);
void  vm_schedule_next(void);

/* vm_memory.c */
int   vm_alloc_memory(uint8_t vm_id);
int   vm_map_page(uint8_t vm_id, uint32_t gpa, uint32_t hpa, uint32_t flags);
int   vm_translate(uint8_t vm_id, uint32_t gpa, uint32_t *hpa_out);

/* vm_cpu.c */
void  vcpu_init(vcpu_state_t *vcpu, uint32_t entry_pc, uint32_t sp);
void  vcpu_save_state(uint8_t vm_id);
void  vcpu_restore_state(uint8_t vm_id);
void  vcpu_run(uint8_t vm_id) __attribute__((noreturn));

/* trap_handler.c */
void  trap_handle(uint32_t cause, uint32_t epc, uint32_t badvaddr);
void  trap_syscall(uint8_t vm_id, uint32_t epc);
void  trap_page_fault(uint8_t vm_id, uint32_t fault_addr, uint32_t epc);
void  trap_illegal_instr(uint8_t vm_id, uint32_t epc);
void  trap_timer(void);

/* ═══════════════════════════════════════════════════════════════════
 *  Utility Macros
 * ═══════════════════════════════════════════════════════════════════ */
#define HV_ASSERT(cond, msg)  do { if (!(cond)) hv_panic(msg); } while (0)
#define ARRAY_SIZE(a)         (sizeof(a) / sizeof((a)[0]))

/* Compiler barriers / hints */
#define barrier()             __asm__ volatile ("" ::: "memory")
#define unreachable()         __builtin_unreachable()

#endif /* HYPERVISOR_H */
