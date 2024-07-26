
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_minimal_stack_512 (
    input wire clk,
    input wire rst,

    /*
     * Configuration parameter
     
    input wire [31:0] dma_transfer_length,
    input wire [23:0] rem_qpn,
    input wire [23:0] rem_psn,
    input wire [31:0] r_key,
    input wire [63:0] rem_addr,
    input wire [31:0] rem_ip_addr,

    input wire start_transfer,
    */

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
    input  wire [511:0] s_udp_payload_axis_tdata,
    input  wire [ 63:0] s_udp_payload_axis_tkeep,
    input  wire         s_udp_payload_axis_tvalid,
    output wire         s_udp_payload_axis_tready,
    input  wire         s_udp_payload_axis_tlast,
    input  wire         s_udp_payload_axis_tuser,

    /*
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    input  wire         m_udp_hdr_ready,
    output wire [ 47:0] m_eth_dest_mac,
    output wire [ 47:0] m_eth_src_mac,
    output wire [ 15:0] m_eth_type,
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
    output wire [511:0] m_udp_payload_axis_tdata,
    output wire [ 63:0] m_udp_payload_axis_tkeep,
    output wire         m_udp_payload_axis_tvalid,
    input  wire         m_udp_payload_axis_tready,
    output wire         m_udp_payload_axis_tlast,
    output wire         m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    output wire         error_payload_early_termination,
    /*
     * Configuration
     */
    input  wire [ 12:0] pmtu,
    input  wire [ 15:0] RoCE_udp_port,
    input  wire [ 31:0] loc_ip_addr

);

  reg [31:0] dma_length_reg = 32'd0;
  reg start_1;
  reg start_2;

  // UDP frame connections to CM                
  wire rx_udp_cm_hdr_valid;
  wire rx_udp_cm_hdr_ready;
  wire [47:0] rx_udp_cm_eth_dest_mac;
  wire [47:0] rx_udp_cm_eth_src_mac;
  wire [15:0] rx_udp_cm_eth_type;
  wire [3:0] rx_udp_cm_ip_version;
  wire [3:0] rx_udp_cm_ip_ihl;
  wire [5:0] rx_udp_cm_ip_dscp;
  wire [1:0] rx_udp_cm_ip_ecn;
  wire [15:0] rx_udp_cm_ip_length;
  wire [15:0] rx_udp_cm_ip_identification;
  wire [2:0] rx_udp_cm_ip_flags;
  wire [12:0] rx_udp_cm_ip_fragment_offset;
  wire [7:0] rx_udp_cm_ip_ttl;
  wire [7:0] rx_udp_cm_ip_protocol;
  wire [15:0] rx_udp_cm_ip_header_checksum;
  wire [31:0] rx_udp_cm_ip_source_ip;
  wire [31:0] rx_udp_cm_ip_dest_ip;
  wire [15:0] rx_udp_cm_source_port;
  wire [15:0] rx_udp_cm_dest_port;
  wire [15:0] rx_udp_cm_length;
  wire [15:0] rx_udp_cm_checksum;
  wire [511:0] rx_udp_cm_payload_axis_tdata;
  wire [63:0] rx_udp_cm_payload_axis_tkeep;
  wire rx_udp_cm_payload_axis_tvalid;
  wire rx_udp_cm_payload_axis_tready;
  wire rx_udp_cm_payload_axis_tlast;
  wire rx_udp_cm_payload_axis_tuser;

  // UDP frame connectionsto RoCE RX
  wire rx_udp_RoCE_hdr_valid;
  wire rx_udp_RoCE_hdr_ready;
  wire [47:0] rx_udp_RoCE_eth_dest_mac;
  wire [47:0] rx_udp_RoCE_eth_src_mac;
  wire [15:0] rx_udp_RoCE_eth_type;
  wire [3:0] rx_udp_RoCE_ip_version;
  wire [3:0] rx_udp_RoCE_ip_ihl;
  wire [5:0] rx_udp_RoCE_ip_dscp;
  wire [1:0] rx_udp_RoCE_ip_ecn;
  wire [15:0] rx_udp_RoCE_ip_length;
  wire [15:0] rx_udp_RoCE_ip_identification;
  wire [2:0] rx_udp_RoCE_ip_flags;
  wire [12:0] rx_udp_RoCE_ip_fragment_offset;
  wire [7:0] rx_udp_RoCE_ip_ttl;
  wire [7:0] rx_udp_RoCE_ip_protocol;
  wire [15:0] rx_udp_RoCE_ip_header_checksum;
  wire [31:0] rx_udp_RoCE_ip_source_ip;
  wire [31:0] rx_udp_RoCE_ip_dest_ip;
  wire [15:0] rx_udp_RoCE_source_port;
  wire [15:0] rx_udp_RoCE_dest_port;
  wire [15:0] rx_udp_RoCE_length;
  wire [15:0] rx_udp_RoCE_checksum;
  wire [511:0] rx_udp_RoCE_payload_axis_tdata;
  wire [63:0] rx_udp_RoCE_payload_axis_tkeep;
  wire rx_udp_RoCE_payload_axis_tvalid;
  wire rx_udp_RoCE_payload_axis_tready;
  wire rx_udp_RoCE_payload_axis_tlast;
  wire rx_udp_RoCE_payload_axis_tuser;

  wire [511:0] s_payload_axis_tdata;
  wire [63:0] s_payload_axis_tkeep;
  wire s_payload_axis_tvalid;
  wire s_payload_axis_tlast;
  wire s_payload_axis_tuser;
  wire s_payload_axis_tready;

  wire [511:0] s_payload_fifo_axis_tdata;
  wire [63:0] s_payload_fifo_axis_tkeep;
  wire s_payload_fifo_axis_tvalid;
  wire s_payload_fifo_axis_tlast;
  wire s_payload_fifo_axis_tuser;
  wire s_payload_fifo_axis_tready;

  wire [511:0] m_roce_payload_axis_tdata;
  wire [63:0] m_roce_payload_axis_tkeep;
  wire m_roce_payload_axis_tvalid;
  wire m_roce_payload_axis_tlast;
  wire m_roce_payload_axis_tuser;
  wire m_roce_payload_axis_tready;

  wire roce_bth_valid;
  wire roce_reth_valid;
  wire roce_immdh_valid;
  wire roce_bth_ready;
  wire roce_reth_ready;
  wire roce_immdh_ready;

  wire [7:0] roce_bth_op_code;
  wire [15:0] roce_bth_p_key;
  wire [23:0] roce_bth_psn;
  wire [23:0] roce_bth_dest_qp;
  wire roce_bth_ack_req;

  wire [63:0] roce_reth_v_addr;
  wire [31:0] roce_reth_r_key;
  wire [31:0] roce_reth_length;

  wire [31:0] roce_immdh_data;

  wire [47:0] eth_dest_mac;
  wire [47:0] eth_src_mac;
  wire [15:0] eth_type;
  wire [3:0] ip_version;
  wire [3:0] ip_ihl;
  wire [5:0] ip_dscp;
  wire [1:0] ip_ecn;
  wire [15:0] ip_identification;
  wire [2:0] ip_flags;
  wire [12:0] ip_fragment_offset;
  wire [7:0] ip_ttl;
  wire [7:0] ip_protocol;
  wire [15:0] ip_header_checksum;
  wire [31:0] ip_source_ip;
  wire [31:0] ip_dest_ip;
  wire [15:0] udp_source_port;
  wire [15:0] udp_dest_port;
  wire [15:0] udp_length;
  wire [15:0] udp_checksum;

  wire m_roce_bth_valid;
  wire m_roce_bth_ready;
  wire [7:0] m_roce_bth_op_code;
  wire [15:0] m_roce_bth_p_key;
  wire [23:0] m_roce_bth_psn;
  wire [23:0] m_roce_bth_dest_qp;
  wire m_roce_bth_ack_req;
  wire m_roce_aeth_valid;
  wire m_roce_aeth_ready;
  wire [7:0] m_roce_aeth_syndrome;
  wire [23:0] m_roce_aeth_msn;

  reg [63:0] word_counter = {64{1'b1}} - 64;
  reg [63:0] remaining_words;

  // redirect udp rx traffic either to CM or RoCE RX
  wire s_select_udp = (s_udp_dest_port != 16'h12B7);
  wire s_select_roce = (s_udp_dest_port == 16'h12B7);

  reg s_select_udp_reg = 1'b0;
  reg s_select_roce_reg = 1'b0;

  wire [31:0] qp_init_dma_transfer_length;
  wire [23:0] qp_init_rem_qpn;
  wire [23:0] qp_init_loc_qpn;
  wire [23:0] qp_init_rem_psn;
  wire [31:0] qp_init_r_key;
  wire [63:0] qp_init_rem_addr;
  wire [31:0] qp_init_rem_ip_addr = {8'd22, 8'd1, 8'd212, 8'd11};

  wire [31:0] qp_update_dma_transfer_length;
  wire [23:0] qp_update_rem_qpn;
  wire [23:0] qp_update_loc_qpn;
  wire [23:0] qp_update_rem_psn;
  wire [31:0] qp_update_r_key;
  wire [63:0] qp_update_rem_addr;
  wire [31:0] qp_update_rem_ip_addr;
  wire start_transfer;
  wire update_qp_state;

  wire stop_transfer;
  wire [23:0] last_acked_psn;

  reg [23:0] last_acked_psn_reg;

  wire [31:0] n_transfers;

  reg [31:0] sent_messages = 32'd0;

  reg [31:0] qp_update_dma_transfer_length_reg;
  reg [23:0] qp_update_rem_qpn_reg;
  reg [23:0] qp_update_loc_qpn_reg;
  reg [23:0] qp_update_rem_psn_reg;
  reg [31:0] qp_update_r_key_reg;
  reg [63:0] qp_update_rem_addr_base_reg;
  reg [31:0] qp_update_rem_addr_offset_reg;
  reg [31:0] qp_update_rem_ip_addr_reg;
  reg start_transfer_reg;
  reg update_qp_state_reg;

  wire [31:0] qp_curr_dma_transfer_length;
  wire [23:0] qp_curr_rem_qpn;
  wire [23:0] qp_curr_loc_qpn;
  wire [23:0] qp_curr_rem_psn;
  wire [31:0] qp_curr_r_key;
  wire [63:0] qp_curr_rem_addr;
  wire [31:0] qp_curr_rem_ip_addr;
  wire start_transfer_wire;

  wire metadata_valid;

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


  /*
   * Generate payolad data
   */

  always @(posedge clk) begin
    if (rst) begin
      word_counter   <= {64{1'b1}} - 64;
      dma_length_reg <= 32'd0;
    end else begin
      start_1 <= start_transfer_wire;
      start_2 <= start_1;
      if (s_payload_axis_tvalid && s_payload_axis_tready) begin
        if ((word_counter <= qp_init_dma_transfer_length)) begin
          word_counter <= word_counter + 64;
        end
      end else if (~start_1 && start_transfer_wire) begin
        dma_length_reg <= qp_init_dma_transfer_length;
        word_counter   <= {64{1'b1}} - 64;
      end else if (~start_2 && start_1) begin
        word_counter <= 0;
      end
      remaining_words <= dma_length_reg - word_counter;
    end
  end

  assign s_payload_axis_tdata[31:0] = word_counter[31:0];
  assign s_payload_axis_tdata[63:32] = ~word_counter[31:0];
  assign s_payload_axis_tdata[511:64] = {14{32'hDEADBEEF}};
  assign s_payload_axis_tkeep = s_payload_axis_tlast ? ((count2keep(
      remaining_words
  ) == 7'd0) ? {64{1'b1}} : count2keep(
      remaining_words
  )) : {64{1'b1}};
  assign s_payload_axis_tvalid = ((word_counter < dma_length_reg) ? 1'b1 : 1'b0);
  assign s_payload_axis_tlast = (word_counter + 64 >= dma_length_reg) ? 1'b1 : 1'b0;
  assign s_payload_axis_tuser = 1'b0;

  always @(posedge clk) begin
    if (rst) begin
      s_select_udp_reg  <= 1'b0;
      s_select_roce_reg <= 1'b0;
    end else begin
      if (s_udp_payload_axis_tvalid) begin
        if ((!s_select_udp_reg && !s_select_roce_reg) ||
                (s_udp_payload_axis_tvalid && s_udp_payload_axis_tready && s_udp_payload_axis_tlast)) begin
          s_select_udp_reg  <= s_select_udp;
          s_select_roce_reg <= s_select_roce;
        end
      end else begin
        s_select_udp_reg  <= 1'b0;
        s_select_roce_reg <= 1'b0;
      end
    end
  end

  assign rx_udp_cm_hdr_valid = s_select_udp && s_udp_hdr_valid;
  assign rx_udp_cm_eth_dest_mac = s_eth_dest_mac;
  assign rx_udp_cm_eth_src_mac = s_eth_src_mac;
  assign rx_udp_cm_eth_type = s_eth_type;
  assign rx_udp_cm_ip_version = s_ip_version;
  assign rx_udp_cm_ip_ihl = s_ip_ihl;
  assign rx_udp_cm_ip_dscp = s_ip_dscp;
  assign rx_udp_cm_ip_ecn = s_ip_ecn;
  assign rx_udp_cm_ip_length = s_ip_length;
  assign rx_udp_cm_ip_identification = s_ip_identification;
  assign rx_udp_cm_ip_flags = s_ip_flags;
  assign rx_udp_cm_ip_fragment_offset = s_ip_fragment_offset;
  assign rx_udp_cm_ip_ttl = s_ip_ttl;
  assign rx_udp_cm_ip_protocol = s_ip_protocol;
  assign rx_udp_cm_ip_header_checksum = s_ip_header_checksum;
  assign rx_udp_cm_ip_source_ip = s_ip_source_ip;
  assign rx_udp_cm_ip_dest_ip = s_ip_dest_ip;
  assign rx_udp_cm_source_port = s_udp_source_port;
  assign rx_udp_cm_dest_port = s_udp_dest_port;
  assign rx_udp_cm_length = s_udp_length;
  assign rx_udp_cm_checksum = s_udp_checksum;
  assign rx_udp_cm_payload_axis_tdata = s_udp_payload_axis_tdata;
  assign rx_udp_cm_payload_axis_tkeep = s_udp_payload_axis_tkeep;
  assign rx_udp_cm_payload_axis_tvalid = s_select_udp_reg && s_udp_payload_axis_tvalid;
  assign rx_udp_cm_payload_axis_tlast = s_udp_payload_axis_tlast;
  assign rx_udp_cm_payload_axis_tuser = s_udp_payload_axis_tuser;

  assign rx_udp_RoCE_hdr_valid = s_select_roce && s_udp_hdr_valid;
  assign rx_udp_RoCE_eth_dest_mac = s_eth_dest_mac;
  assign rx_udp_RoCE_eth_src_mac = s_eth_src_mac;
  assign rx_udp_RoCE_eth_type = s_eth_type;
  assign rx_udp_RoCE_ip_version = s_ip_version;
  assign rx_udp_RoCE_ip_ihl = s_ip_ihl;
  assign rx_udp_RoCE_ip_dscp = s_ip_dscp;
  assign rx_udp_RoCE_ip_ecn = s_ip_ecn;
  assign rx_udp_RoCE_ip_length = s_ip_length;
  assign rx_udp_RoCE_ip_identification = s_ip_identification;
  assign rx_udp_RoCE_ip_flags = s_ip_flags;
  assign rx_udp_RoCE_ip_fragment_offset = s_ip_fragment_offset;
  assign rx_udp_RoCE_ip_ttl = s_ip_ttl;
  assign rx_udp_RoCE_ip_protocol = s_ip_protocol;
  assign rx_udp_RoCE_ip_header_checksum = s_ip_header_checksum;
  assign rx_udp_RoCE_ip_source_ip = s_ip_source_ip;
  assign rx_udp_RoCE_ip_dest_ip = s_ip_dest_ip;
  assign rx_udp_RoCE_source_port = s_udp_source_port;
  assign rx_udp_RoCE_dest_port = 16'h12B7;
  assign rx_udp_RoCE_length = s_udp_length;
  assign rx_udp_RoCE_checksum = s_udp_checksum;
  assign rx_udp_RoCE_payload_axis_tdata = s_udp_payload_axis_tdata;
  assign rx_udp_RoCE_payload_axis_tkeep = s_udp_payload_axis_tkeep;
  assign rx_udp_RoCE_payload_axis_tvalid = s_select_roce_reg && s_udp_payload_axis_tvalid;
  assign rx_udp_RoCE_payload_axis_tlast = s_udp_payload_axis_tlast;
  assign rx_udp_RoCE_payload_axis_tuser = s_udp_payload_axis_tuser;

  assign s_udp_hdr_ready = (s_select_udp && rx_udp_cm_hdr_ready) || (s_select_roce && rx_udp_RoCE_hdr_ready);

  assign s_udp_payload_axis_tready = (s_select_udp_reg && rx_udp_cm_payload_axis_tready) ||
  (s_select_roce_reg && rx_udp_RoCE_payload_axis_tready);

  axis_fifo #(
      .DEPTH(1024),
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(64),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(0)
  ) input_axis_fifo (
      .clk(clk),
      .rst(rst),

      // AXI input
      .s_axis_tdata(s_payload_axis_tdata),
      .s_axis_tkeep(s_payload_axis_tkeep),
      .s_axis_tvalid(s_payload_axis_tvalid),
      .s_axis_tready(s_payload_axis_tready),
      .s_axis_tlast(s_payload_axis_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser(s_payload_axis_tuser),

      // AXI output
      .m_axis_tdata(s_payload_fifo_axis_tdata),
      .m_axis_tkeep(s_payload_fifo_axis_tkeep),
      .m_axis_tvalid(s_payload_fifo_axis_tvalid),
      .m_axis_tready(s_payload_fifo_axis_tready),
      .m_axis_tlast(s_payload_fifo_axis_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(s_payload_fifo_axis_tuser),

      // Status
      .status_overflow  (),
      .status_bad_frame (),
      .status_good_frame()
  );

  Roce_tx_header_producer #(
      .DATA_WIDTH(512)
  ) Roce_tx_header_producer_instance (
      .clk                       (clk),
      .rst                       (rst),
      .s_dma_length              (qp_curr_dma_transfer_length),
      .s_rem_qpn                 (qp_curr_rem_qpn),
      .s_rem_psn                 (qp_curr_rem_psn),
      .s_r_key                   (qp_curr_r_key),
      .s_rem_ip_addr             (qp_curr_rem_ip_addr),
      .s_rem_addr                (qp_curr_rem_addr),
      .s_is_immediate            (1'b0),
      .s_axis_tdata              (s_payload_fifo_axis_tdata),
      .s_axis_tkeep              (s_payload_fifo_axis_tkeep),
      .s_axis_tvalid             (s_payload_fifo_axis_tvalid),
      .s_axis_tready             (s_payload_fifo_axis_tready),
      .s_axis_tlast              (s_payload_fifo_axis_tlast),
      .s_axis_tuser              (s_payload_fifo_axis_tuser),
      .m_roce_bth_valid          (roce_bth_valid),
      .m_roce_bth_ready          (roce_bth_ready),
      .m_roce_bth_op_code        (roce_bth_op_code),
      .m_roce_bth_p_key          (roce_bth_p_key),
      .m_roce_bth_psn            (roce_bth_psn),
      .m_roce_bth_dest_qp        (roce_bth_dest_qp),
      .m_roce_bth_ack_req        (roce_bth_ack_req),
      .m_roce_reth_valid         (roce_reth_valid),
      .m_roce_reth_ready         (roce_reth_ready),
      .m_roce_reth_v_addr        (roce_reth_v_addr),
      .m_roce_reth_r_key         (roce_reth_r_key),
      .m_roce_reth_length        (roce_reth_length),
      .m_roce_immdh_valid        (roce_immdh_valid),
      .m_roce_immdh_ready        (roce_immdh_ready),
      .m_roce_immdh_data         (roce_immdh_data),
      .m_eth_dest_mac            (eth_dest_mac),
      .m_eth_src_mac             (eth_src_mac),
      .m_eth_type                (eth_type),
      .m_ip_version              (ip_version),
      .m_ip_ihl                  (ip_ihl),
      .m_ip_dscp                 (ip_dscp),
      .m_ip_ecn                  (ip_ecn),
      .m_ip_identification       (ip_identification),
      .m_ip_flags                (ip_flags),
      .m_ip_fragment_offset      (ip_fragment_offset),
      .m_ip_ttl                  (ip_ttl),
      .m_ip_protocol             (ip_protocol),
      .m_ip_header_checksum      (ip_header_checksum),
      .m_ip_source_ip            (ip_source_ip),
      .m_ip_dest_ip              (ip_dest_ip),
      .m_udp_source_port         (udp_source_port),
      .m_udp_dest_port           (udp_dest_port),
      .m_udp_length              (udp_length),
      .m_udp_checksum            (udp_checksum),
      .m_roce_payload_axis_tdata (m_roce_payload_axis_tdata),
      .m_roce_payload_axis_tkeep (m_roce_payload_axis_tkeep),
      .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
      .m_roce_payload_axis_tready(m_roce_payload_axis_tready),
      .m_roce_payload_axis_tlast (m_roce_payload_axis_tlast),
      .m_roce_payload_axis_tuser (m_roce_payload_axis_tuser),
      .pmtu                      (pmtu),
      .RoCE_udp_port             (RoCE_udp_port),
      .loc_ip_addr               (loc_ip_addr)
  );

  RoCE_udp_tx_512 RoCE_udp_tx_512_instance (
      .clk                            (clk),
      .rst                            (rst),
      .s_roce_bth_valid               (roce_bth_valid),
      .s_roce_bth_ready               (roce_bth_ready),
      .s_roce_bth_op_code             (roce_bth_op_code),
      .s_roce_bth_p_key               (roce_bth_p_key),
      .s_roce_bth_psn                 (roce_bth_psn),
      .s_roce_bth_dest_qp             (roce_bth_dest_qp),
      .s_roce_bth_ack_req             (roce_bth_ack_req),
      .s_roce_reth_valid              (roce_reth_valid),
      .s_roce_reth_ready              (roce_reth_ready),
      .s_roce_reth_v_addr             (roce_reth_v_addr),
      .s_roce_reth_r_key              (roce_reth_r_key),
      .s_roce_reth_length             (roce_reth_length),
      .s_roce_immdh_valid             (roce_immdh_valid),
      .s_roce_immdh_ready             (roce_immdh_ready),
      .s_roce_immdh_data              (roce_immdh_data),
      .s_eth_dest_mac                 (eth_dest_mac),
      .s_eth_src_mac                  (eth_src_mac),
      .s_eth_type                     (eth_type),
      .s_ip_version                   (ip_version),
      .s_ip_ihl                       (ip_ihl),
      .s_ip_dscp                      (ip_dscp),
      .s_ip_ecn                       (ip_ecn),
      .s_ip_identification            (ip_identification),
      .s_ip_flags                     (ip_flags),
      .s_ip_fragment_offset           (ip_fragment_offset),
      .s_ip_ttl                       (ip_ttl),
      .s_ip_protocol                  (ip_protocol),
      .s_ip_header_checksum           (ip_header_checksum),
      .s_ip_source_ip                 (ip_source_ip),
      .s_ip_dest_ip                   (ip_dest_ip),
      .s_udp_source_port              (udp_source_port),
      .s_udp_dest_port                (udp_dest_port),
      .s_udp_length                   (udp_length),
      .s_udp_checksum                 (udp_checksum),
      .s_roce_payload_axis_tdata      (m_roce_payload_axis_tdata),
      .s_roce_payload_axis_tkeep      (m_roce_payload_axis_tkeep),
      .s_roce_payload_axis_tvalid     (m_roce_payload_axis_tvalid),
      .s_roce_payload_axis_tready     (m_roce_payload_axis_tready),
      .s_roce_payload_axis_tlast      (m_roce_payload_axis_tlast),
      .s_roce_payload_axis_tuser      (m_roce_payload_axis_tuser),
      .m_udp_hdr_valid                (m_udp_hdr_valid),
      .m_udp_hdr_ready                (m_udp_hdr_ready),
      .m_eth_dest_mac                 (m_eth_dest_mac),
      .m_eth_src_mac                  (m_eth_src_mac),
      .m_eth_type                     (m_eth_type),
      .m_ip_version                   (m_ip_version),
      .m_ip_ihl                       (m_ip_ihl),
      .m_ip_dscp                      (m_ip_dscp),
      .m_ip_ecn                       (m_ip_ecn),
      .m_ip_length                    (m_ip_length),
      .m_ip_identification            (m_ip_identification),
      .m_ip_flags                     (m_ip_flags),
      .m_ip_fragment_offset           (m_ip_fragment_offset),
      .m_ip_ttl                       (m_ip_ttl),
      .m_ip_protocol                  (m_ip_protocol),
      .m_ip_header_checksum           (m_ip_header_checksum),
      .m_ip_source_ip                 (m_ip_source_ip),
      .m_ip_dest_ip                   (m_ip_dest_ip),
      .m_udp_source_port              (m_udp_source_port),
      .m_udp_dest_port                (m_udp_dest_port),
      .m_udp_length                   (m_udp_length),
      .m_udp_checksum                 (m_udp_checksum),
      .m_udp_payload_axis_tdata       (m_udp_payload_axis_tdata),
      .m_udp_payload_axis_tkeep       (m_udp_payload_axis_tkeep),
      .m_udp_payload_axis_tvalid      (m_udp_payload_axis_tvalid),
      .m_udp_payload_axis_tready      (m_udp_payload_axis_tready),
      .m_udp_payload_axis_tlast       (m_udp_payload_axis_tlast),
      .m_udp_payload_axis_tuser       (m_udp_payload_axis_tuser),
      .busy                           (busy),
      .error_payload_early_termination(error_payload_early_termination)
  );

  RoCE_udp_rx_512 #(
      .ENABLE_ICRC_CHECK(1'b0)
  ) RoCE_udp_rx_512_instance (
      .clk(clk),
      .rst(rst),
      .s_udp_hdr_valid(rx_udp_RoCE_hdr_valid),
      .s_udp_hdr_ready(rx_udp_RoCE_hdr_ready),
      .s_eth_dest_mac(rx_udp_RoCE_eth_dest_mac),
      .s_eth_src_mac(rx_udp_RoCE_eth_src_mac),
      .s_eth_type(rx_udp_RoCE_eth_type),
      .s_ip_version(rx_udp_RoCE_ip_version),
      .s_ip_ihl(rx_udp_RoCE_ip_ihl),
      .s_ip_dscp(rx_udp_RoCE_ip_dscp),
      .s_ip_ecn(rx_udp_RoCE_ip_ecn),
      .s_ip_length(rx_udp_RoCE_ip_length),
      .s_ip_identification(rx_udp_RoCE_ip_identification),
      .s_ip_flags(rx_udp_RoCE_ip_flags),
      .s_ip_fragment_offset(rx_udp_RoCE_ip_fragment_offset),
      .s_ip_ttl(rx_udp_RoCE_ip_ttl),
      .s_ip_protocol(rx_udp_RoCE_ip_protocol),
      .s_ip_header_checksum(rx_udp_RoCE_ip_header_checksum),
      .s_ip_source_ip(rx_udp_RoCE_ip_source_ip),
      .s_ip_dest_ip(rx_udp_RoCE_ip_dest_ip),
      .s_udp_source_port(rx_udp_RoCE_source_port),
      .s_udp_dest_port(rx_udp_RoCE_dest_port),
      .s_udp_length(rx_udp_RoCE_length),
      .s_udp_checksum(rx_udp_RoCE_checksum),
      .s_roce_computed_icrc(32'hDEADBEEF),
      .s_udp_payload_axis_tdata(rx_udp_RoCE_payload_axis_tdata),
      .s_udp_payload_axis_tkeep(rx_udp_RoCE_payload_axis_tkeep),
      .s_udp_payload_axis_tvalid(rx_udp_RoCE_payload_axis_tvalid),
      .s_udp_payload_axis_tready(rx_udp_RoCE_payload_axis_tready),
      .s_udp_payload_axis_tlast(rx_udp_RoCE_payload_axis_tlast),
      .s_udp_payload_axis_tuser(rx_udp_RoCE_payload_axis_tuser),
      .m_roce_bth_valid(m_roce_bth_valid),
      .m_roce_bth_ready(1'b1),
      .m_roce_bth_op_code(m_roce_bth_op_code),
      .m_roce_bth_p_key(m_roce_bth_p_key),
      .m_roce_bth_psn(m_roce_bth_psn),
      .m_roce_bth_dest_qp(m_roce_bth_dest_qp),
      .m_roce_bth_ack_req(m_roce_bth_ack_req),
      .m_roce_aeth_valid(m_roce_aeth_valid),
      .m_roce_aeth_ready(1'b1),
      .m_roce_aeth_syndrome(m_roce_aeth_syndrome),
      .m_roce_aeth_msn(m_roce_aeth_msn),
      .m_eth_dest_mac(),
      .m_eth_src_mac(),
      .m_eth_type(),
      .m_ip_version(),
      .m_ip_ihl(),
      .m_ip_dscp(),
      .m_ip_ecn(),
      .m_ip_identification(),
      .m_ip_flags(),
      .m_ip_fragment_offset(),
      .m_ip_ttl(),
      .m_ip_protocol(),
      .m_ip_header_checksum(),
      .m_ip_source_ip(),
      .m_ip_dest_ip(),
      .m_udp_source_port(),
      .m_udp_dest_port(),
      .m_udp_length(),
      .m_udp_checksum(),
      .busy(),
      .error_header_early_termination()
  );

  udp_RoCE_connection_manager_512 #(
      .LISTEN_UDP_PORT(16'h4321)
  ) udp_RoCE_connection_manager_512_instance (
      .clk(clk),
      .rst(rst),
      .s_udp_hdr_valid(rx_udp_cm_hdr_valid),
      .s_udp_hdr_ready(rx_udp_cm_hdr_ready),
      .s_eth_dest_mac(rx_udp_cm_eth_dest_mac),
      .s_eth_src_mac(rx_udp_cm_eth_src_mac),
      .s_eth_type(rx_udp_cm_eth_type),
      .s_ip_version(rx_udp_cm_ip_version),
      .s_ip_ihl(rx_udp_cm_ip_ihl),
      .s_ip_dscp(rx_udp_cm_ip_dscp),
      .s_ip_ecn(rx_udp_cm_ip_ecn),
      .s_ip_length(rx_udp_cm_ip_length),
      .s_ip_identification(rx_udp_cm_ip_identification),
      .s_ip_flags(rx_udp_cm_ip_flags),
      .s_ip_fragment_offset(rx_udp_cm_ip_fragment_offset),
      .s_ip_ttl(rx_udp_cm_ip_ttl),
      .s_ip_protocol(rx_udp_cm_ip_protocol),
      .s_ip_header_checksum(rx_udp_cm_ip_header_checksum),
      .s_ip_source_ip(rx_udp_cm_ip_source_ip),
      .s_ip_dest_ip(rx_udp_cm_ip_dest_ip),
      .s_udp_source_port(rx_udp_cm_source_port),
      .s_udp_dest_port(rx_udp_cm_dest_port),
      .s_udp_length(rx_udp_cm_length),
      .s_udp_checksum(rx_udp_cm_checksum),
      .s_udp_payload_axis_tdata(rx_udp_cm_payload_axis_tdata),
      .s_udp_payload_axis_tkeep(rx_udp_cm_payload_axis_tkeep),
      .s_udp_payload_axis_tvalid(rx_udp_cm_payload_axis_tvalid),
      .s_udp_payload_axis_tready(rx_udp_cm_payload_axis_tready),
      .s_udp_payload_axis_tlast(rx_udp_cm_payload_axis_tlast),
      .s_udp_payload_axis_tuser(rx_udp_cm_payload_axis_tuser),
      .dma_transfer(qp_init_dma_transfer_length),
      .r_key(qp_init_r_key),
      .rem_qpn(qp_init_rem_qpn),
      .loc_qpn(qp_init_loc_qpn),
      .rem_psn(qp_init_rem_psn),
      .loc_psn(),
      .rem_addr(qp_init_rem_addr),
      .start_transfer(start_transfer),
      .metadata_valid(metadata_valid),
      .busy()
  );

  wire [63:0] tot_time_wo_ack_avg;
  wire [63:0] tot_time_avg;
  wire [63:0] latency_first_packet;
  wire [63:0] latency_last_packet;

  RoCE_latency_eval RoCE_latency_eval_instance (
      .clk                    (clk),
      .rst                    (rst),
      .start_i                (start_transfer),
      .s_roce_rx_bth_valid    (m_roce_bth_valid),
      .s_roce_rx_bth_op_code  (m_roce_bth_op_code),
      .s_roce_rx_bth_p_key    (m_roce_bth_p_key),
      .s_roce_rx_bth_psn      (m_roce_bth_psn),
      .s_roce_rx_bth_dest_qp  (m_roce_bth_dest_qp),
      .s_roce_rx_bth_ack_req  (m_roce_bth_ack_req),
      .s_roce_rx_aeth_valid   (m_roce_aeth_valid),
      .s_roce_rx_aeth_syndrome(m_roce_aeth_syndrome),
      .s_roce_rx_aeth_msn     (m_roce_aeth_msn),
      .s_roce_tx_bth_valid    (roce_bth_valid & roce_bth_ready),
      .s_roce_tx_bth_op_code  (roce_bth_op_code),
      .s_roce_tx_bth_p_key    (roce_bth_p_key),
      .s_roce_tx_bth_psn      (roce_bth_psn),
      .s_roce_tx_bth_dest_qp  (roce_bth_dest_qp),
      .s_roce_tx_bth_ack_req  (roce_bth_ack_req),
      .s_roce_tx_reth_valid   (roce_reth_valid),
      .s_roce_tx_reth_v_addr  (roce_reth_v_addr),
      .s_roce_tx_reth_r_key   (roce_reth_r_key),
      .s_roce_tx_reth_length  (roce_reth_length),
      .latency_first_packet   (latency_first_packet),
      .latency_last_packet    (latency_last_packet)
  );

  RoCE_qp_state_module #(
      .REM_ADDR_WIDTH(16)
  ) RoCE_qp_state_module_instance (
      .clk                    (clk),
      .rst                    (rst),
      .rst_qp                 (start_transfer),
      .qp_init_dma_transfer   (qp_init_dma_transfer_length),
      .qp_init_r_key          (qp_init_r_key),
      .qp_init_rem_qpn        (qp_init_rem_qpn),
      .qp_init_loc_qpn        (qp_init_loc_qpn),
      .qp_init_rem_psn        (qp_init_rem_psn),
      .qp_init_loc_psn        (24'd0),
      .qp_init_rem_ip_addr    (qp_init_rem_ip_addr),
      .qp_init_rem_addr       (qp_init_rem_addr),
      .s_roce_tx_bth_valid    (roce_bth_valid),
      .s_roce_tx_bth_ready    (),
      .s_roce_tx_bth_op_code  (roce_bth_op_code),
      .s_roce_tx_bth_p_key    (roce_bth_p_key),
      .s_roce_tx_bth_psn      (roce_bth_psn),
      .s_roce_tx_bth_dest_qp  (roce_bth_dest_qp),
      .s_roce_tx_bth_ack_req  (roce_bth_ack_req),
      .s_roce_tx_reth_valid   (roce_reth_valid),
      .s_roce_tx_reth_v_addr  (roce_reth_v_addr),
      .s_roce_tx_reth_r_key   (roce_reth_r_key),
      .s_roce_tx_reth_length  (roce_reth_length),
      .s_roce_rx_bth_valid    (m_roce_bth_valid),
      .s_roce_rx_bth_ready    (),
      .s_roce_rx_bth_op_code  (m_roce_bth_op_code),
      .s_roce_rx_bth_p_key    (m_roce_bth_p_key),
      .s_roce_rx_bth_psn      (m_roce_bth_psn),
      .s_roce_rx_bth_dest_qp  (m_roce_bth_dest_qp),
      .s_roce_rx_bth_ack_req  (m_roce_bth_ack_req),
      .s_roce_rx_aeth_valid   (m_roce_aeth_valid),
      .s_roce_rx_aeth_ready   (m_roce_aeth_ready),
      .s_roce_rx_aeth_syndrome(m_roce_aeth_syndrome),
      .s_roce_rx_aeth_msn     (m_roce_aeth_msn),
      .last_acked_psn         (last_acked_psn),
      .stop_transfer          (stop_transfer)
  );

  reg [3:0] pmtu_shift;
  reg [11:0] length_pmtu_mask;
  reg new_transfer;

  always @(posedge clk) begin
    case (pmtu)
      13'd256: begin
        pmtu_shift <= 4'd8;
        length_pmtu_mask = {4'h0, {8{1'b1}}};
      end
      13'd512: begin
        pmtu_shift <= 4'd9;
        length_pmtu_mask = {3'h0, {9{1'b1}}};
      end
      13'd1024: begin
        pmtu_shift <= 4'd10;
        length_pmtu_mask = {2'h0, {10{1'b1}}};
      end
      13'd2048: begin
        pmtu_shift <= 4'd11;
        length_pmtu_mask = {1'h0, {11{1'b1}}};
      end
      13'd4096: begin
        pmtu_shift <= 4'd12;
        length_pmtu_mask = {12{1'b1}};
      end
    endcase
  end

  always @(posedge clk) begin
    if (start_transfer) begin
      qp_update_dma_transfer_length_reg <= qp_init_dma_transfer_length;
      qp_update_r_key_reg               <= qp_init_r_key;
      qp_update_rem_qpn_reg             <= qp_init_rem_qpn;
      qp_update_loc_qpn_reg             <= qp_init_loc_qpn;
      qp_update_rem_psn_reg             <= qp_init_rem_psn;
      qp_update_rem_ip_addr_reg         <= qp_init_rem_ip_addr;
      qp_update_rem_addr_base_reg       <= qp_init_rem_addr;
      qp_update_rem_addr_offset_reg     <= 32'd0;
      sent_messages                     <= 32'd0;
    end else begin
      if (roce_bth_valid && roce_bth_ready && roce_reth_valid) begin
        //qp_update_dma_transfer_length_reg <= qp_update_dma_transfer_length_reg;
        //qp_update_r_key_reg <= qp_update_r_key_reg;
        //qp_update_rem_qpn_reg <= qp_update_rem_qpn_reg;
        //qp_update_loc_qpn_reg <= qp_update_loc_qpn_reg;
        if (|(qp_update_dma_transfer_length_reg[11:0] & length_pmtu_mask) == 1'b0) begin
          qp_update_rem_psn_reg <= qp_update_rem_psn_reg + (qp_update_dma_transfer_length_reg >> pmtu_shift);
        end else begin
          qp_update_rem_psn_reg <= qp_update_rem_psn_reg + (qp_update_dma_transfer_length_reg >> pmtu_shift) + 1;
        end

        qp_update_rem_ip_addr_reg <= qp_update_rem_ip_addr_reg;
        qp_update_rem_addr_offset_reg[17:0] <= qp_update_rem_addr_offset_reg[17:0] + qp_update_dma_transfer_length_reg[17:0];
      end
      if (s_payload_axis_tvalid && s_payload_axis_tready && s_payload_axis_tlast) begin
        sent_messages <= sent_messages + 32'd1;
        if (stop_transfer) begin
          new_transfer  <= 1'b0;
          sent_messages <= {32{1'b1}};
        end else if (sent_messages < n_transfers - 32'd1) begin
          new_transfer <= 1'b1;
        end
      end else begin
        new_transfer <= 1'b0;
      end
    end
    if (stop_transfer) begin
      new_transfer  <= 1'b0;
      sent_messages <= {32{1'b1}};
    end
    start_transfer_reg <= start_transfer;
  end

  always @(posedge clk) begin
    if (stop_transfer) begin
      last_acked_psn_reg <= last_acked_psn;
    end
  end

  assign qp_curr_dma_transfer_length = qp_update_dma_transfer_length_reg;
  assign qp_curr_r_key               = qp_update_r_key_reg;
  assign qp_curr_rem_qpn             = qp_update_rem_qpn_reg;
  assign qp_curr_loc_qpn             = qp_update_loc_qpn_reg;
  assign qp_curr_rem_psn             = qp_update_rem_psn_reg;
  assign qp_curr_rem_ip_addr         = qp_update_rem_ip_addr_reg;
  assign qp_curr_rem_addr            = qp_update_rem_addr_base_reg + qp_update_rem_addr_offset_reg;

  assign start_transfer_wire         = start_transfer_reg || new_transfer;

endmodule

`resetall
