// ============================================================================
// isa_pkg.vh  —  EduRISC-32v2  Instruction Set Architecture Package
//
// EduRISC-32v2: CPU educacional RISC de 32 bits, 32 registradores, pipeline
// de 5 estágios, com suporte a cache L1, MMU, interrupções e sistema operacional.
//
// ============================================================================
// FORMATOS DE INSTRUÇÃO (32 bits, largura fixa)
// ============================================================================
//
//  R-type:  [31:26]=op6 [25:21]=rd5 [20:16]=rs1_5 [15:11]=rs2_5 [10:6]=shamt5 [5:0]=unused
//  I-type:  [31:26]=op6 [25:21]=rd5 [20:16]=rs1_5 [15:0]=imm16  (sign-extended)
//  S-type:  [31:26]=op6 [25:21]=rs2_5 [20:16]=rs1_5 [15:0]=off16 (store: mem[rs1+off]=rs2)
//  B-type:  [31:26]=op6 [25:21]=rs1_5 [20:16]=rs2_5 [15:0]=off16 (branch, PC-relative em palavras)
//  J-type:  [31:26]=op6 [25:0]=addr26  (salto absoluto)
//  U-type:  [31:26]=op6 [25:21]=rd5  [20:0]=imm21   (MOVHI: carrega 21 bits no topo)
//
// ============================================================================
// REGISTRADORES
// ============================================================================
//  R0       = zero hardwired (leitura retorna 0, escrita descartada)
//  R1–R29   = uso geral pelo compilador / ABI
//  R30      = SP (Stack Pointer)
//  R31      = LR (Link Register — destino de CALL/CALLR)
//
// ============================================================================
// CONJUNTO DE INSTRUÇÕES (57 instruções)
// ============================================================================
//
// Aritmética:
//   ADD  rd,rs1,rs2    R  rd=rs1+rs2
//   ADDI rd,rs1,imm16  I  rd=rs1+sext(imm16)
//   SUB  rd,rs1,rs2    R  rd=rs1-rs2
//   MUL  rd,rs1,rs2    R  rd=(rs1*rs2)[31:0]
//   MULH rd,rs1,rs2    R  rd=(rs1*rs2)[63:32]  (inteiros com sinal)
//   DIV  rd,rs1,rs2    R  rd=rs1/rs2 (com sinal, inteiro)
//   DIVU rd,rs1,rs2    R  rd=rs1/rs2 (sem sinal)
//   REM  rd,rs1,rs2    R  rd=rs1%rs2 (com sinal)
//
// Lógica:
//   AND  rd,rs1,rs2    R   ANDI rd,rs1,imm16  I (zero-ext)
//   OR   rd,rs1,rs2    R   ORI  rd,rs1,imm16  I
//   XOR  rd,rs1,rs2    R   XORI rd,rs1,imm16  I
//   NOT  rd,rs1        R   rd=~rs1
//   NEG  rd,rs1        R   rd=-rs1
//
// Deslocamento:
//   SHL  rd,rs1,rs2    R   SHLI  rd,rs1,imm5  I
//   SHR  rd,rs1,rs2    R   SHRI  rd,rs1,imm5  I   (lógico)
//   SHRA rd,rs1,rs2    R   SHRAI rd,rs1,imm5  I   (aritmético)
//
// Movimentação / Comparação:
//   MOV  rd,rs1        R   rd=rs1
//   MOVI rd,imm16      I   rd=sext(imm16)
//   MOVHI rd,imm21     U   rd=imm21<<11
//   SLT  rd,rs1,rs2    R   rd=(rs1<rs2 signed)?1:0
//   SLTU rd,rs1,rs2    R   (sem sinal)
//   SLTI rd,rs1,imm16  I   (signed imm)
//
// Memória (loads):
//   LW  rd,off(rs1)  I    LH  rd,off(rs1)  I  LHU rd,off(rs1)  I
//   LB  rd,off(rs1)  I    LBU rd,off(rs1)  I
//
// Memória (stores, S-type):
//   SW  rs2,off(rs1)  S    SH  rs2,off(rs1)  S    SB  rs2,off(rs1)  S
//
// Desvios (B-type, offset em palavras de 32-bit, PC-relativo):
//   BEQ rs1,rs2,off  BNE rs1,rs2,off  BLT rs1,rs2,off  BGE rs1,rs2,off
//   BLTU rs1,rs2,off  BGEU rs1,rs2,off
//
// Saltos:
//   JMP  addr26        J   PC=addr26 (absoluto)
//   JMPR rd,rs1,off16  I   rd=PC+1; PC=rs1+sext(off16)  (call-ret via reg)
//   CALL addr26        J   R31=PC+1; PC=addr26
//   CALLR rs1          R   R31=PC+1; PC=rs1
//   RET                R   PC=R31
//   PUSH rs1           R   SP=SP-1; Mem[SP]=rs1
//   POP  rd            R   rd=Mem[SP]; SP=SP+1
//
// Sistema:
//   NOP               R    (no-operation)
//   HLT               R    (para o pipeline)
//   SYSCALL imm16     I    (trap para kernel; nr em imm16)
//   ERET              R    (retorno de exceção: PC=EPC)
//   MFC  rd,csr5      I    (rd=CSR[imm16[4:0]])
//   MTC  rs1,csr5     I    (CSR[imm16[4:0]]=rs1)
//   FENCE             R    (barreira de memória)
//   BREAK             R    (breakpoint — exceção #BREAK)
//
// ============================================================================
// CSRs (5-bit → 32 posições)
// ============================================================================
//  0: STATUS  — [0]=IE(intr enable) [1]=KU(0=kernel,1=user) [7:4]=IM(intr mask)
//  1: IVT     — base da tabela de vetores de interrupção
//  2: EPC     — Program Counter salvo na entrada de exceção
//  3: CAUSE   — [31]=1→intr [31]=0→excep; [30:0]=código
//  4: ESCRATCH— scratch para handler de exceção
//  5: PTBR    — base da tabela de páginas (endereço físico >> 12)
//  6: TLBCTL  — controle do TLB (flush bit em [0])
//  7: CYCLE   — contador de ciclos (32 bits inferiores)
//  8: CYCLEH  — contador de ciclos (32 bits superiores)
//  9: INSTRET — instruções aposentadas
// 10: ICOUNT  — ciclos de stall por dados
// 11: DCMISS  — misses de D-cache
// 12: ICMISS  — misses de I-cache
// 13: BRMISS  — desvios mal previstos
//
// ============================================================================
// CAUSAS DE EXCEÇÃO / INTERRUPÇÃO (campo CAUSE)
// ============================================================================
//  Exceções (bit31=0):  0=ILLEGAL_INST 1=DIV_ZERO 2=OVERFLOW 3=SYSCALL
//                       4=BREAKPOINT   5=IFETCH_PAGEFAULT 6=LOAD_PAGEFAULT
//                       7=STORE_PAGEFAULT  8=UNALIGNED
//  Interrupções (bit31=1): 0=TIMER  1..7=External[6:0]
// ============================================================================

`ifndef ISA_PKG_VH
`define ISA_PKG_VH

// ---------------------------------------------------------------------------
// Dimensões gerais
// ---------------------------------------------------------------------------
`define WORD_W     32          // largura da palavra de dados
`define ADDR_W     26          // largura do PC (64M palavras = 256 MB)
`define REG_W       5          // bits para índice de registrador (32 regs)
`define REG_N      32          // número de registradores
`define REG_SP     5'd30       // Stack Pointer
`define REG_LR     5'd31       // Link Register
`define MEM_DEPTH  (1<<20)     // profundidade da BRAM interna (1M palavras = 4 MB)

// ---------------------------------------------------------------------------
// Opcodes (6 bits)
// ---------------------------------------------------------------------------
// Aritmética
`define OP_ADD      6'h00   // R: rd=rs1+rs2
`define OP_ADDI     6'h01   // I: rd=rs1+sext(imm16)
`define OP_SUB      6'h02   // R: rd=rs1-rs2
`define OP_MUL      6'h03   // R: rd=(rs1*rs2)[31:0]
`define OP_MULH     6'h04   // R: rd=(rs1*rs2)[63:32] signed
`define OP_DIV      6'h05   // R: rd=rs1/rs2 signed
`define OP_DIVU     6'h06   // R: rd=rs1/rs2 unsigned
`define OP_REM      6'h07   // R: rd=rs1%rs2 signed

// Lógica
`define OP_AND      6'h08   // R: rd=rs1&rs2
`define OP_ANDI     6'h09   // I: rd=rs1&zext(imm16)
`define OP_OR       6'h0A   // R: rd=rs1|rs2
`define OP_ORI      6'h0B   // I: rd=rs1|zext(imm16)
`define OP_XOR      6'h0C   // R: rd=rs1^rs2
`define OP_XORI     6'h0D   // I: rd=rs1^zext(imm16)
`define OP_NOT      6'h0E   // R: rd=~rs1
`define OP_NEG      6'h0F   // R: rd=-rs1

// Deslocamento
`define OP_SHL      6'h10   // R: rd=rs1<<rs2[4:0]
`define OP_SHR      6'h11   // R: rd=rs1>>rs2[4:0] (lógico)
`define OP_SHRA     6'h12   // R: rd=rs1>>>rs2[4:0] (aritmético)
`define OP_SHLI     6'h13   // I: rd=rs1<<imm16[4:0]
`define OP_SHRI     6'h14   // I: rd=rs1>>imm16[4:0] (lógico)
`define OP_SHRAI    6'h15   // I: rd=rs1>>>imm16[4:0] (aritmético)

// Movimentação / Comparação
`define OP_MOV      6'h16   // R: rd=rs1
`define OP_MOVI     6'h17   // I: rd=sext(imm16)
`define OP_MOVHI    6'h18   // U: rd=imm21<<11
`define OP_SLT      6'h19   // R: rd=(rs1<rs2 signed)?1:0
`define OP_SLTU     6'h1A   // R: rd=(rs1<rs2 unsigned)?1:0
`define OP_SLTI     6'h1B   // I: rd=(rs1<sext(imm16) signed)?1:0

// Cargas
`define OP_LW       6'h1C   // I: rd=Mem32[rs1+sext(imm16)]
`define OP_LH       6'h1D   // I: rd=sext(Mem16[rs1+sext(imm16)])
`define OP_LHU      6'h1E   // I: rd=zext(Mem16[rs1+sext(imm16)])
`define OP_LB       6'h1F   // I: rd=sext(Mem8[rs1+sext(imm16)])
`define OP_LBU      6'h20   // I: rd=zext(Mem8[rs1+sext(imm16)])

// Armazenamentos (S-type)
`define OP_SW       6'h21   // S: Mem32[rs1+sext(off16)]=rs2
`define OP_SH       6'h22   // S: Mem16[rs1+sext(off16)]=rs2[15:0]
`define OP_SB       6'h23   // S: Mem8 [rs1+sext(off16)]=rs2[7:0]

// Desvios condicionais (B-type, offset em palavras)
`define OP_BEQ      6'h24   // B: se rs1==rs2: PC+=sext(off16)
`define OP_BNE      6'h25   // B: se rs1!=rs2: PC+=sext(off16)
`define OP_BLT      6'h26   // B: se rs1<rs2 (signed): PC+=sext(off16)
`define OP_BGE      6'h27   // B: se rs1>=rs2 (signed): PC+=sext(off16)
`define OP_BLTU     6'h28   // B: se rs1<rs2 (unsigned): PC+=sext(off16)
`define OP_BGEU     6'h29   // B: se rs1>=rs2 (unsigned): PC+=sext(off16)

// Saltos
`define OP_JMP      6'h2A   // J: PC=addr26
`define OP_JMPR     6'h2B   // I: rd=PC+1; PC=rs1+sext(imm16)
`define OP_CALL     6'h2C   // J: R31=PC+1; PC=addr26
`define OP_CALLR    6'h2D   // R: R31=PC+1; PC=rs1
`define OP_RET      6'h2E   // R: PC=R31
`define OP_PUSH     6'h2F   // R: SP--; Mem[SP]=rs1
`define OP_POP      6'h30   // R: rd=Mem[SP]; SP++

// Sistema
`define OP_NOP      6'h31   // R: (nada)
`define OP_HLT      6'h32   // R: parar
`define OP_SYSCALL  6'h33   // I: trap #3; nro em imm16
`define OP_ERET     6'h34   // R: PC=EPC (retorno de exceção)
`define OP_MFC      6'h35   // I: rd=CSR[imm16[4:0]]
`define OP_MTC      6'h36   // I: CSR[imm16[4:0]]=rs1
`define OP_FENCE    6'h37   // R: barreira
`define OP_BREAK    6'h38   // R: breakpoint

// ---------------------------------------------------------------------------
// Códigos internos de operação da ALU (5 bits)
// ---------------------------------------------------------------------------
`define ALU_ADD     5'd0
`define ALU_SUB     5'd1
`define ALU_MUL     5'd2
`define ALU_MULH    5'd3
`define ALU_DIV     5'd4
`define ALU_DIVU    5'd5
`define ALU_REM     5'd6
`define ALU_AND     5'd7
`define ALU_OR      5'd8
`define ALU_XOR     5'd9
`define ALU_NOT     5'd10
`define ALU_NEG     5'd11
`define ALU_SHL     5'd12
`define ALU_SHR     5'd13
`define ALU_SHRA    5'd14
`define ALU_SLT     5'd15
`define ALU_SLTU    5'd16
`define ALU_PASS_A  5'd17   // passa rs1 sem operar (MOV, loads/stores, branches)
`define ALU_PASS_B  5'd18   // passa imm/rs2

// ---------------------------------------------------------------------------
// Tipos de acesso à memória (3 bits: mem_size)
// ---------------------------------------------------------------------------
`define MEM_WORD    2'b00   // 32 bits
`define MEM_HALF    2'b01   // 16 bits
`define MEM_BYTE    2'b10   // 8 bits

// ---------------------------------------------------------------------------
// CSR indices (5 bits)
// ---------------------------------------------------------------------------
`define CSR_STATUS   5'd0
`define CSR_IVT      5'd1
`define CSR_EPC      5'd2
`define CSR_CAUSE    5'd3
`define CSR_ESCRATCH 5'd4
`define CSR_PTBR     5'd5
`define CSR_TLBCTL   5'd6
`define CSR_CYCLE    5'd7
`define CSR_CYCLEH   5'd8
`define CSR_INSTRET  5'd9
`define CSR_ICOUNT   5'd10
`define CSR_DCMISS   5'd11
`define CSR_ICMISS   5'd12
`define CSR_BRMISS   5'd13

// ---------------------------------------------------------------------------
// Causas de exceção (campo CAUSE[30:0] quando CAUSE[31]=0)
// ---------------------------------------------------------------------------
`define EXC_ILLEGAL     5'd0
`define EXC_DIV_ZERO    5'd1
`define EXC_OVERFLOW    5'd2
`define EXC_SYSCALL     5'd3
`define EXC_BREAKPOINT  5'd4
`define EXC_IFETCH_PF   5'd5
`define EXC_LOAD_PF     5'd6
`define EXC_STORE_PF    5'd7
`define EXC_UNALIGNED   5'd8

// Causas de interrupção (campo CAUSE[30:0] quando CAUSE[31]=1)
`define INT_TIMER       5'd0
`define INT_EXT0        5'd1
`define INT_EXT1        5'd2
`define INT_EXT2        5'd3
`define INT_EXT3        5'd4
`define INT_EXT4        5'd5
`define INT_EXT5        5'd6
`define INT_EXT6        5'd7

`endif // ISA_PKG_VH
