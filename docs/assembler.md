# Assembler EduRISC-16 — Guia de Referência

## Introdução

O assembler EduRISC-16 é um assembler de dois passos que converte código assembly em binário de 16 bits. Ele suporta:

- Todas as 16 instruções da ISA
- Labels (rótulos) como alvos de salto
- Diretivas de montagem (`.ORG`, `.WORD`, `.DATA`)
- Comentários com `;`
- Saída em formato binário ou Intel HEX

---

## Uso

### Python API

```python
from assembler import Assembler

asm = Assembler()
words = asm.assemble("""
    .ORG 0x000
    LOAD R1, [R0+16]    ; carrega valor 5
    LOAD R2, [R0+17]    ; acumulador = 0
LOOP:
    ADD  R2, R2, R1     ; acc += i
    SUB  R1, R1, R3     ; i--
    JNZ  LOOP           ; se R1 != 0, repete
    HLT
    .ORG 0x010
    .WORD 5             ; dado: 5
    .WORD 0             ; dado: 0
""")
print(words)  # [lista de int de 16 bits]

# Salvar como binário
asm.write_binary(words, "programa.bin")

# Salvar como HEX (Intel HEX simplificado)
asm.write_hex(words, "programa.hex")

# Imprimir listagem
print(asm.listing(words, source))
```

### Linha de Comando (via main.py)

```bash
python main.py assemble programa.asm -o programa.hex
python main.py assemble programa.asm --binary -o programa.bin
python main.py assemble programa.asm --listing
```

---

## Sintaxe

### Comentários

```asm
; Comentário de linha inteira
ADD R1, R2, R3    ; Comentário no final da linha
```

### Labels (Rótulos)

```asm
LABEL:  instrução   ; label + instrução na mesma linha
OUTRO:              ; label sem instrução (na próxima linha)
        instrução
```

- Labels devem começar com letra ou `_`
- Insensível a maiúsculas/minúsculas
- O valor de um label é o **endereço** da instrução seguinte

### Registradores

Escritos como `R0`–`R15` (ou `r0`–`r15`):

```asm
ADD R3, R1, R2    ; operandos: rd, rs1, rs2
```

### Imediatos e Endereços

```asm
JMP  0x1A0        ; hexadecimal
JMP  256          ; decimal
JMP  MINHA_FUNC   ; símbolo (label)
```

---

## Instruções

### Aritméticas e Lógicas (Tipo R)

```asm
ADD  rd, rs1, rs2    ; rd ← rs1 + rs2
SUB  rd, rs1, rs2    ; rd ← rs1 - rs2
MUL  rd, rs1, rs2    ; rd ← rs1 × rs2 (16 LSBs)
DIV  rd, rs1, rs2    ; rd ← rs1 ÷ rs2
AND  rd, rs1, rs2    ; rd ← rs1 AND rs2
OR   rd, rs1, rs2    ; rd ← rs1 OR rs2
XOR  rd, rs1, rs2    ; rd ← rs1 XOR rs2
NOT  rd, rs1         ; rd ← NOT rs1
```

### Memória (Tipo M)

```asm
LOAD  rd, [base+offset]    ; rd ← mem[regs[base] + offset]
STORE [base+offset], rd    ; mem[regs[base] + offset] ← rd
```

Offset é um imediato de 4 bits (0–15).

### Controle de Fluxo (Tipo J)

```asm
JMP  addr              ; PC ← addr (incondicional)
JZ   addr              ; if rs1 == 0: PC ← addr
JNZ  addr              ; if rs1 != 0: PC ← addr
CALL addr              ; R15 ← PC+1; PC ← addr
```

> **Nota sobre JZ/JNZ:** O simulador testa o registrador `R1` por padrão como condição. Na prática, use `SUB R_result, Ra, Rb` e depois `JZ`/`JNZ` verificando `R_result`.

### Outros

```asm
RET                    ; PC ← R15
HLT                    ; para a CPU
```

---

## Diretivas

### `.ORG addr`

Define o endereço a partir do qual as instruções seguintes serão colocadas.

```asm
.ORG 0x100
    ; código começa em 0x100
```

### `.WORD valor`

Insere uma palavra de 16 bits na posição atual.

```asm
.ORG 0x200
DADOS:  .WORD 42
        .WORD 0x1234
        .WORD -1        ; 0xFFFF
```

### `.DATA label, valor`

Atalho para definir constante com label (equivale a label + `.WORD`):

```asm
.DATA N, 10
.DATA BASE, 0x300
```

---

## Exemplos Completos

### Soma de 1 a N

```asm
        .ORG 0x000
        LOAD R1, [R0+16]   ; R1 = N
        LOAD R2, [R0+17]   ; R2 = 0 (acumulador)
        LOAD R3, [R0+18]   ; R3 = 1 (decremento)
LOOP:   ADD  R2, R2, R1    ; acc += N
        SUB  R1, R1, R3    ; N--
        JNZ  LOOP          ; enquanto N != 0
        HLT                ; R2 = soma total

        .ORG 0x010
        .WORD 5            ; N
        .WORD 0            ; acumulador inicial
        .WORD 1            ; 1
```

Resultado em R2: 5+4+3+2+1 = **15**

---

### Fatorial de N (iterativo)

```asm
        .ORG 0x000
        LOAD R1, [R0+32]   ; R1 = N (ex: 5)
        LOAD R2, [R0+33]   ; R2 = 1 (resultado)
        LOAD R3, [R0+34]   ; R3 = 1

FACT:   XOR  R4, R1, R1    ; testa R1 (R4=0 se R1=0)
        JZ   FACT_END      ; if N==0: fim
        MUL  R2, R2, R1    ; resultado *= N
        SUB  R1, R1, R3    ; N--
        JMP  FACT

FACT_END:
        HLT                ; R2 = N!

        .ORG 0x020
        .WORD 5            ; N = 5 → resultado esperado: 120
        .WORD 1            ; resultado inicial
        .WORD 1
```

---

### Função com CALL/RET

```asm
        .ORG 0x000
MAIN:   LOAD R1, [R0+32]   ; argumento = 6
        CALL DOBRA          ; R0 = dobra(6) = 12
        HLT

; Função: dobra(R1) → R0 = 2 × R1
DOBRA:  ADD  R0, R1, R1    ; R0 = R1 + R1
        RET

        .ORG 0x020
        .WORD 6
```

---

## Listagem de Montagem

O assembler pode gerar uma listagem mostrando endereço, palavra codificada e instrução:

```
Addr  | Word  | Source
------+-------+---------------------------
0x000 | 0x810 | LOAD R1, [R0+16]
0x001 | 0x820 | LOAD R2, [R0+0]   ; acc
0x002 | 0x230 | ADD  R2, R2, R1
...
```

---

## Erros Comuns

| Mensagem                          | Causa                                      |
|-----------------------------------|--------------------------------------------|
| `Instrução desconhecida: FOO`     | Mnemônico não existe na ISA                |
| `Label não definido: LOOP`        | Rótulo usado mas nunca declarado           |
| `Valor muito grande: 0x1234 > 15` | Offset de LOAD/STORE excede 4 bits         |
| `Endereço fora do range: 0x2000`  | Instrução J com addr > 0xFFF              |
| `Esperado registrador, obteve 42` | Operando numérico onde se esperava Rn      |
