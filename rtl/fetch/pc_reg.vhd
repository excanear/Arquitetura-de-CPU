-- =============================================================================
-- pc_reg.vhd
-- Registrador de Program Counter (PC)
--
-- Responsável por:
--   - Manter o valor atual do PC
--   - Avançar para PC+4 em ciclo normal
--   - Aceitar novo valor em caso de branch/jump resolvido
--   - Aceitar sinal de stall (congela PC)
--   - Aceitar sinal de flush (recarrega PC com valor externo)
--
-- Este módulo é puramente sequencial. A lógica de seleção do próximo PC
-- é feita no branch_handler.vhd, que alimenta next_pc_i.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity pc_reg is
    generic (
        DATA_WIDTH : integer := XLEN;
        RESET_ADDR : std_logic_vector(XLEN-1 downto 0) := PC_RESET
    );
    port (
        -- Controle global
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic; -- Reset ativo-baixo

        -- Sinal de stall: quando '1', PC não avança
        stall_i     : in  std_logic;

        -- Flush: força o PC para next_pc_i (usado em branch taken / misprediction)
        flush_i     : in  std_logic;

        -- Próximo PC selecionado externamente (pelo branch_handler)
        next_pc_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Valor atual do PC (saída para o estágio de fetch)
        pc_o        : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- PC + 4 calculado combinacionalmente (conveniente para lógica de fetch)
        pc_plus4_o  : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity pc_reg;

architecture rtl of pc_reg is

    signal pc_r : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    -- =========================================================================
    -- Lógica sequencial do PC
    -- =========================================================================
    pc_seq : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            -- Em reset, carrega endereço de boot
            pc_r <= RESET_ADDR;
        elsif rising_edge(clk_i) then
            if flush_i = '1' then
                -- Branch ou jump tomado: carrega endereço de destino
                pc_r <= next_pc_i;
            elsif stall_i = '0' then
                -- Operação normal: avança para próximo PC
                pc_r <= next_pc_i;
            end if;
            -- Se stall_i='1' e flush_i='0': PC mantido (hazard de dados/controle)
        end if;
    end process pc_seq;

    -- =========================================================================
    -- Saídas combinacionais
    -- =========================================================================
    pc_o       <= pc_r;
    pc_plus4_o <= std_logic_vector(unsigned(pc_r) + 4);

end architecture rtl;
