`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_retransmission_module #(
    parameter DATA_WIDTH = 64,
    parameter BUFFER_ADDR_WIDTH = 24
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE RX ACKed PSNs
     */
    input  wire         s_roce_aeth_valid,
    input  wire [ 7 :0] s_roce_rx_aeth_syndrome,
    input  wire [ 23:0] s_roce_rx_bth_psn,
    input  wire [ 7 :0] s_roce_rx_bth_op_code,
    input  wire [ 23:0] s_roce_rx_last_not_acked_psn,

    /*
     * RoCE TX frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire         s_roce_reth_valid,
    output wire         s_roce_reth_ready,
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire         s_roce_immdh_valid,
    output wire         s_roce_immdh_ready,
    input  wire [ 31:0] s_roce_immdh_data,
    // udp, ip, eth
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_identification,
    input  wire [  2:0] s_ip_flags,
    input  wire [ 12:0] s_ip_fragment_offset,
    input  wire [  7:0] s_ip_ttl,
    input  wire [  7:0] s_ip_protocol,
    input  wire [ 15:0] s_ip_header_checksum,
    input  wire [ 31:0] s_ip_source_ip,
    input  wire [ 31:0] s_ip_dest_ip,
    input  wire [ 15:0] s_udp_source_port,
    input  wire [ 15:0] s_udp_dest_port,
    input  wire [ 15:0] s_udp_length,
    input  wire [ 15:0] s_udp_checksum,
    // payload
    input  wire [DATA_WIDTH   - 1 :0] s_roce_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 :0] s_roce_payload_axis_tkeep,
    input  wire                       s_roce_payload_axis_tvalid,
    output wire                       s_roce_payload_axis_tready,
    input  wire                       s_roce_payload_axis_tlast,
    input  wire                       s_roce_payload_axis_tuser,

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
     * AXI master interface to RAM
     */
    output wire [0                :0] m_axi_awid,
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                 m_axi_awlen,
    output wire [2:0]                 m_axi_awsize,
    output wire [1:0]                 m_axi_awburst,
    output wire                       m_axi_awlock,
    output wire [3:0]                 m_axi_awcache,
    output wire [2:0]                 m_axi_awprot,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,
    output wire [DATA_WIDTH-1:0]      m_axi_wdata,
    output wire [DATA_WIDTH/8 -1:0]   m_axi_wstrb,
    output wire                       m_axi_wlast,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,
    input  wire [0:0]                 m_axi_bid,
    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready,
    output wire [0               :0]  m_axi_arid,
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arlock,
    output wire [3:0]                 m_axi_arcache,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,
    input  wire [0             :0]    m_axi_rid,
    input  wire [DATA_WIDTH  -1:0]    m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready,

    /*
    Configuration
    */
    input wire [63:0] timeout_period,
    input wire [3:0]  retry_count
);

    localparam AXI_DMA_LENGTH = 13;
    //localparam MEMORY_STEPS   = 12 - $clog2(DATA_WIDTH/8);
    localparam MEMORY_STEPS   = 12; // 4096 kB chunks

    localparam [7:0] RC_RDMA_ACK = 8'h11;

    localparam [4:0]
    STATE_IDLE = 5'd0,
    STATE_DMA_WRITE = 5'd1,
    STATE_DMA_READ_HEADER  = 5'd2,
    STATE_DMA_READ  = 5'd3;

    reg [3:0] state_reg = STATE_IDLE, state_next;

    localparam AXI_MAX_BURST_LEN = 4096/(DATA_WIDTH/8) + 1;

    reg trigger_retransmit = 1'b0;
    reg [63:0] timeout_counter;
    reg retransmit_started;

    reg reset_timeout_counter_next, reset_timeout_counter_reg;

    reg retry_counter_reg = 4'd0, retry_counter_next;

    reg [23:0] last_sent_psn_next , last_sent_psn_reg = 24'd0;
    reg [23:0] last_acked_psn_next , last_acked_psn_reg = 24'd0;
    reg [23:0] last_buffered_psn_next , last_buffered_psn_reg = 24'd0;

    reg m_roce_bth_valid_next  , m_roce_bth_valid_reg   = 1'b0;
    reg m_roce_reth_valid_next , m_roce_reth_valid_reg  = 1'b0;
    reg m_roce_immdh_valid_next, m_roce_immdh_valid_reg = 1'b0;

    reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;

    reg [23:0] s_roce_bth_psn_memory_next, s_roce_bth_psn_memory_reg;

    reg  single_packet_frame_next , single_packet_frame_reg;

    reg          retrans_roce_bth_valid_next, retrans_roce_bth_valid_reg;
    reg  [  7:0] retrans_roce_bth_op_code_next, retrans_roce_bth_op_code_reg;
    reg  [ 15:0] retrans_roce_bth_p_key_next, retrans_roce_bth_p_key_reg;
    reg  [ 23:0] retrans_roce_bth_psn_next, retrans_roce_bth_psn_reg;
    reg  [ 23:0] retrans_roce_bth_dest_qp_next, retrans_roce_bth_dest_qp_reg;
    reg          retrans_roce_bth_ack_req_next, retrans_roce_bth_ack_req_reg;

    reg          retrans_roce_reth_valid_next, retrans_roce_reth_valid_reg;
    reg          retrans_roce_reth_ready_next, retrans_roce_reth_ready_reg;
    reg  [ 63:0] retrans_roce_reth_v_addr_next, retrans_roce_reth_v_addr_reg;
    reg  [ 31:0] retrans_roce_reth_r_key_next, retrans_roce_reth_r_key_reg;
    reg  [ 31:0] retrans_roce_reth_length_next, retrans_roce_reth_length_reg;

    reg          retrans_roce_immdh_valid_next, retrans_roce_immdh_valid_reg;
    reg          retrans_roce_immdh_ready_next, retrans_roce_immdh_ready_reg;
    reg  [ 31:0] retrans_roce_immdh_data_next, retrans_roce_immdh_data_reg;

    reg [BUFFER_ADDR_WIDTH-1:0]  s_axis_dma_write_desc_addr_reg  = {BUFFER_ADDR_WIDTH{1'b0}}, s_axis_dma_write_desc_addr_next;
    reg [AXI_DMA_LENGTH-1:0]    s_axis_dma_write_desc_len_reg   = 13'b0, s_axis_dma_write_desc_len_next;
    reg                         s_axis_dma_write_desc_valid_reg = 1'b0 , s_axis_dma_write_desc_valid_next;
    reg                         s_axis_dma_write_desc_ready_reg = 1'b0 , s_axis_dma_write_desc_ready_next;

    reg [BUFFER_ADDR_WIDTH-1:0] s_axis_dma_read_desc_addr_reg  = {BUFFER_ADDR_WIDTH{1'b0}}, s_axis_dma_read_desc_addr_next;
    reg [AXI_DMA_LENGTH-1:0]    s_axis_dma_read_desc_len_reg   = 13'b0, s_axis_dma_read_desc_len_next;
    reg                         s_axis_dma_read_desc_valid_reg = 1'b0 , s_axis_dma_read_desc_valid_next;
    reg                         s_axis_dma_read_desc_ready_reg = 1'b0 , s_axis_dma_read_desc_ready_next;


    wire [BUFFER_ADDR_WIDTH-1:0] s_axis_dma_read_desc_addr;
    wire [AXI_DMA_LENGTH-1:0]  s_axis_dma_read_desc_len;
    //wire [0:0]                  s_axis_dma_read_desc_tag;
    //wire [0:0]                  s_axis_dma_read_desc_id;
    //wire [0:0]                  s_axis_dma_read_desc_dest;
    wire [0:0]                  s_axis_dma_read_desc_user = 0;
    wire                        s_axis_dma_read_desc_valid;
    wire                        s_axis_dma_read_desc_ready;

    wire [0:0]                 m_axis_dma_read_desc_status_tag;
    wire [3:0]                 m_axis_dma_read_desc_status_error;
    wire                       m_axis_dma_read_desc_status_valid;

    wire [DATA_WIDTH-1:0]      m_axis_dma_read_data_tdata;
    wire [DATA_WIDTH/8-1:0]    m_axis_dma_read_data_tkeep;
    wire                       m_axis_dma_read_data_tvalid;
    wire                       m_axis_dma_read_data_tready;
    wire                       m_axis_dma_read_data_tlast;
    wire [0:0]                 m_axis_dma_read_data_tuser;

    wire [BUFFER_ADDR_WIDTH-1:0]  s_axis_dma_write_desc_addr;
    wire [AXI_DMA_LENGTH-1:0]   s_axis_dma_write_desc_len;
    wire [0:0]                  s_axis_dma_write_desc_tag;
    wire                        s_axis_dma_write_desc_valid;
    wire                        s_axis_dma_write_desc_ready;

    wire [AXI_DMA_LENGTH-1:0]  m_axis_dma_write_desc_status_len;
    wire [0:0]                 m_axis_dma_write_desc_status_tag;
    wire [0:0]                 m_axis_dma_write_desc_status_id;
    wire [0:0]                 m_axis_dma_write_desc_status_dest;
    wire [0:0]                 m_axis_dma_write_desc_status_user;
    wire [3:0]                 m_axis_dma_write_desc_status_error;
    wire                       m_axis_dma_write_desc_status_valid;

    wire [DATA_WIDTH-1:0]      s_axis_dma_write_data_tdata;
    wire [DATA_WIDTH/8-1:0]    s_axis_dma_write_data_tkeep;
    wire                       s_axis_dma_write_data_tvalid;
    wire                       s_axis_dma_write_data_tready;
    wire                       s_axis_dma_write_data_tlast;
    wire [0:0]                 s_axis_dma_write_data_tuser;

    wire [DATA_WIDTH-1:0]      axis_bypass_tdata;
    wire [DATA_WIDTH/8-1:0]    axis_bypass_tkeep;
    wire                       axis_bypass_tvalid;
    wire                       axis_bypass_tready;
    wire                       axis_bypass_tlast;
    wire [0:0]                 axis_bypass_tuser;

    wire axis_mux_select;

    reg ram_we_reg = 1'b0, ram_we_next;
    reg [BUFFER_ADDR_WIDTH - 7 : 0] hdr_ram_addr_reg = 0, hdr_ram_addr_next;

    wire ram_we;
    wire [BUFFER_ADDR_WIDTH - 7 : 0] hdr_ram_addr;
    wire [255 :0] hdr_data_in, hdr_data_out;

    ram_block #(
        .DATA_WIDTH(256),
        .ADDR_WIDTH(BUFFER_ADDR_WIDTH - 8)
    ) header_ram_block (
        .clk(clk),
        .rst(rst),
        .write_enable(ram_we),
        .address(hdr_ram_addr),
        .data_in(hdr_data_in),
        .data_out(hdr_data_out)
    );

    // BTH fields
    assign hdr_data_in[7:0]    = s_roce_bth_op_code;
    assign hdr_data_in[23:8]   = s_roce_bth_p_key;
    assign hdr_data_in[47:24]  = s_roce_bth_dest_qp;
    assign hdr_data_in[48]     = s_roce_bth_ack_req;
    assign hdr_data_in[51:49]  = {s_roce_immdh_valid,s_roce_reth_valid, s_roce_bth_valid};
    assign hdr_data_in[55:52]  = {4{1'b0}};
    assign hdr_data_in[79:56]  = s_roce_bth_psn;
    // RETH Fields
    assign hdr_data_in[143:80]  = s_roce_reth_v_addr;
    assign hdr_data_in[175:144] = s_roce_reth_r_key;
    assign hdr_data_in[207:176] = s_roce_reth_length;
    // Immdh field
    assign hdr_data_in[239:208] = s_roce_immdh_data;
    // UDP length
    assign hdr_data_in[255:240] = s_udp_length;

    assign ram_we = s_roce_bth_valid && s_roce_bth_ready;
    assign hdr_ram_addr = axis_mux_select ? s_roce_bth_psn[BUFFER_ADDR_WIDTH - 8 - 1:0] : hdr_ram_addr_reg;

    axi_dma #(
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ADDR_WIDTH(BUFFER_ADDR_WIDTH),
        .AXI_STRB_WIDTH(DATA_WIDTH/8),
        .AXI_ID_WIDTH(1),
        .AXI_MAX_BURST_LEN(256),
        .AXIS_DATA_WIDTH(DATA_WIDTH),
        .AXIS_KEEP_ENABLE(1),
        .AXIS_KEEP_WIDTH(DATA_WIDTH/8),
        .AXIS_LAST_ENABLE(1),
        .AXIS_ID_ENABLE(0),
        .AXIS_DEST_ENABLE(0),
        .AXIS_USER_ENABLE(1),
        .AXIS_USER_WIDTH(1),
        .LEN_WIDTH(AXI_DMA_LENGTH),
        .TAG_WIDTH(1),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(0)
    ) axi_dma_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_read_desc_addr         (s_axis_dma_read_desc_addr),
        .s_axis_read_desc_len          (s_axis_dma_read_desc_len),
        .s_axis_read_desc_tag          (1'b0),
        .s_axis_read_desc_id           (1'b0),
        .s_axis_read_desc_dest         (1'b0),
        .s_axis_read_desc_user         (s_axis_dma_read_desc_user),
        .s_axis_read_desc_valid        (s_axis_dma_read_desc_valid),
        .s_axis_read_desc_ready        (s_axis_dma_read_desc_ready),

        .m_axis_read_desc_status_tag   (m_axis_dma_read_desc_status_tag),
        .m_axis_read_desc_status_error (m_axis_dma_read_desc_status_error),
        .m_axis_read_desc_status_valid (m_axis_dma_read_desc_status_valid),

        .m_axis_read_data_tdata        (m_axis_dma_read_data_tdata),
        .m_axis_read_data_tkeep        (m_axis_dma_read_data_tkeep),
        .m_axis_read_data_tvalid       (m_axis_dma_read_data_tvalid),
        .m_axis_read_data_tready       (m_axis_dma_read_data_tready),
        .m_axis_read_data_tlast        (m_axis_dma_read_data_tlast),
        .m_axis_read_data_tid          (),
        .m_axis_read_data_tdest        (),
        .m_axis_read_data_tuser        (m_axis_dma_read_data_tuser),

        .s_axis_write_desc_addr        (s_axis_dma_write_desc_addr),
        .s_axis_write_desc_len         (s_axis_dma_write_desc_len),
        .s_axis_write_desc_tag         (1'b0),
        .s_axis_write_desc_valid       (s_axis_dma_write_desc_valid),
        .s_axis_write_desc_ready       (s_axis_dma_write_desc_ready),

        .m_axis_write_desc_status_len  (m_axis_dma_write_desc_status_len),
        .m_axis_write_desc_status_tag  (m_axis_dma_write_desc_status_tag),
        .m_axis_write_desc_status_id   (m_axis_dma_write_desc_status_id),
        .m_axis_write_desc_status_dest (m_axis_dma_write_desc_status_dest),
        .m_axis_write_desc_status_user (m_axis_dma_write_desc_status_user),
        .m_axis_write_desc_status_error(m_axis_dma_write_desc_status_error),
        .m_axis_write_desc_status_valid(m_axis_dma_write_desc_status_valid),

        .s_axis_write_data_tdata       (s_axis_dma_write_data_tdata),
        .s_axis_write_data_tkeep       (s_axis_dma_write_data_tkeep),
        .s_axis_write_data_tvalid      (s_axis_dma_write_data_tvalid),
        .s_axis_write_data_tready      (s_axis_dma_write_data_tready),
        .s_axis_write_data_tlast       (s_axis_dma_write_data_tlast),
        .s_axis_write_data_tid         (0),
        .s_axis_write_data_tdest       (0),
        .s_axis_write_data_tuser       (s_axis_dma_write_data_tuser),

        .m_axi_awid                    (m_axi_awid),
        .m_axi_awaddr                  (m_axi_awaddr),
        .m_axi_awlen                   (m_axi_awlen),
        .m_axi_awsize                  (m_axi_awsize),
        .m_axi_awburst                 (m_axi_awburst),
        .m_axi_awlock                  (m_axi_awlock),
        .m_axi_awcache                 (m_axi_awcache),
        .m_axi_awprot                  (m_axi_awprot),
        .m_axi_awvalid                 (m_axi_awvalid),
        .m_axi_awready                 (m_axi_awready),
        .m_axi_wdata                   (m_axi_wdata),
        .m_axi_wstrb                   (m_axi_wstrb),
        .m_axi_wlast                   (m_axi_wlast),
        .m_axi_wvalid                  (m_axi_wvalid),
        .m_axi_wready                  (m_axi_wready),
        .m_axi_bid                     (m_axi_bid),
        .m_axi_bresp                   (m_axi_bresp),
        .m_axi_bvalid                  (m_axi_bvalid),
        .m_axi_bready                  (m_axi_bready),
        .m_axi_arid                    (m_axi_arid),
        .m_axi_araddr                  (m_axi_araddr),
        .m_axi_arlen                   (m_axi_arlen),
        .m_axi_arsize                  (m_axi_arsize),
        .m_axi_arburst                 (m_axi_arburst),
        .m_axi_arlock                  (m_axi_arlock),
        .m_axi_arcache                 (m_axi_arcache),
        .m_axi_arprot                  (m_axi_arprot),
        .m_axi_arvalid                 (m_axi_arvalid),
        .m_axi_arready                 (m_axi_arready),
        .m_axi_rid                     (m_axi_rid),
        .m_axi_rdata                   (m_axi_rdata),
        .m_axi_rresp                   (m_axi_rresp),
        .m_axi_rlast                   (m_axi_rlast),
        .m_axi_rvalid                  (m_axi_rvalid),
        .m_axi_rready                  (m_axi_rready),
        .read_enable                   (1'b1),
        .write_enable                  (1'b1),
        .write_abort                   (1'b0)
    );


    /*
Simple DMA write logic
*/
    always @* begin
        state_next                           = STATE_IDLE;

        last_sent_psn_next     = last_sent_psn_reg;
        last_buffered_psn_next = last_buffered_psn_reg;

        s_roce_bth_psn_memory_next = s_roce_bth_psn_memory_reg;

        s_roce_bth_ready_next                = 1'b0;

        reset_timeout_counter_next = 1'b0;

        s_axis_dma_read_desc_addr_next            = 0;
        s_axis_dma_read_desc_len_next             = 0;
        s_axis_dma_read_desc_valid_next           = 1'b0;

        s_axis_dma_write_desc_addr_next            = 0;
        s_axis_dma_write_desc_len_next             = 0;
        s_axis_dma_write_desc_valid_next           = 1'b0;

        m_roce_bth_valid_next           = m_roce_bth_valid_reg   && !m_roce_bth_ready;
        m_roce_reth_valid_next          = m_roce_reth_valid_reg  && !m_roce_reth_ready;
        m_roce_immdh_valid_next         = m_roce_immdh_valid_reg && !m_roce_immdh_ready;

        retrans_roce_bth_valid_next = retrans_roce_bth_valid_reg && !m_roce_bth_ready;

        hdr_ram_addr_next = (last_acked_psn_reg + 1);

        case (state_reg)
            STATE_IDLE: begin


                s_roce_bth_ready_next               = !m_roce_bth_valid_next;

                single_packet_frame_next = single_packet_frame_reg;

                if (trigger_retransmit) begin

                    m_roce_bth_valid_next   = 1'b0;
                    m_roce_reth_valid_next  = 1'b0;
                    m_roce_immdh_valid_next = 1'b0;

                    s_roce_bth_psn_memory_next = (last_acked_psn_reg + 1);
                    reset_timeout_counter_next = 1'b1;

                    state_next                           = STATE_DMA_READ_HEADER;

                end else begin
                    if (s_roce_bth_ready && s_roce_bth_valid && ~s_roce_reth_valid && ~s_roce_immdh_valid) begin
                        m_roce_bth_valid_next   = 1'b1;
                        m_roce_reth_valid_next  = 1'b0;
                        m_roce_immdh_valid_next = 1'b0;
                        s_roce_bth_ready_next   = 1'b0;
                        s_axis_dma_write_desc_addr_next =  s_roce_bth_psn << MEMORY_STEPS;
                        s_axis_dma_write_desc_len_next  =  s_udp_length - 12 - 8; // UDP length - BTH - UDP HEADER 
                        single_packet_frame_next = ((s_udp_length - 12 - 8) <= 16'd64);
                        last_sent_psn_next = s_roce_bth_psn;
                        last_buffered_psn_next = s_roce_bth_psn;
                        s_axis_dma_write_desc_valid_next = 1'b1;
                        state_next                   = STATE_DMA_WRITE;
                    end else if (s_roce_bth_ready && s_roce_bth_valid && s_roce_immdh_valid && s_roce_immdh_ready && ~s_roce_reth_valid ) begin
                        m_roce_bth_valid_next   = 1'b1;
                        m_roce_reth_valid_next  = 1'b0;
                        m_roce_immdh_valid_next = 1'b1;
                        s_roce_bth_ready_next   = 1'b0;
                        s_axis_dma_write_desc_addr_next =  s_roce_bth_psn << MEMORY_STEPS;
                        s_axis_dma_write_desc_len_next  =  s_udp_length - 12 - 4 - 8; // UDP length - BTH - IMMD - UDP HEADER 
                        last_sent_psn_next = s_roce_bth_psn;
                        last_buffered_psn_next = s_roce_bth_psn;
                        s_axis_dma_write_desc_valid_next = 1'b1;
                        state_next                   = STATE_DMA_WRITE;
                    end else if (s_roce_bth_ready && s_roce_bth_valid &&  s_roce_reth_valid &&  s_roce_reth_ready && ~s_roce_immdh_valid) begin
                        m_roce_bth_valid_next   = 1'b1;
                        m_roce_reth_valid_next  = 1'b1;
                        m_roce_immdh_valid_next = 1'b0;
                        s_roce_bth_ready_next   = 1'b0;
                        s_axis_dma_write_desc_addr_next =  s_roce_bth_psn << MEMORY_STEPS;
                        s_axis_dma_write_desc_len_next  =  s_udp_length - 12 - 16 - 8; // UDP length - BTH - RETH - UDP HEADER 
                        single_packet_frame_next = ((s_udp_length - 12 - 16 - 8) <= 16'd64);
                        last_sent_psn_next = s_roce_bth_psn;
                        last_buffered_psn_next = s_roce_bth_psn;
                        s_axis_dma_write_desc_valid_next = 1'b1;
                        state_next                   = STATE_DMA_WRITE;
                    end else if (s_roce_bth_ready && s_roce_bth_valid &&  s_roce_reth_valid && s_roce_reth_ready & s_roce_immdh_valid & s_roce_immdh_ready) begin
                        m_roce_bth_valid_next   = 1'b1;
                        m_roce_reth_valid_next  = 1'b1;
                        m_roce_immdh_valid_next = 1'b1;
                        s_roce_bth_ready_next   = 1'b0;
                        s_axis_dma_write_desc_addr_next =  s_roce_bth_psn << MEMORY_STEPS;
                        s_axis_dma_write_desc_len_next  =  s_udp_length - 12 - 16 - 4 - 8; // UDP length - BTH - RETH - IMMD - UDP HEADER
                        single_packet_frame_next = ((s_udp_length - 12 - 16 - 4 - 8) <= 16'd64);
                        last_sent_psn_next = s_roce_bth_psn;
                        last_buffered_psn_next = s_roce_bth_psn;
                        s_axis_dma_write_desc_valid_next = 1'b1;
                        state_next                   = STATE_DMA_WRITE;
                    end else  begin
                        state_next                           = STATE_IDLE;
                    end
                end

            end
            STATE_DMA_WRITE: begin
                state_next                   = STATE_DMA_WRITE;
                //m_roce_bth_valid_next        = 1'b0;
                //m_roce_reth_valid_next       = 1'b0;
                //m_roce_immdh_valid_next      = 1'b0;
                if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid && s_roce_payload_axis_tlast) begin
                    state_next                           = STATE_IDLE;
                end else if (single_packet_frame_reg) begin
                    state_next                           = STATE_IDLE;
                end
            end
            STATE_DMA_READ_HEADER: begin
                state_next                           = STATE_DMA_READ_HEADER;

                s_roce_bth_ready_next               = !m_roce_bth_valid_next;

                if (last_buffered_psn_reg + 1 == s_roce_bth_psn_memory_reg ) begin
                    state_next                           = STATE_IDLE;
                end else begin
                    hdr_ram_addr_next = s_roce_bth_psn_memory_reg;

                    if (m_roce_bth_ready) begin // TODO modify this, it does not work ..
                    //s_axis_dma_read_desc_addr_next =  s_roce_bth_psn_memory_reg << MEMORY_STEPS;
                    //s_axis_dma_read_desc_len_next  =  13'd4096; // UDP length - BTH - UDP HEADER 
                        s_axis_dma_read_desc_addr_next =  s_roce_bth_psn_memory_reg  << MEMORY_STEPS;
                        if (hdr_data_out[51:49] == 3'b111) begin //bth reth immdh
                            s_axis_dma_read_desc_len_next  =  hdr_data_out[252:240] - 12 - 16 - 4 - 8;
                        end else if (hdr_data_out[51:49] == 3'b011) begin //bth reth
                            s_axis_dma_read_desc_len_next  =  hdr_data_out[252:240] - 12 - 16 - 8;
                        end else if (hdr_data_out[51:49] == 3'b101) begin // bth immdh
                            s_axis_dma_read_desc_len_next  =  hdr_data_out[252:240] - 12 - 4 - 8;
                        end else if (hdr_data_out[51:49] == 3'b001) begin
                            s_axis_dma_read_desc_len_next  =  hdr_data_out[252:240] - 12 - 8;
                        end else begin
                            s_axis_dma_read_desc_len_next  =  hdr_data_out[252:240] - 12 - 8;
                        end
                        last_sent_psn_next = s_roce_bth_psn;
                        s_axis_dma_read_desc_valid_next = 1'b1;

                        m_roce_bth_valid_next          = hdr_data_out[49];
                        m_roce_reth_valid_next         = hdr_data_out[50];
                        m_roce_immdh_valid_next        = hdr_data_out[51];

                        retrans_roce_bth_op_code_next  = hdr_data_out[7:0];
                        retrans_roce_bth_p_key_next    = hdr_data_out[23:8];
                        retrans_roce_bth_psn_next      = s_roce_bth_psn_memory_reg;
                        retrans_roce_bth_dest_qp_next  = hdr_data_out[47:24];
                        retrans_roce_bth_ack_req_next  = hdr_data_out[48];
                        retrans_roce_reth_v_addr_next  = hdr_data_out[143:80];
                        retrans_roce_reth_r_key_next   = hdr_data_out[175:144];
                        retrans_roce_reth_length_next  = hdr_data_out[207:176];
                        retrans_roce_immdh_data_next   = hdr_data_out[239:208];

                        last_sent_psn_next = s_roce_bth_psn_memory_reg;
                        s_axis_dma_read_desc_valid_next = 1'b1;

                        state_next                           = STATE_DMA_READ;
                    end
                end
            end
            STATE_DMA_READ: begin
                state_next                   = STATE_DMA_READ;
                retrans_roce_bth_valid_next        = 1'b0;
                retrans_roce_reth_valid_next       = 1'b0;
                retrans_roce_immdh_valid_next      = 1'b0;
                s_axis_dma_read_desc_valid_next    = 1'b0;

                if (m_axis_dma_read_data_tready && m_axis_dma_read_data_tvalid && m_axis_dma_read_data_tlast) begin
                    if (trigger_retransmit) begin
                        state_next                           = STATE_IDLE;
                    end else begin
                        state_next                           = STATE_DMA_READ_HEADER;
                        s_roce_bth_psn_memory_next = s_roce_bth_psn_memory_reg + 1;
                        hdr_ram_addr_next = s_roce_bth_psn_memory_reg + 1;
                    end
                end
            end
        endcase
    end

    always @(posedge clk) begin

        if (rst) begin
            timeout_counter <= 64'd0;
        end else begin
            if (reset_timeout_counter_reg) begin
                timeout_counter <= 64'd0;
                trigger_retransmit <= 1'b0;
            end else if (s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00 && s_roce_aeth_valid) begin
                timeout_counter <= 64'd0;
                trigger_retransmit <= 1'b0;
            end else if (retransmit_started || (last_sent_psn_reg == last_acked_psn_reg)) begin
                timeout_counter <= 64'd0;
                trigger_retransmit <= 1'b0;
            end else if (timeout_counter >= timeout_period) begin
                timeout_counter <= timeout_counter;
                trigger_retransmit <= 1'b1;
            end else begin
                timeout_counter <= timeout_counter + 64'd1;
                trigger_retransmit <= 1'b0;
            end
        end

    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg                       <= STATE_IDLE;

            s_axis_dma_read_desc_addr_reg  <= 0;
            s_axis_dma_read_desc_len_reg   <= 0;
            s_axis_dma_read_desc_valid_reg <= 0;

            s_axis_dma_write_desc_addr_reg  <= 0;
            s_axis_dma_write_desc_len_reg   <= 0;
            s_axis_dma_write_desc_valid_reg <= 0;

            s_roce_bth_ready_reg <= 1'b0;

            retrans_roce_bth_valid_reg <= 1'b0;
            m_roce_bth_valid_reg <= 1'b0;

            reset_timeout_counter_reg <= 1'b0;

            single_packet_frame_reg <= 1'b0;

            last_sent_psn_reg <= 24'd0;
            last_buffered_psn_reg <= 24'd0;
        end

        if (s_roce_aeth_valid && (s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00)) begin
            last_acked_psn_reg <= s_roce_rx_bth_psn;
        end

        state_reg <= state_next;

        reset_timeout_counter_reg <= reset_timeout_counter_next;

        s_roce_bth_psn_memory_reg <= s_roce_bth_psn_memory_next;

        s_roce_bth_ready_reg <= s_roce_bth_ready_next;

        hdr_ram_addr_reg <= hdr_ram_addr_next;

        retrans_roce_bth_valid_reg <= retrans_roce_bth_valid_next;
        m_roce_bth_valid_reg       <= m_roce_bth_valid_next;
        m_roce_reth_valid_reg      <= m_roce_reth_valid_next;
        m_roce_immdh_valid_reg     <= m_roce_immdh_valid_next;

        retrans_roce_bth_op_code_reg  <= retrans_roce_bth_op_code_next;
        retrans_roce_bth_p_key_reg    <= retrans_roce_bth_p_key_next  ;
        retrans_roce_bth_psn_reg      <= retrans_roce_bth_psn_next    ;
        retrans_roce_bth_dest_qp_reg  <= retrans_roce_bth_dest_qp_next;
        retrans_roce_bth_ack_req_reg  <= retrans_roce_bth_ack_req_next;
        retrans_roce_reth_v_addr_reg  <= retrans_roce_reth_v_addr_next;
        retrans_roce_reth_r_key_reg   <= retrans_roce_reth_r_key_next ;
        retrans_roce_reth_length_reg  <= retrans_roce_reth_length_next;
        retrans_roce_immdh_data_reg   <= retrans_roce_immdh_data_next ;

        s_axis_dma_read_desc_addr_reg  <= s_axis_dma_read_desc_addr_next;
        s_axis_dma_read_desc_len_reg   <= s_axis_dma_read_desc_len_next;
        s_axis_dma_read_desc_valid_reg <= s_axis_dma_read_desc_valid_next;

        s_axis_dma_write_desc_addr_reg  <= s_axis_dma_write_desc_addr_next;
        s_axis_dma_write_desc_len_reg   <= s_axis_dma_write_desc_len_next;
        s_axis_dma_write_desc_valid_reg <= s_axis_dma_write_desc_valid_next;

        single_packet_frame_reg <= single_packet_frame_next;

        last_sent_psn_reg     <= last_sent_psn_next;
        last_buffered_psn_reg <= last_buffered_psn_next;
    end

    assign s_axis_dma_read_desc_addr  = s_axis_dma_read_desc_addr_reg  ;
    assign s_axis_dma_read_desc_len   = s_axis_dma_read_desc_len_reg   ;
    assign s_axis_dma_read_desc_valid = s_axis_dma_read_desc_valid_reg ;

    assign s_axis_dma_write_desc_addr  = s_axis_dma_write_desc_addr_reg  ;
    assign s_axis_dma_write_desc_len   = s_axis_dma_write_desc_len_reg   ;
    assign s_axis_dma_write_desc_valid = s_axis_dma_write_desc_valid_reg ;

    assign m_roce_bth_valid     = m_roce_bth_valid_reg;
    assign m_roce_reth_valid    = m_roce_reth_valid_reg;
    assign m_roce_immdh_valid   = m_roce_immdh_valid_reg;
    assign s_roce_bth_ready     = axis_mux_select ? s_roce_bth_ready_reg : 1'b0;
    assign s_roce_reth_ready    = axis_mux_select ? s_roce_bth_ready_reg : 1'b0;
    assign s_roce_immdh_ready   = axis_mux_select ? s_roce_bth_ready_reg : 1'b0;

    assign m_roce_bth_op_code   = axis_mux_select ?  s_roce_bth_op_code : retrans_roce_bth_op_code_reg;
    assign m_roce_bth_p_key     = axis_mux_select ?  s_roce_bth_p_key   : retrans_roce_bth_p_key_reg  ;
    assign m_roce_bth_psn       = axis_mux_select ?  s_roce_bth_psn     : retrans_roce_bth_psn_reg    ;
    assign m_roce_bth_dest_qp   = axis_mux_select ?  s_roce_bth_dest_qp : retrans_roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req   = axis_mux_select ?  s_roce_bth_ack_req : retrans_roce_bth_ack_req_reg;

    assign m_roce_reth_v_addr   = s_roce_reth_v_addr;
    assign m_roce_reth_r_key    = s_roce_reth_r_key;
    assign m_roce_reth_length   = s_roce_reth_length;

    assign m_roce_immdh_data    = s_roce_immdh_data;

    assign m_eth_dest_mac       = s_eth_dest_mac;
    assign m_eth_src_mac        = s_eth_src_mac;
    assign m_eth_type           = s_eth_type;
    assign m_ip_version         = s_ip_version;
    assign m_ip_ihl             = s_ip_ihl;
    assign m_ip_dscp            = s_ip_dscp;
    assign m_ip_ecn             = s_ip_ecn;
    assign m_ip_identification  = s_ip_identification;
    assign m_ip_flags           = s_ip_flags;
    assign m_ip_fragment_offset = s_ip_fragment_offset;
    assign m_ip_ttl             = s_ip_ttl;
    assign m_ip_protocol        = s_ip_protocol;
    assign m_ip_header_checksum = s_ip_header_checksum;
    assign m_ip_source_ip       = s_ip_source_ip;
    assign m_ip_dest_ip         = s_ip_dest_ip;

    assign m_udp_source_port    = s_udp_source_port;
    assign m_udp_dest_port      = s_udp_dest_port;
    assign m_udp_length         = s_udp_length;
    assign m_udp_checksum       = s_udp_checksum;

    axis_broadcast #(
        .M_COUNT(2),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) axis_broadcast_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata (s_roce_payload_axis_tdata),
        .s_axis_tkeep (s_roce_payload_axis_tkeep),
        .s_axis_tvalid(s_roce_payload_axis_tvalid),
        .s_axis_tready(s_roce_payload_axis_tready),
        .s_axis_tlast (s_roce_payload_axis_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (s_roce_payload_axis_tuser),
        .m_axis_tdata ({s_axis_dma_write_data_tdata,  axis_bypass_tdata}),
        .m_axis_tkeep ({s_axis_dma_write_data_tkeep,  axis_bypass_tkeep}),
        .m_axis_tvalid({s_axis_dma_write_data_tvalid, axis_bypass_tvalid}),
        .m_axis_tready({s_axis_dma_write_data_tready, axis_bypass_tready}),
        .m_axis_tlast ({s_axis_dma_write_data_tlast,  axis_bypass_tlast}),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser ({s_axis_dma_write_data_tuser, axis_bypass_tuser})
    );

    assign axis_mux_select = (state_reg == STATE_DMA_WRITE || state_reg == STATE_IDLE) & !trigger_retransmit;

    axis_mux #(
        .S_COUNT(2),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) axis_mux_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata ({axis_bypass_tdata , m_axis_dma_read_data_tdata}),
        .s_axis_tkeep ({axis_bypass_tkeep , m_axis_dma_read_data_tkeep}),
        .s_axis_tvalid({axis_bypass_tvalid, m_axis_dma_read_data_tvalid}),
        .s_axis_tready({axis_bypass_tready, m_axis_dma_read_data_tready}),
        .s_axis_tlast ({axis_bypass_tlast , m_axis_dma_read_data_tlast}),
        .s_axis_tid   ({0,0}),
        .s_axis_tdest ({0,0}),
        .s_axis_tuser ({axis_bypass_tuser , m_axis_dma_read_data_tuser}),
        .m_axis_tdata (m_roce_payload_axis_tdata),
        .m_axis_tkeep (m_roce_payload_axis_tkeep),
        .m_axis_tvalid(m_roce_payload_axis_tvalid),
        .m_axis_tready(m_roce_payload_axis_tready),
        .m_axis_tlast (m_roce_payload_axis_tlast),
        .m_axis_tid   (),
        .m_axis_tdest (),
        .m_axis_tuser (m_roce_payload_axis_tuser),
        .enable(1'b1),
        .select(axis_mux_select)
    );

endmodule

`resetall