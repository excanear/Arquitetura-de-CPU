# Interface OS/Hardware EduRISC-32v2

## Visão Geral

O EduRISC-32v2 expõe uma interface OS/hardware clara composta de:
1. **Syscalls** — trap para o kernel via instrução SYSCALL
2. **Exceções** — tratadas pelo `exception_handler.v`
3. **Interrupções** — gerenciadas pelo `interrupt_controller.v`
4. **CSRs** — estado privilegiado acessível via MFC/MTC
5. **ABI** — convenção de registradores/chamada

---

## Tabela de Syscalls

A instrução SYSCALL gera exceção com CAUSE=3. O kernel lê o número de syscall de **R1** e os argumentos de **R2–R5**.

| Num (R1) | Nome | Argumentos | Retorno (R1) |
|---|---|---|---|
| 0 | SYS_EXIT | R2=código de saída | — |
| 1 | SYS_WRITE | R2=fd, R3=buf_addr, R4=len | bytes escritos |
| 2 | SYS_READ | R2=fd, R3=buf_addr, R4=len | bytes lidos |
| 3 | SYS_MALLOC | R2=size (words) | ponteiro ou 0 |
| 4 | SYS_FREE | R2=ponteiro | — |
| 5 | SYS_YIELD | — | — |
| 6 | SYS_SLEEP | R2=ticks | — |
| 7 | SYS_GETPID | — | pid atual |
| 8 | SYS_FORK | — | pid filho ou 0 |
| 9 | SYS_UPTIME | — | ticks desde boot |

**Descrição dos descritores de arquivo:**
- fd=0: stdin (UART RX)
- fd=1: stdout (UART TX)
- fd=2: stderr (UART TX, prefixado com "ERR: ")

---

## Fluxo de Syscall

```
  espaço usuário:
    MOVI  R1, SYS_WRITE   ; número da syscall
    MOVI  R2, 1           ; fd=stdout
    ADDI  R3, R0, buf     ; endereço do buffer
    MOVI  R4, 13          ; tamanho
    SYSCALL               ; trap!

  hardware (exception_handler.v):
    EPC   ← PC da instrução SYSCALL
    CAUSE ← 3 (SYSCALL)
    IE    ← 0
    PC    ← IVT_BASE + 3

  kernel (os/syscalls.c):
    syscall_handler(R1, R2, R3, R4, R5)
    R1 ← resultado
    ERET    ; retorna ao usuário, IE←1
```

---

## Convenção de Chamada ABI

### Registradores

```
R0        zero         sempre 0 (somente leitura)
R1        a0/retval    primeiro argumento / valor de retorno
R2–R6     a1–a5        argumentos (caller-saved)
R7–R12    t0–t5        temporários (caller-saved)
R13–R25   s0–s12       salvos (callee-saved)
R26–R29   t6–t9        temporários extras (caller-saved)
R30       sp           stack pointer
R31       lr           link register (endereço de retorno)
```

### Prólogo/Epílogo de Função

```asm
; Prólogo (função que chama outras funções):
PUSH  R31          ; salva LR
ADDI  R30, R30, -N ; aloca N words na pilha
SW    R13, 0(R30)  ; salva callee-saved usados…

; Epílogo:
LW    R13, 0(R30)  ; restaura callee-saved
ADDI  R30, R30, N  ; desaloca pilha
POP   R31          ; restaura LR
RET                ; PC ← R31
```

### Passagem de Argumentos

- Até 5 argumentos em R1–R5 (inteiros ou ponteiros)
- Argumentos extras: na pilha (R30+0, R30+1, …) antes do CALL
- Struct por valor: copiada na pilha; ponteiro passado via registrador
- Retorno de 64 bits: R1 (bits baixos) + R2 (bits altos)

---

## Estados de Processo

```
  ┌──────┐  proc_create  ┌───────┐  schedule    ┌─────────┐
  │ FREE │──────────────▶│ READY │─────────────▶│ RUNNING │
  └──────┘               └───────┘              └─────────┘
     ▲                                               │
     │  sys_exit                   sys_yield │       │
     └───────────────────◄────────────────────       │
                                                      │  sys_sleep / I/O wait
                                               ┌──────────┐
                                               │ BLOCKED  │◄──────────────┐
                                               └──────────┘               │
                                                    │  evento completado   │
                                                    └──────────────────────┘
```

**Campos da entrada da tabela de processos (at DMEM[0x1000]):**
```c
typedef struct {
    int pid;       // ID do processo (offset 0)
    int state;     // 0=FREE 1=READY 2=RUNNING 3=BLOCKED
    int pc;        // PC salvo
    int sp;        // SP salvo
    int regs[13];  // R1–R13 salvos (callee-saved + args)
} ProcessEntry;    // Tamanho = 16 words
```

---

## Tratamento de Interrupções

### Interrupt Controller (`rtl_v/interrupts/interrupt_controller.v`)

| Bit IM | Fonte | Código CAUSE |
|---|---|---|
| 0 | Timer (TIMER_CNT >= TIMER_CMP) | 0 + IRQ=1 |
| 1–7 | Externas EXT[0–6] | 1–7 + IRQ=1 |

**Prioridade:** Timer > EXT0 > EXT1 > … > EXT6

**Mascaramento:** STATUS[7:4] = IM[3:0]. Uma interrupção é aceita quando `STATUS.IE=1` e o bit IM correspondente = 0 (não mascarado).

### Fluxo de Interrupção

```
  Timer dispara → irq_pending[0] = 1

  Se STATUS.IE=1 && ~STATUS.IM[0]:
    interrupt_controller → irq_req
    exception_handler:
      EPC   ← PC+1 (instrução SEGUINTE, para retomar)
      CAUSE ← {1'b1, cause_code}
      IE    ← 0
      PC    ← IVT_BASE + cause_code

  ISR (isr_timer no bootloader.asm):
    MFC  R1, ESCRATCH       ; salva R1
    LW   R1, TICK_COUNTER   ; incrementa tick
    ADDI R1, R1, 1
    SW   R1, TICK_COUNTER
    MTC  ESCRATCH, R1
    MFC  R1, ESCRATCH       ; restaura R1
    ERET                    ; retorna, IE←1
```

---

## CSRs de Controle de Sistema

### STATUS (CSR[0])

```
Bit 0: IE  — Interrupt Enable (0=disabled, 1=enabled)
Bit 1: KU  — Kernel/User mode (0=kernel, 1=user)
Bit 4: IM0 — Interrupção 0 (timer) mascarada se 1
Bit 5: IM1 — Interrupção 1 mascarada se 1
Bit 6: IM2
Bit 7: IM3
```

### Escrita típica para ativar timer IRQ:
```asm
MOVI  R1, 0x01          ; IE=1, IM=0000 (nenhuma mascarada)
MTC   R1, STATUS        ; CSR[0] ← R1
MOVI  R2, 10000
SW    R2, TIMER_CMP(R0) ; define período
```

---

## Interface de Debug (Hardware)

### Sinal `debug_halted`
- Quando HLT é executado: `halted=1`
- Os 4 LEDs na FPGA mostram `debug_reg[3:0]` (bits baixos de R1)

### Porta UART
- TX: escrever byte em MMIO[0xFF00]
- RX: ler byte de MMIO[0xFF04]; verificar UART_STATUS[1] antes
- Velocidade: configurável via parâmetro `UART_BAUD` em `fpga/top.v`

---

## Exemplo Completo: Hello World

```asm
; Arquivo: hello.asm
; Objetivo: imprimir "Hello!\n" pela UART

    .org 0x000100      ; após bootloader/IVT

msg:
    .word 0x48656C6C   ; "Hell"
    .word 0x6F210A00   ; "o!\n\0"

_start:
    MOVI  R30, 0x0FFF0 ; SP inicial
    ADDI  R1, R0, 1    ; fd=stdout
    ADDI  R3, R0, msg  ; endereço do buffer
    MOVI  R2, 1
    MOVI  R4, 7        ; 7 bytes: "Hello!\n"
    MOVI  R1, 1        ; SYS_WRITE
    SYSCALL
    MOVI  R1, 0        ; SYS_EXIT
    SYSCALL
```
