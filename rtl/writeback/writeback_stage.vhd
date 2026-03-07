-- =============================================================================
-- writeback_stage.vhd
-- Estágio 5 do Pipeline: Write Back (WB)
--
-- Responsabilidades:
--   - Selecionar o dado a ser escrito no register file:
--       * WB_ALU  : resultado da ALU (ADD, AND, etc.)
--       * WB_MEM  : dado lido da memória (load)
--       * WB_PC4  : PC+4 (destino de retorno de JAL/JALR)
--       * WB_IMM  : imediato (não usado atualmente; reservado)
--   - Gerar sinais de retorno para o register file no estágio Decode
--   - Gerar sinais de forwarding (para a forwarding_unit no Execute)
--
-- Este estágio é puramente combinacional: a escrita sequencial
-- ocorre dentro do register_file.vhd, mapeado no decode_stage.
-- O writeback_stage apenas resolve o mux de dados.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.cpu_pkg.all;

entity writeback_stage is
    generic (
        DATA_WIDTH : integer := XLEN
    );
    port (
        -- ---- Entrada: Registrador MEM/WB ----------------------------------
        mem_wb_i     : in  mem_wb_reg_t;

        -- ---- Saídas para o Register File (Decode) -------------------------
        rd_addr_o    : out std_logic_vector(REG_ADDR_W-1 downto 0);
        rd_data_o    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_we_o      : out std_logic;

        -- ---- Saídas para a Forwarding Unit (Execute) ----------------------
        -- São iguais às saídas do register file, mas expostas diretamente
        fwd_rd_addr_o : out std_logic_vector(REG_ADDR_W-1 downto 0);
        fwd_rd_data_o : out std_logic_vector(DATA_WIDTH-1 downto 0);
        fwd_rd_we_o   : out std_logic
    );
end entity writeback_stage;

architecture rtl of writeback_stage is

    signal wb_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal wb_we   : std_logic;

begin

    -- =========================================================================
    -- Mux de seleção do dado de writeback (combinacional)
    -- =========================================================================
    wb_mux : process(mem_wb_i)
    begin
        case mem_wb_i.ctrl.wb_sel is
            when WB_MEM =>
                -- Instrução de load: dado vem da memória
                wb_data <= mem_wb_i.mem_rdata;
            when WB_PC4 =>
                -- JAL/JALR: salva o endereço de retorno (PC+4)
                wb_data <= mem_wb_i.pc_plus4;
            when WB_IMM =>
                -- WB_IMM: reservado para extensões futuras que passem o imediato até WB.
                -- LUI e AUIPC já usam a ALU (ALU_LUI / ALU_ADD) com wb_sel=WB_ALU,
                -- portanto este caso nunca é atingido no RV32I base.
                -- Mapeado em alu_result para evitar saída indeterminada.
                wb_data <= mem_wb_i.alu_result;
            when others => -- WB_ALU
                -- Instrução ALU (padrão)
                wb_data <= mem_wb_i.alu_result;
        end case;

        -- Write enable: apenas se a instrução requer escrita e é válida
        wb_we <= mem_wb_i.ctrl.reg_write and mem_wb_i.valid;
    end process wb_mux;

    -- =========================================================================
    -- Saídas para o Register File (via decode_stage)
    -- =========================================================================
    rd_addr_o <= mem_wb_i.rd_addr;
    rd_data_o <= wb_data;
    rd_we_o   <= wb_we;

    -- =========================================================================
    -- Saídas para a Forwarding Unit (cópia dos mesmos sinais)
    -- =========================================================================
    fwd_rd_addr_o <= mem_wb_i.rd_addr;
    fwd_rd_data_o <= wb_data;
    fwd_rd_we_o   <= wb_we;

end architecture rtl;
