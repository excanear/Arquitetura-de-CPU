-- =============================================================================
-- plic.vhd
-- RISC-V PLIC — Platform-Level Interrupt Controller
--
-- Standard PLIC memory map (relative to PLIC base at 0x0C00_0000):
--   0x000000 + 4*n  : priority[n]   (32-bit, lower 3 bits used, n=1..31)
--   0x001000        : pending[0]    (32-bit, read-only bitmask sources 0..31)
--   0x002000        : enable[0]     (32-bit, context 0 = M-mode hart 0)
--   0x200000        : threshold[0]  (32-bit, lower 3 bits)
--   0x200004        : claim/complete (32-bit, R=claim, W=complete)
--
-- Supports N_SRC interrupt sources (1..N_SRC, source 0 = no-interrupt).
-- One context: M-mode of hart 0.
-- Priority 0 = never interrupt.  Higher number = higher priority.
-- An interrupt fires when: (priority[n] > threshold) AND pending[n] AND enable[n]
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity plic is
    generic (
        DATA_WIDTH : integer := 32;
        N_SRC      : integer := 31   -- number of interrupt sources (1..N_SRC)
    );
    port (
        clk_i  : in  std_logic;
        rst_ni : in  std_logic;

        -- ---- Interrupt source inputs (pulse or level) --------------------
        irq_src_i   : in  std_logic_vector(N_SRC downto 1); -- source 1..N_SRC

        -- ---- AXI4-Lite Slave Interface -----------------------------------
        s_araddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_arvalid_i : in  std_logic;
        s_arready_o : out std_logic;
        s_rdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        s_rresp_o   : out std_logic_vector(1 downto 0);
        s_rvalid_o  : out std_logic;
        s_rready_i  : in  std_logic;

        s_awaddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_awvalid_i : in  std_logic;
        s_awready_o : out std_logic;
        s_wdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_wstrb_i   : in  std_logic_vector(3 downto 0);
        s_wvalid_i  : in  std_logic;
        s_wready_o  : out std_logic;
        s_bresp_o   : out std_logic_vector(1 downto 0);
        s_bvalid_o  : out std_logic;
        s_bready_i  : in  std_logic;

        -- ---- Interrupt output --------------------------------------------
        -- Active-high level: asserted while any interrupt[priority>threshold AND enabled] pending
        irq_o : out std_logic
    );
end entity plic;

architecture rtl of plic is

    -- =========================================================================
    -- PLIC registers
    -- =========================================================================
    type priority_array_t is array (0 to N_SRC) of unsigned(2 downto 0);
    type pending_array_t  is array (0 to N_SRC) of std_logic;

    signal priority_r  : priority_array_t := (others => (others => '0'));
    signal pending_r   : pending_array_t  := (others => '0');
    signal enable_r    : std_logic_vector(N_SRC downto 0) := (others => '0');
    signal threshold_r : unsigned(2 downto 0) := (others => '0');

    -- Claim/complete: stores the currently-claimed source ID (0 = none in service)
    signal in_service_r : integer range 0 to N_SRC := 0;

    -- AXI state
    signal rd_pending_r : std_logic := '0';
    signal rd_data_r    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Highest-priority pending+enabled interrupt (combinatorial)
    signal best_src    : integer range 0 to N_SRC;
    signal best_prio   : unsigned(2 downto 0);

begin

    -- =========================================================================
    -- Priority arbitration (combinatorial)
    -- Find the highest-priority source that is both pending, enabled, and
    -- has priority strictly greater than threshold.
    -- =========================================================================
    prio_arb : process(priority_r, pending_r, enable_r, threshold_r)
        variable b_src  : integer range 0 to N_SRC;
        variable b_prio : unsigned(2 downto 0);
    begin
        b_src  := 0;
        b_prio := (others => '0');
        for i in 1 to N_SRC loop
            if pending_r(i) = '1' and enable_r(i) = '1' and
               priority_r(i) > threshold_r and priority_r(i) > b_prio then
                b_src  := i;
                b_prio := priority_r(i);
            end if;
        end loop;
        best_src  <= b_src;
        best_prio <= b_prio;
    end process prio_arb;

    irq_o <= '1' when best_src /= 0 else '0';

    -- =========================================================================
    -- Pending bit latch: set by irq_src, cleared by complete
    -- =========================================================================
    pending_proc : process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_ni = '0' then
                pending_r <= (others => '0');
            else
                -- Set pending on rising edge of source (or level)
                for i in 1 to N_SRC loop
                    if irq_src_i(i) = '1' then
                        pending_r(i) <= '1';
                    end if;
                end loop;
            end if;
        end if;
    end process pending_proc;

    -- =========================================================================
    -- AXI read / write
    -- =========================================================================
    axi_proc : process(clk_i)
        variable addr22 : unsigned(21 downto 0);
        variable src    : integer range 0 to N_SRC;
        variable pend32 : std_logic_vector(31 downto 0);
        variable enb32  : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk_i) then
            s_arready_o <= '0';
            s_rvalid_o  <= '0';
            s_awready_o <= '0';
            s_wready_o  <= '0';
            s_bvalid_o  <= '0';
            s_rresp_o   <= "00";
            s_bresp_o   <= "00";

            if rst_ni = '0' then
                rd_pending_r <= '0';
                in_service_r <= 0;
                priority_r   <= (others => (others => '0'));
                enable_r     <= (others => '0');
                threshold_r  <= (others => '0');
            else

                -- ---- READ -----------------------------------------------
                if s_arvalid_i = '1' and rd_pending_r = '0' then
                    s_arready_o  <= '1';
                    addr22 := unsigned(s_araddr_i(21 downto 0));
                    rd_data_r <= (others => '0');

                    if addr22(21 downto 12) = x"00" & "00" then
                        -- Priority region 0x000000 - 0x000FFC: priority[n], n = addr[11:2]
                        src := to_integer(addr22(11 downto 2));
                        if src >= 1 and src <= N_SRC then
                            rd_data_r(2 downto 0) <= std_logic_vector(priority_r(src));
                        end if;
                    elsif addr22 = x"01000" then
                        -- 0x001000: pending bitmask
                        pend32 := (others => '0');
                        for i in 1 to N_SRC loop
                            pend32(i) := pending_r(i);
                        end loop;
                        rd_data_r <= pend32;
                    elsif addr22 = x"02000" then
                        -- 0x002000: enable bitmask context 0
                        enb32 := (others => '0');
                        for i in 1 to N_SRC loop
                            enb32(i) := enable_r(i);
                        end loop;
                        rd_data_r <= enb32;
                    elsif addr22 = x"200000" / 4 * 4 then
                        -- 0x200000: threshold
                        rd_data_r(2 downto 0) <= std_logic_vector(threshold_r);
                    elsif addr22 = (x"200004" / 4) * 4 then
                        -- 0x200004: claim — return best pending source, clear its pending
                        rd_data_r <= std_logic_vector(to_unsigned(best_src, DATA_WIDTH));
                        -- Claim: clear pending and record in-service
                        pending_r(best_src) <= '0';
                        in_service_r <= best_src;
                    end if;

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
                    addr22 := unsigned(s_awaddr_i(21 downto 0));

                    if addr22(21 downto 12) = x"00" & "00" then
                        -- Priority region
                        src := to_integer(addr22(11 downto 2));
                        if src >= 1 and src <= N_SRC then
                            if s_wstrb_i(0) = '1' then
                                priority_r(src) <= unsigned(s_wdata_i(2 downto 0));
                            end if;
                        end if;
                    elsif addr22 = x"02000" then
                        -- Enable bitmask
                        for i in 1 to N_SRC loop
                            if s_wstrb_i(i/8) = '1' then
                                enable_r(i) <= s_wdata_i(i);
                            end if;
                        end loop;
                    elsif addr22 = x"200000" then
                        -- Threshold
                        if s_wstrb_i(0) = '1' then
                            threshold_r <= unsigned(s_wdata_i(2 downto 0));
                        end if;
                    elsif addr22 = x"200004" then
                        -- Complete: clear in_service
                        in_service_r <= 0;
                    end if;
                end if;

            end if; -- rst_ni
        end if; -- rising_edge
    end process axi_proc;

end architecture rtl;
