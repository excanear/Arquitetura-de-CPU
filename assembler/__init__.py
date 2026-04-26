"""
__init__.py — Pacote assembler legado EduRISC-16

Nota:
Este pacote ainda expõe tokenizer/parser compatíveis com a trilha legada
EduRISC-16. O assembler principal suportado do repositório segue sendo o
Assembler de EduRISC-32v2 exposto pelo mesmo pacote.
"""

from assembler.tokenizer import tokenize, Token, TokType
from assembler.parser import Parser, InstrNode, LabelNode, DirectiveNode, ParseError
from assembler.assembler import Assembler, AssemblerError

__all__ = [
    "tokenize", "Token", "TokType",
    "Parser", "InstrNode", "LabelNode", "DirectiveNode", "ParseError",
    "Assembler", "AssemblerError",
]
