/* ============================================================================
 * memory.c  —  Gerenciador de Memória EduRISC-32v2
 *
 * Implementa um alocador de blocos simples (first-fit) sobre o heap da DMEM.
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

#define HEAP_START    0x2000
#define HEAP_END      0xF000
#define HEAP_SIZE     (HEAP_END - HEAP_START)

#define BLOCK_FREE    0
#define BLOCK_USED    1
#define HEADER_WORDS  2    /* tamanho do header em words */

/* ---------------------------------------------------------------------------
 * memory_init: inicializa o heap como um único bloco livre
 * --------------------------------------------------------------------------- */
void memory_init() {
    int *heap;
    heap    = HEAP_START;
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

    total_needed = size + HEADER_WORDS;
    cur = HEAP_START;

    while (cur < HEAP_END) {
        block_size = cur[0];
        block_used = cur[1];

        if (block_used == BLOCK_FREE && block_size >= total_needed) {
            /* Dividir bloco se sobrar espaço */
            if (block_size > total_needed + HEADER_WORDS + 1) {
                int *next_block;
                next_block    = cur + total_needed;
                next_block[0] = block_size - total_needed;
                next_block[1] = BLOCK_FREE;
            }
            cur[0] = total_needed;
            cur[1] = BLOCK_USED;
            return cur + HEADER_WORDS;    /* ponteiro para dados */
        }

        cur = cur + block_size;
    }

    return 0;    /* falha de alocação */
}

/* ---------------------------------------------------------------------------
 * kfree: libera um bloco previamente alocado com kmalloc
 * --------------------------------------------------------------------------- */
void kfree(int *ptr) {
    int *header;
    header    = ptr - HEADER_WORDS;
    header[1] = BLOCK_FREE;

    /* Coalescência para frente (merge com próximo bloco livre) */
    int *next;
    next = header + header[0];
    if (next < HEAP_END && next[1] == BLOCK_FREE) {
        header[0] = header[0] + next[0];
    }
}

/* ---------------------------------------------------------------------------
 * kmemset: preenche 'n' words a partir de 'ptr' com valor 'val'
 * --------------------------------------------------------------------------- */
void kmemset(int *ptr, int val, int n) {
    int i;
    i = 0;
    while (i < n) {
        ptr[i] = val;
        i = i + 1;
    }
}

/* ---------------------------------------------------------------------------
 * kmemcpy: copia 'n' words de src para dst
 * --------------------------------------------------------------------------- */
void kmemcpy(int *dst, int *src, int n) {
    int i;
    i = 0;
    while (i < n) {
        dst[i] = src[i];
        i = i + 1;
    }
}

/* ---------------------------------------------------------------------------
 * heap_stats: retorna através de ponteiros: blocos livres e usados
 * --------------------------------------------------------------------------- */
void heap_stats(int *free_blocks, int *used_blocks) {
    int *cur;
    int  f;
    int  u;

    cur = HEAP_START;
    f   = 0;
    u   = 0;

    while (cur < HEAP_END) {
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
