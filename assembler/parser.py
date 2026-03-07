"""
parser.py — Parser para o Assembly EduRISC-16

Converte a lista de Tokens em uma lista de instruções intermediárias
(nós de AST simples) prontas para geração de código pelo assembler.

Gramática suportada:

  linha       ::= [label] instrucao | [label] diretiva | label
  instrucao   ::= MNEM operandos
  operandos ::=
    (vazio)                           ; HLT, RET
    | REG                             ; NOT rd, rs1 — quando mnem usa 1 reg
    | REG ',' REG                     ; NOT rd, rs1
    | REG ',' REG ',' REG             ; ADD rd, rs1, rs2
    | REG ',' '[' REG '+' NUM ']'     ; LOAD/STORE rd, [base+offset]
    | REG ',' '[' REG ']'             ; LOAD/STORE rd, [base]
    | NUM                             ; JMP addr

  diretiva    ::= '.ORG' NUM  | '.WORD' NUM | '.DATA' NUM [, NUM]*
"""

from dataclasses import dataclass, field
from typing import Any
from assembler.tokenizer import Token, TokType, tokenize


# ---------------------------------------------------------------------------
# Nós do AST
# ---------------------------------------------------------------------------

@dataclass
class LabelNode:
    name: str
    line: int


@dataclass
class InstrNode:
    mnemonic: str
    operands: list[Any]   # mix de int (reg) / int (imm) / str (label)
    line:     int
    # flag para distinguir registrador de número
    op_is_reg: list[bool] = field(default_factory=list)


@dataclass
class DirectiveNode:
    name:   str
    values: list[int]
    line:   int


ASTNode = LabelNode | InstrNode | DirectiveNode


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

class ParseError(Exception):
    def __init__(self, msg: str, line: int):
        super().__init__(f"[Linha {line}] Erro de sintaxe: {msg}")
        self.line = line


class Parser:
    """
    Transforma linhas de texto assembly em lista de ASTNode.

    Uso:
        p = Parser()
        nodes = p.parse(source_text)
    """

    def parse(self, source: str) -> list[ASTNode]:
        nodes: list[ASTNode] = []
        for lineno, line in enumerate(source.splitlines(), start=1):
            line = line.strip()
            if not line:
                continue
            tokens = tokenize(line, lineno)
            if not tokens:
                continue
            parsed = self._parse_line(tokens, lineno)
            nodes.extend(parsed)
        return nodes

    # ---- parsing de uma linha ---------------------------------------------

    def _parse_line(self, tokens: list[Token], lineno: int) -> list[ASTNode]:
        nodes: list[ASTNode] = []
        pos = 0

        # Coleta labels (pode haver mais de um na mesma linha)
        while pos < len(tokens) and tokens[pos].type == TokType.LABEL:
            nodes.append(LabelNode(tokens[pos].value, lineno))
            pos += 1

        if pos >= len(tokens):
            return nodes  # linha só com label

        tok = tokens[pos]

        if tok.type == TokType.DIRECTIVE:
            nodes.append(self._parse_directive(tokens, pos, lineno))
            return nodes

        if tok.type == TokType.MNEMONIC:
            nodes.append(self._parse_instr(tokens, pos, lineno))
            return nodes

        raise ParseError(f"Token inesperado: {tok}", lineno)

    # ---- diretivas --------------------------------------------------------

    def _parse_directive(self, tokens: list[Token], pos: int, lineno: int) -> DirectiveNode:
        name  = tokens[pos].value
        pos  += 1
        vals: list[int] = []
        while pos < len(tokens):
            t = tokens[pos]
            if t.type == TokType.NUMBER:
                vals.append(t.value)
                pos += 1
                # consumir vírgula opcional
                if pos < len(tokens) and tokens[pos].type == TokType.COMMA:
                    pos += 1
            else:
                break
        return DirectiveNode(name, vals, lineno)

    # ---- instruções -------------------------------------------------------

    def _parse_instr(self, tokens: list[Token], pos: int, lineno: int) -> InstrNode:
        mnem = tokens[pos].value
        pos += 1
        rest = tokens[pos:]

        operands:   list[Any]  = []
        op_is_reg:  list[bool] = []

        if not rest:
            # HLT, RET
            return InstrNode(mnem, [], lineno, [])

        # J-type: JMP/JZ/JNZ/CALL — único operando: número ou label
        if mnem in ("JMP", "JZ", "JNZ", "CALL"):
            t = rest[0]
            if t.type == TokType.NUMBER:
                operands.append(t.value)
                op_is_reg.append(False)
            elif t.type == TokType.MNEMONIC:
                # label referenciado como número futuro
                operands.append(t.value)   # string do label
                op_is_reg.append(False)
            else:
                raise ParseError(f"Esperado endereço após {mnem}", lineno)
            return InstrNode(mnem, operands, lineno, op_is_reg)

        # LOAD/STORE: Rd, [Base + offset]  ou  Rd, [Base]
        if mnem in ("LOAD", "STORE"):
            return self._parse_mem(mnem, rest, lineno)

        # NOT: rd, rs1
        if mnem == "NOT":
            rd  = self._expect_reg(rest, 0, lineno)
            _   = self._expect(rest, 1, TokType.COMMA, lineno)
            rs1 = self._expect_reg(rest, 2, lineno)
            return InstrNode(mnem, [rd, rs1], lineno, [True, True])

        # R-type padrão: rd, rs1, rs2
        rd  = self._expect_reg(rest, 0, lineno)
        _   = self._expect(rest, 1, TokType.COMMA, lineno)
        rs1 = self._expect_reg(rest, 2, lineno)
        _   = self._expect(rest, 3, TokType.COMMA, lineno)
        rs2 = self._expect_reg(rest, 4, lineno)
        return InstrNode(mnem, [rd, rs1, rs2], lineno, [True, True, True])

    def _parse_mem(self, mnem: str, tokens: list[Token], lineno: int) -> InstrNode:
        """LOAD/STORE rd, [base + offset]"""
        rd  = self._expect_reg(tokens, 0, lineno)
        _   = self._expect(tokens, 1, TokType.COMMA, lineno)
        _   = self._expect(tokens, 2, TokType.LBRACKET, lineno)
        base = self._expect_reg(tokens, 3, lineno)

        # verifica se tem + offset
        if len(tokens) > 4 and tokens[4].type == TokType.PLUS:
            offset = self._expect(tokens, 5, TokType.NUMBER, lineno).value
            _ = self._expect(tokens, 6, TokType.RBRACKET, lineno)
        else:
            _ = self._expect(tokens, 4, TokType.RBRACKET, lineno)
            offset = 0

        return InstrNode(mnem, [rd, base, offset], lineno, [True, True, False])

    # ---- helpers ----------------------------------------------------------

    def _expect(self, tokens: list[Token], idx: int, ttype: TokType, lineno: int) -> Token:
        if idx >= len(tokens):
            raise ParseError(f"Esperado {ttype.name} na posição {idx}", lineno)
        if tokens[idx].type != ttype:
            raise ParseError(f"Esperado {ttype.name}, obteve {tokens[idx]}", lineno)
        return tokens[idx]

    def _expect_reg(self, tokens: list[Token], idx: int, lineno: int) -> int:
        t = self._expect(tokens, idx, TokType.REGISTER, lineno)
        return t.value
