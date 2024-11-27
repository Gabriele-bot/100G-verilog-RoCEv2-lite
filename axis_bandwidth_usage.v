`resetall `timescale 1ns / 1ps `default_nettype none

module axis_bandwidth_usage #(
    parameter WINDOW_WIDTH = 16
) (
    input  wire                     clk,
    input  wire                     rst,
    //--------------------------------------------
    input  wire                     s_axis_tvalid,
    input  wire                     m_axis_tready,
    //--------------------------------------------
    output wire [WINDOW_WIDTH -1:0] n_valid_up,
    output wire [WINDOW_WIDTH -1:0] n_ready_up,
    output wire [WINDOW_WIDTH -1:0] n_both_up

);

  reg [WINDOW_WIDTH -1:0] valid_ctr;
  reg [WINDOW_WIDTH -1:0] ready_ctr;
  reg [WINDOW_WIDTH -1:0] both_ctr;
  reg [WINDOW_WIDTH -1:0] clk_ctr;

  reg [WINDOW_WIDTH -1:0] valid_ctr_srl[7:0];
  reg [WINDOW_WIDTH -1:0] ready_ctr_srl[7:0];
  reg [WINDOW_WIDTH -1:0] both_ctr_srl [7:0];

  always @(posedge clk) begin
    if (rst) begin
      clk_ctr   <= {WINDOW_WIDTH{1'b0}};
      valid_ctr <= {WINDOW_WIDTH{1'b0}};
      ready_ctr <= {WINDOW_WIDTH{1'b0}};
      both_ctr  <= {WINDOW_WIDTH{1'b0}};
    end else begin
      clk_ctr <= clk_ctr + 1;
      if (clk_ctr == 0) begin
        valid_ctr <= {WINDOW_WIDTH{1'b0}};
        ready_ctr <= {WINDOW_WIDTH{1'b0}};
        both_ctr  <= {WINDOW_WIDTH{1'b0}};
      end else begin
        if (s_axis_tvalid) begin
          valid_ctr <= valid_ctr + 1;
        end
        if (m_axis_tready) begin
          ready_ctr <= ready_ctr + 1;
        end
        if (s_axis_tvalid && m_axis_tready) begin
          both_ctr <= both_ctr + 1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (clk_ctr == {WINDOW_WIDTH{1'b0}}) begin
      valid_ctr_srl <= {valid_ctr_srl[6:0], valid_ctr};
      ready_ctr_srl <= {ready_ctr_srl[6:0], ready_ctr};
      both_ctr_srl  <= {both_ctr_srl[6:0], both_ctr};
    end
  end

  reg [WINDOW_WIDTH + 3-1 : 0] valid_ctr_avg_var;
  reg [WINDOW_WIDTH + 3-1 : 0] ready_ctr_avg_var;
  reg [WINDOW_WIDTH + 3-1 : 0] both_ctr_avg_var;

 
  // Average
  always @(posedge clk) begin
    valid_ctr_avg_var <= valid_ctr_srl[7] + valid_ctr_srl[6] + valid_ctr_srl[5] +
             valid_ctr_srl[4]+ valid_ctr_srl[3]+ valid_ctr_srl[2]+ valid_ctr_srl[1]+ valid_ctr_srl[0];
    ready_ctr_avg_var <= ready_ctr_srl[7] + ready_ctr_srl[6] + ready_ctr_srl[5] +
             ready_ctr_srl[4]+ ready_ctr_srl[3]+ ready_ctr_srl[2]+ ready_ctr_srl[1]+ ready_ctr_srl[0];
    both_ctr_avg_var  <= both_ctr_avg_var[7] + both_ctr_avg_var[6] + both_ctr_avg_var[5] + 
            both_ctr_avg_var[4]+ both_ctr_avg_var[3]+ both_ctr_avg_var[2]+ both_ctr_avg_var[1]+ both_ctr_avg_var[0];
  end

  assign n_valid_up = valid_ctr_avg_var[WINDOW_WIDTH+3-1:3];
  assign n_ready_up = ready_ctr_avg_var[WINDOW_WIDTH+3-1:3];
  assign n_both_up  = both_ctr_avg_var[WINDOW_WIDTH+3-1:3];


endmodule

`resetall
