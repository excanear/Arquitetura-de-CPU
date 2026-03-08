"""
toolchain/loader.py — Loader EduRISC-32v2
==========================================
Carrega um arquivo .hex (Intel HEX) e o converte para os formatos
consumidos pelo simulador e pelos testbenches:

  1. Lista de inteiros Python (para o simulador)
  2. Arquivo .mem no formato $readmemh do Verilog (para GHDL/Icarus/Vivado)
  3. Arquivo de inicialização BRAM para Vivado (formato COE)

Uso direto:
  python -m toolchain.loader programa.hex --format mem -o imem.mem
  python -m toolchain.loader programa.hex --format coe -o imem.coe
"""

from __future__ import annotations
import struct
from pathlib import Path
from typing import Dict, List, Optional


class LoaderError(Exception):
    pass


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
MEM_DEPTH = 1 << 20    # 1M words (26-bit PC → 4MB de IMEM)
IMEM_BASE = 0x000000
DMEM_BASE = 0x100000   # endereço físico base da DMEM (acima da IMEM)


class Loader:
    """Carrega arquivos .hex e exporta para diferentes formatos."""

    def __init__(self, mem_depth: int = MEM_DEPTH):
        self.mem_depth = mem_depth
        self._mem: Dict[int, int] = {}   # addr (em words) → word

    # -----------------------------------------------------------------------
    # Leitura de Intel HEX
    # -----------------------------------------------------------------------
    def load_hex(self, path: str | Path) -> None:
        """Parsa um arquivo Intel HEX e preenche o mapa de memória."""
        self._mem.clear()
        path = Path(path)
        if not path.exists():
            raise LoaderError(f"Arquivo não encontrado: {path}")

        ext_addr = 0   # extended linear address record
        for lineno, line in enumerate(path.read_text("ascii").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            if line[0] != ':':
                raise LoaderError(f"Linha {lineno}: record inválido (sem ':')")

            raw      = bytes.fromhex(line[1:])
            count    = raw[0]
            addr     = ((raw[1] << 8) | raw[2]) + ext_addr
            rtype    = raw[3]
            data     = raw[4:4 + count]
            checksum = raw[4 + count]

            calc_chk = (-(sum(raw[:4 + count]))) & 0xFF
            if calc_chk != checksum:
                raise LoaderError(f"Linha {lineno}: checksum inválido")

            if rtype == 0x00:   # data
                if len(data) % 4 != 0:
                    raise LoaderError(f"Linha {lineno}: dados não alinhados (deve ser múltiplo de 4 bytes)")
                for i in range(0, len(data), 4):
                    word_addr = (addr + i) // 4
                    word = struct.unpack(">I", data[i:i + 4])[0]
                    self._mem[word_addr] = word

            elif rtype == 0x04:  # extended linear address
                ext_addr = (struct.unpack(">H", data)[0]) << 16

            elif rtype == 0x01:  # EOF
                break

    def load_words(self, words: List[int], base_addr: int = 0) -> None:
        """Carrega uma lista de words diretamente (para testes)."""
        for i, w in enumerate(words):
            self._mem[base_addr + i] = w & 0xFFFFFFFF

    # -----------------------------------------------------------------------
    # Exportação
    # -----------------------------------------------------------------------
    def to_mem_list(self, base: int = 0, size: Optional[int] = None) -> List[int]:
        """Retorna lista de words para uso no simulador Python."""
        sz = size or self.mem_depth
        result = [0] * sz
        for addr, word in self._mem.items():
            idx = addr - base
            if 0 <= idx < sz:
                result[idx] = word
        return result

    def write_mem(self, path: str | Path, base: int = 0, size: Optional[int] = None) -> None:
        """Grava arquivo .mem compatível com $readmemh do Verilog."""
        sz  = size or self.mem_depth
        buf = self.to_mem_list(base, sz)
        lines = []
        for i, w in enumerate(buf):
            lines.append(f"{w:08X}")
        Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")
        print(f"[loader] {Path(path).name}: {sz} words")

    def write_coe(self, path: str | Path, base: int = 0, size: Optional[int] = None) -> None:
        """Grava arquivo .coe para inicialização de BRAM no Vivado."""
        sz  = size or 4096   # COE menor para init de BRAM
        buf = self.to_mem_list(base, sz)
        lines = [
            "memory_initialization_radix=16;",
            "memory_initialization_vector=",
        ]
        for i, w in enumerate(buf):
            sep = "," if i < sz - 1 else ";"
            lines.append(f"{w:08X}{sep}")
        Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")
        print(f"[loader] {Path(path).name}: {sz} words (COE)")

    def write_verilog_init(self, path: str | Path, module_name: str = "imem_init",
                           base: int = 0, size: int = 4096) -> None:
        """Gera arquivo Verilog com initial block para BRAM (simulação)."""
        buf = self.to_mem_list(base, size)
        lines = [
            f"// Auto-gerado por toolchain/loader.py",
            f"// {Path(path).name}",
            f"initial begin",
        ]
        for i, w in enumerate(buf):
            if w != 0:
                lines.append(f"  mem[{i}] = 32'h{w:08X};")
        lines.append("end")
        Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")

    @property
    def word_count(self) -> int:
        return len(self._mem)

    @property
    def address_range(self):
        if not self._mem:
            return (0, 0)
        return (min(self._mem), max(self._mem))


# ---------------------------------------------------------------------------
# Interface de linha de comando
# ---------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(description="EduRISC-32v2 Loader")
    parser.add_argument("hex_file", help="Arquivo de entrada .hex")
    parser.add_argument("--format", choices=["mem", "coe", "vinit"],
                        default="mem", help="Formato de saída")
    parser.add_argument("-o", "--output", help="Arquivo de saída")
    parser.add_argument("--base", type=lambda x: int(x, 0),
                        default=0, help="Endereço base em words")
    parser.add_argument("--size", type=lambda x: int(x, 0),
                        help="Número de words a exportar")
    args = parser.parse_args()

    loader = Loader()
    loader.load_hex(args.hex_file)
    print(f"[loader] Carregado: {loader.word_count} words, range 0x{loader.address_range[0]:X}–0x{loader.address_range[1]:X}")

    out = args.output or Path(args.hex_file).with_suffix(
        {"mem": ".mem", "coe": ".coe", "vinit": "_init.v"}[args.format]
    )

    if args.format == "mem":
        loader.write_mem(out, args.base, args.size)
    elif args.format == "coe":
        loader.write_coe(out, args.base, args.size)
    elif args.format == "vinit":
        loader.write_verilog_init(out, base=args.base, size=args.size or 4096)


if __name__ == "__main__":
    main()
