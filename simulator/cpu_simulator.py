"""
cpu_simulator.py — Simulador de CPU EduRISC-16 com Pipeline

Simula a execução completa de programas compilados pelo assembler,
modelando todos os 5 estágios do pipeline com hazard detection e forwarding.

Funcionalidades:
  - Execução passo a passo (step) ou contínua (run)
  - Contador de ciclos, stalls e flushes
  - Memória RAM simulada (65536 palavras de 16 bits)
  - Snapshot do estado completo do pipeline a cada ciclo
  - Log de eventos (writes, reads, jumps, traps)
  - Compatível com o debugger
"""

from copy import copy as _copy
from dataclasses import dataclass, field
from typing import Optional
from cpu.instruction_set import (
    Opcode, decode, disassemble, WORD_MASK, MEM_SIZE, LINK_REG, OPCODE_TYPE, InstType,
)
from cpu.registers import RegisterFile
from cpu.alu import ALU
from cpu.control_unit import ControlUnit
from cpu.pipeline import (
    IFIDReg, IDEXReg, EXMEMReg, MEMWBReg, HazardUnit, ForwardingUnit,
)


# ---------------------------------------------------------------------------
# Estado do Simulador
# ---------------------------------------------------------------------------

@dataclass
class PipelineSnapshot:
    """Estado de todos os estágios do pipeline em um dado ciclo."""
    cycle:    int
    pc:       int
    if_instr: str   # disassembly da instrução em IF
    id_instr: str
    ex_instr: str
    mem_instr: str
    wb_instr: str
    stall:    bool
    flush:    bool
    regs:     dict
    flags:    dict

    def __str__(self) -> str:
        return (
            f"Ciclo {self.cycle:4d} | PC={self.pc:04X} | "
            f"IF:[{self.if_instr}] "
            f"ID:[{self.id_instr}] "
            f"EX:[{self.ex_instr}] "
            f"MEM:[{self.mem_instr}] "
            f"WB:[{self.wb_instr}]"
            + (" STALL" if self.stall else "")
            + (" FLUSH" if self.flush else "")
        )


@dataclass
class SimStats:
    cycles:          int = 0
    instructions:    int = 0
    stalls:          int = 0
    flushes:         int = 0
    memory_reads:    int = 0
    memory_writes:   int = 0
    branches_taken:  int = 0


class CPUSimulator:
    """
    Simulador do processador EduRISC-16 com pipeline de 5 estágios.

    Uso básico:
        sim = CPUSimulator()
        sim.load_program(words)
        sim.run()
        sim.dump_state()
    """

    def __init__(self, mem_size: int = MEM_SIZE):
        self.mem:    list[int]    = [0] * mem_size
        self.rf:     RegisterFile = RegisterFile()
        self.alu:    ALU          = ALU()
        self.cu:     ControlUnit  = ControlUnit()
        self.hazard: HazardUnit   = HazardUnit()
        self.fwd:    ForwardingUnit = ForwardingUnit()

        # PC
        self.pc:     int  = 0
        self.halted: bool = False
        self.fetch_stopped: bool = False  # HLT visto em EX: para de buscar

        # Registradores inter-estágio
        self.ifid:  IFIDReg  = IFIDReg()
        self.idex:  IDEXReg  = IDEXReg()
        self.exmem: EXMEMReg = EXMEMReg()
        self.memwb: MEMWBReg = MEMWBReg()

        # Histórico e estatísticas
        self.history:  list[PipelineSnapshot] = []
        self.stats:    SimStats               = SimStats()
        self.log:      list[str]              = []

        # Rastreia qual instrução cada registrador inter-estágio carrega (para display)
        self._stage_dis: dict[str, str] = {"IF": "--", "ID": "--", "EX": "--", "MEM": "--", "WB": "--"}

    # -----------------------------------------------------------------------
    # Carregamento
    # -----------------------------------------------------------------------

    def load_program(self, words: list[int], start_addr: int = 0):
        """Carrega programa na memória e reinicia CPU."""
        self.reset()
        for i, w in enumerate(words):
            self.mem[start_addr + i] = w & WORD_MASK
        self.pc = start_addr
        self._log(f"Programa carregado: {len(words)} palavras em 0x{start_addr:04X}")

    def reset(self):
        """Reinicia CPU mantendo o conteúdo da memória."""
        self.rf      = RegisterFile()
        self.pc      = 0
        self.halted  = False
        self.fetch_stopped = False
        self.ifid    = IFIDReg()
        self.idex    = IDEXReg()
        self.exmem   = EXMEMReg()
        self.memwb   = MEMWBReg()
        self.history = []
        self.stats   = SimStats()
        self.log     = []
        self._stage_dis = {s: "--" for s in ("IF", "ID", "EX", "MEM", "WB")}

    # -----------------------------------------------------------------------
    # Interface de execução
    # -----------------------------------------------------------------------

    def step(self) -> Optional[PipelineSnapshot]:
        """Executa um ciclo de clock. Retorna snapshot do estado ou None se halted."""
        if self.halted:
            return None
        snap = self._clock()
        self.history.append(snap)
        return snap

    def run(self, max_cycles: int = 100_000) -> SimStats:
        """Executa até HLT ou max_cycles ciclos."""
        while not self.halted and self.stats.cycles < max_cycles:
            self.step()
        if not self.halted:
            self._log(f"AVISO: limite de {max_cycles} ciclos atingido")
        return self.stats

    # -----------------------------------------------------------------------
    # Núcleo do pipeline
    # -----------------------------------------------------------------------

    def _clock(self) -> PipelineSnapshot:
        """Executa um ciclo completo do pipeline (WB → MEM → EX → ID → IF)."""
        stall = False
        flush = False

        # ---- WB -----------------------------------------------------------
        self._stage_wb()

        # Captura reg MEM/WB e EX/MEM ANTES de sobrescrever (forwarding usa ciclo anterior)
        prev_memwb = _copy(self.memwb)
        prev_exmem = _copy(self.exmem)

        # ---- MEM ----------------------------------------------------------
        take_jump, jump_pc = self._stage_mem()

        # ---- EX -----------------------------------------------------------
        self._stage_ex(prev_exmem, prev_memwb)

        # ---- ID -----------------------------------------------------------
        stall = self._stage_id_check_hazard()

        # ---- IF -----------------------------------------------------------
        if take_jump:
            flush = True
            self._flush_if_id_ex()
            self.pc = jump_pc
            self.fetch_stopped = False  # branch cancela qualquer HLT ainda no pipeline
            self._stage_if()
        elif not stall:
            self._stage_if()
        else:
            # Insere bolha no ID/EX e mantém IF/ID e PC
            self.idex.flush()
            self.stats.stalls += 1

        # Atualiza stats
        self.stats.cycles += 1
        if flush:
            self.stats.flushes += 1

        snap = self._snapshot(stall, flush)
        return snap

    # ---- Estágio WB -------------------------------------------------------

    def _stage_wb(self):
        wb = self.memwb
        if not wb.valid:
            self._stage_dis["WB"] = "--"
            return
        # HLT chega ao WB → pipeline drenado, pode parar
        if wb.ctrl.halt:
            self.halted = True
            self._log(f"  HLT drenado no WB, ciclo={self.stats.cycles}")
            self._stage_dis["WB"] = "HLT"
            return
        if not wb.ctrl.reg_write:
            self._stage_dis["WB"] = "--"
            return
        val = wb.mem_data if wb.ctrl.mem_read else wb.alu_result
        self.rf[wb.rd] = val
        self._stage_dis["WB"] = f"WB→R{wb.rd}={val:04X}"
        self.stats.instructions += 1

    # ---- Estágio MEM ------------------------------------------------------

    def _stage_mem(self) -> tuple[bool, int]:
        """Retorna (take_jump, jump_pc)."""
        exm = self.exmem

        # Avança o registrador MEM/WB com base no que veio de EX/MEM
        self.memwb.ctrl      = exm.ctrl
        self.memwb.alu_result = exm.alu_result
        self.memwb.rd        = exm.rd
        self.memwb.mem_data  = 0
        self.memwb.valid     = exm.valid

        if not exm.valid:
            self._stage_dis["MEM"] = "--"
            return False, 0

        # Acesso de memória
        if exm.ctrl.mem_read:
            addr = exm.mem_addr & (len(self.mem) - 1)
            self.memwb.mem_data = self.mem[addr]
            self.stats.memory_reads += 1
            self._stage_dis["MEM"] = f"LOAD 0x{addr:04X}→{self.mem[addr]:04X}"
        elif exm.ctrl.mem_write:
            addr = exm.mem_addr & (len(self.mem) - 1)
            self.mem[addr] = exm.rs2_val & WORD_MASK
            self.stats.memory_writes += 1
            self._stage_dis["MEM"] = f"STORE 0x{addr:04X}←{exm.rs2_val:04X}"
            self.stats.instructions += 1  # STORE não tem WB
        else:
            self._stage_dis["MEM"] = "--"

        # Desvio
        if exm.take_jump:
            self.stats.branches_taken += 1
            self._log(f"  Desvio tomado → PC=0x{exm.jump_pc:04X}")
            return True, exm.jump_pc

        return False, 0

    # ---- Estágio EX -------------------------------------------------------

    def _stage_ex(self, prev_exmem: 'EXMEMReg', prev_memwb: 'MEMWBReg'):
        ide = self.idex

        # Inicializa EX/MEM
        self.exmem.ctrl      = ide.ctrl
        self.exmem.rd        = ide.rd
        self.exmem.rs2_val   = ide.rs2_val
        self.exmem.mem_addr  = 0
        self.exmem.alu_result = 0
        self.exmem.take_jump = False
        self.exmem.jump_pc   = 0
        self.exmem.valid     = ide.valid

        if not ide.valid:
            self._stage_dis["EX"] = "--"
            return

        if ide.ctrl.is_nop:
            self._stage_dis["EX"] = "NOP"
            return

        # Forwarding usa registradores do ciclo anterior
        fwd_a, fwd_b = self.fwd.calc(ide, prev_exmem, prev_memwb)
        a, b = self.fwd.resolve(fwd_a, fwd_b, ide, prev_exmem, prev_memwb)

        opcode = ide.opcode

        # Calcula endereço de memória (LOAD/STORE)
        if ide.ctrl.mem_read or ide.ctrl.mem_write:
            mem_addr = (a + ide.offset) & WORD_MASK
            self.exmem.mem_addr = mem_addr
            self.exmem.rs2_val  = ide.rs2_val  # dado para STORE = rd
            self._stage_dis["EX"] = f"MEM_ADDR 0x{mem_addr:04X}"
            return

        # Executa na ALU
        result = self.alu.execute(opcode, a, b)
        # Só atualiza flags para instruções aritméticas/lógicas (R-type)
        if not ide.ctrl.jump and not ide.ctrl.call and not ide.ctrl.halt:
            self.rf.flags.update(result.value, result.carry, result.ovf)
        self.exmem.alu_result = result.value
        self._stage_dis["EX"] = f"ALU {opcode.name} → 0x{result.value:04X}"

        # CALL: salvar PC+1 em R15
        if ide.ctrl.call:
            self.exmem.alu_result = ide.pc_plus1
            self.exmem.rd         = LINK_REG

        # Desvios
        if ide.ctrl.jump:
            take = True
            if opcode == Opcode.JZ:
                take = self.rf.flags.zero
            elif opcode == Opcode.JNZ:
                take = not self.rf.flags.zero
            elif opcode == Opcode.RET:
                ide.addr = self.rf[LINK_REG]
                take = True

            if take:
                self.exmem.take_jump = True
                self.exmem.jump_pc   = ide.addr

        # HLT: para busca mas não interrompe o pipeline — drenagem acontece no WB
        if ide.ctrl.halt:
            self._stage_dis["EX"] = "HLT"
            # Sinaliza ao estágio IF para parar de buscar novas instruções
            self.fetch_stopped = True
            return

    # ---- Estágio ID -------------------------------------------------------

    def _stage_id_check_hazard(self) -> bool:
        """Decodifica instrução em IF/ID → ID/EX. Retorna True se stall necessário."""
        ifi = self.ifid

        stall = self.hazard.detect_load_use(self.idex, ifi)

        if not stall and ifi.valid:
            d      = decode(ifi.instruction)
            opcode = d["opcode"]
            ctrl   = self.cu.decode(ifi.instruction)

            self.idex.opcode  = opcode
            self.idex.ctrl    = ctrl
            self.idex.pc_plus1 = ifi.pc_plus1
            self.idex.valid   = True
            self.idex.addr    = 0
            self.idex.offset  = 0

            itype = d["type"]
            if itype.__class__.__name__ == "InstType":
                pass  # já correto

            if d["type"].value == 2:   # J-type
                self.idex.addr   = d["addr"]
                self.idex.rs1    = 0
                self.idex.rs2    = 0
                self.idex.rd     = 0
                self.idex.rs1_val = 0
                self.idex.rs2_val = 0
            elif d["type"].value == 3:  # M-type
                self.idex.rd      = d["rd"]
                self.idex.base_reg = d["base"]
                self.idex.offset  = d["offset"]
                self.idex.rs1     = d["base"]
                self.idex.rs2     = d["rd"]   # STORE: dado = rd
                self.idex.rs1_val = self.rf[d["base"]]
                self.idex.rs2_val = self.rf[d["rd"]]
            else:  # R-type
                self.idex.rd      = d.get("rd", 0)
                self.idex.rs1     = d.get("rs1", 0)
                self.idex.rs2     = d.get("rs2", 0)
                self.idex.rs1_val = self.rf[d.get("rs1", 0)]
                self.idex.rs2_val = self.rf[d.get("rs2", 0)]

            self._stage_dis["ID"] = disassemble(ifi.instruction)
        elif not ifi.valid:
            self.idex.valid = False
            self._stage_dis["ID"] = "--"

        return stall

    # ---- Estágio IF -------------------------------------------------------

    def _stage_if(self):
        if self.fetch_stopped or self.pc >= len(self.mem):
            self._stage_dis["IF"] = "--"
            self.ifid.valid = False
            return
        word = self.mem[self.pc]
        self.ifid.instruction = word
        self.ifid.pc_plus1    = self.pc + 1
        self.ifid.valid       = True
        self._stage_dis["IF"] = disassemble(word)
        self.pc += 1

    # ---- Utilitários -------------------------------------------------------

    def _flush_if_id_ex(self):
        """Flush dos estágios IF/ID e ID/EX (controle de hazard)."""
        self.ifid.flush()
        self.idex.flush()
        self.exmem.flush()

    def _snapshot(self, stall: bool, flush: bool) -> PipelineSnapshot:
        return PipelineSnapshot(
            cycle    = self.stats.cycles,
            pc       = self.pc,
            if_instr = self._stage_dis["IF"],
            id_instr = self._stage_dis["ID"],
            ex_instr = self._stage_dis["EX"],
            mem_instr= self._stage_dis["MEM"],
            wb_instr = self._stage_dis["WB"],
            stall    = stall,
            flush    = flush,
            regs     = self.rf.to_dict(),
            flags    = self.rf.flags.to_dict(),
        )

    def _log(self, msg: str):
        self.log.append(f"[C{self.stats.cycles:04d}] {msg}")

    # -----------------------------------------------------------------------
    # Display
    # -----------------------------------------------------------------------

    def dump_state(self):
        """Imprime estado completo da CPU no terminal."""
        print("=" * 65)
        print(f"  EduRISC-16 — Ciclo {self.stats.cycles}  PC=0x{self.pc:04X}  "
              f"{'HALTED' if self.halted else 'RUNNING'}")
        print("=" * 65)
        print("  Registradores:")
        print(self.rf.dump())
        print(f"\n  Estatísticas:")
        print(f"    Ciclos:           {self.stats.cycles}")
        print(f"    Instruções:       {self.stats.instructions}")
        print(f"    Stalls:           {self.stats.stalls}")
        print(f"    Flushes:          {self.stats.flushes}")
        print(f"    Leituras de mem:  {self.stats.memory_reads}")
        print(f"    Escritas de mem:  {self.stats.memory_writes}")
        print(f"    Desvios tomados:  {self.stats.branches_taken}")
        print("=" * 65)

    def dump_memory(self, start: int = 0, length: int = 32):
        """Imprime dump hexadecimal da memória."""
        print(f"  Memória 0x{start:04X}–0x{start + length - 1:04X}:")
        for i in range(start, min(start + length, len(self.mem)), 8):
            row = " ".join(f"{self.mem[i+j]:04X}" if i+j < len(self.mem) else "    "
                           for j in range(8))
            print(f"  {i:04X}: {row}")
