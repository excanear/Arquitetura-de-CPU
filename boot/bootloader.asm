; ============================================================================
; bootloader.asm  —  Bootloader EduRISC-32v2
;
; Endereço de entrada: 0x000000  (reset vector)
; Tamanho máximo: 256 words (primeiras 256 posições de IMEM)
;
; Responsabilidades:
;   1. Inicializar stack pointer (R30 = SP)
;   2. Zerar registradores de uso geral (R1-R29)
;   3. Configurar CSR STATUS  (IE=0 durante init, IM=0xFF)
;   4. Configurar IVT          (endereço base dos vetores de exceção)
;   5. Inicializar BSS          (zerar segmento de dados não inicializados)
;   6. Copiar .data de ROM→RAM se necessário (aqui: IMEM = ROM, DMEM = RAM)
;   7. Chamar kernel_main
; ============================================================================

; ---------------------------------------------------------------------------
; Constantes de layout de memória
;   SP_INIT    = 0x0FFFF  (topo da pilha, espaço de 256KB de DMEM)
;   IVT_BASE   = 0x000100 (tabela de vetores logo após bootloader)
;   BSS_START  = 0x000800 (início do segmento BSS em DMEM)
;   BSS_END    = 0x001000 (fim do BSS)
;   KERNEL_ENTRY = 0x000200 (endereço de kernel_main em IMEM)
; ---------------------------------------------------------------------------

    .section .text
    .global  _start

_start:
    ; -----------------------------------------------------------------------
    ; 1. Configurar SP (R30) e LR (R31) iniciais
    ; -----------------------------------------------------------------------
    MOVHI   R30, 0x010          ; R30[31:21] = 0x010 → parte alta de 0x0FFFF0
    ORI     R30, R30, 0xFFF0    ; R30 = 0x000FFFF0 (stack pointer inicial)
    MOVI    R31, 0               ; LR = 0 (retorno do kernel = halt)

    ; -----------------------------------------------------------------------
    ; 2. Zerar R1–R29
    ; -----------------------------------------------------------------------
    MOV     R1,  R0
    MOV     R2,  R0
    MOV     R3,  R0
    MOV     R4,  R0
    MOV     R5,  R0
    MOV     R6,  R0
    MOV     R7,  R0
    MOV     R8,  R0
    MOV     R9,  R0
    MOV     R10, R0
    MOV     R11, R0
    MOV     R12, R0
    MOV     R13, R0
    MOV     R14, R0
    MOV     R15, R0
    MOV     R16, R0
    MOV     R17, R0
    MOV     R18, R0
    MOV     R19, R0
    MOV     R20, R0
    MOV     R21, R0
    MOV     R22, R0
    MOV     R23, R0
    MOV     R24, R0
    MOV     R25, R0
    MOV     R26, R0
    MOV     R27, R0
    MOV     R28, R0
    MOV     R29, R0

    ; -----------------------------------------------------------------------
    ; 3. Configurar CSR STATUS
    ;    IE=0 (interrupções desabilitadas durante boot)
    ;    KU=0 (modo kernel)
    ;    IM=0xFF (todas as máscaras habilitadas para quando ativar)
    ; -----------------------------------------------------------------------
    MOVI    R1, 0x00FF           ; STATUS = IM=0xFF, IE=0, KU=0
    MTC     R1, 0                ; CSR[0] = STATUS

    ; -----------------------------------------------------------------------
    ; 4. Configurar IVT (base dos vetores de exceção)
    ; -----------------------------------------------------------------------
    MOVI    R1, 0x0100           ; IVT_BASE = 0x000100
    MTC     R1, 1                ; CSR[1] = IVT

    ; -----------------------------------------------------------------------
    ; 5. Zerar BSS (DMEM[BSS_START..BSS_END-1])
    ; -----------------------------------------------------------------------
    MOVI    R2, 0x0800           ; R2 = BSS_START
    MOVI    R3, 0x1000           ; R3 = BSS_END
bss_loop:
    BEQ     R2, R3, bss_done     ; se R2==R3 terminar
    SW      R0, R2, 0            ; DMEM[R2] = 0
    ADDI    R2, R2, 1            ; R2++
    JMP     bss_loop
bss_done:

    ; -----------------------------------------------------------------------
    ; 6. Tabela de vetores de exceção (em IVT_BASE = instr 0x100)
    ;    Cada entrada é um JMP absolute para o handler correspondente
    ;    Ordem: ILLEGAL, DIV_ZERO, OVERFLOW, SYSCALL, BREAK,
    ;           IFETCH_PF, LOAD_PF, STORE_PF, UNALIGNED,
    ;           INT_TIMER, INT_EXT[0-6]
    ; -----------------------------------------------------------------------
    ; OBS: o assembler colocará os JMPs no endereço correto via .org
    ; Aqui apenas pulamos para kernel_main antes de alcançar a IVT

    ; -----------------------------------------------------------------------
    ; 7. Entrar no kernel
    ; -----------------------------------------------------------------------
    MOVI    R1, 0x01             ; STATUS |= IE=1 → habilitar interrupções
    MTC     R1, 0                ; CSR[0] = STATUS (IE=1)
    JMP     kernel_main          ; pular para kernel_main (0x000200)

    ; -----------------------------------------------------------------------
    ; Em caso de retorno inesperado do kernel: HLT
    ; -----------------------------------------------------------------------
    HLT

; ============================================================================
; Vetores de exceção (IVT_BASE = 0x000100)
; O hardware calcula: PC = IVT + cause_code
; ============================================================================
    .org    0x100
ivt_illegal:    JMP  exc_illegal
ivt_divzero:    JMP  exc_generic
ivt_overflow:   JMP  exc_generic
ivt_syscall:    JMP  exc_syscall
ivt_break:      JMP  exc_break
ivt_ifetch_pf:  JMP  exc_page_fault
ivt_load_pf:    JMP  exc_page_fault
ivt_store_pf:   JMP  exc_page_fault
ivt_unaligned:  JMP  exc_generic
ivt_timer:      JMP  isr_timer
ivt_ext0:       JMP  isr_ext
ivt_ext1:       JMP  isr_ext
ivt_ext2:       JMP  isr_ext
ivt_ext3:       JMP  isr_ext
ivt_ext4:       JMP  isr_ext
ivt_ext5:       JMP  isr_ext
ivt_ext6:       JMP  isr_ext

; ============================================================================
; Handlers de exceção mínimos
; ============================================================================
exc_illegal:
    MFC     R1, 3                ; R1 = CSR[CAUSE]
    PUSH    R1                   ; salvar causa na pilha (debug)
    JMP     exc_halt             ; haltar (sem OS para tratar)

exc_syscall:
    ; Despachado pelo kernel
    ERET

exc_break:
    ERET

exc_page_fault:
    MFC     R1, 3                ; R1 = CAUSE
    JMP     exc_halt

exc_generic:
    MFC     R1, 3
    JMP     exc_halt

exc_halt:
    HLT

isr_timer:
    PUSH    R1
    PUSH    R2
    ; Incrementar tick counter em DMEM[0x0FF0]
    MOVI    R1, 0x0FF0
    LW      R2, R1, 0
    ADDI    R2, R2, 1
    SW      R2, R1, 0
    POP     R2
    POP     R1
    ERET

isr_ext:
    ; Handlers de interrupção externa mínimos
    ERET
