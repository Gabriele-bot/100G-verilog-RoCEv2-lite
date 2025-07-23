`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_qp_state_module #(
  parameter MAX_QUEUE_PAIRS          = 4, // not working yet
  parameter MAX_WORK_REQUEST_ENTRIES = 16,
  parameter REM_ADDR_WIDTH           = 32
) (
  input wire clk,
  input wire rst,

  input wire rst_qp,

  input wire        qp_init_valid,
  input wire [2 :0] qp_init_req_type,
  input wire [31:0] qp_init_r_key,
  input wire [23:0] qp_init_rem_qpn,
  input wire [23:0] qp_init_loc_qpn,
  input wire [23:0] qp_init_rem_psn,
  input wire [23:0] qp_init_loc_psn,
  input wire [31:0] qp_init_rem_ip_addr,
  input wire [63:0] qp_init_rem_addr,

  output wire       qp_init_status_valid,
  output wire [1:0] qp_init_status,

  // Close qp
  input wire        qp_close_valid,
  input wire [23:0] qp_close_loc_qpn,

  // Output QP contetext
  input wire         qp_context_req,
  input wire [23:0]  qp_local_qpn_req,

  output wire        qp_req_context_valid,
  output wire [2 :0] qp_req_state,
  output wire [31:0] qp_req_r_key,
  output wire [23:0] qp_req_rem_qpn,
  output wire [23:0] qp_req_loc_qpn,
  output wire [23:0] qp_req_rem_psn,
  output wire [23:0] qp_req_loc_psn,
  output wire [31:0] qp_req_rem_ip_addr,
  output wire [63:0] qp_req_rem_addr,

  // SPY QP state
  input wire         qp_context_spy,
  input wire [23:0]  qp_local_qpn_spy,

  output wire        qp_spy_context_valid,
  output wire [2 :0] qp_spy_state,
  output wire [31:0] qp_spy_r_key,
  output wire [23:0] qp_spy_rem_qpn,
  output wire [23:0] qp_spy_loc_qpn,
  output wire [23:0] qp_spy_rem_psn,
  output wire [23:0] qp_spy_rem_acked_psn,
  output wire [23:0] qp_spy_loc_psn,
  output wire [31:0] qp_spy_rem_ip_addr,
  output wire [63:0] qp_spy_rem_addr,
  output wire [7 :0] qp_spy_syndrome,

  input wire        s_dma_meta_valid ,
  input wire [31:0] s_meta_dma_length,
  input wire [23:0] s_meta_rem_qpn   ,
  input wire [23:0] s_meta_loc_qpn   ,
  input wire [23:0] s_meta_rem_psn   ,

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
  output wire        stop_transfer,

  // Config
  input  wire [2:0] pmtu
);

  /*
  +------------------+
  |    PMTU TABLE    |
  +--------------+---+
  | IBV_MTU_256  | 0 |
  | IBV_MTU_512  | 1 |
  | IBV_MTU_1024 | 2 |
  | IBV_MTU_2048 | 3 |
  | IBV_MTU_4096 | 4 |
  +--------------+---+
  */

  /*
 TODO
 Add proper QP state managment
 */

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

  import RoCE_params::*; // Imports RoCE parameters

  localparam [2:0]
  QP_STATE_RESET    = 3'd0,
  QP_STATE_INIT     = 3'd1,
  QP_STATE_RTR      = 3'd2,
  QP_STATE_RTS      = 3'd3,
  QP_STATE_SQ_DRAIN = 3'd4,
  QP_STATE_SQ_ERROR = 3'd5,
  QP_STATE_ERROR    = 3'd6;

  localparam [9:0] QP_CONTEXT_LENGTH = 1+4+3+3+3+3+8+4+3;

  localparam QP_STATE_OFFSET    = 0;
  localparam REM_IPADDR_OFFSET  = 8;
  localparam REM_QPN_OFFSET     = 40;
  localparam LOC_QPN_OFFSET     = 64;
  localparam REM_PSN_OFFSET     = 88;
  localparam LOC_PSN_OFFSET     = 112;
  localparam VADDR_OFFSET       = 136;
  localparam RKEY_OFFSET        = 200;
  localparam SYNDROME_OFFSET    = 232;
  localparam RESERVED_OFFSET    = 240;

  localparam [2:0]
  STATE_IDLE          = 3'd0,
  STATE_OPEN_QP       = 3'd1,
  STATE_MODIFY_QP_RTS = 3'd2,
  STATE_UPDATE_QP     = 3'd3,
  STATE_ERROR_QP      = 3'd4,
  STATE_CLOSE_QP      = 3'd5;

  reg [QP_CONTEXT_LENGTH*8-1 :0] qp_contex [MAX_QUEUE_PAIRS-1:0];
  reg [24-1 :0] qp_rem_acked_psn_mem [MAX_QUEUE_PAIRS-1:0];
  reg [MAX_QUEUE_PAIRS_WIDTH-1:0] qp_init_ptr_reg = 0, qp_init_ptr_next;
  reg [MAX_QUEUE_PAIRS_WIDTH-1:0] qp_update_ptr_reg, qp_update_ptr_next;
  reg [MAX_QUEUE_PAIRS_WIDTH-1:0] qp_close_ptr_reg, qp_close_ptr_next;
  reg [MAX_QUEUE_PAIRS_WIDTH-1:0] qp_ptr_reg, qp_ptr_next;

  reg store_qp_info;

  reg [2:0] state_reg = STATE_IDLE, state_next;


  reg [31:0] dma_transfer_reg;
  reg [31:0] r_key_reg;
  reg [23:0] rem_qpn_reg;
  reg [23:0] loc_qpn_reg;
  reg [23:0] rem_psn_reg;
  reg [23:0] loc_psn_reg;
  reg [31:0] rem_ip_addr_reg;
  reg [63:0] rem_addr_reg;

  reg [31:0] qp_init_r_key_reg;
  reg [23:0] qp_init_rem_qpn_reg;
  reg [23:0] qp_init_loc_qpn_reg;
  reg [23:0] qp_init_rem_psn_reg;
  reg [23:0] qp_init_loc_psn_reg;
  reg [31:0] qp_init_rem_ip_addr_reg;
  reg [63:0] qp_init_rem_addr_reg;


  reg [7:0] qp_aeth_syndrome_reg, qp_aeth_syndrome_next;
  reg [23:0] qp_update_rem_psn_reg = 0, qp_update_rem_psn_next;
  reg [23:0] qp_close_rem_psn_reg = 0, qp_close_rem_psn_next;

  reg [REM_ADDR_WIDTH-1:0] rem_addr_offset_reg;

  reg [QP_CONTEXT_LENGTH*8-1 :0] qp_req_context, qp_req_context_pipe;
  reg [1:0] qp_req_context_valid_pipes;

  reg [QP_CONTEXT_LENGTH*8-1 :0] qp_spy_context, qp_spy_context_pipe;
  reg [1:0] qp_spy_context_valid_pipes;
  reg [24-1:0] qp_spy_rem_acked_psn_reg;

  reg [23:0] last_psn;
  reg [23:0] last_acked_psn_reg;
  reg [23:0] last_nacked_psn_reg;

  reg stop_transfer_reg;

  reg qp_open_status_valid;
  reg error_qp_request;
  reg error_invalid_qp_req;
  reg error_invalid_qp_spy;

  reg [3:0] pmtu_shift;
  reg [11:0] length_pmtu_mask;

  /*
  WORKAROUND to to have only one qp in RTS at the same time
  */
  reg        qp_active;
  reg        qp_active_del;
  reg [23:0] curr_open_qpn;

  always @(posedge clk) begin
    if (rst) begin
      curr_open_qpn <= 24'd0;
      qp_active     <= 1'b0;
    end else begin
      if (qp_init_valid && qp_init_req_type == REQ_MODIFY_QP_RTS && !qp_active) begin
        curr_open_qpn <= qp_init_loc_qpn;
        qp_active     <= 1'b1;
      end else if (qp_init_valid && qp_init_req_type == REQ_CLOSE_QP && qp_active) begin
        curr_open_qpn <= 24'd0;
        qp_active     <= 1'b0;
      end
    end
    qp_active_del <= qp_active;
  end
  /*
  WORKAROUND to to have only one qp in RTS at the same time
  */

  integer i;

  initial begin
    for(i = 0; i < MAX_QUEUE_PAIRS; i = i + 1) begin
      qp_contex[i] <= {QP_CONTEXT_LENGTH*8{1'b0}}; // all QP in RESET STATE
      qp_rem_acked_psn_mem[i] <= 24'd0;
    end
  end


  always @(posedge clk) begin
    case (pmtu)
      3'd0: begin
        pmtu_shift <= 4'd8;
        length_pmtu_mask = {4'h0, {8{1'b1}}};
      end
      3'd1: begin
        pmtu_shift <= 4'd9;
        length_pmtu_mask = {3'h0, {9{1'b1}}};
      end
      3'd2: begin
        pmtu_shift <= 4'd10;
        length_pmtu_mask = {2'h0, {10{1'b1}}};
      end
      3'd3: begin
        pmtu_shift <= 4'd11;
        length_pmtu_mask = {1'h0, {11{1'b1}}};
      end
      3'd4: begin
        pmtu_shift <= 4'd12;
        length_pmtu_mask = {12{1'b1}};
      end
    endcase
  end



  // QP state
  always @* begin

    state_next                     = STATE_IDLE;

    qp_init_ptr_next   = qp_init_ptr_reg;
    qp_update_ptr_next = qp_update_ptr_reg;
    qp_close_ptr_next  = qp_close_ptr_reg;

    qp_aeth_syndrome_next = qp_aeth_syndrome_reg;

    qp_update_rem_psn_next = qp_update_rem_psn_reg;

    store_qp_info = 1'b0;

    case (state_reg)
      STATE_IDLE: begin
        if (qp_close_valid && (qp_close_loc_qpn[23:8] == 16'd1 && qp_close_loc_qpn[7:MAX_QUEUE_PAIRS_WIDTH] == 0)) begin
          //  QP goes to error state, some errors occoured during transfer (e.g. transmission timeout)
          qp_aeth_syndrome_next = {1'b1, 2'b00, 5'b11111}; // 8'h9F
          qp_close_ptr_next = qp_close_loc_qpn[MAX_QUEUE_PAIRS_WIDTH-1:0];
          state_next = STATE_ERROR_QP;
        end else if (s_dma_meta_valid) begin
          if (s_meta_loc_qpn[23:8] == 16'd1 && s_meta_loc_qpn[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
            if (|(s_meta_dma_length[11:0] & length_pmtu_mask) == 1'b0) begin
              qp_update_rem_psn_next = s_meta_rem_psn + (s_meta_dma_length >> pmtu_shift);
            end else begin
              qp_update_rem_psn_next = s_meta_rem_psn + (s_meta_dma_length >> pmtu_shift) + 1;
            end
            qp_update_ptr_next = s_meta_loc_qpn[MAX_QUEUE_PAIRS_WIDTH-1:0];
            state_next = STATE_UPDATE_QP;
          end
        end else if (qp_init_valid) begin
          store_qp_info = 1'b1;
          // local qp must be between 256 and 256+MAX_QP
          if (qp_init_loc_qpn[23:8] == 16'd1 && qp_init_loc_qpn[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
            case(qp_init_req_type)

              REQ_OPEN_QP: begin
                qp_init_ptr_next = qp_init_loc_qpn[MAX_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_OPEN_QP;
              end
              REQ_MODIFY_QP_RTS:begin
                qp_update_ptr_next = qp_init_loc_qpn[MAX_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_MODIFY_QP_RTS;
              end
              REQ_CLOSE_QP:begin
                qp_aeth_syndrome_next = 8'd0;
                qp_close_ptr_next = qp_init_loc_qpn[MAX_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_CLOSE_QP;
              end
            endcase
          end
        end

        if (s_roce_rx_bth_valid & s_roce_rx_aeth_valid) begin

          // local qp must be between 256 and 256+MAX_QP
          if (s_roce_rx_bth_dest_qp[23:8] == 16'd1 && s_roce_rx_bth_dest_qp[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
            // QP goes to error state if NA received and NAK code not PSN seq error
            if (s_roce_rx_bth_op_code == RC_RDMA_ACK &&  s_roce_rx_aeth_syndrome[6:5] == 2'b11 && s_roce_rx_aeth_syndrome[4:0] != 5'b00000) begin
              qp_aeth_syndrome_next = s_roce_rx_aeth_syndrome;
              qp_close_ptr_next = s_roce_rx_bth_dest_qp[MAX_QUEUE_PAIRS_WIDTH-1:0];
              state_next = STATE_ERROR_QP;
            end
          end
        end

      end
      STATE_OPEN_QP : begin
        state_next = STATE_IDLE;
      end
      STATE_MODIFY_QP_RTS : begin
        state_next = STATE_IDLE;
      end
      STATE_UPDATE_QP: begin
        state_next = STATE_IDLE;
      end
      STATE_ERROR_QP: begin
        state_next = STATE_IDLE;
      end
      STATE_CLOSE_QP: begin
        state_next   = STATE_IDLE;
      end
    endcase

  end

  // ACK'ED PSN memory
  always @(posedge clk) begin

    // write first, else read
    if (s_roce_rx_bth_valid & s_roce_rx_aeth_valid) begin
      // local qp must be between 256 and 256+MAX_QP
      if (s_roce_rx_bth_dest_qp[23:8] == 16'd1 && s_roce_rx_bth_dest_qp[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
        // Close QP if NA received and NAK code not PSN seq error
        if (s_roce_rx_bth_op_code == RC_RDMA_ACK &&  s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
          qp_rem_acked_psn_mem[s_roce_rx_bth_dest_qp[MAX_QUEUE_PAIRS_WIDTH-1:0]] <= s_roce_rx_bth_psn;
        end
      end
    end else if (qp_context_spy) begin
      if (qp_local_qpn_spy[23:8] == 16'd1 && qp_local_qpn_spy[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_spy_rem_acked_psn_reg <= qp_rem_acked_psn_mem[qp_local_qpn_spy[MAX_QUEUE_PAIRS_WIDTH-1:0]];
      end
    end
  end

  always @(posedge clk) begin

    // Read request, spy port has low priority
    if (qp_context_req) begin
      qp_spy_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_spy          <= 1'b0;
      if (qp_local_qpn_req[23:8] == 16'd1 && qp_local_qpn_req[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_req_context <= qp_contex[qp_local_qpn_req[MAX_QUEUE_PAIRS_WIDTH-1:0]];
        qp_req_context_valid_pipes[0] <= 1'b1;
        error_invalid_qp_req          <= 1'b0;
      end else begin
        qp_req_context_valid_pipes[0] <= 1'b0;
        error_invalid_qp_req          <= 1'b1;
      end
    end else if (qp_context_spy) begin
      qp_req_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_req          <= 1'b0;
      if (qp_local_qpn_spy[23:8] == 16'd1 && qp_local_qpn_spy[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_spy_context <= qp_contex[qp_local_qpn_spy[MAX_QUEUE_PAIRS_WIDTH-1:0]];
        qp_spy_context_valid_pipes[0] <= 1'b1;
        error_invalid_qp_spy          <= 1'b0;
      end else begin
        qp_spy_context_valid_pipes[0] <= 1'b0;
        error_invalid_qp_spy          <= 1'b1;
      end
    end else begin
      qp_req_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_req          <= 1'b0;

      qp_spy_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_spy          <= 1'b0;
    end

    qp_req_context_pipe <= qp_req_context;
    qp_req_context_valid_pipes[1] <= qp_req_context_valid_pipes[0];

    qp_spy_context_pipe <= qp_spy_context;
    qp_spy_context_valid_pipes[1] <= qp_spy_context_valid_pipes[0];

    qp_open_status_valid <= 1'b0;
    error_qp_request <= 1'b0;
    // Write
    case (state_reg)
      STATE_IDLE: begin
        error_qp_request     <= 1'b0;
        qp_open_status_valid <= 1'b0;
      end
      STATE_OPEN_QP: begin
        // check if QP is RESET state
        if (qp_contex[qp_init_ptr_reg][QP_STATE_OFFSET   +: 3]  == QP_STATE_RESET) begin
          qp_contex[qp_init_ptr_reg][QP_STATE_OFFSET   +: 3 ]  <= QP_STATE_INIT;
          qp_contex[qp_init_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_init_rem_ip_addr_reg;
          qp_contex[qp_init_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_init_rem_qpn_reg;
          qp_contex[qp_init_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_init_loc_qpn_reg;
          qp_contex[qp_init_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_init_rem_psn_reg;
          qp_contex[qp_init_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_init_loc_psn_reg;
          qp_contex[qp_init_ptr_reg][VADDR_OFFSET      +: 64] <= qp_init_rem_addr_reg;
          qp_contex[qp_init_ptr_reg][RKEY_OFFSET       +: 32] <= qp_init_r_key_reg;
          qp_contex[qp_init_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 8'd0;
          qp_contex[qp_init_ptr_reg][RESERVED_OFFSET   +: 16] <= 16'd0;

          error_qp_request     <= 1'b0;
          qp_open_status_valid <= 1'b1;
        end else begin
          error_qp_request     <= 1'b1;
          qp_open_status_valid <= 1'b1;
        end
      end
      STATE_MODIFY_QP_RTS: begin
        // check if QP is RESET state
        if (qp_contex[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3]  == QP_STATE_INIT) begin
          if (!qp_active_del) begin
            qp_contex[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RTS;
            qp_contex[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_contex[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32];
            qp_contex[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24];
            qp_contex[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24];
            qp_contex[qp_update_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][REM_PSN_OFFSET    +: 24];
            qp_contex[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24];
            qp_contex[qp_update_ptr_reg][VADDR_OFFSET      +: 64] <= qp_contex[qp_update_ptr_reg][VADDR_OFFSET      +: 64];
            qp_contex[qp_update_ptr_reg][RKEY_OFFSET       +: 32] <= qp_contex[qp_update_ptr_reg][RKEY_OFFSET       +: 32];
            qp_contex[qp_update_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_contex[qp_update_ptr_reg][SYNDROME_OFFSET   +: 8 ];
            qp_contex[qp_update_ptr_reg][RESERVED_OFFSET   +: 16] <= qp_contex[qp_update_ptr_reg][RESERVED_OFFSET   +: 16];

            error_qp_request     <= 1'b0;
            qp_open_status_valid <= 1'b1;
          end else begin
            error_qp_request     <= 1'b1;
            qp_open_status_valid <= 1'b1;
          end
        end else begin
          error_qp_request     <= 1'b1;
          qp_open_status_valid <= 1'b1;
        end
      end
      STATE_UPDATE_QP: begin
        qp_contex[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= qp_contex[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3] ;
        qp_contex[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_contex[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32];
        qp_contex[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24];
        qp_contex[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24];
        qp_contex[qp_update_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_update_rem_psn_reg;
        qp_contex[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_contex[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24];
        qp_contex[qp_update_ptr_reg][VADDR_OFFSET      +: 64] <= qp_contex[qp_update_ptr_reg][VADDR_OFFSET      +: 64];
        qp_contex[qp_update_ptr_reg][RKEY_OFFSET       +: 32] <= qp_contex[qp_update_ptr_reg][RKEY_OFFSET       +: 32];
        qp_contex[qp_update_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 8'd0;
      end
      STATE_ERROR_QP: begin
        qp_contex[qp_close_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_ERROR;
        qp_contex[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_contex[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32];
        qp_contex[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24];
        qp_contex[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24];
        qp_contex[qp_close_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
        qp_contex[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24];
        qp_contex[qp_close_ptr_reg][VADDR_OFFSET      +: 64] <= qp_contex[qp_close_ptr_reg][VADDR_OFFSET      +: 64];
        qp_contex[qp_close_ptr_reg][RKEY_OFFSET       +: 32] <= qp_contex[qp_close_ptr_reg][RKEY_OFFSET       +: 32];
        qp_contex[qp_close_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;
      end
      STATE_CLOSE_QP: begin
        if (qp_contex[qp_close_ptr_reg][QP_STATE_OFFSET   +: 3]  != QP_STATE_RESET) begin
          qp_contex[qp_close_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RESET;
          qp_contex[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_contex[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32];
          qp_contex[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24];
          qp_contex[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24];
          qp_contex[qp_close_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
          qp_contex[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_contex[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24];
          qp_contex[qp_close_ptr_reg][VADDR_OFFSET      +: 64] <= qp_contex[qp_close_ptr_reg][VADDR_OFFSET      +: 64];
          qp_contex[qp_close_ptr_reg][RKEY_OFFSET       +: 32] <= qp_contex[qp_close_ptr_reg][RKEY_OFFSET       +: 32];
          qp_contex[qp_close_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;

          error_qp_request     <= 1'b0;
          qp_open_status_valid <= 1'b1;
        end else begin
          error_qp_request     <= 1'b1;
          qp_open_status_valid <= 1'b1;
        end
      end
      default: begin
        qp_open_status_valid <= 1'b0;
        error_qp_request     <= 1'b0;
      end
    endcase
  end

  always @(posedge clk) begin

    state_reg       <= state_next;

    qp_init_ptr_reg   <= qp_init_ptr_next;
    qp_update_ptr_reg <= qp_update_ptr_next;
    qp_close_ptr_reg  <= qp_close_ptr_next;

    qp_aeth_syndrome_reg <= qp_aeth_syndrome_next;
    qp_update_rem_psn_reg <= qp_update_rem_psn_next;

    if (store_qp_info) begin
      qp_init_rem_ip_addr_reg  <= qp_init_rem_ip_addr;
      qp_init_rem_qpn_reg      <= qp_init_rem_qpn;
      qp_init_loc_qpn_reg      <= qp_init_loc_qpn;
      qp_init_rem_psn_reg      <= qp_init_rem_psn;
      qp_init_loc_psn_reg      <= qp_init_loc_psn;
      qp_init_rem_addr_reg     <= qp_init_rem_addr;
      qp_init_r_key_reg        <= qp_init_r_key;
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

  assign qp_init_status_valid = qp_open_status_valid;
  assign qp_init_status       = {error_qp_request, 1'b0};

  assign qp_req_context_valid = qp_req_context_valid_pipes[1];
  assign qp_req_state       = qp_req_context_pipe[QP_STATE_OFFSET   +: 3 ];
  assign qp_req_rem_ip_addr = qp_req_context_pipe[REM_IPADDR_OFFSET +: 32];
  assign qp_req_rem_qpn     = qp_req_context_pipe[REM_QPN_OFFSET    +: 24];
  assign qp_req_loc_qpn     = qp_req_context_pipe[LOC_QPN_OFFSET    +: 24];
  assign qp_req_rem_psn     = qp_req_context_pipe[REM_PSN_OFFSET    +: 24];
  assign qp_req_loc_psn     = qp_req_context_pipe[LOC_PSN_OFFSET    +: 24];
  assign qp_req_rem_addr    = qp_req_context_pipe[VADDR_OFFSET      +: 64];
  assign qp_req_r_key       = qp_req_context_pipe[RKEY_OFFSET       +: 32];

  assign qp_spy_context_valid = qp_spy_context_valid_pipes[1];
  assign qp_spy_state         = qp_spy_context_pipe[QP_STATE_OFFSET   +: 3 ];
  assign qp_spy_rem_ip_addr   = qp_spy_context_pipe[REM_IPADDR_OFFSET +: 32];
  assign qp_spy_rem_qpn       = qp_spy_context_pipe[REM_QPN_OFFSET    +: 24];
  assign qp_spy_loc_qpn       = qp_spy_context_pipe[LOC_QPN_OFFSET    +: 24];
  assign qp_spy_rem_psn       = qp_spy_context_pipe[REM_PSN_OFFSET    +: 24];
  assign qp_spy_rem_acked_psn = qp_spy_rem_acked_psn_reg;
  assign qp_spy_loc_psn       = qp_spy_context_pipe[LOC_PSN_OFFSET    +: 24];
  assign qp_spy_rem_addr      = qp_spy_context_pipe[VADDR_OFFSET      +: 64];
  assign qp_spy_r_key         = qp_spy_context_pipe[RKEY_OFFSET       +: 32];
  assign qp_spy_syndrome      = qp_spy_context_pipe[SYNDROME_OFFSET   +: 8];

  assign s_roce_rx_bth_ready = 1'b1;
  assign s_roce_rx_aeth_ready = 1'b1;


  assign last_acked_psn  = last_acked_psn_reg;
  assign last_nacked_psn = last_nacked_psn_reg;
  assign stop_transfer   = stop_transfer_reg;



endmodule

`resetall
