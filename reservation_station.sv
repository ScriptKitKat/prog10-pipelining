// Reservation Station — parameterized, dual-dispatch, dual-issue.
// Supports CDB snooping (2 buses), oldest-first issue (by ROB-head distance),
// grant-based issue acknowledgement, and flush of younger entries.
//
// CDB bypass: the combinational issue logic checks CDB tags in addition to
// registered ready bits, allowing same-cycle wakeup+issue. This removes the
// 1-cycle CDB-to-issue delay from every dependent chain.
//
// entry_valid, entry_src1_rdy, entry_src2_rdy, entry_br_pred are packed
// vectors so that always @(*) correctly re-triggers (iverilog workaround).

module reservation_station #(
    parameter NUM_ENTRIES = 8
) (
    input         clk,
    input         reset,

    // --- Dispatch port 0 ---
    input         dispatch_en0,
    input  [4:0]  dispatch_opcode0,
    input  [63:0] dispatch_src1_value0,
    input  [6:0]  dispatch_src1_tag0,
    input         dispatch_src1_ready0,
    input  [63:0] dispatch_src2_value0,
    input  [6:0]  dispatch_src2_tag0,
    input         dispatch_src2_ready0,
    input  [6:0]  dispatch_dest_tag0,
    input  [4:0]  dispatch_rob_idx0,
    input  [63:0] dispatch_imm0,
    input  [63:0] dispatch_pc0,
    input         dispatch_br_pred0,
    input  [63:0] dispatch_pred_target0,

    // --- Dispatch port 1 ---
    input         dispatch_en1,
    input  [4:0]  dispatch_opcode1,
    input  [63:0] dispatch_src1_value1,
    input  [6:0]  dispatch_src1_tag1,
    input         dispatch_src1_ready1,
    input  [63:0] dispatch_src2_value1,
    input  [6:0]  dispatch_src2_tag1,
    input         dispatch_src2_ready1,
    input  [6:0]  dispatch_dest_tag1,
    input  [4:0]  dispatch_rob_idx1,
    input  [63:0] dispatch_imm1,
    input  [63:0] dispatch_pc1,
    input         dispatch_br_pred1,
    input  [63:0] dispatch_pred_target1,

    output        full,
    output        almost_full,

    // --- CDB snoop (2 buses) ---
    input         cdb_valid0,
    input  [6:0]  cdb_tag0,
    input  [63:0] cdb_value0,
    input         cdb_valid1,
    input  [6:0]  cdb_tag1,
    input  [63:0] cdb_value1,

    // --- Issue port 0 (oldest ready, combinational) ---
    output reg        issue_valid0,
    output reg [4:0]  issue_opcode0,
    output reg [63:0] issue_src1_value0,
    output reg [63:0] issue_src2_value0,
    output reg [6:0]  issue_dest_tag0,
    output reg [4:0]  issue_rob_idx0,
    output reg [63:0] issue_imm0,
    output reg [63:0] issue_pc0,
    output reg        issue_br_pred0,
    output reg [63:0] issue_pred_target0,
    input             issue_grant0,

    // --- Issue port 1 (second oldest ready, combinational) ---
    output reg        issue_valid1,
    output reg [4:0]  issue_opcode1,
    output reg [63:0] issue_src1_value1,
    output reg [63:0] issue_src2_value1,
    output reg [6:0]  issue_dest_tag1,
    output reg [4:0]  issue_rob_idx1,
    output reg [63:0] issue_imm1,
    output reg [63:0] issue_pc1,
    output reg        issue_br_pred1,
    output reg [63:0] issue_pred_target1,
    input             issue_grant1,

    // --- Flush interface ---
    input         flush_en,
    input  [4:0]  flush_rob_idx,
    input  [4:0]  rob_head_idx
);

    // Packed vectors for sensitivity-critical signals
    reg [NUM_ENTRIES-1:0] entry_valid;
    reg [NUM_ENTRIES-1:0] entry_src1_rdy;
    reg [NUM_ENTRIES-1:0] entry_src2_rdy;
    reg [NUM_ENTRIES-1:0] entry_br_pred;

    // Unpacked arrays for data fields
    reg [4:0]  entry_opcode   [0:NUM_ENTRIES-1];
    reg [63:0] entry_src1_val [0:NUM_ENTRIES-1];
    reg [6:0]  entry_src1_tag [0:NUM_ENTRIES-1];
    reg [63:0] entry_src2_val [0:NUM_ENTRIES-1];
    reg [6:0]  entry_src2_tag [0:NUM_ENTRIES-1];
    reg [6:0]  entry_dest_tag [0:NUM_ENTRIES-1];
    reg [4:0]  entry_rob_idx  [0:NUM_ENTRIES-1];
    reg [63:0] entry_imm      [0:NUM_ENTRIES-1];
    reg [63:0] entry_pc       [0:NUM_ENTRIES-1];
    reg [63:0] entry_pred_tgt[0:NUM_ENTRIES-1];

    // --- Free-slot finder (find first two free) ---
    integer fi;
    reg       has_free0, has_free1;
    reg [3:0] free_slot0, free_slot1;

    always @(*) begin
        has_free0 = 0; free_slot0 = 0;
        has_free1 = 0; free_slot1 = 0;
        for (fi = 0; fi < NUM_ENTRIES; fi = fi + 1) begin
            if (!entry_valid[fi]) begin
                if (!has_free0) begin
                    has_free0  = 1;
                    free_slot0 = fi[3:0];
                end else if (!has_free1) begin
                    has_free1  = 1;
                    free_slot1 = fi[3:0];
                end
            end
        end
    end

    assign full        = !has_free0;
    assign almost_full = has_free0 && !has_free1;

    // --- CDB bypass: compute effective readiness + value per entry ---
    // These are combinational signals used by the issue selector below.
    reg [NUM_ENTRIES-1:0] eff_src1_rdy;
    reg [NUM_ENTRIES-1:0] eff_src2_rdy;
    reg [63:0] eff_src1_val [0:NUM_ENTRIES-1];
    reg [63:0] eff_src2_val [0:NUM_ENTRIES-1];

    integer bi;
    always @(*) begin
        for (bi = 0; bi < NUM_ENTRIES; bi = bi + 1) begin
            // src1 bypass
            if (entry_src1_rdy[bi]) begin
                eff_src1_rdy[bi] = 1'b1;
                eff_src1_val[bi] = entry_src1_val[bi];
            end else if (cdb_valid0 && entry_valid[bi] && entry_src1_tag[bi] == cdb_tag0) begin
                eff_src1_rdy[bi] = 1'b1;
                eff_src1_val[bi] = cdb_value0;
            end else if (cdb_valid1 && entry_valid[bi] && entry_src1_tag[bi] == cdb_tag1) begin
                eff_src1_rdy[bi] = 1'b1;
                eff_src1_val[bi] = cdb_value1;
            end else begin
                eff_src1_rdy[bi] = 1'b0;
                eff_src1_val[bi] = entry_src1_val[bi];
            end

            // src2 bypass
            if (entry_src2_rdy[bi]) begin
                eff_src2_rdy[bi] = 1'b1;
                eff_src2_val[bi] = entry_src2_val[bi];
            end else if (cdb_valid0 && entry_valid[bi] && entry_src2_tag[bi] == cdb_tag0) begin
                eff_src2_rdy[bi] = 1'b1;
                eff_src2_val[bi] = cdb_value0;
            end else if (cdb_valid1 && entry_valid[bi] && entry_src2_tag[bi] == cdb_tag1) begin
                eff_src2_rdy[bi] = 1'b1;
                eff_src2_val[bi] = cdb_value1;
            end else begin
                eff_src2_rdy[bi] = 1'b0;
                eff_src2_val[bi] = entry_src2_val[bi];
            end
        end
    end

    // --- Oldest-ready selector (dual: find two oldest ready entries) ---
    integer ii;
    reg       found0, found1;
    reg [3:0] sel0,   sel1;
    reg [4:0] best0,  best1;

    always @(*) begin
        found0 = 0; sel0 = 0; best0 = 5'd31;
        found1 = 0; sel1 = 0; best1 = 5'd31;

        issue_valid0 = 0; issue_opcode0 = 0; issue_src1_value0 = 0;
        issue_src2_value0 = 0; issue_dest_tag0 = 0;
        issue_rob_idx0 = 0; issue_imm0 = 0; issue_pc0 = 0; issue_br_pred0 = 0;
        issue_pred_target0 = 0;

        issue_valid1 = 0; issue_opcode1 = 0; issue_src1_value1 = 0;
        issue_src2_value1 = 0; issue_dest_tag1 = 0;
        issue_rob_idx1 = 0; issue_imm1 = 0; issue_pc1 = 0; issue_br_pred1 = 0;
        issue_pred_target1 = 0;

        // Pass 1: find oldest ready (using CDB-bypassed readiness)
        for (ii = 0; ii < NUM_ENTRIES; ii = ii + 1) begin
            if (entry_valid[ii] && eff_src1_rdy[ii] && eff_src2_rdy[ii]) begin
                if ((entry_rob_idx[ii] - rob_head_idx) < best0 || !found0) begin
                    found0 = 1;
                    best0  = entry_rob_idx[ii] - rob_head_idx;
                    sel0   = ii[3:0];
                end
            end
        end

        // Pass 2: find second oldest ready (skip sel0)
        for (ii = 0; ii < NUM_ENTRIES; ii = ii + 1) begin
            if (entry_valid[ii] && eff_src1_rdy[ii] && eff_src2_rdy[ii] &&
                (ii[3:0] != sel0 || !found0)) begin
                if ((entry_rob_idx[ii] - rob_head_idx) < best1 || !found1) begin
                    if (ii[3:0] != sel0) begin
                        found1 = 1;
                        best1  = entry_rob_idx[ii] - rob_head_idx;
                        sel1   = ii[3:0];
                    end
                end
            end
        end

        // Output selected entries with bypassed values
        if (found0) begin
            issue_valid0      = 1;
            issue_opcode0     = entry_opcode[sel0];
            issue_src1_value0 = eff_src1_val[sel0];
            issue_src2_value0 = eff_src2_val[sel0];
            issue_dest_tag0   = entry_dest_tag[sel0];
            issue_rob_idx0    = entry_rob_idx[sel0];
            issue_imm0        = entry_imm[sel0];
            issue_pc0         = entry_pc[sel0];
            issue_br_pred0    = entry_br_pred[sel0];
            issue_pred_target0 = entry_pred_tgt[sel0];
        end
        if (found1) begin
            issue_valid1      = 1;
            issue_opcode1     = entry_opcode[sel1];
            issue_src1_value1 = eff_src1_val[sel1];
            issue_src2_value1 = eff_src2_val[sel1];
            issue_dest_tag1   = entry_dest_tag[sel1];
            issue_rob_idx1    = entry_rob_idx[sel1];
            issue_imm1        = entry_imm[sel1];
            issue_pc1         = entry_pc[sel1];
            issue_br_pred1    = entry_br_pred[sel1];
            issue_pred_target1 = entry_pred_tgt[sel1];
        end
    end

    // --- Sequential: dispatch, CDB snoop, issue clear, flush ---
    integer si;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            entry_valid    <= {NUM_ENTRIES{1'b0}};
            entry_src1_rdy <= {NUM_ENTRIES{1'b0}};
            entry_src2_rdy <= {NUM_ENTRIES{1'b0}};
            entry_br_pred  <= {NUM_ENTRIES{1'b0}};
            for (si = 0; si < NUM_ENTRIES; si = si + 1) begin
                entry_opcode[si]   <= 5'd0;
                entry_src1_val[si] <= 64'd0;
                entry_src1_tag[si] <= 7'd0;
                entry_src2_val[si] <= 64'd0;
                entry_src2_tag[si] <= 7'd0;
                entry_dest_tag[si] <= 7'd0;
                entry_rob_idx[si]  <= 5'd0;
                entry_imm[si]      <= 64'd0;
                entry_pc[si]       <= 64'd0;
                entry_pred_tgt[si] <= 64'd0;
            end
        end else begin
            // ---- Dispatch ----
            if (dispatch_en0 && has_free0) begin
                entry_valid[free_slot0]    <= 1'b1;
                entry_opcode[free_slot0]   <= dispatch_opcode0;
                entry_src1_tag[free_slot0] <= dispatch_src1_tag0;
                entry_src2_tag[free_slot0] <= dispatch_src2_tag0;
                entry_dest_tag[free_slot0] <= dispatch_dest_tag0;
                entry_rob_idx[free_slot0]  <= dispatch_rob_idx0;
                entry_imm[free_slot0]      <= dispatch_imm0;
                entry_pc[free_slot0]       <= dispatch_pc0;
                entry_br_pred[free_slot0]  <= dispatch_br_pred0;
                entry_pred_tgt[free_slot0] <= dispatch_pred_target0;
                // src1 with CDB bypass
                if (dispatch_src1_ready0) begin
                    entry_src1_rdy[free_slot0] <= 1'b1;
                    entry_src1_val[free_slot0] <= dispatch_src1_value0;
                end else if (cdb_valid0 && dispatch_src1_tag0 == cdb_tag0) begin
                    entry_src1_rdy[free_slot0] <= 1'b1;
                    entry_src1_val[free_slot0] <= cdb_value0;
                end else if (cdb_valid1 && dispatch_src1_tag0 == cdb_tag1) begin
                    entry_src1_rdy[free_slot0] <= 1'b1;
                    entry_src1_val[free_slot0] <= cdb_value1;
                end else begin
                    entry_src1_rdy[free_slot0] <= 1'b0;
                    entry_src1_val[free_slot0] <= dispatch_src1_value0;
                end
                // src2 with CDB bypass
                if (dispatch_src2_ready0) begin
                    entry_src2_rdy[free_slot0] <= 1'b1;
                    entry_src2_val[free_slot0] <= dispatch_src2_value0;
                end else if (cdb_valid0 && dispatch_src2_tag0 == cdb_tag0) begin
                    entry_src2_rdy[free_slot0] <= 1'b1;
                    entry_src2_val[free_slot0] <= cdb_value0;
                end else if (cdb_valid1 && dispatch_src2_tag0 == cdb_tag1) begin
                    entry_src2_rdy[free_slot0] <= 1'b1;
                    entry_src2_val[free_slot0] <= cdb_value1;
                end else begin
                    entry_src2_rdy[free_slot0] <= 1'b0;
                    entry_src2_val[free_slot0] <= dispatch_src2_value0;
                end
            end
            if (dispatch_en1 && has_free1) begin
                entry_valid[free_slot1]    <= 1'b1;
                entry_opcode[free_slot1]   <= dispatch_opcode1;
                entry_src1_tag[free_slot1] <= dispatch_src1_tag1;
                entry_src2_tag[free_slot1] <= dispatch_src2_tag1;
                entry_dest_tag[free_slot1] <= dispatch_dest_tag1;
                entry_rob_idx[free_slot1]  <= dispatch_rob_idx1;
                entry_imm[free_slot1]      <= dispatch_imm1;
                entry_pc[free_slot1]       <= dispatch_pc1;
                entry_br_pred[free_slot1]  <= dispatch_br_pred1;
                entry_pred_tgt[free_slot1] <= dispatch_pred_target1;
                // src1 with CDB bypass
                if (dispatch_src1_ready1) begin
                    entry_src1_rdy[free_slot1] <= 1'b1;
                    entry_src1_val[free_slot1] <= dispatch_src1_value1;
                end else if (cdb_valid0 && dispatch_src1_tag1 == cdb_tag0) begin
                    entry_src1_rdy[free_slot1] <= 1'b1;
                    entry_src1_val[free_slot1] <= cdb_value0;
                end else if (cdb_valid1 && dispatch_src1_tag1 == cdb_tag1) begin
                    entry_src1_rdy[free_slot1] <= 1'b1;
                    entry_src1_val[free_slot1] <= cdb_value1;
                end else begin
                    entry_src1_rdy[free_slot1] <= 1'b0;
                    entry_src1_val[free_slot1] <= dispatch_src1_value1;
                end
                // src2 with CDB bypass
                if (dispatch_src2_ready1) begin
                    entry_src2_rdy[free_slot1] <= 1'b1;
                    entry_src2_val[free_slot1] <= dispatch_src2_value1;
                end else if (cdb_valid0 && dispatch_src2_tag1 == cdb_tag0) begin
                    entry_src2_rdy[free_slot1] <= 1'b1;
                    entry_src2_val[free_slot1] <= cdb_value0;
                end else if (cdb_valid1 && dispatch_src2_tag1 == cdb_tag1) begin
                    entry_src2_rdy[free_slot1] <= 1'b1;
                    entry_src2_val[free_slot1] <= cdb_value1;
                end else begin
                    entry_src2_rdy[free_slot1] <= 1'b0;
                    entry_src2_val[free_slot1] <= dispatch_src2_value1;
                end
            end

            // ---- CDB snoop (update registered ready bits for next cycle) ----
            for (si = 0; si < NUM_ENTRIES; si = si + 1) begin
                if (entry_valid[si]) begin
                    if (cdb_valid0 && !entry_src1_rdy[si] && entry_src1_tag[si] == cdb_tag0) begin
                        entry_src1_val[si] <= cdb_value0;
                        entry_src1_rdy[si] <= 1'b1;
                    end
                    if (cdb_valid0 && !entry_src2_rdy[si] && entry_src2_tag[si] == cdb_tag0) begin
                        entry_src2_val[si] <= cdb_value0;
                        entry_src2_rdy[si] <= 1'b1;
                    end
                    if (cdb_valid1 && !entry_src1_rdy[si] && entry_src1_tag[si] == cdb_tag1) begin
                        entry_src1_val[si] <= cdb_value1;
                        entry_src1_rdy[si] <= 1'b1;
                    end
                    if (cdb_valid1 && !entry_src2_rdy[si] && entry_src2_tag[si] == cdb_tag1) begin
                        entry_src2_val[si] <= cdb_value1;
                        entry_src2_rdy[si] <= 1'b1;
                    end
                end
            end

            // ---- Issue clear (only when granted) ----
            if (issue_valid0 && issue_grant0)
                entry_valid[sel0] <= 1'b0;
            if (issue_valid1 && issue_grant1)
                entry_valid[sel1] <= 1'b0;

            // ---- Flush ----
            if (flush_en) begin
                for (si = 0; si < NUM_ENTRIES; si = si + 1) begin
                    if (entry_valid[si] &&
                        ((entry_rob_idx[si] - flush_rob_idx) != 0) &&
                        ((entry_rob_idx[si] - rob_head_idx) >
                         (flush_rob_idx   - rob_head_idx)))
                        entry_valid[si] <= 1'b0;
                end
            end
        end
    end

endmodule
