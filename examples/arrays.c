/* arrays.c — demonstração de arrays 1-D e operadores novos
 *
 * Compilar:  python main.py build examples/arrays.c -o examples/arrays.hex
 * Simular:   python main.py simulate examples/arrays.hex
 * Esperado:  R1 = 55  (soma de 1..10)
 */

int main() {
    int v[10] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    int soma = 0;
    int i = 0;
    while (i < 10) {
        soma += v[i];
        i += 1;
    }
    return soma;
}
