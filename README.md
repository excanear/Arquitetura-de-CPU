<div align="center">

# EduRISC-32v2 · Full Computing Platform

**Arquitetura de CPU do zero — do transistor ao hypervisor**

[![Tests](https://img.shields.io/badge/tests-117%20passed-brightgreen?style=flat-square)](tests/)
[![Python](https://img.shields.io/badge/python-3.12%20%7C%203.13-blue?style=flat-square)](requirements.txt)
[![Verilog](https://img.shields.io/badge/RTL-Verilog--2012-orange?style=flat-square)](rtl_v/)
[![VHDL](https://img.shields.io/badge/RV32IMAC-VHDL--2008-purple?style=flat-square)](rtl/)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--35T-red?style=flat-square)](fpga/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

</div>

---

## Visão Executiva

Este repositório implementa uma **plataforma de computação completa e autossuficiente** —
construída integralmente do zero — com quatro camadas sobrepostas e funcionais:

| Camada | Tecnologia | Escopo |
|--------|-----------|--------|
| **Hypervisor Tipo 1** | C bare-metal | 4 VMs concorrentes, shadow page tables, trap delegation |
| **Sistema Operacional** | C (microkernel) | 8 processos, 10 syscalls, IRQ, scheduler round-robin |
| **CPU EduRISC-32v2** | Verilog-2012 | Pipeline 5 estágios, MMU, cache L1, branch predictor |
| **Toolchain Completa** | Python 3.12+ | Assembler, compilador C, simulador, linker, loader, debugger |

O projeto inclui também um **núcleo RV32IMAC em VHDL-2008** como trilha paralela, verificado com GHDL.

---

## Arquitetura em Camadas

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                  EduRISC-32v2  ·  Full Computing Platform                       ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  HYPERVISOR TIPO 1  (bare-metal, máximo privilégio)                    │    ║
║  │   VM 0 ── VM 1 ── VM 2 ── VM 3   (preemptive round-robin)             │    ║
║  │   shadow page tables · hypercalls (≥0x80) · ERET trampoline           │    ║
║  │   trap delegation: TIMER / SYSCALL / PAGE_FAULT / ILLEGAL             │    ║
║  └───────────────────────────┬─────────────────────────────────────────────┘    ║
║                               │ executa sobre                                   ║
║  ┌─────────────────────────────▼─────────────────────────────────────────────┐  ║
║  │  SISTEMA OPERACIONAL  (microkernel C)                                    │  ║
║  │   kernel_main · scheduler (round-robin) · PCB (8 processos)            │  ║
║  │   kmalloc/kfree (first-fit) · 10 syscalls · IRQ dispatcher (8 fontes)  │  ║
║  │   process_create/exit/wait/block · context save/restore                 │  ║
║  └───────────────────────────┬─────────────────────────────────────────────┘  ║
║                               │ roda em                                         ║
║  ┌─────────────────────────────▼─────────────────────────────────────────────┐  ║
║  │  CPU EduRISC-32v2  (RTL Verilog-2012)                                   │  ║
║  │   5-stage pipeline · 32-bit · 57 instruções · 32 registradores          │  ║
║  │   I$/D$ 4KB · MMU + TLB 32 entradas · branch predictor BTB 64 ent.     │  ║
║  │   MUL 3 ciclos · DIV 32 ciclos · forwarding · hazard detection           │  ║
║  │   FPGA: Arty A7-35T (Vivado)  ·  30+ módulos Verilog                   │  ║
║  └─────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                  ║
║  ┌──────────────────────────────────────────────────────────────────────────┐   ║
║  │  TOOLCHAIN PYTHON                                                        │   ║
║  │  Assembler · Compilador C · Simulador · Linker · Loader · Debugger      │   ║
║  │  117 testes · CI/CD (Python 3.12 + 3.13) · Visualizador Web 8 painéis  │   ║
║  └──────────────────────────────────────────────────────────────────────────┘   ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## ISA EduRISC-32v2

### Parâmetros Principais

| Parâmetro | Valor |
|-----------|-------|
| Largura de instrução | 32 bits (fixo) |
| Registradores | 32 × 32 bits — R0=zero, R30=SP, R31=LR |
| Espaço de endereçamento | 26 bits → 256 MB word-addressed |
| Total de instruções | **57** definidas (6 formatos: R / I / S / B / J / U) |
| CSRs | 14 nomeados — STATUS, IVT, EPC, CAUSE, PTBR, TLBCTL, TIMECMP… |
| Endianness | Big-endian |

### Formatos de Instrução

```
 31    26 25  21 20  16 15  11 10   6 5      0
┌───────┬──────┬──────┬──────┬──────┬────────┐
│op[5:0]│rd    │rs1   │rs2   │shamt │ —      │  R  (registrador)
├───────┼──────┼──────┼───────────────────────┤
│op[5:0]│rd    │rs1   │    imm16[15:0]        │  I  (imediato)
├───────┼──────┼──────┼───────────────────────┤
│op[5:0]│rs2   │rs1   │    off16[15:0]        │  S  (store)
├───────┼──────┼──────┼───────────────────────┤
│op[5:0]│rs1   │rs2   │    off16[15:0]        │  B  (branch)
├───────┼─────────────────────────────────────┤
│op[5:0]│           addr26[25:0]              │  J  (jump absoluto)
├───────┼──────┼──────────────────────────────┤
│op[5:0]│rd    │        imm21[20:0]           │  U  (upper immediate)
└───────┴──────┴──────────────────────────────┘
```

### Categorias de Instruções

| Categoria | Instruções | Exemplo |
|-----------|-----------|---------|
| Aritmética | ADD, ADDI, SUB, MUL, MULH, DIV, DIVU, REM | `ADD R3, R1, R2` |
| Lógica | AND, OR, XOR, NOT, ANDI, ORI, XORI | `ANDI R1, R1, 0xFF` |
| Shift | SLL, SRL, SRA, SLLI, SRLI, SRAI | `SLL R2, R1, R3` |
| Mov | MOV, MOVI, MOVHI | `MOVHI R1, 0xDEAD` |
| Load/Store | LW, LH, LB, LHU, LBU, SW, SH, SB | `LW R1, 8(R2)` |
| Branch | BEQ, BNE, BLT, BGT, BLE, BGE | `BEQ R1, R2, label` |
| Jump | JMP, CALL, RET, JALR | `CALL func` |
| Sistema | SYSCALL, ERET, MTC, MFC, FENCE, HLT, NOP | `MTC 0, R1` |

---

## Pipeline — 5 Estágios

```
 ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
 │    IF    │  │    ID    │  │    EX    │  │   MEM    │  │    WB    │
 │ I-Cache  │  │ Decoder  │  │   ALU    │  │ D-Cache  │  │ RegFile  │
 │ PC + MMU │  │ RegFile  │  │ MUL/DIV  │  │ MMU/TLB  │  │ Write    │
 │ BTB Pred │  │ Imm Gen  │  │ BranchU  │  │ LSU      │  │          │
 └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────┘
      ╔═══════════════════════════════════════════════════╗
      ║  Forwarding: EX/MEM → EX  ·  MEM/WB → EX        ║
      ║  Hazard: load-use stall (1 ciclo)                 ║
      ║  Branch misprediction: flush (1 ciclo)            ║
      ╚═══════════════════════════════════════════════════╝
```

| Recurso | Detalhe |
|---------|---------|
| Forwarding | EX/MEM → EX e MEM/WB → EX — sem stall para RAW normais |
| Load-use hazard | 1 ciclo de stall automático |
| Branch predictor | BTB 64 entradas, contadores 2-bit saturantes (~88% acerto) |
| Multiplicador | 3 estágios pipeline (3 stalls visíveis) |
| Divisor | Iterativo, 32 ciclos (inteiro com/sem sinal) |
| MUL High | `MULH` — 32 bits superiores do produto sinal×sinal |

---

## Subsistemas de Hardware

### Cache L1

| | I-Cache | D-Cache |
|--|---------|---------|
| Tamanho | 4 KB | 4 KB |
| Organização | Direct-mapped, 256 × 4 words | Direct-mapped, 256 × 4 words |
| Write policy | Read-only | Write-back + Write-allocate |
| CSR de miss | `CSR_ICMISS` | `CSR_DCMISS` |

### MMU + TLB

| Parâmetro | Valor |
|-----------|-------|
| Modelo | `_TLBModel` — 32 entradas fully-associative |
| Substituição | LRU (Least Recently Used) |
| Esquema | Sv32-like: VPN = VA[25:10], offset = VA[9:0] (1024 words/página) |
| Page Table | 1 nível — `PTE = mem[PTBR + VPN]`, flags V/R/W/X bits [3:0] |
| Ativação | `STATUS.KU=1` + `PTBR≠0` → user mode com tradução ativa |
| Page fault | Dispara `CAUSE_PGFAULT=2` → handler via IVT |
| TLBFLUSH | Escrita em `CSR_TLBCTL` bit 0 → flush total + auto-clear |
| Identidade | Modo kernel (KU=0): PA = VA — sem tradução |

### Controlador de Interrupções

- **8 fontes vetorizadas**: Timer (IRQ 0), UART RX/TX, GPIO, SPI, I2C, DMA, EXT
- Tabela de vetores (IVT) em `CSR_IVT` — cada entrada é uma instrução JMP de 32 bits
- `STATUS.IE` (interrupt enable global) + máscara por fonte
- Pipeline flush automático na entrada de qualquer exceção ou interrupção

### CSRs — Control & Status Registers

| Índice | Nome | Descrição |
|--------|------|-----------|
| 0 | `CSR_STATUS` | IE, KU, bits de modo |
| 1 | `CSR_IVT` | Base da tabela de vetores de interrupção |
| 2 | `CSR_EPC` | PC salvo na exceção |
| 3 | `CSR_CAUSE` | Causa: 0=ILLEGAL, 2=PGFAULT, 3=SYSCALL… |
| 4 | `CSR_ESCRATCH` | Scratch register para handler |
| 5 | `CSR_PTBR` | Base da page table |
| 6 | `CSR_TLBCTL` | TLB control — bit 0 = FLUSH |
| 7 | `CSR_TIMECMP` | Comparador do timer (trigger IRQ 0) |
| 8–10 | `CSR_CYCLE/H/INSTRET` | Contadores de ciclos e instruções |
| 11–13 | `CSR_ICMISS/DCMISS/BRMISS` | Misses de I$, D$, branches |

---

## Sistema Operacional (Microkernel C)

```
os/
├── kernel.c       kernel_main(), tabela de processos (MAX=8), subsistemas
├── scheduler.c    round-robin, context save/restore, timer tick handler
├── process.c      PCB: process_create / exit / wait / block / unblock
├── memory.c       heap first-fit: kmalloc() / kfree()
├── syscalls.c     10 syscalls via SYSCALL + CSR_CAUSE
└── interrupts.c   irq_register() / irq_enable() / irq_dispatch() — 8 fontes
```

### Ciclo de Vida do Processo

```
process_create()
      │
      ▼
  [READY] ──── scheduler tick ────► [RUNNING]
      ▲                                   │
      │     process_unblock()             │  process_block() / sleep()
      │                                   ▼
      └─────────────────────────── [BLOCKED]
                                         │
                               process_exit() / return
                                         │
                                    [ZOMBIE] ──► process_wait() ──► [FREE]
```

### Syscalls

| Nº | Nome | Descrição |
|----|------|-----------|
| 0 | `SYS_WRITE` | Escreve na UART |
| 1 | `SYS_MALLOC` | Aloca heap |
| 2 | `SYS_FREE` | Libera heap |
| 3 | `SYS_YIELD` | Cede CPU voluntariamente |
| 4 | `SYS_SLEEP` | Dorme N ticks do timer |
| 5 | `SYS_EXIT` | Termina processo atual |
| 6 | `SYS_GETPID` | Retorna PID |
| 7 | `SYS_UPTIME` | Ciclos desde boot |
| 8 | `SYS_OPEN` | Abre descritor (stub) |
| 9 | `SYS_CLOSE` | Fecha descritor (stub) |

---

## Hypervisor Tipo 1

```
Hardware EduRISC-32v2
        │
        ▼
  ┌─────────────────────────────────────────────┐
  │  HYPERVISOR  (máximo privilégio — ring -1)  │
  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐       │
  │  │ VM0 │  │ VM1 │  │ VM2 │  │ VM3 │       │
  │  │Guest│  │Guest│  │Guest│  │Guest│       │
  │  │ OS  │  │ OS  │  │ OS  │  │ OS  │       │
  │  └─────┘  └─────┘  └─────┘  └─────┘       │
  │  Shadow Page Tables · vCPU State            │
  │  Preemptive Round-Robin · ERET Trampoline   │
  └─────────────────────────────────────────────┘
```

### Fluxo de Trap

```
Guest executa instrução privilegiada ou dispara exceção
        │
        ▼
  Hardware: EPC ← PC  ·  CAUSE ← cause  ·  PC ← IVT[cause]
        │
        ▼
  IVT stub: salva GPRs → scratch_regs[]
        │
        ▼
  trap_handle(cause, epc, badvaddr)
   ├── TIMER      → vm_schedule_next() → vcpu_run(next_vm)
   ├── SYSCALL≥80 → hypercall_handler  → vcpu_run(same_vm)
   ├── SYSCALL<80 → inject ao guest OS → vcpu_run(same_vm)
   ├── PAGE_FAULT → resolve SPT ou inject fault → vcpu_run(same_vm)
   └── ILLEGAL    → emulate CSR / inject SIGILL → vcpu_run(same_vm)
```

### Hypercalls

| R1 | Nome | Ação |
|----|------|------|
| `0x80` | `HV_CALL_VERSION` | Retorna versão do HV (0x00010000) |
| `0x81` | `HV_CALL_VM_ID` | Retorna ID da VM atual (0–3) |
| `0x82` | `HV_CALL_VM_CREATE` | Cria VM filha |
| `0x83` | `HV_CALL_VM_YIELD` | Cede CPU ao HV scheduler |
| `0x84` | `HV_CALL_VM_EXIT` | Termina VM (R2 = exit code) |
| `0x85` | `HV_CALL_CONSOLE_PUT` | Escreve char na console do hypervisor |

---

## Toolchain Python

```
C source (.c)
     │  compiler/compiler.py    (preprocessador, lexer, parser, codegen)
     ▼
assembly (.asm)
     │  assembler/assembler.py  (2 passagens, relocation, 3 formatos)
     ▼
Intel HEX / JSON obj / binário
     │  toolchain/linker.py     (resolve símbolos externos, segmentos)
     ▼
.mem / .coe / vinit
     │  toolchain/loader.py     (formatos Vivado, GHDL, simulador)
     ▼
CPUSimulator / FPGA
```

### Compilador C

| Funcionalidade | Suporte |
|----------------|---------|
| Tipos | `int`, `char`, `unsigned`, ponteiros (`int *`, `void *`, `char *`) |
| Expressões | Aritmética, lógica, bitwise, shift, comparação, cast, unário |
| Controle | `if/else`, `while`, `for`, `break`, `return` |
| Funções | Parâmetros tipados, `void`, forward declarations, recursão |
| Variáveis | Globais, locais, arrays, ponteiros |
| Strings | Literais `"..."` internados na seção de dados, null-terminated |
| Preprocessador | `#include "file"`, `#define`, `#ifndef/#endif` guards, block comments |
| Alvo | EduRISC-32v2 ASM — R1–R29 (pula R26=scratch, R30=SP, R31=LR) |

### Simulador Python

- **Pipeline completo** com registradores de pipeline explícitos IF/ID/EX/MEM/WB
- **Forwarding** e **hazard detection** idênticos ao RTL Verilog
- **Cache model** (`_CacheModel`): I$ e D$ com hit/miss tracking → CSRs
- **MMU/TLB** (`_TLBModel`): 32 entradas LRU, Sv32-like, page fault via `_raise_exception`
- **CSRs com semântica real**: ciclos, instret, miss counters, EPC/CAUSE/STATUS
- **MUL/DIV latency**: 3 e 32 stalls respectivamente
- **Exceções e traps**: IVT, ERET, SYSCALL, PGFAULT com handler correto
- **`dump_state()`**: regs, flags, CSRs, I$, D$, TLB em saída consolidada

### CLI Unificado (13 comandos)

```bash
python main.py compile   examples/fibonacci.c -o fib.asm
python main.py assemble  examples/fibonacci.asm -o fib.hex
python main.py build     examples/fibonacci.c -o fib.hex   # compile + assemble
python main.py simulate  fib.hex --cycles 500 --dump
python main.py debug     fib.hex                            # REPL interativo
python main.py link      a.obj b.obj -o out.hex
python main.py load      out.hex -o prog.coe --format coe
python main.py demo                                         # soma 1..5 = 15
```

---

## Suite de Testes

```
tests/
├── test_simulator.py          28 testes — pipeline, ISA, cache, MMU/TLB, traps
├── test_assembler.py          Assembler 2-passagens, todos os formatos
├── test_compiler.py           Compilador C: expressões, funções, ponteiros, strings
├── test_toolchain.py          Integração: C → asm → hex → simulação
├── test_cli_integration.py    CLI completo: 13 comandos
└── test_contract_consistency.py   Consistência ISA spec ↔ implementação
```

```
117 passed  ·  0 failed  ·  Python 3.12 + 3.13  ·  CI/CD GitHub Actions
```

### Cobertura MMU/TLB

| Teste | Cobertura |
|-------|-----------|
| `test_mmu_kernel_mode_identity` | KU=0 → PA = VA, sem consulta à TLB |
| `test_mmu_tlb_miss_then_hit` | Page walk no miss, hit no segundo acesso |
| `test_tlb_page_fault_invalid_pte` | PTE.V=0 → page fault |
| `test_tlb_permission_write_fault` | Página R-only → write retorna None |
| `test_tlb_flush` | Flush invalida entradas → forçar novo miss |
| `test_tlbflush_via_csr_write` | CSR_TLBCTL bit 0 → `tlb.flush()` + auto-clear |

---

## Início Rápido

### Pré-requisitos

```bash
pip install -r requirements.txt   # pytest, e dependências opcionais
```

### Demo em 3 comandos

```bash
git clone https://github.com/excanear/Arquitetura-de-CPU.git
cd Arquitetura-de-CPU
python main.py demo
```

### Fluxo completo: C → Assembly → Simulação

```bash
# Escreva o programa
echo 'int main() { int x=10; int y=32; return x+y; }' > hello.c

# Compile
python main.py compile hello.c -o hello.asm

# Simule (resultado em R1 = 42)
python main.py simulate hello.asm --cycles 200 --dump
```

### FPGA (Arty A7-35T)

```bash
vivado -mode batch -source fpga/build.tcl
# gera: bitstream + timing report + utilization
```

### Verificação RTL

```bash
iverilog -g2012 -Irtl_v rtl_v/**/*.v verification/cpu_tb.v -o cpu_tb.out
vvp cpu_tb.out   # → "=== Results: 12/12 PASS ==="
```

---

## Estrutura do Repositório

```
.
├── rtl_v/              EduRISC-32v2 RTL Verilog-2012 (30+ módulos)
│   ├── cpu_top.v       Top-level: pipeline + CSR file + perf counters
│   ├── pipeline_*.v    IF · ID · EX · MEM · WB
│   ├── cache/          icache.v · dcache.v · cache_controller.v
│   ├── mmu/            tlb.v · page_table.v · mmu.v
│   ├── interrupts/     interrupt_controller.v · exception_handler.v
│   └── execute/        alu.v · multiplier.v · divider.v · branch_unit.v
│
├── rtl/                RV32IMAC VHDL-2008 (28 unidades, GHDL verified)
├── fpga/               Arty A7-35T: top.v · build.tcl · arty_a7.xdc
├── syn/                Vivado · Quartus · scripts de síntese
│
├── os/                 Sistema Operacional (C)
│   ├── kernel.c / kernel.asm
│   ├── scheduler.c · process.c · memory.c
│   └── syscalls.c / syscalls.asm · interrupts.c
│
├── hypervisor/         Hypervisor Tipo 1 (C)
│   ├── hv_core.c · vm_manager.c · vm_memory.c
│   └── vm_cpu.c · trap_handler.c · hypervisor.h
│
├── boot/               bootloader.asm · bootloader.c
│
├── assembler/          Assembler 2-passagens (Python)
├── compiler/           Compilador C-like → ASM EduRISC-32v2 (Python)
├── simulator/          Simulador pipeline 5 estágios + MMU + Cache (Python)
├── toolchain/          Linker · Loader · Debugger (Python)
├── cpu/                ISA: opcodes, encode/decode/disassemble
│
├── verification/       Testbenches Verilog
│   ├── cpu_tb.v · pipeline_tests.v · cache_tests.v
│   └── mmu_tests.v · hypervisor_tests.v
│
├── web/                Visualizador Web 8 painéis
│   └── index.html · styles.css · cpu_visualization.js
│
├── tests/              Suite pytest (117 testes)
│
├── docs/               Especificações técnicas
│   ├── isa_spec.md           57 instruções, codificação binária completa
│   ├── pipeline_architecture.md
│   ├── cache_design.md
│   ├── memory_system.md      Mapa de memória, MMU, MMIO
│   └── os_interface.md       ABI, syscalls, estados de processo
│
├── examples/           Programas de exemplo (.c e .asm)
├── main.py             CLI unificado (13 comandos)
└── requirements.txt
```

---

## Mapa de Memória

```
0x00000000 – 0x0000FFFF   Código (texto)           64K words
0x00010000 – 0x0001FFFF   Dados globais            64K words
0x00020000 – 0x0003FFFF   Heap (kmalloc)          128K words
0x00040000 – 0x0007FFFF   Stack (cresce ↓)        256K words
0x00080000 – 0x000FFFFF   Espaço de usuário       512K words
0x3FFF0000 – 0x3FFF00FF   MMIO — UART             TX=0x00, STATUS=0x02
0x3FFF0100 – 0x3FFF01FF   MMIO — Timer            MTIME, MTIMECMP
0x3FFF0200 – 0x3FFF02FF   MMIO — GPIO
0x3FFF0300 – 0x3FFF03FF   MMIO — SPI
```

---

## Mapa de Progresso

| Componente | Status |
|------------|--------|
| ISA EduRISC-32v2 — 57 instruções, 6 formatos | ✅ |
| Pipeline RTL Verilog-2012 — 30+ módulos | ✅ |
| Branch predictor BTB 64 entradas, 2-bit saturante | ✅ |
| Cache L1 I$/D$ 4KB direct-mapped | ✅ |
| MMU + TLB 32 entradas LRU (RTL + simulador Python) | ✅ |
| Controlador de interrupções 8 fontes vetorizadas | ✅ |
| FPGA Arty A7-35T — síntese Vivado | ✅ |
| Bootloader ASM + C (UART, timer, GPIO) | ✅ |
| OS microkernel C — 8 processos, 10 syscalls | ✅ |
| Hypervisor Tipo 1 — 4 VMs, shadow page tables | ✅ |
| Toolchain Python — assembler + compilador C | ✅ |
| Simulador pipeline + cache + MMU/TLB | ✅ |
| Suite de testes — 117 testes, 0 falhas | ✅ |
| CI/CD GitHub Actions — Python 3.12 + 3.13 matrix | ✅ |
| RV32IMAC VHDL-2008 — 28 unidades, GHDL OK | ✅ |
| Visualizador Web — 8 painéis | ✅ |

---

## Referências Técnicas

| Documento | Conteúdo |
|-----------|---------|
| [docs/isa_spec.md](docs/isa_spec.md) | 57 opcodes, formatos, codificação binária completa |
| [docs/pipeline_architecture.md](docs/pipeline_architecture.md) | Pipeline 5 estágios, forwarding, hazards, branch predictor |
| [docs/cache_design.md](docs/cache_design.md) | Cache L1 I$/D$, FSM, endereçamento, write policies |
| [docs/memory_system.md](docs/memory_system.md) | Mapa de memória, MMU, TLB, page table walk, MMIO |
| [docs/os_interface.md](docs/os_interface.md) | ABI, syscalls, exceções, ciclo de vida de processos |
| [docs/contrato_arquitetural.md](docs/contrato_arquitetural.md) | Invariantes e contratos entre camadas |

---

<div align="center">

**EduRISC-32v2 Full Computing Platform**  
CPU · OS · Hypervisor · Toolchain — construídos do zero.

</div>
