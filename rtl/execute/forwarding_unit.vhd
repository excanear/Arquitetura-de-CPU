-- =============================================================================
-- forwarding_unit.vhd
-- Unidade de Forwarding (Bypassing) – Pipeline de 5 Estágios RV32I
--
-- Resolve hazards de dados RAW (Read After Write) sem stall, redirecionando
-- resultados de estágios mais avançados de volta ao Execute.
--
-- Fontes de forwarding consideradas:
--   EX/MEM : resultado da ALU do ciclo anterior (forwarding EX→EX, 1 ciclo)
--   MEM/WB : dado do ciclo retrasado (resultado ALU ou dado de memória)
--
-- Codificação do seletor de forwarding:
--   "00" → sem forwarding (usa valor do register file lido no Decode)
--   "01" → forward do registrador EX/MEM (resultado ALU)
--   "10" → forward do registrador MEM/WB (resultado ALU ou dado de load)
--
-- Notas:
--   - Load-use hazard (load seguido imediatamente de instrução que usa o dado)
--     não é resolvível exclusivamente por forwarding → necessita de 1 ciclo de stall.
--     Este sinal (load_use_hazard_o) deve ser utilizado pela HDU (futura).
--   - O módulo é puramente combinacional.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity forwarding_unit is
    generic (
        ADDR_WIDTH : integer := REG_ADDR_W
    );
    port (
        -- Endereços de fonte do estágio Execute (lidos no Decode)
        ex_rs1_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        ex_rs2_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Estágio EX/MEM: registrador de destino e controle
        exmem_rd_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        exmem_reg_write_i: in  std_logic;
        exmem_mem_read_i : in  std_logic;  -- '1' se instrução em MEM é um load

        -- Estágio MEM/WB: registrador de destino e controle
        memwb_rd_addr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        memwb_reg_write_i: in  std_logic;

        -- Seletores de forwarding para operandos A e B da ALU
        -- "00"=sem fwd, "01"=fwd EX/MEM, "10"=fwd MEM/WB
        fwd_a_sel_o    : out std_logic_vector(1 downto 0);
        fwd_b_sel_o    : out std_logic_vector(1 downto 0);

        -- Load-use hazard: instrução no EX/MEM é um load e o destino
        -- coincide com um fonte do estágio ID (próxima instrução)
        -- Nota: detectado aqui mas inserção de stall feita pela HDU
        load_use_hazard_o : out std_logic
    );
end entity forwarding_unit;

architecture rtl of forwarding_unit is

    -- Constantes de seleção de forwarding
    constant FWD_NONE   : std_logic_vector(1 downto 0) := "00";
    constant FWD_EXMEM  : std_logic_vector(1 downto 0) := "01";
    constant FWD_MEMWB  : std_logic_vector(1 downto 0) := "10";

begin

    -- =========================================================================
    -- Forwarding para Operando A (RS1)
    -- =========================================================================
    fwd_a_proc : process(
        ex_rs1_addr_i,
        exmem_rd_addr_i, exmem_reg_write_i,
        memwb_rd_addr_i, memwb_reg_write_i
    )
    begin
        fwd_a_sel_o <= FWD_NONE;

        -- Prioridade: EX/MEM precede MEM/WB (dado mais recente)
        if exmem_reg_write_i = '1' and
           unsigned(exmem_rd_addr_i) /= 0 and
           exmem_rd_addr_i = ex_rs1_addr_i then
            fwd_a_sel_o <= FWD_EXMEM;
        elsif memwb_reg_write_i = '1' and
              unsigned(memwb_rd_addr_i) /= 0 and
              memwb_rd_addr_i = ex_rs1_addr_i then
            fwd_a_sel_o <= FWD_MEMWB;
        end if;
    end process fwd_a_proc;

    -- =========================================================================
    -- Forwarding para Operando B (RS2)
    -- =========================================================================
    fwd_b_proc : process(
        ex_rs2_addr_i,
        exmem_rd_addr_i, exmem_reg_write_i,
        memwb_rd_addr_i, memwb_reg_write_i
    )
    begin
        fwd_b_sel_o <= FWD_NONE;

        if exmem_reg_write_i = '1' and
           unsigned(exmem_rd_addr_i) /= 0 and
           exmem_rd_addr_i = ex_rs2_addr_i then
            fwd_b_sel_o <= FWD_EXMEM;
        elsif memwb_reg_write_i = '1' and
              unsigned(memwb_rd_addr_i) /= 0 and
              memwb_rd_addr_i = ex_rs2_addr_i then
            fwd_b_sel_o <= FWD_MEMWB;
        end if;
    end process fwd_b_proc;

    -- =========================================================================
    -- Detecção de Load-Use Hazard
    -- Ocorre quando a instrução em MEM é um load e a instrução atualmente
    -- em EX precisa do valor antes de ele estar disponível.
    -- A resolução requer stall de 1 ciclo (inserido pelo cpu_top).
    -- =========================================================================
    load_use_proc : process(
        exmem_rd_addr_i, exmem_reg_write_i, exmem_mem_read_i,
        ex_rs1_addr_i, ex_rs2_addr_i
    )
    begin
        -- Só há load-use quando a instrução em MEM é efetivamente um load
        -- (mem_read='1'). Outras instruções write-back não geram stall pois
        -- o forwarding EX/MEM já resolve o hazard em 1 ciclo.
        if exmem_mem_read_i = '1' and
           exmem_reg_write_i = '1' and
           unsigned(exmem_rd_addr_i) /= 0 and
           (exmem_rd_addr_i = ex_rs1_addr_i or
            exmem_rd_addr_i = ex_rs2_addr_i) then
            load_use_hazard_o <= '1';
        else
            load_use_hazard_o <= '0';
        end if;
    end process load_use_proc;

end architecture rtl;
