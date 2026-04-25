/* fibonacci.c — calcula os primeiros N números de Fibonacci usando um array
 * Armazena os primeiros N números de Fibonacci em um array
 * e retorna o N-ésimo elemento.
 *
 * Compilar:  python main.py build examples/fibonacci.c -o examples/fibonacci.hex
 * Simular:   python main.py simulate examples/fibonacci.hex
 * Esperado:  R1 = 8  (fib(6): 0,1,1,2,3,5,8)
 */

int main() {
    int fib[10];
    fib[0] = 0;
    fib[1] = 1;
    int i = 2;
    while (i < 7) {
        fib[i] = fib[i - 1] + fib[i - 2];
        i += 1;
    }
    return fib[6];
}
