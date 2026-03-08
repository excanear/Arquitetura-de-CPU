// ============================================================================
// register_file.v  —  Banco de Registradores — EduRISC-32
//
// 16 registradores de 32 bits (R0-R15).
// R15 é o link register (LR): carregado por CALL, usado por RET.
//
// Leitura:  combinacional (dois leitores independentes: rs1, rs2)
// Escrita:  síncrona na borda de subida do clock
//
// Atenção: diferente de RISC-V, R0 NÃO é hardwired a zero.
//          Qualquer registrador pode ser lido e escrito.
// ============================================================================
`timescale 1ns/1ps

module register_file (
    input  wire        clk,
    input  wire        rst,        // reset síncrono (zera todos os regs)

    // Porta de leitura A (rs1)
    input  wire [3:0]  rs1,
    output wire [31:0] rs1_data,

    // Porta de leitura B (rs2)
    input  wire [3:0]  rs2,
    output wire [31:0] rs2_data,

    // Porta de escrita
    input  wire        we,         // write enable
    input  wire [3:0]  rd,
    input  wire [31:0] wd          // write data
);

    reg [31:0] regs [0:15];
    integer i;

    // ------------------------------------------------------------------
    // Escrita síncrona
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1)
                regs[i] <= 32'h0;
        end else if (we) begin
            regs[rd] <= wd;
        end
    end

    // ------------------------------------------------------------------
    // Leitura combinacional
    // ------------------------------------------------------------------
    assign rs1_data = regs[rs1];
    assign rs2_data = regs[rs2];

endmodule
