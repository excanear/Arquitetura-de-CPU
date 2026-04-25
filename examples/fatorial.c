/* fatorial.c — calcula N! iterativamente
 *
 * Compilar com: python3 -c "from compiler.compiler import compile_source; print(compile_source(open('examples/fatorial.c').read()))"
 * Resultado: R1 = 10! = 3628800
 */

int main() {
    int n = 10;
    int fat = 1;
    while (n > 1) {
        fat *= n;
        n -= 1;
    }
    return fat;
}
