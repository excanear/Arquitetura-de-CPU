-- =============================================================================
-- branch_predictor.vhd
-- Preditor de Desvios – 1-bit com BTB (Branch Target Buffer)
--
-- Arquitetura:
--   - 64 entradas indexadas por PC[7:2] (6 bits)
--   - Tabela de histórico: 1 bit por entrada (0=NOT_TAKEN, 1=TAKEN)
--     Transição: novo_estado = branch_taken_real (perfeito para loops)
--   - BTB: armazena {valid(1), tag(PC[31:8]=24 bits), target(32 bits)}
--     → total de 57 bits por entrada
--
-- Interface de consulta (combinacional):
--   - pc_i          → pred_taken_o, pred_target_o
--   - pred_taken_o='1' apenas quando BTB tem hit E hist=TAKEN
--
-- Interface de atualização (registrada, 1 ciclo após resolução no EX):
--   - upd_en_i      : pulso '1' quando um branch/JAL resolve no execute stage
--   - upd_pc_i      : PC da instrução de branch/jump
--   - upd_taken_i   : resultado real (0=not taken, 1=taken)
--   - upd_target_i  : endereço alvo real (para atualizar o BTB)
--   - upd_is_branch_i: '1' somente para branches condicionais e JAL/JALR
--                      (não atualizar para ECALL, trap, etc.)
--
-- Integração no pipeline:
--   - Consultado pelo fetch_stage com o PC corrente
--   - Quando pred_taken_o='1': branch_handler redireciona PC para pred_target
--   - Quando predição errada (branch resolvido diferente): flush normal via
--     branch_taken_s ou jalr_en_s já existentes no cpu_top
--   - Sem hardware extra de "misprediction detection" – reutiliza flush existente
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity branch_predictor is
    generic (
        DATA_WIDTH : integer := XLEN;
        -- Número de entradas (deve ser potência de 2)
        N_ENTRIES  : integer := 64
    );
    port (
        clk_i           : in  std_logic;
        rst_ni          : in  std_logic;

        -- ---- Interface de Consulta (combinacional) ----------------------
        -- Usado no estágio IF para redirecionar o PC antecipadamente
        pred_pc_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        pred_taken_o    : out std_logic;
        pred_target_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Interface de Atualização (registrada) ----------------------
        -- Acionada quando o branch resolve no estágio Execute
        upd_en_i        : in  std_logic;
        upd_is_branch_i : in  std_logic;   -- '1' = branch/JAL/JALR; '0' = ignorar
        upd_pc_i        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        upd_taken_i     : in  std_logic;
        upd_target_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity branch_predictor;

architecture rtl of branch_predictor is

    -- =========================================================================
    -- Constantes derivadas
    -- =========================================================================
    constant IDX_BITS : integer := 6;   -- log2(64) = 6
    constant TAG_BITS : integer := DATA_WIDTH - IDX_BITS - 2; -- PC[31:8] = 24 bits

    -- =========================================================================
    -- Tabela de histórico: 1 bit por entrada
    -- =========================================================================
    type hist_t is array (0 to N_ENTRIES-1) of std_logic;
    signal hist_r : hist_t := (others => '0'); -- Inicializa como NOT_TAKEN

    -- =========================================================================
    -- BTB (Branch Target Buffer): tag + target + valid
    -- =========================================================================
    type btb_tag_t    is array (0 to N_ENTRIES-1) of std_logic_vector(TAG_BITS-1 downto 0);
    type btb_target_t is array (0 to N_ENTRIES-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal btb_valid_r  : hist_t       := (others => '0');
    signal btb_tag_r    : btb_tag_t    := (others => (others => '0'));
    signal btb_target_r : btb_target_t := (others => (others => '0'));

    -- =========================================================================
    -- Funções auxiliares de índice e tag
    -- =========================================================================
    -- Índice: PC[7:2]
    function get_idx(pc : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(pc(IDX_BITS+1 downto 2)));
    end function;

    -- Tag: PC[31:8]
    function get_tag(pc : std_logic_vector) return std_logic_vector is
    begin
        return pc(DATA_WIDTH-1 downto IDX_BITS+2);
    end function;

    -- Sinais combinacionais de consulta
    signal pred_idx   : integer range 0 to N_ENTRIES-1;
    signal pred_tag_s : std_logic_vector(TAG_BITS-1 downto 0);
    signal btb_hit_s  : std_logic;

begin

    -- =========================================================================
    -- Consulta (puramente combinacional)
    -- =========================================================================
    pred_idx   <= get_idx(pred_pc_i);
    pred_tag_s <= get_tag(pred_pc_i);

    -- BTB hit: entrada válida E tag bate
    btb_hit_s  <= '1' when (btb_valid_r(pred_idx) = '1' and
                             btb_tag_r(pred_idx) = pred_tag_s)
                  else '0';

    -- Predição: tomado apenas se histórico=TAKEN e BTB hit
    pred_taken_o  <= hist_r(pred_idx) and btb_hit_s;
    pred_target_o <= btb_target_r(pred_idx);

    -- =========================================================================
    -- Atualização (registrada na borda de subida)
    -- =========================================================================
    update_proc : process(clk_i)
        variable idx : integer range 0 to N_ENTRIES-1;
    begin
        if rising_edge(clk_i) then
            if rst_ni = '0' then
                hist_r      <= (others => '0');
                btb_valid_r <= (others => '0');
            elsif upd_en_i = '1' and upd_is_branch_i = '1' then
                idx := get_idx(upd_pc_i);

                -- Atualiza histório: 1-bit = resultado real
                hist_r(idx) <= upd_taken_i;

                -- Atualiza BTB sempre que o branch resolve (overwrite)
                btb_valid_r(idx)  <= '1';
                btb_tag_r(idx)    <= get_tag(upd_pc_i);
                btb_target_r(idx) <= upd_target_i;
            end if;
        end if;
    end process update_proc;

end architecture rtl;
