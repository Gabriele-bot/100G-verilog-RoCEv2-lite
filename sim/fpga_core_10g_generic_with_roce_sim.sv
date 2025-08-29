// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * FPGA core logic
 */
module top #(
    parameter MAC_DATA_WIDTH = 64,
    parameter RoCE_DATA_WIDTH = 64
)(
    input wire clk_roce,
    input wire clk_udp,
    input wire clk_mac,
    input wire clk_axi_seg,
    input wire clk_axi_seg_09,
    input wire rst,

    input wire clk_mem,
    input wire rst_mem,
    /*
     * GPIO
     */
    input  wire       btnu,
    input  wire       btnl,
    input  wire       btnd,
    input  wire       btnr,
    input  wire       btnc,
    input  wire [3:0] sw,
    output wire [7:0] led,

    /*
     * Ethernet: QSFP28
     */
    input  wire        xgmii_tx_clk,
    input  wire        xgmii_tx_rst,
    output wire [63:0] xgmii_txd,
    output wire [ 7:0] xgmii_txc,
    input  wire        xgmii_rx_clk,
    input  wire        xgmii_rx_rst,
    input  wire [63:0] xgmii_rxd,
    input  wire [ 7:0] xgmii_rxc
);
  
  parameter DATA_WIDTH = MAC_DATA_WIDTH;
  parameter KEEP_WIDTH = DATA_WIDTH/8;
  
  initial begin
    if (DATA_WIDTH % 64 != 0) begin
        $error("Error: DATA_WIDTH must be mutiple of 64 (instance %m)");
        $finish;
    end
  end


  wire [ 63:0]                                               rx_axis_tdata;
  wire [  7:0]                                               rx_axis_tkeep;
  wire                                                       rx_axis_tvalid;
  wire                                                       rx_axis_tready;
  wire                                                       rx_axis_tlast;
  wire                                                       rx_axis_tuser;

  wire [ 63:0]                                               tx_axis_tdata;
  wire [  7:0]                                               tx_axis_tkeep;
  wire                                                       tx_axis_tvalid;
  wire                                                       tx_axis_tready;
  wire                                                       tx_axis_tlast;
  wire                                                       tx_axis_tuser;

  wire [ 63:0]                                               tx_to_pad_axis_tdata;
  wire [  7:0]                                               tx_to_pad_axis_tkeep;
  wire                                                       tx_to_pad_axis_tvalid;
  wire                                                       tx_to_pad_axis_tready;
  wire                                                       tx_to_pad_axis_tlast;
  wire                                                       tx_to_pad_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      rx_generic_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_generic_axis_tkeep;
  wire                                                       rx_generic_axis_tvalid;
  wire                                                       rx_generic_axis_tready;
  wire                                                       rx_generic_axis_tlast;
  wire                                                       rx_generic_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      tx_generic_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_generic_axis_tkeep;
  wire                                                       tx_generic_axis_tvalid;
  wire                                                       tx_generic_axis_tready;
  wire                                                       tx_generic_axis_tlast;
  wire                                                       tx_generic_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      tx_generic_pad_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_generic_pad_axis_tkeep;
  wire                                                       tx_generic_pad_axis_tvalid;
  wire                                                       tx_generic_pad_axis_tready;
  wire                                                       tx_generic_pad_axis_tlast;
  wire                                                       tx_generic_pad_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      tx_generic_fifo_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_generic_fifo_axis_tkeep;
  wire                                                       tx_generic_fifo_axis_tvalid;
  wire                                                       tx_generic_fifo_axis_tready;
  wire                                                       tx_generic_fifo_axis_tlast;
  wire                                                       tx_generic_fifo_axis_tuser;

  // Ethernet frame between Ethernet modules and UDP stack
  wire                                                       rx_eth_hdr_ready;
  wire                                                       rx_eth_hdr_valid;
  wire [ 47:0]                                               rx_eth_dest_mac;
  wire [ 47:0]                                               rx_eth_src_mac;
  wire [ 15:0]                                               rx_eth_type;
  wire [DATA_WIDTH-1:0]                                      rx_eth_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_eth_payload_axis_tkeep;
  wire                                                       rx_eth_payload_axis_tvalid;
  wire                                                       rx_eth_payload_axis_tready;
  wire                                                       rx_eth_payload_axis_tlast;
  wire                                                       rx_eth_payload_axis_tuser;

  wire                                                       tx_eth_hdr_ready;
  wire                                                       tx_eth_hdr_valid;
  wire [ 47:0]                                               tx_eth_dest_mac;
  wire [ 47:0]                                               tx_eth_src_mac;
  wire [ 15:0]                                               tx_eth_type;
  wire [DATA_WIDTH-1:0]                                      tx_eth_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_eth_payload_axis_tkeep;
  wire                                                       tx_eth_payload_axis_tvalid;
  wire                                                       tx_eth_payload_axis_tready;
  wire                                                       tx_eth_payload_axis_tlast;
  wire                                                       tx_eth_payload_axis_tuser;

  // IP frame connections
  wire                                                       rx_ip_hdr_valid;
  wire                                                       rx_ip_hdr_ready;
  wire [ 47:0]                                               rx_ip_eth_dest_mac;
  wire [ 47:0]                                               rx_ip_eth_src_mac;
  wire [ 15:0]                                               rx_ip_eth_type;
  wire [  3:0]                                               rx_ip_version;
  wire [  3:0]                                               rx_ip_ihl;
  wire [  5:0]                                               rx_ip_dscp;
  wire [  1:0]                                               rx_ip_ecn;
  wire [ 15:0]                                               rx_ip_length;
  wire [ 15:0]                                               rx_ip_identification;
  wire [  2:0]                                               rx_ip_flags;
  wire [ 12:0]                                               rx_ip_fragment_offset;
  wire [  7:0]                                               rx_ip_ttl;
  wire [  7:0]                                               rx_ip_protocol;
  wire [ 15:0]                                               rx_ip_header_checksum;
  wire [ 31:0]                                               rx_ip_source_ip;
  wire [ 31:0]                                               rx_ip_dest_ip;
  wire [DATA_WIDTH-1:0]                                      rx_ip_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_ip_payload_axis_tkeep;
  wire                                                       rx_ip_payload_axis_tvalid;
  wire                                                       rx_ip_payload_axis_tready;
  wire                                                       rx_ip_payload_axis_tlast;
  wire                                                       rx_ip_payload_axis_tuser;

  wire                                                       tx_ip_hdr_valid;
  wire                                                       tx_ip_hdr_ready;
  wire [  5:0]                                               tx_ip_dscp;
  wire [  1:0]                                               tx_ip_ecn;
  wire [ 15:0]                                               tx_ip_length;
  wire [  7:0]                                               tx_ip_ttl;
  wire [  7:0]                                               tx_ip_protocol;
  wire [ 31:0]                                               tx_ip_source_ip;
  wire [ 31:0]                                               tx_ip_dest_ip;
  wire [DATA_WIDTH-1:0]                                      tx_ip_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_ip_payload_axis_tkeep;
  wire                                                       tx_ip_payload_axis_tvalid;
  wire                                                       tx_ip_payload_axis_tready;
  wire                                                       tx_ip_payload_axis_tlast;
  wire                                                       tx_ip_payload_axis_tuser;

  // UDP frame connections
  wire                                                       rx_udp_hdr_valid;
  wire                                                       rx_udp_hdr_ready;
  wire [ 47:0]                                               rx_udp_eth_dest_mac;
  wire [ 47:0]                                               rx_udp_eth_src_mac;
  wire [ 15:0]                                               rx_udp_eth_type;
  wire [  3:0]                                               rx_udp_ip_version;
  wire [  3:0]                                               rx_udp_ip_ihl;
  wire [  5:0]                                               rx_udp_ip_dscp;
  wire [  1:0]                                               rx_udp_ip_ecn;
  wire [ 15:0]                                               rx_udp_ip_length;
  wire [ 15:0]                                               rx_udp_ip_identification;
  wire [  2:0]                                               rx_udp_ip_flags;
  wire [ 12:0]                                               rx_udp_ip_fragment_offset;
  wire [  7:0]                                               rx_udp_ip_ttl;
  wire [  7:0]                                               rx_udp_ip_protocol;
  wire [ 15:0]                                               rx_udp_ip_header_checksum;
  wire [ 31:0]                                               rx_udp_ip_source_ip;
  wire [ 31:0]                                               rx_udp_ip_dest_ip;
  wire [ 15:0]                                               rx_udp_source_port;
  wire [ 15:0]                                               rx_udp_dest_port;
  wire [ 15:0]                                               rx_udp_length;
  wire [ 15:0]                                               rx_udp_checksum;
  wire [DATA_WIDTH-1:0]                                      rx_udp_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_udp_payload_axis_tkeep;
  wire                                                       rx_udp_payload_axis_tvalid;
  wire                                                       rx_udp_payload_axis_tready;
  wire                                                       rx_udp_payload_axis_tlast;
  wire                                                       rx_udp_payload_axis_tuser;

  wire                                                       tx_udp_hdr_valid;
  wire                                                       tx_udp_hdr_ready;
  wire [  5:0]                                               tx_udp_ip_dscp;
  wire [  1:0]                                               tx_udp_ip_ecn;
  wire [  7:0]                                               tx_udp_ip_ttl;
  wire [ 15:0]                                               tx_udp_ip_identification;
  wire [ 31:0]                                               tx_udp_ip_source_ip;
  wire [ 31:0]                                               tx_udp_ip_dest_ip;
  wire [ 15:0]                                               tx_udp_source_port;
  wire [ 15:0]                                               tx_udp_dest_port;
  wire [ 15:0]                                               tx_udp_length;
  wire [ 15:0]                                               tx_udp_checksum;
  wire [DATA_WIDTH-1:0]                                      tx_udp_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_udp_payload_axis_tkeep;
  wire                                                       tx_udp_payload_axis_tvalid;
  wire                                                       tx_udp_payload_axis_tready;
  wire                                                       tx_udp_payload_axis_tlast;
  wire                                                       tx_udp_payload_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      rx_fifo_udp_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_fifo_udp_payload_axis_tkeep;
  wire                                                       rx_fifo_udp_payload_axis_tvalid;
  wire                                                       rx_fifo_udp_payload_axis_tready;
  wire                                                       rx_fifo_udp_payload_axis_tlast;
  wire                                                       rx_fifo_udp_payload_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      tx_fifo_udp_payload_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_fifo_udp_payload_axis_tkeep;
  wire                                                       tx_fifo_udp_payload_axis_tvalid;
  wire                                                       tx_fifo_udp_payload_axis_tready;
  wire                                                       tx_fifo_udp_payload_axis_tlast;
  wire                                                       tx_fifo_udp_payload_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      rx_delay_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_delay_axis_tkeep;
  wire                                                       rx_delay_axis_tvalid;
  wire                                                       rx_delay_axis_tready;
  wire                                                       rx_delay_axis_tlast;
  wire                                                       rx_delay_axis_tuser;
  
  wire [8:0] tx_pause_req, tx_pause_ack;
  
  typedef struct packed {
        logic [2:0]               id;
        logic [11:0]              ena;
        logic [11:0]              sop;
        logic [11:0]              eop;
        logic [11:0]              err;
        logic [11:0][3:0]         mty;
        logic [11:0][127:0]       dat;
    } axis_tx_pkt_t;

  axis_tx_pkt_t    tx_axis_pkt, tx_axis_fifo_pkt;

  // Configuration

  wire [ 2:0] pmtu = 3'd4;
  wire [ 15:0] RoCE_udp_port = 16'h12b7;

  wire [ 47:0] local_mac = 48'h02_00_00_00_00_00;
  wire [ 31:0] local_ip = {8'd22, 8'd1, 8'd212, 8'd10};
  wire [ 31:0] dest_ip = {8'd22, 8'd1, 8'd212, 8'd11};
  wire [ 31:0] gateway_ip = {8'd22, 8'd1, 8'd212, 8'd1};
  wire [ 31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0};

  // IP ports not used
  assign rx_ip_hdr_ready = 1;
  assign rx_ip_payload_axis_tready = 1;

  assign tx_ip_hdr_valid = 0;
  assign tx_ip_dscp = 0;
  assign tx_ip_ecn = 0;
  assign tx_ip_length = 0;
  assign tx_ip_ttl = 0;
  assign tx_ip_protocol = 0;
  assign tx_ip_source_ip = 0;
  assign tx_ip_dest_ip = 0;
  assign tx_ip_payload_axis_tdata = 0;
  assign tx_ip_payload_axis_tkeep = 0;
  assign tx_ip_payload_axis_tvalid = 0;
  assign tx_ip_payload_axis_tlast = 0;
  assign tx_ip_payload_axis_tuser = 0;

  // Loop back UDP
  wire match_cond = rx_udp_dest_port == 1234;
  wire no_match = !match_cond;

  reg match_cond_reg = 0;
  reg no_match_reg = 0;

  integer i;

  always @(posedge clk_mac) begin
    if (rst) begin
      match_cond_reg <= 0;
      no_match_reg   <= 0;
    end else begin
      if (rx_udp_payload_axis_tvalid) begin
        if ((!match_cond_reg && !no_match_reg) ||
                (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready && rx_udp_payload_axis_tlast)) begin
          match_cond_reg <= match_cond;
          no_match_reg   <= no_match;
        end
      end else begin
        match_cond_reg <= 0;
        no_match_reg   <= 0;
      end
    end
  end


  // Place first payload byte onto LEDs
  reg valid_last = 0;
  reg [7:0] led_reg = 0;

  always @(posedge clk_mac) begin
    if (rst) begin
      led_reg <= 0;
    end else begin
      valid_last <= tx_udp_payload_axis_tvalid;
      if (tx_udp_payload_axis_tvalid && !valid_last) begin
        led_reg <= tx_udp_payload_axis_tdata;
      end
    end
  end

  //assign led = sw;
  assign led = led_reg;
  //assign phy_reset_n = !rst;

  eth_mac_10g_fifo #(
      .ENABLE_PADDING(1),
      .ENABLE_DIC(1),
      .MIN_FRAME_LENGTH(64),
      .TX_FIFO_DEPTH(4200),
      .TX_FRAME_FIFO(1),
      .RX_FIFO_DEPTH(4200),
      .RX_FRAME_FIFO(1),
      .PFC_ENABLE(1),
      .PFC_FIFO_ENABLE(8'd3)
  ) eth_mac_10g_fifo_inst (
      .rx_clk(clk_mac),
      .rx_rst(xgmii_rx_rst),
      .tx_clk(clk_mac),
      .tx_rst(xgmii_tx_rst),
      .logic_clk(clk_mac),
      .logic_rst(rst),

      .tx_axis_tdata (tx_axis_tdata),
      .tx_axis_tkeep (tx_axis_tkeep),
      .tx_axis_tvalid(tx_axis_tvalid),
      .tx_axis_tready(tx_axis_tready),
      .tx_axis_tlast (tx_axis_tlast),
      .tx_axis_tuser (tx_axis_tuser),

      .rx_axis_tdata (rx_axis_tdata),
      .rx_axis_tkeep (rx_axis_tkeep),
      .rx_axis_tvalid(rx_axis_tvalid),
      .rx_axis_tready(rx_axis_tready),
      .rx_axis_tlast (rx_axis_tlast),
      .rx_axis_tuser (rx_axis_tuser),

      .xgmii_rxd(xgmii_rxd),
      .xgmii_rxc(xgmii_rxc),
      .xgmii_txd(xgmii_txd),
      .xgmii_txc(xgmii_txc),

      .tx_fifo_overflow  (),
      .tx_fifo_bad_frame (),
      .tx_fifo_good_frame(),
      .rx_error_bad_frame(),
      .rx_error_bad_fcs  (),
      .rx_fifo_overflow  (),
      .rx_fifo_bad_frame (),
      .rx_fifo_good_frame(),
      
      .tx_pause_req_out(tx_pause_req),
      .tx_pause_ack_out(tx_pause_ack),

      .cfg_ifg(8'd12),
      .ctrl_priority_tag(3'd1),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1)
  );
  
  reg clk_05 = 1'b1;
  wire clk_05_wire;
  reg clk_025 = 1'b1;
  wire clk_025_wire;
  always @(posedge clk_udp) begin
 	clk_05 <= ~clk_05;
  end
  
  always @(posedge clk_05_wire) begin
 	clk_025 <= ~clk_025;
  end
  
  
  assign clk_05_wire = clk_05;
  assign clk_025_wire = clk_025;

 
 
  dcmac_pad #(
    .DATA_WIDTH(1024),
    .USER_WIDTH(1)
  ) dcmac_pad_instance (
    .clk(clk_axi_seg),
    .rst(rst),
    .s_axis_tdata(tx_generic_axis_tdata),
    .s_axis_tkeep(tx_generic_axis_tkeep),
    .s_axis_tvalid(tx_generic_axis_tvalid),
    .s_axis_tready(tx_generic_axis_tready),
    .s_axis_tlast(tx_generic_axis_tlast),
    .s_axis_tuser(tx_generic_axis_tuser),
    .m_axis_tdata(tx_generic_pad_axis_tdata),
    .m_axis_tkeep(tx_generic_pad_axis_tkeep),
    .m_axis_tvalid(tx_generic_pad_axis_tvalid),
    .m_axis_tready(tx_generic_pad_axis_tready),
    .m_axis_tlast(tx_generic_pad_axis_tlast),
    .m_axis_tuser(tx_generic_pad_axis_tuser)
  );
  
  
 
  wire [128*8-1:0] s_axis_seg_tdata;
  wire s_axis_seg_tvalid;
  wire s_axis_seg_tready;
  wire [7:0]s_ena;
  wire [7:0]s_sop;
  wire [7:0]s_eop;
  wire [7:0] s_err;
  wire [8*4-1:0] s_mty;
  
  wire [1023:0]                                      s_axis_seg_fifo_tdata;
  wire                                               s_axis_seg_fifo_tvalid;
  wire                                               s_axis_seg_fifo_tready;
  wire [63:0]                                        s_axis_seg_fifo_tuser;
 
  
  axis_2_axi_seg  #(
  //.SEGMENT_FIFO_DEPTH(128)
  ) axis_2_axi_seg_inst (
   	.clk(clk_axi_seg),
	.rst(rst),
	// AXI input
      .s_axis_tdata(tx_generic_pad_axis_tdata),
      .s_axis_tkeep(tx_generic_pad_axis_tkeep),
      .s_axis_tvalid(tx_generic_pad_axis_tvalid),
      .s_axis_tready(tx_generic_pad_axis_tready),
      .s_axis_tlast(tx_generic_pad_axis_tlast),
      .s_axis_tuser(tx_generic_pad_axis_tuser),
       
       //.m_clk(clk_udp),
       //.m_rst(rst),
       
       .m_axis_seg_tvalid(s_axis_seg_tvalid), 
       .m_axis_seg_tready(s_axis_seg_tready),
       .m_axis_seg_tdata({tx_axis_fifo_pkt.dat[7], tx_axis_fifo_pkt.dat[6], tx_axis_fifo_pkt.dat[5], tx_axis_fifo_pkt.dat[4], tx_axis_fifo_pkt.dat[3], tx_axis_fifo_pkt.dat[2], tx_axis_fifo_pkt.dat[1], tx_axis_fifo_pkt.dat[0]}),
       .m_axis_seg_tuser_ena({tx_axis_fifo_pkt.ena[7], tx_axis_fifo_pkt.ena[6], tx_axis_fifo_pkt.ena[5], tx_axis_fifo_pkt.ena[4], tx_axis_fifo_pkt.ena[3], tx_axis_fifo_pkt.ena[2], tx_axis_fifo_pkt.ena[1], tx_axis_fifo_pkt.ena[0]}),
       .m_axis_seg_tuser_sop({tx_axis_fifo_pkt.sop[7], tx_axis_fifo_pkt.sop[6], tx_axis_fifo_pkt.sop[5], tx_axis_fifo_pkt.sop[4], tx_axis_fifo_pkt.sop[3], tx_axis_fifo_pkt.sop[2], tx_axis_fifo_pkt.sop[1], tx_axis_fifo_pkt.sop[0]}),
       .m_axis_seg_tuser_eop({tx_axis_fifo_pkt.eop[7], tx_axis_fifo_pkt.eop[6], tx_axis_fifo_pkt.eop[5], tx_axis_fifo_pkt.eop[4], tx_axis_fifo_pkt.eop[3], tx_axis_fifo_pkt.eop[2], tx_axis_fifo_pkt.eop[1], tx_axis_fifo_pkt.eop[0]}),
       .m_axis_seg_tuser_err({tx_axis_fifo_pkt.err[7], tx_axis_fifo_pkt.err[6], tx_axis_fifo_pkt.err[5], tx_axis_fifo_pkt.err[4], tx_axis_fifo_pkt.err[3], tx_axis_fifo_pkt.err[2], tx_axis_fifo_pkt.err[1], tx_axis_fifo_pkt.err[0]}),
       .m_axis_seg_tuser_mty({tx_axis_fifo_pkt.mty[7], tx_axis_fifo_pkt.mty[6], tx_axis_fifo_pkt.mty[5], tx_axis_fifo_pkt.mty[4], tx_axis_fifo_pkt.mty[3], tx_axis_fifo_pkt.mty[2], tx_axis_fifo_pkt.mty[1], tx_axis_fifo_pkt.mty[0]})
  );
  
  axis_async_fifo #(
      .DEPTH(16),
      .DATA_WIDTH(1024),
      .KEEP_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(64),
      .FRAME_FIFO(0)
  ) middle_fifo (
      .s_clk(clk_axi_seg),
      .s_rst(rst),

      // AXI input
      .s_axis_tvalid(s_axis_seg_tvalid),
      .s_axis_tready(s_axis_seg_tready),
      .s_axis_tdata ({tx_axis_fifo_pkt.dat[7], tx_axis_fifo_pkt.dat[6], tx_axis_fifo_pkt.dat[5], tx_axis_fifo_pkt.dat[4], tx_axis_fifo_pkt.dat[3], tx_axis_fifo_pkt.dat[2], tx_axis_fifo_pkt.dat[1], tx_axis_fifo_pkt.dat[0]}),
      .s_axis_tuser ({{tx_axis_fifo_pkt.ena[7], tx_axis_fifo_pkt.ena[6], tx_axis_fifo_pkt.ena[5], tx_axis_fifo_pkt.ena[4], tx_axis_fifo_pkt.ena[3], tx_axis_fifo_pkt.ena[2], tx_axis_fifo_pkt.ena[1], tx_axis_fifo_pkt.ena[0]},
                      {tx_axis_fifo_pkt.sop[7], tx_axis_fifo_pkt.sop[6], tx_axis_fifo_pkt.sop[5], tx_axis_fifo_pkt.sop[4], tx_axis_fifo_pkt.sop[3], tx_axis_fifo_pkt.sop[2], tx_axis_fifo_pkt.sop[1], tx_axis_fifo_pkt.sop[0]},
                      {tx_axis_fifo_pkt.eop[7], tx_axis_fifo_pkt.eop[6], tx_axis_fifo_pkt.eop[5], tx_axis_fifo_pkt.eop[4], tx_axis_fifo_pkt.eop[3], tx_axis_fifo_pkt.eop[2], tx_axis_fifo_pkt.eop[1], tx_axis_fifo_pkt.eop[0]},
                      {tx_axis_fifo_pkt.err[7], tx_axis_fifo_pkt.err[6], tx_axis_fifo_pkt.err[5], tx_axis_fifo_pkt.err[4], tx_axis_fifo_pkt.err[3], tx_axis_fifo_pkt.err[2], tx_axis_fifo_pkt.err[1], tx_axis_fifo_pkt.err[0]},
                      {tx_axis_fifo_pkt.mty[7], tx_axis_fifo_pkt.mty[6], tx_axis_fifo_pkt.mty[5], tx_axis_fifo_pkt.mty[4], tx_axis_fifo_pkt.mty[3], tx_axis_fifo_pkt.mty[2], tx_axis_fifo_pkt.mty[1], tx_axis_fifo_pkt.mty[0]}}),
      .s_axis_tlast (0),
      .s_axis_tkeep (0),
      .s_axis_tid   (0),
      .s_axis_tdest (0),

      
      .m_clk(clk_axi_seg_09),
      .m_rst(rst),

      // AXI output
      .m_axis_tvalid(s_axis_seg_fifo_tvalid),
      .m_axis_tready(1'b1),
      .m_axis_tdata ({tx_axis_pkt.dat[7], tx_axis_pkt.dat[6], tx_axis_pkt.dat[5], tx_axis_pkt.dat[4], tx_axis_pkt.dat[3], tx_axis_pkt.dat[2], tx_axis_pkt.dat[1], tx_axis_pkt.dat[0]}),
      .m_axis_tuser ({{tx_axis_pkt.ena[7], tx_axis_pkt.ena[6], tx_axis_pkt.ena[5], tx_axis_pkt.ena[4], tx_axis_pkt.ena[3], tx_axis_pkt.ena[2], tx_axis_pkt.ena[1], tx_axis_pkt.ena[0]},
                      {tx_axis_pkt.sop[7], tx_axis_pkt.sop[6], tx_axis_pkt.sop[5], tx_axis_pkt.sop[4], tx_axis_pkt.sop[3], tx_axis_pkt.sop[2], tx_axis_pkt.sop[1], tx_axis_pkt.sop[0]},
                      {tx_axis_pkt.eop[7], tx_axis_pkt.eop[6], tx_axis_pkt.eop[5], tx_axis_pkt.eop[4], tx_axis_pkt.eop[3], tx_axis_pkt.eop[2], tx_axis_pkt.eop[1], tx_axis_pkt.eop[0]},
                      {tx_axis_pkt.err[7], tx_axis_pkt.err[6], tx_axis_pkt.err[5], tx_axis_pkt.err[4], tx_axis_pkt.err[3], tx_axis_pkt.err[2], tx_axis_pkt.err[1], tx_axis_pkt.err[0]},
                      {tx_axis_pkt.mty[7], tx_axis_pkt.mty[6], tx_axis_pkt.mty[5], tx_axis_pkt.mty[4], tx_axis_pkt.mty[3], tx_axis_pkt.mty[2], tx_axis_pkt.mty[1], tx_axis_pkt.mty[0]}})
  );

  
  
  

  axi_seg_2_axis #(
  .AXIS_FIFO_DEPTH(8192)
  ) axi_seg_2_axis_instance (
    .s_clk(clk_axi_seg_09),
    .s_rst(rst),
    .s_axis_seg_tdata({tx_axis_pkt.dat[7], tx_axis_pkt.dat[6], tx_axis_pkt.dat[5], tx_axis_pkt.dat[4], tx_axis_pkt.dat[3], tx_axis_pkt.dat[2], tx_axis_pkt.dat[1], tx_axis_pkt.dat[0]}),
    .s_axis_seg_tvalid(s_axis_seg_fifo_tvalid),
    //.s_axis_seg_tready(),
    .s_ena({tx_axis_pkt.ena[7], tx_axis_pkt.ena[6], tx_axis_pkt.ena[5], tx_axis_pkt.ena[4], tx_axis_pkt.ena[3], tx_axis_pkt.ena[2], tx_axis_pkt.ena[1], tx_axis_pkt.ena[0]}),
    .s_sop({tx_axis_pkt.sop[7], tx_axis_pkt.sop[6], tx_axis_pkt.sop[5], tx_axis_pkt.sop[4], tx_axis_pkt.sop[3], tx_axis_pkt.sop[2], tx_axis_pkt.sop[1], tx_axis_pkt.sop[0]}),
    .s_eop({tx_axis_pkt.eop[7], tx_axis_pkt.eop[6], tx_axis_pkt.eop[5], tx_axis_pkt.eop[4], tx_axis_pkt.eop[3], tx_axis_pkt.eop[2], tx_axis_pkt.eop[1], tx_axis_pkt.eop[0]}),
    .s_err({tx_axis_pkt.err[7], tx_axis_pkt.err[6], tx_axis_pkt.err[5], tx_axis_pkt.err[4], tx_axis_pkt.err[3], tx_axis_pkt.err[2], tx_axis_pkt.err[1], tx_axis_pkt.err[0]}),
    .s_mty({tx_axis_pkt.mty[7], tx_axis_pkt.mty[6], tx_axis_pkt.mty[5], tx_axis_pkt.mty[4], tx_axis_pkt.mty[3], tx_axis_pkt.mty[2], tx_axis_pkt.mty[1], tx_axis_pkt.mty[0]}),
    .m_clk(clk_axi_seg),
    .m_rst(rst),
    .m_axis_tdata(tx_generic_fifo_axis_tdata),
    .m_axis_tkeep(tx_generic_fifo_axis_tkeep),
    .m_axis_tvalid(tx_generic_fifo_axis_tvalid),
    .m_axis_tready(tx_generic_fifo_axis_tready),
    .m_axis_tlast(tx_generic_fifo_axis_tlast),
    .m_axis_tuser(tx_generic_fifo_axis_tuser)
  );
  
  
  
  
  axis_async_fifo_adapter #(
      .DEPTH(4200),
      .S_DATA_WIDTH(DATA_WIDTH),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(KEEP_WIDTH),
      .M_DATA_WIDTH(64),
      .M_KEEP_ENABLE(1),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(0)
  ) eth_tx_axis_fifo (
      .s_clk(clk_axi_seg),
      .s_rst(rst),

      // AXI input
      /*
      .s_axis_tdata (tx_generic_pad_axis_tdata),
      .s_axis_tkeep (tx_generic_pad_axis_tkeep),
      .s_axis_tvalid(tx_generic_pad_axis_tvalid),
      .s_axis_tready(tx_generic_pad_axis_tready),
      .s_axis_tlast (tx_generic_pad_axis_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser(tx_generic_pad_axis_tuser),
      */
      
      
      .s_axis_tdata (tx_generic_fifo_axis_tdata),
      .s_axis_tkeep (tx_generic_fifo_axis_tkeep),
      .s_axis_tvalid(tx_generic_fifo_axis_tvalid),
      .s_axis_tready(tx_generic_fifo_axis_tready),
      .s_axis_tlast (tx_generic_fifo_axis_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser(tx_generic_fifo_axis_tuser),
      
      
      
      .m_clk(clk_mac),
      .m_rst(rst),

      // AXI output
      .m_axis_tdata(tx_axis_tdata),
      .m_axis_tkeep(tx_axis_tkeep),
      .m_axis_tvalid(tx_axis_tvalid),
      .m_axis_tready(tx_axis_tready),
      .m_axis_tlast(tx_axis_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(tx_axis_tuser)
  );


  
  axis_async_fifo_adapter #(
      .DEPTH(4200),
      .S_DATA_WIDTH(64),
      .S_KEEP_ENABLE(1),
      .S_KEEP_WIDTH(8),
      .M_DATA_WIDTH(DATA_WIDTH),
      .M_KEEP_ENABLE(1),
      .M_KEEP_WIDTH(KEEP_WIDTH),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(0)
  ) eth_rx_axis_fifo (
      .s_clk(clk_mac),
      .s_rst(rst),

      // AXI input
      .s_axis_tdata( rx_axis_tdata),
      .s_axis_tkeep( rx_axis_tkeep),
      .s_axis_tvalid(rx_axis_tvalid),
      .s_axis_tready(rx_axis_tready),
      .s_axis_tlast( rx_axis_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser( rx_axis_tuser),
      
      .m_clk(clk_axi_seg),
      .m_rst(rst),

      // AXI output
      .m_axis_tdata (rx_generic_axis_tdata),
      .m_axis_tkeep (rx_generic_axis_tkeep),
      .m_axis_tvalid(rx_generic_axis_tvalid),
      .m_axis_tready(rx_generic_axis_tready),
      .m_axis_tlast (rx_generic_axis_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser (rx_generic_axis_tuser)
  );

  
  network_wrapper_roce_generic #(
    .MAC_DATA_WIDTH(MAC_DATA_WIDTH),
    .STACK_DATA_WIDTH(RoCE_DATA_WIDTH),
    .FIFO_REGS(3),
    .ENABLE_PFC(8'h00),
    .DEBUG(0)
  ) network_wrapper_roce_generic_instance (
    .clk_mac(clk_axi_seg),
    .rst_mac(rst),
    .clk_stack(clk_udp),
    .rst_stack(rst),
    .flow_ctrl_pause         (tx_pause_req[1] || tx_pause_req[8]),
    .m_network_tx_axis_tdata (tx_generic_axis_tdata),
    .m_network_tx_axis_tkeep (tx_generic_axis_tkeep),
    .m_network_tx_axis_tvalid(tx_generic_axis_tvalid),
    .m_network_tx_axis_tready(tx_generic_axis_tready),
    .m_network_tx_axis_tlast (tx_generic_axis_tlast),
    .m_network_tx_axis_tuser (tx_generic_axis_tuser),

    .s_network_rx_axis_tdata (rx_generic_axis_tdata),
    .s_network_rx_axis_tkeep (rx_generic_axis_tkeep),
    .s_network_rx_axis_tvalid(rx_generic_axis_tvalid),
    .s_network_rx_axis_tready(rx_generic_axis_tready),
    .s_network_rx_axis_tlast (rx_generic_axis_tlast),
    .s_network_rx_axis_tuser (rx_generic_axis_tuser),
    
    .m_qp_context_spy (1'b0),
    .m_qp_local_qpn_spy(24'h100),
    
    .ctrl_local_mac_address(48'h00_0A_35_DE_AD_01),
    .ctrl_local_ip({8'd22, 8'd1, 8'd212, 8'd10}),
    .ctrl_clear_arp_cache(1'b0),
    .ctrl_pmtu(3'd4),
    .ctrl_RoCE_udp_port(16'h12B7),
    .ctrl_priority_tag(3'd1),
    
    .pfc_pause_req(8'd0),
    .pfc_pause_ack(),
    
    .transfer_time_avg      (),
    .transfer_time_inst     (),
    .latency_avg            (),
    .latency_inst           (),
    .cfg_latency_avg_po2    (4'd4),
    .cfg_throughput_avg_po2 (5'd4),
    .monitor_loc_qpn        (24'd256)
  );

endmodule

`resetall
