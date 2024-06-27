`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * UDP ethernet frame receiver (IP frame in, UDP frame out, 64 bit datapath)
 */

/*
  * Structure
  * +---------+-------------+---------------------+
  * | OCTETS  |  BIT RANGE  |       Field         |
  * +---------+-------------+---------------------+
  * |   0     |  [0  :0  ]  |  QP_info_valid      |
  * |   0     |  [7  :1  ]  |  QP_info_reserved   |
  * | [3:1]   |  [31 :8  ]  |  QP_info_rem_qpn    |
  * | [6:4]   |  [55 :32 ]  |  QP_info_loc_qpn    |
  * | [9:7]   |  [79 :56 ]  |  QP_info_rem_psn    |
  * | [12:10] |  [103:80 ]  |  QP_info_loc_psn    |
  * | [16:13] |  [135:104]  |  QP_info_r_key      |
  * +---------+-------------+---------------------+
  * |   17    |  [136:136]  |  txmeta_valid       |
  * |   17    |  [137:137]  |  txmeta_start       |
  * |   17    |  [138:138]  |  txmeta_write_type  |
  * |   17    |  [143:139]  |  txmeta_reserved    |
  * | [21:18] |  [175:144]  |  txmeta_rem_ip_addr |
  * | [29:22] |  [239:176]  |  txmeta_rem_addr    |
  * | [33:30] |  [271:240]  |  txmeta_dma_length  |
  * | [35:34] |  [287:272]  |  txmeta_rem_udp_port|
  * +---------+-------------+---------------------+
  * TOTAL length 288 bits, 36 bytes
  */

module udp_RoCE_connection_manager_64 #(
    parameter LISTEN_UDP_PORT = 16'h4321
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
    input  wire [63:0] s_udp_payload_axis_tdata,
    input  wire [ 7:0] s_udp_payload_axis_tkeep,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,

    /*
     * RoCE QP parameters
     */
    output wire [31:0] dma_transfer,
    output wire [31:0] r_key,
    output wire [23:0] rem_qpn,
    output wire [23:0] loc_qpn,
    output wire [23:0] rem_psn,
    output wire [23:0] loc_psn,
    output wire [31:0] rem_ip_addr,
    output wire [63:0] rem_addr,
    output wire        start_transfer,

    output wire metadata_valid,

    /*
     * Status signals
     */
    output wire busy
);

  localparam [2:0] STATE_IDLE = 3'd0, STATE_READ_METADATA = 3'd1;

  reg [2:0] state_reg = STATE_IDLE, state_next;

  reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
  reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

  reg m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;

  reg busy_reg = 1'b0;

  reg [3:0] roce_metadata_ptr_reg, roce_metadata_ptr_next;

  reg [15:0] udp_port_reg, udp_port_next;

  reg qp_info_valid_reg, qp_info_valid_next;
  reg [23:0] qp_info_rem_qpn_reg, qp_info_rem_qpn_next;
  reg [23:0] qp_info_loc_qpn_reg, qp_info_loc_qpn_next;
  reg [23:0] qp_info_rem_psn_reg, qp_info_rem_psn_next;
  reg [23:0] qp_info_loc_psn_reg, qp_info_loc_psn_next;
  reg [31:0] qp_info_r_key_reg, qp_info_r_key_next;

  reg txmeta_valid_reg, txmeta_valid_next;
  reg txmeta_start_reg, txmeta_start_next;
  reg txmeta_write_type_reg, txmeta_write_type_next;
  reg [31:0] txmeta_rem_ip_addr_reg, txmeta_rem_ip_addr_next;
  reg [63:0] txmeta_rem_addr_reg, txmeta_rem_addr_next;
  reg [31:0] txmeta_dma_lentgh_reg, txmeta_dma_lentgh_next;
  reg [15:0] txmeta_rem_udp_port_reg, txmeta_rem_udp_port_next;



  reg metadata_valid_reg, metadata_valid_next;

  assign s_udp_hdr_ready = ~rst;
  assign s_udp_payload_axis_tready = ~rst;

  assign busy = busy_reg;

  always @* begin

    state_next                     = STATE_IDLE;

    s_udp_hdr_ready_next           = 1'b0;
    s_udp_payload_axis_tready_next = 1'b0;

    m_udp_hdr_valid_next           = m_udp_hdr_valid_reg;

    metadata_valid_next            = metadata_valid_reg;

    qp_info_valid_next             = qp_info_valid_reg;
    qp_info_rem_qpn_next           = qp_info_rem_qpn_reg;
    qp_info_loc_qpn_next           = qp_info_loc_qpn_reg;
    qp_info_rem_psn_next           = qp_info_rem_psn_reg;
    qp_info_loc_psn_next           = qp_info_loc_psn_reg;
    qp_info_r_key_next             = qp_info_r_key_reg;

    txmeta_valid_next              = txmeta_valid_reg;
    txmeta_start_next              = txmeta_start_reg;
    txmeta_write_type_next         = txmeta_write_type_reg;
    txmeta_rem_ip_addr_next        = txmeta_rem_ip_addr_reg;
    txmeta_rem_addr_next           = txmeta_rem_addr_reg;
    txmeta_dma_lentgh_next         = txmeta_dma_lentgh_reg;
    txmeta_rem_udp_port_next       = txmeta_rem_udp_port_reg;

    roce_metadata_ptr_next         = roce_metadata_ptr_reg;


    case (state_reg)
      STATE_IDLE: begin
        roce_metadata_ptr_next = 4'd0;
        metadata_valid_next = 1'b0;
        // idle state - wait for header
        s_udp_hdr_ready_next = !m_udp_hdr_valid_next;

        udp_port_next = 16'd0;

        qp_info_valid_next = 1'b0;
        txmeta_valid_next = 1'b0;
        txmeta_start_next = 1'b0;

        if (s_udp_hdr_ready && s_udp_hdr_valid) begin
          if (s_udp_dest_port == LISTEN_UDP_PORT && s_udp_length == 16'd44) begin
            state_next = STATE_READ_METADATA;
            udp_port_next = s_udp_dest_port;
            s_udp_hdr_ready_next = 1'b0;
            s_udp_payload_axis_tready_next = 1'b1;
          end else begin
            state_next = STATE_IDLE;
          end
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_READ_METADATA: begin
        // read header state
        s_udp_payload_axis_tready_next = 1'b1;
        state_next = STATE_READ_METADATA;

        if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid && udp_port_reg == LISTEN_UDP_PORT) begin
          case (roce_metadata_ptr_reg)
            4'd0: begin
              qp_info_valid_next = s_udp_payload_axis_tdata[0];
              if (qp_info_valid_next) begin
                qp_info_rem_qpn_next = {
                  s_udp_payload_axis_tdata[15:8],
                  s_udp_payload_axis_tdata[23:16],
                  s_udp_payload_axis_tdata[31:24]

                };
                qp_info_loc_qpn_next = {
                  s_udp_payload_axis_tdata[39:32],
                  s_udp_payload_axis_tdata[47:40],
                  s_udp_payload_axis_tdata[55:48]
                };
                qp_info_rem_psn_next[23:16] = s_udp_payload_axis_tdata[63:56];
              end

              roce_metadata_ptr_next = 4'd1;
            end
            4'd1: begin
              if (qp_info_valid_reg) begin
                qp_info_rem_psn_next[15:0] = {
                  s_udp_payload_axis_tdata[7:0], s_udp_payload_axis_tdata[15:8]
                };
                qp_info_loc_psn_next = {
                  s_udp_payload_axis_tdata[23:16],
                  s_udp_payload_axis_tdata[31:24],
                  s_udp_payload_axis_tdata[39:32]
                };
                qp_info_r_key_next[31:8] = {
                  s_udp_payload_axis_tdata[47:40],
                  s_udp_payload_axis_tdata[55:48],
                  s_udp_payload_axis_tdata[63:56]
                };
              end

              roce_metadata_ptr_next = 4'd2;
            end
            4'd2: begin
              if (qp_info_valid_reg) begin
                qp_info_r_key_next[7:0] = s_udp_payload_axis_tdata[7:0];
              end

              txmeta_valid_next = s_udp_payload_axis_tdata[8];
              txmeta_start_next = s_udp_payload_axis_tdata[9];
              txmeta_write_type_next = s_udp_payload_axis_tdata[10];
              if (txmeta_valid_next) begin
                txmeta_rem_ip_addr_next = {
                  s_udp_payload_axis_tdata[23:16],
                  s_udp_payload_axis_tdata[31:24],
                  s_udp_payload_axis_tdata[39:32],
                  s_udp_payload_axis_tdata[47:40]
                };
                txmeta_rem_addr_next[63:48] = {
                  s_udp_payload_axis_tdata[55:48], s_udp_payload_axis_tdata[63:56]
                };
              end

              roce_metadata_ptr_next = 4'd3;
            end
            4'd3: begin
              if (txmeta_valid_reg) begin
                txmeta_rem_addr_next[48:0] = {
                  s_udp_payload_axis_tdata[7:0],
                  s_udp_payload_axis_tdata[15:8],
                  s_udp_payload_axis_tdata[23:16],
                  s_udp_payload_axis_tdata[31:24],
                  s_udp_payload_axis_tdata[39:32],
                  s_udp_payload_axis_tdata[47:40]
                };
                txmeta_dma_lentgh_next[31:16] = {
                  s_udp_payload_axis_tdata[55:48], s_udp_payload_axis_tdata[63:56]
                };
              end

              roce_metadata_ptr_next = 4'd4;
            end
            4'd4: begin
              if (txmeta_valid_reg) begin
                txmeta_dma_lentgh_next[15:0] = {
                  s_udp_payload_axis_tdata[7:0], s_udp_payload_axis_tdata[15:8]
                };
                txmeta_rem_udp_port_next = {
                  s_udp_payload_axis_tdata[23:16], s_udp_payload_axis_tdata[31:24]
                };
                metadata_valid_next = 1'b1;
              end

              roce_metadata_ptr_next = 4'd5;
            end
            4'd5: begin
              roce_metadata_ptr_next = 4'd5;
            end
          endcase


          if (s_udp_payload_axis_tlast) begin
            roce_metadata_ptr_next = 4'd0;
            m_udp_hdr_valid_next = 1'b0;
            s_udp_hdr_ready_next = !m_udp_hdr_valid_next;
            s_udp_payload_axis_tready_next = 1'b0;
            state_next = STATE_IDLE;
          end

        end else begin
          state_next = STATE_READ_METADATA;
        end
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state_reg <= STATE_IDLE;
      s_udp_hdr_ready_reg <= 1'b0;
      s_udp_payload_axis_tready_reg <= 1'b0;
      m_udp_hdr_valid_reg <= 1'b0;
      busy_reg <= 1'b0;
      roce_metadata_ptr_reg = 4'd0;
      metadata_valid_reg <= 1'b0;

    end else begin
      state_reg                     <= state_next;

      roce_metadata_ptr_reg         <= roce_metadata_ptr_next;
      metadata_valid_reg            <= metadata_valid_next;

      s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
      s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

      m_udp_hdr_valid_reg           <= m_udp_hdr_valid_next;

      udp_port_reg                  <= udp_port_next;

      qp_info_valid_reg             <= qp_info_valid_next;
      qp_info_rem_qpn_reg           <= qp_info_rem_qpn_next;
      qp_info_loc_qpn_reg           <= qp_info_loc_qpn_next;
      qp_info_rem_psn_reg           <= qp_info_rem_psn_next;
      qp_info_loc_psn_reg           <= qp_info_loc_psn_next;
      qp_info_r_key_reg             <= qp_info_r_key_next;

      txmeta_valid_reg              <= txmeta_valid_next;
      txmeta_start_reg              <= txmeta_start_next;
      txmeta_write_type_reg         <= txmeta_write_type_next;
      txmeta_rem_ip_addr_reg        <= txmeta_rem_ip_addr_next;
      txmeta_rem_addr_reg           <= txmeta_rem_addr_next;
      txmeta_dma_lentgh_reg         <= txmeta_dma_lentgh_next;
      txmeta_rem_udp_port_reg       <= txmeta_rem_udp_port_next;



      busy_reg                      <= state_next != STATE_IDLE;
    end


  end

  assign dma_transfer   = txmeta_dma_lentgh_reg;
  assign r_key          = qp_info_r_key_reg;
  assign rem_qpn        = qp_info_rem_qpn_reg;
  assign rem_psn        = qp_info_rem_psn_reg;
  assign rem_addr       = txmeta_rem_addr_reg;
  assign start_transfer = txmeta_start_reg;

  assign metadata_valid = metadata_valid_reg;

endmodule

`resetall
