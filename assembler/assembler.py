"""
assembler.py — Assembler de dois passos para EduRISC-32v2

Passo 1 — Varredura de labels:
  Percorre todas as linhas e registra o endereço word de cada label.

Passo 2 — Geração de código:
  Traduz cada instrução para uma palavra de 32 bits usando a ISA.

Saída:
  lista de int (palavras de 32 bits)  → gravada como .bin ou Intel HEX

Diretivas suportadas:
  .org  addr    — posiciona contador de localização (endereços word)
  .word val     — insere palavra literal de 32 bits
  .data v1,...  — insere múltiplos words
  .equ  name, val — define constante simbólica

Sintaxe de registradores:
  R0–R31  (também: zero=R0, sp=R30, lr=R31)

Sintaxe de instruções:
  R-type:  ADD   rd, rs1, rs2
  I-type:  ADDI  rd, rs1, imm
  S-type:  SW    rs2, off(rs1)    (store)
  B-type:  BEQ   rs1, rs2, target (branch PC-relative label ou offset)
  J-type:  JMP   addr             (absoluto ou label)
  U-type:  MOVHI rd, imm21
  Especiais: NOP / HLT / RET / ERET / SYSCALL / FENCE / BREAK
             PUSH rs1
             POP  rd
             MFC  rd, csr_idx
             MTC  csr_idx, rs1
"""

import re
import struct
from pathlib import Path

from cpu.instruction_set import (
    Opcode, InstFmt, OPCODE_FMT, MNEMONIC_TO_OPCODE,
    encode_r, encode_i, encode_s, encode_b, encode_j, encode_u,
    disassemble, WORD_MASK, PC_MASK, NUM_REGISTERS,
)


# ---------------------------------------------------------------------------
# Erros
# ---------------------------------------------------------------------------

class AssemblerError(Exception):
    def __init__(self, msg: str, line: int = 0):
        super().__init__(f"[Linha {line}] Erro de montagem: {msg}")
        self.line = line


# ---------------------------------------------------------------------------
# Lexer simples
# ---------------------------------------------------------------------------

_REG_NAMES = {"zero": 0, "sp": 30, "lr": 31}

def _parse_reg(token: str, line: int) -> int:
    """Converte 'R5', 'sp', 'zero', 'lr' em índice 0-31."""
    t = token.strip().lower()
    if t in _REG_NAMES:
        return _REG_NAMES[t]
    m = re.fullmatch(r"r(\d+)", t)
    if m:
        n = int(m.group(1))
        if 0 <= n <= 31:
            return n
    raise AssemblerError(f"Registrador inválido: '{token}'", line)

def _parse_int(token: str, line: int) -> int:
    """Converte token numérico (decimal, 0x hex, 0b bin) em int."""
    t = token.strip().lower()
    try:
        if t.startswith("0x"):
            return int(t, 16)
        elif t.startswith("0b"):
            return int(t, 2)
        else:
            return int(t, 10)
    except ValueError:
        raise AssemblerError(f"Valor numérico inválido: '{token}'", line)


def _is_int(token: str) -> bool:
    t = token.strip().lower()
    return bool(re.fullmatch(r"-?(?:0x[0-9a-f]+|0b[01]+|\d+)", t))


def _tokenize_line(raw: str) -> list[str]:
    """Divide uma linha assembly em tokens, removendo comentários."""
    # Remove comentários (// ou ;)
    for sep in ("//", ";"):
        idx = raw.find(sep)
        if idx >= 0:
            raw = raw[:idx]
    raw = raw.strip()
    if not raw:
        return []
    # Substitui vírgulas e parênteses por espaços para facilitar split
    raw = raw.replace(",", " ")
    raw = raw.replace("(", " ")
    raw = raw.replace(")", " ")
    return raw.split()


# ---------------------------------------------------------------------------
# Assembler
# ---------------------------------------------------------------------------

class Assembler:
    """
    Assembler completo de dois passos para EduRISC-32v2.

    Uso:
        asm = Assembler()
        words = asm.assemble(source_text)
        asm.write_binary(words, "prog.bin")
        asm.write_hex(words, "prog.hex")
    """

    def __init__(self):
        self._symbols: dict[str, int] = {}
        self._origin:  int            = 0

    @property
    def symbols(self) -> dict[str, int]:
        return dict(self._symbols)

    # -----------------------------------------------------------------------
    # Interface principal
    # -----------------------------------------------------------------------

    def assemble(self, source: str) -> list[int]:
        """
        Monta source assembly; retorna lista de palavras de 32 bits.
        Levanta AssemblerError em caso de erro.
        """
        self._symbols = {}
        lines = source.splitlines()

        # Passo 1 — varredura de labels e .equ
        self._pass1(lines)

        # Passo 2 — geração de código
        return self._pass2(lines)

    def write_binary(self, words: list[int], path: str | Path):
        """Grava programa como binário big-endian (4 bytes por palavra)."""
        data = struct.pack(f">{len(words)}I", *words)
        Path(path).write_bytes(data)

    def write_hex(self, words: list[int], path: str | Path, base_addr: int = 0):
        """Grava no formato Intel HEX (endereço de byte = word_addr * 4)."""
        lines = []
        for addr, w in enumerate(words):
            byte_addr = (base_addr + addr) * 4
            b0 = (w >> 24) & 0xFF
            b1 = (w >> 16) & 0xFF
            b2 = (w >>  8) & 0xFF
            b3 =  w        & 0xFF
            # Record type 00, length 4
            rec  = f"04{byte_addr:04X}00{b0:02X}{b1:02X}{b2:02X}{b3:02X}"
            csum = (-(sum(int(rec[i:i+2], 16) for i in range(0, len(rec), 2)))) & 0xFF
            lines.append(f":{rec}{csum:02X}")
        lines.append(":00000001FF")  # EOF record
        Path(path).write_text("\n".join(lines), encoding="utf-8")

    def listing(self, words: list[int], base_addr: int = 0) -> str:
        """Gera listagem com endereço, word hex e disassembly."""
        out = ["ADDR       WORD       DISASSEMBLY"]
        for i, w in enumerate(words):
            addr = base_addr + i
            try:
                dis = disassemble(w)
            except Exception:
                dis = f".word 0x{w:08X}"
            out.append(f"0x{addr:07X}  {w:08X}   {dis}")
        return "\n".join(out)

    # -----------------------------------------------------------------------
    # Passo 1 — coleta de labels e .equ
    # -----------------------------------------------------------------------

    def _pass1(self, lines: list[str]):
        lc = 0  # location counter (word address)
        for lineno, raw in enumerate(lines, start=1):
            tokens = _tokenize_line(raw)
            if not tokens:
                continue

            # Label: token termina com ':'
            if tokens[0].endswith(":"):
                label = tokens[0][:-1]
                if label in self._symbols:
                    raise AssemblerError(f"Label duplicado: '{label}'", lineno)
                self._symbols[label] = lc
                tokens = tokens[1:]
                if not tokens:
                    continue

            if not tokens:
                continue

            directive = tokens[0].lower()

            if directive == ".org":
                if len(tokens) < 2:
                    raise AssemblerError(".org sem valor", lineno)
                lc = _parse_int(tokens[1], lineno)

            elif directive == ".equ":
                if len(tokens) < 3:
                    raise AssemblerError(".equ requer nome e valor", lineno)
                self._symbols[tokens[1]] = _parse_int(tokens[2], lineno)

            elif directive in (".word", ".data"):
                lc += len(tokens) - 1  # um word por valor

            elif not directive.startswith("."):
                # instrução: ocupa 1 word
                lc += 1

    # -----------------------------------------------------------------------
    # Passo 2 — geração de código
    # -----------------------------------------------------------------------

    def _pass2(self, lines: list[str]) -> list[int]:
        lc     = 0
        output: dict[int, int] = {}

        for lineno, raw in enumerate(lines, start=1):
            tokens = _tokenize_line(raw)
            if not tokens:
                continue

            # Consumir label
            if tokens[0].endswith(":"):
                tokens = tokens[1:]
            if not tokens:
                continue

            directive = tokens[0].lower()

            if directive == ".org":
                lc = _parse_int(tokens[1], lineno)

            elif directive == ".equ":
                pass  # já processado no passo 1

            elif directive in (".word", ".data"):
                for val_tok in tokens[1:]:
                    output[lc] = self._resolve(val_tok, lineno) & WORD_MASK
                    lc += 1

            elif not directive.startswith("."):
                # instrução
                word = self._encode_instr(tokens, lc, lineno)
                output[lc] = word & WORD_MASK
                lc += 1

        if not output:
            return []

        max_addr = max(output.keys())
        return [output.get(i, 0x00000000) for i in range(max_addr + 1)]

    # -----------------------------------------------------------------------
    # Resolução de símbolos
    # -----------------------------------------------------------------------

    def _resolve(self, token: str, line: int) -> int:
        """Resolve token como número ou símbolo."""
        if _is_int(token):
            return _parse_int(token, line)
        if token in self._symbols:
            return self._symbols[token]
        raise AssemblerError(f"Símbolo não definido: '{token}'", line)

    def _resolve_branch(self, token: str, pc: int, line: int) -> int:
        """Resolve label de branch como offset PC-relativo (palavras)."""
        target = self._resolve(token, line)
        return (target - pc) & 0xFFFF

    # -----------------------------------------------------------------------
    # Codificação de instruções
    # -----------------------------------------------------------------------

    def _encode_instr(self, tokens: list[str], pc: int, line: int) -> int:
        mnem = tokens[0].upper()
        ops  = tokens[1:]

        # Normaliza aliases
        if mnem == "SLLI":
            mnem = "SHLI"
        elif mnem == "SRLI":
            mnem = "SHRI"
        elif mnem == "SRAI":
            mnem = "SHRAI"

        if mnem not in MNEMONIC_TO_OPCODE:
            raise AssemblerError(f"Mnemônico desconhecido: '{mnem}'", line)

        opcode = MNEMONIC_TO_OPCODE[mnem]
        fmt    = OPCODE_FMT[opcode]

        # ---- Instruções sem operandos ----
        if mnem in ("NOP", "HLT", "SYSCALL", "ERET", "FENCE", "BREAK", "RET"):
            return encode_j(opcode)

        # ---- Formato R ----
        if fmt == InstFmt.R:
            if mnem in ("NOT", "NEG"):
                rd  = _parse_reg(ops[0], line)
                rs1 = _parse_reg(ops[1], line)
                return encode_r(opcode, rd, rs1)

            if mnem in ("SHLI", "SHRI", "SHRAI"):
                rd    = _parse_reg(ops[0], line)
                rs1   = _parse_reg(ops[1], line)
                shamt = _parse_int(ops[2], line) & 0x1F
                return encode_r(opcode, rd, rs1, 0, shamt)

            if mnem == "MOV":
                rd  = _parse_reg(ops[0], line)
                rs1 = _parse_reg(ops[1], line)
                return encode_r(opcode, rd, rs1)

            if mnem == "PUSH":
                rs1 = _parse_reg(ops[0], line)
                return encode_r(opcode, 0, rs1)

            if mnem == "POP":
                rd = _parse_reg(ops[0], line)
                return encode_r(opcode, rd, 0)

            # padrão R: rd, rs1, rs2
            rd  = _parse_reg(ops[0], line)
            rs1 = _parse_reg(ops[1], line)
            rs2 = _parse_reg(ops[2], line)
            return encode_r(opcode, rd, rs1, rs2)

        # ---- Formato I ----
        if fmt == InstFmt.I:
            if mnem in ("JMPR", "CALLR"):
                rs1 = _parse_reg(ops[0], line)
                return encode_i(opcode, 0, rs1, 0)

            if mnem == "MFC":
                # MFC rd, csr_idx
                rd      = _parse_reg(ops[0], line)
                csr_idx = self._resolve(ops[1], line) & 0x1F
                return encode_i(opcode, rd, 0, csr_idx)

            if mnem == "MTC":
                # MTC csr_idx, rs1
                csr_idx = self._resolve(ops[0], line) & 0x1F
                rs1     = _parse_reg(ops[1], line)
                return encode_i(opcode, 0, rs1, csr_idx)

            if mnem in ("LW", "LH", "LHU", "LB", "LBU"):
                # LW rd, off(rs1)   — ops já expandidos após tokenização
                rd  = _parse_reg(ops[0], line)
                off = self._resolve(ops[1], line) & 0xFFFF
                rs1 = _parse_reg(ops[2], line)
                return encode_i(opcode, rd, rs1, off)

            if mnem == "MOVI":
                # MOVI rd, imm16   — rs1 implícito = R0 (zero)
                rd  = _parse_reg(ops[0], line)
                imm = self._resolve(ops[1], line) & 0xFFFF
                return encode_i(opcode, rd, 0, imm)

            if mnem == "SLTI":
                # SLTI rd, rs1, imm  (signed less-than immediate)
                rd  = _parse_reg(ops[0], line)
                rs1 = _parse_reg(ops[1], line)
                imm = self._resolve(ops[2], line) & 0xFFFF
                return encode_i(opcode, rd, rs1, imm)

            # padrão I: rd, rs1, imm
            rd  = _parse_reg(ops[0], line)
            rs1 = _parse_reg(ops[1], line)
            imm = self._resolve(ops[2], line) & 0xFFFF
            return encode_i(opcode, rd, rs1, imm)

        # ---- Formato S (stores) ----
        if fmt == InstFmt.S:
            # SW rs2, off(rs1)
            rs2 = _parse_reg(ops[0], line)
            off = self._resolve(ops[1], line) & 0xFFFF
            rs1 = _parse_reg(ops[2], line)
            return encode_s(opcode, rs2, rs1, off)

        # ---- Formato B (branches) ----
        if fmt == InstFmt.B:
            # BEQ rs1, rs2, target
            rs1 = _parse_reg(ops[0], line)
            rs2 = _parse_reg(ops[1], line)
            off = self._resolve_branch(ops[2], pc, line)
            return encode_b(opcode, rs1, rs2, off)

        # ---- Formato J ----
        if fmt == InstFmt.J:
            addr = self._resolve(ops[0], line) & 0x3FFFFFF
            return encode_j(opcode, addr)

        # ---- Formato U (MOVHI) ----
        if fmt == InstFmt.U:
            rd    = _parse_reg(ops[0], line)
            imm21 = self._resolve(ops[1], line) & 0x1FFFFF
            return encode_u(opcode, rd, imm21)

        raise AssemblerError(f"Formato não suportado: {mnem}", line)
