-- =============================================================================
-- csr_reg.vhd
-- Registradores de Controle e Status (CSR) – M-mode + S-mode + U-mode
--
-- CSRs M-mode:
--   0x300  mstatus  – MIE,MPIE,MPP,SIE,SPIE,SPP,MXR,SUM
--   0x302  medeleg  – Delegação de exceções para S-mode
--   0x303  mideleg  – Delegação de interrupções para S-mode
--   0x304  mie      – Habilitação interrupções (MSIE,MTIE,MEIE,SSIE,STIE,SEIE)
--   0x305  mtvec    – Vetor de trap M-mode
--   0x340  mscratch – Scratch M-mode
--   0x341  mepc     – PC de retorno M-mode
--   0x342  mcause   – Causa trap M-mode
--   0x343  mtval    – Valor trap M-mode
--   0x344  mip      – Interrupções pendentes
--   0x180  satp     – Supervisor Address Translation
--   0xF11-0xF14     – mvendorid,marchid,mimpid,mhartid (RO)
--   0xC00/0xC80/0xC02/0xC82 – cycle/cycleh/instret/instreth
--
-- CSRs S-mode:
--   0x100  sstatus  – Vista restrita de mstatus (SIE,SPIE,SPP,SUM,MXR)
--   0x104  sie      – mie & mideleg
--   0x105  stvec    – Vetor trap S-mode
--   0x106  scounteren
--   0x140  sscratch – Scratch S-mode
--   0x141  sepc     – PC de retorno S-mode
--   0x142  scause   – Causa trap S-mode
--   0x143  stval    – Valor trap S-mode
--   0x144  sip      – mip & mideleg
--
-- Delegação: priv!=M E medeleg/mideleg[cause]=1 → trap para S-mode (stvec/sepc)
-- SRET: sret_en_i porta + sret_pc_o (retorna sepc)
-- privilege_o: "11"=M, "01"=S, "00"=U (registrador priv_r)
-- =============================================================================
-- Operações CSR (funct3): 001/101=W, 010/110=S, 011/111=C
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity csr_reg is
    generic (
        DATA_WIDTH   : integer := XLEN;
        HART_ID      : integer := 0;
        VENDOR_ID    : std_logic_vector(XLEN-1 downto 0) := (others => '0');
        ARCH_ID      : std_logic_vector(XLEN-1 downto 0) := (others => '0');
        IMP_ID       : std_logic_vector(XLEN-1 downto 0) := (others => '0')
    );
    port (
        clk_i        : in  std_logic;
        rst_ni       : in  std_logic;

        -- ---- Interface de acesso CSR (vem do pipeline, estágio Execute/WB) -
        csr_addr_i   : in  std_logic_vector(11 downto 0); -- bits [31:20] da instr.
        csr_wdata_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        csr_op_i     : in  std_logic_vector(2 downto 0);  -- funct3
        csr_we_i     : in  std_logic;                      -- write enable
        csr_re_i     : in  std_logic;                      -- read enable
        csr_uimm_i   : in  std_logic_vector(4 downto 0);  -- imediato zimm[4:0]

        csr_rdata_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        csr_illegal_o: out std_logic;  -- acesso inválido

        -- ---- Interface de trap (ECALL, EBREAK, exceções de hardware) ------
        trap_en_i    : in  std_logic;
        trap_cause_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        trap_val_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        trap_pc_i    : in  std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Destino do trap (stvec ou mtvec conforme delegação)
        trap_target_o: out std_logic_vector(DATA_WIDTH-1 downto 0);
        mret_pc_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mret_en_i    : in  std_logic;
        -- SRET (Supervisor Return) ------------------------------------------
        sret_pc_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        sret_en_i    : in  std_logic;

        -- ---- Contadores de hardware --------------------------------------
        -- instret: incrementado externamente pelo topo quando instrução é retirada
        instret_inc_i: in  std_logic;

        -- ---- Interrupções de hardware (é refletido em mip) ---------------
        irq_external_i : in  std_logic;  -- MEIP: interrupção externa
        irq_timer_i    : in  std_logic;  -- MTIP: interrupção de timer
        irq_software_i : in  std_logic;  -- MSIP: interrupção de software

        -- Sinal combinacional: interrupção pendente e habilitada
        -- (mstatus.MIE=1 AND algum bit de mie AND mip está ativo)
        irq_pending_o  : out std_logic;

        -- Causa da interrupção de maior prioridade pendente (bit31=1 indica interrupção)
        -- MEIP=0x8000000B, MTIP=0x80000007, MSIP=0x80000003
        irq_cause_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- ---- Saídas de estado para MMU / privilégio ---------------------
        satp_o         : out std_logic_vector(DATA_WIDTH-1 downto 0);
        privilege_o    : out std_logic_vector(1 downto 0);  -- "11"=M, "01"=S, "00"=U
        mxr_o          : out std_logic;   -- mstatus[19]: Make eXecutable Readable
        sum_o          : out std_logic    -- mstatus[18]: Supervisor User Memory
    );
end entity csr_reg;

architecture rtl of csr_reg is

    -- =========================================================================
    -- Endereços dos CSRs
    -- =========================================================================
    -- M-mode CSRs
    constant CSR_MSTATUS  : std_logic_vector(11 downto 0) := x"300";
    constant CSR_MEDELEG  : std_logic_vector(11 downto 0) := x"302";
    constant CSR_MIDELEG  : std_logic_vector(11 downto 0) := x"303";
    constant CSR_MIE      : std_logic_vector(11 downto 0) := x"304";
    constant CSR_MTVEC    : std_logic_vector(11 downto 0) := x"305";
    constant CSR_MSCRATCH : std_logic_vector(11 downto 0) := x"340";
    constant CSR_MEPC     : std_logic_vector(11 downto 0) := x"341";
    constant CSR_MCAUSE   : std_logic_vector(11 downto 0) := x"342";
    constant CSR_MTVAL    : std_logic_vector(11 downto 0) := x"343";
    constant CSR_MIP      : std_logic_vector(11 downto 0) := x"344";
    constant CSR_SATP     : std_logic_vector(11 downto 0) := x"180";
    constant CSR_MVENDORID: std_logic_vector(11 downto 0) := x"F11";
    constant CSR_MARCHID  : std_logic_vector(11 downto 0) := x"F12";
    constant CSR_MIMPID   : std_logic_vector(11 downto 0) := x"F13";
    constant CSR_MHARTID  : std_logic_vector(11 downto 0) := x"F14";
    constant CSR_CYCLE    : std_logic_vector(11 downto 0) := x"C00";
    constant CSR_CYCLEH   : std_logic_vector(11 downto 0) := x"C80";
    constant CSR_TIME     : std_logic_vector(11 downto 0) := x"C01";
    constant CSR_INSTRET  : std_logic_vector(11 downto 0) := x"C02";
    constant CSR_INSTRETH : std_logic_vector(11 downto 0) := x"C82";
    -- S-mode CSRs
    constant CSR_SSTATUS   : std_logic_vector(11 downto 0) := x"100";
    constant CSR_SIE       : std_logic_vector(11 downto 0) := x"104";
    constant CSR_STVEC     : std_logic_vector(11 downto 0) := x"105";
    constant CSR_SCOUNTEREN: std_logic_vector(11 downto 0) := x"106";
    constant CSR_SSCRATCH  : std_logic_vector(11 downto 0) := x"140";
    constant CSR_SEPC      : std_logic_vector(11 downto 0) := x"141";
    constant CSR_SCAUSE    : std_logic_vector(11 downto 0) := x"142";
    constant CSR_STVAL     : std_logic_vector(11 downto 0) := x"143";
    constant CSR_SIP       : std_logic_vector(11 downto 0) := x"144";

    -- =========================================================================
    -- Registradores CSR
    -- =========================================================================
    -- M-mode
    signal mstatus_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal medeleg_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mideleg_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mie_r      : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mip_r      : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mtvec_r    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mscratch_r : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mepc_r     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mcause_r   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal mtval_r    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal satp_r     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    -- S-mode
    signal stvec_r     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sscratch_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sepc_r      : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal scause_r    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal stval_r     : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal scounteren_r: std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    -- Privilege level: "11"=M, "01"=S, "00"=U
    signal priv_r      : std_logic_vector(1 downto 0) := "11";

    -- Delegation decision (combinatorial)
    signal trap_to_s   : std_logic;

    -- Contadores de 64 bits
    signal cycle_r    : unsigned(63 downto 0) := (others => '0');
    signal instret_r  : unsigned(63 downto 0) := (others => '0');

    -- =========================================================================
    -- Dado a escrever (após decodificação da operação)
    -- =========================================================================
    signal wdata_final : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rdata_s     : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    -- =========================================================================
    -- Delegation decision (combinatorial)
    -- Exception: medeleg[cause_code], Interrupt: mideleg[irq_bit]
    -- Only possible when not already in M-mode
    -- =========================================================================
    trap_to_s <= '1' when
        priv_r /= "11" and
        ((trap_cause_i(DATA_WIDTH-1) = '0' and
          medeleg_r(to_integer(unsigned(trap_cause_i(4 downto 0)))) = '1') or
         (trap_cause_i(DATA_WIDTH-1) = '1' and
          mideleg_r(to_integer(unsigned(trap_cause_i(3 downto 0)))) = '1'))
        else '0';

    -- Trap target: stvec when delegated to S, mtvec otherwise (vectored support)
    trap_target_o <=
        std_logic_vector(
            unsigned(stvec_r(DATA_WIDTH-1 downto 2) & "00") +
            shift_left(resize(unsigned(trap_cause_i(DATA_WIDTH-2 downto 0)), DATA_WIDTH), 2))
        when trap_to_s = '1' and stvec_r(1 downto 0) = "01" and trap_cause_i(DATA_WIDTH-1) = '1'
        else stvec_r(DATA_WIDTH-1 downto 2) & "00"
        when trap_to_s = '1'
        else std_logic_vector(
            unsigned(mtvec_r(DATA_WIDTH-1 downto 2) & "00") +
            shift_left(resize(unsigned(trap_cause_i(DATA_WIDTH-2 downto 0)), DATA_WIDTH), 2))
        when mtvec_r(1 downto 0) = "01" and trap_cause_i(DATA_WIDTH-1) = '1'
        else mtvec_r(DATA_WIDTH-1 downto 2) & "00";


    write_data_proc : process(csr_op_i, csr_wdata_i, csr_uimm_i, rdata_s)
        variable uimm_ext : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        uimm_ext := (others => '0');
        uimm_ext(4 downto 0) := csr_uimm_i;

        case csr_op_i is
            when "001" => wdata_final <= csr_wdata_i;                      -- CSRRW
            when "010" => wdata_final <= rdata_s or  csr_wdata_i;          -- CSRRS
            when "011" => wdata_final <= rdata_s and (not csr_wdata_i);    -- CSRRC
            when "101" => wdata_final <= uimm_ext;                         -- CSRRWI
            when "110" => wdata_final <= rdata_s or  uimm_ext;             -- CSRRSI
            when "111" => wdata_final <= rdata_s and (not uimm_ext);       -- CSRRCI
            when others => wdata_final <= csr_wdata_i;
        end case;
    end process write_data_proc;

    -- =========================================================================
    -- Leitura de CSR (combinacional) – M-mode + S-mode
    -- =========================================================================
    csr_read_proc : process(
        csr_addr_i, csr_re_i, csr_we_i,
        mstatus_r, medeleg_r, mideleg_r, mie_r, mip_r, mtvec_r,
        mscratch_r, mepc_r, mcause_r, mtval_r, satp_r,
        stvec_r, sscratch_r, sepc_r, scause_r, stval_r, scounteren_r,
        cycle_r, instret_r, priv_r
    )
        variable sstatus_v : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable sie_v     : std_logic_vector(DATA_WIDTH-1 downto 0);
        variable sip_v     : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        rdata_s       <= (others => '0');
        csr_illegal_o <= '0';

        -- sstatus = mstatus masked to S-visible bits
        sstatus_v := (others => '0');
        sstatus_v(31) := mstatus_r(31); -- SD
        sstatus_v(19) := mstatus_r(19); -- MXR
        sstatus_v(18) := mstatus_r(18); -- SUM
        sstatus_v(8)  := mstatus_r(8);  -- SPP
        sstatus_v(5)  := mstatus_r(5);  -- SPIE
        sstatus_v(1)  := mstatus_r(1);  -- SIE

        sie_v := mie_r  and mideleg_r;  -- sie = mie & mideleg
        sip_v := mip_r  and mideleg_r;  -- sip = mip & mideleg

        case csr_addr_i is
            -- S-mode CSRs
            when CSR_SSTATUS    => rdata_s <= sstatus_v;
            when CSR_SIE        => rdata_s <= sie_v;
            when CSR_STVEC      => rdata_s <= stvec_r;
            when CSR_SCOUNTEREN => rdata_s <= scounteren_r;
            when CSR_SSCRATCH   => rdata_s <= sscratch_r;
            when CSR_SEPC       => rdata_s <= sepc_r;
            when CSR_SCAUSE     => rdata_s <= scause_r;
            when CSR_STVAL      => rdata_s <= stval_r;
            when CSR_SIP        => rdata_s <= sip_v;
            when CSR_SATP       => rdata_s <= satp_r;
            -- M-mode CSRs
            when CSR_MSTATUS   => rdata_s <= mstatus_r;
            when CSR_MEDELEG   => rdata_s <= medeleg_r;
            when CSR_MIDELEG   => rdata_s <= mideleg_r;
            when CSR_MIE       => rdata_s <= mie_r;
            when CSR_MIP       => rdata_s <= mip_r;
            when CSR_MTVEC     => rdata_s <= mtvec_r;
            when CSR_MSCRATCH  => rdata_s <= mscratch_r;
            when CSR_MEPC      => rdata_s <= mepc_r;
            when CSR_MCAUSE    => rdata_s <= mcause_r;
            when CSR_MTVAL     => rdata_s <= mtval_r;
            when CSR_MVENDORID => rdata_s <= VENDOR_ID;
            when CSR_MARCHID   => rdata_s <= ARCH_ID;
            when CSR_MIMPID    => rdata_s <= IMP_ID;
            when CSR_MHARTID   =>
                rdata_s <= std_logic_vector(to_unsigned(HART_ID, DATA_WIDTH));
            when CSR_CYCLE | CSR_TIME =>
                rdata_s <= std_logic_vector(cycle_r(31 downto 0));
            when CSR_CYCLEH    =>
                rdata_s <= std_logic_vector(cycle_r(63 downto 32));
            when CSR_INSTRET   =>
                rdata_s <= std_logic_vector(instret_r(31 downto 0));
            when CSR_INSTRETH  =>
                rdata_s <= std_logic_vector(instret_r(63 downto 32));
            when others =>
                csr_illegal_o <= csr_re_i or csr_we_i;
        end case;
    end process csr_read_proc;

    csr_rdata_o <= rdata_s;

    -- =========================================================================
    -- Escrita de CSR + tratamento de traps (síncrono)
    -- Prioridade: trap_en > mret_en > sret_en > csr_we
    -- =========================================================================
    csr_write_proc : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            mstatus_r   <= (others => '0');
            medeleg_r   <= (others => '0');
            mideleg_r   <= (others => '0');
            mie_r       <= (others => '0');
            mip_r       <= (others => '0');
            mtvec_r     <= (others => '0');
            mscratch_r  <= (others => '0');
            mepc_r      <= (others => '0');
            mcause_r    <= (others => '0');
            mtval_r     <= (others => '0');
            satp_r      <= (others => '0');
            stvec_r     <= (others => '0');
            sscratch_r  <= (others => '0');
            sepc_r      <= (others => '0');
            scause_r    <= (others => '0');
            stval_r     <= (others => '0');
            scounteren_r<= (others => '0');
            priv_r      <= "11";  -- inicia em M-mode
            cycle_r     <= (others => '0');
            instret_r   <= (others => '0');

        elsif rising_edge(clk_i) then
            cycle_r <= cycle_r + 1;

            -- Hardware interrupt lines → mip (MEIP/MTIP/MSIP são read-only)
            mip_r(11) <= irq_external_i; -- MEIP
            mip_r(7)  <= irq_timer_i;    -- MTIP
            mip_r(3)  <= irq_software_i; -- MSIP

            if instret_inc_i = '1' then
                instret_r <= instret_r + 1;
            end if;

            -- ---- Trap entry ------------------------------------------------
            if trap_en_i = '1' then
                if trap_to_s = '1' then
                    -- ---- Delegado para S-mode ----
                    sepc_r               <= trap_pc_i;
                    scause_r             <= trap_cause_i;
                    stval_r              <= trap_val_i;
                    mstatus_r(5)         <= mstatus_r(1); -- SPIE ← SIE
                    mstatus_r(1)         <= '0';           -- SIE  ← 0
                    mstatus_r(8)         <= priv_r(0);     -- SPP  ← prev priv bit0 (S=1, U=0)
                    priv_r               <= "01";          -- → S-mode

                else
                    -- ---- Tratado em M-mode ----
                    mepc_r               <= trap_pc_i;
                    mcause_r             <= trap_cause_i;
                    mtval_r              <= trap_val_i;
                    mstatus_r(7)         <= mstatus_r(3);  -- MPIE ← MIE
                    mstatus_r(3)         <= '0';            -- MIE  ← 0
                    mstatus_r(12 downto 11) <= priv_r;     -- MPP  ← prev priv
                    priv_r               <= "11";           -- → M-mode
                end if;

            -- ---- MRET ------------------------------------------------------
            elsif mret_en_i = '1' then
                mstatus_r(3)            <= mstatus_r(7);   -- MIE  ← MPIE
                mstatus_r(7)            <= '1';             -- MPIE ← 1
                priv_r                  <= mstatus_r(12 downto 11); -- priv ← MPP
                mstatus_r(12 downto 11) <= "00";            -- MPP  ← U (WARL)

            -- ---- SRET ------------------------------------------------------
            elsif sret_en_i = '1' then
                mstatus_r(1)            <= mstatus_r(5);   -- SIE  ← SPIE
                mstatus_r(5)            <= '1';             -- SPIE ← 1
                -- SPP bit → new privilege
                if mstatus_r(8) = '1' then
                    priv_r              <= "01";             -- → S-mode
                else
                    priv_r              <= "00";             -- → U-mode
                end if;
                mstatus_r(8)            <= '0';             -- SPP  ← U (WARL)

            -- ---- CSR write -------------------------------------------------
            elsif csr_we_i = '1' then
                case csr_addr_i is
                    -- S-mode writable
                    when CSR_SSTATUS =>
                        mstatus_r(19) <= wdata_final(19); -- MXR
                        mstatus_r(18) <= wdata_final(18); -- SUM
                        mstatus_r(8)  <= wdata_final(8);  -- SPP
                        mstatus_r(5)  <= wdata_final(5);  -- SPIE
                        mstatus_r(1)  <= wdata_final(1);  -- SIE
                    when CSR_SIE =>
                        -- write only delegated bits
                        mie_r <= (mie_r and not mideleg_r) or (wdata_final and mideleg_r);
                    when CSR_STVEC      => stvec_r      <= wdata_final;
                    when CSR_SCOUNTEREN => scounteren_r <= wdata_final;
                    when CSR_SSCRATCH   => sscratch_r   <= wdata_final;
                    when CSR_SEPC       => sepc_r       <= wdata_final;
                    when CSR_SCAUSE     => scause_r     <= wdata_final;
                    when CSR_STVAL      => stval_r      <= wdata_final;
                    when CSR_SIP =>
                        -- Only SSIP (bit1) software-writable via sip when delegated
                        if mideleg_r(1) = '1' then
                            mip_r(1) <= wdata_final(1);
                        end if;
                    when CSR_SATP       => satp_r       <= wdata_final;
                    -- M-mode writable
                    when CSR_MSTATUS  => mstatus_r  <= wdata_final;
                    when CSR_MEDELEG  => medeleg_r  <= wdata_final;
                    when CSR_MIDELEG  => mideleg_r  <= wdata_final;
                    when CSR_MIE      => mie_r      <= wdata_final;
                    when CSR_MIP =>
                        -- Software-writable bits: SSIP(1), STIP(5), SEIP(9)
                        mip_r(1) <= wdata_final(1);
                        mip_r(5) <= wdata_final(5);
                        mip_r(9) <= wdata_final(9);
                    when CSR_MTVEC    => mtvec_r    <= wdata_final;
                    when CSR_MSCRATCH => mscratch_r <= wdata_final;
                    when CSR_MEPC     => mepc_r     <= wdata_final;
                    when CSR_MCAUSE   => mcause_r   <= wdata_final;
                    when CSR_MTVAL    => mtval_r    <= wdata_final;
                    when others       => null;
                end case;
            end if;
        end if;
    end process csr_write_proc;

    -- =========================================================================
    -- Interrupção pendente (combinacional) – M-mode + S-mode
    -- M-level interrupt: pendente se (priv<M OR (priv=M AND MIE=1))
    --                    AND mie[i] AND mip[i] AND NOT mideleg[i]
    -- S-level interrupt: pendente se (priv<S OR (priv=S AND SIE=1))
    --                    AND mie[i] AND mip[i] AND mideleg[i]
    -- =========================================================================
    irq_pending_proc : process(mstatus_r, mie_r, mip_r, mideleg_r, priv_r)
        variable m_en, s_en : std_logic;
        variable meip_v, mtip_v, msip_v : std_logic;
        variable seip_v, stip_v, ssip_v : std_logic;
    begin
        -- M-level global enable
        if priv_r /= "11" then
            m_en := '1';
        else
            m_en := mstatus_r(3); -- MIE
        end if;
        -- S-level global enable (not applicable in M-mode)
        if priv_r = "00" then
            s_en := '1';      -- U-mode: S-level always OK
        elsif priv_r = "01" then
            s_en := mstatus_r(1); -- S-mode: SIE
        else
            s_en := '0';      -- M-mode: S-level never pre-empts
        end if;

        meip_v := mip_r(11) and mie_r(11) and not mideleg_r(11) and m_en;
        mtip_v := mip_r(7)  and mie_r(7)  and not mideleg_r(7)  and m_en;
        msip_v := mip_r(3)  and mie_r(3)  and not mideleg_r(3)  and m_en;

        seip_v := mip_r(9) and mie_r(9) and mideleg_r(9) and s_en;
        stip_v := mip_r(5) and mie_r(5) and mideleg_r(5) and s_en;
        ssip_v := mip_r(1) and mie_r(1) and mideleg_r(1) and s_en;

        irq_pending_o <= meip_v or mtip_v or msip_v or seip_v or stip_v or ssip_v;

        -- Prioridade: MEIP > MTIP > MSIP > SEIP > STIP > SSIP
        if    meip_v = '1' then irq_cause_o <= x"8000000B";
        elsif mtip_v = '1' then irq_cause_o <= x"80000007";
        elsif msip_v = '1' then irq_cause_o <= x"80000003";
        elsif seip_v = '1' then irq_cause_o <= x"80000009";
        elsif stip_v = '1' then irq_cause_o <= x"80000005";
        elsif ssip_v = '1' then irq_cause_o <= x"80000001";
        else                    irq_cause_o <= (others => '0');
        end if;
    end process irq_pending_proc;

    -- =========================================================================
    -- Trap return PCs
    -- =========================================================================
    mret_pc_o <= mepc_r;
    sret_pc_o <= sepc_r;

    -- =========================================================================
    -- Saídas de estado para pipeline / MMU
    -- =========================================================================
    satp_o      <= satp_r;
    privilege_o <= priv_r;       -- agora dinâmico: "11"=M, "01"=S, "00"=U
    mxr_o       <= mstatus_r(19);
    sum_o       <= mstatus_r(18);

end architecture rtl;
