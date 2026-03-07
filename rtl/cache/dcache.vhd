-- =============================================================================
-- dcache.vhd
-- Data Cache – Direct-Mapped, Write-Back + Write-Allocate
-- Interface AXI4-Lite ↔ AXI4-Lite (igual ao icache)
--
-- Arquitetura:
--   ┌─────────────────────────────────────────────────────────────┐
--   │  CPU (LSU/memory_stage AXI master)                          │
--   │    cpu_ar*/cpu_r*  ←→ [dcache slave – Read port ]           │
--   │    cpu_aw*/cpu_w*/cpu_b* ←→ [dcache slave – Write port]     │
--   │                              ↕  cache array (R/W)           │
--   │    mem_ar*/mem_r*  ←→ [external DM slave – Fill/Read]       │
--   │    mem_aw*/mem_w*/mem_b* ←→ [external DM slave – Writeback] │
--   └─────────────────────────────────────────────────────────────┘
--
-- Parâmetros padrão (ENABLE_TAGS=true):
--   - N_LINES     = 256 sets, LINE_WORDS = 4 palavras (16B por linha)
--   - Direct-mapped (1-way), TAG = addr[31:12], INDEX = addr[11:4]
--   - Write-back: dirty bit por linha; writeback ao substituir linha suja
--   - Write-allocate: miss em escrita → carrega linha antes de escrever
--
-- ENABLE_TAGS=false (passthrough):
--   - AXI-to-AXI wire-through; sem memória interna
--
-- FENCE/FENCE.I (flush_i='1'):
--   - Invalida todas as linhas (e enfileira writeback das sujas – simplificado
--     nesta versão: descarta dirty bits junto com valid bits)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity dcache is
    generic (
        DATA_WIDTH   : integer := XLEN;
        N_LINES      : integer := 256;
        LINE_WORDS   : integer := 4;
        ENABLE_TAGS  : boolean := true
    );
    port (
        clk_i        : in  std_logic;
        rst_ni       : in  std_logic;

        -- ---- Interface AXI4-Lite Slave (do LSU / memory_stage) ----------
        -- Read channel
        cpu_araddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_arvalid_i : in  std_logic;
        cpu_arprot_i  : in  std_logic_vector(2 downto 0);
        cpu_arready_o : out std_logic;
        cpu_rdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_rresp_o   : out std_logic_vector(1 downto 0);
        cpu_rvalid_o  : out std_logic;
        cpu_rready_i  : in  std_logic;
        -- Write channels
        cpu_awaddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_awvalid_i : in  std_logic;
        cpu_awprot_i  : in  std_logic_vector(2 downto 0);
        cpu_awready_o : out std_logic;
        cpu_wdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_wstrb_i   : in  std_logic_vector(3 downto 0);
        cpu_wvalid_i  : in  std_logic;
        cpu_wready_o  : out std_logic;
        cpu_bresp_o   : out std_logic_vector(1 downto 0);
        cpu_bvalid_o  : out std_logic;
        cpu_bready_i  : in  std_logic;

        -- ---- Interface AXI4-Lite Master (para external DM) --------------
        -- Read channel
        mem_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_arvalid_o : out std_logic;
        mem_arprot_o  : out std_logic_vector(2 downto 0);
        mem_arready_i : in  std_logic;
        mem_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_rresp_i   : in  std_logic_vector(1 downto 0);
        mem_rvalid_i  : in  std_logic;
        mem_rready_o  : out std_logic;
        -- Write channels
        mem_awaddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_awvalid_o : out std_logic;
        mem_awprot_o  : out std_logic_vector(2 downto 0);
        mem_awready_i : in  std_logic;
        mem_wdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_wstrb_o   : out std_logic_vector(3 downto 0);
        mem_wvalid_o  : out std_logic;
        mem_wready_i  : in  std_logic;
        mem_bresp_i   : in  std_logic_vector(1 downto 0);
        mem_bvalid_i  : in  std_logic;
        mem_bready_o  : out std_logic;

        -- ---- Flush (FENCE/FENCE.I) ---------------------------------------
        flush_i       : in  std_logic
    );
end entity dcache;

architecture rtl of dcache is

    -- =========================================================================
    -- Parâmetros internos
    -- =========================================================================
    constant OFF_BITS  : integer := 4;   -- bits [3:2] = offset em palavras
    constant IDX_BITS  : integer := 8;   -- bits [11:4] = 256 sets
    constant TAG_LO    : integer := OFF_BITS + IDX_BITS;  -- = 12
    constant TAG_HI    : integer := DATA_WIDTH - 1;
    constant TAG_BITS  : integer := TAG_HI - TAG_LO + 1;  -- = 20

    -- =========================================================================
    -- Tipos de memória
    -- =========================================================================
    type data_line_t  is array (0 to LINE_WORDS-1) of
        std_logic_vector(DATA_WIDTH-1 downto 0);
    type cache_data_t is array (0 to N_LINES-1) of data_line_t;
    type tag_arr_t    is array (0 to N_LINES-1) of
        std_logic_vector(TAG_BITS-1 downto 0);
    type bool_arr_t   is array (0 to N_LINES-1) of std_logic;

    signal cache_data_r  : cache_data_t := (others => (others => (others => '0')));
    signal cache_tag_r   : tag_arr_t    := (others => (others => '0'));
    signal cache_valid_r : bool_arr_t   := (others => '0');
    signal cache_dirty_r : bool_arr_t   := (others => '0');

    -- =========================================================================
    -- FSM
    -- =========================================================================
    type dcache_state_t is (
        S_IDLE,
        -- Read path
        S_RFILL_ADDR, S_RFILL_DATA, S_RRESPOND,
        -- Write path (hit)
        S_WRITE_RESP,
        -- Writeback before fill (dirty eviction)
        S_WB_ADDR, S_WB_DATA, S_WB_RESP,
        -- Write-allocate (fill line then write)
        S_WALL_ADDR, S_WALL_DATA
    );
    signal state_r : dcache_state_t := S_IDLE;

    -- Pedido capturado
    signal req_addr_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal req_wdata_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal req_wstrb_r : std_logic_vector(3 downto 0)            := (others => '0');
    signal req_we_r    : std_logic := '0';
    signal req_valid_r : std_logic := '0';

    signal fill_cnt_r   : integer range 0 to LINE_WORDS-1 := 0;
    signal fill_base_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal fill_buf_r   : data_line_t := (others => (others => '0'));

    -- Derivações combinacionais do pedido corrente
    signal req_idx_s   : integer range 0 to N_LINES-1;
    signal req_tag_s   : std_logic_vector(TAG_BITS-1 downto 0);
    signal req_off_s   : integer range 0 to LINE_WORDS-1;
    signal hit_s       : std_logic;

begin

    -- =========================================================================
    -- Modo PASSTHROUGH (ENABLE_TAGS=false)
    -- =========================================================================
    gen_passthrough : if not ENABLE_TAGS generate

        -- Read
        mem_araddr_o  <= cpu_araddr_i;
        mem_arvalid_o <= cpu_arvalid_i;
        mem_arprot_o  <= cpu_arprot_i;
        cpu_arready_o <= mem_arready_i;
        cpu_rdata_o   <= mem_rdata_i;
        cpu_rresp_o   <= mem_rresp_i;
        cpu_rvalid_o  <= mem_rvalid_i;
        mem_rready_o  <= cpu_rready_i;

        -- Write
        mem_awaddr_o  <= cpu_awaddr_i;
        mem_awvalid_o <= cpu_awvalid_i;
        mem_awprot_o  <= cpu_awprot_i;
        cpu_awready_o <= mem_awready_i;
        mem_wdata_o   <= cpu_wdata_i;
        mem_wstrb_o   <= cpu_wstrb_i;
        mem_wvalid_o  <= cpu_wvalid_i;
        cpu_wready_o  <= mem_wready_i;
        cpu_bresp_o   <= mem_bresp_i;
        cpu_bvalid_o  <= mem_bvalid_i;
        mem_bready_o  <= cpu_bready_i;

    end generate gen_passthrough;

    -- =========================================================================
    -- Modo CACHE (ENABLE_TAGS=true): Write-back + Write-allocate
    -- =========================================================================
    gen_cache : if ENABLE_TAGS generate

        req_idx_s <= to_integer(unsigned(req_addr_r(OFF_BITS + IDX_BITS - 1 downto OFF_BITS)));
        req_tag_s <= req_addr_r(TAG_HI downto TAG_LO);
        req_off_s <= to_integer(unsigned(req_addr_r(OFF_BITS-1 downto 2)));

        hit_s <= '1' when (cache_valid_r(req_idx_s) = '1' and
                            cache_tag_r(req_idx_s) = req_tag_s)
                 else '0';

        cache_fsm : process(clk_i)
            variable idx       : integer range 0 to N_LINES-1;
            variable fill_addr : std_logic_vector(DATA_WIDTH-1 downto 0);
            variable wb_addr   : std_logic_vector(DATA_WIDTH-1 downto 0);
            variable word      : std_logic_vector(DATA_WIDTH-1 downto 0);
        begin
            if rising_edge(clk_i) then
                -- Default outputs
                cpu_arready_o <= '0'; cpu_rdata_o  <= (others => '0');
                cpu_rresp_o   <= "00"; cpu_rvalid_o <= '0';
                cpu_awready_o <= '0'; cpu_wready_o <= '0';
                cpu_bresp_o   <= "00"; cpu_bvalid_o <= '0';
                mem_arvalid_o <= '0'; mem_rready_o  <= '0';
                mem_araddr_o  <= (others => '0'); mem_arprot_o  <= "000";
                mem_awvalid_o <= '0'; mem_wvalid_o  <= '0';
                mem_bready_o  <= '0';
                mem_awaddr_o  <= (others => '0'); mem_awprot_o <= "000";
                mem_wdata_o   <= (others => '0'); mem_wstrb_o  <= (others => '0');

                if rst_ni = '0' then
                    state_r       <= S_IDLE;
                    req_valid_r   <= '0';
                    fill_cnt_r    <= 0;
                    cache_valid_r <= (others => '0');
                    cache_dirty_r <= (others => '0');

                elsif flush_i = '1' then
                    -- Simplified flush: drop dirty bits (no writeback on flush)
                    cache_valid_r <= (others => '0');
                    cache_dirty_r <= (others => '0');
                    state_r       <= S_IDLE;
                    req_valid_r   <= '0';

                else
                    case state_r is

                        -- ---- IDLE: captura pedido e verifica tag ----------
                        when S_IDLE =>
                            -- Captura pedido de leitura
                            if cpu_arvalid_i = '1' and req_valid_r = '0' then
                                req_addr_r  <= cpu_araddr_i;
                                req_we_r    <= '0';
                                req_valid_r <= '1';
                                cpu_arready_o <= '1';
                            -- Captura pedido de escrita (AW+W simultâneos)
                            elsif cpu_awvalid_i = '1' and cpu_wvalid_i = '1' and
                                  req_valid_r = '0' then
                                req_addr_r  <= cpu_awaddr_i;
                                req_wdata_r <= cpu_wdata_i;
                                req_wstrb_r <= cpu_wstrb_i;
                                req_we_r    <= '1';
                                req_valid_r <= '1';
                                cpu_awready_o <= '1';
                                cpu_wready_o  <= '1';
                            end if;

                            if req_valid_r = '1' then
                                idx := req_idx_s;
                                if req_we_r = '0' then
                                    -- Read
                                    if hit_s = '1' then
                                        cpu_rdata_o  <= cache_data_r(idx)(req_off_s);
                                        cpu_rresp_o  <= "00";
                                        cpu_rvalid_o <= '1';
                                        req_valid_r  <= '0';
                                    else
                                        -- Read miss: check dirty before fill
                                        fill_base_r <= req_addr_r(DATA_WIDTH-1 downto OFF_BITS)
                                                       & (OFF_BITS-1 downto 0 => '0');
                                        fill_cnt_r  <= 0;
                                        if cache_dirty_r(idx) = '1' then
                                            state_r <= S_WB_ADDR; -- evict dirty
                                        else
                                            state_r <= S_RFILL_ADDR;
                                        end if;
                                    end if;
                                else
                                    -- Write hit: update cache, set dirty
                                    if hit_s = '1' then
                                        for b in 0 to 3 loop
                                            if req_wstrb_r(b) = '1' then
                                                cache_data_r(idx)(req_off_s)(b*8+7 downto b*8)
                                                    <= req_wdata_r(b*8+7 downto b*8);
                                            end if;
                                        end loop;
                                        cache_dirty_r(idx) <= '1';
                                        cpu_bvalid_o <= '1';
                                        cpu_bresp_o  <= "00";
                                        req_valid_r  <= '0';
                                    else
                                        -- Write miss: write-allocate
                                        fill_base_r <= req_addr_r(DATA_WIDTH-1 downto OFF_BITS)
                                                       & (OFF_BITS-1 downto 0 => '0');
                                        fill_cnt_r  <= 0;
                                        if cache_dirty_r(idx) = '1' then
                                            state_r <= S_WB_ADDR;
                                        else
                                            state_r <= S_WALL_ADDR;
                                        end if;
                                    end if;
                                end if;
                            end if;

                        -- ---- WRITEBACK: evict dirty line ------------------
                        when S_WB_ADDR =>
                            idx := req_idx_s;
                            -- Endereço da linha suja na memória
                            wb_addr := cache_tag_r(idx)
                                       & std_logic_vector(to_unsigned(idx, IDX_BITS))
                                       & (OFF_BITS-1 downto 0 => '0');
                            fill_addr := std_logic_vector(
                                unsigned(wb_addr) + to_unsigned(fill_cnt_r * 4, DATA_WIDTH));
                            mem_awaddr_o  <= fill_addr;
                            mem_awvalid_o <= '1';
                            mem_awprot_o  <= "000";
                            mem_wdata_o   <= cache_data_r(idx)(fill_cnt_r);
                            mem_wstrb_o   <= "1111";
                            mem_wvalid_o  <= '1';
                            if mem_awready_i = '1' and mem_wready_i = '1' then
                                state_r <= S_WB_RESP;
                            end if;

                        when S_WB_RESP =>
                            mem_bready_o <= '1';
                            if mem_bvalid_i = '1' then
                                if fill_cnt_r = LINE_WORDS - 1 then
                                    -- Writeback completo; agora faz fill
                                    cache_dirty_r(req_idx_s) <= '0';
                                    fill_cnt_r <= 0;
                                    if req_we_r = '0' then
                                        state_r <= S_RFILL_ADDR;
                                    else
                                        state_r <= S_WALL_ADDR;
                                    end if;
                                else
                                    fill_cnt_r <= fill_cnt_r + 1;
                                    state_r    <= S_WB_ADDR;
                                end if;
                            end if;

                        -- ---- READ FILL ------------------------------------
                        when S_RFILL_ADDR =>
                            fill_addr := std_logic_vector(
                                unsigned(fill_base_r) + to_unsigned(fill_cnt_r * 4, DATA_WIDTH));
                            mem_araddr_o  <= fill_addr;
                            mem_arvalid_o <= '1';
                            mem_arprot_o  <= "000";
                            if mem_arready_i = '1' then
                                state_r <= S_RFILL_DATA;
                            end if;

                        when S_RFILL_DATA =>
                            mem_rready_o <= '1';
                            if mem_rvalid_i = '1' then
                                fill_buf_r(fill_cnt_r) <= mem_rdata_i;
                                if fill_cnt_r = LINE_WORDS - 1 then
                                    idx := req_idx_s;
                                    cache_data_r(idx)  <= fill_buf_r;
                                    cache_data_r(idx)(fill_cnt_r) <= mem_rdata_i;
                                    cache_tag_r(idx)   <= req_tag_s;
                                    cache_valid_r(idx) <= '1';
                                    cache_dirty_r(idx) <= '0';
                                    state_r            <= S_RRESPOND;
                                else
                                    fill_cnt_r <= fill_cnt_r + 1;
                                    state_r    <= S_RFILL_ADDR;
                                end if;
                            end if;

                        when S_RRESPOND =>
                            cpu_rdata_o  <= cache_data_r(req_idx_s)(req_off_s);
                            cpu_rresp_o  <= "00";
                            cpu_rvalid_o <= '1';
                            req_valid_r  <= '0';
                            state_r      <= S_IDLE;

                        -- ---- WRITE-ALLOCATE FILL --------------------------
                        when S_WALL_ADDR =>
                            fill_addr := std_logic_vector(
                                unsigned(fill_base_r) + to_unsigned(fill_cnt_r * 4, DATA_WIDTH));
                            mem_araddr_o  <= fill_addr;
                            mem_arvalid_o <= '1';
                            mem_arprot_o  <= "000";
                            if mem_arready_i = '1' then
                                state_r <= S_WALL_DATA;
                            end if;

                        when S_WALL_DATA =>
                            mem_rready_o <= '1';
                            if mem_rvalid_i = '1' then
                                fill_buf_r(fill_cnt_r) <= mem_rdata_i;
                                if fill_cnt_r = LINE_WORDS - 1 then
                                    idx := req_idx_s;
                                    cache_data_r(idx)  <= fill_buf_r;
                                    cache_data_r(idx)(fill_cnt_r) <= mem_rdata_i;
                                    -- Aplica o write após o fill
                                    for b in 0 to 3 loop
                                        if req_wstrb_r(b) = '1' then
                                            cache_data_r(idx)(req_off_s)(b*8+7 downto b*8)
                                                <= req_wdata_r(b*8+7 downto b*8);
                                        end if;
                                    end loop;
                                    cache_tag_r(idx)   <= req_tag_s;
                                    cache_valid_r(idx) <= '1';
                                    cache_dirty_r(idx) <= '1'; -- escrita suja
                                    cpu_bvalid_o <= '1';
                                    cpu_bresp_o  <= "00";
                                    req_valid_r  <= '0';
                                    state_r      <= S_IDLE;
                                else
                                    fill_cnt_r <= fill_cnt_r + 1;
                                    state_r    <= S_WALL_ADDR;
                                end if;
                            end if;

                        when S_WRITE_RESP =>
                            cpu_bvalid_o <= '1';
                            cpu_bresp_o  <= "00";
                            req_valid_r  <= '0';
                            state_r      <= S_IDLE;

                        when others =>
                            state_r <= S_IDLE;

                    end case;
                end if;
            end if;
        end process cache_fsm;

    end generate gen_cache;

end architecture rtl;
