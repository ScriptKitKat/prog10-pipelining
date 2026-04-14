`include "reservation_station.sv"

module rs_tb;
    reg clk, reset;

    // Dispatch
    reg        dispatch_en;
    reg  [4:0] dispatch_opcode;
    reg [63:0] dispatch_src1_value;
    reg  [6:0] dispatch_src1_tag;
    reg        dispatch_src1_ready;
    reg [63:0] dispatch_src2_value;
    reg  [6:0] dispatch_src2_tag;
    reg        dispatch_src2_ready;
    reg  [6:0] dispatch_dest_tag;
    reg  [4:0] dispatch_rob_idx;
    reg [63:0] dispatch_imm;
    reg [63:0] dispatch_pc;
    wire       full;

    // CDB
    reg        cdb_valid0, cdb_valid1;
    reg  [6:0] cdb_tag0, cdb_tag1;
    reg [63:0] cdb_value0, cdb_value1;

    // Issue
    wire       issue_valid;
    wire [4:0] issue_opcode;
    wire [63:0] issue_src1_value, issue_src2_value;
    wire [6:0] issue_dest_tag;
    wire [4:0] issue_rob_idx;
    wire [63:0] issue_imm, issue_pc;

    // Flush
    reg        flush_en;
    reg  [4:0] flush_rob_idx;
    reg  [4:0] rob_head_idx;

    reservation_station #(.NUM_ENTRIES(4)) dut (
        .clk(clk), .reset(reset),
        .dispatch_en(dispatch_en), .dispatch_opcode(dispatch_opcode),
        .dispatch_src1_value(dispatch_src1_value),
        .dispatch_src1_tag(dispatch_src1_tag),
        .dispatch_src1_ready(dispatch_src1_ready),
        .dispatch_src2_value(dispatch_src2_value),
        .dispatch_src2_tag(dispatch_src2_tag),
        .dispatch_src2_ready(dispatch_src2_ready),
        .dispatch_dest_tag(dispatch_dest_tag),
        .dispatch_rob_idx(dispatch_rob_idx),
        .dispatch_imm(dispatch_imm), .dispatch_pc(dispatch_pc),
        .full(full),
        .cdb_valid0(cdb_valid0), .cdb_tag0(cdb_tag0), .cdb_value0(cdb_value0),
        .cdb_valid1(cdb_valid1), .cdb_tag1(cdb_tag1), .cdb_value1(cdb_value1),
        .issue_valid(issue_valid), .issue_opcode(issue_opcode),
        .issue_src1_value(issue_src1_value), .issue_src2_value(issue_src2_value),
        .issue_dest_tag(issue_dest_tag), .issue_rob_idx(issue_rob_idx),
        .issue_imm(issue_imm), .issue_pc(issue_pc),
        .flush_en(flush_en), .flush_rob_idx(flush_rob_idx),
        .rob_head_idx(rob_head_idx)
    );

    always #5 clk = ~clk;

    integer pass_count, fail_count;

    task check(input [63:0] got, input [63:0] expected, input [255:0] name);
        if (got === expected) begin
            $display("PASS %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL %0s: got %0d (0x%0h), expected %0d (0x%0h)", name, got, got, expected, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task clear_inputs;
        begin
            dispatch_en = 0; dispatch_opcode = 0;
            dispatch_src1_value = 0; dispatch_src1_tag = 0; dispatch_src1_ready = 0;
            dispatch_src2_value = 0; dispatch_src2_tag = 0; dispatch_src2_ready = 0;
            dispatch_dest_tag = 0; dispatch_rob_idx = 0;
            dispatch_imm = 0; dispatch_pc = 0;
            cdb_valid0 = 0; cdb_tag0 = 0; cdb_value0 = 0;
            cdb_valid1 = 0; cdb_tag1 = 0; cdb_value1 = 0;
            flush_en = 0; flush_rob_idx = 0;
        end
    endtask

    initial begin
        $dumpfile("rs_tb.vcd");
        $dumpvars(0, rs_tb);

        clk = 0; reset = 1;
        pass_count = 0; fail_count = 0;
        rob_head_idx = 0;
        clear_inputs;
        #10 reset = 0;

        // ============================================================
        // Test 1: Reset state
        // ============================================================
        $display("\n--- Test 1: Reset state ---");
        #1;
        check({63'd0, full},        64'd0, "not full after reset");
        check({63'd0, issue_valid}, 64'd0, "no issue after reset");

        // ============================================================
        // Test 2: Dispatch ready entry -> issues next cycle
        // ============================================================
        $display("\n--- Test 2: Dispatch ready entry, issue next cycle ---");

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h18;        // ADD
        dispatch_src1_value = 64'd100;
        dispatch_src1_tag = 7'd0; dispatch_src1_ready = 1;
        dispatch_src2_value = 64'd200;
        dispatch_src2_tag = 7'd0; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd32;
        dispatch_rob_idx = 5'd0;
        dispatch_imm = 64'd0;
        dispatch_pc = 64'h1000;

        @(negedge clk);
        clear_inputs;
        #1;

        check({63'd0, issue_valid},  64'd1,     "issue_valid after dispatch ready");
        check({59'd0, issue_opcode}, {59'd0, 5'h18}, "issue opcode = ADD");
        check(issue_src1_value,      64'd100,   "issue src1 = 100");
        check(issue_src2_value,      64'd200,   "issue src2 = 200");
        check({57'd0, issue_dest_tag}, {57'd0, 7'd32}, "issue dest = p32");
        check({59'd0, issue_rob_idx},  {59'd0, 5'd0},  "issue rob_idx = 0");
        check(issue_pc,              64'h1000,  "issue pc = 0x1000");

        // Let issue clear the entry
        @(negedge clk);
        #1;
        check({63'd0, issue_valid}, 64'd0, "no issue after entry cleared");
        check({63'd0, full},        64'd0, "not full after issue");

        // ============================================================
        // Test 3: CDB wakeup for src1
        // ============================================================
        $display("\n--- Test 3: CDB wakeup src1 ---");

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h1a;        // SUB
        dispatch_src1_value = 64'd0;
        dispatch_src1_tag = 7'd42; dispatch_src1_ready = 0; // waiting for p42
        dispatch_src2_value = 64'd50;
        dispatch_src2_tag = 7'd0; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd33;
        dispatch_rob_idx = 5'd1;
        dispatch_imm = 64'd0;
        dispatch_pc = 64'h1004;
        @(negedge clk);
        clear_inputs;
        #1;
        // src1 not ready -> no issue
        check({63'd0, issue_valid}, 64'd0, "no issue: src1 not ready");

        // CDB broadcast tag 42 with value 999
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd42; cdb_value0 = 64'd999;
        @(negedge clk);
        clear_inputs;
        #1;

        // src1 woken up, both ready -> should issue
        check({63'd0, issue_valid},  64'd1,   "issue after src1 wakeup");
        check(issue_src1_value,      64'd999, "issue src1 = CDB value 999");
        check(issue_src2_value,      64'd50,  "issue src2 unchanged = 50");
        check({59'd0, issue_opcode}, {59'd0, 5'h1a}, "issue opcode = SUB");

        @(negedge clk); // clear issued entry
        clear_inputs;

        // ============================================================
        // Test 4: CDB wakeup for src2 via bus 1
        // ============================================================
        $display("\n--- Test 4: CDB wakeup src2 via bus 1 ---");

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h00;        // AND
        dispatch_src1_value = 64'hFF;
        dispatch_src1_tag = 7'd0; dispatch_src1_ready = 1;
        dispatch_src2_value = 64'd0;
        dispatch_src2_tag = 7'd55; dispatch_src2_ready = 0; // waiting for p55
        dispatch_dest_tag = 7'd34;
        dispatch_rob_idx = 5'd2;
        dispatch_imm = 64'd0;
        dispatch_pc = 64'h1008;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd0, "no issue: src2 not ready");

        // CDB bus 1 broadcasts tag 55
        @(negedge clk);
        cdb_valid1 = 1; cdb_tag1 = 7'd55; cdb_value1 = 64'h0F;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd1,    "issue after src2 wakeup");
        check(issue_src2_value,     64'h0F,   "issue src2 = CDB bus1 value");

        @(negedge clk); // clear
        clear_inputs;

        // ============================================================
        // Test 5: Both sources not ready, sequential wakeup
        // ============================================================
        $display("\n--- Test 5: Sequential wakeup (src1 then src2) ---");

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h02;        // XOR
        dispatch_src1_value = 0;
        dispatch_src1_tag = 7'd10; dispatch_src1_ready = 0;
        dispatch_src2_value = 0;
        dispatch_src2_tag = 7'd20; dispatch_src2_ready = 0;
        dispatch_dest_tag = 7'd35;
        dispatch_rob_idx = 5'd3;
        dispatch_imm = 0;
        dispatch_pc = 64'h100C;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd0, "no issue: both srcs not ready");

        // Wakeup src1 (tag 10)
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd10; cdb_value0 = 64'hA0;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd0, "no issue: only src1 woken");

        // Wakeup src2 (tag 20)
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd20; cdb_value0 = 64'hB0;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd1,   "issue after both woken");
        check(issue_src1_value,     64'hA0,  "src1 = 0xA0");
        check(issue_src2_value,     64'hB0,  "src2 = 0xB0");

        @(negedge clk); // clear
        clear_inputs;

        // ============================================================
        // Test 6: Oldest-first issue priority
        // ============================================================
        $display("\n--- Test 6: Oldest-first issue priority ---");
        rob_head_idx = 5'd0;

        // Dispatch entry A: rob_idx=5, NOT ready (waiting for tag 44)
        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h18;        // ADD
        dispatch_src1_value = 0;
        dispatch_src1_tag = 7'd44; dispatch_src1_ready = 0;
        dispatch_src2_value = 64'd2; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd36;
        dispatch_rob_idx = 5'd5;
        dispatch_pc = 64'h2000;
        @(negedge clk);
        clear_inputs;

        // Dispatch entry B: rob_idx=3, NOT ready (same tag 44)
        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h1a;        // SUB
        dispatch_src1_value = 0;
        dispatch_src1_tag = 7'd44; dispatch_src1_ready = 0;
        dispatch_src2_value = 64'd20; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd37;
        dispatch_rob_idx = 5'd3;
        dispatch_pc = 64'h2004;
        @(negedge clk);
        clear_inputs;
        #1;
        // Both present but neither ready
        check({63'd0, issue_valid}, 64'd0, "oldest-first: no issue yet");

        // Wakeup both via CDB (tag 44)
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd44; cdb_value0 = 64'd10;
        @(negedge clk);
        clear_inputs;
        #1;

        // Both ready; entry B (rob_idx=3, age=3) should issue first
        check({63'd0, issue_valid},    64'd1,          "oldest-first: issue valid");
        check({59'd0, issue_rob_idx},  {59'd0, 5'd3},  "oldest-first: rob_idx=3 (B) first");
        check({59'd0, issue_opcode},   {59'd0, 5'h1a}, "oldest-first: opcode=SUB (B)");

        @(negedge clk); // posedge clears B, A auto-selected
        #1;

        // Now entry A (rob_idx=5) should issue
        check({63'd0, issue_valid},    64'd1,          "oldest-first: A issues second");
        check({59'd0, issue_rob_idx},  {59'd0, 5'd5},  "oldest-first: rob_idx=5 (A)");
        check({59'd0, issue_opcode},   {59'd0, 5'h18}, "oldest-first: opcode=ADD (A)");

        @(negedge clk); // clear A
        #1;
        check({63'd0, issue_valid}, 64'd0, "empty after both issued");

        // ============================================================
        // Test 7: Full condition
        // ============================================================
        $display("\n--- Test 7: Full condition ---");

        // Fill all 4 entries with non-ready instructions
        begin : fill_rs
            integer j;
            for (j = 0; j < 4; j = j + 1) begin
                @(negedge clk);
                dispatch_en = 1;
                dispatch_opcode = 5'h18;
                dispatch_src1_tag = 7'd60; dispatch_src1_ready = 0;
                dispatch_src2_tag = 7'd61; dispatch_src2_ready = 0;
                dispatch_dest_tag = j[6:0] + 7'd70;
                dispatch_rob_idx = j[4:0] + 5'd10;
                dispatch_pc = j * 4;
            end
        end
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, full}, 64'd1, "full after 4 dispatches");
        check({63'd0, issue_valid}, 64'd0, "no issue (all waiting)");

        // Wakeup all sources -> one issues, freeing a slot
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd60; cdb_value0 = 64'd7;
        cdb_valid1 = 1; cdb_tag1 = 7'd61; cdb_value1 = 64'd8;
        @(negedge clk);
        clear_inputs;
        #1;

        // All 4 are now ready; oldest (rob_idx=10, age=10) issues
        check({63'd0, issue_valid}, 64'd1, "issue after bulk wakeup");
        check({59'd0, issue_rob_idx}, {59'd0, 5'd10}, "oldest rob_idx=10 issued");

        // Each @(negedge clk) advances one cycle: posedge clears issued,
        // combinational selects next oldest. Check both full and rob_idx together.
        @(negedge clk); #1;
        check({63'd0, full}, 64'd0, "not full after issue cleared one");
        check({59'd0, issue_rob_idx}, {59'd0, 5'd11}, "next oldest rob_idx=11");
        @(negedge clk); #1;
        check({59'd0, issue_rob_idx}, {59'd0, 5'd12}, "next rob_idx=12");
        @(negedge clk); #1;
        check({59'd0, issue_rob_idx}, {59'd0, 5'd13}, "next rob_idx=13");
        @(negedge clk); #1;
        check({63'd0, issue_valid}, 64'd0, "empty after draining all");

        // ============================================================
        // Test 8: Flush
        // ============================================================
        $display("\n--- Test 8: Flush ---");
        rob_head_idx = 5'd0;

        // Dispatch 3 entries with rob_idx 2, 5, 8
        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h18;
        dispatch_src1_tag = 7'd90; dispatch_src1_ready = 0;
        dispatch_src2_tag = 7'd91; dispatch_src2_ready = 0;
        dispatch_dest_tag = 7'd80;
        dispatch_rob_idx = 5'd2;
        dispatch_pc = 64'h3000;
        @(negedge clk);
        clear_inputs;

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h1a;
        dispatch_src1_tag = 7'd90; dispatch_src1_ready = 0;
        dispatch_src2_tag = 7'd91; dispatch_src2_ready = 0;
        dispatch_dest_tag = 7'd81;
        dispatch_rob_idx = 5'd5;
        dispatch_pc = 64'h3004;
        @(negedge clk);
        clear_inputs;

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h1c;
        dispatch_src1_tag = 7'd90; dispatch_src1_ready = 0;
        dispatch_src2_tag = 7'd91; dispatch_src2_ready = 0;
        dispatch_dest_tag = 7'd82;
        dispatch_rob_idx = 5'd8;
        dispatch_pc = 64'h3008;
        @(negedge clk);
        clear_inputs;
        #1;
        // All 3 dispatched, none ready
        check({63'd0, issue_valid}, 64'd0, "no issue before flush");

        // Flush with flush_rob_idx=4 (branch age=4).
        // Entry rob_idx=2 (age=2 < 4) survives.
        // Entry rob_idx=5 (age=5 > 4) flushed.
        // Entry rob_idx=8 (age=8 > 4) flushed.
        @(negedge clk);
        flush_en = 1; flush_rob_idx = 5'd4;
        @(negedge clk);
        flush_en = 0;
        #1;

        // Verify exactly 1 entry survived (packed vector popcount)
        check({60'd0, dut.entry_valid}, 64'd1, "flush: only 1 bit set in entry_valid");

        // Wakeup the surviving entry and verify it issues
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd90; cdb_value0 = 64'hF1;
        cdb_valid1 = 1; cdb_tag1 = 7'd91; cdb_value1 = 64'hF2;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid},   64'd1,          "surviving entry issues after wakeup");
        check({59'd0, issue_rob_idx}, {59'd0, 5'd2},  "survivor is rob_idx=2");
        check(issue_pc,              64'h3000,        "survivor pc = 0x3000");

        @(negedge clk);
        clear_inputs;

        // ============================================================
        // Test 9: CDB non-matching tag is ignored
        // ============================================================
        $display("\n--- Test 9: CDB non-matching tag ignored ---");

        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h01;        // OR
        dispatch_src1_tag = 7'd99; dispatch_src1_ready = 0;
        dispatch_src2_value = 64'd5;    dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd50;
        dispatch_rob_idx = 5'd0;
        dispatch_pc = 64'h4000;
        @(negedge clk);
        clear_inputs;

        // CDB broadcasts tag 77 (doesn't match 99)
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd77; cdb_value0 = 64'hBAD;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd0, "no issue: CDB tag mismatch");

        // Now broadcast the right tag
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd99; cdb_value0 = 64'hCAFE;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd1,     "issue after correct CDB tag");
        check(issue_src1_value,     64'hCAFE,  "src1 = correct CDB value");

        @(negedge clk);
        clear_inputs;

        // ============================================================
        // Test 10: Oldest-first with ROB wrap-around
        // ============================================================
        $display("\n--- Test 10: Oldest-first with ROB index wrapping ---");
        rob_head_idx = 5'd30;

        // Entry A: rob_idx=31, NOT ready (waiting for tag 88)
        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h18;
        dispatch_src1_value = 0;
        dispatch_src1_tag = 7'd88; dispatch_src1_ready = 0;
        dispatch_src2_value = 64'd2; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd40;
        dispatch_rob_idx = 5'd31;
        dispatch_pc = 64'h5000;
        @(negedge clk);
        clear_inputs;

        // Entry B: rob_idx=2, NOT ready (same tag 88)
        @(negedge clk);
        dispatch_en = 1;
        dispatch_opcode = 5'h1a;
        dispatch_src1_value = 0;
        dispatch_src1_tag = 7'd88; dispatch_src1_ready = 0;
        dispatch_src2_value = 64'd4; dispatch_src2_ready = 1;
        dispatch_dest_tag = 7'd41;
        dispatch_rob_idx = 5'd2;
        dispatch_pc = 64'h5004;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, issue_valid}, 64'd0, "wrap: no issue yet (both waiting)");

        // Wakeup both via CDB (tag 88)
        @(negedge clk);
        cdb_valid0 = 1; cdb_tag0 = 7'd88; cdb_value0 = 64'd1;
        @(negedge clk);
        clear_inputs;
        #1;

        // rob_idx=31 is older (age=1 < age=4), should issue first
        check({63'd0, issue_valid},   64'd1,          "wrap: issue valid");
        check({59'd0, issue_rob_idx}, {59'd0, 5'd31}, "wrap: rob_idx=31 (age=1) first");

        @(negedge clk); #1;
        check({59'd0, issue_rob_idx}, {59'd0, 5'd2},  "wrap: rob_idx=2 (age=4) second");

        @(negedge clk); // drain
        clear_inputs;
        rob_head_idx = 5'd0;

        // ============================================================
        $display("\n--- Results: %0d passed, %0d failed ---", pass_count, fail_count);
        if (fail_count > 0)
            $display("*** SOME TESTS FAILED ***");
        else
            $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
