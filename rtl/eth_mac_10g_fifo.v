/*

Copyright (c) 2015-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 10G Ethernet MAC with TX and RX FIFOs
 */
module eth_mac_10g_fifo #
(
    parameter LOCAL_MAC_ADDRESS = 48'h02_00_00_00_00_00,
    parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = (DATA_WIDTH/8),
    parameter AXIS_DATA_WIDTH = DATA_WIDTH,
    parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
    parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
    parameter ENABLE_PADDING = 1,
    parameter ENABLE_DIC = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter TX_FIFO_DEPTH = 4096,
    parameter TX_FIFO_RAM_PIPELINE = 1,
    parameter TX_FRAME_FIFO = 1,
    parameter TX_DROP_OVERSIZE_FRAME = TX_FRAME_FIFO,
    parameter TX_DROP_BAD_FRAME = TX_DROP_OVERSIZE_FRAME,
    parameter TX_DROP_WHEN_FULL = 0,
    parameter RX_FIFO_DEPTH = 4096,
    parameter RX_FIFO_RAM_PIPELINE = 1,
    parameter RX_FRAME_FIFO = 1,
    parameter RX_DROP_OVERSIZE_FRAME = RX_FRAME_FIFO,
    parameter RX_DROP_BAD_FRAME = RX_DROP_OVERSIZE_FRAME,
    parameter RX_DROP_WHEN_FULL = RX_DROP_OVERSIZE_FRAME,
    parameter PTP_TS_ENABLE = 0,
    parameter PTP_TS_FMT_TOD = 1,
    parameter PTP_TS_WIDTH = PTP_TS_FMT_TOD ? 96 : 64,
    parameter TX_PTP_TS_CTRL_IN_TUSER = 0,
    parameter TX_PTP_TS_FIFO_DEPTH = 64,
    parameter TX_PTP_TAG_ENABLE = PTP_TS_ENABLE,
    parameter PTP_TAG_WIDTH = 16,
    parameter TX_USER_WIDTH = (PTP_TS_ENABLE ? (TX_PTP_TAG_ENABLE ? PTP_TAG_WIDTH : 0) + (TX_PTP_TS_CTRL_IN_TUSER ? 1 : 0) : 0) + 1,
    parameter RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1,
    parameter PFC_ENABLE = 0,
    parameter PFC_FIFO_ENABLE = 3'd0,
    parameter PAUSE_ENABLE = PFC_ENABLE
)
(
    input  wire                       rx_clk,
    input  wire                       rx_rst,
    input  wire                       tx_clk,
    input  wire                       tx_rst,
    input  wire                       logic_clk,
    input  wire                       logic_rst,
    input  wire                       ptp_sample_clk,

    /*
     * AXI input
     */
    input  wire [AXIS_DATA_WIDTH-1:0] tx_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0] tx_axis_tkeep,
    input  wire                       tx_axis_tvalid,
    output wire                       tx_axis_tready,
    input  wire                       tx_axis_tlast,
    input  wire [TX_USER_WIDTH-1:0]   tx_axis_tuser,

    /*
     * Transmit timestamp output
     */
    output wire [PTP_TS_WIDTH-1:0]    m_axis_tx_ptp_ts_96,
    output wire [PTP_TAG_WIDTH-1:0]   m_axis_tx_ptp_ts_tag,
    output wire                       m_axis_tx_ptp_ts_valid,
    input  wire                       m_axis_tx_ptp_ts_ready,

    /*
     * AXI output
     */
    output wire [AXIS_DATA_WIDTH-1:0] rx_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] rx_axis_tkeep,
    output wire                       rx_axis_tvalid,
    input  wire                       rx_axis_tready,
    output wire                       rx_axis_tlast,
    output wire [RX_USER_WIDTH-1:0]   rx_axis_tuser,

    /*
     * XGMII interface
     */
    input  wire [DATA_WIDTH-1:0]      xgmii_rxd,
    input  wire [CTRL_WIDTH-1:0]      xgmii_rxc,
    output wire [DATA_WIDTH-1:0]      xgmii_txd,
    output wire [CTRL_WIDTH-1:0]      xgmii_txc,

    /*
     * Status
     */
    output wire                       tx_error_underflow,
    output wire                       tx_fifo_overflow,
    output wire                       tx_fifo_bad_frame,
    output wire                       tx_fifo_good_frame,
    output wire                       rx_error_bad_frame,
    output wire                       rx_error_bad_fcs,
    output wire                       rx_fifo_overflow,
    output wire                       rx_fifo_bad_frame,
    output wire                       rx_fifo_good_frame,

    /*
    Pause outputs
    */
    output wire [8:0] tx_pause_req_out,
    output wire [8:0] tx_pause_ack_out,
    /*
     * PTP clock
     */
    input  wire [PTP_TS_WIDTH-1:0]    ptp_ts_96,
    input  wire                       ptp_ts_step,

    /*
     * Configuration
     */
    input  wire [7:0]                 cfg_ifg,
    input  wire [2:0]                 ctrl_priority_tag,
    input  wire                       cfg_tx_enable,
    input  wire                       cfg_rx_enable,
    input  wire [47:0]                cfg_local_mac
);

    parameter KEEP_WIDTH = DATA_WIDTH/8;

    parameter MAC_MULTICAST_ADDRESS = 48'h01_80_C2_00_00_01;

    parameter MAC_CONTROL_FRAME_ETH_TYPE = 16'h8808;

    parameter LFC_OPCODE = 16'h0001;
    parameter PFC_OPCODE = 16'h0101;

    parameter LFC_QUANTA  = 16'hffff;
    parameter LFC_REFRESH = 16'h7fff;
    parameter PFC_QUANTA  = {16'hffff, 16'hffff, 16'hffff, 16'hffff, 16'hffff, 16'hffff, 16'hffff, 16'hffff};
    parameter PFC_REFRESH = {16'h7fff, 16'h7fff, 16'h7fff, 16'h7fff, 16'h7fff, 16'h7fff, 16'h7fff, 16'h7fff};

    wire [DATA_WIDTH-1:0]      tx_fifo_axis_tdata;
    wire [KEEP_WIDTH-1:0]      tx_fifo_axis_tkeep;
    wire                       tx_fifo_axis_tvalid;
    wire                       tx_fifo_axis_tready;
    wire                       tx_fifo_axis_tlast;
    wire [TX_USER_WIDTH-1:0]   tx_fifo_axis_tuser;

    wire [DATA_WIDTH -1 :0]      m_tx_axis_pfc_demux_tdata;
    wire [KEEP_WIDTH-1 :0 ]      m_tx_axis_pfc_demux_tkeep;
    wire                         m_tx_axis_pfc_demux_tvalid;
    wire                         m_tx_axis_pfc_demux_tready;
    wire                         m_tx_axis_pfc_demux_tlast;
    wire                         m_tx_axis_pfc_demux_tuser;

    wire [DATA_WIDTH -1 :0]      tx_mac_fifo_axis_tdata;
    wire [KEEP_WIDTH-1 :0 ]      tx_mac_fifo_axis_tkeep;
    wire                         tx_mac_fifo_axis_tvalid;
    wire                         tx_mac_fifo_axis_tready;
    wire                         tx_mac_fifo_axis_tlast;
    wire                         tx_mac_fifo_axis_tuser;

    wire [DATA_WIDTH-1:0]      rx_fifo_axis_tdata;
    wire [KEEP_WIDTH-1:0]      rx_fifo_axis_tkeep;
    wire                       rx_fifo_axis_tvalid;
    wire                       rx_fifo_axis_tlast;
    wire [RX_USER_WIDTH-1:0]   rx_fifo_axis_tuser;

    wire [PTP_TS_WIDTH-1:0]    tx_ptp_ts_96;
    wire [PTP_TS_WIDTH-1:0]    rx_ptp_ts_96;

    wire [PTP_TS_WIDTH-1:0]    tx_axis_ptp_ts_96;
    wire [PTP_TAG_WIDTH-1:0]   tx_axis_ptp_ts_tag;
    wire                       tx_axis_ptp_ts_valid;

    // synchronize MAC status signals into logic clock domain
    wire tx_error_underflow_int;

    reg [0:0] tx_sync_reg_1 = 1'b0;
    reg [0:0] tx_sync_reg_2 = 1'b0;
    reg [0:0] tx_sync_reg_3 = 1'b0;
    reg [0:0] tx_sync_reg_4 = 1'b0;

    reg [8:0] eth_tx_pause_req_sync_reg_1 = 9'd0;
    reg [8:0] eth_tx_pause_req_sync_reg_2 = 9'd0;
    reg [8:0] eth_tx_pause_req_sync_reg_3 = 9'd0;

    wire [8:0] eth_tx_pause_req;
    wire [8:0] eth_tx_pause_ack;

    assign tx_error_underflow = tx_sync_reg_3[0] ^ tx_sync_reg_4[0];


    always @(posedge tx_clk or posedge tx_rst) begin
        if (tx_rst) begin
            tx_sync_reg_1 <= 1'b0;
        end else begin
            tx_sync_reg_1 <= tx_sync_reg_1 ^ {tx_error_underflow_int};
        end
    end

    always @(posedge logic_clk or posedge logic_rst) begin
        if (logic_rst) begin
            tx_sync_reg_2 <= 1'b0;
            tx_sync_reg_3 <= 1'b0;
            tx_sync_reg_4 <= 1'b0;
        end else begin
            tx_sync_reg_2 <= tx_sync_reg_1;
            tx_sync_reg_3 <= tx_sync_reg_2;
            tx_sync_reg_4 <= tx_sync_reg_3;
        end
    end

    wire rx_error_bad_frame_int;
    wire rx_error_bad_fcs_int;

    reg [1:0] rx_sync_reg_1 = 2'd0;
    reg [1:0] rx_sync_reg_2 = 2'd0;
    reg [1:0] rx_sync_reg_3 = 2'd0;
    reg [1:0] rx_sync_reg_4 = 2'd0;

    wire [8:0] eth_rx_pause_req;


    reg [8:0] eth_rx_pause_ack_sync_reg_1 = 8'd0;
    reg [8:0] eth_rx_pause_ack_sync_reg_2 = 8'd0;
    reg [8:0] eth_rx_pause_ack_sync_reg_3 = 8'd0;

    // sync rx pfc req with logic clock
    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            eth_tx_pause_req_sync_reg_1 <= 9'd0;
        end else begin
            eth_tx_pause_req_sync_reg_1 <= eth_rx_pause_req;
        end
    end

    always @(posedge logic_clk or posedge logic_rst) begin
        if (logic_rst) begin
            eth_tx_pause_req_sync_reg_2 <= 9'd0;
            eth_tx_pause_req_sync_reg_3 <= 9'd0;
        end else begin
            eth_tx_pause_req_sync_reg_2 <= eth_tx_pause_req_sync_reg_1;
            eth_tx_pause_req_sync_reg_3 <= eth_tx_pause_req_sync_reg_2;
        end
    end

    // sync tx ack with rx clock
    always @(posedge logic_clk or posedge logic_rst) begin
        if (logic_rst) begin
            eth_rx_pause_ack_sync_reg_1 <= 9'd0;
        end else begin
            eth_rx_pause_ack_sync_reg_1 <= eth_tx_pause_ack;
        end
    end

    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            eth_rx_pause_ack_sync_reg_2 <= 9'd0;
            eth_rx_pause_ack_sync_reg_3 <= 9'd0;
        end else begin
            eth_rx_pause_ack_sync_reg_2 <= eth_rx_pause_ack_sync_reg_1;
            eth_rx_pause_ack_sync_reg_3 <= eth_rx_pause_ack_sync_reg_2;
        end
    end

    assign rx_error_bad_frame = rx_sync_reg_3[0] ^ rx_sync_reg_4[0];
    assign rx_error_bad_fcs = rx_sync_reg_3[1] ^ rx_sync_reg_4[1];

    always @(posedge rx_clk or posedge rx_rst) begin
        if (rx_rst) begin
            rx_sync_reg_1 <= 2'd0;
        end else begin
            rx_sync_reg_1 <= rx_sync_reg_1 ^ {rx_error_bad_fcs_int, rx_error_bad_frame_int};
        end
    end

    always @(posedge logic_clk or posedge logic_rst) begin
        if (logic_rst) begin
            rx_sync_reg_2 <= 2'd0;
            rx_sync_reg_3 <= 2'd0;
            rx_sync_reg_4 <= 2'd0;
        end else begin
            rx_sync_reg_2 <= rx_sync_reg_1;
            rx_sync_reg_3 <= rx_sync_reg_2;
            rx_sync_reg_4 <= rx_sync_reg_3;
        end
    end

    assign eth_tx_pause_req = eth_tx_pause_req_sync_reg_3;
    // PFC fifos
    generate

        if (PFC_ENABLE && PFC_FIFO_ENABLE != 8'h00) begin

            wire [8*DATA_WIDTH-1:0]  m_tx_axis_pfc_priorities_tdata;
            wire [8*KEEP_WIDTH-1:0]  m_tx_axis_pfc_priorities_tkeep;
            wire [7:0]               m_tx_axis_pfc_priorities_tvalid;
            wire [7:0]               m_tx_axis_pfc_priorities_tready;
            wire [7:0]               m_tx_axis_pfc_priorities_tlast;
            wire [7:0]               m_tx_axis_pfc_priorities_tuser;

            axis_demux #(
                .M_COUNT(8),
                .DATA_WIDTH(DATA_WIDTH),
                .KEEP_WIDTH(KEEP_WIDTH),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1)
            ) axis_demux_instance (
                .clk(logic_clk),
                .rst(logic_rst),

                .s_axis_tdata (tx_axis_tdata),
                .s_axis_tkeep (tx_axis_tkeep),
                .s_axis_tvalid(tx_axis_tvalid),
                .s_axis_tready(tx_axis_tready),
                .s_axis_tlast (tx_axis_tlast),
                .s_axis_tuser (tx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                .m_axis_tdata (m_tx_axis_pfc_priorities_tdata),
                .m_axis_tkeep (m_tx_axis_pfc_priorities_tkeep),
                .m_axis_tvalid(m_tx_axis_pfc_priorities_tvalid),
                .m_axis_tready(m_tx_axis_pfc_priorities_tready),
                .m_axis_tlast (m_tx_axis_pfc_priorities_tlast),
                .m_axis_tuser (m_tx_axis_pfc_priorities_tuser),

                .enable(1'b1),
                .drop(1'b0),
                .select(ctrl_priority_tag)
            );

            eth_pfc_fifo_tx #(
                .DATA_WIDTH(DATA_WIDTH),
                .KEEP_WIDTH(KEEP_WIDTH),
                .FIFO_DEPTH(TX_FIFO_DEPTH),
                .ENABLE_PRIORITY_MASK(PFC_FIFO_ENABLE)
            ) eth_pfc_fifo_tx_instance (
                .clk(logic_clk),
                .rst(logic_rst),
                .s_priority_0_axis_tdata (m_tx_axis_pfc_priorities_tdata [0*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_0_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [0*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_0_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[0]),
                .s_priority_0_axis_tready(m_tx_axis_pfc_priorities_tready[0]),
                .s_priority_0_axis_tlast (m_tx_axis_pfc_priorities_tlast [0]),
                .s_priority_0_axis_tuser (m_tx_axis_pfc_priorities_tuser [0]),

                .s_priority_1_axis_tdata (m_tx_axis_pfc_priorities_tdata [1*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_1_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [1*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_1_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[1]),
                .s_priority_1_axis_tready(m_tx_axis_pfc_priorities_tready[1]),
                .s_priority_1_axis_tlast (m_tx_axis_pfc_priorities_tlast [1]),
                .s_priority_1_axis_tuser (m_tx_axis_pfc_priorities_tuser [1]),

                .s_priority_2_axis_tdata (m_tx_axis_pfc_priorities_tdata [2*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_2_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [2*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_2_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[2]),
                .s_priority_2_axis_tready(m_tx_axis_pfc_priorities_tready[2]),
                .s_priority_2_axis_tlast (m_tx_axis_pfc_priorities_tlast [2]),
                .s_priority_2_axis_tuser (m_tx_axis_pfc_priorities_tuser [2]),

                .s_priority_3_axis_tdata (m_tx_axis_pfc_priorities_tdata [3*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_3_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [3*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_3_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[3]),
                .s_priority_3_axis_tready(m_tx_axis_pfc_priorities_tready[3]),
                .s_priority_3_axis_tlast (m_tx_axis_pfc_priorities_tlast [3]),
                .s_priority_3_axis_tuser (m_tx_axis_pfc_priorities_tuser [3]),

                .s_priority_4_axis_tdata (m_tx_axis_pfc_priorities_tdata [4*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_4_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [4*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_4_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[4]),
                .s_priority_4_axis_tready(m_tx_axis_pfc_priorities_tready[4]),
                .s_priority_4_axis_tlast (m_tx_axis_pfc_priorities_tlast [4]),
                .s_priority_4_axis_tuser (m_tx_axis_pfc_priorities_tuser [4]),

                .s_priority_5_axis_tdata (m_tx_axis_pfc_priorities_tdata [5*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_5_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [5*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_5_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[5]),
                .s_priority_5_axis_tready(m_tx_axis_pfc_priorities_tready[5]),
                .s_priority_5_axis_tlast (m_tx_axis_pfc_priorities_tlast [5]),
                .s_priority_5_axis_tuser (m_tx_axis_pfc_priorities_tuser [5]),

                .s_priority_6_axis_tdata (m_tx_axis_pfc_priorities_tdata [6*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_6_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [6*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_6_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[6]),
                .s_priority_6_axis_tready(m_tx_axis_pfc_priorities_tready[6]),
                .s_priority_6_axis_tlast (m_tx_axis_pfc_priorities_tlast [6]),
                .s_priority_6_axis_tuser (m_tx_axis_pfc_priorities_tuser [6]),

                .s_priority_7_axis_tdata (m_tx_axis_pfc_priorities_tdata [7*DATA_WIDTH+:DATA_WIDTH]),
                .s_priority_7_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [7*KEEP_WIDTH+:KEEP_WIDTH]),
                .s_priority_7_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[7]),
                .s_priority_7_axis_tready(m_tx_axis_pfc_priorities_tready[7]),
                .s_priority_7_axis_tlast (m_tx_axis_pfc_priorities_tlast [7]),
                .s_priority_7_axis_tuser (m_tx_axis_pfc_priorities_tuser [7]),

                .m_axis_tdata (tx_mac_fifo_axis_tdata),
                .m_axis_tkeep (tx_mac_fifo_axis_tkeep),
                .m_axis_tvalid(tx_mac_fifo_axis_tvalid),
                .m_axis_tready(tx_mac_fifo_axis_tready),
                .m_axis_tlast (tx_mac_fifo_axis_tlast),
                .m_axis_tuser (tx_mac_fifo_axis_tuser),

                .pause_req(eth_tx_pause_req[7:0]),
                .pause_ack(eth_tx_pause_ack[7:0])
            );
        end else begin
            assign tx_mac_fifo_axis_tdata     = tx_axis_tdata;
            assign tx_mac_fifo_axis_tkeep     = tx_axis_tkeep;
            assign tx_mac_fifo_axis_tvalid    = tx_axis_tvalid;
            assign tx_axis_tready             = tx_mac_fifo_axis_tready;
            assign tx_mac_fifo_axis_tlast     = tx_axis_tlast;
            assign tx_mac_fifo_axis_tuser     = tx_axis_tuser;

            assign eth_tx_pause_ack[7:0] = 8'hFF;
        end

    endgenerate

    assign tx_pause_req_out = eth_tx_pause_req;
    assign tx_pause_ack_out = eth_tx_pause_ack;

    // PTP timestamping
    generate

        if (PTP_TS_ENABLE) begin : tx_ptp

            ptp_clock_cdc #(
                .TS_WIDTH(PTP_TS_WIDTH),
                .NS_WIDTH(6)
            )
            tx_ptp_cdc (
                .input_clk(logic_clk),
                .input_rst(logic_rst),
                .output_clk(tx_clk),
                .output_rst(tx_rst),
                .sample_clk(ptp_sample_clk),
                .input_ts(ptp_ts_96),
                .input_ts_step(ptp_ts_step),
                .output_ts(tx_ptp_ts_96),
                .output_ts_step(),
                .output_pps(),
                .locked()
            );

            axis_async_fifo #(
                .DEPTH(TX_PTP_TS_FIFO_DEPTH),
                .DATA_WIDTH(PTP_TS_WIDTH),
                .KEEP_ENABLE(0),
                .LAST_ENABLE(0),
                .ID_ENABLE(TX_PTP_TAG_ENABLE),
                .ID_WIDTH(PTP_TAG_WIDTH),
                .DEST_ENABLE(0),
                .USER_ENABLE(0),
                .FRAME_FIFO(0)
            )
            tx_ptp_ts_fifo (
                // AXI input
                .s_clk(tx_clk),
                .s_rst(tx_rst),
                .s_axis_tdata(tx_axis_ptp_ts_96),
                .s_axis_tkeep(0),
                .s_axis_tvalid(tx_axis_ptp_ts_valid),
                .s_axis_tready(),
                .s_axis_tlast(0),
                .s_axis_tid(tx_axis_ptp_ts_tag),
                .s_axis_tdest(0),
                .s_axis_tuser(0),

                // AXI output
                .m_clk(logic_clk),
                .m_rst(logic_rst),
                .m_axis_tdata(m_axis_tx_ptp_ts_96),
                .m_axis_tkeep(),
                .m_axis_tvalid(m_axis_tx_ptp_ts_valid),
                .m_axis_tready(m_axis_tx_ptp_ts_ready),
                .m_axis_tlast(),
                .m_axis_tid(m_axis_tx_ptp_ts_tag),
                .m_axis_tdest(),
                .m_axis_tuser(),

                // Status
                .s_status_overflow(),
                .s_status_bad_frame(),
                .s_status_good_frame(),
                .m_status_overflow(),
                .m_status_bad_frame(),
                .m_status_good_frame()
            );

        end else begin

            assign m_axis_tx_ptp_ts_96 = {PTP_TS_WIDTH{1'b0}};
            assign m_axis_tx_ptp_ts_tag = {PTP_TAG_WIDTH{1'b0}};
            assign m_axis_tx_ptp_ts_valid = 1'b0;

            assign tx_ptp_ts_96 = {PTP_TS_WIDTH{1'b0}};

        end

        if (PTP_TS_ENABLE) begin : rx_ptp

            ptp_clock_cdc #(
                .TS_WIDTH(PTP_TS_WIDTH),
                .NS_WIDTH(6)
            )
            rx_ptp_cdc (
                .input_clk(logic_clk),
                .input_rst(logic_rst),
                .output_clk(rx_clk),
                .output_rst(rx_rst),
                .sample_clk(ptp_sample_clk),
                .input_ts(ptp_ts_96),
                .input_ts_step(ptp_ts_step),
                .output_ts(rx_ptp_ts_96),
                .output_ts_step(),
                .output_pps(),
                .locked()
            );

        end else begin

            assign rx_ptp_ts_96 = {PTP_TS_WIDTH{1'b0}};

        end

    endgenerate
    
    wire [7:0] rx_pfc_en;
    generate
    if (PFC_ENABLE) begin
    	assign rx_pfc_en = 8'hff;
    end else begin
    	assign rx_pfc_en = 8'd0;
    end
    endgenerate

    eth_mac_10g #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .CTRL_WIDTH(CTRL_WIDTH),
        .ENABLE_PADDING(ENABLE_PADDING),
        .ENABLE_DIC(ENABLE_DIC),
        .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
        .PTP_TS_ENABLE(PTP_TS_ENABLE),
        .PTP_TS_FMT_TOD(PTP_TS_FMT_TOD),
        .PTP_TS_WIDTH(PTP_TS_WIDTH),
        .TX_PTP_TS_CTRL_IN_TUSER(TX_PTP_TS_CTRL_IN_TUSER),
        .TX_PTP_TAG_ENABLE(TX_PTP_TAG_ENABLE),
        .TX_PTP_TAG_WIDTH(PTP_TAG_WIDTH),
        .TX_USER_WIDTH(TX_USER_WIDTH),
        .RX_USER_WIDTH(RX_USER_WIDTH),
        .PFC_ENABLE(PFC_ENABLE),
        .PAUSE_ENABLE(PAUSE_ENABLE)
    )
    eth_mac_10g_inst (
        .tx_clk(tx_clk),
        .tx_rst(tx_rst),
        .rx_clk(rx_clk),
        .rx_rst(rx_rst),

        .tx_axis_tdata(tx_fifo_axis_tdata),
        .tx_axis_tkeep(tx_fifo_axis_tkeep),
        .tx_axis_tvalid(tx_fifo_axis_tvalid),
        .tx_axis_tready(tx_fifo_axis_tready),
        .tx_axis_tlast(tx_fifo_axis_tlast),
        .tx_axis_tuser(tx_fifo_axis_tuser),

        .rx_axis_tdata(rx_fifo_axis_tdata),
        .rx_axis_tkeep(rx_fifo_axis_tkeep),
        .rx_axis_tvalid(rx_fifo_axis_tvalid),
        .rx_axis_tlast(rx_fifo_axis_tlast),
        .rx_axis_tuser(rx_fifo_axis_tuser),

        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),

        .tx_ptp_ts(tx_ptp_ts_96),
        .rx_ptp_ts(rx_ptp_ts_96),
        .tx_axis_ptp_ts(tx_axis_ptp_ts_96),
        .tx_axis_ptp_ts_tag(tx_axis_ptp_ts_tag),
        .tx_axis_ptp_ts_valid(tx_axis_ptp_ts_valid),

        /*
         * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
         */
        .tx_lfc_req(1'b0),
        .tx_lfc_resend(1'b0),
        .rx_lfc_en(PAUSE_ENABLE),
        .rx_lfc_req(eth_rx_pause_req[8]),
        .rx_lfc_ack(1'b0),

        /*
         * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
         */
        .tx_pfc_req(1'b0),
        .tx_pfc_resend(1'b0),
        .rx_pfc_en(rx_pfc_en),
        .rx_pfc_req(eth_rx_pause_req[7:0]),
        .rx_pfc_ack(eth_rx_pause_ack_sync_reg_3[7:0]),

        /*
         * Pause interface
         */
        .tx_lfc_pause_en(PAUSE_ENABLE),
        .tx_pause_req(1'b0),
        .tx_pause_ack(),

        .tx_error_underflow(tx_error_underflow_int),
        .rx_error_bad_frame(rx_error_bad_frame_int),
        .rx_error_bad_fcs(rx_error_bad_fcs_int),

        /*
         * Configuration
         */
        .cfg_ifg(cfg_ifg),
        .cfg_tx_enable(cfg_tx_enable),
        .cfg_rx_enable(cfg_rx_enable),

        .cfg_mcf_rx_eth_dst_mcast(MAC_MULTICAST_ADDRESS),
        .cfg_mcf_rx_check_eth_dst_mcast(1'b1),
        .cfg_mcf_rx_eth_dst_ucast(48'd0),
        .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
        .cfg_mcf_rx_eth_src(48'h0),
        .cfg_mcf_rx_check_eth_src(1'b0),
        .cfg_mcf_rx_eth_type(MAC_CONTROL_FRAME_ETH_TYPE),
        .cfg_mcf_rx_opcode_lfc(LFC_OPCODE),
        .cfg_mcf_rx_check_opcode_lfc(PAUSE_ENABLE),
        .cfg_mcf_rx_opcode_pfc(PFC_OPCODE),
        .cfg_mcf_rx_check_opcode_pfc(PFC_ENABLE),
        .cfg_mcf_rx_forward(1'b0),
        .cfg_mcf_rx_enable(PFC_ENABLE | PAUSE_ENABLE),
        .cfg_tx_lfc_eth_dst(MAC_MULTICAST_ADDRESS),
        .cfg_tx_lfc_eth_src(LOCAL_MAC_ADDRESS),
        .cfg_tx_lfc_eth_type(MAC_CONTROL_FRAME_ETH_TYPE),
        .cfg_tx_lfc_opcode(LFC_OPCODE),
        .cfg_tx_lfc_en(PAUSE_ENABLE),
        .cfg_tx_lfc_quanta(LFC_QUANTA),
        .cfg_tx_lfc_refresh(LFC_REFRESH),
        .cfg_tx_pfc_eth_dst(MAC_MULTICAST_ADDRESS),
        .cfg_tx_pfc_eth_src(LOCAL_MAC_ADDRESS),
        .cfg_tx_pfc_eth_type(MAC_CONTROL_FRAME_ETH_TYPE),
        .cfg_tx_pfc_opcode(PFC_OPCODE),
        .cfg_tx_pfc_en(PFC_ENABLE),
        .cfg_tx_pfc_quanta(PFC_QUANTA),
        .cfg_tx_pfc_refresh(PFC_REFRESH),
        .cfg_rx_lfc_opcode(LFC_OPCODE),
        .cfg_rx_lfc_en(PAUSE_ENABLE),
        .cfg_rx_pfc_opcode(PFC_OPCODE),
        .cfg_rx_pfc_en(PFC_ENABLE)
    );


    axis_async_fifo_adapter #(
        .DEPTH(TX_FIFO_DEPTH),
        .S_DATA_WIDTH(AXIS_DATA_WIDTH),
        .S_KEEP_ENABLE(AXIS_KEEP_ENABLE),
        .S_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .M_DATA_WIDTH(DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(TX_USER_WIDTH),
        .RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
        .FRAME_FIFO(TX_FRAME_FIFO),
        .USER_BAD_FRAME_VALUE(1'b1),
        .USER_BAD_FRAME_MASK(1'b1),
        .DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
        .DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
        .DROP_WHEN_FULL(TX_DROP_WHEN_FULL)
    )
    tx_fifo (
        // AXI input
        .s_clk(logic_clk),
        .s_rst(logic_rst),
        .s_axis_tdata (tx_mac_fifo_axis_tdata),
        .s_axis_tkeep (tx_mac_fifo_axis_tkeep),
        .s_axis_tvalid(tx_mac_fifo_axis_tvalid),
        .s_axis_tready(tx_mac_fifo_axis_tready),
        .s_axis_tlast (tx_mac_fifo_axis_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (tx_mac_fifo_axis_tuser),
        // AXI output
        .m_clk(tx_clk),
        .m_rst(tx_rst),
        .m_axis_tdata(tx_fifo_axis_tdata),
        .m_axis_tkeep(tx_fifo_axis_tkeep),
        .m_axis_tvalid(tx_fifo_axis_tvalid),
        .m_axis_tready(tx_fifo_axis_tready),
        .m_axis_tlast(tx_fifo_axis_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(tx_fifo_axis_tuser),
        // Pause
        .s_pause_req(1'b0),
        .s_pause_ack(),
        .m_pause_req(1'b0),
        .m_pause_ack(),
        // Status
        .s_status_overflow(tx_fifo_overflow),
        .s_status_bad_frame(tx_fifo_bad_frame),
        .s_status_good_frame(tx_fifo_good_frame),
        .m_status_overflow(),
        .m_status_bad_frame(),
        .m_status_good_frame()
    );


    axis_async_fifo_adapter #(
        .DEPTH(RX_FIFO_DEPTH),
        .S_DATA_WIDTH(DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(KEEP_WIDTH),
        .M_DATA_WIDTH(AXIS_DATA_WIDTH),
        .M_KEEP_ENABLE(AXIS_KEEP_ENABLE),
        .M_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(RX_USER_WIDTH),
        .RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
        .FRAME_FIFO(RX_FRAME_FIFO),
        .USER_BAD_FRAME_VALUE(1'b1),
        .USER_BAD_FRAME_MASK(1'b1),
        .DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
        .DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
        .DROP_WHEN_FULL(RX_DROP_WHEN_FULL)
    )
    rx_fifo (
        // AXI input
        .s_clk(rx_clk),
        .s_rst(rx_rst),
        .s_axis_tdata(rx_fifo_axis_tdata),
        .s_axis_tkeep(rx_fifo_axis_tkeep),
        .s_axis_tvalid(rx_fifo_axis_tvalid),
        .s_axis_tready(),
        .s_axis_tlast(rx_fifo_axis_tlast),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(rx_fifo_axis_tuser),
        // AXI output
        .m_clk(logic_clk),
        .m_rst(logic_rst),
        .m_axis_tdata(rx_axis_tdata),
        .m_axis_tkeep(rx_axis_tkeep),
        .m_axis_tvalid(rx_axis_tvalid),
        .m_axis_tready(rx_axis_tready),
        .m_axis_tlast(rx_axis_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(rx_axis_tuser),
        // Status
        .s_status_overflow(),
        .s_status_bad_frame(),
        .s_status_good_frame(),
        .m_status_overflow(rx_fifo_overflow),
        .m_status_bad_frame(rx_fifo_bad_frame),
        .m_status_good_frame(rx_fifo_good_frame)
    );

endmodule

`resetall
