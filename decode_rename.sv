// Decode / Rename / Dispatch stage — dual-issue, combinational.
//
// Accepts up to 2 instructions from the fetch unit per cycle.
// For each: decode opcode → classify type, rename via RAT + free-list,
// read PRF operands, dispatch to RS / LSQ, allocate ROB entry.
//
// This module is purely combinational (outputs drive registered consumers).
// The `stall` output tells the fetch unit to hold (decode_take = 0).

module decode_rename (
    // --- From fetch unit ---
    input  [31:0] in0_inst,
    input  [63:0] in0_pc,
    input         in0_br_pred,
    input         in0_valid,

    input  [31:0] in1_inst,
    input  [63:0] in1_pc,
    input         in1_br_pred,
    input         in1_valid,

    // --- Resource status (combinational inputs) ---
    input         rob_full,
    input         free_list_empty,
    input         free_list_almost_empty,
    input         rs_alu_full,
    input         rs_alu_almost_full,
    input         rs_fpu_full,
    input         rs_fpu_almost_full,
    input         lsq_ld_full,
    input         lsq_ld_almost_full,
    input         lsq_st_full,
    input         lsq_st_almost_full,

    // --- Free list alloc outputs (peeks — head and head+1) ---
    input  [6:0]  fl_alloc_reg0,     // free_list.alloc_reg0
    input  [6:0]  fl_alloc_reg1,     // free_list.alloc_reg1

    // --- RAT lookup results (combinational) ---
    // We drive lookup_arch externally; results come back here.
    input  [6:0]  rat_phys0,         // instr A src1 phys
    input  [6:0]  rat_phys1,         // instr A src2 phys
    input  [6:0]  rat_phys2,         // instr B src1 phys (with intra-group fwd)
    input  [6:0]  rat_phys3,         // instr B src2 phys (with intra-group fwd)
    input  [6:0]  rat_old_a,         // old mapping for A's dest
    input  [6:0]  rat_old_b,         // old mapping for B's dest

    // --- PRF read results (combinational, 4 ports) ---
    input  [63:0] prf_data0,   input prf_ready0,   // A src1
    input  [63:0] prf_data1,   input prf_ready1,   // A src2
    input  [63:0] prf_data2,   input prf_ready2,   // B src1
    input  [63:0] prf_data3,   input prf_ready3,   // B src2

    // --- ROB alloc indices (combinational peek) ---
    input  [4:0]  rob_alloc_idx0,
    input  [4:0]  rob_alloc_idx1,

    // === OUTPUTS ===

    // To fetch unit
    output reg [1:0] decode_take,

    // RAT lookup addresses
    output reg [4:0] rat_lookup0,     // A src1 arch
    output reg [4:0] rat_lookup1,     // A src2 arch
    output reg [4:0] rat_lookup2,     // B src1 arch
    output reg [4:0] rat_lookup3,     // B src2 arch

    // RAT rename
    output reg       rat_rename_en_a,
    output reg [4:0] rat_rename_arch_a,
    output reg [6:0] rat_rename_phys_a,
    output reg       rat_rename_en_b,
    output reg [4:0] rat_rename_arch_b,
    output reg [6:0] rat_rename_phys_b,

    // RAT checkpoint
    output reg       rat_checkpoint_en,

    // Free-list alloc enables
    output reg       fl_alloc_en0,
    output reg       fl_alloc_en1,

    // PRF clear-ready (mark new dest not-ready)
    output reg       prf_clear_en0,
    output reg [6:0] prf_clear_addr0,
    output reg       prf_clear_en1,
    output reg [6:0] prf_clear_addr1,

    // PRF read addresses
    output reg [6:0] prf_read_addr0,
    output reg [6:0] prf_read_addr1,
    output reg [6:0] prf_read_addr2,
    output reg [6:0] prf_read_addr3,

    // ROB allocate
    output reg       rob_alloc_en0,
    output reg [2:0] rob_alloc_type0,
    output reg [4:0] rob_alloc_arch_rd0,
    output reg [6:0] rob_alloc_old_phys0,
    output reg [6:0] rob_alloc_new_phys0,
    output reg       rob_alloc_has_dest0,
    output reg       rob_alloc_br_pred0,
    output reg [63:0] rob_alloc_pc0,

    output reg       rob_alloc_en1,
    output reg [2:0] rob_alloc_type1,
    output reg [4:0] rob_alloc_arch_rd1,
    output reg [6:0] rob_alloc_old_phys1,
    output reg [6:0] rob_alloc_new_phys1,
    output reg       rob_alloc_has_dest1,
    output reg       rob_alloc_br_pred1,
    output reg [63:0] rob_alloc_pc1,

    // ALU RS dispatch (slot A)
    output reg       rs_alu_dispatch_en_a,
    output reg [4:0] rs_alu_dispatch_opcode_a,
    output reg [63:0] rs_alu_dispatch_src1_val_a,
    output reg [6:0]  rs_alu_dispatch_src1_tag_a,
    output reg        rs_alu_dispatch_src1_rdy_a,
    output reg [63:0] rs_alu_dispatch_src2_val_a,
    output reg [6:0]  rs_alu_dispatch_src2_tag_a,
    output reg        rs_alu_dispatch_src2_rdy_a,
    output reg [6:0]  rs_alu_dispatch_dest_tag_a,
    output reg [4:0]  rs_alu_dispatch_rob_idx_a,
    output reg [63:0] rs_alu_dispatch_imm_a,
    output reg [63:0] rs_alu_dispatch_pc_a,
    output reg        rs_alu_dispatch_br_pred_a,

    // ALU RS dispatch (slot B)
    output reg       rs_alu_dispatch_en_b,
    output reg [4:0] rs_alu_dispatch_opcode_b,
    output reg [63:0] rs_alu_dispatch_src1_val_b,
    output reg [6:0]  rs_alu_dispatch_src1_tag_b,
    output reg        rs_alu_dispatch_src1_rdy_b,
    output reg [63:0] rs_alu_dispatch_src2_val_b,
    output reg [6:0]  rs_alu_dispatch_src2_tag_b,
    output reg        rs_alu_dispatch_src2_rdy_b,
    output reg [6:0]  rs_alu_dispatch_dest_tag_b,
    output reg [4:0]  rs_alu_dispatch_rob_idx_b,
    output reg [63:0] rs_alu_dispatch_imm_b,
    output reg [63:0] rs_alu_dispatch_pc_b,
    output reg        rs_alu_dispatch_br_pred_b,

    // FPU RS dispatch (slot A)
    output reg       rs_fpu_dispatch_en_a,
    output reg [4:0] rs_fpu_dispatch_opcode_a,
    output reg [63:0] rs_fpu_dispatch_src1_val_a,
    output reg [6:0]  rs_fpu_dispatch_src1_tag_a,
    output reg        rs_fpu_dispatch_src1_rdy_a,
    output reg [63:0] rs_fpu_dispatch_src2_val_a,
    output reg [6:0]  rs_fpu_dispatch_src2_tag_a,
    output reg        rs_fpu_dispatch_src2_rdy_a,
    output reg [6:0]  rs_fpu_dispatch_dest_tag_a,
    output reg [4:0]  rs_fpu_dispatch_rob_idx_a,
    output reg [63:0] rs_fpu_dispatch_imm_a,
    output reg [63:0] rs_fpu_dispatch_pc_a,
    output reg        rs_fpu_dispatch_br_pred_a,

    // FPU RS dispatch (slot B)
    output reg       rs_fpu_dispatch_en_b,
    output reg [4:0] rs_fpu_dispatch_opcode_b,
    output reg [63:0] rs_fpu_dispatch_src1_val_b,
    output reg [6:0]  rs_fpu_dispatch_src1_tag_b,
    output reg        rs_fpu_dispatch_src1_rdy_b,
    output reg [63:0] rs_fpu_dispatch_src2_val_b,
    output reg [6:0]  rs_fpu_dispatch_src2_tag_b,
    output reg        rs_fpu_dispatch_src2_rdy_b,
    output reg [6:0]  rs_fpu_dispatch_dest_tag_b,
    output reg [4:0]  rs_fpu_dispatch_rob_idx_b,
    output reg [63:0] rs_fpu_dispatch_imm_b,
    output reg [63:0] rs_fpu_dispatch_pc_b,
    output reg        rs_fpu_dispatch_br_pred_b,

    // LSQ dispatch
    output reg       lsq_ld_dispatch_en_a,
    output reg [4:0] lsq_ld_dispatch_rob_idx_a,
    output reg [6:0] lsq_ld_dispatch_dest_tag_a,

    output reg       lsq_ld_dispatch_en_b,
    output reg [4:0] lsq_ld_dispatch_rob_idx_b,
    output reg [6:0] lsq_ld_dispatch_dest_tag_b,

    output reg       lsq_st_dispatch_en_a,
    output reg [4:0] lsq_st_dispatch_rob_idx_a,
    output reg [63:0] lsq_st_dispatch_data_a,
    output reg        lsq_st_dispatch_data_rdy_a,
    output reg [6:0]  lsq_st_dispatch_data_tag_a,

    output reg       lsq_st_dispatch_en_b,
    output reg [4:0] lsq_st_dispatch_rob_idx_b,
    output reg [63:0] lsq_st_dispatch_data_b,
    output reg        lsq_st_dispatch_data_rdy_b,
    output reg [6:0]  lsq_st_dispatch_data_tag_b,

    // Stall (active-high) — no instructions consumed
    output reg       stall
);

    // ================================================================
    // ROB type codes (must match rob.sv)
    // ================================================================
    localparam TYPE_ALU    = 3'd0;
    localparam TYPE_FPU    = 3'd1;
    localparam TYPE_LOAD   = 3'd2;
    localparam TYPE_STORE  = 3'd3;
    localparam TYPE_BRANCH = 3'd4;
    localparam TYPE_HALT   = 3'd5;
    localparam TYPE_OTHER  = 3'd6;

    // ================================================================
    // Instruction decode helpers
    // ================================================================
    wire [4:0]  opc_a = in0_inst[31:27];
    wire [4:0]  rd_a  = in0_inst[26:22];
    wire [4:0]  rs_a  = in0_inst[21:17];
    wire [4:0]  rt_a  = in0_inst[16:12];
    wire [11:0] L_a   = in0_inst[11:0];

    wire [4:0]  opc_b = in1_inst[31:27];
    wire [4:0]  rd_b  = in1_inst[26:22];
    wire [4:0]  rs_b  = in1_inst[21:17];
    wire [4:0]  rt_b  = in1_inst[16:12];
    wire [11:0] L_b   = in1_inst[11:0];

    // Classify type
    function automatic [2:0] classify(input [4:0] op, input [11:0] L_field);
        begin
            case (op)
                // Integer ALU
                5'h18, 5'h19, 5'h1a, 5'h1b, 5'h1c, 5'h1d,
                5'h00, 5'h01, 5'h02, 5'h03,
                5'h04, 5'h05, 5'h06, 5'h07,
                5'h11, 5'h12: classify = TYPE_ALU;
                // FPU
                5'h14, 5'h15, 5'h16, 5'h17: classify = TYPE_FPU;
                // LOAD: mov rd, (rs)(L)
                5'h10: classify = TYPE_LOAD;
                // STORE: mov (rd)(L), rs
                5'h13: classify = TYPE_STORE;
                // Branch
                5'h08, 5'h09, 5'h0a, 5'h0b, 5'h0c, 5'h0d, 5'h0e: classify = TYPE_BRANCH;
                // HALT: opcode 0x0F, L==0
                5'h0f: classify = (L_field == 12'd0) ? TYPE_HALT : TYPE_OTHER;
                default: classify = TYPE_OTHER;
            endcase
        end
    endfunction

    // Has destination register (writes rd)?
    function automatic has_dest(input [4:0] op);
        begin
            case (op)
                5'h18, 5'h19, 5'h1a, 5'h1b, 5'h1c, 5'h1d, // ALU arith
                5'h00, 5'h01, 5'h02, 5'h03,                 // logic
                5'h04, 5'h05, 5'h06, 5'h07,                 // shift
                5'h10, 5'h11, 5'h12,                         // MOV / LOAD / MOVI
                5'h14, 5'h15, 5'h16, 5'h17:                 // FPU
                    has_dest = 1'b1;
                default:
                    has_dest = 1'b0;
            endcase
        end
    endfunction

    // Source1 architectural register:
    //   Most: rs.  Reg-imm (ADDI/SUBI/SHFTRI/SHFTLI): rd.  MOVI: rd.
    //   BRNZ: rs (condition).  BRGT: rs.  BR/BRR/CALL: rd.
    //   LOAD: rs (base).  STORE: rd (base addr).
    function automatic [4:0] src1_arch(input [4:0] op, input [4:0] rd_f, input [4:0] rs_f);
        begin
            case (op)
                5'h19, 5'h1b, 5'h05, 5'h07: src1_arch = rd_f; // ADDI/SUBI/SHFTRI/SHFTLI
                5'h12: src1_arch = rd_f;                         // MOVI
                5'h08, 5'h09, 5'h0c: src1_arch = rd_f;          // BR/BRR/CALL
                5'h13: src1_arch = rd_f;                         // STORE (base = rd)
                default: src1_arch = rs_f;
            endcase
        end
    endfunction

    // Source2 architectural register:
    //   Reg-reg ALU: rt.  BRNZ: rd (target).  BRGT: rt.
    //   STORE: rs (data).
    //   Others needing only 1 source or imm: r0 (unused).
    function automatic [4:0] src2_arch(input [4:0] op, input [4:0] rd_f, input [4:0] rs_f, input [4:0] rt_f);
        begin
            case (op)
                5'h18, 5'h1a, 5'h1c, 5'h1d,   // reg-reg arith
                5'h00, 5'h01, 5'h02,            // AND/OR/XOR
                5'h04, 5'h06,                    // SHFTR/SHFTL (reg-reg)
                5'h14, 5'h15, 5'h16, 5'h17:     // FPU
                    src2_arch = rt_f;
                5'h0b: src2_arch = rd_f;          // BRNZ: target = rd
                5'h0e: src2_arch = rt_f;          // BRGT: rt
                5'h13: src2_arch = rs_f;          // STORE: data = rs
                default: src2_arch = 5'd0;        // unused
            endcase
        end
    endfunction

    // Needs src2 at all?
    function automatic needs_src2(input [4:0] op);
        begin
            case (op)
                5'h18, 5'h1a, 5'h1c, 5'h1d,
                5'h00, 5'h01, 5'h02,
                5'h04, 5'h06,
                5'h14, 5'h15, 5'h16, 5'h17,
                5'h0b, 5'h0e, 5'h13:
                    needs_src2 = 1'b1;
                default:
                    needs_src2 = 1'b0;
            endcase
        end
    endfunction

    // Sign-extended immediate
    wire [63:0] imm_a = {{52{L_a[11]}}, L_a};
    wire [63:0] imm_b = {{52{L_b[11]}}, L_b};

    // ================================================================
    // Per-slot decoded fields
    // ================================================================
    wire [2:0]  type_a  = classify(opc_a, L_a);
    wire        hdest_a = has_dest(opc_a);
    wire [4:0]  s1_a    = src1_arch(opc_a, rd_a, rs_a);
    wire [4:0]  s2_a    = src2_arch(opc_a, rd_a, rs_a, rt_a);
    wire        ns2_a   = needs_src2(opc_a);

    wire [2:0]  type_b  = classify(opc_b, L_b);
    wire        hdest_b = has_dest(opc_b);
    wire [4:0]  s1_b    = src1_arch(opc_b, rd_b, rs_b);
    wire [4:0]  s2_b    = src2_arch(opc_b, rd_b, rs_b, rt_b);
    wire        ns2_b   = needs_src2(opc_b);

    // ================================================================
    // Is it a branch requiring checkpoint?
    // ================================================================
    wire is_br_a = (type_a == TYPE_BRANCH);
    wire is_br_b = (type_b == TYPE_BRANCH);

    // ================================================================
    // Stall detection
    // ================================================================
    reg stall_a, stall_b;
    reg issue_a, issue_b;

    always @(*) begin
        stall_a = 1'b0;
        stall_b = 1'b0;

        if (in0_valid) begin
            if (rob_full)
                stall_a = 1'b1;
            if (hdest_a && free_list_empty)
                stall_a = 1'b1;
            case (type_a)
                TYPE_ALU, TYPE_BRANCH: if (rs_alu_full) stall_a = 1'b1;
                TYPE_FPU:              if (rs_fpu_full) stall_a = 1'b1;
                TYPE_LOAD:             if (lsq_ld_full) stall_a = 1'b1;
                TYPE_STORE:            if (lsq_st_full) stall_a = 1'b1;
                default: ;
            endcase
        end

        if (in1_valid && !stall_a) begin
            if (rob_full)
                stall_b = 1'b1;
            if (hdest_b) begin
                if (hdest_a && free_list_almost_empty)
                    stall_b = 1'b1;
                else if (!hdest_a && free_list_empty)
                    stall_b = 1'b1;
            end
            case (type_b)
                TYPE_ALU, TYPE_BRANCH: if (rs_alu_full)  stall_b = 1'b1;
                TYPE_FPU:              if (rs_fpu_full)  stall_b = 1'b1;
                TYPE_LOAD:             if (lsq_ld_full)  stall_b = 1'b1;
                TYPE_STORE:            if (lsq_st_full)  stall_b = 1'b1;
                default: ;
            endcase
            // Same-type conflict: both A and B need same RS/LSQ and only 1 slot
            if (issue_a) begin
                if ((type_a == TYPE_ALU || type_a == TYPE_BRANCH || type_a == TYPE_LOAD || type_a == TYPE_STORE) &&
                    (type_b == TYPE_ALU || type_b == TYPE_BRANCH || type_b == TYPE_LOAD || type_b == TYPE_STORE)) begin
                    if (rs_alu_almost_full) stall_b = 1'b1;
                end
                if (type_a == TYPE_FPU && type_b == TYPE_FPU) begin
                    if (rs_fpu_almost_full) stall_b = 1'b1;
                end
                if (type_a == TYPE_LOAD && type_b == TYPE_LOAD) begin
                    if (lsq_ld_almost_full) stall_b = 1'b1;
                end
                if (type_a == TYPE_STORE && type_b == TYPE_STORE) begin
                    if (lsq_st_almost_full) stall_b = 1'b1;
                end
            end
        end

        issue_a = in0_valid && !stall_a;
        issue_b = in1_valid && !stall_a && !stall_b;

        stall = stall_a;
        decode_take = {1'b0, issue_a} + {1'b0, issue_b};
    end

    // ================================================================
    // Rename: physical register for destinations
    // ================================================================
    wire [6:0] new_phys_a = fl_alloc_reg0;
    wire [6:0] new_phys_b = hdest_a ? fl_alloc_reg1 : fl_alloc_reg0;

    // ================================================================
    // RAT lookups + PRF reads
    // ================================================================
    always @(*) begin
        rat_lookup0 = s1_a;
        rat_lookup1 = ns2_a ? s2_a : 5'd0;
        rat_lookup2 = s1_b;
        rat_lookup3 = ns2_b ? s2_b : 5'd0;

        prf_read_addr0 = rat_phys0;
        prf_read_addr1 = rat_phys1;
        prf_read_addr2 = rat_phys2;
        prf_read_addr3 = rat_phys3;
    end

    // ================================================================
    // Intra-group dependency: if B's source tag == A's newly allocated
    // physical register, the PRF ready bit is stale (still 1 from reset
    // or a prior write). Override to 0 so the RS waits for CDB snoop.
    // ================================================================
    wire intra_dep_s1b = issue_a && hdest_a && (rat_phys2 == new_phys_a);
    wire intra_dep_s2b = issue_a && hdest_a && (rat_phys3 == new_phys_a);
    wire b_s1_rdy = prf_ready2 && !intra_dep_s1b;
    wire b_s2_rdy = prf_ready3 && !intra_dep_s2b;

    // ================================================================
    // Drive all outputs (combinational)
    // ================================================================
    always @(*) begin
        // Defaults
        rat_rename_en_a  = 1'b0;
        rat_rename_arch_a = 5'd0;
        rat_rename_phys_a = 7'd0;
        rat_rename_en_b  = 1'b0;
        rat_rename_arch_b = 5'd0;
        rat_rename_phys_b = 7'd0;
        rat_checkpoint_en = 1'b0;
        fl_alloc_en0     = 1'b0;
        fl_alloc_en1     = 1'b0;
        prf_clear_en0    = 1'b0;
        prf_clear_addr0  = 7'd0;
        prf_clear_en1    = 1'b0;
        prf_clear_addr1  = 7'd0;

        rob_alloc_en0       = 1'b0; rob_alloc_type0 = 3'd0;
        rob_alloc_arch_rd0  = 5'd0; rob_alloc_old_phys0 = 7'd0;
        rob_alloc_new_phys0 = 7'd0; rob_alloc_has_dest0 = 1'b0;
        rob_alloc_br_pred0  = 1'b0; rob_alloc_pc0 = 64'd0;

        rob_alloc_en1       = 1'b0; rob_alloc_type1 = 3'd0;
        rob_alloc_arch_rd1  = 5'd0; rob_alloc_old_phys1 = 7'd0;
        rob_alloc_new_phys1 = 7'd0; rob_alloc_has_dest1 = 1'b0;
        rob_alloc_br_pred1  = 1'b0; rob_alloc_pc1 = 64'd0;

        rs_alu_dispatch_en_a = 1'b0;
        rs_alu_dispatch_opcode_a = 5'd0;
        rs_alu_dispatch_src1_val_a = 64'd0; rs_alu_dispatch_src1_tag_a = 7'd0; rs_alu_dispatch_src1_rdy_a = 1'b0;
        rs_alu_dispatch_src2_val_a = 64'd0; rs_alu_dispatch_src2_tag_a = 7'd0; rs_alu_dispatch_src2_rdy_a = 1'b0;
        rs_alu_dispatch_dest_tag_a = 7'd0; rs_alu_dispatch_rob_idx_a = 5'd0;
        rs_alu_dispatch_imm_a = 64'd0; rs_alu_dispatch_pc_a = 64'd0; rs_alu_dispatch_br_pred_a = 1'b0;

        rs_alu_dispatch_en_b = 1'b0;
        rs_alu_dispatch_opcode_b = 5'd0;
        rs_alu_dispatch_src1_val_b = 64'd0; rs_alu_dispatch_src1_tag_b = 7'd0; rs_alu_dispatch_src1_rdy_b = 1'b0;
        rs_alu_dispatch_src2_val_b = 64'd0; rs_alu_dispatch_src2_tag_b = 7'd0; rs_alu_dispatch_src2_rdy_b = 1'b0;
        rs_alu_dispatch_dest_tag_b = 7'd0; rs_alu_dispatch_rob_idx_b = 5'd0;
        rs_alu_dispatch_imm_b = 64'd0; rs_alu_dispatch_pc_b = 64'd0; rs_alu_dispatch_br_pred_b = 1'b0;

        rs_fpu_dispatch_en_a = 1'b0;
        rs_fpu_dispatch_opcode_a = 5'd0;
        rs_fpu_dispatch_src1_val_a = 64'd0; rs_fpu_dispatch_src1_tag_a = 7'd0; rs_fpu_dispatch_src1_rdy_a = 1'b0;
        rs_fpu_dispatch_src2_val_a = 64'd0; rs_fpu_dispatch_src2_tag_a = 7'd0; rs_fpu_dispatch_src2_rdy_a = 1'b0;
        rs_fpu_dispatch_dest_tag_a = 7'd0; rs_fpu_dispatch_rob_idx_a = 5'd0;
        rs_fpu_dispatch_imm_a = 64'd0; rs_fpu_dispatch_pc_a = 64'd0; rs_fpu_dispatch_br_pred_a = 1'b0;

        rs_fpu_dispatch_en_b = 1'b0;
        rs_fpu_dispatch_opcode_b = 5'd0;
        rs_fpu_dispatch_src1_val_b = 64'd0; rs_fpu_dispatch_src1_tag_b = 7'd0; rs_fpu_dispatch_src1_rdy_b = 1'b0;
        rs_fpu_dispatch_src2_val_b = 64'd0; rs_fpu_dispatch_src2_tag_b = 7'd0; rs_fpu_dispatch_src2_rdy_b = 1'b0;
        rs_fpu_dispatch_dest_tag_b = 7'd0; rs_fpu_dispatch_rob_idx_b = 5'd0;
        rs_fpu_dispatch_imm_b = 64'd0; rs_fpu_dispatch_pc_b = 64'd0; rs_fpu_dispatch_br_pred_b = 1'b0;

        lsq_ld_dispatch_en_a = 1'b0; lsq_ld_dispatch_rob_idx_a = 5'd0; lsq_ld_dispatch_dest_tag_a = 7'd0;
        lsq_ld_dispatch_en_b = 1'b0; lsq_ld_dispatch_rob_idx_b = 5'd0; lsq_ld_dispatch_dest_tag_b = 7'd0;

        lsq_st_dispatch_en_a = 1'b0; lsq_st_dispatch_rob_idx_a = 5'd0;
        lsq_st_dispatch_data_a = 64'd0; lsq_st_dispatch_data_rdy_a = 1'b0; lsq_st_dispatch_data_tag_a = 7'd0;
        lsq_st_dispatch_en_b = 1'b0; lsq_st_dispatch_rob_idx_b = 5'd0;
        lsq_st_dispatch_data_b = 64'd0; lsq_st_dispatch_data_rdy_b = 1'b0; lsq_st_dispatch_data_tag_b = 7'd0;

        // ==== Instruction A ====
        if (issue_a) begin
            // ROB alloc
            rob_alloc_en0       = 1'b1;
            rob_alloc_type0     = type_a;
            rob_alloc_arch_rd0  = rd_a;
            rob_alloc_old_phys0 = rat_old_a;
            rob_alloc_new_phys0 = hdest_a ? new_phys_a : 7'd0;
            rob_alloc_has_dest0 = hdest_a;
            rob_alloc_br_pred0  = in0_br_pred;
            rob_alloc_pc0       = in0_pc;

            // Rename
            if (hdest_a) begin
                rat_rename_en_a   = 1'b1;
                rat_rename_arch_a = rd_a;
                rat_rename_phys_a = new_phys_a;
                fl_alloc_en0      = 1'b1;
                prf_clear_en0     = 1'b1;
                prf_clear_addr0   = new_phys_a;
            end

            // Checkpoint on branch
            if (is_br_a)
                rat_checkpoint_en = 1'b1;

            // Dispatch to RS/LSQ
            case (type_a)
                TYPE_ALU, TYPE_BRANCH: begin
                    rs_alu_dispatch_en_a       = 1'b1;
                    rs_alu_dispatch_opcode_a   = opc_a;
                    rs_alu_dispatch_src1_val_a = prf_data0;
                    rs_alu_dispatch_src1_tag_a = rat_phys0;
                    rs_alu_dispatch_src1_rdy_a = prf_ready0;
                    rs_alu_dispatch_src2_val_a = ns2_a ? prf_data1 : 64'd0;
                    rs_alu_dispatch_src2_tag_a = ns2_a ? rat_phys1 : 7'd0;
                    rs_alu_dispatch_src2_rdy_a = ns2_a ? prf_ready1 : 1'b1;
                    rs_alu_dispatch_dest_tag_a = hdest_a ? new_phys_a : 7'd0;
                    rs_alu_dispatch_rob_idx_a  = rob_alloc_idx0;
                    rs_alu_dispatch_imm_a      = imm_a;
                    rs_alu_dispatch_pc_a       = in0_pc;
                    rs_alu_dispatch_br_pred_a  = in0_br_pred;
                end
                TYPE_FPU: begin
                    rs_fpu_dispatch_en_a       = 1'b1;
                    rs_fpu_dispatch_opcode_a   = opc_a;
                    rs_fpu_dispatch_src1_val_a = prf_data0;
                    rs_fpu_dispatch_src1_tag_a = rat_phys0;
                    rs_fpu_dispatch_src1_rdy_a = prf_ready0;
                    rs_fpu_dispatch_src2_val_a = prf_data1;
                    rs_fpu_dispatch_src2_tag_a = rat_phys1;
                    rs_fpu_dispatch_src2_rdy_a = prf_ready1;
                    rs_fpu_dispatch_dest_tag_a = new_phys_a;
                    rs_fpu_dispatch_rob_idx_a  = rob_alloc_idx0;
                    rs_fpu_dispatch_imm_a      = imm_a;
                    rs_fpu_dispatch_pc_a       = in0_pc;
                end
                TYPE_LOAD: begin
                    lsq_ld_dispatch_en_a       = 1'b1;
                    lsq_ld_dispatch_rob_idx_a  = rob_alloc_idx0;
                    lsq_ld_dispatch_dest_tag_a = new_phys_a;
                    // LOAD also dispatches to ALU RS for address computation
                    rs_alu_dispatch_en_a       = 1'b1;
                    rs_alu_dispatch_opcode_a   = opc_a;
                    rs_alu_dispatch_src1_val_a = prf_data0;
                    rs_alu_dispatch_src1_tag_a = rat_phys0;
                    rs_alu_dispatch_src1_rdy_a = prf_ready0;
                    rs_alu_dispatch_src2_rdy_a = 1'b1;
                    rs_alu_dispatch_dest_tag_a = new_phys_a;
                    rs_alu_dispatch_rob_idx_a  = rob_alloc_idx0;
                    rs_alu_dispatch_imm_a      = imm_a;
                    rs_alu_dispatch_pc_a       = in0_pc;
                end
                TYPE_STORE: begin
                    // Store: data = rs (src2), base addr = rd (src1)
                    lsq_st_dispatch_en_a       = 1'b1;
                    lsq_st_dispatch_rob_idx_a  = rob_alloc_idx0;
                    lsq_st_dispatch_data_a     = prf_data1;   // rs data
                    lsq_st_dispatch_data_rdy_a = prf_ready1;
                    lsq_st_dispatch_data_tag_a = rat_phys1;
                    // Also dispatch to ALU RS for address computation
                    rs_alu_dispatch_en_a       = 1'b1;
                    rs_alu_dispatch_opcode_a   = opc_a;
                    rs_alu_dispatch_src1_val_a = prf_data0;   // rd (base)
                    rs_alu_dispatch_src1_tag_a = rat_phys0;
                    rs_alu_dispatch_src1_rdy_a = prf_ready0;
                    rs_alu_dispatch_src2_rdy_a = 1'b1;
                    rs_alu_dispatch_dest_tag_a = 7'd0;
                    rs_alu_dispatch_rob_idx_a  = rob_alloc_idx0;
                    rs_alu_dispatch_imm_a      = imm_a;
                    rs_alu_dispatch_pc_a       = in0_pc;
                end
                default: ; // HALT, OTHER — ROB only
            endcase
        end

        // ==== Instruction B ====
        if (issue_b) begin
            rob_alloc_en1       = 1'b1;
            rob_alloc_type1     = type_b;
            rob_alloc_arch_rd1  = rd_b;
            rob_alloc_old_phys1 = rat_old_b;
            rob_alloc_new_phys1 = hdest_b ? new_phys_b : 7'd0;
            rob_alloc_has_dest1 = hdest_b;
            rob_alloc_br_pred1  = in1_br_pred;
            rob_alloc_pc1       = in1_pc;

            if (hdest_b) begin
                rat_rename_en_b   = 1'b1;
                rat_rename_arch_b = rd_b;
                rat_rename_phys_b = new_phys_b;
                // Free-list alloc: if A also allocated, B uses reg1; else reg0
                if (hdest_a) fl_alloc_en1 = 1'b1;
                else         fl_alloc_en0 = 1'b1;
                prf_clear_en1   = 1'b1;
                prf_clear_addr1 = new_phys_b;
            end

            if (is_br_b && !is_br_a)
                rat_checkpoint_en = 1'b1;

            case (type_b)
                TYPE_ALU, TYPE_BRANCH: begin
                    rs_alu_dispatch_en_b      = 1'b1;
                    rs_alu_dispatch_opcode_b  = opc_b;
                    rs_alu_dispatch_src1_val_b = prf_data2;
                    rs_alu_dispatch_src1_tag_b = rat_phys2;
                    rs_alu_dispatch_src1_rdy_b = b_s1_rdy;
                    rs_alu_dispatch_src2_val_b = ns2_b ? prf_data3 : 64'd0;
                    rs_alu_dispatch_src2_tag_b = ns2_b ? rat_phys3 : 7'd0;
                    rs_alu_dispatch_src2_rdy_b = ns2_b ? b_s2_rdy : 1'b1;
                    rs_alu_dispatch_dest_tag_b = hdest_b ? new_phys_b : 7'd0;
                    rs_alu_dispatch_rob_idx_b  = rob_alloc_idx1;
                    rs_alu_dispatch_imm_b      = imm_b;
                    rs_alu_dispatch_pc_b       = in1_pc;
                    rs_alu_dispatch_br_pred_b  = in1_br_pred;
                end
                TYPE_FPU: begin
                    rs_fpu_dispatch_en_b      = 1'b1;
                    rs_fpu_dispatch_opcode_b  = opc_b;
                    rs_fpu_dispatch_src1_val_b = prf_data2;
                    rs_fpu_dispatch_src1_tag_b = rat_phys2;
                    rs_fpu_dispatch_src1_rdy_b = b_s1_rdy;
                    rs_fpu_dispatch_src2_val_b = prf_data3;
                    rs_fpu_dispatch_src2_tag_b = rat_phys3;
                    rs_fpu_dispatch_src2_rdy_b = b_s2_rdy;
                    rs_fpu_dispatch_dest_tag_b = new_phys_b;
                    rs_fpu_dispatch_rob_idx_b  = rob_alloc_idx1;
                    rs_fpu_dispatch_imm_b      = imm_b;
                    rs_fpu_dispatch_pc_b       = in1_pc;
                end
                TYPE_LOAD: begin
                    lsq_ld_dispatch_en_b       = 1'b1;
                    lsq_ld_dispatch_rob_idx_b  = rob_alloc_idx1;
                    lsq_ld_dispatch_dest_tag_b = new_phys_b;
                    rs_alu_dispatch_en_b       = 1'b1;
                    rs_alu_dispatch_opcode_b   = opc_b;
                    rs_alu_dispatch_src1_val_b = prf_data2;
                    rs_alu_dispatch_src1_tag_b = rat_phys2;
                    rs_alu_dispatch_src1_rdy_b = b_s1_rdy;
                    rs_alu_dispatch_src2_rdy_b = 1'b1;
                    rs_alu_dispatch_dest_tag_b = new_phys_b;
                    rs_alu_dispatch_rob_idx_b  = rob_alloc_idx1;
                    rs_alu_dispatch_imm_b      = imm_b;
                    rs_alu_dispatch_pc_b       = in1_pc;
                end
                TYPE_STORE: begin
                    lsq_st_dispatch_en_b       = 1'b1;
                    lsq_st_dispatch_rob_idx_b  = rob_alloc_idx1;
                    lsq_st_dispatch_data_b     = prf_data3;
                    lsq_st_dispatch_data_rdy_b = b_s2_rdy;
                    lsq_st_dispatch_data_tag_b = rat_phys3;
                    rs_alu_dispatch_en_b       = 1'b1;
                    rs_alu_dispatch_opcode_b   = opc_b;
                    rs_alu_dispatch_src1_val_b = prf_data2;
                    rs_alu_dispatch_src1_tag_b = rat_phys2;
                    rs_alu_dispatch_src1_rdy_b = b_s1_rdy;
                    rs_alu_dispatch_src2_rdy_b = 1'b1;
                    rs_alu_dispatch_dest_tag_b = 7'd0;
                    rs_alu_dispatch_rob_idx_b  = rob_alloc_idx1;
                    rs_alu_dispatch_imm_b      = imm_b;
                    rs_alu_dispatch_pc_b       = in1_pc;
                end
                default: ;
            endcase
        end
    end

endmodule
