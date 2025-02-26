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
reg [63:0] qp_info_rem_base_addr_reg, qp_info_rem_base_addr_next;
reg [31:0] qp_info_rem_ip_addr_reg, qp_info_rem_ip_addr_next;

reg qp_context_valid_reg, qp_context_valid_next;

reg txmeta_valid_reg, txmeta_valid_next;
reg txmeta_start_reg, txmeta_start_next;
reg txmeta_is_immediate_reg, txmeta_is_immediate_next;
reg txmeta_tx_type_reg, txmeta_tx_type_next;
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
    qp_context_valid_next          = qp_context_valid_reg;

    udp_port_next                  = udp_port_reg;

    qp_info_valid_next             = qp_info_valid_reg;
    qp_info_rem_qpn_next           = qp_info_rem_qpn_reg;
    qp_info_loc_qpn_next           = qp_info_loc_qpn_reg;
    qp_info_rem_psn_next           = qp_info_rem_psn_reg;
    qp_info_loc_psn_next           = qp_info_loc_psn_reg;
    qp_info_r_key_next             = qp_info_r_key_reg;
    qp_info_rem_base_addr_next     = qp_info_rem_base_addr_reg;
    qp_info_rem_ip_addr_next       = qp_info_rem_ip_addr_reg;

    txmeta_valid_next              = txmeta_valid_reg;
    txmeta_start_next              = txmeta_start_reg;
    txmeta_is_immediate_next       = txmeta_is_immediate_reg;
    txmeta_tx_type_next            = txmeta_tx_type_reg;
    txmeta_rem_addr_offset_next    = txmeta_rem_addr_offset_reg;
    txmeta_dma_lentgh_next         = txmeta_dma_lentgh_reg;
    txmeta_rem_udp_port_next       = txmeta_rem_udp_port_reg;

    roce_metadata_ptr_next         = roce_metadata_ptr_reg;


    case (state_reg)
      STATE_IDLE: begin
        roce_metadata_ptr_next = 4'd0;
        metadata_valid_next    = 1'b0;
        qp_context_valid_next  = 1'b0;
        // idle state - wait for header
        s_udp_hdr_ready_next = !m_udp_hdr_valid_next;

        udp_port_next = 16'd0;

        qp_info_valid_next = 1'b0;
        txmeta_valid_next = 1'b0;
        txmeta_start_next = 1'b0;

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
          case (roce_metadata_ptr_reg)
            4'd0: begin
              qp_info_valid_next = s_udp_payload_axis_tdata[QP_INFO_VALID_OFFSET];
              if (qp_info_valid_next) begin
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
                qp_info_rem_psn_next[23:16] = s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET +: 8];
              end

              roce_metadata_ptr_next = 4'd1;
            end
            4'd1: begin
              if (qp_info_valid_reg) begin
                qp_info_rem_psn_next[15:0] = {
                s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET+8-64 +: 8], s_udp_payload_axis_tdata[QP_INFO_REM_PSN_OFFSET+16-64 +: 8]
                };
                qp_info_loc_psn_next = {
                s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET   -64 +: 8],
                s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET+8 -64 +: 8],
                s_udp_payload_axis_tdata[QP_INFO_LOC_PSN_OFFSET+16-64 +: 8]
                };
                qp_info_r_key_next[31:8] = {
                s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET   -64    +: 8],
                s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+8 -64    +: 8],
                s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+16-64    +: 8]
                };
              end

              roce_metadata_ptr_next = 4'd2;
            end
            4'd2: begin
              if (qp_info_valid_reg) begin
                qp_info_r_key_next[7:0]           = s_udp_payload_axis_tdata[QP_INFO_RKEY_OFFSET+24-128    +: 8];

                qp_info_rem_base_addr_next[63:56] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET   -128 +: 8];
                qp_info_rem_base_addr_next[55:48] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+8 -128 +: 8];
                qp_info_rem_base_addr_next[47:40] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+16-128 +: 8];
                qp_info_rem_base_addr_next[39:32] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+24-128 +: 8];
                qp_info_rem_base_addr_next[31:24] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+32-128 +: 8];
                qp_info_rem_base_addr_next[23:16] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+40-128 +: 8];
                qp_info_rem_base_addr_next[15:8]  = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+48-128 +: 8];
              end



              roce_metadata_ptr_next = 4'd3;
            end
            4'd3: begin

              if (qp_info_valid_reg) begin
                qp_info_rem_base_addr_next[7:0] = s_udp_payload_axis_tdata[QP_INFO_REM_BASE_ADDR_OFFSET+56-192 +: 8];
                qp_info_rem_ip_addr_next = {
                s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET   -192 +: 8],
                s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+8 -192 +: 8],
                s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+16-192 +: 8],
                s_udp_payload_axis_tdata[QP_INFO_REM_IPADDR_OFFSET+24-192 +: 8]
                };
              end



              txmeta_valid_next = s_udp_payload_axis_tdata[TX_META_VALID_OFFSET-192];
              txmeta_start_next = s_udp_payload_axis_tdata[TX_META_START_OFFSET-192];
              txmeta_is_immediate_next = s_udp_payload_axis_tdata[TX_META_IS_IMMD_OFFSET-192];
              txmeta_tx_type_next      = s_udp_payload_axis_tdata[TX_META_TX_TYPE_OFFSET-192];
              if (txmeta_valid_next) begin
                txmeta_rem_addr_offset_next[63:48] = {
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET-192 +: 8], s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+8-192 +: 8]
                };
              end

              roce_metadata_ptr_next = 4'd4;
            end
            4'd4: begin

              if (txmeta_valid_reg) begin
                txmeta_rem_addr_offset_next[48:0] = {
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+16-256 +: 8],
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+24-256 +: 8],
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+32-256 +: 8],
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+40-256 +: 8],
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+48-256 +: 8],
                s_udp_payload_axis_tdata[TX_META_REM_ADDR_OFF_OFFSET+56-256 +: 8]
                };
                txmeta_dma_lentgh_next[31:16] = {
                s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET-256 +: 8], s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+8-256 +: 8]
                };
              end

              roce_metadata_ptr_next = 4'd5;
            end
            4'd5: begin
              if (txmeta_valid_reg) begin
                txmeta_dma_lentgh_next[15:0] = {
                s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+16-320 +: 8], s_udp_payload_axis_tdata[TX_META_DMA_LENGTH_OFFSET+24-320 +: 8]
                };
                txmeta_rem_udp_port_next = {
                s_udp_payload_axis_tdata[TX_META_REM_UDP_PORT_OFFSET-320 +: 8], s_udp_payload_axis_tdata[TX_META_REM_UDP_PORT_OFFSET+8-320 +: 8]
                };
                metadata_valid_next = 1'b1;
              end
              qp_context_valid_next = qp_info_valid_reg;

              roce_metadata_ptr_next = 4'd6;
            end

            4'd6: begin
              roce_metadata_ptr_next = 4'd6;
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
      state_reg                     <= STATE_IDLE;
      s_udp_hdr_ready_reg           <= 1'b0;
      s_udp_payload_axis_tready_reg <= 1'b0;
      m_udp_hdr_valid_reg           <= 1'b0;
      busy_reg                      <= 1'b0;
      roce_metadata_ptr_reg         <= 4'd0;
      metadata_valid_reg            <= 1'b0;

    end else begin
      state_reg                     <= state_next;

      roce_metadata_ptr_reg         <= roce_metadata_ptr_next;
      metadata_valid_reg            <= metadata_valid_next;
      qp_context_valid_reg          <= qp_context_valid_next;

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
        qp_info_rem_ip_addr_reg    <= qp_info_rem_ip_addr_next;
      end

      txmeta_valid_reg <= txmeta_valid_next;
      if (txmeta_valid_next) begin
        txmeta_start_reg           <= txmeta_start_next;
        txmeta_is_immediate_reg    <= txmeta_is_immediate_next;
        txmeta_tx_type_reg         <= txmeta_tx_type_next;
        txmeta_rem_addr_offset_reg <= txmeta_rem_addr_offset_next;
        txmeta_dma_lentgh_reg      <= txmeta_dma_lentgh_next;
        txmeta_rem_udp_port_reg    <= txmeta_rem_udp_port_next;
      end else begin
        txmeta_rem_addr_offset_reg <= 0;
      end
      

      busy_reg <= state_next != STATE_IDLE;
    end


  end

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
