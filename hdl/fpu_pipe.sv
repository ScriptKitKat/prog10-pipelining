`ifndef FPU_PIPE_SV_INCLUDED
`define FPU_PIPE_SV_INCLUDED

// FPU Execution Pipeline — 2-stage wrapper (same depth as alu_pipe).
//
// Stage 1: Latch opcode + operands; compute combinational FPU result from regs.
// Stage 2: Latch result for CDB.  Latency = 2 cycles (was 4; shorter = better ILP on FP benchmarks).
//
// Reuses existing combinational fpu_add, fpu_mul, fpu_div modules from fpu.sv.

`include "fpu.sv"

module fpu_pipe (
    input         clk,
    input         reset,
    input         flush,
    input         stall,        // CDB couldn't accept s2 output — freeze pipeline

    // --- Issue inputs (from FPU reservation station) ---
    input         valid_in,
    input  [4:0]  opcode_in,
    input  [63:0] src1_in,       // rs
    input  [63:0] src2_in,       // rt
    input  [6:0]  dest_tag_in,
    input  [4:0]  rob_idx_in,

    output        pipe_ready,   // can accept new instruction this cycle

    // --- Stage-2 outputs (to CDB) ---
    output        valid_out,
    output [6:0]  dest_tag_out,
    output [4:0]  rob_idx_out,
    output [63:0] result_out
);

    // ----------------------------------------------------------------
    // Stage-1 registers (operands)
    // ----------------------------------------------------------------
    reg        s1_valid;
    reg [4:0]  s1_opcode;
    reg [63:0] s1_src1, s1_src2;
    reg [6:0]  s1_dest_tag;
    reg [4:0]  s1_rob_idx;

    // ----------------------------------------------------------------
    // Combinational FPU — driven from registered operands (timing like alu_pipe)
    // ----------------------------------------------------------------
    wire [63:0] fadd_result, fsub_result, fmul_result, fdiv_result;

    fpu_add u_fadd (
        .a      (s1_src1),
        .b      (s1_src2),
        .result (fadd_result)
    );

    wire [63:0] s1_src2_neg = {~s1_src2[63], s1_src2[62:0]};
    fpu_add u_fsub (
        .a      (s1_src1),
        .b      (s1_src2_neg),
        .result (fsub_result)
    );

    fpu_mul u_fmul (
        .a      (s1_src1),
        .b      (s1_src2),
        .result (fmul_result)
    );

    fpu_div u_fdiv (
        .a      (s1_src1),
        .b      (s1_src2),
        .result (fdiv_result)
    );

    reg [63:0] s1_result_c;
    always @(*) begin
        case (s1_opcode)
            5'h14:   s1_result_c = fadd_result;
            5'h15:   s1_result_c = fsub_result;
            5'h16:   s1_result_c = fmul_result;
            5'h17:   s1_result_c = fdiv_result;
            default: s1_result_c = 64'b0;
        endcase
    end

    // ----------------------------------------------------------------
    // Stage-2 pipeline registers
    // ----------------------------------------------------------------
    reg        s2_valid;
    reg [6:0]  s2_dest_tag;
    reg [4:0]  s2_rob_idx;
    reg [63:0] s2_result;

    // ----------------------------------------------------------------
    // Stall / ready (same pattern as alu_pipe)
    // ----------------------------------------------------------------
    wire pipe_stalled = stall && s2_valid;
    wire advance      = !pipe_stalled;
    assign pipe_ready = !s1_valid || advance;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
        end else if (flush) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
        end else if (advance) begin
            s2_valid    <= s1_valid;
            s2_dest_tag <= s1_dest_tag;
            s2_rob_idx  <= s1_rob_idx;
            s2_result   <= s1_result_c;

            s1_valid    <= valid_in;
            s1_opcode   <= opcode_in;
            s1_src1     <= src1_in;
            s1_src2     <= src2_in;
            s1_dest_tag <= dest_tag_in;
            s1_rob_idx  <= rob_idx_in;
        end else begin
            if (!s1_valid) begin
                s1_valid    <= valid_in;
                s1_opcode   <= opcode_in;
                s1_src1     <= src1_in;
                s1_src2     <= src2_in;
                s1_dest_tag <= dest_tag_in;
                s1_rob_idx  <= rob_idx_in;
            end
        end
    end

    assign valid_out    = s2_valid;
    assign dest_tag_out = s2_dest_tag;
    assign rob_idx_out  = s2_rob_idx;
    assign result_out   = s2_result;

endmodule

`endif // FPU_PIPE_SV_INCLUDED
