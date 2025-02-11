// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * UDP ethernet frame transmitter (UDP frame in, IP frame out, 64-bit datapath)
 */
module RoCE_udp_tx_512 (
  input wire clk,
  input wire rst,

  /*
   * RoCE frame input
   */
  // BTH
  input  wire         s_roce_bth_valid,
  output wire         s_roce_bth_ready,
  input  wire [  7:0] s_roce_bth_op_code,
  input  wire [ 15:0] s_roce_bth_p_key,
  input  wire [ 23:0] s_roce_bth_psn,
  input  wire [ 23:0] s_roce_bth_dest_qp,
  input  wire         s_roce_bth_ack_req,
  // RETH
  input  wire         s_roce_reth_valid,
  output wire         s_roce_reth_ready,
  input  wire [ 63:0] s_roce_reth_v_addr,
  input  wire [ 31:0] s_roce_reth_r_key,
  input  wire [ 31:0] s_roce_reth_length,
  // IMMD
  input  wire         s_roce_immdh_valid,
  output wire         s_roce_immdh_ready,
  input  wire [ 31:0] s_roce_immdh_data,
  // udp, ip, eth
  input  wire [ 47:0] s_eth_dest_mac,
  input  wire [ 47:0] s_eth_src_mac,
  input  wire [ 15:0] s_eth_type,
  input  wire [  3:0] s_ip_version,
  input  wire [  3:0] s_ip_ihl,
  input  wire [  5:0] s_ip_dscp,
  input  wire [  1:0] s_ip_ecn,
  input  wire [ 15:0] s_ip_identification,
  input  wire [  2:0] s_ip_flags,
  input  wire [ 12:0] s_ip_fragment_offset,
  input  wire [  7:0] s_ip_ttl,
  input  wire [  7:0] s_ip_protocol,
  input  wire [ 15:0] s_ip_header_checksum,
  input  wire [ 31:0] s_ip_source_ip,
  input  wire [ 31:0] s_ip_dest_ip,
  input  wire [ 15:0] s_udp_source_port,
  input  wire [ 15:0] s_udp_dest_port,
  input  wire [ 15:0] s_udp_length,
  input  wire [ 15:0] s_udp_checksum,
  // payload
  input  wire [511:0] s_roce_payload_axis_tdata,
  input  wire [ 63:0] s_roce_payload_axis_tkeep,
  input  wire         s_roce_payload_axis_tvalid,
  output wire         s_roce_payload_axis_tready,
  input  wire         s_roce_payload_axis_tlast,
  input  wire         s_roce_payload_axis_tuser,
  /*
   * UDP frame output
   */
  output wire         m_udp_hdr_valid,
  input  wire         m_udp_hdr_ready,
  output wire [ 47:0] m_eth_dest_mac,
  output wire [ 47:0] m_eth_src_mac,
  output wire [ 15:0] m_eth_type,
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
  output wire [ 15:0] m_udp_source_port,
  output wire [ 15:0] m_udp_dest_port,
  output wire [ 15:0] m_udp_length,
  output wire [ 15:0] m_udp_checksum,
  output wire [511:0] m_udp_payload_axis_tdata,
  output wire [ 63:0] m_udp_payload_axis_tkeep,
  output wire         m_udp_payload_axis_tvalid,
  input  wire         m_udp_payload_axis_tready,
  output wire         m_udp_payload_axis_tlast,
  output wire         m_udp_payload_axis_tuser,
  /*
   * Status signals
   */
  output wire         busy,
  output wire         error_payload_early_termination,
  /*
   * Config
   */
  input  wire [              15:0] RoCE_udp_port
);

  /*

RoCE RDMA WRITE Frame.

RDMA WRITE FIRST or RMDA WRITE ONLY
IP_HDR + UDP_HDR + BTH + RETH + PAYLOAD + ICRC
RMDA WRITE ONLY with IMMD + PAYLOAD + ICRC
IP_HDR + UDP_HDR +BTH + RETH + IMMD + PAYLOAD + ICRC
RDMA WRITE MIDDLE or RMDA WRITE LAST
IP_HDR + UDP_HDR +BTH + PAYLOAD + ICRC
RMDA WRITE LAST with IMMD + PAYLOAD + ICRC
IP_HDR + UDP_HDR +BTH + IMMD + PAYLOAD + ICRC


+--------------------------------------+
|                BTH                   |
+--------------------------------------+
 Field                       Length
 OP code                     1 octet
 Solicited Event             1 bit
 Mig request                 1 bit
 Pad count                   2 bits
 Header version              4 bits
 Partition key               2 octets
 Reserved                    1 octet
 Queue Pair Number           3 octets
 Ack request                 1 bit
 Reserved                    7 bits
 Packet Sequence Number      3 octets
+--------------------------------------+
|               RETH                   |
+--------------------------------------+
 Field                       Length
 Remote Address              8 octets
 R key                       4 octets
 DMA length                  4 octets
+--------------------------------------+
|               IMMD                   |
+--------------------------------------+
 Field                       Length
 Immediate data              4 octets
+--------------------------------------+
|               AETH                   |
+--------------------------------------+
 Field                       Length
 Syndrome                    1 octet
 Message Sequence Number     3 octets
 
 payload                     length octets
+--------------------------------------+
|               ICRC                   |
+--------------------------------------+
 Field                       Length
 ICRC field                  4 octets

This module receives a RoCEv2 frame with headers fields in parallel along with the
payload in an AXI stream, combines the headers with the payload, passes through
the UDP headers, and transmits the complete UDP payload on an AXI interface.

*/

  localparam [7:0]
  RC_SEND_FIRST         = 8'h00,
  RC_SEND_MIDDLE        = 8'h01,
  RC_SEND_LAST          = 8'h02,
  RC_SEND_LAST_IMD      = 8'h03,
  RC_SEND_ONLY          = 8'h04,
  RC_SEND_ONLY_IMD      = 8'h05,
  RC_RDMA_WRITE_FIRST   = 8'h06,
  RC_RDMA_WRITE_MIDDLE  = 8'h07,
  RC_RDMA_WRITE_LAST    = 8'h08,
  RC_RDMA_WRITE_LAST_IMD= 8'h09,
  RC_RDMA_WRITE_ONLY    = 8'h0A,
  RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
  RC_RDMA_ACK           = 8'h11;

  // TODO improove the FSM..
  localparam [4:0]
  STATE_IDLE = 5'd0,
  STATE_WAIT_HEADER = 5'd1,
  STATE_WAIT_PAYLOAD = 5'd2,
  STATE_WRITE_BTH = 5'd3,
  STATE_WRITE_BTH_IMMDH = 5'd4,
  STATE_WRITE_BTH_RETH = 5'd5,
  STATE_WRITE_BTH_RETH_IMMDH = 5'd6,
  STATE_WRITE_PAYLOAD_96 = 5'd7,
  STATE_WRITE_PAYLOAD_96_LAST = 5'd8,
  STATE_WRITE_PAYLOAD_128 = 5'd9,
  STATE_WRITE_PAYLOAD_128_LAST = 5'd10,
  STATE_WRITE_PAYLOAD_224 = 5'd11,
  STATE_WRITE_PAYLOAD_224_LAST = 5'd12,
  STATE_WRITE_PAYLOAD_256 = 5'd13,
  STATE_WRITE_PAYLOAD_256_LAST = 5'd14,
  STATE_WAIT_LAST = 5'd15;

  reg [3:0] state_reg = STATE_IDLE, state_next;

  reg solicited_event_reg;

  // datapath control signals
  reg store_bth;
  reg store_reth;
  reg store_immdh;
  reg store_udp;
  reg store_last_word;

  reg flush_save;
  reg transfer_in_save;

  reg [15:0] word_count_reg = 16'd0, word_count_next;

  reg [511:0] last_word_data_reg = 512'd0;
  reg [ 63:0] last_word_keep_reg = 64'd0;

  reg [  7:0] roce_bth_op_code_reg = 8'd0;
  reg [ 15:0] roce_bth_p_key_reg = 16'd0;
  reg [ 23:0] roce_bth_psn_reg = 24'd0;
  reg [ 23:0] roce_bth_dest_qp_reg = 24'd0;
  reg         roce_bth_ack_req_reg = 1'd0;

  reg [ 63:0] roce_reth_v_addr_reg = 64'd0;
  reg [ 31:0] roce_reth_r_key_reg = 32'd0;
  reg [ 31:0] roce_reth_length_reg = 32'd0;

  reg [ 31:0] roce_immdh_data_reg = 32'd0;

  //reg [15:0] udp_source_port_reg = 16'd0;
  //reg [15:0] udp_dest_port_reg   = 16'd0;
  //reg [15:0] udp_length_reg      = 16'd0;
  //reg [15:0] udp_checksum_reg    = 16'd0;

  reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;
  reg s_roce_payload_axis_tready_reg = 1'b0, s_roce_payload_axis_tready_next;

  //reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
  //reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

  reg m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;
  reg [47:0] m_eth_dest_mac_reg = 48'd0;
  reg [47:0] m_eth_src_mac_reg = 48'd0;
  reg [15:0] m_eth_type_reg = 16'd0;
  reg [ 3:0] m_ip_version_reg = 4'd0;
  reg [ 3:0] m_ip_ihl_reg = 4'd0;
  reg [ 5:0] m_ip_dscp_reg = 6'd0;
  reg [ 1:0] m_ip_ecn_reg = 2'd0;
  reg [15:0] m_ip_length_reg = 16'd0;
  reg [15:0] m_ip_identification_reg = 16'd0;
  reg [ 2:0] m_ip_flags_reg = 3'd0;
  reg [12:0] m_ip_fragment_offset_reg = 13'd0;
  reg [ 7:0] m_ip_ttl_reg = 8'd0;
  reg [ 7:0] m_ip_protocol_reg = 8'd0;
  reg [15:0] m_ip_header_checksum_reg = 16'd0;
  reg [31:0] m_ip_source_ip_reg = 32'd0;
  reg [31:0] m_ip_dest_ip_reg = 32'd0;
  reg [15:0] m_udp_source_port_reg = 16'd0;
  reg [15:0] m_udp_dest_port_reg = 16'd0;
  reg [15:0] m_udp_length_reg = 16'd0;
  reg [15:0] m_udp_checksum_reg = 16'd0;

  reg        busy_reg = 1'b0;
  reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

  reg [512:0] save_roce_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] save_roce_payload_axis_tkeep_reg = 64'd0;
  reg         save_roce_payload_axis_tlast_reg = 1'b0;
  reg         save_roce_payload_axis_tuser_reg = 1'b0;

  reg [511:0] shift_roce_payload_axis_tdata;
  reg [ 63:0] shift_roce_payload_axis_tkeep;
  reg [511:0] shift_roce_payload_96_axis_tdata;
  reg [ 63:0] shift_roce_payload_96_axis_tkeep;
  reg [511:0] shift_roce_payload_128_axis_tdata;
  reg [ 63:0] shift_roce_payload_128_axis_tkeep;
  reg [511:0] shift_roce_payload_224_axis_tdata;
  reg [ 63:0] shift_roce_payload_224_axis_tkeep;
  reg [511:0] shift_roce_payload_256_axis_tdata;
  reg [ 63:0] shift_roce_payload_256_axis_tkeep;
  reg         shift_roce_payload_96_axis_tvalid;
  reg         shift_roce_payload_128_axis_tvalid;
  reg         shift_roce_payload_224_axis_tvalid;
  reg         shift_roce_payload_256_axis_tvalid;
  reg         shift_roce_payload_96_axis_tlast;
  reg         shift_roce_payload_96_axis_tuser;
  reg         shift_roce_payload_128_axis_tlast;
  reg         shift_roce_payload_128_axis_tuser;
  reg         shift_roce_payload_224_axis_tlast;
  reg         shift_roce_payload_224_axis_tuser;
  reg         shift_roce_payload_256_axis_tlast;
  reg         shift_roce_payload_256_axis_tuser;
  reg         shift_roce_payload_96_s_tready;
  reg         shift_roce_payload_128_s_tready;
  reg         shift_roce_payload_224_s_tready;
  reg         shift_roce_payload_256_s_tready;
  reg         shift_roce_payload_96_extra_cycle_reg = 1'b0;
  reg         shift_roce_payload_128_extra_cycle_reg = 1'b0;
  reg         shift_roce_payload_224_extra_cycle_reg = 1'b0;
  reg         shift_roce_payload_256_extra_cycle_reg = 1'b0;
  reg shift_roce_payload_late_header_reg = 1'b0, shift_roce_payload_late_header_next;

  // internal datapath
  reg  [511:0] m_udp_payload_axis_tdata_int;
  reg  [ 63:0] m_udp_payload_axis_tkeep_int;
  reg          m_udp_payload_axis_tvalid_int;
  reg          m_udp_payload_axis_tready_int_reg = 1'b0;
  reg          m_udp_payload_axis_tlast_int;
  reg          m_udp_payload_axis_tuser_int;
  wire         m_udp_payload_axis_tready_int_early;

  reg [8:0] roce_header_length_bits_reg, roce_header_length_bits_next;


  assign s_roce_bth_ready                = s_roce_bth_ready_reg;
  assign s_roce_reth_ready               = s_roce_bth_ready_reg;
  assign s_roce_immdh_ready              = s_roce_bth_ready_reg;
  assign s_roce_payload_axis_tready      = s_roce_payload_axis_tready_reg;


  assign m_udp_hdr_valid                 = m_udp_hdr_valid_reg;
  assign m_eth_dest_mac                  = m_eth_dest_mac_reg;
  assign m_eth_src_mac                   = m_eth_src_mac_reg;
  assign m_eth_type                      = m_eth_type_reg;
  assign m_ip_version                    = m_ip_version_reg;
  assign m_ip_ihl                        = m_ip_ihl_reg;
  assign m_ip_dscp                       = m_ip_dscp_reg;
  assign m_ip_ecn                        = m_ip_ecn_reg;
  assign m_ip_length                     = m_ip_length_reg;
  assign m_ip_identification             = m_ip_identification_reg;
  assign m_ip_flags                      = m_ip_flags_reg;
  assign m_ip_fragment_offset            = m_ip_fragment_offset_reg;
  assign m_ip_ttl                        = m_ip_ttl_reg;
  assign m_ip_protocol                   = m_ip_protocol_reg;
  assign m_ip_header_checksum            = m_ip_header_checksum_reg;
  assign m_ip_source_ip                  = m_ip_source_ip_reg;
  assign m_ip_dest_ip                    = m_ip_dest_ip_reg;

  assign m_udp_source_port               = m_udp_source_port_reg;
  assign m_udp_dest_port                 = m_udp_dest_port_reg;
  assign m_udp_length                    = m_udp_length_reg;
  assign m_udp_checksum                  = m_udp_checksum_reg;

  assign busy                            = busy_reg;
  assign error_payload_early_termination = error_payload_early_termination_reg;

  function [15:0] keep2count;
    input [63:0] k;
    casez (k)
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0: keep2count = 16'd0;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01: keep2count = 16'd1;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011: keep2count = 16'd2;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111: keep2count = 16'd3;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111: keep2count = 16'd4;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111: keep2count = 16'd5;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111: keep2count = 16'd6;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111: keep2count = 16'd7;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111: keep2count = 16'd8;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111: keep2count = 16'd9;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111: keep2count = 16'd10;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111: keep2count = 16'd11;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111: keep2count = 16'd12;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111: keep2count = 16'd13;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111: keep2count = 16'd14;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111: keep2count = 16'd15;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111: keep2count = 16'd16;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111: keep2count = 16'd17;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111: keep2count = 16'd18;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111: keep2count = 16'd19;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111: keep2count = 16'd20;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111: keep2count = 16'd21;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111: keep2count = 16'd22;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111: keep2count = 16'd23;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111: keep2count = 16'd24;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111: keep2count = 16'd25;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111: keep2count = 16'd26;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111: keep2count = 16'd27;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111: keep2count = 16'd28;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111: keep2count = 16'd29;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111: keep2count = 16'd30;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111: keep2count = 16'd31;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111: keep2count = 16'd32;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111: keep2count = 16'd33;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111: keep2count = 16'd34;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111: keep2count = 16'd35;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111: keep2count = 16'd36;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111: keep2count = 16'd37;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111: keep2count = 16'd38;
      64'bzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111: keep2count = 16'd39;
      64'bzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111: keep2count = 16'd40;
      64'bzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111: keep2count = 16'd41;
      64'bzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111: keep2count = 16'd42;
      64'bzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111: keep2count = 16'd43;
      64'bzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111: keep2count = 16'd44;
      64'bzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111: keep2count = 16'd45;
      64'bzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111: keep2count = 16'd46;
      64'bzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111111: keep2count = 16'd47;
      64'bzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111111: keep2count = 16'd48;
      64'bzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111111: keep2count = 16'd49;
      64'bzzzzzzzzzzzzz011111111111111111111111111111111111111111111111111: keep2count = 16'd50;
      64'bzzzzzzzzzzzz0111111111111111111111111111111111111111111111111111: keep2count = 16'd51;
      64'bzzzzzzzzzzz01111111111111111111111111111111111111111111111111111: keep2count = 16'd52;
      64'bzzzzzzzzzz011111111111111111111111111111111111111111111111111111: keep2count = 16'd53;
      64'bzzzzzzzzz0111111111111111111111111111111111111111111111111111111: keep2count = 16'd54;
      64'bzzzzzzzz01111111111111111111111111111111111111111111111111111111: keep2count = 16'd55;
      64'bzzzzzzz011111111111111111111111111111111111111111111111111111111: keep2count = 16'd56;
      64'bzzzzzz0111111111111111111111111111111111111111111111111111111111: keep2count = 16'd57;
      64'bzzzzz01111111111111111111111111111111111111111111111111111111111: keep2count = 16'd58;
      64'bzzzz011111111111111111111111111111111111111111111111111111111111: keep2count = 16'd59;
      64'bzzz0111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd60;
      64'bzz01111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd61;
      64'bz011111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd62;
      64'b0111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd63;
      64'b1111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd64;
    endcase
  endfunction

  function [63:0] count2keep;
    input [6:0] k;
    case (k)
      7'd0:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000000;
      7'd1:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000001;
      7'd2:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000011;
      7'd3:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000111;
      7'd4:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000001111;
      7'd5:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000011111;
      7'd6:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000111111;
      7'd7:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000001111111;
      7'd8:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000011111111;
      7'd9:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000111111111;
      7'd10:   count2keep = 64'b0000000000000000000000000000000000000000000000000000001111111111;
      7'd11:   count2keep = 64'b0000000000000000000000000000000000000000000000000000011111111111;
      7'd12:   count2keep = 64'b0000000000000000000000000000000000000000000000000000111111111111;
      7'd13:   count2keep = 64'b0000000000000000000000000000000000000000000000000001111111111111;
      7'd14:   count2keep = 64'b0000000000000000000000000000000000000000000000000011111111111111;
      7'd15:   count2keep = 64'b0000000000000000000000000000000000000000000000000111111111111111;
      7'd16:   count2keep = 64'b0000000000000000000000000000000000000000000000001111111111111111;
      7'd17:   count2keep = 64'b0000000000000000000000000000000000000000000000011111111111111111;
      7'd18:   count2keep = 64'b0000000000000000000000000000000000000000000000111111111111111111;
      7'd19:   count2keep = 64'b0000000000000000000000000000000000000000000001111111111111111111;
      7'd20:   count2keep = 64'b0000000000000000000000000000000000000000000011111111111111111111;
      7'd21:   count2keep = 64'b0000000000000000000000000000000000000000000111111111111111111111;
      7'd22:   count2keep = 64'b0000000000000000000000000000000000000000001111111111111111111111;
      7'd23:   count2keep = 64'b0000000000000000000000000000000000000000011111111111111111111111;
      7'd24:   count2keep = 64'b0000000000000000000000000000000000000000111111111111111111111111;
      7'd25:   count2keep = 64'b0000000000000000000000000000000000000001111111111111111111111111;
      7'd26:   count2keep = 64'b0000000000000000000000000000000000000011111111111111111111111111;
      7'd27:   count2keep = 64'b0000000000000000000000000000000000000111111111111111111111111111;
      7'd28:   count2keep = 64'b0000000000000000000000000000000000001111111111111111111111111111;
      7'd29:   count2keep = 64'b0000000000000000000000000000000000011111111111111111111111111111;
      7'd30:   count2keep = 64'b0000000000000000000000000000000000111111111111111111111111111111;
      7'd31:   count2keep = 64'b0000000000000000000000000000000001111111111111111111111111111111;
      7'd32:   count2keep = 64'b0000000000000000000000000000000011111111111111111111111111111111;
      7'd33:   count2keep = 64'b0000000000000000000000000000000111111111111111111111111111111111;
      7'd34:   count2keep = 64'b0000000000000000000000000000001111111111111111111111111111111111;
      7'd35:   count2keep = 64'b0000000000000000000000000000011111111111111111111111111111111111;
      7'd36:   count2keep = 64'b0000000000000000000000000000111111111111111111111111111111111111;
      7'd37:   count2keep = 64'b0000000000000000000000000001111111111111111111111111111111111111;
      7'd38:   count2keep = 64'b0000000000000000000000000011111111111111111111111111111111111111;
      7'd39:   count2keep = 64'b0000000000000000000000000111111111111111111111111111111111111111;
      7'd40:   count2keep = 64'b0000000000000000000000001111111111111111111111111111111111111111;
      7'd41:   count2keep = 64'b0000000000000000000000011111111111111111111111111111111111111111;
      7'd42:   count2keep = 64'b0000000000000000000000111111111111111111111111111111111111111111;
      7'd43:   count2keep = 64'b0000000000000000000001111111111111111111111111111111111111111111;
      7'd44:   count2keep = 64'b0000000000000000000011111111111111111111111111111111111111111111;
      7'd45:   count2keep = 64'b0000000000000000000111111111111111111111111111111111111111111111;
      7'd46:   count2keep = 64'b0000000000000000001111111111111111111111111111111111111111111111;
      7'd47:   count2keep = 64'b0000000000000000011111111111111111111111111111111111111111111111;
      7'd48:   count2keep = 64'b0000000000000000111111111111111111111111111111111111111111111111;
      7'd49:   count2keep = 64'b0000000000000001111111111111111111111111111111111111111111111111;
      7'd50:   count2keep = 64'b0000000000000011111111111111111111111111111111111111111111111111;
      7'd51:   count2keep = 64'b0000000000000111111111111111111111111111111111111111111111111111;
      7'd52:   count2keep = 64'b0000000000001111111111111111111111111111111111111111111111111111;
      7'd53:   count2keep = 64'b0000000000011111111111111111111111111111111111111111111111111111;
      7'd54:   count2keep = 64'b0000000000111111111111111111111111111111111111111111111111111111;
      7'd55:   count2keep = 64'b0000000001111111111111111111111111111111111111111111111111111111;
      7'd56:   count2keep = 64'b0000000011111111111111111111111111111111111111111111111111111111;
      7'd57:   count2keep = 64'b0000000111111111111111111111111111111111111111111111111111111111;
      7'd58:   count2keep = 64'b0000001111111111111111111111111111111111111111111111111111111111;
      7'd59:   count2keep = 64'b0000011111111111111111111111111111111111111111111111111111111111;
      7'd60:   count2keep = 64'b0000111111111111111111111111111111111111111111111111111111111111;
      7'd61:   count2keep = 64'b0001111111111111111111111111111111111111111111111111111111111111;
      7'd62:   count2keep = 64'b0011111111111111111111111111111111111111111111111111111111111111;
      7'd63:   count2keep = 64'b0111111111111111111111111111111111111111111111111111111111111111;
      7'd64:   count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
      default: count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
    endcase
  endfunction

  always @* begin
    shift_roce_payload_96_axis_tdata[95:0]   = save_roce_payload_axis_tdata_reg[511:416];
    shift_roce_payload_96_axis_tkeep[11:0]   = save_roce_payload_axis_tkeep_reg[63:52];

    shift_roce_payload_128_axis_tdata[127:0] = save_roce_payload_axis_tdata_reg[511:384];
    shift_roce_payload_128_axis_tkeep[15:0]  = save_roce_payload_axis_tkeep_reg[63:48];

    shift_roce_payload_224_axis_tdata[223:0] = save_roce_payload_axis_tdata_reg[511:288];
    shift_roce_payload_224_axis_tkeep[27:0]  = save_roce_payload_axis_tkeep_reg[63:36];

    shift_roce_payload_256_axis_tdata[255:0] = save_roce_payload_axis_tdata_reg[511:256];
    shift_roce_payload_256_axis_tkeep[31:0]  = save_roce_payload_axis_tkeep_reg[63:32];

    if (shift_roce_payload_96_extra_cycle_reg) begin
      shift_roce_payload_96_axis_tdata[511:96]   = 416'd0;
      shift_roce_payload_96_axis_tkeep[63:12]    = 52'd0;
      shift_roce_payload_96_axis_tlast  = 1'b1;
      shift_roce_payload_96_axis_tuser  = save_roce_payload_axis_tuser_reg;
      shift_roce_payload_96_axis_tvalid = 1'b1;
      shift_roce_payload_96_s_tready = flush_save;
    end else begin
      shift_roce_payload_96_axis_tdata[511:96] = s_roce_payload_axis_tdata[415:0];
      shift_roce_payload_96_axis_tkeep[63:12] = s_roce_payload_axis_tkeep[51:0];
      shift_roce_payload_96_axis_tlast = (s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:52] == 0));
      shift_roce_payload_96_axis_tuser = (s_roce_payload_axis_tuser && (s_roce_payload_axis_tkeep[63:52] == 0));
      shift_roce_payload_96_axis_tvalid = s_roce_payload_axis_tvalid && s_roce_payload_axis_tready_reg;
      shift_roce_payload_96_s_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tvalid && transfer_in_save) && !save_roce_payload_axis_tlast_reg;
    end

    if (shift_roce_payload_128_extra_cycle_reg) begin
      shift_roce_payload_128_axis_tdata[511:128]   = 384'd0;
      shift_roce_payload_128_axis_tkeep[63:16]    = 48'd0;
      shift_roce_payload_128_axis_tlast  = 1'b1;
      shift_roce_payload_128_axis_tuser  = save_roce_payload_axis_tuser_reg;
      shift_roce_payload_128_axis_tvalid = 1'b1;
      shift_roce_payload_128_s_tready = flush_save;
    end else begin
      shift_roce_payload_128_axis_tdata[511:128] = s_roce_payload_axis_tdata[383:0];
      shift_roce_payload_128_axis_tkeep[63:16] = s_roce_payload_axis_tkeep[47:0];
      shift_roce_payload_128_axis_tlast = (s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:48] == 0));
      shift_roce_payload_128_axis_tuser = (s_roce_payload_axis_tuser && (s_roce_payload_axis_tkeep[63:48] == 0));
      shift_roce_payload_128_axis_tvalid = s_roce_payload_axis_tvalid && s_roce_payload_axis_tready_reg;
      shift_roce_payload_128_s_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tvalid && transfer_in_save) && !save_roce_payload_axis_tlast_reg;
    end

    if (shift_roce_payload_224_extra_cycle_reg) begin
      shift_roce_payload_224_axis_tdata[511:224] = 288'd0;
      shift_roce_payload_224_axis_tkeep[63:28]   = 36'd0;
      shift_roce_payload_224_axis_tlast  = 1'b1;
      shift_roce_payload_224_axis_tuser  = save_roce_payload_axis_tuser_reg;
      shift_roce_payload_224_axis_tvalid = 1'b1;
      shift_roce_payload_224_s_tready = flush_save;
    end else begin
      shift_roce_payload_224_axis_tdata[511:224] = s_roce_payload_axis_tdata[287:0];
      shift_roce_payload_224_axis_tkeep[63:28] = s_roce_payload_axis_tkeep[35:0];
      shift_roce_payload_224_axis_tlast = (s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:36] == 0));
      shift_roce_payload_224_axis_tuser = (s_roce_payload_axis_tuser && (s_roce_payload_axis_tkeep[63:36] == 0));
      shift_roce_payload_224_axis_tvalid = s_roce_payload_axis_tvalid && s_roce_payload_axis_tready_reg;
      shift_roce_payload_224_s_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tvalid && transfer_in_save) && !save_roce_payload_axis_tlast_reg;
    end

    if (shift_roce_payload_256_extra_cycle_reg) begin
      shift_roce_payload_256_axis_tdata[511:256] = 256'd0;
      shift_roce_payload_256_axis_tkeep[63:32]   = 32'd0;
      shift_roce_payload_256_axis_tlast  = 1'b1;
      shift_roce_payload_256_axis_tuser  = save_roce_payload_axis_tuser_reg;
      shift_roce_payload_256_axis_tvalid = 1'b1;
      shift_roce_payload_256_s_tready = flush_save;
    end else begin
      shift_roce_payload_256_axis_tdata[511:256] = s_roce_payload_axis_tdata[255:0];
      shift_roce_payload_256_axis_tkeep[63:32] = s_roce_payload_axis_tkeep[31:0];
      shift_roce_payload_256_axis_tlast = (s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:32] == 0));
      shift_roce_payload_256_axis_tuser = (s_roce_payload_axis_tuser && (s_roce_payload_axis_tkeep[63:32] == 0));
      shift_roce_payload_256_axis_tvalid = s_roce_payload_axis_tvalid && s_roce_payload_axis_tready_reg;
      shift_roce_payload_256_s_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tvalid && transfer_in_save) && !save_roce_payload_axis_tlast_reg;
    end

  end

  always @* begin
    state_next                           = STATE_IDLE;

    shift_roce_payload_late_header_next  = 1'b0;
    roce_header_length_bits_next         = roce_header_length_bits_reg;

    s_roce_bth_ready_next                = 1'b0;
    s_roce_payload_axis_tready_next      = 1'b0;


    store_bth                            = 1'b0;
    store_reth                           = 1'b0;
    store_immdh                          = 1'b0;

    store_last_word                      = 1'b0;

    flush_save                           = 1'b0;
    transfer_in_save                     = 1'b0;

    word_count_next                      = word_count_reg;

    m_udp_hdr_valid_next                 = m_udp_hdr_valid_reg && !m_udp_hdr_ready;

    error_payload_early_termination_next = 1'b0;

    m_udp_payload_axis_tdata_int         = 512'd0;
    m_udp_payload_axis_tkeep_int         = 64'd0;
    m_udp_payload_axis_tvalid_int        = 1'b0;
    m_udp_payload_axis_tlast_int         = 1'b0;
    m_udp_payload_axis_tuser_int         = 1'b0;

    case (state_reg)
      STATE_IDLE: begin
        // idle state - wait for data
        s_roce_bth_ready_next               = !m_udp_hdr_valid_next;

        //s_roce_payload_axis_tready_next = 1'b0;
        //s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
        shift_roce_payload_late_header_next = 1'b0;

        //roce_header_length_bits_int = 8'd0;

        flush_save                          = 1'b1;
        //transfer_in_save = 1'b1;

        if (s_roce_bth_ready && s_roce_bth_valid && ~s_roce_reth_valid && ~s_roce_immdh_valid) begin
          store_bth                    = 1'b1;
          s_roce_bth_ready_next        = 1'b0;
          m_udp_hdr_valid_next         = 1'b1;
          roce_header_length_bits_next = 9'd96;
          state_next                   = STATE_WRITE_BTH;

        end else if (s_roce_bth_ready && s_roce_bth_valid && s_roce_immdh_valid && s_roce_immdh_ready && ~s_roce_reth_valid ) begin
          store_bth                    = 1'b1;
          store_immdh                  = 1'b1;
          s_roce_bth_ready_next        = 1'b0;
          m_udp_hdr_valid_next         = 1'b1;
          roce_header_length_bits_next = 9'd128;
          state_next                   = STATE_WRITE_BTH_IMMDH;
        end else if (s_roce_bth_ready && s_roce_bth_valid &&  s_roce_reth_valid &&  s_roce_reth_ready && ~s_roce_immdh_valid) begin
          store_bth                    = 1'b1;
          store_reth                   = 1'b1;
          s_roce_bth_ready_next        = 1'b0;
          m_udp_hdr_valid_next         = 1'b1;
          roce_header_length_bits_next = 9'd224;
          state_next                   = STATE_WRITE_BTH_RETH;
        end else if (s_roce_bth_ready && s_roce_bth_valid &&  s_roce_reth_valid &&   s_roce_reth_ready & s_roce_immdh_valid & s_roce_immdh_ready) begin
          store_bth                    = 1'b1;
          store_reth                   = 1'b1;
          store_immdh                  = 1'b1;
          s_roce_bth_ready_next        = 1'b0;
          m_udp_hdr_valid_next         = 1'b1;
          roce_header_length_bits_next = 9'd256;
          state_next                   = STATE_WRITE_BTH_RETH_IMMDH;
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_WRITE_BTH: begin
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_96_s_tready;
        // write bth state
        //if (m_udp_payload_axis_tready_int_reg) begin
        if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) begin

          transfer_in_save = 1'b1;

          // word transfer out
          m_udp_payload_axis_tvalid_int = 1'b1;
          m_udp_payload_axis_tdata_int[7:0] = roce_bth_op_code_reg[7:0];
          m_udp_payload_axis_tdata_int[11:8] = 4'b0; // Header version
          m_udp_payload_axis_tdata_int[13:12] = 2'b0; // Pad count
          m_udp_payload_axis_tdata_int[14] = 1'b0; // Mig request
          m_udp_payload_axis_tdata_int[15] = solicited_event_reg; // Solicited Event
          m_udp_payload_axis_tdata_int[23:16] = roce_bth_p_key_reg[15:8];
          m_udp_payload_axis_tdata_int[31:24] = roce_bth_p_key_reg[7:0];
          m_udp_payload_axis_tdata_int[39:32] = 8'b0; // Reserved
          m_udp_payload_axis_tdata_int[47:40] = roce_bth_dest_qp_reg[23:16];
          m_udp_payload_axis_tdata_int[55:48] = roce_bth_dest_qp_reg[15:8];
          m_udp_payload_axis_tdata_int[63:56] = roce_bth_dest_qp_reg[7:0];
          m_udp_payload_axis_tdata_int[70:64] = 7'b0; // Reserved
          m_udp_payload_axis_tdata_int[71] = s_roce_bth_ack_req;
          m_udp_payload_axis_tdata_int[79:72] = roce_bth_psn_reg[23:16];
          m_udp_payload_axis_tdata_int[87:80] = roce_bth_psn_reg[15:8];
          m_udp_payload_axis_tdata_int[95:88] = roce_bth_psn_reg[7:0];
          m_udp_payload_axis_tdata_int[511:96] = shift_roce_payload_96_axis_tdata[511:96];
          m_udp_payload_axis_tkeep_int = {shift_roce_payload_96_axis_tkeep[63:12], 12'hFFF};

          roce_header_length_bits_next = 9'd96;

          s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

          word_count_next = s_udp_length - keep2count(m_udp_payload_axis_tkeep_int) -
          16'd8; // udp hdr

          if (s_udp_length <= 16'd72) begin // full frame (64 bytes) + udp header length (8 bytes) 
          // have entire payload
          //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (shift_roce_payload_96_axis_tlast) begin
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              m_udp_payload_axis_tlast_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_96_s_tready;
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_96_LAST;
            end
          end else begin
            if (shift_roce_payload_96_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_96_s_tready;
              m_udp_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_96;
            end
          end
        end else begin
          state_next = STATE_WRITE_BTH;
        end
      end
      STATE_WRITE_BTH_IMMDH: begin
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_128_s_tready;
        // write bth state
        //if (m_udp_payload_axis_tready_int_reg) begin
        if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) begin

          transfer_in_save = 1'b1;

          // word transfer out
          m_udp_payload_axis_tvalid_int = 1'b1;
          m_udp_payload_axis_tdata_int[7:0] = roce_bth_op_code_reg[7:0];
          m_udp_payload_axis_tdata_int[11:8] = 4'b0; // Header version
          m_udp_payload_axis_tdata_int[13:12] = 2'b0; // Pad count
          m_udp_payload_axis_tdata_int[14] = 1'b0; // Mig request
          m_udp_payload_axis_tdata_int[15] = solicited_event_reg; // Solicited Event
          m_udp_payload_axis_tdata_int[23:16] = roce_bth_p_key_reg[15:8];
          m_udp_payload_axis_tdata_int[31:24] = roce_bth_p_key_reg[7:0];
          m_udp_payload_axis_tdata_int[39:32] = 8'b0; // Reserved
          m_udp_payload_axis_tdata_int[47:40] = roce_bth_dest_qp_reg[23:16];
          m_udp_payload_axis_tdata_int[55:48] = roce_bth_dest_qp_reg[15:8];
          m_udp_payload_axis_tdata_int[63:56] = roce_bth_dest_qp_reg[7:0];
          m_udp_payload_axis_tdata_int[70:64] = 7'b0; // Reserved
          m_udp_payload_axis_tdata_int[71] = s_roce_bth_ack_req;
          m_udp_payload_axis_tdata_int[79:72] = roce_bth_psn_reg[23:16];
          m_udp_payload_axis_tdata_int[87:80] = roce_bth_psn_reg[15:8];
          m_udp_payload_axis_tdata_int[95:88] = roce_bth_psn_reg[7:0];
          m_udp_payload_axis_tdata_int[511:96] = roce_bth_psn_reg[7:0];
          m_udp_payload_axis_tdata_int[103:96] = roce_immdh_data_reg[31:24];
          m_udp_payload_axis_tdata_int[111:104] = roce_immdh_data_reg[23:16];
          m_udp_payload_axis_tdata_int[119:112] = roce_immdh_data_reg[15:8];
          m_udp_payload_axis_tdata_int[127:120] = roce_immdh_data_reg[7:0];
          m_udp_payload_axis_tdata_int[511:128] = shift_roce_payload_128_axis_tdata[511:128];
          m_udp_payload_axis_tkeep_int = {shift_roce_payload_128_axis_tkeep[63:16], 16'hFFFF};

          roce_header_length_bits_next = 9'd128;

          s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

          word_count_next = s_udp_length - keep2count(m_udp_payload_axis_tkeep_int) -
          16'd8; // udp hdr

          if (s_udp_length <= 16'd72) begin // full frame (64 bytes) + udp header length (8 bytes) 
          // have entire payload
          //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (shift_roce_payload_128_axis_tlast) begin
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              m_udp_payload_axis_tlast_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_128_s_tready;
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_128_LAST;
            end
          end else begin
            if (shift_roce_payload_128_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_128_s_tready;
              m_udp_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_128;
            end
          end
        end else begin
          state_next = STATE_WRITE_BTH_IMMDH;
        end
      end
      STATE_WRITE_BTH_RETH: begin
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_224_s_tready;
        //s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
        // write bth and reth state
        //if (m_udp_payload_axis_tready_int_reg ) begin
        if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) begin
          // word transfer out
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          m_udp_payload_axis_tdata_int[7:0] = roce_bth_op_code_reg[7:0];
          m_udp_payload_axis_tdata_int[11:8] = 4'b0; // Header version
          m_udp_payload_axis_tdata_int[13:12] = 2'b0; // Pad count
          m_udp_payload_axis_tdata_int[14] = 1'b0; // Mig request
          m_udp_payload_axis_tdata_int[15] = solicited_event_reg; // Solicited Event
          m_udp_payload_axis_tdata_int[23:16] = roce_bth_p_key_reg[15:8];
          m_udp_payload_axis_tdata_int[31:24] = roce_bth_p_key_reg[7:0];
          m_udp_payload_axis_tdata_int[39:32] = 8'b0; // Reserved
          m_udp_payload_axis_tdata_int[47:40] = roce_bth_dest_qp_reg[23:16];
          m_udp_payload_axis_tdata_int[55:48] = roce_bth_dest_qp_reg[15:8];
          m_udp_payload_axis_tdata_int[63:56] = roce_bth_dest_qp_reg[7:0];
          m_udp_payload_axis_tdata_int[70:64] = 7'b0; // Reserved
          m_udp_payload_axis_tdata_int[71] = s_roce_bth_ack_req;
          m_udp_payload_axis_tdata_int[79:72] = roce_bth_psn_reg[23:16];
          m_udp_payload_axis_tdata_int[87:80] = roce_bth_psn_reg[15:8];
          m_udp_payload_axis_tdata_int[95:88] = roce_bth_psn_reg[7:0];
          m_udp_payload_axis_tdata_int[103:96] = roce_reth_v_addr_reg[63:56];
          m_udp_payload_axis_tdata_int[111:104] = roce_reth_v_addr_reg[55:48];
          m_udp_payload_axis_tdata_int[119:112] = roce_reth_v_addr_reg[47:40];
          m_udp_payload_axis_tdata_int[127:120] = roce_reth_v_addr_reg[39:32];
          m_udp_payload_axis_tdata_int[135:128] = roce_reth_v_addr_reg[31:24];
          m_udp_payload_axis_tdata_int[143:136] = roce_reth_v_addr_reg[23:16];
          m_udp_payload_axis_tdata_int[151:144] = roce_reth_v_addr_reg[15:8];
          m_udp_payload_axis_tdata_int[159:152] = roce_reth_v_addr_reg[7:0];
          m_udp_payload_axis_tdata_int[167:160] = roce_reth_r_key_reg[31:24];
          m_udp_payload_axis_tdata_int[175:168] = roce_reth_r_key_reg[23:16];
          m_udp_payload_axis_tdata_int[183:176] = roce_reth_r_key_reg[15:8];
          m_udp_payload_axis_tdata_int[191:184] = roce_reth_r_key_reg[7:0];
          m_udp_payload_axis_tdata_int[199:192] = roce_reth_length_reg[31:24];
          m_udp_payload_axis_tdata_int[207:200] = roce_reth_length_reg[23:16];
          m_udp_payload_axis_tdata_int[215:208] = roce_reth_length_reg[15:8];
          m_udp_payload_axis_tdata_int[223:216] = roce_reth_length_reg[7:0];
          m_udp_payload_axis_tdata_int[511:224] = shift_roce_payload_224_axis_tdata[511:224];
          m_udp_payload_axis_tkeep_int = {shift_roce_payload_224_axis_tkeep[63:28], 28'hFFFFFFF};

          roce_header_length_bits_next = 9'd224;

          s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

          word_count_next = s_udp_length - keep2count(m_udp_payload_axis_tkeep_int) -
          16'd8; // udp hdr

          if (s_udp_length <= 16'd72) begin // full frame (64 bytes) + udp header length (8 bytes) 
          // have entire payload
          //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (shift_roce_payload_224_axis_tlast) begin
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              s_roce_payload_axis_tready_next = 1'b0;
              m_udp_payload_axis_tlast_int = 1'b1;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_224_s_tready;
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_224_LAST;
            end
          end else begin
            if (shift_roce_payload_224_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_224_s_tready;
              m_udp_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_224;
            end
          end
        end else begin
          state_next = STATE_WRITE_BTH_RETH;
        end
      end
      STATE_WRITE_BTH_RETH_IMMDH: begin
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_256_s_tready;
        //s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
        // write bth and reth state
        //if (m_udp_payload_axis_tready_int_reg ) begin
        if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) begin
          // word transfer out
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          m_udp_payload_axis_tdata_int[7:0] = roce_bth_op_code_reg[7:0];
          m_udp_payload_axis_tdata_int[11:8] = 4'b0; // Header version
          m_udp_payload_axis_tdata_int[13:12] = 2'b0; // Pad count
          m_udp_payload_axis_tdata_int[14] = 1'b0; // Mig request
          m_udp_payload_axis_tdata_int[15] = solicited_event_reg; // Solicited Event
          m_udp_payload_axis_tdata_int[23:16] = roce_bth_p_key_reg[15:8];
          m_udp_payload_axis_tdata_int[31:24] = roce_bth_p_key_reg[7:0];
          m_udp_payload_axis_tdata_int[39:32] = 8'b0; // Reserved
          m_udp_payload_axis_tdata_int[47:40] = roce_bth_dest_qp_reg[23:16];
          m_udp_payload_axis_tdata_int[55:48] = roce_bth_dest_qp_reg[15:8];
          m_udp_payload_axis_tdata_int[63:56] = roce_bth_dest_qp_reg[7:0];
          m_udp_payload_axis_tdata_int[70:64] = 7'b0; // Reserved
          m_udp_payload_axis_tdata_int[71] = s_roce_bth_ack_req;
          m_udp_payload_axis_tdata_int[79:72] = roce_bth_psn_reg[23:16];
          m_udp_payload_axis_tdata_int[87:80] = roce_bth_psn_reg[15:8];
          m_udp_payload_axis_tdata_int[95:88] = roce_bth_psn_reg[7:0];
          m_udp_payload_axis_tdata_int[103:96] = roce_reth_v_addr_reg[63:56];
          m_udp_payload_axis_tdata_int[111:104] = roce_reth_v_addr_reg[55:48];
          m_udp_payload_axis_tdata_int[119:112] = roce_reth_v_addr_reg[47:40];
          m_udp_payload_axis_tdata_int[127:120] = roce_reth_v_addr_reg[39:32];
          m_udp_payload_axis_tdata_int[135:128] = roce_reth_v_addr_reg[31:24];
          m_udp_payload_axis_tdata_int[143:136] = roce_reth_v_addr_reg[23:16];
          m_udp_payload_axis_tdata_int[151:144] = roce_reth_v_addr_reg[15:8];
          m_udp_payload_axis_tdata_int[159:152] = roce_reth_v_addr_reg[7:0];
          m_udp_payload_axis_tdata_int[167:160] = roce_reth_r_key_reg[31:24];
          m_udp_payload_axis_tdata_int[175:168] = roce_reth_r_key_reg[23:16];
          m_udp_payload_axis_tdata_int[183:176] = roce_reth_r_key_reg[15:8];
          m_udp_payload_axis_tdata_int[191:184] = roce_reth_r_key_reg[7:0];
          m_udp_payload_axis_tdata_int[199:192] = roce_reth_length_reg[31:24];
          m_udp_payload_axis_tdata_int[207:200] = roce_reth_length_reg[23:16];
          m_udp_payload_axis_tdata_int[215:208] = roce_reth_length_reg[15:8];
          m_udp_payload_axis_tdata_int[223:216] = roce_reth_length_reg[7:0];
          m_udp_payload_axis_tdata_int[231:224] = roce_immdh_data_reg[31:24];
          m_udp_payload_axis_tdata_int[239:232] = roce_immdh_data_reg[23:16];
          m_udp_payload_axis_tdata_int[247:240] = roce_immdh_data_reg[15:8];
          m_udp_payload_axis_tdata_int[255:248] = roce_immdh_data_reg[7:0];
          m_udp_payload_axis_tdata_int[511:256] = shift_roce_payload_256_axis_tdata[511:256];
          m_udp_payload_axis_tkeep_int = {shift_roce_payload_256_axis_tkeep[63:32], 32'hFFFFFFFF};

          roce_header_length_bits_next = 9'd256;

          s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;

          word_count_next = s_udp_length - keep2count(m_udp_payload_axis_tkeep_int) -
          16'd8; // udp hdr

          if (s_udp_length <= 16'd72) begin // full frame (64 bytes) + udp header length (8 bytes) 
          // have entire payload
          //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (shift_roce_payload_256_axis_tlast) begin
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              s_roce_payload_axis_tready_next = 1'b0;
              m_udp_payload_axis_tlast_int = 1'b1;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_256_s_tready;
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_256_LAST;
            end
          end else begin
            if (shift_roce_payload_256_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_roce_payload_axis_tready_next = shift_roce_payload_256_s_tready;
              m_udp_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_256;
            end
          end
        end else begin
          state_next = STATE_WRITE_BTH_RETH_IMMDH;
        end
      end
      STATE_WRITE_PAYLOAD_96: begin
        // write payload
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_96_s_tready;

        m_udp_payload_axis_tdata_int = shift_roce_payload_96_axis_tdata;
        m_udp_payload_axis_tkeep_int = shift_roce_payload_96_axis_tkeep;
        m_udp_payload_axis_tlast_int = shift_roce_payload_96_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_96_axis_tuser;


        store_last_word = 1'b1;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_96_axis_tvalid) begin
          // word transfer through
          word_count_next = word_count_reg - 16'd64;
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          if (word_count_reg - keep2count(m_udp_payload_axis_tkeep_int) == 16'd0) begin
            //if (word_count_reg  <= 16'd64) begin
            // have entire payload
            //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (m_udp_payload_axis_tlast_int) begin
              /*
              if (keep2count(m_udp_payload_axis_tkeep_int) < word_count_reg[6:0]) begin
                // end of frame, but length does not match
                error_payload_early_termination_next = 1'b1;
                m_udp_payload_axis_tuser_int = 1'b1;
              end
              */
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_96_LAST;
            end
          end else begin
            if (m_udp_payload_axis_tlast_int) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              m_udp_payload_axis_tuser_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_96;
            end
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_96;
        end
      end
      STATE_WRITE_PAYLOAD_96_LAST: begin
        // read and discard until end of frame
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_96_s_tready;

        m_udp_payload_axis_tdata_int = last_word_data_reg;
        m_udp_payload_axis_tkeep_int = last_word_keep_reg;
        m_udp_payload_axis_tlast_int = shift_roce_payload_96_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_96_axis_tuser;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_96_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (m_udp_payload_axis_tlast_int) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            m_udp_payload_axis_tvalid_int = 1'b1;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WRITE_PAYLOAD_96_LAST;
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_96_LAST;
        end
      end
      STATE_WRITE_PAYLOAD_128: begin
        // write payload
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_128_s_tready;

        m_udp_payload_axis_tdata_int = shift_roce_payload_128_axis_tdata;
        m_udp_payload_axis_tkeep_int = shift_roce_payload_128_axis_tkeep;
        m_udp_payload_axis_tlast_int = shift_roce_payload_128_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_128_axis_tuser;


        store_last_word = 1'b1;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_128_axis_tvalid) begin
          // word transfer through
          word_count_next = word_count_reg - 16'd64;
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          if (word_count_reg - keep2count(m_udp_payload_axis_tkeep_int) == 16'd0) begin
            //if (word_count_reg  <= 16'd64) begin
            // have entire payload
            //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (m_udp_payload_axis_tlast_int) begin
              /*
              if (keep2count(m_udp_payload_axis_tkeep_int) < word_count_reg[6:0]) begin
                // end of frame, but length does not match
                error_payload_early_termination_next = 1'b1;
                m_udp_payload_axis_tuser_int = 1'b1;
              end
              */
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_128_LAST;
            end
          end else begin
            if (m_udp_payload_axis_tlast_int) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              m_udp_payload_axis_tuser_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_128;
            end
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_128;
        end
      end
      STATE_WRITE_PAYLOAD_128_LAST: begin
        // read and discard until end of frame
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_128_s_tready;

        m_udp_payload_axis_tdata_int = last_word_data_reg;
        m_udp_payload_axis_tkeep_int = last_word_keep_reg;
        m_udp_payload_axis_tlast_int = shift_roce_payload_128_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_128_axis_tuser;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_128_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (m_udp_payload_axis_tlast_int) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            m_udp_payload_axis_tvalid_int = 1'b1;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WRITE_PAYLOAD_128_LAST;
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_128_LAST;
        end
      end
      STATE_WRITE_PAYLOAD_224: begin
        // write payload
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_224_s_tready;

        m_udp_payload_axis_tdata_int = shift_roce_payload_224_axis_tdata;
        m_udp_payload_axis_tkeep_int = shift_roce_payload_224_axis_tkeep;
        m_udp_payload_axis_tlast_int = shift_roce_payload_224_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_224_axis_tuser;


        store_last_word = 1'b1;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_224_axis_tvalid) begin
          // word transfer through
          word_count_next = word_count_reg - 16'd64;
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          if (word_count_reg - keep2count(m_udp_payload_axis_tkeep_int) == 16'd0) begin
            //if (word_count_reg  <= 16'd64) begin
            // have entire payload
            //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (m_udp_payload_axis_tlast_int) begin
              /*
              if (keep2count(m_udp_payload_axis_tkeep_int) < word_count_reg[6:0]) begin
                // end of frame, but length does not match
                error_payload_early_termination_next = 1'b1;
                m_udp_payload_axis_tuser_int = 1'b1;
              end
              */
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_224_LAST;
            end
          end else begin
            if (m_udp_payload_axis_tlast_int) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              m_udp_payload_axis_tuser_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_224;
            end
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_224;
        end
      end
      STATE_WRITE_PAYLOAD_224_LAST: begin
        // read and discard until end of frame
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_224_s_tready;

        m_udp_payload_axis_tdata_int = last_word_data_reg;
        m_udp_payload_axis_tkeep_int = last_word_keep_reg;
        m_udp_payload_axis_tlast_int = shift_roce_payload_224_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_224_axis_tuser;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_224_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (m_udp_payload_axis_tlast_int) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            m_udp_payload_axis_tvalid_int = 1'b1;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WRITE_PAYLOAD_224_LAST;
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_224_LAST;
        end
      end
      STATE_WRITE_PAYLOAD_256: begin
        // write payload
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_256_s_tready;

        m_udp_payload_axis_tdata_int = shift_roce_payload_256_axis_tdata;
        m_udp_payload_axis_tkeep_int = shift_roce_payload_256_axis_tkeep;
        m_udp_payload_axis_tlast_int = shift_roce_payload_256_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_256_axis_tuser;


        store_last_word = 1'b1;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_256_axis_tvalid) begin
          // word transfer through
          word_count_next = word_count_reg - 16'd64;
          transfer_in_save = 1'b1;
          m_udp_payload_axis_tvalid_int = 1'b1;
          if (word_count_reg - keep2count(m_udp_payload_axis_tkeep_int) == 16'd0) begin
            //if (word_count_reg  <= 16'd64) begin
            // have entire payload
            //m_udp_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (m_udp_payload_axis_tlast_int) begin
              /*
              if (keep2count(m_udp_payload_axis_tkeep_int) < word_count_reg[6:0]) begin
                // end of frame, but length does not match
                error_payload_early_termination_next = 1'b1;
                m_udp_payload_axis_tuser_int = 1'b1;
              end
              */
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              m_udp_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_256_LAST;
            end
          end else begin
            if (m_udp_payload_axis_tlast_int) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              m_udp_payload_axis_tuser_int = 1'b1;
              s_roce_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_roce_bth_ready_next = !m_udp_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              state_next = STATE_WRITE_PAYLOAD_256;
            end
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_256;
        end
      end
      STATE_WRITE_PAYLOAD_256_LAST: begin
        // read and discard until end of frame
        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_256_s_tready;

        m_udp_payload_axis_tdata_int = last_word_data_reg;
        m_udp_payload_axis_tkeep_int = last_word_keep_reg;
        m_udp_payload_axis_tlast_int = shift_roce_payload_256_axis_tlast;
        m_udp_payload_axis_tuser_int = shift_roce_payload_256_axis_tuser;

        if (m_udp_payload_axis_tready_int_reg && shift_roce_payload_256_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (m_udp_payload_axis_tlast_int) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            m_udp_payload_axis_tvalid_int = 1'b1;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WRITE_PAYLOAD_256_LAST;
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_256_LAST;
        end
      end
      STATE_WAIT_LAST: begin
        // read and discard until end of frame
        s_roce_payload_axis_tready_next = shift_roce_payload_96_s_tready | shift_roce_payload_128_s_tready | shift_roce_payload_224_s_tready | shift_roce_payload_256_s_tready;

        if (shift_roce_payload_96_axis_tvalid | shift_roce_payload_128_axis_tvalid | shift_roce_payload_224_axis_tvalid | shift_roce_payload_256_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (shift_roce_payload_256_axis_tlast && roce_header_length_bits_reg == 9'd96) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            state_next = STATE_IDLE;
          end else if (shift_roce_payload_128_axis_tlast && roce_header_length_bits_reg == 9'd128) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            state_next = STATE_IDLE;
          end else if (shift_roce_payload_224_axis_tlast && roce_header_length_bits_reg == 9'd224) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            state_next = STATE_IDLE;
          end else if (shift_roce_payload_256_axis_tlast && roce_header_length_bits_reg == 9'd256) begin
            s_roce_bth_ready_next = !m_udp_hdr_valid_next;
            s_roce_payload_axis_tready_next = 1'b0;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WAIT_LAST;
          end
        end else begin
          state_next = STATE_WAIT_LAST;
        end
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state_reg                              <= STATE_IDLE;
      s_roce_bth_ready_reg                   <= 1'b0;
      s_roce_payload_axis_tready_reg         <= 1'b0;
      m_udp_hdr_valid_reg                    <= 1'b0;
      roce_header_length_bits_reg            <= 9'd0;
      save_roce_payload_axis_tlast_reg       <= 1'b0;
      shift_roce_payload_96_extra_cycle_reg  <= 1'b0;
      shift_roce_payload_128_extra_cycle_reg <= 1'b0;
      shift_roce_payload_224_extra_cycle_reg <= 1'b0;
      shift_roce_payload_256_extra_cycle_reg <= 1'b0;
      busy_reg                               <= 1'b0;
      error_payload_early_termination_reg    <= 1'b0;
    end else begin
      state_reg                           <= state_next;

      s_roce_bth_ready_reg                <= s_roce_bth_ready_next;

      s_roce_payload_axis_tready_reg      <= s_roce_payload_axis_tready_next;

      m_udp_hdr_valid_reg                 <= m_udp_hdr_valid_next;

      roce_header_length_bits_reg         <= roce_header_length_bits_next;

      busy_reg                            <= state_next != STATE_IDLE;

      error_payload_early_termination_reg <= error_payload_early_termination_next;

      shift_roce_payload_late_header_reg  <= shift_roce_payload_late_header_next;

      if (flush_save) begin
        save_roce_payload_axis_tlast_reg       <= 1'b0;
        shift_roce_payload_96_extra_cycle_reg  <= 1'b0;
        shift_roce_payload_128_extra_cycle_reg <= 1'b0;
        shift_roce_payload_224_extra_cycle_reg <= 1'b0;
        shift_roce_payload_256_extra_cycle_reg <= 1'b0;
      end else if (transfer_in_save) begin
        save_roce_payload_axis_tlast_reg <= s_roce_payload_axis_tlast;
        shift_roce_payload_96_extra_cycle_reg  <= s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:51] != 0);
        shift_roce_payload_128_extra_cycle_reg <= s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:48] != 0);
        shift_roce_payload_224_extra_cycle_reg <= s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:36] != 0);
        shift_roce_payload_256_extra_cycle_reg <= s_roce_payload_axis_tlast && (s_roce_payload_axis_tkeep[63:32] != 0);
      end
    end

    word_count_reg <= word_count_next;

    // datapath
    if (store_bth) begin // bth should always be present
      m_eth_dest_mac_reg <= s_eth_dest_mac;
      m_eth_src_mac_reg <= s_eth_src_mac;
      m_eth_type_reg <= s_eth_type;
      m_ip_version_reg <= s_ip_version;
      m_ip_ihl_reg <= s_ip_ihl;
      m_ip_dscp_reg <= s_ip_dscp;
      m_ip_ecn_reg <= s_ip_ecn;
      m_ip_length_reg <= s_udp_length + 20;
      m_ip_identification_reg <= s_ip_identification;
      m_ip_flags_reg <= s_ip_flags;
      m_ip_fragment_offset_reg <= s_ip_fragment_offset;
      m_ip_ttl_reg <= s_ip_ttl;
      m_ip_protocol_reg <= s_ip_protocol;
      m_ip_header_checksum_reg <= s_ip_header_checksum;
      m_ip_source_ip_reg <= s_ip_source_ip;
      m_ip_dest_ip_reg <= s_ip_dest_ip;
      m_udp_source_port_reg <= s_udp_source_port;
      m_udp_dest_port_reg <= RoCE_udp_port;
      m_udp_length_reg <= s_udp_length;
      m_udp_checksum_reg <= 16'h0000;

      roce_bth_op_code_reg <= s_roce_bth_op_code;
      roce_bth_p_key_reg   <= s_roce_bth_p_key;
      roce_bth_psn_reg     <= s_roce_bth_psn;
      roce_bth_dest_qp_reg <= s_roce_bth_dest_qp;
      roce_bth_ack_req_reg <= s_roce_bth_ack_req;
      if (s_roce_bth_op_code == RC_SEND_FIRST || s_roce_bth_op_code == RC_SEND_MIDDLE || s_roce_bth_op_code == RC_SEND_LAST || s_roce_bth_op_code == RC_SEND_LAST_IMD || s_roce_bth_op_code == RC_SEND_ONLY || s_roce_bth_op_code == RC_SEND_ONLY_IMD) begin
        // SEND operation
        solicited_event_reg  <= 1'b1;
      end else if (s_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD || s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD) begin
        // WRITE with IMMD
        solicited_event_reg  <= 1'b1;
      end else begin
        // WRITE operation
        solicited_event_reg  <= 1'b0;
      end
    end
    if (store_reth) begin
      roce_reth_v_addr_reg = s_roce_reth_v_addr;
      roce_reth_r_key_reg  = s_roce_reth_r_key;
      roce_reth_length_reg = s_roce_reth_length;
    end
    if (store_immdh) begin
      roce_immdh_data_reg = s_roce_immdh_data;
    end

    if (store_last_word) begin
      last_word_data_reg <= m_udp_payload_axis_tdata_int;
      last_word_keep_reg <= m_udp_payload_axis_tkeep_int;
    end

    if (transfer_in_save) begin
      save_roce_payload_axis_tdata_reg <= s_roce_payload_axis_tdata;
      save_roce_payload_axis_tkeep_reg <= s_roce_payload_axis_tkeep;
      save_roce_payload_axis_tuser_reg <= s_roce_payload_axis_tuser;
    end
  end

  // output datapath logic
  reg [511:0] m_udp_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] m_udp_payload_axis_tkeep_reg = 64'd0;
  reg m_udp_payload_axis_tvalid_reg = 1'b0, m_udp_payload_axis_tvalid_next;
  reg         m_udp_payload_axis_tlast_reg = 1'b0;
  reg         m_udp_payload_axis_tuser_reg = 1'b0;

  reg [511:0] temp_m_udp_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] temp_m_udp_payload_axis_tkeep_reg = 64'd0;
  reg temp_m_udp_payload_axis_tvalid_reg = 1'b0, temp_m_udp_payload_axis_tvalid_next;
  reg temp_m_udp_payload_axis_tlast_reg = 1'b0;
  reg temp_m_udp_payload_axis_tuser_reg = 1'b0;

  // datapath control
  reg store_udp_payload_int_to_output;
  reg store_udp_payload_int_to_temp;
  reg store_udp_payload_axis_temp_to_output;

  assign m_udp_payload_axis_tdata = m_udp_payload_axis_tdata_reg;
  assign m_udp_payload_axis_tkeep = m_udp_payload_axis_tkeep_reg;
  assign m_udp_payload_axis_tvalid = m_udp_payload_axis_tvalid_reg;
  assign m_udp_payload_axis_tlast = m_udp_payload_axis_tlast_reg;
  assign m_udp_payload_axis_tuser = m_udp_payload_axis_tuser_reg;

  // enable ready input next cycle if output is ready or if both output registers are empty
  assign m_udp_payload_axis_tready_int_early = m_udp_payload_axis_tready || (!temp_m_udp_payload_axis_tvalid_reg && !m_udp_payload_axis_tvalid_reg);

  always @* begin
    // transfer sink ready state to source
    m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_reg;
    temp_m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;

    store_udp_payload_int_to_output = 1'b0;
    store_udp_payload_int_to_temp = 1'b0;
    store_udp_payload_axis_temp_to_output = 1'b0;

    if (m_udp_payload_axis_tready_int_reg) begin
      // input is ready
      if (m_udp_payload_axis_tready | !m_udp_payload_axis_tvalid_reg) begin
        // output is ready or currently not valid, transfer data to output
        m_udp_payload_axis_tvalid_next  = m_udp_payload_axis_tvalid_int;
        store_udp_payload_int_to_output = 1'b1;
      end else begin
        // output is not ready, store input in temp
        temp_m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
        store_udp_payload_int_to_temp = 1'b1;
      end
    end else if (m_udp_payload_axis_tready) begin
      // input is not ready, but output is ready
      m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;
      temp_m_udp_payload_axis_tvalid_next = 1'b0;
      store_udp_payload_axis_temp_to_output = 1'b1;
    end
  end

  always @(posedge clk) begin
    m_udp_payload_axis_tvalid_reg <= m_udp_payload_axis_tvalid_next;
    m_udp_payload_axis_tready_int_reg <= m_udp_payload_axis_tready_int_early;
    temp_m_udp_payload_axis_tvalid_reg <= temp_m_udp_payload_axis_tvalid_next;

    // datapath
    if (store_udp_payload_int_to_output) begin
      m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
      m_udp_payload_axis_tkeep_reg <= m_udp_payload_axis_tkeep_int;
      m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
      m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
    end else if (store_udp_payload_axis_temp_to_output) begin
      m_udp_payload_axis_tdata_reg <= temp_m_udp_payload_axis_tdata_reg;
      m_udp_payload_axis_tkeep_reg <= temp_m_udp_payload_axis_tkeep_reg;
      m_udp_payload_axis_tlast_reg <= temp_m_udp_payload_axis_tlast_reg;
      m_udp_payload_axis_tuser_reg <= temp_m_udp_payload_axis_tuser_reg;
    end

    if (store_udp_payload_int_to_temp) begin
      temp_m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
      temp_m_udp_payload_axis_tkeep_reg <= m_udp_payload_axis_tkeep_int;
      temp_m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
      temp_m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
    end

    if (rst) begin
      m_udp_payload_axis_tvalid_reg <= 1'b0;
      m_udp_payload_axis_tready_int_reg <= 1'b0;
      temp_m_udp_payload_axis_tvalid_reg <= 1'b0;
    end
  end

endmodule


`resetall
