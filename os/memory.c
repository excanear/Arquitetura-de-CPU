/* ============================================================================
 * memory.c  —  Gerenciador de Memória EduRISC-32v2
 *
 * Implementa um alocador de blocos first-fit sobre o heap da DMEM com
 * coalescência bidirecional (forward + backward merge) no kfree para
 * evitar fragmentação ao longo do tempo.
 *
 * Layout de DMEM:
 *   0x0000 – 0x0FFF  : área OS / variáveis globais / pilhas de processo
 *   0x1000 – 0x1FFF  : tabela de processos (8 × 16 words)
 *   0x2000 – 0xEFFF  : HEAP gerenciado
 *   0xF000 – 0xFFFF  : MMIO + pilha inicial do bootloader
 *
 * Estrutura de cada bloco no heap:
 *   [0] = tamanho do bloco em words (incluindo este header)
 *   [1] = 0=livre / 1=usado
 *   [2..size-1] = dados do usuário
 * ============================================================================ */

#include "os_defs.h"

/* ---------------------------------------------------------------------------
 * memory_init: inicializa o heap como um único bloco livre
 * --------------------------------------------------------------------------- */
void memory_init() {
    int *heap;
    heap    = (int *)HEAP_START;
    heap[0] = HEAP_SIZE;   /* tamanho total */
    heap[1] = BLOCK_FREE;
}

/* ---------------------------------------------------------------------------
 * kmalloc: aloca 'size' words no heap (first-fit)
 * Retorna: ponteiro para área de dados, ou 0 se falhar
 * --------------------------------------------------------------------------- */
int *kmalloc(int size) {
    int *cur;
    int  block_size;
    int  block_used;
    int  total_needed;

    if (size <= 0) {
        return (int *)0;   /* Guarda contra alocação de tamanho inválido */
    }

    total_needed = size + HEADER_WORDS;
    cur = (int *)HEAP_START;

    while (cur < (int *)HEAP_END) {
        block_size = cur[0];
        block_used = cur[1];

        /* Protege contra bloco corrompido com tamanho zero ou negativo */
        if (block_size <= 0) {
            return (int *)0;
        }

        if (block_used == BLOCK_FREE && block_size >= total_needed) {
            /* Dividir bloco se sobrar espaço para pelo menos 1 word de dado */
            if (block_size > total_needed + HEADER_WORDS + 1) {
                int *next_block;
                next_block    = cur + total_needed;
                next_block[0] = block_size - total_needed;
                next_block[1] = BLOCK_FREE;
            }
            cur[0] = total_needed;
            cur[1] = BLOCK_USED;
            return cur + HEADER_WORDS;    /* ponteiro para área de dados */
        }

        cur = cur + block_size;
    }

    return (int *)0;    /* falha de alocação — heap cheio */
}

/* ---------------------------------------------------------------------------
 * kfree: libera um bloco previamente alocado com kmalloc
 *
 * Implementa coalescência bidirecional:
 *   1. Marca o bloco como livre.
 *   2. Faz merge com o bloco seguinte se ele estiver livre (forward merge).
 *   3. Percorre o heap desde o início para encontrar o bloco anterior e
 *      faz merge com ele se estiver livre (backward merge).
 *
 * Garante que ptr seja != 0 antes de acessar o header, prevenindo
 * comportamento indefinido em chamadas kfree(NULL).
 * --------------------------------------------------------------------------- */
void kfree(int *ptr) {
    int *header;
    int *next;
    int *cur;
    int *prev;

    if (ptr == (int *)0) {
        return;   /* kfree(NULL) é operação nula — seguro chamar */
    }

    header    = ptr - HEADER_WORDS;
    header[1] = BLOCK_FREE;

    /* ── Forward merge: combinar com próximo bloco se também livre ── */
    next = header + header[0];
    if (next < (int *)HEAP_END && next[1] == BLOCK_FREE) {
        header[0] = header[0] + next[0];
    }

    /* ── Backward merge: percorre desde HEAP_START para achar bloco anterior ── */
    cur  = (int *)HEAP_START;
    prev = (int *)0;

    while (cur < header) {
        if (cur + cur[0] == header) {
            prev = cur;  /* bloco imediatamente antes de header */
        }
        if (cur[0] <= 0) {
            break;   /* heap corrompido: interrompe varredura */
        }
        cur = cur + cur[0];
    }

    if (prev != (int *)0 && prev[1] == BLOCK_FREE) {
        /* Bloco anterior está livre: absorve header no bloco anterior */
        prev[0] = prev[0] + header[0];
    }
}

/* ---------------------------------------------------------------------------
 * kmemset: preenche 'n' words a partir de 'ptr' com valor 'val'
 * --------------------------------------------------------------------------- */
void kmemset(int *ptr, int val, int n) {
    int i;
    if (ptr == (int *)0 || n <= 0) {
        return;
    }
    i = 0;
    while (i < n) {
        ptr[i] = val;
        i = i + 1;
    }
}

/* ---------------------------------------------------------------------------
 * kmemcpy: copia 'n' words de src para dst
 * Suporta cópia em direções opostas (src > dst: copia para frente;
 * src < dst: copia para trás para evitar sobreposição).
 * --------------------------------------------------------------------------- */
void kmemcpy(int *dst, int *src, int n) {
    int i;
    if (dst == (int *)0 || src == (int *)0 || n <= 0) {
        return;
    }
    if (dst <= src) {
        i = 0;
        while (i < n) {
            dst[i] = src[i];
            i = i + 1;
        }
    } else {
        i = n - 1;
        while (i >= 0) {
            dst[i] = src[i];
            i = i - 1;
        }
    }
}

/* ---------------------------------------------------------------------------
 * heap_stats: retorna via ponteiros o número de blocos livres e usados
 * --------------------------------------------------------------------------- */
void heap_stats(int *free_blocks, int *used_blocks) {
    int *cur;
    int  f;
    int  u;

    if (free_blocks == (int *)0 || used_blocks == (int *)0) {
        return;
    }

    cur = (int *)HEAP_START;
    f   = 0;
    u   = 0;

    while (cur < (int *)HEAP_END) {
        if (cur[0] <= 0) {
            break;   /* heap corrompido: para contagem */
        }
        if (cur[1] == BLOCK_FREE) {
            f = f + 1;
        } else {
            u = u + 1;
        }
        cur = cur + cur[0];
    }

    *free_blocks = f;
    *used_blocks = u;
}
