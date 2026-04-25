; soma_1_a_n.asm — Soma de 1 até N usando loop
;
; Resultado: R2 = N*(N+1)/2  (para N=10 → 55)
; Registro: R1 = N (contador), R2 = acumulador

        .org 0x000000
        MOVI  R1, 10       ; R1 = N = 10
        MOVI  R2, 0        ; R2 = acc = 0
LOOP:
        ADD   R2, R2, R1   ; acc += i
        ADDI  R1, R1, -1   ; i--
        BNE   R1, R0, LOOP ; enquanto i != 0
        HLT                ; R2 = 55
