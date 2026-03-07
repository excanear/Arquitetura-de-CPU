-- =============================================================================
-- decode_stage.vhd
-- Estágio 2 do Pipeline: Instruction Decode (ID)
--
-- Responsabilidades:
--   - Decodificar instrução recebida do registrador IF/ID
--   - Ler operandos do banco de registradores
--   - Gerar imediato estendido em sinal
--   - Calcular destino de JAL (relativo ao PC) para enviar ao branch_handler
--   - Produzir o registrador de pipeline ID/EX
--   - Aceitar flush (branch taken) e stall (hazard de dados)
--
-- Interação com hazard detection (futuro):
--   A unidade de detecção de hazards (HDU) deverá inserir bolhas (stall)
--   na saída deste estágio quando detectar load-use hazards.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity decode_stage is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic;

        -- Stall: congela registrador ID/EX (load-use hazard)
        stall_i     : in  std_logic;
        -- Flush: insere bolha no ID/EX (branch/jump tomado)
        flush_i     : in  std_logic;

        -- ---- Entrada: Registrador IF/ID ------------------------------------
        if_id_i     : in  if_id_reg_t;

        -- ---- Porta de writeback do Register File (vem do estágio WB) ------
        wb_rd_addr_i : in  std_logic_vector(REG_ADDR_W-1 downto 0);
        wb_rd_data_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_rd_we_i   : in  std_logic;

        -- ---- Saída: destino de JAL (para o branch_handler no fetch) -------
        jal_en_o    : out std_logic;
        jal_tgt_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Saída: Registrador ID/EX ------------------------------------
        id_ex_o     : out id_ex_reg_t
    );
end entity decode_stage;

architecture rtl of decode_stage is

    -- =========================================================================
    -- Sinais decodificados (saídas do instruction_decoder)
    -- =========================================================================
    signal dec_opcode  : std_logic_vector(6 downto 0);
    signal dec_rd      : std_logic_vector(REG_ADDR_W-1 downto 0);
    signal dec_rs1     : std_logic_vector(REG_ADDR_W-1 downto 0);
    signal dec_rs2     : std_logic_vector(REG_ADDR_W-1 downto 0);
    signal dec_funct3  : std_logic_vector(2 downto 0);
    signal dec_funct7  : std_logic_vector(6 downto 0);
    signal dec_imm_type: imm_type_t;
    signal dec_ctrl    : ctrl_signals_t;

    -- =========================================================================
    -- Sinais do immediate generator
    -- =========================================================================
    signal imm_out     : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Sinais do register file
    -- =========================================================================
    signal rs1_data    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rs2_data    : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Registrador ID/EX interno
    -- =========================================================================
    signal id_ex_r     : id_ex_reg_t;

begin

    -- =========================================================================
    -- Instância: Instruction Decoder
    -- =========================================================================
    u_decoder : entity work.instruction_decoder
        port map (
            instr_i    => if_id_i.instruction,
            opcode_o   => dec_opcode,
            rd_o       => dec_rd,
            rs1_o      => dec_rs1,
            rs2_o      => dec_rs2,
            funct3_o   => dec_funct3,
            funct7_o   => dec_funct7,
            imm_type_o => dec_imm_type,
            ctrl_o     => dec_ctrl
        );

    -- =========================================================================
    -- Instância: Immediate Generator
    -- =========================================================================
    u_imm_gen : entity work.immediate_generator
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            instr_i    => if_id_i.instruction,
            imm_type_i => dec_imm_type,
            imm_o      => imm_out
        );

    -- =========================================================================
    -- Instância: Register File
    -- =========================================================================
    u_regfile : entity work.register_file
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            ADDR_WIDTH   => REG_ADDR_W,
            ASYNC_READ   => true,
            INTERNAL_FWD => true
        )
        port map (
            clk_i      => clk_i,
            rst_ni     => rst_ni,
            rs1_addr_i => dec_rs1,
            rs1_data_o => rs1_data,
            rs2_addr_i => dec_rs2,
            rs2_data_o => rs2_data,
            rd_addr_i  => wb_rd_addr_i,
            rd_data_i  => wb_rd_data_i,
            rd_we_i    => wb_rd_we_i
        );

    -- =========================================================================
    -- Cálculo do destino JAL (combinacional, para o branch_handler no Fetch)
    -- target = PC + sign_extend(imm_J)
    -- =========================================================================
    jal_en_o  <= dec_ctrl.jal and if_id_i.valid;
    jal_tgt_o <= std_logic_vector(
                    unsigned(if_id_i.pc) + unsigned(imm_out)
                 );

    -- =========================================================================
    -- Registrador de Pipeline ID/EX
    -- =========================================================================
    idex_reg : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            id_ex_r <= ID_EX_NOP;
        elsif rising_edge(clk_i) then
            if flush_i = '1' then
                -- Inserir bolha (NOP) no estágio Execute
                id_ex_r <= (
                    pc       => if_id_i.pc,
                    pc_plus4 => if_id_i.pc_plus4,
                    rs1_data => (others => '0'),
                    rs2_data => (others => '0'),
                    imm      => (others => '0'),
                    rs1_addr => (others => '0'),
                    rs2_addr => (others => '0'),
                    rd_addr  => (others => '0'),
                    ctrl     => CTRL_NOP,
                    valid    => '0'
                );
            elsif stall_i = '0' then
                -- Captura normal
                id_ex_r.pc       <= if_id_i.pc;
                id_ex_r.pc_plus4 <= if_id_i.pc_plus4;
                id_ex_r.rs1_data <= rs1_data;
                id_ex_r.rs2_data <= rs2_data;
                id_ex_r.imm      <= imm_out;
                id_ex_r.rs1_addr <= dec_rs1;
                id_ex_r.rs2_addr <= dec_rs2;
                id_ex_r.rd_addr  <= dec_rd;
                id_ex_r.ctrl     <= dec_ctrl;
                id_ex_r.valid    <= if_id_i.valid;
            end if;
            -- stall_i='1': registrador congelado
        end if;
    end process idex_reg;

    id_ex_o <= id_ex_r;

end architecture rtl;
