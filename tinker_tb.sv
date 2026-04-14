`include "tinker.sv"

module tinker_tb;
    reg clk, reset;
    wire hlt;

    tinker dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    // Instruction format: [opcode:5 | rd:5 | rs:5 | rt:5 | L:12]
    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task store_instr(input [63:0] addr, input [31:0] word);
        begin
            dut.u_mem.bytes[addr + 0] = word[7:0];
            dut.u_mem.bytes[addr + 1] = word[15:8];
            dut.u_mem.bytes[addr + 2] = word[23:16];
            dut.u_mem.bytes[addr + 3] = word[31:24];
        end
    endtask

    task store_dword(input [63:0] addr, input [63:0] data);
        begin
            dut.u_mem.bytes[addr + 0] = data[7:0];
            dut.u_mem.bytes[addr + 1] = data[15:8];
            dut.u_mem.bytes[addr + 2] = data[23:16];
            dut.u_mem.bytes[addr + 3] = data[31:24];
            dut.u_mem.bytes[addr + 4] = data[39:32];
            dut.u_mem.bytes[addr + 5] = data[47:40];
            dut.u_mem.bytes[addr + 6] = data[55:48];
            dut.u_mem.bytes[addr + 7] = data[63:56];
        end
    endtask

    // Opcodes
    localparam OP_AND   = 5'h00, OP_OR    = 5'h01, OP_XOR   = 5'h02, OP_NOT = 5'h03;
    localparam OP_SHFTR = 5'h04, OP_SHFTRI= 5'h05, OP_SHFTL = 5'h06, OP_SHFTLI=5'h07;
    localparam OP_BR    = 5'h08, OP_BRR   = 5'h09, OP_BRR_L = 5'h0a;
    localparam OP_BRNZ  = 5'h0b, OP_CALL  = 5'h0c, OP_RETURN= 5'h0d;
    localparam OP_BRGT  = 5'h0e, OP_HALT  = 5'h0f;
    localparam OP_LOAD  = 5'h10, OP_MOV   = 5'h11, OP_MOVI  = 5'h12, OP_STORE = 5'h13;
    localparam OP_FADD  = 5'h14, OP_FSUB  = 5'h15, OP_FMUL  = 5'h16, OP_FDIV  = 5'h17;
    localparam OP_ADD   = 5'h18, OP_ADDI  = 5'h19, OP_SUB   = 5'h1a, OP_SUBI  = 5'h1b;
    localparam OP_MUL   = 5'h1c, OP_DIV   = 5'h1d;

    integer pass_count, fail_count;
    integer cycle_count;

    task do_reset;
        integer i;
        begin
            reset = 1;
            @(posedge clk);
            #2;
            // Clear instruction memory area
            for (i = 0; i < 128; i = i + 1)
                dut.u_mem.bytes[64'h2000 + i] = 8'd0;
        end
    endtask

    task run_until_halt(input integer max_cycles, output integer cycles);
        begin
            reset = 0;
            cycles = 0;
            while (!hlt && cycles < max_cycles) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task check_reg(input [4:0] regnum, input [63:0] expected, input [8*40:1] test_name);
        reg [63:0] actual;
        begin
            actual = dut.u_arch_rf.registers[regnum];
            if (actual === expected) begin
                $display("  PASS: r%0d = %0d", regnum, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: r%0d = %0d (expected %0d) [%0s]", regnum, actual, expected, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_hlt(input [8*40:1] test_name);
        begin
            if (hlt === 1'b1) begin
                $display("  PASS: hlt asserted");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: hlt not asserted [%0s]", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ================================================================
    // TEST 1: Basic ALU with RAW dependency
    //   addi r1, #5; addi r1, #3; halt
    //   Expect: r1 = 8
    // ================================================================
    task test1_basic_alu;
        begin
            $display("\n=== TEST 1: Basic ALU (RAW dependency) ===");
            do_reset;
            store_instr(64'h2000, mk_instr(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd5));
            store_instr(64'h2004, mk_instr(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd3));
            store_instr(64'h2008, mk_instr(OP_HALT, 5'd0, 5'd0, 5'd0, 12'd0));
            run_until_halt(200, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(1, 64'd8, "test1 r1");
            check_hlt("test1");
        end
    endtask

    // ================================================================
    // TEST 2: Dual-issue independent ALU
    //   addi r1, #10; addi r2, #20; halt
    //   Expect: r1=10, r2=20
    // ================================================================
    task test2_dual_issue;
        begin
            $display("\n=== TEST 2: Dual-issue independent ALU ===");
            do_reset;
            store_instr(64'h2000, mk_instr(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd10));
            store_instr(64'h2004, mk_instr(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd20));
            store_instr(64'h2008, mk_instr(OP_HALT, 5'd0, 5'd0, 5'd0, 12'd0));
            run_until_halt(200, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(1, 64'd10, "test2 r1");
            check_reg(2, 64'd20, "test2 r2");
            check_hlt("test2");
        end
    endtask

    // ================================================================
    // TEST 3: Load / Store
    //   movi r1, #100; store (r0)(0), r1; load r3, (r0)(0); halt
    //   Expect: r3 = 100
    // ================================================================
    task test3_load_store;
        begin
            $display("\n=== TEST 3: Load / Store ===");
            do_reset;
            // movi r1, #100 → r1[11:0] = 100
            store_instr(64'h2000, mk_instr(OP_MOVI, 5'd1, 5'd0, 5'd0, 12'd100));
            // store (r0)(0), r1 → mem[r0+0] = r1   {5'h13, rd=0, rs=1, rt=0, L=0}
            store_instr(64'h2004, mk_instr(OP_STORE, 5'd0, 5'd1, 5'd0, 12'd0));
            // load r3, (r0)(0) → r3 = mem[r0+0]    {5'h10, rd=3, rs=0, rt=0, L=0}
            store_instr(64'h2008, mk_instr(OP_LOAD, 5'd3, 5'd0, 5'd0, 12'd0));
            // halt
            store_instr(64'h200c, mk_instr(OP_HALT, 5'd0, 5'd0, 5'd0, 12'd0));
            run_until_halt(500, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(3, 64'd100, "test3 r3");
            check_hlt("test3");
        end
    endtask

    // ================================================================
    // TEST 4: Branch (BRNZ taken)
    //   movi r1, #1;                 (0x2000)
    //   brnz r1, r4                  (0x2004) where r4=target=0x2010
    //   addi r2, #99;                (0x2008) ← should NOT commit
    //   addi r2, #99;                (0x200c) ← padding (should NOT commit)
    //   target: addi r3, #42;        (0x2010)
    //   halt                         (0x2014)
    //
    //   For BRNZ: src1=rs(condition), src2=rd(target addr)
    //   Encoding: {OP_BRNZ, rd, rs, rt, L}
    //   We need rd to hold the target. Set r4=0x2010 first.
    //
    //   Revised program:
    //   0x2000: movi r1, #1         r1 = 1 (condition)
    //   0x2004: movi r4, #0x10      r4[11:0] = 0x10 (low 12 bits of 0x2010)
    //   0x2008: movi r4, #0x10      NOP-like (re-movi same value, just padding)
    //   Wait: MOVI sets r4[11:0]=0x10, r4[63:12]=0. But target 0x2010
    //   requires encoding the full address. Since r4 starts as 0, movi
    //   will give r4 = 0x010. But 0x2010 doesn't fit in 12 bits.
    //
    //   Simpler approach: use BRR_L (relative branch, unconditional) to
    //   jump over the dead code:
    //   0x2000: movi r1, #1
    //   0x2004: brnz r1, r4  → but r4 must hold 0x2010...
    //
    //   Even simpler: use relative branch with BRR L:
    //   0x2000: movi r1, #42         r1 = 42
    //   0x2004: brr_l #8             pc += 8 → jumps to 0x200c
    //   0x2008: movi r2, #99         ← should NOT commit (flushed)
    //   0x200c: halt
    //   Expect: r1=42, r2=0
    // ================================================================
    task test4_branch;
        begin
            $display("\n=== TEST 4: Branch (BRR_L unconditional relative) ===");
            do_reset;
            // movi r1, #42
            store_instr(64'h2000, mk_instr(OP_MOVI, 5'd1, 5'd0, 5'd0, 12'd42));
            // brr_l #8: PC-relative jump, target = PC + imm = 0x2004 + 8 = 0x200c
            store_instr(64'h2004, mk_instr(OP_BRR_L, 5'd0, 5'd0, 5'd0, 12'd8));
            // This instruction is after the branch; it should be flushed
            store_instr(64'h2008, mk_instr(OP_MOVI, 5'd2, 5'd0, 5'd0, 12'd99));
            // Target: halt
            store_instr(64'h200c, mk_instr(OP_HALT, 5'd0, 5'd0, 5'd0, 12'd0));
            run_until_halt(500, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(1, 64'd42, "test4 r1");
            check_reg(2, 64'd0, "test4 r2 (should not commit)");
            check_hlt("test4");
        end
    endtask

    // ================================================================
    // TEST 5: FPU (FADD)
    //   Pre-load two IEEE 754 doubles into memory, load them into
    //   registers, do FADD, verify result.
    //   1.5 + 2.5 = 4.0
    //   IEEE 754: 1.5 = 64'h3FF8000000000000
    //             2.5 = 64'h4004000000000000
    //             4.0 = 64'h4010000000000000
    // ================================================================
    task test5_fpu;
        begin
            $display("\n=== TEST 5: FPU (FADD 1.5 + 2.5 = 4.0) ===");
            do_reset;
            // Pre-store doubles in data memory
            store_dword(64'h3000, 64'h3FF8000000000000);  // 1.5 at addr 0x3000
            store_dword(64'h3008, 64'h4004000000000000);  // 2.5 at addr 0x3008
            // Program:
            // movi r4, addr-low for 0x3000: need to set r4 = 0x3000
            // Can't fit 0x3000 in 12-bit immediate directly.
            // Use addi sequence: addi r4, #0; then shift left, etc.
            // Simpler: use movi + shftli to build address
            // r4 = 0x3000 = 0x3 << 12
            // movi r4, #0    → r4 = 0
            // addi r4, #3    → r4 = 3
            // shftli r4, #12 → r4 = 0x3000
            store_instr(64'h2000, mk_instr(OP_ADDI, 5'd4, 5'd0, 5'd0, 12'd3));
            store_instr(64'h2004, mk_instr(OP_SHFTLI, 5'd4, 5'd0, 5'd0, 12'd12));
            // load r1, (r4)(0) → r1 = mem[0x3000] = 1.5
            store_instr(64'h2008, mk_instr(OP_LOAD, 5'd1, 5'd4, 5'd0, 12'd0));
            // load r2, (r4)(8) → r2 = mem[0x3008] = 2.5
            store_instr(64'h200c, mk_instr(OP_LOAD, 5'd2, 5'd4, 5'd0, 12'd8));
            // fadd r3, r1, r2 → r3 = 1.5 + 2.5 = 4.0
            store_instr(64'h2010, mk_instr(OP_FADD, 5'd3, 5'd1, 5'd2, 12'd0));
            // halt
            store_instr(64'h2014, mk_instr(OP_HALT, 5'd0, 5'd0, 5'd0, 12'd0));
            run_until_halt(1000, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(3, 64'h4010000000000000, "test5 r3 (fadd)");
            check_hlt("test5");
        end
    endtask

    // ================================================================
    // TEST 6: Mixed ILP — 6 independent ALU instructions
    //   addi r1, #1; addi r2, #2; addi r3, #3;
    //   addi r4, #4; addi r5, #5; addi r6, #6; halt
    //   All independent — should see maximum throughput.
    // ================================================================
    task test6_mixed_ilp;
        begin
            $display("\n=== TEST 6: Mixed ILP (6 independent ADDI) ===");
            do_reset;
            store_instr(64'h2000, mk_instr(OP_ADDI, 5'd1,  5'd0, 5'd0, 12'd1));
            store_instr(64'h2004, mk_instr(OP_ADDI, 5'd2,  5'd0, 5'd0, 12'd2));
            store_instr(64'h2008, mk_instr(OP_ADDI, 5'd3,  5'd0, 5'd0, 12'd3));
            store_instr(64'h200c, mk_instr(OP_ADDI, 5'd4,  5'd0, 5'd0, 12'd4));
            store_instr(64'h2010, mk_instr(OP_ADDI, 5'd5,  5'd0, 5'd0, 12'd5));
            store_instr(64'h2014, mk_instr(OP_ADDI, 5'd6,  5'd0, 5'd0, 12'd6));
            store_instr(64'h2018, mk_instr(OP_HALT, 5'd0,  5'd0, 5'd0, 12'd0));
            run_until_halt(300, cycle_count);
            $display("  Completed in %0d cycles", cycle_count);
            check_reg(1, 64'd1, "test6 r1");
            check_reg(2, 64'd2, "test6 r2");
            check_reg(3, 64'd3, "test6 r3");
            check_reg(4, 64'd4, "test6 r4");
            check_reg(5, 64'd5, "test6 r5");
            check_reg(6, 64'd6, "test6 r6");
            check_hlt("test6");
        end
    endtask

    // ================================================================
    // Main test driver
    // ================================================================
    initial begin
        $dumpfile("tinker_tb.vcd");
        $dumpvars(0, tinker_tb);

        clk = 0; reset = 1;
        pass_count = 0;
        fail_count = 0;

        test1_basic_alu;
        test2_dual_issue;
        test3_load_store;
        test4_branch;
        test5_fpu;
        test6_mixed_ilp;

        $display("\n========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end
endmodule
