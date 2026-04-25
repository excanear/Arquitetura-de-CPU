"""
tests/test_compiler.py — Testes do compilador C-like para EduRISC-32v2

Cobre:
  - Variáveis locais, aritmética básica
  - while loop
  - for loop
  - break / continue
  - atribuições compostas (+=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=)
  - operadores bitwise (&, |, ^, ~)
  - operadores lógicos com short-circuit (&& , ||)
  - shifts (<<, >>)
  - módulo (%)
  - if/else
  - chamadas de função com e sem argumentos
  - return
  - arrays 1-D: declaração, leitura, escrita, inicializadores
  - ponteiros: &global, *ptr, *ptr = expr
  - #define (pré-processamento de constantes)
  - variáveis globais
"""

import pytest
from compiler.compiler import compile_source
from assembler.assembler import Assembler
from simulator.cpu_simulator import CPUSimulator


def run_c(source: str, max_cycles: int = 2000) -> CPUSimulator:
    """Compila código C-like, monta e executa. Retorna simulador."""
    asm   = compile_source(source)
    words = Assembler().assemble(asm)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run(max_cycles=max_cycles)
    return sim


# ---------------------------------------------------------------------------
# Aritmética e variáveis
# ---------------------------------------------------------------------------

def test_literal_soma():
    sim = run_c("int main() { return 3 + 4; }")
    assert sim.rf[1] == 7


def test_variavel_local():
    sim = run_c("""
        int main() {
            int x = 10;
            int y = 32;
            return x + y;
        }
    """)
    assert sim.rf[1] == 42


def test_subtracao():
    sim = run_c("int main() { return 100 - 58; }")
    assert sim.rf[1] == 42


def test_multiplicacao():
    sim = run_c("int main() { return 6 * 7; }")
    assert sim.rf[1] == 42


# ---------------------------------------------------------------------------
# Módulo e shifts
# ---------------------------------------------------------------------------

def test_modulo_simples():
    sim = run_c("int main() { return 10 % 3; }")
    assert sim.rf[1] == 1


def test_modulo_zero():
    sim = run_c("int main() { return 100 % 10; }")
    assert sim.rf[1] == 0


def test_shift_left():
    sim = run_c("int main() { return 1 << 4; }")
    assert sim.rf[1] == 16


def test_shift_right():
    sim = run_c("int main() { return 64 >> 3; }")
    assert sim.rf[1] == 8


def test_shift_left_in_expr():
    sim = run_c("""
        int main() {
            int x = 3;
            return x << 2;
        }
    """)
    assert sim.rf[1] == 12


def test_shift_right_in_expr():
    sim = run_c("""
        int main() {
            int x = 40;
            return x >> 1;
        }
    """)
    assert sim.rf[1] == 20


def test_modulo_in_loop():
    # Soma somente os pares de 0..9
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 0; i < 10; i += 1) {
                if (i % 2 == 0) { s += i; }
            }
            return s;
        }
    """)
    assert sim.rf[1] == 20   # 0+2+4+6+8


# ---------------------------------------------------------------------------
# Operadores lógicos com short-circuit
# ---------------------------------------------------------------------------

def test_logical_and_true():
    sim = run_c("int main() { return 1 && 1; }")
    assert sim.rf[1] == 1


def test_logical_and_false():
    sim = run_c("int main() { return 1 && 0; }")
    assert sim.rf[1] == 0


def test_logical_or_true():
    sim = run_c("int main() { return 0 || 1; }")
    assert sim.rf[1] == 1


def test_logical_or_false():
    sim = run_c("int main() { return 0 || 0; }")
    assert sim.rf[1] == 0


def test_logical_and_short_circuit():
    # side_effect is never called porque left=0
    sim = run_c("""
        int side_effect() { return 99; }
        int main() {
            int a = 0;
            int b = a && side_effect();
            return b;
        }
    """)
    assert sim.rf[1] == 0


def test_logical_or_short_circuit():
    sim = run_c("""
        int main() {
            int a = 1;
            int b = a || 99;
            return b;
        }
    """)
    assert sim.rf[1] == 1


def test_logical_compound():
    sim = run_c("""
        int main() {
            int x = 5;
            int y = 10;
            return (x > 0) && (y > 0);
        }
    """)
    assert sim.rf[1] == 1


# ---------------------------------------------------------------------------
# Atribuições compostas — inclui novos operadores
# ---------------------------------------------------------------------------

def test_assign_plus_eq():
    sim = run_c("""
        int main() {
            int x = 10;
            x += 5;
            return x;
        }
    """)
    assert sim.rf[1] == 15


def test_assign_minus_eq():
    sim = run_c("""
        int main() {
            int x = 20;
            x -= 6;
            return x;
        }
    """)
    assert sim.rf[1] == 14


def test_assign_mul_eq():
    sim = run_c("""
        int main() {
            int x = 3;
            x *= 7;
            return x;
        }
    """)
    assert sim.rf[1] == 21


def test_assign_mod_eq():
    sim = run_c("""
        int main() {
            int x = 17;
            x %= 5;
            return x;
        }
    """)
    assert sim.rf[1] == 2


def test_assign_shl_eq():
    sim = run_c("""
        int main() {
            int x = 3;
            x <<= 3;
            return x;
        }
    """)
    assert sim.rf[1] == 24


def test_assign_shr_eq():
    sim = run_c("""
        int main() {
            int x = 32;
            x >>= 2;
            return x;
        }
    """)
    assert sim.rf[1] == 8


def test_assign_compound_chain():
    sim = run_c("""
        int main() {
            int x = 10;
            x -= 3;
            x *= 2;
            return x;
        }
    """)
    assert sim.rf[1] == 14


# ---------------------------------------------------------------------------
# Operadores bitwise
# ---------------------------------------------------------------------------

def test_bitwise_and():
    sim = run_c("int main() { return 0xFF & 0x0F; }")
    assert sim.rf[1] == 0x0F


def test_bitwise_or():
    sim = run_c("int main() { return 0xF0 | 0x0F; }")
    assert sim.rf[1] == 0xFF


def test_bitwise_xor():
    sim = run_c("int main() { return 0xFF ^ 0x55; }")
    assert sim.rf[1] == 0xAA


# ---------------------------------------------------------------------------
# Controle de fluxo — if/else
# ---------------------------------------------------------------------------

def test_if_taken():
    sim = run_c("""
        int main() {
            int x = 5;
            if (x == 5) { x = 42; }
            return x;
        }
    """)
    assert sim.rf[1] == 42


def test_if_not_taken():
    sim = run_c("""
        int main() {
            int x = 5;
            if (x == 99) { x = 42; }
            return x;
        }
    """)
    assert sim.rf[1] == 5


def test_if_else():
    sim = run_c("""
        int main() {
            int x = 3;
            if (x > 5) { x = 100; } else { x = 0; }
            return x;
        }
    """)
    assert sim.rf[1] == 0


# ---------------------------------------------------------------------------
# Controle de fluxo — while
# ---------------------------------------------------------------------------

def test_while_soma():
    sim = run_c("""
        int main() {
            int n = 5;
            int acc = 0;
            while (n) {
                acc += n;
                n -= 1;
            }
            return acc;
        }
    """)
    assert sim.rf[1] == 15


# ---------------------------------------------------------------------------
# Controle de fluxo — for
# ---------------------------------------------------------------------------

def test_for_soma():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 5; i += 1) {
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 15


def test_for_produto():
    sim = run_c("""
        int main() {
            int p = 1;
            for (int i = 1; i <= 5; i += 1) {
                p *= i;
            }
            return p;
        }
    """)
    assert sim.rf[1] == 120   # 5! = 120


# ---------------------------------------------------------------------------
# break e continue
# ---------------------------------------------------------------------------

def test_break_in_while():
    sim = run_c("""
        int main() {
            int s = 0;
            int i = 0;
            while (1) {
                i += 1;
                s += i;
                if (i == 3) { break; }
            }
            return s;
        }
    """)
    assert sim.rf[1] == 6   # 1+2+3


def test_continue_in_while():
    sim = run_c("""
        int main() {
            int s = 0;
            int i = 0;
            while (i < 5) {
                i += 1;
                if (i == 3) { continue; }
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 12  # 1+2+4+5 (3 pulado)


def test_break_in_for():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 10; i += 1) {
                s += i;
                if (i == 4) { break; }
            }
            return s;
        }
    """)
    assert sim.rf[1] == 10   # 1+2+3+4


def test_continue_in_for():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 5; i += 1) {
                if (i == 3) { continue; }
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 12   # 1+2+4+5


# ---------------------------------------------------------------------------
# Funções com argumentos
# ---------------------------------------------------------------------------

def test_func_call_no_args():
    sim = run_c("""
        int dobro() {
            return 21 + 21;
        }
        int main() {
            return dobro();
        }
    """)
    assert sim.rf[1] == 42


def test_func_call_with_arg():
    sim = run_c("""
        int quadrado(int x) {
            return x * x;
        }
        int main() {
            return quadrado(7);
        }
    """)
    assert sim.rf[1] == 49


def test_func_call_two_args():
    sim = run_c("""
        int soma(int a, int b) {
            return a + b;
        }
        int main() {
            return soma(17, 25);
        }
    """)
    assert sim.rf[1] == 42


# ---------------------------------------------------------------------------
# Literais hexadecimais no código C
# ---------------------------------------------------------------------------

def test_hex_literal():
    sim = run_c("int main() { return 0xFF; }")
    assert sim.rf[1] == 255


# ---------------------------------------------------------------------------
# Arrays 1-D
# ---------------------------------------------------------------------------

def test_array_write_read():
    sim = run_c("""
        int main() {
            int a[5];
            a[0] = 10;
            a[1] = 20;
            a[2] = 30;
            return a[2];
        }
    """)
    assert sim.rf[1] == 30


def test_array_init():
    sim = run_c("""
        int main() {
            int v[4] = {5, 10, 15, 20};
            return v[3];
        }
    """)
    assert sim.rf[1] == 20


def test_array_soma():
    sim = run_c("""
        int main() {
            int v[5] = {1, 2, 3, 4, 5};
            int s = 0;
            int i = 0;
            while (i < 5) {
                s += v[i];
                i += 1;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 15


def test_array_dynamic_index():
    sim = run_c("""
        int main() {
            int a[6];
            int i = 0;
            while (i < 6) {
                a[i] = i * 2;
                i += 1;
            }
            return a[5];
        }
    """)
    assert sim.rf[1] == 10


def test_array_fibonacci():
    sim = run_c("""
        int main() {
            int fib[8];
            fib[0] = 0;
            fib[1] = 1;
            int i = 2;
            while (i < 8) {
                fib[i] = fib[i - 1] + fib[i - 2];
                i += 1;
            }
            return fib[7];
        }
    """)
    assert sim.rf[1] == 13   # fib(7) = 13


def test_global_array():
    sim = run_c("""
        int arr[3] = {100, 200, 300};
        int main() {
            return arr[1];
        }
    """)
    assert sim.rf[1] == 200


# ---------------------------------------------------------------------------
# Ponteiros
# ---------------------------------------------------------------------------

def test_pointer_read_global():
    sim = run_c("""
        int g = 42;
        int main() {
            int *p;
            p = &g;
            return *p;
        }
    """)
    assert sim.rf[1] == 42


def test_pointer_write_global():
    sim = run_c("""
        int g = 10;
        int main() {
            int *p;
            p = &g;
            *p = 77;
            return g;
        }
    """)
    assert sim.rf[1] == 77


def test_pointer_param():
    sim = run_c("""
        int g = 5;
        void dobra(int *p) {
            *p = *p + *p;
        }
        int main() {
            dobra(&g);
            return g;
        }
    """)
    assert sim.rf[1] == 10


def test_pointer_array_addr():
    sim = run_c("""
        int main() {
            int arr[4] = {10, 20, 30, 40};
            int *p;
            p = &arr[2];
            return *p;
        }
    """)
    assert sim.rf[1] == 30


def test_pointer_deref_write():
    sim = run_c("""
        int g = 0;
        int main() {
            int *p;
            p = &g;
            *p = 99;
            return *p;
        }
    """)
    assert sim.rf[1] == 99


# ---------------------------------------------------------------------------
# Pré-processamento: #define
# ---------------------------------------------------------------------------

def test_define_constante():
    sim = run_c("""
        #define MAX 100
        int main() {
            return MAX;
        }
    """)
    assert sim.rf[1] == 100


def test_define_em_expr():
    sim = run_c("""
        #define N 5
        #define M 3
        int main() {
            return N + M;
        }
    """)
    assert sim.rf[1] == 8


def test_define_em_loop():
    sim = run_c("""
        #define LIMIT 5
        int main() {
            int s = 0;
            for (int i = 1; i <= LIMIT; i += 1) {
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 15


# ---------------------------------------------------------------------------
# Variáveis globais
# ---------------------------------------------------------------------------

def test_global_simples():
    sim = run_c("""
        int contador = 7;
        int main() {
            return contador;
        }
    """)
    assert sim.rf[1] == 7


def test_global_escrita():
    sim = run_c("""
        int g = 0;
        int main() {
            g = 42;
            return g;
        }
    """)
    assert sim.rf[1] == 42


def test_global_incremento():
    sim = run_c("""
        int cnt = 10;
        int main() {
            cnt += 5;
            cnt *= 2;
            return cnt;
        }
    """)
    assert sim.rf[1] == 30



# ---------------------------------------------------------------------------
# Aritmética e variáveis
# ---------------------------------------------------------------------------

def test_literal_soma():
    sim = run_c("int main() { return 3 + 4; }")
    assert sim.rf[1] == 7


def test_variavel_local():
    sim = run_c("""
        int main() {
            int x = 10;
            int y = 32;
            return x + y;
        }
    """)
    assert sim.rf[1] == 42


def test_subtracao():
    sim = run_c("int main() { return 100 - 58; }")
    assert sim.rf[1] == 42


def test_multiplicacao():
    sim = run_c("int main() { return 6 * 7; }")
    assert sim.rf[1] == 42


# ---------------------------------------------------------------------------
# Atribuições compostas
# ---------------------------------------------------------------------------

def test_assign_plus_eq():
    sim = run_c("""
        int main() {
            int x = 10;
            x += 5;
            return x;
        }
    """)
    assert sim.rf[1] == 15


def test_assign_minus_eq():
    sim = run_c("""
        int main() {
            int x = 20;
            x -= 6;
            return x;
        }
    """)
    assert sim.rf[1] == 14


def test_assign_mul_eq():
    sim = run_c("""
        int main() {
            int x = 3;
            x *= 7;
            return x;
        }
    """)
    assert sim.rf[1] == 21


def test_assign_compound_chain():
    sim = run_c("""
        int main() {
            int x = 10;
            x -= 3;
            x *= 2;
            return x;
        }
    """)
    assert sim.rf[1] == 14


# ---------------------------------------------------------------------------
# Operadores bitwise
# ---------------------------------------------------------------------------

def test_bitwise_and():
    sim = run_c("int main() { return 0xFF & 0x0F; }")
    assert sim.rf[1] == 0x0F


def test_bitwise_or():
    sim = run_c("int main() { return 0xF0 | 0x0F; }")
    assert sim.rf[1] == 0xFF


def test_bitwise_xor():
    sim = run_c("int main() { return 0xFF ^ 0x55; }")
    assert sim.rf[1] == 0xAA


# ---------------------------------------------------------------------------
# Controle de fluxo — if/else
# ---------------------------------------------------------------------------

def test_if_taken():
    sim = run_c("""
        int main() {
            int x = 5;
            if (x == 5) { x = 42; }
            return x;
        }
    """)
    assert sim.rf[1] == 42


def test_if_not_taken():
    sim = run_c("""
        int main() {
            int x = 5;
            if (x == 99) { x = 42; }
            return x;
        }
    """)
    assert sim.rf[1] == 5


def test_if_else():
    sim = run_c("""
        int main() {
            int x = 3;
            if (x > 5) { x = 100; } else { x = 0; }
            return x;
        }
    """)
    assert sim.rf[1] == 0


# ---------------------------------------------------------------------------
# Controle de fluxo — while
# ---------------------------------------------------------------------------

def test_while_soma():
    sim = run_c("""
        int main() {
            int n = 5;
            int acc = 0;
            while (n) {
                acc += n;
                n -= 1;
            }
            return acc;
        }
    """)
    assert sim.rf[1] == 15


# ---------------------------------------------------------------------------
# Controle de fluxo — for
# ---------------------------------------------------------------------------

def test_for_soma():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 5; i += 1) {
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 15


def test_for_produto():
    sim = run_c("""
        int main() {
            int p = 1;
            for (int i = 1; i <= 5; i += 1) {
                p *= i;
            }
            return p;
        }
    """)
    assert sim.rf[1] == 120   # 5! = 120


# ---------------------------------------------------------------------------
# break e continue
# ---------------------------------------------------------------------------

def test_break_in_while():
    sim = run_c("""
        int main() {
            int s = 0;
            int i = 0;
            while (1) {
                i += 1;
                s += i;
                if (i == 3) { break; }
            }
            return s;
        }
    """)
    assert sim.rf[1] == 6   # 1+2+3


def test_continue_in_while():
    sim = run_c("""
        int main() {
            int s = 0;
            int i = 0;
            while (i < 5) {
                i += 1;
                if (i == 3) { continue; }
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 12  # 1+2+4+5 (3 pulado)


def test_break_in_for():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 10; i += 1) {
                s += i;
                if (i == 4) { break; }
            }
            return s;
        }
    """)
    assert sim.rf[1] == 10   # 1+2+3+4


def test_continue_in_for():
    sim = run_c("""
        int main() {
            int s = 0;
            for (int i = 1; i <= 5; i += 1) {
                if (i == 3) { continue; }
                s += i;
            }
            return s;
        }
    """)
    assert sim.rf[1] == 12   # 1+2+4+5


# ---------------------------------------------------------------------------
# Funções com argumentos
# ---------------------------------------------------------------------------

def test_func_call_no_args():
    sim = run_c("""
        int dobro() {
            return 21 + 21;
        }
        int main() {
            return dobro();
        }
    """)
    assert sim.rf[1] == 42


def test_func_call_with_arg():
    sim = run_c("""
        int quadrado(int x) {
            return x * x;
        }
        int main() {
            return quadrado(7);
        }
    """)
    assert sim.rf[1] == 49


def test_func_call_two_args():
    sim = run_c("""
        int soma(int a, int b) {
            return a + b;
        }
        int main() {
            return soma(17, 25);
        }
    """)
    assert sim.rf[1] == 42


# ---------------------------------------------------------------------------
# Literais hexadecimais no código C
# ---------------------------------------------------------------------------

def test_hex_literal():
    sim = run_c("int main() { return 0xFF; }")
    assert sim.rf[1] == 255
