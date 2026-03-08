// ============================================================================
// program_counter.v  —  Contador de Programa — EduRISC-32
//
// Mantém o PC de 28 bits e gera PC+1 para o pipeline.
// Aceita carga de valor externo (branch/jump) com prioridade sobre incremento.
// ============================================================================
`timescale 1ns/1ps

module program_counter (
    input  wire        clk,
    input  wire        rst,        // reset síncrono → PC = 0
    input  wire        stall,      // congela PC quando asserted
    input  wire        load,       // carrega pc_next quando asserted
    input  wire [27:0] pc_next,    // valor a carregar (branch/jump target)
    output reg  [27:0] pc,         // PC atual
    output wire [27:0] pc_plus1    // PC + 1 (endereço da próxima instrução)
);

    assign pc_plus1 = pc + 28'h1;

    always @(posedge clk) begin
        if (rst)
            pc <= 28'h0;
        else if (!stall) begin
            if (load)
                pc <= pc_next;
            else
                pc <= pc_plus1;
        end
    end

endmodule
