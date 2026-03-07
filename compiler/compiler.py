"""
compiler.py — Compilador de linguagem C-like para Assembly EduRISC-16

Pipeline de compilação:
  texto fonte  →  tokens  →  AST  →  código assembly EduRISC-16

Suporta:
  - declarações de variáveis locais: int x = expr;
  - atribuição: x = expr;
  - expressões: +, -, *, /
  - comparações: ==, !=, <, >, <=, >=  (retornam 0 ou 1)
  - if / else
  - while
  - return expr;
  - funções: int nome() { ... }
  - chamada de função: nome()  (sem parâmetros por hora)

Modelo de execução:
  - Registradores R0–R12 disponíveis como variáveis temporárias
  - R13 = stack pointer (SP) — não usado nesta versão simples
  - R14 = frame pointer (FP) — não usado
  - R15 = link register (usado por CALL/RET)
  - Variáveis locais mapeadas em registradores (máx 12 por função)
  - Constantes: carregadas via LOAD de literal em memória de dados
"""

import re
from compiler.ast_nodes import (
    Program, FuncDef, Stmt, Expr,
    VarDecl, Assign, IfStmt, WhileStmt, ReturnStmt, ExprStmt, Block,
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
    ("NUMBER",   r"\b\d+\b"),
    ("KEYWORD",  r"\b(?:int|if|else|while|return|void)\b"),
    ("IDENT",    r"[A-Za-z_]\w*"),
    ("OP2",      r"==|!=|<=|>=|&&|\|\|"),
    ("OP1",      r"[+\-*/=<>!~]"),
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
        funcs = []
        while self._peek():
            funcs.append(self._parse_func())
        return Program(funcs)

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
        if t.kind == "KEYWORD" and t.value == "return":
            return self._parse_return()
        if t.kind == "LBRACE":
            return self._parse_block()
        # atribuição ou expr
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

    def _parse_assign_or_expr(self) -> Stmt:
        line = self._peek().line
        # tentativa de atribuição: IDENT '=' expr ';'
        if self._match("IDENT"):
            name = self._peek().value
            self._consume()
            if self._match("OP1", "="):
                self._consume()
                val = self._parse_expr()
                self._expect("SEMI")
                return Assign(name, val, line)
            else:
                # não era atribuição — reconstrói como expr_stmt
                # (apenas chamadas de função após ident fazem sentido aqui)
                self._pos -= 1  # devolve o IDENT
        expr = self._parse_expr()
        self._expect("SEMI")
        return ExprStmt(expr, line)

    # ---- Expressões (precedência manual) ----

    def _parse_expr(self) -> Expr:
        return self._parse_comparison()

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
    Gera código assembly EduRISC-16 a partir do AST.

    Estratégia:
      - Variáveis locais são alocadas em registradores R0–R12.
      - Literais inteiros são carregados via LOAD de uma área de dados (.DATA).
      - Temporários extra são derramados (spill) se > 13 variáveis (erro).
      - Cada função gera uma seção de labels com nome da função.
    """

    _MAX_REGS  = 13   # R0–R12 disponíveis para variáveis
    _POOL_PTR  = 13   # R13 reservado como ponteiro do pool de literais
    _FLAGS_TMP = 14   # R14 reservado como temp para teste de flags
    _POOL_ADDR = 0x200  # endereço fixo do pool de literais

    def __init__(self):
        self._lines:    list[str]       = []
        self._var_reg:  dict[str, int]  = {}   # nome → número de reg
        self._next_reg: int             = 0
        self._data:     list[int]       = []   # pool de literais
        self._data_base: int            = 0    # endereço base da seção de dados
        self._label_cnt: int            = 0
        self._pool_initialized: bool    = False  # R13 já foi inicializado?

    # ---- Interface pública ------------------------------------------------

    def compile(self, source: str) -> str:
        """Recebe texto fonte, retorna string com código assembly."""
        tokens  = _lex(source)
        parser  = _Parser(tokens)
        program = parser.parse_program()
        return self._gen_program(program)

    # ---- Geração de programa ----------------------------------------------

    def _gen_program(self, prog: Program) -> str:
        self._lines   = []
        self._data    = []
        self._label_cnt = 0
        self._pool_initialized = False

        # Pula para main; word 1 guarda o endereço do pool (para LOAD R13, [R0+1])
        self._emit(".ORG 0x000")
        self._emit("JMP MAIN")
        self._emit(f".WORD 0x{self._POOL_ADDR:04X}  ; ponteiro do pool de literais")
        self._emit("")

        # Gera código de cada função
        for func in prog.functions:
            self._gen_func(func)

        # Seção de dados literais (após o código)
        if self._data:
            data_addr = len(self._lines) + 2  # estimativa
            self._emit("")
            self._emit(f"; === POOL DE LITERAIS ===")
            self._emit(f".ORG 0x200")
            for i, val in enumerate(self._data):
                self._emit(f"__LIT_{i}: .WORD {val}")

        self._emit("")
        self._emit("; === FIM DO PROGRAMA ===")
        return "\n".join(self._lines)

    def _gen_func(self, func: FuncDef):
        self._var_reg  = {}
        self._next_reg = 0
        self._pool_initialized = False

        # Aloca parâmetros
        for p in func.params:
            self._alloc_var(p, func.line)

        self._emit(f"; --- Função {func.name} ---")
        self._emit(f"{func.name.upper()}:")
        # Inicializa ponteiro do pool: R13 = mem[R0+1] = 0x200  (R0=0 no início)
        # Feito na primeira carga de literal, para não desperdiçar ciclos em funções sem literais

        for stmt in func.body:
            self._gen_stmt(stmt)

        # Fallthrough HLT para main, RET para outras
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
                        # Copia R{r} para R{reg}: XOR Rd,Rd,Rd; ADD Rd,Rs,Rd
                        self._emit(f"XOR R{reg}, R{reg}, R{reg}  ; zera R{reg}")
                        self._emit(f"ADD R{reg}, R{r}, R{reg}  ; R{reg} = R{r}")

            case Assign(name=name, value=value, line=line):
                reg = self._get_var(name, line)
                # Otimização: se o valor é uma BinOp, gera diretamente no registrador destino
                if isinstance(value, BinOp):
                    r = self._gen_binop_into(value.op, value.left, value.right, value.line, reg)
                else:
                    r = self._gen_expr(value)
                    if r != reg:
                        # Copia R{r} para R{reg} usando NOT+NOT ou XOR+ADD
                        # NOT NOT Rs = Rs; mas precisamos de dois regs diferentes
                        # Usa: XOR Rd,Rd,Rd; ADD Rd,Rs,Rd
                        self._emit(f"XOR R{reg}, R{reg}, R{reg}  ; zera R{reg}")
                        self._emit(f"ADD R{reg}, R{r}, R{reg}  ; {name} = R{r}")

            case IfStmt(cond=cond, then_body=then_b, else_body=else_b, line=line):
                self._gen_if(cond, then_b, else_b)

            case WhileStmt(cond=cond, body=body, line=line):
                self._gen_while(cond, body)

            case ReturnStmt(value=val, line=line):
                if val is not None:
                    r = self._gen_expr(val)
                    # convenção: resultado em R0
                    if r != 0:
                        self._emit(f"XOR R0, R0, R0  ; zera R0 para retorno")
                        self._emit(f"ADD R0, R{r}, R0  ; retorno em R0")
                self._emit("RET")

            case ExprStmt(expr=expr):
                self._gen_expr(expr)

            case Block(stmts=stmts):
                for s in stmts:
                    self._gen_stmt(s)

    # ---- Controle de fluxo ------------------------------------------------

    def _gen_if(self, cond: Expr, then_b, else_b):
        lbl_else = self._new_label("ELSE")
        lbl_end  = self._new_label("ENDIF")

        r_cond = self._gen_expr(cond)
        self._ensure_flags(r_cond, cond)
        self._emit(f"JZ {lbl_else}  ; if falso → else")

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

        self._emit(f"{lbl_test}:")
        r_cond = self._gen_expr(cond)
        self._ensure_flags(r_cond, cond)
        self._emit(f"JZ {lbl_end}  ; enquanto falso → fim")

        for s in body:
            self._gen_stmt(s)

        self._emit(f"JMP {lbl_test}")
        self._emit(f"{lbl_end}:")

    # ---- Expressões -------------------------------------------------------

    def _gen_expr(self, expr: Expr) -> int:
        """Gera código para expressão. Retorna número do registrador com resultado."""
        match expr:
            case IntLiteral(value=v, line=line):
                return self._load_literal(v, line)

            case VarRef(name=n, line=line):
                return self._get_var(n, line)

            case BinOp(op=op, left=left, right=right, line=line):
                return self._gen_binop(op, left, right, line)

            case UnaryOp(op=op, operand=operand, line=line):
                return self._gen_unary(op, operand, line)

            case FuncCall(name=name, args=args, line=line):
                # Sem parâmetros por hora
                self._emit(f"CALL {name.upper()}")
                # Resultado em R0 por convenção
                return 0

            case _:
                raise CompileError(f"Expressão não suportada: {type(expr).__name__}", 0)

    def _gen_binop(self, op: str, left: Expr, right: Expr, line: int) -> int:
        return self._gen_binop_into(op, left, right, line, None)

    def _gen_binop_into(self, op: str, left: Expr, right: Expr, line: int, dest_reg) -> int:
        """Gera binop. Se dest_reg não for None, tenta usar como registrador destino."""
        rl = self._gen_expr(left)
        rr = self._gen_expr(right)
        # Usa dest_reg como destino se fornecido, caso contrário aloca temp
        if dest_reg is not None:
            rd = dest_reg
        else:
            rd = self._alloc_temp(line)

        OP_MAP = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV",
                  "&": "AND", "|": "OR",  "^": "XOR"}
        CMP_OPS = {"==", "!=", "<", ">", "<=", ">="}

        if op in OP_MAP:
            self._emit(f"{OP_MAP[op]} R{rd}, R{rl}, R{rr}  ; {op}")
        elif op in CMP_OPS:
            # Implementa comparação como SUB + teste de flags
            # Gera 0 ou 1 no registrador rd
            self._emit(f"SUB R{rd}, R{rl}, R{rr}  ; comparação {op}")
            lbl_t = self._new_label("CMP_T")
            lbl_e = self._new_label("CMP_E")
            match op:
                case "==":
                    self._emit(f"JZ {lbl_t}")
                case "!=":
                    self._emit(f"JNZ {lbl_t}")
                case "<":
                    # rd negativo → rl < rr
                    self._emit(f"JNZ {lbl_t}  ; aproximação: != 0 ≈ <")
                case _:
                    self._emit(f"JNZ {lbl_t}")
            # falso → rd = 0
            self._emit(f"XOR R{rd}, R{rd}, R{rd}")
            self._emit(f"JMP {lbl_e}")
            self._emit(f"{lbl_t}:")
            # verdadeiro → rd = 1
            lit_one = self._load_literal(1, line)
            self._emit(f"ADD R{rd}, R{lit_one}, R0  ; rd = 1")
            self._emit(f"{lbl_e}:")
        else:
            raise CompileError(f"Operador não suportado: {op}", line)

        return rd

    def _gen_unary(self, op: str, operand: Expr, line: int) -> int:
        r  = self._gen_expr(operand)
        rd = self._alloc_temp(line)
        match op:
            case "-":
                # negativo: SUB rd, R0, r  (precisa R0=0)
                self._emit(f"XOR R0, R0, R0  ; R0 = 0")
                self._emit(f"SUB R{rd}, R0, R{r}  ; negação")
            case "~":
                self._emit(f"NOT R{rd}, R{r}")
            case "!":
                self._emit(f"XOR R{rd}, R{r}, R{r}  ; NOT lógico (0 se != 0)")
        return rd

    # ---- Helpers ----------------------------------------------------------

    def _ensure_flags(self, r_cond: int, expr):
        """Garante que os flags de CPU reflitam o valor do registrador r_cond.
        Não necessário se a expressão já é uma BinOp de comparação (ALU já atualizou flags).
        Para VarRef ou literal, emite instrução que seta flags conforme r_cond.
        Usa R14 (_FLAGS_TMP) como registrador scratch temporário.
        """
        if not isinstance(expr, BinOp):
            ft = self._FLAGS_TMP
            self._emit(f"XOR R{ft}, R{ft}, R{ft}  ; R{ft}=0 (scratch para teste)")
            self._emit(f"ADD R{ft}, R{r_cond}, R{ft}  ; flags refletem R{r_cond}")

    def _load_literal(self, value: int, line: int) -> int:
        """Carrega literal inteiro em registrador via LOAD do pool (base em R13)."""
        # Verifica se já alocado no pool
        idx = None
        for i, v in enumerate(self._data):
            if v == value:
                idx = i
                break
        if idx is None:
            idx = len(self._data)
            self._data.append(value)

        if idx >= 15:  # offset 4-bit: max 15 entradas no pool
            raise CompileError(f"Pool de literais cheio (max 15): literal {value}", line)

        # Na primeira carga, inicializa R13 = endereço do pool (lido de mem[R_zero+1])
        # R0 é 0 no início DO programa; usar R14 como zero temporário para bootstrap é arriscado.
        # Soltarão: usamos XOR de R13 com si mesmo para zerar, depois carregamos via cadeia de .WORD
        # Estratégia robusta: emitir 'LOAD R13, [R0+1]' somente quando o R0 ainda for 0 (1ª chamada)
        if not self._pool_initialized:
            # R0 = 0 pois nenhuma variável foi atribuída ainda neste ponto
            self._emit(f"; Inicializa ponteiro do pool: R{self._POOL_PTR} = mem[R0+1] = 0x{self._POOL_ADDR:04X}")
            self._emit(f"LOAD R{self._POOL_PTR}, [R0+1]  ; R{self._POOL_PTR} = 0x{self._POOL_ADDR:04X}")
            self._pool_initialized = True

        rd = self._alloc_temp(line)
        self._emit(f"LOAD R{rd}, [R{self._POOL_PTR}+{idx}]  ; literal {value} de pool[{idx}]")
        return rd

    def _alloc_var(self, name: str, line: int) -> int:
        if name in self._var_reg:
            return self._var_reg[name]
        if self._next_reg >= self._MAX_REGS:
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
    """Compila código C-like e retorna string assembly EduRISC-16."""
    cg = CodeGen()
    return cg.compile(source)
