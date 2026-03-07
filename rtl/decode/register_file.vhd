-- =============================================================================
-- register_file.vhd
-- Banco de Registradores RV32I (x0 – x31)
--
-- Características:
--   - 32 registradores de XLEN bits cada
--   - x0 está fixo em zero (hardwired zero) – leituras retornam 0, escritas
--     em x0 são ignoradas (conformidade com a especificação RISC-V)
--   - 2 portas de leitura combinacionais (rs1, rs2)
--   - 1 porta de escrita síncrona (no rising_edge do clock)
--   - Write-after-read: se rd = rs no mesmo ciclo, a leitura retorna o valor
--     já escrito (forwarding interno, configurável por generic)
--   - Generic ASYNC_READ: quando TRUE, leituras são combinacionais puras;
--     quando FALSE, leituras são registradas (útil para FPGAs com BRAM)
--
-- Nota de pipeline:
--   A escrita ocorre no primeiro sub-ciclo do WB e a leitura ocorre no
--   segundo sub-ciclo do ID (write-first). Com o generic ASYNC_READ=true
--   isso não é necessário pois a leitura reflete a escrita imediatamente.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity register_file is
    generic (
        DATA_WIDTH     : integer := XLEN;
        ADDR_WIDTH     : integer := REG_ADDR_W;
        -- TRUE  = leitura combinacional (padrão para ASICs e simulação)
        -- FALSE = leitura registrada (otimizado para BRAM em FPGA)
        ASYNC_READ     : boolean := true;
        -- TRUE  = forwarding interno (rd→rs no mesmo ciclo)
        INTERNAL_FWD   : boolean := true
    );
    port (
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic;

        -- Porta de leitura 1 (RS1)
        rs1_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        rs1_data_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Porta de leitura 2 (RS2)
        rs2_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        rs2_data_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Porta de escrita (RD) – vem do estágio Writeback
        rd_addr_i   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        rd_data_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_we_i     : in  std_logic  -- Write Enable
    );
end entity register_file;

architecture rtl of register_file is

    -- =========================================================================
    -- Array de registradores
    -- =========================================================================
    type reg_array_t is array (0 to (2**ADDR_WIDTH)-1)
        of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal regs : reg_array_t := (others => (others => '0'));

begin

    -- =========================================================================
    -- Porta de Escrita (síncrona, ativa na borda de subida)
    -- =========================================================================
    write_port : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            regs <= (others => (others => '0'));
        elsif rising_edge(clk_i) then
            if rd_we_i = '1' and unsigned(rd_addr_i) /= 0 then
                regs(to_integer(unsigned(rd_addr_i))) <= rd_data_i;
            end if;
        end if;
    end process write_port;

    -- =========================================================================
    -- Portas de Leitura
    -- =========================================================================
    gen_async_read : if ASYNC_READ generate

        -- Leitura combinacional com forwarding interno opcional
        read_comb : process(regs, rs1_addr_i, rs2_addr_i,
                            rd_addr_i, rd_data_i, rd_we_i)
        begin
            -- RS1
            if unsigned(rs1_addr_i) = 0 then
                rs1_data_o <= (others => '0'); -- x0 sempre zero
            elsif INTERNAL_FWD and
                  rd_we_i = '1' and rs1_addr_i = rd_addr_i then
                rs1_data_o <= rd_data_i;       -- forwarding write→read
            else
                rs1_data_o <= regs(to_integer(unsigned(rs1_addr_i)));
            end if;

            -- RS2
            if unsigned(rs2_addr_i) = 0 then
                rs2_data_o <= (others => '0');
            elsif INTERNAL_FWD and
                  rd_we_i = '1' and rs2_addr_i = rd_addr_i then
                rs2_data_o <= rd_data_i;
            else
                rs2_data_o <= regs(to_integer(unsigned(rs2_addr_i)));
            end if;
        end process read_comb;

    end generate gen_async_read;

    gen_sync_read : if not ASYNC_READ generate

        -- Leitura registrada (para BRAM em FPGAs)
        read_seq : process(clk_i)
        begin
            if rising_edge(clk_i) then
                if unsigned(rs1_addr_i) = 0 then
                    rs1_data_o <= (others => '0');
                else
                    rs1_data_o <= regs(to_integer(unsigned(rs1_addr_i)));
                end if;

                if unsigned(rs2_addr_i) = 0 then
                    rs2_data_o <= (others => '0');
                else
                    rs2_data_o <= regs(to_integer(unsigned(rs2_addr_i)));
                end if;
            end if;
        end process read_seq;

    end generate gen_sync_read;

end architecture rtl;
