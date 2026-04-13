`include "fpu.sv"

module fpu_tb;
    reg  [63:0] a, b;
    wire [63:0] add_r, sub_r, mul_r, div_r;
    wire [63:0] neg_b = {~b[63], b[62:0]};

    fpu_add u_add(.a(a), .b(b),     .result(add_r));
    fpu_add u_sub(.a(a), .b(neg_b), .result(sub_r));
    fpu_mul u_mul(.a(a), .b(b),     .result(mul_r));
    fpu_div u_div(.a(a), .b(b),     .result(div_r));

    initial begin
        $dumpfile("fpu_tb.vcd");
        $dumpvars(0, fpu_tb);

        // 1.0 + 2.0 = 3.0
        a = 64'h3ff0000000000000; b = 64'h4000000000000000; #1;
        $display("1.0 + 2.0 = %h (expect 4008000000000000)", add_r);

        // 5.0 - 2.0 = 3.0
        a = 64'h4014000000000000; b = 64'h4000000000000000; #1;
        $display("5.0 - 2.0 = %h (expect 4008000000000000)", sub_r);

        // 3.0 * 4.0 = 12.0
        a = 64'h4008000000000000; b = 64'h4010000000000000; #1;
        $display("3.0 * 4.0 = %h (expect 4028000000000000)", mul_r);

        // 10.0 / 4.0 = 2.5
        a = 64'h4024000000000000; b = 64'h4010000000000000; #1;
        $display("10.0 / 4.0 = %h (expect 4004000000000000)", div_r);

        // NaN propagation: x + NaN = NaN
        a = 64'h3ff0000000000000; b = 64'h7ff8000000000000; #1;
        $display("1.0 + NaN = %h (expect 7ff8000000000000)", add_r);

        $finish;
    end
endmodule
