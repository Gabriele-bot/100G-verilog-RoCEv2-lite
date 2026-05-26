`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_stack_wrapper #(
    parameter QP_CH_DATA_WIDTH                 = 256,
    parameter QP_CH_KEEP_ENABLE                = (QP_CH_DATA_WIDTH>8),
    parameter QP_CH_KEEP_WIDTH                 = (QP_CH_DATA_WIDTH/8),
    parameter OUT_DATA_WIDTH                   = 512,
    parameter OUT_KEEP_ENABLE                  = (OUT_DATA_WIDTH>8),
    parameter OUT_KEEP_WIDTH                   = (OUT_DATA_WIDTH/8),
    parameter CLOCK_PERIOD                     = 6.4, // in ns
    parameter DEBUG                            = 0,
    parameter REFRESH_CACHE_TICKS              = 32768,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 24,
    parameter N_ROCE_TX_ENGINES                = 1,
    parameter N_QUEUE_PAIRS                    = 2,
    parameter OUTPUT_REG                       = 0
) (
    input wire clk_stack,
    input wire rst_stack,

    input wire clk_roce_eng,
    input wire rst_roce_eng,

    input wire flow_ctrl_pause,

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
     * UDP frame input
     */
    input  wire                          s_udp_hdr_valid,
    output wire                          s_udp_hdr_ready,
    input  wire [ 47:0]                  s_eth_dest_mac,
    input  wire [ 47:0]                  s_eth_src_mac,
    input  wire [ 15:0]                  s_eth_type,
    input  wire [  3:0]                  s_ip_version,
    input  wire [  3:0]                  s_ip_ihl,
    input  wire [  5:0]                  s_ip_dscp,
    input  wire [  1:0]                  s_ip_ecn,
    input  wire [ 15:0]                  s_ip_length,
    input  wire [ 15:0]                  s_ip_identification,
    input  wire [  2:0]                  s_ip_flags,
    input  wire [ 12:0]                  s_ip_fragment_offset,
    input  wire [  7:0]                  s_ip_ttl,
    input  wire [  7:0]                  s_ip_protocol,
    input  wire [ 15:0]                  s_ip_header_checksum,
    input  wire [ 31:0]                  s_ip_source_ip,
    input  wire [ 31:0]                  s_ip_dest_ip,
    input  wire [ 15:0]                  s_udp_source_port,
    input  wire [ 15:0]                  s_udp_dest_port,
    input  wire [ 15:0]                  s_udp_length,
    input  wire [ 15:0]                  s_udp_checksum,
    input  wire [ 31:0]                  s_roce_computed_icrc,
    input  wire [OUT_DATA_WIDTH - 1 : 0] s_udp_payload_axis_tdata,
    input  wire [OUT_KEEP_WIDTH - 1 : 0] s_udp_payload_axis_tkeep,
    input  wire                          s_udp_payload_axis_tvalid,
    output wire                          s_udp_payload_axis_tready,
    input  wire                          s_udp_payload_axis_tlast,
    input  wire                          s_udp_payload_axis_tuser,

    /*
     * UDP frame output
     */
    output wire                          m_udp_hdr_valid,
    input  wire                          m_udp_hdr_ready,
    output wire [ 47:0]                  m_eth_dest_mac,
    output wire [ 47:0]                  m_eth_src_mac,
    output wire [ 15:0]                  m_eth_type,
    output wire [  3:0]                  m_ip_version,
    output wire [  3:0]                  m_ip_ihl,
    output wire [  5:0]                  m_ip_dscp,
    output wire [  1:0]                  m_ip_ecn,
    output wire [ 15:0]                  m_ip_length,
    output wire [ 15:0]                  m_ip_identification,
    output wire [  2:0]                  m_ip_flags,
    output wire [ 12:0]                  m_ip_fragment_offset,
    output wire [  7:0]                  m_ip_ttl,
    output wire [  7:0]                  m_ip_protocol,
    output wire [ 15:0]                  m_ip_header_checksum,
    output wire [ 31:0]                  m_ip_source_ip,
    output wire [ 31:0]                  m_ip_dest_ip,
    output wire [ 15:0]                  m_udp_source_port,
    output wire [ 15:0]                  m_udp_dest_port,
    output wire [ 15:0]                  m_udp_length,
    output wire [ 15:0]                  m_udp_checksum,
    output wire [OUT_DATA_WIDTH - 1 : 0] m_udp_payload_axis_tdata,
    output wire [OUT_KEEP_WIDTH - 1 : 0] m_udp_payload_axis_tkeep,
    output wire                          m_udp_payload_axis_tvalid,
    input  wire                          m_udp_payload_axis_tready,
    output wire                          m_udp_payload_axis_tlast,
    output wire                          m_udp_payload_axis_tuser,

    // QP state spy
    input  wire        m_qp_context_spy,
    input  wire [23:0] m_qp_local_qpn_spy,
    output wire        s_qp_spy_context_valid,
    output wire [2 :0] s_qp_spy_state,
    output wire [23:0] s_qp_spy_rem_qpn,
    output wire [23:0] s_qp_spy_loc_qpn,
    output wire [23:0] s_qp_spy_rem_psn,
    output wire [23:0] s_qp_spy_rem_acked_psn,
    output wire [23:0] s_qp_spy_loc_psn,
    output wire [31:0] s_qp_spy_r_key,
    output wire [63:0] s_qp_spy_rem_addr,
    output wire [31:0] s_qp_spy_rem_ip_addr,
    output wire [7:0]  s_qp_spy_syndrome,


    /*
     * Configuration
     */
    input  wire [  2:0] pmtu,
    input  wire [ 31:0] loc_ip_addr,
    input  wire [ 63:0] timeout_period,
    input  wire [ 2 :0] retry_count,
    input  wire [ 2 :0] rnr_retry_count,

    /*
     * LOC QPN status
     */
    input  wire [23:0] monitor_loc_qpn,

    input  wire [3:0]  cfg_latency_avg_po2,
    input  wire [4:0]  cfg_throughput_avg_po2,

    output wire [31:0] transfer_time_avg,
    output wire [31:0] transfer_time_moving_avg,
    output wire [31:0] latency_avg,
    output wire [31:0] latency_moving_avg,

    output wire [23:0] psn_diff,
    output wire [31:0] n_retransmit_triggers,
    output wire [31:0] n_rnr_retransmit_triggers

);

    import RoCE_params::*; // Imports RoCE parameters

    // instntate N_QUEUE_PAIRS modules
    localparam ARB_HEADER_LENGTH = 12+3+16+4+8+4; // BTH + SRC_QPN +  RETH + IMMD + UDP_HDR + DEST_IP_ADDR

    localparam N_AXI_RAM = RETRANSMISSION_ADDR_BUFFER_WIDTH >= 24 ? 8 : (RETRANSMISSION_ADDR_BUFFER_WIDTH >= 22 ? 4 : (RETRANSMISSION_ADDR_BUFFER_WIDTH >= 20 ? 2 : 1)); // needs to be a power of 2
    localparam INTERCONNECT_ADDR_WIDTH = RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_AXI_RAM);

    // UDP frame connections to CM                
    wire                          rx_udp_cm_hdr_valid;
    wire                          rx_udp_cm_hdr_ready;
    wire [31:0]                   rx_udp_cm_ip_source_ip;
    wire [31:0]                   rx_udp_cm_ip_dest_ip;
    wire [15:0]                   rx_udp_cm_source_port;
    wire [15:0]                   rx_udp_cm_dest_port;
    wire [15:0]                   rx_udp_cm_length;
    wire [15:0]                   rx_udp_cm_checksum;
    wire [OUT_DATA_WIDTH - 1 : 0] rx_udp_cm_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH - 1 : 0] rx_udp_cm_payload_axis_tkeep;
    wire                          rx_udp_cm_payload_axis_tvalid;
    wire                          rx_udp_cm_payload_axis_tready;
    wire                          rx_udp_cm_payload_axis_tlast;
    wire                          rx_udp_cm_payload_axis_tuser;

    wire                          tx_udp_cm_hdr_valid;
    wire                          tx_udp_cm_hdr_ready;
    wire [31:0]                   tx_udp_cm_ip_source_ip;
    wire [31:0]                   tx_udp_cm_ip_dest_ip;
    wire [15:0]                   tx_udp_cm_source_port;
    wire [15:0]                   tx_udp_cm_dest_port;
    wire [15:0]                   tx_udp_cm_length;
    wire [15:0]                   tx_udp_cm_checksum;
    wire [OUT_DATA_WIDTH - 1 : 0] tx_udp_cm_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH - 1 : 0] tx_udp_cm_payload_axis_tkeep;
    wire                          tx_udp_cm_payload_axis_tvalid;
    wire                          tx_udp_cm_payload_axis_tready;
    wire                          tx_udp_cm_payload_axis_tlast;
    wire                          tx_udp_cm_payload_axis_tuser;

    // UDP frame connections to RoCE RX
    wire                          rx_udp_RoCE_hdr_valid;
    wire                          rx_udp_RoCE_hdr_ready;
    wire [47:0]                   rx_udp_RoCE_eth_dest_mac;
    wire [47:0]                   rx_udp_RoCE_eth_src_mac;
    wire [15:0]                   rx_udp_RoCE_eth_type;
    wire [3:0]                    rx_udp_RoCE_ip_version;
    wire [3:0]                    rx_udp_RoCE_ip_ihl;
    wire [5:0]                    rx_udp_RoCE_ip_dscp;
    wire [1:0]                    rx_udp_RoCE_ip_ecn;
    wire [15:0]                   rx_udp_RoCE_ip_length;
    wire [15:0]                   rx_udp_RoCE_ip_identification;
    wire [2:0]                    rx_udp_RoCE_ip_flags;
    wire [12:0]                   rx_udp_RoCE_ip_fragment_offset;
    wire [7:0]                    rx_udp_RoCE_ip_ttl;
    wire [7:0]                    rx_udp_RoCE_ip_protocol;
    wire [15:0]                   rx_udp_RoCE_ip_header_checksum;
    wire [31:0]                   rx_udp_RoCE_ip_source_ip;
    wire [31:0]                   rx_udp_RoCE_ip_dest_ip;
    wire [15:0]                   rx_udp_RoCE_source_port;
    wire [15:0]                   rx_udp_RoCE_dest_port;
    wire [15:0]                   rx_udp_RoCE_length;
    wire [15:0]                   rx_udp_RoCE_checksum;
    wire [OUT_DATA_WIDTH - 1 : 0] rx_udp_RoCE_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH - 1 : 0] rx_udp_RoCE_payload_axis_tkeep;
    wire                          rx_udp_RoCE_payload_axis_tvalid;
    wire                          rx_udp_RoCE_payload_axis_tready;
    wire                          rx_udp_RoCE_payload_axis_tlast;
    wire                          rx_udp_RoCE_payload_axis_tuser;

    // UDP stream from RoCE TX
    wire                           tx_roce_udp_hdr_valid;
    wire                           tx_roce_udp_hdr_ready;
    wire [ 47:0]                   tx_roce_eth_dest_mac;
    wire [ 47:0]                   tx_roce_eth_src_mac;
    wire [ 15:0]                   tx_roce_eth_type;
    wire [  3:0]                   tx_roce_ip_version;
    wire [  3:0]                   tx_roce_ip_ihl;
    wire [  5:0]                   tx_roce_ip_dscp;
    wire [  1:0]                   tx_roce_ip_ecn;
    wire [ 15:0]                   tx_roce_ip_length;
    wire [ 15:0]                   tx_roce_ip_identification;
    wire [  2:0]                   tx_roce_ip_flags;
    wire [ 12:0]                   tx_roce_ip_fragment_offset;
    wire [  7:0]                   tx_roce_ip_ttl;
    wire [  7:0]                   tx_roce_ip_protocol;
    wire [ 15:0]                   tx_roce_ip_header_checksum;
    wire [ 31:0]                   tx_roce_ip_source_ip;
    wire [ 31:0]                   tx_roce_ip_dest_ip;
    wire [ 15:0]                   tx_roce_udp_source_port;
    wire [ 15:0]                   tx_roce_udp_dest_port;
    wire [ 15:0]                   tx_roce_udp_length;
    wire [ 15:0]                   tx_roce_udp_checksum;
    wire [OUT_DATA_WIDTH - 1 : 0]  tx_roce_udp_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH - 1 : 0]  tx_roce_udp_payload_axis_tkeep;
    wire                           tx_roce_udp_payload_axis_tvalid;
    wire                           tx_roce_udp_payload_axis_tready;
    wire                           tx_roce_udp_payload_axis_tlast;
    wire                           tx_roce_udp_payload_axis_tuser;

    // Arbiter output (between QPs)
    wire [7:0]  roce_arb_bth_op_code;
    wire [15:0] roce_arb_bth_p_key;
    wire [23:0] roce_arb_bth_psn;
    wire [23:0] roce_arb_bth_dest_qp;
    wire [23:0] roce_arb_bth_src_qp;
    wire        roce_arb_bth_ack_req;

    wire [63:0] roce_arb_reth_v_addr;
    wire [31:0] roce_arb_reth_r_key;
    wire [31:0] roce_arb_reth_length;

    wire [31:0] roce_arb_immdh_data;

    wire [47:0] roce_arb_eth_dest_mac;
    wire [47:0] roce_arb_eth_src_mac;
    wire [15:0] roce_arb_eth_type;
    wire [3:0]  roce_arb_ip_version;
    wire [3:0]  roce_arb_ip_ihl;
    wire [5:0]  roce_arb_ip_dscp;
    wire [1:0]  roce_arb_ip_ecn;
    wire [15:0] roce_arb_ip_identification;
    wire [2:0]  roce_arb_ip_flags;
    wire [12:0] roce_arb_ip_fragment_offset;
    wire [7:0]  roce_arb_ip_ttl;
    wire [7:0]  roce_arb_ip_protocol;
    wire [15:0] roce_arb_ip_header_checksum;
    wire [31:0] roce_arb_ip_source_ip;
    wire [31:0] roce_arb_ip_dest_ip;
    wire [15:0] roce_arb_udp_source_port;
    wire [15:0] roce_arb_udp_dest_port;
    wire [15:0] roce_arb_udp_length;
    wire [15:0] roce_arb_udp_checksum;

    wire [OUT_DATA_WIDTH - 1 : 0] roce_arb_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH - 1 : 0] roce_arb_payload_axis_tkeep;
    wire                          roce_arb_payload_axis_tvalid;
    wire                          roce_arb_payload_axis_tlast;
    wire                          roce_arb_payload_axis_tuser;
    wire                          roce_arb_payload_axis_tready;

    wire        cm_qp_valid;
    wire [2 :0] cm_qp_req_type;
    wire [31:0] cm_qp_dma_transfer_length;
    wire [23:0] cm_qp_rem_qpn;
    wire [23:0] cm_qp_loc_qpn;
    wire [23:0] cm_qp_rem_psn;
    wire [23:0] cm_qp_loc_psn;
    wire [31:0] cm_qp_r_key;
    wire [63:0] cm_qp_rem_addr;
    wire [31:0] cm_qp_rem_ip_addr;
    wire        qp_is_immediate;
    wire        qp_tx_type;

    wire        cm_qp_valid_roce;
    wire [2 :0] cm_qp_req_type_roce;
    wire [31:0] cm_qp_dma_transfer_length_roce;
    wire [23:0] cm_qp_rem_qpn_roce;
    wire [23:0] cm_qp_loc_qpn_roce;
    wire [23:0] cm_qp_rem_psn_roce;
    wire [23:0] cm_qp_loc_psn_roce;
    wire [31:0] cm_qp_r_key_roce;
    wire [63:0] cm_qp_rem_addr_roce;
    wire [31:0] cm_qp_rem_ip_addr_roce;
    wire        qp_is_immediate_roce;
    wire        qp_tx_type_roce;

    wire cm_qp_status_valid;
    wire [1:0] cm_qp_status;

    wire cm_qp_status_valid_roce;
    wire [1:0] cm_qp_status_roce;

    wire        txmeta_valid;
    wire        txmeta_start_transfer;
    wire [23:0] txmeta_loc_qpn;
    wire        txmeta_is_immediate;
    wire        txmeta_tx_type;
    wire [31:0] txmeta_dma_transfer;
    wire [31:0] txmeta_n_transfers;
    wire [31:0] txmeta_frequency;

    // Roce engine clock domain
    wire        txmeta_roce_valid;
    wire        txmeta_roce_start_transfer;
    wire [23:0] txmeta_roce_loc_qpn;
    wire        txmeta_roce_is_immediate;
    wire        txmeta_roce_tx_type;
    wire [31:0] txmeta_roce_dma_transfer;
    wire [31:0] txmeta_roce_n_transfers;
    wire [31:0] txmeta_roce_frequency;

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


    wire latency_inst_valid;

    integer m;

    // redirect udp rx traffic either to CM or RoCE RX

    reg s_select_cm_reg   = 1'b0;
    reg s_select_roce_reg = 1'b0;
    reg s_select_none_reg = 1'b0;

    wire s_select_cm   = s_udp_dest_port == CM_LISTEN_UDP_PORT ? 1'b1 : 1'b0;
    wire s_select_roce = s_udp_dest_port == ROCE_UDP_PORT      ? 1'b1 : 1'b0;
    wire s_select_none = !(s_select_cm || s_select_roce);


    always @(posedge clk_stack) begin
        if (rst_stack) begin
            s_select_cm_reg   <= 1'b0;
            s_select_roce_reg <= 1'b0;
            s_select_none_reg <= 1'b0;
        end else begin
            if (s_udp_payload_axis_tvalid) begin
                if ((!s_select_cm_reg && !s_select_roce_reg && !s_select_none_reg) ||
                (s_udp_payload_axis_tvalid && s_udp_payload_axis_tready && s_udp_payload_axis_tlast)) begin
                    s_select_cm_reg   <= s_select_cm;
                    s_select_roce_reg <= s_select_roce;
                    s_select_none_reg <= s_select_none;
                end
            end else begin
                s_select_cm_reg   <= 1'b0;
                s_select_roce_reg <= 1'b0;
                s_select_none_reg <= 1'b0;
            end
        end
    end

    assign rx_udp_cm_hdr_valid     = s_select_cm && s_udp_hdr_valid;
    assign rx_udp_cm_ip_source_ip  = s_ip_source_ip;
    assign rx_udp_cm_ip_dest_ip    = s_ip_dest_ip;
    assign rx_udp_cm_source_port   = s_udp_source_port;
    assign rx_udp_cm_dest_port     = s_udp_dest_port;
    assign rx_udp_cm_length        = s_udp_length;
    assign rx_udp_cm_checksum      = s_udp_checksum;

    assign rx_udp_cm_payload_axis_tdata = s_udp_payload_axis_tdata;
    assign rx_udp_cm_payload_axis_tkeep = s_udp_payload_axis_tkeep;
    assign rx_udp_cm_payload_axis_tvalid = s_select_cm_reg && s_udp_payload_axis_tvalid;
    assign rx_udp_cm_payload_axis_tlast = s_udp_payload_axis_tlast;
    assign rx_udp_cm_payload_axis_tuser = s_udp_payload_axis_tuser;


    assign rx_udp_RoCE_hdr_valid = s_select_roce && s_udp_hdr_valid;
    assign rx_udp_RoCE_eth_dest_mac = s_eth_dest_mac;
    assign rx_udp_RoCE_eth_src_mac = s_eth_src_mac;
    assign rx_udp_RoCE_eth_type = s_eth_type;
    assign rx_udp_RoCE_ip_version = s_ip_version;
    assign rx_udp_RoCE_ip_ihl = s_ip_ihl;
    assign rx_udp_RoCE_ip_dscp = s_ip_dscp;
    assign rx_udp_RoCE_ip_ecn = s_ip_ecn;
    assign rx_udp_RoCE_ip_length = s_ip_length;
    assign rx_udp_RoCE_ip_identification = s_ip_identification;
    assign rx_udp_RoCE_ip_flags = s_ip_flags;
    assign rx_udp_RoCE_ip_fragment_offset = s_ip_fragment_offset;
    assign rx_udp_RoCE_ip_ttl = s_ip_ttl;
    assign rx_udp_RoCE_ip_protocol = s_ip_protocol;
    assign rx_udp_RoCE_ip_header_checksum = s_ip_header_checksum;
    assign rx_udp_RoCE_ip_source_ip = s_ip_source_ip;
    assign rx_udp_RoCE_ip_dest_ip = s_ip_dest_ip;
    assign rx_udp_RoCE_source_port = s_udp_source_port;
    assign rx_udp_RoCE_dest_port = ROCE_UDP_PORT;
    assign rx_udp_RoCE_length = s_udp_length;
    assign rx_udp_RoCE_checksum = s_udp_checksum;
    assign rx_udp_RoCE_payload_axis_tdata = s_udp_payload_axis_tdata;
    assign rx_udp_RoCE_payload_axis_tkeep = s_udp_payload_axis_tkeep;
    assign rx_udp_RoCE_payload_axis_tvalid = s_select_roce_reg && s_udp_payload_axis_tvalid;
    assign rx_udp_RoCE_payload_axis_tlast = s_udp_payload_axis_tlast;
    assign rx_udp_RoCE_payload_axis_tuser = s_udp_payload_axis_tuser;

    assign s_udp_hdr_ready = (s_select_cm   && rx_udp_cm_hdr_ready  ) ||
    (s_select_roce && rx_udp_RoCE_hdr_ready) ||
    (s_select_none);

    assign s_udp_payload_axis_tready = (s_select_cm_reg && rx_udp_cm_payload_axis_tready)     ||
    (s_select_roce_reg && rx_udp_RoCE_payload_axis_tready) ||
    (s_select_none_reg);

    wire                 rx_roce_acks_bth_valid;
    wire                 rx_roce_acks_bth_ready;
    wire [7:0]           rx_roce_acks_bth_op_code;
    wire [15:0]          rx_roce_acks_bth_p_key;
    wire [23:0]          rx_roce_acks_bth_psn;
    wire [23:0]          rx_roce_acks_bth_dest_qp;
    wire                 rx_roce_acks_bth_ack_req;
    wire                 rx_roce_acks_aeth_valid;
    wire                 rx_roce_acks_aeth_ready;
    wire [7:0]           rx_roce_acks_aeth_syndrome;
    wire [23:0]          rx_roce_acks_aeth_msn;

    wire                 s_rx_roce_acks_fifo_bth_valid;
    wire                 s_rx_roce_acks_fifo_bth_ready;
    wire roce_bth_hdr_t  s_rx_roce_acks_fifo_bth;
    wire                 s_rx_roce_acks_fifo_aeth_valid;
    wire                 s_rx_roce_acks_fifo_aeth_ready;
    wire roce_aeth_hdr_t s_rx_roce_acks_fifo_aeth;


    wire                 rx_roce_acks_fifo_bth_valid;
    wire                 rx_roce_acks_fifo_bth_ready;
    wire [7:0]           rx_roce_acks_fifo_bth_op_code;
    wire [15:0]          rx_roce_acks_fifo_bth_p_key;
    wire [23:0]          rx_roce_acks_fifo_bth_psn;
    wire [23:0]          rx_roce_acks_fifo_bth_dest_qp;
    wire                 rx_roce_acks_fifo_bth_ack_req;
    wire                 rx_roce_acks_fifo_aeth_valid;
    wire                 rx_roce_acks_fifo_aeth_ready;
    wire [7:0]           rx_roce_acks_fifo_aeth_syndrome;
    wire [23:0]          rx_roce_acks_fifo_aeth_msn;

    wire                 m_rx_roce_acks_fifo_bth_valid;
    wire                 m_rx_roce_acks_fifo_bth_ready;
    wire roce_bth_hdr_t  m_rx_roce_acks_fifo_bth;
    wire                 m_rx_roce_acks_fifo_aeth_valid;
    wire                 m_rx_roce_acks_fifo_aeth_ready;
    wire roce_aeth_hdr_t m_rx_roce_acks_fifo_aeth;

    // DATA GEN
    wire         m_wr_req_gen_valid          [N_QUEUE_PAIRS-1:0];
    wire         m_wr_req_gen_ready          [N_QUEUE_PAIRS-1:0];
    wire         m_wr_req_gen_tx_type        [N_QUEUE_PAIRS-1:0]; // 0 WRITE, 1 SEND
    wire         m_wr_req_gen_is_immediate   [N_QUEUE_PAIRS-1:0];
    wire [31:0]  m_wr_req_gen_immediate_data [N_QUEUE_PAIRS-1:0];
    wire [23:0]  m_wr_req_gen_loc_qp         [N_QUEUE_PAIRS-1:0];
    wire [63:0]  m_wr_req_gen_addr_offset    [N_QUEUE_PAIRS-1:0];
    wire [31:0]  m_wr_req_gen_dma_length     [N_QUEUE_PAIRS-1:0]; // for each transfer

    wire [QP_CH_DATA_WIDTH - 1 :0]  m_gen_axis_tdata  [N_QUEUE_PAIRS-1:0];
    wire [QP_CH_KEEP_WIDTH - 1 :0]  m_gen_axis_tkeep  [N_QUEUE_PAIRS-1:0];
    wire                            m_gen_axis_tvalid [N_QUEUE_PAIRS-1:0];
    wire                            m_gen_axis_tready [N_QUEUE_PAIRS-1:0];
    wire                            m_gen_axis_tlast  [N_QUEUE_PAIRS-1:0];
    wire                            m_gen_axis_tuser  [N_QUEUE_PAIRS-1:0];

    // QP state module

    // request arbiter

    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_ready;
    wire [N_QUEUE_PAIRS*24-1:0] qp_local_qpn_arb_req;


    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_ready;
    wire [N_QUEUE_PAIRS*48-1:0] qp_update_context_loc_qpn_rem_psn_arb;

    wire [N_ROCE_TX_ENGINES*48-1:0] qp_update_context_loc_qpn_rem_psn_tx_eng;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_update_context_tx_eng_valid;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_update_context_tx_eng_ready;

    wire          m_qp_update_context_valid;
    wire          m_qp_update_context_ready;
    wire [24-1:0] m_qp_update_context_loc_qpn;
    wire [24-1:0] m_qp_update_context_rem_psn;

    wire [N_ROCE_TX_ENGINES*24-1:0] qp_context_loc_qpn_tx_eng_req;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_context_tx_eng_req_valid;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_context_tx_eng_req_ready;

    wire        m_qp_context_req_valid;
    wire        m_qp_context_req_ready;
    wire [23:0] m_qp_context_loc_qpn_req;

    wire        s_qp_context_req_valid;
    wire [2 :0] s_qp_context_req_state;
    wire [23:0] s_qp_context_req_rem_qpn;
    wire [23:0] s_qp_context_req_loc_qpn;
    wire [23:0] s_qp_context_req_rem_psn;
    wire [23:0] s_qp_context_req_loc_psn;
    wire [31:0] s_qp_context_req_r_key;
    wire [63:0] s_qp_context_req_rem_addr;
    wire [31:0] s_qp_context_req_rem_ip_addr;

    // close parameters, case of too many retransmissions
    wire [N_QUEUE_PAIRS-1:0]     qp_close_arb_valid;
    wire [N_QUEUE_PAIRS-1:0]     qp_close_arb_ready;
    wire [N_QUEUE_PAIRS*48-1:0]  qp_close_loc_qpn_rem_psn_arb;

    wire [N_ROCE_TX_ENGINES*48-1:0] qp_close_loc_qpn_rem_psn_tx_eng;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_close_tx_eng_valid;
    wire [N_ROCE_TX_ENGINES-1:0]    qp_close_tx_eng_ready;


    wire          m_qp_close_valid;
    wire          m_qp_close_ready;
    wire [24-1:0] m_qp_close_loc_qpn;
    wire [24-1:0] m_qp_close_rem_psn;

    wire [N_QUEUE_PAIRS-1:0]     stall_qp;

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


    // Fifo_async output 
    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_bth_valid;
    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_bth_ready;
    wire [N_ROCE_TX_ENGINES*8 -1:0] m_roce_retrans_fifo_bth_op_code;
    wire [N_ROCE_TX_ENGINES*16-1:0] m_roce_retrans_fifo_bth_p_key;
    wire [N_ROCE_TX_ENGINES*24-1:0] m_roce_retrans_fifo_bth_psn;
    wire [N_ROCE_TX_ENGINES*24-1:0] m_roce_retrans_fifo_bth_dest_qp;
    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_bth_ack_req;
    wire [N_ROCE_TX_ENGINES*24-1:0] m_roce_retrans_fifo_bth_src_qp;

    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_reth_valid;
    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_reth_ready;
    wire [N_ROCE_TX_ENGINES*64-1:0] m_roce_retrans_fifo_reth_v_addr;
    wire [N_ROCE_TX_ENGINES*32-1:0] m_roce_retrans_fifo_reth_r_key;
    wire [N_ROCE_TX_ENGINES*32-1:0] m_roce_retrans_fifo_reth_length;

    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_immdh_valid;
    wire [N_ROCE_TX_ENGINES   -1:0] m_roce_retrans_fifo_immdh_ready;
    wire [N_ROCE_TX_ENGINES*32-1:0] m_roce_retrans_fifo_immdh_data;

    wire [N_ROCE_TX_ENGINES*16-1:0] m_roce_retrans_fifo_udp_src_port;
    wire [N_ROCE_TX_ENGINES*16-1:0] m_roce_retrans_fifo_udp_dest_port;
    wire [N_ROCE_TX_ENGINES*16-1:0] m_roce_retrans_fifo_udp_length;
    wire [N_ROCE_TX_ENGINES*16-1:0] m_roce_retrans_fifo_udp_checksum;


    wire [N_ROCE_TX_ENGINES*32-1:0] m_roce_retrans_fifo_ip_dest_ip;

    wire [N_ROCE_TX_ENGINES*OUT_DATA_WIDTH-1:0]  m_roce_retrans_fifo_payload_axis_tdata ;
    wire [N_ROCE_TX_ENGINES*OUT_KEEP_WIDTH-1:0]  m_roce_retrans_fifo_payload_axis_tkeep ;
    wire [N_ROCE_TX_ENGINES               -1:0]  m_roce_retrans_fifo_payload_axis_tvalid;
    wire [N_ROCE_TX_ENGINES               -1:0]  m_roce_retrans_fifo_payload_axis_tready;
    wire [N_ROCE_TX_ENGINES               -1:0]  m_roce_retrans_fifo_payload_axis_tlast ;
    wire [N_ROCE_TX_ENGINES               -1:0]  m_roce_retrans_fifo_payload_axis_tuser ;

    // Final RoCE arbiter output 
    wire          m_roce_final_arb_bth_valid;
    wire          m_roce_final_arb_bth_ready;
    wire [8 -1:0] m_roce_final_arb_bth_op_code;
    wire [16-1:0] m_roce_final_arb_bth_p_key;
    wire [24-1:0] m_roce_final_arb_bth_psn;
    wire [24-1:0] m_roce_final_arb_bth_dest_qp;
    wire          m_roce_final_arb_bth_ack_req;
    wire [24-1:0] m_roce_final_arb_bth_src_qp;

    wire          m_roce_final_arb_reth_valid;
    wire          m_roce_final_arb_reth_ready;
    wire [64-1:0] m_roce_final_arb_reth_v_addr;
    wire [32-1:0] m_roce_final_arb_reth_r_key;
    wire [32-1:0] m_roce_final_arb_reth_length;

    wire          m_roce_final_arb_immdh_valid;
    wire          m_roce_final_arb_immdh_ready;
    wire [32-1:0] m_roce_final_arb_immdh_data;

    wire [16-1:0] m_roce_final_arb_udp_src_port;
    wire [16-1:0] m_roce_final_arb_udp_dest_port;
    wire [16-1:0] m_roce_final_arb_udp_length;
    wire [16-1:0] m_roce_final_arb_udp_checksum;


    wire [32-1:0] m_roce_final_arb_ip_dest_ip;

    // final arb axis
    wire [OUT_DATA_WIDTH-1:0]  m_roce_final_arb_payload_axis_tdata ;
    wire [OUT_KEEP_WIDTH-1:0]  m_roce_final_arb_payload_axis_tkeep ;
    wire                       m_roce_final_arb_payload_axis_tvalid;
    wire                       m_roce_final_arb_payload_axis_tready;
    wire                       m_roce_final_arb_payload_axis_tlast ;
    wire                       m_roce_final_arb_payload_axis_tuser ;


    /*
    AXI INTERCONNECT OUT INTERFACE
    */
    wire [N_AXI_RAM-1                :0]                    m_axi_interconnect_awid;
    wire [N_AXI_RAM*INTERCONNECT_ADDR_WIDTH-1:0]            m_axi_interconnect_awaddr;
    wire [N_AXI_RAM*8-1:0]                                  m_axi_interconnect_awlen;
    wire [N_AXI_RAM*3-1:0]                                  m_axi_interconnect_awsize;
    wire [N_AXI_RAM*2-1:0]                                  m_axi_interconnect_awburst;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_awlock;
    wire [N_AXI_RAM*4-1:0]                                  m_axi_interconnect_awcache;
    wire [N_AXI_RAM*3-1:0]                                  m_axi_interconnect_awprot;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_awvalid;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_awready;
    wire [N_AXI_RAM*OUT_DATA_WIDTH - 1 : 0]                 m_axi_interconnect_wdata;
    wire [N_AXI_RAM*OUT_KEEP_WIDTH - 1 : 0]                 m_axi_interconnect_wstrb;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_wlast;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_wvalid;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_wready;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_bid;
    wire [N_AXI_RAM*2-1:0]                                  m_axi_interconnect_bresp;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_bvalid;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_bready;
    wire [N_AXI_RAM-1              :0]                      m_axi_interconnect_arid;
    wire [N_AXI_RAM*INTERCONNECT_ADDR_WIDTH-1:0]            m_axi_interconnect_araddr;
    wire [N_AXI_RAM*8-1:0]                                  m_axi_interconnect_arlen;
    wire [N_AXI_RAM*3-1:0]                                  m_axi_interconnect_arsize;
    wire [N_AXI_RAM*2-1:0]                                  m_axi_interconnect_arburst;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_arlock;
    wire [N_AXI_RAM*4-1:0]                                  m_axi_interconnect_arcache;
    wire [N_AXI_RAM*3-1:0]                                  m_axi_interconnect_arprot;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_arvalid;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_arready;
    wire [N_AXI_RAM-1            :0]                        m_axi_interconnect_rid;
    wire [N_AXI_RAM*OUT_DATA_WIDTH   - 1 : 0]               m_axi_interconnect_rdata;
    wire [N_AXI_RAM*2-1:0]                                  m_axi_interconnect_rresp;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_rlast;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_rvalid;
    wire [N_AXI_RAM-1             :0]                       m_axi_interconnect_rready;

    //RX acks fifo cdc clk_stack --> clk_roce_eng (faster to slower)
    assign s_rx_roce_acks_fifo_bth_valid       = rx_roce_acks_bth_valid;
    assign s_rx_roce_acks_fifo_bth.op_code     = rx_roce_acks_bth_op_code;
    assign s_rx_roce_acks_fifo_bth.p_key       = rx_roce_acks_bth_p_key;
    assign s_rx_roce_acks_fifo_bth.psn         = rx_roce_acks_bth_psn;
    assign s_rx_roce_acks_fifo_bth.qp_number   = rx_roce_acks_bth_dest_qp;
    assign s_rx_roce_acks_fifo_bth.ack_request = rx_roce_acks_bth_ack_req;

    assign rx_roce_acks_bth_ready = s_rx_roce_acks_fifo_bth_ready;

    assign s_rx_roce_acks_fifo_aeth_valid    = rx_roce_acks_bth_valid;
    assign s_rx_roce_acks_fifo_aeth.msn      = rx_roce_acks_aeth_msn;
    assign s_rx_roce_acks_fifo_aeth.syndrome = rx_roce_acks_aeth_syndrome;

    assign rx_roce_acks_aeth_ready = s_rx_roce_acks_fifo_bth_ready;

    wire        wr_error_qp_not_rts [N_QUEUE_PAIRS-1:0];
    wire [23:0] wr_error_loc_qpn [N_QUEUE_PAIRS-1:0];



    // clock stack domain (faster one)


    // Connection manager
    udp_RoCE_connection_manager #(
        .DATA_WIDTH      (OUT_DATA_WIDTH),
        .N_QUEUE_PAIRS   (N_QUEUE_PAIRS),
        .MODULE_DIRECTION("Slave"),
        .MASTER_TIMEOUT  (1*10**8)
    ) udp_RoCE_connection_manager_instance (
        .clk(clk_stack),
        .rst(rst_stack),

        .s_udp_hdr_valid          (rx_udp_cm_hdr_valid),
        .s_udp_hdr_ready          (rx_udp_cm_hdr_ready),
        .s_ip_source_ip           (rx_udp_cm_ip_source_ip),
        .s_ip_dest_ip             (rx_udp_cm_ip_dest_ip),
        .s_udp_source_port        (rx_udp_cm_source_port),
        .s_udp_dest_port          (rx_udp_cm_dest_port),
        .s_udp_length             (rx_udp_cm_length),
        .s_udp_checksum           (rx_udp_cm_checksum),
        .s_udp_payload_axis_tdata (rx_udp_cm_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (rx_udp_cm_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(rx_udp_cm_payload_axis_tvalid),
        .s_udp_payload_axis_tready(rx_udp_cm_payload_axis_tready),
        .s_udp_payload_axis_tlast (rx_udp_cm_payload_axis_tlast),
        .s_udp_payload_axis_tuser (rx_udp_cm_payload_axis_tuser),

        .m_udp_hdr_valid          (tx_udp_cm_hdr_valid),
        .m_udp_hdr_ready          (tx_udp_cm_hdr_ready),
        .m_ip_source_ip           (tx_udp_cm_ip_source_ip),
        .m_ip_dest_ip             (tx_udp_cm_ip_dest_ip),
        .m_udp_source_port        (tx_udp_cm_source_port),
        .m_udp_dest_port          (tx_udp_cm_dest_port),
        .m_udp_length             (tx_udp_cm_length),
        .m_udp_checksum           (tx_udp_cm_checksum),
        .m_udp_payload_axis_tdata (tx_udp_cm_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (tx_udp_cm_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(tx_udp_cm_payload_axis_tvalid),
        .m_udp_payload_axis_tready(tx_udp_cm_payload_axis_tready),
        .m_udp_payload_axis_tlast (tx_udp_cm_payload_axis_tlast),
        .m_udp_payload_axis_tuser (tx_udp_cm_payload_axis_tuser),

        .cm_qp_valid        (cm_qp_valid),
        .cm_qp_req_type     (cm_qp_req_type),
        .cm_qp_r_key        (cm_qp_r_key),
        .cm_qp_rem_qpn      (cm_qp_rem_qpn),
        .cm_qp_loc_qpn      (cm_qp_loc_qpn),
        .cm_qp_rem_psn      (cm_qp_rem_psn),
        .cm_qp_loc_psn      (cm_qp_loc_psn),
        .cm_qp_rem_base_addr(cm_qp_rem_addr),
        .cm_qp_rem_ip_addr  (cm_qp_rem_ip_addr),

        .cm_qp_status_valid (cm_qp_status_valid),
        .cm_qp_status       (cm_qp_status),

        .m_metadata_valid     (txmeta_valid),
        .m_start_transfer     (txmeta_start_transfer),
        .m_txmeta_loc_qpn     (txmeta_loc_qpn),
        .m_txmeta_is_immediate(txmeta_is_immediate),
        .m_txmeta_tx_type     (txmeta_tx_type),
        .m_txmeta_dma_transfer(txmeta_dma_transfer),
        .m_txmeta_n_transfers (txmeta_n_transfers),
        .m_txmeta_frequency   (txmeta_frequency),

        .cfg_udp_source_port(16'h8765),
        .cfg_loc_ip_addr    (loc_ip_addr)
    );




    // RX path

    RoCE_udp_rx_acks #(
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .ENABLE_ICRC_CHECK(1'b0)
    ) RoCE_udp_rx_instance (
        .clk                           (clk_stack),
        .rst                           (rst_stack),
        .s_udp_hdr_valid               (rx_udp_RoCE_hdr_valid),
        .s_udp_hdr_ready               (rx_udp_RoCE_hdr_ready),
        .s_eth_dest_mac                (rx_udp_RoCE_eth_dest_mac),
        .s_eth_src_mac                 (0),
        .s_eth_type                    (0),
        .s_ip_version                  (0),
        .s_ip_ihl                      (0),
        .s_ip_dscp                     (0),
        .s_ip_ecn                      (0),
        .s_ip_length                   (0),
        .s_ip_identification           (0),
        .s_ip_flags                    (0),
        .s_ip_fragment_offset          (0),
        .s_ip_ttl                      (0),
        .s_ip_protocol                 (0),
        .s_ip_header_checksum          (0),
        .s_ip_source_ip                (0),
        .s_ip_dest_ip                  (0),
        .s_udp_source_port             (rx_udp_RoCE_source_port),
        .s_udp_dest_port               (rx_udp_RoCE_dest_port),
        .s_udp_length                  (rx_udp_RoCE_length),
        .s_udp_checksum                (rx_udp_RoCE_checksum),
        .s_roce_computed_icrc          (32'hDEADBEEF),
        .s_udp_payload_axis_tdata      (rx_udp_RoCE_payload_axis_tdata),
        .s_udp_payload_axis_tkeep      (rx_udp_RoCE_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid     (rx_udp_RoCE_payload_axis_tvalid),
        .s_udp_payload_axis_tready     (rx_udp_RoCE_payload_axis_tready),
        .s_udp_payload_axis_tlast      (rx_udp_RoCE_payload_axis_tlast),
        .s_udp_payload_axis_tuser      (rx_udp_RoCE_payload_axis_tuser),

        .m_roce_bth_valid              (rx_roce_acks_bth_valid),
        .m_roce_bth_ready              (rx_roce_acks_bth_ready),
        .m_roce_bth_op_code            (rx_roce_acks_bth_op_code),
        .m_roce_bth_p_key              (rx_roce_acks_bth_p_key),
        .m_roce_bth_psn                (rx_roce_acks_bth_psn),
        .m_roce_bth_dest_qp            (rx_roce_acks_bth_dest_qp),
        .m_roce_bth_ack_req            (rx_roce_acks_bth_ack_req),
        .m_roce_aeth_valid             (rx_roce_acks_aeth_valid),
        .m_roce_aeth_ready             (rx_roce_acks_aeth_ready),
        .m_roce_aeth_syndrome          (rx_roce_acks_aeth_syndrome),
        .m_roce_aeth_msn               (rx_roce_acks_aeth_msn),
        .m_eth_dest_mac                (),
        .m_eth_src_mac                 (),
        .m_eth_type                    (),
        .m_ip_version                  (),
        .m_ip_ihl                      (),
        .m_ip_dscp                     (),
        .m_ip_ecn                      (),
        .m_ip_identification           (),
        .m_ip_flags                    (),
        .m_ip_fragment_offset          (),
        .m_ip_ttl                      (),
        .m_ip_protocol                 (),
        .m_ip_header_checksum          (),
        .m_ip_source_ip                (),
        .m_ip_dest_ip                  (),
        .m_udp_source_port             (),
        .m_udp_dest_port               (),
        .m_udp_length                  (),
        .m_udp_checksum                (),
        .busy                          (),
        .error_header_early_termination()
    );


    RoCE_udp_tx #(
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .MIG_REQ(1'b1),
        .FECN   (1'b0)
    ) RoCE_udp_tx_instance (
        .clk                            (clk_stack),
        .rst                            (rst_stack),
        .s_roce_bth_valid               (m_roce_final_arb_bth_valid),
        .s_roce_bth_ready               (m_roce_final_arb_bth_ready),
        .s_roce_bth_op_code             (m_roce_final_arb_bth_op_code),
        .s_roce_bth_p_key               (m_roce_final_arb_bth_p_key),
        .s_roce_bth_psn                 (m_roce_final_arb_bth_psn),
        .s_roce_bth_dest_qp             (m_roce_final_arb_bth_dest_qp),
        .s_roce_bth_ack_req             (m_roce_final_arb_bth_ack_req),
        .s_roce_reth_valid              (m_roce_final_arb_reth_valid),
        .s_roce_reth_ready              (m_roce_final_arb_reth_ready),
        .s_roce_reth_v_addr             (m_roce_final_arb_reth_v_addr),
        .s_roce_reth_r_key              (m_roce_final_arb_reth_r_key),
        .s_roce_reth_length             (m_roce_final_arb_reth_length),
        .s_roce_immdh_valid             (m_roce_final_arb_immdh_valid),
        .s_roce_immdh_ready             (m_roce_final_arb_immdh_ready),
        .s_roce_immdh_data              (m_roce_final_arb_immdh_data),
        .s_eth_dest_mac                 (48'd0),
        .s_eth_src_mac                  (48'd0),
        .s_eth_type                     (16'd0),
        .s_ip_version                   (4'd4),
        .s_ip_ihl                       (4'd0),
        .s_ip_dscp                      (6'd0),
        .s_ip_ecn                       (2'd0),
        .s_ip_identification            (16'd0),
        .s_ip_flags                     (3'b001),
        .s_ip_fragment_offset           (13'd0),
        .s_ip_ttl                       (8'h40),
        .s_ip_protocol                  (8'h11),
        .s_ip_header_checksum           (16'd0),
        .s_ip_source_ip                 (loc_ip_addr),
        .s_ip_dest_ip                   (m_roce_final_arb_ip_dest_ip),
        .s_udp_source_port              (16'h8657),
        .s_udp_dest_port                (ROCE_UDP_PORT),
        .s_udp_length                   (m_roce_final_arb_udp_length),
        .s_udp_checksum                 (16'd0),
        .s_roce_payload_axis_tdata      (m_roce_final_arb_payload_axis_tdata ),
        .s_roce_payload_axis_tkeep      (m_roce_final_arb_payload_axis_tkeep ),
        .s_roce_payload_axis_tvalid     (m_roce_final_arb_payload_axis_tvalid),
        .s_roce_payload_axis_tready     (m_roce_final_arb_payload_axis_tready),
        .s_roce_payload_axis_tlast      (m_roce_final_arb_payload_axis_tlast ),
        .s_roce_payload_axis_tuser      (m_roce_final_arb_payload_axis_tuser ),

        .m_udp_hdr_valid                (tx_roce_udp_hdr_valid),
        .m_udp_hdr_ready                (tx_roce_udp_hdr_ready),
        .m_eth_dest_mac                 (tx_roce_eth_dest_mac),
        .m_eth_src_mac                  (tx_roce_eth_src_mac),
        .m_eth_type                     (tx_roce_eth_type),
        .m_ip_version                   (tx_roce_ip_version),
        .m_ip_ihl                       (tx_roce_ip_ihl),
        .m_ip_dscp                      (tx_roce_ip_dscp),
        .m_ip_ecn                       (tx_roce_ip_ecn),
        .m_ip_length                    (tx_roce_ip_length),
        .m_ip_identification            (tx_roce_ip_identification),
        .m_ip_flags                     (tx_roce_ip_flags),
        .m_ip_fragment_offset           (tx_roce_ip_fragment_offset),
        .m_ip_ttl                       (tx_roce_ip_ttl),
        .m_ip_protocol                  (tx_roce_ip_protocol),
        .m_ip_header_checksum           (tx_roce_ip_header_checksum),
        .m_ip_source_ip                 (tx_roce_ip_source_ip),
        .m_ip_dest_ip                   (tx_roce_ip_dest_ip),
        .m_udp_source_port              (tx_roce_udp_source_port),
        .m_udp_dest_port                (tx_roce_udp_dest_port),
        .m_udp_length                   (tx_roce_udp_length),
        .m_udp_checksum                 (tx_roce_udp_checksum),
        .m_udp_payload_axis_tdata       (tx_roce_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep       (tx_roce_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid      (tx_roce_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready      (tx_roce_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast       (tx_roce_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser       (tx_roce_udp_payload_axis_tuser),

        .busy                           (),
        .error_payload_early_termination(),
        .RoCE_udp_port(ROCE_UDP_PORT)
    );

    wire udp_tx_select;
    reg udp_tx_select_reg, udp_tx_select_next;

    always @* begin
        udp_tx_select_next = udp_tx_select_reg;
        if (tx_udp_cm_hdr_valid && !udp_tx_select_reg) begin
            udp_tx_select_next = 1'b1;
        end else if (udp_tx_select_reg & tx_udp_cm_hdr_ready) begin
            udp_tx_select_next = 1'b0;
        end
    end

    always @(posedge clk_stack) begin
        if (rst_stack) begin
            udp_tx_select_reg <= 1'b0;
        end else begin
            udp_tx_select_reg <= udp_tx_select_next;
        end
    end

    assign udp_tx_select = udp_tx_select_reg;

    udp_mux #(
        .S_COUNT(2),
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) udp_arb_mux_instance (
        .clk(clk_stack),
        .rst(rst_stack),
        .s_udp_hdr_valid          ({tx_udp_cm_hdr_valid,           tx_roce_udp_hdr_valid}),
        .s_udp_hdr_ready          ({tx_udp_cm_hdr_ready,           tx_roce_udp_hdr_ready}),
        .s_eth_dest_mac           ({48'd0,                         48'd0}),
        .s_eth_src_mac            ({48'd0,                         48'd0}),
        .s_eth_type               ({16'd0,                         16'd0}),
        .s_ip_version             ({4'd4,                          4'd4}),
        .s_ip_ihl                 ({4'd0,                          4'd0}),
        .s_ip_dscp                ({6'd0,                          tx_roce_ip_dscp}),
        .s_ip_ecn                 ({2'd0,                          tx_roce_ip_ecn}),
        .s_ip_identification      ({16'd0,                         16'd0}),
        .s_ip_flags               ({3'b001,                        tx_roce_ip_flags}),
        .s_ip_fragment_offset     ({13'd0,                         13'd0}),
        .s_ip_ttl                 ({8'h40,                         tx_roce_ip_ttl}),
        .s_ip_protocol            ({8'h11,                         tx_roce_ip_protocol}),
        .s_ip_header_checksum     ({16'd0,                         16'd0}),
        .s_ip_source_ip           ({loc_ip_addr,                   loc_ip_addr}),
        .s_ip_dest_ip             ({tx_udp_cm_ip_dest_ip,          tx_roce_ip_dest_ip}),
        .s_udp_source_port        ({tx_udp_cm_source_port,         tx_roce_udp_source_port}),
        .s_udp_dest_port          ({tx_udp_cm_dest_port,           tx_roce_udp_dest_port}),
        .s_udp_length             ({tx_udp_cm_length,              tx_roce_udp_length}),
        .s_udp_checksum           ({tx_udp_cm_checksum,            tx_roce_udp_checksum}),
        .s_udp_payload_axis_tdata ({tx_udp_cm_payload_axis_tdata,  tx_roce_udp_payload_axis_tdata}),
        .s_udp_payload_axis_tkeep ({tx_udp_cm_payload_axis_tkeep,  tx_roce_udp_payload_axis_tkeep}),
        .s_udp_payload_axis_tvalid({tx_udp_cm_payload_axis_tvalid, tx_roce_udp_payload_axis_tvalid}),
        .s_udp_payload_axis_tready({tx_udp_cm_payload_axis_tready, tx_roce_udp_payload_axis_tready}),
        .s_udp_payload_axis_tlast ({tx_udp_cm_payload_axis_tlast,  tx_roce_udp_payload_axis_tlast}),
        .s_udp_payload_axis_tuser ({tx_udp_cm_payload_axis_tuser,  tx_roce_udp_payload_axis_tuser}),
        .s_udp_payload_axis_tid   ({0,                             0}),
        .s_udp_payload_axis_tdest ({0,                             0}),


        .m_udp_hdr_valid          (m_udp_hdr_valid),
        .m_udp_hdr_ready          (m_udp_hdr_ready),
        .m_eth_dest_mac           (m_eth_dest_mac),
        .m_eth_src_mac            (m_eth_src_mac),
        .m_eth_type               (m_eth_type),
        .m_ip_version             (m_ip_version),
        .m_ip_ihl                 (m_ip_ihl),
        .m_ip_dscp                (m_ip_dscp),
        .m_ip_ecn                 (m_ip_ecn),
        .m_ip_length              (m_ip_length),
        .m_ip_identification      (m_ip_identification),
        .m_ip_flags               (m_ip_flags),
        .m_ip_fragment_offset     (m_ip_fragment_offset),
        .m_ip_ttl                 (m_ip_ttl),
        .m_ip_protocol            (m_ip_protocol),
        .m_ip_header_checksum     (m_ip_header_checksum),
        .m_ip_source_ip           (m_ip_source_ip),
        .m_ip_dest_ip             (m_ip_dest_ip),
        .m_udp_source_port        (m_udp_source_port),
        .m_udp_dest_port          (m_udp_dest_port),
        .m_udp_length             (m_udp_length),
        .m_udp_checksum           (m_udp_checksum),
        .m_udp_payload_axis_tdata (m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast (m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser (m_udp_payload_axis_tuser),
        .m_udp_payload_axis_tid   (),
        .m_udp_payload_axis_tdest (),

        .enable(1),
        .select(udp_tx_select)
    );

    /*
    +-------------------------------------+
    |      RoCE engine clock domain       |
    +-------------------------------------+
    */


    wire [2:0 ] pmtu_cdc;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(3)
    ) sync_pmtu_instance (
        .src_clk(clk_stack),
        //.src_rst(rst_stack),
        .dest_clk(clk_roce_eng),
        .src_in(pmtu),
        .dest_out(pmtu_cdc)
    );

    /*
     * LOC QPN status
     */

    wire [23:0] monitor_loc_qpn_cdc;

    wire [3:0]  cfg_latency_avg_po2_cdc;
    wire [4:0]  cfg_throughput_avg_po2_cdc;

    wire [23:0]  psn_diff_cdc;
    wire [31:0]  n_retransmit_triggers_cdc;
    wire [31:0]  n_rnr_retransmit_triggers_cdc;

    wire [31:0] transfer_time_avg_cdc;
    wire [31:0] transfer_time_moving_avg_cdc;
    wire [31:0] transfer_time_inst_cdc;
    wire [31:0] latency_avg_cdc;
    wire [31:0] latency_moving_avg_cdc;
    wire [31:0] latency_inst_cdc;



    wire [23:0]  psn_diff_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0]  n_retransmit_triggers_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0]  n_rnr_retransmit_triggers_tx_eng [N_ROCE_TX_ENGINES-1:0];

    wire [31:0] transfer_time_avg_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0] transfer_time_moving_avg_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0] transfer_time_inst_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0] latency_avg_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0] latency_moving_avg_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [31:0] latency_inst_tx_eng [N_ROCE_TX_ENGINES-1:0];
    wire [N_ROCE_TX_ENGINES-1:0] latency_inst_valid_tx_eng ;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(24)
    ) sync_monitor_loc_qpn_instance (
        .src_clk(clk_stack),
        //.src_rst(rst_stack),
        .dest_clk(clk_roce_eng),
        .src_in(monitor_loc_qpn),
        .dest_out(monitor_loc_qpn_cdc)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(4)
    ) sync_cfg_latency_avg_po2_instance (
        .src_clk(clk_stack),
        //.src_rst(rst_stack),
        .dest_clk(clk_roce_eng),
        .src_in(cfg_latency_avg_po2),
        .dest_out(cfg_latency_avg_po2_cdc)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(5)
    ) sync_cfg_throughput_avg_po2_instance (
        .src_clk(clk_stack),
        //.src_rst(rst_stack),
        .dest_clk(clk_roce_eng),
        .src_in(cfg_throughput_avg_po2),
        .dest_out(cfg_throughput_avg_po2_cdc)
    );

    /*
    sync_bit_array #(
        .N(3),
        .BUS_WIDTH(24)
    ) sync_psn_diff_instance (
        .src_clk(clk_roce_eng),
        .src_rst(rst_roce_eng),
        .dest_clk(clk_stack),
        .data_in(psn_diff_cdc),
        .data_out(psn_diff)
    );
    */

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(24)
    )
    sync_psn_diff_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in(psn_diff_cdc),
        .dest_out(psn_diff)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(64)
    )
    sync_transfer_time_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in({transfer_time_avg_cdc, transfer_time_moving_avg_cdc}),
        .dest_out({transfer_time_avg, transfer_time_moving_avg})
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(64)
    )
    sync_latency_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in({latency_avg_cdc, latency_moving_avg_cdc}),
        .dest_out({latency_avg, latency_moving_avg})
    );

    /* 
    sync_bit_array #(
        .N(3),
        .BUS_WIDTH(32)
    ) sync_n_retransmit_triggers_instance (
        .src_clk(clk_roce_eng),
        .src_rst(rst_roce_eng),
        .dest_clk(clk_stack),
        .data_in(n_retransmit_triggers_cdc),
        .data_out(n_retransmit_triggers)
    );
    */
    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(32)
    )
    sync_n_retransmit_triggers_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in(n_retransmit_triggers_cdc),
        .dest_out(n_retransmit_triggers)
    );

    /* 
    sync_bit_array #(
        .N(3),
        .BUS_WIDTH(32)
    ) sync_n_rnr_retransmit_triggers_instance (
        .src_clk(clk_roce_eng),
        .src_rst(rst_roce_eng),
        .dest_clk(clk_stack),
        .data_in(n_rnr_retransmit_triggers_cdc),
        .data_out(n_rnr_retransmit_triggers)
    );
    */

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(32)
    )
    sync_n_rnr_retransmit_triggers_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in(n_rnr_retransmit_triggers_cdc),
        .dest_out(n_rnr_retransmit_triggers)
    );

    wire        m_qp_context_spy_cdc;
    wire [23:0] m_qp_local_qpn_spy_cdc;
    wire        s_qp_spy_context_valid_cdc;
    wire [2 :0] s_qp_spy_state_cdc;
    wire [23:0] s_qp_spy_rem_qpn_cdc;
    wire [23:0] s_qp_spy_loc_qpn_cdc;
    wire [23:0] s_qp_spy_rem_psn_cdc;
    wire [23:0] s_qp_spy_rem_acked_psn_cdc;
    wire [23:0] s_qp_spy_loc_psn_cdc;
    wire [31:0] s_qp_spy_r_key_cdc;
    wire [63:0] s_qp_spy_rem_addr_cdc;
    wire [31:0] s_qp_spy_rem_ip_addr_cdc;
    wire [7:0]  s_qp_spy_syndrome_cdc;

    /* 
    sync_bit_array #(
        .N(3),
        .BUS_WIDTH(25)
    ) sync_qp_spy_req_instance (
        .src_clk(clk_stack),
        .src_rst(rst_stack),
        .dest_clk(clk_roce_eng),
        .data_in({m_qp_context_spy, m_qp_local_qpn_spy}),
        .data_out({m_qp_context_spy_cdc, m_qp_local_qpn_spy_cdc})
    );
    */

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(1+24)
    )
    sync_qp_spy_req_instance (
        .src_clk(clk_stack),
        .dest_clk(clk_roce_eng),
        .src_in({m_qp_context_spy, m_qp_local_qpn_spy}),
        .dest_out({m_qp_context_spy_cdc, m_qp_local_qpn_spy_cdc})
    );

    /* 
    sync_bit_array #(
        .N(3),
        .BUS_WIDTH(1+3+24+24+24+24+24+32+64+32+8)
    ) sync_qp_spy_reply_instance (
        .src_clk(clk_roce_eng),
        .src_rst(rst_roce_eng),
        .dest_clk(clk_stack),
        .data_in({s_qp_spy_context_valid_cdc, s_qp_spy_state_cdc,s_qp_spy_rem_qpn_cdc,s_qp_spy_loc_qpn_cdc,s_qp_spy_rem_psn_cdc,s_qp_spy_rem_acked_psn_cdc,s_qp_spy_loc_psn_cdc,s_qp_spy_r_key_cdc,s_qp_spy_rem_addr_cdc,s_qp_spy_rem_ip_addr_cdc,s_qp_spy_syndrome_cdc}),
        .data_out({s_qp_spy_context_valid, s_qp_spy_state,s_qp_spy_rem_qpn,s_qp_spy_loc_qpn,s_qp_spy_rem_psn,s_qp_spy_rem_acked_psn,s_qp_spy_loc_psn,s_qp_spy_r_key,s_qp_spy_rem_addr,s_qp_spy_rem_ip_addr,s_qp_spy_syndrome})
    );
    */

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(1),
        .WIDTH(1+3+24+24+24+24+24+32+64+32+8)
    )
    sync_qp_spy_reply_instance (
        .src_clk(clk_roce_eng),
        .dest_clk(clk_stack),
        .src_in({s_qp_spy_context_valid_cdc, s_qp_spy_state_cdc,s_qp_spy_rem_qpn_cdc,s_qp_spy_loc_qpn_cdc,s_qp_spy_rem_psn_cdc,s_qp_spy_rem_acked_psn_cdc,s_qp_spy_loc_psn_cdc,s_qp_spy_r_key_cdc,s_qp_spy_rem_addr_cdc,s_qp_spy_rem_ip_addr_cdc,s_qp_spy_syndrome_cdc}),
        .dest_out({s_qp_spy_context_valid, s_qp_spy_state,s_qp_spy_rem_qpn,s_qp_spy_loc_qpn,s_qp_spy_rem_psn,s_qp_spy_rem_acked_psn,s_qp_spy_loc_psn,s_qp_spy_r_key,s_qp_spy_rem_addr,s_qp_spy_rem_ip_addr,s_qp_spy_syndrome})
    );


    axis_async_fifo #(
        .DEPTH(4),
        .DATA_WIDTH((12+4)*8), // BTH+AETH
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0),
        .RAM_PIPELINE(2)
    ) rx_roce_acks_axis_async_fifo (
        .s_clk(clk_stack),
        .s_rst(rst_stack),


        .s_axis_tdata ({s_rx_roce_acks_fifo_bth, s_rx_roce_acks_fifo_aeth}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(s_rx_roce_acks_fifo_bth_valid),
        .s_axis_tready(s_rx_roce_acks_fifo_bth_ready),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_roce_eng),
        .m_rst(rst_roce_eng),

        // AXI output
        .m_axis_tdata ({m_rx_roce_acks_fifo_bth, m_rx_roce_acks_fifo_aeth}),
        .m_axis_tkeep (),
        .m_axis_tvalid(m_rx_roce_acks_fifo_bth_valid),
        .m_axis_tready(m_rx_roce_acks_fifo_bth_ready),
        .m_axis_tlast (),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ()
    );


    axis_async_fifo #(
        .DEPTH(4),
        .DATA_WIDTH(24+1+1+32+32+32+1),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0),
        .RAM_PIPELINE(1)
    ) txmeta_async_fifo (
        .s_clk(clk_stack),
        .s_rst(rst_stack),


        .s_axis_tdata ({txmeta_loc_qpn, txmeta_is_immediate, txmeta_tx_type, txmeta_dma_transfer, txmeta_n_transfers, txmeta_frequency, txmeta_start_transfer}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(txmeta_valid),
        .s_axis_tready(),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_roce_eng),
        .m_rst(rst_roce_eng),

        // AXI output
        .m_axis_tdata ({txmeta_roce_loc_qpn, txmeta_roce_is_immediate, txmeta_roce_tx_type, txmeta_roce_dma_transfer, txmeta_roce_n_transfers, txmeta_roce_frequency, txmeta_roce_start_transfer}),
        .m_axis_tkeep (),
        .m_axis_tvalid(txmeta_roce_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast (),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ()
    );


    assign m_rx_roce_acks_fifo_bth_ready      = rx_roce_acks_fifo_bth_ready;


    assign rx_roce_acks_fifo_bth_valid     = m_rx_roce_acks_fifo_bth_valid      ;
    assign rx_roce_acks_fifo_bth_op_code   = m_rx_roce_acks_fifo_bth.op_code    ;
    assign rx_roce_acks_fifo_bth_p_key     = m_rx_roce_acks_fifo_bth.p_key      ;
    assign rx_roce_acks_fifo_bth_psn       = m_rx_roce_acks_fifo_bth.psn        ;
    assign rx_roce_acks_fifo_bth_dest_qp   = m_rx_roce_acks_fifo_bth.qp_number  ;
    assign rx_roce_acks_fifo_bth_ack_req   = m_rx_roce_acks_fifo_bth.ack_request;

    assign rx_roce_acks_fifo_aeth_valid    = m_rx_roce_acks_fifo_bth_valid    ;
    assign rx_roce_acks_fifo_aeth_msn      = m_rx_roce_acks_fifo_aeth.msn     ;
    assign rx_roce_acks_fifo_aeth_syndrome = m_rx_roce_acks_fifo_aeth.syndrome;

    axis_async_fifo #(
        .DEPTH(3),
        .DATA_WIDTH(3+32+24+24+24+24+32+64+32+1+1),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0),
        .RAM_PIPELINE(1)
    ) cm_qp_async_fifo (
        .s_clk(clk_stack),
        .s_rst(rst_stack),


        .s_axis_tdata ({cm_qp_req_type, cm_qp_dma_transfer_length, cm_qp_rem_qpn, cm_qp_loc_qpn, cm_qp_rem_psn, cm_qp_loc_psn, cm_qp_r_key, cm_qp_rem_addr, cm_qp_rem_ip_addr, qp_is_immediate, qp_tx_type}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(cm_qp_valid),
        .s_axis_tready(),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_roce_eng),
        .m_rst(rst_roce_eng),

        // AXI output
        .m_axis_tdata ({cm_qp_req_type_roce, cm_qp_dma_transfer_length_roce, cm_qp_rem_qpn_roce, cm_qp_loc_qpn_roce, cm_qp_rem_psn_roce, cm_qp_loc_psn_roce, cm_qp_r_key_roce, cm_qp_rem_addr_roce, cm_qp_rem_ip_addr_roce, qp_is_immediate_roce, qp_tx_type_roce}),
        .m_axis_tkeep (),
        .m_axis_tvalid(cm_qp_valid_roce),
        .m_axis_tready(1'b1),
        .m_axis_tlast (),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ()
    );

    axis_async_fifo #(
        .DEPTH(4),
        .DATA_WIDTH(2),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0),
        .RAM_PIPELINE(1)
    ) cm_qp_status_async_fifo (
        .s_clk(clk_roce_eng),
        .s_rst(rst_roce_eng),


        .s_axis_tdata (cm_qp_status_roce),
        .s_axis_tkeep (0),
        .s_axis_tvalid(cm_qp_status_valid_roce),
        .s_axis_tready(),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        .m_clk(clk_stack),
        .m_rst(rst_stack),

        // AXI output
        .m_axis_tdata (cm_qp_status),
        .m_axis_tkeep (),
        .m_axis_tvalid(cm_qp_status_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast (),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ()
    );


    RoCE_qp_state_module #(
        .N_QUEUE_PAIRS(N_QUEUE_PAIRS),
        .REM_ADDR_WIDTH(16)
    ) RoCE_qp_state_module_instance (
        .clk                    (clk_roce_eng),
        .rst                    (rst_roce_eng),
        .rst_qp                 (1'b0),
        // open qp
        .cm_qp_valid          (cm_qp_valid_roce),
        .cm_qp_req_type       (cm_qp_req_type_roce),
        .cm_qp_r_key          (cm_qp_r_key_roce),
        .cm_qp_rem_qpn        (cm_qp_rem_qpn_roce),
        .cm_qp_loc_qpn        (cm_qp_loc_qpn_roce),
        .cm_qp_rem_psn        (cm_qp_rem_psn_roce),
        .cm_qp_loc_psn        (cm_qp_loc_psn_roce),
        .cm_qp_rem_ip_addr    (cm_qp_rem_ip_addr_roce),
        .cm_qp_rem_addr       (cm_qp_rem_addr_roce),
        //open status
        .cm_qp_status_valid(cm_qp_status_valid_roce),
        .cm_qp_status(cm_qp_status_roce),
        // close qp if transfer did not succeed
        .s_qp_close_valid  (m_qp_close_valid),
        .s_qp_close_ready  (m_qp_close_ready),
        .s_qp_close_loc_qpn(m_qp_close_loc_qpn),
        .s_qp_close_rem_psn(m_qp_close_rem_psn),

        // QP request
        .s_qp_context_req_valid   (m_qp_context_req_valid),
        .s_qp_context_req_ready   (m_qp_context_req_ready),
        .s_qp_context_loc_qpn_req (m_qp_context_loc_qpn_req),
        // request reply
        .m_qp_context_req_valid      (s_qp_context_req_valid),
        .m_qp_context_req_state      (s_qp_context_req_state),
        .m_qp_context_req_r_key      (s_qp_context_req_r_key),
        .m_qp_context_req_rem_qpn    (s_qp_context_req_rem_qpn),
        .m_qp_context_req_loc_qpn    (s_qp_context_req_loc_qpn),
        .m_qp_context_req_rem_psn    (s_qp_context_req_rem_psn),
        .m_qp_context_req_loc_psn    (s_qp_context_req_loc_psn),
        .m_qp_context_req_rem_ip_addr(s_qp_context_req_rem_ip_addr),
        .m_qp_context_req_rem_addr   (s_qp_context_req_rem_addr),

        // QP spy
        .qp_context_spy         (m_qp_context_spy_cdc),
        .qp_local_qpn_spy       (m_qp_local_qpn_spy_cdc),
        .qp_spy_context_valid   (s_qp_spy_context_valid_cdc),
        .qp_spy_state           (s_qp_spy_state_cdc),
        .qp_spy_r_key           (s_qp_spy_r_key_cdc),
        .qp_spy_rem_qpn         (s_qp_spy_rem_qpn_cdc),
        .qp_spy_loc_qpn         (s_qp_spy_loc_qpn_cdc),
        .qp_spy_rem_psn         (s_qp_spy_rem_psn_cdc),
        .qp_spy_rem_acked_psn   (s_qp_spy_rem_acked_psn_cdc),
        .qp_spy_loc_psn         (s_qp_spy_loc_psn_cdc),
        .qp_spy_rem_ip_addr     (s_qp_spy_rem_ip_addr_cdc),
        .qp_spy_rem_addr        (s_qp_spy_rem_addr_cdc),
        .qp_spy_syndrome        (s_qp_spy_syndrome_cdc),

        .s_qp_update_context_valid(m_qp_update_context_valid),
        .s_qp_update_context_ready(m_qp_update_context_ready),
        .s_qp_update_loc_qpn      (m_qp_update_context_loc_qpn),
        .s_qp_update_rem_psn      (m_qp_update_context_rem_psn),

        .s_roce_rx_bth_valid    (rx_roce_acks_fifo_bth_valid && rx_roce_acks_fifo_bth_ready),
        .s_roce_rx_bth_op_code  (rx_roce_acks_fifo_bth_op_code),
        .s_roce_rx_bth_p_key    (rx_roce_acks_fifo_bth_p_key),
        .s_roce_rx_bth_psn      (rx_roce_acks_fifo_bth_psn),
        .s_roce_rx_bth_dest_qp  (rx_roce_acks_fifo_bth_dest_qp),
        .s_roce_rx_bth_ack_req  (rx_roce_acks_fifo_bth_ack_req),
        .s_roce_rx_aeth_valid   (rx_roce_acks_fifo_aeth_valid && rx_roce_acks_fifo_bth_ready), // same ready as bth
        .s_roce_rx_aeth_syndrome(rx_roce_acks_fifo_aeth_syndrome),
        .s_roce_rx_aeth_msn     (rx_roce_acks_fifo_aeth_msn),

        .last_acked_psn         (),
        .stop_transfer          (),
        .pmtu(pmtu_cdc)
    );


    // TX QUEUES
    generate
        genvar i;
        for (i=0; i<N_QUEUE_PAIRS; i=i+1) begin

            wire rst_tx_engine = cm_qp_valid_roce && cm_qp_loc_qpn_roce == (256+i) && cm_qp_req_type_roce == REQ_OPEN_QP;
            wire stop_data_gen = cm_qp_valid_roce && cm_qp_loc_qpn_roce == (256+i) && cm_qp_req_type_roce == REQ_CLOSE_QP;



            RoCE_data_generator #(
                .DATA_WIDTH(QP_CH_DATA_WIDTH)
            ) RoCE_data_generator_instance (
                .clk(clk_roce_eng),
                .rst(rst_tx_engine),

                .rst_word_ctr(rst_tx_engine),

                .stop(wr_error_qp_not_rts[i] || stop_data_gen),

                .txmeta_valid           (txmeta_roce_valid && txmeta_roce_loc_qpn==(256+i)),
                .txmeta_start_transfer  (txmeta_roce_start_transfer),
                .txmeta_loc_qpn         (txmeta_roce_loc_qpn),
                .txmeta_is_immediate    (txmeta_roce_is_immediate),
                .txmeta_tx_type         (txmeta_roce_tx_type),
                .txmeta_dma_transfer    (txmeta_roce_dma_transfer),
                .txmeta_n_transfers     (txmeta_roce_n_transfers),
                .txmeta_frequency       (txmeta_roce_frequency),

                .m_wr_req_valid         (m_wr_req_gen_valid[i]),
                .m_wr_req_ready         (m_wr_req_gen_ready[i]),
                .m_wr_req_tx_type       (m_wr_req_gen_tx_type[i]),
                .m_wr_req_is_immediate  (m_wr_req_gen_is_immediate[i]),
                .m_wr_req_immediate_data(m_wr_req_gen_immediate_data[i]),
                .m_wr_req_loc_qp        (m_wr_req_gen_loc_qp[i]),
                .m_wr_req_addr_offset   (m_wr_req_gen_addr_offset[i]),
                .m_wr_req_dma_length    (m_wr_req_gen_dma_length[i]),

                .m_axis_tdata           (m_gen_axis_tdata[i]),
                .m_axis_tkeep           (m_gen_axis_tkeep[i]),
                .m_axis_tvalid          (m_gen_axis_tvalid[i]),
                .m_axis_tready          (m_gen_axis_tready[i]),
                .m_axis_tlast           (m_gen_axis_tlast[i]),
                .m_axis_tuser           (m_gen_axis_tuser[i]),

                .wr_error_qp_not_rts(wr_error_qp_not_rts[i]),
                .wr_error_loc_qpn   (wr_error_loc_qpn[i])
            );

        end
    endgenerate

    // demux RoCE acks
    localparam int SEL_WIDTH  = (N_ROCE_TX_ENGINES > 1) ? $clog2(N_ROCE_TX_ENGINES) : 1;
    localparam int QP_WIDTH   = $clog2(N_QUEUE_PAIRS);

    wire  [N_ROCE_TX_ENGINES-1:0] rx_roce_acks_tx_eng_bth_ready;
    wire  [N_ROCE_TX_ENGINES-1:0] rx_roce_acks_tx_eng_aeth_ready;

    reg [N_ROCE_TX_ENGINES-1:0] s_selector_acks_tx_eng;
    wire s_select_no_ack   = 1'b0;

    wire [SEL_WIDTH-1:0] sel_acks;

    generate
        if (N_ROCE_TX_ENGINES== 1) begin
            assign sel_acks = 0;
        end else begin
            assign sel_acks = rx_roce_acks_fifo_bth_dest_qp[QP_WIDTH-1 -: SEL_WIDTH];
        end
    endgenerate

    always @(*) begin
        s_selector_acks_tx_eng = 0;
        for (int i = 0; i < N_ROCE_TX_ENGINES; i++) begin
            s_selector_acks_tx_eng[i] = (sel_acks == SEL_WIDTH'(i));
        end
    end

    assign rx_roce_acks_fifo_bth_ready = |(s_selector_acks_tx_eng  & rx_roce_acks_tx_eng_bth_ready) || (s_select_no_ack);

    // demux cm reply

    reg [N_ROCE_TX_ENGINES-1:0] s_selector_cm_reply_tx_eng;
    wire [SEL_WIDTH-1:0] sel_cm_reply;

    generate
        if (N_ROCE_TX_ENGINES== 1) begin
            assign sel_cm_reply = 0;
        end else begin
            assign sel_cm_reply = cm_qp_loc_qpn_roce[QP_WIDTH-1 -: SEL_WIDTH];
        end
    endgenerate

    always @(*) begin
        s_selector_cm_reply_tx_eng = 0;
        for (int i = 0; i < N_ROCE_TX_ENGINES; i++) begin
            s_selector_cm_reply_tx_eng[i] = (sel_cm_reply == SEL_WIDTH'(i));
        end
    end

    // demux context req reply

    reg [N_ROCE_TX_ENGINES-1:0] s_selector_context_reply_tx_eng;
    wire [SEL_WIDTH-1:0] sel_context_reply;

    generate
        if (N_ROCE_TX_ENGINES== 1) begin
            assign sel_context_reply = '0;
        end else begin
            assign sel_context_reply = s_qp_context_req_loc_qpn[QP_WIDTH-1 -: SEL_WIDTH];
        end
    endgenerate

    always @(*) begin
        s_selector_context_reply_tx_eng = '0;
        for (int i = 0; i < N_ROCE_TX_ENGINES; i++) begin
            s_selector_context_reply_tx_eng[i] = (sel_context_reply == SEL_WIDTH'(i));
        end
    end

    // arbitrated qp state requests (from various queue pairs)
    axis_arb_mux #(
        .S_COUNT(N_ROCE_TX_ENGINES),
        .DATA_WIDTH(24),
        .KEEP_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0)
    ) axis_arb_mux_qp_state_req (
        .clk(clk_roce_eng),
        .rst(rst_roce_eng),

        .s_axis_tdata (qp_context_loc_qpn_tx_eng_req),
        .s_axis_tkeep (0),
        .s_axis_tvalid(qp_context_tx_eng_req_valid),
        .s_axis_tready(qp_context_tx_eng_req_ready),
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
        .clk(clk_roce_eng),
        .rst(rst_roce_eng),

        .s_axis_tdata (qp_update_context_loc_qpn_rem_psn_tx_eng),
        .s_axis_tkeep (0),
        .s_axis_tvalid(qp_update_context_tx_eng_valid),
        .s_axis_tready(qp_update_context_tx_eng_ready),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_axis_tdata({m_qp_update_context_rem_psn, m_qp_update_context_loc_qpn}),
        .m_axis_tvalid(m_qp_update_context_valid),
        .m_axis_tready(m_qp_update_context_ready)
    );

    axis_arb_mux #(
        .S_COUNT(N_QUEUE_PAIRS),
        .DATA_WIDTH(48),
        .KEEP_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0)
    ) axis_arb_mux_close_qp_req (
        .clk(clk_roce_eng),
        .rst(rst_roce_eng),

        .s_axis_tdata (qp_close_loc_qpn_rem_psn_tx_eng),
        .s_axis_tkeep (0),
        .s_axis_tvalid(qp_close_tx_eng_valid),
        .s_axis_tready(qp_close_tx_eng_ready),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_axis_tdata({m_qp_close_rem_psn, m_qp_close_loc_qpn}),
        .m_axis_tvalid(m_qp_close_valid),
        .m_axis_tready(m_qp_close_ready)
    );




    generate
        for (i = 0; i< N_ROCE_TX_ENGINES; i++)begin

            /*
            AXI FULL INTERFACES
            */
            wire [0                :0]                  m_axi_awid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_awaddr;
            wire [7:0]                                  m_axi_awlen;
            wire [2:0]                                  m_axi_awsize;
            wire [1:0]                                  m_axi_awburst;
            wire                                        m_axi_awlock;
            wire [3:0]                                  m_axi_awcache;
            wire [2:0]                                  m_axi_awprot;
            wire                                        m_axi_awvalid;
            wire                                        m_axi_awready;
            wire [OUT_DATA_WIDTH - 1 : 0]               m_axi_wdata;
            wire [OUT_KEEP_WIDTH - 1 : 0]               m_axi_wstrb;
            wire                                        m_axi_wlast;
            wire                                        m_axi_wvalid;
            wire                                        m_axi_wready;
            wire [0             :0]                     m_axi_bid;
            wire [1:0]                                  m_axi_bresp;
            wire                                        m_axi_bvalid;
            wire                                        m_axi_bready;
            wire [0               :0]                   m_axi_arid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_araddr;
            wire [7:0]                                  m_axi_arlen;
            wire [2:0]                                  m_axi_arsize;
            wire [1:0]                                  m_axi_arburst;
            wire                                        m_axi_arlock;
            wire [3:0]                                  m_axi_arcache;
            wire [2:0]                                  m_axi_arprot;
            wire                                        m_axi_arvalid;
            wire                                        m_axi_arready;
            wire [0             :0]                     m_axi_rid;
            wire [OUT_DATA_WIDTH   - 1 : 0]             m_axi_rdata;
            wire [1:0]                                  m_axi_rresp;
            wire                                        m_axi_rlast;
            wire                                        m_axi_rvalid;
            wire                                        m_axi_rready;

            wire [0                :0]                  m_axi_ram_awid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_ram_awaddr;
            wire [7:0]                                  m_axi_ram_awlen;
            wire [2:0]                                  m_axi_ram_awsize;
            wire [1:0]                                  m_axi_ram_awburst;
            wire                                        m_axi_ram_awlock;
            wire [3:0]                                  m_axi_ram_awcache;
            wire [2:0]                                  m_axi_ram_awprot;
            wire                                        m_axi_ram_awvalid;
            wire                                        m_axi_ram_awready;
            wire [OUT_DATA_WIDTH - 1 : 0]               m_axi_ram_wdata;
            wire [OUT_KEEP_WIDTH - 1 : 0]               m_axi_ram_wstrb;
            wire                                        m_axi_ram_wlast;
            wire                                        m_axi_ram_wvalid;
            wire                                        m_axi_ram_wready;
            wire [0             :0]                     m_axi_ram_bid;
            wire [1:0]                                  m_axi_ram_bresp;
            wire                                        m_axi_ram_bvalid;
            wire                                        m_axi_ram_bready;
            wire [0               :0]                   m_axi_ram_arid;
            wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] m_axi_ram_araddr;
            wire [7:0]                                  m_axi_ram_arlen;
            wire [2:0]                                  m_axi_ram_arsize;
            wire [1:0]                                  m_axi_ram_arburst;
            wire                                        m_axi_ram_arlock;
            wire [3:0]                                  m_axi_ram_arcache;
            wire [2:0]                                  m_axi_ram_arprot;
            wire                                        m_axi_ram_arvalid;
            wire                                        m_axi_ram_arready;
            wire [0             :0]                     m_axi_ram_rid;
            wire [OUT_DATA_WIDTH   - 1 : 0]             m_axi_ram_rdata;
            wire [1:0]                                  m_axi_ram_rresp;
            wire                                        m_axi_ram_rlast;
            wire                                        m_axi_ram_rvalid;
            wire                                        m_axi_ram_rready;

            // Retransmission module output 
            wire        m_roce_retrans_bth_valid ;
            wire        m_roce_retrans_bth_ready ;
            wire [7:0]  m_roce_retrans_bth_op_code ;
            wire [15:0] m_roce_retrans_bth_p_key   ;
            wire [23:0] m_roce_retrans_bth_psn     ;
            wire [23:0] m_roce_retrans_bth_dest_qp ;
            wire        m_roce_retrans_bth_ack_req ;
            wire [23:0] m_roce_retrans_bth_src_qp ;;

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



            // RoCE TX engine wrapper inst
            RoCE_tx_engine_wrapper #(
                .QP_CH_DATA_WIDTH(QP_CH_DATA_WIDTH),
                .QP_CH_KEEP_ENABLE(QP_CH_KEEP_ENABLE),
                .QP_CH_KEEP_WIDTH(QP_CH_KEEP_WIDTH),
                .OUT_DATA_WIDTH(OUT_DATA_WIDTH),
                .OUT_KEEP_ENABLE(OUT_KEEP_ENABLE),
                .OUT_KEEP_WIDTH(OUT_KEEP_WIDTH),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .REFRESH_CACHE_TICKS(REFRESH_CACHE_TICKS),
                .RETRANSMISSION_ADDR_BUFFER_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)),
                .N_QUEUE_PAIRS(N_QUEUE_PAIRS/N_ROCE_TX_ENGINES),
                .BASE_LOC_QPN(256 + i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES), //TODO add check MAX_QUEUE_PAIRS >= N_ROCE_TX_ENGINES, both must be power of 2
                .DEBUG(DEBUG)
            ) RoCE_tx_engine_wrapper_instance (
                .clk(clk_roce_eng),
                .rst(rst_roce_eng),
                .flow_ctrl_pause(flow_ctrl_pause),
                // RoCE ACKS
                .s_roce_rx_bth_valid         (rx_roce_acks_fifo_bth_valid & s_selector_acks_tx_eng[i]),
                .s_roce_rx_bth_ready         (rx_roce_acks_tx_eng_bth_ready[i]),
                .s_roce_rx_bth_psn           (rx_roce_acks_fifo_bth_psn),
                .s_roce_rx_bth_op_code       (rx_roce_acks_fifo_bth_op_code),
                .s_roce_rx_bth_dest_qp       (rx_roce_acks_fifo_bth_dest_qp),
                .s_roce_rx_aeth_valid        (rx_roce_acks_fifo_aeth_valid & s_selector_acks_tx_eng[i]),
                .s_roce_rx_aeth_ready        (rx_roce_acks_tx_eng_aeth_ready[i]),
                .s_roce_rx_aeth_syndrome     (rx_roce_acks_fifo_aeth_syndrome),
                .s_roce_rx_last_not_acked_psn(),
                // DATA in
                /*
                .s_wr_req_valid         (s_wr_req_valid),
                .s_wr_req_ready         (s_wr_req_ready),
                .s_wr_req_tx_type       (s_wr_req_tx_type),
                .s_wr_req_is_immediate  (s_wr_req_is_immediate),
                .s_wr_req_immediate_data(s_wr_req_immediate_data),
                .s_wr_req_loc_qp        (s_wr_req_loc_qp),
                .s_wr_req_addr_offset   (s_wr_req_addr_offset),
                .s_wr_req_dma_length    (s_wr_req_dma_length),
                .s_axis_tdata           (s_axis_tdata),
                .s_axis_tkeep           (s_axis_tkeep),
                .s_axis_tvalid          (s_axis_tvalid),
                .s_axis_tready          (s_axis_tready),
                .s_axis_tlast           (s_axis_tlast),
                .s_axis_tuser           (s_axis_tuser),
                */
                .s_wr_req_valid         (m_wr_req_gen_valid[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_ready         (m_wr_req_gen_ready[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_tx_type       (m_wr_req_gen_tx_type[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_is_immediate  (m_wr_req_gen_is_immediate[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_immediate_data(m_wr_req_gen_immediate_data[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_loc_qp        (m_wr_req_gen_loc_qp[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_addr_offset   (m_wr_req_gen_addr_offset[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_wr_req_dma_length    (m_wr_req_gen_dma_length[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tdata           (m_gen_axis_tdata[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tkeep           (m_gen_axis_tkeep[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tvalid          (m_gen_axis_tvalid[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tready          (m_gen_axis_tready[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tlast           (m_gen_axis_tlast[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .s_axis_tuser           (m_gen_axis_tuser[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),

                // RoCE data and headers out
                .m_roce_bth_valid    (m_roce_retrans_bth_valid),
                .m_roce_bth_ready    (m_roce_retrans_bth_ready),
                .m_roce_bth_op_code  (m_roce_retrans_bth_op_code),
                .m_roce_bth_p_key    (m_roce_retrans_bth_p_key),
                .m_roce_bth_psn      (m_roce_retrans_bth_psn),
                .m_roce_bth_dest_qp  (m_roce_retrans_bth_dest_qp),
                .m_roce_bth_src_qp   (m_roce_retrans_bth_src_qp),
                .m_roce_bth_ack_req  (m_roce_retrans_bth_ack_req),
                .m_roce_reth_valid   (m_roce_retrans_reth_valid),
                .m_roce_reth_ready   (m_roce_retrans_reth_ready),
                .m_roce_reth_v_addr  (m_roce_retrans_reth_v_addr),
                .m_roce_reth_r_key   (m_roce_retrans_reth_r_key),
                .m_roce_reth_length  (m_roce_retrans_reth_length),
                .m_roce_immdh_valid  (m_roce_retrans_immdh_valid),
                .m_roce_immdh_ready  (m_roce_retrans_immdh_ready),
                .m_roce_immdh_data   (m_roce_retrans_immdh_data),
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
                .m_ip_dest_ip        (m_roce_retrans_ip_dest_ip),
                .m_udp_source_port   (),
                .m_udp_dest_port     (m_roce_retrans_udp_dest_port),
                .m_udp_length        (m_roce_retrans_udp_length),
                .m_udp_checksum      (),
                .m_roce_payload_axis_tdata (m_roce_retrans_payload_axis_tdata),
                .m_roce_payload_axis_tkeep (m_roce_retrans_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid(m_roce_retrans_payload_axis_tvalid),
                .m_roce_payload_axis_tready(m_roce_retrans_payload_axis_tready),
                .m_roce_payload_axis_tlast (m_roce_retrans_payload_axis_tlast),
                .m_roce_payload_axis_tuser (m_roce_retrans_payload_axis_tuser),

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

                .m_qp_update_context_valid  (qp_update_context_tx_eng_valid[i]),
                .m_qp_update_context_ready  (qp_update_context_tx_eng_ready[i]),
                .m_qp_update_context_loc_qpn(qp_update_context_loc_qpn_rem_psn_tx_eng[i*48+:24]), // loc qpn
                .m_qp_update_context_rem_psn(qp_update_context_loc_qpn_rem_psn_tx_eng[i*48+24+:24]), // rem psn

                .wr_error_qp_not_rts_out    (wr_error_qp_not_rts[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),
                .wr_error_loc_qpn_out       (wr_error_loc_qpn[i*N_QUEUE_PAIRS/N_ROCE_TX_ENGINES+:N_QUEUE_PAIRS/N_ROCE_TX_ENGINES]),

                .cm_qp_valid              (cm_qp_valid_roce  & s_selector_cm_reply_tx_eng[i]),
                .cm_qp_req_type           (cm_qp_req_type_roce),
                .cm_qp_dma_transfer_length(cm_qp_dma_transfer_length_roce),
                .cm_qp_rem_qpn            (cm_qp_rem_qpn_roce),
                .cm_qp_loc_qpn            (cm_qp_loc_qpn_roce),
                .cm_qp_rem_psn            (cm_qp_rem_psn_roce),
                .cm_qp_loc_psn            (cm_qp_loc_psn_roce),
                .cm_qp_r_key              (cm_qp_r_key_roce),
                .cm_qp_rem_addr           (cm_qp_rem_addr_roce),
                .cm_qp_rem_ip_addr        (cm_qp_rem_ip_addr_roce),
                .qp_is_immediate          (qp_is_immediate_roce),
                .qp_tx_type               (qp_tx_type_roce),


                .m_qp_context_req_valid   (qp_context_tx_eng_req_valid[i]),
                .m_qp_context_req_ready   (qp_context_tx_eng_req_ready[i]),
                .m_qp_context_loc_qpn_req (qp_context_loc_qpn_tx_eng_req[i*24+:24]),

                .s_qp_context_req_valid        (s_qp_context_req_valid & s_selector_context_reply_tx_eng[i]),
                .s_qp_context_req_state        (s_qp_context_req_state),
                .s_qp_context_req_rem_qpn      (s_qp_context_req_rem_qpn),
                .s_qp_context_req_loc_qpn      (s_qp_context_req_loc_qpn),
                .s_qp_context_req_rem_psn      (s_qp_context_req_rem_psn),
                .s_qp_context_req_loc_psn      (s_qp_context_req_loc_psn),
                .s_qp_context_req_r_key        (s_qp_context_req_r_key),
                .s_qp_context_req_rem_addr     (s_qp_context_req_rem_addr),
                .s_qp_context_req_rem_ip_addr  (s_qp_context_req_rem_ip_addr),

                .m_qp_close_valid  (qp_close_tx_eng_valid[i]),
                .m_qp_close_ready  (qp_close_tx_eng_ready[i]),
                .m_qp_close_loc_qpn(qp_close_loc_qpn_rem_psn_tx_eng[48*i+:24]),
                .m_qp_close_rem_psn(qp_close_loc_qpn_rem_psn_tx_eng[48*i+24+:24]),


                .cfg_valid                (1),
                .timeout_period           (timeout_period),
                .retry_count              (retry_count),
                .rnr_retry_count          (rnr_retry_count),
                .loc_ip_addr              (32'd0),
                .pmtu                     (pmtu_cdc),

                .monitor_loc_qpn          (monitor_loc_qpn_cdc),
                .cfg_latency_avg_po2      (cfg_latency_avg_po2_cdc),
                .cfg_throughput_avg_po2   (cfg_throughput_avg_po2_cdc),
                .transfer_time_avg        (transfer_time_avg_tx_eng[i]),
                .transfer_time_moving_avg (transfer_time_moving_avg_tx_eng[i]),
                .transfer_time_inst       (transfer_time_inst_tx_eng[i]),
                .latency_avg              (latency_avg_tx_eng[i]),
                .latency_moving_avg       (latency_moving_avg_tx_eng[i]),
                .latency_inst             (latency_inst_tx_eng[i]),
                .latency_inst_valid       (latency_inst_valid_tx_eng[i]),
                .n_retransmit_triggers    (n_retransmit_triggers_tx_eng[i]),
                .n_rnr_retransmit_triggers(n_rnr_retransmit_triggers_tx_eng[i]),
                .psn_diff                 (psn_diff_tx_eng[i])
            );

            axi_register #(
                .DATA_WIDTH(OUT_DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)),
                .STRB_WIDTH(OUT_KEEP_WIDTH),
                .ID_WIDTH(1)
            ) axi_register_ram_instance (
                .clk(clk_roce_eng),
                .rst(rst_roce_eng),
                .s_axi_awid   (m_axi_awid),
                .s_axi_awaddr (m_axi_awaddr),
                .s_axi_awlen  (m_axi_awlen),
                .s_axi_awsize (m_axi_awsize),
                .s_axi_awburst(m_axi_awburst),
                .s_axi_awlock (m_axi_awlock),
                .s_axi_awcache(m_axi_awcache),
                .s_axi_awprot (m_axi_awprot),
                .s_axi_awvalid(m_axi_awvalid),
                .s_axi_awready(m_axi_awready),
                .s_axi_wdata  (m_axi_wdata),
                .s_axi_wstrb  (m_axi_wstrb),
                .s_axi_wlast  (m_axi_wlast),
                .s_axi_wvalid (m_axi_wvalid),
                .s_axi_wready (m_axi_wready),
                .s_axi_bid    (m_axi_bid),
                .s_axi_bresp  (m_axi_bresp),
                .s_axi_bvalid (m_axi_bvalid),
                .s_axi_bready (m_axi_bready),
                .s_axi_arid   (m_axi_arid),
                .s_axi_araddr (m_axi_araddr),
                .s_axi_arlen  (m_axi_arlen),
                .s_axi_arsize (m_axi_arsize),
                .s_axi_arburst(m_axi_arburst),
                .s_axi_arlock (m_axi_arlock),
                .s_axi_arcache(m_axi_arcache),
                .s_axi_arprot (m_axi_arprot),
                .s_axi_arvalid(m_axi_arvalid),
                .s_axi_arready(m_axi_arready),
                .s_axi_rid    (m_axi_rid),
                .s_axi_rdata  (m_axi_rdata),
                .s_axi_rresp  (m_axi_rresp),
                .s_axi_rlast  (m_axi_rlast),
                .s_axi_rvalid (m_axi_rvalid),
                .s_axi_rready (m_axi_rready),

                .m_axi_awid   (m_axi_ram_awid),
                .m_axi_awaddr (m_axi_ram_awaddr),
                .m_axi_awlen  (m_axi_ram_awlen),
                .m_axi_awsize (m_axi_ram_awsize),
                .m_axi_awburst(m_axi_ram_awburst),
                .m_axi_awlock (m_axi_ram_awlock),
                .m_axi_awcache(m_axi_ram_awcache),
                .m_axi_awprot (m_axi_ram_awprot),
                .m_axi_awvalid(m_axi_ram_awvalid),
                .m_axi_awready(m_axi_ram_awready),
                .m_axi_wdata  (m_axi_ram_wdata),
                .m_axi_wstrb  (m_axi_ram_wstrb),
                .m_axi_wlast  (m_axi_ram_wlast),
                .m_axi_wvalid (m_axi_ram_wvalid),
                .m_axi_wready (m_axi_ram_wready),
                .m_axi_bid    (m_axi_ram_bid),
                .m_axi_bresp  (m_axi_ram_bresp),
                .m_axi_bvalid (m_axi_ram_bvalid),
                .m_axi_bready (m_axi_ram_bready),
                .m_axi_arid   (m_axi_ram_arid),
                .m_axi_araddr (m_axi_ram_araddr),
                .m_axi_arlen  (m_axi_ram_arlen),
                .m_axi_arsize (m_axi_ram_arsize),
                .m_axi_arburst(m_axi_ram_arburst),
                .m_axi_arlock (m_axi_ram_arlock),
                .m_axi_arcache(m_axi_ram_arcache),
                .m_axi_arprot (m_axi_ram_arprot),
                .m_axi_arvalid(m_axi_ram_arvalid),
                .m_axi_arready(m_axi_ram_arready),
                .m_axi_rid    (m_axi_ram_rid),
                .m_axi_rdata  (m_axi_ram_rdata),
                .m_axi_rresp  (m_axi_ram_rresp),
                .m_axi_rlast  (m_axi_ram_rlast),
                .m_axi_rvalid (m_axi_ram_rvalid),
                .m_axi_rready (m_axi_ram_rready)
            );

            axi_ram_xpm #(
                .DATA_WIDTH(OUT_DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH-$clog2(N_ROCE_TX_ENGINES)),
                .STRB_WIDTH(OUT_KEEP_WIDTH),
                .ID_WIDTH(1),
                .READ_LATENCY(6)
            ) RoCE_axi_buffer_instance (
                .clk(clk_roce_eng),
                .rst(rst_roce_eng),

                .s_axi_awid   (m_axi_ram_awid),
                .s_axi_awaddr (m_axi_ram_awaddr),
                .s_axi_awlen  (m_axi_ram_awlen),
                .s_axi_awsize (m_axi_ram_awsize),
                .s_axi_awburst(m_axi_ram_awburst),
                .s_axi_awlock (m_axi_ram_awlock),
                .s_axi_awcache(m_axi_ram_awcache),
                .s_axi_awprot (m_axi_ram_awprot),
                .s_axi_awvalid(m_axi_ram_awvalid),
                .s_axi_awready(m_axi_ram_awready),

                .s_axi_wdata  (m_axi_ram_wdata),
                .s_axi_wstrb  (m_axi_ram_wstrb),
                .s_axi_wlast  (m_axi_ram_wlast),
                .s_axi_wvalid (m_axi_ram_wvalid),
                .s_axi_wready (m_axi_ram_wready),

                .s_axi_bid    (m_axi_ram_bid),
                .s_axi_bresp  (m_axi_ram_bresp),
                .s_axi_bvalid (m_axi_ram_bvalid),
                .s_axi_bready (m_axi_ram_bready),

                .s_axi_arid   (m_axi_ram_arid),
                .s_axi_araddr (m_axi_ram_araddr),
                .s_axi_arlen  (m_axi_ram_arlen),
                .s_axi_arsize (m_axi_ram_arsize),
                .s_axi_arburst(m_axi_ram_arburst),
                .s_axi_arlock (m_axi_ram_arlock),
                .s_axi_arcache(m_axi_ram_arcache),
                .s_axi_arprot (m_axi_ram_arprot),
                .s_axi_arvalid(m_axi_ram_arvalid),
                .s_axi_arready(m_axi_ram_arready),

                .s_axi_rid    (m_axi_ram_rid),
                .s_axi_rdata  (m_axi_ram_rdata),
                .s_axi_rresp  (m_axi_ram_rresp),
                .s_axi_rlast  (m_axi_ram_rlast),
                .s_axi_rvalid (m_axi_ram_rvalid),
                .s_axi_rready (m_axi_ram_rready)
            );

            // finally back to clk_stack domain

            RoCE_realign_frame_fifo #(
                .S_DATA_WIDTH(OUT_DATA_WIDTH),
                .M_DATA_WIDTH(OUT_DATA_WIDTH),
                .HAS_ADAPTER(0),
                .IS_ASYNC(1),
                .FIFO_DEPTH(8192-OUT_DATA_WIDTH/8),
                .RAM_PIPELINE(2),
                .FRAME_FIFO(1),
                .PAUSE_ENABLE(0)
            ) RoCE_realign_frame_fifo_instance (
                .s_clk(clk_roce_eng),
                .s_rst(rst_roce_eng),

                .s_roce_bth_valid    (m_roce_retrans_bth_valid),
                .s_roce_bth_ready    (m_roce_retrans_bth_ready),
                .s_roce_bth_op_code  (m_roce_retrans_bth_op_code),
                .s_roce_bth_p_key    (m_roce_retrans_bth_p_key),
                .s_roce_bth_psn      (m_roce_retrans_bth_psn),
                .s_roce_bth_dest_qp  (m_roce_retrans_bth_dest_qp),
                .s_roce_bth_src_qp   (m_roce_retrans_bth_src_qp),
                .s_roce_bth_ack_req  (m_roce_retrans_bth_ack_req),
                .s_roce_reth_valid   (m_roce_retrans_reth_valid),
                .s_roce_reth_ready   (m_roce_retrans_reth_ready),
                .s_roce_reth_v_addr  (m_roce_retrans_reth_v_addr),
                .s_roce_reth_r_key   (m_roce_retrans_reth_r_key),
                .s_roce_reth_length  (m_roce_retrans_reth_length),
                .s_roce_immdh_valid  (m_roce_retrans_immdh_valid),
                .s_roce_immdh_ready  (m_roce_retrans_immdh_ready),
                .s_roce_immdh_data   (m_roce_retrans_immdh_data),
                .s_ip_dest_ip        (m_roce_retrans_ip_dest_ip),
                .s_udp_dest_port     (m_roce_retrans_udp_dest_port),
                .s_udp_length        (m_roce_retrans_udp_length),

                .s_roce_payload_axis_tdata (m_roce_retrans_payload_axis_tdata),
                .s_roce_payload_axis_tkeep (m_roce_retrans_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid(m_roce_retrans_payload_axis_tvalid),
                .s_roce_payload_axis_tready(m_roce_retrans_payload_axis_tready),
                .s_roce_payload_axis_tlast (m_roce_retrans_payload_axis_tlast),
                .s_roce_payload_axis_tuser (m_roce_retrans_payload_axis_tuser),

                .m_clk(clk_stack),
                .m_rst(rst_stack),

                .m_roce_bth_valid          (m_roce_retrans_fifo_bth_valid[i]),
                .m_roce_bth_ready          (m_roce_retrans_fifo_bth_ready[i]),
                .m_roce_bth_op_code        (m_roce_retrans_fifo_bth_op_code[i*8+:8]),
                .m_roce_bth_p_key          (m_roce_retrans_fifo_bth_p_key[i*16+:16]),
                .m_roce_bth_psn            (m_roce_retrans_fifo_bth_psn[i*24+:24]),
                .m_roce_bth_dest_qp        (m_roce_retrans_fifo_bth_dest_qp[i*24+:24]),
                .m_roce_bth_src_qp         (m_roce_retrans_fifo_bth_src_qp[i*24+:24]),
                .m_roce_bth_ack_req        (m_roce_retrans_fifo_bth_ack_req[i]),
                .m_roce_reth_valid         (m_roce_retrans_fifo_reth_valid[i]),
                .m_roce_reth_ready         (m_roce_retrans_fifo_reth_ready[i]),
                .m_roce_reth_v_addr        (m_roce_retrans_fifo_reth_v_addr[i*64+:64]),
                .m_roce_reth_r_key         (m_roce_retrans_fifo_reth_r_key[i*32+:32]),
                .m_roce_reth_length        (m_roce_retrans_fifo_reth_length[i*32+:32]),
                .m_roce_immdh_valid        (m_roce_retrans_fifo_immdh_valid[i]),
                .m_roce_immdh_ready        (m_roce_retrans_fifo_immdh_ready[i]),
                .m_roce_immdh_data         (m_roce_retrans_fifo_immdh_data[i*32+:32]),
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
                .m_ip_source_ip            (),
                .m_ip_dest_ip              (m_roce_retrans_fifo_ip_dest_ip[i*32+:32]),
                .m_udp_source_port         (m_roce_retrans_fifo_udp_src_port[i*16+:16]),
                .m_udp_dest_port           (m_roce_retrans_fifo_udp_dest_port[i*16+:16]),
                .m_udp_length              (m_roce_retrans_fifo_udp_length[i*16+:16]),
                .m_udp_checksum            (m_roce_retrans_fifo_udp_checksum[i*16+:16]),

                .m_roce_payload_axis_tdata (m_roce_retrans_fifo_payload_axis_tdata[i*OUT_DATA_WIDTH+:OUT_DATA_WIDTH]),
                .m_roce_payload_axis_tkeep (m_roce_retrans_fifo_payload_axis_tkeep[i*OUT_KEEP_WIDTH+:OUT_KEEP_WIDTH]),
                .m_roce_payload_axis_tvalid(m_roce_retrans_fifo_payload_axis_tvalid[i]),
                .m_roce_payload_axis_tready(m_roce_retrans_fifo_payload_axis_tready[i]),
                .m_roce_payload_axis_tlast (m_roce_retrans_fifo_payload_axis_tlast[i]),
                .m_roce_payload_axis_tuser (m_roce_retrans_fifo_payload_axis_tuser[i]),

                .stall(1'b0),
                .loc_ip_addr(loc_ip_addr)
            );

        end
    endgenerate

    assign n_retransmit_triggers_cdc = n_retransmit_triggers_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign n_rnr_retransmit_triggers_cdc = n_rnr_retransmit_triggers_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign psn_diff_cdc = psn_diff_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];

    assign transfer_time_avg_cdc = transfer_time_avg_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign transfer_time_moving_avg_cdc = transfer_time_moving_avg_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign transfer_time_inst_cdc = transfer_time_inst_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign latency_avg_cdc = latency_avg_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign latency_moving_avg_cdc = latency_moving_avg_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];
    assign latency_inst_cdc = latency_inst_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]];

    

    // output arbiter

    RoCE_arb_mux #(
        .S_COUNT(N_ROCE_TX_ENGINES),
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(OUT_KEEP_WIDTH),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .ARB_TYPE_ROUND_ROBIN(1)
    ) RoCE_arb_mux_instance (
        .clk(clk_stack),
        .rst(rst_stack),
        .s_roce_bth_valid  (m_roce_retrans_fifo_bth_valid),
        .s_roce_bth_ready  (m_roce_retrans_fifo_bth_ready),
        .s_roce_bth_op_code(m_roce_retrans_fifo_bth_op_code),
        .s_roce_bth_p_key  (m_roce_retrans_fifo_bth_p_key),
        .s_roce_bth_psn    (m_roce_retrans_fifo_bth_psn),
        .s_roce_bth_dest_qp(m_roce_retrans_fifo_bth_dest_qp),
        .s_roce_bth_src_qp (m_roce_retrans_fifo_bth_src_qp),
        .s_roce_bth_ack_req(m_roce_retrans_fifo_bth_ack_req),
        .s_roce_reth_valid (m_roce_retrans_fifo_reth_valid),
        .s_roce_reth_ready (m_roce_retrans_fifo_reth_ready),
        .s_roce_reth_v_addr(m_roce_retrans_fifo_reth_v_addr),
        .s_roce_reth_r_key (m_roce_retrans_fifo_reth_r_key),
        .s_roce_reth_length(m_roce_retrans_fifo_reth_length),
        .s_roce_immdh_valid(m_roce_retrans_fifo_immdh_valid),
        .s_roce_immdh_ready(m_roce_retrans_fifo_immdh_ready),
        .s_roce_immdh_data (m_roce_retrans_fifo_immdh_data),
        .s_ip_dest_ip      (m_roce_retrans_fifo_ip_dest_ip),
        .s_udp_source_port (m_roce_retrans_fifo_udp_src_port),
        .s_udp_length      (m_roce_retrans_fifo_udp_length),

        .s_roce_payload_axis_tdata (m_roce_retrans_fifo_payload_axis_tdata),
        .s_roce_payload_axis_tkeep (m_roce_retrans_fifo_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(m_roce_retrans_fifo_payload_axis_tvalid),
        .s_roce_payload_axis_tready(m_roce_retrans_fifo_payload_axis_tready),
        .s_roce_payload_axis_tlast (m_roce_retrans_fifo_payload_axis_tlast),
        .s_roce_payload_axis_tuser (m_roce_retrans_fifo_payload_axis_tuser),

        .m_roce_bth_valid  (m_roce_final_arb_bth_valid),
        .m_roce_bth_ready  (m_roce_final_arb_bth_ready),
        .m_roce_bth_op_code(m_roce_final_arb_bth_op_code),
        .m_roce_bth_p_key  (m_roce_final_arb_bth_p_key),
        .m_roce_bth_psn    (m_roce_final_arb_bth_psn),
        .m_roce_bth_dest_qp(m_roce_final_arb_bth_dest_qp),
        .m_roce_bth_src_qp (m_roce_final_arb_bth_src_qp),
        .m_roce_bth_ack_req(m_roce_final_arb_bth_ack_req),
        .m_roce_reth_valid (m_roce_final_arb_reth_valid),
        .m_roce_reth_ready (m_roce_final_arb_reth_ready),
        .m_roce_reth_v_addr(m_roce_final_arb_reth_v_addr),
        .m_roce_reth_r_key (m_roce_final_arb_reth_r_key),
        .m_roce_reth_length(m_roce_final_arb_reth_length),
        .m_roce_immdh_valid(m_roce_final_arb_immdh_valid),
        .m_roce_immdh_ready(m_roce_final_arb_immdh_ready),
        .m_roce_immdh_data (m_roce_final_arb_immdh_data),
        .m_ip_dest_ip      (m_roce_final_arb_ip_dest_ip),
        .m_udp_source_port (),
        .m_udp_length      (m_roce_final_arb_udp_length),

        .m_roce_payload_axis_tdata (m_roce_final_arb_payload_axis_tdata ),
        .m_roce_payload_axis_tkeep (m_roce_final_arb_payload_axis_tkeep ),
        .m_roce_payload_axis_tvalid(m_roce_final_arb_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_final_arb_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_final_arb_payload_axis_tlast ),
        .m_roce_payload_axis_tuser (m_roce_final_arb_payload_axis_tuser )
    );

    generate
        if (DEBUG) begin
            //Histo params
            localparam HISTO_DEPTH = 4096;

            reg [3 :0] latency_inst_valid_pipes;
            reg [31:0] latency_inst_pipes [3:0];

            reg  [23:0]                    monitor_loc_qpn_del;
            wire                           histo_dout_valid;
            wire [23:0]                    histo_latency;
            wire [$clog2(HISTO_DEPTH)-1:0] histo_index;
            wire                           rst_done_latency;

            reg [32 : 0] read_histo_counter;

            always @(posedge clk_roce_eng) begin
                if (rst_roce_eng) begin
                    latency_inst_valid_pipes <= 'd0;
                    for (m = 0; m < 4; m++) begin
                        latency_inst_pipes[m] <= 'd0;
                    end
                    read_histo_counter <= 'd0;
                end else begin
                    read_histo_counter       <= read_histo_counter + 1;
                    latency_inst_valid_pipes <= {latency_inst_valid_pipes[2:0], latency_inst_valid_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]]};
                    latency_inst_pipes       <= {latency_inst_pipes[2:0]      , latency_inst_tx_eng[monitor_loc_qpn_cdc[QP_WIDTH-1 -: SEL_WIDTH]]};
                    monitor_loc_qpn_del      <= monitor_loc_qpn_cdc;
                end
            end



            // Histogramm
            histogrammer #(
                .BRAM_SIZE       (HISTO_DEPTH),
                .INPUT_DATA_WIDTH(32),
                .HISTO_DATA_WIDTH(24),
                .INPUT_VALUE_LSB (4) // granularity of CLOCK_PERIOD * 2**INPUT_VALUE_LSB, e.g. clock period = 3.3 ns and value of 4 will give you ~0.05us
            ) latency_histogrammer_instance (
                .clk     (clk_roce_eng),
                .rst     (rst_roce_eng || monitor_loc_qpn_del != monitor_loc_qpn_cdc), // reset when changing monitor qpn
                .valid   (latency_inst_valid_pipes[3]),
                .data_in (latency_inst_pipes[3]),
                .trigger_read_mem  (read_histo_counter == 33'h1ffff_ffff), // every ~ 26 s
                .histo_dout_valid  (histo_dout_valid),
                .histo_index_out   (histo_index),
                .histo_dout        (histo_latency),
                .rst_done(rst_done_latency)
            );

            ila_latency_distrib ila_latency_distrib_instance(
                .clk(clk_roce_eng),
                .probe0(histo_latency),
                .probe1(histo_index),
                .probe2(histo_dout_valid)
            );
        end
    endgenerate


endmodule

`resetall
