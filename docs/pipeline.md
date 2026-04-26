# Pipeline Legado EduRISC-16 — Guia Detalhado

> Status: legado educacional.
> Para o pipeline principal vigente de EduRISC-32v2, use [docs/pipeline_architecture.md](docs/pipeline_architecture.md).

## Visão Geral dos 5 Estágios

```
Ciclo →     1     2     3     4     5     6     7
           ─────────────────────────────────────────
LOAD R1     IF    ID    EX   MEM    WB
ADD R2,R1         IF    ID  [stall] EX   MEM    WB
SUB R3,R2               IF   ID     ID   EX    MEM   WB
                              ↑
                         bolha de stall
```

---

## Registradores de Pipeline

Entre cada par de estágios existe um **registrador de pipeline** que preserva o estado de uma instrução enquanto avança:

### IF/ID
Armazena a instrução buscada e o PC correspondente.

```python
@dataclass
class IFIDReg:
    valid:  bool = False
    pc:     int  = 0
    instr:  int  = 0   # palavra de 16 bits

    def flush(self):
        self.valid = False
        self.instr = 0
```

### ID/EX
Armazena operandos lidos, sinais de controle e informações estruturais.

```python
@dataclass
class IDEXReg:
    valid:    bool = False
    pc:       int  = 0
    instr:    int  = 0
    ctrl:     ControlSignals = field(default_factory=ControlSignals)
    rs1:      int  = 0    # número do reg fonte 1
    rs2:      int  = 0
    rd:       int  = 0    # número do reg destino
    rs1_val:  int  = 0    # valor lido
    rs2_val:  int  = 0
```

### EX/MEM
Armazena resultado da ALU e sinais para o estágio de memória.

### MEM/WB
Armazena o resultado final (ALU ou dado de memória) para ser escrito no banco.

---

## Forwarding Unit

### Problema

```asm
ADD R1, R2, R3    ; escreve R1 no WB (ciclo 5)
SUB R4, R1, R5    ; lê R1 no ID (ciclo 3) → lê valor antigo!
```

Sem forwarding, `SUB` leria o valor **anterior** de R1, pois o WB da `ADD` ocorre no ciclo 5, mas o ID de `SUB` ocorre no ciclo 3.

### Solução: Forwarding de EX/MEM e MEM/WB

```
Forwarding EX/MEM → EX (1 instrução de distância):

  ADD R1, R2, R3   [EX/MEM agora tem R1]
  SUB R4, R1, R5   ← usa R1 de EX/MEM diretamente

Forwarding MEM/WB → EX (2 instruções de distância):

  ADD R1, R2, R3   [MEM/WB agora tem R1]
  NOP
  MUL R5, R1, R6   ← usa R1 de MEM/WB
```

Lógica de prioridade (EX/MEM tem prioridade sobre MEM/WB):

```python
def calc(idex, exmem, memwb) -> tuple[int, int]:
    fwd_A = fwd_B = 0  # 0=reg, 1=EX/MEM, 2=MEM/WB

    # EX/MEM → EX forwarding
    if exmem.valid and exmem.ctrl.reg_write and exmem.rd != 0:
        if exmem.rd == idex.rs1:
            fwd_A = 1
        if exmem.rd == idex.rs2:
            fwd_B = 1

    # MEM/WB → EX forwarding (só se EX/MEM não resolveu)
    if memwb.valid and memwb.ctrl.reg_write and memwb.rd != 0:
        if memwb.rd == idex.rs1 and fwd_A == 0:
            fwd_A = 2
        if memwb.rd == idex.rs2 and fwd_B == 0:
            fwd_B = 2

    return fwd_A, fwd_B
```

---

## Hazard de Load-Use

O forwarding **não resolve** o caso em que um `LOAD` é seguido imediatamente de uma instrução que usa o registrador carregado, pois o dado da memória só fica disponível após o estágio MEM — que é tarde demais para ser encaminhado para EX da instrução seguinte.

```
Ciclo:     1    2    3    4    5    6
LOAD R1    IF   ID   EX   MEM  WB
ADD R2,R1       IF   ID   ??   EX   MEM  WB
                          ↑
                    Dado de R1 não disponível aqui!
                    (MEM só termina no ciclo 5)
```

### Solução: Stall de 1 ciclo

Quando detectado:
1. O pipeline fica parado: IF e ID mantêm seus valores (PC não avança)
2. Bolha `NOP` é inserida em ID/EX
3. No ciclo seguinte, o forwarding MEM/WB→EX resolve a dependência

```python
def detect_load_use(idex: IDEXReg, ifid: IFIDReg) -> bool:
    if not idex.valid or not idex.ctrl.mem_read:
        return False
    d = decode(ifid.instr)
    return idex.rd != 0 and (idex.rd == d.rs1 or idex.rd == d.rs2)
```

---

## Branch e Jump

Jumps e branches são resolvidos no estágio **EX** (ciclo 3 do salto). As 2 instruções já buscadas precisam ser descartadas (**flush**):

```
Ciclo:     1    2    3    4
JMP 0xABC  IF   ID   EX   ...
instr+1         IF   ID   ← flush (torna NOP)
instr+2              IF   ← flush (torna NOP)
instr@0xABC           IF   ← início correto
```

Chamada `flush()` nos registradores IF/ID e ID/EX.

```python
# Em cpu_simulator.py, durante _stage_ex():
if ctrl.jump or (ctrl.branch and condição_satisfeita):
    self.pc_reg = novo_pc
    self.ifid.flush()
    self.idex.flush()
    self.stats.flushes += 2
```

---

## Diagrama Completo de Hazards

```
Caso 1: RAW com forwarding EX/MEM (sem stall)
  ADD R1,R2,R3   IF  ID  EX  MEM  WB
  SUB R4,R1,R5       IF  ID  EX←─────────── forward R1 de EX/MEM

Caso 2: RAW com forwarding MEM/WB (sem stall)
  ADD R1,R2,R3   IF  ID  EX  MEM  WB
  NOP                IF  ID  EX   MEM  WB
  MUL R5,R1,R6           IF  ID   EX←────── forward R1 de MEM/WB

Caso 3: Load-use (1 stall)
  LOAD R1,[R2+0] IF  ID  EX  MEM  WB
  ADD R3,R1,R4       IF  ID  ──  EX   MEM  WB
                             ↑ stall

Caso 4: Jump (2 flushes)
  JMP 0x100      IF  ID  EX  MEM  WB
  instr+1            IF  ID  (flush)
  instr+2                IF  (flush)
  @0x100                      IF  ID  EX ...
```

---

## Estatísticas do Simulador

O simulador rastreia:

| Métrica             | Descrição                                    |
|---------------------|----------------------------------------------|
| `cycles`            | Total de ciclos de clock executados          |
| `instructions`      | Instruções efetivamente concluídas (WB)      |
| `stalls`            | Ciclos desperdiçados por hazard load-use     |
| `flushes`           | Instruções descartadas por branch/jump       |
| `IPC`               | Instructions Per Cycle = instrs / cycles     |

IPC ideal = 1.0. Stalls e flushes reduzem o IPC.
