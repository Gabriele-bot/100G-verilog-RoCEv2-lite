/*

Copyright (c) 2014-2018 Alex Forencich

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
 * IPv4 and ARP block, ethernet frame interface (64 bit datapath)
 */
module ip_complete_512 #(
    parameter ARP_CACHE_ADDR_WIDTH = 9,
    parameter ARP_REQUEST_RETRY_COUNT = 4,
    parameter ARP_REQUEST_RETRY_INTERVAL = 156250000 * 2,
    parameter ARP_REQUEST_TIMEOUT = 156250000 * 30
) (
    input wire clk,
    input wire rst,

    /*
     * Ethernet frame input
     */
    input  wire         s_eth_hdr_valid,
    output wire         s_eth_hdr_ready,
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [511:0] s_eth_payload_axis_tdata,
    input  wire [ 63:0] s_eth_payload_axis_tkeep,
    input  wire         s_eth_payload_axis_tvalid,
    output wire         s_eth_payload_axis_tready,
    input  wire         s_eth_payload_axis_tlast,
    input  wire         s_eth_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire         m_eth_hdr_valid,
    input  wire         m_eth_hdr_ready,
    output wire [ 47:0] m_eth_dest_mac,
    output wire [ 47:0] m_eth_src_mac,
    output wire [ 15:0] m_eth_type,
    output wire         m_is_roce_packet,
    output wire [511:0] m_eth_payload_axis_tdata,
    output wire [ 63:0] m_eth_payload_axis_tkeep,
    output wire         m_eth_payload_axis_tvalid,
    input  wire         m_eth_payload_axis_tready,
    output wire         m_eth_payload_axis_tlast,
    output wire         m_eth_payload_axis_tuser,

    /*
     * IP input
     */
    input  wire         s_ip_hdr_valid,
    output wire         s_ip_hdr_ready,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_length,
    input  wire [  7:0] s_ip_ttl,
    input  wire [  7:0] s_ip_protocol,
    input  wire [ 31:0] s_ip_source_ip,
    input  wire [ 31:0] s_ip_dest_ip,
    input  wire         s_is_roce_packet,
    input  wire [511:0] s_ip_payload_axis_tdata,
    input  wire [ 63:0] s_ip_payload_axis_tkeep,
    input  wire         s_ip_payload_axis_tvalid,
    output wire         s_ip_payload_axis_tready,
    input  wire         s_ip_payload_axis_tlast,
    input  wire         s_ip_payload_axis_tuser,

    /*
     * IP output
     */
    output wire         m_ip_hdr_valid,
    input  wire         m_ip_hdr_ready,
    output wire [ 47:0] m_ip_eth_dest_mac,
    output wire [ 47:0] m_ip_eth_src_mac,
    output wire [ 15:0] m_ip_eth_type,
    output wire [  3:0] m_ip_version,
    output wire [  3:0] m_ip_ihl,
    output wire [  5:0] m_ip_dscp,
    output wire [  1:0] m_ip_ecn,
    output wire [ 15:0] m_ip_length,
    output wire [ 15:0] m_ip_identification,
    output wire [  2:0] m_ip_flags,
    output wire [ 12:0] m_ip_fragment_offset,
    output wire [  7:0] m_ip_ttl,
    output wire [  7:0] m_ip_protocol,
    output wire [ 15:0] m_ip_header_checksum,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [511:0] m_ip_payload_axis_tdata,
    output wire [ 63:0] m_ip_payload_axis_tkeep,
    output wire         m_ip_payload_axis_tvalid,
    input  wire         m_ip_payload_axis_tready,
    output wire         m_ip_payload_axis_tlast,
    output wire         m_ip_payload_axis_tuser,

    /*
     * Status
     */
    output wire rx_busy,
    output wire tx_busy,
    output wire rx_error_header_early_termination,
    output wire rx_error_payload_early_termination,
    output wire rx_error_invalid_header,
    output wire rx_error_invalid_checksum,
    output wire tx_error_payload_early_termination,
    output wire tx_error_arp_failed,

    /*
     * Configuration
     */
    input wire [47:0] local_mac,
    input wire [31:0] local_ip,
    input wire [31:0] gateway_ip,
    input wire [31:0] subnet_mask,
    input wire        clear_arp_cache
);

  /*

This module integrates the IP and ARP modules for a complete IP stack

*/

  wire arp_request_valid;
  wire arp_request_ready;
  wire [31:0] arp_request_ip;
  wire arp_response_valid;
  wire arp_response_ready;
  wire arp_response_error;
  wire [47:0] arp_response_mac;

  wire ip_rx_eth_hdr_valid;
  wire ip_rx_eth_hdr_ready;
  wire [47:0] ip_rx_eth_dest_mac;
  wire [47:0] ip_rx_eth_src_mac;
  wire [15:0] ip_rx_eth_type;
  wire [511:0] ip_rx_eth_payload_axis_tdata;
  wire [63:0] ip_rx_eth_payload_axis_tkeep;
  wire ip_rx_eth_payload_axis_tvalid;
  wire ip_rx_eth_payload_axis_tready;
  wire ip_rx_eth_payload_axis_tlast;
  wire ip_rx_eth_payload_axis_tuser;

  wire ip_tx_eth_hdr_valid;
  wire ip_tx_eth_hdr_ready;
  wire [47:0] ip_tx_eth_dest_mac;
  wire [47:0] ip_tx_eth_src_mac;
  wire [15:0] ip_tx_eth_type;
  wire ip_tx_eth_is_roce_packet;
  wire [511:0] ip_tx_eth_payload_axis_tdata;
  wire [63:0] ip_tx_eth_payload_axis_tkeep;
  wire ip_tx_eth_payload_axis_tvalid;
  wire ip_tx_eth_payload_axis_tready;
  wire ip_tx_eth_payload_axis_tlast;
  wire ip_tx_eth_payload_axis_tuser;

  wire arp_rx_eth_hdr_valid;
  wire arp_rx_eth_hdr_ready;
  wire [47:0] arp_rx_eth_dest_mac;
  wire [47:0] arp_rx_eth_src_mac;
  wire [15:0] arp_rx_eth_type;
  wire [511:0] arp_rx_eth_payload_axis_tdata;
  wire [63:0] arp_rx_eth_payload_axis_tkeep;
  wire arp_rx_eth_payload_axis_tvalid;
  wire arp_rx_eth_payload_axis_tready;
  wire arp_rx_eth_payload_axis_tlast;
  wire arp_rx_eth_payload_axis_tuser;
  
  

  wire arp_tx_eth_hdr_valid;
  wire arp_tx_eth_hdr_ready;
  wire [47:0] arp_tx_eth_dest_mac;
  wire [47:0] arp_tx_eth_src_mac;
  wire [15:0] arp_tx_eth_type;
  wire [511:0] arp_tx_eth_payload_axis_tdata;
  wire [63:0]  arp_tx_eth_payload_axis_tkeep;
  wire         arp_tx_eth_payload_axis_tvalid;
  wire         arp_tx_eth_payload_axis_tready;
  wire         arp_tx_eth_payload_axis_tlast;
  wire         arp_tx_eth_payload_axis_tuser;

  wire [511:0] arp_tx_eth_payload_pipeline_axis_tdata;
  wire [63:0]  arp_tx_eth_payload_pipeline_axis_tkeep;
  wire         arp_tx_eth_payload_pipeline_axis_tvalid;
  wire         arp_tx_eth_payload_pipeline_axis_tready;
  wire         arp_tx_eth_payload_pipeline_axis_tlast;
  wire         arp_tx_eth_payload_pipeline_axis_tuser;

  // IP
  wire ip_tx_hdr_valid;
  wire ip_tx_hdr_ready;
  wire [3:0]  ip_tx_version;
  wire [3:0]  ip_tx_ihl;
  wire [5:0]  ip_tx_dscp;
  wire [1:0]  ip_tx_ecn;
  wire [15:0] ip_tx_length;
  wire [15:0] ip_tx_identification;
  wire [2:0]  ip_tx_flags;
  wire [12:0] ip_tx_fragment_offset;
  wire [7:0]  ip_tx_ttl;
  wire [7:0]  ip_tx_protocol;
  wire [15:0] ip_tx_header_checksum;
  wire [31:0] ip_tx_source_ip;
  wire [31:0] ip_tx_dest_ip;
  wire        ip_tx_is_roce_packet;
  wire [511:0] ip_tx_payload_axis_tdata;
  wire [63:0] ip_tx_payload_axis_tkeep;
  wire ip_tx_payload_axis_tvalid;
  wire ip_tx_payload_axis_tready;
  wire ip_tx_payload_axis_tlast;
  wire ip_tx_payload_axis_tuser;

  wire         m_ip_rx_hdr_valid;
  wire         m_ip_rx_hdr_ready;
  wire [47:0]  m_ip_rx_eth_dest_mac;
  wire [47:0]  m_ip_rx_eth_src_mac;
  wire [15:0]  m_ip_rx_eth_type;
  wire [3:0]   m_ip_rx_version;
  wire [3:0]   m_ip_rx_ihl;
  wire [5:0]   m_ip_rx_dscp;
  wire [1:0]   m_ip_rx_ecn;
  wire [15:0]  m_ip_rx_length;
  wire [15:0]  m_ip_rx_identification;
  wire [2:0]   m_ip_rx_flags;
  wire [12:0]  m_ip_rx_fragment_offset;
  wire [7:0]   m_ip_rx_ttl;
  wire [7:0]   m_ip_rx_protocol;
  wire [15:0]  m_ip_rx_header_checksum;
  wire [31:0]  m_ip_rx_source_ip;
  wire [31:0]  m_ip_rx_dest_ip;
  wire [511:0] m_ip_rx_payload_axis_tdata;
  wire [63:0]  m_ip_rx_payload_axis_tkeep;
  wire         m_ip_rx_payload_axis_tvalid;
  wire         m_ip_rx_payload_axis_tready;
  wire         m_ip_rx_payload_axis_tlast;
  wire         m_ip_rx_payload_axis_tuser;

  // ICMP
  wire icmp_rx_ip_hdr_valid;
  wire icmp_rx_ip_hdr_ready;
  wire [47:0]  icmp_rx_ip_eth_dest_mac;
  wire [47:0]  icmp_rx_ip_eth_src_mac;
  wire [15:0]  icmp_rx_ip_eth_type;
  wire [3:0]   icmp_rx_ip_version;
  wire [3:0]   icmp_rx_ip_ihl;
  wire [5:0]   icmp_rx_ip_dscp;
  wire [1:0]   icmp_rx_ip_ecn;
  wire [15:0]  icmp_rx_ip_length;
  wire [15:0]  icmp_rx_ip_identification;
  wire [2:0]   icmp_rx_ip_flags;
  wire [12:0]  icmp_rx_ip_fragment_offset;
  wire [7:0]   icmp_rx_ip_ttl;
  wire [7:0]   icmp_rx_ip_protocol;
  wire [15:0]  icmp_rx_ip_header_checksum;
  wire [31:0]  icmp_rx_ip_source_ip;
  wire [31:0]  icmp_rx_ip_dest_ip;
  wire [511:0] icmp_rx_ip_payload_axis_tdata;
  wire [63:0]  icmp_rx_ip_payload_axis_tkeep;
  wire icmp_rx_ip_payload_axis_tvalid;
  wire icmp_rx_ip_payload_axis_tready;
  wire icmp_rx_ip_payload_axis_tlast;
  wire icmp_rx_ip_payload_axis_tuser;

  wire icmp_tx_ip_hdr_valid;
  wire icmp_tx_ip_hdr_ready;
  wire [47:0] icmp_tx_ip_eth_dest_mac;
  wire [47:0] icmp_tx_ip_eth_src_mac;
  wire [15:0] icmp_tx_ip_eth_type;
  wire [3:0]  icmp_tx_ip_version;
  wire [3:0]  icmp_tx_ip_ihl;
  wire [5:0]  icmp_tx_ip_dscp;
  wire [1:0]  icmp_tx_ip_ecn;
  wire [15:0] icmp_tx_ip_length;
  wire [15:0] icmp_tx_ip_identification;
  wire [2:0]  icmp_tx_ip_flags;
  wire [12:0] icmp_tx_ip_fragment_offset;
  wire [7:0]  icmp_tx_ip_ttl;
  wire [7:0]  icmp_tx_ip_protocol;
  wire [15:0] icmp_tx_ip_header_checksum;
  wire [31:0] icmp_tx_ip_source_ip;
  wire [31:0] icmp_tx_ip_dest_ip;
  wire icmp_tx_is_roce_packet;
  wire [511:0] icmp_tx_ip_payload_axis_tdata;
  wire [63:0] icmp_tx_ip_payload_axis_tkeep;
  wire icmp_tx_ip_payload_axis_tvalid;
  wire icmp_tx_ip_payload_axis_tready;
  wire icmp_tx_ip_payload_axis_tlast;
  wire icmp_tx_ip_payload_axis_tuser;
  /*
  * Input classifier (eth_type)
  */
  wire s_select_ip = (s_eth_type == 16'h0800);
  wire s_select_arp = (s_eth_type == 16'h0806);
  wire s_select_none = !(s_select_ip || s_select_arp);

  reg s_select_ip_reg = 1'b0;
  reg s_select_arp_reg = 1'b0;
  reg s_select_none_reg = 1'b0;

  /*
  * Input classifier (ip_protocol)
  */
  wire s_ip_select_icmp = (m_ip_rx_protocol == 8'h01);
  //wire s_ip_select_udp =  (s_ip_protocol == 8'h11);
  wire s_ip_select_udp =  !s_ip_select_icmp;
  wire s_ip_select_none = !(s_ip_select_icmp || s_ip_select_udp);

  reg s_ip_select_icmp_reg = 1'b0;
  reg s_ip_select_udp_reg = 1'b0;
  reg s_ip_select_none_reg = 1'b0;
  

  always @(posedge clk) begin
    if (rst) begin
      s_select_ip_reg   <= 1'b0;
      s_select_arp_reg  <= 1'b0;
      s_select_none_reg <= 1'b0;

      s_ip_select_icmp_reg   <= 1'b0;
      s_ip_select_udp_reg  <= 1'b0;
      s_ip_select_none_reg <= 1'b0;
    end else begin
      if (s_eth_payload_axis_tvalid) begin
        if ((!s_select_ip_reg && !s_select_arp_reg && !s_select_none_reg) ||
                (s_eth_payload_axis_tvalid && s_eth_payload_axis_tready && s_eth_payload_axis_tlast)) begin
          s_select_ip_reg   <= s_select_ip;
          s_select_arp_reg  <= s_select_arp;
          s_select_none_reg <= s_select_none;
        end
      end else begin
        s_select_ip_reg   <= 1'b0;
        s_select_arp_reg  <= 1'b0;
        s_select_none_reg <= 1'b0;
      end

      if (m_ip_rx_payload_axis_tvalid) begin
        if ((!s_ip_select_icmp_reg && !s_ip_select_udp_reg && !s_ip_select_none_reg) ||
                (m_ip_rx_payload_axis_tvalid && m_ip_rx_payload_axis_tready && m_ip_rx_payload_axis_tlast)) begin
          s_ip_select_icmp_reg   <= s_ip_select_icmp;
          s_ip_select_udp_reg    <= s_ip_select_udp;
          s_ip_select_none_reg   <= s_ip_select_none;
        end
      end else begin
        s_ip_select_icmp_reg <= 1'b0;
        s_ip_select_udp_reg  <= 1'b0;
        s_ip_select_none_reg <= 1'b0;
      end
    end
  end

  assign ip_rx_eth_hdr_valid = s_select_ip && s_eth_hdr_valid;
  assign ip_rx_eth_dest_mac = s_eth_dest_mac;
  assign ip_rx_eth_src_mac = s_eth_src_mac;
  assign ip_rx_eth_type = 16'h0800;
  assign ip_rx_eth_payload_axis_tdata = s_eth_payload_axis_tdata;
  assign ip_rx_eth_payload_axis_tkeep = s_eth_payload_axis_tkeep;
  assign ip_rx_eth_payload_axis_tvalid = s_select_ip_reg && s_eth_payload_axis_tvalid;
  assign ip_rx_eth_payload_axis_tlast = s_eth_payload_axis_tlast;
  assign ip_rx_eth_payload_axis_tuser = s_eth_payload_axis_tuser;

  assign arp_rx_eth_hdr_valid = s_select_arp && s_eth_hdr_valid;
  assign arp_rx_eth_dest_mac = s_eth_dest_mac;
  assign arp_rx_eth_src_mac = s_eth_src_mac;
  assign arp_rx_eth_type = 16'h0806;
  assign arp_rx_eth_payload_axis_tdata = s_eth_payload_axis_tdata;
  assign arp_rx_eth_payload_axis_tkeep = s_eth_payload_axis_tkeep;
  assign arp_rx_eth_payload_axis_tvalid = s_select_arp_reg && s_eth_payload_axis_tvalid;
  assign arp_rx_eth_payload_axis_tlast = s_eth_payload_axis_tlast;
  assign arp_rx_eth_payload_axis_tuser = s_eth_payload_axis_tuser;

  assign s_eth_hdr_ready = (s_select_ip && ip_rx_eth_hdr_ready) ||
                         (s_select_arp && arp_rx_eth_hdr_ready) ||
                         (s_select_none);

  assign s_eth_payload_axis_tready = (s_select_ip_reg && ip_rx_eth_payload_axis_tready) ||
                                   (s_select_arp_reg && arp_rx_eth_payload_axis_tready) ||
                                   s_select_none_reg;


  assign m_ip_hdr_valid = s_ip_select_udp && m_ip_rx_hdr_valid;
  assign m_ip_eth_dest_mac = m_ip_rx_eth_dest_mac;
  assign m_ip_eth_src_mac  = m_ip_rx_eth_src_mac;
  assign m_ip_eth_type     = m_ip_rx_eth_type;
  assign m_ip_version = m_ip_rx_version;
  assign m_ip_ihl = m_ip_rx_ihl;
  assign m_ip_dscp = m_ip_rx_dscp;
  assign m_ip_ecn = m_ip_rx_ecn;
  assign m_ip_length = m_ip_rx_length;
  assign m_ip_identification = m_ip_rx_identification;
  assign m_ip_flags = m_ip_rx_flags;
  assign m_ip_fragment_offset = m_ip_rx_fragment_offset;
  assign m_ip_ttl = m_ip_rx_ttl;
  assign m_ip_protocol = m_ip_rx_protocol;
  assign m_ip_header_checksum = m_ip_rx_header_checksum;
  assign m_ip_source_ip = m_ip_rx_source_ip;
  assign m_ip_dest_ip = m_ip_rx_dest_ip;
  assign m_ip_payload_axis_tdata   = m_ip_rx_payload_axis_tdata;
  assign m_ip_payload_axis_tkeep   = m_ip_rx_payload_axis_tkeep;
  assign m_ip_payload_axis_tvalid  = s_ip_select_udp_reg && m_ip_rx_payload_axis_tvalid;
  assign m_ip_payload_axis_tlast   = m_ip_rx_payload_axis_tlast;
  assign m_ip_payload_axis_tuser   = m_ip_rx_payload_axis_tuser;
  assign m_ip_rx_payload_axis_tready = (s_ip_select_udp_reg  && m_ip_payload_axis_tready) ||
                                     (s_ip_select_icmp_reg && icmp_rx_ip_payload_axis_tready) ||
                                      s_ip_select_none_reg;

  assign icmp_rx_ip_hdr_valid = s_ip_select_icmp && m_ip_rx_hdr_valid;
  assign icmp_rx_ip_eth_dest_mac = m_ip_rx_eth_dest_mac;
  assign icmp_rx_ip_eth_src_mac = m_ip_rx_eth_src_mac;
  assign icmp_rx_ip_eth_type = m_ip_rx_eth_type;
  assign icmp_rx_ip_version = m_ip_rx_version;
  assign icmp_rx_ip_ihl = m_ip_rx_ihl;
  assign icmp_rx_ip_dscp = m_ip_rx_dscp;
  assign icmp_rx_ip_ecn = m_ip_rx_ecn;
  assign icmp_rx_ip_length = m_ip_rx_length;
  assign icmp_rx_ip_identification = m_ip_rx_identification;
  assign icmp_rx_ip_flags = m_ip_rx_flags;
  assign icmp_rx_ip_fragment_offset = m_ip_rx_fragment_offset;
  assign icmp_rx_ip_ttl = m_ip_rx_ttl;
  assign icmp_rx_ip_protocol = m_ip_rx_protocol;
  assign icmp_rx_ip_header_checksum = m_ip_rx_header_checksum;
  assign icmp_rx_ip_source_ip = m_ip_rx_source_ip;
  assign icmp_rx_ip_dest_ip = m_ip_rx_dest_ip;
  assign icmp_rx_ip_payload_axis_tdata  = m_ip_rx_payload_axis_tdata;
  assign icmp_rx_ip_payload_axis_tkeep  = m_ip_rx_payload_axis_tkeep;
  assign icmp_rx_ip_payload_axis_tvalid = s_ip_select_icmp_reg && m_ip_rx_payload_axis_tvalid;
  assign icmp_rx_ip_payload_axis_tlast  = m_ip_rx_payload_axis_tlast;
  assign icmp_rx_ip_payload_axis_tuser  = m_ip_rx_payload_axis_tuser;

  assign m_ip_rx_hdr_ready = (s_ip_select_icmp && icmp_rx_ip_hdr_ready) ||
                           (s_ip_select_udp &&  m_ip_hdr_ready) ||
                           (s_ip_select_none);

  assign s_eth_payload_axis_tready = (s_select_ip_reg && ip_rx_eth_payload_axis_tready) ||
                                   (s_select_arp_reg && arp_rx_eth_payload_axis_tready) ||
                                   s_select_none_reg;


  /*
 * Output arbiter
 */
  axis_pipeline_register #(
    .DATA_WIDTH(512),
    .KEEP_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .REG_TYPE(0),
    .LENGTH(1)
  ) eth_tx_pipeline_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata (arp_tx_eth_payload_axis_tdata),
    .s_axis_tkeep (arp_tx_eth_payload_axis_tkeep),
    .s_axis_tvalid(arp_tx_eth_payload_axis_tvalid),
    .s_axis_tready(arp_tx_eth_payload_axis_tready),
    .s_axis_tlast (arp_tx_eth_payload_axis_tlast),
    .s_axis_tuser (arp_tx_eth_payload_axis_tuser),

    .m_axis_tdata (arp_tx_eth_payload_pipeline_axis_tdata),
    .m_axis_tkeep (arp_tx_eth_payload_pipeline_axis_tkeep),
    .m_axis_tvalid(arp_tx_eth_payload_pipeline_axis_tvalid),
    .m_axis_tready(arp_tx_eth_payload_pipeline_axis_tready),
    .m_axis_tlast (arp_tx_eth_payload_pipeline_axis_tlast),
    .m_axis_tuser (arp_tx_eth_payload_pipeline_axis_tuser)
  );
  
  eth_arb_mux #(
      .S_COUNT(2),
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .ARB_TYPE_ROUND_ROBIN(0),
      .ARB_LSB_HIGH_PRIORITY(1)
  ) eth_arb_mux_inst (
      .clk(clk),
      .rst(rst),
      // Ethernet frame inputs
      .s_eth_hdr_valid({ip_tx_eth_hdr_valid, arp_tx_eth_hdr_valid}),
      .s_eth_hdr_ready({ip_tx_eth_hdr_ready, arp_tx_eth_hdr_ready}),
      .s_eth_dest_mac({ip_tx_eth_dest_mac, arp_tx_eth_dest_mac}),
      .s_eth_src_mac({ip_tx_eth_src_mac, arp_tx_eth_src_mac}),
      .s_eth_type({ip_tx_eth_type, arp_tx_eth_type}),
      .s_is_roce_packet({ip_tx_eth_is_roce_packet, 1'b0}),
      .s_eth_payload_axis_tdata( {ip_tx_eth_payload_axis_tdata,  arp_tx_eth_payload_pipeline_axis_tdata}),
      .s_eth_payload_axis_tkeep( {ip_tx_eth_payload_axis_tkeep,  arp_tx_eth_payload_pipeline_axis_tkeep}),
      .s_eth_payload_axis_tvalid({ip_tx_eth_payload_axis_tvalid, arp_tx_eth_payload_pipeline_axis_tvalid}),
      .s_eth_payload_axis_tready({ip_tx_eth_payload_axis_tready, arp_tx_eth_payload_pipeline_axis_tready}),
      .s_eth_payload_axis_tlast( {ip_tx_eth_payload_axis_tlast,  arp_tx_eth_payload_pipeline_axis_tlast}),
      .s_eth_payload_axis_tid(0),
      .s_eth_payload_axis_tdest(0),
      .s_eth_payload_axis_tuser({ip_tx_eth_payload_axis_tuser, arp_tx_eth_payload_pipeline_axis_tuser}),
      // Ethernet frame output
      .m_eth_hdr_valid(m_eth_hdr_valid),
      .m_eth_hdr_ready(m_eth_hdr_ready),
      .m_eth_dest_mac(m_eth_dest_mac),
      .m_eth_src_mac(m_eth_src_mac),
      .m_eth_type(m_eth_type),
      .m_is_roce_packet(m_is_roce_packet),
      .m_eth_payload_axis_tdata(m_eth_payload_axis_tdata),
      .m_eth_payload_axis_tkeep(m_eth_payload_axis_tkeep),
      .m_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
      .m_eth_payload_axis_tready(m_eth_payload_axis_tready),
      .m_eth_payload_axis_tlast(m_eth_payload_axis_tlast),
      .m_eth_payload_axis_tid(),
      .m_eth_payload_axis_tdest(),
      .m_eth_payload_axis_tuser(m_eth_payload_axis_tuser)
  );

  /*
 * IP Input arbiter
 */
 ip_arb_mux #(
  .S_COUNT(2),
  .DATA_WIDTH(512),
  .KEEP_ENABLE(1),
  .ID_ENABLE(0),
  .DEST_ENABLE(0),
  .USER_ENABLE(1),
  .USER_WIDTH(1),
  .ARB_TYPE_ROUND_ROBIN(0),
  .ARB_LSB_HIGH_PRIORITY(1)
) ip_arb_mux_inst (
  .clk(clk),
  .rst(rst),
  // IP frame inputs
  .s_ip_hdr_valid({s_ip_hdr_valid, icmp_tx_ip_hdr_valid}),
  .s_ip_hdr_ready({s_ip_hdr_ready, icmp_tx_ip_hdr_ready}),
  .s_eth_dest_mac(0),
  .s_eth_src_mac(0),
  .s_eth_type(0),
  .s_ip_version(0),
  .s_ip_ihl(0),
  .s_ip_dscp({s_ip_dscp, icmp_tx_ip_dscp}),
  .s_ip_ecn({s_ip_ecn, icmp_tx_ip_ecn}),
  .s_ip_length({s_ip_length, icmp_tx_ip_length}),
  .s_ip_identification(0),
  .s_ip_flags(0),
  .s_ip_fragment_offset(0),
  .s_ip_ttl({s_ip_ttl, icmp_tx_ip_ttl}),
  .s_ip_protocol({s_ip_protocol, icmp_tx_ip_protocol}),
  .s_ip_header_checksum(0),
  .s_ip_source_ip({s_ip_source_ip, icmp_tx_ip_source_ip}),
  .s_ip_dest_ip({s_ip_dest_ip, icmp_tx_ip_dest_ip}),
  .s_is_roce_packet({s_is_roce_packet, 1'b0}),
  .s_ip_payload_axis_tdata({s_ip_payload_axis_tdata, icmp_tx_ip_payload_axis_tdata}),
  .s_ip_payload_axis_tkeep({s_ip_payload_axis_tkeep, icmp_tx_ip_payload_axis_tkeep}),
  .s_ip_payload_axis_tvalid({s_ip_payload_axis_tvalid, icmp_tx_ip_payload_axis_tvalid}),
  .s_ip_payload_axis_tready({s_ip_payload_axis_tready, icmp_tx_ip_payload_axis_tready}),
  .s_ip_payload_axis_tlast({s_ip_payload_axis_tlast, icmp_tx_ip_payload_axis_tlast}),
  .s_ip_payload_axis_tid(0),
  .s_ip_payload_axis_tdest(0),
  .s_ip_payload_axis_tuser({s_ip_payload_axis_tuser, icmp_tx_ip_payload_axis_tuser}),
  // IP frame output
  .m_ip_hdr_valid(ip_tx_hdr_valid),
  .m_ip_hdr_ready(ip_tx_hdr_ready),
  .m_eth_dest_mac(),
  .m_eth_src_mac(),
  .m_eth_type(),
  .m_ip_version(),
  .m_ip_ihl(),
  .m_ip_dscp(ip_tx_dscp),
  .m_ip_ecn(ip_tx_ecn),
  .m_ip_length(ip_tx_length),
  .m_ip_identification(),
  .m_ip_flags(),
  .m_ip_fragment_offset(),
  .m_ip_ttl(ip_tx_ttl),
  .m_ip_protocol(ip_tx_protocol),
  .m_ip_header_checksum(),
  .m_ip_source_ip(ip_tx_source_ip),
  .m_ip_dest_ip(ip_tx_dest_ip),
  .m_is_roce_packet(ip_tx_is_roce_packet),
  .m_ip_payload_axis_tdata(ip_tx_payload_axis_tdata),
  .m_ip_payload_axis_tkeep(ip_tx_payload_axis_tkeep),
  .m_ip_payload_axis_tvalid(ip_tx_payload_axis_tvalid),
  .m_ip_payload_axis_tready(ip_tx_payload_axis_tready),
  .m_ip_payload_axis_tlast(ip_tx_payload_axis_tlast),
  .m_ip_payload_axis_tid(),
  .m_ip_payload_axis_tdest(),
  .m_ip_payload_axis_tuser(ip_tx_payload_axis_tuser)
);

  /*
 * IP module
 */
  ip_512 ip_inst (
      .clk(clk),
      .rst(rst),
      // Ethernet frame input
      .s_eth_hdr_valid(ip_rx_eth_hdr_valid),
      .s_eth_hdr_ready(ip_rx_eth_hdr_ready),
      .s_eth_dest_mac(ip_rx_eth_dest_mac),
      .s_eth_src_mac(ip_rx_eth_src_mac),
      .s_eth_type(ip_rx_eth_type),
      .s_eth_payload_axis_tdata(ip_rx_eth_payload_axis_tdata),
      .s_eth_payload_axis_tkeep(ip_rx_eth_payload_axis_tkeep),
      .s_eth_payload_axis_tvalid(ip_rx_eth_payload_axis_tvalid),
      .s_eth_payload_axis_tready(ip_rx_eth_payload_axis_tready),
      .s_eth_payload_axis_tlast(ip_rx_eth_payload_axis_tlast),
      .s_eth_payload_axis_tuser(ip_rx_eth_payload_axis_tuser),
      // Ethernet frame output
      .m_eth_hdr_valid(ip_tx_eth_hdr_valid),
      .m_eth_hdr_ready(ip_tx_eth_hdr_ready),
      .m_eth_dest_mac(ip_tx_eth_dest_mac),
      .m_eth_src_mac(ip_tx_eth_src_mac),
      .m_eth_type(ip_tx_eth_type),
      .m_is_roce_packet(ip_tx_eth_is_roce_packet),
      .m_eth_payload_axis_tdata(ip_tx_eth_payload_axis_tdata),
      .m_eth_payload_axis_tkeep(ip_tx_eth_payload_axis_tkeep),
      .m_eth_payload_axis_tvalid(ip_tx_eth_payload_axis_tvalid),
      .m_eth_payload_axis_tready(ip_tx_eth_payload_axis_tready),
      .m_eth_payload_axis_tlast(ip_tx_eth_payload_axis_tlast),
      .m_eth_payload_axis_tuser(ip_tx_eth_payload_axis_tuser),
      // IP frame output
      .m_ip_hdr_valid(m_ip_rx_hdr_valid),
      .m_ip_hdr_ready(m_ip_rx_hdr_ready),
      .m_ip_eth_dest_mac(m_ip_rx_eth_dest_mac),
      .m_ip_eth_src_mac(m_ip_rx_eth_src_mac),
      .m_ip_eth_type(m_ip_rx_eth_type),
      .m_ip_version(m_ip_rx_version),
      .m_ip_ihl(m_ip_rx_ihl),
      .m_ip_dscp(m_ip_rx_dscp),
      .m_ip_ecn(m_ip_rx_ecn),
      .m_ip_length(m_ip_rx_length),
      .m_ip_identification(m_ip_rx_identification),
      .m_ip_flags(m_ip_rx_flags),
      .m_ip_fragment_offset(m_ip_rx_fragment_offset),
      .m_ip_ttl(m_ip_rx_ttl),
      .m_ip_protocol(m_ip_rx_protocol),
      .m_ip_header_checksum(m_ip_rx_header_checksum),
      .m_ip_source_ip(m_ip_rx_source_ip),
      .m_ip_dest_ip(m_ip_rx_dest_ip),
      .m_ip_payload_axis_tdata( m_ip_rx_payload_axis_tdata),
      .m_ip_payload_axis_tkeep( m_ip_rx_payload_axis_tkeep),
      .m_ip_payload_axis_tvalid(m_ip_rx_payload_axis_tvalid),
      .m_ip_payload_axis_tready(m_ip_rx_payload_axis_tready),
      .m_ip_payload_axis_tlast( m_ip_rx_payload_axis_tlast),
      .m_ip_payload_axis_tuser( m_ip_rx_payload_axis_tuser),
      // IP frame input
      .s_ip_hdr_valid(ip_tx_hdr_valid),
      .s_ip_hdr_ready(ip_tx_hdr_ready),
      .s_ip_dscp(ip_tx_dscp),
      .s_ip_ecn(ip_tx_ecn),
      .s_ip_length(ip_tx_length),
      .s_ip_ttl(ip_tx_ttl),
      .s_ip_protocol(ip_tx_protocol),
      .s_ip_source_ip(ip_tx_source_ip),
      .s_ip_dest_ip(ip_tx_dest_ip),
      .s_is_roce_packet(ip_tx_is_roce_packet),
      .s_ip_payload_axis_tdata(ip_tx_payload_axis_tdata),
      .s_ip_payload_axis_tkeep(ip_tx_payload_axis_tkeep),
      .s_ip_payload_axis_tvalid(ip_tx_payload_axis_tvalid),
      .s_ip_payload_axis_tready(ip_tx_payload_axis_tready),
      .s_ip_payload_axis_tlast(ip_tx_payload_axis_tlast),
      .s_ip_payload_axis_tuser(ip_tx_payload_axis_tuser),
      // ARP requests
      .arp_request_valid(arp_request_valid),
      .arp_request_ready(arp_request_ready),
      .arp_request_ip(arp_request_ip),
      .arp_response_valid(arp_response_valid),
      .arp_response_ready(arp_response_ready),
      .arp_response_error(arp_response_error),
      .arp_response_mac(arp_response_mac),
      // Status
      .rx_busy(rx_busy),
      .tx_busy(tx_busy),
      .rx_error_header_early_termination(rx_error_header_early_termination),
      .rx_error_payload_early_termination(rx_error_payload_early_termination),
      .rx_error_invalid_header(rx_error_invalid_header),
      .rx_error_invalid_checksum(rx_error_invalid_checksum),
      .tx_error_payload_early_termination(tx_error_payload_early_termination),
      .tx_error_arp_failed(tx_error_arp_failed),
      // Configuration
      .local_mac(local_mac),
      .local_ip(local_ip)
  );

   /*
 * ICMP Echo reply
 */
 icmp_echo_reply #(
  .DATA_WIDTH(512),
  .KEEP_ENABLE(1),
  .KEEP_WIDTH(64),
  .CHECKSUM_PAYLOAD_FIFO_DEPTH(512),
  .CHECKSUM_HEADER_FIFO_DEPTH(8)
 ) icmp_echo_reply_inst (
   .clk(clk),
   .rst(rst),
   // IP frame input
   .s_ip_hdr_valid(icmp_rx_ip_hdr_valid),
   .s_ip_hdr_ready(icmp_rx_ip_hdr_ready),
   .s_eth_dest_mac(0),
   .s_eth_src_mac(0),
   .s_eth_type(0),
   .s_ip_version(icmp_rx_ip_version),
   .s_ip_ihl(icmp_rx_ip_ihl),
   .s_ip_dscp(icmp_rx_ip_dscp),
   .s_ip_ecn(icmp_rx_ip_ecn),
   .s_ip_length(icmp_rx_ip_length),
   .s_ip_identification(icmp_rx_ip_identification),
   .s_ip_flags(icmp_rx_ip_flags),
   .s_ip_fragment_offset(icmp_rx_ip_fragment_offset),
   .s_ip_ttl(icmp_rx_ip_ttl),
   .s_ip_protocol(icmp_rx_ip_protocol),
   .s_ip_header_checksum(icmp_rx_ip_header_checksum),
   .s_ip_source_ip(icmp_rx_ip_source_ip),
   .s_ip_dest_ip(icmp_rx_ip_dest_ip),
   .s_ip_payload_axis_tdata( icmp_rx_ip_payload_axis_tdata),
   .s_ip_payload_axis_tkeep( icmp_rx_ip_payload_axis_tkeep),
   .s_ip_payload_axis_tvalid(icmp_rx_ip_payload_axis_tvalid),
   .s_ip_payload_axis_tready(icmp_rx_ip_payload_axis_tready),
   .s_ip_payload_axis_tlast( icmp_rx_ip_payload_axis_tlast),
   .s_ip_payload_axis_tuser( icmp_rx_ip_payload_axis_tuser),
   // IP frame output
   .m_ip_hdr_valid(icmp_tx_ip_hdr_valid),
   .m_ip_hdr_ready(icmp_tx_ip_hdr_ready),
   .m_eth_dest_mac(),
   .m_eth_src_mac(),
   .m_eth_type(),
   .m_ip_version(icmp_tx_ip_version),
   .m_ip_ihl(icmp_tx_ip_ihl),
   .m_ip_dscp(icmp_tx_ip_dscp),
   .m_ip_ecn(icmp_tx_ip_ecn),
   .m_ip_length(icmp_tx_ip_length),
   .m_ip_identification(icmp_tx_ip_identification),
   .m_ip_flags(icmp_tx_ip_flags),
   .m_ip_fragment_offset(icmp_tx_ip_fragment_offset),
   .m_ip_ttl(icmp_tx_ip_ttl),
   .m_ip_protocol(icmp_tx_ip_protocol),
   .m_ip_header_checksum(icmp_tx_ip_header_checksum),
   .m_ip_source_ip(icmp_tx_ip_source_ip),
   .m_ip_dest_ip(icmp_tx_ip_dest_ip),
   .m_is_roce_packet(icmp_tx_is_roce_packet),
   .m_ip_payload_axis_tdata( icmp_tx_ip_payload_axis_tdata),
   .m_ip_payload_axis_tkeep( icmp_tx_ip_payload_axis_tkeep),
   .m_ip_payload_axis_tvalid(icmp_tx_ip_payload_axis_tvalid),
   .m_ip_payload_axis_tready(icmp_tx_ip_payload_axis_tready),
   .m_ip_payload_axis_tlast( icmp_tx_ip_payload_axis_tlast),
   .m_ip_payload_axis_tuser( icmp_tx_ip_payload_axis_tuser),
   // Configuration
   .local_ip(local_ip)
 );

  /*
 * ARP module
 */
  arp #(
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(64),
      .CACHE_ADDR_WIDTH(ARP_CACHE_ADDR_WIDTH),
      .REQUEST_RETRY_COUNT(ARP_REQUEST_RETRY_COUNT),
      .REQUEST_RETRY_INTERVAL(ARP_REQUEST_RETRY_INTERVAL),
      .REQUEST_TIMEOUT(ARP_REQUEST_TIMEOUT)
  ) arp_inst (
      .clk(clk),
      .rst(rst),
      // Ethernet frame input
      .s_eth_hdr_valid(arp_rx_eth_hdr_valid),
      .s_eth_hdr_ready(arp_rx_eth_hdr_ready),
      .s_eth_dest_mac(arp_rx_eth_dest_mac),
      .s_eth_src_mac(arp_rx_eth_src_mac),
      .s_eth_type(arp_rx_eth_type),
      .s_eth_payload_axis_tdata (arp_rx_eth_payload_axis_tdata),
      .s_eth_payload_axis_tkeep (arp_rx_eth_payload_axis_tkeep),
      .s_eth_payload_axis_tvalid(arp_rx_eth_payload_axis_tvalid),
      .s_eth_payload_axis_tready(arp_rx_eth_payload_axis_tready),
      .s_eth_payload_axis_tlast (arp_rx_eth_payload_axis_tlast),
      .s_eth_payload_axis_tuser (arp_rx_eth_payload_axis_tuser),
      // Ethernet frame output
      .m_eth_hdr_valid(arp_tx_eth_hdr_valid),
      .m_eth_hdr_ready(arp_tx_eth_hdr_ready),
      .m_eth_dest_mac(arp_tx_eth_dest_mac),
      .m_eth_src_mac(arp_tx_eth_src_mac),
      .m_eth_type(arp_tx_eth_type),
      .m_eth_payload_axis_tdata(arp_tx_eth_payload_axis_tdata),
      .m_eth_payload_axis_tkeep(arp_tx_eth_payload_axis_tkeep),
      .m_eth_payload_axis_tvalid(arp_tx_eth_payload_axis_tvalid),
      .m_eth_payload_axis_tready(arp_tx_eth_payload_axis_tready),
      .m_eth_payload_axis_tlast(arp_tx_eth_payload_axis_tlast),
      .m_eth_payload_axis_tuser(arp_tx_eth_payload_axis_tuser),
      // ARP requests
      .arp_request_valid(arp_request_valid),
      .arp_request_ready(arp_request_ready),
      .arp_request_ip(arp_request_ip),
      .arp_response_valid(arp_response_valid),
      .arp_response_ready(arp_response_ready),
      .arp_response_error(arp_response_error),
      .arp_response_mac(arp_response_mac),
      // Configuration
      .local_mac(local_mac),
      .local_ip(local_ip),
      .gateway_ip(gateway_ip),
      .subnet_mask(subnet_mask),
      .clear_cache(clear_arp_cache)
  );
  

endmodule

`resetall
