`resetall `timescale 1ns / 1ps `default_nettype none

module fake_mac #(
    parameter LOCAL_MAC_ADDRESS = 48'h02_00_00_00_00_00,
    parameter MAC_DATA_WIDTH     = 64,
    parameter MAC_KEEP_WIDTH     = MAC_DATA_WIDTH/8,
    parameter MAC_AXI_SEG_INPUT  = 0,
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
    parameter PFC_ENABLE = 0,
    parameter PFC_FIFO_ENABLE = 3'd0,
    parameter PAUSE_ENABLE = PFC_ENABLE
)(
    // 10G MAC
    input  wire                       clk_mac_sim,
    input  wire                       rst_mac_sim,
    // "Fake" MAC clock
    input  wire                       clk_mac,
    input  wire                       rst_mac,

    /*
     * AXIS input
     */
    input  wire [MAC_DATA_WIDTH-1:0]  tx_axis_tdata,
    input  wire [MAC_KEEP_WIDTH-1:0]  tx_axis_tkeep,
    input  wire                       tx_axis_tvalid,
    output wire                       tx_axis_tready,
    input  wire                       tx_axis_tlast,
    input  wire                       tx_axis_tuser,

    /*
     * AXIS output
     */
    output wire [MAC_DATA_WIDTH-1:0]  rx_axis_tdata,
    output wire [MAC_KEEP_WIDTH-1:0]  rx_axis_tkeep,
    output wire                       rx_axis_tvalid,
    input  wire                       rx_axis_tready,
    output wire                       rx_axis_tlast,
    output wire                       rx_axis_tuser,

    /*
     * AXI-SEG input
     */
    input  wire [128*8-1:0]           tx_axi_seg_tdata,
    input  wire                       tx_axi_seg_tvalid,
    output wire                       tx_axi_seg_tready,
    input  wire [7:0]                 tx_axi_seg_tuser_ena,
    input  wire [7:0]                 tx_axi_seg_tuser_sop,
    input  wire [7:0]                 tx_axi_seg_tuser_eop,
    input  wire [7:0]                 tx_axi_seg_tuser_err,
    input  wire [4*8-1:0]             tx_axi_seg_tuser_mty,

    /*
     * AXI-SEG output
     */
    output wire [128*8-1:0]           rx_axi_seg_tdata,
    output wire                       rx_axi_seg_tvalid,
    input  wire                       rx_axi_seg_tready,
    output wire [7:0]                 rx_axi_seg_tuser_ena,
    output wire [7:0]                 rx_axi_seg_tuser_sop,
    output wire [7:0]                 rx_axi_seg_tuser_eop,
    output wire [7:0]                 rx_axi_seg_tuser_err,
    output wire [4*8-1:0]             rx_axi_seg_tuser_mty,

    /*
     * XGMII interface
     */
    input  wire        xgmii_tx_clk,
    input  wire        xgmii_tx_rst,
    output wire [63:0] xgmii_txd,
    output wire [ 7:0] xgmii_txc,
    input  wire        xgmii_rx_clk,
    input  wire        xgmii_rx_rst,
    input  wire [63:0] xgmii_rxd,
    input  wire [ 7:0] xgmii_rxc,

    /*
    PAUSE
    */
    output wire [8:0] tx_pause_req,
    input  wire [8:0] tx_pause_ack,

    /*
     * Configuration
     */
    input  wire [7:0]                 cfg_ifg,
    input  wire [3:0]                 ctrl_priority_tag,
    input  wire                       cfg_tx_enable,
    input  wire                       cfg_rx_enable
);

    initial begin
        if (MAC_AXI_SEG_INPUT && MAC_DATA_WIDTH != 1024) begin
            $error("Error: AXI-SEG input is available only for 1024 datapath (instance %m)");
            $finish;
        end
    end

    wire [MAC_DATA_WIDTH-1:0]  rx_generic_axis_tdata;
    wire [MAC_KEEP_WIDTH-1:0]  rx_generic_axis_tkeep;
    wire                       rx_generic_axis_tvalid;
    wire                       rx_generic_axis_tready;
    wire                       rx_generic_axis_tlast;
    wire                       rx_generic_axis_tuser;

    wire [63:0]                rx_mac_axis_tdata;
    wire [7 :0]                rx_mac_axis_tkeep;
    wire                       rx_mac_axis_tvalid;
    wire                       rx_mac_axis_tready;
    wire                       rx_mac_axis_tlast;
    wire                       rx_mac_axis_tuser;

    wire [128*8-1:0]           tx_axi_seg_fifo_tdata;
    wire                       tx_axi_seg_fifo_tvalid;
    wire                       tx_axi_seg_fifo_tready;
    wire [7:0]                 tx_axi_seg_fifo_tuser_ena;
    wire [7:0]                 tx_axi_seg_fifo_tuser_sop;
    wire [7:0]                 tx_axi_seg_fifo_tuser_eop;
    wire [7:0]                 tx_axi_seg_fifo_tuser_err;
    wire [4*8-1:0]             tx_axi_seg_fifo_tuser_mty;

    wire [128*8-1:0]           rx_axi_seg_fifo_tdata;
    wire                       rx_axi_seg_fifo_tvalid;
    wire                       rx_axi_seg_fifo_tready;
    wire [7:0]                 rx_axi_seg_fifo_tuser_ena;
    wire [7:0]                 rx_axi_seg_fifo_tuser_sop;
    wire [7:0]                 rx_axi_seg_fifo_tuser_eop;
    wire [7:0]                 rx_axi_seg_fifo_tuser_err;
    wire [4*8-1:0]             rx_axi_seg_fifo_tuser_mty;



    wire [MAC_DATA_WIDTH-1:0]  tx_generic_axis_tdata;
    wire [MAC_KEEP_WIDTH-1:0]  tx_generic_axis_tkeep;
    wire                       tx_generic_axis_tvalid;
    wire                       tx_generic_axis_tready;
    wire                       tx_generic_axis_tlast;
    wire                       tx_generic_axis_tuser;

    wire [MAC_DATA_WIDTH-1:0]  tx_generic_0_axis_tdata;
    wire [MAC_KEEP_WIDTH-1:0]  tx_generic_0_axis_tkeep;
    wire                       tx_generic_0_axis_tvalid;
    wire                       tx_generic_0_axis_tready;
    wire                       tx_generic_0_axis_tlast;
    wire                       tx_generic_0_axis_tuser;

    wire [MAC_DATA_WIDTH-1:0]  tx_generic_1_axis_tdata;
    wire [MAC_KEEP_WIDTH-1:0]  tx_generic_1_axis_tkeep;
    wire                       tx_generic_1_axis_tvalid;
    wire                       tx_generic_1_axis_tready;
    wire                       tx_generic_1_axis_tlast;
    wire                       tx_generic_1_axis_tuser;

    wire [63:0]                tx_mac_axis_tdata;
    wire [7 :0]                tx_mac_axis_tkeep;
    wire                       tx_mac_axis_tvalid;
    wire                       tx_mac_axis_tready;
    wire                       tx_mac_axis_tlast;
    wire                       tx_mac_axis_tuser;

    generate
        if (MAC_AXI_SEG_INPUT) begin

            // TX AXI-SEG to AXIS conversion
            // First an async fifo
            axis_fifo #(
                .DEPTH(4200),
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(0),
                .ID_ENABLE(0),
                .LAST_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(64)
            ) axi_seg_tx_fifo_inst (
                .clk(clk_mac),
                .rst(rst_mac),

                .s_axis_tdata (tx_axi_seg_tdata),
                .s_axis_tkeep (0),
                .s_axis_tvalid(tx_axi_seg_tvalid),
                .s_axis_tready(tx_axi_seg_tready),
                .s_axis_tlast (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser ({tx_axi_seg_tuser_ena, tx_axi_seg_tuser_sop, tx_axi_seg_tuser_eop, tx_axi_seg_tuser_err, tx_axi_seg_tuser_mty}),

                // AXI output
                .m_axis_tdata (tx_axi_seg_fifo_tdata),
                .m_axis_tkeep (),
                .m_axis_tvalid(tx_axi_seg_fifo_tvalid),
                .m_axis_tready(tx_axi_seg_fifo_tready),
                .m_axis_tlast (),
                .m_axis_tid   (),
                .m_axis_tdest (),
                .m_axis_tuser ({tx_axi_seg_fifo_tuser_ena, tx_axi_seg_fifo_tuser_sop, tx_axi_seg_fifo_tuser_eop, tx_axi_seg_fifo_tuser_err, tx_axi_seg_fifo_tuser_mty})
            );

            // Then the actual conversion
            
            axi_seg_2_axis #(
                .AXIS_FIFO_DEPTH(8192),
                .ASYNC_FIFO(0)
            ) axi_seg_2_axis_instance (
                .s_clk(clk_mac),
                .s_rst(rst_mac),

                .s_axis_seg_tdata    (tx_axi_seg_fifo_tdata),
                .s_axis_seg_tvalid   (tx_axi_seg_fifo_tvalid),
                .s_axis_seg_tready   (tx_axi_seg_fifo_tready),
                .s_axis_seg_tuser_ena(tx_axi_seg_fifo_tuser_ena),
                .s_axis_seg_tuser_sop(tx_axi_seg_fifo_tuser_sop),
                .s_axis_seg_tuser_eop(tx_axi_seg_fifo_tuser_eop),
                .s_axis_seg_tuser_err(tx_axi_seg_fifo_tuser_err),
                .s_axis_seg_tuser_mty(tx_axi_seg_fifo_tuser_mty),

                .m_clk(clk_mac),
                .m_rst(rst_mac),

                .m_axis_tdata (tx_generic_axis_tdata),
                .m_axis_tkeep (tx_generic_axis_tkeep),
                .m_axis_tvalid(tx_generic_axis_tvalid),
                .m_axis_tready(tx_generic_axis_tready),
                .m_axis_tlast (tx_generic_axis_tlast),
                .m_axis_tuser (tx_generic_axis_tuser)
            );
            
            // RX AXIS to AXI-SEG conversion
            axis_2_axi_seg #(
            ) axis_2_axi_seg_instance (
                .clk(clk_mac),
                .rst(rst_mac),

                .s_axis_tdata (rx_generic_axis_tdata),
                .s_axis_tkeep (rx_generic_axis_tkeep),
                .s_axis_tvalid(rx_generic_axis_tvalid),
                .s_axis_tready(rx_generic_axis_tready),
                .s_axis_tlast (rx_generic_axis_tlast),
                .s_axis_tuser (rx_generic_axis_tuser),

                .m_axis_seg_tdata    (rx_axi_seg_fifo_tdata),
                .m_axis_seg_tvalid   (rx_axi_seg_fifo_tvalid),
                .m_axis_seg_tready   (rx_axi_seg_fifo_tready),
                .m_axis_seg_tuser_ena(rx_axi_seg_fifo_tuser_ena),
                .m_axis_seg_tuser_sop(rx_axi_seg_fifo_tuser_sop),
                .m_axis_seg_tuser_eop(rx_axi_seg_fifo_tuser_eop),
                .m_axis_seg_tuser_err(rx_axi_seg_fifo_tuser_err),
                .m_axis_seg_tuser_mty(rx_axi_seg_fifo_tuser_mty)
            );

            // First an async fifo
            axis_fifo #(
                .DEPTH(4200),
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(0),
                .ID_ENABLE(0),
                .LAST_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(64)
            ) axi_seg_rx_async_fifo_inst (
                .clk(clk_mac),
                .rst(rst_mac),

                .s_axis_tdata (rx_axi_seg_fifo_tdata),
                .s_axis_tkeep (0),
                .s_axis_tvalid(rx_axi_seg_fifo_tvalid),
                .s_axis_tready(rx_axi_seg_fifo_tready),
                .s_axis_tlast (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser ({rx_axi_seg_fifo_tuser_ena, rx_axi_seg_fifo_tuser_sop, rx_axi_seg_fifo_tuser_eop, rx_axi_seg_fifo_tuser_err, rx_axi_seg_fifo_tuser_mty}),

                .m_axis_tdata (rx_axi_seg_tdata),
                .m_axis_tkeep (),
                .m_axis_tvalid(rx_axi_seg_tvalid),
                .m_axis_tready(rx_axi_seg_tready),
                .m_axis_tlast (),
                .m_axis_tid   (),
                .m_axis_tdest (),
                .m_axis_tuser ({rx_axi_seg_tuser_ena, rx_axi_seg_tuser_sop, rx_axi_seg_tuser_eop, rx_axi_seg_tuser_err, rx_axi_seg_tuser_mty})
            );

            assign rx_axis_tvalid = 1'b0;

        end else begin // bypass axiseg conversion

            assign tx_generic_axis_tdata  = tx_axis_tdata;
            assign tx_generic_axis_tkeep  = tx_axis_tkeep;
            assign tx_generic_axis_tvalid = tx_axis_tvalid;
            assign tx_axis_tready         = tx_generic_axis_tready;
            assign tx_generic_axis_tlast  = tx_axis_tlast;
            assign tx_generic_axis_tuser  = tx_axis_tuser;

            assign tx_axi_seg_tready = 1'b1;

            assign rx_axis_tdata          = rx_generic_axis_tdata ;
            assign rx_axis_tkeep          = rx_generic_axis_tkeep ;
            assign rx_axis_tvalid         = rx_generic_axis_tvalid;
            assign rx_generic_axis_tready = rx_axis_tready        ;
            assign rx_axis_tlast          = rx_generic_axis_tlast ;
            assign rx_axis_tuser          = rx_generic_axis_tuser ;

            assign rx_axi_seg_tvalid = 1'b0;

        end
    endgenerate

    axis_async_fifo_adapter #(
        .DEPTH(4200),
        .S_DATA_WIDTH(MAC_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(MAC_KEEP_WIDTH),
        .M_DATA_WIDTH(64),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) tx_axis_fifo (
        .s_clk(clk_mac),
        .s_rst(rst_mac),

        .s_axis_tdata (tx_generic_axis_tdata),
        .s_axis_tkeep (tx_generic_axis_tkeep),
        .s_axis_tvalid(tx_generic_axis_tvalid),
        .s_axis_tready(tx_generic_axis_tready),
        .s_axis_tlast (tx_generic_axis_tlast),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(tx_generic_axis_tuser),



        .m_clk(clk_mac_sim),
        .m_rst(rst_mac_sim),

        // AXI output
        .m_axis_tdata (tx_mac_axis_tdata),
        .m_axis_tkeep (tx_mac_axis_tkeep),
        .m_axis_tvalid(tx_mac_axis_tvalid),
        .m_axis_tready(tx_mac_axis_tready),
        .m_axis_tlast (tx_mac_axis_tlast),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser (tx_mac_axis_tuser)
    );



    axis_async_fifo_adapter #(
        .DEPTH(4200),
        .S_DATA_WIDTH(64),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(8),
        .M_DATA_WIDTH(MAC_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(MAC_KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) rx_axis_fifo (
        .s_clk(clk_mac_sim),
        .s_rst(rst_mac_sim),

        // AXI input
        .s_axis_tdata (rx_mac_axis_tdata),
        .s_axis_tkeep (rx_mac_axis_tkeep),
        .s_axis_tvalid(rx_mac_axis_tvalid),
        .s_axis_tready(rx_mac_axis_tready),
        .s_axis_tlast (rx_mac_axis_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (rx_mac_axis_tuser),

        .m_clk(clk_mac),
        .m_rst(rst_mac),

        // AXI output
        .m_axis_tdata (rx_generic_axis_tdata),
        .m_axis_tkeep (rx_generic_axis_tkeep),
        .m_axis_tvalid(rx_generic_axis_tvalid),
        .m_axis_tready(rx_generic_axis_tready),
        .m_axis_tlast (rx_generic_axis_tlast),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser (rx_generic_axis_tuser)
    );

    eth_mac_10g_fifo #(
        .LOCAL_MAC_ADDRESS(LOCAL_MAC_ADDRESS),
        .DATA_WIDTH(64),
        .CTRL_WIDTH(8),
        .AXIS_DATA_WIDTH(64),
        .AXIS_KEEP_WIDTH(8),
        .ENABLE_PADDING(ENABLE_PADDING),
        .ENABLE_DIC(ENABLE_DIC),
        .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
        .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
        .TX_FIFO_RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
        .TX_FRAME_FIFO(TX_FRAME_FIFO),
        .TX_DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
        .TX_DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
        .TX_DROP_WHEN_FULL(TX_DROP_WHEN_FULL),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .RX_FIFO_RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
        .RX_FRAME_FIFO(RX_FRAME_FIFO),
        .RX_DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
        .RX_DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
        .RX_DROP_WHEN_FULL(RX_DROP_WHEN_FULL),
        .PFC_ENABLE(PFC_ENABLE),
        .PAUSE_ENABLE(PAUSE_ENABLE)
    ) eth_mac_10g_fifo_inst (
        .rx_clk(xgmii_rx_clk),
        .rx_rst(xgmii_rx_rst),
        .tx_clk(xgmii_tx_clk),
        .tx_rst(xgmii_tx_rst),
        .logic_clk(clk_mac_sim),
        .logic_rst(rst_mac_sim),

        .tx_axis_tdata (tx_mac_axis_tdata),
        .tx_axis_tkeep (tx_mac_axis_tkeep),
        .tx_axis_tvalid(tx_mac_axis_tvalid),
        .tx_axis_tready(tx_mac_axis_tready),
        .tx_axis_tlast (tx_mac_axis_tlast),
        .tx_axis_tuser (tx_mac_axis_tuser),

        .rx_axis_tdata (rx_mac_axis_tdata),
        .rx_axis_tkeep (rx_mac_axis_tkeep),
        .rx_axis_tvalid(rx_mac_axis_tvalid),
        .rx_axis_tready(rx_mac_axis_tready),
        .rx_axis_tlast (rx_mac_axis_tlast),
        .rx_axis_tuser (rx_mac_axis_tuser),

        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),

        .tx_fifo_overflow  (),
        .tx_fifo_bad_frame (),
        .tx_fifo_good_frame(),
        .rx_error_bad_frame(),
        .rx_error_bad_fcs  (),
        .rx_fifo_overflow  (),
        .rx_fifo_bad_frame (),
        .rx_fifo_good_frame(),

        .tx_lfc_en (1'b0),
        .tx_lfc_req(),
        .tx_pfc_en (8'h0),
        .tx_pfc_req(),

        .rx_lfc_en (1'b1),
        .rx_lfc_req(tx_pause_req[8]),
        //.rx_lfc_ack(qsfp_rx_lfc_ack), handled internally
        .rx_pfc_en (8'hFF),
        .rx_pfc_req(tx_pause_req[7:0]),
        .rx_pfc_ack(tx_pause_ack[7:0]),

        .cfg_ifg(cfg_ifg),
        .cfg_tx_enable(cfg_tx_enable),
        .cfg_rx_enable(cfg_rx_enable)
    );


endmodule