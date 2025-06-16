`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module axis_2_axi_seg #(
    parameter SEGMENT_FIFO_DEPTH = 2048,
    parameter ASYNC_FIFO = 1'b1,
    // input axis register
    parameter INPUT_REGS = 0,
    // output axis registers
    parameter OUTPUT_REGS = 1
)(
    input  wire s_clk,
    input  wire s_rst,

    input  wire [1023:0]  s_axis_tdata,
    input  wire [127 :0]  s_axis_tkeep,
    input  wire           s_axis_tvalid,
    output wire           s_axis_tready,
    input  wire           s_axis_tlast,
    input  wire           s_axis_tuser,

    input  wire m_clk,
    input  wire m_rst,


    output wire [128*8-1:0] m_axis_seg_tdata,
    output wire             m_axis_seg_tvalid,
    input  wire             m_axis_seg_tready,
    output wire [7:0]       m_ena,
    output wire [7:0]       m_sop,
    output wire [7:0]       m_eop,
    output wire [7:0]       m_err,
    output wire [4*8-1:0]   m_mty

);

    function[2:0] keep2seg;
        input [127:0] keep_in;
        if (keep_in[127:16] == 112'd0) begin
            keep2seg = 0;
        end else if (keep_in[127:32] == 96'd0) begin
            keep2seg =  1;
        end else if (keep_in[127:48] == 80'd0) begin
            keep2seg = 2;
        end else if (keep_in[127:64] == 64'd0) begin
            keep2seg = 3;
        end else if (keep_in[127:80] == 48'd0) begin
            keep2seg = 4;
        end else if (keep_in[127:96] == 32'd0) begin
            keep2seg = 5;
        end else if (keep_in[127:112] == 16'd0) begin
            keep2seg = 6;
        end else begin
            keep2seg = 7;
        end
    endfunction

    function[7:0] keep2ena;
        input [127:0] keep_in;
        integer i;
        for (i=0; i<8; i=i+1) begin
            keep2ena[i] = |keep_in[i*16+:16];
        end
    endfunction

    function [7:0] count2ena;
        input [2:0] count;
        case (count)
            3'd0: count2ena = 8'h01;
            3'd1: count2ena = 8'h03;
            3'd2: count2ena = 8'h07;
            3'd3: count2ena = 8'h0F;
            3'd4: count2ena = 8'h1F;
            3'd5: count2ena = 8'h3F;
            3'd6: count2ena = 8'h7F;
            3'd7: count2ena = 8'hFF;
            default: count2ena =8'h00;
        endcase
    endfunction

    reg [2:0] out_offset_reg,  out_offset_next;
    reg [7:0][2:0] out_index_reg, out_index_next;

    integer k;


    wire [7:0] fifo_tready;

    wire [1023:0]    m_axis_input_reg_tdata;
    wire [127 :0]    m_axis_input_reg_tkeep;
    wire             m_axis_input_reg_tvalid;
    wire             m_axis_input_reg_tready;
    wire             m_axis_input_reg_tlast;
    wire             m_axis_input_reg_tuser;

    wire [128*8-1:0] m_axis_seg_reg_tdata;
    wire             m_axis_seg_reg_tvalid;
    wire             m_axis_seg_reg_tready;
    wire [7:0]       m_ena_reg;
    wire [7:0]       m_sop_reg;
    wire [7:0]       m_eop_reg;
    wire [7:0]       m_err_reg;
    wire [4*8-1:0]   m_mty_reg;

    wire [128*8-1:0] s_fifo_axis_seg_tdata;
    wire             s_fifo_axis_seg_tvalid;
    wire             s_fifo_axis_seg_tready;
    wire [7:0]       s_fifo_axis_seg_tuser_ena;
    wire [7:0]       s_fifo_axis_seg_tuser_sop;
    wire [7:0]       s_fifo_axis_seg_tuser_eop;
    wire [7:0]       s_fifo_axis_seg_tuser_err;
    wire [4*8-1:0]   s_fifo_axis_seg_tuser_mty;




    assign s_fifo_axis_seg_tready = &fifo_tready;

    wire [7:0] fifo_tvalid_out;
    wire [7:0] fifo_tready_out;
    wire [7:0][7:0] fifo_tuser_out;
    wire [7:0][127:0] fifo_tdata_out;

    wire [7:0] ena_fifo_out, sop_fifo_out, eop_fifo_out, err_fifo_out;
    wire [7:0][3:0] mty_fifo_out;

    generate
        if (INPUT_REGS > 0) begin

            axis_pipeline_register #(
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(128),
                .LAST_ENABLE(1),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .REG_TYPE(2),
                .LENGTH(INPUT_REGS)
            ) axis_pipeline_register_instance (
                .clk(s_clk),
                .rst(s_rst),
                .s_axis_tdata (s_axis_tdata),
                .s_axis_tkeep (s_axis_tkeep),
                .s_axis_tvalid(s_axis_tvalid),
                .s_axis_tready(s_axis_tready),
                .s_axis_tlast (s_axis_tlast),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser(s_axis_tuser),
                .m_axis_tdata (m_axis_input_reg_tdata),
                .m_axis_tkeep (m_axis_input_reg_tkeep),
                .m_axis_tvalid(m_axis_input_reg_tvalid),
                .m_axis_tready(m_axis_input_reg_tready),
                .m_axis_tlast (m_axis_input_reg_tlast),
                .m_axis_tuser (m_axis_input_reg_tuser)
            );
        end else begin

            assign m_axis_input_reg_tdata  = s_axis_tdata;
            assign m_axis_input_reg_tkeep  = s_axis_tkeep;
            assign m_axis_input_reg_tvalid = s_axis_tvalid;
            assign s_axis_tready           = m_axis_input_reg_tready;
            assign m_axis_input_reg_tlast  = s_axis_tlast;
            assign m_axis_input_reg_tuser  = s_axis_tuser;

        end
    endgenerate


    axis_2_axi_seg_input_ctrl axis_2_axi_seg_input_ctrl_instance (
        .clk(s_clk),
        .rst(s_rst),
        .s_axis_tdata (m_axis_input_reg_tdata),
        .s_axis_tkeep (m_axis_input_reg_tkeep),
        .s_axis_tvalid(m_axis_input_reg_tvalid),
        .s_axis_tready(m_axis_input_reg_tready),
        .s_axis_tlast (m_axis_input_reg_tlast),
        .s_axis_tuser (m_axis_input_reg_tuser),
        .m_axis_seg_tdata(s_fifo_axis_seg_tdata),
        .m_axis_seg_tvalid(s_fifo_axis_seg_tvalid),
        .m_axis_seg_tready(s_fifo_axis_seg_tready),
        .m_axis_seg_tuser_ena(s_fifo_axis_seg_tuser_ena),
        .m_axis_seg_tuser_sop(s_fifo_axis_seg_tuser_sop),
        .m_axis_seg_tuser_eop(s_fifo_axis_seg_tuser_eop),
        .m_axis_seg_tuser_err(s_fifo_axis_seg_tuser_err),
        .m_axis_seg_tuser_mty(s_fifo_axis_seg_tuser_mty)
    );
    



    generate

        for (genvar i=0; i<8; i=i+1) begin
            /*
            assign tdata[i]      = tdata_seg_reg[in_index_reg[i]];

            maptkeep2mty #(
                .REGISTER(1'b1)
            ) maptkeep2mty_instance (
                .clk(s_clk),
                .rst(s_rst),
                .s_axis_tkeep(s_axis_tkeep[i*16+:16] & {16{s_axis_tvalid}}),
                .m_mty(mty[i])
            );
            

            assign mty_shifted[i] = mty[in_index_reg[i]];
            */

            if (ASYNC_FIFO) begin
                axis_async_fifo #(
                    .DEPTH(SEGMENT_FIFO_DEPTH),
                    .DATA_WIDTH(128),
                    .LAST_ENABLE(0),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(8),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) segment_fifo (
                    .s_clk(s_clk),
                    .s_rst(s_rst),

                    // AXI input
                    .s_axis_tdata(s_fifo_axis_seg_tdata[128*i+:128]),
                    .s_axis_tkeep(16'hffff),
                    .s_axis_tvalid(s_fifo_axis_seg_tuser_ena[i] & s_fifo_axis_seg_tvalid & s_fifo_axis_seg_tready),
                    .s_axis_tready(fifo_tready[i]),
                    .s_axis_tlast(0),
                    .s_axis_tid(0),
                    .s_axis_tdest(0),
                    .s_axis_tuser({s_fifo_axis_seg_tuser_ena[i], s_fifo_axis_seg_tuser_sop[i], s_fifo_axis_seg_tuser_eop[i], s_fifo_axis_seg_tuser_err[i], s_fifo_axis_seg_tuser_mty[4*i+:4]}),

                    .m_clk(m_clk),
                    .m_rst(m_rst),
                    // AXI output
                    .m_axis_tdata (fifo_tdata_out[i]),
                    .m_axis_tvalid(fifo_tvalid_out[i]),
                    .m_axis_tready(fifo_tready_out[i]),
                    .m_axis_tuser({ena_fifo_out[i], sop_fifo_out[i], eop_fifo_out[i], err_fifo_out[i], mty_fifo_out[i]})
                );
            end else begin
                axis_fifo #(
                    .DEPTH(SEGMENT_FIFO_DEPTH),
                    .DATA_WIDTH(128),
                    .LAST_ENABLE(0),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(8),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) segment_fifo (
                    .clk(s_clk),
                    .rst(s_rst),

                    // AXI input
                    .s_axis_tdata(s_fifo_axis_seg_tdata[128*i+:128]),
                    .s_axis_tkeep(0),
                    .s_axis_tvalid(s_fifo_axis_seg_tuser_ena[i] & s_fifo_axis_seg_tvalid & s_fifo_axis_seg_tready),
                    .s_axis_tready(fifo_tready[i]),
                    .s_axis_tlast(0),
                    .s_axis_tid(0),
                    .s_axis_tdest(0),
                    .s_axis_tuser({s_fifo_axis_seg_tuser_ena[i], s_fifo_axis_seg_tuser_sop[i], s_fifo_axis_seg_tuser_eop[i], s_fifo_axis_seg_tuser_err[i], s_fifo_axis_seg_tuser_mty[4*i+:4]}),

                    // AXI output
                    .m_axis_tdata (fifo_tdata_out[i]),
                    .m_axis_tvalid(fifo_tvalid_out[i]),
                    .m_axis_tready(fifo_tready_out[i]),
                    .m_axis_tuser({ena_fifo_out[i], sop_fifo_out[i], eop_fifo_out[i], err_fifo_out[i], mty_fifo_out[i]})
                );
            end
        end
    endgenerate

    // align the fifo data out

    reg temp_ready_reg, temp_ready_next;
    wire fifo_temp_ready;

    always @(*) begin

        temp_ready_next = temp_ready_reg;

        if (|(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)) begin // eop seen
            case(out_offset_reg)
                3'd7: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZ1ZZZZZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZ01ZZZZZ:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[5:0]};
                        8'bZ001ZZZZ:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[4:0]};
                        8'bZ0001ZZZ:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[3:0]};
                        8'bZ00001ZZ:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[2:0]};
                        8'bZ000001Z:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[1:0]};
                        8'bZ0000001:temp_ready_next =  &{fifo_tvalid_out[7], fifo_tvalid_out[0]};
                        8'b10000000:temp_ready_next =  fifo_tvalid_out[7];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd6: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZ1ZZZZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZZ01ZZZZ:temp_ready_next =  &{fifo_tvalid_out[7:6], fifo_tvalid_out[4:0]};
                        8'bZZ001ZZZ:temp_ready_next =  &{fifo_tvalid_out[7:6], fifo_tvalid_out[3:0]};
                        8'bZZ0001ZZ:temp_ready_next =  &{fifo_tvalid_out[7:6], fifo_tvalid_out[2:0]};
                        8'bZZ00001Z:temp_ready_next =  &{fifo_tvalid_out[7:6], fifo_tvalid_out[1:0]};
                        8'bZZ000001:temp_ready_next =  &{fifo_tvalid_out[7:6], fifo_tvalid_out[0]};
                        8'b1Z000000:temp_ready_next =  &fifo_tvalid_out[7:6];
                        8'b01000000:temp_ready_next =  &fifo_tvalid_out[6:6];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd5: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZZ1ZZZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZZZ01ZZZ:temp_ready_next =  &{fifo_tvalid_out[7:5], fifo_tvalid_out[3:0]};
                        8'bZZZ001ZZ:temp_ready_next =  &{fifo_tvalid_out[7:5], fifo_tvalid_out[2:0]};
                        8'bZZZ0001Z:temp_ready_next =  &{fifo_tvalid_out[7:5], fifo_tvalid_out[1:0]};
                        8'bZZZ00001:temp_ready_next =  &{fifo_tvalid_out[7:5], fifo_tvalid_out[0]};
                        8'b1ZZ00000:temp_ready_next =  &fifo_tvalid_out[7:5];
                        8'b01Z00000:temp_ready_next =  &fifo_tvalid_out[6:5];
                        8'b00100000:temp_ready_next =  &fifo_tvalid_out[5:5];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd4: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZZZ1ZZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZZZZ01ZZ:temp_ready_next =  &{fifo_tvalid_out[7:4], fifo_tvalid_out[2:0]};
                        8'bZZZZ001Z:temp_ready_next =  &{fifo_tvalid_out[7:4], fifo_tvalid_out[1:0]};
                        8'bZZZZ0001:temp_ready_next =  &{fifo_tvalid_out[7:4], fifo_tvalid_out[0]};
                        8'b1ZZZ0000:temp_ready_next =  &fifo_tvalid_out[6:4];
                        8'b01ZZ0000:temp_ready_next =  &fifo_tvalid_out[5:4];
                        8'b001Z0000:temp_ready_next =  &fifo_tvalid_out[4:4];
                        8'b00010000:temp_ready_next =  &fifo_tvalid_out[4:4];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd3: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZZZZ1ZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZZZZZ01Z:temp_ready_next =  &{fifo_tvalid_out[7:3], fifo_tvalid_out[1:0]};
                        8'bZZZZZ001:temp_ready_next =  &{fifo_tvalid_out[7:3], fifo_tvalid_out[0]};
                        8'b1ZZZZ000:temp_ready_next =  &fifo_tvalid_out[7:3];
                        8'b01ZZZ000:temp_ready_next =  &fifo_tvalid_out[6:3];
                        8'b001ZZ000:temp_ready_next =  &fifo_tvalid_out[5:3];
                        8'b0001Z000:temp_ready_next =  &fifo_tvalid_out[4:3];
                        8'b00001000:temp_ready_next =  &fifo_tvalid_out[3:3];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd2: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZZZZZ1Z:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'bZZZZZZ01:temp_ready_next =  &{fifo_tvalid_out[7:2], fifo_tvalid_out[0]};
                        8'b1ZZZZZ00:temp_ready_next =  &fifo_tvalid_out[7:2];
                        8'b01ZZZZ00:temp_ready_next =  &fifo_tvalid_out[6:2];
                        8'b001ZZZ00:temp_ready_next =  &fifo_tvalid_out[5:2];
                        8'b0001ZZ00:temp_ready_next =  &fifo_tvalid_out[4:2];
                        8'b00001Z00:temp_ready_next =  &fifo_tvalid_out[3:2];
                        8'b00000100:temp_ready_next =  &fifo_tvalid_out[2:2];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd1: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'bZZZZZZZ1:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'b1ZZZZZZ0:temp_ready_next =  &fifo_tvalid_out[7:1];
                        8'b01ZZZZZ0:temp_ready_next =  &fifo_tvalid_out[6:1];
                        8'b001ZZZZ0:temp_ready_next =  &fifo_tvalid_out[5:1];
                        8'b0001ZZZ0:temp_ready_next =  &fifo_tvalid_out[4:1];
                        8'b00001ZZ0:temp_ready_next =  &fifo_tvalid_out[3:1];
                        8'b000001Z0:temp_ready_next =  &fifo_tvalid_out[2:1];
                        8'b00000010:temp_ready_next =  &fifo_tvalid_out[1:1];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                3'd0: begin
                    casez(eop_fifo_out & ena_fifo_out & fifo_tvalid_out)
                        8'b1ZZZZZZZ:temp_ready_next =  &fifo_tvalid_out[7:0];
                        8'b01ZZZZZZ:temp_ready_next =  &fifo_tvalid_out[6:0];
                        8'b001ZZZZZ:temp_ready_next =  &fifo_tvalid_out[5:0];
                        8'b0001ZZZZ:temp_ready_next =  &fifo_tvalid_out[4:0];
                        8'b00001ZZZ:temp_ready_next =  &fifo_tvalid_out[3:0];
                        8'b000001ZZ:temp_ready_next =  &fifo_tvalid_out[2:0];
                        8'b0000001Z:temp_ready_next =  &fifo_tvalid_out[1:0];
                        8'b00000001:temp_ready_next =  &fifo_tvalid_out[0:0];
                        default: temp_ready_next = 1'b0;
                    endcase
                end
                default: temp_ready_next = 1'b0;
            endcase
        end else begin // no end of packet, all fifos must have data
            temp_ready_next =  &fifo_tvalid_out[7:0];
        end
    end

    reg [15:0] temp_eop_ext = 16'd0, temp_sop_ext = 16'd0;
    reg [7 :0] temp_eop, temp_sop;

    always @(*) begin

        out_offset_next = out_offset_reg;

        out_index_next = out_index_reg;

        temp_eop_ext = {(ena_fifo_out & eop_fifo_out & fifo_tvalid_out & fifo_tready_out), 8'h00} >> out_offset_reg;
        temp_eop = temp_eop_ext[15:8] | temp_eop_ext[7:0];

        temp_sop_ext = {(ena_fifo_out & sop_fifo_out & fifo_tvalid_out & fifo_tready_out), 8'h00} >> out_offset_reg;
        temp_sop = temp_sop_ext[15:8] | temp_sop_ext[7:0];

        if (&(ena_fifo_out & fifo_tvalid_out & fifo_tready_out)) begin //all fifos are full and data available, no need for new out offset
            out_offset_next = out_offset_reg;
        end else begin
            casez(temp_eop)
                8'b1ZZZZZZZ:begin
                    if (temp_sop[0]) begin // new subsequent frame, no need for new offset
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd0;
                    end
                end
                8'bZ1ZZZZZZ:begin
                    if (temp_sop[7]) begin // new subsequent frame, no need for new offset
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd7;
                    end
                end
                8'bZZ1ZZZZZ:begin
                    if (temp_sop[6]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd6;
                    end
                end
                8'bZZZ1ZZZZ:begin
                    if (temp_sop[5]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd5;
                    end
                end
                8'bZZZZ1ZZZ:begin
                    if (temp_sop[4]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd4;
                    end
                end
                8'bZZZZZ1ZZ:begin
                    if (temp_sop[3]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd3;
                    end
                end
                8'bZZZZZZ1Z:begin
                    if (temp_sop[2]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd2;
                    end
                end
                8'bZZZZZZZ1:begin
                    if (temp_sop[1]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg + 3'd1;
                    end
                end
                8'b00000000:begin
                    if (temp_sop[0]) begin // new subsequent frame
                        out_offset_next = out_offset_reg;
                    end else begin // no new frame
                        out_offset_next = out_offset_reg;
                    end
                end
                default: begin
                    out_offset_next = out_offset_reg;
                end
            endcase
            for (k=0; k<8; k=k+1) begin
                out_index_next[k] = out_offset_next + k;
            end
        end
    end

    assign fifo_tready_out = {8{m_axis_seg_reg_tready}} & {8{temp_ready_reg}};

    always @(posedge m_clk) begin
        if (m_rst) begin
            out_offset_reg <= 3'd0;
            out_index_reg  <= {3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0};
            temp_ready_reg <= 1'b0;
        end else begin
            out_offset_reg <= out_offset_next;
            out_index_reg  <= out_index_next;
            temp_ready_reg <= temp_ready_next;
        end
    end

    for (genvar j=0; j<8; j=j+1) begin
        assign m_ena_reg[j]      = (fifo_tvalid_out[out_index_reg[j]] & temp_ready_reg) ? ena_fifo_out[out_index_reg[j]] : 1'b0;
        assign m_sop_reg[j]      = (fifo_tvalid_out[out_index_reg[j]] & temp_ready_reg) ? sop_fifo_out[out_index_reg[j]] : 1'b0;
        assign m_eop_reg[j]      = (fifo_tvalid_out[out_index_reg[j]] & temp_ready_reg) ? eop_fifo_out[out_index_reg[j]] : 1'b0;
        assign m_err_reg[j]      = (fifo_tvalid_out[out_index_reg[j]] & temp_ready_reg) ? err_fifo_out[out_index_reg[j]] : 1'b0;
        assign m_mty_reg[j*4+:4] = (fifo_tvalid_out[out_index_reg[j]] & temp_ready_reg) ? mty_fifo_out[out_index_reg[j]] : 4'd0;
        assign m_axis_seg_reg_tdata[j*128+:128] = fifo_tdata_out[out_index_reg[j]];
    end

    assign m_axis_seg_reg_tvalid = |m_ena_reg;

    generate
        if (OUTPUT_REGS > 0) begin

            axis_pipeline_register #(
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(0),
                .LAST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(64),
                .REG_TYPE(2),
                .LENGTH(OUTPUT_REGS)
            ) axis_pipeline_register_instance (
                .clk(m_clk),
                .rst(m_rst),
                .s_axis_tdata (m_axis_seg_reg_tdata),
                .s_axis_tkeep (0),
                .s_axis_tvalid(m_axis_seg_reg_tvalid),
                .s_axis_tready(m_axis_seg_reg_tready),
                .s_axis_tlast (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser({m_ena_reg, m_sop_reg, m_eop_reg, m_err_reg, m_mty_reg}),

                .m_axis_tdata (m_axis_seg_tdata),
                .m_axis_tvalid(m_axis_seg_tvalid),
                .m_axis_tready(m_axis_seg_tready),
                .m_axis_tuser ({m_ena, m_sop, m_eop, m_err, m_mty})
            );
        end else begin

            assign m_axis_seg_tdata      = m_axis_seg_reg_tdata;
            assign m_axis_seg_tvalid     = m_axis_seg_reg_tvalid;
            assign m_axis_seg_reg_tready = m_axis_seg_tready;
            assign m_ena                 = m_ena_reg;
            assign m_sop                 = m_sop_reg;
            assign m_eop                 = m_eop_reg;
            assign m_err                 = m_err_reg;
            assign m_mty                 = m_mty_reg;

        end
    endgenerate







endmodule