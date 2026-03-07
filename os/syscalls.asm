; ===========================================================================
; syscalls.asm — Tabela de syscalls do Micro-Kernel EduRISC-16
;
; Convenção de chamada de sistema:
;   1. Coloque o número da syscall em R0
;   2. Argumentos em R1, R2 (se houver)
;   3. Execute:  CALL SYS_DISPATCH    (endereço definido em kernel.asm)
;   4. Resultado em R0 após retorno
;
; Tabela de syscalls:
; ┌────┬────────────────┬──────────────────────────────────────────────────┐
; │ N° │ Nome           │ Descrição                                        │
; ├────┼────────────────┼──────────────────────────────────────────────────┤
; │  0 │ SYS_HALT       │ Para a CPU                                       │
; │  1 │ SYS_PRINT      │ "Imprime" R1 (capturado pelo depurador)          │
; │  2 │ SYS_ALLOC      │ Aloca R1 palavras na heap; retorna endereço em R0│
; │  3 │ SYS_COPY       │ Copia R2 palavras de endereço R1 para R0         │
; │  4 │ SYS_MEMSET     │ Preenche R2 palavras a partir de R0 com R1       │
; └────┴────────────────┴──────────────────────────────────────────────────┘
;
; Heap simples: cresce para cima a partir de HEAP_BASE = 0x0800
;               controlado pelo ponteiro HEAP_PTR
; ===========================================================================

        .ORG 0x050              ; área de syscalls (contínua ao kernel)

; ===========================================================================
; Constantes de syscall
; ===========================================================================

SYSCALL_HALT    = 0
SYSCALL_PRINT   = 1
SYSCALL_ALLOC   = 2
SYSCALL_COPY    = 3
SYSCALL_MEMSET  = 4

; ===========================================================================
; SYS_ALLOC — aloca R1 palavras e retorna ponteiro em R0
;
; Algoritmo (bump allocator):
;   R0 = HEAP_PTR
;   HEAP_PTR += R1
;   return R0
; ===========================================================================

        .ORG 0x050

SYS_ALLOC_IMPL:
        ; R3 = endereço de HEAP_PTR
        LOAD  R3, [R0+64]       ; R3 = HEAP_PTR_ADDR (endereço da variável)

        ; R0 = *R3  (valor atual do ponteiro de heap)
        LOAD  R0, [R3+0]

        ; R4 = R0 + R1  (novo ponteiro após alocação)
        ADD   R4, R0, R1

        ; Verifica overflow: R4 >= HEAP_LIMIT ?
        LOAD  R5, [R0+65]       ; R5 = HEAP_LIMIT = 0x0E00
        SUB   R5, R5, R4
        ; Se R5 < 0 (borrow), heap cheia → retorna 0xFFFF
        ; (simplificado: sem verificação de carry nesta versão)

        ; *R3 = R4  (salva novo ponteiro)
        STORE [R3+0], R4

        ; R0 já tem o endereço alocado
        RET

; ===========================================================================
; SYS_COPY_IMPL — copia R2 palavras de addr R1 para addr R0
;
; Algoritmos:
;   for i in range(R2): mem[R0+i] = mem[R1+i]
; ===========================================================================

        .ORG 0x060

SYS_COPY_IMPL:
        ; R3 = destino (R0), R4 = fonte (R1), R5 = contador (R2)
        ; (como R0 será sobrescrito pelo LOAD, preservamos em R3)
        ADD   R3, R0, R0        ; R3 = R0 (dst) — usa ADD R3,R0,R0 com zero
        ; Nota: ADD Rd, Rs, Rs não é "move" seguro se R0 não for 0.
        ; Versão segura: XOR R6,R6,R6; ADD R3,R0,R6
        XOR   R6, R6, R6
        ADD   R3, R0, R6        ; R3 = dst
        ADD   R4, R1, R6        ; R4 = src
        ADD   R5, R2, R6        ; R5 = count

COPY_LOOP:
        XOR   R6, R5, R5        ; testa R5
        JZ    COPY_DONE

        LOAD  R7, [R4+0]        ; R7 = mem[src]
        STORE [R3+0], R7        ; mem[dst] = R7

        LOAD  R8, [R0+66]       ; R8 = 1
        ADD   R4, R4, R8
        ADD   R3, R3, R8
        SUB   R5, R5, R8

        JMP   COPY_LOOP

COPY_DONE:
        RET

; ===========================================================================
; SYS_MEMSET_IMPL — preenche R2 palavras a partir de R0 com valor R1
; ===========================================================================

        .ORG 0x070

SYS_MEMSET_IMPL:
        XOR   R6, R6, R6
        ADD   R3, R0, R6        ; R3 = dst
        ADD   R4, R2, R6        ; R4 = count

MEMSET_LOOP:
        XOR   R5, R4, R4
        JZ    MEMSET_DONE

        STORE [R3+0], R1        ; mem[dst] = valor

        LOAD  R6, [R0+66]       ; R6 = 1
        ADD   R3, R3, R6
        SUB   R4, R4, R6

        JMP   MEMSET_LOOP

MEMSET_DONE:
        RET

; ===========================================================================
; Tabela de despacho estendida (complementa SYS_DISPATCH do kernel.asm)
; Para syscalls 2, 3, 4:
; ===========================================================================

        .ORG 0x040

SYS_DISPATCH_EXT:
        ; Checa syscall 2
        LOAD  R3, [R0+67]      ; R3 = 2
        SUB   R3, R0, R3
        JZ    SYS_ALLOC_IMPL

        ; Checa syscall 3
        LOAD  R3, [R0+68]      ; R3 = 3
        SUB   R3, R0, R3
        JZ    SYS_COPY_IMPL

        ; Checa syscall 4
        LOAD  R3, [R0+69]      ; R3 = 4
        SUB   R3, R0, R3
        JZ    SYS_MEMSET_IMPL

        ; Desconhecida → R0 = 0xFFFF
        LOAD  R0, [R0+70]
        RET

; ===========================================================================
; Dados do syscall handler (a partir de 0x080)
; Offset 64..70 a partir do base (R0=0)
; ===========================================================================

        .ORG 0x040

                                ; (deixamos espaço — os offsets são do kernel.asm)
        .ORG 0x080

HEAP_PTR_VAR:   .WORD 0x0800   ; heap começa em 0x0800
HEAP_LIMIT_VAR: .WORD 0x0E00   ; heap termina antes de 0x0E00
CONST_ONE_SC:   .WORD 1        ; constante 1
CONST_TWO_SC:   .WORD 2        ; constante 2
CONST_THREE_SC: .WORD 3        ; constante 3
CONST_FOUR_SC:  .WORD 4        ; constante 4
CONST_FFFF_SC:  .WORD 0xFFFF  ; código de erro

; ===========================================================================
; EXEMPLO DE USO DAS SYSCALLS (programa de usuário)
;
; Aloca buffer, preenche com 0xABCD, copia para outro endereço:
;
;     ; Aloca 8 palavras
;     LOAD  R1, [R0+??]   ; R1 = 8
;     LOAD  R0, [R0+??]   ; R0 = SYSCALL_ALLOC (2)
;     CALL  SYS_DISPATCH
;     ; R0 agora tem o endereço alocado (ex: 0x0800)
;
;     ; Preenche buffer com 0xABCD
;     ADD   R3, R0, R0    ; dst = R0
;     LOAD  R1, [R0+??]   ; R1 = 0xABCD
;     LOAD  R2, [R0+??]   ; R2 = 8
;     LOAD  R0, [R0+??]   ; R0 = SYSCALL_MEMSET (4)
;     CALL  SYS_DISPATCH
;
;     ; Imprime R3 (endereço do buffer)
;     ADD   R1, R3, R0    ; R1 = endereço
;     LOAD  R0, [R0+??]   ; R0 = SYSCALL_PRINT (1)
;     CALL  SYS_DISPATCH
;
;     ; HLT
;     HLT
;
; A string completa com offsets reais depende do link-editor (não incluso).
; ===========================================================================
