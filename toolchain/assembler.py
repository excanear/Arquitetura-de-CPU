"""
toolchain/assembler.py — EduRISC-32v2 Assembler (Toolchain Wrapper)

Wraps the standalone 2-pass assembler in assembler/assembler.py and
exposes a unified CLI compatible with the rest of the toolchain pipeline:

  C source
     ↓  compiler.py
  assembly (.asm)
     ↓  assembler.py   ← you are here
  object file (.obj / Intel HEX)
     ↓  linker.py
  linked binary
     ↓  loader.py
  BRAM init file (.mem / .coe / .vinit)
     ↓  FPGA / simulator

Usage (standalone):
  python -m toolchain.assembler program.asm -o program.hex
  python -m toolchain.assembler program.asm -o program.obj --format obj
  python -m toolchain.assembler program.asm --listing

Supported output formats:
  hex   — Intel HEX (default, consumed by loader.py and JTAG programmer)
  obj   — JSON object file with symbol table (consumed by linker.py)
  bin   — flat binary (for direct memory load in simulation)
"""

import sys
import os
import importlib
import argparse
from typing import Optional

# ---------------------------------------------------------------------------
# Re-export the core assembler from assembler/assembler.py
# ---------------------------------------------------------------------------
_pkg_dir = os.path.join(os.path.dirname(__file__), "..", "assembler")
sys.path.insert(0, os.path.abspath(_pkg_dir))

try:
    from assembler import Assembler  # assembler/assembler.py
except ImportError as exc:
    raise ImportError(
        "Could not import assembler.Assembler from assembler/assembler.py. "
        f"Original error: {exc}"
    ) from exc


# ---------------------------------------------------------------------------
# Thin wrapper class — adds format conversion on top of the core assembler
# ---------------------------------------------------------------------------
class ToolchainAssembler:
    """
    Assembler entry point for the unified EduRISC-32v2 toolchain.

    Wraps assembler.Assembler (2-pass, all 6 instruction formats, ELF-like
    directives: .org, .word, .byte, .data, .text, .equ, .global).
    """

    def __init__(self, listing: bool = False, verbose: bool = False):
        self.listing = listing
        self.verbose = verbose
        self._asm = Assembler()

    def assemble_file(
        self,
        src_path: str,
        out_path: str,
        fmt: str = "hex",
    ) -> dict:
        """
        Assemble *src_path* and write output to *out_path*.

        Parameters
        ----------
        src_path : path to the .asm source file
        out_path : destination file path (extension need not match fmt)
        fmt      : output format — "hex" | "obj" | "bin"

        Returns a result dict:
          {
            "success": bool,
            "errors":  list[str],
            "symbols": dict[str, int],   # symbol → address
            "bytes":   int,              # number of code bytes generated
          }
        """
        result = {"success": False, "errors": [], "symbols": {}, "bytes": 0}

        if not os.path.isfile(src_path):
            result["errors"].append(f"Source file not found: {src_path}")
            return result

        try:
            with open(src_path, "r", encoding="utf-8") as fh:
                source = fh.read()
        except OSError as exc:
            result["errors"].append(f"Cannot read {src_path}: {exc}")
            return result

        # Run 2-pass assembly
        try:
            assembled = self._asm.assemble(source)
        except Exception as exc:  # noqa: BLE001
            result["errors"].append(f"Assembly error: {exc}")
            return result

        # assembled is expected to be a dict:
        #   {"words": list[int], "symbols": dict, "listing": str}
        if not isinstance(assembled, dict):
            result["errors"].append(
                "Unexpected assembler return type: expected dict"
            )
            return result

        words:   list  = assembled.get("words",   [])
        symbols: dict  = assembled.get("symbols", {})
        listing: str   = assembled.get("listing", "")

        result["symbols"] = symbols
        result["bytes"]   = len(words) * 4

        # Write the requested output format
        try:
            if fmt == "hex":
                self._write_intel_hex(out_path, words)
            elif fmt == "obj":
                self._write_obj(out_path, words, symbols, src_path)
            elif fmt == "bin":
                self._write_bin(out_path, words)
            else:
                result["errors"].append(f"Unknown output format: {fmt}")
                return result
        except OSError as exc:
            result["errors"].append(f"Cannot write {out_path}: {exc}")
            return result

        # Optionally write a .lst listing file
        if self.listing and listing:
            lst_path = os.path.splitext(out_path)[0] + ".lst"
            try:
                with open(lst_path, "w", encoding="utf-8") as lf:
                    lf.write(listing)
                if self.verbose:
                    print(f"[ASM] Listing written to {lst_path}")
            except OSError as exc:
                if self.verbose:
                    print(f"[ASM] Warning: could not write listing: {exc}")

        if self.verbose:
            print(
                f"[ASM] {os.path.basename(src_path)} → {out_path}  "
                f"({result['bytes']} bytes, {len(symbols)} symbols)"
            )

        result["success"] = True
        return result

    # ------------------------------------------------------------------
    # Output format writers
    # ------------------------------------------------------------------

    @staticmethod
    def _write_intel_hex(path: str, words: list) -> None:
        """Write an Intel HEX file (IHEX format) from a list of 32-bit words."""
        with open(path, "w", encoding="ascii") as fh:
            addr = 0
            WORDS_PER_RECORD = 4   # 16 bytes per record
            i = 0
            while i < len(words):
                chunk = words[i : i + WORDS_PER_RECORD]
                byte_addr = addr * 4
                data_bytes = bytearray()
                for w in chunk:
                    data_bytes += w.to_bytes(4, "big")

                count    = len(data_bytes)
                rec_type = 0x00   # Data record
                checksum = (count
                            + ((byte_addr >> 8) & 0xFF)
                            + (byte_addr & 0xFF)
                            + rec_type
                            + sum(data_bytes)) & 0xFF
                checksum = (~checksum + 1) & 0xFF

                fh.write(
                    f":{count:02X}"
                    f"{byte_addr:04X}"
                    f"{rec_type:02X}"
                    + "".join(f"{b:02X}" for b in data_bytes)
                    + f"{checksum:02X}\n"
                )
                addr += WORDS_PER_RECORD
                i += WORDS_PER_RECORD

            # End-of-file record
            fh.write(":00000001FF\n")

    @staticmethod
    def _write_obj(path: str, words: list, symbols: dict, src: str) -> None:
        """Write a JSON object file (consumed by toolchain/linker.py)."""
        import json
        obj = {
            "format":  "edurisc32v2-obj-v1",
            "source":  os.path.basename(src),
            "words":   words,
            "symbols": symbols,
        }
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, indent=2)
            fh.write("\n")

    @staticmethod
    def _write_bin(path: str, words: list) -> None:
        """Write a flat big-endian binary."""
        with open(path, "wb") as fh:
            for w in words:
                fh.write(w.to_bytes(4, "big"))


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="toolchain-assembler",
        description="EduRISC-32v2 Assembler (toolchain wrapper)",
    )
    p.add_argument("source", help="Input .asm source file")
    p.add_argument(
        "-o", "--output",
        default=None,
        help="Output file path (default: source with .hex extension)",
    )
    p.add_argument(
        "--format", "-f",
        choices=["hex", "obj", "bin"],
        default="hex",
        help="Output format (default: hex)",
    )
    p.add_argument(
        "--listing", "-l",
        action="store_true",
        help="Write a .lst assembly listing alongside the output",
    )
    p.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print progress messages",
    )
    return p


def main(argv: Optional[list] = None) -> int:
    parser = _build_parser()
    args   = parser.parse_args(argv)

    src = args.source
    out = args.output or (os.path.splitext(src)[0] + f".{args.format}")

    asm = ToolchainAssembler(listing=args.listing, verbose=args.verbose)
    res = asm.assemble_file(src, out, fmt=args.format)

    if res["errors"]:
        for err in res["errors"]:
            print(f"error: {err}", file=sys.stderr)
        return 1

    print(f"Assembled {src} → {out}  ({res['bytes']} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
