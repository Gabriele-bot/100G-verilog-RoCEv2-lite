`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_rtr_read_module #(
    parameter DATA_WIDTH = 64,
    parameter BUFFER_ADDR_WIDTH = 24,
    parameter HEADER_ADDR_WIDTH = BUFFER_ADDR_WIDTH - 8,
    parameter BASE_LOC_QPN = 256,
    parameter MAX_QPS = 4,
    parameter MAX_QPS_WIDTH = MAX_QPS > 1 ? $clog2(MAX_QPS) : 1,
    parameter EN_DCQCN_LOGIC = 1,
    parameter RD_CMD_FIFO_DEPTH = 8,
    parameter RD_AXIS_DATAMOVER_FIFO_DEPTH = 4096,
    parameter CLOCK_PERIOD = 3.000 // in ns 
) (
    input wire clk,
    input wire rst,

    input wire flow_ctrl_pause, // halt timeout counter when pause is active

    /*
     * RoCE RX ACKed PSNs
     */
    input  wire         s_roce_rx_aeth_valid,
    output wire         s_roce_rx_aeth_ready,
    input  wire [ 7 :0] s_roce_rx_aeth_syndrome,
    input  wire [ 23:0] s_roce_rx_aeth_psn,
    input  wire [ 23:0] s_roce_rx_aeth_dest_qp,

    /*
     * RoCE RX CNP
     */
    input  wire         s_roce_rx_cnp_valid,
    output wire         s_roce_rx_cnp_ready,
    input  wire [ 23:0] s_roce_rx_cnp_dest_qp,

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
    output wire [MAX_QPS_WIDTH-1:0]   m_rd_table_qpn, // used as address
    output wire [24-1:0]              m_rd_table_psn,

    output wire                        s_rd_table_re,
    output wire [MAX_QPS_WIDTH-1:0]    s_rd_table_qpn, // used as address
    input  wire [24-1:0]               s_rd_table_psn,
    /*
     Write table interface
     */
    output wire                        s_wr_table_re,
    output wire [MAX_QPS_WIDTH-1:0]    s_wr_table_qpn, // used as address
    input  wire [24-1:0]               s_wr_table_psn,
    /*
    Completion table interface
    */
    output wire                        s_cpl_table_re,
    output wire [MAX_QPS_WIDTH-1:0]    s_cpl_table_qpn, // used as address
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
    input  wire [31:0]  s_qp_open_r_key,
    input  wire [31:0]  s_qp_open_rem_ip_addr,
    /*
    Configuration
    */
    input wire [31:0] loc_ip_addr,
    input wire [2 :0] pmtu,
    input wire [2 :0] retry_count,
    input wire [2 :0] rnr_retry_count,
    input wire [31:0] timeout_period,

    // dcqcn
    input wire        dcqcn_en,
    input wire [9:0]  dcqcn_par_g,
    input wire [9:0]  dcqcn_alpha_min,
    input wire [31:0] dcqcn_alpha_upd_time,
    input wire [9:0]  dcqcn_rate_decr_min,
    input wire [10:0] dcqcn_rate_min,
    input wire [31:0] dcqcn_upd_time,
    input wire [31:0] dcqcn_rate_ai_time,
    input wire [31:0] dcqcn_rate_hai_time,
    input wire [9:0]  dcqcn_rate_incr_ai,
    input wire [9:0]  dcqcn_rate_incr_hai,
    /*
    QP Status
    */
    input  wire [23:0]  monitor_qpn,
    output wire [31:0]  n_retransmit_triggers,
    output wire [31:0]  n_rnr_retransmit_triggers,
    output wire [31:0]  n_total_psn_seq_errors,
    output wire [31:0]  n_total_timeout_errors
);

    import RoCE_params::*; // Imports RoCE parameters

    localparam RnrTimerValues_t RNR_TIMER_VALUES = getRNRtimercounts(CLOCK_PERIOD);

    // BTH
    localparam RAM_OP_CODE_OFFSET   = 0;
    localparam RAM_PSN_OFFSET       = RAM_OP_CODE_OFFSET   + 8;
    // RETH
    localparam RAM_VADDR_OFFSET     = RAM_PSN_OFFSET       + 24;
    localparam RAM_RETH_LEN_OFFSET  = RAM_VADDR_OFFSET     + 64;
    // IMMD
    localparam RAM_IMMD_DATA_OFFSET = RAM_RETH_LEN_OFFSET  + 32;
    // UDP
    localparam RAM_UDP_LEN_OFFSET   = RAM_IMMD_DATA_OFFSET + 32;
    // Total size
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

    reg [MAX_QPS_WIDTH-1:0] round_robin_qpn_reg, round_robin_qpn_next;

    reg                         hdr_ram_re_reg, hdr_ram_re_next;
    reg [HEADER_ADDR_WIDTH-1:0] hdr_ram_addr_reg, hdr_ram_addr_next;

    reg                     m_rd_table_we_reg, m_rd_table_we_next;
    reg [MAX_QPS_WIDTH-1:0] m_rd_table_qpn_reg, m_rd_table_qpn_next;
    reg [24-1:0]            m_rd_table_psn_reg, m_rd_table_psn_next;

    reg                     s_rd_table_re_reg, s_rd_table_re_next;
    reg [MAX_QPS_WIDTH-1:0] s_rd_table_qpn_reg, s_rd_table_qpn_next;
    reg [24-1:0]            s_rd_table_psn_reg, s_rd_table_psn_next;

    reg                     s_wr_table_re_reg, s_wr_table_re_next;
    reg [MAX_QPS_WIDTH-1:0] s_wr_table_qpn_reg, s_wr_table_qpn_next;
    reg [24-1:0]            s_wr_table_psn_reg, s_wr_table_psn_next;

    reg                     s_cpl_table_re_reg,  s_cpl_table_re_next;
    reg [MAX_QPS_WIDTH-1:0] s_cpl_table_qpn_reg, s_cpl_table_qpn_next;
    reg [24-1:0]            s_cpl_table_psn_reg, s_cpl_table_psn_next;

    reg [BUFFER_ADDR_WIDTH-1:0] dma_read_desc_addr_reg,  dma_read_desc_addr_next;
    reg [12:0]                  dma_read_desc_len_reg ,  dma_read_desc_len_next;
    reg                         dma_read_desc_valid_reg, dma_read_desc_valid_next;
    wire                        dma_read_desc_ready;

    reg dma_rd_cmd_sent_reg, dma_rd_cmd_sent_next;

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
    reg [31:0] cached_r_key_reg   [MAX_QPS-1:0];

    reg s_roce_rx_aeth_ready_reg;
    reg s_roce_rx_cnp_ready_reg;

    reg transmission_complete_reg, transmission_complete_next;

    reg [31:0] timeout_counter [MAX_QPS - 1 : 0];
    reg [31:0] rnr_counter_reg [MAX_QPS - 1 : 0] = '{default:0};
    reg [MAX_QPS_WIDTH-1:0] round_robin_qpn_timeout_reg;
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

    reg [31:0] total_retry_counter_reg      [MAX_QPS-1:0];
    reg [31:0] total_retry_counter_next     [MAX_QPS-1:0];
    reg [31:0] total_rnr_retry_counter_reg  [MAX_QPS-1:0];
    reg [31:0] total_rnr_retry_counter_next [MAX_QPS-1:0];
    reg [31:0] total_psn_seq_errors_next    [MAX_QPS-1:0];
    reg [31:0] total_psn_seq_errors_reg     [MAX_QPS-1:0];
    reg [31:0] total_timeout_errors_next    [MAX_QPS-1:0];
    reg [31:0] total_timeout_errors_reg     [MAX_QPS-1:0];

    reg m_qp_close_valid_reg, m_qp_close_valid_next;
    reg [23:0] m_qp_close_loc_qpn_reg, m_qp_close_loc_qpn_next;
    reg [23:0] m_qp_close_rem_psn_reg, m_qp_close_rem_psn_next;

    reg [31:0] n_retransmit_triggers_reg, n_retransmit_triggers_next;
    reg [31:0] n_rnr_retransmit_triggers_reg, n_rnr_retransmit_triggers_next;
    reg [31:0] n_total_psn_seq_errors_reg, n_total_psn_seq_errors_next;
    reg [31:0] n_total_timeout_errors_reg, n_total_timeout_errors_next;

    reg flow_ctrl_pause_reg, flow_ctrl_pause_next;

    wire         roce_bth_valid;
    wire         roce_bth_ready;
    wire [  7:0] roce_bth_op_code;
    wire [ 15:0] roce_bth_p_key;
    wire [ 23:0] roce_bth_psn;
    wire [ 23:0] roce_bth_dest_qp;
    wire [ 23:0] roce_bth_src_qp;
    wire         roce_bth_ack_req;
    wire         roce_reth_valid;
    wire         roce_reth_ready;
    wire [ 63:0] roce_reth_v_addr;
    wire [ 31:0] roce_reth_r_key;
    wire [ 31:0] roce_reth_length;
    wire         roce_immdh_valid;
    wire         roce_immdh_ready;
    wire [ 31:0] roce_immdh_data;

    wire [ 47:0] eth_dest_mac;
    wire [ 47:0] eth_src_mac;
    wire [ 15:0] eth_type;
    wire [  3:0] ip_version;
    wire [  3:0] ip_ihl;
    wire [  5:0] ip_dscp;
    wire [  1:0] ip_ecn;
    wire [ 15:0] ip_identification;
    wire [  2:0] ip_flags;
    wire [ 12:0] ip_fragment_offset;
    wire [  7:0] ip_ttl;
    wire [  7:0] ip_protocol;
    wire [ 15:0] ip_header_checksum;
    wire [ 31:0] ip_source_ip;
    wire [ 31:0] ip_dest_ip;
    wire [ 15:0] udp_source_port;
    wire [ 15:0] udp_dest_port;
    wire [ 15:0] udp_length;
    wire [ 15:0] udp_checksum;

    // DCQCN_STUFF
    localparam  PACKET_COST = 1023;
    reg [11:0] credit_next    [MAX_QPS-1:0];
    reg [11:0] credit_reg     [MAX_QPS-1:0];

    wire [10:0]  rate_lim     [MAX_QPS-1:0];
    reg  [10:0]  rate_lim_reg [MAX_QPS-1:0];

    reg rx_cnp_reg;
    reg [23:0] rx_cnp_qpn_reg;

    generate
        for (genvar i = 0; i < MAX_QPS; i++) begin : gen_dcqcn

            wire rx_cnp = rx_cnp_reg && rx_cnp_qpn_reg == (i + BASE_LOC_QPN);

            if (EN_DCQCN_LOGIC) begin
                RoCE_dcqcn RoCE_dcqcn_instance (
                    .clk(clk),
                    .rst(rst),
                    .rx_cnp(rx_cnp),
                    .rate_lim(rate_lim[i]),

                    .par_alpha_g          (dcqcn_par_g), // correspond to 1019 DcQcnDceAlphaG mlnx value
                    .par_alpha_min        (dcqcn_alpha_min),
                    .par_alpha_update_time(dcqcn_alpha_upd_time),

                    .par_rate_decr_min(dcqcn_rate_decr_min),
                    .par_rate_min     (dcqcn_rate_min),

                    .par_rate_update_time(dcqcn_upd_time),
                    .par_rate_ai_time    (dcqcn_rate_ai_time),
                    .par_rate_hai_time   (dcqcn_rate_hai_time),
                    .par_rate_incr_ai    (dcqcn_rate_incr_ai),
                    .par_rate_incr_hai   (dcqcn_rate_incr_hai)
                );

                always @(posedge clk) begin
                    rate_lim_reg[i] <= rate_lim[i];
                end

            end else begin
                always @(posedge clk) begin
                    rate_lim_reg[i] <= 11'h3ff;
                end
            end

        end
    endgenerate


    always @(posedge clk) begin
        memory_steps          <= 4'd8 + pmtu;
        pmtu_val              <= 13'd1 << ( pmtu + 13'd8);
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

        roce_bth_valid_next   = roce_bth_valid_reg && !roce_bth_ready;
        roce_bth_op_code_next = roce_bth_op_code_reg;
        roce_bth_p_key_next   = roce_bth_p_key_reg;
        roce_bth_psn_next     = roce_bth_psn_reg;
        roce_bth_dest_qp_next = roce_bth_dest_qp_reg;
        roce_bth_src_qp_next  = roce_bth_src_qp_reg;
        roce_bth_ack_req_next = roce_bth_ack_req_reg;

        roce_reth_valid_next  = roce_reth_valid_reg && !roce_bth_ready;;
        roce_reth_v_addr_next = roce_reth_v_addr_reg;
        roce_reth_r_key_next  = roce_reth_r_key_reg;
        roce_reth_length_next = roce_reth_length_reg;

        roce_immdh_valid_next = roce_immdh_valid_reg && !roce_bth_ready;;
        roce_immdh_data_next  = roce_immdh_data_reg;

        udp_length_next       = udp_length_reg;

        ip_dest_ip_next = ip_dest_ip_reg;

        qp_transmission_complete_next = qp_transmission_complete_reg;

        dma_read_desc_valid_next = dma_read_desc_valid_reg && !dma_read_desc_ready;
        dma_read_desc_len_next   = dma_read_desc_len_reg;
        dma_read_desc_addr_next  = dma_read_desc_addr_reg;

        dma_rd_cmd_sent_next = dma_rd_cmd_sent_reg;

        retry_counter_next           = retry_counter_reg;
        rnr_retry_counter_next       = rnr_retry_counter_reg;
        total_retry_counter_next     = total_retry_counter_reg;
        total_rnr_retry_counter_next = total_rnr_retry_counter_reg;
        total_psn_seq_errors_next    = total_psn_seq_errors_reg;
        total_timeout_errors_next    = total_timeout_errors_reg;

        retry_psn_mark_next = retry_psn_mark_reg;
        rnr_retry_psn_mark_next = rnr_retry_psn_mark_reg;

        m_qp_close_valid_next = m_qp_close_valid_reg && !m_qp_close_ready;
        m_qp_close_loc_qpn_next = m_qp_close_loc_qpn_reg;
        m_qp_close_rem_psn_next = m_qp_close_rem_psn_reg;

        qp_closed_next = qp_closed_reg;

        qp_started_retrans_next = qp_started_retrans_reg;
        qp_started_rnr_retrans_next = qp_started_rnr_retrans_reg;

        if (round_robin_qpn_reg == (monitor_qpn-BASE_LOC_QPN)) begin
            n_retransmit_triggers_next = total_retry_counter_reg[round_robin_qpn_reg];
            n_rnr_retransmit_triggers_next = total_rnr_retry_counter_reg[round_robin_qpn_reg];
            n_total_psn_seq_errors_next = total_psn_seq_errors_reg[round_robin_qpn_reg];
            n_total_timeout_errors_next = total_timeout_errors_reg[round_robin_qpn_reg];
        end else begin
            n_retransmit_triggers_next = n_retransmit_triggers_reg;
            n_rnr_retransmit_triggers_next = n_rnr_retransmit_triggers_reg;
            n_total_psn_seq_errors_next = n_total_psn_seq_errors_reg;
            n_total_timeout_errors_next = n_total_timeout_errors_reg;
        end

        credit_next = credit_reg;

        flow_ctrl_pause_next = flow_ctrl_pause;

        state_cached_next = state_cached_reg;

        case(state_reg)
            STATE_CHECK_TIMEOUT: begin
                // irreversible error happened, close qp
                if (qp_error_reg[round_robin_qpn_reg])begin
                    m_qp_close_valid_next = 1'b1;
                    m_qp_close_loc_qpn_next = BASE_LOC_QPN + round_robin_qpn_reg;
                    qp_closed_next[round_robin_qpn_reg] = 1'b1;
                    qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                    qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;

                    if (MAX_QPS == 1) begin
                        round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QPN
                    end else begin
                        round_robin_qpn_next = round_robin_qpn_reg + 1;
                    end
                    state_next           = STATE_CHECK_TIMEOUT;
                end else begin
                    if (qp_rnr_wait_reg[round_robin_qpn_reg] && !qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // if qp in RNR wait compare table for checking if QP needs to be stalled, then skip to the next one
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;

                        s_rd_table_re_next  = 1'b1;
                        s_wr_table_re_next  = 1'b1;
                        s_cpl_table_re_next = 1'b1;

                        s_rd_table_qpn_next  = round_robin_qpn_reg;
                        s_wr_table_qpn_next  = round_robin_qpn_reg;
                        s_cpl_table_qpn_next = round_robin_qpn_reg;

                        state_next = STATE_FETCH_TABLES;
                    end else if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        // if timeout, bring rd pointer back to cpl pointer
                        // check retry count, if equal to retry count --> close qp
                        if (retry_counter_reg[round_robin_qpn_reg] == retry_count) begin
                            // retry reached, close qp
                            m_qp_close_valid_next = 1'b1;
                            m_qp_close_loc_qpn_next = BASE_LOC_QPN + round_robin_qpn_reg;
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
                        // if got psn sequence error or rnr wait finished, bring rd table back to the nak psn, 
                        state_next = STATE_UPDATE_RD_TABLE;
                    end else begin
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                        // all good, read the tables
                        s_rd_table_re_next  = 1'b1;
                        s_wr_table_re_next  = 1'b1;
                        s_cpl_table_re_next = 1'b1;

                        s_rd_table_qpn_next  = round_robin_qpn_reg;
                        s_wr_table_qpn_next  = round_robin_qpn_reg;
                        s_cpl_table_qpn_next = round_robin_qpn_reg;

                        state_next = STATE_FETCH_TABLES;
                    end
                end
            end
            STATE_UPDATE_RD_TABLE : begin
                if (!m_rd_table_we_reg) begin
                    // TODO use wait 1 clock cycle state
                    m_rd_table_we_next = 1'b1;
                    if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        // timeout
                        total_timeout_errors_next[round_robin_qpn_reg] = total_timeout_errors_reg[round_robin_qpn_reg] + 1;
                        retry_psn_mark_next[round_robin_qpn_reg]       = s_cpl_table_psn + 1;
                        retry_counter_next[round_robin_qpn_reg]        = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg]  = total_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next = s_cpl_table_psn;
                        qp_started_retrans_next[round_robin_qpn_reg] = 1'b1;
                    end else if (qp_psn_error_reg[round_robin_qpn_reg]) begin
                        // psn seq error
                        total_psn_seq_errors_next[round_robin_qpn_reg] = total_psn_seq_errors_reg[round_robin_qpn_reg] + 1;
                        retry_psn_mark_next[round_robin_qpn_reg]       = psn_nak_reg[round_robin_qpn_reg];
                        retry_counter_next[round_robin_qpn_reg]        = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg]  = total_retry_counter_reg[round_robin_qpn_reg] + 1;
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

                    s_rd_table_re_next  = 1'b1;
                    s_wr_table_re_next  = 1'b1;
                    s_cpl_table_re_next = 1'b1;

                    s_rd_table_qpn_next  = round_robin_qpn_reg;
                    s_wr_table_qpn_next  = round_robin_qpn_reg;
                    s_cpl_table_qpn_next = round_robin_qpn_reg;
                    state_next = STATE_FETCH_TABLES;
                end
            end
            STATE_FETCH_TABLES : begin
                state_next = STATE_COMPARE;
            end
            STATE_COMPARE: begin
                if (qp_closed_reg[round_robin_qpn_reg]) begin
                    qp_closed_next[round_robin_qpn_reg] = 1'b0;
                    // is this one necessary?
                    retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    if (MAX_QPS == 1) begin
                        round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                    end else begin
                        round_robin_qpn_next = round_robin_qpn_reg + 1;
                    end
                    state_next           = STATE_CHECK_TIMEOUT;
                end else begin
                    // if cpl table psn not eq than the psn mark (psn when retransmission is triggered) reset retry counter, it means that a valid ACK is received 
                    if (s_cpl_table_psn != (retry_psn_mark_reg[round_robin_qpn_reg] - 24'd1)) begin
                        retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    end
                    if (s_cpl_table_psn != (rnr_retry_psn_mark_reg[round_robin_qpn_reg] - 24'd1)) begin
                        rnr_retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    end

                    // transmission complete, stop timeout counter for that QP
                    //qp_transmission_complete_next[round_robin_qpn_reg] = s_cpl_table_psn == s_wr_table_psn;
                    qp_transmission_complete_next[round_robin_qpn_reg] = s_cpl_table_psn == s_rd_table_psn;

                    // check psn for WR and RD
                    if (s_wr_table_psn == s_rd_table_psn) begin
                        // same pointers, do nothing

                        if (MAX_QPS == 1) begin
                            round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                        end else begin
                            round_robin_qpn_next = round_robin_qpn_reg + 1;
                        end
                        state_next           = STATE_CHECK_TIMEOUT;
                    end else begin
                        // pointers are not the same 
                        if (qp_rnr_wait_reg[round_robin_qpn_reg]) begin
                            // TODO what happens if this register changes in the middle of the state transistions STATE_CHECK_TIMEOUT --> STATE_FETCH_TABLES --> STATE_COMPARE?
                            // RNR wait still on going, skip to the next QP

                            if (MAX_QPS == 1) begin
                                round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                            end else begin
                                round_robin_qpn_next = round_robin_qpn_reg + 1;
                            end
                            state_next           = STATE_CHECK_TIMEOUT;
                        end else begin
                            //send read command to DMA, but first fetch header values
                            // check if header can be sent
                            if (roce_bth_ready) begin
                                if (s_rd_table_psn - s_cpl_table_psn < 24'hff_0000) begin
                                    // read pointer is ahead of completion pointer, all good
                                    if (MAX_QPS == 1) begin
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1:0]  = s_rd_table_psn[HEADER_ADDR_WIDTH-1:0] + 1;
                                    end else begin
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0]  = s_rd_table_psn[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] + 1;
                                    end
                                end else begin
                                    // completion pointer is ahead of read pointer, update read pointer to be the same and read from the completion pointer
                                    // this means that we are sending data that has already been sent and acnowledged, update the pointer to avoid sending useless data
                                    if (MAX_QPS == 1) begin
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1:0]  = s_cpl_table_psn[HEADER_ADDR_WIDTH-1:0] + 1;
                                    end else begin
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0]  = s_cpl_table_psn[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] + 1;
                                    end
                                    m_rd_table_we_next  = 1'b1;
                                    m_rd_table_qpn_next = round_robin_qpn_reg;
                                    m_rd_table_psn_next = s_cpl_table_psn;
                                end
                                //hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];

                                //state_next = STATE_FETCH_HDR;

                                // move to another qp if qp need to be limited
                                if (rate_lim_reg[round_robin_qpn_reg] >= 11'h400 || !dcqcn_en || !EN_DCQCN_LOGIC) begin
                                    credit_next[round_robin_qpn_reg] = PACKET_COST;
                                    hdr_ram_re_next   = 1'b1;
                                    if (MAX_QPS != 1) begin
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];
                                    end
                                    state_next = STATE_FETCH_HDR;
                                end else begin // max
                                    if (credit_reg[round_robin_qpn_reg] <= PACKET_COST) begin // stall qp
                                        hdr_ram_re_next   = 1'b0;
                                        credit_next[round_robin_qpn_reg] = credit_reg[round_robin_qpn_reg] + rate_lim_reg[round_robin_qpn_reg];
                                        if (MAX_QPS == 1) begin
                                            round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                                        end else begin
                                            round_robin_qpn_next = round_robin_qpn_reg + 1;
                                        end
                                        state_next           = STATE_CHECK_TIMEOUT;
                                    end else begin // send packet, reduce credit
                                        credit_next[round_robin_qpn_reg] = credit_reg[round_robin_qpn_reg] - PACKET_COST + rate_lim_reg[round_robin_qpn_reg];
                                        hdr_ram_re_next   = 1'b1;
                                        if (MAX_QPS != 1) begin
                                            hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];
                                        end
                                        state_next = STATE_FETCH_HDR;
                                    end
                                end
                            end else begin // header is not ready to be sent, wait until it can be sent
                                state_next           = STATE_COMPARE;
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
                    roce_bth_dest_qp_next = cached_rem_qpn_reg[round_robin_qpn_reg];
                    roce_bth_src_qp_next  = BASE_LOC_QPN + round_robin_qpn_reg;
                    roce_bth_ack_req_next = 1'b1;
                    // RETH Fields
                    roce_reth_v_addr_next = hdr_ram_data[RAM_VADDR_OFFSET+:64];
                    roce_reth_r_key_next  = cached_r_key_reg[round_robin_qpn_reg];
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
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0]  =  ((s_rd_table_psn + 1) << memory_steps);
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] =  round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];

                    // now update read pointer
                    m_rd_table_we_next = 1'b1;
                    m_rd_table_psn_next = s_rd_table_psn + 1;
                    m_rd_table_qpn_next = round_robin_qpn_reg;

                    if (roce_bth_ready) begin
                        if (dma_read_desc_ready) begin
                            dma_rd_cmd_sent_next = 1'b0;

                            if (MAX_QPS == 1) begin
                                round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                            end else begin
                                round_robin_qpn_next = round_robin_qpn_reg + 1;
                            end
                            state_next           = STATE_CHECK_TIMEOUT;
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
                if (roce_bth_valid & roce_bth_ready) begin
                    if (dma_rd_cmd_sent_reg) begin
                        // dma command already sent and header sent, go on
                        dma_rd_cmd_sent_next = 1'b0;

                        if (MAX_QPS == 1) begin
                            round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                        end else begin
                            round_robin_qpn_next = round_robin_qpn_reg + 1;
                        end
                        state_next           = STATE_CHECK_TIMEOUT;
                    end else begin
                        // dma command sent now and header sent, go on
                        if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                            dma_rd_cmd_sent_next = 1'b0;

                            if (MAX_QPS == 1) begin
                                round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                            end else begin
                                round_robin_qpn_next = round_robin_qpn_reg + 1;
                            end
                            state_next           = STATE_CHECK_TIMEOUT;
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

                    if (MAX_QPS == 1) begin
                        round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                    end else begin
                        round_robin_qpn_next = round_robin_qpn_reg + 1;
                    end
                    state_next           = STATE_CHECK_TIMEOUT;
                end else begin
                    state_next = STATE_WAIT_DMA;
                end
            end
            STATE_CHANGE_QPN: begin
                // update control QPN
                if (MAX_QPS == 1) begin
                    round_robin_qpn_next = round_robin_qpn_reg; // stay in the same QP
                end else begin
                    round_robin_qpn_next = round_robin_qpn_reg + 1;
                end
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

            retry_counter_reg           <= '{default:0};
            rnr_retry_counter_reg       <= '{default:0};
            total_retry_counter_reg     <= '{default:0};
            total_rnr_retry_counter_reg <= '{default:0};
            total_psn_seq_errors_reg    <= '{default:0};
            total_timeout_errors_reg    <= '{default:0};

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
            n_total_psn_seq_errors_reg <= 'd0;
            n_total_timeout_errors_reg <= 'd0;

            flow_ctrl_pause_reg <= 1'b0;

            s_roce_rx_aeth_ready_reg <= 1'b0;
            rx_cnp_reg     <= 1'b0;
            rx_cnp_qpn_reg <= 24'd0;

            credit_reg <= '{default:0};

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
            total_psn_seq_errors_reg    <= total_psn_seq_errors_next;
            total_timeout_errors_reg    <= total_timeout_errors_next;

            n_retransmit_triggers_reg <= n_retransmit_triggers_next;
            n_rnr_retransmit_triggers_reg <= n_rnr_retransmit_triggers_next;
            n_total_psn_seq_errors_reg <= n_total_psn_seq_errors_next;
            n_total_timeout_errors_reg <= n_total_timeout_errors_next;

            flow_ctrl_pause_reg <= flow_ctrl_pause_next;

            credit_reg <= credit_next;

            if (s_qp_open_valid) begin
                if (s_qp_open_loc_qpn >= BASE_LOC_QPN) begin
                    cached_dest_ip_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]] <= s_qp_open_rem_ip_addr;
                    cached_rem_qpn_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]] <= s_qp_open_rem_qpn;
                    cached_r_key_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]   <= s_qp_open_r_key;

                    // reset counters for that qp
                    retry_counter_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]           <= 'd0;
                    rnr_retry_counter_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]       <= 'd0;
                    total_retry_counter_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]     <= 'd0;
                    total_rnr_retry_counter_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]] <= 'd0;
                    total_psn_seq_errors_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]    <= 'd0;
                    total_timeout_errors_reg[s_qp_open_loc_qpn[MAX_QPS_WIDTH-1:0]]    <= 'd0;
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
                    if (rnr_counter_reg[round_robin_qpn_timeout_reg] - MAX_QPS < MAX_QPS || rnr_counter_reg[round_robin_qpn_timeout_reg] == 0) begin
                        // RNR wait finished, deassert rnr wait bit and assert rnr wait done
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
            // decode cnp
            s_roce_rx_cnp_ready_reg  <= 1'b0;
            rx_cnp_reg               <= 1'b0;
            if (s_roce_rx_cnp_valid  && (s_roce_rx_cnp_dest_qp == round_robin_qpn_timeout_reg + BASE_LOC_QPN)) begin // process CNP
                s_roce_rx_cnp_ready_reg  <= 1'b1;
                rx_cnp_reg     <= 1'b1;
                rx_cnp_qpn_reg <= s_roce_rx_cnp_dest_qp;
            end

            // decode rx ACKs and timemout counter logic
            s_roce_rx_aeth_ready_reg <= 1'b0;
            if (s_roce_rx_aeth_valid && (s_roce_rx_aeth_dest_qp == round_robin_qpn_timeout_reg + BASE_LOC_QPN)) begin // process ack
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
                        psn_nak_reg[round_robin_qpn_timeout_reg]          <= s_roce_rx_aeth_psn;
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
                        if (!flow_ctrl_pause_reg) begin
                            timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                        end
                        qp_psn_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                        qp_rnr_wait_reg[round_robin_qpn_timeout_reg]  <= 1'b0;
                    end
                    2'b11: begin // NAK
                        if (s_roce_rx_aeth_syndrome[4:0] == 5'b00000) begin
                            // PSN seq error
                            if (!qp_rnr_wait_reg[round_robin_qpn_timeout_reg]) begin
                                // if RNR was not triggered, otherwise ignore

                                if (retry_counter_reg[round_robin_qpn_timeout_reg] == retry_count) begin
                                    // retry limit reached, close qp
                                    qp_error_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                                end else begin
                                    timeout_counter[round_robin_qpn_timeout_reg]      <= timeout_period;
                                    qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b1;
                                    qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                                    qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                                    psn_nak_reg[round_robin_qpn_timeout_reg]          <= s_roce_rx_aeth_psn;
                                end
                            end

                        end else begin // force close qp
                            qp_error_reg[round_robin_qpn_timeout_reg] <= 1'b1;
                            // s_roce_rx_aeth_syndrome[4:0] == 5'b00001; invalid request
                            // s_roce_rx_aeth_syndrome[4:0] == 5'b00010; remote access error
                            // s_roce_rx_aeth_syndrome[4:0] == 5'b00011; remote operational error
                            // s_roce_rx_aeth_syndrome[4:0] == 5'b00100; invalid RD request
                            // the rest --> reserved
                        end
                    end
                    default: begin
                        if (!flow_ctrl_pause_reg) begin
                            timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                        end
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
                    timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_period;
                end else begin
                    // reduce counter by MAX_QPS (clock cycles required for a complete sweep)
                    if (!flow_ctrl_pause_reg) begin
                        timeout_counter[round_robin_qpn_timeout_reg]  <= timeout_counter[round_robin_qpn_timeout_reg] - MAX_QPS;
                    end
                end
                qp_timed_out_reg[round_robin_qpn_timeout_reg] <= 1'b0;

            end

            if (qp_closed_reg[round_robin_qpn_timeout_reg]) begin
                qp_error_reg[round_robin_qpn_timeout_reg]         <= 1'b0;
                qp_timed_out_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
                timeout_counter[round_robin_qpn_timeout_reg]      <= timeout_period;
                qp_rnr_wait_reg[round_robin_qpn_timeout_reg]      <= 1'b0;
                qp_rnr_wait_done_reg[round_robin_qpn_timeout_reg] <= 1'b0;
                qp_psn_error_reg[round_robin_qpn_timeout_reg]     <= 1'b0;
            end

            if (qp_started_retrans_reg[round_robin_qpn_timeout_reg]) begin
                // deassert errors
                qp_psn_error_reg[round_robin_qpn_timeout_reg] <= 1'b0;
            end

            // next qp
            if (MAX_QPS == 1) begin
                round_robin_qpn_timeout_reg <= round_robin_qpn_timeout_reg; // stay in the same QP
            end else begin
                round_robin_qpn_timeout_reg <= round_robin_qpn_timeout_reg + 1;
            end

        end
    end


    generate
        if (RD_CMD_FIFO_DEPTH <= 2) begin
            axis_register #(
                .DATA_WIDTH  (BUFFER_ADDR_WIDTH+13),
                .KEEP_ENABLE (0),
                .LAST_ENABLE (0),
                .ID_ENABLE   (0),
                .DEST_ENABLE (0),
                .USER_ENABLE (0),
                .REG_TYPE    (2)
            ) dma_read_command_reg (
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
                .m_axis_tready(m_axis_dma_read_desc_ready)
            );
        end else begin
            axis_fifo #(
                .DEPTH       (RD_CMD_FIFO_DEPTH > 2 ? RD_CMD_FIFO_DEPTH : 3),
                .DATA_WIDTH  (BUFFER_ADDR_WIDTH+13),
                .KEEP_ENABLE (0),
                .LAST_ENABLE (0),
                .ID_ENABLE   (0),
                .DEST_ENABLE (0),
                .USER_ENABLE (0),
                .RAM_PIPELINE(0)
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
        end
    endgenerate


    assign roce_bth_valid   = roce_bth_valid_reg;
    assign roce_bth_op_code = roce_bth_op_code_reg;
    assign roce_bth_p_key   = roce_bth_p_key_reg;
    assign roce_bth_psn     = roce_bth_psn_reg;
    assign roce_bth_dest_qp = roce_bth_dest_qp_reg;
    assign roce_bth_src_qp  = roce_bth_src_qp_reg;
    assign roce_bth_ack_req = roce_bth_ack_req_reg;
    assign roce_reth_valid  = roce_reth_valid_reg;
    assign roce_reth_v_addr = roce_reth_v_addr_reg;
    assign roce_reth_r_key  = roce_reth_r_key_reg;
    assign roce_reth_length = roce_reth_length_reg;
    assign roce_immdh_valid = roce_immdh_valid_reg;
    assign roce_immdh_data  = roce_immdh_data_reg;

    assign eth_dest_mac       = 0;
    assign eth_src_mac        = 0;
    assign eth_type           = 0;
    assign ip_version         = 4'd4;
    assign ip_ihl             = 0;
    assign ip_dscp            = 0;
    assign ip_ecn             = 0;
    assign ip_identification  = 0;
    assign ip_flags           = 3'b001;
    assign ip_fragment_offset = 0;
    assign ip_ttl             = 8'h40;
    assign ip_protocol        = 8'h11;
    assign ip_header_checksum = 0;
    assign ip_dest_ip         = ip_dest_ip_reg;
    assign ip_source_ip       = loc_ip_addr;

    assign udp_length      = udp_length_reg;
    assign udp_checksum    =   16'd0;
    assign udp_source_port = 16'd0;
    assign udp_dest_port   = ROCE_UDP_PORT;

    wire roce_bth_hdr_t  temp_roce_bth;
    wire roce_reth_hdr_t temp_roce_reth;
    wire roce_immd_hdr_t temp_roce_immdh;
    wire udp_hdr_t       temp_udp_hdr;

    assign temp_roce_bth.op_code        = roce_bth_op_code;
    assign temp_roce_bth.p_key          = roce_bth_p_key;
    assign temp_roce_bth.psn            = roce_bth_psn;
    assign temp_roce_bth.qp_number      = roce_bth_dest_qp;
    assign temp_roce_bth.ack_request    = roce_bth_ack_req;
    assign temp_roce_bth.fecn           = 1'b0;
    assign temp_roce_bth.becn           = 1'b0;
    assign temp_roce_bth.sol_event      = 1'b0;
    assign temp_roce_bth.mig_request    = 1'b1;
    assign temp_roce_bth.pad_count      = 2'b00;
    assign temp_roce_bth.header_version = 4'd0;
    assign temp_roce_bth.reserved_0     = 'd0;
    assign temp_roce_bth.reserved_1     = 'd0;

    assign temp_roce_reth.vaddr      = roce_reth_v_addr;
    assign temp_roce_reth.r_key      = roce_reth_r_key;
    assign temp_roce_reth.dma_length = roce_reth_length;

    assign temp_roce_immdh.immediate_data     = roce_immdh_data;

    assign temp_udp_hdr.src_port   = udp_source_port;
    assign temp_udp_hdr.dest_port  = udp_dest_port;
    assign temp_udp_hdr.length     = udp_length;
    assign temp_udp_hdr.checksum   = udp_checksum;

    wire [(12+3+16+4+4+8)*8 -1 :0] temp_hdr_fifo_input, temp_hdr_fifo_output;
    wire temp_hdr_fifo_output_valid;
    wire temp_hdr_fifo_output_ready;

    assign temp_hdr_fifo_input =
    {
    temp_roce_bth,
    roce_bth_src_qp,
    temp_roce_reth,
    temp_roce_immdh,
    temp_udp_hdr,
    ip_dest_ip
    };


    generate
        if (RD_CMD_FIFO_DEPTH < 2) begin
            axis_register #(
                .DATA_WIDTH  ((12+3+16+4+8+4)*8), // BTH, SRC QP, RETH, IMMH, UDP, DEST IP ADDR
                .KEEP_ENABLE (0),
                .ID_ENABLE   (0),
                .DEST_ENABLE (0),
                .LAST_ENABLE (0),
                .USER_ENABLE (0),
                .REG_TYPE    (2)
            ) hdr_reg (
                .clk(clk),
                .rst(rst),

                // AXI input
                .s_axis_tdata (temp_hdr_fifo_input),
                .s_axis_tkeep (0),
                .s_axis_tvalid(roce_bth_valid),
                .s_axis_tready(roce_bth_ready),
                .s_axis_tlast (0),
                .s_axis_tuser (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (temp_hdr_fifo_output),
                .m_axis_tkeep (),
                .m_axis_tvalid(temp_hdr_fifo_output_valid),
                .m_axis_tready(temp_hdr_fifo_output_ready),
                .m_axis_tlast (),
                .m_axis_tuser ()
            );
        end else begin
            axis_fifo #(
                .DEPTH       (RD_CMD_FIFO_DEPTH > 2 ? RD_CMD_FIFO_DEPTH-1 : 2),
                .DATA_WIDTH  ((12+3+16+4+8+4)*8), // BTH, SRC QP, RETH, IMMH, UDP, DEST IP ADDR
                .KEEP_ENABLE (0),
                .ID_ENABLE   (0),
                .DEST_ENABLE (0),
                .LAST_ENABLE (0),
                .USER_ENABLE (0),
                .RAM_PIPELINE(0) // enable RAM PIPELINE only for > 333MHz freqs
            ) hdr_fifo (
                .clk(clk),
                .rst(rst),

                // AXI input
                .s_axis_tdata (temp_hdr_fifo_input),
                .s_axis_tkeep (0),
                .s_axis_tvalid(roce_bth_valid),
                .s_axis_tready(roce_bth_ready),
                .s_axis_tlast (0),
                .s_axis_tuser (0),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (temp_hdr_fifo_output),
                .m_axis_tkeep (),
                .m_axis_tvalid(temp_hdr_fifo_output_valid),
                .m_axis_tready(temp_hdr_fifo_output_ready),
                .m_axis_tlast (),
                .m_axis_tuser (),

                // Status
                .status_overflow  (),
                .status_bad_frame (),
                .status_good_frame()
            );
        end
    endgenerate




    generate
        if (RD_AXIS_DATAMOVER_FIFO_DEPTH > 0) begin
            axis_fifo #(
                .DEPTH       (RD_AXIS_DATAMOVER_FIFO_DEPTH),
                .DATA_WIDTH  (DATA_WIDTH),
                .KEEP_ENABLE (1),
                .KEEP_WIDTH  (DATA_WIDTH/8),
                .ID_ENABLE   (0),
                .DEST_ENABLE (0),
                .USER_ENABLE (1),
                .USER_WIDTH  (1),
                .RAM_PIPELINE(0), // enable RAM PIPELINE only for > 333MHz freqs
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
        end else begin
            assign m_roce_payload_axis_tdata  = s_dma_read_axis_tdata;
            assign m_roce_payload_axis_tkeep  = s_dma_read_axis_tkeep;
            assign m_roce_payload_axis_tvalid = s_dma_read_axis_tvalid;
            assign s_dma_read_axis_tready     = m_roce_payload_axis_tready;
            assign m_roce_payload_axis_tlast  = s_dma_read_axis_tlast;
            assign m_roce_payload_axis_tuser  = s_dma_read_axis_tuser;
        end
    endgenerate



    wire roce_bth_hdr_t m_roce_qp_arb_bth = temp_hdr_fifo_output[(12+3+16+4+8+4)*8-1 -: 12*8];
    assign m_roce_bth_op_code = m_roce_qp_arb_bth.op_code;
    assign m_roce_bth_p_key   = m_roce_qp_arb_bth.p_key;
    assign m_roce_bth_psn     = m_roce_qp_arb_bth.psn;
    assign m_roce_bth_dest_qp = m_roce_qp_arb_bth.qp_number;
    assign m_roce_bth_ack_req = m_roce_qp_arb_bth.ack_request;

    wire arb_has_reth =
    m_roce_bth_op_code == RC_RDMA_WRITE_FIRST ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD;

    wire arb_has_immediate =
    m_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
    m_roce_bth_op_code == RC_SEND_LAST_IMD ||
    m_roce_bth_op_code == RC_SEND_ONLY_IMD ;

    assign m_roce_bth_valid    = temp_hdr_fifo_output_valid;
    assign m_roce_reth_valid  = temp_hdr_fifo_output_valid && arb_has_reth;
    assign m_roce_immdh_valid = temp_hdr_fifo_output_valid && arb_has_immediate;

    assign temp_hdr_fifo_output_ready = m_roce_bth_ready;

    assign m_roce_bth_src_qp   = temp_hdr_fifo_output[(3+16+4+8+4)*8-1 -: 3*8];

    wire roce_reth_hdr_t m_roce_qp_arb_reth = temp_hdr_fifo_output[(16+4+8+4)*8-1 -: 16*8];
    assign m_roce_reth_v_addr = m_roce_qp_arb_reth.vaddr;
    assign m_roce_reth_r_key  = m_roce_qp_arb_reth.r_key;
    assign m_roce_reth_length = m_roce_qp_arb_reth.dma_length;

    wire roce_immd_hdr_t m_roce_qp_arb_immd = temp_hdr_fifo_output[(4+8+4)*8-1 -: 4*8];
    assign m_roce_immdh_data = m_roce_qp_arb_immd.immediate_data;;

    wire udp_hdr_t m_roce_qp_arb_udp = temp_hdr_fifo_output[(8+4)*8-1 -: 8*8];
    assign m_udp_source_port  = m_roce_qp_arb_udp.src_port;
    assign m_udp_dest_port = m_roce_qp_arb_udp.dest_port;
    assign m_udp_length    = m_roce_qp_arb_udp.length;
    assign m_udp_checksum  = m_roce_qp_arb_udp.checksum;

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
    assign m_ip_source_ip = loc_ip_addr;
    assign m_ip_dest_ip  = temp_hdr_fifo_output[4*8-1     -: 4*8];

    assign m_eth_dest_mac = 0;
    assign m_eth_src_mac = 0;
    assign m_eth_type = 0;


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
    assign s_roce_rx_cnp_ready  = EN_DCQCN_LOGIC ? s_roce_rx_cnp_ready_reg : 1'b1;

    assign m_qp_close_valid = m_qp_close_valid_reg;
    assign m_qp_close_loc_qpn = m_qp_close_loc_qpn_reg;
    assign m_qp_close_rem_psn = 0;

    assign n_retransmit_triggers     = n_retransmit_triggers_reg;
    assign n_rnr_retransmit_triggers = n_rnr_retransmit_triggers_reg;
    assign n_total_psn_seq_errors    = n_total_psn_seq_errors_reg;
    assign n_total_timeout_errors    = n_total_timeout_errors_reg;

endmodule

`resetall