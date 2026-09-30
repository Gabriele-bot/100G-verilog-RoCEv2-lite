`resetall `timescale 1ns / 1ps `default_nettype none

module top #(
    parameter real MAC_PERIOD      = 3.33,
    parameter real STACK_PERIOD    = 3.33,
    parameter real ROCE_ENG_PERIOD = 3.33,
    parameter MAC_DATA_WIDTH       = 64,
    parameter STACK_DATA_WIDTH     = 64,
    parameter ROCE_ENG_DATA_WIDTH  = STACK_DATA_WIDTH,
    parameter QP_CH_DATA_WIDTH     = ROCE_ENG_DATA_WIDTH,
    parameter N_ROCE_TX_ENGINES    = 1,
    parameter N_QUEUE_PAIRS        = 2,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 23,
    parameter MAC_AXI_SEG_INPUT  = 0
)(
    input wire clk_mac_sim,
    input wire clk_mac,
    input wire clk_stack,
    input wire clk_roce_eng,
    input wire rst,

    input wire clk_mem,
    input wire rst_mem,

    /*
     * Ethernet: QSFP28
     */
    input  wire        xgmii_tx_clk,
    input  wire        xgmii_tx_rst,
    output wire [63:0] xgmii_txd,
    output wire [ 7:0] xgmii_txc,
    input  wire        xgmii_rx_clk,
    input  wire        xgmii_rx_rst,
    input  wire [63:0] xgmii_rxd,
    input  wire [ 7:0] xgmii_rxc
);

    parameter DATA_WIDTH = MAC_DATA_WIDTH;
    parameter KEEP_WIDTH = DATA_WIDTH/8;

    initial begin
        if (DATA_WIDTH % 64 != 0) begin
            $error("Error: DATA_WIDTH must be mutiple of 64 (instance %m)");
            $finish;
        end
    end


    wire [ DATA_WIDTH-1   :0]                                  rx_axis_tdata;
    wire [ DATA_WIDTH/8-1 :0]                                  rx_axis_tkeep;
    wire                                                       rx_axis_tvalid;
    wire                                                       rx_axis_tready;
    wire                                                       rx_axis_tlast;
    wire                                                       rx_axis_tuser;

    wire [ DATA_WIDTH-1   :0]                                  tx_axis_tdata;
    wire [ DATA_WIDTH/8-1 :0]                                  tx_axis_tkeep;
    wire                                                       tx_axis_tvalid;
    wire                                                       tx_axis_tready;
    wire                                                       tx_axis_tlast;
    wire                                                       tx_axis_tuser;

    wire [STACK_DATA_WIDTH-1:0]                                rx_generic_axis_tdata;
    wire [STACK_DATA_WIDTH/8-1:0]                              rx_generic_axis_tkeep;
    wire                                                       rx_generic_axis_tvalid;
    wire                                                       rx_generic_axis_tready;
    wire                                                       rx_generic_axis_tlast;
    wire                                                       rx_generic_axis_tuser;

    wire [STACK_DATA_WIDTH-1:0]                                tx_generic_axis_tdata;
    wire [STACK_DATA_WIDTH/8-1:0]                              tx_generic_axis_tkeep;
    wire                                                       tx_generic_axis_tvalid;
    wire                                                       tx_generic_axis_tready;
    wire                                                       tx_generic_axis_tlast;
    wire                                                       tx_generic_axis_tuser;

    wire [STACK_DATA_WIDTH-1:0]                                tx_generic_axis_dropper_tdata;
    wire [STACK_DATA_WIDTH/8-1:0]                              tx_generic_axis_dropper_tkeep;
    wire                                                       tx_generic_axis_dropper_tvalid;
    wire                                                       tx_generic_axis_dropper_tready;
    wire                                                       tx_generic_axis_dropper_tlast;
    wire                                                       tx_generic_axis_dropper_tuser;

    wire [STACK_DATA_WIDTH-1:0]                                tx_generic_pad_axis_tdata;
    wire [STACK_DATA_WIDTH/8-1:0]                              tx_generic_pad_axis_tkeep;
    wire                                                       tx_generic_pad_axis_tvalid;
    wire                                                       tx_generic_pad_axis_tready;
    wire                                                       tx_generic_pad_axis_tlast;
    wire                                                       tx_generic_pad_axis_tuser;

    wire [0                :0]                                            m_axi_roce_buffer_awid    [N_ROCE_TX_ENGINES-1:0];
    wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)-1:0] m_axi_roce_buffer_awaddr  [N_ROCE_TX_ENGINES-1:0];
    wire [7:0]                                                            m_axi_roce_buffer_awlen   [N_ROCE_TX_ENGINES-1:0];
    wire [2:0]                                                            m_axi_roce_buffer_awsize  [N_ROCE_TX_ENGINES-1:0];
    wire [1:0]                                                            m_axi_roce_buffer_awburst [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_awlock  [N_ROCE_TX_ENGINES-1:0];
    wire [3:0]                                                            m_axi_roce_buffer_awcache [N_ROCE_TX_ENGINES-1:0];
    wire [2:0]                                                            m_axi_roce_buffer_awprot  [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_awvalid [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_awready [N_ROCE_TX_ENGINES-1:0];
    wire [ROCE_ENG_DATA_WIDTH - 1 : 0]                                    m_axi_roce_buffer_wdata   [N_ROCE_TX_ENGINES-1:0];
    wire [ROCE_ENG_DATA_WIDTH/8 - 1 : 0]                                  m_axi_roce_buffer_wstrb   [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_wlast   [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_wvalid  [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_wready  [N_ROCE_TX_ENGINES-1:0];
    wire [0:0]                                                            m_axi_roce_buffer_bid     [N_ROCE_TX_ENGINES-1:0];
    wire [1:0]                                                            m_axi_roce_buffer_bresp   [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_bvalid  [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_bready  [N_ROCE_TX_ENGINES-1:0];
    wire [0               :0]                                             m_axi_roce_buffer_arid    [N_ROCE_TX_ENGINES-1:0];
    wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)-1:0] m_axi_roce_buffer_araddr  [N_ROCE_TX_ENGINES-1:0];
    wire [7:0]                                                            m_axi_roce_buffer_arlen   [N_ROCE_TX_ENGINES-1:0];
    wire [2:0]                                                            m_axi_roce_buffer_arsize  [N_ROCE_TX_ENGINES-1:0];
    wire [1:0]                                                            m_axi_roce_buffer_arburst [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_arlock  [N_ROCE_TX_ENGINES-1:0];
    wire [3:0]                                                            m_axi_roce_buffer_arcache [N_ROCE_TX_ENGINES-1:0];
    wire [2:0]                                                            m_axi_roce_buffer_arprot  [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_arvalid [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_arready [N_ROCE_TX_ENGINES-1:0];
    wire [0             :0]                                               m_axi_roce_buffer_rid     [N_ROCE_TX_ENGINES-1:0];
    wire [ROCE_ENG_DATA_WIDTH  -1:0]                                      m_axi_roce_buffer_rdata   [N_ROCE_TX_ENGINES-1:0];
    wire [1:0]                                                            m_axi_roce_buffer_rresp   [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_rlast   [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_rvalid  [N_ROCE_TX_ENGINES-1:0];
    wire                                                                  m_axi_roce_buffer_rready  [N_ROCE_TX_ENGINES-1:0];

    wire [8:0] tx_pause_req, tx_pause_ack;

    reg [8:0] tx_pause_req_network;
    reg [8:0] tx_pause_ack_network;
    reg [8:0] tx_pause_ack_reg;

    
    typedef struct packed {
        logic [2:0]               id;
        logic [11:0]              ena;
        logic [11:0]              sop;
        logic [11:0]              eop;
        logic [11:0]              err;
        logic [11:0][3:0]         mty;
        logic [11:0][127:0]       dat;
    } axi_seg_pkt_t;

    axi_seg_pkt_t    tx_axi_seg_pkt, rx_axi_seg_pkt;
    axi_seg_pkt_t    tx_axi_seg_pkt_fifo;
    wire tx_axi_seg_tvalid, tx_axi_seg_tready;
    wire tx_axi_seg_fifo_tvalid, tx_axi_seg_fifo_tready;
    wire rx_axi_seg_tvalid, rx_axi_seg_tready;

    network_wrapper_roce_generic #(
        .STACK_DATA_WIDTH   (STACK_DATA_WIDTH),
        .ROCE_ENG_DATA_WIDTH(ROCE_ENG_DATA_WIDTH),
        .QP_CH_DATA_WIDTH   (QP_CH_DATA_WIDTH),
        .N_ROCE_TX_ENGINES  (N_ROCE_TX_ENGINES),
        .N_QUEUE_PAIRS      (N_QUEUE_PAIRS),
        .RETRANSMISSION_ADDR_BUFFER_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
        .STACK_CLK_PERIOD   (STACK_PERIOD   ),
        .ROCE_ENG_CLK_PERIOD(ROCE_ENG_PERIOD), // in ns, to set the timer values scale for the RoCE engine logic. This does not affect the actual clock frequency which is determined by clk_aux_0
        .TARGET_SPEED(98.00),
        .RX_FIFO_REGS(2),
        .TX_FIFO_REGS(2),
        .ENABLE_PFC(1),
        .DEBUG(1)
    ) network_wrapper_roce_generic_instance (
        .clk_stack(clk_stack),
        .rst_stack(rst),
        .clk_roce_eng(clk_roce_eng),
        .rst_roce_eng(rst),
        .flow_ctrl_pause         (tx_pause_req_network[3] || tx_pause_req_network[8]),

        // AXIS inputs
        .s_wr_req_valid           ('{default:{1'b0}}),
        .s_wr_req_ready           (),
        .s_wr_req_tx_type         ('{default:{1'b0}}),
        .s_wr_req_is_immediate    ('{default:{1'b0}}),
        .s_wr_req_immediate_data  ('{default:{32'd0}}),
        .s_wr_req_loc_qp          ('{default:{24'd256}}),
        .s_wr_req_addr_offset     ('{default:{64'd0}}),
        .s_wr_req_dma_length      ('{default:{32'd0}}),
        .s_axis_tdata             ('{default:{512'd0}}),
        .s_axis_tkeep             ('{default:{64'd0}}),
        .s_axis_tvalid            ('{default:{1'b0}}),
        .s_axis_tready            (),
        .s_axis_tlast             ('{default:{1'b0}}),
        .s_axis_tuser             ('{default:{1'b0}}),

        .m_network_tx_axis_tdata (tx_generic_axis_tdata),
        .m_network_tx_axis_tkeep (tx_generic_axis_tkeep),
        .m_network_tx_axis_tvalid(tx_generic_axis_tvalid),
        .m_network_tx_axis_tready(tx_generic_axis_tready),
        .m_network_tx_axis_tlast (tx_generic_axis_tlast),
        .m_network_tx_axis_tuser (tx_generic_axis_tuser),

        .s_network_rx_axis_tdata (rx_generic_axis_tdata),
        .s_network_rx_axis_tkeep (rx_generic_axis_tkeep),
        .s_network_rx_axis_tvalid(rx_generic_axis_tvalid),
        .s_network_rx_axis_tready(rx_generic_axis_tready),
        .s_network_rx_axis_tlast (rx_generic_axis_tlast),
        .s_network_rx_axis_tuser (rx_generic_axis_tuser),

        // AXI master interface to RoCE buffers, 1 per RoCE engine
        .m_axi_awid   (m_axi_roce_buffer_awid),
        .m_axi_awaddr (m_axi_roce_buffer_awaddr),
        .m_axi_awlen  (m_axi_roce_buffer_awlen),
        .m_axi_awsize (m_axi_roce_buffer_awsize),
        .m_axi_awburst(m_axi_roce_buffer_awburst),
        .m_axi_awlock (m_axi_roce_buffer_awlock),
        .m_axi_awcache(m_axi_roce_buffer_awcache),
        .m_axi_awprot (m_axi_roce_buffer_awprot),
        .m_axi_awvalid(m_axi_roce_buffer_awvalid),
        .m_axi_awready(m_axi_roce_buffer_awready),
        .m_axi_wdata  (m_axi_roce_buffer_wdata),
        .m_axi_wstrb  (m_axi_roce_buffer_wstrb),
        .m_axi_wlast  (m_axi_roce_buffer_wlast),
        .m_axi_wvalid (m_axi_roce_buffer_wvalid),
        .m_axi_wready (m_axi_roce_buffer_wready),
        .m_axi_bid    (m_axi_roce_buffer_bid),
        .m_axi_bresp  (m_axi_roce_buffer_bresp),
        .m_axi_bvalid (m_axi_roce_buffer_bvalid),
        .m_axi_bready (m_axi_roce_buffer_bready),
        .m_axi_arid   (m_axi_roce_buffer_arid),
        .m_axi_araddr (m_axi_roce_buffer_araddr),
        .m_axi_arlen  (m_axi_roce_buffer_arlen),
        .m_axi_arsize (m_axi_roce_buffer_arsize),
        .m_axi_arburst(m_axi_roce_buffer_arburst),
        .m_axi_arlock (m_axi_roce_buffer_arlock),
        .m_axi_arcache(m_axi_roce_buffer_arcache),
        .m_axi_arprot (m_axi_roce_buffer_arprot),
        .m_axi_arvalid(m_axi_roce_buffer_arvalid),
        .m_axi_arready(m_axi_roce_buffer_arready),
        .m_axi_rid    (m_axi_roce_buffer_rid),
        .m_axi_rdata  (m_axi_roce_buffer_rdata),
        .m_axi_rresp  (m_axi_roce_buffer_rresp),
        .m_axi_rlast  (m_axi_roce_buffer_rlast),
        .m_axi_rvalid (m_axi_roce_buffer_rvalid),
        .m_axi_rready (m_axi_roce_buffer_rready),
        // cfg signals (clk_stack domain)
        .ctrl_local_mac_address(48'h00_0A_35_DE_AD_01       ),
        .ctrl_local_ip         ({8'd22, 8'd1, 8'd212, 8'd10}),
        .ctrl_clear_arp_cache  (1'b0                        ),
        .ctrl_pmtu             (4'd4                        ),
        .ctrl_RoCE_udp_port    (16'h12B7                    ),
        .ctrl_priority_tag     (3'd3                        ),
        .ctrl_retry_timeout    (32'd10000                   ),
        .ctrl_use_data_gen     (32'hFFFFFFFF                ),
        // dcqcn
        .ctrl_dcqcn_en            (1'b0),
        .ctrl_dcqcn_par_g         (10'h4),
        .ctrl_dcqcn_alpha_min     (10'h2),
        .ctrl_dcqcn_alpha_upd_time(32'd10000),
        .ctrl_dcqcn_rate_decr_min (10'h100),
        .ctrl_dcqcn_rate_min      (11'h10),
        .ctrl_dcqcn_upd_time      (32'd5000),
        .ctrl_dcqcn_rate_ai_time  (32'd10000),
        .ctrl_dcqcn_rate_hai_time (32'd30000),
        .ctrl_dcqcn_rate_incr_ai  (10'h10),
        .ctrl_dcqcn_rate_incr_hai (10'h20),
        // perf monitor (clk_stack domain)
        .perf_cfg_latency_avg_po2      (5), // avg over 32 values
        .perf_cfg_throughput_avg_po2   (5), // avg over 32 values
        .perf_monitor_loc_qpn          (24'd256),
        .perf_transfer_time_avg        (),
        .perf_transfer_time_moving_avg (),
        .perf_latency_max              (),
        .perf_latency_avg              (),
        .perf_latency_moving_avg       (),
        .perf_psn_diff                 (),
        .perf_psn_diff_max             (),
        .perf_n_retransmit_triggers    (),
        .perf_n_rnr_retransmit_triggers(),
        .perf_n_total_psn_seq_errors   (),
        .perf_n_total_timeout_errors   (),
        // perf latency monitor (roce_stack domain)
        .perf_lat_histo_reset_counts(1'b0),
        .perf_lat_histo_trgg_readout(1'b0),
        .perf_lat_histo_index       (),
        .perf_lat_histo_valid       (),
        .perf_lat_histo_counts      (),
        .perf_lat_histo_rst_done    (),
        .perf_lat_histo_ovflw       (),

        .perf_adj_ack_histo_reset_counts(1'b0),
        .perf_adj_ack_histo_trgg_readout(1'b0),
        .perf_adj_ack_histo_index       (),
        .perf_adj_ack_histo_valid       (),
        .perf_adj_ack_histo_counts      (),
        .perf_adj_ack_histo_rst_done    (),
        .perf_adj_ack_histo_ovflw       (),

        .pfc_pause_req(tx_pause_req_network[7:0]),
        .pfc_pause_ack(tx_pause_ack_network[7:0])
    );

    /* 
    axis_packet_dropper #(
        .DATA_WIDTH(DATA_WIDTH),
        .TUSER_WIDTH(1),
        .DROP_PROB_PERCENT(0.0000)
    ) axis_packet_dropper_instance (
        .clk(clk_stack),
        .rst(rst),

        .s_axis_tdata (tx_generic_axis_tdata),
        .s_axis_tkeep (tx_generic_axis_tkeep),
        .s_axis_tvalid(tx_generic_axis_tvalid),
        .s_axis_tready(tx_generic_axis_tready),
        .s_axis_tlast (tx_generic_axis_tlast),
        .s_axis_tuser (tx_generic_axis_tuser),

        .m_axis_tdata (tx_generic_axis_dropper_tdata),
        .m_axis_tkeep (tx_generic_axis_dropper_tkeep),
        .m_axis_tvalid(tx_generic_axis_dropper_tvalid),
        .m_axis_tready(tx_generic_axis_dropper_tready),
        .m_axis_tlast (tx_generic_axis_dropper_tlast),
        .m_axis_tuser (tx_generic_axis_dropper_tuser)
    );
    */
    assign tx_generic_axis_dropper_tdata  = tx_generic_axis_tdata;
    assign tx_generic_axis_dropper_tkeep  = tx_generic_axis_tkeep;
    assign tx_generic_axis_dropper_tvalid = tx_generic_axis_tvalid;
    assign tx_generic_axis_tready         = tx_generic_axis_dropper_tready;
    assign tx_generic_axis_dropper_tlast  = tx_generic_axis_tlast;
    assign tx_generic_axis_dropper_tuser  = tx_generic_axis_tuser;

    generate
        genvar i;
        for (i = 0; i < N_ROCE_TX_ENGINES; i = i + 1) begin
            axi_ram_xpm #(
                .DATA_WIDTH(ROCE_ENG_DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)),
                .STRB_WIDTH(ROCE_ENG_DATA_WIDTH/8),
                .ID_WIDTH(1),
                .READ_LATENCY(8),
                .RAM_STYLE("ultra")
            ) RoCE_axi_buffer_instance (
                .clk(clk_roce_eng),
                .rst(rst),

                .s_axi_awid   (m_axi_roce_buffer_awid[i]),
                .s_axi_awaddr (m_axi_roce_buffer_awaddr[i]),
                .s_axi_awlen  (m_axi_roce_buffer_awlen[i]),
                .s_axi_awsize (m_axi_roce_buffer_awsize[i]),
                .s_axi_awburst(m_axi_roce_buffer_awburst[i]),
                .s_axi_awlock (m_axi_roce_buffer_awlock[i]),
                .s_axi_awcache(m_axi_roce_buffer_awcache[i]),
                .s_axi_awprot (m_axi_roce_buffer_awprot[i]),
                .s_axi_awvalid(m_axi_roce_buffer_awvalid[i]),
                .s_axi_awready(m_axi_roce_buffer_awready[i]),

                .s_axi_wdata  (m_axi_roce_buffer_wdata[i]),
                .s_axi_wstrb  (m_axi_roce_buffer_wstrb[i]),
                .s_axi_wlast  (m_axi_roce_buffer_wlast[i]),
                .s_axi_wvalid (m_axi_roce_buffer_wvalid[i]),
                .s_axi_wready (m_axi_roce_buffer_wready[i]),

                .s_axi_bid    (m_axi_roce_buffer_bid[i]),
                .s_axi_bresp  (m_axi_roce_buffer_bresp[i]),
                .s_axi_bvalid (m_axi_roce_buffer_bvalid[i]),
                .s_axi_bready (m_axi_roce_buffer_bready[i]),

                .s_axi_arid   (m_axi_roce_buffer_arid[i]),
                .s_axi_araddr (m_axi_roce_buffer_araddr[i]),
                .s_axi_arlen  (m_axi_roce_buffer_arlen[i]),
                .s_axi_arsize (m_axi_roce_buffer_arsize[i]),
                .s_axi_arburst(m_axi_roce_buffer_arburst[i]),
                .s_axi_arlock (m_axi_roce_buffer_arlock[i]),
                .s_axi_arcache(m_axi_roce_buffer_arcache[i]),
                .s_axi_arprot (m_axi_roce_buffer_arprot[i]),
                .s_axi_arvalid(m_axi_roce_buffer_arvalid[i]),
                .s_axi_arready(m_axi_roce_buffer_arready[i]),

                .s_axi_rid    (m_axi_roce_buffer_rid[i]),
                .s_axi_rdata  (m_axi_roce_buffer_rdata[i]),
                .s_axi_rresp  (m_axi_roce_buffer_rresp[i]),
                .s_axi_rlast  (m_axi_roce_buffer_rlast[i]),
                .s_axi_rvalid (m_axi_roce_buffer_rvalid[i]),
                .s_axi_rready (m_axi_roce_buffer_rready[i])
            );
        end
        if (MAC_AXI_SEG_INPUT) begin
            // TX AXIS to AXI-SEG conversion
            dcmac_pad #(
                .USER_WIDTH(1)
            ) dcmac_pad_inst (
                .clk(clk_stack),
                .rst(rst),

                .s_axis_tdata (tx_generic_axis_dropper_tdata),
                .s_axis_tkeep (tx_generic_axis_dropper_tkeep),
                .s_axis_tvalid(tx_generic_axis_dropper_tvalid),
                .s_axis_tready(tx_generic_axis_dropper_tready),
                .s_axis_tlast (tx_generic_axis_dropper_tlast),
                .s_axis_tuser (tx_generic_axis_dropper_tuser),

                .m_axis_tdata (tx_generic_pad_axis_tdata),
                .m_axis_tkeep (tx_generic_pad_axis_tkeep),
                .m_axis_tvalid(tx_generic_pad_axis_tvalid),
                .m_axis_tready(tx_generic_pad_axis_tready),
                .m_axis_tlast (tx_generic_pad_axis_tlast),
                .m_axis_tuser (tx_generic_pad_axis_tuser)
            );

            axis_2_axi_seg #(
            ) axis_2_axi_seg_instance (
                .clk(clk_stack),
                .rst(rst),

                .s_axis_tdata (tx_generic_pad_axis_tdata),
                .s_axis_tkeep (tx_generic_pad_axis_tkeep),
                .s_axis_tvalid(tx_generic_pad_axis_tvalid),
                .s_axis_tready(tx_generic_pad_axis_tready),
                .s_axis_tlast (tx_generic_pad_axis_tlast),
                .s_axis_tuser (tx_generic_pad_axis_tuser),

                .m_axis_seg_tdata    ({tx_axi_seg_pkt.dat[7], tx_axi_seg_pkt.dat[6], tx_axi_seg_pkt .dat[5], tx_axi_seg_pkt.dat[4], tx_axi_seg_pkt.dat[3], tx_axi_seg_pkt.dat[2], tx_axi_seg_pkt.dat[1], tx_axi_seg_pkt.dat[0]}),
                .m_axis_seg_tvalid   (tx_axi_seg_tvalid),
                .m_axis_seg_tready   (tx_axi_seg_tready),
                .m_axis_seg_tuser_ena({tx_axi_seg_pkt.ena[7], tx_axi_seg_pkt.ena[6], tx_axi_seg_pkt.ena[5], tx_axi_seg_pkt.ena[4], tx_axi_seg_pkt.ena[3], tx_axi_seg_pkt.ena[2], tx_axi_seg_pkt.ena[1], tx_axi_seg_pkt.ena[0]}),
                .m_axis_seg_tuser_sop({tx_axi_seg_pkt.sop[7], tx_axi_seg_pkt.sop[6], tx_axi_seg_pkt.sop[5], tx_axi_seg_pkt.sop[4], tx_axi_seg_pkt.sop[3], tx_axi_seg_pkt.sop[2], tx_axi_seg_pkt.sop[1], tx_axi_seg_pkt.sop[0]}),
                .m_axis_seg_tuser_eop({tx_axi_seg_pkt.eop[7], tx_axi_seg_pkt.eop[6], tx_axi_seg_pkt.eop[5], tx_axi_seg_pkt.eop[4], tx_axi_seg_pkt.eop[3], tx_axi_seg_pkt.eop[2], tx_axi_seg_pkt.eop[1], tx_axi_seg_pkt.eop[0]}),
                .m_axis_seg_tuser_err({tx_axi_seg_pkt.err[7], tx_axi_seg_pkt.err[6], tx_axi_seg_pkt.err[5], tx_axi_seg_pkt.err[4], tx_axi_seg_pkt.err[3], tx_axi_seg_pkt.err[2], tx_axi_seg_pkt.err[1], tx_axi_seg_pkt.err[0]}),
                .m_axis_seg_tuser_mty({tx_axi_seg_pkt.mty[7], tx_axi_seg_pkt.mty[6], tx_axi_seg_pkt.mty[5], tx_axi_seg_pkt.mty[4], tx_axi_seg_pkt.mty[3], tx_axi_seg_pkt.mty[2], tx_axi_seg_pkt.mty[1], tx_axi_seg_pkt.mty[0]})
            );

            // Async fifo towards the MAC
            axis_async_fifo #(
                .DEPTH(16),
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(0),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(64),
                .LAST_ENABLE(0),
                .RAM_PIPELINE(1),
                .FRAME_FIFO(0)
            ) tx_axis_seg_async_fifo (
                .s_clk(clk_stack),
                .s_rst(rst),

                // AXI input
                .s_axis_tdata ({tx_axi_seg_pkt.dat[7], tx_axi_seg_pkt.dat[6], tx_axi_seg_pkt.dat[5], tx_axi_seg_pkt.dat[4], tx_axi_seg_pkt.dat[3], tx_axi_seg_pkt.dat[2], tx_axi_seg_pkt.dat[1], tx_axi_seg_pkt.dat[0]}),
                .s_axis_tvalid(tx_axi_seg_tvalid),
                .s_axis_tready(tx_axi_seg_tready),
                .s_axis_tuser ({{tx_axi_seg_pkt.ena[7], tx_axi_seg_pkt.ena[6], tx_axi_seg_pkt.ena[5], tx_axi_seg_pkt.ena[4], tx_axi_seg_pkt.ena[3], tx_axi_seg_pkt.ena[2], tx_axi_seg_pkt.ena[1], tx_axi_seg_pkt.ena[0]},
                {tx_axi_seg_pkt.sop[7], tx_axi_seg_pkt.sop[6], tx_axi_seg_pkt.sop[5], tx_axi_seg_pkt.sop[4], tx_axi_seg_pkt.sop[3], tx_axi_seg_pkt.sop[2], tx_axi_seg_pkt.sop[1], tx_axi_seg_pkt.sop[0]},
                {tx_axi_seg_pkt.eop[7], tx_axi_seg_pkt.eop[6], tx_axi_seg_pkt.eop[5], tx_axi_seg_pkt.eop[4], tx_axi_seg_pkt.eop[3], tx_axi_seg_pkt.eop[2], tx_axi_seg_pkt.eop[1], tx_axi_seg_pkt.eop[0]},
                {tx_axi_seg_pkt.err[7], tx_axi_seg_pkt.err[6], tx_axi_seg_pkt.err[5], tx_axi_seg_pkt.err[4], tx_axi_seg_pkt.err[3], tx_axi_seg_pkt.err[2], tx_axi_seg_pkt.err[1], tx_axi_seg_pkt.err[0]},
                {tx_axi_seg_pkt.mty[7], tx_axi_seg_pkt.mty[6], tx_axi_seg_pkt.mty[5], tx_axi_seg_pkt.mty[4], tx_axi_seg_pkt.mty[3], tx_axi_seg_pkt.mty[2], tx_axi_seg_pkt.mty[1], tx_axi_seg_pkt.mty[0]}}),
                .s_axis_tlast (0),
                .s_axis_tkeep (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                .m_clk(clk_mac),
                .m_rst(rst),

                .m_axis_tdata ({tx_axi_seg_pkt_fifo.dat[7], tx_axi_seg_pkt_fifo.dat[6], tx_axi_seg_pkt_fifo.dat[5], tx_axi_seg_pkt_fifo.dat[4], tx_axi_seg_pkt_fifo.dat[3], tx_axi_seg_pkt_fifo.dat[2], tx_axi_seg_pkt_fifo.dat[1], tx_axi_seg_pkt_fifo.dat[0]}),
                .m_axis_tvalid(tx_axi_seg_fifo_tvalid),
                .m_axis_tready(tx_axi_seg_fifo_tready),
                .m_axis_tuser ({{tx_axi_seg_pkt_fifo.ena[7], tx_axi_seg_pkt_fifo.ena[6], tx_axi_seg_pkt_fifo.ena[5], tx_axi_seg_pkt_fifo.ena[4], tx_axi_seg_pkt_fifo.ena[3], tx_axi_seg_pkt_fifo.ena[2], tx_axi_seg_pkt_fifo.ena[1], tx_axi_seg_pkt_fifo.ena[0]},
                {tx_axi_seg_pkt_fifo.sop[7], tx_axi_seg_pkt_fifo.sop[6], tx_axi_seg_pkt_fifo.sop[5], tx_axi_seg_pkt_fifo.sop[4], tx_axi_seg_pkt_fifo.sop[3], tx_axi_seg_pkt_fifo.sop[2], tx_axi_seg_pkt_fifo.sop[1], tx_axi_seg_pkt_fifo.sop[0]},
                {tx_axi_seg_pkt_fifo.eop[7], tx_axi_seg_pkt_fifo.eop[6], tx_axi_seg_pkt_fifo.eop[5], tx_axi_seg_pkt_fifo.eop[4], tx_axi_seg_pkt_fifo.eop[3], tx_axi_seg_pkt_fifo.eop[2], tx_axi_seg_pkt_fifo.eop[1], tx_axi_seg_pkt_fifo.eop[0]},
                {tx_axi_seg_pkt_fifo.err[7], tx_axi_seg_pkt_fifo.err[6], tx_axi_seg_pkt_fifo.err[5], tx_axi_seg_pkt_fifo.err[4], tx_axi_seg_pkt_fifo.err[3], tx_axi_seg_pkt_fifo.err[2], tx_axi_seg_pkt_fifo.err[1], tx_axi_seg_pkt_fifo.err[0]},
                {tx_axi_seg_pkt_fifo.mty[7], tx_axi_seg_pkt_fifo.mty[6], tx_axi_seg_pkt_fifo.mty[5], tx_axi_seg_pkt_fifo.mty[4], tx_axi_seg_pkt_fifo.mty[3], tx_axi_seg_pkt_fifo.mty[2], tx_axi_seg_pkt_fifo.mty[1], tx_axi_seg_pkt_fifo.mty[0]}})
            );

            // RX AXI-SEG to AXIS conversion
            axi_seg_2_axis #(
                .AXIS_FIFO_DEPTH(8192),
                .ASYNC_FIFO(1)
            ) axi_seg_2_axis_instance (
                .s_clk(clk_mac),
                .s_rst(rst),

                .s_axis_seg_tdata    ({rx_axi_seg_pkt.dat[7],rx_axi_seg_pkt.dat[6], rx_axi_seg_pkt.dat[5], rx_axi_seg_pkt.dat[4], rx_axi_seg_pkt.dat[3], rx_axi_seg_pkt.dat[2], rx_axi_seg_pkt.dat[1], rx_axi_seg_pkt.dat[0]}),
                .s_axis_seg_tvalid   (rx_axi_seg_tvalid),
                .s_axis_seg_tready   (rx_axi_seg_tready),
                .s_axis_seg_tuser_ena({rx_axi_seg_pkt.ena[7],rx_axi_seg_pkt.ena[6], rx_axi_seg_pkt.ena[5], rx_axi_seg_pkt.ena[4], rx_axi_seg_pkt.ena[3], rx_axi_seg_pkt.ena[2], rx_axi_seg_pkt.ena[1], rx_axi_seg_pkt.ena[0]}),
                .s_axis_seg_tuser_sop({rx_axi_seg_pkt.sop[7],rx_axi_seg_pkt.sop[6], rx_axi_seg_pkt.sop[5], rx_axi_seg_pkt.sop[4], rx_axi_seg_pkt.sop[3], rx_axi_seg_pkt.sop[2], rx_axi_seg_pkt.sop[1], rx_axi_seg_pkt.sop[0]}),
                .s_axis_seg_tuser_eop({rx_axi_seg_pkt.eop[7],rx_axi_seg_pkt.eop[6], rx_axi_seg_pkt.eop[5], rx_axi_seg_pkt.eop[4], rx_axi_seg_pkt.eop[3], rx_axi_seg_pkt.eop[2], rx_axi_seg_pkt.eop[1], rx_axi_seg_pkt.eop[0]}),
                .s_axis_seg_tuser_err({rx_axi_seg_pkt.err[7],rx_axi_seg_pkt.err[6], rx_axi_seg_pkt.err[5], rx_axi_seg_pkt.err[4], rx_axi_seg_pkt.err[3], rx_axi_seg_pkt.err[2], rx_axi_seg_pkt.err[1], rx_axi_seg_pkt.err[0]}),
                .s_axis_seg_tuser_mty({rx_axi_seg_pkt.mty[7],rx_axi_seg_pkt.mty[6], rx_axi_seg_pkt.mty[5], rx_axi_seg_pkt.mty[4], rx_axi_seg_pkt.mty[3], rx_axi_seg_pkt.mty[2], rx_axi_seg_pkt.mty[1], rx_axi_seg_pkt.mty[0]}),

                .m_clk        (clk_stack),
                .m_rst        (rst),
                .m_axis_tdata (rx_generic_axis_tdata),
                .m_axis_tkeep (rx_generic_axis_tkeep),
                .m_axis_tvalid(rx_generic_axis_tvalid),
                .m_axis_tready(rx_generic_axis_tready),
                .m_axis_tlast (rx_generic_axis_tlast),
                .m_axis_tuser (rx_generic_axis_tuser)
            );

        end else begin

            axis_async_fifo_adapter #(
                .DEPTH(4200),
                .S_DATA_WIDTH(DATA_WIDTH),
                .S_KEEP_ENABLE(1),
                .M_DATA_WIDTH(STACK_DATA_WIDTH),
                .M_KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .FRAME_FIFO(0)
            ) rx_axis_fifo (
                .s_clk(clk_mac),
                .s_rst(rst),

                // AXI input
                .s_axis_tdata (rx_axis_tdata),
                .s_axis_tkeep (rx_axis_tkeep),
                .s_axis_tvalid(rx_axis_tvalid),
                .s_axis_tready(rx_axis_tready),
                .s_axis_tlast (rx_axis_tlast),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser (rx_axis_tuser),

                .m_clk(clk_stack),
                .m_rst(rst),

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

            // Async fifo towards the MAC
            axis_async_fifo_adapter #(
                .DEPTH(4200),
                .S_DATA_WIDTH(STACK_DATA_WIDTH),
                .S_KEEP_ENABLE(1),
                .M_DATA_WIDTH(DATA_WIDTH),
                .M_KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .FRAME_FIFO(0)
            ) tx_axis_fifo (
                .s_clk(clk_stack),
                .s_rst(rst),

                .s_axis_tdata (tx_generic_axis_dropper_tdata),
                .s_axis_tkeep (tx_generic_axis_dropper_tkeep),
                .s_axis_tvalid(tx_generic_axis_dropper_tvalid),
                .s_axis_tready(tx_generic_axis_dropper_tready),
                .s_axis_tlast (tx_generic_axis_dropper_tlast),
                .s_axis_tid(0),
                .s_axis_tdest(0),
                .s_axis_tuser(tx_generic_axis_dropper_tuser),



                .m_clk(clk_mac),
                .m_rst(rst),

                // AXI output
                .m_axis_tdata (tx_axis_tdata),
                .m_axis_tkeep (tx_axis_tkeep),
                .m_axis_tvalid(tx_axis_tvalid),
                .m_axis_tready(tx_axis_tready),
                .m_axis_tlast (tx_axis_tlast),
                .m_axis_tid   (),
                .m_axis_tdest (),
                .m_axis_tuser (tx_axis_tuser)
            );
        end

    endgenerate


    fake_mac #(
        .LOCAL_MAC_ADDRESS(48'h00_0A_35_DE_AD_01),
        .MAC_DATA_WIDTH   (DATA_WIDTH),
        .MAC_KEEP_WIDTH   (KEEP_WIDTH),
        .MAC_AXI_SEG_INPUT(MAC_AXI_SEG_INPUT),
        .ENABLE_PADDING(1),
        .ENABLE_DIC(1),
        .MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(4200),
        .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(4200),
        .RX_FRAME_FIFO(1),
        .PFC_ENABLE(1)
    ) fake_mac_instance (
        .clk_mac_sim(clk_mac_sim),
        .rst_mac_sim(rst),
        .clk_mac(clk_mac),
        .rst_mac(rst),

        .tx_axis_tdata (tx_axis_tdata ),
        .tx_axis_tkeep (tx_axis_tkeep ),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tlast (tx_axis_tlast ),
        .tx_axis_tuser (tx_axis_tuser ),

        .rx_axis_tdata (rx_axis_tdata),
        .rx_axis_tkeep (rx_axis_tkeep),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_axis_tready),
        .rx_axis_tlast (rx_axis_tlast),
        .rx_axis_tuser (rx_axis_tuser),

        .tx_axi_seg_tdata    ({tx_axi_seg_pkt_fifo.dat[7],tx_axi_seg_pkt_fifo.dat[6], tx_axi_seg_pkt_fifo.dat[5], tx_axi_seg_pkt_fifo.dat[4], tx_axi_seg_pkt_fifo.dat[3], tx_axi_seg_pkt_fifo.dat[2], tx_axi_seg_pkt_fifo.dat[1], tx_axi_seg_pkt_fifo.dat[0]}),
        .tx_axi_seg_tvalid   (tx_axi_seg_fifo_tvalid),
        .tx_axi_seg_tready   (tx_axi_seg_fifo_tready),
        .tx_axi_seg_tuser_ena({tx_axi_seg_pkt_fifo.ena[7],tx_axi_seg_pkt_fifo.ena[6], tx_axi_seg_pkt_fifo.ena[5], tx_axi_seg_pkt_fifo.ena[4], tx_axi_seg_pkt_fifo.ena[3], tx_axi_seg_pkt_fifo.ena[2], tx_axi_seg_pkt_fifo.ena[1], tx_axi_seg_pkt_fifo.ena[0]}),
        .tx_axi_seg_tuser_sop({tx_axi_seg_pkt_fifo.sop[7],tx_axi_seg_pkt_fifo.sop[6], tx_axi_seg_pkt_fifo.sop[5], tx_axi_seg_pkt_fifo.sop[4], tx_axi_seg_pkt_fifo.sop[3], tx_axi_seg_pkt_fifo.sop[2], tx_axi_seg_pkt_fifo.sop[1], tx_axi_seg_pkt_fifo.sop[0]}),
        .tx_axi_seg_tuser_eop({tx_axi_seg_pkt_fifo.eop[7],tx_axi_seg_pkt_fifo.eop[6], tx_axi_seg_pkt_fifo.eop[5], tx_axi_seg_pkt_fifo.eop[4], tx_axi_seg_pkt_fifo.eop[3], tx_axi_seg_pkt_fifo.eop[2], tx_axi_seg_pkt_fifo.eop[1], tx_axi_seg_pkt_fifo.eop[0]}),
        .tx_axi_seg_tuser_err({tx_axi_seg_pkt_fifo.err[7],tx_axi_seg_pkt_fifo.err[6], tx_axi_seg_pkt_fifo.err[5], tx_axi_seg_pkt_fifo.err[4], tx_axi_seg_pkt_fifo.err[3], tx_axi_seg_pkt_fifo.err[2], tx_axi_seg_pkt_fifo.err[1], tx_axi_seg_pkt_fifo.err[0]}),
        .tx_axi_seg_tuser_mty({tx_axi_seg_pkt_fifo.mty[7],tx_axi_seg_pkt_fifo.mty[6], tx_axi_seg_pkt_fifo.mty[5], tx_axi_seg_pkt_fifo.mty[4], tx_axi_seg_pkt_fifo.mty[3], tx_axi_seg_pkt_fifo.mty[2], tx_axi_seg_pkt_fifo.mty[1], tx_axi_seg_pkt_fifo.mty[0]}),

        .rx_axi_seg_tdata    ({rx_axi_seg_pkt.dat[7], rx_axi_seg_pkt.dat[6], rx_axi_seg_pkt.dat[5], rx_axi_seg_pkt.dat[4], rx_axi_seg_pkt.dat[3], rx_axi_seg_pkt.dat[2], rx_axi_seg_pkt.dat[1], rx_axi_seg_pkt.dat[0]}),
        .rx_axi_seg_tvalid   (rx_axi_seg_tvalid),
        .rx_axi_seg_tready   (rx_axi_seg_tready),
        .rx_axi_seg_tuser_ena({rx_axi_seg_pkt.ena[7], rx_axi_seg_pkt.ena[6], rx_axi_seg_pkt.ena[5], rx_axi_seg_pkt.ena[4], rx_axi_seg_pkt.ena[3], rx_axi_seg_pkt.ena[2], rx_axi_seg_pkt.ena[1], rx_axi_seg_pkt.ena[0]}),
        .rx_axi_seg_tuser_sop({rx_axi_seg_pkt.sop[7], rx_axi_seg_pkt.sop[6], rx_axi_seg_pkt.sop[5], rx_axi_seg_pkt.sop[4], rx_axi_seg_pkt.sop[3], rx_axi_seg_pkt.sop[2], rx_axi_seg_pkt.sop[1], rx_axi_seg_pkt.sop[0]}),
        .rx_axi_seg_tuser_eop({rx_axi_seg_pkt.eop[7], rx_axi_seg_pkt.eop[6], rx_axi_seg_pkt.eop[5], rx_axi_seg_pkt.eop[4], rx_axi_seg_pkt.eop[3], rx_axi_seg_pkt.eop[2], rx_axi_seg_pkt.eop[1], rx_axi_seg_pkt.eop[0]}),
        .rx_axi_seg_tuser_err({rx_axi_seg_pkt.err[7], rx_axi_seg_pkt.err[6], rx_axi_seg_pkt.err[5], rx_axi_seg_pkt.err[4], rx_axi_seg_pkt.err[3], rx_axi_seg_pkt.err[2], rx_axi_seg_pkt.err[1], rx_axi_seg_pkt.err[0]}),
        .rx_axi_seg_tuser_mty({rx_axi_seg_pkt.mty[7], rx_axi_seg_pkt.mty[6], rx_axi_seg_pkt.mty[5], rx_axi_seg_pkt.mty[4], rx_axi_seg_pkt.mty[3], rx_axi_seg_pkt.mty[2], rx_axi_seg_pkt.mty[1], rx_axi_seg_pkt.mty[0]}),

        .xgmii_tx_clk(xgmii_tx_clk),
        .xgmii_tx_rst(xgmii_tx_rst),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_rx_clk(xgmii_rx_clk),
        .xgmii_rx_rst(xgmii_rx_rst),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),

        .tx_pause_req(tx_pause_req),
        .tx_pause_ack(tx_pause_ack),

        .cfg_ifg(8'd12),
        .ctrl_priority_tag(3'd3),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1)
    );

    // no need for fancy synchronizer in sim
    

    always @(posedge clk_stack) begin
        tx_pause_req_network <= tx_pause_req;
    end
    always @(posedge clk_mac) begin
        tx_pause_ack_reg <= tx_pause_ack_network;
    end
    assign tx_pause_ack = tx_pause_ack_reg;
    
    




endmodule

`resetall
