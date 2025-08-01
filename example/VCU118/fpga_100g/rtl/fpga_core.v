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

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * FPGA core logic
 */
module fpga_core #(
    parameter TARGET = "XILINX",
    parameter LOCAL_MAC_ADDRESS = 48'h02_00_00_00_00_00,
    parameter FIFO_REGS = 4
) (
    /*
     * Clock: TX cmac
     * Synchronous reset
     */
    input wire clk,
    input wire rst,

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

    output wire [511:0] qsfp1_tx_axis_tdata,
    output wire [ 63:0] qsfp1_tx_axis_tkeep,
    output wire         qsfp1_tx_axis_tvalid,
    input  wire         qsfp1_tx_axis_tready,
    output wire         qsfp1_tx_axis_tlast,
    output wire         qsfp1_tx_axis_tuser,

    output wire       qsfp1_tx_enable,

    input wire [511:0] qsfp1_rx_axis_tdata,
    input wire [ 63:0] qsfp1_rx_axis_tkeep,
    input wire         qsfp1_rx_axis_tvalid,
    input wire         qsfp1_rx_axis_tlast,
    input wire         qsfp1_rx_axis_tuser,

    output wire       qsfp1_rx_enable,
    input  wire       qsfp1_rx_status,

    input  wire        qsfp1_drp_clk,
    input  wire        qsfp1_drp_rst,
    output wire [23:0] qsfp1_drp_addr,
    output wire [15:0] qsfp1_drp_di,
    output wire        qsfp1_drp_en,
    output wire        qsfp1_drp_we,
    input  wire [15:0] qsfp1_drp_do,
    input  wire        qsfp1_drp_rdy,

    output wire [511:0] qsfp2_tx_axis_tdata,
    output wire [ 63:0] qsfp2_tx_axis_tkeep,
    output wire         qsfp2_tx_axis_tvalid,
    input  wire         qsfp2_tx_axis_tready,
    output wire         qsfp2_tx_axis_tlast,
    output wire         qsfp2_tx_axis_tuser,

    output wire       qsfp2_tx_enable,

    input wire [511:0] qsfp2_rx_axis_tdata,
    input wire [ 63:0] qsfp2_rx_axis_tkeep,
    input wire         qsfp2_rx_axis_tvalid,
    input wire         qsfp2_rx_axis_tlast,
    input wire         qsfp2_rx_axis_tuser,

    input  wire        qsfp2_drp_clk,
    input  wire        qsfp2_drp_rst,
    output wire [23:0] qsfp2_drp_addr,
    output wire [15:0] qsfp2_drp_di,
    output wire        qsfp2_drp_en,
    output wire        qsfp2_drp_we,
    input  wire [15:0] qsfp2_drp_do,
    input  wire        qsfp2_drp_rdy,

    output wire       qsfp2_rx_enable,
    input  wire       qsfp2_rx_status
);
  wire [511:0]                                               rx_axis_tdata;
  wire [ 63:0]                                               rx_axis_tkeep;
  wire                                                       rx_axis_tvalid;
  wire                                                       rx_axis_tready;
  wire                                                       rx_axis_tlast;
  wire                                                       rx_axis_tuser;

  wire [511:0]                                               tx_axis_tdata;
  wire [ 63:0]                                               tx_axis_tkeep;
  wire                                                       tx_axis_tvalid;
  wire                                                       tx_axis_tready;
  wire                                                       tx_axis_tlast;
  wire                                                       tx_axis_tuser;

  // Ethernet frame between Ethernet modules and UDP stack
  wire                                                       rx_eth_hdr_ready;
  wire                                                       rx_eth_hdr_valid;
  wire [ 47:0]                                               rx_eth_dest_mac;
  wire [ 47:0]                                               rx_eth_src_mac;
  wire [ 15:0]                                               rx_eth_type;
  wire [511:0]                                               rx_eth_payload_axis_tdata;
  wire [ 63:0]                                               rx_eth_payload_axis_tkeep;
  wire                                                       rx_eth_payload_axis_tvalid;
  wire                                                       rx_eth_payload_axis_tready;
  wire                                                       rx_eth_payload_axis_tlast;
  wire                                                       rx_eth_payload_axis_tuser;

  wire                                                       tx_eth_hdr_ready;
  wire                                                       tx_eth_hdr_valid;
  wire [ 47:0]                                               tx_eth_dest_mac;
  wire [ 47:0]                                               tx_eth_src_mac;
  wire [ 15:0]                                               tx_eth_type;
  wire [511:0]                                               tx_eth_payload_axis_tdata;
  wire [ 63:0]                                               tx_eth_payload_axis_tkeep;
  wire                                                       tx_eth_payload_axis_tvalid;
  wire                                                       tx_eth_payload_axis_tready;
  wire                                                       tx_eth_payload_axis_tlast;
  wire                                                       tx_eth_payload_axis_tuser;

  // IP frame connections
  wire                                                       rx_ip_hdr_valid;
  wire                                                       rx_ip_hdr_ready;
  wire [ 47:0]                                               rx_ip_eth_dest_mac;
  wire [ 47:0]                                               rx_ip_eth_src_mac;
  wire [ 15:0]                                               rx_ip_eth_type;
  wire [  3:0]                                               rx_ip_version;
  wire [  3:0]                                               rx_ip_ihl;
  wire [  5:0]                                               rx_ip_dscp;
  wire [  1:0]                                               rx_ip_ecn;
  wire [ 15:0]                                               rx_ip_length;
  wire [ 15:0]                                               rx_ip_identification;
  wire [  2:0]                                               rx_ip_flags;
  wire [ 12:0]                                               rx_ip_fragment_offset;
  wire [  7:0]                                               rx_ip_ttl;
  wire [  7:0]                                               rx_ip_protocol;
  wire [ 15:0]                                               rx_ip_header_checksum;
  wire [ 31:0]                                               rx_ip_source_ip;
  wire [ 31:0]                                               rx_ip_dest_ip;
  wire [511:0]                                               rx_ip_payload_axis_tdata;
  wire [ 63:0]                                               rx_ip_payload_axis_tkeep;
  wire                                                       rx_ip_payload_axis_tvalid;
  wire                                                       rx_ip_payload_axis_tready;
  wire                                                       rx_ip_payload_axis_tlast;
  wire                                                       rx_ip_payload_axis_tuser;

  wire                                                       tx_ip_hdr_valid;
  wire                                                       tx_ip_hdr_ready;
  wire [  5:0]                                               tx_ip_dscp;
  wire [  1:0]                                               tx_ip_ecn;
  wire [ 15:0]                                               tx_ip_length;
  wire [  7:0]                                               tx_ip_ttl;
  wire [  7:0]                                               tx_ip_protocol;
  wire [ 31:0]                                               tx_ip_source_ip;
  wire [ 31:0]                                               tx_ip_dest_ip;
  wire [511:0]                                               tx_ip_payload_axis_tdata;
  wire [ 63:0]                                               tx_ip_payload_axis_tkeep;
  wire                                                       tx_ip_payload_axis_tvalid;
  wire                                                       tx_ip_payload_axis_tready;
  wire                                                       tx_ip_payload_axis_tlast;
  wire                                                       tx_ip_payload_axis_tuser;

  // UDP frame connections
  wire                                                       rx_udp_hdr_valid;
  wire                                                       rx_udp_hdr_ready;
  wire [ 47:0]                                               rx_udp_eth_dest_mac;
  wire [ 47:0]                                               rx_udp_eth_src_mac;
  wire [ 15:0]                                               rx_udp_eth_type;
  wire [  3:0]                                               rx_udp_ip_version;
  wire [  3:0]                                               rx_udp_ip_ihl;
  wire [  5:0]                                               rx_udp_ip_dscp;
  wire [  1:0]                                               rx_udp_ip_ecn;
  wire [ 15:0]                                               rx_udp_ip_length;
  wire [ 15:0]                                               rx_udp_ip_identification;
  wire [  2:0]                                               rx_udp_ip_flags;
  wire [ 12:0]                                               rx_udp_ip_fragment_offset;
  wire [  7:0]                                               rx_udp_ip_ttl;
  wire [  7:0]                                               rx_udp_ip_protocol;
  wire [ 15:0]                                               rx_udp_ip_header_checksum;
  wire [ 31:0]                                               rx_udp_ip_source_ip;
  wire [ 31:0]                                               rx_udp_ip_dest_ip;
  wire [ 15:0]                                               rx_udp_source_port;
  wire [ 15:0]                                               rx_udp_dest_port;
  wire [ 15:0]                                               rx_udp_length;
  wire [ 15:0]                                               rx_udp_checksum;
  wire [511:0]                                               rx_udp_payload_axis_tdata;
  wire [ 63:0]                                               rx_udp_payload_axis_tkeep;
  wire                                                       rx_udp_payload_axis_tvalid;
  wire                                                       rx_udp_payload_axis_tready;
  wire                                                       rx_udp_payload_axis_tlast;
  wire                                                       rx_udp_payload_axis_tuser;

  wire                                                       tx_udp_hdr_valid;
  wire                                                       tx_udp_hdr_ready;
  wire [  5:0]                                               tx_udp_ip_dscp;
  wire [  1:0]                                               tx_udp_ip_ecn;
  wire [  7:0]                                               tx_udp_ip_ttl;
  wire [ 31:0]                                               tx_udp_ip_source_ip;
  wire [ 31:0]                                               tx_udp_ip_dest_ip;
  wire [ 15:0]                                               tx_udp_source_port;
  wire [ 15:0]                                               tx_udp_dest_port;
  wire [ 15:0]                                               tx_udp_length;
  wire [ 15:0]                                               tx_udp_checksum;
  wire [511:0]                                               tx_udp_payload_axis_tdata;
  wire [ 63:0]                                               tx_udp_payload_axis_tkeep;
  wire                                                       tx_udp_payload_axis_tvalid;
  wire                                                       tx_udp_payload_axis_tready;
  wire                                                       tx_udp_payload_axis_tlast;
  wire                                                       tx_udp_payload_axis_tuser;

  wire [511:0]                                               rx_fifo_udp_payload_axis_tdata;
  wire [ 63:0]                                               rx_fifo_udp_payload_axis_tkeep;
  wire                                                       rx_fifo_udp_payload_axis_tvalid;
  wire                                                       rx_fifo_udp_payload_axis_tready;
  wire                                                       rx_fifo_udp_payload_axis_tlast;
  wire                                                       rx_fifo_udp_payload_axis_tuser;

  // Configuration
//wire [31:0] local_ip    = {8'd22 , 8'd1  , 8'd212, 8'd10 };
//wire [31:0] gateway_ip  = {8'd22 , 8'd1  , 8'd212, 8'd1  };
wire [31:0] local_ip;
wire [31:0] gateway_ip;
wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0  };

wire clear_arp_cache;

wire [12:0] pmtu;
wire [15:0] RoCE_udp_port;
  
  vio_roce_ip_cfg vio_roce_ip_cfg_inst (
    .clk(clk),
    .probe_out0(pmtu),
    .probe_out1(RoCE_udp_port),
    .probe_out2(local_ip),
    .probe_out3(clear_arp_cache)
  );
  
 assign gateway_ip = {local_ip[31:8], 8'd1};

  // IP ports not used
  assign rx_ip_hdr_ready           = 1;
  assign rx_ip_payload_axis_tready = 1;

  assign tx_ip_hdr_valid           = 0;
  assign tx_ip_dscp                = 0;
  assign tx_ip_ecn                 = 0;
  assign tx_ip_length              = 0;
  assign tx_ip_ttl                 = 0;
  assign tx_ip_protocol            = 0;
  assign tx_ip_source_ip           = 0;
  assign tx_ip_dest_ip             = 0;
  assign tx_ip_payload_axis_tdata  = 0;
  assign tx_ip_payload_axis_tkeep  = 0;
  assign tx_ip_payload_axis_tvalid = 0;
  assign tx_ip_payload_axis_tlast  = 0;
  assign tx_ip_payload_axis_tuser  = 0;

  assign qsfp1_tx_enable           = 1'b1;

  assign qsfp1_rx_enable           = 1'b1;

  assign qsfp2_tx_enable           = 1'b1;

  assign qsfp2_rx_enable           = 1'b1;

  // Place first payload byte onto LEDs
  reg valid_last = 0;
  reg [7:0] led_reg = 0;

  always @(posedge clk) begin
    if (rst) begin
      led_reg <= 0;
    end else begin
      valid_last <= tx_udp_payload_axis_tvalid;
      if (tx_udp_payload_axis_tvalid && !valid_last) begin
        led_reg <= tx_udp_payload_axis_tdata;
      end
    end
  end

  //assign led = sw;
  assign led = led_reg;

  eth_axis_rx #(
      .DATA_WIDTH(512)
  ) eth_axis_rx_inst (
      .clk(clk),
      .rst(rst),
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
      .DATA_WIDTH(512)
  ) eth_axis_tx_inst (
      .clk(clk),
      .rst(rst),
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
  
  // to aid timings
  axis_srl_fifo #(
    .DATA_WIDTH(512),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(64),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .DEPTH(FIFO_REGS)
  ) tx_axis_srl_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata (tx_axis_tdata),
    .s_axis_tkeep (tx_axis_tkeep),
    .s_axis_tvalid(tx_axis_tvalid),
    .s_axis_tready(tx_axis_tready),
    .s_axis_tlast (tx_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (tx_axis_tuser),

    // AXI output
    .m_axis_tdata (qsfp1_tx_axis_tdata),
    .m_axis_tkeep (qsfp1_tx_axis_tkeep),
    .m_axis_tvalid(qsfp1_tx_axis_tvalid),
    .m_axis_tready(qsfp1_tx_axis_tready),
    .m_axis_tlast (qsfp1_tx_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (qsfp1_tx_axis_tuser)
  );
  
  // to aid timings
  axis_srl_fifo #(
    .DATA_WIDTH(512),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(64),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .DEPTH(FIFO_REGS)
  ) rx_axis_srl_fifo (
    .clk(clk),
    .rst(rst),

    // AXI input
    .s_axis_tdata (qsfp1_rx_axis_tdata),
    .s_axis_tkeep (qsfp1_rx_axis_tkeep),
    .s_axis_tvalid(qsfp1_rx_axis_tvalid),
    .s_axis_tready(),
    .s_axis_tlast (qsfp1_rx_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (qsfp1_rx_axis_tuser),

    // AXI output
    .m_axis_tdata (rx_axis_tdata),
    .m_axis_tkeep (rx_axis_tkeep),
    .m_axis_tvalid(rx_axis_tvalid),
    .m_axis_tready(1'b1),
    .m_axis_tlast (rx_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (rx_axis_tuser)
  );

  // not really used
  assign qsfp2_tx_axis_tdata  = 512'd0;
  assign qsfp2_tx_axis_tkeep  = 64'd0;
  assign qsfp2_tx_axis_tvalid = 1'b0;
  assign qsfp2_tx_axis_tuser  = 1'b0;
  assign qsfp2_tx_axis_tlast  = 1'b0;

  udp_complete_test #(
      .DATA_WIDTH(512),
      .UDP_CHECKSUM_GEN_ENABLE(0),
      .ROCE_ICRC_INSERTER(1)
  ) udp_complete_inst (
      .clk(clk),
      .rst(rst),
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
      .s_ip_hdr_valid(tx_ip_hdr_valid),
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
      .s_ip_payload_axis_tvalid(tx_ip_payload_axis_tvalid),
      .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
      .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
      .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
      // IP frame output
      .m_ip_hdr_valid(rx_ip_hdr_valid),
      .m_ip_hdr_ready(rx_ip_hdr_ready),
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
      .m_ip_payload_axis_tready(rx_ip_payload_axis_tready),
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
      .local_mac(LOCAL_MAC_ADDRESS),
      .local_ip(local_ip),
      .gateway_ip(gateway_ip),
      .subnet_mask(subnet_mask),
      .clear_arp_cache(clear_arp_cache),
      .RoCE_udp_port(RoCE_udp_port)
  );

  assign rx_fifo_udp_payload_axis_tready = 1'b1;

  // ROCE TX inst
  // 10G  64b@156MHz   --> 2**18 * 8 bits / 10Gbps  = 210 us of buffering (best case scenario, every frame is full)
  // 25G  642b@390MHz  --> 2**20 * 8 bits / 25Gbps  = 168 us of buffering (best case scenario, every frame is full)
  // 100G 512b@322MHz  --> 2**21 * 8 bits / 100Gbps = 168 us of buffering (best case scenario, every frame is full)
  // 200G 512b@400MHz  --> 2**22 * 8 bits / 200Gbps = 168 us of buffering (best case scenario, every frame is full)
  // 400G 1024b@400MHz --> 2**24 * 8 bits / 400Gbps = 168 us of buffering (best case scenario, every frame is full)
  
  RoCE_minimal_stack #(
      .DATA_WIDTH(512),
      .DEBUG(1),
      .RETRANSMISSION_ADDR_BUFFER_WIDTH(21) // 2**21 * 8 bits / 100Gbps = 168 us of buffering (best case scenario, every frame is full)
  ) RoCE_minimal_stack_512_instance (
      .clk(clk),
      .rst(rst),
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
      .busy(),
      .error_payload_early_termination(),
      .pmtu(pmtu),
      .RoCE_udp_port(RoCE_udp_port),
      .loc_ip_addr(local_ip),
      .timeout_period(64'd20000), //3.1 ns * 20000 = 62 ns
      .retry_count(3'd7),
      .rnr_retry_count(3'd7)
  );
  
  /*
  ila_axis ila_eth_payload_tx(
    .clk(clk),
    .probe0(tx_eth_payload_axis_tdata),
    .probe1(tx_eth_payload_axis_tkeep),
    .probe2(tx_eth_payload_axis_tvalid),
    .probe3(tx_eth_payload_axis_tready),
    .probe4(tx_eth_payload_axis_tlast),
    .probe5(tx_eth_payload_axis_tuser)
  );
  */
endmodule

`resetall

