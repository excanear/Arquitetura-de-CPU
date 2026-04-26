# Plano Central de Implementação e Correções Gerais

## 1. Objetivo

Este documento é o plano mestre para consolidar a plataforma EduRISC-32v2 e reduzir o desalinhamento atual entre:

- simulador e toolchain em Python;
- SO e hypervisor em C/ASM;
- RTL principal em Verilog;
- núcleo paralelo em VHDL;
- documentação e automação.

O objetivo não é apenas adicionar funcionalidades. O objetivo principal é fechar lacunas de consistência, validação, integração e manutenção para que a arquitetura deixe de ser um conjunto de frentes fortes porém parcialmente desconectadas.

## 2. Diagnóstico Atual

### 2.1 O que já está sólido

- A camada Python está funcional e validada por suíte automatizada.
- A CLI unificada está organizada em [main.py](main.py).
- Existe automação básica via [Makefile](Makefile) e CI Python em [.github/workflows/ci.yml](.github/workflows/ci.yml).
- A suíte Python está estável: 89 testes passaram localmente com `.venv\\Scripts\\python.exe -m pytest tests -q`.
- O repositório tem estrutura abrangente e bem separada por domínios: `assembler/`, `compiler/`, `simulator/`, `os/`, `hypervisor/`, `rtl_v/`, `rtl/`, `fpga/`, `verification/`, `docs/`.

### 2.2 O principal problema estrutural

O repositório mistura pelo menos duas gerações da arquitetura e da documentação.

Exemplos concretos:

- [os/kernel.asm](os/kernel.asm) ainda descreve Micro-Kernel EduRISC-16.
- [os/syscalls.asm](os/syscalls.asm) ainda descreve EduRISC-16.
- [assembler/__init__.py](assembler/__init__.py) referencia EduRISC-16.
- [docs/architecture.md](docs/architecture.md) documenta EduRISC-16.
- [docs/assembler.md](docs/assembler.md) documenta assembler de 16 bits.
- [docs/isa.md](docs/isa.md) documenta ISA EduRISC-16.
- [docs/pipeline.md](docs/pipeline.md) também está em EduRISC-16.
- Ao mesmo tempo, [README.md](README.md), [simulator/cpu_simulator.py](simulator/cpu_simulator.py), [os/syscalls.c](os/syscalls.c), [hypervisor/hv_core.c](hypervisor/hv_core.c) e os módulos em [rtl_v](rtl_v) já apontam para EduRISC-32v2.

Conclusão: hoje o maior risco do projeto não é ausência de código, e sim ausência de uma fonte única de verdade para a arquitetura vigente.

### 2.3 Lacunas de engenharia

- CI cobre Python, mas não cobre smoke tests de RTL Verilog, VHDL, integração OS/hypervisor e build FPGA.
- Não há arquivo de licença no diretório raiz.
- Há documentação muito rica, porém com sobreposição, duplicidade e versões conflitantes.
- Existem componentes legados em ASM convivendo com componentes novos em C sem uma política explícita de compatibilidade ou descontinuação.
- O repositório contém múltiplas frentes de produto, mas sem um roadmap único de dependências entre elas.

## 3. Princípios de Execução

Todas as implementações e correções futuras devem seguir estes princípios:

1. Primeiro convergir a arquitetura oficial; depois expandir funcionalidades.
2. Cada feature nova deve nascer com teste, documentação e comando de validação.
3. Nenhum módulo legado deve permanecer ambíguo: ou é mantido, ou é migrado, ou é explicitamente arquivado.
4. A documentação principal deve refletir apenas o estado suportado.
5. A integração entre Python, OS, hypervisor e RTL deve ser tratada como requisito, não como bônus.

## 4. Norte Arquitetural Oficial

O projeto deve declarar formalmente que a plataforma principal suportada é:

- EduRISC-32v2 como ISA e ecossistema educacional principal;
- pipeline principal em Verilog sob [rtl_v](rtl_v);
- toolchain e simulador em Python como ambiente de referência funcional;
- OS e hypervisor em C como software de sistema prioritário;
- RV32IMAC em VHDL sob [rtl](rtl) como trilha paralela e independente, não como substituto implícito do EduRISC-32v2.

Os artefatos EduRISC-16 só podem permanecer se forem marcados como uma destas opções:

- legado educacional;
- compatibilidade histórica;
- material arquivado sem suporte ativo.

## 5. Frentes Centrais de Trabalho

### Frente A — Convergência de Arquitetura e Documentação

Objetivo: eliminar ambiguidade entre EduRISC-16 e EduRISC-32v2.

Entregas:

- definir um documento único de arquitetura oficial;
- revisar README e docs para separar claramente `vigente`, `legado` e `experimental`;
- renomear, mover ou arquivar documentação legada;
- revisar cabeçalhos e docstrings conflitantes em módulos de código.

Arquivos âncora:

- [README.md](README.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/isa.md](docs/isa.md)
- [docs/assembler.md](docs/assembler.md)
- [docs/pipeline.md](docs/pipeline.md)
- [os/kernel.asm](os/kernel.asm)
- [os/syscalls.asm](os/syscalls.asm)
- [assembler/__init__.py](assembler/__init__.py)

Critério de aceite:

- nenhum artefato suportado descreve uma arquitetura diferente da oficial sem aviso explícito.

### Frente B — Toolchain Python como Referência de Verdade

Objetivo: consolidar a toolchain Python como baseline executável da plataforma.

Entregas:

- transformar a suíte Python em contrato mínimo da ISA e do ABI;
- ampliar testes para linker, loader, debugger e fluxos completos `compile -> assemble -> simulate -> load`;
- criar testes de compatibilidade entre assembly aceito e documentação vigente;
- definir artefatos de saída canônicos para `.hex`, `.mem`, `.coe` e trace.

Arquivos âncora:

- [main.py](main.py)
- [assembler/assembler.py](assembler/assembler.py)
- [compiler/compiler.py](compiler/compiler.py)
- [simulator/cpu_simulator.py](simulator/cpu_simulator.py)
- [toolchain/linker.py](toolchain/linker.py)
- [toolchain/loader.py](toolchain/loader.py)
- [tests/test_assembler.py](tests/test_assembler.py)
- [tests/test_compiler.py](tests/test_compiler.py)
- [tests/test_simulator.py](tests/test_simulator.py)

Critério de aceite:

- qualquer mudança de ISA, ABI, syscall ou formato de saída quebra testes automaticamente se não houver atualização coordenada.

### Frente C — SO e Hypervisor: Integração Real, não Paralela

Objetivo: alinhar o software de sistema moderno ao hardware e ao simulador.

Entregas:

- definir ABI oficial de trap, syscall, interrupções, CSRs e contexto;
- validar se o caminho C do kernel substitui definitivamente os antigos módulos ASM ou se ambos convivem com escopo distinto;
- criar testes direcionados para scheduler, heap, syscalls, traps e troca de contexto;
- especificar mapa de memória único para boot, kernel, userland, MMIO e regiões de VM.

Arquivos âncora:

- [os/os_defs.h](os/os_defs.h)
- [os/kernel.c](os/kernel.c)
- [os/syscalls.c](os/syscalls.c)
- [os/memory.c](os/memory.c)
- [os/process.c](os/process.c)
- [os/scheduler.c](os/scheduler.c)
- [os/interrupts.c](os/interrupts.c)
- [hypervisor/hypervisor.h](hypervisor/hypervisor.h)
- [hypervisor/hv_core.c](hypervisor/hv_core.c)
- [hypervisor/vm_manager.c](hypervisor/vm_manager.c)
- [hypervisor/vm_cpu.c](hypervisor/vm_cpu.c)
- [hypervisor/vm_memory.c](hypervisor/vm_memory.c)
- [hypervisor/trap_handler.c](hypervisor/trap_handler.c)

Critério de aceite:

- kernel, hypervisor e simulador compartilham o mesmo contrato de registradores, traps, memória e syscalls.

### Frente D — Fechamento do RTL Verilog

Objetivo: garantir que o RTL principal reflita a arquitetura documentada e validada pelo ecossistema Python.

Entregas:

- revisar cobertura de hazard, forwarding, branch predictor, caches, MMU e interrupções;
- criar matriz de equivalência entre instruções do simulador e sinais do RTL;
- expandir os testbenches para cenários de exceção, MMIO, syscalls, stalls longos e falhas de tradução;
- definir um smoke test automatizado de compilação e simulação RTL no CI.

Arquivos âncora:

- [rtl_v/cpu_top.v](rtl_v/cpu_top.v)
- [rtl_v/control_unit.v](rtl_v/control_unit.v)
- [rtl_v/pipeline_if.v](rtl_v/pipeline_if.v)
- [rtl_v/pipeline_id.v](rtl_v/pipeline_id.v)
- [rtl_v/pipeline_ex.v](rtl_v/pipeline_ex.v)
- [rtl_v/pipeline_mem.v](rtl_v/pipeline_mem.v)
- [rtl_v/pipeline_wb.v](rtl_v/pipeline_wb.v)
- [rtl_v/branch_predictor.v](rtl_v/branch_predictor.v)
- [rtl_v/hazard_unit.v](rtl_v/hazard_unit.v)
- [rtl_v/forwarding_unit.v](rtl_v/forwarding_unit.v)
- [verification/cpu_tb.v](verification/cpu_tb.v)
- [verification/pipeline_tests.v](verification/pipeline_tests.v)
- [verification/cache_tests.v](verification/cache_tests.v)
- [verification/mmu_tests.v](verification/mmu_tests.v)
- [verification/hypervisor_tests.v](verification/hypervisor_tests.v)

Critério de aceite:

- o CI consegue compilar o RTL principal e rodar pelo menos uma bateria reduzida de validação funcional.

### Frente E — RV32IMAC VHDL como Linha Paralela com Fronteira Clara

Objetivo: preservar o valor do núcleo VHDL sem misturá-lo conceitualmente ao EduRISC-32v2.

Entregas:

- documentar explicitamente o escopo e o status do núcleo em VHDL;
- definir quais testes pertencem ao RV32IMAC e quais pertencem ao EduRISC-32v2;
- remover qualquer ambiguidade de linguagem em README e docs;
- automatizar smoke tests de análise/simulação VHDL quando o ambiente estiver disponível.

Arquivos âncora:

- [rtl/cpu_top.vhd](rtl/cpu_top.vhd)
- [rtl/fetch/fetch_stage.vhd](rtl/fetch/fetch_stage.vhd)
- [rtl/mmu/mmu.vhd](rtl/mmu/mmu.vhd)
- [docs/rtl_architecture.md](docs/rtl_architecture.md)

Critério de aceite:

- o leitor entende em menos de 5 minutos que existem duas linhas de hardware com propósitos diferentes.

### Frente F — FPGA e Integração de Plataforma

Objetivo: fechar a distância entre demonstração local, simulação e execução em placa.

Entregas:

- padronizar fluxo `build -> convert -> load -> rtl-sim -> fpga-build`;
- versionar artefatos de integração necessários e evitar artefatos gerados no repositório sem necessidade;
- validar mapa MMIO único entre boot, kernel, hypervisor e top FPGA;
- produzir roteiro determinístico de bring-up da placa.

Arquivos âncora:

- [fpga/top.v](fpga/top.v)
- [fpga/build.tcl](fpga/build.tcl)
- [fpga/arty_a7.xdc](fpga/arty_a7.xdc)
- [boot/bootloader.asm](boot/bootloader.asm)
- [boot/bootloader.c](boot/bootloader.c)
- [syn/arty_a7_top.vhd](syn/arty_a7_top.vhd)

Critério de aceite:

- o fluxo FPGA tem passos reproduzíveis e documentados a partir de um programa exemplo.

### Frente G — Engenharia, Qualidade e Governança

Objetivo: reduzir o custo de evolução do repositório.

Entregas:

- adicionar licença;
- estabelecer convenção de diretórios `current`, `legacy`, `experimental` se necessário;
- padronizar naming, cabeçalhos, banners e versão do projeto;
- ampliar CI em camadas: Python, docs, RTL, opcional VHDL;
- adicionar checklist de PR e critérios mínimos por mudança.

Arquivos âncora:

- [.github/workflows/ci.yml](.github/workflows/ci.yml)
- [README.md](README.md)
- [LEIAME.md](LEIAME.md)
- [requirements.txt](requirements.txt)

Critério de aceite:

- qualquer colaborador novo consegue entender o que está suportado, como validar e onde tocar sem ambiguidade.

## 6. Ordem de Execução Recomendada

### Fase 0 — Baseline e Congelamento de Contratos

Prioridade máxima.

1. Declarar oficialmente o que é suportado e o que é legado.
2. Congelar ISA, ABI, mapa de memória e contratos de syscall/trap em documento único.
3. Registrar comandos oficiais de validação por camada.

Saída esperada:

- arquitetura oficial definida;
- backlog organizado por frentes;
- zero ambiguidade sobre o que é atual.

### Fase 1 — Higiene Estrutural

1. Corrigir cabeçalhos, docstrings e docs conflitantes.
2. Isolar ou arquivar material EduRISC-16.
3. Adicionar licença.
4. Revisar README/LEIAME para refletir a estrutura real.

Saída esperada:

- repositório coerente em nomenclatura e posicionamento.

### Fase 2 — Fortalecimento da Baseline Python

1. Expandir testes para fluxos completos.
2. Criar fixtures de integração para exemplos em [examples](examples).
3. Garantir que CLI, assembler, compiler, simulator, linker e loader compartilhem contratos claros.

Saída esperada:

- toolchain tratada como oráculo funcional do projeto.

### Fase 3 — Integração SO/Hypervisor

1. Unificar contratos de exceção, contexto, syscalls e MMIO.
2. Definir estratégia para ASM legado do SO.
3. Adicionar testes de comportamento para scheduler, heap e traps.

Saída esperada:

- software de sistema consistente com a plataforma oficial.

### Fase 4 — Fechamento RTL Verilog

1. Levar equivalência funcional entre Python e RTL para uma esteira automatizada.
2. Adicionar smoke test RTL no CI.
3. Fechar cenários de cache, MMU, interrupções, stalls e branches.

Saída esperada:

- confiança mínima de hardware em toda mudança crítica.

### Fase 5 — Linha VHDL e FPGA

1. Separar claramente objetivos do RV32IMAC.
2. Formalizar fluxo FPGA reproduzível.
3. Integrar demonstrações reais com documentação e scripts.

Saída esperada:

- trilha de hardware avançado governada e reproduzível.

## 7. Quick Wins

Estes itens podem ser executados imediatamente e têm alto retorno:

1. Corrigir referências EduRISC-16 em arquivos suportados ou movê-los para uma área legada.
2. Adicionar LICENSE na raiz.
3. Criar seção no README com status por trilha: `suportado`, `legado`, `experimental`.
4. Expandir o CI atual para pelo menos compilar o RTL principal além do pytest.
5. Criar uma tabela oficial de contratos: ISA, registradores, syscalls, traps, MMIO e formatos de artefato.

## 8. Mudanças Maiores

Estas mudanças exigem desenho e execução coordenada:

1. Unificação completa entre simulador, kernel, hypervisor e RTL em torno de um ABI único.
2. Estratégia definitiva para coexistência ou remoção do caminho EduRISC-16.
3. Equivalência funcional automatizada entre simulador Python e RTL Verilog.
4. Separação editorial e técnica madura entre EduRISC-32v2 e RV32IMAC.

## 9. Critérios de Conclusão do Plano

O plano pode ser considerado cumprido quando:

- a arquitetura oficial estiver inequívoca;
- docs, código e testes estiverem apontando para o mesmo contrato;
- a esteira de validação cobrir Python e pelo menos smoke tests de hardware principal;
- não existirem mais artefatos ambíguos entre suportado e legado;
- FPGA, simulador e software de sistema estiverem documentados com fluxo executável único.

## 10. Próxima Sequência Recomendada

Para começar de forma pragmática, a ordem ideal das próximas execuções é:

1. saneamento de documentação e artefatos legados;
2. definição do contrato arquitetural oficial;
3. reforço da esteira de testes Python e integração;
4. alinhamento SO/hypervisor;
5. automação de smoke tests RTL;
6. fechamento de FPGA e VHDL.

---

## Resumo Executivo

O projeto já tem massa crítica real. O problema central não é falta de implementação; é falta de convergência. A prioridade correta agora é consolidar uma plataforma oficial única, transformar a toolchain em baseline contratual e só então empilhar novas entregas sobre uma arquitetura sem ambiguidades.