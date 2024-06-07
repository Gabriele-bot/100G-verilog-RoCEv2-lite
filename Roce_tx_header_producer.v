
`resetall `timescale 1ns / 1ps `default_nettype none


module Roce_tx_header_producer #(
    parameter DATA_WIDTH = 64
) (
    input wire clk,
    input wire rst,

    /*
     * AXIS input
     */
    input  wire [  DATA_WIDTH - 1:0] s_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1:0] s_axis_tkeep,
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire                      s_axis_tlast,
    input  wire                      s_axis_tuser,


    /*
     * RoCE frame output
     */
    // BTH
    output wire                      m_roce_bth_valid,
    input  wire                      m_roce_bth_ready,
    output wire [               7:0] m_roce_bth_op_code,
    output wire [              15:0] m_roce_bth_p_key,
    output wire [              23:0] m_roce_bth_psn,
    output wire [              23:0] m_roce_bth_dest_qp,
    output wire                      m_roce_bth_ack_req,
    // RETH              
    output wire                      m_roce_reth_valid,
    input  wire                      m_roce_reth_ready,
    output wire [              63:0] m_roce_reth_v_addr,
    output wire [              31:0] m_roce_reth_r_key,
    output wire [              31:0] m_roce_reth_length,
    // IMMD              
    output wire                      m_roce_immdh_valid,
    input  wire                      m_roce_immdh_ready,
    output wire [              31:0] m_roce_immdh_data,
    // udp, ip, eth      
    output wire [              47:0] m_eth_dest_mac,
    output wire [              47:0] m_eth_src_mac,
    output wire [              15:0] m_eth_type,
    output wire [               3:0] m_ip_version,
    output wire [               3:0] m_ip_ihl,
    output wire [               5:0] m_ip_dscp,
    output wire [               1:0] m_ip_ecn,
    output wire [              15:0] m_ip_identification,
    output wire [               2:0] m_ip_flags,
    output wire [              12:0] m_ip_fragment_offset,
    output wire [               7:0] m_ip_ttl,
    output wire [               7:0] m_ip_protocol,
    output wire [              15:0] m_ip_header_checksum,
    output wire [              31:0] m_ip_source_ip,
    output wire [              31:0] m_ip_dest_ip,
    output wire [              15:0] m_udp_source_port,
    output wire [              15:0] m_udp_dest_port,
    output wire [              15:0] m_udp_length,
    output wire [              15:0] m_udp_checksum,
    // stream
    output wire [DATA_WIDTH   - 1:0] m_roce_payload_axis_tdata,
    output wire [DATA_WIDTH/8 - 1:0] m_roce_payload_axis_tkeep,
    output wire                      m_roce_payload_axis_tvalid,
    input  wire                      m_roce_payload_axis_tready,
    output wire                      m_roce_payload_axis_tlast,
    output wire                      m_roce_payload_axis_tuser

);
  localparam [7:0]
    RC_RDMA_WRITE_FIRST   = 8'h06,
    RC_RDMA_WRITE_MIDDLE  = 8'h07,
    RC_RDMA_WRITE_LAST    = 8'h08,
    RC_RDMA_WRITE_LAST_IMD= 8'h09,
    RC_RDMA_WRITE_ONLY    = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
    RC_RDMA_ACK           = 8'h11;

  localparam [2:0]
    STATE_IDLE   = 3'd0,
    STATE_FIRST  = 3'd1,
    STATE_MIDDLE = 3'd2,
    STATE_LAST   = 3'd3,
    STATE_ONLY   = 3'd4,
    STATE_ERROR  = 3'd5;

  reg [2:0] state_reg, state_next;

  localparam [31:0] LOC_IP_ADDR = 32'hD1D40116;
  localparam [15:0] LOC_UDP_PORT = 16'h0123;
  localparam [15:0] ROCE_UDP_PORT = 16'h12B7;
  localparam [15:0] PMTU = 16'd2048;


  reg roce_bth_valid_next, roce_bth_valid_reg;
  reg roce_reth_valid_next, roce_reth_valid_reg;
  reg roce_immdh_valid_next, roce_immdh_valid_reg;


  reg [7:0] roce_bth_op_code_next, roce_bth_op_code_reg;
  reg [15:0] roce_bth_p_key_next, roce_bth_p_key_reg;
  reg [23:0] roce_bth_psn_next, roce_bth_psn_reg;
  reg [23:0] roce_bth_dest_qp_next, roce_bth_dest_qp_reg;
  reg roce_bth_ack_req_next, roce_bth_ack_req_reg;

  reg [63:0] roce_reth_v_addr_next, roce_reth_v_addr_reg;
  reg [31:0] roce_reth_r_key_next, roce_reth_r_key_reg;
  reg [31:0] roce_reth_length_next, roce_reth_length_reg;

  reg [31:0] roce_immdh_data_next, roce_immdh_data_reg;

  reg [47:0] eth_dest_mac_next, eth_dest_mac_reg;
  reg [47:0] eth_src_mac_next, eth_src_mac_reg;
  reg [15:0] eth_type_next, eth_type_reg;
  reg [3:0] ip_version_next, ip_version_reg;
  reg [3:0] ip_ihl_next, ip_ihl_reg;
  reg [5:0] ip_dscp_next, ip_dscp_reg;
  reg [1:0] ip_ecn_next, ip_ecn_reg;
  reg [15:0] ip_identification_next, ip_identification_reg;
  reg [2:0] ip_flags_next, ip_flags_reg;
  reg [12:0] ip_fragment_offset_next, ip_fragment_offset_reg;
  reg [7:0] ip_ttl_next, ip_ttl_reg;
  reg [7:0] ip_protocol_next, ip_protocol_reg;
  reg [15:0] ip_header_checksum_next, ip_header_checksum_reg;
  reg [31:0] ip_source_ip_next, ip_source_ip_reg;
  reg [31:0] ip_dest_ip_next, ip_dest_ip_reg;
  reg [15:0] udp_source_port_next, udp_source_port_reg;
  reg [15:0] udp_dest_port_next, udp_dest_port_reg;
  reg [15:0] udp_length_next, udp_length_reg;
  reg [15:0] udp_checksum_next, udp_checksum_reg;


  reg [170:0] qp_info = {{64{1'b0}}, 32'h11223344, 24'h012345, 24'h543210, 24'h000016, 3'b010};
  //assign qp_info[2:0]     = 3'b010;  //qp_state
  //assign qp_info[26:3]    = 24'h000016;  //loc_qpn
  //assign qp_info[50:27]   = 24'h543210;  //rem_psn
  //assign qp_info[74:51]   = 24'h012345;  //loc_psn
  //assign qp_info[106:52]  = 32'h11223344;  //r_key
  //assign qp_info[170:107] = 64'h000000000000;  //vaddr

  reg [154:0] qp_conn = {ROCE_UDP_PORT, 32'h0BD40116, 24'h000016, 24'h000017};
  //assign qp_conn[23:0]  = 24'h000017;  //loc_qpn
  //assign qp_conn[47:24] = 24'h000016;  //rem_qpn
  //assign qp_conn[79:48] = 32'h0BD40116;  //rem_ip_addr
  //assign qp_conn[95:80] = ROCE_UDP_PORT;  //rem_udp_port

  reg [79:0] tx_metadata = {48'h001122334455, 32'd3200};
  //assign tx_metadata[31:0]  = 32'd3200;  //dma_length
  //assign tx_metadata[79:32] = 48'h001122334455;  //rem_addr

  reg [31:0] remaining_length;
  reg [13:0] packet_inst_length;  // MAX 16384

  reg [23:0] curr_psn;

  reg [2:0] axis_valid_shreg;

  reg first_axi_frame;
  reg last_axi_frame;

  reg [DATA_WIDTH - 1:0] axis_tdata_reg;
  reg [DATA_WIDTH/8 - 1:0] axis_tkeep_reg;
  reg axis_tvalid_reg;
  reg axis_tready_reg = 1'b0;
  reg axis_tlast_reg;
  reg axis_tuser_reg;

  reg [DATA_WIDTH - 1:0] m_axis_tdata_reg;
  reg [DATA_WIDTH/8 - 1:0] m_axis_tkeep_reg;
  reg m_axis_tvalid_reg;
  reg m_axis_tready_reg = 1'b0;
  reg m_axis_tlast_reg;
  reg m_axis_tuser_reg;


  always @* begin

    state_next = STATE_IDLE;

    case (state_reg)
      STATE_IDLE: begin
        roce_bth_valid_next     = 1'b0;
        roce_reth_valid_next    = 1'b0;
        roce_immdh_valid_next   = 1'b0;


        eth_dest_mac_next       = 48'hFF;
        eth_src_mac_next        = 48'hFF;
        eth_type_next           = 16'hFF;
        ip_version_next         = 4'd4;
        ip_ihl_next             = 4'd4;
        ip_dscp_next            = 6'h0;
        ip_ecn_next             = 2'h0;
        ip_identification_next  = 16'h0;
        ip_flags_next           = 3'b001;
        ip_fragment_offset_next = 13'hFF;
        ip_ttl_next             = 8'hFF;
        ip_protocol_next        = 8'd11;
        ip_header_checksum_next = 16'd0;
        ip_source_ip_next       = 32'h0;
        ip_dest_ip_next         = 32'h0;
        udp_source_port_next    = 16'd4;
        udp_dest_port_next      = 16'd4;
        udp_length_next         = 16'h0;
        udp_checksum_next       = 16'h0;
        roce_bth_op_code_next   = RC_RDMA_WRITE_ONLY;
        roce_bth_p_key_next     = 16'd11;
        roce_bth_psn_next       = 24'd11;
        roce_bth_dest_qp_next   = 24'd0;
        roce_bth_ack_req_next   = 1'b0;
        roce_reth_v_addr_next   = 48'd0;
        roce_reth_r_key_next    = 32'd4;
        roce_reth_length_next   = 16'h0;
        roce_immdh_data_next    = 32'h0;

        if (s_axis_tready && s_axis_tvalid) begin
          if (qp_conn[31:0] <= PMTU) begin
            state_next <= STATE_ONLY;
          end else begin
            state_next <= STATE_FIRST;
          end
        end
      end
      STATE_FIRST: begin

        state_next            = state_reg;

        roce_bth_valid_next   = first_axi_frame;
        roce_reth_valid_next  = first_axi_frame;
        roce_immdh_valid_next = 1'b0;

        ip_source_ip_next     = LOC_IP_ADDR;
        ip_dest_ip_next       = qp_conn[79:48];

        udp_source_port_next  = LOC_UDP_PORT;
        udp_length_next       = PMTU + 12 + 16 + 8;

        roce_bth_op_code_next = RC_RDMA_WRITE_FIRST;
        roce_bth_p_key_next   = 16'hFFFF;
        roce_bth_psn_next     = curr_psn;
        roce_bth_dest_qp_next = qp_conn[47:24];
        roce_bth_ack_req_next = 1'b0;
        roce_reth_v_addr_next = qp_info[154:107];
        roce_reth_r_key_next  = qp_info[106:52];
        roce_reth_length_next = tx_metadata[31:0];
        roce_immdh_data_next  = 32'hDEADBEEF;


        if (m_roce_payload_axis_tready && m_roce_payload_axis_tvalid) begin
          if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
            state_next <= STATE_LAST;
          end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
            state_next <= STATE_MIDDLE;
          end
        end
      end
      STATE_MIDDLE: begin

        state_next            = state_reg;

        roce_bth_valid_next   = first_axi_frame;
        roce_reth_valid_next  = 1'b0;
        roce_immdh_valid_next = 1'b0;

        udp_length_next       = PMTU + 12 + 8;  //no RETH

        roce_bth_op_code_next = RC_RDMA_WRITE_MIDDLE;
        roce_bth_psn_next     = curr_psn;

        if (s_axis_tready && s_axis_tvalid) begin
          if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
            state_next <= STATE_LAST;
          end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
            state_next <= STATE_MIDDLE;
          end
        end
      end
      STATE_LAST: begin

        state_next = state_reg;

        roce_bth_valid_next = first_axi_frame;
        roce_reth_valid_next = 1'b0;
        roce_immdh_valid_next = 1'b0;

        if (first_axi_frame) begin
          udp_length_next = remaining_length + 12 + 8;  // no reth
        end
        roce_bth_op_code_next = RC_RDMA_WRITE_LAST;
        roce_bth_psn_next     = curr_psn;

        if (s_axis_tready && s_axis_tvalid) begin
          if (remaining_length - DATA_WIDTH / 8 == 0) begin
            state_next <= STATE_IDLE;
          end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
            state_next <= STATE_ERROR;
          end
        end
      end
      STATE_ONLY: begin

        state_next            = state_reg;

        roce_bth_valid_next   = first_axi_frame;
        roce_reth_valid_next  = first_axi_frame;
        roce_immdh_valid_next = 1'b0;

        ip_source_ip_next     = LOC_IP_ADDR;
        ip_dest_ip_next       = qp_conn[79:48];

        udp_source_port_next  = LOC_UDP_PORT;
        udp_length_next       = tx_metadata[31:0] + 12 + 16 + 8;

        roce_bth_op_code_next = RC_RDMA_WRITE_ONLY;
        roce_bth_p_key_next   = 16'hFFFF;
        roce_bth_psn_next     = curr_psn;
        roce_bth_dest_qp_next = qp_conn[47:24];
        roce_bth_ack_req_next = 1'b0;
        roce_reth_v_addr_next = qp_info[154:107];
        roce_reth_r_key_next  = qp_info[106:52];
        roce_reth_length_next = tx_metadata[31:0];
        roce_immdh_data_next  = 32'hDEADBEEF;

        if (s_axis_tready && s_axis_tvalid) begin
          if (packet_inst_length + DATA_WIDTH / 8 >= PMTU) begin
            state_next <= STATE_IDLE;
          end
        end
      end
      STATE_ERROR: begin
        state_next = state_reg;
        if (rst) begin
          state_next = STATE_IDLE;
        end
      end
    endcase
  end

  //assign first_axi_frame = (packet_inst_length < DATA_WIDTH / 8) ? 1'b1 : 1'b0;
  //assign last_axi_frame  = (packet_inst_length + DATA_WIDTH / 8 == PMTU) ? 1'b1 : 1'b0;
  always @(posedge clk) begin
    first_axi_frame <= (packet_inst_length < DATA_WIDTH / 8) ? 1'b1 : 1'b0;
    last_axi_frame  <= (packet_inst_length + DATA_WIDTH / 8 == PMTU) ? 1'b1 : 1'b0;
  end

  always @(posedge clk) begin
    if (state_next == STATE_IDLE) begin
      remaining_length   <= tx_metadata[31:0];
      packet_inst_length <= 14'd0;
    end else begin
      if (packet_inst_length + DATA_WIDTH / 8 == PMTU) begin
        packet_inst_length <= 14'd0;
      end else if (s_axis_tready && s_axis_tvalid) begin
        remaining_length   <= remaining_length - DATA_WIDTH / 8;
        packet_inst_length <= packet_inst_length + DATA_WIDTH / 8;
      end
    end
  end

  always @(posedge clk) begin
    if (state_next == STATE_IDLE) begin
      curr_psn <= qp_info[74:51];  // loc psn
    end else begin
      if (s_axis_tready && s_axis_tvalid) begin
        if (packet_inst_length + DATA_WIDTH / 8 >= PMTU) begin
          curr_psn <= curr_psn + 1;
        end
      end
    end
  end

  always @(posedge clk) begin

    if (rst) begin
      state_reg <= STATE_IDLE;
    end else begin
      state_reg              <= state_next;

      roce_bth_valid_reg     <= roce_bth_valid_next;
      roce_reth_valid_reg    <= roce_reth_valid_next;
      roce_immdh_valid_reg   <= roce_immdh_valid_next;

      roce_bth_op_code_reg   <= roce_bth_op_code_next;
      roce_bth_p_key_reg     <= roce_bth_p_key_next;
      roce_bth_psn_reg       <= roce_bth_psn_next;
      roce_bth_dest_qp_reg   <= roce_bth_dest_qp_next;
      roce_bth_ack_req_reg   <= roce_bth_ack_req_next;

      roce_reth_v_addr_reg   <= roce_reth_v_addr_next;
      roce_reth_r_key_reg    <= roce_reth_r_key_next;
      roce_reth_length_reg   <= roce_reth_length_next;

      roce_immdh_data_reg    <= roce_immdh_data_next;

      eth_dest_mac_reg       <= eth_dest_mac_next;
      eth_src_mac_reg        <= eth_src_mac_next;
      eth_type_reg           <= eth_type_next;
      ip_version_reg         <= ip_version_next;
      ip_ihl_reg             <= ip_ihl_next;
      ip_dscp_reg            <= ip_dscp_next;
      ip_ecn_reg             <= ip_ecn_next;
      ip_identification_reg  <= ip_identification_next;
      ip_flags_reg           <= ip_flags_next;
      ip_fragment_offset_reg <= ip_fragment_offset_next;
      ip_ttl_reg             <= ip_ttl_next;
      ip_protocol_reg        <= ip_protocol_next;
      ip_header_checksum_reg <= ip_header_checksum_next;
      ip_source_ip_reg       <= ip_source_ip_next;
      ip_dest_ip_reg         <= ip_dest_ip_next;
      udp_source_port_reg    <= udp_source_port_next;
      udp_dest_port_reg      <= udp_dest_port_next;
      udp_length_reg         <= udp_length_next;
      udp_checksum_reg       <= udp_checksum_next;
    end

  end

  assign m_roce_bth_valid     = roce_bth_valid_reg;
  assign m_roce_reth_valid    = roce_reth_valid_reg;
  assign m_roce_immdh_valid   = roce_immdh_valid_reg;

  assign m_eth_dest_mac       = eth_dest_mac_reg;
  assign m_eth_src_mac        = eth_src_mac_reg;
  assign m_eth_type           = eth_type_reg;
  assign m_ip_version         = ip_version_reg;
  assign m_ip_ihl             = ip_ihl_reg;
  assign m_ip_dscp            = ip_dscp_reg;
  assign m_ip_ecn             = ip_ecn_reg;
  assign m_ip_identification  = ip_identification_reg;
  assign m_ip_flags           = ip_flags_reg;
  assign m_ip_fragment_offset = ip_fragment_offset_reg;
  assign m_ip_ttl             = ip_ttl_reg;
  assign m_ip_protocol        = ip_protocol_reg;
  assign m_ip_header_checksum = ip_header_checksum_reg;
  assign m_ip_source_ip       = ip_source_ip_reg;
  assign m_ip_dest_ip         = ip_dest_ip_reg;

  assign m_udp_source_port    = udp_source_port_reg;
  assign m_udp_dest_port      = udp_dest_port_reg;
  assign m_udp_length         = udp_length_reg;
  assign m_udp_checksum       = udp_checksum_reg;

  always @(posedge clk) begin
    axis_tdata_reg <= s_axis_tdata;
    axis_tvalid_reg <= s_axis_tvalid;
    axis_tkeep_reg <= s_axis_tkeep;
    axis_tlast_reg <= s_axis_tlast;
    axis_tuser_reg <= s_axis_tuser;

    m_axis_tdata_reg <= axis_tdata_reg;
    m_axis_tvalid_reg <= axis_tvalid_reg;
    m_axis_tkeep_reg <= axis_tkeep_reg;
    m_axis_tlast_reg <= axis_tlast_reg | last_axi_frame;
    m_axis_tuser_reg <= axis_tuser_reg;
  end

  assign m_roce_payload_axis_tdata = m_axis_tdata_reg;
  assign m_roce_payload_axis_tvalid = m_axis_tvalid_reg;
  assign m_roce_payload_axis_tkeep = m_axis_tkeep_reg;
  assign m_roce_payload_axis_tlast = m_axis_tlast_reg;
  assign m_roce_payload_axis_tuser = m_axis_tuser_reg;

  assign s_axis_tready = m_roce_payload_axis_tready;


endmodule
