// ------------------------------------------------------------------------------
//   (c) Copyright 2020-2021 Advanced Micro Devices, Inc. All rights reserved.
// 
//   This file contains confidential and proprietary information
//   of Advanced Micro Devices, Inc. and is protected under U.S. and
//   international copyright and other intellectual property
//   laws.
// 
//   DISCLAIMER
//   This disclaimer is not a license and does not grant any
//   rights to the materials distributed herewith. Except as
//   otherwise provided in a valid license issued to you by
//   AMD, and to the maximum extent permitted by applicable
//   law: (1) THESE MATERIALS ARE MADE AVAILABLE \"AS IS\" AND
//   WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
//   AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//   BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//   INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//   (2) AMD shall not be liable (whether in contract or tort,
//   including negligence, or under any other theory of
//   liability) for any loss or damage of any kind or nature
//   related to, arising under or in connection with these
//   materials, including for any direct, or any indirect,
//   special, incidental, or consequential loss or damage
//   (including loss of data, profits, goodwill, or any type of
//   loss or damage suffered as a result of any action brought
//   by a third party) even if such damage or loss was
//   reasonably foreseeable or AMD had been advised of the
//   possibility of the same.
// 
//   CRITICAL APPLICATIONS
//   AMD products are not designed or intended to be fail-
//   safe, or for use in any application requiring fail-safe
//   performance, such as life-support or safety devices or
//   systems, Class III medical devices, nuclear facilities,
//   applications related to the deployment of airbags, or any
//   other applications that could lead to death, personal
//   injury, or severe property or environmental damage
//   (individually and collectively, \"Critical
//   Applications\"). Customer assumes the sole risk and
//   liability of any use of AMD products in Critical
//   Applications, subject only to applicable laws and
//   regulations governing limitations on product liability.
// 
//   THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//   PART OF THIS FILE AT ALL TIMES.
// ------------------------------------------------------------------------------
////------------------------------------------------------------------------------


`timescale 1ps/1ps

(* DowngradeIPIdentifiedWarnings="yes" *)
module dcmac_0_exdes
(
    input wire            s_axi_aclk,
    input wire            s_axi_aresetn,
    input wire [31 : 0]   s_axi_awaddr,
    input wire            s_axi_awvalid,
    output wire           s_axi_awready,
    input wire [31 : 0]   s_axi_wdata,
    input wire            s_axi_wvalid,
    output wire           s_axi_wready,
    output wire [1 : 0]   s_axi_bresp,
    output wire           s_axi_bvalid,
    input wire            s_axi_bready,
    input wire [31 : 0]   s_axi_araddr,
    input wire            s_axi_arvalid,
    output wire           s_axi_arready,
    output wire [31 : 0]  s_axi_rdata,
    output wire [1 : 0]   s_axi_rresp,
    output wire           s_axi_rvalid,
    input wire            s_axi_rready,
    input  wire [3:0] gt_rxn_in0,
    input  wire [3:0] gt_rxp_in0,
    output wire [3:0] gt_txn_out0,
    output wire [3:0] gt_txp_out0,
    input  wire [3:0] gt_rxn_in1,
    input  wire [3:0] gt_rxp_in1,
    output wire [3:0] gt_txn_out1,
    output wire [3:0] gt_txp_out1,
    input  wire       gt_reset_all_in,
    output wire [31:0] gt_gpo,
    output wire       gt_reset_done,
    input  wire [7:0] gt_line_rate,
    input  wire [2:0] gt_loopback,
    input  wire [5:0] gt_txprecursor,
    input  wire [5:0] gt_txpostcursor,
    input  wire [6:0] gt_txmaincursor,
    input  wire       gt_rxcdrhold,

    output logic [31:0]  APB_M2_prdata,
    output logic [0:0]   APB_M2_pready,
    output logic [0:0]   APB_M2_pslverr,
    output logic [31:0]  APB_M3_prdata,
    output logic [0:0]   APB_M3_pready,
    output logic [0:0]   APB_M3_pslverr,
    output logic [31:0]  APB_M4_prdata,
    output logic [0:0]   APB_M4_pready,
    output logic [0:0]   APB_M4_pslverr,

    input [31:0]      APB_M2_paddr,
    input             APB_M2_penable,
    input [0:0]       APB_M2_psel,
    input [31:0]      APB_M2_pwdata,
    input             APB_M2_pwrite,
    input [31:0]      APB_M3_paddr,
    input             APB_M3_penable,
    input [0:0]       APB_M3_psel,
    input [31:0]      APB_M3_pwdata,
    input             APB_M3_pwrite,
    input [31:0]      APB_M4_paddr,
    input             APB_M4_penable,
    input [0:0]       APB_M4_psel,
    input [31:0]      APB_M4_pwdata,
    input             APB_M4_pwrite,
    input  wire [5:0] tx_serdes_reset,
    input  wire [5:0] rx_serdes_reset,
    input  wire       tx_core_reset,
    input  wire       rx_core_reset,
    output wire [23:0] gt_tx_reset_done_out,
    output wire [23:0] gt_rx_reset_done_out,
    output wire        gt_tx_reset_core,
    output wire        gt_rx_reset_core,
    input  wire       gt_ref_clk0_p,
    input  wire       gt_ref_clk0_n,
    input  wire       gt_ref_clk1_p,
    input  wire       gt_ref_clk1_n,
    input  wire [8-1:0] gt_reset_tx_datapath_in,
    input  wire [8-1:0] gt_reset_rx_datapath_in,
    input  wire       init_clk
);

  //parameter DEVICE_NAME  = "VERSAL_PREMIUM_ES1";
  parameter COUNTER_MODE = 0;

  // For other GT loopback options, please program the value thru CIPS appropriately.
  // For GT Near-end PCS loopback, update the GT loopback value to 3'd1. Drive gt_loopback = 3'b001.
  // For GT External loopback, update the GT loopback value to 3'd0. Drive gt_loopback = 3'b000.
  // For more information & settings on loopback, refer versal GT Transceivers user guide.
  wire  [31:0]   SW_REG_GT_LINE_RATE;
  assign SW_REG_GT_LINE_RATE = {gt_line_rate,gt_line_rate,gt_line_rate,gt_line_rate};

  //wire           gt_rxcdrhold;
  //assign gt_rxcdrhold = (gt_loopback == 3'b001)? 1'b1 : 1'b0;
  ////////////
  wire           tx_core_clk;
  wire           rx_core_clk;
  wire [5:0]     rx_serdes_clk;
  wire [5:0]     tx_serdes_clk;
  wire [5:0]     rx_alt_serdes_clk;
  wire [5:0]     tx_alt_serdes_clk;
  wire           ts_clk;


  wire           gt0_tx_usrclk_0;
  wire           gt0_tx_usrclk2_0;
  wire           gt0_rx_usrclk2_0;
  wire           gt0_rx_usrclk_0;

  wire           gt0_tx_usrclk_1;
  wire           gt0_tx_usrclk2_1;
  wire           gt0_rx_usrclk2_1;
  wire           gt0_rx_usrclk_1;

  wire           gt0_tx_usrclk_2;
  wire           gt0_tx_usrclk2_2;
  wire           gt0_rx_usrclk2_2;
  wire           gt0_rx_usrclk_2;

  wire           gt0_tx_usrclk_3;
  wire           gt0_tx_usrclk2_3;
  wire           gt0_rx_usrclk2_3;
  wire           gt0_rx_usrclk_3;

  wire           gt1_tx_usrclk_0;
  wire           gt1_tx_usrclk2_0;
  wire           gt1_rx_usrclk2_0;
  wire           gt1_rx_usrclk_0;

  wire           gt1_tx_usrclk_1;
  wire           gt1_tx_usrclk2_1;
  wire           gt1_rx_usrclk2_1;
  wire           gt1_rx_usrclk_1;

  wire           gt1_tx_usrclk_2;
  wire           gt1_tx_usrclk2_2;
  wire           gt1_rx_usrclk2_2;
  wire           gt1_rx_usrclk_2;

  wire           gt1_tx_usrclk_3;
  wire           gt1_tx_usrclk2_3;
  wire           gt1_rx_usrclk2_3;
  wire           gt1_rx_usrclk_3;
  wire           gt_reset_tx_datapath_in_0;
  wire           gt_reset_rx_datapath_in_0;
  assign         gt_reset_tx_datapath_in_0 = gt_reset_tx_datapath_in[0];
  assign         gt_reset_rx_datapath_in_0 = gt_reset_rx_datapath_in[0];
  wire           gt_reset_tx_datapath_in_1;
  wire           gt_reset_rx_datapath_in_1;
  assign         gt_reset_tx_datapath_in_1 = gt_reset_tx_datapath_in[1];
  assign         gt_reset_rx_datapath_in_1 = gt_reset_rx_datapath_in[1];
  wire           gt_reset_tx_datapath_in_2;
  wire           gt_reset_rx_datapath_in_2;
  assign         gt_reset_tx_datapath_in_2 = gt_reset_tx_datapath_in[2];
  assign         gt_reset_rx_datapath_in_2 = gt_reset_rx_datapath_in[2];
  wire           gt_reset_tx_datapath_in_3;
  wire           gt_reset_rx_datapath_in_3;
  assign         gt_reset_tx_datapath_in_3 = gt_reset_tx_datapath_in[3];
  assign         gt_reset_rx_datapath_in_3 = gt_reset_rx_datapath_in[3];
  wire           gt_reset_tx_datapath_in_4;
  wire           gt_reset_rx_datapath_in_4;
  assign         gt_reset_tx_datapath_in_4 = gt_reset_tx_datapath_in[4];
  assign         gt_reset_rx_datapath_in_4 = gt_reset_rx_datapath_in[4];
  wire           gt_reset_tx_datapath_in_5;
  wire           gt_reset_rx_datapath_in_5;
  assign         gt_reset_tx_datapath_in_5 = gt_reset_tx_datapath_in[5];
  assign         gt_reset_rx_datapath_in_5 = gt_reset_rx_datapath_in[5];
  wire           gt_reset_tx_datapath_in_6;
  wire           gt_reset_rx_datapath_in_6;
  assign         gt_reset_tx_datapath_in_6 = gt_reset_tx_datapath_in[6];
  assign         gt_reset_rx_datapath_in_6 = gt_reset_rx_datapath_in[6];
  wire           gt_reset_tx_datapath_in_7;
  wire           gt_reset_rx_datapath_in_7;
  assign         gt_reset_tx_datapath_in_7 = gt_reset_tx_datapath_in[7];
  assign         gt_reset_rx_datapath_in_7 = gt_reset_rx_datapath_in[7];
  wire           gtpowergood_0;
  wire           gtpowergood_1;
  wire           gt_rx_reset_done_inv;
  wire           gt_tx_reset_done_inv;
  wire           gt_rx_reset_done_core_clk_sync;
  wire           gt_tx_reset_done_core_clk_sync;
  wire           gt_rx_reset_done_axis_clk_sync;
  wire           gt_tx_reset_done_axis_clk_sync;
  wire           gtpowergood;
  wire [5:0]     pm_tick_core = {6{1'b0}};
  wire           core_clk;
  wire           axis_clk;
  wire           clk_wiz_in;
  wire           clk_wiz_locked;
  wire           clk_tx_axi;
  wire           clk_rx_axi;
  wire           [5:0] tx_serdes_is_am;
  wire           [5:0] tx_serdes_is_am_prefifo;
  wire           clk_apb3;
  wire           rstn_hard_apb3;

  wire [1023 : 0] tx_network_axis_tdata;
  wire [127  : 0] tx_network_axis_tkeep;
  wire            tx_network_axis_tvalid;
  wire            tx_network_axis_tlast;
  wire            tx_network_axis_tuser;
  wire            tx_network_axis_tready;

  wire [1023 : 0] rx_network_axis_tdata;
  wire [127 : 0]  rx_network_axis_tkeep;
  wire            rx_network_axis_tvalid;
  wire            rx_network_axis_tlast;
  wire            rx_network_axis_tuser;

  wire [1023 : 0] tx_network_pipe_axis_tdata;
  wire [127  : 0] tx_network_pipe_axis_tkeep;
  wire            tx_network_pipe_axis_tvalid;
  wire            tx_network_pipe_axis_tlast;
  wire            tx_network_pipe_axis_tuser;
  wire            tx_network_pipe_axis_tready;

  wire [1023 : 0] rx_network_pipe_axis_tdata;
  wire [127 : 0]  rx_network_pipe_axis_tkeep;
  wire            rx_network_pipe_axis_tvalid;
  wire            rx_network_pipe_axis_tlast;
  wire            rx_network_pipe_axis_tuser;

  assign clk_apb3       = s_axi_aclk;
  assign rstn_hard_apb3 = s_axi_aresetn;

assign gt_tx_reset_core = gt_tx_reset_done_inv; 
assign gt_rx_reset_core = gt_rx_reset_done_inv;

  typedef struct packed {
    logic [2:0]               id;
    logic [11:0]              ena;
    logic [11:0]              sop;
    logic [11:0]              eop;
    logic [11:0]              err;
    logic [11:0][3:0]         mty;
    logic [11:0][127:0]       dat;
  } axis_tx_pkt_t;

  typedef struct packed {
    logic [2:0]               id;
    logic [11:0]              ena;
    logic [11:0]              sop;
    logic [11:0]              eop;
    logic [11:0]              err;
    logic [11:0][3:0]         mty;
    logic [11:0][127:0]       dat;
  } axis_rx_pkt_t;

  typedef struct packed {
    logic [1:0]              ena;
    logic [1:0]              sop;
    logic [1:0]              eop;
    logic [1:0]              err;
    logic [1:0][3:0]         mty;
    logic [1:0][127:0]       dat;
  } slice_tx_t;

  typedef struct packed {
    logic [1:0]              ena;
    logic [1:0]              sop;
    logic [1:0]              eop;
    logic [1:0]              err;
    logic [1:0][3:0]         mty;
    logic [1:0][127:0]       dat;
  } slice_rx_t;

  wire                rstn_apb3;
  wire                [31:0] scratch;
  logic               [5:0] tx_axis_ch_status_id;
  logic               tx_axis_ch_status_skip_req;
  logic               tx_axis_ch_status_vld     ;
  logic               [5:0] tx_axis_id_req      ;
  logic               tx_axis_id_req_vld        ;
  wire                tx_axis_tuser_skip_response;
  // MACIF TX
  wire                tx_macif_ena;
  wire                [5:0] tx_macif_ts_id; // delayed tx_macif_ts_id_req
  logic               [5:0] tx_macif_ts_id_req; // from calendar
  wire                tx_macif_ts_id_req_rdy;
  logic               tx_macif_ts_id_req_vld;
  logic               tx_macif_ts_id_req_sic;
  wire                [23:0][65:0] tx_macif_data;
  // MACIF RX
  logic               rx_macif_ena;
  logic               rx_macif_status;  
  logic               [23:0][65:0] rx_macif_data;
  logic               [5:0] rx_macif_ts_id;

  wire                [6:0] tx_pkt_gen_ena;
  wire                [15:0] tx_pkt_gen_min_len;
  wire                [15:0] tx_pkt_gen_max_len;
  wire                [39:0] clear_tx_counters;
  wire                [39:0] clear_rx_counters;


  wire                [5:0][63:0] tx_frames_transmitted_latched, tx_bytes_transmitted_latched;
  wire                [5:0][63:0] rx_frames_received_latched, rx_bytes_received_latched;
  wire                [5:0]       rx_prbs_locked;
  wire                [5:0][31:0] rx_prbs_err;


  axis_tx_pkt_t    tx_gen_axis_pkt, tx_axis_pkt;
  wire             tx_axis_pkt_valid;
  axis_rx_pkt_t    rx_axis_pkt, rx_axis_pkt_mon;
  wire             [11:0] rx_axis_pkt_ena;
  wire             [5:0] rx_axis_tvalid;

  wire             [55:0] tx_tsmac_tdm_stats_data;
  wire             [5:0] tx_tsmac_tdm_stats_id;
  wire             tx_tsmac_tdm_stats_valid;
  wire             [78:0] rx_tsmac_tdm_stats_data;
  wire             [5:0] rx_tsmac_tdm_stats_id;
  wire             rx_tsmac_tdm_stats_valid;

  wire [15:0]      c0_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c0_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c0_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c0_stat_rx_corrected_lane_delay_3;
  wire             c0_stat_rx_corrected_lane_delay_valid;
  wire [15:0]      c1_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c1_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c1_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c1_stat_rx_corrected_lane_delay_3;
  wire             c1_stat_rx_corrected_lane_delay_valid;
  wire [15:0]      c2_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c2_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c2_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c2_stat_rx_corrected_lane_delay_3;
  wire             c2_stat_rx_corrected_lane_delay_valid;
  wire [15:0]      c3_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c3_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c3_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c3_stat_rx_corrected_lane_delay_3;
  wire             c3_stat_rx_corrected_lane_delay_valid;
  wire [15:0]      c4_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c4_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c4_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c4_stat_rx_corrected_lane_delay_3;
  wire c4_stat_rx_corrected_lane_delay_valid;
  wire [15:0]      c5_stat_rx_corrected_lane_delay_0;
  wire [15:0]      c5_stat_rx_corrected_lane_delay_1;
  wire [15:0]      c5_stat_rx_corrected_lane_delay_2;
  wire [15:0]      c5_stat_rx_corrected_lane_delay_3;
  wire             c5_stat_rx_corrected_lane_delay_valid;

  // Pause insertion
  wire                [5:0] emu_tx_resend_pause;
  wire                [5:0][8:0] emu_tx_pause_req;

  // PTP enable
  wire                [1:0]   emu_tx_ptp_opt;
  wire                [11:0]  emu_tx_ptp_cf_offset;
  wire                        emu_tx_ptp_upd_chksum;
  wire                [5:0]   emu_tx_ptp_ena;

  logic               independent_mode;
  wire                [5:0] tx_axi_vld_mask;
  wire                [5:0] tx_gearbox_af, tx_gearbox_dout_vld, tx_axis_tready, tx_axis_af;
  wire                [5:0] tx_axis_tvalid;
  slice_tx_t          [5:0] tx_gearbox_slice;
  slice_rx_t          [5:0] rx_gearbox_slice;
  wire                [5:0] tx_gearbox_ovf, tx_gearbox_unf;
  wire                [5:0] pkt_gen_id_req;
  wire                pkt_gen_id_req_vld;
  axis_rx_pkt_t       rx_gearbox_o_pkt;
  wire                [5:0][31:0] rx_preamble_err_cnt;
  wire                [5:0][1:0]  client_data_rate;

  //wire                [23:0][79:0] tx_serdes_data;
  //wire                [23:0][79:0] rx_serdes_data;

  wire                [15:0] default_vl_length_100GE = 16'd255;
  wire                [15:0] default_vl_length_200GE_or_400GE = 16'd256;

  wire                [63:0] ctl_tx_vl_marker_id0_100ge  = 64'hc16821003e97de00;
  wire                [63:0] ctl_tx_vl_marker_id1_100ge  = 64'h9d718e00628e7100;
  wire                [63:0] ctl_tx_vl_marker_id2_100ge  = 64'h594be800a6b41700;
  wire                [63:0] ctl_tx_vl_marker_id3_100ge  = 64'h4d957b00b26a8400;
  wire                [63:0] ctl_tx_vl_marker_id4_100ge  = 64'hf50709000af8f600;
  wire                [63:0] ctl_tx_vl_marker_id5_100ge  = 64'hdd14c20022eb3d00;
  wire                [63:0] ctl_tx_vl_marker_id6_100ge  = 64'h9a4a260065b5d900;
  wire                [63:0] ctl_tx_vl_marker_id7_100ge  = 64'h7b45660084ba9900;
  wire                [63:0] ctl_tx_vl_marker_id8_100ge  = 64'ha02476005fdb8900;
  wire                [63:0] ctl_tx_vl_marker_id9_100ge  = 64'h68c9fb0097360400;
  wire                [63:0] ctl_tx_vl_marker_id10_100ge = 64'hfd6c990002936600;
  wire                [63:0] ctl_tx_vl_marker_id11_100ge = 64'hb9915500466eaa00;
  wire                [63:0] ctl_tx_vl_marker_id12_100ge = 64'h5cb9b200a3464d00;
  wire                [63:0] ctl_tx_vl_marker_id13_100ge = 64'h1af8bd00e5074200;
  wire                [63:0] ctl_tx_vl_marker_id14_100ge = 64'h83c7ca007c383500;
  wire                [63:0] ctl_tx_vl_marker_id15_100ge = 64'h3536cd00cac93200;
  wire                [63:0] ctl_tx_vl_marker_id16_100ge = 64'hc4314c003bceb300;
  wire                [63:0] ctl_tx_vl_marker_id17_100ge = 64'hadd6b70052294800;
  wire                [63:0] ctl_tx_vl_marker_id18_100ge = 64'h5f662a00a099d500;
  wire                [63:0] ctl_tx_vl_marker_id19_100ge = 64'hc0f0e5003f0f1a00;

  wire                [5:0][55:0] tx_preamble;
  reg                 [5:0][55:0] rx_preamble;
  wire                [5:0][55:0] rx_axis_preamble;

  wire [5:0]          rx_flexif_clk = {6{axis_clk}};
  wire [5:0]          tx_flexif_clk = {6{axis_clk}};

  wire                rx_macif_clk = axis_clk; 
  wire                tx_macif_clk = axis_clk;
  wire                clk_wiz_reset = 1'b0;



  dcmac_0_clk_wiz_0 i_dcmac_0_clk_wiz_0 (
    .reset      (clk_wiz_reset),
    .clk_in1	(clk_wiz_in),
    .locked     (clk_wiz_locked),
    .clk_out1	(core_clk),
    .clk_out2   (axis_clk),
    .clk_out3   (ts_clk)
  );

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) i_dcmac_0_gt_rx_reset_done_core_clk_syncer (
    .clk                 (core_clk),
    .reset_async         (gt_rx_reset_done_inv),
    .reset               (gt_rx_reset_done_core_clk_sync)
  );

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) i_dcmac_0_gt_tx_reset_done_core_clk_syncer (
    .clk                 (core_clk),
    .reset_async         (gt_tx_reset_done_inv),
    .reset               (gt_tx_reset_done_core_clk_sync)
  );

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) i_dcmac_0_gt_rx_reset_done_axis_clk_syncer (
    .clk                 (axis_clk),
    .reset_async         (gt_rx_reset_done_inv),
    .reset               (gt_rx_reset_done_axis_clk_sync)
  );

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) i_dcmac_0_gt_tx_reset_done_axis_clk_syncer (
    .clk                 (axis_clk),
    .reset_async         (gt_tx_reset_done_inv),
    .reset               (gt_tx_reset_done_axis_clk_sync)
  );

  assign gtpowergood       = gtpowergood_0; 
  assign gt_reset_done     = gt_rx_reset_done_out[0];

  ///// Core and Serdes Resets
  assign gt_rx_reset_done_inv  = ~gt_rx_reset_done_out[0];
  assign gt_tx_reset_done_inv  = ~gt_tx_reset_done_out[0];
  ///////  Core and Serdes Clocking
  assign rx_alt_serdes_clk = {1'b0,1'b0,gt0_rx_usrclk2_0,gt0_rx_usrclk2_0,gt0_rx_usrclk2_0,gt0_rx_usrclk2_0};
  assign tx_alt_serdes_clk = {1'b0,1'b0,gt0_tx_usrclk2_0,gt0_tx_usrclk2_0,gt0_tx_usrclk2_0,gt0_tx_usrclk2_0};
  assign rx_serdes_clk     = {1'b0,1'b0,gt0_rx_usrclk_0,gt0_rx_usrclk_0,gt0_rx_usrclk_0,gt0_rx_usrclk_0}; 
  assign tx_serdes_clk     = {1'b0,1'b0,gt0_tx_usrclk_0,gt0_tx_usrclk_0,gt0_tx_usrclk_0,gt0_tx_usrclk_0}; 


  ///// Core Clocks
  assign tx_core_clk       = core_clk;
  assign rx_core_clk       = core_clk;

  ///// AXIS Clocks
  assign clk_tx_axi        = axis_clk;
  assign clk_rx_axi        = axis_clk;
  assign rstn_tx_axi       = clk_wiz_locked & ~gt_tx_reset_done_axis_clk_sync;
  assign rstn_rx_axi       = clk_wiz_locked & ~gt_rx_reset_done_axis_clk_sync;



  dcmac_0_exdes_support_wrapper i_dcmac_0_exdes_support_wrapper
  (
  .CLK_IN_D_0_clk_n(gt_ref_clk0_n),
  .CLK_IN_D_0_clk_p(gt_ref_clk0_p),
  .CLK_IN_D_1_clk_n(gt_ref_clk1_n),
  .CLK_IN_D_1_clk_p(gt_ref_clk1_p),
  .GT_Serial_grx_n(gt_rxn_in0),
  .GT_Serial_grx_p(gt_rxp_in0),
  .GT_Serial_gtx_n(gt_txn_out0),
  .GT_Serial_gtx_p(gt_txp_out0),
  .GT_Serial_1_grx_n(gt_rxn_in1),
  .GT_Serial_1_grx_p(gt_rxp_in1),
  .GT_Serial_1_gtx_n(gt_txn_out1),
  .GT_Serial_1_gtx_p(gt_txp_out1),
  .IBUFDS_ODIV2(clk_wiz_in),
  .gt_rxcdrhold(gt_rxcdrhold),
  .gt_txprecursor(gt_txprecursor),
  .gt_txpostcursor(gt_txpostcursor),
  .gt_txmaincursor(gt_txmaincursor),
  .ch0_loopback_0(gt_loopback),
  .ch0_loopback_1(gt_loopback),
  .ch0_rxrate_0(SW_REG_GT_LINE_RATE[7:0]),
  .ch0_rxrate_1(SW_REG_GT_LINE_RATE[7:0]),
  .ch0_txrate_0(SW_REG_GT_LINE_RATE[7:0]),
  .ch0_txrate_1(SW_REG_GT_LINE_RATE[7:0]),
  .ch0_tx_usr_clk2_0(gt0_tx_usrclk2_0),
  .ch0_tx_usr_clk_0(gt0_tx_usrclk_0),
  .ch0_rx_usr_clk2_0(gt0_rx_usrclk2_0),
  .ch0_rx_usr_clk_0(gt0_rx_usrclk_0),
  .ch1_loopback_0(gt_loopback),
  .ch1_loopback_1(gt_loopback),
  .ch1_rxrate_0(SW_REG_GT_LINE_RATE[15:8]),
  .ch1_rxrate_1(SW_REG_GT_LINE_RATE[15:8]),
  .ch1_txrate_0(SW_REG_GT_LINE_RATE[15:8]),
  .ch1_txrate_1(SW_REG_GT_LINE_RATE[15:8]),
  .ch2_loopback_0(gt_loopback),
  .ch2_loopback_1(gt_loopback),
  .ch2_rxrate_0(SW_REG_GT_LINE_RATE[23:16]),
  .ch2_rxrate_1(SW_REG_GT_LINE_RATE[23:16]),
  .ch2_txrate_0(SW_REG_GT_LINE_RATE[23:16]),
  .ch2_txrate_1(SW_REG_GT_LINE_RATE[23:16]),
  .ch3_loopback_0(gt_loopback),
  .ch3_loopback_1(gt_loopback),
  .ch3_rxrate_0(SW_REG_GT_LINE_RATE[31:24]),
  .ch3_rxrate_1(SW_REG_GT_LINE_RATE[31:24]),
  .ch3_txrate_0(SW_REG_GT_LINE_RATE[31:24]),
  .ch3_txrate_1(SW_REG_GT_LINE_RATE[31:24]),
  .gtpowergood_0(gtpowergood_0),
  .gtpowergood_1(gtpowergood_1),
  .ctl_port_ctl_rx_custom_vl_length_minus1(default_vl_length_200GE_or_400GE),
  .ctl_port_ctl_tx_custom_vl_length_minus1(default_vl_length_200GE_or_400GE),
  .ctl_port_ctl_vl_marker_id0(ctl_tx_vl_marker_id0_100ge),
  .ctl_port_ctl_vl_marker_id1(ctl_tx_vl_marker_id1_100ge),
  .ctl_port_ctl_vl_marker_id2(ctl_tx_vl_marker_id2_100ge),
  .ctl_port_ctl_vl_marker_id3(ctl_tx_vl_marker_id3_100ge),
  .ctl_port_ctl_vl_marker_id4(ctl_tx_vl_marker_id4_100ge),
  .ctl_port_ctl_vl_marker_id5(ctl_tx_vl_marker_id5_100ge),
  .ctl_port_ctl_vl_marker_id6(ctl_tx_vl_marker_id6_100ge),
  .ctl_port_ctl_vl_marker_id7(ctl_tx_vl_marker_id7_100ge),
  .ctl_port_ctl_vl_marker_id8(ctl_tx_vl_marker_id8_100ge),
  .ctl_port_ctl_vl_marker_id9(ctl_tx_vl_marker_id9_100ge),
  .ctl_port_ctl_vl_marker_id10(ctl_tx_vl_marker_id10_100ge),
  .ctl_port_ctl_vl_marker_id11(ctl_tx_vl_marker_id11_100ge),
  .ctl_port_ctl_vl_marker_id12(ctl_tx_vl_marker_id12_100ge),
  .ctl_port_ctl_vl_marker_id13(ctl_tx_vl_marker_id13_100ge),
  .ctl_port_ctl_vl_marker_id14(ctl_tx_vl_marker_id14_100ge),
  .ctl_port_ctl_vl_marker_id15(ctl_tx_vl_marker_id15_100ge),
  .ctl_port_ctl_vl_marker_id16(ctl_tx_vl_marker_id16_100ge),
  .ctl_port_ctl_vl_marker_id17(ctl_tx_vl_marker_id17_100ge),
  .ctl_port_ctl_vl_marker_id18(ctl_tx_vl_marker_id18_100ge),
  .ctl_port_ctl_vl_marker_id19(ctl_tx_vl_marker_id19_100ge),
  .ctl_txrx_port0_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port0_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port0_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port0_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port0_ctl_tx_send_rfi_in(1'b0),
  .ctl_txrx_port1_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port1_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port1_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port1_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port1_ctl_tx_send_rfi_in(1'b0),
  .ctl_txrx_port2_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port2_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port2_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port2_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port2_ctl_tx_send_rfi_in(1'b0),
  .ctl_txrx_port3_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port3_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port3_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port3_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port3_ctl_tx_send_rfi_in(1'b0),
  .ctl_txrx_port4_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port4_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port4_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port4_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port4_ctl_tx_send_rfi_in(1'b0),
  .ctl_txrx_port5_ctl_tx_lane0_vlm_bip7_override(1'b0),
  .ctl_txrx_port5_ctl_tx_lane0_vlm_bip7_override_value(8'd0),
  .ctl_txrx_port5_ctl_tx_send_idle_in(1'b0),
  .ctl_txrx_port5_ctl_tx_send_lfi_in(1'b0),
  .ctl_txrx_port5_ctl_tx_send_rfi_in(1'b0),
  .gt_reset_all_in(gt_reset_all_in),
  .gpo(gt_gpo),
  .gt_reset_tx_datapath_in_0(gt_reset_tx_datapath_in_0),
  .gt_reset_rx_datapath_in_0(gt_reset_rx_datapath_in_0),
  .gt_tx_reset_done_out_0(gt_tx_reset_done_out[0]),
  .gt_rx_reset_done_out_0(gt_rx_reset_done_out[0]),
  .gt_reset_tx_datapath_in_1(gt_reset_tx_datapath_in_1),
  .gt_reset_rx_datapath_in_1(gt_reset_rx_datapath_in_1),
  .gt_tx_reset_done_out_1(gt_tx_reset_done_out[1]),
  .gt_rx_reset_done_out_1(gt_rx_reset_done_out[1]),
  .gt_reset_tx_datapath_in_2(gt_reset_tx_datapath_in_2),
  .gt_reset_rx_datapath_in_2(gt_reset_rx_datapath_in_2),
  .gt_tx_reset_done_out_2(gt_tx_reset_done_out[2]),
  .gt_rx_reset_done_out_2(gt_rx_reset_done_out[2]),
  .gt_reset_tx_datapath_in_3(gt_reset_tx_datapath_in_3),
  .gt_reset_rx_datapath_in_3(gt_reset_rx_datapath_in_3),
  .gt_tx_reset_done_out_3(gt_tx_reset_done_out[3]),
  .gt_rx_reset_done_out_3(gt_rx_reset_done_out[3]),
  .gt_reset_tx_datapath_in_4(gt_reset_tx_datapath_in_4),
  .gt_reset_rx_datapath_in_4(gt_reset_rx_datapath_in_4),
  .gt_tx_reset_done_out_4(gt_tx_reset_done_out[4]),
  .gt_rx_reset_done_out_4(gt_rx_reset_done_out[4]),
  .gt_reset_tx_datapath_in_5(gt_reset_tx_datapath_in_5),
  .gt_reset_rx_datapath_in_5(gt_reset_rx_datapath_in_5),
  .gt_tx_reset_done_out_5(gt_tx_reset_done_out[5]),
  .gt_rx_reset_done_out_5(gt_rx_reset_done_out[5]),
  .gt_reset_tx_datapath_in_6(gt_reset_tx_datapath_in_6),
  .gt_reset_rx_datapath_in_6(gt_reset_rx_datapath_in_6),
  .gt_tx_reset_done_out_6(gt_tx_reset_done_out[6]),
  .gt_rx_reset_done_out_6(gt_rx_reset_done_out[6]),
  .gt_reset_tx_datapath_in_7(gt_reset_tx_datapath_in_7),
  .gt_reset_rx_datapath_in_7(gt_reset_rx_datapath_in_7),
  .gt_tx_reset_done_out_7(gt_tx_reset_done_out[7]),
  .gt_rx_reset_done_out_7(gt_rx_reset_done_out[7]),
  .gtpowergood_in(gtpowergood),
  .ctl_rsvd_in(120'd0),
  .rsvd_in_rx_mac(8'd0),
  .rsvd_in_rx_phy(8'd0),
  .rx_all_channel_mac_pm_tick(1'b0),
  .rx_alt_serdes_clk(rx_alt_serdes_clk),
  .rx_axi_clk(clk_rx_axi),
  .rx_axis_tdata0(rx_axis_pkt.dat[0]),
  .rx_axis_tdata1(rx_axis_pkt.dat[1]),
  .rx_axis_tuser_ena0(rx_axis_pkt.ena[0]),
  .rx_axis_tuser_ena1(rx_axis_pkt.ena[1]),
  .rx_axis_tuser_eop0(rx_axis_pkt.eop[0]),
  .rx_axis_tuser_eop1(rx_axis_pkt.eop[1]),
  .rx_axis_tuser_err0(rx_axis_pkt.err[0]),
  .rx_axis_tuser_err1(rx_axis_pkt.err[1]),
  .rx_axis_tuser_mty0(rx_axis_pkt.mty[0]),
  .rx_axis_tuser_mty1(rx_axis_pkt.mty[1]),
  .rx_axis_tuser_sop0(rx_axis_pkt.sop[0]),
  .rx_axis_tuser_sop1(rx_axis_pkt.sop[1]),
  .rx_axis_tdata2(rx_axis_pkt.dat[2]),
  .rx_axis_tdata3(rx_axis_pkt.dat[3]),
  .rx_axis_tuser_ena2(rx_axis_pkt.ena[2]),
  .rx_axis_tuser_ena3(rx_axis_pkt.ena[3]),
  .rx_axis_tuser_eop2(rx_axis_pkt.eop[2]),
  .rx_axis_tuser_eop3(rx_axis_pkt.eop[3]),
  .rx_axis_tuser_err2(rx_axis_pkt.err[2]),
  .rx_axis_tuser_err3(rx_axis_pkt.err[3]),
  .rx_axis_tuser_mty2(rx_axis_pkt.mty[2]),
  .rx_axis_tuser_mty3(rx_axis_pkt.mty[3]),
  .rx_axis_tuser_sop2(rx_axis_pkt.sop[2]),
  .rx_axis_tuser_sop3(rx_axis_pkt.sop[3]),
  .rx_axis_tdata4(rx_axis_pkt.dat[4]),
  .rx_axis_tdata5(rx_axis_pkt.dat[5]),
  .rx_axis_tuser_ena4(rx_axis_pkt.ena[4]),
  .rx_axis_tuser_ena5(rx_axis_pkt.ena[5]),
  .rx_axis_tuser_eop4(rx_axis_pkt.eop[4]),
  .rx_axis_tuser_eop5(rx_axis_pkt.eop[5]),
  .rx_axis_tuser_err4(rx_axis_pkt.err[4]),
  .rx_axis_tuser_err5(rx_axis_pkt.err[5]),
  .rx_axis_tuser_mty4(rx_axis_pkt.mty[4]),
  .rx_axis_tuser_mty5(rx_axis_pkt.mty[5]),
  .rx_axis_tuser_sop4(rx_axis_pkt.sop[4]),
  .rx_axis_tuser_sop5(rx_axis_pkt.sop[5]),
  .rx_axis_tdata6(rx_axis_pkt.dat[6]),
  .rx_axis_tdata7(rx_axis_pkt.dat[7]),
  .rx_axis_tuser_ena6(rx_axis_pkt.ena[6]),
  .rx_axis_tuser_ena7(rx_axis_pkt.ena[7]),
  .rx_axis_tuser_eop6(rx_axis_pkt.eop[6]),
  .rx_axis_tuser_eop7(rx_axis_pkt.eop[7]),
  .rx_axis_tuser_err6(rx_axis_pkt.err[6]),
  .rx_axis_tuser_err7(rx_axis_pkt.err[7]),
  .rx_axis_tuser_mty6(rx_axis_pkt.mty[6]),
  .rx_axis_tuser_mty7(rx_axis_pkt.mty[7]),
  .rx_axis_tuser_sop6(rx_axis_pkt.sop[6]),
  .rx_axis_tuser_sop7(rx_axis_pkt.sop[7]),
  .rx_axis_tvalid_0(rx_axis_tvalid[0]),
  .rx_channel_flush(6'd0),
  .rx_core_clk(rx_core_clk),
  .rx_core_reset(rx_core_reset),
  .rx_flexif_clk(rx_flexif_clk),
  .rx_lane_aligner_fill(),
  .rx_lane_aligner_fill_start(),
  .rx_lane_aligner_fill_valid(),
  .rx_macif_clk(rx_macif_clk),
  .rx_pcs_tdm_stats_data(),
  .rx_pcs_tdm_stats_start(),
  .rx_pcs_tdm_stats_valid(),
  .rx_port_pm_rdy(),
  .rx_preambleout_0(rx_axis_preamble[0]),
  
  .rx_serdes_albuf_restart_0(),
  .rx_serdes_albuf_restart_1(),
  .rx_serdes_albuf_restart_2(),
  .rx_serdes_albuf_restart_3(),
  .rx_serdes_albuf_restart_4(),
  .rx_serdes_albuf_restart_5(),
  .rx_serdes_albuf_slip_0(),
  .rx_serdes_albuf_slip_1(),
  .rx_serdes_albuf_slip_2(),
  .rx_serdes_albuf_slip_3(),
  .rx_serdes_albuf_slip_4(),
  .rx_serdes_albuf_slip_5(),
  .rx_serdes_albuf_slip_6(),
  .rx_serdes_albuf_slip_7(),
  .rx_serdes_albuf_slip_8(),
  .rx_serdes_albuf_slip_9(),
  .rx_serdes_albuf_slip_10(),
  .rx_serdes_albuf_slip_11(),
  .rx_serdes_albuf_slip_12(),
  .rx_serdes_albuf_slip_13(),
  .rx_serdes_albuf_slip_14(),
  .rx_serdes_albuf_slip_15(),
  .rx_serdes_albuf_slip_16(),
  .rx_serdes_albuf_slip_17(),
  .rx_serdes_albuf_slip_18(),
  .rx_serdes_albuf_slip_19(),
  .rx_serdes_albuf_slip_20(),
  .rx_serdes_albuf_slip_21(),
  .rx_serdes_albuf_slip_22(),
  .rx_serdes_albuf_slip_23(),
  .rx_serdes_clk(rx_serdes_clk),
  .rx_serdes_fifo_flagin_0(1'b0),
  .rx_serdes_fifo_flagin_1(1'b0),
  .rx_serdes_fifo_flagin_2(1'b0),
  .rx_serdes_fifo_flagin_3(1'b0),
  .rx_serdes_fifo_flagin_4(1'b0),
  .rx_serdes_fifo_flagin_5(1'b0),
  .rx_serdes_fifo_flagout_0(),
  .rx_serdes_fifo_flagout_1(),
  .rx_serdes_fifo_flagout_2(),
  .rx_serdes_fifo_flagout_3(),
  .rx_serdes_fifo_flagout_4(),
  .rx_serdes_fifo_flagout_5(),
  .rx_serdes_reset(rx_serdes_reset),
  .rx_tsmac_tdm_stats_data(rx_tsmac_tdm_stats_data),
  .rx_tsmac_tdm_stats_id(rx_tsmac_tdm_stats_id),
  .rx_tsmac_tdm_stats_valid(rx_tsmac_tdm_stats_valid),

  //// GT APB3 ports
  .apb3clk_quad(s_axi_aclk),
  .s_axi_araddr(s_axi_araddr),
  .s_axi_arready(s_axi_arready),
  .s_axi_arvalid(s_axi_arvalid),
  .s_axi_awaddr(s_axi_awaddr),
  .s_axi_awready(s_axi_awready),
  .s_axi_awvalid(s_axi_awvalid),
  .s_axi_bready(s_axi_bready),
  .s_axi_bresp(s_axi_bresp),
  .s_axi_bvalid(s_axi_bvalid),
  .s_axi_rdata(s_axi_rdata),
  .s_axi_rready(s_axi_rready),
  .s_axi_rresp(s_axi_rresp),
  .s_axi_rvalid(s_axi_rvalid),
  .s_axi_wdata(s_axi_wdata),
  .s_axi_wready(s_axi_wready),
  .s_axi_wvalid(s_axi_wvalid),
  .s_axi_aclk(s_axi_aclk),
  .s_axi_aresetn(s_axi_aresetn),
  .ts_clk({6{ts_clk}}),

  .tx_all_channel_mac_pm_rdy(),
  .tx_all_channel_mac_pm_tick(1'b0),
  .tx_alt_serdes_clk(tx_alt_serdes_clk),
  .tx_axi_clk(clk_tx_axi),
  .tx_axis_tdata0(tx_axis_pkt.dat[0]),
  .tx_axis_tdata1(tx_axis_pkt.dat[1]),
  .tx_axis_tuser_ena0(tx_axis_pkt.ena[0]),
  .tx_axis_tuser_ena1(tx_axis_pkt.ena[1]),
  .tx_axis_tuser_eop0(tx_axis_pkt.eop[0]),
  .tx_axis_tuser_eop1(tx_axis_pkt.eop[1]),
  .tx_axis_tuser_err0(tx_axis_pkt.err[0]),
  .tx_axis_tuser_err1(tx_axis_pkt.err[1]),
  .tx_axis_tuser_mty0(tx_axis_pkt.mty[0]),
  .tx_axis_tuser_mty1(tx_axis_pkt.mty[1]),
  .tx_axis_tuser_sop0(tx_axis_pkt.sop[0]),
  .tx_axis_tuser_sop1(tx_axis_pkt.sop[1]),
  .tx_axis_tdata2(tx_axis_pkt.dat[2]),
  .tx_axis_tdata3(tx_axis_pkt.dat[3]),
  .tx_axis_tuser_ena2(tx_axis_pkt.ena[2]),
  .tx_axis_tuser_ena3(tx_axis_pkt.ena[3]),
  .tx_axis_tuser_eop2(tx_axis_pkt.eop[2]),
  .tx_axis_tuser_eop3(tx_axis_pkt.eop[3]),
  .tx_axis_tuser_err2(tx_axis_pkt.err[2]),
  .tx_axis_tuser_err3(tx_axis_pkt.err[3]),
  .tx_axis_tuser_mty2(tx_axis_pkt.mty[2]),
  .tx_axis_tuser_mty3(tx_axis_pkt.mty[3]),
  .tx_axis_tuser_sop2(tx_axis_pkt.sop[2]),
  .tx_axis_tuser_sop3(tx_axis_pkt.sop[3]),
  .tx_axis_tdata4(tx_axis_pkt.dat[4]),
  .tx_axis_tdata5(tx_axis_pkt.dat[5]),
  .tx_axis_tuser_ena4(tx_axis_pkt.ena[4]),
  .tx_axis_tuser_ena5(tx_axis_pkt.ena[5]),
  .tx_axis_tuser_eop4(tx_axis_pkt.eop[4]),
  .tx_axis_tuser_eop5(tx_axis_pkt.eop[5]),
  .tx_axis_tuser_err4(tx_axis_pkt.err[4]),
  .tx_axis_tuser_err5(tx_axis_pkt.err[5]),
  .tx_axis_tuser_mty4(tx_axis_pkt.mty[4]),
  .tx_axis_tuser_mty5(tx_axis_pkt.mty[5]),
  .tx_axis_tuser_sop4(tx_axis_pkt.sop[4]),
  .tx_axis_tuser_sop5(tx_axis_pkt.sop[5]),
  .tx_axis_tdata6(tx_axis_pkt.dat[6]),
  .tx_axis_tdata7(tx_axis_pkt.dat[7]),
  .tx_axis_tuser_ena6(tx_axis_pkt.ena[6]),
  .tx_axis_tuser_ena7(tx_axis_pkt.ena[7]),
  .tx_axis_tuser_eop6(tx_axis_pkt.eop[6]),
  .tx_axis_tuser_eop7(tx_axis_pkt.eop[7]),
  .tx_axis_tuser_err6(tx_axis_pkt.err[6]),
  .tx_axis_tuser_err7(tx_axis_pkt.err[7]),
  .tx_axis_tuser_mty6(tx_axis_pkt.mty[6]),
  .tx_axis_tuser_mty7(tx_axis_pkt.mty[7]),
  .tx_axis_tuser_sop6(tx_axis_pkt.sop[6]),
  .tx_axis_tuser_sop7(tx_axis_pkt.sop[7]),
  .tx_axis_taf_0(tx_axis_af[0]),
  .tx_axis_tready_0(tx_axis_tready[0]),  
  .tx_axis_tvalid_0(tx_axis_tvalid[0]),
  .tx_channel_flush(6'd0),
  .tx_core_clk(tx_core_clk),
  .tx_core_reset(tx_core_reset),
  .tx_flexif_clk(tx_flexif_clk),
  .tx_macif_clk(tx_macif_clk),
  .tx_pcs_tdm_stats_data(),
  .tx_pcs_tdm_stats_start(),
  .tx_pcs_tdm_stats_valid(),
  .tx_port_pm_rdy(),
  .tx_port_pm_tick(pm_tick_core),
  .rx_port_pm_tick(pm_tick_core),
  .tx_preamblein_0(tx_preamble[0]),
  .tx_serdes_clk(tx_serdes_clk),
  .tx_serdes_is_am_0(tx_serdes_is_am[0]),
  .tx_serdes_is_am_1(tx_serdes_is_am[1]),
  .tx_serdes_is_am_2(tx_serdes_is_am[2]),
  .tx_serdes_is_am_3(tx_serdes_is_am[3]),
  .tx_serdes_is_am_4(tx_serdes_is_am[4]),
  .tx_serdes_is_am_5(tx_serdes_is_am[5]),
  .tx_serdes_is_am_prefifo_0(tx_serdes_is_am_prefifo[0]),
  .tx_serdes_is_am_prefifo_1(tx_serdes_is_am_prefifo[1]),
  .tx_serdes_is_am_prefifo_2(tx_serdes_is_am_prefifo[2]),
  .tx_serdes_is_am_prefifo_3(tx_serdes_is_am_prefifo[3]),
  .tx_serdes_is_am_prefifo_4(tx_serdes_is_am_prefifo[4]),
  .tx_serdes_is_am_prefifo_5(tx_serdes_is_am_prefifo[5]),
  .tx_tsmac_tdm_stats_data(tx_tsmac_tdm_stats_data),
  .tx_tsmac_tdm_stats_id(tx_tsmac_tdm_stats_id),
  .tx_tsmac_tdm_stats_valid(tx_tsmac_tdm_stats_valid),
  .c0_stat_rx_corrected_lane_delay_0(c0_stat_rx_corrected_lane_delay_0),
  .c0_stat_rx_corrected_lane_delay_1(c0_stat_rx_corrected_lane_delay_1),
  .c0_stat_rx_corrected_lane_delay_2(c0_stat_rx_corrected_lane_delay_2),
  .c0_stat_rx_corrected_lane_delay_3(c0_stat_rx_corrected_lane_delay_3),
  .c0_stat_rx_corrected_lane_delay_valid(c0_stat_rx_corrected_lane_delay_valid),
  .c1_stat_rx_corrected_lane_delay_0(c1_stat_rx_corrected_lane_delay_0),
  .c1_stat_rx_corrected_lane_delay_1(c1_stat_rx_corrected_lane_delay_1),
  .c1_stat_rx_corrected_lane_delay_2(c1_stat_rx_corrected_lane_delay_2),
  .c1_stat_rx_corrected_lane_delay_3(c1_stat_rx_corrected_lane_delay_3),
  .c1_stat_rx_corrected_lane_delay_valid(c1_stat_rx_corrected_lane_delay_valid),
  .c2_stat_rx_corrected_lane_delay_0(c2_stat_rx_corrected_lane_delay_0),
  .c2_stat_rx_corrected_lane_delay_1(c2_stat_rx_corrected_lane_delay_1),
  .c2_stat_rx_corrected_lane_delay_2(c2_stat_rx_corrected_lane_delay_2),
  .c2_stat_rx_corrected_lane_delay_3(c2_stat_rx_corrected_lane_delay_3),
  .c2_stat_rx_corrected_lane_delay_valid(c2_stat_rx_corrected_lane_delay_valid),
  .c3_stat_rx_corrected_lane_delay_0(c3_stat_rx_corrected_lane_delay_0),
  .c3_stat_rx_corrected_lane_delay_1(c3_stat_rx_corrected_lane_delay_1),
  .c3_stat_rx_corrected_lane_delay_2(c3_stat_rx_corrected_lane_delay_2),
  .c3_stat_rx_corrected_lane_delay_3(c3_stat_rx_corrected_lane_delay_3),
  .c3_stat_rx_corrected_lane_delay_valid(c3_stat_rx_corrected_lane_delay_valid),
  .c4_stat_rx_corrected_lane_delay_0(c4_stat_rx_corrected_lane_delay_0),
  .c4_stat_rx_corrected_lane_delay_1(c4_stat_rx_corrected_lane_delay_1),
  .c4_stat_rx_corrected_lane_delay_2(c4_stat_rx_corrected_lane_delay_2),
  .c4_stat_rx_corrected_lane_delay_3(c4_stat_rx_corrected_lane_delay_3),
  .c4_stat_rx_corrected_lane_delay_valid(c4_stat_rx_corrected_lane_delay_valid),
  .c5_stat_rx_corrected_lane_delay_0(c5_stat_rx_corrected_lane_delay_0),
  .c5_stat_rx_corrected_lane_delay_1(c5_stat_rx_corrected_lane_delay_1),
  .c5_stat_rx_corrected_lane_delay_2(c5_stat_rx_corrected_lane_delay_2),
  .c5_stat_rx_corrected_lane_delay_3(c5_stat_rx_corrected_lane_delay_3),
  .c5_stat_rx_corrected_lane_delay_valid(c5_stat_rx_corrected_lane_delay_valid),
  .tx_serdes_reset(tx_serdes_reset)
  );


  //------------------------------------------
  // EMU registers
  //------------------------------------------
  dcmac_0_emu_register i_dcmac_0_emu_register (
  .apb3_clk                               (clk_apb3),
  .apb3_rstn                              (rstn_apb3),
  .hard_rstn                              (rstn_hard_apb3),
  .APB_M_prdata                           (APB_M2_prdata),
  .APB_M_pready                           (APB_M2_pready),
  .APB_M_pslverr                          (APB_M2_pslverr),
  .APB_M_paddr                            (APB_M2_paddr),
  .APB_M_penable                          (APB_M2_penable),
  .APB_M_psel                             (APB_M2_psel),
  .APB_M_pwdata                           (APB_M2_pwdata),
  .APB_M_pwrite                           (APB_M2_pwrite),

  .tx_pkt_gen_ena                         (tx_pkt_gen_ena),
  .tx_pkt_gen_min_len                     (tx_pkt_gen_min_len),
  .tx_pkt_gen_max_len                     (tx_pkt_gen_max_len),
  .clear_tx_counters                      (clear_tx_counters),
  .clear_rx_counters                      (clear_rx_counters),

  .tx_pause_req                           (emu_tx_pause_req),
  .tx_resend_pause                        (emu_tx_resend_pause),
  .tx_ptp_ena                             (emu_tx_ptp_ena),
  .tx_ptp_opt                             (emu_tx_ptp_opt),
  .tx_ptp_cf_offset                       (emu_tx_ptp_cf_offset),
  .tx_ptp_upd_chksum                      (emu_tx_ptp_upd_chksum),

  .tx_macif_clk                           (),
  .tx_macif_ts_id_req_rdy                 (),
  .tx_macif_ts_id_req                     (),
  .tx_macif_ts_id_req_vld                 (),

  .client_tx_frames_transmitted_latched   (tx_frames_transmitted_latched),
  .client_tx_bytes_transmitted_latched    (tx_bytes_transmitted_latched),
  .client_rx_frames_received_latched      (rx_frames_received_latched),
  .client_rx_bytes_received_latched       (rx_bytes_received_latched),
  .client_rx_preamble_err_cnt             (rx_preamble_err_cnt),
  .client_rx_prbs_locked                  (rx_prbs_locked),
  .client_rx_prbs_err                     (rx_prbs_err),

  .gearbox_unf                            (tx_gearbox_unf),
  .gearbox_ovf                            (tx_gearbox_ovf),

  .scratch                                (scratch),
  .apb3_rstn_out                          (rstn_apb3)
  );
  
  reg                [55:0] tx_tsmac_tdm_stats_data_reg;
  reg                [5:0] tx_tsmac_tdm_stats_id_reg;
  reg                tx_tsmac_tdm_stats_valid_reg;
  reg                [78:0] rx_tsmac_tdm_stats_data_reg;
  reg                [5:0] rx_tsmac_tdm_stats_id_reg;
  reg                rx_tsmac_tdm_stats_valid_reg;

  always @(posedge clk_tx_axi) begin
    tx_tsmac_tdm_stats_valid_reg <= tx_tsmac_tdm_stats_valid;
    tx_tsmac_tdm_stats_id_reg    <= tx_tsmac_tdm_stats_id   ;
    tx_tsmac_tdm_stats_data_reg  <= tx_tsmac_tdm_stats_data ;
  end

  always @(posedge clk_rx_axi) begin
    rx_tsmac_tdm_stats_valid_reg <= rx_tsmac_tdm_stats_valid;
    rx_tsmac_tdm_stats_id_reg    <= rx_tsmac_tdm_stats_id   ;
    rx_tsmac_tdm_stats_data_reg  <= rx_tsmac_tdm_stats_data ;
  end

  wire rst_tx_network, rst_rx_network; 

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) lbus_tx_reset (
    .clk                 (clk_tx_axi),
    .reset_async         (gt_tx_reset_done_inv),
    .reset               (rst_tx_network)
  );

  dcmac_0_syncer_reset #(
    .RESET_PIPE_LEN      (3)
  ) lbus_rx_reset (
    .clk                 (clk_rx_axi),
    .reset_async         (gt_rx_reset_done_inv),
    .reset               (rst_rx_network)
  );

  lbustxaxisrx400g #(
    .dataswap(1'b0)
  ) lbustxaxisrx400g_instance (
    .lbus_txclk   (clk_tx_axi),
    .lbus_txreset (rst_tx_network),

    .axis_rx_tdata (tx_network_axis_tdata),
    .axis_rx_tvalid(tx_network_axis_tvalid),
    .axis_rx_tready(tx_network_axis_tready),
    .axis_rx_tkeep (tx_network_axis_tkeep),
    .axis_rx_tlast (tx_network_axis_tlast),
    .axis_rx_tuser (tx_network_axis_tuser),

    .lbus_tx_rdyout(tx_axis_tready[0]),

    .lbus_txdataout0(tx_axis_pkt.dat[0]),
    .lbus_txenaout0 (tx_axis_pkt.ena[0]),
    .lbus_txsopout0 (tx_axis_pkt.sop[0]),
    .lbus_txeopout0 (tx_axis_pkt.eop[0]),
    .lbus_txerrout0 (tx_axis_pkt.err[0]),
    .lbus_txmtyout0 (tx_axis_pkt.mty[0]),

    .lbus_txdataout1(tx_axis_pkt.dat[1]),
    .lbus_txenaout1 (tx_axis_pkt.ena[1]),
    .lbus_txsopout1 (tx_axis_pkt.sop[1]),
    .lbus_txeopout1 (tx_axis_pkt.eop[1]),
    .lbus_txerrout1 (tx_axis_pkt.err[1]),
    .lbus_txmtyout1 (tx_axis_pkt.mty[1]),

    .lbus_txdataout2(tx_axis_pkt.dat[2]),
    .lbus_txenaout2 (tx_axis_pkt.ena[2]),
    .lbus_txsopout2 (tx_axis_pkt.sop[2]),
    .lbus_txeopout2 (tx_axis_pkt.eop[2]),
    .lbus_txerrout2 (tx_axis_pkt.err[2]),
    .lbus_txmtyout2 (tx_axis_pkt.mty[2]),

    .lbus_txdataout3(tx_axis_pkt.dat[3]),
    .lbus_txenaout3 (tx_axis_pkt.ena[3]),
    .lbus_txsopout3 (tx_axis_pkt.sop[3]),
    .lbus_txeopout3 (tx_axis_pkt.eop[3]),
    .lbus_txerrout3 (tx_axis_pkt.err[3]),
    .lbus_txmtyout3 (tx_axis_pkt.mty[3]),

    .lbus_txdataout4(tx_axis_pkt.dat[4]),
    .lbus_txenaout4 (tx_axis_pkt.ena[4]),
    .lbus_txsopout4 (tx_axis_pkt.sop[4]),
    .lbus_txeopout4 (tx_axis_pkt.eop[4]),
    .lbus_txerrout4 (tx_axis_pkt.err[4]),
    .lbus_txmtyout4 (tx_axis_pkt.mty[4]),

    .lbus_txdataout5(tx_axis_pkt.dat[5]),
    .lbus_txenaout5 (tx_axis_pkt.ena[5]),
    .lbus_txsopout5 (tx_axis_pkt.sop[5]),
    .lbus_txeopout5 (tx_axis_pkt.eop[5]),
    .lbus_txerrout5 (tx_axis_pkt.err[5]),
    .lbus_txmtyout5 (tx_axis_pkt.mty[5]),

    .lbus_txdataout6(tx_axis_pkt.dat[6]),
    .lbus_txenaout6 (tx_axis_pkt.ena[6]),
    .lbus_txsopout6 (tx_axis_pkt.sop[6]),
    .lbus_txeopout6 (tx_axis_pkt.eop[6]),
    .lbus_txerrout6 (tx_axis_pkt.err[6]),
    .lbus_txmtyout6 (tx_axis_pkt.mty[6]),

    .lbus_txdataout7(tx_axis_pkt.dat[7]),
    .lbus_txenaout7 (tx_axis_pkt.ena[7]),
    .lbus_txsopout7 (tx_axis_pkt.sop[7]),
    .lbus_txeopout7 (tx_axis_pkt.eop[7]),
    .lbus_txerrout7 (tx_axis_pkt.err[7]),
    .lbus_txmtyout7 (tx_axis_pkt.mty[7])
  );

  lbusrxaxistx400g lbusrxaxistx400g_instance (
    .lbus_rxclk  (clk_rx_axi),
    .lbus_rxreset(rst_rx_network),

    .axis_tx_tdata (rx_network_axis_tdata),
    .axis_tx_tvalid(rx_network_axis_tvalid),
    .axis_tx_tkeep (rx_network_axis_tkeep),
    .axis_tx_tlast (rx_network_axis_tlast),
    .axis_tx_tuser (rx_network_axis_tuser),

    .lbus_rxvldin0 (rx_axis_tvalid[0]),

    .lbus_rxdatain0(rx_axis_pkt.dat[0]),
    .lbus_rxenain0 (rx_axis_pkt.ena[0]),
    .lbus_rxsopin0 (rx_axis_pkt.sop[0]),
    .lbus_rxeopin0 (rx_axis_pkt.eop[0]),
    .lbus_rxerrin0 (rx_axis_pkt.err[0]),
    .lbus_rxmtyin0 (rx_axis_pkt.mty[0]),

    .lbus_rxdatain1(rx_axis_pkt.dat[1]),
    .lbus_rxenain1 (rx_axis_pkt.ena[1]),
    .lbus_rxsopin1 (rx_axis_pkt.sop[1]),
    .lbus_rxeopin1 (rx_axis_pkt.eop[1]),
    .lbus_rxerrin1 (rx_axis_pkt.err[1]),
    .lbus_rxmtyin1 (rx_axis_pkt.mty[1]),

    .lbus_rxdatain2(rx_axis_pkt.dat[2]),
    .lbus_rxenain2 (rx_axis_pkt.ena[2]),
    .lbus_rxsopin2 (rx_axis_pkt.sop[2]),
    .lbus_rxeopin2 (rx_axis_pkt.eop[2]),
    .lbus_rxerrin2 (rx_axis_pkt.err[2]),
    .lbus_rxmtyin2 (rx_axis_pkt.mty[2]),

    .lbus_rxdatain3(rx_axis_pkt.dat[3]),
    .lbus_rxenain3 (rx_axis_pkt.ena[3]),
    .lbus_rxsopin3 (rx_axis_pkt.sop[3]),
    .lbus_rxeopin3 (rx_axis_pkt.eop[3]),
    .lbus_rxerrin3 (rx_axis_pkt.err[3]),
    .lbus_rxmtyin3 (rx_axis_pkt.mty[3]),

    .lbus_rxdatain4(rx_axis_pkt.dat[4]),
    .lbus_rxenain4 (rx_axis_pkt.ena[4]),
    .lbus_rxsopin4 (rx_axis_pkt.sop[4]),
    .lbus_rxeopin4 (rx_axis_pkt.eop[4]),
    .lbus_rxerrin4 (rx_axis_pkt.err[4]),
    .lbus_rxmtyin4 (rx_axis_pkt.mty[4]),

    .lbus_rxdatain5(rx_axis_pkt.dat[5]),
    .lbus_rxenain5 (rx_axis_pkt.ena[5]),
    .lbus_rxsopin5 (rx_axis_pkt.sop[5]),
    .lbus_rxeopin5 (rx_axis_pkt.eop[5]),
    .lbus_rxerrin5 (rx_axis_pkt.err[5]),
    .lbus_rxmtyin5 (rx_axis_pkt.mty[5]),

    .lbus_rxdatain6(rx_axis_pkt.dat[6]),
    .lbus_rxenain6 (rx_axis_pkt.ena[6]),
    .lbus_rxsopin6 (rx_axis_pkt.sop[6]),
    .lbus_rxeopin6 (rx_axis_pkt.eop[6]),
    .lbus_rxerrin6 (rx_axis_pkt.err[6]),
    .lbus_rxmtyin6 (rx_axis_pkt.mty[6]),

    .lbus_rxdatain7(rx_axis_pkt.dat[7]),
    .lbus_rxenain7 (rx_axis_pkt.ena[7]),
    .lbus_rxsopin7 (rx_axis_pkt.sop[7]),
    .lbus_rxeopin7 (rx_axis_pkt.eop[7]),
    .lbus_rxerrin7 (rx_axis_pkt.err[7]),
    .lbus_rxmtyin7 (rx_axis_pkt.mty[7])
  );

   // to aid timings
   axis_srl_fifo #(
    .DATA_WIDTH(1024),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(128),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .DEPTH(8)
  ) rx_axis_srl_fifo (
    .clk(clk_rx_axi),
    .rst(rst_rx_network),

    // AXI input
    .s_axis_tdata (rx_network_axis_tdata),
    .s_axis_tkeep (rx_network_axis_tkeep),
    .s_axis_tvalid(rx_network_axis_tvalid),
    .s_axis_tready(),
    .s_axis_tlast (rx_network_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (rx_network_axis_tuser),

    // AXI output
    .m_axis_tdata (rx_network_pipe_axis_tdata),
    .m_axis_tkeep (rx_network_pipe_axis_tkeep),
    .m_axis_tvalid(rx_network_pipe_axis_tvalid),
    .m_axis_tready(1'b1),
    .m_axis_tlast (rx_network_pipe_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (rx_network_pipe_axis_tuser)
  );
  

   // to aid timings
   axis_srl_fifo #(
    .DATA_WIDTH(1024),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(128),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .DEPTH(8)
  ) tx_axis_srl_fifo (
    .clk(clk_tx_axi),
    .rst(rst_tx_network),

    // AXI input
    .s_axis_tdata (tx_network_pipe_axis_tdata),
    .s_axis_tkeep (tx_network_pipe_axis_tkeep),
    .s_axis_tvalid(tx_network_pipe_axis_tvalid),
    .s_axis_tready(tx_network_pipe_axis_tready),
    .s_axis_tlast (tx_network_pipe_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (tx_network_pipe_axis_tuser),

    // AXI output
    .m_axis_tdata (tx_network_axis_tdata),
    .m_axis_tkeep (tx_network_axis_tkeep),
    .m_axis_tvalid(tx_network_axis_tvalid),
    .m_axis_tready(tx_network_axis_tready),
    .m_axis_tlast (tx_network_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (tx_network_axis_tuser)
  );
  

  network_wrapper #(
    .FIFO_REGS(4)
) network_wrapper_instance (
    .clk(clk_tx_axi),
    .rst(rst_tx_network),
    .network_tx_axis_tdata (tx_network_pipe_axis_tdata),
    .network_tx_axis_tkeep (tx_network_pipe_axis_tkeep),
    .network_tx_axis_tvalid(tx_network_pipe_axis_tvalid),
    .network_tx_axis_tready(tx_network_pipe_axis_tready),
    .network_tx_axis_tlast (tx_network_pipe_axis_tlast),
    .network_tx_axis_tuser (tx_network_pipe_axis_tuser),

    .network_rx_axis_tdata (rx_network_pipe_axis_tdata),
    .network_rx_axis_tkeep (rx_network_pipe_axis_tkeep),
    .network_rx_axis_tvalid(rx_network_pipe_axis_tvalid),
    .network_rx_axis_tlast (rx_network_pipe_axis_tlast),
    .network_rx_axis_tuser (rx_network_pipe_axis_tuser)
);


endmodule

