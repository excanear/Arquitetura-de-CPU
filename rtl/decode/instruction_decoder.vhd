-- =============================================================================
-- instruction_decoder.vhd
-- Decodificador de Instruções RV32I + RV32M
--
-- Responsável por:
--   - Decodificar o opcode, funct3 e funct7 da instrução
--   - Gerar todos os sinais de controle para os estágios subsequentes
--   - Detectar instruções ilegais
--   - Identificar tipo de imediato para o gerador
--
-- Nota: Este módulo é puramente combinacional.
--       Cobre todo o conjunto base RV32I (47 instruções)
--       e a extensão RV32M (MUL/DIV/REM – 8 instruções).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity instruction_decoder is
    port (
        -- Instrução do registrador IF/ID
        instr_i     : in  std_logic_vector(XLEN-1 downto 0);

        -- Campos extraídos da instrução (para conveniência dos módulos vizinhos)
        opcode_o    : out std_logic_vector(6 downto 0);
        rd_o        : out std_logic_vector(REG_ADDR_W-1 downto 0);
        rs1_o       : out std_logic_vector(REG_ADDR_W-1 downto 0);
        rs2_o       : out std_logic_vector(REG_ADDR_W-1 downto 0);
        funct3_o    : out std_logic_vector(2 downto 0);
        funct7_o    : out std_logic_vector(6 downto 0);

        -- Tipo de imediato (para immediate_generator)
        imm_type_o  : out imm_type_t;

        -- Sinais de controle decodificados
        ctrl_o      : out ctrl_signals_t
    );
end entity instruction_decoder;

architecture rtl of instruction_decoder is

    -- Campos locais para clareza
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);

begin

    -- =========================================================================
    -- Extração de campos da instrução
    -- =========================================================================
    opcode <= instr_i(OPCODE_HI  downto OPCODE_LO);
    funct3 <= instr_i(FUNCT3_HI  downto FUNCT3_LO);
    funct7 <= instr_i(FUNCT7_HI  downto FUNCT7_LO);

    opcode_o <= opcode;
    rd_o     <= instr_i(RD_HI    downto RD_LO);
    rs1_o    <= instr_i(RS1_HI   downto RS1_LO);
    rs2_o    <= instr_i(RS2_HI   downto RS2_LO);
    funct3_o <= funct3;
    funct7_o <= funct7;

    -- =========================================================================
    -- Decodificação principal – combinacional
    -- =========================================================================
    decode_proc : process(opcode, funct3, funct7)
        variable ctrl : ctrl_signals_t;
    begin
        -- ------------------------------------------------------------------
        -- Valores padrão (instrução NOP / inválida)
        -- ------------------------------------------------------------------
        ctrl        := CTRL_NOP;
        imm_type_o  <= IMM_NONE;

        case opcode is

            -- ------------------------------------------------------------------
            -- R-Type: RV32I base e RV32M (MUL/DIV/REM)
            -- Diferenciados por funct7:
            --   0000000 / 0100000 → RV32I (ADD/SUB, lógicos, shifts)
            --   0000001            → RV32M (multiplicação e divisão)
            -- ------------------------------------------------------------------
            when OPC_ALUR =>
                ctrl.reg_write  := '1';
                ctrl.alu_src    := ALUB_REG;
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.wb_sel     := WB_ALU;
                imm_type_o      <= IMM_NONE;

                if funct7 = "0000001" then
                    -- ---- RV32M ------------------------------------------
                    case funct3 is
                        when "000" => ctrl.alu_op := ALU_MUL;
                        when "001" => ctrl.alu_op := ALU_MULH;
                        when "010" => ctrl.alu_op := ALU_MULHSU;
                        when "011" => ctrl.alu_op := ALU_MULHU;
                        when "100" => ctrl.alu_op := ALU_DIV;
                        when "101" => ctrl.alu_op := ALU_DIVU;
                        when "110" => ctrl.alu_op := ALU_REM;
                        when "111" => ctrl.alu_op := ALU_REMU;
                        when others => ctrl.illegal := '1';
                    end case;
                else
                    -- ---- RV32I ------------------------------------------
                    case funct3 is
                        when F3_ADDSUB =>
                            if funct7(5) = '0' then ctrl.alu_op := ALU_ADD;
                            else                     ctrl.alu_op := ALU_SUB;
                            end if;
                        when F3_AND    => ctrl.alu_op := ALU_AND;
                        when F3_OR     => ctrl.alu_op := ALU_OR;
                        when F3_XOR    => ctrl.alu_op := ALU_XOR;
                        when F3_SLT    => ctrl.alu_op := ALU_SLT;
                        when F3_SLTU   => ctrl.alu_op := ALU_SLTU;
                        when F3_SLL    => ctrl.alu_op := ALU_SLL;
                        when F3_SRL    =>
                            if funct7(5) = '0' then ctrl.alu_op := ALU_SRL;
                            else                    ctrl.alu_op := ALU_SRA;
                            end if;
                        when others    => ctrl.illegal := '1';
                    end case;
                end if;

            -- ------------------------------------------------------------------
            -- I-Type ALU: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
            -- ------------------------------------------------------------------
            when OPC_ALUI =>
                ctrl.reg_write  := '1';
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.wb_sel     := WB_ALU;
                imm_type_o      <= IMM_I;

                case funct3 is
                    when F3_ADDSUB => ctrl.alu_op := ALU_ADD;
                    when F3_AND    => ctrl.alu_op := ALU_AND;
                    when F3_OR     => ctrl.alu_op := ALU_OR;
                    when F3_XOR    => ctrl.alu_op := ALU_XOR;
                    when F3_SLT    => ctrl.alu_op := ALU_SLT;
                    when F3_SLTU   => ctrl.alu_op := ALU_SLTU;
                    when F3_SLL    => ctrl.alu_op := ALU_SLL;
                    when F3_SRL    =>
                        if funct7(5) = '0' then ctrl.alu_op := ALU_SRL;
                        else                    ctrl.alu_op := ALU_SRA;
                        end if;
                    when others    => ctrl.illegal := '1';
                end case;

            -- ------------------------------------------------------------------
            -- Load: LB, LH, LW, LBU, LHU
            -- ------------------------------------------------------------------
            when OPC_LOAD =>
                ctrl.reg_write  := '1';
                ctrl.mem_read   := '1';
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.alu_op     := ALU_ADD; -- calcula endereço: rs1 + imm
                ctrl.wb_sel     := WB_MEM;
                ctrl.mem_size   := funct3;
                imm_type_o      <= IMM_I;

            -- ------------------------------------------------------------------
            -- Store: SB, SH, SW
            -- ------------------------------------------------------------------
            when OPC_STORE =>
                ctrl.mem_write  := '1';
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.alu_op     := ALU_ADD; -- calcula endereço: rs1 + imm
                ctrl.mem_size   := funct3;
                imm_type_o      <= IMM_S;

            -- ------------------------------------------------------------------
            -- Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
            -- ------------------------------------------------------------------
            when OPC_BRANCH =>
                ctrl.branch     := '1';
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.alu_op     := ALU_SUB; -- comparação na ALU (Z-flag / sinal)
                imm_type_o      <= IMM_B;

            -- ------------------------------------------------------------------
            -- JAL
            -- ------------------------------------------------------------------
            when OPC_JAL =>
                ctrl.jal        := '1';
                ctrl.reg_write  := '1';
                ctrl.wb_sel     := WB_PC4;
                imm_type_o      <= IMM_J;

            -- ------------------------------------------------------------------
            -- JALR
            -- ------------------------------------------------------------------
            when OPC_JALR =>
                ctrl.jalr       := '1';
                ctrl.reg_write  := '1';
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.alu_op     := ALU_ADD; -- destino: rs1 + imm (bit 0 := 0)
                ctrl.wb_sel     := WB_PC4;
                imm_type_o      <= IMM_I;

            -- ------------------------------------------------------------------
            -- LUI
            -- ------------------------------------------------------------------
            when OPC_LUI =>
                ctrl.reg_write  := '1';
                ctrl.alu_op     := ALU_LUI; -- passa imediato diretamente
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_REG; -- operando A não utilizado
                ctrl.wb_sel     := WB_ALU;
                imm_type_o      <= IMM_U;

            -- ------------------------------------------------------------------
            -- AUIPC
            -- ------------------------------------------------------------------
            when OPC_AUIPC =>
                ctrl.reg_write  := '1';
                ctrl.alu_op     := ALU_ADD; -- PC + imediato
                ctrl.alu_src    := ALUB_IMM;
                ctrl.alu_a_src  := ALUA_PC; -- operando A = PC
                ctrl.wb_sel     := WB_ALU;
                imm_type_o      <= IMM_U;

            -- ------------------------------------------------------------------
            -- FENCE / FENCE.I
            -- ------------------------------------------------------------------
            when OPC_FENCE =>
                ctrl.fence      := '1';
                imm_type_o      <= IMM_NONE;

            -- ------------------------------------------------------------------
            -- SYSTEM: ECALL, EBREAK, MRET, SRET, CSR*
            -- ------------------------------------------------------------------
            when OPC_SYSTEM =>
                case funct3 is
                    when "000" =>
                    -- ECALL / EBREAK / MRET / SRET / SFENCE.VMA
                    if funct7 = "0001001" then
                        -- SFENCE.VMA
                        ctrl.sfence_vma := '1';
                    elsif instr_i(31 downto 20) = x"000" then
                        ctrl.ecall  := '1';
                    elsif instr_i(31 downto 20) = x"001" then
                        ctrl.ebreak := '1';
                    elsif instr_i(31 downto 20) = x"102" then
                        -- SRET: retorno de trap S-mode
                        ctrl.sret   := '1';
                    elsif instr_i(31 downto 20) = x"302" then
                        -- MRET: retorno de trap M-mode
                        ctrl.mret   := '1';
                    else
                        ctrl.illegal := '1';
                    end if;
                    when "001" | "010" | "011" |
                         "101" | "110" | "111" =>
                        -- CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
                        ctrl.csr_access := '1';
                        ctrl.reg_write  := '1';
                        imm_type_o      <= IMM_I;
                    when others =>
                        ctrl.illegal := '1';
                end case;

            -- ------------------------------------------------------------------
            -- RV32A: Atomic Memory Operations (AMO)
            -- Format: funct5[31:27] | aq[26] | rl[25] | rs2[24:20] | rs1[19:15]
            --         | "010"[14:12] | rd[11:7] | 0101111
            -- ------------------------------------------------------------------
            when OPC_AMO =>
                ctrl.amo        := '1';
                ctrl.reg_write  := '1';
                ctrl.mem_read   := '1';   -- AMO reads memory (for LR, AMOADD, …)
                ctrl.wb_sel     := WB_MEM;
                ctrl.alu_op     := ALU_ADD;
                ctrl.alu_src    := ALUB_IMM;  -- imm=0 so ALU computes rs1+0=addr
                ctrl.alu_a_src  := ALUA_REG;
                ctrl.amo_funct5 := instr_i(31 downto 27);
                imm_type_o      <= IMM_NONE;

                case instr_i(31 downto 27) is
                    when "00010" =>           -- LR.W
                        ctrl.amo_is_lr := '1';
                    when "00011" =>           -- SC.W
                        ctrl.amo_is_sc  := '1';
                        ctrl.mem_write  := '1';   -- SC may write memory
                    when "00000" | "00001" |  -- AMOADD, AMOSWAP
                         "00100" | "01100" |  -- AMOXOR, AMOAND
                         "01000" | "10000" |  -- AMOOR,  AMOMIN
                         "10100" | "11000" |  -- AMOMAX, AMOMINU
                         "11100" =>           -- AMOMAXU
                        ctrl.mem_write := '1';    -- Always read-modify-write
                    when others =>
                        ctrl.illegal := '1';
                end case;

            when others =>
                ctrl.illegal := '1';

        end case;

        ctrl_o <= ctrl;
    end process decode_proc;

end architecture rtl;
