#!/usr/bin/env python3
"""
main.py — EduRISC-16 Educational CPU Lab
Ponto de entrada unificado para todas as ferramentas.

Uso:
    python main.py assemble  <arquivo.asm>  [-o saida.hex] [--binary] [--listing]
    python main.py compile   <arquivo.c>    [-o saida.asm] [--show-ast]
    python main.py build     <arquivo.c>    [-o saida.hex]
    python main.py simulate  <arquivo.hex>  [--max-cycles N] [--trace]
    python main.py debug     <arquivo.hex>
    python main.py run       <arquivo.asm>  [--max-cycles N]
    python main.py demo
"""

import sys
import os
import argparse

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_hex(path: str) -> list[int]:
    """Carrega arquivo .hex (um valor hex por linha) em lista de int."""
    words = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(";"):
                words.append(int(line, 16))
    return words


def _print_ast(node, indent: int = 0):
    """Imprime o AST de forma recursiva e legivel."""
    pad = "  " * indent
    name = type(node).__name__
    from compiler.ast_nodes import (
        Program, FuncDef, VarDecl, Assign, IfStmt, WhileStmt,
        ReturnStmt, ExprStmt, Block, BinOp, UnaryOp, VarRef,
        IntLiteral, FuncCall
    )
    match node:
        case Program(functions=funcs):
            print(f"{pad}Program")
            for f in funcs: _print_ast(f, indent + 1)
        case FuncDef(name=n, params=p, body=b):
            print(f"{pad}FuncDef '{n}' params={p}")
            for s in b: _print_ast(s, indent + 1)
        case VarDecl(name=n, init=init):
            print(f"{pad}VarDecl '{n}'")
            if init: _print_ast(init, indent + 1)
        case Assign(name=n, value=v):
            print(f"{pad}Assign '{n}'")
            _print_ast(v, indent + 1)
        case IfStmt(cond=c, then_body=t, else_body=e):
            print(f"{pad}If")
            _print_ast(c, indent + 1)
            print(f"{pad}  Then:")
            for s in t: _print_ast(s, indent + 2)
            if e:
                print(f"{pad}  Else:")
                for s in e: _print_ast(s, indent + 2)
        case WhileStmt(cond=c, body=b):
            print(f"{pad}While")
            _print_ast(c, indent + 1)
            for s in b: _print_ast(s, indent + 1)
        case ReturnStmt(value=v):
            print(f"{pad}Return")
            if v: _print_ast(v, indent + 1)
        case ExprStmt(expr=e):
            print(f"{pad}ExprStmt")
            _print_ast(e, indent + 1)
        case Block(stmts=ss):
            for s in ss: _print_ast(s, indent)
        case BinOp(op=op, left=l, right=r):
            print(f"{pad}BinOp '{op}'")
            _print_ast(l, indent + 1)
            _print_ast(r, indent + 1)
        case UnaryOp(op=op, operand=o):
            print(f"{pad}UnaryOp '{op}'")
            _print_ast(o, indent + 1)
        case VarRef(name=n):
            print(f"{pad}VarRef '{n}'")
        case IntLiteral(value=v):
            print(f"{pad}IntLiteral {v}")
        case FuncCall(name=n, args=a):
            print(f"{pad}FuncCall '{n}'")
            for arg in a: _print_ast(arg, indent + 1)
        case _:
            print(f"{pad}{name}")


def _load_bin(path: str) -> list[int]:
    """Carrega arquivo binário (big-endian, 2 bytes por palavra)."""
    data = open(path, "rb").read()
    words = []
    for i in range(0, len(data) - 1, 2):
        words.append((data[i] << 8) | data[i+1])
    return words


# ---------------------------------------------------------------------------
# Comando: assemble
# ---------------------------------------------------------------------------

def cmd_assemble(args):
    from assembler import Assembler, AssemblerError

    src_path = args.input
    if not os.path.exists(src_path):
        print(f"[ERRO] Arquivo não encontrado: {src_path}", file=sys.stderr)
        sys.exit(1)

    source = open(src_path, encoding="utf-8").read()

    try:
        asm   = Assembler()
        words = asm.assemble(source)
    except AssemblerError as e:
        print(f"[ERRO Assembly] {e}", file=sys.stderr)
        sys.exit(1)

    if args.listing:
        print(asm.listing(words, source))

    out = args.output or (src_path.rsplit(".", 1)[0] + (".bin" if args.binary else ".hex"))
    if args.binary:
        asm.write_binary(words, out)
        print(f"Binário escrito em: {out}  ({len(words)} palavras)")
    else:
        asm.write_hex(words, out)
        print(f"HEX escrito em: {out}  ({len(words)} palavras)")


# ---------------------------------------------------------------------------
# Comando: compile
# ---------------------------------------------------------------------------

def cmd_compile(args):
    from compiler import compile_source, parse_source, CompileError

    src_path = args.input
    if not os.path.exists(src_path):
        print(f"[ERRO] Arquivo não encontrado: {src_path}", file=sys.stderr)
        sys.exit(1)

    source = open(src_path, encoding="utf-8").read()

    if getattr(args, "show_ast", False):
        try:
            ast = parse_source(source)
        except CompileError as e:
            print(f"[ERRO Parser] {e}", file=sys.stderr)
            sys.exit(1)
        _print_ast(ast)
        return

    try:
        asm_code = compile_source(source)
    except CompileError as e:
        print(f"[ERRO Compilador] {e}", file=sys.stderr)
        sys.exit(1)

    out = args.output or (src_path.rsplit(".", 1)[0] + ".asm")
    open(out, "w", encoding="utf-8").write(asm_code)
    print(f"Assembly gerado em: {out}")
    print(asm_code)


# ---------------------------------------------------------------------------
# Comando: build (C → hex)
# ---------------------------------------------------------------------------

def cmd_build(args):
    from compiler import compile_source, CompileError
    from assembler import Assembler, AssemblerError

    src_path = args.input
    if not os.path.exists(src_path):
        print(f"[ERRO] Arquivo não encontrado: {src_path}", file=sys.stderr)
        sys.exit(1)

    source = open(src_path, encoding="utf-8").read()

    # Etapa 1: compilar
    try:
        asm_code = compile_source(source)
    except CompileError as e:
        print(f"[ERRO Compilador] {e}", file=sys.stderr)
        sys.exit(1)

    print(f"[1/2] Compilação OK — {len(asm_code.splitlines())} linhas de assembly")

    # Etapa 2: montar
    try:
        asm   = Assembler()
        words = asm.assemble(asm_code)
    except AssemblerError as e:
        print(f"[ERRO Assembly] {e}", file=sys.stderr)
        print("--- Assembly gerado ---")
        for i, line in enumerate(asm_code.splitlines(), 1):
            print(f"{i:4d}: {line}")
        sys.exit(1)

    out = args.output or (src_path.rsplit(".", 1)[0] + ".hex")
    asm.write_hex(words, out)
    print(f"[2/2] Assembly OK — {len(words)} palavras")
    print(f"Binário HEX escrito em: {out}")


# ---------------------------------------------------------------------------
# Comando: simulate
# ---------------------------------------------------------------------------

def cmd_simulate(args):
    from simulator import CPUSimulator
    from assembler  import Assembler

    path = args.input
    if not os.path.exists(path):
        print(f"[ERRO] Arquivo não encontrado: {path}", file=sys.stderr)
        sys.exit(1)

    # Detect format
    if path.endswith(".asm"):
        src   = open(path, encoding="utf-8").read()
        asm   = Assembler()
        words = asm.assemble(src)
    elif path.endswith(".bin"):
        words = _load_bin(path)
    else:
        words = _load_hex(path)

    sim = CPUSimulator()
    sim.load_program(words)

    max_cycles = args.max_cycles or 100_000
    sim.run(max_cycles=max_cycles)

    st = sim.stats
    print(f"\n=== Simulação Concluída ===")
    print(f"  Ciclos:      {st.cycles}")
    print(f"  Instruções:  {st.instructions}")
    print(f"  Stalls:      {st.stalls}")
    print(f"  Flushes:     {st.flushes}")
    ipc = st.instructions / max(1, st.cycles)
    print(f"  IPC:         {ipc:.3f}")
    print(f"\n  Registradores finais:")
    for i in range(16):
        v = sim.rf[i]
        if v:
            print(f"    R{i:2d} = 0x{v:04X}  ({v})")

    if args.trace:
        print("\n=== Log de Eventos ===")
        for entry in sim.log:
            print(" ", entry)


# ---------------------------------------------------------------------------
# Comando: debug
# ---------------------------------------------------------------------------

def cmd_debug(args):
    from simulator import CPUSimulator, Debugger
    from assembler  import Assembler

    path = args.input
    if not os.path.exists(path):
        print(f"[ERRO] Arquivo não encontrado: {path}", file=sys.stderr)
        sys.exit(1)

    if path.endswith(".asm"):
        src   = open(path, encoding="utf-8").read()
        asm   = Assembler()
        words = asm.assemble(src)
        syms  = {v: k for k, v in asm._symbols.items()}
    elif path.endswith(".bin"):
        words = _load_bin(path)
        syms  = {}
    else:
        words = _load_hex(path)
        syms  = {}

    sim = CPUSimulator()
    sim.load_program(words)
    dbg = Debugger(sim, symbols=syms)
    dbg.run_interactive()


# ---------------------------------------------------------------------------
# Comando: run (asm direto, sem arquivo de saída)
# ---------------------------------------------------------------------------

def cmd_run(args):
    from simulator import CPUSimulator
    from assembler  import Assembler

    path = args.input
    if not os.path.exists(path):
        print(f"[ERRO] Arquivo não encontrado: {path}", file=sys.stderr)
        sys.exit(1)

    src   = open(path, encoding="utf-8").read()
    asm   = Assembler()
    words = asm.assemble(src)

    sim = CPUSimulator()
    sim.load_program(words)

    max_cycles = args.max_cycles or 10_000
    sim.run(max_cycles=max_cycles)

    st = sim.stats
    print(f"Ciclos: {st.cycles}  |  Instruções: {st.instructions}")
    print("Registradores:")
    for i in range(16):
        v = sim.rf[i]
        print(f"  R{i:2d} = 0x{v:04X}  ({v})", end="  " if i % 4 != 3 else "\n")


# ---------------------------------------------------------------------------
# Comando: demo
# ---------------------------------------------------------------------------

_DEMO_ASM = """\
; Demo: soma de 1 a 5 = 15
        .ORG 0x000
        LOAD R4, [R0+8]    ; R4 = endereço base da área de dados (0x010)
        LOAD R1, [R4+0]    ; R1 = 5
        LOAD R2, [R4+1]    ; R2 = 0 (acc)
        LOAD R3, [R4+2]    ; R3 = 1
LOOP:   ADD  R2, R2, R1    ; acc += i
        SUB  R1, R1, R3    ; i--
        JNZ  LOOP
        HLT

        .ORG 0x008
        .WORD 0x010        ; endereço base (pointer para dados)

        .ORG 0x010
        .WORD 5
        .WORD 0
        .WORD 1
"""

_DEMO_C = """\
int main() {
    int n = 5;
    int acc = 0;
    int one = 1;
    while (n) {
        acc = acc + n;
        n = n - one;
    }
    return acc;
}
"""

def cmd_demo(_args):
    from assembler  import Assembler
    from compiler   import compile_source
    from simulator  import CPUSimulator

    print("=" * 60)
    print("  DEMO 1: Assembly → Simulador")
    print("=" * 60)
    print("Código:\n", _DEMO_ASM)

    asm   = Assembler()
    words = asm.assemble(_DEMO_ASM)
    sim   = CPUSimulator()
    sim.load_program(words)
    sim.run(max_cycles=1000)

    st = sim.stats
    print(f"Resultado em R2 = {sim.rf[2]}  (esperado: 15)")
    print(f"Ciclos: {st.cycles}  |  IPC: {st.instructions / max(1, st.cycles):.3f}")

    print("\n" + "=" * 60)
    print("  DEMO 2: C-like → Compilador → Assembly → Simulador")
    print("=" * 60)
    print("Código C:\n", _DEMO_C)

    asm_code = compile_source(_DEMO_C)
    print("Assembly gerado:\n", asm_code)

    try:
        words2 = asm.assemble(asm_code)
        sim2   = CPUSimulator()
        sim2.load_program(words2)
        sim2.run(max_cycles=5000)
        st2 = sim2.stats
        print(f"Resultado em R0 = {sim2.rf[0]}  (esperado: 15)")
    except Exception as e:
        print(f"[Nota] Simulação do código compilado: {e}")


# ---------------------------------------------------------------------------
# Parser de comandos
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="edurisclab",
        description="EduRISC-16 Educational CPU Lab",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # assemble
    p_asm = sub.add_parser("assemble", help="Monta arquivo .asm → .hex/.bin")
    p_asm.add_argument("input")
    p_asm.add_argument("-o", "--output")
    p_asm.add_argument("--binary",  action="store_true", help="Saída binária")
    p_asm.add_argument("--listing", action="store_true", help="Imprime listagem")

    # compile
    p_cc = sub.add_parser("compile", help="Compila arquivo .c → .asm")
    p_cc.add_argument("input")
    p_cc.add_argument("-o", "--output")
    p_cc.add_argument("--show-ast", action="store_true", help="Imprime AST e sai")

    # build
    p_build = sub.add_parser("build", help="Compila + monta .c → .hex")
    p_build.add_argument("input")
    p_build.add_argument("-o", "--output")

    # simulate
    p_sim = sub.add_parser("simulate", help="Simula arquivo .hex/.asm/.bin")
    p_sim.add_argument("input")
    p_sim.add_argument("--max-cycles", type=int, default=100_000)
    p_sim.add_argument("--trace", action="store_true", help="Imprime log de eventos")

    # debug
    p_dbg = sub.add_parser("debug", help="Depurador interativo")
    p_dbg.add_argument("input")

    # run
    p_run = sub.add_parser("run", help="Monta e executa arquivo .asm")
    p_run.add_argument("input")
    p_run.add_argument("--max-cycles", type=int, default=10_000)

    # demo
    sub.add_parser("demo", help="Executa demonstração integrada")

    args = parser.parse_args()

    dispatch = {
        "assemble": cmd_assemble,
        "compile":  cmd_compile,
        "build":    cmd_build,
        "simulate": cmd_simulate,
        "debug":    cmd_debug,
        "run":      cmd_run,
        "demo":     cmd_demo,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
