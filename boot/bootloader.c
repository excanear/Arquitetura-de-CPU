/*
 * bootloader.c — EduRISC-32v2 C-level Bootloader
 *
 * Execution order:
 *   1. CPU reset vector (0x000000) jumps to boot/bootloader.asm
 *   2. bootloader.asm sets SP, zeros BSS, copies .data from ROM→RAM
 *   3. bootloader.asm calls bootloader_main()  ← this file
 *   4. bootloader_main() initialises peripherals, probes memory,
 *      optionally loads the kernel from flash, then calls either:
 *        a. hv_main()     if CONFIG_HYPERVISOR is defined, OR
 *        b. kernel_main() for a bare-OS configuration
 *
 * This file must be compiled with:
 *   -DCONFIG_HYPERVISOR   to build the full HV+OS stack
 *   (omit the flag)       to build the OS-only configuration
 *
 * Memory map (Arty A7-35T at 25 MHz):
 *   0x00000000 – 0x00007FFF  IMEM (32 KB, BRAM)
 *   0x00008000 – 0x0000FFFF  DMEM (32 KB, BRAM)
 *   0x40000000               UART  (115200 baud)
 *   0x40001000               Timer (1 ms tick)
 *   0x40002000               GPIO  (4 LEDs + 4 buttons)
 *   0x60000000               SPI flash (FPGA mode only)
 */

#include <stdint.h>
#include <stddef.h>

/* ═══════════════════════════════════════════════════════════════════
 *  MMIO register map
 * ═══════════════════════════════════════════════════════════════════ */

/* UART */
#define UART_BASE   0x40000000u
#define UART_DR     (*(volatile uint32_t *)(UART_BASE + 0x00u))  /* data reg   */
#define UART_SR     (*(volatile uint32_t *)(UART_BASE + 0x04u))  /* status reg */
#define UART_BAUD   (*(volatile uint32_t *)(UART_BASE + 0x08u))  /* baud div   */
#define UART_TXRDY  (UART_SR & 0x01u)
#define UART_RXRDY  (UART_SR & 0x02u)

/* Timer */
#define TIMER_BASE  0x40001000u
#define TIMER_LOAD  (*(volatile uint32_t *)(TIMER_BASE + 0x00u))
#define TIMER_VAL   (*(volatile uint32_t *)(TIMER_BASE + 0x04u))
#define TIMER_CTRL  (*(volatile uint32_t *)(TIMER_BASE + 0x08u))
#define TIMER_ICLR  (*(volatile uint32_t *)(TIMER_BASE + 0x0Cu))
#define TC_ENABLE   0x01u
#define TC_PERIODIC 0x02u
#define TC_INTEN    0x04u

/* GPIO */
#define GPIO_BASE   0x40002000u
#define GPIO_DIR    (*(volatile uint32_t *)(GPIO_BASE + 0x00u))  /* 1=output   */
#define GPIO_OUT    (*(volatile uint32_t *)(GPIO_BASE + 0x04u))
#define GPIO_IN     (*(volatile uint32_t *)(GPIO_BASE + 0x08u))

/* SPI flash (memory-mapped, FPGA only) */
#define FLASH_BASE  0x60000000u

/* ═══════════════════════════════════════════════════════════════════
 *  Timing constants (25 MHz PLL output on Arty A7)
 * ═══════════════════════════════════════════════════════════════════ */
#define CLK_HZ          25000000u
#define SCHED_HZ        1000u                        /* 1 ms tick            */
#define TIMER_RELOAD    (CLK_HZ / SCHED_HZ)          /* 25 000 cycles        */
#define UART_BAUD_115200 (CLK_HZ / (115200u * 16u))  /* ≈ 13                 */

/* ═══════════════════════════════════════════════════════════════════
 *  Kernel / hypervisor image layout (FPGA flash)
 * ═══════════════════════════════════════════════════════════════════
 *   Flash offset 0x0000 – 0x3FFF : bootloader copy (not re-loaded)
 *   Flash offset 0x4000 – 0x7FFF : kernel / HV image (8 KB)
 */
#define KERNEL_FLASH_OFFSET  0x4000u
#define KERNEL_FLASH_SIZE    0x2000u    /* 8 KB                               */
#define KERNEL_LOAD_ADDR     0x00002000u

/* ═══════════════════════════════════════════════════════════════════
 *  UART helpers
 * ═══════════════════════════════════════════════════════════════════ */
static void uart_init(void)
{
    UART_BAUD = UART_BAUD_115200;
}

static void uart_putc(char c)
{
    while (!UART_TXRDY) {}
    UART_DR = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
    uart_putc('\r');
    uart_putc('\n');
}

static void uart_puthex(uint32_t v)
{
    int i;
    uart_putc('0'); uart_putc('x');
    for (i = 28; i >= 0; i -= 4) {
        uint8_t nib = (v >> i) & 0xFu;
        uart_putc(nib < 10u ? (char)('0' + nib) : (char)('A' + nib - 10u));
    }
}

static void uart_putudec(uint32_t v)
{
    char buf[11];
    int  i = 10;
    buf[i] = '\0';
    if (!v) { uart_putc('0'); return; }
    while (v) { buf[--i] = (char)('0' + v % 10u); v /= 10u; }
    while (buf[i]) uart_putc(buf[i++]);
}

/* ═══════════════════════════════════════════════════════════════════
 *  GPIO / LED helpers
 * ═══════════════════════════════════════════════════════════════════ */
static uint32_t s_led_state = 0u;

static void gpio_init(void)
{
    GPIO_DIR = 0x0Fu;   /* Pins [3:0] outputs (LEDs), [7:4] inputs (buttons) */
    GPIO_OUT = 0x01u;   /* LED0 = "boot in progress"                         */
    s_led_state = 0x01u;
}

static void led_set(uint8_t pattern)
{
    s_led_state = (uint32_t)(pattern & 0x0Fu);
    GPIO_OUT    = s_led_state;
}

static void led_blink(void)
{
    GPIO_OUT ^= 0x02u;   /* Toggle LED1 */
}

/* ═══════════════════════════════════════════════════════════════════
 *  Timer initialisation
 * ═══════════════════════════════════════════════════════════════════ */
static void timer_init(void)
{
    TIMER_CTRL  = 0u;                           /* Disable while configuring  */
    TIMER_LOAD  = TIMER_RELOAD;                 /* Reload value               */
    TIMER_VAL   = TIMER_RELOAD;                 /* Initial count              */
    TIMER_CTRL  = TC_ENABLE | TC_PERIODIC | TC_INTEN;
}

/* ═══════════════════════════════════════════════════════════════════
 *  Memory probe  — walks physical memory in 1 KB steps looking for live RAM
 * ═══════════════════════════════════════════════════════════════════ */
static uint32_t probe_dmem(uint32_t base, uint32_t max_bytes)
{
    volatile uint32_t *p;
    uint32_t           step = 1024u, size;
    uint32_t           save, probe;

    for (size = 0u; size < max_bytes; size += step) {
        p     = (volatile uint32_t *)(base + size);
        save  = *p;
        *p    = 0xA5A5A5A5u;
        probe = *p;
        *p    = save;
        if (probe != 0xA5A5A5A5u) break;
    }
    return size;
}

/* ═══════════════════════════════════════════════════════════════════
 *  Kernel image loader (FPGA mode)
 *  Reads word-by-word from SPI flash memory-mapped region.
 * ═══════════════════════════════════════════════════════════════════ */
static int load_kernel(uint32_t flash_off, uint32_t dest, uint32_t bytes)
{
    volatile uint32_t *src = (volatile uint32_t *)(FLASH_BASE + flash_off);
    volatile uint32_t *dst = (volatile uint32_t *)dest;
    uint32_t           words = bytes / 4u, i;

    uart_puts("[BOOT] Loading kernel...");
    for (i = 0u; i < words; i++) {
        dst[i] = src[i];
        if ((i & 0x1FFu) == 0u) led_blink();   /* Blink during load          */
    }
    uart_puts("[BOOT] Kernel loaded at 0x");
    uart_puthex(dest);
    uart_puts(", size=");
    uart_putudec(bytes);
    uart_puts(" bytes.");
    return 0;
}

/* ═══════════════════════════════════════════════════════════════════
 *  Boot mode detection
 *  GPIO button 0 (input pin 4) held at reset → FPGA mode (load from flash).
 *  Released (or in simulation) → direct execution mode.
 * ═══════════════════════════════════════════════════════════════════ */
#define BOOT_SIM    0
#define BOOT_FPGA   1

static int detect_boot_mode(void)
{
    return (GPIO_IN & 0x10u) ? BOOT_FPGA : BOOT_SIM;
}

/* ═══════════════════════════════════════════════════════════════════
 *  bootloader_main() — C entry point (called from bootloader.asm)
 * ═══════════════════════════════════════════════════════════════════ */
void bootloader_main(void)
{
    int      mode;
    uint32_t dmem_size;

    /* ── 1. GPIO + UART ───────────────────────────────────────────── */
    gpio_init();
    uart_init();

    uart_puts("============================================");
    uart_puts(" EduRISC-32v2 Bootloader  v1.0");
    uart_puts(" Build: " __DATE__ " " __TIME__);
    uart_puts("============================================");

    /* ── 2. Boot mode detection ─────────────────────────────────── */
    mode = detect_boot_mode();
    uart_puts("[BOOT] Mode: ");
    uart_puts(mode == BOOT_FPGA ? "FPGA hardware" : "Software simulation");

    /* ── 3. DMEM probe ──────────────────────────────────────────── */
    uart_puts("[BOOT] Probing DMEM...");
    dmem_size = probe_dmem(0x00008000u, 0x00008000u);   /* Up to 32 KB       */
    uart_puts("[BOOT] DMEM available: ");
    uart_putudec(dmem_size / 1024u);
    uart_puts(" KB (");
    uart_puthex(dmem_size);
    uart_puts(" bytes)");

    if (dmem_size < 4096u) {
        uart_puts("[BOOT] ERROR: Insufficient DMEM (need >= 4 KB)!");
        led_set(0x0Fu);   /* All LEDs on = fatal error                       */
        while (1) {}
    }

    /* ── 4. Load kernel from flash (FPGA only) ──────────────────── */
    if (mode == BOOT_FPGA) {
        if (load_kernel(KERNEL_FLASH_OFFSET,
                        KERNEL_LOAD_ADDR,
                        KERNEL_FLASH_SIZE) < 0) {
            uart_puts("[BOOT] ERROR: Kernel load failed!");
            led_set(0x0Fu);
            while (1) {}
        }
    } else {
        uart_puts("[BOOT] Simulation: kernel already in IMEM, skipping load.");
    }

    /* ── 5. Timer ───────────────────────────────────────────────── */
    timer_init();
    uart_puts("[BOOT] Timer configured: ");
    uart_putudec(SCHED_HZ);
    uart_puts(" Hz (");
    uart_putudec(TIMER_RELOAD);
    uart_puts(" cycles/tick)");

    /* ── 6. Ready indicator ─────────────────────────────────────── */
    led_set(0x03u);   /* LED[1:0] = "running"                               */
    uart_puts("[BOOT] Hardware initialised. Handing off...");
    uart_puts("");

    /* ── 7. Jump to kernel or hypervisor ────────────────────────── */
#ifdef CONFIG_HYPERVISOR
    {
        extern void hv_init(void);
        extern void hv_main(void);

        uart_puts("[BOOT] Starting Hypervisor...");
        hv_init();

        /*
         * Register the built-in guest OS images as VM 0 and (optionally) VM 1.
         * In simulation both images are the same binary; on FPGA they could be
         * separate images loaded at different flash offsets.
         */
        {
            int vm0 = vm_create(0u,           /* auto-assign mem_base */
                                0x00010000u,  /* 64 KB guest memory   */
                                0x00000000u,  /* entry GPA = 0        */
                                "guest-os-0");
            if (vm0 >= 0) {
                vm_start((uint8_t)vm0);
                uart_puts("[BOOT] Registered VM 0: guest-os-0");
            } else {
                uart_puts("[BOOT] WARNING: Could not create VM 0");
            }
        }

        hv_main();   /* Never returns */
    }
#else
    {
        extern void kernel_main(void);
        uart_puts("[BOOT] Starting OS kernel...");
        kernel_main();   /* Never returns */
    }
#endif

    /* Should never reach here */
    uart_puts("[BOOT] ERROR: kernel returned (should never happen)!");
    led_set(0x0Fu);
    while (1) {}
}
