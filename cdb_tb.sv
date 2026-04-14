// Testbench for cdb.sv — round-robin arbitration, dual bus, stall behavior.

`timescale 1ns/1ps
`include "cdb.sv"

module cdb_tb;

    reg clk, reset;
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // Source stimulus
    reg        v_alu0, v_alu1, v_fpu0, v_fpu1, v_lsq0, v_lsq1;
    reg [6:0]  t_alu0, t_alu1, t_fpu0, t_fpu1, t_lsq0, t_lsq1;
    reg [63:0] q_alu0, q_alu1, q_fpu0, q_fpu1, q_lsq0, q_lsq1;
    reg [4:0]  r_alu0, r_alu1, r_fpu0, r_fpu1, r_lsq0, r_lsq1;

    wire        cdb_valid0, cdb_valid1;
    wire [6:0]  cdb_tag0, cdb_tag1;
    wire [63:0] cdb_value0, cdb_value1;
    wire [4:0]  cdb_rob_idx0, cdb_rob_idx1;
    wire        stall_alu0, stall_alu1, stall_fpu0, stall_fpu1, stall_lsq0, stall_lsq1;

    cdb u_cdb (
        .clk(clk), .reset(reset),
        .src_alu0_valid(v_alu0), .src_alu0_tag(t_alu0), .src_alu0_value(q_alu0), .src_alu0_rob_idx(r_alu0),
        .src_alu1_valid(v_alu1), .src_alu1_tag(t_alu1), .src_alu1_value(q_alu1), .src_alu1_rob_idx(r_alu1),
        .src_fpu0_valid(v_fpu0), .src_fpu0_tag(t_fpu0), .src_fpu0_value(q_fpu0), .src_fpu0_rob_idx(r_fpu0),
        .src_fpu1_valid(v_fpu1), .src_fpu1_tag(t_fpu1), .src_fpu1_value(q_fpu1), .src_fpu1_rob_idx(r_fpu1),
        .src_lsq0_valid(v_lsq0), .src_lsq0_tag(t_lsq0), .src_lsq0_value(q_lsq0), .src_lsq0_rob_idx(r_lsq0),
        .src_lsq1_valid(v_lsq1), .src_lsq1_tag(t_lsq1), .src_lsq1_value(q_lsq1), .src_lsq1_rob_idx(r_lsq1),
        .cdb_valid0(cdb_valid0), .cdb_tag0(cdb_tag0), .cdb_value0(cdb_value0), .cdb_rob_idx0(cdb_rob_idx0),
        .cdb_valid1(cdb_valid1), .cdb_tag1(cdb_tag1), .cdb_value1(cdb_value1), .cdb_rob_idx1(cdb_rob_idx1),
        .stall_alu0(stall_alu0), .stall_alu1(stall_alu1), .stall_fpu0(stall_fpu0), .stall_fpu1(stall_fpu1),
        .stall_lsq0(stall_lsq0), .stall_lsq1(stall_lsq1)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check(input [255:0] label, input [63:0] actual, input [63:0] expected);
        test_num = test_num + 1;
        if (actual === expected) pass_count = pass_count + 1;
        else begin
            $display("FAIL test %0d [%0s]: got %0h exp %0h", test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task check1(input [255:0] label, input actual, input expected);
        test_num = test_num + 1;
        if (actual === expected) pass_count = pass_count + 1;
        else begin
            $display("FAIL test %0d [%0s]: got %0b exp %0b", test_num, label, actual, expected);
            fail_count = fail_count + 1;
        end
    endtask

    task clear_all;
        begin
            v_alu0 = 0; v_alu1 = 0; v_fpu0 = 0; v_fpu1 = 0; v_lsq0 = 0; v_lsq1 = 0;
            t_alu0 = 0; q_alu0 = 0; r_alu0 = 0;
            t_alu1 = 0; q_alu1 = 0; r_alu1 = 0;
            t_fpu0 = 0; q_fpu0 = 0; r_fpu0 = 0;
            t_fpu1 = 0; q_fpu1 = 0; r_fpu1 = 0;
            t_lsq0 = 0; q_lsq0 = 0; r_lsq0 = 0;
            t_lsq1 = 0; q_lsq1 = 0; r_lsq1 = 0;
        end
    endtask

    // Tag each source with a unique pattern for identification
    localparam T_ALU0 = 7'd10;
    localparam T_ALU1 = 7'd11;
    localparam T_FPU0 = 7'd20;
    localparam T_FPU1 = 7'd21;
    localparam T_LSQ0 = 7'd30;
    localparam T_LSQ1 = 7'd31;

    initial begin
        $dumpfile("cdb_tb.vcd");
        $dumpvars(0, cdb_tb);

        reset = 1;
        clear_all;
        @(posedge clk); #1;
        reset = 0;

        // ----------------------------------------------------------
        // TEST 1: Single source ALU0 — bus0 only, no stall
        // ----------------------------------------------------------
        $display("\n--- Test 1: Single ALU0 ---");
        v_alu0 = 1; t_alu0 = T_ALU0; q_alu0 = 64'h100; r_alu0 = 5'd0;
        #1;
        check1("t1 v0", cdb_valid0, 1'b1);
        check("t1 tag0", {57'b0, cdb_tag0}, {57'b0, T_ALU0});
        check("t1 val0", cdb_value0, 64'h100);
        check1("t1 v1", cdb_valid1, 1'b0);
        check1("t1 stall alu0", stall_alu0, 1'b0);

        @(posedge clk); #1;
        clear_all;

        // Realign round-robin pointer for deterministic tests
        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ----------------------------------------------------------
        // TEST 2: ALU0 + ALU1 simultaneous — rr=0 → order 0,1
        // ----------------------------------------------------------
        $display("\n--- Test 2: ALU0 + ALU1 ---");
        v_alu0 = 1; t_alu0 = T_ALU0; q_alu0 = 64'h1; r_alu0 = 5'd1;
        v_alu1 = 1; t_alu1 = T_ALU1; q_alu1 = 64'h2; r_alu1 = 5'd2;
        #1;
        check("t2 tag0", {57'b0, cdb_tag0}, {57'b0, T_ALU0});
        check("t2 tag1", {57'b0, cdb_tag1}, {57'b0, T_ALU1});
        check1("t2 stall0", stall_alu0, 1'b0);
        check1("t2 stall1", stall_alu1, 1'b0);

        @(posedge clk); #1; // rr_ptr ← 2
        clear_all;

        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ----------------------------------------------------------
        // TEST 3: Six simultaneous — rr=0: ALU0/ALU1, then FPU0/FPU1, …
        // ----------------------------------------------------------
        $display("\n--- Test 3: Six sources — 2 grants, 4 stalls ---");
        v_alu0 = 1; t_alu0 = T_ALU0; q_alu0 = 64'hA0; r_alu0 = 5'd0;
        v_alu1 = 1; t_alu1 = T_ALU1; q_alu1 = 64'hA1; r_alu1 = 5'd1;
        v_fpu0 = 1; t_fpu0 = T_FPU0; q_fpu0 = 64'hB0; r_fpu0 = 5'd2;
        v_fpu1 = 1; t_fpu1 = T_FPU1; q_fpu1 = 64'hB1; r_fpu1 = 5'd3;
        v_lsq0 = 1; t_lsq0 = T_LSQ0; q_lsq0 = 64'hC0; r_lsq0 = 5'd4;
        v_lsq1 = 1; t_lsq1 = T_LSQ1; q_lsq1 = 64'hC1; r_lsq1 = 5'd5;
        #1;
        // rr=0: winners ALU0, ALU1 (indices 0,1)
        check("t3 bus0 alu0", {57'b0, cdb_tag0}, {57'b0, T_ALU0});
        check("t3 bus1 alu1", {57'b0, cdb_tag1}, {57'b0, T_ALU1});
        check1("t3 stall alu0", stall_alu0, 1'b0);
        check1("t3 stall alu1", stall_alu1, 1'b0);
        check1("t3 stall fpu0", stall_fpu0, 1'b1);
        check1("t3 stall fpu1", stall_fpu1, 1'b1);
        check1("t3 stall lsq0", stall_lsq0, 1'b1);
        check1("t3 stall lsq1", stall_lsq1, 1'b1);

        @(posedge clk); #1;
        // rr=2: order 2,3,4,5,0,1 → FPU0, FPU1
        #1;
        check("t3b bus0 fpu0", {57'b0, cdb_tag0}, {57'b0, T_FPU0});
        check("t3b bus1 fpu1", {57'b0, cdb_tag1}, {57'b0, T_FPU1});
        check1("t3b stall fpu0", stall_fpu0, 1'b0);
        check1("t3b stall fpu1", stall_fpu1, 1'b0);
        check1("t3b stall alu0", stall_alu0, 1'b1);

        @(posedge clk); #1;
        // rr=4: LSQ0, LSQ1
        #1;
        check("t3c bus0 lsq0", {57'b0, cdb_tag0}, {57'b0, T_LSQ0});
        check("t3c bus1 lsq1", {57'b0, cdb_tag1}, {57'b0, T_LSQ1});
        check1("t3c stall lsq0", stall_lsq0, 1'b0);
        check1("t3c stall lsq1", stall_lsq1, 1'b0);

        @(posedge clk); #1;
        // rr=0: ALU0, ALU1 again
        #1;
        check("t3d bus0 alu0", {57'b0, cdb_tag0}, {57'b0, T_ALU0});
        check("t3d bus1 alu1", {57'b0, cdb_tag1}, {57'b0, T_ALU1});

        @(posedge clk); #1;
        clear_all;

        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ----------------------------------------------------------
        // TEST 4: Isolated FPU1 — rr=0, order 0..3 no valids until index 3
        // ----------------------------------------------------------
        $display("\n--- Test 4: Isolated FPU1 ---");
        v_fpu1 = 1; t_fpu1 = T_FPU1; q_fpu1 = 64'hDE; r_fpu1 = 5'd7;
        #1;
        check("t4 tag0", {57'b0, cdb_tag0}, {57'b0, T_FPU1});
        check1("t4 stall fpu1", stall_fpu1, 1'b0);

        @(posedge clk); #1;
        clear_all;

        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(posedge clk); #1;

        // ----------------------------------------------------------
        // TEST 5: LSQ0 + LSQ1 only — rr=0, first valids at indices 4,5
        // ----------------------------------------------------------
        $display("\n--- Test 5: LSQ pair ---");
        v_lsq0 = 1; t_lsq0 = T_LSQ0; q_lsq0 = 64'h50; r_lsq0 = 5'd8;
        v_lsq1 = 1; t_lsq1 = T_LSQ1; q_lsq1 = 64'h51; r_lsq1 = 5'd9;
        #1;
        check("t5 tag0", {57'b0, cdb_tag0}, {57'b0, T_LSQ0});
        check("t5 tag1", {57'b0, cdb_tag1}, {57'b0, T_LSQ1});

        @(posedge clk); #1;
        clear_all;

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
