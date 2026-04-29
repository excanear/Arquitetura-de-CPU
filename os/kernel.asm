; =============================================================================
; kernel.asm — Micro-Kernel EduRISC-32v2
;
; Kernel mínimo para o processador EduRISC-32v2.
; ISA: 32 bits, 32 registradores, instruções de largura fixa de 32 bits.
;
; Responsabilidades:
;   - IVT (Interrupt/Exception Vector Table) em 0x000–0x00F
;   - Inicialização do sistema (stack, CSRs, timer, tabela de processos)
;   - Dispatcher de syscalls via vetor IVT[3]
;   - Round-robin de processos (scheduler simples)
;   - Drivers básicos: UART, timer
;
; Mapa de memória (espaço unificado de instruções + dados):
;   0x000000 – 0x00000F  IVT (16 words — vetores JMP para handlers)
;   0x000010 – 0x0000FF  Código do kernel
;   0x001000 – 0x001FFF  Tabela de processos (8 × 16 words)
;   0x002000 – 0x00EFFF  Heap gerenciado pelo kernel
;   0x00F000 – 0x00FEFF  Pilha do kernel (cresce para baixo)
;   0x00FF00 – 0x00FFFF  MMIO (UART, Timer, GPIO)
;
; Convenção de registradores (EduRISC-32v2):
;   R0       — zero hardwired (leituras retornam 0, escritas ignoradas)
;   R1       — valor de retorno de função / argumento 1 de syscall
;   R2–R3    — argumentos 2–3 de syscall
;   R4–R25   — uso geral (callee-saved em chamadas de kernel)
;   R26–R29  — temporários (caller-saved)
;   R30      — SP (stack pointer, cresce para baixo)
;   R31      — LR (link register)
;
; CSRs utilizados:
;   CSR[0] STATUS   — [0]=IE (interrupt enable), [1]=KU (1=user mode), [7:4]=IM
;   CSR[1] IVT      — [25:0] base da tabela de vetores de exceção
;   CSR[2] EPC      — PC salvo automaticamente na exceção
;   CSR[3] CAUSE    — [31]=IRQ, [3:0]=código da causa
;   CSR[4] ESCRATCH — scratch do kernel para handlers
;   CSR[7] CYCLE    — contador de ciclos (bits baixos)
;   CSR[9] INSTRET  — instruções aposentadas
;
; Syscalls (número em R1 antes de SYSCALL):
;   0  SYS_EXIT    — encerra processo corrente
;   1  SYS_WRITE   — escreve char em UART  (R2=char)
;   2  SYS_READ    — le char da UART       (retorna em R1)
;   3  SYS_MALLOC  — aloca N words         (R2=N, retorna ponteiro em R1)
;   4  SYS_FREE    — libera bloco          (R2=ponteiro)
;   5  SYS_YIELD   — cede CPU
;   6  SYS_GETPID  — retorna PID em R1
; =============================================================================

; ---------------------------------------------------------------------------
; Constantes internas (definidas com .equ para uso em todo o arquivo)
; ---------------------------------------------------------------------------
.equ PROC_TABLE,    0x1000
.equ HEAP_BASE,     0x2000
.equ HEAP_END,      0xF000
.equ STACK_INIT,    0xFEFF
.equ MAX_PROCS,     8
.equ ENTRY_SIZE,    16
.equ UART_TXDATA,   0xFF00
.equ UART_STATUS,   0xFF02
.equ UART_TX_READY, 0x1
.equ TIMER_CMP,     0xFF10
.equ TIMER_QUANTUM, 10000
.equ PROC_FREE,     0
.equ PROC_READY,    1
.equ PROC_RUNNING,  2
.equ PROC_BLOCKED,  3
.equ FIELD_PID,     0
.equ FIELD_STATE,   1
.equ FIELD_PC,      2
.equ FIELD_SP,      3
.equ FIELD_R1,      4
.equ CSR_STATUS,    0
.equ CSR_IVT,       1
.equ CSR_EPC,       2
.equ CSR_CAUSE,     3
.equ CSR_ESCRATCH,  4
.equ HEAP_PTR_ADDR, 0x1FFC
.equ CURRENT_PID_ADDR, 0x0FF0

; =============================================================================
; SECAO 0: IVT — Interrupt/Exception Vector Table
; Cada entry e um JMP para o handler correspondente.
; O hardware salta para IVT[CAUSE] ao receber uma excecao.
; =============================================================================

        .org 0x000

IVT_ILLEGAL:    JMP  exc_illegal
IVT_ALIGN:      JMP  exc_align
IVT_PGFAULT:    JMP  exc_page_fault
IVT_SYSCALL:    JMP  exc_syscall
IVT_BREAK:      JMP  exc_breakpoint
IVT_TIMER:      JMP  irq_timer
IVT_UART:       JMP  irq_uart
IVT_RES7:       JMP  exc_reserved
IVT_RES8:       JMP  exc_reserved
IVT_RES9:       JMP  exc_reserved
IVT_RES10:      JMP  exc_reserved
IVT_RES11:      JMP  exc_reserved
IVT_RES12:      JMP  exc_reserved
IVT_RES13:      JMP  exc_reserved
IVT_RES14:      JMP  exc_reserved
IVT_RES15:      JMP  exc_reserved

; =============================================================================
; SECAO 1: KERNEL_START — ponto de entrada principal
; =============================================================================

        .org 0x010

KERNEL_START:
        MOVI  R30, STACK_INIT
        MOVI  R4, 0
        MTC   R4, CSR_IVT
        MOVI  R4, 0x11
        MTC   R4, CSR_STATUS
        MOVI  R4, TIMER_QUANTUM
        MOVI  R5, TIMER_CMP
        SW    R4, R5, 0
        MOVI  R10, 0
init_proc_loop:
        MOVI  R11, MAX_PROCS
        BEQ   R10, R11, init_proc_done
        MOVI  R12, ENTRY_SIZE
        MUL   R13, R10, R12
        MOVI  R14, PROC_TABLE
        ADD   R13, R13, R14
        SW    R0, R13, FIELD_PID
        SW    R0, R13, FIELD_STATE
        SW    R0, R13, FIELD_PC
        SW    R0, R13, FIELD_SP
        ADDI  R10, R10, 1
        JMP   init_proc_loop
init_proc_done:
        MOVI  R1, msg_boot
        CALL  uart_puts
        MOVI  R1, idle_process
        CALL  proc_create
        MOVI  R1, demo_process
        CALL  proc_create
        JMP   scheduler_run

; =============================================================================
; proc_create — cria processo
; Entrada: R1 = entry_point
; Saida:   R1 = pid ou 0xFFFFFFFF
; =============================================================================
proc_create:
        MOVI  R2, 0
        MOVI  R3, MAX_PROCS
proc_create_loop:
        BEQ   R2, R3, proc_create_fail
        MOVI  R4, ENTRY_SIZE
        MUL   R5, R2, R4
        MOVI  R4, PROC_TABLE
        ADD   R5, R5, R4
        LW    R4, R5, FIELD_STATE
        BNE   R4, R0, proc_create_next
        SW    R2, R5, FIELD_PID
        MOVI  R4, PROC_READY
        SW    R4, R5, FIELD_STATE
        SW    R1, R5, FIELD_PC
        MOVI  R4, STACK_INIT
        MOVI  R26, 256
        MUL   R26, R2, R26
        SUB   R4, R4, R26
        SW    R4, R5, FIELD_SP
        MOV   R1, R2
        RET
proc_create_next:
        ADDI  R2, R2, 1
        JMP   proc_create_loop
proc_create_fail:
        MOVI  R1, 0xFFFFFFFF
        RET

; =============================================================================
; scheduler_run — dispatcher round-robin
; =============================================================================
scheduler_run:
        MOVI  R10, CURRENT_PID_ADDR
        LW    R10, R10, 0
        ADDI  R10, R10, 1
        MOVI  R11, MAX_PROCS
sched_wrap:
        BLT   R10, R11, sched_find
        MOVI  R10, 0
sched_find:
        MOVI  R12, ENTRY_SIZE
        MUL   R13, R10, R12
        MOVI  R12, PROC_TABLE
        ADD   R13, R13, R12
        LW    R14, R13, FIELD_STATE
        MOVI  R12, PROC_READY
        BEQ   R14, R12, sched_dispatch
        ADDI  R10, R10, 1
        JMP   sched_wrap
sched_dispatch:
        MOVI  R14, PROC_RUNNING
        SW    R14, R13, FIELD_STATE
        MOVI  R14, CURRENT_PID_ADDR
        SW    R10, R14, 0
        LW    R30, R13, FIELD_SP
        LW    R26, R13, FIELD_PC
        MTC   R26, CSR_EPC
        MOVI  R26, 0x13
        MTC   R26, CSR_STATUS
        ERET

; =============================================================================
; exc_syscall — handler de SYSCALL (IVT[3])
; =============================================================================
exc_syscall:
        PUSH  R26
        PUSH  R27
        PUSH  R28
        MOVI  R26, 0
        BEQ   R1, R26, syscall_exit
        MOVI  R26, 1
        BEQ   R1, R26, syscall_write
        MOVI  R26, 2
        BEQ   R1, R26, syscall_read
        MOVI  R26, 3
        BEQ   R1, R26, syscall_malloc
        MOVI  R26, 4
        BEQ   R1, R26, syscall_free
        MOVI  R26, 5
        BEQ   R1, R26, syscall_yield
        MOVI  R26, 6
        BEQ   R1, R26, syscall_getpid
        MOVI  R1, 0xFFFFFFFF
        JMP   syscall_return

syscall_exit:
        MOVI  R26, CURRENT_PID_ADDR
        LW    R26, R26, 0
        MOVI  R27, ENTRY_SIZE
        MUL   R27, R26, R27
        MOVI  R28, PROC_TABLE
        ADD   R27, R27, R28
        SW    R0, R27, FIELD_STATE
        POP   R28
        POP   R27
        POP   R26
        JMP   scheduler_run

syscall_write:
        PUSH  R1
        MOV   R1, R2
        CALL  uart_putchar
        POP   R1
        MOVI  R1, 0
        JMP   syscall_return

syscall_read:
        CALL  uart_getchar
        JMP   syscall_return

syscall_malloc:
        MOV   R1, R2
        CALL  kmalloc
        JMP   syscall_return

syscall_free:
        MOV   R1, R2
        CALL  kfree
        MOVI  R1, 0
        JMP   syscall_return

syscall_yield:
        MOVI  R26, CURRENT_PID_ADDR
        LW    R26, R26, 0
        MOWI  R27, ENTRY_SIZE
        MUL   R27, R26, R27
        MOVI  R28, PROC_TABLE
        ADD   R27, R27, R28
        MFC   R28, CSR_EPC
        ADDI  R28, R28, 1
        SW    R28, R27, FIELD_PC
        MOVI  R26, PROC_READY
        SW    R26, R27, FIELD_STATE
        POP   R28
        POP   R27
        POP   R26
        JMP   scheduler_run

syscall_getpid:
        MOVI  R26, CURRENT_PID_ADDR
        LW    R1, R26, 0
        JMP   syscall_return

syscall_return:
        POP   R28
        POP   R27
        POP   R26
        ERET

; =============================================================================
; irq_timer — handler de timer (IVT[5])
; =============================================================================
irq_timer:
        PUSH  R26
        PUSH  R27
        PUSH  R28
        MOVI  R26, CURRENT_PID_ADDR
        LW    R26, R26, 0
        MOVI  R27, ENTRY_SIZE
        MUL   R27, R26, R27
        MOVI  R28, PROC_TABLE
        ADD   R27, R27, R28
        MFC   R26, CSR_EPC
        SW    R26, R27, FIELD_PC
        SW    R30, R27, FIELD_SP
        MOVI  R26, PROC_READY
        SW    R26, R27, FIELD_STATE
        MOVI  R26, TIMER_QUANTUM
        MOVI  R27, TIMER_CMP
        SW    R26, R27, 0
        POP   R28
        POP   R27
        POP   R26
        JMP   scheduler_run

irq_uart:
        ERET

; =============================================================================
; Handlers de excecao fatal
; =============================================================================
exc_illegal:
        MOVI  R1, msg_illegal
        CALL  uart_puts
        HLT

exc_align:
        MOVI  R1, msg_align
        CALL  uart_puts
        HLT

exc_page_fault:
        MOVI  R1, msg_pgfault
        CALL  uart_puts
        HLT

exc_breakpoint:
        MOVI  R1, msg_break
        CALL  uart_puts
        ERET

exc_reserved:
        HLT

; =============================================================================
; kmalloc — bump allocator
; =============================================================================
kmalloc:
        MOVI  R26, HEAP_PTR_ADDR
        LW    R27, R26, 0
        MOVI  R28, HEAP_BASE
        BNE   R27, R0, kmalloc_check
        MOV   R27, R28
kmalloc_check:
        ADD   R28, R27, R1
        MOVI  R26, HEAP_END
        BGE   R28, R26, kmalloc_fail
        MOV   R1, R27
        MOVI  R26, HEAP_PTR_ADDR
        SW    R28, R26, 0
        RET
kmalloc_fail:
        MOVI  R1, 0
        RET

kfree:
        RET

; =============================================================================
; uart_putchar — envia R1[7:0] pela UART (busy-wait)
; =============================================================================
uart_putchar:
        MOVI  R26, UART_STATUS
uart_putchar_wait:
        LW    R27, R26, 0
        ANDI  R27, R27, UART_TX_READY
        BEQ   R27, R0, uart_putchar_wait
        MOVI  R27, UART_TXDATA
        SW    R1, R27, 0
        RET

; =============================================================================
; uart_getchar — le R1[7:0] da UART (busy-wait)
; =============================================================================
uart_getchar:
        MOVI  R26, UART_STATUS
uart_getchar_wait:
        LW    R27, R26, 0
        ANDI  R27, R27, 0x2
        BEQ   R27, R0, uart_getchar_wait
        MOVI  R27, 0xFF01
        LW    R1, R27, 0
        ANDI  R1, R1, 0xFF
        RET

; =============================================================================
; uart_puts — envia string terminada em zero (R1 = ponteiro)
; =============================================================================
uart_puts:
        PUSH  R31
        MOV   R26, R1
uart_puts_loop:
        LW    R27, R26, 0
        BEQ   R27, R0, uart_puts_done
        MOV   R1, R27
        CALL  uart_putchar
        ADDI  R26, R26, 1
        JMP   uart_puts_loop
uart_puts_done:
        POP   R31
        RET

; =============================================================================
; uart_puthex — imprime R1 como 8 hex digits
; =============================================================================
uart_puthex:
        PUSH  R31
        PUSH  R4
        PUSH  R5
        PUSH  R6
        MOV   R4, R1
        MOVI  R1, 0x30
        CALL  uart_putchar
        MOVI  R1, 0x78
        CALL  uart_putchar
        MOVI  R5, 28
uart_puthex_loop:
        BLT   R5, R0, uart_puthex_done
        SHR   R6, R4, R5
        ANDI  R6, R6, 0xF
        MOVI  R1, 10
        BLT   R6, R1, uart_puthex_digit
        ADDI  R6, R6, 55
        JMP   uart_puthex_emit
uart_puthex_digit:
        ADDI  R6, R6, 0x30
uart_puthex_emit:
        MOV   R1, R6
        CALL  uart_putchar
        ADDI  R5, R5, -4
        JMP   uart_puthex_loop
uart_puthex_done:
        POP   R6
        POP   R5
        POP   R4
        POP   R31
        RET

; =============================================================================
; idle_process — PID 0
; =============================================================================
idle_process:
        NOP
        JMP   idle_process

; =============================================================================
; demo_process — PID 1: calcula Fibonacci(10) e imprime via UART
; =============================================================================
demo_process:
        MOVI  R2, 0
        MOVI  R3, 1
        MOVI  R4, 8
demo_fib_loop:
        BEQ   R4, R0, demo_fib_done
        ADD   R5, R2, R3
        MOV   R2, R3
        MOV   R3, R5
        ADDI  R4, R4, -1
        JMP   demo_fib_loop
demo_fib_done:
        MOV   R1, R3
        CALL  uart_puthex
        MOVI  R1, 0x0A
        CALL  uart_putchar
        MOVI  R1, 0
        SYSCALL

; =============================================================================
; Strings de mensagem (words = chars ASCII, terminadas em 0)
; =============================================================================
msg_boot:
        .word 0x45, 0x64, 0x75, 0x52, 0x49, 0x53, 0x43, 0x2D
        .word 0x33, 0x32, 0x76, 0x32, 0x20, 0x4B, 0x65, 0x72
        .word 0x6E, 0x65, 0x6C, 0x20, 0x4F, 0x4B, 0x0A, 0x00

msg_illegal:
        .word 0x49, 0x4C, 0x4C, 0x45, 0x47, 0x41, 0x4C, 0x0A, 0x00

msg_align:
        .word 0x41, 0x4C, 0x49, 0x47, 0x4E, 0x0A, 0x00

msg_pgfault:
        .word 0x50, 0x47, 0x46, 0x41, 0x55, 0x4C, 0x54, 0x0A, 0x00

msg_break:
        .word 0x42, 0x52, 0x4B, 0x0A, 0x00
