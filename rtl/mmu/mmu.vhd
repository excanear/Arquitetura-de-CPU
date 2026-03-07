-- =============================================================================
-- mmu.vhd
-- Memory Management Unit – RV32I / Sv32
--
-- Modos de operação (controlado pelo generic ENABLE_VM + satp.MODE em runtime):
--   Bare  : satp.MODE=0  → endereço físico = endereço virtual (passthrough)
--   Sv32  : satp.MODE=1  → Page Table Walk de 2 níveis + TLB
--
-- Implementação Sv32:
--   VAddr decomposição: VPN[1][31:22] / VPN[0][21:12] / offset[11:0]
--   PTE formato: PPN[31:10] / RSW[9:8] / D[7] / A[6] / G[5] / U[4] /
--                X[3] / W[2] / R[1] / V[0]
--   Nível 1 PA = satp.PPN*4096 + VPN[1]*4
--   Nível 2 PA = PTE1.PPN*4096 + VPN[0]*4
--
-- TLB: 16 entradas, direct-mapped, indexado por VPN[1:0][3:0] (4 bits)
--   Cada entrada: {valid, tag(VPN[1:0]=20b), paddr(32b), R/W/X/U(4b)}
--
-- Permissões (verificadas para M-mode: acesso sempre permitido;
--             para S/U-mode: verifica R/W/X/U bits + MXR/SUM de mstatus):
--   mcause 12 = Instruction Page Fault
--   mcause 13 = Load Page Fault
--   mcause 15 = Store/AMO Page Fault
--
-- Interface PTW (AXI4-Lite read, mestre):
--   ptw_ar* / ptw_r*
--   Stall: ptw_stall_o='1' enquanto a tradução está em andamento
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity mmu is
    generic (
        DATA_WIDTH  : integer := XLEN;
        ENABLE_VM   : boolean := false;  -- false = compila somente o modo bare
        TLB_ENTRIES : integer := 16      -- deve ser potência de 2
    );
    port (
        clk_i        : in  std_logic;
        rst_ni       : in  std_logic;

        -- ---- Endereços virtuais de entrada --------------------------------
        instr_vaddr_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        data_vaddr_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Controle de operação ----------------------------------------
        -- instr_req: '1' quando o fetch_stage emite um novo fetch
        instr_req_i   : in  std_logic;
        -- data_we: '1' quando o acesso de dados é escrita
        data_we_i     : in  std_logic;
        -- data_req: '1' quando memory_stage emite um acesso
        data_req_i    : in  std_logic;

        -- ---- Endereços físicos de saída ----------------------------------
        instr_paddr_o : out std_logic_vector(DATA_WIDTH-1 downto 0);
        data_paddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Stall: tradução em andamento --------------------------------
        ptw_stall_o   : out std_logic;

        -- ---- Descarte de TLB (SFENCE.VMA) --------------------------------
        sfence_vma_i  : in  std_logic;

        -- ---- Exceções de tradução ----------------------------------------
        instr_page_fault_o : out std_logic;
        data_page_fault_o  : out std_logic;

        -- ---- Configuração: satp CSR e nível de privilégio ---------------
        satp_i        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        -- Nível de privilégio atual: "11"=M, "01"=S, "00"=U
        privilege_i   : in  std_logic_vector(1 downto 0);
        -- mstatus.MXR e mstatus.SUM para controle de permissões
        mxr_i         : in  std_logic;
        sum_i         : in  std_logic;

        -- ---- Interface AXI4-Lite Read (Page Table Walk) ------------------
        ptw_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        ptw_arvalid_o : out std_logic;
        ptw_arready_i : in  std_logic;
        ptw_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        ptw_rvalid_i  : in  std_logic;
        ptw_rready_o  : out std_logic
    );
end entity mmu;

architecture rtl of mmu is
begin

    -- =========================================================================
    -- Modo bare: bloco estático sem lógica adicional
    -- =========================================================================
    gen_bare : if not ENABLE_VM generate
        instr_paddr_o      <= instr_vaddr_i;
        data_paddr_o       <= data_vaddr_i;
        instr_page_fault_o <= '0';
        data_page_fault_o  <= '0';
        ptw_stall_o        <= '0';
        ptw_araddr_o       <= (others => '0');
        ptw_arvalid_o      <= '0';
        ptw_rready_o       <= '0';
        -- sfence_vma_i ignorado no modo bare (sem TLB)
    end generate gen_bare;

    -- =========================================================================
    -- Modo Sv32 (ENABLE_VM=true)
    -- =========================================================================
    gen_sv32 : if ENABLE_VM generate

        -- ====================================================================
        -- Constantes Sv32
        -- ====================================================================
        constant PAGE_BITS : integer := 12;
        constant VPN_BITS  : integer := 10;
        constant PPN_BITS  : integer := 22;
        constant PTE_V     : integer := 0;   -- Valid
        constant PTE_R     : integer := 1;   -- Read
        constant PTE_W     : integer := 2;   -- Write
        constant PTE_X     : integer := 3;   -- Execute
        constant PTE_U     : integer := 4;   -- User
        constant PTE_A     : integer := 6;   -- Accessed
        constant PTE_D     : integer := 7;   -- Dirty

        -- ====================================================================
        -- TLB: 16 entradas direct-mapped
        -- ====================================================================
        constant TLB_IDX_W : integer := 4;   -- log2(16)
        constant TLB_TAG_W : integer := 20;  -- VPN[1:0] completo

        type tlb_tag_t   is array (0 to TLB_ENTRIES-1) of
            std_logic_vector(TLB_TAG_W-1 downto 0);
        type tlb_paddr_t is array (0 to TLB_ENTRIES-1) of
            std_logic_vector(DATA_WIDTH-1 downto 0);
        type tlb_perm_t  is array (0 to TLB_ENTRIES-1) of
            std_logic_vector(4 downto 0);  -- {X, W, R, U, V} = PTE bits [4:0]
        type tlb_valid_t is array (0 to TLB_ENTRIES-1) of std_logic;

        signal tlb_valid_r : tlb_valid_t := (others => '0');
        signal tlb_tag_r   : tlb_tag_t   := (others => (others => '0'));
        signal tlb_paddr_r : tlb_paddr_t := (others => (others => '0'));
        signal tlb_perm_r  : tlb_perm_t  := (others => (others => '0'));

        -- ====================================================================
        -- Registradores de controle internos
        -- ====================================================================
        type ptw_state_t is (
            S_IDLE,
            S_CHECK_TLB,
            S_WALK_L1_ADDR,
            S_WALK_L1_DATA,
            S_WALK_L2_ADDR,
            S_WALK_L2_DATA,
            S_CHECK_PERM,
            S_FAULT,
            S_HIT
        );
        signal state_r : ptw_state_t := S_IDLE;

        -- Pedido em curso
        signal req_vaddr_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal req_is_instr : std_logic := '0';
        signal req_is_write : std_logic := '0';

        -- PTE capturado no walk
        signal pte1_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal pte2_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

        -- Resultado traduzido
        signal trans_paddr_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
        signal trans_perm_r  : std_logic_vector(4 downto 0)            := (others => '0');  -- PTE[4:0] = {U,X,W,R,V}

        -- Sinais de stall e fault
        signal ptw_stall_s        : std_logic := '0';
        signal instr_fault_r      : std_logic := '0';
        signal data_fault_r       : std_logic := '0';

        -- satp decomposto
        signal satp_mode_s : std_logic;
        signal satp_ppn_s  : std_logic_vector(PPN_BITS-1 downto 0);

        -- Auxiliares de VPN/offset
        signal vpn1_s  : std_logic_vector(VPN_BITS-1 downto 0);
        signal vpn0_s  : std_logic_vector(VPN_BITS-1 downto 0);

        -- Resultado da consulta TLB
        signal tlb_idx_s  : integer range 0 to TLB_ENTRIES-1;
        signal tlb_hit_s  : std_logic;

        -- (Sem sinais auxiliares adicionais; saídas atribuídas diretamente abaixo)

        -- Função: verifica permissão de acesso para o PTE
        function check_perm(
            pte      : std_logic_vector;
            is_instr : std_logic;
            is_write : std_logic;
            priv     : std_logic_vector(1 downto 0);
            mxr      : std_logic;
            sum      : std_logic
        ) return std_logic is
            variable perm_ok : std_logic;
        begin
            perm_ok := '0';
            if pte(PTE_V) = '0' then
                return '0';  -- PTE inválido
            end if;
            -- Cheque de folha: R=1 ou X=1
            if pte(PTE_R) = '0' and pte(PTE_X) = '0' then
                return '0';  -- Não é folha (ponteiro)
            end if;
            -- Permissões de acesso
            if is_instr = '1' then
                -- Execute: precisa X=1
                perm_ok := pte(PTE_X);
            elsif is_write = '1' then
                -- Write: precisa W=1
                perm_ok := pte(PTE_W);
            else
                -- Read: precisa R=1 (ou X=1 e MXR=1)
                perm_ok := pte(PTE_R) or (pte(PTE_X) and mxr);
            end if;
            -- Em M-mode: ignora U bit (M pode acessar tudo)
            if priv = "11" then
                return perm_ok;
            end if;
            -- Em S-mode: não pode acessar páginas U=1 a menos que SUM=1
            if priv = "01" and pte(PTE_U) = '1' and sum = '0' then
                return '0';
            end if;
            -- Em U-mode: precisa U=1
            if priv = "00" and pte(PTE_U) = '0' then
                return '0';
            end if;
            return perm_ok;
        end function check_perm;

    begin

        -- ====================================================================
        -- Sinais combinacionais derivados
        -- ====================================================================
        satp_mode_s <= satp_i(DATA_WIDTH-1);
        satp_ppn_s  <= satp_i(PPN_BITS-1 downto 0);
        vpn1_s      <= req_vaddr_r(DATA_WIDTH - PAGE_BITS - 1 downto VPN_BITS + PAGE_BITS);
        vpn0_s      <= req_vaddr_r(VPN_BITS + PAGE_BITS - 1 downto PAGE_BITS);
        tlb_idx_s   <= to_integer(unsigned(req_vaddr_r(TLB_IDX_W + PAGE_BITS - 1 downto PAGE_BITS)));
        tlb_hit_s   <= '1' when (tlb_valid_r(tlb_idx_s) = '1' and
                                  tlb_tag_r(tlb_idx_s) = req_vaddr_r(DATA_WIDTH-1 downto PAGE_BITS))
                       else '0';

        -- ====================================================================
        -- FSM principal (Page Table Walker)
        -- ====================================================================
        ptw_fsm : process(clk_i)
            variable idx       : integer range 0 to TLB_ENTRIES-1;
            variable l1_pa     : unsigned(DATA_WIDTH-1 downto 0);
            variable l2_pa     : unsigned(DATA_WIDTH-1 downto 0);
            variable leaf_pte  : std_logic_vector(DATA_WIDTH-1 downto 0);
            variable paddr_out : std_logic_vector(DATA_WIDTH-1 downto 0);
            variable perm_ok   : std_logic;
        begin
            if rising_edge(clk_i) then
                -- Defaults
                ptw_arvalid_o  <= '0';
                ptw_rready_o   <= '0';
                ptw_araddr_o   <= (others => '0');
                instr_fault_r  <= '0';
                data_fault_r   <= '0';

                if rst_ni = '0' then
                    state_r       <= S_IDLE;
                    tlb_valid_r   <= (others => '0');
                    ptw_stall_s   <= '0';

                -- SFENCE.VMA: invalida todo o TLB (operação global por simplicidade)
                elsif sfence_vma_i = '1' then
                    tlb_valid_r <= (others => '0');
                    state_r     <= S_IDLE;
                    ptw_stall_s <= '0';

                else
                    case state_r is

                        when S_IDLE =>
                            ptw_stall_s <= '0';
                            -- Bare mode ou satp.MODE=0: passthrough
                            if satp_mode_s = '0' then
                                null; -- combinacional no gen_sv32_comb
                            else
                                -- Novo pedido de instrução ou dado
                                if instr_req_i = '1' then
                                    req_vaddr_r  <= instr_vaddr_i;
                                    req_is_instr <= '1';
                                    req_is_write <= '0';
                                    state_r      <= S_CHECK_TLB;
                                    ptw_stall_s  <= '1';
                                elsif data_req_i = '1' then
                                    req_vaddr_r  <= data_vaddr_i;
                                    req_is_instr <= '0';
                                    req_is_write <= data_we_i;
                                    state_r      <= S_CHECK_TLB;
                                    ptw_stall_s  <= '1';
                                end if;
                            end if;

                        when S_CHECK_TLB =>
                            ptw_stall_s <= '1';
                            if tlb_hit_s = '1' then
                                -- TLB hit: verificar permissão
                                idx := tlb_idx_s;
                                trans_paddr_r <= tlb_paddr_r(idx);
                                trans_perm_r  <= tlb_perm_r(idx);  -- PTE[4:0]
                                state_r       <= S_CHECK_PERM;
                            else
                                -- TLB miss: iniciar walk
                                l1_pa := shift_left(resize(unsigned(satp_ppn_s), DATA_WIDTH), PAGE_BITS)
                                       + shift_left(resize(unsigned(vpn1_s),   DATA_WIDTH), 2);
                                ptw_araddr_o  <= std_logic_vector(l1_pa);
                                ptw_arvalid_o <= '1';
                                state_r       <= S_WALK_L1_ADDR;
                            end if;

                        when S_WALK_L1_ADDR =>
                            ptw_stall_s   <= '1';
                            l1_pa := shift_left(resize(unsigned(satp_ppn_s), DATA_WIDTH), PAGE_BITS)
                                   + shift_left(resize(unsigned(vpn1_s),   DATA_WIDTH), 2);
                            ptw_araddr_o  <= std_logic_vector(l1_pa);
                            ptw_arvalid_o <= '1';
                            if ptw_arready_i = '1' then
                                state_r <= S_WALK_L1_DATA;
                            end if;

                        when S_WALK_L1_DATA =>
                            ptw_stall_s  <= '1';
                            ptw_rready_o <= '1';
                            if ptw_rvalid_i = '1' then
                                pte1_r  <= ptw_rdata_i;
                                -- Verifica se é folha de nível 1 (superpage)
                                if ptw_rdata_i(PTE_V) = '0' then
                                    -- PTE inválido = page fault
                                    state_r <= S_FAULT;
                                elsif ptw_rdata_i(PTE_R) = '1' or ptw_rdata_i(PTE_X) = '1' then
                                    -- Superpage (folha de L1): PPN[1:0] devem ser 0
                                    if ptw_rdata_i(19 downto 10) /= "0000000000" then
                                        state_r <= S_FAULT; -- misaligned superpage
                                    else
                                        -- Monta paddr superpage: PPN[1][9:0]||VPN[0]||offset = 32 bits
                                        paddr_out := ptw_rdata_i(DATA_WIDTH-3 downto DATA_WIDTH-12) &
                                                     vpn0_s &
                                                     req_vaddr_r(PAGE_BITS-1 downto 0);
                                        trans_paddr_r <= paddr_out;
                                        trans_perm_r  <= ptw_rdata_i(PTE_U downto PTE_V); -- {U,X,W,R,V}
                                        state_r       <= S_CHECK_PERM;
                                    end if;
                                else
                                    -- Ponteiro para nível 2
                                    l2_pa := shift_left(resize(unsigned(ptw_rdata_i(DATA_WIDTH-3 downto 10)), DATA_WIDTH), PAGE_BITS)
                                           + shift_left(resize(unsigned(vpn0_s), DATA_WIDTH), 2);
                                    ptw_araddr_o  <= std_logic_vector(l2_pa);
                                    ptw_arvalid_o <= '1';
                                    state_r       <= S_WALK_L2_ADDR;
                                end if;
                            end if;

                        when S_WALK_L2_ADDR =>
                            ptw_stall_s   <= '1';
                            l2_pa := shift_left(resize(unsigned(pte1_r(DATA_WIDTH-3 downto 10)), DATA_WIDTH), PAGE_BITS)
                                   + shift_left(resize(unsigned(vpn0_s), DATA_WIDTH), 2);
                            ptw_araddr_o  <= std_logic_vector(l2_pa);
                            ptw_arvalid_o <= '1';
                            if ptw_arready_i = '1' then
                                state_r <= S_WALK_L2_DATA;
                            end if;

                        when S_WALK_L2_DATA =>
                            ptw_stall_s  <= '1';
                            ptw_rready_o <= '1';
                            if ptw_rvalid_i = '1' then
                                pte2_r     <= ptw_rdata_i;
                                leaf_pte   := ptw_rdata_i;
                                if leaf_pte(PTE_V) = '0' or
                                   (leaf_pte(PTE_R) = '0' and leaf_pte(PTE_X) = '0') then
                                    state_r <= S_FAULT;
                                else
                                    -- Monta paddr 4KB: PPN[19:0]||offset = 32 bits
                                    paddr_out := leaf_pte(DATA_WIDTH-3 downto 10) &
                                                 req_vaddr_r(PAGE_BITS-1 downto 0);
                                    trans_paddr_r <= paddr_out;
                                    trans_perm_r  <= leaf_pte(PTE_U downto PTE_V); -- {U,X,W,R,V}
                                    -- Atualiza TLB
                                    idx := tlb_idx_s;
                                    tlb_valid_r(idx) <= '1';
                                    tlb_tag_r(idx)   <= req_vaddr_r(DATA_WIDTH-1 downto PAGE_BITS);
                                    tlb_paddr_r(idx) <= paddr_out;
                                    tlb_perm_r(idx)  <= leaf_pte(PTE_U downto PTE_V);
                                    state_r          <= S_CHECK_PERM;
                                end if;
                            end if;

                        when S_CHECK_PERM =>
                            ptw_stall_s <= '1';
                            -- Passa os 5 bits PTE[4:0] no início de um vector de 32 bits
                            -- para que pte(PTE_V)=pte(0), pte(PTE_R)=pte(1), ..., pte(PTE_U)=pte(4)
                            perm_ok := check_perm(
                                pte      => (DATA_WIDTH-1 downto 5 => '0') & trans_perm_r,
                                is_instr => req_is_instr,
                                is_write => req_is_write,
                                priv     => privilege_i,
                                mxr      => mxr_i,
                                sum      => sum_i
                            );
                            if perm_ok = '1' then
                                state_r <= S_HIT;
                            else
                                state_r <= S_FAULT;
                            end if;

                        when S_HIT =>
                            -- Entrega o paddr traduzido por 1 ciclo
                            ptw_stall_s <= '0';
                            state_r     <= S_IDLE;

                        when S_FAULT =>
                            -- Sinaliza page fault por 1 ciclo
                            if req_is_instr = '1' then
                                instr_fault_r <= '1';
                            else
                                data_fault_r  <= '1';
                            end if;
                            ptw_stall_s <= '0';
                            state_r     <= S_IDLE;

                        when others =>
                            state_r <= S_IDLE;

                    end case;
                end if;
            end if;
        end process ptw_fsm;

        -- ====================================================================
        -- Saídas combinacionais
        -- ====================================================================
        ptw_stall_o <= ptw_stall_s;

        -- No modo bare (satp.MODE=0): passthrough
        -- No modo Sv32 (satp.MODE=1): usa resultado do PTW/TLB
        instr_paddr_o <= instr_vaddr_i when satp_mode_s = '0'
                         else trans_paddr_r;
        data_paddr_o  <= data_vaddr_i  when satp_mode_s = '0'
                         else trans_paddr_r;

        instr_page_fault_o <= instr_fault_r;
        data_page_fault_o  <= data_fault_r;

    end generate gen_sv32;

end architecture rtl;
