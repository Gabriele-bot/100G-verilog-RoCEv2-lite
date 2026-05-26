`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_hdr_fifo #(
    parameter HDR_FIFO_DEPTH = 0
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE hdr input
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

    /*
     * RoCE hdr output
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
    output  wire [ 15:0] m_udp_checksum
);

    parameter HDR_FIFO_ADDR_WIDTH = $clog2(HDR_FIFO_DEPTH);

    localparam [2:0]
    STATE_IDLE          = 1'b0,
    STATE_STORE_HDR     = 1'b1;

    reg state_reg = STATE_IDLE, state_next;

    reg store_hdr;

    reg m_roce_bth_valid_reg, m_roce_bth_valid_next;
    reg m_roce_reth_valid_reg, m_roce_reth_valid_next;
    reg m_roce_immdh_valid_reg, m_roce_immdh_valid_next;

    reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;
    reg s_roce_payload_axis_tready_reg = 1'b0, s_roce_payload_axis_tready_next;

    reg [ 7:0] m_roce_bth_op_code_reg = 8'd0;
    reg [15:0] m_roce_bth_p_key_reg = 16'd0;
    reg [23:0] m_roce_bth_psn_reg = 24'd0;
    reg [23:0] m_roce_bth_dest_qp_reg = 24'd0;
    reg        m_roce_bth_ack_req_reg = 1'd0;
    reg [23:0] m_roce_bth_src_qp_reg  = 24'd0;

    reg [63:0] m_roce_reth_v_addr_reg = 64'd0;
    reg [31:0] m_roce_reth_r_key_reg = 32'd0;
    reg [31:0] m_roce_reth_length_reg = 32'd0;

    reg [31:0] m_roce_immdh_data_reg = 32'd0;

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


    reg [ 7:0] roce_bth_op_code_reg = 8'd0;
    reg [15:0] roce_bth_p_key_reg = 16'd0;
    reg [23:0] roce_bth_psn_reg = 24'd0;
    reg [23:0] roce_bth_dest_qp_reg = 24'd0;
    reg        roce_bth_ack_req_reg = 1'd0;
    reg [23:0] roce_bth_src_qp_reg  = 24'd0;

    reg [63:0] roce_reth_v_addr_reg = 64'd0;
    reg [31:0] roce_reth_r_key_reg = 32'd0;
    reg [31:0] roce_reth_length_reg = 32'd0;

    reg [31:0] roce_immdh_data_reg = 32'd0;

    reg [47:0] eth_dest_mac_reg = 48'd0;
    reg [47:0] eth_src_mac_reg = 48'd0;
    reg [15:0] eth_type_reg = 16'd0;
    reg [ 3:0] ip_version_reg = 4'd0;
    reg [ 3:0] ip_ihl_reg = 4'd0;
    reg [ 5:0] ip_dscp_reg = 6'd0;
    reg [ 1:0] ip_ecn_reg = 2'd0;
    reg [15:0] ip_length_reg = 16'd0;
    reg [15:0] ip_identification_reg = 16'd0;
    reg [ 2:0] ip_flags_reg = 3'd0;
    reg [12:0] ip_fragment_offset_reg = 13'd0;
    reg [ 7:0] ip_ttl_reg = 8'd0;
    reg [ 7:0] ip_protocol_reg = 8'd0;
    reg [15:0] ip_header_checksum_reg = 16'd0;
    reg [31:0] ip_source_ip_reg = 32'd0;
    reg [31:0] ip_dest_ip_reg = 32'd0;
    reg [15:0] udp_source_port_reg = 16'd0;
    reg [15:0] udp_dest_port_reg = 16'd0;
    reg [15:0] udp_length_reg = 16'd0;
    reg [15:0] udp_checksum_reg = 16'd0;

    reg [HDR_FIFO_DEPTH:0] header_fifo_wr_ptr_reg = {HDR_FIFO_DEPTH+1{1'b0}}, header_fifo_wr_ptr_next;
    reg [HDR_FIFO_DEPTH:0] header_fifo_rd_ptr_reg = {HDR_FIFO_DEPTH+1{1'b0}}, header_fifo_rd_ptr_next;

    reg [ 7:0] roce_bth_op_code_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] roce_bth_p_key_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [23:0] roce_bth_psn_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [23:0] roce_bth_dest_qp_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 0:0] roce_bth_ack_req_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [23:0] roce_bth_src_qp_mem[(2**HDR_FIFO_DEPTH)-1:0];

    reg [63:0] roce_reth_v_addr_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [31:0] roce_reth_r_key_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [31:0] roce_reth_length_mem[(2**HDR_FIFO_DEPTH)-1:0];

    reg [31:0] roce_immdh_data_mem[(2**HDR_FIFO_DEPTH)-1:0];

    reg [47:0] eth_dest_mac_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [47:0] eth_src_mac_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] eth_type_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 3:0] ip_version_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 3:0] ip_ihl_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 5:0] ip_dscp_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 1:0] ip_ecn_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] ip_identification_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 2:0] ip_flags_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [12:0] ip_fragment_offset_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [ 7:0] ip_ttl_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] ip_header_checksum_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [31:0] ip_source_ip_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [31:0] ip_dest_ip_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] udp_source_port_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] udp_dest_port_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] udp_length_mem[(2**HDR_FIFO_DEPTH)-1:0];
    reg [15:0] udp_checksum_mem[(2**HDR_FIFO_DEPTH)-1:0];

    reg [ 7:0] s_roce_bth_op_code_reg = 8'd0;
    reg [15:0] s_roce_bth_p_key_reg = 16'd0;
    reg [23:0] s_roce_bth_psn_reg = 24'd0;
    reg [23:0] s_roce_bth_dest_qp_reg = 24'd0;
    reg        s_roce_bth_ack_req_reg = 1'd0;
    reg [23:0] s_roce_bth_src_qp_reg  = 24'd0;

    reg [63:0] s_roce_reth_v_addr_reg = 64'd0;
    reg [31:0] s_roce_reth_r_key_reg = 32'd0;
    reg [31:0] s_roce_reth_length_reg = 32'd0;

    reg [31:0] s_roce_immdh_data_reg = 32'd0;

    reg [47:0] s_eth_dest_mac_reg = 48'd0;
    reg [47:0] s_eth_src_mac_reg = 48'd0;
    reg [15:0] s_eth_type_reg = 16'd0;
    reg [ 3:0] s_ip_version_reg = 4'd0;
    reg [ 3:0] s_ip_ihl_reg = 4'd0;
    reg [ 5:0] s_ip_dscp_reg = 6'd0;
    reg [ 1:0] s_ip_ecn_reg = 2'd0;
    reg [15:0] s_ip_length_reg = 16'd0;
    reg [15:0] s_ip_identification_reg = 16'd0;
    reg [ 2:0] s_ip_flags_reg = 3'd0;
    reg [12:0] s_ip_fragment_offset_reg = 13'd0;
    reg [ 7:0] s_ip_ttl_reg = 8'd0;
    reg [ 7:0] s_ip_protocol_reg = 8'd0;
    reg [15:0] s_ip_header_checksum_reg = 16'd0;
    reg [31:0] s_ip_source_ip_reg = 32'd0;
    reg [31:0] s_ip_dest_ip_reg = 32'd0;
    reg [15:0] s_udp_source_port_reg = 16'd0;
    reg [15:0] s_udp_dest_port_reg = 16'd0;
    reg [15:0] s_udp_length_reg = 16'd0;
    reg [15:0] s_udp_checksum_reg = 16'd0;


    reg hdr_valid_reg = 0, hdr_valid_next;

    assign hdr_valid_next = s_roce_bth_ready && s_roce_bth_valid;

    // full when first MSB different but rest same
    wire header_fifo_full = ((header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH] != header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH]) &&
    (header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0] == header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]));
    // empty when pointers match exactly
    wire header_fifo_empty = header_fifo_wr_ptr_reg == header_fifo_rd_ptr_reg;

    // control signals
    reg header_fifo_write;
    reg header_fifo_read;

    wire header_fifo_ready = !header_fifo_full;

    reg  roce_bth_valid_reg, roce_bth_valid_next;

    // Write logic
    always @* begin
        header_fifo_write = 1'b0;

        header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg;

        if (hdr_valid_reg) begin
            // input data valid
            if (~header_fifo_full) begin
                // not full, perform write
                header_fifo_write = 1'b1;
                header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            header_fifo_wr_ptr_reg <= {HDR_FIFO_ADDR_WIDTH+1{1'b0}};

            hdr_valid_reg <= 1'b0;
        end else begin
            header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_next;

            hdr_valid_reg <= hdr_valid_next;
        end

        if (header_fifo_write) begin
            roce_bth_op_code_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_bth_op_code_reg;
            roce_bth_p_key_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]   <= roce_bth_p_key_reg;
            roce_bth_psn_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]     <= roce_bth_psn_reg;
            roce_bth_dest_qp_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_bth_dest_qp_reg;
            roce_bth_ack_req_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_bth_ack_req_reg;
            roce_bth_src_qp_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]  <= roce_bth_src_qp_reg;

            roce_reth_v_addr_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_reth_v_addr_reg;
            roce_reth_r_key_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]  <= roce_reth_r_key_reg;
            roce_reth_length_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_reth_length_reg;

            roce_immdh_data_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= roce_immdh_data_reg;

            eth_dest_mac_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= eth_dest_mac_reg;
            eth_src_mac_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]  <= eth_src_mac_reg;
            eth_type_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]     <= eth_type_reg;

            ip_version_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]         <= ip_version_reg;
            ip_ihl_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]             <= ip_ihl_reg;
            ip_dscp_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]            <= ip_dscp_reg;
            ip_ecn_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]             <= ip_ecn_reg;
            ip_identification_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]  <= ip_identification_reg;
            ip_flags_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]           <= ip_flags_reg;
            ip_fragment_offset_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= ip_fragment_offset_reg;
            ip_ttl_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]             <= ip_ttl_reg;
            ip_header_checksum_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= ip_header_checksum_reg;
            ip_source_ip_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]       <= ip_source_ip_reg;
            ip_dest_ip_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]         <= ip_dest_ip_reg;

            udp_source_port_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]] <= udp_source_port_reg;
            udp_dest_port_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]   <= udp_dest_port_reg;
            udp_length_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]      <= udp_length_reg;
            udp_checksum_mem[header_fifo_wr_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]]    <= udp_checksum_reg;
        end
    end

    // Read logic
    always @* begin
        header_fifo_read = 1'b0;

        header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg;

        roce_bth_valid_next = roce_bth_valid_reg;

        if (m_roce_bth_ready || !m_roce_bth_valid_reg) begin
            // output data not valid OR currently being transferred
            if (!header_fifo_empty) begin
                // not empty, perform read
                header_fifo_read = 1'b1;
                roce_bth_valid_next = 1'b1;
                header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg + 1;
            end else begin
                // empty, invalidate
                roce_bth_valid_next = 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            header_fifo_rd_ptr_reg <= {HDR_FIFO_ADDR_WIDTH+1{1'b0}};
            m_roce_bth_valid_reg <= 1'b0;
        end else begin
            header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_next;
            m_roce_bth_valid_reg <= m_roce_bth_valid_next;
        end

        if (header_fifo_read) begin
            s_roce_bth_op_code_reg <= roce_bth_op_code_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_bth_p_key_reg <= roce_bth_p_key_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_bth_psn_reg <= roce_bth_psn_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_bth_dest_qp_reg <= roce_bth_dest_qp_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_bth_ack_req_reg <= roce_bth_ack_req_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_bth_src_qp_reg <= roce_bth_src_qp_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];

            s_roce_reth_v_addr_reg <= roce_reth_v_addr_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_reth_r_key_reg <= roce_reth_r_key_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_roce_reth_length_reg <= roce_reth_length_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];

            s_roce_immdh_data_reg <= roce_immdh_data_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];

            s_eth_dest_mac_reg <= eth_dest_mac_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_eth_src_mac_reg <= eth_src_mac_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_eth_type_reg <= eth_type_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_version_reg <= ip_version_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_ihl_reg <= ip_ihl_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_dscp_reg <= ip_dscp_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_ecn_reg <= ip_ecn_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_identification_reg <= ip_identification_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_flags_reg <= ip_flags_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_fragment_offset_reg <= ip_fragment_offset_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_ttl_reg <= ip_ttl_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_header_checksum_reg <= ip_header_checksum_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_source_ip_reg <= ip_source_ip_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_ip_dest_ip_reg <= ip_dest_ip_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_udp_source_port_reg <= udp_source_port_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_udp_dest_port_reg <= udp_dest_port_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_udp_length_reg <= udp_length_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
            s_udp_checksum_reg <= udp_checksum_mem[header_fifo_rd_ptr_reg[HDR_FIFO_ADDR_WIDTH-1:0]];
        end
    end

    always @(*) begin

        s_roce_bth_ready_next = 1'b0;
        store_hdr = 1'b0;

        m_roce_bth_valid_next   = m_roce_bth_valid_reg & !m_roce_bth_ready;
        m_roce_reth_valid_next  = m_roce_reth_valid_reg & !m_roce_reth_ready;
        m_roce_immdh_valid_next = m_roce_immdh_valid_reg & !m_roce_immdh_ready;

        case(state_reg)
            STATE_IDLE : begin
                state_next = STATE_IDLE;
                s_roce_bth_ready_next = !hdr_valid_next;
                if (s_roce_bth_valid && s_roce_bth_ready) begin
                    s_roce_bth_ready_next = 1'b0;
                    store_hdr = 1'b1;

                end
            end
            STATE_STORE_HDR : begin
                s_roce_bth_ready_next = !hdr_valid_next;
                state_next = STATE_IDLE;
            end
            default: begin
                store_hdr = 1'b0;
                s_roce_bth_ready_next = !hdr_valid_next;
                state_next = STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            m_roce_bth_valid_reg <= 1'b0;
            m_roce_reth_valid_reg <= 1'b0;
            m_roce_immdh_valid_reg <= 1'b0;

            m_eth_dest_mac_reg <= 0;
            m_eth_src_mac_reg <= 0;
            m_eth_type_reg <= 0;
            m_ip_version_reg <= 0;
            m_ip_ihl_reg <= 0;
            m_ip_dscp_reg <= 0;
            m_ip_ecn_reg <= 0;
            m_ip_length_reg <= 0;
            m_ip_identification_reg <= 0;
            m_ip_flags_reg <= 0;
            m_ip_fragment_offset_reg <= 0;
            m_ip_ttl_reg <= 0;
            m_ip_protocol_reg <= 0;
            m_ip_header_checksum_reg <= 0;
            m_ip_source_ip_reg <= 0;
            m_ip_dest_ip_reg <= 0;

            m_udp_source_port_reg <= s_udp_source_port;
            m_udp_dest_port_reg <= s_udp_dest_port;
            m_udp_length_reg <= s_udp_length;
            m_udp_checksum_reg <= s_udp_checksum;

            m_roce_bth_op_code_reg <= s_roce_bth_op_code;
            m_roce_bth_p_key_reg   <= s_roce_bth_p_key;
            m_roce_bth_psn_reg     <= s_roce_bth_psn;
            m_roce_bth_dest_qp_reg <= s_roce_bth_dest_qp;
            m_roce_bth_ack_req_reg <= s_roce_bth_ack_req;
            m_roce_bth_src_qp_reg  <= s_roce_bth_src_qp;

            m_roce_reth_v_addr_reg <= 0;
            m_roce_reth_r_key_reg  <= 0;
            m_roce_reth_length_reg <= 0;

            m_roce_immdh_data_reg <= 0;

            s_roce_bth_ready_reg <= 1'b0;
            m_roce_payload_axis_fifo_tready_reg <= 1'b0;
        end else begin
            state_reg <= state_next;

            m_roce_bth_valid_reg <= m_roce_bth_valid_next;
            m_roce_reth_valid_reg <= m_roce_reth_valid_next;
            m_roce_immdh_valid_reg <= m_roce_immdh_valid_next;

            s_roce_bth_ready_reg <= s_roce_bth_ready_next;
            m_roce_payload_axis_fifo_tready_reg <= m_roce_payload_axis_fifo_tready_next;

            if (store_hdr) begin
                eth_dest_mac_reg <= s_eth_dest_mac;
                eth_src_mac_reg <= s_eth_src_mac;
                eth_type_reg <= s_eth_type;
                ip_version_reg <= s_ip_version;
                ip_ihl_reg <= s_ip_ihl;
                ip_dscp_reg <= s_ip_dscp;
                ip_ecn_reg <= s_ip_ecn;
                ip_length_reg <= s_udp_length + 20;
                ip_identification_reg <= s_ip_identification;
                ip_flags_reg <= s_ip_flags;
                ip_fragment_offset_reg <= s_ip_fragment_offset;
                ip_ttl_reg <= s_ip_ttl;
                ip_protocol_reg <= s_ip_protocol;
                ip_header_checksum_reg <= s_ip_header_checksum;
                ip_source_ip_reg <= s_ip_source_ip;
                ip_dest_ip_reg <= s_ip_dest_ip;

                udp_source_port_reg <= s_udp_source_port;
                udp_dest_port_reg <= s_udp_dest_port;
                udp_length_reg <= s_udp_length;
                udp_checksum_reg <= s_udp_checksum;

                roce_bth_op_code_reg <= s_roce_bth_op_code;
                roce_bth_p_key_reg   <= s_roce_bth_p_key;
                roce_bth_psn_reg     <= s_roce_bth_psn;
                roce_bth_dest_qp_reg <= s_roce_bth_dest_qp;
                roce_bth_ack_req_reg <= s_roce_bth_ack_req;
                roce_bth_src_qp_reg  <= s_roce_bth_src_qp;

                if (s_roce_reth_valid) begin
                    roce_reth_v_addr_reg <= s_roce_reth_v_addr;
                    roce_reth_r_key_reg  <= s_roce_reth_r_key;
                    roce_reth_length_reg <= s_roce_reth_length;
                end
                if (s_roce_immdh_valid) begin
                    roce_immdh_data_reg <= s_roce_immdh_data;
                end
            end
        end
    end


endmodule