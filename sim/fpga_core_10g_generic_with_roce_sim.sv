// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * FPGA core logic
 */
module top #(
    parameter MAC_DATA_WIDTH     = 64,
    parameter STACK_DATA_WIDTH   = 64
)(
    input wire clk_mac_sim,
    input wire clk_mac,
    input wire clk_stack,
    input wire rst,

    input wire clk_mem,
    input wire rst_mem,

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

  wire [DATA_WIDTH-1:0]                                      rx_generic_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      rx_generic_axis_tkeep;
  wire                                                       rx_generic_axis_tvalid;
  wire                                                       rx_generic_axis_tready;
  wire                                                       rx_generic_axis_tlast;
  wire                                                       rx_generic_axis_tuser;

  wire [DATA_WIDTH-1:0]                                      tx_generic_fifo_axis_tdata;
  wire [KEEP_WIDTH-1:0]                                      tx_generic_fifo_axis_tkeep;
  wire                                                       tx_generic_fifo_axis_tvalid;
  wire                                                       tx_generic_fifo_axis_tready;
  wire                                                       tx_generic_fifo_axis_tlast;
  wire                                                       tx_generic_fifo_axis_tuser;
  
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
      .rx_clk(clk_mac_sim),
      .rx_rst(xgmii_rx_rst),
      .tx_clk(clk_mac_sim),
      .tx_rst(xgmii_tx_rst),
      .logic_clk(clk_mac_sim),
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
      .s_clk(clk_mac),
      .s_rst(rst),
      
      .s_axis_tdata (tx_generic_fifo_axis_tdata),
      .s_axis_tkeep (tx_generic_fifo_axis_tkeep),
      .s_axis_tvalid(tx_generic_fifo_axis_tvalid),
      .s_axis_tready(tx_generic_fifo_axis_tready),
      .s_axis_tlast (tx_generic_fifo_axis_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser(tx_generic_fifo_axis_tuser),
      
      
      
      .m_clk(clk_mac_sim),
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
      .s_clk(clk_mac_sim),
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
      
      .m_clk(clk_mac),
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
    .STACK_DATA_WIDTH(STACK_DATA_WIDTH),
    .FIFO_REGS(3),
    .ENABLE_PFC(8'h00),
    .DEBUG(0)
  ) network_wrapper_roce_generic_instance (
    .clk_mac(clk_mac),
    .rst_mac(rst),
    .clk_stack(clk_stack),
    .rst_stack(rst),
    .flow_ctrl_pause         (tx_pause_req[1] || tx_pause_req[8]),
    .m_network_tx_axis_tdata (tx_generic_fifo_axis_tdata),
    .m_network_tx_axis_tkeep (tx_generic_fifo_axis_tkeep),
    .m_network_tx_axis_tvalid(tx_generic_fifo_axis_tvalid),
    .m_network_tx_axis_tready(tx_generic_fifo_axis_tready),
    .m_network_tx_axis_tlast (tx_generic_fifo_axis_tlast),
    .m_network_tx_axis_tuser (tx_generic_fifo_axis_tuser),

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
