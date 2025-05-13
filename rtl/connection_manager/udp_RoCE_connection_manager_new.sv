`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * Connection manager over UDP
 */

module udp_RoCE_connection_manager_new #(
    parameter DATA_WIDTH      = 256,
    parameter MAX_QUEUE_PAIRS = 4,
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
     * QP info to QP state module
     */
    output wire        qp_init_valid,
    output wire [2:0 ] qp_init_req_type,
    output wire [31:0] qp_init_r_key,
    output wire [23:0] qp_init_rem_qpn,
    output wire [23:0] qp_init_loc_qpn,
    output wire [23:0] qp_init_rem_psn,
    output wire [23:0] qp_init_loc_psn,
    output wire [31:0] qp_init_rem_ip_addr,
    output wire [63:0] qp_init_rem_base_addr,

    input wire       qp_init_status_valid,
    input wire [1:0] qp_init_status,

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
    output wire         busy,
    /*
     * Configuration
     */
    input wire [15:0] cfg_udp_source_port,
    input wire [31:0] cfg_loc_ip_addr
);

    import RoCE_params::*; // Imports RoCE parameters

    localparam [2:0]
    STATE_IDLE       = 3'd0,
    STATE_MODIFY_QP  = 3'd1,
    STATE_SEND_ERROR = 3'd2;

    reg [2:0] state_reg = STATE_IDLE, state_next;


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

    reg qp_init_valid_reg, qp_init_valid_next;

    reg [2 :0] qp_init_req_type_reg, qp_init_req_type_next;
    reg [31:0] qp_init_r_key_reg, qp_init_r_key_next;
    reg [23:0] qp_init_rem_qpn_reg, qp_init_rem_qpn_next;
    reg [23:0] qp_init_loc_qpn_reg, qp_init_loc_qpn_next;
    reg [23:0] qp_init_rem_psn_reg, qp_init_rem_psn_next;
    reg [23:0] qp_init_loc_psn_reg, qp_init_loc_psn_next;
    reg [31:0] qp_init_rem_ip_addr_reg, qp_init_rem_ip_addr_next;
    reg [63:0] qp_init_rem_base_addr_reg, qp_init_rem_base_addr_next;

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

    assign s_qpn_fifo_valid = s_qpn_fifo_valid_reg;
    assign m_qpn_fifo_ready = m_qpn_fifo_ready_reg;

    assign s_qpn = s_qpn_reg;


    udp_RoCE_connection_manager_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .LISTEN_UDP_PORT(LISTEN_UDP_PORT)
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

        .busy(busy)
    );


    udp_RoCE_connection_manager_tx #(
    .DATA_WIDTH(DATA_WIDTH)
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
        .busy(busy),

        .cfg_udp_source_port(cfg_udp_source_port)
    );

    qpn_fifo_init #(
    .MAX_QUEUE_PAIRS(MAX_QUEUE_PAIRS)
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


    always @* begin

        m_qpn_fifo_ready_next = 1'b0;
        s_qpn_fifo_valid_next = 1'b0;

        qp_close_req_next = 1'b0;

        s_qpn_next = s_qpn_reg;

        qp_info_valid_next     = qp_info_valid_reg && !s_qp_info_ready;
        qp_info_ack_valid_next = qp_info_ack_valid_reg && (qp_info_valid_reg && !s_qp_info_ready);

        qp_info_req_type_next    = qp_info_req_type_reg;
        qp_info_ack_type_next    = qp_info_ack_type_reg;
        qp_info_loc_r_key_next   = qp_info_loc_r_key_reg;
        qp_info_loc_qpn_next     = qp_info_loc_qpn_reg;
        qp_info_loc_psn_next     = qp_info_loc_psn_reg;
        qp_info_loc_ip_addr_next = qp_info_loc_ip_addr_reg;
        qp_info_loc_base_addr_next    = qp_info_loc_base_addr_reg;
        qp_info_rem_r_key_next   = qp_info_rem_r_key_reg;
        qp_info_rem_qpn_next     = qp_info_rem_qpn_reg;
        qp_info_rem_psn_next     = qp_info_rem_psn_reg;
        qp_info_rem_ip_addr_next = qp_info_rem_ip_addr_reg;
        qp_info_rem_base_addr_next    = qp_info_rem_base_addr_reg;

        qp_info_udp_dest_port_next = qp_info_udp_dest_port_reg;

        qp_init_valid_next = 1'b0;

        qp_init_req_type_next    = qp_init_req_type_reg;
        qp_init_r_key_next       = qp_init_r_key_reg;
        qp_init_rem_qpn_next     = qp_init_rem_qpn_reg;
        qp_init_loc_qpn_next     = qp_init_loc_qpn_reg;
        qp_init_rem_psn_next     = qp_init_rem_psn_reg;
        qp_init_loc_psn_next     = qp_init_loc_psn_reg;
        qp_init_rem_ip_addr_next = qp_init_rem_ip_addr_reg;
        qp_init_rem_base_addr_next    = qp_init_rem_base_addr_reg;

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
                                qp_info_loc_r_key_next   = 32'd0;
                                qp_info_loc_qpn_next     = m_qpn;
                                qp_info_loc_psn_next     = 24'd0;
                                qp_info_loc_ip_addr_next = cfg_loc_ip_addr;
                                qp_info_loc_base_addr_next    = 64'd0;

                                qp_info_rem_r_key_next   = m_qp_info_loc_r_key;
                                qp_info_rem_qpn_next     = m_qp_info_loc_qpn;
                                qp_info_rem_psn_next     = m_qp_info_loc_psn;
                                qp_info_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                                qp_info_rem_base_addr_next    = m_qp_info_loc_base_addr;

                                qp_info_udp_dest_port_next = m_qp_info_listening_port;

                                qp_init_valid_next = 1'b1;

                                qp_init_req_type_next    = REQ_OPEN_QP;
                                qp_init_r_key_next       = m_qp_info_loc_r_key;
                                qp_init_rem_qpn_next     = m_qp_info_loc_qpn;
                                qp_init_loc_qpn_next     = m_qpn;
                                qp_init_rem_psn_next     = m_qp_info_loc_psn;
                                qp_init_loc_psn_next     = 24'd0;
                                qp_init_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                                qp_init_rem_base_addr_next    = m_qp_info_loc_base_addr;

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

                            qp_init_valid_next = 1'b1;

                            qp_init_req_type_next    = REQ_MODIFY_QP_RTS;
                            qp_init_r_key_next       = m_qp_info_loc_r_key;
                            qp_init_rem_qpn_next     = m_qp_info_loc_qpn;
                            qp_init_loc_qpn_next     = m_qp_info_rem_qpn;
                            qp_init_rem_psn_next     = m_qp_info_loc_psn;
                            qp_init_loc_psn_next     = m_qp_info_rem_psn;
                            qp_init_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                            qp_init_rem_base_addr_next    = m_qp_info_loc_base_addr;

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

                                qp_init_valid_next = 1'b1;

                                qp_init_req_type_next    = REQ_CLOSE_QP;
                                qp_init_r_key_next       = m_qp_info_loc_r_key;
                                qp_init_rem_qpn_next     = m_qp_info_loc_qpn;
                                qp_init_loc_qpn_next     = m_qp_info_rem_qpn;
                                qp_init_rem_psn_next     = m_qp_info_loc_psn;
                                qp_init_loc_psn_next     = m_qp_info_rem_psn;
                                qp_init_rem_ip_addr_next = m_qp_info_loc_ip_addr;
                                qp_init_rem_base_addr_next    = m_qp_info_loc_base_addr;

                                state_next = STATE_MODIFY_QP;
                            end else begin
                                // Try to cloase a QP that is not in the suitable range
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
                if (qp_init_status_valid) begin
                    if (qp_init_status == 2'b00) begin
                        qp_info_valid_next     = 1'b1;
                        qp_info_ack_valid_next = 1'b1;
                        qp_info_ack_type_next = ACK_ACK;
                        if (qp_close_req_reg && s_qpn_fifo_ready) begin
                            // succesfully closed QP
                            s_qpn_next = qp_init_loc_qpn_reg;
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

            qp_init_valid_reg          <= 1'b0;
            qp_init_req_type_reg       <= 0;
            qp_init_r_key_reg          <= 0;
            qp_init_rem_qpn_reg        <= 0;
            qp_init_loc_qpn_reg        <= 0;
            qp_init_rem_psn_reg        <= 0;
            qp_init_loc_psn_reg        <= 0;
            qp_init_rem_ip_addr_reg    <= 0;
            qp_init_rem_base_addr_reg  <= 0;

        end else begin

            state_reg <= state_next;

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

            qp_init_valid_reg <= qp_init_valid_next;

            qp_init_req_type_reg      <= qp_init_req_type_next;
            qp_init_r_key_reg         <= qp_init_r_key_next;
            qp_init_rem_qpn_reg       <= qp_init_rem_qpn_next;
            qp_init_loc_qpn_reg       <= qp_init_loc_qpn_next;
            qp_init_rem_psn_reg       <= qp_init_rem_psn_next;
            qp_init_loc_psn_reg       <= qp_init_loc_psn_next;
            qp_init_rem_ip_addr_reg   <= qp_init_rem_ip_addr_next;
            qp_init_rem_base_addr_reg <= qp_init_rem_base_addr_next;

        end

    end

    assign qp_init_valid = qp_init_valid_reg;
    assign qp_init_req_type = qp_init_req_type_reg;
    assign qp_init_r_key = qp_init_r_key_reg;
    assign qp_init_rem_qpn = qp_init_rem_qpn_reg;
    assign qp_init_loc_qpn = qp_init_loc_qpn_reg;
    assign qp_init_rem_psn = qp_init_rem_psn_reg;
    assign qp_init_loc_psn = qp_init_loc_psn_reg;
    assign qp_init_rem_ip_addr = qp_init_rem_ip_addr_reg;
    assign qp_init_rem_base_addr = qp_init_rem_base_addr_reg;

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


endmodule

`resetall