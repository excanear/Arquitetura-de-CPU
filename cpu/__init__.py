"""
__init__.py — Pacote cpu

Exporta os principais módulos do núcleo da CPU EduRISC-32v2.
32 bits, 32 registradores de uso geral (R0 hardwired zero, R30=SP, R31=LR).
Pipeline de 5 estágios com forwarding e hazard detection.
"""

from cpu.instruction_set import (
    Opcode, InstFmt, InstType, OPCODE_FMT, OPCODE_TYPE, MNEMONIC_TO_OPCODE,
    NUM_REGISTERS, WORD_BITS, WORD_MASK, MEM_SIZE,
    ZERO_REG, SP_REG, LR_REG, LINK_REG, NOP_WORD,
    encode_r, encode_i, encode_s, encode_b, encode_j, encode_u, encode_m,
    decode, disassemble,
)
from cpu.registers import RegisterFile, Flags
from cpu.alu import ALU, ALUResult
from cpu.control_unit import ControlUnit, ControlSignals
from cpu.pipeline import (
    IFIDReg, IDEXReg, EXMEMReg, MEMWBReg,
    HazardUnit, ForwardingUnit,
)

__all__ = [
    # ISA
    "Opcode", "InstFmt", "InstType", "OPCODE_FMT", "OPCODE_TYPE",
    "MNEMONIC_TO_OPCODE",
    "NUM_REGISTERS", "WORD_BITS", "WORD_MASK", "MEM_SIZE",
    "ZERO_REG", "SP_REG", "LR_REG", "LINK_REG", "NOP_WORD",
    "encode_r", "encode_i", "encode_s", "encode_b", "encode_j", "encode_u", "encode_m",
    "decode", "disassemble",
    # Banco de registradores e flags
    "RegisterFile", "Flags",
    # ALU
    "ALU", "ALUResult",
    # Unidade de controle
    "ControlUnit", "ControlSignals",
    # Registradores de pipeline e unidades de hazard/forwarding
    "IFIDReg", "IDEXReg", "EXMEMReg", "MEMWBReg",
    "HazardUnit", "ForwardingUnit",
]
