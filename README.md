# Laboratório Completo de Arquitetura de Computadores

> **Repositório duplo:** processador RV32IMAC em VHDL-2008 para FPGA **+** laboratório educacional Python completo com ISA própria, assembler, simulador, depurador, compilador C-like, visualizador web e micro-OS.

---

## 🧪 EduRISC-16 — Laboratório Educacional Python

Implementação completa de uma CPU educacional de 16 bits do zero, incluindo todas as camadas da pilha de software:

```
┌─────────────────────────────────────────────────────────────────┐
│                   EduRISC-16 Lab Stack                           │
│                                                                   │
│  Código C-like ──► Compilador ──► Assembly ──► Assembler         │
│                                       │             │             │
│                                  Depurador ◄── Simulador         │
│                                       │         Pipeline 5-stage  │
│                                  Web Viz        Forwarding        │
│                                  browser        Hazard detection  │
│                                                                   │
│  Micro-OS: kernel.asm + syscalls.asm (EduRISC-16 Assembly)       │
└─────────────────────────────────────────────────────────────────┘
```

### Início Rápido

```bash
# Demo integrada (assembler + compilador + simulador)
python main.py demo

# Montar e executar arquivo assembly
python main.py run exemplos/soma.asm

# Compilar C-like e executar
python main.py build programa.c

# Depurador interativo
python main.py debug programa.asm

# Visualizador web — abrir no browser
start web/index.html
```

### Estrutura do Laboratório

| Diretório | Conteúdo |
|-----------|----------|
| `cpu/` | ISA EduRISC-16, banco de registradores, ALU, pipeline |
| `assembler/` | Tokenizer, parser, assembler dois-passos |
| `compiler/` | Lexer + parser recursivo + gerador de código C→ASM |
| `simulator/` | Simulador pipeline 5-estágios com forwarding |
| `simulator/debugger.py` | CLI interativo: step, breakpoints, mem dump |
| `web/` | Visualizador de pipeline em HTML/CSS/JS puro |
| `os/` | Micro-kernel + syscalls em EduRISC-16 Assembly |
| `docs/` | Documentação: ISA, pipeline, assembler, compilador |

### EduRISC-16 ISA — Resumo

| Parâmetro | Valor |
|-----------|-------|
| Largura de palavra | 16 bits |
| Registradores | 16 × R0–R15 (R15 = LR) |
| Instruções | 16 (ADD/SUB/MUL/DIV/AND/OR/XOR/NOT/LOAD/STORE/JMP/JZ/JNZ/CALL/RET/HLT) |
| Pipeline | 5 estágios com forwarding e detecção de hazards |
| Memória | 64K palavras (128 KB) |

### Comandos do Depurador

```
(dbg) step          → avança 1 ciclo
(dbg) run 100       → executa até 100 ciclos
(dbg) break 0x020   → breakpoint em 0x020
(dbg) print R1      → exibe valor de R1
(dbg) mem 0x100 16  → dump de memória
(dbg) dis 0x000 20  → desmonta 20 instruções
(dbg) history       → snapshots do pipeline
(dbg) log           → log de eventos
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
    int resultado = fib(8);  // resultado = 21
    return resultado;
}
```

```bash
python main.py build fib.c       # compila + monta
python main.py simulate fib.hex  # executa e exibe resultado
```

---

## ⚙️  Núcleo de Processador RV32IMAC — VHDL-2008

> Núcleo de processador RISC-V totalmente sintetizável, em ordem, com pipeline de 5 estágios, escrito em **VHDL-2008**.
> Direcionado a hardware FPGA real — não é um modelo de software ou emulador.

Um processador completo **RV32IMAC + Zicsr + Sv32** com suporte a modos de privilégio M/S/U — a base mínima de hardware necessária para inicializar o Linux. O design inclui um Page Table Walker Sv32 em hardware, caches L1 de instrução e dados, um preditor de desvios saturante de 1 bit, um CLINT e um PLIC — tudo como RTL sintetizável sem IP de fabricante.

---

## Resumo

| Atributo | Valor |
|---|---|
| Linguagem | **VHDL-2008** (IEEE 1076-2008) |
| ISA | RISC-V **RV32IMAC + Zicsr + Sv32** |
| Níveis de privilégio | **M / S / U** — apto para Linux |
| Pipeline | Em ordem, 5 estágios (IF → ID → EX → MEM → WB) |
| Placas alvo | Digilent Arty A7-35T · Terasic DE0-Nano |
| Ferramentas de síntese | Vivado 2023.x · Quartus Prime 23.1 Lite |
| Recursos estimados | ~4.000 LUTs · ~4.800 FFs · 8× RAMB36 (Artix-7) |
| Simulador | GHDL 5.1.1 — teste de fumaça de 72 ciclos → **[TB] PASS** |
| Unidades RTL | 28 unidades de design VHDL |

---

## Índice

1. [Funcionalidades](#funcionalidades)
2. [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
3. [Estrutura de Diretórios](#estrutura-de-diretórios)
4. [Pipeline](#pipeline)
5. [Cobertura da ISA](#cobertura-da-isa)
6. [Arquitetura de CSR e Privilégio](#arquitetura-de-csr-e-privilégio)
7. [Subsistema de Memória](#subsistema-de-memória)
8. [MMU — Sv32](#mmu--sv32)
9. [Interrupções — CLINT e PLIC](#interrupções--clint-e-plic)
10. [Preditor de Desvios](#preditor-de-desvios)
11. [Interface AXI4-Lite](#interface-axi4-lite)
12. [Síntese em FPGA](#síntese-em-fpga)
13. [Simulação](#simulação)
14. [Limitações Conhecidas](#limitações-conhecidas)
15. [Roadmap](#roadmap)
16. [Referências](#referências)

---

## Funcionalidades

| Funcionalidade | Status |
|---|---|
| ISA base RV32I — todas as 37 instruções | ✅ |
| RV32M — MUL / MULH / MULHSU / MULHU / DIV / DIVU / REM / REMU | ✅ |
| RV32A — LR.W / SC.W + 9 operações AMO | ✅ |
| RV32C — 16 bits comprimido (descompressor combinacional, alinhado a 4 bytes¹) | ✅ parcial |
| Zicsr — CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI | ✅ |
| Traps, exceções e interrupções em modo M | ✅ |
| Níveis de privilégio modo S e modo U | ✅ |
| medeleg / mideleg — delegação de trap para modo S | ✅ |
| ECALL (causa por privilégio: U=8, S=9, M=11) | ✅ |
| EBREAK / MRET / SRET | ✅ |
| FENCE / FENCE.I — flush do pipeline + icache | ✅ |
| SFENCE.VMA — invalidação da TLB | ✅ |
| Caminhos de forwarding completos (EX→EX, MEM→EX) | ✅ |
| Detecção de hazard load-use e stall | ✅ |
| Preditor de desvios saturante de 1 bit + BTB de 64 entradas | ✅ |
| I-cache L1 — mapeamento direto, 256 conjuntos, linhas de 16 B | ✅ |
| D-cache L1 — write-back / write-allocate, 256 conjuntos, linhas de 16 B | ✅ |
| MMU — Sv32 PTW de 2 níveis + TLB de 16 entradas | ✅ |
| CLINT — mtime / mtimecmp / msip | ✅ |
| PLIC — 31 fontes, 1 contexto modo M | ✅ |
| Dois barramentos AXI4-Lite master independentes (IM + DM) | ✅ |
| Testbench de teste de fumaça GHDL | ✅ |

> ¹ Instruções comprimidas são descomprimidas no estágio IF apenas para endereços alinhados a 4 bytes. Suporte completo alinhado a 2 bytes (buffer de busca em meia-palavra) é uma melhoria planejada.

---

## Visão Geral da Arquitetura

```
                    ┌──────────────────────────────────────────────────────────────┐
                    │                        cpu_top                               │
                    │                                                              │
  ┌──────────┐      │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────────┐     │
  │  icache  │◄────►│  │  IF  │─►│  ID  │─►│  EX  │─►│ MEM  │─►│   WB     │     │
  └──────────┘      │  │      │  │      │  │      │  │      │  │          │     │
       │            │  │pc_reg│  │decode│  │ alu  │  │ lsu  │  │ regfile  │     │
  IM AXI4-Lite      │  │btb   │  │immgen│  │ bcmp │  │      │  │          │     │
                    │  │bhand │  │rfile │  │ fwd  │  │      │  │          │     │
  ┌──────────┐      │  └──────┘  └──────┘  └──────┘  └──────┘  └──────────┘     │
  │  dcache  │◄────►│                                                              │
  └──────────┘      │  ┌────────────┐   ┌──────────────────────────────────────┐  │
       │            │  │  csr_reg   │   │  MMU (Sv32 PTW + TLB 16 entradas)    │  │
  DM AXI4-Lite      │  │  mstatus   │   │  satp · privilégio · mxr · sum       │  │
                    │  │  mepc/sepc │   └──────────────────────────────────────┘  │
  PTW AXI4-Lite     │  │  medeleg   │                      │ PTW AXI4-Lite        │
       └────────────┤  │  mideleg   │◄─────────────────────┘                      │
                    │  └────────────┘                                              │
                    └──────────────────────────────────────────────────────────────┘
```

### Portas de Nível Superior (`cpu_top`)

| Porta | Largura | Direção | Descrição |
|---|---|---|---|
| `clk_i` | 1 | entrada | Clock do sistema |
| `rst_i` | 1 | entrada | Reset síncrono ativo em nível alto |
| `im_ar_*` / `im_r_*` | — | master | AXI4-Lite AR+R — busca de instrução |
| `dm_ar_*` / `dm_r_*` / `dm_aw_*` / `dm_w_*` / `dm_b_*` | — | master | AXI4-Lite — carga/armazenamento de dados |
| `irq_external_i` | 1 | entrada | MEIP — interrupção externa de máquina (do PLIC) |
| `irq_timer_i` | 1 | entrada | MTIP — interrupção de timer de máquina (do CLINT) |
| `irq_software_i` | 1 | entrada | MSIP — interrupção de software de máquina (do CLINT) |
| `pc_o` | 32 | saída | PC atual (depuração / monitoramento) |

---

## Estrutura de Diretórios

```
.
├── rtl/                               ← RTL VHDL-2008 sintetizável
│   ├── pkg/
│   │   ├── cpu_pkg.vhd               # Tipos centrais, constantes, registros de pipeline
│   │   └── axi4_pkg.vhd              # Definições de registros AXI4-Lite
│   ├── fetch/
│   │   ├── fetch_stage.vhd           # IF: FSM AXI, descompressor, predição de desvios
│   │   ├── pc_reg.vhd                # Registrador de contador de programa
│   │   ├── branch_handler.vhd        # Mux de PC por prioridade (trap/mret/sret/fence/jalr/btb/+4)
│   │   ├── decompressor.vhd          # Descompressor combinacional RV32C 16→32 bits
│   │   └── branch_predictor.vhd      # Histórico de 1 bit + BTB de 64 entradas
│   ├── decode/
│   │   ├── decode_stage.vhd          # Estágio ID
│   │   ├── instruction_decoder.vhd   # Decodificador combinacional (RV32IMAC + Zicsr + AMO)
│   │   ├── immediate_generator.vhd   # Codificações de imediato I/S/B/U/J
│   │   └── register_file.vhd         # RF 32×32 (x0 fixo em 0)
│   ├── execute/
│   │   ├── execute_stage.vhd         # Estágio EX
│   │   ├── alu.vhd                   # RV32I + RV32M (casos especiais de mul/div)
│   │   ├── branch_comparator.vhd     # BEQ/BNE/BLT/BGE/BLTU/BGEU
│   │   └── forwarding_unit.vhd       # Forwarding EX/MEM + MEM/WB, detecção de load-use
│   ├── memory/
│   │   ├── memory_stage.vhd          # Estágio MEM
│   │   └── load_store_unit.vhd       # FSM AXI: LD/ST + LR/SC + 9 operações AMO
│   ├── writeback/
│   │   └── writeback_stage.vhd       # WB: resultado da ALU ou dado lido → banco de registradores
│   ├── csr/
│   │   └── csr_reg.vhd               # CSRs modo M+S, medeleg/mideleg, MRET/SRET,
│   │                                 #   registrador de privilégio, contadores cycle/instret
│   ├── cache/
│   │   ├── icache.vhd                # I-cache L1: mapeamento direto, slave+master AXI
│   │   └── dcache.vhd                # D-cache L1: write-back/write-allocate
│   ├── mmu/
│   │   └── mmu.vhd                   # Sv32 PTW (2 níveis), TLB de 16 entradas, verificação de permissão
│   ├── clint/
│   │   └── clint.vhd                 # CLINT: mtime/mtimecmp/msip (slave AXI4-Lite)
│   ├── plic/
│   │   └── plic.vhd                  # PLIC: 31 fontes, 1 contexto modo M (slave AXI4-Lite)
│   └── cpu_top.vhd                   # Integração de nível superior
├── syn/                               ← Infraestrutura de síntese FPGA
│   ├── arty_a7_top.vhd               # Wrapper de placa: Arty A7-35T (BRAM + UART + CLINT + PLIC)
│   ├── arty_a7.xdc                   # Restrições de temporização + pinos (Artix-7)
│   ├── vivado_synth.tcl              # Script Vivado sem projeto (síntese → bitstream)
│   ├── quartus.qsf                   # Projeto Quartus Prime (Cyclone IV / DE0-Nano)
│   └── quartus.sdc                   # Restrições de temporização SDC para Quartus
└── sim/
    ├── cpu_top_tb.vhd                # TB de teste de fumaça GHDL (ROM de 24 instruções, slaves AXI)
    └── run_sim.ps1                   # Script PowerShell de compilação + simulação
```

---

## Pipeline

### Resumo dos Estágios

| Estágio | Arquivo | Operações principais |
|---|---|---|
| **IF** | `fetch_stage.vhd` | FSM AXI de busca · descompressor RV32C · consulta BTB · redirecionamento de desvio |
| **ID** | `decode_stage.vhd` | Decodificação de instrução · geração de imediato · leitura de registradores · resolução de JAL |
| **EX** | `execute_stage.vhd` | ALU/MUL/DIV · comparação de desvio · mux de forwarding · resolução de JALR |
| **MEM** | `memory_stage.vhd` | FSM AXI de carga/armazenamento · LR/SC/AMO · leitura/escrita CSR · geração de trap |
| **WB** | `writeback_stage.vhd` | Escrita do resultado da ALU ou dado lido de volta ao banco de registradores |

### Diagrama do Pipeline

```
  Ciclo:   1       2       3       4       5
         ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐
  Instr  │ IF │─►│ ID │─►│ EX │─►│MEM │─►│ WB │
  N      └────┘  └────┘  └────┘  └────┘  └────┘
                ┌────┐  ┌────┐  ┌────┐  ┌────┐
  Instr N+1     │ IF │─►│ ID │─►│ EX │─►│ WB │
                └────┘  └────┘  └────┘  └────┘
```

### Tratamento de Hazards

| Hazard | Resolução |
|---|---|
| RAW (não-load) | Forwarding completo: EX/MEM → EX e MEM/WB → EX |
| RAW load-use | Stall de 1 ciclo + forwarding de MEM/WB |
| Predição de desvio errada | Flush de IF/ID (1 bolha), redirecionamento de PC |
| JAL | Resolvido em ID — 1 bolha |
| JALR | Resolvido em EX — 2 bolhas |
| TRAP / MRET / SRET | Flush completo do pipeline, redirecionamento para mtvec / mepc / sepc |
| FENCE.I | Flush do pipeline + invalidação dos bits de validade da I-cache |
| SFENCE.VMA | Flush do pipeline + invalidação da TLB |

### Prioridade de Redirecionamento de PC (branch_handler)

```
 1. Trap (exceção ou interrupção)       — maior prioridade
 2. MRET
 3. SRET
 4. FENCE.I
 5. JALR
 6. Desvio tomado (resolvido em EX)
 7. JAL (resolvido em ID)
 8. Predição BTB (resolvida em IF)
 9. PC + 4                              — padrão
```

---

## Cobertura da ISA

### RV32I — Inteiros Base (todas as 37)

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

### RV32M — Multiplicação / Divisão (todas as 8)

Todos os casos especiais obrigatórios da especificação RISC-V tratados:

| Instrução | Casos especiais |
|---|---|
| `MUL` `MULH` `MULHSU` `MULHU` | Produto intermediário de 64 bits |
| `DIV` `DIVU` | Divisão por zero → `0xFFFF_FFFF` |
| `REM` `REMU` | Divisão por zero → dividendo |
| `DIV` `REM` | Overflow `INT_MIN / −1` → `INT_MIN` / `0` |

### RV32A — Atômicas (todas as 11)

Implementadas dentro da FSM da LSU como uma sequência de leitura-modificação-escrita AXI4-Lite:

| Instrução | Descrição |
|---|---|
| `LR.W` | Load-Reserved (define registrador de reserva de 32 bits) |
| `SC.W` | Store-Conditional (sucede apenas se a reserva ainda é válida) |
| `AMOSWAP.W` | Troca atômica |
| `AMOADD.W` | Adição atômica |
| `AMOXOR.W` | XOR atômico |
| `AMOAND.W` | AND atômico |
| `AMOOR.W` | OR atômico |
| `AMOMIN.W` | Mínimo atômico com sinal |
| `AMOMAX.W` | Máximo atômico com sinal |
| `AMOMINU.W` | Mínimo atômico sem sinal |
| `AMOMAXU.W` | Máximo atômico sem sinal |

### RV32C — 16 bits Comprimido (parcial)

Um descompressor puramente combinacional (`decompressor.vhd`) expande todos os grupos de instruções Q0/Q1/Q2 para seus equivalentes RV32I/M de 32 bits antes do registrador de pipeline IF/ID. Sem microcódigo ou tabelas de consulta — atribuições de sinal concorrentes puras.

> **Limitação atual**: correto apenas para instruções comprimidas em PCs alinhados a 4 bytes. Suporte completo requer um buffer de busca em meia-palavra (planejado).

### Zicsr — Instruções CSR (todas as 6)

`CSRRW` `CSRRS` `CSRRC` `CSRRWI` `CSRRSI` `CSRRCI`

---

## Arquitetura de CSR e Privilégio

### Modos de Privilégio

Três níveis de privilégio: **M** (Máquina) · **S** (Supervisor) · **U** (Usuário).

- Registrador `priv_r` em `csr_reg.vhd` rastreia o nível de privilégio atual
- Inicia em modo M (`"11"`) após reset
- Salvo/restaurado via `mstatus.MPP` (MRET) e `mstatus.SPP` (SRET)

### CSRs de Modo M

| Endereço | CSR | Descrição |
|---|---|---|
| `0x300` | `mstatus` | Status de máquina (MPP, SPP, MPIE, SPIE, MIE, SIE, MPRV, MXR, SUM) |
| `0x302` | `medeleg` | Delegação de exceções para modo S |
| `0x303` | `mideleg` | Delegação de interrupções para modo S |
| `0x304` | `mie` | Habilitação de interrupção de máquina |
| `0x305` | `mtvec` | Endereço base do tratador de trap de máquina |
| `0x340` | `mscratch` | Registrador scratch de máquina |
| `0x341` | `mepc` | PC de exceção de máquina |
| `0x342` | `mcause` | Causa de trap de máquina |
| `0x343` | `mtval` | Valor de trap de máquina |
| `0x344` | `mip` | Interrupção de máquina pendente (definido por hardware) |
| `0xC00` | `cycle` | Contador de ciclos (32 bits inferiores) |
| `0xC80` | `cycleh` | Contador de ciclos (32 bits superiores) |
| `0xC02` | `instret` | Contador de instruções retiradas |
| `0xF11` | `mvendorid` | ID de fabricante (0x0) |
| `0xF12` | `marchid` | ID de arquitetura (0x0) |
| `0xF13` | `mimpid` | ID de implementação (0x1) |
| `0xF14` | `mhartid` | ID de thread de hardware (0x0) |

### CSRs de Modo S

| Endereço | CSR | Descrição |
|---|---|---|
| `0x100` | `sstatus` | Status de supervisor (subconjunto de mstatus) |
| `0x104` | `sie` | Habilitação de interrupção de supervisor |
| `0x105` | `stvec` | Vetor de trap de supervisor |
| `0x106` | `scounteren` | Habilitação de contadores para modo U |
| `0x140` | `sscratch` | Registrador scratch de supervisor |
| `0x141` | `sepc` | PC de exceção de supervisor |
| `0x142` | `scause` | Causa de trap de supervisor |
| `0x143` | `stval` | Valor de trap de supervisor |
| `0x144` | `sip` | Interrupção de supervisor pendente |
| `0x180` | `satp` | Tradução de endereço de supervisor (modo Sv32 + PPN) |

### Causas de Trap / Exceção

| `mcause` | Evento |
|---|---|
| `0x1` | Falha de acesso a instrução |
| `0x2` | Instrução ilegal |
| `0x3` | Breakpoint (EBREAK) |
| `0x4` | Endereço de carga desalinhado |
| `0x6` | Endereço de armazenamento/AMO desalinhado |
| `0x8` | Chamada de ambiente do modo U |
| `0x9` | Chamada de ambiente do modo S |
| `0xB` | Chamada de ambiente do modo M |
| `0xC` | Falha de página de instrução (Sv32) |
| `0xD` | Falha de página de carga (Sv32) |
| `0xF` | Falha de página de armazenamento/AMO (Sv32) |
| `0x8000_000B` | Interrupção externa de máquina (MEIP) |
| `0x8000_0007` | Interrupção de timer de máquina (MTIP) |
| `0x8000_0003` | Interrupção de software de máquina (MSIP) |
| `0x8000_0009` | Interrupção externa de supervisor (SEIP, quando delegada) |
| `0x8000_0005` | Interrupção de timer de supervisor (STIP, quando delegada) |
| `0x8000_0001` | Interrupção de software de supervisor (SSIP, quando delegada) |

### Delegação de Trap

Quando o bit de um trap está definido em `medeleg` (exceções) ou `mideleg` (interrupções) e o hart não está em modo M, o trap é tratado em modo S:
- `sepc` ← PC com falha
- `scause` ← código de causa
- `stval` ← endereço da falha / bits de instrução
- PC ← `stvec`
- `sstatus.SPP` ← privilégio anterior
- privilégio ← S

### MRET / SRET

| Instrução | Restaura | Salta para |
|---|---|---|
| `MRET` | `mstatus.MPP` → privilégio · `MPIE` → `MIE` | `mepc` |
| `SRET` | `mstatus.SPP` → privilégio · `SPIE` → `SIE` | `sepc` |

---

## Subsistema de Memória

### I-cache L1

| Parâmetro | Valor |
|---|---|
| Organização | Mapeamento direto |
| Conjuntos | 256 (genérico `N_LINES`) |
| Tamanho da linha | 4 palavras / 16 B (genérico `LINE_WORDS`) |
| Substituição | Trivial (mapeamento direto) |
| Invalidação | FENCE.I — todos os bits de validade limpos em um ciclo |

FSM de miss: `IDLE → FILL_ADDR → FILL_DATA → RESPOND`

### D-cache L1

| Parâmetro | Valor |
|---|---|
| Organização | Mapeamento direto, write-back |
| Conjuntos | 256 (genérico `N_LINES`) |
| Tamanho da linha | 4 palavras / 16 B (genérico `LINE_WORDS`) |
| Política de escrita | Write-back + write-allocate |
| Remoção de linha suja | Antes do preenchimento em miss para linha suja |

FSM de miss/remoção: `IDLE → RFILL_ADDR → RFILL_DATA → RRESPOND` (miss limpo)
ou `IDLE → WB_ADDR → WB_DATA → WB_RESP → RFILL_...` (remoção de linha suja)

### Mapa de Memória Física (wrapper de placa)

| Endereço base | Tamanho | Dispositivo |
|---|---|---|
| `0x0000_0000` | 32 KB | BRAM de instrução (IROM) |
| `0x1000_0000` | 64 KB | BRAM de dados (DRAM) |
| `0x0200_0000` | 64 B | Registradores CLINT |
| `0x0C00_0000` | 4 MB | Registradores PLIC |
| `0xF000_0000` | 4 B | FIFO TX da UART |

---

## MMU — Sv32

Ativada pelo genérico `ENABLE_VM` e escrevendo `satp.MODE=1` em tempo de execução.

### Layout de Endereço Virtual (Sv32)

```
 31        22 21        12 11           0
┌────────────┬────────────┬─────────────┐
│  VPN[1]    │  VPN[0]    │   offset    │
│  10 bits   │  10 bits   │  12 bits    │
└────────────┴────────────┴─────────────┘
```

### Entrada de Tabela de Páginas (PTE)

```
 31      10  9  8  7  6  5  4  3  2  1  0
┌──────────┬────┬──┬──┬──┬──┬──┬──┬──┬──┐
│ PPN[21:0]│RSW │D │A │G │U │X │W │R │V │
└──────────┴────┴──┴──┴──┴──┴──┴──┴──┴──┘
```

### Máquina de Estados do PTW

```
S_IDLE ──► S_CHECK_TLB ──acerto──────────────────────────► S_CHECK_PERM
                │                                                  │
                └─miss─► S_WALK_L1_ADDR ─► S_WALK_L1_DATA         │
                                                 │                 │
                                  superpágina ───┤      perm OK ──► S_HIT ─► S_IDLE
                                  ponteiro    ───┤    perm falhou ─► S_FAULT ─► S_IDLE
                                                 │
                              S_WALK_L2_ADDR ─► S_WALK_L2_DATA ─► S_CHECK_PERM
```

### TLB

- 16 entradas, mapeamento direto, indexada por `VA[15:12]`
- Tag: `VA[31:12]` (VPN completo)
- Dado: `PA[31:12]` + bits de permissão `{U, X, W, R, V}`
- Invalidada em um ciclo por `SFENCE.VMA`

### Regras de Permissão

| Modo | Regra |
|---|---|
| Modo M | Ignora todas as verificações de PTE |
| Modo S | Não pode acessar páginas U=1 a menos que `mstatus.SUM=1` |
| Modo U | Requer U=1 na PTE |
| MXR | Páginas somente-execução legíveis como dado quando `mstatus.MXR=1` |

---

## Interrupções — CLINT e PLIC

### CLINT — Controlador de Interrupção Local do Núcleo (`rtl/clint/clint.vhd`)

Mapeado em memória em `0x0200_0000`:

| Offset | Registrador | Largura | Descrição |
|---|---|---|---|
| `0x0000` | `msip` | 32 bits | Interrupção de software de máquina pendente (bit 0) |
| `0x4000` | `mtimecmp_lo` | 32 bits | Comparador de timer — 32 bits inferiores |
| `0x4004` | `mtimecmp_hi` | 32 bits | Comparador de timer — 32 bits superiores |
| `0xBFF8` | `mtime_lo` | 32 bits | Contador em tempo real — 32 bits inferiores |
| `0xBFFC` | `mtime_hi` | 32 bits | Contador em tempo real — 32 bits superiores |

- `mtime` incrementa 1 a cada ciclo de clock
- `timer_irq` assinalado quando `mtime ≥ mtimecmp`
- Limpo escrevendo novo valor `mtimecmp` > `mtime` atual
- `software_irq` = `msip[0]` (definido/limpo por software)

### PLIC — Controlador de Interrupção de Plataforma (`rtl/plic/plic.vhd`)

Mapeado em memória em `0x0C00_0000`:

| Offset | Registrador | Descrição |
|---|---|---|
| `0x0000–0x007C` | `priority[1..31]` | Prioridade por fonte (0 = desabilitado) |
| `0x1000` | `pending[0]` | Bits de interrupção pendente (1 por fonte) |
| `0x2000` | `enable[0]` | Habilitação por fonte para contexto 0 (modo M) |
| `0x20_0000` | `threshold` | Limiar mínimo de prioridade para contexto 0 |
| `0x20_0004` | `claim/complete` | IRQ pendente de maior prioridade (leitura=claim, escrita=complete) |

- 31 fontes de interrupção (fontes 1–31; fonte 0 é reservada)
- 1 contexto modo M (extensível para modo S com contexto adicional)
- `external_irq` assinalado quando alguma fonte habilitada e pendente excede o limiar

### Cabeamento de Interrupções (wrapper de placa)

```
CLINT.timer_irq    ──► cpu_top.irq_timer_i    (MTIP em mip)
CLINT.software_irq ──► cpu_top.irq_software_i (MSIP em mip)
PLIC.external_irq  ──► cpu_top.irq_external_i (MEIP em mip)
```

---

## Preditor de Desvios

Localizado em `fetch_stage.vhd`, instancia `branch_predictor.vhd`.

| Propriedade | Valor |
|---|---|
| Algoritmo | Contador de histórico saturante de 1 bit |
| Entradas BTB | 64, mapeamento direto |
| Índice BTB | `PC[7:2]` (6 bits) |
| Tag BTB | `PC[31:8]` (24 bits) |
| Predição | Tomado se `history=1` E acerto de tag BTB |
| Penalidade de erro | 1 bolha (flush apenas de IF/ID) |
| Atualização | 1 ciclo após resolução do desvio em EX |

---

## Interface AXI4-Lite

Três portas master AXI4-Lite independentes em `cpu_top`:

| Prefixo da porta | Canais | Propósito |
|---|---|---|
| `im_*` | AR + R | Busca de instrução (através da I-cache) |
| `dm_*` | AR + R + AW + W + B | Carga/armazenamento de dados (através da D-cache e LSU) |
| (PTW interno) | AR + R (barramento DM compartilhado) | Caminhada de tabela de páginas (inativo em modo bare) |

Características:
- Transação pendente única por canal (sem burst, sem AXI ID)
- `ARPROT[2]=1` em todos os endereços de busca de instrução
- Handshake padrão valid/ready em todos os canais
- `ARSIZE`/`AWSIZE` codifica granularidade de byte-enable (byte, meia-palavra, palavra)

---

## Síntese em FPGA

Todo o RTL é VHDL-2008 agnóstico de fabricante. Nenhum core IP ou primitivo de fabricante é usado no núcleo. As memórias são inferidas a partir de processos VHDL síncronos e mapeadas para BRAM/M9K pela ferramenta de síntese.

### Placas Alvo

| Placa | Dispositivo | Ferramenta | Clock alvo |
|---|---|---|---|
| Digilent Arty A7-35T | XC7A35T-1CSG324C | Vivado 2023.x | 100 MHz |
| Digilent Arty A7-100T | XC7A100T-1CSG324C | Vivado 2023.x | 100 MHz |
| Terasic DE0-Nano | EP4CE22F17C6 | Quartus Prime 23.1 | 50 / 100 MHz (PLL) |

### Utilização Estimada de Recursos — Arty A7-35T (todas as funcionalidades habilitadas)

| Recurso | Utilizado | Disponível | % |
|---|---|---|---|
| LUT | ~3.500 | 20.800 | ~17% |
| FF | ~4.000 | 41.600 | ~10% |
| RAMB36 | 8 | 50 | 16% |
| DSP48E1 | 4 | 90 | 4% |

*Estimativas pós-síntese. Números pós-roteamento dependem da versão da ferramenta e configurações de otimização.*

### Vivado (Artix-7) — Fluxo em Lote

```tcl
# A partir da raiz do workspace, no Console Tcl do Vivado ou em modo lote:
vivado -mode batch -source syn/vivado_synth.tcl
```

O script (`syn/vivado_synth.tcl`) executa o fluxo de implementação completo:
1. `read_vhdl -vhdl2008` — todos os arquivos RTL em ordem de dependência
2. `synth_design -top arty_a7_top -part xc7a35tcsg324-1`
3. `opt_design` → `place_design` → `phys_opt_design` → `route_design`
4. `report_timing_summary` · `report_utilization` · `report_power`
5. `write_bitstream syn/build/arty_a7_top.bit`

### Restrições de Pinos (`syn/arty_a7.xdc`)

| Pino | Sinal | Notas |
|---|---|---|
| `E3` | `clk_100mhz_i` | XTAL de 100 MHz |
| `C2` | `rst_i` | BTN0 — reset ativo em nível alto |
| `H5 J5 T9 T10` | `led_o[3:0]` | LEDs mostram `pc[6:3]` |
| `D10` | `uart_tx_o` | UART TX @ 115200-8N1 (PMOD JA pino 1) |

### Quartus Prime (Cyclone IV) — Fluxo em Lote

```bash
quartus_sh --flow compile syn/quartus.qsf
```

`syn/quartus.qsf` lista todos os arquivos fonte VHDL-2008 e atribuições de pinos do DE0-Nano.
`syn/quartus.sdc` restringe o clock de entrada de 50 MHz usando `derive_pll_clocks`.

### Arquitetura do Wrapper de Placa (`syn/arty_a7_top.vhd`)

```
             ┌──────────────────────────────────────────────────────┐
 clk_100 ───►│                  arty_a7_top                        │
 rst     ───►│                                                      │
             │  ┌────────────┐  BRAM 32 KB ◄──────── IM AXI4-Lite  │
             │  │  cpu_top   │  BRAM 64 KB ◄──────── DM AXI4-Lite  │
             │  │            │                                      │
             │  │ irq_timer  │◄─────── CLINT.timer_irq             │
             │  │ irq_sw     │◄─────── CLINT.software_irq          │
             │  │ irq_ext    │◄─────── PLIC.external_irq           │
             │  └────────────┘                                      │
             │                                                      │
             │  ┌───────────┐  ┌─────────┐  ┌───────────────────┐  │
             │  │  u_clint  │  │ u_plic  │  │  UART TX (simples)│  │
             │  └───────────┘  └─────────┘  └───────────────────┘  │
             └──────────────────────────────────────────────────────┘
```

---

## Simulação

### Requisitos

- [GHDL](https://github.com/ghdl/ghdl/releases) ≥ 4.0 (testado com 5.1.1, backend mcode)
- PowerShell 5+ (Windows) ou `pwsh` (Linux / macOS)
- Opcional: [GTKWave](https://gtkwave.sourceforge.net/) para inspeção de formas de onda

### Início Rápido (Windows)

```powershell
# 1. Criar junção de caminho ASCII (GHDL não suporta caracteres não-ASCII em caminhos)
New-Item -ItemType Junction -Path C:\ghdl -Target "C:\Users\<usuario>\OneDrive\Área de Trabalho\Arquitetura de CPU"

# 2. Executar o teste de fumaça
cd C:\ghdl
.\sim\run_sim.ps1

# 3. Executar com saída VCD de forma de onda
.\sim\run_sim.ps1 -wave

# 4. Visualizar forma de onda
gtkwave sim\cpu_top_tb.vcd

# 5. Limpar objetos compilados e reexecutar
.\sim\run_sim.ps1 -clean
```

### Saída Esperada

```
[TB] ciclo=1    PC=0x00000000
[TB] ciclo=2    PC=0x00000000
...
[TB] ciclo=70   PC=0x00000058
[TB] =============================================
[TB] CPU alcançou endereço de HALT (0x5C).
[TB] Teste concluído em 72 ciclos.
[TB] =============================================
[TB] PASS
```

### ROM do Testbench

A ROM de 24 instruções exercita o núcleo de ponta a ponta:
`ADDI`, `ADD`, `SW`, `LW`, `BEQ` (tomado), `JAL`, `AUIPC`, `LUI`,
`SUB`, `SLT`, `SLTU`, `XOR`, `OR`, `AND`, `SLLI`, `SRLI`, `SRAI`,
caminhos de forwarding, stall de load-use e um `JAL x0, 0` terminal (HALT infinito).

O slave AXI de memória de dados reporta toda escrita:
```
[DMEM] WRITE addr=0x10000000 data=0x00000005 strb=F
```

---

## Limitações Conhecidas

| # | Limitação | Impacto |
|---|---|---|
| 1 | RV32C: instruções comprimidas em PCs não alinhados a 4 bytes não suportadas | Afeta código com mistura de 16/32 bits em fronteiras ímpares |
| 2 | Linhas sujas da D-cache não são descarregadas por hardware no `FENCE` | Software deve descarregar manualmente antes de operações de DMA / coerência de cache |
| 3 | Transação AXI pendente única (sem pipeline nos canais AXI) | Menor largura de banda de pico vs designs com múltiplas transações pendentes |
| 4 | `mtime` incrementa a cada ciclo de CPU (não é contador em tempo real) | `mtime` rastreia ciclos de CPU, não tempo de relógio de parede |
| 5 | Sem contadores de desempenho de hardware além de `cycle` e `instret` | CSRs `hpmcounter` não implementados |

---

## Roadmap

### Concluído ✅

- [x] RV32A — Instruções atômicas (LR/SC, 9 operações AMO)
- [x] RV32C — Instruções comprimidas de 16 bits (alinhadas a 4 bytes)
- [x] Níveis de privilégio modo S / modo U
- [x] medeleg / mideleg — delegação de trap
- [x] Instrução SRET
- [x] CLINT — mtime / mtimecmp / msip
- [x] PLIC — 31 fontes, contexto modo M
- [x] MMU Sv32 — PTW de 2 níveis + TLB de 16 entradas
- [x] Preditor de desvios saturante de 1 bit + BTB de 64 entradas
- [x] Pipeline de 5 estágios com forwarding completo e detecção de load-use

### Planejado 🔧

- [ ] RV32C — Suporte completo alinhado a 2 bytes (buffer de busca em meia-palavra)
- [ ] Suite de conformidade RISC-V (`riscv-tests` / `riscv-arch-test`)
- [ ] Upgrade de cache N-way associativo por conjunto
- [ ] PLIC contexto modo S (contexto 1)
- [ ] Contadores de desempenho de hardware (`hpmcounter3–31`)
- [ ] Verificação formal (SymbiYosys / RISC-V Formal)
- [ ] Interface de depuração JTAG (RISC-V External Debug Spec v0.13)
- [ ] Suporte a múltiplos harts (multi-core SMP)
- [ ] Execução superescalar / fora de ordem (longo prazo)

---

## Referências

- [Especificação ISA Não Privilegiada RISC-V v20191213](https://github.com/riscv/riscv-isa-manual)
- [Especificação de Arquitetura Privilegiada RISC-V v20211203](https://github.com/riscv/riscv-isa-manual)
- [Especificação SBI RISC-V](https://github.com/riscv-non-isa/riscv-sbi-doc)
- [Especificação PLIC RISC-V](https://github.com/riscv/riscv-plic-spec)
- [ARM IHI0022E — Especificação de Interface AXI4-Lite](https://developer.arm.com/documentation/ihi0022/e/)
- [Documentação GHDL](https://ghdl.github.io/ghdl/)
- [Memória Virtual Sv32 — Spec Privilegiada RISC-V §4.3](https://github.com/riscv/riscv-isa-manual)

---

## Licença

Licença MIT. Veja [LICENSE](LICENSE) para detalhes.

Desenvolvido por: **Escanearcpl** — www.escanearcplx.com
