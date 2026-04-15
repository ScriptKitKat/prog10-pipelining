// Testbench for fetch_unit.sv — sequential fetch, BRR_L + BHT redirect, flush.

`timescale 1ns/1ps
`include "fetch_unit.sv"

module fetch_unit_tb;

    reg clk, reset;
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    wire [63:0] instr_fetch_addr;
    wire [511:0] instr_fetch_data;

    reg [1:0] decode_take;

    wire [31:0] out0_inst, out1_inst;
    wire [63:0] out0_pc, out1_pc;
    wire        out0_br_pred, out1_br_pred;
    wire [63:0] out0_pred_target, out1_pred_target;
    wire        out0_valid, out1_valid;

    reg        flush;
    reg [63:0] flush_pc;

    reg        bht_update_en;
    reg [63:0] bht_update_pc;
    reg        bht_pred_taken;
    reg        bht_actual_taken;

    reg        btb_update_en;
    reg [63:0] btb_update_pc, btb_update_target;
    reg        btb_update_taken;

    function [511:0] line_bytes;
        input [31:0] w0, w1, w2, w3;
        input [31:0] w4, w5, w6, w7;
        input [31:0] w8, w9, wa, wb;
        input [31:0] wc, wd, we, wf;
        begin
            line_bytes = {wf, we, wd, wc, wb, wa, w9, w8,
                          w7, w6, w5, w4, w3, w2, w1, w0};
        end
    endfunction

    localparam [31:0] INS_NOP = {5'h18, 5'd0, 5'd0, 5'd0, 12'd0};

    reg [511:0] line_2000;
    reg [511:0] line_2040;
    reg [511:0] line_3000;

    function [31:0] ins_brr_l(input [11:0] L12);
        begin
            ins_brr_l = {5'h0A, 5'd0, 5'd0, 5'd0, L12};
        end
    endfunction

    assign instr_fetch_data =
        (instr_fetch_addr == 64'h2000) ? line_2000 :
        (instr_fetch_addr == 64'h2040) ? line_2040 :
        (instr_fetch_addr == 64'h3000) ? line_3000 : 512'd0;

    fetch_unit u_ifu (
        .clk(clk), .reset(reset),
        .instr_fetch_addr(instr_fetch_addr),
        .instr_fetch_data(instr_fetch_data),
        .decode_take(decode_take),
        .out0_inst(out0_inst), .out0_pc(out0_pc), .out0_br_pred(out0_br_pred),
        .out0_pred_target(out0_pred_target), .out0_valid(out0_valid),
        .out1_inst(out1_inst), .out1_pc(out1_pc), .out1_br_pred(out1_br_pred),
        .out1_pred_target(out1_pred_target), .out1_valid(out1_valid),
        .flush(flush), .flush_pc(flush_pc),
        .bht_update_en(bht_update_en), .bht_update_pc(bht_update_pc),
        .bht_pred_taken(bht_pred_taken), .bht_actual_taken(bht_actual_taken),
        .btb_update_en(btb_update_en), .btb_update_pc(btb_update_pc),
        .btb_update_target(btb_update_target), .btb_update_taken(btb_update_taken)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check(input [255:0] label, input [63:0] actual, input [63:0] expected);
        test_num = test_num + 1;
        if (actual === expected) pass_count = pass_count + 1;
        else begin
            $display("FAIL test %0d [%0s]: got %h exp %h", test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task check1(input [255:0] label, input actual, input expected);
        test_num = test_num + 1;
        if (actual === expected) pass_count = pass_count + 1;
        else begin
            $display("FAIL test %0d [%0s]: got %b exp %b", test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    initial begin
        $dumpfile("sim/fetch_unit_tb.vcd");
        $dumpvars(0, fetch_unit_tb);

        line_2000 = line_bytes(
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        line_2040 = line_bytes(
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        line_3000 = line_2000;

        decode_take = 0;
        flush = 0;
        flush_pc = 0;
        bht_update_en = 0;
        bht_update_pc = 0;
        bht_pred_taken = 0;
        bht_actual_taken = 0;
        btb_update_en = 0;
        btb_update_pc = 0;
        btb_update_target = 0;
        btb_update_taken = 0;

        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ----------------------------------------------------------
        // TEST 1: Sequential PCs from 0x2000
        // ----------------------------------------------------------
        $display("\n--- Test 1: Sequential fetch ---");
        #1;
        check1("t1 out0_valid", out0_valid, 1'b1);
        check("t1 out0_pc", out0_pc, 64'h2000);

        decode_take = 2'd2;
        @(posedge clk); #1;
        check("t1 pc+8", out0_pc, 64'h2008);

        decode_take = 2'd2;
        @(posedge clk); #1;
        check("t1 pc+16", out0_pc, 64'h2010);

        decode_take = 0;

        // ----------------------------------------------------------
        // TEST 2: BRR_L + BHT taken → next fetch at target 0x2000+0x10=0x2010
        // Line 0x2000: insn0 = BRR_L +16 (0x10), rest NOP
        // Train BHT[0x2000] to taken via update (pred 0, actual 1) → bit=1
        // ----------------------------------------------------------
        $display("\n--- Test 2: BRR_L + BHT redirect ---");
        line_2000 = line_bytes(
            ins_brr_l(12'sh010), // +16 bytes
            INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        flush = 1;
        flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        bht_update_en = 1;
        bht_update_pc = 64'h2000;
        bht_pred_taken = 0;
        bht_actual_taken = 1;
        @(posedge clk); #1;
        bht_update_en = 0;
        @(posedge clk); #1;

        flush = 1;
        flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        #1;
        check1("t2 brr valid", out0_valid, 1'b1);
        check("t2 brr opc", {27'd0, out0_inst[31:27]}, {27'd0, 5'h0A});
        // Redirect skips 0x2004..0x200c; next insn at 0x2010 is second word in line — NOP
        decode_take = 2'd1;
        @(posedge clk); #1;
        decode_take = 0;
        #1;
        check("t2 after br", out0_pc, 64'h2010);
        check("t2 nop opc", {27'd0, out0_inst[31:27]}, {27'd0, 5'h18});

        // ----------------------------------------------------------
        // TEST 3: Flush clears buffer, then refills from new PC
        // ----------------------------------------------------------
        $display("\n--- Test 3: Flush ---");
        flush = 1;
        flush_pc = 64'h3000;
        @(posedge clk); #1;
        // During the flush cycle, outputs are forced invalid
        check1("t3 flush clear", out0_valid, 1'b0);
        flush = 0;
        // Next cycle refills from 0x3000
        @(posedge clk); #1;
        check1("t3 refill valid", out0_valid, 1'b1);
        check("t3 refill pc", out0_pc, 64'h3000);

        // ----------------------------------------------------------
        // TEST 4: Non-BRR_L branches must NOT use BHT prediction
        //         (BRNZ opcode 0x0B should always get pred_taken=0)
        // ----------------------------------------------------------
        $display("\n--- Test 4: BRNZ ignores BHT (pred=0 always) ---");

        // First, train the BHT entry at PC 0x2000 to '1' (taken)
        bht_update_en = 1;
        bht_update_pc = 64'h2000;
        bht_pred_taken = 0;
        bht_actual_taken = 1;
        @(posedge clk); #1;
        bht_update_en = 0;

        // Place a BRNZ instruction at word 0 of line 0x2000
        // BRNZ rs=r1, rd=r2 : {5'h0B, 5'd2, 5'd1, 5'd0, 12'd0}
        line_2000 = line_bytes(
            {5'h0B, 5'd2, 5'd1, 5'd0, 12'd0},  // BRNZ at 0x2000
            INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        flush = 1; flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        // BHT entry at PC[9:2]=0 is '1', but BRNZ should NOT use it
        check1("t4 brnz pred=0", out0_br_pred, 1'b0);
        // Fetch should continue sequentially (no redirect)
        decode_take = 2'd1;
        @(posedge clk); #1;
        decode_take = 0;
        check("t4 seq after brnz", out0_pc, 64'h2004);

        // ----------------------------------------------------------
        // TEST 5: BRGT also ignores BHT
        // ----------------------------------------------------------
        $display("\n--- Test 5: BRGT ignores BHT (pred=0 always) ---");

        // Place BRGT at 0x2000: {5'h0E, 5'd3, 5'd1, 5'd2, 12'd0}
        line_2000 = line_bytes(
            {5'h0E, 5'd3, 5'd1, 5'd2, 12'd0},  // BRGT at 0x2000
            INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        flush = 1; flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        check1("t5 brgt pred=0", out0_br_pred, 1'b0);

        // ----------------------------------------------------------
        // TEST 6: Forward BRR_L learns via BHT after update
        //         BRR_L +0x10 at PC 0x2008 (L[11]=0 → forward, uses BHT)
        // ----------------------------------------------------------
        $display("\n--- Test 6: Forward BRR_L BHT learning ---");

        // Place BRR_L +0x10 at word 2 (PC 0x2008)
        line_2000 = line_bytes(
            INS_NOP, INS_NOP,
            ins_brr_l(12'sh010),  // forward +16 at PC 0x2008
            INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        flush = 1; flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        // Consume the first 2 NOPs to get to the BRR_L at 0x2008
        decode_take = 2'd2;
        @(posedge clk); #1;
        decode_take = 0;
        #1;

        // BHT entry at 0x2008[9:2]=2 should be 0 (cold) → predict not-taken
        check1("t6 fwd brr_l cold pred", out0_br_pred, 1'b0);
        check("t6 fwd brr_l pc", out0_pc, 64'h2008);

        // Train BHT: update PC 0x2008 with pred=0, actual=1 → flip to 1
        bht_update_en = 1;
        bht_update_pc = 64'h2008;
        bht_pred_taken = 0;
        bht_actual_taken = 1;
        @(posedge clk); #1;
        bht_update_en = 0;

        // Re-fetch from 0x2000 and check prediction at 0x2008
        flush = 1; flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        decode_take = 2'd2;
        @(posedge clk); #1;
        decode_take = 0;
        #1;

        // Now BHT[2]=1 → forward BRR_L predicted taken
        check1("t6 fwd brr_l trained pred", out0_br_pred, 1'b1);

        // After predicted-taken BRR_L, next fetch should be at target 0x2008+0x10=0x2018
        decode_take = 2'd1;
        @(posedge clk); #1;
        decode_take = 0;
        #1;
        check("t6 redirect target", out0_pc, 64'h2018);

        // ----------------------------------------------------------
        // TEST 7: Backward BRR_L always statically predicted taken
        //         (regardless of BHT state)
        // ----------------------------------------------------------
        $display("\n--- Test 7: Backward BRR_L static taken ---");

        // Place backward BRR_L -8 at word 4 (PC 0x2010)
        // L = -8 = 12'hFF8, L[11]=1 → backward
        line_2000 = line_bytes(
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            ins_brr_l(12'hFF8),  // backward -8 at PC 0x2010
            INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP,
            INS_NOP, INS_NOP, INS_NOP, INS_NOP);

        flush = 1; flush_pc = 64'h2000;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;

        // Consume 4 NOPs to reach backward BRR_L at 0x2010
        decode_take = 2'd2;
        @(posedge clk); #1;
        decode_take = 2'd2;
        @(posedge clk); #1;
        decode_take = 0;
        #1;

        check1("t7 bkwd pred taken", out0_br_pred, 1'b1);
        check("t7 bkwd brr_l pc", out0_pc, 64'h2010);

        // Next fetch should redirect to 0x2010 + (-8) = 0x2008
        decode_take = 2'd1;
        @(posedge clk); #1;
        decode_take = 0;
        #1;
        check("t7 bkwd target", out0_pc, 64'h2008);

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
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
