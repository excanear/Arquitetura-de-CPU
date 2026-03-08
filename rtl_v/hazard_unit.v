// ============================================================================
// hazard_unit.v  —  Unidade de Detecção de Hazards EduRISC-32v2
//
// Hazards tratados:
//  1. Load-use RAW: instrução de carga seguida imediatamente por instrução
//     que usa o registrador carregado → stall de 1 ciclo.
//
//  2. Branch taken: desvio condicional ou salto → flush de 1 ciclo
//     (a instrução buscada logo após é descartada).
//
//  3. Mul/Div RAW: multiplicação e divisão têm latência de 1 ciclo extra
//     (implementadas como single-cycle na ALU, mas o compilador deve emitir
//      um NOP. A detecção é igual ao load-use para simplificar.)
//
// Saídas:
//  stall     — congela IF e ID (e injeta NOP no ID/EX)
//  flush_id  — descarta IF/ID (insere NOP) no ciclo seguinte a um desvio tomado
// ============================================================================
`timescale 1ns/1ps

module hazard_unit (
    // Instrução ID (sendo decodificada agora)
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire        id_is_branch,
    input  wire        id_is_jump,

    // Instrução EX (pipeline ID/EX)
    input  wire [4:0]  ex_rd,
    input  wire        ex_mem_read,   // load-use detection
    input  wire        ex_mul_div,    // mul/div latency

    // Desvio resultante do estágio EX
    input  wire        ex_branch_taken,

    // Saídas de controle do pipeline
    output wire        stall,
    output wire        flush_id       // flush IF/ID (descarta instrução buscada)
);

    // Load-use: se EX está a ler memória E o rd da EX coincide com rs1 ou rs2 da ID
    wire load_use_hazard = ex_mem_read &&
                           (ex_rd != 5'b0) &&
                           ((ex_rd == id_rs1) || (ex_rd == id_rs2));

    // Mul/Div: mesma lógica de 1 ciclo de stall
    wire mul_div_hazard  = ex_mul_div &&
                           (ex_rd != 5'b0) &&
                           ((ex_rd == id_rs1) || (ex_rd == id_rs2));

    assign stall    = load_use_hazard | mul_div_hazard;
    assign flush_id = ex_branch_taken;  // branch resolvido no EX → flush IF/ID

endmodule
