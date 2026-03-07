-- =============================================================================
-- fetch_stage.vhd
-- Estágio 1 do Pipeline: Instruction Fetch (IF)
--
-- Responsabilidades:
--   - Manter e incrementar o Program Counter
--   - Emitir requisições de leitura de instrução pela interface AXI4-Lite
--   - Tratar stall (aguardar resposta AXI ou hazard de dados upstream)
--   - Tratar flush (branch taken, JAL, JALR, branch predictor)
--   - Produzir o registrador de pipeline IF/ID
--   - Hospedar o Branch Predictor (1-bit + BTB 64 entradas)
--
-- Máquina de estados AXI4-Lite Read:
--   IDLE → WAIT_READY → WAIT_DATA → (dado válido → IDLE)
--
-- Branch Predictor:
--   Consultado com o PC corrente antes de emitir o request AXI.
--   Quando pred_taken='1', branch_handler redireciona o PC especulativamente.
--   A atualização ocorre quando o branch resolve no estágio Execute:
--   cpu_top fornece bp_upd_* mediante ex_mem_s sinais.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity fetch_stage is
    generic (
        DATA_WIDTH : integer := XLEN;
        RESET_ADDR : std_logic_vector(XLEN-1 downto 0) := PC_RESET
    );
    port (
        -- Controle global
        clk_i           : in  std_logic;
        rst_ni          : in  std_logic;

        -- Stall vindo de estágios posteriores (ex.: load-use hazard)
        stall_i         : in  std_logic;

        -- ---- Sinais de controle de Branch/Jump (do estágio Execute/Decode) ----
        jal_en_i        : in  std_logic;
        jal_target_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        branch_taken_i  : in  std_logic;
        branch_target_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        jalr_en_i       : in  std_logic;
        jalr_target_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Trap e MRET (vem do cpu_top via CSR) -----------------------
        trap_en_i       : in  std_logic;  -- '1' quando exceção/interrupção
        trap_target_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        mret_en_i       : in  std_logic;  -- '1' quando MRET em execute
        mret_pc_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- FENCE.I (flush de pipeline para coerência I$) ---------------
        fence_en_i      : in  std_logic;
        fence_pc_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Interface AXI4-Lite Instruction Memory (Master) ----------------
        -- AR Channel (endereço de leitura)
        im_araddr_o     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        im_arvalid_o    : out std_logic;
        im_arprot_o     : out std_logic_vector(2 downto 0);
        im_arready_i    : in  std_logic;
        -- R Channel (dados de leitura)
        im_rdata_i      : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        im_rresp_i      : in  std_logic_vector(1 downto 0);
        im_rvalid_i     : in  std_logic;
        im_rready_o     : out std_logic;

        -- ---- Saída: Registrador IF/ID ----------------------------------------
        if_id_o         : out if_id_reg_t;

        -- ---- Status -----------------------------------------------------------
        -- Sinal para indicar que o fetch está aguardando memória (stall pedido)
        fetch_stall_o   : out std_logic;

        -- Falha de acesso à instrução (AXI SLVERR/DECERR): sinaliza trap mcause=1
        -- fetch_fault_o é um pulso: permanece '1' por 1 ciclo
        fetch_fault_o   : out std_logic;
        fault_pc_o      : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- PC atual (para monitoramento / debug)
        pc_o            : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Branch Predictor: atualização (do estágio Execute) ----------
        -- Acionado 1 ciclo após um branch/JAL/JALR resolver
        bp_upd_en_i       : in  std_logic;
        bp_upd_is_branch_i: in  std_logic;
        bp_upd_pc_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        bp_upd_taken_i    : in  std_logic;
        bp_upd_target_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity fetch_stage;

architecture rtl of fetch_stage is

    -- =========================================================================
    -- Definição da FSM AXI4-Lite Read
    -- =========================================================================
    type fetch_state_t is (
        S_IDLE,         -- Emitir nova requisição de leitura
        S_WAIT_READY,   -- Aguardar arready='1'
        S_WAIT_DATA     -- Aguardar rvalid='1'
    );

    signal state_r      : fetch_state_t;
    signal next_state   : fetch_state_t;

    -- Saídas internas do PC
    signal pc_current   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal pc_plus4     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal next_pc      : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Controle de stall/flush do branch_handler
    signal flush_if_id  : std_logic;
    signal flush_id_ex  : std_logic; -- exposto para o top mas também usado aqui

    -- Internal AXI signals
    signal arvalid_r    : std_logic;
    signal rready_r     : std_logic;

    -- Registrador IF/ID interno
    signal if_id_r      : if_id_reg_t;

    -- Stall combinado: vem de stall_i OU aguardando resposta AXI
    signal stall_fetch  : std_logic;

    -- Endereço do PC que foi enviado na requisição AXI (pode diferir após flush)
    signal pending_pc_r : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Falha de acesso à instrução: pulso quando AXI responde com SLVERR/DECERR
    signal fault_r      : std_logic;
    signal fault_pc_r   : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Branch Predictor outputs (combinacionais)
    signal bp_pred_taken  : std_logic;
    signal bp_pred_target : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- RV32C: Decompressor wires
    -- =========================================================================
    signal decomp_in32  : std_logic_vector(31 downto 0);  -- decompressed instruction
    signal decomp_is_c  : std_logic;                       -- '1' when bits[1:0]!="11"

begin

    -- =========================================================================
    -- Instância: PC Register
    -- =========================================================================
    u_pc_reg : entity work.pc_reg
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            RESET_ADDR => RESET_ADDR
        )
        port map (
            clk_i      => clk_i,
            rst_ni     => rst_ni,
            stall_i    => stall_fetch,
            flush_i    => flush_if_id,
            next_pc_i  => next_pc,
            pc_o       => pc_current,
            pc_plus4_o => pc_plus4
        );

    -- =========================================================================
    -- Instância: Branch Predictor (1-bit + BTB 64 entradas)
    -- =========================================================================
    u_bp : entity work.branch_predictor
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            N_ENTRIES  => 64
        )
        port map (
            clk_i            => clk_i,
            rst_ni           => rst_ni,
            pred_pc_i        => pc_current,
            pred_taken_o     => bp_pred_taken,
            pred_target_o    => bp_pred_target,
            upd_en_i         => bp_upd_en_i,
            upd_is_branch_i  => bp_upd_is_branch_i,
            upd_pc_i         => bp_upd_pc_i,
            upd_taken_i      => bp_upd_taken_i,
            upd_target_i     => bp_upd_target_i
        );

    -- =========================================================================
    -- Instância: RV32C Decompressor (16-bit → 32-bit, purely combinational)
    -- Feeds the IF/ID register when bits[1:0] != "11"
    -- NOTE: Only instructions at 4-byte aligned addresses are handled here.
    --       Full 2-byte aligned RV32C support requires a halfword buffer (TODO).
    -- =========================================================================
    u_decomp : entity work.decompressor
        port map (
            instr16_i     => im_rdata_i(15 downto 0),
            instr32_o     => decomp_in32,
            is_compressed_o => decomp_is_c
        );

    -- =========================================================================
    -- Instância: Branch Handler
    -- =========================================================================
    u_branch_handler : entity work.branch_handler
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            pc_fetch_i       => pc_current,
            pc_plus4_i       => pc_plus4,
            jal_en_i         => jal_en_i,
            jal_target_i     => jal_target_i,
            branch_taken_i   => branch_taken_i,
            branch_target_i  => branch_target_i,
            jalr_en_i        => jalr_en_i,
            jalr_target_i    => jalr_target_i,
            trap_en_i        => trap_en_i,
            trap_target_i    => trap_target_i,
            mret_en_i        => mret_en_i,
            mret_pc_i        => mret_pc_i,
            fence_en_i       => fence_en_i,
            fence_pc_i       => fence_pc_i,
            bp_pred_taken_i  => bp_pred_taken,
            bp_pred_target_i => bp_pred_target,
            next_pc_o        => next_pc,
            flush_if_id_o    => flush_if_id,
            flush_id_ex_o    => flush_id_ex
        );

    -- =========================================================================
    -- FSM AXI4-Lite: controla handshake de leitura da Instruction Memory
    -- =========================================================================

    -- Stall interno: fetch está aguardando resposta da memória
    stall_fetch <= stall_i or
                   '1' when (state_r = S_WAIT_READY or state_r = S_WAIT_DATA) else '0';

    -- Processo de transição de estado
    fsm_seq : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            state_r <= S_IDLE;
        elsif rising_edge(clk_i) then
            state_r <= next_state;
        end if;
    end process fsm_seq;

    -- Lógica de próximo estado e saídas AXI
    fsm_comb : process(state_r, stall_i, im_arready_i, im_rvalid_i, flush_if_id)
    begin
        -- Padrões
        next_state  <= state_r;
        arvalid_r   <= '0';
        rready_r    <= '0';

        case state_r is
            when S_IDLE =>
                if stall_i = '0' then
                    arvalid_r  <= '1';
                    next_state <= S_WAIT_READY;
                end if;

            when S_WAIT_READY =>
                arvalid_r <= '1';
                if im_arready_i = '1' then
                    -- Endereço aceito; aguarda dados
                    next_state <= S_WAIT_DATA;
                end if;
                -- Flush: descarta transação em curso
                if flush_if_id = '1' then
                    next_state <= S_IDLE;
                end if;

            when S_WAIT_DATA =>
                rready_r <= '1';
                if im_rvalid_i = '1' then
                    next_state <= S_IDLE;
                end if;
                -- Flush antes de receber dado: aceita dado mas descarta
                if flush_if_id = '1' and im_rvalid_i = '1' then
                    next_state <= S_IDLE;
                end if;

            when others =>
                next_state <= S_IDLE;
        end case;
    end process fsm_comb;

    -- Captura do PC pendente para envio AXI
    pending_pc_proc : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            pending_pc_r <= RESET_ADDR;
        elsif rising_edge(clk_i) then
            if state_r = S_IDLE and stall_i = '0' then
                pending_pc_r <= pc_current;
            end if;
        end if;
    end process pending_pc_proc;

    -- =========================================================================
    -- Captura do Registrador IF/ID
    -- =========================================================================
    ifid_reg_proc : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            if_id_r  <= IF_ID_NOP;
            fault_r  <= '0';
            fault_pc_r <= (others => '0');
        elsif rising_edge(clk_i) then
            fault_r <= '0'; -- pulso: limpa por padrão a cada ciclo
            if flush_if_id = '1' then
                -- Branch/jump: invalida instrução na saída do fetch
                if_id_r <= IF_ID_NOP;
            elsif stall_i = '1' then
                -- Stall externo: congela registrador
                null;
            elsif state_r = S_WAIT_DATA and im_rvalid_i = '1' then
                -- Instrução recebida com sucesso
                if im_rresp_i = AXI_RESP_OKAY then
                    if_id_r.pc    <= pending_pc_r;
                    if_id_r.valid <= '1';
                    if decomp_is_c = '1' then
                        -- RV32C: Compressed instruction in bits[15:0]
                        -- Decompress and adjust pc_plus4 to PC+2 for correct
                        -- link-address computation (JAL/JALR return address)
                        if_id_r.instruction <= decomp_in32;
                        if_id_r.pc_plus4    <= std_logic_vector(
                            unsigned(pending_pc_r) + 2);
                    else
                        -- Normal 32-bit instruction
                        if_id_r.instruction <= im_rdata_i;
                        if_id_r.pc_plus4    <= std_logic_vector(
                            unsigned(pending_pc_r) + 4);
                    end if;
                else
                    -- Erro de acesso (SLVERR/DECERR): insere bolha e sinaliza trap
                    -- mcause = 1 (Instruction Access Fault)
                    if_id_r    <= IF_ID_NOP;
                    fault_r    <= '1';
                    fault_pc_r <= pending_pc_r;
                end if;
            end if;
        end if;
    end process ifid_reg_proc;

    -- =========================================================================
    -- Mapeamento de Saídas
    -- =========================================================================
    -- AXI4-Lite Read: AR Channel
    im_araddr_o  <= pc_current;
    im_arvalid_o <= arvalid_r;
    im_arprot_o  <= "100"; -- Unprivileged, Secure, Instruction access

    -- AXI4-Lite Read: R Channel
    im_rready_o  <= rready_r;

    -- Saída do registrador de pipeline
    if_id_o      <= if_id_r;

    -- Stall informado para estágios anteriores (aqui não há; exposto para debug)
    fetch_stall_o <= stall_fetch;

    -- Falha de acesso à instrução
    fetch_fault_o <= fault_r;
    fault_pc_o    <= fault_pc_r;

    -- PC atual para debug/trace
    pc_o         <= pc_current;

end architecture rtl;
