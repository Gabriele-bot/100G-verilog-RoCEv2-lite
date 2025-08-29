`resetall `timescale 1ns / 1ps `default_nettype none

/*
This module buffers a packet and stores its length 
*/


module axis_packet_framer #(
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 4096
) (

    input wire clk,
    input wire rst,

    /*
     * Input request
     */
    input  wire                         s_wr_req_valid,
    output wire                         s_wr_req_ready,
    input  wire [23:0]                  s_wr_req_loc_qp,
    input  wire [31:0]                  s_wr_req_dma_length,
    input  wire [63:0]                  s_wr_req_addr_offset,
    input  wire                         s_wr_req_is_immediate,
    input  wire [31:0]                  s_wr_req_immediate_data,
    input  wire                         s_wr_req_tx_type,

    // axis stream
    input   wire [DATA_WIDTH   - 1 :0]  s_axis_tdata,
    input   wire [DATA_WIDTH/8 - 1 :0]  s_axis_tkeep,
    input   wire                        s_axis_tvalid,
    output  wire                        s_axis_tready,
    input   wire                        s_axis_tlast,
    input   wire                        s_axis_tuser,

    /*
     * Output request
     */
    output  wire                        m_wr_req_valid,
    input wire                          m_wr_req_ready,
    output  wire [23:0]                 m_wr_req_loc_qp,
    output  wire [31:0]                 m_wr_req_dma_length,
    output  wire [63:0]                 m_wr_req_addr_offset,
    output  wire                        m_wr_req_is_immediate,
    output  wire [31:0]                 m_wr_req_immediate_data,
    output  wire                        m_wr_req_tx_type,

    // axis stream
    output  wire [DATA_WIDTH   - 1 :0]  m_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0]  m_axis_tkeep,
    output  wire                        m_axis_tvalid,
    input   wire                        m_axis_tready,
    output  wire                        m_axis_tlast,
    output  wire  [14              :0]  m_axis_tuser, // length (13bits), last packet in tranfer, bad frame 

    // config
    input wire [2:0] pmtu
);

    parameter WORD_WIDTH   = DATA_WIDTH/8;

    integer i;
    reg [DATA_WIDTH/8 - 1:0] count2keep_reg [DATA_WIDTH/8 - 1:0];

    generate
        for (genvar j = 0; j <= DATA_WIDTH/8 - 1; j = j + 1) begin
            if (j == 0) begin
                initial count2keep_reg[j] = 0;
            end else begin
                initial count2keep_reg[j] = {(j){1'b1}};
            end
        end
    endgenerate

    function [DATA_WIDTH/8 - 1:0] count2keep;
        input [$clog2(DATA_WIDTH/8):0] k;
        static reg [DATA_WIDTH/4 - 1:0] temp_ones = {{DATA_WIDTH/4{1'b0}}, {DATA_WIDTH/4{1'b1}}};
        reg [DATA_WIDTH/4 - 1:0] temp_srl;
        if (k < DATA_WIDTH/8) begin
            temp_srl = temp_ones << k;
            count2keep = temp_srl[DATA_WIDTH/8 +: DATA_WIDTH/8];
        end
        else begin
            count2keep = {DATA_WIDTH/8{1'b1}};
        end
    endfunction

    localparam [1:0]
    STATE_GET_METADATA     = 2'd0,
    STATE_GET_DATA        = 2'd1;

    reg [1:0] state_reg = STATE_GET_METADATA, state_next;

    reg [12:0] word_counter = {13{1'b1}} - WORD_WIDTH;
    reg [12:0] length_shift_register [1:0];
    reg last_frame;

    wire [153:0] s_wr_req, m_wr_req;
    reg  s_wr_req_reg_ready, s_wr_req_reg_valid;

    reg  s_wr_req_ready_reg = 1'b0, s_wr_req_ready_next;
    reg  m_wr_req_valid_reg = 1'b0, m_wr_req_valid_next;

    wire [DATA_WIDTH   - 1 : 0] s_axis_fifo_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] s_axis_fifo_tkeep;
    wire                        s_axis_fifo_tvalid;
    wire                        s_axis_fifo_tlast;
    wire [1                : 0] s_axis_fifo_tuser; // Bad frame, last
    wire                        s_axis_fifo_tready;

    wire [DATA_WIDTH   - 1 : 0] m_axis_fifo_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_axis_fifo_tkeep;
    wire                        m_axis_fifo_tvalid;
    wire                        m_axis_fifo_tlast;
    wire [1                : 0] m_axis_fifo_tuser; // Bad frame, last
    wire                        m_axis_fifo_tready;

    wire [DATA_WIDTH   - 1 : 0] s_axis_fifo_out_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] s_axis_fifo_out_tkeep;
    wire                        s_axis_fifo_out_tvalid;
    wire                        s_axis_fifo_out_tlast;
    wire [14               : 0] s_axis_fifo_out_tuser; // Bad frame, last
    wire                        s_axis_fifo_out_tready;

    reg transfer_ongoing;

    reg [3:0] pmtu_shift;
    reg [11:0] length_pmtu_mask;

    reg length_last_fifo_reg;

    reg [15:0] frame_len_reg, frame_len_next;
    reg        frame_len_valid_reg, frame_len_valid_next;
    reg [15:0] bit_cnt;

    wire [15:0] length_post_fifo;
    wire        last_post_fifo;
    wire        length_post_fifo_valid;
    reg         length_post_fifo_ready_reg;

    always @(posedge clk) begin
        case (pmtu)
            3'd0: begin
                pmtu_shift <= 4'd8;
                length_pmtu_mask = {4'h0, {8{1'b1}}};
            end
            3'd1: begin
                pmtu_shift <= 4'd9;
                length_pmtu_mask = {3'h0, {9{1'b1}}};
            end
            3'd2: begin
                pmtu_shift <= 4'd10;
                length_pmtu_mask = {2'h0, {10{1'b1}}};
            end
            3'd3: begin
                pmtu_shift <= 4'd11;
                length_pmtu_mask = {1'h0, {11{1'b1}}};
            end
            3'd4: begin
                pmtu_shift <= 4'd12;
                length_pmtu_mask = {12{1'b1}};
            end
        endcase
    end

    always @(*) begin
        state_next = STATE_GET_METADATA;

        s_wr_req_ready_next         = 1'b0;

        case (state_reg)
            STATE_GET_METADATA: begin
                s_wr_req_ready_next               = s_wr_req_reg_ready;
                if (s_wr_req_ready & s_wr_req_valid) begin
                    state_next = STATE_GET_DATA;
                    s_wr_req_ready_next         = 1'b0;
                end
            end
            STATE_GET_DATA: begin
                if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                    s_wr_req_ready_next  = s_wr_req_reg_ready;
                    state_next = STATE_GET_METADATA;
                end else begin
                    s_wr_req_ready_next         = 1'b0;
                    state_next = STATE_GET_DATA;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            word_counter      <= 0;
            transfer_ongoing  <= 1'b0;
            state_reg <= STATE_GET_METADATA;
            s_wr_req_ready_reg <= 1'b0;
        end else begin
            state_reg <= state_next;
            s_wr_req_ready_reg <= s_wr_req_ready_next;
            if (m_axis_fifo_tvalid && m_axis_fifo_tready) begin
                if (m_axis_fifo_tlast) begin
                    transfer_ongoing <= 1'b0;
                end else begin
                    transfer_ongoing <= 1'b1;
                end
            end
            if (s_axis_fifo_tvalid && s_axis_fifo_tready) begin
                word_counter <= word_counter + WORD_WIDTH;
                if (s_axis_fifo_tlast) begin
                    word_counter      <= 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            length_shift_register[0]      <= 13'd0;
            length_shift_register[1]      <= 13'd0;
            last_frame           <= 1'b0;
        end else begin
            if (s_axis_fifo_tready && s_axis_fifo_tvalid && s_axis_fifo_tlast) begin
                if (s_axis_tlast) begin
                    last_frame <= 1'b1;
                end else begin
                    last_frame <= 1'b0;
                end
                length_shift_register[0] <= word_counter + WORD_WIDTH;
                length_shift_register[1] <= length_shift_register[0];
            end
            if (m_axis_fifo_tready && m_axis_fifo_tvalid) begin
                if (m_axis_tlast) begin
                    length_post_fifo_ready_reg <= 1'b1;
                end else begin
                    length_post_fifo_ready_reg <= 1'b0;
                end
            end

        end
    end

    assign s_axis_fifo_tdata       = s_axis_tdata;
    assign s_axis_fifo_tkeep       = s_axis_tkeep;
    assign s_axis_fifo_tvalid      = s_axis_tvalid;
    assign s_axis_tready           = s_axis_fifo_tready;
    assign s_axis_fifo_tlast       = ((word_counter + WORD_WIDTH == (1 << pmtu_shift)) ? 1'b1 : 1'b0) | s_axis_tlast;
    assign s_axis_fifo_tuser[0]    = s_axis_tuser;
    assign s_axis_fifo_tuser[1]    = s_axis_tlast;

    axis_fifo #(
        .DEPTH(8192),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(2),
        .RAM_PIPELINE(2),
        .FRAME_FIFO(1)
    ) input_axis_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_axis_fifo_tdata),
        .s_axis_tkeep (s_axis_fifo_tkeep),
        .s_axis_tvalid(s_axis_fifo_tvalid),
        .s_axis_tready(s_axis_fifo_tready),
        .s_axis_tlast (s_axis_fifo_tlast),
        .s_axis_tuser (s_axis_fifo_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_fifo_tdata),
        .m_axis_tkeep (m_axis_fifo_tkeep),
        .m_axis_tvalid(m_axis_fifo_tvalid),
        .m_axis_tready(m_axis_fifo_tready),
        .m_axis_tlast (m_axis_fifo_tlast),
        .m_axis_tuser (m_axis_fifo_tuser),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );




    // length computation
    always @(*) begin
        frame_len_next = frame_len_reg;
        frame_len_valid_next = 1'b0;

        if (frame_len_valid_reg) begin
            frame_len_next = 0;
        end

        if (s_axis_fifo_tvalid && s_axis_fifo_tready) begin

            if (s_axis_fifo_tlast) begin
                // end of frame
                frame_len_valid_next = 1'b1;
            end

            bit_cnt = 0;
            for (i = 0; i <= DATA_WIDTH/8; i = i + 1) begin
                if (s_axis_fifo_tkeep == ({DATA_WIDTH/8{1'b1}}) >> (DATA_WIDTH/8-i)) bit_cnt = i;
            end
            frame_len_next = frame_len_next + bit_cnt;
        end
    end


    always @(posedge clk) begin
        if (rst) begin
            frame_len_reg <= 16'd0;
            frame_len_valid_reg <= 1'b0;
        end else begin
            frame_len_reg <= frame_len_next;
            frame_len_valid_reg <= frame_len_valid_next;
            length_last_fifo_reg <= s_axis_tlast && s_axis_tvalid && s_axis_tready;
        end
    end


    axis_fifo #(
        .DEPTH(8),
        .DATA_WIDTH(16),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .RAM_PIPELINE(1),
        .FRAME_FIFO(0)
    ) length_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (frame_len_reg),
        .s_axis_tvalid(frame_len_valid_reg),
        .s_axis_tready(),
        .s_axis_tlast (length_last_fifo_reg),
        .s_axis_tuser (0),
        .s_axis_tkeep (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (length_post_fifo),
        .m_axis_tlast (last_post_fifo),
        .m_axis_tvalid(length_post_fifo_valid),
        .m_axis_tready(m_axis_fifo_tvalid && m_axis_fifo_tready && m_axis_fifo_tlast)
    );

    assign s_wr_req_reg_valid = s_wr_req_valid;
    assign s_wr_req_ready     = s_wr_req_ready_reg;

    // DMA meta fifo
    axis_fifo #(
        .DEPTH(16),
        .DATA_WIDTH(154),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) input_wr_req_reg (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_wr_req),
        .s_axis_tvalid(s_wr_req_reg_valid),
        .s_axis_tready(s_wr_req_reg_ready),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_wr_req),
        .m_axis_tvalid(m_wr_req_valid),
        .m_axis_tready(m_wr_req_ready)
    );


    assign s_wr_req = { s_wr_req_loc_qp,
    s_wr_req_dma_length,
    s_wr_req_addr_offset,
    s_wr_req_immediate_data,
    s_wr_req_is_immediate,
    s_wr_req_tx_type};

    assign m_wr_req_tx_type        = m_wr_req[0];
    assign m_wr_req_is_immediate   = m_wr_req[1];
    assign m_wr_req_immediate_data = m_wr_req[2  +:32];
    assign m_wr_req_addr_offset    = m_wr_req[34 +:64];
    assign m_wr_req_dma_length     = m_wr_req[98 +:32];
    assign m_wr_req_loc_qp         = m_wr_req[130+:24];

    assign s_axis_fifo_out_tdata       = m_axis_fifo_tdata;
    assign s_axis_fifo_out_tkeep       = m_axis_fifo_tkeep;
    assign s_axis_fifo_out_tvalid      = m_axis_fifo_tvalid;
    assign m_axis_fifo_tready          = s_axis_fifo_out_tready;
    assign s_axis_fifo_out_tlast       = m_axis_fifo_tlast;
    assign s_axis_fifo_out_tuser[0]    = m_axis_fifo_tuser[0];
    assign s_axis_fifo_out_tuser[1]    = last_post_fifo;
    assign s_axis_fifo_out_tuser[14:2] = length_post_fifo[12:0];

    axis_fifo #(
        .DEPTH(4096),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(15),
        .RAM_PIPELINE(1),
        .FRAME_FIFO(0)
    ) output_axis_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_axis_fifo_out_tdata),
        .s_axis_tkeep (s_axis_fifo_out_tkeep),
        .s_axis_tvalid(s_axis_fifo_out_tvalid),
        .s_axis_tready(s_axis_fifo_out_tready),
        .s_axis_tlast (s_axis_fifo_out_tlast),
        .s_axis_tuser (s_axis_fifo_out_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tuser (m_axis_tuser),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );




endmodule

`resetall