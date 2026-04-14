`include "phys_reg_file.sv"
`include "free_list.sv"
`include "rat.sv"

module rat_tb;
    reg clk, reset;

    // ---- Free list signals ----
    reg        fl_alloc0, fl_alloc1;
    wire [6:0] fl_reg0, fl_reg1;
    reg        fl_free0, fl_free1;
    reg  [6:0] fl_free_reg0, fl_free_reg1;
    wire       fl_empty, fl_almost_empty;

    free_list fl (
        .clk(clk), .reset(reset),
        .alloc_en0(fl_alloc0), .alloc_en1(fl_alloc1),
        .alloc_reg0(fl_reg0),  .alloc_reg1(fl_reg1),
        .free_en0(fl_free0),   .free_reg0(fl_free_reg0),
        .free_en1(fl_free1),   .free_reg1(fl_free_reg1),
        .empty(fl_empty),      .almost_empty(fl_almost_empty)
    );

    // ---- Physical register file signals ----
    reg  [6:0]  prf_ra0, prf_ra1, prf_ra2, prf_ra3;
    wire [63:0] prf_rd0, prf_rd1, prf_rd2, prf_rd3;
    wire        prf_rr0, prf_rr1, prf_rr2, prf_rr3;
    reg         prf_we0, prf_we1;
    reg  [6:0]  prf_wa0, prf_wa1;
    reg  [63:0] prf_wd0, prf_wd1;
    reg         prf_cr0, prf_cr1;
    reg  [6:0]  prf_ca0, prf_ca1;

    phys_reg_file prf (
        .clk(clk), .reset(reset),
        .read_addr0(prf_ra0), .read_data0(prf_rd0), .read_ready0(prf_rr0),
        .read_addr1(prf_ra1), .read_data1(prf_rd1), .read_ready1(prf_rr1),
        .read_addr2(prf_ra2), .read_data2(prf_rd2), .read_ready2(prf_rr2),
        .read_addr3(prf_ra3), .read_data3(prf_rd3), .read_ready3(prf_rr3),
        .write_en0(prf_we0), .write_addr0(prf_wa0), .write_data0(prf_wd0),
        .write_en1(prf_we1), .write_addr1(prf_wa1), .write_data1(prf_wd1),
        .clear_ready_en0(prf_cr0), .clear_ready_addr0(prf_ca0),
        .clear_ready_en1(prf_cr1), .clear_ready_addr1(prf_ca1)
    );

    // ---- RAT signals ----
    reg  [4:0] rat_la0, rat_la1, rat_la2, rat_la3;
    wire [6:0] rat_lp0, rat_lp1, rat_lp2, rat_lp3;
    reg        rat_ren_a, rat_ren_b;
    reg  [4:0] rat_ra_a, rat_ra_b;
    reg  [6:0] rat_rp_a, rat_rp_b;
    wire [6:0] rat_old_a, rat_old_b;
    reg        rat_chk, rat_rst;

    rat rat_dut (
        .clk(clk), .reset(reset),
        .lookup_arch0(rat_la0), .lookup_phys0(rat_lp0),
        .lookup_arch1(rat_la1), .lookup_phys1(rat_lp1),
        .lookup_arch2(rat_la2), .lookup_phys2(rat_lp2),
        .lookup_arch3(rat_la3), .lookup_phys3(rat_lp3),
        .rename_en_a(rat_ren_a), .rename_arch_a(rat_ra_a), .rename_phys_a(rat_rp_a), .rename_old_a(rat_old_a),
        .rename_en_b(rat_ren_b), .rename_arch_b(rat_ra_b), .rename_phys_b(rat_rp_b), .rename_old_b(rat_old_b),
        .checkpoint_en(rat_chk), .restore_en(rat_rst)
    );

    always #5 clk = ~clk;

    integer pass_count, fail_count;

    task check(input [63:0] got, input [63:0] expected, input [255:0] name);
        if (got === expected) begin
            $display("PASS %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL %0s: got %0d, expected %0d", name, got, expected);
            fail_count = fail_count + 1;
        end
    endtask

    initial begin
        $dumpfile("rat_tb.vcd");
        $dumpvars(0, rat_tb);

        clk = 0; reset = 1;
        fl_alloc0 = 0; fl_alloc1 = 0;
        fl_free0 = 0; fl_free1 = 0;
        fl_free_reg0 = 0; fl_free_reg1 = 0;
        prf_ra0 = 0; prf_ra1 = 0; prf_ra2 = 0; prf_ra3 = 0;
        prf_we0 = 0; prf_we1 = 0;
        prf_wa0 = 0; prf_wa1 = 0; prf_wd0 = 0; prf_wd1 = 0;
        prf_cr0 = 0; prf_cr1 = 0; prf_ca0 = 0; prf_ca1 = 0;
        rat_la0 = 0; rat_la1 = 0; rat_la2 = 0; rat_la3 = 0;
        rat_ren_a = 0; rat_ren_b = 0;
        rat_ra_a = 0; rat_ra_b = 0; rat_rp_a = 0; rat_rp_b = 0;
        rat_chk = 0; rat_rst = 0;
        pass_count = 0; fail_count = 0;

        #10 reset = 0;

        // ============================================================
        // Physical Register File tests
        // ============================================================

        // After reset, all registers ready
        prf_ra0 = 7'd0; prf_ra1 = 7'd31; prf_ra2 = 7'd50; prf_ra3 = 7'd127;
        #1;
        check({63'd0, prf_rr0}, 64'd1, "prf reg0 ready");
        check({63'd0, prf_rr2}, 64'd1, "prf reg50 ready");
        check(prf_rd0, 64'd0, "prf reg0 value=0");

        // Write to reg 40, then read back
        @(negedge clk);
        prf_we0 = 1; prf_wa0 = 7'd40; prf_wd0 = 64'hFACE;
        @(negedge clk);
        prf_we0 = 0;
        prf_ra0 = 7'd40;
        #1;
        check(prf_rd0, 64'hFACE, "prf write/read");

        // Clear ready, verify it goes low
        @(negedge clk);
        prf_cr0 = 1; prf_ca0 = 7'd60;
        @(negedge clk);
        prf_cr0 = 0;
        prf_ra1 = 7'd60;
        #1;
        check({63'd0, prf_rr1}, 64'd0, "prf clear_ready");

        // Write to same reg restores ready
        @(negedge clk);
        prf_we0 = 1; prf_wa0 = 7'd60; prf_wd0 = 64'hBEEF;
        @(negedge clk);
        prf_we0 = 0;
        prf_ra1 = 7'd60;
        #1;
        check(prf_rd1, 64'hBEEF, "prf write restores ready val");
        check({63'd0, prf_rr1}, 64'd1, "prf write restores ready bit");

        // Dual write: port 1 wins on conflict
        @(negedge clk);
        prf_we0 = 1; prf_wa0 = 7'd70; prf_wd0 = 64'hAAAA;
        prf_we1 = 1; prf_wa1 = 7'd70; prf_wd1 = 64'hBBBB;
        @(negedge clk);
        prf_we0 = 0; prf_we1 = 0;
        prf_ra0 = 7'd70;
        #1;
        check(prf_rd0, 64'hBBBB, "prf dual write conflict port1 wins");

        // ============================================================
        // Free List tests
        // ============================================================

        // After reset: 96 entries, first alloc should give 32
        check({57'd0, fl_reg0}, 64'd32, "fl first alloc_reg0");
        check({57'd0, fl_reg1}, 64'd33, "fl first alloc_reg1");
        check({63'd0, fl_empty}, 64'd0, "fl not empty");

        // Allocate 2
        @(negedge clk);
        fl_alloc0 = 1; fl_alloc1 = 1;
        @(negedge clk);
        fl_alloc0 = 0; fl_alloc1 = 0;
        #1;
        // Next alloc should give 34, 35
        check({57'd0, fl_reg0}, 64'd34, "fl after alloc2 reg0=34");
        check({57'd0, fl_reg1}, 64'd35, "fl after alloc2 reg1=35");

        // Allocate 1 more
        @(negedge clk);
        fl_alloc0 = 1; fl_alloc1 = 0;
        @(negedge clk);
        fl_alloc0 = 0;
        #1;
        check({57'd0, fl_reg0}, 64'd35, "fl after alloc1 reg0=35");

        // Free a register (push 32 back)
        @(negedge clk);
        fl_free0 = 1; fl_free_reg0 = 7'd32;
        @(negedge clk);
        fl_free0 = 0;

        // ============================================================
        // RAT tests
        // ============================================================

        // Identity mapping on reset: arch reg i -> phys reg i
        rat_la0 = 5'd0;  rat_la1 = 5'd5;
        rat_la2 = 5'd31; rat_la3 = 5'd15;
        #1;
        check({57'd0, rat_lp0}, 64'd0,  "rat identity r0->p0");
        check({57'd0, rat_lp1}, 64'd5,  "rat identity r5->p5");
        check({57'd0, rat_lp2}, 64'd31, "rat identity r31->p31");
        check({57'd0, rat_lp3}, 64'd15, "rat identity r15->p15");

        // Single rename: arch r1 -> phys p50
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd1; rat_rp_a = 7'd50;
        rat_ren_b = 0;
        @(negedge clk);
        rat_ren_a = 0;
        rat_la0 = 5'd1;
        #1;
        check({57'd0, rat_lp0}, 64'd50, "rat single rename r1->p50");

        // Dual rename: arch r2->p60, arch r3->p70
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd2; rat_rp_a = 7'd60;
        rat_ren_b = 1; rat_ra_b = 5'd3; rat_rp_b = 7'd70;
        @(negedge clk);
        rat_ren_a = 0; rat_ren_b = 0;
        rat_la0 = 5'd2; rat_la1 = 5'd3;
        #1;
        check({57'd0, rat_lp0}, 64'd60, "rat dual rename r2->p60");
        check({57'd0, rat_lp1}, 64'd70, "rat dual rename r3->p70");

        // Old mapping output: rename r2 again to p80, should report old=p60
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd2; rat_rp_a = 7'd80;
        rat_ren_b = 0;
        #1;
        check({57'd0, rat_old_a}, 64'd60, "rat old mapping r2 was p60");
        @(negedge clk);
        rat_ren_a = 0;

        // Intra-group forwarding: A renames r5->p90, B reads r5 as source
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd5; rat_rp_a = 7'd90;
        rat_ren_b = 0;
        rat_la2 = 5'd5;
        #1;
        check({57'd0, rat_lp2}, 64'd90, "rat intra-group fwd B sees A rename");
        @(negedge clk);
        rat_ren_a = 0;

        // Intra-group old_b: A renames r10->p100, B renames r10->p110
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd10; rat_rp_a = 7'd100;
        rat_ren_b = 1; rat_ra_b = 5'd10; rat_rp_b = 7'd110;
        #1;
        check({57'd0, rat_old_a}, {57'd0, 7'd10},  "rat old_a r10 was identity p10");
        check({57'd0, rat_old_b}, {57'd0, 7'd100}, "rat old_b r10 is A new p100");
        @(negedge clk);
        rat_ren_a = 0; rat_ren_b = 0;

        // After both renames, r10 should map to p110
        rat_la0 = 5'd10;
        #1;
        check({57'd0, rat_lp0}, 64'd110, "rat r10->p110 after dual rename");

        // Checkpoint / Restore
        @(negedge clk);
        rat_chk = 1;
        @(negedge clk);
        rat_chk = 0;

        // Rename r0 -> p120
        @(negedge clk);
        rat_ren_a = 1; rat_ra_a = 5'd0; rat_rp_a = 7'd120;
        @(negedge clk);
        rat_ren_a = 0;
        rat_la0 = 5'd0;
        #1;
        check({57'd0, rat_lp0}, 64'd120, "rat post-chk rename r0->p120");

        // Restore checkpoint — r0 back to p0
        @(negedge clk);
        rat_rst = 1;
        @(negedge clk);
        rat_rst = 0;
        rat_la0 = 5'd0;
        #1;
        check({57'd0, rat_lp0}, 64'd0, "rat restore r0 back to p0");

        // r10 should still be p110 (checkpointed state)
        rat_la1 = 5'd10;
        #1;
        check({57'd0, rat_lp1}, 64'd110, "rat restore r10 still p110");

        // ============================================================
        $display("\n--- Results: %0d passed, %0d failed ---", pass_count, fail_count);
        $finish;
    end
endmodule
