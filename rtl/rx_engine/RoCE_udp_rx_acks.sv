`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * RoCEethernet frame receiver (UDP frame in, RoCE frame out)
 */
module RoCE_udp_rx_acks #(

    parameter DATA_WIDTH          = 256,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter ENABLE_ICRC_CHECK = 1'b1
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
    input  wire [ 31:0] s_roce_computed_icrc,
    input  wire [DATA_WIDTH - 1   : 0] s_udp_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 : 0] s_udp_payload_axis_tkeep,
    input  wire         s_udp_payload_axis_tvalid,
    output wire         s_udp_payload_axis_tready,
    input  wire         s_udp_payload_axis_tlast,
    input  wire         s_udp_payload_axis_tuser,


    /*
     * RoCE frame output
     */
    // BTH
    output wire        m_roce_bth_valid,
    input  wire        m_roce_bth_ready,
    output wire [ 7:0] m_roce_bth_op_code,
    output wire [15:0] m_roce_bth_p_key,
    output wire [23:0] m_roce_bth_psn,
    output wire [23:0] m_roce_bth_dest_qp,
    output wire        m_roce_bth_ack_req,
    // AETH
    output wire        m_roce_aeth_valid,
    input  wire        m_roce_aeth_ready,
    output wire [ 7:0] m_roce_aeth_syndrome,
    output wire [23:0] m_roce_aeth_msn,
    /*
    // RETH
    output wire        m_roce_reth_valid,
    input  wire        m_roce_reth_ready,
    output wire [63:0] m_roce_reth_v_addr,
    output wire [31:0] m_roce_reth_r_key,
    output wire [31:0] m_roce_reth_length,
    // IMMD
    output wire        m_roce_immdh_valid,
    input  wire        m_roce_immdh_ready,
    output wire [31:0] m_roce_immdh_data,
    */
    // udp, ip, eth
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [ 3:0] m_ip_version,
    output wire [ 3:0] m_ip_ihl,
    output wire [ 5:0] m_ip_dscp,
    output wire [ 1:0] m_ip_ecn,
    output wire [15:0] m_ip_identification,
    output wire [ 2:0] m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [ 7:0] m_ip_ttl,
    output wire [ 7:0] m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    /* TODO maybe implement something here?
    output wire [63:0] m_roce_payload_axis_tdata,
    output wire [ 7:0] m_roce_payload_axis_tkeep,
    output wire        m_roce_payload_axis_tvalid,
    input  wire        m_roce_payload_axis_tready,
    output wire        m_roce_payload_axis_tlast,
    output wire        m_roce_payload_axis_tuser,
    */
    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_header_early_termination
);

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    parameter HDR_SIZE = 12+4+4; // BTH AETH ICRC

    parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

    parameter OFFSET = HDR_SIZE % BYTE_LANES;

    // bus width assertions
    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end

    /*

RoCE ACK Frame.

RDMA ACK 
IP_HDR + UDP_HDR + BTH + AETH + ICRC


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

This module receives an IP frame with header fields in parallel and payload on
an AXI stream interface, decodes and strips the UDP header fields, then
produces the header fields in parallel along with the UDP payload in a
separate AXI stream.


*/

    import RoCE_params::*; // Imports RoCE parameters

    // bus width assertions
    initial begin

        if (DATA_WIDTH > 2048) begin
            $error("Error: AXIS data width must be smaller than 2048 (instance %m)");
            $finish;
        end
    end


    // datapath control signals
    reg store_udp_hdr;

    reg read_udp_header_reg = 1'b1, read_udp_header_next;
    reg read_roce_header_reg = 1'b0, read_roce_header_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
    reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

    reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
    reg [ 7:0] m_roce_bth_op_code_reg, m_roce_bth_op_code_next;
    reg [15:0] m_roce_bth_p_key_reg, m_roce_bth_p_key_next;
    reg [23:0] m_roce_bth_psn_reg, m_roce_bth_psn_next;
    reg [23:0] m_roce_bth_dest_qp_reg, m_roce_bth_dest_qp_next;
    reg        m_roce_bth_ack_req_reg, m_roce_bth_ack_req_next;

    reg m_roce_aeth_valid_reg = 1'b0, m_roce_aeth_valid_next;
    reg [ 7:0] m_roce_aeth_syndrome_reg, m_roce_aeth_syndrome_next;
    reg [23:0] m_roce_aeth_msn_reg, m_roce_aeth_msn_next;

    reg [31:0] m_roce_icrc_reg, m_roce_icrc_next;

    reg [47:0] m_eth_dest_mac_reg = 48'd0;
    reg [47:0] m_eth_src_mac_reg = 48'd0;
    reg [15:0] m_eth_type_reg = 16'd0;
    reg [ 3:0] m_ip_version_reg = 4'd0;
    reg [ 3:0] m_ip_ihl_reg = 4'd0;
    reg [ 5:0] m_ip_dscp_reg = 6'd0;
    reg [ 1:0] m_ip_ecn_reg = 2'd0;
    reg [15:0] m_ip_length_reg = 16'd0;
    reg [15:0] m_ip_identification_reg = 16'd0;
    reg [ 2:0] m_ip_flags_reg = 3'd0;
    reg [12:0] m_ip_fragment_offset_reg = 13'd0;
    reg [ 7:0] m_ip_ttl_reg = 8'd0;
    reg [ 7:0] m_ip_protocol_reg = 8'd0;
    reg [15:0] m_ip_header_checksum_reg = 16'd0;
    reg [31:0] m_ip_source_ip_reg = 32'd0;
    reg [31:0] m_ip_dest_ip_reg = 32'd0;
    reg [15:0] m_udp_source_port_reg = 16'd0;
    reg [15:0] m_udp_dest_port_reg = 16'd0;
    reg [15:0] m_udp_length_reg = 16'd0;
    reg [15:0] m_udp_checksum_reg = 16'd0;

    reg busy_reg = 1'b0;
    reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;

    assign s_udp_hdr_ready                = s_udp_hdr_ready_reg;
    assign s_udp_payload_axis_tready      = s_udp_payload_axis_tready_reg;

    assign m_roce_bth_valid               = m_roce_bth_valid_reg;
    assign m_roce_bth_op_code             = m_roce_bth_op_code_reg;
    assign m_roce_bth_p_key               = m_roce_bth_p_key_reg;
    assign m_roce_bth_psn                 = m_roce_bth_psn_reg;
    assign m_roce_bth_dest_qp             = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req             = m_roce_bth_ack_req_reg;
    assign m_roce_aeth_valid              = m_roce_bth_valid_reg;
    assign m_roce_aeth_syndrome           = m_roce_aeth_syndrome_reg;
    assign m_roce_aeth_msn                = m_roce_aeth_msn_reg;
    assign m_eth_dest_mac                 = m_eth_dest_mac_reg;
    assign m_eth_src_mac                  = m_eth_src_mac_reg;
    assign m_eth_type                     = m_eth_type_reg;
    assign m_ip_version                   = m_ip_version_reg;
    assign m_ip_ihl                       = m_ip_ihl_reg;
    assign m_ip_dscp                      = m_ip_dscp_reg;
    assign m_ip_ecn                       = m_ip_ecn_reg;
    assign m_ip_identification            = m_ip_identification_reg;
    assign m_ip_flags                     = m_ip_flags_reg;
    assign m_ip_fragment_offset           = m_ip_fragment_offset_reg;
    assign m_ip_ttl                       = m_ip_ttl_reg;
    assign m_ip_protocol                  = m_ip_protocol_reg;
    assign m_ip_header_checksum           = m_ip_header_checksum_reg;
    assign m_ip_source_ip                 = m_ip_source_ip_reg;
    assign m_ip_dest_ip                   = m_ip_dest_ip_reg;
    assign m_udp_source_port              = m_udp_source_port_reg;
    assign m_udp_dest_port                = m_udp_dest_port_reg;
    assign m_udp_length                   = m_udp_length_reg;
    assign m_udp_checksum                 = m_udp_checksum_reg;

    reg [31:0] m_roce_computed_icrc_reg = 32'd0;
    reg [31:0] m_roce_recieved_icrc_reg = 32'd0;

    reg error_not_roce_ack_reg = 1'b0, error_not_roce_ack_next;
    reg error_wrong_icrc_reg = 1'b0, error_wrong_icrc_next;

    assign busy                           = busy_reg;
    assign error_header_early_termination = error_header_early_termination_reg;

    always @* begin
        read_udp_header_next = read_udp_header_reg;
        read_roce_header_next = read_roce_header_reg;
        ptr_next = ptr_reg;

        s_udp_hdr_ready_next = 1'b0;
        s_udp_payload_axis_tready_next = 1'b0;

        store_udp_hdr = 1'b0;

        m_roce_bth_valid_next = m_roce_bth_valid_reg && !m_roce_bth_ready;

        m_roce_bth_op_code_next = m_roce_bth_op_code_reg;
        m_roce_bth_p_key_next = m_roce_bth_p_key_reg;
        m_roce_bth_psn_next = m_roce_bth_psn_reg;
        m_roce_bth_dest_qp_next = m_roce_bth_dest_qp_reg;
        m_roce_bth_ack_req_next = m_roce_bth_ack_req_reg;
        m_roce_aeth_syndrome_next = m_roce_aeth_syndrome_reg;
        m_roce_aeth_msn_next = m_roce_aeth_msn_reg;

        error_header_early_termination_next = 1'b0;
        error_wrong_icrc_next = 1'b0;
        error_not_roce_ack_next = 1'b0;

        if (s_udp_hdr_ready && s_udp_hdr_valid) begin
            if (read_udp_header_reg) begin
                store_udp_hdr = 1'b1;
                ptr_next = 0;
                read_udp_header_next = 1'b0;
                read_roce_header_next = 1'b1;
            end
        end

        if (s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) begin
            if (read_roce_header_reg) begin
                // word transfer in - store it
                ptr_next = ptr_reg + 1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_udp_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

                `_HEADER_FIELD_(0,  m_roce_bth_op_code_next[0*8 +: 8])
                //`_HEADER_FIELD_(1, {solicited_event_next, mig_request_next, pad_count_next, header_version_next} )
                `_HEADER_FIELD_(2,  m_roce_bth_p_key_next[1*8 +: 8])
                `_HEADER_FIELD_(3,  m_roce_bth_p_key_next[0*8 +: 8])
                //`_HEADER_FIELD_(4,  rsvd) 
                `_HEADER_FIELD_(5,  m_roce_bth_dest_qp_next[2*8 +: 8])
                `_HEADER_FIELD_(6,  m_roce_bth_dest_qp_next[1*8 +: 8])
                `_HEADER_FIELD_(7,  m_roce_bth_dest_qp_next[0*8 +: 8])
                //`_HEADER_FIELD_(8,  {ack_req_next, 7'd0})
                `_HEADER_FIELD_(9,  m_roce_bth_psn_next[2*8 +: 8])
                `_HEADER_FIELD_(10,  m_roce_bth_psn_next[1*8 +: 8])
                `_HEADER_FIELD_(11, m_roce_bth_psn_next[0*8 +: 8])
                `_HEADER_FIELD_(12, m_roce_aeth_syndrome_next[0*8 +: 8])
                `_HEADER_FIELD_(13, m_roce_aeth_msn_next[2*8 +: 8])
                `_HEADER_FIELD_(14, m_roce_aeth_msn_next[1*8 +: 8])
                `_HEADER_FIELD_(15, m_roce_aeth_msn_next[0*8 +: 8])
                `_HEADER_FIELD_(16, m_roce_icrc_next[3*8 +: 8])
                `_HEADER_FIELD_(17, m_roce_icrc_next[2*8 +: 8])
                `_HEADER_FIELD_(18, m_roce_icrc_next[1*8 +: 8])
                `_HEADER_FIELD_(19, m_roce_icrc_next[0*8 +: 8])

                if (ptr_reg == 19/BYTE_LANES && (!KEEP_ENABLE || s_udp_payload_axis_tkeep[19%BYTE_LANES])) begin
                    read_roce_header_next = 1'b0;
                end

            `undef _HEADER_FIELD_
        end

            if (s_udp_payload_axis_tlast) begin
                if (read_roce_header_next) begin
                    // don't have the whole header
                    error_header_early_termination_next = 1'b1;
                end else if (ENABLE_ICRC_CHECK && m_roce_icrc_next != m_roce_recieved_icrc_reg) begin
                    // wrong ICRC
                    error_wrong_icrc_next = 1'b1;
                end if (m_roce_bth_op_code_next != RC_RDMA_ACK) begin
                    error_not_roce_ack_next <= 1'b1;
                end else begin
                    // otherwise, transfer tuser
                    m_roce_bth_valid_next = !s_udp_payload_axis_tuser;
                end

                ptr_next = 1'b0;
                read_udp_header_next = 1'b1;
                read_roce_header_next = 1'b0;
            end
        end

        if (read_udp_header_next) begin
            s_udp_hdr_ready_next = !m_roce_bth_valid_next;
        end else begin
            s_udp_payload_axis_tready_next = 1'b1;
        end
    end

    always @(posedge clk) begin
        read_udp_header_reg <= read_udp_header_next;
        read_roce_header_reg <= read_roce_header_next;
        ptr_reg <= ptr_next;

        s_udp_hdr_ready_reg <= s_udp_hdr_ready_next;
        s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;

        m_roce_bth_valid_reg <= m_roce_bth_valid_next;

        m_roce_bth_op_code_reg          <= m_roce_bth_op_code_next;
        m_roce_bth_p_key_reg            <= m_roce_bth_p_key_next;
        m_roce_bth_dest_qp_reg          <= m_roce_bth_dest_qp_next;
        m_roce_bth_psn_reg              <= m_roce_bth_psn_next;

        m_roce_aeth_syndrome_reg        <= m_roce_aeth_syndrome_next;
        m_roce_aeth_msn_reg             <= m_roce_aeth_msn_next;

        m_roce_icrc_reg                 <= m_roce_icrc_next;

        error_header_early_termination_reg <= error_header_early_termination_next;
        error_wrong_icrc_reg <= error_wrong_icrc_next;
        error_not_roce_ack_reg <= error_not_roce_ack_next;
        busy_reg <= read_roce_header_next;

        // datapath
        if (store_udp_hdr) begin
            m_eth_dest_mac_reg       <= s_eth_dest_mac;
            m_eth_src_mac_reg        <= s_eth_src_mac;
            m_eth_type_reg           <= s_eth_type;
            m_ip_version_reg         <= s_ip_version;
            m_ip_ihl_reg             <= s_ip_ihl;
            m_ip_dscp_reg            <= s_ip_dscp;
            m_ip_ecn_reg             <= s_ip_ecn;
            m_ip_length_reg          <= s_ip_length;
            m_ip_identification_reg  <= s_ip_identification;
            m_ip_flags_reg           <= s_ip_flags;
            m_ip_fragment_offset_reg <= s_ip_fragment_offset;
            m_ip_ttl_reg             <= s_ip_ttl;
            m_ip_protocol_reg        <= s_ip_protocol;
            m_ip_header_checksum_reg <= s_ip_header_checksum;
            m_ip_source_ip_reg       <= s_ip_source_ip;
            m_ip_dest_ip_reg         <= s_ip_dest_ip;
            m_udp_source_port_reg    <= s_udp_source_port;
            m_udp_dest_port_reg      <= s_udp_dest_port;
            m_udp_length_reg         <= s_udp_length;
            m_udp_checksum_reg       <= s_udp_checksum;
            m_roce_computed_icrc_reg <= s_roce_computed_icrc;
        end

        if (rst) begin
            read_udp_header_reg <= 1'b1;
            read_roce_header_reg <= 1'b0;
            ptr_reg <= 0;
            s_udp_payload_axis_tready_reg <= 1'b0;
            m_roce_bth_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
            error_header_early_termination_reg <= 1'b0;
            error_wrong_icrc_reg <= 1'b0;
            error_not_roce_ack_reg <= 1'b0;
        end
    end

endmodule

`resetall
