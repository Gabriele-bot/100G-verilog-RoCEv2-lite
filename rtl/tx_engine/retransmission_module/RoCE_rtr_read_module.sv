`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_rtr_read_module #(
    parameter DATA_WIDTH = 64,
    parameter BUFFER_ADDR_WIDTH = 24,
    parameter HEADER_ADDR_WIDTH = BUFFER_ADDR_WIDTH - 8,
    parameter MAX_QPS = 4
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE RX ACKed PSNs
     */
    input  wire         s_roce_rx_aeth_valid,
    output wire         s_roce_rx_aeth_ready,
    input  wire [ 7 :0] s_roce_rx_aeth_syndrome,
    input  wire [ 23:0] s_roce_rx_bth_psn,
    input  wire [ 7 :0] s_roce_rx_bth_op_code,
    input  wire [ 23:0] s_roce_rx_bth_dest_qp,
    input  wire [ 23:0] s_roce_rx_last_not_acked_psn,

    /*
     * RoCE TX frame output
     */
    // BTH
    output  wire         m_roce_bth_valid,
    input   wire         m_roce_bth_ready,
    output  wire [  7:0] m_roce_bth_op_code,
    output  wire [ 15:0] m_roce_bth_p_key,
    output  wire [ 23:0] m_roce_bth_psn,
    output  wire [ 23:0] m_roce_bth_dest_qp,
    output  wire [ 23:0] m_roce_bth_src_qp,
    output  wire         m_roce_bth_ack_req,
    // RETH
    output  wire         m_roce_reth_valid,
    input   wire         m_roce_reth_ready,
    output  wire [ 63:0] m_roce_reth_v_addr,
    output  wire [ 31:0] m_roce_reth_r_key,
    output  wire [ 31:0] m_roce_reth_length,
    // IMMD
    output  wire         m_roce_immdh_valid,
    input wire           m_roce_immdh_ready,
    output  wire [ 31:0] m_roce_immdh_data,
    // udp, ip, eth
    output  wire [ 47:0] m_eth_dest_mac,
    output  wire [ 47:0] m_eth_src_mac,
    output  wire [ 15:0] m_eth_type,
    output  wire [  3:0] m_ip_version,
    output  wire [  3:0] m_ip_ihl,
    output  wire [  5:0] m_ip_dscp,
    output  wire [  1:0] m_ip_ecn,
    output  wire [ 15:0] m_ip_identification,
    output  wire [  2:0] m_ip_flags,
    output  wire [ 12:0] m_ip_fragment_offset,
    output  wire [  7:0] m_ip_ttl,
    output  wire [  7:0] m_ip_protocol,
    output  wire [ 15:0] m_ip_header_checksum,
    output  wire [ 31:0] m_ip_source_ip,
    output  wire [ 31:0] m_ip_dest_ip,
    output  wire [ 15:0] m_udp_source_port,
    output  wire [ 15:0] m_udp_dest_port,
    output  wire [ 15:0] m_udp_length,
    output  wire [ 15:0] m_udp_checksum,
    // payload
    output  wire [DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_roce_payload_axis_tkeep,
    output  wire                       m_roce_payload_axis_tvalid,
    input   wire                       m_roce_payload_axis_tready,
    output  wire                       m_roce_payload_axis_tlast,
    output  wire                       m_roce_payload_axis_tuser,
    /*
     * DMA Read command
     */
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axis_dma_read_desc_addr,
    output wire [12:0]                  m_axis_dma_read_desc_len,
    output wire                         m_axis_dma_read_desc_valid,
    input wire                          m_axis_dma_read_desc_ready,
    /*
     * DMA Read status
     */
    input wire [12:0]                  s_axis_dma_read_desc_status_len,
    input wire [3 :0]                  s_axis_dma_read_desc_status_error,
    input wire                         s_axis_dma_read_desc_status_valid,
    // DMA Read payload
    input  wire [DATA_WIDTH   - 1 :0] s_dma_read_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 :0] s_dma_read_axis_tkeep,
    input  wire                       s_dma_read_axis_tvalid,
    output wire                       s_dma_read_axis_tready,
    input  wire                       s_dma_read_axis_tlast,
    input  wire                       s_dma_read_axis_tuser,

    /*HEADER RAM read */
    output wire                         hdr_ram_re,
    output wire [HEADER_ADDR_WIDTH-1:0] hdr_ram_addr,
    input  wire [175:0]                 hdr_ram_data,
    input  wire                         hdr_ram_data_valid,
    /*
     Read table interfaces
     */
    output wire                       m_rd_table_we,
    output wire [$clog2(MAX_QPS)-1:0] m_rd_table_qpn, // used as address
    output wire [24-1:0]              m_rd_table_psn,

    output wire                        s_rd_table_re,
    output wire [$clog2(MAX_QPS)-1:0]  s_rd_table_qpn, // used as address
    input  wire [24-1:0]               s_rd_table_psn,
    /*
     Write table interface
     */
    output wire                        s_wr_table_re,
    output wire [$clog2(MAX_QPS)-1:0]  s_wr_table_qpn, // used as address
    input  wire [24-1:0]               s_wr_table_psn,
    /*
    Completion table interface
    */
    output wire                        s_cpl_table_re,
    output wire [$clog2(MAX_QPS)-1:0]  s_cpl_table_qpn, // used as address
    input  wire [24-1:0]               s_cpl_table_psn,
    /*
    Close QP in case failed transfer (e.g. rnr retry count reached, retry count reached, irreversible error)
    */
    output  wire         m_qp_close_valid,
    input   wire         m_qp_close_ready,
    output  wire [23:0]  m_qp_close_loc_qpn,
    output  wire [23:0]  m_qp_close_rem_psn,
    /*
    Open QP interface, needed only to store dest qp and dest ip address
    // TODO add reset counter and other qp related values upon opening
     */
    input  wire         s_qp_open_valid,
    input  wire [23:0]  s_qp_open_loc_qpn,
    input  wire [23:0]  s_qp_open_rem_qpn,
    input  wire [31:0]  s_qp_open_rem_ip_addr,

    output wire [MAX_QPS-1:0]  stall_qp, // asserted when qp memory is almost full 
    /*
    Configuration
    */
    input wire [31:0] loc_ip_addr,
    input wire [2 :0] pmtu,
    input wire [2 :0] retry_count,
    input wire [2 :0] rnr_retry_count,
    input wire [31:0] timeout_period,
    /*
    QP Status
    */
    input  wire [23:0]  monitor_qpn,
    output wire [31:0]  n_retransmit_triggers,
    output wire [31:0]  n_rnr_retransmit_triggers,
    output wire [23:0]  psn_diff // WR - CPL psn difference  
);

    import RoCE_params::*; // Imports RoCE parameters

    localparam RAM_OP_CODE_OFFSET   = 0;
    localparam RAM_PSN_OFFSET       = RAM_OP_CODE_OFFSET   + 8;
    localparam RAM_VADDR_OFFSET     = RAM_PSN_OFFSET       + 24;
    localparam RAM_RETH_LEN_OFFSET  = RAM_VADDR_OFFSET     + 64;
    localparam RAM_IMMD_DATA_OFFSET = RAM_RETH_LEN_OFFSET  + 32;
    localparam RAM_UDP_LEN_OFFSET   = RAM_IMMD_DATA_OFFSET + 32;
    localparam HEADER_MEMORY_SIZE   = RAM_UDP_LEN_OFFSET + 16; // in bits


    localparam QP_MEMORY_SIZE = 2**(BUFFER_ADDR_WIDTH)/MAX_QPS;

    localparam AXI_MAX_BURST_LEN_COMP = 4096/(DATA_WIDTH/8);
    localparam AXI_MAX_BURST_LEN = 256 <= AXI_MAX_BURST_LEN_COMP ? 256 : AXI_MAX_BURST_LEN_COMP;
    localparam BURST_SIZE = AXI_MAX_BURST_LEN * 8;


    localparam [3:0]
    STATE_CHECK_TIMEOUT   = 4'd0,
    STATE_FETCH_TABLES    = 4'd1,
    STATE_UPDATE_RD_TABLE = 4'd2,
    STATE_COMPARE         = 4'd3,
    STATE_FETCH_HDR       = 4'd4,
    STATE_SEND_HDR        = 4'd5,
    STATE_WAIT_DMA        = 4'd6,
    STATE_CHANGE_QPN      = 4'd7,
    STATE_WAIT_1CLK       = 4'd8;


    reg [3:0] state_reg = STATE_CHECK_TIMEOUT, state_next;
    reg [3:0] state_cached_reg = STATE_CHECK_TIMEOUT, state_cached_next;


    reg [3:0] memory_steps;
    reg [12:0] pmtu_val;
    reg [24-1:0] psn_stall_thr_stop; // threshold for qp stall
    reg [24-1:0] psn_stall_thr_release; // threshold for realease after stalling

    reg [$clog2(MAX_QPS)-1:0] round_robin_qpn_reg, round_robin_qpn_next;

    reg                         hdr_ram_re_reg, hdr_ram_re_next;
    reg [HEADER_ADDR_WIDTH-1:0] hdr_ram_addr_reg, hdr_ram_addr_next;

    reg                       m_rd_table_we_reg, m_rd_table_we_next;
    reg [$clog2(MAX_QPS)-1:0] m_rd_table_qpn_reg, m_rd_table_qpn_next;
    reg [24-1:0]              m_rd_table_psn_reg, m_rd_table_psn_next;

    reg                       s_rd_table_re_reg, s_rd_table_re_next;
    reg [$clog2(MAX_QPS)-1:0] s_rd_table_qpn_reg, s_rd_table_qpn_next;
    reg [24-1:0]              s_rd_table_psn_reg, s_rd_table_psn_next;

    reg                       s_wr_table_re_reg, s_wr_table_re_next;
    reg [$clog2(MAX_QPS)-1:0] s_wr_table_qpn_reg, s_wr_table_qpn_next;
    reg [24-1:0]              s_wr_table_psn_reg, s_wr_table_psn_next;

    reg                       s_cpl_table_re_reg,  s_cpl_table_re_next;
    reg [$clog2(MAX_QPS)-1:0] s_cpl_table_qpn_reg, s_cpl_table_qpn_next;
    reg [24-1:0]              s_cpl_table_psn_reg, s_cpl_table_psn_next;

    reg [BUFFER_ADDR_WIDTH-1:0] dma_read_desc_addr_reg,  dma_read_desc_addr_next;
    reg [12:0]                  dma_read_desc_len_reg ,  dma_read_desc_len_next;
    reg                         dma_read_desc_valid_reg, dma_read_desc_valid_next;
    wire                        dma_read_desc_ready;

    reg dma_rd_cmd_sent_reg, dma_rd_cmd_sent_next;

    reg [MAX_QPS-1:0] stall_qp_reg, stall_qp_next;

    reg          roce_bth_valid_next,   roce_bth_valid_reg;
    reg  [  7:0] roce_bth_op_code_next, roce_bth_op_code_reg;
    reg  [ 15:0] roce_bth_p_key_next,   roce_bth_p_key_reg;
    reg  [ 23:0] roce_bth_psn_next,     roce_bth_psn_reg;
    reg  [ 23:0] roce_bth_dest_qp_next, roce_bth_dest_qp_reg;
    reg  [ 23:0] roce_bth_src_qp_next,  roce_bth_src_qp_reg;
    reg          roce_bth_ack_req_next, roce_bth_ack_req_reg;

    reg          roce_reth_valid_next,  roce_reth_valid_reg;
    reg          roce_reth_ready_next,  roce_reth_ready_reg;
    reg  [ 63:0] roce_reth_v_addr_next, roce_reth_v_addr_reg;
    reg  [ 31:0] roce_reth_r_key_next,  roce_reth_r_key_reg;
    reg  [ 31:0] roce_reth_length_next, roce_reth_length_reg;

    reg          roce_immdh_valid_next, roce_immdh_valid_reg;
    reg          roce_immdh_ready_next, roce_immdh_ready_reg;
    reg  [ 31:0] roce_immdh_data_next,  roce_immdh_data_reg;

    reg  [ 15:0] udp_length_next, udp_length_reg;
    reg  [ 31:0] ip_dest_ip_next, ip_dest_ip_reg;

    reg [31:0] cached_dest_ip_reg [MAX_QPS-1:0];
    reg [23:0] cached_rem_qpn_reg [MAX_QPS-1:0];

    reg s_roce_rx_aeth_ready_reg;

    reg transmission_complete_reg, transmission_complete_next;

    reg [31:0] timeout_counter [MAX_QPS - 1 : 0];
    reg [31:0] rnr_counter_reg [MAX_QPS - 1 : 0] = '{default:0};
    reg [$clog2(MAX_QPS)-1:0] round_robin_qpn_timeout_reg;
    reg [MAX_QPS-1:0] qp_transmission_complete_reg, qp_transmission_complete_next;
    reg [MAX_QPS-1:0] qp_timed_out_reg;
    reg [MAX_QPS-1:0] qp_psn_error_reg;
    reg [MAX_QPS-1:0] qp_rnr_wait_reg;
    reg [MAX_QPS-1:0] qp_rnr_wait_done_reg;
    reg [MAX_QPS-1:0] qp_error_reg;
    reg [MAX_QPS-1:0] qp_closed_reg, qp_closed_next;
    reg [MAX_QPS-1:0] qp_started_retrans_reg, qp_started_retrans_next;
    reg [MAX_QPS-1:0] qp_started_rnr_retrans_reg, qp_started_rnr_retrans_next;

    reg [24-1:0]  psn_nak_reg [MAX_QPS-1:0];

    reg [2:0] retry_counter_reg     [MAX_QPS-1:0];
    reg [2:0] rnr_retry_counter_reg [MAX_QPS-1:0];
    reg [2:0] retry_counter_next     [MAX_QPS-1:0];
    reg [2:0] rnr_retry_counter_next [MAX_QPS-1:0];

    reg [23:0] retry_psn_mark_reg     [MAX_QPS-1:0];
    reg [23:0] retry_psn_mark_next    [MAX_QPS-1:0];

    reg [23:0] rnr_retry_psn_mark_reg  [MAX_QPS-1:0];
    reg [23:0] rnr_retry_psn_mark_next [MAX_QPS-1:0];

    reg [31:0] total_retry_counter_reg     [MAX_QPS-1:0];
    reg [31:0] total_rnr_retry_counter_reg [MAX_QPS-1:0];
    reg [31:0] total_retry_counter_next     [MAX_QPS-1:0];
    reg [31:0] total_rnr_retry_counter_next [MAX_QPS-1:0];

    reg m_qp_close_valid_reg, m_qp_close_valid_next;
    reg [23:0] m_qp_close_loc_qpn_reg, m_qp_close_loc_qpn_next;
    reg [23:0] m_qp_close_rem_psn_reg, m_qp_close_rem_psn_next;

    reg [31:0] n_retransmit_triggers_reg, n_retransmit_triggers_next;
    reg [31:0] n_rnr_retransmit_triggers_reg, n_rnr_retransmit_triggers_next;
    reg [23:0] psn_diff_reg, psn_diff_next;


    always @(posedge clk) begin
        memory_steps  <= 4'd8 + pmtu;
        pmtu_val      <= 13'd1 << ( pmtu + 13'd8);
        psn_stall_thr_stop    <= (QP_MEMORY_SIZE >> (4'd8 + pmtu)) - (MAX_QPS + 6); // too little slack?
        psn_stall_thr_release <= (QP_MEMORY_SIZE >> (4'd8 + pmtu)) - ((MAX_QPS << 1) + 6);
    end


    always @(*) begin

        state_next = STATE_CHANGE_QPN;

        round_robin_qpn_next = round_robin_qpn_reg;

        s_rd_table_re_next  = 1'b0;
        s_wr_table_re_next  = 1'b0;
        s_cpl_table_re_next = 1'b0;

        s_rd_table_qpn_next  = s_rd_table_qpn_reg;
        s_wr_table_qpn_next  = s_wr_table_qpn_reg;
        s_cpl_table_qpn_next = s_cpl_table_qpn_reg;

        m_rd_table_we_next  = 1'b0;
        m_rd_table_psn_next = m_rd_table_psn_reg;
        m_rd_table_qpn_next = m_rd_table_qpn_reg;

        hdr_ram_re_next   = 1'b0;
        hdr_ram_addr_next = hdr_ram_addr_reg;

        roce_bth_valid_next   = roce_bth_valid_reg && !m_roce_bth_ready;
        roce_bth_op_code_next = roce_bth_op_code_reg;
        roce_bth_p_key_next   = roce_bth_p_key_reg;
        roce_bth_psn_next     = roce_bth_psn_reg;
        roce_bth_dest_qp_next = roce_bth_dest_qp_reg;
        roce_bth_src_qp_next  = roce_bth_src_qp_reg;
        roce_bth_ack_req_next = roce_bth_ack_req_reg;

        roce_reth_valid_next  = roce_reth_valid_reg && !m_roce_reth_ready;;
        roce_reth_v_addr_next = roce_reth_v_addr_reg;
        roce_reth_r_key_next  = roce_reth_r_key_reg;
        roce_reth_length_next = roce_reth_length_reg;

        roce_immdh_valid_next = roce_immdh_valid_reg && !m_roce_immdh_ready;;
        roce_immdh_data_next  = roce_immdh_data_reg;

        udp_length_next       = udp_length_reg;

        ip_dest_ip_next = ip_dest_ip_reg;

        qp_transmission_complete_next = qp_transmission_complete_reg;

        dma_read_desc_valid_next = dma_read_desc_valid_reg && !dma_read_desc_ready;
        dma_read_desc_len_next   = dma_read_desc_len_reg;
        dma_read_desc_addr_next  = dma_read_desc_addr_reg;

        dma_rd_cmd_sent_next = dma_rd_cmd_sent_reg;

        stall_qp_next = stall_qp_reg;

        retry_counter_next           = retry_counter_reg;
        rnr_retry_counter_next       = rnr_retry_counter_reg;
        total_retry_counter_next     = total_retry_counter_reg;
        total_rnr_retry_counter_next = total_rnr_retry_counter_reg;

        retry_psn_mark_next = retry_psn_mark_reg;
        rnr_retry_psn_mark_next = rnr_retry_psn_mark_reg;

        m_qp_close_valid_next = m_qp_close_valid_reg && !m_qp_close_ready;
        m_qp_close_loc_qpn_next = m_qp_close_loc_qpn_reg;
        m_qp_close_rem_psn_next = m_qp_close_rem_psn_reg;

        qp_closed_next = qp_closed_reg;

        qp_started_retrans_next = qp_started_retrans_reg;
        qp_started_rnr_retrans_next = qp_started_rnr_retrans_reg;

        if (round_robin_qpn_reg == (monitor_qpn-256)) begin
            n_retransmit_triggers_next = total_retry_counter_reg[round_robin_qpn_reg];
            n_rnr_retransmit_triggers_next = total_rnr_retry_counter_reg[round_robin_qpn_reg];
        end else begin
            n_retransmit_triggers_next = n_retransmit_triggers_reg;
            n_rnr_retransmit_triggers_next = n_rnr_retransmit_triggers_reg;
        end
        psn_diff_next = psn_diff_reg;

        state_cached_next = state_cached_reg;

        case(state_reg)
            STATE_CHECK_TIMEOUT: begin
                // irreversible error happened, close qp
                if (qp_error_reg[round_robin_qpn_reg])begin
                    m_qp_close_valid_next = 1'b1;
                    m_qp_close_loc_qpn_next = 24'd256 + round_robin_qpn_reg;
                    qp_closed_next[round_robin_qpn_reg] = 1'b1;
                    qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                    qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                    state_next = STATE_CHANGE_QPN;
                end else begin
                    if (qp_rnr_wait_reg[round_robin_qpn_reg] && !qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // if qp in RNR wait compare table for checking if QP needs to be stalled, then skip to the next one
                        // TODO check rnr_retry_counter, if value reached (and not 7) trigger close qp
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                        state_next = STATE_FETCH_TABLES;
                        /*
                        if (rnr_retry_counter_reg[round_robin_qpn_reg] < rnr_retry_count || rnr_retry_count == 3'd7) begin
                            state_next = STATE_FETCH_TABLES;
                        end else begin
                            // rnr retry reached, close qp                        
                            m_qp_close_valid_next = 1'b1;
                            m_qp_close_loc_qpn_next = 24'd256 + round_robin_qpn_reg;
                            qp_closed_next[round_robin_qpn_reg] = 1'b1;
                            qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                            qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                            rnr_retry_psn_mark_next[round_robin_qpn_reg] = 24'd0; // to avoid continous rnr retransmission
                            state_cached_next = STATE_CHANGE_QPN;
                            state_next = STATE_WAIT_1CLK;
                        end
                        */
                    end else if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        // if timeout, bring rd pointer back to cpl pointer
                        // check retry count
                        if (retry_counter_reg[round_robin_qpn_reg] == retry_count) begin
                            // retry reached, close qp
                            m_qp_close_valid_next = 1'b1;
                            m_qp_close_loc_qpn_next = 24'd256 + round_robin_qpn_reg;
                            qp_closed_next[round_robin_qpn_reg] = 1'b1;
                            qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                            qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                            retry_psn_mark_next[round_robin_qpn_reg] = 24'd0; // to avoid continous retransmission
                            state_cached_next = STATE_CHANGE_QPN;
                            state_next = STATE_WAIT_1CLK;
                        end else begin
                            // trigger retrans
                            // read cpl table
                            s_cpl_table_re_next  = 1'b1;
                            s_cpl_table_qpn_next = round_robin_qpn_reg;
                            state_cached_next = STATE_UPDATE_RD_TABLE;
                            state_next = STATE_WAIT_1CLK;
                        end
                    end else if (qp_psn_error_reg[round_robin_qpn_reg] || qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // if got psn sequence error or rnr wait finised, bring rd table back to the nak psn, 
                        state_next = STATE_UPDATE_RD_TABLE;
                    end else begin
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                        // all good, read the tables
                        state_next = STATE_FETCH_TABLES;
                    end
                end
            end
            STATE_UPDATE_RD_TABLE : begin
                if (!m_rd_table_we_reg) begin
                    m_rd_table_we_next = 1'b1;
                    if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        // timeout
                        retry_psn_mark_next[round_robin_qpn_reg]      = s_cpl_table_psn + 1;
                        retry_counter_next[round_robin_qpn_reg]       = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg] = total_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next = s_cpl_table_psn;
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b1;
                    end else if (qp_psn_error_reg[round_robin_qpn_reg]) begin
                        // psn seq error
                        retry_psn_mark_next[round_robin_qpn_reg]      = psn_nak_reg[round_robin_qpn_reg];
                        retry_counter_next[round_robin_qpn_reg]       = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg] = total_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next = psn_nak_reg[round_robin_qpn_reg] - 1;
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b1;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                    end else if (qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // rnr wait finished
                        rnr_retry_psn_mark_next[round_robin_qpn_reg]      = psn_nak_reg[round_robin_qpn_reg];
                        rnr_retry_counter_next[round_robin_qpn_reg]       = rnr_retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_rnr_retry_counter_next[round_robin_qpn_reg] = total_rnr_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next = psn_nak_reg[round_robin_qpn_reg] - 1;
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b1;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b1;
                    end
                    m_rd_table_qpn_next = round_robin_qpn_reg;

                    state_next = STATE_UPDATE_RD_TABLE;
                end else begin // wait 1 clk
                    state_next = STATE_FETCH_TABLES;
                end
            end
            STATE_FETCH_TABLES : begin
                // read all tables
                if (!s_rd_table_re_reg) begin
                    s_rd_table_re_next  = 1'b1;
                    s_wr_table_re_next  = 1'b1;
                    s_cpl_table_re_next = 1'b1;

                    s_rd_table_qpn_next  = round_robin_qpn_reg;
                    s_wr_table_qpn_next  = round_robin_qpn_reg;
                    s_cpl_table_qpn_next = round_robin_qpn_reg;

                    state_next = STATE_FETCH_TABLES;
                end else begin // wait 1 clk
                    state_next = STATE_COMPARE;
                end
            end
            STATE_COMPARE: begin
                if (round_robin_qpn_reg == (monitor_qpn-256)) begin
                    psn_diff_next = s_wr_table_psn -  s_cpl_table_psn;
                end
                if (qp_closed_reg[round_robin_qpn_reg]) begin
                    qp_closed_next[round_robin_qpn_reg] = 1'b0;
                    // is this one necessary
                    retry_counter_next[round_robin_qpn_reg] = 3'd0;

                    state_next = STATE_CHANGE_QPN;
                end else begin
                    // if cpl table psn not eq than the psn mark (psn when retransmission is triggered) reset retry counter, it means that a avlid ACK is received 
                    if (s_cpl_table_psn != retry_psn_mark_reg[round_robin_qpn_reg] - 1) begin
                        retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    end
                    if (s_cpl_table_psn != rnr_retry_psn_mark_reg[round_robin_qpn_reg] - 1) begin
                        rnr_retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    end

                    // transmission complete, stop timeout counter for that QP
                    qp_transmission_complete_next[round_robin_qpn_reg] = s_cpl_table_psn == s_wr_table_psn;

                    // check psn for WR and RD
                    if (s_wr_table_psn == s_rd_table_psn) begin
                        // same pointers, do nothing
                        stall_qp_next[round_robin_qpn_reg] = 1'b0;
                        state_next = STATE_CHANGE_QPN;
                    end else begin
                        // pointers are not the same 
                        if (qp_rnr_wait_reg[round_robin_qpn_reg]) begin
                            // TODO what happens if this register changes in the middle of the state transistions STATE_CHECK_TIMEOUT --> STATE_FETCH_TABLES --> STATE_COMPARE?
                            // RNR wait still on going, skip to the next QP
                            state_next = STATE_CHANGE_QPN;
                        end else begin
                            //send read command to DMA, but first fetch header values
                            hdr_ram_re_next   = 1'b1;
                            hdr_ram_addr_next[HEADER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0]  = s_rd_table_psn[HEADER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0] + 1;
                            hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: $clog2(MAX_QPS)] = round_robin_qpn_reg[$clog2(MAX_QPS)-1:0];
                            stall_qp_next[round_robin_qpn_reg] = 1'b0;

                            state_next = STATE_FETCH_HDR;
                        end
                        if ((s_wr_table_psn -  s_cpl_table_psn) > psn_stall_thr_stop) begin
                            // wr pointer and cpl pointer diff too big, stall that QP
                            stall_qp_next[round_robin_qpn_reg] = 1'b1;
                        end else if (stall_qp_reg[round_robin_qpn_reg]) begin
                            if ((s_wr_table_psn -  s_cpl_table_psn) <= psn_stall_thr_release) begin
                                // isteresis
                                stall_qp_next[round_robin_qpn_reg] = 1'b0;
                            end else begin
                                stall_qp_next[round_robin_qpn_reg] = 1'b1;
                            end
                        end
                    end
                end


            end
            STATE_FETCH_HDR: begin
                if (hdr_ram_data_valid) begin
                    roce_bth_op_code_next = hdr_ram_data[RAM_OP_CODE_OFFSET+:8];
                    roce_bth_valid_next   = 1'b1;
                    roce_reth_valid_next  = roce_bth_op_code_next == RC_RDMA_WRITE_ONLY     ||
                    roce_bth_op_code_next == RC_RDMA_WRITE_ONLY_IMD ||
                    roce_bth_op_code_next == RC_RDMA_WRITE_FIRST;
                    roce_immdh_valid_next = roce_bth_op_code_next == RC_RDMA_WRITE_ONLY_IMD ||
                    roce_bth_op_code_next == RC_RDMA_WRITE_LAST_IMD ||
                    roce_bth_op_code_next == RC_SEND_ONLY_IMD       ||
                    roce_bth_op_code_next == RC_SEND_LAST_IMD;
                    roce_bth_psn_next     = hdr_ram_data[RAM_PSN_OFFSET+:24];
                    roce_bth_p_key_next   = 16'hFFFF;
                    roce_bth_dest_qp_next = cached_rem_qpn_reg[round_robin_qpn_reg];;
                    roce_bth_src_qp_next  = 24'd256 + round_robin_qpn_reg;
                    roce_bth_ack_req_next = 1'b1;
                    // RETH Fields
                    roce_reth_v_addr_next = hdr_ram_data[RAM_VADDR_OFFSET+:64];
                    roce_reth_length_next = hdr_ram_data[RAM_RETH_LEN_OFFSET+:32];
                    // Immdh field
                    roce_immdh_data_next = hdr_ram_data[RAM_IMMD_DATA_OFFSET+:32];
                    // UDP length
                    udp_length_next = hdr_ram_data[RAM_UDP_LEN_OFFSET+:16];

                    ip_dest_ip_next = cached_dest_ip_reg[round_robin_qpn_reg];

                    // DMA read command
                    dma_read_desc_valid_next = 1'b1;
                    if (dma_read_desc_ready) begin
                        dma_rd_cmd_sent_next = 1'b1;
                    end
                    if (roce_reth_valid_next && roce_immdh_valid_next) begin //bth reth immdh
                        dma_read_desc_len_next  =  hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 16 - 4 - 8;
                    end else if (roce_reth_valid_next && !roce_immdh_valid_next) begin //bth reth
                        dma_read_desc_len_next  =  hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 16 - 8;
                    end else if (!roce_reth_valid_next && roce_immdh_valid_next) begin // bth immdh
                        dma_read_desc_len_next  =  hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 4 - 8;
                    end else if (!roce_reth_valid_next && !roce_immdh_valid_next) begin // bth
                        dma_read_desc_len_next  =  hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 8;
                    end else begin
                        dma_read_desc_len_next  =  hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 8;
                    end
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0]  =  ((s_rd_table_psn + 1) << memory_steps);
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-1 -: $clog2(MAX_QPS)] =  round_robin_qpn_reg[$clog2(MAX_QPS)-1:0];

                    // now update read pointer
                    m_rd_table_we_next = 1'b1;
                    m_rd_table_psn_next = s_rd_table_psn + 1;
                    m_rd_table_qpn_next = round_robin_qpn_reg;

                    if (m_roce_bth_ready) begin
                        if (dma_read_desc_ready) begin
                            dma_rd_cmd_sent_next = 1'b0;
                            state_next = STATE_CHANGE_QPN;
                        end else begin
                            state_next = STATE_WAIT_DMA;
                        end
                    end else begin
                        state_next = STATE_SEND_HDR;
                    end
                end else begin
                    state_next = STATE_FETCH_HDR;
                end
            end
            STATE_SEND_HDR: begin
                if (m_roce_bth_valid & m_roce_bth_ready) begin
                    if (dma_rd_cmd_sent_reg) begin
                        // dma command already sent and header sent, go on
                        dma_rd_cmd_sent_next = 1'b0;
                        state_next = STATE_CHANGE_QPN;
                    end else begin
                        // dma command sent now and header sent, go on
                        if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                            dma_rd_cmd_sent_next = 1'b0;
                            state_next = STATE_CHANGE_QPN;
                        end else begin
                            // dma command not sent, wait dma
                            state_next = STATE_WAIT_DMA;
                        end
                    end
                end else begin
                    // header not sent
                    if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                        dma_rd_cmd_sent_next = 1'b1;
                    end
                    state_next = STATE_SEND_HDR;
                end
            end
            STATE_WAIT_DMA: begin
                if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                    dma_rd_cmd_sent_next = 1'b0;
                    state_next = STATE_CHANGE_QPN;
                end else begin
                    state_next = STATE_WAIT_DMA;
                end
            end
            STATE_CHANGE_QPN: begin
                // update control QPN
                round_robin_qpn_next = round_robin_qpn_reg + 1;
                state_next           = STATE_CHECK_TIMEOUT;
            end
            STATE_WAIT_1CLK: begin
                state_next = state_cached_reg;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg        <= STATE_CHECK_TIMEOUT;
            state_cached_reg <= STATE_CHECK_TIMEOUT;

            round_robin_qpn_reg  <= 'd0;

            s_rd_table_re_reg    <= 1'b0;
            s_wr_table_re_reg    <= 1'b0;
            s_cpl_table_re_reg   <= 1'b0;

            s_rd_table_qpn_reg   <= 'd0;
            s_wr_table_qpn_reg   <= 'd0;
            s_cpl_table_qpn_reg  <= 'd0;

            hdr_ram_re_reg   <= 1'b0;
            hdr_ram_addr_reg <= 'd0;

            roce_bth_valid_reg   <= 1'b0;
            roce_bth_op_code_reg <= 8'd0;
            roce_bth_p_key_reg   <= 16'hffff;
            roce_bth_psn_reg     <= 24'd0;
            roce_bth_dest_qp_reg <= 24'd0;
            roce_bth_src_qp_reg  <= 24'd0;
            roce_bth_ack_req_reg <= 1'b0;

            roce_reth_valid_reg  <= 1'b0;
            roce_reth_v_addr_reg <= 64'd0;
            roce_reth_r_key_reg  <= 32'd0;
            roce_reth_length_reg <= 32'd0;

            roce_immdh_valid_reg <= 1'b0;
            roce_immdh_data_reg  <= 32'd0;

            udp_length_reg       <= 16'd0;

            ip_dest_ip_reg       <= 32'd0;

            qp_transmission_complete_reg <= 'd0;

            dma_read_desc_valid_reg <= 1'b0;
            dma_read_desc_len_reg   <= 13'd0;
            dma_read_desc_addr_reg  <= 'd0;

            dma_rd_cmd_sent_reg <= 1'b0;

            stall_qp_reg <= 'd0;

            retry_counter_reg           <= '{default:0};
            rnr_retry_counter_reg       <= '{default:0};
            total_retry_counter_reg     <= '{default:0};
            total_rnr_retry_counter_reg <= '{default:0};

            round_robin_qpn_timeout_reg <= 'd0;
            qp_timed_out_reg            <= 'd0;
            qp_rnr_wait_reg             <= 'd0;
            qp_rnr_wait_done_reg        <= 'd0;
            qp_psn_error_reg            <= 'd0;
            qp_error_reg                <= 'd0;

            retry_psn_mark_reg <= '{default:0};

            m_qp_close_valid_reg   <= 1'b0;
            m_qp_close_loc_qpn_reg <= 'd0;
            m_qp_close_rem_psn_reg <= 'd0;

            qp_closed_reg <= 'd0;
            qp_started_retrans_reg <= 'd0;
            qp_started_rnr_retrans_reg <= 'd0;

            n_retransmit_triggers_reg <= 'd0;
            n_rnr_retransmit_triggers_reg <= 'd0;
            psn_diff_reg <= 'd0;

        end else begin
            state_reg        <= state_next;
            state_cached_reg <= state_cached_next;

            round_robin_qpn_reg  <= round_robin_qpn_next;

            m_rd_table_we_reg  <= m_rd_table_we_next;
            m_rd_table_qpn_reg <= m_rd_table_qpn_next;
            m_rd_table_psn_reg <= m_rd_table_psn_next;

            s_rd_table_re_reg    <= s_rd_table_re_next;
            s_wr_table_re_reg    <= s_wr_table_re_next;
            s_cpl_table_re_reg   <= s_cpl_table_re_next;

            s_rd_table_qpn_reg   <= s_rd_table_qpn_next;
            s_wr_table_qpn_reg   <= s_wr_table_qpn_next;
            s_cpl_table_qpn_reg  <= s_cpl_table_qpn_next;

            hdr_ram_re_reg       <= hdr_ram_re_next;
            hdr_ram_addr_reg     <= hdr_ram_addr_next;

            roce_bth_valid_reg   <= roce_bth_valid_next;
            roce_bth_op_code_reg <= roce_bth_op_code_next;
            roce_bth_p_key_reg   <= roce_bth_p_key_next;
            roce_bth_psn_reg     <= roce_bth_psn_next;
            roce_bth_dest_qp_reg <= roce_bth_dest_qp_next;
            roce_bth_src_qp_reg  <= roce_bth_src_qp_next;
            roce_bth_ack_req_reg <= roce_bth_ack_req_next;

            roce_reth_valid_reg  <= roce_reth_valid_next;
            roce_reth_v_addr_reg <= roce_reth_v_addr_next;
            roce_reth_r_key_reg  <= roce_reth_r_key_next;
            roce_reth_length_reg <= roce_reth_length_next;

            roce_immdh_valid_reg <= roce_immdh_valid_next;
            roce_immdh_data_reg  <= roce_immdh_data_next;

            udp_length_reg       <= udp_length_next;

            ip_dest_ip_reg       <= ip_dest_ip_next;

            qp_transmission_complete_reg <= qp_transmission_complete_next;

            dma_read_desc_valid_reg <= dma_read_desc_valid_next;
            dma_read_desc_len_reg   <= dma_read_desc_len_next;
            dma_read_desc_addr_reg  <= dma_read_desc_addr_next;

            dma_rd_cmd_sent_reg <= dma_rd_cmd_sent_next;

            stall_qp_reg <= stall_qp_next;

            retry_psn_mark_reg     <= retry_psn_mark_next;
            rnr_retry_psn_mark_reg <= rnr_retry_psn_mark_next;

            m_qp_close_valid_reg   <= m_qp_close_valid_next;
            m_qp_close_loc_qpn_reg <= m_qp_close_loc_qpn_next;
            m_qp_close_rem_psn_reg <= m_qp_close_rem_psn_next;

            qp_closed_reg <= qp_closed_next;
            qp_started_retrans_reg <= qp_started_retrans_next;
            qp_started_rnr_retrans_reg <= qp_started_rnr_retrans_next;

            retry_counter_reg           <= retry_counter_next;
            rnr_retry_counter_reg       <= rnr_retry_counter_next;
            total_retry_counter_reg     <= total_retry_counter_next;
            total_rnr_retry_counter_reg <= total_rnr_retry_counter_next;

            n_retransmit_triggers_reg <= n_retransmit_triggers_next;
            n_rnr_retransmit_triggers_reg <= n_rnr_retransmit_triggers_next;
            psn_diff_reg <= psn_diff_next;

            if (s_qp_open_valid) begin
                if (s_qp_open_loc_qpn >= 24'd256) begin
                    cached_dest_ip_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]] <= s_qp_open_rem_ip_addr;
                    cached_rem_qpn_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]] <= s_qp_open_rem_qpn;

                    // reset counters for that qp
                    retry_counter_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]]           <= 'd0;
                    rnr_retry_counter_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]]       <= 'd0;
                    total_retry_counter_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]]     <= 'd0;
                    total_rnr_retry_counter_reg[s_qp_open_loc_qpn[$clog2(MAX_QPS)-1:0]] <= 'd0;
                end
            end


            /*
            Timeout counters
            Decrease qp counter every clock cycle in a round robin fashion.
            Once a counter reaches zero retransmission is triggered.
            Reset counters under these conditions:
            - Retransmission is triggered
            - Recieved a valid ACK on that QP
            */
            // RNR counter logic
            if (qp_rnr_wait_reg[round_robin_qpn_timeout_reg] && !qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg]) begin
                // got a qp close request, reset coutner 
                if (qp_closed_reg[round_robin_qpn_timeout_reg]) begin
                    qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                    qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                end else begin
                    if (rnr_counter_reg[round_robin_qpn_timeout_reg] - MAX_QPS < 0 || rnr_counter_reg[round_robin_qpn_timeout_reg] == 0) begin
                        // RNR wait finished, deassert rnr wait bit and asser rnr wait done
                        rnr_counter_reg[round_robin_qpn_timeout_reg]      <= rnr_counter_reg[round_robin_qpn_timeout_reg];
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b1;
                        qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                    end else begin
                        // reduce counter by MAX_QPS (clock cycles required for a complete sweep)
                        rnr_counter_reg[round_robin_qpn_timeout_reg]      <= rnr_counter_reg[round_robin_qpn_timeout_reg] - MAX_QPS;
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b1;
                        qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                    end
                end
            end else begin
                // TODO FIX this
                if (qp_started_retrans_reg[round_robin_qpn_timeout_reg] && qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg]) begin
                    qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                    qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                end
            end

            // decode rx ACKs and timemout counter logic
            s_roce_rx_aeth_ready_reg <= 1'b0;
            if (s_roce_rx_aeth_valid && s_roce_rx_bth_op_code == RC_RDMA_ACK && (s_roce_rx_bth_dest_qp == round_robin_qpn_timeout_reg + 24'd256)) begin // process ack
                s_roce_rx_aeth_ready_reg <= 1'b1;
                qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                case(s_roce_rx_aeth_syndrome[6:5])
                    2'b00:begin // ACK
                    // reset counter
                        timeout_counter[round_robin_qpn_timeout_reg]      <= timeout_period;
                        qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                        qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        // reset rnr_retry_counter maybe?
                        rnr_counter_reg[round_robin_qpn_timeout_reg]  <= 3'd0;
                    end
                    2'b01:begin // RNR NAK
                    // load rnr_counter
                        psn_nak_reg[round_robin_qpn_timeout_reg]          <= s_roce_rx_bth_psn;
                        if (rnr_retry_counter_reg[round_robin_qpn_timeout_reg] < rnr_retry_count || rnr_retry_count == 3'd7) begin
                            timeout_counter[round_robin_qpn_timeout_reg]      <= RNR_TIMER_VALUES[s_roce_rx_aeth_syndrome[4:0]] + timeout_period;
                            rnr_counter_reg[round_robin_qpn_timeout_reg]      <= RNR_TIMER_VALUES[s_roce_rx_aeth_syndrome[4:0]];
                            qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
                            qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b1;
                            qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        end else begin
                            // rnr retry reached, error state
                            timeout_counter[round_robin_qpn_timeout_reg]      <= RNR_TIMER_VALUES[s_roce_rx_aeth_syndrome[4:0]] + timeout_period;
                            rnr_counter_reg[round_robin_qpn_timeout_reg]      <= RNR_TIMER_VALUES[s_roce_rx_aeth_syndrome[4:0]];
                            qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
                            qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                            qp_error_reg[round_robin_qpn_timeout_reg]         <= 1'b1;
                            qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        end
                    end
                    2'b10:begin // reserved, should not happen (ignore)
                        timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                        qp_psn_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]  <= 1'b0;
                    end
                    2'b11: begin // NAK
                        if (s_roce_rx_aeth_syndrome[4:0] == 5'b00000) begin
                            // PSN seq error
                            if (!qp_rnr_wait_reg[round_robin_qpn_timeout_reg]) begin
                                // if RNR was not triggered, otherwise ignore

                                if (retry_counter_reg[round_robin_qpn_timeout_reg] == 3'd7) begin
                                    // retry limit reached, close qp
                                    qp_error_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                                end else begin
                                    timeout_counter[round_robin_qpn_timeout_reg]      <= timeout_period;
                                    qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b1;
                                    qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                                    qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                                    psn_nak_reg[round_robin_qpn_timeout_reg]          <= s_roce_rx_bth_psn;
                                end
                            end

                        end else begin // force close qp
                            qp_error_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                        end
                    end
                    default: begin
                        timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                        qp_psn_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]  <= 1'b0;
                    end
                endcase
            end else if (timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS < MAX_QPS) begin
                if (qp_started_retrans_reg[round_robin_qpn_timeout_reg]) begin
                    // retransmision started, refresh counter and deassert flag
                    timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_period;
                    qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                end else begin
                    // timeout reached, trigger retransmision
                    timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg];
                    qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                end

            end else begin
                if (qp_transmission_complete_reg[round_robin_qpn_timeout_reg]) begin // sub optimal way of reading qp_transmission_complete_reg registers (1 bit per QP)
                // transmission complete, dont reduce counter
                    timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg];
                end else begin
                    // reduce counter by MAX_QPS (clock cycles required for a complete sweep)
                    timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                end
                qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b0;

            end

            if (qp_closed_reg[round_robin_qpn_timeout_reg]) begin
                qp_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_period;
                qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
            end

            if (qp_started_retrans_reg[round_robin_qpn_timeout_reg]) begin
                // deassert errors
                qp_psn_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
            end

            // next qp
            round_robin_qpn_timeout_reg <= round_robin_qpn_timeout_reg + 1;
        end
    end


    axis_fifo #(
        .DEPTH(8),
        .DATA_WIDTH  (BUFFER_ADDR_WIDTH+13),
        .KEEP_ENABLE (0),
        .LAST_ENABLE (0),
        .ID_ENABLE   (0),
        .DEST_ENABLE (0),
        .USER_ENABLE (0),
        .RAM_PIPELINE(1)
    ) dma_read_command_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata ({dma_read_desc_addr_reg, dma_read_desc_len_reg}),
        .s_axis_tvalid(dma_read_desc_valid_reg),
        .s_axis_tready(dma_read_desc_ready),
        .s_axis_tuser (0),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata ({m_axis_dma_read_desc_addr, m_axis_dma_read_desc_len}),
        .m_axis_tvalid(m_axis_dma_read_desc_valid),
        .m_axis_tready(m_axis_dma_read_desc_ready),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );

    axis_fifo #(
        .DEPTH(4096), // max packet size, it seems that the datamover doesn't like the tready going up and down during the transfer 
        //.DEPTH(BURST_SIZE),
        //.DEPTH(DATA_WIDTH/8*4),
        .DATA_WIDTH  (DATA_WIDTH),
        .KEEP_ENABLE (1),
        .KEEP_WIDTH  (DATA_WIDTH/8),
        .ID_ENABLE   (0),
        .DEST_ENABLE (0),
        .USER_ENABLE (1),
        .USER_WIDTH  (1),
        .RAM_PIPELINE(1),
        .FRAME_FIFO  (0)
    ) dma_read_payload_axis_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_dma_read_axis_tdata),
        .s_axis_tkeep (s_dma_read_axis_tkeep),
        .s_axis_tvalid(s_dma_read_axis_tvalid),
        .s_axis_tready(s_dma_read_axis_tready),
        .s_axis_tlast (s_dma_read_axis_tlast),
        .s_axis_tuser (s_dma_read_axis_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_roce_payload_axis_tdata),
        .m_axis_tkeep (m_roce_payload_axis_tkeep),
        .m_axis_tvalid(m_roce_payload_axis_tvalid),
        .m_axis_tready(m_roce_payload_axis_tready),
        .m_axis_tlast (m_roce_payload_axis_tlast),
        .m_axis_tuser (m_roce_payload_axis_tuser),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );


    assign m_roce_bth_valid = roce_bth_valid_reg;
    assign m_roce_bth_op_code = roce_bth_op_code_reg;
    assign m_roce_bth_p_key = roce_bth_p_key_reg;
    assign m_roce_bth_psn = roce_bth_psn_reg;
    assign m_roce_bth_dest_qp = roce_bth_dest_qp_reg;
    assign m_roce_bth_src_qp = roce_bth_src_qp_reg;
    assign m_roce_bth_ack_req = roce_bth_ack_req_reg;
    assign m_roce_reth_valid = roce_reth_valid_reg;
    assign m_roce_reth_v_addr = roce_reth_v_addr_reg;
    assign m_roce_reth_r_key = roce_reth_r_key_reg;
    assign m_roce_reth_length = roce_reth_length_reg;
    assign m_roce_immdh_valid = roce_immdh_valid_reg;
    assign m_roce_immdh_data = roce_immdh_data_reg;

    assign m_eth_dest_mac = 0;
    assign m_eth_src_mac = 0;
    assign m_eth_type = 0;
    assign m_ip_version = 4'd4;
    assign m_ip_ihl = 0;
    assign m_ip_dscp = 0;
    assign m_ip_ecn = 0;
    assign m_ip_identification = 0;
    assign m_ip_flags = 3'b001;
    assign m_ip_fragment_offset = 0;
    assign m_ip_ttl = 8'h40;
    assign m_ip_protocol = 8'h11;
    assign m_ip_header_checksum = 0;
    assign m_ip_dest_ip = ip_dest_ip_reg;
    assign m_ip_source_ip = loc_ip_addr;

    assign m_udp_length      = udp_length_reg;
    assign m_udp_checksum    =   16'd0;
    assign m_udp_source_port = 16'd0;
    assign m_udp_dest_port   = ROCE_UDP_PORT;

    assign  m_rd_table_we  = m_rd_table_we_reg;
    assign  m_rd_table_qpn = m_rd_table_qpn_reg;
    assign  m_rd_table_psn = m_rd_table_psn_reg;

    assign s_rd_table_re  = s_rd_table_re_reg;
    assign s_rd_table_qpn = s_rd_table_qpn_reg;

    assign s_wr_table_re  = s_wr_table_re_reg;
    assign s_wr_table_qpn = s_wr_table_qpn_reg;

    assign s_cpl_table_re  = s_cpl_table_re_reg;
    assign s_cpl_table_qpn = s_cpl_table_qpn_reg;

    assign hdr_ram_re   = hdr_ram_re_reg;
    assign hdr_ram_addr = hdr_ram_addr_reg;

    assign s_roce_rx_aeth_ready = s_roce_rx_aeth_ready_reg;

    assign stall_qp = stall_qp_reg;

    assign m_qp_close_valid = m_qp_close_valid_reg;
    assign m_qp_close_loc_qpn = m_qp_close_loc_qpn_reg;
    assign m_qp_close_rem_psn = 0;

    assign n_retransmit_triggers     = n_retransmit_triggers_reg;
    assign n_rnr_retransmit_triggers = n_rnr_retransmit_triggers_reg;
    assign psn_diff                  = psn_diff_reg;


endmodule

`resetall