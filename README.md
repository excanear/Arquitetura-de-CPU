# Laboratório Completo de Arquitetura de Computadores

> **Repositório triplo:** CPU **EduRISC-32** em Verilog-2012 (pipeline 5 estágios, FPGA-ready) + laboratório educacional **EduRISC-16** em Python (assembler, simulador, compilador C-like, micro-OS) + núcleo **RV32IMAC** em VHDL-2008 (grau Linux, Sv32, caches L1, CLINT, PLIC).

---

## Índice

1. [Visão Geral do Projeto](#visão-geral-do-projeto)
2. [Estrutura de Diretórios](#estrutura-de-diretórios)
3. [EduRISC-32 — CPU Verilog RTL](#eduriscv-32--cpu-verilog-rtl)
4. [EduRISC-16 — Laboratório Python](#eduriscv-16--laboratório-python)
5. [RV32IMAC — Núcleo VHDL-2008](#rv32imac--núcleo-vhdl-2008)
6. [Início Rápido](#início-rápido)
7. [Referências](#referências)

---

## Visão Geral do Projeto

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Arquitetura de Computadores Lab                       │
│                                                                          │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐  │
│  │   EduRISC-32 RTL    │  │  EduRISC-16 Python  │  │  RV32IMAC VHDL  │  │
│  │   (Verilog-2012)    │  │  (laboratório)       │  │  (VHDL-2008)    │  │
│  │                     │  │                      │  │                  │  │
│  │  Pipeline 5 estágs  │  │  Assembler/Compiler  │  │  RV32IMAC+Zicsr │  │
│  │  Forwarding completo│  │  Simulador Python    │  │  Sv32 MMU       │  │
│  │  Hazard detection   │  │  Depurador CLI       │  │  Caches L1      │  │
│  │  FPGA Arty A7-35T   │  │  Web Visualizer      │  │  CLINT + PLIC   │  │
│  │  iverilog sim       │  │  Micro-OS (ASM)      │  │  GHDL verified  │  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────┘  │
│                                                                          │
│  Ponto de entrada unificado:  python main.py <comando>                   │
└─────────────────────────────────────────────────────────────────────────┘
```

| Camada | Linguagem | Status | Destaque |
|--------|-----------|--------|----------|
| EduRISC-32 RTL | Verilog-2012 | ✅ Completo | 15 módulos, testbench 7 testes, Arty A7 |
| EduRISC-16 Lab | Python 3.11+ | ✅ Completo | Demo sum(1..5)=15 via ASM e via C-like |
| RV32IMAC VHDL  | VHDL-2008    | ✅ Completo | 28 unidades de design, GHDL PASS |

---

## Estrutura de Diretórios

```
.
├── rtl_v/                        ← EduRISC-32 RTL (Verilog-2012)
│   ├── isa_pkg.vh                #   Constantes e defines da ISA
│   ├── alu.v                     #   ALU 32-bit: 12 operações + flags Z/C/N/V
│   ├── register_file.v           #   Banco 16×32-bit, dual-read, single-write
│   ├── program_counter.v         #   PC 28-bit com stall/load
│   ├── instruction_decoder.v     #   Extração combinacional de campos R/I/J/M
│   ├── control_unit.v            #   Sinais de controle por opcode
│   ├── hazard_unit.v             #   Load-use stall + branch flush
│   ├── forwarding_unit.v         #   Forwarding EX/MEM→EX e MEM/WB→EX
│   ├── pipeline_if.v             #   Registrador IF/ID (stall/flush)
│   ├── pipeline_id.v             #   Registrador ID/EX (NOP injection)
│   ├── pipeline_ex.v             #   Registrador EX/MEM
│   ├── pipeline_mem.v            #   Registrador MEM/WB
│   ├── pipeline_wb.v             #   Mux write-back (combinacional)
│   ├── memory_interface.v        #   IMEM + DMEM block RAM 1M×32
│   └── cpu_top.v                 #   Top-level — conecta todos os módulos
│
├── testbench/
│   └── cpu_tb.v                  ← Testbench Icarus Verilog (7 testes automáticos)
│
├── fpga/
│   ├── constraints.xdc           ← Pinos Arty A7-35T (clock/reset/LEDs)
│   └── top_module.v              ← Wrapper FPGA com divisor de clock
│
├── rtl/                          ← RV32IMAC RTL (VHDL-2008)
│   ├── pkg/                      #   cpu_pkg.vhd · axi4_pkg.vhd
│   ├── fetch/                    #   fetch_stage · pc_reg · branch_handler
│   ├── decode/                   #   decode_stage · instruction_decoder · register_file
│   ├── execute/                  #   execute_stage · alu · branch_comparator · forwarding_unit
│   ├── memory/                   #   memory_stage · load_store_unit (LR/SC/AMO)
│   ├── writeback/                #   writeback_stage
│   ├── csr/                      #   csr_reg (M+S, medeleg/mideleg, MRET/SRET)
│   ├── cache/                    #   icache · dcache (write-back/write-allocate)
│   ├── mmu/                      #   mmu (Sv32 PTW 2-níveis + TLB 16 entradas)
│   └── cpu_top.vhd               #   Integração de nível superior
│
├── cpu/                          ← EduRISC-16: ISA, ALU, registradores, pipeline
├── assembler/                    ← Assembler dois-passos
├── compiler/                     ← Compilador C-like (lexer + parser recursivo)
├── simulator/                    ← Simulador pipeline 5-estágios + depurador CLI
├── web/                          ← Visualizador de pipeline HTML/CSS/JS puro
├── os/                           ← Micro-kernel + syscalls em EduRISC-16 ASM
├── docs/                         ← Documentação técnica completa
│   └── rtl_architecture.md       #   Arquitetura completa do EduRISC-32
│
├── main.py                       ← Ponto de entrada unificado (todos os comandos)
└── README.md
```

---

## EduRISC-32 — CPU Verilog RTL

### Resumo

| Parâmetro | Valor |
|-----------|-------|
| Largura de palavra | 32 bits |
| Registradores | 16 × 32-bit (R0–R15; R15 = Link Register) |
| PC | 28 bits (256 M palavras de espaço de endereçamento) |
| Profundidade IMEM / DMEM | 1 M palavras × 32-bit cada |
| Pipeline | 5 estágios (IF → ID → EX → MEM → WB) |
| Forwarding | EX/MEM → EX; MEM/WB → EX |
| Hazard detection | Load-use (stall 1 ciclo); Branch (flush 1 ciclo) |
| Simulação | Icarus Verilog (iverilog + vvp) |
| FPGA alvo | Digilent Arty A7-35T (Artix-7 XC7A35T) |
| Síntese | Vivado 2023.x / Quartus Prime 23.1 |

### ISA EduRISC-32 — Formatos de Instrução

```
Tipo-R:  [31:28 opcode][27:24 rd][23:20 rs1][19:16 rs2][15:0 não-usado]
Tipo-I:  [31:28 opcode][27:24 rd][23:20 rs1][19:0  imm20 sinalizado  ]
Tipo-J:  [31:28 opcode][27:0  addr28                                  ]
Tipo-M:  [31:28 opcode][27:24 rd][23:20 base][19:0 offset20 sinalizado]
```

### Tabela de Opcodes

| Opcode | Mnemônico | Tipo | Operação |
|--------|-----------|------|----------|
| 0x0 | ADD   | R/I | `rd = rs1 + rs2 | imm20` |
| 0x1 | SUB   | R   | `rd = rs1 − rs2` |
| 0x2 | MUL   | R   | `rd = rs1 × rs2` |
| 0x3 | DIV   | R   | `rd = rs1 ÷ rs2` |
| 0x4 | AND   | R   | `rd = rs1 & rs2` |
| 0x5 | OR    | R   | `rd = rs1 | rs2` |
| 0x6 | XOR   | R   | `rd = rs1 ^ rs2` |
| 0x7 | NOT   | R   | `rd = ~rs1` |
| 0x8 | LOAD  | M   | `rd = Mem[base + offset20]` |
| 0x9 | STORE | M   | `Mem[base + offset20] = rd` |
| 0xA | JMP   | J   | `PC = addr28` |
| 0xB | JZ    | J   | `if Z: PC = addr28` |
| 0xC | JNZ   | J   | `if !Z: PC = addr28` |
| 0xD | CALL  | J   | `R15 = PC+1; PC = addr28` |
| 0xE | RET   | R   | `PC = R15` |
| 0xF | HLT   | —   | Para o pipeline |

### Diagrama de Blocos do Pipeline

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                          cpu_top.v                                   │
  │                                                                      │
  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────┐  │
  │  │    IF    │  │    ID    │  │    EX    │  │   MEM    │  │  WB  │  │
  │  │          │  │          │  │          │  │          │  │      │  │
  │  │ PC 28-bit│  │ Decoder  │  │ Fwd Mux  │  │  DMEM    │  │ Mux  │  │
  │  │ IMEM     │  │ Control  │  │ ALU      │  │ R/W      │  │ALU / │  │
  │  │ IF/ID reg│  │ RegFile  │  │ Branch   │  │ MEM/WB   │  │ MEM  │  │
  │  │          │  │ ID/EX reg│  │ EX/MEM   │  │  reg     │  │  ↓   │  │
  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │RegFil│  │
  │                                                            └──────┘  │
  │  ┌─────────────────┐   ┌─────────────────────────────────────────┐  │
  │  │  hazard_unit.v  │   │          forwarding_unit.v              │  │
  │  │  load-use stall │   │  EX/MEM→EX  ·  MEM/WB→EX forwarding    │  │
  │  │  branch flush   │   └─────────────────────────────────────────┘  │
  │  └─────────────────┘                                                 │
  └──────────────────────────────────────────────────────────────────────┘
```

### Temporização do Pipeline

**Caso normal (forwarding, sem stall):**
```
Ciclo:   1      2      3      4      5      6      7
ADD      IF     ID     EX     MEM    WB
SUB             IF     ID     EX¹    MEM    WB
MUL                    IF     ID     EX     MEM    WB

¹ Forwarding EX/MEM envia resultado do ADD direto ao operando A do SUB.
```

**Load-use hazard (stall 1 ciclo):**
```
Ciclo:   1      2      3      4      5      6      7
LOAD     IF     ID     EX     MEM    WB
ADD             IF     ID    [NOP]   EX     MEM    WB
                               ↑ stall inserido pela hazard_unit
```

**Branch hazard (flush 1 ciclo):**
```
Ciclo:   1      2      3      4      5      6
JNZ      IF     ID     EX     MEM    WB
?inst           IF    [NOP]               ← flush: instrução descartada
target                 IF     ID     EX   MEM    WB
```

### Testbench — 7 Testes Automáticos

| Teste | Cobertura | Resultado esperado |
|-------|----------|--------------------|
| TEST 1 | ADD/SUB/AND/OR/XOR/NOT com imediatos | R3=17, R4=3, R5=2, R6=15, R7=13 |
| TEST 2 | MUL / DIV | R3=42, R4=6 |
| TEST 3 | LOAD / STORE | R2=R3=0xDEADBEEF |
| TEST 4 | Loop JNZ — Σ(1+2+3+4+5) | **R1 = 15** (igual ao Demo 1 Python) |
| TEST 5 | Forwarding EX/MEM→EX | R1=1, R2=2, R3=3 |
| TEST 6 | Load-use hazard (stall automático) | R2=99, R3=198 |
| TEST 7 | CALL / RET | R1=20, R2=40 |

### Simulação com Icarus Verilog

```bash
# Compilar todos os módulos RTL + testbench
iverilog -g2012 -I rtl_v -o sim.out testbench/cpu_tb.v rtl_v/*.v

# Executar simulação
vvp sim.out

# Inspecionar waveforms (GTKWave)
gtkwave testbench/dump.vcd
```

Via `main.py`:
```bash
python main.py rtl-build                     # verifica sintaxe com iverilog
python main.py rtl-sim  prog.hex             # simula com programa personalizado
python main.py rtl-sim  prog.hex --waves     # + abre GTKWave automaticamente
python main.py compare  prog.hex             # compara Python vs RTL registrador a registrador
```

### Síntese FPGA — Arty A7-35T

| Sinal | Pino | Função |
|-------|------|--------|
| `sys_clk` | E3 | Crystal 100 MHz |
| `sys_rst` | D9 | BTN0 — reset ativo alto |
| `led[0]` | H5 | R0[0] após halt / pisca durante execução |
| `led[1]` | J5 | R0[1] |
| `led[2]` | T9 | R0[2] |
| `led[3]` | T10 | R0[3] |

**Passos no Vivado:**
1. Criar projeto Verilog com todos os fontes de `rtl_v/` + `fpga/top_module.v`
2. Adicionar `fpga/constraints.xdc` como constraint
3. Editar `fpga/top_module.v`: parâmetro `IMEM_HEX` → caminho do `.hex` do programa
4. Run Synthesis → Run Implementation → Generate Bitstream

---

## EduRISC-16 — Laboratório Python

Implementação completa de uma CPU educacional de 16 bits do zero, cobrindo todas as camadas da pilha de software:

```
┌─────────────────────────────────────────────────────────────────┐
│                   EduRISC-16 Lab Stack                           │
│                                                                   │
│  Código C-like ──► Compilador ──► Assembly ──► Assembler         │
│                                       │             │             │
│                                  Depurador ◄── Simulador         │
│                                  CLI                Pipeline      │
│                                  Web Viz             5-estágios   │
│                                  browser             Forwarding   │
│                                                      Hazards      │
│  Micro-OS: kernel.asm + syscalls.asm (EduRISC-16 Assembly)       │
└─────────────────────────────────────────────────────────────────┘
```

### EduRISC-16 ISA

| Parâmetro | Valor |
|-----------|-------|
| Largura de palavra | 16 bits |
| Registradores | 16 × R0–R15 (R15 = Link Register) |
| Instruções | 16 (ADD/SUB/MUL/DIV/AND/OR/XOR/NOT/LOAD/STORE/JMP/JZ/JNZ/CALL/RET/HLT) |
| Pipeline | 5 estágios com forwarding e detecção de hazards |
| Memória | 64 K palavras (128 KB) |

### Todos os Comandos `main.py`

```bash
# ── EduRISC-16 Python ──────────────────────────────────────────────
python main.py demo                         # demo integrada: ASM + C-like → sim
python main.py assemble  prog.asm           # monta .asm → .hex
python main.py assemble  prog.asm --listing # com listagem detalhada
python main.py compile   prog.c             # compila C-like → .asm
python main.py compile   prog.c --show-ast  # imprime AST do compilador
python main.py build     prog.c             # compila + monta .c → .hex
python main.py simulate  prog.hex           # executa e exibe registradores finais
python main.py simulate  prog.hex --trace   # com log de eventos completo
python main.py debug     prog.hex           # depurador interativo CLI
python main.py run       prog.asm           # monta e executa .asm diretamente

# ── EduRISC-32 RTL ─────────────────────────────────────────────────
python main.py rtl-build                    # verifica sintaxe RTL (iverilog)
python main.py rtl-sim   prog.hex           # simula RTL via iverilog+vvp
python main.py rtl-sim   prog.hex --waves   # + abre GTKWave
python main.py compare   prog.hex           # compara Python vs RTL
```

### Depurador CLI

```
(dbg) step          → avança 1 ciclo
(dbg) run 100       → executa até 100 ciclos
(dbg) break 0x020   → define breakpoint em 0x020
(dbg) print R1      → exibe valor de R1
(dbg) mem 0x100 16  → dump de 16 palavras a partir de 0x100
(dbg) dis 0x000 20  → desmonta 20 instruções a partir de 0x000
(dbg) history       → snapshots dos estágios do pipeline
(dbg) log           → log de eventos (stalls, flushes, forwards)
(dbg) quit          → encerra
```

### Linguagem C-like Suportada

```c
int fib(int n) {
    int a = 0;
    int b = 1;
    while (n) {
        int tmp = a + b;
        a = b;
        b = tmp;
        n = n - 1;
    }
    return a;
}

int main() {
    int resultado = fib(8);   // resultado = 21
    return resultado;
}
```

```bash
python main.py build    fib.c        # compila + monta → fib.hex
python main.py simulate fib.hex      # executa → R0 = 21
```

**Construções C-like suportadas:** `int`, atribuição, `while`, `if/else`, chamadas de função, retorno, expresões aritméticas (+, -, *, /), lógicas (&&, ||, !), relacionais (==, !=, <, <=, >, >=).

### Resultados das Demos Verificadas

| Demo | Entrada | Resultado | Status |
|------|---------|-----------|--------|
| Demo 1 | Loop JNZ assembly (sum 1..5) | **R2 = 15** | ✅ |
| Demo 2 | Código C-like compilado (sum 1..5) | **R0 = 15** | ✅ |
| Test 4 RTL | EduRISC-32 testbench loop JNZ | **R1 = 15** | ✅ |
| kernel.asm | `os/kernel.asm` | Assembla sem erros | ✅ |
| syscalls.asm | `os/syscalls.asm` | Assembla sem erros | ✅ |

### Módulos Python

| Diretório / Arquivo | Conteúdo |
|---------------------|----------|
| `cpu/` | ISA EduRISC-16, banco de registradores, ALU, pipeline |
| `assembler/` | Tokenizer, parser, assembler dois-passos |
| `compiler/` | Lexer + parser recursivo descendente + gerador de código |
| `simulator/cpu_simulator.py` | Simulador pipeline 5-estágios com forwarding completo |
| `simulator/debugger.py` | CLI interativo: step, breakpoints, mem dump, disassemble |
| `web/` | Visualizador de pipeline em HTML/CSS/JS puro — abrir no browser |
| `os/kernel.asm` | Micro-kernel EduRISC-16 (scheduler, context switch) |
| `os/syscalls.asm` | Tabela de syscalls do micro-OS |
| `docs/` | Documentação: ISA, pipeline, assembler, compilador, RTL |

---

## RV32IMAC — Núcleo VHDL-2008

> Núcleo RISC-V totalmente sintetizável, em ordem, pipeline de 5 estágios. Direcionado a hardware FPGA real — não é um emulador de software.

### Resumo

| Atributo | Valor |
|---|---|
| Linguagem | **VHDL-2008** (IEEE 1076-2008) |
| ISA | RISC-V **RV32IMAC + Zicsr + Sv32** |
| Modos de privilégio | **M / S / U** — apto para Linux |
| Pipeline | Em ordem, 5 estágios (IF → ID → EX → MEM → WB) |
| Placas alvo | Digilent Arty A7-35T · Terasic DE0-Nano |
| Ferramentas | Vivado 2023.x · Quartus Prime 23.1 Lite |
| Recursos estimados | ~3.500 LUTs · ~4.000 FFs · 8× RAMB36 (Artix-7) |
| Simulador | GHDL 5.1.1 — 72 ciclos → **[TB] PASS** |
| Unidades RTL | **28 unidades de design VHDL** |

### Funcionalidades

| Funcionalidade | Status |
|---|---|
| RV32I — todas as 37 instruções | ✅ |
| RV32M — MUL / MULH / MULHSU / MULHU / DIV / DIVU / REM / REMU | ✅ |
| RV32A — LR.W / SC.W + 9 operações AMO | ✅ |
| RV32C — 16-bit comprimido (alinhado a 4 bytes) | ✅ parcial |
| Zicsr — CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI | ✅ |
| Traps, exceções e interrupções modo M | ✅ |
| Modos de privilégio S e U | ✅ |
| medeleg / mideleg — delegação de trap para modo S | ✅ |
| ECALL / EBREAK / MRET / SRET | ✅ |
| FENCE / FENCE.I / SFENCE.VMA | ✅ |
| Forwarding completo (EX→EX, MEM→EX) + load-use stall | ✅ |
| Preditor de desvios saturante 1-bit + BTB 64 entradas | ✅ |
| I-cache L1 — mapeamento direto, 256 conjuntos, 16 B/linha | ✅ |
| D-cache L1 — write-back / write-allocate | ✅ |
| MMU Sv32 — PTW 2 níveis + TLB 16 entradas | ✅ |
| CLINT — mtime / mtimecmp / msip | ✅ |
| PLIC — 31 fontes, 1 contexto modo M | ✅ |
| Dois barramentos AXI4-Lite master (IM + DM) | ✅ |

### Diagrama de Blocos (cpu_top VHDL)

```
              ┌────────────────────────────────────────────────────────┐
              │                     cpu_top.vhd                        │
              │                                                        │
  ┌──────────┐│ ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌──────────┐         │
  │  icache  │◄►│ IF │─►│ ID │─►│ EX │─►│MEM │─►│   WB     │         │
  └──────────┘│ │btb │  │dec │  │alu │  │lsu │  │ regfile  │         │
  IM AXI4-Lit │ │bhdl│  │imm │  │bcmp│  │amo │  │          │         │
              │ └────┘  │rfile│ │fwd │  │    │  └──────────┘         │
  ┌──────────┐│         └────┘  └────┘  └────┘                       │
  │  dcache  │◄►│ ┌──────────────┐  ┌─────────────────────────────┐  │
  └──────────┘│ │   csr_reg     │  │  MMU Sv32 (PTW + TLB 16e)  │  │
  DM AXI4-Lit │ │  M+S CSRs     │  │  satp · mstatus.MXR/SUM     │  │
              │ │  medeleg/ideleg│  └─────────────────────────────┘  │
              │ └──────────────┘                                      │
              └────────────────────────────────────────────────────────┘
```

### Cobertura de ISA (RV32I — todas as 37)

| Classe | Instruções |
|---|---|
| Aritmética | `ADD` `SUB` `ADDI` `LUI` `AUIPC` |
| Lógica | `AND` `OR` `XOR` `ANDI` `ORI` `XORI` |
| Deslocamento | `SLL` `SRL` `SRA` `SLLI` `SRLI` `SRAI` |
| Comparação | `SLT` `SLTU` `SLTI` `SLTIU` |
| Carga | `LB` `LH` `LW` `LBU` `LHU` |
| Armazenamento | `SB` `SH` `SW` |
| Desvio | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| Salto | `JAL` `JALR` |
| Sistema | `ECALL` `EBREAK` `FENCE` `FENCE.I` |

### Tratamento de Hazards (VHDL)

| Hazard | Resolução |
|---|---|
| RAW (não-load) | Forwarding EX/MEM→EX e MEM/WB→EX |
| RAW load-use | Stall 1 ciclo + MEM/WB forwarding |
| Desvio mal previsto | Flush IF/ID (1 bolha), redirecionamento de PC |
| JAL | Resolvido em ID — 1 bolha |
| JALR | Resolvido em EX — 2 bolhas |
| TRAP / MRET / SRET | Flush completo → mtvec / mepc / sepc |
| FENCE.I | Flush + invalidação da I-cache |
| SFENCE.VMA | Flush + invalidação da TLB |

### CSRs Implementados

**Modo M:** `mstatus`, `medeleg`, `mideleg`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `cycle`, `cycleh`, `instret`, `mvendorid`, `marchid`, `mimpid`, `mhartid`

**Modo S:** `sstatus`, `sie`, `stvec`, `scounteren`, `sscratch`, `sepc`, `scause`, `stval`, `sip`, `satp`

### Mapa de Memória Física

| Endereço base | Tamanho | Dispositivo |
|---|---|---|
| `0x0000_0000` | 32 KB | BRAM de instrução (IROM) |
| `0x1000_0000` | 64 KB | BRAM de dados (DRAM) |
| `0x0200_0000` | 64 B | CLINT (`mtime`, `mtimecmp`, `msip`) |
| `0x0C00_0000` | 4 MB | PLIC (31 fontes, 1 contexto M) |
| `0xF000_0000` | 4 B | FIFO TX da UART |

### Simulação GHDL

```powershell
# Windows: criar junção ASCII (GHDL não suporta caracteres Unicode em caminhos)
New-Item -ItemType Junction -Path C:\ghdl `
         -Target "C:\Users\<usuario>\OneDrive\Área de Trabalho\Arquitetura de CPU"

cd C:\ghdl
.\sim\run_sim.ps1           # teste de fumaça (72 ciclos)
.\sim\run_sim.ps1 -wave     # + gera cpu_top_tb.vcd para GTKWave
.\sim\run_sim.ps1 -clean    # limpa objetos compilados e reexecuta
```

**Saída esperada:**
```
[TB] ciclo=72   PC=0x00000058
[TB] CPU alcançou endereço de HALT.
[TB] Teste concluído em 72 ciclos.
[TB] PASS
```

### Síntese FPGA VHDL (Vivado — Artix-7)

```tcl
vivado -mode batch -source syn/vivado_synth.tcl
```

**Uso estimado (Arty A7-35T):**

| Recurso | Utilizado | Disponível | % |
|---------|-----------|------------|---|
| LUT | ~3.500 | 20.800 | ~17% |
| FF | ~4.000 | 41.600 | ~10% |
| RAMB36 | 8 | 50 | 16% |
| DSP48E1 | 4 | 90 | 4% |

### Limitações Conhecidas

| # | Limitação | Impacto |
|---|---|---|
| 1 | RV32C não suporta PCs não alinhados a 4 bytes | Código com mistura 16/32-bit em fronteiras ímpares |
| 2 | D-cache não descarrega no `FENCE` | Software deve descarregar antes de operações de DMA |
| 3 | Uma transação AXI pendente por canal | Menor largura de banda de pico |
| 4 | `mtime` incrementa por ciclo de CPU (não é tempo real) | `mtime` ≠ relógio de parede |

### Roadmap

Concluído ✅: RV32IMAC · Zicsr · Sv32 MMU · caches L1 · CLINT · PLIC · forwarding completo · preditor de desvios · modos M/S/U · medeleg/mideleg

Planejado 🔧: RV32C alinhado a 2 bytes · suite de conformidade RISC-V · cache N-way · PLIC modo S · contadores de performance · verificação formal · JTAG debug

---

## Início Rápido

### Pré-requisitos

| Ferramenta | Uso | Download |
|---|---|---|
| Python 3.11+ | EduRISC-16 lab + `main.py` | python.org |
| Icarus Verilog ≥ 11 | EduRISC-32 RTL sim | bleyer.org/icarus |
| GTKWave | Visualizar waveforms VCD | gtkwave.sourceforge.net |
| GHDL ≥ 4.0 | RV32IMAC VHDL sim | github.com/ghdl/ghdl |
| Vivado 2023.x | Síntese Artix-7 | xilinx.com |

### EduRISC-16 Python — Demo

```bash
cd "Arquitetura de CPU"
python main.py demo

# Saída esperada:
#   Demo 1: R2 = 15   (sum 1..5 via assembly)
#   Demo 2: R0 = 15   (sum 1..5 via código C-like compilado)
```

### EduRISC-32 Verilog — Testbench

```bash
iverilog -g2012 -I rtl_v -o sim.out testbench/cpu_tb.v rtl_v/*.v
vvp sim.out

# Saída esperada:
#   7 PASS / 0 FAIL
#   *** TODOS OS TESTES PASSARAM ***
```

### RV32IMAC VHDL — Simulação

```powershell
New-Item -ItemType Junction -Path C:\ghdl -Target $PWD
cd C:\ghdl
.\sim\run_sim.ps1

# Saída esperada:
#   [TB] PASS
```

### Comparação Python vs RTL

```bash
# Compilar programa C-like e comparar simuladores
python main.py build   programa.c -o prog.hex
python main.py compare prog.hex

# Saída esperada:
#   Reg       Python           RTL     Match
#   R0     0x0000000F    0x0000000F    OK
#   ...
#   *** TODOS OS REGISTRADORES COINCIDEM ***
```

---

## Documentação

| Arquivo | Conteúdo |
|---------|----------|
| `docs/rtl_architecture.md` | **EduRISC-32 RTL**: ISA, diagrama de blocos, temporização do pipeline, forwarding, hazards, simulação, FPGA |
| `docs/isa_reference.md` | EduRISC-16: referência completa da ISA |
| `docs/pipeline_guide.md` | Guia do pipeline Python (forwarding, hazards, estágios) |
| `docs/assembler_guide.md` | Sintaxe do assembler EduRISC-16 |
| `docs/compiler_guide.md` | Linguagem C-like: construções suportadas e geração de código |

---

## Referências

- [Especificação ISA Não Privilegiada RISC-V v20191213](https://github.com/riscv/riscv-isa-manual)
- [Especificação de Arquitetura Privilegiada RISC-V v20211203](https://github.com/riscv/riscv-isa-manual)
- [Especificação PLIC RISC-V](https://github.com/riscv/riscv-plic-spec)
- [ARM IHI0022E — Especificação AXI4-Lite](https://developer.arm.com/documentation/ihi0022/e/)
- [Documentação GHDL](https://ghdl.github.io/ghdl/)
- [Patterson & Hennessy — Computer Organization and Design, RISC-V Edition](https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-820331-7)

---

## Licença

MIT License — veja [LICENSE](LICENSE) para detalhes.
Desenvolvido por: **Escanearcpl** www.escanearcplx.com
