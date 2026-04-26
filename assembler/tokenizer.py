"""
tokenizer.py — Tokenizador legado para o Assembly EduRISC-16

Converte linhas de texto assembly em tokens estruturados.

Este módulo é mantido para compatibilidade com a trilha histórica EduRISC-16.
Ele não define a arquitetura principal suportada do repositório.

Tokens produzidos:
  LABEL    — identificador seguido de ':'
  MNEMONIC — nome de instrução
  REGISTER — R0-R15
  NUMBER   — literal numérico (decimal ou 0x hex)
  COMMA    — separador ','
  LBRACKET — '['
  RBRACKET — ']'
  PLUS     — '+'
  COMMENT  — texto após ';' (descartado)
"""

import re
from dataclasses import dataclass
from enum import Enum, auto


class TokType(Enum):
    LABEL    = auto()
    MNEMONIC = auto()
    REGISTER = auto()
    NUMBER   = auto()
    COMMA    = auto()
    LBRACKET = auto()
    RBRACKET = auto()
    PLUS     = auto()
    DIRECTIVE = auto()   # .ORG, .WORD, .DATA


@dataclass
class Token:
    type:  TokType
    value: str | int
    line:  int

    def __repr__(self) -> str:
        return f"Token({self.type.name}, {self.value!r}, L{self.line})"


# Ordem importa: mais específico primeiro
_TOKEN_SPEC = [
    ("COMMENT",  r";.*"),
    ("DIRECTIVE", r"\.\w+"),
    ("LABEL",    r"[A-Za-z_]\w*\s*:"),
    ("REGISTER", r"\bR(?:1[0-5]|[0-9])\b"),
    ("HEX",      r"0[xX][0-9A-Fa-f]+"),
    ("DEC",      r"\b\d+\b"),
    ("MNEMONIC", r"[A-Za-z_]\w*"),
    ("COMMA",    r","),
    ("LBRACKET", r"\["),
    ("RBRACKET", r"\]"),
    ("PLUS",     r"\+"),
    ("WS",       r"\s+"),
]

_MASTER_RE = re.compile(
    "|".join(f"(?P<{name}>{pattern})" for name, pattern in _TOKEN_SPEC)
)


def tokenize(line: str, lineno: int) -> list[Token]:
    """Tokeniza uma única linha de assembly. Retorna lista de Tokens."""
    tokens: list[Token] = []
    for m in _MASTER_RE.finditer(line):
        kind = m.lastgroup
        raw  = m.group()

        if kind in ("WS", "COMMENT"):
            continue
        elif kind == "LABEL":
            name = raw.rstrip(":").strip()
            tokens.append(Token(TokType.LABEL, name.upper(), lineno))
        elif kind == "REGISTER":
            tokens.append(Token(TokType.REGISTER, int(raw[1:]), lineno))
        elif kind == "HEX":
            tokens.append(Token(TokType.NUMBER, int(raw, 16), lineno))
        elif kind == "DEC":
            tokens.append(Token(TokType.NUMBER, int(raw), lineno))
        elif kind == "MNEMONIC":
            tokens.append(Token(TokType.MNEMONIC, raw.upper(), lineno))
        elif kind == "COMMA":
            tokens.append(Token(TokType.COMMA, ",", lineno))
        elif kind == "LBRACKET":
            tokens.append(Token(TokType.LBRACKET, "[", lineno))
        elif kind == "RBRACKET":
            tokens.append(Token(TokType.RBRACKET, "]", lineno))
        elif kind == "PLUS":
            tokens.append(Token(TokType.PLUS, "+", lineno))
        elif kind == "DIRECTIVE":
            tokens.append(Token(TokType.DIRECTIVE, raw.upper(), lineno))

    return tokens
