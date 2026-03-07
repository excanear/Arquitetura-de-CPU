-- =============================================================================
-- axi4_pkg.vhd
-- Pacote com definições do barramento AXI4-Lite
-- Utilizado pelas interfaces de instruction memory e data memory
-- Referência: ARM IHI0022E – AXI4-Lite Specification
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package axi4_pkg is

    -- =========================================================================
    -- Constantes AXI4-Lite
    -- =========================================================================
    constant AXI_ADDR_W : integer := 32;  -- Largura do barramento de endereço
    constant AXI_DATA_W : integer := 32;  -- Largura do barramento de dados
    constant AXI_STRB_W : integer := AXI_DATA_W / 8; -- Strobe = 4 bytes

    -- Responses BRESP / RRESP
    constant AXI_RESP_OKAY   : std_logic_vector(1 downto 0) := "00";
    constant AXI_RESP_EXOKAY : std_logic_vector(1 downto 0) := "01"; -- não suportado em Lite
    constant AXI_RESP_SLVERR : std_logic_vector(1 downto 0) := "10";
    constant AXI_RESP_DECERR : std_logic_vector(1 downto 0) := "11";

    -- =========================================================================
    -- Canal de Endereço de Leitura (AR) – Master → Slave
    -- =========================================================================
    type axi4l_ar_m2s_t is record
        araddr  : std_logic_vector(AXI_ADDR_W-1 downto 0);
        arvalid : std_logic;
        arprot  : std_logic_vector(2 downto 0); -- proteção (privilégio, segurança, dados/instr)
    end record axi4l_ar_m2s_t;

    -- Canal de Endereço de Leitura (AR) – Slave → Master
    type axi4l_ar_s2m_t is record
        arready : std_logic;
    end record axi4l_ar_s2m_t;

    -- =========================================================================
    -- Canal de Dados de Leitura (R) – Slave → Master
    -- =========================================================================
    type axi4l_r_s2m_t is record
        rdata   : std_logic_vector(AXI_DATA_W-1 downto 0);
        rresp   : std_logic_vector(1 downto 0);
        rvalid  : std_logic;
    end record axi4l_r_s2m_t;

    -- Canal de Dados de Leitura (R) – Master → Slave
    type axi4l_r_m2s_t is record
        rready  : std_logic;
    end record axi4l_r_m2s_t;

    -- =========================================================================
    -- Canal de Endereço de Escrita (AW) – Master → Slave
    -- =========================================================================
    type axi4l_aw_m2s_t is record
        awaddr  : std_logic_vector(AXI_ADDR_W-1 downto 0);
        awvalid : std_logic;
        awprot  : std_logic_vector(2 downto 0);
    end record axi4l_aw_m2s_t;

    -- Canal de Endereço de Escrita (AW) – Slave → Master
    type axi4l_aw_s2m_t is record
        awready : std_logic;
    end record axi4l_aw_s2m_t;

    -- =========================================================================
    -- Canal de Dados de Escrita (W) – Master → Slave
    -- =========================================================================
    type axi4l_w_m2s_t is record
        wdata   : std_logic_vector(AXI_DATA_W-1 downto 0);
        wstrb   : std_logic_vector(AXI_STRB_W-1 downto 0);
        wvalid  : std_logic;
    end record axi4l_w_m2s_t;

    -- Canal de Dados de Escrita (W) – Slave → Master
    type axi4l_w_s2m_t is record
        wready  : std_logic;
    end record axi4l_w_s2m_t;

    -- =========================================================================
    -- Canal de Resposta de Escrita (B) – Slave → Master
    -- =========================================================================
    type axi4l_b_s2m_t is record
        bresp   : std_logic_vector(1 downto 0);
        bvalid  : std_logic;
    end record axi4l_b_s2m_t;

    -- Canal de Resposta de Escrita (B) – Master → Slave
    type axi4l_b_m2s_t is record
        bready  : std_logic;
    end record axi4l_b_m2s_t;

    -- =========================================================================
    -- Agregado completo: interface AXI4-Lite de leitura (Read Channel)
    -- Conveniente para interligar fetch stage com instruction memory
    -- =========================================================================
    type axi4l_read_m2s_t is record
        ar : axi4l_ar_m2s_t;
        r  : axi4l_r_m2s_t;
    end record axi4l_read_m2s_t;

    type axi4l_read_s2m_t is record
        ar : axi4l_ar_s2m_t;
        r  : axi4l_r_s2m_t;
    end record axi4l_read_s2m_t;

    -- =========================================================================
    -- Agregado completo: interface AXI4-Lite (leitura + escrita)
    -- Utilizado pelo estágio Memory (data memory)
    -- =========================================================================
    type axi4l_m2s_t is record
        ar : axi4l_ar_m2s_t;
        r  : axi4l_r_m2s_t;
        aw : axi4l_aw_m2s_t;
        w  : axi4l_w_m2s_t;
        b  : axi4l_b_m2s_t;
    end record axi4l_m2s_t;

    type axi4l_s2m_t is record
        ar : axi4l_ar_s2m_t;
        r  : axi4l_r_s2m_t;
        aw : axi4l_aw_s2m_t;
        w  : axi4l_w_s2m_t;
        b  : axi4l_b_s2m_t;
    end record axi4l_s2m_t;

    -- =========================================================================
    -- Valores padrão (reset / desconectado)
    -- =========================================================================
    constant AXI4L_AR_M2S_INIT : axi4l_ar_m2s_t := (
        araddr  => (others => '0'),
        arvalid => '0',
        arprot  => "000"
    );

    constant AXI4L_AW_M2S_INIT : axi4l_aw_m2s_t := (
        awaddr  => (others => '0'),
        awvalid => '0',
        awprot  => "000"
    );

    constant AXI4L_W_M2S_INIT : axi4l_w_m2s_t := (
        wdata   => (others => '0'),
        wstrb   => (others => '0'),
        wvalid  => '0'
    );

    constant AXI4L_M2S_INIT : axi4l_m2s_t := (
        ar => AXI4L_AR_M2S_INIT,
        r  => (rready => '0'),
        aw => AXI4L_AW_M2S_INIT,
        w  => AXI4L_W_M2S_INIT,
        b  => (bready => '0')
    );

    constant AXI4L_S2M_INIT : axi4l_s2m_t := (
        ar => (arready => '0'),
        r  => (rdata => (others => '0'), rresp => AXI_RESP_OKAY, rvalid => '0'),
        aw => (awready => '0'),
        w  => (wready => '0'),
        b  => (bresp => AXI_RESP_OKAY, bvalid => '0')
    );

    -- =========================================================================
    -- Função auxiliar: gera strobe de byte-enable a partir do tamanho e endereço
    -- size: "00"=byte, "01"=half, "10"=word
    -- =========================================================================
    function axi_strobe(addr : std_logic_vector(1 downto 0);
                        size : std_logic_vector(1 downto 0))
        return std_logic_vector;

end package axi4_pkg;

-- =============================================================================
package body axi4_pkg is

    function axi_strobe(addr : std_logic_vector(1 downto 0);
                        size : std_logic_vector(1 downto 0))
        return std_logic_vector is
        variable strb : std_logic_vector(3 downto 0) := "0000";
    begin
        case size is
            when "10" =>                          -- word (4 bytes)
                strb := "1111";
            when "01" =>                          -- halfword (2 bytes)
                if addr(1) = '0' then
                    strb := "0011";
                else
                    strb := "1100";
                end if;
            when others =>                        -- byte
                case addr is
                    when "00"   => strb := "0001";
                    when "01"   => strb := "0010";
                    when "10"   => strb := "0100";
                    when others => strb := "1000";
                end case;
        end case;
        return strb;
    end function axi_strobe;

end package body axi4_pkg;
