"""
toolchain/debugger.py — EduRISC-32v2 Interactive Debugger (Toolchain Wrapper)

Wraps the low-level debugger in simulator/debugger.py and the CPU simulator
in simulator/cpu_simulator.py, exposing:

  1. An interactive REPL debugger with GDB-style commands
  2. A programmatic API for test automation (used by verification/)
  3. A batch / script mode for CI pipelines

Debugger commands (interactive REPL):
  r  / run      [hex_file]  — start / restart execution
  s  / step                 — execute one instruction
  si / stepi    [n]         — execute n instructions (default 1)
  c  / continue             — run until breakpoint or HLT
  b  / break    <addr>      — set a breakpoint at address (hex)
  d  / delete   <addr>      — remove breakpoint
  bl / breaklist            — list all breakpoints
  p  / print    <reg>       — print register (R0..R31, PC, SP, etc.)
  pa / printall             — print all 32 GPRs + PC + flags
  m  / mem      <addr> [n]  — dump n words from memory (default 4)
  w  / watch    <addr>      — set a memory watchpoint
  dis / disasm  <addr> [n]  — disassemble n instructions (default 8)
  pp / pipeline             — show current pipeline stage snapshot
  cs / csr      [name]      — show CSR value(s)
  q  / quit                 — exit the debugger

Usage:
  python -m toolchain.debugger program.hex
  python -m toolchain.debugger program.hex --batch "r; si 100; pa; q"
  python -m toolchain.debugger --help
"""

from __future__ import annotations

import sys
import os
import readline  # noqa: F401  — enables line editing / history in REPL
import argparse
import shlex
from typing import Optional

# ---------------------------------------------------------------------------
# Import simulator and debugger from simulator/
# ---------------------------------------------------------------------------
_sim_dir = os.path.join(os.path.dirname(__file__), "..", "simulator")
sys.path.insert(0, os.path.abspath(_sim_dir))

try:
    from cpu_simulator import CPUSimulator  # simulator/cpu_simulator.py
except ImportError as exc:
    raise ImportError(
        "Could not import CPUSimulator from simulator/cpu_simulator.py. "
        f"Original error: {exc}"
    ) from exc

try:
    from debugger import Debugger as _LowLevelDebugger  # simulator/debugger.py
    _HAS_LL_DEBUGGER = True
except ImportError:
    _HAS_LL_DEBUGGER = False


# ---------------------------------------------------------------------------
# ToolchainDebugger — high-level debugger shell
# ---------------------------------------------------------------------------
class ToolchainDebugger:
    """
    Interactive debugger for EduRISC-32v2 binaries.

    Wraps CPUSimulator and provides GDB-style commands over a REPL or
    a programmatic API.
    """

    BANNER = (
        "EduRISC-32v2 Debugger  (type 'help' for commands, 'q' to quit)\n"
        "─────────────────────────────────────────────────────────────────"
    )

    def __init__(self, verbose: bool = False):
        self.sim          = CPUSimulator()
        self.verbose      = verbose
        self._loaded      = False
        self._breakpoints: set[int] = set()
        self._watchpoints: set[int] = set()
        self._hex_path: str = ""

    # ------------------------------------------------------------------
    # File loading
    # ------------------------------------------------------------------
    def load(self, hex_path: str) -> bool:
        """Load an Intel HEX file into the simulator."""
        if not os.path.isfile(hex_path):
            print(f"error: file not found: {hex_path}", file=sys.stderr)
            return False
        try:
            self.sim.load_hex(hex_path)
            self._loaded   = True
            self._hex_path = hex_path
            print(f"Loaded: {hex_path}")
            return True
        except Exception as exc:  # noqa: BLE001
            print(f"error: {exc}", file=sys.stderr)
            return False

    # ------------------------------------------------------------------
    # Execution control
    # ------------------------------------------------------------------
    def step(self, count: int = 1) -> bool:
        """Execute *count* instructions.  Returns False if CPU has halted."""
        for _ in range(count):
            if not self._loaded:
                print("error: no binary loaded. Use 'r <file>' first.")
                return False
            halted = self.sim.step()
            pc     = self.sim.get_pc()
            if pc in self._watchpoints:
                print(f"Watchpoint hit at PC=0x{pc:06X}")
                return False
            if halted:
                print("CPU halted (HLT instruction reached).")
                return False
        return True

    def run_until_break(self) -> str:
        """Run until a breakpoint, watchpoint, HLT, or error."""
        if not self._loaded:
            return "error: no binary loaded"
        while True:
            halted = self.sim.step()
            pc     = self.sim.get_pc()
            if pc in self._breakpoints:
                return f"Breakpoint hit at 0x{pc:06X}"
            if pc in self._watchpoints:
                return f"Watchpoint hit at 0x{pc:06X}"
            if halted:
                return "HLT — simulation complete"

    # ------------------------------------------------------------------
    # Register / memory inspection
    # ------------------------------------------------------------------
    def get_reg(self, name: str) -> Optional[int]:
        """Return the integer value of a register by name (e.g. 'R1', 'PC')."""
        name = name.upper()
        if name == "PC":
            return self.sim.get_pc()
        if name.startswith("R") and name[1:].isdigit():
            idx = int(name[1:])
            if 0 <= idx <= 31:
                return self.sim.get_register(idx)
        return None

    def dump_regs(self) -> str:
        """Return a formatted string of all 32 GPRs + PC."""
        lines = []
        for i in range(0, 32, 4):
            parts = []
            for j in range(4):
                n   = i + j
                val = self.sim.get_register(n)
                parts.append(f"R{n:02d}=0x{val:08X}")
            lines.append("  " + "  ".join(parts))
        lines.append(f"  PC =0x{self.sim.get_pc():08X}")
        return "\n".join(lines)

    def dump_mem(self, addr: int, count: int = 4) -> str:
        """Return a hex dump of *count* words starting at *addr*."""
        lines = []
        for i in range(count):
            a   = addr + i * 4
            val = self.sim.read_memory(a)
            lines.append(f"  0x{a:06X}: 0x{val:08X}")
        return "\n".join(lines)

    def disassemble(self, addr: int, count: int = 8) -> str:
        """Disassemble *count* instructions starting at *addr*."""
        lines = []
        for i in range(count):
            a    = addr + i * 4
            word = self.sim.read_memory(a)
            try:
                from cpu.instruction_set import disassemble as dis_word
                mnem = dis_word(word)
            except Exception:  # noqa: BLE001
                mnem = f"0x{word:08X}"
            marker = "→" if a == self.sim.get_pc() else " "
            lines.append(f" {marker} 0x{a:06X}: {mnem}")
        return "\n".join(lines)

    # ------------------------------------------------------------------
    # Breakpoints & watchpoints
    # ------------------------------------------------------------------
    def add_breakpoint(self, addr: int) -> None:
        self._breakpoints.add(addr)
        print(f"Breakpoint set at 0x{addr:06X}")

    def del_breakpoint(self, addr: int) -> None:
        self._breakpoints.discard(addr)
        print(f"Breakpoint removed from 0x{addr:06X}")

    def add_watchpoint(self, addr: int) -> None:
        self._watchpoints.add(addr)
        print(f"Watchpoint set at 0x{addr:06X}")

    def list_breakpoints(self) -> str:
        if not self._breakpoints:
            return "  (no breakpoints)"
        return "\n".join(f"  0x{a:06X}" for a in sorted(self._breakpoints))

    # ------------------------------------------------------------------
    # REPL
    # ------------------------------------------------------------------
    def repl(self) -> None:
        """Start the interactive debugger REPL."""
        print(self.BANNER)
        if self._hex_path:
            print(f"Loaded: {self._hex_path}")

        while True:
            try:
                line = input("(dbg) ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\nquitting.")
                break

            if not line:
                continue

            parts = shlex.split(line)
            cmd   = parts[0].lower()
            args  = parts[1:]

            if cmd in ("q", "quit", "exit"):
                break

            elif cmd == "help":
                print(
                    "  r/run [file]      — load and start\n"
                    "  s/step            — step one instruction\n"
                    "  si/stepi [n]      — step n instructions\n"
                    "  c/continue        — run to breakpoint / HLT\n"
                    "  b/break <addr>    — set breakpoint (hex addr)\n"
                    "  d/delete <addr>   — remove breakpoint\n"
                    "  bl/breaklist      — list breakpoints\n"
                    "  p/print <R#|PC>   — print register\n"
                    "  pa/printall       — print all registers\n"
                    "  m/mem <addr> [n]  — memory dump (n words)\n"
                    "  w/watch <addr>    — set watchpoint\n"
                    "  dis/disasm [addr] [n]  — disassemble\n"
                    "  q/quit            — exit"
                )

            elif cmd in ("r", "run"):
                path = args[0] if args else self._hex_path
                if path:
                    self.load(path)
                else:
                    print("Usage: r <hex_file>")

            elif cmd in ("s", "step"):
                self.step(1)
                print(self.disassemble(self.sim.get_pc(), 1))

            elif cmd in ("si", "stepi"):
                n = int(args[0]) if args else 1
                self.step(n)
                print(self.disassemble(self.sim.get_pc(), 1))

            elif cmd in ("c", "continue"):
                msg = self.run_until_break()
                print(msg)

            elif cmd in ("b", "break"):
                if args:
                    self.add_breakpoint(int(args[0], 16))
                else:
                    print("Usage: b <hex_addr>")

            elif cmd in ("d", "delete"):
                if args:
                    self.del_breakpoint(int(args[0], 16))
                else:
                    print("Usage: d <hex_addr>")

            elif cmd in ("bl", "breaklist"):
                print(self.list_breakpoints())

            elif cmd in ("p", "print"):
                if args:
                    val = self.get_reg(args[0])
                    if val is None:
                        print(f"Unknown register: {args[0]}")
                    else:
                        print(f"  {args[0].upper()} = 0x{val:08X}  ({val})")
                else:
                    print("Usage: p <R#|PC>")

            elif cmd in ("pa", "printall"):
                print(self.dump_regs())

            elif cmd in ("m", "mem"):
                if args:
                    addr  = int(args[0], 16)
                    count = int(args[1]) if len(args) > 1 else 4
                    print(self.dump_mem(addr, count))
                else:
                    print("Usage: m <hex_addr> [word_count]")

            elif cmd in ("w", "watch"):
                if args:
                    self.add_watchpoint(int(args[0], 16))
                else:
                    print("Usage: w <hex_addr>")

            elif cmd in ("dis", "disasm"):
                addr  = int(args[0], 16) if args else self.sim.get_pc()
                count = int(args[1]) if len(args) > 1 else 8
                print(self.disassemble(addr, count))

            else:
                print(f"Unknown command: {cmd}  (type 'help')")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="toolchain-debugger",
        description="EduRISC-32v2 Interactive Debugger",
    )
    p.add_argument("hex_file", nargs="?", help="Intel HEX binary to load")
    p.add_argument(
        "--batch", "-x",
        default=None,
        metavar="CMDS",
        help="Semicolon-separated commands to execute non-interactively",
    )
    p.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output",
    )
    return p


def main(argv: Optional[list] = None) -> int:
    parser = _build_parser()
    args   = parser.parse_args(argv)

    dbg = ToolchainDebugger(verbose=args.verbose)

    if args.hex_file:
        dbg.load(args.hex_file)

    if args.batch:
        # Non-interactive batch mode
        for raw_cmd in args.batch.split(";"):
            cmd = raw_cmd.strip()
            if cmd:
                print(f"(dbg) {cmd}")
                # Simulate the REPL by calling a minimal command dispatcher
                parts = shlex.split(cmd)
                if parts[0].lower() in ("q", "quit"):
                    break
                elif parts[0].lower() in ("pa", "printall"):
                    print(dbg.dump_regs())
                elif parts[0].lower() in ("si", "stepi"):
                    n = int(parts[1]) if len(parts) > 1 else 1
                    dbg.step(n)
                elif parts[0].lower() in ("c", "continue", "r", "run"):
                    print(dbg.run_until_break())
        return 0

    # Interactive REPL
    dbg.repl()
    return 0


if __name__ == "__main__":
    sys.exit(main())
