"""
registers.py — Banco de registradores EduRISC-32v2

32 registradores de 32 bits (R0-R31).
R0 é hardwired a zero (qualquer escrita é silenciosamente descartada),
  seguindo a convenção de arquiteturas RISC modernas (RISC-V, MIPS).
R30 é o stack pointer (SP) — convenção ABI.
R31 é o link register (LR) — reservado para CALL/RET.

Flags de status (atualizadas pela ALU após operações aritméticas/lógicas):
  ZERO  — resultado da última operação da ALU foi zero
  CARRY — carry/borrow da última operação aritmética
  NEG   — resultado negativo (bit 31 = 1, complemento de 2)
  OVF   — overflow em operação com sinal
"""

from cpu.instruction_set import NUM_REGISTERS, WORD_BITS, WORD_MASK, ZERO_REG


class Flags:
    """Registrador de flags de status (PSW — Program Status Word)."""

    def __init__(self):
        self.zero  = False
        self.carry = False
        self.neg   = False
        self.ovf   = False

    def update(self, result: int, carry: bool = False, ovf: bool = False):
        """Atualiza flags com base no resultado de uma operação de 32 bits."""
        masked = result & WORD_MASK
        self.zero  = (masked == 0)
        self.carry = bool(carry)
        self.neg   = bool(masked >> (WORD_BITS - 1))
        self.ovf   = bool(ovf)

    def __repr__(self) -> str:
        z = "Z" if self.zero  else "z"
        c = "C" if self.carry else "c"
        n = "N" if self.neg   else "n"
        o = "O" if self.ovf   else "o"
        return f"[{z}{c}{n}{o}]"

    def to_dict(self) -> dict:
        return {"zero": self.zero, "carry": self.carry, "neg": self.neg, "ovf": self.ovf}


class RegisterFile:
    """
    Banco de 32 registradores de 32 bits — EduRISC-32v2.

    R0 é hardwired a zero: leituras sempre retornam 0, escritas são ignoradas.

    Uso:
        rf = RegisterFile()
        rf[3] = 0x12345678   # escreve R3
        val   = rf[3]        # lê R3  → 0x12345678
        rf[0] = 0xDEAD       # escreve R0 → ignorado
        assert rf[0] == 0    # R0 é sempre 0
    """

    def __init__(self):
        self._regs = [0] * NUM_REGISTERS
        self.flags = Flags()

    # ---- acesso por índice ------------------------------------------------

    def __getitem__(self, index: int) -> int:
        self._check(index)
        return self._regs[index]   # _regs[0] é sempre 0 (ver __setitem__)

    def __setitem__(self, index: int, value: int):
        self._check(index)
        if index == ZERO_REG:
            return   # R0 hardwired zero — descarta escrita silenciosamente
        self._regs[index] = int(value) & WORD_MASK

    def __iter__(self):
        """Permite list(rf) para leitura de todos os registradores."""
        return iter(self._regs)

    # ---- utilitários -------------------------------------------------------

    def _check(self, index: int):
        if not (0 <= index < NUM_REGISTERS):
            raise IndexError(
                f"Índice de registrador inválido: {index} "
                f"(válido: 0–{NUM_REGISTERS - 1})"
            )

    def reset(self):
        """Zera todos os registradores e flags (mantém R0=0 por design)."""
        self._regs = [0] * NUM_REGISTERS
        self.flags = Flags()

    def dump(self) -> str:
        """Retorna representação formatada de todos os registradores (4 por linha)."""
        aliases = {0: "zero", 30: "sp", 31: "lr"}
        lines = [f"  Flags: {self.flags}"]
        for i in range(0, NUM_REGISTERS, 4):
            parts = []
            for j in range(i, min(i + 4, NUM_REGISTERS)):
                alias = f"/{aliases[j]}" if j in aliases else ""
                parts.append(f"R{j:<2}{alias} = 0x{self._regs[j]:08X} ({self._regs[j]:11d})")
            lines.append("  " + "  ".join(parts))
        return "\n".join(lines)

    def snapshot(self) -> list[int]:
        """Retorna cópia da lista de registradores (imutável)."""
        return list(self._regs)

    def to_dict(self) -> dict:
        """Retorna dicionário {nome: valor} de todos os registradores."""
        return {f"R{i}": self._regs[i] for i in range(NUM_REGISTERS)}
