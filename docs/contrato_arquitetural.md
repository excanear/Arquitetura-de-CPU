# Contrato Arquitetural Oficial — EduRISC-32v2

## Objetivo

Este documento define a fonte única de verdade da plataforma principal do repositório.

Ele existe para reduzir deriva entre:

- implementação Python;
- software de sistema em C;
- RTL principal em Verilog;
- documentação histórica e paralela.

Quando houver conflito entre documentos antigos e este contrato, a prioridade de interpretação deve ser:

1. código implementado nas fontes autoritativas listadas abaixo;
2. este contrato arquitetural;
3. documentação complementar;
4. material explicitamente marcado como legado.

## Fontes Autoritativas

### ISA e codificação

- [cpu/instruction_set.py](cpu/instruction_set.py)
- [assembler/assembler.py](assembler/assembler.py)
- [simulator/cpu_simulator.py](simulator/cpu_simulator.py)

### ABI, syscalls e mapa de memória do OS

- [os/os_defs.h](os/os_defs.h)
- [os/syscalls.c](os/syscalls.c)
- [os/kernel.c](os/kernel.c)

### Hypervisor e virtualização

- [hypervisor/hypervisor.h](hypervisor/hypervisor.h)
- [hypervisor/hv_core.c](hypervisor/hv_core.c)
- [hypervisor/trap_handler.c](hypervisor/trap_handler.c)

### Hardware principal

- [rtl_v/cpu_top.v](rtl_v/cpu_top.v)
- [rtl_v/control_unit.v](rtl_v/control_unit.v)
- [rtl_v/interrupts/exception_handler.v](rtl_v/interrupts/exception_handler.v)

## Escopo Oficial da Plataforma

A plataforma principal suportada do repositório é:

- EduRISC-32v2 como ISA oficial;
- toolchain e simulador Python como baseline funcional;
- RTL Verilog em [rtl_v](rtl_v) como implementação principal de hardware;
- OS e hypervisor como software de sistema da plataforma EduRISC-32v2.

Linhas fora do escopo principal:

- EduRISC-16: legado educacional e histórico;
- RV32IMAC em VHDL: trilha paralela com contrato próprio.

## Contrato da ISA

### Parâmetros centrais

- largura da instrução: 32 bits;
- largura de registrador: 32 bits;
- quantidade de registradores de propósito geral: 32;
- contador de programa: 26 bits;
- espaço de endereçamento do PC: 64 M words = 256 MB;
- registradores especiais: R0 = zero, R30 = SP, R31 = LR.

### Formatos suportados

- R: registrador-registrador;
- I: imediato de 16 bits;
- S: store com deslocamento de 16 bits;
- B: branch PC-relative com deslocamento de 16 bits;
- J: salto absoluto de 26 bits;
- U: upper-immediate de 21 bits.

### Instruções de sistema relevantes para o contrato

- SYSCALL: entrada no software de sistema;
- ERET: retorno de exceção/trap;
- MFC: leitura de CSR;
- MTC: escrita de CSR;
- BREAK: parada/debug/hypercall auxiliar;
- FENCE: barreira de memória/ordenação.

## Contrato de Registradores e ABI

### Convenção geral

- R0: zero hardwired;
- R1: primeiro argumento lógico e valor de retorno quando indicado pelo subsistema;
- R2-R5: argumentos adicionais mais usados pelo software de sistema;
- R30: stack pointer;
- R31: link register.

### Contrato mínimo estável

Este repositório deve preservar, como contrato mínimo entre toolchain, simulador e software de sistema:

- R0 nunca é escrito;
- CALL/CALLR usam R31 como link register;
- PUSH/POP operam sobre R30;
- retorno de função simples usa R1;
- syscalls usam a convenção descrita na próxima seção.

## Contrato de Syscalls do OS

### ABI oficial de syscall

Fonte: [os/syscalls.c](os/syscalls.c).

- entrada por instrução SYSCALL;
- número da syscall em R1;
- argumentos em R2-R5;
- retorno em R1.

Assinatura lógica do handler:

```c
int syscall_handler(int num, int a1, int a2, int a3, int a4)
```

### Números oficiais de syscall

Fonte: [os/os_defs.h](os/os_defs.h).

| Número | Nome |
|---|---|
| 0 | SYS_EXIT |
| 1 | SYS_WRITE |
| 2 | SYS_READ |
| 3 | SYS_MALLOC |
| 4 | SYS_FREE |
| 5 | SYS_YIELD |
| 6 | SYS_GETPID |
| 7 | SYS_SLEEP |
| 8 | SYS_HEAPSTAT |
| 9 | SYS_UPTIME |

### Observações obrigatórias

- SYS_FORK não faz parte do contrato oficial atual.
- SYS_HEAPSTAT faz parte do contrato oficial atual.
- Qualquer documento com tabela diferente desta precisa ser considerado desatualizado até ser corrigido.

## Contrato de Memória do OS

Fonte: [os/os_defs.h](os/os_defs.h).

### Layout lógico em DMEM

- 0x0000-0x0FFF: variáveis globais do kernel e pilhas de ISR;
- 0x0FF0: tick counter;
- 0x1000-0x1FFF: tabela de processos;
- 0x2000-0xEFFF: heap do kernel;
- 0xF000-0xFEFF: pilha inicial de boot/ISR;
- 0xFF00-0xFFFF: MMIO.

### MMIO oficial do OS

- UART_TXDATA = 0xFF00;
- UART_RXDATA = 0xFF01;
- UART_STATUS = 0xFF02;
- TIMER_CMP_ADDR = 0xFF10;
- TIMER_CNT_ADDR = 0xFF11.

### Quantum oficial do sistema

- TIMER_QUANTUM = 10000 ciclos.

## Contrato de Boot e Vetores (Bootloader)

Fonte: [boot/bootloader.asm](boot/bootloader.asm).

### Inicialização mínima obrigatória

- reset vector em 0x000000;
- IVT_BASE = 0x0100 e escrita em CSR[1];
- BSS_START = 0x0800;
- BSS_END = 0x1000 (intervalo zerado: [0x0800, 0x0FFF]).

### Ordem oficial dos vetores IVT

- ivt_illegal;
- ivt_divzero;
- ivt_overflow;
- ivt_syscall;
- ivt_break;
- ivt_ifetch_pf;
- ivt_load_pf;
- ivt_store_pf;
- ivt_unaligned;
- ivt_timer;
- ivt_ext0;
- ivt_ext1;
- ivt_ext2;
- ivt_ext3;
- ivt_ext4;
- ivt_ext5;
- ivt_ext6.

## Contrato de Handoff do Boot em C

Fonte: [boot/bootloader.c](boot/bootloader.c).

### Detecção de modo de boot

- BOOT_SIM = 0;
- BOOT_FPGA = 1;
- seleção por GPIO_IN bit 4 (0x10): 1 = FPGA, 0 = simulação.

### Política de carga de imagem

- em BOOT_FPGA: carregar imagem de FLASH_BASE + 0x4000 para 0x00002000, com tamanho 0x2000 bytes;
- em BOOT_SIM: não recarregar imagem e seguir com execução já presente em IMEM.

### Handoff final obrigatório

- com CONFIG_HYPERVISOR: chamar hv_init() antes de hv_main();
- sem CONFIG_HYPERVISOR: chamar kernel_main();
- retorno de hv_main() ou kernel_main() é erro fatal de boot.

## Contrato de Processos do OS

Fonte: [os/os_defs.h](os/os_defs.h).

### Estrutura lógica da tabela de processos

- ENTRY_SIZE = 16 words por processo;
- FIELD_PID = 0;
- FIELD_STATE = 1;
- FIELD_PC = 2;
- FIELD_SP = 3;
- FIELD_R1 = 4, com faixa salva até o fim da entrada.

### Estados oficiais

- PROC_FREE = 0;
- PROC_READY = 1;
- PROC_RUNNING = 2;
- PROC_BLOCKED = 3;
- PROC_ZOMBIE = 4.

## Contrato Comportamental Mínimo (SO/Hypervisor)

Fontes:

- [os/scheduler.c](os/scheduler.c);
- [os/memory.c](os/memory.c);
- [hypervisor/trap_handler.c](hypervisor/trap_handler.c);
- [hypervisor/vm_manager.c](hypervisor/vm_manager.c).

### Scheduler

- scheduler_tick deve sanitizar PID atual inválido para PID_IDLE;
- scheduler_tick deve transicionar PROC_RUNNING para PROC_READY antes de escolher o próximo;
- scheduler_tick deve sanitizar PID inválido retornado por schedule() para PID_IDLE;
- scheduler_tick deve marcar o próximo processo como PROC_RUNNING.

### Heap

- kmalloc(size <= 0) deve retornar 0;
- kfree(0) deve ser operação nula segura;
- kfree deve realizar coalescência forward e backward quando houver blocos livres adjacentes;
- heap_stats deve interromper varredura ao detectar bloco corrompido (size <= 0).

### Trap e Hypercall

- TRAP_TIMER deve acionar preempção via vm_schedule_next();
- TRAP_SYSCALL com número >= 0x80 deve ser tratado como hypercall no hypervisor;
- TRAP_SYSCALL com número < 0x80 deve ser injetado para o guest (trap_inject_to_guest + vcpu_run);
- TRAP_BREAK deve avançar EPC em +4 e retomar a VM.

### Ciclo de Vida de VM

- vm_create deve inicializar VM em VM_STATE_CREATED;
- vm_start deve transicionar VM para VM_STATE_READY;
- vm_pause deve transicionar VM RUNNING/READY para VM_STATE_BLOCKED;
- vm_schedule_next deve salvar contexto e demover VM_STATE_RUNNING para VM_STATE_READY antes de hv_main().

## Contrato de Hypervisor

Fonte: [hypervisor/hypervisor.h](hypervisor/hypervisor.h).

### Capacidades base

- até 4 VMs concorrentes;
- 1 vCPU por VM;
- quantum de 10000 ciclos por VM;
- hypercalls a partir de 0x80.

### Layout físico do hypervisor

- 0x00000000-0x0000FFFF: hypervisor;
- 0x00010000-0x0001FFFF: memória da VM 0;
- 0x00020000-0x0002FFFF: memória da VM 1;
- 0x00030000-0x0003FFFF: memória da VM 2;
- 0x00040000-0x0004FFFF: memória da VM 3;
- 0x00050000-0x0005FFFF: região compartilhada/MMIO.

### Trap codes oficiais

- 0x00: illegal instruction;
- 0x01: division by zero;
- 0x02: overflow;
- 0x03: syscall;
- 0x04: break;
- 0x05: page fault;
- 0x06: misaligned access;
- 0x10: timer;
- 0x20+n: IRQ externa n.

### Hypercalls oficiais

- 0x80: HV_CALL_VERSION;
- 0x81: HV_CALL_VM_ID;
- 0x82: HV_CALL_VM_CREATE;
- 0x83: HV_CALL_VM_YIELD;
- 0x84: HV_CALL_VM_EXIT;
- 0x85: HV_CALL_CONSOLE_PUT.

### Estados de VM oficiais

- 0: VM_STATE_FREE;
- 1: VM_STATE_CREATED;
- 2: VM_STATE_READY;
- 3: VM_STATE_RUNNING;
- 4: VM_STATE_BLOCKED;
- 5: VM_STATE_HALTED.

## Contrato de Compatibilidade

### O que é compatível por obrigação

- CLI, assembler, compiler, linker, loader e simulator devem aceitar a ISA EduRISC-32v2 oficial;
- documentação principal deve referenciar EduRISC-32v2 como arquitetura vigente;
- OS, hypervisor e RTL principal devem compartilhar a mesma leitura de traps, registradores e papel de SYSCALL/ERET;
- artefatos de EduRISC-16 devem ser marcados como legado.

### O que não deve mais ser tratado como fonte principal

- [docs/architecture.md](docs/architecture.md);
- [docs/assembler.md](docs/assembler.md);
- [docs/isa.md](docs/isa.md);
- [docs/pipeline.md](docs/pipeline.md);
- [os/kernel.asm](os/kernel.asm);
- [os/syscalls.asm](os/syscalls.asm).

## Divergências já Identificadas

No estado atual, não há divergências críticas conhecidas no contrato já coberto por testes automáticos.

Essas divergências devem ser corrigidas a favor das fontes autoritativas listadas neste documento.

## Regra de Evolução

Qualquer mudança em:

- opcode;
- formato de instrução;
- papel de registradores especiais;
- tabela de syscalls;
- trap codes;
- mapa de memória;
- hypercalls;

deve atualizar, na mesma mudança:

- este contrato arquitetural;
- os testes automatizados afetados;
- a documentação principal correspondente.