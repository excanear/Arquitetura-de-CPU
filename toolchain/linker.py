"""
toolchain/linker.py — Linker EduRISC-32v2
==========================================
Combina múltiplos arquivos objeto (.obj) gerados pelo assembler em um
único binário executável (.hex no formato Intel HEX).

Fases:
  1. Coletar seções (.text, .data, .bss) de todos os arquivos objeto
  2. Resolver símbolos externos (labels de múltiplos módulos)
  3. Relocar referências de endereçamento
  4. Emitir arquivo .hex final

Formato de arquivo objeto (.obj) — JSON interno:
  {
    "text": [[addr, word], ...],   # lista de (endereço, instrução)
    "data": [[addr, word], ...],   # dados inicializados
    "bss_size": int,               # tamanho do BSS em words
    "symbols": {"label": addr},    # exportados
    "relocs":  [{"addr":, "sym":, "type":}]  # relocações pendentes
  }
"""

from __future__ import annotations
import json
import struct
from pathlib import Path
from typing import Dict, List, Tuple

# ---------------------------------------------------------------------------
# Layout de memória padrão
# ---------------------------------------------------------------------------
TEXT_BASE   = 0x000000   # início do segmento de código (IMEM)
DATA_BASE   = 0x002000   # início do segmento de dados (DMEM)
BSS_ALIGN   = 4          # alinhamento do BSS em words

# Tipos de relocação
RELOC_ABS26  = "abs26"   # campo addr26 (JMP/CALL)
RELOC_PC16   = "pc16"    # campo off16 com PC-relativo (branches)
RELOC_IMM16  = "imm16"   # campo imm16 absoluto


class LinkerError(Exception):
    pass


class Linker:
    """Linker para arquivos objeto EduRISC-32v2."""

    def __init__(self, text_base: int = TEXT_BASE, data_base: int = DATA_BASE):
        self.text_base = text_base
        self.data_base = data_base

        self._text:    List[Tuple[int, int]] = []   # (addr, word)
        self._data:    List[Tuple[int, int]] = []
        self._bss_size = 0
        self._symbols: Dict[str, int]        = {}
        self._relocs:  List[dict]            = []

    # -----------------------------------------------------------------------
    # 1. Ingestão de módulos
    # -----------------------------------------------------------------------
    def add_object(self, path: str | Path) -> None:
        """Carrega um arquivo objeto (.obj) e acumula seções/símbolos."""
        obj = json.loads(Path(path).read_text(encoding="utf-8"))

        text_offset = len(self._text)
        data_offset = len(self._data)

        # Seção .text
        for addr, word in obj.get("text", []):
            self._text.append((addr + text_offset, word))

        # Seção .data
        for addr, word in obj.get("data", []):
            self._data.append((addr + data_offset, word))

        # BSS
        self._bss_size += obj.get("bss_size", 0)

        # Símbolos — ajustar com offsets
        for sym, addr in obj.get("symbols", {}).items():
            if sym in self._symbols:
                raise LinkerError(f"Símbolo duplicado: {sym!r}")
            if addr < len(obj.get("text", [])):
                self._symbols[sym] = self.text_base + text_offset + addr
            else:
                self._symbols[sym] = self.data_base + data_offset + (addr - len(obj.get("text", [])))

        # Relocações — ajustar endereços
        for rel in obj.get("relocs", []):
            self._relocs.append({
                "addr": rel["addr"] + text_offset,
                "sym":  rel["sym"],
                "type": rel["type"],
            })

    def add_raw_words(self, words: List[int], base_addr: int = 0) -> None:
        """Adiciona uma lista de words diretamente à seção .text."""
        for i, w in enumerate(words):
            self._text.append((base_addr + i, w))

    # -----------------------------------------------------------------------
    # 2. Resolução de símbolos e relocação
    # -----------------------------------------------------------------------
    def _resolve(self) -> Dict[int, int]:
        """Aplica relocações e retorna dicionário {endereço → word final}."""
        # Construir mapa addr→word para .text
        mem: Dict[int, int] = {}
        for addr, word in self._text:
            mem[self.text_base + addr] = word
        for addr, word in self._data:
            mem[self.data_base + addr] = word

        for rel in self._relocs:
            sym   = rel["sym"]
            rtype = rel["type"]
            raddr = self.text_base + rel["addr"]

            if sym not in self._symbols:
                raise LinkerError(f"Símbolo indefinido: {sym!r}")

            sym_val = self._symbols[sym]
            word    = mem.get(raddr, 0)

            if rtype == RELOC_ABS26:
                # Substituir [25:0] com endereço de 26 bits
                if sym_val > 0x3FFFFFF:
                    raise LinkerError(f"Endereço 0x{sym_val:X} fora do alcance addr26 para {sym!r}")
                word = (word & 0xFC000000) | (sym_val & 0x3FFFFFF)

            elif rtype == RELOC_PC16:
                # Calcular offset de PC-relativo
                offset = sym_val - raddr
                if offset < -32768 or offset > 32767:
                    raise LinkerError(f"Offset PC16 fora do alcance ({offset}) para {sym!r}")
                word = (word & 0xFFFF0000) | (offset & 0xFFFF)

            elif rtype == RELOC_IMM16:
                if sym_val > 0xFFFF:
                    raise LinkerError(f"Valor 0x{sym_val:X} fora do alcance imm16 para {sym!r}")
                word = (word & 0xFFFF0000) | (sym_val & 0xFFFF)

            mem[raddr] = word

        return mem

    # -----------------------------------------------------------------------
    # 3. Emissão de saída
    # -----------------------------------------------------------------------
    def link(self, output: str | Path) -> None:
        """Executa a linkagem e grava o arquivo .hex de saída."""
        mem = self._resolve()

        lines: List[str] = []
        for addr in sorted(mem):
            word = mem[addr] & 0xFFFFFFFF
            lines.append(_ihex_record(addr * 4, struct.pack(">I", word)))

        lines.append(":00000001FF")   # EOF record

        Path(output).write_text("\n".join(lines) + "\n", encoding="ascii")
        print(f"[linker] {Path(output).name}: {len(mem)} words")

    def symbols(self) -> Dict[str, int]:
        """Retorna tabela de símbolos (útil para o loader e debugger)."""
        return dict(self._symbols)


# ---------------------------------------------------------------------------
# Utilitário: gerar record Intel HEX
# ---------------------------------------------------------------------------
def _ihex_record(byte_addr: int, data: bytes) -> str:
    """Gera um record Intel HEX tipo 00 (data)."""
    count    = len(data)
    hi       = (byte_addr >> 8) & 0xFF
    lo       = byte_addr & 0xFF
    body     = bytes([count, hi, lo, 0x00]) + data
    checksum = (-(sum(body))) & 0xFF
    return ":" + body.hex().upper() + f"{checksum:02X}"


# ---------------------------------------------------------------------------
# Interface de linha de comando
# ---------------------------------------------------------------------------
def main():
    import sys
    import argparse

    parser = argparse.ArgumentParser(description="EduRISC-32v2 Linker")
    parser.add_argument("objects", nargs="+", help="Arquivos objeto (.obj)")
    parser.add_argument("-o", "--output", default="a.hex", help="Saída .hex")
    parser.add_argument("--text-base", type=lambda x: int(x, 0),
                        default=TEXT_BASE, help="Base da seção .text")
    parser.add_argument("--data-base", type=lambda x: int(x, 0),
                        default=DATA_BASE, help="Base da seção .data")
    args = parser.parse_args()

    linker = Linker(text_base=args.text_base, data_base=args.data_base)
    for obj in args.objects:
        print(f"[linker] Adicionando {obj}")
        linker.add_object(obj)

    linker.link(args.output)
    print(f"[linker] Símbolos: {list(linker.symbols().keys())}")


if __name__ == "__main__":
    main()
