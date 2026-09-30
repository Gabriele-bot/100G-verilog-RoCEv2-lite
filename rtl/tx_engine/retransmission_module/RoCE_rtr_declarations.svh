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

    // DCQCN
    localparam  PACKET_COST = 1023;
    reg [11:0] credit_next    [MAX_QPS-1:0];
    reg [11:0] credit_reg     [MAX_QPS-1:0];

    wire [10:0]  rate_lim     [MAX_QPS-1:0];
    reg  [10:0]  rate_lim_reg [MAX_QPS-1:0];

    reg rx_cnp_reg;
    reg [23:0] rx_cnp_qpn_reg;
