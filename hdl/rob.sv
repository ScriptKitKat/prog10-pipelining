// Reorder Buffer (ROB) — 32-entry circular buffer for in-order commit.
// Supports dual allocate, dual complete (CDB), dual commit, and flush with
// multi-cycle drain of freed physical registers back to the free list.

module rob (
    input         clk,
    input         reset,

    // --- Allocate interface (from decode/rename, up to 2 per cycle) ---
    input         alloc_en0,
    input  [2:0]  alloc_type0,
    input  [4:0]  alloc_arch_rd0,
    input  [6:0]  alloc_old_phys0,
    input  [6:0]  alloc_new_phys0,
    input         alloc_has_dest0,
    input         alloc_br_pred0,
    input  [63:0] alloc_pc0,

    input         alloc_en1,
    input  [2:0]  alloc_type1,
    input  [4:0]  alloc_arch_rd1,
    input  [6:0]  alloc_old_phys1,
    input  [6:0]  alloc_new_phys1,
    input         alloc_has_dest1,
    input         alloc_br_pred1,
    input  [63:0] alloc_pc1,

    output [4:0]  alloc_idx0,
    output [4:0]  alloc_idx1,
    output        full,

    // --- Complete interface (from CDB, up to 2 per cycle) ---
    input         cdb_valid0,
    input  [4:0]  cdb_rob_idx0,
    input  [63:0] cdb_value0,
    input  [63:0] cdb_store_addr0,
    input         cdb_br_actual0,
    input         cdb_mispredict0,

    input         cdb_valid1,
    input  [4:0]  cdb_rob_idx1,
    input  [63:0] cdb_value1,
    input  [63:0] cdb_store_addr1,
    input         cdb_br_actual1,
    input         cdb_mispredict1,

    // --- Commit outputs (active for one cycle per committed instruction) ---
    output reg        commit_en0,
    output reg [2:0]  commit_type0,
    output reg [4:0]  commit_arch_rd0,
    output reg [6:0]  commit_old_phys0,
    output reg [6:0]  commit_new_phys0,
    output reg [63:0] commit_store_addr0,
    output reg [63:0] commit_store_data0,

    output reg        commit_en1,
    output reg [2:0]  commit_type1,
    output reg [4:0]  commit_arch_rd1,
    output reg [6:0]  commit_old_phys1,
    output reg [6:0]  commit_new_phys1,
    output reg [63:0] commit_store_addr1,
    output reg [63:0] commit_store_data1,

    output reg        hlt,

    // --- Flush interface ---
    input             flush_en,
    input  [4:0]      flush_rob_idx,
    output reg [63:0] flush_redirect_pc,

    // Flush drain: returns freed physical registers to the free list (2/cycle)
    output reg        flush_active,
    output reg        flush_free_en0,
    output reg [6:0]  flush_free_reg0,
    output reg        flush_free_en1,
    output reg [6:0]  flush_free_reg1,

    // --- Status ---
    output            empty
);

    localparam ROB_SIZE = 32;
    localparam IDX_BITS = 5;

    localparam TYPE_ALU    = 3'd0;
    localparam TYPE_FPU    = 3'd1;
    localparam TYPE_LOAD   = 3'd2;
    localparam TYPE_STORE  = 3'd3;
    localparam TYPE_BRANCH = 3'd4;
    localparam TYPE_HALT   = 3'd5;
    localparam TYPE_OTHER  = 3'd6;

    // --- ROB entry storage (parallel arrays) ---
    reg        valid      [0:ROB_SIZE-1];
    reg [2:0]  itype      [0:ROB_SIZE-1];
    reg [4:0]  arch_rd    [0:ROB_SIZE-1];
    reg [6:0]  old_phys   [0:ROB_SIZE-1];
    reg [6:0]  new_phys   [0:ROB_SIZE-1];
    reg        has_dest   [0:ROB_SIZE-1];
    reg        completed  [0:ROB_SIZE-1];
    reg        br_pred    [0:ROB_SIZE-1];
    reg        br_actual  [0:ROB_SIZE-1];
    reg        mispred    [0:ROB_SIZE-1];
    reg [63:0] store_addr [0:ROB_SIZE-1];
    reg [63:0] value      [0:ROB_SIZE-1];
    reg [63:0] pc         [0:ROB_SIZE-1];

    // --- Head / tail pointers (extra bit for full/empty disambiguation) ---
    reg [IDX_BITS:0] head, tail;
    wire [IDX_BITS-1:0] head_idx = head[IDX_BITS-1:0];
    wire [IDX_BITS-1:0] tail_idx = tail[IDX_BITS-1:0];

    wire [IDX_BITS:0] count = tail - head;
    assign full  = (count >= ROB_SIZE - 1);
    assign empty = (count == 0);

    assign alloc_idx0 = tail_idx;
    assign alloc_idx1 = tail_idx + 5'd1;

    // --- Flush drain state ---
    reg [IDX_BITS:0] drain_ptr;
    reg [IDX_BITS:0] drain_end;

    // --- Combinational commit logic ---
    reg can_commit0, can_commit1;
    wire [4:0] cidx0 = head_idx;
    wire [4:0] cidx1 = head_idx + 5'd1;

    always @(*) begin
        commit_en0 = 0; commit_type0 = 0; commit_arch_rd0 = 0;
        commit_old_phys0 = 0; commit_new_phys0 = 0;
        commit_store_addr0 = 0; commit_store_data0 = 0;
        commit_en1 = 0; commit_type1 = 0; commit_arch_rd1 = 0;
        commit_old_phys1 = 0; commit_new_phys1 = 0;
        commit_store_addr1 = 0; commit_store_data1 = 0;
        can_commit0 = 0;
        can_commit1 = 0;

        if (!flush_en && !flush_active && count > 0 &&
            valid[cidx0] && completed[cidx0]) begin

            can_commit0        = 1;
            commit_en0         = 1;
            commit_type0       = itype[cidx0];
            commit_arch_rd0    = arch_rd[cidx0];
            commit_old_phys0   = old_phys[cidx0];
            commit_new_phys0   = new_phys[cidx0];
            commit_store_addr0 = store_addr[cidx0];
            commit_store_data0 = value[cidx0];

            if (itype[cidx0] != TYPE_STORE && itype[cidx0] != TYPE_HALT &&
                count > 1 && valid[cidx1] && completed[cidx1]) begin

                can_commit1        = 1;
                commit_en1         = 1;
                commit_type1       = itype[cidx1];
                commit_arch_rd1    = arch_rd[cidx1];
                commit_old_phys1   = old_phys[cidx1];
                commit_new_phys1   = new_phys[cidx1];
                commit_store_addr1 = store_addr[cidx1];
                commit_store_data1 = value[cidx1];
            end
        end
    end

    // --- Flush new-tail calculation ---
    wire [4:0]        flush_offset   = flush_rob_idx - head_idx;
    wire [IDX_BITS:0] flush_new_tail = head + {1'b0, flush_offset} + 1;

    // --- Sequential logic ---
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head         <= 0;
            tail         <= 0;
            hlt          <= 0;
            flush_active <= 0;
            flush_free_en0  <= 0;
            flush_free_en1  <= 0;
            flush_redirect_pc <= 64'd0;
            drain_ptr    <= 0;
            drain_end    <= 0;
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                valid[i]     <= 0;
                completed[i] <= 0;
            end

        end else begin
            // Default: deassert drain free-list outputs each cycle
            flush_free_en0 <= 0;
            flush_free_en1 <= 0;

            // ---- CDB completion (always processed) ----
            if (cdb_valid0) begin
                completed[cdb_rob_idx0]  <= 1;
                value[cdb_rob_idx0]      <= cdb_value0;
                store_addr[cdb_rob_idx0] <= cdb_store_addr0;
                br_actual[cdb_rob_idx0]  <= cdb_br_actual0;
                mispred[cdb_rob_idx0]    <= cdb_mispredict0;
            end
            if (cdb_valid1) begin
                completed[cdb_rob_idx1]  <= 1;
                value[cdb_rob_idx1]      <= cdb_value1;
                store_addr[cdb_rob_idx1] <= cdb_store_addr1;
                br_actual[cdb_rob_idx1]  <= cdb_br_actual1;
                mispred[cdb_rob_idx1]    <= cdb_mispredict1;
            end

            // ---- Flush / Drain / Normal operations (mutually exclusive) ----
            if (flush_en) begin
                // Redirect PC: forward from CDB if the branch is completing now
                if (cdb_valid0 && cdb_rob_idx0 == flush_rob_idx)
                    flush_redirect_pc <= cdb_value0;
                else if (cdb_valid1 && cdb_rob_idx1 == flush_rob_idx)
                    flush_redirect_pc <= cdb_value1;
                else
                    flush_redirect_pc <= value[flush_rob_idx];

                // Set new tail and start drain
                tail      <= flush_new_tail;
                drain_ptr <= flush_new_tail;
                drain_end <= tail;
                flush_active <= (flush_new_tail != tail);

            end else if (flush_active) begin
                // ---- Drain: return new_phys of flushed entries to free list ----
                if ((drain_end - drain_ptr) >= 2) begin
                    if (has_dest[drain_ptr[IDX_BITS-1:0]]) begin
                        flush_free_en0  <= 1;
                        flush_free_reg0 <= new_phys[drain_ptr[IDX_BITS-1:0]];
                    end
                    if (has_dest[drain_ptr[IDX_BITS-1:0] + 5'd1]) begin
                        flush_free_en1  <= 1;
                        flush_free_reg1 <= new_phys[drain_ptr[IDX_BITS-1:0] + 5'd1];
                    end
                    valid[drain_ptr[IDX_BITS-1:0]]        <= 0;
                    valid[drain_ptr[IDX_BITS-1:0] + 5'd1] <= 0;
                    drain_ptr <= drain_ptr + 2;
                    if ((drain_end - drain_ptr) <= 2)
                        flush_active <= 0;

                end else if ((drain_end - drain_ptr) == 1) begin
                    if (has_dest[drain_ptr[IDX_BITS-1:0]]) begin
                        flush_free_en0  <= 1;
                        flush_free_reg0 <= new_phys[drain_ptr[IDX_BITS-1:0]];
                    end
                    valid[drain_ptr[IDX_BITS-1:0]] <= 0;
                    drain_ptr    <= drain_ptr + 1;
                    flush_active <= 0;

                end else begin
                    flush_active <= 0;
                end

            end else begin
                // ---- Normal: commit + allocate ----

                // Commit: advance head
                if (can_commit0 && can_commit1) begin
                    valid[cidx0] <= 0;
                    valid[cidx1] <= 0;
                    head <= head + 2;
                    if (itype[cidx0] == TYPE_HALT || itype[cidx1] == TYPE_HALT)
                        hlt <= 1;
                end else if (can_commit0) begin
                    valid[cidx0] <= 0;
                    head <= head + 1;
                    if (itype[cidx0] == TYPE_HALT)
                        hlt <= 1;
                end

                // Allocate: advance tail
                if (alloc_en0 && alloc_en1 && !full) begin
                    valid[tail_idx]     <= 1;
                    itype[tail_idx]     <= alloc_type0;
                    arch_rd[tail_idx]   <= alloc_arch_rd0;
                    old_phys[tail_idx]  <= alloc_old_phys0;
                    new_phys[tail_idx]  <= alloc_new_phys0;
                    has_dest[tail_idx]  <= alloc_has_dest0;
                    completed[tail_idx] <= (alloc_type0 == TYPE_HALT);
                    br_pred[tail_idx]   <= alloc_br_pred0;
                    mispred[tail_idx]   <= 0;
                    pc[tail_idx]        <= alloc_pc0;

                    valid[tail_idx + 5'd1]     <= 1;
                    itype[tail_idx + 5'd1]     <= alloc_type1;
                    arch_rd[tail_idx + 5'd1]   <= alloc_arch_rd1;
                    old_phys[tail_idx + 5'd1]  <= alloc_old_phys1;
                    new_phys[tail_idx + 5'd1]  <= alloc_new_phys1;
                    has_dest[tail_idx + 5'd1]  <= alloc_has_dest1;
                    completed[tail_idx + 5'd1] <= (alloc_type1 == TYPE_HALT);
                    br_pred[tail_idx + 5'd1]   <= alloc_br_pred1;
                    mispred[tail_idx + 5'd1]   <= 0;
                    pc[tail_idx + 5'd1]        <= alloc_pc1;

                    tail <= tail + 2;

                end else if (alloc_en0 && count < ROB_SIZE) begin
                    valid[tail_idx]     <= 1;
                    itype[tail_idx]     <= alloc_type0;
                    arch_rd[tail_idx]   <= alloc_arch_rd0;
                    old_phys[tail_idx]  <= alloc_old_phys0;
                    new_phys[tail_idx]  <= alloc_new_phys0;
                    has_dest[tail_idx]  <= alloc_has_dest0;
                    completed[tail_idx] <= (alloc_type0 == TYPE_HALT);
                    br_pred[tail_idx]   <= alloc_br_pred0;
                    mispred[tail_idx]   <= 0;
                    pc[tail_idx]        <= alloc_pc0;

                    tail <= tail + 1;
                end
            end
        end
    end

endmodule
