// Smoke-test bench for alu_pipe and fpu_pipe.
// Verifies that results appear at the correct pipeline stage and that
// branch misprediction / flush / MOVI work as expected.

`timescale 1ns/1ps
`include "alu_pipe.sv"
`include "fpu_pipe.sv"

module eu_tb;

    reg         clk, reset, flush;
    integer     pass_count = 0;
    integer     fail_count = 0;
    integer     test_num   = 0;

    // ================================================================
    // ALU pipe instance
    // ================================================================
    reg         alu_valid_in;
    reg  [4:0]  alu_opcode;
    reg  [63:0] alu_src1, alu_src2, alu_imm, alu_pc;
    reg  [6:0]  alu_dest_tag;
    reg  [4:0]  alu_rob_idx;
    reg         alu_br_pred;

    wire        alu_valid_out;
    wire [6:0]  alu_dest_tag_out;
    wire [4:0]  alu_rob_idx_out;
    wire [63:0] alu_result_out;
    wire        alu_is_branch;
    wire        alu_branch_taken;
    wire [63:0] alu_branch_target;
    wire        alu_mispredict;

    alu_pipe u_alu (
        .clk              (clk),
        .reset            (reset),
        .flush            (flush),
        .valid_in         (alu_valid_in),
        .opcode_in        (alu_opcode),
        .src1_in          (alu_src1),
        .src2_in          (alu_src2),
        .dest_tag_in      (alu_dest_tag),
        .rob_idx_in       (alu_rob_idx),
        .imm_in           (alu_imm),
        .pc_in            (alu_pc),
        .br_pred_taken_in (alu_br_pred),
        .valid_out        (alu_valid_out),
        .dest_tag_out     (alu_dest_tag_out),
        .rob_idx_out      (alu_rob_idx_out),
        .result_out       (alu_result_out),
        .is_branch_out    (alu_is_branch),
        .branch_taken_out (alu_branch_taken),
        .branch_target_out(alu_branch_target),
        .mispredict_out   (alu_mispredict)
    );

    // ================================================================
    // FPU pipe instance
    // ================================================================
    reg         fpu_valid_in;
    reg  [4:0]  fpu_opcode;
    reg  [63:0] fpu_src1, fpu_src2;
    reg  [6:0]  fpu_dest_tag;
    reg  [4:0]  fpu_rob_idx;

    wire        fpu_valid_out;
    wire [6:0]  fpu_dest_tag_out;
    wire [4:0]  fpu_rob_idx_out;
    wire [63:0] fpu_result_out;

    fpu_pipe u_fpu (
        .clk        (clk),
        .reset      (reset),
        .flush      (flush),
        .valid_in   (fpu_valid_in),
        .opcode_in  (fpu_opcode),
        .src1_in    (fpu_src1),
        .src2_in    (fpu_src2),
        .dest_tag_in(fpu_dest_tag),
        .rob_idx_in (fpu_rob_idx),
        .valid_out  (fpu_valid_out),
        .dest_tag_out(fpu_dest_tag_out),
        .rob_idx_out (fpu_rob_idx_out),
        .result_out  (fpu_result_out)
    );

    // ================================================================
    // Clock generation
    // ================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // ================================================================
    // Check helper
    // ================================================================
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

    // Helper: clear ALU inputs
    task alu_clear;
        begin
            alu_valid_in = 0; alu_opcode = 0;
            alu_src1 = 0; alu_src2 = 0; alu_imm = 0; alu_pc = 0;
            alu_dest_tag = 0; alu_rob_idx = 0; alu_br_pred = 0;
        end
    endtask

    // Helper: clear FPU inputs
    task fpu_clear;
        begin
            fpu_valid_in = 0; fpu_opcode = 0;
            fpu_src1 = 0; fpu_src2 = 0;
            fpu_dest_tag = 0; fpu_rob_idx = 0;
        end
    endtask

    // ================================================================
    // Tests
    // ================================================================
    initial begin
        $dumpfile("sim/eu_tb.vcd");
        $dumpvars(0, eu_tb);

        // Reset
        reset = 1; flush = 0;
        alu_clear; fpu_clear;
        @(posedge clk); #1;
        reset = 0;

        // ============================================================
        // TEST 1: ALU ADD — result appears at stage 2 (2 cycles later)
        // ============================================================
        $display("\n--- Test 1: ALU ADD ---");
        alu_valid_in = 1; alu_opcode = 5'h18; // ADD
        alu_src1 = 64'd100; alu_src2 = 64'd200;
        alu_dest_tag = 7'd10; alu_rob_idx = 5'd3;
        alu_imm = 0; alu_pc = 64'h1000; alu_br_pred = 0;
        @(posedge clk); #1;
        alu_clear;

        // Cycle after issue: stage 1 has the instruction, stage 2 empty
        check1("add s2 not valid yet", alu_valid_out, 1'b0);
        @(posedge clk); #1;
        // Now stage 2 has the result
        check1("add s2 valid", alu_valid_out, 1'b1);
        check("add result", alu_result_out, 64'd300);
        check("add dest_tag", {57'b0, alu_dest_tag_out}, {57'b0, 7'd10});
        check("add rob_idx", {59'b0, alu_rob_idx_out}, {59'b0, 5'd3});
        check1("add not branch", alu_is_branch, 1'b0);

        @(posedge clk); #1;
        check1("add drained", alu_valid_out, 1'b0);

        // ============================================================
        // TEST 2: ALU SUB
        // ============================================================
        $display("\n--- Test 2: ALU SUB ---");
        alu_valid_in = 1; alu_opcode = 5'h1a; // SUB
        alu_src1 = 64'd500; alu_src2 = 64'd123;
        alu_dest_tag = 7'd20; alu_rob_idx = 5'd7;
        alu_imm = 0; alu_pc = 64'h2000; alu_br_pred = 0;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("sub valid", alu_valid_out, 1'b1);
        check("sub result", alu_result_out, 64'd377);

        @(posedge clk); #1;

        // ============================================================
        // TEST 3: ALU ADDI (reg + imm)
        // ============================================================
        $display("\n--- Test 3: ALU ADDI ---");
        alu_valid_in = 1; alu_opcode = 5'h19; // ADDI
        alu_src1 = 64'd50; alu_imm = 64'd12;
        alu_dest_tag = 7'd5; alu_rob_idx = 5'd1;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("addi valid", alu_valid_out, 1'b1);
        check("addi result", alu_result_out, 64'd62);

        @(posedge clk); #1;

        // ============================================================
        // TEST 4: ALU AND / OR / XOR / NOT
        // ============================================================
        $display("\n--- Test 4: ALU logic ops ---");
        // AND
        alu_valid_in = 1; alu_opcode = 5'h00;
        alu_src1 = 64'hFF00FF00; alu_src2 = 64'h0F0F0F0F;
        alu_dest_tag = 7'd1; alu_rob_idx = 5'd0;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("and result", alu_result_out, 64'h0F000F00);

        @(posedge clk); #1;

        // OR
        alu_valid_in = 1; alu_opcode = 5'h01;
        alu_src1 = 64'hFF00FF00; alu_src2 = 64'h0F0F0F0F;
        alu_dest_tag = 7'd2; alu_rob_idx = 5'd1;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("or result", alu_result_out, 64'hFF0FFF0F);

        @(posedge clk); #1;

        // NOT
        alu_valid_in = 1; alu_opcode = 5'h03;
        alu_src1 = 64'h0;
        alu_dest_tag = 7'd3; alu_rob_idx = 5'd2;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("not result", alu_result_out, 64'hFFFFFFFFFFFFFFFF);

        @(posedge clk); #1;

        // ============================================================
        // TEST 5: ALU SHFTL / SHFTR
        // ============================================================
        $display("\n--- Test 5: ALU shifts ---");
        alu_valid_in = 1; alu_opcode = 5'h06; // SHFTL
        alu_src1 = 64'd1; alu_src2 = 64'd10;
        alu_dest_tag = 7'd4; alu_rob_idx = 5'd0;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("shftl result", alu_result_out, 64'd1024);

        @(posedge clk); #1;

        alu_valid_in = 1; alu_opcode = 5'h04; // SHFTR
        alu_src1 = 64'd1024; alu_src2 = 64'd4;
        alu_dest_tag = 7'd5; alu_rob_idx = 5'd1;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("shftr result", alu_result_out, 64'd64);

        @(posedge clk); #1;

        // ============================================================
        // TEST 6: MOVI — read-modify-write
        // ============================================================
        $display("\n--- Test 6: MOVI ---");
        alu_valid_in = 1; alu_opcode = 5'h12; // MOVI
        alu_src1 = 64'hDEADBEEFCAFE0000;    // rd old value
        alu_imm  = 64'hFFFFFFFFFFFFF123;      // sign-ext L, lower 12 = 0x123
        alu_dest_tag = 7'd30; alu_rob_idx = 5'd5;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("movi valid", alu_valid_out, 1'b1);
        check("movi result", alu_result_out, 64'hDEADBEEFCAFE0123);

        @(posedge clk); #1;

        // ============================================================
        // TEST 7: MOV rd, rs
        // ============================================================
        $display("\n--- Test 7: MOV ---");
        alu_valid_in = 1; alu_opcode = 5'h11;
        alu_src1 = 64'h42;
        alu_dest_tag = 7'd31; alu_rob_idx = 5'd6;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check("mov result", alu_result_out, 64'h42);

        @(posedge clk); #1;

        // ============================================================
        // TEST 8: Branch — BRNZ predicted not-taken, actually taken → mispredict
        // ============================================================
        $display("\n--- Test 8: BRNZ mispredict ---");
        alu_valid_in = 1; alu_opcode = 5'h0b; // BRNZ
        alu_src1 = 64'd1;                       // rs != 0 → taken
        alu_src2 = 64'h8000;                    // rd = target
        alu_br_pred = 1'b0;                      // predicted not-taken
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd8;
        alu_pc = 64'h4000;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("brnz valid", alu_valid_out, 1'b1);
        check1("brnz is_branch", alu_is_branch, 1'b1);
        check1("brnz taken", alu_branch_taken, 1'b1);
        check("brnz target", alu_branch_target, 64'h8000);
        check1("brnz mispredict", alu_mispredict, 1'b1);

        @(posedge clk); #1;

        // ============================================================
        // TEST 9: Branch — BRNZ predicted not-taken, actually not-taken → correct
        // ============================================================
        $display("\n--- Test 9: BRNZ correct prediction ---");
        alu_valid_in = 1; alu_opcode = 5'h0b;
        alu_src1 = 64'd0;                       // rs == 0 → not taken
        alu_src2 = 64'h8000;
        alu_br_pred = 1'b0;                      // predicted not-taken
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd9;
        alu_pc = 64'h4004;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("brnz correct valid", alu_valid_out, 1'b1);
        check1("brnz not taken", alu_branch_taken, 1'b0);
        check1("brnz no mispredict", alu_mispredict, 1'b0);

        @(posedge clk); #1;

        // ============================================================
        // TEST 10: BRGT — mispredict
        // ============================================================
        $display("\n--- Test 10: BRGT mispredict ---");
        alu_valid_in = 1; alu_opcode = 5'h0e; // BRGT
        alu_src1 = 64'd50;                      // rs > rt → taken
        alu_src2 = 64'd10;                      // rt
        alu_imm  = 64'hBEEF;                    // rd (target)
        alu_br_pred = 1'b0;
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd10;
        alu_pc = 64'h5000;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("brgt taken", alu_branch_taken, 1'b1);
        check("brgt target", alu_branch_target, 64'hBEEF);
        check1("brgt mispredict", alu_mispredict, 1'b1);

        @(posedge clk); #1;

        // ============================================================
        // TEST 11: BRR_L — unconditional PC-relative
        // ============================================================
        $display("\n--- Test 11: BRR_L ---");
        alu_valid_in = 1; alu_opcode = 5'h0a; // BRR L
        alu_imm  = -64'sd16;                    // offset = -16
        alu_br_pred = 1'b1;                      // predicted taken
        alu_pc = 64'h6000;
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd11;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("brr_l taken", alu_branch_taken, 1'b1);
        check("brr_l target", alu_branch_target, 64'h6000 - 64'd16);
        check1("brr_l no mispredict", alu_mispredict, 1'b0);

        @(posedge clk); #1;

        // ============================================================
        // TEST 12: Flush clears both stages
        // ============================================================
        $display("\n--- Test 12: Flush ---");
        // Issue two ALU instructions back-to-back
        alu_valid_in = 1; alu_opcode = 5'h18;
        alu_src1 = 64'd1; alu_src2 = 64'd2;
        alu_dest_tag = 7'd40; alu_rob_idx = 5'd12;
        @(posedge clk); #1;
        // Second instruction
        alu_opcode = 5'h18;
        alu_src1 = 64'd3; alu_src2 = 64'd4;
        alu_dest_tag = 7'd41; alu_rob_idx = 5'd13;
        @(posedge clk); #1;
        alu_clear;
        // Now stage 1 has inst2, stage 2 has inst1
        // Assert flush
        flush = 1;
        @(posedge clk); #1;
        flush = 0;
        // Both stages should be invalid
        check1("flush s2 invalid", alu_valid_out, 1'b0);
        @(posedge clk); #1;
        check1("flush still clear", alu_valid_out, 1'b0);

        @(posedge clk); #1;

        // ============================================================
        // TEST 13: Pipeline throughput — back-to-back instructions
        // ============================================================
        $display("\n--- Test 13: ALU back-to-back throughput ---");
        // Issue inst A
        alu_valid_in = 1; alu_opcode = 5'h18;
        alu_src1 = 64'd10; alu_src2 = 64'd20;
        alu_dest_tag = 7'd50; alu_rob_idx = 5'd14;
        @(posedge clk); #1;
        // Issue inst B (A is now in stage 1)
        alu_src1 = 64'd30; alu_src2 = 64'd40;
        alu_dest_tag = 7'd51; alu_rob_idx = 5'd15;
        @(posedge clk); #1;
        alu_clear;
        // A should be at stage 2 now
        check1("throughput A valid", alu_valid_out, 1'b1);
        check("throughput A result", alu_result_out, 64'd30);
        check("throughput A tag", {57'b0, alu_dest_tag_out}, {57'b0, 7'd50});
        @(posedge clk); #1;
        // B should be at stage 2 now
        check1("throughput B valid", alu_valid_out, 1'b1);
        check("throughput B result", alu_result_out, 64'd70);
        check("throughput B tag", {57'b0, alu_dest_tag_out}, {57'b0, 7'd51});

        @(posedge clk); #1;

        // ============================================================
        // TEST 14: FPU FADD — 2-stage pipe: result after 2 cycles from issue
        // ============================================================
        $display("\n--- Test 14: FPU FADD ---");
        // 2.0 + 3.0 = 5.0 in IEEE-754
        fpu_valid_in = 1; fpu_opcode = 5'h14; // FADD
        fpu_src1 = 64'h4000000000000000;  // 2.0
        fpu_src2 = 64'h4008000000000000;  // 3.0
        fpu_dest_tag = 7'd60; fpu_rob_idx = 5'd16;
        @(posedge clk); #1; fpu_clear;

        check1("fadd s1 not out", fpu_valid_out, 1'b0);
        @(posedge clk); #1;
        check1("fadd s2 valid", fpu_valid_out, 1'b1);
        check("fadd result", fpu_result_out, 64'h4014000000000000); // 5.0
        check("fadd dest_tag", {57'b0, fpu_dest_tag_out}, {57'b0, 7'd60});

        @(posedge clk); #1;
        check1("fadd drained", fpu_valid_out, 1'b0);

        // ============================================================
        // TEST 15: FPU FMUL — 2.0 * 3.0 = 6.0
        // ============================================================
        $display("\n--- Test 15: FPU FMUL ---");
        fpu_valid_in = 1; fpu_opcode = 5'h16; // FMUL
        fpu_src1 = 64'h4000000000000000;  // 2.0
        fpu_src2 = 64'h4008000000000000;  // 3.0
        fpu_dest_tag = 7'd61; fpu_rob_idx = 5'd17;
        @(posedge clk); #1; fpu_clear;
        @(posedge clk); #1;
        check1("fmul valid", fpu_valid_out, 1'b1);
        check("fmul result", fpu_result_out, 64'h4018000000000000); // 6.0

        @(posedge clk); #1;

        // ============================================================
        // TEST 16: FPU flush clears both stages
        // ============================================================
        $display("\n--- Test 16: FPU flush ---");
        fpu_valid_in = 1; fpu_opcode = 5'h14;
        fpu_src1 = 64'h4000000000000000; fpu_src2 = 64'h4000000000000000;
        fpu_dest_tag = 7'd70; fpu_rob_idx = 5'd18;
        @(posedge clk); #1;
        // second instruction
        fpu_src1 = 64'h4008000000000000; fpu_src2 = 64'h4008000000000000;
        fpu_dest_tag = 7'd71; fpu_rob_idx = 5'd19;
        @(posedge clk); #1;
        fpu_clear;
        // Flush
        flush = 1;
        @(posedge clk); #1;
        flush = 0;
        check1("fpu flush out", fpu_valid_out, 1'b0);
        @(posedge clk); #1;
        check1("fpu flush +1", fpu_valid_out, 1'b0);

        @(posedge clk); #1;

        // ============================================================
        // TEST 17: FPU back-to-back throughput
        // ============================================================
        $display("\n--- Test 17: FPU throughput ---");
        // Issue A
        fpu_valid_in = 1; fpu_opcode = 5'h14; // FADD
        fpu_src1 = 64'h3FF0000000000000;  // 1.0
        fpu_src2 = 64'h3FF0000000000000;  // 1.0
        fpu_dest_tag = 7'd80; fpu_rob_idx = 5'd20;
        @(posedge clk); #1;
        // Issue B
        fpu_src1 = 64'h4000000000000000;  // 2.0
        fpu_src2 = 64'h4000000000000000;  // 2.0
        fpu_dest_tag = 7'd81; fpu_rob_idx = 5'd21;
        @(posedge clk); #1;
        fpu_clear;
        @(posedge clk); #1;
        // A should appear (2-stage latency from its issue)
        check1("fpu thrpt A valid", fpu_valid_out, 1'b1);
        check("fpu thrpt A result", fpu_result_out, 64'h4000000000000000); // 2.0
        check("fpu thrpt A tag", {57'b0, fpu_dest_tag_out}, {57'b0, 7'd80});
        @(posedge clk); #1;
        // B should appear
        check1("fpu thrpt B valid", fpu_valid_out, 1'b1);
        check("fpu thrpt B result", fpu_result_out, 64'h4010000000000000); // 4.0
        check("fpu thrpt B tag", {57'b0, fpu_dest_tag_out}, {57'b0, 7'd81});

        @(posedge clk); #1;

        // ============================================================
        // TEST 18: ALU CALL — unconditional branch to src1
        // ============================================================
        $display("\n--- Test 18: CALL ---");
        alu_valid_in = 1; alu_opcode = 5'h0c;
        alu_src1 = 64'hABCD0000;  // call target
        alu_br_pred = 1'b1;        // predicted taken
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd22;
        alu_pc = 64'h7000;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("call is_branch", alu_is_branch, 1'b1);
        check1("call taken", alu_branch_taken, 1'b1);
        check("call target", alu_branch_target, 64'hABCD0000);
        check1("call no mispredict", alu_mispredict, 1'b0);

        @(posedge clk); #1;

        // ============================================================
        // TEST 19: ALU RETURN — branch to loaded address (src1)
        // ============================================================
        $display("\n--- Test 19: RETURN ---");
        alu_valid_in = 1; alu_opcode = 5'h0d;
        alu_src1 = 64'h7004;      // return address (loaded from memory)
        alu_br_pred = 1'b1;
        alu_dest_tag = 7'd0; alu_rob_idx = 5'd23;
        alu_pc = 64'hABCD0000;
        @(posedge clk); #1; alu_clear;
        @(posedge clk); #1;
        check1("return taken", alu_branch_taken, 1'b1);
        check("return target", alu_branch_target, 64'h7004);
        check1("return no mispredict", alu_mispredict, 1'b0);

        @(posedge clk); #1;

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
