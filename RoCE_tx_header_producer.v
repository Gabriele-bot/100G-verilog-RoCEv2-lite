
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_tx_header_producer #(
    parameter DATA_WIDTH = 64
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE DMA transfer parameters
     */
    input  wire       s_dma_meta_valid,
    output wire       s_dma_meta_ready,
    input wire [31:0] s_dma_length,
    input wire [23:0] s_rem_qpn,
    input wire [23:0] s_rem_psn,
    input wire [31:0] s_r_key,
    input wire [31:0] s_rem_ip_addr,
    input wire [63:0] s_rem_addr,
    input wire        s_is_immediate,

    /*
     * AXIS input
     */
    input  wire [  DATA_WIDTH - 1:0] s_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1:0] s_axis_tkeep,
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire                      s_axis_tlast,
    input  wire                      s_axis_tuser,


    /*
     * RoCE frame output
     */
    // BTH
    output wire                      m_roce_bth_valid,
    input  wire                      m_roce_bth_ready,
    output wire [               7:0] m_roce_bth_op_code,
    output wire [              15:0] m_roce_bth_p_key,
    output wire [              23:0] m_roce_bth_psn,
    output wire [              23:0] m_roce_bth_dest_qp,
    output wire                      m_roce_bth_ack_req,
    // RETH              
    output wire                      m_roce_reth_valid,
    input  wire                      m_roce_reth_ready,
    output wire [              63:0] m_roce_reth_v_addr,
    output wire [              31:0] m_roce_reth_r_key,
    output wire [              31:0] m_roce_reth_length,
    // IMMD              
    output wire                      m_roce_immdh_valid,
    input  wire                      m_roce_immdh_ready,
    output wire [              31:0] m_roce_immdh_data,
    // udp, ip, eth      
    output wire [              47:0] m_eth_dest_mac,
    output wire [              47:0] m_eth_src_mac,
    output wire [              15:0] m_eth_type,
    output wire [               3:0] m_ip_version,
    output wire [               3:0] m_ip_ihl,
    output wire [               5:0] m_ip_dscp,
    output wire [               1:0] m_ip_ecn,
    output wire [              15:0] m_ip_identification,
    output wire [               2:0] m_ip_flags,
    output wire [              12:0] m_ip_fragment_offset,
    output wire [               7:0] m_ip_ttl,
    output wire [               7:0] m_ip_protocol,
    output wire [              15:0] m_ip_header_checksum,
    output wire [              31:0] m_ip_source_ip,
    output wire [              31:0] m_ip_dest_ip,
    output wire [              15:0] m_udp_source_port,
    output wire [              15:0] m_udp_dest_port,
    output wire [              15:0] m_udp_length,
    output wire [              15:0] m_udp_checksum,
    // stream
    output wire [DATA_WIDTH   - 1:0] m_roce_payload_axis_tdata,
    output wire [DATA_WIDTH/8 - 1:0] m_roce_payload_axis_tkeep,
    output wire                      m_roce_payload_axis_tvalid,
    input  wire                      m_roce_payload_axis_tready,
    output wire                      m_roce_payload_axis_tlast,
    output wire                      m_roce_payload_axis_tuser,
    // config
    input  wire [              12:0] pmtu,
    input  wire [              15:0] RoCE_udp_port,
    input  wire [              31:0] loc_ip_addr

);

    function [15:0] keep2count;
        input [63:0] k;
        casez (k)
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0: keep2count = 16'd0;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01: keep2count = 16'd1;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011: keep2count = 16'd2;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111: keep2count = 16'd3;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111: keep2count = 16'd4;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111: keep2count = 16'd5;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111: keep2count = 16'd6;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111: keep2count = 16'd7;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111: keep2count = 16'd8;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111: keep2count = 16'd9;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111: keep2count = 16'd10;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111: keep2count = 16'd11;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111: keep2count = 16'd12;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111: keep2count = 16'd13;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111: keep2count = 16'd14;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111: keep2count = 16'd15;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111: keep2count = 16'd16;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111: keep2count = 16'd17;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111: keep2count = 16'd18;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111: keep2count = 16'd19;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111: keep2count = 16'd20;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111: keep2count = 16'd21;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111: keep2count = 16'd22;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111: keep2count = 16'd23;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111: keep2count = 16'd24;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111: keep2count = 16'd25;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111: keep2count = 16'd26;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111: keep2count = 16'd27;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111: keep2count = 16'd28;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111: keep2count = 16'd29;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111: keep2count = 16'd30;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111: keep2count = 16'd31;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111: keep2count = 16'd32;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111: keep2count = 16'd33;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111: keep2count = 16'd34;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111: keep2count = 16'd35;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111: keep2count = 16'd36;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111: keep2count = 16'd37;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111: keep2count = 16'd38;
            64'bzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111: keep2count = 16'd39;
            64'bzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111: keep2count = 16'd40;
            64'bzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111: keep2count = 16'd41;
            64'bzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111: keep2count = 16'd42;
            64'bzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111: keep2count = 16'd43;
            64'bzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111: keep2count = 16'd44;
            64'bzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111: keep2count = 16'd45;
            64'bzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111: keep2count = 16'd46;
            64'bzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111111: keep2count = 16'd47;
            64'bzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111111: keep2count = 16'd48;
            64'bzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111111: keep2count = 16'd49;
            64'bzzzzzzzzzzzzz011111111111111111111111111111111111111111111111111: keep2count = 16'd50;
            64'bzzzzzzzzzzzz0111111111111111111111111111111111111111111111111111: keep2count = 16'd51;
            64'bzzzzzzzzzzz01111111111111111111111111111111111111111111111111111: keep2count = 16'd52;
            64'bzzzzzzzzzz011111111111111111111111111111111111111111111111111111: keep2count = 16'd53;
            64'bzzzzzzzzz0111111111111111111111111111111111111111111111111111111: keep2count = 16'd54;
            64'bzzzzzzzz01111111111111111111111111111111111111111111111111111111: keep2count = 16'd55;
            64'bzzzzzzz011111111111111111111111111111111111111111111111111111111: keep2count = 16'd56;
            64'bzzzzzz0111111111111111111111111111111111111111111111111111111111: keep2count = 16'd57;
            64'bzzzzz01111111111111111111111111111111111111111111111111111111111: keep2count = 16'd58;
            64'bzzzz011111111111111111111111111111111111111111111111111111111111: keep2count = 16'd59;
            64'bzzz0111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd60;
            64'bzz01111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd61;
            64'bz011111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd62;
            64'b0111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd63;
            64'b1111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd64;
        endcase
    endfunction

    function [63:0] count2keep;
        input [6:0] k;
        case (k)
            7'd0:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000000;
            7'd1:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000001;
            7'd2:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000011;
            7'd3:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000111;
            7'd4:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000001111;
            7'd5:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000011111;
            7'd6:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000111111;
            7'd7:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000001111111;
            7'd8:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000011111111;
            7'd9:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000111111111;
            7'd10:   count2keep = 64'b0000000000000000000000000000000000000000000000000000001111111111;
            7'd11:   count2keep = 64'b0000000000000000000000000000000000000000000000000000011111111111;
            7'd12:   count2keep = 64'b0000000000000000000000000000000000000000000000000000111111111111;
            7'd13:   count2keep = 64'b0000000000000000000000000000000000000000000000000001111111111111;
            7'd14:   count2keep = 64'b0000000000000000000000000000000000000000000000000011111111111111;
            7'd15:   count2keep = 64'b0000000000000000000000000000000000000000000000000111111111111111;
            7'd16:   count2keep = 64'b0000000000000000000000000000000000000000000000001111111111111111;
            7'd17:   count2keep = 64'b0000000000000000000000000000000000000000000000011111111111111111;
            7'd18:   count2keep = 64'b0000000000000000000000000000000000000000000000111111111111111111;
            7'd19:   count2keep = 64'b0000000000000000000000000000000000000000000001111111111111111111;
            7'd20:   count2keep = 64'b0000000000000000000000000000000000000000000011111111111111111111;
            7'd21:   count2keep = 64'b0000000000000000000000000000000000000000000111111111111111111111;
            7'd22:   count2keep = 64'b0000000000000000000000000000000000000000001111111111111111111111;
            7'd23:   count2keep = 64'b0000000000000000000000000000000000000000011111111111111111111111;
            7'd24:   count2keep = 64'b0000000000000000000000000000000000000000111111111111111111111111;
            7'd25:   count2keep = 64'b0000000000000000000000000000000000000001111111111111111111111111;
            7'd26:   count2keep = 64'b0000000000000000000000000000000000000011111111111111111111111111;
            7'd27:   count2keep = 64'b0000000000000000000000000000000000000111111111111111111111111111;
            7'd28:   count2keep = 64'b0000000000000000000000000000000000001111111111111111111111111111;
            7'd29:   count2keep = 64'b0000000000000000000000000000000000011111111111111111111111111111;
            7'd30:   count2keep = 64'b0000000000000000000000000000000000111111111111111111111111111111;
            7'd31:   count2keep = 64'b0000000000000000000000000000000001111111111111111111111111111111;
            7'd32:   count2keep = 64'b0000000000000000000000000000000011111111111111111111111111111111;
            7'd33:   count2keep = 64'b0000000000000000000000000000000111111111111111111111111111111111;
            7'd34:   count2keep = 64'b0000000000000000000000000000001111111111111111111111111111111111;
            7'd35:   count2keep = 64'b0000000000000000000000000000011111111111111111111111111111111111;
            7'd36:   count2keep = 64'b0000000000000000000000000000111111111111111111111111111111111111;
            7'd37:   count2keep = 64'b0000000000000000000000000001111111111111111111111111111111111111;
            7'd38:   count2keep = 64'b0000000000000000000000000011111111111111111111111111111111111111;
            7'd39:   count2keep = 64'b0000000000000000000000000111111111111111111111111111111111111111;
            7'd40:   count2keep = 64'b0000000000000000000000001111111111111111111111111111111111111111;
            7'd41:   count2keep = 64'b0000000000000000000000011111111111111111111111111111111111111111;
            7'd42:   count2keep = 64'b0000000000000000000000111111111111111111111111111111111111111111;
            7'd43:   count2keep = 64'b0000000000000000000001111111111111111111111111111111111111111111;
            7'd44:   count2keep = 64'b0000000000000000000011111111111111111111111111111111111111111111;
            7'd45:   count2keep = 64'b0000000000000000000111111111111111111111111111111111111111111111;
            7'd46:   count2keep = 64'b0000000000000000001111111111111111111111111111111111111111111111;
            7'd47:   count2keep = 64'b0000000000000000011111111111111111111111111111111111111111111111;
            7'd48:   count2keep = 64'b0000000000000000111111111111111111111111111111111111111111111111;
            7'd49:   count2keep = 64'b0000000000000001111111111111111111111111111111111111111111111111;
            7'd50:   count2keep = 64'b0000000000000011111111111111111111111111111111111111111111111111;
            7'd51:   count2keep = 64'b0000000000000111111111111111111111111111111111111111111111111111;
            7'd52:   count2keep = 64'b0000000000001111111111111111111111111111111111111111111111111111;
            7'd53:   count2keep = 64'b0000000000011111111111111111111111111111111111111111111111111111;
            7'd54:   count2keep = 64'b0000000000111111111111111111111111111111111111111111111111111111;
            7'd55:   count2keep = 64'b0000000001111111111111111111111111111111111111111111111111111111;
            7'd56:   count2keep = 64'b0000000011111111111111111111111111111111111111111111111111111111;
            7'd57:   count2keep = 64'b0000000111111111111111111111111111111111111111111111111111111111;
            7'd58:   count2keep = 64'b0000001111111111111111111111111111111111111111111111111111111111;
            7'd59:   count2keep = 64'b0000011111111111111111111111111111111111111111111111111111111111;
            7'd60:   count2keep = 64'b0000111111111111111111111111111111111111111111111111111111111111;
            7'd61:   count2keep = 64'b0001111111111111111111111111111111111111111111111111111111111111;
            7'd62:   count2keep = 64'b0011111111111111111111111111111111111111111111111111111111111111;
            7'd63:   count2keep = 64'b0111111111111111111111111111111111111111111111111111111111111111;
            7'd64:   count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
            default: count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
        endcase
    endfunction


    localparam [7:0]
    RC_RDMA_WRITE_FIRST   = 8'h06,
    RC_RDMA_WRITE_MIDDLE  = 8'h07,
    RC_RDMA_WRITE_LAST    = 8'h08,
    RC_RDMA_WRITE_LAST_IMD= 8'h09,
    RC_RDMA_WRITE_ONLY    = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
    RC_RDMA_ACK           = 8'h11;

    localparam [2:0]
    STATE_IDLE               = 3'd0,
    STATE_STORE_PAR          = 3'd1,
    STATE_FIRST              = 3'd2,
    STATE_MIDDLE             = 3'd3,
    STATE_LAST               = 3'd4,
    STATE_ONLY               = 3'd5,
    STATE_WRITE_PAYLOAD_LAST = 3'd6,
    STATE_ERROR              = 3'd7;

    reg [2:0] state_reg, state_next;

    //localparam [31:0] LOC_IP_ADDR = {8'd22, 8'd1, 8'd212, 8'd10};
    localparam [15:0] LOC_UDP_PORT = 16'h2123;
    //localparam [15:0] ROCE_UDP_PORT = 16'h12B7;

    reg s_dma_meta_ready_reg = 1'b0, s_dma_meta_ready_next;

    reg roce_bth_valid_next, roce_bth_valid_reg;
    reg roce_reth_valid_next, roce_reth_valid_reg;
    reg roce_immdh_valid_next, roce_immdh_valid_reg;

    reg [DATA_WIDTH   - 1:0] m_roce_payload_axis_tdata_int;
    reg [DATA_WIDTH/8 - 1:0] m_roce_payload_axis_tkeep_int;
    reg                      m_roce_payload_axis_tvalid_int;
    reg                      m_roce_payload_axis_tready_int;
    reg                      m_roce_payload_axis_tlast_int;
    reg                      m_roce_payload_axis_tuser_int;

    reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
    reg m_roce_reth_valid_reg = 1'b0, m_roce_reth_valid_next;
    reg m_roce_immdh_valid_reg = 1'b0, m_roce_immdh_valid_next;


    reg [7:0] roce_bth_op_code_next, roce_bth_op_code_reg;
    reg [15:0] roce_bth_p_key_next, roce_bth_p_key_reg;
    reg [23:0] roce_bth_psn_next, roce_bth_psn_reg;
    reg [23:0] roce_bth_dest_qp_next, roce_bth_dest_qp_reg;
    reg roce_bth_ack_req_next, roce_bth_ack_req_reg;

    reg [63:0] roce_reth_v_addr_next, roce_reth_v_addr_reg;
    reg [31:0] roce_reth_r_key_next, roce_reth_r_key_reg;
    reg [31:0] roce_reth_length_next, roce_reth_length_reg;

    reg [31:0] roce_immdh_data_next, roce_immdh_data_reg;

    reg [47:0] eth_dest_mac_next, eth_dest_mac_reg;
    reg [47:0] eth_src_mac_next, eth_src_mac_reg;
    reg [15:0] eth_type_next, eth_type_reg;
    reg [3:0] ip_version_next, ip_version_reg;
    reg [3:0] ip_ihl_next, ip_ihl_reg;
    reg [5:0] ip_dscp_next, ip_dscp_reg;
    reg [1:0] ip_ecn_next, ip_ecn_reg;
    reg [15:0] ip_identification_next, ip_identification_reg;
    reg [2:0] ip_flags_next, ip_flags_reg;
    reg [12:0] ip_fragment_offset_next, ip_fragment_offset_reg;
    reg [7:0] ip_ttl_next, ip_ttl_reg;
    reg [7:0] ip_protocol_next, ip_protocol_reg;
    reg [15:0] ip_header_checksum_next, ip_header_checksum_reg;
    reg [31:0] ip_source_ip_next, ip_source_ip_reg;
    reg [31:0] ip_dest_ip_next, ip_dest_ip_reg;
    reg [15:0] udp_source_port_next, udp_source_port_reg;
    reg [15:0] udp_dest_port_next, udp_dest_port_reg;
    reg [15:0] udp_length_next, udp_length_reg;
    reg [15:0] udp_checksum_next, udp_checksum_reg;


    reg [170:0] qp_info;
    //assign qp_info[2:0]     = 3'b010;  //qp_state
    //assign qp_info[26:3]    = 24'h000016;  //loc_qpn
    //assign qp_info[50:27]   = 24'h543210;  //rem_psn
    //assign qp_info[74:51]   = 24'h012345;  //loc_psn
    //assign qp_info[106:52]  = 32'h11223344;  //r_key
    //assign qp_info[170:107] = 64'h000000000000;  //vaddr

    reg [154:0] qp_conn;
    //assign qp_conn[23:0]  = 24'h000017;  //loc_qpn
    //assign qp_conn[47:24] = 24'h000016;  //rem_qpn
    //assign qp_conn[79:48] = 32'h0BD40116;  //rem_ip_addr
    //assign qp_conn[95:80] = ROCE_UDP_PORT;  //rem_udp_port

    reg [ 95:0] tx_metadata;
    //assign tx_metadata[31:0]  = 32'd3200;  //dma_length
    //assign tx_metadata[95:32] = 64'h00001122334455;  //rem_addr

    reg is_immediate_reg;

    reg [31:0] remaining_length_next, remaining_length_reg;
    reg [13:0] packet_inst_length_next, packet_inst_length_reg; // MAX 16384
    reg [31:0] total_packet_inst_length_next, total_packet_inst_length_reg;

    reg [23:0] psn_next, psn_reg;

    reg  [               2:0] axis_valid_shreg;

    wire                      first_axi_frame;
    wire                      last_axi_frame;

    reg  [  DATA_WIDTH - 1:0] last_word_data_reg = {DATA_WIDTH{1'b0}};
    reg  [DATA_WIDTH/8 - 1:0] last_word_keep_reg = {DATA_WIDTH / 8{1'b0}};


    // internal datapath
    reg  [  DATA_WIDTH - 1:0] m_axis_tdata_int;
    reg  [DATA_WIDTH/8 - 1:0] m_axis_tkeep_int;
    reg                       m_axis_tvalid_int;
    reg                       m_axis_tready_int_reg = 1'b0;
    reg                       m_axis_tlast_int;
    reg                       m_axis_tuser_int;
    wire                      m_axis_tready_int_early;

    reg                       s_axis_tready_next;
    reg                       s_axis_tready_reg;

    // datapath control signals
    reg store_last_word;
    reg store_parameters;

    assign s_dma_meta_ready   = s_dma_meta_ready_reg;
    assign s_axis_tready      = s_axis_tready_reg;

    always @* begin

        state_next                    = STATE_IDLE;

        s_axis_tready_next            = 1'b0;

        store_parameters              = 1'b0;

        store_last_word               = 1'b0;

        roce_bth_valid_next           = roce_bth_valid_reg && !m_roce_bth_ready;
        roce_reth_valid_next          = roce_reth_valid_reg && !m_roce_reth_ready;
        roce_immdh_valid_next         = roce_immdh_valid_reg && !m_roce_immdh_ready;

        remaining_length_next         = remaining_length_reg;
        packet_inst_length_next       = packet_inst_length_reg;
        total_packet_inst_length_next = total_packet_inst_length_reg;

        psn_next                      = psn_reg;

        eth_dest_mac_next             = eth_dest_mac_reg;
        eth_src_mac_next              = eth_src_mac_reg;
        eth_type_next                 = eth_type_reg;

        ip_version_next               = ip_version_reg;
        ip_ihl_next                   = ip_ihl_reg;
        ip_dscp_next                  = ip_dscp_reg;
        ip_ecn_next                   = ip_ecn_reg;
        ip_identification_next        = ip_identification_reg;
        ip_flags_next                 = ip_flags_reg;
        ip_fragment_offset_next       = ip_fragment_offset_reg;
        ip_ttl_next                   = ip_ttl_reg;
        ip_protocol_next              = ip_protocol_reg;
        ip_header_checksum_next       = ip_header_checksum_reg;
        ip_source_ip_next             = ip_source_ip_reg;
        ip_dest_ip_next               = ip_dest_ip_reg;

        udp_source_port_next          = udp_source_port_reg;
        udp_dest_port_next            = udp_dest_port_reg;
        udp_length_next               = udp_length_reg;
        udp_checksum_next             = udp_checksum_reg;

        roce_bth_op_code_next         = roce_bth_op_code_reg;
        roce_bth_p_key_next           = roce_bth_p_key_reg;
        roce_bth_psn_next             = roce_bth_psn_reg;
        roce_bth_dest_qp_next         = roce_bth_dest_qp_reg;
        roce_bth_ack_req_next         = roce_bth_ack_req_reg;
        roce_reth_v_addr_next         = roce_reth_v_addr_reg;
        roce_reth_r_key_next          = roce_reth_r_key_reg;
        roce_reth_length_next         = roce_reth_length_reg;
        roce_immdh_data_next          = roce_immdh_data_reg;

        s_dma_meta_ready_next         = 1'b0;

        m_axis_tdata_int              = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_int              = {DATA_WIDTH / 8{1'b0}};
        m_axis_tvalid_int             = 1'b0;
        m_axis_tlast_int              = 1'b0;
        m_axis_tuser_int              = 1'b0;


        case (state_reg)
            STATE_IDLE: begin
                s_dma_meta_ready_next               = !roce_bth_valid_next;
                if (s_dma_meta_ready && s_dma_meta_valid) begin
                    store_parameters = 1'b1;
                    s_dma_meta_ready_next = 1'b0;
                    s_axis_tready_next = 1'b0;
                    state_next       = STATE_STORE_PAR;
                end
            end
            STATE_STORE_PAR: begin
                udp_dest_port_next = udp_dest_port_reg;

                //if (m_axis_tready_int_reg) begin
                //    s_axis_tready_next = m_axis_tready_int_early;
                //end
                //s_axis_tready_next = m_axis_tready_int_early;
                //s_axis_tready_next = 1'b1;

                //m_axis_tdata_int   = s_axis_tdata;
                //m_axis_tkeep_int   = s_axis_tkeep;
                //m_axis_tlast_int   = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                //m_axis_tuser_int   = s_axis_tuser;
                //m_axis_tlast_int  = s_axis_tlast;
                //if (m_axis_tready_int_reg) begin
                //    m_axis_tvalid_int = s_axis_tvalid;
                //end

                s_axis_tready_next = m_axis_tready_int_early;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tready && s_axis_tvalid) begin

                    //m_axis_tdata_int   = s_axis_tdata;
                    //m_axis_tkeep_int   = s_axis_tkeep;
                    //m_axis_tlast_int   = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                    //m_axis_tuser_int   = s_axis_tuser;
                    //m_axis_tvalid_int = s_axis_tvalid;

                    //if (m_axis_tready_int_reg) begin
                    //    m_axis_tvalid_int = s_axis_tvalid;
                    //end

                    remaining_length_next = tx_metadata[31:0] - DATA_WIDTH / 8;
                    packet_inst_length_next = DATA_WIDTH / 8;
                    total_packet_inst_length_next = DATA_WIDTH / 8;
                    if (tx_metadata[31:0] <= pmtu) begin
                        state_next            = STATE_ONLY;
                        s_dma_meta_ready_next = 1'b0;
                        roce_bth_valid_next   = 1'b1;
                        roce_reth_valid_next  = 1'b1;
                        roce_immdh_valid_next = is_immediate_reg;
                        // TODO add option for immediate 

                        ip_source_ip_next     = loc_ip_addr;
                        ip_dest_ip_next       = qp_conn[79:48];

                        udp_source_port_next  = LOC_UDP_PORT;
                        udp_dest_port_next    = RoCE_udp_port;
                        if (is_immediate_reg) begin
                            udp_length_next = tx_metadata[31:0] + 12 + 16 + 4 + 8;
                            // dma length (less than PMTU) + BTH + RETH + + IMMDH UDP HEADER 
                        end else begin
                            udp_length_next = tx_metadata[31:0] + 12 + 16 + 8;
                            // dma length (less than PMTU) + BTH + RETH + UDP HEADER 
                        end


                        roce_bth_op_code_next = is_immediate_reg ? RC_RDMA_WRITE_ONLY_IMD : RC_RDMA_WRITE_ONLY;
                        roce_bth_p_key_next   = 16'hFFFF;
                        roce_bth_psn_next     = qp_info[74:51];
                        roce_bth_dest_qp_next = qp_conn[47:24];
                        roce_bth_ack_req_next = 1'b1;
                        roce_reth_v_addr_next = tx_metadata[95:32];
                        roce_reth_r_key_next  = qp_info[106:75];
                        roce_reth_length_next = tx_metadata[31:0];
                        roce_immdh_data_next  = 32'hDEADBEEF; //TODO change this

                        psn_next              = qp_info[74:51];
                    end else begin
                        state_next            = STATE_FIRST;
                        s_dma_meta_ready_next = 1'b0;
                        roce_bth_valid_next   = 1'b1;
                        roce_reth_valid_next  = 1'b1;
                        roce_immdh_valid_next = 1'b0;

                        ip_source_ip_next     = loc_ip_addr;
                        ip_dest_ip_next       = qp_conn[79:48];

                        udp_source_port_next  = LOC_UDP_PORT;
                        udp_dest_port_next    = RoCE_udp_port;
                        udp_length_next       = pmtu + 12 + 16 + 8;
                        // PMTU + BTH + RETH + UDP HEADER

                        roce_bth_op_code_next = RC_RDMA_WRITE_FIRST;
                        roce_bth_p_key_next   = 16'hFFFF;
                        roce_bth_psn_next     = qp_info[74:51];
                        roce_bth_dest_qp_next = qp_conn[47:24];
                        roce_bth_ack_req_next = 1'b1;
                        roce_reth_v_addr_next = tx_metadata[95:32];
                        roce_reth_r_key_next  = qp_info[106:75];
                        roce_reth_length_next = tx_metadata[31:0];
                        roce_immdh_data_next  = 32'hDEADBEEF;

                        psn_next              = qp_info[74:51];
                    end
                end else begin
                    state_next       = STATE_STORE_PAR;
                end
            end
            STATE_FIRST: begin

                state_next = state_reg;


                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                //if (m_axis_tready_int_reg) begin
                //    m_axis_tvalid_int = 1'b1;
                //end

                s_axis_tready_next = m_axis_tready_int_early;

                if (s_axis_tready && s_axis_tvalid) begin
                    remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                    packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                    total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                    //if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
                    if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8 <= pmtu) begin
                        packet_inst_length_next = 14'd0;
                        state_next = STATE_LAST;
                        roce_bth_valid_next = 1'b1;
                        roce_reth_valid_next = 1'b0;
                        roce_immdh_valid_next = s_is_immediate;

                        if (roce_bth_valid_next) begin
                            if (s_is_immediate) begin
                                udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8 + 4; // no reth
                                // remaining length + BTH + UDP HEADER
                            end else begin
                                udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8; // no reth
                                // remaining length + BTH + UDP HEADER
                            end
                        end
                        roce_bth_op_code_next = s_is_immediate ? RC_RDMA_WRITE_LAST_IMD : RC_RDMA_WRITE_LAST;
                        roce_bth_psn_next     = psn_reg + 1;
                        roce_bth_ack_req_next = 1'b1;

                        psn_next              = psn_reg + 1;

                        //end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
                    end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8 > pmtu) begin
                        packet_inst_length_next = 14'd0;
                        state_next              = STATE_MIDDLE;
                        roce_bth_valid_next     = 1'b1;
                        roce_reth_valid_next    = 1'b0;
                        roce_immdh_valid_next   = 1'b0;

                        udp_length_next         = pmtu + 12 + 8; //no RETH
                        // PMTU + BTH + UDP HEADER

                        roce_bth_op_code_next   = RC_RDMA_WRITE_MIDDLE;
                        roce_bth_psn_next       = psn_reg + 1;
                        roce_bth_ack_req_next   = 1'b1;

                        psn_next                = psn_reg + 1;
                    end
                end
            end
            STATE_MIDDLE: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                //if (m_axis_tready_int_reg) begin
                //    m_axis_tvalid_int = 1'b1;
                //end

                s_axis_tready_next = m_axis_tready_int_early;


                if (s_axis_tready && s_axis_tvalid) begin
                    remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                    packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                    total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                    //if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
                    if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8 <= pmtu) begin
                        packet_inst_length_next = 14'd0;
                        state_next = STATE_LAST;
                        roce_bth_valid_next = 1'b1;
                        roce_reth_valid_next = 1'b0;
                        roce_immdh_valid_next = s_is_immediate;

                        if (roce_bth_valid_next) begin
                            if (s_is_immediate) begin
                                udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8 + 4; // no reth
                                // remaining length + BTH + UDP HEADER
                            end else begin
                                udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8; // no reth
                                // remaining length + BTH + UDP HEADER
                            end
                        end
                        roce_bth_op_code_next = s_is_immediate ? RC_RDMA_WRITE_LAST_IMD : RC_RDMA_WRITE_LAST;
                        roce_bth_psn_next     = psn_reg + 1;
                        roce_bth_ack_req_next = 1'b1;

                        psn_next              = psn_reg + 1;

                        //end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
                    end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8 > pmtu) begin
                        packet_inst_length_next = 14'd0;
                        state_next              = STATE_MIDDLE;
                        roce_bth_valid_next     = 1'b1;
                        roce_reth_valid_next    = 1'b0;
                        roce_immdh_valid_next   = 1'b0;

                        udp_length_next         = pmtu + 12 + 8; //no RETH
                        // PMTU + BTH + UDP HEADER

                        roce_bth_op_code_next   = RC_RDMA_WRITE_MIDDLE;
                        roce_bth_psn_next       = psn_reg + 1;
                        roce_bth_ack_req_next   = 1'b1;

                        psn_next                = psn_reg + 1;
                    end
                end
            end
            STATE_LAST: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                //if (m_axis_tready_int_reg) begin
                //    m_axis_tvalid_int = 1'b1;
                //end

                s_axis_tready_next = m_axis_tready_int_early;

                store_last_word = 1'b1;

                if (s_axis_tready && s_axis_tvalid) begin

                    if (remaining_length_reg <= DATA_WIDTH / 8) begin
                        // have entire payload
                        if (s_axis_tlast) begin
                            if (keep2count(s_axis_tkeep) < remaining_length_reg) begin
                                // end of frame, but length does not match
                                m_axis_tuser_int = 1'b1;
                            end
                            s_axis_tready_next    = 1'b0;
                            s_dma_meta_ready_next = !roce_bth_valid_next;
                            state_next = STATE_IDLE;
                        end else begin
                            m_axis_tvalid_int = 1'b0;
                            state_next = STATE_WRITE_PAYLOAD_LAST;
                        end
                    end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8> pmtu) begin
                        packet_inst_length_next = 14'd0;
                        total_packet_inst_length_next = 32'd0;
                        state_next = STATE_ERROR;
                    end else begin
                        if (s_axis_tlast) begin
                            // end of frame, but length does not match
                            s_dma_meta_ready_next = !roce_bth_valid_next;
                            m_axis_tuser_int = 1'b1;
                            s_axis_tready_next = 1'b0;
                            state_next = STATE_IDLE;
                        end
                    end

                    remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                    packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                    total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                    //if (remaining_length - DATA_WIDTH / 8 == 0) begin

                end
            end
            STATE_ONLY: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                //if (m_axis_tready_int_reg) begin
                //    m_axis_tvalid_int = 1'b1;
                //end

                s_axis_tready_next = m_axis_tready_int_early;

                store_last_word = 1'b1;

                if (s_axis_tready && s_axis_tvalid) begin

                    if (remaining_length_reg <= DATA_WIDTH / 8) begin
                        // have entire payload
                        if (s_axis_tlast) begin
                            if (keep2count(s_axis_tkeep) < remaining_length_reg[7:0]) begin
                                // end of frame, but length does not match
                                m_axis_tuser_int = 1'b1;
                            end
                            s_dma_meta_ready_next = !roce_bth_valid_next;
                            s_axis_tready_next    = 1'b0;
                            state_next = STATE_IDLE;
                        end else begin
                            m_axis_tvalid_int = 1'b0;
                            state_next = STATE_WRITE_PAYLOAD_LAST;
                        end
                    end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu && remaining_length_reg - DATA_WIDTH / 8 > pmtu) begin
                        packet_inst_length_next = 14'd0;
                        total_packet_inst_length_next = 32'd0;
                        state_next = STATE_ERROR;
                    end else begin
                        if (s_axis_tlast) begin
                            // end of frame, but length does not match
                            s_dma_meta_ready_next = !roce_bth_valid_next;
                            m_axis_tuser_int      = 1'b1;
                            s_axis_tready_next    = 1'b0;
                            state_next = STATE_IDLE;
                        end
                    end

                    remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                    packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                    total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                    //if (remaining_length - DATA_WIDTH / 8 == 0) begin

                end
            end

            STATE_WRITE_PAYLOAD_LAST: begin
                state_next = state_reg;

                m_axis_tdata_int = last_word_data_reg;
                m_axis_tkeep_int = last_word_keep_reg;
                m_axis_tlast_int = s_axis_tlast;
                m_axis_tuser_int = s_axis_tuser;

                s_axis_tready_next = m_axis_tready_int_early;

                if (s_axis_tready && s_axis_tvalid) begin
                    if (s_axis_tlast) begin
                        s_dma_meta_ready_next = !roce_bth_valid_next;
                        s_axis_tready_next = 1'b0;
                        m_axis_tvalid_int = 1'b1;
                        packet_inst_length_next = 14'd0;
                        total_packet_inst_length_next = 32'd0;
                        state_next = STATE_IDLE;
                    end else begin
                        remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                        packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                        total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                        state_next = STATE_WRITE_PAYLOAD_LAST;
                    end
                end else begin
                    remaining_length_next = remaining_length_reg;
                    packet_inst_length_next = packet_inst_length_reg;
                    total_packet_inst_length_next = total_packet_inst_length_reg;
                    state_next = STATE_WRITE_PAYLOAD_LAST;
                end
            end
            STATE_ERROR: begin
                state_next = state_reg;
                m_axis_tdata_int = {DATA_WIDTH{1'b0}};
                m_axis_tkeep_int = {DATA_WIDTH / 8{1'b0}};
                m_axis_tvalid_int = 1'b0;
                m_axis_tlast_int = 1'b0;
                s_axis_tready_next = 1'b0;
                if (rst) begin
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end
            end
        endcase
    end

    assign first_axi_frame = 1'b0;
    assign last_axi_frame  = 1'b0;
    /*
  always @(posedge clk) begin
    first_axi_frame <= (packet_inst_length < DATA_WIDTH / 8) ? 1'b1 : 1'b0;
    last_axi_frame  <= (packet_inst_length + DATA_WIDTH / 8 == PMTU) ? 1'b1 : 1'b0;
  end
  
  always @(posedge clk) begin
    if (rst) begin
      packet_inst_length <= 14'd0;
      total_packet_inst_length <= 14'd0;
    end else begin
      if (s_axis_tvalid && s_axis_tready) begin
        if (packet_inst_length + DATA_WIDTH / 8 == PMTU) begin
          packet_inst_length <= 14'd0;
          total_packet_inst_length <= total_packet_inst_length + DATA_WIDTH / 8;
        end else if (packet_inst_length + DATA_WIDTH / 8 != PMTU && s_axis_tlast) begin
          packet_inst_length <= 14'd0;
          total_packet_inst_length <= 14'd0;
        end else begin
          packet_inst_length <= packet_inst_length + DATA_WIDTH / 8;
          total_packet_inst_length <= total_packet_inst_length + DATA_WIDTH / 8;
        end
      end
    end
  end

  assign remaining_length = s_dma_length - total_packet_inst_length - DATA_WIDTH / 8;

*/
    always @(posedge clk) begin

        if (rst) begin
            state_reg <= STATE_IDLE;
            qp_info = 171'h0;
            qp_conn = 155'h0;
            tx_metadata = 80'h0;

            remaining_length_reg         <= {32{1'b1}};
            packet_inst_length_reg       <= 14'd0;
            total_packet_inst_length_reg <= 32'd0;

            psn_reg                      <= 24'd0;

            eth_dest_mac_reg             <= 48'h0;
            eth_src_mac_reg              <= 48'h0;
            eth_type_reg                 <= 16'h0;
            ip_version_reg               <= 4'd4;
            ip_ihl_reg                   <= 4'd0;
            ip_dscp_reg                  <= 6'h0;
            ip_ecn_reg                   <= 2'h0;
            ip_identification_reg        <= 16'h0;
            ip_flags_reg                 <= 3'b001;
            ip_fragment_offset_reg       <= 13'h0;
            ip_ttl_reg                   <= 8'h40;
            ip_protocol_reg              <= 8'h11;
            ip_header_checksum_reg       <= 16'd0;
            ip_source_ip_reg             <= 32'h0;
            ip_dest_ip_reg               <= 32'h0;
            udp_source_port_reg          <= 16'd0;
            udp_dest_port_reg            <= RoCE_udp_port;
            udp_length_reg               <= 16'h0;
            udp_checksum_reg             <= 16'h0;
            roce_bth_op_code_reg         <= RC_RDMA_WRITE_ONLY;
            roce_bth_p_key_reg           <= 16'd0;
            roce_bth_psn_reg             <= 24'd0;
            roce_bth_dest_qp_reg         <= 24'd0;
            roce_bth_ack_req_reg         <= 1'b0;
            roce_reth_v_addr_reg         <= 48'd0;
            roce_reth_r_key_reg          <= 32'd0;
            roce_reth_length_reg         <= 16'h0;
            roce_immdh_data_reg          <= 32'h0;

        end else begin
            state_reg <= state_next;

            s_axis_tready_reg <= s_axis_tready_next;

            m_roce_bth_valid_reg <= m_roce_bth_valid_next;
            m_roce_reth_valid_reg <= m_roce_reth_valid_next;
            m_roce_immdh_valid_reg <= m_roce_immdh_valid_next;

            s_dma_meta_ready_reg <= s_dma_meta_ready_next;

            remaining_length_reg <= remaining_length_next;
            packet_inst_length_reg <= packet_inst_length_next;
            total_packet_inst_length_reg <= total_packet_inst_length_next;

            psn_reg <= psn_next;

            if (store_parameters) begin
                qp_info <= {{64{1'b0}}, s_r_key, s_rem_psn, s_rem_qpn, 24'h000016, 3'b010};
                //assign qp_info[2:0]     = 3'b010;  //qp_state
                //assign qp_info[26:3]    = 24'h000016;  //loc_qpn
                //assign qp_info[50:27]   = 24'h543210;  //rem_psn
                //assign qp_info[74:51]   = 24'h012345;  //loc_psn
                //assign qp_info[106:75]  = 32'h11223344;  //r_key
                //assign qp_info[170:107] = 64'h000000000000;  //vaddr

                qp_conn <= {RoCE_udp_port, s_rem_ip_addr, s_rem_qpn, 24'h000017};
                //assign qp_conn[23:0]  = 24'h000017;  //loc_qpn
                //assign qp_conn[47:24] = 24'h000016;  //rem_qpn
                //assign qp_conn[79:48] = 32'h0BD40116;  //rem_ip_addr
                //assign qp_conn[95:80] = ROCE_UDP_PORT;  //rem_udp_port

                tx_metadata <= {s_rem_addr, s_dma_length};
                //assign tx_metadata[31:0]  = 32'd3200;  //dma_length
                //assign tx_metadata[79:32] = 64'h001122334455;  //rem_addr

                is_immediate_reg <= s_is_immediate;
            end


            roce_bth_valid_reg   <= roce_bth_valid_next;
            roce_reth_valid_reg  <= roce_reth_valid_next;
            roce_immdh_valid_reg <= roce_immdh_valid_next;

            roce_bth_op_code_reg <= roce_bth_op_code_next;
            roce_bth_p_key_reg   <= roce_bth_p_key_next;
            roce_bth_psn_reg     <= roce_bth_psn_next;
            roce_bth_dest_qp_reg <= roce_bth_dest_qp_next;
            roce_bth_ack_req_reg <= roce_bth_ack_req_next;

            roce_reth_v_addr_reg <= roce_reth_v_addr_next;
            roce_reth_r_key_reg  <= roce_reth_r_key_next;
            roce_reth_length_reg <= roce_reth_length_next;

            roce_immdh_data_reg  <= roce_immdh_data_next;

            ip_source_ip_reg     <= ip_source_ip_next;
            ip_dest_ip_reg       <= ip_dest_ip_next;
            udp_source_port_reg  <= udp_source_port_next;
            udp_dest_port_reg    <= udp_dest_port_next;
            udp_length_reg       <= udp_length_next;


        end

        if (store_last_word) begin
            last_word_data_reg <= m_axis_tdata_int;
            last_word_keep_reg <= m_axis_tkeep_int;
        end

    end

    assign m_roce_bth_valid     = roce_bth_valid_reg;
    assign m_roce_reth_valid    = roce_reth_valid_reg;
    assign m_roce_immdh_valid   = roce_immdh_valid_reg;

    assign m_roce_bth_op_code   = roce_bth_op_code_reg;
    assign m_roce_bth_p_key     = roce_bth_p_key_reg;
    assign m_roce_bth_psn       = roce_bth_psn_reg;
    assign m_roce_bth_dest_qp   = roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req   = roce_bth_ack_req_reg;

    assign m_roce_reth_v_addr   = roce_reth_v_addr_reg;
    assign m_roce_reth_r_key    = roce_reth_r_key_reg;
    assign m_roce_reth_length   = roce_reth_length_reg;

    assign m_roce_immdh_data    = roce_immdh_data_reg;

    assign m_eth_dest_mac       = eth_dest_mac_reg;
    assign m_eth_src_mac        = eth_src_mac_reg;
    assign m_eth_type           = eth_type_reg;
    assign m_ip_version         = ip_version_reg;
    assign m_ip_ihl             = ip_ihl_reg;
    assign m_ip_dscp            = ip_dscp_reg;
    assign m_ip_ecn             = ip_ecn_reg;
    assign m_ip_identification  = ip_identification_reg;
    assign m_ip_flags           = ip_flags_reg;
    assign m_ip_fragment_offset = ip_fragment_offset_reg;
    assign m_ip_ttl             = ip_ttl_reg;
    assign m_ip_protocol        = ip_protocol_reg;
    assign m_ip_header_checksum = ip_header_checksum_reg;
    assign m_ip_source_ip       = ip_source_ip_reg;
    assign m_ip_dest_ip         = ip_dest_ip_reg;

    assign m_udp_source_port    = udp_source_port_reg;
    assign m_udp_dest_port      = udp_dest_port_reg;
    assign m_udp_length         = udp_length_reg;
    assign m_udp_checksum       = udp_checksum_reg;


    // output datapath logic
    reg [   DATA_WIDTH - 1:0] m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] m_axis_tkeep_reg = 8'd0;
    reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                       m_axis_tlast_reg = 1'b0;
    reg                       m_axis_tuser_reg = 1'b0;

    reg [   DATA_WIDTH - 1:0] m_axis_not_masked_tdata_reg = 64'd0;

    reg [   DATA_WIDTH - 1:0] temp_m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] temp_m_axis_tkeep_reg = 8'd0;
    reg temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg temp_m_axis_tlast_reg = 1'b0;
    reg temp_m_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    assign m_roce_payload_axis_tdata = m_axis_tdata_reg;
    assign m_roce_payload_axis_tkeep = m_axis_tkeep_reg;
    assign m_roce_payload_axis_tvalid = m_axis_tvalid_reg;
    assign m_roce_payload_axis_tlast = m_axis_tlast_reg;
    assign m_roce_payload_axis_tuser = m_axis_tuser_reg;


    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);
    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    //assign m_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_int_to_output = 1'b0;
        store_axis_int_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_tready_int_reg) begin
            // input is ready
            if (m_roce_payload_axis_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_temp  = 1'b1;
            end
        end else if (m_roce_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        m_axis_tready_int_reg <= m_axis_tready_int_early;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= m_axis_tdata_int;
            m_axis_tkeep_reg <= m_axis_tkeep_int;
            m_axis_tlast_reg <= m_axis_tlast_int;
            m_axis_tuser_reg <= m_axis_tuser_int;


        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
            m_axis_tuser_reg <= temp_m_axis_tuser_reg;

        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= m_axis_tdata_int;
            temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
            temp_m_axis_tlast_reg <= m_axis_tlast_int;
            temp_m_axis_tuser_reg <= m_axis_tuser_int;

        end

        if (rst) begin
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tready_int_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end



endmodule