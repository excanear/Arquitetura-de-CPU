# Compilador EduRISC-32v2 — Guia de Referência

## Introdução

O compilador EduRISC-32v2 converte um subconjunto da linguagem C para código assembly EduRISC-32v2. É um compilador educacional de **passa única** (pré-processo → lexer → parser → gerador de código) sem otimizações.

### Funcionalidades suportadas

| Recurso                                          | Suporte        |
|--------------------------------------------------|:--------------:|
| Tipos: `int`, `int *` (ponteiro)                 | ✅             |
| Declaração de variáveis locais e globais          | ✅             |
| Atribuição simples `=`                            | ✅             |
| Atribuições compostas `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `\|=`, `^=`, `<<=`, `>>=` | ✅ |
| Aritmética: `+`, `-`, `*`, `/`, `%`              | ✅             |
| Shifts: `<<`, `>>`                               | ✅             |
| Bitwise: `&`, `\|`, `^`, `~`                     | ✅             |
| Lógicos com short-circuit: `&&`, `\|\|`, `!`     | ✅             |
| Comparação: `==`, `!=`, `<`, `>`, `<=`, `>=`     | ✅             |
| `if` / `else` / `else if`                        | ✅             |
| `while`                                          | ✅             |
| `for`                                            | ✅             |
| `break` / `continue`                             | ✅             |
| `return`                                         | ✅             |
| Funções com parâmetros (até 24)                  | ✅             |
| Funções void                                     | ✅             |
| Arrays 1-D: `int a[N]`, `a[i]`, `a[i] = expr`   | ✅             |
| Inicializadores de array: `int a[N] = {v1,...}`  | ✅             |
| Ponteiros: `int *p`, `*p`, `&var`, `*p = expr`   | ✅ (globais/arrays) |
| Literais hexadecimais: `0xFF`                    | ✅             |
| Pré-processamento: `#define NOME valor`          | ✅             |
| Variáveis globais                                | ✅             |
| Arrays globais                                   | ✅             |
| Recursão                                         | ❌ (ABI simples sem pilha de chamada completa) |
| `float`, `double`                                | ❌             |
| `struct`, `union`                                | ❌             |

---

## Uso

### Python API

```python
from compiler.compiler import compile_source

asm_code = compile_source("""
#define N 5

int soma(int n) {
    int acc = 0;
    while (n) {
        acc += n;
        n -= 1;
    }
    return acc;
}

int main() {
    int resultado = soma(N);
    return resultado;
}
""")
print(asm_code)
```

### Linha de Comando (via main.py)

```bash
python main.py compile programa.c          # imprime assembly na tela
python main.py compile programa.c -o prog.asm
python main.py build   programa.c -o prog.hex   # compila + monta
python main.py run     prog.asm                 # monta e executa
```

### Pipeline Completo (C → binário)

```bash
python main.py build programa.c -o programa.hex
```

Equivale a: `compile` → `assemble` → escreve `.hex`

---

## Linguagem C-like Suportada

### Tipos

- `int` — inteiro de 32 bits com sinal
- `int *` — ponteiro (endereço de 32 bits)
- `void` — tipo de retorno de função sem valor

```c
int x = 10;
int y;          // não inicializado = 0
int *p;         // ponteiro
int arr[5];     // array de 5 inteiros
```

### Pré-processamento: `#define`

```c
#define N   10
#define MAX 0xFF

int main() {
    int x = N;        // equivale a  int x = 10;
    int y = MAX & 15; // equivale a  int y = 0xFF & 15;
    return y;         // → 15
}
```

### Expressões Aritméticas

```c
int a = x + y;
int b = x * 3;
int c = (a + b) / 2;
int d = a % 7;     // módulo (resto)
```

Operadores:
- `+` → `ADD`     |  `-` → `SUB`
- `*` → `MUL`     |  `/` → `DIV` (inteiro)
- `%` → `REM` (resto)

### Shifts

```c
int a = x << 3;    // deslocamento lógico à esquerda
int b = x >> 1;    // deslocamento lógico à direita
x <<= 2;           // atribuição composta
```

Operadores: `<<` → `SHL`, `>>` → `SHR`

### Bitwise

```c
int a = x & 0xFF;   // AND
int b = x | 0x80;   // OR
int c = x ^ 0x55;   // XOR
int d = ~x;         // NOT
```

### Operadores Lógicos (Short-Circuit)

```c
int ok = (a > 0) && (b > 0);   // && com short-circuit
int any = (a != 0) || (b != 0); // || com short-circuit
int nok = !a;                    // negação lógica
```

> `&&` e `||` geram código com short-circuit: o operando direito **não** é avaliado se o resultado já é determinado pelo esquerdo.

### Comparações

Retornam 1 (verdadeiro) ou 0 (falso):

```c
if (x == 5) { ... }
while (n != 0) { ... }
if (a <= b && b <= c) { ... }
```

### Atribuições Compostas

```c
x += 5;     // x = x + 5
x -= 3;     // x = x - 3
x *= 2;     // x = x * 2
x /= 4;     // x = x / 4
x %= 7;     // x = x % 7
x &= 0xF;   // x = x & 0xF
x |= 0x1;   // x = x | 0x1
x ^= 0xFF;  // x = x ^ 0xFF
x <<= 2;    // x = x << 2
x >>= 1;    // x = x >> 1
```

### Controle de Fluxo

```c
if (cond) {
    // então
} else if (outra_cond) {
    // senão se
} else {
    // senão (opcional)
}
```

```c
while (cond) {
    // corpo
    break;      // sai do loop
    continue;   // vai para o próximo ciclo
}
```

```c
for (int i = 0; i < 10; i += 1) {
    // corpo
}
```

### Arrays 1-D

```c
int arr[5];              // declaração sem inicialização
int v[3] = {10, 20, 30}; // com inicializador

arr[0] = 42;             // escrita
int x = arr[2];          // leitura

// índice dinâmico
int i = 2;
arr[i] = arr[i - 1] + 1;
```

> Arrays são alocados no segmento de dados a partir do endereço `0x4000`.

### Ponteiros

```c
int g = 10;
int arr[4] = {1, 2, 3, 4};

int *p;
p = &g;          // endereço de variável global
p = &arr[2];     // endereço de elemento de array

int x = *p;      // leitura via ponteiro
*p = 99;         // escrita via ponteiro
```

> `&` só é suportado para variáveis globais e elementos de arrays.

### Funções

```c
int quadrado(int n) {
    return n * n;
}

void zera(int *p) {
    *p = 0;
}

int main() {
    int x = quadrado(7);   // R1=resultado
    zera(&x);              // passagem de ponteiro
    return x;              // → 0
}
```

- Argumentos passados em R1, R2, ... (até 24 parâmetros)
- Valor de retorno em R1
- Funções `void` não definem R1

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
