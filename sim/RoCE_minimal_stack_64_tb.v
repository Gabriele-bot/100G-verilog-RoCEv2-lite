`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_minimal_stack_64_tb ();

  parameter C_CLK_PERIOD = 10;  // Clock period (100 Mhz).    


  // ==========================================================================
  // ==                                Signals                               ==
  // ==========================================================================
  // Simulation (DUT inputs and outputs).
  reg         clk;
  reg         rst;

  wire [31:0] dma_transfer_length;
  wire [23:0] rem_qpn;
  wire [23:0] rem_psn;
  wire [31:0] r_key;
  wire [47:0] rem_addr;
  wire [31:0] rem_ip_addr;

  reg  [31:0] dma_transfer_length_reg;
  reg  [23:0] rem_qpn_reg;
  reg  [23:0] rem_psn_reg;
  reg  [31:0] r_key_reg;
  reg  [47:0] rem_addr_reg;
  reg  [31:0] rem_ip_addr_reg;
  wire        start_transfer;

  reg         start_transfer_reg;

  wire        m_udp_hdr_valid;
  wire [47:0] m_eth_dest_mac;
  wire [47:0] m_eth_src_mac;
  wire [15:0] m_eth_type;
  wire [ 3:0] m_ip_version;
  wire [ 3:0] m_ip_ihl;
  wire [ 5:0] m_ip_dscp;
  wire [ 1:0] m_ip_ecn;
  wire [15:0] m_ip_length;
  wire [15:0] m_ip_identification;
  wire [ 2:0] m_ip_flags;
  wire [12:0] m_ip_fragment_offset;
  wire [ 7:0] m_ip_ttl;
  wire [ 7:0] m_ip_protocol;
  wire [15:0] m_ip_header_checksum;
  wire [31:0] m_ip_source_ip;
  wire [31:0] m_ip_dest_ip;
  wire [15:0] m_udp_source_port;
  wire [15:0] m_udp_dest_port;
  wire [15:0] m_udp_length;
  wire [15:0] m_udp_checksum;
  wire [63:0] m_udp_payload_axis_tdata;
  wire [ 7:0] m_udp_payload_axis_tkeep;
  wire        m_udp_payload_axis_tvalid;
  wire        m_udp_payload_axis_tlast;
  wire        m_udp_payload_axis_tuser;



  RoCE_minimal_stack_64 #(
      .DATA_WIDTH(64)
  ) RoCE_minimal_stack_64_instance (
      .clk(clk),
      .rst(rst),
      .dma_transfer_length(dma_transfer_length),
      .rem_qpn(rem_qpn),
      .rem_psn(rem_psn),
      .r_key(r_key),
      .rem_addr(rem_addr),
      .rem_ip_addr(rem_ip_addr),
      .start_transfer(start_transfer),
      .m_udp_hdr_valid(m_udp_hdr_valid),
      .m_udp_hdr_ready(1'b1),
      .m_eth_dest_mac(m_eth_dest_mac),
      .m_eth_src_mac(m_eth_src_mac),
      .m_eth_type(m_eth_type),
      .m_ip_version(m_ip_version),
      .m_ip_ihl(m_ip_ihl),
      .m_ip_dscp(m_ip_dscp),
      .m_ip_ecn(m_ip_ecn),
      .m_ip_length(m_ip_length),
      .m_ip_identification(m_ip_identification),
      .m_ip_flags(m_ip_flags),
      .m_ip_fragment_offset(m_ip_fragment_offset),
      .m_ip_ttl(m_ip_ttl),
      .m_ip_protocol(m_ip_protocol),
      .m_ip_header_checksum(m_ip_header_checksum),
      .m_ip_source_ip(m_ip_source_ip),
      .m_ip_dest_ip(m_ip_dest_ip),
      .m_udp_source_port(m_udp_source_port),
      .m_udp_dest_port(m_udp_dest_port),
      .m_udp_length(m_udp_length),
      .m_udp_checksum(m_udp_checksum),
      .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
      .m_udp_payload_axis_tkeep(m_udp_payload_axis_tkeep),
      .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
      .m_udp_payload_axis_tready(1'b1),
      .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
      .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
      .busy(),
      .error_payload_early_termination()
  );

  // Clock generation.
  always begin
    #(C_CLK_PERIOD / 2) clk = !clk;
  end

  initial begin
    clk = 1'b1;
    rst = 1'b0;
    dma_transfer_length_reg = 32'd128;
    rem_qpn_reg = 24'h16;
    rem_psn_reg = 24'd302;
    r_key_reg = 32'hDEFE;
    rem_addr_reg = 48'h0;
    rem_ip_addr_reg = 32'h0BD40116;

    start_transfer_reg <= 1'b0;


    // Generate first reset.
    #(10 * C_CLK_PERIOD) rst <= 1'b0;
    #(50 * C_CLK_PERIOD) rst <= 1'b1;
    #(50 * C_CLK_PERIOD) rst <= 1'b0;

    #(10 * C_CLK_PERIOD) start_transfer_reg <= 1'b1;

    #(2 * C_CLK_PERIOD) start_transfer_reg <= 1'b0;


  end

  assign dma_transfer_length = dma_transfer_length_reg;
  assign rem_qpn = rem_qpn_reg;
  assign rem_psn = rem_psn_reg;
  assign r_key = r_key_reg;
  assign rem_addr = rem_addr_reg;
  assign rem_ip_addr = rem_ip_addr_reg;

  assign start_transfer = start_transfer_reg;


endmodule : RoCE_minimal_stack_64_tb
