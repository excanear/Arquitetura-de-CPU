"""
compiler.py — Compilador de linguagem C-like para Assembly EduRISC-32v2

Pipeline de compilação:
  texto fonte  →  tokens  →  AST  →  código assembly EduRISC-32v2

Suporta:
  - variáveis locais e globais: int x = expr;
  - atribuição simples (=) e composta (+=, -=, *=, /=, &=, |=, ^=)
  - expressões: +, -, *, /, &, |, ^, ~, !
  - comparações: ==, !=, <, >, <=, >=  (retornam 0 ou 1)
  - if / else
  - while / for
  - break / continue
  - return expr;
  - funções: int/void nome(int p1, int p2, ...) { ... }
  - chamada de função com argumentos (passados em registradores)

Modelo de execução:
  - R0  = zero hardwired (constante 0)
  - R1  = valor de retorno de função (convenção ABI)
  - R2–R25 disponíveis como variáveis locais / temporários
  - R30 = SP (stack pointer), R31 = LR (link register)
  - Argumentos passados em R1, R2, ... (convenção simples de registrador)
  - Variáveis globais armazenadas em posições de memória fixas
"""

import re
from compiler.ast_nodes import (
    Program, GlobalVarDecl, FuncDef, Stmt, Expr,
    VarDecl, Assign, IfStmt, WhileStmt, ForStmt,
    ReturnStmt, BreakStmt, ContinueStmt, ExprStmt, Block,
    IntLiteral, VarRef, BinOp, UnaryOp, FuncCall,
)


# ---------------------------------------------------------------------------
# Erros
# ---------------------------------------------------------------------------

class CompileError(Exception):
    def __init__(self, msg: str, line: int = 0):
        super().__init__(f"[Linha {line}] Erro de compilação: {msg}")
        self.line = line


# ---------------------------------------------------------------------------
# Lexer minimalista
# ---------------------------------------------------------------------------

_LEX_SPEC = [
    ("COMMENT_LINE",  r"//[^\n]*"),
    ("COMMENT_BLOCK", r"/\*[\s\S]*?\*/"),
    ("NUMBER",   r"\b(?:0x[0-9A-Fa-f]+|\d+)\b"),
    ("KEYWORD",  r"\b(?:int|if|else|while|for|break|continue|return|void)\b"),
    ("IDENT",    r"[A-Za-z_]\w*"),
    ("ASSIGNOP", r"\+=|-=|\*=|/=|&=|\|=|\^="),   # atribuições compostas
    ("OP2",      r"==|!=|<=|>=|&&|\|\|"),
    ("OP1",      r"[+\-*/=<>!~&|^]"),
    ("SEMI",     r";"),
    ("COMMA",    r","),
    ("LPAREN",   r"\("),
    ("RPAREN",   r"\)"),
    ("LBRACE",   r"\{"),
    ("RBRACE",   r"\}"),
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
        if kind == "NUMBER":
            # Normaliza literais numéricos (suporte a hex 0x...)
            tokens.append(Token(kind, str(int(value, 16 if value.startswith("0x") or value.startswith("0X") else 10)), line))
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
        globs: list[GlobalVarDecl] = []
        funcs: list[FuncDef]       = []
        while self._peek():
            t = self._peek()
            # Variável global: int nome [= expr] ;   (sem parêntese após nome)
            if t and t.kind == "KEYWORD" and t.value in ("int", "void"):
                # Look-ahead: keyword IDENT ... → função se próximo de IDENT for '('
                saved_pos = self._pos
                self._consume()  # consome 'int'/'void'
                name_tok = self._expect("IDENT")
                if self._match("LPAREN"):
                    # É uma função — volta para reprocessar corretamente
                    self._pos = saved_pos
                    funcs.append(self._parse_func())
                else:
                    # É variável global
                    init = None
                    if self._match("OP1", "="):
                        self._consume()
                        init = self._parse_expr()
                    self._expect("SEMI")
                    globs.append(GlobalVarDecl(name_tok.value, init, name_tok.line))
            else:
                funcs.append(self._parse_func())
        return Program(globs, funcs)

    def _parse_func(self) -> FuncDef:
        # int ou void
        ret_tok = self._consume()
        name_tok = self._expect("IDENT")
        self._expect("LPAREN")
        params = []
        while not self._match("RPAREN"):
            self._expect("KEYWORD", "int")
            params.append(self._expect("IDENT").value)
            if self._match("COMMA"):
                self._consume()
        self._expect("RPAREN")
        body = self._parse_block()
        return FuncDef(name_tok.value, params, body.stmts, name_tok.line)

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
        # atribuição (simples ou composta) ou expr
        return self._parse_assign_or_expr()

    def _parse_vardecl(self) -> VarDecl:
        line = self._peek().line
        self._expect("KEYWORD", "int")
        name = self._expect("IDENT").value
        init = None
        if self._match("OP1", "="):
            self._consume()
            init = self._parse_expr()
        self._expect("SEMI")
        return VarDecl(name, init, line)

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
        # update — sem ';' final; consome até ')'
        update: Stmt | None = None
        if not self._match("RPAREN"):
            update = self._parse_assign_or_expr(expect_semi=False)
        self._expect("RPAREN")
        body = self._parse_block().stmts
        return ForStmt(init, cond, update, body, line)

    def _parse_assign_or_expr(self, expect_semi: bool = True) -> Stmt:
        line = self._peek().line
        # tentativa de atribuição: IDENT ('=' | ASSIGNOP) expr ';'
        if self._match("IDENT"):
            name = self._peek().value
            self._consume()
            # atribuição composta: +=, -=, *=, /=, &=, |=, ^=
            if self._peek() and self._peek().kind == "ASSIGNOP":
                op = self._consume().value   # ex: '+='
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return Assign(name, op, val, line)
            # atribuição simples
            if self._match("OP1", "="):
                self._consume()
                val = self._parse_expr()
                if expect_semi:
                    self._expect("SEMI")
                return Assign(name, "=", val, line)
            else:
                # não era atribuição — devolve o IDENT e trata como expr_stmt
                self._pos -= 1
        expr = self._parse_expr()
        if expect_semi:
            self._expect("SEMI")
        return ExprStmt(expr, line)

    # ---- Expressões (precedência manual) ----

    def _parse_expr(self) -> Expr:
        return self._parse_bitwise()

    def _parse_bitwise(self) -> Expr:
        left = self._parse_comparison()
        while self._peek() and self._peek().kind == "OP1" and \
              self._peek().value in ("&", "|", "^"):
            op    = self._consume().value
            right = self._parse_comparison()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_comparison(self) -> Expr:
        left = self._parse_additive()
        while self._peek() and self._peek().kind in ("OP2", "OP1") and \
              self._peek().value in ("==", "!=", "<", ">", "<=", ">="):
            op   = self._consume().value
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
        while self._match("OP1", "*") or self._match("OP1", "/"):
            op    = self._consume().value
            right = self._parse_unary()
            left  = BinOp(op, left, right, left.line)
        return left

    def _parse_unary(self) -> Expr:
        t = self._peek()
        if t and t.kind == "OP1" and t.value in ("-", "~", "!"):
            op  = self._consume().value
            operand = self._parse_unary()
            return UnaryOp(op, operand, t.line)
        return self._parse_primary()

    def _parse_primary(self) -> Expr:
        t = self._peek()
        if t is None:
            raise CompileError("Expressão esperada mas EOF encontrado", 0)

        if t.kind == "NUMBER":
            self._consume()
            return IntLiteral(int(t.value), t.line)

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
            return VarRef(t.value, t.line)

        if t.kind == "LPAREN":
            self._consume()
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
      - R26 = scratch temporário para comparações.
      - Argumentos passados em R1, R2, ... (máx 8 args).
      - Variáveis globais: armazenadas em posições de memória no segmento de dados.
      - Literais inteiros ≤ 16 bits → MOVI;  > 16 bits → MOVHI + ORI.
      - break/continue usam uma pilha de labels de loop.
    """

    _MAX_REGS  = 25   # R1–R25 disponíveis (R0=zero, R26=scratch, R27-R29=livres, R30=SP, R31=LR)
    _FIRST_REG = 2    # alocação de locais começa em R2 (R1 = retorno / arg1)
    _FLAGS_TMP = 26   # R26 reservado como scratch temporário de comparações

    # Endereço base para variáveis globais (segmento de dados separado do código)
    _GLOBAL_BASE_ADDR = 0x8000

    def __init__(self):
        self._lines:    list[str]       = []
        self._var_reg:  dict[str, int]  = {}   # nome local → número de reg
        self._next_reg: int             = self._FIRST_REG
        self._label_cnt: int            = 0
        self._current_func_name: str    = ""
        # Pilha de (lbl_continue, lbl_break) para loops aninhados
        self._loop_stack: list[tuple[str, str]] = []
        # Variáveis globais: nome → endereço de memória
        self._globals:     dict[str, int] = {}
        self._global_next: int            = self._GLOBAL_BASE_ADDR

    # ---- Interface pública ------------------------------------------------

    def compile(self, source: str) -> str:
        """Recebe texto fonte, retorna string com código assembly."""
        tokens  = _lex(source)
        parser  = _Parser(tokens)
        program = parser.parse_program()
        return self._gen_program(program)

    # ---- Geração de programa ----------------------------------------------

    def _gen_program(self, prog: Program) -> str:
        self._lines     = []
        self._label_cnt = 0
        self._globals   = {}
        self._global_next = self._GLOBAL_BASE_ADDR

        # Registra variáveis globais (endereços serão emitidos ao final)
        for gv in prog.globals:
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

        # Inicializa variáveis globais (seção de dados ao final)
        if self._globals:
            self._emit("; --- Dados globais ---")
            for gv in prog.globals:
                addr = self._globals[gv.name]
                val  = 0
                if gv.init is not None and isinstance(gv.init, IntLiteral):
                    val = gv.init.value
                self._emit(f".org 0x{addr:06X}")
                self._emit(f".word {val}  ; global {gv.name}")

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

            case Assign(name=name, op=op, value=value, line=line):
                self._gen_assign(name, op, value, line)

            case IfStmt(cond=cond, then_body=then_b, else_body=else_b, line=line):
                self._gen_if(cond, then_b, else_b)

            case WhileStmt(cond=cond, body=body, line=line):
                self._gen_while(cond, body)

            case ForStmt(init=init, cond=cond, update=update, body=body, line=line):
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

            case Block(stmts=stmts):
                for s in stmts:
                    self._gen_stmt(s)

    # ---- Geração de atribuição -------------------------------------------

    def _gen_assign(self, name: str, op: str, value: Expr, line: int):
        """Gera atribuição simples (=) ou composta (+=, -=, etc.)."""
        # Verifica se é global ou local
        if name in self._globals:
            # Variável global: carrega endereço, opera e armazena
            addr = self._globals[name]
            r_addr = self._alloc_temp(line)
            self._emit(f"MOVI R{r_addr}, 0x{addr:04X}  ; &{name}")
            r_val  = self._gen_expr(value)
            if op == "=":
                self._emit(f"SW R{r_val}, 0(R{r_addr})  ; {name} = R{r_val}")
            else:
                r_cur = self._alloc_temp(line)
                self._emit(f"LW R{r_cur}, 0(R{r_addr})  ; {name} (atual)")
                base_op = op[:-1]   # '+=' → '+'
                OP_MAP  = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV",
                           "&": "AND", "|": "OR",  "^": "XOR"}
                asm_op  = OP_MAP.get(base_op)
                if asm_op is None:
                    raise CompileError(f"Operador composto não suportado: {op}", line)
                self._emit(f"{asm_op} R{r_cur}, R{r_cur}, R{r_val}  ; {op}")
                self._emit(f"SW R{r_cur}, 0(R{r_addr})  ; {name} = resultado")
            return

        # Variável local
        reg = self._get_or_alloc_var(name, line)
        if op == "=":
            if isinstance(value, BinOp):
                self._gen_binop_into(value.op, value.left, value.right, value.line, reg)
            else:
                r = self._gen_expr(value)
                if r != reg:
                    self._emit(f"MOV R{reg}, R{r}  ; {name} = R{r}")
        else:
            # Atribuição composta: nome op= expr  →  nome = nome op expr
            r_val  = self._gen_expr(value)
            base_op = op[:-1]   # '+=' → '+'
            OP_MAP  = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV",
                       "&": "AND", "|": "OR",  "^": "XOR"}
            asm_op  = OP_MAP.get(base_op)
            if asm_op is None:
                raise CompileError(f"Operador composto não suportado: {op}", line)
            self._emit(f"{asm_op} R{reg}, R{reg}, R{r_val}  ; {op}")

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

        # init
        if init is not None:
            self._gen_stmt(init)

        self._loop_stack.append((lbl_upd, lbl_end))

        self._emit(f"{lbl_test}:")
        if cond is not None:
            r_cond = self._gen_expr(cond)
            self._emit(f"BEQ R{r_cond}, R0, {lbl_end}  ; for: cond falsa → fim")

        for s in body:
            self._gen_stmt(s)

        # continue salta para o update
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
                # Verifica se é global
                if n in self._globals:
                    addr  = self._globals[n]
                    r_adr = self._alloc_temp(line)
                    r_val = self._alloc_temp(line)
                    self._emit(f"MOVI R{r_adr}, 0x{addr:04X}  ; &{n}")
                    self._emit(f"LW   R{r_val}, 0(R{r_adr})   ; {n}")
                    return r_val
                return self._get_or_alloc_var(n, line)

            case BinOp(op=op, left=left, right=right, line=line):
                return self._gen_binop(op, left, right, line)

            case UnaryOp(op=op, operand=operand, line=line):
                return self._gen_unary(op, operand, line)

            case FuncCall(name=name, args=args, line=line):
                # Passa argumentos em R1, R2, ...
                for i, arg in enumerate(args):
                    r = self._gen_expr(arg)
                    arg_reg = 1 + i
                    if r != arg_reg:
                        self._emit(f"MOV R{arg_reg}, R{r}  ; arg{i+1}")
                self._emit(f"CALL {name.upper()}")
                # Resultado em R1 por convenção ABI
                return 1

            case _:
                raise CompileError(f"Expressão não suportada: {type(expr).__name__}", 0)

    def _gen_binop(self, op: str, left: Expr, right: Expr, line: int) -> int:
        return self._gen_binop_into(op, left, right, line, None)

    def _gen_binop_into(self, op: str, left: Expr, right: Expr, line: int, dest_reg) -> int:
        """Gera binop. Se dest_reg não for None, tenta usar como registrador destino."""
        rl = self._gen_expr(left)
        rr = self._gen_expr(right)
        rd = dest_reg if dest_reg is not None else self._alloc_temp(line)

        OP_MAP  = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV",
                   "&": "AND", "|": "OR",  "^": "XOR"}
        CMP_OPS = {"==", "!=", "<", ">", "<=", ">="}

        if op in OP_MAP:
            self._emit(f"{OP_MAP[op]} R{rd}, R{rl}, R{rr}  ; {op}")
        elif op in CMP_OPS:
            ft = self._FLAGS_TMP
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
                    self._emit(f"SUB R{ft}, R{rl}, R{rr}")
                    if op == "==":
                        self._emit(f"BEQ R{ft}, R0, {lbl_t}")
                    else:  # "!="
                        self._emit(f"BNE R{ft}, R0, {lbl_t}")
                    self._emit(f"MOVI R{rd}, 0")
                    self._emit(f"JMP {lbl_e}")
                    self._emit(f"{lbl_t}:")
                    self._emit(f"MOVI R{rd}, 1")
                    self._emit(f"{lbl_e}:")
        else:
            raise CompileError(f"Operador não suportado: '{op}'", line)

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
        if -32768 <= value <= 32767:
            self._emit(f"MOVI R{rd}, {value}  ; literal {value}")
        else:
            upper = (value >> 11) & 0x1FFFFF
            lower = value & 0xFFFF
            self._emit(f"MOVHI R{rd}, 0x{upper:05X}  ; literal {value} (upper)")
            if lower:
                self._emit(f"ORI   R{rd}, R{rd}, 0x{lower:04X}  ; literal (lower)")
        return rd

    def _alloc_var(self, name: str, line: int) -> int:
        if name in self._var_reg:
            return self._var_reg[name]
        if self._next_reg > self._MAX_REGS:
            raise CompileError(f"Muitas variáveis locais (máx {self._MAX_REGS})", line)
        reg = self._next_reg
        self._next_reg += 1
        self._var_reg[name] = reg
        self._emit(f"; var {name} → R{reg}")
        return reg

    def _alloc_temp(self, line: int) -> int:
        return self._alloc_var(f"__tmp{self._next_reg}", line)

    def _get_var(self, name: str, line: int) -> int:
        if name not in self._var_reg:
            raise CompileError(f"Variável não declarada: '{name}'", line)
        return self._var_reg[name]

    def _get_or_alloc_var(self, name: str, line: int) -> int:
        """Retorna reg se já alocado, aloca novo se não existir."""
        if name in self._var_reg:
            return self._var_reg[name]
        return self._alloc_var(name, line)

    def _emit(self, line: str):
        self._lines.append(line)

    def _new_label(self, prefix: str) -> str:
        lbl = f"{prefix}_{self._label_cnt}"
        self._label_cnt += 1
        return lbl


# ---------------------------------------------------------------------------
# Ponto de entrada principal
# ---------------------------------------------------------------------------

def compile_source(source: str) -> str:
    """Compila código C-like e retorna string assembly EduRISC-32v2."""
    cg = CodeGen()
    return cg.compile(source)


def parse_source(source: str):
    """Faz o parsing do codigo fonte e retorna o AST (Program)."""
    tokens  = _lex(source)
    parser  = _Parser(tokens)
    return parser.parse_program()
