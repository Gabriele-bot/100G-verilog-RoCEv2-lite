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
    input  wire        s_roce_tx_bth_ack_req,
    // RETH           
    input  wire        s_roce_tx_reth_valid,
    input  wire [63:0] s_roce_tx_reth_v_addr,
    input  wire [31:0] s_roce_tx_reth_r_key,
    input  wire [31:0] s_roce_tx_reth_length,
    // AETH
    /*
     * TODO ADD 
     */
    // Performance results
    output wire [63:0] latency_first_packet,
    output wire [63:0] latency_last_packet
);

  localparam [7:0]
    RC_RDMA_WRITE_FIRST   = 8'h06,
    RC_RDMA_WRITE_MIDDLE  = 8'h07,
    RC_RDMA_WRITE_LAST    = 8'h08,
    RC_RDMA_WRITE_LAST_IMD= 8'h09,
    RC_RDMA_WRITE_ONLY    = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
    RC_RDMA_ACK           = 8'h11;

  wire        fifo_rst;

  reg  [63:0] free_running_ctr;



  reg         start_d;

  wire [63:0] start_stamp_fifo_out_data;
  wire        start_stamp_fifo_out_valid;
  wire        start_fifos_out_ready;
  wire        last_fifos_out_ready;

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (64),
      .KEEP_ENABLE(0),
      .KEEP_WIDTH (8),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_start_message_time_stamp (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(free_running_ctr),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(s_roce_tx_bth_valid & s_roce_tx_reth_valid),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (start_stamp_fifo_out_data),
      .m_axis_tvalid(start_stamp_fifo_out_valid),
      .m_axis_tready(start_fifos_out_ready)
  );

  wire [63:0] last_stamp_fifo_out_data;
  wire        last_stamp_fifo_out_valid;
  wire        last_psn_fifo_we;

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (64),
      .KEEP_ENABLE(0),
      .KEEP_WIDTH (8),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_last_message_time_stamp (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(free_running_ctr),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(last_psn_fifo_we),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (last_stamp_fifo_out_data),
      .m_axis_tvalid(last_stamp_fifo_out_valid),
      .m_axis_tready(last_fifos_out_ready)
  );



  wire [23:0] start_psn_fifo_out_data;
  wire        start_psn_fifo_out_valid;

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (24),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH (3),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_start_psn (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(s_roce_tx_bth_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(s_roce_tx_bth_valid & s_roce_tx_reth_valid), // RDMA WRITE FIRST or RDMA WRITE ONLY, start of packet
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (start_psn_fifo_out_data),
      .m_axis_tvalid(start_psn_fifo_out_valid),
      .m_axis_tready(start_fifos_out_ready)
  );

  wire [23:0] last_psn_fifo_out_data;
  wire        last_psn_fifo_out_valid;

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (24),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH (3),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_last_psn (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(s_roce_tx_bth_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(last_psn_fifo_we),  // RDMA WRITE FIRST or RDMA WRITE ONLY, start of packet
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (last_psn_fifo_out_data),
      .m_axis_tvalid(last_psn_fifo_out_valid),
      .m_axis_tready(last_fifos_out_ready)
  );

  assign last_psn_fifo_we = s_roce_tx_bth_valid & (s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
    s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD
  );

  assign start_fifos_out_ready = s_roce_rx_bth_valid & s_roce_rx_aeth_valid & (s_roce_rx_bth_psn == start_psn_fifo_out_data);
  assign last_fifos_out_ready  = s_roce_rx_bth_valid & s_roce_rx_aeth_valid & (s_roce_rx_bth_psn == last_psn_fifo_out_data);
  assign fifo_rst = start_i & ~start_d;

  always @(posedge clk) begin
    start_d <= start_i;
  end

  always @(posedge clk) begin
    if (rst) begin  // reset counter when start of packet is detected at the transmitter side
      free_running_ctr <= 64'd0;
    end else begin
      if (start_i & ~start_d) begin
        free_running_ctr <= 64'd0;
      end else begin
        free_running_ctr <= free_running_ctr + 64'd1;
      end
    end
  end


  reg [63:0] transfer_time_wo_ack_reg;
  reg [63:0] transfer_time_reg;

  reg [63:0] tot_time_wo_ack_reg;
  reg [63:0] tot_time_reg;
  reg [63:0] latency_tot_first_reg;
  reg [63:0] latency_tot_last_reg;
  reg [63:0] latency_first_reg;
  reg [63:0] latency_last_reg;



  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      latency_tot_first_reg    <= 64'd0;
      latency_tot_last_reg     <= 64'd0;
      transfer_time_reg        <= 64'd0;
      transfer_time_wo_ack_reg <= 64'd0;
      tot_time_wo_ack_reg      <= 64'd0;
      tot_time_reg             <= 64'd0;

      latency_first_reg        <= 64'd0;
      latency_last_reg         <= 64'd0;
    end else begin
      if (start_fifos_out_ready && start_stamp_fifo_out_valid) begin
        latency_tot_first_reg    <= latency_tot_first_reg + (free_running_ctr - start_stamp_fifo_out_data);
        latency_first_reg <= free_running_ctr - start_stamp_fifo_out_data;
      end
      if (last_fifos_out_ready && last_stamp_fifo_out_valid) begin
        latency_tot_last_reg     <= latency_tot_last_reg + (free_running_ctr - last_stamp_fifo_out_data);
        latency_last_reg <= free_running_ctr - last_stamp_fifo_out_data;
        tot_time_reg <= free_running_ctr;
        transfer_time_reg <= transfer_time_reg + (free_running_ctr - last_stamp_fifo_out_data);
      end
    end
  end

  assign latency_first_packet = latency_first_reg;
  assign latency_last_packet  = latency_last_reg;

endmodule

`resetall
