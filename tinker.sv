// tinker.sv — Top-level pipelined OOO Tinker processor.
//
// External interface: clk, reset, hlt (same as legacy multicycle `tinker_multicycle.sv`).
// Instantiates: memory, reg_file, phys_reg_file, free_list, rat,
// fetch_unit, decode_rename, rs_alu (8), rs_fpu (8),
// alu_pipe x2, fpu_pipe x2, load_store_queue, cdb, rob.

`include "alu.sv"
`include "memory_reg.sv"
`include "phys_reg_file.sv"
`include "free_list.sv"
`include "rat.sv"
`include "rob.sv"
`include "cdb.sv"
`include "fetch_unit.sv"
`include "decode_rename.sv"
`include "reservation_station.sv"
`include "alu_pipe.sv"
`include "fpu_pipe.sv"
`include "load_store_queue.sv"

module tinker_core(
    input clk,
    input reset,
    output logic hlt
);

    // ================================================================
    // Memory
    // ================================================================
    wire [63:0]  mem_instr_fetch_addr;
    wire [511:0] mem_instr_fetch_data;
    wire [63:0]  mem_data_addr;
    wire [63:0]  mem_data_out;
    wire         mem_data_ready;
    wire         mem_write_en;
    wire [63:0]  mem_write_addr;
    wire [63:0]  mem_write_data;

    memory u_mem (
        .clk(clk), .reset(reset),
        .PC(64'd0), .instruction(),
        .instr_fetch_addr(mem_instr_fetch_addr),
        .instr_fetch_data(mem_instr_fetch_data),
        .data_address(mem_data_addr),
        .data_out(mem_data_out),
        .data_ready(mem_data_ready),
        .write_enable(mem_write_en),
        .write_address(mem_write_addr),
        .write_data(mem_write_data)
    );

    // ================================================================
    // Architectural Register File
    // ================================================================
    wire        arch_we0, arch_we1;
    wire [4:0]  arch_wsel0, arch_wsel1;
    wire [63:0] arch_wdata0, arch_wdata1;

    reg_file u_arch_rf (
        .clk(clk), .reset(reset),
        .write_enable(arch_we0),   .write_data(arch_wdata0), .write_select(arch_wsel0),
        .write_enable2(arch_we1),  .write_data2(arch_wdata1), .write_select2(arch_wsel1),
        .read_sel1(5'd0), .read_sel2(5'd0), .read_sel3(5'd0), .read_sel4(5'd0),
        .read_data1(), .read_data2(), .read_data3(), .read_data4(), .read_r31()
    );

    // ================================================================
    // Physical Register File
    // ================================================================
    wire [6:0]  prf_raddr0, prf_raddr1, prf_raddr2, prf_raddr3;
    wire [63:0] prf_rdata0, prf_rdata1, prf_rdata2, prf_rdata3;
    wire        prf_rdy0,   prf_rdy1,   prf_rdy2,   prf_rdy3;
    wire        prf_we0, prf_we1;
    wire [6:0]  prf_waddr0, prf_waddr1;
    wire [63:0] prf_wdata0, prf_wdata1;
    wire        prf_clr_en0, prf_clr_en1;
    wire [6:0]  prf_clr_addr0, prf_clr_addr1;

    phys_reg_file u_prf (
        .clk(clk), .reset(reset),
        .read_addr0(prf_raddr0), .read_data0(prf_rdata0), .read_ready0(prf_rdy0),
        .read_addr1(prf_raddr1), .read_data1(prf_rdata1), .read_ready1(prf_rdy1),
        .read_addr2(prf_raddr2), .read_data2(prf_rdata2), .read_ready2(prf_rdy2),
        .read_addr3(prf_raddr3), .read_data3(prf_rdata3), .read_ready3(prf_rdy3),
        .write_en0(prf_we0), .write_addr0(prf_waddr0), .write_data0(prf_wdata0),
        .write_en1(prf_we1), .write_addr1(prf_waddr1), .write_data1(prf_wdata1),
        .clear_ready_en0(prf_clr_en0), .clear_ready_addr0(prf_clr_addr0),
        .clear_ready_en1(prf_clr_en1), .clear_ready_addr1(prf_clr_addr1)
    );

    // ================================================================
    // Free List
    // ================================================================
    wire        fl_alloc_en0, fl_alloc_en1;
    wire [6:0]  fl_alloc_reg0, fl_alloc_reg1;
    wire        fl_free_en0, fl_free_en1;
    wire [6:0]  fl_free_reg0, fl_free_reg1;
    wire        fl_empty, fl_almost_empty;

    free_list u_fl (
        .clk(clk), .reset(reset),
        .alloc_en0(fl_alloc_en0), .alloc_en1(fl_alloc_en1),
        .alloc_reg0(fl_alloc_reg0), .alloc_reg1(fl_alloc_reg1),
        .free_en0(fl_free_en0), .free_reg0(fl_free_reg0),
        .free_en1(fl_free_en1), .free_reg1(fl_free_reg1),
        .empty(fl_empty), .almost_empty(fl_almost_empty)
    );

    // ================================================================
    // Register Alias Table
    // ================================================================
    wire [4:0]  rat_lk0, rat_lk1, rat_lk2, rat_lk3;
    wire [6:0]  rat_ph0, rat_ph1, rat_ph2, rat_ph3;
    wire        rat_ren_en_a, rat_ren_en_b;
    wire [4:0]  rat_ren_arch_a, rat_ren_arch_b;
    wire [6:0]  rat_ren_phys_a, rat_ren_phys_b;
    wire [6:0]  rat_old_a, rat_old_b;
    wire        rat_ckpt_en;

    wire        flush_active;   // from ROB
    wire        do_flush;       // misprediction detected

    rat u_rat (
        .clk(clk), .reset(reset),
        .lookup_arch0(rat_lk0), .lookup_phys0(rat_ph0),
        .lookup_arch1(rat_lk1), .lookup_phys1(rat_ph1),
        .lookup_arch2(rat_lk2), .lookup_phys2(rat_ph2),
        .lookup_arch3(rat_lk3), .lookup_phys3(rat_ph3),
        .rename_en_a(rat_ren_en_a), .rename_arch_a(rat_ren_arch_a), .rename_phys_a(rat_ren_phys_a), .rename_old_a(rat_old_a),
        .rename_en_b(rat_ren_en_b), .rename_arch_b(rat_ren_arch_b), .rename_phys_b(rat_ren_phys_b), .rename_old_b(rat_old_b),
        .checkpoint_en(rat_ckpt_en),
        .restore_en(do_flush)
    );

    // ================================================================
    // Fetch Unit
    // ================================================================
    wire [31:0] fu_inst0, fu_inst1;
    wire [63:0] fu_pc0, fu_pc1;
    wire        fu_br_pred0, fu_br_pred1;
    wire [63:0] fu_pred_target0, fu_pred_target1;
    wire        fu_valid0, fu_valid1;
    wire [1:0]  decode_take;
    wire        fetch_flush;
    wire [63:0] fetch_flush_pc;
    wire        bht_update_en;
    wire [63:0] bht_update_pc;
    wire        bht_pred_taken, bht_actual_taken;
    wire        btb_update_en;
    wire [63:0] btb_update_pc, btb_update_target;
    wire        btb_update_taken;

    fetch_unit u_fu (
        .clk(clk), .reset(reset),
        .instr_fetch_addr(mem_instr_fetch_addr),
        .instr_fetch_data(mem_instr_fetch_data),
        .decode_take(decode_take),
        .out0_inst(fu_inst0), .out0_pc(fu_pc0), .out0_br_pred(fu_br_pred0),
        .out0_pred_target(fu_pred_target0), .out0_valid(fu_valid0),
        .out1_inst(fu_inst1), .out1_pc(fu_pc1), .out1_br_pred(fu_br_pred1),
        .out1_pred_target(fu_pred_target1), .out1_valid(fu_valid1),
        .flush(fetch_flush), .flush_pc(fetch_flush_pc),
        .bht_update_en(bht_update_en), .bht_update_pc(bht_update_pc),
        .bht_pred_taken(bht_pred_taken), .bht_actual_taken(bht_actual_taken),
        .btb_update_en(btb_update_en), .btb_update_pc(btb_update_pc),
        .btb_update_target(btb_update_target), .btb_update_taken(btb_update_taken)
    );

    // ================================================================
    // ROB
    // ================================================================
    wire        rob_alloc_en0, rob_alloc_en1;
    wire [2:0]  rob_alloc_type0, rob_alloc_type1;
    wire [4:0]  rob_alloc_arch_rd0, rob_alloc_arch_rd1;
    wire [6:0]  rob_alloc_old_phys0, rob_alloc_new_phys0;
    wire [6:0]  rob_alloc_old_phys1, rob_alloc_new_phys1;
    wire        rob_alloc_has_dest0, rob_alloc_has_dest1;
    wire        rob_alloc_br_pred0, rob_alloc_br_pred1;
    wire [63:0] rob_alloc_pc0, rob_alloc_pc1;
    wire [4:0]  rob_alloc_idx0, rob_alloc_idx1;
    wire        rob_full, rob_empty;

    wire        rob_commit_en0, rob_commit_en1;
    wire [2:0]  rob_commit_type0, rob_commit_type1;
    wire [4:0]  rob_commit_arch_rd0, rob_commit_arch_rd1;
    wire [6:0]  rob_commit_old_phys0, rob_commit_new_phys0;
    wire [6:0]  rob_commit_old_phys1, rob_commit_new_phys1;
    wire [63:0] rob_commit_store_addr0, rob_commit_store_data0;
    wire [63:0] rob_commit_store_addr1, rob_commit_store_data1;
    wire        rob_hlt;

    wire [63:0] rob_flush_redirect_pc;
    wire        rob_flush_free_en0, rob_flush_free_en1;
    wire [6:0]  rob_flush_free_reg0, rob_flush_free_reg1;

    // CDB → ROB side-band for branch info
    wire        cdb_valid_bus0, cdb_valid_bus1;
    wire [6:0]  cdb_tag_bus0, cdb_tag_bus1;
    wire [63:0] cdb_value_bus0, cdb_value_bus1;
    wire [4:0]  cdb_rob_idx_bus0, cdb_rob_idx_bus1;

    // Branch side-band muxed from ALU pipes via CDB winner IDs
    reg  [63:0] rob_cdb_store_addr0, rob_cdb_store_addr1;
    reg         rob_cdb_br_actual0, rob_cdb_br_actual1;
    reg         rob_cdb_mispredict0, rob_cdb_mispredict1;

    wire [4:0]  rob_head_idx;
    wire [4:0]  flush_rob_idx_w;

    rob u_rob (
        .clk(clk), .reset(reset),
        .alloc_en0(rob_alloc_en0), .alloc_type0(rob_alloc_type0),
        .alloc_arch_rd0(rob_alloc_arch_rd0), .alloc_old_phys0(rob_alloc_old_phys0),
        .alloc_new_phys0(rob_alloc_new_phys0), .alloc_has_dest0(rob_alloc_has_dest0),
        .alloc_br_pred0(rob_alloc_br_pred0), .alloc_pc0(rob_alloc_pc0),
        .alloc_en1(rob_alloc_en1), .alloc_type1(rob_alloc_type1),
        .alloc_arch_rd1(rob_alloc_arch_rd1), .alloc_old_phys1(rob_alloc_old_phys1),
        .alloc_new_phys1(rob_alloc_new_phys1), .alloc_has_dest1(rob_alloc_has_dest1),
        .alloc_br_pred1(rob_alloc_br_pred1), .alloc_pc1(rob_alloc_pc1),
        .alloc_idx0(rob_alloc_idx0), .alloc_idx1(rob_alloc_idx1),
        .full(rob_full),
        .cdb_valid0(cdb_valid_bus0), .cdb_rob_idx0(cdb_rob_idx_bus0),
        .cdb_value0(cdb_value_bus0), .cdb_store_addr0(rob_cdb_store_addr0),
        .cdb_br_actual0(rob_cdb_br_actual0), .cdb_mispredict0(rob_cdb_mispredict0),
        .cdb_valid1(cdb_valid_bus1), .cdb_rob_idx1(cdb_rob_idx_bus1),
        .cdb_value1(cdb_value_bus1), .cdb_store_addr1(rob_cdb_store_addr1),
        .cdb_br_actual1(rob_cdb_br_actual1), .cdb_mispredict1(rob_cdb_mispredict1),
        .commit_en0(rob_commit_en0), .commit_type0(rob_commit_type0),
        .commit_arch_rd0(rob_commit_arch_rd0), .commit_old_phys0(rob_commit_old_phys0),
        .commit_new_phys0(rob_commit_new_phys0),
        .commit_store_addr0(rob_commit_store_addr0), .commit_store_data0(rob_commit_store_data0),
        .commit_en1(rob_commit_en1), .commit_type1(rob_commit_type1),
        .commit_arch_rd1(rob_commit_arch_rd1), .commit_old_phys1(rob_commit_old_phys1),
        .commit_new_phys1(rob_commit_new_phys1),
        .commit_store_addr1(rob_commit_store_addr1), .commit_store_data1(rob_commit_store_data1),
        .hlt(rob_hlt),
        .flush_en(do_flush), .flush_rob_idx(flush_rob_idx_w),
        .flush_redirect_pc(rob_flush_redirect_pc),
        .flush_active(flush_active),
        .flush_free_en0(rob_flush_free_en0), .flush_free_reg0(rob_flush_free_reg0),
        .flush_free_en1(rob_flush_free_en1), .flush_free_reg1(rob_flush_free_reg1),
        .empty(rob_empty)
    );

    assign rob_head_idx = u_rob.head_idx;
    assign hlt = rob_hlt;

    // ================================================================
    // Decode / Rename / Dispatch
    // ================================================================
    wire        dr_stall;
    wire        rs_alu_full_w, rs_alu_almost_full_w;
    wire        rs_fpu_full_w, rs_fpu_almost_full_w;
    wire        lsq_ld_full_w, lsq_ld_almost_full_w;
    wire        lsq_st_full_w, lsq_st_almost_full_w;

    // RS ALU dispatch wires
    wire        dr_rs_alu_en_a, dr_rs_alu_en_b;
    wire [4:0]  dr_rs_alu_opc_a, dr_rs_alu_opc_b;
    wire [63:0] dr_rs_alu_s1v_a, dr_rs_alu_s2v_a, dr_rs_alu_s1v_b, dr_rs_alu_s2v_b;
    wire [6:0]  dr_rs_alu_s1t_a, dr_rs_alu_s2t_a, dr_rs_alu_s1t_b, dr_rs_alu_s2t_b;
    wire        dr_rs_alu_s1r_a, dr_rs_alu_s2r_a, dr_rs_alu_s1r_b, dr_rs_alu_s2r_b;
    wire [6:0]  dr_rs_alu_dt_a, dr_rs_alu_dt_b;
    wire [4:0]  dr_rs_alu_ri_a, dr_rs_alu_ri_b;
    wire [63:0] dr_rs_alu_imm_a, dr_rs_alu_imm_b, dr_rs_alu_pc_a, dr_rs_alu_pc_b;
    wire        dr_rs_alu_bp_a, dr_rs_alu_bp_b;
    wire [63:0] dr_rs_alu_pt_a, dr_rs_alu_pt_b;

    // RS FPU dispatch wires
    wire        dr_rs_fpu_en_a, dr_rs_fpu_en_b;
    wire [4:0]  dr_rs_fpu_opc_a, dr_rs_fpu_opc_b;
    wire [63:0] dr_rs_fpu_s1v_a, dr_rs_fpu_s2v_a, dr_rs_fpu_s1v_b, dr_rs_fpu_s2v_b;
    wire [6:0]  dr_rs_fpu_s1t_a, dr_rs_fpu_s2t_a, dr_rs_fpu_s1t_b, dr_rs_fpu_s2t_b;
    wire        dr_rs_fpu_s1r_a, dr_rs_fpu_s2r_a, dr_rs_fpu_s1r_b, dr_rs_fpu_s2r_b;
    wire [6:0]  dr_rs_fpu_dt_a, dr_rs_fpu_dt_b;
    wire [4:0]  dr_rs_fpu_ri_a, dr_rs_fpu_ri_b;
    wire [63:0] dr_rs_fpu_imm_a, dr_rs_fpu_imm_b, dr_rs_fpu_pc_a, dr_rs_fpu_pc_b;
    wire        dr_rs_fpu_bp_a, dr_rs_fpu_bp_b;

    // LSQ dispatch wires
    wire        dr_lsq_ld_en_a, dr_lsq_ld_en_b;
    wire [4:0]  dr_lsq_ld_ri_a, dr_lsq_ld_ri_b;
    wire [6:0]  dr_lsq_ld_dt_a, dr_lsq_ld_dt_b;
    wire        dr_lsq_st_en_a, dr_lsq_st_en_b;
    wire [4:0]  dr_lsq_st_ri_a, dr_lsq_st_ri_b;
    wire [63:0] dr_lsq_st_data_a, dr_lsq_st_data_b;
    wire        dr_lsq_st_drdy_a, dr_lsq_st_drdy_b;
    wire [6:0]  dr_lsq_st_dtag_a, dr_lsq_st_dtag_b;

    decode_rename u_dr (
        .in0_inst(fu_inst0), .in0_pc(fu_pc0), .in0_br_pred(fu_br_pred0), .in0_pred_target(fu_pred_target0), .in0_valid(fu_valid0 && !do_flush && !flush_active),
        .in1_inst(fu_inst1), .in1_pc(fu_pc1), .in1_br_pred(fu_br_pred1), .in1_pred_target(fu_pred_target1), .in1_valid(fu_valid1 && !do_flush && !flush_active),
        .rob_full(rob_full),
        .free_list_empty(fl_empty), .free_list_almost_empty(fl_almost_empty),
        .rs_alu_full(rs_alu_full_w), .rs_alu_almost_full(rs_alu_almost_full_w),
        .rs_fpu_full(rs_fpu_full_w), .rs_fpu_almost_full(rs_fpu_almost_full_w),
        .lsq_ld_full(lsq_ld_full_w), .lsq_ld_almost_full(lsq_ld_almost_full_w),
        .lsq_st_full(lsq_st_full_w), .lsq_st_almost_full(lsq_st_almost_full_w),
        .fl_alloc_reg0(fl_alloc_reg0), .fl_alloc_reg1(fl_alloc_reg1),
        .rat_phys0(rat_ph0), .rat_phys1(rat_ph1), .rat_phys2(rat_ph2), .rat_phys3(rat_ph3),
        .rat_old_a(rat_old_a), .rat_old_b(rat_old_b),
        .prf_data0(prf_rdata0), .prf_ready0(prf_rdy0),
        .prf_data1(prf_rdata1), .prf_ready1(prf_rdy1),
        .prf_data2(prf_rdata2), .prf_ready2(prf_rdy2),
        .prf_data3(prf_rdata3), .prf_ready3(prf_rdy3),
        .rob_alloc_idx0(rob_alloc_idx0), .rob_alloc_idx1(rob_alloc_idx1),
        .decode_take(decode_take), .stall(dr_stall),
        .rat_lookup0(rat_lk0), .rat_lookup1(rat_lk1), .rat_lookup2(rat_lk2), .rat_lookup3(rat_lk3),
        .rat_rename_en_a(rat_ren_en_a), .rat_rename_arch_a(rat_ren_arch_a), .rat_rename_phys_a(rat_ren_phys_a),
        .rat_rename_en_b(rat_ren_en_b), .rat_rename_arch_b(rat_ren_arch_b), .rat_rename_phys_b(rat_ren_phys_b),
        .rat_checkpoint_en(rat_ckpt_en),
        .fl_alloc_en0(fl_alloc_en0), .fl_alloc_en1(fl_alloc_en1),
        .prf_clear_en0(prf_clr_en0), .prf_clear_addr0(prf_clr_addr0),
        .prf_clear_en1(prf_clr_en1), .prf_clear_addr1(prf_clr_addr1),
        .prf_read_addr0(prf_raddr0), .prf_read_addr1(prf_raddr1),
        .prf_read_addr2(prf_raddr2), .prf_read_addr3(prf_raddr3),
        .rob_alloc_en0(rob_alloc_en0), .rob_alloc_type0(rob_alloc_type0),
        .rob_alloc_arch_rd0(rob_alloc_arch_rd0), .rob_alloc_old_phys0(rob_alloc_old_phys0),
        .rob_alloc_new_phys0(rob_alloc_new_phys0), .rob_alloc_has_dest0(rob_alloc_has_dest0),
        .rob_alloc_br_pred0(rob_alloc_br_pred0), .rob_alloc_pc0(rob_alloc_pc0),
        .rob_alloc_en1(rob_alloc_en1), .rob_alloc_type1(rob_alloc_type1),
        .rob_alloc_arch_rd1(rob_alloc_arch_rd1), .rob_alloc_old_phys1(rob_alloc_old_phys1),
        .rob_alloc_new_phys1(rob_alloc_new_phys1), .rob_alloc_has_dest1(rob_alloc_has_dest1),
        .rob_alloc_br_pred1(rob_alloc_br_pred1), .rob_alloc_pc1(rob_alloc_pc1),
        // RS ALU
        .rs_alu_dispatch_en_a(dr_rs_alu_en_a), .rs_alu_dispatch_opcode_a(dr_rs_alu_opc_a),
        .rs_alu_dispatch_src1_val_a(dr_rs_alu_s1v_a), .rs_alu_dispatch_src1_tag_a(dr_rs_alu_s1t_a), .rs_alu_dispatch_src1_rdy_a(dr_rs_alu_s1r_a),
        .rs_alu_dispatch_src2_val_a(dr_rs_alu_s2v_a), .rs_alu_dispatch_src2_tag_a(dr_rs_alu_s2t_a), .rs_alu_dispatch_src2_rdy_a(dr_rs_alu_s2r_a),
        .rs_alu_dispatch_dest_tag_a(dr_rs_alu_dt_a), .rs_alu_dispatch_rob_idx_a(dr_rs_alu_ri_a),
        .rs_alu_dispatch_imm_a(dr_rs_alu_imm_a), .rs_alu_dispatch_pc_a(dr_rs_alu_pc_a), .rs_alu_dispatch_br_pred_a(dr_rs_alu_bp_a), .rs_alu_dispatch_pred_target_a(dr_rs_alu_pt_a),
        .rs_alu_dispatch_en_b(dr_rs_alu_en_b), .rs_alu_dispatch_opcode_b(dr_rs_alu_opc_b),
        .rs_alu_dispatch_src1_val_b(dr_rs_alu_s1v_b), .rs_alu_dispatch_src1_tag_b(dr_rs_alu_s1t_b), .rs_alu_dispatch_src1_rdy_b(dr_rs_alu_s1r_b),
        .rs_alu_dispatch_src2_val_b(dr_rs_alu_s2v_b), .rs_alu_dispatch_src2_tag_b(dr_rs_alu_s2t_b), .rs_alu_dispatch_src2_rdy_b(dr_rs_alu_s2r_b),
        .rs_alu_dispatch_dest_tag_b(dr_rs_alu_dt_b), .rs_alu_dispatch_rob_idx_b(dr_rs_alu_ri_b),
        .rs_alu_dispatch_imm_b(dr_rs_alu_imm_b), .rs_alu_dispatch_pc_b(dr_rs_alu_pc_b), .rs_alu_dispatch_br_pred_b(dr_rs_alu_bp_b), .rs_alu_dispatch_pred_target_b(dr_rs_alu_pt_b),
        // RS FPU
        .rs_fpu_dispatch_en_a(dr_rs_fpu_en_a), .rs_fpu_dispatch_opcode_a(dr_rs_fpu_opc_a),
        .rs_fpu_dispatch_src1_val_a(dr_rs_fpu_s1v_a), .rs_fpu_dispatch_src1_tag_a(dr_rs_fpu_s1t_a), .rs_fpu_dispatch_src1_rdy_a(dr_rs_fpu_s1r_a),
        .rs_fpu_dispatch_src2_val_a(dr_rs_fpu_s2v_a), .rs_fpu_dispatch_src2_tag_a(dr_rs_fpu_s2t_a), .rs_fpu_dispatch_src2_rdy_a(dr_rs_fpu_s2r_a),
        .rs_fpu_dispatch_dest_tag_a(dr_rs_fpu_dt_a), .rs_fpu_dispatch_rob_idx_a(dr_rs_fpu_ri_a),
        .rs_fpu_dispatch_imm_a(dr_rs_fpu_imm_a), .rs_fpu_dispatch_pc_a(dr_rs_fpu_pc_a), .rs_fpu_dispatch_br_pred_a(dr_rs_fpu_bp_a),
        .rs_fpu_dispatch_en_b(dr_rs_fpu_en_b), .rs_fpu_dispatch_opcode_b(dr_rs_fpu_opc_b),
        .rs_fpu_dispatch_src1_val_b(dr_rs_fpu_s1v_b), .rs_fpu_dispatch_src1_tag_b(dr_rs_fpu_s1t_b), .rs_fpu_dispatch_src1_rdy_b(dr_rs_fpu_s1r_b),
        .rs_fpu_dispatch_src2_val_b(dr_rs_fpu_s2v_b), .rs_fpu_dispatch_src2_tag_b(dr_rs_fpu_s2t_b), .rs_fpu_dispatch_src2_rdy_b(dr_rs_fpu_s2r_b),
        .rs_fpu_dispatch_dest_tag_b(dr_rs_fpu_dt_b), .rs_fpu_dispatch_rob_idx_b(dr_rs_fpu_ri_b),
        .rs_fpu_dispatch_imm_b(dr_rs_fpu_imm_b), .rs_fpu_dispatch_pc_b(dr_rs_fpu_pc_b), .rs_fpu_dispatch_br_pred_b(dr_rs_fpu_bp_b),
        // LSQ
        .lsq_ld_dispatch_en_a(dr_lsq_ld_en_a), .lsq_ld_dispatch_rob_idx_a(dr_lsq_ld_ri_a), .lsq_ld_dispatch_dest_tag_a(dr_lsq_ld_dt_a),
        .lsq_ld_dispatch_en_b(dr_lsq_ld_en_b), .lsq_ld_dispatch_rob_idx_b(dr_lsq_ld_ri_b), .lsq_ld_dispatch_dest_tag_b(dr_lsq_ld_dt_b),
        .lsq_st_dispatch_en_a(dr_lsq_st_en_a), .lsq_st_dispatch_rob_idx_a(dr_lsq_st_ri_a),
        .lsq_st_dispatch_data_a(dr_lsq_st_data_a), .lsq_st_dispatch_data_rdy_a(dr_lsq_st_drdy_a), .lsq_st_dispatch_data_tag_a(dr_lsq_st_dtag_a),
        .lsq_st_dispatch_en_b(dr_lsq_st_en_b), .lsq_st_dispatch_rob_idx_b(dr_lsq_st_ri_b),
        .lsq_st_dispatch_data_b(dr_lsq_st_data_b), .lsq_st_dispatch_data_rdy_b(dr_lsq_st_drdy_b), .lsq_st_dispatch_data_tag_b(dr_lsq_st_dtag_b)
    );

    // ================================================================
    // ALU Reservation Station (8 entries, dual dispatch, dual issue)
    // ================================================================
    wire        alu_rs_iv0, alu_rs_iv1;
    wire [4:0]  alu_rs_iopc0, alu_rs_iopc1;
    wire [63:0] alu_rs_is1v0, alu_rs_is2v0, alu_rs_is1v1, alu_rs_is2v1;
    wire [6:0]  alu_rs_idt0, alu_rs_idt1;
    wire [4:0]  alu_rs_iri0, alu_rs_iri1;
    wire [63:0] alu_rs_iimm0, alu_rs_iimm1, alu_rs_ipc0, alu_rs_ipc1;
    wire        alu_rs_ibp0, alu_rs_ibp1;
    wire [63:0] alu_rs_ipt0, alu_rs_ipt1;
    wire        alu_rs_grant0, alu_rs_grant1;

    reservation_station #(.NUM_ENTRIES(8)) u_rs_alu (
        .clk(clk), .reset(reset),
        .dispatch_en0(dr_rs_alu_en_a), .dispatch_opcode0(dr_rs_alu_opc_a),
        .dispatch_src1_value0(dr_rs_alu_s1v_a), .dispatch_src1_tag0(dr_rs_alu_s1t_a), .dispatch_src1_ready0(dr_rs_alu_s1r_a),
        .dispatch_src2_value0(dr_rs_alu_s2v_a), .dispatch_src2_tag0(dr_rs_alu_s2t_a), .dispatch_src2_ready0(dr_rs_alu_s2r_a),
        .dispatch_dest_tag0(dr_rs_alu_dt_a), .dispatch_rob_idx0(dr_rs_alu_ri_a),
        .dispatch_imm0(dr_rs_alu_imm_a), .dispatch_pc0(dr_rs_alu_pc_a), .dispatch_br_pred0(dr_rs_alu_bp_a), .dispatch_pred_target0(dr_rs_alu_pt_a),
        .dispatch_en1(dr_rs_alu_en_b), .dispatch_opcode1(dr_rs_alu_opc_b),
        .dispatch_src1_value1(dr_rs_alu_s1v_b), .dispatch_src1_tag1(dr_rs_alu_s1t_b), .dispatch_src1_ready1(dr_rs_alu_s1r_b),
        .dispatch_src2_value1(dr_rs_alu_s2v_b), .dispatch_src2_tag1(dr_rs_alu_s2t_b), .dispatch_src2_ready1(dr_rs_alu_s2r_b),
        .dispatch_dest_tag1(dr_rs_alu_dt_b), .dispatch_rob_idx1(dr_rs_alu_ri_b),
        .dispatch_imm1(dr_rs_alu_imm_b), .dispatch_pc1(dr_rs_alu_pc_b), .dispatch_br_pred1(dr_rs_alu_bp_b), .dispatch_pred_target1(dr_rs_alu_pt_b),
        .full(rs_alu_full_w), .almost_full(rs_alu_almost_full_w),
        .cdb_valid0(cdb_valid_bus0), .cdb_tag0(cdb_tag_bus0), .cdb_value0(cdb_value_bus0),
        .cdb_valid1(cdb_valid_bus1), .cdb_tag1(cdb_tag_bus1), .cdb_value1(cdb_value_bus1),
        .issue_valid0(alu_rs_iv0), .issue_opcode0(alu_rs_iopc0),
        .issue_src1_value0(alu_rs_is1v0), .issue_src2_value0(alu_rs_is2v0),
        .issue_dest_tag0(alu_rs_idt0), .issue_rob_idx0(alu_rs_iri0),
        .issue_imm0(alu_rs_iimm0), .issue_pc0(alu_rs_ipc0), .issue_br_pred0(alu_rs_ibp0), .issue_pred_target0(alu_rs_ipt0),
        .issue_grant0(alu_rs_grant0),
        .issue_valid1(alu_rs_iv1), .issue_opcode1(alu_rs_iopc1),
        .issue_src1_value1(alu_rs_is1v1), .issue_src2_value1(alu_rs_is2v1),
        .issue_dest_tag1(alu_rs_idt1), .issue_rob_idx1(alu_rs_iri1),
        .issue_imm1(alu_rs_iimm1), .issue_pc1(alu_rs_ipc1), .issue_br_pred1(alu_rs_ibp1), .issue_pred_target1(alu_rs_ipt1),
        .issue_grant1(alu_rs_grant1),
        .flush_en(do_flush), .flush_rob_idx(flush_rob_idx_w), .rob_head_idx(rob_head_idx)
    );

    // ================================================================
    // FPU Reservation Station (8 entries, dual dispatch, dual issue)
    // ================================================================
    wire        fpu_rs_iv0, fpu_rs_iv1;
    wire [4:0]  fpu_rs_iopc0, fpu_rs_iopc1;
    wire [63:0] fpu_rs_is1v0, fpu_rs_is2v0, fpu_rs_is1v1, fpu_rs_is2v1;
    wire [6:0]  fpu_rs_idt0, fpu_rs_idt1;
    wire [4:0]  fpu_rs_iri0, fpu_rs_iri1;
    wire [63:0] fpu_rs_iimm0, fpu_rs_iimm1, fpu_rs_ipc0, fpu_rs_ipc1;
    wire        fpu_rs_ibp0, fpu_rs_ibp1;
    wire        fpu_rs_grant0, fpu_rs_grant1;

    reservation_station #(.NUM_ENTRIES(8)) u_rs_fpu (
        .clk(clk), .reset(reset),
        .dispatch_en0(dr_rs_fpu_en_a), .dispatch_opcode0(dr_rs_fpu_opc_a),
        .dispatch_src1_value0(dr_rs_fpu_s1v_a), .dispatch_src1_tag0(dr_rs_fpu_s1t_a), .dispatch_src1_ready0(dr_rs_fpu_s1r_a),
        .dispatch_src2_value0(dr_rs_fpu_s2v_a), .dispatch_src2_tag0(dr_rs_fpu_s2t_a), .dispatch_src2_ready0(dr_rs_fpu_s2r_a),
        .dispatch_dest_tag0(dr_rs_fpu_dt_a), .dispatch_rob_idx0(dr_rs_fpu_ri_a),
        .dispatch_imm0(dr_rs_fpu_imm_a), .dispatch_pc0(dr_rs_fpu_pc_a), .dispatch_br_pred0(dr_rs_fpu_bp_a), .dispatch_pred_target0(64'd0),
        .dispatch_en1(dr_rs_fpu_en_b), .dispatch_opcode1(dr_rs_fpu_opc_b),
        .dispatch_src1_value1(dr_rs_fpu_s1v_b), .dispatch_src1_tag1(dr_rs_fpu_s1t_b), .dispatch_src1_ready1(dr_rs_fpu_s1r_b),
        .dispatch_src2_value1(dr_rs_fpu_s2v_b), .dispatch_src2_tag1(dr_rs_fpu_s2t_b), .dispatch_src2_ready1(dr_rs_fpu_s2r_b),
        .dispatch_dest_tag1(dr_rs_fpu_dt_b), .dispatch_rob_idx1(dr_rs_fpu_ri_b),
        .dispatch_imm1(dr_rs_fpu_imm_b), .dispatch_pc1(dr_rs_fpu_pc_b), .dispatch_br_pred1(dr_rs_fpu_bp_b), .dispatch_pred_target1(64'd0),
        .full(rs_fpu_full_w), .almost_full(rs_fpu_almost_full_w),
        .cdb_valid0(cdb_valid_bus0), .cdb_tag0(cdb_tag_bus0), .cdb_value0(cdb_value_bus0),
        .cdb_valid1(cdb_valid_bus1), .cdb_tag1(cdb_tag_bus1), .cdb_value1(cdb_value_bus1),
        .issue_valid0(fpu_rs_iv0), .issue_opcode0(fpu_rs_iopc0),
        .issue_src1_value0(fpu_rs_is1v0), .issue_src2_value0(fpu_rs_is2v0),
        .issue_dest_tag0(fpu_rs_idt0), .issue_rob_idx0(fpu_rs_iri0),
        .issue_imm0(fpu_rs_iimm0), .issue_pc0(fpu_rs_ipc0), .issue_br_pred0(fpu_rs_ibp0), .issue_pred_target0(),
        .issue_grant0(fpu_rs_grant0),
        .issue_valid1(fpu_rs_iv1), .issue_opcode1(fpu_rs_iopc1),
        .issue_src1_value1(fpu_rs_is1v1), .issue_src2_value1(fpu_rs_is2v1),
        .issue_dest_tag1(fpu_rs_idt1), .issue_rob_idx1(fpu_rs_iri1),
        .issue_imm1(fpu_rs_iimm1), .issue_pc1(fpu_rs_ipc1), .issue_br_pred1(fpu_rs_ibp1), .issue_pred_target1(),
        .issue_grant1(fpu_rs_grant1),
        .flush_en(do_flush), .flush_rob_idx(flush_rob_idx_w), .rob_head_idx(rob_head_idx)
    );

    // ================================================================
    // ALU Pipelines x2
    // ================================================================
    wire        alu0_valid_out, alu1_valid_out;
    wire [4:0]  alu0_opc_out, alu1_opc_out;
    wire [6:0]  alu0_dt_out, alu1_dt_out;
    wire [4:0]  alu0_ri_out, alu1_ri_out;
    wire [63:0] alu0_result, alu1_result;
    wire        alu0_is_br, alu1_is_br;
    wire        alu0_br_taken, alu1_br_taken;
    wire [63:0] alu0_br_target, alu1_br_target;
    wire        alu0_mispred, alu1_mispred;
    wire        alu0_ready, alu1_ready;

    // LOAD/STORE address computations should NOT broadcast on CDB
    wire alu0_is_mem = alu0_valid_out && ((alu0_opc_out == 5'h10) || (alu0_opc_out == 5'h13));
    wire alu1_is_mem = alu1_valid_out && ((alu1_opc_out == 5'h10) || (alu1_opc_out == 5'h13));
    wire alu0_cdb_valid = alu0_valid_out && !alu0_is_mem;
    wire alu1_cdb_valid = alu1_valid_out && !alu1_is_mem;

    wire        stall_alu0_cdb, stall_alu1_cdb;

    alu_pipe u_alu0 (
        .clk(clk), .reset(reset), .flush(do_flush),
        .stall(stall_alu0_cdb),
        .valid_in(alu_rs_iv0 && alu_rs_grant0),
        .opcode_in(alu_rs_iopc0), .src1_in(alu_rs_is1v0), .src2_in(alu_rs_is2v0),
        .dest_tag_in(alu_rs_idt0), .rob_idx_in(alu_rs_iri0),
        .imm_in(alu_rs_iimm0), .pc_in(alu_rs_ipc0), .br_pred_taken_in(alu_rs_ibp0), .pred_target_in(alu_rs_ipt0),
        .pipe_ready(alu0_ready),
        .valid_out(alu0_valid_out), .opcode_out(alu0_opc_out),
        .dest_tag_out(alu0_dt_out), .rob_idx_out(alu0_ri_out),
        .result_out(alu0_result), .is_branch_out(alu0_is_br),
        .branch_taken_out(alu0_br_taken), .branch_target_out(alu0_br_target),
        .mispredict_out(alu0_mispred)
    );

    alu_pipe u_alu1 (
        .clk(clk), .reset(reset), .flush(do_flush),
        .stall(stall_alu1_cdb),
        .valid_in(alu_rs_iv1 && alu_rs_grant1),
        .opcode_in(alu_rs_iopc1), .src1_in(alu_rs_is1v1), .src2_in(alu_rs_is2v1),
        .dest_tag_in(alu_rs_idt1), .rob_idx_in(alu_rs_iri1),
        .imm_in(alu_rs_iimm1), .pc_in(alu_rs_ipc1), .br_pred_taken_in(alu_rs_ibp1), .pred_target_in(alu_rs_ipt1),
        .pipe_ready(alu1_ready),
        .valid_out(alu1_valid_out), .opcode_out(alu1_opc_out),
        .dest_tag_out(alu1_dt_out), .rob_idx_out(alu1_ri_out),
        .result_out(alu1_result), .is_branch_out(alu1_is_br),
        .branch_taken_out(alu1_br_taken), .branch_target_out(alu1_br_target),
        .mispredict_out(alu1_mispred)
    );

    assign alu_rs_grant0 = alu_rs_iv0 && alu0_ready;
    assign alu_rs_grant1 = alu_rs_iv1 && alu1_ready;

    // ================================================================
    // FPU Pipelines x2
    // ================================================================
    wire        fpu0_valid_out, fpu1_valid_out;
    wire [6:0]  fpu0_dt_out, fpu1_dt_out;
    wire [4:0]  fpu0_ri_out, fpu1_ri_out;
    wire [63:0] fpu0_result, fpu1_result;
    wire        fpu0_ready, fpu1_ready;

    wire        stall_fpu0_cdb, stall_fpu1_cdb;

    fpu_pipe fpu (
        .clk(clk), .reset(reset), .flush(do_flush),
        .stall(stall_fpu0_cdb),
        .valid_in(fpu_rs_iv0 && fpu_rs_grant0),
        .opcode_in(fpu_rs_iopc0), .src1_in(fpu_rs_is1v0), .src2_in(fpu_rs_is2v0),
        .dest_tag_in(fpu_rs_idt0), .rob_idx_in(fpu_rs_iri0),
        .pipe_ready(fpu0_ready),
        .valid_out(fpu0_valid_out), .dest_tag_out(fpu0_dt_out), .rob_idx_out(fpu0_ri_out),
        .result_out(fpu0_result)
    );

    fpu_pipe u_fpu1 (
        .clk(clk), .reset(reset), .flush(do_flush),
        .stall(stall_fpu1_cdb),
        .valid_in(fpu_rs_iv1 && fpu_rs_grant1),
        .opcode_in(fpu_rs_iopc1), .src1_in(fpu_rs_is1v1), .src2_in(fpu_rs_is2v1),
        .dest_tag_in(fpu_rs_idt1), .rob_idx_in(fpu_rs_iri1),
        .pipe_ready(fpu1_ready),
        .valid_out(fpu1_valid_out), .dest_tag_out(fpu1_dt_out), .rob_idx_out(fpu1_ri_out),
        .result_out(fpu1_result)
    );

    assign fpu_rs_grant0 = fpu_rs_iv0 && fpu0_ready;
    assign fpu_rs_grant1 = fpu_rs_iv1 && fpu1_ready;

    // ================================================================
    // Load/Store Queue
    // ================================================================
    wire        lsq_load_result_valid;
    wire [6:0]  lsq_load_result_dt;
    wire [4:0]  lsq_load_result_ri;
    wire [63:0] lsq_load_result_data;
    wire        lsq_store_complete_valid;
    wire [4:0]  lsq_store_complete_ri;
    wire [63:0] lsq_store_complete_addr, lsq_store_complete_data;

    wire        lsq_mem_read_en;
    wire [63:0] lsq_mem_read_addr;
    wire        lsq_mem_write_en;
    wire [63:0] lsq_mem_write_addr, lsq_mem_write_data;

    // Address from ALU pipes: LOAD/STORE addresses are computed in ALU
    // We route completed LOAD/STORE results from ALU0/ALU1 to the LSQ
    // For simplicity, we use the CDB broadcast mechanism.
    // The ALU computes base+imm for LOAD/STORE opcodes and puts the address
    // in the result field. The LSQ listens for address arrival via rob_idx.

    load_store_queue u_lsq (
        .clk(clk), .reset(reset),
        .flush_en(do_flush), .flush_rob_idx(flush_rob_idx_w), .rob_head_idx(rob_head_idx),
        .ld_dispatch_en0(dr_lsq_ld_en_a), .ld_dispatch_rob_idx0(dr_lsq_ld_ri_a), .ld_dispatch_dest_tag0(dr_lsq_ld_dt_a),
        .ld_dispatch_en1(dr_lsq_ld_en_b), .ld_dispatch_rob_idx1(dr_lsq_ld_ri_b), .ld_dispatch_dest_tag1(dr_lsq_ld_dt_b),
        .ld_full(lsq_ld_full_w), .ld_almost_full(lsq_ld_almost_full_w),
        .st_dispatch_en0(dr_lsq_st_en_a), .st_dispatch_rob_idx0(dr_lsq_st_ri_a),
        .st_dispatch_data0(dr_lsq_st_data_a), .st_dispatch_data_ready0(dr_lsq_st_drdy_a), .st_dispatch_data_tag0(dr_lsq_st_dtag_a),
        .st_dispatch_en1(dr_lsq_st_en_b), .st_dispatch_rob_idx1(dr_lsq_st_ri_b),
        .st_dispatch_data1(dr_lsq_st_data_b), .st_dispatch_data_ready1(dr_lsq_st_drdy_b), .st_dispatch_data_tag1(dr_lsq_st_dtag_b),
        .st_full(lsq_st_full_w), .st_almost_full(lsq_st_almost_full_w),
        // Address arrival from ALU pipes — either ALU can compute either type.
        // LSQ matches by rob_idx, so we mux with ALU0 priority on ld_addr
        // and ALU1 priority on st_addr (covers single + dual address cycles).
        .ld_addr_valid(alu0_is_mem || alu1_is_mem),
        .ld_addr_rob_idx(alu0_is_mem ? alu0_ri_out : alu1_ri_out),
        .ld_addr_value(alu0_is_mem ? alu0_result : alu1_result),
        .st_addr_valid(alu1_is_mem || alu0_is_mem),
        .st_addr_rob_idx(alu1_is_mem ? alu1_ri_out : alu0_ri_out),
        .st_addr_value(alu1_is_mem ? alu1_result : alu0_result),
        .st_addr_data(64'd0), .st_addr_data_valid(1'b0),
        // CDB snoop for store data capture
        .cdb_valid0(cdb_valid_bus0), .cdb_tag0(cdb_tag_bus0), .cdb_value0(cdb_value_bus0),
        .cdb_valid1(cdb_valid_bus1), .cdb_tag1(cdb_tag_bus1), .cdb_value1(cdb_value_bus1),
        // Memory ports
        .mem_read_addr(lsq_mem_read_addr), .mem_read_en(lsq_mem_read_en),
        .mem_read_data(mem_data_out),
        .mem_write_en(lsq_mem_write_en), .mem_write_addr(lsq_mem_write_addr), .mem_write_data(lsq_mem_write_data),
        // Store commit (either ROB slot can commit a store)
        .store_commit_en((rob_commit_en0 && rob_commit_type0 == 3'd3) ||
                         (rob_commit_en1 && rob_commit_type1 == 3'd3)),
        .store_commit_rob_idx((rob_commit_en0 && rob_commit_type0 == 3'd3) ?
                              rob_head_idx : (rob_head_idx + 5'd1)),
        // Outputs
        .load_result_valid(lsq_load_result_valid), .load_result_dest_tag(lsq_load_result_dt),
        .load_result_rob_idx(lsq_load_result_ri), .load_result_data(lsq_load_result_data),
        .store_complete_valid(lsq_store_complete_valid), .store_complete_rob_idx(lsq_store_complete_ri),
        .store_complete_addr(lsq_store_complete_addr), .store_complete_data(lsq_store_complete_data)
    );

    // Memory read port wiring: LSQ drives data reads
    assign mem_data_addr = lsq_mem_read_addr;

    // ================================================================
    // Common Data Bus (2 buses, 6 sources)
    // ================================================================
    wire [2:0] cdb_win0_id, cdb_win1_id;
    wire       cdb_win0_valid, cdb_win1_valid;

    cdb u_cdb (
        .clk(clk), .reset(reset),
        .src_alu0_valid(alu0_cdb_valid), .src_alu0_tag(alu0_dt_out),
        .src_alu0_value(alu0_result), .src_alu0_rob_idx(alu0_ri_out),
        .src_alu1_valid(alu1_cdb_valid), .src_alu1_tag(alu1_dt_out),
        .src_alu1_value(alu1_result), .src_alu1_rob_idx(alu1_ri_out),
        .src_fpu0_valid(fpu0_valid_out), .src_fpu0_tag(fpu0_dt_out),
        .src_fpu0_value(fpu0_result), .src_fpu0_rob_idx(fpu0_ri_out),
        .src_fpu1_valid(fpu1_valid_out), .src_fpu1_tag(fpu1_dt_out),
        .src_fpu1_value(fpu1_result), .src_fpu1_rob_idx(fpu1_ri_out),
        .src_lsq0_valid(lsq_load_result_valid), .src_lsq0_tag(lsq_load_result_dt),
        .src_lsq0_value(lsq_load_result_data), .src_lsq0_rob_idx(lsq_load_result_ri),
        .src_lsq1_valid(lsq_store_complete_valid), .src_lsq1_tag(7'd0),
        .src_lsq1_value(lsq_store_complete_data), .src_lsq1_rob_idx(lsq_store_complete_ri),
        .cdb_valid0(cdb_valid_bus0), .cdb_tag0(cdb_tag_bus0),
        .cdb_value0(cdb_value_bus0), .cdb_rob_idx0(cdb_rob_idx_bus0),
        .cdb_valid1(cdb_valid_bus1), .cdb_tag1(cdb_tag_bus1),
        .cdb_value1(cdb_value_bus1), .cdb_rob_idx1(cdb_rob_idx_bus1),
        .stall_alu0(stall_alu0_cdb), .stall_alu1(stall_alu1_cdb),
        .stall_fpu0(stall_fpu0_cdb), .stall_fpu1(stall_fpu1_cdb),
        .stall_lsq0(), .stall_lsq1(),
        .win0_src_id(cdb_win0_id), .win0_valid(cdb_win0_valid),
        .win1_src_id(cdb_win1_id), .win1_valid(cdb_win1_valid)
    );

    // ================================================================
    // PRF writes from CDB
    // ================================================================
    assign prf_we0    = cdb_valid_bus0;
    assign prf_waddr0 = cdb_tag_bus0;
    assign prf_wdata0 = cdb_value_bus0;
    assign prf_we1    = cdb_valid_bus1;
    assign prf_waddr1 = cdb_tag_bus1;
    assign prf_wdata1 = cdb_value_bus1;

    // ================================================================
    // Branch side-band routing (CDB winner → ROB)
    // ================================================================
    always @(*) begin
        rob_cdb_store_addr0 = 64'd0;
        rob_cdb_br_actual0  = 1'b0;
        rob_cdb_mispredict0 = 1'b0;
        if (cdb_win0_valid) begin
            case (cdb_win0_id)
                3'd0: begin rob_cdb_br_actual0 = alu0_br_taken; rob_cdb_mispredict0 = alu0_mispred; rob_cdb_store_addr0 = alu0_br_target; end
                3'd1: begin rob_cdb_br_actual0 = alu1_br_taken; rob_cdb_mispredict0 = alu1_mispred; rob_cdb_store_addr0 = alu1_br_target; end
                3'd5: begin rob_cdb_store_addr0 = lsq_store_complete_addr; end
                default: ;
            endcase
        end

        rob_cdb_store_addr1 = 64'd0;
        rob_cdb_br_actual1  = 1'b0;
        rob_cdb_mispredict1 = 1'b0;
        if (cdb_win1_valid) begin
            case (cdb_win1_id)
                3'd0: begin rob_cdb_br_actual1 = alu0_br_taken; rob_cdb_mispredict1 = alu0_mispred; rob_cdb_store_addr1 = alu0_br_target; end
                3'd1: begin rob_cdb_br_actual1 = alu1_br_taken; rob_cdb_mispredict1 = alu1_mispred; rob_cdb_store_addr1 = alu1_br_target; end
                3'd5: begin rob_cdb_store_addr1 = lsq_store_complete_addr; end
                default: ;
            endcase
        end
    end

    // ================================================================
    // Misprediction detection and flush
    // ================================================================
    // Detect misprediction from CDB broadcast — if any ALU source on either
    // bus reported a misprediction this cycle, trigger flush.
    reg         mispredict_detected;
    reg  [4:0]  mispredict_rob_idx;

    always @(*) begin
        mispredict_detected = 1'b0;
        mispredict_rob_idx  = 5'd0;
        if (cdb_valid_bus0 && rob_cdb_mispredict0) begin
            mispredict_detected = 1'b1;
            mispredict_rob_idx  = cdb_rob_idx_bus0;
        end else if (cdb_valid_bus1 && rob_cdb_mispredict1) begin
            mispredict_detected = 1'b1;
            mispredict_rob_idx  = cdb_rob_idx_bus1;
        end
    end

    assign do_flush        = mispredict_detected && !flush_active;
    assign flush_rob_idx_w = mispredict_rob_idx;

    // ================================================================
    // Fetch unit flush + BHT update
    // ================================================================
    // Bypass redirect PC directly from CDB (available same cycle as flush)
    // rather than waiting for ROB's registered output.
    reg [63:0] mispredict_redirect_pc;
    always @(*) begin
        mispredict_redirect_pc = 64'd0;
        if (cdb_valid_bus0 && rob_cdb_mispredict0)
            mispredict_redirect_pc = cdb_value_bus0;
        else if (cdb_valid_bus1 && rob_cdb_mispredict1)
            mispredict_redirect_pc = cdb_value_bus1;
    end

    assign fetch_flush    = do_flush;
    assign fetch_flush_pc = mispredict_redirect_pc;

    // BHT update on branch completion via CDB (check both buses)
    wire bht_bus0_is_br = cdb_valid_bus0 && cdb_win0_valid &&
                          ((cdb_win0_id == 3'd0 && alu0_is_br) ||
                           (cdb_win0_id == 3'd1 && alu1_is_br));
    wire bht_bus1_is_br = cdb_valid_bus1 && cdb_win1_valid &&
                          ((cdb_win1_id == 3'd0 && alu0_is_br) ||
                           (cdb_win1_id == 3'd1 && alu1_is_br));

    assign bht_update_en = bht_bus0_is_br || bht_bus1_is_br;

    // Use branch instruction PC (s2_pc), not result (s2_result was redirect target — wrong!)
    assign bht_update_pc = bht_bus0_is_br ?
                           ((cdb_win0_id == 3'd0) ? u_alu0.s2_pc : u_alu1.s2_pc) :
                           ((cdb_win1_id == 3'd0) ? u_alu0.s2_pc : u_alu1.s2_pc);

    assign bht_pred_taken = bht_bus0_is_br ?
                            ((cdb_win0_id == 3'd0) ? u_alu0.s2_br_pred : u_alu1.s2_br_pred) :
                            ((cdb_win1_id == 3'd0) ? u_alu0.s2_br_pred : u_alu1.s2_br_pred);

    assign bht_actual_taken = bht_bus0_is_br ?
                              ((cdb_win0_id == 3'd0) ? alu0_br_taken : alu1_br_taken) :
                              ((cdb_win1_id == 3'd0) ? alu0_br_taken : alu1_br_taken);

    // ================================================================
    // BTB update on branch completion via CDB
    // ================================================================
    assign btb_update_en = bht_bus0_is_br || bht_bus1_is_br;

    assign btb_update_pc = bht_bus0_is_br ?
                           ((cdb_win0_id == 3'd0) ? u_alu0.s2_pc : u_alu1.s2_pc) :
                           ((cdb_win1_id == 3'd0) ? u_alu0.s2_pc : u_alu1.s2_pc);

    assign btb_update_target = bht_bus0_is_br ?
                               ((cdb_win0_id == 3'd0) ? alu0_br_target : alu1_br_target) :
                               ((cdb_win1_id == 3'd0) ? alu0_br_target : alu1_br_target);

    assign btb_update_taken = bht_bus0_is_br ?
                              ((cdb_win0_id == 3'd0) ? alu0_br_taken : alu1_br_taken) :
                              ((cdb_win1_id == 3'd0) ? alu0_br_taken : alu1_br_taken);

    // ================================================================
    // ROB Commit → Architectural Register File + Free List + Memory
    // ================================================================

    // Commit slot 0: write arch reg if has dest (not STORE, not BRANCH, not HALT)
    wire commit0_writes_reg = rob_commit_en0 &&
                              (rob_commit_type0 != 3'd3) && // not STORE
                              (rob_commit_type0 != 3'd4) && // not BRANCH
                              (rob_commit_type0 != 3'd5);   // not HALT

    wire commit1_writes_reg = rob_commit_en1 &&
                              (rob_commit_type1 != 3'd3) &&
                              (rob_commit_type1 != 3'd4) &&
                              (rob_commit_type1 != 3'd5);

    assign arch_we0    = commit0_writes_reg;
    assign arch_wsel0  = rob_commit_arch_rd0;
    assign arch_wdata0 = rob_commit_store_data0; // ROB `value` field = result

    assign arch_we1    = commit1_writes_reg;
    assign arch_wsel1  = rob_commit_arch_rd1;
    assign arch_wdata1 = rob_commit_store_data1;

    // Free old physical registers on commit
    wire commit0_has_old = commit0_writes_reg;
    wire commit1_has_old = commit1_writes_reg;

    // Free list: combine ROB commit frees + ROB flush drain frees
    assign fl_free_en0 = flush_active ? rob_flush_free_en0 :
                         commit0_has_old;
    assign fl_free_reg0 = flush_active ? rob_flush_free_reg0 :
                          rob_commit_old_phys0;

    assign fl_free_en1 = flush_active ? rob_flush_free_en1 :
                         commit1_has_old;
    assign fl_free_reg1 = flush_active ? rob_flush_free_reg1 :
                          rob_commit_old_phys1;

    // Memory store commit — only the LSQ writes to memory (after ROB signals commit)
    assign mem_write_en   = lsq_mem_write_en;
    assign mem_write_addr = lsq_mem_write_addr;
    assign mem_write_data = lsq_mem_write_data;

endmodule
