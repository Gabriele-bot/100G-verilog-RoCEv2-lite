`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_latency_eval (
  input wire clk,
  input wire rst,

  input wire        start_i,
  //input wire [31:0] message_length,
  // RX 
  input wire        s_roce_rx_bth_valid,
  input wire [ 7:0] s_roce_rx_bth_op_code,
  input wire [15:0] s_roce_rx_bth_p_key,
  input wire [23:0] s_roce_rx_bth_psn,
  input wire [23:0] s_roce_rx_bth_dest_qp,
  input wire        s_roce_rx_bth_ack_req,
  // AETH
  input wire        s_roce_rx_aeth_valid,
  input wire [ 7:0] s_roce_rx_aeth_syndrome,
  input wire [23:0] s_roce_rx_aeth_msn,
  // RETH
  /*
   * TODO ADD 
   */

  // TX
  // BTH
  input  wire        s_roce_tx_bth_valid,
  input  wire [ 7:0] s_roce_tx_bth_op_code,
  input  wire [15:0] s_roce_tx_bth_p_key,
  input  wire [23:0] s_roce_tx_bth_psn,
  input  wire [23:0] s_roce_tx_bth_dest_qp,
  input  wire [23:0] s_roce_tx_bth_src_qp,
  input  wire        s_roce_tx_bth_ack_req,
  // AXIS
  input  wire        s_axis_tx_payload_valid,
  input  wire        s_axis_tx_payload_last,
  /*
   * TODO ADD 
   */
  // Performance results
  output wire [31:0] transfer_time_avg,
  output wire [31:0] transfer_time_moving_avg,
  output wire [31:0] transfer_time_inst,
  output wire [31:0] latency_avg,
  output wire [31:0] latency_moving_avg,
  output wire [31:0] latency_inst,
  // cfg
  input  wire [3:0] cfg_latency_avg_po2, // must be a power of 2 for easy division
  input  wire [4:0] cfg_throughput_avg_po2, // must be a power of 2 for easy division
  input  wire [23:0] monitor_loc_qpn
);

  import RoCE_params::*; // Imports RoCE parameters

  localparam RAM_ADD_WIDTH = 12; // 4096 points


  reg start_d;

  reg [31:0] free_running_ctr;
  reg [31:0] throughput_ctr;
  reg [31:0] throughput_out_sum;
  reg [31:0] throughput_out_sum_reg;
  reg [31:0] throughput_out_inst;
  reg [31:0] throughput_starting_point;
  reg [31:0] throughput_starting_point_inst;
  reg last_frame;
  reg [31:0] latency_out_sum;
  reg [31:0] latency_out_sum_reg;
  reg [31:0] latency_out_inst;
  reg [RAM_ADD_WIDTH-2:0]  measure_ctr;
  reg ren_del_1;
  reg ren_del_2;

  wire [12:0] n_transfer_latency_avg = 1 << cfg_latency_avg_po2;
  wire [16:0] n_transfer_throughput_avg = 1 << cfg_throughput_avg_po2;
  wire [31:0] ram_dout;

  reg latency_avg_valid;
  reg throughput_avg_valid;

  integer i;


  always @(posedge clk) begin
    start_d <= start_i;
  end

  always @(posedge clk) begin
    if (rst) begin // reset counter when start of packet is detected at the transmitter side
      free_running_ctr <= 32'd0;
    end else begin
      if (start_i & ~start_d) begin
        free_running_ctr <= 32'd0;
      end else begin
        free_running_ctr <= free_running_ctr + 32'd1;
      end
    end
  end

  simple_dpram #(
    .ADDR_WIDTH(RAM_ADD_WIDTH),
    .DATA_WIDTH(32),
    .STRB_WIDTH(1),
    .NPIPES(0)
  ) simple_dpram_instance (
    .clk(clk),
    .rst(rst),
    .waddr(s_roce_tx_bth_psn[RAM_ADD_WIDTH-1:0]),
    .raddr(s_roce_rx_bth_psn[RAM_ADD_WIDTH-1:0]),
    .din(free_running_ctr),
    .dout(ram_dout),
    .strb(1'b1),
    .ena(1),
    .ren(s_roce_rx_bth_valid && s_roce_rx_bth_dest_qp == monitor_loc_qpn),
    .wen(s_roce_tx_bth_valid && s_roce_tx_bth_src_qp == monitor_loc_qpn)
  );


  // round trip latency
  always @(posedge clk) begin
    if (rst) begin
      measure_ctr <= 0;
      ren_del_1 <= 1'b0;
      ren_del_2 <= 1'b0;
      latency_out_sum <= 32'd0;
    end else begin
      latency_avg_valid <= 1'b0;
      ren_del_1 <= s_roce_rx_bth_valid && s_roce_rx_bth_dest_qp == monitor_loc_qpn;
      ren_del_2 <= ren_del_1;
      if (ren_del_2) begin
        if (measure_ctr < n_transfer_latency_avg-1) begin
          measure_ctr <= measure_ctr + 1;
          latency_out_sum <= latency_out_sum + free_running_ctr - ram_dout;
        end else begin
          measure_ctr <= 0;
          latency_out_sum <= 32'd0;
          latency_out_sum_reg <= latency_out_sum + free_running_ctr - ram_dout;
          latency_avg_valid <= 1'b1;
        end
        latency_out_inst <= free_running_ctr - ram_dout;
      end
    end
  end

  assign latency_avg = latency_out_sum_reg >> cfg_latency_avg_po2;
  assign latency_inst = latency_out_inst;

  // throughput
  always @(posedge clk) begin
    if (rst) begin
      throughput_ctr <= 32'd0;
      throughput_out_sum <= 32'd0;
      last_frame <= 1'b0;
    end else begin
      throughput_avg_valid <= 1'b0;
      if (s_roce_tx_bth_valid && s_roce_tx_bth_src_qp == monitor_loc_qpn) begin
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_FIRST || s_roce_tx_bth_op_code == RC_SEND_FIRST    ||
        s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
        s_roce_tx_bth_op_code == RC_SEND_ONLY       || s_roce_tx_bth_op_code == RC_SEND_ONLY_IMD) begin
          if (throughput_ctr == 0) begin
            throughput_starting_point <= free_running_ctr;
            throughput_starting_point_inst <= free_running_ctr;
          end
        end
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
        s_roce_tx_bth_op_code == RC_SEND_LAST       || s_roce_tx_bth_op_code == RC_SEND_LAST_IMD       ||
        s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
        s_roce_tx_bth_op_code == RC_SEND_ONLY       || s_roce_tx_bth_op_code == RC_SEND_ONLY_IMD) begin
          last_frame <= 1'b1;
        end
      end
      if (last_frame && s_axis_tx_payload_valid && s_axis_tx_payload_last) begin
        last_frame <= 1'b0;
        if (throughput_ctr < n_transfer_throughput_avg-1) begin
          throughput_ctr <= throughput_ctr + 1;
        end else begin
          throughput_ctr <= 0;
          throughput_avg_valid <= 1'b1;
          throughput_out_sum_reg <= free_running_ctr - throughput_starting_point;
        end
        throughput_starting_point_inst <= free_running_ctr;
        throughput_out_inst <= free_running_ctr - throughput_starting_point_inst;
      end
    end
  end

  assign transfer_time_avg = throughput_out_sum_reg >> cfg_throughput_avg_po2;
  assign transfer_time_inst = throughput_out_inst;

  // moving averages

  reg [31:0] srl_trpt_ctr [7:0];
  reg [31:0] srl_lat_ctr [7:0];

  reg [34:0] srl_lat_ctr_moving_avg_reg, srl_lat_ctr_moving_avg_next;
  reg [34:0] srl_trpt_ctr_moving_avg_reg, srl_trpt_ctr_moving_avg_next;

  always @(*) begin

    srl_lat_ctr_moving_avg_next = 35'd0;
    srl_trpt_ctr_moving_avg_next = 35'd0;

    for (i=0; i<8; i=i+1) begin
      srl_lat_ctr_moving_avg_next = srl_lat_ctr_moving_avg_next + srl_lat_ctr[i];
      srl_trpt_ctr_moving_avg_next = srl_trpt_ctr_moving_avg_next + srl_trpt_ctr[i];
    end
    
  end
  

  always @(posedge clk) begin
    if (rst) begin
      for (i=0; i<8; i=i+1) begin
        srl_lat_ctr[i]  <= 35'd0;
        srl_trpt_ctr[i] <= 35'd0;
      end

    end else begin
      srl_lat_ctr_moving_avg_reg <= srl_lat_ctr_moving_avg_next;
      srl_trpt_ctr_moving_avg_reg <= srl_trpt_ctr_moving_avg_next;
      if (latency_avg_valid) begin
        srl_lat_ctr[0] <= latency_out_sum_reg;
        srl_lat_ctr[7:1] <= srl_lat_ctr[6:0];
      end
      if (throughput_avg_valid) begin
        srl_trpt_ctr[0] <= throughput_out_sum_reg;
        srl_trpt_ctr[7:1] <= srl_trpt_ctr[6:0];
      end
    end
  end

  assign latency_moving_avg       = srl_lat_ctr_moving_avg_reg[34:3];
  assign transfer_time_moving_avg = srl_trpt_ctr_moving_avg_reg[34:3];



endmodule

`resetall
