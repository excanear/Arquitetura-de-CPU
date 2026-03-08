/*
 * branch_predictor.v — 2-bit Saturating Counter Branch Predictor
 *
 * Implements a bimodal predictor (2-bit saturating counters) with a
 * Branch Target Buffer (BTB) for predicting taken branches in the
 * EduRISC-32v2 5-stage pipeline.
 *
 * Prediction accuracy: ~85-92% for typical loop-heavy workloads.
 *
 * 2-bit counter states:
 *   2'b11 — Strongly Taken     ┐ → predict TAKEN
 *   2'b10 — Weakly   Taken     ┘
 *   2'b01 — Weakly   Not-Taken ┐ → predict NOT TAKEN
 *   2'b00 — Strongly Not-Taken ┘
 *
 * Pipeline integration:
 *   IF stage: pred_pc → {pred_taken, pred_target, pred_valid}
 *   EX stage: upd_*   → update counter + BTB entry after branch resolves
 *
 * On misprediction (pipeline_if detects pred_taken ≠ actual_taken):
 *   The pipeline flushes IF/ID stages (flush signal from branch_unit.v)
 *   and the BTB counter is updated here to improve future predictions.
 *
 * Parameters:
 *   BTB_ENTRIES : number of BTB entries (must be power of 2)
 *   PC_WIDTH    : width of the program counter in bits
 *   TAG_WIDTH   : width of the PC tag field (for aliasing detection)
 */

`timescale 1ns/1ps

module branch_predictor #(
    parameter BTB_ENTRIES = 64,
    parameter PC_WIDTH    = 26,
    parameter TAG_WIDTH   = 14
) (
    input  wire                 clk,
    input  wire                 rst,

    /* ── Prediction port: queried every cycle by the IF stage ─── */
    input  wire [PC_WIDTH-1:0]  pred_pc,        /* PC of fetched instruction  */
    output wire                 pred_taken,      /* 1 = predict branch taken   */
    output wire [PC_WIDTH-1:0]  pred_target,     /* Predicted branch target    */
    output wire                 pred_valid,      /* 1 = prediction is valid    */

    /* ── Update port: driven by EX stage after branch resolves ── */
    input  wire                 upd_en,          /* 1 = update this cycle      */
    input  wire [PC_WIDTH-1:0]  upd_pc,          /* Address of branch instr    */
    input  wire [PC_WIDTH-1:0]  upd_target,      /* Resolved branch target     */
    input  wire                 upd_taken,        /* 1 = branch actually taken  */
    input  wire                 upd_is_branch,    /* 1 = this is a branch instr */

    /* ── Flush request: 1 when misprediction is detected ─────── */
    output wire                 mispredict       /* 1 = flush pipeline         */
);

    /* ─── Derived widths ────────────────────────────────────────── */
    localparam IDX_BITS = $clog2(BTB_ENTRIES);  /* Index into BTB array       */

    /* ─── BTB storage arrays ─────────────────────────────────────
     * Each BTB entry contains:
     *   counter [1:0]           — 2-bit saturating predictor
     *   tag     [TAG_WIDTH-1:0] — upper PC bits for tag matching
     *   target  [PC_WIDTH-1:0]  — predicted branch target address
     *   valid                   — entry has been filled at least once
     * ─────────────────────────────────────────────────────────── */
    reg [1:0]           counter [0:BTB_ENTRIES-1];
    reg [TAG_WIDTH-1:0] tag     [0:BTB_ENTRIES-1];
    reg [PC_WIDTH-1:0]  target  [0:BTB_ENTRIES-1];
    reg                 valid   [0:BTB_ENTRIES-1];

    /* ─── Misprediction tracking ──────────────────────────────── */
    reg  r_mispredict;

    /* ─── Prediction (combinational) ─────────────────────────────
     *
     * Index selection: bits [IDX_BITS+1 : 2]  (skip 2 LSBs; word-aligned PC)
     * Tag   selection: bits [IDX_BITS+TAG_WIDTH+1 : IDX_BITS+2]
     * ─────────────────────────────────────────────────────────── */
    wire [IDX_BITS-1:0]  pred_idx = pred_pc[IDX_BITS+1:2];
    wire [TAG_WIDTH-1:0] pred_tag = pred_pc[IDX_BITS+TAG_WIDTH+1:IDX_BITS+2];

    wire hit = valid[pred_idx] && (tag[pred_idx] == pred_tag);

    assign pred_valid  = hit;
    assign pred_taken  = hit && counter[pred_idx][1];   /* MSB = predict taken */
    assign pred_target = hit ? target[pred_idx] : {PC_WIDTH{1'b0}};

    /* ─── Misprediction detection (combinational) ─────────────── */
    wire [IDX_BITS-1:0]  upd_idx = upd_pc[IDX_BITS+1:2];
    wire [TAG_WIDTH-1:0] upd_tag = upd_pc[IDX_BITS+TAG_WIDTH+1:IDX_BITS+2];

    /* Misprediction: prediction was made AND the actual outcome differs */
    wire prediction_was_taken = valid[upd_idx] && (tag[upd_idx] == upd_tag)
                                && counter[upd_idx][1];

    assign mispredict = upd_en && upd_is_branch &&
                        valid[upd_idx] && (tag[upd_idx] == upd_tag) &&
                        (prediction_was_taken != upd_taken);

    /* ─── Sequential update logic ─────────────────────────────── */
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                counter[i] <= 2'b01;    /* Weakly not-taken at reset         */
                tag[i]     <= {TAG_WIDTH{1'b0}};
                target[i]  <= {PC_WIDTH{1'b0}};
                valid[i]   <= 1'b0;
            end
            r_mispredict <= 1'b0;
        end else if (upd_en && upd_is_branch) begin
            /* ── Install / refresh BTB entry ─────────────────── */
            tag[upd_idx]    <= upd_tag;
            target[upd_idx] <= upd_target;
            valid[upd_idx]  <= 1'b1;

            /* ── Update 2-bit saturating counter ─────────────── */
            if (upd_taken) begin
                /* Saturate upward toward Strongly Taken (2'b11) */
                if (counter[upd_idx] != 2'b11)
                    counter[upd_idx] <= counter[upd_idx] + 2'b01;
            end else begin
                /* Saturate downward toward Strongly Not-Taken (2'b00) */
                if (counter[upd_idx] != 2'b00)
                    counter[upd_idx] <= counter[upd_idx] - 2'b01;
            end
        end
    end

endmodule
