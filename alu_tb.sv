`include "alu.sv"

module alu_tb;
    reg  [4:0]  opcode;
    reg  [63:0] PC, rd_data, rs_data, rt_data, r31_data;
    reg  [11:0] L_data;
    wire [63:0] result, branch_target;
    wire        writeback, branch_taken;

    ALU dut(
        .opcode(opcode), .PC(PC),
        .rd_data(rd_data), .rs_data(rs_data), .rt_data(rt_data),
        .r31_data(r31_data), .L_data(L_data),
        .result(result), .writeback(writeback),
        .branch_target(branch_target), .branch_taken(branch_taken)
    );

    task check(input [63:0] expected, input [255:0] name);
        begin
            if (result === expected)
                $display("PASS %0s: %0d", name, result);
            else
                $display("FAIL %0s: got %0d expected %0d", name, result, expected);
        end
    endtask

    initial begin
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, alu_tb);

        PC = 64'h2000; r31_data = 64'd0; rd_data = 64'd0; L_data = 12'd0;

        // ADD: 10 + 20 = 30
        opcode = 5'h18; rs_data = 64'd10; rt_data = 64'd20; #1;
        check(64'd30, "ADD");

        // SUB: 50 - 8 = 42
        opcode = 5'h1a; rs_data = 64'd50; rt_data = 64'd8; #1;
        check(64'd42, "SUB");

        // MUL: 6 * 7 = 42
        opcode = 5'h1c; rs_data = 64'd6; rt_data = 64'd7; #1;
        check(64'd42, "MUL");

        // ADDI: rd=100, L=5 -> 105
        opcode = 5'h19; rd_data = 64'd100; L_data = 12'd5; #1;
        check(64'd105, "ADDI");

        // AND: 0xF0 & 0x0F = 0
        opcode = 5'h00; rs_data = 64'hF0; rt_data = 64'h0F; #1;
        check(64'd0, "AND");

        // OR: 0xF0 | 0x0F = 0xFF
        opcode = 5'h01; rs_data = 64'hF0; rt_data = 64'h0F; #1;
        check(64'hFF, "OR");

        // SHFTL: 1 << 4 = 16
        opcode = 5'h06; rs_data = 64'd1; rt_data = 64'd4; #1;
        check(64'd16, "SHFTL");

        // brr L (opcode 0x0a): branch_target = PC + L
        opcode = 5'h0a; L_data = 12'd16; PC = 64'h2000; #1;
        if (branch_taken && branch_target === 64'h2010)
            $display("PASS BRR_L: target=%h", branch_target);
        else
            $display("FAIL BRR_L: target=%h taken=%b", branch_target, branch_taken);

        $finish;
    end
endmodule
