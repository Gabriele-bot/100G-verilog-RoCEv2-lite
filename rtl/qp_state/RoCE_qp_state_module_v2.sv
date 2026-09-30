`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * RoCE QP State Module v2 — BRAM-backed context storage
 *
 * Context RAM (256-bit × N_QUEUE_PAIRS, STYLE="block"):
 *   Port A : state machine — read in IDLE, write-back in processing state (1-cycle BRAM latency)
 *   Port B : context_req + spy — independent read port, always available
 *
 * ACK'd PSN memory stays as distributed RAM (24-bit × N, updated per-packet, small).
 *
 * State machine: IDLE → {UPDATE_CONTEXT, UPDATE_QP, ERROR_QP, READ_CONTEXT} → IDLE
 *   OPEN→MODIFY RTS chain uses a bypass register to avoid a second RAM read.
 */

module RoCE_qp_state_module_v2 #(
  parameter N_QUEUE_PAIRS  = 2,
  parameter REM_ADDR_WIDTH = 32
) (
  input wire clk,
  input wire rst,
  input wire rst_qp,

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

  // Forced close / error
  input  wire        s_qp_close_valid,
  output wire        s_qp_close_ready,
  input  wire [23:0] s_qp_close_loc_qpn,
  input  wire [23:0] s_qp_close_rem_psn,

  // Context read-out (TX path)
  input  wire        s_qp_context_req_valid,
  output wire        s_qp_context_req_ready,
  input  wire [23:0] s_qp_context_loc_qpn_req,

  output wire        m_qp_context_req_valid,
  output wire [2 :0] m_qp_context_req_state,
  output wire [31:0] m_qp_context_req_r_key,
  output wire [23:0] m_qp_context_req_rem_qpn,
  output wire [23:0] m_qp_context_req_loc_qpn,
  output wire [23:0] m_qp_context_req_rem_psn,
  output wire [23:0] m_qp_context_req_loc_psn,
  output wire [31:0] m_qp_context_req_rem_ip_addr,
  output wire [63:0] m_qp_context_req_rem_addr,

  // Spy / monitor
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

  // PSN update (from ACK handler)
  input  wire        s_qp_update_context_valid,
  output wire        s_qp_update_context_ready,
  input  wire [23:0] s_qp_update_loc_qpn,
  input  wire [23:0] s_qp_update_rem_psn,

  // RX AETH (ACK/NAK from remote)
  input  wire        s_roce_rx_aeth_valid,
  input  wire [23:0] s_roce_rx_aeth_psn,
  input  wire [23:0] s_roce_rx_aeth_dest_qp,
  input  wire [ 7:0] s_roce_rx_aeth_syndrome,

  output wire [23:0] last_acked_psn,
  output wire [23:0] last_nacked_psn,
  output wire        stop_transfer,

  input wire [2:0] pmtu
);

  import RoCE_params::*;

  // -------------------------------------------------------------------------
  // Parameters and constants
  // -------------------------------------------------------------------------

  localparam [2:0]
    QP_STATE_RESET    = 3'd0,
    QP_STATE_INIT     = 3'd1,
    QP_STATE_RTR      = 3'd2,
    QP_STATE_RTS      = 3'd3,
    QP_STATE_SQ_DRAIN = 3'd4,
    QP_STATE_SQ_ERROR = 3'd5,
    QP_STATE_ERROR    = 3'd6;

  // 256-bit context word layout (matches original offsets exactly)
  localparam QP_STATE_OFFSET   = 0;    // [7:0]   state[2:0] + 5 reserved bits
  localparam REM_IPADDR_OFFSET = 8;    // [39:8]
  localparam REM_QPN_OFFSET    = 40;   // [63:40]
  localparam LOC_QPN_OFFSET    = 64;   // [87:64]
  localparam REM_PSN_OFFSET    = 88;   // [111:88]
  localparam LOC_PSN_OFFSET    = 112;  // [135:112]
  localparam VADDR_OFFSET      = 136;  // [199:136]
  localparam RKEY_OFFSET       = 200;  // [231:200]
  localparam SYNDROME_OFFSET   = 232;  // [239:232]
  localparam RESERVED_OFFSET   = 240;  // [255:240]
  localparam CONTEXT_WIDTH     = 256;
  localparam CONTEXT_BYTES     = CONTEXT_WIDTH / 8;

  localparam N_QP_W = $clog2(N_QUEUE_PAIRS); // RAM address width

  localparam [2:0]
    STATE_IDLE           = 3'd0,
    STATE_UPDATE_CONTEXT = 3'd1,  // open / modify-RTS / close
    STATE_UPDATE_QP      = 3'd2,  // PSN update from ACK handler
    STATE_ERROR_QP       = 3'd3,  // forced close / NAK error
    STATE_READ_CONTEXT   = 3'd4;  // REQ_FETCH_QP_INFO

  // -------------------------------------------------------------------------
  // QP active workaround (only one QP in RTS at a time)
  // -------------------------------------------------------------------------

  reg        qp_active;
  reg [1:0]  qp_active_pipe;
  reg [23:0] curr_open_qpn;

  always @(posedge clk) begin
    if (rst) begin
      qp_active    <= 1'b0;
      curr_open_qpn <= 24'd0;
    end else begin
      if (cm_qp_valid && cm_qp_req_type == REQ_MODIFY_QP_RTS && !qp_active) begin
        curr_open_qpn <= cm_qp_loc_qpn;
        qp_active     <= 1'b1;
      end else if (cm_qp_valid && cm_qp_req_type == REQ_CLOSE_QP && qp_active) begin
        curr_open_qpn <= 24'd0;
        qp_active     <= 1'b0;
      end
    end
    qp_active_pipe[0] <= qp_active;
    qp_active_pipe[1] <= qp_active_pipe[0];
  end

  // -------------------------------------------------------------------------
  // Port A — state machine (read then write-back)
  // -------------------------------------------------------------------------

  reg [N_QP_W-1:0]      ram_a_addr;
  reg [CONTEXT_WIDTH-1:0] ram_a_din;
  reg [CONTEXT_BYTES-1:0] ram_a_strb;
  reg                    ram_a_ren;
  reg                    ram_a_wen;
  wire [CONTEXT_WIDTH-1:0] ram_a_dout;

  // -------------------------------------------------------------------------
  // Port B — context_req + spy (read-only, independent of state machine)
  // -------------------------------------------------------------------------

  // Combinatorial: context_req has priority over spy
  wire b_req_valid = s_qp_context_req_valid &&
                     s_qp_context_loc_qpn_req[23:8] == 16'd1 &&
                     s_qp_context_loc_qpn_req[7:N_QP_W] == 0;
  wire b_spy_valid = m_qp_spy_context &&
                     m_qp_spy_loc_qpn[23:8] == 16'd1 &&
                     m_qp_spy_loc_qpn[7:N_QP_W] == 0 &&
                     !s_qp_context_req_valid;

  wire                  ram_b_ren  = b_req_valid || b_spy_valid;
  wire [N_QP_W-1:0]    ram_b_addr = b_req_valid ?
                                    s_qp_context_loc_qpn_req[N_QP_W-1:0] :
                                    m_qp_spy_loc_qpn[N_QP_W-1:0];
  wire [CONTEXT_WIDTH-1:0] ram_b_dout;

  // 1-cycle pipeline for Port B output type tracking (NPIPES=-1 → 1-cycle RAM latency)
  reg b_valid_d1;
  reg b_is_req_d1;
  reg [23:0] b_spy_acked_psn_d1;

  always @(posedge clk) begin
    if (rst) begin
      b_valid_d1 <= 1'b0;
      b_is_req_d1 <= 1'b0;
    end else begin
      b_valid_d1  <= ram_b_ren;
      b_is_req_d1 <= b_req_valid;
      if (b_spy_valid)
        b_spy_acked_psn_d1 <= qp_rem_acked_psn_mem[m_qp_spy_loc_qpn[N_QP_W-1:0]];
    end
  end

  // -------------------------------------------------------------------------
  // True dual-port BRAM for QP context
  // -------------------------------------------------------------------------

  true_dpram #(
    .ADDR_WIDTH (N_QP_W),
    .DATA_WIDTH (CONTEXT_WIDTH),
    .STRB_WIDTH (CONTEXT_BYTES),
    .SIZE       (N_QUEUE_PAIRS),
    .NPIPES     (-1),
    .INIT_VALUE ({CONTEXT_WIDTH{1'b0}}),
    .STYLE      ("block")
  ) u_qp_ctx_ram (
    .clka  (clk),         .rsta  (rst),
    .addra (ram_a_addr),  .dina  (ram_a_din),  .douta (ram_a_dout),
    .strba (ram_a_strb),  .ena   (1'b1),
    .rea   (ram_a_ren),   .wea   (ram_a_wen),

    .clkb  (clk),         .rstb  (rst),
    .addrb (ram_b_addr),  .dinb  ({CONTEXT_WIDTH{1'b0}}),  .doutb (ram_b_dout),
    .strbb ({CONTEXT_BYTES{1'b0}}),  .enb   (1'b1),
    .reb   (ram_b_ren),   .web   (1'b0)
  );

  // -------------------------------------------------------------------------
  // ACK'd PSN memory — small, keep as distributed RAM (updated per packet)
  // -------------------------------------------------------------------------

  reg [23:0] qp_rem_acked_psn_mem [N_QUEUE_PAIRS-1:0];

  integer ii;
  initial begin
    for (ii = 0; ii < N_QUEUE_PAIRS; ii = ii + 1)
      qp_rem_acked_psn_mem[ii] = 24'd0;
  end

  always @(posedge clk) begin
    if (s_roce_rx_aeth_valid &&
        s_roce_rx_aeth_dest_qp[23:8] == 16'd1 &&
        s_roce_rx_aeth_dest_qp[7:N_QP_W] == 0) begin
      if (s_roce_rx_aeth_syndrome[6:5] == 2'b00) // ACK
        qp_rem_acked_psn_mem[s_roce_rx_aeth_dest_qp[N_QP_W-1:0]] <= s_roce_rx_aeth_psn;
    end else if (ram_a_wen && state_reg == STATE_UPDATE_CONTEXT &&
                 cm_qp_req_type_reg == REQ_OPEN_QP &&
                 !bypass_valid) begin
      // Reset acked PSN when QP is opened
      qp_rem_acked_psn_mem[cm_qp_ptr] <= 24'd0;
    end
  end

  // -------------------------------------------------------------------------
  // State machine registers
  // -------------------------------------------------------------------------

  reg [2:0]  state_reg = STATE_IDLE;

  // Latched CM inputs
  reg [2:0]  cm_qp_req_type_reg;
  reg [31:0] cm_qp_r_key_reg;
  reg [23:0] cm_qp_rem_qpn_reg;
  reg [23:0] cm_qp_loc_qpn_reg;
  reg [23:0] cm_qp_rem_psn_reg;
  reg [23:0] cm_qp_loc_psn_reg;
  reg [31:0] cm_qp_rem_ip_addr_reg;
  reg [63:0] cm_qp_rem_addr_reg;

  // Address pointers
  reg [N_QP_W-1:0] cm_qp_ptr;
  reg [N_QP_W-1:0] qp_update_ptr;
  reg [N_QP_W-1:0] qp_close_ptr;

  // Misc latched
  reg [7:0]  qp_aeth_syndrome_reg;
  reg [23:0] qp_update_rem_psn_reg;
  reg [23:0] qp_close_rem_psn_reg;

  // Bypass context: after OPEN_QP writes INIT, avoid re-reading RAM for the RTS step.
  // bypass_valid=1 means STATE_UPDATE_CONTEXT should use bypass_ctx instead of ram_a_dout.
  reg                      bypass_valid;
  reg [CONTEXT_WIDTH-1:0]  bypass_ctx;

  // The effective context for the current processing state
  wire [CONTEXT_WIDTH-1:0] sm_ctx = bypass_valid ? bypass_ctx : ram_a_dout;

  // Status output registers
  reg        status_valid_r;
  reg        status_error_r;
  reg [2:0]  status_state_r;
  reg [31:0] status_r_key_r;
  reg [23:0] status_rem_qpn_r;
  reg [23:0] status_loc_qpn_r;
  reg [23:0] status_rem_psn_r;
  reg [23:0] status_loc_psn_r;
  reg [31:0] status_rem_ip_r;
  reg [63:0] status_rem_addr_r;

  // -------------------------------------------------------------------------
  // RX side: last acked/nacked PSN
  // -------------------------------------------------------------------------

  reg [23:0] rx_loc_qpn_reg;
  reg [23:0] last_acked_psn_reg;
  reg [23:0] last_nacked_psn_reg;
  reg        stop_transfer_reg;

  always @(posedge clk) begin
    if (rst_qp) begin
      rx_loc_qpn_reg      <= cm_qp_loc_qpn;
      last_acked_psn_reg  <= cm_qp_rem_psn;
      last_nacked_psn_reg <= cm_qp_rem_psn;
      stop_transfer_reg   <= 1'b0;
    end else begin
      if (s_roce_rx_aeth_valid && s_roce_rx_aeth_dest_qp == rx_loc_qpn_reg) begin
        if (s_roce_rx_aeth_syndrome[6:5] == 2'b00) begin
          last_acked_psn_reg <= s_roce_rx_aeth_psn;
          stop_transfer_reg  <= 1'b0;
        end else begin
          last_nacked_psn_reg <= s_roce_rx_aeth_psn;
          stop_transfer_reg   <= 1'b1;
        end
      end else begin
        stop_transfer_reg <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Main state machine
  // -------------------------------------------------------------------------

  always @(posedge clk) begin
    if (rst) begin
      state_reg    <= STATE_IDLE;
      ram_a_ren    <= 1'b0;
      ram_a_wen    <= 1'b0;
      bypass_valid <= 1'b0;
      status_valid_r <= 1'b0;
      status_error_r <= 1'b0;
    end else begin

      // Default: no RAM operation, no status pulse, no bypass
      ram_a_ren      <= 1'b0;
      ram_a_wen      <= 1'b0;
      ram_a_strb     <= {CONTEXT_BYTES{1'b1}};
      status_valid_r <= 1'b0;
      status_error_r <= 1'b0;
      bypass_valid   <= 1'b0;

      case (state_reg)

        // ------------------------------------------------------------------
        STATE_IDLE: begin
          // Priority: forced-close/error > PSN update > CM request

          if (s_qp_close_valid &&
              s_qp_close_loc_qpn[23:8] == 16'd1 &&
              s_qp_close_loc_qpn[7:N_QP_W] == 0) begin
            // Forced close → set QP to error state
            qp_aeth_syndrome_reg  <= {1'b1, 2'b00, 5'b11111}; // 8'h9F
            qp_close_ptr          <= s_qp_close_loc_qpn[N_QP_W-1:0];
            qp_close_rem_psn_reg  <= s_qp_close_rem_psn;
            ram_a_addr <= s_qp_close_loc_qpn[N_QP_W-1:0];
            ram_a_ren  <= 1'b1;
            state_reg  <= STATE_ERROR_QP;

          end else if (s_roce_rx_aeth_valid &&
                       s_roce_rx_aeth_dest_qp[23:8] == 16'd1 &&
                       s_roce_rx_aeth_dest_qp[7:N_QP_W] == 0 &&
                       s_roce_rx_aeth_syndrome[6:5] == 2'b11 &&
                       s_roce_rx_aeth_syndrome[4:0] != 5'b00000) begin
            // NAK (not PSN sequence error) → set QP to error state
            qp_aeth_syndrome_reg <= s_roce_rx_aeth_syndrome;
            qp_close_ptr         <= s_roce_rx_aeth_dest_qp[N_QP_W-1:0];
            ram_a_addr <= s_roce_rx_aeth_dest_qp[N_QP_W-1:0];
            ram_a_ren  <= 1'b1;
            state_reg  <= STATE_ERROR_QP;

          end else if (s_qp_update_context_valid &&
                       s_qp_update_loc_qpn[23:8] == 16'd1 &&
                       s_qp_update_loc_qpn[7:N_QP_W] == 0) begin
            // PSN update from ACK handler
            qp_update_rem_psn_reg <= s_qp_update_rem_psn;
            qp_update_ptr         <= s_qp_update_loc_qpn[N_QP_W-1:0];
            ram_a_addr <= s_qp_update_loc_qpn[N_QP_W-1:0];
            ram_a_ren  <= 1'b1;
            state_reg  <= STATE_UPDATE_QP;

          end else if (cm_qp_valid &&
                       cm_qp_loc_qpn[23:8] == 16'd1 &&
                       cm_qp_loc_qpn[7:N_QP_W] == 0) begin
            // Latch all CM inputs
            cm_qp_req_type_reg    <= cm_qp_req_type;
            cm_qp_r_key_reg       <= cm_qp_r_key;
            cm_qp_rem_qpn_reg     <= cm_qp_rem_qpn;
            cm_qp_loc_qpn_reg     <= cm_qp_loc_qpn;
            cm_qp_rem_psn_reg     <= cm_qp_rem_psn;
            cm_qp_loc_psn_reg     <= cm_qp_loc_psn;
            cm_qp_rem_ip_addr_reg <= cm_qp_rem_ip_addr;
            cm_qp_rem_addr_reg    <= cm_qp_rem_addr;
            cm_qp_ptr             <= cm_qp_loc_qpn[N_QP_W-1:0];
            qp_update_ptr         <= cm_qp_loc_qpn[N_QP_W-1:0];

            ram_a_addr <= cm_qp_loc_qpn[N_QP_W-1:0];
            ram_a_ren  <= 1'b1;

            case (cm_qp_req_type)
              REQ_OPEN_QP, REQ_MODIFY_QP_RTS: begin
                state_reg <= STATE_UPDATE_CONTEXT;
              end
              REQ_CLOSE_QP: begin
                qp_aeth_syndrome_reg <= 8'd0;
                qp_close_ptr         <= cm_qp_loc_qpn[N_QP_W-1:0];
                state_reg            <= STATE_UPDATE_CONTEXT;
              end
              REQ_FETCH_QP_INFO: begin
                state_reg <= STATE_READ_CONTEXT;
              end
              default: state_reg <= STATE_IDLE;
            endcase
          end
        end // STATE_IDLE

        // ------------------------------------------------------------------
        // ram_a_dout (or bypass_ctx) has the context read in the previous cycle.
        // Check validity, construct write-back, then return to IDLE.
        // Exception: after REQ_OPEN_QP succeeds we chain directly into MODIFY_RTS
        // using bypass_ctx so no extra RAM read is needed.
        // ------------------------------------------------------------------
        STATE_UPDATE_CONTEXT: begin

          case (cm_qp_req_type_reg)

            REQ_OPEN_QP: begin
              if (sm_ctx[QP_STATE_OFFSET +: 3] == QP_STATE_RESET) begin
                // Write INIT state back to RAM
                ram_a_addr <= cm_qp_ptr;
                ram_a_wen  <= 1'b1;
                ram_a_din[QP_STATE_OFFSET   +: 3 ] <= QP_STATE_INIT;
                ram_a_din[QP_STATE_OFFSET+3 +: 5 ] <= 5'd0;
                ram_a_din[REM_IPADDR_OFFSET +: 32] <= cm_qp_rem_ip_addr_reg;
                ram_a_din[REM_QPN_OFFSET    +: 24] <= cm_qp_rem_qpn_reg;
                ram_a_din[LOC_QPN_OFFSET    +: 24] <= cm_qp_loc_qpn_reg;
                ram_a_din[REM_PSN_OFFSET    +: 24] <= cm_qp_rem_psn_reg;
                ram_a_din[LOC_PSN_OFFSET    +: 24] <= cm_qp_loc_psn_reg;
                ram_a_din[VADDR_OFFSET      +: 64] <= cm_qp_rem_addr_reg;
                ram_a_din[RKEY_OFFSET       +: 32] <= cm_qp_r_key_reg;
                ram_a_din[SYNDROME_OFFSET   +: 8 ] <= 8'd0;
                ram_a_din[RESERVED_OFFSET   +: 16] <= 16'd0;

                // Chain into MODIFY_RTS without a RAM re-read (bypass)
                bypass_valid                         <= 1'b1;
                bypass_ctx[QP_STATE_OFFSET   +: 3 ] <= QP_STATE_INIT;
                bypass_ctx[QP_STATE_OFFSET+3 +: 5 ] <= 5'd0;
                bypass_ctx[REM_IPADDR_OFFSET +: 32] <= cm_qp_rem_ip_addr_reg;
                bypass_ctx[REM_QPN_OFFSET    +: 24] <= cm_qp_rem_qpn_reg;
                bypass_ctx[LOC_QPN_OFFSET    +: 24] <= cm_qp_loc_qpn_reg;
                bypass_ctx[REM_PSN_OFFSET    +: 24] <= cm_qp_rem_psn_reg;
                bypass_ctx[LOC_PSN_OFFSET    +: 24] <= cm_qp_loc_psn_reg;
                bypass_ctx[VADDR_OFFSET      +: 64] <= cm_qp_rem_addr_reg;
                bypass_ctx[RKEY_OFFSET       +: 32] <= cm_qp_r_key_reg;
                bypass_ctx[SYNDROME_OFFSET   +: 8 ] <= 8'd0;
                bypass_ctx[RESERVED_OFFSET   +: 16] <= 16'd0;

                cm_qp_req_type_reg <= REQ_MODIFY_QP_RTS;
                // Stay in UPDATE_CONTEXT; next cycle uses bypass_ctx
                state_reg <= STATE_UPDATE_CONTEXT;
              end else begin
                status_valid_r <= 1'b1;
                status_error_r <= 1'b1;
                state_reg      <= STATE_IDLE;
              end
            end

            REQ_MODIFY_QP_RTS: begin
              if (sm_ctx[QP_STATE_OFFSET +: 3] == QP_STATE_INIT) begin
                if (!qp_active_pipe[1]) begin
                  // Promote to RTS, preserve all other fields from context
                  ram_a_addr <= qp_update_ptr;
                  ram_a_wen  <= 1'b1;
                  ram_a_din[QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RTS;
                  ram_a_din[QP_STATE_OFFSET+3 +: 5 ] <= sm_ctx[QP_STATE_OFFSET+3 +: 5];
                  ram_a_din[REM_IPADDR_OFFSET +: 32] <= sm_ctx[REM_IPADDR_OFFSET +: 32];
                  ram_a_din[REM_QPN_OFFSET    +: 24] <= sm_ctx[REM_QPN_OFFSET    +: 24];
                  ram_a_din[LOC_QPN_OFFSET    +: 24] <= sm_ctx[LOC_QPN_OFFSET    +: 24];
                  ram_a_din[REM_PSN_OFFSET    +: 24] <= sm_ctx[REM_PSN_OFFSET    +: 24];
                  ram_a_din[LOC_PSN_OFFSET    +: 24] <= sm_ctx[LOC_PSN_OFFSET    +: 24];
                  ram_a_din[VADDR_OFFSET      +: 64] <= sm_ctx[VADDR_OFFSET      +: 64];
                  ram_a_din[RKEY_OFFSET       +: 32] <= sm_ctx[RKEY_OFFSET       +: 32];
                  ram_a_din[SYNDROME_OFFSET   +: 8 ] <= sm_ctx[SYNDROME_OFFSET   +: 8];
                  ram_a_din[RESERVED_OFFSET   +: 16] <= sm_ctx[RESERVED_OFFSET   +: 16];

                  status_valid_r    <= 1'b1;
                  status_error_r    <= 1'b0;
                  status_rem_qpn_r  <= sm_ctx[REM_QPN_OFFSET    +: 24];
                  status_rem_ip_r   <= sm_ctx[REM_IPADDR_OFFSET +: 32];
                end else begin
                  // Another QP already in RTS
                  status_valid_r <= 1'b1;
                  status_error_r <= 1'b1;
                end
              end else begin
                // QP not in INIT state
                status_valid_r <= 1'b1;
                status_error_r <= 1'b1;
              end
              state_reg <= STATE_IDLE;
            end

            REQ_CLOSE_QP: begin
              if (sm_ctx[QP_STATE_OFFSET +: 3] != QP_STATE_RESET) begin
                ram_a_addr <= qp_close_ptr;
                ram_a_wen  <= 1'b1;
                ram_a_din[QP_STATE_OFFSET   +: 3 ] <= QP_STATE_RESET;
                ram_a_din[QP_STATE_OFFSET+3 +: 5 ] <= sm_ctx[QP_STATE_OFFSET+3 +: 5];
                ram_a_din[REM_IPADDR_OFFSET +: 32] <= sm_ctx[REM_IPADDR_OFFSET +: 32];
                ram_a_din[REM_QPN_OFFSET    +: 24] <= sm_ctx[REM_QPN_OFFSET    +: 24];
                ram_a_din[LOC_QPN_OFFSET    +: 24] <= sm_ctx[LOC_QPN_OFFSET    +: 24];
                ram_a_din[REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
                ram_a_din[LOC_PSN_OFFSET    +: 24] <= sm_ctx[LOC_PSN_OFFSET    +: 24];
                ram_a_din[VADDR_OFFSET      +: 64] <= sm_ctx[VADDR_OFFSET      +: 64];
                ram_a_din[RKEY_OFFSET       +: 32] <= sm_ctx[RKEY_OFFSET       +: 32];
                ram_a_din[SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;
                ram_a_din[RESERVED_OFFSET   +: 16] <= sm_ctx[RESERVED_OFFSET   +: 16];

                status_valid_r   <= 1'b1;
                status_error_r   <= 1'b0;
                status_rem_qpn_r <= sm_ctx[REM_QPN_OFFSET    +: 24];
                status_rem_ip_r  <= sm_ctx[REM_IPADDR_OFFSET +: 32];
              end else begin
                status_valid_r <= 1'b1;
                status_error_r <= 1'b1;
              end
              state_reg <= STATE_IDLE;
            end

            default: state_reg <= STATE_IDLE;
          endcase
        end // STATE_UPDATE_CONTEXT

        // ------------------------------------------------------------------
        // PSN update: read-modify-write, update REM_PSN and clear syndrome
        // ------------------------------------------------------------------
        STATE_UPDATE_QP: begin
          ram_a_addr <= qp_update_ptr;
          ram_a_wen  <= 1'b1;
          ram_a_din[QP_STATE_OFFSET   +: 3 ] <= ram_a_dout[QP_STATE_OFFSET   +: 3];
          ram_a_din[QP_STATE_OFFSET+3 +: 5 ] <= ram_a_dout[QP_STATE_OFFSET+3 +: 5];
          ram_a_din[REM_IPADDR_OFFSET +: 32] <= ram_a_dout[REM_IPADDR_OFFSET +: 32];
          ram_a_din[REM_QPN_OFFSET    +: 24] <= ram_a_dout[REM_QPN_OFFSET    +: 24];
          ram_a_din[LOC_QPN_OFFSET    +: 24] <= ram_a_dout[LOC_QPN_OFFSET    +: 24];
          ram_a_din[REM_PSN_OFFSET    +: 24] <= qp_update_rem_psn_reg;
          ram_a_din[LOC_PSN_OFFSET    +: 24] <= ram_a_dout[LOC_PSN_OFFSET    +: 24];
          ram_a_din[VADDR_OFFSET      +: 64] <= ram_a_dout[VADDR_OFFSET      +: 64];
          ram_a_din[RKEY_OFFSET       +: 32] <= ram_a_dout[RKEY_OFFSET       +: 32];
          ram_a_din[SYNDROME_OFFSET   +: 8 ] <= 8'd0;
          ram_a_din[RESERVED_OFFSET   +: 16] <= ram_a_dout[RESERVED_OFFSET   +: 16];
          state_reg <= STATE_IDLE;
        end

        // ------------------------------------------------------------------
        // Error / NAK: set QP to error state, update PSN and syndrome
        // ------------------------------------------------------------------
        STATE_ERROR_QP: begin
          ram_a_addr <= qp_close_ptr;
          ram_a_wen  <= 1'b1;
          ram_a_din[QP_STATE_OFFSET   +: 3 ] <= QP_STATE_ERROR;
          ram_a_din[QP_STATE_OFFSET+3 +: 5 ] <= ram_a_dout[QP_STATE_OFFSET+3 +: 5];
          ram_a_din[REM_IPADDR_OFFSET +: 32] <= ram_a_dout[REM_IPADDR_OFFSET +: 32];
          ram_a_din[REM_QPN_OFFSET    +: 24] <= ram_a_dout[REM_QPN_OFFSET    +: 24];
          ram_a_din[LOC_QPN_OFFSET    +: 24] <= ram_a_dout[LOC_QPN_OFFSET    +: 24];
          ram_a_din[REM_PSN_OFFSET    +: 24] <= qp_close_rem_psn_reg;
          ram_a_din[LOC_PSN_OFFSET    +: 24] <= ram_a_dout[LOC_PSN_OFFSET    +: 24];
          ram_a_din[VADDR_OFFSET      +: 64] <= ram_a_dout[VADDR_OFFSET      +: 64];
          ram_a_din[RKEY_OFFSET       +: 32] <= ram_a_dout[RKEY_OFFSET       +: 32];
          ram_a_din[SYNDROME_OFFSET   +: 8 ] <= qp_aeth_syndrome_reg;
          ram_a_din[RESERVED_OFFSET   +: 16] <= ram_a_dout[RESERVED_OFFSET   +: 16];
          state_reg <= STATE_IDLE;
        end

        // ------------------------------------------------------------------
        // Context fetch: output RAM read result to CM status interface
        // ------------------------------------------------------------------
        STATE_READ_CONTEXT: begin
          status_valid_r  <= 1'b1;
          status_error_r  <= (ram_a_dout[QP_STATE_OFFSET +: 3] == QP_STATE_RESET) ||
                             (ram_a_dout[QP_STATE_OFFSET +: 3] == QP_STATE_ERROR);
          status_state_r  <= ram_a_dout[QP_STATE_OFFSET   +: 3];
          status_r_key_r  <= ram_a_dout[RKEY_OFFSET       +: 32];
          status_rem_qpn_r <= ram_a_dout[REM_QPN_OFFSET   +: 24];
          status_loc_qpn_r <= ram_a_dout[LOC_QPN_OFFSET   +: 24];
          status_rem_psn_r <= ram_a_dout[REM_PSN_OFFSET   +: 24];
          status_loc_psn_r <= ram_a_dout[LOC_PSN_OFFSET   +: 24];
          status_rem_ip_r  <= ram_a_dout[REM_IPADDR_OFFSET +: 32];
          status_rem_addr_r <= ram_a_dout[VADDR_OFFSET    +: 64];
          state_reg <= STATE_IDLE;
        end

        default: state_reg <= STATE_IDLE;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // Output assignments
  // -------------------------------------------------------------------------

  assign cm_qp_ready    = (state_reg == STATE_IDLE);
  assign cm_qp_status_valid       = status_valid_r;
  assign cm_qp_status             = {status_error_r, 1'b0};
  assign cm_qp_status_state       = status_state_r;
  assign cm_qp_status_r_key       = status_r_key_r;
  assign cm_qp_status_rem_qpn     = status_rem_qpn_r;
  assign cm_qp_status_loc_qpn     = status_loc_qpn_r;
  assign cm_qp_status_rem_psn     = status_rem_psn_r;
  assign cm_qp_status_loc_psn     = status_loc_psn_r;
  assign cm_qp_status_rem_ip_addr = status_rem_ip_r;
  assign cm_qp_status_rem_addr    = status_rem_addr_r;

  // Port B outputs (1-cycle pipeline)
  assign m_qp_context_req_valid       = b_valid_d1 && b_is_req_d1;
  assign m_qp_context_req_state       = ram_b_dout[QP_STATE_OFFSET   +: 3];
  assign m_qp_context_req_r_key       = ram_b_dout[RKEY_OFFSET       +: 32];
  assign m_qp_context_req_rem_qpn     = ram_b_dout[REM_QPN_OFFSET    +: 24];
  assign m_qp_context_req_loc_qpn     = ram_b_dout[LOC_QPN_OFFSET    +: 24];
  assign m_qp_context_req_rem_psn     = ram_b_dout[REM_PSN_OFFSET    +: 24];
  assign m_qp_context_req_loc_psn     = ram_b_dout[LOC_PSN_OFFSET    +: 24];
  assign m_qp_context_req_rem_ip_addr = ram_b_dout[REM_IPADDR_OFFSET +: 32];
  assign m_qp_context_req_rem_addr    = ram_b_dout[VADDR_OFFSET      +: 64];

  assign s_qp_spy_context_valid = b_valid_d1 && !b_is_req_d1;
  assign s_qp_spy_state         = ram_b_dout[QP_STATE_OFFSET   +: 3];
  assign s_qp_spy_r_key         = ram_b_dout[RKEY_OFFSET       +: 32];
  assign s_qp_spy_rem_qpn       = ram_b_dout[REM_QPN_OFFSET    +: 24];
  assign s_qp_spy_loc_qpn       = ram_b_dout[LOC_QPN_OFFSET    +: 24];
  assign s_qp_spy_rem_psn       = ram_b_dout[REM_PSN_OFFSET    +: 24];
  assign s_qp_spy_rem_acked_psn = b_spy_acked_psn_d1;
  assign s_qp_spy_loc_psn       = ram_b_dout[LOC_PSN_OFFSET    +: 24];
  assign s_qp_spy_rem_ip_addr   = ram_b_dout[REM_IPADDR_OFFSET +: 32];
  assign s_qp_spy_rem_addr      = ram_b_dout[VADDR_OFFSET      +: 64];
  assign s_qp_spy_syndrome      = ram_b_dout[SYNDROME_OFFSET   +: 8];

  assign s_qp_context_req_ready    = 1'b1;  // Port B is independent — always ready
  assign s_qp_update_context_ready = (state_reg == STATE_UPDATE_QP);
  assign s_qp_close_ready          = (state_reg == STATE_ERROR_QP);

  assign last_acked_psn  = last_acked_psn_reg;
  assign last_nacked_psn = last_nacked_psn_reg;
  assign stop_transfer   = stop_transfer_reg;

endmodule

`resetall
