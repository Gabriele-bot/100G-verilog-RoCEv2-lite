`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_tx_queue #(
    parameter DATA_WIDTH                       = 256,
    parameter CLOCK_PERIOD                     = 6.4, // in ns
    parameter DEBUG                            = 0,
    parameter LOCAL_QPN                        = 256,
    parameter REFRESH_CACHE_TICKS              = 32768
) (
    input wire clk,
    input wire rst,

    input  wire         s_wr_req_valid,
    output wire         s_wr_req_ready,
    input  wire         s_wr_req_tx_type,
    input  wire         s_wr_req_is_immediate,
    input  wire [31:0]  s_wr_req_immediate_data,
    input  wire [23:0]  s_wr_req_loc_qp,
    input  wire [63:0]  s_wr_req_addr_offset,
    input  wire [31:0]  s_wr_req_dma_length,

    input  wire [DATA_WIDTH   - 1 : 0] s_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 : 0] s_payload_axis_tkeep,
    input  wire                        s_payload_axis_tvalid,
    output wire                        s_payload_axis_tready,
    input  wire                        s_payload_axis_tlast,
    input  wire                        s_payload_axis_tuser,

    // RoCE AXIS output
    // RoCE AXIS from retransmission module
    output wire m_roce_bth_valid,
    output wire m_roce_reth_valid,
    output wire m_roce_immdh_valid,
    input  wire m_roce_bth_ready,
    input  wire m_roce_reth_ready,
    input  wire m_roce_immdh_ready,

    output wire [7:0]  m_roce_bth_op_code,
    output wire [15:0] m_roce_bth_p_key,
    output wire [23:0] m_roce_bth_psn,
    output wire [23:0] m_roce_bth_dest_qp,
    output wire [23:0] m_roce_bth_src_qp,
    output wire        m_roce_bth_ack_req,

    output wire [63:0] m_roce_reth_v_addr,
    output wire [31:0] m_roce_reth_r_key,
    output wire [31:0] m_roce_reth_length,

    output wire [31:0] m_roce_immdh_data,


    output wire [47:0] m_roce_eth_dest_mac,
    output wire [47:0] m_roce_eth_src_mac,
    output wire [15:0] m_roce_eth_type,
    output wire [3:0]  m_roce_ip_version,
    output wire [3:0]  m_roce_ip_ihl,
    output wire [5:0]  m_roce_ip_dscp,
    output wire [1:0]  m_roce_ip_ecn,
    output wire [15:0] m_roce_ip_identification,
    output wire [2:0]  m_roce_ip_flags,
    output wire [12:0] m_roce_ip_fragment_offset,
    output wire [7:0]  m_roce_ip_ttl,
    output wire [7:0]  m_roce_ip_protocol,
    output wire [15:0] m_roce_ip_header_checksum,
    output wire [31:0] m_roce_ip_source_ip,
    output wire [31:0] m_roce_ip_dest_ip,
    output wire [15:0] m_roce_udp_source_port,
    output wire [15:0] m_roce_udp_dest_port,
    output wire [15:0] m_roce_udp_length,
    output wire [15:0] m_roce_udp_checksum,

    output wire [DATA_WIDTH   - 1 : 0] m_roce_payload_axis_tdata,
    output wire [DATA_WIDTH/8 - 1 : 0] m_roce_payload_axis_tkeep,
    output wire                        m_roce_payload_axis_tvalid,
    output wire                        m_roce_payload_axis_tlast,
    output wire                        m_roce_payload_axis_tuser,
    input  wire                        m_roce_payload_axis_tready,

    // Update qp state
    output wire         m_qp_update_context_valid,
    input  wire         m_qp_update_context_ready,
    output wire [23:0]  m_qp_update_context_loc_qpn,
    output wire [23:0]  m_qp_update_context_rem_psn,

    output wire        wr_error_qp_not_rts_out,
    output wire [23:0] wr_error_loc_qpn_out,

    // CM signals
    input wire        cm_qp_valid,

    input wire [2 :0] cm_qp_req_type,
    input wire [31:0] cm_qp_dma_transfer_length,
    input wire [23:0] cm_qp_rem_qpn,
    input wire [23:0] cm_qp_loc_qpn,
    input wire [23:0] cm_qp_rem_psn,
    input wire [23:0] cm_qp_loc_psn,
    input wire [31:0] cm_qp_r_key,
    input wire [63:0] cm_qp_rem_addr,
    input wire [31:0] cm_qp_rem_ip_addr,
    input wire        qp_is_immediate,
    input wire        qp_tx_type,
    // QP state request
    output wire        m_qp_context_req_valid,
    input  wire        m_qp_context_req_ready,
    output wire [23:0] m_qp_local_qpn_req,
    // QP state reply
    input wire        s_qp_req_context_valid,
    input wire [2 :0] s_qp_req_state,
    input wire [23:0] s_qp_req_rem_qpn,
    input wire [23:0] s_qp_req_loc_qpn,
    input wire [23:0] s_qp_req_rem_psn,
    input wire [23:0] s_qp_req_loc_psn,
    input wire [31:0] s_qp_req_r_key,
    input wire [63:0] s_qp_req_rem_addr,
    input wire [31:0] s_qp_req_rem_ip_addr,

    // TODO Fix stall
    input wire stall,

    /* Configuration
     */
    input  wire [  2:0] pmtu,
    input  wire [ 15:0] RoCE_udp_port,
    input  wire [ 31:0] loc_ip_addr

);

    import RoCE_params::*; // Imports RoCE parameters


    // work request metadata
    wire         m_wr_req_valid;
    wire         m_wr_req_ready;
    wire         m_wr_req_tx_type; // 0 WRITE, 1 SEND
    wire         m_wr_req_is_immediate;
    wire [31:0]  m_wr_req_immediate_data;
    wire [23:0]  m_wr_req_loc_qp;
    wire [63:0]  m_wr_req_addr_offset;
    wire [31:0]  m_wr_req_dma_length; // for each transfer

    // axis to framer
    wire [DATA_WIDTH   - 1 : 0] m_payload_framer_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_payload_framer_axis_tkeep;
    wire                        m_payload_framer_axis_tvalid;
    wire                        m_payload_framer_axis_tlast;
    wire [14:0]                 m_payload_framer_axis_tuser;
    wire                        m_payload_framer_axis_tready;

    // axis from framer to RoCE queue
    wire [DATA_WIDTH   - 1 : 0] m_payload_queue_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_payload_queue_axis_tkeep;
    wire                        m_payload_queue_axis_tvalid;
    wire                        m_payload_queue_axis_tlast;
    wire [14:0]                 m_payload_queue_axis_tuser;
    wire                        m_payload_queue_axis_tready;

    // dma metadata from framer to RoCE queue
    wire        m_framer_dma_meta_valid;
    wire        m_framer_dma_meta_ready;
    wire [31:0] m_framer_dma_length;
    wire [23:0] m_framer_rem_qpn;
    wire [23:0] m_framer_loc_qpn;
    wire [23:0] m_framer_rem_psn;
    wire [31:0] m_framer_r_key;
    wire [31:0] m_framer_rem_ip_addr;
    wire [63:0] m_framer_rem_addr;
    wire        m_framer_is_immediate;
    wire [31:0] m_framer_immediate_data;
    wire        m_framer_transfer_type;

    wire [15:0] source_udp_port = 16'd40128 + LOCAL_QPN;

    reg        qp_active;

    wire        wr_error_qp_not_rts;
    wire [23:0] wr_error_loc_qpn;

    wire stop_transfer_nack;

    reg [3:0] pmtu_shift;
    reg [11:0] length_pmtu_mask;

    always @(posedge clk) begin
        case (pmtu)
            3'd0: begin
                pmtu_shift <= 4'd8;
                length_pmtu_mask = {4'h0, {8{1'b1}}};
            end
            3'd1: begin
                pmtu_shift <= 4'd9;
                length_pmtu_mask = {3'h0, {9{1'b1}}};
            end
            3'd2: begin
                pmtu_shift <= 4'd10;
                length_pmtu_mask = {2'h0, {10{1'b1}}};
            end
            3'd3: begin
                pmtu_shift <= 4'd11;
                length_pmtu_mask = {1'h0, {11{1'b1}}};
            end
            3'd4: begin
                pmtu_shift <= 4'd12;
                length_pmtu_mask = {12{1'b1}};
            end
        endcase
    end


    always @(posedge clk) begin
        if (rst) begin
            qp_active     <= 1'b0;
        end else begin
            if (cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP && !qp_active && cm_qp_loc_qpn == LOCAL_QPN) begin
                qp_active     <= 1'b1;
            end else if (cm_qp_valid && cm_qp_req_type == REQ_CLOSE_QP && qp_active && cm_qp_loc_qpn == LOCAL_QPN) begin
                qp_active     <= 1'b0;
            end
        end
    end

    axis_packet_framer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) axis_packet_framer_instance (
        .clk(clk),
        .rst(rst),

        .s_wr_req_valid         (s_wr_req_valid),
        .s_wr_req_ready         (s_wr_req_ready),
        .s_wr_req_loc_qp        (s_wr_req_loc_qp),
        .s_wr_req_dma_length    (s_wr_req_dma_length),
        .s_wr_req_addr_offset   (s_wr_req_addr_offset),
        .s_wr_req_immediate_data(s_wr_req_immediate_data),
        .s_wr_req_is_immediate  (s_wr_req_is_immediate),
        .s_wr_req_tx_type       (s_wr_req_tx_type),

        .s_axis_tdata           (s_payload_axis_tdata ),
        .s_axis_tkeep           (s_payload_axis_tkeep ),
        .s_axis_tvalid          (s_payload_axis_tvalid),
        .s_axis_tready          (s_payload_axis_tready),
        .s_axis_tlast           (s_payload_axis_tlast ),
        .s_axis_tuser           (s_payload_axis_tuser ),

        .m_wr_req_valid         (m_wr_req_valid),
        .m_wr_req_ready         (m_wr_req_ready),
        .m_wr_req_loc_qp        (m_wr_req_loc_qp),
        .m_wr_req_dma_length    (m_wr_req_dma_length),
        .m_wr_req_addr_offset   (m_wr_req_addr_offset),
        .m_wr_req_immediate_data(m_wr_req_immediate_data),
        .m_wr_req_is_immediate  (m_wr_req_is_immediate),
        .m_wr_req_tx_type       (m_wr_req_tx_type),

        .m_axis_tdata           (m_payload_framer_axis_tdata ),
        .m_axis_tkeep           (m_payload_framer_axis_tkeep ),
        .m_axis_tvalid          (m_payload_framer_axis_tvalid),
        .m_axis_tready          (m_payload_framer_axis_tready),
        .m_axis_tlast           (m_payload_framer_axis_tlast ),
        .m_axis_tuser           (m_payload_framer_axis_tuser ),
        .pmtu                   (pmtu)
    );

    RoCE_simple_work_queue #(
        .DATA_WIDTH         (DATA_WIDTH),
        .REFRESH_CACHE_TICKS(REFRESH_CACHE_TICKS)
    ) RoCE_simple_work_queue_instance (
        .clk(clk),
        .rst(rst),

        .s_axis_tdata           (m_payload_framer_axis_tdata ),
        .s_axis_tkeep           (m_payload_framer_axis_tkeep ),
        .s_axis_tvalid          (m_payload_framer_axis_tvalid),
        .s_axis_tready          (m_payload_framer_axis_tready),
        .s_axis_tlast           (m_payload_framer_axis_tlast ),
        .s_axis_tuser           (m_payload_framer_axis_tuser ),

        .m_axis_tdata           (m_payload_queue_axis_tdata ),
        .m_axis_tkeep           (m_payload_queue_axis_tkeep ),
        .m_axis_tvalid          (m_payload_queue_axis_tvalid),
        .m_axis_tready          (m_payload_queue_axis_tready),
        .m_axis_tlast           (m_payload_queue_axis_tlast ),
        .m_axis_tuser           (m_payload_queue_axis_tuser ),

        .s_wr_req_valid         (m_wr_req_valid),
        .s_wr_req_ready         (m_wr_req_ready),
        .s_wr_req_loc_qp        (m_wr_req_loc_qp),
        .s_wr_req_dma_length    (m_wr_req_dma_length),
        .s_wr_req_addr_offset   (m_wr_req_addr_offset),
        .s_wr_req_immediate_data(m_wr_req_immediate_data),
        .s_wr_req_is_immediate  (m_wr_req_is_immediate),
        .s_wr_req_tx_type       (m_wr_req_tx_type),

        .m_qp_context_req_valid (m_qp_context_req_valid),
        .m_qp_context_req_ready (m_qp_context_req_ready),
        .m_qp_local_qpn_req     (m_qp_local_qpn_req),

        .s_qp_context_valid     (s_qp_req_context_valid),
        .s_qp_state             (s_qp_req_state),
        .s_qp_r_key             (s_qp_req_r_key),
        .s_qp_rem_qpn           (s_qp_req_rem_qpn),
        .s_qp_loc_qpn           (s_qp_req_loc_qpn),
        .s_qp_rem_psn           (s_qp_req_rem_psn),
        .s_qp_loc_psn           (s_qp_req_loc_psn),
        .s_qp_rem_ip_addr       (s_qp_req_rem_ip_addr),
        .s_qp_rem_addr          (s_qp_req_rem_addr),

        // dma metadata
        .m_dma_meta_valid       (m_framer_dma_meta_valid),
        .m_dma_meta_ready       (m_framer_dma_meta_ready),
        .m_dma_length           (m_framer_dma_length    ),
        .m_rem_qpn              (m_framer_rem_qpn       ),
        .m_loc_qpn              (m_framer_loc_qpn       ),
        .m_rem_psn              (m_framer_rem_psn       ),
        .m_r_key                (m_framer_r_key         ),
        .m_rem_ip_addr          (m_framer_rem_ip_addr   ),
        .m_rem_addr             (m_framer_rem_addr      ),
        .m_immediate_data       (m_framer_immediate_data),
        .m_is_immediate         (m_framer_is_immediate  ),
        .m_transfer_type        (m_framer_transfer_type ),

        .m_qp_update_context_valid  (m_qp_update_context_valid),
        .m_qp_update_context_ready  (m_qp_update_context_ready),
        .m_qp_update_context_loc_qpn(m_qp_update_context_loc_qpn),
        .m_qp_update_context_rem_psn(m_qp_update_context_rem_psn),

        .error_qp_not_rts       (wr_error_qp_not_rts),
        .error_loc_qpn          (wr_error_loc_qpn   )
    );

    RoCE_tx_header_producer #(
        .DATA_WIDTH(DATA_WIDTH)
    ) Roce_tx_header_producer_instance (
        .clk                       (clk),
        .rst                       (rst),

        .s_dma_meta_valid          (m_framer_dma_meta_valid),
        .s_dma_meta_ready          (m_framer_dma_meta_ready),
        .s_dma_length              (m_framer_dma_length    ),
        .s_rem_qpn                 (m_framer_rem_qpn       ),
        .s_loc_qpn                 (m_framer_loc_qpn       ),
        .s_rem_psn                 (m_framer_rem_psn       ),
        .s_r_key                   (m_framer_r_key         ),
        .s_rem_ip_addr             (m_framer_rem_ip_addr   ),
        .s_src_udp_port            (source_udp_port        ),
        .s_rem_addr                (m_framer_rem_addr      ),
        .s_is_immediate            (m_framer_is_immediate  ),
        .s_immediate_data          (m_framer_immediate_data),
        .s_transfer_type           (m_framer_transfer_type ),

        .s_axis_tdata              (m_payload_queue_axis_tdata),
        .s_axis_tkeep              (m_payload_queue_axis_tkeep),
        .s_axis_tvalid             (m_payload_queue_axis_tvalid),
        .s_axis_tready             (m_payload_queue_axis_tready),
        .s_axis_tlast              (m_payload_queue_axis_tlast),
        .s_axis_tuser              (m_payload_queue_axis_tuser),

        .m_roce_bth_valid          (m_roce_bth_valid),
        .m_roce_bth_ready          (m_roce_bth_ready),
        .m_roce_bth_op_code        (m_roce_bth_op_code),
        .m_roce_bth_p_key          (m_roce_bth_p_key),
        .m_roce_bth_psn            (m_roce_bth_psn),
        .m_roce_bth_dest_qp        (m_roce_bth_dest_qp),
        .m_roce_bth_src_qp         (m_roce_bth_src_qp),
        .m_roce_bth_ack_req        (m_roce_bth_ack_req),
        .m_roce_reth_valid         (m_roce_reth_valid),
        .m_roce_reth_ready         (m_roce_reth_ready),
        .m_roce_reth_v_addr        (m_roce_reth_v_addr),
        .m_roce_reth_r_key         (m_roce_reth_r_key),
        .m_roce_reth_length        (m_roce_reth_length),
        .m_roce_immdh_valid        (m_roce_immdh_valid),
        .m_roce_immdh_ready        (m_roce_immdh_ready),
        .m_roce_immdh_data         (m_roce_immdh_data),
        .m_eth_dest_mac            (m_roce_eth_dest_mac),
        .m_eth_src_mac             (m_roce_eth_src_mac),
        .m_eth_type                (m_roce_eth_type),
        .m_ip_version              (m_roce_ip_version),
        .m_ip_ihl                  (m_roce_ip_ihl),
        .m_ip_dscp                 (m_roce_ip_dscp),
        .m_ip_ecn                  (m_roce_ip_ecn),
        .m_ip_identification       (m_roce_ip_identification),
        .m_ip_flags                (m_roce_ip_flags),
        .m_ip_fragment_offset      (m_roce_ip_fragment_offset),
        .m_ip_ttl                  (m_roce_ip_ttl),
        .m_ip_protocol             (m_roce_ip_protocol),
        .m_ip_header_checksum      (m_roce_ip_header_checksum),
        .m_ip_source_ip            (m_roce_ip_source_ip),
        .m_ip_dest_ip              (m_roce_ip_dest_ip),
        .m_udp_source_port         (m_roce_udp_source_port),
        .m_udp_dest_port           (m_roce_udp_dest_port),
        .m_udp_length              (m_roce_udp_length),
        .m_udp_checksum            (m_roce_udp_checksum),

        .m_roce_payload_axis_tdata (m_roce_payload_axis_tdata),
        .m_roce_payload_axis_tkeep (m_roce_payload_axis_tkeep),
        .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_payload_axis_tlast),
        .m_roce_payload_axis_tuser (m_roce_payload_axis_tuser),

        .stall                     (stall),

        .pmtu                      (pmtu),
        .RoCE_udp_port             (RoCE_udp_port),
        .loc_ip_addr               (loc_ip_addr)
    );

    assign wr_error_qp_not_rts_out = wr_error_qp_not_rts;
    assign wr_error_loc_qpn_out    = wr_error_loc_qpn;

endmodule

`resetall