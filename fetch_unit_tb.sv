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
    wire        out0_valid, out1_valid;

    reg        flush;
    reg [63:0] flush_pc;

    reg        bht_update_en;
    reg [63:0] bht_update_pc;
    reg        bht_pred_taken;
    reg        bht_actual_taken;

    function automatic [511:0] line_bytes(
        input [31:0] w0, w1, w2, w3,
        input [31:0] w4, w5, w6, w7,
        input [31:0] w8, w9, wa, wb,
        input [31:0] wc, wd, we, wf
    );
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
        .out0_inst(out0_inst), .out0_pc(out0_pc), .out0_br_pred(out0_br_pred), .out0_valid(out0_valid),
        .out1_inst(out1_inst), .out1_pc(out1_pc), .out1_br_pred(out1_br_pred), .out1_valid(out1_valid),
        .flush(flush), .flush_pc(flush_pc),
        .bht_update_en(bht_update_en), .bht_update_pc(bht_update_pc),
        .bht_pred_taken(bht_pred_taken), .bht_actual_taken(bht_actual_taken)
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
        $dumpfile("fetch_unit_tb.vcd");
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
