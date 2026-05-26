module udp_complete_opt #(
  // Width of AXI stream interfaces in bits
  parameter DATA_WIDTH = 8,
  // Propagate tkeep signal
  // If disabled, tkeep assumed to be 1'b1
  parameter KEEP_ENABLE = (DATA_WIDTH > 8),
  // tkeep signal width (words per cycle)
  parameter KEEP_WIDTH = (DATA_WIDTH / 8),
  // ARP paramters
  parameter ARP_CACHE_ADDR_WIDTH = 9,
  parameter ARP_REQUEST_RETRY_COUNT = 4,
  parameter ARP_REQUEST_RETRY_INTERVAL = 125000000 * 2,
  parameter ARP_REQUEST_TIMEOUT = 125000000 * 30,
  // ETH parameters
  parameter ENABLE_DOT1Q_HEADER = 0,
  // Pipelined IP header checksum computation
  parameter HEADER_CHECKSUM_PIPELINED = 0,
  // compute ICRC for RoCE packets
  parameter ROCE_ICRC_INSERTER = 1
) (
  input wire clk,
  input wire rst,

  /*
   * AXIS frame input
   */
  input  wire [DATA_WIDTH-1:0] s_network_axis_tdata,
  input  wire [KEEP_WIDTH-1:0] s_network_axis_tkeep,
  input  wire                  s_network_axis_tvalid,
  output wire                  s_network_axis_tready,
  input  wire                  s_network_axis_tlast,
  input  wire                  s_network_axis_tuser,

  /*
   * AXIS frame output
   */
  output wire [DATA_WIDTH-1:0] m_network_axis_tdata,
  output wire [KEEP_WIDTH-1:0] m_network_axis_tkeep,
  output wire                  m_network_axis_tvalid,
  input  wire                  m_network_axis_tready,
  output wire                  m_network_axis_tlast,
  output wire [           1:0] m_network_axis_tuser,

  /*
   * UDP frame input
   */
  input  wire                      s_udp_hdr_valid,
  output wire                      s_udp_hdr_ready,
  input  wire [              47:0] s_udp_eth_dest_mac,
  input  wire [              47:0] s_udp_eth_src_mac,
  input  wire [              15:0] s_udp_eth_type,
  input  wire [               3:0] s_udp_ip_version,
  input  wire [               3:0] s_udp_ip_ihl,
  input  wire [               5:0] s_udp_ip_dscp,
  input  wire [               1:0] s_udp_ip_ecn,
  input  wire [              15:0] s_udp_ip_identification,
  input  wire [               2:0] s_udp_ip_flags,
  input  wire [              12:0] s_udp_ip_fragment_offset,
  input  wire [               7:0] s_udp_ip_ttl,
  input  wire [              15:0] s_udp_ip_header_checksum,
  input  wire [              31:0] s_udp_ip_source_ip,
  input  wire [              31:0] s_udp_ip_dest_ip,
  input  wire [              15:0] s_udp_source_port,
  input  wire [              15:0] s_udp_dest_port,
  input  wire [              15:0] s_udp_length,
  input  wire [              15:0] s_udp_checksum,
  input  wire [DATA_WIDTH - 1 : 0] s_udp_payload_axis_tdata,
  input  wire [KEEP_WIDTH - 1 : 0] s_udp_payload_axis_tkeep,
  input  wire                      s_udp_payload_axis_tvalid,
  output wire                      s_udp_payload_axis_tready,
  input  wire                      s_udp_payload_axis_tlast,
  input  wire                      s_udp_payload_axis_tuser,

  /*
   * UDP frame output
   */
  output wire                      m_udp_hdr_valid,
  input  wire                      m_udp_hdr_ready,
  output wire [              47:0] m_udp_eth_dest_mac,
  output wire [              47:0] m_udp_eth_src_mac,
  output wire [              15:0] m_udp_eth_type,
  output wire [               3:0] m_udp_ip_version,
  output wire [               3:0] m_udp_ip_ihl,
  output wire [               5:0] m_udp_ip_dscp,
  output wire [               1:0] m_udp_ip_ecn,
  output wire [              15:0] m_udp_ip_length,
  output wire [              15:0] m_udp_ip_identification,
  output wire [               2:0] m_udp_ip_flags,
  output wire [              12:0] m_udp_ip_fragment_offset,
  output wire [               7:0] m_udp_ip_ttl,
  output wire [               7:0] m_udp_ip_protocol,
  output wire [              15:0] m_udp_ip_header_checksum,
  output wire [              31:0] m_udp_ip_source_ip,
  output wire [              31:0] m_udp_ip_dest_ip,
  output wire [              15:0] m_udp_source_port,
  output wire [              15:0] m_udp_dest_port,
  output wire [              15:0] m_udp_length,
  output wire [              15:0] m_udp_checksum,
  output wire [DATA_WIDTH - 1 : 0] m_udp_payload_axis_tdata,
  output wire [KEEP_WIDTH - 1 : 0] m_udp_payload_axis_tkeep,
  output wire                      m_udp_payload_axis_tvalid,
  input  wire                      m_udp_payload_axis_tready,
  output wire                      m_udp_payload_axis_tlast,
  output wire                      m_udp_payload_axis_tuser,

  input wire [47:0] local_mac_addr,
  input wire [31:0] local_ip_addr,
  input wire [31:0] gateway_ip,
  input wire [31:0] subnet_mask,
  input wire        clear_arp_cache,
  input wire [15:0] RoCE_udp_port,

  output wire tx_error_arp_failed

);

  // RX Ethernet frame
  wire                    s_rx_eth_hdr_valid;
  wire                    s_rx_eth_hdr_ready;
  wire [            47:0] s_rx_eth_dest_mac;
  wire [            47:0] s_rx_eth_src_mac;
  wire [            15:0] s_rx_eth_type;
  wire [DATA_WIDTH - 1:0] s_rx_eth_payload_axis_tdata;
  wire [KEEP_WIDTH - 1:0] s_rx_eth_payload_axis_tkeep;
  wire                    s_rx_eth_payload_axis_tvalid;
  wire                    s_rx_eth_payload_axis_tready;
  wire                    s_rx_eth_payload_axis_tlast;
  wire                    s_rx_eth_payload_axis_tuser;

  // to ARP RX
  wire                    arp_rx_eth_hdr_valid;
  wire                    arp_rx_eth_hdr_ready;
  wire [            47:0] arp_rx_eth_dest_mac;
  wire [            47:0] arp_rx_eth_src_mac;
  wire [            15:0] arp_rx_eth_type;
  wire [  DATA_WIDTH-1:0] arp_rx_eth_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] arp_rx_eth_payload_axis_tkeep;
  wire                    arp_rx_eth_payload_axis_tvalid;
  wire                    arp_rx_eth_payload_axis_tready;
  wire                    arp_rx_eth_payload_axis_tlast;
  wire                    arp_rx_eth_payload_axis_tuser;

  // to ip RX
  wire                    ip_rx_eth_hdr_valid;
  wire                    ip_rx_eth_hdr_ready;
  wire [            47:0] ip_rx_eth_dest_mac;
  wire [            47:0] ip_rx_eth_src_mac;
  wire [            15:0] ip_rx_eth_type;
  wire [  DATA_WIDTH-1:0] ip_rx_eth_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] ip_rx_eth_payload_axis_tkeep;
  wire                    ip_rx_eth_payload_axis_tvalid;
  wire                    ip_rx_eth_payload_axis_tready;
  wire                    ip_rx_eth_payload_axis_tlast;
  wire                    ip_rx_eth_payload_axis_tuser;

  // IP RX frame
  wire                    s_rx_ip_hdr_valid;
  wire                    s_rx_ip_hdr_ready;
  wire [            47:0] s_rx_ip_eth_dest_mac;
  wire [            47:0] s_rx_ip_eth_src_mac;
  wire [            15:0] s_rx_ip_eth_type;
  wire [             3:0] s_rx_ip_version;
  wire [             3:0] s_rx_ip_ihl;
  wire [             5:0] s_rx_ip_dscp;
  wire [             1:0] s_rx_ip_ecn;
  wire [            15:0] s_rx_ip_length;
  wire [            15:0] s_rx_ip_identification;
  wire [             2:0] s_rx_ip_flags;
  wire [            12:0] s_rx_ip_fragment_offset;
  wire [             7:0] s_rx_ip_ttl;
  wire [             7:0] s_rx_ip_protocol;
  wire [            15:0] s_rx_ip_header_checksum;
  wire [            31:0] s_rx_ip_source_ip;
  wire [            31:0] s_rx_ip_dest_ip;
  wire [  DATA_WIDTH-1:0] s_rx_ip_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] s_rx_ip_payload_axis_tkeep;
  wire                    s_rx_ip_payload_axis_tvalid;
  wire                    s_rx_ip_payload_axis_tready;
  wire                    s_rx_ip_payload_axis_tlast;
  wire                    s_rx_ip_payload_axis_tuser;

  wire                    udp_rx_ip_hdr_valid;
  wire                    udp_rx_ip_hdr_ready;
  wire [            47:0] udp_rx_ip_eth_dest_mac;
  wire [            47:0] udp_rx_ip_eth_src_mac;
  wire [            15:0] udp_rx_ip_eth_type;
  wire [             3:0] udp_rx_ip_version;
  wire [             3:0] udp_rx_ip_ihl;
  wire [             5:0] udp_rx_ip_dscp;
  wire [             1:0] udp_rx_ip_ecn;
  wire [            15:0] udp_rx_ip_length;
  wire [            15:0] udp_rx_ip_identification;
  wire [             2:0] udp_rx_ip_flags;
  wire [            12:0] udp_rx_ip_fragment_offset;
  wire [             7:0] udp_rx_ip_ttl;
  wire [             7:0] udp_rx_ip_protocol;
  wire [            15:0] udp_rx_ip_header_checksum;
  wire [            31:0] udp_rx_ip_source_ip;
  wire [            31:0] udp_rx_ip_dest_ip;
  wire [  DATA_WIDTH-1:0] udp_rx_ip_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] udp_rx_ip_payload_axis_tkeep;
  wire                    udp_rx_ip_payload_axis_tvalid;
  wire                    udp_rx_ip_payload_axis_tready;
  wire                    udp_rx_ip_payload_axis_tlast;
  wire                    udp_rx_ip_payload_axis_tuser;

  wire                    icmp_rx_ip_hdr_valid;
  wire                    icmp_rx_ip_hdr_ready;
  wire [            47:0] icmp_rx_ip_eth_dest_mac;
  wire [            47:0] icmp_rx_ip_eth_src_mac;
  wire [            15:0] icmp_rx_ip_eth_type;
  wire [             3:0] icmp_rx_ip_version;
  wire [             3:0] icmp_rx_ip_ihl;
  wire [             5:0] icmp_rx_ip_dscp;
  wire [             1:0] icmp_rx_ip_ecn;
  wire [            15:0] icmp_rx_ip_length;
  wire [            15:0] icmp_rx_ip_identification;
  wire [             2:0] icmp_rx_ip_flags;
  wire [            12:0] icmp_rx_ip_fragment_offset;
  wire [             7:0] icmp_rx_ip_ttl;
  wire [             7:0] icmp_rx_ip_protocol;
  wire [            15:0] icmp_rx_ip_header_checksum;
  wire [            31:0] icmp_rx_ip_source_ip;
  wire [            31:0] icmp_rx_ip_dest_ip;
  wire [  DATA_WIDTH-1:0] icmp_rx_ip_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] icmp_rx_ip_payload_axis_tkeep;
  wire                    icmp_rx_ip_payload_axis_tvalid;
  wire                    icmp_rx_ip_payload_axis_tready;
  wire                    icmp_rx_ip_payload_axis_tlast;
  wire                    icmp_rx_ip_payload_axis_tuser;

  wire                    arp_request_valid;
  wire                    arp_request_ready;
  wire [            31:0] arp_request_ip;
  wire                    arp_response_valid;
  wire                    arp_response_ready;
  wire                    arp_response_error;
  wire [            47:0] arp_response_mac;

  // ARP RX 64-bit adapter output
  wire [            63:0] arp_rx_eth_payload_64_axis_tdata;
  wire [             7:0] arp_rx_eth_payload_64_axis_tkeep;
  wire                    arp_rx_eth_payload_64_axis_tvalid;
  wire                    arp_rx_eth_payload_64_axis_tready;
  wire                    arp_rx_eth_payload_64_axis_tlast;
  wire                    arp_rx_eth_payload_64_axis_tuser;

  // ARP TX eth header + 64-bit payload (from arp module)
  wire                    arp_tx_eth_hdr_valid;
  wire                    arp_tx_eth_hdr_ready;
  wire [            47:0] arp_tx_eth_dest_mac;
  wire [            47:0] arp_tx_eth_src_mac;
  wire [            15:0] arp_tx_eth_type;
  wire [            63:0] arp_tx_eth_payload_64_axis_tdata;
  wire [             7:0] arp_tx_eth_payload_64_axis_tkeep;
  wire                    arp_tx_eth_payload_64_axis_tvalid;
  wire                    arp_tx_eth_payload_64_axis_tready;
  wire                    arp_tx_eth_payload_64_axis_tlast;
  wire                    arp_tx_eth_payload_64_axis_tuser;

  // ICMP TX IP header (from icmp_echo_reply)
  wire                    icmp_tx_ip_hdr_valid;
  wire                    icmp_tx_ip_hdr_ready;
  wire [            47:0] icmp_tx_ip_eth_dest_mac;
  wire [            47:0] icmp_tx_ip_eth_src_mac;
  wire [            15:0] icmp_tx_ip_eth_type;
  wire [             3:0] icmp_tx_ip_version;
  wire [             3:0] icmp_tx_ip_ihl;
  wire [             5:0] icmp_tx_ip_dscp;
  wire [             1:0] icmp_tx_ip_ecn;
  wire [            15:0] icmp_tx_ip_length;
  wire [            15:0] icmp_tx_ip_identification;
  wire [             2:0] icmp_tx_ip_flags;
  wire [            12:0] icmp_tx_ip_fragment_offset;
  wire [             7:0] icmp_tx_ip_ttl;
  wire [             7:0] icmp_tx_ip_protocol;
  wire [            15:0] icmp_tx_ip_hdr_checksum;
  wire [            31:0] icmp_tx_ip_source_ip;
  wire [            31:0] icmp_tx_ip_dest_ip;
  wire                    icmp_tx_is_roce_packet;


  // ICMP TX eth header + payload (ip_eth_tx output)
  wire                    icmp_tx_eth_hdr_valid;
  wire          icmp_tx_eth_hdr_ready;
  wire [  47:0] icmp_tx_eth_dest_mac;
  wire [  47:0] icmp_tx_eth_src_mac;
  wire [  15:0] icmp_tx_eth_type;
  wire [  63:0] icmp_tx_eth_payload_64_axis_tdata;
  wire [  7 :0] icmp_tx_eth_payload_64_axis_tkeep;
  wire          icmp_tx_eth_payload_64_axis_tvalid;
  wire          icmp_tx_eth_payload_64_axis_tready;
  wire          icmp_tx_eth_payload_64_axis_tlast;
  wire          icmp_tx_eth_payload_64_axis_tuser;

  wire          icmp_arp_tx_eth_hdr_valid;
  wire          icmp_arp_tx_eth_hdr_ready;
  wire [  47:0] icmp_arp_tx_eth_dest_mac;
  wire [  47:0] icmp_arp_tx_eth_src_mac;
  wire [  15:0] icmp_arp_tx_eth_type;
  wire [  63:0] icmp_arp_tx_eth_payload_64_axis_tdata;
  wire [  7 :0] icmp_arp_tx_eth_payload_64_axis_tkeep;
  wire          icmp_arp_tx_eth_payload_64_axis_tvalid;
  wire          icmp_arp_tx_eth_payload_64_axis_tready;
  wire          icmp_arp_tx_eth_payload_64_axis_tlast;
  wire          icmp_arp_tx_eth_payload_64_axis_tuser;

  wire [  63          :0] m_icmp_arp_64_axis_tdata;
  wire [  7           :0] m_icmp_arp_64_axis_tkeep;
  wire                    m_icmp_arp_64_axis_tvalid;
  wire                    m_icmp_arp_64_axis_tready;
  wire                    m_icmp_arp_64_axis_tlast;
  wire                    m_icmp_arp_64_axis_tuser;

  // ICMP eth_axis_tx output
  wire [  DATA_WIDTH-1:0] m_icmp_arp_axis_tdata;
  wire [  KEEP_WIDTH-1:0] m_icmp_arp_axis_tkeep;
  wire                    m_icmp_arp_axis_tvalid;
  wire                    m_icmp_arp_axis_tready;
  wire                    m_icmp_arp_axis_tlast;
  wire                    m_icmp_arp_axis_tuser;

  // UDP TX intermediate: udp_ip_tx_test → state machine / ip_eth_tx_test
  wire                    s_ip_hdr_valid;
  wire                    s_ip_hdr_ready;
  wire [            47:0] s_eth_dest_mac;
  wire [            47:0] s_eth_src_mac;
  wire [            15:0] s_eth_type;
  wire [             3:0] s_ip_version;
  wire [             3:0] s_ip_ihl;
  wire [             5:0] s_ip_dscp;
  wire [             1:0] s_ip_ecn;
  wire [            15:0] s_ip_length;
  wire [            15:0] s_ip_identification;
  wire [             2:0] s_ip_flags;
  wire [            12:0] s_ip_fragment_offset;
  wire [             7:0] s_ip_ttl;
  wire [             7:0] s_ip_protocol;
  wire [            15:0] s_ip_header_checksum;
  wire [            31:0] s_ip_source_ip;
  wire [            31:0] s_ip_dest_ip;
  wire                    s_is_roce_packet;
  wire [  DATA_WIDTH-1:0] s_ip_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] s_ip_payload_axis_tkeep;
  wire                    s_ip_payload_axis_tvalid;
  wire                    s_ip_payload_axis_tready;
  wire                    s_ip_payload_axis_tlast;
  wire                    s_ip_payload_axis_tuser;

  wire [  DATA_WIDTH-1:0] m_ip_fifo_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] m_ip_fifo_payload_axis_tkeep;
  wire                    m_ip_fifo_payload_axis_tvalid;
  wire                    m_ip_fifo_payload_axis_tready;
  wire                    m_ip_fifo_payload_axis_tlast;
  wire                    m_ip_fifo_payload_axis_tuser;

  // ip_eth_tx_test → icrc insterter (UDP TX ethernet frame)
  wire                    tx_eth_hdr_valid;
  wire                    tx_eth_hdr_ready;
  wire [            47:0] tx_eth_dest_mac;
  wire [            47:0] tx_eth_src_mac;
  wire [            15:0] tx_eth_type;
  wire                    tx_is_roce_packet;

  wire [  DATA_WIDTH-1:0] tx_eth_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] tx_eth_payload_axis_tkeep;
  wire                    tx_eth_payload_axis_tvalid;
  wire                    tx_eth_payload_axis_tready;
  wire                    tx_eth_payload_axis_tlast;
  wire [             1:0] tx_eth_payload_axis_tuser;

  wire                    m_eth_hdr_valid;
  wire                    m_eth_hdr_ready;
  wire [            47:0] m_eth_dest_mac;
  wire [            47:0] m_eth_src_mac;
  wire [            15:0] m_eth_type;

  wire [  DATA_WIDTH-1:0] m_eth_payload_axis_tdata;
  wire [  KEEP_WIDTH-1:0] m_eth_payload_axis_tkeep;
  wire                    m_eth_payload_axis_tvalid;
  wire                    m_eth_payload_axis_tready;
  wire                    m_eth_payload_axis_tlast;
  wire [             1:0] m_eth_payload_axis_tuser;

  // Stack eth_axis_tx output
  wire [  DATA_WIDTH-1:0] m_stack_axis_tdata;
  wire [  KEEP_WIDTH-1:0] m_stack_axis_tkeep;
  wire                    m_stack_axis_tvalid;
  wire                    m_stack_axis_tready;
  wire                    m_stack_axis_tlast;
  wire                    m_stack_axis_tuser;

  localparam [2:0] STATE_IDLE = 3'd0,  STATE_COMPUTE_CHECKSUM = 3'd1, STATE_ARP_QUERY = 3'd2, STATE_WAIT_1CLK = 3'd3, STATE_WAIT_PACKET = 3'd4;

  reg [2:0] state_reg = STATE_IDLE, state_next;

  reg [5:0] outgoing_ip_dscp_reg, outgoing_ip_dscp_next;
  reg [1:0] outgoing_ip_ecn_reg, outgoing_ip_ecn_next;
  reg [15:0] outgoing_ip_length_reg, outgoing_ip_length_next;
  reg [7:0] outgoing_ip_ttl_reg, outgoing_ip_ttl_next;
  reg [7:0] outgoing_ip_protocol_reg, outgoing_ip_protocol_next;
  reg [31:0] outgoing_ip_source_ip_reg, outgoing_ip_source_ip_next;
  reg [31:0] outgoing_ip_dest_ip_reg, outgoing_ip_dest_ip_next;
  reg outgoing_is_roce_packet_reg, outgoing_is_roce_packet_next;

  reg outgoing_ip_hdr_valid_reg = 1'b0, outgoing_ip_hdr_valid_next;
  wire outgoing_ip_hdr_ready;
  reg [47:0] outgoing_eth_dest_mac_reg = 48'h000000000000, outgoing_eth_dest_mac_next;
  wire outgoing_ip_payload_axis_tready;

  reg [19:0] hdr_sum_temp_reg = 20'd0, hdr_sum_temp_next;
  reg [19:0] hdr_sum_reg = 20'd0, hdr_sum_next;


  reg [31:0] last_ip_addr_query_reg, last_ip_addr_query_next;
  reg [47:0] cached_mac_address_reg, cached_mac_address_next;

  reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;

  reg arp_request_valid_reg = 1'b0, arp_request_valid_next;
  reg arp_response_ready_reg = 1'b0, arp_response_ready_next;
  reg drop_packet_reg = 1'b0, drop_packet_next;

  reg [15:0] s_ip_identification_reg = 16'd0;

  wire [15:0] s_ip_length_roce = s_ip_length + 16'd4;

  wire m_fifo_ip_hdr_valid;
  wire m_fifo_ip_hdr_ready;

  wire [47:0] m_fifo_ip_eth_dest_mac;
  wire [ 5:0] m_fifo_ip_dscp;
  wire [ 1:0] m_fifo_ip_ecn;
  wire [15:0] m_fifo_ip_length;
  wire [15:0] m_fifo_ip_identification;
  wire [ 7:0] m_fifo_ip_ttl;
  wire [ 7:0] m_fifo_ip_protocol;
  wire [15:0] m_fifo_ip_hdr_checksum;
  wire [31:0] m_fifo_ip_dest_ip;
  wire        m_fifo_is_roce_packet;

  assign s_ip_hdr_ready = s_ip_hdr_ready_reg;
  assign s_ip_payload_axis_tready = outgoing_ip_payload_axis_tready || drop_packet_reg;

  assign arp_request_valid = arp_request_valid_reg;
  assign arp_request_ip = s_ip_dest_ip;
  assign arp_response_ready = arp_response_ready_reg;

  assign tx_error_arp_failed = arp_response_error;

  // RX PATH

  eth_axis_rx #(
    .DATA_WIDTH(DATA_WIDTH)
  ) eth_axis_rx_inst (
    .clk                           (clk),
    .rst                           (rst),
    // AXI input
    .s_axis_tdata                  (s_network_axis_tdata),
    .s_axis_tkeep                  (s_network_axis_tkeep),
    .s_axis_tvalid                 (s_network_axis_tvalid),
    .s_axis_tready                 (s_network_axis_tready),
    .s_axis_tlast                  (s_network_axis_tlast),
    .s_axis_tuser                  (s_network_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid               (s_rx_eth_hdr_valid),
    .m_eth_hdr_ready               (s_rx_eth_hdr_ready),
    .m_eth_dest_mac                (s_rx_eth_dest_mac),
    .m_eth_src_mac                 (s_rx_eth_src_mac),
    .m_eth_type                    (s_rx_eth_type),
    .m_eth_payload_axis_tdata      (s_rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep      (s_rx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid     (s_rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready     (s_rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast      (s_rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser      (s_rx_eth_payload_axis_tuser),
    // Status signals
    .busy                          (),
    .error_header_early_termination()
  );

  // DEMUX RX eth traffic

  wire s_select_ip = (s_rx_eth_type == 16'h0800 && (s_rx_eth_dest_mac == local_mac_addr || s_rx_eth_dest_mac == 48'hFFFF_FFFF_FFFF));
  wire s_select_arp = (s_rx_eth_type == 16'h0806 && (s_rx_eth_dest_mac == local_mac_addr || s_rx_eth_dest_mac == 48'hFFFF_FFFF_FFFF));
  wire s_select_none = !(s_select_ip || s_select_arp);

  reg s_select_ip_reg = 1'b0;
  reg s_select_arp_reg = 1'b0;
  reg s_select_none_reg = 1'b0;


  always @(posedge clk) begin
    if (rst) begin
      s_select_ip_reg   <= 1'b0;
      s_select_arp_reg  <= 1'b0;
      s_select_none_reg <= 1'b0;
    end else begin
      if (s_rx_eth_payload_axis_tvalid) begin
        if ((!s_select_ip_reg && !s_select_arp_reg && !s_select_none_reg) ||
        (s_rx_eth_payload_axis_tvalid && s_rx_eth_payload_axis_tready && s_rx_eth_payload_axis_tlast)) begin
          s_select_ip_reg   <= s_select_ip;
          s_select_arp_reg  <= s_select_arp;
          s_select_none_reg <= s_select_none;
        end
      end else begin
        s_select_ip_reg   <= 1'b0;
        s_select_arp_reg  <= 1'b0;
        s_select_none_reg <= 1'b0;
      end
    end
  end

  assign ip_rx_eth_hdr_valid = s_select_ip && s_rx_eth_hdr_valid;
  assign ip_rx_eth_dest_mac = s_rx_eth_dest_mac;
  assign ip_rx_eth_src_mac = s_rx_eth_src_mac;
  assign ip_rx_eth_type = 16'h0800;
  assign ip_rx_eth_payload_axis_tdata = s_rx_eth_payload_axis_tdata;
  assign ip_rx_eth_payload_axis_tkeep = s_rx_eth_payload_axis_tkeep;
  assign ip_rx_eth_payload_axis_tvalid = s_select_ip_reg && s_rx_eth_payload_axis_tvalid;
  assign ip_rx_eth_payload_axis_tlast = s_rx_eth_payload_axis_tlast;
  assign ip_rx_eth_payload_axis_tuser = s_rx_eth_payload_axis_tuser;

  assign arp_rx_eth_hdr_valid = s_select_arp && s_rx_eth_hdr_valid;
  assign arp_rx_eth_dest_mac = s_rx_eth_dest_mac;
  assign arp_rx_eth_src_mac = s_rx_eth_src_mac;
  assign arp_rx_eth_type = 16'h0806;
  assign arp_rx_eth_payload_axis_tdata = s_rx_eth_payload_axis_tdata;
  assign arp_rx_eth_payload_axis_tkeep = s_rx_eth_payload_axis_tkeep;
  assign arp_rx_eth_payload_axis_tvalid = s_select_arp_reg && s_rx_eth_payload_axis_tvalid;
  assign arp_rx_eth_payload_axis_tlast = s_rx_eth_payload_axis_tlast;
  assign arp_rx_eth_payload_axis_tuser = s_rx_eth_payload_axis_tuser;

  assign s_rx_eth_hdr_ready = (s_select_ip && ip_rx_eth_hdr_ready) ||
  (s_select_arp && arp_rx_eth_hdr_ready) ||
  (s_select_none);

  assign s_rx_eth_payload_axis_tready = (s_select_ip_reg && ip_rx_eth_payload_axis_tready) ||
  (s_select_arp_reg && arp_rx_eth_payload_axis_tready) ||
  s_select_none_reg;

  // TODO merge APR and ICMP path, share same eth block and same arbiter


  /*
   * ARP module
   */
  arp #(
    .DATA_WIDTH            (64),
    .KEEP_ENABLE           (KEEP_ENABLE),
    .KEEP_WIDTH            (8),
    .CACHE_ADDR_WIDTH      (ARP_CACHE_ADDR_WIDTH),
    .REQUEST_RETRY_COUNT   (ARP_REQUEST_RETRY_COUNT),
    .REQUEST_RETRY_INTERVAL(ARP_REQUEST_RETRY_INTERVAL),
    .REQUEST_TIMEOUT       (ARP_REQUEST_TIMEOUT)
  ) arp_inst (
    .clk                      (clk),
    .rst                      (rst),
    // Ethernet frame input
    .s_eth_hdr_valid          (arp_rx_eth_hdr_valid),
    .s_eth_hdr_ready          (arp_rx_eth_hdr_ready),
    .s_eth_dest_mac           (arp_rx_eth_dest_mac),
    .s_eth_src_mac            (arp_rx_eth_src_mac),
    .s_eth_type               (arp_rx_eth_type),
    .s_eth_payload_axis_tdata (arp_rx_eth_payload_64_axis_tdata),
    .s_eth_payload_axis_tkeep (arp_rx_eth_payload_64_axis_tkeep),
    .s_eth_payload_axis_tvalid(arp_rx_eth_payload_64_axis_tvalid),
    .s_eth_payload_axis_tready(arp_rx_eth_payload_64_axis_tready),
    .s_eth_payload_axis_tlast (arp_rx_eth_payload_64_axis_tlast),
    .s_eth_payload_axis_tuser (arp_rx_eth_payload_64_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid          (arp_tx_eth_hdr_valid),
    .m_eth_hdr_ready          (arp_tx_eth_hdr_ready),
    .m_eth_dest_mac           (arp_tx_eth_dest_mac),
    .m_eth_src_mac            (arp_tx_eth_src_mac),
    .m_eth_type               (arp_tx_eth_type),
    .m_eth_payload_axis_tdata (arp_tx_eth_payload_64_axis_tdata),
    .m_eth_payload_axis_tkeep (arp_tx_eth_payload_64_axis_tkeep),
    .m_eth_payload_axis_tvalid(arp_tx_eth_payload_64_axis_tvalid),
    .m_eth_payload_axis_tready(arp_tx_eth_payload_64_axis_tready),
    .m_eth_payload_axis_tlast (arp_tx_eth_payload_64_axis_tlast),
    .m_eth_payload_axis_tuser (arp_tx_eth_payload_64_axis_tuser),
    // ARP requests
    .arp_request_valid        (arp_request_valid),
    .arp_request_ready        (arp_request_ready),
    .arp_request_ip           (arp_request_ip),
    .arp_response_valid       (arp_response_valid),
    .arp_response_ready       (arp_response_ready),
    .arp_response_error       (arp_response_error),
    .arp_response_mac         (arp_response_mac),
    // Configuration
    .local_mac                (local_mac_addr),
    .local_ip                 (local_ip_addr),
    .gateway_ip               (gateway_ip),
    .subnet_mask              (subnet_mask),
    .clear_cache              (clear_arp_cache)
  );

  axis_adapter #(
    .S_DATA_WIDTH(DATA_WIDTH),
    .S_KEEP_ENABLE(1),
    .M_DATA_WIDTH(64),
    .M_KEEP_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
  ) arp_rx_adapter_inst (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata (arp_rx_eth_payload_axis_tdata),
    .s_axis_tkeep (arp_rx_eth_payload_axis_tkeep),
    .s_axis_tvalid(arp_rx_eth_payload_axis_tvalid),
    .s_axis_tready(arp_rx_eth_payload_axis_tready),
    .s_axis_tlast (arp_rx_eth_payload_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (arp_rx_eth_payload_axis_tuser),
    // AXI output
    .m_axis_tdata (arp_rx_eth_payload_64_axis_tdata),
    .m_axis_tkeep (arp_rx_eth_payload_64_axis_tkeep),
    .m_axis_tvalid(arp_rx_eth_payload_64_axis_tvalid),
    .m_axis_tready(arp_rx_eth_payload_64_axis_tready),
    .m_axis_tlast (arp_rx_eth_payload_64_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (arp_rx_eth_payload_64_axis_tuser)
  );


  ip_eth_rx_test #(
    .DATA_WIDTH(DATA_WIDTH)
  ) ip_eth_rx_inst (
    .clk                      (clk),
    .rst                      (rst),
    // Ethernet frame input
    .s_eth_hdr_valid          (ip_rx_eth_hdr_valid),
    .s_eth_hdr_ready          (ip_rx_eth_hdr_ready),
    .s_eth_dest_mac           (ip_rx_eth_dest_mac),
    .s_eth_src_mac            (ip_rx_eth_src_mac),
    .s_eth_type               (ip_rx_eth_type),
    .s_eth_payload_axis_tdata (ip_rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep (ip_rx_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(ip_rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(ip_rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast (ip_rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser (ip_rx_eth_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid           (s_rx_ip_hdr_valid),
    .m_ip_hdr_ready           (s_rx_ip_hdr_ready),
    .m_eth_dest_mac           (s_rx_ip_eth_dest_mac),
    .m_eth_src_mac            (s_rx_ip_eth_src_mac),
    .m_eth_type               (s_rx_ip_eth_type),
    .m_ip_version             (s_rx_ip_version),
    .m_ip_ihl                 (s_rx_ip_ihl),
    .m_ip_dscp                (s_rx_ip_dscp),
    .m_ip_ecn                 (s_rx_ip_ecn),
    .m_ip_length              (s_rx_ip_length),
    .m_ip_identification      (s_rx_ip_identification),
    .m_ip_flags               (s_rx_ip_flags),
    .m_ip_fragment_offset     (s_rx_ip_fragment_offset),
    .m_ip_ttl                 (s_rx_ip_ttl),
    .m_ip_protocol            (s_rx_ip_protocol),
    .m_ip_header_checksum     (s_rx_ip_header_checksum),
    .m_ip_source_ip           (s_rx_ip_source_ip),
    .m_ip_dest_ip             (s_rx_ip_dest_ip),
    .m_ip_payload_axis_tdata  (s_rx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tkeep  (s_rx_ip_payload_axis_tkeep),
    .m_ip_payload_axis_tvalid (s_rx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready (s_rx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast  (s_rx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser  (s_rx_ip_payload_axis_tuser)
  );

  wire s_broadcast_ip_addr = ~(s_rx_ip_dest_ip | subnet_mask) == 0;
  wire s_ip_select_icmp = (s_rx_ip_protocol == 8'h01 && (s_rx_ip_dest_ip == local_ip_addr || s_broadcast_ip_addr));
  wire s_ip_select_udp = (s_rx_ip_protocol == 8'h11 && (s_rx_ip_dest_ip == local_ip_addr || s_broadcast_ip_addr));
  wire s_ip_select_none = !(s_ip_select_icmp || s_ip_select_udp);

  reg s_ip_select_icmp_reg = 1'b0;
  reg s_ip_select_udp_reg = 1'b0;
  reg s_ip_select_none_reg = 1'b0;

  always @(posedge clk) begin
    if (rst) begin
      s_ip_select_icmp_reg <= 1'b0;
      s_ip_select_udp_reg  <= 1'b0;
      s_ip_select_none_reg <= 1'b0;
    end else begin

      if (s_rx_ip_payload_axis_tvalid) begin
        if ((!s_ip_select_icmp_reg && !s_ip_select_udp_reg && !s_ip_select_none_reg) ||
        (s_rx_ip_payload_axis_tvalid && s_rx_ip_payload_axis_tready && s_rx_ip_payload_axis_tlast)) begin
          s_ip_select_icmp_reg <= s_ip_select_icmp;
          s_ip_select_udp_reg  <= s_ip_select_udp;
          s_ip_select_none_reg <= s_ip_select_none;
        end
      end else begin
        s_ip_select_icmp_reg <= 1'b0;
        s_ip_select_udp_reg  <= 1'b0;
        s_ip_select_none_reg <= 1'b0;
      end
    end
  end

  assign udp_rx_ip_hdr_valid            = s_ip_select_udp && s_rx_ip_hdr_valid;
  assign udp_rx_ip_eth_dest_mac         = s_rx_ip_eth_dest_mac;
  assign udp_rx_ip_eth_src_mac          = s_rx_ip_eth_src_mac;
  assign udp_rx_ip_eth_type             = s_rx_ip_eth_type;
  assign udp_rx_ip_version              = s_rx_ip_version;
  assign udp_rx_ip_ihl                  = s_rx_ip_ihl;
  assign udp_rx_ip_dscp                 = s_rx_ip_dscp;
  assign udp_rx_ip_ecn                  = s_rx_ip_ecn;
  assign udp_rx_ip_length               = s_rx_ip_length;
  assign udp_rx_ip_identification       = s_rx_ip_identification;
  assign udp_rx_ip_flags                = s_rx_ip_flags;
  assign udp_rx_ip_fragment_offset      = s_rx_ip_fragment_offset;
  assign udp_rx_ip_ttl                  = s_rx_ip_ttl;
  assign udp_rx_ip_protocol             = s_rx_ip_protocol;
  assign udp_rx_ip_header_checksum      = s_rx_ip_header_checksum;
  assign udp_rx_ip_source_ip            = s_rx_ip_source_ip;
  assign udp_rx_ip_dest_ip              = s_rx_ip_dest_ip;
  assign udp_rx_ip_payload_axis_tdata   = s_rx_ip_payload_axis_tdata;
  assign udp_rx_ip_payload_axis_tkeep   = s_rx_ip_payload_axis_tkeep;
  assign udp_rx_ip_payload_axis_tvalid  = s_ip_select_udp_reg && s_rx_ip_payload_axis_tvalid;
  assign udp_rx_ip_payload_axis_tlast   = s_rx_ip_payload_axis_tlast;
  assign udp_rx_ip_payload_axis_tuser   = s_rx_ip_payload_axis_tuser;


  assign icmp_rx_ip_hdr_valid           = s_ip_select_icmp && s_rx_ip_hdr_valid;
  assign icmp_rx_ip_eth_dest_mac        = s_rx_ip_eth_dest_mac;
  assign icmp_rx_ip_eth_src_mac         = s_rx_ip_eth_src_mac;
  assign icmp_rx_ip_eth_type            = s_rx_ip_eth_type;
  assign icmp_rx_ip_version             = s_rx_ip_version;
  assign icmp_rx_ip_ihl                 = s_rx_ip_ihl;
  assign icmp_rx_ip_dscp                = s_rx_ip_dscp;
  assign icmp_rx_ip_ecn                 = s_rx_ip_ecn;
  assign icmp_rx_ip_length              = s_rx_ip_length;
  assign icmp_rx_ip_identification      = s_rx_ip_identification;
  assign icmp_rx_ip_flags               = s_rx_ip_flags;
  assign icmp_rx_ip_fragment_offset     = s_rx_ip_fragment_offset;
  assign icmp_rx_ip_ttl                 = s_rx_ip_ttl;
  assign icmp_rx_ip_protocol            = s_rx_ip_protocol;
  assign icmp_rx_ip_header_checksum     = s_rx_ip_header_checksum;
  assign icmp_rx_ip_source_ip           = s_rx_ip_source_ip;
  assign icmp_rx_ip_dest_ip             = s_rx_ip_dest_ip;
  assign icmp_rx_ip_payload_axis_tdata  = s_rx_ip_payload_axis_tdata;
  assign icmp_rx_ip_payload_axis_tkeep  = s_rx_ip_payload_axis_tkeep;
  assign icmp_rx_ip_payload_axis_tvalid = s_ip_select_icmp_reg && s_rx_ip_payload_axis_tvalid;
  assign icmp_rx_ip_payload_axis_tlast  = s_rx_ip_payload_axis_tlast;
  assign icmp_rx_ip_payload_axis_tuser  = s_rx_ip_payload_axis_tuser;

  assign s_rx_ip_hdr_ready = (s_ip_select_udp && udp_rx_ip_hdr_ready) ||
  (s_ip_select_icmp && icmp_rx_ip_hdr_ready) ||
  (s_ip_select_none);

  assign s_rx_ip_payload_axis_tready = (s_ip_select_udp_reg && udp_rx_ip_payload_axis_tready) ||
  (s_ip_select_icmp_reg && icmp_rx_ip_payload_axis_tready) ||
  s_ip_select_none_reg;
  // ICMP block
  /*
   * ICMP Echo reply
   */

  wire [ 63:0] icmp_tx_ip_payload_64_axis_tdata;
  wire [7 : 0] icmp_tx_ip_payload_64_axis_tkeep;
  wire         icmp_tx_ip_payload_64_axis_tvalid;
  wire         icmp_tx_ip_payload_64_axis_tready;
  wire         icmp_tx_ip_payload_64_axis_tlast;
  wire         icmp_tx_ip_payload_64_axis_tuser;

  wire [ 63:0] icmp_rx_ip_payload_64_axis_tdata;
  wire [7 : 0] icmp_rx_ip_payload_64_axis_tkeep;
  wire         icmp_rx_ip_payload_64_axis_tvalid;
  wire         icmp_rx_ip_payload_64_axis_tready;
  wire         icmp_rx_ip_payload_64_axis_tlast;
  wire         icmp_rx_ip_payload_64_axis_tuser;

  icmp_echo_reply #(
    .DATA_WIDTH(64),
    .KEEP_ENABLE(1),
    .CHECKSUM_PAYLOAD_FIFO_DEPTH(1024),
    .CHECKSUM_HEADER_FIFO_DEPTH(4),
    .COMPUTE_IP_HDR_CHECKSUM(1),
    .IP_HDR_CHECKSUM_PIPELINED(1)
  ) icmp_echo_reply_inst (
    .clk(clk),
    .rst(rst),
    // IP frame input
    .s_ip_hdr_valid(icmp_rx_ip_hdr_valid),
    .s_ip_hdr_ready(icmp_rx_ip_hdr_ready),
    .s_eth_dest_mac(icmp_rx_ip_eth_dest_mac),
    .s_eth_src_mac(icmp_rx_ip_eth_src_mac),
    .s_eth_type(icmp_rx_ip_eth_type),
    .s_ip_version(icmp_rx_ip_version),
    .s_ip_ihl(icmp_rx_ip_ihl),
    .s_ip_dscp(icmp_rx_ip_dscp),
    .s_ip_ecn(icmp_rx_ip_ecn),
    .s_ip_length(icmp_rx_ip_length),
    .s_ip_identification(icmp_rx_ip_identification),
    .s_ip_flags(icmp_rx_ip_flags),
    .s_ip_fragment_offset(icmp_rx_ip_fragment_offset),
    .s_ip_ttl(icmp_rx_ip_ttl),
    .s_ip_protocol(icmp_rx_ip_protocol),
    .s_ip_header_checksum(icmp_rx_ip_header_checksum),
    .s_ip_source_ip(icmp_rx_ip_source_ip),
    .s_ip_dest_ip(icmp_rx_ip_dest_ip),
    .s_ip_payload_axis_tdata(icmp_rx_ip_payload_64_axis_tdata),
    .s_ip_payload_axis_tkeep(icmp_rx_ip_payload_64_axis_tkeep),
    .s_ip_payload_axis_tvalid(icmp_rx_ip_payload_64_axis_tvalid),
    .s_ip_payload_axis_tready(icmp_rx_ip_payload_64_axis_tready),
    .s_ip_payload_axis_tlast(icmp_rx_ip_payload_64_axis_tlast),
    .s_ip_payload_axis_tuser(icmp_rx_ip_payload_64_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid      (icmp_tx_ip_hdr_valid),
    .m_ip_hdr_ready      (icmp_tx_ip_hdr_ready),
    .m_eth_dest_mac      (icmp_tx_ip_eth_dest_mac),
    .m_eth_src_mac       (icmp_tx_ip_eth_src_mac),
    .m_eth_type          (icmp_tx_ip_eth_type),
    .m_ip_version        (icmp_tx_ip_version),
    .m_ip_ihl            (icmp_tx_ip_ihl),
    .m_ip_dscp           (icmp_tx_ip_dscp),
    .m_ip_ecn            (icmp_tx_ip_ecn),
    .m_ip_length         (icmp_tx_ip_length),
    .m_ip_identification (icmp_tx_ip_identification),
    .m_ip_flags          (icmp_tx_ip_flags),
    .m_ip_fragment_offset(icmp_tx_ip_fragment_offset),
    .m_ip_ttl            (icmp_tx_ip_ttl),
    .m_ip_protocol       (icmp_tx_ip_protocol),
    .m_ip_header_checksum(icmp_tx_ip_hdr_checksum),
    .m_ip_source_ip      (icmp_tx_ip_source_ip),
    .m_ip_dest_ip        (icmp_tx_ip_dest_ip),
    .m_is_roce_packet    (icmp_tx_is_roce_packet),
    .m_ip_payload_axis_tdata (icmp_tx_ip_payload_64_axis_tdata),
    .m_ip_payload_axis_tkeep (icmp_tx_ip_payload_64_axis_tkeep),
    .m_ip_payload_axis_tvalid(icmp_tx_ip_payload_64_axis_tvalid),
    .m_ip_payload_axis_tready(icmp_tx_ip_payload_64_axis_tready),
    .m_ip_payload_axis_tlast (icmp_tx_ip_payload_64_axis_tlast),
    .m_ip_payload_axis_tuser (icmp_tx_ip_payload_64_axis_tuser),
    // Configuration
    .local_ip(local_ip_addr)
  );

  axis_adapter #(
    .S_DATA_WIDTH(DATA_WIDTH),
    .S_KEEP_ENABLE(1),
    .M_DATA_WIDTH(64),
    .M_KEEP_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
  ) icmp_rx_adapter_inst (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata (icmp_rx_ip_payload_axis_tdata),
    .s_axis_tkeep (icmp_rx_ip_payload_axis_tkeep),
    .s_axis_tvalid(icmp_rx_ip_payload_axis_tvalid),
    .s_axis_tready(icmp_rx_ip_payload_axis_tready),
    .s_axis_tlast (icmp_rx_ip_payload_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (icmp_rx_ip_payload_axis_tuser),
    // AXI output
    .m_axis_tdata (icmp_rx_ip_payload_64_axis_tdata),
    .m_axis_tkeep (icmp_rx_ip_payload_64_axis_tkeep),
    .m_axis_tvalid(icmp_rx_ip_payload_64_axis_tvalid),
    .m_axis_tready(icmp_rx_ip_payload_64_axis_tready),
    .m_axis_tlast (icmp_rx_ip_payload_64_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (icmp_rx_ip_payload_64_axis_tuser)
  );

  ip_eth_tx_test #(
    .DATA_WIDTH (64),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH (8)
  ) ip_eth_tx_icmp (
    .clk                     (clk),
    .rst                     (rst),
    .s_ip_hdr_valid          (icmp_tx_ip_hdr_valid),
    .s_ip_hdr_ready          (icmp_tx_ip_hdr_ready),
    .s_eth_dest_mac          (icmp_tx_ip_eth_dest_mac),
    .s_eth_src_mac           (icmp_tx_ip_eth_src_mac),
    .s_eth_type              (icmp_tx_ip_eth_type),
    .s_ip_dscp               (icmp_tx_ip_dscp),
    .s_ip_ecn                (icmp_tx_ip_ecn),
    .s_ip_length             (icmp_tx_ip_length),
    .s_ip_identification     (icmp_tx_ip_identification),
    .s_ip_flags              (icmp_tx_ip_flags),
    .s_ip_fragment_offset    (icmp_tx_ip_fragment_offset),
    .s_ip_ttl                (icmp_tx_ip_ttl),
    .s_ip_protocol           (icmp_tx_ip_protocol),
    .s_ip_hdr_checksum       (icmp_tx_ip_hdr_checksum),
    .s_ip_source_ip          (icmp_tx_ip_source_ip),
    .s_ip_dest_ip            (icmp_tx_ip_dest_ip),
    .s_is_roce_packet        (0),
    .s_ip_payload_axis_tdata (icmp_tx_ip_payload_64_axis_tdata),
    .s_ip_payload_axis_tkeep (icmp_tx_ip_payload_64_axis_tkeep),
    .s_ip_payload_axis_tvalid(icmp_tx_ip_payload_64_axis_tvalid),
    .s_ip_payload_axis_tready(icmp_tx_ip_payload_64_axis_tready),
    .s_ip_payload_axis_tlast (icmp_tx_ip_payload_64_axis_tlast),
    .s_ip_payload_axis_tuser (icmp_tx_ip_payload_64_axis_tuser),

    .m_eth_hdr_valid          (icmp_tx_eth_hdr_valid),
    .m_eth_hdr_ready          (icmp_tx_eth_hdr_ready),
    .m_eth_dest_mac           (icmp_tx_eth_dest_mac),
    .m_eth_src_mac            (icmp_tx_eth_src_mac),
    .m_eth_type               (icmp_tx_eth_type),
    .m_is_roce_packet         (),
    .m_eth_payload_axis_tdata (icmp_tx_eth_payload_64_axis_tdata),
    .m_eth_payload_axis_tkeep (icmp_tx_eth_payload_64_axis_tkeep),
    .m_eth_payload_axis_tvalid(icmp_tx_eth_payload_64_axis_tvalid),
    .m_eth_payload_axis_tready(icmp_tx_eth_payload_64_axis_tready),
    .m_eth_payload_axis_tlast (icmp_tx_eth_payload_64_axis_tlast),
    .m_eth_payload_axis_tuser (icmp_tx_eth_payload_64_axis_tuser),
    .busy                     ()
  );

  eth_arb_mux #(
      .S_COUNT(2),
      .DATA_WIDTH(64),
      .KEEP_ENABLE(1),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(1),
      .ARB_TYPE_ROUND_ROBIN(0),
      .ARB_LSB_HIGH_PRIORITY(0)
  ) eth_arb_mux_arp_icmp_inst (
      .clk(clk),
      .rst(rst),
      // Ethernet frame inputs
      .s_eth_hdr_valid ({icmp_tx_eth_hdr_valid, arp_tx_eth_hdr_valid}),
      .s_eth_hdr_ready ({icmp_tx_eth_hdr_ready, arp_tx_eth_hdr_ready}),
      .s_eth_dest_mac  ({icmp_tx_eth_dest_mac , arp_tx_eth_dest_mac}),
      .s_eth_src_mac   ({icmp_tx_eth_src_mac  , arp_tx_eth_src_mac}),
      .s_eth_type      ({icmp_tx_eth_type     , arp_tx_eth_type}),
      .s_is_roce_packet({1'b0, 1'b0}),
      .s_eth_payload_axis_tdata ({icmp_tx_eth_payload_64_axis_tdata,  arp_tx_eth_payload_64_axis_tdata}),
      .s_eth_payload_axis_tkeep ({icmp_tx_eth_payload_64_axis_tkeep,  arp_tx_eth_payload_64_axis_tkeep}),
      .s_eth_payload_axis_tvalid({icmp_tx_eth_payload_64_axis_tvalid, arp_tx_eth_payload_64_axis_tvalid}),
      .s_eth_payload_axis_tready({icmp_tx_eth_payload_64_axis_tready, arp_tx_eth_payload_64_axis_tready}),
      .s_eth_payload_axis_tlast ({icmp_tx_eth_payload_64_axis_tlast,  arp_tx_eth_payload_64_axis_tlast}),
      .s_eth_payload_axis_tid   (0),
      .s_eth_payload_axis_tdest (0),
      .s_eth_payload_axis_tuser ({icmp_tx_eth_payload_64_axis_tuser, arp_tx_eth_payload_64_axis_tuser}),
      // Ethernet frame output
      .m_eth_hdr_valid(icmp_arp_tx_eth_hdr_valid),
      .m_eth_hdr_ready(icmp_arp_tx_eth_hdr_ready),
      .m_eth_dest_mac (icmp_arp_tx_eth_dest_mac),
      .m_eth_src_mac  (icmp_arp_tx_eth_src_mac),
      .m_eth_type     (icmp_arp_tx_eth_type),
      .m_eth_payload_axis_tdata (icmp_arp_tx_eth_payload_64_axis_tdata),
      .m_eth_payload_axis_tkeep (icmp_arp_tx_eth_payload_64_axis_tkeep),
      .m_eth_payload_axis_tvalid(icmp_arp_tx_eth_payload_64_axis_tvalid),
      .m_eth_payload_axis_tready(icmp_arp_tx_eth_payload_64_axis_tready),
      .m_eth_payload_axis_tlast (icmp_arp_tx_eth_payload_64_axis_tlast),
      .m_eth_payload_axis_tid   (),
      .m_eth_payload_axis_tdest (),
      .m_eth_payload_axis_tuser (icmp_arp_tx_eth_payload_64_axis_tuser)
  );


  eth_axis_tx #(
    .DATA_WIDTH(64),
    .ENABLE_DOT1Q_HEADER(ENABLE_DOT1Q_HEADER)
  ) eth_axis_tx_icmp (
    .clk                      (clk),
    .rst                      (rst),
    .s_eth_hdr_valid          (icmp_arp_tx_eth_hdr_valid),
    .s_eth_hdr_ready          (icmp_arp_tx_eth_hdr_ready),
    .s_eth_dest_mac           (icmp_arp_tx_eth_dest_mac),
    .s_eth_src_mac            (icmp_arp_tx_eth_src_mac),
    .s_eth_tpid               (0),
    .s_eth_pcp                (0),
    .s_eth_dei                (0),
    .s_eth_vid                (0),
    .s_eth_type               (icmp_arp_tx_eth_type),
    .s_eth_payload_axis_tdata (icmp_arp_tx_eth_payload_64_axis_tdata),
    .s_eth_payload_axis_tkeep (icmp_arp_tx_eth_payload_64_axis_tkeep),
    .s_eth_payload_axis_tvalid(icmp_arp_tx_eth_payload_64_axis_tvalid),
    .s_eth_payload_axis_tready(icmp_arp_tx_eth_payload_64_axis_tready),
    .s_eth_payload_axis_tlast (icmp_arp_tx_eth_payload_64_axis_tlast),
    .s_eth_payload_axis_tuser (icmp_arp_tx_eth_payload_64_axis_tuser),
    .m_axis_tdata             (m_icmp_arp_64_axis_tdata),
    .m_axis_tkeep             (m_icmp_arp_64_axis_tkeep),
    .m_axis_tvalid            (m_icmp_arp_64_axis_tvalid),
    .m_axis_tready            (m_icmp_arp_64_axis_tready),
    .m_axis_tlast             (m_icmp_arp_64_axis_tlast),
    .m_axis_tuser             (m_icmp_arp_64_axis_tuser),
    .busy                     ()
  );

  axis_adapter #(
    .S_DATA_WIDTH(64),
    .S_KEEP_ENABLE(1),
    .M_DATA_WIDTH(DATA_WIDTH),
    .M_KEEP_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1)
  ) icmp_tx_adapter_inst (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata (m_icmp_arp_64_axis_tdata),
    .s_axis_tkeep (m_icmp_arp_64_axis_tkeep),
    .s_axis_tvalid(m_icmp_arp_64_axis_tvalid),
    .s_axis_tready(m_icmp_arp_64_axis_tready),
    .s_axis_tlast (m_icmp_arp_64_axis_tlast),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser (m_icmp_arp_64_axis_tuser),
    // AXI output
    .m_axis_tdata (m_icmp_arp_axis_tdata),
    .m_axis_tkeep (m_icmp_arp_axis_tkeep),
    .m_axis_tvalid(m_icmp_arp_axis_tvalid),
    .m_axis_tready(m_icmp_arp_axis_tready),
    .m_axis_tlast (m_icmp_arp_axis_tlast),
    .m_axis_tid   (),
    .m_axis_tdest (),
    .m_axis_tuser (m_icmp_arp_axis_tuser)
  );

  // finally rx UDP

  udp_ip_rx_test #(
    .DATA_WIDTH (DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH (KEEP_WIDTH)
  ) udp_ip_rx_test_instance (
    .clk(clk),
    .rst(rst),

    .s_ip_hdr_valid          (udp_rx_ip_hdr_valid),
    .s_ip_hdr_ready          (udp_rx_ip_hdr_ready),
    .s_eth_dest_mac          (udp_rx_ip_eth_dest_mac),
    .s_eth_src_mac           (udp_rx_ip_eth_src_mac),
    .s_eth_type              (udp_rx_ip_eth_type),
    .s_ip_version            (udp_rx_ip_version),
    .s_ip_ihl                (udp_rx_ip_ihl),
    .s_ip_dscp               (udp_rx_ip_dscp),
    .s_ip_ecn                (udp_rx_ip_ecn),
    .s_ip_length             (udp_rx_ip_length),
    .s_ip_identification     (udp_rx_ip_identification),
    .s_ip_flags              (udp_rx_ip_flags),
    .s_ip_fragment_offset    (udp_rx_ip_fragment_offset),
    .s_ip_ttl                (udp_rx_ip_ttl),
    .s_ip_protocol           (udp_rx_ip_protocol),
    .s_ip_header_checksum    (udp_rx_ip_header_checksum),
    .s_ip_source_ip          (udp_rx_ip_source_ip),
    .s_ip_dest_ip            (udp_rx_ip_dest_ip),
    .s_ip_payload_axis_tdata (udp_rx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tkeep (udp_rx_ip_payload_axis_tkeep),
    .s_ip_payload_axis_tvalid(udp_rx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(udp_rx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast (udp_rx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser (udp_rx_ip_payload_axis_tuser),

    .m_udp_hdr_valid          (m_udp_hdr_valid),
    .m_udp_hdr_ready          (m_udp_hdr_ready),
    .m_eth_dest_mac           (m_udp_eth_dest_mac),
    .m_eth_src_mac            (m_udp_eth_src_mac),
    .m_eth_type               (m_udp_eth_type),
    .m_ip_version             (m_udp_ip_version),
    .m_ip_ihl                 (m_udp_ip_ihl),
    .m_ip_dscp                (m_udp_ip_dscp),
    .m_ip_ecn                 (m_udp_ip_ecn),
    .m_ip_length              (m_udp_ip_length),
    .m_ip_identification      (m_udp_ip_identification),
    .m_ip_flags               (m_udp_ip_flags),
    .m_ip_fragment_offset     (m_udp_ip_fragment_offset),
    .m_ip_ttl                 (m_udp_ip_ttl),
    .m_ip_protocol            (m_udp_ip_protocol),
    .m_ip_header_checksum     (m_udp_ip_header_checksum),
    .m_ip_source_ip           (m_udp_ip_source_ip),
    .m_ip_dest_ip             (m_udp_ip_dest_ip),
    .m_udp_source_port        (m_udp_source_port),
    .m_udp_dest_port          (m_udp_dest_port),
    .m_udp_checksum           (m_udp_checksum),
    .m_udp_length             (m_udp_length),
    .m_udp_payload_axis_tdata (m_udp_payload_axis_tdata),
    .m_udp_payload_axis_tkeep (m_udp_payload_axis_tkeep),
    .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast (m_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser (m_udp_payload_axis_tuser),

    .busy(),
    .error_header_early_termination(),
    .error_payload_early_termination()
  );


  // Optimized TX, no arbiters within the path

  udp_ip_tx_test #(
    .DATA_WIDTH (DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH (KEEP_WIDTH)
  ) udp_ip_tx_test_instance (
    .clk                      (clk),
    .rst                      (rst),
    // UDP frame input
    .s_udp_hdr_valid          (s_udp_hdr_valid),
    .s_udp_hdr_ready          (s_udp_hdr_ready),
    .s_eth_dest_mac           (s_udp_eth_dest_mac),
    .s_eth_src_mac            (s_udp_eth_src_mac),
    .s_eth_type               (s_udp_eth_type),
    .s_ip_version             (s_udp_ip_version),
    .s_ip_ihl                 (s_udp_ip_ihl),
    .s_ip_dscp                (s_udp_ip_dscp),
    .s_ip_ecn                 (s_udp_ip_ecn),
    .s_ip_identification      (s_udp_ip_identification),
    .s_ip_flags               (s_udp_ip_flags),
    .s_ip_fragment_offset     (s_udp_ip_fragment_offset),
    .s_ip_ttl                 (s_udp_ip_ttl),
    .s_ip_protocol            (8'h11),
    .s_ip_header_checksum     (s_udp_ip_header_checksum),
    .s_ip_source_ip           (s_udp_ip_source_ip),
    .s_ip_dest_ip             (s_udp_ip_dest_ip),
    .s_udp_source_port        (s_udp_source_port),
    .s_udp_dest_port          (s_udp_dest_port),
    .s_udp_length             (s_udp_length),
    .s_udp_checksum           (s_udp_checksum),
    .s_udp_payload_axis_tdata (s_udp_payload_axis_tdata),
    .s_udp_payload_axis_tkeep (s_udp_payload_axis_tkeep),
    .s_udp_payload_axis_tvalid(s_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(s_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast (s_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser (s_udp_payload_axis_tuser),
    // IP frame output → state machine
    .m_ip_hdr_valid           (s_ip_hdr_valid),
    .m_ip_hdr_ready           (s_ip_hdr_ready),
    .m_eth_dest_mac           (s_eth_dest_mac),
    .m_eth_src_mac            (s_eth_src_mac),
    .m_eth_type               (s_eth_type),
    .m_ip_version             (s_ip_version),
    .m_ip_ihl                 (s_ip_ihl),
    .m_ip_dscp                (s_ip_dscp),
    .m_ip_ecn                 (s_ip_ecn),
    .m_ip_length              (s_ip_length),
    .m_ip_identification      (s_ip_identification),
    .m_ip_flags               (s_ip_flags),
    .m_ip_fragment_offset     (s_ip_fragment_offset),
    .m_ip_ttl                 (s_ip_ttl),
    .m_ip_protocol            (s_ip_protocol),
    .m_ip_header_checksum     (s_ip_header_checksum),
    .m_ip_source_ip           (s_ip_source_ip),
    .m_ip_dest_ip             (s_ip_dest_ip),
    .m_is_roce_packet         (s_is_roce_packet),
    .m_ip_payload_axis_tdata  (s_ip_payload_axis_tdata),
    .m_ip_payload_axis_tkeep  (s_ip_payload_axis_tkeep),
    .m_ip_payload_axis_tvalid (s_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready (s_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast  (s_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser  (s_ip_payload_axis_tuser),
    .busy                     (),
    .RoCE_udp_port            (RoCE_udp_port)
  );

  always @(posedge clk) begin
    if (rst) begin
      s_ip_identification_reg <= 16'd0;
    end else begin
      if (outgoing_ip_hdr_valid_reg & outgoing_ip_hdr_ready) begin
        s_ip_identification_reg <= s_ip_identification_reg + 1;
      end
    end
  end

  // compute ip header check sum and query MAC address form ARP table
  always @* begin
    state_next = STATE_IDLE;

    arp_request_valid_next = arp_request_valid_reg && !arp_request_ready;
    arp_response_ready_next = 1'b0;
    drop_packet_next = 1'b0;

    last_ip_addr_query_next = last_ip_addr_query_reg;
    cached_mac_address_next = cached_mac_address_reg;

    s_ip_hdr_ready_next = 1'b0;

    hdr_sum_next = hdr_sum_reg;
    hdr_sum_temp_next = hdr_sum_temp_reg;

    outgoing_ip_dscp_next = outgoing_ip_dscp_reg;
    outgoing_ip_ecn_next = outgoing_ip_ecn_reg;
    outgoing_ip_length_next = outgoing_ip_length_reg;
    outgoing_ip_ttl_next = outgoing_ip_ttl_reg;
    outgoing_ip_protocol_next = outgoing_ip_protocol_reg;
    outgoing_ip_source_ip_next = outgoing_ip_source_ip_reg;
    outgoing_ip_dest_ip_next = outgoing_ip_dest_ip_reg;
    outgoing_is_roce_packet_next = outgoing_is_roce_packet_reg;

    outgoing_ip_hdr_valid_next = outgoing_ip_hdr_valid_reg && !outgoing_ip_hdr_ready;
    outgoing_eth_dest_mac_next = outgoing_eth_dest_mac_reg;

    case (state_reg)
      STATE_IDLE: begin
        // wait for outgoing packet
        if (s_ip_hdr_valid) begin
          outgoing_ip_dscp_next = s_ip_dscp;
          outgoing_ip_ecn_next = s_ip_ecn;
          outgoing_ip_length_next = s_ip_length;
          outgoing_ip_ttl_next = s_ip_ttl;
          outgoing_ip_protocol_next = s_ip_protocol;
          outgoing_ip_source_ip_next = s_ip_source_ip;
          outgoing_ip_dest_ip_next = s_ip_dest_ip;
          outgoing_is_roce_packet_next = s_is_roce_packet;
          if (s_is_roce_packet) begin
            hdr_sum_next = {4'd4, 4'd5, s_ip_dscp, s_ip_ecn} +
            s_ip_length_roce +
            s_ip_identification_reg +
            {3'b010, 13'd0} +
            {s_ip_ttl, s_ip_protocol} +
            s_ip_source_ip[31:16] +
            s_ip_source_ip[15: 0] +
            s_ip_dest_ip[31:16] +
            s_ip_dest_ip[15: 0];
          end else begin
            hdr_sum_next = {4'd4, 4'd5, s_ip_dscp, s_ip_ecn} +
            s_ip_length +
            s_ip_identification_reg +
            {3'b010, 13'd0} +
            {s_ip_ttl, s_ip_protocol} +
            s_ip_source_ip[31:16] +
            s_ip_source_ip[15: 0] +
            s_ip_dest_ip[31:16] +
            s_ip_dest_ip[15: 0];
          end
          if (s_ip_dest_ip == last_ip_addr_query_reg) begin
            outgoing_eth_dest_mac_next = cached_mac_address_reg;
            if (HEADER_CHECKSUM_PIPELINED) begin
              state_next = STATE_COMPUTE_CHECKSUM;
            end else begin
              hdr_sum_temp_next = hdr_sum_next[15:0] + hdr_sum_next[19:16];
              hdr_sum_temp_next = hdr_sum_temp_next[15:0] + hdr_sum_temp_next[16];
              s_ip_hdr_ready_next = 1'b1;
              outgoing_ip_hdr_valid_next = 1'b1;
              state_next = STATE_WAIT_1CLK;
            end
          end else begin
            // initiate ARP request
            arp_request_valid_next = 1'b1;
            last_ip_addr_query_next = arp_request_ip;
            arp_response_ready_next = 1'b1;
            state_next = STATE_ARP_QUERY;
          end
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_ARP_QUERY: begin
        hdr_sum_temp_next = hdr_sum_reg[15:0] + hdr_sum_reg[19:16];
        hdr_sum_temp_next = hdr_sum_temp_next[15:0] + hdr_sum_temp_next[16];

        arp_response_ready_next = 1'b1;

        if (arp_response_valid) begin
          // wait for ARP reponse
          if (arp_response_error) begin
            // did not get MAC address; drop packet
            s_ip_hdr_ready_next = 1'b1;
            drop_packet_next = 1'b1;
            state_next = STATE_WAIT_PACKET;
          end else begin
            // got MAC address; send packet
            s_ip_hdr_ready_next = 1'b1;
            outgoing_ip_hdr_valid_next = 1'b1;
            outgoing_eth_dest_mac_next = arp_response_mac;
            cached_mac_address_next = arp_response_mac;
            state_next = STATE_WAIT_1CLK;
          end
        end else begin
          state_next = STATE_ARP_QUERY;
        end
      end
      STATE_COMPUTE_CHECKSUM: begin
        hdr_sum_temp_next = hdr_sum_reg[15:0] + hdr_sum_reg[19:16];
        hdr_sum_temp_next = hdr_sum_temp_next[15:0] + hdr_sum_temp_next[16];

        s_ip_hdr_ready_next = 1'b1;
        outgoing_ip_hdr_valid_next = 1'b1;

        state_next = STATE_WAIT_1CLK;
      end
      STATE_WAIT_1CLK: begin
        state_next = STATE_IDLE;
      end
      STATE_WAIT_PACKET: begin
        drop_packet_next = drop_packet_reg;

        // wait last
        if (s_ip_payload_axis_tlast && s_ip_payload_axis_tready && s_ip_payload_axis_tvalid) begin
          state_next = STATE_IDLE;
        end else begin
          state_next = STATE_WAIT_PACKET;
        end

        state_next = STATE_IDLE;
      end
      default: begin
        state_next = STATE_IDLE;

        s_ip_hdr_ready_next = 1'b0;
        outgoing_ip_hdr_valid_next = 1'b0;
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state_reg                   <= STATE_IDLE;
      arp_request_valid_reg       <= 1'b0;
      arp_response_ready_reg      <= 1'b0;
      drop_packet_reg             <= 1'b0;
      s_ip_hdr_ready_reg          <= 1'b0;
      outgoing_ip_hdr_valid_reg   <= 1'b0;

      outgoing_ip_dscp_reg        <= 6'd0;
      outgoing_ip_ecn_reg         <= 2'd0;
      outgoing_ip_length_reg      <= 16'd0;
      outgoing_ip_ttl_reg         <= 8'h40;
      outgoing_ip_protocol_reg    <= 8'h11;
      outgoing_ip_source_ip_reg   <= local_ip_addr;
      outgoing_ip_dest_ip_reg     <= {8'hFF, 8'hFF, 8'hFF, 8'hFF};
      outgoing_is_roce_packet_reg <= 1'b0;

      last_ip_addr_query_reg      <= {8'hFF, 8'hFF, 8'hFF, 8'hFF};
      cached_mac_address_reg      <= 48'h00_00_00_00_00_00;

    end else begin
      state_reg                   <= state_next;

      arp_request_valid_reg       <= arp_request_valid_next;
      arp_response_ready_reg      <= arp_response_ready_next;
      drop_packet_reg             <= drop_packet_next;

      last_ip_addr_query_reg      <= last_ip_addr_query_next;
      cached_mac_address_reg      <= cached_mac_address_next;

      s_ip_hdr_ready_reg          <= s_ip_hdr_ready_next;

      outgoing_ip_dscp_reg        <= outgoing_ip_dscp_next;
      outgoing_ip_ecn_reg         <= outgoing_ip_ecn_next;
      outgoing_ip_length_reg      <= outgoing_ip_length_next;
      outgoing_ip_ttl_reg         <= outgoing_ip_ttl_next;
      outgoing_ip_protocol_reg    <= outgoing_ip_protocol_next;
      outgoing_ip_source_ip_reg   <= outgoing_ip_source_ip_next;
      outgoing_ip_dest_ip_reg     <= outgoing_ip_dest_ip_next;
      outgoing_is_roce_packet_reg <= outgoing_is_roce_packet_next;

      outgoing_ip_hdr_valid_reg   <= outgoing_ip_hdr_valid_next;

      hdr_sum_reg                 <= hdr_sum_next;
      hdr_sum_temp_reg            <= hdr_sum_temp_next;

      outgoing_eth_dest_mac_reg   <= outgoing_eth_dest_mac_next;

    end
  end

  axis_fifo #(
    .DEPTH(64),
    .RAM_PIPELINE(1),
    .DATA_WIDTH(48+6+2+16+16+8+8+16+32+1),
    .KEEP_ENABLE(0),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(0),
    .LAST_ENABLE(0)
  ) hdr_fifo (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata ({
    outgoing_eth_dest_mac_reg,
    outgoing_ip_dscp_reg,
    outgoing_ip_ecn_reg,
    outgoing_ip_length_reg,
    s_ip_identification_reg,
    outgoing_ip_ttl_reg,
    outgoing_ip_protocol_reg,
    ~hdr_sum_temp_reg[15:0],
    outgoing_ip_dest_ip_reg,
    outgoing_is_roce_packet_reg
    }),
    .s_axis_tkeep (0),
    .s_axis_tvalid(outgoing_ip_hdr_valid_reg),
    .s_axis_tready(outgoing_ip_hdr_ready),
    .s_axis_tlast (0),
    .s_axis_tuser (0),
    .s_axis_tid   (0),
    .s_axis_tdest (0),

    // AXI output
    .m_axis_tdata ({
    m_fifo_ip_eth_dest_mac,
    m_fifo_ip_dscp,
    m_fifo_ip_ecn,
    m_fifo_ip_length,
    m_fifo_ip_identification,
    m_fifo_ip_ttl,
    m_fifo_ip_protocol,
    m_fifo_ip_hdr_checksum,
    m_fifo_ip_dest_ip,
    m_fifo_is_roce_packet
    }),
    .m_axis_tkeep (),
    .m_axis_tvalid(m_fifo_ip_hdr_valid),
    .m_axis_tready(m_fifo_ip_hdr_ready),
    .m_axis_tlast (),
    .m_axis_tuser (),
    .m_axis_tid   (),
    .m_axis_tdest ()
  );


  axis_fifo #(
    .DEPTH(8192-KEEP_WIDTH), 
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(1),
    .FRAME_FIFO(1),
    .PAUSE_ENABLE(0),
    .FRAME_PAUSE(0)
  ) axis_fifo_instance (
    .clk(clk),
    .rst(rst),
    .s_axis_tdata (s_ip_payload_axis_tdata),
    .s_axis_tkeep (s_ip_payload_axis_tkeep),
    .s_axis_tvalid(s_ip_payload_axis_tvalid && !drop_packet_reg),
    .s_axis_tready(outgoing_ip_payload_axis_tready),
    .s_axis_tlast (s_ip_payload_axis_tlast),
    .s_axis_tuser (s_ip_payload_axis_tuser),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .m_axis_tdata (m_ip_fifo_payload_axis_tdata ),
    .m_axis_tkeep (m_ip_fifo_payload_axis_tkeep ),
    .m_axis_tvalid(m_ip_fifo_payload_axis_tvalid),
    .m_axis_tready(m_ip_fifo_payload_axis_tready),
    .m_axis_tlast (m_ip_fifo_payload_axis_tlast ),
    .m_axis_tuser (m_ip_fifo_payload_axis_tuser )
  );


  ip_eth_tx_test #(
    .DATA_WIDTH (DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH (KEEP_WIDTH)
  ) ip_eth_tx_test_instance (
    .clk                      (clk),
    .rst                      (rst),
    // IP frame input (from state machine)
    .s_ip_hdr_valid           (m_fifo_ip_hdr_valid),
    .s_ip_hdr_ready           (m_fifo_ip_hdr_ready),
    .s_eth_dest_mac           (m_fifo_ip_eth_dest_mac),
    .s_eth_src_mac            (local_mac_addr),
    .s_eth_type               (16'h0800),
    .s_ip_dscp                (m_fifo_ip_dscp),
    .s_ip_ecn                 (m_fifo_ip_ecn),
    .s_ip_length              (m_fifo_ip_length),
    .s_ip_identification      (m_fifo_ip_identification),
    .s_ip_flags               (3'b010),
    .s_ip_fragment_offset     (13'd0),
    .s_ip_ttl                 (m_fifo_ip_ttl),
    .s_ip_protocol            (m_fifo_ip_protocol),
    .s_ip_hdr_checksum        (m_fifo_ip_hdr_checksum),
    .s_ip_source_ip           (local_ip_addr),
    .s_ip_dest_ip             (m_fifo_ip_dest_ip),
    .s_is_roce_packet         (m_fifo_is_roce_packet),
    .s_ip_payload_axis_tdata  (m_ip_fifo_payload_axis_tdata ),
    .s_ip_payload_axis_tkeep  (m_ip_fifo_payload_axis_tkeep ),
    .s_ip_payload_axis_tvalid (m_ip_fifo_payload_axis_tvalid),
    .s_ip_payload_axis_tready (m_ip_fifo_payload_axis_tready),
    .s_ip_payload_axis_tlast  (m_ip_fifo_payload_axis_tlast ),
    .s_ip_payload_axis_tuser  (m_ip_fifo_payload_axis_tuser ),
    // Ethernet frame output
    .m_eth_hdr_valid          (tx_eth_hdr_valid),
    .m_eth_hdr_ready          (tx_eth_hdr_ready),
    .m_eth_dest_mac           (tx_eth_dest_mac),
    .m_eth_src_mac            (tx_eth_src_mac),
    .m_eth_type               (tx_eth_type),
    .m_is_roce_packet         (tx_is_roce_packet),
    .m_eth_payload_axis_tdata (tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep (tx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast (tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser (tx_eth_payload_axis_tuser),
    .busy                     ()
  );

  generate
    if (ROCE_ICRC_INSERTER) begin

      wire [  DATA_WIDTH-1:0] m_eth_payload_reg_axis_tdata;
      wire [  KEEP_WIDTH-1:0] m_eth_payload_reg_axis_tkeep;
      wire                    m_eth_payload_reg_axis_tvalid;
      wire                    m_eth_payload_reg_axis_tready;
      wire                    m_eth_payload_reg_axis_tlast;
      wire [             1:0] m_eth_payload_reg_axis_tuser;

      /*
       * ICRC insertion, only if is RoCE packet
       */
      eth_hdr_fifo eth_hdr_fifo_icrc_instance (
        .clk(clk),
        .rst(rst),

        .s_eth_hdr_valid(tx_eth_hdr_valid),
        .s_eth_hdr_ready(tx_eth_hdr_ready),
        .s_eth_dest_mac (tx_eth_dest_mac),
        .s_eth_src_mac  (tx_eth_src_mac),
        .s_eth_type     (tx_eth_type),

        .m_eth_hdr_valid(m_eth_hdr_valid),
        .m_eth_hdr_ready(m_eth_hdr_ready),
        .m_eth_dest_mac (m_eth_dest_mac),
        .m_eth_src_mac  (m_eth_src_mac),
        .m_eth_type     (m_eth_type)
      );


      // Insert ICRC
      axis_RoCE_icrc_insert #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_PIPE    (5)
      ) axis_RoCE_icrc_insert_instance (
        .clk(clk),
        .rst(rst),

        .s_eth_payload_axis_tdata (tx_eth_payload_axis_tdata),
        .s_eth_payload_axis_tkeep (tx_eth_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
        .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
        .s_eth_payload_axis_tlast (tx_eth_payload_axis_tlast),
        .s_eth_payload_axis_tuser (tx_eth_payload_axis_tuser),

        .m_eth_payload_axis_tdata (m_eth_payload_reg_axis_tdata),
        .m_eth_payload_axis_tkeep (m_eth_payload_reg_axis_tkeep),
        .m_eth_payload_axis_tvalid(m_eth_payload_reg_axis_tvalid),
        .m_eth_payload_axis_tready(m_eth_payload_reg_axis_tready),
        .m_eth_payload_axis_tlast (m_eth_payload_reg_axis_tlast),
        .m_eth_payload_axis_tuser (m_eth_payload_reg_axis_tuser),
        .busy                     ()
      );

      axis_register #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(KEEP_ENABLE),
        .KEEP_WIDTH(KEEP_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .REG_TYPE(2)
      ) axis_register_icrc_out_inst (
        .clk(clk),
        .rst(rst),

        .s_axis_tdata (m_eth_payload_reg_axis_tdata),
        .s_axis_tkeep (m_eth_payload_reg_axis_tkeep),
        .s_axis_tvalid(m_eth_payload_reg_axis_tvalid),
        .s_axis_tready(m_eth_payload_reg_axis_tready),
        .s_axis_tlast (m_eth_payload_reg_axis_tlast),
        .s_axis_tuser (m_eth_payload_reg_axis_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        .m_axis_tdata (m_eth_payload_axis_tdata),
        .m_axis_tkeep (m_eth_payload_axis_tkeep),
        .m_axis_tvalid(m_eth_payload_axis_tvalid),
        .m_axis_tready(m_eth_payload_axis_tready),
        .m_axis_tlast (m_eth_payload_axis_tlast),
        .m_axis_tuser (m_eth_payload_axis_tuser)
      );
    end else begin

      assign m_eth_hdr_valid            = tx_eth_hdr_valid;
      assign tx_eth_hdr_ready           = m_eth_hdr_ready;
      assign m_eth_dest_mac             = tx_eth_dest_mac;
      assign m_eth_src_mac              = tx_eth_src_mac;
      assign m_eth_type                 = tx_eth_type;

      assign m_eth_payload_axis_tdata   = tx_eth_payload_axis_tdata;
      assign m_eth_payload_axis_tkeep   = tx_eth_payload_axis_tkeep;
      assign m_eth_payload_axis_tvalid  = tx_eth_payload_axis_tvalid;
      assign tx_eth_payload_axis_tready = m_eth_payload_axis_tready;
      assign m_eth_payload_axis_tlast   = tx_eth_payload_axis_tlast;
      assign m_eth_payload_axis_tuser   = tx_eth_payload_axis_tuser;


    end
  endgenerate

  eth_axis_tx #(
    .DATA_WIDTH(DATA_WIDTH),
    .KEEP_ENABLE(KEEP_ENABLE),
    .KEEP_WIDTH(KEEP_WIDTH),
    .ENABLE_DOT1Q_HEADER(ENABLE_DOT1Q_HEADER)
  ) eth_axis_tx_instance (
    .clk                      (clk),
    .rst                      (rst),
    .s_eth_hdr_valid          (m_eth_hdr_valid),
    .s_eth_hdr_ready          (m_eth_hdr_ready),
    .s_eth_dest_mac           (m_eth_dest_mac),
    .s_eth_src_mac            (m_eth_src_mac),
    .s_eth_tpid               (16'd0),
    .s_eth_pcp                (3'd0),
    .s_eth_dei                (1'd0),
    .s_eth_vid                (12'd0),
    .s_eth_type               (m_eth_type),
    .s_eth_payload_axis_tdata (m_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep (m_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(m_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(m_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast (m_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser (m_eth_payload_axis_tuser),
    .m_axis_tdata             (m_stack_axis_tdata),
    .m_axis_tkeep             (m_stack_axis_tkeep),
    .m_axis_tvalid            (m_stack_axis_tvalid),
    .m_axis_tready            (m_stack_axis_tready),
    .m_axis_tlast             (m_stack_axis_tlast),
    .m_axis_tuser             (m_stack_axis_tuser),
    .busy                     ()
  );

  // finally outout arbiter from ARP-ICMP-STACK
  // Only 1 axis arbiter, no header arbitration 

  axis_arb_mux #(
    .S_COUNT              (2),
    .DATA_WIDTH           (DATA_WIDTH),
    .KEEP_ENABLE          (KEEP_ENABLE),
    .KEEP_WIDTH           (KEEP_WIDTH),
    .ID_ENABLE            (0),
    .DEST_ENABLE          (0),
    .USER_ENABLE          (1),
    .USER_WIDTH           (1),
    .ARB_TYPE_ROUND_ROBIN (0),
    .ARB_LSB_HIGH_PRIORITY(0)
  ) axis_arb_mux_instance (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata ({m_icmp_arp_axis_tdata , m_stack_axis_tdata}),
    .s_axis_tkeep ({m_icmp_arp_axis_tkeep , m_stack_axis_tkeep}),
    .s_axis_tvalid({m_icmp_arp_axis_tvalid, m_stack_axis_tvalid}),
    .s_axis_tready({m_icmp_arp_axis_tready, m_stack_axis_tready}),
    .s_axis_tlast ({m_icmp_arp_axis_tlast , m_stack_axis_tlast}),
    .s_axis_tid   (0),
    .s_axis_tdest (0),
    .s_axis_tuser ({m_icmp_arp_axis_tuser , m_stack_axis_tuser}),

    .m_axis_tdata (m_network_axis_tdata),
    .m_axis_tkeep (m_network_axis_tkeep),
    .m_axis_tvalid(m_network_axis_tvalid),
    .m_axis_tready(m_network_axis_tready),
    .m_axis_tlast (m_network_axis_tlast),
    .m_axis_tuser (m_network_axis_tuser)
  );




endmodule
