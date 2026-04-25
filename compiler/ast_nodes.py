"""
ast_nodes.py — Nós da Árvore Sintática Abstrata para o compilador EduRISC-32v2

Representa expressões e statements da linguagem fonte (subconjunto de C):
  - variáveis inteiras locais e globais
  - atribuição simples e composta (+=, -=, *=, /=, &=, |=, ^=, <<=, >>=, %=)
  - operações aritméticas (+, -, *, /, %), bitwise (&, |, ^, ~, !)
  - shifts (<<, >>)
  - lógicos com short-circuit (&& , ||)
  - comparações (==, !=, <, >, <=, >=)
  - if / else
  - while / for
  - break / continue
  - return
  - chamadas de função com argumentos
  - bloco { ... }
  - arrays 1-D: int a[N]; a[i]; a[i] = expr;
  - ponteiros: int *p; *p; &var; &arr[i]; *p = expr;
  - #define (pré-processamento de constantes simples)
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
    op:    str       # '+','-','*','/','%','<<','>>','==','!=','<','>','<=','>=','&','|','^','&&','||'
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

@dataclass
class ArrayRef:
    """Leitura de elemento de array: a[i]"""
    name:  str
    index: "Expr"
    line:  int

@dataclass
class AddrOf:
    """Endereço de variável/elemento: &name  ou  &name[index]"""
    name:  str
    index: Optional["Expr"]   # None para &var; expr para &arr[i]
    line:  int

@dataclass
class Deref:
    """Leitura via ponteiro: *ptr"""
    ptr:  "Expr"
    line: int


Expr = IntLiteral | VarRef | BinOp | UnaryOp | FuncCall | ArrayRef | AddrOf | Deref


# ---------------------------------------------------------------------------
# Statements
# ---------------------------------------------------------------------------

@dataclass
class VarDecl:
    name:    str
    init:    Optional[Expr]
    line:    int
    is_ptr:  bool = False   # True para 'int *p'

@dataclass
class ArrayDecl:
    """Declaração de array local: int a[N] [= {v1, v2, ...}]"""
    name: str
    size: int                        # tamanho em elementos
    init: Optional[list[Expr]]       # lista de inicializadores ou None
    line: int

@dataclass
class Assign:
    name:  str
    op:    str   # '=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='
    value: Expr
    line:  int

@dataclass
class ArrayAssign:
    """Atribuição de elemento de array: a[i] op= expr"""
    name:  str
    index: Expr
    op:    str   # '=', '+=', etc.
    value: Expr
    line:  int

@dataclass
class DerefAssign:
    """Atribuição via ponteiro: *ptr op= expr"""
    ptr:   Expr
    op:    str
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
    init:   Optional["Stmt"]   # VarDecl/ArrayDecl/Assign ou None
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


Stmt = (VarDecl | ArrayDecl | Assign | ArrayAssign | DerefAssign |
        IfStmt | WhileStmt | ForStmt |
        ReturnStmt | BreakStmt | ContinueStmt | ExprStmt | Block)


# ---------------------------------------------------------------------------
# Declaração de função e programa
# ---------------------------------------------------------------------------

@dataclass
class GlobalVarDecl:
    """Variável global declarada no escopo de arquivo."""
    name:   str
    init:   Optional[Expr]
    line:   int
    is_ptr: bool = False

@dataclass
class GlobalArrayDecl:
    """Array global declarado no escopo de arquivo: int a[N] [= {...}]"""
    name: str
    size: int
    init: Optional[list[Expr]]
    line: int

@dataclass
class FuncDef:
    name:   str
    params: list[str]          # nomes dos parâmetros
    is_ptr: list[bool]         # is_ptr[i] = True se parâmetro i é ponteiro
    body:   list[Stmt]
    line:   int

@dataclass
class Program:
    globals:   list[GlobalVarDecl | GlobalArrayDecl]
    functions: list[FuncDef]
