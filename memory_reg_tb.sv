`include "memory_reg.sv"

module memory_reg_tb;
    reg clk, reset;

    // reg_file signals
    reg         rf_we, rf_we2;
    reg  [63:0] rf_wdata, rf_wdata2;
    reg  [4:0]  rf_wsel, rf_wsel2, rf_rs1, rf_rs2, rf_rs3, rf_rs4;
    wire [63:0] rf_rd1, rf_rd2, rf_rd3, rf_rd4, rf_r31;

    reg_file rf(
        .clk(clk), .reset(reset),
        .write_enable(rf_we), .write_data(rf_wdata), .write_select(rf_wsel),
        .write_enable2(rf_we2), .write_data2(rf_wdata2), .write_select2(rf_wsel2),
        .read_sel1(rf_rs1), .read_sel2(rf_rs2), .read_sel3(rf_rs3), .read_sel4(rf_rs4),
        .read_data1(rf_rd1), .read_data2(rf_rd2), .read_data3(rf_rd3), .read_data4(rf_rd4),
        .read_r31(rf_r31)
    );

    // memory signals
    reg  [63:0] PC;
    reg  [63:0] fetch_addr;
    wire [511:0] fetch_data;
    reg  [63:0] data_addr, wr_addr, wr_data;
    reg         mem_we;
    wire [31:0] instr;
    wire [63:0] mem_out;
    wire        mem_rdy;

    memory mem(
        .clk(clk), .reset(reset),
        .PC(PC), .instruction(instr),
        .instr_fetch_addr(fetch_addr), .instr_fetch_data(fetch_data),
        .data_address(data_addr), .data_out(mem_out), .data_ready(mem_rdy),
        .write_enable(mem_we), .write_address(wr_addr), .write_data(wr_data)
    );

    always #5 clk = ~clk;

    integer pass_count, fail_count;

    task check(input [63:0] got, input [63:0] expected, input [255:0] name);
        if (got === expected) begin
            $display("PASS %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL %0s: got %h, expected %h", name, got, expected);
            fail_count = fail_count + 1;
        end
    endtask

    initial begin
        $dumpfile("memory_reg_tb.vcd");
        $dumpvars(0, memory_reg_tb);

        clk = 0; reset = 1;
        rf_we = 0; rf_wdata = 0; rf_wsel = 0;
        rf_we2 = 0; rf_wdata2 = 0; rf_wsel2 = 0;
        rf_rs1 = 0; rf_rs2 = 0; rf_rs3 = 0; rf_rs4 = 0;
        mem_we = 0; wr_addr = 0; wr_data = 0; data_addr = 0;
        PC = 64'h2000; fetch_addr = 64'h2000;
        pass_count = 0; fail_count = 0;

        #10 reset = 0;

        // ===== reg_file tests =====

        // Task 1.3: r31 == MEM_SIZE after reset
        check(rf_r31, `MEM_SIZE, "r31 init");

        // Original test: write/read single port
        @(negedge clk);
        rf_we = 1; rf_wsel = 5'd5; rf_wdata = 64'hDEADBEEF;
        @(negedge clk);
        rf_we = 0; rf_rs1 = 5'd5;
        #1;
        check(rf_rd1, 64'hDEADBEEF, "reg write/read port1");

        // Task 1.2: 4th read port
        rf_rs4 = 5'd5;
        #1;
        check(rf_rd4, 64'hDEADBEEF, "read port4");

        // Task 1.2: 2nd write port
        @(negedge clk);
        rf_we2 = 1; rf_wsel2 = 5'd10; rf_wdata2 = 64'hCAFEBABE;
        @(negedge clk);
        rf_we2 = 0; rf_rs2 = 5'd10;
        #1;
        check(rf_rd2, 64'hCAFEBABE, "write port2");

        // Task 1.2: simultaneous writes to different registers
        @(negedge clk);
        rf_we = 1; rf_wsel = 5'd1; rf_wdata = 64'h1111;
        rf_we2 = 1; rf_wsel2 = 5'd2; rf_wdata2 = 64'h2222;
        @(negedge clk);
        rf_we = 0; rf_we2 = 0;
        rf_rs1 = 5'd1; rf_rs2 = 5'd2;
        #1;
        check(rf_rd1, 64'h1111, "dual write reg1");
        check(rf_rd2, 64'h2222, "dual write reg2");

        // Task 1.2: simultaneous writes to SAME register (port 2 wins)
        @(negedge clk);
        rf_we = 1; rf_wsel = 5'd7; rf_wdata = 64'hAAAA;
        rf_we2 = 1; rf_wsel2 = 5'd7; rf_wdata2 = 64'hBBBB;
        @(negedge clk);
        rf_we = 0; rf_we2 = 0;
        rf_rs1 = 5'd7;
        #1;
        check(rf_rd1, 64'hBBBB, "same-reg conflict port2 wins");

        // Task 1.3: r31 still correct after writes
        check(rf_r31, `MEM_SIZE, "r31 preserved");

        // ===== memory tests =====

        // Original test: write/read data port
        @(negedge clk);
        mem_we = 1; wr_addr = 64'h100; wr_data = 64'h1122334455667788;
        @(negedge clk);
        mem_we = 0; data_addr = 64'h100;
        #1;
        check(mem_out, 64'h1122334455667788, "mem write/read");

        // Task 1.1: 64-byte instruction fetch port
        // Store 16 known 32-bit words at address 0x3000
        @(negedge clk);
        mem_we = 1; wr_addr = 64'h3000; wr_data = {32'h0, 32'hAABBCCDD};
        @(negedge clk);
        wr_addr = 64'h3008; wr_data = {32'h0, 32'h11223344};
        @(negedge clk);
        mem_we = 0;

        fetch_addr = 64'h3000;
        #1;
        // First 32-bit word at offset 0
        check({32'h0, fetch_data[31:0]}, {32'h0, 32'hAABBCCDD}, "fetch word 0");
        // Second 32-bit word at offset 4
        check({32'h0, fetch_data[63:32]}, {32'h0, 32'h00000000}, "fetch word 1");
        // Third 32-bit word at offset 8
        check({32'h0, fetch_data[95:64]}, {32'h0, 32'h11223344}, "fetch word 2");

        // ===== Summary =====
        $display("\n--- Results: %0d passed, %0d failed ---", pass_count, fail_count);
        $finish;
    end
endmodule
