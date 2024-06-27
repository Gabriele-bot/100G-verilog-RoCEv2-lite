
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_minimal_stack_64 #(
    parameter DATA_WIDTH = 64
) (
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
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [ 3:0] m_ip_version,
    output wire [ 3:0] m_ip_ihl,
    output wire [ 5:0] m_ip_dscp,
    output wire [ 1:0] m_ip_ecn,
    output wire [15:0] m_ip_length,
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
    output wire [63:0] m_udp_payload_axis_tdata,
    output wire [ 7:0] m_udp_payload_axis_tkeep,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire        busy,
    output wire        error_payload_early_termination

);

  reg  [31:0] dma_length_reg = 32'd0;
  reg         start_1;
  reg         start_2;

  wire [63:0] s_payload_axis_tdata;
  wire [ 7:0] s_payload_axis_tkeep;
  wire        s_payload_axis_tvalid;
  wire        s_payload_axis_tlast;
  wire        s_payload_axis_tuser;
  wire        s_payload_axis_tready;

  wire [63:0] m_udp_payload_axis_not_masked_tdata;
  wire [ 7:0] m_udp_payload_axis_not_masked_tkeep;
  wire        m_udp_payload_axis_not_masked_tvalid;
  wire        m_udp_payload_axis_not_masked_tlast;
  wire        m_udp_payload_axis_not_masked_tuser;
  wire        m_udp_payload_axis_not_masked_tready;

  wire [63:0] m_udp_payload_axis_masked_tdata;
  wire [ 7:0] m_udp_payload_axis_masked_tkeep;
  wire        m_udp_payload_axis_masked_tvalid;
  wire        m_udp_payload_axis_masked_tlast;
  wire        m_udp_payload_axis_masked_tuser;
  wire        m_udp_payload_axis_masked_tready;

  wire [63:0] m_udp_payload_axis_to_icrc_tdata;
  wire [ 7:0] m_udp_payload_axis_to_icrc_tkeep;
  wire        m_udp_payload_axis_to_icrc_tvalid;
  wire        m_udp_payload_axis_to_icrc_tlast;
  wire        m_udp_payload_axis_to_icrc_tuser;
  wire        m_udp_payload_axis_to_icrc_tready;

  wire [63:0] m_udp_payload_axis_to_mask_tdata;
  wire [ 7:0] m_udp_payload_axis_to_mask_tkeep;
  wire        m_udp_payload_axis_to_mask_tvalid;
  wire        m_udp_payload_axis_to_mask_tlast;
  wire        m_udp_payload_axis_to_mask_tuser;
  wire        m_udp_payload_axis_to_mask_tready;

  wire [63:0] m_roce_payload_axis_tdata;
  wire [ 7:0] m_roce_payload_axis_tkeep;
  wire        m_roce_payload_axis_tvalid;
  wire        m_roce_payload_axis_tlast;
  wire        m_roce_payload_axis_tuser;
  wire        m_roce_payload_axis_tready;

  wire        roce_bth_valid;
  wire        roce_reth_valid;
  wire        roce_immdh_valid;
  wire        roce_bth_ready;
  wire        roce_reth_ready;
  wire        roce_immdh_ready;

  wire [ 7:0] roce_bth_op_code;
  wire [15:0] roce_bth_p_key;
  wire [23:0] roce_bth_psn;
  wire [23:0] roce_bth_dest_qp;
  wire        roce_bth_ack_req;

  wire [63:0] roce_reth_v_addr;
  wire [31:0] roce_reth_r_key;
  wire [31:0] roce_reth_length;

  wire [31:0] roce_immdh_data;

  wire        udp_hdr_valid_int;
  reg m_udp_hdr_valid_1, m_udp_hdr_valid_2;

  wire [47:0] eth_dest_mac;
  wire [47:0] eth_src_mac;
  wire [15:0] eth_type;
  wire [ 3:0] ip_version;
  wire [ 3:0] ip_ihl;
  wire [ 5:0] ip_dscp;
  wire [ 1:0] ip_ecn;
  wire [15:0] ip_identification;
  wire [ 2:0] ip_flags;
  wire [12:0] ip_fragment_offset;
  wire [ 7:0] ip_ttl;
  wire [ 7:0] ip_protocol;
  wire [15:0] ip_header_checksum;
  wire [31:0] ip_source_ip;
  wire [31:0] ip_dest_ip;
  wire [15:0] udp_source_port;
  wire [15:0] udp_dest_port;
  wire [15:0] udp_length;
  wire [15:0] udp_checksum;

  reg  [63:0] word_counter = {64{1'b1}} - 8;

  function [3:0] keep2count;
    input [7:0] k;
    casez (k)
      8'bzzzzzzz0: keep2count = 4'd0;
      8'bzzzzzz01: keep2count = 4'd1;
      8'bzzzzz011: keep2count = 4'd2;
      8'bzzzz0111: keep2count = 4'd3;
      8'bzzz01111: keep2count = 4'd4;
      8'bzz011111: keep2count = 4'd5;
      8'bz0111111: keep2count = 4'd6;
      8'b01111111: keep2count = 4'd7;
      8'b11111111: keep2count = 4'd8;
    endcase
  endfunction

  function [7:0] count2keep;
    input [3:0] k;
    case (k)
      4'd0:    count2keep = 8'b00000000;
      4'd1:    count2keep = 8'b00000001;
      4'd2:    count2keep = 8'b00000011;
      4'd3:    count2keep = 8'b00000111;
      4'd4:    count2keep = 8'b00001111;
      4'd5:    count2keep = 8'b00011111;
      4'd6:    count2keep = 8'b00111111;
      4'd7:    count2keep = 8'b01111111;
      4'd8:    count2keep = 8'b11111111;
      default: count2keep = 8'b11111111;
    endcase
  endfunction


  /*
   * Generate payolad data
   */

  always @(posedge clk) begin
    if (rst) begin
      word_counter   <= {64{1'b1}} - 8;
      dma_length_reg <= 32'd0;
    end else begin
      start_1 <= start_transfer;
      start_2 <= start_1;
      if (s_payload_axis_tvalid && s_payload_axis_tready) begin
        if ((word_counter <= dma_transfer_length)) begin
          word_counter <= word_counter + 8;
        end
      end else if (~start_1 && start_transfer) begin
        dma_length_reg <= dma_transfer_length;
        word_counter   <= {64{1'b1}} - 8;
      end else if (~start_2 && start_1) begin
        word_counter <= 0;
      end
    end
  end

  assign s_payload_axis_tdata[31:0] = word_counter;
  assign s_payload_axis_tdata[63:32] = ~word_counter;
  assign s_payload_axis_tkeep = s_payload_axis_tlast ? ((count2keep(
      word_counter
  ) == 4'd0) ? {8{1'b1}} : count2keep(
      word_counter
  )) : {8{1'b1}};
  assign s_payload_axis_tvalid = ((word_counter < dma_length_reg) ? 1'b1 : 1'b0);
  assign s_payload_axis_tlast = (word_counter + 8 >= dma_length_reg) ? 1'b1 : 1'b0;
  assign s_payload_axis_tuser = 1'b0;

  Roce_tx_header_producer #(
      .DATA_WIDTH(DATA_WIDTH)
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

  RoCE_udp_tx_64 RoCE_udp_tx_64_instance (
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
