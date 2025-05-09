
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_minimal_stack #(
    parameter DATA_WIDTH      = 256,
    parameter MAX_QUEUE_PAIRS = 4,
    parameter CLOCK_PERIOD    = 6.4, // in ns
    parameter DEBUG           = 0,
    parameter RETRANSMISSION  = 1,
    parameter RETRANSMISSION_ADDR_BUFFER_WIDTH = 24,
    parameter ENABLE_SIM_PACKET_DROP_TX = 0,
    parameter ENABLE_SIM_PACKET_DROP_RX = 0
) (
    input wire clk,
    input wire rst,

    /*
     * Configuration parameter
     
    input wire [31:0] dma_transfer_length,
    input wire [23:0] rem_qpn,
    input wire [23:0] rem_psn,
    input wire [31:0] r_key,
    input wire [63:0] rem_addr,
    input wire [31:0] rem_ip_addr,

    input wire start_transfer,
    */

    /*
     * UDP frame input
     */
    input  wire                        s_udp_hdr_valid,
    output wire                        s_udp_hdr_ready,
    input  wire [ 47:0]                s_eth_dest_mac,
    input  wire [ 47:0]                s_eth_src_mac,
    input  wire [ 15:0]                s_eth_type,
    input  wire [  3:0]                s_ip_version,
    input  wire [  3:0]                s_ip_ihl,
    input  wire [  5:0]                s_ip_dscp,
    input  wire [  1:0]                s_ip_ecn,
    input  wire [ 15:0]                s_ip_length,
    input  wire [ 15:0]                s_ip_identification,
    input  wire [  2:0]                s_ip_flags,
    input  wire [ 12:0]                s_ip_fragment_offset,
    input  wire [  7:0]                s_ip_ttl,
    input  wire [  7:0]                s_ip_protocol,
    input  wire [ 15:0]                s_ip_header_checksum,
    input  wire [ 31:0]                s_ip_source_ip,
    input  wire [ 31:0]                s_ip_dest_ip,
    input  wire [ 15:0]                s_udp_source_port,
    input  wire [ 15:0]                s_udp_dest_port,
    input  wire [ 15:0]                s_udp_length,
    input  wire [ 15:0]                s_udp_checksum,
    input  wire [ 31:0]                s_roce_computed_icrc,
    input  wire [DATA_WIDTH   - 1 : 0] s_udp_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 : 0] s_udp_payload_axis_tkeep,
    input  wire                        s_udp_payload_axis_tvalid,
    output wire                        s_udp_payload_axis_tready,
    input  wire                        s_udp_payload_axis_tlast,
    input  wire                        s_udp_payload_axis_tuser,

    /*
     * UDP frame output
     */
    output wire                         m_udp_hdr_valid,
    input  wire                         m_udp_hdr_ready,
    output wire [ 47:0]                 m_eth_dest_mac,
    output wire [ 47:0]                 m_eth_src_mac,
    output wire [ 15:0]                 m_eth_type,
    output wire [  3:0]                 m_ip_version,
    output wire [  3:0]                 m_ip_ihl,
    output wire [  5:0]                 m_ip_dscp,
    output wire [  1:0]                 m_ip_ecn,
    output wire [ 15:0]                 m_ip_length,
    output wire [ 15:0]                 m_ip_identification,
    output wire [  2:0]                 m_ip_flags,
    output wire [ 12:0]                 m_ip_fragment_offset,
    output wire [  7:0]                 m_ip_ttl,
    output wire [  7:0]                 m_ip_protocol,
    output wire [ 15:0]                 m_ip_header_checksum,
    output wire [ 31:0]                 m_ip_source_ip,
    output wire [ 31:0]                 m_ip_dest_ip,
    output wire [ 15:0]                 m_udp_source_port,
    output wire [ 15:0]                 m_udp_dest_port,
    output wire [ 15:0]                 m_udp_length,
    output wire [ 15:0]                 m_udp_checksum,
    output wire [DATA_WIDTH   - 1 : 0]  m_udp_payload_axis_tdata,
    output wire [DATA_WIDTH/8 - 1 : 0]  m_udp_payload_axis_tkeep,
    output wire                         m_udp_payload_axis_tvalid,
    input  wire                         m_udp_payload_axis_tready,
    output wire                         m_udp_payload_axis_tlast,
    output wire                         m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    output wire         error_payload_early_termination,
    /*
     * Configuration
     */
    input  wire [  2:0] pmtu,
    input  wire [ 15:0] RoCE_udp_port,
    input  wire [ 31:0] loc_ip_addr,
    input  wire [ 63:0] timeout_period,
    input  wire [ 2 :0] retry_count,
    input  wire [ 2 :0] rnr_retry_count

);

    import RoCE_params::*; // Imports RoCE parameters

    // UDP frame connections to CM                
    wire                        rx_udp_cm_hdr_valid;
    wire                        rx_udp_cm_hdr_ready;
    wire [15:0]                 rx_udp_cm_source_port;
    wire [15:0]                 rx_udp_cm_dest_port;
    wire [15:0]                 rx_udp_cm_length;
    wire [15:0]                 rx_udp_cm_checksum;
    wire [DATA_WIDTH   - 1 : 0] rx_udp_cm_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] rx_udp_cm_payload_axis_tkeep;
    wire                        rx_udp_cm_payload_axis_tvalid;
    wire                        rx_udp_cm_payload_axis_tready;
    wire                        rx_udp_cm_payload_axis_tlast;
    wire                        rx_udp_cm_payload_axis_tuser;

    wire                        tx_udp_cm_hdr_valid;
    wire                        tx_udp_cm_hdr_ready;
    wire [31:0]                 tx_udp_cm_ip_source_ip;
    wire [31:0]                 tx_udp_cm_ip_dest_ip;
    wire [15:0]                 tx_udp_cm_source_port;
    wire [15:0]                 tx_udp_cm_dest_port;
    wire [15:0]                 tx_udp_cm_length;
    wire [15:0]                 tx_udp_cm_checksum;
    wire [DATA_WIDTH   - 1 : 0] tx_udp_cm_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] tx_udp_cm_payload_axis_tkeep;
    wire                        tx_udp_cm_payload_axis_tvalid;
    wire                        tx_udp_cm_payload_axis_tready;
    wire                        tx_udp_cm_payload_axis_tlast;
    wire                        tx_udp_cm_payload_axis_tuser;

    wire                         roce_tx_udp_hdr_valid;
    wire                         roce_tx_udp_hdr_ready;
    wire [ 47:0]                 roce_tx_eth_dest_mac;
    wire [ 47:0]                 roce_tx_eth_src_mac;
    wire [ 15:0]                 roce_tx_eth_type;
    wire [  3:0]                 roce_tx_ip_version;
    wire [  3:0]                 roce_tx_ip_ihl;
    wire [  5:0]                 roce_tx_ip_dscp;
    wire [  1:0]                 roce_tx_ip_ecn;
    wire [ 15:0]                 roce_tx_ip_length;
    wire [ 15:0]                 roce_tx_ip_identification;
    wire [  2:0]                 roce_tx_ip_flags;
    wire [ 12:0]                 roce_tx_ip_fragment_offset;
    wire [  7:0]                 roce_tx_ip_ttl;
    wire [  7:0]                 roce_tx_ip_protocol;
    wire [ 15:0]                 roce_tx_ip_header_checksum;
    wire [ 31:0]                 roce_tx_ip_source_ip;
    wire [ 31:0]                 roce_tx_ip_dest_ip;
    wire [ 15:0]                 roce_tx_udp_source_port;
    wire [ 15:0]                 roce_tx_udp_dest_port;
    wire [ 15:0]                 roce_tx_udp_length;
    wire [ 15:0]                 roce_tx_udp_checksum;
    wire [DATA_WIDTH   - 1 : 0]  roce_tx_udp_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0]  roce_tx_udp_payload_axis_tkeep;
    wire                         roce_tx_udp_payload_axis_tvalid;
    wire                         roce_tx_udp_payload_axis_tready;
    wire                         roce_tx_udp_payload_axis_tlast;
    wire                         roce_tx_udp_payload_axis_tuser;

    // UDP frame connections to RoCE RX
    wire rx_udp_RoCE_hdr_valid;
    wire rx_udp_RoCE_hdr_ready;
    wire [47:0] rx_udp_RoCE_eth_dest_mac;
    wire [47:0] rx_udp_RoCE_eth_src_mac;
    wire [15:0] rx_udp_RoCE_eth_type;
    wire [3:0] rx_udp_RoCE_ip_version;
    wire [3:0] rx_udp_RoCE_ip_ihl;
    wire [5:0] rx_udp_RoCE_ip_dscp;
    wire [1:0] rx_udp_RoCE_ip_ecn;
    wire [15:0] rx_udp_RoCE_ip_length;
    wire [15:0] rx_udp_RoCE_ip_identification;
    wire [2:0] rx_udp_RoCE_ip_flags;
    wire [12:0] rx_udp_RoCE_ip_fragment_offset;
    wire [7:0] rx_udp_RoCE_ip_ttl;
    wire [7:0] rx_udp_RoCE_ip_protocol;
    wire [15:0] rx_udp_RoCE_ip_header_checksum;
    wire [31:0] rx_udp_RoCE_ip_source_ip;
    wire [31:0] rx_udp_RoCE_ip_dest_ip;
    wire [15:0] rx_udp_RoCE_source_port;
    wire [15:0] rx_udp_RoCE_dest_port;
    wire [15:0] rx_udp_RoCE_length;
    wire [15:0] rx_udp_RoCE_checksum;
    wire [DATA_WIDTH   - 1 : 0] rx_udp_RoCE_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] rx_udp_RoCE_payload_axis_tkeep;
    wire rx_udp_RoCE_payload_axis_tvalid;
    wire rx_udp_RoCE_payload_axis_tready;
    wire rx_udp_RoCE_payload_axis_tlast;
    wire rx_udp_RoCE_payload_axis_tuser;

    wire [DATA_WIDTH   - 1 : 0] s_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] s_payload_axis_tkeep;
    wire s_payload_axis_tvalid;
    wire s_payload_axis_tlast;
    wire s_payload_axis_tuser;
    wire s_payload_axis_tready;

    wire [DATA_WIDTH   - 1 : 0] s_payload_fifo_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] s_payload_fifo_axis_tkeep;
    wire s_payload_fifo_axis_tvalid;
    wire s_payload_fifo_axis_tlast;
    wire s_payload_fifo_axis_tuser;
    wire s_payload_fifo_axis_tready;

    wire [DATA_WIDTH   - 1 : 0] m_roce_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_roce_payload_axis_tkeep;
    wire m_roce_payload_axis_tvalid;
    wire m_roce_payload_axis_tlast;
    wire m_roce_payload_axis_tuser;
    wire m_roce_payload_axis_tready;

    wire [DATA_WIDTH   - 1 : 0] m_roce_to_retrans_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_roce_to_retrans_payload_axis_tkeep;
    wire         m_roce_to_retrans_payload_axis_tvalid;
    wire         m_roce_to_retrans_payload_axis_tlast;
    wire         m_roce_to_retrans_payload_axis_tuser;
    wire         m_roce_to_retrans_payload_axis_tready;

    wire [DATA_WIDTH   - 1 : 0] m_roce_to_dropper_payload_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] m_roce_to_dropper_payload_axis_tkeep;
    wire         m_roce_to_dropper_payload_axis_tvalid;
    wire         m_roce_to_dropper_payload_axis_tlast;
    wire         m_roce_to_dropper_payload_axis_tuser;
    wire         m_roce_to_dropper_payload_axis_tready;

    wire roce_bth_valid;
    wire roce_reth_valid;
    wire roce_immdh_valid;
    wire roce_bth_ready;
    wire roce_reth_ready;
    wire roce_immdh_ready;

    wire [7:0]  roce_bth_op_code;
    wire [15:0] roce_bth_p_key;
    wire [23:0] roce_bth_psn;
    wire [23:0] roce_bth_dest_qp;
    wire [23:0] roce_bth_src_qp;
    wire        roce_bth_ack_req;

    wire [63:0] roce_reth_v_addr;
    wire [31:0] roce_reth_r_key;
    wire [31:0] roce_reth_length;

    wire [31:0] roce_immdh_data;

    wire [47:0] eth_dest_mac;
    wire [47:0] eth_src_mac;
    wire [15:0] eth_type;
    wire [3:0]  ip_version;
    wire [3:0]  ip_ihl;
    wire [5:0]  ip_dscp;
    wire [1:0]  ip_ecn;
    wire [15:0] ip_identification;
    wire [2:0]  ip_flags;
    wire [12:0] ip_fragment_offset;
    wire [7:0]  ip_ttl;
    wire [7:0]  ip_protocol;
    wire [15:0] ip_header_checksum;
    wire [31:0] ip_source_ip;
    wire [31:0] ip_dest_ip;
    wire [15:0] udp_source_port;
    wire [15:0] udp_dest_port;
    wire [15:0] udp_length;
    wire [15:0] udp_checksum;

    wire m_roce_to_retrans_bth_valid;
    wire m_roce_to_retrans_reth_valid;
    wire m_roce_to_retrans_immdh_valid;
    wire m_roce_to_retrans_bth_ready;
    wire m_roce_to_retrans_reth_ready;
    wire m_roce_to_retrans_immdh_ready;

    wire [7:0]  m_roce_to_retrans_bth_op_code;
    wire [15:0] m_roce_to_retrans_bth_p_key;
    wire [23:0] m_roce_to_retrans_bth_psn;
    wire [23:0] m_roce_to_retrans_bth_dest_qp;
    wire [23:0] m_roce_to_retrans_bth_src_qp;
    wire        m_roce_to_retrans_bth_ack_req;

    wire [63:0] m_roce_to_retrans_reth_v_addr;
    wire [31:0] m_roce_to_retrans_reth_r_key;
    wire [31:0] m_roce_to_retrans_reth_length;

    wire [31:0] m_roce_to_retrans_immdh_data;

    wire [47:0] m_roce_to_retrans_eth_dest_mac;
    wire [47:0] m_roce_to_retrans_eth_src_mac;
    wire [15:0] m_roce_to_retrans_eth_type;
    wire [3:0]  m_roce_to_retrans_ip_version;
    wire [3:0]  m_roce_to_retrans_ip_ihl;
    wire [5:0]  m_roce_to_retrans_ip_dscp;
    wire [1:0]  m_roce_to_retrans_ip_ecn;
    wire [15:0] m_roce_to_retrans_ip_identification;
    wire [2:0]  m_roce_to_retrans_ip_flags;
    wire [12:0] m_roce_to_retrans_ip_fragment_offset;
    wire [7:0]  m_roce_to_retrans_ip_ttl;
    wire [7:0]  m_roce_to_retrans_ip_protocol;
    wire [15:0] m_roce_to_retrans_ip_header_checksum;
    wire [31:0] m_roce_to_retrans_ip_source_ip;
    wire [31:0] m_roce_to_retrans_ip_dest_ip;
    wire [15:0] m_roce_to_retrans_udp_source_port;
    wire [15:0] m_roce_to_retrans_udp_dest_port;
    wire [15:0] m_roce_to_retrans_udp_length;
    wire [15:0] m_roce_to_retrans_udp_checksum;

    wire [23:0] last_buffered_psn;
    //wire [23:0] last_acked_psn;
    wire [23:0] psn_diff;
    wire [RETRANSMISSION_ADDR_BUFFER_WIDTH-1:0] used_memory;


    wire m_roce_to_dropper_bth_valid;
    wire m_roce_to_dropper_reth_valid;
    wire m_roce_to_dropper_immdh_valid;
    wire m_roce_to_dropper_bth_ready;
    wire m_roce_to_dropper_reth_ready;
    wire m_roce_to_dropper_immdh_ready;

    wire [7:0]  m_roce_to_dropper_bth_op_code;
    wire [15:0] m_roce_to_dropper_bth_p_key;
    wire [23:0] m_roce_to_dropper_bth_psn;
    wire [23:0] m_roce_to_dropper_bth_dest_qp;
    wire [23:0] m_roce_to_dropper_bth_src_qp;
    wire        m_roce_to_dropper_bth_ack_req;

    wire [63:0] m_roce_to_dropper_reth_v_addr;
    wire [31:0] m_roce_to_dropper_reth_r_key;
    wire [31:0] m_roce_to_dropper_reth_length;

    wire [31:0] m_roce_to_dropper_immdh_data;

    wire [47:0] m_roce_to_dropper_eth_dest_mac;
    wire [47:0] m_roce_to_dropper_eth_src_mac;
    wire [15:0] m_roce_to_dropper_eth_type;
    wire [3:0]  m_roce_to_dropper_ip_version;
    wire [3:0]  m_roce_to_dropper_ip_ihl;
    wire [5:0]  m_roce_to_dropper_ip_dscp;
    wire [1:0]  m_roce_to_dropper_ip_ecn;
    wire [15:0] m_roce_to_dropper_ip_identification;
    wire [2:0]  m_roce_to_dropper_ip_flags;
    wire [12:0] m_roce_to_dropper_ip_fragment_offset;
    wire [7:0]  m_roce_to_dropper_ip_ttl;
    wire [7:0]  m_roce_to_dropper_ip_protocol;
    wire [15:0] m_roce_to_dropper_ip_header_checksum;
    wire [31:0] m_roce_to_dropper_ip_source_ip;
    wire [31:0] m_roce_to_dropper_ip_dest_ip;
    wire [15:0] m_roce_to_dropper_udp_source_port;
    wire [15:0] m_roce_to_dropper_udp_dest_port;
    wire [15:0] m_roce_to_dropper_udp_length;
    wire [15:0] m_roce_to_dropper_udp_checksum;


    wire        m_roce_bth_valid;
    wire        m_roce_bth_ready = 1'b1;
    wire [7:0]  m_roce_bth_op_code;
    wire [15:0] m_roce_bth_p_key;
    wire [23:0] m_roce_bth_psn;
    wire [23:0] m_roce_bth_dest_qp;
    wire        m_roce_bth_ack_req;
    wire        m_roce_aeth_valid;
    wire        m_roce_aeth_ready = 1'b1;
    wire [7:0]  m_roce_aeth_syndrome;
    wire [23:0] m_roce_aeth_msn;

    wire        m_roce_rx_to_dropper_bth_valid;
    wire        m_roce_rx_to_dropper_bth_ready;
    wire [7:0]  m_roce_rx_to_dropper_bth_op_code;
    wire [15:0] m_roce_rx_to_dropper_bth_p_key;
    wire [23:0] m_roce_rx_to_dropper_bth_psn;
    wire [23:0] m_roce_rx_to_dropper_bth_dest_qp;
    wire        m_roce_rx_to_dropper_bth_ack_req;
    wire        m_roce_rx_to_dropper_aeth_valid;
    wire        m_roce_rx_to_dropper_aeth_ready;
    wire [7:0]  m_roce_rx_to_dropper_aeth_syndrome;
    wire [23:0] m_roce_rx_to_dropper_aeth_msn;


    // redirect udp rx traffic either to CM or RoCE RX
    wire s_select_udp  = (s_udp_dest_port != 16'h12B7);
    wire s_select_roce = (s_udp_dest_port == 16'h12B7);

    reg s_select_udp_reg = 1'b0;
    reg s_select_roce_reg = 1'b0;

    wire        qp_init_valid;

    wire [6 :0] qp_init_req_type;
    wire [31:0] qp_init_dma_transfer_length;
    wire [23:0] qp_init_rem_qpn;
    wire [23:0] qp_init_loc_qpn;
    wire [23:0] qp_init_rem_psn;
    wire [23:0] qp_init_loc_psn;
    wire [31:0] qp_init_r_key;
    wire [63:0] qp_init_rem_addr;
    wire [31:0] qp_init_rem_ip_addr;
    wire        qp_is_immediate;
    wire        qp_tx_type;

    wire qp_init_status_valid;
    wire [1:0] qp_init_status;

    // QP request
    wire        m_qp_context_req;
    wire [23:0] m_qp_local_qpn_req;

    wire        s_qp_req_context_valid;
    wire [2 :0] s_qp_req_state;
    wire [23:0] s_qp_req_rem_qpn;
    wire [23:0] s_qp_req_loc_qpn;
    wire [23:0] s_qp_req_rem_psn;
    wire [23:0] s_qp_req_loc_psn;
    wire [31:0] s_qp_req_r_key;
    wire [63:0] s_qp_req_rem_addr;
    wire [31:0] s_qp_req_rem_ip_addr;

    // QP state spy
    wire        m_qp_context_spy;
    wire [23:0] m_qp_local_qpn_spy;

    wire        s_qp_spy_context_valid;
    wire [2 :0] s_qp_spy_state;
    wire [23:0] s_qp_spy_rem_qpn;
    wire [23:0] s_qp_spy_loc_qpn;
    wire [23:0] s_qp_spy_rem_psn;
    wire [23:0] s_qp_spy_rem_acked_psn;
    wire [23:0] s_qp_spy_loc_psn;
    wire [31:0] s_qp_spy_r_key;
    wire [63:0] s_qp_spy_rem_addr;
    wire [31:0] s_qp_spy_rem_ip_addr;
    wire [7:0]  s_qp_spy_syndrome;


    wire start_transfer;

    wire stop_transfer;
    reg  stop_transfer_reg;
    wire stop_transfer_nack;

    wire en_retrans;

    wire [23:0] last_acked_psn;
    reg  [23:0] last_acked_psn_reg;
    wire [31:0] n_transfers;

    wire txmeta_valid;
    wire txmeta_start_transfer;
    wire [23:0] txmeta_loc_qpn;
    wire txmeta_is_immediate;
    wire txmeta_tx_type;
    wire [31:0] txmeta_dma_transfer;
    wire [31:0] txmeta_n_transfers;
    wire [31:0] txmeta_frequency;

    wire        s_dma_meta_valid;
    wire        s_dma_meta_ready;
    wire [31:0] s_dma_length;
    wire [23:0] s_rem_qpn;
    wire [23:0] s_loc_qpn;
    wire [23:0] s_rem_psn;
    wire [31:0] s_r_key;
    wire [31:0] s_rem_ip_addr;
    wire [63:0] s_rem_addr;
    wire        s_is_immediate;
    wire        s_trasfer_type;

    /*
    AXI RAM INTERFACE
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
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_wdata;
    wire [DATA_WIDTH/8 - 1 : 0]                 m_axi_wstrb;
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
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_rdata;
    wire [1:0]                                  m_axi_rresp;
    wire                                        m_axi_rlast;
    wire                                        m_axi_rvalid;
    wire                                        m_axi_rready;

    /*
    AXI RAM BUFFER INTERFACE
    */
    localparam BUFFER_ADDR_WIDTH = 24;
    wire [0                :0]   m_axi_buffer_awid;
    wire [BUFFER_ADDR_WIDTH-1:0] m_axi_buffer_awaddr;
    wire [7:0]                   m_axi_buffer_awlen;
    wire [2:0]                   m_axi_buffer_awsize;
    wire [1:0]                   m_axi_buffer_awburst;
    wire                         m_axi_buffer_awlock;
    wire [3:0]                   m_axi_buffer_awcache;
    wire [2:0]                   m_axi_buffer_awprot;
    wire                         m_axi_buffer_awvalid;
    wire                         m_axi_buffer_awready;
    wire [DATA_WIDTH   - 1 : 0]  m_axi_buffer_wdata;
    wire [DATA_WIDTH/8 - 1 : 0]  m_axi_buffer_wstrb;
    wire                         m_axi_buffer_wlast;
    wire                         m_axi_buffer_wvalid;
    wire                         m_axi_buffer_wready;
    wire [0             :0]      m_axi_buffer_bid;
    wire [1:0]                   m_axi_buffer_bresp;
    wire                         m_axi_buffer_bvalid;
    wire                         m_axi_buffer_bready;
    wire [0               :0]    m_axi_buffer_arid;
    wire [BUFFER_ADDR_WIDTH-1:0] m_axi_buffer_araddr;
    wire [7:0]                   m_axi_buffer_arlen;
    wire [2:0]                   m_axi_buffer_arsize;
    wire [1:0]                   m_axi_buffer_arburst;
    wire                         m_axi_buffer_arlock;
    wire [3:0]                   m_axi_buffer_arcache;
    wire [2:0]                   m_axi_buffer_arprot;
    wire                         m_axi_buffer_arvalid;
    wire                         m_axi_buffer_arready;
    wire [0             :0]      m_axi_buffer_rid;
    wire [DATA_WIDTH   - 1 : 0]  m_axi_buffer_rdata;
    wire [1:0]                   m_axi_buffer_rresp;
    wire                         m_axi_buffer_rlast;
    wire                         m_axi_buffer_rvalid;
    wire                         m_axi_buffer_rready;

    wire         qp_close_params_valid;
    wire [127:0] qp_close_params;

    wire [26:0] RoCE_tx_n_valid_up;
    wire [26:0] RoCE_tx_n_ready_up;
    wire [26:0] RoCE_tx_n_both_up;

    reg [3:0] pmtu_shift;
    reg [11:0] length_pmtu_mask;

    always @(posedge clk) begin
        case (pmtu)
            3'd0: begin
                pmtu_shift <= 4'd8;
                length_pmtu_mask = {4'h0, {8{1'b1}}};
            end
            3'd1: begin
                pmtu_shift <= 4'd9;
                length_pmtu_mask = {3'h0, {9{1'b1}}};
            end
            3'd2: begin
                pmtu_shift <= 4'd10;
                length_pmtu_mask = {2'h0, {10{1'b1}}};
            end
            3'd3: begin
                pmtu_shift <= 4'd11;
                length_pmtu_mask = {1'h0, {11{1'b1}}};
            end
            3'd4: begin
                pmtu_shift <= 4'd12;
                length_pmtu_mask = {12{1'b1}};
            end
        endcase
    end

    /*
     * Generate payolad data
     */
    axis_data_generator #(
    .DATA_WIDTH(DATA_WIDTH)
    ) axis_data_generator_instance (
        .clk(clk),
        .rst(rst),
        .start(s_dma_meta_valid && s_dma_meta_ready),
        .stop((stop_transfer && en_retrans) || (stop_transfer_nack && ~en_retrans)),
        .m_axis_tdata (s_payload_axis_tdata),
        .m_axis_tkeep (s_payload_axis_tkeep),
        .m_axis_tvalid(s_payload_axis_tvalid),
        .m_axis_tready(s_payload_axis_tready),
        .m_axis_tlast (s_payload_axis_tlast),
        .m_axis_tuser (s_payload_axis_tuser),
        .length(s_dma_length)
    );


    always @(posedge clk) begin
        if (rst) begin
            s_select_udp_reg  <= 1'b0;
            s_select_roce_reg <= 1'b0;
        end else begin
            if (s_udp_payload_axis_tvalid) begin
                if ((!s_select_udp_reg && !s_select_roce_reg) ||
                (s_udp_payload_axis_tvalid && s_udp_payload_axis_tready && s_udp_payload_axis_tlast)) begin
                    s_select_udp_reg  <= s_select_udp;
                    s_select_roce_reg <= s_select_roce;
                end
            end else begin
                s_select_udp_reg  <= 1'b0;
                s_select_roce_reg <= 1'b0;
            end
        end
    end

    assign rx_udp_cm_hdr_valid = s_select_udp && s_udp_hdr_valid;
    assign rx_udp_cm_source_port = s_udp_source_port;
    assign rx_udp_cm_dest_port = s_udp_dest_port;
    assign rx_udp_cm_length = s_udp_length;
    assign rx_udp_cm_checksum = s_udp_checksum;
    assign rx_udp_cm_payload_axis_tdata = s_udp_payload_axis_tdata;
    assign rx_udp_cm_payload_axis_tkeep = s_udp_payload_axis_tkeep;
    assign rx_udp_cm_payload_axis_tvalid = s_select_udp_reg && s_udp_payload_axis_tvalid;
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
    assign rx_udp_RoCE_dest_port = 16'h12B7;
    assign rx_udp_RoCE_length = s_udp_length;
    assign rx_udp_RoCE_checksum = s_udp_checksum;
    assign rx_udp_RoCE_payload_axis_tdata = s_udp_payload_axis_tdata;
    assign rx_udp_RoCE_payload_axis_tkeep = s_udp_payload_axis_tkeep;
    assign rx_udp_RoCE_payload_axis_tvalid = s_select_roce_reg && s_udp_payload_axis_tvalid;
    assign rx_udp_RoCE_payload_axis_tlast = s_udp_payload_axis_tlast;
    assign rx_udp_RoCE_payload_axis_tuser = s_udp_payload_axis_tuser;

    assign s_udp_hdr_ready = (s_select_udp && rx_udp_cm_hdr_ready) || (s_select_roce && rx_udp_RoCE_hdr_ready);

    assign s_udp_payload_axis_tready = (s_select_udp_reg && rx_udp_cm_payload_axis_tready) ||
    (s_select_roce_reg && rx_udp_RoCE_payload_axis_tready);

    wire [DATA_WIDTH -1  :0]    s_payload_fifo_temp_axis_tdata;
    wire [DATA_WIDTH/8 -1:0]    s_payload_fifo_temp_axis_tkeep;
    wire                        s_payload_fifo_temp_axis_tvalid;
    wire                        s_payload_fifo_temp_axis_tready;
    wire                        s_payload_fifo_temp_axis_tlast;
    wire                        s_payload_fifo_temp_axis_tuser;

    axis_fifo #(
        .DEPTH(4096),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) input_axis_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata(s_payload_axis_tdata),
        .s_axis_tkeep(s_payload_axis_tkeep),
        .s_axis_tvalid(s_payload_axis_tvalid),
        .s_axis_tready(s_payload_axis_tready),
        .s_axis_tlast(s_payload_axis_tlast),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(s_payload_axis_tuser),

        // AXI output
        .m_axis_tdata (s_payload_fifo_axis_tdata),
        .m_axis_tkeep (s_payload_fifo_axis_tkeep),
        .m_axis_tvalid(s_payload_fifo_axis_tvalid),
        .m_axis_tready(s_payload_fifo_axis_tready),
        .m_axis_tlast (s_payload_fifo_axis_tlast),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser (s_payload_fifo_axis_tuser),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );

    RoCE_tx_header_producer #(
    .DATA_WIDTH(DATA_WIDTH)
    ) Roce_tx_header_producer_instance (
        .clk                       (clk),
        .rst                       (rst),

        .s_dma_meta_valid          (s_dma_meta_valid),
        .s_dma_meta_ready          (s_dma_meta_ready),
        .s_dma_length              (s_dma_length),
        .s_rem_qpn                 (s_rem_qpn),
        .s_loc_qpn                 (s_loc_qpn),
        .s_rem_psn                 (s_rem_psn),
        .s_r_key                   (s_r_key),
        .s_rem_ip_addr             (s_rem_ip_addr),
        .s_rem_addr                (s_rem_addr),
        .s_is_immediate            (s_is_immediate),
        .s_trasfer_type            (s_trasfer_type),

        .s_axis_tdata              (s_payload_fifo_axis_tdata),
        .s_axis_tkeep              (s_payload_fifo_axis_tkeep),
        .s_axis_tvalid             (s_payload_fifo_axis_tvalid),
        .s_axis_tready             (s_payload_fifo_axis_tready),
        .s_axis_tlast              (s_payload_fifo_axis_tlast),
        .s_axis_tuser              (s_payload_fifo_axis_tuser),
        .m_roce_bth_valid          (m_roce_to_retrans_bth_valid),
        .m_roce_bth_ready          (m_roce_to_retrans_bth_ready),
        .m_roce_bth_op_code        (m_roce_to_retrans_bth_op_code),
        .m_roce_bth_p_key          (m_roce_to_retrans_bth_p_key),
        .m_roce_bth_psn            (m_roce_to_retrans_bth_psn),
        .m_roce_bth_dest_qp        (m_roce_to_retrans_bth_dest_qp),
        .m_roce_bth_src_qp         (m_roce_to_retrans_bth_src_qp),
        .m_roce_bth_ack_req        (m_roce_to_retrans_bth_ack_req),
        .m_roce_reth_valid         (m_roce_to_retrans_reth_valid),
        .m_roce_reth_ready         (m_roce_to_retrans_reth_ready),
        .m_roce_reth_v_addr        (m_roce_to_retrans_reth_v_addr),
        .m_roce_reth_r_key         (m_roce_to_retrans_reth_r_key),
        .m_roce_reth_length        (m_roce_to_retrans_reth_length),
        .m_roce_immdh_valid        (m_roce_to_retrans_immdh_valid),
        .m_roce_immdh_ready        (m_roce_to_retrans_immdh_ready),
        .m_roce_immdh_data         (m_roce_to_retrans_immdh_data),
        .m_eth_dest_mac            (m_roce_to_retrans_eth_dest_mac),
        .m_eth_src_mac             (m_roce_to_retrans_eth_src_mac),
        .m_eth_type                (m_roce_to_retrans_eth_type),
        .m_ip_version              (m_roce_to_retrans_ip_version),
        .m_ip_ihl                  (m_roce_to_retrans_ip_ihl),
        .m_ip_dscp                 (m_roce_to_retrans_ip_dscp),
        .m_ip_ecn                  (m_roce_to_retrans_ip_ecn),
        .m_ip_identification       (m_roce_to_retrans_ip_identification),
        .m_ip_flags                (m_roce_to_retrans_ip_flags),
        .m_ip_fragment_offset      (m_roce_to_retrans_ip_fragment_offset),
        .m_ip_ttl                  (m_roce_to_retrans_ip_ttl),
        .m_ip_protocol             (m_roce_to_retrans_ip_protocol),
        .m_ip_header_checksum      (m_roce_to_retrans_ip_header_checksum),
        .m_ip_source_ip            (m_roce_to_retrans_ip_source_ip),
        .m_ip_dest_ip              (m_roce_to_retrans_ip_dest_ip),
        .m_udp_source_port         (m_roce_to_retrans_udp_source_port),
        .m_udp_dest_port           (m_roce_to_retrans_udp_dest_port),
        .m_udp_length              (m_roce_to_retrans_udp_length),
        .m_udp_checksum            (m_roce_to_retrans_udp_checksum),
        .m_roce_payload_axis_tdata (m_roce_to_retrans_payload_axis_tdata),
        .m_roce_payload_axis_tkeep (m_roce_to_retrans_payload_axis_tkeep),
        .m_roce_payload_axis_tvalid(m_roce_to_retrans_payload_axis_tvalid),
        .m_roce_payload_axis_tready(m_roce_to_retrans_payload_axis_tready),
        .m_roce_payload_axis_tlast (m_roce_to_retrans_payload_axis_tlast),
        .m_roce_payload_axis_tuser (m_roce_to_retrans_payload_axis_tuser),
        .pmtu                      (pmtu),
        .RoCE_udp_port             (RoCE_udp_port),
        .loc_ip_addr               (loc_ip_addr)
    );

    generate
        if (RETRANSMISSION) begin

            /*
            WORKAROUND to to have only one qp in RTS at the same time
            */
            reg        qp_active;
            reg [23:0] curr_open_qpn;

            always @(posedge clk) begin
                if (rst) begin
                    curr_open_qpn <= 24'd0;
                    qp_active     <= 1'b0;
                end else begin
                    if (qp_init_valid && qp_init_req_type == REQ_MODIFY_QP_RTS && !qp_active) begin
                        curr_open_qpn <= qp_init_loc_qpn;
                        qp_active     <= 1'b1;
                    end else if (qp_init_valid && qp_init_req_type == REQ_CLOSE_QP && qp_active) begin
                        curr_open_qpn <= 24'd0;
                        qp_active     <= 1'b0;
                    end
                end
            end


            wire [127:0] s_qp_params;
            assign s_qp_params[31 :0  ] = qp_init_rem_ip_addr;
            assign s_qp_params[55 :32 ] = qp_init_rem_qpn;
            assign s_qp_params[79 :56 ] = qp_init_loc_qpn;
            assign s_qp_params[111:80 ] = qp_init_r_key;
            assign s_qp_params[127:112] = 16'hffff; // p_key


            RoCE_retransmission_module #(
                .DATA_WIDTH(DATA_WIDTH),
                .BUFFER_ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                //.MAX_QUEUE_PAIRS(MAX_QUEUE_PAIRS),
                .CLOCK_PERIOD(CLOCK_PERIOD),
                .DEBUG(DEBUG)
            ) RoCE_retransmission_module_instance (
                .clk(clk),
                .rst(rst),
                .rst_retry_cntr              (qp_init_valid && qp_init_req_type == REQ_MODIFY_QP_RTS & !qp_active),
                .s_qp_params_valid           (qp_init_valid && qp_init_req_type == REQ_MODIFY_QP_RTS & !qp_active),
                .s_qp_params                 (s_qp_params),
                .s_roce_aeth_valid           (m_roce_aeth_valid),
                .s_roce_rx_aeth_syndrome     (m_roce_aeth_syndrome),
                .s_roce_rx_bth_psn           (m_roce_bth_psn),
                .s_roce_rx_bth_op_code       (m_roce_bth_op_code),
                .s_roce_rx_bth_dest_qp       (m_roce_bth_dest_qp),
                .s_roce_rx_last_not_acked_psn(0),
                .s_roce_bth_valid            (m_roce_to_retrans_bth_valid),
                .s_roce_bth_ready            (m_roce_to_retrans_bth_ready),
                .s_roce_bth_op_code          (m_roce_to_retrans_bth_op_code),
                .s_roce_bth_p_key            (m_roce_to_retrans_bth_p_key),
                .s_roce_bth_psn              (m_roce_to_retrans_bth_psn),
                .s_roce_bth_dest_qp          (m_roce_to_retrans_bth_dest_qp),
                .s_roce_bth_src_qp           (m_roce_to_retrans_bth_src_qp),
                .s_roce_bth_ack_req          (m_roce_to_retrans_bth_ack_req),
                .s_roce_reth_valid           (m_roce_to_retrans_reth_valid),
                .s_roce_reth_ready           (m_roce_to_retrans_reth_ready),
                .s_roce_reth_v_addr          (m_roce_to_retrans_reth_v_addr),
                .s_roce_reth_r_key           (m_roce_to_retrans_reth_r_key),
                .s_roce_reth_length          (m_roce_to_retrans_reth_length),
                .s_roce_immdh_valid          (m_roce_to_retrans_immdh_valid),
                .s_roce_immdh_ready          (m_roce_to_retrans_immdh_ready),
                .s_roce_immdh_data           (m_roce_to_retrans_immdh_data),
                .s_eth_dest_mac              (m_roce_to_retrans_eth_dest_mac),
                .s_eth_src_mac               (m_roce_to_retrans_eth_src_mac),
                .s_eth_type                  (m_roce_to_retrans_eth_type),
                .s_ip_version                (m_roce_to_retrans_ip_version),
                .s_ip_ihl                    (m_roce_to_retrans_ip_ihl),
                .s_ip_dscp                   (m_roce_to_retrans_ip_dscp),
                .s_ip_ecn                    (m_roce_to_retrans_ip_ecn),
                .s_ip_identification         (m_roce_to_retrans_ip_identification),
                .s_ip_flags                  (m_roce_to_retrans_ip_flags),
                .s_ip_fragment_offset        (m_roce_to_retrans_ip_fragment_offset),
                .s_ip_ttl                    (m_roce_to_retrans_ip_ttl),
                .s_ip_protocol               (m_roce_to_retrans_ip_protocol),
                .s_ip_header_checksum        (m_roce_to_retrans_ip_header_checksum),
                .s_ip_source_ip              (m_roce_to_retrans_ip_source_ip),
                .s_ip_dest_ip                (m_roce_to_retrans_ip_dest_ip),
                .s_udp_source_port           (m_roce_to_retrans_udp_source_port),
                .s_udp_dest_port             (m_roce_to_retrans_udp_dest_port),
                .s_udp_length                (m_roce_to_retrans_udp_length),
                .s_udp_checksum              (m_roce_to_retrans_udp_checksum),
                .s_roce_payload_axis_tdata   (m_roce_to_retrans_payload_axis_tdata),
                .s_roce_payload_axis_tkeep   (m_roce_to_retrans_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid  (m_roce_to_retrans_payload_axis_tvalid),
                .s_roce_payload_axis_tready  (m_roce_to_retrans_payload_axis_tready),
                .s_roce_payload_axis_tlast   (m_roce_to_retrans_payload_axis_tlast),
                .s_roce_payload_axis_tuser   (m_roce_to_retrans_payload_axis_tuser),
                .m_roce_bth_valid            (m_roce_to_dropper_bth_valid),
                .m_roce_bth_ready            (m_roce_to_dropper_bth_ready),
                .m_roce_bth_op_code          (m_roce_to_dropper_bth_op_code),
                .m_roce_bth_p_key            (m_roce_to_dropper_bth_p_key),
                .m_roce_bth_psn              (m_roce_to_dropper_bth_psn),
                .m_roce_bth_dest_qp          (m_roce_to_dropper_bth_dest_qp),
                .m_roce_bth_src_qp           (m_roce_to_dropper_bth_src_qp),
                .m_roce_bth_ack_req          (m_roce_to_dropper_bth_ack_req),
                .m_roce_reth_valid           (m_roce_to_dropper_reth_valid),
                .m_roce_reth_ready           (m_roce_to_dropper_reth_ready),
                .m_roce_reth_v_addr          (m_roce_to_dropper_reth_v_addr),
                .m_roce_reth_r_key           (m_roce_to_dropper_reth_r_key),
                .m_roce_reth_length          (m_roce_to_dropper_reth_length),
                .m_roce_immdh_valid          (m_roce_to_dropper_immdh_valid),
                .m_roce_immdh_ready          (m_roce_to_dropper_immdh_ready),
                .m_roce_immdh_data           (m_roce_to_dropper_immdh_data),
                .m_eth_dest_mac              (m_roce_to_dropper_eth_dest_mac),
                .m_eth_src_mac               (m_roce_to_dropper_eth_src_mac),
                .m_eth_type                  (m_roce_to_dropper_eth_type),
                .m_ip_version                (m_roce_to_dropper_ip_version),
                .m_ip_ihl                    (m_roce_to_dropper_ip_ihl),
                .m_ip_dscp                   (m_roce_to_dropper_ip_dscp),
                .m_ip_ecn                    (m_roce_to_dropper_ip_ecn),
                .m_ip_identification         (m_roce_to_dropper_ip_identification),
                .m_ip_flags                  (m_roce_to_dropper_ip_flags),
                .m_ip_fragment_offset        (m_roce_to_dropper_ip_fragment_offset),
                .m_ip_ttl                    (m_roce_to_dropper_ip_ttl),
                .m_ip_protocol               (m_roce_to_dropper_ip_protocol),
                .m_ip_header_checksum        (m_roce_to_dropper_ip_header_checksum),
                .m_ip_source_ip              (m_roce_to_dropper_ip_source_ip),
                .m_ip_dest_ip                (m_roce_to_dropper_ip_dest_ip),
                .m_udp_source_port           (m_roce_to_dropper_udp_source_port),
                .m_udp_dest_port             (m_roce_to_dropper_udp_dest_port),
                .m_udp_length                (m_roce_to_dropper_udp_length),
                .m_udp_checksum              (m_roce_to_dropper_udp_checksum),
                .m_roce_payload_axis_tdata   (m_roce_to_dropper_payload_axis_tdata),
                .m_roce_payload_axis_tkeep   (m_roce_to_dropper_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid  (m_roce_to_dropper_payload_axis_tvalid),
                .m_roce_payload_axis_tready  (m_roce_to_dropper_payload_axis_tready),
                .m_roce_payload_axis_tlast   (m_roce_to_dropper_payload_axis_tlast),
                .m_roce_payload_axis_tuser   (m_roce_to_dropper_payload_axis_tuser),
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
                //
                .m_qp_close_params_valid(qp_close_params_valid),
                .m_qp_close_params(qp_close_params),
                //
                .stop_transfer(stop_transfer),
                .last_buffered_psn(last_buffered_psn),
                .last_acked_psn(),
                .psn_diff(psn_diff),
                .used_memory(used_memory),
                // Config
                .timeout_period(timeout_period),
                .retry_count(retry_count),
                .rnr_retry_count(rnr_retry_count),
                .pmtu(pmtu),
                .en_retrans(en_retrans)
            );

            /*
      axi_register #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
        .STRB_WIDTH(DATA_WIDTH/8),
        .ID_WIDTH(1),
        .AW_REG_TYPE(0),
        .W_REG_TYPE(0),
        .B_REG_TYPE(0),
        .AR_REG_TYPE(1),
        .R_REG_TYPE(2)
      ) axi_register_instance (
        .clk(clk),
        .rst(rst),
        .s_axi_awid    (m_axi_reg_awid),
        .s_axi_awaddr  (m_axi_reg_awaddr),
        .s_axi_awlen   (m_axi_reg_awlen),
        .s_axi_awsize  (m_axi_reg_awsize),
        .s_axi_awburst (m_axi_reg_awburst),
        .s_axi_awlock  (m_axi_reg_awlock),
        .s_axi_awcache (m_axi_reg_awcache),
        .s_axi_awprot  (m_axi_reg_awprot),
        //.s_axi_awqos   (m_axi_awqos),
        //.s_axi_awregion(m_axi_awregion),
        //.s_axi_awuser  (m_axi_awuser),
        .s_axi_awvalid (m_axi_reg_awvalid),
        .s_axi_awready (m_axi_reg_awready),
        .s_axi_wdata   (m_axi_reg_wdata),
        .s_axi_wstrb   (m_axi_reg_wstrb),
        .s_axi_wlast   (m_axi_reg_wlast),
        //.s_axi_wuser   (m_axi_wuser),
        .s_axi_wvalid  (m_axi_reg_wvalid),
        .s_axi_wready  (m_axi_reg_wready),
        .s_axi_bid     (m_axi_reg_bid),
        .s_axi_bresp   (m_axi_reg_bresp),
        //.s_axi_buser   (m_axi_buser),
        .s_axi_bvalid  (m_axi_reg_bvalid),
        .s_axi_bready  (m_axi_reg_bready),
        .s_axi_arid    (m_axi_reg_arid),
        .s_axi_araddr  (m_axi_reg_araddr),
        .s_axi_arlen   (m_axi_reg_arlen),
        .s_axi_arsize  (m_axi_reg_arsize),
        .s_axi_arburst (m_axi_reg_arburst),
        .s_axi_arlock  (m_axi_reg_arlock),
        .s_axi_arcache (m_axi_reg_arcache),
        .s_axi_arprot  (m_axi_reg_arprot),
        //.s_axi_arqos   (m_axi_arqos),
        //.s_axi_arregion(m_axi_arregion),
        //.s_axi_aruser  (m_axi_aruser),
        .s_axi_arvalid (m_axi_reg_arvalid),
        .s_axi_arready (m_axi_reg_arready),
        .s_axi_rid     (m_axi_reg_rid),
        .s_axi_rdata   (m_axi_reg_rdata),
        .s_axi_rresp   (m_axi_reg_rresp),
        .s_axi_rlast   (m_axi_reg_rlast),
        //.s_axi_ruser   (m_axi_ruser),
        .s_axi_rvalid  (m_axi_reg_rvalid),
        .s_axi_rready  (m_axi_reg_rready),
        .m_axi_awid    (m_axi_awid),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awlock  (m_axi_awlock),
        .m_axi_awcache (m_axi_awcache),
        .m_axi_awprot  (m_axi_awprot),
        //.m_axi_awqos   (m_axi_awqos),
        //.m_axi_awregion(m_axi_awregion),
        //.m_axi_awuser  (m_axi_awuser),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        //.m_axi_wuser   (m_axi_wuser),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bid     (m_axi_bid),
        .m_axi_bresp   (m_axi_bresp),
        //.m_axi_buser   (m_axi_buser),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_arid    (m_axi_arid),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arlock  (m_axi_arlock),
        .m_axi_arcache (m_axi_arcache),
        .m_axi_arprot  (m_axi_arprot),
        //.m_axi_arqos   (m_axi_arqos),
        //.m_axi_arregion(m_axi_arregion),
        //.m_axi_aruser  (m_axi_aruser),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rid     (m_axi_rid),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rlast   (m_axi_rlast),
        //.m_axi_ruser   (m_axi_ruser),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready)
      );
      */

            axi_ram_mod #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(RETRANSMISSION_ADDR_BUFFER_WIDTH),
                .STRB_WIDTH(DATA_WIDTH/8),
                .ID_WIDTH(1)
            ) RoCE_axi_ram_mod_instance (
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
                .s_axi_rready (m_axi_rready)
            );

        end else begin

            assign roce_bth_valid = m_roce_to_retrans_bth_valid;
            assign m_roce_to_retrans_bth_ready = roce_bth_ready;
            assign roce_bth_op_code = m_roce_to_retrans_bth_op_code;
            assign roce_bth_p_key = m_roce_to_retrans_bth_p_key;
            assign roce_bth_psn = m_roce_to_retrans_bth_psn;
            assign roce_bth_dest_qp = m_roce_to_retrans_bth_dest_qp;
            assign roce_bth_src_qp = m_roce_to_retrans_bth_src_qp;
            assign roce_bth_ack_req = m_roce_to_retrans_bth_ack_req;
            assign roce_reth_valid = m_roce_to_retrans_reth_valid;
            assign m_roce_to_retrans_reth_ready = roce_reth_ready;
            assign roce_reth_v_addr = m_roce_to_retrans_reth_v_addr;
            assign roce_reth_r_key = m_roce_to_retrans_reth_r_key;
            assign roce_reth_length = m_roce_to_retrans_reth_length;
            assign roce_immdh_valid = m_roce_to_retrans_immdh_valid;
            assign m_roce_to_retrans_immdh_ready = roce_immdh_ready;
            assign roce_immdh_data = m_roce_to_retrans_immdh_data;
            assign eth_dest_mac =  m_roce_to_retrans_eth_dest_mac;
            assign eth_src_mac =  m_roce_to_retrans_eth_src_mac;
            assign eth_type =  m_roce_to_retrans_eth_type;
            assign ip_version = m_roce_to_retrans_ip_version;
            assign ip_ihl = m_roce_to_retrans_ip_ihl;
            assign ip_dscp = m_roce_to_retrans_ip_dscp;
            assign ip_ecn = m_roce_to_retrans_ip_ecn;
            assign ip_identification = m_roce_to_retrans_ip_identification;
            assign ip_flags =  m_roce_to_retrans_ip_flags;
            assign ip_fragment_offset = m_roce_to_retrans_ip_fragment_offset;
            assign ip_ttl = m_roce_to_retrans_ip_ttl;
            assign ip_protocol = m_roce_to_retrans_ip_protocol;
            assign ip_header_checksum = m_roce_to_retrans_ip_header_checksum;
            assign ip_source_ip = m_roce_to_retrans_ip_source_ip;
            assign ip_dest_ip = m_roce_to_retrans_ip_dest_ip;
            assign udp_source_port = m_roce_to_retrans_udp_source_port;
            assign udp_dest_port = m_roce_to_retrans_udp_dest_port;
            assign udp_length = m_roce_to_retrans_udp_length;
            assign udp_checksum = m_roce_to_retrans_udp_checksum;
            assign m_roce_payload_axis_tdata = m_roce_to_retrans_payload_axis_tdata;
            assign m_roce_payload_axis_tkeep = m_roce_to_retrans_payload_axis_tkeep;
            assign m_roce_payload_axis_tvalid = m_roce_to_retrans_payload_axis_tvalid;
            assign m_roce_to_retrans_payload_axis_tready = m_roce_payload_axis_tready;
            assign m_roce_payload_axis_tlast = m_roce_to_retrans_payload_axis_tlast;
            assign m_roce_payload_axis_tuser = m_roce_to_retrans_payload_axis_tuser;

            assign qp_close_params_valid = 1'b0;
            assign qp_close_params = 128'd0;

            assign stop_transfer = stop_transfer_nack;

            assign last_buffered_psn = 24'd0;
            assign psn_diff          = 24'd0;
            assign used_memory       = 0;
        end
    endgenerate

    generate
        if (ENABLE_SIM_PACKET_DROP_TX) begin

            RoCE_packet_dropper #(
                .DATA_WIDTH(DATA_WIDTH),
                .DROP_PROBABILITY(50)
            ) RoCE_packet_dropper_instance (
                .clk(clk),
                .rst(rst),
                .s_roce_bth_valid          (m_roce_to_dropper_bth_valid),
                .s_roce_bth_ready          (m_roce_to_dropper_bth_ready),
                .s_roce_bth_op_code        (m_roce_to_dropper_bth_op_code),
                .s_roce_bth_p_key          (m_roce_to_dropper_bth_p_key),
                .s_roce_bth_psn            (m_roce_to_dropper_bth_psn),
                .s_roce_bth_dest_qp        (m_roce_to_dropper_bth_dest_qp),
                .s_roce_bth_src_qp         (m_roce_to_dropper_bth_src_qp),
                .s_roce_bth_ack_req        (m_roce_to_dropper_bth_ack_req),
                .s_roce_reth_valid         (m_roce_to_dropper_reth_valid),
                .s_roce_reth_ready         (m_roce_to_dropper_reth_ready),
                .s_roce_reth_v_addr        (m_roce_to_dropper_reth_v_addr),
                .s_roce_reth_r_key         (m_roce_to_dropper_reth_r_key),
                .s_roce_reth_length        (m_roce_to_dropper_reth_length),
                .s_roce_immdh_valid        (m_roce_to_dropper_immdh_valid),
                .s_roce_immdh_ready        (m_roce_to_dropper_immdh_ready),
                .s_roce_immdh_data         (m_roce_to_dropper_immdh_data),
                .s_eth_dest_mac            (m_roce_to_dropper_eth_dest_mac),
                .s_eth_src_mac             (m_roce_to_dropper_eth_src_mac),
                .s_eth_type                (m_roce_to_dropper_eth_type),
                .s_ip_version              (m_roce_to_dropper_ip_version),
                .s_ip_ihl                  (m_roce_to_dropper_ip_ihl),
                .s_ip_dscp                 (m_roce_to_dropper_ip_dscp),
                .s_ip_ecn                  (m_roce_to_dropper_ip_ecn),
                .s_ip_identification       (m_roce_to_dropper_ip_identification),
                .s_ip_flags                (m_roce_to_dropper_ip_flags),
                .s_ip_fragment_offset      (m_roce_to_dropper_ip_fragment_offset),
                .s_ip_ttl                  (m_roce_to_dropper_ip_ttl),
                .s_ip_protocol             (m_roce_to_dropper_ip_protocol),
                .s_ip_header_checksum      (m_roce_to_dropper_ip_header_checksum),
                .s_ip_source_ip            (m_roce_to_dropper_ip_source_ip),
                .s_ip_dest_ip              (m_roce_to_dropper_ip_dest_ip),
                .s_udp_source_port         (m_roce_to_dropper_udp_source_port),
                .s_udp_dest_port           (m_roce_to_dropper_udp_dest_port),
                .s_udp_length              (m_roce_to_dropper_udp_length),
                .s_udp_checksum            (m_roce_to_dropper_udp_checksum),
                .s_roce_payload_axis_tdata (m_roce_to_dropper_payload_axis_tdata),
                .s_roce_payload_axis_tkeep (m_roce_to_dropper_payload_axis_tkeep),
                .s_roce_payload_axis_tvalid(m_roce_to_dropper_payload_axis_tvalid),
                .s_roce_payload_axis_tready(m_roce_to_dropper_payload_axis_tready),
                .s_roce_payload_axis_tlast (m_roce_to_dropper_payload_axis_tlast),
                .s_roce_payload_axis_tuser (m_roce_to_dropper_payload_axis_tuser),
                .m_roce_bth_valid          (roce_bth_valid),
                .m_roce_bth_ready          (roce_bth_ready),
                .m_roce_bth_op_code        (roce_bth_op_code),
                .m_roce_bth_p_key          (roce_bth_p_key),
                .m_roce_bth_psn            (roce_bth_psn),
                .m_roce_bth_dest_qp        (roce_bth_dest_qp),
                .m_roce_bth_src_qp         (roce_bth_src_qp),
                .m_roce_bth_ack_req        (roce_bth_ack_req),
                .m_roce_reth_valid         (roce_reth_valid),
                .m_roce_reth_ready         (roce_reth_ready),
                .m_roce_reth_v_addr        (roce_reth_v_addr),
                .m_roce_reth_r_key         (roce_reth_r_key),
                .m_roce_reth_length        (roce_reth_length),
                .m_roce_immdh_valid        (roce_immdh_valid),
                .m_roce_immdh_ready        (roce_immdh_ready),
                .m_roce_immdh_data         (roce_immdh_data),
                .m_eth_dest_mac            (eth_dest_mac),
                .m_eth_src_mac             (eth_src_mac),
                .m_eth_type                (eth_type),
                .m_ip_version              (ip_version),
                .m_ip_ihl                  (ip_ihl),
                .m_ip_dscp                 (ip_dscp),
                .m_ip_ecn                  (ip_ecn),
                .m_ip_identification       (ip_identification),
                .m_ip_flags                (ip_flags),
                .m_ip_fragment_offset      (ip_fragment_offset),
                .m_ip_ttl                  (ip_ttl),
                .m_ip_protocol             (ip_protocol),
                .m_ip_header_checksum      (ip_header_checksum),
                .m_ip_source_ip            (ip_source_ip),
                .m_ip_dest_ip              (ip_dest_ip),
                .m_udp_source_port         (udp_source_port),
                .m_udp_dest_port           (udp_dest_port),
                .m_udp_length              (udp_length),
                .m_udp_checksum            (udp_checksum),
                .m_roce_payload_axis_tdata (m_roce_payload_axis_tdata),
                .m_roce_payload_axis_tkeep (m_roce_payload_axis_tkeep),
                .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
                .m_roce_payload_axis_tready(m_roce_payload_axis_tready),
                .m_roce_payload_axis_tlast (m_roce_payload_axis_tlast),
                .m_roce_payload_axis_tuser (m_roce_payload_axis_tuser)
            );
        end else begin

            assign roce_bth_valid              = m_roce_to_dropper_bth_valid;
            assign m_roce_to_dropper_bth_ready = roce_bth_ready;
            assign roce_bth_op_code            = m_roce_to_dropper_bth_op_code;
            assign roce_bth_p_key              = m_roce_to_dropper_bth_p_key;
            assign roce_bth_psn                = m_roce_to_dropper_bth_psn;
            assign roce_bth_dest_qp            = m_roce_to_dropper_bth_dest_qp;
            assign roce_bth_src_qp             = m_roce_to_dropper_bth_src_qp;
            assign roce_bth_ack_req            = m_roce_to_dropper_bth_ack_req;
            assign roce_reth_valid             = m_roce_to_dropper_reth_valid;
            assign m_roce_to_dropper_reth_ready = roce_reth_ready;
            assign roce_reth_v_addr            = m_roce_to_dropper_reth_v_addr;
            assign roce_reth_r_key             = m_roce_to_dropper_reth_r_key;
            assign roce_reth_length            = m_roce_to_dropper_reth_length;
            assign roce_immdh_valid            = m_roce_to_dropper_immdh_valid;
            assign m_roce_to_dropper_immdh_ready = roce_immdh_ready;
            assign roce_immdh_data             = m_roce_to_dropper_immdh_data;
            assign eth_dest_mac                = m_roce_to_dropper_eth_dest_mac;
            assign eth_src_mac                 = m_roce_to_dropper_eth_src_mac;
            assign eth_type                    = m_roce_to_dropper_eth_type;
            assign ip_version                  = m_roce_to_dropper_ip_version;
            assign ip_ihl                      = m_roce_to_dropper_ip_ihl;
            assign ip_dscp                     = m_roce_to_dropper_ip_dscp;
            assign ip_ecn                      = m_roce_to_dropper_ip_ecn;
            assign ip_identification           = m_roce_to_dropper_ip_identification;
            assign ip_flags                    = m_roce_to_dropper_ip_flags;
            assign ip_fragment_offset          = m_roce_to_dropper_ip_fragment_offset;
            assign ip_ttl                      = m_roce_to_dropper_ip_ttl;
            assign ip_protocol                 = m_roce_to_dropper_ip_protocol;
            assign ip_header_checksum          = m_roce_to_dropper_ip_header_checksum;
            assign ip_source_ip                = m_roce_to_dropper_ip_source_ip;
            assign ip_dest_ip                  = m_roce_to_dropper_ip_dest_ip;
            assign udp_source_port             = m_roce_to_dropper_udp_source_port;
            assign udp_dest_port               = m_roce_to_dropper_udp_dest_port;
            assign udp_length                  = m_roce_to_dropper_udp_length;
            assign udp_checksum                = m_roce_to_dropper_udp_checksum;
            // AXIS payload
            assign m_roce_payload_axis_tdata              = m_roce_to_dropper_payload_axis_tdata;
            assign m_roce_payload_axis_tkeep              = m_roce_to_dropper_payload_axis_tkeep;
            assign m_roce_payload_axis_tvalid             = m_roce_to_dropper_payload_axis_tvalid;
            assign m_roce_to_dropper_payload_axis_tready  = m_roce_payload_axis_tready;
            assign m_roce_payload_axis_tlast              = m_roce_to_dropper_payload_axis_tlast;
            assign m_roce_payload_axis_tuser              = m_roce_to_dropper_payload_axis_tuser;

        end
    endgenerate

    generate
        if (ENABLE_SIM_PACKET_DROP_RX) begin

            reg [31:0] random_number = 32'b0;
            wire    drop_ack_packet;
            integer test_value = 32'h7c000000;

            // extract random integer
            always @(posedge clk) begin
                if (m_roce_rx_to_dropper_bth_valid & m_roce_rx_to_dropper_aeth_valid) begin
                    random_number <= $random;
                end
            end


            assign drop_ack_packet = (random_number > test_value);

            assign m_roce_bth_valid                = m_roce_rx_to_dropper_bth_valid & drop_ack_packet;
            assign m_roce_rx_to_dropper_bth_ready  = m_roce_bth_ready;
            assign m_roce_bth_op_code              = m_roce_rx_to_dropper_bth_op_code;
            assign m_roce_bth_p_key                = m_roce_rx_to_dropper_bth_p_key;
            assign m_roce_bth_psn                  = m_roce_rx_to_dropper_bth_psn;
            assign m_roce_bth_dest_qp              = m_roce_rx_to_dropper_bth_dest_qp;
            assign m_roce_bth_ack_req              = m_roce_rx_to_dropper_bth_ack_req;
            assign m_roce_aeth_valid               = m_roce_rx_to_dropper_aeth_valid & drop_ack_packet;
            assign m_roce_rx_to_dropper_aeth_ready = m_roce_aeth_ready;
            assign m_roce_aeth_syndrome            = m_roce_rx_to_dropper_aeth_syndrome;
            assign m_roce_aeth_msn                 = m_roce_rx_to_dropper_aeth_msn;


        end else begin
            assign m_roce_bth_valid                = m_roce_rx_to_dropper_bth_valid;
            assign m_roce_rx_to_dropper_bth_ready  = m_roce_bth_ready;
            assign m_roce_bth_op_code              = m_roce_rx_to_dropper_bth_op_code;
            assign m_roce_bth_p_key                = m_roce_rx_to_dropper_bth_p_key;
            assign m_roce_bth_psn                  = m_roce_rx_to_dropper_bth_psn;
            assign m_roce_bth_dest_qp              = m_roce_rx_to_dropper_bth_dest_qp;
            assign m_roce_bth_ack_req              = m_roce_rx_to_dropper_bth_ack_req;
            assign m_roce_aeth_valid               = m_roce_rx_to_dropper_aeth_valid;
            assign m_roce_rx_to_dropper_aeth_ready = m_roce_aeth_ready;
            assign m_roce_aeth_syndrome            = m_roce_rx_to_dropper_aeth_syndrome;
            assign m_roce_aeth_msn                 = m_roce_rx_to_dropper_aeth_msn;
        end
    endgenerate

    RoCE_udp_tx #(
    .DATA_WIDTH(DATA_WIDTH)
    ) RoCE_udp_tx_instance (
        .clk                            (clk),
        .rst                            (rst),
        .s_roce_bth_valid               (roce_bth_valid),
        .s_roce_bth_ready               (roce_bth_ready),
        .s_roce_bth_op_code             (roce_bth_op_code),
        .s_roce_bth_p_key               (roce_bth_p_key),
        .s_roce_bth_psn                 (roce_bth_psn),
        .s_roce_bth_dest_qp             (roce_bth_dest_qp),
        .s_roce_bth_ack_req             (roce_bth_ack_req),
        .s_roce_reth_valid              (roce_reth_valid),
        .s_roce_reth_ready              (roce_reth_ready),
        .s_roce_reth_v_addr             (roce_reth_v_addr),
        .s_roce_reth_r_key              (roce_reth_r_key),
        .s_roce_reth_length             (roce_reth_length),
        .s_roce_immdh_valid             (roce_immdh_valid),
        .s_roce_immdh_ready             (roce_immdh_ready),
        .s_roce_immdh_data              (roce_immdh_data),
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
        .s_ip_dest_ip                   (ip_dest_ip),
        .s_udp_source_port              (ROCE_UDP_TX_SOURCE_PORT),
        .s_udp_dest_port                (RoCE_udp_port),
        .s_udp_length                   (udp_length),
        .s_udp_checksum                 (16'h0000),
        .s_roce_payload_axis_tdata      (m_roce_payload_axis_tdata),
        .s_roce_payload_axis_tkeep      (m_roce_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid     (m_roce_payload_axis_tvalid),
        .s_roce_payload_axis_tready     (m_roce_payload_axis_tready),
        .s_roce_payload_axis_tlast      (m_roce_payload_axis_tlast),
        .s_roce_payload_axis_tuser      (m_roce_payload_axis_tuser),
        .m_udp_hdr_valid                (roce_tx_udp_hdr_valid),
        .m_udp_hdr_ready                (roce_tx_udp_hdr_ready),
        .m_eth_dest_mac                 (roce_tx_eth_dest_mac),
        .m_eth_src_mac                  (roce_tx_eth_src_mac),
        .m_eth_type                     (roce_tx_eth_type),
        .m_ip_version                   (roce_tx_ip_version),
        .m_ip_ihl                       (roce_tx_ip_ihl),
        .m_ip_dscp                      (roce_tx_ip_dscp),
        .m_ip_ecn                       (roce_tx_ip_ecn),
        .m_ip_length                    (roce_tx_ip_length),
        .m_ip_identification            (roce_tx_ip_identification),
        .m_ip_flags                     (roce_tx_ip_flags),
        .m_ip_fragment_offset           (roce_tx_ip_fragment_offset),
        .m_ip_ttl                       (roce_tx_ip_ttl),
        .m_ip_protocol                  (roce_tx_ip_protocol),
        .m_ip_header_checksum           (roce_tx_ip_header_checksum),
        .m_ip_source_ip                 (roce_tx_ip_source_ip),
        .m_ip_dest_ip                   (roce_tx_ip_dest_ip),
        .m_udp_source_port              (roce_tx_udp_source_port),
        .m_udp_dest_port                (roce_tx_udp_dest_port),
        .m_udp_length                   (roce_tx_udp_length),
        .m_udp_checksum                 (roce_tx_udp_checksum),
        .m_udp_payload_axis_tdata       (roce_tx_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep       (roce_tx_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid      (roce_tx_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready      (roce_tx_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast       (roce_tx_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser       (roce_tx_udp_payload_axis_tuser),
        .busy                           (busy),
        .error_payload_early_termination(error_payload_early_termination),
        .RoCE_udp_port(RoCE_udp_port)
    );

    RoCE_udp_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .ENABLE_ICRC_CHECK(1'b0)
    ) RoCE_udp_rx_instance (
        .clk(clk),
        .rst(rst),
        .s_udp_hdr_valid(rx_udp_RoCE_hdr_valid),
        .s_udp_hdr_ready(rx_udp_RoCE_hdr_ready),
        .s_eth_dest_mac(rx_udp_RoCE_eth_dest_mac),
        .s_eth_src_mac(rx_udp_RoCE_eth_src_mac),
        .s_eth_type(rx_udp_RoCE_eth_type),
        .s_ip_version(rx_udp_RoCE_ip_version),
        .s_ip_ihl(rx_udp_RoCE_ip_ihl),
        .s_ip_dscp(rx_udp_RoCE_ip_dscp),
        .s_ip_ecn(rx_udp_RoCE_ip_ecn),
        .s_ip_length(rx_udp_RoCE_ip_length),
        .s_ip_identification(rx_udp_RoCE_ip_identification),
        .s_ip_flags(rx_udp_RoCE_ip_flags),
        .s_ip_fragment_offset(rx_udp_RoCE_ip_fragment_offset),
        .s_ip_ttl(rx_udp_RoCE_ip_ttl),
        .s_ip_protocol(rx_udp_RoCE_ip_protocol),
        .s_ip_header_checksum(rx_udp_RoCE_ip_header_checksum),
        .s_ip_source_ip(rx_udp_RoCE_ip_source_ip),
        .s_ip_dest_ip(rx_udp_RoCE_ip_dest_ip),
        .s_udp_source_port(rx_udp_RoCE_source_port),
        .s_udp_dest_port(rx_udp_RoCE_dest_port),
        .s_udp_length(rx_udp_RoCE_length),
        .s_udp_checksum(rx_udp_RoCE_checksum),
        .s_roce_computed_icrc(32'hDEADBEEF),
        .s_udp_payload_axis_tdata(rx_udp_RoCE_payload_axis_tdata),
        .s_udp_payload_axis_tkeep(rx_udp_RoCE_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(rx_udp_RoCE_payload_axis_tvalid),
        .s_udp_payload_axis_tready(rx_udp_RoCE_payload_axis_tready),
        .s_udp_payload_axis_tlast(rx_udp_RoCE_payload_axis_tlast),
        .s_udp_payload_axis_tuser(rx_udp_RoCE_payload_axis_tuser),
        .m_roce_bth_valid(m_roce_rx_to_dropper_bth_valid),
        .m_roce_bth_ready(1'b1),
        .m_roce_bth_op_code(m_roce_rx_to_dropper_bth_op_code),
        .m_roce_bth_p_key(m_roce_rx_to_dropper_bth_p_key),
        .m_roce_bth_psn(m_roce_rx_to_dropper_bth_psn),
        .m_roce_bth_dest_qp(m_roce_rx_to_dropper_bth_dest_qp),
        .m_roce_bth_ack_req(m_roce_rx_to_dropper_bth_ack_req),
        .m_roce_aeth_valid(m_roce_rx_to_dropper_aeth_valid),
        .m_roce_aeth_ready(1'b1),
        .m_roce_aeth_syndrome(m_roce_rx_to_dropper_aeth_syndrome),
        .m_roce_aeth_msn(m_roce_rx_to_dropper_aeth_msn),
        .m_eth_dest_mac(),
        .m_eth_src_mac(),
        .m_eth_type(),
        .m_ip_version(),
        .m_ip_ihl(),
        .m_ip_dscp(),
        .m_ip_ecn(),
        .m_ip_identification(),
        .m_ip_flags(),
        .m_ip_fragment_offset(),
        .m_ip_ttl(),
        .m_ip_protocol(),
        .m_ip_header_checksum(),
        .m_ip_source_ip(),
        .m_ip_dest_ip(),
        .m_udp_source_port(),
        .m_udp_dest_port(),
        .m_udp_length(),
        .m_udp_checksum(),
        .busy(),
        .error_header_early_termination()
    );

    udp_RoCE_connection_manager_new #(
        .DATA_WIDTH(DATA_WIDTH),
        .LISTEN_UDP_PORT(16'h4321)
    ) udp_RoCE_connection_manager_instance (
        .clk(clk),
        .rst(rst),

        .s_udp_hdr_valid(rx_udp_cm_hdr_valid),
        .s_udp_hdr_ready(rx_udp_cm_hdr_ready),
        .s_udp_source_port(rx_udp_cm_source_port),
        .s_udp_dest_port(rx_udp_cm_dest_port),
        .s_udp_length(rx_udp_cm_length),
        .s_udp_checksum(rx_udp_cm_checksum),
        .s_udp_payload_axis_tdata(rx_udp_cm_payload_axis_tdata),
        .s_udp_payload_axis_tkeep(rx_udp_cm_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(rx_udp_cm_payload_axis_tvalid),
        .s_udp_payload_axis_tready(rx_udp_cm_payload_axis_tready),
        .s_udp_payload_axis_tlast(rx_udp_cm_payload_axis_tlast),
        .s_udp_payload_axis_tuser(rx_udp_cm_payload_axis_tuser),

        .m_udp_hdr_valid(tx_udp_cm_hdr_valid),
        .m_udp_hdr_ready(tx_udp_cm_hdr_ready),
        .m_ip_source_ip(tx_udp_cm_ip_source_ip),
        .m_ip_dest_ip(tx_udp_cm_ip_dest_ip),
        .m_udp_source_port(tx_udp_cm_source_port),
        .m_udp_dest_port(tx_udp_cm_dest_port),
        .m_udp_length(tx_udp_cm_length),
        .m_udp_checksum(tx_udp_cm_checksum),
        .m_udp_payload_axis_tdata(tx_udp_cm_payload_axis_tdata),
        .m_udp_payload_axis_tkeep(tx_udp_cm_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(tx_udp_cm_payload_axis_tvalid),
        .m_udp_payload_axis_tready(tx_udp_cm_payload_axis_tready),
        .m_udp_payload_axis_tlast(tx_udp_cm_payload_axis_tlast),
        .m_udp_payload_axis_tuser(tx_udp_cm_payload_axis_tuser),

        .qp_init_valid(qp_init_valid),
        .qp_init_req_type(qp_init_req_type),
        .qp_init_r_key(qp_init_r_key),
        .qp_init_rem_qpn(qp_init_rem_qpn),
        .qp_init_loc_qpn(qp_init_loc_qpn),
        .qp_init_rem_psn(qp_init_rem_psn),
        .qp_init_loc_psn(qp_init_loc_psn),
        .qp_init_rem_base_addr(qp_init_rem_addr),
        .qp_init_rem_ip_addr(qp_init_rem_ip_addr),

        .qp_init_status_valid(qp_init_status_valid),
        .qp_init_status(qp_init_status),

        .m_metadata_valid     (txmeta_valid),
        .m_start_transfer     (txmeta_start_transfer),
        .m_txmeta_loc_qpn     (txmeta_loc_qpn),
        .m_txmeta_is_immediate(txmeta_is_immediate),
        .m_txmeta_tx_type     (txmeta_tx_type),
        .m_txmeta_dma_transfer(txmeta_dma_transfer),
        .m_txmeta_n_transfers (txmeta_n_transfers),
        .m_txmeta_frequency   (txmeta_frequency),

        .cfg_udp_source_port(16'h8765),
        .cfg_loc_ip_addr(loc_ip_addr),

        .busy()
    );

    /*
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
    .s_ip_dest_ip                   (ip_dest_ip),
    */
    udp_arb_mux #(
        .S_COUNT(2),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) udp_arb_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_udp_hdr_valid          ({tx_udp_cm_hdr_valid, roce_tx_udp_hdr_valid}),
        .s_udp_hdr_ready          ({tx_udp_cm_hdr_ready, roce_tx_udp_hdr_ready}),
        .s_eth_dest_mac           ({48'd0, roce_tx_eth_dest_mac}),
        .s_eth_src_mac            ({48'd0, roce_tx_eth_src_mac}),
        .s_eth_type               ({16'd0, roce_tx_eth_type}),
        .s_ip_version             ({4'd4, roce_tx_ip_version}),
        .s_ip_ihl                 ({4'd0, roce_tx_ip_ihl}),
        .s_ip_dscp                ({6'd0, roce_tx_ip_dscp}),
        .s_ip_ecn                 ({2'd0, roce_tx_ip_ecn}),
        .s_ip_identification      ({16'd0, roce_tx_ip_identification}),
        .s_ip_flags               ({3'b001, roce_tx_ip_flags}),
        .s_ip_fragment_offset     ({13'd0, roce_tx_ip_fragment_offset}),
        .s_ip_ttl                 ({8'h40, roce_tx_ip_ttl}),
        .s_ip_protocol            ({8'h11, roce_tx_ip_protocol}),
        .s_ip_header_checksum     ({16'd0, roce_tx_ip_header_checksum}),
        .s_ip_source_ip           ({loc_ip_addr, roce_tx_ip_source_ip}),
        .s_ip_dest_ip             ({tx_udp_cm_ip_dest_ip, roce_tx_ip_dest_ip}),
        .s_udp_source_port        ({tx_udp_cm_source_port, roce_tx_udp_source_port}),
        .s_udp_dest_port          ({tx_udp_cm_dest_port, roce_tx_udp_dest_port}),
        .s_udp_length             ({tx_udp_cm_length, roce_tx_udp_length}),
        .s_udp_checksum           ({tx_udp_cm_checksum, roce_tx_udp_checksum}),
        .s_udp_payload_axis_tdata ({tx_udp_cm_payload_axis_tdata, roce_tx_udp_payload_axis_tdata}),
        .s_udp_payload_axis_tkeep ({tx_udp_cm_payload_axis_tkeep, roce_tx_udp_payload_axis_tkeep}),
        .s_udp_payload_axis_tvalid({tx_udp_cm_payload_axis_tvalid, roce_tx_udp_payload_axis_tvalid}),
        .s_udp_payload_axis_tready({tx_udp_cm_payload_axis_tready, roce_tx_udp_payload_axis_tready}),
        .s_udp_payload_axis_tlast ({tx_udp_cm_payload_axis_tlast, roce_tx_udp_payload_axis_tlast}),
        .s_udp_payload_axis_tid   ({0,0}),
        .s_udp_payload_axis_tdest ({0,0}),
        .s_udp_payload_axis_tuser ({tx_udp_cm_payload_axis_tuser, roce_tx_udp_payload_axis_tuser}),

        .m_udp_hdr_valid(m_udp_hdr_valid),
        .m_udp_hdr_ready(m_udp_hdr_ready),
        .m_eth_dest_mac(m_eth_dest_mac),
        .m_eth_src_mac(m_eth_src_mac),
        .m_eth_type(m_eth_type),
        .m_ip_version(m_ip_version),
        .m_ip_ihl(m_ip_ihl),
        .m_ip_dscp(m_ip_dscp),
        .m_ip_ecn(m_ip_ecn),
        .m_ip_length(m_ip_length),
        .m_ip_identification(m_ip_identification),
        .m_ip_flags(m_ip_flags),
        .m_ip_fragment_offset(m_ip_fragment_offset),
        .m_ip_ttl(m_ip_ttl),
        .m_ip_protocol(m_ip_protocol),
        .m_ip_header_checksum(m_ip_header_checksum),
        .m_ip_source_ip(m_ip_source_ip),
        .m_ip_dest_ip(m_ip_dest_ip),
        .m_udp_source_port(m_udp_source_port),
        .m_udp_dest_port(m_udp_dest_port),
        .m_udp_length(m_udp_length),
        .m_udp_checksum(m_udp_checksum),
        .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep(m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tid(),
        .m_udp_payload_axis_tdest(),
        .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser)
    );

    wire [63:0] tot_time_wo_ack_avg;
    wire [63:0] tot_time_avg;
    wire [63:0] transfer_time_tot;
    wire [63:0] transfer_time_single;
    wire [63:0] latency_first_packet;
    wire [63:0] latency_last_packet;

    RoCE_latency_eval RoCE_latency_eval_instance (
        .clk                    (clk),
        .rst                    (rst),
        .start_i                (start_transfer),
        .s_roce_rx_bth_valid    (m_roce_rx_to_dropper_bth_valid),
        .s_roce_rx_bth_op_code  (m_roce_rx_to_dropper_bth_op_code),
        .s_roce_rx_bth_p_key    (m_roce_rx_to_dropper_bth_p_key),
        .s_roce_rx_bth_psn      (m_roce_rx_to_dropper_bth_psn),
        .s_roce_rx_bth_dest_qp  (m_roce_rx_to_dropper_bth_dest_qp),
        .s_roce_rx_bth_ack_req  (m_roce_rx_to_dropper_bth_ack_req),
        .s_roce_rx_aeth_valid   (m_roce_rx_to_dropper_aeth_valid),
        .s_roce_rx_aeth_syndrome(m_roce_rx_to_dropper_aeth_syndrome),
        .s_roce_rx_aeth_msn     (m_roce_rx_to_dropper_aeth_msn),
        .s_roce_tx_bth_valid    (m_roce_to_retrans_bth_valid & m_roce_to_retrans_bth_ready),
        .s_roce_tx_bth_op_code  (m_roce_to_retrans_bth_op_code),
        .s_roce_tx_bth_p_key    (m_roce_to_retrans_bth_p_key),
        .s_roce_tx_bth_psn      (m_roce_to_retrans_bth_psn),
        .s_roce_tx_bth_dest_qp  (m_roce_to_retrans_bth_dest_qp),
        .s_roce_tx_bth_ack_req  (m_roce_to_retrans_bth_ack_req),
        .s_roce_tx_reth_valid   (m_roce_to_retrans_reth_valid & m_roce_to_retrans_bth_ready),
        .s_roce_tx_reth_v_addr  (m_roce_to_retrans_reth_v_addr),
        .s_roce_tx_reth_r_key   (m_roce_to_retrans_reth_r_key),
        .s_roce_tx_reth_length  (m_roce_to_retrans_reth_length),
        .transfer_time_tot      (transfer_time_tot),
        .transfer_time_single   (transfer_time_single),
        .latency_first_packet   (latency_first_packet),
        .latency_last_packet    (latency_last_packet)
    );

    axis_handshake_monitor #(
    .window_width(27)
    ) axis_handshake_monitor_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(m_roce_payload_axis_tvalid),
        .m_axis_tready(m_roce_payload_axis_tready),
        .n_valid_up(RoCE_tx_n_valid_up),
        .n_ready_up(RoCE_tx_n_ready_up),
        .n_both_up(RoCE_tx_n_both_up)
    );

    RoCE_qp_state_module #(
        .MAX_QUEUE_PAIRS(MAX_QUEUE_PAIRS),
        .REM_ADDR_WIDTH(16)
    ) RoCE_qp_state_module_instance (
        .clk                    (clk),
        .rst                    (rst),
        .rst_qp                 (start_transfer),
        // open qp
        .qp_init_valid          (qp_init_valid),
        .qp_init_req_type       (qp_init_req_type),
        .qp_init_r_key          (qp_init_r_key),
        .qp_init_rem_qpn        (qp_init_rem_qpn),
        .qp_init_loc_qpn        (qp_init_loc_qpn),
        .qp_init_rem_psn        (qp_init_rem_psn),
        .qp_init_loc_psn        (qp_init_loc_psn),
        .qp_init_rem_ip_addr    (qp_init_rem_ip_addr),
        .qp_init_rem_addr       (qp_init_rem_addr),
        //open status
        .qp_init_status_valid(qp_init_status_valid),
        .qp_init_status(qp_init_status),
        // close qp if transfer did not succed
        .qp_close_valid(qp_close_params_valid),
        .qp_close_loc_qpn(qp_close_params[79 :56 ]), // loc_qpn
        // QP request
        .qp_context_req         (m_qp_context_req),
        .qp_local_qpn_req       (m_qp_local_qpn_req),
        .qp_req_context_valid   (s_qp_req_context_valid),
        .qp_req_state           (s_qp_req_state),
        .qp_req_r_key           (s_qp_req_r_key),
        .qp_req_rem_qpn         (s_qp_req_rem_qpn),
        .qp_req_loc_qpn         (s_qp_req_loc_qpn),
        .qp_req_rem_psn         (s_qp_req_rem_psn),
        .qp_req_loc_psn         (s_qp_req_loc_psn),
        .qp_req_rem_ip_addr     (s_qp_req_rem_ip_addr),
        .qp_req_rem_addr        (s_qp_req_rem_addr),

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

        .s_dma_meta_valid       (s_dma_meta_valid & s_dma_meta_ready),
        .s_meta_dma_length      (s_dma_length),
        .s_meta_rem_qpn         (s_rem_qpn),
        .s_meta_loc_qpn         (s_loc_qpn),
        .s_meta_rem_psn         (s_rem_psn),

        .s_roce_rx_bth_valid    (m_roce_rx_to_dropper_bth_valid & m_roce_rx_to_dropper_bth_ready),
        .s_roce_rx_bth_ready    (),
        .s_roce_rx_bth_op_code  (m_roce_rx_to_dropper_bth_op_code),
        .s_roce_rx_bth_p_key    (m_roce_rx_to_dropper_bth_p_key),
        .s_roce_rx_bth_psn      (m_roce_rx_to_dropper_bth_psn),
        .s_roce_rx_bth_dest_qp  (m_roce_rx_to_dropper_bth_dest_qp),
        .s_roce_rx_bth_ack_req  (m_roce_rx_to_dropper_bth_ack_req),
        .s_roce_rx_aeth_valid   (m_roce_rx_to_dropper_aeth_valid),
        .s_roce_rx_aeth_ready   (m_roce_rx_to_dropper_aeth_ready),
        .s_roce_rx_aeth_syndrome(m_roce_rx_to_dropper_aeth_syndrome),
        .s_roce_rx_aeth_msn     (m_roce_rx_to_dropper_aeth_msn),
        .last_acked_psn         (last_acked_psn),
        .stop_transfer          (stop_transfer_nack),
        .pmtu(pmtu)
    );



    reg [23:0] wr_req_loc_qp;
    reg [31:0] wr_req_dma_length;
    reg        wr_req_is_immediate;
    reg        wr_req_tx_type;
    reg [31:0] messages_to_trasnfer;
    reg [27:0] address_offset;

    reg [31:0] txmeta_frequency_reg;
    reg [63:0] transmit_wait_ctnr; // wait counter trasnfering at a given frequency

    reg transfer_ongoing;

    reg s_wr_req_valid_reg = 1'b0, s_wr_req_valid_next;

    // Work request
    wire         s_wr_req_valid;
    wire         s_wr_req_ready;

    assign s_wr_req_valid = s_wr_req_valid_reg;

    wire         s_wr_req_tx_type; // 0 WRITE, 1 SEND
    wire         s_wr_req_is_immediate;
    wire [23:0]  s_wr_req_loc_qp;
    wire [63:0]  s_wr_req_addr_offset;
    wire [31:0]  s_wr_req_dma_length; // for each transfer

    assign s_wr_req_tx_type = wr_req_tx_type; // 0 WRITE, 1 SEND
    assign s_wr_req_is_immediate = wr_req_is_immediate;
    assign s_wr_req_loc_qp = wr_req_loc_qp;
    assign s_wr_req_addr_offset = address_offset;
    assign s_wr_req_dma_length = wr_req_dma_length; // for each transfer

    // Dummy work request producer
    always @* begin

        s_wr_req_valid_next = s_wr_req_valid_reg && !s_wr_req_ready;

        // loop over until all requests are sent
        if (s_wr_req_ready && ~s_wr_req_valid_reg) begin
            if (messages_to_trasnfer > 0 && transmit_wait_ctnr == 0) begin
                s_wr_req_valid_next  = 1'b1;
            end else begin
                s_wr_req_valid_next = 1'b0;
            end
        end else begin
            s_wr_req_valid_next = 1'b0;
        end
    end

    always @(posedge clk) begin

        if (rst)  begin
            transmit_wait_ctnr <= {64{1'b1}};
            wr_req_loc_qp         <= 0;
            wr_req_is_immediate   <= 0;
            wr_req_tx_type        <= 0;
            wr_req_dma_length     <= 0;
            messages_to_trasnfer  <= 0;
            txmeta_frequency_reg  <= 0;
            address_offset        <= 0;
            transfer_ongoing      <= 0;
            s_wr_req_valid_reg    <= 0;

        end else begin
            // load request only
            if (txmeta_valid && txmeta_start_transfer && ~transfer_ongoing) begin
                wr_req_loc_qp         <= txmeta_loc_qpn;
                wr_req_is_immediate   <= txmeta_is_immediate;
                wr_req_tx_type        <= txmeta_tx_type;
                wr_req_dma_length     <= txmeta_dma_transfer;
                messages_to_trasnfer  <= txmeta_n_transfers;
                txmeta_frequency_reg  <= txmeta_frequency;
                address_offset        <= 28'd0;
                transfer_ongoing      <= 1'b1;
            end

            if (txmeta_valid && txmeta_start_transfer && ~transfer_ongoing) begin
                transmit_wait_ctnr    <= FREQ_CLK_COUNTER_VALUES[txmeta_frequency[4:0]];
            end else if (transmit_wait_ctnr == 64'd0) begin
                if (s_wr_req_ready) begin
                    transmit_wait_ctnr    <= FREQ_CLK_COUNTER_VALUES[txmeta_frequency_reg[4:0]];
                end else begin
                    transmit_wait_ctnr <= transmit_wait_ctnr;
                end
            end else if (messages_to_trasnfer > 0) begin
                transmit_wait_ctnr <= transmit_wait_ctnr - 64'd1;
            end else begin
                transmit_wait_ctnr <= transmit_wait_ctnr;
            end

            // loop over until all requests are sent
            if (messages_to_trasnfer > 0) begin
                if (s_wr_req_valid && s_wr_req_ready) begin
                    messages_to_trasnfer <= messages_to_trasnfer - 32'd1;
                    if (wr_req_dma_length <= 32'h10000000) begin
                        address_offset <= address_offset + wr_req_dma_length[27:0];
                    end else begin
                        address_offset <= 28'd0;
                    end
                end
            end else begin
                transfer_ongoing    <= 1'b0;
            end

            s_wr_req_valid_reg <= s_wr_req_valid_next;
        end
    end

    always @(posedge clk) begin
        if (stop_transfer) begin
            last_acked_psn_reg <= last_acked_psn;
        end
    end



    RoCE_simple_work_queue #(
        .MAX_QUEUE_PAIRS(MAX_QUEUE_PAIRS),
        .QUEUE_LENGTH(32)
    ) RoCE_simple_work_queue_instance (
        .clk(clk),
        .rst(rst),

        .s_wr_req_valid       (s_wr_req_valid),
        .s_wr_req_ready       (s_wr_req_ready),
        .s_wr_req_loc_qp      (s_wr_req_loc_qp),
        .s_wr_req_dma_length  (s_wr_req_dma_length),
        .s_wr_req_addr_offset (s_wr_req_addr_offset),
        .s_wr_req_is_immediate(s_wr_req_is_immediate),
        .s_wr_req_tx_type     (s_wr_req_tx_type),

        .m_qp_context_req     (m_qp_context_req),
        .m_qp_local_qpn_req   (m_qp_local_qpn_req),
        .s_qp_context_valid   (s_qp_req_context_valid),
        .s_qp_state           (s_qp_req_state),
        .s_qp_r_key           (s_qp_req_r_key),
        .s_qp_rem_qpn         (s_qp_req_rem_qpn),
        .s_qp_loc_qpn         (s_qp_req_loc_qpn),
        .s_qp_rem_psn         (s_qp_req_rem_psn),
        .s_qp_loc_psn         (s_qp_req_loc_psn),
        .s_qp_rem_ip_addr     (s_qp_req_rem_ip_addr),
        .s_qp_rem_addr        (s_qp_req_rem_addr),

        .m_dma_meta_valid     (s_dma_meta_valid),
        .m_dma_meta_ready     (s_dma_meta_ready),
        .m_dma_length         (s_dma_length),
        .m_rem_qpn            (s_rem_qpn),
        .m_loc_qpn            (s_loc_qpn),
        .m_rem_psn            (s_rem_psn),
        .m_r_key              (s_r_key),
        .m_rem_ip_addr        (s_rem_ip_addr),
        .m_rem_addr           (s_rem_addr),
        .m_is_immediate       (s_is_immediate),
        .m_trasfer_type       (s_trasfer_type)
    );

    generate
        if (DEBUG) begin
            vio_throughput VIO_roce_throughput (
                .clk(clk),
                .probe_in0(RoCE_tx_n_valid_up),
                .probe_in1(RoCE_tx_n_ready_up),
                .probe_in2(RoCE_tx_n_both_up),
                .probe_in3(latency_first_packet),
                .probe_in4(latency_last_packet),
                .probe_in5(transfer_time_tot),
                .probe_in6(transfer_time_single),
                .probe_in7(last_acked_psn_reg),
                .probe_in8(last_acked_psn),
                .probe_in9(last_buffered_psn),
                .probe_in10(psn_diff),
                .probe_in11(used_memory),
                .probe_out0(n_transfers),
                .probe_out1(en_retrans)
            );

            vio_qp_state_spy VIO_roce_qp_state_spy (
                .clk(clk),
                .probe_in0 (s_qp_spy_context_valid),
                .probe_in1 (s_qp_spy_state),
                .probe_in2 (s_qp_spy_r_key),
                .probe_in3 (s_qp_spy_rem_qpn),
                .probe_in4 (s_qp_spy_loc_qpn),
                .probe_in5 (s_qp_spy_rem_psn),
                .probe_in6 (s_qp_spy_rem_acked_psn),
                .probe_in7 (s_qp_spy_loc_psn),
                .probe_in8 (s_qp_spy_rem_ip_addr),
                .probe_in9 (s_qp_spy_rem_addr),
                .probe_in10(s_qp_spy_syndrome),
                .probe_out0(m_qp_context_spy),
                .probe_out1(m_qp_local_qpn_spy)
            );

            /*
      ila_axis ila_roce_payload_tx(
        .clk(clk),
        .probe0(m_roce_payload_axis_tdata),
        .probe1(m_roce_payload_axis_tkeep),
        .probe2(m_roce_payload_axis_tvalid),
        .probe3(m_roce_payload_axis_tready),
        .probe4(m_roce_payload_axis_tlast),
        .probe5(m_roce_payload_axis_tuser)
      );

      ila_axis ila_udp_payload_tx(
        .clk(clk),
        .probe0(m_udp_payload_axis_tdata),
        .probe1(m_udp_payload_axis_tkeep),
        .probe2(m_udp_payload_axis_tvalid),
        .probe3(m_udp_payload_axis_tready),
        .probe4(m_udp_payload_axis_tlast),
        .probe5(m_udp_payload_axis_tuser)
      );
      */
        end else begin
            assign n_transfers = 1;
            assign en_retrans  = 1'b1;
        end
    endgenerate


endmodule

`resetall
