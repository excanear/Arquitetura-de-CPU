-- =============================================================================
-- memory_stage.vhd
-- Estágio 4 do Pipeline: Memory Access (MEM)
--
-- Responsabilidades:
--   - Acionar a Load/Store Unit para loads e stores
--   - Propagar sinais de controle e resultado da ALU para o WB
--   - Inserir stall enquanto a LSU aguarda resposta AXI
--   - Gerar o registrador de pipeline MEM/WB
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;
use work.axi4_pkg.all;

entity memory_stage is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        clk_i       : in  std_logic;
        rst_ni      : in  std_logic;

        -- Stall: gerado pela própria LSU (upstream) ou externo
        -- mem_stall_o propaga para o topo para congelar os estágios anteriores
        stall_i     : in  std_logic;
        flush_i     : in  std_logic;

        -- ---- Entrada: Registrador EX/MEM ----------------------------------
        ex_mem_i    : in  ex_mem_reg_t;

        -- ---- Interface AXI4-Lite para Data Memory -------------------------
        dm_araddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_arvalid_o : out std_logic;
        dm_arprot_o  : out std_logic_vector(2 downto 0);
        dm_arready_i : in  std_logic;
        dm_rdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_rresp_i   : in  std_logic_vector(1 downto 0);
        dm_rvalid_i  : in  std_logic;
        dm_rready_o  : out std_logic;
        dm_awaddr_o  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_awvalid_o : out std_logic;
        dm_awprot_o  : out std_logic_vector(2 downto 0);
        dm_awready_i : in  std_logic;
        dm_wdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dm_wstrb_o   : out std_logic_vector(3 downto 0);
        dm_wvalid_o  : out std_logic;
        dm_wready_i  : in  std_logic;
        dm_bresp_i   : in  std_logic_vector(1 downto 0);
        dm_bvalid_i  : in  std_logic;
        dm_bready_o  : out std_logic;

        -- ---- Saídas de stall para o topo ----------------------------------
        mem_stall_o : out std_logic;

        -- ---- Saída: Registrador MEM/WB ------------------------------------
        mem_wb_o    : out mem_wb_reg_t
    );
end entity memory_stage;

architecture rtl of memory_stage is

    -- =========================================================================
    -- Sinais da LSU
    -- =========================================================================
    signal lsu_rdata      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal lsu_sc_result  : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal lsu_rdata_valid: std_logic;
    signal lsu_stall      : std_logic;

    -- =========================================================================
    -- Registrador MEM/WB
    -- =========================================================================
    signal mem_wb_r : mem_wb_reg_t;

begin

    -- =========================================================================
    -- Instância: Load/Store Unit
    -- =========================================================================
    u_lsu : entity work.load_store_unit
        generic map (DATA_WIDTH => DATA_WIDTH)
        port map (
            clk_i         => clk_i,
            rst_ni        => rst_ni,
            mem_read_i    => ex_mem_i.ctrl.mem_read,
            mem_write_i   => ex_mem_i.ctrl.mem_write,
            mem_size_i    => ex_mem_i.ctrl.mem_size,
            addr_i        => ex_mem_i.alu_result,
            wdata_i       => ex_mem_i.rs2_data,
            rdata_o       => lsu_rdata,
            rdata_valid_o => lsu_rdata_valid,
            mem_stall_o   => lsu_stall,
            -- AMO / LR / SC
            amo_i         => ex_mem_i.ctrl.amo,
            amo_is_lr_i   => ex_mem_i.ctrl.amo_is_lr,
            amo_is_sc_i   => ex_mem_i.ctrl.amo_is_sc,
            amo_funct5_i  => ex_mem_i.ctrl.amo_funct5,
            sc_result_o   => lsu_sc_result,
            -- AXI AR
            dm_araddr_o   => dm_araddr_o,
            dm_arvalid_o  => dm_arvalid_o,
            dm_arprot_o   => dm_arprot_o,
            dm_arready_i  => dm_arready_i,
            -- AXI R
            dm_rdata_i    => dm_rdata_i,
            dm_rresp_i    => dm_rresp_i,
            dm_rvalid_i   => dm_rvalid_i,
            dm_rready_o   => dm_rready_o,
            -- AXI AW
            dm_awaddr_o   => dm_awaddr_o,
            dm_awvalid_o  => dm_awvalid_o,
            dm_awprot_o   => dm_awprot_o,
            dm_awready_i  => dm_awready_i,
            -- AXI W
            dm_wdata_o    => dm_wdata_o,
            dm_wstrb_o    => dm_wstrb_o,
            dm_wvalid_o   => dm_wvalid_o,
            dm_wready_i   => dm_wready_i,
            -- AXI B
            dm_bresp_i    => dm_bresp_i,
            dm_bvalid_i   => dm_bvalid_i,
            dm_bready_o   => dm_bready_o
        );

    mem_stall_o <= lsu_stall;

    -- =========================================================================
    -- Registrador MEM/WB
    -- =========================================================================
    memwb_reg : process(clk_i, rst_ni)
    begin
        if rst_ni = '0' then
            mem_wb_r <= MEM_WB_NOP;
        elsif rising_edge(clk_i) then
            if flush_i = '1' then
                mem_wb_r <= MEM_WB_NOP;
            elsif stall_i = '0' and lsu_stall = '0' then
                mem_wb_r.pc_plus4   <= ex_mem_i.pc_plus4;
                mem_wb_r.alu_result <= ex_mem_i.alu_result;
                -- Dado de memória: atualiza quando rdata_valid (load/AMO) 
                -- Para SC.W: usa lsu_sc_result (0=ok, 1=fail)
                if lsu_rdata_valid = '1' then
                    if ex_mem_i.ctrl.amo_is_sc = '1' then
                        mem_wb_r.mem_rdata <= lsu_sc_result;
                    else
                        mem_wb_r.mem_rdata <= lsu_rdata;
                    end if;
                else
                    mem_wb_r.mem_rdata <= (others => '0');
                end if;
                mem_wb_r.rd_addr    <= ex_mem_i.rd_addr;
                mem_wb_r.ctrl       <= ex_mem_i.ctrl;
                mem_wb_r.valid      <= ex_mem_i.valid;
            end if;
        end if;
    end process memwb_reg;

    mem_wb_o <= mem_wb_r;

end architecture rtl;
