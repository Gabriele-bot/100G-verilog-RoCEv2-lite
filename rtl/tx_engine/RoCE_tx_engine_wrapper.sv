`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_tx_engine_wrapper #(
    parameter QP_CH_DATA_WIDTH                 = 256,
    parameter QP_CH_KEEP_ENABLE                = (QP_CH_DATA_WIDTH>8),
    parameter QP_CH_KEEP_WIDTH                 = (QP_CH_DATA_WIDTH/8),
    parameter OUT_DATA_WIDTH                   = 512,
    parameter OUT_KEEP_ENABLE                  = (OUT_DATA_WIDTH>8),
    parameter OUT_KEEP_WIDTH                   = (OUT_DATA_WIDTH/8),
    parameter CLOCK_PERIOD                     = 6.4, // in ns
    parameter REFRESH_CACHE_TICKS              = 32768,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 24,
    parameter N_QUEUE_PAIRS                    = 2,
    parameter BASE_LOC_QPN                     = 256,
    parameter DEBUG                            = 0
) (

    input wire clk,
    input wire rst,

    input wire flow_ctrl_pause,

    /*
     * RoCE RX ACKed PSNs
     */
    input  wire         s_roce_rx_bth_valid,
    output wire         s_roce_rx_bth_ready,
    input  wire [ 23:0] s_roce_rx_bth_psn,
    input  wire [ 7 :0] s_roce_rx_bth_op_code,
    input  wire [ 23:0] s_roce_rx_bth_dest_qp,
    input  wire         s_roce_rx_aeth_valid,
    output wire         s_roce_rx_aeth_ready,
    input  wire [ 7 :0] s_roce_rx_aeth_syndrome,
    input  wire [ 23:0] s_roce_rx_last_not_acked_psn,

    // input Work request
    input wire         s_wr_req_valid          [N_QUEUE_PAIRS-1:0],
    input wire         s_wr_req_ready          [N_QUEUE_PAIRS-1:0],
    input wire         s_wr_req_tx_type        [N_QUEUE_PAIRS-1:0], // 0 WRITE, 1 SEND
    input wire         s_wr_req_is_immediate   [N_QUEUE_PAIRS-1:0],
    input wire [31:0]  s_wr_req_immediate_data [N_QUEUE_PAIRS-1:0],
    input wire [23:0]  s_wr_req_loc_qp         [N_QUEUE_PAIRS-1:0],
    input wire [63:0]  s_wr_req_addr_offset    [N_QUEUE_PAIRS-1:0],
    input wire [31:0]  s_wr_req_dma_length     [N_QUEUE_PAIRS-1:0], // for each transfer

    // input QPs AXIS
    input  wire [QP_CH_DATA_WIDTH - 1 :0]  s_axis_tdata  [N_QUEUE_PAIRS-1:0],
    input  wire [QP_CH_KEEP_WIDTH - 1 :0]  s_axis_tkeep  [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tvalid [N_QUEUE_PAIRS-1:0],
    output wire                            s_axis_tready [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tlast  [N_QUEUE_PAIRS-1:0],
    input  wire                            s_axis_tuser  [N_QUEUE_PAIRS-1:0],

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
    output  wire [OUT_DATA_WIDTH - 1 :0] m_roce_payload_axis_tdata,
    output  wire [OUT_KEEP_WIDTH - 1 :0] m_roce_payload_axis_tkeep,
    output  wire                         m_roce_payload_axis_tvalid,
    input   wire                         m_roce_payload_axis_tready,
    output  wire                         m_roce_payload_axis_tlast,
    output  wire                         m_roce_payload_axis_tuser,
    /*
     * AXI master interface to RAM
     */
    output wire [0                :0]                  m_axi_awid,
    output wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                                  m_axi_awlen,
    output wire [2:0]                                  m_axi_awsize,
    output wire [1:0]                                  m_axi_awburst,
    output wire                                        m_axi_awlock,
    output wire [3:0]                                  m_axi_awcache,
    output wire [2:0]                                  m_axi_awprot,
    output wire                                        m_axi_awvalid,
    input  wire                                        m_axi_awready,
    output wire [OUT_DATA_WIDTH-1:0]                   m_axi_wdata,
    output wire [OUT_KEEP_WIDTH -1:0]                  m_axi_wstrb,
    output wire                                        m_axi_wlast,
    output wire                                        m_axi_wvalid,
    input  wire                                        m_axi_wready,
    input  wire [0:0]                                  m_axi_bid,
    input  wire [1:0]                                  m_axi_bresp,
    input  wire                                        m_axi_bvalid,
    output wire                                        m_axi_bready,
    output wire [0               :0]                   m_axi_arid,
    output wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]                                  m_axi_arlen,
    output wire [2:0]                                  m_axi_arsize,
    output wire [1:0]                                  m_axi_arburst,
    output wire                                        m_axi_arlock,
    output wire [3:0]                                  m_axi_arcache,
    output wire [2:0]                                  m_axi_arprot,
    output wire                                        m_axi_arvalid,
    input  wire                                        m_axi_arready,
    input  wire [0             :0]                     m_axi_rid,
    input  wire [OUT_DATA_WIDTH  -1:0]                 m_axi_rdata,
    input  wire [1:0]                                  m_axi_rresp,
    input  wire                                        m_axi_rlast,
    input  wire                                        m_axi_rvalid,
    output wire                                        m_axi_rready,

    // Update qp state
    output wire         m_qp_update_context_valid,
    input  wire         m_qp_update_context_ready,
    output wire [23:0]  m_qp_update_context_loc_qpn,
    output wire [23:0]  m_qp_update_context_rem_psn,

    output wire        wr_error_qp_not_rts_out [N_QUEUE_PAIRS-1:0],
    output wire [23:0] wr_error_loc_qpn_out [N_QUEUE_PAIRS-1:0],

    // CM signals
    input wire        cm_qp_valid,

    input wire [2 :0] cm_qp_req_type,
    input wire [31:0] cm_qp_dma_transfer_length,
    input wire [23:0] cm_qp_rem_qpn,
    input wire [23:0] cm_qp_loc_qpn,
    input wire [23:0] cm_qp_rem_psn,
    input wire [23:0] cm_qp_loc_psn,
    input wire [31:0] cm_qp_r_key,
    input wire [63:0] cm_qp_rem_addr,
    input wire [31:0] cm_qp_rem_ip_addr,
    input wire        qp_is_immediate,
    input wire        qp_tx_type,

    // QP state request
    output wire        m_qp_context_req_valid,
    input  wire        m_qp_context_req_ready,
    output wire [23:0] m_qp_context_loc_qpn_req,
    // QP state reply
    input wire        s_qp_context_req_valid,
    input wire [2 :0] s_qp_context_req_state,
    input wire [23:0] s_qp_context_req_rem_qpn,
    input wire [23:0] s_qp_context_req_loc_qpn,
    input wire [23:0] s_qp_context_req_rem_psn,
    input wire [23:0] s_qp_context_req_loc_psn,
    input wire [31:0] s_qp_context_req_r_key,
    input wire [63:0] s_qp_context_req_rem_addr,
    input wire [31:0] s_qp_context_req_rem_ip_addr,

    /*
    Close QP in case failed transfer (e.g. rnr retry count reached, retry count reached, irreversible error)
    */
    output  wire         m_qp_close_valid,
    input   wire         m_qp_close_ready,
    output  wire [23:0]  m_qp_close_loc_qpn,
    output  wire [23:0]  m_qp_close_rem_psn,
    /*
    Configuration
    */
    input wire        cfg_valid,
    input wire [63:0] timeout_period,
    input wire [2 :0] retry_count,
    input wire [2 :0] rnr_retry_count,
    input wire [31:0] loc_ip_addr,
    input wire [2 :0] pmtu,

    /*
     * LOC QPN status
     */
    input  wire [23:0] monitor_loc_qpn,

    input  wire [3:0]  cfg_latency_avg_po2,
    input  wire [4:0]  cfg_throughput_avg_po2,

    output wire [31:0] transfer_time_avg,
    output wire [31:0] transfer_time_moving_avg,
    output wire [31:0] transfer_time_inst,
    output wire [31:0] latency_avg,
    output wire [31:0] latency_moving_avg,
    output wire [31:0] latency_inst,
    output wire        latency_inst_valid,

    output wire [31:0]  n_retransmit_triggers,
    output wire [31:0]  n_rnr_retransmit_triggers,
    output wire [23:0]  psn_diff // WR - CPL psn difference   
);

    import RoCE_params::*; // Imports RoCE parameters

    // instntate N_QUEUE_PAIRS modules
    localparam ARB_HEADER_LENGTH = 12+3+16+4+8+4; // BTH + SRC_QPN +  RETH + IMMD + UDP_HDR + DEST_IP_ADDR

    // request arbiter

    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_ready;
    wire [N_QUEUE_PAIRS*24-1:0] qp_local_qpn_arb_req;


    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_ready;
    wire [N_QUEUE_PAIRS*48-1:0] qp_update_context_loc_qpn_rem_psn_arb;

    // merge RoCE TX Engine output
    // first stage arbiter  
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_hdr_valid;
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_hdr_ready;
    wire [ARB_HEADER_LENGTH*8*N_QUEUE_PAIRS-1:0] s_roce_arb_header;
    wire [N_QUEUE_PAIRS*OUT_DATA_WIDTH-1 :0]     s_roce_qp_arb_payload_axis_tdata;
    wire [N_QUEUE_PAIRS*OUT_KEEP_WIDTH-1 :0]     s_roce_qp_arb_payload_axis_tkeep;
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_payload_axis_tvalid;
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_payload_axis_tready;
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_payload_axis_tlast;
    wire [N_QUEUE_PAIRS-1                :0]     s_roce_qp_arb_payload_axis_tuser;

    wire                           m_roce_qp_arb_hdr_valid;
    wire                           m_roce_qp_arb_hdr_ready;
    wire [ARB_HEADER_LENGTH*8-1:0] m_roce_qp_arb_hdr; // BTH + SRC_QPN + RETH + IMMD + UDP_HDR + IP_ADDR
    wire [OUT_DATA_WIDTH-1 :0]     m_roce_qp_arb_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH-1 :0]     m_roce_qp_arb_payload_axis_tkeep;
    wire                           m_roce_qp_arb_payload_axis_tvalid;
    wire                           m_roce_qp_arb_payload_axis_tready;
    wire                           m_roce_qp_arb_payload_axis_tlast;
    wire                           m_roce_qp_arb_payload_axis_tuser;

    // Arbiter output (between QPs)
    wire roce_bth_hdr_t m_roce_qp_arb_bth = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH)*8-1 -: 12*8];
    wire [7:0]  m_roce_qp_arb_bth_op_code = m_roce_qp_arb_bth.op_code;
    wire [15:0] m_roce_qp_arb_bth_p_key   = m_roce_qp_arb_bth.p_key;
    wire [23:0] m_roce_qp_arb_bth_psn     = m_roce_qp_arb_bth.psn;
    wire [23:0] m_roce_qp_arb_bth_dest_qp = m_roce_qp_arb_bth.qp_number;
    wire        m_roce_qp_arb_bth_ack_req = m_roce_qp_arb_bth.ack_request;

    wire [23:0] m_roce_qp_arb_bth_src_qp   = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH-12)*8-1 -: 3*8];

    wire roce_reth_hdr_t m_roce_qp_arb_reth = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH-12-3)*8-1 -: 16*8];
    wire [63:0] m_roce_qp_arb_reth_v_addr = m_roce_qp_arb_reth.vaddr;
    wire [31:0] m_roce_qp_arb_reth_r_key  = m_roce_qp_arb_reth.r_key;
    wire [31:0] m_roce_qp_arb_reth_length = m_roce_qp_arb_reth.dma_length;

    wire roce_immd_hdr_t m_roce_qp_arb_immd = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH-12-3-16)*8-1 -: 4*8];
    wire [31:0] m_roce_qp_arb_immdh_data = m_roce_qp_arb_immd.immediate_data;;

    wire udp_hdr_t m_roce_qp_arb_udp = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH-12-3-16-4)*8-1 -: 8*8];
    wire [15:0] m_roce_qp_arb_udp_src_port  = m_roce_qp_arb_udp.src_port;
    wire [15:0] m_roce_qp_arb_udp_dest_port = m_roce_qp_arb_udp.dest_port;
    wire [15:0] m_roce_qp_arb_udp_length    = m_roce_qp_arb_udp.length;
    wire [15:0] m_roce_qp_arb_udp_checksum  = m_roce_qp_arb_udp.checksum;


    wire [31:0] m_roce_qp_arb_ip_dest_ip  = m_roce_qp_arb_hdr[(ARB_HEADER_LENGTH-12-3-16-4-8)*8-1     -: 4*8];

    wire arb_has_reth =
    m_roce_qp_arb_bth_op_code == RC_RDMA_WRITE_FIRST ||
    m_roce_qp_arb_bth_op_code == RC_RDMA_WRITE_ONLY ||
    m_roce_qp_arb_bth_op_code == RC_RDMA_WRITE_ONLY_IMD;

    wire arb_has_immediate =
    m_roce_qp_arb_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
    m_roce_qp_arb_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
    m_roce_qp_arb_bth_op_code == RC_SEND_LAST_IMD ||
    m_roce_qp_arb_bth_op_code == RC_SEND_ONLY_IMD ;

    // Retransmission module output 
    wire        m_roce_retrans_bth_valid;
    wire        m_roce_retrans_bth_ready;
    wire [7:0]  m_roce_retrans_bth_op_code;
    wire [15:0] m_roce_retrans_bth_p_key  ;
    wire [23:0] m_roce_retrans_bth_psn    ;
    wire [23:0] m_roce_retrans_bth_dest_qp;
    wire        m_roce_retrans_bth_ack_req;
    wire [23:0] m_roce_retrans_bth_src_qp;;

    wire        m_roce_retrans_reth_valid;
    wire        m_roce_retrans_reth_ready;
    wire [63:0] m_roce_retrans_reth_v_addr;
    wire [31:0] m_roce_retrans_reth_r_key ;
    wire [31:0] m_roce_retrans_reth_length;

    wire        m_roce_retrans_immdh_valid;
    wire        m_roce_retrans_immdh_ready;
    wire [31:0] m_roce_retrans_immdh_data;

    wire [15:0] m_roce_retrans_udp_src_port;
    wire [15:0] m_roce_retrans_udp_dest_port;
    wire [15:0] m_roce_retrans_udp_length  ;
    wire [15:0] m_roce_retrans_udp_checksum;

    wire [31:0] m_roce_retrans_ip_dest_ip;

    wire [OUT_DATA_WIDTH-1 :0]     m_roce_retrans_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH-1 :0]     m_roce_retrans_payload_axis_tkeep;
    wire                           m_roce_retrans_payload_axis_tvalid;
    wire                           m_roce_retrans_payload_axis_tready;
    wire                           m_roce_retrans_payload_axis_tlast;
    wire                           m_roce_retrans_payload_axis_tuser;

    wire [N_QUEUE_PAIRS-1:0] stall_qp;

    // arbitrated qp state requests (from various queue pairs)
    axis_arb_mux #(
        .S_COUNT(N_QUEUE_PAIRS),
        .DATA_WIDTH(24),
        .KEEP_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0)
    ) axis_arb_mux_qp_state_req (
        .clk(clk),
        .rst(rst),

        .s_axis_tdata (qp_local_qpn_arb_req),
        .s_axis_tkeep (0),
        .s_axis_tvalid(qp_context_arb_req_valid),
        .s_axis_tready(qp_context_arb_req_ready),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_axis_tdata (m_qp_context_loc_qpn_req),
        .m_axis_tvalid(m_qp_context_req_valid),
        .m_axis_tready(m_qp_context_req_ready)
    );

    // arbitrated qp update requests (from various queue pairs)
    axis_arb_mux #(
        .S_COUNT(N_QUEUE_PAIRS),
        .DATA_WIDTH(48),
        .KEEP_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0)
    ) axis_arb_mux_update_qp_state_req (
        .clk(clk),
        .rst(rst),

        .s_axis_tdata (qp_update_context_loc_qpn_rem_psn_arb),
        .s_axis_tkeep (0),
        .s_axis_tvalid(qp_update_context_arb_valid),
        .s_axis_tready(qp_update_context_arb_ready),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_axis_tdata({m_qp_update_context_rem_psn, m_qp_update_context_loc_qpn}),
        .m_axis_tvalid(m_qp_update_context_valid),
        .m_axis_tready(m_qp_update_context_ready)
    );

    // TX QUEUES
    generate
        genvar i;
        for (i=0; i<N_QUEUE_PAIRS; i=i+1) begin

            wire roce_tx_eng_bth_valid  ;
            wire roce_tx_eng_reth_valid ;
            wire roce_tx_eng_immdh_valid;

            wire roce_tx_eng_bth_ready  ;
            wire roce_tx_eng_reth_ready ;
            wire roce_tx_eng_immdh_ready;

            wire [7:0]  roce_tx_eng_bth_op_code;
            wire [15:0] roce_tx_eng_bth_p_key  ;
            wire [23:0] roce_tx_eng_bth_psn    ;
            wire [23:0] roce_tx_eng_bth_dest_qp;
            wire [23:0] roce_tx_eng_bth_src_qp;
            wire        roce_tx_eng_bth_ack_req;

            wire [63:0] roce_tx_eng_reth_v_addr;
            wire [31:0] roce_tx_eng_reth_r_key ;
            wire [31:0] roce_tx_eng_reth_length;

            wire [31:0] roce_tx_eng_immdh_data;

            wire [15:0] roce_tx_eng_udp_src_port ;
            wire [15:0] roce_tx_eng_udp_dest_port;
            wire [15:0] roce_tx_eng_udp_length   ;
            wire [15:0] roce_tx_eng_udp_checksum ;

            wire [31:0] roce_tx_eng_ip_src_ip;
            wire [31:0] roce_tx_eng_ip_dest_ip;

            wire [QP_CH_DATA_WIDTH - 1 : 0] roce_tx_eng_payload_axis_tdata;
            wire [QP_CH_KEEP_WIDTH - 1 : 0] roce_tx_eng_payload_axis_tkeep;
            wire                            roce_tx_eng_payload_axis_tvalid;
            wire                            roce_tx_eng_payload_axis_tlast;
            wire                            roce_tx_eng_payload_axis_tuser;
            wire                            roce_tx_eng_payload_axis_tready;

            wire roce_tx_eng_post_align_bth_valid  ;
            wire roce_tx_eng_post_align_reth_valid ;
            wire roce_tx_eng_post_align_immdh_valid;

            wire roce_tx_eng_post_align_bth_ready  ;
            wire roce_tx_eng_post_align_reth_ready ;
            wire roce_tx_eng_post_align_immdh_ready;

            wire [7:0]  roce_tx_eng_post_align_bth_op_code;
            wire [15:0] roce_tx_eng_post_align_bth_p_key  ;
            wire [23:0] roce_tx_eng_post_align_bth_psn    ;
            wire [23:0] roce_tx_eng_post_align_bth_dest_qp;
            wire [23:0] roce_tx_eng_post_align_bth_src_qp;
            wire        roce_tx_eng_post_align_bth_ack_req;

            wire [63:0] roce_tx_eng_post_align_reth_v_addr;
            wire [31:0] roce_tx_eng_post_align_reth_r_key ;
            wire [31:0] roce_tx_eng_post_align_reth_length;

            wire [31:0] roce_tx_eng_post_align_immdh_data;

            wire [15:0] roce_tx_eng_post_align_udp_src_port ;
            wire [15:0] roce_tx_eng_post_align_udp_dest_port;
            wire [15:0] roce_tx_eng_post_align_udp_length   ;
            wire [15:0] roce_tx_eng_post_align_udp_checksum ;

            wire [31:0] roce_tx_eng_post_align_ip_src_ip;
            wire [31:0] roce_tx_eng_post_align_ip_dest_ip;

            wire [ARB_HEADER_LENGTH*8-1:0] roce_arb_header_temp, roce_arb_header_reg_temp;
            wire roce_arb_header_reg_temp_valid;
            wire roce_arb_header_reg_temp_ready;
            wire roce_bth_hdr_t roce_arb_bth_temp;
            wire roce_reth_hdr_t roce_arb_reth_temp;
            wire roce_immd_hdr_t roce_arb_immdh_temp;

            wire udp_hdr_t roce_arb_udp_temp;


            wire         m_wr_req_data_gen_valid;
            wire         m_wr_req_data_gen_ready;
            wire         m_wr_req_data_gen_tx_type;
            wire         m_wr_req_data_gen_is_immediate;
            wire [31:0]  m_wr_req_data_gen_immediate_data;
            wire [23:0]  m_wr_req_data_gen_loc_qp;
            wire [63:0]  m_wr_req_data_gen_addr_offset;
            wire [31:0]  m_wr_req_data_gen_dma_length;

            wire [QP_CH_DATA_WIDTH-1:0] m_axis_data_gen_tdata;
            wire [QP_CH_KEEP_WIDTH-1:0] m_axis_data_gen_tkeep;
            wire  m_axis_data_gen_tvalid;
            wire  m_axis_data_gen_tready;
            wire  m_axis_data_gen_tlast;
            wire  m_axis_data_gen_tuser;

            wire stop_transfer;
            wire en_retrans = 1'b1;

            wire rst_tx_engine = cm_qp_valid && cm_qp_loc_qpn == (BASE_LOC_QPN+i) && cm_qp_req_type == REQ_OPEN_QP;
            wire stop_data_gen = cm_qp_valid && cm_qp_loc_qpn == (BASE_LOC_QPN+i) && cm_qp_req_type == REQ_CLOSE_QP;


            RoCE_tx_queue #(
                .DATA_WIDTH(QP_CH_DATA_WIDTH),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .LOCAL_QPN(BASE_LOC_QPN+i),
                .REFRESH_CACHE_TICKS(REFRESH_CACHE_TICKS)
            ) RoCE_tx_queue_instance (
                .clk(clk),
                .rst(rst | rst_tx_engine),


                .s_wr_req_valid            (s_wr_req_valid[i]),
                .s_wr_req_ready            (s_wr_req_ready[i]),
                .s_wr_req_tx_type          (s_wr_req_tx_type[i]),
                .s_wr_req_is_immediate     (s_wr_req_is_immediate[i]),
                .s_wr_req_immediate_data   (s_wr_req_immediate_data[i]),
                .s_wr_req_loc_qp           (s_wr_req_loc_qp[i]),
                .s_wr_req_addr_offset      (s_wr_req_addr_offset[i]),
                .s_wr_req_dma_length       (s_wr_req_dma_length[i]),
                .s_payload_axis_tdata      (s_axis_tdata[i]),
                .s_payload_axis_tkeep      (s_axis_tkeep[i]),
                .s_payload_axis_tvalid     (s_axis_tvalid[i]),
                .s_payload_axis_tready     (s_axis_tready[i]),
                .s_payload_axis_tlast      (s_axis_tlast[i]),
                .s_payload_axis_tuser      (s_axis_tuser[i]),

                .m_roce_bth_valid          (roce_tx_eng_bth_valid),
                .m_roce_reth_valid         (roce_tx_eng_reth_valid),
                .m_roce_immdh_valid        (roce_tx_eng_immdh_valid),
                .m_roce_bth_ready          (roce_tx_eng_bth_ready),
                .m_roce_reth_ready         (roce_tx_eng_reth_ready),
                .m_roce_immdh_ready        (roce_tx_eng_immdh_ready),
                .m_roce_bth_op_code        (roce_tx_eng_bth_op_code),
                .m_roce_bth_p_key          (roce_tx_eng_bth_p_key),
                .m_roce_bth_psn            (roce_tx_eng_bth_psn),
                .m_roce_bth_dest_qp        (roce_tx_eng_bth_dest_qp),
                .m_roce_bth_src_qp         (roce_tx_eng_bth_src_qp),
                .m_roce_bth_ack_req        (roce_tx_eng_bth_ack_req),
                .m_roce_reth_v_addr        (roce_tx_eng_reth_v_addr),
                .m_roce_reth_r_key         (roce_tx_eng_reth_r_key),
                .m_roce_reth_length        (roce_tx_eng_reth_length),
                .m_roce_immdh_data         (roce_tx_eng_immdh_data),
                .m_roce_eth_dest_mac       (),
                .m_roce_eth_src_mac        (),
                .m_roce_eth_type           (),
                .m_roce_ip_version         (),
                .m_roce_ip_ihl             (),
                .m_roce_ip_dscp            (),
                .m_roce_ip_ecn             (),
                .m_roce_ip_identification  (),
                .m_roce_ip_flags           (),
                .m_roce_ip_fragment_offset (),
                .m_roce_ip_ttl             (),
                .m_roce_ip_protocol        (),
                .m_roce_ip_header_checksum (),
                .m_roce_ip_source_ip       (roce_tx_eng_ip_src_ip),
                .m_roce_ip_dest_ip         (roce_tx_eng_ip_dest_ip),
                .m_roce_udp_source_port    (roce_tx_eng_udp_src_port),
                .m_roce_udp_dest_port      (roce_tx_eng_udp_dest_port),
                .m_roce_udp_length         (roce_tx_eng_udp_length),
                .m_roce_udp_checksum       (roce_tx_eng_udp_checksum),
                .m_roce_payload_axis_tdata (roce_tx_eng_payload_axis_tdata),
                .m_roce_payload_axis_tkeep (roce_tx_eng_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid(roce_tx_eng_payload_axis_tvalid),
                .m_roce_payload_axis_tlast (roce_tx_eng_payload_axis_tlast),
                .m_roce_payload_axis_tuser (roce_tx_eng_payload_axis_tuser),
                .m_roce_payload_axis_tready(roce_tx_eng_payload_axis_tready),

                // update QP state interface
                .m_qp_update_context_valid(qp_update_context_arb_valid[i]),
                .m_qp_update_context_ready(qp_update_context_arb_ready[i]),
                .m_qp_update_context_loc_qpn(qp_update_context_loc_qpn_rem_psn_arb[48*i    +: 24]),
                .m_qp_update_context_rem_psn(qp_update_context_loc_qpn_rem_psn_arb[48*i+24 +: 24]),

                .wr_error_qp_not_rts_out  (wr_error_qp_not_rts_out[i]),
                .wr_error_loc_qpn_out     (wr_error_loc_qpn_out[i]),

                // initialize module with qp parameteres (from CM)
                .cm_qp_valid              (cm_qp_valid && cm_qp_loc_qpn == (BASE_LOC_QPN+i)),
                .cm_qp_req_type           (cm_qp_req_type),
                .cm_qp_dma_transfer_length(cm_qp_dma_transfer_length),
                .cm_qp_rem_qpn            (cm_qp_rem_qpn),
                .cm_qp_loc_qpn            (cm_qp_loc_qpn),
                .cm_qp_rem_psn            (cm_qp_rem_psn),
                .cm_qp_loc_psn            (cm_qp_loc_psn),
                .cm_qp_r_key              (cm_qp_r_key),
                .cm_qp_rem_addr           (cm_qp_rem_addr),
                .cm_qp_rem_ip_addr        (cm_qp_rem_ip_addr),

                .qp_is_immediate(qp_is_immediate),
                .qp_tx_type     (qp_tx_type),

                // request to qp state
                .m_qp_context_req_valid(qp_context_arb_req_valid[i]),
                .m_qp_context_req_ready(qp_context_arb_req_ready[i]),
                .m_qp_local_qpn_req(qp_local_qpn_arb_req[24*i +: 24]),
                // reply from qp state
                .s_qp_req_context_valid(s_qp_context_req_valid && s_qp_context_req_loc_qpn == (BASE_LOC_QPN+i)),
                .s_qp_req_state        (s_qp_context_req_state),
                .s_qp_req_rem_qpn      (s_qp_context_req_rem_qpn),
                .s_qp_req_loc_qpn      (s_qp_context_req_loc_qpn),
                .s_qp_req_rem_psn      (s_qp_context_req_rem_psn),
                .s_qp_req_loc_psn      (s_qp_context_req_loc_psn),
                .s_qp_req_r_key        (s_qp_context_req_r_key),
                .s_qp_req_rem_addr     (s_qp_context_req_rem_addr),
                .s_qp_req_rem_ip_addr  (s_qp_context_req_rem_ip_addr),

                //.stall(stall_qp[i]),
                .stall(1'b0),

                .pmtu(pmtu),
                .RoCE_udp_port(ROCE_UDP_PORT),
                .loc_ip_addr(32'd0)
            );

            RoCE_realign_frame_fifo #(
                .S_DATA_WIDTH(QP_CH_DATA_WIDTH),
                .M_DATA_WIDTH(OUT_DATA_WIDTH),
                .HAS_ADAPTER(1),
                .IS_ASYNC(0),
                .FIFO_DEPTH(8192-(OUT_DATA_WIDTH/8)),
                .RAM_PIPELINE(1),
                .FRAME_FIFO(1),
                .PAUSE_ENABLE(1),
                .FRAME_PAUSE(1)
            ) RoCE_realign_frame_fifo_instance (
                .s_clk(clk),
                .s_rst(rst | rst_tx_engine),
                .s_roce_bth_valid    (roce_tx_eng_bth_valid),
                .s_roce_bth_ready    (roce_tx_eng_bth_ready),
                .s_roce_bth_op_code  (roce_tx_eng_bth_op_code),
                .s_roce_bth_p_key    (roce_tx_eng_bth_p_key),
                .s_roce_bth_psn      (roce_tx_eng_bth_psn),
                .s_roce_bth_dest_qp  (roce_tx_eng_bth_dest_qp),
                .s_roce_bth_src_qp   (roce_tx_eng_bth_src_qp),
                .s_roce_bth_ack_req  (roce_tx_eng_bth_ack_req),
                .s_roce_reth_valid   (roce_tx_eng_reth_valid),
                .s_roce_reth_ready   (roce_tx_eng_reth_ready),
                .s_roce_reth_v_addr  (roce_tx_eng_reth_v_addr),
                .s_roce_reth_r_key   (roce_tx_eng_reth_r_key),
                .s_roce_reth_length  (roce_tx_eng_reth_length),
                .s_roce_immdh_valid  (roce_tx_eng_immdh_valid),
                .s_roce_immdh_ready  (roce_tx_eng_immdh_ready),
                .s_roce_immdh_data   (roce_tx_eng_immdh_data),
                .s_ip_dest_ip        (roce_tx_eng_ip_dest_ip),
                .s_udp_dest_port     (roce_tx_eng_udp_dest_port),
                .s_udp_length        (roce_tx_eng_udp_length),

                .s_roce_payload_axis_tdata (roce_tx_eng_payload_axis_tdata),
                .s_roce_payload_axis_tkeep (roce_tx_eng_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid(roce_tx_eng_payload_axis_tvalid),
                .s_roce_payload_axis_tready(roce_tx_eng_payload_axis_tready),
                .s_roce_payload_axis_tlast (roce_tx_eng_payload_axis_tlast),
                .s_roce_payload_axis_tuser (roce_tx_eng_payload_axis_tuser),

                .m_clk(clk),
                .m_rst(rst | rst_tx_engine),

                .m_roce_bth_valid          (roce_tx_eng_post_align_bth_valid),
                .m_roce_bth_ready          (roce_tx_eng_post_align_bth_ready),
                .m_roce_bth_op_code        (roce_tx_eng_post_align_bth_op_code),
                .m_roce_bth_p_key          (roce_tx_eng_post_align_bth_p_key),
                .m_roce_bth_psn            (roce_tx_eng_post_align_bth_psn),
                .m_roce_bth_dest_qp        (roce_tx_eng_post_align_bth_dest_qp),
                .m_roce_bth_src_qp         (roce_tx_eng_post_align_bth_src_qp),
                .m_roce_bth_ack_req        (roce_tx_eng_post_align_bth_ack_req),
                .m_roce_reth_valid         (roce_tx_eng_post_align_reth_valid),
                .m_roce_reth_ready         (roce_tx_eng_post_align_reth_ready),
                .m_roce_reth_v_addr        (roce_tx_eng_post_align_reth_v_addr),
                .m_roce_reth_r_key         (roce_tx_eng_post_align_reth_r_key),
                .m_roce_reth_length        (roce_tx_eng_post_align_reth_length),
                .m_roce_immdh_valid        (roce_tx_eng_post_align_immdh_valid),
                .m_roce_immdh_ready        (roce_tx_eng_post_align_immdh_ready),
                .m_roce_immdh_data         (roce_tx_eng_post_align_immdh_data),
                .m_eth_dest_mac            (),
                .m_eth_src_mac             (),
                .m_eth_type                (),
                .m_ip_version              (),
                .m_ip_ihl                  (),
                .m_ip_dscp                 (),
                .m_ip_ecn                  (),
                .m_ip_identification       (),
                .m_ip_flags                (),
                .m_ip_fragment_offset      (),
                .m_ip_ttl                  (),
                .m_ip_protocol             (),
                .m_ip_header_checksum      (),
                .m_ip_source_ip            (roce_tx_eng_post_align_ip_src_ip),
                .m_ip_dest_ip              (roce_tx_eng_post_align_ip_dest_ip),
                .m_udp_source_port         (roce_tx_eng_post_align_udp_src_port),
                .m_udp_dest_port           (roce_tx_eng_post_align_udp_dest_port),
                .m_udp_length              (roce_tx_eng_post_align_udp_length),
                .m_udp_checksum            (roce_tx_eng_post_align_udp_checksum),

                .m_roce_payload_axis_tdata (s_roce_qp_arb_payload_axis_tdata[OUT_DATA_WIDTH*i +: OUT_DATA_WIDTH]),
                .m_roce_payload_axis_tkeep (s_roce_qp_arb_payload_axis_tkeep[OUT_KEEP_WIDTH*i +: OUT_KEEP_WIDTH]),
                .m_roce_payload_axis_tvalid(s_roce_qp_arb_payload_axis_tvalid[i]),
                .m_roce_payload_axis_tready(s_roce_qp_arb_payload_axis_tready[i]),
                .m_roce_payload_axis_tlast (s_roce_qp_arb_payload_axis_tlast[i]),
                .m_roce_payload_axis_tuser (s_roce_qp_arb_payload_axis_tuser[i]),

                .stall(stall_qp[i]),
                .loc_ip_addr(32'd0)
            );

            assign roce_arb_bth_temp.op_code        = roce_tx_eng_post_align_bth_op_code;
            assign roce_arb_bth_temp.p_key          = roce_tx_eng_post_align_bth_p_key;
            assign roce_arb_bth_temp.psn            = roce_tx_eng_post_align_bth_psn;
            assign roce_arb_bth_temp.qp_number      = roce_tx_eng_post_align_bth_dest_qp;
            assign roce_arb_bth_temp.ack_request    = roce_tx_eng_post_align_bth_ack_req;
            assign roce_arb_bth_temp.fecn           = 1'b0;
            assign roce_arb_bth_temp.becn           = 1'b0;
            assign roce_arb_bth_temp.sol_event      = 1'b0;
            assign roce_arb_bth_temp.mig_request    = 1'b1;
            assign roce_arb_bth_temp.pad_count      = 2'b00;
            assign roce_arb_bth_temp.header_version = 4'd0;
            assign roce_arb_bth_temp.reserved_0     = 'd0;
            assign roce_arb_bth_temp.reserved_1     = 'd0;

            assign roce_arb_reth_temp.vaddr      = roce_tx_eng_post_align_reth_v_addr;
            assign roce_arb_reth_temp.r_key      = roce_tx_eng_post_align_reth_r_key;
            assign roce_arb_reth_temp.dma_length = roce_tx_eng_post_align_reth_length;

            assign roce_arb_immdh_temp.immediate_data     = roce_tx_eng_post_align_immdh_data;

            assign roce_arb_udp_temp.src_port   = roce_tx_eng_post_align_udp_src_port;
            assign roce_arb_udp_temp.dest_port  = roce_tx_eng_post_align_udp_dest_port;
            assign roce_arb_udp_temp.length     = roce_tx_eng_post_align_udp_length;
            assign roce_arb_udp_temp.checksum   = roce_tx_eng_post_align_udp_checksum;

            assign roce_arb_header_temp =
            {
            roce_arb_bth_temp,
            roce_tx_eng_bth_src_qp,
            roce_arb_reth_temp,
            roce_arb_immdh_temp,
            roce_arb_udp_temp,
            roce_tx_eng_ip_dest_ip
            };

            assign roce_tx_eng_post_align_bth_ready      = s_roce_qp_arb_hdr_ready[i];
            assign roce_tx_eng_post_align_reth_ready     = s_roce_qp_arb_hdr_ready[i];
            assign roce_tx_eng_post_align_immdh_ready    = s_roce_qp_arb_hdr_ready[i];

            assign s_roce_arb_header[i*(ARB_HEADER_LENGTH)*8 +: (ARB_HEADER_LENGTH)*8] = roce_arb_header_temp;

            assign s_roce_qp_arb_hdr_valid[i]      = roce_tx_eng_post_align_bth_valid;

        end
    endgenerate

    generic_arb_mux #(
        .S_COUNT              (N_QUEUE_PAIRS),
        .DATA_WIDTH           (OUT_DATA_WIDTH),
        .KEEP_ENABLE          (OUT_KEEP_ENABLE),
        .KEEP_WIDTH           (OUT_KEEP_WIDTH),
        .ID_ENABLE            (0),
        .DEST_ENABLE          (0),
        .USER_ENABLE          (1),
        .USER_WIDTH           (1),
        .ARB_TYPE_ROUND_ROBIN (1),
        .HEADER_WIDTH         (ARB_HEADER_LENGTH) // BTH + SRC_QPN + RETH + IMMD + UDP + IP_ADDR
    ) RoCE_TX_eng_arb_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_hdr_valid          (s_roce_qp_arb_hdr_valid),
        .s_hdr_ready          (s_roce_qp_arb_hdr_ready),
        .s_hdr                (s_roce_arb_header),
        .s_payload_axis_tdata (s_roce_qp_arb_payload_axis_tdata),
        .s_payload_axis_tkeep (s_roce_qp_arb_payload_axis_tkeep),
        .s_payload_axis_tvalid(s_roce_qp_arb_payload_axis_tvalid),
        .s_payload_axis_tready(s_roce_qp_arb_payload_axis_tready),
        .s_payload_axis_tlast (s_roce_qp_arb_payload_axis_tlast),
        .s_payload_axis_tid   (0),
        .s_payload_axis_tdest (0),
        .s_payload_axis_tuser (s_roce_qp_arb_payload_axis_tuser),
        .m_hdr_valid          (m_roce_qp_arb_hdr_valid),
        .m_hdr_ready          (m_roce_qp_arb_hdr_ready),
        .m_hdr                (m_roce_qp_arb_hdr),
        .m_payload_axis_tdata (m_roce_qp_arb_payload_axis_tdata),
        .m_payload_axis_tkeep (m_roce_qp_arb_payload_axis_tkeep),
        .m_payload_axis_tvalid(m_roce_qp_arb_payload_axis_tvalid),
        .m_payload_axis_tready(m_roce_qp_arb_payload_axis_tready),
        .m_payload_axis_tlast (m_roce_qp_arb_payload_axis_tlast),
        .m_payload_axis_tid   (),
        .m_payload_axis_tdest (),
        .m_payload_axis_tuser (m_roce_qp_arb_payload_axis_tuser)
    );

    RoCE_retransmission_module_v2 #(
        .DATA_WIDTH           (OUT_DATA_WIDTH),
        .BUFFER_ADDR_WIDTH    (RETRANSMISSION_ADDR_BUFFER_WIDTH), // total buffer, all QPs
        .BASE_LOC_QPN         (BASE_LOC_QPN),
        .MAX_QPS              (N_QUEUE_PAIRS),
        .CLOCK_PERIOD         (CLOCK_PERIOD),
        .OUTPUT_AXI_FIFO_DEPTH(0)
    ) RoCE_retransmission_module_v2_instance (
        .clk(clk),
        .rst(rst),
        .flow_ctrl_pause(flow_ctrl_pause),
        .s_roce_rx_bth_valid         (s_roce_rx_bth_valid    ),
        .s_roce_rx_bth_ready         (s_roce_rx_bth_ready    ),
        .s_roce_rx_bth_psn           (s_roce_rx_bth_psn      ),
        .s_roce_rx_bth_op_code       (s_roce_rx_bth_op_code  ),
        .s_roce_rx_bth_dest_qp       (s_roce_rx_bth_dest_qp  ),
        .s_roce_rx_aeth_valid        (s_roce_rx_aeth_valid   ),
        .s_roce_rx_aeth_ready        (s_roce_rx_aeth_ready   ),
        .s_roce_rx_aeth_syndrome     (s_roce_rx_aeth_syndrome),
        .s_roce_rx_last_not_acked_psn(),

        .s_roce_bth_valid    (m_roce_qp_arb_hdr_valid),
        .s_roce_bth_ready    (m_roce_qp_arb_hdr_ready),
        .s_roce_bth_op_code  (m_roce_qp_arb_bth_op_code),
        .s_roce_bth_p_key    (m_roce_qp_arb_bth_p_key),
        .s_roce_bth_psn      (m_roce_qp_arb_bth_psn),
        .s_roce_bth_dest_qp  (m_roce_qp_arb_bth_dest_qp),
        .s_roce_bth_src_qp   (m_roce_qp_arb_bth_src_qp),
        .s_roce_bth_ack_req  (m_roce_qp_arb_bth_ack_req),
        .s_roce_reth_valid   (m_roce_qp_arb_hdr_valid && arb_has_reth),
        .s_roce_reth_ready   (),
        .s_roce_reth_v_addr  (m_roce_qp_arb_reth_v_addr),
        .s_roce_reth_r_key   (m_roce_qp_arb_reth_r_key),
        .s_roce_reth_length  (m_roce_qp_arb_reth_length),
        .s_roce_immdh_valid  (m_roce_qp_arb_hdr_valid && arb_has_immediate),
        .s_roce_immdh_ready  (),
        .s_roce_immdh_data   (m_roce_qp_arb_immdh_data),
        .s_eth_dest_mac      (48'd0),
        .s_eth_src_mac       (48'd0),
        .s_eth_type          (16'd0),
        .s_ip_version        (4'd4),
        .s_ip_ihl            (4'd0),
        .s_ip_dscp           (6'd0),
        .s_ip_ecn            (2'd0),
        .s_ip_identification (16'd0),
        .s_ip_flags          (3'b001),
        .s_ip_fragment_offset(13'd0),
        .s_ip_ttl            (8'h40),
        .s_ip_protocol       (8'h11),
        .s_ip_header_checksum(16'd0),
        .s_ip_source_ip      (32'd0),
        .s_ip_dest_ip        (m_roce_qp_arb_ip_dest_ip),
        .s_udp_source_port   (16'h8657),
        .s_udp_dest_port     (m_roce_qp_arb_udp_dest_port),
        .s_udp_length        (m_roce_qp_arb_udp_length),
        .s_udp_checksum      (m_roce_qp_arb_udp_checksum),

        .s_roce_payload_axis_tdata      (m_roce_qp_arb_payload_axis_tdata),
        .s_roce_payload_axis_tkeep      (m_roce_qp_arb_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid     (m_roce_qp_arb_payload_axis_tvalid),
        .s_roce_payload_axis_tready     (m_roce_qp_arb_payload_axis_tready),
        .s_roce_payload_axis_tlast      (m_roce_qp_arb_payload_axis_tlast),
        .s_roce_payload_axis_tuser      (m_roce_qp_arb_payload_axis_tuser),

        .m_roce_bth_valid    (m_roce_bth_valid),
        .m_roce_bth_ready    (m_roce_bth_ready),
        .m_roce_bth_op_code  (m_roce_bth_op_code),
        .m_roce_bth_p_key    (m_roce_bth_p_key),
        .m_roce_bth_psn      (m_roce_bth_psn),
        .m_roce_bth_dest_qp  (m_roce_bth_dest_qp),
        .m_roce_bth_src_qp   (m_roce_bth_src_qp),
        .m_roce_bth_ack_req  (m_roce_bth_ack_req),
        .m_roce_reth_valid   (m_roce_reth_valid),
        .m_roce_reth_ready   (m_roce_reth_ready),
        .m_roce_reth_v_addr  (m_roce_reth_v_addr),
        .m_roce_reth_r_key   (m_roce_reth_r_key),
        .m_roce_reth_length  (m_roce_reth_length),
        .m_roce_immdh_valid  (m_roce_immdh_valid),
        .m_roce_immdh_ready  (m_roce_immdh_ready),
        .m_roce_immdh_data   (m_roce_immdh_data),
        .m_eth_dest_mac      (),
        .m_eth_src_mac       (),
        .m_eth_type          (),
        .m_ip_version        (),
        .m_ip_ihl            (),
        .m_ip_dscp           (),
        .m_ip_ecn            (),
        .m_ip_identification (),
        .m_ip_flags          (),
        .m_ip_fragment_offset(),
        .m_ip_ttl            (),
        .m_ip_protocol       (),
        .m_ip_header_checksum(),
        .m_ip_source_ip      (),
        .m_ip_dest_ip        (m_ip_dest_ip),
        .m_udp_source_port   (m_udp_source_port),
        .m_udp_dest_port     (m_udp_dest_port),
        .m_udp_length        (m_udp_length),
        .m_udp_checksum      (m_udp_checksum),

        .m_roce_payload_axis_tdata (m_roce_payload_axis_tdata),
        .m_roce_payload_axis_tkeep (m_roce_payload_axis_tkeep),
        .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_payload_axis_tlast),
        .m_roce_payload_axis_tuser (m_roce_payload_axis_tuser),

        // AXI master to Memory
        .m_axi_awid   (m_axi_awid),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awlen  (m_axi_awlen),
        .m_axi_awsize (m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock (m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot (m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wlast  (m_axi_wlast),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bid    (m_axi_bid),
        .m_axi_bresp  (m_axi_bresp),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .m_axi_arid   (m_axi_arid),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arlen  (m_axi_arlen),
        .m_axi_arsize (m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock (m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot (m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid    (m_axi_rid),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rlast  (m_axi_rlast),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready),


        .cm_qp_valid              (cm_qp_valid),
        .cm_qp_req_type           (cm_qp_req_type),
        .cm_qp_dma_transfer_length(cm_qp_dma_transfer_length),
        .cm_qp_rem_qpn            (cm_qp_rem_qpn),
        .cm_qp_loc_qpn            (cm_qp_loc_qpn),
        .cm_qp_rem_psn            (cm_qp_rem_psn),
        .cm_qp_loc_psn            (cm_qp_loc_psn),
        .cm_qp_r_key              (cm_qp_r_key),
        .cm_qp_rem_addr           (cm_qp_rem_addr),
        .cm_qp_rem_ip_addr        (cm_qp_rem_ip_addr),
        .qp_is_immediate          (qp_is_immediate),
        .qp_tx_type               (qp_tx_type),

        .m_qp_close_valid  (m_qp_close_valid),
        .m_qp_close_ready  (m_qp_close_ready),
        .m_qp_close_loc_qpn(m_qp_close_loc_qpn),
        .m_qp_close_rem_psn(m_qp_close_rem_psn),

        .stall_qp                 (stall_qp),

        .cfg_valid                (1),
        .timeout_period           (timeout_period),
        .retry_count              (retry_count),
        .rnr_retry_count          (rnr_retry_count),
        .loc_ip_addr              (32'd0),
        .pmtu                     (pmtu),

        .monitor_qpn              (monitor_loc_qpn),
        .n_retransmit_triggers    (n_retransmit_triggers),
        .n_rnr_retransmit_triggers(n_rnr_retransmit_triggers),
        .psn_diff                 (psn_diff)
    );

    generate
        if (DEBUG) begin

            reg  [23:0]                    monitor_loc_qpn_del;

            reg       cm_qp_valid_roce_reg;
            reg [2:0] cm_qp_req_type_roce_reg;

            reg        rx_roce_acks_bth_valid_reg;
            reg        rx_roce_acks_bth_ready_reg;
            reg [23:0] rx_roce_acks_bth_psn_reg;
            reg [23:0] rx_roce_acks_bth_dest_qp_reg;
            reg [7:0]  rx_roce_acks_aeth_syndrome_reg;


            reg        m_roce_bth_valid_reg;
            reg [7:0]  m_roce_bth_op_code_reg;
            reg [23:0] m_roce_bth_psn_reg;
            reg [23:0] m_roce_bth_src_qp_reg;

            reg        m_roce_payload_axis_tvalid_reg;
            reg        m_roce_payload_axis_tlast_reg;



            always @(posedge clk) begin
                if (rst) begin
                    
                end else begin
                    
                    monitor_loc_qpn_del      <= monitor_loc_qpn;

                    cm_qp_valid_roce_reg    <= cm_qp_valid;
                    cm_qp_req_type_roce_reg <= cm_qp_req_type;


                    rx_roce_acks_bth_valid_reg     <= s_roce_rx_bth_valid;
                    rx_roce_acks_bth_ready_reg     <= s_roce_rx_bth_ready;
                    rx_roce_acks_bth_psn_reg       <= s_roce_rx_bth_psn;
                    rx_roce_acks_bth_dest_qp_reg   <= s_roce_rx_bth_dest_qp;
                    rx_roce_acks_aeth_syndrome_reg <= s_roce_rx_aeth_syndrome;

                    m_roce_bth_valid_reg   <= m_roce_bth_valid && m_roce_bth_ready;
                    m_roce_bth_op_code_reg <= m_roce_bth_op_code;
                    m_roce_bth_psn_reg     <= m_roce_bth_psn;
                    m_roce_bth_src_qp_reg  <= m_roce_bth_src_qp;

                    m_roce_payload_axis_tvalid_reg <= m_roce_payload_axis_tvalid && m_roce_payload_axis_tready;
                    m_roce_payload_axis_tlast_reg  <= m_roce_payload_axis_tlast;
                end
            end

            RoCE_latency_eval RoCE_latency_eval_instance (
                .clk(clk),
                .rst(rst),
                .start_i                 (cm_qp_valid_roce_reg && cm_qp_req_type_roce_reg == REQ_OPEN_QP ),
                .s_roce_rx_bth_valid     (rx_roce_acks_bth_valid_reg && rx_roce_acks_bth_ready_reg),
                .s_roce_rx_bth_psn       (rx_roce_acks_bth_psn_reg),
                .s_roce_rx_bth_dest_qp   (rx_roce_acks_bth_dest_qp_reg),
                .s_roce_rx_aeth_syndrome (rx_roce_acks_aeth_syndrome_reg),

                .s_roce_tx_bth_valid     (m_roce_bth_valid_reg),
                .s_roce_tx_bth_op_code   (m_roce_bth_op_code_reg),
                .s_roce_tx_bth_psn       (m_roce_bth_psn_reg),
                .s_roce_tx_bth_src_qp    (m_roce_bth_src_qp_reg),
                .s_axis_tx_payload_valid (m_roce_payload_axis_tvalid_reg),
                .s_axis_tx_payload_last  (m_roce_payload_axis_tlast_reg),
                .transfer_time_avg       (transfer_time_avg),
                .transfer_time_moving_avg(transfer_time_moving_avg),
                .transfer_time_inst      (transfer_time_inst),
                .latency_avg             (latency_avg),
                .latency_moving_avg      (latency_moving_avg),
                .latency_inst            (latency_inst),
                .latency_inst_valid      (latency_inst_valid),
                .cfg_latency_avg_po2     (cfg_latency_avg_po2),
                .cfg_throughput_avg_po2  (cfg_throughput_avg_po2),
                .monitor_loc_qpn         (monitor_loc_qpn)
            );
        end else begin
            assign transfer_time_avg = 0;
            assign transfer_time_moving_avg = 0;
            assign transfer_time_inst = 0;
            assign latency_avg = 0;
            assign latency_moving_avg = 0;
            assign latency_inst = 0;
            assign latency_inst_valid = 1'b0;
        end
    endgenerate



endmodule

`resetall