
`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_udp_tx_simple  #(
    parameter DATA_WIDTH          = 256
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire [ 31:0] s_roce_immdh_data,
    // udp, ip
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
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
    // payload
    input  wire [DATA_WIDTH-1   : 0] s_roce_payload_axis_tdata,
    input  wire [DATA_WIDTH/8-1 : 0] s_roce_payload_axis_tkeep,
    input  wire                      s_roce_payload_axis_tvalid,
    output wire                      s_roce_payload_axis_tready,
    input  wire                      s_roce_payload_axis_tlast,
    input  wire                      s_roce_payload_axis_tuser,
    /*
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    output wire         m_udp_hdr_ready,

    output wire [  3:0] m_ip_version,
    output wire [  3:0] m_ip_ihl,
    output wire [  5:0] m_ip_dscp,
    output wire [  1:0] m_ip_ecn,
    output wire [ 15:0] m_ip_length,
    output wire [ 15:0] m_ip_identification,
    output wire [  2:0] m_ip_flags,
    output wire [ 12:0] m_ip_fragment_offset,
    output wire [  7:0] m_ip_ttl,
    output wire [  7:0] m_ip_protocol,
    output wire [ 15:0] m_ip_header_checksum,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [ 15:0] m_udp_source_port,
    output wire [ 15:0] m_udp_dest_port,
    output wire [ 15:0] m_udp_length,
    output wire [ 15:0] m_udp_checksum,
    output wire [DATA_WIDTH-1   : 0] m_udp_payload_axis_tdata ,
    output wire [DATA_WIDTH/8-1 : 0] m_udp_payload_axis_tkeep ,
    output wire                      m_udp_payload_axis_tvalid,
    input  wire                      m_udp_payload_axis_tready,
    output wire                      m_udp_payload_axis_tlast ,
    output wire                      m_udp_payload_axis_tuser ,
    /*
     * Status signals
     */
    output wire         busy,
    output wire         error_payload_early_termination
);

    /*

RoCE RDMA WRITE Frame.

RDMA WRITE FIRST or RMDA WRITE ONLY
IP_HDR + UDP_HDR + BTH + RETH + PAYLOAD + ICRC
RMDA WRITE ONLY with IMMD + PAYLOAD + ICRC
IP_HDR + UDP_HDR +BTH + RETH + IMMD + PAYLOAD + ICRC
RDMA WRITE MIDDLE or RMDA WRITE LAST
IP_HDR + UDP_HDR +BTH + PAYLOAD + ICRC
RMDA WRITE LAST with IMMD + PAYLOAD + ICRC
IP_HDR + UDP_HDR +BTH + IMMD + PAYLOAD + ICRC
`include "RoCE_parameters.svh"

+--------------------------------------+
|                BTH                   |
+--------------------------------------+
 Field                       Length
 OP code                     1 octet
 Solicited Event             1 bit
 Mig request                 1 bit
 Pad count                   2 bits
 Header version              4 bits
 Partition key               2 octets
 Reserved                    1 octet
 Queue Pair Number           3 octets
 Ack request                 1 bit
 Reserved                    7 bits
 Packet Sequence Number      3 octets
+--------------------------------------+
|               RETH                   |
+--------------------------------------+
 Field                       Length
 Remote Address              8 octets
 R key                       4 octets
 DMA length                  4 octets
+--------------------------------------+
|               IMMD                   |
+--------------------------------------+
 Field                       Length
 Immediate data              4 octets
+--------------------------------------+
|               AETH                   |
+--------------------------------------+
 Field                       Length
 Syndrome                    1 octet
 Message Sequence Number     3 octets
 
 payload                     length octets
+--------------------------------------+
|               ICRC                   |
+--------------------------------------+
 Field                       Length
 ICRC field                  4 octets

This module receives a RoCEv2 frame with headers fields in parallel along with the
payload in an AXI stream, combines the headers with the payload, passes through
the UDP headers, and transmits the complete UDP payload on an AXI interface.

*/

    import RoCE_params::*; // Imports RoCE parameters

    // bus width assertions
    initial begin
        if (DATA_WIDTH < 256) begin
            $error("Error: AXIS data width must be greater than 256 (instance %m)");
            $finish;
        end

        if (DATA_WIDTH > 2048) begin
            $error("Error: AXIS data width must be smaller than 2048 (instance %m)");
            $finish;
        end
    end

    wire ip_hdr_t        s_ip_header;
    wire udp_hdr_t       s_udp_header;
    wire roce_bth_hdr_t  s_bth, s_bth_post_immd_prepend;
    wire roce_reth_hdr_t s_reth;
    wire roce_immd_hdr_t s_immdh;

    wire ip_hdr_t        m_ip_header;
    wire udp_hdr_t       m_udp_header;



    assign {s_ip_header.header_version, s_ip_header.ihl, s_ip_header.dscp, s_ip_header.ecn} = {<<byte {s_ip_version, s_ip_ihl, s_ip_dscp, s_ip_ecn}};
    assign s_ip_header.length                               = {<<byte {s_udp_length + 16'd20}};
    assign s_ip_header.identification                       = {<<byte {s_ip_identification}};
    assign {s_ip_header.flags, s_ip_header.fragment_offset} = {<<byte {s_ip_flags, s_ip_fragment_offset}};
    assign s_ip_header.ttl                                  = s_ip_ttl;
    assign s_ip_header.protocol                             = s_ip_protocol;
    assign s_ip_header.header_checksum                      = {<<byte {s_ip_header_checksum}};
    assign s_ip_header.src_address                          = {<<byte {s_ip_source_ip}};
    assign s_ip_header.dest_address                         = {<<byte {s_ip_dest_ip}};

    assign s_udp_header.src_port  = {<<byte {s_udp_source_port}};
    assign s_udp_header.dest_port = {<<byte {s_udp_dest_port}};
    assign s_udp_header.length    = {<<byte {s_udp_length}};
    assign s_udp_header.checksum  = {<<byte {s_udp_checksum}};

    wire sol_event = s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD | s_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD |
    s_roce_bth_op_code == RC_SEND_LAST           | s_roce_bth_op_code == RC_SEND_LAST_IMD |
    s_roce_bth_op_code == RC_SEND_ONLY           | s_roce_bth_op_code == RC_SEND_ONLY_IMD;

    assign s_bth.op_code = {<<byte {s_roce_bth_op_code}};
    assign {s_bth.sol_event, s_bth.mig_request, s_bth.pad_count, s_bth.header_version} = {sol_event, 1'b1, 2'd0, 4'd0};
    assign s_bth.p_key = {<<byte {s_roce_bth_p_key}};
    assign s_bth.qp_number = {<<byte {s_roce_bth_dest_qp}};
    assign {s_bth.ack_request, s_bth.reserved_1}  = {s_roce_bth_ack_req, 7'd0};
    assign s_bth.psn = {<<byte {s_roce_bth_psn}};
    assign s_bth.reserved_0 = 8'd0;

    assign s_reth.vaddr = {<<byte {s_roce_reth_v_addr}};
    assign s_reth.r_key = {<<byte {s_roce_reth_r_key}};
    assign s_reth.dma_length = {<<byte {s_roce_reth_length}};

    assign s_immdh.immediate_data = {<<byte {s_roce_immdh_data}};

    // First stage selection, either IMMD, RETH or BTH
    // decide if IMMD is needed
    wire s_select_1stg_immd  = (s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD || s_roce_bth_op_code == RC_SEND_ONLY_IMD
    || s_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD || s_roce_bth_op_code == RC_SEND_LAST_IMD);
    reg  s_select_1stg_immd_reg = 1'b0;
    // decide if RETH is needed
    wire s_select_1stg_reth  = (s_roce_bth_op_code == s_roce_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_bth_op_code == RC_RDMA_WRITE_FIRST);
    reg  s_select_1stg_reth_reg = 1'b0;
    // decide if BTH is needed
    wire s_select_1stg_bth  = !(s_select_1stg_immd | s_select_1stg_reth);
    reg  s_select_1stg_bth_reg = 1'b0;

    wire [(12+16)*8-1:0] m_hdr_immd;

    // to immd prepend module
    wire                        s_immd_prepend_ready;
    wire                        s_immd_prepend_valid;
    wire [(20+8+12+16+4)*8-1:0] s_immd_prepend_header;
    wire [DATA_WIDTH-1   : 0]   s_roce_payload_immd_prepend_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0]   s_roce_payload_immd_prepend_axis_tkeep;
    wire                        s_roce_payload_immd_prepend_axis_tvalid;
    wire                        s_roce_payload_immd_prepend_axis_tready;
    wire                        s_roce_payload_immd_prepend_axis_tlast;
    wire                        s_roce_payload_immd_prepend_axis_tuser;

    // from immd prepend module
    wire                      m_immd_prepend_valid;
    wire                      m_immd_prepend_ready;
    wire [(20+8+12+16)*8-1:0] m_immd_prepend_header;
    wire [DATA_WIDTH-1   : 0] m_roce_payload_immd_prepend_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] m_roce_payload_immd_prepend_axis_tkeep;
    wire                      m_roce_payload_immd_prepend_axis_tvalid;
    wire                      m_roce_payload_immd_prepend_axis_tready;
    wire                      m_roce_payload_immd_prepend_axis_tlast;
    wire                      m_roce_payload_immd_prepend_axis_tuser;

    // to reth arb mux
    wire                      s_reth_arb_mux_from_input_ready;
    wire                      s_reth_arb_mux_from_input_valid;
    wire [(20+8+12+16)*8-1:0] s_reth_arb_mux_from_input_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_reth_arb_mux_from_input_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_reth_arb_mux_from_input_axis_tkeep;
    wire                      s_roce_payload_reth_arb_mux_from_input_axis_tvalid;
    wire                      s_roce_payload_reth_arb_mux_from_input_axis_tready;
    wire                      s_roce_payload_reth_arb_mux_from_input_axis_tlast;
    wire                      s_roce_payload_reth_arb_mux_from_input_axis_tuser;

    wire                      s_reth_arb_mux_from_immd_ready;
    wire                      s_reth_arb_mux_from_immd_valid;
    wire [(20+8+12+16)*8-1:0] s_reth_arb_mux_from_immd_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_reth_arb_mux_from_immd_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_reth_arb_mux_from_immd_axis_tkeep;
    wire                      s_roce_payload_reth_arb_mux_from_immd_axis_tvalid;
    wire                      s_roce_payload_reth_arb_mux_from_immd_axis_tready;
    wire                      s_roce_payload_reth_arb_mux_from_immd_axis_tlast;
    wire                      s_roce_payload_reth_arb_mux_from_immd_axis_tuser;

    // to reth prepend payload
    wire                      s_reth_prepend_ready;
    wire                      s_reth_prepend_valid;
    wire [(20+8+12+16)*8-1:0] s_reth_prepend_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_reth_prepend_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_reth_prepend_axis_tkeep;
    wire                      s_roce_payload_reth_prepend_axis_tvalid;
    wire                      s_roce_payload_reth_prepend_axis_tready;
    wire                      s_roce_payload_reth_prepend_axis_tlast;
    wire                      s_roce_payload_reth_prepend_axis_tuser;

    // from reth prepend payload
    wire                      m_reth_prepend_ready;
    wire                      m_reth_prepend_valid;
    wire [(20+8+12)*8-1:0]    m_reth_prepend_hdr;
    wire [DATA_WIDTH-1   : 0] m_roce_payload_reth_prepend_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] m_roce_payload_reth_prepend_axis_tkeep;
    wire                      m_roce_payload_reth_prepend_axis_tvalid;
    wire                      m_roce_payload_reth_prepend_axis_tready;
    wire                      m_roce_payload_reth_prepend_axis_tlast;
    wire                      m_roce_payload_reth_prepend_axis_tuser;

    // bth arb mux
    wire                      s_bth_arb_mux_from_input_ready;
    wire                      s_bth_arb_mux_from_input_valid;
    wire [(20+8+12)*8-1:0]    s_bth_arb_mux_from_input_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_bth_arb_mux_from_input_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_bth_arb_mux_from_input_axis_tkeep;
    wire                      s_roce_payload_bth_arb_mux_from_input_axis_tvalid;
    wire                      s_roce_payload_bth_arb_mux_from_input_axis_tready;
    wire                      s_roce_payload_bth_arb_mux_from_input_axis_tlast;
    wire                      s_roce_payload_bth_arb_mux_from_input_axis_tuser;

    wire                      s_bth_arb_mux_from_reth_ready;
    wire                      s_bth_arb_mux_from_reth_valid;
    wire [(20+8+12)*8-1:0]    s_bth_arb_mux_from_reth_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_bth_arb_mux_from_reth_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_bth_arb_mux_from_reth_axis_tkeep;
    wire                      s_roce_payload_bth_arb_mux_from_reth_axis_tvalid;
    wire                      s_roce_payload_bth_arb_mux_from_reth_axis_tready;
    wire                      s_roce_payload_bth_arb_mux_from_reth_axis_tlast;
    wire                      s_roce_payload_bth_arb_mux_from_reth_axis_tuser;

    wire                      s_bth_arb_mux_from_immd_ready;
    wire                      s_bth_arb_mux_from_immd_valid;
    wire [(20+8+12)*8-1:0]    s_bth_arb_mux_from_immd_hdr;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_bth_arb_mux_from_immd_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_bth_arb_mux_from_immd_axis_tkeep;
    wire                      s_roce_payload_bth_arb_mux_from_immd_axis_tvalid;
    wire                      s_roce_payload_bth_arb_mux_from_immd_axis_tready;
    wire                      s_roce_payload_bth_arb_mux_from_immd_axis_tlast;
    wire                      s_roce_payload_bth_arb_mux_from_immd_axis_tuser;

    wire                      s_bth_prepend_ready;
    wire                      s_bth_prepend_valid;
    wire [(20+8+12)*8-1:0]    s_bth_prepend_header;
    wire [DATA_WIDTH-1   : 0] s_roce_payload_bth_prepend_axis_tdata;
    wire [DATA_WIDTH/8-1 : 0] s_roce_payload_bth_prepend_axis_tkeep;
    wire                      s_roce_payload_bth_prepend_axis_tvalid;
    wire                      s_roce_payload_bth_prepend_axis_tready;
    wire                      s_roce_payload_bth_prepend_axis_tlast;
    wire                      s_roce_payload_bth_prepend_axis_tuser;

    wire                      m_bth_prepend_ready;
    wire                      m_bth_prepend_valid;
    wire [(20+8)*8-1:0]       m_bth_prepend_header;

    assign s_bth_post_immd_prepend = m_immd_prepend_header[4*8+:12*8];

    // Second stage selection, either RETH or BTH
    // decide if RETH is needed
    wire s_select_2stg_reth  = (s_bth_post_immd_prepend.op_code == RC_RDMA_WRITE_ONLY_IMD) ? 1'b1 : 1'b0;
    reg  s_select_2stg_reth_reg = 1'b0;
    // decide if BTH is needed
    wire s_select_2stg_bth  = !(s_select_2stg_reth);
    reg  s_select_2stg_bth_reg = 1'b0;



    always @(posedge clk) begin
        if (rst) begin
            s_select_1stg_immd_reg  <= 1'b0;
            s_select_1stg_reth_reg  <= 1'b0;
            s_select_1stg_bth_reg   <= 1'b0;

            s_select_2stg_reth_reg  <= 1'b0;
            s_select_2stg_bth_reg   <= 1'b0;
        end else begin
            if (s_roce_payload_axis_tvalid) begin
                if ((!s_select_1stg_immd_reg) ||
                (s_roce_payload_axis_tvalid && s_roce_payload_axis_tready && s_roce_payload_axis_tlast)) begin
                    s_select_1stg_immd_reg  <= s_select_1stg_immd;
                end
                if ((!s_select_1stg_reth_reg) ||
                (s_roce_payload_axis_tvalid && s_roce_payload_axis_tready && s_roce_payload_axis_tlast)) begin
                    s_select_1stg_reth_reg  <= s_select_1stg_reth;
                end
                if ((!s_select_1stg_bth_reg) ||
                (s_roce_payload_axis_tvalid && s_roce_payload_axis_tready && s_roce_payload_axis_tlast)) begin
                    s_select_1stg_bth_reg   <= s_select_1stg_bth;
                end
            end else begin
                s_select_1stg_immd_reg  <= 1'b0;
                s_select_1stg_reth_reg  <= 1'b0;
                s_select_1stg_bth_reg   <= 1'b0;
            end

            if (m_roce_payload_immd_prepend_axis_tvalid) begin
                if ((!s_select_2stg_reth_reg) ||
                (m_roce_payload_immd_prepend_axis_tvalid && m_roce_payload_immd_prepend_axis_tready && m_roce_payload_immd_prepend_axis_tlast)) begin
                    s_select_2stg_reth_reg  <= s_select_2stg_reth;
                end
                if ((!s_select_2stg_bth_reg) ||
                (m_roce_payload_immd_prepend_axis_tvalid && m_roce_payload_immd_prepend_axis_tready && m_roce_payload_immd_prepend_axis_tlast)) begin
                    s_select_2stg_bth_reg   <= s_select_2stg_bth;
                end
            end else begin
                s_select_2stg_reth_reg  <= 1'b0;
                s_select_2stg_bth_reg   <= 1'b0;
            end
        end
    end

    assign s_immd_prepend_valid = s_roce_bth_valid & s_select_1stg_immd;
    assign s_immd_prepend_header = {s_ip_header, s_udp_header, s_bth, s_reth, s_immdh};

    assign s_roce_payload_immd_prepend_axis_tdata  = s_roce_payload_axis_tdata ;
    assign s_roce_payload_immd_prepend_axis_tkeep  = s_roce_payload_axis_tkeep ;
    assign s_roce_payload_immd_prepend_axis_tvalid = s_roce_payload_axis_tvalid & s_select_1stg_immd_reg;
    assign s_roce_payload_immd_prepend_axis_tlast  = s_roce_payload_axis_tlast ;
    assign s_roce_payload_immd_prepend_axis_tuser  = s_roce_payload_axis_tuser ;

    assign s_roce_payload_axis_tready = (s_roce_payload_immd_prepend_axis_tready            & s_select_1stg_immd_reg) ||
    (s_roce_payload_reth_arb_mux_from_input_axis_tready & s_select_1stg_reth_reg) ||
    (s_roce_payload_bth_arb_mux_from_input_axis_tready  & s_select_1stg_bth_reg);

    assign s_roce_bth_ready = (s_immd_prepend_ready            & s_select_1stg_immd) ||
    (s_reth_arb_mux_from_input_ready & s_select_1stg_reth) ||
    (s_bth_arb_mux_from_input_ready  & s_select_1stg_bth);

    header_prepender #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_HEADER_WIDTH(4),
        .OUT_HEADER_WIDTH(20+8+12+16) // IP UDP BTH RETH
    ) immdediate_prepender_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid(s_immd_prepend_valid),
        .s_hdr_ready(s_immd_prepend_ready),
        .s_hdr(s_immd_prepend_header[(4)*8-1:0]), // extract only Immediate data
        .s_hdr_out(s_immd_prepend_header[(20+8+12+16+4)*8-1:4*8]), // PASSTHROUGH IP UDP BTH RETH
        .s_payload_axis_tdata (s_roce_payload_immd_prepend_axis_tdata ),
        .s_payload_axis_tkeep (s_roce_payload_immd_prepend_axis_tkeep ),
        .s_payload_axis_tvalid(s_roce_payload_immd_prepend_axis_tvalid),
        .s_payload_axis_tready(s_roce_payload_immd_prepend_axis_tready),
        .s_payload_axis_tlast (s_roce_payload_immd_prepend_axis_tlast ),
        .s_payload_axis_tuser (s_roce_payload_immd_prepend_axis_tuser ),

        .m_hdr_valid(m_immd_prepend_valid),
        .m_hdr_ready(m_immd_prepend_ready),
        .m_hdr(m_immd_prepend_header),
        .m_payload_axis_tdata (m_roce_payload_immd_prepend_axis_tdata),
        .m_payload_axis_tkeep (m_roce_payload_immd_prepend_axis_tkeep),
        .m_payload_axis_tvalid(m_roce_payload_immd_prepend_axis_tvalid),
        .m_payload_axis_tready(m_roce_payload_immd_prepend_axis_tready),
        .m_payload_axis_tlast (m_roce_payload_immd_prepend_axis_tlast),
        .m_payload_axis_tuser (m_roce_payload_immd_prepend_axis_tuser),
        .busy()
    );

    assign m_roce_payload_immd_prepend_axis_tready = (s_roce_payload_reth_arb_mux_from_immd_axis_tready & s_select_2stg_reth_reg) ||
    (s_roce_payload_bth_arb_mux_from_immd_axis_tready  & s_select_2stg_bth_reg);

    assign m_immd_prepend_ready = (s_reth_arb_mux_from_immd_ready & s_select_2stg_reth) ||
    (s_bth_arb_mux_from_immd_ready  & s_select_2stg_bth);

    assign s_reth_arb_mux_from_input_valid = s_roce_bth_valid && s_select_1stg_reth;
    assign s_reth_arb_mux_from_input_hdr = {s_ip_header, s_udp_header, s_bth, s_reth};

    assign s_roce_payload_reth_arb_mux_from_input_axis_tdata  = s_roce_payload_axis_tdata;
    assign s_roce_payload_reth_arb_mux_from_input_axis_tkeep  = s_roce_payload_axis_tkeep;
    assign s_roce_payload_reth_arb_mux_from_input_axis_tvalid = s_roce_payload_axis_tvalid && s_select_1stg_reth_reg;
    assign s_roce_payload_reth_arb_mux_from_input_axis_tlast  = s_roce_payload_axis_tlast;
    assign s_roce_payload_reth_arb_mux_from_input_axis_tuser  = s_roce_payload_axis_tuser;


    assign s_reth_arb_mux_from_immd_valid = m_immd_prepend_valid && s_select_2stg_reth;
    assign s_reth_arb_mux_from_immd_hdr   = m_immd_prepend_header;

    assign s_roce_payload_reth_arb_mux_from_immd_axis_tdata  = m_roce_payload_immd_prepend_axis_tdata;
    assign s_roce_payload_reth_arb_mux_from_immd_axis_tkeep  = m_roce_payload_immd_prepend_axis_tkeep;
    assign s_roce_payload_reth_arb_mux_from_immd_axis_tvalid = m_roce_payload_immd_prepend_axis_tvalid && s_select_2stg_reth_reg;
    assign s_roce_payload_reth_arb_mux_from_immd_axis_tlast  = m_roce_payload_immd_prepend_axis_tlast;
    assign s_roce_payload_reth_arb_mux_from_immd_axis_tuser  = m_roce_payload_immd_prepend_axis_tuser;

    generic_arb_mux #(
        .S_COUNT(2),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .ARB_TYPE_ROUND_ROBIN(1),
        .HEADER_WIDTH(20+8+12+16) // IP UDP BTH RETH
    ) RETH_in_arb_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid({s_reth_arb_mux_from_input_valid, s_reth_arb_mux_from_immd_valid}),
        .s_hdr_ready({s_reth_arb_mux_from_input_ready, s_reth_arb_mux_from_immd_ready}),
        .s_hdr({s_reth_arb_mux_from_input_hdr, m_immd_prepend_header}),
        .s_payload_axis_tdata ({s_roce_payload_reth_arb_mux_from_input_axis_tdata , s_roce_payload_reth_arb_mux_from_immd_axis_tdata }),
        .s_payload_axis_tkeep ({s_roce_payload_reth_arb_mux_from_input_axis_tkeep , s_roce_payload_reth_arb_mux_from_immd_axis_tkeep }),
        .s_payload_axis_tvalid({s_roce_payload_reth_arb_mux_from_input_axis_tvalid, s_roce_payload_reth_arb_mux_from_immd_axis_tvalid}),
        .s_payload_axis_tready({s_roce_payload_reth_arb_mux_from_input_axis_tready, s_roce_payload_reth_arb_mux_from_immd_axis_tready}),
        .s_payload_axis_tlast ({s_roce_payload_reth_arb_mux_from_input_axis_tlast , s_roce_payload_reth_arb_mux_from_immd_axis_tlast }),
        .s_payload_axis_tuser ({s_roce_payload_reth_arb_mux_from_input_axis_tuser , s_roce_payload_reth_arb_mux_from_immd_axis_tuser }),
        .s_payload_axis_tid  (0),
        .s_payload_axis_tdest(0),
        .m_hdr_valid(s_reth_prepend_valid),
        .m_hdr_ready(s_reth_prepend_ready),
        .m_hdr(s_reth_prepend_hdr),
        .m_payload_axis_tdata (s_roce_payload_reth_prepend_axis_tdata ),
        .m_payload_axis_tkeep (s_roce_payload_reth_prepend_axis_tkeep ),
        .m_payload_axis_tvalid(s_roce_payload_reth_prepend_axis_tvalid),
        .m_payload_axis_tready(s_roce_payload_reth_prepend_axis_tready),
        .m_payload_axis_tlast (s_roce_payload_reth_prepend_axis_tlast ),
        .m_payload_axis_tuser (s_roce_payload_reth_prepend_axis_tuser )
    );

    header_prepender #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_HEADER_WIDTH(16),
        .OUT_HEADER_WIDTH(20+8+12) // IP UDP BTH
    ) reth_prepender_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid(s_reth_prepend_valid),
        .s_hdr_ready(s_reth_prepend_ready),
        .s_hdr(s_reth_prepend_hdr[(16)*8-1:0]), // RETH only
        .s_hdr_out(s_reth_prepend_hdr[(20+8+12+16)*8-1:16*8]), // PASSTROUGH IP UDP BTH
        .s_payload_axis_tdata (s_roce_payload_reth_prepend_axis_tdata ),
        .s_payload_axis_tkeep (s_roce_payload_reth_prepend_axis_tkeep ),
        .s_payload_axis_tvalid(s_roce_payload_reth_prepend_axis_tvalid),
        .s_payload_axis_tready(s_roce_payload_reth_prepend_axis_tready),
        .s_payload_axis_tlast (s_roce_payload_reth_prepend_axis_tlast ),
        .s_payload_axis_tuser (s_roce_payload_reth_prepend_axis_tuser ),

        .m_hdr_valid(m_reth_prepend_valid),
        .m_hdr_ready(m_reth_prepend_ready),
        .m_hdr(m_reth_prepend_hdr), // IP UDP BTH 
        .m_payload_axis_tdata (m_roce_payload_reth_prepend_axis_tdata ),
        .m_payload_axis_tkeep (m_roce_payload_reth_prepend_axis_tkeep ),
        .m_payload_axis_tvalid(m_roce_payload_reth_prepend_axis_tvalid),
        .m_payload_axis_tready(m_roce_payload_reth_prepend_axis_tready),
        .m_payload_axis_tlast (m_roce_payload_reth_prepend_axis_tlast ),
        .m_payload_axis_tuser (m_roce_payload_reth_prepend_axis_tuser ),
        .busy()
    );

    assign s_bth_arb_mux_from_input_valid = s_roce_bth_valid && s_select_1stg_bth;
    assign s_bth_arb_mux_from_input_hdr = {s_ip_header, s_udp_header, s_bth};

    assign s_roce_payload_bth_arb_mux_from_input_axis_tdata  = s_roce_payload_axis_tdata;
    assign s_roce_payload_bth_arb_mux_from_input_axis_tkeep  = s_roce_payload_axis_tkeep;
    assign s_roce_payload_bth_arb_mux_from_input_axis_tvalid = s_roce_payload_axis_tvalid && s_select_1stg_bth_reg;
    assign s_roce_payload_bth_arb_mux_from_input_axis_tlast  = s_roce_payload_axis_tlast;
    assign s_roce_payload_bth_arb_mux_from_input_axis_tuser  = s_roce_payload_axis_tuser;


    assign s_bth_arb_mux_from_reth_valid = m_reth_prepend_valid && s_select_2stg_bth;
    assign s_bth_arb_mux_from_reth_hdr = m_reth_prepend_hdr;

    assign m_reth_prepend_ready = s_bth_arb_mux_from_reth_ready;

    assign s_roce_payload_bth_arb_mux_from_reth_axis_tdata  = m_roce_payload_reth_prepend_axis_tdata;
    assign s_roce_payload_bth_arb_mux_from_reth_axis_tkeep  = m_roce_payload_reth_prepend_axis_tkeep;
    assign s_roce_payload_bth_arb_mux_from_reth_axis_tvalid = m_roce_payload_reth_prepend_axis_tvalid;
    assign s_roce_payload_bth_arb_mux_from_reth_axis_tlast  = m_roce_payload_reth_prepend_axis_tlast;
    assign s_roce_payload_bth_arb_mux_from_reth_axis_tuser  = m_roce_payload_reth_prepend_axis_tuser;

    assign m_roce_payload_reth_prepend_axis_tready = s_roce_payload_bth_arb_mux_from_reth_axis_tready;


    assign s_bth_arb_mux_from_immd_valid = m_immd_prepend_valid && s_select_2stg_bth;
    assign s_bth_arb_mux_from_immd_hdr = m_immd_prepend_header[(20+8+12+16)*8-1:16*8]; // remove RETH

    assign s_roce_payload_bth_arb_mux_from_immd_axis_tdata  = m_roce_payload_immd_prepend_axis_tdata;
    assign s_roce_payload_bth_arb_mux_from_immd_axis_tkeep  = m_roce_payload_immd_prepend_axis_tkeep;
    assign s_roce_payload_bth_arb_mux_from_immd_axis_tvalid = m_roce_payload_immd_prepend_axis_tvalid && s_select_2stg_bth_reg;
    assign s_roce_payload_bth_arb_mux_from_immd_axis_tlast  = m_roce_payload_immd_prepend_axis_tlast;
    assign s_roce_payload_bth_arb_mux_from_immd_axis_tuser  = m_roce_payload_immd_prepend_axis_tuser;

    

    generic_arb_mux #(
        .S_COUNT(3),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .ARB_TYPE_ROUND_ROBIN(1),
        .HEADER_WIDTH(20+8+12) // IP UDP BTH
    ) BTH_in_arb_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid({s_bth_arb_mux_from_input_valid, s_bth_arb_mux_from_reth_valid, s_bth_arb_mux_from_immd_valid}),
        .s_hdr_ready({s_bth_arb_mux_from_input_ready, s_bth_arb_mux_from_reth_ready, s_bth_arb_mux_from_immd_ready}),
        .s_hdr({s_bth_arb_mux_from_input_hdr, s_bth_arb_mux_from_reth_hdr,  s_bth_arb_mux_from_immd_hdr}),
        .s_payload_axis_tdata ({s_roce_payload_bth_arb_mux_from_input_axis_tdata , s_roce_payload_bth_arb_mux_from_reth_axis_tdata , s_roce_payload_bth_arb_mux_from_immd_axis_tdata }),
        .s_payload_axis_tkeep ({s_roce_payload_bth_arb_mux_from_input_axis_tkeep , s_roce_payload_bth_arb_mux_from_reth_axis_tkeep , s_roce_payload_bth_arb_mux_from_immd_axis_tkeep }),
        .s_payload_axis_tvalid({s_roce_payload_bth_arb_mux_from_input_axis_tvalid, s_roce_payload_bth_arb_mux_from_reth_axis_tvalid, s_roce_payload_bth_arb_mux_from_immd_axis_tvalid}),
        .s_payload_axis_tready({s_roce_payload_bth_arb_mux_from_input_axis_tready, s_roce_payload_bth_arb_mux_from_reth_axis_tready, s_roce_payload_bth_arb_mux_from_immd_axis_tready}),
        .s_payload_axis_tlast ({s_roce_payload_bth_arb_mux_from_input_axis_tlast , s_roce_payload_bth_arb_mux_from_reth_axis_tlast , s_roce_payload_bth_arb_mux_from_immd_axis_tlast }),
        .s_payload_axis_tuser ({s_roce_payload_bth_arb_mux_from_input_axis_tuser , s_roce_payload_bth_arb_mux_from_reth_axis_tuser , s_roce_payload_bth_arb_mux_from_immd_axis_tuser }),
        .s_payload_axis_tid  (0),
        .s_payload_axis_tdest(0),
        .m_hdr_valid(s_bth_prepend_valid),
        .m_hdr_ready(s_bth_prepend_ready),
        .m_hdr(s_bth_prepend_header),
        .m_payload_axis_tdata (s_roce_payload_bth_prepend_axis_tdata ),
        .m_payload_axis_tkeep (s_roce_payload_bth_prepend_axis_tkeep ),
        .m_payload_axis_tvalid(s_roce_payload_bth_prepend_axis_tvalid),
        .m_payload_axis_tready(s_roce_payload_bth_prepend_axis_tready),
        .m_payload_axis_tlast (s_roce_payload_bth_prepend_axis_tlast ),
        .m_payload_axis_tuser (s_roce_payload_bth_prepend_axis_tuser )
    );

    header_prepender #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_HEADER_WIDTH(12),
        .OUT_HEADER_WIDTH(8+20) // IP UDP
    ) bth_prepender_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid(s_bth_prepend_valid),
        .s_hdr_ready(s_bth_prepend_ready),
        .s_hdr(s_bth_prepend_header[(12)*8-1:0]), // BTH only
        .s_hdr_out(s_bth_prepend_header[(20+8+12)*8-1:(12*8)]), // PASSTROUGH IP UDP
        .s_payload_axis_tdata (s_roce_payload_bth_prepend_axis_tdata ),
        .s_payload_axis_tkeep (s_roce_payload_bth_prepend_axis_tkeep ),
        .s_payload_axis_tvalid(s_roce_payload_bth_prepend_axis_tvalid),
        .s_payload_axis_tready(s_roce_payload_bth_prepend_axis_tready),
        .s_payload_axis_tlast (s_roce_payload_bth_prepend_axis_tlast ),
        .s_payload_axis_tuser (s_roce_payload_bth_prepend_axis_tuser ),

        .m_hdr_valid(m_bth_prepend_valid),
        .m_hdr_ready(m_bth_prepend_ready),
        .m_hdr(m_bth_prepend_header), // BTH only
        .m_payload_axis_tdata (m_udp_payload_axis_tdata ),
        .m_payload_axis_tkeep (m_udp_payload_axis_tkeep ),
        .m_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_payload_axis_tready(m_udp_payload_axis_tready),
        .m_payload_axis_tlast (m_udp_payload_axis_tlast ),
        .m_payload_axis_tuser (m_udp_payload_axis_tuser ),
        .busy()
    );

    assign m_udp_hdr_valid = m_bth_prepend_valid;
    assign m_bth_prepend_ready = m_udp_hdr_ready;

    assign m_ip_header  = m_bth_prepend_header[(8)*8+:20*8];
    assign m_udp_header = m_bth_prepend_header[(8)*8-1:0];

    assign {m_ip_version, m_ip_ihl, m_ip_dscp, m_ip_ecn} = {<<byte {m_ip_header.header_version, m_ip_header.ihl, m_ip_header.dscp, m_ip_header.ecn}};
    assign m_ip_length = {<<byte {m_ip_header.length}};
    assign m_ip_identification = {<<byte {m_ip_header.identification}};
    assign {m_ip_flags, m_ip_fragment_offset} = {<<byte {m_ip_header.flags, m_ip_header.fragment_offset}};
    assign m_ip_ttl = m_ip_header.ttl;
    assign m_ip_protocol = m_ip_header.protocol;
    assign m_ip_header_checksum = {<<byte {m_ip_header.header_checksum}};
    assign m_ip_source_ip = {<<byte {m_ip_header.src_address}};
    assign m_ip_dest_ip = {<<byte {m_ip_header.dest_address}};

    assign m_udp_source_port = {<<byte {m_udp_header.src_port}};
    assign m_udp_dest_port = {<<byte {m_udp_header.dest_port}};
    assign m_udp_length = {<<byte {m_udp_header.length}};
    assign m_udp_checksum = {<<byte {m_udp_header.checksum}};


endmodule


`resetall
