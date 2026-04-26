# Plataforma Completa de Computação — Arquitetura de CPU + OS + Hypervisor

# ([EM DESENVOLVIMENTO!!!])

> **Repositório quádruplo:** CPU **EduRISC-32v2** em Verilog-2012 (microarquitetura com cache L1, branch prediction, MMU, interrupt controller) + **OS** (microkernel, escalonador, gerenciamento de memória, syscalls, interrupts, processos) + **Hypervisor Tipo 1** (bare-metal, 4 VMs, context switch, shadow page tables, trap delegation) + laboratório educacional **EduRISC-32v2** em Python + núcleo **RV32IMAC** em VHDL-2008.

## Status das Trilhas

| Trilha | Status | Escopo atual |
|---|---|---|
| EduRISC-32v2 Python + Toolchain | Suportado | Baseline funcional do projeto; CLI, assembler, compiler, simulator, loader e testes automatizados |
| EduRISC-32v2 RTL Verilog | Suportado | Implementação principal de hardware em Verilog-2012 |
| OS + Hypervisor em C | Suportado em evolução | Camada de software de sistema alinhada à plataforma EduRISC-32v2 |
| RV32IMAC em VHDL | Trilha paralela | Núcleo separado, com objetivo próprio e documentação específica |
| Artefatos EduRISC-16 | Legado educacional | Material histórico e de referência; não definem a arquitetura principal vigente |

Leitura recomendada:

- Para a plataforma principal, use [README.md](README.md), [docs/isa_spec.md](docs/isa_spec.md), [docs/pipeline_architecture.md](docs/pipeline_architecture.md), [docs/memory_system.md](docs/memory_system.md) e [docs/os_interface.md](docs/os_interface.md).
- Para material histórico, consulte os documentos explicitamente marcados como legado em [docs](docs).

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Estrutura de Diretórios](#estrutura-de-diretórios)
3. [Camada 1 — CPU Architecture (RTL Verilog)](#camada-1--cpu-architecture-rtl-verilog)
4. [Camada 2 — Operating System](#camada-2--operating-system)
5. [Camada 3 — Hypervisor Tipo 1](#camada-3--hypervisor-tipo-1)
6. [EduRISC-32v2 — Laboratório Python + Toolchain](#eduriscv-32v2--laboratório-python--toolchain)
7. [RV32IMAC — Núcleo VHDL-2008](#rv32imac--núcleo-vhdl-2008)
8. [Início Rápido](#início-rápido)
9. [Fluxo Completo: C → CPU → FPGA](#fluxo-completo-c--cpu--fpga)
10. [Referências](#referências)

---

## Visão Geral

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                  Plataforma Completa de Computação  EduRISC-32v2                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  CAMADA 3 — HYPERVISOR TIPO 1 (bare-metal)                                       │
│  hypervisor/  hv_core.c  vm_manager.c  vm_memory.c  vm_cpu.c  trap_handler.c    │
│  • 4 VMs concorrentes  • context switch completo  • shadow page tables           │
│  • hypercalls (SYSCALL ≥ 0x80)  • preemptive round-robin  • ERET-based dispatch │
│                              ↑  runs inside                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│  CAMADA 2 — OPERATING SYSTEM (microkernel)                                       │
│  os/  kernel.c  scheduler.c  process.c  memory.c  syscalls.c  interrupts.c      │
│  • 8 processos  • IRQ subsystem (8 fontes)  • PCB completo  • kmalloc/kfree     │
│  • Round-robin + context save/restore  • 10 syscalls  • process_create/exit     │
│                              ↑  runs inside                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│  CAMADA 1 — CPU ARCHITECTURE (RTL + boot)                                        │
│  rtl_v/  pipeline 5 estágios  cache L1 I$/D$  MMU+TLB  interrupt controller     │
│  boot/   bootloader.asm + bootloader.c  (UART, timer, GPIO, flash loader)        │
│  • 32-bit / 32 regs / 57 inst  • branch prediction (2-bit BTB 64 entradas)      │
│  • forwarding + hazard detection  • FPGA Arty A7-35T  • 30 módulos Verilog      │
│                              ↑  hardware                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│  TOOLCHAIN (Python)                                                               │
│  toolchain/  assembler.py  compiler.py  linker.py  loader.py  debugger.py       │
│  assembler/  compiler/  simulator/  web/  (8-panel visualizer)                   │
│                                                                                   │
│  VERIFICATIONN                                                                    │
│  verification/  cpu_tb.v  pipeline_tests.v  cache_tests.v  mmu_tests.v          │
│                 hypervisor_tests.v  (10 HV scenarios)                             │
│                                                                                   │
│  FPGA                                          RV32IMAC (VHDL-2008)              │
│  fpga/  syn/  top.v  constraints.xdc           rtl/  28 unidades, GHDL PASS     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

| Camada | Conteúdo | Status |
|---|---|---|
| Hypervisor Tipo 1 | hv_core, vm_manager, vm_memory, vm_cpu, trap_handler | ✅ Novo |
| Operating System | kernel, scheduler, process, memory, syscalls, interrupts | ✅ Expandido |
| CPU Architecture | 31 módulos Verilog + branch predictor BTB | ✅ Expandido |
| Boot | bootloader.asm + bootloader.c (UART/timer/GPIO) | ✅ Novo |
| Toolchain | assembler + compiler + linker + loader + debugger | ✅ Completo |
| EduRISC-32v2 Python | Simulador + web visualizer (8 painéis) | ✅ Completo |
| RV32IMAC VHDL | 28 unidades, GHDL verified | ✅ Completo |

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
│   ├── bootloader.asm            #   Bootloader ASM: init stack, CSR, BSS, IVT
│   └── bootloader.c              #   Bootloader C: UART, timer, GPIO, flash loader
│
├── os/
│   ├── kernel.c                   #   kernel_main, tabela de processos
│   ├── scheduler.c                #   Context save/restore, round-robin
│   ├── memory.c                   #   Heap first-fit (kmalloc/kfree)
│   ├── syscalls.c                 #   10 syscalls (SYS_EXIT..SYS_UPTIME)
│   ├── interrupts.c               #   IRQ registration, dispatch, pending queue
│   └── process.c                  #   PCB management, create/exit/wait/block
│
├── hypervisor/
│   ├── hypervisor.h               #   Types: vm_t, vcpu_state_t, hv_state_t
│   ├── hv_core.c                  #   Init, main scheduling loop, panic
│   ├── vm_manager.c               #   VM create/destroy/start/pause/schedule
│   ├── vm_memory.c                #   Shadow page tables, GPA→HPA translation
│   ├── vm_cpu.c                   #   vCPU save/restore, ERET trampoline
│   └── trap_handler.c             #   Trap dispatch: timer/syscall/fault/illegal
│
├── verification/
│   ├── cpu_tb.v                   #   Testbench principal (12 testes)
│   ├── pipeline_tests.v           #   5 testes de forwarding/stalls
│   ├── cache_tests.v              #   3 testes I$/D$
│   ├── mmu_tests.v               #   6 testes TLB + PTW
│   └── hypervisor_tests.v        #   10 testes HV (traps, ERET, CSRs, timer IRQ)
│
├── toolchain/
│   ├── __init__.py               #   Exports: Linker, Loader, Assembler, Compiler, Debugger
│   ├── linker.py                  #   Linker: JSON .obj → Intel HEX
│   ├── loader.py                  #   Loader: Intel HEX → .mem/.coe/vinit
│   ├── assembler.py               #   Assembler wrapper: .asm → .hex/.obj/.bin
│   ├── compiler.py                #   Compiler wrapper: .c → .asm [→ .hex]
│   └── debugger.py                #   Interactive debugger REPL + batch mode
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

## Camada 1 — CPU Architecture (RTL Verilog)

### ISA EduRISC-32v2

- **32 bits** por instrução (6 formatos: R/I/S/B/J/U)
- **32 registradores**: R0=zero, R30=SP, R31=LR
- **57 instruções**: aritmética, lógica, shifts, mov, loads/stores, branches, system
- **Espaço de endereçamento**: 26 bits → 256 MB
- **CSRs**: STATUS, IVT, EPC, CAUSE, PTBASE, TIMECMP, IM e performance counters

### Pipeline 5 estágios

```
[IF]  →  [ID]  →  [EX]  →  [MEM]  →  [WB]

Forwarding:      EX/MEM → EX,  MEM/WB → EX
Hazard detection: Load-use (1 stall),  Branch taken (1 flush)
Mul/Div:         MUL = 3 stalls,  DIV = 32 stalls (iterativo)
Branch prediction: BTB 64 entradas, contadores 2-bit saturantes (~88%)
```

### Branch Predictor (novo)

- **Bimodal predictor**: BTB direto com 64 entradas × 2-bit saturating counter
- `rtl_v/branch_predictor.v`: prediction port (IF) + update port (EX)
- Detecção automática de misprediction → flush sinal para pipeline

### Cache L1

| | I-Cache | D-Cache |
|---|---|---|
| Tamanho | 4 KB | 4 KB |
| Organização | Direct-mapped, 256×4w | Direct-mapped, 256×4w |
| Write policy | Read-only | Write-back + Write-allocate |

---

## Camada 2 — Operating System

### Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `os/kernel.c` | `kernel_main()`, tabela de processos, inicialização |
| `os/scheduler.c` | Round-robin, context save/restore, tick handler |
| `os/process.c` | PCB management: `process_create/exit/wait/block/unblock` (NOVO) |
| `os/memory.c` | `kmalloc/kfree`, first-fit heap |
| `os/syscalls.c` | 10 syscalls: write, malloc, free, yield, sleep, exit, getpid, uptime, open, close |
| `os/interrupts.c` | IRQ registration, dispatch, pending queue, per-source masking (NOVO) |

### Interrupt Subsystem (novo)

```c
interrupts_init();
irq_register(IRQ_UART_RX, uart_rx_handler, &uart_dev);
irq_enable(IRQ_UART_RX);
global_irq_enable();
// → irq_dispatch() chamado pelo IVT stub com o número da IRQ
```

8 fontes de interrupção: Timer (IRQ 0), UART RX/TX, GPIO, SPI, I2C, DMA, EXT.

### Process Management (novo)

```c
int pid = process_create(entry_addr, priority, "my_task");
// processo passa por: READY → RUNNING → BLOCKED → READY → ZOMBIE → FREE
process_exit(0);
process_wait(child_pid, &exit_code);
```

---

## Camada 3 — Hypervisor Tipo 1

### Filosofia

```
Hardware (EduRISC-32v2 CPU)
       ↓
Hypervisor (privilegio máximo — "ring -1")
   ├─ VM 0 → Guest OS A   (executa como "ring 0 restrito")
   ├─ VM 1 → Guest OS B
   ├─ VM 2 → Guest OS C
   └─ VM 3 → Guest OS D
```

### Arquivos e Responsabilidades

| Arquivo | Conteúdo |
|---|---|
| `hypervisor/hypervisor.h` | Tipos: `vm_t`, `vcpu_state_t`, `hv_state_t`; códigos de trap; API pública |
| `hypervisor/hv_core.c` | `hv_init()`, `hv_main()` (loop de scheduling), `hv_panic()` |
| `hypervisor/vm_manager.c` | `vm_create/destroy/start/pause/get`, `vm_schedule_next()` |
| `hypervisor/vm_memory.c` | Shadow page table (64 PTEs/VM), `vm_alloc_memory`, `vm_translate` |
| `hypervisor/vm_cpu.c` | `vcpu_init/save_state/restore_state`, `vcpu_run()` (ERET trampoline) |
| `hypervisor/trap_handler.c` | `trap_handle()` dispatcher, hypercalls (≥0x80), fault injection |

### Fluxo de Trap

```
Guest instrução → TRAP
   hardware: EPC ← PC; CAUSE ← cause; PC ← IVT[cause]
   IVT stub: salva GPRs → s_scratch_regs[]
   trap_handle(cause, epc, badvaddr)
      ┌── TIMER      → vm_schedule_next() → hv_main() → vcpu_run(next)
      ├── SYSCALL ≥80 → hypercall handler → vcpu_run(same)
      ├── SYSCALL <80 → inject ao guest OS → vcpu_run(same)
      ├── PAGE_FAULT  → resolve SPT ou inject → vcpu_run(same)
      └── ILLEGAL     → emulate CSR / inject → vcpu_run(same)
```

### Hypercalls disponíveis

| Nº (R1) | Nome | Descrição |
|---|---|---|
| `0x80` | `HV_CALL_VERSION` | R1 ← versão do HV (0x00010000) |
| `0x81` | `HV_CALL_VM_ID` | R1 ← ID da VM atual (0-3) |
| `0x82` | `HV_CALL_VM_CREATE` | Criar nova VM filha |
| `0x83` | `HV_CALL_VM_YIELD` | Ceder CPU voluntariamente |
| `0x84` | `HV_CALL_VM_EXIT` | Terminar esta VM (R2 = exit code) |
| `0x85` | `HV_CALL_CONSOLE_PUT` | Escrever char na console do HV |

### Inicialização (via bootloader.c)

```c
// Com hipervisor (CONFIG_HYPERVISOR definido):
hv_init();
vm_create(0, 0x10000, 0x0, "guest-os-0");
vm_start(0);
hv_main();   // nunca retorna — scheduling loop infinito
```

---

## EduRISC-32v2 — Laboratório Python + Toolchain

### Toolchain unificada (novo/expandido)

```
C source (.c)
   ↓  toolchain/compiler.py    (wraps compiler/compiler.py + preprocessor)
assembly (.asm)
   ↓  toolchain/assembler.py   (wraps assembler/assembler.py, 3 formats)
Intel HEX (.hex) ou JSON obj
   ↓  toolchain/linker.py      (links múltiplos .obj → single HEX)
BRAM init (.mem / .coe / .vinit)
   ↓  toolchain/loader.py      (converte para FPGA)
CPU execution
```

Debugger interativo (novo):
```bash
python -m toolchain.debugger program.hex
(dbg) r                   # load and run
(dbg) b 0x0100            # breakpoint at 0x100
(dbg) si 10               # step 10 instructions
(dbg) pa                  # print all 32 registers
(dbg) dis 0x0100 8        # disassemble 8 instructions at 0x100
(dbg) m 0x8000 4          # dump 4 words from DMEM
```

### Comandos CLI (main.py)

```bash
python main.py demo                         # Demo soma 1..5=15
python main.py assemble prog.asm -o prog.hex --listing
python main.py compile prog.c -o prog.asm
python main.py build prog.c -o prog.hex     # compile + assemble
python main.py simulate prog.hex --trace
python main.py link a.obj b.obj -o out.hex
python main.py load out.hex -o mem.coe --format coe
python main.py fpga-build                   # gera .bit para Arty A7
python main.py debug prog.hex               # inicia debugger REPL
```

---

## RV32IMAC — Núcleo VHDL-2008

### Separação das trilhas de hardware

O repositório possui duas linhas de hardware distintas:

- **Linha principal EduRISC-32v2**: [rtl_v](rtl_v), [fpga](fpga), [boot](boot), [os](os), [hypervisor](hypervisor) e [verification](verification).
- **Linha paralela RV32IMAC em VHDL**: [rtl](rtl) e artefatos VHDL relacionados.

Importante:

- O núcleo RV32IMAC não substitui implicitamente a linha EduRISC-32v2.
- O software de sistema em [os](os) e [hypervisor](hypervisor) pertence à plataforma EduRISC-32v2.
- O fluxo `python main.py fpga-build` usa a trilha principal em Verilog, não o núcleo RV32IMAC em VHDL.

### MMU / TLB

- TLB: 32 entradas fully-associative, política FIFO
- PTW: 2 níveis, páginas de 4 KB (VPN[31:22] + VPN[21:12])
- Exceções: LOAD_PF, STORE_PF, IFETCH_PF

### Software de sistema da plataforma EduRISC-32v2

| Arquivo | Função |
|---|---|
| `boot/bootloader.asm` | Inicializa SP, CSR STATUS/IVT, BSS; salta para kernel_main |
| `os/kernel.c` | process table, round-robin scheduler, UART I/O |
| `os/scheduler.c` | context\_save / context\_restore / scheduler\_tick |
| `os/memory.c` | first-fit heap: kmalloc, kfree, coalescência |
| `os/syscalls.c` | 10 syscalls: EXIT, WRITE, READ, MALLOC, FREE, YIELD, GETPID, SLEEP, HEAPSTAT, UPTIME |

### FPGA da plataforma EduRISC-32v2

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

---

## Licença

Este projeto é distribuído sob a [MIT License](LICENSE).  
Veja o arquivo [LICENSE](LICENSE) para os termos completos.
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

### Instalação

```bash
# Clone o repositório
git clone https://github.com/excanear/Arquitetura-de-CPU.git
cd Arquitetura-de-CPU

# Instale dependências Python opcionais (apenas para testes)
pip install -r requirements.txt
```

### Demo em 3 passos

```bash
# 1. Demonstração integrada (Assembly → Simulador + C → compilador → Simulador)
python main.py demo
# → DEMO 1: Resultado em R2 = 15 (esperado: 15)  ✓
# → DEMO 2: Resultado em R1 = 15 (esperado: 15)  ✓

# 2. Ou via Makefile
make demo

# 3. Abra a visualização web (no browser)
start web/index.html   # Windows
open  web/index.html   # macOS
xdg-open web/index.html  # Linux
```

### Uso da toolchain

```bash
# Montar arquivo assembly
python main.py assemble boot/bootloader.asm -o boot.hex --listing

# Compilar C-like → Assembly
python main.py compile programa.c -o prog.asm

# Compilar + montar em um passo
python main.py build programa.c -o prog.hex

# Simular programa
python main.py simulate prog.hex --trace --max-cycles 50000

# Depurador interativo
python main.py debug prog.hex

# Equivalentes via Makefile
make assemble SRC=boot/bootloader.asm
make build    SRC=programa.c
make simulate SRC=prog.hex
```

### Simulação RTL

```bash
# Montar o bootloader
python main.py assemble boot/bootloader.asm -o boot.hex

# Simular RTL (requer Icarus Verilog)
python main.py rtl-sim boot.hex

# Verificação completa com testbench principal
iverilog -g2012 -Irtl_v rtl_v/**/*.v verification/cpu_tb.v -o sim.out
vvp sim.out
# → "=== Results: 12/12 PASS ==="
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
