`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * UDP ethernet frame receiver (IP frame in, UDP frame out, 64 bit datapath)
 */

/*
  * Structure
  * +---------+-------------+--------------------------+
  * | OCTETS  |  BIT RANGE  |       Field              |
  * +---------+-------------+--------------------------+
  * |   0     |  [0  :0  ]  |  QP_info_valid           |
  * |   0     |  [7  :1  ]  |  QP_info_reserved        |
  * | [3:1]   |  [31 :8  ]  |  QP_info_rem_qpn         |
  * | [6:4]   |  [55 :32 ]  |  QP_info_loc_qpn         |
  * | [9:7]   |  [79 :56 ]  |  QP_info_rem_psn         |
  * | [12:10] |  [103:80 ]  |  QP_info_loc_psn         |
  * | [16:13] |  [135:104]  |  QP_info_r_key           |
  * | [24:17] |  [199:136]  |  QP_info_rem_base_addr   |
  * +---------+-------------+--------------------------+
  * |   25    |  [200:200]  |  txmeta_valid            |
  * |   25    |  [201:201]  |  txmeta_start            |
  * |   25    |  [202:202]  |  txmeta_write_type       |
  * |   25    |  [207:203]  |  txmeta_reserved         |
  * | [29:26] |  [239:208]  |  txmeta_rem_ip_addr      |
  * | [37:30] |  [303:240]  |  txmeta_rem_addr_offset  |
  * | [41:38] |  [335:304]  |  txmeta_dma_length       |
  * | [43:42] |  [351:336]  |  txmeta_rem_udp_port     |
  * +---------+-------------+--------------------------+
  * TOTAL length 352 bits, 44 bytes
  */

module udp_RoCE_connection_manager_512 #(
    parameter LISTEN_UDP_PORT = 16'h4321
) (
    input wire clk,
    input wire rst,

    /*
     * UDP frame input
     */
    input  wire         s_udp_hdr_valid,
    output wire         s_udp_hdr_ready,
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_length,
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
    input  wire [511:0] s_udp_payload_axis_tdata,
    input  wire [ 63:0] s_udp_payload_axis_tkeep,
    input  wire         s_udp_payload_axis_tvalid,
    output wire         s_udp_payload_axis_tready,
    input  wire         s_udp_payload_axis_tlast,
    input  wire         s_udp_payload_axis_tuser,

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
    output wire        write_type,
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

  reg [15:0] udp_port_reg, udp_port_next;

  reg qp_info_valid_reg, qp_info_valid_next;
  reg [23:0] qp_info_rem_qpn_reg, qp_info_rem_qpn_next;
  reg [23:0] qp_info_loc_qpn_reg, qp_info_loc_qpn_next;
  reg [23:0] qp_info_rem_psn_reg, qp_info_rem_psn_next;
  reg [23:0] qp_info_loc_psn_reg, qp_info_loc_psn_next;
  reg [31:0] qp_info_r_key_reg, qp_info_r_key_next;
  reg [63:0] qp_info_rem_base_addr_reg, qp_info_rem_base_addr_next;

  reg txmeta_valid_reg, txmeta_valid_next;
  reg txmeta_start_reg, txmeta_start_next;
  reg txmeta_write_type_reg, txmeta_write_type_next;
  reg [31:0] txmeta_rem_ip_addr_reg, txmeta_rem_ip_addr_next;
  reg [63:0] txmeta_rem_addr_offset_reg, txmeta_rem_addr_offset_next;
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

    udp_port_next                  = udp_port_reg;

    qp_info_valid_next             = qp_info_valid_reg;
    qp_info_rem_qpn_next           = qp_info_rem_qpn_reg;
    qp_info_loc_qpn_next           = qp_info_loc_qpn_reg;
    qp_info_rem_psn_next           = qp_info_rem_psn_reg;
    qp_info_loc_psn_next           = qp_info_loc_psn_reg;
    qp_info_r_key_next             = qp_info_r_key_reg;
    qp_info_rem_base_addr_next     = qp_info_rem_base_addr_reg;

    txmeta_valid_next              = txmeta_valid_reg;
    txmeta_start_next              = txmeta_start_reg;
    txmeta_write_type_next         = txmeta_write_type_reg;
    txmeta_rem_ip_addr_next        = txmeta_rem_ip_addr_reg;
    txmeta_rem_addr_offset_next    = txmeta_rem_addr_offset_reg;
    txmeta_dma_lentgh_next         = txmeta_dma_lentgh_reg;
    txmeta_rem_udp_port_next       = txmeta_rem_udp_port_reg;

    case (state_reg)
      STATE_IDLE: begin
        metadata_valid_next  = 1'b0;
        // idle state - wait for header
        s_udp_hdr_ready_next = !m_udp_hdr_valid_next;

        udp_port_next        = 16'd0;

        qp_info_valid_next   = 1'b0;
        txmeta_valid_next    = 1'b0;
        txmeta_start_next    = 1'b0;

        if (s_udp_hdr_ready && s_udp_hdr_valid) begin
          if (s_udp_dest_port == LISTEN_UDP_PORT && s_udp_length == 16'd52) begin
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

          qp_info_valid_next = s_udp_payload_axis_tdata[0];
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

          qp_info_rem_psn_next = {
            s_udp_payload_axis_tdata[63:56],
            s_udp_payload_axis_tdata[71:64],
            s_udp_payload_axis_tdata[79:72]
          };
          qp_info_loc_psn_next = {
            s_udp_payload_axis_tdata[87:80],
            s_udp_payload_axis_tdata[95:88],
            s_udp_payload_axis_tdata[103:96]
          };
          qp_info_r_key_next = {
            s_udp_payload_axis_tdata[111:104],
            s_udp_payload_axis_tdata[119:112],
            s_udp_payload_axis_tdata[127:120],
            s_udp_payload_axis_tdata[135:128]
          };

          qp_info_rem_base_addr_next = {
            s_udp_payload_axis_tdata[143:136],
            s_udp_payload_axis_tdata[151:144],
            s_udp_payload_axis_tdata[159:152],
            s_udp_payload_axis_tdata[167:160],
            s_udp_payload_axis_tdata[175:168],
            s_udp_payload_axis_tdata[183:176],
            s_udp_payload_axis_tdata[191:184],
            s_udp_payload_axis_tdata[199:192]
          };

          txmeta_valid_next = s_udp_payload_axis_tdata[200];
          txmeta_start_next = s_udp_payload_axis_tdata[201];
          txmeta_write_type_next = s_udp_payload_axis_tdata[202];
          if (txmeta_valid_next) begin
            txmeta_rem_ip_addr_next = {
              s_udp_payload_axis_tdata[215:208],
              s_udp_payload_axis_tdata[223:216],
              s_udp_payload_axis_tdata[231:224],
              s_udp_payload_axis_tdata[239:232]
            };
            txmeta_rem_addr_offset_next = {
              s_udp_payload_axis_tdata[247:240],
              s_udp_payload_axis_tdata[255:248],
              s_udp_payload_axis_tdata[263:256],
              s_udp_payload_axis_tdata[271:264],
              s_udp_payload_axis_tdata[279:272],
              s_udp_payload_axis_tdata[287:280],
              s_udp_payload_axis_tdata[295:288],
              s_udp_payload_axis_tdata[303:296]
            };
            txmeta_dma_lentgh_next = {
              s_udp_payload_axis_tdata[311:304],
              s_udp_payload_axis_tdata[319:312],
              s_udp_payload_axis_tdata[327:320],
              s_udp_payload_axis_tdata[335:328]
            };

            txmeta_rem_udp_port_next = {
              s_udp_payload_axis_tdata[343:336], s_udp_payload_axis_tdata[351:344]
            };
            metadata_valid_next = 1'b1;
          end

          if (s_udp_payload_axis_tlast) begin
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
      state_reg                     <= STATE_IDLE;
      s_udp_hdr_ready_reg           <= 1'b0;
      s_udp_payload_axis_tready_reg <= 1'b0;
      m_udp_hdr_valid_reg           <= 1'b0;
      busy_reg                      <= 1'b0;
      metadata_valid_reg            <= 1'b0;

    end else begin
      state_reg                     <= state_next;

      metadata_valid_reg            <= metadata_valid_next;

      s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
      s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

      m_udp_hdr_valid_reg           <= m_udp_hdr_valid_next;

      udp_port_reg                  <= udp_port_next;

      qp_info_valid_reg             <= qp_info_valid_next;
      if (qp_info_valid_next) begin
        qp_info_rem_qpn_reg       <= qp_info_rem_qpn_next;
        qp_info_loc_qpn_reg       <= qp_info_loc_qpn_next;
        qp_info_rem_psn_reg       <= qp_info_rem_psn_next;
        qp_info_loc_psn_reg       <= qp_info_loc_psn_next;
        qp_info_r_key_reg         <= qp_info_r_key_next;
        qp_info_rem_base_addr_reg <= qp_info_rem_base_addr_next;
      end

      txmeta_valid_reg <= txmeta_valid_next;
      if (txmeta_valid_next) begin
        txmeta_start_reg           <= txmeta_start_next;
        txmeta_write_type_reg      <= txmeta_write_type_next;
        txmeta_rem_ip_addr_reg     <= txmeta_rem_ip_addr_next;
        txmeta_rem_addr_offset_reg <= txmeta_rem_addr_offset_next;
        txmeta_dma_lentgh_reg      <= txmeta_dma_lentgh_next;
        txmeta_rem_udp_port_reg    <= txmeta_rem_udp_port_next;
      end else begin
        txmeta_start_reg           <= 1'b0;
      end

      busy_reg <= state_next != STATE_IDLE;
    end


  end

  assign dma_transfer   = txmeta_dma_lentgh_reg;
  assign rem_ip_addr    = txmeta_rem_ip_addr_reg;
  assign r_key          = qp_info_r_key_reg;

  assign rem_qpn        = qp_info_rem_qpn_reg;
  assign rem_psn        = qp_info_rem_psn_reg;
  assign rem_addr       = qp_info_rem_base_addr_reg + txmeta_rem_addr_offset_reg;

  assign loc_qpn        = qp_info_loc_qpn_reg;
  assign loc_psn        = qp_info_loc_psn_reg;
  
  assign write_type     = txmeta_write_type_reg;
  
  assign start_transfer = txmeta_start_reg & metadata_valid_reg;

  assign metadata_valid = metadata_valid_reg;

endmodule

`resetall
