-- =============================================================================
-- branch_handler.vhd
-- Unidade de Tratamento de Desvios e Saltos
--
-- Responsável por:
--   - Selecionar o próximo PC (PC+4, branch target, JAL target, JALR target,
--     predição do branch predictor)
--   - Gerar sinal de flush para o registrador IF/ID quando um salto é tomado
--   - Calcular o endereço alvo de JAL no estágio Decode (sem bolha extra)
--   - Receber branch_taken e branch_tgt do estágio Execute
--
-- Nota sobre penalidade de desvio:
--   - Branch predictor (BTB hit + TAKEN): penalidade 0 ciclos (predição correta)
--       → mispredição ainda gera 2 ciclos de penalidade via branch_taken/jalr
--   - Branch condicional (sem preditor): resolvido no Execute → 2 ciclos
--   - JAL             : resolvido no Decode     → 1 ciclo
--   - JALR            : resolvido no Execute    → 2 ciclos
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity branch_handler is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        -- PC atual e seguinte natural
        pc_fetch_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        pc_plus4_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Sinal de JAL resolvido no Decode
        jal_en_i        : in  std_logic;
        jal_target_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Sinal de branch/JALR resolvido no Execute
        branch_taken_i  : in  std_logic;
        branch_target_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        jalr_en_i       : in  std_logic;
        jalr_target_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Trap: exceção ou interrupção (maior prioridade)
        trap_en_i       : in  std_logic;
        trap_target_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- MRET: retorno de trap (segunda prioridade)
        mret_en_i       : in  std_logic;
        mret_pc_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- FENCE.I: flush de pipeline para coerência instrucão/dados (terceira prioridade)
        fence_en_i      : in  std_logic;
        fence_pc_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Branch Predictor: predição especulativa (menor prioridade entre redirects,
        -- maior que PC+4). Flush vem do próprio branch_taken/jalr se errado.
        bp_pred_taken_i  : in  std_logic;
        bp_pred_target_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Saída: próximo PC a ser carregado no pc_reg
        next_pc_o       : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Flush para o pipeline (inserir bolhas nos registradores de estágio)
        flush_if_id_o   : out std_logic; -- flush do registrador IF/ID
        flush_id_ex_o   : out std_logic  -- flush do registrador ID/EX
    );
end entity branch_handler;

architecture rtl of branch_handler is
begin

    -- =========================================================================
    -- Seleção combinacional do próximo PC
    -- Prioridade (maior → menor):
    --   1. Trap (exceção/IRQ)          → flush IF/ID + ID/EX
    --   2. MRET                        → flush IF/ID + ID/EX
    --   3. FENCE.I                     → flush IF/ID + ID/EX
    --   4. JALR (resolve no Execute)   → flush IF/ID + ID/EX
    --   5. Branch taken (no Execute)   → flush IF/ID + ID/EX
    --   6. JAL (resolve no Decode)     → flush IF/ID
    --   7. Branch Predictor (BTB hit)  → flush IF/ID  (redirect especulativo)
    --   8. PC + 4                      → sem flush
    -- =========================================================================
    next_pc_proc : process(
        pc_plus4_i,
        jal_en_i,         jal_target_i,
        branch_taken_i,   branch_target_i,
        jalr_en_i,        jalr_target_i,
        trap_en_i,        trap_target_i,
        mret_en_i,        mret_pc_i,
        fence_en_i,       fence_pc_i,
        bp_pred_taken_i,  bp_pred_target_i
    )
    begin
        -- Padrão: fluxo normal
        next_pc_o     <= pc_plus4_i;
        flush_if_id_o <= '0';
        flush_id_ex_o <= '0';

        if trap_en_i = '1' then
            next_pc_o     <= trap_target_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '1';
        elsif mret_en_i = '1' then
            next_pc_o     <= mret_pc_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '1';
        elsif fence_en_i = '1' then
            next_pc_o     <= fence_pc_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '1';
        elsif jalr_en_i = '1' then
            next_pc_o     <= jalr_target_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '1';
        elsif branch_taken_i = '1' then
            next_pc_o     <= branch_target_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '1';
        elsif jal_en_i = '1' then
            next_pc_o     <= jal_target_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '0';
        elsif bp_pred_taken_i = '1' then
            -- Predição especulativa: redireciona sem o branch ter resolvido ainda.
            -- Se errado, branch_taken_i ou jalr_en_i corrigirão depois (flush normal).
            next_pc_o     <= bp_pred_target_i;
            flush_if_id_o <= '1';
            flush_id_ex_o <= '0';
        end if;
    end process next_pc_proc;

end architecture rtl;
