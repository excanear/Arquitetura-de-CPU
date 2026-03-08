# Arquitetura do Pipeline EduRISC-32v2

## Visão Geral

O EduRISC-32v2 implementa um pipeline clássico de **5 estágios** com forwarding completo e detecção de hazards em hardware.

```
       ┌────────────────────────────────────────────────────────────────────┐
       │                     EduRISC-32v2 Pipeline                         │
       └────────────────────────────────────────────────────────────────────┘

  ┌──────┐  IF/ID  ┌──────┐  ID/EX  ┌──────┐  EX/MEM  ┌──────┐  MEM/WB  ┌──────┐
  │  IF  │────────▶│  ID  │─────────▶│  EX  │──────────▶│ MEM  │──────────▶│  WB  │
  └──────┘         └──────┘          └──────┘           └──────┘           └──────┘
     │                │                 │  ▲               │  ▲               │
     │                │                 │  │               │  │               │
     ▼                ▼                 │  │               │  │               ▼
  I-Cache         Reg File         Forwarding         D-Cache            Reg File
  PC Reg          Imm Gen          ALU/MUL/DIV        LSU               (write)
  Branch Pred     Decoder          Branch Unit        MMU/TLB
                                   Perf Count

  ◄─────────────────────── Forwarding EX/MEM → EX ──────────────────────────────►
  ◄─────────────────────── Forwarding MEM/WB → EX ──────────────────────────────►
```

---

## Estágios

### IF — Instruction Fetch

| Componente | Arquivo |
|---|---|
| PC Register | `rtl_v/fetch/program_counter.v` (embutido em cpu_top) |
| I-Cache Interface | `rtl_v/cache/icache.v` |
| Branch Handler | redireciona PC em flush |

**Operação:**
1. Envia PC atual para I-cache
2. Se I-cache HIT (ciclo seguinte): instrução disponível em `if_insn`
3. Se MISS: sinal `icache_stall` congela IF/ID até FILL completar
4. Registra `IF/ID` com: `{insn[31:0], pc[25:0]}`

**Flush:** quando `branch_taken` do estágio EX chega, o registrador IF/ID é zerado (NOP inserido).

---

### ID — Instruction Decode

| Componente | Arquivo |
|---|---|
| Instruction Decoder | `rtl_v/decode/instruction_decoder.v` |
| Register File | `rtl_v/decode/register_file.v` |
| Immediate Generator | deduzido da ISA |
| Control Unit | `rtl_v/control/control_unit.v` |
| Hazard Unit | `rtl_v/hazard/hazard_unit.v` |

**Operação:**
1. Decodifica instrução: extrai opcode, rd, rs1, rs2, imm
2. Lê R[rs1] e R[rs2] do Register File
3. Gera imediato (sext/zext conforme formato)
4. Hazard Unit verifica se o estágio EX anterior é um load com rd que coincide com rs1/rs2: em caso positivo, sinaliza **stall** (1 ciclo)

**Registrador ID/EX:** `{ctrl_sigs, rs1_val, rs2_val, imm, rd, rs1, rs2, pc}`

---

### EX — Execução

| Componente | Arquivo |
|---|---|
| ALU | `rtl_v/execute/alu.v` |
| Multiplier (3 estg.) | `rtl_v/execute/multiplier.v` |
| Divider (32 ciclos) | `rtl_v/execute/divider.v` |
| Branch Unit | `rtl_v/execute/branch_unit.v` |
| Forwarding Unit | `rtl_v/execute/forwarding_unit.v` |

**Operação:**
1. Forwarding Unit seleciona operandos A e B (entre Register File, EX/MEM.result, MEM/WB.result)
2. ALU executa operação conforme `alu_op`
3. MUL ocupa 3 ciclos (pipeline; `valid_in`/`valid_out`)
4. DIV ocupa 32 ciclos (FSM IDLE→CALC→CORR→DONE)
5. Branch Unit calcula `taken` e `target`; se `taken`, envia sinal de flush para IF/ID e ID/EX
6. Exceções geradas: DIV_ZERO, OVERFLOW, UNALIGNED

**Registrador EX/MEM:** `{result, rs2_val_fwd, rd, mem_we, mem_re, wb_we, …}`

---

### MEM — Acesso à Memória

| Componente | Arquivo |
|---|---|
| Load/Store Unit | `rtl_v/memory/load_store_unit.v` |
| D-Cache | `rtl_v/cache/dcache.v` |
| MMU | `rtl_v/mmu/mmu.v` |
| Cache Controller | `rtl_v/cache/cache_controller.v` |

**Operação:**
1. Se `mem_we` ou `mem_re`: envia endereço virtual ao MMU → PA
2. D-cache: verificar hit/miss com PA
3. HIT read: dado disponível no mesmo ciclo
4. HIT write: marcar bloco como dirty (write-back)
5. MISS: `dcache_stall` congela MEM; FSM (EVICT→)FILL→UPDATE
6. Page faults geram `mem_exception` → exceção LOAD_PF / STORE_PF

**Registrador MEM/WB:** `{result, mem_data, rd, wb_we, wb_sel}`

---

### WB — Write-Back

**Operação:**
- Se `wb_we`: escreve no Register File
- Multiplexador `wb_sel` escolhe entre `result` (ALU) e `mem_data` (load)
- R0 sempre ignorado (hardwired 0)

---

## Forwarding

```
        ID/EX       EX/MEM       MEM/WB
          │             │             │
          ▼             │             │
    ┌───────────┐       │             │
    │ Forwarding│◄──────┘             │
    │   Unit    │◄────────────────────┘
    └───────────┘
          │
    OperandA, OperandB → ALU
```

**Condições de forwarding (prioridade EX/MEM > MEM/WB):**

| Situação | De | Para |
|---|---|---|
| EX/MEM.rd == ID/EX.rs1 | EX/MEM.result | ALU_A |
| EX/MEM.rd == ID/EX.rs2 | EX/MEM.result | ALU_B |
| MEM/WB.rd == ID/EX.rs1 | MEM/WB.(result\|mem_data) | ALU_A |
| MEM/WB.rd == ID/EX.rs2 | MEM/WB.(result\|mem_data) | ALU_B |

*Forwarding não se aplica quando rd == R0.*

---

## Hazards e Stalls

### Load-Use Hazard (1 ciclo)
```
  LW  R1, 0(R2)   ; ID/EX.mem_re=1, ID/EX.rd=R1
  ADD R3, R1, R4  ; ID detecta: usa R1 antes de WB
  ─────────────────────────────────────────────────
  IF  ID  EX  MEM WB
      IF  ID  **STALL** EX MEM WB  ← ADD atrasa 1 ciclo
```

### MUL Latência (3 ciclos)
O multiplicador opera em pipeline de 3 estágios. Stall até `valid_out` = 1.

### DIV Latência (32 ciclos)
O divisor usa FSM iterativa. Pipeline fica parado durante DIV.

### Branch Flush (1 ciclo)
Quando branch taken é resolvido no estágio EX, os registradores IF/ID e ID/EX são zerados (bolha), descartando a instrução buscada incorretamente.

---

## Tratamento de Exceções

```
  Estágio EX ou MEM detecta exceção
       │
       ▼
  exception_handler.v captura:
    - EPC  ← PC da instrução culpada
    - CAUSE ← código da exceção
    - STATUS.IE ← 0 (desabilita interrupções)
       │
       ▼
  PC ← IVT_BASE + cause_code  (vector IVT + código)
  Pipeline flush (todos os estágios)
       │
       ▼
  ISR: salva contexto, trata, ERET
  ERET: PC ← EPC, STATUS.IE ← 1
```

---

## Diagramas de Tempo (Ciclos)

### Pipeline nominal sem hazards

```
Ciclo:   1    2    3    4    5    6    7
I1:     [IF] [ID] [EX] [MEM][WB]
I2:          [IF] [ID] [EX] [MEM][WB]
I3:               [IF] [ID] [EX] [MEM][WB]
```

### Load-Use

```
Ciclo:   1    2    3    4    5    6    7    8
LW:     [IF] [ID] [EX] [MEM][WB]
ADD:          [IF] [ID] [--] [EX] [MEM][WB]
                    ↑ stall 1 ciclo
I3:                [IF] [--] [ID] [EX] [MEM][WB]
```

### Branch Taken

```
Ciclo:   1    2    3    4    5    6
BEQ:    [IF] [ID] [EX] [MEM][WB]
I+1:         [IF] [ID] [--]      ← flush (bolha)
target:             [IF] [ID] [EX]...
```
