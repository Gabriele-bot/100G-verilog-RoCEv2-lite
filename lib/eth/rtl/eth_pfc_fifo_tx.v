`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream ethernet frame transmitter (Ethernet frame in, AXI out)
 */
module eth_pfc_fifo_tx#
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // Flow control fifo depth
    parameter FIFO_DEPTH = 1024
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * AXIS inputs
     */
    input  wire [DATA_WIDTH-1:0] s_priority_0_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_0_axis_tkeep,
    input  wire                  s_priority_0_axis_tvalid,
    output wire                  s_priority_0_axis_tready,
    input  wire                  s_priority_0_axis_tlast,
    input  wire                  s_priority_0_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_1_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_1_axis_tkeep,
    input  wire                  s_priority_1_axis_tvalid,
    output wire                  s_priority_1_axis_tready,
    input  wire                  s_priority_1_axis_tlast,
    input  wire                  s_priority_1_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_2_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_2_axis_tkeep,
    input  wire                  s_priority_2_axis_tvalid,
    output wire                  s_priority_2_axis_tready,
    input  wire                  s_priority_2_axis_tlast,
    input  wire                  s_priority_2_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_3_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_3_axis_tkeep,
    input  wire                  s_priority_3_axis_tvalid,
    output wire                  s_priority_3_axis_tready,
    input  wire                  s_priority_3_axis_tlast,
    input  wire                  s_priority_3_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_4_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_4_axis_tkeep,
    input  wire                  s_priority_4_axis_tvalid,
    output wire                  s_priority_4_axis_tready,
    input  wire                  s_priority_4_axis_tlast,
    input  wire                  s_priority_4_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_5_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_5_axis_tkeep,
    input  wire                  s_priority_5_axis_tvalid,
    output wire                  s_priority_5_axis_tready,
    input  wire                  s_priority_5_axis_tlast,
    input  wire                  s_priority_5_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_6_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_6_axis_tkeep,
    input  wire                  s_priority_6_axis_tvalid,
    output wire                  s_priority_6_axis_tready,
    input  wire                  s_priority_6_axis_tlast,
    input  wire                  s_priority_6_axis_tuser,

    input  wire [DATA_WIDTH-1:0] s_priority_7_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_7_axis_tkeep,
    input  wire                  s_priority_7_axis_tvalid,
    output wire                  s_priority_7_axis_tready,
    input  wire                  s_priority_7_axis_tlast,
    input  wire                  s_priority_7_axis_tuser,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire                  m_axis_tuser,

    /*
    Pause signals
    */
    input  wire [8:0]             pause_req,
    output wire [8:0]             pause_ack,

    /*
     * Status signals
     */
    output wire                  busy
);

    wire [8*DATA_WIDTH-1:0] m_axis_pfc_fifo_tdata ;
    wire [8*KEEP_WIDTH-1:0] m_axis_pfc_fifo_tkeep ;
    wire [7:0]              m_axis_pfc_fifo_tvalid;
    wire [7:0]              m_axis_pfc_fifo_tlast ;
    wire [7:0]              m_axis_pfc_fifo_tuser ;
    wire [7:0]              m_axis_pfc_fifo_tready;

    wire [DATA_WIDTH-1:0]   s_axis_lfc_fifo_tdata ;
    wire [KEEP_WIDTH-1:0]   s_axis_lfc_fifo_tkeep ;
    wire                    s_axis_lfc_fifo_tvalid;
    wire                    s_axis_lfc_fifo_tlast ;
    wire                    s_axis_lfc_fifo_tuser ;
    wire                    s_axis_lfc_fifo_tready;

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_0_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_0_axis_tdata ),
        .s_axis_tkeep (s_priority_0_axis_tkeep ),
        .s_axis_tvalid(s_priority_0_axis_tvalid),
        .s_axis_tready(s_priority_0_axis_tready),
        .s_axis_tlast (s_priority_0_axis_tlast ),
        .s_axis_tuser (s_priority_0_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [0*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [0*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[0]),
        .m_axis_tready(m_axis_pfc_fifo_tready[0]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [0]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [0]),
        // pause 
        .pause_req(pause_req[0]),
        .pause_ack(pause_ack[0])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_1_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_1_axis_tdata ),
        .s_axis_tkeep (s_priority_1_axis_tkeep ),
        .s_axis_tvalid(s_priority_1_axis_tvalid),
        .s_axis_tready(s_priority_1_axis_tready),
        .s_axis_tlast (s_priority_1_axis_tlast ),
        .s_axis_tuser (s_priority_1_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [1*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [1*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[1]),
        .m_axis_tready(m_axis_pfc_fifo_tready[1]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [1]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [1]),
        // pause 
        .pause_req(pause_req[1]),
        .pause_ack(pause_ack[1])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_2_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_2_axis_tdata ),
        .s_axis_tkeep (s_priority_2_axis_tkeep ),
        .s_axis_tvalid(s_priority_2_axis_tvalid),
        .s_axis_tready(s_priority_2_axis_tready),
        .s_axis_tlast (s_priority_2_axis_tlast ),
        .s_axis_tuser (s_priority_2_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [2*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [2*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[2]),
        .m_axis_tready(m_axis_pfc_fifo_tready[2]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [2]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [2]),
        // pause 
        .pause_req(pause_req[2]),
        .pause_ack(pause_ack[2])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_3_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_3_axis_tdata ),
        .s_axis_tkeep (s_priority_3_axis_tkeep ),
        .s_axis_tvalid(s_priority_3_axis_tvalid),
        .s_axis_tready(s_priority_3_axis_tready),
        .s_axis_tlast (s_priority_3_axis_tlast ),
        .s_axis_tuser (s_priority_3_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [3*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [3*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[3]),
        .m_axis_tready(m_axis_pfc_fifo_tready[3]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [3]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [3]),
        // pause 
        .pause_req(pause_req[3]),
        .pause_ack(pause_ack[3])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_4_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_4_axis_tdata ),
        .s_axis_tkeep (s_priority_4_axis_tkeep ),
        .s_axis_tvalid(s_priority_4_axis_tvalid),
        .s_axis_tready(s_priority_4_axis_tready),
        .s_axis_tlast (s_priority_4_axis_tlast ),
        .s_axis_tuser (s_priority_4_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [4*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [4*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[4]),
        .m_axis_tready(m_axis_pfc_fifo_tready[4]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [4]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [4]),
        // pause 
        .pause_req(pause_req[4]),
        .pause_ack(pause_ack[4])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_5_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_5_axis_tdata ),
        .s_axis_tkeep (s_priority_5_axis_tkeep ),
        .s_axis_tvalid(s_priority_5_axis_tvalid),
        .s_axis_tready(s_priority_5_axis_tready),
        .s_axis_tlast (s_priority_5_axis_tlast ),
        .s_axis_tuser (s_priority_5_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [5*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [5*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[5]),
        .m_axis_tready(m_axis_pfc_fifo_tready[5]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [5]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [5]),
        // pause 
        .pause_req(pause_req[5]),
        .pause_ack(pause_ack[5])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_6_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_6_axis_tdata ),
        .s_axis_tkeep (s_priority_6_axis_tkeep ),
        .s_axis_tvalid(s_priority_6_axis_tvalid),
        .s_axis_tready(s_priority_6_axis_tready),
        .s_axis_tlast (s_priority_6_axis_tlast ),
        .s_axis_tuser (s_priority_6_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [6*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [6*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[6]),
        .m_axis_tready(m_axis_pfc_fifo_tready[6]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [6]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [6]),
        // pause 
        .pause_req(pause_req[6]),
        .pause_ack(pause_ack[6])
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_7_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_7_axis_tdata ),
        .s_axis_tkeep (s_priority_7_axis_tkeep ),
        .s_axis_tvalid(s_priority_7_axis_tvalid),
        .s_axis_tready(s_priority_7_axis_tready),
        .s_axis_tlast (s_priority_7_axis_tlast ),
        .s_axis_tuser (s_priority_7_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_pfc_fifo_tdata [7*DATA_WIDTH+:DATA_WIDTH]),
        .m_axis_tkeep (m_axis_pfc_fifo_tkeep [7*KEEP_WIDTH+:KEEP_WIDTH]),
        .m_axis_tvalid(m_axis_pfc_fifo_tvalid[7]),
        .m_axis_tready(m_axis_pfc_fifo_tready[7]),
        .m_axis_tlast (m_axis_pfc_fifo_tlast [7]),
        .m_axis_tuser (m_axis_pfc_fifo_tuser [7]),
        // pause 
        .pause_req(pause_req[7]),
        .pause_ack(pause_ack[7])
    );


    axis_arb_mux #(
        .S_COUNT(8),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .ARB_TYPE_ROUND_ROBIN(1)
    ) axis_arb_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata (m_axis_pfc_fifo_tdata ),
        .s_axis_tkeep (m_axis_pfc_fifo_tkeep ),
        .s_axis_tvalid(m_axis_pfc_fifo_tvalid),
        .s_axis_tready(m_axis_pfc_fifo_tready),
        .s_axis_tlast (m_axis_pfc_fifo_tlast ),
        .s_axis_tuser (m_axis_pfc_fifo_tuser ),
        .s_axis_tid(0),
        .s_axis_tdest(0),

        .m_axis_tdata (s_axis_lfc_fifo_tdata),
        .m_axis_tkeep (s_axis_lfc_fifo_tkeep),
        .m_axis_tvalid(s_axis_lfc_fifo_tvalid),
        .m_axis_tready(s_axis_lfc_fifo_tready),
        .m_axis_tlast (s_axis_lfc_fifo_tlast),
        .m_axis_tuser (s_axis_lfc_fifo_tuser)
    );

    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_lfc_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_axis_lfc_fifo_tdata),
        .s_axis_tkeep (s_axis_lfc_fifo_tkeep),
        .s_axis_tvalid(s_axis_lfc_fifo_tvalid),
        .s_axis_tready(s_axis_lfc_fifo_tready),
        .s_axis_tlast (s_axis_lfc_fifo_tlast),
        .s_axis_tuser (s_axis_lfc_fifo_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .m_axis_tuser (m_axis_tuser),
        // pause 
        .pause_req(pause_req[8]),
        .pause_ack(pause_ack[8])
    );


endmodule