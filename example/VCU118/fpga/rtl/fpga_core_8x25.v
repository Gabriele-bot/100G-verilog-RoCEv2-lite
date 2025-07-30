/*

Copyright (c) 2014-2021 Alex Forencich

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
 * FPGA core logic
 */
module fpga_core #
(
    parameter TARGET = "XILINX"
)
(
    /*
     * Clock: 390.625 MHz
     * Synchronous reset
     */
    input  wire [7:0] clk,
    input  wire [7:0] rst,

    /*
     * GPIO
     */
    input  wire       btnu,
    input  wire       btnl,
    input  wire       btnd,
    input  wire       btnr,
    input  wire       btnc,
    input  wire [3:0] sw,
    output wire [7:0] led,

    /*
     * Ethernet: QSFP28
     */
    input  wire        qsfp1_tx_clk_1,
    input  wire        qsfp1_tx_rst_1,
    output wire [63:0] qsfp1_txd_1,
    output wire [7:0]  qsfp1_txc_1,
    input  wire        qsfp1_rx_clk_1,
    input  wire        qsfp1_rx_rst_1,
    input  wire [63:0] qsfp1_rxd_1,
    input  wire [7:0]  qsfp1_rxc_1,
    input  wire        qsfp1_tx_clk_2,
    input  wire        qsfp1_tx_rst_2,
    output wire [63:0] qsfp1_txd_2,
    output wire [7:0]  qsfp1_txc_2,
    input  wire        qsfp1_rx_clk_2,
    input  wire        qsfp1_rx_rst_2,
    input  wire [63:0] qsfp1_rxd_2,
    input  wire [7:0]  qsfp1_rxc_2,
    input  wire        qsfp1_tx_clk_3,
    input  wire        qsfp1_tx_rst_3,
    output wire [63:0] qsfp1_txd_3,
    output wire [7:0]  qsfp1_txc_3,
    input  wire        qsfp1_rx_clk_3,
    input  wire        qsfp1_rx_rst_3,
    input  wire [63:0] qsfp1_rxd_3,
    input  wire [7:0]  qsfp1_rxc_3,
    input  wire        qsfp1_tx_clk_4,
    input  wire        qsfp1_tx_rst_4,
    output wire [63:0] qsfp1_txd_4,
    output wire [7:0]  qsfp1_txc_4,
    input  wire        qsfp1_rx_clk_4,
    input  wire        qsfp1_rx_rst_4,
    input  wire [63:0] qsfp1_rxd_4,
    input  wire [7:0]  qsfp1_rxc_4,
    input  wire        qsfp2_tx_clk_1,
    input  wire        qsfp2_tx_rst_1,
    output wire [63:0] qsfp2_txd_1,
    output wire [7:0]  qsfp2_txc_1,
    input  wire        qsfp2_rx_clk_1,
    input  wire        qsfp2_rx_rst_1,
    input  wire [63:0] qsfp2_rxd_1,
    input  wire [7:0]  qsfp2_rxc_1,
    input  wire        qsfp2_tx_clk_2,
    input  wire        qsfp2_tx_rst_2,
    output wire [63:0] qsfp2_txd_2,
    output wire [7:0]  qsfp2_txc_2,
    input  wire        qsfp2_rx_clk_2,
    input  wire        qsfp2_rx_rst_2,
    input  wire [63:0] qsfp2_rxd_2,
    input  wire [7:0]  qsfp2_rxc_2,
    input  wire        qsfp2_tx_clk_3,
    input  wire        qsfp2_tx_rst_3,
    output wire [63:0] qsfp2_txd_3,
    output wire [7:0]  qsfp2_txc_3,
    input  wire        qsfp2_rx_clk_3,
    input  wire        qsfp2_rx_rst_3,
    input  wire [63:0] qsfp2_rxd_3,
    input  wire [7:0]  qsfp2_rxc_3,
    input  wire        qsfp2_tx_clk_4,
    input  wire        qsfp2_tx_rst_4,
    output wire [63:0] qsfp2_txd_4,
    output wire [7:0]  qsfp2_txc_4,
    input  wire        qsfp2_rx_clk_4,
    input  wire        qsfp2_rx_rst_4,
    input  wire [63:0] qsfp2_rxd_4,
    input  wire [7:0]  qsfp2_rxc_4
);



    // Configuration
    wire [47:0] local_macs [7:0];
    assign local_macs[0] = 48'h00_0A_35_DE_AD_00;
    assign local_macs[1] = 48'h00_0A_35_DE_AD_01;
    assign local_macs[2] = 48'h00_0A_35_DE_AD_02;
    assign local_macs[3] = 48'h00_0A_35_DE_AD_03;
    assign local_macs[4] = 48'h00_0A_35_DE_AD_04;
    assign local_macs[5] = 48'h00_0A_35_DE_AD_05;
    assign local_macs[6] = 48'h00_0A_35_DE_AD_06;
    assign local_macs[7] = 48'h00_0A_35_DE_AD_07;
    //wire [31:0] local_ip    = {8'd22 , 8'd1  , 8'd212, 8'd10 };
    //wire [31:0] gateway_ip  = {8'd22 , 8'd1  , 8'd212, 8'd1  };
    wire [31:0] base_local_ip = {8'd22 , 8'd1  , 8'd212, 8'd10 };
    wire [31:0] local_ips [7:0];
    wire [31:0] gateway_ip;
    wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0  };

    generate
        for (genvar i = 0; i<8; i=i+1) begin
            assign local_ips[i] = base_local_ip + i;
        end
    endgenerate


    assign gateway_ip = {base_local_ip[31:8], 8'd1};

    //assign led = sw;

    wire [63:0] qsfp1_txd [3:0];
    wire [7:0]  qsfp1_txc [3:0];
    wire [63:0] qsfp1_rxd [3:0];
    wire [7:0]  qsfp1_rxc [3:0];

    wire [3:0] qsfp1_tx_clk;
    wire [3:0] qsfp1_rx_clk;

    wire [3:0] qsfp1_tx_rst;
    wire [3:0] qsfp1_rx_rst;

    wire [63:0] qsfp2_txd [3:0];
    wire [7:0]  qsfp2_txc [3:0];
    wire [63:0] qsfp2_rxd [3:0];
    wire [7:0]  qsfp2_rxc [3:0];

    wire [3:0] qsfp2_tx_clk;
    wire [3:0] qsfp2_rx_clk;

    wire [3:0] qsfp2_tx_rst;
    wire [3:0] qsfp2_rx_rst;

    assign qsfp1_txd_1 = qsfp1_txd[0];
    assign qsfp1_txc_1 = qsfp1_txc[0];
    assign qsfp1_txd_2 = qsfp1_txd[1];
    assign qsfp1_txc_2 = qsfp1_txc[1];
    assign qsfp1_txd_3 = qsfp1_txd[2];
    assign qsfp1_txc_3 = qsfp1_txc[2];
    assign qsfp1_txd_4 = qsfp1_txd[3];
    assign qsfp1_txc_4 = qsfp1_txc[3];

    assign  qsfp1_rxd[0] = qsfp1_rxd_1;
    assign  qsfp1_rxc[0] = qsfp1_rxc_1;
    assign  qsfp1_rxd[1] = qsfp1_rxd_2;
    assign  qsfp1_rxc[1] = qsfp1_rxc_2;
    assign  qsfp1_rxd[2] = qsfp1_rxd_3;
    assign  qsfp1_rxc[2] = qsfp1_rxc_3;
    assign  qsfp1_rxd[3] = qsfp1_rxd_4;
    assign  qsfp1_rxc[3] = qsfp1_rxc_4;

    assign qsfp1_tx_clk[0] = qsfp1_tx_clk_1;
    assign qsfp1_rx_clk[0] = qsfp1_rx_clk_1;
    assign qsfp1_tx_clk[1] = qsfp1_tx_clk_2;
    assign qsfp1_rx_clk[1] = qsfp1_rx_clk_2;
    assign qsfp1_tx_clk[2] = qsfp1_tx_clk_3;
    assign qsfp1_rx_clk[2] = qsfp1_rx_clk_3;
    assign qsfp1_tx_clk[3] = qsfp1_tx_clk_4;
    assign qsfp1_rx_clk[3] = qsfp1_rx_clk_4;

    assign qsfp1_tx_rst[0] = qsfp1_tx_rst_1;
    assign qsfp1_rx_rst[0] = qsfp1_rx_rst_1;
    assign qsfp1_tx_rst[1] = qsfp1_tx_rst_2;
    assign qsfp1_rx_rst[1] = qsfp1_rx_rst_2;
    assign qsfp1_tx_rst[2] = qsfp1_tx_rst_3;
    assign qsfp1_rx_rst[2] = qsfp1_rx_rst_3;
    assign qsfp1_tx_rst[3] = qsfp1_tx_rst_4;
    assign qsfp1_rx_rst[3] = qsfp1_rx_rst_4;

    assign qsfp2_txd_1 = qsfp2_txd[0];
    assign qsfp2_txc_1 = qsfp2_txc[0];
    assign qsfp2_txd_2 = qsfp2_txd[1];
    assign qsfp2_txc_2 = qsfp2_txc[1];
    assign qsfp2_txd_3 = qsfp2_txd[2];
    assign qsfp2_txc_3 = qsfp2_txc[2];
    assign qsfp2_txd_4 = qsfp2_txd[3];
    assign qsfp2_txc_4 = qsfp2_txc[3];

    assign  qsfp2_rxd[0] = qsfp2_rxd_1;
    assign  qsfp2_rxc[0] = qsfp2_rxc_1;
    assign  qsfp2_rxd[1] = qsfp2_rxd_2;
    assign  qsfp2_rxc[1] = qsfp2_rxc_2;
    assign  qsfp2_rxd[2] = qsfp2_rxd_3;
    assign  qsfp2_rxc[2] = qsfp2_rxc_3;
    assign  qsfp2_rxd[3] = qsfp2_rxd_4;
    assign  qsfp2_rxc[3] = qsfp2_rxc_4;

    assign qsfp2_tx_clk[0] = qsfp2_tx_clk_1;
    assign qsfp2_rx_clk[0] = qsfp2_rx_clk_1;
    assign qsfp2_tx_clk[1] = qsfp2_tx_clk_2;
    assign qsfp2_rx_clk[1] = qsfp2_rx_clk_2;
    assign qsfp2_tx_clk[2] = qsfp2_tx_clk_3;
    assign qsfp2_rx_clk[2] = qsfp2_rx_clk_3;
    assign qsfp2_tx_clk[3] = qsfp2_tx_clk_4;
    assign qsfp2_rx_clk[3] = qsfp2_rx_clk_4;

    assign qsfp2_tx_rst[0] = qsfp2_tx_rst_1;
    assign qsfp2_rx_rst[0] = qsfp2_rx_rst_1;
    assign qsfp2_tx_rst[1] = qsfp2_tx_rst_2;
    assign qsfp2_rx_rst[1] = qsfp2_rx_rst_2;
    assign qsfp2_tx_rst[2] = qsfp2_tx_rst_3;
    assign qsfp2_rx_rst[2] = qsfp2_rx_rst_3;
    assign qsfp2_tx_rst[3] = qsfp2_tx_rst_4;
    assign qsfp2_rx_rst[3] = qsfp2_rx_rst_4;


    generate
        for (genvar j=0; j<4; j=j+1) begin


            // AXI between MAC and Ethernet modules
            wire [63:0] mac_rx_axis_tdata;
            wire [7:0] mac_rx_axis_tkeep;
            wire mac_rx_axis_tvalid;
            wire mac_rx_axis_tready;
            wire mac_rx_axis_tlast;
            wire mac_rx_axis_tuser;

            wire [63:0] mac_tx_axis_tdata;
            wire [7:0] mac_tx_axis_tkeep;
            wire mac_tx_axis_tvalid;
            wire mac_tx_axis_tready;
            wire mac_tx_axis_tlast;
            wire mac_tx_axis_tuser;

            wire [63:0] rx_axis_tdata;
            wire [7:0] rx_axis_tkeep;
            wire rx_axis_tvalid;
            wire rx_axis_tready;
            wire rx_axis_tlast;
            wire rx_axis_tuser;

            wire [63:0] tx_axis_tdata;
            wire [7:0] tx_axis_tkeep;
            wire tx_axis_tvalid;
            wire tx_axis_tready;
            wire tx_axis_tlast;
            wire tx_axis_tuser;

            // Ethernet frame between Ethernet modules and UDP stack
            wire rx_eth_hdr_ready;
            wire rx_eth_hdr_valid;
            wire [47:0] rx_eth_dest_mac;
            wire [47:0] rx_eth_src_mac;
            wire [15:0] rx_eth_type;
            wire [63:0] rx_eth_payload_axis_tdata;
            wire [7:0] rx_eth_payload_axis_tkeep;
            wire rx_eth_payload_axis_tvalid;
            wire rx_eth_payload_axis_tready;
            wire rx_eth_payload_axis_tlast;
            wire rx_eth_payload_axis_tuser;

            wire tx_eth_hdr_ready;
            wire tx_eth_hdr_valid;
            wire [47:0] tx_eth_dest_mac;
            wire [47:0] tx_eth_src_mac;
            wire [15:0] tx_eth_type;
            wire [63:0] tx_eth_payload_axis_tdata;
            wire [7:0] tx_eth_payload_axis_tkeep;
            wire tx_eth_payload_axis_tvalid;
            wire tx_eth_payload_axis_tready;
            wire tx_eth_payload_axis_tlast;
            wire tx_eth_payload_axis_tuser;

            // IP frame connections
            wire rx_ip_hdr_valid;
            wire rx_ip_hdr_ready;
            wire [47:0] rx_ip_eth_dest_mac;
            wire [47:0] rx_ip_eth_src_mac;
            wire [15:0] rx_ip_eth_type;
            wire [3:0] rx_ip_version;
            wire [3:0] rx_ip_ihl;
            wire [5:0] rx_ip_dscp;
            wire [1:0] rx_ip_ecn;
            wire [15:0] rx_ip_length;
            wire [15:0] rx_ip_identification;
            wire [2:0] rx_ip_flags;
            wire [12:0] rx_ip_fragment_offset;
            wire [7:0] rx_ip_ttl;
            wire [7:0] rx_ip_protocol;
            wire [15:0] rx_ip_header_checksum;
            wire [31:0] rx_ip_source_ip;
            wire [31:0] rx_ip_dest_ip;
            wire [63:0] rx_ip_payload_axis_tdata;
            wire [7:0] rx_ip_payload_axis_tkeep;
            wire rx_ip_payload_axis_tvalid;
            wire rx_ip_payload_axis_tready;
            wire rx_ip_payload_axis_tlast;
            wire rx_ip_payload_axis_tuser;

            wire tx_ip_hdr_valid;
            wire tx_ip_hdr_ready;
            wire [5:0] tx_ip_dscp;
            wire [1:0] tx_ip_ecn;
            wire [15:0] tx_ip_length;
            wire [7:0] tx_ip_ttl;
            wire [7:0] tx_ip_protocol;
            wire [31:0] tx_ip_source_ip;
            wire [31:0] tx_ip_dest_ip;
            wire [63:0] tx_ip_payload_axis_tdata;
            wire [7:0] tx_ip_payload_axis_tkeep;
            wire tx_ip_payload_axis_tvalid;
            wire tx_ip_payload_axis_tready;
            wire tx_ip_payload_axis_tlast;
            wire tx_ip_payload_axis_tuser;

            // UDP frame connections
            wire rx_udp_hdr_valid;
            wire rx_udp_hdr_ready;
            wire [47:0] rx_udp_eth_dest_mac;
            wire [47:0] rx_udp_eth_src_mac;
            wire [15:0] rx_udp_eth_type;
            wire [3:0] rx_udp_ip_version;
            wire [3:0] rx_udp_ip_ihl;
            wire [5:0] rx_udp_ip_dscp;
            wire [1:0] rx_udp_ip_ecn;
            wire [15:0] rx_udp_ip_length;
            wire [15:0] rx_udp_ip_identification;
            wire [2:0] rx_udp_ip_flags;
            wire [12:0] rx_udp_ip_fragment_offset;
            wire [7:0] rx_udp_ip_ttl;
            wire [7:0] rx_udp_ip_protocol;
            wire [15:0] rx_udp_ip_header_checksum;
            wire [31:0] rx_udp_ip_source_ip;
            wire [31:0] rx_udp_ip_dest_ip;
            wire [15:0] rx_udp_source_port;
            wire [15:0] rx_udp_dest_port;
            wire [15:0] rx_udp_length;
            wire [15:0] rx_udp_checksum;
            wire [63:0] rx_udp_payload_axis_tdata;
            wire [7:0] rx_udp_payload_axis_tkeep;
            wire rx_udp_payload_axis_tvalid;
            wire rx_udp_payload_axis_tready;
            wire rx_udp_payload_axis_tlast;
            wire rx_udp_payload_axis_tuser;

            wire tx_udp_hdr_valid;
            wire tx_udp_hdr_ready;
            wire [5:0] tx_udp_ip_dscp;
            wire [1:0] tx_udp_ip_ecn;
            wire [7:0] tx_udp_ip_ttl;
            wire [31:0] tx_udp_ip_source_ip;
            wire [31:0] tx_udp_ip_dest_ip;
            wire [15:0] tx_udp_source_port;
            wire [15:0] tx_udp_dest_port;
            wire [15:0] tx_udp_length;
            wire [15:0] tx_udp_checksum;
            wire [63:0] tx_udp_payload_axis_tdata;
            wire [7:0] tx_udp_payload_axis_tkeep;
            wire tx_udp_payload_axis_tvalid;
            wire tx_udp_payload_axis_tready;
            wire tx_udp_payload_axis_tlast;
            wire tx_udp_payload_axis_tuser;

            // QP state spy
            wire        m_qp_context_spy;
            wire [23:0] m_qp_local_qpn_spy;

            wire        s_qp_spy_context_valid;
            wire [2 :0] s_qp_spy_state;
            wire [23:0] s_qp_spy_rem_qpn;
            wire [23:0] s_qp_spy_loc_qpn;
            wire [23:0] s_qp_spy_rem_psn;
            wire [23:0] s_qp_spy_rem_acked_psn;
            wire [23:0] s_qp_spy_loc_psn;
            wire [31:0] s_qp_spy_r_key;
            wire [63:0] s_qp_spy_rem_addr;
            wire [31:0] s_qp_spy_rem_ip_addr;
            wire [7:0]  s_qp_spy_syndrome;

            vio_qp_state_spy VIO_roce_qp_state_spy (
                .clk(clk[j]),
                .probe_in0 (s_qp_spy_context_valid),
                .probe_in1 (s_qp_spy_state),
                .probe_in2 (s_qp_spy_r_key),
                .probe_in3 (s_qp_spy_rem_qpn),
                .probe_in4 (s_qp_spy_loc_qpn),
                .probe_in5 (s_qp_spy_rem_psn),
                .probe_in6 (s_qp_spy_rem_acked_psn),
                .probe_in7 (s_qp_spy_loc_psn),
                .probe_in8 (s_qp_spy_rem_ip_addr),
                .probe_in9 (s_qp_spy_rem_addr),
                .probe_in10(s_qp_spy_syndrome),
                .probe_out0(m_qp_context_spy),
                .probe_out1(m_qp_local_qpn_spy)
            );


            eth_mac_10g_fifo #(
                .ENABLE_PADDING(1),
                .ENABLE_DIC(1),
                .MIN_FRAME_LENGTH(64),
                .TX_FIFO_DEPTH(4200),
                .TX_FRAME_FIFO(1),
                .RX_FIFO_DEPTH(4200),
                .RX_FRAME_FIFO(1),
                .PFC_ENABLE(1)
            )
            eth_mac_10g_fifo_inst (
                .rx_clk(qsfp1_rx_clk[j]),
                .rx_rst(qsfp1_rx_rst[j]),
                .tx_clk(qsfp1_tx_clk[j]),
                .tx_rst(qsfp1_tx_rst[j]),
                .logic_clk(clk[j]),
                .logic_rst(rst[j]),

                .tx_axis_tdata(mac_tx_axis_tdata),
                .tx_axis_tkeep(mac_tx_axis_tkeep),
                .tx_axis_tvalid(mac_tx_axis_tvalid),
                .tx_axis_tready(mac_tx_axis_tready),
                .tx_axis_tlast(mac_tx_axis_tlast),
                .tx_axis_tuser(mac_tx_axis_tuser),

                .rx_axis_tdata(mac_rx_axis_tdata),
                .rx_axis_tkeep(mac_rx_axis_tkeep),
                .rx_axis_tvalid(mac_rx_axis_tvalid),
                .rx_axis_tready(mac_rx_axis_tready),
                .rx_axis_tlast(mac_rx_axis_tlast),
                .rx_axis_tuser(mac_rx_axis_tuser),

                .xgmii_rxd(qsfp1_rxd[j]),
                .xgmii_rxc(qsfp1_rxc[j]),
                .xgmii_txd(qsfp1_txd[j]),
                .xgmii_txc(qsfp1_txc[j]),

                .tx_fifo_overflow(),
                .tx_fifo_bad_frame(),
                .tx_fifo_good_frame(),
                .rx_error_bad_frame(),
                .rx_error_bad_fcs(),
                .rx_fifo_overflow(),
                .rx_fifo_bad_frame(),
                .rx_fifo_good_frame(),

                .cfg_ifg(8'd12),
                .cfg_tx_enable(1'b1),
                .cfg_rx_enable(1'b1),
                .cfg_local_mac(local_macs[j])
            );


            // AXIS pipeline regs to help timing

            axis_pipeline_register #(
                .DATA_WIDTH(64),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .LENGTH(3)
            ) rx_mac_axis_pipeline (
                .clk(clk[j]),
                .rst(rst[j]),

                // AXI input
                .s_axis_tdata (mac_rx_axis_tdata),
                .s_axis_tkeep (mac_rx_axis_tkeep),
                .s_axis_tvalid(mac_rx_axis_tvalid),
                .s_axis_tready(mac_rx_axis_tready),
                .s_axis_tlast (mac_rx_axis_tlast),
                .s_axis_tuser (mac_rx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (rx_axis_tdata),
                .m_axis_tkeep (rx_axis_tkeep),
                .m_axis_tvalid(rx_axis_tvalid),
                .m_axis_tready(rx_axis_tready),
                .m_axis_tlast (rx_axis_tlast),
                .m_axis_tuser (rx_axis_tuser)
            );

            axis_pipeline_register #(
                .DATA_WIDTH(64),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .LENGTH(3)
            ) tx_mac_axis_pipeline (
                .clk(clk[j]),
                .rst(rst[j]),

                // AXI input
                .s_axis_tdata (tx_axis_tdata),
                .s_axis_tkeep (tx_axis_tkeep),
                .s_axis_tvalid(tx_axis_tvalid),
                .s_axis_tready(tx_axis_tready),
                .s_axis_tlast (tx_axis_tlast),
                .s_axis_tuser (tx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (mac_tx_axis_tdata),
                .m_axis_tkeep (mac_tx_axis_tkeep),
                .m_axis_tvalid(mac_tx_axis_tvalid),
                .m_axis_tready(mac_tx_axis_tready),
                .m_axis_tlast (mac_tx_axis_tlast),
                .m_axis_tuser (mac_tx_axis_tuser)
            );

            eth_axis_rx #(
            .DATA_WIDTH(64)
            )
            eth_axis_rx_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // AXI input
                .s_axis_tdata(rx_axis_tdata),
                .s_axis_tkeep(rx_axis_tkeep),
                .s_axis_tvalid(rx_axis_tvalid),
                .s_axis_tready(rx_axis_tready),
                .s_axis_tlast(rx_axis_tlast),
                .s_axis_tuser(rx_axis_tuser),
                // Ethernet frame output
                .m_eth_hdr_valid(rx_eth_hdr_valid),
                .m_eth_hdr_ready(rx_eth_hdr_ready),
                .m_eth_dest_mac(rx_eth_dest_mac),
                .m_eth_src_mac(rx_eth_src_mac),
                .m_eth_type(rx_eth_type),
                .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
                .m_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
                .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
                .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
                .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
                .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
                // Status signals
                .busy(),
                .error_header_early_termination()
            );

            eth_axis_tx #(
            .DATA_WIDTH(64)
            )
            eth_axis_tx_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // Ethernet frame input
                .s_eth_hdr_valid(tx_eth_hdr_valid),
                .s_eth_hdr_ready(tx_eth_hdr_ready),
                .s_eth_dest_mac(tx_eth_dest_mac),
                .s_eth_src_mac(tx_eth_src_mac),
                .s_eth_type(tx_eth_type),
                .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
                .s_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
                .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
                .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
                .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
                .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
                // AXI output
                .m_axis_tdata(tx_axis_tdata),
                .m_axis_tkeep(tx_axis_tkeep),
                .m_axis_tvalid(tx_axis_tvalid),
                .m_axis_tready(tx_axis_tready),
                .m_axis_tlast(tx_axis_tlast),
                .m_axis_tuser(tx_axis_tuser),
                // Status signals
                .busy()
            );

            udp_complete_test #(
                .DATA_WIDTH(64),
                .UDP_CHECKSUM_GEN_ENABLE(0),
                .ROCE_ICRC_INSERTER(1),
                .IP_HEADER_CHECKSUM_PIPELINED(1)
            ) udp_complete_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // Ethernet frame input
                .s_eth_hdr_valid(rx_eth_hdr_valid),
                .s_eth_hdr_ready(rx_eth_hdr_ready),
                .s_eth_dest_mac(rx_eth_dest_mac),
                .s_eth_src_mac(rx_eth_src_mac),
                .s_eth_type(rx_eth_type),
                .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
                .s_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
                .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
                .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
                .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
                .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
                // Ethernet frame output
                .m_eth_hdr_valid(tx_eth_hdr_valid),
                .m_eth_hdr_ready(tx_eth_hdr_ready),
                .m_eth_dest_mac(tx_eth_dest_mac),
                .m_eth_src_mac(tx_eth_src_mac),
                .m_eth_type(tx_eth_type),
                .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
                .m_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
                .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
                .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
                .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
                .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
                // IP frame input
                .s_ip_hdr_valid(1'b0),
                .s_ip_hdr_ready(tx_ip_hdr_ready),
                .s_ip_dscp(tx_ip_dscp),
                .s_ip_ecn(tx_ip_ecn),
                .s_ip_length(tx_ip_length),
                .s_ip_ttl(tx_ip_ttl),
                .s_ip_protocol(tx_ip_protocol),
                .s_ip_source_ip(tx_ip_source_ip),
                .s_ip_dest_ip(tx_ip_dest_ip),
                .s_ip_payload_axis_tdata(tx_ip_payload_axis_tdata),
                .s_ip_payload_axis_tkeep(tx_ip_payload_axis_tkeep),
                .s_ip_payload_axis_tvalid(1'b0),
                .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
                .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
                .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
                // IP frame output
                .m_ip_hdr_valid(rx_ip_hdr_valid),
                .m_ip_hdr_ready(1'b1),
                .m_ip_eth_dest_mac(rx_ip_eth_dest_mac),
                .m_ip_eth_src_mac(rx_ip_eth_src_mac),
                .m_ip_eth_type(rx_ip_eth_type),
                .m_ip_version(rx_ip_version),
                .m_ip_ihl(rx_ip_ihl),
                .m_ip_dscp(rx_ip_dscp),
                .m_ip_ecn(rx_ip_ecn),
                .m_ip_length(rx_ip_length),
                .m_ip_identification(rx_ip_identification),
                .m_ip_flags(rx_ip_flags),
                .m_ip_fragment_offset(rx_ip_fragment_offset),
                .m_ip_ttl(rx_ip_ttl),
                .m_ip_protocol(rx_ip_protocol),
                .m_ip_header_checksum(rx_ip_header_checksum),
                .m_ip_source_ip(rx_ip_source_ip),
                .m_ip_dest_ip(rx_ip_dest_ip),
                .m_ip_payload_axis_tdata(rx_ip_payload_axis_tdata),
                .m_ip_payload_axis_tkeep(rx_ip_payload_axis_tkeep),
                .m_ip_payload_axis_tvalid(rx_ip_payload_axis_tvalid),
                .m_ip_payload_axis_tready(1'b1),
                .m_ip_payload_axis_tlast(rx_ip_payload_axis_tlast),
                .m_ip_payload_axis_tuser(rx_ip_payload_axis_tuser),
                // UDP frame input
                .s_udp_hdr_valid(tx_udp_hdr_valid),
                .s_udp_hdr_ready(tx_udp_hdr_ready),
                .s_udp_ip_dscp(tx_udp_ip_dscp),
                .s_udp_ip_ecn(tx_udp_ip_ecn),
                .s_udp_ip_ttl(tx_udp_ip_ttl),
                .s_udp_ip_source_ip(tx_udp_ip_source_ip),
                .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
                .s_udp_source_port(tx_udp_source_port),
                .s_udp_dest_port(tx_udp_dest_port),
                .s_udp_length(tx_udp_length),
                .s_udp_checksum(tx_udp_checksum),
                .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
                .s_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
                .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
                .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
                .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
                .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
                // UDP frame output
                .m_udp_hdr_valid(rx_udp_hdr_valid),
                .m_udp_hdr_ready(rx_udp_hdr_ready),
                .m_udp_eth_dest_mac(rx_udp_eth_dest_mac),
                .m_udp_eth_src_mac(rx_udp_eth_src_mac),
                .m_udp_eth_type(rx_udp_eth_type),
                .m_udp_ip_version(rx_udp_ip_version),
                .m_udp_ip_ihl(rx_udp_ip_ihl),
                .m_udp_ip_dscp(rx_udp_ip_dscp),
                .m_udp_ip_ecn(rx_udp_ip_ecn),
                .m_udp_ip_length(rx_udp_ip_length),
                .m_udp_ip_identification(rx_udp_ip_identification),
                .m_udp_ip_flags(rx_udp_ip_flags),
                .m_udp_ip_fragment_offset(rx_udp_ip_fragment_offset),
                .m_udp_ip_ttl(rx_udp_ip_ttl),
                .m_udp_ip_protocol(rx_udp_ip_protocol),
                .m_udp_ip_header_checksum(rx_udp_ip_header_checksum),
                .m_udp_ip_source_ip(rx_udp_ip_source_ip),
                .m_udp_ip_dest_ip(rx_udp_ip_dest_ip),
                .m_udp_source_port(rx_udp_source_port),
                .m_udp_dest_port(rx_udp_dest_port),
                .m_udp_length(rx_udp_length),
                .m_udp_checksum(rx_udp_checksum),
                .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
                .m_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
                .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
                .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
                .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
                .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
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
                .local_mac(local_macs[j]),
                .local_ip(local_ips[j]),
                .gateway_ip(gateway_ip),
                .subnet_mask(subnet_mask),
                .clear_arp_cache(1'b0),
                .RoCE_udp_port(16'h12b7)
            );

            // ROCE TX inst
            RoCE_minimal_stack #(
                .DATA_WIDTH(64),
                .DEBUG(0),
                .CLOCK_PERIOD(1000/390.625),
                .RETRANSMISSION(1),
                .RETRANSMISSION_ADDR_BUFFER_WIDTH(17)
            ) RoCE_minimal_stack_64_instance (
                .clk(clk[j]),
                .rst(rst[j]),
                .s_udp_hdr_valid(rx_udp_hdr_valid),
                .s_udp_hdr_ready(rx_udp_hdr_ready),
                .s_eth_dest_mac(rx_udp_eth_dest_mac),
                .s_eth_src_mac(rx_udp_eth_src_mac),
                .s_eth_type(rx_udp_eth_type),
                .s_ip_version(rx_udp_ip_version),
                .s_ip_ihl(rx_udp_ip_ihl),
                .s_ip_dscp(rx_udp_ip_dscp),
                .s_ip_ecn(rx_udp_ip_ecn),
                .s_ip_length(rx_udp_ip_length),
                .s_ip_identification(rx_udp_ip_identification),
                .s_ip_flags(rx_udp_ip_flags),
                .s_ip_fragment_offset(rx_udp_ip_fragment_offset),
                .s_ip_ttl(rx_udp_ip_ttl),
                .s_ip_protocol(rx_udp_ip_protocol),
                .s_ip_header_checksum(rx_udp_ip_header_checksum),
                .s_ip_source_ip(rx_udp_ip_source_ip),
                .s_ip_dest_ip(rx_udp_ip_dest_ip),
                .s_udp_source_port(rx_udp_source_port),
                .s_udp_dest_port(rx_udp_dest_port),
                .s_udp_length(rx_udp_length),
                .s_udp_checksum(rx_udp_checksum),
                .s_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
                .s_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
                .s_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
                .s_udp_payload_axis_tready(rx_udp_payload_axis_tready),
                .s_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
                .s_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
                .m_udp_hdr_valid(tx_udp_hdr_valid),
                .m_udp_hdr_ready(tx_udp_hdr_ready),
                .m_eth_dest_mac(),
                .m_eth_src_mac(),
                .m_eth_type(),
                .m_ip_version(),
                .m_ip_ihl(),
                .m_ip_dscp(tx_udp_ip_dscp),
                .m_ip_ecn(tx_udp_ip_ecn),
                .m_ip_length(),
                .m_ip_identification(),
                .m_ip_flags(),
                .m_ip_fragment_offset(),
                .m_ip_ttl(tx_udp_ip_ttl),
                .m_ip_protocol(),
                .m_ip_header_checksum(),
                .m_ip_source_ip(tx_udp_ip_source_ip),
                .m_ip_dest_ip(tx_udp_ip_dest_ip),
                .m_udp_source_port(tx_udp_source_port),
                .m_udp_dest_port(tx_udp_dest_port),
                .m_udp_length(tx_udp_length),
                .m_udp_checksum(tx_udp_checksum),
                .m_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
                .m_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
                .m_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
                .m_udp_payload_axis_tready(tx_udp_payload_axis_tready),
                .m_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
                .m_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
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
                .pmtu(3'd4),
                .RoCE_udp_port(16'h12b7),
                .loc_ip_addr(local_ips[j]),
                .timeout_period(64'd13000),
                .retry_count(3'd7),
                .rnr_retry_count(3'd7)
            );

        end

        for (genvar j=4; j<8; j=j+1) begin

            // AXI between MAC and Ethernet modules
            wire [63:0] mac_rx_axis_tdata;
            wire [7:0] mac_rx_axis_tkeep;
            wire mac_rx_axis_tvalid;
            wire mac_rx_axis_tready;
            wire mac_rx_axis_tlast;
            wire mac_rx_axis_tuser;

            wire [63:0] mac_tx_axis_tdata;
            wire [7:0] mac_tx_axis_tkeep;
            wire mac_tx_axis_tvalid;
            wire mac_tx_axis_tready;
            wire mac_tx_axis_tlast;
            wire mac_tx_axis_tuser;

            wire [63:0] rx_axis_tdata;
            wire [7:0] rx_axis_tkeep;
            wire rx_axis_tvalid;
            wire rx_axis_tready;
            wire rx_axis_tlast;
            wire rx_axis_tuser;

            wire [63:0] tx_axis_tdata;
            wire [7:0] tx_axis_tkeep;
            wire tx_axis_tvalid;
            wire tx_axis_tready;
            wire tx_axis_tlast;
            wire tx_axis_tuser;

            // Ethernet frame between Ethernet modules and UDP stack
            wire rx_eth_hdr_ready;
            wire rx_eth_hdr_valid;
            wire [47:0] rx_eth_dest_mac;
            wire [47:0] rx_eth_src_mac;
            wire [15:0] rx_eth_type;
            wire [63:0] rx_eth_payload_axis_tdata;
            wire [7:0] rx_eth_payload_axis_tkeep;
            wire rx_eth_payload_axis_tvalid;
            wire rx_eth_payload_axis_tready;
            wire rx_eth_payload_axis_tlast;
            wire rx_eth_payload_axis_tuser;

            wire tx_eth_hdr_ready;
            wire tx_eth_hdr_valid;
            wire [47:0] tx_eth_dest_mac;
            wire [47:0] tx_eth_src_mac;
            wire [15:0] tx_eth_type;
            wire [63:0] tx_eth_payload_axis_tdata;
            wire [7:0] tx_eth_payload_axis_tkeep;
            wire tx_eth_payload_axis_tvalid;
            wire tx_eth_payload_axis_tready;
            wire tx_eth_payload_axis_tlast;
            wire tx_eth_payload_axis_tuser;

            // IP frame connections
            wire rx_ip_hdr_valid;
            wire rx_ip_hdr_ready;
            wire [47:0] rx_ip_eth_dest_mac;
            wire [47:0] rx_ip_eth_src_mac;
            wire [15:0] rx_ip_eth_type;
            wire [3:0] rx_ip_version;
            wire [3:0] rx_ip_ihl;
            wire [5:0] rx_ip_dscp;
            wire [1:0] rx_ip_ecn;
            wire [15:0] rx_ip_length;
            wire [15:0] rx_ip_identification;
            wire [2:0] rx_ip_flags;
            wire [12:0] rx_ip_fragment_offset;
            wire [7:0] rx_ip_ttl;
            wire [7:0] rx_ip_protocol;
            wire [15:0] rx_ip_header_checksum;
            wire [31:0] rx_ip_source_ip;
            wire [31:0] rx_ip_dest_ip;
            wire [63:0] rx_ip_payload_axis_tdata;
            wire [7:0] rx_ip_payload_axis_tkeep;
            wire rx_ip_payload_axis_tvalid;
            wire rx_ip_payload_axis_tready;
            wire rx_ip_payload_axis_tlast;
            wire rx_ip_payload_axis_tuser;

            wire tx_ip_hdr_valid;
            wire tx_ip_hdr_ready;
            wire [5:0] tx_ip_dscp;
            wire [1:0] tx_ip_ecn;
            wire [15:0] tx_ip_length;
            wire [7:0] tx_ip_ttl;
            wire [7:0] tx_ip_protocol;
            wire [31:0] tx_ip_source_ip;
            wire [31:0] tx_ip_dest_ip;
            wire [63:0] tx_ip_payload_axis_tdata;
            wire [7:0] tx_ip_payload_axis_tkeep;
            wire tx_ip_payload_axis_tvalid;
            wire tx_ip_payload_axis_tready;
            wire tx_ip_payload_axis_tlast;
            wire tx_ip_payload_axis_tuser;

            // UDP frame connections
            wire rx_udp_hdr_valid;
            wire rx_udp_hdr_ready;
            wire [47:0] rx_udp_eth_dest_mac;
            wire [47:0] rx_udp_eth_src_mac;
            wire [15:0] rx_udp_eth_type;
            wire [3:0] rx_udp_ip_version;
            wire [3:0] rx_udp_ip_ihl;
            wire [5:0] rx_udp_ip_dscp;
            wire [1:0] rx_udp_ip_ecn;
            wire [15:0] rx_udp_ip_length;
            wire [15:0] rx_udp_ip_identification;
            wire [2:0] rx_udp_ip_flags;
            wire [12:0] rx_udp_ip_fragment_offset;
            wire [7:0] rx_udp_ip_ttl;
            wire [7:0] rx_udp_ip_protocol;
            wire [15:0] rx_udp_ip_header_checksum;
            wire [31:0] rx_udp_ip_source_ip;
            wire [31:0] rx_udp_ip_dest_ip;
            wire [15:0] rx_udp_source_port;
            wire [15:0] rx_udp_dest_port;
            wire [15:0] rx_udp_length;
            wire [15:0] rx_udp_checksum;
            wire [63:0] rx_udp_payload_axis_tdata;
            wire [7:0] rx_udp_payload_axis_tkeep;
            wire rx_udp_payload_axis_tvalid;
            wire rx_udp_payload_axis_tready;
            wire rx_udp_payload_axis_tlast;
            wire rx_udp_payload_axis_tuser;

            wire tx_udp_hdr_valid;
            wire tx_udp_hdr_ready;
            wire [5:0] tx_udp_ip_dscp;
            wire [1:0] tx_udp_ip_ecn;
            wire [7:0] tx_udp_ip_ttl;
            wire [31:0] tx_udp_ip_source_ip;
            wire [31:0] tx_udp_ip_dest_ip;
            wire [15:0] tx_udp_source_port;
            wire [15:0] tx_udp_dest_port;
            wire [15:0] tx_udp_length;
            wire [15:0] tx_udp_checksum;
            wire [63:0] tx_udp_payload_axis_tdata;
            wire [7:0] tx_udp_payload_axis_tkeep;
            wire tx_udp_payload_axis_tvalid;
            wire tx_udp_payload_axis_tready;
            wire tx_udp_payload_axis_tlast;
            wire tx_udp_payload_axis_tuser;

            // QP state spy
            wire        m_qp_context_spy;
            wire [23:0] m_qp_local_qpn_spy;

            wire        s_qp_spy_context_valid;
            wire [2 :0] s_qp_spy_state;
            wire [23:0] s_qp_spy_rem_qpn;
            wire [23:0] s_qp_spy_loc_qpn;
            wire [23:0] s_qp_spy_rem_psn;
            wire [23:0] s_qp_spy_rem_acked_psn;
            wire [23:0] s_qp_spy_loc_psn;
            wire [31:0] s_qp_spy_r_key;
            wire [63:0] s_qp_spy_rem_addr;
            wire [31:0] s_qp_spy_rem_ip_addr;
            wire [7:0]  s_qp_spy_syndrome;


            eth_mac_10g_fifo #(
                .ENABLE_PADDING(1),
                .ENABLE_DIC(1),
                .MIN_FRAME_LENGTH(64),
                .TX_FIFO_DEPTH(4200),
                .TX_FRAME_FIFO(1),
                .RX_FIFO_DEPTH(4200),
                .RX_FRAME_FIFO(1),
                .PFC_ENABLE(1)
            )
            eth_mac_10g_fifo_inst (
                .rx_clk(qsfp2_rx_clk[j-4]),
                .rx_rst(qsfp2_rx_rst[j-4]),
                .tx_clk(qsfp2_tx_clk[j-4]),
                .tx_rst(qsfp2_tx_rst[j-4]),
                .logic_clk(clk[j]),
                .logic_rst(rst[j]),

                .tx_axis_tdata(mac_tx_axis_tdata),
                .tx_axis_tkeep(mac_tx_axis_tkeep),
                .tx_axis_tvalid(mac_tx_axis_tvalid),
                .tx_axis_tready(mac_tx_axis_tready),
                .tx_axis_tlast(mac_tx_axis_tlast),
                .tx_axis_tuser(mac_tx_axis_tuser),

                .rx_axis_tdata(mac_rx_axis_tdata),
                .rx_axis_tkeep(mac_rx_axis_tkeep),
                .rx_axis_tvalid(mac_rx_axis_tvalid),
                .rx_axis_tready(mac_rx_axis_tready),
                .rx_axis_tlast(mac_rx_axis_tlast),
                .rx_axis_tuser(mac_rx_axis_tuser),

                .xgmii_rxd(qsfp2_rxd[j-4]),
                .xgmii_rxc(qsfp2_rxc[j-4]),
                .xgmii_txd(qsfp2_txd[j-4]),
                .xgmii_txc(qsfp2_txc[j-4]),

                .tx_fifo_overflow(),
                .tx_fifo_bad_frame(),
                .tx_fifo_good_frame(),
                .rx_error_bad_frame(),
                .rx_error_bad_fcs(),
                .rx_fifo_overflow(),
                .rx_fifo_bad_frame(),
                .rx_fifo_good_frame(),

                .cfg_ifg(8'd12),
                .cfg_tx_enable(1'b1),
                .cfg_rx_enable(1'b1),
                .cfg_local_mac(local_macs[j])
            );



            axis_pipeline_register #(
                .DATA_WIDTH(64),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .LENGTH(3)
            ) rx_mac_axis_pipeline (
                .clk(clk[j]),
                .rst(rst[j]),

                // AXI input
                .s_axis_tdata (mac_rx_axis_tdata),
                .s_axis_tkeep (mac_rx_axis_tkeep),
                .s_axis_tvalid(mac_rx_axis_tvalid),
                .s_axis_tready(mac_rx_axis_tready),
                .s_axis_tlast (mac_rx_axis_tlast),
                .s_axis_tuser (mac_rx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (rx_axis_tdata),
                .m_axis_tkeep (rx_axis_tkeep),
                .m_axis_tvalid(rx_axis_tvalid),
                .m_axis_tready(rx_axis_tready),
                .m_axis_tlast (rx_axis_tlast),
                .m_axis_tuser (rx_axis_tuser)
            );

            axis_pipeline_register #(
                .DATA_WIDTH(64),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .LENGTH(3)
            ) tx_mac_axis_pipeline(
                .clk(clk[j]),
                .rst(rst[j]),

                // AXI input
                .s_axis_tdata (tx_axis_tdata),
                .s_axis_tkeep (tx_axis_tkeep),
                .s_axis_tvalid(tx_axis_tvalid),
                .s_axis_tready(tx_axis_tready),
                .s_axis_tlast (tx_axis_tlast),
                .s_axis_tuser (tx_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (mac_tx_axis_tdata),
                .m_axis_tkeep (mac_tx_axis_tkeep),
                .m_axis_tvalid(mac_tx_axis_tvalid),
                .m_axis_tready(mac_tx_axis_tready),
                .m_axis_tlast (mac_tx_axis_tlast),
                .m_axis_tuser (mac_tx_axis_tuser)
            );

            eth_axis_rx #(
            .DATA_WIDTH(64)
            )
            eth_axis_rx_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // AXI input
                .s_axis_tdata(rx_axis_tdata),
                .s_axis_tkeep(rx_axis_tkeep),
                .s_axis_tvalid(rx_axis_tvalid),
                .s_axis_tready(rx_axis_tready),
                .s_axis_tlast(rx_axis_tlast),
                .s_axis_tuser(rx_axis_tuser),
                // Ethernet frame output
                .m_eth_hdr_valid(rx_eth_hdr_valid),
                .m_eth_hdr_ready(rx_eth_hdr_ready),
                .m_eth_dest_mac(rx_eth_dest_mac),
                .m_eth_src_mac(rx_eth_src_mac),
                .m_eth_type(rx_eth_type),
                .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
                .m_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
                .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
                .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
                .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
                .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
                // Status signals
                .busy(),
                .error_header_early_termination()
            );

            eth_axis_tx #(
            .DATA_WIDTH(64)
            )
            eth_axis_tx_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // Ethernet frame input
                .s_eth_hdr_valid(tx_eth_hdr_valid),
                .s_eth_hdr_ready(tx_eth_hdr_ready),
                .s_eth_dest_mac(tx_eth_dest_mac),
                .s_eth_src_mac(tx_eth_src_mac),
                .s_eth_type(tx_eth_type),
                .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
                .s_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
                .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
                .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
                .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
                .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
                // AXI output
                .m_axis_tdata(tx_axis_tdata),
                .m_axis_tkeep(tx_axis_tkeep),
                .m_axis_tvalid(tx_axis_tvalid),
                .m_axis_tready(tx_axis_tready),
                .m_axis_tlast(tx_axis_tlast),
                .m_axis_tuser(tx_axis_tuser),
                // Status signals
                .busy()
            );

            udp_complete_test #(
                .DATA_WIDTH(64),
                .UDP_CHECKSUM_GEN_ENABLE(0),
                .ROCE_ICRC_INSERTER(1),
                .IP_HEADER_CHECKSUM_PIPELINED(1)
            ) udp_complete_inst (
                .clk(clk[j]),
                .rst(rst[j]),
                // Ethernet frame input
                .s_eth_hdr_valid(rx_eth_hdr_valid),
                .s_eth_hdr_ready(rx_eth_hdr_ready),
                .s_eth_dest_mac(rx_eth_dest_mac),
                .s_eth_src_mac(rx_eth_src_mac),
                .s_eth_type(rx_eth_type),
                .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
                .s_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
                .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
                .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
                .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
                .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
                // Ethernet frame output
                .m_eth_hdr_valid(tx_eth_hdr_valid),
                .m_eth_hdr_ready(tx_eth_hdr_ready),
                .m_eth_dest_mac(tx_eth_dest_mac),
                .m_eth_src_mac(tx_eth_src_mac),
                .m_eth_type(tx_eth_type),
                .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
                .m_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
                .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
                .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
                .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
                .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
                // IP frame input
                .s_ip_hdr_valid(1'b0),
                .s_ip_hdr_ready(tx_ip_hdr_ready),
                .s_ip_dscp(tx_ip_dscp),
                .s_ip_ecn(tx_ip_ecn),
                .s_ip_length(tx_ip_length),
                .s_ip_ttl(tx_ip_ttl),
                .s_ip_protocol(tx_ip_protocol),
                .s_ip_source_ip(tx_ip_source_ip),
                .s_ip_dest_ip(tx_ip_dest_ip),
                .s_ip_payload_axis_tdata(tx_ip_payload_axis_tdata),
                .s_ip_payload_axis_tkeep(tx_ip_payload_axis_tkeep),
                .s_ip_payload_axis_tvalid(1'b0),
                .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
                .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
                .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
                // IP frame output
                .m_ip_hdr_valid(rx_ip_hdr_valid),
                .m_ip_hdr_ready(1'b1),
                .m_ip_eth_dest_mac(rx_ip_eth_dest_mac),
                .m_ip_eth_src_mac(rx_ip_eth_src_mac),
                .m_ip_eth_type(rx_ip_eth_type),
                .m_ip_version(rx_ip_version),
                .m_ip_ihl(rx_ip_ihl),
                .m_ip_dscp(rx_ip_dscp),
                .m_ip_ecn(rx_ip_ecn),
                .m_ip_length(rx_ip_length),
                .m_ip_identification(rx_ip_identification),
                .m_ip_flags(rx_ip_flags),
                .m_ip_fragment_offset(rx_ip_fragment_offset),
                .m_ip_ttl(rx_ip_ttl),
                .m_ip_protocol(rx_ip_protocol),
                .m_ip_header_checksum(rx_ip_header_checksum),
                .m_ip_source_ip(rx_ip_source_ip),
                .m_ip_dest_ip(rx_ip_dest_ip),
                .m_ip_payload_axis_tdata(rx_ip_payload_axis_tdata),
                .m_ip_payload_axis_tkeep(rx_ip_payload_axis_tkeep),
                .m_ip_payload_axis_tvalid(rx_ip_payload_axis_tvalid),
                .m_ip_payload_axis_tready(1'b1),
                .m_ip_payload_axis_tlast(rx_ip_payload_axis_tlast),
                .m_ip_payload_axis_tuser(rx_ip_payload_axis_tuser),
                // UDP frame input
                .s_udp_hdr_valid(tx_udp_hdr_valid),
                .s_udp_hdr_ready(tx_udp_hdr_ready),
                .s_udp_ip_dscp(tx_udp_ip_dscp),
                .s_udp_ip_ecn(tx_udp_ip_ecn),
                .s_udp_ip_ttl(tx_udp_ip_ttl),
                .s_udp_ip_source_ip(tx_udp_ip_source_ip),
                .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
                .s_udp_source_port(tx_udp_source_port),
                .s_udp_dest_port(tx_udp_dest_port),
                .s_udp_length(tx_udp_length),
                .s_udp_checksum(tx_udp_checksum),
                .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
                .s_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
                .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
                .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
                .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
                .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
                // UDP frame output
                .m_udp_hdr_valid(rx_udp_hdr_valid),
                .m_udp_hdr_ready(rx_udp_hdr_ready),
                .m_udp_eth_dest_mac(rx_udp_eth_dest_mac),
                .m_udp_eth_src_mac(rx_udp_eth_src_mac),
                .m_udp_eth_type(rx_udp_eth_type),
                .m_udp_ip_version(rx_udp_ip_version),
                .m_udp_ip_ihl(rx_udp_ip_ihl),
                .m_udp_ip_dscp(rx_udp_ip_dscp),
                .m_udp_ip_ecn(rx_udp_ip_ecn),
                .m_udp_ip_length(rx_udp_ip_length),
                .m_udp_ip_identification(rx_udp_ip_identification),
                .m_udp_ip_flags(rx_udp_ip_flags),
                .m_udp_ip_fragment_offset(rx_udp_ip_fragment_offset),
                .m_udp_ip_ttl(rx_udp_ip_ttl),
                .m_udp_ip_protocol(rx_udp_ip_protocol),
                .m_udp_ip_header_checksum(rx_udp_ip_header_checksum),
                .m_udp_ip_source_ip(rx_udp_ip_source_ip),
                .m_udp_ip_dest_ip(rx_udp_ip_dest_ip),
                .m_udp_source_port(rx_udp_source_port),
                .m_udp_dest_port(rx_udp_dest_port),
                .m_udp_length(rx_udp_length),
                .m_udp_checksum(rx_udp_checksum),
                .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
                .m_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
                .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
                .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
                .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
                .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
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
                .local_mac(local_macs[j]),
                .local_ip(local_ips[j]),
                .gateway_ip(gateway_ip),
                .subnet_mask(subnet_mask),
                .clear_arp_cache(1'b0),
                .RoCE_udp_port(16'h12b7)
            );

            // ROCE TX inst
            RoCE_minimal_stack #(
                .DATA_WIDTH(64),
                .DEBUG(0),
                .CLOCK_PERIOD(1000/390.625),
                .RETRANSMISSION(1),
                .RETRANSMISSION_ADDR_BUFFER_WIDTH(17) // 2**18 * 8 bits / 25Gbps = 83 us of buffering (best case scenario, every frame is full)
            ) RoCE_minimal_stack_64_instance (
                .clk(clk[j]),
                .rst(rst[j]),
                .s_udp_hdr_valid(rx_udp_hdr_valid),
                .s_udp_hdr_ready(rx_udp_hdr_ready),
                .s_eth_dest_mac(rx_udp_eth_dest_mac),
                .s_eth_src_mac(rx_udp_eth_src_mac),
                .s_eth_type(rx_udp_eth_type),
                .s_ip_version(rx_udp_ip_version),
                .s_ip_ihl(rx_udp_ip_ihl),
                .s_ip_dscp(rx_udp_ip_dscp),
                .s_ip_ecn(rx_udp_ip_ecn),
                .s_ip_length(rx_udp_ip_length),
                .s_ip_identification(rx_udp_ip_identification),
                .s_ip_flags(rx_udp_ip_flags),
                .s_ip_fragment_offset(rx_udp_ip_fragment_offset),
                .s_ip_ttl(rx_udp_ip_ttl),
                .s_ip_protocol(rx_udp_ip_protocol),
                .s_ip_header_checksum(rx_udp_ip_header_checksum),
                .s_ip_source_ip(rx_udp_ip_source_ip),
                .s_ip_dest_ip(rx_udp_ip_dest_ip),
                .s_udp_source_port(rx_udp_source_port),
                .s_udp_dest_port(rx_udp_dest_port),
                .s_udp_length(rx_udp_length),
                .s_udp_checksum(rx_udp_checksum),
                .s_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
                .s_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
                .s_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
                .s_udp_payload_axis_tready(rx_udp_payload_axis_tready),
                .s_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
                .s_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
                .m_udp_hdr_valid(tx_udp_hdr_valid),
                .m_udp_hdr_ready(tx_udp_hdr_ready),
                .m_eth_dest_mac(),
                .m_eth_src_mac(),
                .m_eth_type(),
                .m_ip_version(),
                .m_ip_ihl(),
                .m_ip_dscp(tx_udp_ip_dscp),
                .m_ip_ecn(tx_udp_ip_ecn),
                .m_ip_length(),
                .m_ip_identification(),
                .m_ip_flags(),
                .m_ip_fragment_offset(),
                .m_ip_ttl(tx_udp_ip_ttl),
                .m_ip_protocol(),
                .m_ip_header_checksum(),
                .m_ip_source_ip(tx_udp_ip_source_ip),
                .m_ip_dest_ip(tx_udp_ip_dest_ip),
                .m_udp_source_port(tx_udp_source_port),
                .m_udp_dest_port(tx_udp_dest_port),
                .m_udp_length(tx_udp_length),
                .m_udp_checksum(tx_udp_checksum),
                .m_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
                .m_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
                .m_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
                .m_udp_payload_axis_tready(tx_udp_payload_axis_tready),
                .m_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
                .m_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
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
                .pmtu(3'd4),
                .RoCE_udp_port(16'h12b7),
                .loc_ip_addr(local_ips[j]),
                .timeout_period(64'd13000), //2.6 ns * 13000 = 34 us
                .retry_count(3'd7),
                .rnr_retry_count(3'd7)
            );

        end
    endgenerate


endmodule

`resetall
