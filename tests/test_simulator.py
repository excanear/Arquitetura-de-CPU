"""
tests/test_simulator.py — Testes do simulador EduRISC-32v2

Cobre:
  - Instruções aritméticas básicas
  - LB/LBU/LH/LHU: sign/zero-extension correta
  - SB/SH: mascaramento parcial de bytes/halfwords
  - MFC/MTC: banco de 32 CSRs
  - SP (R30): inicialização em SP_INIT
  - Branches e saltos
  - Forwarding e stalls (load-use hazard)
"""

import pytest
from assembler.assembler import Assembler
from simulator.cpu_simulator import CPUSimulator

WORD_MASK = 0xFFFFFFFF


def run(code: str, preload: dict = None, max_cycles: int = 300) -> CPUSimulator:
    """Monta e executa um programa. Retorna o simulador após execução."""
    words = Assembler().assemble(code)
    sim   = CPUSimulator()
    sim.load_program(words)
    if preload:
        for addr, val in preload.items():
            sim.mem[addr] = val & WORD_MASK
    sim.run(max_cycles=max_cycles)
    return sim


# ---------------------------------------------------------------------------
# Aritmética básica
# ---------------------------------------------------------------------------

def test_movi_add():
    sim = run("""
        .org 0x0
        MOVI R1, 10
        MOVI R2, 32
        ADD  R3, R1, R2
        HLT
    """)
    assert sim.rf[3] == 42


def test_sub():
    sim = run("""
        .org 0x0
        MOVI R1, 100
        MOVI R2, 37
        SUB  R3, R1, R2
        HLT
    """)
    assert sim.rf[3] == 63


def test_mul():
    sim = run("""
        .org 0x0
        MOVI R1, 7
        MOVI R2, 6
        MUL  R3, R1, R2
        HLT
    """)
    assert sim.rf[3] == 42


def test_addi_negative():
    sim = run("""
        .org 0x0
        MOVI R1, 10
        ADDI R1, R1, -3
        HLT
    """)
    assert sim.rf[1] == 7


# ---------------------------------------------------------------------------
# Loads: LB, LBU, LH, LHU, LW
# ---------------------------------------------------------------------------

def test_lw():
    sim = run("""
        .org 0x0
        MOVI R1, 0x100
        LW   R2, 0(R1)
        HLT
    """, preload={0x100: 0xDEADBEEF})
    assert sim.rf[2] == 0xDEADBEEF


def test_lb_sign_extension_positive():
    """LB de valor positivo (bit 7 = 0) não deve sign-extend."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x200
        MOVI R2, 0x7F
        SB   R2, 0(R1)
        LB   R3, 0(R1)
        HLT
    """)
    assert sim.rf[3] == 0x7F


def test_lb_sign_extension_negative():
    """LB de 0xFF deve retornar -1 (0xFFFFFFFF)."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x200
        MOVI R2, 0xFF
        SB   R2, 0(R1)
        LB   R3, 0(R1)
        HLT
    """)
    assert sim.rf[3] == 0xFFFFFFFF


def test_lbu_no_sign_extension():
    """LBU de 0xFF deve retornar 255 (sem sign-extension)."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x200
        MOVI R2, 0xFF
        SB   R2, 0(R1)
        LBU  R3, 0(R1)
        HLT
    """)
    assert sim.rf[3] == 255


def test_lh_sign_extension():
    """LH de 0x8000 deve retornar 0xFFFF8000."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x200
        MOVI R2, 0x8000
        SH   R2, 0(R1)
        LH   R3, 0(R1)
        HLT
    """)
    assert sim.rf[3] == 0xFFFF8000


def test_lhu_no_sign_extension():
    """LHU de 0x8000 deve retornar 0x8000."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x200
        MOVI R2, 0x8000
        SH   R2, 0(R1)
        LHU  R3, 0(R1)
        HLT
    """)
    assert sim.rf[3] == 0x8000


# ---------------------------------------------------------------------------
# Stores: SB, SH — mascaramento parcial
# ---------------------------------------------------------------------------

def test_sb_preserves_other_bytes():
    """SB deve sobrescrever apenas o byte da posição, preservando os outros."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x300
        MOVI R2, 0xAB
        SB   R2, 0(R1)
        LW   R3, 0(R1)
        HLT
    """, preload={0x300: 0x11223344})
    # Byte 0 sobrescrito com 0xAB; bytes 1,2,3 preservados
    assert sim.rf[3] == 0x112233AB


def test_sh_preserves_upper_halfword():
    """SH deve sobrescrever apenas os 16 bits inferiores."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x300
        MOVI R2, 0x1234
        SH   R2, 0(R1)
        LW   R3, 0(R1)
        HLT
    """, preload={0x300: 0xDEADBEEF})
    # Halfword 0 (bits 15:0) = 0x1234; halfword 1 (bits 31:16) = 0xDEAD
    assert sim.rf[3] == 0xDEAD1234


def test_sw_full_word():
    """SW deve sobrescrever a word inteira."""
    sim = run("""
        .org 0x0
        MOVI R1, 0x300
        MOVI R2, 0x5A5A
        SW   R2, 0(R1)
        LW   R3, 0(R1)
        HLT
    """, preload={0x300: 0xFFFFFFFF})
    assert sim.rf[3] == 0x5A5A


# ---------------------------------------------------------------------------
# CSRs: MFC / MTC
# ---------------------------------------------------------------------------

def test_mtc_mfc_round_trip():
    """MTC escreve no CSR; MFC lê de volta o mesmo valor."""
    sim = run("""
        .org 0x0
        MOVI R1, 999
        MTC  0, R1
        MFC  R2, 0
        HLT
    """)
    assert sim.rf[2] == 999


def test_mtc_mfc_different_csrs():
    """Dois CSRs distintos são independentes."""
    sim = run("""
        .org 0x0
        MOVI R1, 111
        MOVI R2, 222
        MTC  1, R1
        MTC  2, R2
        MFC  R3, 1
        MFC  R4, 2
        HLT
    """)
    assert sim.rf[3] == 111
    assert sim.rf[4] == 222


# ---------------------------------------------------------------------------
# SP (R30) inicialização
# ---------------------------------------------------------------------------

def test_sp_init():
    """SP deve ser inicializado em 0x010000 ao criar o simulador."""
    sim = CPUSimulator()
    assert sim.rf[30] == 0x010000


def test_sp_reset():
    """reset() deve restaurar SP para 0x010000."""
    sim = CPUSimulator()
    sim.rf[30] = 0x0  # modifica manualmente
    sim.reset()
    assert sim.rf[30] == 0x010000


# ---------------------------------------------------------------------------
# Branches e saltos
# ---------------------------------------------------------------------------

def test_beq_taken():
    sim = run("""
        .org 0x0
        MOVI R1, 5
        MOVI R2, 5
        BEQ  R1, R2, DONE
        MOVI R3, 99    ; não deve executar
DONE:
        HLT
    """)
    assert sim.rf[3] == 0   # não executou MOVI R3, 99


def test_bne_not_taken():
    sim = run("""
        .org 0x0
        MOVI R1, 3
        MOVI R2, 7
        BEQ  R1, R2, SKIP  ; não deve pular
        MOVI R3, 42
SKIP:
        HLT
    """)
    assert sim.rf[3] == 42


def test_jmp_unconditional():
    sim = run("""
        .org 0x0
        JMP  TARGET
        MOVI R1, 11    ; não deve executar
TARGET:
        MOVI R1, 42
        HLT
    """)
    assert sim.rf[1] == 42


# ---------------------------------------------------------------------------
# Demo principal (regressão)
# ---------------------------------------------------------------------------

def test_demo_soma_1_a_5():
    """Verifica a demo principal: soma de 1 a 5 = 15."""
    sim = run("""
        .org 0x000000
        MOVI  R1, 5
        MOVI  R2, 0
LOOP:
        ADD   R2, R2, R1
        ADDI  R1, R1, -1
        BNE   R1, R0, LOOP
        HLT
    """)
    assert sim.rf[2] == 15


# ---------------------------------------------------------------------------
# ERET — retorno de exceção via CSR_EPC
# ---------------------------------------------------------------------------

def test_eret_restores_pc():
    """SYSCALL salva PC em CSR[0]; ERET restaura PC a partir de CSR[0]."""
    from assembler.assembler import Assembler
    from simulator.cpu_simulator import CPUSimulator
    from cpu.instruction_set import Opcode

    # MTC CSR[0] = endereço alvo (0x5) manualmente, depois ERET
    # Instruções:
    #   0: MOVI R1, 5         → R1 = 5 (endereço de retorno)
    #   1: MTC CSR[0], R1     → CSR[0] = 5 (sintaxe: MTC csr_idx, rs1)
    #   2: ERET               → PC deve ir para 5
    #   3: MOVI R2, 99        → NÃO deve executar (será pulado)
    #   4: MOVI R2, 99        → NÃO deve executar
    #   5: MOVI R3, 42        → deve executar
    #   6: HLT
    src = """
        .org 0x000000
        MOVI R1, 5
        MTC  0, R1
        ERET
        MOVI R2, 99
        MOVI R2, 99
        MOVI R3, 42
        HLT
    """
    words = Assembler().assemble(src)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run(max_cycles=200)
    assert sim.rf[2] == 0, "R2 não deveria ter sido tocado"
    assert sim.rf[3] == 42, f"R3 esperado 42, obteve {sim.rf[3]}"
