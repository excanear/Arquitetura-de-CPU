// ============================================================================
// control_unit.v  —  Unidade de Controle EduRISC-32v2
//
// Gera todos os sinais de controle do pipeline a partir do opcode de 6 bits.
// Utiliza always@(*) com defaults seguros para evitar latches.
//
// Sinais de saída:
//  reg_write   — habilita escrita no banco de registradores no WB
//  mem_read    — habilita leitura da D-cache/memória no MEM
//  mem_write   — habilita escrita na D-cache/memória no MEM
//  mem_to_reg  — 1=rd←memdata, 0=rd←alu_result
//  mem_size    — 2'b00=word 2'b01=half 2'b10=byte
//  mem_signed  — 1=extensão de sinal para LH/LB
//  alu_src_b   — 0=rs2, 1=imediato
//  is_branch   — instrução de desvio condicional
//  is_jump     — instrução de salto incondicional (inclui CALL/RET)
//  is_call     — escreve R31 com PC+1
//  is_ret      — PC←R31 (ou EPC para ERET)
//  is_push     — PUSH: decrementa SP e armazena
//  is_pop      — POP:  carrega e incrementa SP
//  is_system   — SYSCALL/ERET/FENCE/BREAK/HLT -> encaminha para exc_handler
//  halt        — HLT
//  trap_cause  — exceção causada por instrução (SYSCALL/BREAK/ILLEGAL)
//  trap_valid  — 1=dispara trap
//  alu_op      — código de operação para a ALU (5 bits)
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module control_unit (
    input  wire [5:0]  op,

    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,
    output reg  [1:0]  mem_size,    // `MEM_WORD / `MEM_HALF / `MEM_BYTE
    output reg         mem_signed,
    output reg         alu_src_b,   // 0=rs2, 1=immediate
    output reg         is_branch,
    output reg         is_jump,
    output reg         is_call,
    output reg         is_ret,
    output reg         is_push,
    output reg         is_pop,
    output reg         is_system,
    output reg         halt,
    output reg         trap_valid,
    output reg  [4:0]  trap_cause,  // campo EXC_*
    output reg  [4:0]  alu_op
);

    always @(*) begin
        // -- Defaults seguros (NOP-like) --
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_to_reg  = 1'b0;
        mem_size    = `MEM_WORD;
        mem_signed  = 1'b0;
        alu_src_b   = 1'b0;
        is_branch   = 1'b0;
        is_jump     = 1'b0;
        is_call     = 1'b0;
        is_ret      = 1'b0;
        is_push     = 1'b0;
        is_pop      = 1'b0;
        is_system   = 1'b0;
        halt        = 1'b0;
        trap_valid  = 1'b0;
        trap_cause  = `EXC_ILLEGAL;
        alu_op      = `ALU_ADD;

        case (op)
            // ---- Aritmética R-type ----
            `OP_ADD:  begin reg_write=1; alu_op=`ALU_ADD;  end
            `OP_SUB:  begin reg_write=1; alu_op=`ALU_SUB;  end
            `OP_MUL:  begin reg_write=1; alu_op=`ALU_MUL;  end
            `OP_MULH: begin reg_write=1; alu_op=`ALU_MULH; end
            `OP_DIV:  begin reg_write=1; alu_op=`ALU_DIV;  end
            `OP_DIVU: begin reg_write=1; alu_op=`ALU_DIVU; end
            `OP_REM:  begin reg_write=1; alu_op=`ALU_REM;  end

            // ---- Aritmética I-type ----
            `OP_ADDI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_ADD; end

            // ---- Lógica R-type ----
            `OP_AND:  begin reg_write=1; alu_op=`ALU_AND;  end
            `OP_OR:   begin reg_write=1; alu_op=`ALU_OR;   end
            `OP_XOR:  begin reg_write=1; alu_op=`ALU_XOR;  end
            `OP_NOT:  begin reg_write=1; alu_op=`ALU_NOT;  end
            `OP_NEG:  begin reg_write=1; alu_op=`ALU_NEG;  end

            // ---- Lógica I-type ----
            `OP_ANDI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_AND; end
            `OP_ORI:  begin reg_write=1; alu_src_b=1; alu_op=`ALU_OR;  end
            `OP_XORI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_XOR; end

            // ---- Deslocamento R-type ----
            `OP_SHL:  begin reg_write=1; alu_op=`ALU_SHL;  end
            `OP_SHR:  begin reg_write=1; alu_op=`ALU_SHR;  end
            `OP_SHRA: begin reg_write=1; alu_op=`ALU_SHRA; end

            // ---- Deslocamento I-type (usa shamt = bits [10:6] via imm5_zext) ----
            `OP_SHLI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_SHL; end
            `OP_SHRI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_SHR; end
            `OP_SHRAI:begin reg_write=1; alu_src_b=1; alu_op=`ALU_SHRA;end

            // ---- Movimentação ----
            `OP_MOV:  begin reg_write=1; alu_op=`ALU_PASS_A; end
            `OP_MOVI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_PASS_B; end
            `OP_MOVHI:begin reg_write=1; alu_src_b=1; alu_op=`ALU_PASS_B; end  // imm21_upper via alu_src_b

            // ---- Comparação ----
            `OP_SLT:  begin reg_write=1; alu_op=`ALU_SLT;  end
            `OP_SLTU: begin reg_write=1; alu_op=`ALU_SLTU; end
            `OP_SLTI: begin reg_write=1; alu_src_b=1; alu_op=`ALU_SLT; end

            // ---- Loads ----
            `OP_LW:   begin reg_write=1; mem_read=1; mem_to_reg=1; alu_src_b=1;
                           alu_op=`ALU_ADD; mem_size=`MEM_WORD; mem_signed=0; end
            `OP_LH:   begin reg_write=1; mem_read=1; mem_to_reg=1; alu_src_b=1;
                           alu_op=`ALU_ADD; mem_size=`MEM_HALF; mem_signed=1; end
            `OP_LHU:  begin reg_write=1; mem_read=1; mem_to_reg=1; alu_src_b=1;
                           alu_op=`ALU_ADD; mem_size=`MEM_HALF; mem_signed=0; end
            `OP_LB:   begin reg_write=1; mem_read=1; mem_to_reg=1; alu_src_b=1;
                           alu_op=`ALU_ADD; mem_size=`MEM_BYTE; mem_signed=1; end
            `OP_LBU:  begin reg_write=1; mem_read=1; mem_to_reg=1; alu_src_b=1;
                           alu_op=`ALU_ADD; mem_size=`MEM_BYTE; mem_signed=0; end

            // ---- Stores ----
            `OP_SW:   begin mem_write=1; alu_src_b=1; alu_op=`ALU_ADD; mem_size=`MEM_WORD; end
            `OP_SH:   begin mem_write=1; alu_src_b=1; alu_op=`ALU_ADD; mem_size=`MEM_HALF; end
            `OP_SB:   begin mem_write=1; alu_src_b=1; alu_op=`ALU_ADD; mem_size=`MEM_BYTE; end

            // ---- Desvios condicionais (cálculo de destino na ALU, comparação no EX)
            `OP_BEQ,`OP_BNE,`OP_BLT,`OP_BGE,`OP_BLTU,`OP_BGEU:
                      begin is_branch=1; alu_op=`ALU_SUB; end  // ALU faz rs1-rs2 para comparação

            // ---- Saltos incondicionais ----
            `OP_JMP:  begin is_jump=1;  alu_op=`ALU_PASS_B; end          // addr26 via alu_src_b
            `OP_JMPR: begin is_jump=1; is_call=1; reg_write=1;
                           alu_src_b=1; alu_op=`ALU_ADD; end               // PC=rs1+imm; rd=PC+1
            `OP_CALL: begin is_jump=1; is_call=1; alu_op=`ALU_PASS_B; end // R31=PC+1; PC=addr26
            `OP_CALLR:begin is_jump=1; is_call=1; alu_op=`ALU_PASS_A; end // R31=PC+1; PC=rs1
            `OP_RET:  begin is_jump=1; is_ret=1;  alu_op=`ALU_PASS_A; end // PC=R31

            // ---- Stack ----
            `OP_PUSH: begin is_push=1; mem_write=1; alu_op=`ALU_PASS_A; mem_size=`MEM_WORD; end
            `OP_POP:  begin is_pop=1;  mem_read=1; reg_write=1; mem_to_reg=1;
                           alu_op=`ALU_PASS_A; mem_size=`MEM_WORD; end

            // ---- Sistema ----
            `OP_NOP:  begin /* nada */   end
            `OP_HLT:  begin halt=1; is_system=1; end
            `OP_SYSCALL: begin is_system=1; trap_valid=1; trap_cause=`EXC_SYSCALL; end
            `OP_ERET:    begin is_jump=1; is_ret=1; is_system=1; alu_op=`ALU_PASS_A; end
            `OP_MFC:     begin reg_write=1; is_system=1; alu_op=`ALU_PASS_B; end
            `OP_MTC:     begin is_system=1; end
            `OP_FENCE:   begin is_system=1; end
            `OP_BREAK:   begin is_system=1; trap_valid=1; trap_cause=`EXC_BREAKPOINT; end

            default:  begin
                trap_valid=1; trap_cause=`EXC_ILLEGAL;    // instrução ilegal
            end
        endcase
    end

endmodule
