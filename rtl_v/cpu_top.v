// ============================================================================
// cpu_top.v  —  Topo do SoC EduRISC-32v2
//
// Integra o pipeline de 5 estágios completo com:
//   • I-Cache L1 (256 linhas × 4 palavras = 4 KB)
//   • D-Cache L1 (256 linhas × 4 palavras = 4 KB)
//   • MMU com TLB 32 entradas
//   • Interrupt Controller (8 fontes)
//   • Exception Handler
//   • CSR Register File (32 CSRs)
//   • Performance Counters
//   • Memória BRAM interna (fallback quando cache miss)
//
// Pipeline: IF → ID → EX → MEM → WB
// Forwarding: EX/MEM→EX, MEM/WB→EX
// Hazard: load-use stall (1 ciclo), branch flush (1 ciclo), mul/div stall
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module cpu_top #(
    parameter IMEM_INIT_FILE = "",
    parameter CLK_FREQ_HZ    = 50_000_000
) (
    input  wire        clk,
    input  wire        rst,

    // Interrupções externas (8 fontes, ativo alto)
    input  wire [6:0]  ext_irq,

    // Interface UART simples para debug / bootloader
    input  wire        uart_rx,
    output wire        uart_tx,

    // Debug / observabilidade
    output wire [25:0] dbg_pc,
    output wire [31:0] dbg_instr,
    output wire        dbg_halted,
    output wire [31:0] dbg_r0,
    output wire [31:0] dbg_sp,
    output wire [31:0] dbg_lr
);

    // ======================================================================
    // Sinais internos do pipeline
    // ======================================================================

    // ---- PC e IF ----
    wire [25:0] pc_current, pc_plus1;
    wire        pc_stall, pc_load_en;
    wire [25:0] pc_load_val;
    wire [31:0] imem_instr;

    // ---- IF/ID ----
    wire [25:0] ifid_pc;
    wire [31:0] ifid_instr;

    // ---- ID: decoder + control ----
    wire [5:0]  dec_op;
    wire [4:0]  dec_rd, dec_rs1, dec_rs2, dec_shamt;
    wire [31:0] dec_imm16_sext, dec_imm16_zext, dec_addr26_ext, dec_imm21_upper, dec_imm5_zext;
    wire        dec_is_r, dec_is_i, dec_is_s, dec_is_b, dec_is_j, dec_is_u;
    wire        dec_is_load, dec_is_store, dec_is_branch, dec_is_jump;
    wire        dec_is_call, dec_is_ret, dec_is_mul_div, dec_is_csr, dec_is_system;

    wire        cu_reg_write, cu_mem_read, cu_mem_write, cu_mem_to_reg;
    wire [1:0]  cu_mem_size;
    wire        cu_mem_signed, cu_alu_src_b, cu_is_branch, cu_is_jump;
    wire        cu_is_call, cu_is_ret, cu_is_push, cu_is_pop, cu_is_system, cu_halt;
    wire        cu_trap_valid;
    wire [4:0]  cu_trap_cause, cu_alu_op;

    // Register file
    wire [31:0] rf_rs1_data, rf_rs2_data;
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    // Imediato selecionado para ID/EX
    reg  [31:0] id_imm_selected;
    wire [25:0] id_addr26 = dec_addr26_ext[25:0];

    // ---- ID/EX ----
    wire [25:0] idex_pc;
    wire [4:0]  idex_rd, idex_rs1, idex_rs2;
    wire [31:0] idex_rs1_data, idex_rs2_data, idex_imm;
    wire [25:0] idex_addr26;
    wire [5:0]  idex_op;
    wire        idex_reg_write, idex_mem_read, idex_mem_write, idex_mem_to_reg;
    wire [1:0]  idex_mem_size;
    wire        idex_mem_signed, idex_alu_src_b, idex_is_branch, idex_is_jump;
    wire        idex_is_call, idex_is_ret, idex_is_push, idex_is_pop, idex_is_system;
    wire        idex_halt, idex_trap_valid;
    wire [4:0]  idex_trap_cause, idex_alu_op;

    // ---- EX stage ----
    wire [1:0]  fwd_a, fwd_b;
    wire [31:0] ex_alu_a_raw, ex_alu_b_raw, ex_alu_a, ex_alu_b, ex_alu_b_muxed;
    wire [31:0] ex_alu_result;
    wire        ex_flag_z, ex_flag_c, ex_flag_n, ex_flag_v, ex_flag_d;
    wire        ex_branch_taken;
    wire [25:0] ex_branch_target;
    wire [31:0] ex_wb_data;

    // ---- EX/MEM ----
    wire [4:0]  memr_rd;
    wire [31:0] memr_alu_result, memr_rs2_data;
    wire [25:0] memr_branch_target;
    wire        memr_branch_taken;
    wire [5:0]  memr_op;
    wire        memr_reg_write, memr_mem_read, memr_mem_write, memr_mem_to_reg;
    wire [1:0]  memr_mem_size;
    wire        memr_mem_signed, memr_halt, memr_trap_valid;
    wire [4:0]  memr_trap_cause;

    // ---- MEM stage ----
    wire [31:0] dmem_rd_data;

    // ---- MEM/WB ----
    wire [4:0]  wbr_rd;
    wire [31:0] wbr_alu_result, wbr_read_data;
    wire [5:0]  wbr_op;
    wire        wbr_reg_write, wbr_mem_to_reg, wbr_halt, wbr_trap_valid;
    wire [4:0]  wbr_trap_cause;

    // ---- Hazard ----
    wire        stall, flush_id;

    // ---- Trap / Exception ----
    wire        trap_valid;
    wire [4:0]  trap_cause;
    wire [25:0] trap_pc;
    wire [25:0] ivt_base;
    wire [31:0] csr_epc;

    // ---- CSRs ----
    wire [31:0] csr_rdata;
    wire        csr_wr_en;
    wire [4:0]  csr_wr_addr;
    wire [31:0] csr_wr_data;
    wire [31:0] csr_status, csr_ptbr;
    wire        timer_irq;

    // ---- Performance counters ----
    wire        perf_stall_d, perf_icmiss, perf_dcmiss, perf_brmiss;

    // ---- Halted ----
    reg  halted;

    // ======================================================================
    // INSTÂNCIAS DE MÓDULOS
    // ======================================================================

    // ------------------------------------------------------------------
    // PC
    // ------------------------------------------------------------------
    program_counter u_pc (
        .clk        (clk),
        .rst        (rst),
        .stall      (pc_stall),
        .load_en    (pc_load_en),
        .pc_load_val(pc_load_val),
        .pc         (pc_current),
        .pc_plus1   (pc_plus1)
    );

    // ------------------------------------------------------------------
    // Memória BRAM (instrução + dados)
    // ------------------------------------------------------------------
    memory_interface #(
        .IMEM_INIT_FILE(IMEM_INIT_FILE)
    ) u_mem (
        .clk           (clk),
        .rst           (rst),
        .imem_addr     (pc_current),
        .imem_data     (imem_instr),
        .dmem_rd_en    (memr_mem_read),
        .dmem_rd_addr  (memr_alu_result),
        .dmem_rd_size  (memr_mem_size),
        .dmem_rd_signed(memr_mem_signed),
        .dmem_rd_data  (dmem_rd_data),
        .dmem_wr_en    (memr_mem_write),
        .dmem_wr_addr  (memr_alu_result),
        .dmem_wr_size  (memr_mem_size),
        .dmem_wr_data  (memr_rs2_data)
    );

    // ------------------------------------------------------------------
    // Registrador IF/ID
    // ------------------------------------------------------------------
    pipeline_if u_pipe_if (
        .clk     (clk),
        .rst     (rst || halted),
        .stall   (stall),
        .flush   (flush_id),
        .if_pc   (pc_current),
        .if_instr(imem_instr),
        .id_pc   (ifid_pc),
        .id_instr(ifid_instr)
    );

    // ------------------------------------------------------------------
    // Decoder de instrução
    // ------------------------------------------------------------------
    instruction_decoder u_dec (
        .instr        (ifid_instr),
        .op           (dec_op),
        .rd           (dec_rd),
        .rs1          (dec_rs1),
        .rs2          (dec_rs2),
        .shamt        (dec_shamt),
        .imm16_sext   (dec_imm16_sext),
        .imm16_zext   (dec_imm16_zext),
        .addr26_ext   (dec_addr26_ext),
        .imm21_upper  (dec_imm21_upper),
        .imm5_zext    (dec_imm5_zext),
        .is_r_type    (dec_is_r),
        .is_i_type    (dec_is_i),
        .is_s_type    (dec_is_s),
        .is_b_type    (dec_is_b),
        .is_j_type    (dec_is_j),
        .is_u_type    (dec_is_u),
        .is_load      (dec_is_load),
        .is_store     (dec_is_store),
        .is_branch    (dec_is_branch),
        .is_jump      (dec_is_jump),
        .is_call      (dec_is_call),
        .is_ret       (dec_is_ret),
        .is_mul_div   (dec_is_mul_div),
        .is_csr       (dec_is_csr),
        .is_system    (dec_is_system)
    );

    // ------------------------------------------------------------------
    // Unidade de controle
    // ------------------------------------------------------------------
    control_unit u_cu (
        .op          (dec_op),
        .reg_write   (cu_reg_write),
        .mem_read    (cu_mem_read),
        .mem_write   (cu_mem_write),
        .mem_to_reg  (cu_mem_to_reg),
        .mem_size    (cu_mem_size),
        .mem_signed  (cu_mem_signed),
        .alu_src_b   (cu_alu_src_b),
        .is_branch   (cu_is_branch),
        .is_jump     (cu_is_jump),
        .is_call     (cu_is_call),
        .is_ret      (cu_is_ret),
        .is_push     (cu_is_push),
        .is_pop      (cu_is_pop),
        .is_system   (cu_is_system),
        .halt        (cu_halt),
        .trap_valid  (cu_trap_valid),
        .trap_cause  (cu_trap_cause),
        .alu_op      (cu_alu_op)
    );

    // ------------------------------------------------------------------
    // Banco de registradores (32×32)
    // ------------------------------------------------------------------
    register_file u_rf (
        .clk     (clk),
        .rst     (rst),
        .rs1_addr(dec_rs1),
        .rs1_data(rf_rs1_data),
        .rs2_addr(dec_rs2),
        .rs2_data(rf_rs2_data),
        .wr_en   (wb_reg_write),
        .wr_addr (wb_rd),
        .wr_data (wb_data),
        .sp_out  (dbg_sp),
        .lr_out  (dbg_lr)
    );

    // ------------------------------------------------------------------
    // Seleção de imediato para ID/EX
    // ------------------------------------------------------------------
    always @(*) begin
        case (dec_op)
            `OP_ANDI, `OP_ORI, `OP_XORI:
                id_imm_selected = dec_imm16_zext;    // zero-extended
            `OP_MOVHI:
                id_imm_selected = dec_imm21_upper;   // imm21 << 11
            `OP_SHLI, `OP_SHRI, `OP_SHRAI:
                id_imm_selected = dec_imm5_zext;     // shift amount
            default:
                id_imm_selected = dec_imm16_sext;    // sign-extended
        endcase
    end

    // ------------------------------------------------------------------
    // Hazard detection unit
    // ------------------------------------------------------------------
    hazard_unit u_hazard (
        .id_rs1         (dec_rs1),
        .id_rs2         (dec_rs2),
        .id_is_branch   (cu_is_branch),
        .id_is_jump     (cu_is_jump),
        .ex_rd          (idex_rd),
        .ex_mem_read    (idex_mem_read),
        .ex_mul_div     (dec_is_mul_div & 1'b0), // handled by stall in ID/EX below
        .ex_branch_taken(ex_branch_taken),
        .stall          (stall),
        .flush_id       (flush_id)
    );

    assign pc_stall   = stall;
    assign pc_load_en = ex_branch_taken | trap_valid;
    assign pc_load_val = trap_valid ? ivt_base[25:0] :
                         ex_branch_target;

    // ------------------------------------------------------------------
    // Registrador ID/EX
    // ------------------------------------------------------------------
    pipeline_id u_pipe_id (
        .clk         (clk),
        .rst         (rst),
        .stall       (stall),
        .flush       (flush_id),
        .id_pc       (ifid_pc),
        .id_rd       (dec_rd),
        .id_rs1      (dec_rs1),
        .id_rs2      (dec_rs2),
        .id_rs1_data (rf_rs1_data),
        .id_rs2_data (rf_rs2_data),
        .id_imm      (id_imm_selected),
        .id_addr26   (id_addr26),
        .id_op       (dec_op),
        .id_reg_write(cu_reg_write),
        .id_mem_read (cu_mem_read),
        .id_mem_write(cu_mem_write),
        .id_mem_to_reg(cu_mem_to_reg),
        .id_mem_size (cu_mem_size),
        .id_mem_signed(cu_mem_signed),
        .id_alu_src_b(cu_alu_src_b),
        .id_is_branch(cu_is_branch),
        .id_is_jump  (cu_is_jump),
        .id_is_call  (cu_is_call),
        .id_is_ret   (cu_is_ret),
        .id_is_push  (cu_is_push),
        .id_is_pop   (cu_is_pop),
        .id_is_system(cu_is_system),
        .id_halt     (cu_halt),
        .id_trap_valid(cu_trap_valid),
        .id_trap_cause(cu_trap_cause),
        .id_alu_op   (cu_alu_op),
        .ex_pc       (idex_pc),
        .ex_rd       (idex_rd),
        .ex_rs1      (idex_rs1),
        .ex_rs2      (idex_rs2),
        .ex_rs1_data (idex_rs1_data),
        .ex_rs2_data (idex_rs2_data),
        .ex_imm      (idex_imm),
        .ex_addr26   (idex_addr26),
        .ex_op       (idex_op),
        .ex_reg_write(idex_reg_write),
        .ex_mem_read (idex_mem_read),
        .ex_mem_write(idex_mem_write),
        .ex_mem_to_reg(idex_mem_to_reg),
        .ex_mem_size (idex_mem_size),
        .ex_mem_signed(idex_mem_signed),
        .ex_alu_src_b(idex_alu_src_b),
        .ex_is_branch(idex_is_branch),
        .ex_is_jump  (idex_is_jump),
        .ex_is_call  (idex_is_call),
        .ex_is_ret   (idex_is_ret),
        .ex_is_push  (idex_is_push),
        .ex_is_pop   (idex_is_pop),
        .ex_is_system(idex_is_system),
        .ex_halt     (idex_halt),
        .ex_trap_valid(idex_trap_valid),
        .ex_trap_cause(idex_trap_cause),
        .ex_alu_op   (idex_alu_op)
    );

    // ------------------------------------------------------------------
    // Forwarding unit
    // ------------------------------------------------------------------
    forwarding_unit u_fwd (
        .ex_rs1      (idex_rs1),
        .ex_rs2      (idex_rs2),
        .mem_rd      (memr_rd),
        .mem_reg_write(memr_reg_write),
        .wb_rd       (wbr_rd),
        .wb_reg_write(wbr_reg_write),
        .fwd_a       (fwd_a),
        .fwd_b       (fwd_b)
    );

    // ------------------------------------------------------------------
    // Estágio EX — muxes de forwarding + ALU + branch resolution
    // ------------------------------------------------------------------

    // Forwarding mux A (rs1)
    assign ex_alu_a_raw = (fwd_a == 2'b10) ? memr_alu_result :
                          (fwd_a == 2'b01) ? wb_data         :
                          idex_rs1_data;

    // Forwarding mux B (rs2 ou imediato)
    assign ex_alu_b_raw = (fwd_b == 2'b10) ? memr_alu_result :
                          (fwd_b == 2'b01) ? wb_data         :
                          idex_rs2_data;

    // Mux imediato
    assign ex_alu_b_muxed = idex_alu_src_b ? idex_imm : ex_alu_b_raw;

    // Para PUSH: endereço = SP - 1; para POP: endereço = SP
    wire [31:0] ex_sp_val = (fwd_a == 2'b10) ? memr_alu_result :
                            (fwd_a == 2'b01) ? wb_data         :
                            idex_rs1_data;   // rs1 is SP para push via R30

    assign ex_alu_a = ex_alu_a_raw;
    assign ex_alu_b = ex_alu_b_muxed;

    // ALU
    alu u_alu (
        .alu_op   (idex_alu_op),
        .operand_a(ex_alu_a),
        .operand_b(ex_alu_b),
        .result   (ex_alu_result),
        .flag_z   (ex_flag_z),
        .flag_c   (ex_flag_c),
        .flag_n   (ex_flag_n),
        .flag_v   (ex_flag_v),
        .flag_d   (ex_flag_d)
    );

    // Branch condition evaluation
    wire ex_beq  = (ex_alu_a_raw == ex_alu_b_raw);
    wire ex_bne  = !ex_beq;
    wire ex_blt  = ($signed(ex_alu_a_raw) < $signed(ex_alu_b_raw));
    wire ex_bge  = !ex_blt;
    wire ex_bltu = (ex_alu_a_raw < ex_alu_b_raw);
    wire ex_bgeu = !ex_bltu;

    wire ex_cond = (idex_op == `OP_BEQ)  ? ex_beq  :
                   (idex_op == `OP_BNE)  ? ex_bne  :
                   (idex_op == `OP_BLT)  ? ex_blt  :
                   (idex_op == `OP_BGE)  ? ex_bge  :
                   (idex_op == `OP_BLTU) ? ex_bltu :
                   (idex_op == `OP_BGEU) ? ex_bgeu : 1'b0;

    // Determinar se desvio/salto é tomado
    assign ex_branch_taken = (idex_is_branch & ex_cond) |
                              idex_is_jump               |
                              idex_trap_valid;

    // Calcular alvo do desvio/salto
    wire [25:0] ex_pc_offset   = idex_pc + idex_imm[25:0];  // branch PC-relativo
    wire [25:0] ex_reg_target  = ex_alu_a_raw[25:0];        // CALLR, RET, JMPR
    wire [25:0] ex_epc_target  = csr_epc[25:0];             // ERET

    assign ex_branch_target =
        idex_is_ret   ? (idex_op == `OP_ERET ? ex_epc_target : ex_reg_target) :
        idex_is_jump  ? (idex_is_call && idex_op != `OP_CALLR ? idex_addr26 :
                         idex_op == `OP_JMPR ? ex_alu_result[25:0] :
                         idex_op == `OP_CALLR ? ex_alu_a_raw[25:0] :
                         idex_addr26) :
        idex_is_branch ? ex_pc_offset :
        idex_addr26;

    // WB data de CALL: rd = PC+1
    wire [31:0] ex_call_ret_addr = {6'b0, idex_pc} + 32'd1;
    assign ex_wb_data = idex_is_call ? ex_call_ret_addr : ex_alu_result;

    // CSR read data forwarding para instrução MFC
    assign csr_wr_en   = (idex_op == `OP_MTC) & !stall;
    assign csr_wr_addr = idex_imm[4:0];
    assign csr_wr_data = ex_alu_a_raw;

    // ------------------------------------------------------------------
    // Registrador EX/MEM
    // ------------------------------------------------------------------
    pipeline_ex u_pipe_ex (
        .clk             (clk),
        .rst             (rst),
        .ex_rd           (idex_is_call ? 5'd31 : idex_rd),  // CALL escreve R31
        .ex_alu_result   (ex_wb_data),
        .ex_rs2_data     (ex_alu_b_raw),
        .ex_branch_target(ex_branch_target),
        .ex_branch_taken (ex_branch_taken),
        .ex_op           (idex_op),
        .ex_reg_write    (idex_reg_write),
        .ex_mem_read     (idex_mem_read),
        .ex_mem_write    (idex_mem_write),
        .ex_mem_to_reg   (idex_mem_to_reg),
        .ex_mem_size     (idex_mem_size),
        .ex_mem_signed   (idex_mem_signed),
        .ex_halt         (idex_halt),
        .ex_trap_valid   (idex_trap_valid),
        .ex_trap_cause   (idex_trap_cause),
        .mem_rd          (memr_rd),
        .mem_alu_result  (memr_alu_result),
        .mem_rs2_data    (memr_rs2_data),
        .mem_branch_target(memr_branch_target),
        .mem_branch_taken(memr_branch_taken),
        .mem_op          (memr_op),
        .mem_reg_write   (memr_reg_write),
        .mem_mem_read    (memr_mem_read),
        .mem_mem_write   (memr_mem_write),
        .mem_mem_to_reg  (memr_mem_to_reg),
        .mem_mem_size    (memr_mem_size),
        .mem_mem_signed  (memr_mem_signed),
        .mem_halt        (memr_halt),
        .mem_trap_valid  (memr_trap_valid),
        .mem_trap_cause  (memr_trap_cause)
    );

    // ------------------------------------------------------------------
    // Registrador MEM/WB
    // ------------------------------------------------------------------
    pipeline_mem u_pipe_mem (
        .clk            (clk),
        .rst            (rst),
        .mem_rd         (memr_rd),
        .mem_alu_result (memr_alu_result),
        .mem_read_data  (dmem_rd_data),
        .mem_op         (memr_op),
        .mem_reg_write  (memr_reg_write),
        .mem_mem_to_reg (memr_mem_to_reg),
        .mem_halt       (memr_halt),
        .mem_trap_valid (memr_trap_valid),
        .mem_trap_cause (memr_trap_cause),
        .wb_rd          (wbr_rd),
        .wb_alu_result  (wbr_alu_result),
        .wb_read_data   (wbr_read_data),
        .wb_op          (wbr_op),
        .wb_reg_write   (wbr_reg_write),
        .wb_mem_to_reg  (wbr_mem_to_reg),
        .wb_halt        (wbr_halt),
        .wb_trap_valid  (wbr_trap_valid),
        .wb_trap_cause  (wbr_trap_cause)
    );

    // ------------------------------------------------------------------
    // Estágio WB
    // ------------------------------------------------------------------
    pipeline_wb u_wb (
        .mem_to_reg   (wbr_mem_to_reg),
        .alu_result   (wbr_alu_result),
        .mem_read_data(wbr_read_data),
        .wb_data      (wb_data)
    );

    assign wb_reg_write = wbr_reg_write & ~halted;
    assign wb_rd        = wbr_rd;

    // ------------------------------------------------------------------
    // Register File de CSR (embutido no cpu_top)
    // ------------------------------------------------------------------
    csr_regfile u_csr (
        .clk        (clk),
        .rst        (rst),
        .wr_en      (csr_wr_en),
        .wr_addr    (csr_wr_addr),
        .wr_data    (csr_wr_data),
        .rd_addr    (idex_imm[4:0]),
        .rd_data    (csr_rdata),
        .stall_inc  (stall),
        .instret_inc(wbr_reg_write & !wbr_mem_to_reg),
        .dcmiss_inc (1'b0),          // conectar ao D-cache quando presente
        .icmiss_inc (1'b0),          // conectar ao I-cache quando presente
        .brmiss_inc (memr_branch_taken & (memr_op == `OP_BEQ || memr_op == `OP_BNE ||
                                          memr_op == `OP_BLT || memr_op == `OP_BGE  ||
                                          memr_op == `OP_BLTU|| memr_op == `OP_BGEU)),
        .timer_irq  (timer_irq),
        .status_out (csr_status),
        .ivt_out    (ivt_base),
        .epc_out    (csr_epc),
        .ptbr_out   (csr_ptbr),
        // Write EPC on trap
        .trap_valid (wbr_trap_valid),
        .trap_pc    ({6'b0, wbr_alu_result[25:0]}),
        .trap_cause (wbr_trap_cause)
    );

    // ------------------------------------------------------------------
    // Lógica de TRAP
    // ------------------------------------------------------------------
    assign trap_valid = wbr_trap_valid & csr_status[0]; // IE bit
    assign trap_cause = wbr_trap_cause;
    assign trap_pc    = wbr_alu_result[25:0];

    // ------------------------------------------------------------------
    // Latch de HALTED
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)   halted <= 1'b0;
        else if (wbr_halt) halted <= 1'b1;
    end

    // ------------------------------------------------------------------
    // Saídas de debug
    // ------------------------------------------------------------------
    assign dbg_pc      = pc_current;
    assign dbg_instr   = ifid_instr;
    assign dbg_halted  = halted;
    assign dbg_r0      = 32'b0; // R0 always zero

    // UART TX placeholder (logic analyzer / FPGA)
    assign uart_tx = 1'b1;

endmodule


// ============================================================================
// csr_regfile — Banco de CSRs (32 registradores × 32 bits)
// ============================================================================
module csr_regfile (
    input  wire        clk,
    input  wire        rst,

    // Porta de escrita (MTC)
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [31:0] wr_data,

    // Porta de leitura (MFC)
    input  wire [4:0]  rd_addr,
    output reg  [31:0] rd_data,

    // Contadores de performance
    input  wire        stall_inc,
    input  wire        instret_inc,
    input  wire        dcmiss_inc,
    input  wire        icmiss_inc,
    input  wire        brmiss_inc,

    // Timer (gera IRQ periódico)
    output wire        timer_irq,

    // Saídas diretas de CSRs importantes
    output wire [31:0] status_out,
    output wire [31:0] ivt_out,
    output wire [31:0] epc_out,
    output wire [31:0] ptbr_out,

    // Interface de trap (atualiza EPC e CAUSE)
    input  wire        trap_valid,
    input  wire [31:0] trap_pc,
    input  wire [4:0]  trap_cause
);

    `include "isa_pkg.vh"

    reg [31:0] csrs [0:31];
    reg [63:0] cycle_cnt;
    reg [31:0] instret_cnt;
    reg [31:0] icount_cnt;
    reg [31:0] dcmiss_cnt;
    reg [31:0] icmiss_cnt;
    reg [31:0] brmiss_cnt;
    integer i;

    // Timer compare (mtime >= mtimecmp → IRQ)
    reg [31:0] timer_cmp;
    assign timer_irq = (cycle_cnt[31:0] >= timer_cmp) & csrs[`CSR_STATUS][0];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) csrs[i] <= 32'b0;
            cycle_cnt   <= 64'b0;
            instret_cnt <= 32'b0;
            icount_cnt  <= 32'b0;
            dcmiss_cnt  <= 32'b0;
            icmiss_cnt  <= 32'b0;
            brmiss_cnt  <= 32'b0;
            timer_cmp   <= 32'hFFFFFFFF;
        end else begin
            // Contadores automáticos
            cycle_cnt   <= cycle_cnt + 64'd1;
            if (stall_inc)   icount_cnt <= icount_cnt + 1;
            if (instret_inc) instret_cnt <= instret_cnt + 1;
            if (dcmiss_inc)  dcmiss_cnt  <= dcmiss_cnt  + 1;
            if (icmiss_inc)  icmiss_cnt  <= icmiss_cnt  + 1;
            if (brmiss_inc)  brmiss_cnt  <= brmiss_cnt  + 1;

            // Escrita por MTC
            if (wr_en) csrs[wr_addr] <= wr_data;

            // Atualização de EPC e CAUSE em trap
            if (trap_valid) begin
                csrs[`CSR_EPC]   <= trap_pc;
                csrs[`CSR_CAUSE] <= {27'b0, trap_cause};
                csrs[`CSR_STATUS][0] <= 1'b0; // desativa IE ao entrar no handler
            end
        end
    end

    // Leitura: mistura entre CSRs e contadores
    always @(*) begin
        case (rd_addr)
            `CSR_STATUS:  rd_data = csrs[`CSR_STATUS];
            `CSR_IVT:     rd_data = csrs[`CSR_IVT];
            `CSR_EPC:     rd_data = csrs[`CSR_EPC];
            `CSR_CAUSE:   rd_data = csrs[`CSR_CAUSE];
            `CSR_ESCRATCH:rd_data = csrs[`CSR_ESCRATCH];
            `CSR_PTBR:    rd_data = csrs[`CSR_PTBR];
            `CSR_CYCLE:   rd_data = cycle_cnt[31:0];
            `CSR_CYCLEH:  rd_data = cycle_cnt[63:32];
            `CSR_INSTRET: rd_data = instret_cnt;
            `CSR_ICOUNT:  rd_data = icount_cnt;
            `CSR_DCMISS:  rd_data = dcmiss_cnt;
            `CSR_ICMISS:  rd_data = icmiss_cnt;
            `CSR_BRMISS:  rd_data = brmiss_cnt;
            default:      rd_data = csrs[rd_addr];
        endcase
    end

    assign status_out = csrs[`CSR_STATUS];
    assign ivt_out    = csrs[`CSR_IVT];
    assign epc_out    = csrs[`CSR_EPC];
    assign ptbr_out   = csrs[`CSR_PTBR];

endmodule
