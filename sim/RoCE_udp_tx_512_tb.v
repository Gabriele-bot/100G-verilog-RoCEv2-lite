// Language: Verilog 2001


`resetall 
`timescale 1ns / 1ps 
`default_nettype none

/*
 * UDP ethernet frame transmitter (UDP frame in, IP frame out, 64-bit datapath)
 */
module RoCE_udp_tx_512_tb();

    parameter C_CLK_PERIOD = 10 ; // Clock period (100 Mhz).    


    // ==========================================================================
    // ==                                Signals                               ==
    // ==========================================================================
    // Simulation (DUT inputs and outputs).
    reg clk;
    reg resetn;

    wire [511:0] m_udp_payload_axis_tdata;
    wire [63:0] m_udp_payload_axis_tkeep;
    wire m_udp_payload_axis_tvalid;
    wire m_udp_payload_axis_tlast;
    wire m_udp_payload_axis_tuser;
    wire m_udp_payload_axis_tready;
    
    wire [511:0] m_udp_payload_axis_icrc_tdata;
    wire [63:0] m_udp_payload_axis_icrc_tkeep;
    wire m_udp_payload_axis_icrc_tvalid;
    wire m_udp_payload_axis_icrc_tlast;
    wire m_udp_payload_axis_icrc_tuser;
    wire m_udp_payload_axis_icrc_tready;

    wire [511:0] s_roce_payload_axis_tdata;
    wire [63:0] s_roce_payload_axis_tkeep;
    wire s_roce_payload_axis_tvalid;
    wire s_roce_payload_axis_tlast;
    wire s_roce_payload_axis_tuser;
    wire s_roce_payload_axis_tready;

    wire s_roce_payload_axis_tvalid_1;
    reg  s_roce_payload_axis_tvalid_2;

    reg [511:0] s_axis_tdata;
    reg [63:0] s_axis_tkeep;
    reg s_axis_tvalid;
    reg s_axis_tlast;
    reg s_axis_tuser;

    reg m_axis_tready;

    wire s_roce_bth_valid;
    wire s_roce_reth_valid;

    reg s_roce_bth_valid_reg;
    wire s_roce_bth_ready;
    reg s_roce_reth_valid_reg;
    wire s_roce_reth_ready;

    reg [ 7:0] s_roce_bth_op_code = 8'd2;
    reg [15:0] s_roce_bth_p_key = 16'd4552;
    reg [23:0] s_roce_bth_psn = 24'd200;
    reg [23:0] s_roce_bth_dest_qp = 24'd16;
    reg        s_roce_bth_ack_req = 1'd1;

    reg [63:0] s_roce_reth_v_addr = 64'd12435;
    reg [31:0] s_roce_reth_r_key = 32'd233;
    reg [31:0] s_roce_reth_length = 32'd444;

    reg [47:0] s_eth_dest_mac = 48'd124521111;
    reg [47:0] s_eth_src_mac = 48'd2318743;
    reg [15:0] s_eth_type = 16'd123;
    reg [ 3:0] s_ip_version = 4'd2;
    reg [ 3:0] s_ip_ihl = 4'd2;
    reg [ 5:0] s_ip_dscp = 6'd3;
    reg [ 1:0] s_ip_ecn = 2'd3;
    reg [15:0] s_ip_identification = 16'd44;
    reg [ 2:0] s_ip_flags = 3'd3;
    reg [12:0] s_ip_fragment_offset = 13'd21;
    reg [ 7:0] s_ip_ttl = 8'd42;
    reg [ 7:0] s_ip_protocol = 8'd23;
    reg [15:0] s_ip_header_checksum = 16'd312;
    reg [31:0] s_ip_source_ip = 32'd232;
    reg [31:0] s_ip_dest_ip = 32'd3214;
    reg [15:0] s_udp_source_port = 16'd2321;
    reg [15:0] s_udp_dest_port = 16'd123;
    reg [15:0] s_udp_length = 16'd1400;
    reg [15:0] s_udp_checksum = 16'd0;

    reg[63:0] word_counter = 64'd0;
    reg[32:0] random_value = 32'd0;

    reg enable_input;

    wire busy;
    wire error_payload_early_termination;

    integer i;
    integer j;
    integer k;

    function [15:0] keep2count;
        input [63:0] k;
        casez (k)
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0: keep2count = 16'd0;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01: keep2count = 16'd1;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011: keep2count = 16'd2;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111: keep2count = 16'd3;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111: keep2count = 16'd4;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111: keep2count = 16'd5;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111: keep2count = 16'd6;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111: keep2count = 16'd7;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111: keep2count = 16'd8;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111: keep2count = 16'd9;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111: keep2count = 16'd10;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111: keep2count = 16'd11;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111: keep2count = 16'd12;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111: keep2count = 16'd13;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111: keep2count = 16'd14;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111: keep2count = 16'd15;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111: keep2count = 16'd16;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111: keep2count = 16'd17;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111: keep2count = 16'd18;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111: keep2count = 16'd19;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111: keep2count = 16'd20;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111: keep2count = 16'd21;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111: keep2count = 16'd22;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111: keep2count = 16'd23;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111: keep2count = 16'd24;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111: keep2count = 16'd25;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111: keep2count = 16'd26;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111: keep2count = 16'd27;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111: keep2count = 16'd28;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111: keep2count = 16'd29;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111: keep2count = 16'd30;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111: keep2count = 16'd31;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111: keep2count = 16'd32;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111: keep2count = 16'd33;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111: keep2count = 16'd34;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111: keep2count = 16'd35;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111: keep2count = 16'd36;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111: keep2count = 16'd37;
            64'bzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111: keep2count = 16'd38;
            64'bzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111: keep2count = 16'd39;
            64'bzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111: keep2count = 16'd40;
            64'bzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111: keep2count = 16'd41;
            64'bzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111: keep2count = 16'd42;
            64'bzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111: keep2count = 16'd43;
            64'bzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111: keep2count = 16'd44;
            64'bzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111: keep2count = 16'd45;
            64'bzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111: keep2count = 16'd46;
            64'bzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111111: keep2count = 16'd47;
            64'bzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111111: keep2count = 16'd48;
            64'bzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111111: keep2count = 16'd49;
            64'bzzzzzzzzzzzzz011111111111111111111111111111111111111111111111111: keep2count = 16'd50;
            64'bzzzzzzzzzzzz0111111111111111111111111111111111111111111111111111: keep2count = 16'd51;
            64'bzzzzzzzzzzz01111111111111111111111111111111111111111111111111111: keep2count = 16'd52;
            64'bzzzzzzzzzz011111111111111111111111111111111111111111111111111111: keep2count = 16'd53;
            64'bzzzzzzzzz0111111111111111111111111111111111111111111111111111111: keep2count = 16'd54;
            64'bzzzzzzzz01111111111111111111111111111111111111111111111111111111: keep2count = 16'd55;
            64'bzzzzzzz011111111111111111111111111111111111111111111111111111111: keep2count = 16'd56;
            64'bzzzzzz0111111111111111111111111111111111111111111111111111111111: keep2count = 16'd57;
            64'bzzzzz01111111111111111111111111111111111111111111111111111111111: keep2count = 16'd58;
            64'bzzzz011111111111111111111111111111111111111111111111111111111111: keep2count = 16'd59;
            64'bzzz0111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd60;
            64'bzz01111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd61;
            64'bz011111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd62;
            64'b0111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd63;
            64'b1111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd64;
        endcase
    endfunction

    function [63:0] count2keep;
        input [6:0] k;
        case (k)
            7'd0    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000000000;
            7'd1    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000000001;
            7'd2    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000000011;
            7'd3    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000000111;
            7'd4    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000001111;
            7'd5    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000011111;
            7'd6    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000000111111;
            7'd7    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000001111111;
            7'd8    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000011111111;
            7'd9    : count2keep =    64'b0000000000000000000000000000000000000000000000000000000111111111;
            7'd10   : count2keep =    64'b0000000000000000000000000000000000000000000000000000001111111111;
            7'd11   : count2keep =    64'b0000000000000000000000000000000000000000000000000000011111111111;
            7'd12   : count2keep =    64'b0000000000000000000000000000000000000000000000000000111111111111;
            7'd13   : count2keep =    64'b0000000000000000000000000000000000000000000000000001111111111111;
            7'd14   : count2keep =    64'b0000000000000000000000000000000000000000000000000011111111111111;
            7'd15   : count2keep =    64'b0000000000000000000000000000000000000000000000000111111111111111;
            7'd16   : count2keep =    64'b0000000000000000000000000000000000000000000000001111111111111111;
            7'd17   : count2keep =    64'b0000000000000000000000000000000000000000000000011111111111111111;
            7'd18   : count2keep =    64'b0000000000000000000000000000000000000000000000111111111111111111;
            7'd19   : count2keep =    64'b0000000000000000000000000000000000000000000001111111111111111111;
            7'd20   : count2keep =    64'b0000000000000000000000000000000000000000000011111111111111111111;
            7'd21   : count2keep =    64'b0000000000000000000000000000000000000000000111111111111111111111;
            7'd22   : count2keep =    64'b0000000000000000000000000000000000000000001111111111111111111111;
            7'd23   : count2keep =    64'b0000000000000000000000000000000000000000011111111111111111111111;
            7'd24   : count2keep =    64'b0000000000000000000000000000000000000000111111111111111111111111;
            7'd25   : count2keep =    64'b0000000000000000000000000000000000000001111111111111111111111111;
            7'd26   : count2keep =    64'b0000000000000000000000000000000000000011111111111111111111111111;
            7'd27   : count2keep =    64'b0000000000000000000000000000000000000111111111111111111111111111;
            7'd28   : count2keep =    64'b0000000000000000000000000000000000001111111111111111111111111111;
            7'd29   : count2keep =    64'b0000000000000000000000000000000000011111111111111111111111111111;
            7'd30   : count2keep =    64'b0000000000000000000000000000000000111111111111111111111111111111;
            7'd31   : count2keep =    64'b0000000000000000000000000000000001111111111111111111111111111111;
            7'd32   : count2keep =    64'b0000000000000000000000000000000011111111111111111111111111111111;
            7'd33   : count2keep =    64'b0000000000000000000000000000000111111111111111111111111111111111;
            7'd34   : count2keep =    64'b0000000000000000000000000000001111111111111111111111111111111111;
            7'd35   : count2keep =    64'b0000000000000000000000000000011111111111111111111111111111111111;
            7'd36   : count2keep =    64'b0000000000000000000000000000111111111111111111111111111111111111;
            7'd37   : count2keep =    64'b0000000000000000000000000001111111111111111111111111111111111111;
            7'd38   : count2keep =    64'b0000000000000000000000000011111111111111111111111111111111111111;
            7'd39   : count2keep =    64'b0000000000000000000000000111111111111111111111111111111111111111;
            7'd40   : count2keep =    64'b0000000000000000000000001111111111111111111111111111111111111111;
            7'd41   : count2keep =    64'b0000000000000000000000011111111111111111111111111111111111111111;
            7'd42   : count2keep =    64'b0000000000000000000000111111111111111111111111111111111111111111;
            7'd43   : count2keep =    64'b0000000000000000000001111111111111111111111111111111111111111111;
            7'd44   : count2keep =    64'b0000000000000000000011111111111111111111111111111111111111111111;
            7'd45   : count2keep =    64'b0000000000000000000111111111111111111111111111111111111111111111;
            7'd46   : count2keep =    64'b0000000000000000001111111111111111111111111111111111111111111111;
            7'd47   : count2keep =    64'b0000000000000000011111111111111111111111111111111111111111111111;
            7'd48   : count2keep =    64'b0000000000000000111111111111111111111111111111111111111111111111;
            7'd49   : count2keep =    64'b0000000000000001111111111111111111111111111111111111111111111111;
            7'd50   : count2keep =    64'b0000000000000011111111111111111111111111111111111111111111111111;
            7'd51   : count2keep =    64'b0000000000000111111111111111111111111111111111111111111111111111;
            7'd52   : count2keep =    64'b0000000000001111111111111111111111111111111111111111111111111111;
            7'd53   : count2keep =    64'b0000000000011111111111111111111111111111111111111111111111111111;
            7'd54   : count2keep =    64'b0000000000111111111111111111111111111111111111111111111111111111;
            7'd55   : count2keep =    64'b0000000001111111111111111111111111111111111111111111111111111111;
            7'd56   : count2keep =    64'b0000000011111111111111111111111111111111111111111111111111111111;
            7'd57   : count2keep =    64'b0000000111111111111111111111111111111111111111111111111111111111;
            7'd58   : count2keep =    64'b0000001111111111111111111111111111111111111111111111111111111111;
            7'd59   : count2keep =    64'b0000011111111111111111111111111111111111111111111111111111111111;
            7'd60   : count2keep =    64'b0000111111111111111111111111111111111111111111111111111111111111;
            7'd61   : count2keep =    64'b0001111111111111111111111111111111111111111111111111111111111111;
            7'd62   : count2keep =    64'b0011111111111111111111111111111111111111111111111111111111111111;
            7'd63   : count2keep =    64'b0111111111111111111111111111111111111111111111111111111111111111;
            7'd64   : count2keep =    64'b1111111111111111111111111111111111111111111111111111111111111111;
            default : count2keep =    64'b1111111111111111111111111111111111111111111111111111111111111111;
        endcase
    endfunction


    // ==========================================================================
    // ==                                  DUT                                 ==
    // ==========================================================================

    // Instantiate the DUT.
    RoCE_udp_tx_512 RoCE_udp_tx_512_instance(
        .clk(clk),
        .rst(~resetn),
        .s_roce_bth_valid(s_roce_bth_valid),
        .s_roce_bth_ready(s_roce_bth_ready),
        .s_roce_bth_op_code(s_roce_bth_op_code),
        .s_roce_bth_p_key(s_roce_bth_p_key),
        .s_roce_bth_psn(s_roce_bth_psn),
        .s_roce_bth_dest_qp(s_roce_bth_dest_qp),
        .s_roce_bth_ack_req(s_roce_bth_ack_req),
        .s_roce_reth_valid(s_roce_reth_valid),
        .s_roce_reth_ready(s_roce_reth_ready),
        .s_roce_reth_v_addr(s_roce_reth_v_addr),
        .s_roce_reth_r_key(s_roce_reth_r_key),
        .s_roce_reth_length(s_roce_reth_length),
        .s_eth_dest_mac(s_eth_dest_mac),
        .s_eth_src_mac(s_eth_src_mac),
        .s_eth_type(s_eth_type),
        .s_ip_version(s_ip_version),
        .s_ip_ihl(s_ip_ihl),
        .s_ip_dscp(s_ip_dscp),
        .s_ip_ecn(s_ip_ecn),
        .s_ip_identification(s_ip_identification),
        .s_ip_flags(s_ip_flags),
        .s_ip_fragment_offset(s_ip_fragment_offset),
        .s_ip_ttl(s_ip_ttl),
        .s_ip_protocol(s_ip_protocol),
        .s_ip_header_checksum(s_ip_header_checksum),
        .s_ip_source_ip(s_ip_source_ip),
        .s_ip_dest_ip(s_ip_dest_ip),
        .s_udp_source_port(s_udp_source_port),
        .s_udp_dest_port(s_udp_dest_port),
        .s_udp_length(s_udp_length),
        .s_udp_checksum(s_udp_checksum),
        .s_roce_payload_axis_tdata(s_roce_payload_axis_tdata),
        .s_roce_payload_axis_tkeep(s_roce_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(s_roce_payload_axis_tvalid),
        .s_roce_payload_axis_tready(s_roce_payload_axis_tready),
        .s_roce_payload_axis_tlast(s_roce_payload_axis_tlast),
        .s_roce_payload_axis_tuser(1'b0),
        .m_udp_hdr_valid(),
        .m_udp_hdr_ready(1'b1),
        .m_eth_dest_mac(),
        .m_eth_src_mac(),
        .m_eth_type(),
        .m_ip_version(),
        .m_ip_ihl(),
        .m_ip_dscp(),
        .m_ip_ecn(),
        .m_ip_length(),
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
        .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep(m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
        .busy(busy),
        .error_payload_early_termination(error_payload_early_termination)
    );
    
    axis_RoCE_icrc_insert_512 #(
        .ENABLE_PADDING(0),
        .MIN_FRAME_LENGTH(64)
    ) axis_RoCE_icrc_insert_512_instance(
        .clk(clk),
        .rst(~resetn),
        .s_axis_tdata(m_udp_payload_axis_tdata),
        .s_axis_tkeep(m_udp_payload_axis_tkeep),
        .s_axis_tvalid(m_udp_payload_axis_tvalid),
        .s_axis_tready(m_udp_payload_axis_tready),
        .s_axis_tlast(m_udp_payload_axis_tlast),
        .s_axis_tuser(m_udp_payload_axis_tuser),
        .m_axis_tdata(m_udp_payload_axis_icrc_tdata),
        .m_axis_tkeep(m_udp_payload_axis_icrc_tkeep),
        .m_axis_tvalid(m_udp_payload_axis_icrc_tvalid),
        .m_axis_tready(m_udp_payload_axis_icrc_tready),
        .m_axis_tlast(m_udp_payload_axis_icrc_tlast),
        .m_axis_tuser(m_udp_payload_axis_icrc_tuser),
        .busy(busy)
    );
    


    //assign s_roce_payload_axis_tdata = s_axis_tdata;
    assign s_roce_payload_axis_tkeep = s_roce_payload_axis_tlast ? count2keep(s_udp_length-word_counter-28-8) : {64{1'b1}};
    assign s_roce_payload_axis_tvalid = ((word_counter+8+28 <= s_udp_length) ? 1'b1 : 1'b0) && enable_input;
    assign s_roce_payload_axis_tlast = (word_counter+64+28+8 >= s_udp_length) ? 1'b1 : 1'b0;
    assign s_roce_payload_axis_tuser = s_axis_tuser;

    assign s_roce_payload_axis_tvalid_1 = s_roce_payload_axis_tvalid;
    always @(posedge clk) begin
        s_roce_payload_axis_tvalid_2 <= s_roce_payload_axis_tvalid_1;
    end

    assign s_roce_bth_valid = (s_roce_payload_axis_tvalid_1 && ~s_roce_payload_axis_tvalid_2) ? 1'b1 : 1'b0;
    assign s_roce_reth_valid = (s_roce_payload_axis_tvalid_1 && ~s_roce_payload_axis_tvalid_2) ? 1'b1 : 1'b0;

    assign m_udp_payload_axis_icrc_tready = m_axis_tready;

    // Clock generation.
    always begin
        #(C_CLK_PERIOD / 2) clk = ! clk;
    end

    initial begin
        clk = 1'b1;
        resetn = 1'b1;

        s_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
        s_axis_tuser <= 1'b0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;

        m_axis_tready <= 1'b0;

        s_roce_bth_valid_reg <= 1'b0;
        s_roce_reth_valid_reg <= 1'b0;

        enable_input <= 1'b0;




        // Generate first reset.
        #(2 * C_CLK_PERIOD) resetn <= 1'b0;
        #(50 * C_CLK_PERIOD) resetn <= 1'b1;
        #(50 * C_CLK_PERIOD) resetn <= 1'b1;


        #(1 * C_CLK_PERIOD) begin
            s_roce_bth_valid_reg <= 1'b1;
            s_roce_reth_valid_reg <= 1'b1;
            s_axis_tvalid <= 1'b1;
            enable_input <= 1'b1;
        end

        //#(1 * C_CLK_PERIOD) begin
        //    s_axis_tvalid <= 1'b0;
        //end


        for (i = 0; i < 50; i = i + 1) begin
            for (j = 0; j < 2; j = j + 1) begin
                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b1;
                end

                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b0;
                end

                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b0;
                    m_axis_tready <= 1'b0;
                end
                
                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b1;
                end

                #(4 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b0;
                end

                //#(1 * C_CLK_PERIOD) begin
                //    s_axis_tvalid <= 1'b1;
                //    s_axis_tlast <= 1'b0;
                //end
            end
            for (i = 0; i < 18; i = i + 1) begin
                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b1;
                end

                //#(1 * C_CLK_PERIOD) begin
                //    s_axis_tvalid <= 1'b1;
                //    s_axis_tlast <= 1'b0;
                //end
            end
            #(1 * C_CLK_PERIOD) begin
                s_axis_tvalid <= 1'b1;
            end

            //#(1 * C_CLK_PERIOD) begin
            //s_axis_tvalid <= 1'b1;
            //s_axis_tlast  <= 1'b1;
            //end

            #(1 * C_CLK_PERIOD) begin
                s_axis_tvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (~resetn) begin
            word_counter <= 0;
        end
        if (s_roce_payload_axis_tvalid && s_roce_payload_axis_tready )begin
            if ((word_counter+8+28 <= s_udp_length)) begin
                word_counter <= word_counter + 64;
                random_value <= $random;
            end
        end else if (word_counter+8+28 >= s_udp_length) begin
            word_counter <= 0;
            random_value <= $random;
        end
    end

    assign s_roce_payload_axis_tdata[63:0] = word_counter;
    assign s_roce_payload_axis_tdata[255:64]  = 196'h0;
    assign s_roce_payload_axis_tdata[287:256] = 32'h02230223;
    assign s_roce_payload_axis_tdata[319:288] = 32'hF224F224;
    assign s_roce_payload_axis_tdata[479:320] = 160'h0;
    assign s_roce_payload_axis_tdata[511:480] = random_value;

endmodule
    
    
    