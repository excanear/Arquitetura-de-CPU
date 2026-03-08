# O que é este projeto? (para quem não é da área)

Bem-vindo! Este repositório é um **laboratório completo de como um computador funciona por dentro** — desde a explicação mais simples até chips reais funcionando em hardware.

Não precisa saber programar para entender a ideia. Vamos com calma. 😊

---

## A ideia central: como um computador "pensa"?

Imagine uma **linha de montagem de fábrica**:

```
Esteira 1       Esteira 2        Esteira 3        Esteira 4        Esteira 5
"Buscar peça" → "Ler a ficha" → "Montar a peça" → "Embalar" → "Entregar ao cliente"
```

Um processador (CPU) funciona **exatamente assim**. Cada instrução do programa passa por esses estágios um de cada vez, em fila. Enquanto uma instrução está sendo "montada", a próxima já está sendo "lida", e outra está "buscando a peça" — tudo ao mesmo tempo. Isso se chama **pipeline**.

Esse projeto constrói **três processadores diferentes** do zero, cada um ensinando algo novo.

---

## Os três projetos

### 🟢 Projeto 1 — EduRISC-16 (o mais simples, em Python)

**O que é:** Uma CPU completamente simulada em Python, feita para aprender.

**Analogia:** É como uma calculadora muito poderosa que entende 16 comandos diferentes. Você escreve uma lista de instruções (tipo uma receita de bolo), e ela executa passo a passo.

**O que tem dentro:**
- Um **montador** — traduz texto legível (como `ADD R1, R2`) para os números que a CPU entende
- Um **compilador** — traduz código parecido com C (linguagem de programação) para as tais instruções
- Um **simulador** — executa tudo e mostra o resultado
- Um **depurador** — deixa você ver o que acontece dentro da CPU a cada passo
- Um **visualizador web** — abre no navegador e mostra a linha de montagem em tempo real

**Como rodar:**
```bash
python main.py demo
```
Você verá a CPU calcular a soma de 1+2+3+4+5 = **15**, tanto usando código montador quanto usando código C simplificado.

---

### 🔵 Projeto 2 — EduRISC-32 (CPU real em hardware)

**O que é:** A mesma ideia do Projeto 1, mas agora escrita em **Verilog** — a linguagem que engenheiros usam para descrever transistores e chips reais.

**Analogia:** No Projeto 1, você simulou a linha de montagem numa planilha do computador. Agora você está **construindo a linha de montagem de verdade**, com máquinas reais, em uma fábrica.

**Por que importa:** Esse código pode ser gravado em um chip **FPGA** (um chip programável que você compra numa loja) e executar de verdade em hardware físico.

**O que tem dentro:**
- 15 módulos de hardware (cada um descreve uma parte do chip)
- Testes automáticos que verificam se o chip funciona corretamente
- Configurações para gravar em uma placa FPGA real

**Como testar (com Verilog instalado):**
```bash
iverilog -g2012 -I rtl_v -o sim.out testbench/cpu_tb.v rtl_v/*.v
vvp sim.out
```
Se aparecer **"TODOS OS TESTES PASSARAM"**, a CPU está funcionando. 🎉

---

### 🔴 Projeto 3 — RV32IMAC (CPU profissional em VHDL)

**O que é:** Um processador no padrão **RISC-V** — o mesmo padrão usado em chips reais de celulares, roteadores e computadores embarcados no mundo todo.

**Analogia:** Os projetos 1 e 2 eram carros de brinquedo. Este é um **carro de corrida de verdade** — muito mais complexo, mas também muito mais poderoso.

**Por que importa:** É o tipo de CPU que poderia rodar Linux. Tem proteção de memória, caches de velocidade, suporte a múltiplos programas rodando ao mesmo tempo, e muitas outras funcionalidades avançadas que um computador moderno precisa.

**O que tem dentro:**
- 28 arquivos de hardware descrevendo cada peça do chip
- Suporte a instruções de multiplicação, divisão, operações atômicas (usadas para evitar conflitos entre programas)
- Uma unidade de gerenciamento de memória (MMU) — que é o que permite vários programas rodarem sem se atrapalharem
- Caches L1 — memórias ultra-rápidas que ficam dentro do chip para não precisar ir buscar dados na memória principal toda hora

---

## Glossário: palavras que aparecem no código

| Palavra técnica | O que significa em português simples |
|---|---|
| CPU | O "cérebro" do computador — executa as instruções |
| Instrução | Um comando simples, como "some estes dois números" |
| Registrador | Uma caixinha de memória dentro da CPU (rapidíssima, mas só guarda 1 valor) |
| Pipeline | A linha de montagem — várias instruções em fases diferentes ao mesmo tempo |
| Clock | O "metrônomo" do processador — determina o ritmo de execução |
| MHz / GHz | Quantos ciclos de clock por segundo (1 GHz = 1 bilhão de operações/segundo) |
| FPGA | Um chip programável — você define o hardware gravando um arquivo nele |
| Verilog / VHDL | Linguagens para descrever hardware (não software!) |
| Compilador | Programa que traduz código humano para código de máquina |
| Assembly / Montador | Linguagem de baixíssimo nível, quase o código que a CPU entende diretamente |
| Cache | Memória muito rápida dentro do chip que guarda as coisas usadas com frequência |
| Forwarding | Atalho que evita que a CPU fique parada esperando um resultado ficar pronto |
| Hazard | Um "conflito" na linha de montagem — uma instrução precisa de algo que a anterior ainda não terminou |
| RISC-V | Um padrão aberto de instruções para CPUs — qualquer um pode usar sem pagar royalties |

---

## O que você precisa para rodar

| Para o quê | Ferramenta | É gratuito? |
|---|---|---|
| Projetos 1 e 2 (Python) | Python 3.11 ou mais novo | ✅ Sim |
| Simular o chip Verilog (Projeto 2) | Icarus Verilog | ✅ Sim |
| Ver as ondas do chip graficamente | GTKWave | ✅ Sim |
| Simular o chip VHDL (Projeto 3) | GHDL | ✅ Sim |
| Gravar em chip FPGA real | Vivado (Xilinx) | ✅ Versão gratuita disponível |

---

## Por que isso foi construído?

Muita gente aprende programação, mas pouquíssimas pessoas entendem o que acontece **dentro do processador** quando seu programa roda. Este projeto foi criado para preencher essa lacuna — explicar, passo a passo, como uma CPU é construída do zero.

Os três projetos formam uma progressão natural:

```
Python (simulação)  →  Verilog (hardware simples)  →  VHDL (hardware profissional)
     "entender"              "construir"                   "dominar"
```

---

## Quer aprender mais?

Se a curiosidade bateu, estes são bons pontos de partida:

- **Nand2Tetris** (nand2tetris.org) — constrói um computador completo do zero, de forma interativa, sem precisar de conhecimento prévio
- **Computer Organization and Design** (Patterson & Hennessy) — o livro clássico da área, usado em universidades do mundo todo
- **RISC-V International** (riscv.org) — documentação oficial do padrão RISC-V, gratuita e aberta
- **YouTube: Ben Eater** — canal que constrói um computador com fios e chips na bancada, explicando tudo visualmente

---

*Este laboratório foi desenvolvido como projeto acadêmico de Arquitetura de Computadores.*
