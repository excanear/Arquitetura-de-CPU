-- =============================================================================
-- cpu_top.vhd
-- Topo da CPU RISC-V RV32I – Pipeline de 5 Estágios (In-Order)
--
-- Hierarquia de instâncias:
--   cpu_top
--   ├── u_fetch    : fetch_stage
--   │   ├── u_pc_reg         : pc_reg
--   │   └── u_branch_handler : branch_handler
--   ├── u_decode   : decode_stage
--   │   ├── u_decoder        : instruction_decoder
--   │   ├── u_imm_gen        : immediate_generator
--   │   └── u_regfile        : register_file
--   ├── u_execute  : execute_stage
--   │   ├── u_fwd            : forwarding_unit
--   │   ├── u_alu            : alu
--   │   └── u_bcmp           : branch_comparator
--   ├── u_memory   : memory_stage
--   │   └── u_lsu            : load_store_unit
--   ├── u_writeback: writeback_stage
--   ├── u_csr      : csr_reg
--   └── u_mmu      : mmu
--
-- Interfaces externas:
--   - AXI4-Lite para Instruction Memory (via icache → AXI)
--   - AXI4-Lite para Data Memory        (via dcache → AXI)
--   - Interrupção externa, timer e software (via mie/mip CSR + irq_pending_o)
--
-- Exceções/traps implementados (mcause):
--   0x1  Instruction Access Fault    (AXI SLVERR/DECERR no fetch)
--   0x2  Illegal Instruction
--   0x3  Breakpoint (EBREAK)
--   0x4  Load Address Misaligned
--   0x6  Store Address Misaligned
--   0xB  Environment Call (ECALL M-mode)
--   0x8000000B  External Interrupt (MEIP)
--   0x80000007  Timer Interrupt    (MTIP)
--   0x80000003  Software Interrupt (MSIP)
--
-- Notas de expansão:
--   - Branch Predictor: substitui "always-not-taken" atual
--   - Out-of-Order: substitui registradores de pipeline por ROB/RS
--   - iCache/dCache: ENABLE_TAGS=true ativa tag-checking + miss handling
--   - MMU Sv32: ENABLE_VM=true no u_mmu (requer page table walker + TLB)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity cpu_top is
    generic (
        DATA_WIDTH   : integer := XLEN;
        RESET_ADDR   : std_logic_vector(XLEN-1 downto 0) := PC_RESET;
        HART_ID      : integer := 0
    );
    port (
        -- Controle global
        clk_i        : in  std_logic;
        rst_ni       : in  std_logic;  -- Reset ativo-baixo, síncrono

        -- ---- Interface AXI4-Lite – Instruction Memory (Master) -----------
        -- AR Channel
        im_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        im_arvalid_o : out std_logic;
        im_arprot_o  : out std_logic_vector(2 downto 0);
        im_arready_i : in  std_logic;
        -- R Channel
        im_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        im_rresp_i   : in  std_logic_vector(1 downto 0);
        im_rvalid_i  : in  std_logic;
        im_rready_o  : out std_logic;

        -- ---- Interface AXI4-Lite – Data Memory (Master) ------------------
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

        -- ---- Interrupção externa (nível) ---------------------------------
        irq_external_i : in  std_logic;
        irq_timer_i    : in  std_logic;
        irq_software_i : in  std_logic;

        -- ---- Status/Debug (opcional) ------------------------------------
        pc_o           : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity cpu_top;

architecture rtl of cpu_top is

    -- =========================================================================
    -- Registradores de pipeline (saídas de cada estágio)
    -- =========================================================================
    signal if_id_s  : if_id_reg_t;
    signal id_ex_s  : id_ex_reg_t;
    signal ex_mem_s : ex_mem_reg_t;
    signal mem_wb_s : mem_wb_reg_t;

    -- =========================================================================
    -- Sinais de controle de branch/jump (Fetch ← Execute/Decode)
    -- =========================================================================
    signal jal_en_s        : std_logic;
    signal jal_tgt_s       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal branch_taken_s  : std_logic;
    signal branch_target_s : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal jalr_en_s       : std_logic;
    signal jalr_target_s   : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Sinais de flush (branch handler → estágios)
    -- Nota: flush_if_id e flush_id_ex são gerados internamente pelo
    -- branch_handler dentro do fetch_stage. Aqui usamos os equivalentes
    -- derivados dos sinais de controle acima.
    -- =========================================================================
    -- Flush efetivo: qualquer redirecionamento de PC
    signal flush_pipeline_s : std_logic;

    -- =========================================================================
    -- Sinais de stall
    -- =========================================================================
    signal fetch_stall_s   : std_logic; -- Fetch aguardando AXI IM
    signal mem_stall_s     : std_logic; -- Memory aguardando AXI DM
    signal load_use_haz_s  : std_logic; -- Load-use hazard detectado
    signal global_stall_s  : std_logic; -- Stall global para todos estágios

    -- =========================================================================
    -- Writeback → Decode (register file write)
    -- =========================================================================
    signal wb_rd_addr_s   : std_logic_vector(REG_ADDR_W-1 downto 0);
    signal wb_rd_data_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal wb_rd_we_s     : std_logic;

    -- =========================================================================
    -- Forwarding → Execute (MEM/WB)
    -- =========================================================================
    signal fwd_memwb_addr_s : std_logic_vector(REG_ADDR_W-1 downto 0);
    signal fwd_memwb_data_s : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fwd_memwb_we_s   : std_logic;

    -- =========================================================================
    -- CSR
    -- =========================================================================
    signal csr_rdata_s    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal csr_illegal_s  : std_logic;
    signal trap_en_s      : std_logic;
    signal trap_cause_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal trap_val_s     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal trap_pc_s      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal trap_target_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mret_pc_s      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mret_en_s      : std_logic;
    signal sret_en_s      : std_logic;
    signal sret_pc_s      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ret_en_s       : std_logic;  -- mret OR sret
    signal ret_pc_s       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal instret_inc_s  : std_logic;

    -- MMU
    signal instr_paddr_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal data_paddr_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mmu_stall_s    : std_logic;
    signal instr_pf_s     : std_logic;  -- mcause 12: instruction page fault
    signal data_pf_s      : std_logic;  -- mcause 13/15: load/store page fault
    -- MMU Page Table Walk – AXI4-Lite Read (mestre, conectado ao barramento DM)
    signal ptw_araddr_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ptw_arvalid_s  : std_logic;
    signal ptw_arready_s  : std_logic;
    signal ptw_rdata_s    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ptw_rvalid_s   : std_logic;
    signal ptw_rready_s   : std_logic;
    -- Sinais do CSR para o MMU
    signal satp_s         : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal privilege_s    : std_logic_vector(1 downto 0);
    signal mxr_s          : std_logic;
    signal sum_s          : std_logic;

    -- Interrupções
    signal irq_pending_s  : std_logic;
    signal irq_cause_s    : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- FENCE.I: flush de pipeline para coesão instrucção/dado
    signal fence_en_s     : std_logic;
    signal fence_pc_s     : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Branch Predictor: sinais de atualização (do estágio EX/MEM)
    signal bp_upd_en_s        : std_logic;
    signal bp_upd_is_branch_s : std_logic;
    signal bp_upd_pc_s        : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal bp_upd_taken_s     : std_logic;
    signal bp_upd_target_s    : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Acesso desalinhado (combinacional, do execute_stage)
    signal misalign_s      : std_logic;
    signal misalign_addr_s : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Falha de acesso à instrução (AXI error no fetch)
    signal fetch_fault_s   : std_logic;
    signal fetch_fault_pc_s: std_logic_vector(DATA_WIDTH-1 downto 0);

    -- PC atual (debug)
    signal pc_s : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- =========================================================================
    -- Barramentos AXI internos (entre fetch_stage e icache / LSU e dcache)
    -- Nomeados com prefixo "i_" (instrução) e "d_" (dado)
    -- =========================================================================
    -- icache – slave side (do fetch_stage)
    signal i_araddr_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal i_arvalid_s : std_logic;
    signal i_arprot_s  : std_logic_vector(2 downto 0);
    signal i_arready_s : std_logic;
    signal i_rdata_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal i_rresp_s   : std_logic_vector(1 downto 0);
    signal i_rvalid_s  : std_logic;
    signal i_rready_s  : std_logic;

    -- dcache – slave side (do memory_stage/LSU)
    signal d_araddr_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal d_arvalid_s : std_logic;
    signal d_arprot_s  : std_logic_vector(2 downto 0);
    signal d_arready_s : std_logic;
    signal d_rdata_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal d_rresp_s   : std_logic_vector(1 downto 0);
    signal d_rvalid_s  : std_logic;
    signal d_rready_s  : std_logic;
    signal d_awaddr_s  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal d_awvalid_s : std_logic;
    signal d_awprot_s  : std_logic_vector(2 downto 0);
    signal d_awready_s : std_logic;
    signal d_wdata_s   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal d_wstrb_s   : std_logic_vector(3 downto 0);
    signal d_wvalid_s  : std_logic;
    signal d_wready_s  : std_logic;
    signal d_bresp_s   : std_logic_vector(1 downto 0);
    signal d_bvalid_s  : std_logic;
    signal d_bready_s  : std_logic;

begin

    -- =========================================================================
    -- Stall global: qualquer fonte de stall paralisa o pipeline inteiro
    -- (simplificação in-order; futuramente diferenciado por estágio)
    -- =========================================================================
    global_stall_s <= fetch_stall_s or mem_stall_s or load_use_haz_s or mmu_stall_s;

    -- Flush: gerado quando branch/jump/trap/mret/sret/fence redireciona o PC
    flush_pipeline_s <= branch_taken_s or jalr_en_s or trap_en_s or ret_en_s or fence_en_s;

    -- =========================================================================
    -- CSR: construção do acesso a partir do estágio ID/EX
    -- Nota: O acesso CSR ocorre no Execute (instrução em id_ex_s)
    -- =========================================================================
    -- Exceções síncronas: requerem instrução válida em EX.
    -- Interrupções: aceitas também quando EX tem bolha (evita latência indefinida).
    -- global_stall_s: pipeline travado, adiar o trap para não corromper estado.
    trap_en_s    <= ((id_ex_s.ctrl.ecall or id_ex_s.ctrl.ebreak or
                      csr_illegal_s or misalign_s or fetch_fault_s or
                      instr_pf_s or data_pf_s) and id_ex_s.valid)
                  or (irq_pending_s and not global_stall_s);

    -- PC salvo em mepc:
    --   Instr. access fault -> PC do fetch (endereço que falhou)
    --   Interrupção com bolha em EX -> usar PC do IF/ID (1a instrução não executada)
    --   Exceção ou IRQ com instrucção válida em EX -> PC da instrucção em EX
    trap_pc_s    <= fetch_fault_pc_s when fetch_fault_s = '1'
                               else if_id_s.pc when (irq_pending_s = '1' and id_ex_s.valid = '0')
                               else id_ex_s.pc;

    -- Valor de trap (mtval): endereço defeituoso para desalinhamentos e instruction fault
    trap_val_s   <= fetch_fault_pc_s when fetch_fault_s  = '1' else
                    misalign_addr_s  when misalign_s      = '1' else
                    (others => '0');

    -- Causa: exceções síncronas têm prioridade sobre interrupções
    trap_cause_s <= x"00000001" when fetch_fault_s='1'                               else -- instruction access fault
                    x"0000000C" when instr_pf_s='1'    and id_ex_s.valid='1'         else -- instruction page fault
                    x"0000000B" when id_ex_s.ctrl.ecall='1' and id_ex_s.valid='1' and privilege_s="11" else -- ecall M-mode
                    x"00000009" when id_ex_s.ctrl.ecall='1' and id_ex_s.valid='1' and privilege_s="01" else -- ecall S-mode
                    x"00000008" when id_ex_s.ctrl.ecall='1' and id_ex_s.valid='1'                     else -- ecall U-mode
                    x"00000003" when id_ex_s.ctrl.ebreak='1' and id_ex_s.valid='1'  else -- breakpoint
                    x"00000004" when misalign_s='1' and id_ex_s.ctrl.mem_read='1'   else -- load misalign
                    x"00000006" when misalign_s='1' and id_ex_s.ctrl.mem_write='1'  else -- store misalign
                    x"0000000D" when data_pf_s='1' and id_ex_s.ctrl.mem_read='1'    else -- load page fault
                    x"0000000F" when data_pf_s='1' and id_ex_s.ctrl.mem_write='1'   else -- store/AMO page fault
                    x"00000002" when csr_illegal_s='1'        and id_ex_s.valid='1' else -- illegal
                    irq_cause_s;                                                          -- interrupção

    -- FENCE.I: redireciona para PC+4 após o FENCE, forando flush do pipeline
    fence_en_s   <= id_ex_s.ctrl.fence and id_ex_s.valid;
    fence_pc_s   <= id_ex_s.pc_plus4;

    mret_en_s    <= id_ex_s.ctrl.mret and id_ex_s.valid;  -- MRET decodificado no ID/EX
    sret_en_s    <= id_ex_s.ctrl.sret and id_ex_s.valid;  -- SRET (S-mode return)
    ret_en_s     <= mret_en_s or sret_en_s;
    ret_pc_s     <= mret_pc_s when mret_en_s = '1' else sret_pc_s;

    -- Instrução retirada (WB stage valid)
    instret_inc_s <= mem_wb_s.valid;

    -- =========================================================================
    -- Branch Predictor Update
    -- Quando um branch, JAL ou JALR resolve em EX/MEM, atualiza o preditor.
    -- ex_mem_s.branch_taken indica branch tomado; JAL/JALR são sempre tomados.
    -- =========================================================================
    bp_upd_en_s        <= ex_mem_s.valid and
                          (ex_mem_s.ctrl.branch or ex_mem_s.ctrl.jal or ex_mem_s.ctrl.jalr);
    bp_upd_is_branch_s <= ex_mem_s.ctrl.branch or ex_mem_s.ctrl.jal or ex_mem_s.ctrl.jalr;
    bp_upd_pc_s        <= ex_mem_s.pc;
    bp_upd_taken_s     <= ex_mem_s.branch_taken when ex_mem_s.ctrl.branch = '1'
                          else '1'; -- JAL/JALR são sempre tomados
    -- Alvo: para branch usa branch_tgt; para JALR usa alu_result
    bp_upd_target_s    <= ex_mem_s.alu_result when ex_mem_s.ctrl.jalr = '1'
                          else ex_mem_s.branch_tgt;

    -- =========================================================================
    -- Instância: MMU
    -- =========================================================================
    -- =========================================================================
    -- PTW AXI: quando ENABLE_VM=false, ptw_arvalid_s nunca sobe; o barramento
    -- fica quiescente. Quando ENABLE_VM=true, os sinais ptw_* precisam ser
    -- arbitrados com o barramento DM. Por simplicidade conectamos direto ao DM
    -- externo usando os canais AR/R (leitura apenas) e travamos o canal W.
    -- Um árbitro round-robin real seria necessário em produção.
    -- =========================================================================
    -- Para o modo bare (ENABLE_VM=false): PTW nunca emite transações → arvalid=0
    -- → barramento DM não é perturbado.
    ptw_arready_s <= dm_arready_i  when ptw_arvalid_s = '1' else '0';
    ptw_rdata_s   <= dm_rdata_i;
    ptw_rvalid_s  <= dm_rvalid_i   when ptw_arvalid_s = '1' else '0';

    u_mmu : entity work.mmu
        generic map (
            DATA_WIDTH  => DATA_WIDTH,
            ENABLE_VM   => false,   -- true = Sv32 PTW ativo; false = bare
            TLB_ENTRIES => 16
        )
        port map (
            clk_i              => clk_i,
            rst_ni             => rst_ni,
            -- Endereços virtuais
            instr_vaddr_i      => pc_s,
            data_vaddr_i       => ex_mem_s.alu_result,
            -- Controle de operação
            instr_req_i        => i_arvalid_s,
            data_req_i         => ex_mem_s.valid,
            data_we_i          => ex_mem_s.ctrl.mem_write,
            -- Endereços físicos
            instr_paddr_o      => instr_paddr_s,
            data_paddr_o       => data_paddr_s,
            -- Stall
            ptw_stall_o        => mmu_stall_s,
            -- Descarte de TLB
            sfence_vma_i       => id_ex_s.ctrl.sfence_vma,
            -- Page faults
            instr_page_fault_o => instr_pf_s,
            data_page_fault_o  => data_pf_s,
            -- Configuração
            satp_i             => satp_s,
            privilege_i        => privilege_s,
            mxr_i              => mxr_s,
            sum_i              => sum_s,
            -- AXI PTW
            ptw_araddr_o       => ptw_araddr_s,
            ptw_arvalid_o      => ptw_arvalid_s,
            ptw_arready_i      => ptw_arready_s,
            ptw_rdata_i        => ptw_rdata_s,
            ptw_rvalid_i       => ptw_rvalid_s,
            ptw_rready_o       => ptw_rready_s
        );

    -- =========================================================================
    -- Instância: Fetch Stage
    -- =========================================================================
    u_fetch : entity work.fetch_stage
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            RESET_ADDR => RESET_ADDR
        )
        port map (
            clk_i           => clk_i,
            rst_ni          => rst_ni,
            stall_i         => global_stall_s,
            jal_en_i        => jal_en_s,
            jal_target_i    => jal_tgt_s,
            branch_taken_i  => branch_taken_s,
            branch_target_i => branch_target_s,
            jalr_en_i       => jalr_en_s,
            jalr_target_i   => jalr_target_s,
            trap_en_i       => trap_en_s,
            trap_target_i   => trap_target_s,
            mret_en_i       => ret_en_s,
            mret_pc_i       => ret_pc_s,
            fence_en_i      => fence_en_s,
            fence_pc_i      => fence_pc_s,
            im_araddr_o     => i_araddr_s,
            im_arvalid_o    => i_arvalid_s,
            im_arprot_o     => i_arprot_s,
            im_arready_i    => i_arready_s,
            im_rdata_i      => i_rdata_s,
            im_rresp_i      => i_rresp_s,
            im_rvalid_i     => i_rvalid_s,
            im_rready_o     => i_rready_s,
            if_id_o         => if_id_s,
            fetch_stall_o   => fetch_stall_s,
            fetch_fault_o   => fetch_fault_s,
            fault_pc_o      => fetch_fault_pc_s,
            pc_o            => pc_s,
            -- Branch Predictor update
            bp_upd_en_i         => bp_upd_en_s,
            bp_upd_is_branch_i  => bp_upd_is_branch_s,
            bp_upd_pc_i         => bp_upd_pc_s,
            bp_upd_taken_i      => bp_upd_taken_s,
            bp_upd_target_i     => bp_upd_target_s
        );

    -- =========================================================================
    -- Instância: Instruction Cache (icache)
    -- Interpositionão entre fetch_stage AXI e barramento externo IM
    -- =========================================================================
    u_icache : entity work.icache
        generic map (
            DATA_WIDTH  => DATA_WIDTH,
            N_LINES     => 256,
            LINE_WORDS  => 4,
            ENABLE_TAGS => false  -- true = cache real; false = passthrough
        )
        port map (
            clk_i        => clk_i,
            rst_ni       => rst_ni,
            -- Slave (do fetch_stage)
            cpu_araddr_i  => i_araddr_s,
            cpu_arvalid_i => i_arvalid_s,
            cpu_arprot_i  => i_arprot_s,
            cpu_arready_o => i_arready_s,
            cpu_rdata_o   => i_rdata_s,
            cpu_rresp_o   => i_rresp_s,
            cpu_rvalid_o  => i_rvalid_s,
            cpu_rready_i  => i_rready_s,
            -- Master (para IM externo)
            mem_araddr_o  => im_araddr_o,
            mem_arvalid_o => im_arvalid_o,
            mem_arprot_o  => im_arprot_o,
            mem_arready_i => im_arready_i,
            mem_rdata_i   => im_rdata_i,
            mem_rresp_i   => im_rresp_i,
            mem_rvalid_i  => im_rvalid_i,
            mem_rready_o  => im_rready_o,
            -- Flush FENCE.I
            flush_i       => fence_en_s
        );

    -- =========================================================================
    -- Instância: Decode Stage
    -- =========================================================================
    u_decode : entity work.decode_stage
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            clk_i        => clk_i,
            rst_ni       => rst_ni,
            stall_i      => global_stall_s,
            flush_i      => flush_pipeline_s,
            if_id_i      => if_id_s,
            wb_rd_addr_i => wb_rd_addr_s,
            wb_rd_data_i => wb_rd_data_s,
            wb_rd_we_i   => wb_rd_we_s,
            jal_en_o     => jal_en_s,
            jal_tgt_o    => jal_tgt_s,
            id_ex_o      => id_ex_s
        );

    -- =========================================================================
    -- Instância: Execute Stage
    -- =========================================================================
    u_execute : entity work.execute_stage
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            clk_i             => clk_i,
            rst_ni            => rst_ni,
            stall_i           => mem_stall_s,  -- stall pelo MEM
            flush_i           => trap_en_s,     -- trap: cancela escrita da instrução corrente
            id_ex_i           => id_ex_s,
            -- Forwarding EX/MEM
            exmem_rd_addr_i   => ex_mem_s.rd_addr,
            exmem_rd_data_i   => ex_mem_s.alu_result,
            exmem_reg_write_i => ex_mem_s.ctrl.reg_write,
            exmem_mem_read_i  => ex_mem_s.ctrl.mem_read,
            -- Forwarding MEM/WB
            memwb_rd_addr_i   => fwd_memwb_addr_s,
            memwb_rd_data_i   => fwd_memwb_data_s,
            memwb_reg_write_i => fwd_memwb_we_s,
            -- Branch outputs
            branch_taken_o    => branch_taken_s,
            branch_target_o   => branch_target_s,
            jalr_en_o         => jalr_en_s,
            jalr_target_o     => jalr_target_s,
            ex_mem_o          => ex_mem_s,
            load_use_hazard_o => load_use_haz_s,
            csr_rdata_i       => csr_rdata_s,
            alu_result_o      => misalign_addr_s,
            misalign_o        => misalign_s
        );

    -- =========================================================================
    -- Instância: Memory Stage
    -- =========================================================================
    u_memory : entity work.memory_stage
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            clk_i        => clk_i,
            rst_ni       => rst_ni,
            stall_i      => '0',
            -- FENCE: descarta instrução de FENCE do registrador MEM/WB
            -- e garantirá flush do dcache quando ele for integrado (ENABLE_TAGS)
            flush_i      => fence_en_s,
            ex_mem_i     => ex_mem_s,
            -- AXI AR
            dm_araddr_o  => d_araddr_s,
            dm_arvalid_o => d_arvalid_s,
            dm_arprot_o  => d_arprot_s,
            dm_arready_i => d_arready_s,
            -- AXI R
            dm_rdata_i   => d_rdata_s,
            dm_rresp_i   => d_rresp_s,
            dm_rvalid_i  => d_rvalid_s,
            dm_rready_o  => d_rready_s,
            -- AXI AW
            dm_awaddr_o  => d_awaddr_s,
            dm_awvalid_o => d_awvalid_s,
            dm_awprot_o  => d_awprot_s,
            dm_awready_i => d_awready_s,
            -- AXI W
            dm_wdata_o   => d_wdata_s,
            dm_wstrb_o   => d_wstrb_s,
            dm_wvalid_o  => d_wvalid_s,
            dm_wready_i  => d_wready_s,
            -- AXI B
            dm_bresp_i   => d_bresp_s,
            dm_bvalid_i  => d_bvalid_s,
            dm_bready_o  => d_bready_s,
            mem_stall_o  => mem_stall_s,
            mem_wb_o     => mem_wb_s
        );

    -- =========================================================================
    -- Instância: Data Cache (dcache)
    -- Interpositionão entre memory_stage AXI e barramento externo DM
    -- =========================================================================
    u_dcache : entity work.dcache
        generic map (
            DATA_WIDTH  => DATA_WIDTH,
            N_LINES     => 256,
            LINE_WORDS  => 4,
            ENABLE_TAGS => false  -- true = cache real; false = passthrough
        )
        port map (
            clk_i        => clk_i,
            rst_ni       => rst_ni,
            -- Slave (do memory_stage/LSU)
            cpu_araddr_i  => d_araddr_s,
            cpu_arvalid_i => d_arvalid_s,
            cpu_arprot_i  => d_arprot_s,
            cpu_arready_o => d_arready_s,
            cpu_rdata_o   => d_rdata_s,
            cpu_rresp_o   => d_rresp_s,
            cpu_rvalid_o  => d_rvalid_s,
            cpu_rready_i  => d_rready_s,
            cpu_awaddr_i  => d_awaddr_s,
            cpu_awvalid_i => d_awvalid_s,
            cpu_awprot_i  => d_awprot_s,
            cpu_awready_o => d_awready_s,
            cpu_wdata_i   => d_wdata_s,
            cpu_wstrb_i   => d_wstrb_s,
            cpu_wvalid_i  => d_wvalid_s,
            cpu_wready_o  => d_wready_s,
            cpu_bresp_o   => d_bresp_s,
            cpu_bvalid_o  => d_bvalid_s,
            cpu_bready_i  => d_bready_s,
            -- Master (para DM externo)
            mem_araddr_o  => dm_araddr_o,
            mem_arvalid_o => dm_arvalid_o,
            mem_arprot_o  => dm_arprot_o,
            mem_arready_i => dm_arready_i,
            mem_rdata_i   => dm_rdata_i,
            mem_rresp_i   => dm_rresp_i,
            mem_rvalid_i  => dm_rvalid_i,
            mem_rready_o  => dm_rready_o,
            mem_awaddr_o  => dm_awaddr_o,
            mem_awvalid_o => dm_awvalid_o,
            mem_awprot_o  => dm_awprot_o,
            mem_awready_i => dm_awready_i,
            mem_wdata_o   => dm_wdata_o,
            mem_wstrb_o   => dm_wstrb_o,
            mem_wvalid_o  => dm_wvalid_o,
            mem_wready_i  => dm_wready_i,
            mem_bresp_i   => dm_bresp_i,
            mem_bvalid_i  => dm_bvalid_i,
            mem_bready_o  => dm_bready_o,
            -- Flush FENCE/FENCE.I
            flush_i       => fence_en_s
        );

    -- =========================================================================
    -- Instância: Writeback Stage
    -- =========================================================================
    u_writeback : entity work.writeback_stage
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            mem_wb_i      => mem_wb_s,
            rd_addr_o     => wb_rd_addr_s,
            rd_data_o     => wb_rd_data_s,
            rd_we_o       => wb_rd_we_s,
            fwd_rd_addr_o => fwd_memwb_addr_s,
            fwd_rd_data_o => fwd_memwb_data_s,
            fwd_rd_we_o   => fwd_memwb_we_s
        );

    -- =========================================================================
    -- Instância: CSR Register File
    -- =========================================================================
    u_csr : entity work.csr_reg
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            HART_ID    => HART_ID,
            VENDOR_ID  => (others => '0'),
            ARCH_ID    => (others => '0'),
            IMP_ID     => (others => '0')
        )
        port map (
            clk_i         => clk_i,
            rst_ni        => rst_ni,
            -- Acesso CSR vem da instrução em EX (id_ex_s contém a instrução)
            csr_addr_i    => id_ex_s.imm(11 downto 0),
            csr_wdata_i   => id_ex_s.rs1_data,
            csr_op_i      => id_ex_s.ctrl.mem_size, -- funct3 reaproveitado
            csr_we_i      => id_ex_s.ctrl.csr_access,
            csr_re_i      => id_ex_s.ctrl.csr_access,
            csr_uimm_i    => id_ex_s.rs1_addr,      -- zimm = rs1 field
            csr_rdata_o   => csr_rdata_s,
            csr_illegal_o => csr_illegal_s,
            trap_en_i     => trap_en_s,
            trap_cause_i  => trap_cause_s,
            trap_val_i    => trap_val_s,
            trap_pc_i     => trap_pc_s,
            trap_target_o => trap_target_s,
            mret_pc_o     => mret_pc_s,
            mret_en_i     => mret_en_s,
            sret_pc_o     => sret_pc_s,
            sret_en_i     => sret_en_s,
            instret_inc_i => instret_inc_s,
            irq_external_i => irq_external_i,
            irq_timer_i    => irq_timer_i,
            irq_software_i => irq_software_i,
            irq_pending_o  => irq_pending_s,
            irq_cause_o    => irq_cause_s,
            -- Saídas de estado para o MMU
            satp_o         => satp_s,
            privilege_o    => privilege_s,
            mxr_o          => mxr_s,
            sum_o          => sum_s
        );

    -- =========================================================================
    -- Saídas de status
    -- =========================================================================
    pc_o <= pc_s;

end architecture rtl;
