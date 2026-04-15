`ifndef RAT_SV_INCLUDED
`define RAT_SV_INCLUDED

// Register Alias Table (RAT) — 32 entries mapping architectural reg -> physical reg (7-bit).
// Supports dual-issue: 4 source lookups + 2 renames per cycle.
// Handles intra-group forwarding (instruction B reads what instruction A just renamed).
// One checkpoint for branch misprediction recovery.

module rat (
    input         clk,
    input         reset,

    // Source lookups (combinational, 4 ports for dual-issue)
    input  [4:0]  lookup_arch0,     // instr A src1
    output [6:0]  lookup_phys0,
    input  [4:0]  lookup_arch1,     // instr A src2
    output [6:0]  lookup_phys1,
    input  [4:0]  lookup_arch2,     // instr B src1
    output reg [6:0] lookup_phys2,
    input  [4:0]  lookup_arch3,     // instr B src2
    output reg [6:0] lookup_phys3,

    // Rename port A (instruction A, first in program order)
    input         rename_en_a,
    input  [4:0]  rename_arch_a,
    input  [6:0]  rename_phys_a,
    output [6:0]  rename_old_a,

    // Rename port B (instruction B, second in program order)
    input         rename_en_b,
    input  [4:0]  rename_arch_b,
    input  [6:0]  rename_phys_b,
    output reg [6:0] rename_old_b,

    // Checkpoint
    input         checkpoint_en,
    input         restore_en
);

    reg [6:0] table_r [0:31];
    reg [6:0] checkpoint_r [0:31];

    // --- Combinational lookups ---
    // Ports 0,1 for instruction A: read directly from table
    assign lookup_phys0 = table_r[lookup_arch0];
    assign lookup_phys1 = table_r[lookup_arch1];

    // Ports 2,3 for instruction B: intra-group forwarding from A
    always @(*) begin
        if (rename_en_a && lookup_arch2 == rename_arch_a)
            lookup_phys2 = rename_phys_a;
        else
            lookup_phys2 = table_r[lookup_arch2];
    end

    always @(*) begin
        if (rename_en_a && lookup_arch3 == rename_arch_a)
            lookup_phys3 = rename_phys_a;
        else
            lookup_phys3 = table_r[lookup_arch3];
    end

    // --- Old mapping outputs ---
    assign rename_old_a = table_r[rename_arch_a];

    // For B: if A renames the same arch reg, B's "old" is A's *new* mapping
    always @(*) begin
        if (rename_en_a && rename_arch_b == rename_arch_a)
            rename_old_b = rename_phys_a;
        else
            rename_old_b = table_r[rename_arch_b];
    end

    // --- Sequential: rename + checkpoint/restore ---
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                table_r[i]      <= i[6:0];
                checkpoint_r[i] <= i[6:0];
            end
        end else if (restore_en) begin
            for (i = 0; i < 32; i = i + 1)
                table_r[i] <= checkpoint_r[i];
        end else begin
            // Rename A first, then B (program order)
            if (rename_en_a)
                table_r[rename_arch_a] <= rename_phys_a;
            if (rename_en_b)
                table_r[rename_arch_b] <= rename_phys_b;

            // Checkpoint: snapshot current state including this cycle's renames
            if (checkpoint_en) begin
                for (i = 0; i < 32; i = i + 1)
                    checkpoint_r[i] <= table_r[i];
                if (rename_en_a)
                    checkpoint_r[rename_arch_a] <= rename_phys_a;
                if (rename_en_b)
                    checkpoint_r[rename_arch_b] <= rename_phys_b;
            end
        end
    end

endmodule

`endif // RAT_SV_INCLUDED
