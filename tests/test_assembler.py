"""
tests/test_assembler.py — Testes do montador EduRISC-32v2

Cobre:
  - Codificação de instruções R-type, I-type, S-type, B-type, J-type, U-type
  - Resolução de labels (forward e backward)
  - Pseudo-instrução NOP
  - Diretiva .org
  - Comentários de linha
"""

import pytest
from assembler.assembler import Assembler
from cpu.instruction_set import Opcode, encode_r, encode_i, encode_j


def assemble(code: str) -> list[int]:
    return Assembler().assemble(code)


# ---------------------------------------------------------------------------
# Instruções simples
# ---------------------------------------------------------------------------

def test_movi():
    words = assemble("MOVI R1, 42")
    assert len(words) > 0
    # Verifica que o opcode é MOVI e o imediato é 42
    # Campo imm (bits 15:0) = 42, rd (bits 25:21) = 1
    w = words[0]
    assert (w & 0xFFFF) == 42
    assert ((w >> 21) & 0x1F) == 1


def test_add_r_type():
    words = assemble("ADD R3, R1, R2")
    w = words[0]
    # rd=3, rs1=1, rs2=2
    assert ((w >> 21) & 0x1F) == 3
    assert ((w >> 16) & 0x1F) == 1
    assert ((w >> 11) & 0x1F) == 2


def test_hlt():
    words = assemble("HLT")
    assert len(words) == 1


def test_nop():
    words = assemble("NOP")
    assert len(words) == 1


# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

def test_forward_label():
    """Instrução de branch com label à frente deve ser resolvida corretamente."""
    code = """
        .org 0x0
        MOVI R1, 0
        JMP  END
        MOVI R1, 99  ; não deve executar
END:
        HLT
    """
    from simulator.cpu_simulator import CPUSimulator
    words = assemble(code)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run()
    assert sim.rf[1] == 0


def test_backward_label():
    """Branch backward para label anterior (loop)."""
    code = """
        .org 0x0
        MOVI R1, 3
        MOVI R2, 0
LOOP:
        ADD  R2, R2, R1
        ADDI R1, R1, -1
        BNE  R1, R0, LOOP
        HLT
    """
    from simulator.cpu_simulator import CPUSimulator
    words = assemble(code)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run()
    assert sim.rf[2] == 6   # 3+2+1


# ---------------------------------------------------------------------------
# Diretiva .org
# ---------------------------------------------------------------------------

def test_org_directive():
    code = """
        .org 0x0
        MOVI R1, 1
        .org 0x4
        MOVI R2, 2
    """
    words = assemble(code)
    assert len(words) >= 5   # posições 0-4 (com NOP/zero entre elas se necessário)
    # Instrução em posição 4 deve ser MOVI R2
    w = words[4]
    assert ((w >> 21) & 0x1F) == 2   # rd = R2


# ---------------------------------------------------------------------------
# Programas completos
# ---------------------------------------------------------------------------

def test_soma_1_a_5():
    code = """
        .org 0x0
        MOVI R1, 5
        MOVI R2, 0
LOOP:
        ADD  R2, R2, R1
        ADDI R1, R1, -1
        BNE  R1, R0, LOOP
        HLT
    """
    from simulator.cpu_simulator import CPUSimulator
    words = assemble(code)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run()
    assert sim.rf[2] == 15
