/*

Copyright (c) 2014-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * FPGA top-level module
 */
module fpga (
    /*
     * Clock: 125MHz LVDS
     * Reset: Push button, active low
     */
    input wire clk_125mhz_p,
    input wire clk_125mhz_n,
    input wire reset,

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
     * I2C for board management
     */
    inout wire i2c_scl,
    inout wire i2c_sda,

    /*
     * Ethernet: QSFP28
     */
    output wire [3:0] qsfp1_tx_p,
    output wire [3:0] qsfp1_tx_n,
    input  wire [3:0] qsfp1_rx_p,
    input  wire [3:0] qsfp1_rx_n,
    input  wire       qsfp1_mgt_refclk_0_p,
    input  wire       qsfp1_mgt_refclk_0_n,
    // input  wire       qsfp1_mgt_refclk_1_p,
    // input  wire       qsfp1_mgt_refclk_1_n,
    // output wire       qsfp1_recclk_p,
    // output wire       qsfp1_recclk_n,
    output wire       qsfp1_modsell,
    output wire       qsfp1_resetl,
    input  wire       qsfp1_modprsl,
    input  wire       qsfp1_intl,
    output wire       qsfp1_lpmode,

    output wire [3:0] qsfp2_tx_p,
    output wire [3:0] qsfp2_tx_n,
    input  wire [3:0] qsfp2_rx_p,
    input  wire [3:0] qsfp2_rx_n,
    // input  wire       qsfp2_mgt_refclk_0_p,
    // input  wire       qsfp2_mgt_refclk_0_n,
    // input  wire       qsfp2_mgt_refclk_1_p,
    // input  wire       qsfp2_mgt_refclk_1_n,
    // output wire       qsfp2_recclk_p,
    // output wire       qsfp2_recclk_n,
    output wire       qsfp2_modsell,
    output wire       qsfp2_resetl,
    input  wire       qsfp2_modprsl,
    input  wire       qsfp2_intl,
    output wire       qsfp2_lpmode
);

  // Clock and reset

  wire clk_125mhz_ibufg;

  // Internal 125 MHz clock
  wire clk_125mhz_mmcm_out;
  wire clk_125mhz_int;
  wire rst_125mhz_int;

  // Internal net clock
  wire clk_net_int;
  wire rst_net_int;

  wire mmcm_rst;
  wire mmcm_locked;
  wire mmcm_clkfb;
  
  wire mmcm_rst_ext; 
  wire cmac_rst_ext;  
 
  IBUFGDS #(
      .DIFF_TERM("FALSE"),
      .IBUF_LOW_PWR("FALSE")
  ) clk_125mhz_ibufg_inst (
      .O (clk_125mhz_ibufg),
      .I (clk_125mhz_p),
      .IB(clk_125mhz_n)
  );
  
  vio_ext_rst VIO_ext_rst_inst (
     .clk(clk_125mhz_ibufg),
     .probe_out0(mmcm_rst_ext),
     .probe_out1(cmac_rst_ext)
     
  );
  
  assign mmcm_rst = reset | mmcm_rst_ext; 
  
  
  // MMCM instance
  // 125 MHz in, 125 MHz out
  // PFD range: 10 MHz to 500 MHz
  // VCO range: 800 MHz to 1600 MHz
  // M = 8, D = 1 sets Fvco = 1000 MHz (in range)
  // Divide by 8 to get output frequency of 125 MHz
  MMCME3_BASE #(
      .BANDWIDTH("OPTIMIZED"),
      .CLKOUT0_DIVIDE_F(8),
      .CLKOUT0_DUTY_CYCLE(0.5),
      .CLKOUT0_PHASE(0),
      .CLKOUT1_DIVIDE(1),
      .CLKOUT1_DUTY_CYCLE(0.5),
      .CLKOUT1_PHASE(0),
      .CLKOUT2_DIVIDE(1),
      .CLKOUT2_DUTY_CYCLE(0.5),
      .CLKOUT2_PHASE(0),
      .CLKOUT3_DIVIDE(1),
      .CLKOUT3_DUTY_CYCLE(0.5),
      .CLKOUT3_PHASE(0),
      .CLKOUT4_DIVIDE(1),
      .CLKOUT4_DUTY_CYCLE(0.5),
      .CLKOUT4_PHASE(0),
      .CLKOUT5_DIVIDE(1),
      .CLKOUT5_DUTY_CYCLE(0.5),
      .CLKOUT5_PHASE(0),
      .CLKOUT6_DIVIDE(1),
      .CLKOUT6_DUTY_CYCLE(0.5),
      .CLKOUT6_PHASE(0),
      .CLKFBOUT_MULT_F(8),
      .CLKFBOUT_PHASE(0),
      .DIVCLK_DIVIDE(1),
      .REF_JITTER1(0.010),
      .CLKIN1_PERIOD(8.0),
      .STARTUP_WAIT("FALSE"),
      .CLKOUT4_CASCADE("FALSE")
  ) clk_mmcm_inst (
      .CLKIN1(clk_125mhz_ibufg),
      .CLKFBIN(mmcm_clkfb),
      .RST(mmcm_rst),
      .PWRDWN(1'b0),
      .CLKOUT0(clk_125mhz_mmcm_out),
      .CLKOUT0B(),
      .CLKOUT1(),
      .CLKOUT1B(),
      .CLKOUT2(),
      .CLKOUT2B(),
      .CLKOUT3(),
      .CLKOUT3B(),
      .CLKOUT4(),
      .CLKOUT5(),
      .CLKOUT6(),
      .CLKFBOUT(mmcm_clkfb),
      .CLKFBOUTB(),
      .LOCKED(mmcm_locked)
  );

  BUFG clk_125mhz_bufg_inst (
      .I(clk_125mhz_mmcm_out),
      .O(clk_125mhz_int)
  );

  sync_reset #(
      .N(4)
  ) sync_reset_125mhz_inst (
      .clk(clk_125mhz_int),
      .rst(~mmcm_locked | cmac_rst_ext),
      .out(rst_125mhz_int)
  );

  // GPIO
  wire btnu_int;
  wire btnl_int;
  wire btnd_int;
  wire btnr_int;
  wire btnc_int;
  wire [3:0] sw_int;

  debounce_switch #(
      .WIDTH(9),
      .N(4),
      .RATE(156000)
  ) debounce_switch_inst (
      .clk(clk_net_int),
      .rst(rst_net_int),
      .in ({btnu, btnl, btnd, btnr, btnc, sw}),
      .out({btnu_int, btnl_int, btnd_int, btnr_int, btnc_int, sw_int})
  );

  // SI570 I2C
  wire i2c_scl_i;
  wire i2c_scl_o = 1'b1;
  wire i2c_scl_t = 1'b1;
  wire i2c_sda_i;
  wire i2c_sda_o = 1'b1;
  wire i2c_sda_t = 1'b1;

  assign i2c_scl_i = i2c_scl;
  assign i2c_scl   = i2c_scl_t ? 1'bz : i2c_scl_o;
  assign i2c_sda_i = i2c_sda;
  assign i2c_sda   = i2c_sda_t ? 1'bz : i2c_sda_o;

  // QSFP1 CMAC
  
  assign qsfp1_modsell = 1'b0;
  assign qsfp1_resetl  = 1'b1;
  assign qsfp1_lpmode  = 1'b0;

  wire                                         qsfp1_tx_clk_int;
  wire                                         qsfp1_tx_rst_int;

  wire                                 [511:0] qsfp1_tx_axis_tdata_int;
  wire                                 [ 63:0] qsfp1_tx_axis_tkeep_int;
  wire                                         qsfp1_tx_axis_tvalid_int;
  wire                                         qsfp1_tx_axis_tready_int;
  wire                                         qsfp1_tx_axis_tlast_int;
  wire                                         qsfp1_tx_axis_tuser_int;

  wire                                 [511:0] qsfp1_fifo_tx_axis_tdata_int;
  wire                                 [ 63:0] qsfp1_fifo_tx_axis_tkeep_int;
  wire                                         qsfp1_fifo_tx_axis_tvalid_int;
  wire                                         qsfp1_fifo_tx_axis_tready_int;
  wire                                         qsfp1_fifo_tx_axis_tlast_int;
  wire                                         qsfp1_fifo_tx_axis_tuser_int;

  wire                                         qsfp1_rx_clk_int;
  wire                                         qsfp1_rx_rst_int;

  wire                                 [511:0] qsfp1_rx_axis_tdata_int;
  wire                                 [ 63:0] qsfp1_rx_axis_tkeep_int;
  wire                                         qsfp1_rx_axis_tvalid_int;
  wire                                         qsfp1_rx_axis_tlast_int;
  wire                                         qsfp1_rx_axis_tuser_int;

  wire                                 [511:0] qsfp1_fifo_rx_axis_tdata_int;
  wire                                 [ 63:0] qsfp1_fifo_rx_axis_tkeep_int;
  wire                                         qsfp1_fifo_rx_axis_tvalid_int;
  wire                                         qsfp1_fifo_rx_axis_tlast_int;
  wire                                         qsfp1_fifo_rx_axis_tuser_int;

  wire qsfp1_drp_clk = clk_125mhz_int;
  wire qsfp1_drp_rst = rst_125mhz_int;
  wire                                 [ 23:0] qsfp1_drp_addr;
  wire                                 [ 15:0] qsfp1_drp_di;
  wire                                         qsfp1_drp_en;
  wire                                         qsfp1_drp_we;
  wire                                 [ 15:0] qsfp1_drp_do;
  wire                                         qsfp1_drp_rdy;

  wire                                         qsfp1_tx_enable;
  wire                                         qsfp1_tx_lfc_en  = 1'b1;
  wire                                         qsfp1_tx_lfc_req = 1'b0;
  wire                                 [  7:0] qsfp1_tx_pfc_en  = 8'hFF;
  wire                                 [  7:0] qsfp1_tx_pfc_req = 8'h00;

  wire                                         qsfp1_rx_enable;
  wire                                         qsfp1_rx_status;
  wire                                         qsfp1_rx_lfc_en  = 1'b1;
  wire                                         qsfp1_rx_lfc_req;
  wire                                         qsfp1_rx_lfc_ack;
  wire                                 [  7:0] qsfp1_rx_pfc_en  = 8'hFF;
  wire                                 [  7:0] qsfp1_rx_pfc_req;
  wire                                 [  7:0] qsfp1_rx_pfc_ack; // define queues with axis ID bus??

  wire                                         qsfp1_gtpowergood;

  wire                                         qsfp1_mgt_refclk_0;
  wire                                         qsfp1_mgt_refclk_0_int;
  wire                                         qsfp1_mgt_refclk_0_bufg;

  assign clk_net_int = qsfp1_tx_clk_int;
  assign rst_net_int = qsfp1_tx_rst_int;

  IBUFDS_GTE4 ibufds_gte4_qsfp1_mgt_refclk_0_inst (
      .I    (qsfp1_mgt_refclk_0_p),
      .IB   (qsfp1_mgt_refclk_0_n),
      .CEB  (1'b0),
      .O    (qsfp1_mgt_refclk_0),
      .ODIV2(qsfp1_mgt_refclk_0_int)
  );

  BUFG_GT bufg_gt_qsfp1_mgt_refclk_0_inst (
      .CE     (qsfp1_gtpowergood),
      .CEMASK (1'b1),
      .CLR    (1'b0),
      .CLRMASK(1'b1),
      .DIV    (3'd0),
      .I      (qsfp1_mgt_refclk_0_int),
      .O      (qsfp1_mgt_refclk_0_bufg)
  );

  wire qsfp1_rst;

  sync_reset #(
      .N(4)
  ) qsfp1_sync_reset_inst (
      .clk(qsfp1_mgt_refclk_0_bufg),
      .rst(rst_125mhz_int),
      .out(qsfp1_rst)
  );
  

  cmac_gty_wrapper #(
      .DRP_CLK_FREQ_HZ(125000000),
      .AXIS_DATA_WIDTH(512),
      .AXIS_KEEP_WIDTH(64),
      .TX_SERDES_PIPELINE(0),
      .RX_SERDES_PIPELINE(0),
      .RS_FEC_ENABLE(1)
  ) qsfp1_cmac_inst (
      .xcvr_ctrl_clk(clk_125mhz_int),
      .xcvr_ctrl_rst(qsfp1_rst),

      /*
     * Common
     */
      .xcvr_gtpowergood_out(qsfp1_gtpowergood),
      .xcvr_ref_clk(qsfp1_mgt_refclk_0),

      /*
     * DRP
     */
      .drp_clk (qsfp1_drp_clk),
      .drp_rst (qsfp1_drp_rst),
      .drp_addr(qsfp1_drp_addr),
      .drp_di  (qsfp1_drp_di),
      .drp_en  (qsfp1_drp_en),
      .drp_we  (qsfp1_drp_we),
      .drp_do  (qsfp1_drp_do),
      .drp_rdy (qsfp1_drp_rdy),

      /*
     * Serial data
     */
      .xcvr_txp(qsfp1_tx_p),
      .xcvr_txn(qsfp1_tx_n),
      .xcvr_rxp(qsfp1_rx_p),
      .xcvr_rxn(qsfp1_rx_n),

      /*
     * CMAC connections
     */
      .tx_clk(qsfp1_tx_clk_int),
      .tx_rst(qsfp1_tx_rst_int),

      .tx_axis_tdata (qsfp1_tx_axis_tdata_int),
      .tx_axis_tkeep (qsfp1_tx_axis_tkeep_int),
      .tx_axis_tvalid(qsfp1_tx_axis_tvalid_int),
      .tx_axis_tready(qsfp1_tx_axis_tready_int),
      .tx_axis_tlast (qsfp1_tx_axis_tlast_int),
      .tx_axis_tuser (qsfp1_tx_axis_tuser_int),

      .tx_enable (qsfp1_tx_enable),
      .tx_lfc_en (qsfp1_tx_lfc_en),
      .tx_lfc_req(qsfp1_tx_lfc_req),
      .tx_pfc_en (qsfp1_tx_pfc_en),
      .tx_pfc_req(qsfp1_tx_pfc_req),

      .rx_clk(qsfp1_rx_clk_int),
      .rx_rst(qsfp1_rx_rst_int),

      .rx_axis_tdata (qsfp1_rx_axis_tdata_int),
      .rx_axis_tkeep (qsfp1_rx_axis_tkeep_int),
      .rx_axis_tvalid(qsfp1_rx_axis_tvalid_int),
      .rx_axis_tlast (qsfp1_rx_axis_tlast_int),
      .rx_axis_tuser (qsfp1_rx_axis_tuser_int),


      .rx_enable (qsfp1_rx_enable),
      .rx_status (qsfp1_rx_status),
      .rx_lfc_en (qsfp1_rx_lfc_en),
      .rx_lfc_req(qsfp1_rx_lfc_req),
      .rx_lfc_ack(qsfp1_rx_lfc_ack),
      .rx_pfc_en (qsfp1_rx_pfc_en),
      .rx_pfc_req(qsfp1_rx_pfc_req),
      .rx_pfc_ack(qsfp1_rx_pfc_ack)
  );

  // QSFP2 CMAC
  
  assign qsfp2_modsell = 1'b0;
  assign qsfp2_resetl  = 1'b1;
  assign qsfp2_lpmode  = 1'b0;

  
  wire                                         qsfp2_tx_clk_int;
  wire                                         qsfp2_tx_rst_int;

  wire                                 [511:0] qsfp2_tx_axis_tdata_int;
  wire                                 [ 63:0] qsfp2_tx_axis_tkeep_int;
  wire                                         qsfp2_tx_axis_tvalid_int;
  wire                                         qsfp2_tx_axis_tready_int;
  wire                                         qsfp2_tx_axis_tlast_int;
  wire                                         qsfp2_tx_axis_tuser_int;

  wire                                         qsfp2_rx_clk_int;
  wire                                         qsfp2_rx_rst_int;

  wire                                 [511:0] qsfp2_rx_axis_tdata_int;
  wire                                 [ 63:0] qsfp2_rx_axis_tkeep_int;
  wire                                         qsfp2_rx_axis_tvalid_int;
  wire                                         qsfp2_rx_axis_tlast_int;
  wire                                         qsfp2_rx_axis_tuser_int;

  wire qsfp2_drp_clk = clk_125mhz_int;
  wire qsfp2_drp_rst = rst_125mhz_int;
  wire                                 [ 23:0] qsfp2_drp_addr;
  wire                                 [ 15:0] qsfp2_drp_di;
  wire                                         qsfp2_drp_en;
  wire                                         qsfp2_drp_we;
  wire                                 [ 15:0] qsfp2_drp_do;
  wire                                         qsfp2_drp_rdy;

  wire                                         qsfp2_tx_enable;
  wire                                         qsfp2_tx_lfc_en  = 1'b1;
  wire                                         qsfp2_tx_lfc_req = 1'b0;
  wire                                 [  7:0] qsfp2_tx_pfc_en  = 8'hFF;
  wire                                 [  7:0] qsfp2_tx_pfc_req = 8'h00;

  wire                                         qsfp2_rx_enable;
  wire                                         qsfp2_rx_status;
  wire                                         qsfp2_rx_lfc_en  = 1'b1;
  wire                                         qsfp2_rx_lfc_req;
  wire                                         qsfp2_rx_lfc_ack;
  wire                                 [  7:0] qsfp2_rx_pfc_en  = 8'hFF;
  wire                                 [  7:0] qsfp2_rx_pfc_req;
  wire                                 [  7:0] qsfp2_rx_pfc_ack = 8'h00; // define queues with axis ID bus??

  cmac_gty_wrapper #(
      .DRP_CLK_FREQ_HZ(125000000),
      .AXIS_DATA_WIDTH(512),
      .AXIS_KEEP_WIDTH(64),
      .TX_SERDES_PIPELINE(0),
      .RX_SERDES_PIPELINE(0),
      .RS_FEC_ENABLE(1)
  ) qsfp2_cmac_inst (
      .xcvr_ctrl_clk(clk_125mhz_int),
      .xcvr_ctrl_rst(qsfp1_rst),

      /*
     * Common
     */
      .xcvr_gtpowergood_out(),
      .xcvr_ref_clk(qsfp1_mgt_refclk_0),

      /*
     * DRP
     */
      .drp_clk (qsfp2_drp_clk),
      .drp_rst (qsfp2_drp_rst),
      .drp_addr(qsfp2_drp_addr),
      .drp_di  (qsfp2_drp_di),
      .drp_en  (qsfp2_drp_en),
      .drp_we  (qsfp2_drp_we),
      .drp_do  (qsfp2_drp_do),
      .drp_rdy (qsfp2_drp_rdy),

      /*
     * Serial data
     */
      .xcvr_txp(qsfp2_tx_p),
      .xcvr_txn(qsfp2_tx_n),
      .xcvr_rxp(qsfp2_rx_p),
      .xcvr_rxn(qsfp2_rx_n),

      /*
     * CMAC connections
     */
      .tx_clk(qsfp2_tx_clk_int),
      .tx_rst(qsfp2_tx_rst_int),

      .tx_axis_tdata (qsfp2_tx_axis_tdata_int),
      .tx_axis_tkeep (qsfp2_tx_axis_tkeep_int),
      .tx_axis_tvalid(qsfp2_tx_axis_tvalid_int),
      .tx_axis_tready(qsfp2_tx_axis_tready_int),
      .tx_axis_tlast (qsfp2_tx_axis_tlast_int),
      .tx_axis_tuser (qsfp2_tx_axis_tuser_int),

      .tx_enable (qsfp2_tx_enable),
      .tx_lfc_en (qsfp2_tx_lfc_en),
      .tx_lfc_req(qsfp2_tx_lfc_req),
      .tx_pfc_en (qsfp2_tx_pfc_en),
      .tx_pfc_req(qsfp2_tx_pfc_req),

      .rx_clk(qsfp2_rx_clk_int),
      .rx_rst(qsfp2_rx_rst_int),

      .rx_axis_tdata (qsfp2_rx_axis_tdata_int),
      .rx_axis_tkeep (qsfp2_rx_axis_tkeep_int),
      .rx_axis_tvalid(qsfp2_rx_axis_tvalid_int),
      .rx_axis_tlast (qsfp2_rx_axis_tlast_int),
      .rx_axis_tuser (qsfp2_rx_axis_tuser_int),

      .rx_enable (qsfp2_rx_enable),
      .rx_status (qsfp2_rx_status),
      .rx_lfc_en (qsfp2_rx_lfc_en),
      .rx_lfc_req(qsfp2_rx_lfc_req),
      .rx_lfc_ack(qsfp2_rx_lfc_ack),
      .rx_pfc_en (qsfp2_rx_pfc_en),
      .rx_pfc_req(qsfp2_rx_pfc_req),
      .rx_pfc_ack(qsfp2_rx_pfc_ack)
  );
 
 /*
 ila_axis ila_eth_rx(
    .clk(qsfp1_rx_clk_int),
    .probe0(qsfp1_rx_axis_tdata_int),
    .probe1(qsfp1_rx_axis_tkeep_int),
    .probe2(qsfp1_rx_axis_tvalid_int),
    .probe3(qsfp1_rx_axis_tvalid_int),
    .probe4(qsfp1_rx_axis_tlast_int),
    .probe5(qsfp1_rx_axis_tuser_int)
);

ila_axis ila_eth_tx(
    .clk(qsfp1_tx_clk_int),
    .probe0(qsfp1_tx_axis_tdata_int),
    .probe1(qsfp1_tx_axis_tkeep_int),
    .probe2(qsfp1_tx_axis_tvalid_int),
    .probe3(qsfp1_tx_axis_tready_int),
    .probe4(qsfp1_tx_axis_tlast_int),
    .probe5(qsfp1_tx_axis_tuser_int)
);
*/

  wire [7:0] led_int;
  /*
  assign led[0] = sw[0] ? qsfp1_rx_block_lock_1 : led_int[0];
  assign led[1] = sw[0] ? qsfp1_rx_block_lock_2 : led_int[1];
  assign led[2] = sw[0] ? qsfp1_rx_block_lock_3 : led_int[2];
  assign led[3] = sw[0] ? qsfp1_rx_block_lock_4 : led_int[3];
  assign led[4] = sw[0] ? qsfp2_rx_block_lock_1 : led_int[4];
  assign led[5] = sw[0] ? qsfp2_rx_block_lock_2 : led_int[5];
  assign led[6] = sw[0] ? qsfp2_rx_block_lock_3 : led_int[6];
  assign led[7] = sw[0] ? qsfp2_rx_block_lock_4 : led_int[7];
  */
  axis_async_fifo #(
      .DEPTH(4200),
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(64),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(1'b1),
      .USER_BAD_FRAME_VALUE(1'b1),
      .USER_BAD_FRAME_MASK(1'b1),
      .PAUSE_ENABLE(1),
      .FRAME_PAUSE(1)
  ) tx_fifo_stack2cmac (
      // AXI input
      .s_clk              (clk_net_int),
      .s_rst              (rst_net_int),
      .s_axis_tdata       (qsfp1_fifo_tx_axis_tdata_int),
      .s_axis_tkeep       (qsfp1_fifo_tx_axis_tkeep_int),
      .s_axis_tvalid      (qsfp1_fifo_tx_axis_tvalid_int),
      .s_axis_tready      (qsfp1_fifo_tx_axis_tready_int),
      .s_axis_tlast       (qsfp1_fifo_tx_axis_tlast_int),
      .s_axis_tid         (0),
      .s_axis_tdest       (0),
      .s_axis_tuser       (qsfp1_tx_axis_tuser_int),
      // AXI output
      .m_clk              (qsfp1_tx_clk_int),
      .m_rst              (qsfp1_tx_rst_int),
      .m_axis_tdata       (qsfp1_tx_axis_tdata_int),
      .m_axis_tkeep       (qsfp1_tx_axis_tkeep_int),
      .m_axis_tvalid      (qsfp1_tx_axis_tvalid_int),
      .m_axis_tready      (qsfp1_tx_axis_tready_int),
      .m_axis_tlast       (qsfp1_tx_axis_tlast_int),
      .m_axis_tid         (),
      .m_axis_tdest       (),
      .m_axis_tuser       (qsfp1_tx_axis_tuser_int),
      // Pause
      .s_pause_req(1'b0),
      .s_pause_ack(),
      .m_pause_req(qsfp1_rx_pfc_req[0]),
      .m_pause_ack(qsfp1_rx_pfc_ack[0]),
      // Status
      .s_status_overflow  (),
      .s_status_bad_frame (),
      .s_status_good_frame(),
      .m_status_overflow  (),
      .m_status_bad_frame (),
      .m_status_good_frame()
  );


  axis_async_fifo #(
      .DEPTH(4200),
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(64),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .FRAME_FIFO(1'b1),
      .USER_BAD_FRAME_VALUE(1'b1),
      .USER_BAD_FRAME_MASK(1'b1)
  ) rx_fifo_cmac2stack (
      // AXI input
      .s_clk              (qsfp1_rx_clk_int),
      .s_rst              (qsfp1_rx_rst_int),
      .s_axis_tdata       (qsfp1_rx_axis_tdata_int),
      .s_axis_tkeep       (qsfp1_rx_axis_tkeep_int),
      .s_axis_tvalid      (qsfp1_rx_axis_tvalid_int),
      .s_axis_tready      (),
      .s_axis_tlast       (qsfp1_rx_axis_tlast_int),
      .s_axis_tid         (0),
      .s_axis_tdest       (0),
      .s_axis_tuser       (qsfp1_rx_axis_tuser_int),
      // AXI output
      .m_clk              (clk_net_int),
      .m_rst              (rst_net_int),
      .m_axis_tdata       (qsfp1_fifo_rx_axis_tdata_int),
      .m_axis_tkeep       (qsfp1_fifo_rx_axis_tkeep_int),
      .m_axis_tvalid      (qsfp1_fifo_rx_axis_tvalid_int),
      .m_axis_tready      (1'b1),
      .m_axis_tlast       (qsfp1_fifo_rx_axis_tlast_int),
      .m_axis_tid         (),
      .m_axis_tdest       (),
      .m_axis_tuser       (qsfp1_fifo_rx_axis_tuser_int),
      // Status
      .s_status_overflow  (),
      .s_status_bad_frame (),
      .s_status_good_frame(),
      .m_status_overflow  (),
      .m_status_bad_frame (),
      .m_status_good_frame()
  );

  fpga_core core_inst (
      /*
     * Clock: 322.625 MHz
     * Synchronous reset
     */
      .clk                 (clk_net_int),
      .rst                 (rst_net_int),
      /*
     * GPIO
     */
      .btnu                (btnu_int),
      .btnl                (btnl_int),
      .btnd                (btnd_int),
      .btnr                (btnr_int),
      .btnc                (btnc_int),
      .sw                  (sw_int),
      .led                 (led_int),
      /*
     * Ethernet: QSFP28
     */
      .qsfp1_tx_axis_tdata (qsfp1_fifo_tx_axis_tdata_int),
      .qsfp1_tx_axis_tkeep (qsfp1_fifo_tx_axis_tkeep_int),
      .qsfp1_tx_axis_tvalid(qsfp1_fifo_tx_axis_tvalid_int),
      .qsfp1_tx_axis_tready(qsfp1_fifo_tx_axis_tready_int),
      .qsfp1_tx_axis_tlast (qsfp1_fifo_tx_axis_tlast_int),
      .qsfp1_tx_axis_tuser (qsfp1_fifo_tx_axis_tuser_int),

      .qsfp1_tx_enable (qsfp1_tx_enable),

      .qsfp1_rx_axis_tdata (qsfp1_fifo_rx_axis_tdata_int),
      .qsfp1_rx_axis_tkeep (qsfp1_fifo_rx_axis_tkeep_int),
      .qsfp1_rx_axis_tvalid(qsfp1_fifo_rx_axis_tvalid_int),
      .qsfp1_rx_axis_tlast (qsfp1_fifo_rx_axis_tlast_int),
      .qsfp1_rx_axis_tuser (qsfp1_fifo_rx_axis_tuser_int),

      .qsfp1_rx_enable (qsfp1_rx_enable),
      .qsfp1_rx_status (qsfp1_rx_status),

      .qsfp1_drp_clk (qsfp1_drp_clk),
      .qsfp1_drp_rst (qsfp1_drp_rst),
      .qsfp1_drp_addr(qsfp1_drp_addr),
      .qsfp1_drp_di  (qsfp1_drp_di),
      .qsfp1_drp_en  (qsfp1_drp_en),
      .qsfp1_drp_we  (qsfp1_drp_we),
      .qsfp1_drp_do  (qsfp1_drp_do),
      .qsfp1_drp_rdy (qsfp1_drp_rdy),

      .qsfp2_tx_axis_tdata  (qsfp2_tx_axis_tdata_int),
      .qsfp2_tx_axis_tkeep  (qsfp2_tx_axis_tkeep_int),
      .qsfp2_tx_axis_tvalid (qsfp2_tx_axis_tvalid_int),
      .qsfp2_tx_axis_tready (qsfp2_tx_axis_tready_int),
      .qsfp2_tx_axis_tlast  (qsfp2_tx_axis_tlast_int),
      .qsfp2_tx_axis_tuser  (qsfp2_tx_axis_tuser_int),

      .qsfp2_tx_enable (qsfp2_tx_enable),

      .qsfp2_rx_axis_tdata (qsfp2_rx_axis_tdata_int),
      .qsfp2_rx_axis_tkeep (qsfp2_rx_axis_tkeep_int),
      .qsfp2_rx_axis_tvalid(qsfp2_rx_axis_tvalid_int),
      .qsfp2_rx_axis_tlast (qsfp2_rx_axis_tlast_int),
      .qsfp2_rx_axis_tuser (qsfp2_rx_axis_tuser_int),

      .qsfp2_rx_enable (qsfp2_rx_enable),
      .qsfp2_rx_status (qsfp2_rx_status),

      .qsfp2_drp_clk (qsfp2_drp_clk),
      .qsfp2_drp_rst (qsfp2_drp_rst),
      .qsfp2_drp_addr(qsfp2_drp_addr),
      .qsfp2_drp_di  (qsfp2_drp_di),
      .qsfp2_drp_en  (qsfp2_drp_en),
      .qsfp2_drp_we  (qsfp2_drp_we),
      .qsfp2_drp_do  (qsfp2_drp_do),
      .qsfp2_drp_rdy (qsfp2_drp_rdy)
  );

endmodule

`resetall

