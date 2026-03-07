"""
__init__.py — Pacote cpu

Exporta os principais módulos do núcleo da CPU EduRISC-16.
"""

from cpu.instruction_set import (
    Opcode, InstType, OPCODE_TYPE, MNEMONIC_TO_OPCODE,
    NUM_REGISTERS, WORD_BITS, WORD_MASK, MEM_SIZE, LINK_REG,
    encode_r, encode_m, encode_j, decode, disassemble,
)
from cpu.registers import RegisterFile, Flags
from cpu.alu import ALU, ALUResult
from cpu.control_unit import ControlUnit, ControlSignals
from cpu.pipeline import (
    IFIDReg, IDEXReg, EXMEMReg, MEMWBReg,
    HazardUnit, ForwardingUnit,
)

__all__ = [
    "Opcode", "InstType", "OPCODE_TYPE", "MNEMONIC_TO_OPCODE",
    "NUM_REGISTERS", "WORD_BITS", "WORD_MASK", "MEM_SIZE", "LINK_REG",
    "encode_r", "encode_m", "encode_j", "decode", "disassemble",
    "RegisterFile", "Flags",
    "ALU", "ALUResult",
    "ControlUnit", "ControlSignals",
    "IFIDReg", "IDEXReg", "EXMEMReg", "MEMWBReg",
    "HazardUnit", "ForwardingUnit",
]
