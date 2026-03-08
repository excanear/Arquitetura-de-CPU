# EduRISC-32v2 ISA Specification

## Visão Geral

| Parâmetro | Valor |
|---|---|
| Largura de palavra | 32 bits |
| Número de registradores | 32 (R0–R31) |
| Largura do PC | 26 bits (64M words = 256 MB) |
| Instruções | 57 definidas (6 slots reservados) |
| Endereçamento | Byte-addressable, word-aligned no fetch |
| Endianness | Big-endian (MSB no endereço menor) |

---

## Registradores

| Registrador | Alias | Papel Convencional |
|---|---|---|
| R0 | zero | Hardwired 0 — escritas ignoradas |
| R1–R25 | — | Uso geral |
| R26–R29 | t0–t3 | Temporários de chamada (caller-saved) |
| R30 | SP | Stack Pointer |
| R31 | LR | Link Register (endereço de retorno) |

---

## Formatos de Instrução

```
 31      26 25    21 20    16 15    11 10    6  5       0
┌─────────┬────────┬────────┬────────┬───────┬─────────┐
│ op[5:0] │ rd[4:0]│rs1[4:0]│rs2[4:0]│shamt  │ unused  │  Formato R
└─────────┴────────┴────────┴────────┴───────┴─────────┘

┌─────────┬────────┬────────┬─────────────────────────┐
│ op[5:0] │ rd[4:0]│rs1[4:0]│      imm16[15:0]        │  Formato I
└─────────┴────────┴────────┴─────────────────────────┘

┌─────────┬────────┬────────┬─────────────────────────┐
│ op[5:0] │rs2[4:0]│rs1[4:0]│      off16[15:0]        │  Formato S (Store)
└─────────┴────────┴────────┴─────────────────────────┘

┌─────────┬────────┬────────┬─────────────────────────┐
│ op[5:0] │rs1[4:0]│rs2[4:0]│      off16[15:0]        │  Formato B (Branch)
└─────────┴────────┴────────┴─────────────────────────┘

┌─────────┬────────────────────────────────────────────┐
│ op[5:0] │              addr26[25:0]                  │  Formato J (Jump)
└─────────┴────────────────────────────────────────────┘

┌─────────┬────────┬──────────────────────────────────┐
│ op[5:0] │ rd[4:0]│           imm21[20:0]             │  Formato U (Upper)
└─────────┴────────┴──────────────────────────────────┘
```

**Observações:**
- `imm16` é sign-extended para 32 bits em todas as instruções I exceto LHU/LBU/ANDI/ORI/XORI (zero-extended)
- `off16` (branches/stores) é sign-extended e somado ao PC (branches) ou a rs1 (stores)
- `addr26` é zero-extended para 26 bits (jmp/call absoluto)
- `imm21` (MOVHI) é carregado nos bits [31:11] do registrador destino

---

## Tabela de Opcodes

### Aritmética (0x00–0x07)

| Opcode | Hex | Formato | Operação |
|---|---|---|---|
| ADD | 0x00 | R | `rd = rs1 + rs2` |
| ADDI | 0x01 | I | `rd = rs1 + sext(imm16)` |
| SUB | 0x02 | R | `rd = rs1 - rs2` |
| MUL | 0x03 | R | `rd = (rs1 × rs2)[31:0]` |
| MULH | 0x04 | R | `rd = (rs1 × rs2)[63:32]` (sinal×sinal) |
| DIV | 0x05 | R | `rd = rs1 / rs2` (sinal, arredond. para zero) |
| DIVU | 0x06 | R | `rd = rs1 / rs2` (sem sinal) |
| REM | 0x07 | R | `rd = rs1 mod rs2` (sinal) |

### Lógica (0x08–0x0F)

| Opcode | Hex | Formato | Operação |
|---|---|---|---|
| AND | 0x08 | R | `rd = rs1 & rs2` |
| ANDI | 0x09 | I | `rd = rs1 & zext(imm16)` |
| OR | 0x0A | R | `rd = rs1 \| rs2` |
| ORI | 0x0B | I | `rd = rs1 \| zext(imm16)` |
| XOR | 0x0C | R | `rd = rs1 ^ rs2` |
| XORI | 0x0D | I | `rd = rs1 ^ zext(imm16)` |
| NOT | 0x0E | R | `rd = ~rs1` (rs2 ignorado) |
| NEG | 0x0F | R | `rd = -rs1` (complemento de dois) |

### Deslocamentos (0x10–0x15)

| Opcode | Hex | Formato | Operação |
|---|---|---|---|
| SHL | 0x10 | R | `rd = rs1 << rs2[4:0]` |
| SHR | 0x11 | R | `rd = rs1 >> rs2[4:0]` (lógico) |
| SHRA | 0x12 | R | `rd = rs1 >>> rs2[4:0]` (aritmético) |
| SHLI | 0x13 | R* | `rd = rs1 << shamt[4:0]` |
| SHRI | 0x14 | R* | `rd = rs1 >> shamt[4:0]` (lógico) |
| SHRAI | 0x15 | R* | `rd = rs1 >>> shamt[4:0]` (aritmético) |

*Usa campo shamt[10:6] em vez de rs2.

### Movimentação e Comparação (0x16–0x1B)

| Opcode | Hex | Formato | Operação |
|---|---|---|---|
| MOV | 0x16 | R | `rd = rs1` |
| MOVI | 0x17 | I | `rd = sext(imm16)` |
| MOVHI | 0x18 | U | `rd = imm21 << 11` |
| SLT | 0x19 | R | `rd = (rs1 < rs2) ? 1 : 0` (sinal) |
| SLTU | 0x1A | R | `rd = (rs1 < rs2) ? 1 : 0` (sem sinal) |
| SLTI | 0x1B | I | `rd = (rs1 < sext(imm16)) ? 1 : 0` |

### Loads (0x1C–0x20)

| Opcode | Hex | Operação |
|---|---|---|
| LW | 0x1C | `rd = MEM[rs1 + sext(off)][31:0]` |
| LH | 0x1D | `rd = sext(MEM[rs1+off][15:0])` |
| LHU | 0x1E | `rd = zext(MEM[rs1+off][15:0])` |
| LB | 0x1F | `rd = sext(MEM[rs1+off][7:0])` |
| LBU | 0x20 | `rd = zext(MEM[rs1+off][7:0])` |

### Stores (0x21–0x23)

| Opcode | Hex | Operação |
|---|---|---|
| SW | 0x21 | `MEM[rs1 + sext(off)] = rs2[31:0]` |
| SH | 0x22 | `MEM[rs1 + sext(off)][15:0] = rs2[15:0]` |
| SB | 0x23 | `MEM[rs1 + sext(off)][7:0] = rs2[7:0]` |

### Branches (0x24–0x29)

Todos os branches usam o Formato B. O endereço alvo é `PC + sext(off16)`.

| Opcode | Hex | Condição |
|---|---|---|
| BEQ | 0x24 | rs1 == rs2 |
| BNE | 0x25 | rs1 != rs2 |
| BLT | 0x26 | rs1 < rs2 (sinal) |
| BGE | 0x27 | rs1 >= rs2 (sinal) |
| BLTU | 0x28 | rs1 < rs2 (sem sinal) |
| BGEU | 0x29 | rs1 >= rs2 (sem sinal) |

### Saltos e Sub-rotinas (0x2A–0x30)

| Opcode | Hex | Formato | Operação |
|---|---|---|---|
| JMP | 0x2A | J | `PC = addr26` |
| JMPR | 0x2B | I | `PC = rs1` |
| CALL | 0x2C | J | `R31 = PC+1; PC = addr26` |
| CALLR | 0x2D | I | `R31 = PC+1; PC = rs1` |
| RET | 0x2E | J | `PC = R31` |
| PUSH | 0x2F | J | `R30 -= 1; MEM[R30] = rs2` |
| POP | 0x30 | J | `rd = MEM[R30]; R30 += 1` |

### Instruções de Sistema (0x31–0x38)

| Opcode | Hex | Operação |
|---|---|---|
| NOP | 0x31 | Nenhuma operação |
| HLT | 0x32 | Parar o pipeline |
| SYSCALL | 0x33 | Exceção de sistema (cause=3) |
| ERET | 0x34 | `PC = EPC; STATUS.IE=1` |
| MFC | 0x35 | `rd = CSR[imm16[4:0]]` |
| MTC | 0x36 | `CSR[imm16[4:0]] = rs1` |
| FENCE | 0x37 | Sincronizar memória |
| BREAK | 0x38 | Exceção de breakpoint (cause=4) |

---

## Registradores de Controle (CSR)

| Índice | Nome | Bits Relevantes |
|---|---|---|
| 0 | STATUS | [0]=IE, [1]=KU, [7:4]=IM[3:0] |
| 1 | IVT | [25:0] = base da tabela de vetores |
| 2 | EPC | PC ao momento da exceção |
| 3 | CAUSE | [31]=irq, [3:0]=código |
| 4 | ESCRATCH | Scratch de exceção |
| 5 | PTBR | Page Table Base Register |
| 6 | TLBCTL | Flush bits |
| 7 | CYCLE | Contador de ciclos (32 bits baixos) |
| 8 | CYCLEH | Contador de ciclos (32 bits altos) |
| 9 | INSTRET | Instruções aposentadas |
| 10 | ICOUNT | Ciclos com stall |
| 11 | DCMISS | Faltas no D-cache |
| 12 | ICMISS | Faltas no I-cache |
| 13 | BRMISS | Predições erradas de desvio |

---

## Códigos de Exceção

| Código | Source | `CAUSE[31]` |
|---|---|---|
| 0 | ILLEGAL | 0 |
| 1 | DIV_ZERO | 0 |
| 2 | OVERFLOW | 0 |
| 3 | SYSCALL | 0 |
| 4 | BREAKPOINT | 0 |
| 5 | IFETCH_PF | 0 |
| 6 | LOAD_PF | 0 |
| 7 | STORE_PF | 0 |
| 8 | UNALIGNED | 0 |
| 0 | TIMER | 1 (INT) |
| 1–7 | EXT[0–6] | 1 (INT) |

---

## Convenção de Chamada ABI

```
Argumentos:  R1–R6   (caller-saved)
Retorno:     R1      (ou R1:R2 para 64-bit)
Temporários: R7–R12  (caller-saved)
Saved:       R13–R25 (callee-saved, restaurar antes de RET)
SP:          R30     (decrementar antes de push)
LR:          R31     (salvar na pilha se chamar sub-rotina)
```
