`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_qp_state_module #(
  parameter REM_ADDR_WIDTH = 32
) (
  input wire clk,
  input wire rst,

  input wire rst_qp,

  input wire [31:0] qp_init_dma_transfer,
  input wire [31:0] qp_init_r_key,
  input wire [23:0] qp_init_rem_qpn,
  input wire [23:0] qp_init_loc_qpn,
  input wire [23:0] qp_init_rem_psn,
  input wire [23:0] qp_init_loc_psn,
  input wire [31:0] qp_init_rem_ip_addr,
  input wire [63:0] qp_init_rem_addr,

  // TX BTH
  input  wire        s_roce_tx_bth_valid,
  output wire        s_roce_tx_bth_ready,
  input  wire [ 7:0] s_roce_tx_bth_op_code,
  input  wire [15:0] s_roce_tx_bth_p_key,
  input  wire [23:0] s_roce_tx_bth_psn,
  input  wire [23:0] s_roce_tx_bth_dest_qp,
  input  wire        s_roce_tx_bth_ack_req,
  // TX RETH
  // RETH           
  input  wire        s_roce_tx_reth_valid,
  input  wire [63:0] s_roce_tx_reth_v_addr,
  input  wire [31:0] s_roce_tx_reth_r_key,
  input  wire [31:0] s_roce_tx_reth_length,

  // RX BTH
  input  wire        s_roce_rx_bth_valid,
  output wire        s_roce_rx_bth_ready,
  input  wire [ 7:0] s_roce_rx_bth_op_code,
  input  wire [15:0] s_roce_rx_bth_p_key,
  input  wire [23:0] s_roce_rx_bth_psn,
  input  wire [23:0] s_roce_rx_bth_dest_qp,
  input  wire        s_roce_rx_bth_ack_req,
  // RX AETH                  
  input  wire        s_roce_rx_aeth_valid,
  output wire        s_roce_rx_aeth_ready,
  input  wire [ 7:0] s_roce_rx_aeth_syndrome,
  input  wire [23:0] s_roce_rx_aeth_msn,


  output wire [23:0] last_acked_psn,
  output wire [23:0] last_nacked_psn,
  output wire stop_transfer



);

  /*
+--------------------------------------+
|            QP STATE CONTEXT          |
+--------------------------------------+
 QP State                    3 bits
 Reserved                    5 bits
 Remote IPAddr               4 octets
 Remote QPN                  3 octets
 Local  QPN                  3 octets
 Remote PSN                  3 octets
 Local PSN                   3 octets
 Virtual Addr                8 octets
 R_key                       4 octets
 Reserved                    3 octets
 ---------------------------------------
 Total                       32 octets (256 bits)
  */

  localparam [9:0] QP_CONTEXT_LENGTH = 1+4+3+3+3+3+8+4+3;

  localparam [7:0]
  RC_RDMA_WRITE_FIRST   = 8'h06,
  RC_RDMA_WRITE_MIDDLE  = 8'h07,
  RC_RDMA_WRITE_LAST    = 8'h08,
  RC_RDMA_WRITE_LAST_IMD= 8'h09,
  RC_RDMA_WRITE_ONLY    = 8'h0A,
  RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
  RC_RDMA_ACK           = 8'h11,
  ROCE_CNP              = 8'h81;

  localparam [2:0]  STATE_IDLE      = 3'd0,
                    STATE_OPEN_QP   = 3'd1,
                    STATE_UPDATE_QP = 3'd2,
                    STATE_CLOSE_QP  = 3'd3;

  reg [QP_CONTEXT_LENGTH*8-1 :0] current_qp_contex, next_qp_contex;

  reg [2:0] state_reg = STATE_IDLE, state_next;


  reg [31:0] dma_transfer_reg;
  reg [31:0] r_key_reg;
  reg [23:0] rem_qpn_reg;
  reg [23:0] loc_qpn_reg;
  reg [23:0] rem_psn_reg;
  reg [23:0] loc_psn_reg;
  reg [31:0] rem_ip_addr_reg;
  reg [63:0] rem_addr_reg;

  reg [REM_ADDR_WIDTH-1:0] rem_addr_offset_reg;

  reg [23:0] last_psn;
  reg [23:0] last_acked_psn_reg;
  reg [23:0] last_nacked_psn_reg;

  reg udapte_qp_state_reg;
  reg stop_transfer_reg;

  // TX side 
  always @(posedge clk) begin
    if (rst_qp) begin
      dma_transfer_reg    <= qp_init_dma_transfer;
      r_key_reg           <= qp_init_r_key;
      rem_qpn_reg         <= qp_init_rem_qpn;
      rem_psn_reg         <= qp_init_rem_psn;
      rem_ip_addr_reg     <= qp_init_rem_ip_addr;
      rem_addr_reg        <= qp_init_rem_addr;
      rem_addr_offset_reg <= {REM_ADDR_WIDTH{1'b0}};
      last_psn            <= 24'd0;
    end else begin

      /*
      if (s_roce_tx_reth_valid && s_roce_rx_bth_valid && s_roce_tx_bth_dest_qp == rem_qpn_reg) begin
        rem_addr_reg <= s_roce_tx_reth_v_addr;
        rem_addr_offset_reg <= s_roce_tx_reth_length;
      end
      */

      if (s_roce_tx_bth_valid && s_roce_tx_bth_dest_qp == rem_qpn_reg) begin
        rem_psn_reg <= s_roce_tx_bth_psn;
        if (s_roce_tx_reth_valid) begin
          rem_addr_offset_reg <= dma_transfer_reg[REM_ADDR_WIDTH-1:0];
        end
        if (s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST || s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY ||
        s_roce_tx_bth_op_code == RC_RDMA_WRITE_ONLY_IMD || s_roce_tx_bth_op_code == RC_RDMA_WRITE_LAST_IMD
        ) begin
          last_psn <= s_roce_tx_bth_psn;
          rem_addr_offset_reg <= dma_transfer_reg[REM_ADDR_WIDTH-1:0];
          rem_addr_reg[REM_ADDR_WIDTH-1:0] <= rem_addr_reg[REM_ADDR_WIDTH-1:0] + rem_addr_offset_reg[REM_ADDR_WIDTH-1:0];
          rem_addr_reg[63:REM_ADDR_WIDTH] <= rem_addr_reg[63:REM_ADDR_WIDTH];
          udapte_qp_state_reg <= 1'b1;
        end
      end else begin
        udapte_qp_state_reg <= 1'b0;
      end
    end
  end

  // RX side 
  always @(posedge clk) begin
    if (rst_qp) begin
      loc_qpn_reg         <= qp_init_loc_qpn;
      loc_psn_reg         <= qp_init_loc_psn;
      last_acked_psn_reg  <= qp_init_rem_psn;
      last_nacked_psn_reg <= qp_init_rem_psn;
    end else begin
      if (s_roce_rx_bth_valid && s_roce_rx_bth_dest_qp == loc_qpn_reg) begin
        if (s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
          last_acked_psn_reg <= s_roce_rx_bth_psn;
          stop_transfer_reg  <= 1'b0;
        end else if (s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] != 2'b00) begin
          last_nacked_psn_reg <= s_roce_rx_bth_psn;
          stop_transfer_reg   <= 1'b1;
        end
      end else begin
        stop_transfer_reg <= 1'b0;
      end
    end
  end


  assign last_acked_psn  = last_acked_psn_reg;
  assign last_nacked_psn = last_nacked_psn_reg;
  assign stop_transfer   = stop_transfer_reg;

endmodule

`resetall
