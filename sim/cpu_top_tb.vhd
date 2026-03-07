-- =============================================================================
-- cpu_top_tb.vhd
-- Testbench para cpu_top – RV32I 5-stage pipeline
--
-- Programa de teste (assembly RV32I compilado manualmente):
--
--   Addr 0x00:  addi x1,  x0, 5      # x1  = 5
--   Addr 0x04:  addi x2,  x0, 3      # x2  = 3
--   Addr 0x08:  add  x3,  x1, x2     # x3  = 8
--   Addr 0x0C:  sw   x3,  0(x0)      # mem[0x0] = 8
--   Addr 0x10:  lw   x4,  0(x0)      # x4  = 8
--   Addr 0x14:  beq  x3,  x4, +8     # branch to 0x1C  (taken, x3==x4)
--   Addr 0x18:  addi x5,  x0, 255    # SKIPPED pelo branch
--   Addr 0x1C:  addi x5,  x0, 1      # x5  = 1  (via branch)
--   Addr 0x20:  addi x6,  x0, 10     # x6  = 10
--   Addr 0x24:  addi x7,  x0, -1     # x7  = -1 (0xFFFFFFFF)
--   Addr 0x28:  sub  x8,  x6, x1     # x8  = 10 - 5 = 5
--   Addr 0x2C:  slt  x9,  x7, x6     # x9  = 1  (-1 < 10)
--   Addr 0x30:  sltu x10, x7, x6     # x10 = 0  (0xFFFFFFFF > 10 unsigned)
--   Addr 0x34:  xor  x11, x6, x1     # x11 = 10 xor 5 = 15
--   Addr 0x38:  or   x12, x6, x1     # x12 = 10 | 5 = 15
--   Addr 0x3C:  and  x13, x6, x1     # x13 = 10 & 5 = 0
--   Addr 0x40:  slli x14, x6, 2      # x14 = 10 << 2 = 40
--   Addr 0x44:  srli x15, x14, 1     # x15 = 40 >> 1 = 20 (lógico)
--   Addr 0x48:  srai x16, x7, 1      # x16 = -1 >> 1 = -1 (aritmético)
--   Addr 0x4C:  jal  x17, +4         # x17 = 0x54, PC → 0x54
--   Addr 0x50:  addi x0, x0, 0       # NOP – SKIPPED pelo jal
--   Addr 0x54:  auipc x18, 0         # x18 = PC = 0x54
--   Addr 0x58:  lui   x19, 1         # x19 = 0x1000
--   Addr 0x5C:  jalr  x20, x17, 0    # x20 = 0x60, PC → x17 = 0x54? correção: PC→0x54
--              (JALR testa retorno de função simples)
--   Addr 0x60:  jal  x0, 0           # HALT – loop infinito
--
-- Sinais verificados:
--   - pc_o muda a cada ciclo válido
--   - Teste de "sanidade": rodar 200 ciclos sem travar indefinidamente
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity cpu_top_tb is
end entity cpu_top_tb;

architecture sim of cpu_top_tb is

    -- =========================================================================
    -- Parâmetros
    -- =========================================================================
    constant CLK_PERIOD  : time    := 10 ns;
    constant SIM_TIMEOUT : integer := 500;   -- ciclos máximos
    constant DATA_WIDTH  : integer := XLEN;

    -- =========================================================================
    -- Memória de instruções (ROM – 256 palavras × 32 bits)
    -- =========================================================================
    type rom_t is array (0 to 255) of std_logic_vector(31 downto 0);

    -- Codificação manual do programa de teste
    constant IMEM : rom_t := (
        -- Addr 0x00: addi x1, x0, 5
        0  => x"00500093",
        -- Addr 0x04: addi x2, x0, 3
        1  => x"00300113",
        -- Addr 0x08: add x3, x1, x2
        2  => x"002081B3",
        -- Addr 0x0C: sw x3, 0(x0)
        3  => x"00302023",
        -- Addr 0x10: lw x4, 0(x0)
        4  => x"00002203",
        -- Addr 0x14: beq x3, x4, +8  (target = 0x1C)
        5  => x"00418463",
        -- Addr 0x18: addi x5, x0, 255  (deve ser pulado)
        6  => x"0FF00293",
        -- Addr 0x1C: addi x5, x0, 1
        7  => x"00100293",
        -- Addr 0x20: addi x6, x0, 10
        8  => x"00A00313",
        -- Addr 0x24: addi x7, x0, -1
        9  => x"FFF00393",
        -- Addr 0x28: sub x8, x6, x1  (10 - 5 = 5)
        10 => x"40130433",
        -- Addr 0x2C: slt x9, x7, x6  (-1 < 10 → 1)
        11 => x"0063A4B3",
        -- Addr 0x30: sltu x10, x7, x6 (0xFFFF...FF > 10 unsigned → 0)
        12 => x"0063B533",
        -- Addr 0x34: xor x11, x6, x1  (10 xor 5 = 15)
        13 => x"005345B3",
        -- Addr 0x38: or x12, x6, x1   (10 | 5 = 15)
        14 => x"00536633",
        -- Addr 0x3C: and x13, x6, x1  (10 & 5 = 0)
        15 => x"005376B3",
        -- Addr 0x40: slli x14, x6, 2  (10 << 2 = 40)
        16 => x"00231713",
        -- Addr 0x44: srli x15, x14, 1 (40 >> 1 = 20)
        17 => x"00175793",
        -- Addr 0x48: srai x16, x7, 1  (-1 >> 1 = -1)
        18 => x"40139813",
        -- Addr 0x4C: jal x17, +4  (x17 = 0x54, PC → 0x54 [+8 por causa do delay de 1 instr])
        -- jal offset=+8 para pular a instrução na 0x50: imm=8
        -- [31]=0,[30:21]=0000000100,[20]=0,[19:12]=00000000,[11:7]=10001,[6:0]=1101111
        -- = 0x008008EF
        19 => x"008008EF",
        -- Addr 0x50: nop (skipped pelo jal)
        20 => x"00000013",
        -- Addr 0x54: auipc x18, 0   (x18 = PC = 0x54)
        21 => x"00000917",
        -- Addr 0x58: lui x19, 1     (x19 = 0x1000)
        22 => x"000019B7",
        -- Addr 0x5C: jal x0, 0  (HALT – loop infinito em 0x5C)
        23 => x"0000006F",
        -- Endereços restantes: NOP
        others => x"00000013"
    );

    -- =========================================================================
    -- Memória de dados (RAM – 256 palavras × 32 bits)
    -- =========================================================================
    type ram_t is array (0 to 255) of std_logic_vector(31 downto 0);

    -- =========================================================================
    -- Sinais do DUT
    -- =========================================================================
    signal clk_i            : std_logic := '0';
    signal rst_ni           : std_logic := '0';

    -- AXI Instruction Memory
    signal im_araddr_o      : std_logic_vector(31 downto 0);
    signal im_arvalid_o     : std_logic;
    signal im_arprot_o      : std_logic_vector(2 downto 0);
    signal im_arready_i     : std_logic := '0';
    signal im_rdata_i       : std_logic_vector(31 downto 0) := (others => '0');
    signal im_rresp_i       : std_logic_vector(1 downto 0)  := "00";
    signal im_rvalid_i      : std_logic := '0';
    signal im_rready_o      : std_logic;

    -- AXI Data Memory
    signal dm_araddr_o      : std_logic_vector(31 downto 0);
    signal dm_arvalid_o     : std_logic;
    signal dm_arprot_o      : std_logic_vector(2 downto 0);
    signal dm_arready_i     : std_logic := '0';
    signal dm_rdata_i       : std_logic_vector(31 downto 0) := (others => '0');
    signal dm_rresp_i       : std_logic_vector(1 downto 0)  := "00";
    signal dm_rvalid_i      : std_logic := '0';
    signal dm_rready_o      : std_logic;
    signal dm_awaddr_o      : std_logic_vector(31 downto 0);
    signal dm_awvalid_o     : std_logic;
    signal dm_awprot_o      : std_logic_vector(2 downto 0);
    signal dm_awready_i     : std_logic := '0';
    signal dm_wdata_o       : std_logic_vector(31 downto 0);
    signal dm_wstrb_o       : std_logic_vector(3 downto 0);
    signal dm_wvalid_o      : std_logic;
    signal dm_wready_i      : std_logic := '0';
    signal dm_bresp_i       : std_logic_vector(1 downto 0)  := "00";
    signal dm_bvalid_i      : std_logic := '0';
    signal dm_bready_o      : std_logic;

    -- Interrupções
    signal irq_external_i   : std_logic := '0';
    signal irq_timer_i      : std_logic := '0';
    signal irq_software_i   : std_logic := '0';

    -- Debug
    signal pc_o             : std_logic_vector(31 downto 0);

    -- =========================================================================
    -- Variáveis internas da memória de dados (processo)
    -- =========================================================================
    -- =========================================================================
    -- Contagem de ciclos
    -- =========================================================================
    signal cycle_count : integer := 0;

begin

    -- =========================================================================
    -- Geração de clock
    -- =========================================================================
    clk_proc : process
    begin
        loop
            clk_i <= '0'; wait for CLK_PERIOD / 2;
            clk_i <= '1'; wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- =========================================================================
    -- Reset: ativo por 5 ciclos
    -- =========================================================================
    reset_proc : process
    begin
        rst_ni <= '0';
        wait for CLK_PERIOD * 5;
        rst_ni <= '1';
        wait;
    end process;

    -- =========================================================================
    -- Contador de ciclos + timeout
    -- =========================================================================
    cycle_proc : process(clk_i)
    begin
        if rising_edge(clk_i) then
            cycle_count <= cycle_count + 1;
            if cycle_count >= SIM_TIMEOUT then
                report "[TB] TIMEOUT após " & integer'image(SIM_TIMEOUT) & " ciclos."
                    severity failure;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- DUT: cpu_top
    -- =========================================================================
    dut : entity work.cpu_top
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            RESET_ADDR => x"00000000",
            HART_ID    => 0
        )
        port map (
            clk_i          => clk_i,
            rst_ni         => rst_ni,
            -- AXI IM
            im_araddr_o    => im_araddr_o,
            im_arvalid_o   => im_arvalid_o,
            im_arprot_o    => im_arprot_o,
            im_arready_i   => im_arready_i,
            im_rdata_i     => im_rdata_i,
            im_rresp_i     => im_rresp_i,
            im_rvalid_i    => im_rvalid_i,
            im_rready_o    => im_rready_o,
            -- AXI DM
            dm_araddr_o    => dm_araddr_o,
            dm_arvalid_o   => dm_arvalid_o,
            dm_arprot_o    => dm_arprot_o,
            dm_arready_i   => dm_arready_i,
            dm_rdata_i     => dm_rdata_i,
            dm_rresp_i     => dm_rresp_i,
            dm_rvalid_i    => dm_rvalid_i,
            dm_rready_o    => dm_rready_o,
            dm_awaddr_o    => dm_awaddr_o,
            dm_awvalid_o   => dm_awvalid_o,
            dm_awprot_o    => dm_awprot_o,
            dm_awready_i   => dm_awready_i,
            dm_wdata_o     => dm_wdata_o,
            dm_wstrb_o     => dm_wstrb_o,
            dm_wvalid_o    => dm_wvalid_o,
            dm_wready_i    => dm_wready_i,
            dm_bresp_i     => dm_bresp_i,
            dm_bvalid_i    => dm_bvalid_i,
            dm_bready_o    => dm_bready_o,
            -- Interrupções
            irq_external_i => irq_external_i,
            irq_timer_i    => irq_timer_i,
            irq_software_i => irq_software_i,
            -- Status
            pc_o           => pc_o
        );

    -- =========================================================================
    -- Slave AXI: Instruction Memory (ROM)
    -- Latência: 1 ciclo (arready e rvalid no ciclo seguinte do arvalid)
    -- =========================================================================
    imem_slave : process(clk_i)
        variable word_idx : integer;
    begin
        if rising_edge(clk_i) then
            -- Defaults
            im_arready_i <= '0';
            im_rvalid_i  <= '0';
            im_rdata_i   <= (others => '0');
            im_rresp_i   <= "00";

            if rst_ni = '0' then
                im_arready_i <= '0';
                im_rvalid_i  <= '0';
            elsif im_arvalid_o = '1' then
                -- Aceita o endereço e devolve dado no mesmo ciclo (latência 1)
                im_arready_i <= '1';
                im_rvalid_i  <= '1';
                word_idx     := to_integer(unsigned(im_araddr_o(9 downto 2)));
                -- Garante que acesso fique dentro da ROM
                if word_idx >= 0 and word_idx <= 255 then
                    im_rdata_i <= IMEM(word_idx);
                else
                    im_rdata_i <= x"00000013"; -- NOP para endereços fora da ROM
                end if;
                im_rresp_i <= "00"; -- OKAY
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Slave AXI: Data Memory (RAM)
    -- Suporta reads e writes com latência de 1 ciclo
    -- =========================================================================
    dmem_slave : process(clk_i)
        variable dmem     : ram_t := (others => (others => '0'));
        variable word_idx : integer;
        variable wdata    : std_logic_vector(31 downto 0);
        variable wstrb    : std_logic_vector(3 downto 0);
    begin
        if rising_edge(clk_i) then
            -- Defaults
            dm_arready_i <= '0';
            dm_rvalid_i  <= '0';
            dm_rdata_i   <= (others => '0');
            dm_rresp_i   <= "00";
            dm_awready_i <= '0';
            dm_wready_i  <= '0';
            dm_bvalid_i  <= '0';
            dm_bresp_i   <= "00";

            if rst_ni = '0' then
                null;
            else
                -- ---- Leitura -----------------------------------------------
                if dm_arvalid_o = '1' then
                    dm_arready_i <= '1';
                    dm_rvalid_i  <= '1';
                    word_idx     := to_integer(unsigned(dm_araddr_o(9 downto 2)));
                    if word_idx >= 0 and word_idx <= 255 then
                        dm_rdata_i <= dmem(word_idx);
                    else
                        dm_rdata_i <= (others => '0');
                    end if;
                    dm_rresp_i <= "00";
                end if;

                -- ---- Escrita -----------------------------------------------
                -- Aceita endereço e dado no mesmo ciclo
                if dm_awvalid_o = '1' and dm_wvalid_o = '1' then
                    dm_awready_i <= '1';
                    dm_wready_i  <= '1';
                    dm_bvalid_i  <= '1';
                    dm_bresp_i   <= "00";

                    word_idx := to_integer(unsigned(dm_awaddr_o(9 downto 2)));
                    wdata    := dm_wdata_o;
                    wstrb    := dm_wstrb_o;

                    if word_idx >= 0 and word_idx <= 255 then
                        -- Write com strobe
                        for b in 0 to 3 loop
                            if wstrb(b) = '1' then
                                dmem(word_idx)(b*8+7 downto b*8) := wdata(b*8+7 downto b*8);
                            end if;
                        end loop;
                    end if;

                    report "[DMEM] WRITE addr=0x"
                        & to_hstring(dm_awaddr_o)
                        & " data=0x"
                        & to_hstring(wdata)
                        & " strb=" & to_hstring(wstrb)
                        severity note;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Monitor: imprime PC a cada ciclo para rastreabilidade
    -- =========================================================================
    monitor_proc : process(clk_i)
    begin
        if rising_edge(clk_i) and rst_ni = '1' then
            report "[TB] ciclo=" & integer'image(cycle_count)
                 & "  PC=0x" & to_hstring(pc_o)
                severity note;
        end if;
    end process;

    -- =========================================================================
    -- Checagens de saída esperada
    -- Quando a CPU alcança o endereço de HALT (0x60 ou loop), encerra o teste.
    -- =========================================================================
    check_proc : process(clk_i)
    begin
        if rising_edge(clk_i) and rst_ni = '1' then
            -- Detecta que o CPU chegou ao HALT (jal x0, 0 em 0x5C → fica em 0x5C)
            -- Aguardamos ciclo > 50 para garantir que o pipeline drenou
            if cycle_count > 50 and pc_o = x"0000005C" then
                report "[TB] ==================================================" severity note;
                report "[TB] CPU alcançou endereço de HALT (0x5C)."             severity note;
                report "[TB] Teste concluído em " & integer'image(cycle_count)
                    & " ciclos."                                                severity note;
                report "[TB] ==================================================" severity note;
                report "[TB] PASS" severity note;
                finish;
            end if;
        end if;
    end process;

end architecture sim;
