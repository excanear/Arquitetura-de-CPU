"""
control_unit.py — Unidade de Controle EduRISC-32v2

Decodifica a instrução e gera os sinais de controle para o datapath do
pipeline de 5 estágios. Modela o comportamento combinacional de uma
unidade de controle de hardware real.

Sinais de controle gerados:
  alu_src    — True: operando B da ALU vem do imediato/offset (I/S/B/U-type)
               False: operando B da ALU vem do banco de registradores (R-type)
  mem_read   — True: habilita leitura de memória no estágio MEM (loads)
  mem_write  — True: habilita escrita em memória no estágio MEM (stores)
  reg_write  — True: habilita escrita de resultado em registrador no estágio WB
  branch     — True: instrução de desvio condicional (BEQ, BNE, BLT, BGE, ...)
  jump       — True: salto incondicional (JMP, CALL, CALLR, RET, JMPR)
  halt       — True: instrução HLT — drena pipeline e para execução
  call       — True: CALL/CALLR — salva PC+1 em LR (R31) antes de saltar
  ret        — True: RET — salta para o endereço em LR (R31)
  is_nop     — True: bolha de pipeline (NOP) — sem efeitos colaterais
  push       — True: PUSH — decrementa SP e armazena rs1 em memória
  pop        — True: POP  — carrega memória e incrementa SP
  eret       — True: ERET — retorno de exceção (restaura CSR_EPC)
  syscall    — True: SYSCALL — transfere controle para handler de exceção
"""

from dataclasses import dataclass, field
from cpu.instruction_set import (
    Opcode, InstFmt, OPCODE_FMT, NOP_WORD, decode,
)


@dataclass
class ControlSignals:
    alu_src:   bool = False   # True → usa imediato/offset como operando B
    mem_read:  bool = False   # True → lê memória (load)
    mem_write: bool = False   # True → escreve memória (store)
    reg_write: bool = False   # True → escreve em registrador (WB)
    branch:    bool = False   # True → desvio condicional (comparação de regs)
    jump:      bool = False   # True → salto incondicional
    halt:      bool = False   # True → para execução após drenar pipeline
    call:      bool = False   # True → CALL/CALLR (salva LR=R31)
    ret:       bool = False   # True → RET (PC ← R31)
    is_nop:    bool = False   # True → bolha de pipeline
    push:      bool = False   # True → PUSH (SP--, Mem[SP]=rs1)
    pop:       bool = False   # True → POP  (rd=Mem[SP], SP++)
    eret:      bool = False   # True → ERET (retorno de exceção)
    syscall:   bool = False   # True → SYSCALL

    def __repr__(self) -> str:
        active = [f.upper() for f, v in self.__dict__.items() if v]
        return f"Ctrl[{' '.join(active) if active else 'NOP'}]"


# Conjuntos de opcodes por categoria para lookup O(1)
_LOADS   = frozenset({Opcode.LW, Opcode.LH, Opcode.LHU, Opcode.LB, Opcode.LBU})
_STORES  = frozenset({Opcode.SW, Opcode.SH, Opcode.SB})
_BRANCHES = frozenset({Opcode.BEQ, Opcode.BNE, Opcode.BLT, Opcode.BGE,
                        Opcode.BLTU, Opcode.BGEU})
_R_ALU   = frozenset({Opcode.ADD, Opcode.SUB, Opcode.MUL, Opcode.MULH,
                       Opcode.DIV, Opcode.DIVU, Opcode.REM,
                       Opcode.AND, Opcode.OR,  Opcode.XOR, Opcode.NOT, Opcode.NEG,
                       Opcode.SHL, Opcode.SHR, Opcode.SHRA,
                       Opcode.SHLI, Opcode.SHRI, Opcode.SHRAI,
                       Opcode.MOV, Opcode.SLT, Opcode.SLTU})
_I_ALU   = frozenset({Opcode.ADDI, Opcode.ANDI, Opcode.ORI, Opcode.XORI,
                       Opcode.MOVI, Opcode.SLTI})
_MOVHI   = frozenset({Opcode.MOVHI})
_JUMPS   = frozenset({Opcode.JMP, Opcode.JMPR})
_CALLS   = frozenset({Opcode.CALL, Opcode.CALLR})
_CSR     = frozenset({Opcode.MFC, Opcode.MTC})


class ControlUnit:
    """
    Unidade de controle combinacional EduRISC-32v2.

    Recebe uma palavra de instrução de 32 bits e devolve um ControlSignals
    com todos os sinais de controle necessários para o datapath.

    Uso:
        cu = ControlUnit()
        ctrl = cu.decode(instruction_word)
    """

    def decode(self, word: int) -> ControlSignals:
        """Gera sinais de controle a partir de uma palavra de instrução de 32 bits."""
        # Bolha explícita: palavra NOP codificada ou palavra zero
        if word == NOP_WORD or word == 0:
            return ControlSignals(is_nop=True)

        try:
            d = decode(word)
        except Exception:
            return ControlSignals(is_nop=True)

        opcode = d.get("opcode")
        if opcode is None:
            return ControlSignals(is_nop=True)

        ctrl = ControlSignals()

        # ---- Instruções aritméticas/lógicas R-type (registrador → registrador) ----
        if opcode in _R_ALU:
            ctrl.reg_write = True

        # ---- Instruções aritméticas/lógicas I-type (imediato) ----
        elif opcode in _I_ALU:
            ctrl.reg_write = True
            ctrl.alu_src   = True   # operando B = imediato sign-extended

        # ---- MOVHI (U-type) — carrega imediato de 21 bits no topo do registrador ----
        elif opcode in _MOVHI:
            ctrl.reg_write = True
            ctrl.alu_src   = True

        # ---- Loads (I-type) ----
        elif opcode in _LOADS:
            ctrl.mem_read  = True
            ctrl.reg_write = True
            ctrl.alu_src   = True   # endereço = rs1 + sext(off16)

        # ---- Stores (S-type) ----
        elif opcode in _STORES:
            ctrl.mem_write = True
            ctrl.alu_src   = True   # endereço = rs1 + sext(off16)

        # ---- Desvios condicionais (B-type) — comparação direta de registradores ----
        elif opcode in _BRANCHES:
            ctrl.branch = True

        # ---- Saltos incondicionais ----
        elif opcode in _JUMPS:
            ctrl.jump = True
            if opcode == Opcode.JMPR:
                ctrl.alu_src = True   # PC = rs1 + sext(off16)

        # ---- CALL e CALLR — salto + salva endereço de retorno em R31 ----
        elif opcode in _CALLS:
            ctrl.jump      = True
            ctrl.call      = True
            ctrl.reg_write = True   # rd = R31 ← PC+1
            if opcode == Opcode.CALLR:
                ctrl.alu_src = False  # CALLR: PC = rs1 (sem offset)

        # ---- RET — salto para R31 ----
        elif opcode == Opcode.RET:
            ctrl.ret  = True
            ctrl.jump = True

        # ---- PUSH ----
        elif opcode == Opcode.PUSH:
            ctrl.mem_write = True
            ctrl.push      = True

        # ---- POP ----
        elif opcode == Opcode.POP:
            ctrl.mem_read  = True
            ctrl.reg_write = True
            ctrl.pop       = True

        # ---- Instruções de sistema ----
        elif opcode == Opcode.HLT:
            ctrl.halt = True

        elif opcode == Opcode.NOP:
            ctrl.is_nop = True

        elif opcode == Opcode.SYSCALL:
            ctrl.syscall = True

        elif opcode == Opcode.ERET:
            ctrl.eret = True
            ctrl.jump = True

        elif opcode in _CSR:
            # MFC: rd ← CSR[idx]    →  reg_write
            # MTC: CSR[idx] ← rs1   →  nenhum reg_write
            if opcode == Opcode.MFC:
                ctrl.reg_write = True
            ctrl.alu_src = True

        elif opcode == Opcode.FENCE:
            ctrl.is_nop = True   # FENCE: sem efeito no simulador (sincronização)

        elif opcode == Opcode.BREAK:
            ctrl.syscall = True   # BREAK: trata como armadilha de depuração

        return ctrl
