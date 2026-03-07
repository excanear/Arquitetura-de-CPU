"""
pipeline.py — Pipeline de 5 Estágios EduRISC-16

Implementa os registradores inter-estágio e a lógica de:
  - Detecção de hazards (data hazard load-use, control hazard)
  - Forwarding (EX/MEM → EX  e  MEM/WB → EX)
  - Flush e stall

Estágios:
  IF  — busca de instrução
  ID  — decodificação e leitura de registradores
  EX  — execução na ALU
  MEM — acesso à memória
  WB  — escrita no banco de registradores

Registradores inter-estágio:
  IF/ID   — guarda a instrução buscada e o PC+1
  ID/EX   — guarda sinais decodificados e valores de registradores
  EX/MEM  — guarda resultado da ALU e dados para memória
  MEM/WB  — guarda dado lido da memória ou resultado da ALU
"""

from dataclasses import dataclass, field
from cpu.instruction_set import Opcode, WORD_MASK
from cpu.control_unit import ControlSignals


# ---------------------------------------------------------------------------
# Registradores inter-estágio
# ---------------------------------------------------------------------------

@dataclass
class IFIDReg:
    """Registrador de pipeline IF/ID."""
    instruction: int    = 0xFFFF  # NOP
    pc_plus1:    int    = 0
    valid:       bool   = False

    def flush(self):
        self.instruction = 0xFFFF
        self.valid       = False


@dataclass
class IDEXReg:
    """Registrador de pipeline ID/EX."""
    opcode:   Opcode         = Opcode.HLT
    ctrl:     ControlSignals = field(default_factory=ControlSignals)
    rs1_val:  int            = 0
    rs2_val:  int            = 0
    rd:       int            = 0
    rs1:      int            = 0
    rs2:      int            = 0
    addr:     int            = 0   # endereço J-type
    offset:   int            = 0   # offset M-type
    base_reg: int            = 0   # registrador base M-type
    pc_plus1: int            = 0
    valid:    bool           = False

    def flush(self):
        self.ctrl  = ControlSignals(is_nop=True)
        self.valid = False


@dataclass
class EXMEMReg:
    """Registrador de pipeline EX/MEM."""
    ctrl:      ControlSignals = field(default_factory=ControlSignals)
    alu_result: int           = 0
    rs2_val:    int           = 0   # dado para STORE
    rd:         int           = 0
    mem_addr:   int           = 0
    jump_pc:    int           = 0
    take_jump:  bool          = False
    valid:      bool          = False

    def flush(self):
        self.ctrl      = ControlSignals(is_nop=True)
        self.take_jump = False
        self.valid     = False


@dataclass
class MEMWBReg:
    """Registrador de pipeline MEM/WB."""
    ctrl:       ControlSignals = field(default_factory=ControlSignals)
    alu_result: int            = 0
    mem_data:   int            = 0
    rd:         int            = 0
    valid:      bool           = False

    def flush(self):
        self.ctrl  = ControlSignals(is_nop=True)
        self.valid = False


# ---------------------------------------------------------------------------
# Lógica de Hazard e Forwarding
# ---------------------------------------------------------------------------

class HazardUnit:
    """
    Detecta hazards de dados (load-use) e gera sinais de stall.

    Load-use hazard:
      LOAD no estágio EX/ID ainda não escreveu o registrador;
      a instrução seguinte precisa desse valor → inserir 1 bolha.
    """

    def detect_load_use(self, idex: IDEXReg, ifid: IFIDReg) -> bool:
        """
        Retorna True se a instrução no estágio ID/EX é LOAD
        e o registrador destino coincide com algum operando da instrução em IF/ID.
        """
        if not idex.valid or not idex.ctrl.mem_read:
            return False
        # decodifica rdest da instrução seguinte
        next_word = ifid.instruction
        next_rs1  = (next_word >> 4) & 0xF
        next_rs2  = next_word & 0xF
        return (idex.rd == next_rs1) or (idex.rd == next_rs2)


class ForwardingUnit:
    """
    Calcula os muxes de forwarding para evitar stalls por RAW sem load-use.

    Forward A (operando rs1 do estágio EX):
      0 → sem forwarding (usa valor do banco de reg)
      1 → forward de MEM/WB (resultado ALU ou dado de memória)
      2 → forward de EX/MEM (resultado ALU)

    Forward B: idem para rs2.
    """

    def calc(self, idex: IDEXReg, exmem: EXMEMReg, memwb: MEMWBReg) -> tuple[int, int]:
        """Retorna (fwd_a, fwd_b)."""
        fwd_a = 0
        fwd_b = 0

        # Forward de EX/MEM → EX (prioridade maior)
        if exmem.valid and exmem.ctrl.reg_write and exmem.rd != 0:
            if exmem.rd == idex.rs1:
                fwd_a = 2
            if exmem.rd == idex.rs2:
                fwd_b = 2

        # Forward de MEM/WB → EX
        if memwb.valid and memwb.ctrl.reg_write and memwb.rd != 0:
            if memwb.rd == idex.rs1 and fwd_a == 0:
                fwd_a = 1
            if memwb.rd == idex.rs2 and fwd_b == 0:
                fwd_b = 1

        return fwd_a, fwd_b

    def resolve(self, fwd_a: int, fwd_b: int,
                idex: IDEXReg, exmem: EXMEMReg, memwb: MEMWBReg) -> tuple[int, int]:
        """Retorna os valores reais de operando A e B após forwarding."""
        def pick_wb(memwb):
            return memwb.mem_data if memwb.ctrl.mem_read else memwb.alu_result

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
