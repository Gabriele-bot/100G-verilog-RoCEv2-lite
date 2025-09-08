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

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module
 */
module fpga (
    /*
     * Clock: 125MHz LVDS
     * Reset: Push button, active low
     */
    input  wire       clk_125mhz_p,
    input  wire       clk_125mhz_n,
    input  wire       reset,

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
    inout  wire       i2c_scl,
    inout  wire       i2c_sda,

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
    input  wire       qsfp2_mgt_refclk_0_p,
    input  wire       qsfp2_mgt_refclk_0_n,
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

// Internal 390.625 MHz clock
wire [7:0] clk_390mhz_int;
wire [7:0] rst_390mhz_int;

wire mmcm_rst;
wire mmcm_locked;
wire mmcm_clkfb;

wire ext_rst;

vio_ext_rst vio_ext_rst_inst (
    .clk(clk_125mhz_ibufg),
    .probe_out0(ext_rst)
  );

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")   
)
clk_125mhz_ibufg_inst (
   .O   (clk_125mhz_ibufg),
   .I   (clk_125mhz_p),
   .IB  (clk_125mhz_n) 
);

assign mmcm_rst = reset | ext_rst;

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
)
clk_mmcm_inst (
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

BUFG
clk_125mhz_bufg_inst (
    .I(clk_125mhz_mmcm_out),
    .O(clk_125mhz_int)
);

sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
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
)
debounce_switch_inst (
    .clk(clk_390mhz_int[0]),
    .rst(rst_390mhz_int[0]),
    .in({btnu,
        btnl,
        btnd,
        btnr,
        btnc,
        sw}),
    .out({btnu_int,
        btnl_int,
        btnd_int,
        btnr_int,
        btnc_int,
        sw_int})
);



// SI570 I2C
wire i2c_scl_i;
wire i2c_scl_o = 1'b1;
wire i2c_scl_t = 1'b1;
wire i2c_sda_i;
wire i2c_sda_o = 1'b1;
wire i2c_sda_t = 1'b1;

assign i2c_scl_i = i2c_scl;
assign i2c_scl = i2c_scl_t ? 1'bz : i2c_scl_o;
assign i2c_sda_i = i2c_sda;
assign i2c_sda = i2c_sda_t ? 1'bz : i2c_sda_o;

// XGMII 10G PHY

// QSFP1
assign qsfp1_modsell = 1'b0;
assign qsfp1_resetl = 1'b1;
assign qsfp1_lpmode = 1'b0;

wire        qsfp1_tx_clk_1_int;
wire        qsfp1_tx_rst_1_int;
wire [63:0] qsfp1_txd_1_int;
wire [7:0]  qsfp1_txc_1_int;
wire        qsfp1_rx_clk_1_int;
wire        qsfp1_rx_rst_1_int;
wire [63:0] qsfp1_rxd_1_int;
wire [7:0]  qsfp1_rxc_1_int;
wire        qsfp1_tx_clk_2_int;
wire        qsfp1_tx_rst_2_int;
wire [63:0] qsfp1_txd_2_int;
wire [7:0]  qsfp1_txc_2_int;
wire        qsfp1_rx_clk_2_int;
wire        qsfp1_rx_rst_2_int;
wire [63:0] qsfp1_rxd_2_int;
wire [7:0]  qsfp1_rxc_2_int;
wire        qsfp1_tx_clk_3_int;
wire        qsfp1_tx_rst_3_int;
wire [63:0] qsfp1_txd_3_int;
wire [7:0]  qsfp1_txc_3_int;
wire        qsfp1_rx_clk_3_int;
wire        qsfp1_rx_rst_3_int;
wire [63:0] qsfp1_rxd_3_int;
wire [7:0]  qsfp1_rxc_3_int;
wire        qsfp1_tx_clk_4_int;
wire        qsfp1_tx_rst_4_int;
wire [63:0] qsfp1_txd_4_int;
wire [7:0]  qsfp1_txc_4_int;
wire        qsfp1_rx_clk_4_int;
wire        qsfp1_rx_rst_4_int;
wire [63:0] qsfp1_rxd_4_int;
wire [7:0]  qsfp1_rxc_4_int;

assign clk_390mhz_int[0] = qsfp1_tx_clk_1_int;
assign rst_390mhz_int[0] = qsfp1_tx_rst_1_int;
assign clk_390mhz_int[1] = qsfp1_tx_clk_2_int;
assign rst_390mhz_int[1] = qsfp1_tx_rst_2_int;
assign clk_390mhz_int[2] = qsfp1_tx_clk_3_int;
assign rst_390mhz_int[2] = qsfp1_tx_rst_3_int;
assign clk_390mhz_int[3] = qsfp1_tx_clk_4_int;
assign rst_390mhz_int[3] = qsfp1_tx_rst_4_int;
assign clk_390mhz_int[4] = qsfp2_tx_clk_1_int;
assign rst_390mhz_int[4] = qsfp2_tx_rst_1_int;
assign clk_390mhz_int[5] = qsfp2_tx_clk_2_int;
assign rst_390mhz_int[5] = qsfp2_tx_rst_2_int;
assign clk_390mhz_int[6] = qsfp2_tx_clk_3_int;
assign rst_390mhz_int[6] = qsfp2_tx_rst_3_int;
assign clk_390mhz_int[7] = qsfp2_tx_clk_4_int;
assign rst_390mhz_int[7] = qsfp2_tx_rst_4_int;

wire qsfp1_rx_block_lock_1;
wire qsfp1_rx_block_lock_2;
wire qsfp1_rx_block_lock_3;
wire qsfp1_rx_block_lock_4;

wire qsfp1_mgt_refclk;

wire qsfp2_mgt_refclk;

IBUFDS_GTE4 ibufds_gte4_qsfp1_mgt_refclk_0_inst (
    .I     (qsfp1_mgt_refclk_0_p),
    .IB    (qsfp1_mgt_refclk_0_n),
    .CEB   (1'b0),
    .O     (qsfp1_mgt_refclk),
    .ODIV2 ()
);

IBUFDS_GTE4 ibufds_gte4_qsfp2_mgt_refclk_0_inst (
    .I     (qsfp2_mgt_refclk_0_p),
    .IB    (qsfp2_mgt_refclk_0_n),
    .CEB   (1'b0),
    .O     (qsfp2_mgt_refclk),
    .ODIV2 ()
);

eth_xcvr_phy_quad_wrapper#(
    //.TX_SERDES_PIPELINE(2),
    //.RX_SERDES_PIPELINE(2)
) qsfp1_phy_inst (
    .xcvr_ctrl_clk(clk_125mhz_int),
    .xcvr_ctrl_rst(rst_125mhz_int),

    /*
     * Common
     */
    .xcvr_gtpowergood_out(),

    /*
     * PLL
     */
    .xcvr_gtrefclk00_in(qsfp1_mgt_refclk),

    /*
     * Serial data
     */
    .xcvr_txp(qsfp1_tx_p),
    .xcvr_txn(qsfp1_tx_n),
    .xcvr_rxp(qsfp1_rx_p),
    .xcvr_rxn(qsfp1_rx_n),

    /*
     * PHY connections
     */
    .phy_1_tx_clk(qsfp1_tx_clk_1_int),
    .phy_1_tx_rst(qsfp1_tx_rst_1_int),
    .phy_1_xgmii_txd(qsfp1_txd_1_int),
    .phy_1_xgmii_txc(qsfp1_txc_1_int),
    .phy_1_rx_clk(qsfp1_rx_clk_1_int),
    .phy_1_rx_rst(qsfp1_rx_rst_1_int),
    .phy_1_xgmii_rxd(qsfp1_rxd_1_int),
    .phy_1_xgmii_rxc(qsfp1_rxc_1_int),
    .phy_1_tx_bad_block(),
    .phy_1_rx_error_count(),
    .phy_1_rx_bad_block(),
    .phy_1_rx_sequence_error(),
    .phy_1_rx_block_lock(qsfp1_rx_block_lock_1),
    .phy_1_rx_status(),
    .phy_1_cfg_tx_prbs31_enable(1'b0),
    .phy_1_cfg_rx_prbs31_enable(1'b0),

    .phy_2_tx_clk(qsfp1_tx_clk_2_int),
    .phy_2_tx_rst(qsfp1_tx_rst_2_int),
    .phy_2_xgmii_txd(qsfp1_txd_2_int),
    .phy_2_xgmii_txc(qsfp1_txc_2_int),
    .phy_2_rx_clk(qsfp1_rx_clk_2_int),
    .phy_2_rx_rst(qsfp1_rx_rst_2_int),
    .phy_2_xgmii_rxd(qsfp1_rxd_2_int),
    .phy_2_xgmii_rxc(qsfp1_rxc_2_int),
    .phy_2_tx_bad_block(),
    .phy_2_rx_error_count(),
    .phy_2_rx_bad_block(),
    .phy_2_rx_sequence_error(),
    .phy_2_rx_block_lock(qsfp1_rx_block_lock_2),
    .phy_2_rx_status(),
    .phy_2_cfg_tx_prbs31_enable(1'b0),
    .phy_2_cfg_rx_prbs31_enable(1'b0),

    .phy_3_tx_clk(qsfp1_tx_clk_3_int),
    .phy_3_tx_rst(qsfp1_tx_rst_3_int),
    .phy_3_xgmii_txd(qsfp1_txd_3_int),
    .phy_3_xgmii_txc(qsfp1_txc_3_int),
    .phy_3_rx_clk(qsfp1_rx_clk_3_int),
    .phy_3_rx_rst(qsfp1_rx_rst_3_int),
    .phy_3_xgmii_rxd(qsfp1_rxd_3_int),
    .phy_3_xgmii_rxc(qsfp1_rxc_3_int),
    .phy_3_tx_bad_block(),
    .phy_3_rx_error_count(),
    .phy_3_rx_bad_block(),
    .phy_3_rx_sequence_error(),
    .phy_3_rx_block_lock(qsfp1_rx_block_lock_3),
    .phy_3_rx_status(),
    .phy_3_cfg_tx_prbs31_enable(1'b0),
    .phy_3_cfg_rx_prbs31_enable(1'b0),

    .phy_4_tx_clk(qsfp1_tx_clk_4_int),
    .phy_4_tx_rst(qsfp1_tx_rst_4_int),
    .phy_4_xgmii_txd(qsfp1_txd_4_int),
    .phy_4_xgmii_txc(qsfp1_txc_4_int),
    .phy_4_rx_clk(qsfp1_rx_clk_4_int),
    .phy_4_rx_rst(qsfp1_rx_rst_4_int),
    .phy_4_xgmii_rxd(qsfp1_rxd_4_int),
    .phy_4_xgmii_rxc(qsfp1_rxc_4_int),
    .phy_4_tx_bad_block(),
    .phy_4_rx_error_count(),
    .phy_4_rx_bad_block(),
    .phy_4_rx_sequence_error(),
    .phy_4_rx_block_lock(qsfp1_rx_block_lock_4),
    .phy_4_rx_status(),
    .phy_4_cfg_tx_prbs31_enable(1'b0),
    .phy_4_cfg_rx_prbs31_enable(1'b0)
);

// QSFP2
assign qsfp2_modsell = 1'b0;
assign qsfp2_resetl = 1'b1;
assign qsfp2_lpmode = 1'b0;

wire        qsfp2_tx_clk_1_int;
wire        qsfp2_tx_rst_1_int;
wire [63:0] qsfp2_txd_1_int;
wire [7:0]  qsfp2_txc_1_int;
wire        qsfp2_rx_clk_1_int;
wire        qsfp2_rx_rst_1_int;
wire [63:0] qsfp2_rxd_1_int;
wire [7:0]  qsfp2_rxc_1_int;
wire        qsfp2_tx_clk_2_int;
wire        qsfp2_tx_rst_2_int;
wire [63:0] qsfp2_txd_2_int;
wire [7:0]  qsfp2_txc_2_int;
wire        qsfp2_rx_clk_2_int;
wire        qsfp2_rx_rst_2_int;
wire [63:0] qsfp2_rxd_2_int;
wire [7:0]  qsfp2_rxc_2_int;
wire        qsfp2_tx_clk_3_int;
wire        qsfp2_tx_rst_3_int;
wire [63:0] qsfp2_txd_3_int;
wire [7:0]  qsfp2_txc_3_int;
wire        qsfp2_rx_clk_3_int;
wire        qsfp2_rx_rst_3_int;
wire [63:0] qsfp2_rxd_3_int;
wire [7:0]  qsfp2_rxc_3_int;
wire        qsfp2_tx_clk_4_int;
wire        qsfp2_tx_rst_4_int;
wire [63:0] qsfp2_txd_4_int;
wire [7:0]  qsfp2_txc_4_int;
wire        qsfp2_rx_clk_4_int;
wire        qsfp2_rx_rst_4_int;
wire [63:0] qsfp2_rxd_4_int;
wire [7:0]  qsfp2_rxc_4_int;

wire qsfp2_rx_block_lock_1;
wire qsfp2_rx_block_lock_2;
wire qsfp2_rx_block_lock_3;
wire qsfp2_rx_block_lock_4;

eth_xcvr_phy_quad_wrapper #(
    //.TX_SERDES_PIPELINE(2),
    //.RX_SERDES_PIPELINE(2)
) qsfp2_phy_inst (
    .xcvr_ctrl_clk(clk_125mhz_int),
    .xcvr_ctrl_rst(rst_125mhz_int),

    /*
     * Common
     */
    .xcvr_gtpowergood_out(),

    /*
     * PLL
     */
    .xcvr_gtrefclk00_in(qsfp2_mgt_refclk),

    /*
     * Serial data
     */
    .xcvr_txp(qsfp2_tx_p),
    .xcvr_txn(qsfp2_tx_n),
    .xcvr_rxp(qsfp2_rx_p),
    .xcvr_rxn(qsfp2_rx_n),

    /*
     * PHY connections
     */
    .phy_1_tx_clk(qsfp2_tx_clk_1_int),
    .phy_1_tx_rst(qsfp2_tx_rst_1_int),
    .phy_1_xgmii_txd(qsfp2_txd_1_int),
    .phy_1_xgmii_txc(qsfp2_txc_1_int),
    .phy_1_rx_clk(qsfp2_rx_clk_1_int),
    .phy_1_rx_rst(qsfp2_rx_rst_1_int),
    .phy_1_xgmii_rxd(qsfp2_rxd_1_int),
    .phy_1_xgmii_rxc(qsfp2_rxc_1_int),
    .phy_1_tx_bad_block(),
    .phy_1_rx_error_count(),
    .phy_1_rx_bad_block(),
    .phy_1_rx_sequence_error(),
    .phy_1_rx_block_lock(qsfp2_rx_block_lock_1),
    .phy_1_rx_status(),
    .phy_1_cfg_tx_prbs31_enable(1'b0),
    .phy_1_cfg_rx_prbs31_enable(1'b0),

    .phy_2_tx_clk(qsfp2_tx_clk_2_int),
    .phy_2_tx_rst(qsfp2_tx_rst_2_int),
    .phy_2_xgmii_txd(qsfp2_txd_2_int),
    .phy_2_xgmii_txc(qsfp2_txc_2_int),
    .phy_2_rx_clk(qsfp2_rx_clk_2_int),
    .phy_2_rx_rst(qsfp2_rx_rst_2_int),
    .phy_2_xgmii_rxd(qsfp2_rxd_2_int),
    .phy_2_xgmii_rxc(qsfp2_rxc_2_int),
    .phy_2_tx_bad_block(),
    .phy_2_rx_error_count(),
    .phy_2_rx_bad_block(),
    .phy_2_rx_sequence_error(),
    .phy_2_rx_block_lock(qsfp2_rx_block_lock_2),
    .phy_2_rx_status(),
    .phy_2_cfg_tx_prbs31_enable(1'b0),
    .phy_2_cfg_rx_prbs31_enable(1'b0),

    .phy_3_tx_clk(qsfp2_tx_clk_3_int),
    .phy_3_tx_rst(qsfp2_tx_rst_3_int),
    .phy_3_xgmii_txd(qsfp2_txd_3_int),
    .phy_3_xgmii_txc(qsfp2_txc_3_int),
    .phy_3_rx_clk(qsfp2_rx_clk_3_int),
    .phy_3_rx_rst(qsfp2_rx_rst_3_int),
    .phy_3_xgmii_rxd(qsfp2_rxd_3_int),
    .phy_3_xgmii_rxc(qsfp2_rxc_3_int),
    .phy_3_tx_bad_block(),
    .phy_3_rx_error_count(),
    .phy_3_rx_bad_block(),
    .phy_3_rx_sequence_error(),
    .phy_3_rx_block_lock(qsfp2_rx_block_lock_3),
    .phy_3_rx_status(),
    .phy_3_cfg_tx_prbs31_enable(1'b0),
    .phy_3_cfg_rx_prbs31_enable(1'b0),

    .phy_4_tx_clk(qsfp2_tx_clk_4_int),
    .phy_4_tx_rst(qsfp2_tx_rst_4_int),
    .phy_4_xgmii_txd(qsfp2_txd_4_int),
    .phy_4_xgmii_txc(qsfp2_txc_4_int),
    .phy_4_rx_clk(qsfp2_rx_clk_4_int),
    .phy_4_rx_rst(qsfp2_rx_rst_4_int),
    .phy_4_xgmii_rxd(qsfp2_rxd_4_int),
    .phy_4_xgmii_rxc(qsfp2_rxc_4_int),
    .phy_4_tx_bad_block(),
    .phy_4_rx_error_count(),
    .phy_4_rx_bad_block(),
    .phy_4_rx_sequence_error(),
    .phy_4_rx_block_lock(qsfp2_rx_block_lock_4),
    .phy_4_rx_status(),
    .phy_4_cfg_tx_prbs31_enable(1'b0),
    .phy_4_cfg_rx_prbs31_enable(1'b0)
);


wire [7:0] led_int;

assign led[0] = sw[0] ? qsfp1_rx_block_lock_1 : led_int[0];
assign led[1] = sw[0] ? qsfp1_rx_block_lock_2 : led_int[1];
assign led[2] = sw[0] ? qsfp1_rx_block_lock_3 : led_int[2];
assign led[3] = sw[0] ? qsfp1_rx_block_lock_4 : led_int[3];
assign led[4] = sw[0] ? qsfp2_rx_block_lock_1 : led_int[4];
assign led[5] = sw[0] ? qsfp2_rx_block_lock_2 : led_int[5];
assign led[6] = sw[0] ? qsfp2_rx_block_lock_3 : led_int[6];
assign led[7] = sw[0] ? qsfp2_rx_block_lock_4 : led_int[7];

fpga_core #(
	ENABLE_QSFP1 = 1,
	ENABLE_QSFP1 = 0
) core_inst (
    /*
     * Clock: 390.625 MHz for 25G
     * Clock: 156.250 MHz for 10G
     * Synchronous reset
     */
    .clk(clk_390mhz_int),
    .rst(rst_390mhz_int),
    /*
     * GPIO
     */
    .btnu(btnu_int),
    .btnl(btnl_int),
    .btnd(btnd_int),
    .btnr(btnr_int),
    .btnc(btnc_int),
    .sw(sw_int),
    .led(led_int),
    /*
     * Ethernet: QSFP28
     */
    .qsfp1_tx_clk_1(qsfp1_tx_clk_1_int),
    .qsfp1_tx_rst_1(qsfp1_tx_rst_1_int),
    .qsfp1_txd_1(qsfp1_txd_1_int),
    .qsfp1_txc_1(qsfp1_txc_1_int),
    .qsfp1_rx_clk_1(qsfp1_rx_clk_1_int),
    .qsfp1_rx_rst_1(qsfp1_rx_rst_1_int),
    .qsfp1_rxd_1(qsfp1_rxd_1_int),
    .qsfp1_rxc_1(qsfp1_rxc_1_int),
    .qsfp1_tx_clk_2(qsfp1_tx_clk_2_int),
    .qsfp1_tx_rst_2(qsfp1_tx_rst_2_int),
    .qsfp1_txd_2(qsfp1_txd_2_int),
    .qsfp1_txc_2(qsfp1_txc_2_int),
    .qsfp1_rx_clk_2(qsfp1_rx_clk_2_int),
    .qsfp1_rx_rst_2(qsfp1_rx_rst_2_int),
    .qsfp1_rxd_2(qsfp1_rxd_2_int),
    .qsfp1_rxc_2(qsfp1_rxc_2_int),
    .qsfp1_tx_clk_3(qsfp1_tx_clk_3_int),
    .qsfp1_tx_rst_3(qsfp1_tx_rst_3_int),
    .qsfp1_txd_3(qsfp1_txd_3_int),
    .qsfp1_txc_3(qsfp1_txc_3_int),
    .qsfp1_rx_clk_3(qsfp1_rx_clk_3_int),
    .qsfp1_rx_rst_3(qsfp1_rx_rst_3_int),
    .qsfp1_rxd_3(qsfp1_rxd_3_int),
    .qsfp1_rxc_3(qsfp1_rxc_3_int),
    .qsfp1_tx_clk_4(qsfp1_tx_clk_4_int),
    .qsfp1_tx_rst_4(qsfp1_tx_rst_4_int),
    .qsfp1_txd_4(qsfp1_txd_4_int),
    .qsfp1_txc_4(qsfp1_txc_4_int),
    .qsfp1_rx_clk_4(qsfp1_rx_clk_4_int),
    .qsfp1_rx_rst_4(qsfp1_rx_rst_4_int),
    .qsfp1_rxd_4(qsfp1_rxd_4_int),
    .qsfp1_rxc_4(qsfp1_rxc_4_int),
    .qsfp2_tx_clk_1(qsfp2_tx_clk_1_int),
    .qsfp2_tx_rst_1(qsfp2_tx_rst_1_int),
    .qsfp2_txd_1(qsfp2_txd_1_int),
    .qsfp2_txc_1(qsfp2_txc_1_int),
    .qsfp2_rx_clk_1(qsfp2_rx_clk_1_int),
    .qsfp2_rx_rst_1(qsfp2_rx_rst_1_int),
    .qsfp2_rxd_1(qsfp2_rxd_1_int),
    .qsfp2_rxc_1(qsfp2_rxc_1_int),
    .qsfp2_tx_clk_2(qsfp2_tx_clk_2_int),
    .qsfp2_tx_rst_2(qsfp2_tx_rst_2_int),
    .qsfp2_txd_2(qsfp2_txd_2_int),
    .qsfp2_txc_2(qsfp2_txc_2_int),
    .qsfp2_rx_clk_2(qsfp2_rx_clk_2_int),
    .qsfp2_rx_rst_2(qsfp2_rx_rst_2_int),
    .qsfp2_rxd_2(qsfp2_rxd_2_int),
    .qsfp2_rxc_2(qsfp2_rxc_2_int),
    .qsfp2_tx_clk_3(qsfp2_tx_clk_3_int),
    .qsfp2_tx_rst_3(qsfp2_tx_rst_3_int),
    .qsfp2_txd_3(qsfp2_txd_3_int),
    .qsfp2_txc_3(qsfp2_txc_3_int),
    .qsfp2_rx_clk_3(qsfp2_rx_clk_3_int),
    .qsfp2_rx_rst_3(qsfp2_rx_rst_3_int),
    .qsfp2_rxd_3(qsfp2_rxd_3_int),
    .qsfp2_rxc_3(qsfp2_rxc_3_int),
    .qsfp2_tx_clk_4(qsfp2_tx_clk_4_int),
    .qsfp2_tx_rst_4(qsfp2_tx_rst_4_int),
    .qsfp2_txd_4(qsfp2_txd_4_int),
    .qsfp2_txc_4(qsfp2_txc_4_int),
    .qsfp2_rx_clk_4(qsfp2_rx_clk_4_int),
    .qsfp2_rx_rst_4(qsfp2_rx_rst_4_int),
    .qsfp2_rxd_4(qsfp2_rxd_4_int),
    .qsfp2_rxc_4(qsfp2_rxc_4_int)
);

endmodule

`resetall
