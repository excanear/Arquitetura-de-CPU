# Design do Sistema de Cache EduRISC-32v2

## Visão Geral

O EduRISC-32v2 possui dois caches L1 independentes de **4 KB** cada:

| Parâmetro | I-Cache | D-Cache |
|---|---|---|
| Capacidade | 4 KB | 4 KB |
| Organização | Direct-mapped | Direct-mapped |
| Sets | 256 | 256 |
| Words/linha | 4 (128 bits) | 4 (128 bits) |
| Write policy | — (somente leitura) | Write-back + Write-allocate |
| Arquivo RTL | `rtl_v/cache/icache.v` | `rtl_v/cache/dcache.v` |

---

## Organização de Endereços

Para um endereço físico de 26 bits (word granularity):

```
  Endereço físico (26 bits):
  ┌──────────────────────┬────────────────┬──────────┐
  │      tag[25:10]      │  index[9:2]    │ word[1:0]│
  │       (16 bits)      │   (8 bits)     │ (2 bits) │
  └──────────────────────┴────────────────┴──────────┘
       ↓                       ↓               ↓
  256 possíveis tags      256 sets       4 words/linha
  armazenados no array    de cache       seleção dentro
  de tags                               da linha
```

**Cálculo:**
- 256 sets × 4 words × 4 bytes = 4.096 bytes = **4 KB**
- Tamanho de linha = 16 bytes (128 bits)
- Offset de byte dentro de word: bits [1:0] são ignorados (acesso word-aligned)

---

## I-Cache (`icache.v`)

### Organização Interna

```verilog
reg [31:0]  data  [0:255][0:3];  // 256 linhas × 4 words
reg [15:0]  tag   [0:255];       // 256 tags de 16 bits
reg         valid [0:255];       // bits de validade
```

### FSM

```
           miss
  ┌────────────┐       FILL (4 ciclos)
  │    IDLE    │──────────────────────────────┐
  └────────────┘                              │
        │  hit                                ▼
        │                             ┌──────────────┐
        │  ◄──────── UPDATE ──────────│    FILL      │
        │            (1 ciclo)        │  (busca da   │
        └────────────────────────────▶│  memória)    │
                                      └──────────────┘
```

| Estado | Descrição |
|---|---|
| IDLE | Verifica valid[index] && tag[index]==addr_tag |
| FILL | Emite 4 leituras consecutivas à memória (word 0..3) |
| UPDATE | Escreve linha no array, seta valid e tag |

**Stall:** `icache_stall = 1` durante FILL+UPDATE.

---

## D-Cache (`dcache.v`)

### Organização Interna

```verilog
reg [31:0]  data  [0:255][0:3];
reg [15:0]  tag   [0:255];
reg         valid [0:255];
reg         dirty [0:255];    // sinaliza linha modificada
```

### FSM

```
           miss, dirty=0            miss, dirty=1
  ┌────────────┐ ──────────────►  ┌───────────────┐
  │    IDLE    │                  │     EVICT     │──► mem_write (4 words)
  └────────────┘                  └───────────────┘
        │  hit read/write                │
        │                               ▼
        │                        ┌──────────────┐
        │  ◄── UPDATE ◄──────────│     FILL     │
        │     (1 ciclo)          │  (4 leituras)│
        └────────────────────────└──────────────┘
```

| Estado | Descrição |
|---|---|
| IDLE | Testa hit; aceita leituras e escritas |
| EVICT | Envia os 4 words da linha dirty p/ memória (write-back) |
| FILL | Lê os 4 words da nova linha da memória |
| UPDATE | Atualiza arrays de tag/data/valid/dirty; dirty=0 em leitura |

### Política de Escrita

- **Write-hit:** Escreve no array de dados local; marca `dirty[index] = 1`
- **Write-miss (Write-allocate):** Se o bloco atual é dirty → EVICT; depois FILL com a linha nova, depois aplica a escrita

---

## Cache Controller (`cache_controller.v`)

O `cache_controller` arbitra o barramento de memória físico entre I-cache e D-cache:

```
  I-Cache ──►──┐
               │  Cache Controller ──► Memória Física
  D-Cache ──►──┘    (árbitro)
```

**Prioridade:** D-cache tem prioridade sobre I-cache durante evicção ou fill simultâneos.

**Interface com cpu_top:**
```
  icache_stall    → congela IF
  dcache_stall    → congela MEM
  mem_addr[25:0]  → endereço selecionado
  mem_rdata[31:0] → dado lido
  mem_wdata[31:0] → dado a escrever
  mem_we          → sinal de escrita
```

---

## Métricas de Performance

Os contadores CSR rastreiam:
- **ICMISS** (CSR[12]): cada vez que I-cache entra em FILL
- **DCMISS** (CSR[11]): cada vez que D-cache entra em FILL

**Taxa de hit esperada** (código localizado):
- I-cache: >98% após warm-up
- D-cache: >90% em acessos sequenciais

---

## Exemplo de Trace

```
Ciclo 10: LOAD @ PA=0x001450
  index = 0x145 >> 2 = 0x51 = 81
  tag   = 0x1450 >> 10 = 0x05
  valid[81]=0 → MISS → dcache_stall asserted

Ciclos 11-14: FILL — lê MEM[0x1450..0x1453]
Ciclo 15: UPDATE — data[81][0..3] = {…}, tag[81]=0x05, valid=1, dirty=0

Ciclo 16: LOAD @ PA=0x001451 (mesmo bloco)
  index=81, tag=0x05, valid=1 → HIT → dado disponível em 1 ciclo
```

---

## Checklist de Coerência

| Situação | Comportamento |
|---|---|
| I/D cache acessam mesmo endereço | I-cache é read-only; D-cache write invalida linha de I-cache (via `cache_flush`) |
| Troca de processo (ERET) | FENCE instrui o controller a completar writes pendentes |
| TLB flush (TLBCTL write) | Não invalida caches (PA já resolvido) |
