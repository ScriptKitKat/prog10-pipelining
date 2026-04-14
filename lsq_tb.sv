// Testbench for load_store_queue.sv
// Tests: load from memory, store-to-load forwarding, store commit → memory
//        write, CDB snoop for store data, flush, full condition.

`timescale 1ns/1ps
`include "memory_reg.sv"
`include "load_store_queue.sv"

module lsq_tb;

    reg clk, reset;
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // ----------------------------------------------------------------
    // Memory instance
    // ----------------------------------------------------------------
    wire [63:0] mem_read_addr;
    wire        mem_read_en;
    wire [63:0] mem_read_data;
    wire        mem_write_en;
    wire [63:0] mem_write_addr;
    wire [63:0] mem_write_data;

    wire [31:0] mem_instr;
    wire [511:0] mem_fetch_data;
    wire mem_data_ready;

    memory u_mem (
        .clk            (clk),
        .reset          (reset),
        .PC             (64'h2000),
        .instruction    (mem_instr),
        .instr_fetch_addr(64'h2000),
        .instr_fetch_data(mem_fetch_data),
        .data_address   (mem_read_addr),
        .data_out       (mem_read_data),
        .data_ready     (mem_data_ready),
        .write_enable   (mem_write_en),
        .write_address  (mem_write_addr),
        .write_data     (mem_write_data)
    );

    // ----------------------------------------------------------------
    // LSQ instance
    // ----------------------------------------------------------------
    reg         flush_en;
    reg  [4:0]  flush_rob_idx;
    reg  [4:0]  rob_head_idx;

    reg         ld_dispatch_en;
    reg  [4:0]  ld_dispatch_rob_idx;
    reg  [6:0]  ld_dispatch_dest_tag;
    wire        ld_full;

    reg         st_dispatch_en;
    reg  [4:0]  st_dispatch_rob_idx;
    reg  [63:0] st_dispatch_data;
    reg         st_dispatch_data_ready;
    reg  [6:0]  st_dispatch_data_tag;
    wire        st_full;

    reg         ld_addr_valid;
    reg  [4:0]  ld_addr_rob_idx;
    reg  [63:0] ld_addr_value;

    reg         st_addr_valid;
    reg  [4:0]  st_addr_rob_idx;
    reg  [63:0] st_addr_value;
    reg  [63:0] st_addr_data;
    reg         st_addr_data_valid;

    reg         cdb_valid0, cdb_valid1;
    reg  [6:0]  cdb_tag0, cdb_tag1;
    reg  [63:0] cdb_value0, cdb_value1;

    reg         store_commit_en;
    reg  [4:0]  store_commit_rob_idx;

    wire        load_result_valid;
    wire [6:0]  load_result_dest_tag;
    wire [4:0]  load_result_rob_idx;
    wire [63:0] load_result_data;

    wire        store_complete_valid;
    wire [4:0]  store_complete_rob_idx;
    wire [63:0] store_complete_addr;
    wire [63:0] store_complete_data;

    load_store_queue u_lsq (
        .clk                 (clk),
        .reset               (reset),
        .flush_en            (flush_en),
        .flush_rob_idx       (flush_rob_idx),
        .rob_head_idx        (rob_head_idx),
        .ld_dispatch_en      (ld_dispatch_en),
        .ld_dispatch_rob_idx (ld_dispatch_rob_idx),
        .ld_dispatch_dest_tag(ld_dispatch_dest_tag),
        .ld_full             (ld_full),
        .st_dispatch_en      (st_dispatch_en),
        .st_dispatch_rob_idx (st_dispatch_rob_idx),
        .st_dispatch_data    (st_dispatch_data),
        .st_dispatch_data_ready(st_dispatch_data_ready),
        .st_dispatch_data_tag(st_dispatch_data_tag),
        .st_full             (st_full),
        .ld_addr_valid       (ld_addr_valid),
        .ld_addr_rob_idx     (ld_addr_rob_idx),
        .ld_addr_value       (ld_addr_value),
        .st_addr_valid       (st_addr_valid),
        .st_addr_rob_idx     (st_addr_rob_idx),
        .st_addr_value       (st_addr_value),
        .st_addr_data        (st_addr_data),
        .st_addr_data_valid  (st_addr_data_valid),
        .cdb_valid0          (cdb_valid0),
        .cdb_tag0            (cdb_tag0),
        .cdb_value0          (cdb_value0),
        .cdb_valid1          (cdb_valid1),
        .cdb_tag1            (cdb_tag1),
        .cdb_value1          (cdb_value1),
        .mem_read_addr       (mem_read_addr),
        .mem_read_en         (mem_read_en),
        .mem_read_data       (mem_read_data),
        .mem_write_en        (mem_write_en),
        .mem_write_addr      (mem_write_addr),
        .mem_write_data      (mem_write_data),
        .store_commit_en     (store_commit_en),
        .store_commit_rob_idx(store_commit_rob_idx),
        .load_result_valid   (load_result_valid),
        .load_result_dest_tag(load_result_dest_tag),
        .load_result_rob_idx (load_result_rob_idx),
        .load_result_data    (load_result_data),
        .store_complete_valid(store_complete_valid),
        .store_complete_rob_idx(store_complete_rob_idx),
        .store_complete_addr (store_complete_addr),
        .store_complete_data (store_complete_data)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task check(input [255:0] label, input [63:0] actual, input [63:0] expected);
        test_num = test_num + 1;
        if (actual === expected) begin
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL test %0d [%0s]: got %0h, expected %0h",
                     test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task check1(input [255:0] label, input actual, input expected);
        test_num = test_num + 1;
        if (actual === expected) begin
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL test %0d [%0s]: got %0b, expected %0b",
                     test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task clear_inputs;
        begin
            ld_dispatch_en = 0; ld_dispatch_rob_idx = 0; ld_dispatch_dest_tag = 0;
            st_dispatch_en = 0; st_dispatch_rob_idx = 0; st_dispatch_data = 0;
            st_dispatch_data_ready = 0; st_dispatch_data_tag = 0;
            ld_addr_valid = 0; ld_addr_rob_idx = 0; ld_addr_value = 0;
            st_addr_valid = 0; st_addr_rob_idx = 0; st_addr_value = 0;
            st_addr_data = 0; st_addr_data_valid = 0;
            cdb_valid0 = 0; cdb_tag0 = 0; cdb_value0 = 0;
            cdb_valid1 = 0; cdb_tag1 = 0; cdb_value1 = 0;
            store_commit_en = 0; store_commit_rob_idx = 0;
            flush_en = 0; flush_rob_idx = 0;
        end
    endtask

    // ================================================================
    // Test sequence
    // ================================================================
    initial begin
        $dumpfile("lsq_tb.vcd");
        $dumpvars(0, lsq_tb);

        // --- Reset ---
        reset = 1; rob_head_idx = 0;
        clear_inputs;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ============================================================
        // TEST 1: Seed memory + load from memory
        // ============================================================
        $display("\n--- Test 1: Load from memory ---");

        // Dispatch store (rob_idx=0, data=0xDEADBEEFCAFE0000, addr=0x100)
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd0;
        st_dispatch_data = 64'hDEADBEEFCAFE0000;
        st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        // Provide store address
        st_addr_valid = 1; st_addr_rob_idx = 5'd0; st_addr_value = 64'h100;
        @(posedge clk); #1; clear_inputs;

        // Wait for store complete broadcast
        @(posedge clk); #1;
        check1("seed store complete", store_complete_valid, 1'b1);

        // Commit store
        store_commit_en = 1; store_commit_rob_idx = 5'd0;
        @(posedge clk); #1; clear_inputs;

        // Committed store writes to memory and clears
        @(posedge clk); #1;

        // Now load from 0x100
        rob_head_idx = 5'd1;
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd1; ld_dispatch_dest_tag = 7'd10;
        @(posedge clk); #1; clear_inputs;

        ld_addr_valid = 1; ld_addr_rob_idx = 5'd1; ld_addr_value = 64'h100;
        @(posedge clk); #1; clear_inputs;

        // Result available next cycle (registered output)
        @(posedge clk); #1;
        check1("ld mem valid", load_result_valid, 1'b1);
        check("ld mem data", load_result_data, 64'hDEADBEEFCAFE0000);
        check("ld mem tag", {57'b0, load_result_dest_tag}, {57'b0, 7'd10});
        check("ld mem rob", {59'b0, load_result_rob_idx}, {59'b0, 5'd1});

        @(posedge clk); #1;
        check1("ld drained", load_result_valid, 1'b0);

        // ============================================================
        // TEST 2: Store-to-load forwarding
        // ============================================================
        $display("\n--- Test 2: Store-to-load forwarding ---");
        rob_head_idx = 5'd2;

        // Dispatch store (rob=2, data=0x42)
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd2;
        st_dispatch_data = 64'h42; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        // Dispatch load (rob=3)
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd3;
        ld_dispatch_dest_tag = 7'd20;
        @(posedge clk); #1; clear_inputs;

        // Provide store address (0x200)
        st_addr_valid = 1; st_addr_rob_idx = 5'd2; st_addr_value = 64'h200;
        @(posedge clk); #1; clear_inputs;

        // Provide load address (same)
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd3; ld_addr_value = 64'h200;
        @(posedge clk); #1; clear_inputs;

        // Result: forwarded
        @(posedge clk); #1;
        check1("fwd valid", load_result_valid, 1'b1);
        check("fwd data", load_result_data, 64'h42);
        check("fwd tag", {57'b0, load_result_dest_tag}, {57'b0, 7'd20});

        // Cleanup store: commit + write + clear
        store_commit_en = 1; store_commit_rob_idx = 5'd2;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;

        // ============================================================
        // TEST 3: Store data via CDB snoop
        // ============================================================
        $display("\n--- Test 3: Store data via CDB ---");
        rob_head_idx = 5'd4;

        // Dispatch store without data (tag=50)
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd4;
        st_dispatch_data_ready = 0; st_dispatch_data_tag = 7'd50;
        @(posedge clk); #1; clear_inputs;

        // Provide store address
        st_addr_valid = 1; st_addr_rob_idx = 5'd4; st_addr_value = 64'h300;
        @(posedge clk); #1; clear_inputs;

        // Not complete yet (no data)
        @(posedge clk); #1;
        check1("cdb no data yet", store_complete_valid, 1'b0);

        // CDB broadcasts matching tag
        cdb_valid0 = 1; cdb_tag0 = 7'd50; cdb_value0 = 64'h99;
        @(posedge clk); #1; clear_inputs;

        // Now complete
        @(posedge clk); #1;
        check1("cdb store complete", store_complete_valid, 1'b1);
        check("cdb store data", store_complete_data, 64'h99);
        check("cdb store addr", store_complete_addr, 64'h300);

        // Commit, write, verify memory
        store_commit_en = 1; store_commit_rob_idx = 5'd4;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1; // writes to memory

        rob_head_idx = 5'd5;
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd5; ld_dispatch_dest_tag = 7'd30;
        @(posedge clk); #1; clear_inputs;
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd5; ld_addr_value = 64'h300;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;
        check1("cdb verify valid", load_result_valid, 1'b1);
        check("cdb verify data", load_result_data, 64'h99);

        @(posedge clk); #1;

        // ============================================================
        // TEST 4: Load must wait for store data
        // ============================================================
        $display("\n--- Test 4: Load must wait ---");
        rob_head_idx = 5'd6;

        // Store without data
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd6;
        st_dispatch_data_ready = 0; st_dispatch_data_tag = 7'd60;
        @(posedge clk); #1; clear_inputs;

        // Store address
        st_addr_valid = 1; st_addr_rob_idx = 5'd6; st_addr_value = 64'h400;
        @(posedge clk); #1; clear_inputs;

        // Load at same address
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd7; ld_dispatch_dest_tag = 7'd40;
        @(posedge clk); #1; clear_inputs;
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd7; ld_addr_value = 64'h400;
        @(posedge clk); #1; clear_inputs;

        // Must wait — no result
        @(posedge clk); #1;
        check1("must wait", load_result_valid, 1'b0);

        // CDB delivers store data
        cdb_valid0 = 1; cdb_tag0 = 7'd60; cdb_value0 = 64'hABCD;
        @(posedge clk); #1; clear_inputs;

        // Now forward resolves
        @(posedge clk); #1;
        check1("wait resolved", load_result_valid, 1'b1);
        check("wait data", load_result_data, 64'hABCD);

        // Cleanup store
        store_commit_en = 1; store_commit_rob_idx = 5'd6;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;

        // ============================================================
        // TEST 5: Flush — younger entries removed, older survives
        //   Dispatch entries. Flush before providing surviving load's
        //   address to ensure it persists and executes after flush.
        // ============================================================
        $display("\n--- Test 5: Flush ---");
        rob_head_idx = 5'd8;

        // Dispatch: ld=8 (survives), ld=9 (flushed), st=10 (flushed)
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd8;
        ld_dispatch_dest_tag = 7'd55;
        @(posedge clk); #1; clear_inputs;

        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd9;
        ld_dispatch_dest_tag = 7'd56;
        @(posedge clk); #1; clear_inputs;

        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd10;
        st_dispatch_data = 64'hFF; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        // Flush at rob_idx=8 → entries 9,10 flushed (age > 0); entry 8 survives
        flush_en = 1; flush_rob_idx = 5'd8;
        @(posedge clk); #1;
        flush_en = 0;

        // Verify queues freed slots
        @(posedge clk); #1;
        check1("flush ld not full", ld_full, 1'b0);
        check1("flush st not full", st_full, 1'b0);

        // Surviving load (rob=8) still has no address; provide it now
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd8; ld_addr_value = 64'h100;
        @(posedge clk); #1; clear_inputs;

        // Load executes from memory
        @(posedge clk); #1;
        check1("flush survive valid", load_result_valid, 1'b1);
        check("flush survive data", load_result_data, 64'hDEADBEEFCAFE0000);
        check("flush survive rob", {59'b0, load_result_rob_idx}, {59'b0, 5'd8});

        @(posedge clk); #1;

        // ============================================================
        // TEST 6: Store commit → memory write → readback
        // ============================================================
        $display("\n--- Test 6: Store commit to memory ---");
        rob_head_idx = 5'd11;

        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd11;
        st_dispatch_data = 64'hBEEF; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        st_addr_valid = 1; st_addr_rob_idx = 5'd11; st_addr_value = 64'h700;
        @(posedge clk); #1; clear_inputs;

        @(posedge clk); #1;
        check1("st6 complete", store_complete_valid, 1'b1);

        store_commit_en = 1; store_commit_rob_idx = 5'd11;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1; // writes to memory

        // Load back
        rob_head_idx = 5'd12;
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd12; ld_dispatch_dest_tag = 7'd70;
        @(posedge clk); #1; clear_inputs;
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd12; ld_addr_value = 64'h700;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;
        check1("st6 readback valid", load_result_valid, 1'b1);
        check("st6 readback data", load_result_data, 64'hBEEF);

        @(posedge clk); #1;

        // ============================================================
        // TEST 7: Store addr + data arrive together
        // ============================================================
        $display("\n--- Test 7: Store addr+data together ---");
        rob_head_idx = 5'd13;

        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd13;
        st_dispatch_data_ready = 0; st_dispatch_data_tag = 7'd80;
        @(posedge clk); #1; clear_inputs;

        // Address + data in one shot
        st_addr_valid = 1; st_addr_rob_idx = 5'd13;
        st_addr_value = 64'h800;
        st_addr_data = 64'hFACE; st_addr_data_valid = 1;
        @(posedge clk); #1; clear_inputs;

        @(posedge clk); #1;
        check1("t7 complete", store_complete_valid, 1'b1);
        check("t7 data", store_complete_data, 64'hFACE);
        check("t7 addr", store_complete_addr, 64'h800);

        // Cleanup
        store_commit_en = 1; store_commit_rob_idx = 5'd13;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;

        // ============================================================
        // TEST 8: Youngest older store wins forwarding
        // ============================================================
        $display("\n--- Test 8: Youngest older store fwd ---");
        rob_head_idx = 5'd14;

        // Store A (rob=14, addr=0x900, data=0x11)
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd14;
        st_dispatch_data = 64'h11; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        // Store B (rob=15, addr=0x900, data=0x22) — younger
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd15;
        st_dispatch_data = 64'h22; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;

        // Load (rob=16)
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd16;
        ld_dispatch_dest_tag = 7'd90;
        @(posedge clk); #1; clear_inputs;

        // Provide all addresses
        st_addr_valid = 1; st_addr_rob_idx = 5'd14; st_addr_value = 64'h900;
        @(posedge clk); #1; clear_inputs;
        st_addr_valid = 1; st_addr_rob_idx = 5'd15; st_addr_value = 64'h900;
        @(posedge clk); #1; clear_inputs;
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd16; ld_addr_value = 64'h900;
        @(posedge clk); #1; clear_inputs;

        // Forward from Store B (youngest older)
        @(posedge clk); #1;
        check1("youngest fwd valid", load_result_valid, 1'b1);
        check("youngest fwd data", load_result_data, 64'h22);

        // Cleanup stores
        store_commit_en = 1; store_commit_rob_idx = 5'd14;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;
        store_commit_en = 1; store_commit_rob_idx = 5'd15;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;

        // ============================================================
        // TEST 9: Non-matching address → memory
        // ============================================================
        $display("\n--- Test 9: Non-matching addr → memory ---");
        rob_head_idx = 5'd17;

        // Store at 0xA00
        st_dispatch_en = 1; st_dispatch_rob_idx = 5'd17;
        st_dispatch_data = 64'hBB; st_dispatch_data_ready = 1;
        @(posedge clk); #1; clear_inputs;
        st_addr_valid = 1; st_addr_rob_idx = 5'd17; st_addr_value = 64'hA00;
        @(posedge clk); #1; clear_inputs;

        // Load at 0x100 (seeded in test 1)
        ld_dispatch_en = 1; ld_dispatch_rob_idx = 5'd18;
        ld_dispatch_dest_tag = 7'd95;
        @(posedge clk); #1; clear_inputs;
        ld_addr_valid = 1; ld_addr_rob_idx = 5'd18; ld_addr_value = 64'h100;
        @(posedge clk); #1; clear_inputs;

        @(posedge clk); #1;
        check1("nomatch valid", load_result_valid, 1'b1);
        check("nomatch data", load_result_data, 64'hDEADBEEFCAFE0000);

        // Cleanup store
        store_commit_en = 1; store_commit_rob_idx = 5'd17;
        @(posedge clk); #1; clear_inputs;
        @(posedge clk); #1;

        // ============================================================
        // TEST 10: Full condition (last — no cleanup needed)
        // ============================================================
        $display("\n--- Test 10: Full condition ---");
        rob_head_idx = 5'd20;

        begin : fill_lq
            integer k;
            for (k = 0; k < 8; k = k + 1) begin
                ld_dispatch_en = 1;
                ld_dispatch_rob_idx = (20 + k) & 5'h1F;
                ld_dispatch_dest_tag = k[6:0];
                @(posedge clk); #1; clear_inputs;
            end
        end
        check1("lq full", ld_full, 1'b1);

        begin : fill_sq
            integer k;
            for (k = 0; k < 8; k = k + 1) begin
                st_dispatch_en = 1;
                st_dispatch_rob_idx = (28 + k) & 5'h1F;
                st_dispatch_data = k[63:0]; st_dispatch_data_ready = 1;
                @(posedge clk); #1; clear_inputs;
            end
        end
        check1("sq full", st_full, 1'b1);

        // ============================================================
        // Summary
        // ============================================================
        $display("\n==================================================");
        $display("  %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d TESTS FAILED", fail_count);
        $display("==================================================\n");
        $finish;
    end

endmodule
