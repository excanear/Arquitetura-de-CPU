"""
pipeline.py — Pipeline de 5 Estágios EduRISC-32v2

Implementa os registradores inter-estágio e a lógica de:
  - Detecção de hazards (data hazard load-use, control hazard)
  - Forwarding (EX/MEM → EX  e  MEM/WB → EX)
  - Flush e stall

Estágios:
  IF  — busca de instrução (PC → memória de instrução)
  ID  — decodificação e leitura de registradores
  EX  — execução na ALU e cálculo de endereços
  MEM — acesso à memória de dados
  WB  — escrita no banco de registradores

Registradores inter-estágio:
  IF/ID   — guarda a instrução buscada de 32 bits e PC+1
  ID/EX   — guarda sinais de controle, valores de registradores e campos decodificados
  EX/MEM  — guarda resultado da ALU, dado para STORE e sinal de salto
  MEM/WB  — guarda dado lido da memória ou resultado da ALU para WB
"""

from dataclasses import dataclass, field
from cpu.instruction_set import Opcode, InstFmt, WORD_MASK, NOP_WORD, ZERO_REG
from cpu.control_unit import ControlSignals


# ---------------------------------------------------------------------------
# Registradores inter-estágio
# ---------------------------------------------------------------------------

@dataclass
class IFIDReg:
    """Registrador de pipeline IF/ID — instrução de 32 bits + PC+1."""
    instruction: int  = NOP_WORD   # palavra de instrução (32 bits); NOP por padrão
    pc_plus1:    int  = 0
    valid:       bool = False

    def flush(self):
        """Insere bolha (NOP) no estágio — equivale a cancelar a instrução buscada."""
        self.instruction = NOP_WORD
        self.valid       = False


@dataclass
class IDEXReg:
    """Registrador de pipeline ID/EX — campos decodificados e valores de regs."""
    opcode:   Opcode         = Opcode.HLT
    fmt:      InstFmt        = InstFmt.J        # formato da instrução decodificada
    ctrl:     ControlSignals = field(default_factory=ControlSignals)
    rs1_val:  int            = 0    # valor lido de rs1 (ou 0 para R0)
    rs2_val:  int            = 0    # valor lido de rs2 ou imediato preparado
    rd:       int            = 0    # registrador destino
    rs1:      int            = 0    # índice de rs1
    rs2:      int            = 0    # índice de rs2
    shamt:    int            = 0    # campo shamt para deslocamentos imediatos
    addr:     int            = 0    # campo addr26 para J-type
    offset:   int            = 0    # campo off16/imm16 (sign-extended)
    pc_plus1: int            = 0    # PC+1 (para CALL/CALLR salvarem em LR)
    valid:    bool           = False

    def flush(self):
        """Insere bolha — limpa todos os sinais de controle."""
        self.ctrl  = ControlSignals(is_nop=True)
        self.fmt   = InstFmt.J
        self.valid = False
        self.rd    = 0


@dataclass
class EXMEMReg:
    """Registrador de pipeline EX/MEM — resultado da ALU e controle de memória."""
    ctrl:       ControlSignals = field(default_factory=ControlSignals)
    alu_result: int            = 0    # resultado da ALU (também endereço MEM)
    rs2_val:    int            = 0    # dado para STORE
    rd:         int            = 0    # registrador destino
    mem_addr:   int            = 0    # endereço de memória calculado
    jump_pc:    int            = 0    # PC de destino de salto/desvio
    take_jump:  bool           = False
    valid:      bool           = False

    def flush(self):
        self.ctrl      = ControlSignals(is_nop=True)
        self.take_jump = False
        self.valid     = False
        self.rd        = 0


@dataclass
class MEMWBReg:
    """Registrador de pipeline MEM/WB — dado de memória ou resultado ALU para WB."""
    ctrl:       ControlSignals = field(default_factory=ControlSignals)
    alu_result: int            = 0
    mem_data:   int            = 0
    rd:         int            = 0
    valid:      bool           = False

    def flush(self):
        self.ctrl  = ControlSignals(is_nop=True)
        self.valid = False
        self.rd    = 0


# ---------------------------------------------------------------------------
# Lógica de Hazard e Forwarding
# ---------------------------------------------------------------------------

class HazardUnit:
    """
    Detecta hazards de dados (load-use) e gera sinal de stall.

    Load-use hazard:
      Uma instrução LOAD em ID/EX ainda não completou a leitura de memória
      quando a instrução seguinte já está em IF/ID precisando do mesmo valor.
      Solução: inserir 1 ciclo de bolha (stall) para aguardar o dado.

    Decodificação de rs1/rs2 para instruções EduRISC-32v2 de 32 bits:
      rs1 em bits [20:16], rs2 em bits [15:11] (formatos R, S, B)
      Para I-type: apenas rs1 existe (rs2 campo = imediato)
    """

    def detect_load_use(self, idex: IDEXReg, ifid: IFIDReg) -> bool:
        """
        Retorna True se a instrução em ID/EX é LOAD e o registrador destino
        coincide com algum operando fonte da instrução em IF/ID.
        """
        if not idex.valid or not idex.ctrl.mem_read or idex.ctrl.pop:
            return False

        # Extrai índices de registradores fonte da próxima instrução (em IF/ID)
        next_word = ifid.instruction
        next_rs1  = (next_word >> 16) & 0x1F
        next_rs2  = (next_word >> 11) & 0x1F

        # R0 é hardwired zero → sem dependência real
        if idex.rd == ZERO_REG:
            return False

        return (idex.rd == next_rs1) or (idex.rd == next_rs2)


class ForwardingUnit:
    """
    Calcula os muxes de forwarding para evitar stalls desnecessários por RAW.

    Forwarding permite que o resultado de uma instrução ainda no pipeline
    seja utilizado como operando de uma instrução posterior sem stall,
    desde que o dado já esteja disponível (não seja um load-use).

    Forward A (operando rs1 do estágio EX):
      0 → sem forwarding — usa valor lido do banco de registradores em ID
      1 → forward de MEM/WB — resultado da ALU ou dado carregado da memória
      2 → forward de EX/MEM — resultado da ALU (prioridade máxima)

    Forward B (operando rs2): idem.
    """

    def calc(self, idex: IDEXReg, exmem: EXMEMReg, memwb: MEMWBReg) -> tuple[int, int]:
        """Retorna (fwd_a, fwd_b) com os seletores de mux."""
        fwd_a = 0
        fwd_b = 0

        # Forward de EX/MEM → EX (prioridade maior, dado mais recente)
        # Guarda: R0 é hardwired zero → nunca faz forwarding para R0
        if exmem.valid and exmem.ctrl.reg_write and exmem.rd != ZERO_REG:
            if exmem.rd == idex.rs1:
                fwd_a = 2
            if exmem.rd == idex.rs2:
                fwd_b = 2

        # Forward de MEM/WB → EX (prioridade menor, dado mais antigo)
        if memwb.valid and memwb.ctrl.reg_write and memwb.rd != ZERO_REG:
            if memwb.rd == idex.rs1 and fwd_a == 0:
                fwd_a = 1
            if memwb.rd == idex.rs2 and fwd_b == 0:
                fwd_b = 1

        return fwd_a, fwd_b

    def resolve(self, fwd_a: int, fwd_b: int,
                idex: IDEXReg, exmem: EXMEMReg, memwb: MEMWBReg) -> tuple[int, int]:
        """Retorna os valores reais de operando A e B após aplicar forwarding."""
        def pick_wb(mwb: MEMWBReg) -> int:
            return mwb.mem_data if mwb.ctrl.mem_read else mwb.alu_result

        a = idex.rs1_val
        if fwd_a == 2:
            a = exmem.alu_result
        elif fwd_a == 1:
            a = pick_wb(memwb)

        b = idex.rs2_val
        if fwd_b == 2:
            b = exmem.alu_result
        elif fwd_b == 1:
            b = pick_wb(memwb)

        return a & WORD_MASK, b & WORD_MASK
