
`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_tx_header_producer #(
    parameter DATA_WIDTH = 64
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE DMA transfer parameters
     */
    input  wire       s_dma_meta_valid,
    output wire       s_dma_meta_ready,
    input wire [31:0] s_dma_length,
    input wire [23:0] s_rem_qpn,
    input wire [23:0] s_loc_qpn,
    input wire [23:0] s_rem_psn,
    input wire [31:0] s_r_key,
    input wire [31:0] s_rem_ip_addr,
    input wire [63:0] s_rem_addr,
    input wire        s_is_immediate,
    input wire        s_trasfer_type, // 0 SEND 1 RDMA_WRITE 

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
    output wire [              23:0] m_roce_bth_src_qp,
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
    output wire                      m_roce_payload_axis_tuser,
    // config
    input  wire [               2:0] pmtu,
    input  wire [              15:0] RoCE_udp_port,
    input  wire [              31:0] loc_ip_addr

);

    integer i;

    function [$clog2(DATA_WIDTH/8):0] keep2count;
        input [DATA_WIDTH/8 - 1:0] k;
        for (i = DATA_WIDTH/8 - 1; i >= 0; i = i - 1) begin
            if (i == DATA_WIDTH/8 - 1) begin
                if (k[DATA_WIDTH/8 -1]) keep2count = DATA_WIDTH/8;
            end else begin
                if (k[i +: 2] == 2'b01) keep2count = i+1;
                else if (k[i +: 2] == 2'b00) keep2count = 0;
            end
        end
    endfunction


    localparam [7:0]
    RC_SEND_FIRST         = 8'h00,
    RC_SEND_MIDDLE        = 8'h01,
    RC_SEND_LAST          = 8'h02,
    RC_SEND_LAST_IMD      = 8'h03,
    RC_SEND_ONLY          = 8'h04,
    RC_SEND_ONLY_IMD      = 8'h05,
    RC_RDMA_WRITE_FIRST   = 8'h06,
    RC_RDMA_WRITE_MIDDLE  = 8'h07,
    RC_RDMA_WRITE_LAST    = 8'h08,
    RC_RDMA_WRITE_LAST_IMD= 8'h09,
    RC_RDMA_WRITE_ONLY    = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
    RC_RDMA_ACK           = 8'h11;

    localparam [2:0]
    STATE_IDLE               = 3'd0,
    STATE_STORE_PAR          = 3'd1,
    STATE_FIRST              = 3'd2,
    STATE_MIDDLE             = 3'd3,
    STATE_LAST               = 3'd4,
    STATE_ONLY               = 3'd5,
    STATE_WRITE_PAYLOAD_LAST = 3'd6,
    STATE_ERROR              = 3'd7;

    reg [2:0] state_reg, state_next;

    //localparam [31:0] LOC_IP_ADDR = {8'd22, 8'd1, 8'd212, 8'd10};
    localparam [15:0] LOC_UDP_PORT = 16'h2123;
    //localparam [15:0] ROCE_UDP_PORT = 16'h12B7;

    reg s_dma_meta_ready_reg = 1'b0, s_dma_meta_ready_next;

    reg roce_bth_valid_next, roce_bth_valid_reg;
    reg roce_reth_valid_next, roce_reth_valid_reg;
    reg roce_immdh_valid_next, roce_immdh_valid_reg;

    reg [DATA_WIDTH   - 1:0] m_roce_payload_axis_tdata_int;
    reg [DATA_WIDTH/8 - 1:0] m_roce_payload_axis_tkeep_int;
    reg                      m_roce_payload_axis_tvalid_int;
    reg                      m_roce_payload_axis_tready_int;
    reg                      m_roce_payload_axis_tlast_int;
    reg                      m_roce_payload_axis_tuser_int;

    reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
    reg m_roce_reth_valid_reg = 1'b0, m_roce_reth_valid_next;
    reg m_roce_immdh_valid_reg = 1'b0, m_roce_immdh_valid_next;


    reg [7:0] roce_bth_op_code_next, roce_bth_op_code_reg;
    reg [15:0] roce_bth_p_key_next, roce_bth_p_key_reg;
    reg [23:0] roce_bth_psn_next, roce_bth_psn_reg;
    reg [23:0] roce_bth_dest_qp_next, roce_bth_dest_qp_reg;
    reg [23:0] roce_bth_src_qp_next, roce_bth_src_qp_reg;
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


    reg [170:0] qp_info;
    //assign qp_info[2:0]     = 3'b010;  //qp_state
    //assign qp_info[26:3]    = 24'h000016;  //loc_qpn
    //assign qp_info[50:27]   = 24'h543210;  //rem_psn
    //assign qp_info[74:51]   = 24'h012345;  //loc_psn
    //assign qp_info[106:52]  = 32'h11223344;  //r_key
    //assign qp_info[170:107] = 64'h000000000000;  //vaddr

    reg [154:0] qp_conn;
    //assign qp_conn[23:0]  = 24'h000017;  //loc_qpn
    //assign qp_conn[47:24] = 24'h000016;  //rem_qpn
    //assign qp_conn[79:48] = 32'h0BD40116;  //rem_ip_addr
    //assign qp_conn[95:80] = ROCE_UDP_PORT;  //rem_udp_port

    reg [ 95:0] tx_metadata;
    //assign tx_metadata[31:0]  = 32'd3200;  //dma_length
    //assign tx_metadata[95:32] = 64'h00001122334455;  //rem_addr

    reg is_immediate_reg;
    reg trasfer_type_reg;

    reg [31:0] remaining_length_next, remaining_length_reg;
    reg [13:0] packet_inst_length_next, packet_inst_length_reg; // MAX 16384
    reg [31:0] total_packet_inst_length_next, total_packet_inst_length_reg;

    reg [23:0] psn_next, psn_reg;

    reg  [               2:0] axis_valid_shreg;

    wire                      first_axi_frame;
    wire                      last_axi_frame;

    reg  [  DATA_WIDTH - 1:0] last_word_data_reg = {DATA_WIDTH{1'b0}};
    reg  [DATA_WIDTH/8 - 1:0] last_word_keep_reg = {DATA_WIDTH / 8{1'b0}};


    // internal datapath
    reg  [  DATA_WIDTH - 1:0] m_axis_tdata_int;
    reg  [DATA_WIDTH/8 - 1:0] m_axis_tkeep_int;
    reg                       m_axis_tvalid_int;
    reg                       m_axis_tready_int_reg = 1'b0;
    reg                       m_axis_tlast_int;
    reg                       m_axis_tuser_int;
    wire                      m_axis_tready_int_early;

    reg                       s_axis_tready_next;
    reg                       s_axis_tready_reg;

    reg [12:0] pmtu_val;

    // datapath control signals
    reg store_last_word;
    reg store_parameters;

    assign s_dma_meta_ready   = s_dma_meta_ready_reg;
    assign s_axis_tready      = s_axis_tready_reg;

    always @(posedge clk) begin
        pmtu_val     <= 13'd1 << ( pmtu + 13'd8);
    end

    always @* begin

        state_next                    = STATE_IDLE;

        s_axis_tready_next            = 1'b0;

        store_parameters              = 1'b0;

        store_last_word               = 1'b0;

        roce_bth_valid_next           = roce_bth_valid_reg && !m_roce_bth_ready;
        roce_reth_valid_next          = roce_reth_valid_reg && !m_roce_reth_ready;
        roce_immdh_valid_next         = roce_immdh_valid_reg && !m_roce_immdh_ready;

        remaining_length_next         = remaining_length_reg;
        packet_inst_length_next       = packet_inst_length_reg;
        total_packet_inst_length_next = total_packet_inst_length_reg;

        psn_next                      = psn_reg;

        eth_dest_mac_next             = eth_dest_mac_reg;
        eth_src_mac_next              = eth_src_mac_reg;
        eth_type_next                 = eth_type_reg;

        ip_version_next               = ip_version_reg;
        ip_ihl_next                   = ip_ihl_reg;
        ip_dscp_next                  = ip_dscp_reg;
        ip_ecn_next                   = ip_ecn_reg;
        ip_identification_next        = ip_identification_reg;
        ip_flags_next                 = ip_flags_reg;
        ip_fragment_offset_next       = ip_fragment_offset_reg;
        ip_ttl_next                   = ip_ttl_reg;
        ip_protocol_next              = ip_protocol_reg;
        ip_header_checksum_next       = ip_header_checksum_reg;
        ip_source_ip_next             = ip_source_ip_reg;
        ip_dest_ip_next               = ip_dest_ip_reg;

        udp_source_port_next          = udp_source_port_reg;
        udp_dest_port_next            = udp_dest_port_reg;
        udp_length_next               = udp_length_reg;
        udp_checksum_next             = udp_checksum_reg;

        roce_bth_op_code_next         = roce_bth_op_code_reg;
        roce_bth_p_key_next           = roce_bth_p_key_reg;
        roce_bth_psn_next             = roce_bth_psn_reg;
        roce_bth_dest_qp_next         = roce_bth_dest_qp_reg;
        roce_bth_src_qp_next          = roce_bth_src_qp_reg;
        roce_bth_ack_req_next         = roce_bth_ack_req_reg;
        roce_reth_v_addr_next         = roce_reth_v_addr_reg;
        roce_reth_r_key_next          = roce_reth_r_key_reg;
        roce_reth_length_next         = roce_reth_length_reg;
        roce_immdh_data_next          = roce_immdh_data_reg;

        s_dma_meta_ready_next         = 1'b0;

        m_axis_tdata_int              = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_int              = {DATA_WIDTH / 8{1'b0}};
        m_axis_tvalid_int             = 1'b0;
        m_axis_tlast_int              = 1'b0;
        m_axis_tuser_int              = 1'b0;


        case (state_reg)
            STATE_IDLE: begin
                //s_dma_meta_ready_next               = !roce_bth_valid_next;
                s_dma_meta_ready_next               = 1'b1;
                if (s_dma_meta_ready && s_dma_meta_valid) begin
                    store_parameters = 1'b1;
                    s_dma_meta_ready_next = 1'b0;
                    s_axis_tready_next = m_axis_tready_int_early;
                    state_next       = STATE_STORE_PAR;
                end
            end
            STATE_STORE_PAR: begin

                udp_dest_port_next = udp_dest_port_reg;

                s_axis_tready_next = m_axis_tready_int_early;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu_val | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tready && s_axis_tvalid) begin
                    remaining_length_next = tx_metadata[31:0] - DATA_WIDTH / 8;
                    packet_inst_length_next = DATA_WIDTH / 8;
                    total_packet_inst_length_next = DATA_WIDTH / 8;
                end else begin
                    remaining_length_next = tx_metadata[31:0];
                    packet_inst_length_next = 14'b0;
                    total_packet_inst_length_next = 32'd0;
                end

                if (tx_metadata[31:0] <= pmtu_val) begin
                    state_next            = STATE_ONLY;
                    s_dma_meta_ready_next = 1'b0;
                    roce_bth_valid_next   = 1'b1;
                    roce_reth_valid_next  = trasfer_type_reg;
                    roce_immdh_valid_next = is_immediate_reg;
                    // TODO add option for immediate 

                    ip_source_ip_next     = loc_ip_addr;
                    ip_dest_ip_next       = qp_conn[79:48];

                    udp_source_port_next  = LOC_UDP_PORT;
                    udp_dest_port_next    = RoCE_udp_port;
                    if (is_immediate_reg) begin
                        if (trasfer_type_reg) begin // RDMA_WRITE, need to add RETH
                            udp_length_next = tx_metadata[31:0] + 12 + 16 + 4 + 8;
                        end else begin
                            udp_length_next = tx_metadata[31:0] + 12 + 4 + 8;
                        end
                        // dma length (less than PMTU) + BTH + RETH + + IMMDH UDP HEADER 
                    end else begin
                        if (trasfer_type_reg) begin // RDMA_WRITE, need to add RETH
                            udp_length_next = tx_metadata[31:0] + 12 + 16 + 8;
                        end else begin
                            udp_length_next = tx_metadata[31:0] + 12 + 8;
                        end
                        // dma length (less than PMTU) + BTH + RETH + UDP HEADER 
                    end

                    if (trasfer_type_reg) begin
                        roce_bth_op_code_next = is_immediate_reg ? RC_RDMA_WRITE_ONLY_IMD : RC_RDMA_WRITE_ONLY;
                    end else begin
                        roce_bth_op_code_next = is_immediate_reg ? RC_SEND_ONLY_IMD : RC_SEND_ONLY;
                    end
                    roce_bth_p_key_next   = 16'hFFFF;
                    roce_bth_psn_next     = qp_info[74:51];
                    roce_bth_dest_qp_next = qp_conn[47:24];
                    roce_bth_ack_req_next = 1'b1;
                    roce_reth_v_addr_next = tx_metadata[95:32];
                    roce_reth_r_key_next  = qp_info[106:75];
                    roce_reth_length_next = tx_metadata[31:0];
                    roce_immdh_data_next  = 32'hDEADBEEF; //TODO change this

                    psn_next              = qp_info[74:51];
                end else begin
                    state_next            = STATE_FIRST;
                    s_dma_meta_ready_next = 1'b0;
                    roce_bth_valid_next   = 1'b1;
                    roce_reth_valid_next  = trasfer_type_reg;
                    roce_immdh_valid_next = 1'b0;

                    ip_source_ip_next     = loc_ip_addr;
                    ip_dest_ip_next       = qp_conn[79:48];

                    udp_source_port_next  = LOC_UDP_PORT;
                    udp_dest_port_next    = RoCE_udp_port;
                    if (trasfer_type_reg) begin
                        udp_length_next       = pmtu_val + 12 + 16 + 8;
                    end else begin
                        udp_length_next       = pmtu_val + 12 + 8; // for SEND  
                    end
                    // PMTU + BTH + RETH + UDP HEADER

                    roce_bth_op_code_next = trasfer_type_reg ? RC_RDMA_WRITE_FIRST : RC_SEND_FIRST;
                    roce_bth_p_key_next   = 16'hFFFF;
                    roce_bth_psn_next     = qp_info[74:51];
                    roce_bth_dest_qp_next = qp_conn[47:24];
                    roce_bth_ack_req_next = 1'b1;
                    roce_reth_v_addr_next = tx_metadata[95:32];
                    roce_reth_r_key_next  = qp_info[106:75];
                    roce_reth_length_next = tx_metadata[31:0];
                    roce_immdh_data_next  = 32'hDEADBEEF;

                    psn_next              = qp_info[74:51];
                end

            end
            STATE_FIRST: begin

                state_next = state_reg;


                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu_val | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tuser) begin
                    s_axis_tready_next    = 1'b0;
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    s_axis_tready_next = m_axis_tready_int_early;

                    if (s_axis_tready && s_axis_tvalid) begin
                        remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                        packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                        total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                        //if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
                        if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8 <= pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            state_next = STATE_LAST;
                            roce_bth_valid_next = 1'b1;
                            roce_reth_valid_next = 1'b0;
                            roce_immdh_valid_next = s_is_immediate;

                            if (roce_bth_valid_next) begin
                                if (s_is_immediate) begin
                                    udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8 + 4; // no reth
                                    // remaining length + BTH + UDP HEADER
                                end else begin
                                    udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8; // no reth
                                    // remaining length + BTH + UDP HEADER
                                end
                            end
                            if (trasfer_type_reg) begin
                                roce_bth_op_code_next = s_is_immediate ? RC_RDMA_WRITE_LAST_IMD : RC_RDMA_WRITE_LAST;
                            end else begin
                                roce_bth_op_code_next = s_is_immediate ? RC_SEND_LAST_IMD : RC_SEND_LAST;
                            end
                            roce_bth_psn_next     = psn_reg + 1;
                            roce_bth_ack_req_next = 1'b1;

                            psn_next              = psn_reg + 1;

                            //end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
                        end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8 > pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            state_next              = STATE_MIDDLE;
                            roce_bth_valid_next     = 1'b1;
                            roce_reth_valid_next    = 1'b0;
                            roce_immdh_valid_next   = 1'b0;

                            udp_length_next         = pmtu_val + 12 + 8; //no RETH
                            // PMTU + BTH + UDP HEADER

                            roce_bth_op_code_next   = trasfer_type_reg ? RC_RDMA_WRITE_MIDDLE : RC_SEND_MIDDLE;
                            roce_bth_psn_next       = psn_reg + 1;
                            roce_bth_ack_req_next   = 1'b1;

                            psn_next                = psn_reg + 1;
                        end
                    end
                end
            end
            STATE_MIDDLE: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu_val | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tuser) begin
                    s_axis_tready_next    = 1'b0;
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    s_axis_tready_next = m_axis_tready_int_early;


                    if (s_axis_tready && s_axis_tvalid) begin
                        remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                        packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                        total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                        //if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 <= PMTU) begin
                        if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8 <= pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            state_next = STATE_LAST;
                            roce_bth_valid_next = 1'b1;
                            roce_reth_valid_next = 1'b0;
                            roce_immdh_valid_next = s_is_immediate;

                            if (roce_bth_valid_next) begin
                                if (s_is_immediate) begin
                                    udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8 + 4; // no reth
                                    // remaining length + BTH + UDP HEADER
                                end else begin
                                    udp_length_next = remaining_length_reg - DATA_WIDTH / 8 + 12 + 8; // no reth
                                    // remaining length + BTH + UDP HEADER
                                end
                            end
                            if (trasfer_type_reg) begin
                                roce_bth_op_code_next = is_immediate_reg ? RC_RDMA_WRITE_LAST_IMD : RC_RDMA_WRITE_LAST;
                            end else begin
                                roce_bth_op_code_next = is_immediate_reg ? RC_SEND_LAST_IMD : RC_SEND_LAST;
                            end
                            roce_bth_psn_next     = psn_reg + 1;
                            roce_bth_ack_req_next = 1'b1;

                            psn_next              = psn_reg + 1;

                            //end else if (packet_inst_length + DATA_WIDTH / 8 >= PMTU && remaining_length - DATA_WIDTH / 8 > PMTU) begin
                        end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8 > pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            state_next              = STATE_MIDDLE;
                            roce_bth_valid_next     = 1'b1;
                            roce_reth_valid_next    = 1'b0;
                            roce_immdh_valid_next   = 1'b0;

                            udp_length_next         = pmtu_val + 12 + 8; //no RETH
                            // PMTU + BTH + UDP HEADER

                            roce_bth_op_code_next   = trasfer_type_reg ? RC_RDMA_WRITE_MIDDLE : RC_SEND_MIDDLE;
                            roce_bth_psn_next       = psn_reg + 1;
                            roce_bth_ack_req_next   = 1'b1;

                            psn_next                = psn_reg + 1;
                        end
                    end
                end
            end
            STATE_LAST: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu_val | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tuser) begin
                    s_axis_tready_next    = 1'b0;
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    s_axis_tready_next = m_axis_tready_int_early;

                    store_last_word = 1'b1;

                    if (s_axis_tready && s_axis_tvalid) begin

                        if (remaining_length_reg <= DATA_WIDTH / 8) begin
                            // have entire payload
                            if (s_axis_tlast) begin
                                if (keep2count(s_axis_tkeep) < remaining_length_reg) begin
                                    // end of frame, but length does not match
                                    m_axis_tuser_int = 1'b1;
                                end
                                s_axis_tready_next    = 1'b0;
                                s_dma_meta_ready_next = !roce_bth_valid_next;
                                state_next = STATE_IDLE;
                            end else begin
                                m_axis_tvalid_int = 1'b0;
                                state_next = STATE_WRITE_PAYLOAD_LAST;
                            end
                        end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8> pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            total_packet_inst_length_next = 32'd0;
                            state_next = STATE_ERROR;
                        end else begin
                            if (s_axis_tlast) begin
                                // end of frame, but length does not match
                                s_dma_meta_ready_next = !roce_bth_valid_next;
                                m_axis_tuser_int = 1'b1;
                                s_axis_tready_next = 1'b0;
                                state_next = STATE_IDLE;
                            end
                        end

                        remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                        packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                        total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                        //if (remaining_length - DATA_WIDTH / 8 == 0) begin

                    end
                end
            end
            STATE_ONLY: begin

                state_next = state_reg;

                m_axis_tdata_int  = s_axis_tdata;
                m_axis_tkeep_int  = s_axis_tkeep;
                m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tlast_int  = packet_inst_length_reg + DATA_WIDTH / 8 == pmtu_val | s_axis_tlast;
                m_axis_tuser_int  = s_axis_tuser;

                if (s_axis_tuser) begin
                    s_axis_tready_next    = 1'b0;
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    s_axis_tready_next = m_axis_tready_int_early;

                    store_last_word = 1'b1;

                    if (s_axis_tready && s_axis_tvalid) begin

                        if (remaining_length_reg <= DATA_WIDTH / 8) begin
                            // have entire payload
                            if (s_axis_tlast) begin
                                if (keep2count(s_axis_tkeep) < remaining_length_reg[7:0]) begin
                                    // end of frame, but length does not match
                                    m_axis_tuser_int = 1'b1;
                                end
                                s_dma_meta_ready_next = !roce_bth_valid_next;
                                s_axis_tready_next    = 1'b0;
                                state_next = STATE_IDLE;
                            end else begin
                                m_axis_tvalid_int = 1'b0;
                                state_next = STATE_WRITE_PAYLOAD_LAST;
                            end
                        end else if (packet_inst_length_reg + DATA_WIDTH / 8 >= pmtu_val && remaining_length_reg - DATA_WIDTH / 8 > pmtu_val) begin
                            packet_inst_length_next = 14'd0;
                            total_packet_inst_length_next = 32'd0;
                            state_next = STATE_ERROR;
                        end else begin
                            if (s_axis_tlast) begin
                                // end of frame, but length does not match
                                s_dma_meta_ready_next = !roce_bth_valid_next;
                                m_axis_tuser_int      = 1'b1;
                                s_axis_tready_next    = 1'b0;
                                state_next = STATE_IDLE;
                            end
                        end

                        remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                        packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                        total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                        //if (remaining_length - DATA_WIDTH / 8 == 0) begin

                    end
                end
            end

            STATE_WRITE_PAYLOAD_LAST: begin
                state_next = state_reg;

                m_axis_tdata_int = last_word_data_reg;
                m_axis_tkeep_int = last_word_keep_reg;
                m_axis_tlast_int = s_axis_tlast;
                m_axis_tuser_int = s_axis_tuser;

                if (s_axis_tuser) begin
                    s_axis_tready_next    = 1'b0;
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end else begin
                    s_axis_tready_next = m_axis_tready_int_early;

                    if (s_axis_tready && s_axis_tvalid) begin
                        if (s_axis_tlast) begin
                            s_dma_meta_ready_next = !roce_bth_valid_next;
                            s_axis_tready_next = 1'b0;
                            m_axis_tvalid_int = 1'b1;
                            packet_inst_length_next = 14'd0;
                            total_packet_inst_length_next = 32'd0;
                            state_next = STATE_IDLE;
                        end else begin
                            remaining_length_next = remaining_length_reg - DATA_WIDTH / 8;
                            packet_inst_length_next = packet_inst_length_reg + DATA_WIDTH / 8;
                            total_packet_inst_length_next = total_packet_inst_length_reg + DATA_WIDTH / 8;
                            state_next = STATE_WRITE_PAYLOAD_LAST;
                        end
                    end else begin
                        remaining_length_next = remaining_length_reg;
                        packet_inst_length_next = packet_inst_length_reg;
                        total_packet_inst_length_next = total_packet_inst_length_reg;
                        state_next = STATE_WRITE_PAYLOAD_LAST;
                    end
                end
            end
            STATE_ERROR: begin
                state_next = state_reg;
                m_axis_tdata_int = {DATA_WIDTH{1'b0}};
                m_axis_tkeep_int = {DATA_WIDTH / 8{1'b0}};
                m_axis_tvalid_int = 1'b0;
                m_axis_tlast_int = 1'b0;
                s_axis_tready_next = 1'b0;
                if (rst) begin
                    s_dma_meta_ready_next = !roce_bth_valid_next;
                    state_next = STATE_IDLE;
                end
            end
        endcase
    end

    assign first_axi_frame = 1'b0;
    assign last_axi_frame  = 1'b0;

    always @(posedge clk) begin

        if (rst) begin
            state_reg   <= STATE_IDLE;
            qp_info     <= 171'h0;
            qp_conn     <= 155'h0;
            tx_metadata <= 80'h0;

            remaining_length_reg         <= {32{1'b1}};
            packet_inst_length_reg       <= 14'd0;
            total_packet_inst_length_reg <= 32'd0;

            psn_reg                      <= 24'd0;

            eth_dest_mac_reg             <= 48'h0;
            eth_src_mac_reg              <= 48'h0;
            eth_type_reg                 <= 16'h0;
            ip_version_reg               <= 4'd4;
            ip_ihl_reg                   <= 4'd0;
            ip_dscp_reg                  <= 6'h0;
            ip_ecn_reg                   <= 2'h0;
            ip_identification_reg        <= 16'h0;
            ip_flags_reg                 <= 3'b001;
            ip_fragment_offset_reg       <= 13'h0;
            ip_ttl_reg                   <= 8'h40;
            ip_protocol_reg              <= 8'h11;
            ip_header_checksum_reg       <= 16'd0;
            ip_source_ip_reg             <= 32'h0;
            ip_dest_ip_reg               <= 32'h0;
            udp_source_port_reg          <= 16'd0;
            udp_dest_port_reg            <= RoCE_udp_port;
            udp_length_reg               <= 16'h0;
            udp_checksum_reg             <= 16'h0;
            roce_bth_op_code_reg         <= RC_RDMA_WRITE_ONLY;
            roce_bth_p_key_reg           <= 16'd0;
            roce_bth_psn_reg             <= 24'd0;
            roce_bth_dest_qp_reg         <= 24'd0;
            roce_bth_src_qp_reg          <= 24'd0;
            roce_bth_ack_req_reg         <= 1'b0;
            roce_reth_v_addr_reg         <= 48'd0;
            roce_reth_r_key_reg          <= 32'd0;
            roce_reth_length_reg         <= 16'h0;
            roce_immdh_data_reg          <= 32'h0;

        end else begin
            state_reg <= state_next;

            s_axis_tready_reg <= s_axis_tready_next;

            m_roce_bth_valid_reg <= m_roce_bth_valid_next;
            m_roce_reth_valid_reg <= m_roce_reth_valid_next;
            m_roce_immdh_valid_reg <= m_roce_immdh_valid_next;

            s_dma_meta_ready_reg <= s_dma_meta_ready_next;

            remaining_length_reg <= remaining_length_next;
            packet_inst_length_reg <= packet_inst_length_next;
            total_packet_inst_length_reg <= total_packet_inst_length_next;

            psn_reg <= psn_next;

            if (store_parameters) begin
                qp_info <= {{64{1'b0}}, s_r_key, s_rem_psn, s_rem_qpn, 24'h000016, 3'b010};
                //assign qp_info[2:0]     = 3'b010;  //qp_state
                //assign qp_info[26:3]    = 24'h000016;  //loc_qpn
                //assign qp_info[50:27]   = 24'h543210;  //rem_psn
                //assign qp_info[74:51]   = 24'h012345;  //loc_psn
                //assign qp_info[106:75]  = 32'h11223344;  //r_key
                //assign qp_info[170:107] = 64'h000000000000;  //vaddr

                qp_conn <= {RoCE_udp_port, s_rem_ip_addr, s_rem_qpn, 24'h000017};
                //assign qp_conn[23:0]  = 24'h000017;  //loc_qpn
                //assign qp_conn[47:24] = 24'h000016;  //rem_qpn
                //assign qp_conn[79:48] = 32'h0BD40116;  //rem_ip_addr
                //assign qp_conn[95:80] = ROCE_UDP_PORT;  //rem_udp_port

                tx_metadata <= {s_rem_addr, s_dma_length};
                //assign tx_metadata[31:0]  = 32'd3200;  //dma_length
                //assign tx_metadata[79:32] = 64'h001122334455;  //rem_addr

                is_immediate_reg <= s_is_immediate;
                trasfer_type_reg <= s_trasfer_type;
            end


            roce_bth_valid_reg   <= roce_bth_valid_next;
            roce_reth_valid_reg  <= roce_reth_valid_next;
            roce_immdh_valid_reg <= roce_immdh_valid_next;

            roce_bth_op_code_reg <= roce_bth_op_code_next;
            roce_bth_p_key_reg   <= roce_bth_p_key_next;
            roce_bth_psn_reg     <= roce_bth_psn_next;
            roce_bth_dest_qp_reg <= roce_bth_dest_qp_next;
            roce_bth_src_qp_reg  <= roce_bth_src_qp_next;
            roce_bth_ack_req_reg <= roce_bth_ack_req_next;

            roce_reth_v_addr_reg <= roce_reth_v_addr_next;
            roce_reth_r_key_reg  <= roce_reth_r_key_next;
            roce_reth_length_reg <= roce_reth_length_next;

            roce_immdh_data_reg  <= roce_immdh_data_next;

            ip_source_ip_reg     <= ip_source_ip_next;
            ip_dest_ip_reg       <= ip_dest_ip_next;
            udp_source_port_reg  <= udp_source_port_next;
            udp_dest_port_reg    <= udp_dest_port_next;
            udp_length_reg       <= udp_length_next;


        end

        if (store_last_word) begin
            last_word_data_reg <= m_axis_tdata_int;
            last_word_keep_reg <= m_axis_tkeep_int;
        end

    end

    assign s_dma_meta_ready = s_dma_meta_ready_reg;

    assign m_roce_bth_valid     = roce_bth_valid_reg;
    assign m_roce_reth_valid    = roce_reth_valid_reg;
    assign m_roce_immdh_valid   = roce_immdh_valid_reg;

    assign m_roce_bth_op_code   = roce_bth_op_code_reg;
    assign m_roce_bth_p_key     = roce_bth_p_key_reg;
    assign m_roce_bth_psn       = roce_bth_psn_reg;
    assign m_roce_bth_dest_qp   = roce_bth_dest_qp_reg;
    assign m_roce_bth_src_qp    = roce_bth_src_qp_reg;
    assign m_roce_bth_ack_req   = roce_bth_ack_req_reg;

    assign m_roce_reth_v_addr   = roce_reth_v_addr_reg;
    assign m_roce_reth_r_key    = roce_reth_r_key_reg;
    assign m_roce_reth_length   = roce_reth_length_reg;

    assign m_roce_immdh_data    = roce_immdh_data_reg;

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


    // output datapath logic
    reg [   DATA_WIDTH - 1:0] m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] m_axis_tkeep_reg = 8'd0;
    reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                       m_axis_tlast_reg = 1'b0;
    reg                       m_axis_tuser_reg = 1'b0;

    reg [   DATA_WIDTH - 1:0] m_axis_not_masked_tdata_reg = 64'd0;

    reg [   DATA_WIDTH - 1:0] temp_m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] temp_m_axis_tkeep_reg = 8'd0;
    reg temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg temp_m_axis_tlast_reg = 1'b0;
    reg temp_m_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    assign m_roce_payload_axis_tdata = m_axis_tdata_reg;
    assign m_roce_payload_axis_tkeep = m_axis_tkeep_reg;
    assign m_roce_payload_axis_tvalid = m_axis_tvalid_reg;
    assign m_roce_payload_axis_tlast = m_axis_tlast_reg;
    assign m_roce_payload_axis_tuser = m_axis_tuser_reg;


    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);
    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    //assign m_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_int_to_output = 1'b0;
        store_axis_int_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_tready_int_reg) begin
            // input is ready
            if (m_roce_payload_axis_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_temp  = 1'b1;
            end
        end else if (m_roce_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        m_axis_tready_int_reg <= m_axis_tready_int_early;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= m_axis_tdata_int;
            m_axis_tkeep_reg <= m_axis_tkeep_int;
            m_axis_tlast_reg <= m_axis_tlast_int;
            m_axis_tuser_reg <= m_axis_tuser_int;


        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
            m_axis_tuser_reg <= temp_m_axis_tuser_reg;

        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= m_axis_tdata_int;
            temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
            temp_m_axis_tlast_reg <= m_axis_tlast_int;
            temp_m_axis_tuser_reg <= m_axis_tuser_int;

        end

        if (rst) begin
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tready_int_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end



endmodule