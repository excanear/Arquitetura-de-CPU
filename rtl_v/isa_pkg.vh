// ============================================================================
// isa_pkg.vh  —  EduRISC-32 Instruction Set Architecture Package
//
// EduRISC-32: RISC educacional de 32 bits derivado do EduRISC-16.
//
// Formato de instrução (32 bits, largura fixa):
//
//   Tipo-R:  [31:28]=opcode [27:24]=rd [23:20]=rs1 [19:16]=rs2 [15:0]=unused
//   Tipo-I:  [31:28]=opcode [27:24]=rd [23:20]=rs1 [19:0 ]=imm20
//   Tipo-J:  [31:28]=opcode [27:0 ]=addr28
//   Tipo-M:  [31:28]=opcode [27:24]=rd [23:20]=base [19:0]=offset20
//
// Opcodes (4 bits → 16 operações):
//   0x0  ADD    R-type  rd = rs1 + rs2
//   0x1  SUB    R-type  rd = rs1 - rs2
//   0x2  MUL    R-type  rd = rs1 * rs2  (32 bits inferiores)
//   0x3  DIV    R-type  rd = rs1 / rs2  (inteiro sem sinal)
//   0x4  AND    R-type  rd = rs1 & rs2
//   0x5  OR     R-type  rd = rs1 | rs2
//   0x6  XOR    R-type  rd = rs1 ^ rs2
//   0x7  NOT    R-type  rd = ~rs1
//   0x8  LOAD   M-type  rd = MEM[base + offset20]
//   0x9  STORE  M-type  MEM[base + offset20] = rd
//   0xA  JMP    J-type  PC = addr28
//   0xB  JZ     J-type  if ZERO: PC = addr28
//   0xC  JNZ    J-type  if !ZERO: PC = addr28
//   0xD  CALL   J-type  R15=PC+1; PC = addr28
//   0xE  RET    R-type  PC = R15
//   0xF  HLT    R-type  parar execução (saída halt=1)
//
// Flags: ZERO (Z), CARRY (C), NEGATIVE (N), OVERFLOW (V)
// ============================================================================

`ifndef ISA_PKG_VH
`define ISA_PKG_VH

// ---- Opcodes ---------------------------------------------------------------
`define OP_ADD    4'h0
`define OP_SUB    4'h1
`define OP_MUL    4'h2
`define OP_DIV    4'h3
`define OP_AND    4'h4
`define OP_OR     4'h5
`define OP_XOR    4'h6
`define OP_NOT    4'h7
`define OP_LOAD   4'h8
`define OP_STORE  4'h9
`define OP_JMP    4'hA
`define OP_JZ     4'hB
`define OP_JNZ    4'hC
`define OP_CALL   4'hD
`define OP_RET    4'hE
`define OP_HLT    4'hF

// ---- Larguras --------------------------------------------------------------
`define WORD_WIDTH  32       // largura do barramento de dados
`define ADDR_WIDTH  28       // largura do espaço de endereçamento
`define REG_COUNT   16       // número de registradores
`define REG_BITS    4        // bits para indexar registradores
`define MEM_DEPTH   (1<<20)  // 1M palavras de 32-bit = 4 MB

// ---- ALU opcode (para sinal alu_op interno, 4 bits) -----------------------
`define ALU_ADD  4'h0
`define ALU_SUB  4'h1
`define ALU_MUL  4'h2
`define ALU_DIV  4'h3
`define ALU_AND  4'h4
`define ALU_OR   4'h5
`define ALU_XOR  4'h6
`define ALU_NOT  4'h7
`define ALU_SHL  4'h8
`define ALU_SHR  4'h9
`define ALU_SHRS 4'hA   // shift right aritmético
`define ALU_CMP  4'hB   // subtração sem writeback (só flags)
`define ALU_PASS 4'hF   // passa operando A sem operar

`endif // ISA_PKG_VH
