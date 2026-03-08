"""
instruction_set.py — Definição completa da ISA EduRISC-32v2

Arquitetura de 32 bits com 32 registradores de uso geral (R0-R31).
Instrução de largura fixa de 32 bits com 6 formatos.

Formatos de instrução:
  R:  [31:26]=op  [25:21]=rd  [20:16]=rs1  [15:11]=rs2  [10:6]=shamt  [5:0]=funct
  I:  [31:26]=op  [25:21]=rd  [20:16]=rs1  [15:0]=imm16
  S:  [31:26]=op  [25:21]=rs2 [20:16]=rs1  [15:0]=off16  (store)
  B:  [31:26]=op  [25:21]=rs1 [20:16]=rs2  [15:0]=off16  (branch PC-relative)
  J:  [31:26]=op  [25:0]=addr26
  U:  [31:26]=op  [25:21]=rd  [20:0]=imm21  (upper-immediate)

Espaço de endereçamento PC: 26 bits → 64 M words = 256 MB
Registradores especiais: R0=zero, R30=SP, R31=LR
"""

from enum import IntEnum

# ---------------------------------------------------------------------------
# Opcodes (6 bits)
# ---------------------------------------------------------------------------

class Opcode(IntEnum):
    # Aritmética
    ADD   = 0x00
    ADDI  = 0x01
    SUB   = 0x02
    MUL   = 0x03
    MULH  = 0x04
    DIV   = 0x05
    DIVU  = 0x06
    REM   = 0x07
    # Lógica
    AND   = 0x08
    ANDI  = 0x09
    OR    = 0x0A
    ORI   = 0x0B
    XOR   = 0x0C
    XORI  = 0x0D
    NOT   = 0x0E
    NEG   = 0x0F
    # Deslocamentos
    SHL   = 0x10
    SHR   = 0x11
    SHRA  = 0x12
    SHLI  = 0x13
    SHRI  = 0x14
    SHRAI = 0x15
    # Movimentação / comparação
    MOV   = 0x16
    MOVI  = 0x17
    MOVHI = 0x18
    SLT   = 0x19
    SLTU  = 0x1A
    SLTI  = 0x1B
    # Loads
    LW    = 0x1C
    LH    = 0x1D
    LHU   = 0x1E
    LB    = 0x1F
    LBU   = 0x20
    # Stores
    SW    = 0x21
    SH    = 0x22
    SB    = 0x23
    # Branches
    BEQ   = 0x24
    BNE   = 0x25
    BLT   = 0x26
    BGE   = 0x27
    BLTU  = 0x28
    BGEU  = 0x29
    # Saltos
    JMP   = 0x2A
    JMPR  = 0x2B
    CALL  = 0x2C
    CALLR = 0x2D
    RET   = 0x2E
    PUSH  = 0x2F
    POP   = 0x30
    # Sistema
    NOP     = 0x31
    HLT     = 0x32
    SYSCALL = 0x33
    ERET    = 0x34
    MFC     = 0x35
    MTC     = 0x36
    FENCE   = 0x37
    BREAK   = 0x38


# ---------------------------------------------------------------------------
# Tipos / Formatos
# ---------------------------------------------------------------------------

class InstFmt(IntEnum):
    R = 0   # registrador-registrador
    I = 1   # imediato 16 bits
    S = 2   # store (rs2, rs1, off16)
    B = 3   # branch (rs1, rs2, off16)
    J = 4   # jump absoluto 26 bits
    U = 5   # upper-immediate 21 bits


# Mapeamento opcode → formato
OPCODE_FMT: dict[Opcode, InstFmt] = {
    Opcode.ADD:    InstFmt.R,
    Opcode.ADDI:   InstFmt.I,
    Opcode.SUB:    InstFmt.R,
    Opcode.MUL:    InstFmt.R,
    Opcode.MULH:   InstFmt.R,
    Opcode.DIV:    InstFmt.R,
    Opcode.DIVU:   InstFmt.R,
    Opcode.REM:    InstFmt.R,
    Opcode.AND:    InstFmt.R,
    Opcode.ANDI:   InstFmt.I,
    Opcode.OR:     InstFmt.R,
    Opcode.ORI:    InstFmt.I,
    Opcode.XOR:    InstFmt.R,
    Opcode.XORI:   InstFmt.I,
    Opcode.NOT:    InstFmt.R,
    Opcode.NEG:    InstFmt.R,
    Opcode.SHL:    InstFmt.R,
    Opcode.SHR:    InstFmt.R,
    Opcode.SHRA:   InstFmt.R,
    Opcode.SHLI:   InstFmt.R,  # usa campo shamt
    Opcode.SHRI:   InstFmt.R,
    Opcode.SHRAI:  InstFmt.R,
    Opcode.MOV:    InstFmt.R,
    Opcode.MOVI:   InstFmt.I,
    Opcode.MOVHI:  InstFmt.U,
    Opcode.SLT:    InstFmt.R,
    Opcode.SLTU:   InstFmt.R,
    Opcode.SLTI:   InstFmt.I,
    Opcode.LW:     InstFmt.I,
    Opcode.LH:     InstFmt.I,
    Opcode.LHU:    InstFmt.I,
    Opcode.LB:     InstFmt.I,
    Opcode.LBU:    InstFmt.I,
    Opcode.SW:     InstFmt.S,
    Opcode.SH:     InstFmt.S,
    Opcode.SB:     InstFmt.S,
    Opcode.BEQ:    InstFmt.B,
    Opcode.BNE:    InstFmt.B,
    Opcode.BLT:    InstFmt.B,
    Opcode.BGE:    InstFmt.B,
    Opcode.BLTU:   InstFmt.B,
    Opcode.BGEU:   InstFmt.B,
    Opcode.JMP:    InstFmt.J,
    Opcode.JMPR:   InstFmt.I,
    Opcode.CALL:   InstFmt.J,
    Opcode.CALLR:  InstFmt.I,
    Opcode.RET:    InstFmt.J,
    Opcode.PUSH:   InstFmt.R,
    Opcode.POP:    InstFmt.R,
    Opcode.NOP:    InstFmt.J,
    Opcode.HLT:    InstFmt.J,
    Opcode.SYSCALL:InstFmt.J,
    Opcode.ERET:   InstFmt.J,
    Opcode.MFC:    InstFmt.I,
    Opcode.MTC:    InstFmt.I,
    Opcode.FENCE:  InstFmt.J,
    Opcode.BREAK:  InstFmt.J,
}

MNEMONIC_TO_OPCODE: dict[str, Opcode] = {op.name: op for op in Opcode}

# Aliases convencionais
MNEMONIC_TO_OPCODE["SLLI"] = Opcode.SHLI
MNEMONIC_TO_OPCODE["SRLI"] = Opcode.SHRI
MNEMONIC_TO_OPCODE["SRAI"] = Opcode.SHRAI

# Constantes
NUM_REGISTERS = 32
WORD_BITS     = 32
WORD_MASK     = (1 << WORD_BITS) - 1
PC_BITS       = 26
PC_MASK       = (1 << PC_BITS) - 1
MEM_SIZE      = 1 << PC_BITS   # 64 M words
ZERO_REG      = 0              # R0 = hardwired 0
SP_REG        = 30             # R30 = stack pointer
LR_REG        = 31             # R31 = link register


# ---------------------------------------------------------------------------
# Helpers de sinal-extensão
# ---------------------------------------------------------------------------

def _sext(value: int, bits: int) -> int:
    """Sign-extends `value` from `bits`-wide to Python int."""
    mask = (1 << bits) - 1
    value &= mask
    if value & (1 << (bits - 1)):
        value -= (1 << bits)
    return value


# ---------------------------------------------------------------------------
# Codificação
# ---------------------------------------------------------------------------

def encode_r(opcode: Opcode, rd: int, rs1: int, rs2: int = 0, shamt: int = 0) -> int:
    """Codifica instrução Formato-R em 32 bits."""
    return (
        ((int(opcode) & 0x3F) << 26)
        | ((rd    & 0x1F) << 21)
        | ((rs1   & 0x1F) << 16)
        | ((rs2   & 0x1F) << 11)
        | ((shamt & 0x1F) << 6)
    )


def encode_i(opcode: Opcode, rd: int, rs1: int, imm: int) -> int:
    """Codifica instrução Formato-I em 32 bits."""
    return (
        ((int(opcode) & 0x3F) << 26)
        | ((rd  & 0x1F) << 21)
        | ((rs1 & 0x1F) << 16)
        | (imm  & 0xFFFF)
    )


def encode_s(opcode: Opcode, rs2: int, rs1: int, off: int) -> int:
    """Codifica instrução Formato-S (store) em 32 bits."""
    return (
        ((int(opcode) & 0x3F) << 26)
        | ((rs2 & 0x1F) << 21)
        | ((rs1 & 0x1F) << 16)
        | (off  & 0xFFFF)
    )


def encode_b(opcode: Opcode, rs1: int, rs2: int, off: int) -> int:
    """Codifica instrução Formato-B (branch) em 32 bits."""
    return (
        ((int(opcode) & 0x3F) << 26)
        | ((rs1 & 0x1F) << 21)
        | ((rs2 & 0x1F) << 16)
        | (off  & 0xFFFF)
    )


def encode_j(opcode: Opcode, addr: int = 0) -> int:
    """Codifica instrução Formato-J em 32 bits."""
    return ((int(opcode) & 0x3F) << 26) | (addr & 0x3FFFFFF)


def encode_u(opcode: Opcode, rd: int, imm21: int) -> int:
    """Codifica instrução Formato-U (MOVHI) em 32 bits."""
    return (
        ((int(opcode) & 0x3F) << 26)
        | ((rd & 0x1F) << 21)
        | (imm21 & 0x1FFFFF)
    )


# ---------------------------------------------------------------------------
# Decodificação
# ---------------------------------------------------------------------------

def decode(word: int) -> dict:
    """Decodifica palavra de 32 bits em dicionário de campos."""
    op_code = (word >> 26) & 0x3F
    try:
        opcode = Opcode(op_code)
    except ValueError:
        return {"opcode": None, "raw": op_code, "word": word}

    fmt = OPCODE_FMT.get(opcode, InstFmt.J)

    if fmt == InstFmt.R:
        return {
            "opcode": opcode, "fmt": fmt,
            "rd":    (word >> 21) & 0x1F,
            "rs1":   (word >> 16) & 0x1F,
            "rs2":   (word >> 11) & 0x1F,
            "shamt": (word >>  6) & 0x1F,
        }
    elif fmt == InstFmt.I:
        return {
            "opcode": opcode, "fmt": fmt,
            "rd":  (word >> 21) & 0x1F,
            "rs1": (word >> 16) & 0x1F,
            "imm": _sext(word & 0xFFFF, 16),
        }
    elif fmt == InstFmt.S:
        return {
            "opcode": opcode, "fmt": fmt,
            "rs2": (word >> 21) & 0x1F,
            "rs1": (word >> 16) & 0x1F,
            "off": _sext(word & 0xFFFF, 16),
        }
    elif fmt == InstFmt.B:
        return {
            "opcode": opcode, "fmt": fmt,
            "rs1": (word >> 21) & 0x1F,
            "rs2": (word >> 16) & 0x1F,
            "off": _sext(word & 0xFFFF, 16),
        }
    elif fmt == InstFmt.U:
        return {
            "opcode": opcode, "fmt": fmt,
            "rd":    (word >> 21) & 0x1F,
            "imm21": word & 0x1FFFFF,
        }
    else:  # J
        return {
            "opcode": opcode, "fmt": fmt,
            "addr": word & 0x3FFFFFF,
        }


# ---------------------------------------------------------------------------
# Disassembly
# ---------------------------------------------------------------------------

_REG_ALIAS = {30: "sp", 31: "lr"}

def _reg(n: int) -> str:
    return _REG_ALIAS.get(n, f"R{n}")


def disassemble(word: int) -> str:
    """Retorna string de disassembly legível para uma instrução de 32 bits."""
    d = decode(word)
    if d.get("opcode") is None:
        return f".word 0x{word:08X}"

    op  = d["opcode"].name
    fmt = d["fmt"]

    if fmt == InstFmt.R:
        rd, rs1, rs2 = _reg(d["rd"]), _reg(d["rs1"]), _reg(d["rs2"])
        if d["opcode"] in (Opcode.NOT, Opcode.NEG):
            return f"{op} {rd}, {rs1}"
        if d["opcode"] in (Opcode.SHLI, Opcode.SHRI, Opcode.SHRAI):
            return f"{op} {rd}, {rs1}, {d['shamt']}"
        if d["opcode"] == Opcode.MOV:
            return f"MOV {rd}, {rs1}"
        if d["opcode"] == Opcode.PUSH:
            return f"PUSH {rs1}"
        if d["opcode"] == Opcode.POP:
            return f"POP {rd}"
        return f"{op} {rd}, {rs1}, {rs2}"

    elif fmt == InstFmt.I:
        rd, rs1, imm = _reg(d["rd"]), _reg(d["rs1"]), d["imm"]
        if d["opcode"] in (Opcode.LW, Opcode.LH, Opcode.LHU, Opcode.LB, Opcode.LBU):
            return f"{op} {rd}, {imm}({rs1})"
        if d["opcode"] in (Opcode.JMPR, Opcode.CALLR):
            return f"{op} {rs1}"
        if d["opcode"] in (Opcode.MFC, Opcode.MTC):
            csr_idx = imm & 0x1F
            if d["opcode"] == Opcode.MFC:
                return f"MFC {rd}, CSR[{csr_idx}]"
            else:
                return f"MTC CSR[{csr_idx}], {rs1}"
        return f"{op} {rd}, {rs1}, {imm}"

    elif fmt == InstFmt.S:
        rs2, rs1, off = _reg(d["rs2"]), _reg(d["rs1"]), d["off"]
        return f"{op} {rs2}, {off}({rs1})"

    elif fmt == InstFmt.B:
        rs1, rs2, off = _reg(d["rs1"]), _reg(d["rs2"]), d["off"]
        return f"{op} {rs1}, {rs2}, {off:+d}"

    elif fmt == InstFmt.U:
        return f"MOVHI {_reg(d['rd'])}, 0x{d['imm21']:05X}"

    else:  # J
        if d["opcode"] in (Opcode.NOP, Opcode.HLT, Opcode.SYSCALL, Opcode.ERET,
                           Opcode.FENCE, Opcode.BREAK, Opcode.RET):
            return op
        return f"{op} 0x{d['addr']:07X}"
