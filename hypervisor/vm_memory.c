/*
 * vm_memory.c — Guest Memory Isolation and Address Translation
 *
 * Provides a software shadow page table for each VM that maps
 * Guest Physical Addresses (GPA) to Host Physical Addresses (HPA).
 *
 * Design decisions:
 *  • The EduRISC-32v2 MMU uses 1 KB pages (10-bit offset, 22-bit VPN).
 *    We mirror that granularity in the shadow table for simplicity.
 *  • Each VM gets up to PT_ENTRIES shadow page table entries.
 *    With PAGE_SIZE=1024 and PT_ENTRIES=64: 64 × 1KB = 64 KB per VM.
 *  • The translation is: HPA = shadow_pte[gpa/PAGE_SIZE].hpa + (gpa % PAGE_SIZE)
 *  • Guest memory is identity-mapped on creation: GPA 0 → HPA mem_base.
 *    This keeps the guest OS unaware of its real physical placement.
 *
 * Security property:
 *  • Guests cannot map pages below HV_SIZE (hypervisor memory).
 *  • Guests cannot map pages belonging to other VMs.
 *  • Any GPA outside the shadow table raises a page fault → trap_page_fault().
 */

#include "hypervisor.h"

/* ─── Page table constants ───────────────────── */
#define PAGE_SIZE       1024u       /* 1 KB per page (matches EduRISC-32v2 MMU) */
#define PT_ENTRIES      64u         /* Shadow PTE entries per VM (= 64 KB / 1 KB)*/

/* Page permission flags (stored in shadow PTE) */
#define PTE_VALID   (1u << 0)
#define PTE_READ    (1u << 1)
#define PTE_WRITE   (1u << 2)
#define PTE_EXEC    (1u << 3)
#define PTE_GUEST   (1u << 4)   /* Allocated for guest (not HV-internal)    */
#define PTE_RWX     (PTE_READ | PTE_WRITE | PTE_EXEC)

/* ─── Shadow page table entry ─────────────────── */
typedef struct {
    uint32_t hpa;               /* Host physical address (page-aligned HPA)  */
    uint32_t flags;             /* PTE_* flags                               */
} spte_t;

/* One shadow page table per VM */
static spte_t s_spt[HV_MAX_VMS][PT_ENTRIES];

/* ═══════════════════════════════════════════════════════════════════
 *  vm_alloc_memory() — set up GPA→HPA mappings for a new VM
 *
 *  Builds an identity mapping: GPA N*PAGE_SIZE → HPA mem_base + N*PAGE_SIZE
 *  for all pages within vm->mem_size. Pages beyond are marked invalid.
 *  The guest memory region is zeroed for security.
 * ═══════════════════════════════════════════════════════════════════ */
int vm_alloc_memory(uint8_t vm_id)
{
    vm_t    *vm;
    uint32_t page_idx;
    uint32_t gpa, hpa;

    if (vm_id >= HV_MAX_VMS) return -1;
    vm = &g_hv.vms[vm_id];

    /* Validate: guest memory must lie entirely within physical address space */
    if ((vm->mem_base + vm->mem_size) > TOTAL_MEM_SIZE)      return -2;
    if (vm->mem_size > (uint32_t)(PT_ENTRIES * PAGE_SIZE))   return -3;
    if (vm->mem_base < HV_SIZE)                              return -4; /* Safety */

    /* Securely zero the entire guest physical memory region */
    {
        volatile uint32_t *p = (volatile uint32_t *)vm->mem_base;
        uint32_t words = vm->mem_size / 4u;
        uint32_t w;
        for (w = 0; w < words; w++) p[w] = 0u;
    }

    /* Build shadow page table */
    for (page_idx = 0; page_idx < PT_ENTRIES; page_idx++) {
        gpa = (uint32_t)(page_idx * PAGE_SIZE);
        hpa = vm->mem_base + gpa;

        if (gpa >= vm->mem_size) {
            /* Beyond the actual allocation: invalid */
            s_spt[vm_id][page_idx].hpa   = 0u;
            s_spt[vm_id][page_idx].flags = 0u;
        } else {
            s_spt[vm_id][page_idx].hpa   = hpa;
            s_spt[vm_id][page_idx].flags = PTE_VALID | PTE_RWX | PTE_GUEST;
        }
    }

    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_map_page() — install or update a single shadow PTE
 *
 *  The caller specifies GPA (guest physical) and HPA (host physical).
 *  Both must be PAGE_SIZE-aligned.  Flags are ORed with PTE_VALID.
 *
 *  Security checks:
 *    • HPA must not fall within the hypervisor's own memory.
 *    • HPA must not fall within another VM's memory region.
 * ═══════════════════════════════════════════════════════════════════ */
int vm_map_page(uint8_t vm_id, uint32_t gpa, uint32_t hpa, uint32_t flags)
{
    uint32_t  page_idx;
    uint8_t   other;

    if (vm_id >= HV_MAX_VMS)      return -1;
    if (gpa & (PAGE_SIZE - 1u))   return -2;   /* GPA not page-aligned        */
    if (hpa & (PAGE_SIZE - 1u))   return -3;   /* HPA not page-aligned        */

    page_idx = gpa / PAGE_SIZE;
    if (page_idx >= PT_ENTRIES)   return -4;   /* GPA out of range            */

    /* Protect hypervisor memory */
    if (hpa < HV_SIZE)            return -5;

    /* Protect other VMs' memory */
    for (other = 0; other < HV_MAX_VMS; other++) {
        if (other == vm_id) continue;
        if (g_hv.vms[other].state == VM_STATE_FREE) continue;
        if (hpa >= g_hv.vms[other].mem_base &&
            hpa <  g_hv.vms[other].mem_base + g_hv.vms[other].mem_size)
            return -6;  /* Attempting to alias another VM's memory            */
    }

    s_spt[vm_id][page_idx].hpa   = hpa;
    s_spt[vm_id][page_idx].flags = flags | PTE_VALID;
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  vm_translate() — translate GPA → HPA
 *
 *  Returns 0 and writes *hpa_out on success.
 *  Returns -1 on page fault (invalid mapping or out-of-range GPA).
 * ═══════════════════════════════════════════════════════════════════ */
int vm_translate(uint8_t vm_id, uint32_t gpa, uint32_t *hpa_out)
{
    uint32_t page_idx = gpa / PAGE_SIZE;
    uint32_t offset   = gpa & (PAGE_SIZE - 1u);

    if (vm_id >= HV_MAX_VMS)                               return -1;
    if (page_idx >= PT_ENTRIES)                             return -1;
    if (!(s_spt[vm_id][page_idx].flags & PTE_VALID))       return -1;

    *hpa_out = s_spt[vm_id][page_idx].hpa + offset;
    return 0;
}
