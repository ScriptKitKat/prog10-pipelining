`define MEM_SIZE (1024*512)
`define START 64'h2000

module memory(
    input clk,
    input reset,
    input [63:0] PC,
    output [31:0] instruction,
    input [63:0] data_address,
    output [63:0] data_out,
    output data_ready,
    input write_enable,
    input [63:0] write_address,
    input [63:0] write_data
);
    reg [7:0] bytes [0:`MEM_SIZE-1];

    assign instruction = {bytes[PC + 3], bytes[PC + 2], bytes[PC + 1], bytes[PC]};

    assign data_out = {bytes[data_address + 7], bytes[data_address + 6],
                       bytes[data_address + 5], bytes[data_address + 4],
                       bytes[data_address + 3], bytes[data_address + 2],
                       bytes[data_address + 1], bytes[data_address]};

    assign data_ready = 1'b1;

    always @(posedge clk) begin
        if (write_enable) begin
            bytes[write_address] <= write_data[7:0];
            bytes[write_address + 1] <= write_data[15:8];
            bytes[write_address + 2] <= write_data[23:16];
            bytes[write_address + 3] <= write_data[31:24];
            bytes[write_address + 4] <= write_data[39:32];
            bytes[write_address + 5] <= write_data[47:40];
            bytes[write_address + 6] <= write_data[55:48];
            bytes[write_address + 7] <= write_data[63:56];
        end
    end
endmodule

module reg_file(
    input clk,
    input reset,
    input write_enable,
    input [63:0] write_data,
    input [4:0] write_select,
    input [4:0] read_sel1,
    input [4:0] read_sel2,
    input [4:0] read_sel3,
    output [63:0] read_data1,
    output [63:0] read_data2,
    output [63:0] read_data3,
    output [63:0] read_r31
);
    reg [63:0] registers [0:31];

    assign read_data1 = registers[read_sel1];
    assign read_data2 = registers[read_sel2];
    assign read_data3 = registers[read_sel3];
    assign read_r31 = registers[31];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 31; i = i + 1) begin
                registers[i] <= 64'b0;
            end
            registers[31] <= `MEM_SIZE;
        end else if (write_enable) begin
            registers[write_select] <= write_data;
        end
    end
endmodule