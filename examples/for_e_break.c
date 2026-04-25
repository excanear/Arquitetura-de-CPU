/* for_e_break.c — demonstra for loop com break e continue
 *
 * Soma os ímpares de 1 a 9 (pulando pares com continue,
 * parando quando soma >= 20 com break).
 * Esperado: 1+3+5+7 = 16  (9 seria somado mas soma >= 20 pararia antes)
 */

int main() {
    int soma = 0;
    for (int i = 1; i <= 10; i += 1) {
        if (i == 2) { continue; }
        if (i == 4) { continue; }
        if (i == 6) { continue; }
        if (i == 8) { continue; }
        if (i == 10) { continue; }
        soma += i;
        if (soma >= 20) { break; }
    }
    return soma;
}
