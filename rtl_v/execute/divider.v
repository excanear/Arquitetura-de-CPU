// ============================================================================
// divider.v  —  Divisor iterativo de 32 bits (algoritmo de restauração)
//
// Latência: 32 ciclos de clock (1 bit por ciclo)
// Interface handshake: start → (32 ciclos) → done
//
// Modos:
//   signed_mode=0 → divisão sem sinal (DIVU)
//   signed_mode=1 → divisão com sinal (DIV, REM)
//
// Flags:
//   div_by_zero=1 quando divisor=0
//   Resultado para div/0: quotient=0xFFFFFFFF, remainder=dividend
// ============================================================================
`timescale 1ns/1ps

module divider (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        signed_mode,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder,
    output reg         done,
    output reg         div_by_zero,
    output wire        busy
);

    // -------------------------------------------------------------------------
    // Estados
    // -------------------------------------------------------------------------
    localparam IDLE  = 2'd0;
    localparam CALC  = 2'd1;
    localparam CORR  = 2'd2;   // correção de sinal
    localparam DONE  = 2'd3;

    reg [1:0]  state;
    reg [5:0]  count;           // 0..31

    // Operandos internos (sempre unsigned durante o cálculo)
    reg [31:0] dvd;             // dividendo (magnitude)
    reg [31:0] dvs;             // divisor   (magnitude)
    reg        neg_q;           // sinal do quociente
    reg        neg_r;           // sinal do resto

    // Registrador parcial de 64 bits: {partial[31:0], q[31:0]}
    reg [31:0] partial;
    reg [31:0] q_reg;

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            done        <= 0;
            div_by_zero <= 0;
            quotient    <= 0;
            remainder   <= 0;
        end else begin
            done <= 0;

            case (state)
                // -----------------------------------------------------------------
                IDLE: begin
                    if (start) begin
                        if (divisor == 32'd0) begin
                            quotient    <= 32'hFFFF_FFFF;
                            remainder   <= dividend;
                            div_by_zero <= 1;
                            done        <= 1;
                            // permanece em IDLE (resultado imediato)
                        end else begin
                            div_by_zero <= 0;

                            // Determinar sinais
                            if (signed_mode) begin
                                neg_q <= dividend[31] ^ divisor[31];
                                neg_r <= dividend[31];
                                dvd   <= dividend[31] ? (~dividend + 1) : dividend;
                                dvs   <= divisor[31]  ? (~divisor  + 1) : divisor;
                            end else begin
                                neg_q <= 0;
                                neg_r <= 0;
                                dvd   <= dividend;
                                dvs   <= divisor;
                            end

                            partial <= 32'd0;
                            q_reg   <= 0;
                            count   <= 31;
                            state   <= CALC;
                        end
                    end
                end

                // -----------------------------------------------------------------
                CALC: begin
                    // Deslocar partial:dvd um bit para a esquerda
                    // Tentar subtrair dvs de partial
                    begin
                        reg [32:0] p_shifted;
                        p_shifted = {partial[30:0], dvd[31]};

                        if (p_shifted >= {1'b0, dvs}) begin
                            partial <= p_shifted[31:0] - dvs;
                            q_reg   <= {q_reg[30:0], 1'b1};
                        end else begin
                            partial <= p_shifted[31:0];
                            q_reg   <= {q_reg[30:0], 1'b0};
                        end

                        dvd <= {dvd[30:0], 1'b0};

                        if (count == 0)
                            state <= CORR;
                        else
                            count <= count - 1;
                    end
                end

                // -----------------------------------------------------------------
                CORR: begin
                    // Aplicar sinal
                    quotient  <= neg_q ? (~q_reg  + 1) : q_reg;
                    remainder <= neg_r ? (~partial + 1) : partial;
                    state     <= DONE;
                end

                // -----------------------------------------------------------------
                DONE: begin
                    done  <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
