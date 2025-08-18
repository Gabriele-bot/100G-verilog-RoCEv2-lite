`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * Connection manager over UDP, RX path
 * TX meta used only for debug purposes
 */

/*
 * Structure
 * +---------+-------------+--------------------------+
 * | OCTETS  |  BIT RANGE  |       Field              |
 * +---------+-------------+--------------------------+
 * |   0     |  [0  :0  ]  |  QP_info_valid           |
 * |   0     |  [3  :1  ]  |  QP_req_type             |
 * |   0     |  [4  :4  ]  |  QP_ack_valid            |
 * |   0     |  [7  :5  ]  |  QP_ack_type             |
 * | [3:1]   |  [32 :8  ]  |  QP_info_loc_qpn         |
 * |   4     |  [39 :33 ]  |  ZERO_PADD               |
 * | [7:5]   |  [63 :40 ]  |  QP_info_loc_psn         |
 * |   8     |  [71 :64 ]  |  ZERO_PADD               |
 * | [12:9]  |  [103 :72]  |  QP_info_loc_r_key       |
 * | [20:13] |  [167:104]  |  QP_info_loc_base_addr   |
 * | [24:21] |  [199:168]  |  QP_info_loc_ip_addr     |
 * | [27:25] |  [223:200]  |  QP_info_rem_qpn         |
 * |   28    |  [231:224]  |  ZERO_PADD               |
 * | [31:29] |  [255:232]  |  QP_info_rem_psn         |
 * |   32    |  [263:256]  |  ZERO_PADD               |
 * | [36:33] |  [295:264]  |  QP_info_rem_r_key       |
 * | [44:37] |  [359:296]  |  QP_info_rem_base_addr   |
 * | [48:45] |  [391:360]  |  QP_info_rem_ip_addr     |
 * | [50:49] |  [407:392]  |  QP_info_listening_port  |
 * +---------+-------------+--------------------------+
 * |   51    |  [408:408]  |  txmeta_valid            |
 * |   51    |  [409:409]  |  txmeta_start            |
 * |   51    |  [410:410]  |  txmeta_is_immediate     |
 * |   51    |  [411:411]  |  txmeta_tx_type          |
 * |   51    |  [415:412]  |  txmeta_reserved         |
 * | [55:52] |  [447:416]  |  txmeta_dma_length       |
 * | [59:56] |  [479:448]  |  txmeta_n_transfers      |
 * | [63:60] |  [511:480]  |  txmeta_frequency        |
 * +---------+-------------+--------------------------+
 * TOTAL length 512 bits, 64 bytes
 */

module udp_RoCE_connection_manager_rx #(
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
     * RoCE QP info
     */
    output wire        m_qp_info_valid,
    output wire [2 :0] m_qp_info_req_type,
    output wire        m_qp_info_ack_valid,
    output wire [2 :0] m_qp_info_ack_type,
    output wire [31:0] m_qp_info_loc_r_key,
    output wire [23:0] m_qp_info_loc_qpn,
    output wire [23:0] m_qp_info_loc_psn,
    output wire [31:0] m_qp_info_loc_ip_addr,
    output wire [63:0] m_qp_info_loc_base_addr,
    output wire [31:0] m_qp_info_rem_r_key,
    output wire [23:0] m_qp_info_rem_qpn,
    output wire [23:0] m_qp_info_rem_psn,
    output wire [31:0] m_qp_info_rem_ip_addr,
    output wire [63:0] m_qp_info_rem_base_addr,
    output wire [15:0] m_qp_info_listening_port,
    /*
     * TX meta parameters
     */
    output wire        m_metadata_valid,
    output wire        m_start_transfer,
    output wire [23:0] m_txmeta_loc_qpn,
    output wire [31:0] m_txmeta_dma_transfer,
    output wire [31:0] m_txmeta_n_transfers,
    output wire [31:0] m_txmeta_frequency,
    output wire        m_txmeta_is_immediate,
    output wire        m_txmeta_tx_type, // 0 SEND, 1 RDMA WRITE
    /*
     * Status signals
     */
    output wire busy
);

    parameter KEEP_ENABLE = 1;
    parameter KEEP_WIDTH  = DATA_WIDTH/8;

    parameter BYTE_LANES = KEEP_WIDTH;

    parameter QP_INFO_SIZE = 64;

    parameter CYCLE_COUNT = (QP_INFO_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

    parameter OFFSET = QP_INFO_SIZE % BYTE_LANES;


    reg [3:0] temp_4bits;
    reg [5:0] temp_6bits;
    reg [7:0] temp_zero_padd;

    reg read_qp_info_reg = 1'b1, read_qp_info_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    localparam [2:0] STATE_IDLE = 3'd0, STATE_READ_METADATA = 3'd1;

    reg [2:0] state_reg = STATE_IDLE, state_next;

    reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
    reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

    reg busy_reg = 1'b0;

    reg [15:0] udp_port_reg, udp_port_next;


    reg qp_info_valid_reg, qp_info_valid_next;
    reg [2 :0] qp_info_req_type_reg, qp_info_req_type_next;
    reg        qp_info_ack_valid_reg, qp_info_ack_valid_next;
    reg [2 :0] qp_info_ack_type_reg, qp_info_ack_type_next;
    reg [23:0] qp_info_loc_qpn_reg, qp_info_loc_qpn_next;
    reg [23:0] qp_info_loc_psn_reg, qp_info_loc_psn_next;
    reg [31:0] qp_info_loc_r_key_reg, qp_info_loc_r_key_next;
    reg [63:0] qp_info_loc_base_addr_reg, qp_info_loc_base_addr_next;
    reg [31:0] qp_info_loc_ip_addr_reg, qp_info_loc_ip_addr_next;
    reg [23:0] qp_info_rem_qpn_reg, qp_info_rem_qpn_next;
    reg [23:0] qp_info_rem_psn_reg, qp_info_rem_psn_next;
    reg [31:0] qp_info_rem_r_key_reg, qp_info_rem_r_key_next;
    reg [63:0] qp_info_rem_base_addr_reg, qp_info_rem_base_addr_next;
    reg [31:0] qp_info_rem_ip_addr_reg, qp_info_rem_ip_addr_next;
    reg [15:0] qp_info_listening_port_reg, qp_info_listening_port_next;

    reg txmeta_valid_reg, txmeta_valid_next;
    reg txmeta_start_reg, txmeta_start_next;
    reg [23:0] txmeta_loc_qpn_reg, txmeta_loc_qpn_next;
    reg txmeta_is_immediate_reg, txmeta_is_immediate_next;
    reg txmeta_tx_type_reg, txmeta_tx_type_next;
    reg [31:0] txmeta_n_transfers_reg, txmeta_n_transfers_next;
    reg [31:0] txmeta_dma_lentgh_reg, txmeta_dma_lentgh_next;
    reg [31:0] txmeta_frequency_reg, txmeta_frequency_next;

    reg m_qp_info_valid_reg, m_qp_info_valid_next;


    reg metadata_valid_reg, metadata_valid_next;

    assign s_udp_hdr_ready = s_udp_hdr_ready_reg;
    assign s_udp_payload_axis_tready = s_udp_payload_axis_tready_reg;

    assign busy = busy_reg;

    always @* begin

        state_next                     = STATE_IDLE;

        s_udp_hdr_ready_next           = 1'b0;
        s_udp_payload_axis_tready_next = 1'b0;

        metadata_valid_next            = metadata_valid_reg;
        qp_info_valid_next          = qp_info_valid_reg;
        txmeta_valid_next = txmeta_valid_reg;

        udp_port_next                  = udp_port_reg;

        ptr_next = ptr_reg;

        qp_info_valid_next             = qp_info_valid_reg;
        qp_info_req_type_next          = qp_info_req_type_reg;
        qp_info_ack_valid_next         = qp_info_ack_valid_reg;
        qp_info_ack_type_next          = qp_info_ack_type_reg;

        qp_info_loc_qpn_next           = qp_info_loc_qpn_reg;
        qp_info_loc_psn_next           = qp_info_loc_psn_reg;
        qp_info_loc_r_key_next         = qp_info_loc_r_key_reg;
        qp_info_loc_base_addr_next     = qp_info_loc_base_addr_reg;
        qp_info_loc_ip_addr_next       = qp_info_loc_ip_addr_reg;

        qp_info_rem_qpn_next           = qp_info_rem_qpn_reg;
        qp_info_rem_psn_next           = qp_info_rem_psn_reg;
        qp_info_rem_r_key_next         = qp_info_rem_r_key_reg;
        qp_info_rem_base_addr_next     = qp_info_rem_base_addr_reg;
        qp_info_rem_ip_addr_next       = qp_info_rem_ip_addr_reg;

        qp_info_listening_port_next    = qp_info_listening_port_reg;

        txmeta_valid_next              = txmeta_valid_reg;
        txmeta_start_next              = txmeta_start_reg;
        txmeta_loc_qpn_next            = txmeta_loc_qpn_reg;
        txmeta_is_immediate_next       = txmeta_is_immediate_reg;
        txmeta_tx_type_next            = txmeta_tx_type_reg;
        txmeta_dma_lentgh_next         = txmeta_dma_lentgh_reg;
        txmeta_n_transfers_next        = txmeta_n_transfers_reg;
        txmeta_frequency_next          = txmeta_frequency_reg;

        m_qp_info_valid_next  = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                metadata_valid_next    = 1'b0;
                qp_info_valid_next  = 1'b0;
                // idle state - wait for header
                s_udp_hdr_ready_next = !m_qp_info_valid_next;

                read_qp_info_next = read_qp_info_reg;
                ptr_next = ptr_reg;

                udp_port_next        = 16'd0;

                qp_info_valid_next   = qp_info_valid_reg;
                txmeta_valid_next    = 1'b0;
                txmeta_start_next    = 1'b0;

                if (s_udp_hdr_ready && s_udp_hdr_valid) begin
                    if (s_udp_dest_port == LISTEN_UDP_PORT && s_udp_length == (QP_INFO_SIZE + 16'd8)) begin
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

                    ptr_next = ptr_reg + 1; 

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_udp_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

                    `_HEADER_FIELD_(0 ,  {qp_info_ack_type_next, qp_info_ack_valid_next, qp_info_req_type_next, qp_info_valid_next})
                    `_HEADER_FIELD_(1 ,  qp_info_loc_qpn_next[0*8 +: 8])
                    `_HEADER_FIELD_(2 ,  qp_info_loc_qpn_next[1*8 +: 8])
                    `_HEADER_FIELD_(3 ,  qp_info_loc_qpn_next[2*8 +: 8])
                    //`_HEADER_FIELD_(4 ,  temp_zero_padd)
                    `_HEADER_FIELD_(5 ,  qp_info_loc_psn_next[0*8 +: 8])
                    `_HEADER_FIELD_(6 ,  qp_info_loc_psn_next[1*8 +: 8])
                    `_HEADER_FIELD_(7 ,  qp_info_loc_psn_next[2*8 +: 8])
                    //`_HEADER_FIELD_(8 ,  temp_zero_padd)
                    `_HEADER_FIELD_(9 ,  qp_info_loc_r_key_next[0*8 +: 8])
                    `_HEADER_FIELD_(10,  qp_info_loc_r_key_next[1*8 +: 8])
                    `_HEADER_FIELD_(11,  qp_info_loc_r_key_next[2*8 +: 8])
                    `_HEADER_FIELD_(12,  qp_info_loc_r_key_next[3*8 +: 8])
                    `_HEADER_FIELD_(13,  qp_info_loc_base_addr_next[0*8 +: 8])
                    `_HEADER_FIELD_(14,  qp_info_loc_base_addr_next[1*8 +: 8])
                    `_HEADER_FIELD_(15,  qp_info_loc_base_addr_next[2*8 +: 8])
                    `_HEADER_FIELD_(16,  qp_info_loc_base_addr_next[3*8 +: 8])
                    `_HEADER_FIELD_(17,  qp_info_loc_base_addr_next[4*8 +: 8])
                    `_HEADER_FIELD_(18,  qp_info_loc_base_addr_next[5*8 +: 8])
                    `_HEADER_FIELD_(19,  qp_info_loc_base_addr_next[6*8 +: 8])
                    `_HEADER_FIELD_(20,  qp_info_loc_base_addr_next[7*8 +: 8])
                    `_HEADER_FIELD_(21,  qp_info_loc_ip_addr_next[0*8 +: 8])
                    `_HEADER_FIELD_(22,  qp_info_loc_ip_addr_next[1*8 +: 8])
                    `_HEADER_FIELD_(23,  qp_info_loc_ip_addr_next[2*8 +: 8])
                    `_HEADER_FIELD_(24,  qp_info_loc_ip_addr_next[3*8 +: 8])

                    `_HEADER_FIELD_(25,  qp_info_rem_qpn_next[0*8 +: 8])
                    `_HEADER_FIELD_(26,  qp_info_rem_qpn_next[1*8 +: 8])
                    `_HEADER_FIELD_(27,  qp_info_rem_qpn_next[2*8 +: 8])
                    //`_HEADER_FIELD_(28 ,  temp_zero_padd)
                    `_HEADER_FIELD_(29,  qp_info_rem_psn_next[0*8 +: 8])
                    `_HEADER_FIELD_(30,  qp_info_rem_psn_next[1*8 +: 8])
                    `_HEADER_FIELD_(31,  qp_info_rem_psn_next[2*8 +: 8])
                    //`_HEADER_FIELD_(32 ,  temp_zero_padd)
                    `_HEADER_FIELD_(33,  qp_info_rem_r_key_next[0*8 +: 8])
                    `_HEADER_FIELD_(34,  qp_info_rem_r_key_next[1*8 +: 8])
                    `_HEADER_FIELD_(35,  qp_info_rem_r_key_next[2*8 +: 8])
                    `_HEADER_FIELD_(36,  qp_info_rem_r_key_next[3*8 +: 8])
                    `_HEADER_FIELD_(37,  qp_info_rem_base_addr_next[0*8 +: 8])
                    `_HEADER_FIELD_(38,  qp_info_rem_base_addr_next[1*8 +: 8])
                    `_HEADER_FIELD_(39,  qp_info_rem_base_addr_next[2*8 +: 8])
                    `_HEADER_FIELD_(40,  qp_info_rem_base_addr_next[3*8 +: 8])
                    `_HEADER_FIELD_(41,  qp_info_rem_base_addr_next[4*8 +: 8])
                    `_HEADER_FIELD_(42,  qp_info_rem_base_addr_next[5*8 +: 8])
                    `_HEADER_FIELD_(43,  qp_info_rem_base_addr_next[6*8 +: 8])
                    `_HEADER_FIELD_(44,  qp_info_rem_base_addr_next[7*8 +: 8])
                    `_HEADER_FIELD_(45,  qp_info_rem_ip_addr_next[0*8 +: 8])
                    `_HEADER_FIELD_(46,  qp_info_rem_ip_addr_next[1*8 +: 8])
                    `_HEADER_FIELD_(47,  qp_info_rem_ip_addr_next[2*8 +: 8])
                    `_HEADER_FIELD_(48,  qp_info_rem_ip_addr_next[3*8 +: 8])
                    `_HEADER_FIELD_(49,  qp_info_listening_port_next[0*8 +: 8])
                    `_HEADER_FIELD_(50,  qp_info_listening_port_next[1*8 +: 8])

                    `_HEADER_FIELD_(51,  {temp_4bits, txmeta_tx_type_next, txmeta_is_immediate_next, txmeta_start_next, txmeta_valid_next})
                    `_HEADER_FIELD_(52,  txmeta_dma_lentgh_next[0*8 +: 8])
                    `_HEADER_FIELD_(53,  txmeta_dma_lentgh_next[1*8 +: 8])
                    `_HEADER_FIELD_(54,  txmeta_dma_lentgh_next[2*8 +: 8])
                    `_HEADER_FIELD_(55,  txmeta_dma_lentgh_next[3*8 +: 8])
                    `_HEADER_FIELD_(56,  txmeta_n_transfers_next[0*8 +: 8])
                    `_HEADER_FIELD_(57,  txmeta_n_transfers_next[1*8 +: 8])
                    `_HEADER_FIELD_(58,  txmeta_n_transfers_next[2*8 +: 8])
                    `_HEADER_FIELD_(59,  txmeta_n_transfers_next[3*8 +: 8])
                    `_HEADER_FIELD_(60,  txmeta_frequency_next[0*8 +: 8])
                    `_HEADER_FIELD_(61,  txmeta_frequency_next[1*8 +: 8])
                    `_HEADER_FIELD_(62,  txmeta_frequency_next[2*8 +: 8])
                    `_HEADER_FIELD_(63,  txmeta_frequency_next[3*8 +: 8])

                    txmeta_loc_qpn_next = qp_info_rem_qpn_next;

                    if (ptr_reg == (QP_INFO_SIZE-1)/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[(QP_INFO_SIZE-1)%BYTE_LANES])) begin
                        if (s_udp_payload_axis_tlast) begin
                            metadata_valid_next   = txmeta_valid_next;
                            m_qp_info_valid_next = qp_info_valid_next;
                            read_qp_info_next = 1'b0;
                        end
                    end
          `undef _HEADER_FIELD_


                    if (s_udp_payload_axis_tlast) begin
                        //m_qp_info_valid_next = 1'b0;
                        s_udp_hdr_ready_next = !m_qp_info_valid_next;
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
            m_qp_info_valid_reg           <= 1'b0;
            busy_reg                      <= 1'b0;
            metadata_valid_reg            <= 1'b0;

        end else begin
            state_reg                     <= state_next;

            metadata_valid_reg            <= metadata_valid_next;
            m_qp_info_valid_reg           <= m_qp_info_valid_next;

            s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
            s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

            ptr_reg                       <= ptr_next;
            read_qp_info_reg           <= read_qp_info_next;

            udp_port_reg                  <= udp_port_next;

            qp_info_valid_reg          <= qp_info_valid_next;

            if (qp_info_valid_next) begin
                qp_info_req_type_reg      <= qp_info_req_type_next;

                qp_info_loc_qpn_reg       <= qp_info_loc_qpn_next;
                qp_info_loc_psn_reg       <= qp_info_loc_psn_next;
                qp_info_loc_r_key_reg     <= qp_info_loc_r_key_next;
                qp_info_loc_base_addr_reg <= qp_info_loc_base_addr_next;
                qp_info_loc_ip_addr_reg   <= qp_info_loc_ip_addr_next;

                qp_info_rem_qpn_reg       <= qp_info_rem_qpn_next;
                qp_info_rem_psn_reg       <= qp_info_rem_psn_next;
                qp_info_rem_r_key_reg     <= qp_info_rem_r_key_next;
                qp_info_rem_base_addr_reg <= qp_info_rem_base_addr_next;
                qp_info_rem_ip_addr_reg   <= qp_info_rem_ip_addr_next;

                qp_info_listening_port_reg   <= qp_info_listening_port_next;
            end

            if (qp_info_ack_valid_next) begin
                qp_info_ack_type_reg      <= qp_info_ack_type_next;
            end

            txmeta_valid_reg <= txmeta_valid_next;
            if (txmeta_valid_next) begin
                txmeta_start_reg           <= txmeta_start_next;
                txmeta_loc_qpn_reg         <= txmeta_loc_qpn_next;
                txmeta_is_immediate_reg    <= txmeta_is_immediate_next;
                txmeta_tx_type_reg         <= txmeta_tx_type_next;
                txmeta_dma_lentgh_reg      <= txmeta_dma_lentgh_next;
                txmeta_n_transfers_reg     <= txmeta_n_transfers_next;
                txmeta_frequency_reg       <= txmeta_frequency_next;
            end else begin
                txmeta_start_reg           <= 1'b0;
            end

            busy_reg <= state_next != STATE_IDLE;
        end


    end

    assign m_qp_info_req_type = qp_info_req_type_reg;
    assign m_qp_info_ack_type = qp_info_ack_type_reg;

    assign m_qp_info_loc_qpn        = qp_info_loc_qpn_reg;
    assign m_qp_info_loc_psn        = qp_info_loc_psn_reg;
    assign m_qp_info_loc_r_key      = qp_info_loc_r_key_reg;
    assign m_qp_info_loc_base_addr  = qp_info_loc_base_addr_reg;
    assign m_qp_info_loc_ip_addr    = qp_info_loc_ip_addr_reg;

    assign m_qp_info_rem_qpn        = qp_info_rem_qpn_reg;
    assign m_qp_info_rem_psn        = qp_info_rem_psn_reg;
    assign m_qp_info_rem_r_key      = qp_info_rem_r_key_reg;
    assign m_qp_info_rem_base_addr  = qp_info_rem_base_addr_reg;
    assign m_qp_info_rem_ip_addr    = qp_info_rem_ip_addr_reg;

    assign m_qp_info_listening_port = qp_info_listening_port_reg;

    assign m_txmeta_loc_qpn        = txmeta_loc_qpn_reg;
    assign m_txmeta_dma_transfer   = txmeta_dma_lentgh_reg & 32'hFFFFFFFC; // mask last two bits to have always multiple of 4
    assign m_txmeta_n_transfers    = txmeta_n_transfers_reg;
    assign m_txmeta_frequency      = txmeta_frequency_reg;
    assign m_txmeta_is_immediate   = txmeta_is_immediate_reg;
    assign m_txmeta_tx_type        = txmeta_tx_type_reg;

    assign m_start_transfer = txmeta_start_reg & metadata_valid_reg;

    assign m_metadata_valid = metadata_valid_reg;

    assign m_qp_info_valid     = m_qp_info_valid_reg;
    assign m_qp_info_ack_valid = qp_info_ack_valid_reg & m_qp_info_valid_reg;

endmodule

`resetall
