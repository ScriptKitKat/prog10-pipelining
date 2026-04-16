// tinker.sv — Pipelined Tinker processor (in-order, 5-stage with forwarding).
// Stages: FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK
// Data forwarding from EX, MEM, WB to DE. Stall only for load-use hazard.

`include "alu.sv"
`include "memory_reg.sv"

module tinker_core(
    input clk,
    input reset,
    output logic hlt
);

    // ================================================================
    // Pipeline register declarations (all before use for iverilog)
    // ================================================================
    reg [63:0] PC;

    // FETCH → DECODE
    reg        fd_valid;
    reg [31:0] fd_inst;
    reg [63:0] fd_pc;

    // DECODE → EXECUTE
    reg        dx_valid;
    reg [4:0]  dx_opcode;
    reg [4:0]  dx_rd, dx_rs, dx_rt;
    reg [11:0] dx_L;
    reg [63:0] dx_rd_data, dx_rs_data, dx_rt_data, dx_r31_data;
    reg [63:0] dx_pc;
    reg        dx_reg_we;
    reg        dx_mem_we;
    reg        dx_is_halt;
    reg        dx_is_return;
    reg        dx_is_call;
    reg        dx_is_load;
    reg [4:0]  dx_write_reg;

    // EXECUTE → MEMORY
    reg        xm_valid;
    reg [4:0]  xm_opcode;
    reg [63:0] xm_alu_result;
    reg [63:0] xm_write_data;
    reg [63:0] xm_mem_write_data;
    reg [4:0]  xm_write_reg;
    reg        xm_reg_we;
    reg        xm_mem_we;
    reg        xm_is_load;
    reg        xm_is_halt;
    reg        xm_is_return;

    // MEMORY → WRITEBACK
    reg        mw_valid;
    reg [63:0] mw_write_data;
    reg [4:0]  mw_write_reg;
    reg        mw_reg_we;
    reg        mw_is_halt;
    reg        mw_is_return;
    reg [63:0] mw_mem_read_data;

    // ================================================================
    // Memory
    // ================================================================
    wire [31:0] instruction;
    wire [63:0] mem_read_data;

    memory memory(
        .clk(clk),
        .reset(reset),
        .PC(PC),
        .instruction(instruction),
        .instr_fetch_addr(64'd0),
        .instr_fetch_data(),
        .data_address(xm_alu_result),
        .data_out(mem_read_data),
        .data_ready(),
        .write_enable(xm_valid && xm_mem_we),
        .write_address(xm_alu_result),
        .write_data(xm_mem_write_data)
    );

    // ================================================================
    // DECODE — instruction fields
    // ================================================================
    wire [4:0]  opcode = fd_inst[31:27];
    wire [4:0]  rd     = fd_inst[26:22];
    wire [4:0]  rs     = fd_inst[21:17];
    wire [4:0]  rt     = fd_inst[16:12];
    wire [11:0] L      = fd_inst[11:0];

    wire is_alu_reg = (opcode == 5'h18) || (opcode == 5'h1a) || (opcode == 5'h1c) || (opcode == 5'h1d) ||
                      (opcode == 5'h00) || (opcode == 5'h01) || (opcode == 5'h02) || (opcode == 5'h03) ||
                      (opcode == 5'h04) || (opcode == 5'h06) ||
                      (opcode == 5'h14) || (opcode == 5'h15) || (opcode == 5'h16) || (opcode == 5'h17);
    wire is_alu_L   = (opcode == 5'h19) || (opcode == 5'h1b) || (opcode == 5'h05) || (opcode == 5'h07);
    wire is_mov_rd  = (opcode == 5'h10) || (opcode == 5'h11) || (opcode == 5'h12);
    wire is_call    = (opcode == 5'h0c);
    wire is_return  = (opcode == 5'h0d);
    wire is_halt    = (opcode == 5'h0f) && (L == 12'h000);
    wire is_load    = (opcode == 5'h10);
    wire is_store   = (opcode == 5'h13);

    wire reg_write_en_comb = is_alu_reg || is_alu_L || is_mov_rd;
    wire mem_write_en_comb = is_store || is_call;
    wire [4:0] de_write_reg = (is_call || is_return) ? 5'd31 : rd;

    // ================================================================
    // Register file
    // ================================================================
    wire [63:0] rf_rd_data, rf_rs_data, rf_rt_data, rf_r31_data;

    reg_file reg_file(
        .clk(clk),
        .reset(reset),
        .write_enable(mw_valid && mw_reg_we),
        .write_data(mw_write_data),
        .write_select(mw_write_reg),
        .write_enable2(1'b0),
        .write_data2(64'd0),
        .write_select2(5'd0),
        .read_sel1(rd),
        .read_sel2(rs),
        .read_sel3(rt),
        .read_sel4(5'd0),
        .read_data1(rf_rd_data),
        .read_data2(rf_rs_data),
        .read_data3(rf_rt_data),
        .read_data4(),
        .read_r31(rf_r31_data)
    );

    // ================================================================
    // Forwarding logic
    // ================================================================
    // EX stage forward value
    wire [63:0] ex_fwd_val;
    wire        ex_fwd_valid;
    // MEM stage forward value (for loads: mem_read_data; otherwise xm_write_data)
    wire [63:0] mem_fwd_val = xm_is_load ? mem_read_data : xm_write_data;

    // Forward a specific register read through EX > MEM > WB priority
    // For a given 5-bit register index, return the most up-to-date value
    function [63:0] forward_reg;
        input [4:0]  regnum;
        input [63:0] rf_val;       // from register file
        // All other inputs accessed as module-level wires
        begin
            forward_reg = rf_val;  // default
        end
    endfunction

    // Forwarded register values (combinational)
    reg [63:0] fwd_rd_data, fwd_rs_data, fwd_rt_data, fwd_r31_data;

    always @(*) begin
        // rd forwarding
        if (dx_valid && dx_reg_we && dx_write_reg == rd && dx_write_reg != 5'd0)
            fwd_rd_data = ex_fwd_val;
        else if (xm_valid && xm_reg_we && xm_write_reg == rd && xm_write_reg != 5'd0)
            fwd_rd_data = mem_fwd_val;
        else if (mw_valid && mw_reg_we && mw_write_reg == rd && mw_write_reg != 5'd0)
            fwd_rd_data = mw_write_data;
        else
            fwd_rd_data = rf_rd_data;

        // rs forwarding
        if (dx_valid && dx_reg_we && dx_write_reg == rs && dx_write_reg != 5'd0)
            fwd_rs_data = ex_fwd_val;
        else if (xm_valid && xm_reg_we && xm_write_reg == rs && xm_write_reg != 5'd0)
            fwd_rs_data = mem_fwd_val;
        else if (mw_valid && mw_reg_we && mw_write_reg == rs && mw_write_reg != 5'd0)
            fwd_rs_data = mw_write_data;
        else
            fwd_rs_data = rf_rs_data;

        // rt forwarding
        if (dx_valid && dx_reg_we && dx_write_reg == rt && dx_write_reg != 5'd0)
            fwd_rt_data = ex_fwd_val;
        else if (xm_valid && xm_reg_we && xm_write_reg == rt && xm_write_reg != 5'd0)
            fwd_rt_data = mem_fwd_val;
        else if (mw_valid && mw_reg_we && mw_write_reg == rt && mw_write_reg != 5'd0)
            fwd_rt_data = mw_write_data;
        else
            fwd_rt_data = rf_rt_data;

        // r31 forwarding
        if (dx_valid && dx_reg_we && dx_write_reg == 5'd31)
            fwd_r31_data = ex_fwd_val;
        else if (xm_valid && xm_reg_we && xm_write_reg == 5'd31)
            fwd_r31_data = mem_fwd_val;
        else if (mw_valid && mw_reg_we && mw_write_reg == 5'd31)
            fwd_r31_data = mw_write_data;
        else
            fwd_r31_data = rf_r31_data;
    end

    // ================================================================
    // ALU (combinational, driven by EX stage regs)
    // ================================================================
    wire [63:0] alu_result;
    wire        alu_writeback;
    wire [63:0] alu_branch_target;
    wire        alu_branch_taken;

    ALU alu(
        .opcode(dx_opcode),
        .PC(dx_pc),
        .rd_data(dx_rd_data),
        .rs_data(dx_rs_data),
        .rt_data(dx_rt_data),
        .r31_data(dx_r31_data),
        .L_data(dx_L),
        .result(alu_result),
        .writeback(alu_writeback),
        .branch_target(alu_branch_target),
        .branch_taken(alu_branch_taken)
    );

    // EX forward value: for MOVI use read-modify-write result, otherwise ALU result
    assign ex_fwd_val = (dx_opcode == 5'h12) ? {dx_rd_data[63:12], dx_L} : alu_result;

    // ================================================================
    // Hazard / stall: only for load-use (load in EX, dependent in DE)
    // ================================================================
    wire load_use_hazard;
    wire reads_rs_de = is_alu_reg || is_load || (opcode == 5'h11) ||
                       (opcode == 5'h0b) || (opcode == 5'h0e) || is_store;
    wire reads_rt_de = (opcode == 5'h18) || (opcode == 5'h1a) || (opcode == 5'h1c) || (opcode == 5'h1d) ||
                       (opcode == 5'h00) || (opcode == 5'h01) || (opcode == 5'h02) ||
                       (opcode == 5'h04) || (opcode == 5'h06) ||
                       (opcode == 5'h14) || (opcode == 5'h15) || (opcode == 5'h16) || (opcode == 5'h17) ||
                       (opcode == 5'h0e);
    wire reads_rd_de = is_alu_L || (opcode == 5'h12) || is_store ||
                       (opcode == 5'h08) || (opcode == 5'h09) || (opcode == 5'h0b) || (opcode == 5'h0c) ||
                       (opcode == 5'h0e);

    assign load_use_hazard = fd_valid && dx_valid && dx_is_load && dx_reg_we && (
        (reads_rs_de && dx_write_reg == rs && dx_write_reg != 5'd0) ||
        (reads_rt_de && dx_write_reg == rt && dx_write_reg != 5'd0) ||
        (reads_rd_de && dx_write_reg == rd && dx_write_reg != 5'd0) ||
        ((is_call || is_return) && dx_write_reg == 5'd31)
    );

    wire stall = load_use_hazard;

    // ================================================================
    // Branch / flush control
    // ================================================================
    // RETURN is special: branch target comes from memory, not ALU.
    // For RETURN, flush in EX but don't redirect PC yet — wait for MEM.
    wire ex_branch = dx_valid && alu_branch_taken && !dx_is_return;
    wire ex_return = dx_valid && dx_is_return;
    wire flush = ex_branch || ex_return;

    // EX writeback data
    wire [63:0] ex_write_data = (dx_opcode == 5'h12) ? {dx_rd_data[63:12], dx_L} :
                                 alu_result;

    // Memory write data at EX
    wire [63:0] ex_mem_write_data = (dx_opcode == 5'h0c) ? (dx_pc + 64'd4) :
                                    (dx_opcode == 5'h13) ? dx_rs_data :
                                    dx_rt_data;

    // ================================================================
    // Pipeline advancement
    // ================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            PC <= `START;
            hlt <= 1'b0;
            fd_valid <= 1'b0;
            dx_valid <= 1'b0;
            xm_valid <= 1'b0;
            mw_valid <= 1'b0;
        end else begin

            // ======== WRITEBACK ========
            if (mw_valid && mw_is_halt)
                hlt <= 1'b1;

            // ======== MEM → WB ========
            mw_valid <= xm_valid;
            mw_write_reg <= xm_write_reg;
            mw_reg_we <= xm_reg_we;
            mw_is_halt <= xm_is_halt;
            mw_is_return <= xm_is_return && xm_valid;
            mw_mem_read_data <= mem_read_data;
            mw_write_data <= xm_is_load ? mem_read_data : xm_write_data;

            // ======== EX → MEM ========
            if (flush) begin
                xm_valid <= 1'b0;
            end else begin
                xm_valid <= dx_valid;
                xm_opcode <= dx_opcode;
                xm_alu_result <= alu_result;
                xm_write_data <= ex_write_data;
                xm_mem_write_data <= ex_mem_write_data;
                xm_write_reg <= dx_write_reg;
                xm_reg_we <= dx_reg_we;
                xm_mem_we <= dx_mem_we;
                xm_is_load <= dx_is_load;
                xm_is_halt <= dx_is_halt;
                xm_is_return <= dx_is_return;
            end

            // ======== DE → EX ========
            if (stall) begin
                dx_valid <= 1'b0;
            end else if (flush) begin
                dx_valid <= 1'b0;
            end else begin
                dx_valid <= fd_valid;
                dx_opcode <= opcode;
                dx_rd <= rd;
                dx_rs <= rs;
                dx_rt <= rt;
                dx_L <= L;
                dx_rd_data <= fwd_rd_data;
                dx_rs_data <= fwd_rs_data;
                dx_rt_data <= fwd_rt_data;
                dx_r31_data <= fwd_r31_data;
                dx_pc <= fd_pc;
                dx_reg_we <= reg_write_en_comb;
                dx_mem_we <= mem_write_en_comb;
                dx_is_halt <= is_halt;
                dx_is_return <= is_return;
                dx_is_call <= is_call;
                dx_is_load <= is_load;
                dx_write_reg <= de_write_reg;
            end

            // ======== FETCH ========
            if (stall) begin
                // Hold fd register and PC
            end else if (ex_branch) begin
                // Normal branch: redirect PC to branch target
                fd_valid <= 1'b0;
                PC <= alu_branch_target;
            end else if (ex_return) begin
                // RETURN: flush but don't redirect yet — wait for MEM read
                fd_valid <= 1'b0;
            end else if (xm_valid && xm_is_return) begin
                // RETURN's MEM stage: memory read is available, redirect PC
                fd_valid <= 1'b0;
                PC <= mem_read_data;
            end else if (mw_valid && mw_is_return) begin
                // One more bubble after return redirect
                fd_valid <= 1'b0;
            end else begin
                fd_valid <= 1'b1;
                fd_inst <= instruction;
                fd_pc <= PC;
                PC <= PC + 64'd4;
            end
        end
    end

endmodule
