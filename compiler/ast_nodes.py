"""
ast_nodes.py — Nós da Árvore Sintática Abstrata para o compilador EduRISC-16

Representa expressões e statements da linguagem fonte minimalista,
que é um subconjunto de C com:
  - variáveis inteiras locais
  - atribuição
  - operações aritméticas (+, -, *, /)
  - comparações (==, !=, <, >, <=, >=)
  - if / else
  - while
  - return
  - chamadas de função simples (sem parâmetros por hora)
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
    op:    str       # '+', '-', '*', '/', '==', '!=', '<', '>', '<=', '>='
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
class ReturnStmt:
    value: Optional[Expr]
    line:  int

@dataclass
class ExprStmt:
    expr: Expr
    line: int

@dataclass
class Block:
    stmts: list["Stmt"]
    line:  int


Stmt = VarDecl | Assign | IfStmt | WhileStmt | ReturnStmt | ExprStmt | Block


# ---------------------------------------------------------------------------
# Declaração de função e programa
# ---------------------------------------------------------------------------

@dataclass
class FuncDef:
    name:   str
    params: list[str]
    body:   list[Stmt]
    line:   int

@dataclass
class Program:
    functions: list[FuncDef]
