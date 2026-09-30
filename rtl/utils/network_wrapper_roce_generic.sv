`resetall `timescale 1ns / 1ps `default_nettype none


module network_wrapper_roce_generic #(
    parameter STACK_DATA_WIDTH         = 1024,
    parameter ROCE_ENG_DATA_WIDTH      = STACK_DATA_WIDTH,
    parameter ROCE_ENG_KEEP_ENABLE     = (ROCE_ENG_DATA_WIDTH>8),
    parameter ROCE_ENG_KEEP_WIDTH      = (ROCE_ENG_DATA_WIDTH/8),
    parameter QP_CH_DATA_WIDTH         = STACK_DATA_WIDTH,
    parameter QP_CH_KEEP_ENABLE        = QP_CH_DATA_WIDTH > 8,
    parameter QP_CH_KEEP_WIDTH         = QP_CH_DATA_WIDTH/8,
    parameter real ROCE_ENG_CLK_PERIOD = 3.000, // in ns, needed to compute RNR timer values
    parameter real STACK_CLK_PERIOD    = 3.000, // in ns
    parameter N_ROCE_TX_ENGINES        = 1,
    parameter real TARGET_SPEED        = 98.05,
    parameter N_QUEUE_PAIRS            = 4,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 23,
    parameter HEADER_CHECKSUM_PIPELINED = 1,
    parameter IP_PAYLOAD_FIFO_CHECKSUM  = 1,
    parameter RX_FIFO_REGS = 2,
    parameter TX_FIFO_REGS = 2,
    parameter ENABLE_PFC = 0,
    parameter DEBUG = 0,
    // Register to achieve better timings, enable them if you want to trade some flops with better timing
    parameter ENABLE_TIMING_OPT_REGS = 0
) (
    input wire clk_stack,
    input wire rst_stack,

    input wire clk_roce_eng,
    input wire rst_roce_eng,

    input wire flow_ctrl_pause, // stack clock domain

    /*
    AXIS input streams
    */
    // input Work request
    input  wire         s_wr_req_valid          [N_QUEUE_PAIRS-1:0],
    output wire         s_wr_req_ready          [N_QUEUE_PAIRS-1:0],
    input  wire         s_wr_req_tx_type        [N_QUEUE_PAIRS-1:0], // 0 WRITE, 1 SEND
    input  wire         s_wr_req_is_immediate   [N_QUEUE_PAIRS-1:0],
    input  wire [31:0]  s_wr_req_immediate_data [N_QUEUE_PAIRS-1:0],
    input  wire [23:0]  s_wr_req_loc_qp         [N_QUEUE_PAIRS-1:0],
    input  wire [63:0]  s_wr_req_addr_offset    [N_QUEUE_PAIRS-1:0],
    input  wire [31:0]  s_wr_req_dma_length     [N_QUEUE_PAIRS-1:0], // for each transfer

    // input QPs AXIS
    input  wire [QP_CH_DATA_WIDTH - 1 :0]  s_axis_tdata  [N_QUEUE_PAIRS-1:0],
    input  wire [QP_CH_KEEP_WIDTH - 1 :0]  s_axis_tkeep  [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tvalid [N_QUEUE_PAIRS-1:0],
    output wire                            s_axis_tready [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tlast  [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tuser  [N_QUEUE_PAIRS-1:0],

    /*
     * Ethernet: AXIS
     */
    // TX AXIS
    output wire [STACK_DATA_WIDTH -1 :0]    m_network_tx_axis_tdata,
    output wire [STACK_DATA_WIDTH/8-1 :0 ]  m_network_tx_axis_tkeep,
    output wire                             m_network_tx_axis_tvalid,
    input  wire                             m_network_tx_axis_tready,
    output wire                             m_network_tx_axis_tlast,
    output wire                             m_network_tx_axis_tuser,
    // RX AXIS
    input  wire [STACK_DATA_WIDTH -1 :0]    s_network_rx_axis_tdata,
    input  wire [STACK_DATA_WIDTH/8-1 :0]   s_network_rx_axis_tkeep,
    input  wire                             s_network_rx_axis_tvalid,
    output wire                             s_network_rx_axis_tready,
    input  wire                             s_network_rx_axis_tlast,
    input  wire                             s_network_rx_axis_tuser,
    /*
     * AXI master interface to RAM
     */
    output wire [0                :0]                                            m_axi_awid    [N_ROCE_TX_ENGINES-1:0],
    output wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)-1:0] m_axi_awaddr  [N_ROCE_TX_ENGINES-1:0],
    output wire [7:0]                                                            m_axi_awlen   [N_ROCE_TX_ENGINES-1:0],
    output wire [2:0]                                                            m_axi_awsize  [N_ROCE_TX_ENGINES-1:0],
    output wire [1:0]                                                            m_axi_awburst [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_awlock  [N_ROCE_TX_ENGINES-1:0],
    output wire [3:0]                                                            m_axi_awcache [N_ROCE_TX_ENGINES-1:0],
    output wire [2:0]                                                            m_axi_awprot  [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_awvalid [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_awready [N_ROCE_TX_ENGINES-1:0],
    output wire [ROCE_ENG_DATA_WIDTH - 1 : 0]                                    m_axi_wdata   [N_ROCE_TX_ENGINES-1:0],
    output wire [ROCE_ENG_KEEP_WIDTH - 1 : 0]                                    m_axi_wstrb   [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_wlast   [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_wvalid  [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_wready  [N_ROCE_TX_ENGINES-1:0],
    input  wire [0:0]                                                            m_axi_bid     [N_ROCE_TX_ENGINES-1:0],
    input  wire [1:0]                                                            m_axi_bresp   [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_bvalid  [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_bready  [N_ROCE_TX_ENGINES-1:0],
    output wire [0               :0]                                             m_axi_arid    [N_ROCE_TX_ENGINES-1:0],
    output wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)-1:0] m_axi_araddr  [N_ROCE_TX_ENGINES-1:0],
    output wire [7:0]                                                            m_axi_arlen   [N_ROCE_TX_ENGINES-1:0],
    output wire [2:0]                                                            m_axi_arsize  [N_ROCE_TX_ENGINES-1:0],
    output wire [1:0]                                                            m_axi_arburst [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_arlock  [N_ROCE_TX_ENGINES-1:0],
    output wire [3:0]                                                            m_axi_arcache [N_ROCE_TX_ENGINES-1:0],
    output wire [2:0]                                                            m_axi_arprot  [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_arvalid [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_arready [N_ROCE_TX_ENGINES-1:0],
    input  wire [0             :0]                                               m_axi_rid     [N_ROCE_TX_ENGINES-1:0],
    input  wire [ROCE_ENG_DATA_WIDTH  -1:0]                                      m_axi_rdata   [N_ROCE_TX_ENGINES-1:0],
    input  wire [1:0]                                                            m_axi_rresp   [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_rlast   [N_ROCE_TX_ENGINES-1:0],
    input  wire                                                                  m_axi_rvalid  [N_ROCE_TX_ENGINES-1:0],
    output wire                                                                  m_axi_rready  [N_ROCE_TX_ENGINES-1:0],
    /*
    Pause signals
    */
    input  wire [7:0]             pfc_pause_req,
    output wire [7:0]             pfc_pause_ack,
    /* 
    QP state spy
    */
    input wire         m_qp_spy_context,
    input wire [23:0]  m_qp_spy_loc_qpn,

    output wire        s_qp_spy_context_valid,
    output wire [2 :0] s_qp_spy_state,
    output wire [23:0] s_qp_spy_rem_qpn,
    output wire [23:0] s_qp_spy_loc_qpn,
    output wire [23:0] s_qp_spy_rem_psn,
    output wire [23:0] s_qp_spy_rem_acked_psn,
    output wire [23:0] s_qp_spy_loc_psn,
    output wire [31:0] s_qp_spy_r_key,
    output wire [63:0] s_qp_spy_rem_addr,
    output wire [31:0] s_qp_spy_rem_ip_addr,
    output wire [7:0]  s_qp_spy_syndrome,
    /*
    Control registers
    */
    input wire [47:0]               ctrl_local_mac_address, // Should not be a generic
    input wire [31:0]               ctrl_local_ip,
    input wire                      ctrl_clear_arp_cache,
    input wire [2:0 ]               ctrl_pmtu,
    input wire [15:0]               ctrl_RoCE_udp_port,
    input wire [2:0 ]               ctrl_priority_tag,
    input wire [31:0]               ctrl_retry_timeout, // in number of clk_stack cycles, after which a packet is considered lost and retransmission is triggered
    input wire  [N_QUEUE_PAIRS-1:0] ctrl_use_data_gen,

    // dcqcn
    input wire        ctrl_dcqcn_en,
    input wire [9:0]  ctrl_dcqcn_par_g,
    input wire [9:0]  ctrl_dcqcn_alpha_min,
    input wire [31:0] ctrl_dcqcn_alpha_upd_time,
    input wire [9:0]  ctrl_dcqcn_rate_decr_min,
    input wire [10:0] ctrl_dcqcn_rate_min,
    input wire [31:0] ctrl_dcqcn_upd_time,
    input wire [31:0] ctrl_dcqcn_rate_ai_time,
    input wire [31:0] ctrl_dcqcn_rate_hai_time,
    input wire [9:0]  ctrl_dcqcn_rate_incr_ai,
    input wire [9:0]  ctrl_dcqcn_rate_incr_hai,

    // perf monitor
    input  wire [3:0]  perf_cfg_latency_avg_po2,
    input  wire [4:0]  perf_cfg_throughput_avg_po2,
    input  wire [23:0] perf_monitor_loc_qpn,
    output wire [31:0] perf_transfer_time_avg,
    output wire [31:0] perf_transfer_time_moving_avg,
    output wire [31:0] perf_latency_max,
    output wire [31:0] perf_latency_avg,
    output wire [31:0] perf_latency_moving_avg,
    output wire [23:0] perf_psn_diff,
    output wire [23:0] perf_psn_diff_max,
    output wire [31:0] perf_n_retransmit_triggers,
    output wire [31:0] perf_n_rnr_retransmit_triggers,
    output wire [31:0] perf_n_total_psn_seq_errors,
    output wire [31:0] perf_n_total_timeout_errors,
    //latency histogram
    input  wire        perf_lat_histo_reset_counts,
    input  wire        perf_lat_histo_trgg_readout,
    output wire [31:0] perf_lat_histo_index,
    output wire        perf_lat_histo_valid,
    output wire [31:0] perf_lat_histo_counts,
    output wire        perf_lat_histo_rst_done,
    output wire        perf_lat_histo_ovflw,

    input  wire        perf_adj_ack_histo_reset_counts,
    input  wire        perf_adj_ack_histo_trgg_readout,
    output wire [31:0] perf_adj_ack_histo_index,
    output wire        perf_adj_ack_histo_valid,
    output wire [31:0] perf_adj_ack_histo_counts,
    output wire        perf_adj_ack_histo_rst_done,
    output wire        perf_adj_ack_histo_ovflw


);

    initial begin
        if (N_QUEUE_PAIRS/N_ROCE_TX_ENGINES <  1) begin
            $error("Error: Must have at least 1 QUEUE PAIR per TX engine (instance %m)");
            $finish;
        end
    end

    import RoCE_params::*; // Imports RoCE parameters

    wire [STACK_DATA_WIDTH -1 :0]    s_rx_axis_srl_fifo_tdata;
    wire [STACK_DATA_WIDTH/8-1 :0 ]  s_rx_axis_srl_fifo_tkeep;
    wire                             s_rx_axis_srl_fifo_tvalid;
    wire                             s_rx_axis_srl_fifo_tready;
    wire                             s_rx_axis_srl_fifo_tlast;
    wire                             s_rx_axis_srl_fifo_tuser;

    wire [STACK_DATA_WIDTH -1 :0]    m_tx_axis_srl_fifo_tdata;
    wire [STACK_DATA_WIDTH/8-1 :0 ]  m_tx_axis_srl_fifo_tkeep;
    wire                             m_tx_axis_srl_fifo_tvalid;
    wire                             m_tx_axis_srl_fifo_tready;
    wire                             m_tx_axis_srl_fifo_tlast;
    wire                             m_tx_axis_srl_fifo_tuser;

    wire [STACK_DATA_WIDTH -1 :0]    m_tx_axis_pfc_tdata;
    wire [STACK_DATA_WIDTH/8-1 :0 ]  m_tx_axis_pfc_tkeep;
    wire                             m_tx_axis_pfc_tvalid;
    wire                             m_tx_axis_pfc_tready;
    wire                             m_tx_axis_pfc_tlast;
    wire                             m_tx_axis_pfc_tuser;

    wire [STACK_DATA_WIDTH  -1 :0]   s_rx_axis_adapter_tdata;
    wire [STACK_DATA_WIDTH/8-1 :0]   s_rx_axis_adapter_tkeep;
    wire                             s_rx_axis_adapter_tvalid;
    wire                             s_rx_axis_adapter_tready;
    wire                             s_rx_axis_adapter_tlast;
    wire                             s_rx_axis_adapter_tuser;

    wire [STACK_DATA_WIDTH  -1 :0]   m_tx_axis_adapter_tdata;
    wire [STACK_DATA_WIDTH/8-1 :0]   m_tx_axis_adapter_tkeep;
    wire                             m_tx_axis_adapter_tvalid;
    wire                             m_tx_axis_adapter_tready;
    wire                             m_tx_axis_adapter_tlast;
    wire                             m_tx_axis_adapter_tuser;

    // RX UDP frame
    wire                             s_rx_udp_hdr_valid;
    wire                             s_rx_udp_hdr_ready;
    wire [ 47:0]                     s_rx_udp_eth_dest_mac;
    wire [ 47:0]                     s_rx_udp_eth_src_mac;
    wire [ 15:0]                     s_rx_udp_eth_type;
    wire [  3:0]                     s_rx_udp_ip_version;
    wire [  3:0]                     s_rx_udp_ip_ihl;
    wire [  5:0]                     s_rx_udp_ip_dscp;
    wire [  1:0]                     s_rx_udp_ip_ecn;
    wire [ 15:0]                     s_rx_udp_ip_length;
    wire [ 15:0]                     s_rx_udp_ip_identification;
    wire [  2:0]                     s_rx_udp_ip_flags;
    wire [ 12:0]                     s_rx_udp_ip_fragment_offset;
    wire [  7:0]                     s_rx_udp_ip_ttl;
    wire [  7:0]                     s_rx_udp_ip_protocol;
    wire [ 15:0]                     s_rx_udp_ip_header_checksum;
    wire [ 31:0]                     s_rx_udp_ip_source_ip;
    wire [ 31:0]                     s_rx_udp_ip_dest_ip;
    wire [ 15:0]                     s_rx_udp_source_port;
    wire [ 15:0]                     s_rx_udp_dest_port;
    wire [ 15:0]                     s_rx_udp_length;
    wire [ 15:0]                     s_rx_udp_checksum;
    wire [STACK_DATA_WIDTH - 1  :0]  s_rx_udp_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  s_rx_udp_payload_axis_tkeep;
    wire                             s_rx_udp_payload_axis_tvalid;
    wire                             s_rx_udp_payload_axis_tready;
    wire                             s_rx_udp_payload_axis_tlast;
    wire                             s_rx_udp_payload_axis_tuser;

    // TX UDP frame
    wire                             m_tx_udp_hdr_valid;
    wire                             m_tx_udp_hdr_ready;
    wire [ 47:0]                     m_tx_udp_eth_dest_mac;
    wire [ 47:0]                     m_tx_udp_eth_src_mac;
    wire [ 15:0]                     m_tx_udp_eth_type;
    wire [  3:0]                     m_tx_udp_ip_version;
    wire [  3:0]                     m_tx_udp_ip_ihl;
    wire [  5:0]                     m_tx_udp_ip_dscp;
    wire [  1:0]                     m_tx_udp_ip_ecn;
    wire [ 15:0]                     m_tx_udp_ip_length;
    wire [ 15:0]                     m_tx_udp_ip_identification;
    wire [  2:0]                     m_tx_udp_ip_flags;
    wire [ 12:0]                     m_tx_udp_ip_fragment_offset;
    wire [  7:0]                     m_tx_udp_ip_ttl;
    wire [  7:0]                     m_tx_udp_ip_protocol;
    wire [ 15:0]                     m_tx_udp_ip_header_checksum;
    wire [ 31:0]                     m_tx_udp_ip_source_ip;
    wire [ 31:0]                     m_tx_udp_ip_dest_ip;
    wire [ 15:0]                     m_tx_udp_source_port;
    wire [ 15:0]                     m_tx_udp_dest_port;
    wire [ 15:0]                     m_tx_udp_length;
    wire [ 15:0]                     m_tx_udp_checksum;
    wire [STACK_DATA_WIDTH - 1  :0]  m_tx_udp_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  m_tx_udp_payload_axis_tkeep;
    wire                             m_tx_udp_payload_axis_tvalid;
    wire                             m_tx_udp_payload_axis_tready;
    wire                             m_tx_udp_payload_axis_tlast;
    wire                             m_tx_udp_payload_axis_tuser;

    reg [47:0] ctrl_local_mac_address_reg;
    reg [31:0] ctrl_local_ip_reg;
    reg        ctrl_clear_arp_cache_reg;
    reg [2:0 ] ctrl_pmtu_reg;
    reg [15:0] ctrl_RoCE_udp_port_reg;
    reg [2:0 ] ctrl_priority_tag_reg;
    reg [31:0] ctrl_retry_timeout_reg;
    reg [31:0] ctrl_use_data_gen_reg;

    always @(posedge clk_stack) begin
        ctrl_local_mac_address_reg <= ctrl_local_mac_address;
        ctrl_local_ip_reg          <= ctrl_local_ip;
        ctrl_clear_arp_cache_reg   <= ctrl_clear_arp_cache;
        ctrl_pmtu_reg              <= ctrl_pmtu;
        ctrl_RoCE_udp_port_reg     <= ctrl_RoCE_udp_port;
        ctrl_priority_tag_reg      <= ctrl_priority_tag;
        ctrl_retry_timeout_reg     <= ctrl_retry_timeout;
        ctrl_use_data_gen_reg      <= ctrl_use_data_gen;
    end


    // Configuration
    wire [31:0] gateway_ip = {ctrl_local_ip_reg[31:8], 8'd1};
    wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0  };

    generate

        if (TX_FIFO_REGS == 0) begin
            assign m_network_tx_axis_tdata   = m_tx_axis_srl_fifo_tdata;
            assign m_network_tx_axis_tkeep   = m_tx_axis_srl_fifo_tkeep;
            assign m_network_tx_axis_tvalid  = m_tx_axis_srl_fifo_tvalid;
            assign m_tx_axis_srl_fifo_tready = m_network_tx_axis_tready;
            assign m_network_tx_axis_tlast   = m_tx_axis_srl_fifo_tlast;
            assign m_network_tx_axis_tuser   = m_tx_axis_srl_fifo_tuser;
        end else if (TX_FIFO_REGS == 1) begin
            axis_srl_register #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1)
            ) tx_axis_srl_reg (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (m_tx_axis_srl_fifo_tdata),
                .s_axis_tkeep (m_tx_axis_srl_fifo_tkeep),
                .s_axis_tvalid(m_tx_axis_srl_fifo_tvalid),
                .s_axis_tready(m_tx_axis_srl_fifo_tready),
                .s_axis_tlast (m_tx_axis_srl_fifo_tlast),
                .s_axis_tuser (m_tx_axis_srl_fifo_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_network_tx_axis_tdata),
                .m_axis_tkeep (m_network_tx_axis_tkeep),
                .m_axis_tvalid(m_network_tx_axis_tvalid),
                .m_axis_tready(m_network_tx_axis_tready),
                .m_axis_tlast (m_network_tx_axis_tlast),
                .m_axis_tuser (m_network_tx_axis_tuser)
            );
        end else begin
            axis_srl_fifo #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .DEPTH(TX_FIFO_REGS)
            ) tx_axis_srl_fifo (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (m_tx_axis_srl_fifo_tdata),
                .s_axis_tkeep (m_tx_axis_srl_fifo_tkeep),
                .s_axis_tvalid(m_tx_axis_srl_fifo_tvalid),
                .s_axis_tready(m_tx_axis_srl_fifo_tready),
                .s_axis_tlast (m_tx_axis_srl_fifo_tlast),
                .s_axis_tuser (m_tx_axis_srl_fifo_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_network_tx_axis_tdata),
                .m_axis_tkeep (m_network_tx_axis_tkeep),
                .m_axis_tvalid(m_network_tx_axis_tvalid),
                .m_axis_tready(m_network_tx_axis_tready),
                .m_axis_tlast (m_network_tx_axis_tlast),
                .m_axis_tuser (m_network_tx_axis_tuser)
            );
        end
        if (RX_FIFO_REGS == 0) begin
            assign s_rx_axis_srl_fifo_tdata   = s_network_rx_axis_tdata;
            assign s_rx_axis_srl_fifo_tkeep   = s_network_rx_axis_tkeep;
            assign s_rx_axis_srl_fifo_tvalid  = s_network_rx_axis_tvalid;
            assign s_network_rx_axis_tready   = s_rx_axis_srl_fifo_tready;
            assign s_rx_axis_srl_fifo_tlast   = s_network_rx_axis_tlast;
            assign s_rx_axis_srl_fifo_tuser   = s_network_rx_axis_tuser;
        end else if (RX_FIFO_REGS == 1) begin
            axis_srl_register #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1)
            ) rx_axis_srl_reg (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (s_network_rx_axis_tdata),
                .s_axis_tkeep (s_network_rx_axis_tkeep),
                .s_axis_tvalid(s_network_rx_axis_tvalid),
                .s_axis_tready(s_network_rx_axis_tready),
                .s_axis_tlast (s_network_rx_axis_tlast),
                .s_axis_tuser (s_network_rx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (s_rx_axis_srl_fifo_tdata),
                .m_axis_tkeep (s_rx_axis_srl_fifo_tkeep),
                .m_axis_tvalid(s_rx_axis_srl_fifo_tvalid),
                .m_axis_tready(s_rx_axis_srl_fifo_tready),
                .m_axis_tlast (s_rx_axis_srl_fifo_tlast),
                .m_axis_tuser (s_rx_axis_srl_fifo_tuser)
            );
        end else begin
            axis_srl_fifo #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .DEPTH(RX_FIFO_REGS)
            ) rx_axis_srl_fifo (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (s_network_rx_axis_tdata),
                .s_axis_tkeep (s_network_rx_axis_tkeep),
                .s_axis_tvalid(s_network_rx_axis_tvalid),
                .s_axis_tready(s_network_rx_axis_tready),
                .s_axis_tlast (s_network_rx_axis_tlast),
                .s_axis_tuser (s_network_rx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (s_rx_axis_srl_fifo_tdata),
                .m_axis_tkeep (s_rx_axis_srl_fifo_tkeep),
                .m_axis_tvalid(s_rx_axis_srl_fifo_tvalid),
                .m_axis_tready(s_rx_axis_srl_fifo_tready),
                .m_axis_tlast (s_rx_axis_srl_fifo_tlast),
                .m_axis_tuser (s_rx_axis_srl_fifo_tuser)
            );
        end

        if (ENABLE_PFC) begin

            localparam OPTIMAL_FIFO_SIZE = (512-1)*STACK_DATA_WIDTH/8; // for 1024b it's around 60kB
            localparam PFC_FIFO_SIZE = OPTIMAL_FIFO_SIZE > 4200 ? OPTIMAL_FIFO_SIZE : (8192 - STACK_DATA_WIDTH/8); // for 1024b it's around 60kB

            eth_pfc_fifo_tx #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                // And the minimum depth would be 512, so why not use all of them rather than underutilize them
                .FIFO_DEPTH(PFC_FIFO_SIZE),
                .OUTPUT_SRL_REG(0)
            ) eth_pfc_fifo_tx_instance (
                .clk(clk_stack),
                .rst(rst_stack),
                .s_priority_axis_tdata (m_tx_axis_pfc_tdata ),
                .s_priority_axis_tkeep (m_tx_axis_pfc_tkeep ),
                .s_priority_axis_tvalid(m_tx_axis_pfc_tvalid),
                .s_priority_axis_tready(m_tx_axis_pfc_tready),
                .s_priority_axis_tlast (m_tx_axis_pfc_tlast ),
                .s_priority_axis_tuser (m_tx_axis_pfc_tuser ),



                .m_axis_tdata (m_tx_axis_srl_fifo_tdata),
                .m_axis_tkeep (m_tx_axis_srl_fifo_tkeep),
                .m_axis_tvalid(m_tx_axis_srl_fifo_tvalid),
                .m_axis_tready(m_tx_axis_srl_fifo_tready),
                .m_axis_tlast (m_tx_axis_srl_fifo_tlast),
                .m_axis_tuser (m_tx_axis_srl_fifo_tuser),

                .priority_tag(ctrl_priority_tag_reg),

                .pause_req(pfc_pause_req),
                .pause_ack(pfc_pause_ack)
            );

        end else begin
            assign m_tx_axis_srl_fifo_tdata   = m_tx_axis_pfc_tdata;
            assign m_tx_axis_srl_fifo_tkeep   = m_tx_axis_pfc_tkeep;
            assign m_tx_axis_srl_fifo_tvalid  = m_tx_axis_pfc_tvalid;
            assign m_tx_axis_pfc_tready       = m_tx_axis_srl_fifo_tready;
            assign m_tx_axis_srl_fifo_tlast   = m_tx_axis_pfc_tlast;
            assign m_tx_axis_srl_fifo_tuser   = m_tx_axis_pfc_tuser;

            assign pfc_pause_ack = 8'hFF;
        end

        if (ENABLE_TIMING_OPT_REGS) begin
            // RX
            axis_register #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .REG_TYPE(2)
            ) rx_axis_register (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (s_rx_axis_srl_fifo_tdata),
                .s_axis_tkeep (s_rx_axis_srl_fifo_tkeep),
                .s_axis_tvalid(s_rx_axis_srl_fifo_tvalid),
                .s_axis_tready(s_rx_axis_srl_fifo_tready),
                .s_axis_tlast (s_rx_axis_srl_fifo_tlast),
                .s_axis_tuser (s_rx_axis_srl_fifo_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (s_rx_axis_adapter_tdata),
                .m_axis_tkeep (s_rx_axis_adapter_tkeep),
                .m_axis_tvalid(s_rx_axis_adapter_tvalid),
                .m_axis_tready(s_rx_axis_adapter_tready),
                .m_axis_tlast (s_rx_axis_adapter_tlast),
                .m_axis_tuser (s_rx_axis_adapter_tuser)
            );
            // TX
            axis_register #(
                .DATA_WIDTH(STACK_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .REG_TYPE(2)
            ) tx_axis_register (
                .clk(clk_stack),
                .rst(rst_stack),

                // AXI input
                .s_axis_tdata (m_tx_axis_adapter_tdata),
                .s_axis_tkeep (m_tx_axis_adapter_tkeep),
                .s_axis_tvalid(m_tx_axis_adapter_tvalid),
                .s_axis_tready(m_tx_axis_adapter_tready),
                .s_axis_tlast (m_tx_axis_adapter_tlast),
                .s_axis_tuser (m_tx_axis_adapter_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_tx_axis_pfc_tdata),
                .m_axis_tkeep (m_tx_axis_pfc_tkeep),
                .m_axis_tvalid(m_tx_axis_pfc_tvalid),
                .m_axis_tready(m_tx_axis_pfc_tready),
                .m_axis_tlast (m_tx_axis_pfc_tlast),
                .m_axis_tuser (m_tx_axis_pfc_tuser)
            );
        end else begin
            assign s_rx_axis_adapter_tdata   = s_rx_axis_srl_fifo_tdata;
            assign s_rx_axis_adapter_tkeep   = s_rx_axis_srl_fifo_tkeep;
            assign s_rx_axis_adapter_tvalid  = s_rx_axis_srl_fifo_tvalid;
            assign s_rx_axis_srl_fifo_tready = s_rx_axis_adapter_tready;
            assign s_rx_axis_adapter_tlast   = s_rx_axis_srl_fifo_tlast;
            assign s_rx_axis_adapter_tuser   = s_rx_axis_srl_fifo_tuser;

            assign m_tx_axis_pfc_tdata      = m_tx_axis_adapter_tdata;
            assign m_tx_axis_pfc_tkeep      = m_tx_axis_adapter_tkeep;
            assign m_tx_axis_pfc_tvalid     = m_tx_axis_adapter_tvalid;
            assign m_tx_axis_adapter_tready = m_tx_axis_pfc_tready;
            assign m_tx_axis_pfc_tlast      = m_tx_axis_adapter_tlast;
            assign m_tx_axis_pfc_tuser      = m_tx_axis_adapter_tuser;
        end

    endgenerate;

    udp_complete_opt #(
        .DATA_WIDTH                (STACK_DATA_WIDTH),
        .ARP_CACHE_ADDR_WIDTH      (9),
        .ARP_REQUEST_RETRY_INTERVAL($rtoi(10**9/STACK_CLK_PERIOD)*2),
        .ARP_REQUEST_TIMEOUT       ($rtoi(10**9/STACK_CLK_PERIOD)*30),
        .ENABLE_DOT1Q_HEADER       (0),
        .HEADER_CHECKSUM_PIPELINED (HEADER_CHECKSUM_PIPELINED),
        .IP_PAYLOAD_FIFO_CHECKSUM  (IP_PAYLOAD_FIFO_CHECKSUM),
        .ARP_ICMP_DATA_WIDTH       (32),
        .ROCE_ICRC_INSERTER        (1),
        .ENABLE_TIMING_OPT_REGS    (ENABLE_TIMING_OPT_REGS)
    ) udp_complete_opt_instance (
        .clk(clk_stack),
        .rst(rst_stack),
        // AXIS from MAC
        .s_network_axis_tdata (s_rx_axis_adapter_tdata),
        .s_network_axis_tkeep (s_rx_axis_adapter_tkeep),
        .s_network_axis_tvalid(s_rx_axis_adapter_tvalid),
        .s_network_axis_tready(s_rx_axis_adapter_tready),
        .s_network_axis_tlast (s_rx_axis_adapter_tlast),
        .s_network_axis_tuser (s_rx_axis_adapter_tuser),
        // AXIS to MAC
        .m_network_axis_tdata (m_tx_axis_adapter_tdata),
        .m_network_axis_tkeep (m_tx_axis_adapter_tkeep),
        .m_network_axis_tvalid(m_tx_axis_adapter_tvalid),
        .m_network_axis_tready(m_tx_axis_adapter_tready),
        .m_network_axis_tlast (m_tx_axis_adapter_tlast),
        .m_network_axis_tuser (m_tx_axis_adapter_tuser),

        // UDP frame input
        .s_udp_hdr_valid          (m_tx_udp_hdr_valid),
        .s_udp_hdr_ready          (m_tx_udp_hdr_ready),
        //.s_udp_ip_dscp            (m_tx_udp_ip_dscp),
        .s_udp_ip_dscp            ({ctrl_priority_tag_reg, 3'd0}),
        .s_udp_ip_ecn             (m_tx_udp_ip_ecn),
        .s_udp_ip_ttl             (m_tx_udp_ip_ttl),
        .s_udp_ip_source_ip       (m_tx_udp_ip_source_ip),
        .s_udp_ip_dest_ip         (m_tx_udp_ip_dest_ip),
        .s_udp_source_port        (m_tx_udp_source_port),
        .s_udp_dest_port          (m_tx_udp_dest_port),
        .s_udp_length             (m_tx_udp_length),
        .s_udp_checksum           (m_tx_udp_checksum),
        .s_udp_payload_axis_tdata (m_tx_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (m_tx_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(m_tx_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready(m_tx_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast (m_tx_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser (m_tx_udp_payload_axis_tuser),
        // UDP frame output
        .m_udp_hdr_valid          (s_rx_udp_hdr_valid),
        .m_udp_hdr_ready          (s_rx_udp_hdr_ready),
        .m_udp_eth_dest_mac       (s_rx_udp_eth_dest_mac),
        .m_udp_eth_src_mac        (s_rx_udp_eth_src_mac),
        .m_udp_eth_type           (s_rx_udp_eth_type),
        .m_udp_ip_version         (s_rx_udp_ip_version),
        .m_udp_ip_ihl             (s_rx_udp_ip_ihl),
        .m_udp_ip_dscp            (s_rx_udp_ip_dscp),
        .m_udp_ip_ecn             (s_rx_udp_ip_ecn),
        .m_udp_ip_length          (s_rx_udp_ip_length),
        .m_udp_ip_identification  (s_rx_udp_ip_identification),
        .m_udp_ip_flags           (s_rx_udp_ip_flags),
        .m_udp_ip_fragment_offset (s_rx_udp_ip_fragment_offset),
        .m_udp_ip_ttl             (s_rx_udp_ip_ttl),
        .m_udp_ip_protocol        (s_rx_udp_ip_protocol),
        .m_udp_ip_header_checksum (s_rx_udp_ip_header_checksum),
        .m_udp_ip_source_ip       (s_rx_udp_ip_source_ip),
        .m_udp_ip_dest_ip         (s_rx_udp_ip_dest_ip),
        .m_udp_source_port        (s_rx_udp_source_port),
        .m_udp_dest_port          (s_rx_udp_dest_port),
        .m_udp_length             (s_rx_udp_length),
        .m_udp_checksum           (s_rx_udp_checksum),
        .m_udp_payload_axis_tdata (s_rx_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (s_rx_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(s_rx_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(s_rx_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast (s_rx_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser (s_rx_udp_payload_axis_tuser),
        // Status signals
        // Configuration
        .local_mac_addr      (ctrl_local_mac_address_reg),
        .local_ip_addr       (ctrl_local_ip_reg),
        .gateway_ip          (gateway_ip),
        .subnet_mask         (subnet_mask),
        .clear_arp_cache     (ctrl_clear_arp_cache_reg),
        .RoCE_udp_port       (ctrl_RoCE_udp_port_reg)
    );

    RoCE_stack_wrapper #(
        .QP_CH_DATA_WIDTH                (QP_CH_DATA_WIDTH),
        .QP_CH_KEEP_ENABLE               (QP_CH_KEEP_ENABLE),
        .QP_CH_KEEP_WIDTH                (QP_CH_KEEP_WIDTH),
        .ROCE_ENG_DATA_WIDTH             (ROCE_ENG_DATA_WIDTH),
        .ROCE_ENG_KEEP_ENABLE            (ROCE_ENG_KEEP_ENABLE),
        .ROCE_ENG_KEEP_WIDTH             (ROCE_ENG_KEEP_WIDTH),
        .OUT_DATA_WIDTH                  (STACK_DATA_WIDTH),
        .OUT_KEEP_ENABLE                 (1),
        .OUT_KEEP_WIDTH                  (STACK_DATA_WIDTH/8),
        .CLOCK_PERIOD                    (ROCE_ENG_CLK_PERIOD),
        .ASYNC_OUTPUT                    (ROCE_ENG_CLK_PERIOD != STACK_CLK_PERIOD),
        .DEBUG                           (DEBUG),
        .REFRESH_CACHE_TICKS             (32767),
        .TARGET_SPEED                    (TARGET_SPEED), // in Gbps
        .RETRANSMISSION_ADDR_BUFFER_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
        .N_ROCE_TX_ENGINES               (N_ROCE_TX_ENGINES),
        .N_QUEUE_PAIRS                   (N_QUEUE_PAIRS), // must be a power of two
        .ENABLE_TIMING_OPT_REGS          (ENABLE_TIMING_OPT_REGS)
    ) RoCE_stack_wrapper_instance (
        .clk_stack(clk_stack),
        .rst_stack(rst_stack),

        .clk_roce_eng(clk_roce_eng),
        .rst_roce_eng(rst_roce_eng),

        .flow_ctrl_pause          (flow_ctrl_pause),

        // clk roce eng  domain
        .s_wr_req_valid           (s_wr_req_valid),
        .s_wr_req_ready           (s_wr_req_ready),
        .s_wr_req_tx_type         (s_wr_req_tx_type),
        .s_wr_req_is_immediate    (s_wr_req_is_immediate),
        .s_wr_req_immediate_data  (s_wr_req_immediate_data),
        .s_wr_req_loc_qp          (s_wr_req_loc_qp),
        .s_wr_req_addr_offset     (s_wr_req_addr_offset),
        .s_wr_req_dma_length      (s_wr_req_dma_length),
        .s_axis_tdata             (s_axis_tdata),
        .s_axis_tkeep             (s_axis_tkeep),
        .s_axis_tvalid            (s_axis_tvalid),
        .s_axis_tready            (s_axis_tready),
        .s_axis_tlast             (s_axis_tlast),
        .s_axis_tuser             (s_axis_tuser),

        // clk stack domain
        .s_udp_hdr_valid          (s_rx_udp_hdr_valid),
        .s_udp_hdr_ready          (s_rx_udp_hdr_ready),
        .s_eth_dest_mac           (0),
        .s_eth_src_mac            (0),
        .s_eth_type               (0),
        .s_ip_version             (0),
        .s_ip_ihl                 (0),
        .s_ip_dscp                (s_rx_udp_ip_dscp),
        .s_ip_ecn                 (s_rx_udp_ip_ecn),
        .s_ip_length              (s_rx_udp_ip_length),
        .s_ip_identification      (0),
        .s_ip_flags               (0),
        .s_ip_fragment_offset     (0),
        .s_ip_ttl                 (s_rx_udp_ip_ttl),
        .s_ip_protocol            (16'h11),
        .s_ip_header_checksum     (0),
        .s_ip_source_ip           (s_rx_udp_ip_source_ip),
        .s_ip_dest_ip             (s_rx_udp_ip_dest_ip),
        .s_udp_source_port        (s_rx_udp_source_port),
        .s_udp_dest_port          (s_rx_udp_dest_port),
        .s_udp_length             (s_rx_udp_length),
        .s_udp_checksum           (s_rx_udp_checksum),
        .s_udp_payload_axis_tdata (s_rx_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (s_rx_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(s_rx_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready(s_rx_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast (s_rx_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser (s_rx_udp_payload_axis_tuser),

        // UDP frame output (TX)
        // clk stack domain
        .m_udp_hdr_valid          (m_tx_udp_hdr_valid),
        .m_udp_hdr_ready          (m_tx_udp_hdr_ready),
        .m_ip_dscp                (m_tx_udp_ip_dscp),
        .m_ip_ecn                 (m_tx_udp_ip_ecn),
        .m_ip_ttl                 (m_tx_udp_ip_ttl),
        .m_ip_source_ip           (m_tx_udp_ip_source_ip),
        .m_ip_dest_ip             (m_tx_udp_ip_dest_ip),
        .m_udp_source_port        (m_tx_udp_source_port),
        .m_udp_dest_port          (m_tx_udp_dest_port),
        .m_udp_length             (m_tx_udp_length),
        .m_udp_checksum           (m_tx_udp_checksum),
        .m_udp_payload_axis_tdata (m_tx_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (m_tx_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_tx_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_tx_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast (m_tx_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser (m_tx_udp_payload_axis_tuser),

        // AXI master interface to RoCE buffers, 1 per RoCE engine
        .m_axi_awid   (m_axi_awid),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awlen  (m_axi_awlen),
        .m_axi_awsize (m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock (m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot (m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wlast  (m_axi_wlast),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bid    (m_axi_bid),
        .m_axi_bresp  (m_axi_bresp),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .m_axi_arid   (m_axi_arid),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arlen  (m_axi_arlen),
        .m_axi_arsize (m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock (m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot (m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid    (m_axi_rid),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rlast  (m_axi_rlast),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready),

        // QP spy output roce engine domain
        .m_qp_spy_context         (m_qp_spy_context),
        .m_qp_spy_loc_qpn         (m_qp_spy_loc_qpn),
        .s_qp_spy_context_valid   (s_qp_spy_context_valid),
        .s_qp_spy_state           (s_qp_spy_state),
        .s_qp_spy_rem_qpn         (s_qp_spy_rem_qpn),
        .s_qp_spy_loc_qpn         (s_qp_spy_loc_qpn),
        .s_qp_spy_rem_psn         (s_qp_spy_rem_psn),
        .s_qp_spy_rem_acked_psn   (s_qp_spy_rem_acked_psn),
        .s_qp_spy_loc_psn         (s_qp_spy_loc_psn),
        .s_qp_spy_r_key           (s_qp_spy_r_key),
        .s_qp_spy_rem_addr        (s_qp_spy_rem_addr),
        .s_qp_spy_rem_ip_addr     (s_qp_spy_rem_ip_addr),
        .s_qp_spy_syndrome        (s_qp_spy_syndrome),

        .pmtu           (ctrl_pmtu_reg),
        .loc_ip_addr    (ctrl_local_ip_reg),
        .timeout_period (ctrl_retry_timeout_reg),
        .use_data_gen   (ctrl_use_data_gen_reg),
        .retry_count    (3'd7),
        .rnr_retry_count(3'd7),
        // dcqcn
        .dcqcn_en            (ctrl_dcqcn_en),
        .dcqcn_par_g         (ctrl_dcqcn_par_g),
        .dcqcn_alpha_min     (ctrl_dcqcn_alpha_min),
        .dcqcn_alpha_upd_time(ctrl_dcqcn_alpha_upd_time),
        .dcqcn_rate_decr_min (ctrl_dcqcn_rate_decr_min),
        .dcqcn_rate_min      (ctrl_dcqcn_rate_min),
        .dcqcn_upd_time      (ctrl_dcqcn_upd_time),
        .dcqcn_rate_ai_time  (ctrl_dcqcn_rate_ai_time),
        .dcqcn_rate_hai_time (ctrl_dcqcn_rate_hai_time),
        .dcqcn_rate_incr_ai  (ctrl_dcqcn_rate_incr_ai),
        .dcqcn_rate_incr_hai (ctrl_dcqcn_rate_incr_hai),

        .cfg_latency_avg_po2      (perf_cfg_latency_avg_po2),
        .monitor_loc_qpn          (perf_monitor_loc_qpn),
        .transfer_time_avg        (perf_transfer_time_avg),
        .cfg_throughput_avg_po2   (perf_cfg_throughput_avg_po2),
        .transfer_time_moving_avg (perf_transfer_time_moving_avg),
        .latency_max              (perf_latency_max),
        .latency_avg              (perf_latency_avg),
        .latency_moving_avg       (perf_latency_moving_avg),
        .psn_diff                 (perf_psn_diff),
        .psn_diff_max             (perf_psn_diff_max),
        .n_retransmit_triggers    (perf_n_retransmit_triggers),
        .n_rnr_retransmit_triggers(perf_n_rnr_retransmit_triggers),
        .n_total_psn_seq_errors   (perf_n_total_psn_seq_errors),
        .n_total_timeout_errors   (perf_n_total_timeout_errors),

        .lat_histo_reset_counts(perf_lat_histo_reset_counts),
        .lat_histo_trgg_readout(perf_lat_histo_trgg_readout),
        .lat_histo_index       (perf_lat_histo_index),
        .lat_histo_valid       (perf_lat_histo_valid),
        .lat_histo_counts      (perf_lat_histo_counts),
        .lat_histo_rst_done    (perf_lat_histo_rst_done),
        .lat_histo_ovflw       (perf_lat_histo_ovflw),

        .adj_ack_histo_reset_counts(perf_adj_ack_histo_reset_counts),
        .adj_ack_histo_trgg_readout(perf_adj_ack_histo_trgg_readout),
        .adj_ack_histo_index       (perf_adj_ack_histo_index),
        .adj_ack_histo_valid       (perf_adj_ack_histo_valid),
        .adj_ack_histo_counts      (perf_adj_ack_histo_counts),
        .adj_ack_histo_rst_done    (perf_adj_ack_histo_rst_done),
        .adj_ack_histo_ovflw       (perf_adj_ack_histo_ovflw)


    );

endmodule

`resetall

