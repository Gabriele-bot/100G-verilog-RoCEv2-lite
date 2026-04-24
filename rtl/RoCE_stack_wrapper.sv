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
    parameter REFRESH_CACHE_TICKS              = 32767,
    parameter RETRANSMISSION                   = 1,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 24,
    parameter N_QUEUE_PAIRS                    = 2
) (
    input wire clk,
    input wire rst,

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
    input wire         m_qp_context_spy,
    input wire [23:0]  m_qp_local_qpn_spy,
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
    input  wire [ 15:0] RoCE_udp_port,
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
    output wire [31:0] transfer_time_inst,
    output wire [31:0] latency_avg,
    output wire [31:0] latency_moving_avg,
    output wire [31:0] latency_inst,

    output wire [23:0]                                  psn_diff,
    output wire [31:0]                                  n_retransmit_triggers,
    output wire [31:0]                                  n_rnr_retransmit_triggers

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

    reg        cm_qp_valid_pipe;
    reg [2 :0] cm_qp_req_type_pipe;
    reg [31:0] cm_qp_dma_transfer_length_pipe;
    reg [23:0] cm_qp_rem_qpn_pipe;
    reg [23:0] cm_qp_loc_qpn_pipe;
    reg [23:0] cm_qp_rem_psn_pipe;
    reg [23:0] cm_qp_loc_psn_pipe;
    reg [31:0] cm_qp_r_key_pipe;
    reg [63:0] cm_qp_rem_addr_pipe;
    reg [31:0] cm_qp_rem_ip_addr_pipe;
    reg        qp_is_immediate_pipe;
    reg        qp_tx_type_pipe;

    wire cm_qp_status_valid;
    wire [1:0] cm_qp_status;

    wire        txmeta_valid;
    wire        txmeta_start_transfer;
    wire [23:0] txmeta_loc_qpn;
    wire        txmeta_is_immediate;
    wire        txmeta_tx_type;
    wire [31:0] txmeta_dma_transfer;
    wire [31:0] txmeta_n_transfers;
    wire [31:0] txmeta_frequency;

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

    wire [OUT_DATA_WIDTH-1 :0]     m_roce_retrans_payload_axis_tdata;
    wire [OUT_KEEP_WIDTH-1 :0]     m_roce_retrans_payload_axis_tkeep;
    wire                           m_roce_retrans_payload_axis_tvalid;
    wire                           m_roce_retrans_payload_axis_tready;
    wire                           m_roce_retrans_payload_axis_tlast;
    wire                           m_roce_retrans_payload_axis_tuser;

    wire latency_inst_valid;

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

    integer m;

    // redirect udp rx traffic either to CM or RoCE RX

    reg s_select_cm_reg   = 1'b0;
    reg s_select_roce_reg = 1'b0;
    reg s_select_none_reg = 1'b0;

    wire s_select_cm   = s_udp_dest_port == CM_LISTEN_UDP_PORT ? 1'b1 : 1'b0;
    wire s_select_roce = s_udp_dest_port == ROCE_UDP_PORT      ? 1'b1 : 1'b0;
    wire s_select_none = !(s_select_cm || s_select_roce);


    always @(posedge clk) begin
        if (rst) begin
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

    wire        rx_roce_acks_bth_valid;
    wire        rx_roce_acks_bth_ready;
    wire [7:0]  rx_roce_acks_bth_op_code;
    wire [15:0] rx_roce_acks_bth_p_key;
    wire [23:0] rx_roce_acks_bth_psn;
    wire [23:0] rx_roce_acks_bth_dest_qp;
    wire        rx_roce_acks_bth_ack_req;
    wire        rx_roce_acks_aeth_valid;
    wire        rx_roce_acks_aeth_ready;
    wire [7:0]  rx_roce_acks_aeth_syndrome;
    wire [23:0] rx_roce_acks_aeth_msn;

    wire        rx_roce_acks_reg_bth_valid;
    wire        rx_roce_acks_reg_bth_ready;
    wire [7:0]  rx_roce_acks_reg_bth_op_code;
    wire [15:0] rx_roce_acks_reg_bth_p_key;
    wire [23:0] rx_roce_acks_reg_bth_psn;
    wire [23:0] rx_roce_acks_reg_bth_dest_qp;
    wire        rx_roce_acks_reg_bth_ack_req;
    wire        rx_roce_acks_reg_aeth_valid;
    wire        rx_roce_acks_reg_aeth_ready;
    wire [7:0]  rx_roce_acks_reg_aeth_syndrome;
    wire [23:0] rx_roce_acks_reg_aeth_msn;

    wire                 s_rx_roce_acks_reg_bth_valid;
    wire                 s_rx_roce_acks_reg_bth_ready;
    wire roce_bth_hdr_t  s_rx_roce_acks_reg_bth;
    wire                 s_rx_roce_acks_reg_aeth_valid;
    wire                 s_rx_roce_acks_reg_aeth_ready;
    wire roce_aeth_hdr_t s_rx_roce_acks_reg_aeth;

    wire                 m_rx_roce_acks_reg_bth_valid;
    wire                 m_rx_roce_acks_reg_bth_ready;
    wire roce_bth_hdr_t  m_rx_roce_acks_reg_bth;
    wire                 m_rx_roce_acks_reg_aeth_valid;
    wire                 m_rx_roce_acks_reg_aeth_ready;
    wire roce_aeth_hdr_t m_rx_roce_acks_reg_aeth;

    // QP state module

    // request arbiter

    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_context_arb_req_ready;
    wire [N_QUEUE_PAIRS*24-1:0] qp_local_qpn_arb_req;


    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_valid;
    wire [N_QUEUE_PAIRS-1:0]    qp_update_context_arb_ready;
    wire [N_QUEUE_PAIRS*48-1:0] qp_update_context_loc_qpn_rem_psn_arb;

    wire          m_qp_update_context_valid;
    wire          m_qp_update_context_ready;
    wire [24-1:0] m_qp_update_context_loc_qpn;
    wire [24-1:0] m_qp_update_context_rem_psn;

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

    /*
    AXI CROSSBAR IN INTERFACE
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

    // pipe cm_qp_output
    always @(posedge clk) begin
        cm_qp_valid_pipe <= cm_qp_valid;
        cm_qp_req_type_pipe <= cm_qp_req_type;
        cm_qp_dma_transfer_length_pipe <= cm_qp_dma_transfer_length;
        cm_qp_rem_qpn_pipe <= cm_qp_rem_qpn;
        cm_qp_loc_qpn_pipe <= cm_qp_loc_qpn;
        cm_qp_rem_psn_pipe <= cm_qp_rem_psn;
        cm_qp_loc_psn_pipe <= cm_qp_loc_psn;
        cm_qp_r_key_pipe <= cm_qp_r_key;
        cm_qp_rem_addr_pipe <= cm_qp_rem_addr;
        cm_qp_rem_ip_addr_pipe <= cm_qp_rem_ip_addr;
        qp_is_immediate_pipe <= qp_is_immediate;
        qp_tx_type_pipe <= qp_tx_type;
    end


    // Connection manager
    udp_RoCE_connection_manager #(
        .DATA_WIDTH     (OUT_DATA_WIDTH),
        .MODULE_DIRECTION("Slave"),
        .MASTER_TIMEOUT(1*10**8)
    ) udp_RoCE_connection_manager_instance (
        .clk(clk),
        .rst(rst),

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

    RoCE_qp_state_module #(
        .REM_ADDR_WIDTH(16)
    ) RoCE_qp_state_module_instance (
        .clk                    (clk),
        .rst                    (rst),
        .rst_qp                 (1'b0),
        // open qp
        .cm_qp_valid          (cm_qp_valid_pipe),
        .cm_qp_req_type       (cm_qp_req_type_pipe),
        .cm_qp_r_key          (cm_qp_r_key_pipe),
        .cm_qp_rem_qpn        (cm_qp_rem_qpn_pipe),
        .cm_qp_loc_qpn        (cm_qp_loc_qpn_pipe),
        .cm_qp_rem_psn        (cm_qp_rem_psn_pipe),
        .cm_qp_loc_psn        (cm_qp_loc_psn_pipe),
        .cm_qp_rem_ip_addr    (cm_qp_rem_ip_addr_pipe),
        .cm_qp_rem_addr       (cm_qp_rem_addr_pipe),
        //open status
        .cm_qp_status_valid(cm_qp_status_valid),
        .cm_qp_status(cm_qp_status),
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
        .qp_context_spy         (m_qp_context_spy),
        .qp_local_qpn_spy       (m_qp_local_qpn_spy),
        .qp_spy_context_valid   (s_qp_spy_context_valid),
        .qp_spy_state           (s_qp_spy_state),
        .qp_spy_r_key           (s_qp_spy_r_key),
        .qp_spy_rem_qpn         (s_qp_spy_rem_qpn),
        .qp_spy_loc_qpn         (s_qp_spy_loc_qpn),
        .qp_spy_rem_psn         (s_qp_spy_rem_psn),
        .qp_spy_rem_acked_psn   (s_qp_spy_rem_acked_psn),
        .qp_spy_loc_psn         (s_qp_spy_loc_psn),
        .qp_spy_rem_ip_addr     (s_qp_spy_rem_ip_addr),
        .qp_spy_rem_addr        (s_qp_spy_rem_addr),
        .qp_spy_syndrome        (s_qp_spy_syndrome),

        .s_qp_update_context_valid(m_qp_update_context_valid),
        .s_qp_update_context_ready(m_qp_update_context_ready),
        .s_qp_update_loc_qpn      (m_qp_update_context_loc_qpn),
        .s_qp_update_rem_psn      (m_qp_update_context_rem_psn),

        .s_roce_rx_bth_valid    (rx_roce_acks_reg_bth_valid && rx_roce_acks_reg_bth_ready),
        //.s_roce_rx_bth_ready    (rx_roce_acks_reg_bth_ready),
        .s_roce_rx_bth_op_code  (rx_roce_acks_reg_bth_op_code),
        .s_roce_rx_bth_p_key    (rx_roce_acks_reg_bth_p_key),
        .s_roce_rx_bth_psn      (rx_roce_acks_reg_bth_psn),
        .s_roce_rx_bth_dest_qp  (rx_roce_acks_reg_bth_dest_qp),
        .s_roce_rx_bth_ack_req  (rx_roce_acks_reg_bth_ack_req),
        .s_roce_rx_aeth_valid   (rx_roce_acks_reg_aeth_valid && rx_roce_acks_reg_aeth_ready),
        //.s_roce_rx_aeth_ready   (rx_roce_acks_reg_aeth_ready),
        .s_roce_rx_aeth_syndrome(rx_roce_acks_reg_aeth_syndrome),
        .s_roce_rx_aeth_msn     (rx_roce_acks_reg_aeth_msn),

        .last_acked_psn         (),
        .stop_transfer          (),
        .pmtu(pmtu)
    );


    // RX path

    RoCE_udp_rx_acks #(
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .ENABLE_ICRC_CHECK(1'b0)
    ) RoCE_udp_rx_instance (
        .clk(clk),
        .rst(rst),
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
        .m_roce_aeth_ready             (rx_roce_acks_bth_ready), //same as aeth actually
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

    //RX acks register
    assign s_rx_roce_acks_reg_bth_valid       = rx_roce_acks_bth_valid;
    assign s_rx_roce_acks_reg_bth.op_code     = rx_roce_acks_bth_op_code;
    assign s_rx_roce_acks_reg_bth.p_key       = rx_roce_acks_bth_p_key;
    assign s_rx_roce_acks_reg_bth.psn         = rx_roce_acks_bth_psn;
    assign s_rx_roce_acks_reg_bth.qp_number   = rx_roce_acks_bth_dest_qp;
    assign s_rx_roce_acks_reg_bth.ack_request = rx_roce_acks_bth_ack_req;

    assign s_rx_roce_acks_reg_aeth_valid    = rx_roce_acks_bth_valid;
    assign s_rx_roce_acks_reg_aeth.msn      = rx_roce_acks_aeth_msn;
    assign s_rx_roce_acks_reg_aeth.syndrome = rx_roce_acks_aeth_syndrome;

    assign m_rx_roce_acks_reg_bth_ready = rx_roce_acks_reg_bth_ready;

    axis_pipeline_register #(
        .DATA_WIDTH((12+4)*8), // BTH+AETH
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .LAST_ENABLE(0),
        .REG_TYPE(2),
        .LENGTH(3)
    ) rx_roce_acks_axis_registers (
        .clk(clk),
        .rst(rst),


        .s_axis_tdata ({s_rx_roce_acks_reg_bth, s_rx_roce_acks_reg_aeth}),
        .s_axis_tkeep (0),
        .s_axis_tvalid(s_rx_roce_acks_reg_bth_valid),
        .s_axis_tready(rx_roce_acks_bth_ready),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (0),

        // AXI output
        .m_axis_tdata ({m_rx_roce_acks_reg_bth, m_rx_roce_acks_reg_aeth}),
        .m_axis_tkeep (),
        .m_axis_tvalid(m_rx_roce_acks_reg_bth_valid),
        .m_axis_tready(m_rx_roce_acks_reg_bth_ready),
        .m_axis_tlast (),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ()
    );

    assign rx_roce_acks_reg_bth_valid   = m_rx_roce_acks_reg_bth_valid      ;
    assign rx_roce_acks_reg_bth_op_code = m_rx_roce_acks_reg_bth.op_code    ;
    assign rx_roce_acks_reg_bth_p_key   = m_rx_roce_acks_reg_bth.p_key      ;
    assign rx_roce_acks_reg_bth_psn     = m_rx_roce_acks_reg_bth.psn        ;
    assign rx_roce_acks_reg_bth_dest_qp = m_rx_roce_acks_reg_bth.qp_number  ;
    assign rx_roce_acks_reg_bth_ack_req = m_rx_roce_acks_reg_bth.ack_request;

    assign rx_roce_acks_reg_aeth_valid    = m_rx_roce_acks_reg_bth_valid    ;
    assign rx_roce_acks_reg_aeth_msn      = m_rx_roce_acks_reg_aeth.msn     ;
    assign rx_roce_acks_reg_aeth_syndrome = m_rx_roce_acks_reg_aeth.syndrome;


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

            wire wr_error_qp_not_rts;
            wire [23:0] wr_error_loc_qpn;

            wire rst_tx_engine = cm_qp_valid_pipe && cm_qp_loc_qpn_pipe == (256+i) && cm_qp_req_type_pipe == REQ_OPEN_QP;
            wire stop_data_gen = cm_qp_valid_pipe && cm_qp_loc_qpn_pipe == (256+i) && cm_qp_req_type_pipe == REQ_CLOSE_QP;



            RoCE_data_generator #(
                .DATA_WIDTH(QP_CH_DATA_WIDTH)
            ) RoCE_data_generator_instance (
                .clk(clk),
                .rst(rst_tx_engine),

                .rst_word_ctr(rst_tx_engine),

                .stop(stop_transfer && en_retrans || wr_error_qp_not_rts || stop_data_gen),

                .txmeta_valid           (txmeta_valid && txmeta_loc_qpn==(256+i)),
                .txmeta_start_transfer  (txmeta_start_transfer),
                .txmeta_loc_qpn         (txmeta_loc_qpn),
                .txmeta_is_immediate    (txmeta_is_immediate),
                .txmeta_tx_type         (txmeta_tx_type),
                .txmeta_dma_transfer    (txmeta_dma_transfer),
                .txmeta_n_transfers     (txmeta_n_transfers),
                .txmeta_frequency       (txmeta_frequency),

                .m_wr_req_valid         (m_wr_req_data_gen_valid),
                .m_wr_req_ready         (m_wr_req_data_gen_ready),
                .m_wr_req_tx_type       (m_wr_req_data_gen_tx_type),
                .m_wr_req_is_immediate  (m_wr_req_data_gen_is_immediate),
                .m_wr_req_immediate_data(m_wr_req_data_gen_immediate_data),
                .m_wr_req_loc_qp        (m_wr_req_data_gen_loc_qp),
                .m_wr_req_addr_offset   (m_wr_req_data_gen_addr_offset),
                .m_wr_req_dma_length    (m_wr_req_data_gen_dma_length),

                .m_axis_tdata           (m_axis_data_gen_tdata),
                .m_axis_tkeep           (m_axis_data_gen_tkeep),
                .m_axis_tvalid          (m_axis_data_gen_tvalid),
                .m_axis_tready          (m_axis_data_gen_tready),
                .m_axis_tlast           (m_axis_data_gen_tlast),
                .m_axis_tuser           (m_axis_data_gen_tuser),

                .wr_error_qp_not_rts(wr_error_qp_not_rts),
                .wr_error_loc_qpn   (wr_error_loc_qpn)
            );

            RoCE_tx_queue #(
                .DATA_WIDTH(QP_CH_DATA_WIDTH),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .LOCAL_QPN(256+i),
                .REFRESH_CACHE_TICKS(REFRESH_CACHE_TICKS)
            ) RoCE_tx_queue_instance (
                .clk(clk),
                .rst(rst | rst_tx_engine),

                /*
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
                */
                .s_wr_req_valid            (m_wr_req_data_gen_valid),
                .s_wr_req_ready            (m_wr_req_data_gen_ready),
                .s_wr_req_tx_type          (m_wr_req_data_gen_tx_type),
                .s_wr_req_is_immediate     (m_wr_req_data_gen_is_immediate),
                .s_wr_req_immediate_data   (m_wr_req_data_gen_immediate_data),
                .s_wr_req_loc_qp           (m_wr_req_data_gen_loc_qp),
                .s_wr_req_addr_offset      (m_wr_req_data_gen_addr_offset),
                .s_wr_req_dma_length       (m_wr_req_data_gen_dma_length),
                .s_payload_axis_tdata      (m_axis_data_gen_tdata),
                .s_payload_axis_tkeep      (m_axis_data_gen_tkeep),
                .s_payload_axis_tvalid     (m_axis_data_gen_tvalid),
                .s_payload_axis_tready     (m_axis_data_gen_tready),
                .s_payload_axis_tlast      (m_axis_data_gen_tlast),
                .s_payload_axis_tuser      (m_axis_data_gen_tuser),

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

                .wr_error_qp_not_rts_out  (wr_error_qp_not_rts),
                .wr_error_loc_qpn_out     (wr_error_loc_qpn),

                // initialize module with qp parameteres (from CM)
                .cm_qp_valid              (cm_qp_valid_pipe && cm_qp_loc_qpn_pipe == (256+i)),
                .cm_qp_req_type           (cm_qp_req_type_pipe),
                .cm_qp_dma_transfer_length(cm_qp_dma_transfer_length_pipe),
                .cm_qp_rem_qpn            (cm_qp_rem_qpn_pipe),
                .cm_qp_loc_qpn            (cm_qp_loc_qpn_pipe),
                .cm_qp_rem_psn            (cm_qp_rem_psn_pipe),
                .cm_qp_loc_psn            (cm_qp_loc_psn_pipe),
                .cm_qp_r_key              (cm_qp_r_key_pipe),
                .cm_qp_rem_addr           (cm_qp_rem_addr_pipe),
                .cm_qp_rem_ip_addr        (cm_qp_rem_ip_addr_pipe),

                .qp_is_immediate(qp_is_immediate_pipe),
                .qp_tx_type     (qp_tx_type_pipe),

                // request to qp state
                .m_qp_context_req_valid(qp_context_arb_req_valid[i]),
                .m_qp_context_req_ready(qp_context_arb_req_ready[i]),
                .m_qp_local_qpn_req(qp_local_qpn_arb_req[24*i +: 24]),
                // reply from qp state
                .s_qp_req_context_valid(s_qp_context_req_valid && s_qp_context_req_loc_qpn == (256+i)),
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
                .RoCE_udp_port(RoCE_udp_port),
                .loc_ip_addr(loc_ip_addr)
            );

            RoCE_realign_frame_fifo #(
                .S_DATA_WIDTH(QP_CH_DATA_WIDTH),
                .M_DATA_WIDTH(OUT_DATA_WIDTH),
                .HAS_ADAPTER(1),
                .FIFO_DEPTH(4200)
            ) RoCE_realign_frame_fifo_instance (
                .clk(clk),
                .rst(rst | rst_tx_engine),
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
                .s_ip_source_ip      (roce_tx_eng_ip_src_ip),
                .s_ip_dest_ip        (roce_tx_eng_ip_dest_ip),
                .s_udp_source_port   (roce_tx_eng_udp_src_port),
                .s_udp_dest_port     (roce_tx_eng_udp_dest_port),
                .s_udp_length        (roce_tx_eng_udp_length),
                .s_udp_checksum      (roce_tx_eng_udp_checksum),

                .s_roce_payload_axis_tdata (roce_tx_eng_payload_axis_tdata),
                .s_roce_payload_axis_tkeep (roce_tx_eng_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid(roce_tx_eng_payload_axis_tvalid),
                .s_roce_payload_axis_tready(roce_tx_eng_payload_axis_tready),
                .s_roce_payload_axis_tlast (roce_tx_eng_payload_axis_tlast),
                .s_roce_payload_axis_tuser (roce_tx_eng_payload_axis_tuser),

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

                .stall(stall_qp[i])
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
        .DATA_WIDTH       (OUT_DATA_WIDTH),
        .BUFFER_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH), // total buffer, all QPs
        .MAX_QPS          (N_QUEUE_PAIRS),
        .CLOCK_PERIOD     (CLOCK_PERIOD),
        .AXI_FIFO_DEPTH   (4)
    ) RoCE_retransmission_module_v2_instance (
        .clk(clk),
        .rst(rst),
        .flow_ctrl_pause(flow_ctrl_pause),
        .s_roce_rx_bth_valid         (rx_roce_acks_reg_bth_valid),
        .s_roce_rx_bth_ready         (rx_roce_acks_reg_bth_ready),
        .s_roce_rx_bth_psn           (rx_roce_acks_reg_bth_psn),
        .s_roce_rx_bth_op_code       (rx_roce_acks_reg_bth_op_code),
        .s_roce_rx_bth_dest_qp       (rx_roce_acks_reg_bth_dest_qp),
        .s_roce_rx_aeth_valid        (rx_roce_acks_reg_aeth_valid),
        .s_roce_rx_aeth_ready        (rx_roce_acks_reg_aeth_ready),
        .s_roce_rx_aeth_syndrome     (rx_roce_acks_reg_aeth_syndrome),
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
        .s_ip_source_ip      (loc_ip_addr),
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
        .m_udp_source_port   (m_roce_retrans_udp_src_port),
        .m_udp_dest_port     (m_roce_retrans_udp_dest_port),
        .m_udp_length        (m_roce_retrans_udp_length),
        .m_udp_checksum      (m_roce_retrans_udp_checksum),

        .m_roce_payload_axis_tdata (m_roce_retrans_payload_axis_tdata),
        .m_roce_payload_axis_tkeep (m_roce_retrans_payload_axis_tkeep),
        .m_roce_payload_axis_tvalid(m_roce_retrans_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_retrans_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_retrans_payload_axis_tlast),
        .m_roce_payload_axis_tuser (m_roce_retrans_payload_axis_tuser),

        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),


        .cm_qp_valid(cm_qp_valid_pipe),
        .cm_qp_req_type(cm_qp_req_type_pipe),
        .cm_qp_dma_transfer_length(cm_qp_dma_transfer_length_pipe),
        .cm_qp_rem_qpn(cm_qp_rem_qpn_pipe),
        .cm_qp_loc_qpn(cm_qp_loc_qpn_pipe),
        .cm_qp_rem_psn(cm_qp_rem_psn_pipe),
        .cm_qp_loc_psn(cm_qp_loc_psn_pipe),
        .cm_qp_r_key(cm_qp_r_key_pipe),
        .cm_qp_rem_addr(cm_qp_rem_addr_pipe),
        .cm_qp_rem_ip_addr(cm_qp_rem_ip_addr_pipe),
        .qp_is_immediate(qp_is_immediate_pipe),
        .qp_tx_type(qp_tx_type_pipe),

        .m_qp_close_valid(m_qp_close_valid),
        .m_qp_close_ready(m_qp_close_ready),
        .m_qp_close_loc_qpn(m_qp_close_loc_qpn),
        .m_qp_close_rem_psn(m_qp_close_rem_psn),

        .stall_qp                 (stall_qp),

        .cfg_valid                (1),
        .timeout_period           (timeout_period),
        .retry_count              (retry_count),
        .rnr_retry_count          (rnr_retry_count),
        .loc_ip_addr              (loc_ip_addr),
        .pmtu                     (pmtu),

        .monitor_qpn              (monitor_loc_qpn),
        .n_retransmit_triggers    (n_retransmit_triggers),
        .n_rnr_retransmit_triggers(n_rnr_retransmit_triggers),
        .psn_diff                 (psn_diff)
    );

    axi_crossbar #(
        .S_COUNT        (1),
        .M_COUNT        (N_AXI_RAM),
        .DATA_WIDTH     (OUT_DATA_WIDTH),
        .ADDR_WIDTH     (RETRANSMISSION_ADDR_BUFFER_WIDTH),
        .STRB_WIDTH     (OUT_KEEP_WIDTH),
        .S_ID_WIDTH     (1),
        .M_REGIONS      (1),
        .M_BASE_ADDR    (0),
        .M_ADDR_WIDTH   ({N_AXI_RAM{INTERCONNECT_ADDR_WIDTH}})
    ) axi_ram_xbar_instance (
        .clk(clk),
        .rst(rst),
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

        .m_axi_awid   (m_axi_interconnect_awid),
        .m_axi_awaddr (m_axi_interconnect_awaddr),
        .m_axi_awlen  (m_axi_interconnect_awlen),
        .m_axi_awsize (m_axi_interconnect_awsize),
        .m_axi_awburst(m_axi_interconnect_awburst),
        .m_axi_awlock (m_axi_interconnect_awlock),
        .m_axi_awcache(m_axi_interconnect_awcache),
        .m_axi_awprot (m_axi_interconnect_awprot),
        .m_axi_awvalid(m_axi_interconnect_awvalid),
        .m_axi_awready(m_axi_interconnect_awready),
        .m_axi_wdata  (m_axi_interconnect_wdata),
        .m_axi_wstrb  (m_axi_interconnect_wstrb),
        .m_axi_wlast  (m_axi_interconnect_wlast),
        .m_axi_wvalid (m_axi_interconnect_wvalid),
        .m_axi_wready (m_axi_interconnect_wready),
        .m_axi_bid    (m_axi_interconnect_bid),
        .m_axi_bresp  (m_axi_interconnect_bresp),
        .m_axi_bvalid (m_axi_interconnect_bvalid),
        .m_axi_bready (m_axi_interconnect_bready),
        .m_axi_arid   (m_axi_interconnect_arid),
        .m_axi_araddr (m_axi_interconnect_araddr),
        .m_axi_arlen  (m_axi_interconnect_arlen),
        .m_axi_arsize (m_axi_interconnect_arsize),
        .m_axi_arburst(m_axi_interconnect_arburst),
        .m_axi_arlock (m_axi_interconnect_arlock),
        .m_axi_arcache(m_axi_interconnect_arcache),
        .m_axi_arprot (m_axi_interconnect_arprot),
        .m_axi_arvalid(m_axi_interconnect_arvalid),
        .m_axi_arready(m_axi_interconnect_arready),
        .m_axi_rid    (m_axi_interconnect_rid),
        .m_axi_rdata  (m_axi_interconnect_rdata),
        .m_axi_rresp  (m_axi_interconnect_rresp),
        .m_axi_rlast  (m_axi_interconnect_rlast),
        .m_axi_rvalid (m_axi_interconnect_rvalid),
        .m_axi_rready (m_axi_interconnect_rready)
    );

    generate
        genvar j;
        for (j =0; j < N_AXI_RAM; j++) begin
            /*
            AXI CROSSBAR INTERFACE
            */
            wire [0                :0]                  m_axi_ram_awid;
            wire [INTERCONNECT_ADDR_WIDTH-1:0]          m_axi_ram_awaddr;
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
            wire [INTERCONNECT_ADDR_WIDTH-1:0]          m_axi_ram_araddr;
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

            axi_register #(
                .DATA_WIDTH(OUT_DATA_WIDTH),
                .ADDR_WIDTH(INTERCONNECT_ADDR_WIDTH),
                .STRB_WIDTH(OUT_KEEP_WIDTH),
                .ID_WIDTH(1)
            ) axi_register_ram_instance (
                .clk(clk),
                .rst(rst),
                .s_axi_awid   (m_axi_interconnect_awid[j]),
                .s_axi_awaddr (m_axi_interconnect_awaddr[j*INTERCONNECT_ADDR_WIDTH+:INTERCONNECT_ADDR_WIDTH]),
                .s_axi_awlen  (m_axi_interconnect_awlen[j*8+:8]),
                .s_axi_awsize (m_axi_interconnect_awsize[j*3+:3]),
                .s_axi_awburst(m_axi_interconnect_awburst[j*2+:2]),
                .s_axi_awlock (m_axi_interconnect_awlock[j]),
                .s_axi_awcache(m_axi_interconnect_awcache[j*4+:4]),
                .s_axi_awprot (m_axi_interconnect_awprot[j*3+:3]),
                .s_axi_awvalid(m_axi_interconnect_awvalid[j]),
                .s_axi_awready(m_axi_interconnect_awready[j]),
                .s_axi_wdata  (m_axi_interconnect_wdata[j*OUT_DATA_WIDTH+:OUT_DATA_WIDTH]),
                .s_axi_wstrb  (m_axi_interconnect_wstrb[j*OUT_KEEP_WIDTH+:OUT_KEEP_WIDTH]),
                .s_axi_wlast  (m_axi_interconnect_wlast[j]),
                .s_axi_wvalid (m_axi_interconnect_wvalid[j]),
                .s_axi_wready (m_axi_interconnect_wready[j]),
                .s_axi_bid    (m_axi_interconnect_bid[j]),
                .s_axi_bresp  (m_axi_interconnect_bresp[j*2+:2]),
                .s_axi_bvalid (m_axi_interconnect_bvalid[j]),
                .s_axi_bready (m_axi_interconnect_bready[j]),
                .s_axi_arid   (m_axi_interconnect_arid[j]),
                .s_axi_araddr (m_axi_interconnect_araddr[j*INTERCONNECT_ADDR_WIDTH+:INTERCONNECT_ADDR_WIDTH]),
                .s_axi_arlen  (m_axi_interconnect_arlen[j*8+:8]),
                .s_axi_arsize (m_axi_interconnect_arsize[j*3+:3]),
                .s_axi_arburst(m_axi_interconnect_arburst[j*2+:2]),
                .s_axi_arlock (m_axi_interconnect_arlock[j]),
                .s_axi_arcache(m_axi_interconnect_arcache[j*4+:4]),
                .s_axi_arprot (m_axi_interconnect_arprot[j*3+:3]),
                .s_axi_arvalid(m_axi_interconnect_arvalid[j]),
                .s_axi_arready(m_axi_interconnect_arready[j]),
                .s_axi_rid    (m_axi_interconnect_rid[j]),
                .s_axi_rdata  (m_axi_interconnect_rdata[j*OUT_DATA_WIDTH+:OUT_DATA_WIDTH]),
                .s_axi_rresp  (m_axi_interconnect_rresp[j*2+:2]),
                .s_axi_rlast  (m_axi_interconnect_rlast[j]),
                .s_axi_rvalid (m_axi_interconnect_rvalid[j]),
                .s_axi_rready (m_axi_interconnect_rready[j]),

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
                .ADDR_WIDTH(INTERCONNECT_ADDR_WIDTH),
                .STRB_WIDTH(OUT_KEEP_WIDTH),
                .ID_WIDTH(1),
                .READ_LATENCY(4)
            ) RoCE_axi_buffer_instance (
                .clk(clk),
                .rst(rst),

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
        end
    endgenerate



    RoCE_udp_tx #(
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .MIG_REQ(1'b1),
        .FECN   (1'b0)
    ) RoCE_udp_tx_instance (
        .clk                            (clk),
        .rst                            (rst),
        .s_roce_bth_valid               (m_roce_retrans_bth_valid),
        .s_roce_bth_ready               (m_roce_retrans_bth_ready),
        .s_roce_bth_op_code             (m_roce_retrans_bth_op_code),
        .s_roce_bth_p_key               (m_roce_retrans_bth_p_key),
        .s_roce_bth_psn                 (m_roce_retrans_bth_psn),
        .s_roce_bth_dest_qp             (m_roce_retrans_bth_dest_qp),
        .s_roce_bth_ack_req             (m_roce_retrans_bth_ack_req),
        .s_roce_reth_valid              (m_roce_retrans_reth_valid),
        .s_roce_reth_ready              (m_roce_retrans_reth_ready),
        .s_roce_reth_v_addr             (m_roce_retrans_reth_v_addr),
        .s_roce_reth_r_key              (m_roce_retrans_reth_r_key),
        .s_roce_reth_length             (m_roce_retrans_reth_length),
        .s_roce_immdh_valid             (m_roce_retrans_immdh_valid),
        .s_roce_immdh_ready             (m_roce_retrans_immdh_ready),
        .s_roce_immdh_data              (m_roce_retrans_immdh_data),
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
        .s_ip_dest_ip                   (m_roce_retrans_ip_dest_ip),
        .s_udp_source_port              (16'h8657),
        .s_udp_dest_port                (m_roce_retrans_udp_dest_port),
        .s_udp_length                   (m_roce_retrans_udp_length),
        .s_udp_checksum                 (m_roce_retrans_udp_checksum),
        .s_roce_payload_axis_tdata      (m_roce_retrans_payload_axis_tdata),
        .s_roce_payload_axis_tkeep      (m_roce_retrans_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid     (m_roce_retrans_payload_axis_tvalid),
        .s_roce_payload_axis_tready     (m_roce_retrans_payload_axis_tready),
        .s_roce_payload_axis_tlast      (m_roce_retrans_payload_axis_tlast),
        .s_roce_payload_axis_tuser      (m_roce_retrans_payload_axis_tuser),

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
        .RoCE_udp_port(RoCE_udp_port)
    );

    udp_arb_mux #(
        .S_COUNT(2),
        .DATA_WIDTH(OUT_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) udp_arb_mux_instance (
        .clk(clk),
        .rst(rst),
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
        .m_udp_payload_axis_tdest ()
    );


    RoCE_latency_eval RoCE_latency_eval_instance (
        .clk(clk),
        .rst(rst),
        .start_i                 (cm_qp_valid_pipe && cm_qp_req_type_pipe == REQ_OPEN_QP ),
        .s_roce_rx_bth_valid     (rx_roce_acks_reg_bth_valid && rx_roce_acks_reg_bth_ready),
        .s_roce_rx_bth_op_code   (rx_roce_acks_reg_bth_op_code),
        .s_roce_rx_bth_p_key     (rx_roce_acks_reg_bth_p_key),
        .s_roce_rx_bth_psn       (rx_roce_acks_reg_bth_psn),
        .s_roce_rx_bth_dest_qp   (rx_roce_acks_reg_bth_dest_qp),
        .s_roce_rx_bth_ack_req   (rx_roce_acks_reg_bth_ack_req),
        .s_roce_rx_aeth_valid    (rx_roce_acks_reg_aeth_valid && rx_roce_acks_reg_aeth_ready),
        .s_roce_rx_aeth_syndrome (rx_roce_acks_reg_aeth_syndrome),
        .s_roce_rx_aeth_msn      (rx_roce_acks_reg_aeth_msn),

        .s_roce_tx_bth_valid     (m_roce_retrans_bth_valid && m_roce_retrans_bth_ready),
        .s_roce_tx_bth_op_code   (m_roce_retrans_bth_op_code),
        .s_roce_tx_bth_p_key     (m_roce_retrans_bth_p_key),
        .s_roce_tx_bth_psn       (m_roce_retrans_bth_psn),
        .s_roce_tx_bth_dest_qp   (m_roce_retrans_bth_dest_qp),
        .s_roce_tx_bth_src_qp    (m_roce_retrans_bth_src_qp),
        .s_roce_tx_bth_ack_req   (m_roce_retrans_bth_ack_req),
        .s_axis_tx_payload_valid (m_roce_retrans_payload_axis_tvalid && m_roce_qp_arb_payload_axis_tready),
        .s_axis_tx_payload_last  (m_roce_retrans_payload_axis_tlast),
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


    always @(posedge clk) begin
        if (rst) begin
            latency_inst_valid_pipes <= 'd0;
            for (m = 0; m < 4; m++) begin
                latency_inst_pipes[m] <= 'd0;
            end
            read_histo_counter <= 'd0;
        end else begin
            read_histo_counter <= read_histo_counter + 1;
            latency_inst_valid_pipes <= {latency_inst_valid_pipes[2:0], latency_inst_valid};
            latency_inst_pipes       <= {latency_inst_pipes[2:0]      , latency_inst};
            monitor_loc_qpn_del <= monitor_loc_qpn;
        end
    end


    // Histogramm
    histogrammer #(
        .BRAM_SIZE       (HISTO_DEPTH),
        .INPUT_DATA_WIDTH(32),
        .HISTO_DATA_WIDTH(24),
        .INPUT_VALUE_LSB (4) // granularity of CLOCK_PERIOD * 2**INPUT_VALUE_LSB, e.g. clock period = 3.1 ns and value of 4 will give you ~0.05us
    ) latency_histogrammer_instance (
        .clk     (clk),
        .rst     (rst || monitor_loc_qpn_del != monitor_loc_qpn), // reset when changing monitor qpn
        .valid   (latency_inst_valid_pipes[3]),
        .data_in (latency_inst_pipes[3]),
        .trigger_read_mem  (read_histo_counter == 33'h1ffff_ffff), // every ~ 26 s
        .histo_dout_valid  (histo_dout_valid),
        .histo_index_out   (histo_index),
        .histo_dout        (histo_latency),
        .rst_done(rst_done_latency)
    );

    generate
        if (DEBUG) begin
            ila_latency_distrib ila_latency_distrib_instance(
                .clk(clk),
                .probe0(histo_latency),
                .probe1(histo_index),
                .probe2(histo_dout_valid)
            );
        end
    endgenerate





endmodule

`resetall
