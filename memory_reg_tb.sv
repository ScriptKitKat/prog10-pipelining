`include "memory_reg.sv"

module memory_reg_tb;
    reg clk, reset;

    // reg_file signals
    reg         rf_we;
    reg  [63:0] rf_wdata;
    reg  [4:0]  rf_wsel, rf_rs1, rf_rs2, rf_rs3;
    wire [63:0] rf_rd1, rf_rd2, rf_rd3, rf_r31;

    reg_file rf(
        .clk(clk), .reset(reset),
        .write_enable(rf_we), .write_data(rf_wdata), .write_select(rf_wsel),
        .read_sel1(rf_rs1), .read_sel2(rf_rs2), .read_sel3(rf_rs3),
        .read_data1(rf_rd1), .read_data2(rf_rd2), .read_data3(rf_rd3),
        .read_r31(rf_r31)
    );

    // memory signals
    reg  [63:0] PC;
    reg  [63:0] data_addr, wr_addr, wr_data;
    reg         mem_we;
    wire [31:0] instr;
    wire [63:0] mem_out;
    wire        mem_rdy;

    memory mem(
        .clk(clk), .reset(reset),
        .PC(PC), .instruction(instr),
        .data_address(data_addr), .data_out(mem_out), .data_ready(mem_rdy),
        .write_enable(mem_we), .write_address(wr_addr), .write_data(wr_data)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("memory_reg_tb.vcd");
        $dumpvars(0, memory_reg_tb);

        clk = 0; reset = 1;
        rf_we = 0; rf_wdata = 0; rf_wsel = 0;
        rf_rs1 = 0; rf_rs2 = 0; rf_rs3 = 0;
        mem_we = 0; wr_addr = 0; wr_data = 0; data_addr = 0; PC = 64'h2000;

        #10 reset = 0;

        // r31 should equal MEM_SIZE after reset
        $display("reset r31 = %0d (expect %0d)", rf_r31, `MEM_SIZE);

        // Write 0xDEADBEEF to register 5
        @(negedge clk);
        rf_we = 1; rf_wsel = 5'd5; rf_wdata = 64'hDEADBEEF;
        @(negedge clk);
        rf_we = 0; rf_rs1 = 5'd5;
        #1;
        if (rf_rd1 === 64'hDEADBEEF) $display("PASS reg_file write/read");
        else                          $display("FAIL reg_file: got %h", rf_rd1);

        // Write 0x1122334455667788 to memory at address 0x100, read it back
        @(negedge clk);
        mem_we = 1; wr_addr = 64'h100; wr_data = 64'h1122334455667788;
        @(negedge clk);
        mem_we = 0; data_addr = 64'h100;
        #1;
        if (mem_out === 64'h1122334455667788) $display("PASS memory write/read");
        else                                  $display("FAIL memory: got %h", mem_out);

        $finish;
    end
endmodule
