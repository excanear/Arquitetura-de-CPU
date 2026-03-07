"""
registers.py — Banco de registradores EduRISC-16

16 registradores de 16 bits (R0-R15).
R0 é de uso geral (diferente do RISC-V, não é hardwired a zero).
R15 é o link register (reservado para CALL/RET).

Flags de status:
  ZERO  — resultado da última operação da ALU foi zero
  CARRY — carry/borrow da última operação aritmética
  NEG   — resultado negativo (bit 15 = 1)
  OVF   — overflow em operação com sinal
"""

from cpu.instruction_set import NUM_REGISTERS, WORD_BITS, WORD_MASK


class Flags:
    """Registrador de flags de status."""

    def __init__(self):
        self.zero  = False
        self.carry = False
        self.neg   = False
        self.ovf   = False

    def update(self, result: int, carry: bool = False, ovf: bool = False):
        """Atualiza flags com base no resultado de uma operação."""
        masked = result & WORD_MASK
        self.zero  = (masked == 0)
        self.carry = carry
        self.neg   = bool(masked >> (WORD_BITS - 1))
        self.ovf   = ovf

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
    Banco de 16 registradores de 16 bits.

    Uso:
        rf = RegisterFile()
        rf[3] = 0x1234      # escreve R3
        val = rf[3]         # lê R3
    """

    def __init__(self):
        self._regs = [0] * NUM_REGISTERS
        self.flags = Flags()

    # ---- acesso por índice ------------------------------------------------
    def __getitem__(self, index: int) -> int:
        self._check(index)
        return self._regs[index]

    def __setitem__(self, index: int, value: int):
        self._check(index)
        self._regs[index] = value & WORD_MASK

    # ---- utilitários -------------------------------------------------------
    def _check(self, index: int):
        if not (0 <= index < NUM_REGISTERS):
            raise IndexError(f"Índice de registrador inválido: {index}")

    def reset(self):
        self._regs = [0] * NUM_REGISTERS
        self.flags = Flags()

    def dump(self) -> str:
        """Retorna representação formatada de todos os registradores."""
        lines = [f"  Flags: {self.flags}"]
        for i in range(0, NUM_REGISTERS, 4):
            row = "  ".join(
                f"R{j:<2} = 0x{self._regs[j]:04X} ({self._regs[j]:5d})"
                for j in range(i, min(i + 4, NUM_REGISTERS))
            )
            lines.append("  " + row)
        return "\n".join(lines)

    def snapshot(self) -> list[int]:
        """Retorna cópia da lista de registradores."""
        return list(self._regs)

    def to_dict(self) -> dict:
        return {f"R{i}": self._regs[i] for i in range(NUM_REGISTERS)}
