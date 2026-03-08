# Laboratório Completo de Arquitetura de Computadores

> **Repositório triplo:** CPU **EduRISC-32v2** em Verilog-2012 (microarquitetura completa com cache L1, MMU, OS, FPGA Arty A7) + laboratório educacional **EduRISC-32v2** em Python (assembler, compilador C-like, simulador, toolchain) + núcleo **RV32IMAC** em VHDL-2008 (grau Linux, Sv32, caches L1, CLINT, PLIC).

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Estrutura de Diretórios](#estrutura-de-diretórios)
3. [EduRISC-32v2 — Microarquitetura RTL](#eduriscv-32v2--microarquitetura-rtl)
4. [EduRISC-32v2 — Laboratório Python](#eduriscv-32v2--laboratório-python)
5. [RV32IMAC — Núcleo VHDL-2008](#rv32imac--núcleo-vhdl-2008)
6. [Início Rápido](#início-rápido)
7. [Referências](#referências)

---

## Visão Geral

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       Arquitetura de Computadores Lab                            │
│                                                                                  │
│  ┌──────────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐   │
│  │   EduRISC-32v2 RTL       │  │  EduRISC-32v2 Python │  │  RV32IMAC VHDL  │   │
│  │   (Verilog-2012)         │  │  (ferramentas)        │  │  (VHDL-2008)    │   │
│  │                          │  │                       │  │                  │   │
│  │  32-bit, 32 regs, 57 ins │  │  Assembler 32v2       │  │  RV32IMAC+Zicsr │   │
│  │  Pipeline 5 estágios     │  │  Compilador C-like    │  │  Sv32 MMU       │   │
│  │  Cache L1 I$/D$ (4KB)    │  │  Simulador Python     │  │  Caches L1      │   │
│  │  MMU 2-nível, TLB 32     │  │  Linker + Loader      │  │  CLINT + PLIC   │   │
│  │  Interrupt controller    │  │  Web Visualizer        │  │  GHDL verified  │   │
│  │  OS (kernel + scheduler) │  │  Demo soma 1..5=15    │  │                  │   │
│  │  FPGA Arty A7-35T        │  └──────────────────────┘  └─────────────────┘   │
│  │  Performance counters    │                                                    │
│  └──────────────────────────┘                                                    │
│                                                                                  │
│  Ponto de entrada unificado:  python main.py <comando>                           │
└─────────────────────────────────────────────────────────────────────────────────┘
```

| Camada | Linguagem | Status | Destaque |
|---|---|---|---|
| EduRISC-32v2 RTL | Verilog-2012 | ✅ Completo | 30 módulos, cache, MMU, OS, FPGA |
| EduRISC-32v2 Lab | Python 3.11+ | ✅ Completo | Assembler+Compiler+Linker+Loader+Web |
| RV32IMAC VHDL | VHDL-2008 | ✅ Completo | 28 unidades, GHDL PASS |

---

## Estrutura de Diretórios

```
.
├── rtl_v/                         ← EduRISC-32v2 RTL (Verilog-2012)
│   ├── isa_pkg.vh                 #   Constantes de opcode e CSR
│   ├── cpu_top.v                  #   Instância top-level + csr_regfile
│   ├── register_file.v            #   Banco 32×32-bit, dual-read, single-write
│   ├── program_counter.v          #   PC 26-bit com stall/load
│   ├── pipeline_if.v              #   Estágio IF (I-cache + fetch)
│   ├── pipeline_id.v              #   Estágio ID (decode + reg read)
│   ├── pipeline_ex.v              #   Estágio EX (ALU + branch unit)
│   ├── pipeline_mem.v             #   Estágio MEM (D-cache + MMU)
│   ├── pipeline_wb.v              #   Estágio WB (write-back)
│   ├── memory_interface.v         #   Interface barramento → cache
│   ├── perf_counters.v            #   Contadores: ciclos, instret, miss
│   ├── cache/
│   │   ├── icache.v               #   I-cache 4KB direct-mapped
│   │   ├── dcache.v               #   D-cache 4KB write-back
│   │   └── cache_controller.v    #   Árbitro I$/D$ ↔ memória
│   ├── mmu/
│   │   ├── tlb.v                  #   TLB 32 entradas fully-associative FIFO
│   │   ├── page_table.v           #   Page Table Walker 2 níveis
│   │   └── mmu.v                  #   MMU top: TLB + PTW
│   ├── interrupts/
│   │   ├── interrupt_controller.v #   8 fontes vetorizadas (timer + EXT)
│   │   └── exception_handler.v   #   CSR EPC/CAUSE/STATUS + pipeline flush
│   ├── control/
│   │   └── control_unit.v        #   Sinais de controle por opcode
│   ├── hazard/
│   │   └── hazard_unit.v         #   Load-use stall + branch flush
│   └── execute/
│       ├── alu.v                  #   ALU 32-bit (14 ops + flags)
│       ├── multiplier.v           #   Multiplier 3-stage pipeline
│       ├── divider.v              #   Divisor iterativo 32 ciclos
│       ├── branch_unit.v         #   Branch/Jump resolver
│       └── forwarding_unit.v     #   Forwarding EX/MEM→EX e MEM/WB→EX
│
├── fpga/
│   ├── top.v                      #   Wrapper FPGA: clock 100→25MHz, LEDs
│   ├── build.tcl                  #   Script Vivado batch (synth→route→bit)
│   └── arty_a7.xdc               #   Constraints para Arty A7-35T
│
├── boot/
│   └── bootloader.asm            #   Bootloader ASM: init stack, CSR, BSS, IVT
│
├── os/
│   ├── kernel.c                   #   kernel_main, tabela de processos
│   ├── scheduler.c                #   Context save/restore, round-robin
│   ├── memory.c                   #   Heap first-fit (kmalloc/kfree)
│   └── syscalls.c                 #   10 syscalls (SYS_EXIT..SYS_UPTIME)
│
├── verification/
│   ├── cpu_tb.v                   #   Testbench principal (12 testes)
│   ├── pipeline_tests.v           #   5 testes de forwarding/stalls
│   ├── cache_tests.v              #   3 testes I$/D$
│   └── mmu_tests.v               #   6 testes TLB + PTW
│
├── toolchain/
│   ├── __init__.py               #   Exports: Linker, Loader (v2.0.0)
│   ├── linker.py                  #   Linker: JSON .obj → Intel HEX
│   └── loader.py                  #   Loader: Intel HEX → .mem/.coe/vinit
│
├── cpu/
│   └── instruction_set.py        #   ISA EduRISC-32v2: opcodes, formatos,
│                                  #   encode/decode/disassemble
│
├── assembler/
│   └── assembler.py              #   Assembler 2-passagens para EduRISC-32v2
│
├── compiler/
│   └── compiler.py               #   Compilador C-like → ASM 32v2
│
├── simulator/                     #   Simulador Python EduRISC-32v2
│
├── web/
│   ├── index.html                 #   8 painéis: Pipeline, Regs, CSR, Cache, MMU
│   ├── styles.css                 #   Dark theme, CSS variables, responsivo
│   └── cpu_visualization.js      #   Simulador completo 32v2 em JavaScript
│
├── docs/
│   ├── isa_spec.md               #   Especificação completa da ISA (57 instrucoes)
│   ├── pipeline_architecture.md  #   Diagrama do pipeline, forwarding, hazards
│   ├── cache_design.md           #   Cache L1 I$/D$ 4KB, FSM, address breakdown
│   ├── memory_system.md          #   Mapa de memória, MMU, TLB, PTW, MMIO
│   └── os_interface.md           #   Syscalls, ABI, exceções, estados de processo
│
├── rtl/                           ← RV32IMAC VHDL-2008
│   ├── cpu_top.vhd
│   ├── fetch/, decode/, execute/  #   28 unidades de design
│   ├── memory/, writeback/
│   ├── cache/, csr/, mmu/
│   └── pkg/
│
├── main.py                        ← CLI unificado (13 comandos)
├── README.md
└── LEIAME.md
```

---

## EduRISC-32v2 — Microarquitetura RTL

### ISA

- **32 bits** por instrução (6 formatos: R/I/S/B/J/U)
- **32 registradores**: R0=zero, R30=SP, R31=LR
- **57 instruções**: aritmética, lógica, shifts, mov, loads/stores, branches, system
- **Espaço de endereçamento**: 26 bits → 256 MB
- **CSRs**: STATUS, IVT, EPC, CAUSE, ESCRATCH, PTBR, TLBCTL, CYCLE, CYCLEH, INSTRET, ICOUNT, DCMISS, ICMISS, BRMISS

### Pipeline

```
[IF]  →  [ID]  →  [EX]  →  [MEM]  →  [WB]

Forwarding:  EX/MEM → EX,  MEM/WB → EX
Hazards:     Load-use (1 stall),  Branch taken (1 flush), MUL (3 stalls), DIV (32 stalls)
```

### Cache L1

| | I-Cache | D-Cache |
|---|---|---|
| Tamanho | 4 KB | 4 KB |
| Organização | Direct-mapped, 256×4w | Direct-mapped, 256×4w |
| Write policy | Read-only | Write-back + Write-allocate |

### MMU / TLB

- TLB: 32 entradas fully-associative, política FIFO
- PTW: 2 níveis, páginas de 4 KB (VPN[31:22] + VPN[21:12])
- Exceções: LOAD_PF, STORE_PF, IFETCH_PF

### OS embutido

| Arquivo | Função |
|---|---|
| `boot/bootloader.asm` | Inicializa SP, CSR STATUS/IVT, BSS; salta para kernel_main |
| `os/kernel.c` | process table, round-robin scheduler, UART I/O |
| `os/scheduler.c` | context\_save / context\_restore / scheduler\_tick |
| `os/memory.c` | first-fit heap: kmalloc, kfree, coalescência |
| `os/syscalls.c` | 10 syscalls: EXIT, WRITE, READ, MALLOC, FREE, YIELD, SLEEP, GETPID, FORK, UPTIME |

### FPGA

| Parâmetro | Valor |
|---|---|
| Target | Arty A7-35T (xc7a35ticsg324-1L) |
| Clock externo | 100 MHz |
| Clock CPU | 25 MHz |
| Pinos | CLK=E3, RST=C2, LED[3:0]=H5/J5/T9/T10, UART\_TX=D10, UART\_RX=A9 |

```bash
python main.py fpga-build        # Gera bitstream via Vivado batch
```

### Verificação

```bash
# Compilar e rodar todos os testbenches com Icarus Verilog
iverilog -g2012 -Irtl_v rtl_v/**/*.v verification/cpu_tb.v -o cpu_tb.out
vvp cpu_tb.out            # → "=== Results: 12/12 PASS ==="

iverilog -g2012 -Irtl_v rtl_v/**/*.v verification/pipeline_tests.v -o pipe_tb.out
vvp pipe_tb.out           # → "=== Pipeline Tests: 5/5 PASS ==="

iverilog -g2012 -Irtl_v rtl_v/cache/*.v verification/cache_tests.v -o cache_tb.out
vvp cache_tb.out          # → cache tests PASS

iverilog -g2012 -Irtl_v rtl_v/mmu/*.v verification/mmu_tests.v -o mmu_tb.out
vvp mmu_tb.out            # → mmu tests PASS
```

---

## EduRISC-32v2 — Laboratório Python

### Ferramentas disponíveis

```bash
# Montar arquivo .asm → Intel HEX
python main.py assemble boot/bootloader.asm -o boot.hex --listing

# Compilar C-like → Assembly
python main.py compile programa.c -o prog.asm

# Compilar + montar (pipeline completo)
python main.py build programa.c -o prog.hex

# Simular
python main.py simulate prog.hex --trace --max-cycles 500000

# Depurador interativo
python main.py debug prog.hex

# Ligar arquivos objeto
python main.py link obj1.json obj2.json -o linked.hex

# Converter HEX para formato Vivado BRAM
python main.py load linked.hex --format coe -o prog.coe

# Rodar demonstração integrada (somaSum 1..5 = 15)
python main.py demo
```

### Assembler (`assembler/assembler.py`)

- 2 passagens: varredura de labels + geração de código
- Formatos R / I / S / B / J / U
- Diretivas: `.org`, `.word`, `.data`, `.equ`
- Aliases: `zero`=R0, `sp`=R30, `lr`=R31

### Compilador C-like (`compiler/compiler.py`)

- Lexer → Parser recursivo descendente → CodeGen
- Suporte: `int`, `if/else`, `while`, expressões binárias (+−×÷&|^), comparações, chamadas de função
- Usa MOVI (16-bit) / MOVHI+ORI (32-bit) para literais — sem pool de dados
- BEQ/BNE R_cond, R0, label para condicionais

### Toolchain (`toolchain/`)

| Módulo | Classe | Função |
|---|---|---|
| `linker.py` | `Linker` | JSON .obj → Intel HEX com relocações (abs26, pc16, imm16) |
| `loader.py` | `Loader` | Intel HEX → `.mem` (Verilog $readmemh), `.coe` (Vivado), `_init.v` |

### Web Visualizer (`web/`)

Abra `web/index.html` no navegador. Painéis:
1. **Control** — botões Step/Run/Reset + editor de assembly inline
2. **Pipeline** — 5 estágios IF/ID/EX/MEM/WB com estado (active/stall/flush)
3. **Registradores** — R0–R31 em grid 8 colunas
4. **CSR** — STATUS, IVT, EPC, CAUSE, PTBR e contadores
5. **Cache I$** — 256 sets, hit/miss, taxa de acertos
6. **Cache D$** — 256 sets, dirty bits, write-back
7. **MMU / TLB** — 32 entradas, FIFO, hit/miss
8. **Performance** — CYCLE, INSTRET, IPC, miss rates

---

## RV32IMAC — Núcleo VHDL-2008

Pipeline de 5 estágios para RISC-V RV32IMAC compliant:

| Módulo (rtl/) | Função |
|---|---|
| `cpu_top.vhd` | Top-level com AXI4-Lite |
| `fetch/fetch_stage.vhd` | I-cache + branch predictor |
| `decode/decode_stage.vhd` | Decodificador + register file |
| `execute/alu.vhd` | ALU + branch comparator |
| `memory/memory_stage.vhd` | D-cache + LSU |
| `writeback/writeback_stage.vhd` | Write-back |
| `mmu/mmu.vhd` | Sv32 MMU + TLB |
| `csr/csr_reg.vhd` | CSRs RISC-V (mstatus, mie, mip, …) |
| `cache/icache.vhd` + `dcache.vhd` | Caches L1 |

**Verificação:**
```bash
ghdl -a --std=08 rtl/*.vhd rtl/**/*.vhd
ghdl -e --std=08 cpu_top
ghdl -r --std=08 cpu_top --vcd=wave.vcd
# → [TB] PASS
```

---

## Início Rápido

### Pré-requisitos

| Ferramenta | Versão mínima | Uso |
|---|---|---|
| Python | 3.11 | Assembler, compiler, simulator, toolchain |
| Icarus Verilog | 11.0 | Simulação RTL |
| GHDL | 3.0 | Simulação VHDL |
| Vivado | 2022.2+ | Bitstream FPGA |
| GTKWave | 3.3+ | Visualização de waveforms (opcional) |

### Demo em 3 passos

```bash
# 1. Clone e entre na pasta
cd "Arquitetura de CPU"

# 2. Rode a demo Python integrada
python main.py demo
# → Resultado em R2 = 15 (esperado: 15)
# → Assembly gerado + simulação do código compilado

# 3. Abra a visualização web
start web/index.html
# → Abre o simulador interativo EduRISC-32v2 no browser
```

### Simulação RTL

```bash
# Montar o bootloader
python main.py assemble boot/bootloader.asm -o boot.hex

# Simular RTL
python main.py rtl-sim boot.hex

# Verificação completa com testbench principal
iverilog -g2012 -Irtl_v $(Get-ChildItem rtl_v -Recurse -Filter "*.v" | % FullName) verification/cpu_tb.v -o sim.out
vvp sim.out
```

---

## Referências

- [RISC-V Specification v2.2](https://riscv.org/technical/specifications/)
- Patterson & Hennessy, *Computer Organization and Design RISC-V Edition*, 2ed
- Harris & Harris, *Digital Design and Computer Architecture: RISC-V Edition*
- Vivado Design Suite User Guide (UG912)
- Arty A7 Reference Manual — Digilent
- [GHDL Documentation](https://ghdl.github.io/ghdl/)
Desenvolvedor principal do projeto: **Escanearcpl** www.escanearcplx.com