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
 * roce ethernet frame receiver (UDP frame in, RoCE frame out, 64 bit datapath)
 */
module RoCE_udp_rx_64 #(
  parameter ENABLE_ICRC_CHECK = 1'b1
) (
  input wire clk,
  input wire rst,

  /*
   * UDP frame input
   */
  input  wire        s_udp_hdr_valid,
  output wire        s_udp_hdr_ready,
  input  wire [47:0] s_eth_dest_mac,
  input  wire [47:0] s_eth_src_mac,
  input  wire [15:0] s_eth_type,
  input  wire [ 3:0] s_ip_version,
  input  wire [ 3:0] s_ip_ihl,
  input  wire [ 5:0] s_ip_dscp,
  input  wire [ 1:0] s_ip_ecn,
  input  wire [15:0] s_ip_length,
  input  wire [15:0] s_ip_identification,
  input  wire [ 2:0] s_ip_flags,
  input  wire [12:0] s_ip_fragment_offset,
  input  wire [ 7:0] s_ip_ttl,
  input  wire [ 7:0] s_ip_protocol,
  input  wire [15:0] s_ip_header_checksum,
  input  wire [31:0] s_ip_source_ip,
  input  wire [31:0] s_ip_dest_ip,
  input  wire [15:0] s_udp_source_port,
  input  wire [15:0] s_udp_dest_port,
  input  wire [15:0] s_udp_length,
  input  wire [15:0] s_udp_checksum,
  input  wire [31:0] s_roce_computed_icrc,
  input  wire [63:0] s_udp_payload_axis_tdata,
  input  wire [ 7:0] s_udp_payload_axis_tkeep,
  input  wire        s_udp_payload_axis_tvalid,
  output wire        s_udp_payload_axis_tready,
  input  wire        s_udp_payload_axis_tlast,
  input  wire        s_udp_payload_axis_tuser,


  /*
   * RoCE frame output
   */
  // BTH
  output wire        m_roce_bth_valid,
  input  wire        m_roce_bth_ready,
  output wire [ 7:0] m_roce_bth_op_code,
  output wire [15:0] m_roce_bth_p_key,
  output wire [23:0] m_roce_bth_psn,
  output wire [23:0] m_roce_bth_dest_qp,
  output wire        m_roce_bth_ack_req,
  // AETH
  output wire        m_roce_aeth_valid,
  input  wire        m_roce_aeth_ready,
  output wire [ 7:0] m_roce_aeth_syndrome,
  output wire [23:0] m_roce_aeth_msn,
  /*
    // RETH
    output wire        m_roce_reth_valid,
    input  wire        m_roce_reth_ready,
    output wire [63:0] m_roce_reth_v_addr,
    output wire [31:0] m_roce_reth_r_key,
    output wire [31:0] m_roce_reth_length,
    // IMMD
    output wire        m_roce_immdh_valid,
    input  wire        m_roce_immdh_ready,
    output wire [31:0] m_roce_immdh_data,
    */
  // udp, ip, eth
  output wire [47:0] m_eth_dest_mac,
  output wire [47:0] m_eth_src_mac,
  output wire [15:0] m_eth_type,
  output wire [ 3:0] m_ip_version,
  output wire [ 3:0] m_ip_ihl,
  output wire [ 5:0] m_ip_dscp,
  output wire [ 1:0] m_ip_ecn,
  output wire [15:0] m_ip_identification,
  output wire [ 2:0] m_ip_flags,
  output wire [12:0] m_ip_fragment_offset,
  output wire [ 7:0] m_ip_ttl,
  output wire [ 7:0] m_ip_protocol,
  output wire [15:0] m_ip_header_checksum,
  output wire [31:0] m_ip_source_ip,
  output wire [31:0] m_ip_dest_ip,
  output wire [15:0] m_udp_source_port,
  output wire [15:0] m_udp_dest_port,
  output wire [15:0] m_udp_length,
  output wire [15:0] m_udp_checksum,
  /* TODO maybe implement something here?
    output wire [63:0] m_roce_payload_axis_tdata,
    output wire [ 7:0] m_roce_payload_axis_tkeep,
    output wire        m_roce_payload_axis_tvalid,
    input  wire        m_roce_payload_axis_tready,
    output wire        m_roce_payload_axis_tlast,
    output wire        m_roce_payload_axis_tuser,
    */
  /*
   * Status signals
   */
  output wire        busy,
  output wire        error_header_early_termination
);

  /*

RoCE ACK Frame.

RDMA ACK 
IP_HDR + UDP_HDR + BTH + AETH + PAYLOAD + ICRC


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

This module receives an IP frame with header fields in parallel and payload on
an AXI stream interface, decodes and strips the UDP header fields, then
produces the header fields in parallel along with the UDP payload in a
separate AXI stream.

*/

  localparam [7:0]
  RC_RDMA_WRITE_FIRST   = 8'h06,
  RC_RDMA_WRITE_MIDDLE  = 8'h07,
  RC_RDMA_WRITE_LAST    = 8'h08,
  RC_RDMA_WRITE_LAST_IMD= 8'h09,
  RC_RDMA_WRITE_ONLY    = 8'h0A,
  RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
  RC_RDMA_ACK           = 8'h11;

  localparam [15:0] ROCE_UDP_PORT = 16'h12B7;


  localparam [2:0] STATE_IDLE = 3'd0, STATE_READ_BTH_AETH = 3'd1, STATE_CHECK_ICRC = 3'd2, STATE_WAIT_LAST = 3'd3;

  reg [2:0] state_reg = STATE_IDLE, state_next;

  // datapath control signals
  reg store_udp_hdr;
  reg store_hdr_word_0;
  reg store_hdr_word_1;
  reg store_hdr_word_2;
  reg store_last_word;

  reg [5:0] hdr_ptr_reg = 6'd0, hdr_ptr_next;
  reg [15:0] word_count_reg = 16'd0, word_count_next;

  reg [63:0] last_word_data_reg = 64'd0;
  reg [ 7:0] last_word_keep_reg = 8'd0;

  reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
  reg [ 7:0] m_roce_bth_op_code_reg;
  reg [15:0] m_roce_bth_p_key_reg;
  reg [23:0] m_roce_bth_psn_reg;
  reg [23:0] m_roce_bth_dest_qp_reg;
  reg        m_roce_bth_ack_req_reg;

  reg m_roce_aeth_valid_reg = 1'b0, m_roce_aeth_valid_next;
  reg [ 7:0] m_roce_aeth_syndrome_reg;
  reg [23:0] m_roce_aeth_msn_reg;

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

  reg [31:0] m_roce_computed_icrc_reg = 32'd0;
  reg [31:0] m_roce_recieved_icrc_reg = 32'd0;

  reg error_not_roce_ack_reg = 1'b0, error_not_roce_ack_next;

  reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
  reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

  reg busy_reg = 1'b0;
  reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;

  /*
  // internal datapath
  reg  [63:0] m_roce_payload_axis_tdata_int;
  reg  [ 7:0] m_roce_payload_axis_tkeep_int;
  reg         m_roce_payload_axis_tvalid_int;
  reg         m_roce_payload_axis_tready_int_reg = 1'b0;
  reg         m_roce_payload_axis_tlast_int;
  reg         m_roce_payload_axis_tuser_int;
  wire        m_roce_payload_axis_tready_int_early;
  */

  assign s_udp_hdr_ready                = s_udp_hdr_ready_reg;
  assign s_udp_payload_axis_tready      = s_udp_payload_axis_tready_reg;

  assign m_roce_bth_valid               = m_roce_bth_valid_reg;
  assign m_roce_bth_op_code             = m_roce_bth_op_code_reg;
  assign m_roce_bth_p_key               = m_roce_bth_p_key_reg;
  assign m_roce_bth_psn                 = m_roce_bth_psn_reg;
  assign m_roce_bth_dest_qp             = m_roce_bth_dest_qp_reg;
  assign m_roce_bth_ack_req             = m_roce_bth_ack_req_reg;
  assign m_roce_aeth_valid              = m_roce_aeth_valid_reg;
  assign m_roce_aeth_syndrome           = m_roce_aeth_syndrome_reg;
  assign m_roce_aeth_msn                = m_roce_aeth_msn_reg;
  assign m_eth_dest_mac                 = m_eth_dest_mac_reg;
  assign m_eth_src_mac                  = m_eth_src_mac_reg;
  assign m_eth_type                     = m_eth_type_reg;
  assign m_ip_version                   = m_ip_version_reg;
  assign m_ip_ihl                       = m_ip_ihl_reg;
  assign m_ip_dscp                      = m_ip_dscp_reg;
  assign m_ip_ecn                       = m_ip_ecn_reg;
  assign m_ip_identification            = m_ip_identification_reg;
  assign m_ip_flags                     = m_ip_flags_reg;
  assign m_ip_fragment_offset           = m_ip_fragment_offset_reg;
  assign m_ip_ttl                       = m_ip_ttl_reg;
  assign m_ip_protocol                  = m_ip_protocol_reg;
  assign m_ip_header_checksum           = m_ip_header_checksum_reg;
  assign m_ip_source_ip                 = m_ip_source_ip_reg;
  assign m_ip_dest_ip                   = m_ip_dest_ip_reg;
  assign m_udp_source_port              = m_udp_source_port_reg;
  assign m_udp_dest_port                = m_udp_dest_port_reg;
  assign m_udp_length                   = m_udp_length_reg;
  assign m_udp_checksum                 = m_udp_checksum_reg;

  assign busy                           = busy_reg;
  assign error_header_early_termination = error_header_early_termination_reg;

  function [3:0] keep2count;
    input [7:0] k;
    casez (k)
      8'bzzzzzzz0: keep2count = 4'd0;
      8'bzzzzzz01: keep2count = 4'd1;
      8'bzzzzz011: keep2count = 4'd2;
      8'bzzzz0111: keep2count = 4'd3;
      8'bzzz01111: keep2count = 4'd4;
      8'bzz011111: keep2count = 4'd5;
      8'bz0111111: keep2count = 4'd6;
      8'b01111111: keep2count = 4'd7;
      8'b11111111: keep2count = 4'd8;
    endcase
  endfunction

  function [7:0] count2keep;
    input [3:0] k;
    case (k)
      4'd0: count2keep = 8'b00000000;
      4'd1: count2keep = 8'b00000001;
      4'd2: count2keep = 8'b00000011;
      4'd3: count2keep = 8'b00000111;
      4'd4: count2keep = 8'b00001111;
      4'd5: count2keep = 8'b00011111;
      4'd6: count2keep = 8'b00111111;
      4'd7: count2keep = 8'b01111111;
      4'd8: count2keep = 8'b11111111;
    endcase
  endfunction

  always @* begin
    state_next = STATE_IDLE;

    s_udp_hdr_ready_next = 1'b0;
    s_udp_payload_axis_tready_next = 1'b0;

    store_udp_hdr = 1'b0;
    store_hdr_word_0 = 1'b0;
    store_hdr_word_1 = 1'b0;
    store_hdr_word_2 = 1'b0;

    store_last_word = 1'b0;

    hdr_ptr_next = hdr_ptr_reg;
    word_count_next = word_count_reg;

    m_roce_bth_valid_next = m_roce_bth_valid_reg && !m_roce_bth_ready;
    m_roce_aeth_valid_next = m_roce_aeth_valid_reg && !m_roce_aeth_ready;

    error_not_roce_ack_next = 1'b0;
    error_header_early_termination_next = 1'b0;

    /*
    m_roce_payload_axis_tdata_int = 64'd0;
    m_roce_payload_axis_tkeep_int = 8'd0;
    m_roce_payload_axis_tvalid_int = 1'b0;
    m_roce_payload_axis_tlast_int = 1'b0;
    m_roce_payload_axis_tuser_int = 1'b0;
    */

    case (state_reg)
      STATE_IDLE: begin
        // idle state - wait for header
        hdr_ptr_next = 6'd0;
        s_udp_hdr_ready_next = !m_roce_bth_valid_next;

        if (s_udp_hdr_ready && s_udp_hdr_valid) begin
          s_udp_hdr_ready_next = 1'b0;
          s_udp_payload_axis_tready_next = 1'b1;
          store_udp_hdr = 1'b1;
          state_next = STATE_READ_BTH_AETH;
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_READ_BTH_AETH: begin
        // read header state
        s_udp_payload_axis_tready_next = 1'b1;

        word_count_next = m_udp_length_reg;

        if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
          // word transfer in - store it
          hdr_ptr_next = hdr_ptr_reg + 6'd8;
          state_next   = STATE_READ_BTH_AETH;

          case (hdr_ptr_reg)
            6'h00: begin
              store_hdr_word_0 = 1'b1;
            end
            6'h08: begin
              store_hdr_word_1 = 1'b1;

            end
            6'h10: begin
              store_hdr_word_2 = 1'b1;
              if (m_roce_bth_op_code_reg != RC_RDMA_ACK && m_udp_dest_port_reg != ROCE_UDP_PORT) begin
                // Drop anything beside RDMA ACK packets
                error_not_roce_ack_next = 1'b1;
                if (s_udp_payload_axis_tlast) begin
                  s_udp_hdr_ready_next = !m_roce_bth_valid_next;
                  s_udp_payload_axis_tready_next = 1'b0;
                  state_next = STATE_IDLE;
                end else begin
                  s_udp_payload_axis_tready_next = 1'b1;
                  state_next = STATE_WAIT_LAST;
                end
              end else begin
                state_next = STATE_CHECK_ICRC;
                m_roce_bth_valid_next  = 1'b0;
                m_roce_aeth_valid_next = 1'b0;
              end

            end
          endcase

        end else begin
          state_next = STATE_READ_BTH_AETH;
        end
      end

      STATE_CHECK_ICRC: begin

        s_udp_payload_axis_tready_next = 1'b0;
        s_udp_hdr_ready_next = !m_roce_bth_valid_next;
        state_next = STATE_IDLE;
        if (ENABLE_ICRC_CHECK) begin
          if (m_roce_computed_icrc_reg != m_roce_recieved_icrc_reg) begin
            m_roce_bth_valid_next  = 1'b0;
            m_roce_aeth_valid_next = 1'b0;
          end else begin
            m_roce_bth_valid_next  = 1'b1;
            m_roce_aeth_valid_next = 1'b1;
          end
        end else begin
          m_roce_bth_valid_next  = 1'b1;
          m_roce_aeth_valid_next = 1'b1;
        end

      end

      STATE_WAIT_LAST: begin
        // wait for end of frame; read and discard
        s_udp_payload_axis_tready_next = 1'b1;

        if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
          if (s_udp_payload_axis_tlast) begin
            s_udp_hdr_ready_next = !m_roce_bth_valid_next;
            s_udp_payload_axis_tready_next = 1'b0;
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
      state_reg                          <= STATE_IDLE;
      s_udp_hdr_ready_reg                <= 1'b0;
      s_udp_payload_axis_tready_reg      <= 1'b0;
      m_roce_bth_valid_reg               <= 1'b0;
      m_roce_aeth_valid_reg              <= 1'b0;
      busy_reg                           <= 1'b0;
      error_header_early_termination_reg <= 1'b0;
      error_not_roce_ack_reg             <= 1'b0;
    end else begin
      state_reg <= state_next;

      s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
      s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

      m_roce_bth_valid_reg  <= m_roce_bth_valid_next;
      m_roce_aeth_valid_reg <= m_roce_aeth_valid_next;

      error_header_early_termination_reg <= error_header_early_termination_next;
      error_not_roce_ack_reg             <= error_not_roce_ack_next;

      busy_reg <= state_next != STATE_IDLE;
    end

    hdr_ptr_reg <= hdr_ptr_next;

    word_count_reg <= word_count_next;

    // datapath
    if (store_udp_hdr) begin
      m_eth_dest_mac_reg <= s_eth_dest_mac;
      m_eth_src_mac_reg <= s_eth_src_mac;
      m_eth_type_reg <= s_eth_type;
      m_ip_version_reg <= s_ip_version;
      m_ip_ihl_reg <= s_ip_ihl;
      m_ip_dscp_reg <= s_ip_dscp;
      m_ip_ecn_reg <= s_ip_ecn;
      m_ip_length_reg <= s_ip_length;
      m_ip_identification_reg <= s_ip_identification;
      m_ip_flags_reg <= s_ip_flags;
      m_ip_fragment_offset_reg <= s_ip_fragment_offset;
      m_ip_ttl_reg <= s_ip_ttl;
      m_ip_protocol_reg <= s_ip_protocol;
      m_ip_header_checksum_reg <= s_ip_header_checksum;
      m_ip_source_ip_reg <= s_ip_source_ip;
      m_ip_dest_ip_reg <= s_ip_dest_ip;
      m_udp_source_port_reg <= s_udp_source_port;
      m_udp_dest_port_reg <= s_udp_dest_port;
      m_udp_length_reg <= s_udp_length;
      m_udp_checksum_reg <= s_udp_checksum;
      m_roce_computed_icrc_reg <= s_roce_computed_icrc;
    end

    /*
    if (store_last_word) begin
      last_word_data_reg <= m_roce_payload_axis_tdata_int;
      last_word_keep_reg <= m_roce_payload_axis_tkeep_int;
    end
    */

    if (store_hdr_word_0) begin
      m_roce_bth_op_code_reg <= s_udp_payload_axis_tdata[7:0];
      /*
      solicited_event <= s_udp_payload_axis_tdata[7];
      mig_regquest    <= s_udp_payload_axis_tdata[6];
      pad_count       <= s_udp_payload_axis_tdata[5:4];
      header_version  <= s_udp_payload_axis_tdata[3:0];
      */
      m_roce_bth_p_key_reg[15:8] <= s_udp_payload_axis_tdata[23:16];
      m_roce_bth_p_key_reg[7:0] <= s_udp_payload_axis_tdata[31:24];
      /*
      reserved <= s_udp_payload_axis_tdata[39:32];
      */
      m_roce_bth_dest_qp_reg[23:16] <= s_udp_payload_axis_tdata[47:40];
      m_roce_bth_dest_qp_reg[15:8] <= s_udp_payload_axis_tdata[55:48];
      m_roce_bth_dest_qp_reg[7:0] <= s_udp_payload_axis_tdata[63:56];
    end

    if (store_hdr_word_1) begin
      m_roce_bth_ack_req_reg <= s_udp_payload_axis_tdata[7];
      /*
      reserved <= s_udp_payload_axis_tdata[6:0]
      */
      m_roce_bth_psn_reg[23:16] <= s_udp_payload_axis_tdata[15:8];
      m_roce_bth_psn_reg[15:8] <= s_udp_payload_axis_tdata[23:16];
      m_roce_bth_psn_reg[7:0] <= s_udp_payload_axis_tdata[31:24];
      m_roce_aeth_syndrome_reg[7:0] <= s_udp_payload_axis_tdata[39:32];
      m_roce_aeth_msn_reg[23:16] <= s_udp_payload_axis_tdata[47:40];
      m_roce_aeth_msn_reg[15:8] <= s_udp_payload_axis_tdata[55:48];
      m_roce_aeth_msn_reg[7:0] <= s_udp_payload_axis_tdata[63:56];
    end

    if (store_hdr_word_2) begin
      m_roce_recieved_icrc_reg[31:24] <= s_udp_payload_axis_tdata[7:0];
      m_roce_recieved_icrc_reg[23:16] <= s_udp_payload_axis_tdata[15:8];
      m_roce_recieved_icrc_reg[15:8]  <= s_udp_payload_axis_tdata[23:16];
      m_roce_recieved_icrc_reg[7:0]   <= s_udp_payload_axis_tdata[31:24];
    end
  end

  /*
  // output datapath logic
  reg [63:0] m_roce_payload_axis_tdata_reg = 64'd0;
  reg [ 7:0] m_roce_payload_axis_tkeep_reg = 8'd0;
  reg m_roce_payload_axis_tvalid_reg = 1'b0, m_roce_payload_axis_tvalid_next;
  reg        m_roce_payload_axis_tlast_reg = 1'b0;
  reg        m_roce_payload_axis_tuser_reg = 1'b0;

  reg [63:0] temp_m_roce_payload_axis_tdata_reg = 64'd0;
  reg [ 7:0] temp_m_roce_payload_axis_tkeep_reg = 8'd0;
  reg temp_m_roce_payload_axis_tvalid_reg = 1'b0, temp_m_roce_payload_axis_tvalid_next;
  reg temp_m_roce_payload_axis_tlast_reg = 1'b0;
  reg temp_m_roce_payload_axis_tuser_reg = 1'b0;

  // datapath control
  reg store_roce_payload_int_to_output;
  reg store_roce_payload_int_to_temp;
  reg store_roce_payload_axis_temp_to_output;

  assign m_roce_payload_axis_tdata = m_roce_payload_axis_tdata_reg;
  assign m_roce_payload_axis_tkeep = m_roce_payload_axis_tkeep_reg;
  assign m_roce_payload_axis_tvalid = m_roce_payload_axis_tvalid_reg;
  assign m_roce_payload_axis_tlast = m_roce_payload_axis_tlast_reg;
  assign m_roce_payload_axis_tuser = m_roce_payload_axis_tuser_reg;

  // enable ready input next cycle if output is ready or if both output registers are empty
  assign m_roce_payload_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_roce_payload_axis_tvalid_reg && !m_roce_payload_axis_tvalid_reg);

  always @* begin
    // transfer sink ready state to source
    m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_reg;
    temp_m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;

    store_roce_payload_int_to_output = 1'b0;
    store_roce_payload_int_to_temp = 1'b0;
    store_roce_payload_axis_temp_to_output = 1'b0;

    if (m_roce_payload_axis_tready_int_reg) begin
      // input is ready
      if (m_roce_payload_axis_tready || !m_roce_payload_axis_tvalid_reg) begin
        // output is ready or currently not valid, transfer data to output
        m_roce_payload_axis_tvalid_next  = m_roce_payload_axis_tvalid_int;
        store_roce_payload_int_to_output = 1'b1;
      end else begin
        // output is not ready, store input in temp
        temp_m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_int;
        store_roce_payload_int_to_temp = 1'b1;
      end
    end else if (m_roce_payload_axis_tready) begin
      // input is not ready, but output is ready
      m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;
      temp_m_roce_payload_axis_tvalid_next = 1'b0;
      store_roce_payload_axis_temp_to_output = 1'b1;
    end
  end

  always @(posedge clk) begin
    m_roce_payload_axis_tvalid_reg <= m_roce_payload_axis_tvalid_next;
    m_roce_payload_axis_tready_int_reg <= m_roce_payload_axis_tready_int_early;
    temp_m_roce_payload_axis_tvalid_reg <= temp_m_roce_payload_axis_tvalid_next;

    // datapath
    if (store_roce_payload_int_to_output) begin
      m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
      m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
      m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
      m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
    end else if (store_roce_payload_axis_temp_to_output) begin
      m_roce_payload_axis_tdata_reg <= temp_m_roce_payload_axis_tdata_reg;
      m_roce_payload_axis_tkeep_reg <= temp_m_roce_payload_axis_tkeep_reg;
      m_roce_payload_axis_tlast_reg <= temp_m_roce_payload_axis_tlast_reg;
      m_roce_payload_axis_tuser_reg <= temp_m_roce_payload_axis_tuser_reg;
    end

    if (store_roce_payload_int_to_temp) begin
      temp_m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
      temp_m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
      temp_m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
      temp_m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
    end

    if (rst) begin
      m_roce_payload_axis_tvalid_reg <= 1'b0;
      m_roce_payload_axis_tready_int_reg <= 1'b0;
      temp_m_roce_payload_axis_tvalid_reg <= 1'b0;
    end
  end
  */

endmodule

`resetall
