`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * Connection manager over UDP
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
 * |   1     |  [15 :8  ]  |  ZERO_PADD               |
 * | [4:2]   |  [39 :16 ]  |  QP_info_loc_qpn         |
 * |   5     |  [47 :40 ]  |  ZERO_PADD               |
 * | [8:6]   |  [71 :48 ]  |  QP_info_loc_psn         |
 * | [12:9]  |  [103 :72]  |  QP_info_loc_r_key       |
 * | [20:13] |  [167:104]  |  QP_info_loc_base_addr   |
 * | [24:21] |  [199:168]  |  QP_info_loc_ip_addr     |
 * |   25    |  [207:200]  |  ZERO_PADD               |
 * | [28:26] |  [231:208]  |  QP_info_rem_qpn         |
 * |   29    |  [239:232]  |  ZERO_PADD               |
 * | [32:30] |  [263:240]  |  QP_info_rem_psn         |
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

module udp_RoCE_connection_manager #(
    parameter DATA_WIDTH       = 256,
    parameter MODULE_DIRECTION = "Slave", // Slave or Master 
    parameter MASTER_TIMEOUT   = 200 // with 5ns clock it is equivalent to 10 ms 
    // Master:
    // The FPGA's CM will request QP parameters from the client
    // Operation will be triggered by a signal in this module (through slow control maybe)
    // Slave
    // The FPGA's CM will reply to the client requests with it's own QP parameters
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
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    input  wire         m_udp_hdr_ready,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [ 15:0] m_udp_source_port,
    output wire [ 15:0] m_udp_dest_port,
    output wire [ 15:0] m_udp_length,
    output wire [ 15:0] m_udp_checksum,
    output wire [DATA_WIDTH-1   : 0] m_udp_payload_axis_tdata,
    output wire [DATA_WIDTH/8-1 : 0] m_udp_payload_axis_tkeep,
    output wire         m_udp_payload_axis_tvalid,
    input  wire         m_udp_payload_axis_tready,
    output wire         m_udp_payload_axis_tlast,
    output wire         m_udp_payload_axis_tuser,
    /*
     * QP state table interface
     */
    output wire        cm_qp_valid,
    output wire [2:0 ] cm_qp_req_type,
    output wire [31:0] cm_qp_r_key,
    output wire [23:0] cm_qp_rem_qpn,
    output wire [23:0] cm_qp_loc_qpn,
    output wire [23:0] cm_qp_rem_psn,
    output wire [23:0] cm_qp_loc_psn,
    output wire [31:0] cm_qp_rem_ip_addr,
    output wire [63:0] cm_qp_rem_base_addr,

    input wire        cm_qp_status_valid,
    input wire [1 :0] cm_qp_status,
    input wire [2 :0] cm_qp_status_state,
    input wire [31:0] cm_qp_status_r_key,
    input wire [23:0] cm_qp_status_rem_qpn,
    input wire [23:0] cm_qp_status_loc_qpn,
    input wire [23:0] cm_qp_status_rem_psn,
    input wire [23:0] cm_qp_status_loc_psn,
    input wire [31:0] cm_qp_status_rem_ip_addr,
    input wire [63:0] cm_qp_status_rem_addr,

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

    // Commands (used only as Master)
    input wire        cm_qp_master_req_valid,
    input wire [2:0]  cm_qp_master_req_type,
    input wire [23:0] cm_qp_master_req_loc_qpn,
    input wire [31:0] cm_qp_master_req_rem_ip_addr,
    // Output errors here if any
    output wire        cm_qp_master_status_valid,
    output wire [2:0]  cm_qp_master_status,
    output wire [23:0] cm_qp_master_status_loc_qpn,
    /*
     * Configuration
     */
    input wire [15:0] cfg_udp_source_port,
    input wire [31:0] cfg_loc_ip_addr
);

    import RoCE_params::*; // Imports RoCE parameters


    wire        m_qp_info_valid;
    wire [2 :0] m_qp_info_req_type;
    wire        m_qp_info_ack_valid;
    wire [2 :0] m_qp_info_ack_type;
    wire [31:0] m_qp_info_loc_r_key;
    wire [23:0] m_qp_info_loc_qpn;
    wire [23:0] m_qp_info_loc_psn;
    wire [31:0] m_qp_info_loc_ip_addr;
    wire [63:0] m_qp_info_loc_base_addr;
    wire [31:0] m_qp_info_rem_r_key;
    wire [23:0] m_qp_info_rem_qpn;
    wire [23:0] m_qp_info_rem_psn;
    wire [31:0] m_qp_info_rem_ip_addr;
    wire [63:0] m_qp_info_rem_base_addr;
    wire [15:0] m_qp_info_listening_port;

    wire        s_qp_info_valid;
    wire        s_qp_info_ready;
    wire [2 :0] s_qp_info_req_type;
    wire        s_qp_info_ack_valid;
    wire [2 :0] s_qp_info_ack_type;
    wire [31:0] s_qp_info_loc_r_key;
    wire [23:0] s_qp_info_loc_qpn;
    wire [23:0] s_qp_info_loc_psn;
    wire [31:0] s_qp_info_loc_ip_addr;
    wire [63:0] s_qp_info_loc_base_addr;
    wire [31:0] s_qp_info_rem_r_key;
    wire [23:0] s_qp_info_rem_qpn;
    wire [23:0] s_qp_info_rem_psn;
    wire [31:0] s_qp_info_rem_ip_addr;
    wire [63:0] s_qp_info_rem_base_addr;

    wire [15:0] s_qp_info_udp_dest_port;

    wire [15:0] udp_dest_port;


    reg qp_info_valid_reg, qp_info_valid_next;
    reg [2:0] qp_info_req_type_reg, qp_info_req_type_next;
    reg qp_info_ack_valid_reg, qp_info_ack_valid_next;
    reg [2:0] qp_info_ack_type_reg, qp_info_ack_type_next;

    reg [31:0] qp_info_loc_r_key_reg  , qp_info_loc_r_key_next;
    reg [31:0] qp_info_loc_qpn_reg    , qp_info_loc_qpn_next;
    reg [31:0] qp_info_loc_psn_reg    , qp_info_loc_psn_next;
    reg [31:0] qp_info_loc_ip_addr_reg, qp_info_loc_ip_addr_next;
    reg [63:0] qp_info_loc_base_addr_reg   , qp_info_loc_base_addr_next;

    reg [31:0] qp_info_rem_r_key_reg  , qp_info_rem_r_key_next;
    reg [31:0] qp_info_rem_qpn_reg    , qp_info_rem_qpn_next;
    reg [31:0] qp_info_rem_psn_reg    , qp_info_rem_psn_next;
    reg [31:0] qp_info_rem_ip_addr_reg, qp_info_rem_ip_addr_next;
    reg [63:0] qp_info_rem_base_addr_reg   , qp_info_rem_base_addr_next;

    reg [15:0] qp_info_udp_dest_port_reg   , qp_info_udp_dest_port_next;

    reg [15:0] udp_dest_port_reg   , udp_dest_port_next;

    reg cm_qp_valid_reg, cm_qp_valid_next;

    reg [2 :0] cm_qp_req_type_reg, cm_qp_req_type_next;
    reg [31:0] cm_qp_r_key_reg, cm_qp_r_key_next;
    reg [23:0] cm_qp_rem_qpn_reg, cm_qp_rem_qpn_next;
    reg [23:0] cm_qp_loc_qpn_reg, cm_qp_loc_qpn_next;
    reg [23:0] cm_qp_rem_psn_reg, cm_qp_rem_psn_next;
    reg [23:0] cm_qp_loc_psn_reg, cm_qp_loc_psn_next;
    reg [31:0] cm_qp_rem_ip_addr_reg, cm_qp_rem_ip_addr_next;
    reg [63:0] cm_qp_rem_base_addr_reg, cm_qp_rem_base_addr_next;

    reg qp_close_req_reg, qp_close_req_next;

    reg s_qpn_fifo_valid_reg, s_qpn_fifo_valid_next;
    reg s_qpn_fifo_ready_reg, s_qpn_fifo_ready_next;
    reg m_qpn_fifo_valid_reg, m_qpn_fifo_valid_next;
    reg m_qpn_fifo_ready_reg, m_qpn_fifo_ready_next;

    wire s_qpn_fifo_valid, s_qpn_fifo_ready;
    wire m_qpn_fifo_valid, m_qpn_fifo_ready;

    reg [23:0] s_qpn_reg, s_qpn_next;


    wire [23:0] s_qpn;
    wire [23:0] m_qpn;

    wire busy_rx, busy_tx;

    assign s_qpn_fifo_valid = s_qpn_fifo_valid_reg;
    assign m_qpn_fifo_ready = m_qpn_fifo_ready_reg;

    assign s_qpn = s_qpn_reg;


    udp_RoCE_connection_manager_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .LISTEN_UDP_PORT(CM_LISTEN_UDP_PORT)
    ) udp_RoCE_connection_manager_rx_instance (
        .clk(clk),
        .rst(rst),
        .s_udp_hdr_valid(s_udp_hdr_valid),
        .s_udp_hdr_ready(s_udp_hdr_ready),
        .s_udp_source_port(s_udp_source_port),
        .s_udp_dest_port(s_udp_dest_port),
        .s_udp_length(s_udp_length),
        .s_udp_checksum(s_udp_checksum),

        .s_udp_payload_axis_tdata(s_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep(s_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(s_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready(s_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast(s_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser(s_udp_payload_axis_tuser),

        .m_qp_info_valid    (m_qp_info_valid),
        .m_qp_info_req_type (m_qp_info_req_type),
        .m_qp_info_ack_valid(m_qp_info_ack_valid),
        .m_qp_info_ack_type (m_qp_info_ack_type),

        .m_qp_info_loc_r_key    (m_qp_info_loc_r_key),
        .m_qp_info_loc_qpn      (m_qp_info_loc_qpn),
        .m_qp_info_loc_psn      (m_qp_info_loc_psn),
        .m_qp_info_loc_ip_addr  (m_qp_info_loc_ip_addr),
        .m_qp_info_loc_base_addr(m_qp_info_loc_base_addr),

        .m_qp_info_rem_r_key    (m_qp_info_rem_r_key),
        .m_qp_info_rem_qpn      (m_qp_info_rem_qpn),
        .m_qp_info_rem_psn      (m_qp_info_rem_psn),
        .m_qp_info_rem_ip_addr  (m_qp_info_rem_ip_addr),
        .m_qp_info_rem_base_addr(m_qp_info_rem_base_addr),

        .m_qp_info_listening_port(m_qp_info_listening_port),

        .m_metadata_valid     (m_metadata_valid),
        .m_start_transfer     (m_start_transfer),
        .m_txmeta_loc_qpn     (m_txmeta_loc_qpn),
        .m_txmeta_dma_transfer(m_txmeta_dma_transfer),
        .m_txmeta_n_transfers (m_txmeta_n_transfers),
        .m_txmeta_frequency   (m_txmeta_frequency),
        .m_txmeta_is_immediate(m_txmeta_is_immediate),
        .m_txmeta_tx_type     (m_txmeta_tx_type),

        .busy(busy_rx)
    );


    udp_RoCE_connection_manager_tx #(
        .DATA_WIDTH     (DATA_WIDTH),
        .DEST_UDP_PORT  (CM_DEST_UDP_PORT),
        .LISTEN_UDP_PORT(CM_LISTEN_UDP_PORT)
    ) udp_RoCE_connection_manager_tx_instance (
        .clk(clk),
        .rst(rst),
        .s_qp_info_valid        (s_qp_info_valid),
        .s_qp_info_ready        (s_qp_info_ready),

        .s_qp_info_req_type     (s_qp_info_req_type),
        .s_qp_info_ack_valid    (s_qp_info_ack_valid),
        .s_qp_info_ack_type     (s_qp_info_ack_type),
        .s_qp_info_loc_qpn      (s_qp_info_loc_qpn),
        .s_qp_info_loc_psn      (s_qp_info_loc_psn),
        .s_qp_info_loc_r_key    (s_qp_info_loc_r_key),
        .s_qp_info_loc_ip_addr  (s_qp_info_loc_ip_addr),
        .s_qp_info_loc_base_addr(s_qp_info_loc_base_addr),

        .s_qp_info_rem_qpn      (s_qp_info_rem_qpn),
        .s_qp_info_rem_psn      (s_qp_info_rem_psn),
        .s_qp_info_rem_r_key    (s_qp_info_rem_r_key),
        .s_qp_info_rem_ip_addr  (s_qp_info_rem_ip_addr),
        .s_qp_info_rem_base_addr(s_qp_info_rem_base_addr),

        .s_qp_info_udp_dest_port(s_qp_info_udp_dest_port),

        .s_udp_dest_port        (udp_dest_port),

        .m_udp_hdr_valid  (m_udp_hdr_valid),
        .m_udp_hdr_ready  (m_udp_hdr_ready),
        .m_ip_source_ip   (m_ip_source_ip),
        .m_ip_dest_ip     (m_ip_dest_ip),
        .m_udp_source_port(m_udp_source_port),
        .m_udp_dest_port  (m_udp_dest_port),
        .m_udp_length     (m_udp_length),
        .m_udp_checksum   (m_udp_checksum),

        .m_udp_payload_axis_tdata (m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast (m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser (m_udp_payload_axis_tuser),
        .busy(busy_tx),

        .cfg_udp_source_port(cfg_udp_source_port)
    );


    qpn_fifo_init #(
        .MAX_QUEUE_PAIRS_FIFO(MAX_QUEUE_PAIRS),
        .BASE_QPN_FIFO(256)
    ) qpn_fifo_init_instance (
        .clk(clk),
        .rst(rst),
        .s_qpn_fifo_valid(s_qpn_fifo_valid),
        .s_qpn_fifo_ready(s_qpn_fifo_ready),
        .s_qpn           (s_qpn),
        .m_qpn_fifo_valid(m_qpn_fifo_valid),
        .m_qpn_fifo_ready(m_qpn_fifo_ready),
        .m_qpn           (m_qpn)
    );

    generate
        if (MODULE_DIRECTION == "Slave") begin

            localparam [2:0]
            STATE_IDLE       = 3'd0,
            STATE_MODIFY_QP  = 3'd1,
            STATE_SEND_ERROR = 3'd2;

            reg [2:0] state_reg = STATE_IDLE, state_next;

            always @* begin

                m_qpn_fifo_ready_next = 1'b0;
                s_qpn_fifo_valid_next = 1'b0;

                qp_close_req_next = 1'b0;

                s_qpn_next = s_qpn_reg;

                qp_info_valid_next     = qp_info_valid_reg && !s_qp_info_ready;
                qp_info_ack_valid_next = qp_info_ack_valid_reg && (qp_info_valid_reg && !s_qp_info_ready);

                qp_info_req_type_next       = qp_info_req_type_reg;
                qp_info_ack_type_next       = qp_info_ack_type_reg;
                qp_info_loc_r_key_next      = qp_info_loc_r_key_reg;
                qp_info_loc_qpn_next        = qp_info_loc_qpn_reg;
                qp_info_loc_psn_next        = qp_info_loc_psn_reg;
                qp_info_loc_ip_addr_next    = qp_info_loc_ip_addr_reg;
                qp_info_loc_base_addr_next  = qp_info_loc_base_addr_reg;
                qp_info_rem_r_key_next      = qp_info_rem_r_key_reg;
                qp_info_rem_qpn_next        = qp_info_rem_qpn_reg;
                qp_info_rem_psn_next        = qp_info_rem_psn_reg;
                qp_info_rem_ip_addr_next    = qp_info_rem_ip_addr_reg;
                qp_info_rem_base_addr_next  = qp_info_rem_base_addr_reg;

                qp_info_udp_dest_port_next = qp_info_udp_dest_port_reg;

                udp_dest_port_next          = udp_dest_port_reg;

                cm_qp_valid_next = 1'b0;

                cm_qp_req_type_next    = cm_qp_req_type_reg;
                cm_qp_r_key_next       = cm_qp_r_key_reg;
                cm_qp_rem_qpn_next     = cm_qp_rem_qpn_reg;
                cm_qp_loc_qpn_next     = cm_qp_loc_qpn_reg;
                cm_qp_rem_psn_next     = cm_qp_rem_psn_reg;
                cm_qp_loc_psn_next     = cm_qp_loc_psn_reg;
                cm_qp_rem_ip_addr_next = cm_qp_rem_ip_addr_reg;
                cm_qp_rem_base_addr_next    = cm_qp_rem_base_addr_reg;

                state_next = STATE_IDLE;

                case (state_reg)
                    STATE_IDLE: begin
                        if (m_qp_info_valid) begin
                            case(m_qp_info_req_type)
                                REQ_OPEN_QP: begin

                                    if (m_qpn_fifo_valid) begin // QP available
                                        m_qpn_fifo_ready_next = 1'b1;

                                        qp_info_req_type_next = REQ_OPEN_QP;
                                        // Swap loc with rem
                                        qp_info_loc_r_key_next     = 32'd0;
                                        qp_info_loc_qpn_next       = m_qpn;
                                        qp_info_loc_psn_next       = 24'd0;
                                        qp_info_loc_ip_addr_next   = cfg_loc_ip_addr;
                                        qp_info_loc_base_addr_next = 64'd0;

                                        qp_info_rem_r_key_next      = m_qp_info_loc_r_key;
                                        qp_info_rem_qpn_next        = m_qp_info_loc_qpn;
                                        qp_info_rem_psn_next        = m_qp_info_loc_psn;
                                        qp_info_rem_ip_addr_next    = m_qp_info_loc_ip_addr;
                                        qp_info_rem_base_addr_next  = m_qp_info_loc_base_addr;
                                        qp_info_udp_dest_port_next  = m_qp_info_listening_port;

                                        udp_dest_port_next           = m_qp_info_listening_port;

                                        cm_qp_valid_next = 1'b1;

                                        cm_qp_req_type_next      = REQ_OPEN_QP;
                                        cm_qp_r_key_next         = m_qp_info_loc_r_key;
                                        cm_qp_rem_qpn_next       = m_qp_info_loc_qpn;
                                        cm_qp_loc_qpn_next       = m_qpn;
                                        cm_qp_rem_psn_next       = m_qp_info_loc_psn;
                                        cm_qp_loc_psn_next       = 24'd0;
                                        cm_qp_rem_ip_addr_next   = m_qp_info_loc_ip_addr;
                                        cm_qp_rem_base_addr_next = m_qp_info_loc_base_addr;

                                        state_next = STATE_MODIFY_QP;
                                    end else begin
                                        // Failed to open qp
                                        qp_info_ack_type_next = ACK_NO_QP;
                                        state_next = STATE_SEND_ERROR;
                                    end
                                end
                                REQ_MODIFY_QP_RTS: begin

                                    qp_info_req_type_next = REQ_MODIFY_QP_RTS;
                                    // Swap loc with rem
                                    qp_info_loc_r_key_next     = m_qp_info_rem_r_key;
                                    qp_info_loc_qpn_next       = m_qp_info_rem_qpn;
                                    qp_info_loc_psn_next       = m_qp_info_rem_psn;
                                    qp_info_loc_ip_addr_next   = cfg_loc_ip_addr;
                                    qp_info_loc_base_addr_next = m_qp_info_rem_base_addr;

                                    qp_info_rem_r_key_next     = m_qp_info_loc_r_key;
                                    qp_info_rem_qpn_next       = m_qp_info_loc_qpn;
                                    qp_info_rem_psn_next       = m_qp_info_loc_psn;
                                    qp_info_rem_ip_addr_next   = m_qp_info_loc_ip_addr;
                                    qp_info_rem_base_addr_next = m_qp_info_loc_base_addr;

                                    qp_info_udp_dest_port_next = m_qp_info_listening_port;

                                    udp_dest_port_next           = m_qp_info_listening_port;

                                    cm_qp_valid_next = 1'b1;

                                    cm_qp_req_type_next    = REQ_MODIFY_QP_RTS;
                                    cm_qp_r_key_next       = m_qp_info_loc_r_key;
                                    cm_qp_rem_qpn_next     = m_qp_info_loc_qpn;
                                    cm_qp_loc_qpn_next     = m_qp_info_rem_qpn;
                                    cm_qp_rem_psn_next     = m_qp_info_loc_psn;
                                    cm_qp_loc_psn_next     = m_qp_info_rem_psn;
                                    cm_qp_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                                    cm_qp_rem_base_addr_next    = m_qp_info_loc_base_addr;

                                    state_next = STATE_MODIFY_QP;
                                end
                                REQ_CLOSE_QP: begin

                                    if ((m_qp_info_rem_qpn[23:8] == 16'd1 && m_qp_info_rem_qpn[7:MAX_QUEUE_PAIRS_WIDTH] == 0)) begin
                                        //  QP goes to error state, some errors occoured during transfer (e.g. transmission timeout)

                                        qp_close_req_next = 1'b1;

                                        qp_info_req_type_next = REQ_CLOSE_QP;
                                        // Swap loc with rem
                                        qp_info_loc_r_key_next     = m_qp_info_rem_r_key;
                                        qp_info_loc_qpn_next       = m_qp_info_rem_qpn;
                                        qp_info_loc_psn_next       = m_qp_info_rem_psn;
                                        qp_info_loc_ip_addr_next   = cfg_loc_ip_addr;
                                        qp_info_loc_base_addr_next = m_qp_info_rem_base_addr;

                                        qp_info_rem_r_key_next     = m_qp_info_loc_r_key;
                                        qp_info_rem_qpn_next       = m_qp_info_loc_qpn;
                                        qp_info_rem_psn_next       = m_qp_info_loc_psn;
                                        qp_info_rem_ip_addr_next   = m_qp_info_loc_ip_addr;
                                        qp_info_rem_base_addr_next = m_qp_info_loc_base_addr;

                                        qp_info_udp_dest_port_next = m_qp_info_listening_port;

                                        udp_dest_port_next           = m_qp_info_listening_port;

                                        cm_qp_valid_next = 1'b1;

                                        cm_qp_req_type_next    = REQ_CLOSE_QP;
                                        cm_qp_r_key_next       = m_qp_info_loc_r_key;
                                        cm_qp_rem_qpn_next     = m_qp_info_loc_qpn;
                                        cm_qp_loc_qpn_next     = m_qp_info_rem_qpn;
                                        cm_qp_rem_psn_next     = m_qp_info_loc_psn;
                                        cm_qp_loc_psn_next     = m_qp_info_rem_psn;
                                        cm_qp_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                                        cm_qp_rem_base_addr_next    = m_qp_info_loc_base_addr;

                                        state_next = STATE_MODIFY_QP;
                                    end else begin
                                        // Try to close a QP that is not in the suitable range
                                        qp_info_ack_type_next = ACK_NAK;
                                        state_next = STATE_SEND_ERROR;
                                    end
                                end
                                default: begin
                                    qp_info_valid_next     = 1'b0;
                                    qp_info_ack_valid_next = 1'b0;
                                    qp_info_req_type_next = REQ_NULL;
                                    qp_info_ack_type_next = ACK_NULL;
                                end
                            endcase
                        end
                    end
                    STATE_MODIFY_QP: begin
                        qp_close_req_next = qp_close_req_reg;
                        if (cm_qp_status_valid) begin
                            if (cm_qp_status == 2'b00) begin
                                qp_info_valid_next     = 1'b1;
                                qp_info_ack_valid_next = 1'b1;
                                qp_info_ack_type_next = ACK_ACK;
                                if (qp_close_req_reg && s_qpn_fifo_ready) begin
                                    // succesfully closed QP
                                    s_qpn_next = cm_qp_loc_qpn_reg;
                                    s_qpn_fifo_valid_next = 1'b1;
                                    state_next = STATE_IDLE;
                                end else if (qp_close_req_reg && ~s_qpn_fifo_ready)  begin
                                    // Falied to close QP
                                    qp_info_valid_next     = 1'b0;
                                    qp_info_ack_valid_next = 1'b0;
                                    qp_info_ack_type_next = ACK_ERROR;
                                    state_next = STATE_SEND_ERROR;
                                end else if (~qp_close_req_reg) begin
                                    state_next = STATE_IDLE;
                                end
                            end else begin
                                // Failed to open/modify, QP in the wrong state
                                qp_info_valid_next     = 1'b0;
                                qp_info_ack_valid_next = 1'b0;
                                qp_info_ack_type_next = ACK_ERROR;
                                state_next = STATE_SEND_ERROR;
                            end
                        end else begin
                            state_next = STATE_MODIFY_QP;
                        end
                    end
                    STATE_SEND_ERROR: begin
                        qp_info_valid_next      = 1'b1;
                        qp_info_ack_valid_next  = 1'b1;

                        state_next = STATE_IDLE;
                    end
                endcase
            end

            always @(posedge clk) begin
                if (rst)begin

                    state_reg <= STATE_IDLE;

                end else begin
                    state_reg <= state_next;
                end
            end

            assign cm_qp_master_status_valid   = 1'b0;
            assign cm_qp_master_status         = 3'd0;
            assign cm_qp_master_status_loc_qpn = 24'd0;

        end else if (MODULE_DIRECTION == "Master") begin

            localparam [3:0]
            STATE_IDLE             = 4'd0,
            STATE_WAIT_REM_RPY     = 4'd1,
            STATE_MODIFY_QP        = 4'd2,
            STATE_CLOSE_QP         = 4'd3,
            STATE_FETCH_QP_CONTEXT = 4'd4;

            reg [2:0] state_reg = STATE_IDLE, state_next;

            reg       cm_qp_master_req_valid_reg;
            reg [2:0] cm_qp_master_req_type_reg;

            reg        cm_qp_master_status_valid_next, cm_qp_master_status_valid_reg = 1'b0;
            reg [2:0]  cm_qp_master_status_next, cm_qp_master_status_reg = 3'd0;
            reg [23:0] cm_qp_master_status_loc_qpn_next, cm_qp_master_status_loc_qpn_reg = 24'd0;

            reg [$clog2(MASTER_TIMEOUT):0] cm_timout_counter;
            reg cm_timout_retry_next, cm_timout_retry_reg; // only one retry
            reg cm_timout_retry_reg_del;

            always @* begin

                m_qpn_fifo_ready_next = 1'b0;
                s_qpn_fifo_valid_next = 1'b0;

                qp_close_req_next = 1'b0;

                s_qpn_next = s_qpn_reg;

                cm_qp_master_status_valid_next   = 1'b0;
                cm_qp_master_status_next         = 'd0;
                cm_qp_master_status_loc_qpn_next = cm_qp_master_status_loc_qpn_reg;
                cm_timout_retry_next     =   cm_timout_retry_reg;

                qp_info_valid_next     = qp_info_valid_reg && !s_qp_info_ready;
                qp_info_ack_valid_next = qp_info_ack_valid_reg && (qp_info_valid_reg && !s_qp_info_ready);

                qp_info_req_type_next         = qp_info_req_type_reg;
                qp_info_ack_type_next         = qp_info_ack_type_reg;
                qp_info_loc_r_key_next        = qp_info_loc_r_key_reg;
                qp_info_loc_qpn_next          = qp_info_loc_qpn_reg;
                qp_info_loc_psn_next          = qp_info_loc_psn_reg;
                qp_info_loc_ip_addr_next      = qp_info_loc_ip_addr_reg;
                qp_info_loc_base_addr_next    = qp_info_loc_base_addr_reg;
                qp_info_rem_r_key_next        = qp_info_rem_r_key_reg;
                qp_info_rem_qpn_next          = qp_info_rem_qpn_reg;
                qp_info_rem_psn_next          = qp_info_rem_psn_reg;
                qp_info_rem_ip_addr_next      = qp_info_rem_ip_addr_reg;
                qp_info_rem_base_addr_next    = qp_info_rem_base_addr_reg;

                qp_info_udp_dest_port_next = qp_info_udp_dest_port_reg;

                udp_dest_port_next         = udp_dest_port_reg;

                cm_qp_valid_next = 1'b0;

                cm_qp_req_type_next         = cm_qp_req_type_reg;
                cm_qp_r_key_next            = cm_qp_r_key_reg;
                cm_qp_rem_qpn_next          = cm_qp_rem_qpn_reg;
                cm_qp_loc_qpn_next          = cm_qp_loc_qpn_reg;
                cm_qp_rem_psn_next          = cm_qp_rem_psn_reg;
                cm_qp_loc_psn_next          = cm_qp_loc_psn_reg;
                cm_qp_rem_ip_addr_next      = cm_qp_rem_ip_addr_reg;
                cm_qp_rem_base_addr_next    = cm_qp_rem_base_addr_reg;

                state_next = STATE_IDLE;

                case (state_reg)
                    STATE_IDLE: begin
                        cm_timout_retry_next     = 1'b0;
                        if (cm_qp_master_req_valid && !cm_qp_master_req_valid_reg) begin //rising edge
                            case(cm_qp_master_req_type)
                                REQ_OPEN_QP: begin
                                    if (m_qpn_fifo_valid) begin // QP available
                                        m_qpn_fifo_ready_next = 1'b1;
                                        $display("[%t] FETCHING QPN FROM THE POOL, (%0d)\n", $time, m_qpn);
                                        // send local values
                                        qp_info_valid_next     = 1'b1;

                                        qp_info_req_type_next = REQ_OPEN_QP;
                                        // Swap loc with rem
                                        qp_info_loc_r_key_next     = 32'd0;
                                        qp_info_loc_qpn_next       = m_qpn;
                                        qp_info_loc_psn_next       = 24'd0;
                                        qp_info_loc_ip_addr_next   = cfg_loc_ip_addr;
                                        qp_info_loc_base_addr_next = 64'd0;

                                        qp_info_rem_r_key_next      = 32'd0;
                                        qp_info_rem_qpn_next        = 24'd0;
                                        qp_info_rem_psn_next        = 24'd0;
                                        qp_info_rem_ip_addr_next    = cm_qp_master_req_rem_ip_addr;
                                        qp_info_rem_base_addr_next  = 64'd0;
                                        qp_info_udp_dest_port_next  = 0;

                                        state_next = STATE_WAIT_REM_RPY;
                                    end else begin
                                        // Failed to fetch a local qpn
                                        cm_qp_master_status_valid_next   = 1'b1;
                                        cm_qp_master_status_next         = CM_ERROR_NO_LOC_QP;
                                        cm_qp_master_status_loc_qpn_next = 24'd0; // not relevant

                                        state_next = STATE_IDLE;
                                    end
                                end
                                REQ_MODIFY_QP_RTS: begin // do nothing for now
                                    qp_info_valid_next     = 1'b0;
                                    state_next             = STATE_IDLE;
                                end
                                REQ_CLOSE_QP: begin
                                    // close local qp
                                    if ((cm_qp_master_req_loc_qpn[23:8] == 16'd1 && cm_qp_master_req_loc_qpn[7:MAX_QUEUE_PAIRS_WIDTH] == 0)) begin
                                        cm_qp_valid_next = 1'b1;
                                        // fetch QP parameters from table
                                        cm_qp_req_type_next         = REQ_FETCH_QP_INFO;
                                        cm_qp_r_key_next            = 32'd0;
                                        cm_qp_rem_qpn_next          = 24'd0;
                                        cm_qp_loc_qpn_next          = cm_qp_master_req_loc_qpn;
                                        cm_qp_rem_psn_next          = 24'd0;
                                        cm_qp_loc_psn_next          = 24'd0;
                                        cm_qp_rem_ip_addr_next      = 32'd0; // ip address will be fetched form qp state table
                                        cm_qp_rem_base_addr_next    = 64'd0;

                                        state_next = STATE_FETCH_QP_CONTEXT;
                                    end
                                end
                                default: begin
                                    qp_info_valid_next     = 1'b0;
                                    state_next             = STATE_IDLE;
                                end
                            endcase
                        end
                    end
                    STATE_FETCH_QP_CONTEXT: begin
                        if (cm_qp_status_valid) begin
                            if (cm_qp_status == 2'b00) begin // no errors 
                            // send local and remote values (only the needed ones)
                                qp_info_valid_next     = 1'b1;

                                qp_info_req_type_next = cm_qp_master_req_type_reg; // now send the request

                                qp_info_loc_r_key_next     = 32'd0;
                                qp_info_loc_qpn_next       = cm_qp_loc_qpn_reg;
                                qp_info_loc_psn_next       = 24'd0;
                                qp_info_loc_ip_addr_next   = cfg_loc_ip_addr;
                                qp_info_loc_base_addr_next = 64'd0;

                                qp_info_rem_r_key_next      = 32'd0;
                                qp_info_rem_qpn_next        = cm_qp_status_rem_qpn;
                                qp_info_rem_psn_next        = 24'd0;
                                qp_info_rem_ip_addr_next    = cm_qp_status_rem_ip_addr;
                                qp_info_rem_base_addr_next  = 64'd0;
                                qp_info_udp_dest_port_next  = 0;

                                state_next = STATE_WAIT_REM_RPY;
                            end else begin //error accoured
                            // Failed to fetch a local qpn
                                cm_qp_master_status_valid_next   = 1'b1;
                                cm_qp_master_status_next         = CM_ERROR_FETCH_QP;
                                cm_qp_master_status_loc_qpn_next = cm_qp_loc_qpn_reg;

                                state_next = STATE_IDLE;
                            end
                        end else begin
                            state_next = STATE_FETCH_QP_CONTEXT;
                        end
                    end
                    STATE_WAIT_REM_RPY: begin
                        if (cm_timout_counter > 0) begin
                            if (m_qp_info_valid && m_qp_info_loc_ip_addr == qp_info_rem_ip_addr_reg) begin // got a reply from the server
                                if (m_qp_info_ack_valid && (m_qp_info_ack_type == ACK_ACK || m_qp_info_ack_type == ACK_NO_QP)) begin // server ack'ed the request or close qp request, but no qp is present on the receiver (server) side
                                    
                                    cm_qp_valid_next = 1'b1;
                                    // store remote qp parameters into table (and change local qp according to the request made)
                                    // swap loc with rem
                                    cm_qp_req_type_next         = m_qp_info_req_type; // now send the request to the QP state table
                                    cm_qp_r_key_next            = m_qp_info_loc_r_key;
                                    cm_qp_rem_qpn_next          = m_qp_info_loc_qpn;
                                    cm_qp_loc_qpn_next          = m_qp_info_rem_qpn;
                                    cm_qp_rem_psn_next          = m_qp_info_loc_psn;
                                    cm_qp_loc_psn_next          = m_qp_info_rem_psn;
                                    cm_qp_rem_ip_addr_next      = m_qp_info_loc_ip_addr;
                                    cm_qp_rem_base_addr_next    = m_qp_info_loc_base_addr;

                                    state_next = STATE_MODIFY_QP;
                                end else begin // server didn't send a proper ack packet
                                    case(qp_info_req_type_reg)
                                        REQ_OPEN_QP:begin // put back the loc qpn to the avaiable ones
                                            if (s_qpn_fifo_ready) begin // put QPN back to the pool
                                                s_qpn_next = qp_info_loc_qpn_reg;
                                                $display("[%t] GOT BAD ACK REPLY, put QPN (%0d) back to the pool\n", $time, qp_info_loc_qpn_reg);
                                                state_next = STATE_IDLE;
                                            end else begin
                                                //error
                                                state_next = STATE_IDLE;
                                            end
                                        end
                                        REQ_CLOSE_QP: begin
                                            //error
                                            state_next = STATE_IDLE;
                                        end
                                        default: begin
                                            //error
                                            state_next = STATE_IDLE;
                                        end
                                    endcase
                                end
                            end else begin
                                state_next = STATE_WAIT_REM_RPY;
                            end
                        end else begin // timeout
                            if (!cm_timout_retry_reg) begin
                                qp_info_valid_next = 1'b1; // send OP again

                                cm_timout_retry_next = 1'b1;
                                $display("[%t] TRIGGERED CM REQUEST RETRANSMISSION\n", $time);
                                state_next = STATE_WAIT_REM_RPY;
                            end else begin
                                if (qp_info_req_type_reg == REQ_OPEN_QP) begin // put back the loc qpn to the avaiable ones
                                    if (s_qpn_fifo_ready) begin // put QPN back to the pool
                                        s_qpn_next = qp_info_loc_qpn_reg;
                                        s_qpn_fifo_valid_next = 1'b1;
                                        $display("[%t] TIMEOUT, put QPN (%0d) back to the pool\n", $time, qp_info_loc_qpn_reg);
                                    end else begin
                                        //errors?
                                    end
                                end
                                cm_qp_master_status_valid_next   = 1'b1;
                                cm_qp_master_status_next         = CM_ERROR_TIMEOUT;
                                cm_qp_master_status_loc_qpn_next = cm_qp_loc_qpn_reg;

                                cm_timout_retry_next     = 1'b0;
                                state_next = STATE_IDLE;
                            end
                        end
                    end
                    STATE_MODIFY_QP: begin
                        if (cm_qp_status_valid) begin
                            if (cm_qp_status == 2'b00) begin //succesfully modify local qp
                                if (cm_qp_req_type_reg == REQ_CLOSE_QP) begin
                                    if (s_qpn_fifo_ready) begin // put closed local QPN back to the pool
                                        s_qpn_next            = cm_qp_loc_qpn_reg;
                                        s_qpn_fifo_valid_next = 1'b1;
                                        $display("[%t] SUCCESFULLY CLOSED QP, put QPN (%0d) back to the pool\n", $time, cm_qp_loc_qpn_reg);
                                    end
                                end
                                cm_qp_master_status_valid_next   = 1'b1;
                                cm_qp_master_status_next         = CM_STATUS_OK;
                                cm_qp_master_status_loc_qpn_next = cm_qp_loc_qpn_reg;
                                state_next = STATE_IDLE;
                            end else begin
                                cm_qp_master_status_valid_next   = 1'b1;
                                cm_qp_master_status_next         = CM_ERROR_MOD_QP;
                                cm_qp_master_status_loc_qpn_next = cm_qp_loc_qpn_reg;
                                state_next = STATE_IDLE;
                            end
                        end else begin // maybe add a timeout here as well
                            state_next = STATE_MODIFY_QP;
                        end
                    end
                endcase
            end

            always @(posedge clk) begin
                if (rst)begin
                    state_reg <= STATE_IDLE;
                    cm_qp_master_req_valid_reg <= 1'b0;

                    cm_qp_master_status_valid_reg   <= 1'b0;
                    cm_qp_master_status_reg         <= 'd0;
                    cm_qp_master_status_loc_qpn_reg <= 24'd0;

                    cm_timout_retry_reg <= 1'b0;
                    cm_timout_retry_reg_del <= 1'b0;

                    cm_timout_counter <= MASTER_TIMEOUT;

                end else begin
                    state_reg <= state_next;
                    cm_qp_master_req_valid_reg <= cm_qp_master_req_valid;
                    if (cm_qp_master_req_valid) begin
                        cm_qp_master_req_type_reg <= cm_qp_master_req_type;
                    end

                    cm_qp_master_status_valid_reg   <= cm_qp_master_status_valid_next;
                    cm_qp_master_status_reg         <= cm_qp_master_status_next;
                    cm_qp_master_status_loc_qpn_reg <= cm_qp_master_status_loc_qpn_next;

                    cm_timout_retry_reg     <= cm_timout_retry_next;
                    cm_timout_retry_reg_del <= cm_timout_retry_reg;

                    if (state_reg == STATE_WAIT_REM_RPY || state_reg == STATE_MODIFY_QP) begin
                        //if (cm_timout_retry_reg && ~cm_timout_retry_reg_del) begin // rising edge
                        //    cm_timout_counter <= MASTER_TIMEOUT;
                        //end else
                        if (cm_timout_counter > 0) begin
                            cm_timout_counter <= cm_timout_counter - 1;
                        end else begin
                            cm_timout_counter <= MASTER_TIMEOUT;
                        end
                    end else begin
                        cm_timout_counter <= MASTER_TIMEOUT;
                    end
                end
            end

            assign cm_qp_master_status_valid   = cm_qp_master_status_valid_reg;
            assign cm_qp_master_status         = cm_qp_master_status_reg;
            assign cm_qp_master_status_loc_qpn = cm_qp_master_status_loc_qpn_reg;

        end

    endgenerate


    always @(posedge clk) begin
        if (rst)begin

            m_qpn_fifo_ready_reg <= 1'b0;

            s_qpn_fifo_valid_reg <= 1'b0;
            s_qpn_reg            <= 0;

            qp_close_req_reg <= 1'b0;

            qp_info_valid_reg     <= 1'b0;
            qp_info_ack_valid_reg <= 1'b0;

            qp_info_req_type_reg      <= REQ_NULL;
            qp_info_ack_type_reg      <= ACK_NULL;
            qp_info_loc_r_key_reg     <= 0;
            qp_info_loc_qpn_reg       <= 0;
            qp_info_loc_psn_reg       <= 0;
            qp_info_loc_ip_addr_reg   <= 0;
            qp_info_loc_base_addr_reg <= 0;
            qp_info_rem_r_key_reg     <= 0;
            qp_info_rem_qpn_reg       <= 0;
            qp_info_rem_psn_reg       <= 0;
            qp_info_rem_ip_addr_reg   <= 0;
            qp_info_rem_base_addr_reg <= 0;

            udp_dest_port_reg         <= CM_DEST_UDP_PORT; 

            cm_qp_valid_reg          <= 1'b0;
            cm_qp_req_type_reg       <= 0;
            cm_qp_r_key_reg          <= 0;
            cm_qp_rem_qpn_reg        <= 0;
            cm_qp_loc_qpn_reg        <= 0;
            cm_qp_rem_psn_reg        <= 0;
            cm_qp_loc_psn_reg        <= 0;
            cm_qp_rem_ip_addr_reg    <= 0;
            cm_qp_rem_base_addr_reg  <= 0;

        end else begin

            m_qpn_fifo_ready_reg <= m_qpn_fifo_ready_next;

            s_qpn_fifo_valid_reg <= s_qpn_fifo_valid_next;
            s_qpn_reg            <= s_qpn_next;

            qp_close_req_reg <= qp_close_req_next;

            qp_info_valid_reg <= qp_info_valid_next;
            qp_info_ack_valid_reg <= qp_info_ack_valid_next;

            qp_info_req_type_reg      <= qp_info_req_type_next    ;
            qp_info_ack_type_reg      <= qp_info_ack_type_next    ;
            qp_info_loc_r_key_reg     <= qp_info_loc_r_key_next   ;
            qp_info_loc_qpn_reg       <= qp_info_loc_qpn_next     ;
            qp_info_loc_psn_reg       <= qp_info_loc_psn_next     ;
            qp_info_loc_ip_addr_reg   <= qp_info_loc_ip_addr_next ;
            qp_info_loc_base_addr_reg <= qp_info_loc_base_addr_next    ;
            qp_info_rem_r_key_reg     <= qp_info_rem_r_key_next   ;
            qp_info_rem_qpn_reg       <= qp_info_rem_qpn_next     ;
            qp_info_rem_psn_reg       <= qp_info_rem_psn_next     ;
            qp_info_rem_ip_addr_reg   <= qp_info_rem_ip_addr_next ;
            qp_info_rem_base_addr_reg <= qp_info_rem_base_addr_next;

            qp_info_udp_dest_port_reg <= qp_info_udp_dest_port_next;

            udp_dest_port_reg         <= MODULE_DIRECTION == "Master" ? CM_DEST_UDP_PORT : udp_dest_port_next; 

            cm_qp_valid_reg <= cm_qp_valid_next;

            cm_qp_req_type_reg      <= cm_qp_req_type_next;
            cm_qp_r_key_reg         <= cm_qp_r_key_next;
            cm_qp_rem_qpn_reg       <= cm_qp_rem_qpn_next;
            cm_qp_loc_qpn_reg       <= cm_qp_loc_qpn_next;
            cm_qp_rem_psn_reg       <= cm_qp_rem_psn_next;
            cm_qp_loc_psn_reg       <= cm_qp_loc_psn_next;
            cm_qp_rem_ip_addr_reg   <= cm_qp_rem_ip_addr_next;
            cm_qp_rem_base_addr_reg <= cm_qp_rem_base_addr_next;

        end

    end

    assign cm_qp_valid = cm_qp_valid_reg;
    assign cm_qp_req_type = cm_qp_req_type_reg;
    assign cm_qp_r_key = cm_qp_r_key_reg;
    assign cm_qp_rem_qpn = cm_qp_rem_qpn_reg;
    assign cm_qp_loc_qpn = cm_qp_loc_qpn_reg;
    assign cm_qp_rem_psn = cm_qp_rem_psn_reg;
    assign cm_qp_loc_psn = cm_qp_loc_psn_reg;
    assign cm_qp_rem_ip_addr = cm_qp_rem_ip_addr_reg;
    assign cm_qp_rem_base_addr = cm_qp_rem_base_addr_reg;

    assign s_qp_info_valid     = qp_info_valid_reg;
    assign s_qp_info_ack_valid = qp_info_ack_valid_reg;

    assign s_qp_info_req_type = qp_info_req_type_reg;
    assign s_qp_info_ack_type = qp_info_ack_type_reg;
    assign s_qp_info_loc_qpn  = qp_info_loc_qpn_reg;
    assign s_qp_info_loc_psn = qp_info_loc_psn_reg;
    assign s_qp_info_loc_r_key = qp_info_loc_r_key_reg;
    assign s_qp_info_loc_ip_addr = qp_info_loc_ip_addr_reg;
    assign s_qp_info_loc_base_addr = qp_info_loc_base_addr_reg;

    assign s_qp_info_rem_qpn = qp_info_rem_qpn_reg;
    assign s_qp_info_rem_psn = qp_info_rem_psn_reg;
    assign s_qp_info_rem_r_key = qp_info_rem_r_key_reg;
    assign s_qp_info_rem_ip_addr = qp_info_rem_ip_addr_reg;
    assign s_qp_info_rem_base_addr = qp_info_rem_base_addr_reg;

    assign s_qp_info_udp_dest_port = qp_info_udp_dest_port_reg;

    assign udp_dest_port = udp_dest_port_reg;


endmodule

`resetall