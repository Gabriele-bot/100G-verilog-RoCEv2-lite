`resetall `timescale 1ns / 1ps `default_nettype none


module network_wrapper_roce_generic #(
    parameter TARGET = "XILINX",
    parameter LOCAL_MAC_ADDRESS = 48'h02_00_00_00_00_00,
    parameter MAC_DATA_WIDTH = 1024,
    parameter UDP_IP_DATA_WIDTH = 1024,
    parameter RoCE_DATA_WIDTH   = UDP_IP_DATA_WIDTH,
    parameter FIFO_REGS = 4,
    parameter DEBUG = 0
) (
    input wire clk_network,
    input wire rst_network,

    input wire clk_udp_ip,
    input wire rst_udp_ip,

    input wire clk_roce,
    input wire rst_roce,

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
    input  wire [8:0]             pause_req,
    output wire [8:0]             pause_ack
);

    import Board_params::*; // Imports Board parameters
    import RoCE_params::*; // Imports RoCE parameters

    wire [MAC_DATA_WIDTH -1 :0]              s_rx_axis_srl_fifo_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]            s_rx_axis_srl_fifo_tkeep;
    wire                                     s_rx_axis_srl_fifo_tvalid;
    wire                                     s_rx_axis_srl_fifo_tready;
    wire                                     s_rx_axis_srl_fifo_tlast;
    wire                                     s_rx_axis_srl_fifo_tuser;

    wire [MAC_DATA_WIDTH -1 :0]              m_tx_axis_srl_fifo_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]            m_tx_axis_srl_fifo_tkeep;
    wire                                     m_tx_axis_srl_fifo_tvalid;
    wire                                     m_tx_axis_srl_fifo_tready;
    wire                                     m_tx_axis_srl_fifo_tlast;
    wire                                     m_tx_axis_srl_fifo_tuser;

    wire [UDP_IP_DATA_WIDTH  -1 :0]          s_rx_axis_adapter_tdata;
    wire [UDP_IP_DATA_WIDTH/8-1 :0]          s_rx_axis_adapter_tkeep;
    wire                                     s_rx_axis_adapter_tvalid;
    wire                                     s_rx_axis_adapter_tready;
    wire                                     s_rx_axis_adapter_tlast;
    wire                                     s_rx_axis_adapter_tuser;

    wire [UDP_IP_DATA_WIDTH  -1 :0]          m_tx_axis_adapter_tdata;
    wire [UDP_IP_DATA_WIDTH/8-1 :0]          m_tx_axis_adapter_tkeep;
    wire                                     m_tx_axis_adapter_tvalid;
    wire                                     m_tx_axis_adapter_tready;
    wire                                     m_tx_axis_adapter_tlast;
    wire                                     m_tx_axis_adapter_tuser;

    // RX Ethernet frame
    wire                                                       s_rx_eth_hdr_valid;
    wire                                                       s_rx_eth_hdr_ready;
    wire [ 47:0]                                               s_rx_eth_dest_mac;
    wire [ 47:0]                                               s_rx_eth_src_mac;
    wire [ 15:0]                                               s_rx_eth_type;
    wire [UDP_IP_DATA_WIDTH - 1  :0]                           s_rx_eth_payload_axis_tdata;
    wire [UDP_IP_DATA_WIDTH/8 - 1:0]                           s_rx_eth_payload_axis_tkeep;
    wire                                                       s_rx_eth_payload_axis_tvalid;
    wire                                                       s_rx_eth_payload_axis_tready;
    wire                                                       s_rx_eth_payload_axis_tlast;
    wire                                                       s_rx_eth_payload_axis_tuser;

    // TX Ethernet frame
    wire                                                       m_tx_eth_hdr_valid;
    wire                                                       m_tx_eth_hdr_ready;
    wire [ 47:0]                                               m_tx_eth_dest_mac;
    wire [ 47:0]                                               m_tx_eth_src_mac;
    wire [ 15:0]                                               m_tx_eth_type;
    wire [UDP_IP_DATA_WIDTH - 1  :0]                           m_tx_eth_payload_axis_tdata;
    wire [UDP_IP_DATA_WIDTH/8 - 1:0]                           m_tx_eth_payload_axis_tkeep;
    wire                                                       m_tx_eth_payload_axis_tvalid;
    wire                                                       m_tx_eth_payload_axis_tready;
    wire                                                       m_tx_eth_payload_axis_tlast;
    wire                                                       m_tx_eth_payload_axis_tuser;

    // RX UDP frame
    wire                                                       s_rx_udp_hdr_valid;
    wire                                                       s_rx_udp_hdr_ready;
    wire [ 47:0]                                               s_rx_udp_eth_dest_mac;
    wire [ 47:0]                                               s_rx_udp_eth_src_mac;
    wire [ 15:0]                                               s_rx_udp_eth_type;
    wire [  3:0]                                               s_rx_udp_ip_version;
    wire [  3:0]                                               s_rx_udp_ip_ihl;
    wire [  5:0]                                               s_rx_udp_ip_dscp;
    wire [  1:0]                                               s_rx_udp_ip_ecn;
    wire [ 15:0]                                               s_rx_udp_ip_length;
    wire [ 15:0]                                               s_rx_udp_ip_identification;
    wire [  2:0]                                               s_rx_udp_ip_flags;
    wire [ 12:0]                                               s_rx_udp_ip_fragment_offset;
    wire [  7:0]                                               s_rx_udp_ip_ttl;
    wire [  7:0]                                               s_rx_udp_ip_protocol;
    wire [ 15:0]                                               s_rx_udp_ip_header_checksum;
    wire [ 31:0]                                               s_rx_udp_ip_source_ip;
    wire [ 31:0]                                               s_rx_udp_ip_dest_ip;
    wire [ 15:0]                                               s_rx_udp_source_port;
    wire [ 15:0]                                               s_rx_udp_dest_port;
    wire [ 15:0]                                               s_rx_udp_length;
    wire [ 15:0]                                               s_rx_udp_checksum;
    wire [UDP_IP_DATA_WIDTH - 1  :0]                           s_rx_udp_payload_axis_tdata;
    wire [UDP_IP_DATA_WIDTH/8 - 1:0]                           s_rx_udp_payload_axis_tkeep;
    wire                                                       s_rx_udp_payload_axis_tvalid;
    wire                                                       s_rx_udp_payload_axis_tready;
    wire                                                       s_rx_udp_payload_axis_tlast;
    wire                                                       s_rx_udp_payload_axis_tuser;

    // TX UDP frame
    wire                                                       m_tx_udp_hdr_valid;
    wire                                                       m_tx_udp_hdr_ready;
    wire [ 47:0]                                               m_tx_udp_eth_dest_mac;
    wire [ 47:0]                                               m_tx_udp_eth_src_mac;
    wire [ 15:0]                                               m_tx_udp_eth_type;
    wire [  3:0]                                               m_tx_udp_ip_version;
    wire [  3:0]                                               m_tx_udp_ip_ihl;
    wire [  5:0]                                               m_tx_udp_ip_dscp;
    wire [  1:0]                                               m_tx_udp_ip_ecn;
    wire [ 15:0]                                               m_tx_udp_ip_length;
    wire [ 15:0]                                               m_tx_udp_ip_identification;
    wire [  2:0]                                               m_tx_udp_ip_flags;
    wire [ 12:0]                                               m_tx_udp_ip_fragment_offset;
    wire [  7:0]                                               m_tx_udp_ip_ttl;
    wire [  7:0]                                               m_tx_udp_ip_protocol;
    wire [ 15:0]                                               m_tx_udp_ip_header_checksum;
    wire [ 31:0]                                               m_tx_udp_ip_source_ip;
    wire [ 31:0]                                               m_tx_udp_ip_dest_ip;
    wire [ 15:0]                                               m_tx_udp_source_port;
    wire [ 15:0]                                               m_tx_udp_dest_port;
    wire [ 15:0]                                               m_tx_udp_length;
    wire [ 15:0]                                               m_tx_udp_checksum;
    wire [UDP_IP_DATA_WIDTH - 1  :0]                           m_tx_udp_payload_axis_tdata;
    wire [UDP_IP_DATA_WIDTH/8 - 1:0]                           m_tx_udp_payload_axis_tkeep;
    wire                                                       m_tx_udp_payload_axis_tvalid;
    wire                                                       m_tx_udp_payload_axis_tready;
    wire                                                       m_tx_udp_payload_axis_tlast;
    wire                                                       m_tx_udp_payload_axis_tuser;

    // RX UDP frame adapter
    wire                                                       s_rx_udp_adapter_hdr_valid;
    wire                                                       s_rx_udp_adapter_hdr_ready;
    wire [ 47:0]                                               s_rx_udp_adapter_eth_dest_mac;
    wire [ 47:0]                                               s_rx_udp_adapter_eth_src_mac;
    wire [ 15:0]                                               s_rx_udp_adapter_eth_type;
    wire [  3:0]                                               s_rx_udp_adapter_ip_version;
    wire [  3:0]                                               s_rx_udp_adapter_ip_ihl;
    wire [  5:0]                                               s_rx_udp_adapter_ip_dscp;
    wire [  1:0]                                               s_rx_udp_adapter_ip_ecn;
    wire [ 15:0]                                               s_rx_udp_adapter_ip_length;
    wire [ 15:0]                                               s_rx_udp_adapter_ip_identification;
    wire [  2:0]                                               s_rx_udp_adapter_ip_flags;
    wire [ 12:0]                                               s_rx_udp_adapter_ip_fragment_offset;
    wire [  7:0]                                               s_rx_udp_adapter_ip_ttl;
    wire [  7:0]                                               s_rx_udp_adapter_ip_protocol;
    wire [ 15:0]                                               s_rx_udp_adapter_ip_header_checksum;
    wire [ 31:0]                                               s_rx_udp_adapter_ip_source_ip;
    wire [ 31:0]                                               s_rx_udp_adapter_ip_dest_ip;
    wire [ 15:0]                                               s_rx_udp_adapter_source_port;
    wire [ 15:0]                                               s_rx_udp_adapter_dest_port;
    wire [ 15:0]                                               s_rx_udp_adapter_length;
    wire [ 15:0]                                               s_rx_udp_adapter_checksum;
    wire [RoCE_DATA_WIDTH - 1  :0]                             s_rx_udp_adapter_payload_axis_tdata;
    wire [RoCE_DATA_WIDTH/8 - 1:0]                             s_rx_udp_adapter_payload_axis_tkeep;
    wire                                                       s_rx_udp_adapter_payload_axis_tvalid;
    wire                                                       s_rx_udp_adapter_payload_axis_tready;
    wire                                                       s_rx_udp_adapter_payload_axis_tlast;
    wire                                                       s_rx_udp_adapter_payload_axis_tuser;

    // TX UDP frame adapter
    wire                                                       m_tx_udp_adapter_hdr_valid;
    wire                                                       m_tx_udp_adapter_hdr_ready;
    wire [ 47:0]                                               m_tx_udp_adapter_eth_dest_mac;
    wire [ 47:0]                                               m_tx_udp_adapter_eth_src_mac;
    wire [ 15:0]                                               m_tx_udp_adapter_eth_type;
    wire [  3:0]                                               m_tx_udp_adapter_ip_version;
    wire [  3:0]                                               m_tx_udp_adapter_ip_ihl;
    wire [  5:0]                                               m_tx_udp_adapter_ip_dscp;
    wire [  1:0]                                               m_tx_udp_adapter_ip_ecn;
    wire [ 15:0]                                               m_tx_udp_adapter_ip_length;
    wire [ 15:0]                                               m_tx_udp_adapter_ip_identification;
    wire [  2:0]                                               m_tx_udp_adapter_ip_flags;
    wire [ 12:0]                                               m_tx_udp_adapter_ip_fragment_offset;
    wire [  7:0]                                               m_tx_udp_adapter_ip_ttl;
    wire [  7:0]                                               m_tx_udp_adapter_ip_protocol;
    wire [ 15:0]                                               m_tx_udp_adapter_ip_header_checksum;
    wire [ 31:0]                                               m_tx_udp_adapter_ip_source_ip;
    wire [ 31:0]                                               m_tx_udp_adapter_ip_dest_ip;
    wire [ 15:0]                                               m_tx_udp_adapter_source_port;
    wire [ 15:0]                                               m_tx_udp_adapter_dest_port;
    wire [ 15:0]                                               m_tx_udp_adapter_length;
    wire [ 15:0]                                               m_tx_udp_adapter_checksum;
    wire [RoCE_DATA_WIDTH - 1  :0]                             m_tx_udp_adapter_payload_axis_tdata;
    wire [RoCE_DATA_WIDTH/8 - 1:0]                             m_tx_udp_adapter_payload_axis_tkeep;
    wire                                                       m_tx_udp_adapter_payload_axis_tvalid;
    wire                                                       m_tx_udp_adapter_payload_axis_tready;
    wire                                                       m_tx_udp_adapter_payload_axis_tlast;
    wire                                                       m_tx_udp_adapter_payload_axis_tuser;




    // Configuration
    wire [31:0] local_ip =  {8'd22, 8'd1, 8'd212, 8'd10  };
    wire [31:0] gateway_ip = {local_ip[31:8], 8'd1};
    wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0  };

    wire clear_arp_cache = 1'b0;

    wire [ 2:0] pmtu = 3'd4;
    wire [15:0] RoCE_udp_port = ROCE_UDP_PORT;
    /*
  vio_roce_ip_cfg vio_roce_ip_cfg_inst (
    .clk(clk),
    .probe_out0(pmtu),
    .probe_out1(RoCE_udp_port),
    .probe_out2(local_ip),
    .probe_out3(clear_arp_cache)
  );
  */


    axis_srl_fifo #(
        .DATA_WIDTH(MAC_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .DEPTH(FIFO_REGS)
    ) rx_axis_srl_fifo (
        .clk(clk_network),
        .rst(rst_network),

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
        .clk(clk_network),
        .rst(rst_network),

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
        .DEPTH(4096),
        .S_DATA_WIDTH(MAC_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) rx_axis_adapter_fifo (
        .s_clk(clk_network),
        .s_rst(rst_network),

        // AXI input
        .s_axis_tdata (s_rx_axis_srl_fifo_tdata),
        .s_axis_tkeep (s_rx_axis_srl_fifo_tkeep),
        .s_axis_tvalid(s_rx_axis_srl_fifo_tvalid),
        .s_axis_tready(s_rx_axis_srl_fifo_tready),
        .s_axis_tlast (s_rx_axis_srl_fifo_tlast),
        .s_axis_tuser (s_rx_axis_srl_fifo_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_clk(clk_udp_ip),
        .m_rst(rst_udp_ip),

        // AXI output
        .m_axis_tdata (s_rx_axis_adapter_tdata),
        .m_axis_tkeep (s_rx_axis_adapter_tkeep),
        .m_axis_tvalid(s_rx_axis_adapter_tvalid),
        .m_axis_tready(s_rx_axis_adapter_tready),
        .m_axis_tlast (s_rx_axis_adapter_tlast),
        .m_axis_tuser (s_rx_axis_adapter_tuser)
    );

    axis_async_fifo_adapter #(
        .DEPTH(4096),
        .S_DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(MAC_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) tx_axis_adapter_fifo (
        .s_clk(clk_udp_ip),
        .s_rst(rst_udp_ip),

        // AXI input
        .s_axis_tdata (m_tx_axis_adapter_tdata),
        .s_axis_tkeep (m_tx_axis_adapter_tkeep),
        .s_axis_tvalid(m_tx_axis_adapter_tvalid),
        .s_axis_tready(m_tx_axis_adapter_tready),
        .s_axis_tlast (m_tx_axis_adapter_tlast),
        .s_axis_tuser (m_tx_axis_adapter_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_clk(clk_network),
        .m_rst(rst_network),

        // AXI output
        .m_axis_tdata (m_tx_axis_srl_fifo_tdata),
        .m_axis_tkeep (m_tx_axis_srl_fifo_tkeep),
        .m_axis_tvalid(m_tx_axis_srl_fifo_tvalid),
        .m_axis_tready(m_tx_axis_srl_fifo_tready),
        .m_axis_tlast (m_tx_axis_srl_fifo_tlast),
        .m_axis_tuser (m_tx_axis_srl_fifo_tuser)
    );



    eth_axis_rx #(
    .DATA_WIDTH(UDP_IP_DATA_WIDTH)
    ) eth_axis_rx_inst (
        .clk(clk_udp_ip),
        .rst(rst_udp_ip),
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
        .DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .ENABLE_DOT1Q_HEADER(0)
    ) eth_axis_tx_inst (
        .clk(clk_udp_ip),
        .rst(rst_udp_ip),
        // Ethernet frame input
        .s_eth_hdr_valid          (m_tx_eth_hdr_valid),
        .s_eth_hdr_ready          (m_tx_eth_hdr_ready),
        .s_eth_dest_mac           (m_tx_eth_dest_mac),
        .s_eth_src_mac            (m_tx_eth_src_mac),
        .s_eth_tpid               (16'h8100),
        .s_eth_pcp                (3'd0),
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
        .DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .UDP_CHECKSUM_GEN_ENABLE(0),
        .ROCE_ICRC_INSERTER(1)
    ) udp_complete_inst (
        .clk(clk_udp_ip),
        .rst(rst_udp_ip),
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
        .local_mac(LOCAL_MAC_ADDRESS),
        .local_ip(local_ip),
        .gateway_ip(gateway_ip),
        .subnet_mask(subnet_mask),
        .clear_arp_cache(clear_arp_cache),
        .RoCE_udp_port(RoCE_udp_port)
    );

    /*
    Cross from UDP_IP domain to RoCE domain
    TODO thin on ho to align header and payload
    */

    /*
    axis_async_fifo #(
        .DEPTH(256),
        .DATA_WIDTH(144),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .LAST_ENABLE(0),
        .USER_ENABLE(0),
        .FRAME_FIFO(0)
    ) udp_tx_header_axis_fifo (
        .s_clk(clk_roce),
        .s_rst(rst_roce),

        // AXI input
        .s_axis_tdata ({tx_udp_ip_dscp, tx_udp_ip_ecn, tx_udp_ip_ttl, tx_udp_ip_source_ip, tx_udp_ip_dest_ip, tx_udp_source_port, tx_udp_dest_port, tx_udp_length,tx_udp_checksum}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(tx_udp_hdr_valid),
        .s_axis_tready(tx_udp_hdr_ready),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_network),
        .m_rst(rst_network),

        // AXI output
        .m_axis_tdata ({tx_udp_1024_ip_dscp, tx_udp_1024_ip_ecn, tx_udp_1024_ip_ttl, tx_udp_1024_ip_source_ip, tx_udp_1024_ip_dest_ip, tx_udp_1024_source_port, tx_udp_1024_dest_port, tx_udp_1024_length,tx_udp_1024_checksum}),
        .m_axis_tvalid(tx_udp_1024_hdr_valid),
        .m_axis_tready(tx_udp_1024_hdr_ready)
    );

    axis_async_fifo_adapter #(
        .DEPTH(8192),
        .S_DATA_WIDTH(RoCE_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) udp_tx_payload_axis_fifo (
        .s_clk(clk_roce),
        .s_rst(rst_roce),

        // AXI input
        .s_axis_tdata (tx_udp_payload_axis_tdata),
        .s_axis_tkeep (tx_udp_payload_axis_tkeep),
        .s_axis_tvalid(tx_udp_payload_axis_tvalid),
        .s_axis_tready(tx_udp_payload_axis_tready),
        .s_axis_tlast (tx_udp_payload_axis_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (tx_udp_payload_axis_tuser),

        .m_clk(clk_network),
        .m_rst(rst_network),

        // AXI output
        .m_axis_tdata (tx_udp_1024_payload_axis_tdata),
        .m_axis_tkeep (tx_udp_1024_payload_axis_tkeep),
        .m_axis_tvalid(tx_udp_1024_payload_axis_tvalid),
        .m_axis_tready(tx_udp_1024_payload_axis_tready),
        .m_axis_tlast (tx_udp_1024_payload_axis_tlast),
        .m_axis_tuser (tx_udp_1024_payload_axis_tuser)
    );

    udp_fifo #(
        .DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .PAYLOAD_FIFO_DEPTH(8192),
        .HEADER_FIFO_DEPTH(8)
    ) tx_udp_fifo_instance (
        .clk(clk_network),
        .rst(rst_network),
        .s_udp_hdr_valid(tx_udp_1024_hdr_valid),
        .s_udp_hdr_ready(tx_udp_1024_hdr_ready),
        .s_eth_dest_mac      (0),
        .s_eth_src_mac       (0),
        .s_eth_type          (0),
        .s_ip_version        (0),
        .s_ip_ihl            (0),
        .s_ip_dscp           (tx_udp_1024_ip_dscp),
        .s_ip_ecn            (tx_udp_1024_ip_ecn),
        .s_ip_length         (0),
        .s_ip_identification (0),
        .s_ip_flags          (0),
        .s_ip_fragment_offset(0),
        .s_ip_ttl            (tx_udp_1024_ip_ttl),
        .s_ip_header_checksum(0),
        .s_ip_source_ip      (tx_udp_1024_ip_source_ip),
        .s_ip_dest_ip        (tx_udp_1024_ip_dest_ip),
        .s_udp_source_port   (tx_udp_1024_source_port),
        .s_udp_dest_port     (tx_udp_1024_dest_port),
        .s_udp_length        (tx_udp_1024_length),
        .s_udp_checksum      (tx_udp_1024_checksum),

        .s_udp_payload_axis_tdata (tx_udp_1024_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (tx_udp_1024_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(tx_udp_1024_payload_axis_tvalid),
        .s_udp_payload_axis_tready(tx_udp_1024_payload_axis_tready),
        .s_udp_payload_axis_tlast (tx_udp_1024_payload_axis_tlast),
        .s_udp_payload_axis_tuser (tx_udp_1024_payload_axis_tuser),

        .m_udp_hdr_valid(tx_udp_1024_align_hdr_valid),
        .m_udp_hdr_ready(tx_udp_1024_align_hdr_ready),
        .m_eth_dest_mac      (),
        .m_eth_src_mac       (),
        .m_eth_type          (),
        .m_ip_version        (),
        .m_ip_ihl            (),
        .m_ip_dscp           (tx_udp_1024_align_ip_dscp),
        .m_ip_ecn            (tx_udp_1024_align_ip_ecn),
        .m_ip_length         (),
        .m_ip_identification (),
        .m_ip_flags          (),
        .m_ip_fragment_offset(),
        .m_ip_ttl            (tx_udp_1024_align_ip_ttl),
        .m_ip_protocol       (),
        .m_ip_header_checksum(),
        .m_ip_source_ip      (tx_udp_1024_align_ip_source_ip),
        .m_ip_dest_ip        (tx_udp_1024_align_ip_dest_ip),
        .m_udp_source_port   (tx_udp_1024_align_source_port),
        .m_udp_dest_port     (tx_udp_1024_align_dest_port),
        .m_udp_length        (tx_udp_1024_align_length),
        .m_udp_checksum      (tx_udp_1024_align_checksum),

        .m_udp_payload_axis_tdata (tx_udp_1024_align_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (tx_udp_1024_align_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(tx_udp_1024_align_payload_axis_tvalid),
        .m_udp_payload_axis_tready(tx_udp_1024_align_payload_axis_tready),
        .m_udp_payload_axis_tlast (tx_udp_1024_align_payload_axis_tlast),
        .m_udp_payload_axis_tuser (tx_udp_1024_align_payload_axis_tuser),

        .busy()
    );

    axis_async_fifo #(
        .DEPTH(256),
        .DATA_WIDTH(144),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .LAST_ENABLE(0),
        .USER_ENABLE(0),
        .FRAME_FIFO(0)
    ) udp_rx_header_axis_fifo (
        .s_clk(clk_network),
        .s_rst(rst_network),

        // AXI input
        .s_axis_tdata ({rx_udp_1024_ip_dscp, rx_udp_1024_ip_ecn, rx_udp_1024_ip_ttl, rx_udp_1024_ip_source_ip, rx_udp_1024_ip_dest_ip, rx_udp_1024_source_port, rx_udp_1024_dest_port, rx_udp_1024_length,rx_udp_1024_checksum}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(rx_udp_1024_hdr_valid),
        .s_axis_tready(rx_udp_1024_hdr_ready),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_roce),
        .m_rst(rst_roce),

        // AXI output
        .m_axis_tdata ({rx_udp_ip_dscp, rx_udp_ip_ecn, rx_udp_ip_ttl, rx_udp_ip_source_ip, rx_udp_ip_dest_ip, rx_udp_source_port, rx_udp_dest_port, rx_udp_length,rx_udp_checksum}),
        .m_axis_tvalid(rx_udp_hdr_valid),
        .m_axis_tready(rx_udp_hdr_ready)
    );

    axis_async_fifo_adapter #(
        .DEPTH(1024),
        .S_DATA_WIDTH(UDP_IP_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .M_DATA_WIDTH(RoCE_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) udp_rx_payload_axis_fifo (
        .s_clk(clk_network),
        .s_rst(rst_network),

        // AXI input
        .s_axis_tdata (rx_udp_1024_payload_axis_tdata),
        .s_axis_tkeep (rx_udp_1024_payload_axis_tkeep),
        .s_axis_tvalid(rx_udp_1024_payload_axis_tvalid),
        .s_axis_tready(rx_udp_1024_payload_axis_tready),
        .s_axis_tlast (rx_udp_1024_payload_axis_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (rx_udp_1024_payload_axis_tuser),

        .m_clk(clk_roce),
        .m_rst(rst_roce),

        // AXI output
        .m_axis_tdata (rx_udp_payload_axis_tdata),
        .m_axis_tkeep (rx_udp_payload_axis_tkeep),
        .m_axis_tvalid(rx_udp_payload_axis_tvalid),
        .m_axis_tready(rx_udp_payload_axis_tready),
        .m_axis_tlast (rx_udp_payload_axis_tlast),
        .m_axis_tuser (rx_udp_payload_axis_tuser)
    );

    udp_fifo #(
        .DATA_WIDTH(RoCE_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .PAYLOAD_FIFO_DEPTH(8192),
        .HEADER_FIFO_DEPTH(8)
    ) rx_udp_fifo_instance (
        .clk(clk_roce),
        .rst(rst_roce),
        .s_udp_hdr_valid(rx_udp_hdr_valid),
        .s_udp_hdr_ready(rx_udp_hdr_ready),
        .s_eth_dest_mac      (0),
        .s_eth_src_mac       (0),
        .s_eth_type          (0),
        .s_ip_version        (0),
        .s_ip_ihl            (0),
        .s_ip_dscp           (rx_udp_ip_dscp),
        .s_ip_ecn            (rx_udp_ip_ecn),
        .s_ip_length         (rx_udp_ip_length),
        .s_ip_identification (0),
        .s_ip_flags          (0),
        .s_ip_fragment_offset(0),
        .s_ip_ttl            (rx_udp_ip_ttl),
        .s_ip_header_checksum(0),
        .s_ip_source_ip      (rx_udp_ip_source_ip),
        .s_ip_dest_ip        (rx_udp_ip_dest_ip),
        .s_udp_source_port   (rx_udp_source_port),
        .s_udp_dest_port     (rx_udp_dest_port),
        .s_udp_length        (rx_udp_length),
        .s_udp_checksum      (rx_udp_checksum),

        .s_udp_payload_axis_tdata (rx_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (rx_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready(rx_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast (rx_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser (rx_udp_payload_axis_tuser),

        .m_udp_hdr_valid(rx_udp_align_hdr_valid),
        .m_udp_hdr_ready(rx_udp_align_hdr_ready),
        .m_eth_dest_mac      (),
        .m_eth_src_mac       (),
        .m_eth_type          (),
        .m_ip_version        (),
        .m_ip_ihl            (),
        .m_ip_dscp           (rx_udp_align_ip_dscp),
        .m_ip_ecn            (rx_udp_align_ip_ecn),
        .m_ip_length         (rx_udp_align_ip_length),
        .m_ip_identification (),
        .m_ip_flags          (),
        .m_ip_fragment_offset(),
        .m_ip_ttl            (rx_udp_align_ip_ttl),
        .m_ip_protocol       (),
        .m_ip_header_checksum(),
        .m_ip_source_ip      (rx_udp_align_ip_source_ip),
        .m_ip_dest_ip        (rx_udp_align_ip_dest_ip),
        .m_udp_source_port   (rx_udp_align_source_port),
        .m_udp_dest_port     (rx_udp_align_dest_port),
        .m_udp_length        (rx_udp_align_length),
        .m_udp_checksum      (rx_udp_align_checksum),

        .m_udp_payload_axis_tdata (rx_udp_align_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (rx_udp_align_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(rx_udp_align_payload_axis_tvalid),
        .m_udp_payload_axis_tready(rx_udp_align_payload_axis_tready),
        .m_udp_payload_axis_tlast (rx_udp_align_payload_axis_tlast),
        .m_udp_payload_axis_tuser (rx_udp_align_payload_axis_tuser),

        .busy()
    );

    */



    RoCE_minimal_stack #(
        .DATA_WIDTH(RoCE_DATA_WIDTH),
        .CLOCK_PERIOD(RoCE_CLOCK_PERIOD),
        .DEBUG(DEBUG),
        .RETRANSMISSION(1),
        .RETRANSMISSION_ADDR_BUFFER_WIDTH(22)
    ) RoCE_minimal_stack_instance (
        .clk(clk_udp_ip),
        .rst(rst_udp_ip),
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

        .busy(),
        .error_payload_early_termination(),
        .pmtu(pmtu),
        .RoCE_udp_port(RoCE_udp_port),
        .loc_ip_addr(local_ip),
        .timeout_period(64'd15000), //4.3 ns * 15000 = 64 us
        .retry_count(3'd7),
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
                .clk(clk_udp_ip),
                .rst(rst_udp_ip),
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
                .clk(clk_udp_ip),
                .rst(rst_udp_ip),
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
                .clk(clk_udp_ip),
                .rst(rst_udp_ip),
                .s_axis_tvalid(m_tx_axis_adapter_tvalid),
                .m_axis_tready(m_tx_axis_adapter_tready),
                .n_valid_up(eth_out_n_valid_up),
                .n_ready_up(eth_out_n_ready_up),
                .n_both_up (eth_out_n_both_up )
            );

            vio_axis_monitor VIO_axis_monitor_udp_eth (
                .clk(clk_udp_ip),
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


            /*
  ila_axis ila_eth_payload_tx(
    .clk(clk_udp_ip),
    .probe0(tx_eth_payload_axis_tdata),
    .probe1(tx_eth_payload_axis_tkeep),
    .probe2(tx_eth_payload_axis_tvalid),
    .probe3(tx_eth_payload_axis_tready),
    .probe4(tx_eth_payload_axis_tlast),
    .probe5(tx_eth_payload_axis_tuser)
  );
  */
        end
    endgenerate
endmodule

`resetall

