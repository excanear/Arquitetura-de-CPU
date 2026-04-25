"""
ast_nodes.py — Nós da Árvore Sintática Abstrata para o compilador EduRISC-32v2

Representa expressões e statements da linguagem fonte (subconjunto de C):
  - variáveis inteiras locais e globais
  - atribuição simples e composta (+=, -=, *=, /=, &=, |=, ^=)
  - operações aritméticas (+, -, *, /), bitwise (&, |, ^, ~, !)
  - comparações (==, !=, <, >, <=, >=)
  - if / else
  - while / for
  - break / continue
  - return
  - chamadas de função com argumentos
  - bloco { ... }
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Expressões
# ---------------------------------------------------------------------------

@dataclass
class IntLiteral:
    value: int
    line:  int

@dataclass
class VarRef:
    name: str
    line: int

@dataclass
class BinOp:
    op:    str       # '+', '-', '*', '/', '==', '!=', '<', '>', '<=', '>=', '&', '|', '^'
    left:  "Expr"
    right: "Expr"
    line:  int

@dataclass
class UnaryOp:
    op:      str    # '-', '~', '!'
    operand: "Expr"
    line:    int

@dataclass
class FuncCall:
    name: str
    args: list["Expr"]
    line: int


Expr = IntLiteral | VarRef | BinOp | UnaryOp | FuncCall


# ---------------------------------------------------------------------------
# Statements
# ---------------------------------------------------------------------------

@dataclass
class VarDecl:
    name:  str
    init:  Optional[Expr]
    line:  int

@dataclass
class Assign:
    name:  str
    op:    str   # '=', '+=', '-=', '*=', '/=', '&=', '|=', '^='
    value: Expr
    line:  int

@dataclass
class IfStmt:
    cond:      Expr
    then_body: list["Stmt"]
    else_body: list["Stmt"]
    line:      int

@dataclass
class WhileStmt:
    cond: Expr
    body: list["Stmt"]
    line: int

@dataclass
class ForStmt:
    """for (init; cond; update) body"""
    init:   Optional["Stmt"]   # VarDecl ou Assign ou None
    cond:   Optional[Expr]     # None → loop infinito
    update: Optional["Stmt"]   # Assign ou ExprStmt ou None
    body:   list["Stmt"]
    line:   int

@dataclass
class ReturnStmt:
    value: Optional[Expr]
    line:  int

@dataclass
class BreakStmt:
    line: int

@dataclass
class ContinueStmt:
    line: int

@dataclass
class ExprStmt:
    expr: Expr
    line: int

@dataclass
class Block:
    stmts: list["Stmt"]
    line:  int


Stmt = (VarDecl | Assign | IfStmt | WhileStmt | ForStmt |
        ReturnStmt | BreakStmt | ContinueStmt | ExprStmt | Block)


# ---------------------------------------------------------------------------
# Declaração de função e programa
# ---------------------------------------------------------------------------

@dataclass
class GlobalVarDecl:
    """Variável global declarada no escopo de arquivo."""
    name: str
    init: Optional[Expr]
    line: int

@dataclass
class FuncDef:
    name:   str
    params: list[str]
    body:   list[Stmt]
    line:   int

@dataclass
class Program:
    globals:   list[GlobalVarDecl]
    functions: list[FuncDef]
