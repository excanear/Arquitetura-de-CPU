-- =============================================================================
-- alu.vhd
-- Unidade Lógico-Aritmética – RV32I + RV32M
--
-- Operações suportadas (conforme alu_op_t em cpu_pkg):
--   RV32I : ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA, LUI (pass B), NOP
--   RV32M : MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
--
-- Flags de saída:
--   zero_o  : resultado == 0           (usado em comparações BEQ/BNE)
--   sign_o  : bit de sinal do resultado (bit DATA_WIDTH-1)
--   ovf_o   : overflow aritmético com sinal (ADD/SUB)
--   carry_o : carry-out da adição sem sinal
--
-- Notas RV32M:
--   - DIV e REM por zero: resultado definido pelo spec (DIV→-1, REM→dividendo)
--   - Overflow em DIV signed (INT_MIN / -1): resultado definido pelo spec (→ INT_MIN)
--   - Operações de divisão são combinacionais – em síntese para FPGA substituir
--     por um divisor iterativo ou DSP para melhor timing.
--
-- O módulo é puramente combinacional e sintetizável.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity alu is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        operand_a_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        operand_b_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        alu_op_i    : in  alu_op_t;

        result_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        zero_o      : out std_logic;  -- result == 0
        sign_o      : out std_logic;  -- result[MSB]
        ovf_o       : out std_logic;  -- signed overflow
        carry_o     : out std_logic   -- unsigned carry
    );
end entity alu;

architecture rtl of alu is

    signal result_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal carry_s   : std_logic;
    signal ovf_s     : std_logic;

begin

    alu_proc : process(operand_a_i, operand_b_i, alu_op_i)
        variable a_u    : unsigned(DATA_WIDTH   downto 0); -- 1 bit extra para carry
        variable b_u    : unsigned(DATA_WIDTH   downto 0);
        variable sum    : unsigned(DATA_WIDTH   downto 0);
        variable a_s    : signed(DATA_WIDTH-1   downto 0);
        variable b_s    : signed(DATA_WIDTH-1   downto 0);
        variable shamt  : integer range 0 to DATA_WIDTH-1;
        -- RV32M: produtos e quocientes de 64 bits
        variable prod_ss : signed(2*DATA_WIDTH-1   downto 0); -- signed×signed
        variable prod_su : signed(2*DATA_WIDTH-1   downto 0); -- signed×unsigned (cast)
        variable prod_uu : unsigned(2*DATA_WIDTH-1 downto 0); -- unsigned×unsigned
        variable div_s   : signed(DATA_WIDTH-1   downto 0);
        variable div_u   : unsigned(DATA_WIDTH-1 downto 0);
        variable rem_s   : signed(DATA_WIDTH-1   downto 0);
        variable rem_u   : unsigned(DATA_WIDTH-1 downto 0);
        constant INT_MIN : signed(DATA_WIDTH-1 downto 0) :=
            '1' & (DATA_WIDTH-2 downto 0 => '0'); -- 0x80000000
    begin
        -- Conversões auxiliares
        a_u   := unsigned('0' & operand_a_i);
        b_u   := unsigned('0' & operand_b_i);
        a_s   := signed(operand_a_i);
        b_s   := signed(operand_b_i);
        shamt := to_integer(unsigned(operand_b_i(4 downto 0)));

        result_s <= (others => '0');
        carry_s  <= '0';
        ovf_s    <= '0';

        case alu_op_i is

            when ALU_ADD =>
                sum      := a_u + b_u;
                result_s <= std_logic_vector(sum(DATA_WIDTH-1 downto 0));
                carry_s  <= sum(DATA_WIDTH);
                -- Signed overflow: (+)+(+)=(−) ou (−)+(−)=(+)
                ovf_s    <= (not operand_a_i(DATA_WIDTH-1) and
                             not operand_b_i(DATA_WIDTH-1) and
                             sum(DATA_WIDTH-1)) or
                            (operand_a_i(DATA_WIDTH-1) and
                             operand_b_i(DATA_WIDTH-1) and
                             not sum(DATA_WIDTH-1));

            when ALU_SUB =>
                sum      := a_u - b_u;
                result_s <= std_logic_vector(sum(DATA_WIDTH-1 downto 0));
                carry_s  <= sum(DATA_WIDTH); -- borrow
                -- Signed overflow: (+)−(−)=(−) ou (−)−(+)=(+)
                ovf_s    <= (not operand_a_i(DATA_WIDTH-1) and
                             operand_b_i(DATA_WIDTH-1) and
                             sum(DATA_WIDTH-1)) or
                            (operand_a_i(DATA_WIDTH-1) and
                             not operand_b_i(DATA_WIDTH-1) and
                             not sum(DATA_WIDTH-1));

            when ALU_AND =>
                result_s <= operand_a_i and operand_b_i;

            when ALU_OR =>
                result_s <= operand_a_i or operand_b_i;

            when ALU_XOR =>
                result_s <= operand_a_i xor operand_b_i;

            when ALU_SLT =>
                -- Set Less Than (com sinal)
                if a_s < b_s then
                    result_s <= std_logic_vector(to_unsigned(1, DATA_WIDTH));
                else
                    result_s <= (others => '0');
                end if;

            when ALU_SLTU =>
                -- Set Less Than (sem sinal)
                if a_u(DATA_WIDTH-1 downto 0) < b_u(DATA_WIDTH-1 downto 0) then
                    result_s <= std_logic_vector(to_unsigned(1, DATA_WIDTH));
                else
                    result_s <= (others => '0');
                end if;

            when ALU_SLL =>
                result_s <= std_logic_vector(shift_left(unsigned(operand_a_i), shamt));

            when ALU_SRL =>
                result_s <= std_logic_vector(shift_right(unsigned(operand_a_i), shamt));

            when ALU_SRA =>
                result_s <= std_logic_vector(shift_right(signed(operand_a_i), shamt));

            when ALU_LUI =>
                -- Passa operando B diretamente (imediato U-type já está em posição)
                result_s <= operand_b_i;

            -- ================================================================
            -- RV32M: Multiplicação
            -- ================================================================
            when ALU_MUL =>
                -- Produto signed×signed – retorna os 32 bits baixos
                prod_ss  := a_s * b_s;
                result_s <= std_logic_vector(prod_ss(DATA_WIDTH-1 downto 0));

            when ALU_MULH =>
                -- Produto signed×signed – retorna os 32 bits altos
                prod_ss  := a_s * b_s;
                result_s <= std_logic_vector(prod_ss(2*DATA_WIDTH-1 downto DATA_WIDTH));

            when ALU_MULHSU =>
                -- Produto signed×unsigned – bits altos
                -- Realizado zero-extendendo B e calculando com sinal no produto
                prod_su  := a_s * signed('0' & operand_b_i);
                result_s <= std_logic_vector(prod_su(2*DATA_WIDTH-1 downto DATA_WIDTH));

            when ALU_MULHU =>
                -- Produto unsigned×unsigned – bits altos
                prod_uu  := unsigned(operand_a_i) * unsigned(operand_b_i);
                result_s <= std_logic_vector(prod_uu(2*DATA_WIDTH-1 downto DATA_WIDTH));

            -- ================================================================
            -- RV32M: Divisão e Resto
            -- ================================================================
            when ALU_DIV =>
                -- Divisão inteira com sinal
                -- Casos especiais conforme RISC-V spec:
                --   Divisão por zero       → resultado = -1 (todos os bits 1)
                --   INT_MIN / -1 (overflow) → resultado = INT_MIN
                if b_s = 0 then
                    result_s <= (others => '1');
                elsif a_s = INT_MIN and b_s = -1 then
                    result_s <= std_logic_vector(INT_MIN);
                else
                    div_s    := a_s / b_s;
                    result_s <= std_logic_vector(div_s);
                end if;

            when ALU_DIVU =>
                -- Divisão inteira sem sinal
                -- Divisão por zero → resultado = 2^32 - 1 (todos os bits 1)
                if b_u(DATA_WIDTH-1 downto 0) = 0 then
                    result_s <= (others => '1');
                else
                    div_u    := unsigned(operand_a_i) / unsigned(operand_b_i);
                    result_s <= std_logic_vector(div_u);
                end if;

            when ALU_REM =>
                -- Resto inteiro com sinal
                -- Divisão por zero → resultado = dividendo
                -- INT_MIN / -1    → resultado = 0 (resto)
                if b_s = 0 then
                    result_s <= operand_a_i;
                elsif a_s = INT_MIN and b_s = -1 then
                    result_s <= (others => '0');
                else
                    rem_s    := a_s rem b_s;
                    result_s <= std_logic_vector(rem_s);
                end if;

            when ALU_REMU =>
                -- Resto inteiro sem sinal
                -- Divisão por zero → resultado = dividendo
                if b_u(DATA_WIDTH-1 downto 0) = 0 then
                    result_s <= operand_a_i;
                else
                    rem_u    := unsigned(operand_a_i) rem unsigned(operand_b_i);
                    result_s <= std_logic_vector(rem_u);
                end if;

            when others => -- ALU_NOP
                result_s <= (others => '0');

        end case;
    end process alu_proc;

    -- =========================================================================
    -- Atribuição de saídas
    -- =========================================================================
    result_o <= result_s;
    zero_o   <= '1' when unsigned(result_s) = 0 else '0';
    sign_o   <= result_s(DATA_WIDTH-1);
    ovf_o    <= ovf_s;
    carry_o  <= carry_s;

end architecture rtl;
