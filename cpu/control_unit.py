"""
control_unit.py — Unidade de Controle EduRISC-16

Decodifica a instrução e gera os sinais de controle para o datapath.
Modela o comportamento combinacional da unidade de controle real.

Sinais de controle gerados:
  alu_src    — fonte do segundo operando da ALU (registrador ou imediato/offset)
  mem_read   — habilita leitura de memória
  mem_write  — habilita escrita em memória
  reg_write  — habilita escrita no banco de registradores
  branch     — instrução de desvio condicional
  jump       — instrução de salto incondicional
  halt       — instrução HLT
  call       — instrução CALL (salva PC em R15)
  ret        — instrução RET (PC ← R15)
"""

from dataclasses import dataclass
from cpu.instruction_set import Opcode, OPCODE_TYPE, InstType, decode


@dataclass
class ControlSignals:
    alu_src:   bool = False   # True → usa offset/imediato como operando B da ALU
    mem_read:  bool = False   # True → lê memória no estágio MEM
    mem_write: bool = False   # True → escreve memória no estágio MEM
    reg_write: bool = False   # True → escreve resultado em registrador no estágio WB
    branch:    bool = False   # True → instrução de desvio condicional
    jump:      bool = False   # True → salto incondicional
    halt:      bool = False   # True → para execução
    call:      bool = False   # True → CALL (salva link)
    ret:       bool = False   # True → RET (usa link)
    is_nop:    bool = False   # True → bolha de pipeline (NOP)

    def __repr__(self) -> str:
        active = [f.upper() for f, v in self.__dict__.items() if v]
        return f"Ctrl[{' '.join(active) if active else 'NOP'}]"


class ControlUnit:
    """
    Unidade de controle combinacional.

    Uso:
        cu = ControlUnit()
        ctrl = cu.decode(instruction_word)
    """

    def decode(self, word: int) -> ControlSignals:
        """Gera sinais de controle a partir de uma palavra de instrução."""
        if word == 0xFFFF:  # NOP explícito
            return ControlSignals(is_nop=True)

        try:
            d = decode(word)
        except Exception:
            return ControlSignals(is_nop=True)

        opcode = d["opcode"]
        ctrl   = ControlSignals()

        match opcode:
            case Opcode.ADD | Opcode.SUB | Opcode.MUL | Opcode.DIV | \
                 Opcode.AND | Opcode.OR  | Opcode.XOR | Opcode.NOT:
                ctrl.reg_write = True

            case Opcode.LOAD:
                ctrl.mem_read  = True
                ctrl.reg_write = True
                ctrl.alu_src   = True   # offset como imediato

            case Opcode.STORE:
                ctrl.mem_write = True
                ctrl.alu_src   = True

            case Opcode.JMP:
                ctrl.jump = True

            case Opcode.JZ | Opcode.JNZ:
                ctrl.branch = True
                ctrl.jump   = True   # também sinaliza desvio de PC

            case Opcode.CALL:
                ctrl.jump      = True
                ctrl.call      = True
                ctrl.reg_write = True   # escreve R15

            case Opcode.RET:
                ctrl.ret  = True
                ctrl.jump = True

            case Opcode.HLT:
                ctrl.halt = True

        return ctrl
