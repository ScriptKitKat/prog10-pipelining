`ifndef CDB_SV_INCLUDED
`define CDB_SV_INCLUDED

// Common Data Bus — 2 broadcast buses with round-robin arbitration across 6 sources.
//
// Sources (fixed order for arbitration index 0..5):
//   0 = ALU0, 1 = ALU1, 2 = FPU0, 3 = FPU1, 4 = LSQ load 0, 5 = LSQ load 1
//
// Each cycle up to 2 asserted sources receive a grant and drive cdb{0,1}_*.
// Remaining valid sources are stalled (must hold their result next cycle).
// Priority rotates each cycle among sources that were serviced.
//
// Downstream (top-level wiring, not instantiated here):
//   — Reservation stations: operand wakeup (tag + value match)
//   — ROB: mark instruction complete (rob_idx + value + side-band if extended)
//   — Physical register file: write data, set ready bit (tag + value)

module cdb (
    input         clk,
    input         reset,

    // --- Source 0: ALU0 ---
    input         src_alu0_valid,
    input  [6:0]  src_alu0_tag,
    input  [63:0] src_alu0_value,
    input  [4:0]  src_alu0_rob_idx,

    // --- Source 1: ALU1 ---
    input         src_alu1_valid,
    input  [6:0]  src_alu1_tag,
    input  [63:0] src_alu1_value,
    input  [4:0]  src_alu1_rob_idx,

    // --- Source 2: FPU0 ---
    input         src_fpu0_valid,
    input  [6:0]  src_fpu0_tag,
    input  [63:0] src_fpu0_value,
    input  [4:0]  src_fpu0_rob_idx,

    // --- Source 3: FPU1 ---
    input         src_fpu1_valid,
    input  [6:0]  src_fpu1_tag,
    input  [63:0] src_fpu1_value,
    input  [4:0]  src_fpu1_rob_idx,

    // --- Source 4: LSQ load 0 ---
    input         src_lsq0_valid,
    input  [6:0]  src_lsq0_tag,
    input  [63:0] src_lsq0_value,
    input  [4:0]  src_lsq0_rob_idx,

    // --- Source 5: LSQ load 1 ---
    input         src_lsq1_valid,
    input  [6:0]  src_lsq1_tag,
    input  [63:0] src_lsq1_value,
    input  [4:0]  src_lsq1_rob_idx,

    // --- Broadcast bus 0 (combinational — listeners sample in same cycle) ---
    output wire        cdb_valid0,
    output wire [6:0]  cdb_tag0,
    output wire [63:0] cdb_value0,
    output wire [4:0]  cdb_rob_idx0,

    // --- Broadcast bus 1 ---
    output wire        cdb_valid1,
    output wire [6:0]  cdb_tag1,
    output wire [63:0] cdb_value1,
    output wire [4:0]  cdb_rob_idx1,

    // --- Per-source stall (valid but not granted this cycle) ---
    output wire        stall_alu0,
    output wire        stall_alu1,
    output wire        stall_fpu0,
    output wire        stall_fpu1,
    output wire        stall_lsq0,
    output wire        stall_lsq1,

    // --- Winner source IDs (for top-level side-band muxing) ---
    output wire [2:0]  win0_src_id,   // source index on bus 0 (0-5)
    output wire        win0_valid,
    output wire [2:0]  win1_src_id,   // source index on bus 1 (0-5)
    output wire        win1_valid
);

    localparam NSRC = 6;

    // Packed valid vector for combinational scan (iverilog-friendly)
    reg [NSRC-1:0] src_valid_packed;

    always @(*) begin
        src_valid_packed = {
            src_lsq1_valid,
            src_lsq0_valid,
            src_fpu1_valid,
            src_fpu0_valid,
            src_alu1_valid,
            src_alu0_valid
        };
    end

    // Round-robin pointer: next cycle starts after last granted in ring order
    reg [2:0] rr_ptr;

    // Combinational winners
    reg [2:0] win0, win1;
    reg       has_win0, has_win1;

    reg [3:0] sum;
    integer   step;
    reg [2:0] cand;
    reg       f0, f1;

    function [2:0] inc_mod6(input [2:0] x);
        begin
            if (x == 3'd5)
                inc_mod6 = 3'd0;
            else
                inc_mod6 = x + 3'd1;
        end
    endfunction

    always @(*) begin
        has_win0 = 1'b0;
        has_win1 = 1'b0;
        win0     = 3'd0;
        win1     = 3'd0;
        f0       = 1'b0;
        f1       = 1'b0;

        for (step = 0; step < NSRC; step = step + 1) begin
            sum = {1'b0, rr_ptr} + step[2:0];
            if (sum >= 4'd6)
                cand = sum[3:0] - 4'd6;
            else
                cand = sum[2:0];

            if (src_valid_packed[cand] && !f0) begin
                win0     = cand;
                has_win0 = 1'b1;
                f0       = 1'b1;
            end else if (src_valid_packed[cand] && f0 && !f1) begin
                win1     = cand;
                has_win1 = 1'b1;
                f1       = 1'b1;
            end
        end
    end

    // Mux data by win index
    reg [6:0]  mux_tag0,  mux_tag1;
    reg [63:0] mux_val0,  mux_val1;
    reg [4:0]  mux_rob0,  mux_rob1;

    always @(*) begin
        mux_tag0  = 7'd0;
        mux_val0  = 64'd0;
        mux_rob0  = 5'd0;
        mux_tag1  = 7'd0;
        mux_val1  = 64'd0;
        mux_rob1  = 5'd0;

        if (has_win0) begin
            case (win0)
                3'd0: begin mux_tag0 = src_alu0_tag; mux_val0 = src_alu0_value; mux_rob0 = src_alu0_rob_idx; end
                3'd1: begin mux_tag0 = src_alu1_tag; mux_val0 = src_alu1_value; mux_rob0 = src_alu1_rob_idx; end
                3'd2: begin mux_tag0 = src_fpu0_tag; mux_val0 = src_fpu0_value; mux_rob0 = src_fpu0_rob_idx; end
                3'd3: begin mux_tag0 = src_fpu1_tag; mux_val0 = src_fpu1_value; mux_rob0 = src_fpu1_rob_idx; end
                3'd4: begin mux_tag0 = src_lsq0_tag; mux_val0 = src_lsq0_value; mux_rob0 = src_lsq0_rob_idx; end
                3'd5: begin mux_tag0 = src_lsq1_tag; mux_val0 = src_lsq1_value; mux_rob0 = src_lsq1_rob_idx; end
                default: ;
            endcase
        end
        if (has_win1) begin
            case (win1)
                3'd0: begin mux_tag1 = src_alu0_tag; mux_val1 = src_alu0_value; mux_rob1 = src_alu0_rob_idx; end
                3'd1: begin mux_tag1 = src_alu1_tag; mux_val1 = src_alu1_value; mux_rob1 = src_alu1_rob_idx; end
                3'd2: begin mux_tag1 = src_fpu0_tag; mux_val1 = src_fpu0_value; mux_rob1 = src_fpu0_rob_idx; end
                3'd3: begin mux_tag1 = src_fpu1_tag; mux_val1 = src_fpu1_value; mux_rob1 = src_fpu1_rob_idx; end
                3'd4: begin mux_tag1 = src_lsq0_tag; mux_val1 = src_lsq0_value; mux_rob1 = src_lsq0_rob_idx; end
                3'd5: begin mux_tag1 = src_lsq1_tag; mux_val1 = src_lsq1_value; mux_rob1 = src_lsq1_rob_idx; end
                default: ;
            endcase
        end
    end

    wire grant_alu0 = (has_win0 && (win0 == 3'd0)) || (has_win1 && (win1 == 3'd0));
    wire grant_alu1 = (has_win0 && (win0 == 3'd1)) || (has_win1 && (win1 == 3'd1));
    wire grant_fpu0 = (has_win0 && (win0 == 3'd2)) || (has_win1 && (win1 == 3'd2));
    wire grant_fpu1 = (has_win0 && (win0 == 3'd3)) || (has_win1 && (win1 == 3'd3));
    wire grant_lsq0 = (has_win0 && (win0 == 3'd4)) || (has_win1 && (win1 == 3'd4));
    wire grant_lsq1 = (has_win0 && (win0 == 3'd5)) || (has_win1 && (win1 == 3'd5));

    assign cdb_valid0   = has_win0;
    assign cdb_tag0     = mux_tag0;
    assign cdb_value0   = mux_val0;
    assign cdb_rob_idx0 = mux_rob0;

    assign cdb_valid1   = has_win1;
    assign cdb_tag1     = mux_tag1;
    assign cdb_value1   = mux_val1;
    assign cdb_rob_idx1 = mux_rob1;

    assign stall_alu0 = src_alu0_valid && !grant_alu0;
    assign stall_alu1 = src_alu1_valid && !grant_alu1;
    assign stall_fpu0 = src_fpu0_valid && !grant_fpu0;
    assign stall_fpu1 = src_fpu1_valid && !grant_fpu1;
    assign stall_lsq0 = src_lsq0_valid && !grant_lsq0;
    assign stall_lsq1 = src_lsq1_valid && !grant_lsq1;

    assign win0_src_id = win0;
    assign win0_valid  = has_win0;
    assign win1_src_id = win1;
    assign win1_valid  = has_win1;

    always @(posedge clk or posedge reset) begin
        if (reset)
            rr_ptr <= 3'd0;
        else begin
            if (has_win1)
                rr_ptr <= inc_mod6(win1);
            else if (has_win0)
                rr_ptr <= inc_mod6(win0);
        end
    end

endmodule

`endif // CDB_SV_INCLUDED
