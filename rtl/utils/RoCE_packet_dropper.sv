`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_packet_dropper #(
    parameter DATA_WIDTH = 64,
    parameter DROP_PROBABILITY = 1
) (
    input wire clk,
    input wire rst,
    /*
     * RoCE TX frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire [ 23:0] s_roce_bth_src_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire         s_roce_reth_valid,
    output wire         s_roce_reth_ready,
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire         s_roce_immdh_valid,
    output wire         s_roce_immdh_ready,
    input  wire [ 31:0] s_roce_immdh_data,
    // udp, ip, eth
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
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
    input  wire [DATA_WIDTH   - 1 :0] s_roce_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 :0] s_roce_payload_axis_tkeep,
    input  wire                       s_roce_payload_axis_tvalid,
    output wire                       s_roce_payload_axis_tready,
    input  wire                       s_roce_payload_axis_tlast,
    input  wire                       s_roce_payload_axis_tuser,

    /*
     * RoCE TX frame output
     */
    // BTH
    output  wire         m_roce_bth_valid,
    input   wire         m_roce_bth_ready,
    output  wire [  7:0] m_roce_bth_op_code,
    output  wire [ 15:0] m_roce_bth_p_key,
    output  wire [ 23:0] m_roce_bth_psn,
    output  wire [ 23:0] m_roce_bth_dest_qp,
    output  wire [ 23:0] m_roce_bth_src_qp,
    output  wire         m_roce_bth_ack_req,
    // RETH
    output  wire         m_roce_reth_valid,
    input   wire         m_roce_reth_ready,
    output  wire [ 63:0] m_roce_reth_v_addr,
    output  wire [ 31:0] m_roce_reth_r_key,
    output  wire [ 31:0] m_roce_reth_length,
    // IMMD
    output  wire         m_roce_immdh_valid,
    input wire           m_roce_immdh_ready,
    output  wire [ 31:0] m_roce_immdh_data,
    // udp, ip, eth
    output  wire [ 47:0] m_eth_dest_mac,
    output  wire [ 47:0] m_eth_src_mac,
    output  wire [ 15:0] m_eth_type,
    output  wire [  3:0] m_ip_version,
    output  wire [  3:0] m_ip_ihl,
    output  wire [  5:0] m_ip_dscp,
    output  wire [  1:0] m_ip_ecn,
    output  wire [ 15:0] m_ip_identification,
    output  wire [  2:0] m_ip_flags,
    output  wire [ 12:0] m_ip_fragment_offset,
    output  wire [  7:0] m_ip_ttl,
    output  wire [  7:0] m_ip_protocol,
    output  wire [ 15:0] m_ip_header_checksum,
    output  wire [ 31:0] m_ip_source_ip,
    output  wire [ 31:0] m_ip_dest_ip,
    output  wire [ 15:0] m_udp_source_port,
    output  wire [ 15:0] m_udp_dest_port,
    output  wire [ 15:0] m_udp_length,
    output  wire [ 15:0] m_udp_checksum,
    // payload
    output  wire [DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_tkeep,
    output  wire                       m_roce_payload_axis_tvalid,
    input   wire                       m_roce_payload_axis_tready,
    output  wire                       m_roce_payload_axis_tlast,
    output  wire                       m_roce_payload_axis_tuser
);

    integer random_number;
    wire    drop_packet;
    integer test_value = 32'h7c200000;

    // extract random integer
    always @(posedge clk) begin
        if (s_roce_bth_valid && s_roce_bth_ready) begin
            random_number <= $random;
        end
    end

    
    assign drop_packet = (random_number > test_value);


    assign m_roce_bth_valid = s_roce_bth_valid;
    assign s_roce_bth_ready = m_roce_bth_ready;
    assign m_roce_bth_op_code = s_roce_bth_op_code;
    assign m_roce_bth_p_key   = s_roce_bth_p_key;
    assign m_roce_bth_psn     = s_roce_bth_psn;
    assign m_roce_bth_dest_qp = s_roce_bth_dest_qp;
    assign m_roce_bth_src_qp  = s_roce_bth_src_qp;
    assign m_roce_bth_ack_req = s_roce_bth_ack_req;
    assign m_roce_reth_valid  = s_roce_reth_valid;
    assign s_roce_reth_ready  = m_roce_reth_ready;
    assign m_roce_reth_v_addr = s_roce_reth_v_addr;
    assign m_roce_reth_r_key  = s_roce_reth_r_key;
    assign m_roce_reth_length = s_roce_reth_length;
    assign m_roce_immdh_valid = s_roce_immdh_valid;
    assign s_roce_immdh_ready = m_roce_immdh_ready;
    assign m_roce_immdh_data  = s_roce_immdh_data;

    assign m_eth_dest_mac       = s_eth_dest_mac;
    assign m_eth_src_mac        = s_eth_src_mac;
    assign m_eth_type           = s_eth_type;
    assign m_ip_version         = s_ip_version;
    assign m_ip_ihl             = s_ip_ihl;
    assign m_ip_dscp            = s_ip_dscp;
    assign m_ip_ecn             = s_ip_ecn;
    assign m_ip_identification  = s_ip_identification;
    assign m_ip_flags           = s_ip_flags;
    assign m_ip_fragment_offset = s_ip_fragment_offset;
    assign m_ip_ttl             = s_ip_ttl;
    assign m_ip_protocol        = s_ip_protocol;
    assign m_ip_header_checksum = s_ip_header_checksum;
    assign m_ip_source_ip       = s_ip_source_ip;
    assign m_ip_dest_ip         = s_ip_dest_ip;
    assign m_udp_source_port    = s_udp_source_port;
    assign m_udp_dest_port      = s_udp_dest_port;
    assign m_udp_length         = s_udp_length;
    assign m_udp_checksum       = s_udp_checksum;

    assign m_roce_payload_axis_tdata   = s_roce_payload_axis_tdata;
    assign m_roce_payload_axis_tkeep   = s_roce_payload_axis_tkeep;
    assign m_roce_payload_axis_tvalid  = s_roce_payload_axis_tvalid;
    assign s_roce_payload_axis_tready  = m_roce_payload_axis_tready;
    assign m_roce_payload_axis_tlast   = s_roce_payload_axis_tlast;
    assign m_roce_payload_axis_tuser   = s_roce_payload_axis_tuser | (s_roce_payload_axis_tlast & drop_packet);


endmodule