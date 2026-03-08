/*
 * interrupts.c — OS Interrupt Subsystem
 *
 * Provides a registration API over the raw hardware interrupt vector table.
 * The hardware IVT (configured in CSR_IVT) routes each of the 8 interrupt
 * sources to an assembly stub, which then calls irq_dispatch() here.
 *
 * Interrupt sources (EduRISC-32v2 hardware):
 *   IRQ 0 — Timer    (used by scheduler for preemptive multitasking)
 *   IRQ 1 — UART RX  (byte received on serial port)
 *   IRQ 2 — UART TX  (FIFO ready for next byte)
 *   IRQ 3 — GPIO     (edge-triggered on any GPIO pin)
 *   IRQ 4 — SPI      (SPI transfer complete)
 *   IRQ 5 — I2C      (I2C byte ready / NAK)
 *   IRQ 6 — DMA      (DMA transfer complete)
 *   IRQ 7 — EXT      (user-defined external interrupt)
 *
 * Usage:
 *   interrupts_init();
 *   irq_register(IRQ_UART_RX, uart_rx_handler, &uart_device);
 *   irq_enable(IRQ_UART_RX);
 *   global_irq_enable();
 */

#include <stdint.h>
#include <stddef.h>

/* ─── Configuration ──────────────────────────── */
#define NUM_IRQS        8u

/* Symbolic IRQ numbers */
#define IRQ_TIMER       0u
#define IRQ_UART_RX     1u
#define IRQ_UART_TX     2u
#define IRQ_GPIO        3u
#define IRQ_SPI         4u
#define IRQ_I2C         5u
#define IRQ_DMA         6u
#define IRQ_EXT         7u

/* EduRISC-32v2 CSR addresses */
#define CSR_STATUS_ADDR 0x000   /* IE[0], IM[7:1], priv[9:8]               */
#define CSR_IM_ADDR     0x004   /* Interrupt mask: bit N enables IRQ N      */

/* ─── Types ─────────────────────────────────── */
typedef void (*irq_handler_t)(uint32_t irq, void *data);

typedef struct {
    irq_handler_t handler;   /* Registered handler function                 */
    void         *data;      /* Opaque context passed to handler            */
    uint32_t      count;     /* Number of times this IRQ has fired          */
    uint8_t       enabled;   /* IRQ mask bit (1 = unmasked in hardware)     */
    uint8_t       registered;/* 1 if a handler has been installed           */
} irq_desc_t;

/* ─── Module state ───────────────────────────── */
static irq_desc_t s_irq[NUM_IRQS];
static uint32_t   s_irq_pending;    /* Bitmask of deferred (no-handler) IRQs */

/* ═══════════════════════════════════════════════════════════════════
 *  interrupts_init() — initialize interrupt subsystem
 * ═══════════════════════════════════════════════════════════════════
 *  Call once during kernel startup, with global interrupts disabled.
 */
void interrupts_init(void)
{
    uint32_t i;
    for (i = 0; i < NUM_IRQS; i++) {
        s_irq[i].handler    = (irq_handler_t)0;
        s_irq[i].data       = (void *)0;
        s_irq[i].count      = 0u;
        s_irq[i].enabled    = 0u;
        s_irq[i].registered = 0u;
    }
    s_irq_pending = 0u;

    /* Hardware: mask all interrupt sources */
    __asm__ volatile ("CSRW im, %0" : : "r"(0u));
}

/* ═══════════════════════════════════════════════════════════════════
 *  irq_register() — install an interrupt handler
 *
 *  Does NOT automatically enable the IRQ.  Call irq_enable() separately.
 *  Returns 0 on success, -1 on bad IRQ number, -2 on null handler.
 * ═══════════════════════════════════════════════════════════════════ */
int irq_register(uint32_t irq, irq_handler_t handler, void *data)
{
    if (irq >= NUM_IRQS) return -1;
    if (!handler)        return -2;

    global_irq_disable();   /* Atomic update */
    s_irq[irq].handler    = handler;
    s_irq[irq].data       = data;
    s_irq[irq].registered = 1u;
    s_irq[irq].count      = 0u;
    global_irq_enable();

    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  irq_enable() / irq_disable() — per-source masking
 * ═══════════════════════════════════════════════════════════════════ */
void irq_enable(uint32_t irq)
{
    uint32_t mask;
    if (irq >= NUM_IRQS) return;
    s_irq[irq].enabled = 1u;
    __asm__ volatile ("CSRR %0, im" : "=r"(mask));
    mask |= (1u << irq);
    __asm__ volatile ("CSRW im, %0" : : "r"(mask));
}

void irq_disable(uint32_t irq)
{
    uint32_t mask;
    if (irq >= NUM_IRQS) return;
    s_irq[irq].enabled = 0u;
    __asm__ volatile ("CSRR %0, im" : "=r"(mask));
    mask &= ~(1u << irq);
    __asm__ volatile ("CSRW im, %0" : : "r"(mask));
}

/* ═══════════════════════════════════════════════════════════════════
 *  global_irq_enable() / global_irq_disable() — CPU-wide IRQ gate
 * ═══════════════════════════════════════════════════════════════════ */
void global_irq_enable(void)
{
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0001u));
}

void global_irq_disable(void)
{
    __asm__ volatile ("CSRW status, %0" : : "r"(0x0000u));
}

/* ═══════════════════════════════════════════════════════════════════
 *  irq_dispatch() — called from the hardware IVT assembly stubs
 *
 *  Fires the registered handler, or queues the IRQ as pending if no
 *  handler is installed.  Automatically masks the IRQ during handling
 *  to prevent re-entrance on level-triggered interrupt lines.
 * ═══════════════════════════════════════════════════════════════════ */
void irq_dispatch(uint32_t irq)
{
    if (irq >= NUM_IRQS) return;

    s_irq[irq].count++;

    if (s_irq[irq].registered && s_irq[irq].handler) {
        /* Mask this source during handling */
        irq_disable(irq);

        s_irq[irq].handler(irq, s_irq[irq].data);

        /* Re-enable after handling (unless the handler disabled it) */
        if (s_irq[irq].registered)
            irq_enable(irq);
    } else {
        /* No handler: mark pending for irq_process_pending() */
        s_irq_pending |= (1u << irq);
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  irq_process_pending() — service deferred IRQs from kernel idle loop
 * ═══════════════════════════════════════════════════════════════════ */
void irq_process_pending(void)
{
    uint32_t pending;
    uint32_t i;

    global_irq_disable();
    pending = s_irq_pending;
    s_irq_pending = 0u;
    global_irq_enable();

    for (i = 0; i < NUM_IRQS; i++) {
        if (pending & (1u << i))
            irq_dispatch(i);
    }
}

/* ═══════════════════════════════════════════════════════════════════
 *  irq_get_count() — return number of times an IRQ has fired
 * ═══════════════════════════════════════════════════════════════════ */
uint32_t irq_get_count(uint32_t irq)
{
    if (irq >= NUM_IRQS) return 0u;
    return s_irq[irq].count;
}
