# ISA Legada EduRISC-16 — Referência Completa

> Status: legado educacional.
> A ISA principal suportada do repositório está em [docs/isa_spec.md](docs/isa_spec.md).

## Formato das Instruções

Todas as instruções têm **16 bits de largura fixa**. Existem três formatos:

### Tipo R — Operações Registrador-Registrador

```
 15  14  13  12 | 11  10   9   8 |  7   6   5   4 |  3   2   1   0
 ───────────────────────────────────────────────────────────────────
      OP [3:0]  │     rd [3:0]   │    rs1 [3:0]   │   rs2 [3:0]
```

Instruções R: `ADD`, `SUB`, `MUL`, `DIV`, `AND`, `OR`, `XOR`, `NOT`, `RET`, `HLT`

### Tipo M — Acesso à Memória (base + offset)

```
 15  14  13  12 | 11  10   9   8 |  7   6   5   4 |  3   2   1   0
 ───────────────────────────────────────────────────────────────────
      OP [3:0]  │     rd [3:0]   │   base [3:0]   │ offset [3:0]
```

Endereço efetivo = `regs[base] + offset`  
Instruções M: `LOAD`, `STORE`

### Tipo J — Jump / Chamada (endereço imediato 12 bits)

```
 15  14  13  12 | 11  10   9   8   7   6   5   4   3   2   1   0
 ─────────────────────────────────────────────────────────────────
      OP [3:0]  │                addr [11:0]
```

Instruções J: `JMP`, `JZ`, `JNZ`, `CALL`

---

## Tabela de Opcodes

| Opcode (hex) | Mnemônico | Tipo | Operandos          | Operação                                       |
|:---:|-----------|:----:|--------------------|-------------------------------------------------|
| 0x0 | `ADD`     | R    | `rd, rs1, rs2`     | `rd ← rs1 + rs2`                               |
| 0x1 | `SUB`     | R    | `rd, rs1, rs2`     | `rd ← rs1 - rs2`                               |
| 0x2 | `MUL`     | R    | `rd, rs1, rs2`     | `rd ← (rs1 × rs2)[15:0]`                       |
| 0x3 | `DIV`     | R    | `rd, rs1, rs2`     | `rd ← rs1 ÷ rs2`  (por zero = 0xFFFF)         |
| 0x4 | `AND`     | R    | `rd, rs1, rs2`     | `rd ← rs1 AND rs2`                             |
| 0x5 | `OR`      | R    | `rd, rs1, rs2`     | `rd ← rs1 OR rs2`                              |
| 0x6 | `XOR`     | R    | `rd, rs1, rs2`     | `rd ← rs1 XOR rs2`                             |
| 0x7 | `NOT`     | R    | `rd, rs1`          | `rd ← NOT rs1`                                 |
| 0x8 | `LOAD`    | M    | `rd, [base+offset]`| `rd ← mem[regs[base] + offset]`                |
| 0x9 | `STORE`   | M    | `[base+offset], rd`| `mem[regs[base] + offset] ← rd`               |
| 0xA | `JMP`     | J    | `addr`             | `PC ← addr`                                    |
| 0xB | `JZ`      | J    | `addr`             | `if ZERO: PC ← addr`                           |
| 0xC | `JNZ`     | J    | `addr`             | `if NOT ZERO: PC ← addr`                       |
| 0xD | `CALL`    | J    | `addr`             | `R15 ← PC+1; PC ← addr`                        |
| 0xE | `RET`     | R    | —                  | `PC ← R15`                                     |
| 0xF | `HLT`     | R    | —                  | para a CPU                                      |

---

## Flags de Status

| Flag  | Nome     | Condição de ativação                                        |
|:-----:|----------|-------------------------------------------------------------|
| `Z`   | ZERO     | Resultado da última operação ALU = 0                       |
| `C`   | CARRY    | Overflow sem sinal em ADD/MUL (carry out do bit 15)        |
| `N`   | NEGATIVE | Bit 15 do resultado = 1 (interpretação com sinal)          |
| `V`   | OVERFLOW | Overflow com sinal em ADD/SUB                               |

> O branch `JZ` testa o registrador `rs1` diretamente (zero ou não), **não** a flag Z do último resultado. Isso simplifica o pipeline mas exige explicitamente `SUB` antes de `JZ` para comparações.

---

## Codificação de Exemplos

### `ADD R3, R1, R2`
```
OP=0x0  rd=3  rs1=1  rs2=2
0000 | 0011 | 0001 | 0010  →  0x0312
```

### `LOAD R5, [R2+4]`
```
OP=0x8  rd=5  base=2  offset=4
1000 | 0101 | 0010 | 0100  →  0x8524
```

### `JMP 0x0A0`
```
OP=0xA  addr=0x0A0
1010 | 0000 1010 0000  →  0xA0A0
```

### `CALL 0x010`
```
OP=0xD  addr=0x010
1101 | 0000 0001 0000  →  0xD010
```

### `HLT`
```
OP=0xF  (demais bits = 0)
1111 | 0000 | 0000 | 0000  →  0xF000
```

---

## Convenção de Chamada de Funções

```
Caller:
  1. Coloca argumentos em R1, R2, ...
  2. CALL nome_funcao      (salva PC+1 em R15)

Callee:
  1. Executa corpo da função
  2. Coloca resultado em R0
  3. RET                   (salta para R15)
```

> Funções aninhadas (call dentro de call) precisam salvar R15 na pilha manualmente.

---

## Pseudo-instruções Comuns

Embora não sejam opcodes reais, são padrões úteis:

| Pseudo-instrução     | Expansão                                | Efeito               |
|----------------------|-----------------------------------------|----------------------|
| `CLR Rd`             | `XOR Rd, Rd, Rd`                        | `Rd ← 0`             |
| `MOV Rd, Rs`         | `XOR R0,R0,R0; ADD Rd,Rs,R0`            | `Rd ← Rs`            |
| `NOP`                | `ADD R0, R0, R0`                        | sem efeito           |
| `NEG Rd, Rs`         | `XOR R0,R0,R0; SUB Rd,R0,Rs`           | `Rd ← -Rs`           |
| `CMP Rs1, Rs2`       | `SUB R0, Rs1, Rs2` (def flags)          | compara (descarta result.) |
