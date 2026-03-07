"""
alu.py — Unidade Lógico-Aritmética EduRISC-16

Implementa todas as operações aritméticas e lógicas da ISA.
Retorna (resultado_16bit, carry, overflow).
"""

from cpu.instruction_set import Opcode, WORD_BITS, WORD_MASK


class ALUResult:
    """Container para resultado de operação da ALU."""
    __slots__ = ("value", "carry", "ovf")

    def __init__(self, value: int, carry: bool = False, ovf: bool = False):
        self.value = value & WORD_MASK
        self.carry = carry
        self.ovf   = ovf

    def __repr__(self) -> str:
        return f"ALUResult(0x{self.value:04X}, carry={self.carry}, ovf={self.ovf})"


class ALU:
    """
    Unidade Lógico-Aritmética de 16 bits.

    Uso:
        alu = ALU()
        result = alu.execute(Opcode.ADD, 10, 20)
        print(result.value)  # 30
    """

    def execute(self, opcode: Opcode, a: int, b: int = 0) -> ALUResult:
        """Executa operação e retorna ALUResult."""
        a = a & WORD_MASK
        b = b & WORD_MASK

        match opcode:
            case Opcode.ADD:
                return self._add(a, b)
            case Opcode.SUB:
                return self._sub(a, b)
            case Opcode.MUL:
                return self._mul(a, b)
            case Opcode.DIV:
                return self._div(a, b)
            case Opcode.AND:
                return ALUResult(a & b)
            case Opcode.OR:
                return ALUResult(a | b)
            case Opcode.XOR:
                return ALUResult(a ^ b)
            case Opcode.NOT:
                return ALUResult(~a)
            case _:
                # Operações de controle passam pelo execute sem modificar ALU
                return ALUResult(a)

    # ---- operações internas -----------------------------------------------

    def _add(self, a: int, b: int) -> ALUResult:
        raw   = a + b
        carry = raw > WORD_MASK
        # overflow com sinal: dois positivos somam negativo, ou dois negativos somam positivo
        sign_a = a >> (WORD_BITS - 1)
        sign_b = b >> (WORD_BITS - 1)
        sign_r = (raw & WORD_MASK) >> (WORD_BITS - 1)
        ovf = bool((sign_a == sign_b) and (sign_r != sign_a))
        return ALUResult(raw, carry, ovf)

    def _sub(self, a: int, b: int) -> ALUResult:
        # sub via complemento de dois
        raw   = a - b
        carry = raw < 0  # borrow
        sign_a = a >> (WORD_BITS - 1)
        sign_b = b >> (WORD_BITS - 1)
        sign_r = (raw & WORD_MASK) >> (WORD_BITS - 1)
        ovf = bool((sign_a != sign_b) and (sign_r != sign_a))
        return ALUResult(raw, carry, ovf)

    def _mul(self, a: int, b: int) -> ALUResult:
        raw = a * b
        carry = raw > WORD_MASK
        return ALUResult(raw, carry)

    def _div(self, a: int, b: int) -> ALUResult:
        if b == 0:
            # divisão por zero: retorna 0xFFFF com carry
            return ALUResult(WORD_MASK, carry=True)
        return ALUResult(a // b)
