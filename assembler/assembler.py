"""
assembler.py — Assembler de dois passos para EduRISC-16

Passo 1 — Varredura de labels:
  Percorre o AST e registra o endereço de cada label no mapa de símbolos.

Passo 2 — Geração de código:
  Traduz cada InstrNode para uma palavra de 16 bits usando a ISA.

Saída:
  lista de int (palavras de 16 bits)  → pode ser gravada como .bin ou .hex

Suporta diretivas:
  .ORG addr   — posiciona contador de localização em addr (máx 0x0FFF)
  .WORD val   — insere palavra literal
  .DATA v1, v2, ... — insere múltiplos words
"""

import struct
from pathlib import Path
from assembler.parser import Parser, InstrNode, LabelNode, DirectiveNode, ParseError
from cpu.instruction_set import (
    Opcode, MNEMONIC_TO_OPCODE, OPCODE_TYPE, InstType,
    encode_r, encode_m, encode_j, MEM_SIZE, WORD_MASK,
)


class AssemblerError(Exception):
    def __init__(self, msg: str, line: int = 0):
        super().__init__(f"[Linha {line}] Erro de montagem: {msg}")
        self.line = line


class Assembler:
    """
    Assembler completo de dois passos para EduRISC-16.

    Uso:
        asm = Assembler()
        words = asm.assemble(source_text)
        asm.write_binary(words, "prog.bin")
        asm.write_hex(words, "prog.hex")
    """

    def __init__(self):
        self._symbols: dict[str, int] = {}
        self._errors:  list[str]      = []

    @property
    def symbols(self) -> dict[str, int]:
        return dict(self._symbols)

    # -----------------------------------------------------------------------
    # Interface principal
    # -----------------------------------------------------------------------

    def assemble(self, source: str) -> list[int]:
        """
        Monta source assembly e retorna lista de palavras de 16 bits.
        Levanta AssemblerError em caso de erro.
        """
        self._symbols = {}
        self._errors  = []

        # Parsing
        parser = Parser()
        try:
            nodes = parser.parse(source)
        except ParseError as e:
            raise AssemblerError(str(e), e.line)

        # Passo 1 — varredura de labels
        self._pass1(nodes)

        # Passo 2 — geração de código
        words = self._pass2(nodes)
        return words

    def write_binary(self, words: list[int], path: str | Path):
        """Grava programa como arquivo binário (big-endian, 2 bytes por palavra)."""
        data = struct.pack(f">{len(words)}H", *words)
        Path(path).write_bytes(data)

    def write_hex(self, words: list[int], path: str | Path):
        """Grava programa no formato Intel HEX simplificado (uma palavra por linha)."""
        lines = [f":{i:04X} {w:04X}" for i, w in enumerate(words)]
        lines.append(":END")
        Path(path).write_text("\n".join(lines), encoding="utf-8")

    def listing(self, words: list[int], source: str) -> str:
        """Gera listagem com endereço, palavra e mnemônico."""
        from cpu.instruction_set import disassemble
        out = ["ADDR  WORD   DISASSEMBLY"]
        for addr, w in enumerate(words):
            try:
                dis = disassemble(w)
            except Exception:
                dis = f"0x{w:04X}"
            out.append(f"0x{addr:04X}  {w:04X}   {dis}")
        return "\n".join(out)

    # -----------------------------------------------------------------------
    # Passo 1
    # -----------------------------------------------------------------------

    def _pass1(self, nodes):
        """Atribui endereço a cada label."""
        lc = 0  # location counter
        for node in nodes:
            if isinstance(node, LabelNode):
                if node.name in self._symbols:
                    raise AssemblerError(f"Label duplicado: '{node.name}'", node.line)
                self._symbols[node.name] = lc
            elif isinstance(node, DirectiveNode):
                if node.name == ".ORG":
                    lc = node.values[0]
                elif node.name in (".WORD", ".DATA"):
                    lc += len(node.values)
            elif isinstance(node, InstrNode):
                lc += 1

    # -----------------------------------------------------------------------
    # Passo 2
    # -----------------------------------------------------------------------

    def _pass2(self, nodes) -> list[int]:
        """Gera palavras de código."""
        lc     = 0
        output: dict[int, int] = {}

        for node in nodes:
            if isinstance(node, LabelNode):
                continue

            elif isinstance(node, DirectiveNode):
                if node.name == ".ORG":
                    lc = node.values[0]
                elif node.name in (".WORD", ".DATA"):
                    for val in node.values:
                        output[lc] = val & WORD_MASK
                        lc += 1

            elif isinstance(node, InstrNode):
                word = self._encode_instr(node)
                output[lc] = word
                lc += 1

        if not output:
            return []

        max_addr = max(output.keys())
        words    = [output.get(i, 0xFFFF) for i in range(max_addr + 1)]
        return words

    # -----------------------------------------------------------------------
    # Codificação de instruções
    # -----------------------------------------------------------------------

    def _encode_instr(self, node: InstrNode) -> int:
        mnem = node.mnemonic
        ops  = node.operands
        line = node.line

        if mnem not in MNEMONIC_TO_OPCODE:
            raise AssemblerError(f"Mnemônico desconhecido: '{mnem}'", line)

        opcode = MNEMONIC_TO_OPCODE[mnem]
        itype  = OPCODE_TYPE[opcode]

        match itype:
            case InstType.J:
                addr = self._resolve_addr(ops[0], line)
                return encode_j(opcode, addr)

            case InstType.M:
                rd, base, offset = ops
                if offset > 0xF:
                    raise AssemblerError(f"Offset {offset} excede 4 bits (máx 15)", line)
                return encode_m(opcode, rd, base, offset)

            case InstType.R:
                if mnem == "HLT":
                    return encode_r(opcode, 0, 0, 0)
                elif mnem == "RET":
                    return encode_r(opcode, 0, 0, 0)
                elif mnem == "NOT":
                    rd, rs1 = ops
                    return encode_r(opcode, rd, rs1, 0)
                else:
                    rd, rs1, rs2 = ops
                    return encode_r(opcode, rd, rs1, rs2)

            case _:
                raise AssemblerError(f"Tipo não suportado para {mnem}", line)

    def _resolve_addr(self, operand, line: int) -> int:
        """Resolve operando de endereço: número ou nome de label."""
        if isinstance(operand, int):
            return operand & 0xFFF
        # é string — busca no mapa de símbolos
        if operand not in self._symbols:
            raise AssemblerError(f"Label não definido: '{operand}'", line)
        return self._symbols[operand] & 0xFFF
