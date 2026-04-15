// Free List — circular FIFO of 7-bit physical register indices.
// Capacity: 96 entries (phys regs 32-127 initially free).
// Supports alloc (pop) up to 2 per cycle and free (push) up to 2 per cycle.

module free_list (
    input         clk,
    input         reset,

    // Allocate (pop) interface
    input         alloc_en0,
    input         alloc_en1,
    output [6:0]  alloc_reg0,
    output [6:0]  alloc_reg1,

    // Free (push) interface
    input         free_en0,
    input  [6:0]  free_reg0,
    input         free_en1,
    input  [6:0]  free_reg1,

    // Status
    output        empty,
    output        almost_empty
);

    localparam FIFO_DEPTH = 128;
    localparam PTR_BITS   = 7;

    reg [6:0] fifo [0:FIFO_DEPTH-1];
    reg [PTR_BITS:0] head, tail;
    wire [PTR_BITS:0] count;

    assign count = tail - head;
    assign empty = (count == 0);
    assign almost_empty = (count == 1);

    assign alloc_reg0 = fifo[head[PTR_BITS-1:0]];
    assign alloc_reg1 = fifo[head[PTR_BITS-1:0] + 1];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 0;
            tail <= 0;
            for (i = 0; i < 96; i = i + 1) begin
                fifo[i] <= i[6:0] + 7'd32;
            end
            tail <= 8'd96;
        end else begin
            // Allocate (pop from head)
            if (alloc_en0 && alloc_en1 && count >= 2)
                head <= head + 2;
            else if (alloc_en0 && count >= 1)
                head <= head + 1;

            // Free (push to tail)
            if (free_en0 && free_en1) begin
                fifo[tail[PTR_BITS-1:0]]     <= free_reg0;
                fifo[tail[PTR_BITS-1:0] + 1] <= free_reg1;
                tail <= tail + 2;
            end else if (free_en0) begin
                fifo[tail[PTR_BITS-1:0]] <= free_reg0;
                tail <= tail + 1;
            end else if (free_en1) begin
                fifo[tail[PTR_BITS-1:0]] <= free_reg1;
                tail <= tail + 1;
            end
        end
    end

endmodule
