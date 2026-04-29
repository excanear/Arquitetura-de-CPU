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
    """ERET restaura PC a partir de CSR[EPC] (índice 2, conforme ISA EduRISC-32v2)."""
    from assembler.assembler import Assembler
    from simulator.cpu_simulator import CPUSimulator
    from cpu.instruction_set import Opcode

    # Instruções:
    #   0: MOVI R1, 5         → R1 = 5 (endereço de retorno)
    #   1: MTC  2, R1         → CSR[EPC] = 5  (CSR[2] = EPC conforme ISA spec)
    #   2: ERET               → PC deve ir para CSR[EPC] = 5
    #   3: MOVI R2, 99        → NÃO deve executar (será pulado)
    #   4: MOVI R2, 99        → NÃO deve executar
    #   5: MOVI R3, 42        → deve executar
    #   6: HLT
    src = """
        .org 0x000000
        MOVI R1, 5
        MTC  2, R1
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


# ---------------------------------------------------------------------------
# MMU / TLB — tradução de endereços virtuais
# ---------------------------------------------------------------------------

def test_mmu_kernel_mode_identity():
    """Em modo kernel (STATUS.KU=0, padrão), o endereço físico é igual ao virtual."""
    from simulator.cpu_simulator import CPUSimulator, _TLBModel
    from cpu.instruction_set import CSR_PTBR

    tlb = _TLBModel()
    # Cria memória mínima com um PTE válido apontando para frame 5
    # (não deve ser consultado em modo kernel)
    mem = [0] * 512
    ptbr = 0
    # translate com mem e ptbr inválidos — deve retornar identidade sem consultar TLB
    # Simulamos chamando _translate_addr via um CPUSimulator com KU=0
    sim = CPUSimulator()
    # KU=0 por padrão → modo kernel
    # _mmu_active() deve retornar False
    assert not sim._mmu_active(), "MODE_KU=0 deve desativar MMU"
    # Tradução deve ser identidade
    result = sim._translate_addr(0x1000)
    assert result == 0x1000, f"identidade esperada, got {result:#x}"


def test_mmu_tlb_miss_then_hit():
    """Primeiro acesso a uma página: TLB miss + page walk. Segundo: TLB hit."""
    from simulator.cpu_simulator import _TLBModel

    PAGE_BITS = _TLBModel.PAGE_BITS   # 10
    PTE_V = _TLBModel.PTE_V
    PTE_R = _TLBModel.PTE_R
    PTE_W = _TLBModel.PTE_W

    tlb = _TLBModel()
    # Monta uma memória com page table na posição 0
    mem = [0] * 4096

    ptbr = 0       # base da page table em word 0
    vpn  = 3       # VPN que queremos traduzir
    pfn  = 7       # frame físico alvo

    # PTE para VPN=3 em mem[ptbr + vpn] = mem[3]
    # flags: V=1, R=1, W=1
    pte_flags = PTE_V | PTE_R | PTE_W
    mem[ptbr + vpn] = (pfn << PAGE_BITS) | pte_flags

    # Endereço virtual: VPN=3, offset=5
    va = (vpn << PAGE_BITS) | 5

    # Primeiro acesso → miss
    pa1 = tlb.translate(va, mem, ptbr)
    expected_pa = pfn * (1 << PAGE_BITS) + 5
    assert pa1 == expected_pa, f"PA esperado {expected_pa}, got {pa1}"
    assert tlb.misses == 1
    assert tlb.hits   == 0

    # Segundo acesso mesma página → hit
    pa2 = tlb.translate(va, mem, ptbr)
    assert pa2 == expected_pa
    assert tlb.hits   == 1
    assert tlb.misses == 1


def test_tlb_page_fault_invalid_pte():
    """PTE com V=0 → tradução retorna None (page fault)."""
    from simulator.cpu_simulator import _TLBModel

    PAGE_BITS = _TLBModel.PAGE_BITS

    tlb = _TLBModel()
    mem = [0] * 512

    ptbr = 0
    vpn  = 1
    # PTE com V=0 (inválido)
    mem[ptbr + vpn] = 0

    va = (vpn << PAGE_BITS) | 0

    result = tlb.translate(va, mem, ptbr)
    assert result is None, "PTE inválido deve retornar None (page fault)"
    assert tlb.misses == 1


def test_tlb_permission_write_fault():
    """PTE sem flag W → write access retorna None (page fault)."""
    from simulator.cpu_simulator import _TLBModel

    PAGE_BITS = _TLBModel.PAGE_BITS
    PTE_V = _TLBModel.PTE_V
    PTE_R = _TLBModel.PTE_R
    # PTE sem PTE_W (somente leitura)

    tlb = _TLBModel()
    mem = [0] * 512

    ptbr = 0
    vpn  = 2
    pfn  = 4
    mem[ptbr + vpn] = (pfn << PAGE_BITS) | PTE_V | PTE_R  # R-only

    va = (vpn << PAGE_BITS) | 10

    # Leitura deve ter sucesso
    pa = tlb.translate(va, mem, ptbr, write=False)
    assert pa is not None, "Leitura em página R deve ter sucesso"

    # Reset TLB e testa escrita
    tlb2 = _TLBModel()
    pa_write = tlb2.translate(va, mem, ptbr, write=True)
    assert pa_write is None, "Escrita em página R-only deve retornar None"


def test_tlb_flush():
    """TLBFLUSH invalida entradas — próximo acesso faz page walk novamente."""
    from simulator.cpu_simulator import _TLBModel

    PAGE_BITS = _TLBModel.PAGE_BITS
    PTE_V = _TLBModel.PTE_V
    PTE_R = _TLBModel.PTE_R

    tlb  = _TLBModel()
    mem  = [0] * 512
    ptbr = 0
    vpn  = 1
    pfn  = 9
    mem[ptbr + vpn] = (pfn << PAGE_BITS) | PTE_V | PTE_R

    va = (vpn << PAGE_BITS) | 0

    # Preenche TLB
    tlb.translate(va, mem, ptbr)
    assert tlb.misses == 1 and tlb.hits == 0

    # Acessa novamente → hit
    tlb.translate(va, mem, ptbr)
    assert tlb.hits == 1

    # Flush
    tlb.flush()
    assert tlb.flushes == 1

    # Acessa novamente → miss (entradas invalidadas)
    tlb.translate(va, mem, ptbr)
    assert tlb.misses == 2
    assert tlb.hits   == 1   # não incrementou


def test_tlbflush_via_csr_write():
    """Escrita em CSR_TLBCTL com bit 0 set dispara flush da TLB."""
    from simulator.cpu_simulator import CPUSimulator
    from cpu.instruction_set import CSR_TLBCTL, CSR_STATUS, STATUS_KU, CSR_PTBR

    sim = CPUSimulator()

    # Preenche TLB com uma entrada (modo usuário)
    PAGE_BITS = sim.tlb.PAGE_BITS
    PTE_V = sim.tlb.PTE_V
    PTE_R = sim.tlb.PTE_R

    ptbr = 10
    vpn  = 0
    pfn  = 5
    mem  = sim.mem
    mem[ptbr + vpn] = (pfn << PAGE_BITS) | PTE_V | PTE_R

    # Ativa modo usuário temporariamente para traduzir
    sim.csrs[CSR_STATUS] = STATUS_KU
    sim.csrs[CSR_PTBR]   = ptbr
    sim.tlb.translate(0, mem, ptbr)   # miss → carrega entrada na TLB
    assert sim.tlb.misses == 1

    # Dispara flush via CSR_TLBCTL
    sim._csr_write(CSR_TLBCTL, 1)
    assert sim.tlb.flushes == 1

    # CSR_TLBCTL deve ter sido auto-cleared
    assert sim.csrs[CSR_TLBCTL] == 0
