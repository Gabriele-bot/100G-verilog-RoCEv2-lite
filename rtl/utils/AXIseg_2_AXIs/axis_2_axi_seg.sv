`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module axis_2_axi_seg_v2 #(
    // input axis register
    parameter INPUT_REGS = 1
)(
    input  wire clk,
    input  wire rst,

    input  wire [1023:0]  s_axis_tdata,
    input  wire [127 :0]  s_axis_tkeep,
    input  wire           s_axis_tvalid,
    output wire           s_axis_tready,
    input  wire           s_axis_tlast,
    input  wire           s_axis_tuser,


    output wire [128*8-1:0] m_axis_seg_tdata,
    output wire             m_axis_seg_tvalid,
    input  wire             m_axis_seg_tready,
    output wire [7:0]       m_axis_seg_tuser_ena,
    output wire [7:0]       m_axis_seg_tuser_sop,
    output wire [7:0]       m_axis_seg_tuser_eop,
    output wire [7:0]       m_axis_seg_tuser_err,
    output wire [4*8-1:0]   m_axis_seg_tuser_mty

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
    reg [7:0][2:0] out_index_reg, out_index_before_reg, out_index_next;

    integer k;


    wire [7:0] fifo_tready;

    wire [1023:0]    m_axis_input_reg_tdata;
    wire [127 :0]    m_axis_input_reg_tkeep;
    wire             m_axis_input_reg_tvalid;
    wire             m_axis_input_reg_tready;
    wire             m_axis_input_reg_tlast;
    wire             m_axis_input_reg_tuser;

    reg [128*8-1:0] s_fifo_axis_seg_del_tdata;
    reg [7:0]       s_fifo_axis_seg_del_tvalid;
    reg             s_fifo_axis_seg_del_tready;
    reg [7:0]       s_fifo_axis_seg_del_tuser_ena;
    reg [7:0]       s_fifo_axis_seg_del_tuser_sop;
    reg [7:0]       s_fifo_axis_seg_del_tuser_eop;
    reg [7:0]       s_fifo_axis_seg_del_tuser_err;
    reg [4*8-1:0]   s_fifo_axis_seg_del_tuser_mty;

    wire  [128*8-1:0] s_fifo_axis_seg_del_wire_tdata;
    wire  [7:0]       s_fifo_axis_seg_del_wire_tvalid;
    wire              s_fifo_axis_seg_del_wire_tready;
    wire  [7:0]       s_fifo_axis_seg_del_wire_tuser_ena;
    wire  [7:0]       s_fifo_axis_seg_del_wire_tuser_sop;
    wire  [7:0]       s_fifo_axis_seg_del_wire_tuser_eop;
    wire  [7:0]       s_fifo_axis_seg_del_wire_tuser_err;
    wire  [4*8-1:0]   s_fifo_axis_seg_del_wire_tuser_mty;

    wire [128*8-1:0] s_fifo_axis_seg_tdata;
    wire             s_fifo_axis_seg_tvalid;
    wire             s_fifo_axis_seg_tready;
    wire [7:0]       s_fifo_axis_seg_tuser_ena;
    wire [7:0]       s_fifo_axis_seg_tuser_sop;
    wire [7:0]       s_fifo_axis_seg_tuser_eop;
    wire [7:0]       s_fifo_axis_seg_tuser_err;
    wire [4*8-1:0]   s_fifo_axis_seg_tuser_mty;




    assign s_fifo_axis_seg_tready = &fifo_tready;

    reg [7:0] fifo_tvalid_out;
    wire [7:0] fifo_tready_out;
    reg [7:0][7:0] fifo_tuser_out;
    reg [7:0][127:0] fifo_tdata_out;

    reg [7:0] ena_fifo_out, sop_fifo_out, eop_fifo_out, err_fifo_out;
    reg [7:0][3:0] mty_fifo_out;

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
                .clk(clk),
                .rst(rst),
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
        .clk(clk),
        .rst(rst),
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
                axis_fifo #(
                    .DEPTH(64),
                    .DATA_WIDTH(128),
                    .LAST_ENABLE(0),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(8),
                    .RAM_PIPELINE(3),
                    .FRAME_FIFO(0)
                ) segment_fifo (
                    .clk(clk),
                    .rst(rst),

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
                    .m_axis_tready(fifo_tready_out[i] ),
                    .m_axis_tuser({ena_fifo_out[i], sop_fifo_out[i], eop_fifo_out[i], err_fifo_out[i], mty_fifo_out[i]})
                );

            
        end
    endgenerate


    reg [15:0] temp_eop_ext = 16'd0, temp_sop_ext = 16'd0;
    reg [7 :0] temp_eop, temp_sop;

    always @(*) begin

        out_offset_next = out_offset_reg;

        out_index_next = out_index_before_reg;

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

    

    always @(posedge clk) begin
        if (rst) begin
            out_offset_reg <= 3'd0;
            out_index_before_reg  <= {3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0};
        end else begin
            out_offset_reg <= out_offset_next;
            out_index_before_reg  <= out_index_next;
        end
    end

    // skid buffer, no bubble cycles

    // datapath registers
    reg                  fifo_out_axis_tready_reg = 1'b0;

    reg [7:0][127:0]     m_axis_seg_tdata_reg = {{128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg [7:0]            m_ena_reg = 8'h0;
    reg [7:0]            m_sop_reg = 8'h0;
    reg [7:0]            m_eop_reg = 8'h0;
    reg [7:0]            m_err_reg = 8'h0;
    reg [7:0][3:0]       m_mty_reg = {4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0};


    reg [7:0][127:0] temp_m_axis_seg_tdata_reg = {{128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}};
    reg              temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg [7:0]        temp_m_ena_reg  = 8'h0;
    reg [7:0]        temp_m_sop_reg  = 8'h0;
    reg [7:0]        temp_m_eop_reg  = 8'h0;
    reg [7:0]        temp_m_err_reg  = 8'h0;
    reg [7:0][3:0]   temp_m_mty_reg  = {4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0};
    reg [7:0][2:0]   temp_out_index_reg = {3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0};

    // datapath control
    reg store_axis_input_to_output;
    reg store_axis_input_to_temp;
    reg store_axis_temp_to_output;

    assign fifo_tready_out = {8{fifo_out_axis_tready_reg}};

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    wire fifo_out_axis_tready_early = m_axis_seg_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !(|fifo_tvalid_out)));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_input_to_output = 1'b0;
        store_axis_input_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (fifo_out_axis_tready_reg) begin
            // input is ready
            if (m_axis_seg_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = |fifo_tvalid_out;
                store_axis_input_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = |fifo_tvalid_out;
                store_axis_input_to_temp = 1'b1;
            end
        end else if (m_axis_seg_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        fifo_out_axis_tready_reg <= fifo_out_axis_tready_early;
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_input_to_output) begin
            m_axis_seg_tdata_reg[0] <= fifo_tdata_out[0];
            m_axis_seg_tdata_reg[1] <= fifo_tdata_out[1];
            m_axis_seg_tdata_reg[2] <= fifo_tdata_out[2];
            m_axis_seg_tdata_reg[3] <= fifo_tdata_out[3];
            m_axis_seg_tdata_reg[4] <= fifo_tdata_out[4];
            m_axis_seg_tdata_reg[5] <= fifo_tdata_out[5];
            m_axis_seg_tdata_reg[6] <= fifo_tdata_out[6];
            m_axis_seg_tdata_reg[7] <= fifo_tdata_out[7];

            m_ena_reg <= ena_fifo_out & fifo_tvalid_out;
            m_sop_reg <= sop_fifo_out & fifo_tvalid_out;
            m_eop_reg <= eop_fifo_out & fifo_tvalid_out;
            m_err_reg <= err_fifo_out & fifo_tvalid_out;

            m_mty_reg[0] <= mty_fifo_out[0];
            m_mty_reg[1] <= mty_fifo_out[1];
            m_mty_reg[2] <= mty_fifo_out[2];
            m_mty_reg[3] <= mty_fifo_out[3];
            m_mty_reg[4] <= mty_fifo_out[4];
            m_mty_reg[5] <= mty_fifo_out[5];
            m_mty_reg[6] <= mty_fifo_out[6];
            m_mty_reg[7] <= mty_fifo_out[7];

            out_index_reg <= out_index_before_reg;
        end else if (store_axis_temp_to_output) begin
            m_axis_seg_tdata_reg <= temp_m_axis_seg_tdata_reg;
            m_ena_reg <= temp_m_ena_reg;
            m_sop_reg <= temp_m_sop_reg;
            m_eop_reg <= temp_m_eop_reg;
            m_err_reg <= temp_m_err_reg;
            m_mty_reg <= temp_m_mty_reg;

            out_index_reg <= temp_out_index_reg;
        end

        if (store_axis_input_to_temp) begin
            temp_m_axis_seg_tdata_reg[0] <= fifo_tdata_out[0];
            temp_m_axis_seg_tdata_reg[1] <= fifo_tdata_out[1];
            temp_m_axis_seg_tdata_reg[2] <= fifo_tdata_out[2];
            temp_m_axis_seg_tdata_reg[3] <= fifo_tdata_out[3];
            temp_m_axis_seg_tdata_reg[4] <= fifo_tdata_out[4];
            temp_m_axis_seg_tdata_reg[5] <= fifo_tdata_out[5];
            temp_m_axis_seg_tdata_reg[6] <= fifo_tdata_out[6];
            temp_m_axis_seg_tdata_reg[7] <= fifo_tdata_out[7];

            temp_m_ena_reg <= ena_fifo_out;
            temp_m_sop_reg <= sop_fifo_out;
            temp_m_eop_reg <= eop_fifo_out;
            temp_m_err_reg <= err_fifo_out;

            temp_m_mty_reg[0] <= mty_fifo_out[0];
            temp_m_mty_reg[1] <= mty_fifo_out[1];
            temp_m_mty_reg[2] <= mty_fifo_out[2];
            temp_m_mty_reg[3] <= mty_fifo_out[3];
            temp_m_mty_reg[4] <= mty_fifo_out[4];
            temp_m_mty_reg[5] <= mty_fifo_out[5];
            temp_m_mty_reg[6] <= mty_fifo_out[6];
            temp_m_mty_reg[7] <= mty_fifo_out[7];

            temp_out_index_reg <= out_index_before_reg;
        end

        if (rst) begin
            fifo_out_axis_tready_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end

    assign m_axis_seg_tvalid = m_axis_tvalid_reg;

    // reorder the segments accordingly
    assign m_axis_seg_tdata[0*128+:128] = m_axis_seg_tdata_reg[out_index_reg[0]];
    assign m_axis_seg_tdata[1*128+:128] = m_axis_seg_tdata_reg[out_index_reg[1]];
    assign m_axis_seg_tdata[2*128+:128] = m_axis_seg_tdata_reg[out_index_reg[2]];
    assign m_axis_seg_tdata[3*128+:128] = m_axis_seg_tdata_reg[out_index_reg[3]];
    assign m_axis_seg_tdata[4*128+:128] = m_axis_seg_tdata_reg[out_index_reg[4]];
    assign m_axis_seg_tdata[5*128+:128] = m_axis_seg_tdata_reg[out_index_reg[5]];
    assign m_axis_seg_tdata[6*128+:128] = m_axis_seg_tdata_reg[out_index_reg[6]];
    assign m_axis_seg_tdata[7*128+:128] = m_axis_seg_tdata_reg[out_index_reg[7]];

    assign m_axis_seg_tuser_mty[0*4+:4] = m_mty_reg[out_index_reg[0]];
    assign m_axis_seg_tuser_mty[1*4+:4] = m_mty_reg[out_index_reg[1]];
    assign m_axis_seg_tuser_mty[2*4+:4] = m_mty_reg[out_index_reg[2]];
    assign m_axis_seg_tuser_mty[3*4+:4] = m_mty_reg[out_index_reg[3]];
    assign m_axis_seg_tuser_mty[4*4+:4] = m_mty_reg[out_index_reg[4]];
    assign m_axis_seg_tuser_mty[5*4+:4] = m_mty_reg[out_index_reg[5]];
    assign m_axis_seg_tuser_mty[6*4+:4] = m_mty_reg[out_index_reg[6]];
    assign m_axis_seg_tuser_mty[7*4+:4] = m_mty_reg[out_index_reg[7]];

    assign m_axis_seg_tuser_ena[0] = m_ena_reg[out_index_reg[0]];
    assign m_axis_seg_tuser_ena[1] = m_ena_reg[out_index_reg[1]];
    assign m_axis_seg_tuser_ena[2] = m_ena_reg[out_index_reg[2]];
    assign m_axis_seg_tuser_ena[3] = m_ena_reg[out_index_reg[3]];
    assign m_axis_seg_tuser_ena[4] = m_ena_reg[out_index_reg[4]];
    assign m_axis_seg_tuser_ena[5] = m_ena_reg[out_index_reg[5]];
    assign m_axis_seg_tuser_ena[6] = m_ena_reg[out_index_reg[6]];
    assign m_axis_seg_tuser_ena[7] = m_ena_reg[out_index_reg[7]];

    assign m_axis_seg_tuser_sop[0] = m_sop_reg[out_index_reg[0]];
    assign m_axis_seg_tuser_sop[1] = m_sop_reg[out_index_reg[1]];
    assign m_axis_seg_tuser_sop[2] = m_sop_reg[out_index_reg[2]];
    assign m_axis_seg_tuser_sop[3] = m_sop_reg[out_index_reg[3]];
    assign m_axis_seg_tuser_sop[4] = m_sop_reg[out_index_reg[4]];
    assign m_axis_seg_tuser_sop[5] = m_sop_reg[out_index_reg[5]];
    assign m_axis_seg_tuser_sop[6] = m_sop_reg[out_index_reg[6]];
    assign m_axis_seg_tuser_sop[7] = m_sop_reg[out_index_reg[7]];

    assign m_axis_seg_tuser_eop[0] = m_eop_reg[out_index_reg[0]];
    assign m_axis_seg_tuser_eop[1] = m_eop_reg[out_index_reg[1]];
    assign m_axis_seg_tuser_eop[2] = m_eop_reg[out_index_reg[2]];
    assign m_axis_seg_tuser_eop[3] = m_eop_reg[out_index_reg[3]];
    assign m_axis_seg_tuser_eop[4] = m_eop_reg[out_index_reg[4]];
    assign m_axis_seg_tuser_eop[5] = m_eop_reg[out_index_reg[5]];
    assign m_axis_seg_tuser_eop[6] = m_eop_reg[out_index_reg[6]];
    assign m_axis_seg_tuser_eop[7] = m_eop_reg[out_index_reg[7]];

    assign m_axis_seg_tuser_err[0] = m_err_reg[out_index_reg[0]];
    assign m_axis_seg_tuser_err[1] = m_err_reg[out_index_reg[1]];
    assign m_axis_seg_tuser_err[2] = m_err_reg[out_index_reg[2]];
    assign m_axis_seg_tuser_err[3] = m_err_reg[out_index_reg[3]];
    assign m_axis_seg_tuser_err[4] = m_err_reg[out_index_reg[4]];
    assign m_axis_seg_tuser_err[5] = m_err_reg[out_index_reg[5]];
    assign m_axis_seg_tuser_err[6] = m_err_reg[out_index_reg[6]];
    assign m_axis_seg_tuser_err[7] = m_err_reg[out_index_reg[7]];

endmodule