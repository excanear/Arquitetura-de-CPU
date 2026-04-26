# Arquitetura Legada EduRISC-16

> Status: legado educacional.
> Para a trilha principal vigente, use a documentação de EduRISC-32v2 em [README.md](README.md), [docs/isa_spec.md](docs/isa_spec.md), [docs/pipeline_architecture.md](docs/pipeline_architecture.md) e [docs/memory_system.md](docs/memory_system.md).

## Visão Geral

O **EduRISC-16** é uma arquitetura de conjunto de instruções (ISA) educacional de 16 bits, inspirada nos princípios RISC (Reduced Instruction Set Computer). Foi projetada para ser simples o suficiente para estudar em detalhes, mas completa o suficiente para executar programas reais.

```
┌─────────────────────────────────────────────────────────────────┐
│                      EduRISC-16 CPU                              │
│                                                                   │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐              │
│  │  IF  │→ │  ID  │→ │  EX  │→ │ MEM  │→ │  WB  │              │
│  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘              │
│      │         │         │         │         │                   │
│  ┌───┴───┐ ┌───┴───┐ ┌───┴───┐ ┌───┴───┐ ┌───┴───┐            │
│  │ PC    │ │RegFile│ │  ALU  │ │D-Cache│ │RegFile│            │
│  │ I-Mem │ │ Imm   │ │ Flags │ │       │ │ WrBack│            │
│  └───────┘ └───────┘ └───────┘ └───────┘ └───────┘            │
│                                                                   │
│  Forwarding:  EX/MEM → EX,  MEM/WB → EX                        │
│  Hazard:      Load-use stall (1 ciclo)                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Características Gerais

| Parâmetro              | Valor                     |
|------------------------|---------------------------|
| Largura de palavra     | 16 bits                   |
| Registradores          | 16 × 16 bits (R0–R15)     |
| Espaço de memória      | 64K palavras (128 KB)     |
| Tamanho de instrução   | 16 bits (fixo)            |
| Pipeline               | 5 estágios (IF/ID/EX/MEM/WB) |
| Forwarding             | EX/MEM→EX, MEM/WB→EX     |
| Endereçamento          | Word-addressed (16 bits)  |

---

## Banco de Registradores

| Registrador | Alias | Uso Convencional              |
|-------------|-------|-------------------------------|
| R0          | ZERO  | Registrador zero (não forçado)  |
| R1–R12      | —     | Variáveis de propósito geral   |
| R13         | SP    | Stack Pointer (convenção)      |
| R14         | FP    | Frame Pointer (convenção)      |
| R15         | LR    | Link Register (CALL/RET)       |

> **Nota:** R0 não é hardwired para zero nesta ISA. Para usar zero, limpe R0 com `XOR R0, R0, R0`.

---

## Mapa de Memória

```
0x0000 ─── Vetor de boot (JMP KERNEL_START)
0x0001 ─── Vetor de interrupção
0x0010 ─── Início do kernel
0x0030 ─── Tabela de dados do kernel
0x0050 ─── Syscall handlers
0x0100 ─── Início do espaço de usuário (programa carregado pelo loader)
0x0200 ─── Área de staging (programa antes do loader)
0x0800 ─── Base da heap (bump allocator)
0x0E00 ─── Limite da heap
0x0FFF ─── Topo da pilha (Stack Pointer inicial)
0xFFFF ─── Fim do espaço de endereçamento
```

---

## Pipeline — Estágios

### IF — Instruction Fetch
- Lê a instrução da memória no endereço `PC`
- Incrementa `PC ← PC + 1`
- Salva instrução e PC no registrador `IF/ID`

### ID — Instruction Decode
- Decodifica instrução: opcode, tipo, operandos
- Lê registradores `rs1`, `rs2` do banco
- Gera sinais de controle
- Detecta hazard de load-use (insere bolha se necessário)

### EX — Execute
- Executa operação na ULA (ALU)
- Calcula endereço efetivo para LOAD/STORE
- Resolve branch/jump (flush do pipeline se tomado)
- Forwarding: substitui operandos obsoletos por valores atualizados

### MEM — Memory Access
- LOAD: lê memória de dados
- STORE: escreve na memória de dados
- Outras instruções: passam resultado da EX adiante

### WB — Write-Back
- Escreve resultado no banco de registradores
- Destino: `rd` (campo bits [11:8])

---

## Unidade de Forwarding

Resolve dependências de dados sem inserir bolhas (quando possível):

```
Forwarding EX/MEM → EX:
  if (EX/MEM.regWrite && EX/MEM.rd != 0 && EX/MEM.rd == ID/EX.rs1)
      fwd_A = EX/MEM.alu_result
  if (EX/MEM.regWrite && EX/MEM.rd != 0 && EX/MEM.rd == ID/EX.rs2)
      fwd_B = EX/MEM.alu_result

Forwarding MEM/WB → EX:
  (mesma lógica, mas com MEM/WB.result)
```

---

## Detecção de Hazard Load-Use

Quando uma instrução LOAD é seguida imediatamente por uma instrução que usa o registrador carregado, é necessário 1 ciclo de stall:

```
Ciclo:    1    2    3    4    5    6
LOAD R1   IF   ID   EX   MEM  WB
ADD R2,R1      IF   ID  [stall] EX  MEM  WB
                         ↑
                    bolha inserida (NOP)
```

---

## Fluxo de Dados — Diagrama Simplificado

```
         ┌──────────────────────────────────────────────┐
         │                                              │
    PC ──┤ IF: Fetch ──→ IF/ID ──→ ID: Decode ─┐      │
         │                                      │      │
         │         ┌────────────────────────────┘      │
         │         │                                   │
         │         └→ ID/EX ──→ EX: ALU ──→ EX/MEM    │
         │                           ↑    ↑            │
         │              Forward EX/MEM    MEM/WB        │
         │                                    │        │
         │         EX/MEM ──→ MEM: Access ──→ MEM/WB  │
         │                                    │        │
         │         MEM/WB ──→ WB: RegFile ─────┘       │
         └──────────────────────────────────────────────┘
```
