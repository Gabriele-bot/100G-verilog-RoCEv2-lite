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
     * RoCE DMA transfer parameters in
     */
    input  wire       s_dma_meta_valid,
    output wire       s_dma_meta_ready,
    input wire [31:0] s_dma_length, // used on for WRITE operations
    input wire [23:0] s_rem_qpn,
    input wire [23:0] s_loc_qpn,
    input wire [23:0] s_rem_psn,
    input wire [31:0] s_r_key,
    input wire [31:0] s_rem_ip_addr,
    input wire [63:0] s_rem_addr,
    input wire        s_is_immediate,
    input wire [31:0] s_immediate_data,
    input wire        s_trasfer_type, // 0 SEND 1 RDMA_WRITE 

    // axis stream
    input   wire [DATA_WIDTH   - 1 :0] s_axis_tdata,
    input   wire [DATA_WIDTH/8 - 1 :0] s_axis_tkeep,
    input   wire                       s_axis_tvalid,
    output  wire                       s_axis_tready,
    input   wire                       s_axis_tlast,
    input   wire                       s_axis_tuser,

    /*
     * RoCE DMA transfer parameters out
     */
    output wire        m_dma_meta_valid,
    input  wire        m_dma_meta_ready,
    output wire [31:0] m_dma_length, // used on for WRITE operations
    output wire [23:0] m_rem_qpn,
    output wire [23:0] m_loc_qpn,
    output wire [23:0] m_rem_psn,
    output wire [31:0] m_r_key,
    output wire [31:0] m_rem_ip_addr,
    output wire [63:0] m_rem_addr,
    output wire        m_is_immediate,
    output wire [31:0] m_immediate_data,
    output wire        m_trasfer_type, // 0 SEND 1 RDMA_WRITE 

    // axis stream
    output  wire [DATA_WIDTH   - 1 :0] m_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_axis_tkeep,
    output  wire                       m_axis_tvalid,
    input   wire                       m_axis_tready,
    output  wire                       m_axis_tlast,
    output  wire  [14              :0] m_axis_tuser, // bad frame, current packet type, next packet type, length (13bits)

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

    function [$clog2(DATA_WIDTH/8):0] keep2count;
        input [DATA_WIDTH/8 - 1:0] k;
        for (i = DATA_WIDTH/8 - 1; i >= 0; i = i - 1) begin
            if (i == DATA_WIDTH/8 - 1) begin
                if (k[DATA_WIDTH/8 -1]) keep2count = DATA_WIDTH/8;
            end else begin
                if (k[i +: 2] == 2'b01) keep2count = i+1;
                else if (k[i +: 2] == 2'b00) keep2count = 0;
            end
        end
    endfunction

    function [DATA_WIDTH/8 - 1:0] count2keep;
        input [$clog2(DATA_WIDTH/8):0] k;
        if (k < DATA_WIDTH/8) count2keep = count2keep_reg[k];
        else count2keep = {DATA_WIDTH/8{1'b1}};
    endfunction

    localparam [1:0]
    STATE_GET_METADATA     = 2'd0,
    STATE_GET_DATA        = 2'd1;

    reg [1:0] state_reg = STATE_GET_METADATA, state_next;

    reg [12:0] word_counter = {13{1'b1}} - WORD_WIDTH;
    reg [12:0] length_shift_register [1:0];
    reg last_frame;

    wire  s_dma_meta_reg_valid, m_dma_meta_reg_valid;
    wire  s_dma_meta_reg_ready, m_dma_meta_reg_ready;
    wire [265:0] s_dma_metadata, m_dma_metadata;

    reg  s_dma_meta_ready_reg = 1'b0, s_dma_meta_ready_next;
    reg  m_dma_meta_valid_reg = 1'b0, m_dma_meta_valid_next;

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

    reg transfer_ongoing;

    reg [3:0] pmtu_shift;
    reg [11:0] length_pmtu_mask;


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

        s_dma_meta_ready_next         = 1'b0;

        case (state_reg)
            STATE_GET_METADATA: begin
                s_dma_meta_ready_next               = s_dma_meta_reg_ready;
                if (s_dma_meta_ready & s_dma_meta_valid) begin
                    state_next = STATE_GET_DATA;
                    s_dma_meta_ready_next         = 1'b0;
                end
            end
            STATE_GET_DATA: begin
                if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                    s_dma_meta_ready_next  = s_dma_meta_reg_ready;
                    state_next = STATE_GET_METADATA;
                end else begin
                    s_dma_meta_ready_next         = 1'b0;
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
            s_dma_meta_ready_reg <= 1'b0;
        end else begin
            state_reg <= state_next;
            s_dma_meta_ready_reg <= s_dma_meta_ready_next;
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

    axis_fifo #(
        .DEPTH(6),
        .DATA_WIDTH(16),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .FRAME_FIFO(0)
    ) length_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (word_counter + keep2count(s_axis_tkeep)),
        .s_axis_tvalid(s_axis_fifo_tready && s_axis_fifo_tvalid && s_axis_fifo_tlast),
        .s_axis_tready(),
        .s_axis_tlast (s_axis_tlast),
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

    assign s_dma_metadata = {
    s_dma_length,
    s_rem_qpn,
    s_loc_qpn,
    s_rem_psn,
    s_r_key,
    s_rem_ip_addr,
    s_rem_addr,
    s_is_immediate,
    s_immediate_data,
    s_trasfer_type};

    assign s_dma_meta_reg_valid = s_dma_meta_valid;
    assign s_dma_meta_ready = s_dma_meta_ready_reg;

    // DMA meta fifo
    axis_fifo #(
        .DEPTH(128),
        .DATA_WIDTH(266),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) input_dma_meta_reg (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_dma_metadata),
        .s_axis_tvalid(s_dma_meta_reg_valid),
        .s_axis_tready(s_dma_meta_reg_ready),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_dma_metadata),
        .m_axis_tvalid(m_dma_meta_valid),
        .m_axis_tready(m_dma_meta_ready)
    );



    assign m_trasfer_type = m_dma_metadata[0];
    assign m_immediate_data = m_dma_metadata[1+:32];
    assign m_is_immediate = m_dma_metadata[33];
    assign m_rem_addr = m_dma_metadata[34+:64];
    assign m_rem_ip_addr = m_dma_metadata[98+:32];
    assign m_r_key = m_dma_metadata[130+:32];
    assign m_rem_psn = m_dma_metadata[162+:24];
    assign m_loc_qpn = m_dma_metadata[186+:24];
    assign m_rem_qpn = m_dma_metadata[210+:24];
    assign m_dma_length = m_dma_metadata[234+:32];

    assign m_axis_tdata       = m_axis_fifo_tdata;
    assign m_axis_tkeep       = m_axis_fifo_tkeep;
    assign m_axis_tvalid      = m_axis_fifo_tvalid;
    assign m_axis_fifo_tready = m_axis_tready;
    assign m_axis_tlast       = m_axis_fifo_tlast;
    assign m_axis_tuser[0]    = m_axis_fifo_tuser[0];
    assign m_axis_tuser[1]    = last_post_fifo;
    assign m_axis_tuser[14:2] = length_post_fifo[12:0];

endmodule

`resetall