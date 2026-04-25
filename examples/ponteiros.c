/* ponteiros.c — demonstração de ponteiros e operadores bit-a-bit
 *
 * Compilar:  python main.py build examples/ponteiros.c -o examples/ponteiros.hex
 * Simular:   python main.py simulate examples/ponteiros.hex
 * Esperado:  R1 = 12  (ver cálculo abaixo)
 */

/* variável global acessada via ponteiro */
int global_val = 10;

int dobra(int *p) {
    *p = *p + *p;
    return *p;
}

int main() {
    /* ponteiro para global */
    int *ptr;
    ptr = &global_val;

    /* *ptr == 10 → dobra → 20 */
    dobra(ptr);

    /* operadores bit-a-bit e shift */
    int x = global_val >> 1;   /* 20 >> 1 = 10 */
    int y = x % 7;             /* 10 % 7  =  3 */
    int z = x & 0xF;           /* 10 & 15 = 10 */

    /* && e || */
    int cond = (y > 0) && (z > 0);   /* 1 */
    int res = z + cond;               /* 10 + 1 = 11 */

    /* <<  */
    res += (1 << 0);   /* 11 + 1 = 12 */

    return res;
}
