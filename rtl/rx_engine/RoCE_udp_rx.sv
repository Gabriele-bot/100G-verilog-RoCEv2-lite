
`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * RoCE UDP RX, ACKs and CNPs
 */
module RoCE_udp_rx #(
    parameter DATA_WIDTH     = 256,
    parameter KEEP_ENABLE    = (DATA_WIDTH > 8),
    parameter KEEP_WIDTH     = (DATA_WIDTH / 8),
    parameter EN_DCQCN_LOGIC = 1
) (
    input wire clk,
    input wire rst,

    // UDP frame input
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
    input  wire [DATA_WIDTH-1:0] s_udp_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_udp_payload_axis_tkeep,
    input  wire                  s_udp_payload_axis_tvalid,
    output wire                  s_udp_payload_axis_tready,
    input  wire                  s_udp_payload_axis_tlast,
    input  wire                  s_udp_payload_axis_tuser,

    // AETH output
    output wire        m_roce_aeth_hdr_valid,
    input  wire        m_roce_aeth_hdr_ready,
    output wire [23:0] m_roce_aeth_dest_qp, // BTH QPN
    output wire [23:0] m_roce_aeth_psn, // BTH PSN
    output wire [ 7:0] m_roce_aeth_syndrome,
    output wire [23:0] m_roce_aeth_msn,
    output wire [31:0] m_roce_aeth_icrc,

    // CNP output: QPN from BTH, ICRC
    output wire        m_roce_cnp_hdr_valid,
    input  wire        m_roce_cnp_hdr_ready,
    output wire [23:0] m_roce_cnp_dest_qp, // BTH QPN
    output wire [31:0] m_roce_cnp_icrc,

    // Status
    output wire busy,
    output wire error_header_early_termination,
    output wire error_payload_early_termination
);

    import RoCE_params::*; // Imports RoCE parameters

    wire        bth_hdr_valid;
    wire        bth_hdr_ready;
    wire [ 7:0] bth_op_code;
    wire        bth_sol_event;
    wire        bth_mig_req;
    wire [ 1:0] bth_pad_count;
    wire [ 3:0] bth_hdr_version;
    wire [15:0] bth_p_key;
    wire        bth_fecn;
    wire        bth_becn;
    wire [23:0] bth_dest_qp;
    wire        bth_ack_req;
    wire [23:0] bth_psn;

    wire [DATA_WIDTH-1:0] bth_payload_tdata;
    wire [KEEP_WIDTH-1:0] bth_payload_tkeep;
    wire                  bth_payload_tvalid;
    wire                  bth_payload_tready;
    wire                  bth_payload_tlast;
    wire                  bth_payload_tuser;

    wire route_aeth_comb = (bth_op_code == RC_RDMA_ACK);
    wire route_cnp_comb  = (bth_op_code == RoCE_CNP);

    reg route_aeth_reg = 1'b0;
    reg route_cnp_reg  = 1'b0;
    reg drop_reg       = 1'b0;

    wire payload_end = bth_payload_tvalid && bth_payload_tready && bth_payload_tlast;

    always @(posedge clk) begin
        if (bth_hdr_valid && bth_hdr_ready) begin
            route_aeth_reg <= route_aeth_comb;
            route_cnp_reg  <= route_cnp_comb;
            drop_reg       <= !route_aeth_comb && !route_cnp_comb;
        end

        if (payload_end) begin
            route_aeth_reg <= 1'b0;
            route_cnp_reg  <= 1'b0;
            drop_reg       <= 1'b0;
        end

        if (rst) begin
            route_aeth_reg <= 1'b0;
            route_cnp_reg  <= 1'b0;
            drop_reg       <= 1'b0;
        end
    end


    wire s_aeth_bth_hdr_valid = bth_hdr_valid && route_aeth_comb;
    wire s_cnp_bth_hdr_valid  = bth_hdr_valid && route_cnp_comb;

    wire s_aeth_bth_hdr_ready;
    wire s_cnp_bth_hdr_ready;

    assign bth_hdr_ready = route_aeth_comb ? s_aeth_bth_hdr_ready :
    route_cnp_comb  ? s_cnp_bth_hdr_ready  : 1'b1;


    wire s_aeth_bth_payload_tready;
    wire s_cnp_bth_payload_tready;

    wire s_aeth_bth_payload_tvalid = bth_payload_tvalid && route_aeth_reg;
    wire s_cnp_bth_payload_tvalid  = bth_payload_tvalid && route_cnp_reg;

    assign bth_payload_tready = route_aeth_reg ? s_aeth_bth_payload_tready :
    route_cnp_reg  ? s_cnp_bth_payload_tready  : 1'b1;

    wire        aeth_busy;
    wire        aeth_error_hdr;

    RoCE_aeth_bth_rx #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KEEP_ENABLE (KEEP_ENABLE),
        .KEEP_WIDTH  (KEEP_WIDTH)
    ) u_aeth_rx (
        .clk                          (clk),
        .rst                          (rst),

        .s_roce_bth_hdr_valid         (s_aeth_bth_hdr_valid),
        .s_roce_bth_hdr_ready         (s_aeth_bth_hdr_ready),
        .s_roce_bth_op_code           (bth_op_code),
        .s_roce_bth_sol_event         (bth_sol_event),
        .s_roce_bth_mig_req           (bth_mig_req),
        .s_roce_bth_pad_count         (bth_pad_count),
        .s_roce_bth_hdr_version       (bth_hdr_version),
        .s_roce_bth_p_key             (bth_p_key),
        .s_roce_bth_fecn              (bth_fecn),
        .s_roce_bth_becn              (bth_becn),
        .s_roce_bth_dest_qp           (bth_dest_qp),
        .s_roce_bth_ack_req           (bth_ack_req),
        .s_roce_bth_psn               (bth_psn),

        .s_roce_bth_payload_axis_tdata  (bth_payload_tdata),
        .s_roce_bth_payload_axis_tkeep  (bth_payload_tkeep),
        .s_roce_bth_payload_axis_tvalid (s_aeth_bth_payload_tvalid),
        .s_roce_bth_payload_axis_tready (s_aeth_bth_payload_tready),
        .s_roce_bth_payload_axis_tlast  (bth_payload_tlast),
        .s_roce_bth_payload_axis_tuser  (bth_payload_tuser),

        .m_roce_aeth_hdr_valid        (m_roce_aeth_hdr_valid),
        .m_roce_aeth_hdr_ready        (m_roce_aeth_hdr_ready),
        .m_roce_bth_op_code           (),
        .m_roce_bth_sol_event         (),
        .m_roce_bth_mig_req           (),
        .m_roce_bth_pad_count         (),
        .m_roce_bth_hdr_version       (),
        .m_roce_bth_p_key             (),
        .m_roce_bth_fecn              (),
        .m_roce_bth_becn              (),
        .m_roce_bth_dest_qp           (m_roce_aeth_dest_qp),
        .m_roce_bth_ack_req           (),
        .m_roce_bth_psn               (m_roce_aeth_psn),
        .m_roce_aeth_syndrome         (m_roce_aeth_syndrome),
        .m_roce_aeth_msn              (m_roce_aeth_msn),
        .m_roce_icrc                  (m_roce_aeth_icrc),
        .busy                         (aeth_busy),
        .error_header_early_termination (aeth_error_hdr)
    );

    wire cnp_busy;
    wire cnp_error_hdr;

    generate
        if (EN_DCQCN_LOGIC)begin
            RoCE_cnp_bth_rx #(
                .DATA_WIDTH  (DATA_WIDTH),
                .KEEP_ENABLE (KEEP_ENABLE),
                .KEEP_WIDTH  (KEEP_WIDTH)
            ) u_cnp_rx (
                .clk                          (clk),
                .rst                          (rst),

                .s_roce_bth_hdr_valid         (s_cnp_bth_hdr_valid),
                .s_roce_bth_hdr_ready         (s_cnp_bth_hdr_ready),
                .s_roce_bth_op_code           (bth_op_code),
                .s_roce_bth_sol_event         (bth_sol_event),
                .s_roce_bth_mig_req           (bth_mig_req),
                .s_roce_bth_pad_count         (bth_pad_count),
                .s_roce_bth_hdr_version       (bth_hdr_version),
                .s_roce_bth_p_key             (bth_p_key),
                .s_roce_bth_fecn              (bth_fecn),
                .s_roce_bth_becn              (bth_becn),
                .s_roce_bth_dest_qp           (bth_dest_qp),
                .s_roce_bth_ack_req           (bth_ack_req),
                .s_roce_bth_psn               (bth_psn),

                .s_roce_bth_payload_axis_tdata  (bth_payload_tdata),
                .s_roce_bth_payload_axis_tkeep  (bth_payload_tkeep),
                .s_roce_bth_payload_axis_tvalid (s_cnp_bth_payload_tvalid),
                .s_roce_bth_payload_axis_tready (s_cnp_bth_payload_tready),
                .s_roce_bth_payload_axis_tlast  (bth_payload_tlast),
                .s_roce_bth_payload_axis_tuser  (bth_payload_tuser),

                .m_roce_cnp_hdr_valid         (m_roce_cnp_hdr_valid),
                .m_roce_cnp_hdr_ready         (m_roce_cnp_hdr_ready),
                .m_roce_bth_op_code           (),
                .m_roce_bth_sol_event         (),
                .m_roce_bth_mig_req           (),
                .m_roce_bth_pad_count         (),
                .m_roce_bth_hdr_version       (),
                .m_roce_bth_p_key             (),
                .m_roce_bth_fecn              (),
                .m_roce_bth_becn              (),
                .m_roce_bth_dest_qp           (m_roce_cnp_dest_qp),
                .m_roce_bth_ack_req           (),
                .m_roce_bth_psn               (),
                .m_roce_icrc                  (m_roce_cnp_icrc),
                .busy                         (cnp_busy),
                .error_header_early_termination (cnp_error_hdr)
            );
        end else begin
            assign s_cnp_bth_hdr_ready      = 1'b1;
            assign s_cnp_bth_payload_tready = 1'b1;
            assign m_roce_cnp_hdr_valid     = 1'b0;
            assign cnp_busy                 = 1'b0;
            assign cnp_error_hdr            = 1'b0;
        end
    endgenerate


    wire bth_busy;
    wire bth_error_hdr;
    wire bth_error_payload;


    wire [47:0] bth_eth_dest_mac;
    wire [47:0] bth_eth_src_mac;
    wire [15:0] bth_eth_type;
    wire [ 3:0] bth_ip_version;
    wire [ 3:0] bth_ip_ihl;
    wire [ 5:0] bth_ip_dscp;
    wire [ 1:0] bth_ip_ecn;
    wire [15:0] bth_ip_length;
    wire [15:0] bth_ip_identification;
    wire [ 2:0] bth_ip_flags;
    wire [12:0] bth_ip_fragment_offset;
    wire [ 7:0] bth_ip_ttl;
    wire [ 7:0] bth_ip_protocol;
    wire [15:0] bth_ip_header_checksum;
    wire [31:0] bth_ip_source_ip;
    wire [31:0] bth_ip_dest_ip;
    wire [15:0] bth_udp_source_port;
    wire [15:0] bth_udp_dest_port;
    wire [15:0] bth_udp_length;
    wire [15:0] bth_udp_checksum;

    RoCE_bth_udp_rx #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KEEP_ENABLE (KEEP_ENABLE),
        .KEEP_WIDTH  (KEEP_WIDTH)
    ) u_bth_rx (
        .clk                             (clk),
        .rst                             (rst),

        // UDP input
        .s_udp_hdr_valid                 (s_udp_hdr_valid),
        .s_udp_hdr_ready                 (s_udp_hdr_ready),
        .s_eth_dest_mac                  (s_eth_dest_mac),
        .s_eth_src_mac                   (s_eth_src_mac),
        .s_eth_type                      (s_eth_type),
        .s_ip_version                    (s_ip_version),
        .s_ip_ihl                        (s_ip_ihl),
        .s_ip_dscp                       (s_ip_dscp),
        .s_ip_ecn                        (s_ip_ecn),
        .s_ip_length                     (s_ip_length),
        .s_ip_identification             (s_ip_identification),
        .s_ip_flags                      (s_ip_flags),
        .s_ip_fragment_offset            (s_ip_fragment_offset),
        .s_ip_ttl                        (s_ip_ttl),
        .s_ip_protocol                   (s_ip_protocol),
        .s_ip_header_checksum            (s_ip_header_checksum),
        .s_ip_source_ip                  (s_ip_source_ip),
        .s_ip_dest_ip                    (s_ip_dest_ip),
        .s_udp_source_port               (s_udp_source_port),
        .s_udp_dest_port                 (s_udp_dest_port),
        .s_udp_length                    (s_udp_length),
        .s_udp_checksum                  (s_udp_checksum),
        .s_udp_payload_axis_tdata        (s_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep        (s_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid       (s_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready       (s_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast        (s_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser        (s_udp_payload_axis_tuser),

        // BTH header output
        .m_roce_bth_hdr_valid            (bth_hdr_valid),
        .m_roce_bth_hdr_ready            (bth_hdr_ready),
        .m_eth_dest_mac                  (bth_eth_dest_mac),
        .m_eth_src_mac                   (bth_eth_src_mac),
        .m_eth_type                      (bth_eth_type),
        .m_ip_version                    (bth_ip_version),
        .m_ip_ihl                        (bth_ip_ihl),
        .m_ip_dscp                       (bth_ip_dscp),
        .m_ip_ecn                        (bth_ip_ecn),
        .m_ip_length                     (bth_ip_length),
        .m_ip_identification             (bth_ip_identification),
        .m_ip_flags                      (bth_ip_flags),
        .m_ip_fragment_offset            (bth_ip_fragment_offset),
        .m_ip_ttl                        (bth_ip_ttl),
        .m_ip_protocol                   (bth_ip_protocol),
        .m_ip_header_checksum            (bth_ip_header_checksum),
        .m_ip_source_ip                  (bth_ip_source_ip),
        .m_ip_dest_ip                    (bth_ip_dest_ip),
        .m_udp_source_port               (bth_udp_source_port),
        .m_udp_dest_port                 (bth_udp_dest_port),
        .m_udp_length                    (bth_udp_length),
        .m_udp_checksum                  (bth_udp_checksum),
        .m_roce_bth_op_code              (bth_op_code),
        .m_roce_bth_sol_event            (bth_sol_event),
        .m_roce_bth_mig_req              (bth_mig_req),
        .m_roce_bth_pad_count            (bth_pad_count),
        .m_roce_bth_hdr_version          (bth_hdr_version),
        .m_roce_bth_p_key                (bth_p_key),
        .m_roce_bth_fecn                 (bth_fecn),
        .m_roce_bth_becn                 (bth_becn),
        .m_roce_bth_dest_qp              (bth_dest_qp),
        .m_roce_bth_ack_req              (bth_ack_req),
        .m_roce_bth_psn                  (bth_psn),

        // BTH payload stream
        .m_roce_bth_payload_axis_tdata   (bth_payload_tdata),
        .m_roce_bth_payload_axis_tkeep   (bth_payload_tkeep),
        .m_roce_bth_payload_axis_tvalid  (bth_payload_tvalid),
        .m_roce_bth_payload_axis_tready  (bth_payload_tready),
        .m_roce_bth_payload_axis_tlast   (bth_payload_tlast),
        .m_roce_bth_payload_axis_tuser   (bth_payload_tuser),

        .busy                            (bth_busy),
        .error_header_early_termination  (bth_error_hdr),
        .error_payload_early_termination (bth_error_payload)
    );

    assign busy                        = bth_busy | aeth_busy | cnp_busy;
    assign error_header_early_termination  = bth_error_hdr | aeth_error_hdr | cnp_error_hdr;
    assign error_payload_early_termination = bth_error_payload;

endmodule

`resetall
