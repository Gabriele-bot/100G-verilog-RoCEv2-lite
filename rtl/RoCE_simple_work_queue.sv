// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

module RoCE_simple_work_queue #
    (
    parameter MAX_QUEUE_PAIRS = 4,
    parameter QUEUE_LENGTH = 32
)(
    input wire clk,
    input wire rst,

    // Requests
    input  wire        s_wr_req_valid,
    output wire        s_wr_req_ready,
    input  wire [23:0] s_wr_req_loc_qp,
    input  wire [31:0] s_wr_req_dma_length,
    input  wire [63:0] s_wr_req_addr_offset,
    input  wire        s_wr_req_is_immediate,
    input  wire [31:0] s_wr_req_immediate_data,
    input  wire        s_wr_req_tx_type,

    // query qp context
    output wire        m_qp_context_req,
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
    output wire        m_transfer_type
);

    localparam MAX_QUEUE_PAIRS_WIDTH = $clog2(MAX_QUEUE_PAIRS);

    localparam [2:0]
    QP_STATE_RESET    = 3'd0,
    QP_STATE_INIT     = 3'd1,
    QP_STATE_RTR      = 3'd2,
    QP_STATE_RTS      = 3'd3,
    QP_STATE_SQ_DRAIN = 3'd4,
    QP_STATE_SQ_ERROR = 3'd5,
    QP_STATE_ERROR    = 3'd6;

    localparam [2:0]
    STATE_IDLE  = 3'd0,
    STATE_NEW_WORK_REQ   = 3'd1,
    STATE_WORK_REQ_SENT   = 3'd2;

    reg [2:0] state_reg = STATE_IDLE, state_next;

    reg [31:0] m_dma_length_fifo_out_reg;
    reg [63:0] m_rem_addr_offset_fifo_out_reg;
    reg        m_is_immediate_fifo_out_reg;
    reg [31:0] m_immediate_data_fifo_out_reg;
    reg        m_transfer_type_fifo_out_reg;

    reg        m_dma_meta_valid_reg;

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

    reg s_wr_req_ready_reg, s_wr_req_ready_next;

    assign m_qp_local_qpn_req = s_wr_req_loc_qp;
    assign s_wr_req_ready = s_wr_req_ready_reg;
    assign m_qp_context_req = s_wr_req_valid && s_wr_req_ready && (m_qp_local_qpn_req[23:8] == 16'd1 && m_qp_local_qpn_req[7:MAX_QUEUE_PAIRS_WIDTH] == 0);

    always @* begin

        

        s_wr_req_ready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                if (s_wr_req_valid && s_wr_req_ready) begin
                    if (s_wr_req_loc_qp[23:8] == 16'd1 && s_wr_req_loc_qp[7:MAX_QUEUE_PAIRS_WIDTH] == 0) begin // move only if loc qpn is in the rights range
                        state_next = STATE_NEW_WORK_REQ;
                    end
                end else begin
                    state_next = STATE_IDLE;
                    s_wr_req_ready_next = 1'b1;
                end
            end
            STATE_NEW_WORK_REQ: begin
                s_wr_req_ready_next = 1'b0;
                if (m_dma_meta_ready && m_dma_meta_valid) begin
                    state_next = STATE_WORK_REQ_SENT;
                end else if (s_qp_context_valid && s_qp_state != QP_STATE_RTS) begin
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_NEW_WORK_REQ;
                end
            end
            STATE_WORK_REQ_SENT: begin
                s_wr_req_ready_next = 1'b0;
                if (m_dma_meta_ready) begin
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WORK_REQ_SENT;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            m_dma_meta_valid_reg <= 1'b0;
        end else begin
            state_reg <= state_next;
            s_wr_req_ready_reg <= s_wr_req_ready_next;

            m_dma_meta_valid_reg <= m_dma_meta_ready & !m_dma_meta_valid_reg & s_qp_context_valid && s_qp_state == QP_STATE_RTS;
        end
    end

    always @(posedge clk) begin
        if (s_wr_req_valid && s_wr_req_ready) begin
            m_dma_length_fifo_out_reg       <= s_wr_req_dma_length;
            m_rem_addr_offset_fifo_out_reg  <= s_wr_req_addr_offset;
            m_immediate_data_fifo_out_reg   <= s_wr_req_immediate_data;
            m_is_immediate_fifo_out_reg     <= s_wr_req_is_immediate;
            m_transfer_type_fifo_out_reg    <= s_wr_req_tx_type;
        end

        if (s_qp_context_valid) begin
            m_rem_qpn_reg        <= s_qp_rem_qpn;
            m_loc_qpn_reg        <= s_qp_loc_qpn;
            m_rem_psn_reg        <= s_qp_rem_psn;
            m_dma_length_reg     <= m_dma_length_fifo_out_reg;
            m_r_key_reg          <= s_qp_r_key;
            m_rem_addr_reg       <= s_qp_rem_addr + m_rem_addr_offset_fifo_out_reg;
            m_rem_ip_addr_reg    <= s_qp_rem_ip_addr;
            m_immediate_data_reg <= m_immediate_data_fifo_out_reg;
            m_is_immediate_reg   <= m_is_immediate_fifo_out_reg;
            m_transfer_type_reg   <= m_transfer_type_fifo_out_reg;
        end

    end

    assign m_dma_meta_valid = m_dma_meta_valid_reg;
    assign m_dma_length     = m_dma_length_reg;
    assign m_rem_qpn        = m_rem_qpn_reg;
    assign m_loc_qpn        = m_loc_qpn_reg;
    assign m_rem_psn        = m_rem_psn_reg;
    assign m_r_key          = m_r_key_reg;
    assign m_rem_ip_addr    = m_rem_ip_addr_reg;
    assign m_rem_addr       = m_rem_addr_reg;
    assign m_immediate_data = m_immediate_data_reg;
    assign m_is_immediate   = m_is_immediate_reg;
    assign m_transfer_type  = m_transfer_type_reg;

endmodule
