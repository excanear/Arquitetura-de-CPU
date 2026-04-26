## Resumo

Descreva em 3-6 linhas o problema e a mudança proposta.

## Tipo de Mudança

- [ ] Correção de bug
- [ ] Nova funcionalidade
- [ ] Refatoração sem mudança de comportamento
- [ ] Mudança de contrato arquitetural (ISA/ABI/syscalls/MMIO/traps/hypercalls)
- [ ] Documentação
- [ ] CI/CD

## Trilhas Impactadas

- [ ] EduRISC-32v2 Python + Toolchain
- [ ] EduRISC-32v2 RTL Verilog
- [ ] OS + Hypervisor
- [ ] RV32IMAC VHDL
- [ ] Artefatos legados EduRISC-16

## Checklist de Qualidade

- [ ] Rodei os testes locais relevantes e eles passaram
- [ ] Se alterei contrato, atualizei docs/contrato_arquitetural.md
- [ ] Se alterei syscall/MMIO/traps/hypercalls/VM states, atualizei testes de consistência
- [ ] Se alterei docs, validei links e tabelas principais
- [ ] Não introduzi mudanças não relacionadas ao objetivo deste PR

## Evidências de Validação

Cole os comandos executados e os resultados principais.

Exemplo:

- .venv\Scripts\python.exe -m pytest tests/test_contract_consistency.py -q
- .venv\Scripts\python.exe -m pytest tests -q

## Riscos e Mitigações

Liste riscos técnicos e como foram mitigados.

## Observações

Notas adicionais para revisão (decisões de design, trade-offs, follow-ups).
