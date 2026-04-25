"""
cpu_simulator.py — Simulador de CPU EduRISC-32v2 com Pipeline

Simula a execução completa de programas montados para a ISA EduRISC-32v2,
modelando fielmente todos os 5 estágios do pipeline com hazard detection,
data forwarding e branch resolution.

Características:
  - 32 registradores de 32 bits (R0 hardwired zero, R30=SP, R31=LR)
  - Memória de 64 M palavras de 32 bits (PC_BITS=26)
  - Pipeline de 5 estágios: IF, ID, EX, MEM, WB
  - Forwarding EX/MEM→EX e MEM/WB→EX (sem stall para dependências RAW simples)
  - Stall para load-use hazard (1 ciclo de bolha)
  - Flush completo de IF/ID/EX para branch taken (branch resolution no MEM)
  - PUSH/POP: operações sobre R30 (SP) com acesso a memória de dados
  - Contadores de ciclos, instruções, stalls, flushes, leituras/escritas de mem
  - Log de eventos para rastreamento e depuração
"""

from copy import copy as _copy
from dataclasses import dataclass, field
from typing import Optional
from cpu.instruction_set import (
    Opcode, InstFmt, decode, disassemble,
    WORD_MASK, MEM_SIZE, LR_REG, SP_REG, ZERO_REG,
    NOP_WORD,
)
from cpu.registers import RegisterFile
from cpu.alu import ALU
from cpu.control_unit import ControlUnit
from cpu.pipeline import (
    IFIDReg, IDEXReg, EXMEMReg, MEMWBReg, HazardUnit, ForwardingUnit,
)

# Conjunto de opcodes de branch condicional
_COND_BRANCHES = frozenset({
    Opcode.BEQ, Opcode.BNE, Opcode.BLT, Opcode.BGE, Opcode.BLTU, Opcode.BGEU,
})

# Endereço inicial do stack pointer (topo da área de pilha, crescendo para baixo).
# Mantido separado do segmento de código (0x000000–) e dados intermediários.
_SP_INIT: int = 0x010000   # 64 K → área de pilha começa em 0x00FFFF downward


# ---------------------------------------------------------------------------
# Estado do Simulador
# ---------------------------------------------------------------------------

@dataclass
class PipelineSnapshot:
    """Estado de todos os estágios do pipeline em um dado ciclo."""
    cycle:     int
    pc:        int
    if_instr:  str
    id_instr:  str
    ex_instr:  str
    mem_instr: str
    wb_instr:  str
    stall:     bool
    flush:     bool
    regs:      dict
    flags:     dict

    def __str__(self) -> str:
        return (
            f"Ciclo {self.cycle:4d} | PC=0x{self.pc:08X} | "
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
    cycles:         int = 0
    instructions:   int = 0
    stalls:         int = 0
    flushes:        int = 0
    memory_reads:   int = 0
    memory_writes:  int = 0
    branches_taken: int = 0


class CPUSimulator:
    """
    Simulador do processador EduRISC-32v2 com pipeline de 5 estágios.

    Uso básico:
        sim = CPUSimulator()
        sim.load_program(words)   # words: lista de inteiros de 32 bits
        sim.run()
        sim.dump_state()
    """

    def __init__(self, mem_size: int = MEM_SIZE):
        self.mem:    list[int]      = [0] * mem_size
        self.rf:     RegisterFile   = RegisterFile()
        self.alu:    ALU            = ALU()
        self.cu:     ControlUnit    = ControlUnit()
        self.hazard: HazardUnit     = HazardUnit()
        self.fwd:    ForwardingUnit = ForwardingUnit()

        # Banco de 32 Registradores de Controle e Status (CSRs)
        self.csrs: list[int] = [0] * 32

        self.pc:            int  = 0
        self.halted:        bool = False
        self.fetch_stopped: bool = False   # HLT visto em EX: para de buscar

        self.ifid:  IFIDReg  = IFIDReg()
        self.idex:  IDEXReg  = IDEXReg()
        self.exmem: EXMEMReg = EXMEMReg()
        self.memwb: MEMWBReg = MEMWBReg()

        self.history:  list[PipelineSnapshot] = []
        self.stats:    SimStats               = SimStats()
        self.log:      list[str]              = []

        self._stage_dis: dict[str, str] = {
            "IF": "--", "ID": "--", "EX": "--", "MEM": "--", "WB": "--"
        }

        # SP (R30) inicializado no topo da área de pilha (cresce para baixo)
        self.rf[SP_REG] = _SP_INIT

    # -----------------------------------------------------------------------
    # Carregamento e reset
    # -----------------------------------------------------------------------

    def load_program(self, words: list[int], start_addr: int = 0):
        """Carrega programa na memória de instrução e reinicia CPU."""
        self.reset()
        for i, w in enumerate(words):
            self.mem[start_addr + i] = int(w) & WORD_MASK
        self.pc = start_addr
        self._log(f"Programa carregado: {len(words)} palavras em 0x{start_addr:08X}")

    def reset(self):
        """Reinicia CPU (mantém conteúdo de memória)."""
        self.rf     = RegisterFile()
        self.csrs   = [0] * 32
        self.pc     = 0
        self.halted = False
        self.fetch_stopped = False
        self.ifid   = IFIDReg()
        self.idex   = IDEXReg()
        self.exmem  = EXMEMReg()
        self.memwb  = MEMWBReg()
        self.history = []
        self.stats   = SimStats()
        self.log     = []
        self._stage_dis = {s: "--" for s in ("IF", "ID", "EX", "MEM", "WB")}
        # SP (R30) inicializado no topo da área de pilha
        self.rf[SP_REG] = _SP_INIT

    # -----------------------------------------------------------------------
    # Interface de execução
    # -----------------------------------------------------------------------

    def step(self) -> Optional[PipelineSnapshot]:
        """Executa um ciclo de clock. Retorna snapshot ou None se halted."""
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
            self._log(f"AVISO: limite de {max_cycles} ciclos atingido sem HLT")
        return self.stats

    # -----------------------------------------------------------------------
    # Núcleo do pipeline
    # -----------------------------------------------------------------------

    def _clock(self) -> PipelineSnapshot:
        """Executa um ciclo completo do pipeline (ordem: WB → MEM → EX → ID → IF)."""
        stall = False
        flush = False

        # ---- WB -----------------------------------------------------------
        self._stage_wb()

        # Captura registradores ANTES de avançar (forwarding usa ciclo anterior)
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
            self.pc = jump_pc & (len(self.mem) - 1)
            self.fetch_stopped = False
            self._stage_if()
        elif not stall:
            self._stage_if()
        else:
            self.idex.flush()
            self.stats.stalls += 1

        # Contadores
        self.stats.cycles += 1
        if flush:
            self.stats.flushes += 1

        return self._snapshot(stall, flush)

    # ---- WB ---------------------------------------------------------------

    def _stage_wb(self):
        wb = self.memwb
        if not wb.valid:
            self._stage_dis["WB"] = "--"
            return
        if wb.ctrl.halt:
            self.halted = True
            self._log(f"HLT drenado no WB (ciclo {self.stats.cycles})")
            self._stage_dis["WB"] = "HLT"
            return
        if not wb.ctrl.reg_write:
            self._stage_dis["WB"] = "--"
            return
        # R0 hardwired zero — nunca escreve
        if wb.rd == ZERO_REG:
            self._stage_dis["WB"] = "--"
            return
        val = wb.mem_data if wb.ctrl.mem_read else wb.alu_result
        self.rf[wb.rd] = val
        self._stage_dis["WB"] = f"WB→R{wb.rd}=0x{val:08X}"
        self.stats.instructions += 1

    # ---- MEM --------------------------------------------------------------

    def _stage_mem(self) -> tuple[bool, int]:
        """Estágio MEM: acesso a memória e resolução de saltos. Retorna (take_jump, jump_pc)."""
        exm = self.exmem

        # Propaga para MEM/WB
        self.memwb.ctrl       = exm.ctrl
        self.memwb.alu_result = exm.alu_result
        self.memwb.rd         = exm.rd
        self.memwb.mem_data   = 0
        self.memwb.valid      = exm.valid

        if not exm.valid:
            self._stage_dis["MEM"] = "--"
            return False, 0

        # Load — com suporte a byte (LB/LBU), halfword (LH/LHU) e word (LW)
        if exm.ctrl.mem_read:
            addr     = exm.mem_addr & (len(self.mem) - 1)
            raw_word = self.mem[addr]
            size     = exm.ctrl.mem_size   # 0=byte, 1=halfword, 2=word

            if size == 0:   # byte: extrai byte dentro da word de 32 bits
                byte_off = exm.mem_addr & 3          # posição 0–3 dentro da word
                data = (raw_word >> (byte_off * 8)) & 0xFF
                if exm.ctrl.mem_signed and (data & 0x80):
                    data |= 0xFFFFFF00               # sign-extend para 32 bits
            elif size == 1: # halfword: extrai 16 bits alinhados a 2 bytes
                half_off = exm.mem_addr & 2          # posição 0 ou 2
                data = (raw_word >> (half_off * 8)) & 0xFFFF
                if exm.ctrl.mem_signed and (data & 0x8000):
                    data |= 0xFFFF0000               # sign-extend para 32 bits
            else:           # word: leitura completa de 32 bits
                data = raw_word

            data &= WORD_MASK
            self.memwb.mem_data = data
            self.stats.memory_reads += 1
            sz_name = ("B", "H", "W")[size]
            self._stage_dis["MEM"] = f"LOAD{sz_name} [0x{addr:08X}]→0x{data:08X}"

        # Store — com suporte a byte (SB), halfword (SH) e word (SW)
        elif exm.ctrl.mem_write:
            addr = exm.mem_addr & (len(self.mem) - 1)
            size = exm.ctrl.mem_size   # 0=byte, 1=halfword, 2=word
            val  = exm.rs2_val & WORD_MASK

            if size == 0:   # byte: sobrescreve apenas o byte na posição correta
                byte_off = exm.mem_addr & 3
                shift    = byte_off * 8
                mask     = ~(0xFF << shift) & WORD_MASK
                self.mem[addr] = (self.mem[addr] & mask) | ((val & 0xFF) << shift)
            elif size == 1: # halfword: sobrescreve 16 bits na posição correta
                half_off = exm.mem_addr & 2
                shift    = half_off * 8
                mask     = ~(0xFFFF << shift) & WORD_MASK
                self.mem[addr] = (self.mem[addr] & mask) | ((val & 0xFFFF) << shift)
            else:           # word: escreve 32 bits completos
                self.mem[addr] = val

            self.stats.memory_writes += 1
            sz_name = ("B", "H", "W")[size]
            self._stage_dis["MEM"] = f"STORE{sz_name} [0x{addr:08X}]←0x{val:08X}"
            self.stats.instructions += 1   # stores não têm WB

        else:
            self._stage_dis["MEM"] = "--"

        # Resolução de salto
        if exm.take_jump:
            self.stats.branches_taken += 1
            self._log(f"Salto tomado → PC=0x{exm.jump_pc:08X}")
            return True, exm.jump_pc

        return False, 0

    # ---- EX ---------------------------------------------------------------

    def _stage_ex(self, prev_exmem: EXMEMReg, prev_memwb: MEMWBReg):
        """Estágio EX: execução na ALU, cálculo de endereços e avaliação de saltos."""
        ide = self.idex

        # Inicializa EX/MEM
        self.exmem.ctrl       = ide.ctrl
        self.exmem.rd         = ide.rd
        self.exmem.rs2_val    = ide.rs2_val
        self.exmem.mem_addr   = 0
        self.exmem.alu_result = 0
        self.exmem.take_jump  = False
        self.exmem.jump_pc    = 0
        self.exmem.valid      = ide.valid

        if not ide.valid or ide.ctrl.is_nop:
            self._stage_dis["EX"] = "NOP" if ide.ctrl.is_nop else "--"
            return

        # Forwarding — obtém valores atualizados de operandos
        fwd_a, fwd_b = self.fwd.calc(ide, prev_exmem, prev_memwb)
        a, b = self.fwd.resolve(fwd_a, fwd_b, ide, prev_exmem, prev_memwb)

        opcode = ide.opcode
        fmt    = ide.fmt

        # ---- HLT: drena pipeline sem executar nada -------------------------
        if ide.ctrl.halt:
            self._stage_dis["EX"] = "HLT"
            self.fetch_stopped = True
            return

        # ---- SYSCALL / ERET ------------------------------------------------
        if ide.ctrl.syscall or ide.ctrl.eret:
            self._stage_dis["EX"] = opcode.name
            if ide.ctrl.syscall:
                # SYSCALL: salva PC+1 em CSR_EPC (índice 0) e salta para handler
                # (handler não definido no sim — registra e continua)
                self.csrs[0] = (self.pc) & WORD_MASK   # salva PC atual (após HLT pipeline)
            if ide.ctrl.eret:
                # ERET: restaura PC a partir de CSR_EPC (índice 0)
                self.exmem.take_jump = True
                self.exmem.jump_pc   = self.csrs[0] & WORD_MASK
            return

        # ---- PUSH: SP--; Mem[SP] = rs1 ------------------------------------
        if ide.ctrl.push:
            sp_val = (self.rf[SP_REG] - 1) & WORD_MASK
            self.rf[SP_REG] = sp_val
            self.exmem.mem_addr  = sp_val
            self.exmem.rs2_val   = a          # rs1_val: dado a armazenar
            self.exmem.alu_result = sp_val
            self._stage_dis["EX"] = f"PUSH SP=0x{sp_val:08X}"
            return

        # ---- POP: rd = Mem[SP]; SP++ --------------------------------------
        if ide.ctrl.pop:
            sp_val = self.rf[SP_REG] & WORD_MASK
            self.exmem.mem_addr  = sp_val
            self.exmem.rd        = ide.rd
            self.rf[SP_REG] = (sp_val + 1) & WORD_MASK
            self._stage_dis["EX"] = f"POP SP=0x{sp_val:08X}"
            return

        # ---- Loads: endereço = rs1 + sext(off16) --------------------------
        if ide.ctrl.mem_read and not ide.ctrl.pop:
            mem_addr = (a + ide.offset) & WORD_MASK
            self.exmem.mem_addr  = mem_addr
            self.exmem.rs2_val   = ide.rs2_val
            self._stage_dis["EX"] = f"LOAD_ADDR 0x{mem_addr:08X}"
            return

        # ---- Stores: endereço = rs1 + sext(off16); dado = rs2 ------------
        if ide.ctrl.mem_write and not ide.ctrl.push:
            mem_addr = (a + ide.offset) & WORD_MASK
            self.exmem.mem_addr  = mem_addr
            self.exmem.rs2_val   = b          # dado a armazenar (rs2)
            self._stage_dis["EX"] = f"STORE_ADDR 0x{mem_addr:08X}"
            return

        # ---- Desvios condicionais (B-type) --------------------------------
        if ide.ctrl.branch:
            taken = self._eval_branch(opcode, a, b)
            if taken:
                # Cálculo do destino de branch (arquiteturalmente correto):
                #   O PC da instrução de branch (PC_branch) é o endereço da
                #   própria instrução. O pipeline armazena pc_plus1 = PC_branch + 1.
                #   O offset off16 é relativo a PC_branch (não a pc_plus1), portanto:
                #     target = PC_branch + off16 = (pc_plus1 - 1) + off16
                #   A subtração de 1 recupera PC_branch a partir de pc_plus1.
                #   Isso é equivalente ao que hardware RISC faz: EX usa PC salvo,
                #   não PC incrementado, para calcular o endereço de destino.
                pc_branch = ide.pc_plus1 - 1
                jump_pc = (pc_branch + ide.offset) & (len(self.mem) - 1)
                self.exmem.take_jump = True
                self.exmem.jump_pc   = jump_pc
                self._stage_dis["EX"] = f"BRANCH {opcode.name} TAKEN→0x{jump_pc:08X}"
            else:
                self._stage_dis["EX"] = f"BRANCH {opcode.name} NOT-TAKEN"
            return

        # ---- Saltos incondicionais -----------------------------------------
        if ide.ctrl.jump:
            # CALL/CALLR: salva PC+1 em LR=R31
            if ide.ctrl.call:
                self.exmem.alu_result = ide.pc_plus1 & WORD_MASK
                self.exmem.rd         = LR_REG
                self.exmem.take_jump  = True
                if opcode == Opcode.CALLR:
                    # CALLR rs1: PC = rs1
                    self.exmem.jump_pc = a & (len(self.mem) - 1)
                else:
                    # CALL addr26: PC = addr26
                    self.exmem.jump_pc = ide.addr & (len(self.mem) - 1)
                self._stage_dis["EX"] = f"CALL→0x{self.exmem.jump_pc:08X}"
                return

            # RET: PC = LR=R31
            if ide.ctrl.ret:
                jump_pc = self.rf[LR_REG] & (len(self.mem) - 1)
                self.exmem.take_jump = True
                self.exmem.jump_pc   = jump_pc
                self._stage_dis["EX"] = f"RET→0x{jump_pc:08X}"
                return

            # JMP addr26: PC = addr26
            if opcode == Opcode.JMP:
                self.exmem.take_jump = True
                self.exmem.jump_pc   = ide.addr & (len(self.mem) - 1)
                self._stage_dis["EX"] = f"JMP→0x{ide.addr:08X}"
                return

            # JMPR rs1, off16: PC = rs1 + sext(off16)
            if opcode == Opcode.JMPR:
                jump_pc = (a + ide.offset) & (len(self.mem) - 1)
                self.exmem.take_jump = True
                self.exmem.jump_pc   = jump_pc
                self._stage_dis["EX"] = f"JMPR→0x{jump_pc:08X}"
                return

        # ---- Instruções ALU (R-type e I-type) -----------------------------
        # Para MOVI: b já contém o imediato (sign-extended) preparado em ID
        # Para MOVHI: b contém imm21 (ALU faz b<<11)
        # Para MOV: b contém rs1_val (via rs2_val=rs1_val no ID)

        # ---- MFC: rd ← CSR[idx] -------------------------------------------
        if opcode == Opcode.MFC:
            csr_idx = ide.rs2_val & 0x1F   # índice CSR nos bits [4:0] do imediato
            val = self.csrs[csr_idx] & WORD_MASK
            self.exmem.alu_result = val
            self.exmem.rd = ide.rd
            self._stage_dis["EX"] = f"MFC R{ide.rd} ← CSR[{csr_idx}]=0x{val:08X}"
            return

        # ---- MTC: CSR[idx] ← rs1 ------------------------------------------
        if opcode == Opcode.MTC:
            csr_idx = ide.rs2_val & 0x1F   # índice CSR nos bits [4:0] do imediato
            self.csrs[csr_idx] = a & WORD_MASK
            self.exmem.rd = 0              # MTC não escreve registrador
            self._stage_dis["EX"] = f"MTC CSR[{csr_idx}] ← 0x{a:08X}"
            self.stats.instructions += 1
            return

        result = self.alu.execute(opcode, a, b)
        self.exmem.alu_result = result.value

        # Atualiza flags de status apenas para operações que as afetam
        if not (ide.ctrl.jump or ide.ctrl.call or ide.ctrl.halt):
            self.rf.flags.update(result.value, result.carry, result.ovf)

        self._stage_dis["EX"] = f"{opcode.name} → 0x{result.value:08X}"

    # ---- Avaliação de branch condicional ----------------------------------

    @staticmethod
    def _eval_branch(opcode: Opcode, a: int, b: int) -> bool:
        """Avalia condição de branch comparando registradores rs1=a e rs2=b."""
        def signed(v: int) -> int:
            return v if v < (1 << 31) else v - (1 << 32)

        match opcode:
            case Opcode.BEQ:  return a == b
            case Opcode.BNE:  return a != b
            case Opcode.BLT:  return signed(a) < signed(b)
            case Opcode.BGE:  return signed(a) >= signed(b)
            case Opcode.BLTU: return a < b
            case Opcode.BGEU: return a >= b
            case _:           return False

    # ---- ID ---------------------------------------------------------------

    def _stage_id_check_hazard(self) -> bool:
        """
        Estágio ID: decodifica instrução em IF/ID → ID/EX.
        Detecta load-use hazard e retorna True se stall necessário.
        """
        ifi = self.ifid

        stall = self.hazard.detect_load_use(self.idex, ifi)

        if not stall and ifi.valid:
            word   = ifi.instruction
            d      = decode(word)
            opcode = d.get("opcode")

            if opcode is None:
                # Instrução inválida — trata como NOP
                self.idex.flush()
                self.idex.valid = True
                self._stage_dis["ID"] = f".word 0x{word:08X}"
                return False

            fmt  = d.get("fmt", InstFmt.J)
            ctrl = self.cu.decode(word)

            self.idex.opcode   = opcode
            self.idex.fmt      = fmt
            self.idex.ctrl     = ctrl
            self.idex.pc_plus1 = ifi.pc_plus1
            self.idex.valid    = True
            self.idex.addr     = 0
            self.idex.offset   = 0
            self.idex.shamt    = 0
            self.idex.rs1      = 0
            self.idex.rs2      = 0
            self.idex.rd       = 0
            self.idex.rs1_val  = 0
            self.idex.rs2_val  = 0

            if fmt == InstFmt.R:
                rd   = d["rd"]
                rs1  = d["rs1"]
                rs2  = d.get("rs2", 0)
                shmt = d.get("shamt", 0)
                self.idex.rd      = rd
                self.idex.rs1     = rs1
                self.idex.rs2     = rs2
                self.idex.shamt   = shmt
                self.idex.rs1_val = self.rf[rs1]
                # Para deslocamentos imediatos SHLI/SHRI/SHRAI: b = shamt
                if opcode in (Opcode.SHLI, Opcode.SHRI, Opcode.SHRAI):
                    self.idex.rs2_val = shmt
                # Para MOV: b = rs1_val (copia rs1 → rd)
                elif opcode == Opcode.MOV:
                    self.idex.rs2_val = self.rf[rs1]
                else:
                    self.idex.rs2_val = self.rf[rs2]

            elif fmt == InstFmt.I:
                rd   = d["rd"]
                rs1  = d["rs1"]
                imm  = d["imm"]
                self.idex.rd      = rd
                self.idex.rs1     = rs1
                self.idex.offset  = imm     # usado como endereço em loads
                self.idex.rs1_val = self.rf[rs1]
                # Para MOVI: a=0, b=sext(imm16)
                if opcode == Opcode.MOVI:
                    self.idex.rs1_val = 0
                    self.idex.rs2_val = imm & WORD_MASK
                # Para MFC/MTC: imm contém índice CSR
                elif opcode in (Opcode.MFC, Opcode.MTC):
                    self.idex.rs2_val = imm & WORD_MASK
                else:
                    # ADDI, ANDI, ORI, XORI, SLTI, loads: b = sext(imm16)
                    self.idex.rs2_val = imm & WORD_MASK

            elif fmt == InstFmt.S:
                rs2  = d["rs2"]
                rs1  = d["rs1"]
                off  = d["off"]
                self.idex.rs1     = rs1
                self.idex.rs2     = rs2
                self.idex.offset  = off
                self.idex.rs1_val = self.rf[rs1]
                self.idex.rs2_val = self.rf[rs2]   # dado a armazenar

            elif fmt == InstFmt.B:
                rs1  = d["rs1"]
                rs2  = d["rs2"]
                off  = d["off"]
                self.idex.rs1     = rs1
                self.idex.rs2     = rs2
                self.idex.offset  = off
                self.idex.rs1_val = self.rf[rs1]
                self.idex.rs2_val = self.rf[rs2]

            elif fmt == InstFmt.J:
                addr = d["addr"]
                self.idex.addr = addr
                # CALL/CALLR salva LR=R31
                if ctrl.call:
                    self.idex.rd = LR_REG

            elif fmt == InstFmt.U:
                rd    = d["rd"]
                imm21 = d["imm21"]
                self.idex.rd      = rd
                self.idex.offset  = imm21
                # ALU recebe (0, imm21) e faz MOVHI: rd = imm21 << 11
                self.idex.rs1_val = 0
                self.idex.rs2_val = imm21

            self._stage_dis["ID"] = disassemble(word)

        elif not ifi.valid:
            self.idex.valid = False
            self._stage_dis["ID"] = "--"

        return stall

    # ---- IF ---------------------------------------------------------------

    def _stage_if(self):
        """Estágio IF: busca instrução da memória no endereço PC."""
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

    # -----------------------------------------------------------------------
    # Utilitários internos
    # -----------------------------------------------------------------------

    def _flush_if_id_ex(self):
        """Flush de IF/ID, ID/EX e EX/MEM (controle de hazard por branch)."""
        self.ifid.flush()
        self.idex.flush()
        self.exmem.flush()

    def _snapshot(self, stall: bool, flush: bool) -> PipelineSnapshot:
        return PipelineSnapshot(
            cycle     = self.stats.cycles,
            pc        = self.pc,
            if_instr  = self._stage_dis["IF"],
            id_instr  = self._stage_dis["ID"],
            ex_instr  = self._stage_dis["EX"],
            mem_instr = self._stage_dis["MEM"],
            wb_instr  = self._stage_dis["WB"],
            stall     = stall,
            flush     = flush,
            regs      = self.rf.to_dict(),
            flags     = self.rf.flags.to_dict(),
        )

    def _log(self, msg: str):
        self.log.append(f"[C{self.stats.cycles:05d}] {msg}")

    # -----------------------------------------------------------------------
    # Display
    # -----------------------------------------------------------------------

    def dump_state(self):
        """Imprime estado completo da CPU no terminal."""
        print("=" * 75)
        print(f"  EduRISC-32v2 — Ciclo {self.stats.cycles}  "
              f"PC=0x{self.pc:08X}  "
              f"{'HALTED' if self.halted else 'RUNNING'}")
        print("=" * 75)
        print("  Registradores:")
        print(self.rf.dump())
        print(f"\n  Flags: {self.rf.flags}")
        # Exibe apenas CSRs com valor não-zero
        csr_nz = [(i, v) for i, v in enumerate(self.csrs) if v]
        if csr_nz:
            print("\n  CSRs (não-zero):")
            for idx, val in csr_nz:
                print(f"    CSR[{idx:2d}] = 0x{val:08X}  ({val})")
        print(f"\n  Estatísticas:")
        print(f"    Ciclos:           {self.stats.cycles}")
        print(f"    Instruções:       {self.stats.instructions}")
        print(f"    Stalls:           {self.stats.stalls}")
        print(f"    Flushes:          {self.stats.flushes}")
        print(f"    Leituras de mem:  {self.stats.memory_reads}")
        print(f"    Escritas de mem:  {self.stats.memory_writes}")
        print(f"    Desvios tomados:  {self.stats.branches_taken}")
        if self.stats.cycles > 0:
            ipc = self.stats.instructions / self.stats.cycles
            print(f"    IPC:              {ipc:.3f}")
        print("=" * 75)

    def dump_memory(self, start: int = 0, length: int = 32):
        """Imprime dump hexadecimal da memória de dados."""
        print(f"  Memória 0x{start:08X}–0x{start + length - 1:08X}:")
        for i in range(start, min(start + length, len(self.mem)), 4):
            row = " ".join(
                f"{self.mem[i+j]:08X}" if i + j < len(self.mem) else "        "
                for j in range(4)
            )
            print(f"  {i:08X}: {row}")
