// ALU Execution Pipeline — 2-stage wrapper for integer/logic/branch operations.
//
// Stage 1: Latch inputs from RS, compute result combinationally.
// Stage 2: Latch result, present to CDB.  Latency = 2 cycles.
//
// Operand convention (set by decode/dispatch):
//   src1:  rs  for reg-reg ALU ops; rd (old) for reg-imm ops & MOVI;
//          rd for BR/BRR/CALL; loaded addr for RETURN;
//          rs (condition) for BRNZ; rs (cmp op1) for BRGT.
//   src2:  rt  for reg-reg ALU ops; rd (target) for BRNZ;
//          rt (cmp op2) for BRGT.
//   imm:   sign_ext(L) for reg-imm ops / BRR_L / MOVI; rd value for BRGT.

module alu_pipe (
    input         clk,
    input         reset,
    input         flush,
    input         stall,        // CDB couldn't accept s2 output — freeze pipeline

    // --- Issue inputs (from reservation station) ---
    input         valid_in,
    input  [4:0]  opcode_in,
    input  [63:0] src1_in,
    input  [63:0] src2_in,
    input  [6:0]  dest_tag_in,
    input  [4:0]  rob_idx_in,
    input  [63:0] imm_in,
    input  [63:0] pc_in,
    input         br_pred_taken_in,

    output        pipe_ready,   // can accept new instruction this cycle

    // --- Stage-2 outputs (to CDB) ---
    output        valid_out,
    output [4:0]  opcode_out,
    output [6:0]  dest_tag_out,
    output [4:0]  rob_idx_out,
    output [63:0] result_out,
    output        is_branch_out,
    output        branch_taken_out,
    output [63:0] branch_target_out,
    output        mispredict_out
);

    // ----------------------------------------------------------------
    // Stage-1 pipeline registers (input latch)
    // ----------------------------------------------------------------
    reg        s1_valid;
    reg [4:0]  s1_opcode;
    reg [63:0] s1_src1, s1_src2, s1_imm, s1_pc;
    reg [6:0]  s1_dest_tag;
    reg [4:0]  s1_rob_idx;
    reg        s1_br_pred;

    // ----------------------------------------------------------------
    // Stage-1 combinational result
    // ----------------------------------------------------------------
    reg [63:0] s1_result_c;
    reg        s1_is_branch_c;
    reg        s1_branch_taken_c;
    reg [63:0] s1_branch_target_c;

    always @(*) begin
        s1_result_c        = 64'b0;
        s1_is_branch_c     = 1'b0;
        s1_branch_taken_c  = 1'b0;
        s1_branch_target_c = s1_pc + 64'd4;

        case (s1_opcode)
            // --- Integer arithmetic ---
            5'h18: s1_result_c = s1_src1 + s1_src2;           // ADD
            5'h19: s1_result_c = s1_src1 + s1_imm;            // ADDI
            5'h1a: s1_result_c = s1_src1 - s1_src2;           // SUB
            5'h1b: s1_result_c = s1_src1 - s1_imm;            // SUBI
            5'h1c: s1_result_c = s1_src1 * s1_src2;           // MUL
            5'h1d: s1_result_c = s1_src1 / s1_src2;           // DIV

            // --- Logic ---
            5'h00: s1_result_c = s1_src1 & s1_src2;           // AND
            5'h01: s1_result_c = s1_src1 | s1_src2;           // OR
            5'h02: s1_result_c = s1_src1 ^ s1_src2;           // XOR
            5'h03: s1_result_c = ~s1_src1;                    // NOT

            // --- Shifts ---
            5'h04: s1_result_c = s1_src1 >> s1_src2;          // SHFTR
            5'h05: s1_result_c = s1_src1 >> s1_imm;           // SHFTRI
            5'h06: s1_result_c = s1_src1 << s1_src2;          // SHFTL
            5'h07: s1_result_c = s1_src1 << s1_imm;           // SHFTLI

            // --- Unconditional branches ---
            5'h08: begin                                       // BR rd
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_src1;
                s1_branch_taken_c  = 1'b1;
            end
            5'h09: begin                                       // BRR rd
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_src1 + s1_pc;
                s1_branch_taken_c  = 1'b1;
            end
            5'h0a: begin                                       // BRR L
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_imm + s1_pc;
                s1_branch_taken_c  = 1'b1;
            end

            // --- Conditional branches ---
            5'h0b: begin                                       // BRNZ: src1=rs, src2=rd(target)
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_src2;
                s1_branch_taken_c  = (s1_src1 != 64'b0);
            end
            5'h0e: begin                                       // BRGT: src1=rs, src2=rt, imm=rd(target)
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_imm;
                s1_branch_taken_c  = (s1_src1 > s1_src2);
            end

            // --- CALL / RETURN ---
            5'h0c: begin                                       // CALL: target=src1(rd)
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_src1;
                s1_branch_taken_c  = 1'b1;
            end
            5'h0d: begin                                       // RETURN: target=src1(loaded addr)
                s1_is_branch_c     = 1'b1;
                s1_branch_target_c = s1_src1;
                s1_branch_taken_c  = 1'b1;
            end

            // --- MOV / MOVI ---
            5'h11: s1_result_c = s1_src1;                      // MOV rd, rs
            5'h12: s1_result_c = {s1_src1[63:12], s1_imm[11:0]}; // MOVI (read-modify-write)

            // --- LOAD / STORE address computation ---
            5'h10: s1_result_c = s1_src1 + s1_imm;            // LOAD addr = base + offset
            5'h13: s1_result_c = s1_src1 + s1_imm;            // STORE addr = base + offset

            default: s1_result_c = 64'b0;
        endcase

        // For branches, the result carries the correct next PC for flush redirect
        if (s1_is_branch_c)
            s1_result_c = s1_branch_taken_c ? s1_branch_target_c : (s1_pc + 64'd4);
    end

    // ----------------------------------------------------------------
    // Stage-2 pipeline registers (result latch → CDB)
    // ----------------------------------------------------------------
    reg        s2_valid;
    reg [4:0]  s2_opcode;
    reg [6:0]  s2_dest_tag;
    reg [4:0]  s2_rob_idx;
    reg [63:0] s2_result;
    reg        s2_is_branch;
    reg        s2_branch_taken;
    reg [63:0] s2_branch_target;
    reg        s2_br_pred;
    reg [63:0] s2_pc;

    // ----------------------------------------------------------------
    // Stall / ready logic
    // ----------------------------------------------------------------
    wire pipe_stalled = stall && s2_valid;
    wire advance      = !pipe_stalled;
    assign pipe_ready = !s1_valid || advance;

    // ----------------------------------------------------------------
    // Pipeline advancement
    // ----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
        end else if (flush) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
        end else if (advance) begin
            // Stage 2 ← stage-1 combinational result
            s2_valid         <= s1_valid;
            s2_opcode        <= s1_opcode;
            s2_dest_tag      <= s1_dest_tag;
            s2_rob_idx       <= s1_rob_idx;
            s2_result        <= s1_result_c;
            s2_is_branch     <= s1_is_branch_c;
            s2_branch_taken  <= s1_branch_taken_c;
            s2_branch_target <= s1_branch_target_c;
            s2_br_pred       <= s1_br_pred;
            s2_pc            <= s1_pc;

            // Stage 1 ← input
            s1_valid    <= valid_in;
            s1_opcode   <= opcode_in;
            s1_src1     <= src1_in;
            s1_src2     <= src2_in;
            s1_dest_tag <= dest_tag_in;
            s1_rob_idx  <= rob_idx_in;
            s1_imm      <= imm_in;
            s1_pc       <= pc_in;
            s1_br_pred  <= br_pred_taken_in;
        end else begin
            // Pipe stalled — s2 holds. s1 can still accept if empty.
            if (!s1_valid) begin
                s1_valid    <= valid_in;
                s1_opcode   <= opcode_in;
                s1_src1     <= src1_in;
                s1_src2     <= src2_in;
                s1_dest_tag <= dest_tag_in;
                s1_rob_idx  <= rob_idx_in;
                s1_imm      <= imm_in;
                s1_pc       <= pc_in;
                s1_br_pred  <= br_pred_taken_in;
            end
        end
    end

    // ----------------------------------------------------------------
    // Outputs (from stage 2)
    // ----------------------------------------------------------------
    assign valid_out         = s2_valid;
    assign opcode_out        = s2_opcode;
    assign dest_tag_out      = s2_dest_tag;
    assign rob_idx_out       = s2_rob_idx;
    assign result_out        = s2_result;
    assign is_branch_out     = s2_is_branch;
    assign branch_taken_out  = s2_branch_taken;
    assign branch_target_out = s2_branch_target;
    assign mispredict_out    = s2_valid && s2_is_branch &&
                               (s2_branch_taken != s2_br_pred);

endmodule
