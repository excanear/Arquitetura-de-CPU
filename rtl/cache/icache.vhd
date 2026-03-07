-- =============================================================================
-- icache.vhd
-- Instruction Cache – Direct-Mapped (1-way), Interface AXI4-Lite ↔ AXI4-Lite
--
-- Arquitetura:
--   ┌────────────────────────────────────────────────────────────┐
--   │  CPU (fetch_stage AXI master)                              │
--   │      cpu_ar* ──→ [icache slave port]                       │
--   │      cpu_r*  ←── [icache slave port]                       │
--   │                              ↕  cache array                │
--   │      mem_ar* ──→ [external IM AXI slave]  (miss only)      │
--   │      mem_r*  ←── [external IM AXI slave]                   │
--   └────────────────────────────────────────────────────────────┘
--
-- Configuração padrão (ENABLE_TAGS=true):
--   - N_LINES  = 256 linhas (sets), LINE_WORDS = 4 palavras por linha
--   - Direct-mapped (1-way), TAG = PC[31:10], INDEX = PC[9:4], OFFSET = PC[3:2]
--   - Política: read-allocate on miss (write-through no aplicável – instrução ROM)
--
-- Estado ENABLE_TAGS=false (passthrough):
--   - AXI-to-AXI transparent bridge (sem cache real)
--   - arready/rvalid passados diretamente entre os dois lados
--
-- FSM de Miss (ENABLE_TAGS=true):
--   IDLE        : verifica tag
--   FILL_ADDR   : emite arvalid para IM (requisição de linha)
--   FILL_DATA   : aguarda rvalid por LINE_WORDS palavras
--   RESPOND     : entrega instrução ao fetch_stage
--
-- FENCE.I:
--   flush_i='1' invalida todos os valid bits na borda de subida
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity icache is
    generic (
        DATA_WIDTH  : integer := XLEN;
        N_LINES     : integer := 256;    -- Número de sets (deve ser 2^N)
        LINE_WORDS  : integer := 4;      -- Palavras de 32 bits por linha
        ENABLE_TAGS : boolean := true    -- false = passthrough
    );
    port (
        clk_i        : in  std_logic;
        rst_ni       : in  std_logic;

        -- ---- Interface AXI4-Lite Slave (do fetch_stage) ------------------
        cpu_araddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_arvalid_i : in  std_logic;
        cpu_arprot_i  : in  std_logic_vector(2 downto 0);
        cpu_arready_o : out std_logic;
        cpu_rdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        cpu_rresp_o   : out std_logic_vector(1 downto 0);
        cpu_rvalid_o  : out std_logic;
        cpu_rready_i  : in  std_logic;

        -- ---- Interface AXI4-Lite Master (para external IM) ---------------
        mem_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_arvalid_o : out std_logic;
        mem_arprot_o  : out std_logic_vector(2 downto 0);
        mem_arready_i : in  std_logic;
        mem_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_rresp_i   : in  std_logic_vector(1 downto 0);
        mem_rvalid_i  : in  std_logic;
        mem_rready_o  : out std_logic;

        -- ---- Flush FENCE.I -----------------------------------------------
        flush_i       : in  std_logic
    );
end entity icache;

architecture rtl of icache is

    -- =========================================================================
    -- Parâmetros derivados
    -- =========================================================================
    -- Bits de offset dentro da linha: log2(LINE_WORDS) + 2 (byte offset)
    constant OFF_BITS  : integer := 4;  -- log2(4 palavras) + 2 = 4  → bits [3:2]
    constant IDX_BITS  : integer := 8;  -- log2(256 sets)           → bits [11:4]
    constant TAG_HI    : integer := DATA_WIDTH - 1;
    constant TAG_LO    : integer := OFF_BITS + IDX_BITS;            -- = 12
    constant TAG_BITS  : integer := TAG_HI - TAG_LO + 1;            -- = 20

    -- =========================================================================
    -- Tipos de memória interna do cache
    -- =========================================================================
    -- Memória de dados: [N_LINES][LINE_WORDS] x DATA_WIDTH
    type data_line_t is array (0 to LINE_WORDS-1) of
        std_logic_vector(DATA_WIDTH-1 downto 0);
    type cache_data_t is array (0 to N_LINES-1) of data_line_t;

    -- Tag array
    type tag_arr_t   is array (0 to N_LINES-1) of
        std_logic_vector(TAG_BITS-1 downto 0);

    -- Valid bits
    type valid_arr_t is array (0 to N_LINES-1) of std_logic;

    signal cache_data_r  : cache_data_t  := (others => (others => (others => '0')));
    signal cache_tag_r   : tag_arr_t     := (others => (others => '0'));
    signal cache_valid_r : valid_arr_t   := (others => '0');

    -- =========================================================================
    -- FSM de controle
    -- =========================================================================
    type icache_state_t is (
        S_IDLE,       -- Verifica tag; em miss ou primeiro acesso, vai para FILL
        S_FILL_ADDR,  -- Emite endereços de linha para a memória
        S_FILL_DATA,  -- Captura palavras de resposta (LINE_WORDS ciclos)
        S_RESPOND     -- Entrega instrução ao fetch_stage
    );

    signal state_r  : icache_state_t := S_IDLE;

    -- Registro do pedido em curso
    signal req_addr_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal req_valid_r : std_logic := '0';

    -- Contador de palavras preenchidas durante miss
    signal fill_cnt_r  : integer range 0 to LINE_WORDS-1 := 0;
    -- Endereço base da linha (linha alinhada)
    signal fill_base_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Dados da linha em preenchimento
    signal fill_buf_r  : data_line_t := (others => (others => '0'));

    -- Resultado da consulta (mux de saída)
    signal hit_data_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal hit_s       : std_logic;

    -- Sinais auxiliares de índice/tag
    signal req_idx_s   : integer range 0 to N_LINES-1;
    signal req_tag_s   : std_logic_vector(TAG_BITS-1 downto 0);
    signal req_off_s   : integer range 0 to LINE_WORDS-1;

begin

    -- =========================================================================
    -- Modo PASSTHROUGH (ENABLE_TAGS=false)
    -- AXI-to-AXI wire-through com handshake completo
    -- =========================================================================
    gen_passthrough : if not ENABLE_TAGS generate

        -- AR: repassa do CPU para a memória diretamente
        mem_araddr_o  <= cpu_araddr_i;
        mem_arvalid_o <= cpu_arvalid_i;
        mem_arprot_o  <= cpu_arprot_i;
        cpu_arready_o <= mem_arready_i;

        -- R: repassa da memória para o CPU diretamente
        cpu_rdata_o   <= mem_rdata_i;
        cpu_rresp_o   <= mem_rresp_i;
        cpu_rvalid_o  <= mem_rvalid_i;
        mem_rready_o  <= cpu_rready_i;

    end generate gen_passthrough;

    -- =========================================================================
    -- Modo com TAGS (ENABLE_TAGS=true): Direct-mapped, fill on miss
    -- =========================================================================
    gen_cache : if ENABLE_TAGS generate

        -- Decompõe o endereço requerido
        req_idx_s <= to_integer(unsigned(req_addr_r(OFF_BITS + IDX_BITS - 1 downto OFF_BITS)));
        req_tag_s <= req_addr_r(TAG_HI downto TAG_LO);
        req_off_s <= to_integer(unsigned(req_addr_r(OFF_BITS-1 downto 2)));

        -- Hit: valid E tag bate
        hit_s      <= '1' when (cache_valid_r(req_idx_s) = '1' and
                                 cache_tag_r(req_idx_s) = req_tag_s)
                      else '0';
        hit_data_s <= cache_data_r(req_idx_s)(req_off_s);

        -- ====================================================================
        -- FSM principal
        -- ====================================================================
        fsm_proc : process(clk_i)
            variable idx       : integer range 0 to N_LINES-1;
            variable fill_addr : std_logic_vector(DATA_WIDTH-1 downto 0);
            variable fill_off  : integer range 0 to LINE_WORDS-1;
        begin
            if rising_edge(clk_i) then
                -- Defaults
                cpu_arready_o <= '0';
                cpu_rdata_o   <= (others => '0');
                cpu_rresp_o   <= "00";
                cpu_rvalid_o  <= '0';
                mem_arvalid_o <= '0';
                mem_rready_o  <= '0';
                mem_araddr_o  <= (others => '0');
                mem_arprot_o  <= cpu_arprot_i;

                if rst_ni = '0' then
                    state_r      <= S_IDLE;
                    req_valid_r  <= '0';
                    fill_cnt_r   <= 0;
                    cache_valid_r <= (others => '0');

                elsif flush_i = '1' then
                    -- FENCE.I: invalida todas as linhas
                    cache_valid_r <= (others => '0');
                    state_r       <= S_IDLE;
                    req_valid_r   <= '0';

                else
                    case state_r is

                        -- --------------------------------------------------
                        when S_IDLE =>
                            if cpu_arvalid_i = '1' and req_valid_r = '0' then
                                -- Captura novo pedido
                                req_addr_r  <= cpu_araddr_i;
                                req_valid_r <= '1';
                                cpu_arready_o <= '1'; -- aceita endereço
                            end if;

                            if req_valid_r = '1' then
                                if hit_s = '1' then
                                    -- HIT: devolve dado imediatamente
                                    cpu_rdata_o  <= hit_data_s;
                                    cpu_rresp_o  <= "00";
                                    cpu_rvalid_o <= '1';
                                    req_valid_r  <= '0';
                                    state_r      <= S_IDLE;
                                else
                                    -- MISS: inicia fill
                                    fill_base_r <= req_addr_r(DATA_WIDTH-1 downto OFF_BITS)
                                                   & (OFF_BITS-1 downto 0 => '0');
                                    fill_cnt_r  <= 0;
                                    state_r     <= S_FILL_ADDR;
                                end if;
                            end if;

                        -- --------------------------------------------------
                        when S_FILL_ADDR =>
                            -- Emite endereço para a palavra fill_cnt_r da linha
                            fill_off  := fill_cnt_r;
                            fill_addr := std_logic_vector(
                                unsigned(fill_base_r) + to_unsigned(fill_off * 4, DATA_WIDTH));
                            mem_araddr_o  <= fill_addr;
                            mem_arvalid_o <= '1';
                            mem_arprot_o  <= "100";
                            if mem_arready_i = '1' then
                                -- Endereço aceito; aguarda dado
                                state_r <= S_FILL_DATA;
                            end if;

                        -- --------------------------------------------------
                        when S_FILL_DATA =>
                            mem_rready_o <= '1';
                            if mem_rvalid_i = '1' then
                                -- Captura dado e armazena no buffer
                                fill_buf_r(fill_cnt_r) <= mem_rdata_i;
                                if fill_cnt_r = LINE_WORDS - 1 then
                                    -- Última palavra: commit para cache
                                    idx := to_integer(unsigned(
                                        fill_base_r(OFF_BITS + IDX_BITS - 1 downto OFF_BITS)));
                                    cache_data_r(idx)  <= fill_buf_r;
                                    -- Atualiza última palavra direto
                                    cache_data_r(idx)(fill_cnt_r) <= mem_rdata_i;
                                    cache_tag_r(idx)   <= fill_base_r(TAG_HI downto TAG_LO);
                                    cache_valid_r(idx) <= '1';
                                    state_r            <= S_RESPOND;
                                else
                                    fill_cnt_r <= fill_cnt_r + 1;
                                    state_r    <= S_FILL_ADDR;
                                end if;
                            end if;

                        -- --------------------------------------------------
                        when S_RESPOND =>
                            -- Linha preenchida; entrega instrução
                            cpu_rdata_o  <= cache_data_r(req_idx_s)(req_off_s);
                            cpu_rresp_o  <= "00";
                            cpu_rvalid_o <= '1';
                            req_valid_r  <= '0';
                            state_r      <= S_IDLE;

                        when others =>
                            state_r <= S_IDLE;

                    end case;
                end if;
            end if;
        end process fsm_proc;

    end generate gen_cache;

end architecture rtl;
