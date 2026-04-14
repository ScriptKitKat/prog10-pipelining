// Load / Store Queue — 8-entry load queue + 8-entry store queue.
//
// Load flow:  dispatch → address arrival → forwarding check → memory read → CDB
// Store flow: dispatch → address & data arrival → complete (CDB) → ROB commit
//             → memory write → clear
//
// Store-to-load forwarding: youngest older store with matching address and
// data ready supplies the load result.  If the youngest matching older store
// has no data, the load waits.  Stores without an address are ignored
// (optimistic, no speculation rollback).
//
// Packed bit-vectors for status flags (iverilog always @(*) workaround).

module load_store_queue (
    input         clk,
    input         reset,

    // --- Flush ---
    input         flush_en,
    input  [4:0]  flush_rob_idx,
    input  [4:0]  rob_head_idx,

    // --- Load dispatch port 0 (from decode) ---
    input         ld_dispatch_en0,
    input  [4:0]  ld_dispatch_rob_idx0,
    input  [6:0]  ld_dispatch_dest_tag0,
    // --- Load dispatch port 1 ---
    input         ld_dispatch_en1,
    input  [4:0]  ld_dispatch_rob_idx1,
    input  [6:0]  ld_dispatch_dest_tag1,
    output        ld_full,
    output        ld_almost_full,

    // --- Store dispatch port 0 (from decode) ---
    input         st_dispatch_en0,
    input  [4:0]  st_dispatch_rob_idx0,
    input  [63:0] st_dispatch_data0,
    input         st_dispatch_data_ready0,
    input  [6:0]  st_dispatch_data_tag0,
    // --- Store dispatch port 1 ---
    input         st_dispatch_en1,
    input  [4:0]  st_dispatch_rob_idx1,
    input  [63:0] st_dispatch_data1,
    input         st_dispatch_data_ready1,
    input  [6:0]  st_dispatch_data_tag1,
    output        st_full,
    output        st_almost_full,

    // --- Address from L/S compute unit ---
    input         ld_addr_valid,
    input  [4:0]  ld_addr_rob_idx,
    input  [63:0] ld_addr_value,

    input         st_addr_valid,
    input  [4:0]  st_addr_rob_idx,
    input  [63:0] st_addr_value,
    input  [63:0] st_addr_data,           // store data delivered alongside addr
    input         st_addr_data_valid,     // 1 if data accompanies addr

    // --- CDB snoop (store data capture) ---
    input         cdb_valid0,
    input  [6:0]  cdb_tag0,
    input  [63:0] cdb_value0,
    input         cdb_valid1,
    input  [6:0]  cdb_tag1,
    input  [63:0] cdb_value1,

    // --- Memory read port (directly wired to memory combinational read) ---
    output reg [63:0] mem_read_addr,
    output reg        mem_read_en,
    input      [63:0] mem_read_data,

    // --- Memory write port (committed stores) ---
    output reg        mem_write_en,
    output reg [63:0] mem_write_addr,
    output reg [63:0] mem_write_data,

    // --- Store commit from ROB ---
    input         store_commit_en,
    input  [4:0]  store_commit_rob_idx,

    // --- Load result (to CDB) ---
    output reg        load_result_valid,
    output reg [6:0]  load_result_dest_tag,
    output reg [4:0]  load_result_rob_idx,
    output reg [63:0] load_result_data,

    // --- Store complete (to CDB / ROB) ---
    output reg        store_complete_valid,
    output reg [4:0]  store_complete_rob_idx,
    output reg [63:0] store_complete_addr,
    output reg [63:0] store_complete_data
);

    localparam Q_SIZE = 8;

    // ================================================================
    // Load queue storage
    // ================================================================
    reg [Q_SIZE-1:0] lq_valid;
    reg [Q_SIZE-1:0] lq_addr_ready;

    reg [4:0]  lq_rob_idx  [0:Q_SIZE-1];
    reg [6:0]  lq_dest_tag [0:Q_SIZE-1];
    reg [63:0] lq_addr     [0:Q_SIZE-1];

    // ================================================================
    // Store queue storage
    // ================================================================
    reg [Q_SIZE-1:0] sq_valid;
    reg [Q_SIZE-1:0] sq_addr_ready;
    reg [Q_SIZE-1:0] sq_data_ready;
    reg [Q_SIZE-1:0] sq_committed;
    reg [Q_SIZE-1:0] sq_complete;          // CDB broadcast done

    reg [4:0]  sq_rob_idx  [0:Q_SIZE-1];
    reg [63:0] sq_addr     [0:Q_SIZE-1];
    reg [63:0] sq_data     [0:Q_SIZE-1];
    reg [6:0]  sq_data_tag [0:Q_SIZE-1];

    // ================================================================
    // Free-slot search (first-fit, dual)
    // ================================================================
    reg [2:0] lq_free_slot0, lq_free_slot1;
    reg       lq_has_free0,  lq_has_free1;
    reg [2:0] sq_free_slot0, sq_free_slot1;
    reg       sq_has_free0,  sq_has_free1;

    integer fi;
    always @(*) begin
        lq_has_free0 = 0; lq_free_slot0 = 0;
        lq_has_free1 = 0; lq_free_slot1 = 0;
        for (fi = 0; fi < Q_SIZE; fi = fi + 1)
            if (!lq_valid[fi]) begin
                if (!lq_has_free0) begin
                    lq_has_free0  = 1;
                    lq_free_slot0 = fi[2:0];
                end else if (!lq_has_free1) begin
                    lq_has_free1  = 1;
                    lq_free_slot1 = fi[2:0];
                end
            end

        sq_has_free0 = 0; sq_free_slot0 = 0;
        sq_has_free1 = 0; sq_free_slot1 = 0;
        for (fi = 0; fi < Q_SIZE; fi = fi + 1)
            if (!sq_valid[fi]) begin
                if (!sq_has_free0) begin
                    sq_has_free0  = 1;
                    sq_free_slot0 = fi[2:0];
                end else if (!sq_has_free1) begin
                    sq_has_free1  = 1;
                    sq_free_slot1 = fi[2:0];
                end
            end
    end

    assign ld_full        = ~lq_has_free0;
    assign ld_almost_full = lq_has_free0 && !lq_has_free1;
    assign st_full        = ~sq_has_free0;
    assign st_almost_full = sq_has_free0 && !sq_has_free1;

    // ================================================================
    // Load execution — select oldest ready load
    // ================================================================
    reg [2:0] ld_sel;
    reg       ld_sel_valid;
    reg [4:0] ld_sel_age;

    integer li;
    reg [4:0] ld_age_i;
    always @(*) begin
        ld_sel       = 0;
        ld_sel_valid = 0;
        ld_sel_age   = 5'h1F;
        for (li = 0; li < Q_SIZE; li = li + 1) begin
            if (lq_valid[li] && lq_addr_ready[li]) begin
                ld_age_i = (lq_rob_idx[li] - rob_head_idx) & 5'h1F;
                if (!ld_sel_valid || ld_age_i < ld_sel_age) begin
                    ld_sel       = li[2:0];
                    ld_sel_valid = 1;
                    ld_sel_age   = ld_age_i;
                end
            end
        end
    end

    // ================================================================
    // Store-to-load forwarding for selected load
    // ================================================================
    reg       fwd_match;
    reg [4:0] fwd_best_age;
    reg       fwd_data_avail;     // youngest match has data
    reg [63:0] fwd_data;
    reg       fwd_must_wait;

    integer si;
    reg [4:0] sq_age_i;
    always @(*) begin
        fwd_match      = 0;
        fwd_best_age   = 0;
        fwd_data_avail = 0;
        fwd_data       = 64'b0;
        fwd_must_wait  = 0;

        if (ld_sel_valid) begin
            for (si = 0; si < Q_SIZE; si = si + 1) begin
                if (sq_valid[si] && sq_addr_ready[si] &&
                    sq_addr[si] == lq_addr[ld_sel]) begin
                    sq_age_i = (sq_rob_idx[si] - rob_head_idx) & 5'h1F;
                    if (sq_age_i < ld_sel_age) begin          // store older than load
                        if (!fwd_match || sq_age_i > fwd_best_age) begin
                            fwd_match    = 1;
                            fwd_best_age = sq_age_i;
                            fwd_data_avail = sq_data_ready[si];
                            fwd_data       = sq_data[si];
                        end
                    end
                end
            end

            if (fwd_match && !fwd_data_avail)
                fwd_must_wait = 1;
        end
    end

    wire ld_can_execute = ld_sel_valid && !fwd_must_wait;
    wire ld_use_fwd     = fwd_match && fwd_data_avail;

    // Memory read address (combinational — memory responds same cycle)
    always @(*) begin
        mem_read_en   = 0;
        mem_read_addr = 64'b0;
        if (ld_can_execute && !ld_use_fwd) begin
            mem_read_en   = 1;
            mem_read_addr = lq_addr[ld_sel];
        end
    end

    // ================================================================
    // Store complete detection — oldest newly-complete store
    // ================================================================
    reg [2:0] sc_sel;
    reg       sc_found;
    reg [4:0] sc_age;

    integer sci;
    reg [4:0] sc_age_i;
    always @(*) begin
        sc_sel   = 0;
        sc_found = 0;
        sc_age   = 5'h1F;
        for (sci = 0; sci < Q_SIZE; sci = sci + 1) begin
            if (sq_valid[sci] && sq_addr_ready[sci] &&
                sq_data_ready[sci] && !sq_complete[sci]) begin
                sc_age_i = (sq_rob_idx[sci] - rob_head_idx) & 5'h1F;
                if (!sc_found || sc_age_i < sc_age) begin
                    sc_sel   = sci[2:0];
                    sc_found = 1;
                    sc_age   = sc_age_i;
                end
            end
        end
    end

    // ================================================================
    // Committed store → memory write (combinational output)
    // ================================================================
    reg [2:0] sw_sel;
    reg       sw_found;
    reg [4:0] sw_age;

    integer swi;
    reg [4:0] sw_age_i;
    always @(*) begin
        sw_sel   = 0;
        sw_found = 0;
        sw_age   = 5'h1F;
        mem_write_en   = 0;
        mem_write_addr = 64'b0;
        mem_write_data = 64'b0;
        for (swi = 0; swi < Q_SIZE; swi = swi + 1) begin
            if (sq_valid[swi] && sq_committed[swi]) begin
                sw_age_i = (sq_rob_idx[swi] - rob_head_idx) & 5'h1F;
                if (!sw_found || sw_age_i < sw_age) begin
                    sw_sel   = swi[2:0];
                    sw_found = 1;
                    sw_age   = sw_age_i;
                end
            end
        end
        if (sw_found) begin
            mem_write_en   = 1;
            mem_write_addr = sq_addr[sw_sel];
            mem_write_data = sq_data[sw_sel];
        end
    end

    // ================================================================
    // Flush age threshold
    // ================================================================
    wire [4:0] flush_age = (flush_rob_idx - rob_head_idx) & 5'h1F;

    // ================================================================
    // Sequential logic
    // ================================================================
    integer i;
    reg [4:0] entry_age;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            lq_valid      <= 0;
            lq_addr_ready <= 0;
            sq_valid      <= 0;
            sq_addr_ready <= 0;
            sq_data_ready <= 0;
            sq_committed  <= 0;
            sq_complete   <= 0;
            load_result_valid    <= 0;
            store_complete_valid <= 0;
        end else begin

            // --- CDB snoop for store data (always active) ---
            for (i = 0; i < Q_SIZE; i = i + 1) begin
                if (sq_valid[i] && !sq_data_ready[i]) begin
                    if (cdb_valid0 && cdb_tag0 == sq_data_tag[i]) begin
                        sq_data[i]       <= cdb_value0;
                        sq_data_ready[i] <= 1'b1;
                    end else if (cdb_valid1 && cdb_tag1 == sq_data_tag[i]) begin
                        sq_data[i]       <= cdb_value1;
                        sq_data_ready[i] <= 1'b1;
                    end
                end
            end

            // --- Committed-store memory write: clear entry (always active) ---
            if (sw_found && !flush_en) begin
                sq_valid[sw_sel]      <= 1'b0;
                sq_addr_ready[sw_sel] <= 1'b0;
                sq_data_ready[sw_sel] <= 1'b0;
                sq_committed[sw_sel]  <= 1'b0;
                sq_complete[sw_sel]   <= 1'b0;
            end

            // ==========================================================
            if (flush_en) begin
            // ==========================================================
                load_result_valid    <= 1'b0;
                store_complete_valid <= 1'b0;

                for (i = 0; i < Q_SIZE; i = i + 1) begin
                    if (lq_valid[i]) begin
                        entry_age = (lq_rob_idx[i] - rob_head_idx) & 5'h1F;
                        if (entry_age > flush_age) begin
                            lq_valid[i]      <= 1'b0;
                            lq_addr_ready[i] <= 1'b0;
                        end
                    end
                    if (sq_valid[i] && !sq_committed[i]) begin
                        entry_age = (sq_rob_idx[i] - rob_head_idx) & 5'h1F;
                        if (entry_age > flush_age) begin
                            sq_valid[i]      <= 1'b0;
                            sq_addr_ready[i] <= 1'b0;
                            sq_data_ready[i] <= 1'b0;
                            sq_committed[i]  <= 1'b0;
                            sq_complete[i]   <= 1'b0;
                        end
                    end
                end

            // ==========================================================
            end else begin  // normal operation
            // ==========================================================

                // --- Defaults ---
                load_result_valid    <= 1'b0;
                store_complete_valid <= 1'b0;

                // --- Load execution result (registered) ---
                if (ld_can_execute) begin
                    load_result_valid    <= 1'b1;
                    load_result_dest_tag <= lq_dest_tag[ld_sel];
                    load_result_rob_idx  <= lq_rob_idx[ld_sel];
                    load_result_data     <= ld_use_fwd ? fwd_data : mem_read_data;
                    lq_valid[ld_sel]      <= 1'b0;
                    lq_addr_ready[ld_sel] <= 1'b0;
                end

                // --- Store complete broadcast (registered) ---
                if (sc_found) begin
                    store_complete_valid    <= 1'b1;
                    store_complete_rob_idx  <= sq_rob_idx[sc_sel];
                    store_complete_addr     <= sq_addr[sc_sel];
                    store_complete_data     <= sq_data[sc_sel];
                    sq_complete[sc_sel]     <= 1'b1;
                end

                // --- Store commit notification ---
                if (store_commit_en) begin
                    for (i = 0; i < Q_SIZE; i = i + 1)
                        if (sq_valid[i] && sq_rob_idx[i] == store_commit_rob_idx)
                            sq_committed[i] <= 1'b1;
                end

                // --- Load dispatch (dual) ---
                if (ld_dispatch_en0 && lq_has_free0) begin
                    lq_valid[lq_free_slot0]      <= 1'b1;
                    lq_addr_ready[lq_free_slot0]  <= 1'b0;
                    lq_rob_idx[lq_free_slot0]    <= ld_dispatch_rob_idx0;
                    lq_dest_tag[lq_free_slot0]   <= ld_dispatch_dest_tag0;
                end
                if (ld_dispatch_en1 && lq_has_free1) begin
                    lq_valid[lq_free_slot1]      <= 1'b1;
                    lq_addr_ready[lq_free_slot1]  <= 1'b0;
                    lq_rob_idx[lq_free_slot1]    <= ld_dispatch_rob_idx1;
                    lq_dest_tag[lq_free_slot1]   <= ld_dispatch_dest_tag1;
                end

                // --- Store dispatch (dual) ---
                if (st_dispatch_en0 && sq_has_free0) begin
                    sq_valid[sq_free_slot0]      <= 1'b1;
                    sq_addr_ready[sq_free_slot0]  <= 1'b0;
                    sq_data_ready[sq_free_slot0]  <= st_dispatch_data_ready0;
                    sq_committed[sq_free_slot0]   <= 1'b0;
                    sq_complete[sq_free_slot0]    <= 1'b0;
                    sq_rob_idx[sq_free_slot0]    <= st_dispatch_rob_idx0;
                    sq_data[sq_free_slot0]       <= st_dispatch_data0;
                    sq_data_tag[sq_free_slot0]   <= st_dispatch_data_tag0;
                end
                if (st_dispatch_en1 && sq_has_free1) begin
                    sq_valid[sq_free_slot1]      <= 1'b1;
                    sq_addr_ready[sq_free_slot1]  <= 1'b0;
                    sq_data_ready[sq_free_slot1]  <= st_dispatch_data_ready1;
                    sq_committed[sq_free_slot1]   <= 1'b0;
                    sq_complete[sq_free_slot1]    <= 1'b0;
                    sq_rob_idx[sq_free_slot1]    <= st_dispatch_rob_idx1;
                    sq_data[sq_free_slot1]       <= st_dispatch_data1;
                    sq_data_tag[sq_free_slot1]   <= st_dispatch_data_tag1;
                end

                // --- Load address arrival ---
                if (ld_addr_valid) begin
                    for (i = 0; i < Q_SIZE; i = i + 1)
                        if (lq_valid[i] && !lq_addr_ready[i] &&
                            lq_rob_idx[i] == ld_addr_rob_idx) begin
                            lq_addr[i]      <= ld_addr_value;
                            lq_addr_ready[i] <= 1'b1;
                        end
                end

                // --- Store address (+ optional data) arrival ---
                if (st_addr_valid) begin
                    for (i = 0; i < Q_SIZE; i = i + 1)
                        if (sq_valid[i] && !sq_addr_ready[i] &&
                            sq_rob_idx[i] == st_addr_rob_idx) begin
                            sq_addr[i]      <= st_addr_value;
                            sq_addr_ready[i] <= 1'b1;
                            if (st_addr_data_valid) begin
                                sq_data[i]      <= st_addr_data;
                                sq_data_ready[i] <= 1'b1;
                            end
                        end
                end

            end // normal operation
        end // !reset
    end

endmodule
