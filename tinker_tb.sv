`include "tinker.sv"

// Simple top-level smoke test: load a few instructions into memory and run.
// Program:
//   0x2000: addi r1, #5     -> r1 = 5
//   0x2004: addi r1, #3     -> r1 = 8
//   0x2008: halt
module tinker_tb;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    // Helper to build an instruction word: [opcode:5 | rd:5 | rs:5 | rt:5 | L:12]
    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task store_instr(input [63:0] addr, input [31:0] word);
        begin
            dut.memory.bytes[addr + 0] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    initial begin
        $dumpfile("tinker_tb.vcd");
        $dumpvars(0, tinker_tb);

        clk = 0; reset = 1;
        #2;
        // addi r1, #5
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));
        // addi r1, #3
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd3));
        // halt (opcode 0x0f, L=0)
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        // Run long enough for FETCH/DECODE/EXECUTE/WB across 3 instrs
        repeat (60) @(posedge clk);

        $display("r1 = %0d (expect 8)", dut.reg_file.registers[1]);
        $display("hlt = %b (expect 1)", hlt);
        if (dut.reg_file.registers[1] === 64'd8 && hlt === 1'b1)
            $display("PASS tinker smoke test");
        else
            $display("FAIL tinker smoke test");

        $finish;
    end
endmodule
