`include "rob.sv"

module rob_tb;
    reg clk, reset;

    // Allocate
    reg        alloc_en0, alloc_en1;
    reg  [2:0] alloc_type0, alloc_type1;
    reg  [4:0] alloc_arch_rd0, alloc_arch_rd1;
    reg  [6:0] alloc_old_phys0, alloc_old_phys1;
    reg  [6:0] alloc_new_phys0, alloc_new_phys1;
    reg        alloc_has_dest0, alloc_has_dest1;
    reg        alloc_br_pred0, alloc_br_pred1;
    reg [63:0] alloc_pc0, alloc_pc1;
    wire [4:0] alloc_idx0, alloc_idx1;
    wire       full;

    // Complete (CDB)
    reg        cdb_valid0, cdb_valid1;
    reg  [4:0] cdb_rob_idx0, cdb_rob_idx1;
    reg [63:0] cdb_value0, cdb_value1;
    reg [63:0] cdb_store_addr0, cdb_store_addr1;
    reg        cdb_br_actual0, cdb_br_actual1;
    reg        cdb_mispredict0, cdb_mispredict1;

    // Commit
    wire       commit_en0, commit_en1;
    wire [2:0] commit_type0, commit_type1;
    wire [4:0] commit_arch_rd0, commit_arch_rd1;
    wire [6:0] commit_old_phys0, commit_old_phys1;
    wire [6:0] commit_new_phys0, commit_new_phys1;
    wire [63:0] commit_store_addr0, commit_store_addr1;
    wire [63:0] commit_store_data0, commit_store_data1;
    wire       hlt;

    // Flush
    reg        flush_en;
    reg  [4:0] flush_rob_idx;
    wire [63:0] flush_redirect_pc;
    wire       flush_active;
    wire       flush_free_en0, flush_free_en1;
    wire [6:0] flush_free_reg0, flush_free_reg1;

    // Status
    wire       empty;

    rob dut (
        .clk(clk), .reset(reset),
        .alloc_en0(alloc_en0), .alloc_type0(alloc_type0),
        .alloc_arch_rd0(alloc_arch_rd0), .alloc_old_phys0(alloc_old_phys0),
        .alloc_new_phys0(alloc_new_phys0), .alloc_has_dest0(alloc_has_dest0),
        .alloc_br_pred0(alloc_br_pred0), .alloc_pc0(alloc_pc0),
        .alloc_en1(alloc_en1), .alloc_type1(alloc_type1),
        .alloc_arch_rd1(alloc_arch_rd1), .alloc_old_phys1(alloc_old_phys1),
        .alloc_new_phys1(alloc_new_phys1), .alloc_has_dest1(alloc_has_dest1),
        .alloc_br_pred1(alloc_br_pred1), .alloc_pc1(alloc_pc1),
        .alloc_idx0(alloc_idx0), .alloc_idx1(alloc_idx1), .full(full),
        .cdb_valid0(cdb_valid0), .cdb_rob_idx0(cdb_rob_idx0),
        .cdb_value0(cdb_value0), .cdb_store_addr0(cdb_store_addr0),
        .cdb_br_actual0(cdb_br_actual0), .cdb_mispredict0(cdb_mispredict0),
        .cdb_valid1(cdb_valid1), .cdb_rob_idx1(cdb_rob_idx1),
        .cdb_value1(cdb_value1), .cdb_store_addr1(cdb_store_addr1),
        .cdb_br_actual1(cdb_br_actual1), .cdb_mispredict1(cdb_mispredict1),
        .commit_en0(commit_en0), .commit_type0(commit_type0),
        .commit_arch_rd0(commit_arch_rd0), .commit_old_phys0(commit_old_phys0),
        .commit_new_phys0(commit_new_phys0),
        .commit_store_addr0(commit_store_addr0), .commit_store_data0(commit_store_data0),
        .commit_en1(commit_en1), .commit_type1(commit_type1),
        .commit_arch_rd1(commit_arch_rd1), .commit_old_phys1(commit_old_phys1),
        .commit_new_phys1(commit_new_phys1),
        .commit_store_addr1(commit_store_addr1), .commit_store_data1(commit_store_data1),
        .hlt(hlt),
        .flush_en(flush_en), .flush_rob_idx(flush_rob_idx),
        .flush_redirect_pc(flush_redirect_pc),
        .flush_active(flush_active),
        .flush_free_en0(flush_free_en0), .flush_free_reg0(flush_free_reg0),
        .flush_free_en1(flush_free_en1), .flush_free_reg1(flush_free_reg1),
        .empty(empty)
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
            alloc_en0 = 0; alloc_en1 = 0;
            alloc_type0 = 0; alloc_type1 = 0;
            alloc_arch_rd0 = 0; alloc_arch_rd1 = 0;
            alloc_old_phys0 = 0; alloc_old_phys1 = 0;
            alloc_new_phys0 = 0; alloc_new_phys1 = 0;
            alloc_has_dest0 = 0; alloc_has_dest1 = 0;
            alloc_br_pred0 = 0; alloc_br_pred1 = 0;
            alloc_pc0 = 0; alloc_pc1 = 0;
            cdb_valid0 = 0; cdb_valid1 = 0;
            cdb_rob_idx0 = 0; cdb_rob_idx1 = 0;
            cdb_value0 = 0; cdb_value1 = 0;
            cdb_store_addr0 = 0; cdb_store_addr1 = 0;
            cdb_br_actual0 = 0; cdb_br_actual1 = 0;
            cdb_mispredict0 = 0; cdb_mispredict1 = 0;
            flush_en = 0; flush_rob_idx = 0;
        end
    endtask

    initial begin
        $dumpfile("rob_tb.vcd");
        $dumpvars(0, rob_tb);

        clk = 0; reset = 1;
        pass_count = 0; fail_count = 0;
        clear_inputs;

        #10 reset = 0;

        // ============================================================
        // Test 1: Reset state — empty, not full
        // ============================================================
        $display("\n--- Test 1: Reset state ---");
        #1;
        check({63'd0, empty}, 64'd1, "empty after reset");
        check({63'd0, full},  64'd0, "not full after reset");
        check({63'd0, hlt},   64'd0, "no halt after reset");
        check({59'd0, alloc_idx0}, 64'd0, "alloc_idx0 = 0");
        check({59'd0, alloc_idx1}, 64'd1, "alloc_idx1 = 1");

        // ============================================================
        // Test 2: Dual allocate, CDB complete, dual commit (ALU)
        // ============================================================
        $display("\n--- Test 2: Allocate -> Complete -> Commit (dual ALU) ---");

        // Allocate 2 ALU instructions
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd0; // ALU
        alloc_arch_rd0 = 5'd1; alloc_old_phys0 = 7'd1; alloc_new_phys0 = 7'd32;
        alloc_has_dest0 = 1; alloc_pc0 = 64'h100;

        alloc_en1 = 1; alloc_type1 = 3'd0; // ALU
        alloc_arch_rd1 = 5'd2; alloc_old_phys1 = 7'd2; alloc_new_phys1 = 7'd33;
        alloc_has_dest1 = 1; alloc_pc1 = 64'h104;

        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, empty}, 64'd0, "not empty after alloc");
        check({58'd0, dut.count}, 64'd2, "count = 2 after dual alloc");
        check({59'd0, alloc_idx0}, 64'd2, "next alloc_idx0 = 2");

        // Neither committed yet (not completed)
        check({63'd0, commit_en0}, 64'd0, "no commit before complete");

        // Complete both via CDB
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd0; cdb_value0 = 64'hAAAA;
        cdb_valid1 = 1; cdb_rob_idx1 = 5'd1; cdb_value1 = 64'hBBBB;
        @(negedge clk);
        clear_inputs;
        #1;

        // Now both should be committed (combinational commit sees completed bits)
        check({63'd0, commit_en0}, 64'd1, "commit_en0 after complete");
        check({63'd0, commit_en1}, 64'd1, "commit_en1 after complete");
        check({57'd0, commit_new_phys0}, {57'd0, 7'd32}, "commit new_phys0 = 32");
        check({57'd0, commit_old_phys0}, {57'd0, 7'd1},  "commit old_phys0 = 1");
        check({59'd0, commit_arch_rd0},  {59'd0, 5'd1},  "commit arch_rd0 = 1");
        check(commit_store_data0, 64'hAAAA, "commit value0 = 0xAAAA");
        check({57'd0, commit_new_phys1}, {57'd0, 7'd33}, "commit new_phys1 = 33");
        check({57'd0, commit_old_phys1}, {57'd0, 7'd2},  "commit old_phys1 = 2");
        check(commit_store_data1, 64'hBBBB, "commit value1 = 0xBBBB");

        // Let commit take effect (head advances)
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, empty}, 64'd1, "empty after dual commit");
        check({63'd0, commit_en0}, 64'd0, "no commit when empty");

        // ============================================================
        // Test 3: Store commit — only 1 instruction commits per cycle
        // ============================================================
        $display("\n--- Test 3: Store at head limits commit to 1 ---");

        // Allocate: STORE then ALU
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd3; // STORE
        alloc_arch_rd0 = 5'd0; alloc_old_phys0 = 7'd0; alloc_new_phys0 = 7'd0;
        alloc_has_dest0 = 0; alloc_pc0 = 64'h200;

        alloc_en1 = 1; alloc_type1 = 3'd0; // ALU
        alloc_arch_rd1 = 5'd3; alloc_old_phys1 = 7'd3; alloc_new_phys1 = 7'd34;
        alloc_has_dest1 = 1; alloc_pc1 = 64'h204;

        @(negedge clk);
        clear_inputs;

        // Complete both
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd2;
        cdb_value0 = 64'h42; cdb_store_addr0 = 64'h1000;
        cdb_valid1 = 1; cdb_rob_idx1 = 5'd3;
        cdb_value1 = 64'hCC;
        @(negedge clk);
        clear_inputs;
        #1;

        // Store at head: only commit_en0 should fire
        check({63'd0, commit_en0}, 64'd1, "store commits");
        check({61'd0, commit_type0}, 64'd3, "commit type0 = STORE");
        check(commit_store_addr0, 64'h1000, "store addr = 0x1000");
        check(commit_store_data0, 64'h42, "store data = 0x42");
        check({63'd0, commit_en1}, 64'd0, "no second commit after store");

        // Let store commit, then ALU should commit next cycle
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, commit_en0}, 64'd1, "ALU commits after store");
        check({61'd0, commit_type0}, 64'd0, "commit type0 = ALU");
        check(commit_store_data0, 64'hCC, "ALU value = 0xCC");
        check({63'd0, commit_en1}, 64'd0, "no second commit (only 1 entry left)");

        // Drain that commit
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, empty}, 64'd1, "empty after store+ALU commit");

        // ============================================================
        // Test 4: HALT handling
        // ============================================================
        $display("\n--- Test 4: HALT assertion ---");

        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd5; // HALT
        alloc_arch_rd0 = 0; alloc_old_phys0 = 0; alloc_new_phys0 = 0;
        alloc_has_dest0 = 0; alloc_pc0 = 64'h300;
        alloc_en1 = 0;
        @(negedge clk);
        clear_inputs;

        // Complete HALT
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd4; cdb_value0 = 0;
        @(negedge clk);
        clear_inputs;
        #1;

        check({63'd0, commit_en0}, 64'd1, "HALT commits");
        check({61'd0, commit_type0}, 64'd5, "commit type = HALT");
        // hlt is registered, so it will be set on the next posedge
        check({63'd0, hlt}, 64'd0, "hlt not set yet (registered)");

        @(negedge clk); // Let posedge happen, hlt gets latched
        clear_inputs;
        #1;
        check({63'd0, hlt}, 64'd1, "hlt asserted after HALT commit");

        // Reset for remaining tests
        reset = 1;
        #10; reset = 0;
        clear_inputs;
        #1;
        check({63'd0, hlt}, 64'd0, "hlt cleared after reset");

        // ============================================================
        // Test 5: Flush with drain
        // ============================================================
        $display("\n--- Test 5: Flush and drain ---");

        // Allocate 4 instructions: ALU, BRANCH, ALU, ALU
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd0; // ALU
        alloc_arch_rd0 = 5'd1; alloc_old_phys0 = 7'd1; alloc_new_phys0 = 7'd40;
        alloc_has_dest0 = 1; alloc_pc0 = 64'h400;
        alloc_en1 = 1; alloc_type1 = 3'd4; // BRANCH
        alloc_arch_rd1 = 5'd0; alloc_old_phys1 = 7'd0; alloc_new_phys1 = 7'd0;
        alloc_has_dest1 = 0; alloc_br_pred1 = 0; alloc_pc1 = 64'h404;
        @(negedge clk);
        clear_inputs;

        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd0; // ALU (after branch)
        alloc_arch_rd0 = 5'd5; alloc_old_phys0 = 7'd5; alloc_new_phys0 = 7'd41;
        alloc_has_dest0 = 1; alloc_pc0 = 64'h408;
        alloc_en1 = 1; alloc_type1 = 3'd0; // ALU (after branch)
        alloc_arch_rd1 = 5'd6; alloc_old_phys1 = 7'd6; alloc_new_phys1 = 7'd42;
        alloc_has_dest1 = 1; alloc_pc1 = 64'h40C;
        @(negedge clk);
        clear_inputs;
        #1;
        check({58'd0, dut.count}, 64'd4, "count = 4 before flush");

        // Complete the branch (mispredicted, correct target = 0x500)
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd1;
        cdb_value0 = 64'h500; // correct branch target
        cdb_br_actual0 = 1; cdb_mispredict0 = 1;
        @(negedge clk);
        clear_inputs;

        // Now flush: mispredicted branch is at ROB index 1
        @(negedge clk);
        flush_en = 1; flush_rob_idx = 5'd1;
        @(negedge clk);
        flush_en = 0;
        #1;

        check(flush_redirect_pc, 64'h500, "redirect PC = 0x500");
        check({58'd0, dut.count}, 64'd2, "count = 2 after flush (entries 0,1 remain)");

        // Drain should free phys regs 41 and 42 (entries 2 and 3 had has_dest)
        if (flush_active) begin
            $display("  flush_active: draining flushed entries...");
            // Wait for drain to complete
            @(negedge clk);
            #1;
        end

        // Check that the drain freed the right registers
        // The drain happens on posedge, so outputs are available after
        // Let's check the drain occurred (free_en was asserted)
        // Since entries 2 and 3 both had has_dest, both should be freed in 1 drain cycle
        check({63'd0, flush_active}, 64'd0, "drain complete");

        // Verify ROB state: only entries 0 and 1 remain
        check({58'd0, dut.count}, 64'd2, "count still 2 after drain");

        // Complete entry 0 (ALU) and let it commit
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd0; cdb_value0 = 64'h99;
        @(negedge clk);
        clear_inputs;
        #1;

        // Entry 0 completed, entry 1 (branch) already completed
        // Both should commit (ALU + BRANCH, neither is STORE or HALT)
        check({63'd0, commit_en0}, 64'd1, "ALU at head commits after flush");
        check({63'd0, commit_en1}, 64'd1, "BRANCH commits as second");

        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, empty}, 64'd1, "empty after post-flush commits");

        // ============================================================
        // Test 6: Full condition
        // ============================================================
        $display("\n--- Test 6: Full condition ---");

        // Reset for clean state
        reset = 1; #10; reset = 0; clear_inputs;

        // Allocate 31 entries (2 at a time) to trigger full
        begin : fill_rob
            integer j;
            for (j = 0; j < 15; j = j + 1) begin
                @(negedge clk);
                alloc_en0 = 1; alloc_type0 = 3'd0;
                alloc_arch_rd0 = 5'd1; alloc_old_phys0 = 7'd1;
                alloc_new_phys0 = j[6:0] + 7'd50; alloc_has_dest0 = 1;
                alloc_pc0 = j * 4;
                alloc_en1 = 1; alloc_type1 = 3'd0;
                alloc_arch_rd1 = 5'd2; alloc_old_phys1 = 7'd2;
                alloc_new_phys1 = j[6:0] + 7'd80; alloc_has_dest1 = 1;
                alloc_pc1 = j * 4 + 4;
            end
        end
        @(negedge clk);
        clear_inputs;
        #1;
        check({58'd0, dut.count}, 64'd30, "count = 30 after 15x dual alloc");
        check({63'd0, full}, 64'd0, "not full at 30 entries");

        // Allocate 1 more -> count = 31 -> full
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd0;
        alloc_arch_rd0 = 5'd3; alloc_old_phys0 = 7'd3;
        alloc_new_phys0 = 7'd100; alloc_has_dest0 = 1;
        alloc_pc0 = 64'hF00;
        alloc_en1 = 0;
        @(negedge clk);
        clear_inputs;
        #1;
        check({58'd0, dut.count}, 64'd31, "count = 31");
        check({63'd0, full}, 64'd1, "full at 31 entries");

        // ============================================================
        // Test 7: Single allocate
        // ============================================================
        $display("\n--- Test 7: Single allocate ---");

        reset = 1; #10; reset = 0; clear_inputs;

        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd1; // FPU
        alloc_arch_rd0 = 5'd10; alloc_old_phys0 = 7'd10; alloc_new_phys0 = 7'd60;
        alloc_has_dest0 = 1; alloc_pc0 = 64'h800;
        alloc_en1 = 0;
        @(negedge clk);
        clear_inputs;
        #1;
        check({58'd0, dut.count}, 64'd1, "count = 1 after single alloc");

        // Complete and commit
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd0; cdb_value0 = 64'hDEAD;
        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, commit_en0}, 64'd1, "FPU commits");
        check({61'd0, commit_type0}, 64'd1, "type = FPU");
        check({63'd0, commit_en1}, 64'd0, "no second commit");

        @(negedge clk);
        clear_inputs;
        #1;
        check({63'd0, empty}, 64'd1, "empty after FPU commit");

        // ============================================================
        // Test 8: Flush with same-cycle CDB (redirect PC forwarding)
        // ============================================================
        $display("\n--- Test 8: Same-cycle CDB + flush (redirect PC forwarding) ---");

        reset = 1; #10; reset = 0; clear_inputs;

        // Allocate a branch at index 0
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd4; // BRANCH
        alloc_has_dest0 = 0; alloc_br_pred0 = 0; alloc_pc0 = 64'hA00;
        alloc_en1 = 0;
        @(negedge clk);
        clear_inputs;

        // Allocate an ALU after the branch
        @(negedge clk);
        alloc_en0 = 1; alloc_type0 = 3'd0; // ALU
        alloc_arch_rd0 = 5'd7; alloc_old_phys0 = 7'd7; alloc_new_phys0 = 7'd70;
        alloc_has_dest0 = 1; alloc_pc0 = 64'hA04;
        alloc_en1 = 0;
        @(negedge clk);
        clear_inputs;

        // CDB complete for branch (mispredicted) AND flush in the SAME cycle
        @(negedge clk);
        cdb_valid0 = 1; cdb_rob_idx0 = 5'd0;
        cdb_value0 = 64'hB00; // correct target
        cdb_br_actual0 = 1; cdb_mispredict0 = 1;
        flush_en = 1; flush_rob_idx = 5'd0;
        @(negedge clk);
        clear_inputs;
        #1;

        // Redirect PC should be forwarded from CDB value (not stale ROB entry)
        check(flush_redirect_pc, 64'hB00, "same-cycle CDB forward: redirect = 0xB00");

        // Drain: entry 1 (ALU, has_dest, new_phys=70) should be freed
        // Wait for drain
        if (flush_active) begin
            @(negedge clk);
            #1;
        end
        check({63'd0, flush_active}, 64'd0, "drain done");

        // ============================================================
        $display("\n--- Results: %0d passed, %0d failed ---", pass_count, fail_count);
        if (fail_count > 0)
            $display("*** SOME TESTS FAILED ***");
        else
            $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
