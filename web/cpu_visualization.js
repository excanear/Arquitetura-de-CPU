/**
 * cpu_visualization.js — EduRISC-32v2 Pipeline Visualizer
 *
 * Contém:
 *   - ISA EduRISC-32v2 (57 instruções, 6 formatos)
 *   - Assembler JavaScript inline
 *   - Simulador de pipeline 5 estágios com forwarding e hazards
 *   - Cache L1 modelo (I$/D$, direct-mapped)
 *   - MMU/TLB modelo (32 entradas, fully associative)
 *   - Contadores de desempenho
 *   - Atualização do DOM em tempo real
 */

"use strict";

// ============================================================
// ISA EduRISC-32v2
// ============================================================

const OP = {
  ADD:0x00, ADDI:0x01, SUB:0x02, MUL:0x03, MULH:0x04, DIV:0x05, DIVU:0x06, REM:0x07,
  AND:0x08, ANDI:0x09, OR:0x0A,  ORI:0x0B,  XOR:0x0C, XORI:0x0D, NOT:0x0E, NEG:0x0F,
  SHL:0x10, SHR:0x11, SHRA:0x12, SHLI:0x13, SHRI:0x14, SHRAI:0x15,
  MOV:0x16, MOVI:0x17, MOVHI:0x18, SLT:0x19, SLTU:0x1A, SLTI:0x1B,
  LW:0x1C, LH:0x1D, LHU:0x1E, LB:0x1F, LBU:0x20,
  SW:0x21, SH:0x22, SB:0x23,
  BEQ:0x24, BNE:0x25, BLT:0x26, BGE:0x27, BLTU:0x28, BGEU:0x29,
  JMP:0x2A, JMPR:0x2B, CALL:0x2C, CALLR:0x2D, RET:0x2E, PUSH:0x2F, POP:0x30,
  NOP:0x31, HLT:0x32, SYSCALL:0x33, ERET:0x34, MFC:0x35, MTC:0x36, FENCE:0x37, BREAK:0x38,
};

const OP_NAME = {};
for (const [k,v] of Object.entries(OP)) OP_NAME[v] = k;

// Formato de cada instrução
const FMT = {
  R:  new Set([OP.ADD,OP.SUB,OP.MUL,OP.MULH,OP.DIV,OP.DIVU,OP.REM,
               OP.AND,OP.OR,OP.XOR,OP.NOT,OP.NEG,OP.SHL,OP.SHR,OP.SHRA,
               OP.MOV,OP.SLT,OP.SLTU]),
  I:  new Set([OP.ADDI,OP.ANDI,OP.ORI,OP.XORI,OP.SHLI,OP.SHRI,OP.SHRAI,
               OP.MOVI,OP.SLTI,OP.LW,OP.LH,OP.LHU,OP.LB,OP.LBU,
               OP.MFC,OP.MTC]),
  S:  new Set([OP.SW,OP.SH,OP.SB]),
  B:  new Set([OP.BEQ,OP.BNE,OP.BLT,OP.BGE,OP.BLTU,OP.BGEU]),
  J:  new Set([OP.JMP,OP.CALL,OP.RET,OP.NOP,OP.HLT,OP.SYSCALL,OP.ERET,OP.FENCE,OP.BREAK,OP.PUSH,OP.POP]),
  U:  new Set([OP.MOVHI]),
};

function instrFmt(op) {
  for (const [f, s] of Object.entries(FMT)) if (s.has(op)) return f;
  return "J";
}

// Instruções de load/store/branch/jump
const isLoad  = op => [OP.LW,OP.LH,OP.LHU,OP.LB,OP.LBU].includes(op);
const isStore = op => [OP.SW,OP.SH,OP.SB].includes(op);
const isBranch= op => [OP.BEQ,OP.BNE,OP.BLT,OP.BGE,OP.BLTU,OP.BGEU].includes(op);
const isJump  = op => [OP.JMP,OP.JMPR,OP.CALL,OP.CALLR,OP.RET].includes(op);
const isMulDiv= op => [OP.MUL,OP.MULH,OP.DIV,OP.DIVU,OP.REM].includes(op);

// ============================================================
// Inline Assembler (suporta MOVI, ADDI, ADD, MOV, BNE, HLT)
// ============================================================

function assemble(src) {
  /** Retorna { words: [int, ...], symbols: {label: addr} } ou lança Error */
  const lines = src.split('\n');
  const symbols = {};
  const intermediate = [];   // { op, args, addr }
  let addr = 0;

  // Passo 1: coletar símbolos e criar lista intermediária
  for (let rawLine of lines) {
    const line = rawLine.replace(/;.*$/, '').trim();
    if (!line) continue;

    // Label?
    let rest = line;
    const labelMatch = rest.match(/^(\w+)\s*:/);
    if (labelMatch) {
      symbols[labelMatch[1]] = addr;
      rest = rest.slice(labelMatch[0].length).trim();
      if (!rest) continue;
    }

    // Diretiva .org / .word
    if (rest.startsWith('.')) {
      const [dir, ...dargs] = rest.split(/\s+/);
      if (dir.toLowerCase() === '.org') {
        addr = parseInt(dargs[0], 0);
      } else if (dir.toLowerCase() === '.word') {
        intermediate.push({ addr, op: '__DATA__', val: parseInt(dargs[0], 0) });
        addr++;
      }
      continue;
    }

    const parts = rest.split(/[\s,]+/).filter(Boolean);
    if (!parts.length) continue;

    const mnemonic = parts[0].toUpperCase();
    intermediate.push({ addr, mnemonic, args: parts.slice(1) });
    addr++;
  }

  // Passo 2: gerar palavras
  const words = new Array(addr).fill(0);

  function parseReg(s) {
    if (!s) throw new Error(`Registrador ausente`);
    const m = s.toUpperCase().match(/^R(\d+)$/);
    if (!m) throw new Error(`Registrador inválido: ${s}`);
    const n = parseInt(m[1]);
    if (n > 31) throw new Error(`R${n} fora do intervalo`);
    return n;
  }

  function parseImm(s, bits) {
    if (symbols[s] !== undefined) return symbols[s];
    const v = parseInt(s, 0);
    if (isNaN(v)) throw new Error(`Operando inválido: ${s}`);
    return v & ((1 << bits) - 1);
  }

  for (const item of intermediate) {
    if (item.op === '__DATA__') { words[item.addr] = item.val & 0xFFFFFFFF; continue; }
    const { mnemonic, args, addr: ia } = item;
    const opcode = OP[mnemonic];
    if (opcode === undefined) throw new Error(`Mnemônico desconhecido: ${mnemonic}`);
    let word = (opcode << 26) >>> 0;
    const fmt = instrFmt(opcode);

    try {
      if (fmt === 'R') {
        const rd  = parseReg(args[0]);
        const rs1 = parseReg(args[1]);
        const rs2 = parseReg(args[2] || '0');
        word |= (rd << 21) | (rs1 << 16) | (rs2 << 11);
      } else if (fmt === 'I') {
        const rd  = parseReg(args[0]);
        const rs1 = parseReg(args[1]);
        const imm = parseImm(args[2] || '0', 16) & 0xFFFF;
        word |= (rd << 21) | (rs1 << 16) | imm;
      } else if (fmt === 'S') {
        const rs2 = parseReg(args[0]);
        const rs1 = parseReg(args[1]);
        const off = parseImm(args[2] || '0', 16) & 0xFFFF;
        word |= (rs2 << 21) | (rs1 << 16) | off;
      } else if (fmt === 'B') {
        const rs1 = parseReg(args[0]);
        const rs2 = parseReg(args[1]);
        let   off = parseImm(args[2] || '0', 16);
        // Se argumento for label, calcular offset relativo
        if (symbols[args[2]] !== undefined) off = symbols[args[2]] - ia;
        word |= (rs1 << 21) | (rs2 << 16) | (off & 0xFFFF);
      } else if (fmt === 'J') {
        if (args[0]) {
          const dest = symbols[args[0]] !== undefined ? symbols[args[0]] : parseImm(args[0], 26);
          word |= dest & 0x3FFFFFF;
        }
        // PUSH/POP usam campo rs2 (bits 25:21)
        if (opcode === OP.PUSH || opcode === OP.POP) {
          const rn = parseReg(args[0]);
          word = ((opcode << 26) | (rn << 21)) >>> 0;
        }
      } else if (fmt === 'U') {
        const rd  = parseReg(args[0]);
        const imm = parseImm(args[1] || '0', 21) & 0x1FFFFF;
        word |= (rd << 21) | imm;
      }
    } catch(e) {
      throw new Error(`Linha "${mnemonic} ${args.join(' ')}": ${e.message}`);
    }

    words[ia] = word >>> 0;
  }

  return { words, symbols };
}

// ============================================================
// Simulador de pipeline 5 estágios
// ============================================================

class PipelineStage {
  constructor(name) {
    this.name   = name;
    this.valid  = false;
    this.op     = OP.NOP;
    this.pc     = 0;
    this.rd     = 0;
    this.rs1    = 0;
    this.rs2    = 0;
    this.imm    = 0;
    this.result = 0;
    this.memData= 0;
    this.detail = '—';
  }
}

class Cache {
  constructor(sets=256, ways=1, lineWords=4) {
    this.sets     = sets;
    this.ways     = ways;
    this.lineWords= lineWords;
    this.tags     = new Int32Array(sets).fill(-1);
    this.valid    = new Uint8Array(sets);
    this.dirty    = new Uint8Array(sets);   // D-cache
    this.data     = [];
    for (let i=0;i<sets;i++) this.data.push(new Array(lineWords).fill(0));

    this.accesses = 0;
    this.misses   = 0;
  }

  access(addr, write=false, wdata=0) {
    const idx = (addr >> 2) & (this.sets - 1);
    const tag = (addr >> (2 + Math.log2(this.sets)));
    this.accesses++;
    if (this.valid[idx] && this.tags[idx] === tag) {
      if (write) { this.data[idx][0] = wdata; this.dirty[idx] = 1; }
      return { hit: true, data: this.data[idx][0] };
    }
    // Miss → fill (simplificado: sem latência na simulação)
    this.misses++;
    this.valid[idx] = 1;
    this.tags[idx]  = tag;
    this.dirty[idx] = write ? 1 : 0;
    if (write) this.data[idx][0] = wdata;
    return { hit: false, data: 0 };
  }

  get missRate() {
    return this.accesses ? (this.misses / this.accesses * 100).toFixed(1) + '%' : '—';
  }
}

class TLB {
  constructor(entries=32) {
    this.entries = entries;
    this.vpn   = new Int32Array(entries).fill(-1);
    this.pfn   = new Int32Array(entries);
    this.flags = new Uint8Array(entries);  // V/R/W/X/U
    this.fifo  = 0;
    this.hits   = 0;
    this.misses = 0;
    this.faults = 0;
  }

  lookup(vpn) {
    for (let i=0;i<this.entries;i++) {
      if ((this.flags[i]&1) && this.vpn[i]===vpn) { this.hits++; return i; }
    }
    this.misses++;
    return -1;
  }

  install(vpn, pfn, flags) {
    const idx = this.fifo;
    this.vpn[idx]   = vpn;
    this.pfn[idx]   = pfn;
    this.flags[idx] = flags | 1;  // V=1
    this.fifo       = (this.fifo + 1) % this.entries;
  }

  flush() {
    this.flags.fill(0);
    this.vpn.fill(-1);
    this.fifo = 0;
  }
}

class EduRISC32Sim {
  constructor() {
    this.regs   = new Int32Array(32);
    this.csrs   = new Int32Array(32);
    this.mem    = new Int32Array(1 << 20);  // 1M words = 4MB
    this.pc     = 0;
    this.cycle  = 0;
    this.instret= 0;
    this.stalls  = 0;
    this.brmiss  = 0;
    this.halted  = false;
    this.log     = [];

    this.icache = new Cache();
    this.dcache = new Cache();
    this.tlb    = new TLB();

    // Estágios do pipeline (registradores inter-estágio)
    this.if_stage  = new PipelineStage("IF");
    this.id_stage  = new PipelineStage("ID");
    this.ex_stage  = new PipelineStage("EX");
    this.mem_stage = new PipelineStage("MEM");
    this.wb_stage  = new PipelineStage("WB");

    // Flags de hazard
    this.stall    = false;
    this.flush    = false;
    this.fwd_ex   = false;
    this.fwd_mem  = false;
  }

  loadProgram(words) {
    for (let i=0;i<words.length;i++) this.mem[i] = words[i];
  }

  reset() {
    this.regs.fill(0);
    this.csrs.fill(0);
    this.pc     = 0;
    this.cycle  = 0;
    this.instret= 0;
    this.stalls  = 0;
    this.brmiss  = 0;
    this.halted  = false;
    this.log     = [];
    this.icache = new Cache();
    this.dcache = new Cache();
    this.tlb    = new TLB();
    this.if_stage  = new PipelineStage("IF");
    this.id_stage  = new PipelineStage("ID");
    this.ex_stage  = new PipelineStage("EX");
    this.mem_stage = new PipelineStage("MEM");
    this.wb_stage  = new PipelineStage("WB");
    this.stall = false; this.flush = false;
    this.fwd_ex = false; this.fwd_mem = false;
  }

  /** Avança 1 ciclo de clock */
  step() {
    if (this.halted) return;
    this.cycle++;
    this.stall = false; this.flush = false;
    this.fwd_ex = false; this.fwd_mem = false;

    // === WB ===
    const wb = this.wb_stage;
    if (wb.valid && wb.rd !== 0 && wb.rd !== undefined) {
      const wdata = isLoad(wb.op) ? wb.memData : wb.result;
      this.regs[wb.rd] = wdata;
      if (wb.op === OP.HLT) this.halted = true;
    }

    // === MEM ===
    const ms = this.mem_stage;
    this.wb_stage = new PipelineStage("WB");
    Object.assign(this.wb_stage, ms);
    if (ms.valid && isLoad(ms.op)) {
      const { data } = this.dcache.access(ms.result & 0xFFFFF);
      this.wb_stage.memData = data;
      this.instret++;
    } else if (ms.valid && isStore(ms.op)) {
      this.dcache.access(ms.result & 0xFFFFF, true, this.regs[ms.rs2]);
      this.mem[ms.result & 0xFFFFF] = this.regs[ms.rs2];
      this.instret++;
    } else if (ms.valid) {
      this.instret++;
    }

    // === EX ===
    const ex = this.ex_stage;
    this.mem_stage = new PipelineStage("MEM");
    Object.assign(this.mem_stage, ex);

    if (ex.valid) {
      // Forwarding
      let a = this.regs[ex.rs1] || 0;
      let b = this.regs[ex.rs2] || 0;

      if (ms.valid && ms.rd && ms.rd === ex.rs1) { a = ms.result; this.fwd_ex = true; }
      if (ms.valid && ms.rd && ms.rd === ex.rs2) { b = ms.result; this.fwd_ex = true; }
      if (wb.valid && wb.rd && wb.rd === ex.rs1 && !this.fwd_ex) { a = this.regs[ex.rs1]; this.fwd_mem = true; }

      // Selecionar operando B (imediato vs.reg)
      const bsrc = FMT.I.has(ex.op) || FMT.S.has(ex.op) || FMT.B.has(ex.op) ? ex.imm : b;

      const sa  = a | 0;  const sb = bsrc | 0;
      const ua  = a >>> 0; const ub = bsrc >>> 0;

      switch(ex.op) {
        case OP.ADD:  case OP.ADDI: this.mem_stage.result = (sa + sb) | 0; break;
        case OP.SUB:                this.mem_stage.result = (sa - sb) | 0; break;
        case OP.MUL:                this.mem_stage.result = Math.imul(sa, sb); break;
        case OP.AND:  case OP.ANDI: this.mem_stage.result = sa & sb; break;
        case OP.OR:   case OP.ORI:  this.mem_stage.result = sa | sb; break;
        case OP.XOR:  case OP.XORI: this.mem_stage.result = sa ^ sb; break;
        case OP.NOT:                this.mem_stage.result = ~sa; break;
        case OP.NEG:                this.mem_stage.result = -sa; break;
        case OP.SHL:  case OP.SHLI: this.mem_stage.result = sa << (sb & 31); break;
        case OP.SHR:  case OP.SHRI: this.mem_stage.result = ua >>> (ub & 31); break;
        case OP.SHRA: case OP.SHRAI:this.mem_stage.result = sa >> (sb & 31); break;
        case OP.MOV:                this.mem_stage.result = sa; break;
        case OP.MOVI:               this.mem_stage.result = ex.imm; break;
        case OP.MOVHI:              this.mem_stage.result = (ex.imm & 0x1FFFFF) << 11; break;
        case OP.SLT:  case OP.SLTI: this.mem_stage.result = sa < sb ? 1 : 0; break;
        case OP.SLTU:               this.mem_stage.result = ua < ub ? 1 : 0; break;
        case OP.LW:  case OP.LH: case OP.LHU: case OP.LB: case OP.LBU:
        case OP.SW:  case OP.SH:  case OP.SB:
          this.mem_stage.result = (sa + sb) | 0;  // addr
          break;
        // Branches: calcular taken
        case OP.BEQ:  case OP.BNE: case OP.BLT:
        case OP.BGE:  case OP.BLTU: case OP.BGEU: {
          let taken = false;
          if (ex.op===OP.BEQ)  taken = a===b;
          if (ex.op===OP.BNE)  taken = a!==b;
          if (ex.op===OP.BLT)  taken = sa<(b|0);
          if (ex.op===OP.BGE)  taken = sa>=(b|0);
          if (ex.op===OP.BLTU) taken = ua<ub;
          if (ex.op===OP.BGEU) taken = ua>=ub;
          if (taken) {
            const target = (ex.pc + ex.imm) & 0x3FFFFFF;
            this.pc = target;
            this.flush = true; this.brmiss++;
          }
          this.mem_stage.result = taken ? 1 : 0;
          break;
        }
        case OP.JMP:  case OP.CALL:
          this.pc = ex.imm & 0x3FFFFFF; this.flush = true; break;
        case OP.RET:
          this.pc = this.regs[31] & 0x3FFFFFF; this.flush = true; break;
        case OP.MFC:
          this.mem_stage.result = this.csrs[ex.imm & 0x1F]; break;
        case OP.MTC:
          this.csrs[ex.imm & 0x1F] = a; break;
        default: break;
      }

      // CALL: salvar LR
      if (ex.op === OP.CALL || ex.op === OP.CALLR) this.regs[31] = ex.pc + 1;

      this.mem_stage.detail = `${OP_NAME[ex.op]||'?'} R${ex.rd}=0x${(this.mem_stage.result>>>0).toString(16)}`;
    }

    // === ID ===
    const id = this.id_stage;
    this.ex_stage = new PipelineStage("EX");

    // Load-use hazard: bolha se instrução anterior é LW e usa o mesmo registrador
    const load_use = ms.valid && isLoad(ms.op) && ms.rd !== 0 &&
                     (ms.rd === id.rs1 || ms.rd === id.rs2);
    if (load_use) { this.stall = true; this.stalls++; }

    if (load_use) {
      // Inserir bolha no EX, manter ID/IF
      this.ex_stage.valid = false;
      this.ex_stage.op    = OP.NOP;
    } else {
      Object.assign(this.ex_stage, id);
      this.ex_stage.detail = id.valid ? `${OP_NAME[id.op]||'?'} R${id.rs1},R${id.rs2}` : '—';
    }

    // === IF ===
    const io = this.if_stage;
    this.id_stage = new PipelineStage("ID");

    if (!load_use && !this.halted) {
      if (io.valid && !this.flush) {
        const word = io.word || 0;
        const op   = (word >>> 26) & 0x3F;
        const fmt  = instrFmt(op);
        let rd=0, rs1=0, rs2=0, imm=0;
        if (fmt==='R'||fmt==='I'||fmt==='U') { rd=(word>>>21)&0x1f; rs1=(word>>>16)&0x1f; }
        if (fmt==='R') { rs2=(word>>>11)&0x1f; }
        if (fmt==='I') { imm=((word&0xFFFF)<<16)>>16; }  // sext16
        if (fmt==='S') { rs2=(word>>>21)&0x1f; rs1=(word>>>16)&0x1f; imm=((word&0xFFFF)<<16)>>16; }
        if (fmt==='B') { rs1=(word>>>21)&0x1f; rs2=(word>>>16)&0x1f; imm=((word&0xFFFF)<<16)>>16; }
        if (fmt==='J') { imm=((word&0x3FFFFFF)<<6)>>6; }  // sext26
        if (fmt==='U') { imm=word&0x1FFFFF; }
        this.id_stage = { ...new PipelineStage("ID"), valid:true, op, rd, rs1, rs2, imm,
          pc:io.pc, detail:`${OP_NAME[op]||'?'} [${io.pc.toString(16)}]` };
      }
    }

    // Fetch nova instrução
    if (!this.stall && !this.halted) {
      const fetchPc = this.flush ? this.pc : this.pc;
      const { hit } = this.icache.access(fetchPc);
      const word = this.mem[fetchPc & 0xFFFFF] || 0;
      this.if_stage = { ...new PipelineStage("IF"), valid:true, pc: fetchPc,
        word, detail:`0x${(word>>>0).toString(16).padStart(8,'0')} @${fetchPc.toString(16)}` };
      if (!this.flush) this.pc = (this.pc + 1) & 0x3FFFFFF;
    }

    if (this.flush) {
      this.if_stage.valid = false;
      this.id_stage.valid = false;
    }

    // Update performance counters
    this.csrs[7] = this.cycle & 0x7FFFFFFF;
    this.csrs[9] = this.instret;
    this.csrs[10]= this.stalls;
    this.csrs[11]= this.dcache.misses;
    this.csrs[12]= this.icache.misses;
    this.csrs[13]= this.brmiss;

    this.regs[0] = 0;  // R0 sempre zero

    this.log.push(`[${this.cycle}] PC=0x${this.ex_stage.pc?.toString(16)||'?'} ${OP_NAME[this.ex_stage.op]||'?'}`);
    if (this.log.length > 200) this.log.shift();
  }
}

// ============================================================
// UI
// ============================================================

const sim = new EduRISC32Sim();
let programLoaded = false;
let runTimer = null;

// Nomes canônicos dos CSRs
const CSR_NAMES = [
  'STATUS','IVT','EPC','CAUSE','ESCRATCH','PTBR','TLBCTL',
  'CYCLE','CYCLEH','INSTRET','ICOUNT','DCMISS','ICMISS','BRMISS',
];

// ---------------------------------------------------------------
// Inicialização dos painéis
// ---------------------------------------------------------------
function initRegGrid() {
  const grid = document.getElementById('reg-grid');
  grid.innerHTML = '';
  for (let i=0;i<32;i++) {
    const cell = document.createElement('div');
    cell.className = 'reg-cell' + (i===0?' r0':(i===30?' sp':(i===31?' lr':'')));
    cell.id = `reg-${i}`;
    cell.innerHTML = `<div class="reg-name">R${i}${i===0?'/zero':i===30?'/SP':i===31?'/LR':''}</div>
                      <div class="reg-val" id="rval-${i}">0x00000000</div>`;
    grid.appendChild(cell);
  }
}

function initCSRGrid() {
  const grid = document.getElementById('csr-grid');
  grid.innerHTML = '';
  for (let i=0;i<14;i++) {
    const cell = document.createElement('div');
    cell.className = 'csr-cell';
    cell.innerHTML = `<div class="csr-name">[${i}] ${CSR_NAMES[i]||'CSR'+i}</div>
                      <div class="csr-val" id="csr-${i}">0x00000000</div>`;
    grid.appendChild(cell);
  }
}

function initCacheTables() {
  // Mostrar apenas as primeiras 16 linhas
  const rows = 16;
  ['ic-tbody','dc-tbody'].forEach(id => {
    const tbody = document.getElementById(id);
    tbody.innerHTML = '';
    for (let i=0;i<rows;i++) {
      const tr = document.createElement('tr');
      tr.id = `${id}-row-${i}`;
      tr.innerHTML = `<td>${i}</td><td>0</td><td>—</td><td>0x00000000</td><td>0x00000000</td>`;
      tbody.appendChild(tr);
    }
  });
}

function initTLBTable() {
  const tbody = document.getElementById('tlb-tbody');
  tbody.innerHTML = '';
  for (let i=0;i<16;i++) {
    const tr = document.createElement('tr');
    tr.id = `tlb-row-${i}`;
    tr.innerHTML = `<td>${i}</td><td>0</td><td>—</td><td>—</td><td>0</td><td>0</td><td>0</td><td>0</td>`;
    tbody.appendChild(tr);
  }
}

// ---------------------------------------------------------------
// Atualização de UI
// ---------------------------------------------------------------
const prevRegs = new Int32Array(32);

function updateUI() {
  // Registradores
  for (let i=0;i<32;i++) {
    const el = document.getElementById(`rval-${i}`);
    const cell = document.getElementById(`reg-${i}`);
    if (!el) continue;
    const val = sim.regs[i] >>> 0;
    el.textContent = '0x' + val.toString(16).padStart(8,'0');
    if (val !== (prevRegs[i] >>> 0)) { cell.classList.add('changed'); }
    else { cell.classList.remove('changed'); }
    prevRegs[i] = sim.regs[i];
  }

  // CSRs
  for (let i=0;i<14;i++) {
    const el = document.getElementById(`csr-${i}`);
    if (el) el.textContent = '0x'+(sim.csrs[i]>>>0).toString(16).padStart(8,'0');
  }

  // Pipeline stages
  const stages = [
    ['if',  sim.if_stage],
    ['id',  sim.id_stage],
    ['ex',  sim.ex_stage],
    ['mem', sim.mem_stage],
    ['wb',  sim.wb_stage],
  ];
  for (const [name, st] of stages) {
    document.getElementById(`${name}-detail`).textContent = st.detail || '—';
    const el = document.getElementById(`stage-${name}`);
    el.classList.toggle('active', !!st.valid);
    el.classList.toggle('stall',  name==='if' && sim.stall);
    el.classList.toggle('flush',  name==='if' && sim.flush);
  }

  // Hazard indicators
  document.getElementById('haz-stall'  ).classList.toggle('active', sim.stall);
  document.getElementById('haz-flush'  ).classList.toggle('active', sim.flush);
  document.getElementById('haz-fwd-ex' ).classList.toggle('active', sim.fwd_ex);
  document.getElementById('haz-fwd-mem').classList.toggle('active', sim.fwd_mem);

  // Cache stats
  document.getElementById('ic-access').textContent   = sim.icache.accesses;
  document.getElementById('ic-miss').textContent     = sim.icache.misses;
  document.getElementById('ic-missrate').textContent = sim.icache.missRate;
  document.getElementById('dc-access').textContent   = sim.dcache.accesses;
  document.getElementById('dc-miss').textContent     = sim.dcache.misses;
  document.getElementById('dc-missrate').textContent = sim.dcache.missRate;

  // Cache rows
  for (let i=0;i<16;i++) {
    const ic = document.getElementById(`ic-tbody-row-${i}`);
    const dc = document.getElementById(`dc-tbody-row-${i}`);
    if (ic) {
      const v = sim.icache.valid[i];
      const tag = v ? ('0x'+sim.icache.tags[i].toString(16)) : '—';
      const w0  = v ? ('0x'+(sim.icache.data[i][0]>>>0).toString(16).padStart(8,'0')) : '—';
      const w1  = v ? ('0x'+(sim.icache.data[i][1]>>>0).toString(16).padStart(8,'0')) : '—';
      ic.innerHTML = `<td>${i}</td><td>${v}</td><td>${tag}</td><td>${w0}</td><td>${w1}</td>`;
    }
    if (dc) {
      const v = sim.dcache.valid[i]; const d = sim.dcache.dirty[i];
      const tag = v ? ('0x'+sim.dcache.tags[i].toString(16)) : '—';
      const w0  = v ? ('0x'+(sim.dcache.data[i][0]>>>0).toString(16).padStart(8,'0')) : '—';
      const w1  = v ? ('0x'+(sim.dcache.data[i][1]>>>0).toString(16).padStart(8,'0')) : '—';
      dc.innerHTML = `<td>${i}</td><td>${v}</td><td class="${d?'dirty':''}">${d}</td><td>${tag}</td><td>${w0}</td><td>${w1}</td>`;
    }
  }

  // TLB rows
  for (let i=0;i<16;i++) {
    const tr = document.getElementById(`tlb-row-${i}`);
    if (!tr) continue;
    const v    = (sim.tlb.flags[i] & 1);
    const vpn  = v ? ('0x'+sim.tlb.vpn[i].toString(16)) : '—';
    const pfn  = v ? ('0x'+sim.tlb.pfn[i].toString(16)) : '—';
    const f    = sim.tlb.flags[i];
    tr.innerHTML=`<td>${i}</td><td>${v}</td><td>${vpn}</td><td>${pfn}</td>`+
      `<td>${(f>>1)&1}</td><td>${(f>>2)&1}</td><td>${(f>>3)&1}</td><td>${(f>>4)&1}</td>`;
  }

  document.getElementById('tlb-hits').textContent   = sim.tlb.hits;
  document.getElementById('tlb-misses').textContent = sim.tlb.misses;
  document.getElementById('pf-count').textContent   = sim.tlb.faults;

  // MMU vm-enable
  const st = sim.csrs[0];
  const vmOn = !!(st & 2);
  const vmEl = document.getElementById('vm-enable');
  vmEl.textContent = vmOn ? 'ON' : 'OFF';
  vmEl.className   = vmOn ? 'vm-on' : 'vm-off';

  // Counters
  document.getElementById('p-cycles').textContent  = sim.cycle;
  document.getElementById('p-instret').textContent = sim.instret;
  document.getElementById('p-stalls').textContent  = sim.stalls;
  document.getElementById('p-icmiss').textContent  = sim.icache.misses;
  document.getElementById('p-dcmiss').textContent  = sim.dcache.misses;
  document.getElementById('p-brmiss').textContent  = sim.brmiss;

  // CPI
  const cpi = sim.instret > 0 ? (sim.cycle / sim.instret).toFixed(2) : '—';
  document.getElementById('cpi-display').textContent = cpi;

  // PC / cycle / status
  document.getElementById('cycle-num').textContent = sim.cycle;
  document.getElementById('pc-display').textContent = '0x' + sim.pc.toString(16).padStart(6,'0');
  const statusEl = document.getElementById('status-display');
  if (sim.halted) { statusEl.textContent='HALTED'; statusEl.className='status-halted'; }
  else if (sim.stall) { statusEl.textContent='STALL'; statusEl.className='status-stall'; }
  else { statusEl.textContent='RUNNING'; statusEl.className='status-running'; }

  // Log
  const logEl = document.getElementById('exec-log');
  logEl.textContent = sim.log.slice(-60).join('\n');
  logEl.scrollTop = logEl.scrollHeight;
}

// ---------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------
document.getElementById('btn-assemble').addEventListener('click', () => {
  const src = document.getElementById('asm-source').value;
  const errEl = document.getElementById('asm-error');
  try {
    const { words } = assemble(src);
    sim.reset();
    sim.loadProgram(words);
    programLoaded = true;
    errEl.textContent = `Montado: ${words.length} words`;
    errEl.classList.remove('hidden');
    errEl.style.color = 'var(--accent2)';
    updateUI();
  } catch(e) {
    errEl.textContent = '❌ ' + e.message;
    errEl.classList.remove('hidden');
    errEl.style.color = 'var(--danger)';
    programLoaded = false;
  }
});

document.getElementById('btn-step').addEventListener('click', () => {
  if (!programLoaded) return;
  sim.step();
  updateUI();
});

document.getElementById('btn-run').addEventListener('click', () => {
  if (!programLoaded) return;
  if (runTimer) { clearInterval(runTimer); runTimer = null; return; }
  runTimer = setInterval(() => {
    for (let i=0;i<4;i++) { sim.step(); if (sim.halted) break; }
    updateUI();
    if (sim.halted) { clearInterval(runTimer); runTimer = null; }
  }, 50);
});

document.getElementById('btn-reset').addEventListener('click', () => {
  if (runTimer) { clearInterval(runTimer); runTimer = null; }
  sim.reset();
  programLoaded = false;
  updateUI();
  document.getElementById('status-display').textContent = 'IDLE';
  document.getElementById('status-display').className   = 'status-idle';
  document.getElementById('exec-log').textContent = '';
});

document.getElementById('btn-load').addEventListener('click', () => {
  const example = `; Fibonacci F(10) — resultado em R3
    MOVI  R1, 0
    MOVI  R2, 1
    MOVI  R4, 10
loop:
    ADD   R3, R1, R2
    MOV   R1, R2
    MOV   R2, R3
    ADDI  R4, R4, -1
    BNE   R4, R0, loop
    HLT`;
  document.getElementById('asm-source').value = example;
  document.getElementById('btn-assemble').click();
});

// ---------------------------------------------------------------
// Inicializar
// ---------------------------------------------------------------
initRegGrid();
initCSRGrid();
initCacheTables();
initTLBTable();
updateUI();
