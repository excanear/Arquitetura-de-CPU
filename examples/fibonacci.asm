; fibonacci.asm — Calcula o N-ésimo número de Fibonacci
;
; Entrada:  R1 = N (índice, começa em 0)
; Saída:    R3 = Fib(N)
; Exemplo:  N=10 → Fib(10) = 55

        .org 0x000000
        MOVI  R1, 10       ; N = 10
        MOVI  R2, 0        ; a = Fib(0) = 0
        MOVI  R3, 1        ; b = Fib(1) = 1
        MOVI  R4, 0        ; contador

LOOP:
        BEQ   R4, R1, DONE ; se contador == N, termina
        MOV   R5, R3       ; tmp = b
        ADD   R3, R2, R3   ; b = a + b  →  Fib(n+1)
        MOV   R2, R5       ; a = tmp (antigo b)
        ADDI  R4, R4, 1    ; contador++
        JMP   LOOP

DONE:
        ; R3 = Fib(N)
        HLT
