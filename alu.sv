`include "fpu.sv"

module ALU(
    input [4:0] opcode,
    input [63:0] PC,
    input [63:0] rd_data,
    input [63:0] rs_data,
    input [63:0] rt_data,
    input [63:0] r31_data,
    input [11:0] L_data,
    output reg [63:0] result,
    output reg writeback,
    output reg [63:0] branch_target,
    output reg branch_taken
);
// control signal:
// use register or L bit for operation
    wire [63:0] extended_L;
    assign extended_L = {{52{L_data[11]}}, L_data};

    wire [63:0] fpu_add_result;
    wire [63:0] fpu_sub_result;
    wire [63:0] fpu_mul_result;
    wire [63:0] fpu_div_result;

    fpu_add fpu_add_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_add_result)
    );

    fpu_mul fpu_mul_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_mul_result)
    );

    fpu_div fpu_div_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_div_result)
    );

    wire [63:0] negated;
    assign negated = {~rt_data[63], rt_data[62:0]};
    fpu_add fpu_sub_unit(
        .a(rs_data),
        .b(negated),
        .result(fpu_sub_result)
    );

    always @(*) begin
        result = 64'b0;
        branch_target = PC + 64'd4;
        branch_taken = 1'b0;
        case (opcode)
            5'h18: result = rs_data + rt_data; // ADD
            5'h19: result = rd_data + extended_L; // ADDI
            5'h1a: result = rs_data - rt_data; // SUB
            5'h1b: result = rd_data - extended_L; // SUBI
            5'h1c: result = rs_data * rt_data; // MUL
            5'h1d: result = rs_data / rt_data; // DIV

            5'h00: result = rs_data & rt_data; // AND
            5'h01: result = rs_data | rt_data; // OR
            5'h02: result = rs_data ^ rt_data; // XOR
            5'h03: result = ~rs_data; // NOT

            5'h04: result = rs_data >> rt_data; // SHFTR
            5'h05: result = rd_data >> extended_L; // SHFTRI
            5'h06: result = rs_data << rt_data; // SHFTL
            5'h07: result = rd_data << extended_L; // SHFTLI

            5'h08: begin // br rd
                branch_target = rd_data;
                branch_taken = 1'b1;
            end
            5'h09: begin // brr rd
                branch_target = rd_data + PC;
                branch_taken = 1'b1;
            end
            5'h0a: begin // brr L
                branch_target = extended_L + PC;
                branch_taken = 1'b1;
            end

            5'h0b: begin  // brnz rd, rs
                branch_target = rd_data;
                if (rs_data != 64'b0) begin
                    branch_taken = 1'b1;
                end
            end
            5'h0c: begin // call
                // TODO: mem[r31 - 8] = pc + 4
                result = r31_data - 64'd8;
                branch_target = rd_data;
                branch_taken = 1'b1;
            end
            5'h0d: begin // return
                result = r31_data - 64'd8; // address of saved PC on stack
                branch_taken = 1'b1;
            end
            5'h0e: begin // brgt rd, rs, rt
                branch_target = rd_data;
                if (rs_data > rt_data) begin
                    branch_taken = 1'b1;
                end
            end

            // mov operations
            5'h10: result = rs_data + extended_L; // mov rd, (rs)(L)
            5'h11: result = rs_data; // mov rd, rs
            5'h12: result = extended_L; // mov rd [52:63], L
            5'h13: result = rd_data + extended_L; // mov (rd)(L), rs
            
            // FPU operations in another file: fpu.sv
            5'h14: result = fpu_add_result; // FADD
            5'h15: result = fpu_sub_result; // FSUB
            5'h16: result = fpu_mul_result; // FMUL
            5'h17: result = fpu_div_result; // FDIV
            default: result = 64'b0;
        endcase
    end
endmodule