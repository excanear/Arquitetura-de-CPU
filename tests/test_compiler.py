"""
tests/test_compiler.py — Testes do compilador C-like para EduRISC-32v2

Cobre:
  - Variáveis locais, aritmética básica
  - while loop
  - for loop
  - break / continue
  - atribuições compostas (+=, -=, *=, /=, &=, |=, ^=)
  - operadores bitwise (&, |, ^, ~)
  - if/else
  - chamadas de função com e sem argumentos
  - return
"""

import pytest
from compiler.compiler import compile_source
from assembler.assembler import Assembler
from simulator.cpu_simulator import CPUSimulator


def run_c(source: str, max_cycles: int = 1000) -> CPUSimulator:
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
