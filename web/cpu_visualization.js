/**
 * cpu_visualization.js
 * Lógica de simulação e visualização do EduRISC-16
 *
 * Arquitetura:
 *   - EduRISC16Sim: simulador completo em JavaScript (espelho do cpu_simulator.py)
 *   - UI: atualiza DOM a cada ciclo, animando o pipeline
 */

"use strict";

// ============================================================
// ISA EduRISC-16 — espelho do instruction_set.py em JS
// ============================================================

const OP = {
  ADD:   0x0, SUB:  0x1, MUL: 0x2, DIV: 0x3,
  AND:   0x4, OR:   0x5, XOR: 0x6, NOT: 0x7,
  LOAD:  0x8, STORE:0x9, JMP: 0xA, JZ:  0xB,
  JNZ:   0xC, CALL: 0xD, RET: 0xE, HLT: 0xF,
};

// Nome do opcode por número
const OP_NAME = Object.fromEntries(Object.entries(OP).map(([k,v])=>[v,k]));

const INST_TYPE = {
  R: "R",  // reg-reg     [15:12=op][11:8=rd][7:4=rs1][3:0=rs2]
  M: "M",  // memória     [15:12=op][11:8=rd][7:4=base][3:0=offset4]
  J: "J",  // jump        [15:12=op][11:0=addr12]
};

function instType(op) {
  if ([OP.LOAD, OP.STORE].includes(op))          return INST_TYPE.M;
  if ([OP.JMP, OP.JZ, OP.JNZ, OP.CALL].includes(op)) return INST_TYPE.J;
  return INST_TYPE.R;
}

function decode(word) {
  word &= 0xFFFF;
  const op = (word >> 12) & 0xF;
  const t  = instType(op);
  if (t === INST_TYPE.J) {
    return { op, type: t, addr: word & 0x0FFF };
  }
  if (t === INST_TYPE.M) {
    return { op, type: t, rd: (word >> 8) & 0xF, base: (word >> 4) & 0xF, offset: word & 0xF };
  }
  // R-type
  return { op, type: t, rd: (word >> 8) & 0xF, rs1: (word >> 4) & 0xF, rs2: word & 0xF };
}

function disassemble(word) {
  if (word === 0) return "NOP";
  const d = decode(word);
  const mn = OP_NAME[d.op] ?? `?${d.op}`;
  switch (d.type) {
    case INST_TYPE.J: return `${mn} 0x${d.addr.toString(16).padStart(3,"0").toUpperCase()}`;
    case INST_TYPE.M:
      if (d.op === OP.LOAD)  return `${mn} R${d.rd}, [R${d.base}+${d.offset}]`;
      return `${mn} [R${d.base}+${d.offset}], R${d.rd}`;
    default:
      if (d.op === OP.NOT) return `NOT R${d.rd}, R${d.rs1}`;
      if (d.op === OP.RET) return `RET`;
      if (d.op === OP.HLT) return `HLT`;
      return `${mn} R${d.rd}, R${d.rs1}, R${d.rs2}`;
  }
}

// ============================================================
// Assembler JS mínimo (subset para o exemplo embutido)
// ============================================================

function jsAssemble(src) {
  /** Retorna Uint16Array com o programa, ou lança erro. */
  const mem = new Uint16Array(0x10000).fill(0);
  const symbols = {};
  const fixups  = [];
  let   orgAddr = 0;
  let   pc      = 0;
  const lines   = src.split("\n");

  // Dois passos: 1) coletar labels; 2) gerar código
  for (let pass = 1; pass <= 2; pass++) {
    orgAddr = 0; pc = 0;
    for (let li = 0; li < lines.length; li++) {
      let line = lines[li].replace(/;.*/, "").trim();
      if (!line) continue;

      // Label
      const lblM = line.match(/^([A-Za-z_]\w*)\s*:/);
      if (lblM) {
        if (pass === 1) symbols[lblM[1].toUpperCase()] = orgAddr + pc;
        line = line.slice(lblM[0].length).trim();
        if (!line) continue;
      }

      // Diretiva .ORG
      const orgM = line.match(/^\.ORG\s+(0[xX][0-9A-Fa-f]+|\d+)/i);
      if (orgM) { orgAddr = Number(orgM[1]); pc = 0; continue; }

      // Diretiva .WORD
      const wordM = line.match(/^\.WORD\s+(0[xX][0-9A-Fa-f]+|-?\d+)/i);
      if (wordM) {
        if (pass === 2) mem[orgAddr + pc] = Number(wordM[1]) & 0xFFFF;
        pc++; continue;
      }

      if (pass === 1) { pc++; continue; }  // pass 1: só conta endereço

      // Instruções
      const toks = line.split(/[\s,]+/).filter(Boolean);
      const mn   = toks[0].toUpperCase();

      const parseReg = (s) => { const m = s?.match(/^[Rr](\d+)$/); if (!m) return null; return +m[1]; };
      const parseImm = (s) => {
        if (!s) return null;
        // label?
        const key = s.toUpperCase();
        if (key in symbols) return symbols[key];
        return Number(s) | 0;
      };
      const memArg = (s) => {
        // [RN+offset]
        const m = s?.match(/^\[R(\d+)\+(\d+)\]$/i);
        return m ? { base: +m[1], offset: +m[2] } : null;
      };

      let word = 0;
      const opcode = OP[mn];
      if (opcode === undefined) throw new Error(`L${li+1}: mnemônico desconhecido '${mn}'`);
      const t = instType(opcode);

      if (t === INST_TYPE.J) {
        let addr = parseImm(toks[1]);
        if (addr === null) throw new Error(`L${li+1}: endereço inválido`);
        word = (opcode << 12) | (addr & 0x0FFF);
      } else if (t === INST_TYPE.M) {
        const rd   = parseReg(toks[1]);
        const mobj = memArg(toks[2]);
        if (rd === null || !mobj) throw new Error(`L${li+1}: sintaxe inválida LOAD/STORE`);
        word = (opcode << 12) | (rd << 8) | (mobj.base << 4) | (mobj.offset & 0xF);
      } else {
        // R-type
        if (mn === "RET") { word = (opcode << 12); }
        else if (mn === "HLT") { word = (opcode << 12); }
        else if (mn === "NOT") {
          const rd = parseReg(toks[1]);
          const rs = parseReg(toks[2]);
          word = (opcode << 12) | (rd << 8) | (rs << 4);
        } else {
          const rd  = parseReg(toks[1]);
          const rs1 = parseReg(toks[2]);
          const rs2 = parseReg(toks[3]);
          if (rd === null || rs1 === null || rs2 === null)
            throw new Error(`L${li+1}: registrador inválido — esperado Rd, Rs1, Rs2`);
          word = (opcode << 12) | (rd << 8) | (rs1 << 4) | (rs2 & 0xF);
        }
      }
      mem[orgAddr + pc] = word & 0xFFFF;
      pc++;
    }
  }
  return mem;
}

// ============================================================
// Simulador EduRISC-16 em JavaScript
// ============================================================

class EduRISC16Sim {
  constructor() {
    this.mem   = new Uint16Array(0x10000);
    this.regs  = new Int16Array(16);
    this.pc    = 0;
    this.zero  = false;
    this.carry = false;
    this.neg   = false;
    this.ovf   = false;
    this.halted = false;
    this.cycles = 0;
    this.instrsRetired = 0;
    this.stalls  = 0;
    this.flushes = 0;

    // Pipeline registers (word de instrução + PC)
    this.pip = { IF: 0, ID: 0, EX: 0, MEM: 0, WB: 0 };
    this.pipPC = { IF: 0, ID: 0, EX: 0, MEM: 0, WB: 0 };

    // Registradores de pipeline para exibição
    this.ifid  = { valid: false, pc: 0, instr: 0 };
    this.idex  = { valid: false, pc: 0, instr: 0, rs1: 0, rs2: 0, rd: 0, rs1v: 0, rs2v: 0 };
    this.exmem = { valid: false, pc: 0, instr: 0, alu: 0, rs2v: 0, rd: 0 };
    this.memwb = { valid: false, pc: 0, instr: 0, result: 0, rd: 0 };

    this.eventLog = [];
  }

  loadProgram(mem) {
    this.mem = new Uint16Array(mem);
    this.reset(false);
  }

  reset(clearMem = false) {
    if (clearMem) this.mem.fill(0);
    this.regs.fill(0);
    this.pc      = 0;
    this.zero    = false; this.carry = false;
    this.neg     = false; this.ovf   = false;
    this.halted  = false;
    this.cycles  = 0;
    this.instrsRetired = 0;
    this.stalls  = 0; this.flushes = 0;
    this.pip     = { IF: 0, ID: 0, EX: 0, MEM: 0, WB: 0 };
    this.pipPC   = { IF: 0, ID: 0, EX: 0, MEM: 0, WB: 0 };
    this.ifid    = { valid: false, pc: 0, instr: 0 };
    this.idex    = { valid: false, pc: 0, instr: 0, rs1: 0, rs2: 0, rd: 0, rs1v: 0, rs2v: 0 };
    this.exmem   = { valid: false, pc: 0, instr: 0, alu: 0, rs2v: 0, rd: 0 };
    this.memwb   = { valid: false, pc: 0, instr: 0, result: 0, rd: 0 };
    this.eventLog = [];
  }

  get ipc() {
    return this.cycles > 0 ? (this.instrsRetired / this.cycles).toFixed(2) : "0.00";
  }

  step() {
    if (this.halted) return;
    this.cycles++;

    // Clone dos registradores de pipeline (anterior)
    const prev_ifid  = {...this.ifid};
    const prev_idex  = {...this.idex};
    const prev_exmem = {...this.exmem};
    const prev_memwb = {...this.memwb};

    // ---- WB ----
    if (prev_memwb.valid) {
      const d = decode(prev_memwb.instr);
      if (d.op !== OP.STORE && d.op !== OP.JMP && d.op !== OP.JZ &&
          d.op !== OP.JNZ     && d.op !== OP.HLT && d.op !== OP.RET) {
        if (d.rd !== undefined) {
          this.regs[d.rd] = prev_memwb.result & 0xFFFF;
          this._log(`WB: R${d.rd} ← 0x${(prev_memwb.result & 0xFFFF).toString(16).toUpperCase().padStart(4,"0")}`);
        }
      }
      if (d.op === OP.HLT) { this.halted = true; }
      this.instrsRetired++;
    }

    // ---- MEM ----
    this.memwb = { valid: false, pc: 0, instr: 0, result: 0, rd: 0 };
    if (prev_exmem.valid) {
      const d = decode(prev_exmem.instr);
      let result = prev_exmem.alu;
      if (d.op === OP.LOAD) {
        result = this.mem[prev_exmem.alu & 0xFFFF] ?? 0;
        this._log(`MEM: LOAD mem[0x${(prev_exmem.alu & 0xFFFF).toString(16).toUpperCase().padStart(4,"0")}] = 0x${result.toString(16).toUpperCase().padStart(4,"0")}`);
      } else if (d.op === OP.STORE) {
        this.mem[prev_exmem.alu & 0xFFFF] = prev_exmem.rs2v & 0xFFFF;
        this._log(`MEM: STORE mem[0x${(prev_exmem.alu & 0xFFFF).toString(16).toUpperCase().padStart(4,"0")}] ← 0x${(prev_exmem.rs2v & 0xFFFF).toString(16).toUpperCase().padStart(4,"0")}`);
      }
      this.memwb = { valid: true, pc: prev_exmem.pc, instr: prev_exmem.instr, result, rd: prev_exmem.rd };
    }

    // ---- EX ----
    this.exmem = { valid: false, pc: 0, instr: 0, alu: 0, rs2v: 0, rd: 0 };
    if (prev_idex.valid) {
      const d   = decode(prev_idex.instr);
      let   alu = 0;

      // Forwarding simples: MEM/WB → EX
      let rs1v = prev_idex.rs1v;
      let rs2v = prev_idex.rs2v;
      if (prev_exmem.valid && prev_exmem.rd !== 0) {
        if (d.rs1 === prev_exmem.rd) rs1v = prev_exmem.alu;
        if (d.rs2 === prev_exmem.rd) rs2v = prev_exmem.alu;
      }
      if (prev_memwb.valid && prev_memwb.rd !== 0) {
        if (d.rs1 === prev_memwb.rd) rs1v = prev_memwb.result;
        if (d.rs2 === prev_memwb.rd) rs2v = prev_memwb.result;
      }

      const s16 = v => (v & 0x8000) ? (v | 0xFFFF0000) : (v & 0xFFFF);

      switch(d.op) {
        case OP.ADD:  alu = (rs1v + rs2v) & 0xFFFF; break;
        case OP.SUB:  alu = (rs1v - rs2v) & 0xFFFF; break;
        case OP.MUL:  alu = (rs1v * rs2v) & 0xFFFF; break;
        case OP.DIV:  alu = rs2v ? ((rs1v / rs2v) | 0) & 0xFFFF : 0xFFFF; break;
        case OP.AND:  alu = (rs1v & rs2v) & 0xFFFF; break;
        case OP.OR:   alu = (rs1v | rs2v) & 0xFFFF; break;
        case OP.XOR:  alu = (rs1v ^ rs2v) & 0xFFFF; break;
        case OP.NOT:  alu = (~rs1v) & 0xFFFF; break;
        case OP.LOAD: alu = (this.regs[d.base] + d.offset) & 0xFFFF; break;
        case OP.STORE:alu = (this.regs[d.base] + d.offset) & 0xFFFF; rs2v = this.regs[d.rd]; break;
        case OP.JMP:  this.pc = d.addr; this.flushes++; this._flush(); break;
        case OP.JZ:
          this.zero = (this.regs[prev_idex.rs1 ?? 0] === 0);
          if (this.zero)  { this.pc = d.addr; this.flushes++; this._flush(); }
          break;
        case OP.JNZ:
          this.zero = (this.regs[prev_idex.rs1 ?? 0] === 0);
          if (!this.zero) { this.pc = d.addr; this.flushes++; this._flush(); }
          break;
        case OP.CALL:
          this.regs[15] = (prev_idex.pc + 1) & 0xFFFF;
          this.pc = d.addr; this.flushes++; this._flush();
          break;
        case OP.RET:
          this.pc = this.regs[15];
          this.flushes++; this._flush();
          break;
        default: break;
      }

      // Flags (após ops aritméticas)
      if ([OP.ADD,OP.SUB,OP.MUL,OP.DIV,OP.AND,OP.OR,OP.XOR,OP.NOT].includes(d.op)) {
        this.zero  = (alu === 0);
        this.neg   = !!(alu & 0x8000);
        this.carry = (rs1v + rs2v) > 0xFFFF;
        this.ovf   = false; // simplificado
      }

      this.exmem = { valid: true, pc: prev_idex.pc, instr: prev_idex.instr, alu, rs2v: rs2v & 0xFFFF, rd: d.rd ?? 0 };
      this._log(`EX: ${disassemble(prev_idex.instr)} → ALU=0x${alu.toString(16).toUpperCase().padStart(4,"0")}`);
    }

    // ---- ID ----
    this.idex = { valid: false, pc: 0, instr: 0, rs1: 0, rs2: 0, rd: 0, rs1v: 0, rs2v: 0 };
    if (prev_ifid.valid) {
      const d = decode(prev_ifid.instr);
      const rs1v = (d.rs1 !== undefined) ? (this.regs[d.rs1] & 0xFFFF) : 0;
      const rs2v = (d.rs2 !== undefined) ? (this.regs[d.rs2] & 0xFFFF) : 0;
      this.idex = {
        valid: true, pc: prev_ifid.pc, instr: prev_ifid.instr,
        rs1: d.rs1 ?? 0, rs2: d.rs2 ?? 0, rd: d.rd ?? 0,
        rs1v, rs2v,
      };
      this._log(`ID: ${disassemble(prev_ifid.instr)}`);
    }

    // ---- IF ----
    this.ifid = { valid: false, pc: 0, instr: 0 };
    if (!this.halted) {
      const instr = this.mem[this.pc] ?? 0;
      this.ifid = { valid: true, pc: this.pc, instr };
      this._log(`IF: fetch PC=0x${this.pc.toString(16).toUpperCase().padStart(4,"0")} → ${disassemble(instr)}`);
      this.pc = (this.pc + 1) & 0xFFFF;
    }

    // Atualiza exibição do pipeline
    this.pip.IF  = this.ifid.valid  ? this.ifid.instr  : 0;
    this.pip.ID  = this.idex.valid  ? this.idex.instr  : 0;
    this.pip.EX  = this.exmem.valid ? this.exmem.instr : 0;
    this.pip.MEM = this.memwb.valid ? this.memwb.instr : 0;
    this.pip.WB  = prev_memwb.valid ? prev_memwb.instr : 0;
  }

  _flush() {
    this.ifid = { valid: false, pc: 0, instr: 0 };
    this.idex = { valid: false, pc: 0, instr: 0, rs1: 0, rs2: 0, rd: 0, rs1v: 0, rs2v: 0 };
  }

  _log(msg) {
    this.eventLog.push(`[C${this.cycles}] ${msg}`);
    if (this.eventLog.length > 200) this.eventLog.shift();
  }

  snapshot() {
    return {
      pc:      this.pc,
      regs:    Array.from(this.regs),
      flags:   { zero: this.zero, carry: this.carry, neg: this.neg, ovf: this.ovf },
      pip:     {...this.pip},
      ifid:    {...this.ifid},
      idex:    {...this.idex},
      exmem:   {...this.exmem},
      memwb:   {...this.memwb},
      cycles:  this.cycles,
      instrs:  this.instrsRetired,
      stalls:  this.stalls,
      flushes: this.flushes,
      halted:  this.halted,
    };
  }
}

// ============================================================
// Controlador de UI
// ============================================================

const sim = new EduRISC16Sim();
let   memViewBase = 0;

// ---- Inicializa banco de registradores ----
function buildRegGrid() {
  const grid = document.getElementById("regfile-grid");
  grid.innerHTML = "";
  for (let i = 0; i < 16; i++) {
    const cell = document.createElement("div");
    cell.className = "reg-cell";
    cell.id        = `reg-${i}`;
    const aliases  = { 15: "LR" };
    cell.innerHTML = `<span class="reg-name">R${i}${aliases[i] ? "<br/><small>"+aliases[i]+"</small>" : ""}</span><span class="reg-val" id="regval-${i}">0x0000</span>`;
    grid.appendChild(cell);
  }
}

// ---- Atualiza toda a UI com o estado atual do simulador ----
function updateUI(snap) {
  // Ciclo / PC / status
  document.getElementById("cycle-num").textContent  = snap.cycles;
  document.getElementById("pc-display").textContent  = "0x" + snap.pc.toString(16).toUpperCase().padStart(4,"0");
  const statusEl = document.getElementById("status-display");
  if (snap.halted) {
    statusEl.textContent = "HALTED";
    statusEl.className   = "status-halted";
  } else {
    statusEl.textContent = "RUN";
    statusEl.className   = "status-run";
  }

  // Pipeline stages
  const STAGES = ["IF","ID","EX","MEM","WB"];
  STAGES.forEach(s => {
    const el = document.getElementById(`cell-${s}`);
    const w  = snap.pip[s];
    el.textContent   = w ? disassemble(w) : "—";
    el.className     = "stage-instr" + (w ? " stage-active" : "");
  });

  // Registradores de pipeline (detail boxes)
  const ifidEl = document.getElementById("preg-IFID-body");
  ifidEl.textContent = snap.ifid.valid
    ? `PC=0x${snap.ifid.pc.toString(16).toUpperCase().padStart(4,"0")}\n${disassemble(snap.ifid.instr)}`
    : "NOP / vazio";

  const idexEl = document.getElementById("preg-IDEX-body");
  idexEl.textContent = snap.idex.valid
    ? `PC=0x${snap.idex.pc.toString(16).toUpperCase().padStart(4,"0")}\n${disassemble(snap.idex.instr)}\nRS1=0x${snap.idex.rs1v.toString(16).toUpperCase().padStart(4,"0")} RS2=0x${snap.idex.rs2v.toString(16).toUpperCase().padStart(4,"0")}`
    : "NOP / vazio";

  const exmemEl = document.getElementById("preg-EXMEM-body");
  exmemEl.textContent = snap.exmem.valid
    ? `PC=0x${snap.exmem.pc.toString(16).toUpperCase().padStart(4,"0")}\n${disassemble(snap.exmem.instr)}\nALU=0x${snap.exmem.alu.toString(16).toUpperCase().padStart(4,"0")} RD=R${snap.exmem.rd}`
    : "NOP / vazio";

  const memwbEl = document.getElementById("preg-MEMWB-body");
  memwbEl.textContent = snap.memwb.valid
    ? `PC=0x${snap.memwb.pc.toString(16).toUpperCase().padStart(4,"0")}\n${disassemble(snap.memwb.instr)}\nRES=0x${snap.memwb.result.toString(16).toUpperCase().padStart(4,"0")} RD=R${snap.memwb.rd}`
    : "NOP / vazio";

  // Banco de registradores
  snap.regs.forEach((v, i) => {
    const el = document.getElementById(`regval-${i}`);
    if (!el) return;
    const hex = (v & 0xFFFF).toString(16).toUpperCase().padStart(4,"0");
    const changed = el.textContent !== `0x${hex}`;
    el.textContent = `0x${hex}`;
    if (changed) {
      el.parentElement.classList.add("reg-changed");
      setTimeout(() => el.parentElement.classList.remove("reg-changed"), 600);
    }
  });

  // Flags
  document.getElementById("flag-Z").textContent = `Z=${+snap.flags.zero}`;
  document.getElementById("flag-C").textContent = `C=${+snap.flags.carry}`;
  document.getElementById("flag-N").textContent = `N=${+snap.flags.neg}`;
  document.getElementById("flag-V").textContent = `V=${+snap.flags.ovf}`;
  document.getElementById("flag-Z").className = "flag" + (snap.flags.zero  ? " flag-set" : "");
  document.getElementById("flag-C").className = "flag" + (snap.flags.carry ? " flag-set" : "");
  document.getElementById("flag-N").className = "flag" + (snap.flags.neg   ? " flag-set" : "");
  document.getElementById("flag-V").className = "flag" + (snap.flags.ovf   ? " flag-set" : "");

  // Estatísticas
  document.getElementById("stat-cycles").textContent  = snap.cycles;
  document.getElementById("stat-instrs").textContent  = snap.instrs;
  document.getElementById("stat-stalls").textContent  = snap.stalls;
  document.getElementById("stat-flushes").textContent = snap.flushes;
  document.getElementById("stat-ipc").textContent     = sim.ipc;

  // Log de eventos
  updateEventLog();

  // Memória
  updateMemView(memViewBase);
}

function updateEventLog() {
  const el = document.getElementById("event-log");
  el.innerHTML = sim.eventLog.slice().reverse().map(l =>
    `<div class="log-entry">${escHtml(l)}</div>`
  ).join("");
}

function updateMemView(base) {
  base = Math.max(0, Math.min(0xFFF8, base & 0xFFF8));
  memViewBase = base;
  const tbody = document.getElementById("mem-tbody");
  tbody.innerHTML = "";
  for (let row = 0; row < 8; row++) {
    const addr = base + row * 8;
    const tr   = document.createElement("tr");
    let html   = `<td class="mem-addr">0x${addr.toString(16).toUpperCase().padStart(4,"0")}</td>`;
    for (let col = 0; col < 8; col++) {
      const a   = addr + col;
      const val = sim.mem[a] ?? 0;
      const highlight = (a === sim.pc) ? " mem-pc" : "";
      html += `<td class="mem-word${highlight}">0x${val.toString(16).toUpperCase().padStart(4,"0")}</td>`;
    }
    tr.innerHTML = html;
    tbody.appendChild(tr);
  }
}

function escHtml(s) {
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

// ============================================================
// Handlers de botões
// ============================================================

document.getElementById("btn-step").addEventListener("click", () => {
  if (!sim.halted) {
    sim.step();
    updateUI(sim.snapshot());
  }
});

let runTimer = null;

document.getElementById("btn-run").addEventListener("click", () => {
  if (runTimer) { clearInterval(runTimer); runTimer = null; return; }
  runTimer = setInterval(() => {
    if (sim.halted) { clearInterval(runTimer); runTimer = null; return; }
    sim.step();
    updateUI(sim.snapshot());
  }, 150);
});

document.getElementById("btn-reset").addEventListener("click", () => {
  if (runTimer) { clearInterval(runTimer); runTimer = null; }
  // Preserva memória do programa mas reinicia estado
  const savedMem = new Uint16Array(sim.mem);
  sim.reset();
  sim.mem = savedMem;
  updateUI(sim.snapshot());
  document.getElementById("status-display").textContent = "IDLE";
  document.getElementById("status-display").className   = "status-idle";
});

document.getElementById("btn-assemble").addEventListener("click", () => {
  const src     = document.getElementById("asm-source").value;
  const errEl   = document.getElementById("asm-error");
  try {
    const mem = jsAssemble(src);
    if (runTimer) { clearInterval(runTimer); runTimer = null; }
    sim.loadProgram(mem);
    errEl.textContent = "";
    errEl.classList.add("hidden");
    updateUI(sim.snapshot());
  } catch(e) {
    errEl.textContent = "Erro: " + e.message;
    errEl.classList.remove("hidden");
  }
});

document.getElementById("btn-load").addEventListener("click", () => {
  // Carrega o exemplo padrão do textarea e monta
  document.getElementById("btn-assemble").click();
});

document.getElementById("btn-mem-goto").addEventListener("click", () => {
  const val = parseInt(document.getElementById("mem-addr-input").value, 16);
  if (!isNaN(val)) updateMemView(val);
});

// ---- Inicialização ----
buildRegGrid();
updateUI(sim.snapshot());
// Monta o código de exemplo ao carregar
setTimeout(() => document.getElementById("btn-assemble").click(), 100);
