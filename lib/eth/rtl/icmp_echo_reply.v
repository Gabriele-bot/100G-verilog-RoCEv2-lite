
`resetall `timescale 1ns / 1ps `default_nettype none

module icmp_echo_reply #(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH > 8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH / 8),
    // Checksum parameters
    parameter CHECKSUM_PAYLOAD_FIFO_DEPTH = 256,
    parameter CHECKSUM_HEADER_FIFO_DEPTH = 8,
    // Compute IP header checksum; if 0, sends 16'h0000
    parameter COMPUTE_IP_HDR_CHECKSUM = 1,
    parameter IP_HDR_CHECKSUM_PIPELINED = 0
) (
    input wire clk,
    input wire rst,

    /*
     * IP frame input
     */
    input  wire                  s_ip_hdr_valid,
    output wire                  s_ip_hdr_ready,
    input  wire [          47:0] s_eth_dest_mac,
    input  wire [          47:0] s_eth_src_mac,
    input  wire [          15:0] s_eth_type,
    input  wire [           3:0] s_ip_version,
    input  wire [           3:0] s_ip_ihl,
    input  wire [           5:0] s_ip_dscp,
    input  wire [           1:0] s_ip_ecn,
    input  wire [          15:0] s_ip_length,
    input  wire [          15:0] s_ip_identification,
    input  wire [           2:0] s_ip_flags,
    input  wire [          12:0] s_ip_fragment_offset,
    input  wire [           7:0] s_ip_ttl,
    input  wire [           7:0] s_ip_protocol,
    input  wire [          15:0] s_ip_header_checksum,
    input  wire [          31:0] s_ip_source_ip,
    input  wire [          31:0] s_ip_dest_ip,
    input  wire [DATA_WIDTH-1:0] s_ip_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_ip_payload_axis_tkeep,
    input  wire                  s_ip_payload_axis_tvalid,
    output wire                  s_ip_payload_axis_tready,
    input  wire                  s_ip_payload_axis_tlast,
    input  wire                  s_ip_payload_axis_tuser,

    /*
     * IP frame output
     */
    output wire                  m_ip_hdr_valid,
    input  wire                  m_ip_hdr_ready,
    output wire [          47:0] m_eth_dest_mac,
    output wire [          47:0] m_eth_src_mac,
    output wire [          15:0] m_eth_type,
    output wire [           3:0] m_ip_version,
    output wire [           3:0] m_ip_ihl,
    output wire [           5:0] m_ip_dscp,
    output wire [           1:0] m_ip_ecn,
    output wire [          15:0] m_ip_length,
    output wire [          15:0] m_ip_identification,
    output wire [           2:0] m_ip_flags,
    output wire [          12:0] m_ip_fragment_offset,
    output wire [           7:0] m_ip_ttl,
    output wire [           7:0] m_ip_protocol,
    output wire [          15:0] m_ip_header_checksum,
    output wire [          31:0] m_ip_source_ip,
    output wire [          31:0] m_ip_dest_ip,
    output wire                  m_is_roce_packet,
    output wire [DATA_WIDTH-1:0] m_ip_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep,
    output wire                  m_ip_payload_axis_tvalid,
    input  wire                  m_ip_payload_axis_tready,
    output wire                  m_ip_payload_axis_tlast,
    output wire                  m_ip_payload_axis_tuser,


    /*
     * Status
     */
    output wire rx_busy,
    output wire tx_busy,
    output wire rx_error_header_early_termination,
    output wire rx_error_payload_early_termination,
    output wire rx_error_invalid_header,
    output wire rx_error_invalid_checksum,
    output wire tx_error_payload_early_termination,
    output wire tx_error_arp_failed,

    /*
     * Configuration
     */
    input wire [31:0] local_ip
);

    function integer max;
        input integer a, b;
        begin
            if (a > b) max = a;
            else max = b;
        end
    endfunction

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    // bus width assertions
    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end

    localparam [1:0] STATE_IDLE = 2'd0,  STATE_COMPUTE_CHECKSUM = 2'd1, STATE_WAIT_PACKET = 2'd2;

    reg [1:0] state_reg = STATE_IDLE, state_next;

    // ICMP frame connections
    wire                  rx_icmp_hdr_valid;
    wire                  rx_icmp_hdr_ready;
    wire [          47:0] rx_icmp_eth_dest_mac;
    wire [          47:0] rx_icmp_eth_src_mac;
    wire [          15:0] rx_icmp_eth_type;
    wire [           3:0] rx_icmp_ip_version;
    wire [           3:0] rx_icmp_ip_ihl;
    wire [           5:0] rx_icmp_ip_dscp;
    wire [           1:0] rx_icmp_ip_ecn;
    wire [          15:0] rx_icmp_ip_length;
    wire [          15:0] rx_icmp_ip_identification;
    wire [           2:0] rx_icmp_ip_flags;
    wire [          12:0] rx_icmp_ip_fragment_offset;
    wire [           7:0] rx_icmp_ip_ttl;
    wire [           7:0] rx_icmp_ip_protocol;
    wire [          15:0] rx_icmp_ip_header_checksum;
    wire [          31:0] rx_icmp_ip_source_ip;
    wire [          31:0] rx_icmp_ip_dest_ip;
    wire [           7:0] rx_icmp_type;
    wire [           7:0] rx_icmp_code;
    wire [          15:0] rx_icmp_checksum;
    wire [          31:0] rx_icmp_roh;
    wire [DATA_WIDTH-1:0] rx_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] rx_icmp_payload_axis_tkeep;
    wire                  rx_icmp_payload_axis_tvalid;
    wire                  rx_icmp_payload_axis_tready;
    wire                  rx_icmp_payload_axis_tlast;
    wire                  rx_icmp_payload_axis_tuser;

    wire                  tx_icmp_hdr_valid;
    wire                  tx_icmp_hdr_ready;
    wire [          47:0] tx_icmp_eth_dest_mac;
    wire [          47:0] tx_icmp_eth_src_mac;
    wire [          15:0] tx_icmp_eth_type;
    wire [           5:0] tx_icmp_ip_dscp;
    wire [           1:0] tx_icmp_ip_ecn;
    wire [          15:0] tx_icmp_ip_length;
    wire [          15:0] tx_icmp_ip_identification;
    wire [           2:0] tx_icmp_ip_flags;
    wire [          12:0] tx_icmp_ip_fragment_offset;
    wire [           7:0] tx_icmp_ip_ttl;
    wire [          31:0] tx_icmp_ip_source_ip;
    wire [          31:0] tx_icmp_ip_dest_ip;
    wire [           7:0] tx_icmp_type;
    wire [           7:0] tx_icmp_code;
    wire [          15:0] tx_icmp_checksum;
    wire [          31:0] tx_icmp_roh;
    wire [DATA_WIDTH-1:0] tx_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] tx_icmp_payload_axis_tkeep;
    wire                  tx_icmp_payload_axis_tvalid;
    wire                  tx_icmp_payload_axis_tready;
    wire                  tx_icmp_payload_axis_tlast;
    wire                  tx_icmp_payload_axis_tuser;

    wire                  tx_post_checksum_icmp_hdr_valid;
    wire                  tx_post_checksum_icmp_hdr_ready;
    wire [47          :0] tx_post_checksum_icmp_eth_dest_mac;
    wire [47          :0] tx_post_checksum_icmp_eth_src_mac;
    wire [15          :0] tx_post_checksum_icmp_eth_type;
    wire [           5:0] tx_post_checksum_icmp_ip_dscp;
    wire [           1:0] tx_post_checksum_icmp_ip_ecn;
    wire [          15:0] tx_post_checksum_icmp_ip_length;
    wire [          15:0] tx_post_checksum_icmp_ip_identification;
    wire [           2:0] tx_post_checksum_icmp_ip_flags;
    wire [          12:0] tx_post_checksum_icmp_ip_fragment_offset;
    wire [           7:0] tx_post_checksum_icmp_ip_ttl;
    wire [          31:0] tx_post_checksum_icmp_ip_source_ip;
    wire [          31:0] tx_post_checksum_icmp_ip_dest_ip;
    wire [           7:0] tx_post_checksum_icmp_type;
    wire [           7:0] tx_post_checksum_icmp_code;
    wire [          15:0] tx_post_checksum_icmp_checksum;
    wire [          31:0] tx_post_checksum_icmp_roh;
    wire [DATA_WIDTH-1:0] tx_post_checksum_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] tx_post_checksum_icmp_payload_axis_tkeep;
    wire                  tx_post_checksum_icmp_payload_axis_tvalid;
    wire                  tx_post_checksum_icmp_payload_axis_tready;
    wire                  tx_post_checksum_icmp_payload_axis_tlast;
    wire                  tx_post_checksum_icmp_payload_axis_tuser;

    reg [47:0] outgoing_eth_dest_mac_reg, outgoing_eth_dest_mac_next;
    reg [47:0] outgoing_eth_src_mac_reg, outgoing_eth_src_mac_next;
    reg [15:0] outgoing_ip_length_reg, outgoing_ip_length_next;
    reg [31:0] outgoing_ip_source_ip_reg, outgoing_ip_source_ip_next;
    reg [31:0] outgoing_ip_dest_ip_reg, outgoing_ip_dest_ip_next;
    //icmp fields
    reg [ 7:0] outgoing_icmp_type_reg, outgoing_icmp_type_next;
    reg [ 7:0] outgoing_icmp_code_reg, outgoing_icmp_code_next;
    reg [15:0] outgoing_icmp_checksum_reg, outgoing_icmp_checksum_next;
    reg [31:0] outgoing_icmp_roh_reg, outgoing_icmp_roh_next;


    reg tx_post_checksum_icmp_hdr_ready_reg, tx_post_checksum_icmp_hdr_ready_next;

    reg outgoing_ip_hdr_valid_reg = 1'b0, outgoing_ip_hdr_valid_next;
    wire outgoing_ip_hdr_ready;
    wire outgoing_ip_payload_axis_tready;

    reg [19:0] hdr_sum_temp_reg = 20'd0, hdr_sum_temp_next;
    reg [19:0] hdr_sum_reg = 20'd0, hdr_sum_next;

    // ICMP Echo Reply when ICMP Echo Request and dest IP equal local IP
    wire match_cond = (rx_icmp_type == 8'h08) & (rx_icmp_code == 8'h00) & (rx_icmp_ip_dest_ip == local_ip);
    wire no_match = !match_cond;

    reg match_cond_reg = 0;
    reg no_match_reg = 0;

    always @(posedge clk) begin
        if (rst) begin
            match_cond_reg <= 0;
            no_match_reg   <= 0;
        end else begin
            if (rx_icmp_payload_axis_tvalid) begin
                if ((!match_cond_reg && !no_match_reg) ||
                (rx_icmp_payload_axis_tvalid && rx_icmp_payload_axis_tready && rx_icmp_payload_axis_tlast)) begin
                    match_cond_reg <= match_cond;
                    no_match_reg   <= no_match;
                end
            end else begin
                match_cond_reg <= 0;
                no_match_reg   <= 0;
            end
        end
    end

    assign tx_icmp_hdr_valid = rx_icmp_hdr_valid && match_cond;
    assign rx_icmp_hdr_ready = (tx_icmp_hdr_ready && match_cond) || no_match;
    // swap mac addresses
    assign tx_icmp_eth_dest_mac = rx_icmp_eth_src_mac;
    assign tx_icmp_eth_src_mac  = rx_icmp_eth_dest_mac;
    assign tx_icmp_eth_type     = rx_icmp_eth_type;

    assign tx_icmp_ip_dscp = rx_icmp_ip_dscp;
    assign tx_icmp_ip_ecn = rx_icmp_ip_ecn;
    assign tx_icmp_ip_length = rx_icmp_ip_length;
    assign tx_icmp_ip_identification = rx_icmp_ip_identification + 16'd1;
    assign tx_icmp_ip_flags = rx_icmp_ip_flags;
    assign tx_icmp_ip_fragment_offset = rx_icmp_ip_fragment_offset;
    assign tx_icmp_ip_ttl = rx_icmp_ip_ttl;
    // Swap addresses 
    assign tx_icmp_ip_source_ip = local_ip;
    assign tx_icmp_ip_dest_ip = rx_icmp_ip_source_ip;
    // Echo reply
    assign tx_icmp_type = 8'h00;
    assign tx_icmp_code = 8'h00;
    // TODO copute the real check sum
    assign tx_icmp_checksum = rx_icmp_checksum[15:8] >= 8'hf8 ? rx_icmp_checksum + 16'h0801 : rx_icmp_checksum + 16'h0800;
    assign tx_icmp_roh = rx_icmp_roh;

    assign tx_icmp_payload_axis_tdata = rx_icmp_payload_axis_tdata;
    assign tx_icmp_payload_axis_tkeep = rx_icmp_payload_axis_tkeep;
    assign tx_icmp_payload_axis_tvalid = rx_icmp_payload_axis_tvalid && match_cond_reg;
    assign rx_icmp_payload_axis_tready = (tx_icmp_payload_axis_tready && match_cond_reg) || no_match_reg;
    assign tx_icmp_payload_axis_tlast = rx_icmp_payload_axis_tlast;
    assign tx_icmp_payload_axis_tuser = rx_icmp_payload_axis_tuser;

    icmp_ip_rx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) icmp_ip_rx_inst (
        .clk(clk),
        .rst(rst),
        // IP frame input
        .s_ip_hdr_valid(s_ip_hdr_valid),
        .s_ip_hdr_ready(s_ip_hdr_ready),
        .s_eth_dest_mac(s_eth_dest_mac),
        .s_eth_src_mac(s_eth_src_mac),
        .s_eth_type(s_eth_type),
        .s_ip_version(s_ip_version),
        .s_ip_ihl(s_ip_ihl),
        .s_ip_dscp(s_ip_dscp),
        .s_ip_ecn(s_ip_ecn),
        .s_ip_length(s_ip_length),
        .s_ip_identification(s_ip_identification),
        .s_ip_flags(s_ip_flags),
        .s_ip_fragment_offset(s_ip_fragment_offset),
        .s_ip_ttl(s_ip_ttl),
        .s_ip_protocol(s_ip_protocol),
        .s_ip_header_checksum(s_ip_header_checksum),
        .s_ip_source_ip(s_ip_source_ip),
        .s_ip_dest_ip(s_ip_dest_ip),
        .s_ip_payload_axis_tdata(s_ip_payload_axis_tdata),
        .s_ip_payload_axis_tkeep(s_ip_payload_axis_tkeep),
        .s_ip_payload_axis_tvalid(s_ip_payload_axis_tvalid),
        .s_ip_payload_axis_tready(s_ip_payload_axis_tready),
        .s_ip_payload_axis_tlast(s_ip_payload_axis_tlast),
        .s_ip_payload_axis_tuser(s_ip_payload_axis_tuser),
        // ICMP frame output
        .m_icmp_hdr_valid(rx_icmp_hdr_valid),
        .m_icmp_hdr_ready(rx_icmp_hdr_ready),
        .m_eth_dest_mac(rx_icmp_eth_dest_mac),
        .m_eth_src_mac(rx_icmp_eth_src_mac),
        .m_eth_type(rx_icmp_eth_type),
        .m_ip_version(rx_icmp_ip_version),
        .m_ip_ihl(rx_icmp_ip_ihl),
        .m_ip_dscp(rx_icmp_ip_dscp),
        .m_ip_ecn(rx_icmp_ip_ecn),
        .m_ip_length(rx_icmp_ip_length),
        .m_ip_identification(rx_icmp_ip_identification),
        .m_ip_flags(rx_icmp_ip_flags),
        .m_ip_fragment_offset(rx_icmp_ip_fragment_offset),
        .m_ip_ttl(rx_icmp_ip_ttl),
        .m_ip_protocol(rx_icmp_ip_protocol),
        .m_ip_header_checksum(rx_icmp_ip_header_checksum),
        .m_ip_source_ip(rx_icmp_ip_source_ip),
        .m_ip_dest_ip(rx_icmp_ip_dest_ip),
        .m_icmp_type(rx_icmp_type),
        .m_icmp_code(rx_icmp_code),
        .m_icmp_checksum(rx_icmp_checksum),
        .m_icmp_roh(rx_icmp_roh),
        .m_icmp_payload_axis_tdata(rx_icmp_payload_axis_tdata),
        .m_icmp_payload_axis_tkeep(rx_icmp_payload_axis_tkeep),
        .m_icmp_payload_axis_tvalid(rx_icmp_payload_axis_tvalid),
        .m_icmp_payload_axis_tready(rx_icmp_payload_axis_tready),
        .m_icmp_payload_axis_tlast(rx_icmp_payload_axis_tlast),
        .m_icmp_payload_axis_tuser(rx_icmp_payload_axis_tuser),
        // Status signals
        .busy(rx_busy),
        .error_header_early_termination(rx_error_header_early_termination),
        .error_payload_early_termination(rx_error_payload_early_termination)
    );

    icmp_checksum_gen #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDER_STEPS(max(2, (2 ** $clog2(DATA_WIDTH / 64)))),
        .PAYLOAD_FIFO_DEPTH(CHECKSUM_PAYLOAD_FIFO_DEPTH),
        .HEADER_FIFO_DEPTH(CHECKSUM_HEADER_FIFO_DEPTH)
    ) icmp_checksum_gen_test_inst (
        .clk(clk),
        .rst(rst),
        // ICMP frame input
        .s_icmp_hdr_valid(tx_icmp_hdr_valid),
        .s_icmp_hdr_ready(tx_icmp_hdr_ready),
        .s_eth_dest_mac(tx_icmp_eth_dest_mac),
        .s_eth_src_mac(tx_icmp_eth_src_mac),
        .s_eth_type(tx_icmp_type),
        .s_ip_version(4'h4),
        .s_ip_ihl(4'h5),
        .s_ip_dscp(tx_icmp_ip_dscp),
        .s_ip_ecn(tx_icmp_ip_ecn),
        .s_ip_length(tx_icmp_ip_length),
        .s_ip_identification(tx_icmp_ip_identification),
        .s_ip_flags(tx_icmp_ip_flags),
        .s_ip_fragment_offset(tx_icmp_ip_fragment_offset),
        .s_ip_ttl(tx_icmp_ip_ttl),
        .s_ip_protocol(8'h01),
        .s_ip_header_checksum(0),
        .s_ip_source_ip(tx_icmp_ip_source_ip),
        .s_ip_dest_ip(tx_icmp_ip_dest_ip),
        .s_icmp_type(tx_icmp_type),
        .s_icmp_code(tx_icmp_code),
        .s_icmp_checksum(tx_icmp_checksum),
        .s_icmp_roh(tx_icmp_roh),
        .s_icmp_payload_axis_tdata(tx_icmp_payload_axis_tdata),
        .s_icmp_payload_axis_tkeep(tx_icmp_payload_axis_tkeep),
        .s_icmp_payload_axis_tvalid(tx_icmp_payload_axis_tvalid),
        .s_icmp_payload_axis_tready(tx_icmp_payload_axis_tready),
        .s_icmp_payload_axis_tlast(tx_icmp_payload_axis_tlast),
        .s_icmp_payload_axis_tuser(tx_icmp_payload_axis_tuser),
        // ICMP frame output
        .m_icmp_hdr_valid(tx_post_checksum_icmp_hdr_valid),
        .m_icmp_hdr_ready(tx_post_checksum_icmp_hdr_ready),
        .m_eth_dest_mac(tx_post_checksum_icmp_eth_dest_mac),
        .m_eth_src_mac (tx_post_checksum_icmp_eth_src_mac),
        .m_eth_type(tx_post_checksum_icmp_eth_type),
        .m_ip_version(),
        .m_ip_ihl(),
        .m_ip_dscp(tx_post_checksum_icmp_ip_dscp),
        .m_ip_ecn(tx_post_checksum_icmp_ip_ecn),
        .m_ip_length(tx_post_checksum_icmp_ip_length),
        .m_ip_identification(tx_post_checksum_icmp_ip_identification),
        .m_ip_flags(tx_post_checksum_icmp_ip_flags),
        .m_ip_fragment_offset(tx_post_checksum_icmp_ip_fragment_offset),
        .m_ip_ttl(tx_post_checksum_icmp_ip_ttl),
        .m_ip_protocol(),
        .m_ip_header_checksum(),
        .m_ip_source_ip(tx_post_checksum_icmp_ip_source_ip),
        .m_ip_dest_ip(tx_post_checksum_icmp_ip_dest_ip),
        .m_icmp_type(tx_post_checksum_icmp_type),
        .m_icmp_code(tx_post_checksum_icmp_code),
        .m_icmp_checksum(tx_post_checksum_icmp_checksum),
        .m_icmp_roh(tx_post_checksum_icmp_roh),
        .m_icmp_payload_axis_tdata(tx_post_checksum_icmp_payload_axis_tdata),
        .m_icmp_payload_axis_tkeep(tx_post_checksum_icmp_payload_axis_tkeep),
        .m_icmp_payload_axis_tvalid(tx_post_checksum_icmp_payload_axis_tvalid),
        .m_icmp_payload_axis_tready(tx_post_checksum_icmp_payload_axis_tready),
        .m_icmp_payload_axis_tlast(tx_post_checksum_icmp_payload_axis_tlast),
        .m_icmp_payload_axis_tuser(tx_post_checksum_icmp_payload_axis_tuser),
        // Status signals
        .busy()
    );

    always @* begin
        state_next = STATE_IDLE;

        tx_post_checksum_icmp_hdr_ready_next = 1'b0;

        hdr_sum_next = hdr_sum_reg;
        hdr_sum_temp_next = hdr_sum_temp_reg;

        outgoing_eth_dest_mac_next = outgoing_eth_dest_mac_reg;
        outgoing_eth_src_mac_next = outgoing_eth_src_mac_reg;
        outgoing_ip_length_next = outgoing_ip_length_reg;
        outgoing_ip_source_ip_next = outgoing_ip_source_ip_reg;
        outgoing_ip_dest_ip_next = outgoing_ip_dest_ip_reg;
        outgoing_icmp_type_next = outgoing_icmp_type_reg;
        outgoing_icmp_code_next = outgoing_icmp_code_reg;
        outgoing_icmp_checksum_next = outgoing_icmp_checksum_reg;
        outgoing_icmp_roh_next = outgoing_icmp_roh_reg;

        outgoing_ip_hdr_valid_next = outgoing_ip_hdr_valid_reg && !outgoing_ip_hdr_ready;

        case (state_reg)
            STATE_IDLE: begin
                // wait for outgoing packet
                if (tx_post_checksum_icmp_hdr_valid) begin
                    if (COMPUTE_IP_HDR_CHECKSUM) begin
                        outgoing_eth_dest_mac_next      = tx_post_checksum_icmp_eth_dest_mac;
                        outgoing_eth_src_mac_next       = tx_post_checksum_icmp_eth_src_mac;
                        outgoing_ip_length_next         = tx_post_checksum_icmp_ip_length;
                        outgoing_ip_source_ip_next      = tx_post_checksum_icmp_ip_source_ip;
                        outgoing_ip_dest_ip_next        = tx_post_checksum_icmp_ip_dest_ip;
                        outgoing_icmp_type_next         = tx_post_checksum_icmp_type;
                        outgoing_icmp_code_next         = tx_post_checksum_icmp_code;
                        outgoing_icmp_checksum_next     = tx_post_checksum_icmp_checksum;
                        outgoing_icmp_roh_next          = tx_post_checksum_icmp_roh;
                        hdr_sum_next = {4'd4, 4'd5, 6'd0, 2'b00} +
                        tx_post_checksum_icmp_ip_length +
                        16'd0 +
                        {3'b010, 13'd0} +
                        {8'h40, 8'h01} +
                        tx_post_checksum_icmp_ip_source_ip[31:16] +
                        tx_post_checksum_icmp_ip_source_ip[15: 0] +
                        tx_post_checksum_icmp_ip_dest_ip[31:16] +
                        tx_post_checksum_icmp_ip_dest_ip[15: 0];
                        if (IP_HDR_CHECKSUM_PIPELINED) begin
                            state_next = STATE_COMPUTE_CHECKSUM;
                        end else begin
                            hdr_sum_temp_next = hdr_sum_next[15:0] + hdr_sum_next[19:16];
                            hdr_sum_temp_next = hdr_sum_temp_next[15:0] + hdr_sum_temp_next[16];
                            tx_post_checksum_icmp_hdr_ready_next = 1'b1;
                            outgoing_ip_hdr_valid_next = 1'b1;
                            state_next = STATE_WAIT_PACKET;
                        end
                    end else begin
                        outgoing_eth_dest_mac_next      = tx_post_checksum_icmp_eth_dest_mac;
                        outgoing_eth_src_mac_next       = tx_post_checksum_icmp_eth_src_mac;
                        outgoing_ip_length_next         = tx_post_checksum_icmp_ip_length;
                        outgoing_ip_source_ip_next      = tx_post_checksum_icmp_ip_source_ip;
                        outgoing_ip_dest_ip_next        = tx_post_checksum_icmp_ip_dest_ip;
                        outgoing_icmp_type_next         = tx_post_checksum_icmp_type;
                        outgoing_icmp_code_next         = tx_post_checksum_icmp_code;
                        outgoing_icmp_checksum_next     = tx_post_checksum_icmp_checksum;
                        outgoing_icmp_roh_next          = tx_post_checksum_icmp_roh;
                        hdr_sum_temp_next = 20'hf_ffff;
                        outgoing_ip_hdr_valid_next = 1'b1;
                        state_next = STATE_WAIT_PACKET;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_COMPUTE_CHECKSUM: begin
                hdr_sum_temp_next = hdr_sum_reg[15:0] + hdr_sum_reg[19:16];
                hdr_sum_temp_next = hdr_sum_temp_next[15:0] + hdr_sum_temp_next[16];

                tx_post_checksum_icmp_hdr_ready_next = 1'b1;
                outgoing_ip_hdr_valid_next = 1'b1;

                state_next = STATE_WAIT_PACKET;
            end
            STATE_WAIT_PACKET: begin

                // wait for packet transfer to complete
                if (tx_post_checksum_icmp_payload_axis_tlast && tx_post_checksum_icmp_payload_axis_tready && tx_post_checksum_icmp_payload_axis_tvalid) begin
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_PACKET;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            tx_post_checksum_icmp_hdr_ready_reg <= 1'b0;
            outgoing_ip_hdr_valid_reg <= 1'b0;

            outgoing_eth_dest_mac_reg      <= 48'h0;
            outgoing_eth_src_mac_reg       <= 48'h0;
            outgoing_ip_length_reg         <= 16'd0;
            outgoing_ip_source_ip_reg      <= local_ip;
            outgoing_ip_dest_ip_reg        <= {8'hFF, 8'hFF, 8'hFF, 8'hFF};

            outgoing_icmp_type_reg     <= 8'h00;
            outgoing_icmp_code_reg     <= 8'h00;
            outgoing_icmp_checksum_reg <= 16'h0000;
            outgoing_icmp_roh_reg      <= 32'h0000_0000;

        end else begin
            state_reg <= state_next;

            tx_post_checksum_icmp_hdr_ready_reg <= tx_post_checksum_icmp_hdr_ready_next;

            outgoing_eth_dest_mac_reg      <= outgoing_eth_dest_mac_next;
            outgoing_eth_src_mac_reg       <= outgoing_eth_src_mac_next;
            outgoing_ip_length_reg         <= outgoing_ip_length_next;
            outgoing_ip_source_ip_reg      <= outgoing_ip_source_ip_next;
            outgoing_ip_dest_ip_reg        <= outgoing_ip_dest_ip_next;

            outgoing_icmp_type_reg     <= outgoing_icmp_type_next;
            outgoing_icmp_code_reg     <= outgoing_icmp_code_next;
            outgoing_icmp_checksum_reg <= outgoing_icmp_checksum_next;
            outgoing_icmp_roh_reg      <= outgoing_icmp_roh_next;

            outgoing_ip_hdr_valid_reg <= outgoing_ip_hdr_valid_next;

            hdr_sum_reg      <= hdr_sum_next;
            hdr_sum_temp_reg <= hdr_sum_temp_next;

        end
    end

    assign tx_post_checksum_icmp_hdr_ready = tx_post_checksum_icmp_hdr_ready_reg;

    icmp_ip_tx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) icmp_ip_tx_inst (
        .clk(clk),
        .rst(rst),
        // ICMP frame input
        .s_icmp_hdr_valid    (outgoing_ip_hdr_valid_reg),
        .s_icmp_hdr_ready    (outgoing_ip_hdr_ready),
        .s_eth_dest_mac      (outgoing_eth_dest_mac_reg),
        .s_eth_src_mac       (outgoing_eth_src_mac_reg),
        .s_eth_type          (16'h0800),
        .s_ip_version        (4'h4),
        .s_ip_ihl            (4'h5),
        .s_ip_dscp           (6'd0),
        .s_ip_ecn            (2'b00),
        .s_ip_length         (outgoing_ip_length_reg),
        .s_ip_identification (16'd0),
        .s_ip_flags          (3'b010),
        .s_ip_fragment_offset(13'd0),
        .s_ip_ttl            (8'h40),
        .s_ip_protocol       (8'h01),
        .s_ip_header_checksum(~hdr_sum_temp_reg[15:0]),
        .s_ip_source_ip      (outgoing_ip_source_ip_reg),
        .s_ip_dest_ip        (outgoing_ip_dest_ip_reg),
        .s_icmp_type         (outgoing_icmp_type_reg),
        .s_icmp_code         (outgoing_icmp_code_reg),
        .s_icmp_checksum     (outgoing_icmp_checksum_reg),
        .s_icmp_roh          (outgoing_icmp_roh_reg),
        .s_icmp_payload_axis_tdata (tx_post_checksum_icmp_payload_axis_tdata),
        .s_icmp_payload_axis_tkeep (tx_post_checksum_icmp_payload_axis_tkeep),
        .s_icmp_payload_axis_tvalid(tx_post_checksum_icmp_payload_axis_tvalid),
        .s_icmp_payload_axis_tready(tx_post_checksum_icmp_payload_axis_tready),
        .s_icmp_payload_axis_tlast (tx_post_checksum_icmp_payload_axis_tlast),
        .s_icmp_payload_axis_tuser (tx_post_checksum_icmp_payload_axis_tuser),
        // IP frame output
        .m_ip_hdr_valid      (m_ip_hdr_valid),
        .m_ip_hdr_ready      (m_ip_hdr_ready),
        .m_eth_dest_mac      (m_eth_dest_mac),
        .m_eth_src_mac       (m_eth_src_mac),
        .m_eth_type          (m_eth_type),
        .m_ip_version        (m_ip_version),
        .m_ip_ihl            (m_ip_ihl),
        .m_ip_dscp           (m_ip_dscp),
        .m_ip_ecn            (m_ip_ecn),
        .m_ip_length         (m_ip_length),
        .m_ip_identification (m_ip_identification),
        .m_ip_flags          (m_ip_flags),
        .m_ip_fragment_offset(m_ip_fragment_offset),
        .m_ip_ttl            (m_ip_ttl),
        .m_ip_protocol       (m_ip_protocol),
        .m_ip_header_checksum(m_ip_header_checksum),
        .m_ip_source_ip      (m_ip_source_ip),
        .m_ip_dest_ip        (m_ip_dest_ip),
        .m_is_roce_packet    (m_is_roce_packet),

        .m_ip_payload_axis_tdata (m_ip_payload_axis_tdata),
        .m_ip_payload_axis_tkeep (m_ip_payload_axis_tkeep),
        .m_ip_payload_axis_tvalid(m_ip_payload_axis_tvalid),
        .m_ip_payload_axis_tready(m_ip_payload_axis_tready),
        .m_ip_payload_axis_tlast (m_ip_payload_axis_tlast),
        .m_ip_payload_axis_tuser (m_ip_payload_axis_tuser),
        // Status signals
        .busy(tx_busy)
    );


endmodule

`resetall
