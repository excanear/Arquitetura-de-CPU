-- =============================================================================
-- clint.vhd
-- RISC-V CLINT — Core-Local Interruptor
--
-- Implements the standard RISC-V CLINT memory map (1 hart):
--   BASE+0x0000        : msip[0]        (32-bit, bit0 = software interrupt)
--   BASE+0x4000        : mtimecmp[0] lo (32-bit)
--   BASE+0x4004        : mtimecmp[0] hi (32-bit)
--   BASE+0xBFF8        : mtime lo       (32-bit, free-running counter)
--   BASE+0xBFFC        : mtime hi       (32-bit)
--
-- AXI4-Lite slave interface (read + write).
-- Outputs: timer_irq_o (mtime >= mtimecmp), software_irq_o (msip[0]=1).
--
-- mtime increments every clock cycle (for simplicity; in a real system it
-- increments at a lower frequency via a prescaler, but that is configurable
-- by the platform firmware through mtime/mtimecmp).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clint is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk_i  : in  std_logic;
        rst_ni : in  std_logic;

        -- ---- AXI4-Lite Slave Interface ------------------------------------
        -- AR channel
        s_araddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_arvalid_i : in  std_logic;
        s_arready_o : out std_logic;
        -- R channel
        s_rdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        s_rresp_o   : out std_logic_vector(1 downto 0);
        s_rvalid_o  : out std_logic;
        s_rready_i  : in  std_logic;
        -- AW channel
        s_awaddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_awvalid_i : in  std_logic;
        s_awready_o : out std_logic;
        -- W channel
        s_wdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_wstrb_i   : in  std_logic_vector(3 downto 0);
        s_wvalid_i  : in  std_logic;
        s_wready_o  : out std_logic;
        -- B channel
        s_bresp_o   : out std_logic_vector(1 downto 0);
        s_bvalid_o  : out std_logic;
        s_bready_i  : in  std_logic;

        -- ---- Interrupt outputs -------------------------------------------
        timer_irq_o    : out std_logic; -- MTIP: mtime >= mtimecmp
        software_irq_o : out std_logic  -- MSIP: msip[0] = 1
    );
end entity clint;

architecture rtl of clint is

    -- =========================================================================
    -- CLINT registers
    -- =========================================================================
    signal mtime_r    : unsigned(63 downto 0) := (others => '0');
    signal mtimecmp_r : unsigned(63 downto 0) := (others => '1'); -- default: never fire
    signal msip_r     : std_logic := '0'; -- software interrupt pending

    -- =========================================================================
    -- AXI state (1-cycle registered response)
    -- =========================================================================
    signal rd_pending_r : std_logic := '0';
    signal rd_data_r    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal wr_resp_r    : std_logic := '0';

begin

    -- =========================================================================
    -- mtime free-running counter (increments every clock)
    -- =========================================================================
    mtime_proc : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_ni = '0' then
                mtime_r <= (others => '0');
            else
                mtime_r <= mtime_r + 1;
            end if;
        end if;
    end process mtime_proc;

    -- =========================================================================
    -- Interrupt generation (combinatorial)
    -- =========================================================================
    timer_irq_o    <= '1' when mtime_r >= mtimecmp_r else '0';
    software_irq_o <= msip_r;

    -- =========================================================================
    -- AXI read / write
    -- =========================================================================
    axi_proc : process(clk_i)
        variable addr16 : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk_i) then
            -- Defaults
            s_arready_o <= '0';
            s_rvalid_o  <= '0';
            s_awready_o <= '0';
            s_wready_o  <= '0';
            s_bvalid_o  <= '0';
            s_rresp_o   <= "00";
            s_bresp_o   <= "00";

            if rst_ni = '0' then
                rd_pending_r <= '0';
                wr_resp_r    <= '0';
                mtimecmp_r   <= (others => '1');
                msip_r       <= '0';
            else

                -- ---- READ -----------------------------------------------
                if s_arvalid_i = '1' and rd_pending_r = '0' then
                    s_arready_o  <= '1';
                    addr16 := s_araddr_i(15 downto 0);
                    case addr16 is
                        when x"0000" =>
                            rd_data_r <= (DATA_WIDTH-1 downto 1 => '0') & msip_r;
                        when x"4000" =>
                            rd_data_r <= std_logic_vector(mtimecmp_r(31 downto 0));
                        when x"4004" =>
                            rd_data_r <= std_logic_vector(mtimecmp_r(63 downto 32));
                        when x"BFF8" =>
                            rd_data_r <= std_logic_vector(mtime_r(31 downto 0));
                        when x"BFFC" =>
                            rd_data_r <= std_logic_vector(mtime_r(63 downto 32));
                        when others =>
                            rd_data_r <= (others => '0');
                    end case;
                    rd_pending_r <= '1';
                end if;

                if rd_pending_r = '1' then
                    s_rdata_o    <= rd_data_r;
                    s_rvalid_o   <= '1';
                    rd_pending_r <= '0';
                end if;

                -- ---- WRITE -----------------------------------------------
                if s_awvalid_i = '1' and s_wvalid_i = '1' then
                    s_awready_o <= '1';
                    s_wready_o  <= '1';
                    s_bvalid_o  <= '1';
                    addr16 := s_awaddr_i(15 downto 0);
                    case addr16 is
                        when x"0000" =>
                            if s_wstrb_i(0) = '1' then
                                msip_r <= s_wdata_i(0);
                            end if;
                        when x"4000" =>
                            for b in 0 to 3 loop
                                if s_wstrb_i(b) = '1' then
                                    mtimecmp_r(b*8+7 downto b*8) <=
                                        unsigned(s_wdata_i(b*8+7 downto b*8));
                                end if;
                            end loop;
                        when x"4004" =>
                            for b in 0 to 3 loop
                                if s_wstrb_i(b) = '1' then
                                    mtimecmp_r(32+b*8+7 downto 32+b*8) <=
                                        unsigned(s_wdata_i(b*8+7 downto b*8));
                                end if;
                            end loop;
                        when x"BFF8" =>
                            for b in 0 to 3 loop
                                if s_wstrb_i(b) = '1' then
                                    mtime_r(b*8+7 downto b*8) <=
                                        unsigned(s_wdata_i(b*8+7 downto b*8));
                                end if;
                            end loop;
                        when x"BFFC" =>
                            for b in 0 to 3 loop
                                if s_wstrb_i(b) = '1' then
                                    mtime_r(32+b*8+7 downto 32+b*8) <=
                                        unsigned(s_wdata_i(b*8+7 downto b*8));
                                end if;
                            end loop;
                        when others =>
                            null; -- writes to other addresses are ignored
                    end case;
                end if;

            end if; -- rst_ni
        end if; -- rising_edge
    end process axi_proc;

end architecture rtl;
