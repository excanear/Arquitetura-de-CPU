"""
debugger.py — Debugger Educacional para EduRISC-32v2

Interface interativa de linha de comando para depuração de programas.

Comandos disponíveis:
  s / step            — executa um ciclo
  r / run             — executa até HLT ou breakpoint
  r N                 — executa N ciclos
  b / break ADDR      — define breakpoint no endereço ADDR (hex ou dec)
  bl / breaklist      — lista breakpoints
  bd / breakdel ADDR  — remove breakpoint
  p / print           — dump de registradores
  m / mem ADDR [N]    — dump de memória (N palavras, padrão 16)
  d / dis ADDR [N]    — disassembly de N instruções a partir de ADDR
  h / history [N]     — mostra últimos N snapshots do pipeline
  l / log             — mostra log de eventos
  sym / symbols       — lista símbolos do programa
  q / quit            — sai do debugger
  ? / help            — lista comandos
"""

import sys
from simulator.cpu_simulator import CPUSimulator
from cpu.instruction_set import disassemble, WORD_MASK


class Debugger:
    """
    Debugger educacional interativo.

    Uso:
        from assembler import Assembler
        from simulator.cpu_simulator import CPUSimulator
        from simulator.debugger import Debugger

        asm = Assembler()
        words = asm.assemble(source)

        sim = CPUSimulator()
        sim.load_program(words)

        dbg = Debugger(sim, symbols=asm.symbols)
        dbg.run_interactive()
    """

    BANNER = """
╔══════════════════════════════════════════════════════╗
║         EduRISC-32v2  Debugger Educacional           ║
║  Digite '?' ou 'help' para lista de comandos         ║
╚══════════════════════════════════════════════════════╝
"""

    def __init__(self, sim: CPUSimulator, symbols: dict[str, int] | None = None):
        self.sim         = sim
        self.symbols     = symbols or {}
        self.breakpoints: set[int] = set()
        self._addr_to_sym: dict[int, str] = {v: k for k, v in self.symbols.items()}

    # -----------------------------------------------------------------------
    # Shell interativo
    # -----------------------------------------------------------------------

    def run_interactive(self):
        """Inicia o loop interativo do debugger."""
        print(self.BANNER)
        self._print_state()

        while True:
            try:
                raw = input("(dbg) ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\nSaindo do debugger.")
                break

            if not raw:
                continue

            parts = raw.split()
            cmd   = parts[0].lower()
            args  = parts[1:]

            if not self._dispatch(cmd, args):
                break

    # -----------------------------------------------------------------------
    # Dispatcher de comandos
    # -----------------------------------------------------------------------

    def _dispatch(self, cmd: str, args: list[str]) -> bool:
        """Retorna False para sair do loop."""
        match cmd:
            case "s" | "step":
                self._cmd_step(1)
            case "r" | "run":
                n = int(args[0]) if args else None
                self._cmd_run(n)
            case "b" | "break":
                self._cmd_break(args)
            case "bl" | "breaklist":
                self._cmd_break_list()
            case "bd" | "breakdel":
                self._cmd_break_del(args)
            case "p" | "print":
                self._cmd_print()
            case "m" | "mem":
                self._cmd_mem(args)
            case "d" | "dis":
                self._cmd_dis(args)
            case "h" | "history":
                self._cmd_history(args)
            case "l" | "log":
                self._cmd_log()
            case "sym" | "symbols":
                self._cmd_symbols()
            case "q" | "quit" | "exit":
                print("Saindo.")
                return False
            case "?" | "help":
                self._cmd_help()
            case _:
                print(f"  Comando desconhecido: '{cmd}'. Digite '?' para ajuda.")

        return True

    # -----------------------------------------------------------------------
    # Implementação dos comandos
    # -----------------------------------------------------------------------

    def _cmd_step(self, n: int = 1):
        for _ in range(n):
            snap = self.sim.step()
            if snap is None:
                print("  CPU parada (HLT).")
                break
            print(f"  {snap}")
        self._print_state()

    def _cmd_run(self, max_cycles: int | None):
        """Executa até HLT, breakpoint ou max_cycles ciclos."""
        limit = max_cycles or 200_000
        for _ in range(limit):
            if self.sim.halted:
                print("  CPU parada (HLT).")
                break
            if self.sim.pc in self.breakpoints:
                print(f"  *** Breakpoint em 0x{self.sim.pc:04X} ***")
                break
            self.sim.step()
        self._print_state()

    def _cmd_break(self, args: list[str]):
        if not args:
            print("  Uso: break <endereço>")
            return
        addr = self._parse_addr(args[0])
        self.breakpoints.add(addr)
        sym  = self._addr_to_sym.get(addr, "")
        print(f"  Breakpoint definido em 0x{addr:04X}{(' (' + sym + ')') if sym else ''}")

    def _cmd_break_list(self):
        if not self.breakpoints:
            print("  Sem breakpoints definidos.")
            return
        print("  Breakpoints:")
        for a in sorted(self.breakpoints):
            sym = self._addr_to_sym.get(a, "")
            print(f"    0x{a:04X}  {sym}")

    def _cmd_break_del(self, args: list[str]):
        if not args:
            print("  Uso: bd <endereço>")
            return
        addr = self._parse_addr(args[0])
        self.breakpoints.discard(addr)
        print(f"  Breakpoint removido: 0x{addr:04X}")

    def _cmd_print(self):
        print("\n  Estado dos Registradores:")
        print(self.sim.rf.dump())
        print()

    def _cmd_mem(self, args: list[str]):
        start = self._parse_addr(args[0]) if args else self.sim.pc
        n     = int(args[1]) if len(args) > 1 else 16
        self.sim.dump_memory(start, n)

    def _cmd_dis(self, args: list[str]):
        start = self._parse_addr(args[0]) if args else self.sim.pc
        n     = int(args[1]) if len(args) > 1 else 10
        print(f"\n  Disassembly @ 0x{start:04X}:")
        for i in range(n):
            addr = start + i
            if addr >= len(self.sim.mem):
                break
            word = self.sim.mem[addr]
            try:
                dis = disassemble(word)
            except Exception:
                dis = f"??? (0x{word:04X})"
            sym  = self._addr_to_sym.get(addr, "")
            cur  = "→" if addr == self.sim.pc else " "
            bp   = "●" if addr in self.breakpoints else " "
            print(f"  {cur}{bp} 0x{addr:04X}: {word:04X}  {dis:<20} {sym}")
        print()

    def _cmd_history(self, args: list[str]):
        n   = int(args[0]) if args else 10
        h   = self.sim.history[-n:]
        if not h:
            print("  Sem histórico disponível.")
            return
        print(f"\n  Últimos {len(h)} snapshots do pipeline:")
        for snap in h:
            print(f"  {snap}")
        print()

    def _cmd_log(self):
        if not self.sim.log:
            print("  Log vazio.")
            return
        print("\n  Log de eventos:")
        for entry in self.sim.log:
            print(f"  {entry}")
        print()

    def _cmd_symbols(self):
        if not self.symbols:
            print("  Nenhum símbolo disponível.")
            return
        print("\n  Tabela de Símbolos:")
        for name, addr in sorted(self.symbols.items(), key=lambda x: x[1]):
            print(f"    {name:<20} 0x{addr:04X}")
        print()

    def _cmd_help(self):
        print("""
  Comandos disponíveis:
    s / step           — executa 1 ciclo
    r / run [N]        — executa até HLT/breakpoint (ou N ciclos)
    b  <addr>          — define breakpoint
    bl                 — lista breakpoints
    bd <addr>          — remove breakpoint
    p  / print         — dump de registradores
    m  <addr> [N]      — dump de memória (N palavras)
    d  <addr> [N]      — disassembly de N instruções
    h  [N]             — histórico do pipeline (N últimos ciclos)
    l  / log           — log de eventos da CPU
    sym / symbols      — tabela de símbolos
    q  / quit          — sair
    ? / help           — este texto
""")

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _parse_addr(self, s: str) -> int:
        """Aceita '0x1F', '31' ou nome de label."""
        if s in self.symbols:
            return self.symbols[s]
        try:
            return int(s, 0)
        except ValueError:
            print(f"  Endereço inválido: '{s}'")
            return 0

    def _print_state(self):
        if self.sim.halted:
            return
        pc   = self.sim.pc
        word = self.sim.mem[pc] if pc < len(self.sim.mem) else 0xFFFF
        try:
            dis = disassemble(word)
        except Exception:
            dis = f"0x{word:04X}"
        sym = self._addr_to_sym.get(pc, "")
        print(f"\n  PC=0x{pc:04X} [{dis}] {sym}  "
              f"Ciclos={self.sim.stats.cycles}  "
              f"Flags={self.sim.rf.flags}\n")
