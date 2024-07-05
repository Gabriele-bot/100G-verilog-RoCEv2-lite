`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_throughput_eval (
    input wire clk,
    input wire rst,

    input wire        start_i,
    // Meta info
    /*
    input wire [23:0] start_rem_psn,
    input wire [23:0] loc_qpn,
    input wire [23:0] rem_qpn,
    */
    input wire [31:0] n_transfers,
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
    output wire [63:0] tot_time_wo_ack_avg,
    output wire [63:0] tot_time_avg,
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

  wire [63:0] begin_transfer_stamp;
  wire [63:0] finish_transfer_stamp;
  wire [63:0] ack_stamp;
  reg [63:0] ack_stamp_reg, ack_stamp_reg_del;

  wire [63:0] begin_transfer_stamp_fifo_out;
  wire [63:0] finish_transfer_stamp_fifo_out;
  wire [63:0] ack_stamp_fifo_out;

  reg  [63:0] begin_transfer_stamp_fifo_out_reg;
  reg  [63:0] finish_transfer_stamp_fifo_out_reg;

  wire [63:0] start_transfer_stamp;

  wire        begin_transfer_stamp_fifo_valid;
  wire        finish_transfer_stamp_fifo_valid;
  wire        ack_stamp_fifo_valid;

  wire        fifo_re_start;
  reg         fifo_re_start_reg;
  wire        fifo_re_last;
  reg         fifo_re_last_reg;

  wire        begin_transfer_stamp_we;
  wire        finish_transfer_stamp_we;
  wire        ack_stamp_we;
  reg ack_stamp_we_reg, ack_stamp_we_reg_del;

  wire [23:0] starting_psn;
  wire [23:0] last_psn;
  wire [23:0] ack_psn;
  reg [23:0] ack_psn_reg, ack_psn_reg_del;
  wire [31:0] rdma_length;

  wire [23:0] spsn_fifo_out;
  wire [23:0] lpsn_fifo_out;
  wire [23:0] ackpsn_fifo_out;

  reg  [23:0] spsn_fifo_out_reg;
  reg  [23:0] lpsn_fifo_out_reg;

  wire        spsn_fifo_valid;
  wire        lpsn_fifo_valid;
  wire        ackpsn_fifo_valid;

  wire [63:0] ctr_tot;
  wire [63:0] ctr_tot_out;

  wire        transfer_ongoing;

  wire [63:0] transfer_time_no_ack;
  wire [63:0] latency_inst;
  wire [63:0] transfer_time;

  reg         start_d;

  wire [31:0] sent_messages;
  wire [31:0] acked_messages;

  /*

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (64),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH (8),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_starts (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(begin_transfer_stamp),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(begin_transfer_stamp_we),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (begin_transfer_stamp_fifo_out),
      .m_axis_tvalid(begin_transfer_stamp_fifo_valid),
      .m_axis_tready(fifo_re_start)
  );

  axis_fifo #(
      .DEPTH      (1024),
      .DATA_WIDTH (64),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH (8),
      .ID_ENABLE  (0),
      .DEST_ENABLE(0),
      .USER_ENABLE(0),
      .USER_WIDTH (1),
      .FRAME_FIFO (0)
  ) fifo_ends (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(finish_transfer_stamp),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(finish_transfer_stamp_we),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (finish_transfer_stamp_fifo_out),
      .m_axis_tvalid(finish_transfer_stamp_fifo_valid),
      .m_axis_tready(fifo_re_last)
  );

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
      .s_axis_tdata(starting_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(begin_transfer_stamp_we),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (spsn_fifo_out),
      .m_axis_tvalid(spsn_fifo_valid),
      .m_axis_tready(fifo_re_start)
  );

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
      .s_axis_tdata(last_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(finish_transfer_stamp_we),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (lpsn_fifo_out),
      .m_axis_tvalid(lpsn_fifo_valid),
      .m_axis_tready(fifo_re_last)
  );
  

  wire [63:0] sent_message_stamp_fifo_out_data;
  wire        sent_message_stamp_fifo_out_valid;
  wire        sent_message_stamp_fifo_out_ready;
  reg         sent_message_stamp_fifo_out_ready_reg;

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
  ) fifo_sent_message_time_stamp (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(free_running_ctr),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(s_roce_tx_bth_valid),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (sent_message_stamp_fifo_out_data),
      .m_axis_tvalid(sent_message_stamp_fifo_out_valid),
      .m_axis_tready(sent_message_stamp_fifo_out_ready)
  );

  
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
  ) fifo_ack_message_time_stamp (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(free_running_ctr),
      .s_axis_tkeep({8{1'b1}}),
      .s_axis_tvalid(s_roce_rx_bth_valid),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (),
      .m_axis_tvalid(),
      .m_axis_tready(1'b0)
  );
  

  wire [23:0] sent_psn_fifo_out_data;
  wire sent_psn_fifo_out_valid;
  wire sent_psn_fifo_out_ready;
  reg sent_psn_fifo_out_ready_reg;

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
  ) fifo_sent_psn (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(s_roce_tx_bth_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(s_roce_tx_bth_valid),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (sent_psn_fifo_out_data),
      .m_axis_tvalid(sent_psn_fifo_out_valid),
      .m_axis_tready(sent_psn_fifo_out_ready)
  );
  
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
  ) fifo_ack_psn (
      .clk(clk),
      .rst(fifo_rst | rst),

      // AXI input
      .s_axis_tdata(s_roce_rx_bth_psn),
      .s_axis_tkeep({3{1'b1}}),
      .s_axis_tvalid(s_roce_rx_bth_valid),
      .s_axis_tuser(0),
      .s_axis_tlast(0),
      .s_axis_tdest(0),
      .s_axis_tid(0),

      // AXI output
      .m_axis_tdata (),
      .m_axis_tvalid(),
      .m_axis_tready(1'b0)
  );
  

  assign fifo_rst = (start_i & ~start_d) ? 1'b1 : 1'b0;
  */
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
  /*
  reg [31:0] sent_messages_reg;
  reg [63:0] begin_transfer_stamp_reg;
  reg [63:0] finish_transfer_stamp_reg;
  reg begin_transfer_stamp_we_reg;
  reg finish_transfer_stamp_we_reg;

  reg [23:0] starting_psn_reg;
  reg [23:0] last_psn_reg;

  reg [31:0] rdma_length_reg;

  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      sent_messages_reg            <= 32'd0;
      begin_transfer_stamp_reg     <= 64'd0;
      begin_transfer_stamp_we_reg  <= 1'b0;
      finish_transfer_stamp_we_reg <= 1'b0;
    end else begin
      if (s_roce_tx_bth_valid) begin //reset counter when start of packet is detected at the transmitter side
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_FIRST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD) begin
          starting_psn_reg <= s_roce_tx_bth_psn;
          begin_transfer_stamp_reg <= free_running_ctr;
          begin_transfer_stamp_we_reg <= 1'b1;
          if (sent_messages == 32'd0) begin
            begin_transfer_stamp_reg <= free_running_ctr;
          end
        end else begin
          begin_transfer_stamp_we_reg <= 1'b0;
        end
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD || s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST_IMD) begin
          last_psn_reg <= s_roce_tx_bth_psn;
          finish_transfer_stamp_reg <= free_running_ctr;
          finish_transfer_stamp_we_reg <= 1'b1;
          sent_messages_reg <= sent_messages_reg + 32'd1;
        end else begin
          finish_transfer_stamp_we_reg <= 1'b0;
        end
      end else begin
        begin_transfer_stamp_we_reg  <= 1'b0;
        finish_transfer_stamp_we_reg <= 1'b0;
      end
      if (s_roce_tx_reth_valid) begin
        rdma_length_reg <= s_roce_tx_reth_length;
      end
    end
  end
  
  assign sent_messages            = sent_messages_reg;
  assign begin_transfer_stamp     = begin_transfer_stamp_reg;
  assign begin_transfer_stamp_we  = begin_transfer_stamp_we_reg;
  assign finish_transfer_stamp    = finish_transfer_stamp_reg;
  assign finish_transfer_stamp_we = finish_transfer_stamp_we_reg;

  assign starting_psn             = starting_psn_reg;
  assign last_psn                 = last_psn_reg;
  */

  /*
  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      ack_stamp_we_reg <= 1'b0;
    end else if (s_roce_rx_bth_valid && s_roce_rx_aeth_valid) begin
      if (s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
        ack_psn_reg <= s_roce_rx_bth_psn;
        ack_stamp_reg <= free_running_ctr;
        ack_stamp_we_reg <= 1'b1;
      end else begin
        ack_stamp_we_reg <= 1'b0;
      end
    end else begin
      ack_stamp_we_reg <= 1'b0;
    end
    ack_stamp_we_reg_del <= ack_stamp_we_reg;
    ack_stamp_reg_del <= ack_stamp_reg;
    ack_psn_reg_del <= ack_psn_reg;
  end

  always @(posedge clk) begin
    if (spsn_fifo_valid && ack_stamp_we_reg_del && spsn_fifo_out == ack_psn_reg_del) begin
      fifo_re_start_reg <= 1'b1;
      spsn_fifo_out_reg <= spsn_fifo_out;
      begin_transfer_stamp_fifo_out_reg <= begin_transfer_stamp_fifo_out;
    end else begin
      fifo_re_start_reg <= 1'b0;
    end
  end

  assign fifo_re_start = fifo_re_start_reg;

  always @(posedge clk) begin
    if (lpsn_fifo_valid && ack_stamp_we_reg_del && lpsn_fifo_out == ack_psn_reg_del) begin
      fifo_re_last_reg <= 1'b1;
      lpsn_fifo_out_reg <= lpsn_fifo_out;
      finish_transfer_stamp_fifo_out_reg <= finish_transfer_stamp_fifo_out;
    end else begin
      fifo_re_last_reg <= 1'b0;
    end
  end

  assign fifo_re_last = fifo_re_last_reg;

  reg [31:0] acked_messages_reg;

  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      acked_messages_reg <= 32'd0;
    end else if (lpsn_fifo_out_reg == ack_psn_reg && ack_stamp_we_reg) begin
      if (acked_messages_reg < n_transfers) begin
        acked_messages_reg <= acked_messages_reg + 1;
      end else begin
        acked_messages_reg <= 32'd0;
      end
    end
  end
  */

  reg [63:0] transfer_time_no_ack_reg = 64'd0;
  reg [63:0] transfer_time_reg = 64'd0;

  reg [63:0] tot_time_wo_ack_avg_reg = 64'd0;
  reg [63:0] tot_time_avg_reg = 64'd0;
  reg [63:0] latency_tot_reg = 64'd0;
  reg [63:0] latency_first_reg = 64'd0;
  reg [63:0] latency_last_reg = 64'd0;
  /*
  reg bad_transfer;

  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      latency_tot_reg <= 64'd0;
      bad_transfer <= 1'b0;
    end else if (sent_message_stamp_fifo_out_valid && s_roce_rx_bth_valid && ~bad_transfer) begin
      if (sent_psn_fifo_out_valid && (sent_psn_fifo_out_data == s_roce_rx_bth_psn) && (s_roce_rx_aeth_syndrome[6:5] == 2'b00 )) begin
        latency_tot_reg <= latency_tot_reg + (free_running_ctr - sent_message_stamp_fifo_out_data);
        sent_message_stamp_fifo_out_ready_reg <= 1'b1;
        sent_psn_fifo_out_ready_reg <= 1'b1;
      end else begin
        bad_transfer <= 1'b1;
      end
    end
    if (sent_message_stamp_fifo_out_ready_reg) begin
      sent_message_stamp_fifo_out_ready_reg <= 1'b0;
    end
    if (sent_psn_fifo_out_ready_reg) begin
      sent_psn_fifo_out_ready_reg <= 1'b0;
    end
  end

  assign sent_message_stamp_fifo_out_ready = sent_message_stamp_fifo_out_ready_reg;
  assign sent_psn_fifo_out_ready = sent_psn_fifo_out_ready_reg;
  */

  reg [23:0] start_psn;
  reg [23:0] finish_psn;
  reg [63:0] start_time_stamp;
  reg [63:0] end_time_stamp;
  reg [63:0] end_time_stamp_acked;


  always @(posedge clk) begin
    if (start_i & ~start_d) begin
      transfer_time_reg        <= 64'd0;
      transfer_time_no_ack_reg <= 64'd0;
      latency_first_reg        <= 64'd0;
      latency_last_reg         <= 64'd0;
      start_psn                <= {24{1'b0}};
      finish_psn               <= {24{1'b0}};
      start_time_stamp         <= 64'd0;
      end_time_stamp           <= 64'd0;
      end_time_stamp_acked     <= 64'd0;
    end else begin
      if (s_roce_tx_bth_valid) begin
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_FIRST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD) begin
          start_psn        <= s_roce_tx_bth_psn;
          start_time_stamp <= free_running_ctr;
        end
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD || s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST_IMD) begin
          finish_psn               <= s_roce_tx_bth_psn;
          end_time_stamp           <= free_running_ctr;
          transfer_time_no_ack_reg <= free_running_ctr - start_time_stamp;
        end
      end
      if (s_roce_rx_bth_valid && s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
        if (s_roce_rx_bth_psn == start_psn) begin
          latency_first_reg <= free_running_ctr - start_time_stamp;
        end
        if (s_roce_rx_bth_psn == finish_psn) begin
          end_time_stamp_acked <= free_running_ctr;
          latency_last_reg     <= free_running_ctr - end_time_stamp;
          transfer_time_reg    <= free_running_ctr - start_time_stamp;
        end
      end
    end
  end

  assign tot_time_wo_ack_avg  = transfer_time_no_ack_reg;
  assign tot_time_avg         = transfer_time_reg;
  assign latency_first_packet = latency_first_reg;
  assign latency_last_packet  = latency_last_reg;

endmodule : RoCE_throughput_eval

`resetall
