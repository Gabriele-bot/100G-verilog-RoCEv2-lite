`resetall `timescale 1ns / 1ps `default_nettype none


module network_wrapper_roce_generic #(
    parameter MAC_DATA_WIDTH = 1024,
    parameter STACK_DATA_WIDTH = 1024,
    parameter FIFO_REGS = 4,
    parameter ENABLE_PFC = 8'h0,
    parameter DEBUG = 0
) (
    input wire clk_mac,
    input wire rst_mac,

    input wire clk_stack,
    input wire rst_stack,

    /*
     * Ethernet: AXIS
     */

    output wire [MAC_DATA_WIDTH -1 :0]      m_network_tx_axis_tdata,
    output wire [MAC_DATA_WIDTH/8-1 :0 ]    m_network_tx_axis_tkeep,
    output wire                             m_network_tx_axis_tvalid,
    input  wire                             m_network_tx_axis_tready,
    output wire                             m_network_tx_axis_tlast,
    output wire                             m_network_tx_axis_tuser,

    input  wire [MAC_DATA_WIDTH -1 :0]      s_network_rx_axis_tdata,
    input  wire [MAC_DATA_WIDTH/8-1 :0]     s_network_rx_axis_tkeep,
    input  wire                             s_network_rx_axis_tvalid,
    output wire                             s_network_rx_axis_tready,
    input  wire                             s_network_rx_axis_tlast,
    input  wire                             s_network_rx_axis_tuser,
    /*
    Pause signals
    */
    input  wire [7:0]             pfc_pause_req,
    output wire [7:0]             pfc_pause_ack,

    /* 
    QP state spy
    */
    input wire         m_qp_context_spy,
    input wire [23:0]  m_qp_local_qpn_spy,
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
    input wire [47:0] ctrl_local_mac_address, // This should be fixed...
    input wire [31:0] ctrl_local_ip,
    input wire        ctrl_clear_arp_cache,
    input wire [2:0 ] ctrl_pmtu,
    input wire [15:0] ctrl_RoCE_udp_port,
    input wire [2:0 ] ctrl_priority_tag,

    /*
    Status registers
    */
    output wire stat_test
);

    import Board_params::*; // Imports Board parameters
    import RoCE_params::*; // Imports RoCE parameters

    wire [MAC_DATA_WIDTH -1 :0]      s_rx_axis_srl_fifo_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]    s_rx_axis_srl_fifo_tkeep;
    wire                             s_rx_axis_srl_fifo_tvalid;
    wire                             s_rx_axis_srl_fifo_tready;
    wire                             s_rx_axis_srl_fifo_tlast;
    wire                             s_rx_axis_srl_fifo_tuser;

    wire [MAC_DATA_WIDTH -1 :0]      m_tx_axis_srl_fifo_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]    m_tx_axis_srl_fifo_tkeep;
    wire                             m_tx_axis_srl_fifo_tvalid;
    wire                             m_tx_axis_srl_fifo_tready;
    wire                             m_tx_axis_srl_fifo_tlast;
    wire                             m_tx_axis_srl_fifo_tuser;

    wire [MAC_DATA_WIDTH -1 :0]      m_tx_axis_pfc_demux_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]    m_tx_axis_pfc_demux_tkeep;
    wire                             m_tx_axis_pfc_demux_tvalid;
    wire                             m_tx_axis_pfc_demux_tready;
    wire                             m_tx_axis_pfc_demux_tlast;
    wire                             m_tx_axis_pfc_demux_tuser;

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

    // RX Ethernet frame
    wire                             s_rx_eth_hdr_valid;
    wire                             s_rx_eth_hdr_ready;
    wire [ 47:0]                     s_rx_eth_dest_mac;
    wire [ 47:0]                     s_rx_eth_src_mac;
    wire [ 15:0]                     s_rx_eth_type;
    wire [STACK_DATA_WIDTH - 1  :0]  s_rx_eth_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  s_rx_eth_payload_axis_tkeep;
    wire                             s_rx_eth_payload_axis_tvalid;
    wire                             s_rx_eth_payload_axis_tready;
    wire                             s_rx_eth_payload_axis_tlast;
    wire                             s_rx_eth_payload_axis_tuser;

    // TX Ethernet frame
    wire                             m_tx_eth_hdr_valid;
    wire                             m_tx_eth_hdr_ready;
    wire [ 47:0]                     m_tx_eth_dest_mac;
    wire [ 47:0]                     m_tx_eth_src_mac;
    wire [ 15:0]                     m_tx_eth_type;
    wire [STACK_DATA_WIDTH - 1  :0]  m_tx_eth_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  m_tx_eth_payload_axis_tkeep;
    wire                             m_tx_eth_payload_axis_tvalid;
    wire                             m_tx_eth_payload_axis_tready;
    wire                             m_tx_eth_payload_axis_tlast;
    wire                             m_tx_eth_payload_axis_tuser;

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

    // RX UDP frame adapter
    wire                             s_rx_udp_adapter_hdr_valid;
    wire                             s_rx_udp_adapter_hdr_ready;
    wire [ 47:0]                     s_rx_udp_adapter_eth_dest_mac;
    wire [ 47:0]                     s_rx_udp_adapter_eth_src_mac;
    wire [ 15:0]                     s_rx_udp_adapter_eth_type;
    wire [  3:0]                     s_rx_udp_adapter_ip_version;
    wire [  3:0]                     s_rx_udp_adapter_ip_ihl;
    wire [  5:0]                     s_rx_udp_adapter_ip_dscp;
    wire [  1:0]                     s_rx_udp_adapter_ip_ecn;
    wire [ 15:0]                     s_rx_udp_adapter_ip_length;
    wire [ 15:0]                     s_rx_udp_adapter_ip_identification;
    wire [  2:0]                     s_rx_udp_adapter_ip_flags;
    wire [ 12:0]                     s_rx_udp_adapter_ip_fragment_offset;
    wire [  7:0]                     s_rx_udp_adapter_ip_ttl;
    wire [  7:0]                     s_rx_udp_adapter_ip_protocol;
    wire [ 15:0]                     s_rx_udp_adapter_ip_header_checksum;
    wire [ 31:0]                     s_rx_udp_adapter_ip_source_ip;
    wire [ 31:0]                     s_rx_udp_adapter_ip_dest_ip;
    wire [ 15:0]                     s_rx_udp_adapter_source_port;
    wire [ 15:0]                     s_rx_udp_adapter_dest_port;
    wire [ 15:0]                     s_rx_udp_adapter_length;
    wire [ 15:0]                     s_rx_udp_adapter_checksum;
    wire [STACK_DATA_WIDTH - 1  :0]  s_rx_udp_adapter_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  s_rx_udp_adapter_payload_axis_tkeep;
    wire                             s_rx_udp_adapter_payload_axis_tvalid;
    wire                             s_rx_udp_adapter_payload_axis_tready;
    wire                             s_rx_udp_adapter_payload_axis_tlast;
    wire                             s_rx_udp_adapter_payload_axis_tuser;

    // TX UDP 
    wire                             m_tx_udp_adapter_hdr_valid;
    wire                             m_tx_udp_adapter_hdr_ready;
    wire [ 47:0]                     m_tx_udp_adapter_eth_dest_mac;
    wire [ 47:0]                     m_tx_udp_adapter_eth_src_mac;
    wire [ 15:0]                     m_tx_udp_adapter_eth_type;
    wire [  3:0]                     m_tx_udp_adapter_ip_version;
    wire [  3:0]                     m_tx_udp_adapter_ip_ihl;
    wire [  5:0]                     m_tx_udp_adapter_ip_dscp;
    wire [  1:0]                     m_tx_udp_adapter_ip_ecn;
    wire [ 15:0]                     m_tx_udp_adapter_ip_length;
    wire [ 15:0]                     m_tx_udp_adapter_ip_identification;
    wire [  2:0]                     m_tx_udp_adapter_ip_flags;
    wire [ 12:0]                     m_tx_udp_adapter_ip_fragment_offset;
    wire [  7:0]                     m_tx_udp_adapter_ip_ttl;
    wire [  7:0]                     m_tx_udp_adapter_ip_protocol;
    wire [ 15:0]                     m_tx_udp_adapter_ip_header_checksum;
    wire [ 31:0]                     m_tx_udp_adapter_ip_source_ip;
    wire [ 31:0]                     m_tx_udp_adapter_ip_dest_ip;
    wire [ 15:0]                     m_tx_udp_adapter_source_port;
    wire [ 15:0]                     m_tx_udp_adapter_dest_port;
    wire [ 15:0]                     m_tx_udp_adapter_length;
    wire [ 15:0]                     m_tx_udp_adapter_checksum;
    wire [STACK_DATA_WIDTH - 1  :0]  m_tx_udp_adapter_payload_axis_tdata;
    wire [STACK_DATA_WIDTH/8 - 1:0]  m_tx_udp_adapter_payload_axis_tkeep;
    wire                             m_tx_udp_adapter_payload_axis_tvalid;
    wire                             m_tx_udp_adapter_payload_axis_tready;
    wire                             m_tx_udp_adapter_payload_axis_tlast;
    wire                             m_tx_udp_adapter_payload_axis_tuser;

    // Configuration
    wire [31:0] gateway_ip = {ctrl_local_ip[31:8], 8'd1};
    wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0  };




    axis_srl_fifo #(
        .DATA_WIDTH(MAC_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .DEPTH(FIFO_REGS)
    ) rx_axis_srl_fifo (
        .clk(clk_mac),
        .rst(rst_mac),

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

    axis_srl_fifo #(
        .DATA_WIDTH(MAC_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .DEPTH(FIFO_REGS)
    ) tx_axis_srl_fifo (
        .clk(clk_mac),
        .rst(rst_mac),

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

    axis_async_fifo_adapter #(
        .DEPTH(2048),
        .S_DATA_WIDTH(MAC_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(STACK_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) rx_axis_adapter_fifo (
        .s_clk(clk_mac),
        .s_rst(rst_mac),

        // AXI input
        .s_axis_tdata (s_rx_axis_srl_fifo_tdata),
        .s_axis_tkeep (s_rx_axis_srl_fifo_tkeep),
        .s_axis_tvalid(s_rx_axis_srl_fifo_tvalid),
        .s_axis_tready(s_rx_axis_srl_fifo_tready),
        .s_axis_tlast (s_rx_axis_srl_fifo_tlast),
        .s_axis_tuser (s_rx_axis_srl_fifo_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_clk(clk_stack),
        .m_rst(rst_stack),

        // AXI output
        .m_axis_tdata (s_rx_axis_adapter_tdata),
        .m_axis_tkeep (s_rx_axis_adapter_tkeep),
        .m_axis_tvalid(s_rx_axis_adapter_tvalid),
        .m_axis_tready(s_rx_axis_adapter_tready),
        .m_axis_tlast (s_rx_axis_adapter_tlast),
        .m_axis_tuser (s_rx_axis_adapter_tuser)
    );

    generate

        if (ENABLE_PFC != 8'h00) begin

            wire [8*MAC_DATA_WIDTH -1 :0]    m_tx_axis_pfc_priorities_tdata;
            wire [8*MAC_DATA_WIDTH/8-1 :0 ]  m_tx_axis_pfc_priorities_tkeep;
            wire [7:0]                       m_tx_axis_pfc_priorities_tvalid;
            wire [7:0]                       m_tx_axis_pfc_priorities_tready;
            wire [7:0]                       m_tx_axis_pfc_priorities_tlast;
            wire [7:0]                       m_tx_axis_pfc_priorities_tuser;

            wire [2:0] ctrl_priority_tag_sync;

            sync_bit_array #(
                .N(3),
                .BUS_WIDTH(3)
            ) sync_bit_array_instance (
                .src_clk(clk_stack),
                .src_rst(rst_stack),
                .dest_clk(clk_mac),
                .data_in(ctrl_priority_tag),
                .data_out(ctrl_priority_tag_sync)
            );

            axis_demux #(
                .M_COUNT(8),
                .DATA_WIDTH(MAC_DATA_WIDTH),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1)
            ) axis_demux_instance (
                .clk(clk_mac),
                .rst(rst_mac),

                .s_axis_tdata (m_tx_axis_pfc_demux_tdata),
                .s_axis_tkeep (m_tx_axis_pfc_demux_tkeep),
                .s_axis_tvalid(m_tx_axis_pfc_demux_tvalid),
                .s_axis_tready(m_tx_axis_pfc_demux_tready),
                .s_axis_tlast (m_tx_axis_pfc_demux_tlast),
                .s_axis_tuser (m_tx_axis_pfc_demux_tuser),
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
                .select(ctrl_priority_tag_sync)
            );

            eth_pfc_fifo_tx #(
                .DATA_WIDTH(MAC_DATA_WIDTH),
                .FIFO_DEPTH(8192),
                .ENABLE_PRIORITY_MASK(ENABLE_PFC)
            ) eth_pfc_fifo_tx_instance (
                .clk(clk_mac),
                .rst(rst_mac),
                .s_priority_0_axis_tdata (m_tx_axis_pfc_priorities_tdata [0*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_0_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [0*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_0_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[0]),
                .s_priority_0_axis_tready(m_tx_axis_pfc_priorities_tready[0]),
                .s_priority_0_axis_tlast (m_tx_axis_pfc_priorities_tlast [0]),
                .s_priority_0_axis_tuser (m_tx_axis_pfc_priorities_tuser [0]),

                .s_priority_1_axis_tdata (m_tx_axis_pfc_priorities_tdata [1*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_1_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [1*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_1_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[1]),
                .s_priority_1_axis_tready(m_tx_axis_pfc_priorities_tready[1]),
                .s_priority_1_axis_tlast (m_tx_axis_pfc_priorities_tlast [1]),
                .s_priority_1_axis_tuser (m_tx_axis_pfc_priorities_tuser [1]),

                .s_priority_2_axis_tdata (m_tx_axis_pfc_priorities_tdata [2*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_2_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [2*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_2_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[2]),
                .s_priority_2_axis_tready(m_tx_axis_pfc_priorities_tready[2]),
                .s_priority_2_axis_tlast (m_tx_axis_pfc_priorities_tlast [2]),
                .s_priority_2_axis_tuser (m_tx_axis_pfc_priorities_tuser [2]),

                .s_priority_3_axis_tdata (m_tx_axis_pfc_priorities_tdata [3*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_3_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [3*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_3_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[3]),
                .s_priority_3_axis_tready(m_tx_axis_pfc_priorities_tready[3]),
                .s_priority_3_axis_tlast (m_tx_axis_pfc_priorities_tlast [3]),
                .s_priority_3_axis_tuser (m_tx_axis_pfc_priorities_tuser [3]),

                .s_priority_4_axis_tdata (m_tx_axis_pfc_priorities_tdata [4*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_4_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [4*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_4_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[4]),
                .s_priority_4_axis_tready(m_tx_axis_pfc_priorities_tready[4]),
                .s_priority_4_axis_tlast (m_tx_axis_pfc_priorities_tlast [4]),
                .s_priority_4_axis_tuser (m_tx_axis_pfc_priorities_tuser [4]),

                .s_priority_5_axis_tdata (m_tx_axis_pfc_priorities_tdata [5*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_5_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [5*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_5_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[5]),
                .s_priority_5_axis_tready(m_tx_axis_pfc_priorities_tready[5]),
                .s_priority_5_axis_tlast (m_tx_axis_pfc_priorities_tlast [5]),
                .s_priority_5_axis_tuser (m_tx_axis_pfc_priorities_tuser [5]),

                .s_priority_6_axis_tdata (m_tx_axis_pfc_priorities_tdata [6*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_6_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [6*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_6_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[6]),
                .s_priority_6_axis_tready(m_tx_axis_pfc_priorities_tready[6]),
                .s_priority_6_axis_tlast (m_tx_axis_pfc_priorities_tlast [6]),
                .s_priority_6_axis_tuser (m_tx_axis_pfc_priorities_tuser [6]),

                .s_priority_7_axis_tdata (m_tx_axis_pfc_priorities_tdata [7*MAC_DATA_WIDTH+:MAC_DATA_WIDTH]),
                .s_priority_7_axis_tkeep (m_tx_axis_pfc_priorities_tkeep [7*MAC_DATA_WIDTH/8+:MAC_DATA_WIDTH/8]),
                .s_priority_7_axis_tvalid(m_tx_axis_pfc_priorities_tvalid[7]),
                .s_priority_7_axis_tready(m_tx_axis_pfc_priorities_tready[7]),
                .s_priority_7_axis_tlast (m_tx_axis_pfc_priorities_tlast [7]),
                .s_priority_7_axis_tuser (m_tx_axis_pfc_priorities_tuser [7]),

                .m_axis_tdata (m_tx_axis_srl_fifo_tdata),
                .m_axis_tkeep (m_tx_axis_srl_fifo_tkeep),
                .m_axis_tvalid(m_tx_axis_srl_fifo_tvalid),
                .m_axis_tready(m_tx_axis_srl_fifo_tready),
                .m_axis_tlast (m_tx_axis_srl_fifo_tlast),
                .m_axis_tuser (m_tx_axis_srl_fifo_tuser),

                .pause_req(pfc_pause_req),
                .pause_ack(pfc_pause_ack)
            );
        end else begin
            assign m_tx_axis_srl_fifo_tdata   = m_tx_axis_pfc_demux_tdata;
            assign m_tx_axis_srl_fifo_tkeep   = m_tx_axis_pfc_demux_tkeep;
            assign m_tx_axis_srl_fifo_tvalid  = m_tx_axis_pfc_demux_tvalid;
            assign m_tx_axis_pfc_demux_tready = m_tx_axis_srl_fifo_tready;
            assign m_tx_axis_srl_fifo_tlast   = m_tx_axis_pfc_demux_tlast;
            assign m_tx_axis_srl_fifo_tuser   = m_tx_axis_pfc_demux_tuser;

            assign pfc_pause_ack = 8'hFF;
        end

    endgenerate

    axis_async_fifo_adapter #(
        .DEPTH(2048),
        .S_DATA_WIDTH(STACK_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(MAC_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) tx_axis_adapter_fifo (
        .s_clk(clk_stack),
        .s_rst(rst_stack),

        // AXI input
        .s_axis_tdata (m_tx_axis_adapter_tdata),
        .s_axis_tkeep (m_tx_axis_adapter_tkeep),
        .s_axis_tvalid(m_tx_axis_adapter_tvalid),
        .s_axis_tready(m_tx_axis_adapter_tready),
        .s_axis_tlast (m_tx_axis_adapter_tlast),
        .s_axis_tuser (m_tx_axis_adapter_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_clk(clk_mac),
        .m_rst(rst_mac),

        // AXI output
        .m_axis_tdata (m_tx_axis_pfc_demux_tdata),
        .m_axis_tkeep (m_tx_axis_pfc_demux_tkeep),
        .m_axis_tvalid(m_tx_axis_pfc_demux_tvalid),
        .m_axis_tready(m_tx_axis_pfc_demux_tready),
        .m_axis_tlast (m_tx_axis_pfc_demux_tlast),
        .m_axis_tuser (m_tx_axis_pfc_demux_tuser)
    );



    eth_axis_rx #(
    .DATA_WIDTH(STACK_DATA_WIDTH)
    ) eth_axis_rx_inst (
        .clk(clk_stack),
        .rst(rst_stack),
        // AXI input
        .s_axis_tdata (s_rx_axis_adapter_tdata),
        .s_axis_tkeep (s_rx_axis_adapter_tkeep),
        .s_axis_tvalid(s_rx_axis_adapter_tvalid),
        .s_axis_tready(s_rx_axis_adapter_tready),
        .s_axis_tlast (s_rx_axis_adapter_tlast),
        .s_axis_tuser (s_rx_axis_adapter_tuser),
        // Ethernet frame output
        .m_eth_hdr_valid          (s_rx_eth_hdr_valid),
        .m_eth_hdr_ready          (s_rx_eth_hdr_ready),
        .m_eth_dest_mac           (s_rx_eth_dest_mac),
        .m_eth_src_mac            (s_rx_eth_src_mac),
        .m_eth_type               (s_rx_eth_type),
        .m_eth_payload_axis_tdata (s_rx_eth_payload_axis_tdata),
        .m_eth_payload_axis_tkeep (s_rx_eth_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(s_rx_eth_payload_axis_tvalid),
        .m_eth_payload_axis_tready(s_rx_eth_payload_axis_tready),
        .m_eth_payload_axis_tlast (s_rx_eth_payload_axis_tlast),
        .m_eth_payload_axis_tuser (s_rx_eth_payload_axis_tuser),
        // Status signals
        .busy(),
        .error_header_early_termination()
    );


    eth_axis_tx #(
        .DATA_WIDTH(STACK_DATA_WIDTH),
        .ENABLE_DOT1Q_HEADER(0)
    ) eth_axis_tx_inst (
        .clk(clk_stack),
        .rst(rst_stack),
        // Ethernet frame input
        .s_eth_hdr_valid          (m_tx_eth_hdr_valid),
        .s_eth_hdr_ready          (m_tx_eth_hdr_ready),
        .s_eth_dest_mac           (m_tx_eth_dest_mac),
        .s_eth_src_mac            (m_tx_eth_src_mac),
        .s_eth_tpid               (16'h8100),
        .s_eth_pcp                (ctrl_priority_tag),
        .s_eth_dei                (1'b0),
        .s_eth_vid                (12'd10),
        .s_eth_type               (m_tx_eth_type),
        .s_eth_payload_axis_tdata (m_tx_eth_payload_axis_tdata),
        .s_eth_payload_axis_tkeep (m_tx_eth_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(m_tx_eth_payload_axis_tvalid),
        .s_eth_payload_axis_tready(m_tx_eth_payload_axis_tready),
        .s_eth_payload_axis_tlast (m_tx_eth_payload_axis_tlast),
        .s_eth_payload_axis_tuser (m_tx_eth_payload_axis_tuser),
        // AXI output
        .m_axis_tdata (m_tx_axis_adapter_tdata),
        .m_axis_tkeep (m_tx_axis_adapter_tkeep),
        .m_axis_tvalid(m_tx_axis_adapter_tvalid),
        .m_axis_tready(m_tx_axis_adapter_tready),
        .m_axis_tlast (m_tx_axis_adapter_tlast),
        .m_axis_tuser (m_tx_axis_adapter_tuser),
        // Status signals
        .busy()
    );


    udp_complete_test #(
        .DATA_WIDTH(STACK_DATA_WIDTH),
        .UDP_CHECKSUM_GEN_ENABLE(0),
        .ROCE_ICRC_INSERTER(1)
    ) udp_complete_inst (
        .clk(clk_stack),
        .rst(rst_stack),
        // Ethernet frame input
        .s_eth_hdr_valid          (s_rx_eth_hdr_valid),
        .s_eth_hdr_ready          (s_rx_eth_hdr_ready),
        .s_eth_dest_mac           (s_rx_eth_dest_mac),
        .s_eth_src_mac            (s_rx_eth_src_mac),
        .s_eth_type               (s_rx_eth_type),
        .s_eth_payload_axis_tdata (s_rx_eth_payload_axis_tdata),
        .s_eth_payload_axis_tkeep (s_rx_eth_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(s_rx_eth_payload_axis_tvalid),
        .s_eth_payload_axis_tready(s_rx_eth_payload_axis_tready),
        .s_eth_payload_axis_tlast (s_rx_eth_payload_axis_tlast),
        .s_eth_payload_axis_tuser (s_rx_eth_payload_axis_tuser),
        // Ethernet frame output
        .m_eth_hdr_valid          (m_tx_eth_hdr_valid),
        .m_eth_hdr_ready          (m_tx_eth_hdr_ready),
        .m_eth_dest_mac           (m_tx_eth_dest_mac),
        .m_eth_src_mac            (m_tx_eth_src_mac),
        .m_eth_type               (m_tx_eth_type),
        .m_eth_payload_axis_tdata (m_tx_eth_payload_axis_tdata),
        .m_eth_payload_axis_tkeep (m_tx_eth_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(m_tx_eth_payload_axis_tvalid),
        .m_eth_payload_axis_tready(m_tx_eth_payload_axis_tready),
        .m_eth_payload_axis_tlast (m_tx_eth_payload_axis_tlast),
        .m_eth_payload_axis_tuser (m_tx_eth_payload_axis_tuser),
        // IP frame input
        .s_ip_hdr_valid(1'b0),
        .s_ip_hdr_ready(),
        .s_ip_dscp(0),
        .s_ip_ecn(0),
        .s_ip_length(0),
        .s_ip_ttl(0),
        .s_ip_protocol(0),
        .s_ip_source_ip(0),
        .s_ip_dest_ip(0),
        .s_ip_payload_axis_tdata(0),
        .s_ip_payload_axis_tkeep(0),
        .s_ip_payload_axis_tvalid(1'b0),
        .s_ip_payload_axis_tready(),
        .s_ip_payload_axis_tlast(0),
        .s_ip_payload_axis_tuser(0),
        // IP frame output
        .m_ip_hdr_valid(),
        .m_ip_hdr_ready(1'b1),
        .m_ip_eth_dest_mac(),
        .m_ip_eth_src_mac(),
        .m_ip_eth_type(),
        .m_ip_version(),
        .m_ip_ihl(),
        .m_ip_dscp(),
        .m_ip_ecn(),
        .m_ip_length(),
        .m_ip_identification(),
        .m_ip_flags(),
        .m_ip_fragment_offset(),
        .m_ip_ttl(),
        .m_ip_protocol(),
        .m_ip_header_checksum(),
        .m_ip_source_ip(),
        .m_ip_dest_ip(),
        .m_ip_payload_axis_tdata(),
        .m_ip_payload_axis_tkeep(),
        .m_ip_payload_axis_tvalid(),
        .m_ip_payload_axis_tready(1'b1),
        .m_ip_payload_axis_tlast(),
        .m_ip_payload_axis_tuser(),

        // UDP frame input
        .s_udp_hdr_valid          (m_tx_udp_hdr_valid),
        .s_udp_hdr_ready          (m_tx_udp_hdr_ready),
        .s_udp_ip_dscp            (m_tx_udp_ip_dscp),
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
        .ip_rx_busy(),
        .ip_tx_busy(),
        .udp_rx_busy(),
        .udp_tx_busy(),
        .ip_rx_error_header_early_termination(),
        .ip_rx_error_payload_early_termination(),
        .ip_rx_error_invalid_header(),
        .ip_rx_error_invalid_checksum(),
        .ip_tx_error_payload_early_termination(),
        .ip_tx_error_arp_failed(),
        .udp_rx_error_header_early_termination(),
        .udp_rx_error_payload_early_termination(),
        .udp_tx_error_payload_early_termination(),
        // Configuration
        .local_mac      (ctrl_local_mac_address),
        .local_ip       (ctrl_local_ip),
        .gateway_ip     (gateway_ip),
        .subnet_mask    (subnet_mask),
        .clear_arp_cache(ctrl_clear_arp_cache),
        .RoCE_udp_port  (ctrl_RoCE_udp_port)
    );


    RoCE_minimal_stack #(
        .DATA_WIDTH(STACK_DATA_WIDTH),
        .CLOCK_PERIOD(RoCE_CLOCK_PERIOD),
        .DEBUG(DEBUG),
        .RETRANSMISSION(1),
        .RETRANSMISSION_ADDR_BUFFER_WIDTH(22)
    ) RoCE_minimal_stack_instance (
        .clk(clk_stack),
        .rst(rst_stack),
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

        // QP spy output
        .m_qp_context_spy         (m_qp_context_spy),
        .m_qp_local_qpn_spy       (m_qp_local_qpn_spy),
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

        .busy(),
        .error_payload_early_termination(),
        .pmtu           (ctrl_pmtu),
        .RoCE_udp_port  (ctrl_RoCE_udp_port),
        .loc_ip_addr    (ctrl_local_ip),
        .timeout_period (64'd15000), //4.3 ns * 15000 = 64 us
        .retry_count    (3'd7),
        .rnr_retry_count(3'd7)
    );

    generate
        if (DEBUG) begin



            localparam MONITOR_WINDOW_SIZE_BITS = 27;

            wire [MONITOR_WINDOW_SIZE_BITS-1:0] udp_n_valid_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] udp_n_ready_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] udp_n_both_up ;

            axis_handshake_monitor #(
            .window_width(MONITOR_WINDOW_SIZE_BITS)
            ) axis_handshake_monitor_udp (
                .clk(clk_stack),
                .rst(rst_stack),
                .s_axis_tvalid(m_tx_udp_payload_axis_tvalid),
                .m_axis_tready(m_tx_udp_payload_axis_tready),
                .n_valid_up(udp_n_valid_up),
                .n_ready_up(udp_n_ready_up),
                .n_both_up (udp_n_both_up )
            );

            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_in_n_valid_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_in_n_ready_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_in_n_both_up ;

            axis_handshake_monitor #(
            .window_width(MONITOR_WINDOW_SIZE_BITS)
            ) axis_handshake_monitor_eth_in (
                .clk(clk_stack),
                .rst(rst_stack),
                .s_axis_tvalid(m_tx_eth_payload_axis_tvalid),
                .m_axis_tready(m_tx_eth_payload_axis_tready),
                .n_valid_up(eth_in_n_valid_up),
                .n_ready_up(eth_in_n_ready_up),
                .n_both_up (eth_in_n_both_up )
            );

            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_out_n_valid_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_out_n_ready_up;
            wire [MONITOR_WINDOW_SIZE_BITS-1:0] eth_out_n_both_up ;

            axis_handshake_monitor #(
            .window_width(MONITOR_WINDOW_SIZE_BITS)
            ) axis_handshake_monitor_eth_out (
                .clk(clk_stack),
                .rst(rst_stack),
                .s_axis_tvalid(m_tx_axis_adapter_tvalid),
                .m_axis_tready(m_tx_axis_adapter_tready),
                .n_valid_up(eth_out_n_valid_up),
                .n_ready_up(eth_out_n_ready_up),
                .n_both_up (eth_out_n_both_up )
            );

            vio_axis_monitor VIO_axis_monitor_udp_eth (
                .clk(clk_stack),
                .probe_in0(udp_n_valid_up),
                .probe_in1(udp_n_ready_up),
                .probe_in2(udp_n_both_up ),
                .probe_in3(eth_in_n_valid_up),
                .probe_in4(eth_in_n_ready_up),
                .probe_in5(eth_in_n_both_up ),
                .probe_in6(eth_out_n_valid_up),
                .probe_in7(eth_out_n_ready_up),
                .probe_in8(eth_out_n_both_up )
            );

        end
    endgenerate
endmodule

`resetall

