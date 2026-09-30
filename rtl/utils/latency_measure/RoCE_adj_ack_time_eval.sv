`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_adj_ack_time_eval #(
  N_PIPES = 4
) (
  input wire clk,
  input wire rst,

  input wire        s_roce_rx_bth_valid,
  input wire [23:0] s_roce_rx_bth_psn,
  input wire [23:0] s_roce_rx_bth_dest_qp,
  input wire [ 7:0] s_roce_rx_aeth_syndrome,

  // Performance results
  output wire [31:0] adj_ack_time,
  output wire        adj_ack_time_valid,
  // cfg
  input  wire [23:0] monitor_loc_qpn
);

  reg [31:0] free_running_ctr;
  reg [31:0] prev_free_running_ctr;
  reg [31:0] adj_ack_time_reg;
  reg        adj_ack_time_valid_reg;

  reg [N_PIPES-1:0] s_roce_rx_bth_valid_pipe;
  reg [23:0] s_roce_rx_bth_psn_pipe       [N_PIPES-1:0];
  reg [23:0] s_roce_rx_bth_dest_qp_pipe   [N_PIPES-1:0];
  reg [23:0] s_roce_rx_aeth_syndrome_pipe [N_PIPES-1:0];

  always @(posedge clk) begin
    if (rst) begin
      free_running_ctr       <= 32'd0;
      adj_ack_time_reg       <= 32'd0;
      adj_ack_time_valid_reg <= 1'b0;

      s_roce_rx_bth_valid_pipe     <= 0;
      s_roce_rx_bth_psn_pipe       <= '{default:0};
      s_roce_rx_bth_dest_qp_pipe   <= '{default:0};
      s_roce_rx_aeth_syndrome_pipe <= '{default:0};

    end else begin
      free_running_ctr <= free_running_ctr + 32'd1;

      s_roce_rx_bth_valid_pipe[N_PIPES-1:0]     <= {s_roce_rx_bth_valid_pipe[N_PIPES-2:0],     s_roce_rx_bth_valid};
      s_roce_rx_bth_psn_pipe[N_PIPES-1:0]       <= {s_roce_rx_bth_psn_pipe[N_PIPES-2:0],       s_roce_rx_bth_psn};
      s_roce_rx_bth_dest_qp_pipe[N_PIPES-1:0]   <= {s_roce_rx_bth_dest_qp_pipe[N_PIPES-2:0],   s_roce_rx_bth_dest_qp};
      s_roce_rx_aeth_syndrome_pipe[N_PIPES-1:0] <= {s_roce_rx_aeth_syndrome_pipe[N_PIPES-2:0], s_roce_rx_aeth_syndrome};

      if (s_roce_rx_bth_valid_pipe[N_PIPES-1] && s_roce_rx_bth_dest_qp_pipe[N_PIPES-1] == monitor_loc_qpn) begin
        prev_free_running_ctr  <= free_running_ctr;
        adj_ack_time_reg       <= free_running_ctr - prev_free_running_ctr;
        adj_ack_time_valid_reg <= 1'b1;
      end else begin
        adj_ack_time_valid_reg <= 1'b0;
      end
    end
  end

  assign adj_ack_time       = adj_ack_time_reg;
  assign adj_ack_time_valid = adj_ack_time_valid_reg;



endmodule

`resetall
