; ===========================================================================
; syscalls.asm - Syscalls legadas do Micro-Kernel EduRISC-16
;
; ATENCAO:
; Este arquivo pertence a uma trilha historica/educacional anterior ao
; ambiente principal EduRISC-32v2. Ele permanece no repositorio como material
; de referencia e compatibilidade, nao como definicao oficial de syscalls do
; kernel atual.
;
; Convencao de chamada de sistema:
;   1. Coloque o numero da syscall em R0
;   2. Argumentos em R1, R2 (se houver)
;   3. Execute:  CALL SYS_DISPATCH    (endereco definido em kernel.asm)
;   4. Resultado em R0 apos retorno
;
; Tabela de syscalls:
;   0 - SYS_HALT    : para a CPU
;   1 - SYS_PRINT   : exibe R1 (capturado pelo depurador/simulador)
;   2 - SYS_ALLOC   : aloca R1 palavras; retorna endereco em R0
;   3 - SYS_COPY    : copia R2 palavras de endereco R1 para R0
;   4 - SYS_MEMSET  : preenche R2 palavras em endereco R0 com R1
;
; Heap simples: cresce para cima a partir de HEAP_BASE = 0x0800
;               controlado pelo ponteiro HEAP_PTR_VAR em 0x0080
;
; IMPORTANTE: pressupoe R13 = 0 (definido em KERNEL_START do kernel.asm).
; Constantes do kernel acessiveis via [R13+N]:
;   [R13+8]  = 1      (CONST_ONE)
;   [R13+9]  = 0xFFFF (CONST_NEG1)
;   [R13+10] = 2      (CONST_TWO   -- numero syscall SYS_ALLOC)
;   [R13+11] = 3      (CONST_THREE -- numero syscall SYS_COPY)
;   [R13+12] = 4      (CONST_FOUR  -- numero syscall SYS_MEMSET)
;   [R13+13] = 0x0080 (CONST_HEAP_PTR -- endereco de HEAP_PTR_VAR)
;   [R13+14] = 0x0E00 (CONST_HEAP_LIM -- limite superior do heap)
; ===========================================================================

; ===========================================================================
; SYS_DISPATCH_EXT -- extensao do despachante para syscalls 2, 3 e 4
; Chamado pelo SYS_DISPATCH do kernel quando R0 >= 2.
; Entrada:  R0 = numero da syscall
; Retorno:  R0 = resultado
; ===========================================================================

        .ORG 0x040

SYS_DISPATCH_EXT:
        ; Testa R0 == 2 -> SYS_ALLOC
        LOAD  R3, [R13+10]     ; R3 = CONST_TWO = 2
        SUB   R3, R0, R3       ; R3 = R0 - 2; Z se R0==2
        JZ    SYS_ALLOC_IMPL

        ; Testa R0 == 3 -> SYS_COPY
        LOAD  R3, [R13+11]     ; R3 = CONST_THREE = 3
        SUB   R3, R0, R3       ; R3 = R0 - 3; Z se R0==3
        JZ    SYS_COPY_IMPL

        ; Testa R0 == 4 -> SYS_MEMSET
        LOAD  R3, [R13+12]     ; R3 = CONST_FOUR = 4
        SUB   R3, R0, R3       ; R3 = R0 - 4; Z se R0==4
        JZ    SYS_MEMSET_IMPL

        ; Syscall desconhecida -> retorna 0xFFFF
        LOAD  R0, [R13+9]      ; R0 = CONST_NEG1 = 0xFFFF
        RET

; ===========================================================================
; SYS_ALLOC_IMPL -- bump allocator
;
; Entrada:  R1 = palavras a alocar
; Saida:    R0 = ponteiro para bloco alocado
;
; Algoritmo:
;   R3 = 0x0080 via [R13+13]  -- endereco de HEAP_PTR_VAR
;   R0 = mem[R3]              -- heap pointer atual
;   R4 = R0 + R1              -- novo heap pointer
;   mem[R3] = R4              -- atualiza heap pointer
;   retorna R0                -- endereco do bloco alocado
; ===========================================================================

        .ORG 0x050

SYS_ALLOC_IMPL:
        LOAD  R3, [R13+13]     ; R3 = 0x0080 (endereco de HEAP_PTR_VAR)
        LOAD  R0, [R3+0]       ; R0 = heap pointer atual
        ADD   R4, R0, R1       ; R4 = novo heap pointer
        STORE R4, [R3+0]       ; salva novo heap pointer
        RET

; ===========================================================================
; SYS_COPY_IMPL -- copia R2 palavras do endereco R1 para R0
;
; ADD Rd, Rs, R13 equivale a MOV Rd, Rs (R13=0 permanente no kernel)
; ===========================================================================

        .ORG 0x060

SYS_COPY_IMPL:
        LOAD  R6, [R13+8]      ; R6 = 1 (CONST_ONE)
        ADD   R3, R0, R13      ; R3 = dst
        ADD   R4, R1, R13      ; R4 = src
        ADD   R5, R2, R13      ; R5 = count

COPY_LOOP:
        ADD   R7, R5, R13      ; R7 = count; Z se count == 0
        JZ    COPY_DONE

        LOAD  R7, [R4+0]       ; R7 = mem[src]
        STORE R7, [R3+0]       ; mem[dst] = R7
        ADD   R4, R4, R6       ; src++
        ADD   R3, R3, R6       ; dst++
        SUB   R5, R5, R6       ; count--

        JMP   COPY_LOOP

COPY_DONE:
        RET

; ===========================================================================
; SYS_MEMSET_IMPL -- preenche R2 palavras a partir de R0 com valor R1
; ===========================================================================

        .ORG 0x070

SYS_MEMSET_IMPL:
        LOAD  R6, [R13+8]      ; R6 = 1 (CONST_ONE)
        ADD   R3, R0, R13      ; R3 = dst
        ADD   R4, R2, R13      ; R4 = count

MEMSET_LOOP:
        ADD   R5, R4, R13      ; R5 = count; Z se count == 0
        JZ    MEMSET_DONE

        STORE R1, [R3+0]       ; mem[dst] = valor
        ADD   R3, R3, R6       ; dst++
        SUB   R4, R4, R6       ; count--

        JMP   MEMSET_LOOP

MEMSET_DONE:
        RET

; ===========================================================================
; HEAP_PTR_VAR -- ponteiro do heap (endereco 0x080)
; Inicializado com HEAP_BASE = 0x0800
; ===========================================================================

        .ORG 0x080

HEAP_PTR_VAR:   .WORD 0x0800   ; heap comeca em 0x0800
