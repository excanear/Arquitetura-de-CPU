# Sistema de Memória EduRISC-32v2

## Mapa de Memória Física

```
Endereço Word [25:0]     Região               Tamanho
──────────────────────────────────────────────────────────
0x000000 – 0x03FFFF      IMEM (instrução)      256 K words = 1 MB
0x040000 – 0x07FFFF      DMEM (dados)          256 K words = 1 MB
0x080000 – 0x0FFFFD      Expansão futura       512 K words
0x0FFFFE                 UART_TX (MMIO)
0x0FFFFF                 UART_RX (MMIO)
0x100000+                (não mapeado)
```

> **Nota:** O PC tem 26 bits → espaço máximo de 64 M words (256 MB), mas a instância de simulação usa IMEM/DMEM de 1 MB cada por padrão.

---

## Mapa de DMEM (Espaço de Dados)

```
Offset (words)    Região
────────────────────────────────────────────────────────
0x00000 – 0x003FF  OS data / globais / BSS
0x00400 – 0x007FF  Stack do kernel (SP inicial = 0x0FFFF0)
0x00800 – 0x00FFF  BSS de usuário (zerado pelo bootloader)
0x01000 – 0x01FFF  Tabela de processos (8 entradas × 16 words)
0x02000 – 0x0EFFF  Heap (kmalloc/kfree)
0x0F000 – 0x0FEFF  MMIO interno (periféricos)
0x0FF00            UART_TX (write-only)
0x0FF04            UART_RX (read-only)
0x0FF10            TIMER_CMP (comparador de timer)
0x0FF20            TIMER_CNT (contador de timer, read-only)
0x0FFE0            DEBUG (escrita para stop-at simulation)
0x0FFF0            TICK_COUNTER (incrementado pelo ISR de timer)
```

---

## Memória Virtual e Paginação

### Espaço de Endereços Virtual

- Largura: 32 bits (4 GB virtual)
- Tamanho de página: 4 KB (12 bits de offset)
- VPN (Virtual Page Number): bits [31:12] = 20 bits

### TLB — Translation Lookaside Buffer

| Parâmetro | Valor |
|---|---|
| Entradas | 32 |
| Associatividade | Totalmente associativo |
| Substituição | FIFO |
| Arquivo RTL | `rtl_v/mmu/tlb.v` |

**Estrutura de uma entrada TLB:**

```
┌──────────────────────────────────────────────────────────┐
│ valid │   VPN[31:12]   │   PFN[31:12]   │ D │ A │ U │ X │ W │ R │
└──────────────────────────────────────────────────────────┘
  1 bit     20 bits          20 bits       1   1   1   1   1   1
```

**Flags:**
| Bit | Nome | Significado |
|---|---|---|
| R | Read | Página leitura permitida |
| W | Write | Página escrita permitida |
| X | Execute | Página execução permitida |
| U | User | Acessível em modo usuário |
| A | Accessed | Hardware seta em acesso |
| D | Dirty | Hardware seta em escrita |

### Page Table Walker (PTW)

O EduRISC-32v2 usa tabelas de página de **2 níveis** (estilo RISC-V Sv32):

```
Tradução de endereço virtual VA[31:0]:

VA[31:22] = índice L1 (10 bits) → offset em L1PT (4-byte entries)
VA[21:12] = índice L2 (10 bits) → offset em L2PT (4-byte entries)
VA[11:0]  = offset de página (12 bits)

L1PT base = PTBR << 12   (CSR[5])

L1 PTE addr = (PTBR << 12) + VA[31:22]*4
L2PT base   = L1PTE[31:12] << 12
L2 PTE addr = L2PT_base    + VA[21:12]*4
PA          = L2PTE[31:12] || VA[11:0]
```

**Formato de PTE (Page Table Entry):**

```
┌────────────────────────┬───┬───┬───┬───┬───┬───┬───┬───┐
│      PFN [31:12]       │ _ │ _ │ D │ A │ U │ X │ W │ R │ V │
└────────────────────────┴───┴───┴───┴───┴───┴───┴───┴───┘
         20 bits                                           1 (valid)
```

### Fluxo de Tradução no MMU

```
VA chega ao MMU
      │
      ▼
  Busca na TLB (fully associative lookup)
      │
  HIT ──────────────────────────────►  PA = PFN || offset
      │
  MISS
      │
      ▼
  PTW: 2 leituras de memória (L1 PTE + L2 PTE)
      │
  Falha de PTE (V=0 ou permissão) ──► page_fault signal
      │
  Sucesso
      │
      ▼
  Instala nova entrada na TLB (policy FIFO)
      │
      ▼
  PA = PFN || VA[11:0]
```

---

## MMIO (Memory-Mapped I/O)

| Endereço | Registrador | Acesso |
|---|---|---|
| 0x0FF00 | UART_TX | Escrita: envia byte |
| 0x0FF04 | UART_RX | Leitura: recebe byte |
| 0x0FF08 | UART_STATUS | [0]=TX_READY, [1]=RX_VALID |
| 0x0FF10 | TIMER_CMP | Escrita: define intervalo do timer |
| 0x0FF14 | TIMER_CNT | Leitura: contador atual |
| 0x0FF20 | IRQ_MASK | Escrita: máscara de interrupções |
| 0x0FF24 | IRQ_PEND | Leitura: interrupções pendentes |
| 0x0FFE0 | SIM_DEBUG | Escrita de 0xDEAD = parar simulação |

---

## Interface de Barramento (AXI4-Lite Simplificado)

O `memory_interface.v` traduz os sinais internos do pipeline para o barramento de memória:

```
  cpu_top
    │  mem_addr[25:0]
    │  mem_wdata[31:0]
    │  mem_we
    │  mem_re
    │  mem_byte_en[3:0]
    ▼
  memory_interface.v
    │
    ▼  PA (após MMU)
  cache_controller.v
    │  ├─► icache.v
    │  └─► dcache.v
    ▼
  Memória física (IMEM/DMEM array)
```

---

## Page Faults e Tratamento

Quando o PTW detecta violação de permissão ou PTE inválido:

1. `page_fault` é assertado com `fault_type` (LOAD_PF=6, STORE_PF=7, IFETCH_PF=5)
2. `exception_handler.v` captura: `EPC ← faulting PC`, `CAUSE ← fault_type`
3. Pipeline é flushed; PC ← `IVT_BASE + fault_type`
4. ISR executa, possivelmente carrega PTE faltante, e faz `ERET`

---

## Desempenho do Sistema de Memória

| Operação | Latência (ciclos) |
|---|---|
| I-cache hit | 1 |
| I-cache miss (fill de 4 words) | ~6 |
| D-cache read hit | 1 |
| D-cache write hit | 1 |
| D-cache read miss (fill) | ~6 |
| D-cache write miss + dirty eviction | ~10 |
| TLB hit | 0 (paralelo ao cache lookup) |
| TLB miss + PTW (2 níveis) | ~4 (2 acessos L1+L2 à mem) |
