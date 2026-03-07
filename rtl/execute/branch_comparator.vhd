-- =============================================================================
-- branch_comparator.vhd
-- Comparador de Branch Condicional – RV32I
--
-- Decide se um branch é tomado com base em funct3 e nos valores rs1/rs2.
-- Utiliza os sinais de flag vindos da ALU (zero, sign, overflow, carry) ou
-- realiza sua própria comparação direta (mais eficiente em síntese).
--
-- Instruções suportadas:
--   BEQ  (000): branch se rs1 == rs2
--   BNE  (001): branch se rs1 != rs2
--   BLT  (100): branch se rs1 <  rs2  (signed)
--   BGE  (101): branch se rs1 >= rs2  (signed)
--   BLTU (110): branch se rs1 <  rs2  (unsigned)
--   BGEU (111): branch se rs1 >= rs2  (unsigned)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity branch_comparator is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        rs1_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        rs2_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        funct3_i    : in  std_logic_vector(2 downto 0);
        branch_en_i : in  std_logic;  -- '1' se instrução é um branch (ctrl.branch)

        branch_taken_o : out std_logic  -- '1' se branch deve ser tomado
    );
end entity branch_comparator;

architecture rtl of branch_comparator is
begin

    cmp_proc : process(rs1_i, rs2_i, funct3_i, branch_en_i)
        variable a_s : signed(DATA_WIDTH-1 downto 0);
        variable b_s : signed(DATA_WIDTH-1 downto 0);
        variable a_u : unsigned(DATA_WIDTH-1 downto 0);
        variable b_u : unsigned(DATA_WIDTH-1 downto 0);
        variable taken : boolean;
    begin
        a_s   := signed(rs1_i);
        b_s   := signed(rs2_i);
        a_u   := unsigned(rs1_i);
        b_u   := unsigned(rs2_i);
        taken := false;

        if branch_en_i = '1' then
            case funct3_i is
                when F3_BEQ  => taken := (a_u = b_u);
                when F3_BNE  => taken := (a_u /= b_u);
                when F3_BLT  => taken := (a_s < b_s);
                when F3_BGE  => taken := (a_s >= b_s);
                when F3_BLTU => taken := (a_u < b_u);
                when F3_BGEU => taken := (a_u >= b_u);
                when others  => taken := false;
            end case;
        end if;

        if taken then
            branch_taken_o <= '1';
        else
            branch_taken_o <= '0';
        end if;
    end process cmp_proc;

end architecture rtl;
