`ifndef PHYS_REG_FILE_SV_INCLUDED
`define PHYS_REG_FILE_SV_INCLUDED

// Physical Register File — 128 x 64-bit, 4 read ports (combinational), 2 write ports (posedge clk)
// Each register has a "ready" bit indicating the value is valid.

module phys_reg_file (
    input         clk,
    input         reset,

    // Read ports (combinational)
    input  [6:0]  read_addr0,
    output [63:0] read_data0,
    output        read_ready0,

    input  [6:0]  read_addr1,
    output [63:0] read_data1,
    output        read_ready1,

    input  [6:0]  read_addr2,
    output [63:0] read_data2,
    output        read_ready2,

    input  [6:0]  read_addr3,
    output [63:0] read_data3,
    output        read_ready3,

    // Write port 0
    input         write_en0,
    input  [6:0]  write_addr0,
    input  [63:0] write_data0,

    // Write port 1 (wins on conflict with port 0)
    input         write_en1,
    input  [6:0]  write_addr1,
    input  [63:0] write_data1,

    // Clear ready bit (used at rename time to mark destination "not ready")
    input         clear_ready_en0,
    input  [6:0]  clear_ready_addr0,
    input         clear_ready_en1,
    input  [6:0]  clear_ready_addr1
);

    reg [63:0] data  [0:127];
    reg        ready [0:127];

    // Combinational reads
    assign read_data0  = data[read_addr0];
    assign read_ready0 = ready[read_addr0];
    assign read_data1  = data[read_addr1];
    assign read_ready1 = ready[read_addr1];
    assign read_data2  = data[read_addr2];
    assign read_ready2 = ready[read_addr2];
    assign read_data3  = data[read_addr3];
    assign read_ready3 = ready[read_addr3];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 128; i = i + 1) begin
                data[i]  <= 64'd0;
                ready[i] <= 1'b1;
            end
        end else begin
            // Clear ready bits first (rename destinations become not-ready)
            if (clear_ready_en0) ready[clear_ready_addr0] <= 1'b0;
            if (clear_ready_en1) ready[clear_ready_addr1] <= 1'b0;

            // Write port 0
            if (write_en0) begin
                data[write_addr0]  <= write_data0;
                ready[write_addr0] <= 1'b1;
            end
            // Write port 1 (wins on conflict)
            if (write_en1) begin
                data[write_addr1]  <= write_data1;
                ready[write_addr1] <= 1'b1;
            end
        end
    end

endmodule

`endif // PHYS_REG_FILE_SV_INCLUDED
