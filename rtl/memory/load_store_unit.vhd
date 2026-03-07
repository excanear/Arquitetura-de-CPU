-- =============================================================================
-- load_store_unit.vhd
-- Unidade de Load/Store – Interface AXI4-Lite para Data Memory
--
-- Responsabilidades:
--   - Gerar requisições AXI4-Lite de leitura (load) e escrita (store)
--   - Alinhar e expandir dados de acordo com o tamanho (byte/half/word)
--   - Realizar extensão de sinal para loads (LB, LH) ou zero-extend (LBU, LHU)
--   - Informar stall enquanto aguarda resposta AXI
--
-- Máquinas de estado:
--   IDLE → ADDR_PHASE → DATA_PHASE → RESP_PHASE (apenas stores) → IDLE
--
-- Restrições de alinhamento:
--   A especificação RV32I exige acesso alinhado. A detecção de endereços
--   desalinhados é feita no execute_stage (misalign_o) e sinalizada como
--   trap mcause=4 (load) ou mcause=6 (store) pelo cpu_top.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity load_store_unit is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic;

        -- Controle
        mem_read_i  : in  std_logic;
        mem_write_i : in  std_logic;
        mem_size_i  : in  std_logic_vector(2 downto 0); -- funct3

        -- Dados de entrada
        addr_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wdata_i     : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Dados de saída (leitura)
        rdata_o     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rdata_valid_o : out std_logic; -- pulso: dado de leitura válido

        -- Stall: unidade aguardando resposta AXI
        mem_stall_o : out std_logic;

        -- ---- Interface AXI4-Lite para Data Memory -------------------------
        -- AR Channel
        dm_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_arvalid_o : out std_logic;
        dm_arprot_o  : out std_logic_vector(2 downto 0);
        dm_arready_i : in  std_logic;
        -- R Channel
        dm_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_rresp_i   : in  std_logic_vector(1 downto 0);
        dm_rvalid_i  : in  std_logic;
        dm_rready_o  : out std_logic;
        -- AW Channel
        dm_awaddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_awvalid_o : out std_logic;
        dm_awprot_o  : out std_logic_vector(2 downto 0);
        dm_awready_i : in  std_logic;
        -- W Channel
        dm_wdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_wstrb_o   : out std_logic_vector(3 downto 0);
        dm_wvalid_o  : out std_logic;
        dm_wready_i  : in  std_logic;
        -- B Channel
        dm_bresp_i   : in  std_logic_vector(1 downto 0);
        dm_bvalid_i  : in  std_logic;
        dm_bready_o  : out std_logic;

        -- ---- RV32A Atomic operations (AMO / LR / SC) ---------------------
        amo_i        : in  std_logic;                      -- AMO op in progress
        amo_is_lr_i  : in  std_logic;                      -- LR.W
        amo_is_sc_i  : in  std_logic;                      -- SC.W
        amo_funct5_i : in  std_logic_vector(4 downto 0);   -- AMO operation select
        sc_result_o  : out std_logic_vector(DATA_WIDTH-1 downto 0) -- 0=SC ok, 1=fail
    );
end entity load_store_unit;

architecture rtl of load_store_unit is

    -- =========================================================================
    -- FSM de controle AXI
    -- =========================================================================
    type lsu_state_t is (
        S_IDLE,
        S_LOAD_ADDR,      -- AR phase for regular load
        S_LOAD_DATA,      -- R phase for regular load
        S_STORE_ADDR,     -- AW+W phase for regular store
        S_STORE_RESP,     -- B phase for regular store
        S_AMO_LOAD_ADDR,  -- AR phase for LR/AMO read
        S_AMO_LOAD_DATA,  -- R phase for LR/AMO read
        S_AMO_STORE_ADDR, -- AW+W phase for SC/AMO write
        S_AMO_STORE_RESP, -- B phase for SC/AMO write
        S_SC_FAIL         -- SC.W failed (no reservation) – output 1 for 1 cycle
    );

    signal state_r : lsu_state_t;
    signal next_s  : lsu_state_t;

    -- Latches internos para sinais AXI
    signal arvalid_r : std_logic;
    signal rready_r  : std_logic;
    signal awvalid_r : std_logic;
    signal wvalid_r  : std_logic;
    signal bready_r  : std_logic;

    signal addr_r    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal wdata_r   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal wstrb_r   : std_logic_vector(3 downto 0);
    signal size_r    : std_logic_vector(2 downto 0);

    -- Captura do dado de leitura
    signal rdata_r   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rdata_vld : std_logic;

    -- =========================================================================
    -- AMO / LR / SC support
    -- =========================================================================
    -- Reservation register for LR.W / SC.W
    signal reservation_valid_r : std_logic                          := '0';
    signal reservation_addr_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- AMO: value loaded from memory (used in read-modify-write)
    signal amo_loaded_r  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal amo_funct5_r  : std_logic_vector(4 downto 0);
    signal amo_is_lr_r   : std_logic;
    signal amo_is_sc_r   : std_logic;
    signal sc_ok         : std_logic; -- SC.W succeeds when '1'

    -- AMO computed write-back value (combinatorial)
    signal amo_result    : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    -- =========================================================================
    -- AMO result computation (combinatorial)
    -- Uses amo_loaded_r (old memory value) and wdata_r (rs2 operand)
    -- =========================================================================
    amo_compute : process(amo_funct5_r, amo_loaded_r, wdata_r)
        variable s_a, s_b : signed(DATA_WIDTH-1 downto 0);
        variable u_a, u_b : unsigned(DATA_WIDTH-1 downto 0);
    begin
        s_a := signed(amo_loaded_r);
        s_b := signed(wdata_r);
        u_a := unsigned(amo_loaded_r);
        u_b := unsigned(wdata_r);

        case amo_funct5_r is
            when "00001" => amo_result <= wdata_r;                              -- AMOSWAP
            when "00000" => amo_result <= std_logic_vector(s_a + s_b);          -- AMOADD
            when "00100" => amo_result <= amo_loaded_r xor wdata_r;             -- AMOXOR
            when "01100" => amo_result <= amo_loaded_r and wdata_r;             -- AMOAND
            when "01000" => amo_result <= amo_loaded_r or  wdata_r;             -- AMOOR
            when "10000" =>                                                      -- AMOMIN
                if s_a < s_b then amo_result <= amo_loaded_r;
                else              amo_result <= wdata_r; end if;
            when "10100" =>                                                      -- AMOMAX
                if s_a > s_b then amo_result <= amo_loaded_r;
                else              amo_result <= wdata_r; end if;
            when "11000" =>                                                      -- AMOMINU
                if u_a < u_b then amo_result <= amo_loaded_r;
                else              amo_result <= wdata_r; end if;
            when "11100" =>                                                      -- AMOMAXU
                if u_a > u_b then amo_result <= amo_loaded_r;
                else              amo_result <= wdata_r; end if;
            when others  => amo_result <= wdata_r;
        end case;
    end process amo_compute;

    -- SC.W succeeds only when reservation is valid and address matches
    -- addr_i is checked here (not addr_r) because the check happens in S_IDLE
    -- before addr_r is latched at the next rising edge.
    sc_ok <= reservation_valid_r when
        reservation_addr_r = addr_i else '0';

    -- SC result for rd writeback: 0=success, 1=failure
    sc_result_o <= (others => '0') when sc_ok = '1'
                   else std_logic_vector(to_unsigned(1, DATA_WIDTH));

    -- =========================================================================
    -- Captura dos parâmetros da transação na borda de entrada
    -- =========================================================================
    latch_req : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            addr_r      <= (others => '0');
            wdata_r     <= (others => '0');
            wstrb_r     <= (others => '0');
            size_r      <= "010";
            amo_funct5_r<= (others => '0');
            amo_is_lr_r <= '0';
            amo_is_sc_r <= '0';
        elsif rising_edge(clk_i) then
            if state_r = S_IDLE then
                addr_r      <= addr_i;
                size_r      <= mem_size_i;
                amo_funct5_r<= amo_funct5_i;
                amo_is_lr_r <= amo_is_lr_i;
                amo_is_sc_r <= amo_is_sc_i;
                -- Alinha dado de escrita e gera strobe de byte-enable
                case mem_size_i(1 downto 0) is
                    when "00" => -- byte
                        case addr_i(1 downto 0) is
                            when "00"   =>
                                wdata_r <= x"000000" & wdata_i(7 downto 0);
                                wstrb_r <= "0001";
                            when "01"   =>
                                wdata_r <= x"0000" & wdata_i(7 downto 0) & x"00";
                                wstrb_r <= "0010";
                            when "10"   =>
                                wdata_r <= x"00" & wdata_i(7 downto 0) & x"0000";
                                wstrb_r <= "0100";
                            when others =>
                                wdata_r <= wdata_i(7 downto 0) & x"000000";
                                wstrb_r <= "1000";
                        end case;
                    when "01" => -- halfword
                        if addr_i(1) = '0' then
                            wdata_r <= x"0000"   & wdata_i(15 downto 0);
                            wstrb_r <= "0011";
                        else
                            wdata_r <= wdata_i(15 downto 0) & x"0000";
                            wstrb_r <= "1100";
                        end if;
                    when others => -- word (also AMO: always word-aligned)
                        wdata_r <= wdata_i;
                        wstrb_r <= "1111";
                end case;
            end if;
        end if;
    end process latch_req;

    -- =========================================================================
    -- FSM: Próximo estado
    -- =========================================================================
    fsm_seq : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            state_r            <= S_IDLE;
            reservation_valid_r<= '0';
            reservation_addr_r <= (others => '0');
            amo_loaded_r       <= (others => '0');
        elsif rising_edge(clk_i) then
            state_r <= next_s;

            -- LR.W: set reservation when load completes
            if state_r = S_AMO_LOAD_DATA and dm_rvalid_i = '1' and amo_is_lr_r = '1' then
                reservation_valid_r <= '1';
                reservation_addr_r  <= addr_r;
                amo_loaded_r        <= dm_rdata_i;
            end if;

            -- AMO: capture loaded value when load completes
            if state_r = S_AMO_LOAD_DATA and dm_rvalid_i = '1' and amo_is_lr_r = '0' then
                amo_loaded_r <= dm_rdata_i;
            end if;

            -- SC.W success/fail: clear reservation on any SC attempt
            if state_r = S_IDLE and amo_is_sc_i = '1' and amo_i = '1' then
                reservation_valid_r <= '0';
            end if;
        end if;
    end process fsm_seq;

    fsm_comb : process(state_r, mem_read_i, mem_write_i, amo_i, amo_is_lr_i, amo_is_sc_i,
                       addr_i, sc_ok, amo_loaded_r, amo_result,
                       dm_arready_i, dm_rvalid_i,
                       dm_awready_i, dm_wready_i, dm_bvalid_i)
    begin
        next_s      <= state_r;
        arvalid_r   <= '0';
        rready_r    <= '0';
        awvalid_r   <= '0';
        wvalid_r    <= '0';
        bready_r    <= '0';
        rdata_vld   <= '0';
        mem_stall_o <= '0';

        case state_r is

            when S_IDLE =>
                if amo_i = '1' then
                    if amo_is_sc_i = '1' then
                        if sc_ok = '1' then
                            -- SC succeeds: do the store
                            next_s      <= S_AMO_STORE_ADDR;
                            mem_stall_o <= '1';
                        else
                            -- SC fails immediately (no reservation)
                            next_s      <= S_SC_FAIL;
                            mem_stall_o <= '1';
                        end if;
                    else
                        -- LR or regular AMO: first load
                        next_s      <= S_AMO_LOAD_ADDR;
                        mem_stall_o <= '1';
                    end if;
                elsif mem_read_i = '1' then
                    next_s      <= S_LOAD_ADDR;
                    mem_stall_o <= '1';
                elsif mem_write_i = '1' then
                    next_s      <= S_STORE_ADDR;
                    mem_stall_o <= '1';
                end if;

            -- ----- Regular load -------------------------------------------
            when S_LOAD_ADDR =>
                arvalid_r   <= '1';
                mem_stall_o <= '1';
                if dm_arready_i = '1' then
                    next_s <= S_LOAD_DATA;
                end if;

            when S_LOAD_DATA =>
                rready_r    <= '1';
                mem_stall_o <= '1';
                if dm_rvalid_i = '1' then
                    rdata_vld   <= '1';
                    next_s      <= S_IDLE;
                    mem_stall_o <= '0';
                end if;

            -- ----- Regular store ------------------------------------------
            when S_STORE_ADDR =>
                awvalid_r   <= '1';
                wvalid_r    <= '1';
                mem_stall_o <= '1';
                if dm_awready_i = '1' and dm_wready_i = '1' then
                    next_s <= S_STORE_RESP;
                end if;

            when S_STORE_RESP =>
                bready_r    <= '1';
                mem_stall_o <= '1';
                if dm_bvalid_i = '1' then
                    next_s      <= S_IDLE;
                    mem_stall_o <= '0';
                end if;

            -- ----- AMO / LR load phase ------------------------------------
            when S_AMO_LOAD_ADDR =>
                arvalid_r   <= '1';
                mem_stall_o <= '1';
                if dm_arready_i = '1' then
                    next_s <= S_AMO_LOAD_DATA;
                end if;

            when S_AMO_LOAD_DATA =>
                rready_r    <= '1';
                mem_stall_o <= '1';
                if dm_rvalid_i = '1' then
                    rdata_vld <= '1';   -- rdata captured in lsu_seq (amo_loaded_r)
                    if amo_is_lr_r = '1' then
                        next_s      <= S_IDLE;  -- LR done; rdata = loaded value
                        mem_stall_o <= '0';
                    else
                        next_s <= S_AMO_STORE_ADDR;
                    end if;
                end if;

            -- ----- AMO / SC store phase -----------------------------------
            when S_AMO_STORE_ADDR =>
                awvalid_r   <= '1';
                wvalid_r    <= '1';
                mem_stall_o <= '1';
                if dm_awready_i = '1' and dm_wready_i = '1' then
                    next_s <= S_AMO_STORE_RESP;
                end if;

            when S_AMO_STORE_RESP =>
                bready_r    <= '1';
                mem_stall_o <= '1';
                if dm_bvalid_i = '1' then
                    rdata_vld   <= '1';   -- output old value (amo_loaded_r) or 0 for SC
                    next_s      <= S_IDLE;
                    mem_stall_o <= '0';
                end if;

            -- ----- SC.W fail (1-cycle stall, output 1) -------------------
            when S_SC_FAIL =>
                rdata_vld   <= '1';
                next_s      <= S_IDLE;
                mem_stall_o <= '0';

            when others => next_s <= S_IDLE;
        end case;
    end process fsm_comb;

    -- =========================================================================
    -- Captura e extensão do dado de leitura
    -- For regular loads: capture and sign/zero-extend from dm_rdata_i
    -- For LR.W and AMO: rdata = amo_loaded_r (old value from memory)
    -- For SC.W success: rdata = 0; SC fail: rdata = 1 (via sc_result_o used upstream)
    -- =========================================================================
    rdata_proc : process(clk_i, rst_ni)
        variable raw : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable byte_val : std_logic_vector(7 downto 0);
        variable half_val : std_logic_vector(15 downto 0);
    begin
        if rst_ni = '0' then
            rdata_r <= (others => '0');
        elsif rising_edge(clk_i) then
            if rdata_vld = '1' then
                -- AMO/LR: output the value loaded from memory (before modification)
                if state_r = S_AMO_LOAD_DATA or
                   state_r = S_AMO_STORE_RESP then
                    rdata_r <= amo_loaded_r;
                -- SC fail: output 1
                elsif state_r = S_SC_FAIL then
                    rdata_r <= std_logic_vector(to_unsigned(1, DATA_WIDTH));
                -- SC success: output 0 (set during S_AMO_STORE_RESP when amo_is_sc_r='1')
                elsif state_r = S_AMO_STORE_RESP then
                    rdata_r <= (others => '0');
                else
                    -- Regular load: decode size and align
                    raw := dm_rdata_i;
                    case size_r is
                        when F3_BYTE =>
                            case addr_r(1 downto 0) is
                                when "00"   => byte_val := raw(7 downto 0);
                                when "01"   => byte_val := raw(15 downto 8);
                                when "10"   => byte_val := raw(23 downto 16);
                                when others => byte_val := raw(31 downto 24);
                            end case;
                            rdata_r <= sign_extend(byte_val, DATA_WIDTH);

                        when F3_HALF =>
                            if addr_r(1) = '0' then
                                half_val := raw(15 downto 0);
                            else
                                half_val := raw(31 downto 16);
                            end if;
                            rdata_r <= sign_extend(half_val, DATA_WIDTH);

                        when F3_WORD =>
                            rdata_r <= raw;

                        when F3_BYTEU =>
                            case addr_r(1 downto 0) is
                                when "00"   => byte_val := raw(7 downto 0);
                                when "01"   => byte_val := raw(15 downto 8);
                                when "10"   => byte_val := raw(23 downto 16);
                                when others => byte_val := raw(31 downto 24);
                            end case;
                            rdata_r <= zero_extend(byte_val, DATA_WIDTH);

                        when F3_HALFU =>
                            if addr_r(1) = '0' then
                                half_val := raw(15 downto 0);
                            else
                                half_val := raw(31 downto 16);
                            end if;
                            rdata_r <= zero_extend(half_val, DATA_WIDTH);

                        when others =>
                            rdata_r <= raw;
                    end case;
                end if;
            end if;
        end if;
    end process rdata_proc;

    -- =========================================================================
    -- Mapeamento AXI
    -- AMO store phase uses amo_result (computed new value), not wdata_r
    -- =========================================================================
    dm_araddr_o  <= addr_r;
    dm_arvalid_o <= arvalid_r;
    dm_arprot_o  <= "000";
    dm_rready_o  <= rready_r;

    dm_awaddr_o  <= addr_r;
    dm_awvalid_o <= awvalid_r;
    dm_awprot_o  <= "000";
    -- For AMO store phases, write amo_result; for regular stores, write wdata_r
    dm_wdata_o   <= amo_result when (state_r = S_AMO_STORE_ADDR or state_r = S_AMO_STORE_RESP)
                    else wdata_r;
    dm_wstrb_o   <= "1111" when (state_r = S_AMO_STORE_ADDR or state_r = S_AMO_STORE_RESP)
                    else wstrb_r;
    dm_wvalid_o  <= wvalid_r;
    dm_bready_o  <= bready_r;

    -- Saídas de leitura
    rdata_o       <= rdata_r;
    rdata_valid_o <= rdata_vld;

end architecture rtl;
