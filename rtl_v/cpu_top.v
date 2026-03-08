// ============================================================================
// cpu_top.v  —  Topo do Pipeline EduRISC-32 (5 estágios)
//
// Pipeline: IF → ID → EX → MEM → WB
//
//  ┌────────────────────────────────────────────────────────────────────┐
//  │  IF         │  ID          │  EX         │  MEM         │  WB    │
//  │  Fetch      │  Decode /    │  Execução   │  Memória de  │  Write │
//  │  PC, IMEM   │  RegFile /   │  ALU /      │  Dados       │  Back  │
//  │             │  Control     │  Branch     │              │        │
//  └─────────────┴──────────────┴─────────────┴──────────────┴────────┘
//
// Hazards resolvidos:
//  • Forwarding EX/MEM→EX e MEM/WB→EX (sem stall para RAW simples)
//  • Load-use stall de 1 ciclo (hazard_unit)
//  • Branch flush de 1 ciclo (desvio resolvido no EX)
//
// Parâmetro:
//  IMEM_INIT_FILE — arquivo .hex a carregar na IMEM
// ============================================================================
`timescale 1ns/1ps
`include "isa_pkg.vh"

module cpu_top #(
    parameter IMEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,

    // Interface de depuração/observabilidade (opcional)
    output wire [27:0] dbg_pc,
    output wire [31:0] dbg_instr,
    output wire        dbg_halted
);

    // ==================================================================
    // Fios internos
    // ==================================================================

    // ---- PC ----
    wire [27:0] pc_current, pc_plus1;
    wire        pc_stall, pc_load;
    wire [27:0] pc_next_val;

    // ---- Hazard / Forwarding ----
    wire        stall, flush;
    wire [1:0]  fwd_a, fwd_b;

    // ---- IF estágio: IF/ID pipe regs ----
    wire [27:0] ifid_pc;
    wire [31:0] ifid_instr;
    wire [31:0] imem_instr;

    // ---- ID estágio: decoder + control ----
    wire [3:0]  dec_opcode, dec_rd, dec_rs1, dec_rs2;
    wire [31:0] dec_imm20, dec_offset20;
    wire [27:0] dec_addr28;
    // controle
    wire        cu_reg_write, cu_mem_read, cu_mem_write, cu_mem_to_reg;
    wire        cu_alu_src, cu_branch, cu_jump, cu_is_call, cu_is_ret, cu_halt;
    wire [3:0]  cu_alu_op;
    // register file
    wire [31:0] rf_rs1_data, rf_rs2_data;
    // write-back para register file
    wire        wb_reg_write;
    wire [3:0]  wb_rd;
    wire [31:0] wb_data;

    // ---- ID/EX pipe regs ----
    wire [27:0] idex_pc;
    wire [3:0]  idex_opcode, idex_rd, idex_rs1, idex_rs2;
    wire [31:0] idex_rs1_data, idex_rs2_data, idex_imm20, idex_offset20;
    wire [27:0] idex_addr28;
    wire        idex_reg_write, idex_mem_read, idex_mem_write, idex_mem_to_reg;
    wire        idex_alu_src, idex_branch, idex_jump, idex_is_call, idex_is_ret, idex_halt;
    wire [3:0]  idex_alu_op;

    // ---- EX estágio ----
    wire [31:0] ex_alu_a, ex_alu_b, ex_alu_b_muxed;
    wire [31:0] ex_alu_result;
    wire        ex_flag_z, ex_flag_c, ex_flag_n, ex_flag_v;
    wire        ex_branch_taken;
    wire [27:0] ex_branch_target;
    wire [31:0] ex_wb_data_call;   // PC+1 para CALL→R15

    // ---- EX/MEM pipe regs ----
    wire [3:0]  exmem_rd;
    wire [31:0] exmem_alu_result, exmem_rs2_data;
    wire [27:0] exmem_branch_target;
    wire        exmem_branch_taken;
    wire        exmem_reg_write, exmem_mem_read, exmem_mem_write, exmem_mem_to_reg, exmem_halt;

    // ---- MEM estágio ----
    wire [31:0] dmem_rdata;

    // ---- MEM/WB pipe regs ----
    wire [3:0]  memwb_rd;
    wire [31:0] memwb_alu_result, memwb_mem_data;
    wire        memwb_halt, memwb_reg_write, memwb_mem_to_reg;

    // halted flag
    reg         halted;

    // ==================================================================
    // Módulos instanciados
    // ==================================================================

    // ------------------------------------------------------------------
    // 0. Memória (IMEM + DMEM)
    // ------------------------------------------------------------------
    memory_interface #(
        .IMEM_INIT_FILE(IMEM_INIT_FILE)
    ) u_mem (
        .clk         (clk),
        .rst         (rst),
        .imem_addr   (pc_current),
        .imem_data   (imem_instr),
        .dmem_addr   (exmem_alu_result[27:0]),
        .dmem_read   (exmem_mem_read),
        .dmem_rdata  (dmem_rdata),
        .dmem_write  (exmem_mem_write),
        .dmem_wdata  (exmem_rs2_data)
    );

    // ------------------------------------------------------------------
    // 1. Program Counter
    // ------------------------------------------------------------------
    // Escolha do próximo PC:
    //  • desvio/jump tomado  → ex_branch_target
    //  • RET                 → R15 (encaminhado via branch_target quando is_ret)
    //  • normal              → pc_plus1
    assign pc_load     = exmem_branch_taken;
    assign pc_next_val = exmem_branch_target;
    assign pc_stall    = stall;

    program_counter u_pc (
        .clk     (clk),
        .rst     (rst),
        .stall   (pc_stall),
        .load    (pc_load),
        .pc_next (pc_next_val),
        .pc      (pc_current),
        .pc_plus1(pc_plus1)
    );

    // ------------------------------------------------------------------
    // 2. Estágio IF: registrador IF/ID
    // ------------------------------------------------------------------
    pipeline_if u_ifid (
        .clk       (clk),
        .rst       (rst),
        .stall     (stall),
        .flush     (flush),
        .pc_in     (pc_current),
        .instr_in  (imem_instr),
        .ifid_pc   (ifid_pc),
        .ifid_instr(ifid_instr)
    );

    // ------------------------------------------------------------------
    // 3. Instruction Decoder (combinacional, opera sobre IF/ID)
    // ------------------------------------------------------------------
    instruction_decoder u_dec (
        .instr     (ifid_instr),
        .opcode    (dec_opcode),
        .rd        (dec_rd),
        .rs1       (dec_rs1),
        .rs2       (dec_rs2),
        .imm20     (dec_imm20),
        .offset20  (dec_offset20),
        .addr28    (dec_addr28),
        // classificação (não usados em cpu_top diretamente)
        .is_r_type (),
        .is_m_type (),
        .is_j_type (),
        .is_load   (),
        .is_store  (),
        .is_jump   (),
        .is_branch (),
        .is_call   (),
        .is_ret    (),
        .is_hlt    ()
    );

    // ------------------------------------------------------------------
    // 4. Control Unit (combinacional, opera sobre opcode do decoder)
    // ------------------------------------------------------------------
    control_unit u_cu (
        .opcode     (dec_opcode),
        .reg_write  (cu_reg_write),
        .mem_read   (cu_mem_read),
        .mem_write  (cu_mem_write),
        .mem_to_reg (cu_mem_to_reg),
        .alu_src    (cu_alu_src),
        .branch     (cu_branch),
        .jump       (cu_jump),
        .is_call    (cu_is_call),
        .is_ret     (cu_is_ret),
        .halt       (cu_halt),
        .alu_op     (cu_alu_op)
    );

    // ------------------------------------------------------------------
    // 5. Register File
    // ------------------------------------------------------------------
    register_file u_rf (
        .clk     (clk),
        .rst     (rst),
        .rs1     (dec_rs1),
        .rs2     (dec_rs2),
        .rs1_data(rf_rs1_data),
        .rs2_data(rf_rs2_data),
        .we      (wb_reg_write),
        .rd      (wb_rd),
        .wd      (wb_data)
    );

    // ------------------------------------------------------------------
    // 6. Hazard Unit
    // ------------------------------------------------------------------
    hazard_unit u_haz (
        .id_rs1       (dec_rs1),
        .id_rs2       (dec_rs2),
        .ex_rd        (idex_rd),
        .ex_mem_read  (idex_mem_read),
        .branch_taken (exmem_branch_taken),
        .stall        (stall),
        .flush        (flush)
    );

    // ------------------------------------------------------------------
    // 7. Forwarding Unit
    // ------------------------------------------------------------------
    forwarding_unit u_fwd (
        .ex_rs1         (idex_rs1),
        .ex_rs2         (idex_rs2),
        .exmem_rd       (exmem_rd),
        .exmem_reg_write(exmem_reg_write),
        .memwb_rd       (memwb_rd),
        .memwb_reg_write(memwb_reg_write),
        .fwd_a          (fwd_a),
        .fwd_b          (fwd_b)
    );

    // ------------------------------------------------------------------
    // 8. Estágio ID: registrador ID/EX
    // ------------------------------------------------------------------
    pipeline_id u_idex (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall),
        .flush          (flush),
        .pc_in          (ifid_pc),
        .opcode_in      (dec_opcode),
        .rd_in          (dec_rd),
        .rs1_in         (dec_rs1),
        .rs2_in         (dec_rs2),
        .rs1_data_in    (rf_rs1_data),
        .rs2_data_in    (rf_rs2_data),
        .imm20_in       (dec_imm20),
        .offset20_in    (dec_offset20),
        .addr28_in      (dec_addr28),
        .reg_write_in   (cu_reg_write),
        .mem_read_in    (cu_mem_read),
        .mem_write_in   (cu_mem_write),
        .mem_to_reg_in  (cu_mem_to_reg),
        .alu_src_in     (cu_alu_src),
        .branch_in      (cu_branch),
        .jump_in        (cu_jump),
        .is_call_in     (cu_is_call),
        .is_ret_in      (cu_is_ret),
        .halt_in        (cu_halt),
        .alu_op_in      (cu_alu_op),
        .idex_pc        (idex_pc),
        .idex_opcode    (idex_opcode),
        .idex_rd        (idex_rd),
        .idex_rs1       (idex_rs1),
        .idex_rs2       (idex_rs2),
        .idex_rs1_data  (idex_rs1_data),
        .idex_rs2_data  (idex_rs2_data),
        .idex_imm20     (idex_imm20),
        .idex_offset20  (idex_offset20),
        .idex_addr28    (idex_addr28),
        .idex_reg_write (idex_reg_write),
        .idex_mem_read  (idex_mem_read),
        .idex_mem_write (idex_mem_write),
        .idex_mem_to_reg(idex_mem_to_reg),
        .idex_alu_src   (idex_alu_src),
        .idex_branch    (idex_branch),
        .idex_jump      (idex_jump),
        .idex_is_call   (idex_is_call),
        .idex_is_ret    (idex_is_ret),
        .idex_halt      (idex_halt),
        .idex_alu_op    (idex_alu_op)
    );

    // ------------------------------------------------------------------
    // 9. Estágio EX: Muxes de Forwarding + ALU + Cálculo de Branch
    // ------------------------------------------------------------------

    // 9a. Mux forwarding para operando A (rs1)
    assign ex_alu_a = (fwd_a == 2'b10) ? exmem_alu_result :
                      (fwd_a == 2'b01) ? wb_data           :
                                         idex_rs1_data;

    // 9b. Mux forwarding para operando B (rs2 ou imediato)
    wire [31:0] ex_fwd_b_raw;
    assign ex_fwd_b_raw = (fwd_b == 2'b10) ? exmem_alu_result :
                          (fwd_b == 2'b01) ? wb_data           :
                                             idex_rs2_data;

    // 9c. Mux ALU src: imediato ou rs2
    assign ex_alu_b_muxed = idex_alu_src ? idex_imm20 : ex_fwd_b_raw;

    // 9d. Para RET, a ALU passa R15 direto como resultado (endereço de retorno)
    //     Para CALL, o resultado escrito em R15 é PC+1
    assign ex_wb_data_call = {{4{1'b0}}, idex_pc} + 32'd1;

    // 9e. ALU
    alu u_alu (
        .alu_op  (idex_alu_op),
        .a       ((idex_is_ret) ? idex_rs1_data : ex_alu_a),
        .b       (ex_alu_b_muxed),
        .result  (ex_alu_result),
        .flag_z  (ex_flag_z),
        .flag_c  (ex_flag_c),
        .flag_n  (ex_flag_n),
        .flag_v  (ex_flag_v)
    );

    // 9f. Avaliação de branch condicional
    wire ex_cond_taken;
    assign ex_cond_taken = (idex_opcode == `OP_JZ)  ?  ex_flag_z :
                           (idex_opcode == `OP_JNZ) ? ~ex_flag_z :
                           1'b0;

    // 9g. Branch/Jump tomado?
    wire ex_jump_taken;
    assign ex_jump_taken   = idex_jump || (idex_branch && ex_cond_taken);
    assign ex_branch_taken = ex_jump_taken;

    // 9h. Cálculo do alvo:
    //   JMP/JZ/JNZ/CALL  — addr28 embutido na instrução
    //   RET              — valor de R15 (rs1_data, que é R15 pela convenção)
    assign ex_branch_target = idex_is_ret ? ex_alu_result[27:0] : idex_addr28;

    // 9i. Para CALL, o resultado a registrar em rd (=R15) é PC+1
    wire [31:0] ex_result_final;
    assign ex_result_final = idex_is_call ? ex_wb_data_call : ex_alu_result;

    // 9j. Para STORE, o dado a escrever na memória é o rs2 com forwarding
    wire [31:0] ex_store_data;
    assign ex_store_data = ex_fwd_b_raw;

    // ------------------------------------------------------------------
    // 10. Registrador EX/MEM
    // ------------------------------------------------------------------
    pipeline_ex u_exmem (
        .clk                (clk),
        .rst                (rst),
        .rd_in              (idex_rd),
        .alu_result_in      (ex_result_final),
        .rs2_data_in        (ex_store_data),
        .branch_target_in   (ex_branch_target),
        .branch_taken_in    (ex_branch_taken),
        .reg_write_in       (idex_reg_write),
        .mem_read_in        (idex_mem_read),
        .mem_write_in       (idex_mem_write),
        .mem_to_reg_in      (idex_mem_to_reg),
        .halt_in            (idex_halt),
        .exmem_rd           (exmem_rd),
        .exmem_alu_result   (exmem_alu_result),
        .exmem_rs2_data     (exmem_rs2_data),
        .exmem_branch_target(exmem_branch_target),
        .exmem_branch_taken (exmem_branch_taken),
        .exmem_reg_write    (exmem_reg_write),
        .exmem_mem_read     (exmem_mem_read),
        .exmem_mem_write    (exmem_mem_write),
        .exmem_mem_to_reg   (exmem_mem_to_reg),
        .exmem_halt         (exmem_halt)
    );

    // ------------------------------------------------------------------
    // 11. Registrador MEM/WB  (acesso à dmem está em memory_interface)
    // ------------------------------------------------------------------
    pipeline_mem u_memwb (
        .clk             (clk),
        .rst             (rst),
        .rd_in           (exmem_rd),
        .alu_result_in   (exmem_alu_result),
        .mem_data_in     (dmem_rdata),
        .halt_in         (exmem_halt),
        .reg_write_in    (exmem_reg_write),
        .mem_to_reg_in   (exmem_mem_to_reg),
        .memwb_rd        (memwb_rd),
        .memwb_alu_result(memwb_alu_result),
        .memwb_mem_data  (memwb_mem_data),
        .memwb_halt      (memwb_halt),
        .memwb_reg_write (memwb_reg_write),
        .memwb_mem_to_reg(memwb_mem_to_reg)
    );

    // ------------------------------------------------------------------
    // 12. Estágio WB: mux final e sinal de volta ao register_file
    // ------------------------------------------------------------------
    pipeline_wb u_wb (
        .alu_result(memwb_alu_result),
        .mem_data  (memwb_mem_data),
        .mem_to_reg(memwb_mem_to_reg),
        .wb_data   (wb_data)
    );

    assign wb_reg_write = memwb_reg_write;
    assign wb_rd        = memwb_rd;

    // ------------------------------------------------------------------
    // 13. Controle de Halt
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            halted <= 1'b0;
        else if (memwb_halt)
            halted <= 1'b1;
    end

    // ==================================================================
    // Saídas de depuração
    // ==================================================================
    assign dbg_pc     = pc_current;
    assign dbg_instr  = ifid_instr;
    assign dbg_halted = halted;

endmodule
