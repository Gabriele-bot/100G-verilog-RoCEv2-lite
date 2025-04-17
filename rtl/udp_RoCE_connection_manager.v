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
 * |   0     |  [1  :1  ]  |  QP_info_open_qp         |
 * |   0     |  [7  :2  ]  |  QP_info_reserved        |
 * | [3:1]   |  [31 :8  ]  |  QP_info_rem_qpn         |
 * | [6:4]   |  [55 :32 ]  |  QP_info_loc_qpn         |
 * | [9:7]   |  [79 :56 ]  |  QP_info_rem_psn         |
 * | [12:10] |  [103:80 ]  |  QP_info_loc_psn         |
 * | [16:13] |  [135:104]  |  QP_info_r_key           |
 * | [24:17] |  [199:136]  |  QP_info_rem_base_addr   |
 * | [28:25] |  [231:200]  |  QP_info_rem_ip_addr     |
 * +---------+-------------+--------------------------+
 * |   29    |  [232:232]  |  txmeta_valid            |
 * |   29    |  [233:233]  |  txmeta_start            |
 * |   29    |  [234:234]  |  txmeta_is_immediate     |
 * |   29    |  [235:235]  |  txmeta_tx_type          |
 * |   29    |  [239:236]  |  txmeta_reserved         |
 * | [37:30] |  [303:240]  |  txmeta_rem_addr_offset  |
 * | [41:38] |  [335:304]  |  txmeta_dma_length       |
 * | [43:42] |  [351:336]  |  txmeta_rem_udp_port     |
 * +---------+-------------+--------------------------+
 * TOTAL length 352 bits, 44 bytes
 */

module udp_RoCE_connection_manager #(
  parameter DATA_WIDTH      = 256,
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
  input  wire [DATA_WIDTH   - 1 : 0] s_udp_payload_axis_tdata,
  input  wire [DATA_WIDTH/8 - 1 : 0] s_udp_payload_axis_tkeep,
  input  wire         s_udp_payload_axis_tvalid,
  output wire         s_udp_payload_axis_tready,
  input  wire         s_udp_payload_axis_tlast,
  input  wire         s_udp_payload_axis_tuser,

  /*
   * RoCE QP parameters
   */
  output wire        open_qp,
  output wire [31:0] dma_transfer,
  output wire [31:0] r_key,
  output wire [23:0] rem_qpn,
  output wire [23:0] loc_qpn,
  output wire [23:0] rem_psn,
  output wire [23:0] loc_psn,
  output wire [31:0] rem_ip_addr,
  output wire [63:0] rem_addr,
  output wire        is_immediate,
  output wire        tx_type, // 0 SEND, 1 RDMA WRITE 
  output wire        start_transfer,

  output wire metadata_valid,
  output wire qp_context_valid,

  /*
   * Status signals
   */
  output wire busy
);

  parameter KEEP_ENABLE = 1;
  parameter KEEP_WIDTH  = DATA_WIDTH/8;

  parameter BYTE_LANES = KEEP_WIDTH;

  parameter QP_INFO_SIZE = 44;

  parameter CYCLE_COUNT = (QP_INFO_SIZE+BYTE_LANES-1)/BYTE_LANES;

  parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

  parameter OFFSET = QP_INFO_SIZE % BYTE_LANES;



  localparam QP_INFO_VALID_OFFSET         = 0;
  localparam QP_INFO_REM_QPN_OFFSET       = 8;
  localparam QP_INFO_LOC_QPN_OFFSET       = 32;
  localparam QP_INFO_REM_PSN_OFFSET       = 56;
  localparam QP_INFO_LOC_PSN_OFFSET       = 80;
  localparam QP_INFO_RKEY_OFFSET          = 104;
  localparam QP_INFO_REM_BASE_ADDR_OFFSET = 136;
  localparam QP_INFO_REM_IPADDR_OFFSET    = 200;

  localparam TX_META_VALID_OFFSET         = 232;
  localparam TX_META_START_OFFSET         = 233;
  localparam TX_META_IS_IMMD_OFFSET       = 234;
  localparam TX_META_TX_TYPE_OFFSET       = 235;
  localparam TX_META_REM_ADDR_OFF_OFFSET  = 240;
  localparam TX_META_DMA_LENGTH_OFFSET    = 304;
  localparam TX_META_REM_UDP_PORT_OFFSET  = 336;

  reg [3:0] temp_4bits;
  reg [5:0] temp_6bits;

  reg read_qp_info_reg = 1'b1, read_qp_info_next;
  reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

  localparam [2:0] STATE_IDLE = 3'd0, STATE_READ_METADATA = 3'd1;

  reg [2:0] state_reg = STATE_IDLE, state_next;

  reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
  reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

  reg m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;

  reg busy_reg = 1'b0;

  reg [15:0] udp_port_reg, udp_port_next;


  reg qp_info_valid_reg, qp_info_valid_next;
  reg qp_info_open_qp_reg, qp_info_open_qp_next;
  reg [23:0] qp_info_rem_qpn_reg, qp_info_rem_qpn_next;
  reg [23:0] qp_info_loc_qpn_reg, qp_info_loc_qpn_next;
  reg [23:0] qp_info_rem_psn_reg, qp_info_rem_psn_next;
  reg [23:0] qp_info_loc_psn_reg, qp_info_loc_psn_next;
  reg [31:0] qp_info_r_key_reg, qp_info_r_key_next;
  reg [63:0] qp_info_rem_base_addr_reg, qp_info_rem_base_addr_next;
  reg [31:0] qp_info_rem_ip_addr_reg, qp_info_rem_ip_addr_next;

  reg txmeta_valid_reg, txmeta_valid_next;
  reg txmeta_start_reg, txmeta_start_next;
  reg txmeta_is_immediate_reg, txmeta_is_immediate_next;
  reg txmeta_tx_type_reg, txmeta_tx_type_next;
  reg [63:0] txmeta_rem_addr_offset_reg, txmeta_rem_addr_offset_next;
  reg [31:0] txmeta_dma_lentgh_reg, txmeta_dma_lentgh_next;
  reg [15:0] txmeta_rem_udp_port_reg, txmeta_rem_udp_port_next;

  reg qp_context_valid_reg, qp_context_valid_next;

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
    qp_context_valid_next          = qp_context_valid_reg;
    txmeta_valid_next = txmeta_valid_reg;

    udp_port_next                  = udp_port_reg;

    ptr_next = ptr_reg;

    qp_info_valid_next             = qp_info_valid_reg;
    qp_info_open_qp_next           = qp_info_open_qp_reg;
    qp_info_rem_qpn_next           = qp_info_rem_qpn_reg;
    qp_info_loc_qpn_next           = qp_info_loc_qpn_reg;
    qp_info_rem_psn_next           = qp_info_rem_psn_reg;
    qp_info_loc_psn_next           = qp_info_loc_psn_reg;
    qp_info_r_key_next             = qp_info_r_key_reg;
    qp_info_rem_base_addr_next     = qp_info_rem_base_addr_reg;
    qp_info_rem_ip_addr_next        = qp_info_rem_ip_addr_reg;

    txmeta_valid_next              = txmeta_valid_reg;
    txmeta_start_next              = txmeta_start_reg;
    txmeta_is_immediate_next       = txmeta_is_immediate_reg;
    txmeta_tx_type_next            = txmeta_tx_type_reg;
    txmeta_rem_addr_offset_next    = txmeta_rem_addr_offset_reg;
    txmeta_dma_lentgh_next         = txmeta_dma_lentgh_reg;
    txmeta_rem_udp_port_next       = txmeta_rem_udp_port_reg;

    case (state_reg)
      STATE_IDLE: begin
        metadata_valid_next    = 1'b0;
        qp_context_valid_next  = 1'b0;
        // idle state - wait for header
        s_udp_hdr_ready_next = !m_udp_hdr_valid_next;

        read_qp_info_next = read_qp_info_reg;
        ptr_next = ptr_reg;

        udp_port_next        = 16'd0;

        qp_info_valid_next   = qp_info_valid_reg;
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

          /*
          qp_info_valid_next = s_udp_payload_axis_tdata[QP_INFO_VALID_OFFSET];
          qp_info_rem_qpn_next = {
          s_udp_payload_axis_tdata[QP_INFO_REM_QPN_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_QPN_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_QPN_OFFSET+16 +: 8]

          };
          qp_info_loc_qpn_next = {
          s_udp_payload_axis_tdata[QP_INFO_LOC_QPN_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_LOC_QPN_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_LOC_QPN_OFFSET+16 +: 8]
          };

          qp_info_rem_psn_next = {
          s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET+16 +: 8]
          };
          qp_info_loc_psn_next = {
          s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET+16 +: 8]
          };
          qp_info_r_key_next = {
          s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+16 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+24 +: 8]
          };

          qp_info_rem_base_addr_next = {
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+16 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+24 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+32 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+40 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+48 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+56 +: 8]
          };

          qp_info_rem_ip_addr_next = {
          s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET    +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+8  +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+16 +: 8],
          s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+24 +: 8]
          };

          txmeta_valid_next = s_udp_payload_axis_tdata[TX_META_VALID_OFFSET];
          txmeta_start_next = s_udp_payload_axis_tdata[TX_META_START_OFFSET];
          txmeta_is_immediate_next = s_udp_payload_axis_tdata[TX_META_IS_IMMD_OFFSET];
          txmeta_tx_type_next      = s_udp_payload_axis_tdata[TX_META_TX_TYPE_OFFSET];
          if (txmeta_valid_next) begin
            txmeta_rem_addr_offset_next = {
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET    +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+8  +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+16 +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+24 +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+32 +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+40 +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+48 +: 8],
            s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+56 +: 8]
            };
            txmeta_dma_lentgh_next = {
            s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET    +: 8],
            s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+8  +: 8],
            s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+16 +: 8],
            s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+24 +: 8]
            };

            txmeta_rem_udp_port_next = {
            s_udp_payload_axis_tdata[TX_META_REM_UDP_PORT_OFFSET    +: 8], s_udp_payload_axis_tdata[TX_META_REM_UDP_PORT_OFFSET+8    +: 8]
            };
            metadata_valid_next = 1'b1;

          end
          */

          ptr_next = ptr_reg + 1; 

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_udp_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

          `_HEADER_FIELD_(0 ,   {temp_6bits, qp_info_open_qp_next, qp_info_valid_next})
          `_HEADER_FIELD_(1 ,  qp_info_rem_qpn_next[0*8 +: 8])
          `_HEADER_FIELD_(2 ,  qp_info_rem_qpn_next[1*8 +: 8])
          `_HEADER_FIELD_(3 ,  qp_info_rem_qpn_next[2*8 +: 8])
          `_HEADER_FIELD_(4 ,  qp_info_loc_qpn_next[0*8 +: 8])
          `_HEADER_FIELD_(5 ,  qp_info_loc_qpn_next[1*8 +: 8])
          `_HEADER_FIELD_(6 ,  qp_info_loc_qpn_next[2*8 +: 8])
          `_HEADER_FIELD_(7 ,  qp_info_rem_psn_next[0*8 +: 8])
          `_HEADER_FIELD_(8 ,  qp_info_rem_psn_next[1*8 +: 8])
          `_HEADER_FIELD_(9 ,  qp_info_rem_psn_next[2*8 +: 8])
          `_HEADER_FIELD_(10,  qp_info_loc_psn_next[0*8 +: 8])
          `_HEADER_FIELD_(11,  qp_info_loc_psn_next[1*8 +: 8])
          `_HEADER_FIELD_(12,  qp_info_loc_psn_next[2*8 +: 8])
          `_HEADER_FIELD_(13,  qp_info_r_key_next[0*8 +: 8])
          `_HEADER_FIELD_(14,  qp_info_r_key_next[1*8 +: 8])
          `_HEADER_FIELD_(15,  qp_info_r_key_next[2*8 +: 8])
          `_HEADER_FIELD_(16,  qp_info_r_key_next[3*8 +: 8])
          `_HEADER_FIELD_(17,  qp_info_rem_base_addr_next[0*8 +: 8])
          `_HEADER_FIELD_(18,  qp_info_rem_base_addr_next[1*8 +: 8])
          `_HEADER_FIELD_(19,  qp_info_rem_base_addr_next[2*8 +: 8])
          `_HEADER_FIELD_(20,  qp_info_rem_base_addr_next[3*8 +: 8])
          `_HEADER_FIELD_(21,  qp_info_rem_base_addr_next[4*8 +: 8])
          `_HEADER_FIELD_(22,  qp_info_rem_base_addr_next[5*8 +: 8])
          `_HEADER_FIELD_(23,  qp_info_rem_base_addr_next[6*8 +: 8])
          `_HEADER_FIELD_(24,  qp_info_rem_base_addr_next[7*8 +: 8])
          `_HEADER_FIELD_(25,  qp_info_rem_ip_addr_next[0*8 +: 8])
          `_HEADER_FIELD_(26,  qp_info_rem_ip_addr_next[1*8 +: 8])
          `_HEADER_FIELD_(27,  qp_info_rem_ip_addr_next[2*8 +: 8])
          `_HEADER_FIELD_(28,  qp_info_rem_ip_addr_next[3*8 +: 8])
          `_HEADER_FIELD_(29,  {temp_4bits, txmeta_tx_type_next, txmeta_is_immediate_next, txmeta_start_next, txmeta_valid_next})
          `_HEADER_FIELD_(30,  txmeta_rem_addr_offset_next[0*8 +: 8])
          `_HEADER_FIELD_(31,  txmeta_rem_addr_offset_next[1*8 +: 8])
          `_HEADER_FIELD_(32,  txmeta_rem_addr_offset_next[2*8 +: 8])
          `_HEADER_FIELD_(33,  txmeta_rem_addr_offset_next[3*8 +: 8])
          `_HEADER_FIELD_(34,  txmeta_rem_addr_offset_next[4*8 +: 8])
          `_HEADER_FIELD_(35,  txmeta_rem_addr_offset_next[5*8 +: 8])
          `_HEADER_FIELD_(36,  txmeta_rem_addr_offset_next[6*8 +: 8])
          `_HEADER_FIELD_(37,  txmeta_rem_addr_offset_next[7*8 +: 8])
          `_HEADER_FIELD_(38,  txmeta_dma_lentgh_next[0*8 +: 8])
          `_HEADER_FIELD_(39,  txmeta_dma_lentgh_next[1*8 +: 8])
          `_HEADER_FIELD_(40,  txmeta_dma_lentgh_next[2*8 +: 8])
          `_HEADER_FIELD_(41,  txmeta_dma_lentgh_next[3*8 +: 8])
          `_HEADER_FIELD_(42,  txmeta_rem_udp_port_next[0*8 +: 8])
          `_HEADER_FIELD_(43,  txmeta_rem_udp_port_next[1*8 +: 8])

          if (ptr_reg == (QP_INFO_SIZE-1)/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[(QP_INFO_SIZE-1)%BYTE_LANES])) begin
            if (s_udp_payload_axis_tlast) begin
              metadata_valid_next   = txmeta_valid_next;
              qp_context_valid_next = qp_info_valid_next;
              read_qp_info_next = 1'b0;
            end
          end
          `undef _HEADER_FIELD_


          if (s_udp_payload_axis_tlast) begin
            m_udp_hdr_valid_next = 1'b0;
            s_udp_hdr_ready_next = !m_udp_hdr_valid_next;
            s_udp_payload_axis_tready_next = 1'b0;
            ptr_next                       = 0;
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
      qp_context_valid_reg          <= qp_context_valid_next;

      s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
      s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

      ptr_reg                       <= ptr_next;
      read_qp_info_reg              <= read_qp_info_next;

      m_udp_hdr_valid_reg           <= m_udp_hdr_valid_next;

      udp_port_reg                  <= udp_port_next;

      qp_info_valid_reg             <= qp_info_valid_next;
      if (qp_info_valid_next) begin
        qp_info_open_qp_reg       <= qp_info_open_qp_next;
        qp_info_rem_qpn_reg       <= qp_info_rem_qpn_next;
        qp_info_loc_qpn_reg       <= qp_info_loc_qpn_next;
        qp_info_rem_psn_reg       <= qp_info_rem_psn_next;
        qp_info_loc_psn_reg       <= qp_info_loc_psn_next;
        qp_info_r_key_reg         <= qp_info_r_key_next;
        qp_info_rem_base_addr_reg <= qp_info_rem_base_addr_next;
        qp_info_rem_ip_addr_reg   <= qp_info_rem_ip_addr_next;
      end

      txmeta_valid_reg <= txmeta_valid_next;
      if (txmeta_valid_next) begin
        qp_info_loc_qpn_reg        <= qp_info_loc_qpn_next;
        txmeta_start_reg           <= txmeta_start_next;
        txmeta_is_immediate_reg    <= txmeta_is_immediate_next;
        txmeta_tx_type_reg         <= txmeta_tx_type_next;
        txmeta_rem_addr_offset_reg <= txmeta_rem_addr_offset_next;
        txmeta_dma_lentgh_reg      <= txmeta_dma_lentgh_next;
        txmeta_rem_udp_port_reg    <= txmeta_rem_udp_port_next;
      end else begin
        txmeta_start_reg           <= 1'b0;
        txmeta_rem_addr_offset_reg <= 0;
      end

      busy_reg <= state_next != STATE_IDLE;
    end


  end

  assign open_qp        = qp_info_open_qp_reg; // 1 for opening qp,  0 for closing qp
  assign dma_transfer   = txmeta_dma_lentgh_reg;
  assign rem_ip_addr    = qp_info_rem_ip_addr_reg;
  assign r_key          = qp_info_r_key_reg;

  assign rem_qpn        = qp_info_rem_qpn_reg;
  assign rem_psn        = qp_info_rem_psn_reg;
  assign rem_addr       = qp_info_rem_base_addr_reg + txmeta_rem_addr_offset_reg;

  assign loc_qpn        = qp_info_loc_qpn_reg;
  assign loc_psn        = qp_info_loc_psn_reg;

  assign is_immediate   = txmeta_is_immediate_reg;
  assign tx_type        = txmeta_tx_type_reg;

  assign start_transfer = txmeta_start_reg & metadata_valid_reg;

  assign metadata_valid = metadata_valid_reg;

  assign qp_context_valid = qp_context_valid_reg;

endmodule

`resetall
