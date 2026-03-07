-- =============================================================================
-- arty_a7_top.vhd
-- Board-level top for Digilent Arty A7-35T / A7-100T
--
-- Resources used (estimated, ENABLE_TAGS=false, ENABLE_VM=false):
--   ~3 500 LUTs  |  ~4 000 FFs  |  8 RAMB36  |  fmax ~85 MHz on Artix-7-1
--
-- Memory map (AXI4-Lite, word-addressed inside each slave):
--   0x0000_0000 – 0x0000_7FFF  : Instruction ROM  (32 KB, BRAM)
--   0x8000_0000 – 0x8000_7FFF  : Data RAM          (32 KB, BRAM)
--   0xF000_0000 – 0xF000_000F  : UART (TX only, 115200-8N1)
--
-- External I/O (Arty A7 headers):
--   clk_i    ← E3  (100 MHz oscillator)
--   rst_ni   ← C2  (BTN0, active-low after inversion)
--   led_o[3:0] → H5,J5,T9,T10 (LD4–LD7, mapped to mem_wb.rd_data[3:0])
--   uart_tx_o → D10 (UART TXD on PMOD JA.1)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity arty_a7_top is
    port (
        -- 100 MHz board clock
        clk_i      : in  std_logic;
        -- BTN0 (active HIGH on board → inverted here to give active-LOW reset)
        btn_rst_i  : in  std_logic;

        -- RGB / plain LEDs (LD4–LD7)
        led_o      : out std_logic_vector(3 downto 0);

        -- UART TX (connect to USB-UART bridge or PMOD)
        uart_tx_o  : out std_logic
    );
end entity arty_a7_top;

architecture rtl of arty_a7_top is

    -- =========================================================================
    -- Clock / Reset
    -- =========================================================================
    signal rst_n    : std_logic;
    signal clk      : std_logic;

    -- =========================================================================
    -- AXI4-Lite buses (cpu_top master signals)
    -- =========================================================================
    -- Instruction memory (IM)
    signal im_araddr  : std_logic_vector(31 downto 0);
    signal im_arvalid : std_logic;
    signal im_arprot  : std_logic_vector(2 downto 0);
    signal im_arready : std_logic;
    signal im_rdata   : std_logic_vector(31 downto 0);
    signal im_rresp   : std_logic_vector(1 downto 0);
    signal im_rvalid  : std_logic;
    signal im_rready  : std_logic;

    -- Data memory (DM)
    signal dm_araddr  : std_logic_vector(31 downto 0);
    signal dm_arvalid : std_logic;
    signal dm_arprot  : std_logic_vector(2 downto 0);
    signal dm_arready : std_logic;
    signal dm_rdata   : std_logic_vector(31 downto 0);
    signal dm_rresp   : std_logic_vector(1 downto 0);
    signal dm_rvalid  : std_logic;
    signal dm_rready  : std_logic;
    signal dm_awaddr  : std_logic_vector(31 downto 0);
    signal dm_awvalid : std_logic;
    signal dm_awprot  : std_logic_vector(2 downto 0);
    signal dm_awready : std_logic;
    signal dm_wdata   : std_logic_vector(31 downto 0);
    signal dm_wstrb   : std_logic_vector(3 downto 0);
    signal dm_wvalid  : std_logic;
    signal dm_wready  : std_logic;
    signal dm_bresp   : std_logic_vector(1 downto 0);
    signal dm_bvalid  : std_logic;
    signal dm_bready  : std_logic;

    signal pc_dbg     : std_logic_vector(31 downto 0);

    -- =========================================================================
    -- CLINT AXI4-Lite slave bus (@ 0x0200_0000)
    -- =========================================================================
    signal clint_araddr   : std_logic_vector(31 downto 0);
    signal clint_arvalid  : std_logic;
    signal clint_arready  : std_logic;
    signal clint_rdata    : std_logic_vector(31 downto 0);
    signal clint_rresp    : std_logic_vector(1 downto 0);
    signal clint_rvalid   : std_logic;
    signal clint_rready   : std_logic;
    signal clint_awaddr   : std_logic_vector(31 downto 0);
    signal clint_awvalid  : std_logic;
    signal clint_awready  : std_logic;
    signal clint_wdata    : std_logic_vector(31 downto 0);
    signal clint_wstrb    : std_logic_vector(3 downto 0);
    signal clint_wvalid   : std_logic;
    signal clint_wready   : std_logic;
    signal clint_bresp    : std_logic_vector(1 downto 0);
    signal clint_bvalid   : std_logic;
    signal clint_bready   : std_logic;
    signal clint_timer_irq_s    : std_logic;
    signal clint_software_irq_s : std_logic;

    -- =========================================================================
    -- PLIC AXI4-Lite slave bus (@ 0x0C00_0000)
    -- =========================================================================
    signal plic_araddr    : std_logic_vector(31 downto 0);
    signal plic_arvalid   : std_logic;
    signal plic_arready   : std_logic;
    signal plic_rdata     : std_logic_vector(31 downto 0);
    signal plic_rresp     : std_logic_vector(1 downto 0);
    signal plic_rvalid    : std_logic;
    signal plic_rready    : std_logic;
    signal plic_awaddr    : std_logic_vector(31 downto 0);
    signal plic_awvalid   : std_logic;
    signal plic_awready   : std_logic;
    signal plic_wdata     : std_logic_vector(31 downto 0);
    signal plic_wstrb     : std_logic_vector(3 downto 0);
    signal plic_wvalid    : std_logic;
    signal plic_wready    : std_logic;
    signal plic_bresp     : std_logic_vector(1 downto 0);
    signal plic_bvalid    : std_logic;
    signal plic_bready    : std_logic;
    signal plic_irq_s     : std_logic;

    -- =========================================================================
    -- DM decoder: internal bus routed to DRAM/UART (after decode)
    -- =========================================================================
    signal mem_araddr     : std_logic_vector(31 downto 0);
    signal mem_arvalid    : std_logic;
    signal mem_arready    : std_logic;
    signal mem_rdata      : std_logic_vector(31 downto 0);
    signal mem_rresp      : std_logic_vector(1 downto 0);
    signal mem_rvalid     : std_logic;
    signal mem_rready     : std_logic;
    signal mem_awaddr     : std_logic_vector(31 downto 0);
    signal mem_awvalid    : std_logic;
    signal mem_awready    : std_logic;
    signal mem_wdata      : std_logic_vector(31 downto 0);
    signal mem_wstrb      : std_logic_vector(3 downto 0);
    signal mem_wvalid     : std_logic;
    signal mem_wready     : std_logic;
    signal mem_bresp      : std_logic_vector(1 downto 0);
    signal mem_bvalid     : std_logic;
    signal mem_bready     : std_logic;

    -- Address decode qualifiers (combinatorial from master address)
    signal ar_sel_clint   : std_logic;
    signal ar_sel_plic    : std_logic;
    signal aw_sel_clint   : std_logic;
    signal aw_sel_plic    : std_logic;
    -- Registered slave selection (valid when R/B data arrives)
    signal rd_sel_clint_r : std_logic := '0';
    signal rd_sel_plic_r  : std_logic := '0';
    signal wr_sel_clint_r : std_logic := '0';
    signal wr_sel_plic_r  : std_logic := '0';

    -- =========================================================================
    -- BRAM Instruction ROM  (32 KB = 8192 × 32-bit words)
    -- Initialise with your compiled RV32I binary.
    -- In Vivado: add a .coe / .mem file to the BRAM IP or use
    --   set_property -dict {INIT_FILE firmware.mem} [get_cells u_irom/...]
    -- =========================================================================
    constant IROM_DEPTH : integer := 8192;
    type irom_t is array (0 to IROM_DEPTH-1) of std_logic_vector(31 downto 0);

    -- *** Replace this with your firmware binary (readmemh format) ***
    signal irom : irom_t := (others => x"00000013"); -- NOP sled placeholder

    -- =========================================================================
    -- BRAM Data RAM  (32 KB = 8192 × 32-bit words)
    -- =========================================================================
    constant DRAM_DEPTH : integer := 8192;
    type dram_t is array (0 to DRAM_DEPTH-1) of std_logic_vector(31 downto 0);
    signal dram : dram_t := (others => (others => '0'));

    -- BRAM inference attributes (Xilinx)
    attribute ram_style : string;
    attribute ram_style of irom : signal is "block";
    attribute ram_style of dram : signal is "block";

    -- =========================================================================
    -- UART TX parameters  (100 MHz / 115200 baud = 868 cycles)
    -- =========================================================================
    constant UART_DIV : integer := 868;

    -- UART state
    type uart_state_t is (U_IDLE, U_START, U_DATA, U_STOP);
    signal uart_state    : uart_state_t := U_IDLE;
    signal uart_div_cnt  : integer range 0 to UART_DIV-1 := 0;
    signal uart_bit_cnt  : integer range 0 to 7 := 0;
    signal uart_shift    : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_tx_reg   : std_logic := '1';

    -- Write decode for UART region (addr[31:4] = 0xF000_000x)
    signal uart_wen      : std_logic;
    signal uart_wdata    : std_logic_vector(7 downto 0);
    signal uart_busy     : std_logic;

    -- =========================================================================
    -- AXI read/write state (1-cycle registered response for BRAM timing)
    -- =========================================================================
    signal im_rd_pending  : std_logic := '0';
    signal im_rd_addr_r   : integer range 0 to IROM_DEPTH-1 := 0;

    signal dm_rd_pending  : std_logic := '0';
    signal dm_rd_addr_r   : integer range 0 to DRAM_DEPTH-1 := 0;
    signal dm_wr_pending  : std_logic := '0';

begin

    -- =========================================================================
    -- Reset synchroniser (2-FF)
    -- =========================================================================
    clk   <= clk_i;
    rst_n <= not btn_rst_i;  -- BTN0 active HIGH → invert for active-LOW reset

    -- =========================================================================
    -- CPU Core
    -- =========================================================================
    u_cpu : entity work.cpu_top
        generic map (
            DATA_WIDTH => 32,
            RESET_ADDR => x"00000000",
            HART_ID    => 0
        )
        port map (
            clk_i          => clk,
            rst_ni         => rst_n,
            im_araddr_o    => im_araddr,
            im_arvalid_o   => im_arvalid,
            im_arprot_o    => im_arprot,
            im_arready_i   => im_arready,
            im_rdata_i     => im_rdata,
            im_rresp_i     => im_rresp,
            im_rvalid_i    => im_rvalid,
            im_rready_o    => im_rready,
            dm_araddr_o    => dm_araddr,
            dm_arvalid_o   => dm_arvalid,
            dm_arprot_o    => dm_arprot,
            dm_arready_i   => dm_arready,
            dm_rdata_i     => dm_rdata,
            dm_rresp_i     => dm_rresp,
            dm_rvalid_i    => dm_rvalid,
            dm_rready_o    => dm_rready,
            dm_awaddr_o    => dm_awaddr,
            dm_awvalid_o   => dm_awvalid,
            dm_awprot_o    => dm_awprot,
            dm_awready_i   => dm_awready,
            dm_wdata_o     => dm_wdata,
            dm_wstrb_o     => dm_wstrb,
            dm_wvalid_o    => dm_wvalid,
            dm_wready_i    => dm_wready,
            dm_bresp_i     => dm_bresp,
            dm_bvalid_i    => dm_bvalid,
            dm_bready_o    => dm_bready,
            irq_external_i => plic_irq_s,
            irq_timer_i    => clint_timer_irq_s,
            irq_software_i => clint_software_irq_s,
            pc_o           => pc_dbg
        );

    -- =========================================================================
    -- AXI DM Decoder
    -- Address map:
    --   0x0200_0000 – 0x0200_FFFF  CLINT  (bit[31:16] = 0x0200)
    --   0x0C00_0000 – 0x0CFF_FFFF  PLIC   (bit[31:24] = 0x0C)
    --   0x8000_0000 – 0x8000_7FFF  DRAM + UART (everything else)
    -- Single-master: only one outstanding transaction at a time.
    -- =========================================================================
    ar_sel_clint <= '1' when dm_araddr(31 downto 16) = x"0200" else '0';
    ar_sel_plic  <= '1' when dm_araddr(31 downto 24) = x"0C"   else '0';
    aw_sel_clint <= '1' when dm_awaddr(31 downto 16) = x"0200" else '0';
    aw_sel_plic  <= '1' when dm_awaddr(31 downto 24) = x"0C"   else '0';

    -- AR channel steering
    clint_araddr  <= dm_araddr;
    clint_arvalid <= dm_arvalid when ar_sel_clint = '1' else '0';
    plic_araddr   <= dm_araddr;
    plic_arvalid  <= dm_arvalid when ar_sel_plic  = '1' else '0';
    mem_araddr    <= dm_araddr;
    mem_arvalid   <= dm_arvalid when ar_sel_clint = '0' and ar_sel_plic = '0' else '0';

    dm_arready    <= clint_arready when ar_sel_clint = '1' else
                     plic_arready  when ar_sel_plic  = '1' else
                     mem_arready;

    -- AW + W channel steering
    clint_awaddr  <= dm_awaddr;
    clint_awvalid <= dm_awvalid when aw_sel_clint = '1' else '0';
    clint_wdata   <= dm_wdata;
    clint_wstrb   <= dm_wstrb;
    clint_wvalid  <= dm_wvalid when aw_sel_clint = '1' else '0';
    plic_awaddr   <= dm_awaddr;
    plic_awvalid  <= dm_awvalid when aw_sel_plic  = '1' else '0';
    plic_wdata    <= dm_wdata;
    plic_wstrb    <= dm_wstrb;
    plic_wvalid   <= dm_wvalid when aw_sel_plic  = '1' else '0';
    mem_awaddr    <= dm_awaddr;
    mem_awvalid   <= dm_awvalid when aw_sel_clint = '0' and aw_sel_plic = '0' else '0';
    mem_wdata     <= dm_wdata;
    mem_wstrb     <= dm_wstrb;
    mem_wvalid    <= dm_wvalid when aw_sel_clint = '0' and aw_sel_plic = '0' else '0';

    dm_awready    <= clint_awready when aw_sel_clint = '1' else
                     plic_awready  when aw_sel_plic  = '1' else
                     mem_awready;
    dm_wready     <= clint_wready  when aw_sel_clint = '1' else
                     plic_wready   when aw_sel_plic  = '1' else
                     mem_wready;

    -- Latch slave selection when AR / AW handshake completes
    dec_latch_proc : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                rd_sel_clint_r <= '0'; rd_sel_plic_r <= '0';
                wr_sel_clint_r <= '0'; wr_sel_plic_r <= '0';
            else
                if dm_arvalid = '1' and dm_arready = '1' then
                    rd_sel_clint_r <= ar_sel_clint;
                    rd_sel_plic_r  <= ar_sel_plic;
                end if;
                if dm_awvalid = '1' and dm_awready = '1' then
                    wr_sel_clint_r <= aw_sel_clint;
                    wr_sel_plic_r  <= aw_sel_plic;
                end if;
            end if;
        end if;
    end process dec_latch_proc;

    -- R channel mux (use registered selection)
    dm_rdata   <= clint_rdata  when rd_sel_clint_r = '1' else
                  plic_rdata   when rd_sel_plic_r  = '1' else
                  mem_rdata;
    dm_rresp   <= clint_rresp  when rd_sel_clint_r = '1' else
                  plic_rresp   when rd_sel_plic_r  = '1' else
                  mem_rresp;
    dm_rvalid  <= clint_rvalid when rd_sel_clint_r = '1' else
                  plic_rvalid  when rd_sel_plic_r  = '1' else
                  mem_rvalid;
    clint_rready <= dm_rready when rd_sel_clint_r = '1' else '0';
    plic_rready  <= dm_rready when rd_sel_plic_r  = '1' else '0';
    mem_rready   <= dm_rready when rd_sel_clint_r = '0' and rd_sel_plic_r = '0' else '0';

    -- B channel mux (use registered selection)
    dm_bresp   <= clint_bresp  when wr_sel_clint_r = '1' else
                  plic_bresp   when wr_sel_plic_r  = '1' else
                  mem_bresp;
    dm_bvalid  <= clint_bvalid when wr_sel_clint_r = '1' else
                  plic_bvalid  when wr_sel_plic_r  = '1' else
                  mem_bvalid;
    clint_bready <= dm_bready when wr_sel_clint_r = '1' else '0';
    plic_bready  <= dm_bready when wr_sel_plic_r  = '1' else '0';
    mem_bready   <= dm_bready when wr_sel_clint_r = '0' and wr_sel_plic_r = '0' else '0';

    -- =========================================================================
    -- CLINT instance (Core-Local INTerrupt controller)
    -- =========================================================================
    u_clint : entity work.clint
        generic map (DATA_WIDTH => 32)
        port map (
            clk_i          => clk,
            rst_ni         => rst_n,
            axi_araddr_i   => clint_araddr,
            axi_arvalid_i  => clint_arvalid,
            axi_arready_o  => clint_arready,
            axi_rdata_o    => clint_rdata,
            axi_rresp_o    => clint_rresp,
            axi_rvalid_o   => clint_rvalid,
            axi_rready_i   => clint_rready,
            axi_awaddr_i   => clint_awaddr,
            axi_awvalid_i  => clint_awvalid,
            axi_awready_o  => clint_awready,
            axi_wdata_i    => clint_wdata,
            axi_wstrb_i    => clint_wstrb,
            axi_wvalid_i   => clint_wvalid,
            axi_wready_o   => clint_wready,
            axi_bresp_o    => clint_bresp,
            axi_bvalid_o   => clint_bvalid,
            axi_bready_i   => clint_bready,
            timer_irq_o    => clint_timer_irq_s,
            software_irq_o => clint_software_irq_s
        );

    -- =========================================================================
    -- PLIC instance (Platform-Level Interrupt Controller)
    -- No external interrupt sources on Arty A7 by default; wired to '0'.
    -- Connect real peripherals here for production use.
    -- =========================================================================
    u_plic : entity work.plic
        generic map (
            DATA_WIDTH => 32,
            N_SOURCES  => 31,
            N_CONTEXTS => 1
        )
        port map (
            clk_i         => clk,
            rst_ni        => rst_n,
            axi_araddr_i  => plic_araddr,
            axi_arvalid_i => plic_arvalid,
            axi_arready_o => plic_arready,
            axi_rdata_o   => plic_rdata,
            axi_rresp_o   => plic_rresp,
            axi_rvalid_o  => plic_rvalid,
            axi_rready_i  => plic_rready,
            axi_awaddr_i  => plic_awaddr,
            axi_awvalid_i => plic_awvalid,
            axi_awready_o => plic_awready,
            axi_wdata_i   => plic_wdata,
            axi_wstrb_i   => plic_wstrb,
            axi_wvalid_i  => plic_wvalid,
            axi_wready_o  => plic_wready,
            axi_bresp_o   => plic_bresp,
            axi_bvalid_o  => plic_bvalid,
            axi_bready_i  => plic_bready,
            irq_sources_i => (others => '0'),
            irq_o         => plic_irq_s
        );

    -- =========================================================================
    -- Instruction ROM (BRAM, 32 KB)
    -- 1-cycle read latency registered response
    -- =========================================================================
    irom_proc : process(clk)
        variable idx : integer;
    begin
        if rising_edge(clk) then
            im_arready   <= '0';
            im_rvalid    <= '0';
            im_rd_pending <= '0';

            if rst_n = '0' then
                null;
            else
                -- Accept AR and register
                if im_arvalid = '1' and im_rd_pending = '0' then
                    im_arready   <= '1';
                    idx := to_integer(unsigned(im_araddr(14 downto 2)));
                    if idx < IROM_DEPTH then
                        im_rdata  <= irom(idx);
                    else
                        im_rdata  <= x"00000013"; -- NOP if out-of-bounds
                    end if;
                    im_rd_pending <= '1';
                end if;

                -- Deliver data one cycle after accept
                if im_rd_pending = '1' then
                    im_rvalid <= '1';
                    im_rresp  <= "00";
                end if;
            end if;
        end if;
    end process irom_proc;

    -- =========================================================================
    -- Data RAM + UART decode (BRAM, 32 KB + peripheral)
    -- Memory map (AXI addr):
    --   0x8000_0000..0x8000_7FFF  → DRAM word index [12:2]
    --   0xF000_0000..0xF000_000F  → UART (byte 0 = TX data)
    -- =========================================================================
    uart_wen   <= '1' when (mem_awvalid = '1' and mem_wvalid = '1' and
                            mem_awaddr(31 downto 4) = x"F000000") else '0';
    uart_wdata <= mem_wdata(7 downto 0);

    dram_proc : process(clk)
        variable idx  : integer;
        variable bidx : integer;
    begin
        if rising_edge(clk) then
            -- Defaults
            mem_arready <= '0';
            mem_rvalid  <= '0';
            mem_awready <= '0';
            mem_wready  <= '0';
            mem_bvalid  <= '0';
            mem_bresp   <= "00";
            mem_rresp   <= "00";

            if rst_n = '0' then
                dm_rd_pending <= '0';
            else
                -- ---- READ -----------------------------------------------
                if mem_arvalid = '1' and dm_rd_pending = '0' then
                    mem_arready   <= '1';
                    idx := to_integer(unsigned(mem_araddr(14 downto 2)));
                    if mem_araddr(31) = '1' and idx < DRAM_DEPTH then
                        mem_rdata  <= dram(idx);
                    else
                        mem_rdata  <= (others => '0');
                    end if;
                    dm_rd_pending <= '1';
                end if;

                if dm_rd_pending = '1' then
                    mem_rvalid    <= '1';
                    dm_rd_pending <= '0';
                end if;

                -- ---- WRITE (DRAM) ----------------------------------------
                if mem_awvalid = '1' and mem_wvalid = '1' then
                    mem_awready <= '1';
                    mem_wready  <= '1';
                    mem_bvalid  <= '1';
                    if mem_awaddr(31) = '1' then
                        idx := to_integer(unsigned(mem_awaddr(14 downto 2)));
                        if idx < DRAM_DEPTH then
                            for b in 0 to 3 loop
                                if mem_wstrb(b) = '1' then
                                    dram(idx)(b*8+7 downto b*8) <=
                                        mem_wdata(b*8+7 downto b*8);
                                end if;
                            end loop;
                        end if;
                    end if;
                    -- UART write handled separately below
                end if;
            end if;
        end if;
    end process dram_proc;

    -- =========================================================================
    -- UART TX — 8N1, 115200 baud @ 100 MHz
    -- Single-byte FIFO-less (busy bit returned via dm_rdata[0] at UART addr)
    -- =========================================================================
    uart_busy  <= '0' when uart_state = U_IDLE else '1';
    uart_tx_o  <= uart_tx_reg;

    uart_proc : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                uart_state   <= U_IDLE;
                uart_tx_reg  <= '1';
                uart_div_cnt <= 0;
                uart_bit_cnt <= 0;
            else
                case uart_state is
                    when U_IDLE =>
                        uart_tx_reg <= '1';
                        if uart_wen = '1' and uart_busy = '0' then
                            uart_shift   <= uart_wdata;
                            uart_div_cnt <= 0;
                            uart_state   <= U_START;
                        end if;

                    when U_START =>
                        uart_tx_reg <= '0';
                        if uart_div_cnt = UART_DIV - 1 then
                            uart_div_cnt <= 0;
                            uart_bit_cnt <= 0;
                            uart_state   <= U_DATA;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;

                    when U_DATA =>
                        uart_tx_reg <= uart_shift(uart_bit_cnt);
                        if uart_div_cnt = UART_DIV - 1 then
                            uart_div_cnt <= 0;
                            if uart_bit_cnt = 7 then
                                uart_state <= U_STOP;
                            else
                                uart_bit_cnt <= uart_bit_cnt + 1;
                            end if;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;

                    when U_STOP =>
                        uart_tx_reg <= '1';
                        if uart_div_cnt = UART_DIV - 1 then
                            uart_div_cnt <= 0;
                            uart_state   <= U_IDLE;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process uart_proc;

    -- =========================================================================
    -- LED output: PC[6:3] — shows coarse instruction progress on board LEDs
    -- =========================================================================
    led_o <= pc_dbg(6 downto 3);

end architecture rtl;
