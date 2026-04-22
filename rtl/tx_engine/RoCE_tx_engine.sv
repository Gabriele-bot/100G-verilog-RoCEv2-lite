`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_tx_engine #(
    parameter DATA_WIDTH                       = 256,
    parameter CLOCK_PERIOD                     = 6.4, // in ns
    parameter DEBUG                            = 0,
    parameter LOCAL_QPN                        = 256,
    parameter REFRESH_CACHE_TICKS              = 32768,
    parameter RETRANSMISSION                   = 1,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 24
) (
    input wire clk,
    input wire rst,

    input wire flow_ctrl_pause,

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

    // RoCE RX signals (ACKs)
    input  wire        s_roce_ack_bth_valid,
    output wire        s_roce_ack_bth_ready,
    input  wire [7:0]  s_roce_ack_bth_op_code,
    input  wire [15:0] s_roce_ack_bth_p_key,
    input  wire [23:0] s_roce_ack_bth_psn,
    input  wire [23:0] s_roce_ack_bth_dest_qp,
    input  wire        s_roce_ack_bth_ack_req,
    input  wire        s_roce_ack_aeth_valid,
    output wire        s_roce_ack_aeth_ready,
    input  wire [7:0]  s_roce_ack_aeth_syndrome,
    input  wire [23:0] s_roce_ack_aeth_msn,

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
    // close qp in case of connection errors
    output wire        qp_close_valid,
    input  wire        qp_close_ready,
    output wire [23:0] qp_close_loc_qpn,
    output wire [23:0] qp_close_rem_psn,

    output wire stop_transfer,

    /*
    Status
    */
    output wire [23:0]                                  last_buffered_psn,
    output wire [23:0]                                  last_acked_psn,
    output wire [23:0]                                  psn_diff,
    output wire [RETRANSMISSION_ADDR_BUFFER_WIDTH -1:0] used_memory, // in bytes
    output wire [31:0]                                  n_retransmit_triggers,
    output wire [31:0]                                  n_rnr_retransmit_triggers,


    /* Configuration
     */
    input  wire [  2:0] pmtu,
    input  wire [ 15:0] RoCE_udp_port,
    input  wire [ 31:0] loc_ip_addr,
    input  wire [ 63:0] timeout_period,
    input  wire [ 2 :0] retry_count,
    input  wire [ 2 :0] rnr_retry_count,
    input  wire         en_retrans

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

    // RoCE headers from RoCE hdr fsm to restransmission module
    wire m_roce_to_retrans_bth_valid;
    wire m_roce_to_retrans_reth_valid;
    wire m_roce_to_retrans_immdh_valid;
    wire m_roce_to_retrans_bth_ready;
    wire m_roce_to_retrans_reth_ready;
    wire m_roce_to_retrans_immdh_ready;

    wire [23:0] m_roce_to_retrans_bth_src_qp;
    wire roce_bth_hdr_t m_roce_to_retrans_bth;

    wire roce_reth_hdr_t m_roce_to_retrans_reth;

    wire roce_immd_hdr_t m_roce_to_retrans_immdh;

    wire [47:0] m_roce_to_retrans_eth_dest_mac;
    wire [47:0] m_roce_to_retrans_eth_src_mac;
    wire [15:0] m_roce_to_retrans_eth_type;
    wire [3:0]  m_roce_to_retrans_ip_version;
    wire [3:0]  m_roce_to_retrans_ip_ihl;
    wire [5:0]  m_roce_to_retrans_ip_dscp;
    wire [1:0]  m_roce_to_retrans_ip_ecn;
    wire [15:0] m_roce_to_retrans_ip_identification;
    wire [2:0]  m_roce_to_retrans_ip_flags;
    wire [12:0] m_roce_to_retrans_ip_fragment_offset;
    wire [7:0]  m_roce_to_retrans_ip_ttl;
    wire [7:0]  m_roce_to_retrans_ip_protocol;
    wire [15:0] m_roce_to_retrans_ip_header_checksum;
    wire [31:0] m_roce_to_retrans_ip_source_ip;
    wire [31:0] m_roce_to_retrans_ip_dest_ip;
    wire [15:0] m_roce_to_retrans_udp_source_port;
    wire [15:0] m_roce_to_retrans_udp_dest_port;
    wire [15:0] m_roce_to_retrans_udp_length;
    wire [15:0] m_roce_to_retrans_udp_checksum;

    wire [DATA_WIDTH   - 1 : 0] m_roce_to_retrans_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_roce_to_retrans_payload_axis_tkeep;
    wire                        m_roce_to_retrans_payload_axis_tvalid;
    wire                        m_roce_to_retrans_payload_axis_tlast;
    wire                        m_roce_to_retrans_payload_axis_tuser;
    wire                        m_roce_to_retrans_payload_axis_tready;


    /*
    AXI RAM INTERFACE
    */
    wire [0                :0]                  m_axi_awid;
    wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_awaddr;
    wire [7:0]                                  m_axi_awlen;
    wire [2:0]                                  m_axi_awsize;
    wire [1:0]                                  m_axi_awburst;
    wire                                        m_axi_awlock;
    wire [3:0]                                  m_axi_awcache;
    wire [2:0]                                  m_axi_awprot;
    wire                                        m_axi_awvalid;
    wire                                        m_axi_awready;
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_wdata;
    wire [DATA_WIDTH/8 - 1 : 0]                 m_axi_wstrb;
    wire                                        m_axi_wlast;
    wire                                        m_axi_wvalid;
    wire                                        m_axi_wready;
    wire [0             :0]                     m_axi_bid;
    wire [1:0]                                  m_axi_bresp;
    wire                                        m_axi_bvalid;
    wire                                        m_axi_bready;
    wire [0               :0]                   m_axi_arid;
    wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_araddr;
    wire [7:0]                                  m_axi_arlen;
    wire [2:0]                                  m_axi_arsize;
    wire [1:0]                                  m_axi_arburst;
    wire                                        m_axi_arlock;
    wire [3:0]                                  m_axi_arcache;
    wire [2:0]                                  m_axi_arprot;
    wire                                        m_axi_arvalid;
    wire                                        m_axi_arready;
    wire [0             :0]                     m_axi_rid;
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_rdata;
    wire [1:0]                                  m_axi_rresp;
    wire                                        m_axi_rlast;
    wire                                        m_axi_rvalid;
    wire                                        m_axi_rready;

    // remove!!
    wire [3:0] stall_qp;

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

        .m_roce_bth_valid          (m_roce_to_retrans_bth_valid),
        .m_roce_bth_ready          (m_roce_to_retrans_bth_ready && !stall_qp[0]),
        .m_roce_bth_op_code        (m_roce_to_retrans_bth.op_code),
        .m_roce_bth_p_key          (m_roce_to_retrans_bth.p_key),
        .m_roce_bth_psn            (m_roce_to_retrans_bth.psn),
        .m_roce_bth_dest_qp        (m_roce_to_retrans_bth.qp_number),
        .m_roce_bth_src_qp         (m_roce_to_retrans_bth_src_qp),
        .m_roce_bth_ack_req        (m_roce_to_retrans_bth.ack_request),
        .m_roce_reth_valid         (m_roce_to_retrans_reth_valid),
        .m_roce_reth_ready         (m_roce_to_retrans_reth_ready && !stall_qp[0]),
        .m_roce_reth_v_addr        (m_roce_to_retrans_reth.vaddr),
        .m_roce_reth_r_key         (m_roce_to_retrans_reth.r_key),
        .m_roce_reth_length        (m_roce_to_retrans_reth.dma_length),
        .m_roce_immdh_valid        (m_roce_to_retrans_immdh_valid),
        .m_roce_immdh_ready        (m_roce_to_retrans_immdh_ready && !stall_qp[0]),
        .m_roce_immdh_data         (m_roce_to_retrans_immdh.immediate_data),
        .m_eth_dest_mac            (m_roce_to_retrans_eth_dest_mac),
        .m_eth_src_mac             (m_roce_to_retrans_eth_src_mac),
        .m_eth_type                (m_roce_to_retrans_eth_type),
        .m_ip_version              (m_roce_to_retrans_ip_version),
        .m_ip_ihl                  (m_roce_to_retrans_ip_ihl),
        .m_ip_dscp                 (m_roce_to_retrans_ip_dscp),
        .m_ip_ecn                  (m_roce_to_retrans_ip_ecn),
        .m_ip_identification       (m_roce_to_retrans_ip_identification),
        .m_ip_flags                (m_roce_to_retrans_ip_flags),
        .m_ip_fragment_offset      (m_roce_to_retrans_ip_fragment_offset),
        .m_ip_ttl                  (m_roce_to_retrans_ip_ttl),
        .m_ip_protocol             (m_roce_to_retrans_ip_protocol),
        .m_ip_header_checksum      (m_roce_to_retrans_ip_header_checksum),
        .m_ip_source_ip            (m_roce_to_retrans_ip_source_ip),
        .m_ip_dest_ip              (m_roce_to_retrans_ip_dest_ip),
        .m_udp_source_port         (m_roce_to_retrans_udp_source_port),
        .m_udp_dest_port           (m_roce_to_retrans_udp_dest_port),
        .m_udp_length              (m_roce_to_retrans_udp_length),
        .m_udp_checksum            (m_roce_to_retrans_udp_checksum),

        .m_roce_payload_axis_tdata (m_roce_to_retrans_payload_axis_tdata),
        .m_roce_payload_axis_tkeep (m_roce_to_retrans_payload_axis_tkeep),
        .m_roce_payload_axis_tvalid(m_roce_to_retrans_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_to_retrans_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_to_retrans_payload_axis_tlast),
        .m_roce_payload_axis_tuser (m_roce_to_retrans_payload_axis_tuser),

        .pmtu                      (pmtu),
        .RoCE_udp_port             (RoCE_udp_port),
        .loc_ip_addr               (loc_ip_addr)
    );

    generate
        if (RETRANSMISSION) begin

            wire [151:0] s_qp_params;
            assign s_qp_params[31 :0  ] = cm_qp_rem_ip_addr;
            assign s_qp_params[55 :32 ] = cm_qp_rem_qpn;
            assign s_qp_params[79 :56 ] = cm_qp_loc_qpn;
            assign s_qp_params[111:80 ] = cm_qp_r_key;
            assign s_qp_params[127:112] = 16'hffff; // p_key
            assign s_qp_params[151:128] = cm_qp_rem_psn;

            /*
            
            RoCE_retransmission_module #(
                .DATA_WIDTH(DATA_WIDTH),
                .BUFFER_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                //.MAX_QUEUE_PAIRS(MAX_QUEUE_PAIRS),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .DEBUG(0)
            ) RoCE_retransmission_module_instance (
                .clk(clk),
                .rst(rst || (wr_error_qp_not_rts && wr_error_loc_qpn == LOCAL_QPN && qp_active) || (cm_qp_valid && cm_qp_loc_qpn == LOCAL_QPN && cm_qp_req_type == REQ_OPEN_QP)),
                .rst_retry_cntr              (cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP & !qp_active),
                .flow_ctrl_pause             (flow_ctrl_pause),
                .s_qp_params_valid           (cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP & !qp_active),
                .s_qp_params                 (s_qp_params),
                .s_roce_aeth_valid           (s_roce_ack_aeth_valid),
                .s_roce_rx_aeth_syndrome     (s_roce_ack_aeth_syndrome),
                .s_roce_rx_bth_psn           (s_roce_ack_bth_psn),
                .s_roce_rx_bth_op_code       (s_roce_ack_bth_op_code),
                .s_roce_rx_bth_dest_qp       (s_roce_ack_bth_dest_qp),
                .s_roce_rx_last_not_acked_psn(0),

                .s_roce_bth_valid            (m_roce_to_retrans_bth_valid),
                .s_roce_bth_ready            (m_roce_to_retrans_bth_ready),
                .s_roce_bth_op_code          (m_roce_to_retrans_bth.op_code),
                .s_roce_bth_p_key            (m_roce_to_retrans_bth.p_key),
                .s_roce_bth_psn              (m_roce_to_retrans_bth.psn),
                .s_roce_bth_dest_qp          (m_roce_to_retrans_bth.qp_number),
                .s_roce_bth_src_qp           (m_roce_to_retrans_bth_src_qp),
                .s_roce_bth_ack_req          (m_roce_to_retrans_bth.ack_request),
                .s_roce_reth_valid           (m_roce_to_retrans_reth_valid),
                .s_roce_reth_ready           (m_roce_to_retrans_reth_ready),
                .s_roce_reth_v_addr          (m_roce_to_retrans_reth.vaddr),
                .s_roce_reth_r_key           (m_roce_to_retrans_reth.r_key),
                .s_roce_reth_length          (m_roce_to_retrans_reth.dma_length),
                .s_roce_immdh_valid          (m_roce_to_retrans_immdh_valid),
                .s_roce_immdh_ready          (m_roce_to_retrans_immdh_ready),
                .s_roce_immdh_data           (m_roce_to_retrans_immdh.immediate_data),
                .s_eth_dest_mac              (m_roce_to_retrans_eth_dest_mac),
                .s_eth_src_mac               (m_roce_to_retrans_eth_src_mac),
                .s_eth_type                  (m_roce_to_retrans_eth_type),
                .s_ip_version                (m_roce_to_retrans_ip_version),
                .s_ip_ihl                    (m_roce_to_retrans_ip_ihl),
                .s_ip_dscp                   (m_roce_to_retrans_ip_dscp),
                .s_ip_ecn                    (m_roce_to_retrans_ip_ecn),
                .s_ip_identification         (m_roce_to_retrans_ip_identification),
                .s_ip_flags                  (m_roce_to_retrans_ip_flags),
                .s_ip_fragment_offset        (m_roce_to_retrans_ip_fragment_offset),
                .s_ip_ttl                    (m_roce_to_retrans_ip_ttl),
                .s_ip_protocol               (m_roce_to_retrans_ip_protocol),
                .s_ip_header_checksum        (m_roce_to_retrans_ip_header_checksum),
                .s_ip_source_ip              (m_roce_to_retrans_ip_source_ip),
                .s_ip_dest_ip                (m_roce_to_retrans_ip_dest_ip),
                .s_udp_source_port           (m_roce_to_retrans_udp_source_port),
                .s_udp_dest_port             (m_roce_to_retrans_udp_dest_port),
                .s_udp_length                (m_roce_to_retrans_udp_length),
                .s_udp_checksum              (m_roce_to_retrans_udp_checksum),

                .s_roce_payload_axis_tdata   (m_roce_to_retrans_payload_axis_tdata),
                .s_roce_payload_axis_tkeep   (m_roce_to_retrans_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid  (m_roce_to_retrans_payload_axis_tvalid),
                .s_roce_payload_axis_tready  (m_roce_to_retrans_payload_axis_tready),
                .s_roce_payload_axis_tlast   (m_roce_to_retrans_payload_axis_tlast),
                .s_roce_payload_axis_tuser   (m_roce_to_retrans_payload_axis_tuser),

                .m_roce_bth_valid            (m_roce_bth_valid),
                .m_roce_bth_ready            (m_roce_bth_ready),
                .m_roce_bth_op_code          (m_roce_bth_op_code),
                .m_roce_bth_p_key            (m_roce_bth_p_key),
                .m_roce_bth_psn              (m_roce_bth_psn),
                .m_roce_bth_dest_qp          (m_roce_bth_dest_qp),
                .m_roce_bth_src_qp           (m_roce_bth_src_qp),
                .m_roce_bth_ack_req          (m_roce_bth_ack_req),
                .m_roce_reth_valid           (m_roce_reth_valid),
                .m_roce_reth_ready           (m_roce_reth_ready),
                .m_roce_reth_v_addr          (m_roce_reth_v_addr),
                .m_roce_reth_r_key           (m_roce_reth_r_key),
                .m_roce_reth_length          (m_roce_reth_length),
                .m_roce_immdh_valid          (m_roce_immdh_valid),
                .m_roce_immdh_ready          (m_roce_immdh_ready),
                .m_roce_immdh_data           (m_roce_immdh_data),
                .m_eth_dest_mac              (m_roce_eth_dest_mac),
                .m_eth_src_mac               (m_roce_eth_src_mac),
                .m_eth_type                  (m_roce_eth_type),
                .m_ip_version                (m_roce_ip_version),
                .m_ip_ihl                    (m_roce_ip_ihl),
                .m_ip_dscp                   (m_roce_ip_dscp),
                .m_ip_ecn                    (m_roce_ip_ecn),
                .m_ip_identification         (m_roce_ip_identification),
                .m_ip_flags                  (m_roce_ip_flags),
                .m_ip_fragment_offset        (m_roce_ip_fragment_offset),
                .m_ip_ttl                    (m_roce_ip_ttl),
                .m_ip_protocol               (m_roce_ip_protocol),
                .m_ip_header_checksum        (m_roce_ip_header_checksum),
                .m_ip_source_ip              (m_roce_ip_source_ip),
                .m_ip_dest_ip                (m_roce_ip_dest_ip),
                .m_udp_source_port           (m_roce_udp_source_port),
                .m_udp_dest_port             (m_roce_udp_dest_port),
                .m_udp_length                (m_roce_udp_length),
                .m_udp_checksum              (m_roce_udp_checksum),

                .m_roce_payload_axis_tdata   (m_roce_payload_axis_tdata),
                .m_roce_payload_axis_tkeep   (m_roce_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid  (m_roce_payload_axis_tvalid),
                .m_roce_payload_axis_tready  (m_roce_payload_axis_tready),
                .m_roce_payload_axis_tlast   (m_roce_payload_axis_tlast),
                .m_roce_payload_axis_tuser   (m_roce_payload_axis_tuser),

                .m_axi_awid   (m_axi_awid),
                .m_axi_awaddr (m_axi_awaddr),
                .m_axi_awlen  (m_axi_awlen),
                .m_axi_awsize (m_axi_awsize),
                .m_axi_awburst(m_axi_awburst),
                .m_axi_awlock (m_axi_awlock),
                .m_axi_awcache(m_axi_awcache),
                .m_axi_awprot (m_axi_awprot),
                .m_axi_awvalid(m_axi_awvalid),
                .m_axi_awready(m_axi_awready),
                .m_axi_wdata  (m_axi_wdata),
                .m_axi_wstrb  (m_axi_wstrb),
                .m_axi_wlast  (m_axi_wlast),
                .m_axi_wvalid (m_axi_wvalid),
                .m_axi_wready (m_axi_wready),
                .m_axi_bid    (m_axi_bid),
                .m_axi_bresp  (m_axi_bresp),
                .m_axi_bvalid (m_axi_bvalid),
                .m_axi_bready (m_axi_bready),
                .m_axi_arid   (m_axi_arid),
                .m_axi_araddr (m_axi_araddr),
                .m_axi_arlen  (m_axi_arlen),
                .m_axi_arsize (m_axi_arsize),
                .m_axi_arburst(m_axi_arburst),
                .m_axi_arlock (m_axi_arlock),
                .m_axi_arcache(m_axi_arcache),
                .m_axi_arprot (m_axi_arprot),
                .m_axi_arvalid(m_axi_arvalid),
                .m_axi_arready(m_axi_arready),
                .m_axi_rid    (m_axi_rid),
                .m_axi_rdata  (m_axi_rdata),
                .m_axi_rresp  (m_axi_rresp),
                .m_axi_rlast  (m_axi_rlast),
                .m_axi_rvalid (m_axi_rvalid),
                .m_axi_rready (m_axi_rready),
                //
                .m_qp_close_valid  (qp_close_valid),
                .m_qp_close_ready  (qp_close_ready),
                .m_qp_close_loc_qpn(qp_close_loc_qpn),
                .m_qp_close_rem_psn(qp_close_rem_psn),
                //status
                .stop_transfer            (stop_transfer),
                .last_buffered_psn        (last_buffered_psn),
                .last_acked_psn           (last_acked_psn),
                .psn_diff                 (psn_diff),
                .used_memory              (used_memory),
                .n_retransmit_triggers    (n_retransmit_triggers),
                .n_rnr_retransmit_triggers(n_rnr_retransmit_triggers),
                // Config
                .cfg_valid(cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP & !qp_active),
                .timeout_period(timeout_period),
                .retry_count(retry_count),
                .rnr_retry_count(rnr_retry_count),
                .pmtu(pmtu),
                .en_retrans(en_retrans)
            );
            */

            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axis_dma_write_desc_addr;
            wire [12:0]                                 m_axis_dma_write_desc_len;
            wire                                        m_axis_dma_write_desc_valid;
            wire                                        m_axis_dma_write_desc_ready;

            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axis_dma_read_desc_addr;
            wire [12:0]                                 m_axis_dma_read_desc_len;
            wire                                        m_axis_dma_read_desc_valid;
            wire                                        m_axis_dma_read_desc_ready;
            /*
             * DMA Write status
             */
            wire [12:0]                  s_axis_dma_write_desc_status_len;
            wire [3 :0]                  s_axis_dma_write_desc_status_error;
            wire                         s_axis_dma_write_desc_status_valid;
            // DMA write payload
            wire [DATA_WIDTH   - 1 :0] m_dma_write_axis_tdata;
            wire [DATA_WIDTH/8 - 1 :0] m_dma_write_axis_tkeep;
            wire                       m_dma_write_axis_tvalid;
            wire                       m_dma_write_axis_tready;
            wire                       m_dma_write_axis_tlast;
            wire                       m_dma_write_axis_tuser;
            // DMA Read payload
            wire [DATA_WIDTH   - 1 :0] s_dma_read_axis_tdata;
            wire [DATA_WIDTH/8 - 1 :0] s_dma_read_axis_tkeep;
            wire                       s_dma_read_axis_tvalid;
            wire                       s_dma_read_axis_tready;
            wire                       s_dma_read_axis_tlast;
            wire                       s_dma_read_axis_tuser;

            wire hdr_ram_we, hdr_ram_re;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1-1:0] hdr_ram_waddr, hdr_ram_raddr;
            wire [199:0] hdr_ram_din, hdr_ram_dout;
            wire hdr_ram_dout_valid;
            reg [3:0] hdr_ram_dout_valid_pipes;

            wire                       m_rd_table_we;
            wire [$clog2(4)-1:0]       m_rd_table_qpn;
            wire [24-1:0]              m_rd_table_psn;

            wire                       s_rd_table_re;
            wire [$clog2(4)-1:0]       s_rd_table_qpn;
            wire [24-1:0]              s_rd_table_psn;

            wire                       m_wr_table_we;
            wire [$clog2(4)-1:0]       m_wr_table_qpn;
            wire [24-1:0]              m_wr_table_psn;

            wire                       s_wr_table_re;
            wire [$clog2(4)-1:0]       s_wr_table_qpn;
            wire [24-1:0]              s_wr_table_psn;

            wire                       m_cpl_table_we;
            wire [$clog2(4)-1:0]       m_cpl_table_qpn;
            wire [24-1:0]              m_cpl_table_psn;

            wire                       s_cpl_table_re;
            wire [$clog2(4)-1:0]       s_cpl_table_qpn;
            wire [24-1:0]              s_cpl_table_psn;

            wire                       m_rd_table_we_rtr;
            wire [$clog2(4)-1:0]       m_rd_table_qpn_rtr;
            wire [24-1:0]              m_rd_table_psn_rtr;

            wire                       m_wr_table_we_rtr;
            wire [$clog2(4)-1:0]       m_wr_table_qpn_rtr;
            wire [24-1:0]              m_wr_table_psn_rtr;

            wire                       m_cpl_table_we_rtr;
            wire [$clog2(4)-1:0]       m_cpl_table_qpn_rtr;
            wire [24-1:0]              m_cpl_table_psn_rtr;

            wire         rtr_wr_qp_close_valid   = (qp_close_valid && qp_close_ready) | (cm_qp_valid && cm_qp_req_type == REQ_CLOSE_QP);
            wire  [23:0] rtr_wr_qp_close_loc_qpn = (qp_close_valid && qp_close_ready) ? qp_close_loc_qpn : cm_qp_loc_qpn;

            RoCE_rtr_write_module #(
                .DATA_WIDTH(DATA_WIDTH),
                .BUFFER_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .MAX_QPS(4),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .DEBUG(0)
            ) RoCE_rtr_write_module_instance (
                .clk(clk),
                .rst(rst || (wr_error_qp_not_rts && wr_error_loc_qpn == LOCAL_QPN && qp_active) || (cm_qp_valid && cm_qp_loc_qpn == LOCAL_QPN && cm_qp_req_type == REQ_OPEN_QP)),

                .s_roce_bth_valid            (m_roce_to_retrans_bth_valid && !stall_qp[0]),
                .s_roce_bth_ready            (m_roce_to_retrans_bth_ready),
                .s_roce_bth_op_code          (m_roce_to_retrans_bth.op_code),
                .s_roce_bth_p_key            (m_roce_to_retrans_bth.p_key),
                .s_roce_bth_psn              (m_roce_to_retrans_bth.psn),
                .s_roce_bth_dest_qp          (m_roce_to_retrans_bth.qp_number),
                .s_roce_bth_src_qp           (m_roce_to_retrans_bth_src_qp),
                .s_roce_bth_ack_req          (m_roce_to_retrans_bth.ack_request),
                .s_roce_reth_valid           (m_roce_to_retrans_reth_valid && !stall_qp[0]),
                .s_roce_reth_ready           (m_roce_to_retrans_reth_ready),
                .s_roce_reth_v_addr          (m_roce_to_retrans_reth.vaddr),
                .s_roce_reth_r_key           (m_roce_to_retrans_reth.r_key),
                .s_roce_reth_length          (m_roce_to_retrans_reth.dma_length),
                .s_roce_immdh_valid          (m_roce_to_retrans_immdh_valid && !stall_qp[0]),
                .s_roce_immdh_ready          (m_roce_to_retrans_immdh_ready),
                .s_roce_immdh_data           (m_roce_to_retrans_immdh.immediate_data),
                .s_eth_dest_mac              (m_roce_to_retrans_eth_dest_mac),
                .s_eth_src_mac               (m_roce_to_retrans_eth_src_mac),
                .s_eth_type                  (m_roce_to_retrans_eth_type),
                .s_ip_version                (m_roce_to_retrans_ip_version),
                .s_ip_ihl                    (m_roce_to_retrans_ip_ihl),
                .s_ip_dscp                   (m_roce_to_retrans_ip_dscp),
                .s_ip_ecn                    (m_roce_to_retrans_ip_ecn),
                .s_ip_identification         (m_roce_to_retrans_ip_identification),
                .s_ip_flags                  (m_roce_to_retrans_ip_flags),
                .s_ip_fragment_offset        (m_roce_to_retrans_ip_fragment_offset),
                .s_ip_ttl                    (m_roce_to_retrans_ip_ttl),
                .s_ip_protocol               (m_roce_to_retrans_ip_protocol),
                .s_ip_header_checksum        (m_roce_to_retrans_ip_header_checksum),
                .s_ip_source_ip              (m_roce_to_retrans_ip_source_ip),
                .s_ip_dest_ip                (m_roce_to_retrans_ip_dest_ip),
                .s_udp_source_port           (m_roce_to_retrans_udp_source_port),
                .s_udp_dest_port             (m_roce_to_retrans_udp_dest_port),
                .s_udp_length                (m_roce_to_retrans_udp_length),
                .s_udp_checksum              (m_roce_to_retrans_udp_checksum),

                .s_roce_payload_axis_tdata   (m_roce_to_retrans_payload_axis_tdata),
                .s_roce_payload_axis_tkeep   (m_roce_to_retrans_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid  (m_roce_to_retrans_payload_axis_tvalid),
                .s_roce_payload_axis_tready  (m_roce_to_retrans_payload_axis_tready),
                .s_roce_payload_axis_tlast   (m_roce_to_retrans_payload_axis_tlast),
                .s_roce_payload_axis_tuser   (m_roce_to_retrans_payload_axis_tuser),

                .m_axis_dma_write_desc_addr (m_axis_dma_write_desc_addr),
                .m_axis_dma_write_desc_len  (m_axis_dma_write_desc_len),
                .m_axis_dma_write_desc_valid(m_axis_dma_write_desc_valid),
                .m_axis_dma_write_desc_ready(m_axis_dma_write_desc_ready),

                .s_axis_dma_write_desc_status_len  (s_axis_dma_write_desc_status_len),
                .s_axis_dma_write_desc_status_error(s_axis_dma_write_desc_status_error),
                .s_axis_dma_write_desc_status_valid(s_axis_dma_write_desc_status_valid),

                .m_dma_write_axis_tdata (m_dma_write_axis_tdata),
                .m_dma_write_axis_tkeep (m_dma_write_axis_tkeep),
                .m_dma_write_axis_tvalid(m_dma_write_axis_tvalid),
                .m_dma_write_axis_tready(m_dma_write_axis_tready),
                .m_dma_write_axis_tlast (m_dma_write_axis_tlast),
                .m_dma_write_axis_tuser (m_dma_write_axis_tuser),

                .hdr_ram_we        (hdr_ram_we),
                .hdr_ram_addr      (hdr_ram_waddr),
                .hdr_ram_data      (hdr_ram_din),

                .m_wr_table_we  (m_wr_table_we_rtr),
                .m_wr_table_qpn (m_wr_table_qpn_rtr),
                .m_wr_table_psn (m_wr_table_psn_rtr),

                .s_qp_close_valid  (rtr_wr_qp_close_valid),
                .s_qp_close_loc_qpn(rtr_wr_qp_close_loc_qpn),

                .s_qp_open_valid  (cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP),
                .s_qp_open_loc_qpn(cm_qp_loc_qpn),

                .pmtu(pmtu)
            );

            

            RoCE_rtr_read_module #(
                .DATA_WIDTH(DATA_WIDTH),
                .BUFFER_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .MAX_QPS(4),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .DEBUG(DEBUG)
            ) RoCE_rtr_read_module_instance (
                .clk(clk),
                .rst(rst),
                .s_roce_rx_aeth_valid        (s_roce_ack_aeth_valid),
                .s_roce_rx_aeth_ready        (s_roce_ack_aeth_ready),
                .s_roce_rx_aeth_syndrome     (s_roce_ack_aeth_syndrome),
                .s_roce_rx_bth_psn           (s_roce_ack_bth_psn),
                .s_roce_rx_bth_op_code       (s_roce_ack_bth_op_code),
                .s_roce_rx_bth_dest_qp       (s_roce_ack_bth_dest_qp),

                .s_roce_rx_last_not_acked_psn(0),

                .m_roce_bth_valid  (m_roce_bth_valid),
                .m_roce_bth_ready  (m_roce_bth_ready),
                .m_roce_bth_op_code(m_roce_bth_op_code),
                .m_roce_bth_p_key  (m_roce_bth_p_key),
                .m_roce_bth_psn    (m_roce_bth_psn),
                .m_roce_bth_dest_qp(m_roce_bth_dest_qp),
                .m_roce_bth_src_qp (m_roce_bth_src_qp),
                .m_roce_bth_ack_req(m_roce_bth_ack_req),
                .m_roce_reth_valid (m_roce_reth_valid),
                .m_roce_reth_ready (m_roce_reth_ready),
                .m_roce_reth_v_addr(m_roce_reth_v_addr),
                .m_roce_reth_r_key (m_roce_reth_r_key),
                .m_roce_reth_length(m_roce_reth_length),
                .m_roce_immdh_valid(m_roce_immdh_valid),
                .m_roce_immdh_ready(m_roce_immdh_ready),
                .m_roce_immdh_data (m_roce_immdh_data),

                .m_eth_dest_mac      (m_roce_eth_dest_mac),
                .m_eth_src_mac       (m_roce_eth_src_mac),
                .m_eth_type          (m_roce_eth_type),
                .m_ip_version        (m_roce_ip_version),
                .m_ip_ihl            (m_roce_ip_ihl),
                .m_ip_dscp           (m_roce_ip_dscp),
                .m_ip_ecn            (m_roce_ip_ecn),
                .m_ip_identification (m_roce_ip_identification),
                .m_ip_flags          (m_roce_ip_flags),
                .m_ip_fragment_offset(m_roce_ip_fragment_offset),
                .m_ip_ttl            (m_roce_ip_ttl),
                .m_ip_protocol       (m_roce_ip_protocol),
                .m_ip_header_checksum(m_roce_ip_header_checksum),
                .m_ip_source_ip      (m_roce_ip_source_ip),
                .m_ip_dest_ip        (m_roce_ip_dest_ip),
                .m_udp_source_port   (m_roce_udp_source_port),
                .m_udp_dest_port     (m_roce_udp_dest_port),
                .m_udp_length        (m_roce_udp_length),
                .m_udp_checksum      (m_roce_udp_checksum),

                .m_roce_payload_axis_tdata (m_roce_payload_axis_tdata),
                .m_roce_payload_axis_tkeep (m_roce_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
                .m_roce_payload_axis_tready(m_roce_payload_axis_tready),
                .m_roce_payload_axis_tlast (m_roce_payload_axis_tlast),
                .m_roce_payload_axis_tuser (m_roce_payload_axis_tuser),

                .m_axis_dma_read_desc_addr (m_axis_dma_read_desc_addr),
                .m_axis_dma_read_desc_len  (m_axis_dma_read_desc_len),
                .m_axis_dma_read_desc_valid(m_axis_dma_read_desc_valid),
                .m_axis_dma_read_desc_ready(m_axis_dma_read_desc_ready),

                .s_axis_dma_read_desc_status_len(),
                .s_axis_dma_read_desc_status_error(),
                .s_axis_dma_read_desc_status_valid(),

                .s_dma_read_axis_tdata (s_dma_read_axis_tdata),
                .s_dma_read_axis_tkeep (s_dma_read_axis_tkeep),
                .s_dma_read_axis_tvalid(s_dma_read_axis_tvalid),
                .s_dma_read_axis_tready(s_dma_read_axis_tready),
                .s_dma_read_axis_tlast (s_dma_read_axis_tlast),
                .s_dma_read_axis_tuser (s_dma_read_axis_tuser),

                .m_qp_close_valid  (qp_close_valid),
                .m_qp_close_ready  (qp_close_ready),
                .m_qp_close_loc_qpn(qp_close_loc_qpn),
                .m_qp_close_rem_psn(qp_close_rem_psn),

                .hdr_ram_re        (hdr_ram_re),
                .hdr_ram_addr      (hdr_ram_raddr),
                .hdr_ram_data      (hdr_ram_dout),
                .hdr_ram_data_valid(hdr_ram_dout_valid),

                .m_rd_table_we  (m_rd_table_we_rtr),
                .m_rd_table_qpn (m_rd_table_qpn_rtr),
                .m_rd_table_psn (m_rd_table_psn_rtr),

                .s_rd_table_re  (s_rd_table_re),
                .s_rd_table_qpn (s_rd_table_qpn),
                .s_rd_table_psn (s_rd_table_psn),

                .s_wr_table_re  (s_wr_table_re),
                .s_wr_table_qpn (s_wr_table_qpn),
                .s_wr_table_psn (s_wr_table_psn),

                .s_cpl_table_re (s_cpl_table_re),
                .s_cpl_table_qpn(s_cpl_table_qpn),
                .s_cpl_table_psn(s_cpl_table_psn),

                .mem_full(),
                .stall_qp(stall_qp),
                .loc_ip_addr(loc_ip_addr),
                .pmtu(pmtu),
                .timeout_period(32'd5000),
                .retry_count(3'd7),
                .rnr_retry_count(3'd7)
            );

            simple_dpram #(
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH-8),
                .DATA_WIDTH(200),
                .STRB_WIDTH(1),
                .NPIPES(2),
                .STYLE("auto")
            ) hdr_ram_instance (
                .clk(clk),
                .rst(rst),
                .waddr(hdr_ram_waddr),
                .raddr(hdr_ram_raddr),
                .din(hdr_ram_din),
                .dout(hdr_ram_dout),
                .strb(1),
                .ena(1'b1),
                .ren(hdr_ram_re),
                .wen(hdr_ram_we)
            );

            reg                       m_rd_table_we_rst;
            reg [$clog2(4)-1:0]       m_rd_table_qpn_rst;
            reg [24-1:0]              m_rd_table_psn_rst;

            reg                       m_wr_table_we_rst;
            reg [$clog2(4)-1:0]       m_wr_table_qpn_rst;
            reg [24-1:0]              m_wr_table_psn_rst;

            reg                       m_cpl_table_we_rst;
            reg [$clog2(4)-1:0]       m_cpl_table_qpn_rst;
            reg [24-1:0]              m_cpl_table_psn_rst;

            // when qp_close reset all table to same psn (24'hff_ffff)
            always @(posedge clk) begin
                if (rst) begin
                    m_rd_table_we_rst  <= 1'b0;
                    m_rd_table_qpn_rst <= 24'd0;
                    m_rd_table_psn_rst <= 24'd0;

                    m_wr_table_we_rst  <= 1'b0;
                    m_wr_table_qpn_rst <= 24'd0;
                    m_wr_table_psn_rst <= 24'd0;

                    m_cpl_table_we_rst  <= 1'b0;
                    m_cpl_table_qpn_rst <= 24'd0;
                    m_cpl_table_psn_rst <= 24'd0;
                end else begin
                    if (qp_close_valid || (cm_qp_valid && cm_qp_req_type == REQ_CLOSE_QP)) begin
                        m_rd_table_we_rst  <= 1'b1;
                        m_rd_table_qpn_rst <= qp_close_loc_qpn[$clog2(4)-1:0];
                        m_rd_table_psn_rst <= 24'hFF_FFFF;

                        m_wr_table_we_rst  <= 1'b1;
                        m_wr_table_qpn_rst <= qp_close_loc_qpn[$clog2(4)-1:0];
                        m_wr_table_psn_rst <= 24'hFF_FFFF;

                        m_cpl_table_we_rst  <= 1'b1;
                        m_cpl_table_qpn_rst <= qp_close_loc_qpn[$clog2(4)-1:0];
                        m_cpl_table_psn_rst <= 24'hFF_FFFF;
                    end else if (cm_qp_valid && cm_qp_req_type == REQ_OPEN_QP) begin
                        m_rd_table_we_rst  <= 1'b1;
                        m_rd_table_qpn_rst <= cm_qp_loc_qpn[$clog2(4)-1:0];
                        m_rd_table_psn_rst <= cm_qp_rem_psn - 24'd1;

                        m_wr_table_we_rst  <= 1'b1;
                        m_wr_table_qpn_rst <= cm_qp_loc_qpn[$clog2(4)-1:0];
                        m_wr_table_psn_rst <= cm_qp_rem_psn - 24'd1;

                        m_cpl_table_we_rst  <= 1'b1;
                        m_cpl_table_qpn_rst <= cm_qp_loc_qpn[$clog2(4)-1:0];
                        m_cpl_table_psn_rst <= cm_qp_rem_psn - 24'd1;
                    end else begin
                        m_rd_table_we_rst  <= 1'b0;
                        m_rd_table_qpn_rst <= 24'd0;
                        m_rd_table_psn_rst <= 24'd0;

                        m_wr_table_we_rst  <= 1'b0;
                        m_wr_table_qpn_rst <= 24'd0;
                        m_wr_table_psn_rst <= 24'd0;

                        m_cpl_table_we_rst  <= 1'b0;
                        m_cpl_table_qpn_rst <= 24'd0;
                        m_cpl_table_psn_rst <= 24'd0;
                    end
                end
            end

            assign m_rd_table_we  = m_rd_table_we_rst | m_rd_table_we_rtr; 
            assign m_rd_table_qpn = m_rd_table_we_rst ? m_rd_table_qpn_rst : m_rd_table_qpn_rtr;
            assign m_rd_table_psn = m_rd_table_we_rst ? m_rd_table_psn_rst : m_rd_table_psn_rtr;

            assign m_wr_table_we  = m_wr_table_we_rst | m_wr_table_we_rtr; 
            assign m_wr_table_qpn = m_wr_table_we_rst ? m_wr_table_qpn_rst : m_wr_table_qpn_rtr;
            assign m_wr_table_psn = m_wr_table_we_rst ? m_wr_table_psn_rst : m_wr_table_psn_rtr;


            always @(posedge clk) begin
                hdr_ram_dout_valid_pipes[3:0] <= {hdr_ram_dout_valid_pipes[2:0], hdr_ram_re};
            end
            assign hdr_ram_dout_valid = hdr_ram_dout_valid_pipes[3];

            simple_dpram #(
                .ADDR_WIDTH($clog2(4)),
                .DATA_WIDTH(24),
                .STRB_WIDTH(1),
                .NPIPES(-1),
                .INIT_VALUE(24'hff_ffff),
                .STYLE("auto")
            ) wr_table_instance (
                .clk(clk),
                .rst(rst),
                .waddr(m_wr_table_qpn),
                .raddr(s_wr_table_qpn),
                .din(m_wr_table_psn),
                .dout(s_wr_table_psn),
                .strb(1),
                .ena(1'b1),
                .ren(s_wr_table_re),
                .wen(m_wr_table_we)
            );

            simple_dpram #(
                .ADDR_WIDTH($clog2(4)),
                .DATA_WIDTH(24),
                .STRB_WIDTH(1),
                .NPIPES(-1),
                .INIT_VALUE(24'hff_ffff),
                .STYLE("auto")
            ) rd_table_instance (
                .clk(clk),
                .rst(rst),
                .waddr (m_rd_table_qpn),
                .raddr (s_rd_table_qpn),
                .din   (m_rd_table_psn),
                .dout  (s_rd_table_psn),
                .strb  (1),
                .ena   (1'b1),
                .ren   (s_rd_table_re),
                .wen   (m_rd_table_we)
            );

            assign m_cpl_table_we  = (s_roce_ack_aeth_valid & s_roce_ack_aeth_ready && s_roce_ack_bth_op_code == RC_RDMA_ACK && s_roce_ack_aeth_syndrome[6:5] == 2'b00) | m_cpl_table_we_rst;
            assign m_cpl_table_qpn = m_cpl_table_we_rst ? m_cpl_table_qpn_rst : s_roce_ack_bth_dest_qp;
            assign m_cpl_table_psn = m_cpl_table_we_rst ? m_cpl_table_psn_rst : s_roce_ack_bth_psn;

            simple_dpram #(
                .ADDR_WIDTH($clog2(4)),
                .DATA_WIDTH(24),
                .STRB_WIDTH(1),
                .NPIPES(-1),
                .INIT_VALUE(24'hff_ffff),
                .STYLE("auto")
            ) cpl_table_instance (
                .clk(clk),
                .rst(rst),
                .waddr (m_cpl_table_qpn),
                .raddr (s_cpl_table_qpn),
                .din   (m_cpl_table_psn),
                .dout  (s_cpl_table_psn),
                .strb  (1),
                .ena   (1'b1),
                .ren   (s_cpl_table_re),
                .wen   (m_cpl_table_we)
            );

            /*
    AXI fifo INTERFACE
    */
            wire [0                :0]                  m_axi_fifo_awid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_fifo_awaddr;
            wire [7:0]                                  m_axi_fifo_awlen;
            wire [2:0]                                  m_axi_fifo_awsize;
            wire [1:0]                                  m_axi_fifo_awburst;
            wire                                        m_axi_fifo_awlock;
            wire [3:0]                                  m_axi_fifo_awcache;
            wire [2:0]                                  m_axi_fifo_awprot;
            wire                                        m_axi_fifo_awvalid;
            wire                                        m_axi_fifo_awready;
            wire [DATA_WIDTH   - 1 : 0]                 m_axi_fifo_wdata;
            wire [DATA_WIDTH/8 - 1 : 0]                 m_axi_fifo_wstrb;
            wire                                        m_axi_fifo_wlast;
            wire                                        m_axi_fifo_wvalid;
            wire                                        m_axi_fifo_wready;
            wire [0             :0]                     m_axi_fifo_bid;
            wire [1:0]                                  m_axi_fifo_bresp;
            wire                                        m_axi_fifo_bvalid;
            wire                                        m_axi_fifo_bready;
            wire [0               :0]                   m_axi_fifo_arid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_fifo_araddr;
            wire [7:0]                                  m_axi_fifo_arlen;
            wire [2:0]                                  m_axi_fifo_arsize;
            wire [1:0]                                  m_axi_fifo_arburst;
            wire                                        m_axi_fifo_arlock;
            wire [3:0]                                  m_axi_fifo_arcache;
            wire [2:0]                                  m_axi_fifo_arprot;
            wire                                        m_axi_fifo_arvalid;
            wire                                        m_axi_fifo_arready;
            wire [0             :0]                     m_axi_fifo_rid;
            wire [DATA_WIDTH   - 1 : 0]                 m_axi_fifo_rdata;
            wire [1:0]                                  m_axi_fifo_rresp;
            wire                                        m_axi_fifo_rlast;
            wire                                        m_axi_fifo_rvalid;
            wire                                        m_axi_fifo_rready;


            axi_dma #(
                .AXI_DATA_WIDTH(DATA_WIDTH),
                .AXI_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .AXI_STRB_WIDTH(DATA_WIDTH/8),
                .AXI_ID_WIDTH(1),
                .AXI_MAX_BURST_LEN(256),
                .AXIS_DATA_WIDTH(DATA_WIDTH),
                .AXIS_KEEP_ENABLE(1),
                .AXIS_KEEP_WIDTH(DATA_WIDTH/8),
                .AXIS_LAST_ENABLE(1),
                .AXIS_ID_ENABLE(0),
                .AXIS_DEST_ENABLE(0),
                .AXIS_USER_ENABLE(1),
                .AXIS_USER_WIDTH(1),
                .LEN_WIDTH(13),
                .TAG_WIDTH(1),
                .ENABLE_SG(0),
                .ENABLE_UNALIGNED(1)
            ) axi_dma_instance (
                .clk(clk),
                .rst(rst),
                .s_axis_read_desc_addr         (m_axis_dma_read_desc_addr),
                .s_axis_read_desc_len          (m_axis_dma_read_desc_len),
                .s_axis_read_desc_tag          (0),
                .s_axis_read_desc_id           (0),
                .s_axis_read_desc_dest         (0),
                .s_axis_read_desc_user         (0),
                .s_axis_read_desc_valid        (m_axis_dma_read_desc_valid),
                .s_axis_read_desc_ready        (m_axis_dma_read_desc_ready),

                .m_axis_read_desc_status_tag   (),
                .m_axis_read_desc_status_error (),
                .m_axis_read_desc_status_valid (),

                .m_axis_read_data_tdata        (s_dma_read_axis_tdata),
                .m_axis_read_data_tkeep        (s_dma_read_axis_tkeep),
                .m_axis_read_data_tvalid       (s_dma_read_axis_tvalid),
                .m_axis_read_data_tready       (s_dma_read_axis_tready),
                .m_axis_read_data_tlast        (s_dma_read_axis_tlast),
                .m_axis_read_data_tid          (),
                .m_axis_read_data_tdest        (),
                .m_axis_read_data_tuser        (s_dma_read_axis_tuser),

                .s_axis_write_desc_addr        (m_axis_dma_write_desc_addr),
                .s_axis_write_desc_len         (m_axis_dma_write_desc_len),
                .s_axis_write_desc_tag         (1'b0),
                .s_axis_write_desc_valid       (m_axis_dma_write_desc_valid),
                .s_axis_write_desc_ready       (m_axis_dma_write_desc_ready),

                .m_axis_write_desc_status_len  (s_axis_dma_write_desc_status_len),
                .m_axis_write_desc_status_tag  (),
                .m_axis_write_desc_status_id   (),
                .m_axis_write_desc_status_dest (),
                .m_axis_write_desc_status_user (),
                .m_axis_write_desc_status_error(s_axis_dma_write_desc_status_error),
                .m_axis_write_desc_status_valid(s_axis_dma_write_desc_status_valid),

                .s_axis_write_data_tdata       (m_dma_write_axis_tdata),
                .s_axis_write_data_tkeep       (m_dma_write_axis_tkeep),
                .s_axis_write_data_tvalid      (m_dma_write_axis_tvalid),
                .s_axis_write_data_tready      (m_dma_write_axis_tready),
                .s_axis_write_data_tlast       (m_dma_write_axis_tlast),
                .s_axis_write_data_tid         (0),
                .s_axis_write_data_tdest       (0),
                .s_axis_write_data_tuser       (m_dma_write_axis_tuser),

                .m_axi_awid                    (m_axi_fifo_awid),
                .m_axi_awaddr                  (m_axi_fifo_awaddr),
                .m_axi_awlen                   (m_axi_fifo_awlen),
                .m_axi_awsize                  (m_axi_fifo_awsize),
                .m_axi_awburst                 (m_axi_fifo_awburst),
                .m_axi_awlock                  (m_axi_fifo_awlock),
                .m_axi_awcache                 (m_axi_fifo_awcache),
                .m_axi_awprot                  (m_axi_fifo_awprot),
                .m_axi_awvalid                 (m_axi_fifo_awvalid),
                .m_axi_awready                 (m_axi_fifo_awready),
                .m_axi_wdata                   (m_axi_fifo_wdata),
                .m_axi_wstrb                   (m_axi_fifo_wstrb),
                .m_axi_wlast                   (m_axi_fifo_wlast),
                .m_axi_wvalid                  (m_axi_fifo_wvalid),
                .m_axi_wready                  (m_axi_fifo_wready),
                .m_axi_bid                     (m_axi_fifo_bid),
                .m_axi_bresp                   (m_axi_fifo_bresp),
                .m_axi_bvalid                  (m_axi_fifo_bvalid),
                .m_axi_bready                  (m_axi_fifo_bready),
                .m_axi_arid                    (m_axi_fifo_arid),
                .m_axi_araddr                  (m_axi_fifo_araddr),
                .m_axi_arlen                   (m_axi_fifo_arlen),
                .m_axi_arsize                  (m_axi_fifo_arsize),
                .m_axi_arburst                 (m_axi_fifo_arburst),
                .m_axi_arlock                  (m_axi_fifo_arlock),
                .m_axi_arcache                 (m_axi_fifo_arcache),
                .m_axi_arprot                  (m_axi_fifo_arprot),
                .m_axi_arvalid                 (m_axi_fifo_arvalid),
                .m_axi_arready                 (m_axi_fifo_arready),
                .m_axi_rid                     (m_axi_fifo_rid),
                .m_axi_rdata                   (m_axi_fifo_rdata),
                .m_axi_rresp                   (m_axi_fifo_rresp),
                .m_axi_rlast                   (m_axi_fifo_rlast),
                .m_axi_rvalid                  (m_axi_fifo_rvalid),
                .m_axi_rready                  (m_axi_fifo_rready),
                .read_enable                   (1'b1),
                .write_enable                  (1'b1),
                .write_abort                   (1'b0)
            );

            axi_fifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .STRB_WIDTH(DATA_WIDTH/8),
                .READ_FIFO_DEPTH(64),
                .WRITE_FIFO_DEPTH(64),
                .ID_WIDTH(1)
            ) axi_fifo_instance (
                .clk(clk),
                .rst(rst),
                .s_axi_awid    (m_axi_fifo_awid),
                .s_axi_awaddr  (m_axi_fifo_awaddr),
                .s_axi_awlen   (m_axi_fifo_awlen),
                .s_axi_awsize  (m_axi_fifo_awsize),
                .s_axi_awburst (m_axi_fifo_awburst),
                .s_axi_awlock  (m_axi_fifo_awlock),
                .s_axi_awcache (m_axi_fifo_awcache),
                .s_axi_awprot  (m_axi_fifo_awprot),

                .s_axi_awvalid (m_axi_fifo_awvalid),
                .s_axi_awready (m_axi_fifo_awready),
                .s_axi_wdata   (m_axi_fifo_wdata),
                .s_axi_wstrb   (m_axi_fifo_wstrb),
                .s_axi_wlast   (m_axi_fifo_wlast),

                .s_axi_wvalid  (m_axi_fifo_wvalid),
                .s_axi_wready  (m_axi_fifo_wready),
                .s_axi_bid     (m_axi_fifo_bid),
                .s_axi_bresp   (m_axi_fifo_bresp),

                .s_axi_bvalid  (m_axi_fifo_bvalid),
                .s_axi_bready  (m_axi_fifo_bready),
                .s_axi_arid    (m_axi_fifo_arid),
                .s_axi_araddr  (m_axi_fifo_araddr),
                .s_axi_arlen   (m_axi_fifo_arlen),
                .s_axi_arsize  (m_axi_fifo_arsize),
                .s_axi_arburst (m_axi_fifo_arburst),
                .s_axi_arlock  (m_axi_fifo_arlock),
                .s_axi_arcache (m_axi_fifo_arcache),
                .s_axi_arprot  (m_axi_fifo_arprot),

                .s_axi_arvalid (m_axi_fifo_arvalid),
                .s_axi_arready (m_axi_fifo_arready),
                .s_axi_rid     (m_axi_fifo_rid),
                .s_axi_rdata   (m_axi_fifo_rdata),
                .s_axi_rresp   (m_axi_fifo_rresp),
                .s_axi_rlast   (m_axi_fifo_rlast),

                .s_axi_rvalid  (m_axi_fifo_rvalid),
                .s_axi_rready  (m_axi_fifo_rready),
                .m_axi_awid    (m_axi_awid),
                .m_axi_awaddr  (m_axi_awaddr),
                .m_axi_awlen   (m_axi_awlen),
                .m_axi_awsize  (m_axi_awsize),
                .m_axi_awburst (m_axi_awburst),
                .m_axi_awlock  (m_axi_awlock),
                .m_axi_awcache (m_axi_awcache),
                .m_axi_awprot  (m_axi_awprot),
                //.m_axi_awqos   (m_axi_awqos),
                //.m_axi_awregion(m_axi_awregion),
                //.m_axi_awuser  (m_axi_awuser),
                .m_axi_awvalid (m_axi_awvalid),
                .m_axi_awready (m_axi_awready),
                .m_axi_wdata   (m_axi_wdata),
                .m_axi_wstrb   (m_axi_wstrb),
                .m_axi_wlast   (m_axi_wlast),
                //.m_axi_wuser   (m_axi_wuser),
                .m_axi_wvalid  (m_axi_wvalid),
                .m_axi_wready  (m_axi_wready),
                .m_axi_bid     (m_axi_bid),
                .m_axi_bresp   (m_axi_bresp),
                //.m_axi_buser   (m_axi_buser),
                .m_axi_bvalid  (m_axi_bvalid),
                .m_axi_bready  (m_axi_bready),
                .m_axi_arid    (m_axi_arid),
                .m_axi_araddr  (m_axi_araddr),
                .m_axi_arlen   (m_axi_arlen),
                .m_axi_arsize  (m_axi_arsize),
                .m_axi_arburst (m_axi_arburst),
                .m_axi_arlock  (m_axi_arlock),
                .m_axi_arcache (m_axi_arcache),
                .m_axi_arprot  (m_axi_arprot),
                //.m_axi_arqos   (m_axi_arqos),
                //.m_axi_arregion(m_axi_arregion),
                //.m_axi_aruser  (m_axi_aruser),
                .m_axi_arvalid (m_axi_arvalid),
                .m_axi_arready (m_axi_arready),
                .m_axi_rid     (m_axi_rid),
                .m_axi_rdata   (m_axi_rdata),
                .m_axi_rresp   (m_axi_rresp),
                .m_axi_rlast   (m_axi_rlast),
                //.m_axi_ruser   (m_axi_ruser),
                .m_axi_rvalid  (m_axi_rvalid),
                .m_axi_rready  (m_axi_rready)
            );

            axi_ram_mod #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .STRB_WIDTH(DATA_WIDTH/8),
                .ID_WIDTH(1)
            ) RoCE_axi_ram_mod_instance (
                .clk(clk),
                .rst(rst),
                .s_axi_awid   (m_axi_awid),
                .s_axi_awaddr (m_axi_awaddr),
                .s_axi_awlen  (m_axi_awlen),
                .s_axi_awsize (m_axi_awsize),
                .s_axi_awburst(m_axi_awburst),
                .s_axi_awlock (m_axi_awlock),
                .s_axi_awcache(m_axi_awcache),
                .s_axi_awprot (m_axi_awprot),
                .s_axi_awvalid(m_axi_awvalid),
                .s_axi_awready(m_axi_awready),
                .s_axi_wdata  (m_axi_wdata),
                .s_axi_wstrb  (m_axi_wstrb),
                .s_axi_wlast  (m_axi_wlast),
                .s_axi_wvalid (m_axi_wvalid),
                .s_axi_wready (m_axi_wready),
                .s_axi_bid    (m_axi_bid),
                .s_axi_bresp  (m_axi_bresp),
                .s_axi_bvalid (m_axi_bvalid),
                .s_axi_bready (m_axi_bready),
                .s_axi_arid   (m_axi_arid),
                .s_axi_araddr (m_axi_araddr),
                .s_axi_arlen  (m_axi_arlen),
                .s_axi_arsize (m_axi_arsize),
                .s_axi_arburst(m_axi_arburst),
                .s_axi_arlock (m_axi_arlock),
                .s_axi_arcache(m_axi_arcache),
                .s_axi_arprot (m_axi_arprot),
                .s_axi_arvalid(m_axi_arvalid),
                .s_axi_arready(m_axi_arready),
                .s_axi_rid    (m_axi_rid),
                .s_axi_rdata  (m_axi_rdata),
                .s_axi_rresp  (m_axi_rresp),
                .s_axi_rlast  (m_axi_rlast),
                .s_axi_rvalid (m_axi_rvalid),
                .s_axi_rready (m_axi_rready)
            );

        end else begin

            assign m_roce_bth_valid                      = m_roce_to_retrans_bth_valid;
            assign m_roce_to_retrans_bth_ready           = m_roce_bth_ready;
            assign m_roce_bth_op_code                    = m_roce_to_retrans_bth.op_code;
            assign m_roce_bth_p_key                      = m_roce_to_retrans_bth.p_key;
            assign m_roce_bth_psn                        = m_roce_to_retrans_bth.psn;
            assign m_roce_bth_dest_qp                    = m_roce_to_retrans_bth.qp_number;
            assign m_roce_bth_src_qp                     = m_roce_to_retrans_bth_src_qp;
            assign m_roce_bth_ack_req                    = m_roce_to_retrans_bth.ack_request;
            assign m_roce_reth_valid                     = m_roce_to_retrans_reth_valid;
            assign m_roce_to_retrans_reth_ready          = m_roce_reth_ready;
            assign m_roce_reth_v_addr                    = m_roce_to_retrans_reth.vaddr;
            assign m_roce_reth_r_key                     = m_roce_to_retrans_reth.r_key;
            assign m_roce_reth_length                    = m_roce_to_retrans_reth.dma_length;
            assign m_roce_immdh_valid                    = m_roce_to_retrans_immdh_valid;
            assign m_roce_to_retrans_immdh_ready         = m_roce_immdh_ready;
            assign m_roce_immdh_data                     = m_roce_to_retrans_immdh.immediate_data;
            assign m_roce_eth_dest_mac                   = m_roce_to_retrans_eth_dest_mac;
            assign m_roce_eth_src_mac                    = m_roce_to_retrans_eth_src_mac;
            assign m_roce_eth_type                       = m_roce_to_retrans_eth_type;
            assign m_roce_ip_version                     = m_roce_to_retrans_ip_version;
            assign m_roce_ip_ihl                         = m_roce_to_retrans_ip_ihl;
            assign m_roce_ip_dscp                        = m_roce_to_retrans_ip_dscp;
            assign m_roce_ip_ecn                         = m_roce_to_retrans_ip_ecn;
            assign m_roce_ip_identification              = m_roce_to_retrans_ip_identification;
            assign m_roce_ip_flags                       = m_roce_to_retrans_ip_flags;
            assign m_roce_ip_fragment_offset             = m_roce_to_retrans_ip_fragment_offset;
            assign m_roce_ip_ttl                         = m_roce_to_retrans_ip_ttl;
            assign m_roce_ip_protocol                    = m_roce_to_retrans_ip_protocol;
            assign m_roce_ip_header_checksum             = m_roce_to_retrans_ip_header_checksum;
            assign m_roce_ip_source_ip                   = m_roce_to_retrans_ip_source_ip;
            assign m_roce_ip_dest_ip                     = m_roce_to_retrans_ip_dest_ip;
            assign m_roce_udp_source_port                = m_roce_to_retrans_udp_source_port;
            assign m_roce_udp_dest_port                  = m_roce_to_retrans_udp_dest_port;
            assign m_roce_udp_length                     = m_roce_to_retrans_udp_length;
            assign m_roce_udp_checksum                   = m_roce_to_retrans_udp_checksum;
            assign m_roce_payload_axis_tdata             = m_roce_to_retrans_payload_axis_tdata;
            assign m_roce_payload_axis_tkeep             = m_roce_to_retrans_payload_axis_tkeep;
            assign m_roce_payload_axis_tvalid            = m_roce_to_retrans_payload_axis_tvalid;
            assign m_roce_to_retrans_payload_axis_tready = m_roce_payload_axis_tready;
            assign m_roce_payload_axis_tlast             = m_roce_to_retrans_payload_axis_tlast;
            assign m_roce_payload_axis_tuser             = m_roce_to_retrans_payload_axis_tuser;

            assign qp_close_valid   = 1'b0;
            assign qp_close_loc_qpn = 24'd256;

            assign stop_transfer = stop_transfer_nack;
        end
    endgenerate

    assign wr_error_qp_not_rts_out = wr_error_qp_not_rts;
    assign wr_error_loc_qpn_out    = wr_error_loc_qpn;

    assign s_roce_ack_bth_ready = s_roce_ack_aeth_ready;


endmodule

`resetall