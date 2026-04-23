`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_realign_frame_fifo #(
    parameter S_DATA_WIDTH = 64,
    parameter M_DATA_WIDTH = 64,
    parameter HAS_ADAPTER = 0,
    parameter FIFO_DEPTH = 1024
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
    input  wire [S_DATA_WIDTH   - 1 :0] s_roce_payload_axis_tdata,
    input  wire [S_DATA_WIDTH/8 - 1 :0] s_roce_payload_axis_tkeep,
    input  wire                         s_roce_payload_axis_tvalid,
    output wire                         s_roce_payload_axis_tready,
    input  wire                         s_roce_payload_axis_tlast,
    input  wire                         s_roce_payload_axis_tuser,

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
    output  wire [M_DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata,
    output  wire [M_DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_tkeep,
    output  wire                         m_roce_payload_axis_tvalid,
    input   wire                         m_roce_payload_axis_tready,
    output  wire                         m_roce_payload_axis_tlast,
    output  wire                         m_roce_payload_axis_tuser,

    input   wire     stall

);

    import RoCE_params::*; // Imports RoCE parameters

    localparam [2:0]
    STATE_IDLE          = 3'd0,
    STATE_STORE_HDR     = 3'd1,
    STATE_SEND          = 3'd2;

    reg [2:0] state_reg = STATE_IDLE, state_next;


    reg [M_DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata_int;
    reg [M_DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_tkeep_int;
    reg                         m_roce_payload_axis_tvalid_int;
    reg                         m_roce_payload_axis_tready_int_reg;
    reg                         m_roce_payload_axis_tlast_int;
    reg                         m_roce_payload_axis_tuser_int;
    wire                        m_roce_payload_axis_tready_int_early;

    reg store_hdr;

    reg m_roce_bth_valid_reg, m_roce_bth_valid_next;
    reg m_roce_reth_valid_reg, m_roce_reth_valid_next;
    reg m_roce_immdh_valid_reg, m_roce_immdh_valid_next;


    reg [  7:0] m_roce_bth_op_code_reg = 8'd0;
    reg [ 15:0] m_roce_bth_p_key_reg = 16'd0;
    reg [ 23:0] m_roce_bth_psn_reg = 24'd0;
    reg [ 23:0] m_roce_bth_dest_qp_reg = 24'd0;
    reg         m_roce_bth_ack_req_reg = 1'd0;
    reg [23:0]  m_roce_bth_src_qp_reg  = 24'd0;

    reg [ 63:0] m_roce_reth_v_addr_reg = 64'd0;
    reg [ 31:0] m_roce_reth_r_key_reg = 32'd0;
    reg [ 31:0] m_roce_reth_length_reg = 32'd0;

    reg [ 31:0] m_roce_immdh_data_reg = 32'd0;


    reg m_roce_payload_axis_fifo_tready_reg, m_roce_payload_axis_fifo_tready_next;
    reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;
    reg s_roce_payload_axis_tready_reg = 1'b0, s_roce_payload_axis_tready_next;

    //reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
    //reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;
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

    wire [M_DATA_WIDTH   - 1 :0] m_roce_payload_axis_fifo_tdata;
    wire [M_DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_fifo_tkeep;
    wire                         m_roce_payload_axis_fifo_tvalid;
    wire                         m_roce_payload_axis_fifo_tready;
    wire                         m_roce_payload_axis_fifo_tlast;
    wire                         m_roce_payload_axis_fifo_tuser;

    assign m_roce_bth_valid = m_roce_bth_valid_reg;
    assign m_roce_bth_op_code = m_roce_bth_op_code_reg;
    assign m_roce_bth_p_key = m_roce_bth_p_key_reg;
    assign m_roce_bth_psn = m_roce_bth_psn_reg;
    assign m_roce_bth_dest_qp = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_src_qp = m_roce_bth_src_qp_reg;
    assign m_roce_bth_ack_req = m_roce_bth_ack_req_reg;
    assign m_roce_reth_valid = m_roce_reth_valid_reg;
    assign m_roce_reth_v_addr = m_roce_reth_v_addr_reg;
    assign m_roce_reth_r_key = m_roce_reth_r_key_reg;
    assign m_roce_reth_length = m_roce_reth_length_reg;
    assign m_roce_immdh_valid = m_roce_immdh_valid_reg;
    assign m_roce_immdh_data = m_roce_immdh_data_reg;
    assign m_eth_dest_mac = m_eth_dest_mac_reg;
    assign m_eth_src_mac = m_eth_src_mac_reg;
    assign m_eth_type = m_eth_type_reg;
    assign m_ip_version = m_ip_version_reg;
    assign m_ip_ihl = m_ip_ihl_reg;
    assign m_ip_dscp = m_ip_dscp_reg;
    assign m_ip_ecn = m_ip_ecn_reg;
    assign m_ip_identification = m_ip_identification_reg;
    assign m_ip_flags = m_ip_flags_reg;
    assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
    assign m_ip_ttl = m_ip_ttl_reg;
    assign m_ip_protocol = m_ip_protocol_reg;
    assign m_ip_header_checksum = m_ip_header_checksum_reg;
    assign m_ip_source_ip = m_ip_source_ip_reg;
    assign m_ip_dest_ip = m_ip_dest_ip_reg;
    assign m_udp_source_port = m_udp_source_port_reg;
    assign m_udp_dest_port = m_udp_dest_port_reg;
    assign m_udp_length = m_udp_length_reg;
    assign m_udp_checksum = m_udp_checksum_reg;

    assign s_roce_bth_ready = s_roce_bth_ready_reg;
    assign s_roce_reth_ready = s_roce_bth_ready_reg;
    assign s_roce_immdh_ready = s_roce_bth_ready_reg;

    generate
        if (S_DATA_WIDTH == M_DATA_WIDTH) begin
            axis_fifo #(
                .DEPTH(FIFO_DEPTH),
                .RAM_PIPELINE(1),
                .DATA_WIDTH(S_DATA_WIDTH),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(S_DATA_WIDTH/8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .FRAME_FIFO(1),
                .PAUSE_ENABLE(1),
                .FRAME_PAUSE(1)
            ) roce_payload_fifo (
                .clk(clk),
                .rst(rst),


                .s_axis_tdata (s_roce_payload_axis_tdata),
                .s_axis_tkeep (s_roce_payload_axis_tkeep),
                .s_axis_tvalid(s_roce_payload_axis_tvalid),
                .s_axis_tready(s_roce_payload_axis_tready),
                .s_axis_tlast (s_roce_payload_axis_tlast),
                .s_axis_tuser (s_roce_payload_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_roce_payload_axis_fifo_tdata),
                .m_axis_tkeep (m_roce_payload_axis_fifo_tkeep),
                .m_axis_tvalid(m_roce_payload_axis_fifo_tvalid),
                .m_axis_tready(m_roce_payload_axis_fifo_tready),
                .m_axis_tlast (m_roce_payload_axis_fifo_tlast),
                .m_axis_tuser (m_roce_payload_axis_fifo_tuser),
                .m_axis_tid   (),
                .m_axis_tdest (),
                // pause 
                .pause_req(stall),
                .pause_ack()
            );
        end else begin
            axis_fifo_adapter #(
                .DEPTH(FIFO_DEPTH),
                .RAM_PIPELINE(1),
                .S_DATA_WIDTH(S_DATA_WIDTH),
                .S_KEEP_ENABLE(1),
                .S_KEEP_WIDTH(S_DATA_WIDTH/8),
                .M_DATA_WIDTH(M_DATA_WIDTH),
                .M_KEEP_ENABLE(1),
                .M_KEEP_WIDTH(M_DATA_WIDTH/8),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .FRAME_FIFO(1),
                .PAUSE_ENABLE(1),
                .FRAME_PAUSE(1)
            ) roce_payload_fifo_adapter (
                .clk(clk),
                .rst(rst),


                .s_axis_tdata (s_roce_payload_axis_tdata),
                .s_axis_tkeep (s_roce_payload_axis_tkeep),
                .s_axis_tvalid(s_roce_payload_axis_tvalid),
                .s_axis_tready(s_roce_payload_axis_tready),
                .s_axis_tlast (s_roce_payload_axis_tlast),
                .s_axis_tuser (s_roce_payload_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_roce_payload_axis_fifo_tdata),
                .m_axis_tkeep (m_roce_payload_axis_fifo_tkeep),
                .m_axis_tvalid(m_roce_payload_axis_fifo_tvalid),
                .m_axis_tready(m_roce_payload_axis_fifo_tready),
                .m_axis_tlast (m_roce_payload_axis_fifo_tlast),
                .m_axis_tuser (m_roce_payload_axis_fifo_tuser),
                .m_axis_tid   (),
                .m_axis_tdest (),
                // pause 
                .pause_req(stall),
                .pause_ack()
            );
        end
    endgenerate




    always @(*) begin
        state_next = STATE_IDLE;

        s_roce_bth_ready_next = 1'b0;
        store_hdr = 1'b0;
        m_roce_payload_axis_fifo_tready_next = 1'b0;

        m_roce_bth_valid_next   = m_roce_bth_valid_reg & !m_roce_bth_ready;
        m_roce_reth_valid_next  = m_roce_reth_valid_reg & !m_roce_reth_ready;
        m_roce_immdh_valid_next = m_roce_immdh_valid_reg & !m_roce_immdh_ready;

        m_roce_payload_axis_tdata_int  = 0;
        m_roce_payload_axis_tkeep_int  = 0;
        m_roce_payload_axis_tvalid_int = 0;
        m_roce_payload_axis_tlast_int  = 0;
        m_roce_payload_axis_tuser_int  = 0;

        case(state_reg)
            STATE_IDLE : begin
                s_roce_bth_ready_next = !m_roce_bth_valid_next;
                if (s_roce_bth_valid && s_roce_bth_ready) begin
                    s_roce_bth_ready_next = 1'b0;
                    store_hdr = 1'b1;
                    // input completed its transfer, fifo will output the payolad
                    if (m_roce_payload_axis_fifo_tvalid) begin // data already available at the fifo, input frame completed
                        m_roce_bth_valid_next = 1'b1;
                        m_roce_reth_valid_next = s_roce_bth_op_code == RC_RDMA_WRITE_FIRST ||
                        s_roce_bth_op_code == RC_RDMA_WRITE_ONLY ||
                        s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD;

                        m_roce_immdh_valid_next = s_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
                        s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
                        s_roce_bth_op_code == RC_SEND_LAST_IMD ||
                        s_roce_bth_op_code == RC_SEND_ONLY_IMD;

                        m_roce_payload_axis_fifo_tready_next = m_roce_payload_axis_tready_int_early;

                        state_next = STATE_SEND;
                    end else begin
                        state_next = STATE_STORE_HDR;
                    end
                end
            end
            STATE_STORE_HDR : begin
                // input completed its transfer, fifo will output the payolad
                if (m_roce_payload_axis_fifo_tvalid) begin
                    m_roce_bth_valid_next = 1'b1;
                    m_roce_reth_valid_next = m_roce_bth_op_code_reg == RC_RDMA_WRITE_FIRST ||
                    m_roce_bth_op_code_reg == RC_RDMA_WRITE_ONLY ||
                    m_roce_bth_op_code_reg == RC_RDMA_WRITE_ONLY_IMD;

                    m_roce_immdh_valid_next = m_roce_bth_op_code_reg == RC_RDMA_WRITE_LAST_IMD ||
                    m_roce_bth_op_code_reg == RC_RDMA_WRITE_ONLY_IMD ||
                    m_roce_bth_op_code_reg == RC_SEND_LAST_IMD ||
                    m_roce_bth_op_code_reg == RC_SEND_ONLY_IMD ;

                    m_roce_payload_axis_fifo_tready_next = m_roce_payload_axis_tready_int_early;

                    state_next = STATE_SEND;
                end else begin
                    state_next = STATE_STORE_HDR;
                end

            end
            STATE_SEND: begin
                m_roce_payload_axis_fifo_tready_next = m_roce_payload_axis_tready_int_early;

                m_roce_payload_axis_tdata_int  = m_roce_payload_axis_fifo_tdata;
                m_roce_payload_axis_tkeep_int  = m_roce_payload_axis_fifo_tkeep;
                m_roce_payload_axis_tvalid_int = m_roce_payload_axis_fifo_tvalid;
                m_roce_payload_axis_tlast_int  = m_roce_payload_axis_fifo_tlast;
                m_roce_payload_axis_tuser_int  = m_roce_payload_axis_fifo_tuser;
                // word transfer trhough
                if (m_roce_payload_axis_tready_int_reg && m_roce_payload_axis_tvalid_int && m_roce_payload_axis_tlast_int) begin // disable fifo out
                    m_roce_payload_axis_fifo_tready_next = 1'b0;
                    s_roce_bth_ready_next = !m_roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_SEND;
                end
            end
            default: begin
                store_hdr = 1'b0;
                s_roce_bth_ready_next = !m_roce_bth_valid_next;
                m_roce_payload_axis_fifo_tready_next = 1'b0;

                m_roce_payload_axis_tdata_int  = 0;
                m_roce_payload_axis_tkeep_int  = 0;
                m_roce_payload_axis_tvalid_int = 0;
                m_roce_payload_axis_tlast_int  = 0;
                m_roce_payload_axis_tuser_int  = 0;

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
                m_eth_dest_mac_reg <= s_eth_dest_mac;
                m_eth_src_mac_reg <= s_eth_src_mac;
                m_eth_type_reg <= s_eth_type;
                m_ip_version_reg <= s_ip_version;
                m_ip_ihl_reg <= s_ip_ihl;
                m_ip_dscp_reg <= s_ip_dscp;
                m_ip_ecn_reg <= s_ip_ecn;
                m_ip_length_reg <= s_udp_length + 20;
                m_ip_identification_reg <= s_ip_identification;
                m_ip_flags_reg <= s_ip_flags;
                m_ip_fragment_offset_reg <= s_ip_fragment_offset;
                m_ip_ttl_reg <= s_ip_ttl;
                m_ip_protocol_reg <= s_ip_protocol;
                m_ip_header_checksum_reg <= s_ip_header_checksum;
                m_ip_source_ip_reg <= s_ip_source_ip;
                m_ip_dest_ip_reg <= s_ip_dest_ip;

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

                if (s_roce_reth_valid) begin
                    m_roce_reth_v_addr_reg <= s_roce_reth_v_addr;
                    m_roce_reth_r_key_reg  <= s_roce_reth_r_key;
                    m_roce_reth_length_reg <= s_roce_reth_length;
                end
                if (s_roce_immdh_valid) begin
                    m_roce_immdh_data_reg <= s_roce_immdh_data;
                end
            end
        end
    end

    // output datapath logic
    reg [M_DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata_reg = 0;
    reg [M_DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_tkeep_reg = 0;
    reg m_roce_payload_axis_tvalid_reg = 1'b0, m_roce_payload_axis_tvalid_next;
    reg         m_roce_payload_axis_tlast_reg = 1'b0;
    reg         m_roce_payload_axis_tuser_reg = 1'b0;

    reg [M_DATA_WIDTH   - 1 :0] temp_m_roce_payload_axis_tdata_reg = 0;
    reg [M_DATA_WIDTH/8 - 1 :0] temp_m_roce_payload_axis_tkeep_reg = 0;
    reg temp_m_roce_payload_axis_tvalid_reg = 1'b0, temp_m_roce_payload_axis_tvalid_next;
    reg temp_m_roce_payload_axis_tlast_reg = 1'b0;
    reg temp_m_roce_payload_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_roce_payload_int_to_output;
    reg store_roce_payload_int_to_temp;
    reg store_roce_payload_axis_temp_to_output;

    assign m_roce_payload_axis_tdata = m_roce_payload_axis_tdata_reg;
    assign m_roce_payload_axis_tkeep = m_roce_payload_axis_tkeep_reg;
    assign m_roce_payload_axis_tvalid = m_roce_payload_axis_tvalid_reg;
    assign m_roce_payload_axis_tlast = m_roce_payload_axis_tlast_reg;
    assign m_roce_payload_axis_tuser = m_roce_payload_axis_tuser_reg;

    assign m_roce_payload_axis_fifo_tready = m_roce_payload_axis_fifo_tready_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_roce_payload_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_roce_payload_axis_tvalid_reg && !m_roce_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_reg;
        temp_m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;

        store_roce_payload_int_to_output = 1'b0;
        store_roce_payload_int_to_temp = 1'b0;
        store_roce_payload_axis_temp_to_output = 1'b0;

        if (m_roce_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_roce_payload_axis_tready | !m_roce_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_roce_payload_axis_tvalid_next  = m_roce_payload_axis_tvalid_int;
                store_roce_payload_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_int;
                store_roce_payload_int_to_temp = 1'b1;
            end
        end else if (m_roce_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;
            temp_m_roce_payload_axis_tvalid_next = 1'b0;
            store_roce_payload_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_roce_payload_axis_tvalid_reg <= m_roce_payload_axis_tvalid_next;
        m_roce_payload_axis_tready_int_reg <= m_roce_payload_axis_tready_int_early;
        temp_m_roce_payload_axis_tvalid_reg <= temp_m_roce_payload_axis_tvalid_next;

        // datapath
        if (store_roce_payload_int_to_output) begin
            m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
            m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
            m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
            m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
        end else if (store_roce_payload_axis_temp_to_output) begin
            m_roce_payload_axis_tdata_reg <= temp_m_roce_payload_axis_tdata_reg;
            m_roce_payload_axis_tkeep_reg <= temp_m_roce_payload_axis_tkeep_reg;
            m_roce_payload_axis_tlast_reg <= temp_m_roce_payload_axis_tlast_reg;
            m_roce_payload_axis_tuser_reg <= temp_m_roce_payload_axis_tuser_reg;
        end

        if (store_roce_payload_int_to_temp) begin
            temp_m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
            temp_m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
            temp_m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
            temp_m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
        end

        if (rst) begin
            m_roce_payload_axis_tvalid_reg <= 1'b0;
            m_roce_payload_axis_tready_int_reg <= 1'b0;
            temp_m_roce_payload_axis_tvalid_reg <= 1'b0;
        end
    end




endmodule

`resetall