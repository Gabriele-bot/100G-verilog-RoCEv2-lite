`resetall `timescale 1ns / 1ps `default_nettype none

/*
8 AXI segmented to 1 AXI Stream, minimum frame length is supposed to be 64 Bytes or 4 segments.axi_seg_2_axis
This means that up to 2 frames can be sent in the same clock cycles  
 */
module axi_seg_2_axis #(
    parameter SEGMENT_FIFO_DEPTH = 2048,
    parameter AXIS_FIFO_DEPTH    = 8192,
    parameter ASYNC_FIFO = 1'b1,
    // input axis register
    parameter INPUT_REGS = 1
)(
    input  wire s_clk,
    input  wire s_rst,

    input  wire [128*8-1:0] s_axis_seg_tdata,
    input  wire             s_axis_seg_tvalid,
    output wire             s_axis_seg_tready,
    input  wire [7:0]       s_ena,
    input  wire [7:0]       s_sop,
    input  wire [7:0]       s_eop,
    input  wire [7:0]       s_err,
    input  wire [4*8-1:0]   s_mty,

    input  wire m_clk,
    input  wire m_rst,


    output  wire [1023:0]  m_axis_tdata,
    output  wire [127 :0]  m_axis_tkeep,
    output  wire           m_axis_tvalid,
    input   wire           m_axis_tready,
    output  wire           m_axis_tlast,
    output  wire           m_axis_tuser
);

    wire [7:0] fifo_in_tready;


    wire [128*8-1:0] fifo_tdata;
    wire [7:0]       fifo_tvalid;
    wire [7:0]       fifo_tready;
    wire [7:0]       fifo_ena;
    wire [7:0]       fifo_sop;
    wire [7:0]       fifo_eop;
    wire [7:0]       fifo_err;
    wire [4*8-1:0]   fifo_mty;

    reg [2:0] active_frame_reg, active_frame_next;

    reg [128*8-1:0] axis_seg_tdata_0_reg , axis_seg_tdata_0_next ;
    reg             axis_seg_tvalid_0_reg, axis_seg_tvalid_0_next;
    reg             axis_seg_tready_0_reg, axis_seg_tready_0_next;
    reg [7:0]       ena_0_reg            , ena_0_next            ;
    reg [7:0]       sop_0_reg            , sop_0_next            ;
    reg [7:0]       eop_0_reg            , eop_0_next            ;
    reg [7:0]       err_0_reg            , err_0_next            ;
    reg [4*8-1:0]   mty_0_reg            , mty_0_next            ;

    reg [128*8-1:0] axis_seg_tdata_1_reg , axis_seg_tdata_1_next ;
    reg             axis_seg_tvalid_1_reg, axis_seg_tvalid_1_next;
    reg             axis_seg_tready_1_reg, axis_seg_tready_1_next;
    reg [7:0]       ena_1_reg            , ena_1_next            ;
    reg [7:0]       sop_1_reg            , sop_1_next            ;
    reg [7:0]       eop_1_reg            , eop_1_next            ;
    reg [7:0]       err_1_reg            , err_1_next            ;
    reg [4*8-1:0]   mty_1_reg            , mty_1_next            ;

    reg [128*8-1:0] axis_seg_tdata_2_reg , axis_seg_tdata_2_next ;
    reg             axis_seg_tvalid_2_reg, axis_seg_tvalid_2_next;
    reg             axis_seg_tready_2_reg, axis_seg_tready_2_next;
    reg [7:0]       ena_2_reg            , ena_2_next            ;
    reg [7:0]       sop_2_reg            , sop_2_next            ;
    reg [7:0]       eop_2_reg            , eop_2_next            ;
    reg [7:0]       err_2_reg            , err_2_next            ;
    reg [4*8-1:0]   mty_2_reg            , mty_2_next            ;

    wire [1023:0]  s_axis_0_tdata;
    wire [127 :0]  s_axis_0_tkeep;
    wire           s_axis_0_tvalid;
    wire           s_axis_0_tready;
    wire           s_axis_0_tlast;
    wire           s_axis_0_tuser;

    wire [1023:0]  s_axis_1_tdata;
    wire [127 :0]  s_axis_1_tkeep;
    wire           s_axis_1_tvalid;
    wire           s_axis_1_tready;
    wire           s_axis_1_tlast;
    wire           s_axis_1_tuser;

    wire [1023:0]  s_axis_2_tdata;
    wire [127 :0]  s_axis_2_tkeep;
    wire           s_axis_2_tvalid;
    wire           s_axis_2_tready;
    wire           s_axis_2_tlast;
    wire           s_axis_2_tuser;

    generate

        wire [128*8-1:0] s_axis_seg_reg_tdata;
        wire             s_axis_seg_reg_tvalid;
        wire             s_axis_seg_reg_tready;
        wire [7:0]       s_ena_reg;
        wire [7:0]       s_sop_reg;
        wire [7:0]       s_eop_reg;
        wire [7:0]       s_err_reg;
        wire [4*8-1:0]   s_mty_reg;

        if (INPUT_REGS > 0) begin

            axis_pipeline_register #(
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(0),
                .LAST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(64),
                .REG_TYPE(2),
                .LENGTH(INPUT_REGS)
            ) axis_pipeline_register_instance (
                .clk(s_clk),
                .rst(s_rst),
                .s_axis_tdata (s_axis_seg_tdata),
                .s_axis_tkeep (0),
                .s_axis_tvalid(s_axis_seg_tvalid),
                .s_axis_tready(s_axis_seg_tready),
                .s_axis_tlast (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser({s_ena, s_sop, s_eop, s_err, s_mty}),

                .m_axis_tdata (s_axis_seg_reg_tdata),
                .m_axis_tvalid(s_axis_seg_reg_tvalid),
                .m_axis_tready(s_axis_seg_reg_tready),
                .m_axis_tuser ({s_ena_reg, s_sop_reg, s_eop_reg, s_err_reg, s_mty_reg})
            );
        end else begin

            assign s_axis_seg_reg_tdata  = s_axis_seg_tdata;
            assign s_axis_seg_reg_tvalid = s_axis_seg_tvalid;
            assign s_axis_seg_tready     = s_axis_seg_reg_tready;
            assign s_ena_reg             = s_ena;
            assign s_sop_reg             = s_sop;
            assign s_eop_reg             = s_eop;
            assign s_err_reg             = s_err;
            assign s_mty_reg             = s_mty;

        end

        for (genvar i=0; i<8; i=i+1) begin
            axis_pipeline_register #(
                .DATA_WIDTH(128),
                .KEEP_ENABLE(0),
                .LAST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(8),
                .REG_TYPE(2),
                .LENGTH(1)
            ) axis_pipeline_register_instance (
                .clk(s_clk),
                .rst(s_rst),

                // AXI input
                .s_axis_tdata(s_axis_seg_reg_tdata[128*i+:128]),
                .s_axis_tkeep(0),
                .s_axis_tvalid(s_ena_reg[i] & s_axis_seg_reg_tvalid & s_axis_seg_reg_tready),
                .s_axis_tready(fifo_in_tready[i]),
                .s_axis_tlast(0),
                .s_axis_tid(0),
                .s_axis_tdest(0),
                .s_axis_tuser({s_ena_reg[i], s_sop_reg[i], s_eop_reg[i], s_err_reg[i], s_mty_reg[i*4+:4]}),

                // AXI output
                .m_axis_tdata (fifo_tdata[128*i+:128]),
                .m_axis_tkeep (),
                .m_axis_tvalid(fifo_tvalid[i]),
                //.m_axis_tready(fifo_tready[i]),
                .m_axis_tready(1'b1),
                .m_axis_tlast (),
                .m_axis_tid   (),
                .m_axis_tdest (),
                .m_axis_tuser({fifo_ena[i], fifo_sop[i], fifo_eop[i], fifo_err[i], fifo_mty[i*4+:4]})
            );
            /*
            axis_fifo #(
                .DEPTH(SEGMENT_FIFO_DEPTH),
                .DATA_WIDTH(128),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(9),
                .RAM_PIPELINE(2),
                .FRAME_FIFO(0),
                .USER_BAD_FRAME_VALUE(256),
                .USER_BAD_FRAME_MASK(9'h100)
            ) segment_fifo (
                .clk(s_clk),
                .rst(s_rst),

                // AXI input
                .s_axis_tdata(s_axis_seg_reg_tdata[128*i+:128]),
                .s_axis_tkeep(16'hffff),
                .s_axis_tvalid(s_ena_reg[i] & s_axis_seg_reg_tvalid & s_axis_seg_reg_tready),
                .s_axis_tready(fifo_in_tready[i]),
                .s_axis_tlast(0),
                .s_axis_tid(0),
                .s_axis_tdest(0),
                .s_axis_tuser({1'b0, s_ena_reg[i], s_sop_reg[i], s_eop_reg[i], s_err_reg[i], s_mty_reg[i*4+:4]}),

                // AXI output
                .m_axis_tdata (fifo_tdata[128*i+:128]),
                .m_axis_tkeep (),
                .m_axis_tvalid(fifo_tvalid[i]),
                //.m_axis_tready(fifo_tready[i]),
                .m_axis_tready(1'b1),
                .m_axis_tlast (),
                .m_axis_tid   (),
                .m_axis_tdest (),
                .m_axis_tuser({fifo_ena[i], fifo_sop[i], fifo_eop[i], fifo_err[i], fifo_mty[i*4+:4]})
            );
            */
        end

        assign s_axis_seg_reg_tready = &fifo_in_tready;

    endgenerate




    always @(*) begin

        active_frame_next = active_frame_reg;

        axis_seg_tdata_0_next  = {128*8{1'b0}};
        axis_seg_tvalid_0_next = 1'b0;
        ena_0_next             = 8'h0;
        sop_0_next             = 8'h0;
        eop_0_next             = 8'h0;
        err_0_next             = 8'h0;
        mty_0_next             = 32'h00000000;

        axis_seg_tdata_1_next  = {128*8{1'b0}};
        axis_seg_tvalid_1_next = 1'b0;
        ena_1_next             = 8'h0;
        sop_1_next             = 8'h0;
        eop_1_next             = 8'h0;
        err_1_next             = 8'h0;
        mty_1_next             = 32'h00000000;

        axis_seg_tdata_2_next  = {128*8{1'b0}};
        axis_seg_tvalid_2_next = 1'b0;
        ena_2_next             = 8'h0;
        sop_2_next             = 8'h0;
        eop_2_next             = 8'h0;
        err_2_next             = 8'h0;
        mty_2_next             = 32'h00000000;

        case({active_frame_reg})
            3'b000: begin // no active frames
                active_frame_next[2] = 1'b0; // cannot have 3 frames active at time, 64 Byte min length
                if (fifo_ena[0] & fifo_sop[0] & fifo_tvalid[0]) begin // start of frame on the first segment
                    if (|(fifo_ena[7:3] & fifo_eop[7:3] & fifo_tvalid[7:3])) begin // end of frame already on the first clock cycle
                        active_frame_next[0] = 1'b0;
                        casez(fifo_eop[7:3])
                            5'bZZZZ1: begin
                                axis_seg_tdata_0_next[128*4-1:0]      = fifo_tdata[128*4-1:0];
                                axis_seg_tdata_0_next[128*8-1:128*4]  = {128*4{1'b0}};
                                axis_seg_tvalid_0_next = 1'b1;
                                ena_0_next             = {4'h0, fifo_ena[3:0]};
                                sop_0_next             = {4'h0, fifo_sop[3:0]};
                                eop_0_next             = {4'h0, fifo_eop[3:0]};
                                err_0_next             = {4'h0, fifo_err[3:0]};
                                mty_0_next             = {16'h0000, fifo_mty[4*4-1:0]};
                            end
                            5'bZZZ10: begin
                                axis_seg_tdata_0_next[128*5-1:0]      = fifo_tdata[128*5-1:0];
                                axis_seg_tdata_0_next[128*8-1:128*5]  = {128*3{1'b0}};
                                axis_seg_tvalid_0_next = 1'b1;
                                ena_0_next             = {3'h0, fifo_ena[4:0]};
                                sop_0_next             = {3'h0, fifo_sop[4:0]};
                                eop_0_next             = {3'h0, fifo_eop[4:0]};
                                err_0_next             = {3'h0, fifo_err[4:0]};
                                mty_0_next             = {12'h000, fifo_mty[5*4-1:0]};
                            end
                            5'bZZ100: begin
                                axis_seg_tdata_0_next[128*6-1:0]      = fifo_tdata[128*6-1:0];
                                axis_seg_tdata_0_next[128*8-1:128*6]  = {128*2{1'b0}};
                                axis_seg_tvalid_0_next = 1'b1;
                                ena_0_next             = {2'h0, fifo_ena[5:0]};
                                sop_0_next             = {2'h0, fifo_sop[5:0]};
                                eop_0_next             = {2'h0, fifo_eop[5:0]};
                                err_0_next             = {2'h0, fifo_err[5:0]};
                                mty_0_next             = {8'h0, fifo_mty[6*4-1:0]};
                            end
                            5'bZ1000: begin
                                axis_seg_tdata_0_next[128*7-1:0]      = fifo_tdata[128*7-1:0];
                                axis_seg_tdata_0_next[128*8-1:128*7]  = {128*1{1'b0}};
                                axis_seg_tvalid_0_next = 1'b1;
                                ena_0_next             = {1'b0, fifo_ena[6:0]};
                                sop_0_next             = {1'b0, fifo_sop[6:0]};
                                eop_0_next             = {1'b0, fifo_eop[6:0]};
                                err_0_next             = {1'b0, fifo_err[6:0]};
                                mty_0_next             = {4'h0, fifo_mty[7*4-1:0]};
                            end
                            5'b10000: begin
                                active_frame_next[0]   = 1'b1;
                                axis_seg_tdata_0_next  = fifo_tdata;
                                axis_seg_tvalid_0_next = |(fifo_ena & fifo_tvalid);
                                ena_0_next             = fifo_ena & fifo_tvalid;
                                sop_0_next             = fifo_sop & fifo_tvalid;
                                eop_0_next             = fifo_eop & fifo_tvalid;
                                err_0_next             = fifo_err & fifo_tvalid;
                                mty_0_next             = fifo_mty;
                            end
                        endcase
                    end else begin
                        active_frame_next[0]   = 1'b1;
                        axis_seg_tdata_0_next  = fifo_tdata;
                        axis_seg_tvalid_0_next = |(fifo_ena  & fifo_tvalid);
                        ena_0_next             = fifo_ena & fifo_tvalid;
                        sop_0_next             = fifo_sop & fifo_tvalid;
                        eop_0_next             = fifo_eop & fifo_tvalid;
                        err_0_next             = fifo_err & fifo_tvalid;
                        mty_0_next             = fifo_mty;
                    end
                end

                if (|(fifo_ena[7:4] & fifo_sop[7:4] & fifo_tvalid[7:4])) begin // a second packet can only start on last four segments
                    if ((fifo_ena[4] & fifo_sop[4] & fifo_tvalid[4]) & (fifo_ena[7] & fifo_eop[7] & fifo_tvalid[7])) begin // end of frame 1 already on the first clock cycle
                        active_frame_next[1] = 1'b0;
                        axis_seg_tdata_1_next[128*8-1:128*4]      = fifo_tdata[128*8-1:128*4];
                        axis_seg_tdata_1_next[128*4-1:0]  = {128*4{1'b0}};
                        axis_seg_tvalid_1_next = 1'b1;
                        ena_1_next             = {fifo_ena[7:4], 4'h0};
                        sop_1_next             = {fifo_sop[7:4], 4'h0};
                        eop_1_next             = {fifo_eop[7:4], 4'h0};
                        err_1_next             = {fifo_err[7:4], 4'h0};
                        mty_1_next             = {fifo_mty[8*4-1:4*4], 16'h0000};
                    end else begin
                        active_frame_next[1] = 1'b1;
                        casez(fifo_sop[7:4])
                            4'bZZZ1: begin
                                axis_seg_tdata_1_next[128*8-1:128*4]      = fifo_tdata[128*8-1:128*4];
                                axis_seg_tdata_1_next[128*4-1:0]  = {128*4{1'b0}};
                                axis_seg_tvalid_1_next = 1'b1;
                                ena_1_next             = {fifo_ena[7:4], 4'h0};
                                sop_1_next             = {fifo_sop[7:4], 4'h0};
                                eop_1_next             = {fifo_eop[7:4], 4'h0};
                                err_1_next             = {fifo_err[7:4], 4'h0};
                                mty_1_next             = {fifo_mty[8*4-1:4*4], 16'h0000};
                            end
                            4'bZZ10: begin
                                axis_seg_tdata_1_next[128*8-1:128*5]      = fifo_tdata[128*8-1:128*5];
                                axis_seg_tdata_1_next[128*5-1:0]  = {128*5{1'b0}};
                                axis_seg_tvalid_1_next = 1'b1;
                                ena_1_next             = {fifo_ena[7:5], 5'h00};
                                sop_1_next             = {fifo_sop[7:5], 5'h00};
                                eop_1_next             = {fifo_eop[7:5], 5'h00};
                                err_1_next             = {fifo_err[7:5], 5'h00};
                                mty_1_next             = {fifo_mty[8*4-1:5*4], 20'h00000};
                            end
                            4'bZ100: begin
                                axis_seg_tdata_1_next[128*8-1:128*6]      = fifo_tdata[128*8-1:128*6];
                                axis_seg_tdata_1_next[128*6-1:0]  = {128*6{1'b0}};
                                axis_seg_tvalid_1_next = 1'b1;
                                ena_1_next             = {fifo_ena[7:6], 6'h00};
                                sop_1_next             = {fifo_sop[7:6], 6'h00};
                                eop_1_next             = {fifo_eop[7:6], 6'h00};
                                err_1_next             = {fifo_err[7:6], 6'h00};
                                mty_1_next             = {fifo_mty[8*4-1:6*4], 24'h000000};
                            end
                            4'b1000: begin
                                axis_seg_tdata_1_next[128*8-1:128*7]      = fifo_tdata[128*8-1:128*7];
                                axis_seg_tdata_1_next[128*7-1:0]  = {128*7{1'b0}};
                                axis_seg_tvalid_1_next = 1'b1;
                                ena_1_next             = {fifo_ena[7:7], 7'h00};
                                sop_1_next             = {fifo_sop[7:7], 7'h00};
                                eop_1_next             = {fifo_eop[7:7], 7'h00};
                                err_1_next             = {fifo_err[7:7], 7'h00};
                                mty_1_next             = {fifo_mty[8*4-1:7*4], 28'h0000000};
                            end
                        endcase
                    end
                end
            end
            3'b001: begin // only first frame is active

                axis_seg_tdata_0_next  = fifo_tdata;
                axis_seg_tvalid_0_next = |(fifo_ena & fifo_tvalid);
                ena_0_next             = fifo_ena  & fifo_tvalid;
                sop_0_next             = fifo_sop  & fifo_tvalid;
                eop_0_next             = fifo_eop  & fifo_tvalid;
                err_0_next             = fifo_err  & fifo_tvalid;
                mty_0_next             = fifo_mty;

                axis_seg_tdata_1_next  = {128*8{1'b0}};
                axis_seg_tvalid_1_next = 1'b0;
                ena_1_next             = 8'h0;
                sop_1_next             = 8'h0;
                eop_1_next             = 8'h0;
                err_1_next             = 8'h0;
                mty_1_next             = 32'h00000000;

                axis_seg_tdata_2_next  = {128*8{1'b0}};
                axis_seg_tvalid_2_next = 1'b0;
                ena_2_next             = 8'h0;
                sop_2_next             = 8'h0;
                eop_2_next             = 8'h0;
                err_2_next             = 8'h0;
                mty_2_next             = 32'h00000000;

                if (|(fifo_ena & fifo_eop & fifo_tvalid)) begin // end of frame on any position
                    active_frame_next[0] = 1'b0;
                end

                if (|(fifo_ena[7:1] & fifo_sop[7:1] & fifo_tvalid[7:1])) begin // new frame, need to put it on frame 1 (cannot happen on segment 0)
                    if (|(fifo_ena[3:0] & fifo_eop[3:0] & fifo_tvalid[3:0]) & |(fifo_ena[7:4] & fifo_eop[7:4] & fifo_tvalid[7:4])) begin // two end of frame values, no new active frames as they both stop here
                        active_frame_next[1] = 1'b0;
                    end else begin // frame 1 is now active
                        active_frame_next[1] = 1'b1;
                    end


                    casez(fifo_sop[7:1])
                        7'bZZZZZZ1: begin

                            axis_seg_tdata_0_next[128*8-1:128*1]  = {128*7{1'b0}};
                            ena_0_next[7:1]             = 7'h00;
                            sop_0_next[7:1]             = 7'h00;
                            eop_0_next[7:1]             = 7'h00;
                            err_0_next[7:1]             = 7'h00;
                            mty_0_next[8*4-1:1*4]       = 28'h0000000;

                            if (|(fifo_sop[7:5])) begin
                                active_frame_next[2] = 1'b1;
                            end

                            casez(fifo_sop[7:5])
                                3'b000: begin
                                    axis_seg_tdata_1_next[128*8-1:128*1]  = fifo_tdata[128*8-1:128*1] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:1]             = fifo_ena[7:1] & fifo_tvalid[7:1];
                                    sop_1_next[7:1]             = fifo_sop[7:1] & fifo_tvalid[7:1];
                                    eop_1_next[7:1]             = fifo_eop[7:1] & fifo_tvalid[7:1];
                                    err_1_next[7:1]             = fifo_err[7:1] & fifo_tvalid[7:1];
                                    mty_1_next[8*4-1:1*4]       = fifo_mty[8*4-1:1*4];
                                end
                                3'bZZ1: begin

                                    axis_seg_tdata_1_next[128*5-1:128*1]  = fifo_tdata[128*5-1:128*1] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[4:1]             = fifo_ena[4:1] & fifo_tvalid[4:1];
                                    sop_1_next[4:1]             = fifo_sop[4:1] & fifo_tvalid[4:1];
                                    eop_1_next[4:1]             = fifo_eop[4:1] & fifo_tvalid[4:1];
                                    err_1_next[4:1]             = fifo_err[4:1] & fifo_tvalid[4:1];
                                    mty_1_next[5*4-1:1*4]       = fifo_mty[5*4-1:1*4];

                                    axis_seg_tdata_2_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                                    sop_2_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                                    eop_2_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                                    err_2_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                                    mty_2_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                                end
                                3'bZ10: begin

                                    axis_seg_tdata_1_next[128*6-1:128*1]  = fifo_tdata[128*6-1:128*1] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[5:1]             = fifo_ena[5:1] & fifo_tvalid[5:1];
                                    sop_1_next[5:1]             = fifo_sop[5:1] & fifo_tvalid[5:1];
                                    eop_1_next[5:1]             = fifo_eop[5:1] & fifo_tvalid[5:1];
                                    err_1_next[5:1]             = fifo_err[5:1] & fifo_tvalid[5:1];
                                    mty_1_next[6*4-1:1*4]       = fifo_mty[6*4-1:1*4];

                                    axis_seg_tdata_2_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_2_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_2_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_2_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_2_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];


                                end
                                3'b100: begin

                                    axis_seg_tdata_1_next[128*7-1:128*1]  = fifo_tdata[128*7-1:128*1] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[6:1]             = fifo_ena[6:1] & fifo_tvalid[6:1];
                                    sop_1_next[6:1]             = fifo_sop[6:1] & fifo_tvalid[6:1];
                                    eop_1_next[6:1]             = fifo_eop[6:1] & fifo_tvalid[6:1];
                                    err_1_next[6:1]             = fifo_err[6:1] & fifo_tvalid[6:1];
                                    mty_1_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                    axis_seg_tdata_2_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_2_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_2_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_2_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_2_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZZ10: begin

                            axis_seg_tdata_0_next[128*8-1:128*2]  = {128*6{1'b0}};
                            ena_0_next[7:2]             = 6'h00;
                            sop_0_next[7:2]             = 6'h00;
                            eop_0_next[7:2]             = 6'h00;
                            err_0_next[7:2]             = 6'h00;
                            mty_0_next[8*4-1:2*4]       = 24'h000000;

                            if (|(fifo_sop[7:6])) begin
                                active_frame_next[2] = 1'b1;
                            end

                            casez(fifo_sop[7:6])
                                2'b00: begin
                                    axis_seg_tdata_1_next[128*8-1:128*2]  = fifo_tdata[128*8-1:128*2] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:2]             = fifo_ena[7:2] & fifo_tvalid[7:2];
                                    sop_1_next[7:2]             = fifo_sop[7:2] & fifo_tvalid[7:2];
                                    eop_1_next[7:2]             = fifo_eop[7:2] & fifo_tvalid[7:2];
                                    err_1_next[7:2]             = fifo_err[7:2] & fifo_tvalid[7:2];
                                    mty_1_next[8*4-1:2*4]       = fifo_mty[8*4-1:2*4];
                                end
                                2'bZ1: begin

                                    axis_seg_tdata_1_next[128*6-1:128*2]  = fifo_tdata[128*6-1:128*2] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[5:2]             = fifo_ena[5:2] & fifo_tvalid[5:2];
                                    sop_1_next[5:2]             = fifo_sop[5:2] & fifo_tvalid[5:2];
                                    eop_1_next[5:2]             = fifo_eop[5:2] & fifo_tvalid[5:2];
                                    err_1_next[5:2]             = fifo_err[5:2] & fifo_tvalid[5:2];
                                    mty_1_next[6*4-1:2*4]       = fifo_mty[6*4-1:2*4];

                                    axis_seg_tdata_2_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_2_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_2_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_2_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_2_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                                end
                                2'b10: begin

                                    axis_seg_tdata_1_next[128*7-1:128*2]  = fifo_tdata[128*7-1:128*2] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[6:2]             = fifo_ena[6:2] & fifo_tvalid[6:2];
                                    sop_1_next[6:2]             = fifo_sop[6:2] & fifo_tvalid[6:2];
                                    eop_1_next[6:2]             = fifo_eop[6:2] & fifo_tvalid[6:2];
                                    err_1_next[6:2]             = fifo_err[6:2] & fifo_tvalid[6:2];
                                    mty_1_next[7*4-1:2*4]       = fifo_mty[7*4-1:2*4];

                                    axis_seg_tdata_2_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_2_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_2_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_2_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_2_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZ100: begin

                            axis_seg_tdata_0_next[128*8-1:128*3]  = {128*5{1'b0}};
                            ena_0_next[7:3]             = 5'h00;
                            sop_0_next[7:3]             = 5'h00;
                            eop_0_next[7:3]             = 5'h00;
                            err_0_next[7:3]             = 5'h00;
                            mty_0_next[8*4-1:3*4]       = 20'h00000;



                            if (fifo_sop[7]) begin

                                active_frame_next[2] = 1'b1;

                                axis_seg_tdata_1_next[128*7-1:128*3]  = fifo_tdata[128*7-1:128*3] ;
                                axis_seg_tvalid_1_next      = 1'b1;
                                ena_1_next[6:3]             = fifo_ena[6:3] & fifo_tvalid[6:3];
                                sop_1_next[6:3]             = fifo_sop[6:3] & fifo_tvalid[6:3];
                                eop_1_next[6:3]             = fifo_eop[6:3] & fifo_tvalid[6:3];
                                err_1_next[6:3]             = fifo_err[6:3] & fifo_tvalid[6:3];
                                mty_1_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                axis_seg_tdata_2_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                axis_seg_tvalid_2_next      = 1'b1;
                                ena_2_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                sop_2_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                eop_2_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                err_2_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                mty_2_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                            end else begin

                                axis_seg_tdata_1_next[128*8-1:128*3]  = fifo_tdata[128*8-1:128*3] ;
                                axis_seg_tvalid_1_next      = 1'b1;
                                ena_1_next[7:3]             = fifo_ena[7:3] & fifo_tvalid[7:3];
                                sop_1_next[7:3]             = fifo_sop[7:3] & fifo_tvalid[7:3];
                                eop_1_next[7:3]             = fifo_eop[7:3] & fifo_tvalid[7:3];
                                err_1_next[7:3]             = fifo_err[7:3] & fifo_tvalid[7:3];
                                mty_1_next[8*4-1:3*4]       = fifo_mty[8*4-1:3*4];
                            end

                        end
                        7'bZZZ1000: begin

                            axis_seg_tdata_0_next[128*8-1:128*4]  = {128*4{1'b0}};
                            ena_0_next[7:4]             = 4'h0;
                            sop_0_next[7:4]             = 4'h0;
                            eop_0_next[7:4]             = 4'h0;
                            err_0_next[7:4]             = 4'h0;
                            mty_0_next[8*4-1:4*4]       = 16'h0000;

                            axis_seg_tdata_1_next[128*8-1:128*4]  = fifo_tdata[128*8-1:128*4] ;
                            axis_seg_tvalid_1_next      = 1'b1;
                            ena_1_next[7:4]             = fifo_ena[7:4] & fifo_tvalid[7:4];
                            sop_1_next[7:4]             = fifo_sop[7:4] & fifo_tvalid[7:4];
                            eop_1_next[7:4]             = fifo_eop[7:4] & fifo_tvalid[7:4];
                            err_1_next[7:4]             = fifo_err[7:4] & fifo_tvalid[7:4];
                            mty_1_next[8*4-1:4*4]       = fifo_mty[8*4-1:4*4];

                        end
                        7'bZZ10000: begin

                            axis_seg_tdata_0_next[128*8-1:128*5]  = {128*3{1'b0}};
                            ena_0_next[7:5]             = 3'h0;
                            sop_0_next[7:5]             = 3'h0;
                            eop_0_next[7:5]             = 3'h0;
                            err_0_next[7:5]             = 3'h0;
                            mty_0_next[8*4-1:5*4]       = 12'h000;

                            axis_seg_tdata_1_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                            axis_seg_tvalid_1_next      = 1'b1;
                            ena_1_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                            sop_1_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                            eop_1_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                            err_1_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                            mty_1_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                        end
                        7'bZ100000: begin

                            axis_seg_tdata_0_next[128*8-1:128*6]  = {128*2{1'b0}};
                            ena_0_next[7:6]             = 2'h0;
                            sop_0_next[7:6]             = 2'h0;
                            eop_0_next[7:6]             = 2'h0;
                            err_0_next[7:6]             = 2'h0;
                            mty_0_next[8*4-1:6*4]       = 8'h00;

                            axis_seg_tdata_1_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                            axis_seg_tvalid_1_next      = 1'b1;
                            ena_1_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                            sop_1_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                            eop_1_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                            err_1_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                            mty_1_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                        end
                        7'b1000000: begin

                            axis_seg_tdata_0_next[128*8-1:128*7]  = {128*1{1'b0}};
                            ena_0_next[7:7]             = 1'h0;
                            sop_0_next[7:7]             = 1'h0;
                            eop_0_next[7:7]             = 1'h0;
                            err_0_next[7:7]             = 1'h0;
                            mty_0_next[8*4-1:7*4]       = 4'h0;

                            axis_seg_tdata_1_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                            axis_seg_tvalid_1_next      = 1'b1;
                            ena_1_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                            sop_1_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                            eop_1_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                            err_1_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                            mty_1_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                        end
                    endcase
                end
            end
            3'b010: begin // only second frame is active

                axis_seg_tdata_1_next  = fifo_tdata;
                axis_seg_tvalid_1_next = |(fifo_ena & fifo_tvalid);
                ena_1_next             = fifo_ena & fifo_tvalid;
                sop_1_next             = fifo_sop & fifo_tvalid;
                eop_1_next             = fifo_eop & fifo_tvalid;
                err_1_next             = fifo_err & fifo_tvalid;
                mty_1_next             = fifo_mty;

                axis_seg_tdata_0_next  = {128*8{1'b0}};
                axis_seg_tvalid_0_next = 1'b0;
                ena_0_next             = 8'h0;
                sop_0_next             = 8'h0;
                eop_0_next             = 8'h0;
                err_0_next             = 8'h0;
                mty_0_next             = 32'h00000000;

                axis_seg_tdata_2_next  = {128*8{1'b0}};
                axis_seg_tvalid_2_next = 1'b0;
                ena_2_next             = 8'h0;
                sop_2_next             = 8'h0;
                eop_2_next             = 8'h0;
                err_2_next             = 8'h0;
                mty_2_next             = 32'h00000000;

                if (|(fifo_ena & fifo_eop & fifo_tvalid)) begin // end of frame on any position
                    active_frame_next[1] = 1'b0;
                end

                if (|(fifo_ena & fifo_sop & fifo_tvalid)) begin // new frame, need to put it on frame 0
                    if (|(fifo_ena[3:0] & fifo_eop[3:0] & fifo_tvalid[3:0]) & |(fifo_ena[7:4] & fifo_eop[7:4] & fifo_tvalid[7:4])) begin // two end of frame values, no new active frames as they both stop here
                        active_frame_next[2] = 1'b0;
                    end else begin // frame 0 is now active
                        active_frame_next[2] = 1'b1;
                    end

                    casez(fifo_sop[7:1])
                        7'bZZZZZZ1: begin

                            axis_seg_tdata_1_next[128*8-1:128*1]  = {128*7{1'b0}};
                            ena_1_next[7:1]             = 7'h00;
                            sop_1_next[7:1]             = 7'h00;
                            eop_1_next[7:1]             = 7'h00;
                            err_1_next[7:1]             = 7'h00;
                            mty_1_next[8*4-1:1*4]       = 28'h0000000;

                            if (|(fifo_sop[7:5])) begin
                                active_frame_next[0] = 1'b1;
                            end

                            casez(fifo_sop[7:5])
                                3'b000: begin
                                    axis_seg_tdata_2_next[128*8-1:128*1]  = fifo_tdata[128*8-1:128*1] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:1]             = fifo_ena[7:1] & fifo_tvalid[7:1];
                                    sop_2_next[7:1]             = fifo_sop[7:1] & fifo_tvalid[7:1];
                                    eop_2_next[7:1]             = fifo_eop[7:1] & fifo_tvalid[7:1];
                                    err_2_next[7:1]             = fifo_err[7:1] & fifo_tvalid[7:1];
                                    mty_2_next[8*4-1:1*4]       = fifo_mty[8*4-1:1*4];
                                end
                                3'bZZ1: begin

                                    axis_seg_tdata_2_next[128*5-1:128*1]  = fifo_tdata[128*5-1:128*1] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[4:1]             = fifo_ena[4:1] & fifo_tvalid[4:1];
                                    sop_2_next[4:1]             = fifo_sop[4:1] & fifo_tvalid[4:1];
                                    eop_2_next[4:1]             = fifo_eop[4:1] & fifo_tvalid[4:1];
                                    err_2_next[4:1]             = fifo_err[4:1] & fifo_tvalid[4:1];
                                    mty_2_next[5*4-1:1*4]       = fifo_mty[5*4-1:1*4];

                                    axis_seg_tdata_0_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                                    sop_0_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                                    eop_0_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                                    err_0_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                                    mty_0_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                                end
                                3'bZ10: begin

                                    axis_seg_tdata_2_next[128*6-1:128*1]  = fifo_tdata[128*6-1:128*1] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[5:1]             = fifo_ena[5:1] & fifo_tvalid[5:1];
                                    sop_2_next[5:1]             = fifo_sop[5:1] & fifo_tvalid[5:1];
                                    eop_2_next[5:1]             = fifo_eop[5:1] & fifo_tvalid[5:1];
                                    err_2_next[5:1]             = fifo_err[5:1] & fifo_tvalid[5:1];
                                    mty_2_next[6*4-1:1*4]       = fifo_mty[6*4-1:1*4];

                                    axis_seg_tdata_0_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_0_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_0_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_0_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_0_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];


                                end
                                3'b100: begin

                                    axis_seg_tdata_2_next[128*7-1:128*1]  = fifo_tdata[128*7-1:128*1] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[6:1]             = fifo_ena[6:1] & fifo_tvalid[6:1];
                                    sop_2_next[6:1]             = fifo_sop[6:1] & fifo_tvalid[6:1];
                                    eop_2_next[6:1]             = fifo_eop[6:1] & fifo_tvalid[6:1];
                                    err_2_next[6:1]             = fifo_err[6:1] & fifo_tvalid[6:1];
                                    mty_2_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                    axis_seg_tdata_0_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_0_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_0_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_0_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_0_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZZ10: begin

                            axis_seg_tdata_1_next[128*8-1:128*2]  = {128*6{1'b0}};
                            ena_1_next[7:2]             = 6'h00;
                            sop_1_next[7:2]             = 6'h00;
                            eop_1_next[7:2]             = 6'h00;
                            err_1_next[7:2]             = 6'h00;
                            mty_1_next[8*4-1:2*4]       = 24'h000000;

                            if (|(fifo_sop[7:6])) begin
                                active_frame_next[0] = 1'b1;
                            end

                            casez(fifo_sop[7:6])
                                2'b00: begin
                                    axis_seg_tdata_2_next[128*8-1:128*2]  = fifo_tdata[128*8-1:128*2] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[7:2]             = fifo_ena[7:2] & fifo_tvalid[7:2];
                                    sop_2_next[7:2]             = fifo_sop[7:2] & fifo_tvalid[7:2];
                                    eop_2_next[7:2]             = fifo_eop[7:2] & fifo_tvalid[7:2];
                                    err_2_next[7:2]             = fifo_err[7:2] & fifo_tvalid[7:2];
                                    mty_2_next[8*4-1:2*4]       = fifo_mty[8*4-1:2*4];
                                end
                                2'bZ1: begin

                                    axis_seg_tdata_2_next[128*6-1:128*2]  = fifo_tdata[128*6-1:128*2] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[5:2]             = fifo_ena[5:2] & fifo_tvalid[5:2];
                                    sop_2_next[5:2]             = fifo_sop[5:2] & fifo_tvalid[5:2];
                                    eop_2_next[5:2]             = fifo_eop[5:2] & fifo_tvalid[5:2];
                                    err_2_next[5:2]             = fifo_err[5:2] & fifo_tvalid[5:2];
                                    mty_2_next[6*4-1:2*4]       = fifo_mty[6*4-1:2*4];

                                    axis_seg_tdata_1_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_0_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_0_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_0_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_0_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_0_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                                end
                                2'b10: begin

                                    axis_seg_tdata_2_next[128*7-1:128*2]  = fifo_tdata[128*7-1:128*2] ;
                                    axis_seg_tvalid_2_next      = 1'b1;
                                    ena_2_next[6:2]             = fifo_ena[6:2] & fifo_tvalid[6:2];
                                    sop_2_next[6:2]             = fifo_sop[6:2] & fifo_tvalid[6:2];
                                    eop_2_next[6:2]             = fifo_eop[6:2] & fifo_tvalid[6:2];
                                    err_2_next[6:2]             = fifo_err[6:2] & fifo_tvalid[6:2];
                                    mty_2_next[7*4-1:2*4]       = fifo_mty[7*4-1:2*4];

                                    axis_seg_tdata_1_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_0_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_0_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_0_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_0_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_0_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZ100: begin

                            axis_seg_tdata_1_next[128*8-1:128*3]  = {128*5{1'b0}};
                            ena_1_next[7:3]             = 5'h00;
                            sop_1_next[7:3]             = 5'h00;
                            eop_1_next[7:3]             = 5'h00;
                            err_1_next[7:3]             = 5'h00;
                            mty_1_next[8*4-1:3*4]       = 20'h00000;

                            if (fifo_sop[7]) begin

                                active_frame_next[0] = 1'b1;

                                axis_seg_tdata_2_next[128*7-1:128*3]  = fifo_tdata[128*7-1:128*3] ;
                                axis_seg_tvalid_2_next      = 1'b1;
                                ena_2_next[6:3]             = fifo_ena[6:3] & fifo_tvalid[6:3];
                                sop_2_next[6:3]             = fifo_sop[6:3] & fifo_tvalid[6:3];
                                eop_2_next[6:3]             = fifo_eop[6:3] & fifo_tvalid[6:3];
                                err_2_next[6:3]             = fifo_err[6:3] & fifo_tvalid[6:3];
                                mty_2_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                axis_seg_tdata_0_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                axis_seg_tvalid_0_next      = 1'b1;
                                ena_0_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                sop_0_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                eop_0_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                err_0_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                mty_0_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                            end else begin

                                axis_seg_tdata_2_next[128*8-1:128*3]  = fifo_tdata[128*8-1:128*3] ;
                                axis_seg_tvalid_2_next      = 1'b1;
                                ena_2_next[7:3]             = fifo_ena[7:3] & fifo_tvalid[7:3];
                                sop_2_next[7:3]             = fifo_sop[7:3] & fifo_tvalid[7:3];
                                eop_2_next[7:3]             = fifo_eop[7:3] & fifo_tvalid[7:3];
                                err_2_next[7:3]             = fifo_err[7:3] & fifo_tvalid[7:3];
                                mty_2_next[8*4-1:3*4]       = fifo_mty[8*4-1:3*4];
                            end

                        end
                        7'bZZZ1000: begin

                            axis_seg_tdata_1_next[128*8-1:128*4]  = {128*4{1'b0}};
                            ena_1_next[7:4]             = 4'h0;
                            sop_1_next[7:4]             = 4'h0;
                            eop_1_next[7:4]             = 4'h0;
                            err_1_next[7:4]             = 4'h0;
                            mty_1_next[8*4-1:4*4]       = 16'h0000;

                            axis_seg_tdata_2_next[128*8-1:128*4]  = fifo_tdata[128*8-1:128*4] ;
                            axis_seg_tvalid_2_next      = 1'b1;
                            ena_2_next[7:4]             = fifo_ena[7:4] & fifo_tvalid[7:4];
                            sop_2_next[7:4]             = fifo_sop[7:4] & fifo_tvalid[7:4];
                            eop_2_next[7:4]             = fifo_eop[7:4] & fifo_tvalid[7:4];
                            err_2_next[7:4]             = fifo_err[7:4] & fifo_tvalid[7:4];
                            mty_2_next[8*4-1:4*4]       = fifo_mty[8*4-1:4*4];

                        end
                        7'bZZ10000: begin

                            axis_seg_tdata_1_next[128*8-1:128*5]  = {128*3{1'b0}};
                            ena_1_next[7:5]             = 3'h0;
                            sop_1_next[7:5]             = 3'h0;
                            eop_1_next[7:5]             = 3'h0;
                            err_1_next[7:5]             = 3'h0;
                            mty_1_next[8*4-1:5*4]       = 12'h000;

                            axis_seg_tdata_2_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                            axis_seg_tvalid_2_next      = 1'b1;
                            ena_2_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                            sop_2_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                            eop_2_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                            err_2_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                            mty_2_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                        end
                        7'bZ100000: begin

                            axis_seg_tdata_1_next[128*8-1:128*6]  = {128*2{1'b0}};
                            ena_1_next[7:6]             = 2'h0;
                            sop_1_next[7:6]             = 2'h0;
                            eop_1_next[7:6]             = 2'h0;
                            err_1_next[7:6]             = 2'h0;
                            mty_1_next[8*4-1:6*4]       = 8'h00;

                            axis_seg_tdata_2_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                            axis_seg_tvalid_2_next      = 1'b1;
                            ena_2_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                            sop_2_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                            eop_2_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                            err_2_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                            mty_2_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                        end
                        7'b1000000: begin

                            axis_seg_tdata_1_next[128*8-1:128*7]  = {128*1{1'b0}};
                            ena_1_next[7:7]             = 1'h0;
                            sop_1_next[7:7]             = 1'h0;
                            eop_1_next[7:7]             = 1'h0;
                            err_1_next[7:7]             = 1'h0;
                            mty_1_next[8*4-1:7*4]       = 4'h0;

                            axis_seg_tdata_2_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                            axis_seg_tvalid_2_next      = 1'b1;
                            ena_2_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                            sop_2_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                            eop_2_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                            err_2_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                            mty_2_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                        end
                    endcase

                end

            end
            3'b100: begin // only third frame is active

                axis_seg_tdata_2_next  = fifo_tdata;
                axis_seg_tvalid_2_next = |(fifo_ena & fifo_tvalid);
                ena_2_next             = fifo_ena & fifo_tvalid;
                sop_2_next             = fifo_sop & fifo_tvalid;
                eop_2_next             = fifo_eop & fifo_tvalid;
                err_2_next             = fifo_err & fifo_tvalid;
                mty_2_next             = fifo_mty;

                axis_seg_tdata_0_next  = {128*8{1'b0}};
                axis_seg_tvalid_0_next = 1'b0;
                ena_0_next             = 8'h0;
                sop_0_next             = 8'h0;
                eop_0_next             = 8'h0;
                err_0_next             = 8'h0;
                mty_0_next             = 32'h00000000;

                axis_seg_tdata_1_next  = {128*8{1'b0}};
                axis_seg_tvalid_1_next = 1'b0;
                ena_1_next             = 8'h0;
                sop_1_next             = 8'h0;
                eop_1_next             = 8'h0;
                err_1_next             = 8'h0;
                mty_1_next             = 32'h00000000;

                if (|(fifo_ena & fifo_eop & fifo_tvalid)) begin // end of frame on any position
                    active_frame_next[2] = 1'b0;
                end

                if (|(fifo_ena & fifo_sop & fifo_tvalid)) begin // new frame, need to put it on frame 0
                    if (|(fifo_ena[3:0] & fifo_eop[3:0] & fifo_tvalid[3:0]) & |(fifo_ena[7:4] & fifo_eop[7:4] & fifo_tvalid[7:4])) begin // two end of frame values, no new active frames as they both stop here
                        active_frame_next[0] = 1'b0;
                    end else begin // frame 0 is now active
                        active_frame_next[0] = 1'b1;
                    end

                    casez(fifo_sop[7:1])
                        7'bZZZZZZ1: begin

                            axis_seg_tdata_2_next[128*8-1:128*1]  = {128*7{1'b0}};
                            ena_2_next[7:1]             = 7'h00;
                            sop_2_next[7:1]             = 7'h00;
                            eop_2_next[7:1]             = 7'h00;
                            err_2_next[7:1]             = 7'h00;
                            mty_2_next[8*4-1:1*4]       = 28'h0000000;

                            if (|(fifo_sop[7:5])) begin
                                active_frame_next[1] = 1'b1;
                            end

                            casez(fifo_sop[7:5])
                                3'b000: begin
                                    axis_seg_tdata_0_next[128*8-1:128*1]  = fifo_tdata[128*8-1:128*1] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[7:1]             = fifo_ena[7:1] & fifo_tvalid[7:1];
                                    sop_0_next[7:1]             = fifo_sop[7:1] & fifo_tvalid[7:1];
                                    eop_0_next[7:1]             = fifo_eop[7:1] & fifo_tvalid[7:1];
                                    err_0_next[7:1]             = fifo_err[7:1] & fifo_tvalid[7:1];
                                    mty_0_next[8*4-1:1*4]       = fifo_mty[8*4-1:1*4];
                                end
                                3'bZZ1: begin

                                    axis_seg_tdata_0_next[128*5-1:128*1]  = fifo_tdata[128*5-1:128*1] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[4:1]             = fifo_ena[4:1] & fifo_tvalid[4:1];
                                    sop_0_next[4:1]             = fifo_sop[4:1] & fifo_tvalid[4:1];
                                    eop_0_next[4:1]             = fifo_eop[4:1] & fifo_tvalid[4:1];
                                    err_0_next[4:1]             = fifo_err[4:1] & fifo_tvalid[4:1];
                                    mty_0_next[5*4-1:1*4]       = fifo_mty[5*4-1:1*4];

                                    axis_seg_tdata_1_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                                    sop_1_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                                    eop_1_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                                    err_1_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                                    mty_1_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                                end
                                3'bZ10: begin

                                    axis_seg_tdata_0_next[128*6-1:128*1]  = fifo_tdata[128*6-1:128*1] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[5:1]             = fifo_ena[5:1] & fifo_tvalid[5:1];
                                    sop_0_next[5:1]             = fifo_sop[5:1] & fifo_tvalid[5:1];
                                    eop_0_next[5:1]             = fifo_eop[5:1] & fifo_tvalid[5:1];
                                    err_0_next[5:1]             = fifo_err[5:1] & fifo_tvalid[5:1];
                                    mty_0_next[6*4-1:1*4]       = fifo_mty[6*4-1:1*4];

                                    axis_seg_tdata_1_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_1_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_1_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_1_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_1_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];


                                end
                                3'b100: begin

                                    axis_seg_tdata_0_next[128*7-1:128*1]  = fifo_tdata[128*7-1:128*1] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[6:1]             = fifo_ena[6:1] & & fifo_tvalid[6:1];
                                    sop_0_next[6:1]             = fifo_sop[6:1] & & fifo_tvalid[6:1];
                                    eop_0_next[6:1]             = fifo_eop[6:1] & & fifo_tvalid[6:1];
                                    err_0_next[6:1]             = fifo_err[6:1] & & fifo_tvalid[6:1];
                                    mty_0_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                    axis_seg_tdata_1_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_1_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_1_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_1_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_1_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZZ10: begin

                            axis_seg_tdata_2_next[128*8-1:128*2]  = {128*6{1'b0}};
                            ena_2_next[7:2]             = 6'h00;
                            sop_2_next[7:2]             = 6'h00;
                            eop_2_next[7:2]             = 6'h00;
                            err_2_next[7:2]             = 6'h00;
                            mty_2_next[8*4-1:2*4]       = 24'h000000;

                            if (|(fifo_sop[7:6])) begin
                                active_frame_next[1] = 1'b1;
                            end

                            casez(fifo_sop[7:6])
                                2'b00: begin
                                    axis_seg_tdata_0_next[128*8-1:128*2]  = fifo_tdata[128*8-1:128*2] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[7:2]             = fifo_ena[7:2] & fifo_tvalid[7:2];
                                    sop_0_next[7:2]             = fifo_sop[7:2] & fifo_tvalid[7:2];
                                    eop_0_next[7:2]             = fifo_eop[7:2] & fifo_tvalid[7:2];
                                    err_0_next[7:2]             = fifo_err[7:2] & fifo_tvalid[7:2];
                                    mty_0_next[8*4-1:2*4]       = fifo_mty[8*4-1:2*4];
                                end
                                2'bZ1: begin

                                    axis_seg_tdata_0_next[128*6-1:128*2]  = fifo_tdata[128*6-1:128*2] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[5:2]             = fifo_ena[5:2] & fifo_tvalid[5:2];
                                    sop_0_next[5:2]             = fifo_sop[5:2] & fifo_tvalid[5:2];
                                    eop_0_next[5:2]             = fifo_eop[5:2] & fifo_tvalid[5:2];
                                    err_0_next[5:2]             = fifo_err[5:2] & fifo_tvalid[5:2];
                                    mty_0_next[6*4-1:2*4]       = fifo_mty[6*4-1:2*4];

                                    axis_seg_tdata_1_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                                    sop_1_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                                    eop_1_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                                    err_1_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                                    mty_1_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                                end
                                2'b10: begin

                                    axis_seg_tdata_0_next[128*7-1:128*2]  = fifo_tdata[128*7-1:128*2] ;
                                    axis_seg_tvalid_0_next      = 1'b1;
                                    ena_0_next[6:2]             = fifo_ena[6:2] & fifo_tvalid[6:2];
                                    sop_0_next[6:2]             = fifo_sop[6:2] & fifo_tvalid[6:2];
                                    eop_0_next[6:2]             = fifo_eop[6:2] & fifo_tvalid[6:2];
                                    err_0_next[6:2]             = fifo_err[6:2] & fifo_tvalid[6:2];
                                    mty_0_next[7*4-1:2*4]       = fifo_mty[7*4-1:2*4];

                                    axis_seg_tdata_1_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                    axis_seg_tvalid_1_next      = 1'b1;
                                    ena_1_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                    sop_1_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                    eop_1_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                    err_1_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                    mty_1_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                                end
                            endcase

                        end
                        7'bZZZZ100: begin

                            axis_seg_tdata_2_next[128*8-1:128*3]  = {128*5{1'b0}};
                            ena_2_next[7:3]             = 5'h00;
                            sop_2_next[7:3]             = 5'h00;
                            eop_2_next[7:3]             = 5'h00;
                            err_2_next[7:3]             = 5'h00;
                            mty_2_next[8*4-1:3*4]       = 20'h00000;

                            if (fifo_sop[7]) begin

                                active_frame_next[1] = 1'b1;

                                axis_seg_tdata_0_next[128*7-1:128*3]  = fifo_tdata[128*7-1:128*3] ;
                                axis_seg_tvalid_0_next      = 1'b1;
                                ena_0_next[6:3]             = fifo_ena[6:3] & fifo_tvalid[6:3];
                                sop_0_next[6:3]             = fifo_sop[6:3] & fifo_tvalid[6:3];
                                eop_0_next[6:3]             = fifo_eop[6:3] & fifo_tvalid[6:3];
                                err_0_next[6:3]             = fifo_err[6:3] & fifo_tvalid[6:3];
                                mty_0_next[7*4-1:1*4]       = fifo_mty[7*4-1:1*4];

                                axis_seg_tdata_1_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                                axis_seg_tvalid_1_next      = 1'b1;
                                ena_1_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                                sop_1_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                                eop_1_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                                err_1_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                                mty_1_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                            end else begin

                                axis_seg_tdata_0_next[128*8-1:128*3]  = fifo_tdata[128*8-1:128*3] ;
                                axis_seg_tvalid_0_next      = 1'b1;
                                ena_0_next[7:3]             = fifo_ena[7:3] & fifo_tvalid[7:3];
                                sop_0_next[7:3]             = fifo_sop[7:3] & fifo_tvalid[7:3];
                                eop_0_next[7:3]             = fifo_eop[7:3] & fifo_tvalid[7:3];
                                err_0_next[7:3]             = fifo_err[7:3] & fifo_tvalid[7:3];
                                mty_0_next[8*4-1:3*4]       = fifo_mty[8*4-1:3*4];
                            end

                        end
                        7'bZZZ1000: begin

                            axis_seg_tdata_2_next[128*8-1:128*4]  = {128*4{1'b0}};
                            ena_2_next[7:4]             = 4'h0;
                            sop_2_next[7:4]             = 4'h0;
                            eop_2_next[7:4]             = 4'h0;
                            err_2_next[7:4]             = 4'h0;
                            mty_2_next[8*4-1:4*4]       = 16'h0000;

                            axis_seg_tdata_0_next[128*8-1:128*4]  = fifo_tdata[128*8-1:128*4] ;
                            axis_seg_tvalid_0_next      = 1'b1;
                            ena_0_next[7:4]             = fifo_ena[7:4] & fifo_tvalid[7:4];
                            sop_0_next[7:4]             = fifo_sop[7:4] & fifo_tvalid[7:4];
                            eop_0_next[7:4]             = fifo_eop[7:4] & fifo_tvalid[7:4];
                            err_0_next[7:4]             = fifo_err[7:4] & fifo_tvalid[7:4];
                            mty_0_next[8*4-1:4*4]       = fifo_mty[8*4-1:4*4];

                        end
                        7'bZZ10000: begin

                            axis_seg_tdata_2_next[128*8-1:128*5]  = {128*3{1'b0}};
                            ena_2_next[7:5]             = 3'h0;
                            sop_2_next[7:5]             = 3'h0;
                            eop_2_next[7:5]             = 3'h0;
                            err_2_next[7:5]             = 3'h0;
                            mty_2_next[8*4-1:5*4]       = 12'h000;

                            axis_seg_tdata_0_next[128*8-1:128*5]  = fifo_tdata[128*8-1:128*5] ;
                            axis_seg_tvalid_0_next      = 1'b1;
                            ena_0_next[7:5]             = fifo_ena[7:5] & fifo_tvalid[7:5];
                            sop_0_next[7:5]             = fifo_sop[7:5] & fifo_tvalid[7:5];
                            eop_0_next[7:5]             = fifo_eop[7:5] & fifo_tvalid[7:5];
                            err_0_next[7:5]             = fifo_err[7:5] & fifo_tvalid[7:5];
                            mty_0_next[8*4-1:5*4]       = fifo_mty[8*4-1:5*4];

                        end
                        7'bZ100000: begin

                            axis_seg_tdata_2_next[128*8-1:128*6]  = {128*2{1'b0}};
                            ena_2_next[7:6]             = 2'h0;
                            sop_2_next[7:6]             = 2'h0;
                            eop_2_next[7:6]             = 2'h0;
                            err_2_next[7:6]             = 2'h0;
                            mty_2_next[8*4-1:6*4]       = 8'h00;

                            axis_seg_tdata_0_next[128*8-1:128*6]  = fifo_tdata[128*8-1:128*6] ;
                            axis_seg_tvalid_0_next      = 1'b1;
                            ena_0_next[7:6]             = fifo_ena[7:6] & fifo_tvalid[7:6];
                            sop_0_next[7:6]             = fifo_sop[7:6] & fifo_tvalid[7:6];
                            eop_0_next[7:6]             = fifo_eop[7:6] & fifo_tvalid[7:6];
                            err_0_next[7:6]             = fifo_err[7:6] & fifo_tvalid[7:6];
                            mty_0_next[8*4-1:6*4]       = fifo_mty[8*4-1:6*4];

                        end
                        7'b1000000: begin

                            axis_seg_tdata_2_next[128*8-1:128*7]  = {128*1{1'b0}};
                            ena_2_next[7:7]             = 1'h0;
                            sop_2_next[7:7]             = 1'h0;
                            eop_2_next[7:7]             = 1'h0;
                            err_2_next[7:7]             = 1'h0;
                            mty_2_next[8*4-1:7*4]       = 4'h0;

                            axis_seg_tdata_0_next[128*8-1:128*7]  = fifo_tdata[128*8-1:128*7] ;
                            axis_seg_tvalid_0_next      = 1'b1;
                            ena_0_next[7:7]             = fifo_ena[7:7] & fifo_tvalid[7:7];
                            sop_0_next[7:7]             = fifo_sop[7:7] & fifo_tvalid[7:7];
                            eop_0_next[7:7]             = fifo_eop[7:7] & fifo_tvalid[7:7];
                            err_0_next[7:7]             = fifo_err[7:7] & fifo_tvalid[7:7];
                            mty_0_next[8*4-1:7*4]       = fifo_mty[8*4-1:7*4];

                        end
                    endcase

                end

            end
            default : begin // all other cases are not possible

            end
        endcase

    end


    always @(posedge s_clk) begin

        if (s_rst) begin
            active_frame_reg <= 3'b000;

            axis_seg_tdata_0_reg   <= {128*8{1'b0}};
            axis_seg_tvalid_0_reg  <= 1'b0;
            ena_0_reg <= 8'h0;
            sop_0_reg <= 8'h0;
            eop_0_reg <= 8'h0;
            err_0_reg <= 8'h0;
            mty_0_reg <= 32'd0;

            axis_seg_tdata_1_reg   <= {128*8{1'b0}};
            axis_seg_tvalid_1_reg  <= 1'b0;
            ena_1_reg <= 8'h0;
            sop_1_reg <= 8'h0;
            eop_1_reg <= 8'h0;
            err_1_reg <= 8'h0;
            mty_1_reg <= 32'd0;

            axis_seg_tdata_2_reg   <= {128*8{1'b0}};
            axis_seg_tvalid_2_reg  <= 1'b0;
            ena_2_reg <= 8'h0;
            sop_2_reg <= 8'h0;
            eop_2_reg <= 8'h0;
            err_2_reg <= 8'h0;
            mty_2_reg <= 32'd0;

        end else begin
            active_frame_reg <= active_frame_next;

            axis_seg_tdata_0_reg   <= axis_seg_tdata_0_next ;
            axis_seg_tvalid_0_reg  <= axis_seg_tvalid_0_next;
            ena_0_reg              <= ena_0_next            ;
            sop_0_reg              <= sop_0_next            ;
            eop_0_reg              <= eop_0_next            ;
            err_0_reg              <= err_0_next            ;
            mty_0_reg              <= mty_0_next            ;

            axis_seg_tdata_1_reg   <= axis_seg_tdata_1_next ;
            axis_seg_tvalid_1_reg  <= axis_seg_tvalid_1_next;
            ena_1_reg              <= ena_1_next            ;
            sop_1_reg              <= sop_1_next            ;
            eop_1_reg              <= eop_1_next            ;
            err_1_reg              <= err_1_next            ;
            mty_1_reg              <= mty_1_next            ;

            axis_seg_tdata_2_reg   <= axis_seg_tdata_2_next ;
            axis_seg_tvalid_2_reg  <= axis_seg_tvalid_2_next;
            ena_2_reg              <= ena_2_next            ;
            sop_2_reg              <= sop_2_next            ;
            eop_2_reg              <= eop_2_next            ;
            err_2_reg              <= err_2_next            ;
            mty_2_reg              <= mty_2_next            ;


        end

    end


    // Convert 3 AXI segmented streams in to 1 AXI stream

    wire [7:0][127:0] axi_seg_stream_0_tdata, axi_seg_stream_1_tdata, axi_seg_stream_2_tdata;
    wire axi_seg_stream_0_tvalid = axis_seg_tvalid_0_reg;
    wire axi_seg_stream_1_tvalid = axis_seg_tvalid_1_reg;
    wire axi_seg_stream_2_tvalid = axis_seg_tvalid_2_reg;

    wire [7:0] axi_seg_stream_0_ena = ena_0_reg;
    wire [7:0] axi_seg_stream_1_ena = ena_1_reg;
    wire [7:0] axi_seg_stream_2_ena = ena_2_reg;

    wire [7:0] axi_seg_stream_0_sop = sop_0_reg;
    wire [7:0] axi_seg_stream_1_sop = sop_1_reg;
    wire [7:0] axi_seg_stream_2_sop = sop_2_reg;

    wire [7:0] axi_seg_stream_0_eop = eop_0_reg;
    wire [7:0] axi_seg_stream_1_eop = eop_1_reg;
    wire [7:0] axi_seg_stream_2_eop = eop_2_reg;

    wire [7:0] axi_seg_stream_0_err = err_0_reg;
    wire [7:0] axi_seg_stream_1_err = err_1_reg;
    wire [7:0] axi_seg_stream_2_err = err_2_reg;

    wire [7:0][3:0] axi_seg_stream_0_mty, axi_seg_stream_1_mty, axi_seg_stream_2_mty;


    generate
        for (genvar j=0; j<8; j=j+1) begin

            assign  axi_seg_stream_0_tdata[j] = axis_seg_tdata_0_reg[128*j+:128];
            assign  axi_seg_stream_1_tdata[j] = axis_seg_tdata_1_reg[128*j+:128];
            assign  axi_seg_stream_2_tdata[j] = axis_seg_tdata_2_reg[128*j+:128];

            assign  axi_seg_stream_0_mty[j] = mty_0_reg[4*j+:4];
            assign  axi_seg_stream_1_mty[j] = mty_1_reg[4*j+:4];
            assign  axi_seg_stream_2_mty[j] = mty_2_reg[4*j+:4];

        end



    endgenerate

    wire [1023:0] axis_0_tdata, axis_1_tdata, axis_2_tdata;
    wire [127:0]  axis_0_tkeep, axis_1_tkeep, axis_2_tkeep;
    wire          axis_0_tvalid, axis_1_tvalid, axis_2_tvalid;
    wire          axis_0_tlast, axis_1_tlast, axis_2_tlast;
    wire          axis_0_tuser, axis_1_tuser, axis_2_tuser;

    unaligned_axi_seg_2_axis  #(
    .FIFO_DEPTH(AXIS_FIFO_DEPTH),
    .ASYNC_FIFO(ASYNC_FIFO)
    ) unaligned_axi_seg_2_axis_instance_0 (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis_seg_tdata(axi_seg_stream_0_tdata),
        .s_axis_seg_tvalid(axi_seg_stream_0_tvalid),
        .s_axis_seg_tready(),
        .s_ena(axi_seg_stream_0_ena),
        .s_sop(axi_seg_stream_0_sop),
        .s_eop(axi_seg_stream_0_eop),
        .s_err(axi_seg_stream_0_err),
        .s_mty(axi_seg_stream_0_mty),

        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis_tdata (s_axis_0_tdata),
        .m_axis_tkeep (s_axis_0_tkeep),
        .m_axis_tvalid(s_axis_0_tvalid),
        .m_axis_tready(s_axis_0_tready),
        .m_axis_tlast (s_axis_0_tlast),
        .m_axis_tuser (s_axis_0_tuser)
    );

    unaligned_axi_seg_2_axis  #(
    .FIFO_DEPTH(AXIS_FIFO_DEPTH),
    .ASYNC_FIFO(ASYNC_FIFO)
    ) unaligned_axi_seg_2_axis_instance_1 (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis_seg_tdata(axi_seg_stream_1_tdata),
        .s_axis_seg_tvalid(axi_seg_stream_1_tvalid),
        .s_axis_seg_tready(),
        .s_ena(axi_seg_stream_1_ena),
        .s_sop(axi_seg_stream_1_sop),
        .s_eop(axi_seg_stream_1_eop),
        .s_err(axi_seg_stream_1_err),
        .s_mty(axi_seg_stream_1_mty),

        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis_tdata (s_axis_1_tdata),
        .m_axis_tkeep (s_axis_1_tkeep),
        .m_axis_tvalid(s_axis_1_tvalid),
        .m_axis_tready(s_axis_1_tready),
        .m_axis_tlast (s_axis_1_tlast),
        .m_axis_tuser (s_axis_1_tuser)
    );

    unaligned_axi_seg_2_axis #(
    .FIFO_DEPTH(AXIS_FIFO_DEPTH),
    .ASYNC_FIFO(ASYNC_FIFO)
    ) unaligned_axi_seg_2_axis_instance_2 (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis_seg_tdata(axi_seg_stream_2_tdata),
        .s_axis_seg_tvalid(axi_seg_stream_2_tvalid),
        .s_axis_seg_tready(),
        .s_ena(axi_seg_stream_2_ena),
        .s_sop(axi_seg_stream_2_sop),
        .s_eop(axi_seg_stream_2_eop),
        .s_err(axi_seg_stream_2_err),
        .s_mty(axi_seg_stream_2_mty),

        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis_tdata (s_axis_2_tdata),
        .m_axis_tkeep (s_axis_2_tkeep),
        .m_axis_tvalid(s_axis_2_tvalid),
        .m_axis_tready(s_axis_2_tready),
        .m_axis_tlast (s_axis_2_tlast),
        .m_axis_tuser (s_axis_2_tuser)
    );

    axis_arb_mux #(
        .S_COUNT(3),
        .DATA_WIDTH(1024),
        .KEEP_ENABLE(1),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .ARB_TYPE_ROUND_ROBIN(1)
    ) axis_arb_mux_instance (
        .clk(m_clk),
        .rst(m_rst),
        .s_axis_tdata ({s_axis_0_tdata , s_axis_1_tdata , s_axis_2_tdata }),
        .s_axis_tkeep ({s_axis_0_tkeep , s_axis_1_tkeep , s_axis_2_tkeep }),
        .s_axis_tvalid({s_axis_0_tvalid, s_axis_1_tvalid, s_axis_2_tvalid}),
        .s_axis_tready({s_axis_0_tready, s_axis_1_tready, s_axis_2_tready}),
        .s_axis_tlast ({s_axis_0_tlast , s_axis_1_tlast , s_axis_2_tlast }),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser({s_axis_0_tuser, s_axis_1_tuser, s_axis_2_tuser}),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );



endmodule


`resetall