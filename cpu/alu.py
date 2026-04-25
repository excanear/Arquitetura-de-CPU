"""
alu.py — Unidade Lógico-Aritmética EduRISC-32v2

Implementa todas as operações aritméticas, lógicas e de deslocamento
da ISA de 32 bits com 32 registradores.

Características:
  - Palavras de 32 bits sem sinal (valor interno sempre mascarado)
  - Inteiros com sinal representados em complemento de 2
  - Multiplicação 32×32 → 64 bits (MUL = bits inferiores, MULH = bits superiores)
  - Divisão por zero: retorna 0xFFFFFFFF e ativa carry (flag D no hardware RTL)
  - Flags: ZERO, CARRY, NEGATIVE, OVERFLOW (atualizadas pela unidade de controle)
"""

from cpu.instruction_set import (
    Opcode, WORD_BITS, WORD_MASK, SP_REG, LR_REG,
)

# Máscara de bit de sinal de 32 bits
_SIGN_BIT   = 1 << (WORD_BITS - 1)
_SIGNED_MAX =  (1 << (WORD_BITS - 1)) - 1
_SIGNED_MIN = -(1 << (WORD_BITS - 1))


def _to_signed(v: int) -> int:
    """Converte valor de 32 bits sem sinal para inteiro Python com sinal."""
    v &= WORD_MASK
    return v if v < _SIGN_BIT else v - (1 << WORD_BITS)


class ALUResult:
    """Container imutável para o resultado de uma operação da ALU."""
    __slots__ = ("value", "carry", "ovf")

    def __init__(self, value: int, carry: bool = False, ovf: bool = False):
        self.value = int(value) & WORD_MASK   # sempre 32 bits
        self.carry = bool(carry)
        self.ovf   = bool(ovf)

    def __repr__(self) -> str:
        return (f"ALUResult(0x{self.value:08X}, "
                f"carry={self.carry}, ovf={self.ovf})")


class ALU:
    """
    Unidade Lógico-Aritmética de 32 bits — EduRISC-32v2.

    Uso:
        alu = ALU()
        result = alu.execute(Opcode.ADD, a, b)
        print(result.value)   # inteiro de 32 bits sem sinal
        print(result.carry)   # True se ocorreu carry/borrow
        print(result.ovf)     # True se ocorreu overflow com sinal

    O parâmetro `b` deve conter o valor já preparado pelo estágio ID:
      - Para instruções R-type:  b = valor de rs2
      - Para instruções I-type:  b = sext(imm16) ou imm21
      - Para deslocamentos imediatos (SHLI/SHRI/SHRAI): b = shamt (5 bits)
    """

    # Conjunto de opcodes que a ALU processa (para verificação rápida)
    _HANDLED = frozenset({
        Opcode.ADD,  Opcode.ADDI,
        Opcode.SUB,
        Opcode.MUL,  Opcode.MULH,
        Opcode.DIV,  Opcode.DIVU,
        Opcode.REM,
        Opcode.AND,  Opcode.ANDI,
        Opcode.OR,   Opcode.ORI,
        Opcode.XOR,  Opcode.XORI,
        Opcode.NOT,  Opcode.NEG,
        Opcode.SHL,  Opcode.SHR,  Opcode.SHRA,
        Opcode.SHLI, Opcode.SHRI, Opcode.SHRAI,
        Opcode.MOV,  Opcode.MOVI, Opcode.MOVHI,
        Opcode.SLT,  Opcode.SLTU, Opcode.SLTI,
    })

    def execute(self, opcode: Opcode, a: int, b: int = 0) -> ALUResult:
        """
        Executa operação da ALU e retorna ALUResult.

        `a` e `b` são interpretados como valores de 32 bits sem sinal;
        operações com sinal usam _to_signed() internamente.
        """
        a = int(a) & WORD_MASK
        b = int(b) & WORD_MASK

        match opcode:
            # ---- Aritmética ----
            case Opcode.ADD | Opcode.ADDI:
                return self._add(a, b)

            case Opcode.SUB:
                return self._sub(a, b)

            case Opcode.MUL:
                # Produto de 64 bits — retorna os 32 bits inferiores
                raw   = (_to_signed(a) * _to_signed(b)) & ((1 << 64) - 1)
                carry = (raw >> 32) != 0
                return ALUResult(raw, carry)

            case Opcode.MULH:
                # Produto de 64 bits — retorna os 32 bits superiores
                raw   = _to_signed(a) * _to_signed(b)
                upper = (raw >> 32) & WORD_MASK
                return ALUResult(upper)

            case Opcode.DIV:
                return self._div_signed(a, b)

            case Opcode.DIVU:
                return self._div_unsigned(a, b)

            case Opcode.REM:
                return self._rem_signed(a, b)

            # ---- Lógica ----
            case Opcode.AND | Opcode.ANDI:
                return ALUResult(a & b)

            case Opcode.OR | Opcode.ORI:
                return ALUResult(a | b)

            case Opcode.XOR | Opcode.XORI:
                return ALUResult(a ^ b)

            case Opcode.NOT:
                return ALUResult(~a)      # mascarado pelo construtor

            case Opcode.NEG:
                return self._sub(0, a)   # NEG = 0 - a (em complemento de 2)

            # ---- Deslocamentos ----
            case Opcode.SHL | Opcode.SHLI:
                shamt = b & 0x1F
                return ALUResult(a << shamt)

            case Opcode.SHR | Opcode.SHRI:
                shamt = b & 0x1F
                return ALUResult(a >> shamt)  # lógico: zeros entram pela esquerda

            case Opcode.SHRA | Opcode.SHRAI:
                # Aritmético: mantém o bit de sinal
                shamt  = b & 0x1F
                result = _to_signed(a) >> shamt
                return ALUResult(result)

            # ---- Movimentação ----
            case Opcode.MOV:
                return ALUResult(a)   # MOV rd, rs1 → rd = rs1_val (forwarding via a)

            case Opcode.MOVI:
                return ALUResult(b)   # MOVI rd, imm → rd = imm (preparado em b pelo ID)

            case Opcode.MOVHI:
                # U-type: rd = imm21 << 11
                # ID stage coloca imm21 em b
                return ALUResult(b << 11)

            # ---- Comparação ----
            case Opcode.SLT | Opcode.SLTI:
                # Signed less-than
                result = 1 if _to_signed(a) < _to_signed(b) else 0
                return ALUResult(result)

            case Opcode.SLTU:
                # Unsigned less-than
                result = 1 if a < b else 0
                return ALUResult(result)

            case _:
                # Instruções de controle de fluxo, memória e sistema não executam
                # nada na ALU; passam o operando A transparentemente (para cálculo
                # de endereço de desvio ou apenas propagação de dados).
                return ALUResult(a)

    # -----------------------------------------------------------------------
    # Operações internas
    # -----------------------------------------------------------------------

    def _add(self, a: int, b: int) -> ALUResult:
        raw    = a + b
        carry  = raw > WORD_MASK
        # Overflow com sinal: dois positivos somam negativo, ou vice-versa
        sa, sb = bool(a & _SIGN_BIT), bool(b & _SIGN_BIT)
        sr     = bool((raw & WORD_MASK) & _SIGN_BIT)
        ovf    = (sa == sb) and (sr != sa)
        return ALUResult(raw, carry, ovf)

    def _sub(self, a: int, b: int) -> ALUResult:
        # Subtração em complemento de 2: a - b = a + (~b + 1)
        raw    = a - b
        carry  = raw < 0          # borrow (carry invertido na subtração)
        sa, sb = bool(a & _SIGN_BIT), bool(b & _SIGN_BIT)
        sr     = bool((raw & WORD_MASK) & _SIGN_BIT)
        ovf    = (sa != sb) and (sr != sa)
        return ALUResult(raw, carry, ovf)

    def _div_signed(self, a: int, b: int) -> ALUResult:
        if b == 0:
            return ALUResult(WORD_MASK, carry=True)   # divisão por zero
        # Truncamento em direção ao zero (C99 / padrão RISC)
        sa, sb  = _to_signed(a), _to_signed(b)
        result  = int(sa / sb)   # trunca (não arredonda) como hardware
        return ALUResult(result)

    def _div_unsigned(self, a: int, b: int) -> ALUResult:
        if b == 0:
            return ALUResult(WORD_MASK, carry=True)
        return ALUResult(a // b)

    def _rem_signed(self, a: int, b: int) -> ALUResult:
        if b == 0:
            return ALUResult(a)   # REM por zero: retorna dividendo (padrão RISC-V)
        sa, sb = _to_signed(a), _to_signed(b)
        result = int(sa - (int(sa / sb)) * sb)   # mantém sinal do dividendo
        return ALUResult(result)
