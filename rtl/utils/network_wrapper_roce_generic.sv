`resetall `timescale 1ns / 1ps `default_nettype none


module network_wrapper_roce_generic #(
    parameter MAC_DATA_WIDTH = 1024,
    parameter STACK_DATA_WIDTH = 1024,
    parameter N_ROCE_TX_ENGINES = 1,
    parameter FIFO_REGS = 4,
    parameter ASYNC_MAC_STACK = 1,
    parameter ENABLE_PFC = 0,
    parameter DEBUG = 0
) (
    input wire clk_mac,
    input wire rst_mac,

    input wire clk_stack,
    input wire rst_stack,

    input wire clk_roce_eng,
    input wire rst_roce_eng,

    input wire flow_ctrl_pause, // stack clock domain

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
    input wire [47:0] ctrl_local_mac_address, // Should not be a generic
    input wire [31:0] ctrl_local_ip,
    input wire        ctrl_clear_arp_cache,
    input wire [2:0 ] ctrl_pmtu,
    input wire [15:0] ctrl_RoCE_udp_port,
    input wire [2:0 ] ctrl_priority_tag,

    // perf monitor
    input  wire [3:0]  cfg_latency_avg_po2,
    input  wire [4:0]  cfg_throughput_avg_po2,
    input  wire [23:0] monitor_loc_qpn,
    output wire [31:0] transfer_time_avg,
    output wire [31:0] transfer_time_moving_avg,
    output wire [31:0] latency_avg,
    output wire [31:0] latency_moving_avg,
    output wire [23:0] psn_diff,                 
    output wire [31:0] n_retransmit_triggers,    
    output wire [31:0] n_rnr_retransmit_triggers
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

    wire [MAC_DATA_WIDTH -1 :0]      m_tx_axis_pfc_tdata;
    wire [MAC_DATA_WIDTH/8-1 :0 ]    m_tx_axis_pfc_tkeep;
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

    always @(clk_stack) begin
        ctrl_local_mac_address_reg <= ctrl_local_mac_address;
        ctrl_local_ip_reg          <= ctrl_local_ip;
        ctrl_clear_arp_cache_reg   <= ctrl_clear_arp_cache;
        ctrl_pmtu_reg              <= ctrl_pmtu;
        ctrl_RoCE_udp_port_reg     <= ctrl_RoCE_udp_port;
        ctrl_priority_tag_reg      <= ctrl_priority_tag;
    end
    

    // Configuration
    wire [31:0] gateway_ip = {ctrl_local_ip_reg[31:8], 8'd1};
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



    generate

        if (ENABLE_PFC) begin

            wire [2:0] ctrl_priority_tag_sync;

            xpm_cdc_array_single #(
                .DEST_SYNC_FF(4),
                .INIT_SYNC_FF(0),
                .SIM_ASSERT_CHK(0),
                .SRC_INPUT_REG(1),
                .WIDTH(3)
            ) sync_bit_array_instance (
                .src_clk(clk_stack),
                //.src_rst(rst_stack),
                .dest_clk(clk_mac),
                .src_in(ctrl_priority_tag_reg),
                .dest_out(ctrl_priority_tag_sync)
            );

            localparam OPTIMAL_FIFO_SIZE = (512-1)*MAC_DATA_WIDTH/8; // for 1024b it's around 60kB

            eth_pfc_fifo_tx #(
                .DATA_WIDTH(MAC_DATA_WIDTH),
                // TODO optimize fifo depth, considering that for wider datapath muliple BRAM will be used in parallel
                // And the minimum depth would be 512, so why not use all of them rather than underutilize them
                .FIFO_DEPTH(OPTIMAL_FIFO_SIZE), 
                .OUTPUT_SRL_REG(0)
            ) eth_pfc_fifo_tx_instance (
                .clk(clk_mac),
                .rst(rst_mac),
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

                .priority_tag(ctrl_priority_tag_sync),

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

        if (ASYNC_MAC_STACK) begin
            if (STACK_DATA_WIDTH != MAC_DATA_WIDTH) begin
                axis_async_fifo_adapter #(
                    .DEPTH(1024),
                    .S_DATA_WIDTH(MAC_DATA_WIDTH),
                    .S_KEEP_ENABLE(1),
                    .M_DATA_WIDTH(STACK_DATA_WIDTH),
                    .M_KEEP_ENABLE(1),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
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

                axis_async_fifo_adapter #(
                    .DEPTH(1024),
                    .S_DATA_WIDTH(STACK_DATA_WIDTH),
                    .S_KEEP_ENABLE(1),
                    .M_DATA_WIDTH(MAC_DATA_WIDTH),
                    .M_KEEP_ENABLE(1),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
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
                    .m_axis_tdata (m_tx_axis_pfc_tdata),
                    .m_axis_tkeep (m_tx_axis_pfc_tkeep),
                    .m_axis_tvalid(m_tx_axis_pfc_tvalid),
                    .m_axis_tready(m_tx_axis_pfc_tready),
                    .m_axis_tlast (m_tx_axis_pfc_tlast),
                    .m_axis_tuser (m_tx_axis_pfc_tuser)
                );
            end else begin
                axis_async_fifo #(
                    .DEPTH(1024),
                    .DATA_WIDTH(MAC_DATA_WIDTH),
                    .KEEP_ENABLE(1),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) rx_axis_async_fifo (
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

                axis_async_fifo #(
                    .DEPTH(1024),
                    .DATA_WIDTH(STACK_DATA_WIDTH),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) tx_axis_async_fifo (
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
                    .m_axis_tdata (m_tx_axis_pfc_tdata),
                    .m_axis_tkeep (m_tx_axis_pfc_tkeep),
                    .m_axis_tvalid(m_tx_axis_pfc_tvalid),
                    .m_axis_tready(m_tx_axis_pfc_tready),
                    .m_axis_tlast (m_tx_axis_pfc_tlast),
                    .m_axis_tuser (m_tx_axis_pfc_tuser)
                );
            end
        end else begin // same clock
            if (STACK_DATA_WIDTH != MAC_DATA_WIDTH) begin
                axis_fifo_adapter #(
                    .DEPTH(1024),
                    .S_DATA_WIDTH(MAC_DATA_WIDTH),
                    .S_KEEP_ENABLE(1),
                    .M_DATA_WIDTH(STACK_DATA_WIDTH),
                    .M_KEEP_ENABLE(1),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) rx_axis_adapter_fifo (
                    .clk(clk_mac),
                    .rst(rst_mac),

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

                axis_fifo_adapter #(
                    .DEPTH(1024),
                    .S_DATA_WIDTH(STACK_DATA_WIDTH),
                    .S_KEEP_ENABLE(1),
                    .M_DATA_WIDTH(MAC_DATA_WIDTH),
                    .M_KEEP_ENABLE(1),
                    .ID_ENABLE(0),
                    .DEST_ENABLE(0),
                    .USER_ENABLE(1),
                    .USER_WIDTH(1),
                    .RAM_PIPELINE(2),
                    .FRAME_FIFO(0)
                ) tx_axis_adapter_fifo (
                    .clk(clk_mac),
                    .rst(rst_mac),

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
            end else begin // no need for fifos
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
            end
        end

    endgenerate

    udp_complete_opt #(
        .DATA_WIDTH(STACK_DATA_WIDTH),
        .ARP_CACHE_ADDR_WIDTH(9),
        .ARP_REQUEST_RETRY_INTERVAL(425000000*2),
        .ARP_REQUEST_TIMEOUT(425000000*30),
        .ENABLE_DOT1Q_HEADER(0),
        .HEADER_CHECKSUM_PIPELINED(1),
        .ROCE_ICRC_INSERTER(1)
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
        .QP_CH_DATA_WIDTH                (STACK_DATA_WIDTH/4),
        .QP_CH_KEEP_ENABLE               (1),
        .QP_CH_KEEP_WIDTH                (STACK_DATA_WIDTH/4/8),
        .OUT_DATA_WIDTH                  (STACK_DATA_WIDTH),
        .OUT_KEEP_ENABLE                 (1),
        .OUT_KEEP_WIDTH                  (STACK_DATA_WIDTH/8),
        .CLOCK_PERIOD                    (RoCE_CLOCK_PERIOD),
        .DEBUG                           (DEBUG),
        .REFRESH_CACHE_TICKS             (32767),
        .RETRANSMISSION_ADDR_BUFFER_WIDTH(23),
        .N_ROCE_TX_ENGINES               (N_ROCE_TX_ENGINES),
        .N_QUEUE_PAIRS                   (MAX_QUEUE_PAIRS)
    ) RoCE_stack_wrapper_instance (
        .clk_stack(clk_stack),
        .rst_stack(rst_stack),

        .clk_roce_eng(clk_roce_eng),
        .rst_roce_eng(rst_roce_eng),

        .flow_ctrl_pause          (flow_ctrl_pause),

        // TODO forward these signals outside
        // clk roce eng  domain
        //.s_wr_req_valid           ('{default:0}),          
        //.s_wr_req_ready           (),          
        //.s_wr_req_tx_type         ('{default:0}),        
        //.s_wr_req_is_immediate    ('{default:0}),   
        //.s_wr_req_immediate_data  ('{default:0}), 
        //.s_wr_req_loc_qp          ('{default:0}),         
        //.s_wr_req_addr_offset     ('{default:0}),    
        //.s_wr_req_dma_length      ('{default:0}), 
        //.s_axis_tdata             ('{default:0}),
        //.s_axis_tkeep             ('{default:0}),
        //.s_axis_tvalid            ('{default:0}),
        //.s_axis_tready            (),
        //.s_axis_tlast             ('{default:0}),
        //.s_axis_tuser             ('{default:0}),  

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

        // QP spy output roce engine domain
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

        .pmtu           (ctrl_pmtu_reg),
        .loc_ip_addr    (ctrl_local_ip_reg),
        .timeout_period (64'd15000), //3.3 ns * 15000 = 50 us
        .retry_count    (3'd7),
        .rnr_retry_count(3'd7),

        .cfg_latency_avg_po2      (cfg_latency_avg_po2),
        .monitor_loc_qpn          (monitor_loc_qpn),
        .transfer_time_avg        (transfer_time_avg),
        .cfg_throughput_avg_po2   (cfg_throughput_avg_po2),
        .transfer_time_moving_avg (transfer_time_moving_avg),
        .latency_avg              (latency_avg),
        .latency_moving_avg       (latency_moving_avg),
        .psn_diff                 (psn_diff),
        .n_retransmit_triggers    (n_retransmit_triggers),
        .n_rnr_retransmit_triggers(n_rnr_retransmit_triggers)

    );

endmodule

`resetall

