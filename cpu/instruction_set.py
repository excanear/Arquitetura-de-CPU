"""
instruction_set.py — Definição completa da ISA EduRISC-16

Arquitetura de 16 bits com 16 registradores de uso geral (R0-R15).
Instrução de largura fixa de 16 bits.

Formato das instruções:
  Tipo-R  [15:12]=opcode  [11:8]=rd  [7:4]=rs1  [3:0]=rs2
  Tipo-I  [15:12]=opcode  [11:8]=rd  [7:0]=imm8
  Tipo-J  [15:12]=opcode  [11:0]=addr12
  Tipo-M  [15:12]=opcode  [11:8]=rd  [7:4]=base  [3:0]=offset4

Espaço de endereçamento: 65536 palavras de 16 bits (128 KB)
"""

from enum import IntEnum

# ---------------------------------------------------------------------------
# Opcodes (4 bits → 16 operações)
# ---------------------------------------------------------------------------
class Opcode(IntEnum):
    ADD   = 0x0   # R-type: rd = rs1 + rs2
    SUB   = 0x1   # R-type: rd = rs1 - rs2
    MUL   = 0x2   # R-type: rd = rs1 * rs2  (16 bits inferiores)
    DIV   = 0x3   # R-type: rd = rs1 / rs2  (inteiro sem sinal)
    AND   = 0x4   # R-type: rd = rs1 & rs2
    OR    = 0x5   # R-type: rd = rs1 | rs2
    XOR   = 0x6   # R-type: rd = rs1 ^ rs2
    NOT   = 0x7   # R-type: rd = ~rs1   (rs2 ignorado)
    LOAD  = 0x8   # M-type: rd = MEM[base + offset4]
    STORE = 0x9   # M-type: MEM[base + offset4] = rd
    JMP   = 0xA   # J-type: PC = addr12
    JZ    = 0xB   # J-type: if ZERO: PC = addr12
    JNZ   = 0xC   # J-type: if !ZERO: PC = addr12
    CALL  = 0xD   # J-type: R15=PC+1; PC = addr12  (R15 = link register)
    RET   = 0xE   # R-type: PC = R15
    HLT   = 0xF   # R-type: para execução

# ---------------------------------------------------------------------------
# Tipo de instrução
# ---------------------------------------------------------------------------
class InstType(IntEnum):
    R = 0   # registrador-registrador
    I = 1   # imediato
    J = 2   # jump / endereço 12-bit
    M = 3   # memória (base+offset)

# Mapeamento opcode → tipo
OPCODE_TYPE: dict[Opcode, InstType] = {
    Opcode.ADD:   InstType.R,
    Opcode.SUB:   InstType.R,
    Opcode.MUL:   InstType.R,
    Opcode.DIV:   InstType.R,
    Opcode.AND:   InstType.R,
    Opcode.OR:    InstType.R,
    Opcode.XOR:   InstType.R,
    Opcode.NOT:   InstType.R,
    Opcode.LOAD:  InstType.M,
    Opcode.STORE: InstType.M,
    Opcode.JMP:   InstType.J,
    Opcode.JZ:    InstType.J,
    Opcode.JNZ:   InstType.J,
    Opcode.CALL:  InstType.J,
    Opcode.RET:   InstType.R,
    Opcode.HLT:   InstType.R,
}

# Mnemônico → opcode
MNEMONIC_TO_OPCODE: dict[str, Opcode] = {op.name: op for op in Opcode}

NUM_REGISTERS = 16
WORD_BITS     = 16
WORD_MASK     = (1 << WORD_BITS) - 1      # 0xFFFF
MEM_SIZE      = 1 << 16                   # 65536 palavras
LINK_REG      = 15                         # R15 = link register para CALL/RET

# ---------------------------------------------------------------------------
# Codificação / Decodificação
# ---------------------------------------------------------------------------

def encode_r(opcode: Opcode, rd: int, rs1: int, rs2: int = 0) -> int:
    """Codifica instrução Tipo-R em 16 bits."""
    return ((int(opcode) & 0xF) << 12) | ((rd & 0xF) << 8) | ((rs1 & 0xF) << 4) | (rs2 & 0xF)

def encode_m(opcode: Opcode, rd: int, base: int, offset: int) -> int:
    """Codifica instrução Tipo-M em 16 bits."""
    return ((int(opcode) & 0xF) << 12) | ((rd & 0xF) << 8) | ((base & 0xF) << 4) | (offset & 0xF)

def encode_j(opcode: Opcode, addr: int) -> int:
    """Codifica instrução Tipo-J em 16 bits."""
    return ((int(opcode) & 0xF) << 12) | (addr & 0xFFF)

def decode(word: int) -> dict:
    """Decodifica palavra de 16 bits em dicionário de campos."""
    opcode = Opcode((word >> 12) & 0xF)
    itype  = OPCODE_TYPE[opcode]
    if itype == InstType.J:
        return {"opcode": opcode, "type": itype, "addr": word & 0xFFF}
    elif itype == InstType.M:
        return {
            "opcode": opcode, "type": itype,
            "rd":     (word >> 8) & 0xF,
            "base":   (word >> 4) & 0xF,
            "offset": word & 0xF,
        }
    else:  # R / I
        return {
            "opcode": opcode, "type": itype,
            "rd":  (word >> 8) & 0xF,
            "rs1": (word >> 4) & 0xF,
            "rs2": word & 0xF,
        }

def disassemble(word: int) -> str:
    """Retorna string de disassembly legível para uma instrução."""
    d = decode(word)
    op = d["opcode"].name
    if d["type"] == InstType.J:
        return f"{op} 0x{d['addr']:03X}"
    elif d["type"] == InstType.M:
        if d["opcode"] == Opcode.LOAD:
            return f"LOAD R{d['rd']}, [R{d['base']}+{d['offset']}]"
        else:
            return f"STORE R{d['rd']}, [R{d['base']}+{d['offset']}]"
    else:
        if d["opcode"] == Opcode.NOT:
            return f"NOT R{d['rd']}, R{d['rs1']}"
        elif d["opcode"] == Opcode.RET:
            return "RET"
        elif d["opcode"] == Opcode.HLT:
            return "HLT"
        else:
            return f"{op} R{d['rd']}, R{d['rs1']}, R{d['rs2']}"
