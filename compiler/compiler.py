"""
compiler.py — Compilador de linguagem C-like para Assembly EduRISC-32v2

Pipeline de compilação:
  texto fonte  →  pré-processo  →  tokens  →  AST  →  código assembly EduRISC-32v2

Suporta:
  - variáveis locais e globais: int x = expr;
  - ponteiros: int *p;  *p;  &var;  &arr[i];  *p = expr;
  - arrays 1-D: int a[N];  a[i];  a[i] = expr;  int a[N] = {v1, v2, ...};
  - atribuição simples (=) e composta (+=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=)
  - expressões: +, -, *, /, %, <<, >>, &, |, ^, ~, !, &&, ||
  - comparações: ==, !=, <, >, <=, >=  (retornam 0 ou 1)
  - if / else
  - while / for
  - break / continue
  - return expr;
  - funções: int/void nome(int p1, int *p2, ...) { ... }
  - chamada de função com argumentos (passados em registradores)
  - pré-processamento: #define NOME valor

Modelo de execução:
  - R0  = zero hardwired (constante 0)
  - R1  = valor de retorno de função (convenção ABI)
  - R2–R25 disponíveis como variáveis locais / temporários
  - R30 = SP (stack pointer), R31 = LR (link register)
  - R26 = scratch temporário (comparações/endereços)
  - Argumentos passados em R1, R2, ... (convenção simples de registrador)
  - Variáveis globais e arrays: armazenados em posições fixas de memória (segmento de dados)
"""

import os
import re
from compiler.ast_nodes import (
    Program, GlobalVarDecl, GlobalArrayDecl, FuncDef, Stmt, Expr,
    VarDecl, ArrayDecl, Assign, ArrayAssign, DerefAssign,
    IfStmt, WhileStmt, ForStmt,
    ReturnStmt, BreakStmt, ContinueStmt, ExprStmt, Block,
    IntLiteral, VarRef, BinOp, UnaryOp, FuncCall,
    ArrayRef, AddrOf, Deref, StringLit,
)


# ---------------------------------------------------------------------------
# Erros
# ---------------------------------------------------------------------------

class CompileError(Exception):
    def __init__(self, msg: str, line: int = 0):
        super().__init__(f"[Linha {line}] Erro de compilação: {msg}")
        self.line = line


# ---------------------------------------------------------------------------
# Pré-processador: #define NOME valor
# ---------------------------------------------------------------------------

def _preprocess(source: str, base_dir: str | None = None,
                _guard_set: set | None = None,
                _shared_defines: dict | None = None) -> str:
    """Substitui #define simples, resolve #include \"file\" e remove diretivas de guarda.

    _shared_defines: dict compartilhado entre chamadas recursivas (#include) para que
    defines do header fiquem visíveis no arquivo que o inclui.
    """
    if _guard_set is None:
        _guard_set = set()
    if _shared_defines is None:
        _shared_defines = {}
    defines = _shared_defines   # compartilhado entre todos os arquivos
    out_lines: list[str] = []
    skip_depth  = 0   # nesting depth de #ifndef/#ifdef blocos a ignorar
    for raw_line in source.splitlines():
        stripped = raw_line.strip()
        # --- guardas de inclusão (#ifndef / #ifdef / #endif) ---
        if stripped.startswith("#ifndef") or stripped.startswith("#ifdef"):
            parts = stripped.split()
            guard = parts[1] if len(parts) > 1 else ""
            if stripped.startswith("#ifndef") and guard in _guard_set:
                skip_depth += 1
            # #ifdef: incluir bloco normalmente (não travamos)
            continue
        if stripped.startswith("#endif"):
            if skip_depth > 0:
                skip_depth -= 1
            continue
        if skip_depth > 0:
            continue
        # --- #define ---
        if stripped.startswith("#define"):
            parts = stripped.split(None, 2)
            if len(parts) >= 3:
                name_def = parts[1]
                # Remove comentários inline do valor (/* ... */ ou //)
                val = parts[2].strip()
                val = re.sub(r"/\*.*?\*/", "", val).strip()
                val = re.sub(r"//.*$", "", val).strip()
                defines[name_def] = val
                _guard_set.add(name_def)
            elif len(parts) == 2:
                defines[parts[1]] = "1"
                _guard_set.add(parts[1])
            continue
        # --- #include "file" ---
        if stripped.startswith("#include"):
            m_inc = re.match(r'#include\s+"([^"]+)"', stripped)
            if m_inc and base_dir:
                inc_path = os.path.join(base_dir, m_inc.group(1))
                try:
                    inc_text = open(inc_path, encoding="utf-8").read()
                    # Passa _shared_defines para propagar defines do header ao pai
                    inc_processed = _preprocess(inc_text, base_dir, _guard_set, defines)
                    out_lines.append(inc_processed)
                except FileNotFoundError:
                    pass  # silenciosamente ignora arquivos não encontrados
            continue
        # --- outras diretivas ---
        if stripped.startswith("#"):
            continue
        out_lines.append(raw_line)
    result = "\n".join(out_lines)
    # Aplica substituições de #define apenas fora de comentários C block (/* ... */)
    _BLOCK_CMT = re.compile(r"/\*[\s\S]*?\*/")
    def _apply_defines(text: str, defs: dict) -> str:
        parts: list[str] = []
        last = 0
        for m in _BLOCK_CMT.finditer(text):
            seg = text[last:m.start()]
            for nm in sorted(defs, key=len, reverse=True):
                seg = re.sub(r"\b" + re.escape(nm) + r"\b", defs[nm], seg)
            parts.append(seg)
            parts.append(m.group())   # mantém comentário intacto
            last = m.end()
        seg = text[last:]
        for nm in sorted(defs, key=len, reverse=True):
            seg = re.sub(r"\b" + re.escape(nm) + r"\b", defs[nm], seg)
        parts.append(seg)
        return "".join(parts)
    return _apply_defines(result, defines)


# ---------------------------------------------------------------------------
# Lexer minimalista
# ---------------------------------------------------------------------------

_LEX_SPEC = [
    ("COMMENT_LINE",  r"//[^\n]*"),
    ("COMMENT_BLOCK", r"/\*[\s\S]*?\*/"),
    ("STRLIT",   r'"(?:[^"\\]|\\.)*"'),               # literal de string: "texto"
    ("CHARLIT",  r"'(?:[^'\\]|\\[ntr\\0])'" ),        # literal de caractere: 'A', '\n'
    ("NUMBER",   r"\b(?:0x[0-9A-Fa-f]+|\d+)\b"),
    ("KEYWORD",  r"\b(?:int|if|else|while|for|break|continue|return|void|struct|char|unsigned)\b"),
    ("IDENT",    r"[A-Za-z_]\w*"),
    # Atribuições compostas — ANTES dos operadores simples para match ganancioso
    ("ASSIGNOP", r"\+=|-=|\*=|/=|%=|&=|\|=|\^=|<<=|>>="),
    # Operadores de 2 chars — antes dos de 1 char
    ("OP2",      r"==|!=|<=|>=|<<|>>|&&|\|\|"),
    # Operadores de 1 char — inclui % e &
    ("OP1",      r"[+\-*/=<>!~&|^%]"),
    ("SEMI",     r";"),
    ("COMMA",    r","),
    ("LPAREN",   r"\("),
    ("RPAREN",   r"\)"),
    ("LBRACE",   r"\{"),
    ("RBRACE",   r"\}"),
    ("LBRACKET", r"\["),
    ("RBRACKET", r"\]"),
    ("NL",       r"\n"),
    ("WS",       r"[ \t\r]+"),
]
_LEX_RE = re.compile("|".join(f"(?P<{n}>{p})" for n, p in _LEX_SPEC))


class Token:
    __slots__ = ("kind", "value", "line")
    def __init__(self, kind, value, line):
        self.kind  = kind
        self.value = value
        self.line  = line
    def __repr__(self):
        return f"<{self.kind} {self.value!r} L{self.line}>"


def _lex(source: str) -> list[Token]:
    tokens = []
    line   = 1
    for m in _LEX_RE.finditer(source):
        kind  = m.lastgroup
        value = m.group()
        if kind in ("WS", "COMMENT_LINE", "COMMENT_BLOCK"):
            line += value.count("\n")
            continue
        if kind == "NL":
            line += 1
            continue
        if kind == "STRLIT":
            # Preserva a string sem aspas externas como token STRLIT
            tokens.append(Token("STRLIT", value[1:-1], line))
            continue
        if kind == "NUMBER":
            tokens.append(Token(kind, str(int(value, 16 if value.lower().startswith("0x") else 10)), line))
            continue
        if kind == "CHARLIT":
            inner = value[1:-1]   # remove aspas simples externas
            _esc  = {'n': 10, 't': 9, 'r': 13, '\\': 92, '0': 0}
            val_int = _esc[inner[1]] if inner.startswith('\\') else ord(inner)
            tokens.append(Token("NUMBER", str(val_int), line))
            continue
        tokens.append(Token(kind, value, line))
    return tokens


# ---------------------------------------------------------------------------
# Parser recursivo descendente
# ---------------------------------------------------------------------------

class _Parser:
    def __init__(self, tokens: list[Token]):
        self._toks = tokens
        self._pos  = 0

    def _peek(self) -> Token | None:
        return self._toks[self._pos] if self._pos < len(self._toks) else None

    def _consume(self) -> Token:
        t = self._toks[self._pos]
        self._pos += 1
        return t

    def _expect(self, kind: str, value: str | None = None) -> Token:
        t = self._peek()
        if t is None or t.kind != kind or (value and t.value != value):
            exp = f"'{value}'" if value else kind
            got = repr(t) if t else "EOF"
            raise CompileError(f"Esperado {exp}, obteve {got}", t.line if t else 0)
        return self._consume()

    def _match(self, kind: str, value: str | None = None) -> bool:
        t = self._peek()
        return t is not None and t.kind == kind and (value is None or t.value == value)

    # ---- Programa / Funções ----

    def parse_program(self) -> Program:
        globs: list = []
        funcs: list[FuncDef] = []
        while self._peek():
            t = self._peek()
            if t and t.kind == "KEYWORD" and t.value in ("int", "void"):
                saved_pos = self._pos
                ret_type = self._consume()   # consome 'int'/'void'
                # verifica ponteiro em declaração global: int *nome ...
                is_ptr = False
                if self._match("OP1", "*"):
                    self._consume()
                    is_ptr = True
                name_tok = self._expect("IDENT")
                if self._match("LPAREN"):
                    # Função — volta e reprocessa
                    self._pos = saved_pos
                    f = self._parse_func()
                    if f is not None:
                        funcs.append(f)
                elif self._match("LBRACKET"):
                    # Array global: int nome[N] [= {...}] ;
                    self._consume()
                    size_tok = self._expect("NUMBER")
                    self._expect("RBRACKET")
                    init = None
                    if self._match("OP1", "="):
                        self._consume()
                        init = self._parse_brace_init()
                    self._expect("SEMI")
                    globs.append(GlobalArrayDecl(name_tok.value, int(size_tok.value), init, name_tok.line))
                else:
                    # Variável global simples
                    init = None
                    if self._match("OP1", "="):
                        self._consume()
                        init = self._parse_expr()
                    self._expect("SEMI")
                    globs.append(GlobalVarDecl(name_tok.value, init, name_tok.line, is_ptr))
            else:
                f = self._parse_func()
                if f is not None:
                    funcs.append(f)
        return Program(globs, funcs)

    def _parse_brace_init(self) -> list[Expr]:
        self._expect("LBRACE")
        items: list[Expr] = []
        while not self._match("RBRACE"):
            items.append(self._parse_expr())
            if self._match("COMMA"):
                self._consume()
        self._expect("RBRACE")
        return items

    def _parse_func(self) -> "FuncDef | None":
        ret_tok  = self._consume()   # int ou void
        name_tok = self._expect("IDENT")
        self._expect("LPAREN")
        params:  list[str]  = []
        is_ptrs: list[bool] = []
        # Lista de parâmetros vazia explícita: (void)
        if self._match("KEYWORD", "void") and self._pos + 1 < len(self._toks) and \
                self._toks[self._pos + 1].kind == "RPAREN":
            self._consume()   # void
        else:
            while not self._match("RPAREN"):
                # Aceita int, void*, char, unsigned como tipo de parâmetro
                if self._match("KEYWORD"):
                    self._consume()   # int/void/char/unsigned
                is_p = False
                while self._match("OP1", "*"):
                    self._consume()
                    is_p = True
                if self._match("RPAREN"):
                    break
                params.append(self._expect("IDENT").value)
                is_ptrs.append(is_p)
                if self._match("COMMA"):
                    self._consume()
        self._expect("RPAREN")
        # Declaração antecipada (forward declaration): int foo(params);
        if self._match("SEMI"):
            self._consume()
            return None   # ignorar — sem corpo
        body = self._parse_block()
        return FuncDef(name_tok.value, params, is_ptrs, body.stmts, name_tok.line)

    def _parse_block(self) -> Block:
        t = self._expect("LBRACE")
        stmts = []
        while not self._match("RBRACE"):
            stmts.append(self._parse_stmt())
        self._expect("RBRACE")
        return Block(stmts, t.line)

    # ---- Statements ----

    def _parse_stmt(self) -> Stmt:
        t = self._peek()
        if t is None:
            raise CompileError("Statement esperado mas EOF encontrado", 0)

        if t.kind == "KEYWORD" and t.value == "int":
            return self._parse_vardecl()
        if t.kind == "KEYWORD" and t.value == "if":
            return self._parse_if()
        if t.kind == "KEYWORD" and t.value == "while":
            return self._parse_while()
        if t.kind == "KEYWORD" and t.value == "for":
            return self._parse_for()
        if t.kind == "KEYWORD" and t.value == "break":
            line = t.line; self._consume(); self._expect("SEMI")
            return BreakStmt(line)
        if t.kind == "KEYWORD" and t.value == "continue":
            line = t.line; self._consume(); self._expect("SEMI")
            return ContinueStmt(line)
        if t.kind == "KEYWORD" and t.value == "return":
            return self._parse_return()
        if t.kind == "LBRACE":
            return self._parse_block()
        return self._parse_assign_or_expr()

    def _parse_vardecl(self) -> Stmt:
        line = self._peek().line
        self._expect("KEYWORD", "int")
        # Ponteiro: int *p
        is_ptr = False
        if self._match("OP1", "*"):
            self._consume()
            is_ptr = True
        name = self._expect("IDENT").value
        # Array: int a[N]
        if self._match("LBRACKET"):
            self._consume()
            size_tok = self._expect("NUMBER")
            self._expect("RBRACKET")
            init = None
            if self._match("OP1", "="):
                self._consume()
                init = self._parse_brace_init()
            self._expect("SEMI")
            return ArrayDecl(name, int(size_tok.value), init, line)
        init = None
        if self._match("OP1", "="):
            self._consume()
            init = self._parse_expr()
        self._expect("SEMI")
        return VarDecl(name, init, line, is_ptr)

    def _parse_if(self) -> IfStmt:
        line = self._peek().line
        self._expect("KEYWORD", "if")
        self._expect("LPAREN")
        cond = self._parse_expr()
        self._expect("RPAREN")
        then_b = self._parse_block().stmts
        else_b: list[Stmt] = []
        if self._match("KEYWORD", "else"):
            self._consume()
            if self._match("KEYWORD", "if"):
                else_b = [self._parse_if()]
            else:
                else_b = self._parse_block().stmts
        return IfStmt(cond, then_b, else_b, line)

    def _parse_while(self) -> WhileStmt:
        line = self._peek().line
        self._expect("KEYWORD", "while")
        self._expect("LPAREN")
        cond = self._parse_expr()
        self._expect("RPAREN")
        body = self._parse_block().stmts
        return WhileStmt(cond, body, line)

    def _parse_return(self) -> ReturnStmt:
        line = self._peek().line
        self._expect("KEYWORD", "return")
        val = None
        if not self._match("SEMI"):
            val = self._parse_expr()
        self._expect("SEMI")
        return ReturnStmt(val, line)

    def _parse_for(self) -> ForStmt:
        line = self._peek().line
        self._expect("KEYWORD", "for")
        self._expect("LPAREN")
        # init
        init: Stmt | None = None
        if not self._match("SEMI"):
            if self._match("KEYWORD", "int"):
                init = self._parse_vardecl()
            else:
                init = self._parse_assign_or_expr()
        else:
            self._expect("SEMI")
        # cond
        cond: Expr | None = None
        if not self._match("SEMI"):
            cond = self._parse_expr()
        self._expect("SEMI")
        # update — sem ';' final
        update: Stmt | None = None
        if not self._match("RPAREN"):
            update = self._parse_assign_or_expr(expect_semi=False)
        self._expect("RPAREN")
        body = self._parse_block().stmts
        return ForStmt(init, cond, update, body, line)

    def _parse_assign_or_expr(self, expect_semi: bool = True) -> Stmt:
        line = self._peek().line

        # DerefAssign: *expr op= expr
        if self._match("OP1", "*"):
            saved = self._pos
            self._consume()
            # tenta parsear o ptr como expressão unária/primária
            ptr_expr = self._parse_unary()
            if self._peek() and (self._peek().kind == "OP1" and self._peek().value == "=" and
                                  not self._match("OP2")):
                op = self._consume().value   # '='
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return DerefAssign(ptr_expr, op, val, line)
            if self._peek() and self._peek().kind == "ASSIGNOP":
                op = self._consume().value
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return DerefAssign(ptr_expr, op, val, line)
            # não é atribuição — volta e trata como expr_stmt
            self._pos = saved

        # Tentativa: IDENT [ '[' idx ']' ] (ASSIGNOP | '=') expr
        if self._match("IDENT"):
            name = self._peek().value
            saved = self._pos
            self._consume()

            # a[i] op= expr
            if self._match("LBRACKET"):
                self._consume()
                idx = self._parse_expr()
                self._expect("RBRACKET")
                if self._peek() and self._peek().kind == "ASSIGNOP":
                    op = self._consume().value
                    val = self._parse_expr()
                    if expect_semi:
                        self._expect("SEMI")
                    return ArrayAssign(name, idx, op, val, line)
                if self._match("OP1", "="):
                    self._consume()
                    val = self._parse_expr()
                    if expect_semi:
                        self._expect("SEMI")
                    return ArrayAssign(name, idx, "=", val, line)
                # não é atribuição — volta
                self._pos = saved

            # name ASSIGNOP expr
            elif self._peek() and self._peek().kind == "ASSIGNOP":
                op = self._consume().value
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return Assign(name, op, val, line)

            # name '=' expr  (mas não '==')
            elif self._match("OP1", "="):
                self._consume()
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return Assign(name, "=", val, line)

            else:
                # não era atribuição — volta o IDENT
                self._pos = saved

        expr = self._parse_expr()
        if expect_semi:
            self._expect("SEMI")
        return ExprStmt(expr, line)

    # ---- Expressões (precedência crescente) --------------------------------

    def _parse_expr(self) -> Expr:
        return self._parse_logical_or()

    def _parse_logical_or(self) -> Expr:
        left = self._parse_logical_and()
        while self._match("OP2", "||"):
            op    = self._consume().value
            right = self._parse_logical_and()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_logical_and(self) -> Expr:
        left = self._parse_bitwise_or()
        while self._match("OP2", "&&"):
            op    = self._consume().value
            right = self._parse_bitwise_or()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_bitwise_or(self) -> Expr:
        left = self._parse_bitwise_xor()
        while self._peek() and self._peek().kind == "OP1" and self._peek().value == "|":
            op    = self._consume().value
            right = self._parse_bitwise_xor()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_bitwise_xor(self) -> Expr:
        left = self._parse_bitwise_and()
        while self._peek() and self._peek().kind == "OP1" and self._peek().value == "^":
            op    = self._consume().value
            right = self._parse_bitwise_and()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_bitwise_and(self) -> Expr:
        left = self._parse_comparison()
        while self._peek() and self._peek().kind == "OP1" and self._peek().value == "&":
            op    = self._consume().value
            right = self._parse_comparison()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_comparison(self) -> Expr:
        left = self._parse_shift()
        while self._peek() and self._peek().kind in ("OP2", "OP1") and \
              self._peek().value in ("==", "!=", "<", ">", "<=", ">="):
            op    = self._consume().value
            right = self._parse_shift()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_shift(self) -> Expr:
        left = self._parse_additive()
        while self._peek() and self._peek().kind == "OP2" and \
              self._peek().value in ("<<", ">>"):
            op    = self._consume().value
            right = self._parse_additive()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_additive(self) -> Expr:
        left = self._parse_multiplicative()
        while self._match("OP1", "+") or self._match("OP1", "-"):
            op    = self._consume().value
            right = self._parse_multiplicative()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_multiplicative(self) -> Expr:
        left = self._parse_unary()
        while self._peek() and self._peek().kind == "OP1" and \
              self._peek().value in ("*", "/", "%"):
            op    = self._consume().value
            right = self._parse_unary()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_unary(self) -> Expr:
        t = self._peek()
        # Operadores unários aritméticos/lógicos
        if t and t.kind == "OP1" and t.value in ("-", "~", "!"):
            op  = self._consume().value
            operand = self._parse_unary()
            return UnaryOp(op, operand, t.line)
        # Dereference: *expr
        if t and t.kind == "OP1" and t.value == "*":
            self._consume()
            ptr = self._parse_unary()
            return Deref(ptr, t.line)
        # Address-of: &name  ou  &name[idx]
        if t and t.kind == "OP1" and t.value == "&":
            self._consume()
            name_tok = self._expect("IDENT")
            idx: Expr | None = None
            if self._match("LBRACKET"):
                self._consume()
                idx = self._parse_expr()
                self._expect("RBRACKET")
            return AddrOf(name_tok.value, idx, t.line)
        return self._parse_primary()

    def _parse_primary(self) -> Expr:
        t = self._peek()
        if t is None:
            raise CompileError("Expressão esperada mas EOF encontrado", 0)

        if t.kind == "NUMBER":
            self._consume()
            return IntLiteral(int(t.value), t.line)

        if t.kind == "STRLIT":
            self._consume()
            return StringLit(t.value, t.line)

        if t.kind == "IDENT":
            self._consume()
            # chamada de função?
            if self._match("LPAREN"):
                self._consume()
                args: list[Expr] = []
                while not self._match("RPAREN"):
                    args.append(self._parse_expr())
                    if self._match("COMMA"):
                        self._consume()
                self._expect("RPAREN")
                return FuncCall(t.value, args, t.line)
            # indexação de array: a[i]
            if self._match("LBRACKET"):
                self._consume()
                idx = self._parse_expr()
                self._expect("RBRACKET")
                return ArrayRef(t.value, idx, t.line)
            return VarRef(t.value, t.line)

        if t.kind == "LPAREN":
            self._consume()
            # Detecta cast: (int), (int *), (void *), (char), (unsigned) etc.
            saved_cast = self._pos
            if self._match("KEYWORD") and self._peek().value in ("int", "void", "char", "unsigned"):
                self._consume()   # consome tipo
                while self._match("OP1", "*"):
                    self._consume()  # consome *
                if self._match("RPAREN"):
                    self._consume()  # fecha o parêntese do cast
                    # Apenas ignora o cast e retorna a expressão seguinte
                    return self._parse_unary()
                # Não era um cast — restaura
                self._pos = saved_cast
            expr = self._parse_expr()
            self._expect("RPAREN")
            return expr

        raise CompileError(f"Token inesperado: {t}", t.line)


# ---------------------------------------------------------------------------
# Gerador de código assembly
# ---------------------------------------------------------------------------

class CodeGen:
    """
    Gera código assembly EduRISC-32v2 a partir do AST.

    Estratégia:
      - Variáveis locais são alocadas em registradores R2–R25.
      - R0  = zero hardwired.  R1 = retorno de função / arg 1.
      - R30 = SP, R31 = LR.
      - R26 = scratch temporário para comparações e endereços.
      - Argumentos passados em R1, R2, ... (máx 8 args).
      - Variáveis globais e arrays (locais e globais) armazenados em memória
        a partir de _GLOBAL_BASE_ADDR.
      - break/continue usam uma pilha de labels de loop.
      - && e || usam short-circuit com labels.
    """

    _MAX_REGS  = 29   # R1–R29 disponíveis (R30=SP, R31=LR, R0=zero hardwired)
    _FIRST_REG = 2    # alocação de locais começa em R2
    _FLAGS_TMP = 26   # R26 reservado como scratch de comparações/endereços

    # Endereço base para variáveis globais e arrays (max 0x7FFF para caber em MOVI signed16)
    _GLOBAL_BASE_ADDR = 0x4000

    def __init__(self):
        self._lines:    list[str]       = []
        self._var_reg:  dict[str, int]  = {}   # nome local → número de reg
        self._next_reg: int             = self._FIRST_REG
        self._label_cnt: int            = 0
        self._current_func_name: str    = ""
        # Pilha de (lbl_continue, lbl_break) para loops aninhados
        self._loop_stack: list[tuple[str, str]] = []
        # Variáveis globais simples: nome → endereço de memória
        self._globals:      dict[str, int]       = {}
        # Arrays (locais e globais): nome → (endereço_base, tamanho)
        self._arrays:       dict[str, tuple[int, int]] = {}
        self._global_next:  int = self._GLOBAL_BASE_ADDR
        # Tabela de strings interned: conteúdo → endereço
        self._strings:      dict[str, int]       = {}

    # ---- Interface pública ------------------------------------------------

    def compile(self, source: str, base_dir: str | None = None) -> str:
        """Recebe texto fonte, retorna string com código assembly.

        Args:
            source:   Código fonte C-like.
            base_dir: Diretório base para resolver #include "file" relativos.
        """
        source  = _preprocess(source, base_dir=base_dir)
        tokens  = _lex(source)
        parser  = _Parser(tokens)
        program = parser.parse_program()
        return self._gen_program(program)

    # ---- Geração de programa ----------------------------------------------

    def _gen_program(self, prog: Program) -> str:
        self._lines       = []
        self._label_cnt   = 0
        self._globals     = {}
        self._arrays      = {}
        self._global_next = self._GLOBAL_BASE_ADDR
        self._strings     = {}

        # Registra variáveis e arrays globais
        for gv in prog.globals:
            if isinstance(gv, GlobalArrayDecl):
                base = self._global_next
                self._arrays[gv.name] = (base, gv.size)
                self._global_next += gv.size
            else:
                addr = self._global_next
                self._globals[gv.name] = addr
                self._global_next += 1

        # Pula para main
        self._emit(".org 0x000000")
        self._emit("JMP MAIN")
        self._emit("")

        # Gera código de cada função
        for func in prog.functions:
            self._gen_func(func)

        # Emite seção de dados (globais e arrays globais)
        has_data = bool(self._globals) or any(
            n in self._arrays for gv in prog.globals
            if isinstance(gv, GlobalArrayDecl) for n in [gv.name]
        )
        if has_data or self._global_next > self._GLOBAL_BASE_ADDR:
            self._emit("; --- Dados globais ---")
            for gv in prog.globals:
                if isinstance(gv, GlobalArrayDecl):
                    base = self._arrays[gv.name][0]
                    self._emit(f".org 0x{base:06X}  ; array {gv.name}[{gv.size}]")
                    for i in range(gv.size):
                        val = 0
                        if gv.init and i < len(gv.init) and isinstance(gv.init[i], IntLiteral):
                            val = gv.init[i].value  # type: ignore[union-attr]
                        self._emit(f".word {val}  ; {gv.name}[{i}]")
                else:
                    addr = self._globals[gv.name]
                    val  = 0
                    if gv.init is not None and isinstance(gv.init, IntLiteral):
                        val = gv.init.value
                    self._emit(f".org 0x{addr:06X}")
                    self._emit(f".word {val}  ; global {gv.name}")

        self._emit("")
        # Emite strings interned na seção de dados
        if self._strings:
            self._emit("; --- Strings literais ---")
            _esc_map = {'n': 10, 't': 9, 'r': 13, '\\': 92, '0': 0, '"': 34, "'": 39}
            for raw, addr in self._strings.items():
                # Decodifica o raw para emitir .word por caractere
                decoded: list[int] = []
                i = 0
                while i < len(raw):
                    c = raw[i]
                    if c == '\\' and i + 1 < len(raw):
                        decoded.append(_esc_map.get(raw[i + 1], ord(raw[i + 1])))
                        i += 2
                    else:
                        decoded.append(ord(c))
                        i += 1
                decoded.append(0)
                self._emit(f".org 0x{addr:06X}  ; \"{raw[:20]}{'...' if len(raw)>20 else ''}\"")
                for ch in decoded:
                    self._emit(f".word {ch}")
        self._emit("")
        self._emit("; === FIM DO PROGRAMA ===")
        return "\n".join(self._lines)

    def _gen_func(self, func: FuncDef):
        self._var_reg  = {}
        self._next_reg = self._FIRST_REG
        self._current_func_name = func.name.upper()
        self._loop_stack = []

        self._emit(f"; --- Função {func.name} ---")
        self._emit(f"{func.name.upper()}:")

        # Aloca parâmetros: recebidos em R1, R2, ... (ABI simples)
        arg_start = 1
        for i, p in enumerate(func.params):
            arg_reg = arg_start + i
            if arg_reg > self._MAX_REGS:
                raise CompileError(f"Muitos parâmetros na função '{func.name}'", func.line)
            self._var_reg[p] = arg_reg
            self._emit(f"; param {p} → R{arg_reg}")
            if arg_reg >= self._next_reg:
                self._next_reg = arg_reg + 1

        for stmt in func.body:
            self._gen_stmt(stmt)

        # Fallthrough: HLT para main, RET para outras funções
        if func.name.upper() == "MAIN":
            self._emit("HLT")
        else:
            self._emit("RET")
        self._emit("")

    # ---- Statements -------------------------------------------------------

    def _gen_stmt(self, stmt: Stmt):
        match stmt:
            case VarDecl(name=name, init=init, line=line):
                reg = self._alloc_var(name, line)
                if init is not None:
                    r = self._gen_expr(init)
                    if r != reg:
                        self._emit(f"MOV R{reg}, R{r}  ; {name} = R{r}")
                self._free_temps()

            case ArrayDecl(name=name, size=size, init=init, line=line):
                # Aloca array em memória (segmento de dados fixo)
                base = self._global_next
                self._arrays[name] = (base, size)
                self._global_next += size
                if init:
                    for i, expr in enumerate(init):
                        r_val = self._gen_expr(expr)
                        r_adr = self._FLAGS_TMP
                        self._emit_load_imm(r_adr, base + i, f"&{name}[{i}]")
                        self._emit(f"SW   R{r_val}, 0(R{r_adr})  ; {name}[{i}] = init")
                self._free_temps()

            case Assign(name=name, op=op, value=value, line=line):
                self._gen_assign(name, op, value, line)
                self._free_temps()

            case ArrayAssign(name=name, index=index, op=op, value=value, line=line):
                self._gen_array_assign(name, index, op, value, line)
                self._free_temps()

            case DerefAssign(ptr=ptr, op=op, value=value, line=line):
                self._gen_deref_assign(ptr, op, value, line)
                self._free_temps()

            case IfStmt(cond=cond, then_body=then_b, else_body=else_b):
                self._gen_if(cond, then_b, else_b)

            case WhileStmt(cond=cond, body=body):
                self._gen_while(cond, body)

            case ForStmt(init=init, cond=cond, update=update, body=body):
                self._gen_for(init, cond, update, body)

            case ReturnStmt(value=val, line=line):
                if val is not None:
                    r = self._gen_expr(val)
                    if r != 1:
                        self._emit(f"MOV R1, R{r}  ; retorno em R1")
                if self._current_func_name == "MAIN":
                    self._emit("HLT")
                else:
                    self._emit("RET")
                self._free_temps()

            case BreakStmt(line=line):
                if not self._loop_stack:
                    raise CompileError("'break' fora de um loop", line)
                _, lbl_break = self._loop_stack[-1]
                self._emit(f"JMP {lbl_break}  ; break")

            case ContinueStmt(line=line):
                if not self._loop_stack:
                    raise CompileError("'continue' fora de um loop", line)
                lbl_cont, _ = self._loop_stack[-1]
                self._emit(f"JMP {lbl_cont}  ; continue")

            case ExprStmt(expr=expr):
                self._gen_expr(expr)
                self._free_temps()

            case Block(stmts=stmts):
                for s in stmts:
                    self._gen_stmt(s)

    # ---- Atribuições especializadas ----------------------------------------

    def _gen_assign(self, name: str, op: str, value: Expr, line: int):
        """Gera atribuição simples (=) ou composta (+=, -=, etc.) para variável escalar."""
        if name in self._globals:
            addr   = self._globals[name]
            r_addr = self._FLAGS_TMP
            self._emit_load_imm(r_addr, addr, f"&{name}")
            r_val  = self._gen_expr(value)
            if op == "=":
                self._emit(f"SW R{r_val}, 0(R{r_addr})  ; {name} = R{r_val}")
            else:
                r_cur = self._alloc_temp(line)
                self._emit(f"LW R{r_cur}, 0(R{r_addr})  ; {name} (atual)")
                asm_op = self._compound_op(op, line)
                self._emit(f"{asm_op} R{r_cur}, R{r_cur}, R{r_val}  ; {op}")
                self._emit(f"SW R{r_cur}, 0(R{r_addr})  ; {name} = resultado")
            return

        reg = self._get_or_alloc_var(name, line)
        if op == "=":
            if isinstance(value, BinOp) and value.op not in ("&&", "||"):
                self._gen_binop_into(value.op, value.left, value.right, value.line, reg)
            else:
                r = self._gen_expr(value)
                if r != reg:
                    self._emit(f"MOV R{reg}, R{r}  ; {name} = R{r}")
        else:
            r_val   = self._gen_expr(value)
            asm_op  = self._compound_op(op, line)
            self._emit(f"{asm_op} R{reg}, R{reg}, R{r_val}  ; {op}")

    def _gen_array_assign(self, name: str, index: Expr, op: str, value: Expr, line: int):
        """Gera atribuição a elemento de array ou ponteiro: name[index] op= value."""
        if name in self._arrays:
            r_addr = self._array_elem_addr(name, index, line)
        else:
            # Ponteiro local/global: ptr[i] ≡ *(ptr + i)
            r_ptr  = self._gen_expr(VarRef(name, line))
            r_idx  = self._gen_expr(index)
            r_addr = self._alloc_temp(line)
            self._emit(f"ADD  R{r_addr}, R{r_ptr}, R{r_idx}  ; {name}+idx")
        r_val  = self._gen_expr(value)
        if op == "=":
            self._emit(f"SW R{r_val}, 0(R{r_addr})  ; {name}[...] = R{r_val}")
        else:
            r_cur  = self._alloc_temp(line)
            self._emit(f"LW R{r_cur}, 0(R{r_addr})  ; {name}[...] atual")
            asm_op = self._compound_op(op, line)
            self._emit(f"{asm_op} R{r_cur}, R{r_cur}, R{r_val}  ; {op}")
            self._emit(f"SW R{r_cur}, 0(R{r_addr})  ; {name}[...] = resultado")

    def _gen_deref_assign(self, ptr: Expr, op: str, value: Expr, line: int):
        """Gera atribuição via ponteiro: *ptr op= value."""
        r_ptr = self._gen_expr(ptr)
        r_val = self._gen_expr(value)
        if op == "=":
            self._emit(f"SW R{r_val}, 0(R{r_ptr})  ; *ptr = R{r_val}")
        else:
            r_cur  = self._alloc_temp(line)
            self._emit(f"LW R{r_cur}, 0(R{r_ptr})  ; *ptr atual")
            asm_op = self._compound_op(op, line)
            self._emit(f"{asm_op} R{r_cur}, R{r_cur}, R{r_val}  ; {op}")
            self._emit(f"SW R{r_cur}, 0(R{r_ptr})  ; *ptr = resultado")

    def _array_elem_addr(self, name: str, index: Expr, line: int) -> int:
        """Calcula endereço de name[index] em um registrador; retorna nº do reg."""
        if name not in self._arrays:
            raise CompileError(f"Array não declarado: '{name}'", line)
        base, _size = self._arrays[name]
        r_adr = self._alloc_temp(line)
        if isinstance(index, IntLiteral):
            # Índice constante: calcula endereço diretamente
            addr = base + index.value
            self._emit_load_imm(r_adr, addr, f"&{name}[{index.value}]")
        else:
            # Índice dinâmico
            r_base = self._alloc_temp(line)
            r_idx  = self._gen_expr(index)
            self._emit_load_imm(r_base, base, f"base {name}")
            self._emit(f"ADD  R{r_adr}, R{r_base}, R{r_idx}  ; &{name}[idx]")
        return r_adr

    # ---- Controle de fluxo ------------------------------------------------

    def _gen_if(self, cond: Expr, then_b, else_b):
        lbl_else = self._new_label("ELSE")
        lbl_end  = self._new_label("ENDIF")

        r_cond = self._gen_expr(cond)
        self._emit(f"BEQ R{r_cond}, R0, {lbl_else}  ; if falso → else")

        for s in then_b:
            self._gen_stmt(s)

        if else_b:
            self._emit(f"JMP {lbl_end}")

        self._emit(f"{lbl_else}:")
        for s in else_b:
            self._gen_stmt(s)
        self._emit(f"{lbl_end}:")

    def _gen_while(self, cond: Expr, body):
        lbl_test = self._new_label("WHILE_TEST")
        lbl_end  = self._new_label("WHILE_END")

        self._loop_stack.append((lbl_test, lbl_end))
        self._emit(f"{lbl_test}:")
        r_cond = self._gen_expr(cond)
        self._emit(f"BEQ R{r_cond}, R0, {lbl_end}  ; enquanto falso → fim")

        for s in body:
            self._gen_stmt(s)

        self._emit(f"JMP {lbl_test}")
        self._emit(f"{lbl_end}:")
        self._loop_stack.pop()

    def _gen_for(self, init, cond, update, body):
        lbl_test = self._new_label("FOR_TEST")
        lbl_upd  = self._new_label("FOR_UPD")
        lbl_end  = self._new_label("FOR_END")

        if init is not None:
            self._gen_stmt(init)

        self._loop_stack.append((lbl_upd, lbl_end))

        self._emit(f"{lbl_test}:")
        if cond is not None:
            r_cond = self._gen_expr(cond)
            self._emit(f"BEQ R{r_cond}, R0, {lbl_end}  ; for: cond falsa → fim")

        for s in body:
            self._gen_stmt(s)

        self._emit(f"{lbl_upd}:")
        if update is not None:
            self._gen_stmt(update)

        self._emit(f"JMP {lbl_test}")
        self._emit(f"{lbl_end}:")
        self._loop_stack.pop()

    # ---- Expressões -------------------------------------------------------

    def _gen_expr(self, expr: Expr) -> int:
        """Gera código para expressão. Retorna número do registrador com resultado."""
        match expr:
            case IntLiteral(value=v, line=line):
                return self._load_literal(v, line)

            case VarRef(name=n, line=line):
                if n in self._globals:
                    addr  = self._globals[n]
                    r_adr = self._FLAGS_TMP
                    r_val = self._alloc_temp(line)
                    self._emit_load_imm(r_adr, addr, f"&{n}")
                    self._emit(f"LW   R{r_val}, 0(R{r_adr})   ; {n}")
                    return r_val
                return self._get_or_alloc_var(n, line)

            case ArrayRef(name=n, index=idx, line=line):
                if n in self._arrays:
                    r_adr = self._array_elem_addr(n, idx, line)
                else:
                    # Ponteiro local/global: ptr[i] ≡ *(ptr + i)
                    r_ptr = self._gen_expr(VarRef(n, line))
                    r_idx = self._gen_expr(idx)
                    r_adr = self._alloc_temp(line)
                    self._emit(f"ADD  R{r_adr}, R{r_ptr}, R{r_idx}  ; {n}+idx")
                r_val = self._alloc_temp(line)
                self._emit(f"LW   R{r_val}, 0(R{r_adr})  ; {n}[...]")
                return r_val

            case AddrOf(name=n, index=idx, line=line):
                # &n ou &n[idx]
                if idx is None:
                    # &variável escalar global
                    if n in self._globals:
                        addr  = self._globals[n]
                        r_adr = self._alloc_temp(line)
                        self._emit_load_imm(r_adr, addr, f"&{n}")
                        return r_adr
                    raise CompileError(f"'&' só suportado para globais e arrays: '{n}'", line)
                else:
                    # &arr[idx]
                    return self._array_elem_addr(n, idx, line)

            case Deref(ptr=ptr, line=line):
                r_ptr = self._gen_expr(ptr)
                r_val = self._alloc_temp(line)
                self._emit(f"LW   R{r_val}, 0(R{r_ptr})  ; *ptr")
                return r_val

            case BinOp(op=op, left=left, right=right, line=line):
                if op == "&&":
                    return self._gen_logical_and(left, right, line)
                if op == "||":
                    return self._gen_logical_or(left, right, line)
                return self._gen_binop(op, left, right, line)

            case UnaryOp(op=op, operand=operand, line=line):
                return self._gen_unary(op, operand, line)

            case FuncCall(name=name, args=args, line=line):
                # Salva registradores de variáveis locais que sobrepõem os args
                # (ABI simplificada: args em R1, R2, ...)
                for i, arg in enumerate(args):
                    r = self._gen_expr(arg)
                    arg_reg = 1 + i
                    if r != arg_reg:
                        self._emit(f"MOV R{arg_reg}, R{r}  ; arg{i+1}")
                self._emit(f"CALL {name.upper()}")
                return 1   # resultado em R1

            case StringLit(value=sv, line=line):
                # Aloca string na seção de dados e retorna seu endereço
                addr = self._intern_string(sv, line)
                r    = self._alloc_temp(line)
                self._emit_load_imm(r, addr, f"str@{addr:#x}")
                return r

            case _:
                raise CompileError(f"Expressão não suportada: {type(expr).__name__}", 0)

    def _gen_binop(self, op: str, left: Expr, right: Expr, line: int) -> int:
        return self._gen_binop_into(op, left, right, line, None)

    def _gen_binop_into(self, op: str, left: Expr, right: Expr, line: int, dest_reg) -> int:
        """Gera binop. Se dest_reg não for None, tenta usar como registrador destino."""
        rl = self._gen_expr(left)
        rr = self._gen_expr(right)
        rd = dest_reg if dest_reg is not None else self._alloc_temp(line)

        OP_MAP  = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "REM",
                   "<<": "SHL", ">>": "SHR",
                   "&": "AND", "|": "OR",  "^": "XOR"}
        CMP_OPS = {"==", "!=", "<", ">", "<=", ">="}

        if op in OP_MAP:
            self._emit(f"{OP_MAP[op]} R{rd}, R{rl}, R{rr}  ; {op}")
        elif op in CMP_OPS:
            match op:
                case "<":
                    self._emit(f"SLT R{rd}, R{rl}, R{rr}")
                    return rd
                case ">":
                    self._emit(f"SLT R{rd}, R{rr}, R{rl}")
                    return rd
                case "<=":
                    self._emit(f"SLT R{rd}, R{rr}, R{rl}  ; NOT (rr < rl) ↔ rl <= rr")
                    self._emit(f"XORI R{rd}, R{rd}, 1")
                    return rd
                case ">=":
                    self._emit(f"SLT R{rd}, R{rl}, R{rr}  ; NOT (rl < rr) ↔ rl >= rr")
                    self._emit(f"XORI R{rd}, R{rd}, 1")
                    return rd
                case _:
                    lbl_t = self._new_label("CMP_T")
                    lbl_e = self._new_label("CMP_E")
                    self._emit(f"SUB R{self._FLAGS_TMP}, R{rl}, R{rr}")
                    if op == "==":
                        self._emit(f"BEQ R{self._FLAGS_TMP}, R0, {lbl_t}")
                    else:  # "!="
                        self._emit(f"BNE R{self._FLAGS_TMP}, R0, {lbl_t}")
                    self._emit(f"MOVI R{rd}, 0")
                    self._emit(f"JMP {lbl_e}")
                    self._emit(f"{lbl_t}:")
                    self._emit(f"MOVI R{rd}, 1")
                    self._emit(f"{lbl_e}:")
        else:
            raise CompileError(f"Operador não suportado: '{op}'", line)

        return rd

    def _gen_logical_and(self, left: Expr, right: Expr, line: int) -> int:
        """&& com short-circuit: se left==0 não avalia right."""
        lbl_false = self._new_label("AND_FALSE")
        lbl_end   = self._new_label("AND_END")
        rd = self._alloc_temp(line)
        rl = self._gen_expr(left)
        self._emit(f"BEQ R{rl}, R0, {lbl_false}  ; && short-circuit")
        rr = self._gen_expr(right)
        self._emit(f"BEQ R{rr}, R0, {lbl_false}")
        self._emit(f"MOVI R{rd}, 1")
        self._emit(f"JMP {lbl_end}")
        self._emit(f"{lbl_false}:")
        self._emit(f"MOVI R{rd}, 0")
        self._emit(f"{lbl_end}:")
        return rd

    def _gen_logical_or(self, left: Expr, right: Expr, line: int) -> int:
        """|| com short-circuit: se left!=0 não avalia right."""
        lbl_true = self._new_label("OR_TRUE")
        lbl_end  = self._new_label("OR_END")
        rd = self._alloc_temp(line)
        rl = self._gen_expr(left)
        self._emit(f"BNE R{rl}, R0, {lbl_true}  ; || short-circuit")
        rr = self._gen_expr(right)
        self._emit(f"BNE R{rr}, R0, {lbl_true}")
        self._emit(f"MOVI R{rd}, 0")
        self._emit(f"JMP {lbl_end}")
        self._emit(f"{lbl_true}:")
        self._emit(f"MOVI R{rd}, 1")
        self._emit(f"{lbl_end}:")
        return rd

    def _gen_unary(self, op: str, operand: Expr, line: int) -> int:
        r  = self._gen_expr(operand)
        rd = self._alloc_temp(line)
        match op:
            case "-":
                self._emit(f"NEG R{rd}, R{r}")
            case "~":
                self._emit(f"NOT R{rd}, R{r}")
            case "!":
                lbl_one = self._new_label("NOT_ONE")
                lbl_end = self._new_label("NOT_END")
                self._emit(f"BEQ R{r}, R0, {lbl_one}")
                self._emit(f"MOVI R{rd}, 0")
                self._emit(f"JMP {lbl_end}")
                self._emit(f"{lbl_one}:")
                self._emit(f"MOVI R{rd}, 1")
                self._emit(f"{lbl_end}:")
        return rd

    # ---- Helpers ----------------------------------------------------------

    def _load_literal(self, value: int, line: int) -> int:
        """Carrega literal inteiro em registrador: MOVI (16 bits) ou MOVHI+ORI (32 bits)."""
        rd = self._alloc_temp(line)
        self._emit_load_imm(rd, value, f"literal {value}")
        return rd

    def _emit_load_imm(self, rd: int, value: int, comment: str = "") -> None:
        """Emite instruções para carregar `value` em R{rd} (sem alocar reg)."""
        cmt = f"  ; {comment}" if comment else ""
        if -32768 <= value <= 32767:
            self._emit(f"MOVI R{rd}, {value}{cmt}")
        else:
            upper = (value >> 11) & 0x1FFFFF
            lower = value & 0xFFFF
            self._emit(f"MOVHI R{rd}, 0x{upper:05X}{cmt}")
            if lower:
                self._emit(f"ORI   R{rd}, R{rd}, 0x{lower:04X}")

    def _compound_op(self, op: str, line: int) -> str:
        """Converte operador composto (+=, %=, <<=, ...) para mnemônico ASM."""
        _MAP = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "REM",
                "<<": "SHL", ">>": "SHR",
                "&": "AND", "|": "OR", "^": "XOR"}
        base = op[:-1]   # '+=' → '+'  ou  '<<=' → '<<'
        asm  = _MAP.get(base)
        if asm is None:
            raise CompileError(f"Operador composto não suportado: {op}", line)
        return asm

    def _alloc_var(self, name: str, line: int) -> int:
        if name in self._var_reg:
            return self._var_reg[name]
        if self._next_reg > self._MAX_REGS:
            raise CompileError(f"Muitas variáveis locais (máx {self._MAX_REGS})", line)
        reg = self._next_reg
        # Pula R26 (scratch reservado)
        if reg == self._FLAGS_TMP:
            self._next_reg += 1
            reg = self._next_reg
        self._next_reg += 1
        self._var_reg[name] = reg
        self._emit(f"; var {name} → R{reg}")
        return reg

    def _alloc_temp(self, line: int) -> int:
        """Aloca registrador temporário. NÃO registra em _var_reg (reciclado no próximo stmt)."""
        if self._next_reg > self._MAX_REGS:
            raise CompileError(f"Registradores temporários esgotados (máx {self._MAX_REGS})", line)
        reg = self._next_reg
        # Pula R26 (scratch reservado)
        if reg == self._FLAGS_TMP:
            self._next_reg += 1
            reg = self._next_reg
        self._next_reg += 1
        return reg

    def _free_temps(self):
        """Libera registradores temporários (não registrados em _var_reg).
        Reseta _next_reg para logo após o último registrador de variável declarada.
        """
        if self._var_reg:
            self._next_reg = max(self._var_reg.values()) + 1
        else:
            self._next_reg = self._FIRST_REG

    def _get_or_alloc_var(self, name: str, line: int) -> int:
        if name in self._var_reg:
            return self._var_reg[name]
        return self._alloc_var(name, line)

    def _emit(self, line: str):
        self._lines.append(line)

    def _new_label(self, prefix: str) -> str:
        lbl = f"{prefix}_{self._label_cnt}"
        self._label_cnt += 1
        return lbl

    def _intern_string(self, raw: str, line: int) -> int:
        """Registra string literal na tabela de strings e retorna seu endereço em memória.

        O conteúdo é armazenado como words de inteiros (1 char por word),
        terminado por 0 (null terminator). As strings são alocadas consecutivamente
        no segmento de dados a partir de _global_next.
        """
        if raw in self._strings:
            return self._strings[raw]
        # Decodifica escapes simples para gerar os bytes
        decoded: list[int] = []
        i = 0
        while i < len(raw):
            c = raw[i]
            if c == '\\' and i + 1 < len(raw):
                esc = raw[i + 1]
                decoded.append({'n': 10, 't': 9, 'r': 13, '\\': 92, '0': 0,
                                 '"': 34, "'": 39}.get(esc, ord(esc)))
                i += 2
            else:
                decoded.append(ord(c))
                i += 1
        decoded.append(0)   # null terminator
        addr = self._global_next
        self._global_next += len(decoded)
        self._strings[raw] = addr
        return addr


# ---------------------------------------------------------------------------
# Ponto de entrada principal
# ---------------------------------------------------------------------------

def compile_source(source: str) -> str:
    """Compila código C-like e retorna string assembly EduRISC-32v2."""
    cg = CodeGen()
    return cg.compile(source)


def parse_source(source: str):
    """Faz o parsing do codigo fonte e retorna o AST (Program)."""
    source  = _preprocess(source)
    tokens  = _lex(source)
    parser  = _Parser(tokens)
    return parser.parse_program()
