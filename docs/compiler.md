# Compilador EduRISC-16 — Guia de Referência

## Introdução

O compilador EduRISC-16 converte um subconjunto da linguagem C para código assembly EduRISC-16. É um compilador educacional de **passa única** (lexer → parser → gerador de código) sem otimizações.

### Funcionalidades suportadas

| Recurso                         | Suporte |
|---------------------------------|:-------:|
| Tipos: `int`                    | ✅      |
| Declaração de variáveis         | ✅      |
| Atribuição                      | ✅      |
| Aritmética: `+`, `-`, `*`, `/`  | ✅      |
| Comparação: `==`, `!=`, `<`, `>`, `<=`, `>=` | ✅ |
| `if` / `else`                   | ✅      |
| `while`                         | ✅      |
| `return`                        | ✅      |
| Funções sem parâmetros          | ✅      |
| Funções com parâmetros          | ✅ (até 12) |
| Arrays                          | ❌      |
| Ponteiros                       | ❌      |
| `for` loop                      | ❌ (use `while`) |
| Recursão                        | ❌ (sem pilha de chamada) |

---

## Uso

### Python API

```python
from compiler import compile_source

asm_code = compile_source("""
int soma(int n) {
    int acc = 0;
    while (n) {
        acc = acc + n;
        n = n - 1;
    }
    return acc;
}

int main() {
    int resultado = soma(5);
    return resultado;
}
""")
print(asm_code)
```

### Linha de Comando (via main.py)

```bash
python main.py compile programa.c
python main.py compile programa.c -o programa.asm
python main.py compile --show-ast programa.c
```

### Pipeline Completo (C → binário)

```bash
python main.py build programa.c -o programa.hex
```

Equivale a: `compile` → `assemble` → escreve `.hex`

---

## Linguagem C-like Suportada

### Tipos

Apenas `int` (inteiro sem sinal de 16 bits, 0–65535):

```c
int x = 10;
int y;          // não inicializado = 0
```

### Expressões Aritméticas

```c
int a = x + y;
int b = x * 3;     // cuidado: 16 bits (truncado)
int c = (a + b) * 2;
```

Operadores:
- `+` → `ADD`
- `-` → `SUB`
- `*` → `MUL`
- `/` → `DIV` (inteiro, divisão por zero = 0xFFFF)

### Comparações

Retornam 1 (verdadeiro) ou 0 (falso):

```c
if (x == 5) { ... }
while (n != 0) { ... }
```

### Controle de Fluxo

```c
if (cond) {
    // então
} else {
    // senão (opcional)
}
```

```c
while (cond) {
    // corpo
}
```

> **Não** existe `for`, `do-while`, `break`, `continue`. Use `while` com controle manual.

### Funções

```c
int quadrado(int n) {
    return n * n;
}

int main() {
    int x = quadrado(4);
    return x;
}
```

- Máximo de **12 variáveis locais** por função
- Resultado de retorno em `R0` (convenção)
- `R15` é o link register (salvo automaticamente por `CALL`)
- Funções sem `return` explícito emitem `RET` no final

---

## Modelo de Compilação

### Mapeamento de Variáveis

Variáveis locais são mapeadas em registradores R0–R12:

```
Variável   Registrador
---------  -----------
n          R0
acc        R1
resultado  R2
__tmp0     R3     ← temporários gerados pelo compilador
__tmp1     R4
...
```

### Código Gerado — Exemplo

Entrada C:
```c
int soma(int n) {
    int acc = 0;
    while (n) {
        acc = acc + n;
        n = n - 1;
    }
    return acc;
}
```

Assembly gerado:
```asm
; --- Função soma ---
; var n → R0
; var acc → R1
SOMA:
    ; acc = 0
    XOR R0, R0, R0        ; R0 = 0 (temporário zero)
    ADD R1, R0, R0        ; acc = 0

WHILE_TEST_0:
    ; testa n (R0)
    XOR R2, R0, R0        ; R2 = n (para testar)
    JZ WHILE_END_1        ; while falso → fim

    ; acc = acc + n
    ADD R1, R1, R0        ; acc += n
    ; n = n - 1
    LOAD R3, __LIT_0      ; carrega literal 1
    SUB R0, R0, R3        ; n--
    JMP WHILE_TEST_0

WHILE_END_1:
    ; return acc
    ADD R0, R1, R0        ; R0 = acc (retorno)
    RET
```

### Geração de Labels

O compilador gera labels únicos incrementais:
- `WHILE_TEST_N`, `WHILE_END_N`
- `IF_ELSE_N`, `IF_ENDIF_N`
- `CMP_T_N`, `CMP_E_N` (para comparações)
- `__LIT_N` (pool de literais)

### Pool de Literais

Constantes inteiras são armazenadas em uma seção de dados após o código:

```asm
.ORG 0x200
__LIT_0: .WORD 1
__LIT_1: .WORD 5
__LIT_2: .WORD 100
```

Acesso via `LOAD Rd, [R0+N]` com R0=0 e N = índice do literal.

---

## Limitações e Erros

| Erro                                          | Causa                                     |
|-----------------------------------------------|-------------------------------------------|
| `Muitas variáveis locais (máx 13)`            | Função usa mais de 13 variáveis           |
| `Variável não declarada: 'x'`                 | Variável usada sem `int x = ...`          |
| `Operador não suportado: %`                   | Módulo não implementado                   |
| `Token inesperado: <KEYWORD 'for'>`           | `for` não suportado (use `while`)         |
| `Esperado '}' obteve EOF`                     | Chaves desbalanceadas                     |

---

## Fluxo Interno do Compilador

```
Código C
    │
    ▼ Lexer (_lex)
Tokens (KEYWORD, IDENT, NUMBER, OP1, OP2, SEMI, ...)
    │
    ▼ Parser recursivo descendente (_Parser)
AST (Program → FuncDef → Block → Stmt → Expr)
    │
    ▼ CodeGen
Linhas de Assembly (list[str])
    │
    ▼ str.join("\n")
String de Assembly completa
    │
    ▼ (opcional) Assembler
Binário EduRISC-16
```

### Nós do AST

```
Program
└── FuncDef(name, params, body)
    └── Block(stmts)
        ├── VarDecl(name, init?)
        ├── Assign(name, value)
        ├── IfStmt(cond, then_body, else_body?)
        ├── WhileStmt(cond, body)
        ├── ReturnStmt(value?)
        └── ExprStmt(expr)
            └── Expr:
                ├── IntLiteral(value)
                ├── VarRef(name)
                ├── BinOp(op, left, right)
                ├── UnaryOp(op, operand)
                └── FuncCall(name, args)
```

---

## Exemplo Completo: Fibonacci

```c
int fib(int n) {
    int a = 0;
    int b = 1;
    while (n) {
        int tmp = a + b;
        a = b;
        b = tmp;
        n = n - 1;
    }
    return a;
}

int main() {
    int resultado = fib(8);
    return resultado;
}
```

Resultado esperado: fib(8) = **21**.
