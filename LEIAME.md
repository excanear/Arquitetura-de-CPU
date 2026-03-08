# O que é este projeto? (para quem não é da área)

Bem-vindo! Este repositório é um **laboratório completo de como um computador funciona por dentro** — desde a explicação mais simples até chips reais funcionando em hardware.

Não precisa saber programar para entender a ideia geral. Vamos devagar. 😊

---

## A ideia central: como um computador "pensa"?

Imagine uma **linha de montagem de fábrica**:

```
Estação 1         Estação 2          Estação 3          Estação 4         Estação 5
"Buscar a peça" → "Ler a ficha" → "Montar a peça" → "Testar a peça" → "Embalar e entregar"
```

Um processador (CPU) funciona **exatamente assim**. Cada instrução do programa passa por essas estações uma de cada vez, em fila. O truque inteligente é que, enquanto uma instrução está em "montar", a próxima já está em "ler a ficha", e outra está "buscando a peça" — tudo ao mesmo tempo.

Isso se chama **pipeline** ("cano" em inglês — a instrução flui pelo cano como água).

Este projeto constrói **três processadores diferentes** do zero, cada vez mais complexo e mais parecido com o de um computador real.

---

## Os três projetos

### 🟢 Projeto 1 — EduRISC-32v2 em Python (o simulador educacional)

**O que é:** Uma CPU completamente simulada em Python, feita para aprender como tudo funciona.

**Analogia:** É uma **linha de montagem num tablet**. Você não está mexendo em parafusos de verdade — está simulando o processo numa tela. Mas a lógica é idêntica à de um chip real.

**Detalhes:**
- Trabalha com **32 peças de memória** dentro da CPU (chamadas de registradores), cada uma guardando um número de até 32 bits
- Entende **57 instruções** diferentes (como "some", "compare", "pule para outro trecho do programa")
- Tem **memória cache** simulada — uma memória extra pequena e rápida que fica "na frente" da memória principal
- Tem **proteção de memória** (MMU) — cada programa fica no seu espaço, sem invadir o do outro

**O que vem junto:**

| Ferramenta | O que faz | Analogia |
|---|---|---|
| **Montador** (assembler) | Traduz texto legível (`ADD R1, R2, R3`) para números que a CPU entende | Um tradutor simultâneo |
| **Compilador** | Traduz código em linguagem C simplificada para as instruções do processador | Um escritor que reformata um texto |
| **Ligador** (linker) | Junta vários arquivos de código num único programa | Montar capítulos soltos num livro encadernado |
| **Carregador** (loader) | Converte o programa para formatos que chips de hardware conseguem usar | Converter um arquivo Word para PDF |
| **Simulador** | Executa o programa e mostra o resultado | Um ensaio geral antes da estreia |
| **Depurador** | Para a execução a qualquer momento para inspecionar o que está dentro da CPU | Uma câmera lenta com replay frame a frame |
| **Visualizador web** | Abre no navegador com 8 painéis mostrando TUDO em tempo real | Um painel de controle de trem com todas as gauges |

**Como rodar um exemplo:**
```bash
python main.py demo
```
A CPU vai calcular 1+2+3+4+5 = **15**, usando duas formas diferentes: código montador e código C simplificado.

**Como montar e rodar seu próprio programa:**
```bash
python main.py assemble meu_programa.asm -o meu_programa.hex --listing
python main.py simulate meu_programa.hex --trace
```

---

### 🔵 Projeto 2 — EduRISC-32v2 em Hardware (chip real em Verilog)

**O que é:** A mesma CPU do Projeto 1, mas agora escrita em **Verilog** — a linguagem que engenheiros usam para descrever circuitos físicos de verdade.

**Analogia:** No Projeto 1 você simulou a linha de montagem numa tela. Agora você está **construindo a linha de montagem de verdade** com máquinas físicas, correias transportadoras e operários reais.

**Por que isso importa:** Este código pode ser gravado em um chip **FPGA** — um tipo de chip que você compra numa loja eletrônica, conecta num computador por USB, e ele vira a sua CPU. É hardware de verdade funcionando.

**O que tem dentro:**

```
30 módulos de hardware, incluindo:

  Pipeline de 5 estágios   → as 5 estações da linha de montagem
  Cache L1 de instrução    → memória rápida para o código do programa (4 KB)
  Cache L1 de dados        → memória rápida para os dados do programa (4 KB)
  MMU + TLB                → sistema de proteção de memória (32 entradas)
  Controlador de interrupções → para o sistema reagir a eventos externos (timer, botões)
  OS rudimentar (kernel)   → escalonador, heap, syscalls — como um mini Linux!
  Bootloader               → código que inicializa tudo ao ligar o chip
  Contadores de desempenho → mede ciclos, instruções, erros de cache, etc.
```

**Como testar (com Icarus Verilog instalado):**
```bash
iverilog -g2012 -Irtl_v -o sim.out $(ls rtl_v/**/*.v rtl_v/*.v) verification/cpu_tb.v
vvp sim.out
# → "=== Results: 12/12 PASS ===" significa que todos os testes passaram ✅
```

**Como gravar em chip FPGA real (com Vivado instalado):**
```bash
python main.py fpga-build
# Gera o arquivo .bit para gravar na placa Arty A7
```
Após gravar, os LEDs da placa piscam enquanto a CPU está executando.

---

### 🔴 Projeto 3 — RV32IMAC em VHDL (CPU profissional)

**O que é:** Um processador no padrão **RISC-V** — o mesmo padrão usado em chips reais de celulares, roteadores e computadores embarcados no mundo todo.

**Analogia:** Os Projetos 1 e 2 eram carros de brinquedo e um carro escolar. Este é um **carro de Fórmula 1** — muito mais complexo, mais completo, mais parecido com o que roda um servidor ou um smartphone.

**Escrito em VHDL**, outra linguagem de hardware (diferente do Verilog, mas serve para o mesmo propósito).

**Por que importa:** É o tipo de CPU que poderia rodar Linux embarcado. Tem proteção de memória sofisticada, caches L1, suporte a múltiplos programas simultâneos, e uma interface de barramento padronizada (AXI4-Lite) usada pela indústria.

**28 módulos de hardware**, verificados com GHDL — todos os testes passam ✅.

---

## Como a CPU fica mais esperta: cache e proteção de memória

### O problema da memória lenta

Imagine que a CPU é um chef de cozinha. A memória principal (RAM) é a despensa no fundo do restaurante. Cada vez que o chef precisa de sal, ele precisa ir lá buscar — demora 50 passos. Isso atrasa demais.

A solução: uma **bancada** (cache) do lado do chef com os ingredientes mais usados. Ai fica a 2 passos. Se o sal estiver na bancada → **cache hit** (rápido!). Se não → **cache miss**, vai buscar na despensa e traz um pote maior de volta.

Neste projeto, cada CPU tem **duas** bancadas:
- **Cache de instrução (I$)**: guarda o *código* do programa que está rodando
- **Cache de dados (D$)**: guarda os *valores* (variáveis, resultados) que o programa usa

Cada bancada tem 4 KB e é organizada em 256 "gavetas" com 4 itens cada.

### O problema de vários programas ao mesmo tempo

Imagine que dois programas estão rodando. O Programa A usa o endereço de memória `1000`. O Programa B também usa o endereço `1000`. Como eles não se pisam?

A resposta é a **MMU** (Unidade de Gerenciamento de Memória). Ela funciona como uma **recepcionista** que traduz os endereços:

```
Programa A pede endereço 1000 → recepcionista olha no mapa → entrega o quarto 3847
Programa B pede endereço 1000 → recepcionista olha no mapa → entrega o quarto 9201
```

O **TLB** é o bloco de notas da recepcionista com as últimas 32 traduções (para não ter que recalcular toda vez).

Se um programa tenta acessar um endereço que não é seu → **Page Fault** (como tentar entrar num quarto com a chave errada) → o sistema operacional é avisado.

---

## Como funciona o mini sistema operacional

O Projeto 2 inclui um pequeno OS embarcado. Ele funciona assim:

**1. Boot (ligar):**
```
Chip liga → bootloader roda → inicializa memória → chama kernel_main
```

**2. Kernel:**
- Cria uma "tabela de processos" — uma lista de todos os programas que existem
- Cada processo tem suas próprias variáveis salvas: onde estava (PC), qual era sua pilha (SP), os valores dos registradores

**3. Escalonador:**
- A cada "tick" do timer (como um metrônomo), o SO pausa o programa atual, salva seu estado, e passa a vez para o próximo — **round-robin**, como uma fila circular
- Para o usuário parece que tudo roda ao mesmo tempo

**4. Syscalls:**
Quando um programa precisa de algo do SO (escrever na tela, alocar memória, dormir por um tempo), ele chama `SYSCALL`. É como apertar um botão de chamada para o gerente.

| Syscall | Para que serve |
|---|---|
| `SYS_WRITE` | Escrever texto na porta serial (UART) |
| `SYS_MALLOC` | Pedir um pedaço de memória |
| `SYS_FREE` | Devolver a memória que não precisa mais |
| `SYS_YIELD` | "Pode passar a vez, estou esperando" |
| `SYS_SLEEP` | Dormir por N ticks do timer |
| `SYS_EXIT` | Terminar o programa |

---

## Glossário completo — palavras que aparecem no código

| Palavra técnica | O que significa para um leigo |
|---|---|
| **CPU** | O "cérebro" do computador — executa as instruções |
| **Instrução** | Um comando simples, como "some estes dois números" |
| **Registrador** | Uma caixinha de memória dentro da CPU — rapidíssima, mas só guarda 1 número por vez. Esta CPU tem 32 |
| **Pipeline** | A linha de montagem — várias instruções em fases diferentes ao mesmo tempo |
| **Estágio (IF/ID/EX/MEM/WB)** | As 5 estações da linha de montagem: Buscar / Ler / Executar / Memória / Escrever |
| **Forwarding** | Um atalho na linha de montagem — passa o resultado direto para quem precisa sem esperar o "fim da fila" |
| **Hazard** | Um "conflito" na linha de montagem — uma instrução precisa de algo que a anterior ainda não terminou |
| **Stall** | A linha de montagem pausa um ciclo porque houve um conflito (hazard) |
| **Flush** | A linha de montagem descarta instruções que já entraram mas não deveriam (exemplo: depois de um desvio de rota inesperado) |
| **Clock** | O "metrônomo" do processador — cada tick é um ciclo |
| **MHz / GHz** | Quantos ticks por segundo (1 GHz = 1 bilhão/segundo). Esta CPU roda a 25 MHz no chip |
| **Cache** | Memória ultra-rápida dentro do chip — como a bancada do chef ao lado do fogão |
| **Cache hit** | O dado pedido estava na bancada — rápido! (1 ciclo) |
| **Cache miss** | O dado não estava — precisa ir buscar na despensa (±6 ciclos) |
| **MMU** | A "recepcionista" que traduz endereços de memória de cada programa — impede conflitos |
| **TLB** | O bloco de notas da recepcionista — guarda as últimas traduções para ir mais rápido |
| **Page fault** | Quando um programa tenta acessar um endereço que não é dele — o SO é chamado |
| **FPGA** | Um chip programável — você define o hardware gravando um arquivo nele |
| **Verilog / VHDL** | Linguagens para *descrever hardware* (não software!) — como uma planta arquitetônica para chips |
| **Compilador** | Programa que traduz código humano para código de máquina |
| **Montador (Assembler)** | Traduz linguagem de baixíssimo nível (quase código de máquina) para números binários |
| **Linker (Ligador)** | Junta vários arquivos de código num único programa executável |
| **Loader (Carregador)** | Coloca o programa na memória pronto para rodar |
| **Syscall** | Um "botão de chamada para o gerente" — quando um programa precisa que o SO faça algo por ele |
| **Bootloader** | O primeiro código que roda quando o chip liga — prepara tudo antes do sistema operacional |
| **Escalonador** | O "gerente de turno" do SO — decide qual programa usa a CPU agora |
| **RISC-V** | Um padrão aberto de instruções para CPUs — qualquer um pode usar sem pagar royalties |
| **IPC** | Instruções por ciclo — mede a eficiência da CPU (1.0 = perfeito) |
| **ISA** | "Conjunto de instruções" — o vocabulário que a CPU entende (esta fala 57 "palavras") |

---

## O que você precisa instalar

| Para quê | Ferramenta | Gratuito? | Onde baixar |
|---|---|---|---|
| Simulador Python (Projetos 1 e 2) | Python 3.11+ | ✅ Sim | python.org |
| Simular o chip Verilog | Icarus Verilog | ✅ Sim | bleyer.org/icarus |
| Ver as ondas do chip graficamente | GTKWave | ✅ Sim | gtkwave.sourceforge.net |
| Simular o chip VHDL (Projeto 3) | GHDL | ✅ Sim | ghdl.github.io |
| Gravar em chip FPGA real | Vivado (Xilinx) | ✅ Versão gratuita | xilinx.com/vivado |
| Placa FPGA (opcional, para gravar) | Arty A7-35T | 💰 ~US$130 | digilentinc.com |

---

## Primeiros passos (do mais fácil ao mais avançado)

### Passo 1 — Ver a CPU funcionando em 1 minuto
```bash
# Instale Python e abra o terminal na pasta do projeto
python main.py demo

# Resultado esperado:
# "Resultado em R2 = 15 (esperado: 15)" ✅
```

### Passo 2 — Abrir o visualizador animado
```
Abra o arquivo  web/index.html  no seu navegador (Chrome, Firefox, Edge)
```
Você verá 8 painéis com a CPU rodando em tempo real: os registradores piscando, o pipeline se movendo, a cache sendo preenchida, tudo animado.

### Passo 3 — Escrever seu primeiro programa em assembly
Crie um arquivo `meu_prog.asm`:
```asm
; Calcula 10 * 3 = 30
.org 0x000000
    MOVI  R1, 10       ; R1 = 10
    MOVI  R2, 3        ; R2 = 3
    MUL   R3, R1, R2   ; R3 = R1 * R2 = 30
    HLT                ; Para a CPU
```
Rode:
```bash
python main.py run meu_prog.asm
# → R3 = 30
```

### Passo 4 — Compilar código C parecido com programação de verdade
Crie `fatorial.c`:
```c
int fatorial(int n) {
    int resultado = 1;
    while (n) {
        resultado = resultado * n;
        n = n - 1;
    }
    return resultado;
}

int main() {
    int x = fatorial(5);
    return x;
}
```
Rode:
```bash
python main.py build fatorial.c -o fatorial.hex
python main.py simulate fatorial.hex
# → R1 = 120 (5! = 120)
```

---

## Por que isso foi construído?

Muita gente aprende programação, mas pouquíssimas pessoas entendem o que acontece **dentro do processador** quando seu programa roda. Entre o `x = 2 + 3` que você escreve e os transistores que mudam de estado existem centenas de camadas de complexidade.

Este projeto foi criado para **abrir todas essas camadas**, uma de cada vez:

```
Python (simular)  →  Verilog/VHDL (construir)  →  FPGA (executar de verdade)
  "entender"              "descrever"                    "ver na prática"
```

A progressão é proposital:

1. **EduRISC-32v2 Python** — você entende a lógica sem preocupar com hardware
2. **EduRISC-32v2 RTL** — você vê como isso vira circuito
3. **RV32IMAC VHDL** — você vê como a indústria faz de verdade

---

## Quer aprender mais?

Se a curiosidade bateu, estes são ótimos pontos de partida:

| Recurso | Por que é bom | Onde encontrar |
|---|---|---|
| **Nand2Tetris** | Constrói um computador do zero, do zero mesmo, passo a passo, de forma interativa | nand2tetris.org |
| **Ben Eater no YouTube** | Monta um computador com fios e chips na bancada, explicando tudo visualmente em vídeo | youtube.com/@BenEater |
| **Computer Organization and Design** (Patterson & Hennessy) | O livro clássico da área de arquitetura de computadores, usado em universidades do mundo todo | biblioteca ou Amazon |
| **RISC-V International** | Documentação oficial do padrão RISC-V, gratuita e aberta | riscv.org |
| **Curso "Build a Modern Computer"** (Coursera/edX) | Baseado no Nand2Tetris, com vídeos e projetos práticos, gratuito para auditar | coursera.org |

---

## Resumo visual do projeto inteiro

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       O QUE ESTE PROJETO FAZ                                  │
├─────────────────────┬────────────────────────┬──────────────────────────────┤
│  🟢 EduRISC-32v2    │  🔵 EduRISC-32v2 RTL  │  🔴 RV32IMAC VHDL           │
│     (Python)        │     (Verilog)           │     (VHDL)                   │
├─────────────────────┼────────────────────────┼──────────────────────────────┤
│  Simulação          │  Hardware real          │  CPU profissional            │
│  32 registradores   │  30 módulos de circuito │  Padrão RISC-V               │
│  57 instruções      │  Cache L1 I$/D$ (4KB)   │  28 módulos de circuito      │
│  Pipeline 5 etapas  │  MMU + TLB 32 entradas  │  Caches + MMU Sv32           │
│  Cache simulada     │  OS: kernel+scheduler   │  Suporte a Linux embarcado   │
│  Web visualizer     │  FPGA Arty A7-35T       │  Testado com GHDL ✅         │
│  Assembler + C      │  12 testes automáticos  │  28 units, todos passaram ✅ │
│  Linker + Loader    │  Vivado ready           │                              │
├─────────────────────┴────────────────────────┴──────────────────────────────┤
│                  python main.py <comando>  ←  ponto de entrada único          │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

*Este laboratório foi desenvolvido como projeto acadêmico de Arquitetura de Computadores.*
*Todos os simuladores e ferramentas são de código aberto e gratuitos para uso educacional.*
