-- =============================================================================
-- execute_stage.vhd
-- Estágio 3 do Pipeline: Execute (EX)
--
-- Responsabilidades:
--   - Selecionar operandos da ALU (com forwarding)
--   - Executar operação aritmética/lógica na ALU
--   - Resolver branches condicionais pelo comparador
--   - Calcular endereço de destino de branch/JALR
--   - Produzir o registrador de pipeline EX/MEM
--   - Expor sinais para o branch_handler no Fetch
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity execute_stage is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic;

        -- Stall: congela registrador EX/MEM
        stall_i     : in  std_logic;
        -- Flush: insere bolha (branch taken)
        flush_i     : in  std_logic;

        -- ---- Entrada: Registrador ID/EX -----------------------------------
        id_ex_i     : in  id_ex_reg_t;

        -- ---- Forwarding de estágios posteriores ---------------------------
        -- EX/MEM forward
        exmem_rd_addr_i   : in  std_logic_vector(REG_ADDR_W-1  downto 0);
        exmem_rd_data_i   : in  std_logic_vector(DATA_WIDTH-1  downto 0);
        exmem_reg_write_i : in  std_logic;
        exmem_mem_read_i  : in  std_logic;  -- '1' se instrução em MEM é um load
        -- MEM/WB forward
        memwb_rd_addr_i   : in  std_logic_vector(REG_ADDR_W-1  downto 0);
        memwb_rd_data_i   : in  std_logic_vector(DATA_WIDTH-1  downto 0);
        memwb_reg_write_i : in  std_logic;

        -- ---- Saídas de controle para o Fetch (branch/JALR) ---------------
        branch_taken_o  : out std_logic;
        branch_target_o : out std_logic_vector(DATA_WIDTH-1 downto 0);
        jalr_en_o       : out std_logic;
        jalr_target_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Saída: Registrador EX/MEM ------------------------------------
        ex_mem_o        : out ex_mem_reg_t;

        -- ---- Status -------------------------------------------------------
        load_use_hazard_o : out std_logic;

        -- Resultado bruto da ALU (combinacional, para trap_val no cpu_top)
        alu_result_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Dado lido do CSR (vem do csr_reg, combinacional).
        -- Para instruções CSR (csr_access=1), este valor é escrito em EX/MEM.alu_result
        -- para que o WB_ALU path entregue o valor antigo do CSR ao registrador rd.
        csr_rdata_i     : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Acesso desalinhado detectado (combinacional, antes do registrador EX/MEM)
        -- '1' quando load/store aponta para endereço não alinhado ao tamanho
        misalign_o      : out std_logic
    );
end entity execute_stage;

architecture rtl of execute_stage is

    -- =========================================================================
    -- Forwarding
    -- =========================================================================
    signal fwd_a_sel     : std_logic_vector(1 downto 0);
    signal fwd_b_sel     : std_logic_vector(1 downto 0);

    -- =========================================================================
    -- Operandos selecionados (pós-forwarding)
    -- =========================================================================
    signal rs1_fwd       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rs2_fwd       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal alu_op_a      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal alu_op_b      : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Saídas ALU
    -- =========================================================================
    signal alu_result    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal alu_zero      : std_logic;
    signal alu_sign      : std_logic;
    signal alu_ovf       : std_logic;
    signal alu_carry     : std_logic;

    -- =========================================================================
    -- Branch
    -- =========================================================================
    signal branch_taken  : std_logic;
    signal branch_target : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal jalr_target   : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Registrador EX/MEM
    -- =========================================================================
    signal ex_mem_r      : ex_mem_reg_t;

begin

    -- =========================================================================
    -- Instância: Forwarding Unit
    -- =========================================================================
    u_fwd : entity work.forwarding_unit
        generic map (ADDR_WIDTH => REG_ADDR_W)
        port map (
            ex_rs1_addr_i     => id_ex_i.rs1_addr,
            ex_rs2_addr_i     => id_ex_i.rs2_addr,
            exmem_rd_addr_i   => exmem_rd_addr_i,
            exmem_reg_write_i => exmem_reg_write_i,
            exmem_mem_read_i  => exmem_mem_read_i,
            memwb_rd_addr_i   => memwb_rd_addr_i,
            memwb_reg_write_i => memwb_reg_write_i,
            fwd_a_sel_o       => fwd_a_sel,
            fwd_b_sel_o       => fwd_b_sel,
            load_use_hazard_o => load_use_hazard_o
        );

    -- =========================================================================
    -- Seleção de operandos com forwarding
    -- =========================================================================
    rs1_fwd <= exmem_rd_data_i when fwd_a_sel = "01" else
               memwb_rd_data_i when fwd_a_sel = "10" else
               id_ex_i.rs1_data;

    rs2_fwd <= exmem_rd_data_i when fwd_b_sel = "01" else
               memwb_rd_data_i when fwd_b_sel = "10" else
               id_ex_i.rs2_data;

    -- Mux operando A: registrador ou PC (AUIPC)
    alu_op_a <= id_ex_i.pc when id_ex_i.ctrl.alu_a_src = ALUA_PC else rs1_fwd;

    -- Mux operando B: registrador ou imediato
    alu_op_b <= id_ex_i.imm when id_ex_i.ctrl.alu_src = ALUB_IMM else rs2_fwd;

    -- =========================================================================
    -- Instância: ALU
    -- =========================================================================
    u_alu : entity work.alu
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            operand_a_i => alu_op_a,
            operand_b_i => alu_op_b,
            alu_op_i    => id_ex_i.ctrl.alu_op,
            result_o    => alu_result,
            zero_o      => alu_zero,
            sign_o      => alu_sign,
            ovf_o       => alu_ovf,
            carry_o     => alu_carry
        );

    -- =========================================================================
    -- Instância: Branch Comparator
    -- =========================================================================
    u_bcmp : entity work.branch_comparator
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            rs1_i          => rs1_fwd,
            rs2_i          => rs2_fwd,
            funct3_i       => id_ex_i.ctrl.mem_size, -- funct3 reaproveitado
            branch_en_i    => id_ex_i.ctrl.branch,
            branch_taken_o => branch_taken
        );

    -- =========================================================================
    -- Cálculo dos endereços de destino
    -- =========================================================================
    -- Branch target: PC + imm_B (offset relativo ao PC da instrução de branch)
    branch_target <= std_logic_vector(
                        unsigned(id_ex_i.pc) + unsigned(id_ex_i.imm)
                     );

    -- JALR target: (rs1 + imm_I) AND NOT 1 (força bit 0 = 0)
    jalr_target <= std_logic_vector(
                       unsigned(rs1_fwd) + unsigned(id_ex_i.imm)
                   ) and x"FFFFFFFE";

    -- =========================================================================
    -- Saídas de controle para o Fetch
    -- =========================================================================
    branch_taken_o  <= branch_taken  and id_ex_i.valid;
    branch_target_o <= branch_target;
    jalr_en_o       <= id_ex_i.ctrl.jalr and id_ex_i.valid;
    jalr_target_o   <= jalr_target;

    -- =========================================================================
    -- Resultado bruto da ALU (combinacional) e detecção de acesso desalinhado
    -- RV32I exige alinhamento natural: HW requer addr[0]=0; W requer addr[1:0]="00".
    -- Byte (F3="000"/"100") é sempre alinhado.
    -- =========================================================================
    alu_result_o <= alu_result;

    misalign_o <=
        '1' when id_ex_i.valid = '1' and
                 (id_ex_i.ctrl.mem_read = '1' or id_ex_i.ctrl.mem_write = '1') and
                 ((id_ex_i.ctrl.mem_size(1 downto 0) = "01" and alu_result(0) /= '0') or
                  (id_ex_i.ctrl.mem_size(1 downto 0) = "10" and alu_result(1 downto 0) /= "00"))
        else '0';

    -- =========================================================================
    -- Registrador de Pipeline EX/MEM
    -- =========================================================================
    exmem_reg : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            ex_mem_r <= EX_MEM_NOP;
        elsif rising_edge(clk_i) then
            if flush_i = '1' then
                -- Inserir bolha
                ex_mem_r <= (
                    pc           => id_ex_i.pc,
                    pc_plus4     => id_ex_i.pc_plus4,
                    alu_result   => (others => '0'),
                    rs2_data     => (others => '0'),
                    rd_addr      => (others => '0'),
                    branch_tgt   => (others => '0'),
                    branch_taken => '0',
                    ctrl         => CTRL_NOP,
                    valid        => '0'
                );
            elsif stall_i = '0' then
                ex_mem_r.pc           <= id_ex_i.pc;
                ex_mem_r.pc_plus4     <= id_ex_i.pc_plus4;
                -- Instruções CSR: alu_result transporta o VALOR ANTIGO do CSR (para rd).
                -- Para todas as outras, usa o resultado da ALU.
                ex_mem_r.alu_result   <= csr_rdata_i when id_ex_i.ctrl.csr_access = '1'
                                         else alu_result;
                ex_mem_r.rs2_data     <= rs2_fwd; -- dado para store (após fwd)
                ex_mem_r.rd_addr      <= id_ex_i.rd_addr;
                ex_mem_r.branch_tgt   <= branch_target;
                ex_mem_r.branch_taken <= branch_taken;
                ex_mem_r.ctrl         <= id_ex_i.ctrl;
                ex_mem_r.valid        <= id_ex_i.valid;
            end if;
        end if;
    end process exmem_reg;

    ex_mem_o <= ex_mem_r;

end architecture rtl;
