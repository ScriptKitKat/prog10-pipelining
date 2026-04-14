// Fetch unit: PC, 16-entry instruction FIFO, 64-byte line fetch,
// 1-bit BHT (256 entries), 64-entry BTB for register-indirect branches.

`ifndef TINKER_START_PC
`define TINKER_START_PC 64'h2000
`endif

module fetch_unit (
    input         clk,
    input         reset,

    output wire [63:0] instr_fetch_addr,
    input      [511:0] instr_fetch_data,

    input      [1:0]  decode_take,

    output reg [31:0] out0_inst,
    output reg [63:0] out0_pc,
    output reg        out0_br_pred,
    output reg [63:0] out0_pred_target,
    output reg        out0_valid,

    output reg [31:0] out1_inst,
    output reg [63:0] out1_pc,
    output reg        out1_br_pred,
    output reg [63:0] out1_pred_target,
    output reg        out1_valid,

    input             flush,
    input      [63:0] flush_pc,

    input             bht_update_en,
    input      [63:0] bht_update_pc,
    input             bht_pred_taken,
    input             bht_actual_taken,

    // BTB update from branch completion
    input             btb_update_en,
    input      [63:0] btb_update_pc,
    input      [63:0] btb_update_target,
    input             btb_update_taken
);

    localparam OPC_BRR_L = 5'h0A;

    function automatic is_branch_opcode(input [4:0] op);
        begin
            is_branch_opcode = (op == 5'h08) || (op == 5'h09) || (op == 5'h0a) ||
                               (op == 5'h0b) || (op == 5'h0c) || (op == 5'h0d) ||
                               (op == 5'h0e);
        end
    endfunction

    function automatic [3:0] inc_ptr(input [3:0] x);
        begin
            inc_ptr = (x == 4'd15) ? 4'd0 : (x + 4'd1);
        end
    endfunction

    reg [63:0] fetch_pc;
    reg [31:0] q_inst [0:15];
    reg [63:0] q_pc   [0:15];
    reg [15:0] q_pred;
    reg [63:0] q_pred_target [0:15];

    reg [3:0] wr_ptr;
    reg [3:0] rd_ptr;
    reg [4:0] q_count;

    // 1-bit BHT: 256 entries indexed by PC[9:2]
    reg [255:0] bht_bits;

    // BTB: 64 entries indexed by PC[7:2], direct-mapped
    reg [63:0] btb_valid;
    reg [63:0] btb_target [0:63];

    assign instr_fetch_addr = {fetch_pc[63:6], 6'b0};

    integer w;
    reg [4:0]  cnt;
    reg [3:0]  rp;
    reg [3:0]  wp;
    reg [63:0] fpc;
    reg [63:0] insn_pc;
    reg [31:0] insn_w;
    reg [4:0]  opc;
    reg        is_br;
    reg        pred_taken;
    reg [63:0] pred_target;
    reg [63:0] se_L;
    reg        stop_line;
    reg [1:0]  take;
    reg [63:0] lbase;
    reg [3:0]  sw;
    reg [3:0]  rdp1;
    reg [5:0]  btb_idx;

    integer ri;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_pc <= `TINKER_START_PC;
            wr_ptr   <= 4'd0;
            rd_ptr   <= 4'd0;
            q_count  <= 5'd0;
            bht_bits <= 256'b0;
            btb_valid <= 64'b0;

            out0_valid       <= 1'b0;
            out1_valid       <= 1'b0;
            out0_inst        <= 32'b0;
            out0_pc          <= 64'b0;
            out0_br_pred     <= 1'b0;
            out0_pred_target <= 64'b0;
            out1_inst        <= 32'b0;
            out1_pc          <= 64'b0;
            out1_br_pred     <= 1'b0;
            out1_pred_target <= 64'b0;

            for (ri = 0; ri < 64; ri = ri + 1)
                btb_target[ri] <= 64'd0;

        end else begin
            // BHT update: flip bit on misprediction
            if (bht_update_en && (bht_pred_taken != bht_actual_taken))
                bht_bits[bht_update_pc[9:2]] <= ~bht_bits[bht_update_pc[9:2]];

            // BTB update: store target for taken branches
            if (btb_update_en && btb_update_taken) begin
                btb_valid[btb_update_pc[7:2]]  <= 1'b1;
                btb_target[btb_update_pc[7:2]] <= btb_update_target;
            end

            if (flush) begin
                fetch_pc <= flush_pc;
                wr_ptr   <= 4'd0;
                rd_ptr   <= 4'd0;
                q_count  <= 5'd0;
                out0_valid <= 1'b0;
                out1_valid <= 1'b0;

            end else begin
                cnt = q_count;
                rp  = rd_ptr;
                wp  = wr_ptr;
                fpc = fetch_pc;

                case (decode_take)
                    2'd0: take = 2'd0;
                    2'd1: take = (cnt >= 5'd1) ? 2'd1 : 2'd0;
                    default: take = (cnt >= 5'd2) ? 2'd2 :
                                    (cnt == 5'd1) ? 2'd1 : 2'd0;
                endcase

                if (take == 2'd2) begin
                    cnt = cnt - 5'd2;
                    rp  = inc_ptr(inc_ptr(rd_ptr));
                end else if (take == 2'd1) begin
                    cnt = cnt - 5'd1;
                    rp  = inc_ptr(rd_ptr);
                end

                stop_line = 1'b0;
                lbase     = {fpc[63:6], 6'b0};
                sw        = fpc[5:2];

                if (cnt < 5'd16) begin
                    for (w = sw; w <= 15; w = w + 1) begin
                        if (!(stop_line || cnt >= 5'd16)) begin
                            insn_w  = instr_fetch_data[w * 32 +: 32];
                            insn_pc = lbase + (w << 2);
                            opc     = insn_w[31:27];
                            is_br   = is_branch_opcode(opc);
                            btb_idx = insn_pc[7:2];

                            pred_taken  = 1'b0;
                            pred_target = insn_pc + 64'd4; // default: fall-through

                            if (is_br) begin
                                if (opc == OPC_BRR_L) begin
                                    // BRR_L: target computable from immediate
                                    se_L = {{52{insn_w[11]}}, insn_w[11:0]};
                                    if (insn_w[11]) begin
                                        // Backward: static predict taken
                                        pred_taken  = 1'b1;
                                        pred_target = insn_pc + se_L;
                                    end else begin
                                        // Forward: use BHT
                                        pred_taken = bht_bits[insn_pc[9:2]];
                                        if (pred_taken)
                                            pred_target = insn_pc + se_L;
                                    end
                                end else begin
                                    // Register-indirect branch (BRNZ, BRGT, BR, BRR, CALL, RETURN)
                                    // Use BHT for taken/not-taken, BTB for target
                                    if (bht_bits[insn_pc[9:2]] && btb_valid[btb_idx]) begin
                                        pred_taken  = 1'b1;
                                        pred_target = btb_target[btb_idx];
                                    end
                                    // else: predict not-taken (no BTB entry = can't redirect)
                                end
                            end

                            q_inst[wp]        = insn_w;
                            q_pc[wp]          = insn_pc;
                            q_pred[wp]        = pred_taken;
                            q_pred_target[wp] = pred_target;

                            wp  = inc_ptr(wp);
                            cnt = cnt + 5'd1;
                            fpc = insn_pc + 64'd4;

                            // Redirect fetch on predicted-taken branch
                            if (is_br && pred_taken) begin
                                fpc = pred_target;
                                stop_line = 1'b1;
                            end
                        end
                    end
                end

                fetch_pc <= fpc;
                wr_ptr   <= wp;
                rd_ptr   <= rp;
                q_count  <= cnt;

                rdp1 = inc_ptr(rp);

                out0_valid       <= (cnt >= 5'd1);
                out1_valid       <= (cnt >= 5'd2);
                out0_inst        <= q_inst[rp];
                out0_pc          <= q_pc[rp];
                out0_br_pred     <= q_pred[rp];
                out0_pred_target <= q_pred_target[rp];
                out1_inst        <= q_inst[rdp1];
                out1_pc          <= q_pc[rdp1];
                out1_br_pred     <= q_pred[rdp1];
                out1_pred_target <= q_pred_target[rdp1];
            end
        end
    end

endmodule
