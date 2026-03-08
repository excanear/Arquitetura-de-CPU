"""
toolchain/compiler.py — EduRISC-32v2 C Compiler (Toolchain Wrapper)

Wraps the code generator in compiler/compiler.py and exposes a unified
CLI for the complete toolchain pipeline:

  C source (.c)
     ↓  compiler.py   ← you are here
  assembly (.asm)
     ↓  assembler.py
  Intel HEX (.hex)
     ↓  linker.py
  linked binary
     ↓  loader.py
  BRAM init file

Supported language subset (EduRISC-32v2 C subset):
  • int / unsigned types (32-bit)
  • if / else / while / for / return
  • Function calls (up to 8 args, standard ABI via R1-R8)
  • Global and local variable declarations
  • Arithmetic: + - * / % (no floating point)
  • Logical:    && || !
  • Comparison: == != < > <= >=
  • Bitwise:    & | ^ ~ << >>
  • Arrays (1-D, fixed size)
  • Pointers (read/write via unary *)
  • Preprocessor: #define constant substitution (simple, no macros)

Usage:
  python -m toolchain.compiler hello.c -o hello.asm
  python -m toolchain.compiler hello.c -o hello.hex --assemble
  python -m toolchain.compiler hello.c --emit-ast
"""

import sys
import os
import argparse
from typing import Optional

# ---------------------------------------------------------------------------
# Import the core compiler from compiler/compiler.py
# ---------------------------------------------------------------------------
_pkg_dir = os.path.join(os.path.dirname(__file__), "..", "compiler")
sys.path.insert(0, os.path.abspath(_pkg_dir))

try:
    from compiler import Compiler  # compiler/compiler.py
except ImportError as exc:
    raise ImportError(
        "Could not import compiler.Compiler from compiler/compiler.py. "
        f"Original error: {exc}"
    ) from exc


# ---------------------------------------------------------------------------
# Toolchain wrapper
# ---------------------------------------------------------------------------
class ToolchainCompiler:
    """
    Compiler entry point for the unified EduRISC-32v2 toolchain.

    Wraps compiler.Compiler (recursive descent parser → AST → code gen) and
    optionally drives the assembler stage to produce a .hex in one pass.
    """

    def __init__(self, verbose: bool = False, emit_ast: bool = False):
        self.verbose  = verbose
        self.emit_ast = emit_ast
        self._comp    = Compiler()

    def compile_file(
        self,
        src_path: str,
        out_path: str,
        assemble: bool = False,
    ) -> dict:
        """
        Compile *src_path* (C source) and write the result to *out_path*.

        Parameters
        ----------
        src_path : path to the .c input file
        out_path : destination — .asm (default) or .hex if assemble=True
        assemble : if True, run the assembler stage automatically to produce
                   an Intel HEX file at *out_path*

        Returns
        -------
        dict with keys:
          success  : bool
          errors   : list[str]
          warnings : list[str]
          asm_path : str   (path of generated .asm file)
          hex_path : str | None
        """
        result: dict = {
            "success":  False,
            "errors":   [],
            "warnings": [],
            "asm_path": "",
            "hex_path": None,
        }

        if not os.path.isfile(src_path):
            result["errors"].append(f"Source file not found: {src_path}")
            return result

        try:
            with open(src_path, "r", encoding="utf-8") as fh:
                source = fh.read()
        except OSError as exc:
            result["errors"].append(f"Cannot read {src_path}: {exc}")
            return result

        # ── Preprocessing: expand simple #define constants ──────────────
        source = self._preprocess(source)

        # ── Compilation: C source → assembly text ──────────────────────
        try:
            assembly = self._comp.compile(source)
        except Exception as exc:  # noqa: BLE001
            result["errors"].append(f"Compiler error: {exc}")
            return result

        # Determine .asm output path
        asm_path = out_path if not assemble else (
            os.path.splitext(out_path)[0] + ".asm"
        )
        result["asm_path"] = asm_path

        # Write the assembly source
        try:
            with open(asm_path, "w", encoding="utf-8") as fh:
                fh.write(assembly)
        except OSError as exc:
            result["errors"].append(f"Cannot write {asm_path}: {exc}")
            return result

        if self.verbose:
            lines = assembly.count("\n")
            print(
                f"[CC] {os.path.basename(src_path)} → {asm_path}"
                f"  ({lines} lines)"
            )

        # ── Optional: emit AST dump ─────────────────────────────────────
        if self.emit_ast and hasattr(self._comp, "last_ast"):
            ast_path = os.path.splitext(asm_path)[0] + ".ast"
            try:
                with open(ast_path, "w", encoding="utf-8") as fh:
                    fh.write(str(self._comp.last_ast))
                if self.verbose:
                    print(f"[CC] AST written to {ast_path}")
            except OSError:
                pass

        # ── Optional: drive the assembler stage ────────────────────────
        if assemble:
            from toolchain.assembler import ToolchainAssembler  # noqa: PLC0415
            asm_tool = ToolchainAssembler(verbose=self.verbose)
            asm_result = asm_tool.assemble_file(asm_path, out_path, fmt="hex")
            if not asm_result["success"]:
                result["errors"].extend(asm_result["errors"])
                return result
            result["hex_path"] = out_path
            if self.verbose:
                print(
                    f"[CC] Assembled → {out_path}"
                    f"  ({asm_result['bytes']} bytes)"
                )

        result["success"] = True
        return result

    # ------------------------------------------------------------------
    # Minimal preprocessor: handle #define name value lines
    # ------------------------------------------------------------------
    @staticmethod
    def _preprocess(source: str) -> str:
        """
        Expand #define constant macros (no function-like macros).
        Lines starting with '#include' are stripped (no header support).
        """
        defines: dict = {}
        out_lines: list = []

        for line in source.splitlines():
            stripped = line.strip()

            if stripped.startswith("#define"):
                parts = stripped.split(None, 2)
                if len(parts) >= 3:
                    defines[parts[1]] = parts[2]
                elif len(parts) == 2:
                    defines[parts[1]] = "1"
                continue  # Don't emit #define lines

            if stripped.startswith("#include"):
                continue  # Strip headers (no file expansion in this subset)

            # Expand defined identifiers in the line
            for name, value in defines.items():
                # Simple word-boundary replacement
                import re
                line = re.sub(r"\b" + re.escape(name) + r"\b", value, line)

            out_lines.append(line)

        return "\n".join(out_lines)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="toolchain-compiler",
        description="EduRISC-32v2 C Compiler (toolchain wrapper)",
    )
    p.add_argument("source", help="Input .c source file")
    p.add_argument(
        "-o", "--output",
        default=None,
        help="Output file (default: source.asm, or source.hex if --assemble)",
    )
    p.add_argument(
        "--assemble", "-S",
        action="store_true",
        help="Run the assembler stage after compilation (produces .hex)",
    )
    p.add_argument(
        "--emit-ast",
        action="store_true",
        help="Write an .ast dump of the parse tree",
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
    if args.output:
        out = args.output
    elif args.assemble:
        out = os.path.splitext(src)[0] + ".hex"
    else:
        out = os.path.splitext(src)[0] + ".asm"

    tc = ToolchainCompiler(verbose=args.verbose, emit_ast=args.emit_ast)
    res = tc.compile_file(src, out, assemble=args.assemble)

    if res["errors"]:
        for err in res["errors"]:
            print(f"error: {err}", file=sys.stderr)
        return 1

    print(f"Compiled {src} → {res['asm_path']}" +
          (f" → {res['hex_path']}" if res["hex_path"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
