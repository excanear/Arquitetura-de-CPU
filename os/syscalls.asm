; =============================================================================
; syscalls.asm — Tabela de Syscalls EduRISC-32v2
;
; Documentacao das chamadas de sistema do kernel EduRISC-32v2.
; A implementacao real esta em kernel.asm (handler exc_syscall / IVT[3]).
;
; Como usar syscalls em assembly EduRISC-32v2:
;   1. Coloque o numero da syscall em R1
;   2. Coloque os argumentos em R2, R3 (se houver)
;   3. Execute: SYSCALL
;   4. O resultado retorna em R1 apos o ERET do handler
;
; Tabela de syscalls:
;
;   Num  Nome         Args              Retorno         Descricao
;   ---  -----------  ----------------  --------------  -----------------------
;   0    SYS_EXIT     —                 (nao retorna)   Encerra processo atual
;   1    SYS_WRITE    R2=char           R1=0            Envia char pela UART
;   2    SYS_READ     —                 R1=char         Le char da UART
;   3    SYS_MALLOC   R2=words          R1=ptr ou 0     Aloca N words no heap
;   4    SYS_FREE     R2=ptr            R1=0            Libera bloco (no-op nesta versao)
;   5    SYS_YIELD    —                 —               Cede CPU (preempcao cooperativa)
;   6    SYS_GETPID   —                 R1=pid          Retorna PID do processo atual
;   7    SYS_HEAPSTAT —                 R1=bytes livres Diagnostico do heap
;   8    SYS_UPTIME   —                 R1=ciclos       Retorna CSR[CYCLE]
;
; Vetores de excecao (IVT — base em CSR[1]):
;
;   IVT[0]  exc_illegal    — instrucao ilegal (opcode invalido)
;   IVT[1]  exc_align      — acesso nao alinhado a memoria
;   IVT[2]  exc_page_fault — page fault (MMU)
;   IVT[3]  exc_syscall    — SYSCALL (dispatcher de chamadas de sistema)
;   IVT[4]  exc_breakpoint — instrucao BREAK (depuracao)
;   IVT[5]  irq_timer      — interrupcao de timer (preempcao)
;   IVT[6]  irq_uart       — interrupcao de UART
;   IVT[7-15] exc_reserved — reservado (causa HLT se atingido)
;
; Codigos de CAUSE (CSR[3][3:0]):
;   0  CAUSE_ILLEGAL  — instrucao ilegal
;   1  CAUSE_ALIGN    — erro de alinhamento
;   2  CAUSE_PGFAULT  — page fault
;   3  CAUSE_SYSCALL  — SYSCALL
;   4  CAUSE_BREAK    — BREAK
;   5  CAUSE_TIMER    — timer (IRQ, bit[31]=1)
;   6  CAUSE_UART     — UART  (IRQ, bit[31]=1)
;
; Codigos de STATUS (CSR[0]):
;   bit 0  IE  — Interrupt Enable (1=habilitado)
;   bit 1  KU  — Kernel/User mode (0=kernel, 1=user)
;   bits 7:4  IM[3:0] — Interrupt Mask (1=permite)
;
; =============================================================================

; ---------------------------------------------------------------------------
; Macros uteis para uso em programas assembly
; ---------------------------------------------------------------------------

; syscall_exit: encerra o processo atual
; Uso: CALL syscall_exit (ou use diretamente SYSCALL apos MOVI R1, 0)
syscall_exit_stub:
        MOVI  R1, 0
        SYSCALL
        ; nao retorna

; syscall_write: envia caractere em R2 pela UART
syscall_write_stub:
        MOVI  R1, 1
        SYSCALL
        RET

; syscall_read: le caractere da UART, retorna em R1
syscall_read_stub:
        MOVI  R1, 2
        SYSCALL
        RET

; syscall_malloc: aloca R2 words; retorna ponteiro em R1
syscall_malloc_stub:
        MOVI  R1, 3
        SYSCALL
        RET

; syscall_free: libera bloco em R2
syscall_free_stub:
        MOVI  R1, 4
        SYSCALL
        RET

; syscall_yield: cede CPU voluntariamente
syscall_yield_stub:
        MOVI  R1, 5
        SYSCALL
        RET

; syscall_getpid: retorna PID do processo atual em R1
syscall_getpid_stub:
        MOVI  R1, 6
        SYSCALL
        RET

; syscall_uptime: retorna contador de ciclos (CSR[CYCLE]) em R1
syscall_uptime_stub:
        MOVI  R1, 8
        SYSCALL
        RET
