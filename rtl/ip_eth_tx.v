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

// TODO add check on payload length!

/*
 * IP ethernet frame transmitter (IP frame in, Ethernet frame out)
 */
module ip_eth_tx #(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH  = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH > 8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH  = (DATA_WIDTH / 8)
) (
    input wire clk,
    input wire rst,

    /*
     * IP frame input
     */
    input  wire                  s_ip_hdr_valid,
    output wire                  s_ip_hdr_ready,
    input  wire [          47:0] s_eth_dest_mac,
    input  wire [          47:0] s_eth_src_mac,
    input  wire [          15:0] s_eth_type,
    input  wire [           5:0] s_ip_dscp,
    input  wire [           1:0] s_ip_ecn,
    input  wire [          15:0] s_ip_length,
    input  wire [          15:0] s_ip_identification,
    input  wire [           2:0] s_ip_flags,
    input  wire [          12:0] s_ip_fragment_offset,
    input  wire [           7:0] s_ip_ttl,
    input  wire [           7:0] s_ip_protocol,
    input  wire [          31:0] s_ip_source_ip,
    input  wire [          31:0] s_ip_dest_ip,
    // input  wire        s_is_roce_packet,
    input  wire [DATA_WIDTH-1:0] s_ip_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_ip_payload_axis_tkeep,
    input  wire                  s_ip_payload_axis_tvalid,
    output wire                  s_ip_payload_axis_tready,
    input  wire                  s_ip_payload_axis_tlast,
    input  wire                  s_ip_payload_axis_tuser,

    /*
     * Ethernet frame output
     */
    output wire                  m_eth_hdr_valid,
    input  wire                  m_eth_hdr_ready,
    output wire [          47:0] m_eth_dest_mac,
    output wire [          47:0] m_eth_src_mac,
    output wire [          15:0] m_eth_type,
    //output wire        m_is_roce_packet,
    output wire [DATA_WIDTH-1:0] m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep,
    output wire                  m_eth_payload_axis_tvalid,
    input  wire                  m_eth_payload_axis_tready,
    output wire                  m_eth_payload_axis_tlast,
    output wire                  m_eth_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire busy,
    output wire error_payload_early_termination
);

  parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

  parameter HDR_SIZE = 20;

  parameter CYCLE_COUNT = (HDR_SIZE + BYTE_LANES - 1) / BYTE_LANES;

  parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

  parameter OFFSET = HDR_SIZE % BYTE_LANES;

  // bus width assertions
  initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
      $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
      $finish;
    end
  end

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

  // datapath control signals
  reg store_ip_hdr;

  reg send_ip_header_reg = 1'b0, send_ip_header_next;
  reg send_ip_payload_reg = 1'b0, send_ip_payload_next;
  reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

  reg flush_save;
  reg transfer_in_save;

  reg [19:0] hdr_sum_temp;
  reg [19:0] hdr_sum_reg = 20'd0, hdr_sum_next;


  reg [ 5:0] ip_dscp_reg = 6'd0;
  reg [ 1:0] ip_ecn_reg = 2'd0;
  reg [15:0] ip_length_reg = 16'd0;
  //reg [15:0] ip_length_roce_reg = 16'd0;
  reg [15:0] ip_identification_reg = 16'd0;
  reg [ 2:0] ip_flags_reg = 3'd0;
  reg [12:0] ip_fragment_offset_reg = 13'd0;
  reg [ 7:0] ip_ttl_reg = 8'd0;
  reg [ 7:0] ip_protocol_reg = 8'd0;
  reg [31:0] ip_source_ip_reg = 32'd0;
  reg [31:0] ip_dest_ip_reg = 32'd0;
  //reg        is_roce_packet_reg = 1'b0;

  //wire [15:0] ip_length_roce_int;

  //assign ip_length_roce_int = s_ip_length + 16'd4;

  reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;
  reg s_ip_payload_axis_tready_reg = 1'b0, s_ip_payload_axis_tready_next;

  reg m_eth_hdr_valid_reg = 1'b0, m_eth_hdr_valid_next;
  reg [47:0] m_eth_dest_mac_reg = 48'd0;
  reg [47:0] m_eth_src_mac_reg = 48'd0;
  reg [15:0] m_eth_type_reg = 16'd0;


  reg        busy_reg = 1'b0;
  reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

  reg  [DATA_WIDTH-1:0] save_ip_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg  [KEEP_WIDTH-1:0] save_ip_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
  reg                   save_ip_payload_axis_tlast_reg = 1'b0;
  reg                   save_ip_payload_axis_tuser_reg = 1'b0;

  reg  [DATA_WIDTH-1:0] shift_ip_payload_axis_tdata;
  reg  [KEEP_WIDTH-1:0] shift_ip_payload_axis_tkeep;
  reg                   shift_ip_payload_axis_tvalid;
  reg                   shift_ip_payload_axis_tlast;
  reg                   shift_ip_payload_axis_tuser;
  reg                   shift_ip_payload_axis_input_tready;
  reg                   shift_ip_payload_axis_extra_cycle_reg = 1'b0;

  // internal datapath
  reg  [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_int;
  reg  [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_int;
  reg                   m_eth_payload_axis_tvalid_int;
  reg                   m_eth_payload_axis_tready_int_reg = 1'b0;
  reg                   m_eth_payload_axis_tlast_int;
  reg                   m_eth_payload_axis_tuser_int;
  wire                  m_eth_payload_axis_tready_int_early;

  assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
  assign s_ip_payload_axis_tready = s_ip_payload_axis_tready_reg;

  assign m_eth_hdr_valid = m_eth_hdr_valid_reg;
  assign m_eth_dest_mac = m_eth_dest_mac_reg;
  assign m_eth_src_mac = m_eth_src_mac_reg;
  assign m_eth_type = m_eth_type_reg;
  //assign m_is_roce_packet = m_is_roce_packet_reg;

  assign busy = busy_reg;
  assign error_payload_early_termination = error_payload_early_termination_reg;

  assign busy = busy_reg;

  always @* begin
    if (OFFSET == 0) begin
      // passthrough if no overlap
      shift_ip_payload_axis_tdata = s_ip_payload_axis_tdata;
      shift_ip_payload_axis_tkeep = s_ip_payload_axis_tkeep;
      shift_ip_payload_axis_tvalid = s_ip_payload_axis_tvalid;
      shift_ip_payload_axis_tlast = s_ip_payload_axis_tlast;
      shift_ip_payload_axis_tuser = s_ip_payload_axis_tuser;
      shift_ip_payload_axis_input_tready = 1'b1;
    end else if (shift_ip_payload_axis_extra_cycle_reg) begin
      shift_ip_payload_axis_tdata = {s_ip_payload_axis_tdata, save_ip_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET)*8);
      shift_ip_payload_axis_tkeep = {{KEEP_WIDTH{1'b0}}, save_ip_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET);
      shift_ip_payload_axis_tvalid = 1'b1;
      shift_ip_payload_axis_tlast = save_ip_payload_axis_tlast_reg;
      shift_ip_payload_axis_tuser = save_ip_payload_axis_tuser_reg;
      shift_ip_payload_axis_input_tready = flush_save;
    end else begin
      shift_ip_payload_axis_tdata = {s_ip_payload_axis_tdata, save_ip_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET)*8);
      shift_ip_payload_axis_tkeep = {s_ip_payload_axis_tkeep, save_ip_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET);
      shift_ip_payload_axis_tvalid = s_ip_payload_axis_tvalid;
      shift_ip_payload_axis_tlast = (s_ip_payload_axis_tlast && ((s_ip_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) == 0));
      shift_ip_payload_axis_tuser = (s_ip_payload_axis_tuser && ((s_ip_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) == 0));
      shift_ip_payload_axis_input_tready = !(s_ip_payload_axis_tlast && s_ip_payload_axis_tready && s_ip_payload_axis_tvalid);
    end
  end

  always @* begin
    send_ip_header_next = send_ip_header_reg;
    send_ip_payload_next = send_ip_payload_reg;
    ptr_next = ptr_reg;

    s_ip_hdr_ready_next = 1'b0;
    s_ip_payload_axis_tready_next = 1'b0;

    store_ip_hdr = 1'b0;

    flush_save = 1'b0;
    transfer_in_save = 1'b0;

    hdr_sum_temp = 20'd0;
    hdr_sum_next = hdr_sum_reg;

    m_eth_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
    m_eth_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int = 1'b0;
    m_eth_payload_axis_tuser_int = 1'b0;

    if (s_ip_hdr_ready && s_ip_hdr_valid) begin
      store_ip_hdr = 1'b1;
      ptr_next = 0;
      send_ip_header_next = 1'b1;
      send_ip_payload_next = (OFFSET != 0) && (CYCLE_COUNT == 1);
      s_ip_payload_axis_tready_next = send_ip_payload_next && m_eth_payload_axis_tready_int_early;

      /*
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
     * */
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

    if (send_ip_payload_reg) begin
      s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_ip_payload_axis_input_tready;

      m_eth_payload_axis_tdata_int = shift_ip_payload_axis_tdata;
      m_eth_payload_axis_tkeep_int = shift_ip_payload_axis_tkeep;
      m_eth_payload_axis_tlast_int = shift_ip_payload_axis_tlast;
      m_eth_payload_axis_tuser_int = shift_ip_payload_axis_tuser;

      if ((s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) || (m_eth_payload_axis_tready_int_reg && shift_ip_payload_axis_extra_cycle_reg)) begin
        transfer_in_save = 1'b1;

        m_eth_payload_axis_tvalid_int = 1'b1;

        if (shift_ip_payload_axis_tlast) begin
          flush_save = 1'b1;
          s_ip_payload_axis_tready_next = 1'b0;
          ptr_next = 0;
          send_ip_payload_next = 1'b0;
        end
      end
    end

    if (m_eth_payload_axis_tready_int_reg && (!OFFSET || !send_ip_payload_reg || m_eth_payload_axis_tvalid_int)) begin
      if (send_ip_header_reg) begin
        ptr_next = ptr_reg + 1;

        if ((OFFSET != 0) && (CYCLE_COUNT == 1 || ptr_next == CYCLE_COUNT-1) && !send_ip_payload_reg) begin
          send_ip_payload_next = 1'b1;
          s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early && shift_ip_payload_axis_input_tready;
        end

        m_eth_payload_axis_tvalid_int = 1'b1;

        `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_eth_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_eth_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end

        `_HEADER_FIELD_(0, {4'd4, 4'd5})
        `_HEADER_FIELD_(1, {ip_dscp_reg, ip_ecn_reg})
        `_HEADER_FIELD_(2, ip_length_reg[1*8+:8])
        `_HEADER_FIELD_(3, ip_length_reg[0*8+:8])
        `_HEADER_FIELD_(4, ip_identification_reg[1*8+:8])
        `_HEADER_FIELD_(5, ip_identification_reg[0*8+:8])
        `_HEADER_FIELD_(6, {s_ip_flags, s_ip_fragment_offset[12:8]})
        `_HEADER_FIELD_(7, ip_fragment_offset_reg[0*8+:8])
        `_HEADER_FIELD_(8, ip_ttl_reg[1*8+:8])
        `_HEADER_FIELD_(9, ip_protocol_reg[0*8+:8])
        `_HEADER_FIELD_(10, ~hdr_sum_temp[1*8+:8])
        `_HEADER_FIELD_(11, ~hdr_sum_temp[0*8+:8])
        `_HEADER_FIELD_(12, ip_source_ip_reg[3*8+:8])
        `_HEADER_FIELD_(13, ip_source_ip_reg[2*8+:8])
        `_HEADER_FIELD_(14, ip_source_ip_reg[1*8+:8])
        `_HEADER_FIELD_(15, ip_source_ip_reg[0*8+:8])
        `_HEADER_FIELD_(16, ip_dest_ip_reg[3*8+:8])
        `_HEADER_FIELD_(17, ip_dest_ip_reg[2*8+:8])
        `_HEADER_FIELD_(18, ip_dest_ip_reg[1*8+:8])
        `_HEADER_FIELD_(19, ip_dest_ip_reg[0*8+:8])

        if (ptr_reg == 19 / BYTE_LANES) begin
          if (!send_ip_payload_reg) begin
            s_ip_payload_axis_tready_next = m_eth_payload_axis_tready_int_early;
            send_ip_payload_next = 1'b1;
          end
          send_ip_header_next = 1'b0;
        end else if (ptr_reg == 10 / BYTE_LANES) begin
          hdr_sum_temp = hdr_sum_reg[15:0] + hdr_sum_reg[19:16];
          hdr_sum_temp = hdr_sum_temp[15:0] + hdr_sum_temp[16];
        end

        `undef _HEADER_FIELD_
      end
    end

    s_ip_hdr_ready_next = !(send_ip_header_next || send_ip_payload_next);
  end

  always @(posedge clk) begin
    send_ip_header_reg <= send_ip_header_next;
    send_ip_payload_reg <= send_ip_payload_next;
    ptr_reg <= ptr_next;

    s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;
    s_ip_payload_axis_tready_reg <= s_ip_payload_axis_tready_next;

    busy_reg <= send_ip_header_next || send_ip_payload_next;

    if (store_ip_hdr) begin
      m_eth_dest_mac_reg <= s_eth_dest_mac;
      m_eth_src_mac_reg <= s_eth_src_mac;
      m_eth_type_reg <= s_eth_type;
      //m_is_roce_packet_reg <= s_is_roce_packet;
      ip_dscp_reg <= s_ip_dscp;
      ip_ecn_reg <= s_ip_ecn;
      // ip_length_reg <= s_is_roce_packet ? ip_length_roce_int  : s_ip_length;
      ip_length_reg <= s_ip_length;
      ip_identification_reg <= s_ip_identification;
      ip_flags_reg <= s_ip_flags;
      ip_fragment_offset_reg <= s_ip_fragment_offset;
      ip_ttl_reg <= s_ip_ttl;
      ip_protocol_reg <= s_ip_protocol;
      ip_source_ip_reg <= s_ip_source_ip;
      ip_dest_ip_reg <= s_ip_dest_ip;
      //ip_length_roce_reg <= s_ip_length + 16'd4;
    end

    if (transfer_in_save) begin
      save_ip_payload_axis_tdata_reg <= s_ip_payload_axis_tdata;
      save_ip_payload_axis_tkeep_reg <= s_ip_payload_axis_tkeep;
      save_ip_payload_axis_tuser_reg <= s_ip_payload_axis_tuser;
    end

    if (flush_save) begin
      save_ip_payload_axis_tlast_reg <= 1'b0;
      shift_ip_payload_axis_extra_cycle_reg <= 1'b0;
    end else if (transfer_in_save) begin
      save_ip_payload_axis_tlast_reg <= s_ip_payload_axis_tlast;
      shift_ip_payload_axis_extra_cycle_reg <= OFFSET ? s_ip_payload_axis_tlast && ((s_ip_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET))) != 0) : 1'b0;
    end

    if (rst) begin
      send_ip_header_reg <= 1'b0;
      send_ip_payload_reg <= 1'b0;
      ptr_reg <= 0;
      s_ip_hdr_ready_reg <= 1'b0;
      s_ip_payload_axis_tready_reg <= 1'b0;
      busy_reg <= 1'b0;
    end
  end

  // output datapath logic
  reg [DATA_WIDTH-1:0] m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
  reg m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
  reg                  m_eth_payload_axis_tlast_reg = 1'b0;
  reg                  m_eth_payload_axis_tuser_reg = 1'b0;

  reg [DATA_WIDTH-1:0] temp_m_eth_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] temp_m_eth_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
  reg temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
  reg temp_m_eth_payload_axis_tlast_reg = 1'b0;
  reg temp_m_eth_payload_axis_tuser_reg = 1'b0;

  // datapath control
  reg store_eth_payload_axis_int_to_output;
  reg store_eth_payload_axis_int_to_temp;
  reg store_eth_payload_axis_temp_to_output;

  assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
  assign m_eth_payload_axis_tkeep = KEEP_ENABLE ? m_eth_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
  assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
  assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
  assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

  // enable ready input next cycle if output is ready or if both output registers are empty
  assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

  always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_eth_payload_axis_int_to_output = 1'b0;
    store_eth_payload_axis_int_to_temp = 1'b0;
    store_eth_payload_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
      // input is ready
      if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
        // output is ready or currently not valid, transfer data to output
        m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
        store_eth_payload_axis_int_to_output = 1'b1;
      end else begin
        // output is not ready, store input in temp
        temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
        store_eth_payload_axis_int_to_temp  = 1'b1;
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
    if (store_eth_payload_axis_int_to_output) begin
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

    if (store_eth_payload_axis_int_to_temp) begin
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
