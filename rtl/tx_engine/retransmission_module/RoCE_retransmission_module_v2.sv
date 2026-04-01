`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_retransmission_module_v2 #(
    parameter DATA_WIDTH = 64,
    parameter BUFFER_ADDR_WIDTH = 24,
    parameter MAX_QPS = 4,
    parameter CLOCK_PERIOD = 6.4,
    parameter DEBUG = 0
) (
    input wire clk,
    input wire rst,
    input wire rst_retry_cntr,
    input wire flow_ctrl_pause, // stops timeout counter
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
    input  wire [ 23:0] s_roce_bth_src_qp,
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
     * AXI master interface to RAM
     */
    output wire [0                :0]   m_axi_awid,
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,
    output wire [DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [DATA_WIDTH/8 -1:0]     m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,
    input  wire [0:0]                   m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,
    output wire [0               :0]    m_axi_arid,
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [0             :0]      m_axi_rid,
    input  wire [DATA_WIDTH  -1:0]      m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    /*
    Close QP in case failed transfer (e.g. rnr retry count reached, retry count reached, irreversible error)
    */
    output  wire         m_qp_close_valid,
    input   wire         m_qp_close_ready,
    output  wire [23:0]  m_qp_close_loc_qpn,
    output  wire [23:0]  m_qp_close_rem_psn,
    /*
    Status ?
    */
    output wire [MAX_QPS-1:0]            stall_qp,
    output wire [31:0]                   n_retransmit_triggers [MAX_QPS-1:0],
    output wire [31:0]                   n_rnr_retransmit_triggers [MAX_QPS-1:0],
    output wire [23:0]                   psn_diff [MAX_QPS-1:0],
    output wire [BUFFER_ADDR_WIDTH -1:0] used_memory [MAX_QPS-1:0], // in bytes
    /*
    Configuration
    */
    input wire        cfg_valid,
    input wire [63:0] timeout_period,
    input wire [2 :0] retry_count,
    input wire [2 :0] rnr_retry_count,
    input wire [31:0] loc_ip_addr,
    input wire [2 :0] pmtu,
    input wire        en_retrans
);

    import RoCE_params::*; // Imports RoCE parameters

    wire [BUFFER_ADDR_WIDTH-1:0] m_axis_dma_write_desc_addr;
    wire [12:0]                                 m_axis_dma_write_desc_len;
    wire                                        m_axis_dma_write_desc_valid;
    wire                                        m_axis_dma_write_desc_ready;

    wire [BUFFER_ADDR_WIDTH-1:0] m_axis_dma_read_desc_addr;
    wire [12:0]                                 m_axis_dma_read_desc_len;
    wire                                        m_axis_dma_read_desc_valid;
    wire                                        m_axis_dma_read_desc_ready;
    /*
     * DMA Write status
     */
    wire [12:0]                  s_axis_dma_write_desc_status_len;
    wire [3 :0]                  s_axis_dma_write_desc_status_error;
    wire                         s_axis_dma_write_desc_status_valid;
    // DMA write payload
    wire [DATA_WIDTH   - 1 :0] m_dma_write_axis_tdata;
    wire [DATA_WIDTH/8 - 1 :0] m_dma_write_axis_tkeep;
    wire                       m_dma_write_axis_tvalid;
    wire                       m_dma_write_axis_tready;
    wire                       m_dma_write_axis_tlast;
    wire                       m_dma_write_axis_tuser;
    // DMA Read payload
    wire [DATA_WIDTH   - 1 :0] s_dma_read_axis_tdata;
    wire [DATA_WIDTH/8 - 1 :0] s_dma_read_axis_tkeep;
    wire                       s_dma_read_axis_tvalid;
    wire                       s_dma_read_axis_tready;
    wire                       s_dma_read_axis_tlast;
    wire                       s_dma_read_axis_tuser;

    wire hdr_ram_we, hdr_ram_re;
    wire [BUFFER_ADDR_WIDTH-1-1:0] hdr_ram_waddr, hdr_ram_raddr;
    wire [199:0] hdr_ram_din, hdr_ram_dout;
    wire hdr_ram_dout_valid;
    reg [3:0] hdr_ram_dout_valid_pipes;

    wire                       m_rd_table_we;
    wire [$clog2(4)-1:0]       m_rd_table_qpn;
    wire [24-1:0]              m_rd_table_psn;

    wire                       s_rd_table_re;
    wire [$clog2(4)-1:0]       s_rd_table_qpn;
    wire [24-1:0]              s_rd_table_psn;

    wire                       m_wr_table_we;
    wire [$clog2(4)-1:0]       m_wr_table_qpn;
    wire [24-1:0]              m_wr_table_psn;

    wire                       s_wr_table_re;
    wire [$clog2(4)-1:0]       s_wr_table_qpn;
    wire [24-1:0]              s_wr_table_psn;

    wire                       m_cpl_table_we;
    wire [$clog2(4)-1:0]       m_cpl_table_qpn;
    wire [24-1:0]              m_cpl_table_psn;

    wire                       s_cpl_table_re;
    wire [$clog2(4)-1:0]       s_cpl_table_qpn;
    wire [24-1:0]              s_cpl_table_psn;

    RoCE_rtr_write_module #(
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_ADDR_WIDTH(BUFFER_ADDR_WIDTH),
        .MAX_QPS(4),
        .CLOCK_PERIOD(CLOCK_PERIOD),
        .DEBUG(0)
    ) RoCE_rtr_write_module_instance (
        .clk(clk),
        .rst(rst),

        .s_roce_bth_valid            (s_roce_bth_valid),
        .s_roce_bth_ready            (s_roce_bth_ready),
        .s_roce_bth_op_code          (s_roce_bth_op_code),
        .s_roce_bth_p_key            (s_roce_bth_p_key),
        .s_roce_bth_psn              (s_roce_bth_psn),
        .s_roce_bth_dest_qp          (s_roce_bth_dest_qp),
        .s_roce_bth_src_qp           (s_roce_bth_src_qp),
        .s_roce_bth_ack_req          (s_roce_bth_ack_req),
        .s_roce_reth_valid           (s_roce_reth_valid),
        .s_roce_reth_ready           (s_roce_reth_ready),
        .s_roce_reth_v_addr          (s_roce_reth_v_addr),
        .s_roce_reth_r_key           (s_roce_reth_r_key),
        .s_roce_reth_length          (s_roce_reth_length),
        .s_roce_immdh_valid          (s_roce_immdh_valid),
        .s_roce_immdh_ready          (s_roce_immdh_ready),
        .s_roce_immdh_data           (s_roce_immdh_data),
        .s_eth_dest_mac              (s_eth_dest_mac),
        .s_eth_src_mac               (s_eth_src_mac),
        .s_eth_type                  (s_eth_type),
        .s_ip_version                (s_ip_version),
        .s_ip_ihl                    (s_ip_ihl),
        .s_ip_dscp                   (s_ip_dscp),
        .s_ip_ecn                    (s_ip_ecn),
        .s_ip_identification         (s_ip_identification),
        .s_ip_flags                  (s_ip_flags),
        .s_ip_fragment_offset        (s_ip_fragment_offset),
        .s_ip_ttl                    (s_ip_ttl),
        .s_ip_protocol               (s_ip_protocol),
        .s_ip_header_checksum        (s_ip_header_checksum),
        .s_ip_source_ip              (s_ip_source_ip),
        .s_ip_dest_ip                (s_ip_dest_ip),
        .s_udp_source_port           (s_udp_source_port),
        .s_udp_dest_port             (s_udp_dest_port),
        .s_udp_length                (s_udp_length),
        .s_udp_checksum              (s_udp_checksum),

        .s_roce_payload_axis_tdata   (s_roce_payload_axis_tdata),
        .s_roce_payload_axis_tkeep   (s_roce_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid  (s_roce_payload_axis_tvalid),
        .s_roce_payload_axis_tready  (s_roce_payload_axis_tready),
        .s_roce_payload_axis_tlast   (s_roce_payload_axis_tlast),
        .s_roce_payload_axis_tuser   (s_roce_payload_axis_tuser),

        .m_axis_dma_write_desc_addr (m_axis_dma_write_desc_addr),
        .m_axis_dma_write_desc_len  (m_axis_dma_write_desc_len),
        .m_axis_dma_write_desc_valid(m_axis_dma_write_desc_valid),
        .m_axis_dma_write_desc_ready(m_axis_dma_write_desc_ready),

        .s_axis_dma_write_desc_status_len  (s_axis_dma_write_desc_status_len),
        .s_axis_dma_write_desc_status_error(s_axis_dma_write_desc_status_error),
        .s_axis_dma_write_desc_status_valid(s_axis_dma_write_desc_status_valid),

        .m_dma_write_axis_tdata (m_dma_write_axis_tdata),
        .m_dma_write_axis_tkeep (m_dma_write_axis_tkeep),
        .m_dma_write_axis_tvalid(m_dma_write_axis_tvalid),
        .m_dma_write_axis_tready(m_dma_write_axis_tready),
        .m_dma_write_axis_tlast (m_dma_write_axis_tlast),
        .m_dma_write_axis_tuser (m_dma_write_axis_tuser),

        .hdr_ram_we        (hdr_ram_we),
        .hdr_ram_addr      (hdr_ram_waddr),
        .hdr_ram_data      (hdr_ram_din),

        .m_wr_table_we  (m_wr_table_we),
        .m_wr_table_qpn (m_wr_table_qpn),
        .m_wr_table_psn (m_wr_table_psn),

        .pmtu(pmtu)
    );

    RoCE_rtr_read_module #(
        .DATA_WIDTH(DATA_WIDTH),
        .BUFFER_ADDR_WIDTH(BUFFER_ADDR_WIDTH),
        .MAX_QPS(4),
        .CLOCK_PERIOD(CLOCK_PERIOD),
        .DEBUG(DEBUG)
    ) RoCE_rtr_read_module_instance (
        .clk(clk),
        .rst(rst),
        .s_roce_rx_aeth_valid        (s_roce_rx_aeth_valid),
        .s_roce_rx_aeth_ready        (s_roce_rx_aeth_ready),
        .s_roce_rx_aeth_syndrome     (s_roce_rx_aeth_syndrome),
        .s_roce_rx_bth_psn           (s_roce_rx_bth_psn),
        .s_roce_rx_bth_op_code       (s_roce_rx_bth_op_code),
        .s_roce_rx_bth_dest_qp       (s_roce_rx_bth_dest_qp),

        .s_roce_rx_last_not_acked_psn(0),

        .m_roce_bth_valid  (m_roce_bth_valid),
        .m_roce_bth_ready  (m_roce_bth_ready),
        .m_roce_bth_op_code(m_roce_bth_op_code),
        .m_roce_bth_p_key  (m_roce_bth_p_key),
        .m_roce_bth_psn    (m_roce_bth_psn),
        .m_roce_bth_dest_qp(m_roce_bth_dest_qp),
        .m_roce_bth_src_qp (m_roce_bth_src_qp),
        .m_roce_bth_ack_req(m_roce_bth_ack_req),
        .m_roce_reth_valid (m_roce_reth_valid),
        .m_roce_reth_ready (m_roce_reth_ready),
        .m_roce_reth_v_addr(m_roce_reth_v_addr),
        .m_roce_reth_r_key (m_roce_reth_r_key),
        .m_roce_reth_length(m_roce_reth_length),
        .m_roce_immdh_valid(m_roce_immdh_valid),
        .m_roce_immdh_ready(m_roce_immdh_ready),
        .m_roce_immdh_data (m_roce_immdh_data),

        .m_eth_dest_mac      (m_eth_dest_mac),
        .m_eth_src_mac       (m_eth_src_mac),
        .m_eth_type          (m_eth_type),
        .m_ip_version        (m_ip_version),
        .m_ip_ihl            (m_ip_ihl),
        .m_ip_dscp           (m_ip_dscp),
        .m_ip_ecn            (m_ip_ecn),
        .m_ip_identification (m_ip_identification),
        .m_ip_flags          (m_ip_flags),
        .m_ip_fragment_offset(m_ip_fragment_offset),
        .m_ip_ttl            (m_ip_ttl),
        .m_ip_protocol       (m_ip_protocol),
        .m_ip_header_checksum(m_ip_header_checksum),
        .m_ip_source_ip      (m_ip_source_ip),
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

        .m_axis_dma_read_desc_addr (m_axis_dma_read_desc_addr),
        .m_axis_dma_read_desc_len  (m_axis_dma_read_desc_len),
        .m_axis_dma_read_desc_valid(m_axis_dma_read_desc_valid),
        .m_axis_dma_read_desc_ready(m_axis_dma_read_desc_ready),

        .s_axis_dma_read_desc_status_len(),
        .s_axis_dma_read_desc_status_error(),
        .s_axis_dma_read_desc_status_valid(),

        .s_dma_read_axis_tdata (s_dma_read_axis_tdata),
        .s_dma_read_axis_tkeep (s_dma_read_axis_tkeep),
        .s_dma_read_axis_tvalid(s_dma_read_axis_tvalid),
        .s_dma_read_axis_tready(s_dma_read_axis_tready),
        .s_dma_read_axis_tlast (s_dma_read_axis_tlast),
        .s_dma_read_axis_tuser (s_dma_read_axis_tuser),

        .hdr_ram_re        (hdr_ram_re),
        .hdr_ram_addr      (hdr_ram_raddr),
        .hdr_ram_data      (hdr_ram_dout),
        .hdr_ram_data_valid(hdr_ram_dout_valid),

        .m_rd_table_we  (m_rd_table_we),
        .m_rd_table_qpn (m_rd_table_qpn),
        .m_rd_table_psn (m_rd_table_psn),

        .s_rd_table_re  (s_rd_table_re),
        .s_rd_table_qpn (s_rd_table_qpn),
        .s_rd_table_psn (s_rd_table_psn),

        .s_wr_table_re  (s_wr_table_re),
        .s_wr_table_qpn (s_wr_table_qpn),
        .s_wr_table_psn (s_wr_table_psn),

        .s_cpl_table_re (s_cpl_table_re),
        .s_cpl_table_qpn(s_cpl_table_qpn),
        .s_cpl_table_psn(s_cpl_table_psn),

        .mem_full(),
        .stall_qp(stall_qp),
        .loc_ip_addr(loc_ip_addr),
        .pmtu(pmtu),
        .timeout_period(32'd5000)
    );

    simple_dpram #(
        .ADDR_WIDTH(BUFFER_ADDR_WIDTH-8),
        .DATA_WIDTH(200),
        .STRB_WIDTH(1),
        .NPIPES(2),
        .STYLE("auto")
    ) hdr_ram_instance (
        .clk(clk),
        .rst(rst),
        .waddr(hdr_ram_waddr),
        .raddr(hdr_ram_raddr),
        .din(hdr_ram_din),
        .dout(hdr_ram_dout),
        .strb(1),
        .ena(1'b1),
        .ren(hdr_ram_re),
        .wen(hdr_ram_we)
    );

    always @(posedge clk) begin
        hdr_ram_dout_valid_pipes[3:0] <= {hdr_ram_dout_valid_pipes[2:0], hdr_ram_re};
    end
    assign hdr_ram_dout_valid = hdr_ram_dout_valid_pipes[3];

    simple_dpram #(
        .ADDR_WIDTH($clog2(4)),
        .DATA_WIDTH(24),
        .STRB_WIDTH(1),
        .NPIPES(-1),
        .INIT_VALUE(24'hff_ffff),
        .STYLE("auto")
    ) wr_table_instance (
        .clk(clk),
        .rst(rst),
        .waddr(m_wr_table_qpn),
        .raddr(s_wr_table_qpn),
        .din(m_wr_table_psn),
        .dout(s_wr_table_psn),
        .strb(1),
        .ena(1'b1),
        .ren(s_wr_table_re),
        .wen(m_wr_table_we)
    );

    simple_dpram #(
        .ADDR_WIDTH($clog2(4)),
        .DATA_WIDTH(24),
        .STRB_WIDTH(1),
        .NPIPES(-1),
        .INIT_VALUE(24'hff_ffff),
        .STYLE("auto")
    ) rd_table_instance (
        .clk(clk),
        .rst(rst),
        .waddr (m_rd_table_qpn),
        .raddr (s_rd_table_qpn),
        .din   (m_rd_table_psn),
        .dout  (s_rd_table_psn),
        .strb  (1),
        .ena   (1'b1),
        .ren   (s_rd_table_re),
        .wen   (m_rd_table_we)
    );

    assign m_cpl_table_we  = s_roce_rx_aeth_valid & s_roce_rx_aeth_ready && s_roce_rx_bth_op_code == RC_RDMA_ACK && s_roce_rx_aeth_syndrome[6:5] == 2'b00;
    assign m_cpl_table_qpn = s_roce_rx_bth_dest_qp;
    assign m_cpl_table_psn = s_roce_rx_bth_psn;

    simple_dpram #(
        .ADDR_WIDTH($clog2(4)),
        .DATA_WIDTH(24),
        .STRB_WIDTH(1),
        .NPIPES(-1),
        .INIT_VALUE(24'hff_ffff),
        .STYLE("auto")
    ) cpl_table_instance (
        .clk(clk),
        .rst(rst),
        .waddr (m_cpl_table_qpn),
        .raddr (s_cpl_table_qpn),
        .din   (m_cpl_table_psn),
        .dout  (s_cpl_table_psn),
        .strb  (1),
        .ena   (1'b1),
        .ren   (s_cpl_table_re),
        .wen   (m_cpl_table_we)
    );

    /*
    AXI fifo INTERFACE
    */
    wire [0                :0]                  m_axi_fifo_awid;
    wire [BUFFER_ADDR_WIDTH-1:0] m_axi_fifo_awaddr;
    wire [7:0]                                  m_axi_fifo_awlen;
    wire [2:0]                                  m_axi_fifo_awsize;
    wire [1:0]                                  m_axi_fifo_awburst;
    wire                                        m_axi_fifo_awlock;
    wire [3:0]                                  m_axi_fifo_awcache;
    wire [2:0]                                  m_axi_fifo_awprot;
    wire                                        m_axi_fifo_awvalid;
    wire                                        m_axi_fifo_awready;
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_fifo_wdata;
    wire [DATA_WIDTH/8 - 1 : 0]                 m_axi_fifo_wstrb;
    wire                                        m_axi_fifo_wlast;
    wire                                        m_axi_fifo_wvalid;
    wire                                        m_axi_fifo_wready;
    wire [0             :0]                     m_axi_fifo_bid;
    wire [1:0]                                  m_axi_fifo_bresp;
    wire                                        m_axi_fifo_bvalid;
    wire                                        m_axi_fifo_bready;
    wire [0               :0]                   m_axi_fifo_arid;
    wire [BUFFER_ADDR_WIDTH-1:0] m_axi_fifo_araddr;
    wire [7:0]                                  m_axi_fifo_arlen;
    wire [2:0]                                  m_axi_fifo_arsize;
    wire [1:0]                                  m_axi_fifo_arburst;
    wire                                        m_axi_fifo_arlock;
    wire [3:0]                                  m_axi_fifo_arcache;
    wire [2:0]                                  m_axi_fifo_arprot;
    wire                                        m_axi_fifo_arvalid;
    wire                                        m_axi_fifo_arready;
    wire [0             :0]                     m_axi_fifo_rid;
    wire [DATA_WIDTH   - 1 : 0]                 m_axi_fifo_rdata;
    wire [1:0]                                  m_axi_fifo_rresp;
    wire                                        m_axi_fifo_rlast;
    wire                                        m_axi_fifo_rvalid;
    wire                                        m_axi_fifo_rready;


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
        .LEN_WIDTH(13),
        .TAG_WIDTH(1),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(1)
    ) axi_dma_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_read_desc_addr         (m_axis_dma_read_desc_addr),
        .s_axis_read_desc_len          (m_axis_dma_read_desc_len),
        .s_axis_read_desc_tag          (0),
        .s_axis_read_desc_id           (0),
        .s_axis_read_desc_dest         (0),
        .s_axis_read_desc_user         (0),
        .s_axis_read_desc_valid        (m_axis_dma_read_desc_valid),
        .s_axis_read_desc_ready        (m_axis_dma_read_desc_ready),

        .m_axis_read_desc_status_tag   (),
        .m_axis_read_desc_status_error (),
        .m_axis_read_desc_status_valid (),

        .m_axis_read_data_tdata        (s_dma_read_axis_tdata),
        .m_axis_read_data_tkeep        (s_dma_read_axis_tkeep),
        .m_axis_read_data_tvalid       (s_dma_read_axis_tvalid),
        .m_axis_read_data_tready       (s_dma_read_axis_tready),
        .m_axis_read_data_tlast        (s_dma_read_axis_tlast),
        .m_axis_read_data_tid          (),
        .m_axis_read_data_tdest        (),
        .m_axis_read_data_tuser        (s_dma_read_axis_tuser),

        .s_axis_write_desc_addr        (m_axis_dma_write_desc_addr),
        .s_axis_write_desc_len         (m_axis_dma_write_desc_len),
        .s_axis_write_desc_tag         (1'b0),
        .s_axis_write_desc_valid       (m_axis_dma_write_desc_valid),
        .s_axis_write_desc_ready       (m_axis_dma_write_desc_ready),

        .m_axis_write_desc_status_len  (s_axis_dma_write_desc_status_len),
        .m_axis_write_desc_status_tag  (),
        .m_axis_write_desc_status_id   (),
        .m_axis_write_desc_status_dest (),
        .m_axis_write_desc_status_user (),
        .m_axis_write_desc_status_error(s_axis_dma_write_desc_status_error),
        .m_axis_write_desc_status_valid(s_axis_dma_write_desc_status_valid),

        .s_axis_write_data_tdata       (m_dma_write_axis_tdata),
        .s_axis_write_data_tkeep       (m_dma_write_axis_tkeep),
        .s_axis_write_data_tvalid      (m_dma_write_axis_tvalid),
        .s_axis_write_data_tready      (m_dma_write_axis_tready),
        .s_axis_write_data_tlast       (m_dma_write_axis_tlast),
        .s_axis_write_data_tid         (0),
        .s_axis_write_data_tdest       (0),
        .s_axis_write_data_tuser       (m_dma_write_axis_tuser),

        .m_axi_awid                    (m_axi_fifo_awid),
        .m_axi_awaddr                  (m_axi_fifo_awaddr),
        .m_axi_awlen                   (m_axi_fifo_awlen),
        .m_axi_awsize                  (m_axi_fifo_awsize),
        .m_axi_awburst                 (m_axi_fifo_awburst),
        .m_axi_awlock                  (m_axi_fifo_awlock),
        .m_axi_awcache                 (m_axi_fifo_awcache),
        .m_axi_awprot                  (m_axi_fifo_awprot),
        .m_axi_awvalid                 (m_axi_fifo_awvalid),
        .m_axi_awready                 (m_axi_fifo_awready),
        .m_axi_wdata                   (m_axi_fifo_wdata),
        .m_axi_wstrb                   (m_axi_fifo_wstrb),
        .m_axi_wlast                   (m_axi_fifo_wlast),
        .m_axi_wvalid                  (m_axi_fifo_wvalid),
        .m_axi_wready                  (m_axi_fifo_wready),
        .m_axi_bid                     (m_axi_fifo_bid),
        .m_axi_bresp                   (m_axi_fifo_bresp),
        .m_axi_bvalid                  (m_axi_fifo_bvalid),
        .m_axi_bready                  (m_axi_fifo_bready),
        .m_axi_arid                    (m_axi_fifo_arid),
        .m_axi_araddr                  (m_axi_fifo_araddr),
        .m_axi_arlen                   (m_axi_fifo_arlen),
        .m_axi_arsize                  (m_axi_fifo_arsize),
        .m_axi_arburst                 (m_axi_fifo_arburst),
        .m_axi_arlock                  (m_axi_fifo_arlock),
        .m_axi_arcache                 (m_axi_fifo_arcache),
        .m_axi_arprot                  (m_axi_fifo_arprot),
        .m_axi_arvalid                 (m_axi_fifo_arvalid),
        .m_axi_arready                 (m_axi_fifo_arready),
        .m_axi_rid                     (m_axi_fifo_rid),
        .m_axi_rdata                   (m_axi_fifo_rdata),
        .m_axi_rresp                   (m_axi_fifo_rresp),
        .m_axi_rlast                   (m_axi_fifo_rlast),
        .m_axi_rvalid                  (m_axi_fifo_rvalid),
        .m_axi_rready                  (m_axi_fifo_rready),
        .read_enable                   (1'b1),
        .write_enable                  (1'b1),
        .write_abort                   (1'b0)
    );

    axi_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(BUFFER_ADDR_WIDTH),
        .STRB_WIDTH(DATA_WIDTH/8),
        .ID_WIDTH(1),
        .WRITE_FIFO_DEPTH(16),
        .READ_FIFO_DEPTH(16)
    ) axi_fifo_instance (
        .clk(clk),
        .rst(rst),
        .s_axi_awid    (m_axi_fifo_awid),
        .s_axi_awaddr  (m_axi_fifo_awaddr),
        .s_axi_awlen   (m_axi_fifo_awlen),
        .s_axi_awsize  (m_axi_fifo_awsize),
        .s_axi_awburst (m_axi_fifo_awburst),
        .s_axi_awlock  (m_axi_fifo_awlock),
        .s_axi_awcache (m_axi_fifo_awcache),
        .s_axi_awprot  (m_axi_fifo_awprot),

        .s_axi_awvalid (m_axi_fifo_awvalid),
        .s_axi_awready (m_axi_fifo_awready),
        .s_axi_wdata   (m_axi_fifo_wdata),
        .s_axi_wstrb   (m_axi_fifo_wstrb),
        .s_axi_wlast   (m_axi_fifo_wlast),

        .s_axi_wvalid  (m_axi_fifo_wvalid),
        .s_axi_wready  (m_axi_fifo_wready),
        .s_axi_bid     (m_axi_fifo_bid),
        .s_axi_bresp   (m_axi_fifo_bresp),

        .s_axi_bvalid  (m_axi_fifo_bvalid),
        .s_axi_bready  (m_axi_fifo_bready),
        .s_axi_arid    (m_axi_fifo_arid),
        .s_axi_araddr  (m_axi_fifo_araddr),
        .s_axi_arlen   (m_axi_fifo_arlen),
        .s_axi_arsize  (m_axi_fifo_arsize),
        .s_axi_arburst (m_axi_fifo_arburst),
        .s_axi_arlock  (m_axi_fifo_arlock),
        .s_axi_arcache (m_axi_fifo_arcache),
        .s_axi_arprot  (m_axi_fifo_arprot),

        .s_axi_arvalid (m_axi_fifo_arvalid),
        .s_axi_arready (m_axi_fifo_arready),
        .s_axi_rid     (m_axi_fifo_rid),
        .s_axi_rdata   (m_axi_fifo_rdata),
        .s_axi_rresp   (m_axi_fifo_rresp),
        .s_axi_rlast   (m_axi_fifo_rlast),

        .s_axi_rvalid  (m_axi_fifo_rvalid),
        .s_axi_rready  (m_axi_fifo_rready),
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


endmodule