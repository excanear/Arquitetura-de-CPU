-- =============================================================================
-- immediate_generator.vhd
-- Gerador de Imediatos RV32I
--
-- Responsável por:
--   - Extrair e montar o valor imediato de instrução conforme o tipo
--   - Realizar extensão de sinal para XLEN bits
--
-- Formatos suportados:
--   I-type: [31:20] → imm[11:0]
--   S-type: [31:25] + [11:7] → imm[11:5] + imm[4:0]
--   B-type: [31] + [7] + [30:25] + [11:8] + '0' → imm[12:1]
--   U-type: [31:12] << 12 → imm[31:12] (zero nos 12 LSBs)
--   J-type: [31] + [19:12] + [20] + [30:21] + '0' → imm[20:1]
--
-- Referência: RISC-V Spec v2.2, Capítulo 2.3 (Immediate Encoding Variants)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity immediate_generator is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        instr_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        imm_type_i : in  imm_type_t;
        imm_o      : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity immediate_generator;

architecture rtl of immediate_generator is
begin

    imm_gen : process(instr_i, imm_type_i)
        variable imm_raw : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        imm_raw := (others => '0');

        case imm_type_i is

            -- ------------------------------------------------------------------
            -- I-Type: ADDI, LW, JALR, CSRRW …
            -- imm[11:0] = instr[31:20], sign-extended
            -- ------------------------------------------------------------------
            when IMM_I =>
                imm_raw(11 downto 0)   := instr_i(31 downto 20);
                imm_raw(DATA_WIDTH-1 downto 12) := (others => instr_i(31));

            -- ------------------------------------------------------------------
            -- S-Type: SW, SH, SB
            -- imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
            -- ------------------------------------------------------------------
            when IMM_S =>
                imm_raw(11 downto 5)   := instr_i(31 downto 25);
                imm_raw(4  downto 0)   := instr_i(11 downto  7);
                imm_raw(DATA_WIDTH-1 downto 12) := (others => instr_i(31));

            -- ------------------------------------------------------------------
            -- B-Type: BEQ, BNE, BLT …
            -- imm[12]  = instr[31]
            -- imm[11]  = instr[7]
            -- imm[10:5]= instr[30:25]
            -- imm[4:1] = instr[11:8]
            -- imm[0]   = '0'
            -- ------------------------------------------------------------------
            when IMM_B =>
                imm_raw(0)             := '0';
                imm_raw(4  downto 1)   := instr_i(11 downto  8);
                imm_raw(10 downto 5)   := instr_i(30 downto 25);
                imm_raw(11)            := instr_i(7);
                imm_raw(12)            := instr_i(31);
                imm_raw(DATA_WIDTH-1 downto 13) := (others => instr_i(31));

            -- ------------------------------------------------------------------
            -- U-Type: LUI, AUIPC
            -- imm[31:12] = instr[31:12], imm[11:0] = 0
            -- ------------------------------------------------------------------
            when IMM_U =>
                imm_raw(11 downto  0)  := (others => '0');
                imm_raw(31 downto 12)  := instr_i(31 downto 12);

            -- ------------------------------------------------------------------
            -- J-Type: JAL
            -- imm[20]   = instr[31]
            -- imm[10:1] = instr[30:21]
            -- imm[11]   = instr[20]
            -- imm[19:12]= instr[19:12]
            -- imm[0]    = '0'
            -- ------------------------------------------------------------------
            when IMM_J =>
                imm_raw(0)             := '0';
                imm_raw(10 downto  1)  := instr_i(30 downto 21);
                imm_raw(11)            := instr_i(20);
                imm_raw(19 downto 12)  := instr_i(19 downto 12);
                imm_raw(20)            := instr_i(31);
                imm_raw(DATA_WIDTH-1 downto 21) := (others => instr_i(31));

            when IMM_NONE =>
                imm_raw := (others => '0');

            when others =>
                imm_raw := (others => '0');

        end case;

        imm_o <= imm_raw;
    end process imm_gen;

end architecture rtl;
