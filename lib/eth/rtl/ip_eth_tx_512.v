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

/*
* Modified by Gabriele Bortolato gabriele.bortolato@cern.ch
* Need to support RoCEv2 UDP packets, udp_length is increased by 4 to accomodate the ICRC value.
* The actual value is inserted later after the IP stack (ICRC is computed on UDP and IP headers as well).
* */


// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * IP ethernet frame transmitter (IP frame in, Ethernet frame out, 512 bit datapath)
 */
module ip_eth_tx_512 (
    input wire clk,
    input wire rst,

    /*
     * IP frame input
     */
    input  wire         s_ip_hdr_valid,
    output wire         s_ip_hdr_ready,
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_length,
    input  wire [ 15:0] s_ip_identification,
    input  wire [  2:0] s_ip_flags,
    input  wire [ 12:0] s_ip_fragment_offset,
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
     * Status signals
     */
    output wire busy,
    output wire error_payload_early_termination
);

  /*

IP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets
 payload                     length octets

This module receives an IP frame with header fields in parallel along with the
payload in an AXI stream, combines the header with the payload, passes through
the Ethernet headers, and transmits the complete Ethernet payload on an AXI
interface.

*/

  localparam [2:0]
    STATE_IDLE = 3'd0,
    STATE_WRITE_HEADER = 3'd1,
    STATE_WRITE_PAYLOAD = 3'd2,
    STATE_WRITE_PAYLOAD_LAST = 3'd3,
    STATE_WAIT_LAST = 3'd4;

  reg [2:0] state_reg = STATE_IDLE, state_next;

  // datapath control signals
  reg store_ip_hdr;
  reg store_last_word;

  reg [15:0] word_count_reg = 16'd0, word_count_next;

  reg flush_save;
  reg transfer_in_save;

  reg [19:0] hdr_sum_temp;
  reg [19:0] hdr_sum_reg = 20'd0, hdr_sum_next;

  reg [511:0] last_word_data_reg = 512'd0;
  reg [ 63:0] last_word_keep_reg = 64'd0;

  reg [  5:0] ip_dscp_reg = 6'd0;
  reg [  1:0] ip_ecn_reg = 2'd0;
  reg [ 15:0] ip_length_reg = 16'd0;
  reg [ 15:0] ip_length_roce_reg = 16'd0;
  reg [ 15:0] ip_identification_reg = 16'd0;
  reg [  2:0] ip_flags_reg = 3'd0;
  reg [ 12:0] ip_fragment_offset_reg = 13'd0;
  reg [  7:0] ip_ttl_reg = 8'd0;
  reg [  7:0] ip_protocol_reg = 8'd0;
  reg [ 31:0] ip_source_ip_reg = 32'd0;
  reg [ 31:0] ip_dest_ip_reg = 32'd0;
  reg         is_roce_packet_reg = 1'b0;

  reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;
  reg s_ip_payload_axis_tready_reg = 1'b0, s_ip_payload_axis_tready_next;

  reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
  reg [47:0] m_eth_dest_mac_reg = 48'd0;
  reg [47:0] m_eth_src_mac_reg = 48'd0;
  reg [15:0] m_eth_type_reg = 16'd0;

  reg m_is_roce_packet_reg = 1'b0;

  reg busy_reg = 1'b0;
  reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

  reg  [511:0] save_ip_payload_axis_tdata_reg = 512'd0;
  reg  [ 63:0] save_ip_payload_axis_tkeep_reg = 64'd0;
  reg          save_ip_payload_axis_tlast_reg = 1'b0;
  reg          save_ip_payload_axis_tuser_reg = 1'b0;

  reg  [511:0] shift_ip_payload_axis_tdata;
  reg  [ 63:0] shift_ip_payload_axis_tkeep;
  reg          shift_ip_payload_axis_tvalid;
  reg          shift_ip_payload_axis_tlast;
  reg          shift_ip_payload_axis_tuser;
  reg          shift_ip_payload_s_tready;
  reg          shift_ip_payload_extra_cycle_reg = 1'b0;

  // internal datapath
  reg  [511:0] m_eth_payload_axis_tdata_int;
  reg  [ 63:0] m_eth_payload_axis_tkeep_int;
  reg          m_eth_payload_axis_tvalid_int;
  reg          m_eth_payload_axis_tready_int_reg = 1'b0;
  reg          m_eth_payload_axis_tlast_int;
  reg          m_eth_payload_axis_tuser_int;
  wire         m_eth_payload_axis_tready_int_early;

  wire [ 15:0] ip_length_roce_int;

  assign ip_length_roce_int = s_ip_length + 16'd4;

  assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
  assign s_ip_payload_axis_tready = s_ip_payload_axis_tready_reg;

  assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
  assign m_eth_dest_mac = m_eth_dest_mac_reg;
  assign m_eth_src_mac = m_eth_src_mac_reg;
  assign m_eth_type = m_eth_type_reg;
  assign m_is_roce_packet = m_is_roce_packet_reg;

  assign busy = busy_reg;
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
    shift_ip_payload_axis_tdata[159:0] = save_ip_payload_axis_tdata_reg[511:352];
    shift_ip_payload_axis_tkeep[19:0]  = save_ip_payload_axis_tkeep_reg[63:44];

    if (shift_ip_payload_extra_cycle_reg) begin
      shift_ip_payload_axis_tdata[511:160] = 352'd0;
      shift_ip_payload_axis_tkeep[63:20] = 44'd0;
      shift_ip_payload_axis_tvalid = 1'b1;
      shift_ip_payload_axis_tlast = save_ip_payload_axis_tlast_reg;
      shift_ip_payload_axis_tuser = save_ip_payload_axis_tuser_reg;
      shift_ip_payload_s_tready = flush_save;
    end else begin
      shift_ip_payload_axis_tdata[511:160] = s_ip_payload_axis_tdata[351:0];
      shift_ip_payload_axis_tkeep[63:20] = s_ip_payload_axis_tkeep[43:0];
      shift_ip_payload_axis_tvalid = s_ip_payload_axis_tvalid;
      shift_ip_payload_axis_tlast = (s_ip_payload_axis_tlast && (s_ip_payload_axis_tkeep[63:44] == 0));
      shift_ip_payload_axis_tuser = (s_ip_payload_axis_tuser && (s_ip_payload_axis_tkeep[63:44] == 0));
      shift_ip_payload_s_tready = !(s_ip_payload_axis_tlast && s_ip_payload_axis_tvalid && transfer_in_save);
    end
  end

  always @* begin
    state_next = STATE_IDLE;

    s_ip_hdr_ready_next = 1'b0;
    s_ip_payload_axis_tready_next = 1'b0;

    store_ip_hdr = 1'b0;

    store_last_word = 1'b0;

    flush_save = 1'b0;
    transfer_in_save = 1'b0;

    word_count_next = word_count_reg;

    hdr_sum_temp = 20'd0;
    hdr_sum_next = hdr_sum_reg;

    m_eth_hdr_valid_next = m_eth_hdr_valid_reg && !m_eth_hdr_ready;

    error_payload_early_termination_next = 1'b0;

    m_eth_payload_axis_tdata_int = 1'b0;
    m_eth_payload_axis_tkeep_int = 1'b0;
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int = 1'b0;
    m_eth_payload_axis_tuser_int = 1'b0;

    case (state_reg)
      STATE_IDLE: begin
        // idle state - wait for data
        flush_save = 1'b1;
        s_ip_hdr_ready_next = !m_eth_hdr_valid_next;

        if (s_ip_hdr_ready && s_ip_hdr_valid) begin
          store_ip_hdr = 1'b1;
          if (s_is_roce_packet) begin
            hdr_sum_next = {4'd4, 4'd5, s_ip_dscp, s_ip_ecn} +
                               ip_length_roce_int +
                               s_ip_identification +
                               {s_ip_flags, s_ip_fragment_offset} +
                               {s_ip_ttl, s_ip_protocol} +
                               s_ip_source_ip[31:16] +
                               s_ip_source_ip[15: 0] +
                               s_ip_dest_ip[31:16] +
                               s_ip_dest_ip[15: 0];
          end else begin
            hdr_sum_next = {4'd4, 4'd5, s_ip_dscp, s_ip_ecn} +
                               s_ip_length +
                               s_ip_identification +
                               {s_ip_flags, s_ip_fragment_offset} +
                               {s_ip_ttl, s_ip_protocol} +
                               s_ip_source_ip[31:16] +
                               s_ip_source_ip[15: 0] +
                               s_ip_dest_ip[31:16] +
                               s_ip_dest_ip[15: 0];
          end
          // will this thing work??
          hdr_sum_temp = hdr_sum_next[15:0] + hdr_sum_next[19:16];
          hdr_sum_temp = hdr_sum_temp[15:0] + hdr_sum_temp[16];
          s_ip_hdr_ready_next = 1'b0;
          m_eth_hdr_valid_next = 1'b1;
          /*
          s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;
          if (m_eth_payload_axis_tready_int_reg && shift_ip_payload_axis_tvalid) begin
            transfer_in_save = 1'b1;
            m_eth_payload_axis_tvalid_int = 1'b1;
            m_eth_payload_axis_tdata_int[7:0] = {4'd4, 4'd5};  // ip_version, ip_ihl
            m_eth_payload_axis_tdata_int[15:8] = {s_ip_dscp, s_ip_ecn};
            if (s_is_roce_packet) begin
              m_eth_payload_axis_tdata_int[23:16] = ip_length_roce_int[15:8];
              m_eth_payload_axis_tdata_int[31:24] = ip_length_roce_int[7:0];
            end else begin
              m_eth_payload_axis_tdata_int[23:16] = s_ip_length[15:8];
              m_eth_payload_axis_tdata_int[31:24] = s_ip_length[7:0];
            end
            m_eth_payload_axis_tdata_int[39:32]   = s_ip_identification[15:8];
            m_eth_payload_axis_tdata_int[47:40]   = s_ip_identification[7:0];
            m_eth_payload_axis_tdata_int[55:48]   = {s_ip_flags, s_ip_fragment_offset[12:8]};
            m_eth_payload_axis_tdata_int[63:56]   = s_ip_fragment_offset[7:0];
            m_eth_payload_axis_tdata_int[71:64]   = s_ip_ttl;
            m_eth_payload_axis_tdata_int[79:72]   = s_ip_protocol[7:0];
            m_eth_payload_axis_tdata_int[87:80]   = ~hdr_sum_temp[15:8];
            m_eth_payload_axis_tdata_int[95:88]   = ~hdr_sum_temp[7:0];
            m_eth_payload_axis_tdata_int[103:96]  = s_ip_source_ip[31:24];
            m_eth_payload_axis_tdata_int[111:104] = s_ip_source_ip[23:16];
            m_eth_payload_axis_tdata_int[119:112] = s_ip_source_ip[15:8];
            m_eth_payload_axis_tdata_int[127:120] = s_ip_source_ip[7:0];
            m_eth_payload_axis_tdata_int[135:128] = s_ip_dest_ip[31:24];
            m_eth_payload_axis_tdata_int[143:136] = s_ip_dest_ip[23:16];
            m_eth_payload_axis_tdata_int[152:144] = s_ip_dest_ip[15:8];
            m_eth_payload_axis_tdata_int[159:152] = s_ip_dest_ip[7:0];
            m_eth_payload_axis_tdata_int[511:160] = shift_ip_payload_axis_tdata[511:160];
            m_eth_payload_axis_tkeep_int          = {shift_ip_payload_axis_tkeep[63:20], 20'hFFFFF};
            s_ip_payload_axis_tready_next         = m_eth_payload_axis_tready_int_early;

            word_count_next = s_ip_length - keep2count(m_eth_payload_axis_tkeep_int);
        end
        
          state_next = STATE_WRITE_HEADER;
          if (s_ip_length - keep2count(m_eth_payload_axis_tkeep_int) == 16'd0) begin
            // have entire payload 
            if (shift_ip_payload_axis_tlast) begin
              m_eth_payload_axis_tlast_int = 1'b1;
              s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
              s_ip_payload_axis_tready_next = 1'b0;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_ip_payload_axis_tready_next = shift_ip_payload_s_tready;
              m_eth_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_LAST;
            end
          end else begin
            if (shift_ip_payload_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_ip_payload_axis_tready_next = shift_ip_payload_s_tready;
              m_eth_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD;
            end
        end
        */
          state_next = STATE_WRITE_HEADER;
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_WRITE_HEADER: begin
        // write header
        s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_ip_payload_s_tready;

        if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
          transfer_in_save = 1'b1;

          m_eth_payload_axis_tvalid_int = 1'b1;
          hdr_sum_temp = hdr_sum_reg[15:0] + hdr_sum_reg[19:16];
          hdr_sum_temp = hdr_sum_temp[15:0] + hdr_sum_temp[16];

          m_eth_payload_axis_tdata_int[7:0] = {4'd4, 4'd5};  // ip_version, ip_ihl
          m_eth_payload_axis_tdata_int[15:8] = {ip_dscp_reg, ip_ecn_reg};
          if (s_is_roce_packet) begin
            m_eth_payload_axis_tdata_int[23:16] = ip_length_roce_reg[15:8];
            m_eth_payload_axis_tdata_int[31:24] = ip_length_roce_reg[7:0];
          end else begin
            m_eth_payload_axis_tdata_int[23:16] = ip_length_reg[15:8];
            m_eth_payload_axis_tdata_int[31:24] = ip_length_reg[7:0];
          end
          m_eth_payload_axis_tdata_int[39:32] = ip_identification_reg[15:8];
          m_eth_payload_axis_tdata_int[47:40] = ip_identification_reg[7:0];
          m_eth_payload_axis_tdata_int[55:48] = {ip_flags_reg, ip_fragment_offset_reg[12:8]};
          m_eth_payload_axis_tdata_int[63:56] = ip_fragment_offset_reg[7:0];
          m_eth_payload_axis_tdata_int[71:64] = ip_ttl_reg;
          m_eth_payload_axis_tdata_int[79:72] = ip_protocol_reg[7:0];
          m_eth_payload_axis_tdata_int[87:80] = ~hdr_sum_temp[15:8];
          m_eth_payload_axis_tdata_int[95:88] = ~hdr_sum_temp[7:0];
          m_eth_payload_axis_tdata_int[103:96] = ip_source_ip_reg[31:24];
          m_eth_payload_axis_tdata_int[111:104] = ip_source_ip_reg[23:16];
          m_eth_payload_axis_tdata_int[119:112] = ip_source_ip_reg[15:8];
          m_eth_payload_axis_tdata_int[127:120] = ip_source_ip_reg[7:0];
          m_eth_payload_axis_tdata_int[135:128] = ip_dest_ip_reg[31:24];
          m_eth_payload_axis_tdata_int[143:136] = ip_dest_ip_reg[23:16];
          m_eth_payload_axis_tdata_int[152:144] = ip_dest_ip_reg[15:8];
          m_eth_payload_axis_tdata_int[159:152] = ip_dest_ip_reg[7:0];
          m_eth_payload_axis_tdata_int[511:160] = shift_ip_payload_axis_tdata[511:160];
          m_eth_payload_axis_tkeep_int = {shift_ip_payload_axis_tkeep[63:20], 20'hFFFFF};

          s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;

          word_count_next = s_ip_length - keep2count(m_eth_payload_axis_tkeep_int);

          if (s_ip_length - keep2count(m_eth_payload_axis_tkeep_int) == 16'd0) begin
            // have entire payload
            if (shift_ip_payload_axis_tlast) begin
              s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
              s_ip_payload_axis_tready_next = 1'b0;
              m_eth_payload_axis_tlast_int = 1'b1;
              state_next = STATE_IDLE;
            end else begin
              store_last_word = 1'b1;
              s_ip_payload_axis_tready_next = shift_ip_payload_s_tready;
              m_eth_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_LAST;
            end
          end else begin
            if (shift_ip_payload_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              s_ip_payload_axis_tready_next = shift_ip_payload_s_tready;
              m_eth_payload_axis_tuser_int = 1'b1;
              state_next = STATE_WAIT_LAST;
            end else begin
              state_next = STATE_WRITE_PAYLOAD;
            end
          end
        end else begin
          state_next = STATE_WRITE_HEADER;
        end
      end
      STATE_WRITE_PAYLOAD: begin
        // write payload
        s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_ip_payload_s_tready;

        m_eth_payload_axis_tdata_int = shift_ip_payload_axis_tdata;
        m_eth_payload_axis_tkeep_int = shift_ip_payload_axis_tkeep;
        m_eth_payload_axis_tlast_int = shift_ip_payload_axis_tlast;
        m_eth_payload_axis_tuser_int = shift_ip_payload_axis_tuser;

        store_last_word = 1'b1;

        if (m_eth_payload_axis_tready_int_reg && shift_ip_payload_axis_tvalid) begin
          // word transfer through
          word_count_next = word_count_reg - 16'd64;
          transfer_in_save = 1'b1;
          m_eth_payload_axis_tvalid_int = 1'b1;
          if (word_count_reg - keep2count(m_eth_payload_axis_tkeep_int) == 16'd0) begin
            // have entire payload
            m_eth_payload_axis_tkeep_int = count2keep(word_count_reg);
            if (shift_ip_payload_axis_tlast) begin
              if (keep2count(shift_ip_payload_axis_tkeep) < word_count_reg[6:0]) begin
                // end of frame, but length does not match
                error_payload_early_termination_next = 1'b1;
                m_eth_payload_axis_tuser_int = 1'b1;
              end
              s_ip_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              m_eth_payload_axis_tvalid_int = 1'b0;
              state_next = STATE_WRITE_PAYLOAD_LAST;
            end
          end else begin
            if (shift_ip_payload_axis_tlast) begin
              // end of frame, but length does not match
              error_payload_early_termination_next = 1'b1;
              m_eth_payload_axis_tuser_int = 1'b1;
              s_ip_payload_axis_tready_next = 1'b0;
              flush_save = 1'b1;
              s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
              state_next = STATE_IDLE;
            end else begin
              state_next = STATE_WRITE_PAYLOAD;
            end
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD;
        end
      end
      STATE_WRITE_PAYLOAD_LAST: begin
        // read and discard until end of frame
        s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_ip_payload_s_tready;

        m_eth_payload_axis_tdata_int = last_word_data_reg;
        m_eth_payload_axis_tkeep_int = last_word_keep_reg;
        m_eth_payload_axis_tlast_int = shift_ip_payload_axis_tlast;
        m_eth_payload_axis_tuser_int = shift_ip_payload_axis_tuser;

        if (m_eth_payload_axis_tready_int_reg && shift_ip_payload_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (shift_ip_payload_axis_tlast) begin
            s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
            s_ip_payload_axis_tready_next = 1'b0;
            m_eth_payload_axis_tvalid_int = 1'b1;
            state_next = STATE_IDLE;
          end else begin
            state_next = STATE_WRITE_PAYLOAD_LAST;
          end
        end else begin
          state_next = STATE_WRITE_PAYLOAD_LAST;
        end
      end
      STATE_WAIT_LAST: begin
        // read and discard until end of frame
        s_ip_payload_axis_tready_next = shift_ip_payload_s_tready;

        if (shift_ip_payload_axis_tvalid) begin
          transfer_in_save = 1'b1;
          if (shift_ip_payload_axis_tlast) begin
            s_ip_hdr_ready_next = !m_eth_hdr_valid_next;
            s_ip_payload_axis_tready_next = 1'b0;
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
      state_reg <= STATE_IDLE;
      s_ip_hdr_ready_reg <= 1'b0;
      s_ip_payload_axis_tready_reg <= 1'b0;
      m_eth_hdr_valid_reg <= 1'b0;
      save_ip_payload_axis_tlast_reg <= 1'b0;
      shift_ip_payload_extra_cycle_reg <= 1'b0;
      busy_reg <= 1'b0;
      error_payload_early_termination_reg <= 1'b0;
    end else begin
      state_reg <= state_next;

      s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;
      s_ip_payload_axis_tready_reg <= s_ip_payload_axis_tready_next;

      m_eth_hdr_valid_reg <= m_eth_hdr_valid_next;

      busy_reg <= state_next != STATE_IDLE;

      error_payload_early_termination_reg <= error_payload_early_termination_next;

      if (flush_save) begin
        save_ip_payload_axis_tlast_reg   <= 1'b0;
        shift_ip_payload_extra_cycle_reg <= 1'b0;
      end else if (transfer_in_save) begin
        save_ip_payload_axis_tlast_reg <= s_ip_payload_axis_tlast;
        shift_ip_payload_extra_cycle_reg <= s_ip_payload_axis_tlast && (s_ip_payload_axis_tkeep[7:4] != 0);
      end
    end

    word_count_reg <= word_count_next;

    hdr_sum_reg <= hdr_sum_next;

    // datapath
    if (store_ip_hdr) begin
      m_eth_dest_mac_reg <= s_eth_dest_mac;
      m_eth_src_mac_reg <= s_eth_src_mac;
      m_eth_type_reg <= s_eth_type;
      m_is_roce_packet_reg <= s_is_roce_packet;
      ip_dscp_reg <= s_ip_dscp;
      ip_ecn_reg <= s_ip_ecn;
      ip_length_reg <= s_ip_length;
      ip_identification_reg <= s_ip_identification;
      ip_flags_reg <= s_ip_flags;
      ip_fragment_offset_reg <= s_ip_fragment_offset;
      ip_ttl_reg <= s_ip_ttl;
      ip_protocol_reg <= s_ip_protocol;
      ip_source_ip_reg <= s_ip_source_ip;
      ip_dest_ip_reg <= s_ip_dest_ip;
      ip_length_roce_reg <= s_ip_length + 16'd4;
    end

    if (store_last_word) begin
      last_word_data_reg <= m_eth_payload_axis_tdata_int;
      last_word_keep_reg <= m_eth_payload_axis_tkeep_int;
    end

    if (transfer_in_save) begin
      save_ip_payload_axis_tdata_reg <= s_ip_payload_axis_tdata;
      save_ip_payload_axis_tkeep_reg <= s_ip_payload_axis_tkeep;
      save_ip_payload_axis_tuser_reg <= s_ip_payload_axis_tuser;
    end
  end

  // output datapath logic
  reg [511:0] m_eth_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] m_eth_payload_axis_tkeep_reg = 64'd0;
  reg m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
  reg         m_eth_payload_axis_tlast_reg = 1'b0;
  reg         m_eth_payload_axis_tuser_reg = 1'b0;

  reg [511:0] temp_m_eth_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] temp_m_eth_payload_axis_tkeep_reg = 64'd0;
  reg temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
  reg temp_m_eth_payload_axis_tlast_reg = 1'b0;
  reg temp_m_eth_payload_axis_tuser_reg = 1'b0;

  // datapath control
  reg store_eth_payload_int_to_output;
  reg store_eth_payload_int_to_temp;
  reg store_eth_payload_axis_temp_to_output;

  assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
  assign m_eth_payload_axis_tkeep = m_eth_payload_axis_tkeep_reg;
  assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
  assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
  assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

  // enable ready input next cycle if output is ready or if both output registers are empty
  assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

  always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_eth_payload_int_to_output = 1'b0;
    store_eth_payload_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
      // input is ready
      if (m_eth_payload_axis_tready | !m_eth_payload_axis_tvalid_reg) begin
        // output is ready or currently not valid, transfer data to output
        m_eth_payload_axis_tvalid_next  = m_eth_payload_axis_tvalid_int;
        store_eth_payload_int_to_output = 1'b1;
      end else begin
        // output is not ready, store input in temp
        temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
        store_eth_payload_int_to_temp = 1'b1;
      end
    end else if (m_eth_payload_axis_tready) begin
      // input is not ready, but output is ready
      m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
      temp_m_eth_payload_axis_tvalid_next = 1'b0;
      store_eth_payload_axis_temp_to_output = 1'b1;
    end
  end

  always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    // datapath
    if (store_eth_payload_int_to_output) begin
      m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
      m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
      m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
      m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_eth_payload_axis_temp_to_output) begin
      m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
      m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
      m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
      m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_eth_payload_int_to_temp) begin
      temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
      temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
      temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
      temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
      m_eth_payload_axis_tvalid_reg <= 1'b0;
      m_eth_payload_axis_tready_int_reg <= 1'b0;
      temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
  end

endmodule

`resetall
