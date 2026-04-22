// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

module RoCE_simple_work_queue #
    (
    parameter DATA_WIDTH          = 256,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    //local queue pair number
    parameter LOCAL_QPN            = 256,
    // refresh qp state every N clock ticks
    parameter REFRESH_CACHE_TICKS  = 16384
)(
    input wire clk,
    input wire rst,

    // axis stream
    input   wire [DATA_WIDTH   - 1 :0]  s_axis_tdata,
    input   wire [KEEP_WIDTH - 1 :0]    s_axis_tkeep,
    input   wire                        s_axis_tvalid,
    output  wire                        s_axis_tready,
    input   wire                        s_axis_tlast,
    input   wire [14:0]                 s_axis_tuser,

    // axis stream
    output  wire [DATA_WIDTH   - 1 :0]  m_axis_tdata,
    output  wire [KEEP_WIDTH - 1 :0]    m_axis_tkeep,
    output  wire                        m_axis_tvalid,
    input   wire                        m_axis_tready,
    output  wire                        m_axis_tlast,
    output  wire  [14:0]                m_axis_tuser,

    // Work Requests
    input  wire        s_wr_req_valid,
    output wire        s_wr_req_ready,
    input  wire [23:0] s_wr_req_loc_qp,
    input  wire [31:0] s_wr_req_dma_length,
    input  wire [63:0] s_wr_req_addr_offset,
    input  wire        s_wr_req_is_immediate,
    input  wire [31:0] s_wr_req_immediate_data,
    input  wire        s_wr_req_tx_type,

    // query qp context
    output wire        m_qp_context_req_valid,
    input  wire        m_qp_context_req_ready,
    output wire [23:0] m_qp_local_qpn_req,

    input wire        s_qp_context_valid,
    input wire [2 :0] s_qp_state,
    input wire [31:0] s_qp_r_key,
    input wire [23:0] s_qp_rem_qpn,
    input wire [23:0] s_qp_loc_qpn,
    input wire [23:0] s_qp_rem_psn,
    input wire [23:0] s_qp_loc_psn,
    input wire [31:0] s_qp_rem_ip_addr,
    input wire [63:0] s_qp_rem_addr,

    // Output, to Header FSM
    output wire        m_dma_meta_valid,
    input  wire        m_dma_meta_ready,
    output wire [31:0] m_dma_length,
    output wire [23:0] m_rem_qpn,
    output wire [23:0] m_loc_qpn,
    output wire [23:0] m_rem_psn,
    output wire [31:0] m_r_key,
    output wire [31:0] m_rem_ip_addr,
    output wire [63:0] m_rem_addr,
    output wire        m_is_immediate,
    output wire [31:0] m_immediate_data,
    output wire        m_transfer_type,

    // Update QP state output
    output wire        m_qp_update_context_valid,
    input wire         m_qp_update_context_ready,
    output wire [23:0] m_qp_update_context_loc_qpn,
    output wire [23:0] m_qp_update_context_rem_psn,

    // Status
    output wire        error_qp_not_rts,
    output wire [23:0] error_loc_qpn
);

    import RoCE_params::*; // Imports RoCE parameters

    localparam COOLDOWN_CLK_TICKS = 2;


    localparam [2:0]
    QP_STATE_RESET    = 3'd0,
    QP_STATE_INIT     = 3'd1,
    QP_STATE_RTR      = 3'd2,
    QP_STATE_RTS      = 3'd3,
    QP_STATE_SQ_DRAIN = 3'd4,
    QP_STATE_SQ_ERROR = 3'd5,
    QP_STATE_ERROR    = 3'd6;

    localparam [2:0]
    STATE_IDLE                 = 3'd0,
    STATE_LOAD_QP_CACHE        = 3'd1,
    STATE_WAIT_REQ_CD          = 3'd2,
    STATE_NEW_WORK_REQ         = 3'd3,
    STATE_WORK_REQ_SENT        = 3'd4,
    STATE_SEND_DATA            = 3'd5,
    STATE_DROP_AXIS            = 3'd6,
    STATE_UPDATE_QP_STATE_PSN  = 3'd7;

    reg [2:0] state_reg = STATE_IDLE, state_next;

    reg error_qp_not_rts_reg = 1'b0, error_qp_not_rts_next;
    reg [23:0] error_loc_qpn_reg = 24'd0, error_loc_qpn_next;

    reg [31:0] m_dma_length_fifo_out_reg;
    reg [63:0] m_rem_addr_offset_fifo_out_reg;
    reg        m_is_immediate_fifo_out_reg;
    reg [31:0] m_immediate_data_fifo_out_reg;
    reg        m_transfer_type_fifo_out_reg;

    reg        m_dma_meta_valid_reg, m_dma_meta_valid_next;

    reg [31:0] m_dma_length_reg;
    reg [23:0] m_rem_qpn_reg;
    reg [23:0] m_loc_qpn_reg;
    reg [23:0] m_rem_psn_reg;
    reg [31:0] m_r_key_reg;
    reg [31:0] m_rem_ip_addr_reg;
    reg [63:0] m_rem_addr_reg;
    reg        m_is_immediate_reg;
    reg [31:0] m_immediate_data_reg;
    reg        m_transfer_type_reg;

    reg [23:0] wr_loc_qpn_reg;

    // internal datapath
    reg  [DATA_WIDTH-1 : 0] m_axis_tdata_int;
    reg  [KEEP_WIDTH-1 : 0] m_axis_tkeep_int;
    reg                     m_axis_tvalid_int;
    reg                     m_axis_tready_int_reg = 1'b0;
    reg                     m_axis_tlast_int;
    reg [14:0]              m_axis_tuser_int;
    wire                    m_axis_tready_int_early;

    reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

    reg s_wr_req_ready_reg, s_wr_req_ready_next;

    reg        m_qp_context_req_valid_reg, m_qp_context_req_valid_next;
    reg [23:0] m_qp_local_qpn_req_reg, m_qp_local_qpn_req_next;

    reg last_end_of_frame;

    reg [2:0] qp_req_cooldown; // contex request must wait 6 clks after qp update;

    // QP state cache
    reg        cache_qp_active_next, cache_qp_active_reg;
    reg [2 :0] cache_qp_state_next, cache_qp_state_reg;
    reg [31:0] cache_qp_r_key_next, cache_qp_r_key_reg;
    reg [23:0] cache_qp_rem_qpn_next, cache_qp_rem_qpn_reg;
    reg [23:0] cache_qp_loc_qpn_next, cache_qp_loc_qpn_reg;
    reg [23:0] cache_qp_rem_psn_next, cache_qp_rem_psn_reg;
    reg [23:0] cache_qp_loc_psn_next, cache_qp_loc_psn_reg;
    reg [31:0] cache_qp_rem_ip_addr_next, cache_qp_rem_ip_addr_reg;
    reg [63:0] cache_qp_rem_addr_next, cache_qp_rem_addr_reg;

    // logic to refresh qp state table with cached values, once every REFRESH_CACHE_TICKS
    // First read the state then update the PSN if in RTS state
    reg [$clog2(REFRESH_CACHE_TICKS):0] refresh_counter_reg;

    reg [23:0] qp_update_context_loc_qpn_reg, qp_update_context_loc_qpn_next;
    reg [23:0] qp_update_context_rem_psn_reg, qp_update_context_rem_psn_next;
    reg        qp_update_context_valid_reg, qp_update_context_valid_next;

    assign s_axis_tready = s_axis_tready_reg;

    assign m_qp_local_qpn_req = m_qp_local_qpn_req_reg;
    assign s_wr_req_ready = s_wr_req_ready_reg;
    assign m_qp_context_req_valid = m_qp_context_req_valid_reg;

    always @* begin

        state_next = STATE_IDLE;

        s_wr_req_ready_next = 1'b0;

        cache_qp_active_next      = cache_qp_active_reg;
        cache_qp_state_next       = cache_qp_state_reg;
        cache_qp_r_key_next       = cache_qp_r_key_reg;
        cache_qp_rem_qpn_next     = cache_qp_rem_qpn_reg;
        cache_qp_loc_qpn_next     = cache_qp_loc_qpn_reg;
        cache_qp_rem_psn_next     = cache_qp_rem_psn_reg;
        cache_qp_loc_psn_next     = cache_qp_loc_psn_reg;
        cache_qp_rem_ip_addr_next = cache_qp_rem_ip_addr_reg;
        cache_qp_rem_addr_next    = cache_qp_rem_addr_reg;

        m_qp_context_req_valid_next = m_qp_context_req_valid_reg && !m_qp_context_req_ready;
        m_qp_local_qpn_req_next     = m_qp_local_qpn_req_reg;

        m_dma_meta_valid_next = m_dma_meta_valid_reg && !m_dma_meta_ready;

        qp_update_context_valid_next  =  qp_update_context_valid_reg && !m_qp_update_context_ready;
        qp_update_context_loc_qpn_next = qp_update_context_loc_qpn_reg;
        qp_update_context_rem_psn_next = qp_update_context_rem_psn_reg;

        error_qp_not_rts_next = 1'b0;
        error_loc_qpn_next = error_loc_qpn_reg;

        m_axis_tdata_int = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
        m_axis_tvalid_int = 1'b0;
        m_axis_tlast_int = 1'b0;
        m_axis_tuser_int = 1'b0;

        s_axis_tready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                s_wr_req_ready_next = 1'b1;
                if (s_wr_req_valid && s_wr_req_ready) begin
                    if (s_wr_req_loc_qp[23:8] == 16'd1 && s_wr_req_loc_qp[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin // move only if loc qpn is in the right range
                        s_wr_req_ready_next = 1'b0;
                        if (!cache_qp_active_reg) begin // QP not active, load QP CTX to cache (regs)
                            state_next = STATE_LOAD_QP_CACHE;
                            m_qp_context_req_valid_next = 1'b1;
                            m_qp_local_qpn_req_next = s_wr_req_loc_qp;
                        end else begin // QP active, fetch QP CTX from cache instead
                            if (qp_req_cooldown == 3'd0) begin
                                state_next = STATE_NEW_WORK_REQ;
                            end else begin
                                state_next = STATE_WAIT_REQ_CD;
                            end
                        end
                    end else begin
                        error_qp_not_rts_next = 1'b1;
                        error_loc_qpn_next = s_wr_req_loc_qp;
                        s_wr_req_ready_next = 1'b0;
                        state_next = STATE_DROP_AXIS;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_LOAD_QP_CACHE: begin
                s_wr_req_ready_next = 1'b0;
                if (s_qp_context_valid && s_qp_state == QP_STATE_RTS) begin // got reply from QP state table and QP is on RTS state
                    m_dma_meta_valid_next = 1'b1;
                    cache_qp_active_next = 1'b1;
                    // load ctx to cache
                    cache_qp_state_next       = s_qp_state;
                    cache_qp_r_key_next       = s_qp_r_key;
                    cache_qp_rem_qpn_next     = s_qp_rem_qpn;
                    cache_qp_loc_qpn_next     = s_qp_loc_qpn;
                    cache_qp_rem_psn_next     = s_qp_rem_psn;
                    cache_qp_loc_psn_next     = s_qp_loc_psn;
                    cache_qp_rem_ip_addr_next = s_qp_rem_ip_addr;
                    cache_qp_rem_addr_next    = s_qp_rem_addr;
                    state_next = STATE_WORK_REQ_SENT;
                end else if (s_qp_context_valid && s_qp_state != QP_STATE_RTS) begin // got reply from QP state table and QP is NOT on RTS state
                    error_qp_not_rts_next = 1'b1;
                    error_loc_qpn_next = wr_loc_qpn_reg;
                    cache_qp_active_next = 1'b0;
                    cache_qp_state_next  = s_qp_state;
                    state_next = STATE_DROP_AXIS;
                end else begin
                    state_next = STATE_LOAD_QP_CACHE;
                end
            end
            STATE_WAIT_REQ_CD: begin
                if (qp_req_cooldown == 3'd0) begin
                    state_next = STATE_NEW_WORK_REQ;
                end else begin
                    state_next = STATE_WAIT_REQ_CD;
                end
            end
            STATE_NEW_WORK_REQ: begin
                s_wr_req_ready_next = 1'b0;
                if (cache_qp_active_reg && cache_qp_state_reg == QP_STATE_RTS) begin
                    m_dma_meta_valid_next = 1'b1;
                    state_next = STATE_WORK_REQ_SENT;
                end else if (cache_qp_active_reg && cache_qp_state_reg != QP_STATE_RTS) begin
                    error_qp_not_rts_next = 1'b1;
                    error_loc_qpn_next = wr_loc_qpn_reg;
                    state_next = STATE_DROP_AXIS;
                end else begin
                    error_loc_qpn_next = wr_loc_qpn_reg;
                    state_next = STATE_DROP_AXIS;
                end
            end
            STATE_WORK_REQ_SENT: begin
                s_wr_req_ready_next = 1'b0;
                if (m_dma_meta_valid && m_dma_meta_ready) begin
                    s_axis_tready_next = m_axis_tready_int_early;
                    m_axis_tdata_int  = s_axis_tdata;
                    m_axis_tkeep_int  = s_axis_tkeep;
                    m_axis_tvalid_int = s_axis_tvalid && s_axis_tready;;
                    m_axis_tlast_int  = s_axis_tlast;
                    m_axis_tuser_int  = s_axis_tuser;
                    state_next = STATE_SEND_DATA;
                end else begin
                    state_next = STATE_WORK_REQ_SENT;
                end
            end
            STATE_SEND_DATA: begin
                s_wr_req_ready_next = 1'b0;
                s_axis_tready_next = m_axis_tready_int_early;
                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid && s_axis_tready;
                m_axis_tlast_int  = s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;
                if (s_axis_tvalid && s_axis_tready && s_axis_tlast && s_axis_tuser[1]) begin
                    if (refresh_counter_reg >= REFRESH_CACHE_TICKS) begin //trigger cache refresh
                        s_wr_req_ready_next = 1'b0;
                        s_axis_tready_next = 1'b0;
                        m_qp_context_req_valid_next = 1'b1;
                        m_qp_local_qpn_req_next = cache_qp_loc_qpn_reg;
                        state_next = STATE_UPDATE_QP_STATE_PSN;
                    end else begin
                        s_wr_req_ready_next = 1'b1; // if stall asserted, dont accept new work request
                        s_axis_tready_next = 1'b0;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_SEND_DATA;
                end
            end
            STATE_DROP_AXIS: begin
                s_wr_req_ready_next = 1'b0;
                m_axis_tvalid_int   = 1'b0;
                s_axis_tready_next  = 1'b1;
                if (s_axis_tvalid && s_axis_tready && s_axis_tlast && (|s_axis_tuser[1:0])) begin
                    s_wr_req_ready_next = 1'b0;
                    s_axis_tready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_DROP_AXIS;
                end
            end
            STATE_UPDATE_QP_STATE_PSN: begin
                if (s_qp_context_valid) begin
                    if (s_qp_state == QP_STATE_RTS || s_qp_state == QP_STATE_INIT) begin
                        // update cache qp state
                        cache_qp_state_next       = s_qp_state;
                        // update rem psn
                        qp_update_context_valid_next   = 1'b1;
                        qp_update_context_loc_qpn_next = cache_qp_loc_qpn_reg;
                        qp_update_context_rem_psn_next = cache_qp_rem_psn_reg;
                    end else begin
                        cache_qp_active_next = 1'b0;
                    end
                    s_wr_req_ready_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_UPDATE_QP_STATE_PSN;
                end
            end
        endcase
    end



    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axis_tready_reg <= 1'b0;

            m_dma_meta_valid_reg <= 1'b0;

            error_qp_not_rts_reg <= 1'b0;
            error_loc_qpn_reg <= 24'd0;

            wr_loc_qpn_reg                  <= 24'd0;
            m_dma_length_fifo_out_reg       <= 32'd0;
            m_rem_addr_offset_fifo_out_reg  <= 64'd0;
            m_immediate_data_fifo_out_reg   <= 32'd0;
            m_is_immediate_fifo_out_reg     <= 1'b0;
            m_transfer_type_fifo_out_reg    <= 1'b0;

            m_qp_context_req_valid_reg   <= 1'b0;
            m_qp_local_qpn_req_reg <= 24'd0;

        end else begin
            state_reg <= state_next;
            s_wr_req_ready_reg <= s_wr_req_ready_next;

            m_qp_context_req_valid_reg   <= m_qp_context_req_valid_next;
            m_qp_local_qpn_req_reg <= m_qp_local_qpn_req_next;


            s_axis_tready_reg <= s_axis_tready_next;

            m_dma_meta_valid_reg <= m_dma_meta_valid_next;

            error_qp_not_rts_reg <= error_qp_not_rts_next;
            error_loc_qpn_reg <= error_loc_qpn_next;

            if (s_wr_req_valid && s_wr_req_ready) begin
                wr_loc_qpn_reg                  <= s_wr_req_loc_qp;
                m_dma_length_fifo_out_reg       <= s_wr_req_dma_length;
                m_rem_addr_offset_fifo_out_reg  <= s_wr_req_addr_offset;
                m_immediate_data_fifo_out_reg   <= s_wr_req_immediate_data;
                m_is_immediate_fifo_out_reg     <= s_wr_req_is_immediate;
                m_transfer_type_fifo_out_reg    <= s_wr_req_tx_type;
            end
        end
    end

    assign error_qp_not_rts = error_qp_not_rts_reg;
    assign error_loc_qpn = error_loc_qpn_reg;

    assign m_dma_meta_valid = m_dma_meta_valid_reg;
    assign m_dma_length     = m_dma_length_fifo_out_reg;
    assign m_rem_qpn        = cache_qp_rem_qpn_reg;
    assign m_loc_qpn        = cache_qp_loc_qpn_reg;
    assign m_rem_psn        = cache_qp_rem_psn_reg;
    assign m_r_key          = cache_qp_r_key_reg;
    assign m_rem_ip_addr    = cache_qp_rem_ip_addr_reg;
    assign m_rem_addr       = cache_qp_rem_addr_reg + m_rem_addr_offset_fifo_out_reg;
    assign m_immediate_data = m_immediate_data_fifo_out_reg;
    assign m_is_immediate   = m_is_immediate_fifo_out_reg;
    assign m_transfer_type  = m_transfer_type_fifo_out_reg;

    // output datapath logic
    reg [DATA_WIDTH   - 1 :0] m_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] m_axis_tkeep_reg = 0;
    reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg         m_axis_tlast_reg = 1'b0;
    reg [14:0]  m_axis_tuser_reg = 15'd0;

    reg [DATA_WIDTH   - 1 :0] temp_m_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] temp_m_axis_tkeep_reg = 0;
    reg temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg temp_m_axis_tlast_reg = 1'b0;
    reg [14:0] temp_m_axis_tuser_reg = 15'd0;

    // datapath control
    reg store_int_to_output;
    reg store_int_to_temp;
    reg store_axis_temp_to_output;

    assign m_axis_tdata = m_axis_tdata_reg;
    assign m_axis_tkeep = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast = m_axis_tlast_reg;
    assign m_axis_tuser = m_axis_tuser_reg;

    assign m_axis_tready_int_early = m_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_int_to_output = 1'b0;
        store_int_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_tready_int_reg) begin
            // input is ready
            if (m_axis_tready | !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next  = m_axis_tvalid_int;
                store_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_tvalid_int;
                store_int_to_temp = 1'b1;
            end
        end else if (m_axis_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        m_axis_tready_int_reg <= m_axis_tready_int_early;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_int_to_output) begin
            m_axis_tdata_reg <= m_axis_tdata_int;
            m_axis_tkeep_reg <= m_axis_tkeep_int;
            m_axis_tlast_reg <= m_axis_tlast_int;
            m_axis_tuser_reg <= m_axis_tuser_int;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
            m_axis_tuser_reg <= temp_m_axis_tuser_reg;
        end

        if (store_int_to_temp) begin
            temp_m_axis_tdata_reg <= m_axis_tdata_int;
            temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
            temp_m_axis_tlast_reg <= m_axis_tlast_int;
            temp_m_axis_tuser_reg <= m_axis_tuser_int;
        end

        if (rst) begin
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tready_int_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end

    // update qp logic

    reg [23:0] rem_psn_add_reg,  rem_psn_add_next;
    reg [23:0] qp_cache_update_rem_psn_add_reg, qp_cache_update_rem_psn_add_next;
    reg        qp_cache_update_valid_reg,  qp_cache_update_valid_next;

    always @(*) begin

        rem_psn_add_next = rem_psn_add_reg;
        qp_cache_update_rem_psn_add_next = qp_cache_update_rem_psn_add_reg;
        qp_cache_update_valid_next = 1'b0;

        if (s_axis_tvalid && s_axis_tready && last_end_of_frame) begin
            rem_psn_add_next = rem_psn_add_reg + 24'd1;
            if (s_axis_tuser[1]) begin // last packet
                rem_psn_add_next = 24'd0;
                qp_cache_update_rem_psn_add_next = rem_psn_add_reg + 24'd1;
                qp_cache_update_valid_next = 1'b1;
            end
        end

    end

    always @(posedge clk) begin
        if (rst) begin
            rem_psn_add_reg <= 24'd0;

            qp_cache_update_valid_reg <= 1'b0;
            qp_cache_update_rem_psn_add_reg <= 24'd0;

            qp_update_context_valid_reg             <= 1'b0;
            qp_update_context_loc_qpn_reg           <= 24'd0;
            qp_update_context_rem_psn_reg           <= 24'd0;

            cache_qp_active_reg      <= 1'b0;
            cache_qp_state_reg       <= 3'd0;
            cache_qp_r_key_reg       <= 32'd0;
            cache_qp_rem_qpn_reg     <= 24'd0;
            cache_qp_loc_qpn_reg     <= 24'd0;
            cache_qp_rem_psn_reg     <= 24'd0;
            cache_qp_loc_psn_reg     <= 24'd0;
            cache_qp_rem_ip_addr_reg <= 32'd0;
            cache_qp_rem_addr_reg    <= 64'd0;

            qp_req_cooldown <= 3'd0;

            last_end_of_frame <= 1'b1;
        end else begin

            if (s_axis_tvalid && s_axis_tready) begin
                last_end_of_frame <= s_axis_tlast;
            end

            rem_psn_add_reg <= rem_psn_add_next;

            qp_cache_update_valid_reg       <= qp_cache_update_valid_next;
            qp_cache_update_rem_psn_add_reg <= qp_cache_update_rem_psn_add_next;

            qp_update_context_valid_reg             <= qp_update_context_valid_next;
            qp_update_context_loc_qpn_reg           <= qp_update_context_loc_qpn_next;
            qp_update_context_rem_psn_reg           <= qp_update_context_rem_psn_next;

            cache_qp_active_reg  <= cache_qp_active_next;
            cache_qp_state_reg   <= cache_qp_state_next;
            cache_qp_r_key_reg   <= cache_qp_r_key_next;
            cache_qp_rem_qpn_reg <= cache_qp_rem_qpn_next;
            cache_qp_loc_qpn_reg <= cache_qp_loc_qpn_next;
            if (qp_cache_update_valid_next) begin // update QPN ctx local psn cache triggered at the end of the packet transfer 
                cache_qp_rem_psn_reg <= cache_qp_rem_psn_next + qp_cache_update_rem_psn_add_next;
            end else begin
                cache_qp_rem_psn_reg <= cache_qp_rem_psn_next;
            end
            cache_qp_loc_psn_reg     <= cache_qp_loc_psn_next;
            cache_qp_rem_ip_addr_reg <= cache_qp_rem_ip_addr_next;
            cache_qp_rem_addr_reg    <= cache_qp_rem_addr_next;


            if (qp_update_context_valid_next) begin
                qp_req_cooldown <= COOLDOWN_CLK_TICKS;
            end else if (qp_req_cooldown == 3'd0) begin
                qp_req_cooldown <= 3'd0;
            end else begin
                qp_req_cooldown <= qp_req_cooldown - 3'd1;
            end

        end
    end



    always @(posedge clk) begin
        if (rst) begin
            refresh_counter_reg <= 0;
        end else begin
            if (cache_qp_active_reg) begin
                if (refresh_counter_reg >= REFRESH_CACHE_TICKS) begin
                    if (state_reg == STATE_UPDATE_QP_STATE_PSN) begin
                        refresh_counter_reg <= 0;
                    end
                end else begin
                    refresh_counter_reg <= refresh_counter_reg + 1;
                end
            end else begin
                refresh_counter_reg <= 0;
            end
        end
    end
    assign m_qp_update_context_valid   = qp_update_context_valid_reg;
    assign m_qp_update_context_loc_qpn = qp_update_context_loc_qpn_reg;
    assign m_qp_update_context_rem_psn = qp_update_context_rem_psn_reg;


endmodule
