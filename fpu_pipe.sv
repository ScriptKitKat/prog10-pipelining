// FPU Execution Pipeline — 4-stage wrapper for floating-point operations.
//
// Stage 1: Latch inputs, compute FPU result combinationally.
// Stages 2-3: Pipeline registers (for timing).
// Stage 4: Present result to CDB.  Latency = 4 cycles.
//
// Reuses existing combinational fpu_add, fpu_mul, fpu_div modules from fpu.sv.

`include "fpu.sv"

module fpu_pipe (
    input         clk,
    input         reset,
    input         flush,
    input         stall,        // CDB couldn't accept s4 output — freeze pipeline

    // --- Issue inputs (from FPU reservation station) ---
    input         valid_in,
    input  [4:0]  opcode_in,
    input  [63:0] src1_in,       // rs
    input  [63:0] src2_in,       // rt
    input  [6:0]  dest_tag_in,
    input  [4:0]  rob_idx_in,

    output        pipe_ready,   // can accept new instruction this cycle

    // --- Stage-4 outputs (to CDB) ---
    output        valid_out,
    output [6:0]  dest_tag_out,
    output [4:0]  rob_idx_out,
    output [63:0] result_out
);

    // ----------------------------------------------------------------
    // Combinational FPU units (shared, selected by opcode in stage 1)
    // ----------------------------------------------------------------
    wire [63:0] fadd_result, fsub_result, fmul_result, fdiv_result;

    fpu_add u_fadd (
        .a      (src1_in),
        .b      (src2_in),
        .result (fadd_result)
    );

    wire [63:0] src2_negated = {~src2_in[63], src2_in[62:0]};
    fpu_add u_fsub (
        .a      (src1_in),
        .b      (src2_negated),
        .result (fsub_result)
    );

    fpu_mul u_fmul (
        .a      (src1_in),
        .b      (src2_in),
        .result (fmul_result)
    );

    fpu_div u_fdiv (
        .a      (src1_in),
        .b      (src2_in),
        .result (fdiv_result)
    );

    // Mux the result based on opcode (combinational, driven by the
    // *input* opcode so the result is ready by posedge stage-1 latch).
    reg [63:0] fpu_result_mux;
    always @(*) begin
        case (opcode_in)
            5'h14:   fpu_result_mux = fadd_result;   // FADD
            5'h15:   fpu_result_mux = fsub_result;    // FSUB
            5'h16:   fpu_result_mux = fmul_result;    // FMUL
            5'h17:   fpu_result_mux = fdiv_result;    // FDIV
            default: fpu_result_mux = 64'b0;
        endcase
    end

    // ----------------------------------------------------------------
    // 4-stage pipeline registers
    // ----------------------------------------------------------------

    // Stage 1
    reg        s1_valid;
    reg [6:0]  s1_dest_tag;
    reg [4:0]  s1_rob_idx;
    reg [63:0] s1_result;

    // Stage 2
    reg        s2_valid;
    reg [6:0]  s2_dest_tag;
    reg [4:0]  s2_rob_idx;
    reg [63:0] s2_result;

    // Stage 3
    reg        s3_valid;
    reg [6:0]  s3_dest_tag;
    reg [4:0]  s3_rob_idx;
    reg [63:0] s3_result;

    // Stage 4
    reg        s4_valid;
    reg [6:0]  s4_dest_tag;
    reg [4:0]  s4_rob_idx;
    reg [63:0] s4_result;

    // ----------------------------------------------------------------
    // Stall / ready logic
    // ----------------------------------------------------------------
    wire pipe_stalled = stall && s4_valid;
    wire advance      = !pipe_stalled;
    assign pipe_ready = !s1_valid || advance;

    // ----------------------------------------------------------------
    // Pipeline advancement
    // ----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            s4_valid <= 1'b0;
        end else if (flush) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            s4_valid <= 1'b0;
        end else if (advance) begin
            s4_valid    <= s3_valid;
            s4_dest_tag <= s3_dest_tag;
            s4_rob_idx  <= s3_rob_idx;
            s4_result   <= s3_result;

            s3_valid    <= s2_valid;
            s3_dest_tag <= s2_dest_tag;
            s3_rob_idx  <= s2_rob_idx;
            s3_result   <= s2_result;

            s2_valid    <= s1_valid;
            s2_dest_tag <= s1_dest_tag;
            s2_rob_idx  <= s1_rob_idx;
            s2_result   <= s1_result;

            s1_valid    <= valid_in;
            s1_dest_tag <= dest_tag_in;
            s1_rob_idx  <= rob_idx_in;
            s1_result   <= fpu_result_mux;
        end else begin
            if (!s1_valid) begin
                s1_valid    <= valid_in;
                s1_dest_tag <= dest_tag_in;
                s1_rob_idx  <= rob_idx_in;
                s1_result   <= fpu_result_mux;
            end
        end
    end

    // ----------------------------------------------------------------
    // Outputs (from stage 4)
    // ----------------------------------------------------------------
    assign valid_out    = s4_valid;
    assign dest_tag_out = s4_dest_tag;
    assign rob_idx_out  = s4_rob_idx;
    assign result_out   = s4_result;

endmodule
