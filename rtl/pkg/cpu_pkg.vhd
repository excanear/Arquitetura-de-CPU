-- =============================================================================
-- cpu_pkg.vhd
-- Pacote central da CPU RV32I
-- Define tipos, constantes, enumerações e funções auxiliares compartilhadas
-- por todos os estágios do pipeline.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cpu_pkg is

    -- =========================================================================
    -- Parâmetros Globais
    -- =========================================================================
    constant XLEN       : integer := 32;   -- Largura do registrador (RV32)
    constant REG_ADDR_W : integer := 5;    -- Bits para endereçar 32 registradores
    constant PC_RESET   : std_logic_vector(XLEN-1 downto 0) := x"00000000";
    constant NOP_INSTR  : std_logic_vector(XLEN-1 downto 0) := x"00000013"; -- addi x0, x0, 0

    -- =========================================================================
    -- Campos de Instrução RV32I (posições de bits)
    -- =========================================================================
    constant OPCODE_HI  : integer := 6;
    constant OPCODE_LO  : integer := 0;
    constant RD_HI      : integer := 11;
    constant RD_LO      : integer := 7;
    constant FUNCT3_HI  : integer := 14;
    constant FUNCT3_LO  : integer := 12;
    constant RS1_HI     : integer := 19;
    constant RS1_LO     : integer := 15;
    constant RS2_HI     : integer := 24;
    constant RS2_LO     : integer := 20;
    constant FUNCT7_HI  : integer := 31;
    constant FUNCT7_LO  : integer := 25;

    -- =========================================================================
    -- Opcodes RV32I (bits [6:0])
    -- =========================================================================
    constant OPC_LOAD   : std_logic_vector(6 downto 0) := "0000011"; -- LB LH LW LBU LHU
    constant OPC_STORE  : std_logic_vector(6 downto 0) := "0100011"; -- SB SH SW
    constant OPC_BRANCH : std_logic_vector(6 downto 0) := "1100011"; -- BEQ BNE BLT BGE BLTU BGEU
    constant OPC_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OPC_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OPC_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OPC_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OPC_ALUI   : std_logic_vector(6 downto 0) := "0010011"; -- ALU Imediato
    constant OPC_ALUR   : std_logic_vector(6 downto 0) := "0110011"; -- ALU Registrador
    constant OPC_FENCE  : std_logic_vector(6 downto 0) := "0001111";
    constant OPC_SYSTEM : std_logic_vector(6 downto 0) := "1110011"; -- ECALL EBREAK CSR*
    constant OPC_AMO    : std_logic_vector(6 downto 0) := "0101111"; -- RV32A atomic (LR/SC/AMO)

    -- =========================================================================
    -- funct3 – Operações de Branch
    -- =========================================================================
    constant F3_BEQ  : std_logic_vector(2 downto 0) := "000";
    constant F3_BNE  : std_logic_vector(2 downto 0) := "001";
    constant F3_BLT  : std_logic_vector(2 downto 0) := "100";
    constant F3_BGE  : std_logic_vector(2 downto 0) := "101";
    constant F3_BLTU : std_logic_vector(2 downto 0) := "110";
    constant F3_BGEU : std_logic_vector(2 downto 0) := "111";

    -- =========================================================================
    -- funct3 – Operações Load/Store
    -- =========================================================================
    constant F3_BYTE  : std_logic_vector(2 downto 0) := "000"; -- LB / SB
    constant F3_HALF  : std_logic_vector(2 downto 0) := "001"; -- LH / SH
    constant F3_WORD  : std_logic_vector(2 downto 0) := "010"; -- LW / SW
    constant F3_BYTEU : std_logic_vector(2 downto 0) := "100"; -- LBU
    constant F3_HALFU : std_logic_vector(2 downto 0) := "101"; -- LHU

    -- =========================================================================
    -- funct3 – Operações ALU (tipo-I e tipo-R)
    -- =========================================================================
    constant F3_ADDSUB : std_logic_vector(2 downto 0) := "000"; -- ADD/SUB
    constant F3_SLL    : std_logic_vector(2 downto 0) := "001";
    constant F3_SLT    : std_logic_vector(2 downto 0) := "010";
    constant F3_SLTU   : std_logic_vector(2 downto 0) := "011";
    constant F3_XOR    : std_logic_vector(2 downto 0) := "100";
    constant F3_SRL    : std_logic_vector(2 downto 0) := "101"; -- SRL/SRA
    constant F3_OR     : std_logic_vector(2 downto 0) := "110";
    constant F3_AND    : std_logic_vector(2 downto 0) := "111";

    -- =========================================================================
    -- Enumeração: Operações da ALU (decodificado pelo controle)
    -- RV32I + extensão M (Multiply/Divide)
    -- =========================================================================
    type alu_op_t is (
        -- ---- RV32I base ------------------------------------------------
        ALU_ADD,    -- Adição
        ALU_SUB,    -- Subtração
        ALU_AND,    -- AND lógico
        ALU_OR,     -- OR lógico
        ALU_XOR,    -- XOR lógico
        ALU_SLT,    -- Set Less Than (com sinal)
        ALU_SLTU,   -- Set Less Than (sem sinal)
        ALU_SLL,    -- Shift Left Logical
        ALU_SRL,    -- Shift Right Logical
        ALU_SRA,    -- Shift Right Arithmetic
        ALU_LUI,    -- Passagem do imediato (para LUI/AUIPC)
        ALU_NOP,    -- Sem operação
        -- ---- RV32M: Multiplicação ----------------------------------------
        ALU_MUL,    -- Produto 32 bits baixos (signed × signed)
        ALU_MULH,   -- Produto 32 bits altos  (signed × signed)
        ALU_MULHSU, -- Produto 32 bits altos  (signed × unsigned)
        ALU_MULHU,  -- Produto 32 bits altos  (unsigned × unsigned)
        -- ---- RV32M: Divisão e Resto -------------------------------------
        ALU_DIV,    -- Quociente (signed)
        ALU_DIVU,   -- Quociente (unsigned)
        ALU_REM,    -- Resto (signed)
        ALU_REMU    -- Resto (unsigned)
    );

    -- =========================================================================
    -- Enumeração: Tipos de imediato RV32I
    -- =========================================================================
    type imm_type_t is (
        IMM_I,     -- Tipo I: loads, ALU imediatos, JALR
        IMM_S,     -- Tipo S: stores
        IMM_B,     -- Tipo B: branches
        IMM_U,     -- Tipo U: LUI, AUIPC
        IMM_J,     -- Tipo J: JAL
        IMM_NONE   -- Sem imediato
    );

    -- =========================================================================
    -- Enumeração: Seletor do operando B da ALU
    -- =========================================================================
    type alu_src_t is (
        ALUB_REG,  -- Operando B vem do registrador RS2
        ALUB_IMM   -- Operando B vem do imediato
    );

    -- =========================================================================
    -- Enumeração: Seletor do dado a ser escrito no registrador (WB)
    -- =========================================================================
    type wb_sel_t is (
        WB_ALU,    -- Resultado da ALU
        WB_MEM,    -- Dado lido da memória
        WB_PC4,    -- PC+4 (para JAL/JALR)
        WB_IMM     -- Imediato (para LUI – passthrough)
    );

    -- =========================================================================
    -- Enumeração: Seletor do próximo PC
    -- =========================================================================
    type pc_sel_t is (
        PC_PLUS4,  -- PC + 4 (fluxo normal)
        PC_BRANCH, -- PC de destino de branch (cálculo no execute)
        PC_JALR,   -- PC calculado para JALR (rs1 + imm)
        PC_JAL     -- PC de destino para JAL
    );

    -- =========================================================================
    -- Enumeração: seletor do operando A da ALU
    -- =========================================================================
    type alu_a_src_t is (
        ALUA_REG,  -- Operando A vem de RS1
        ALUA_PC    -- Operando A vem do PC (para AUIPC)
    );

    -- =========================================================================
    -- Estrutura de Sinais de Controle (decodificada no estágio Decode)
    -- Propagada pelo pipeline em registradores de estágio.
    -- =========================================================================
    type ctrl_signals_t is record
        reg_write  : std_logic;                     -- Habilita escrita no register file
        mem_read   : std_logic;                     -- Habilita leitura da memória de dados
        mem_write  : std_logic;                     -- Habilita escrita na memória de dados
        branch     : std_logic;                     -- Instrução de branch condicional
        jal        : std_logic;                     -- Instrução JAL
        jalr       : std_logic;                     -- Instrução JALR
        alu_op     : alu_op_t;                      -- Operação a ser executada pela ALU
        alu_src    : alu_src_t;                     -- Fonte do operando B
        alu_a_src  : alu_a_src_t;                   -- Fonte do operando A
        wb_sel     : wb_sel_t;                      -- Seleção do dado de writeback
        mem_size   : std_logic_vector(2 downto 0);  -- funct3 para load/store
        csr_access : std_logic;                     -- Instrução CSR
        ecall      : std_logic;                     -- ECALL
        ebreak     : std_logic;                     -- EBREAK
        mret       : std_logic;                     -- MRET (retorno de trap M-mode)
        sret       : std_logic;                     -- SRET (retorno de trap S-mode)
        fence      : std_logic;                     -- FENCE / FENCE.I
        sfence_vma : std_logic;                     -- SFENCE.VMA (invalida TLB)
        illegal    : std_logic;                     -- Instrução ilegal detectada
        -- ---- RV32A: Atomic Memory Operations ----------------------------
        amo        : std_logic;                     -- Qualquer AMO (LR/SC/AMOXX)
        amo_is_lr  : std_logic;                     -- LR.W
        amo_is_sc  : std_logic;                     -- SC.W
        amo_funct5 : std_logic_vector(4 downto 0);  -- funct5 da instrução AMO
    end record ctrl_signals_t;

    -- Sinais de controle nulos (flush/bolha no pipeline)
    constant CTRL_NOP : ctrl_signals_t := (
        reg_write  => '0',
        mem_read   => '0',
        mem_write  => '0',
        branch     => '0',
        jal        => '0',
        jalr       => '0',
        alu_op     => ALU_NOP,
        alu_src    => ALUB_REG,
        alu_a_src  => ALUA_REG,
        wb_sel     => WB_ALU,
        mem_size   => "010",
        csr_access => '0',
        ecall      => '0',
        ebreak     => '0',
        mret       => '0',
        sret       => '0',
        fence      => '0',
        sfence_vma => '0',
        illegal    => '0',
        amo        => '0',
        amo_is_lr  => '0',
        amo_is_sc  => '0',
        amo_funct5 => "00000"
    );

    -- =========================================================================
    -- Registro de Pipeline IF/ID
    -- =========================================================================
    type if_id_reg_t is record
        pc          : std_logic_vector(XLEN-1 downto 0);
        pc_plus4    : std_logic_vector(XLEN-1 downto 0);
        instruction : std_logic_vector(XLEN-1 downto 0);
        valid       : std_logic; -- '0' indica bolha
    end record if_id_reg_t;

    constant IF_ID_NOP : if_id_reg_t := (
        pc          => (others => '0'),
        pc_plus4    => (others => '0'),
        instruction => NOP_INSTR,
        valid       => '0'
    );

    -- =========================================================================
    -- Registro de Pipeline ID/EX
    -- =========================================================================
    type id_ex_reg_t is record
        pc          : std_logic_vector(XLEN-1 downto 0);
        pc_plus4    : std_logic_vector(XLEN-1 downto 0);
        rs1_data    : std_logic_vector(XLEN-1 downto 0);
        rs2_data    : std_logic_vector(XLEN-1 downto 0);
        imm         : std_logic_vector(XLEN-1 downto 0);
        rs1_addr    : std_logic_vector(REG_ADDR_W-1 downto 0);
        rs2_addr    : std_logic_vector(REG_ADDR_W-1 downto 0);
        rd_addr     : std_logic_vector(REG_ADDR_W-1 downto 0);
        ctrl        : ctrl_signals_t;
        valid       : std_logic;
    end record id_ex_reg_t;

    -- =========================================================================
    -- Registro de Pipeline EX/MEM
    -- =========================================================================
    type ex_mem_reg_t is record
        pc          : std_logic_vector(XLEN-1 downto 0); -- PC da instrução
        pc_plus4    : std_logic_vector(XLEN-1 downto 0);
        alu_result  : std_logic_vector(XLEN-1 downto 0);
        rs2_data    : std_logic_vector(XLEN-1 downto 0); -- dado para store
        rd_addr     : std_logic_vector(REG_ADDR_W-1 downto 0);
        branch_tgt  : std_logic_vector(XLEN-1 downto 0);
        branch_taken: std_logic;
        ctrl        : ctrl_signals_t;
        valid       : std_logic;
    end record ex_mem_reg_t;

    -- =========================================================================
    -- Registro de Pipeline MEM/WB
    -- =========================================================================
    type mem_wb_reg_t is record
        pc_plus4    : std_logic_vector(XLEN-1 downto 0);
        alu_result  : std_logic_vector(XLEN-1 downto 0);
        mem_rdata   : std_logic_vector(XLEN-1 downto 0);
        rd_addr     : std_logic_vector(REG_ADDR_W-1 downto 0);
        ctrl        : ctrl_signals_t;
        valid       : std_logic;
    end record mem_wb_reg_t;

    -- =========================================================================
    -- Constantes NOP para registradores de pipeline
    -- =========================================================================
    constant ID_EX_NOP : id_ex_reg_t := (
        pc       => (others => '0'),
        pc_plus4 => (others => '0'),
        rs1_data => (others => '0'),
        rs2_data => (others => '0'),
        imm      => (others => '0'),
        rs1_addr => (others => '0'),
        rs2_addr => (others => '0'),
        rd_addr  => (others => '0'),
        ctrl     => CTRL_NOP,
        valid    => '0'
    );

    constant EX_MEM_NOP : ex_mem_reg_t := (
        pc           => (others => '0'),
        pc_plus4     => (others => '0'),
        alu_result   => (others => '0'),
        rs2_data     => (others => '0'),
        rd_addr      => (others => '0'),
        branch_tgt   => (others => '0'),
        branch_taken => '0',
        ctrl         => CTRL_NOP,
        valid        => '0'
    );

    constant MEM_WB_NOP : mem_wb_reg_t := (
        pc_plus4   => (others => '0'),
        alu_result => (others => '0'),
        mem_rdata  => (others => '0'),
        rd_addr    => (others => '0'),
        ctrl       => CTRL_NOP,
        valid      => '0'
    );

    -- =========================================================================
    -- Funções auxiliares
    -- =========================================================================

    -- Extensão de sinal de N para XLEN bits
    function sign_extend(val : std_logic_vector; result_len : integer)
        return std_logic_vector;

    -- Extensão sem sinal (zero-extend) de N para XLEN bits
    function zero_extend(val : std_logic_vector; result_len : integer)
        return std_logic_vector;

end package cpu_pkg;

-- =============================================================================
-- Corpo do pacote
-- =============================================================================
package body cpu_pkg is

    function sign_extend(val : std_logic_vector; result_len : integer)
        return std_logic_vector is
        variable result : std_logic_vector(result_len-1 downto 0);
    begin
        result := (others => val(val'high));
        result(val'length-1 downto 0) := val;
        return result;
    end function sign_extend;

    function zero_extend(val : std_logic_vector; result_len : integer)
        return std_logic_vector is
        variable result : std_logic_vector(result_len-1 downto 0);
    begin
        result := (others => '0');
        result(val'length-1 downto 0) := val;
        return result;
    end function zero_extend;

end package body cpu_pkg;
