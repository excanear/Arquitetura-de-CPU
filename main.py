#!/usr/bin/env python3
"""
main.py — EduRISC-32v2 Educational CPU Lab
Ponto de entrada unificado para todas as ferramentas.

Uso — ferramentas EduRISC-32v2 (Python):
    python main.py assemble  <arquivo.asm>  [-o saida.hex] [--binary] [--listing]
    python main.py compile   <arquivo.c>    [-o saida.asm] [--show-ast]
    python main.py build     <arquivo.c>    [-o saida.hex]
    python main.py simulate  <arquivo.hex>  [--max-cycles N] [--trace]
    python main.py debug     <arquivo.hex>
    python main.py run       <arquivo.asm>  [--max-cycles N]
    python main.py link      <obj1> [obj2...] -o prog.hex
    python main.py load      <prog.hex> [--format mem|coe|vinit] [-o saida]
    python main.py demo

Uso — RTL EduRISC-32v2 (Icarus Verilog):
    python main.py rtl-sim   <prog.hex>           # simula RTL com iverilog
    python main.py compare   <prog.hex>           # compara Python vs RTL
    python main.py rtl-build                      # compila apenas o RTL
    python main.py fpga-build                     # gera bitstream via Vivado batch
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
    """Carrega arquivo binário (big-endian, 4 bytes por palavra de 32 bits)."""
    data = open(path, "rb").read()
    words = []
    for i in range(0, len(data) - 3, 4):
        words.append((data[i] << 24) | (data[i+1] << 16) | (data[i+2] << 8) | data[i+3])
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
        print(asm.listing(words))

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
    print(f"\n  Registradores finais (n\u00e3o-zero):")
    for i in range(32):
        v = sim.rf[i]
        if v:
            print(f"    R{i:2d} = 0x{v:08X}  ({v})")

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

    sim = CPUSimulator(num_regs=32)
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

    sim = CPUSimulator(num_regs=32)
    sim.load_program(words)

    max_cycles = args.max_cycles or 10_000
    sim.run(max_cycles=max_cycles)

    st = sim.stats
    print(f"Ciclos: {st.cycles}  |  Instruções: {st.instructions}")
    print("Registradores (n\u00e3o-zero):")
    for i in range(32):
        v = sim.rf[i]
        if v:
            print(f"  R{i:2d} = 0x{v:08X}  ({v})", end="  " if i % 4 != 3 else "\n")


# ---------------------------------------------------------------------------
# Comando: demo
# ---------------------------------------------------------------------------

_DEMO_ASM = """\
; Demo EduRISC-32v2: soma de 1 a 5 = 15
        .org 0x000000
        MOVI  R1, 5        ; R1 = n = 5
        MOVI  R2, 0        ; R2 = acc = 0
LOOP:
        ADD   R2, R2, R1   ; acc += n
        ADDI  R1, R1, -1   ; n--
        BNE   R1, R0, LOOP ; enquanto n != 0
        HLT
"""

_DEMO_C = """\
int main() {
    int n = 5;
    int acc = 0;
    while (n) {
        acc = acc + n;
        n = n - 1;
    }
    return acc;
}
"""

# ---------------------------------------------------------------------------
# RTL helpers (EduRISC-32 / Icarus Verilog)
# ---------------------------------------------------------------------------

import subprocess
import tempfile
import shutil

_RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rtl_v")
_TB_DIR  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "testbench")
_RTL_SOURCES_FLAT = [
    "isa_pkg.vh",
    "register_file.v", "program_counter.v",
    "execute/alu.v", "execute/multiplier.v", "execute/divider.v", "execute/branch_unit.v",
    "decode/instruction_decoder.v", "control/control_unit.v",
    "hazard/hazard_unit.v", "execute/forwarding_unit.v",
    "pipeline_if.v", "pipeline_id.v", "pipeline_ex.v", "pipeline_mem.v", "pipeline_wb.v",
    "cache/icache.v", "cache/dcache.v", "cache/cache_controller.v",
    "mmu/tlb.v", "mmu/page_table.v", "mmu/mmu.v",
    "interrupts/interrupt_controller.v", "interrupts/exception_handler.v",
    "memory_interface.v", "perf_counters.v", "cpu_top.v",
]


def _rtl_source_files():
    return [os.path.join(_RTL_DIR, f) for f in _RTL_SOURCES_FLAT if not f.endswith(".vh")]


def _find_iverilog():
    exe = shutil.which("iverilog")
    if exe:
        return exe
    for p in [r"C:\iverilog\bin\iverilog.exe", "/usr/bin/iverilog", "/usr/local/bin/iverilog"]:
        if os.path.isfile(p):
            return p
    return None





def cmd_rtl_build(_args):
    iverilog = _find_iverilog()
    if not iverilog:
        print("[ERRO] iverilog não encontrado — instale o Icarus Verilog.")
        sys.exit(1)
    sources = _rtl_source_files()
    missing = [s for s in sources if not os.path.exists(s)]
    if missing:
        print("[ERRO] Arquivos RTL ausentes:"); [print(" ", m) for m in missing]
        sys.exit(1)
    cmd = [iverilog, "-g2012", f"-I{_RTL_DIR}", "-o", os.devnull] + sources
    print(f"[rtl-build] Verificando {len(sources)} fontes RTL...")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode == 0:
        print("[rtl-build] OK — nenhum erro de sintaxe.")
    else:
        print("[rtl-build] FALHA:\n", r.stderr); sys.exit(1)


def cmd_rtl_sim(args):
    iverilog = _find_iverilog()
    vvp_path = shutil.which("vvp")
    if iverilog and not vvp_path:
        vvp_path = os.path.join(os.path.dirname(iverilog), "vvp")
        if not os.path.isfile(vvp_path):
            vvp_path = None
    if not iverilog or not vvp_path:
        print("[ERRO] iverilog/vvp não encontrados — instale o Icarus Verilog."); sys.exit(1)

    hex_file = os.path.abspath(args.input)
    if not os.path.exists(hex_file):
        print(f"[ERRO] Arquivo não encontrado: {hex_file}"); sys.exit(1)

    tb_file = os.path.join(_TB_DIR, "cpu_tb.v")
    with tempfile.TemporaryDirectory() as tmpdir:
        sim_out = os.path.join(tmpdir, "sim.out")
        sources = _rtl_source_files() + [tb_file]
        compile_cmd = [iverilog, "-g2012", f"-I{_RTL_DIR}",
                       f'-DIMEM_INIT_FILE="{hex_file}"', "-o", sim_out] + sources
        print("[rtl-sim] Compilando RTL...")
        r = subprocess.run(compile_cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("[rtl-sim] Erro de compilação:\n", r.stderr); sys.exit(1)
        print("[rtl-sim] Executando simulação...")
        try:
            r2 = subprocess.run([vvp_path, sim_out], capture_output=True, text=True,
                                timeout=getattr(args, "timeout", 30))
        except subprocess.TimeoutExpired:
            print("[rtl-sim] TIMEOUT."); sys.exit(1)
        print(r2.stdout)
        if r2.returncode != 0:
            print(r2.stderr)
        vcd = os.path.join(_TB_DIR, "dump.vcd")
        if getattr(args, "waves", False) and os.path.exists(vcd):
            gtkwave = shutil.which("gtkwave")
            if gtkwave:
                subprocess.Popen([gtkwave, vcd])
            else:
                print(f"[rtl-sim] VCD gerado em {vcd} (gtkwave não encontrado)")


# ---------------------------------------------------------------------------
# Comando: link
# ---------------------------------------------------------------------------

def cmd_link(args):
    from toolchain import Linker, LinkerError

    if not args.files:
        print("[ERRO] Nenhum arquivo objeto fornecido.", file=sys.stderr); sys.exit(1)

    out = args.output or "out.hex"
    lnk = Linker()
    for f in args.files:
        if not os.path.exists(f):
            print(f"[ERRO] Arquivo não encontrado: {f}", file=sys.stderr); sys.exit(1)
        try:
            lnk.add_object(f)
        except LinkerError as e:
            print(f"[ERRO Linker] {e}", file=sys.stderr); sys.exit(1)

    try:
        lnk.link(out)
    except LinkerError as e:
        print(f"[ERRO Linker] {e}", file=sys.stderr); sys.exit(1)

    print(f"Linker OK — saída: {out}")


# ---------------------------------------------------------------------------
# Comando: load (hex → mem/coe/vinit)
# ---------------------------------------------------------------------------

def cmd_load(args):
    from toolchain import Loader, LoaderError

    if not os.path.exists(args.input):
        print(f"[ERRO] Arquivo não encontrado: {args.input}", file=sys.stderr); sys.exit(1)

    try:
        loader = Loader()
        loader.load_hex(args.input)
    except LoaderError as e:
        print(f"[ERRO Loader] {e}", file=sys.stderr); sys.exit(1)

    fmt = getattr(args, "format", "mem")
    base = os.path.splitext(args.output or args.input)[0]

    if fmt == "coe":
        out = (args.output or base + ".coe")
        loader.write_coe(out)
    elif fmt == "vinit":
        out = (args.output or base + "_init.v")
        loader.write_verilog_init(out)
    else:  # mem
        out = (args.output or base + ".mem")
        loader.write_mem(out)

    print(f"Loader OK [{fmt}] — saída: {out}  ({len(loader.to_mem_list())} words)")


# ---------------------------------------------------------------------------
# Comando: fpga-build
# ---------------------------------------------------------------------------

def cmd_fpga_build(_args):
    vivado = shutil.which("vivado")
    if not vivado:
        for p in [r"C:\Xilinx\Vivado\2023.2\bin\vivado.bat",
                  r"C:\Xilinx\Vivado\2022.2\bin\vivado.bat"]:
            if os.path.exists(p):
                vivado = p
                break
    if not vivado:
        print("[ERRO] Vivado não encontrado. Adicione ao PATH ou instale.")
        sys.exit(1)

    tcl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fpga", "build.tcl")
    if not os.path.exists(tcl):
        print(f"[ERRO] Script Tcl não encontrado: {tcl}"); sys.exit(1)

    print(f"[fpga-build] Executando Vivado batch: {tcl}")
    r = subprocess.run([vivado, "-mode", "batch", "-source", tcl],
                       capture_output=False, text=True)
    if r.returncode == 0:
        print("[fpga-build] Bitstream gerado com sucesso.")
    else:
        print(f"[fpga-build] FALHA (código {r.returncode}).")
        sys.exit(1)


def cmd_compare(args):
    import re
    from simulator import CPUSimulator

    hex_file = args.input
    if not os.path.exists(hex_file):
        print(f"[ERRO] Arquivo não encontrado: {hex_file}"); sys.exit(1)

    # Python sim
    words = _load_hex(hex_file)
    sim = CPUSimulator()
    sim.load_program(words)
    sim.run(max_cycles=500_000)
    py_regs = list(sim.rf)

    # RTL sim
    rtl_regs = None
    iverilog = _find_iverilog()
    vvp_path = shutil.which("vvp")
    if iverilog and not vvp_path:
        vvp_path = os.path.join(os.path.dirname(iverilog), "vvp")
        if not os.path.isfile(vvp_path):
            vvp_path = None
    if iverilog and vvp_path:
        tb_file = os.path.join(_TB_DIR, "cpu_tb.v")
        sources = _rtl_source_files() + [tb_file]
        with tempfile.TemporaryDirectory() as tmpdir:
            sim_out = os.path.join(tmpdir, "sim.out")
            hex_abs = os.path.abspath(hex_file)
            compile_cmd = [iverilog, "-g2012", f"-I{_RTL_DIR}",
                           f'-DIMEM_INIT_FILE="{hex_abs}"', "-o", sim_out] + sources
            r = subprocess.run(compile_cmd, capture_output=True, text=True)
            if r.returncode == 0:
                r2 = subprocess.run([vvp_path, sim_out], capture_output=True, text=True,
                                    timeout=30)
                rtl_regs = [0] * 16
                for m in re.finditer(r'R(\d+)\s*=\s*0x([0-9A-Fa-f]+)', r2.stdout):
                    idx = int(m.group(1))
                    if idx < 16:
                        rtl_regs[idx] = int(m.group(2), 16)

    print("=" * 62)
    print("  Comparação EduRISC Python vs RTL")
    print("=" * 62)
    print(f"  {'Reg':<6}  {'Python':>12}  {'RTL':>12}  Match")
    print("  " + "-" * 48)
    all_match = True
    for i in range(32):
        pv = py_regs[i] if i < len(py_regs) else 0
        rv = rtl_regs[i] if rtl_regs is not None and i < len(rtl_regs) else None
        match_ch = ("OK" if rv is None else ("OK" if pv == rv else "XX"))
        if rv is not None and pv != rv:
            all_match = False
        rtl_str = f"0x{rv:08X}" if rv is not None else "    N/A    "
        if pv or (rv is not None and rv != 0):
            print(f"  R{i:<4}  0x{pv:08X}   {rtl_str}   {match_ch}")
    if rtl_regs is None:
        print("\n  [Nota] iverilog indisponível — apenas resultado Python exibido.")
    elif all_match:
        print("\n  *** TODOS OS REGISTRADORES COINCIDEM ***")
    else:
        print("\n  !!! DIVERGENCIAS DETECTADAS !!!")


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
        sim2   = CPUSimulator(num_regs=32)
        sim2.load_program(words2)
        sim2.run(max_cycles=5000)
        st2 = sim2.stats
        # Resultado da função main em R1 (ABI EduRISC-32v2)
        print(f"Resultado em R1 = {sim2.rf[1]}  (esperado: 15)")
    except Exception as e:
        print(f"[Nota] Simulação do código compilado: {e}")


# ---------------------------------------------------------------------------
# Parser de comandos
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="edurisclab",
        description="EduRISC-32v2 Educational CPU Lab",
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

    # rtl-build
    sub.add_parser("rtl-build", help="Verifica sintaxe do RTL EduRISC-32 com iverilog")

    # rtl-sim
    p_rtl = sub.add_parser("rtl-sim", help="Simula EduRISC-32 RTL com Icarus Verilog")
    p_rtl.add_argument("input", help="Arquivo .hex de 32 bits (IMEM)")
    p_rtl.add_argument("--waves", action="store_true", help="Abre GTKWave após simulação")
    p_rtl.add_argument("--timeout", type=int, default=30, help="Timeout em segundos")

    # compare
    p_cmp = sub.add_parser("compare",
        help="Compara registradores: simulador Python vs RTL Verilog")
    p_cmp.add_argument("input", help="Arquivo .hex")

    # link
    p_lnk = sub.add_parser("link", help="Liga arquivos objeto .json → Intel HEX")
    p_lnk.add_argument("files", nargs="+", help="Arquivos objeto (.json)")
    p_lnk.add_argument("-o", "--output", help="Arquivo de saída (.hex)")

    # load
    p_ld = sub.add_parser("load", help="Converte Intel HEX → mem/coe/vinit")
    p_ld.add_argument("input", help="Arquivo Intel HEX")
    p_ld.add_argument("-o", "--output", help="Arquivo de saída")
    p_ld.add_argument("--format", choices=["mem", "coe", "vinit"], default="mem",
                      help="Formato de saída (padrão: mem)")

    # fpga-build
    sub.add_parser("fpga-build", help="Gera bitstream para Arty A7 via Vivado batch")

    args = parser.parse_args()

    dispatch = {
        "assemble":   cmd_assemble,
        "compile":    cmd_compile,
        "build":      cmd_build,
        "simulate":   cmd_simulate,
        "debug":      cmd_debug,
        "run":        cmd_run,
        "demo":       cmd_demo,
        "rtl-sim":    cmd_rtl_sim,
        "rtl-build":  cmd_rtl_build,
        "compare":    cmd_compare,
        "link":       cmd_link,
        "load":       cmd_load,
        "fpga-build": cmd_fpga_build,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
