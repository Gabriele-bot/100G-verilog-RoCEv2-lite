
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_minimal_stack_512 (
    input wire clk,
    input wire rst,

    /*
     * Configuration parameter
     */
    input wire [31:0] dma_transfer_length,
    input wire [23:0] rem_qpn,
    input wire [23:0] rem_psn,
    input wire [31:0] r_key,
    input wire [63:0] rem_addr,
    input wire [31:0] rem_ip_addr,

    input wire start_transfer,

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
    output wire         error_payload_early_termination

);

  reg  [ 31:0] dma_length_reg = 32'd0;
  reg          start_1;
  reg          start_2;

  wire [511:0] s_payload_axis_tdata;
  wire [ 63:0] s_payload_axis_tkeep;
  wire         s_payload_axis_tvalid;
  wire         s_payload_axis_tlast;
  wire         s_payload_axis_tuser;
  wire         s_payload_axis_tready;

  wire [511:0] m_udp_payload_axis_not_masked_tdata;
  wire [ 63:0] m_udp_payload_axis_not_masked_tkeep;
  wire         m_udp_payload_axis_not_masked_tvalid;
  wire         m_udp_payload_axis_not_masked_tlast;
  wire         m_udp_payload_axis_not_masked_tuser;
  wire         m_udp_payload_axis_not_masked_tready;

  wire [511:0] m_udp_payload_axis_masked_tdata;
  wire [ 63:0] m_udp_payload_axis_masked_tkeep;
  wire         m_udp_payload_axis_masked_tvalid;
  wire         m_udp_payload_axis_masked_tlast;
  wire         m_udp_payload_axis_masked_tuser;
  wire         m_udp_payload_axis_masked_tready;

  wire [511:0] m_udp_payload_axis_to_icrc_tdata;
  wire [ 63:0] m_udp_payload_axis_to_icrc_tkeep;
  wire         m_udp_payload_axis_to_icrc_tvalid;
  wire         m_udp_payload_axis_to_icrc_tlast;
  wire         m_udp_payload_axis_to_icrc_tuser;
  wire         m_udp_payload_axis_to_icrc_tready;

  wire [511:0] m_udp_payload_axis_to_mask_tdata;
  wire [ 63:0] m_udp_payload_axis_to_mask_tkeep;
  wire         m_udp_payload_axis_to_mask_tvalid;
  wire         m_udp_payload_axis_to_mask_tlast;
  wire         m_udp_payload_axis_to_mask_tuser;
  wire         m_udp_payload_axis_to_mask_tready;

  wire [511:0] m_roce_payload_axis_tdata;
  wire [ 63:0] m_roce_payload_axis_tkeep;
  wire         m_roce_payload_axis_tvalid;
  wire         m_roce_payload_axis_tlast;
  wire         m_roce_payload_axis_tuser;
  wire         m_roce_payload_axis_tready;

  wire         roce_bth_valid;
  wire         roce_reth_valid;
  wire         roce_immdh_valid;
  wire         roce_bth_ready;
  wire         roce_reth_ready;
  wire         roce_immdh_ready;

  wire [  7:0] roce_bth_op_code;
  wire [ 15:0] roce_bth_p_key;
  wire [ 23:0] roce_bth_psn;
  wire [ 23:0] roce_bth_dest_qp;
  wire         roce_bth_ack_req;

  wire [ 63:0] roce_reth_v_addr;
  wire [ 31:0] roce_reth_r_key;
  wire [ 31:0] roce_reth_length;

  wire [ 31:0] roce_immdh_data;

  wire [ 47:0] eth_dest_mac;
  wire [ 47:0] eth_src_mac;
  wire [ 15:0] eth_type;
  wire [  3:0] ip_version;
  wire [  3:0] ip_ihl;
  wire [  5:0] ip_dscp;
  wire [  1:0] ip_ecn;
  wire [ 15:0] ip_identification;
  wire [  2:0] ip_flags;
  wire [ 12:0] ip_fragment_offset;
  wire [  7:0] ip_ttl;
  wire [  7:0] ip_protocol;
  wire [ 15:0] ip_header_checksum;
  wire [ 31:0] ip_source_ip;
  wire [ 31:0] ip_dest_ip;
  wire [ 15:0] udp_source_port;
  wire [ 15:0] udp_dest_port;
  wire [ 15:0] udp_length;
  wire [ 15:0] udp_checksum;

  reg  [ 63:0] word_counter = {64{1'b1}} - 64;
  reg  [ 63:0] remaining_words;

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
      start_1 <= start_transfer;
      start_2 <= start_1;
      if (s_payload_axis_tvalid && s_payload_axis_tready) begin
        if ((word_counter <= dma_transfer_length)) begin
          word_counter <= word_counter + 64;
        end
      end else if (~start_1 && start_transfer) begin
        dma_length_reg <= dma_transfer_length;
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

  Roce_tx_header_producer #(
      .DATA_WIDTH(512)
  ) Roce_tx_header_producer_instance (
      .clk                       (clk),
      .rst                       (rst),
      .s_dma_length              (dma_transfer_length),
      .s_rem_qpn                 (rem_qpn),
      .s_rem_psn                 (rem_psn),
      .s_r_key                   (r_key),
      .s_rem_ip_addr             (rem_ip_addr),
      .s_rem_addr                (rem_addr),
      .s_axis_tdata              (s_payload_axis_tdata),
      .s_axis_tkeep              (s_payload_axis_tkeep),
      .s_axis_tvalid             (s_payload_axis_tvalid),
      .s_axis_tready             (s_payload_axis_tready),
      .s_axis_tlast              (s_payload_axis_tlast),
      .s_axis_tuser              (s_payload_axis_tuser),
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
      .pmtu                      (13'd2048)
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
  /*
  always @(posedge clk) begin
    m_udp_hdr_valid_1 <= udp_hdr_valid_int;
    m_udp_hdr_valid_2 <= m_udp_hdr_valid_1;
  end

  assign m_udp_hdr_valid = m_udp_hdr_valid_2;

  
  axis_RoCE_icrc_insert_64 #(
      .ENABLE_PADDING  (0),
      .MIN_FRAME_LENGTH(64)
  ) axis_RoCE_icrc_insert_64_instance (
      .clk(clk),
      .rst(rst),
      .s_axis_tdata(m_udp_payload_axis_not_masked_tdata),
      .s_axis_tkeep(m_udp_payload_axis_not_masked_tkeep),
      .s_axis_tvalid(m_udp_payload_axis_not_masked_tvalid),
      .s_axis_tready(m_udp_payload_axis_not_masked_tready),
      .s_axis_tlast(m_udp_payload_axis_not_masked_tlast),
      .s_axis_tuser(m_udp_payload_axis_not_masked_tuser),
      .m_axis_tdata (m_udp_payload_axis_tdata),
      .m_axis_tkeep (m_udp_payload_axis_tkeep),
      .m_axis_tvalid(m_udp_payload_axis_tvalid),
      .m_axis_tready(m_udp_payload_axis_tready),
      .m_axis_tlast (m_udp_payload_axis_tlast),
      .m_axis_tuser (m_udp_payload_axis_tuser),
      .busy()
  );
*/
endmodule

`resetall
