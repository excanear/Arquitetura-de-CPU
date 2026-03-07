; ===========================================================================
; kernel.asm — Micro-Kernel EduRISC-16
;
; Mapa de memória:
;   0x000 — Vetor de boot:         JMP KERNEL_START
;   0x001 — Vetor de interrupção:  JMP KERNEL_START (placeholder)
;   0x002–0x009 — Tabela de constantes do kernel (8 words)
;   0x010 — Início do código do kernel
;   0x100 — Base do espaço de usuário (destino do loader)
;   0x200 — Programa demo raw (copiado pelo loader para 0x100)
;
; Mapa de registradores do kernel:
;   R0  — Temporário / retorno de syscall
;   R1  — Argumento 1 de syscall
;   R2  — Argumento 2 de syscall
;   R3  — Temporário interno
;   R13 — Zero base (= 0 sempre; acessa tabela de constantes via [R13+N])
;   R14 — Stack pointer (cresce para baixo a partir de 0x0FFF)
;   R15 — Link register (endereço de retorno após CALL)
;
; Tabela de constantes (indexada por [R13+N], R13=0):
;   [R13+2] = 0x0FFF — valor inicial do stack pointer
;   [R13+3] = 0x00ED — número mágico de boot (banner)
;   [R13+4] = 0x0001 — número da syscall SYS_PRINT
;   [R13+5] = 0x0100 — DST_BASE (destino do loader)
;   [R13+6] = 0x0200 — SRC_BASE (fonte do loader)
;   [R13+7] = 0x0010 — N padrão (palavras a copiar = 16)
;   [R13+8] = 0x0001 — constante 1
;   [R13+9] = 0xFFFF — constante 0xFFFF / -1
;
; Syscalls (número em R0 antes de CALL SYS_DISPATCH):
;   0 — SYS_HALT  : para a CPU
;   1 — SYS_PRINT : o simulador captura R1 e exibe antes de parar
; ===========================================================================

        .ORG 0x000

; ---- Vetor de boot ----
BOOT:   JMP  KERNEL_START      ; 0x000 — sempre o primeiro endereço executado

; ---- Vetor de interrupção (placeholder) ----
        JMP  KERNEL_START      ; 0x001 — IRQ não implementado nesta versão

; ===========================================================================
; TABELA DE CONSTANTES DO KERNEL
; Acessível via LOAD Rd, [R13+N] onde R13 = 0 permanentemente.
; Offsets N em 2–9 garantem campo de 4 bits (máx 15) do formato M-type.
; ===========================================================================

        .ORG 0x002

CONST_SP_INIT:   .WORD 0x0FFF   ; [R13+2] valor inicial do stack pointer
CONST_BANNER:    .WORD 0x00ED   ; [R13+3] número mágico de boot
CONST_SYS_PRINT: .WORD 0x0001   ; [R13+4] número da syscall SYS_PRINT
CONST_DST_BASE:  .WORD 0x0100   ; [R13+5] endereço destino do loader
CONST_SRC_BASE:  .WORD 0x0200   ; [R13+6] endereço fonte do loader
CONST_N:         .WORD 0x0010   ; [R13+7] número de palavras a copiar (16)
CONST_ONE:       .WORD 0x0001   ; [R13+8] constante 1
CONST_NEG1:      .WORD 0xFFFF   ; [R13+9] constante 0xFFFF / -1

; ===========================================================================
; KERNEL_START — inicialização do sistema
; ===========================================================================

        .ORG 0x010

KERNEL_START:
        ; R13 = 0 permanente (zero base para acesso à tabela de constantes)
        XOR   R13, R13, R13

        ; R14 = stack pointer inicial (0x0FFF)
        LOAD  R14, [R13+2]     ; R14 = CONST_SP_INIT = 0x0FFF

        ; Limpa registradores de usuário R0–R6
        XOR   R0,  R0,  R0
        XOR   R1,  R1,  R1
        XOR   R2,  R2,  R2
        XOR   R3,  R3,  R3
        XOR   R4,  R4,  R4
        XOR   R5,  R5,  R5
        XOR   R6,  R6,  R6

        ; Copia programa de usuário de SRC_BASE para DST_BASE
        CALL  LOADER

        ; Salta para início do espaço de usuário
        JMP   0x100

; ===========================================================================
; LOADER
; Copia N palavras de endereço SRC para endereço DST
;   SRC = 0x200, DST = 0x100, N = tamanho em 0x1FF
; ===========================================================================

LOADER:
        LOAD  R3, [R13+5]      ; R3 = DST_BASE = 0x0100
        LOAD  R4, [R13+6]      ; R4 = SRC_BASE = 0x0200
        LOAD  R5, [R13+7]      ; R5 = N = 16
        LOAD  R6, [R13+8]      ; R6 = 1 (incremento)

LOADER_LOOP:
        ; Testa R5 == 0: ADD R0,R5,R13 → R0=R5; Z flag ligado se R5==0
        ADD   R0, R5, R13      ; R0 = R5 + 0; flags refletem R5
        JZ    LOADER_DONE

        ; R7 = mem[R4] — lê palavra fonte
        LOAD  R7, [R4+0]

        ; mem[R3] = R7 — escreve no destino
        STORE R7, [R3+0]

        ; R4++, R3++, R5--
        ADD   R4, R4, R6
        ADD   R3, R3, R6
        SUB   R5, R5, R6

        JMP   LOADER_LOOP

LOADER_DONE:
        RET

; ===========================================================================
; SYS_DISPATCH — despacha syscall pelo número em R0
; ===========================================================================

SYS_DISPATCH:
        ; Testa R0 == 0 → SYS_HALT
        ; ADD Rd,Rs,R13 copia Rs e seta Z se Rs==0 (R13=0 permanente)
        ADD   R3, R0, R13      ; R3 = R0; Z se R0 == 0
        JZ    SYS_HALT

        ; Testa R0 == 1 → SYS_PRINT
        LOAD  R3, [R13+8]      ; R3 = CONST_ONE = 1
        SUB   R3, R0, R3       ; R3 = R0 - 1; Z se R0 == 1
        JZ    SYS_PRINT

        ; Syscall desconhecida → retorna 0xFFFF
        LOAD  R0, [R13+9]      ; R0 = CONST_NEG1 = 0xFFFF
        RET

; ===========================================================================
; SYS_HALT — para a CPU
; ===========================================================================

SYS_HALT:
        HLT

; ===========================================================================
; SYS_PRINT — "imprime" R1 (o simulador loga valor antes de HLT)
; Convenção: o depurador pode interceptar e exibir R1
; ===========================================================================

SYS_PRINT:
        ; O simulador/depurador intercepta este ponto e exibe o valor de R1
        HLT                    ; captura do simulador
        RET

; ===========================================================================
; PROGRAMA DEMO — em 0x200 (copiado pelo loader para 0x100)
;
; Calcula N iterações de Fibonacci partindo de F0=0, F1=1.
; NOTA EDUCACIONAL: este bloco usa opcodes binários (.WORD) para ilustrar
; que mover código para outro endereço (0x200→0x100) quebra branches
; absolutos — demonstração clássica do problema de relocação de código.
; ===========================================================================

        .ORG 0x200

        ; R1 = 0 (F_n-2), R2 = 1 (F_n-1), R3 = N = 8, R4 = 1
        .WORD 0x8110            ; LOAD R1, [R0+16]  → R1=0
        .WORD 0x8211            ; LOAD R2, [R0+17]  → R2=1
        .WORD 0x8312            ; LOAD R3, [R0+18]  → R3=8
        .WORD 0x8413            ; LOAD R4, [R0+19]  → R4=1

        ; Loop: R5 = R1 + R2; R1 = R2; R2 = R5; R3--
        .WORD 0x0512            ; ADD R5, R1, R2
        .WORD 0x0125            ; ADD R1, R2, R5 — ERRO INTENCIONAL: veja abaixo
        .WORD 0x0251            ; ADD R2, R5, R1

        ; R3--
        .WORD 0x1334            ; SUB R3, R3, R4

        ; JNZ loop (volta 4 posições: PC=0x100+8=0x108, volta para 0x104)
        .WORD 0xC104            ; JNZ 0x104

        ; HLT — resultado em R2
        .WORD 0xF000            ; HLT

        ; Dados: offset 16..19 a partir de base 0x200+0x10 = 0x210
        .ORG 0x210
        .WORD 0                 ; R1 = 0
        .WORD 1                 ; R2 = 1
        .WORD 8                 ; R3 = 8
        .WORD 1                 ; R4 = 1
