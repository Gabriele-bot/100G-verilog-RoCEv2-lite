`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_qp_state_module #(
  parameter N_QUEUE_PAIRS   = 2,
  parameter REM_ADDR_WIDTH  = 32
) (
  input wire clk,
  input wire rst,


  // CM ports
  input wire        cm_qp_valid,
  output wire       cm_qp_ready,
  input wire [2 :0] cm_qp_req_type,
  input wire [31:0] cm_qp_r_key,
  input wire [23:0] cm_qp_rem_qpn,
  input wire [23:0] cm_qp_loc_qpn,
  input wire [23:0] cm_qp_rem_psn,
  input wire [23:0] cm_qp_loc_psn,
  input wire [31:0] cm_qp_rem_ip_addr,
  input wire [63:0] cm_qp_rem_addr,

  output wire        cm_qp_status_valid,
  output wire [1 :0] cm_qp_status,
  output wire [2 :0] cm_qp_status_state,
  output wire [31:0] cm_qp_status_r_key,
  output wire [23:0] cm_qp_status_rem_qpn,
  output wire [23:0] cm_qp_status_loc_qpn,
  output wire [23:0] cm_qp_status_rem_psn,
  output wire [23:0] cm_qp_status_loc_psn,
  output wire [31:0] cm_qp_status_rem_ip_addr,
  output wire [63:0] cm_qp_status_rem_addr,

  output wire        m_cm_next_qp_available_valid,
  input  wire        m_cm_next_qp_available_ready,
  output wire [23:0] m_cm_next_qp_available_qpn,

  // Close qp
  input  wire        s_qp_close_valid,
  output wire        s_qp_close_ready,
  input  wire [23:0] s_qp_close_loc_qpn,
  input  wire [23:0] s_qp_close_rem_psn,

  // Output QP contetext
  input  wire         s_qp_context_req_valid,
  output wire         s_qp_context_req_ready,
  input  wire [23:0]  s_qp_context_loc_qpn_req,

  output wire        m_qp_context_req_valid,
  output wire [2 :0] m_qp_context_req_state,
  output wire [31:0] m_qp_context_req_r_key,
  output wire [23:0] m_qp_context_req_rem_qpn,
  output wire [23:0] m_qp_context_req_loc_qpn,
  output wire [23:0] m_qp_context_req_rem_psn,
  output wire [23:0] m_qp_context_req_loc_psn,
  output wire [31:0] m_qp_context_req_rem_ip_addr,
  output wire [63:0] m_qp_context_req_rem_addr,

  // SPY QP state
  input wire         m_qp_spy_context,
  input wire [23:0]  m_qp_spy_loc_qpn,

  output wire        s_qp_spy_context_valid,
  output wire [2 :0] s_qp_spy_state,
  output wire [31:0] s_qp_spy_r_key,
  output wire [23:0] s_qp_spy_rem_qpn,
  output wire [23:0] s_qp_spy_loc_qpn,
  output wire [23:0] s_qp_spy_rem_psn,
  output wire [23:0] s_qp_spy_rem_acked_psn,
  output wire [23:0] s_qp_spy_loc_psn,
  output wire [31:0] s_qp_spy_rem_ip_addr,
  output wire [63:0] s_qp_spy_rem_addr,
  output wire [7 :0] s_qp_spy_syndrome,

  // update qp state input
  input  wire        s_qp_update_context_valid,
  output wire        s_qp_update_context_ready,
  input  wire [23:0] s_qp_update_loc_qpn,
  input  wire [23:0] s_qp_update_rem_psn,

  // RX AETH
  input  wire        s_roce_rx_aeth_valid,
  //output wire        s_roce_rx_bth_ready,
  input  wire [23:0] s_roce_rx_aeth_psn,
  input  wire [23:0] s_roce_rx_aeth_dest_qp,
  // RX AETH                  
  input  wire [ 7:0] s_roce_rx_aeth_syndrome,


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
  QP_STATE_RTR      = 3'd2, // not used
  QP_STATE_RTS      = 3'd3,
  QP_STATE_SQ_DRAIN = 3'd4, // not yet uesd
  QP_STATE_SQ_ERROR = 3'd5, // not yet used
  QP_STATE_ERROR    = 3'd6,
  QP_STATE_INVALID  = 3'd7;

  localparam [9:0] QP_CONTEXT_LENGTH = 1+4+3+3+3+3+8+4+3;

  localparam QP_STATE_OFFSET    = 0;
  localparam REM_IPADDR_OFFSET  = QP_STATE_OFFSET   + 8;
  localparam REM_QPN_OFFSET     = REM_IPADDR_OFFSET + 32;
  localparam LOC_QPN_OFFSET     = REM_QPN_OFFSET    + 24;
  localparam REM_PSN_OFFSET     = LOC_QPN_OFFSET    + 24;
  localparam LOC_PSN_OFFSET     = REM_PSN_OFFSET    + 24;
  localparam VADDR_OFFSET       = LOC_PSN_OFFSET    + 24;
  localparam RKEY_OFFSET        = VADDR_OFFSET      + 64;
  localparam SYNDROME_OFFSET    = RKEY_OFFSET       + 32;
  localparam RESERVED_OFFSET    = SYNDROME_OFFSET   + 8;

  localparam [3:0]
  STATE_IDLE           = 4'd0,
  STATE_OPEN_QP        = 4'd1,
  STATE_MODIFY_QP_RTS  = 4'd2,
  STATE_UPDATE_QP      = 4'd3,
  STATE_ERROR_QP       = 4'd4,
  STATE_CLOSE_QP       = 4'd5,
  STATE_UPDATE_CONTEXT = 4'd6,
  STATE_READ_CONTEXT   = 4'd7,
  STATE_FIND_NEXT_QP   = 4'd8,
  STATE_RESET_ALL_QPS  = 4'd9;


  localparam N_QUEUE_PAIRS_WIDTH = (N_QUEUE_PAIRS > 1) ? $clog2(N_QUEUE_PAIRS) : 1;


  reg [QP_CONTEXT_LENGTH*8-1 :0] qp_context [N_QUEUE_PAIRS-1:0];
  reg [QP_CONTEXT_LENGTH*8-1 :0] qp_context_state_temp;
  reg [24-1 :0] qp_rem_acked_psn_mem [N_QUEUE_PAIRS-1:0];
  reg [N_QUEUE_PAIRS_WIDTH-1:0] cm_qp_ptr_reg = 0, cm_qp_ptr_next;
  reg [N_QUEUE_PAIRS_WIDTH-1:0] qp_update_ptr_reg, qp_update_ptr_next;
  reg [N_QUEUE_PAIRS_WIDTH-1:0] qp_close_ptr_reg, qp_close_ptr_next;
  reg [N_QUEUE_PAIRS_WIDTH-1:0] qp_ptr_reg, qp_ptr_next;

  reg store_qp_info;

  reg [3:0] state_reg = STATE_IDLE, state_next;


  reg [2:0] cm_qp_req_type_reg = 0, cm_qp_req_type_next;


  reg [31:0] dma_transfer_reg;
  reg [31:0] r_key_reg;
  reg [23:0] rem_qpn_reg;
  reg [23:0] loc_qpn_reg;
  reg [23:0] rem_psn_reg;
  reg [23:0] loc_psn_reg;
  reg [31:0] rem_ip_addr_reg;
  reg [63:0] rem_addr_reg;

  reg cm_qp_ready_reg, cm_qp_ready_next;

  reg [31:0] cm_qp_r_key_reg;
  reg [23:0] cm_qp_rem_qpn_reg;
  reg [23:0] cm_qp_loc_qpn_reg;
  reg [23:0] cm_qp_rem_psn_reg;
  reg [23:0] cm_qp_loc_psn_reg;
  reg [31:0] cm_qp_rem_ip_addr_reg;
  reg [63:0] cm_qp_rem_addr_reg;


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

  reg        qp_open_status_valid;
  reg        qp_find_status_valid;
  reg [23:0] qp_status_rem_qpn;
  reg [31:0] qp_status_rem_ip_addr;

  reg [1:0]  cm_qp_status_reg, cm_qp_status_next;
  reg [2:0]  cm_qp_status_state_reg;
  reg [31:0] cm_qp_status_r_key_reg;
  reg [23:0] cm_qp_status_rem_qpn_reg;
  reg [23:0] cm_qp_status_loc_qpn_reg;
  reg [23:0] cm_qp_status_rem_psn_reg;
  reg [23:0] cm_qp_status_loc_psn_reg;
  reg [31:0] cm_qp_status_rem_ip_addr_reg;
  reg [63:0] cm_qp_status_rem_addr_reg;
  reg        error_qp_request;
  reg        error_invalid_qp_req;
  reg        error_invalid_qp_spy;

  reg        cm_next_qp_available_valid_reg, cm_next_qp_available_valid_next;
  wire       cm_next_qp_available_ready;
  reg [23:0] cm_next_qp_available_qpn_reg, cm_next_qp_available_qpn_next;

  reg  no_qp_available_reg, no_qp_available_next;


  reg [N_QUEUE_PAIRS_WIDTH+1-1 : 0] qpn_sweep_ctr_reg, qpn_sweep_ctr_next;
  reg [N_QUEUE_PAIRS_WIDTH-1 : 0] qpn_sweep_ctr_start_reg, qpn_sweep_ctr_start_next;

  /*
  WORKAROUND to to have only one qp in RTS at the same time
  */
  reg        qp_active;
  reg [1 :0] qp_active_pipes;
  reg [23:0] curr_open_qpn;

  always @(posedge clk) begin
    if (rst) begin
      curr_open_qpn <= 24'd0;
      qp_active     <= 1'b0;
    end else begin
      if (cm_qp_valid && cm_qp_req_type == REQ_MODIFY_QP_RTS && !qp_active) begin
        curr_open_qpn <= cm_qp_loc_qpn;
        qp_active     <= 1'b1;
      end else if (cm_qp_valid && cm_qp_req_type == REQ_CLOSE_QP && qp_active) begin
        curr_open_qpn <= 24'd0;
        qp_active     <= 1'b0;
      end
    end
    qp_active_pipes[0] <= qp_active;
    qp_active_pipes[1] <= qp_active_pipes[0];
  end
  /*
  WORKAROUND to to have only one qp in RTS at the same time
  */

  integer i;

  initial begin
    for(i = 0; i < N_QUEUE_PAIRS; i = i + 1) begin
      qp_context[i] <= {QP_CONTEXT_LENGTH*8{1'b0}}; // all QP in RESET STATE
      qp_rem_acked_psn_mem[i] <= 24'd0;
    end
    for(i = N_QUEUE_PAIRS; i < 2**N_QUEUE_PAIRS_WIDTH; i = i + 1) begin
      qp_context[i][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_INVALID;
      qp_context[i][REM_IPADDR_OFFSET +: 32] <= 'd0;
      qp_context[i][REM_QPN_OFFSET    +: 24] <= 'd0;
      qp_context[i][LOC_QPN_OFFSET    +: 24] <= 'd0;
      qp_context[i][REM_PSN_OFFSET    +: 24] <= 'd0;
      qp_context[i][LOC_PSN_OFFSET    +: 24] <= 'd0;
      qp_context[i][VADDR_OFFSET      +: 64] <= 'd0;
      qp_context[i][RKEY_OFFSET       +: 32] <= 'd0;
      qp_context[i][SYNDROME_OFFSET   +: 8 ] <= 'd0;
      qp_context[i][RESERVED_OFFSET   +: 16] <= 'd0;
      qp_rem_acked_psn_mem[i] <= 24'd0;
    end
  end



  // QP state
  always @* begin

    state_next = STATE_IDLE;

    cm_qp_req_type_next = cm_qp_req_type_reg;

    cm_qp_ptr_next   = cm_qp_ptr_reg;
    qp_update_ptr_next = qp_update_ptr_reg;
    qp_close_ptr_next  = qp_close_ptr_reg;

    qp_aeth_syndrome_next = qp_aeth_syndrome_reg;

    qp_update_rem_psn_next = qp_update_rem_psn_reg;
    qp_close_rem_psn_next  = qp_close_rem_psn_reg;

    store_qp_info = 1'b0;

    qpn_sweep_ctr_next       = qpn_sweep_ctr_reg;
    qpn_sweep_ctr_start_next = qpn_sweep_ctr_start_reg;

    cm_next_qp_available_valid_next = 1'b0;
    cm_next_qp_available_qpn_next = cm_next_qp_available_qpn_reg;

    no_qp_available_next = no_qp_available_reg;


    cm_qp_ready_next = state_reg == STATE_IDLE;

    case (state_reg)
      STATE_RESET_ALL_QPS: begin
        if (cm_qp_ptr_reg == {N_QUEUE_PAIRS_WIDTH{1'b1}}) begin
          state_next = STATE_IDLE;
        end else begin
          cm_qp_ptr_next = cm_qp_ptr_reg + 1;
          state_next = STATE_RESET_ALL_QPS;
        end
      end
      STATE_IDLE: begin
        if (s_qp_close_valid && (s_qp_close_loc_qpn[23:8] == 16'd1 && s_qp_close_loc_qpn[7:N_QUEUE_PAIRS_WIDTH] == 0)) begin
          //  QP goes to error state, some errors occoured during transfer (e.g. transmission timeout)
          qp_aeth_syndrome_next = {1'b1, 2'b00, 5'b11111}; // 8'h9F
          qp_close_ptr_next = s_qp_close_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
          qp_close_rem_psn_next = s_qp_close_rem_psn;
          cm_qp_ready_next = 1'b0;
          state_next = STATE_ERROR_QP;
        end else if (s_qp_update_context_valid) begin
          // update QP
          if (s_qp_update_loc_qpn[23:8] == 16'd1 && s_qp_update_loc_qpn[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
            qp_update_rem_psn_next = s_qp_update_rem_psn;
            qp_update_ptr_next = s_qp_update_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
            cm_qp_ready_next = 1'b0;
            state_next = STATE_UPDATE_QP;
          end
        end else if (cm_qp_valid) begin
          cm_qp_ready_next = 1'b0;
          store_qp_info = 1'b1;
          if (cm_qp_loc_qpn[23:8] == 16'd1 && cm_qp_loc_qpn[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
            // local qp must be between 256 and 256+N_QUEUE_PAIRS
            cm_qp_req_type_next = cm_qp_req_type;
            case(cm_qp_req_type)
              REQ_OPEN_QP: begin
                cm_qp_ptr_next = cm_qp_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_OPEN_QP;
              end
              REQ_MODIFY_QP_RTS:begin
                qp_update_ptr_next = cm_qp_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_MODIFY_QP_RTS;
              end
              REQ_CLOSE_QP:begin
                qp_aeth_syndrome_next = 8'd0;
                qp_close_ptr_next = cm_qp_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_CLOSE_QP;
              end
              REQ_FETCH_QP_INFO:begin // fetch context from QP state table
                cm_qp_ptr_next = cm_qp_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0];
                state_next = STATE_READ_CONTEXT;
              end
              default:begin
                cm_qp_ready_next = 1'b1;
                state_next = STATE_IDLE;
              end
            endcase
          end
        end

        if (s_roce_rx_aeth_valid & s_roce_rx_aeth_valid) begin
          // recieved an ACK packet
          if (s_roce_rx_aeth_dest_qp[23:8] == 16'd1 && s_roce_rx_aeth_dest_qp[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
            // QP goes to error state if a NAK is received, but not a PSN sequence error (the latter will trigger retransmission)
            if (s_roce_rx_aeth_syndrome[6:5] == 2'b11 && s_roce_rx_aeth_syndrome[4:0] != 5'b00000) begin
              qp_aeth_syndrome_next = s_roce_rx_aeth_syndrome;
              qp_close_ptr_next = s_roce_rx_aeth_dest_qp[N_QUEUE_PAIRS_WIDTH-1:0];
              cm_qp_ready_next = 1'b0;
              state_next = STATE_ERROR_QP;
            end
          end
        end
      end
      STATE_OPEN_QP : begin
        state_next = STATE_UPDATE_CONTEXT;
      end
      STATE_MODIFY_QP_RTS : begin
        state_next = STATE_UPDATE_CONTEXT;
      end
      STATE_UPDATE_QP: begin
        cm_qp_ready_next = 1'b1;
        state_next = STATE_IDLE;
      end
      STATE_ERROR_QP: begin
        cm_qp_ready_next = 1'b1;
        state_next = STATE_IDLE;
      end
      STATE_CLOSE_QP: begin
        state_next   = STATE_UPDATE_CONTEXT;
      end
      STATE_UPDATE_CONTEXT: begin
        if (cm_qp_req_type_reg == REQ_OPEN_QP) begin
          cm_qp_req_type_next = REQ_MODIFY_QP_RTS;
          qp_update_ptr_next = cm_qp_loc_qpn_reg[N_QUEUE_PAIRS_WIDTH-1:0];
          state_next = STATE_MODIFY_QP_RTS;
        end else if ((cm_qp_req_type_reg == REQ_MODIFY_QP_RTS && cm_next_qp_available_ready) || (cm_qp_req_type_reg == REQ_CLOSE_QP && no_qp_available_reg)) begin
          // search for netx qp available after open qp or close qp and no qp were already available
          cm_qp_ptr_next = qpn_sweep_ctr_start_reg;
          cm_qp_req_type_next = REQ_NULL;
          state_next = STATE_READ_CONTEXT;
        end else begin
          cm_qp_ready_next = 1'b1;
          state_next   = STATE_IDLE;
        end
      end
      STATE_READ_CONTEXT: begin
        if (cm_qp_req_type_reg == REQ_FETCH_QP_INFO) begin
          cm_qp_ready_next = 1'b1;
          state_next   = STATE_IDLE;
        end else begin
          state_next   = STATE_FIND_NEXT_QP;
        end
      end
      STATE_FIND_NEXT_QP: begin
        if (qpn_sweep_ctr_reg >= N_QUEUE_PAIRS) begin // no qp available found
          no_qp_available_next = 1'b1;
          qpn_sweep_ctr_next = 'd0;
          cm_next_qp_available_qpn_next = 'd0;
          cm_qp_ready_next = 1'b1;
          state_next         = STATE_IDLE;
        end else begin
          if (cm_qp_status_state_reg == QP_STATE_RESET && qp_find_status_valid) begin // found a qp in a reset state
            no_qp_available_next = 1'b0;
            qpn_sweep_ctr_next = 'd0;
            if (N_QUEUE_PAIRS > 1) begin
              qpn_sweep_ctr_start_next = qpn_sweep_ctr_reg[N_QUEUE_PAIRS_WIDTH-1:0] + 1;
            end else begin
              qpn_sweep_ctr_start_next = 'd0;
            end
            // output value
            cm_next_qp_available_valid_next <= 1'b1;
            cm_next_qp_available_qpn_next = 24'd256 + cm_qp_ptr_reg;
            cm_qp_ready_next = 1'b1;
            state_next         = STATE_IDLE;
          end else begin // try another qpn
            if (N_QUEUE_PAIRS > 1) begin
              cm_qp_ptr_next     = qpn_sweep_ctr_start_reg + qpn_sweep_ctr_reg[N_QUEUE_PAIRS_WIDTH-1:0] + 1;
            end else begin
              cm_qp_ptr_next     = 'd0;
            end
            qpn_sweep_ctr_next = qpn_sweep_ctr_reg + 1;
            state_next         = STATE_READ_CONTEXT;
          end
        end
      end

    endcase

  end

  // ACK'ED PSN memory
  always @(posedge clk) begin

    // write first, else read
    if (s_roce_rx_aeth_valid & s_roce_rx_aeth_valid) begin
      // local qp must be between 256 and 256+N_QUEUE_PAIRS
      if (s_roce_rx_aeth_dest_qp[23:8] == 16'd1 && s_roce_rx_aeth_dest_qp[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
        if (s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin // ACK
          qp_rem_acked_psn_mem[s_roce_rx_aeth_dest_qp[N_QUEUE_PAIRS_WIDTH-1:0]] <= s_roce_rx_aeth_psn;
        end
      end
      // if reset QP put it to 0  
    end else if (state_reg == STATE_OPEN_QP) begin
      qp_rem_acked_psn_mem[cm_qp_ptr_reg] <= 24'd0;
    end else if (m_qp_spy_context) begin
      if (m_qp_spy_loc_qpn[23:8] == 16'd1 && m_qp_spy_loc_qpn[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_spy_rem_acked_psn_reg <= qp_rem_acked_psn_mem[m_qp_spy_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0]];
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      qpn_sweep_ctr_reg       <= 'd0;
      qpn_sweep_ctr_start_reg <= 'd0;
    end else begin
      qpn_sweep_ctr_reg       <= qpn_sweep_ctr_next;
      qpn_sweep_ctr_start_reg <= qpn_sweep_ctr_start_next;
    end

    qp_find_status_valid <= 1'b0;

    // Read request, spy port has low priority
    if (s_qp_context_req_valid && s_qp_context_req_ready) begin
      qp_spy_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_spy          <= 1'b0;
      if (s_qp_context_loc_qpn_req[23:8] == 16'd1 && s_qp_context_loc_qpn_req[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_req_context <= qp_context[s_qp_context_loc_qpn_req[N_QUEUE_PAIRS_WIDTH-1:0]];
        qp_req_context_valid_pipes[0] <= 1'b1;
        error_invalid_qp_req          <= 1'b0;
      end else begin
        qp_req_context_valid_pipes[0] <= 1'b0;
        error_invalid_qp_req          <= 1'b1;
      end
    end else if (m_qp_spy_context) begin
      qp_req_context_valid_pipes[0] <= 1'b0;
      error_invalid_qp_req          <= 1'b0;
      if (m_qp_spy_loc_qpn[23:8] == 16'd1 && m_qp_spy_loc_qpn[7:N_QUEUE_PAIRS_WIDTH] == 0) begin
        qp_spy_context <= qp_context[m_qp_spy_loc_qpn[N_QUEUE_PAIRS_WIDTH-1:0]];
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
      STATE_RESET_ALL_QPS: begin
        if (cm_qp_ptr_reg < N_QUEUE_PAIRS) begin
          qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RESET;
          qp_context[cm_qp_ptr_reg][REM_IPADDR_OFFSET +: 32] <= 'd0;
          qp_context[cm_qp_ptr_reg][REM_QPN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][LOC_QPN_OFFSET    +: 24] <= 24'd256 + cm_qp_ptr_reg;
          qp_context[cm_qp_ptr_reg][REM_PSN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][LOC_PSN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][VADDR_OFFSET      +: 64] <= 'd0;
          qp_context[cm_qp_ptr_reg][RKEY_OFFSET       +: 32] <= 'd0;
          qp_context[cm_qp_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 'd0;
          qp_context[cm_qp_ptr_reg][RESERVED_OFFSET   +: 16] <= 'd0;
        end else begin
          qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_INVALID;
          qp_context[cm_qp_ptr_reg][REM_IPADDR_OFFSET +: 32] <= 'd0;
          qp_context[cm_qp_ptr_reg][REM_QPN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][LOC_QPN_OFFSET    +: 24] <= 24'd256 + cm_qp_ptr_reg;
          qp_context[cm_qp_ptr_reg][REM_PSN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][LOC_PSN_OFFSET    +: 24] <= 'd0;
          qp_context[cm_qp_ptr_reg][VADDR_OFFSET      +: 64] <= 'd0;
          qp_context[cm_qp_ptr_reg][RKEY_OFFSET       +: 32] <= 'd0;
          qp_context[cm_qp_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 'd0;
          qp_context[cm_qp_ptr_reg][RESERVED_OFFSET   +: 16] <= 'd0;
        end
      end
      STATE_IDLE: begin
        error_qp_request     <= 1'b0;
        qp_open_status_valid <= 1'b0;
      end
      STATE_OPEN_QP: begin
        // check if QP is RESET state
        qp_context_state_temp  <= qp_context[cm_qp_ptr_reg];
      end
      STATE_MODIFY_QP_RTS: begin
        // check if QP is RESET state
        qp_context_state_temp  <= qp_context[qp_update_ptr_reg];
      end
      STATE_UPDATE_QP: begin
        qp_context[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= qp_context[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3] ;
        qp_context[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_context[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32];
        qp_context[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_context[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24];
        qp_context[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_context[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24];
        qp_context[qp_update_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_update_rem_psn_reg;
        qp_context[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_context[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24];
        qp_context[qp_update_ptr_reg][VADDR_OFFSET      +: 64] <= qp_context[qp_update_ptr_reg][VADDR_OFFSET      +: 64];
        qp_context[qp_update_ptr_reg][RKEY_OFFSET       +: 32] <= qp_context[qp_update_ptr_reg][RKEY_OFFSET       +: 32];
        qp_context[qp_update_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 8'd0;
      end
      STATE_ERROR_QP: begin
        qp_context[qp_close_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_ERROR;
        qp_context[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_context[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32];
        qp_context[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_context[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24];
        qp_context[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_context[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24];
        qp_context[qp_close_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
        qp_context[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_context[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24];
        qp_context[qp_close_ptr_reg][VADDR_OFFSET      +: 64] <= qp_context[qp_close_ptr_reg][VADDR_OFFSET      +: 64];
        qp_context[qp_close_ptr_reg][RKEY_OFFSET       +: 32] <= qp_context[qp_close_ptr_reg][RKEY_OFFSET       +: 32];
        qp_context[qp_close_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;
      end
      STATE_CLOSE_QP: begin
        qp_context_state_temp <= qp_context[qp_close_ptr_reg];
      end
      STATE_UPDATE_CONTEXT: begin
        case(cm_qp_req_type_reg)
          REQ_OPEN_QP: begin
            if (qp_context_state_temp[QP_STATE_OFFSET   +: 3]  == QP_STATE_RESET) begin
              qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_INIT;
              qp_context[cm_qp_ptr_reg][REM_IPADDR_OFFSET +: 32] <= cm_qp_rem_ip_addr_reg;
              qp_context[cm_qp_ptr_reg][REM_QPN_OFFSET    +: 24] <= cm_qp_rem_qpn_reg;
              qp_context[cm_qp_ptr_reg][LOC_QPN_OFFSET    +: 24] <= cm_qp_loc_qpn_reg;
              qp_context[cm_qp_ptr_reg][REM_PSN_OFFSET    +: 24] <= cm_qp_rem_psn_reg;
              qp_context[cm_qp_ptr_reg][LOC_PSN_OFFSET    +: 24] <= cm_qp_loc_psn_reg;
              qp_context[cm_qp_ptr_reg][VADDR_OFFSET      +: 64] <= cm_qp_rem_addr_reg;
              qp_context[cm_qp_ptr_reg][RKEY_OFFSET       +: 32] <= cm_qp_r_key_reg;
              qp_context[cm_qp_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= 8'd0;
              qp_context[cm_qp_ptr_reg][RESERVED_OFFSET   +: 16] <= 16'd0;

              //error_qp_request     <= 1'b0;
              //qp_open_status_valid <= 1'b1;
            end else begin
              error_qp_request      <= 1'b1;
              qp_open_status_valid  <= 1'b1;
              qp_status_rem_qpn     <= 24'd0;
              qp_status_rem_ip_addr <= 32'd0;
            end
          end
          REQ_MODIFY_QP_RTS:begin
            if (qp_context_state_temp[QP_STATE_OFFSET   +: 3]  == QP_STATE_INIT) begin
              qp_context[qp_update_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RTS;
              qp_context[qp_update_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_context_state_temp[REM_IPADDR_OFFSET +: 32];
              qp_context[qp_update_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_context_state_temp[REM_QPN_OFFSET    +: 24];
              qp_context[qp_update_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_context_state_temp[LOC_QPN_OFFSET    +: 24];
              qp_context[qp_update_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_context_state_temp[REM_PSN_OFFSET    +: 24];
              qp_context[qp_update_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_context_state_temp[LOC_PSN_OFFSET    +: 24];
              qp_context[qp_update_ptr_reg][VADDR_OFFSET      +: 64] <= qp_context_state_temp[VADDR_OFFSET      +: 64];
              qp_context[qp_update_ptr_reg][RKEY_OFFSET       +: 32] <= qp_context_state_temp[RKEY_OFFSET       +: 32];
              qp_context[qp_update_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_context_state_temp[SYNDROME_OFFSET   +: 8 ];
              qp_context[qp_update_ptr_reg][RESERVED_OFFSET   +: 16] <= qp_context_state_temp[RESERVED_OFFSET   +: 16];

              error_qp_request      <= 1'b0;
              qp_open_status_valid  <= 1'b1;
              qp_status_rem_qpn     <= qp_context_state_temp[REM_QPN_OFFSET    +: 24];
              qp_status_rem_ip_addr <= qp_context_state_temp[REM_IPADDR_OFFSET +: 32];
            end else begin
              error_qp_request      <= 1'b1;
              qp_open_status_valid  <= 1'b1;
              qp_status_rem_qpn     <= 24'd0;
              qp_status_rem_ip_addr <= 32'd0;
            end
          end
          REQ_CLOSE_QP:begin
            if (qp_context_state_temp[QP_STATE_OFFSET   +: 3]  != QP_STATE_RESET || qp_context_state_temp[QP_STATE_OFFSET   +: 3]  != QP_STATE_INVALID) begin
              qp_context[qp_close_ptr_reg][QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RESET;
              qp_context[qp_close_ptr_reg][REM_IPADDR_OFFSET +: 32] <= qp_context_state_temp[REM_IPADDR_OFFSET +: 32];
              qp_context[qp_close_ptr_reg][REM_QPN_OFFSET    +: 24] <= qp_context_state_temp[REM_QPN_OFFSET    +: 24];
              qp_context[qp_close_ptr_reg][LOC_QPN_OFFSET    +: 24] <= qp_context_state_temp[LOC_QPN_OFFSET    +: 24];
              qp_context[qp_close_ptr_reg][REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
              qp_context[qp_close_ptr_reg][LOC_PSN_OFFSET    +: 24] <= qp_context_state_temp[LOC_PSN_OFFSET    +: 24];
              qp_context[qp_close_ptr_reg][VADDR_OFFSET      +: 64] <= qp_context_state_temp[VADDR_OFFSET      +: 64];
              qp_context[qp_close_ptr_reg][RKEY_OFFSET       +: 32] <= qp_context_state_temp[RKEY_OFFSET       +: 32];
              qp_context[qp_close_ptr_reg][SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;

              error_qp_request      <= 1'b0;
              qp_open_status_valid  <= 1'b1;
              qp_status_rem_qpn     <= qp_context_state_temp[REM_QPN_OFFSET    +: 24];
              qp_status_rem_ip_addr <= qp_context_state_temp[REM_IPADDR_OFFSET +: 32];
            end else begin
              error_qp_request     <= 1'b1;
              qp_open_status_valid <= 1'b1;
            end
          end
        endcase
      end
      STATE_READ_CONTEXT: begin
        error_qp_request             <= qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3] == QP_STATE_RESET || qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3] == QP_STATE_ERROR; // qp not open or in error state, send error
        qp_open_status_valid         <= cm_qp_req_type_reg == REQ_FETCH_QP_INFO;;
        qp_find_status_valid         <= cm_qp_req_type_reg == REQ_NULL;
        cm_qp_status_state_reg       <= qp_context[cm_qp_ptr_reg][QP_STATE_OFFSET   +: 3];
        cm_qp_status_r_key_reg       <= qp_context[cm_qp_ptr_reg][RKEY_OFFSET       +: 32];
        cm_qp_status_rem_qpn_reg     <= qp_context[cm_qp_ptr_reg][REM_QPN_OFFSET    +: 24];
        cm_qp_status_loc_qpn_reg     <= qp_context[cm_qp_ptr_reg][LOC_QPN_OFFSET    +: 24];
        cm_qp_status_rem_psn_reg     <= qp_context[cm_qp_ptr_reg][REM_PSN_OFFSET    +: 24];
        cm_qp_status_loc_psn_reg     <= qp_context[cm_qp_ptr_reg][LOC_PSN_OFFSET    +: 24];
        cm_qp_status_rem_ip_addr_reg <= qp_context[cm_qp_ptr_reg][REM_IPADDR_OFFSET +: 32];
        cm_qp_status_rem_addr_reg    <= qp_context[cm_qp_ptr_reg][VADDR_OFFSET      +: 64];
      end
      STATE_FIND_NEXT_QP: begin
        qp_find_status_valid         <= 1'b0;
      end

      default: begin
        qp_open_status_valid <= 1'b0;
        error_qp_request     <= 1'b0;
      end
    endcase
  end

  always @(posedge clk) begin

    if (rst) begin
      state_reg <= STATE_RESET_ALL_QPS;

      cm_qp_req_type_reg <= 3'd0;

      cm_qp_ready_reg <= 1'b0;

      cm_qp_ptr_reg   <= 0;
      qp_update_ptr_reg <= 0;
      qp_close_ptr_reg  <= 0;

      cm_next_qp_available_valid_reg <= 1'b0;
      cm_next_qp_available_qpn_reg <= 24'd256;

      no_qp_available_reg <= 1'b0;
    end else begin
      state_reg       <= state_next;

      cm_qp_req_type_reg <= cm_qp_req_type_next;

      cm_qp_ready_reg <= cm_qp_ready_next;

      cm_qp_ptr_reg   <= cm_qp_ptr_next;
      qp_update_ptr_reg <= qp_update_ptr_next;
      qp_close_ptr_reg  <= qp_close_ptr_next;

      cm_next_qp_available_valid_reg <= cm_next_qp_available_valid_next;
      cm_next_qp_available_qpn_reg <= cm_next_qp_available_qpn_next;

      no_qp_available_reg <= no_qp_available_next;

      qp_aeth_syndrome_reg <= qp_aeth_syndrome_next;
      qp_update_rem_psn_reg <= qp_update_rem_psn_next;

      if (store_qp_info) begin
        cm_qp_rem_ip_addr_reg  <= cm_qp_rem_ip_addr;
        cm_qp_rem_qpn_reg      <= cm_qp_rem_qpn;
        cm_qp_loc_qpn_reg      <= cm_qp_loc_qpn;
        cm_qp_rem_psn_reg      <= cm_qp_rem_psn;
        cm_qp_loc_psn_reg      <= cm_qp_loc_psn;
        cm_qp_rem_addr_reg     <= cm_qp_rem_addr;
        cm_qp_r_key_reg        <= cm_qp_r_key;
      end
    end



  end

  // RX side 
  always @(posedge clk) begin
    if (rst) begin
      loc_qpn_reg         <= cm_qp_loc_qpn;
      loc_psn_reg         <= cm_qp_loc_psn;
      last_acked_psn_reg  <= cm_qp_rem_psn;
      last_nacked_psn_reg <= cm_qp_rem_psn;
    end else begin
      if (s_roce_rx_aeth_valid && s_roce_rx_aeth_dest_qp == loc_qpn_reg) begin
        if (s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
          last_acked_psn_reg <= s_roce_rx_aeth_psn;
          stop_transfer_reg  <= 1'b0;
        end else if (s_roce_rx_aeth_syndrome[6:5] != 2'b00) begin
          last_nacked_psn_reg <= s_roce_rx_aeth_psn;
          stop_transfer_reg   <= 1'b1;
        end
      end else begin
        stop_transfer_reg <= 1'b0;
      end
    end
  end

  assign cm_qp_ready = cm_qp_ready_reg;

  assign cm_qp_status_valid       = qp_open_status_valid;
  assign cm_qp_status             = {error_qp_request, 1'b0};
  assign cm_qp_status_state       = cm_qp_status_state_reg;
  assign cm_qp_status_r_key       = cm_qp_status_r_key_reg;
  assign cm_qp_status_rem_qpn     = cm_qp_status_rem_qpn_reg;
  assign cm_qp_status_loc_qpn     = cm_qp_status_loc_qpn_reg;
  assign cm_qp_status_rem_psn     = cm_qp_status_rem_psn_reg;
  assign cm_qp_status_loc_psn     = cm_qp_status_loc_psn_reg;
  assign cm_qp_status_rem_ip_addr = cm_qp_status_rem_ip_addr_reg;
  assign cm_qp_status_rem_addr    = cm_qp_status_rem_addr_reg;

  assign m_qp_context_req_valid         = qp_req_context_valid_pipes[1];
  assign m_qp_context_req_state         = qp_req_context_pipe[QP_STATE_OFFSET   +: 3 ];
  assign m_qp_context_req_rem_ip_addr   = qp_req_context_pipe[REM_IPADDR_OFFSET +: 32];
  assign m_qp_context_req_rem_qpn       = qp_req_context_pipe[REM_QPN_OFFSET    +: 24];
  assign m_qp_context_req_loc_qpn       = qp_req_context_pipe[LOC_QPN_OFFSET    +: 24];
  assign m_qp_context_req_rem_psn       = qp_req_context_pipe[REM_PSN_OFFSET    +: 24];
  assign m_qp_context_req_loc_psn       = qp_req_context_pipe[LOC_PSN_OFFSET    +: 24];
  assign m_qp_context_req_rem_addr      = qp_req_context_pipe[VADDR_OFFSET      +: 64];
  assign m_qp_context_req_r_key         = qp_req_context_pipe[RKEY_OFFSET       +: 32];

  assign s_qp_spy_context_valid = qp_spy_context_valid_pipes[1];
  assign s_qp_spy_state         = qp_spy_context_pipe[QP_STATE_OFFSET   +: 3 ];
  assign s_qp_spy_rem_ip_addr   = qp_spy_context_pipe[REM_IPADDR_OFFSET +: 32];
  assign s_qp_spy_rem_qpn       = qp_spy_context_pipe[REM_QPN_OFFSET    +: 24];
  assign s_qp_spy_loc_qpn       = qp_spy_context_pipe[LOC_QPN_OFFSET    +: 24];
  assign s_qp_spy_rem_psn       = qp_spy_context_pipe[REM_PSN_OFFSET    +: 24];
  assign s_qp_spy_rem_acked_psn = qp_spy_rem_acked_psn_reg;
  assign s_qp_spy_loc_psn       = qp_spy_context_pipe[LOC_PSN_OFFSET    +: 24];
  assign s_qp_spy_rem_addr      = qp_spy_context_pipe[VADDR_OFFSET      +: 64];
  assign s_qp_spy_r_key         = qp_spy_context_pipe[RKEY_OFFSET       +: 32];
  assign s_qp_spy_syndrome      = qp_spy_context_pipe[SYNDROME_OFFSET   +: 8];

  //assign s_roce_rx_bth_ready  = 1'b1;
  //assign s_roce_rx_aeth_ready = 1'b1;


  assign last_acked_psn  = last_acked_psn_reg;
  assign last_nacked_psn = last_nacked_psn_reg;
  assign stop_transfer   = stop_transfer_reg;

  assign s_qp_update_context_ready = state_reg == STATE_UPDATE_QP;
  assign s_qp_close_ready          = state_reg == STATE_ERROR_QP;
  assign s_qp_context_req_ready = 1'b1;

  qpn_fifo_init #(
    .MAX_QUEUE_PAIRS_FIFO(1),
    .BASE_QPN_FIFO(256)
  ) qpn_fifo_init_instance (
    .clk(clk),
    .rst(rst | state_reg == STATE_RESET_ALL_QPS),
    .s_qpn_fifo_valid(cm_next_qp_available_valid_reg),
    .s_qpn_fifo_ready(cm_next_qp_available_ready),
    .s_qpn(cm_next_qp_available_qpn_reg),
    .m_qpn_fifo_valid(m_cm_next_qp_available_valid),
    .m_qpn_fifo_ready(m_cm_next_qp_available_ready),
    .m_qpn(m_cm_next_qp_available_qpn)
  );


endmodule

`resetall
