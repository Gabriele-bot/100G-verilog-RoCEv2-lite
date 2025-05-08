/*

Copyright (c) 2014-2018 Gabriele Bortolato

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * IPv4 block, ethernet frame interface (64 bit datapath)
 */
module icmp_echo_reply #(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // Checksum parameters
    parameter CHECKSUM_PAYLOAD_FIFO_DEPTH = 256,
    parameter CHECKSUM_HEADER_FIFO_DEPTH  = 8
) (
    input wire clk,
    input wire rst,

    /*
    * IP frame input
    */
    input  wire                  s_ip_hdr_valid,
    output wire                  s_ip_hdr_ready,
    input  wire [47:0]           s_eth_dest_mac,
    input  wire [47:0]           s_eth_src_mac,
    input  wire [15:0]           s_eth_type,
    input  wire [3:0]            s_ip_version,
    input  wire [3:0]            s_ip_ihl,
    input  wire [5:0]            s_ip_dscp,
    input  wire [1:0]            s_ip_ecn,
    input  wire [15:0]           s_ip_length,
    input  wire [15:0]           s_ip_identification,
    input  wire [2:0]            s_ip_flags,
    input  wire [12:0]           s_ip_fragment_offset,
    input  wire [7:0]            s_ip_ttl,
    input  wire [7:0]            s_ip_protocol,
    input  wire [15:0]           s_ip_header_checksum,
    input  wire [31:0]           s_ip_source_ip,
    input  wire [31:0]           s_ip_dest_ip,
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
    output wire [47:0]           m_eth_dest_mac,
    output wire [47:0]           m_eth_src_mac,
    output wire [15:0]           m_eth_type,
    output wire [ 3:0]           m_ip_version,
    output wire [ 3:0]           m_ip_ihl,
    output wire [ 5:0]           m_ip_dscp,
    output wire [ 1:0]           m_ip_ecn,
    output wire [15:0]           m_ip_length,
    output wire [15:0]           m_ip_identification,
    output wire [ 2:0]           m_ip_flags,
    output wire [12:0]           m_ip_fragment_offset,
    output wire [ 7:0]           m_ip_ttl,
    output wire [ 7:0]           m_ip_protocol,
    output wire [15:0]           m_ip_header_checksum,
    output wire [31:0]           m_ip_source_ip,
    output wire [31:0]           m_ip_dest_ip,
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

    // ICMP frame connections
    wire rx_icmp_hdr_valid;
    wire rx_icmp_hdr_ready;
    wire [47:0] rx_icmp_eth_dest_mac;
    wire [47:0] rx_icmp_eth_src_mac;
    wire [15:0] rx_icmp_eth_type;
    wire [3:0]  rx_icmp_ip_version;
    wire [3:0]  rx_icmp_ip_ihl;
    wire [5:0]  rx_icmp_ip_dscp;
    wire [1:0]  rx_icmp_ip_ecn;
    wire [15:0] rx_icmp_ip_length;
    wire [15:0] rx_icmp_ip_identification;
    wire [2:0]  rx_icmp_ip_flags;
    wire [12:0] rx_icmp_ip_fragment_offset;
    wire [7:0]  rx_icmp_ip_ttl;
    wire [7:0]  rx_icmp_ip_protocol;
    wire [15:0] rx_icmp_ip_header_checksum;
    wire [31:0] rx_icmp_ip_source_ip;
    wire [31:0] rx_icmp_ip_dest_ip;
    wire [7:0]  rx_icmp_type;
    wire [7:0]  rx_icmp_code;
    wire [15:0] rx_icmp_checksum;
    wire [31:0] rx_icmp_roh;
    wire [DATA_WIDTH-1:0] rx_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0]  rx_icmp_payload_axis_tkeep;
    wire rx_icmp_payload_axis_tvalid;
    wire rx_icmp_payload_axis_tready;
    wire rx_icmp_payload_axis_tlast;
    wire rx_icmp_payload_axis_tuser;

    wire tx_icmp_hdr_valid;
    wire tx_icmp_hdr_ready;
    wire [5:0]  tx_icmp_ip_dscp;
    wire [1:0]  tx_icmp_ip_ecn;
    wire [15:0] tx_icmp_ip_length;
    wire [15:0] tx_icmp_ip_identification;
    wire [2:0]  tx_icmp_ip_flags;
    wire [12:0] tx_icmp_ip_fragment_offset;
    wire [7:0]  tx_icmp_ip_ttl;
    wire [31:0] tx_icmp_ip_source_ip;
    wire [31:0] tx_icmp_ip_dest_ip;
    wire [7:0]  tx_icmp_type;
    wire [7:0]  tx_icmp_code;
    wire [15:0] tx_icmp_checksum;
    wire [31:0] tx_icmp_roh;
    wire [DATA_WIDTH-1:0] tx_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] tx_icmp_payload_axis_tkeep;
    wire tx_icmp_payload_axis_tvalid;
    wire tx_icmp_payload_axis_tready;
    wire tx_icmp_payload_axis_tlast;
    wire tx_icmp_payload_axis_tuser;

    wire tx_post_checksum_icmp_hdr_valid;
    wire tx_post_checksum_icmp_hdr_ready;
    wire [5:0]  tx_post_checksum_icmp_ip_dscp;
    wire [1:0]  tx_post_checksum_icmp_ip_ecn;
    wire [15:0] tx_post_checksum_icmp_ip_length;
    wire [15:0] tx_post_checksum_icmp_ip_identification;
    wire [2:0]  tx_post_checksum_icmp_ip_flags;
    wire [12:0] tx_post_checksum_icmp_ip_fragment_offset;
    wire [7:0]  tx_post_checksum_icmp_ip_ttl;
    wire [31:0] tx_post_checksum_icmp_ip_source_ip;
    wire [31:0] tx_post_checksum_icmp_ip_dest_ip;
    wire [7:0]  tx_post_checksum_icmp_type;
    wire [7:0]  tx_post_checksum_icmp_code;
    wire [15:0] tx_post_checksum_icmp_checksum;
    wire [31:0] tx_post_checksum_icmp_roh;
    wire [DATA_WIDTH-1:0] tx_post_checksum_icmp_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] tx_post_checksum_icmp_payload_axis_tkeep;
    wire tx_post_checksum_icmp_payload_axis_tvalid;
    wire tx_post_checksum_icmp_payload_axis_tready;
    wire tx_post_checksum_icmp_payload_axis_tlast;
    wire tx_post_checksum_icmp_payload_axis_tuser;

    wire [DATA_WIDTH-1:0] tx_pipeline_ip_payload_axis_tdata;
    wire [KEEP_WIDTH-1:0] tx_pipeline_ip_payload_axis_tkeep;
    wire                  tx_pipeline_ip_payload_axis_tvalid;
    wire                  tx_pipeline_ip_payload_axis_tready;
    wire                  tx_pipeline_ip_payload_axis_tlast;
    wire                  tx_pipeline_ip_payload_axis_tuser;

    // Dirty Hack, need to compute the real chack sum
    wire [16:0] temp_cecksum;


    // ICMP Echo Reply when ICMP Echo Request and dest IP equal local IP
    wire match_cond = (rx_icmp_type == 8'h08) & (rx_icmp_code == 8'h00) & (rx_icmp_ip_dest_ip == local_ip); 
    wire no_match = !match_cond;

    reg match_cond_reg = 0;
    reg no_match_reg = 0;

    always @(posedge clk) begin
        if (rst) begin
            match_cond_reg <= 0;
            no_match_reg <= 0;
        end else begin
            if (rx_icmp_payload_axis_tvalid) begin
                if ((!match_cond_reg && !no_match_reg) ||
                    (rx_icmp_payload_axis_tvalid && rx_icmp_payload_axis_tready && rx_icmp_payload_axis_tlast)) begin
                    match_cond_reg <= match_cond;
                    no_match_reg <= no_match;
                end
            end else begin
                match_cond_reg <= 0;
                no_match_reg <= 0;
            end
        end
    end

    assign tx_icmp_hdr_valid = rx_icmp_hdr_valid && match_cond;
    assign rx_icmp_hdr_ready = (tx_icmp_hdr_ready && match_cond) || no_match;
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
    assign tx_icmp_roh= rx_icmp_roh;

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
        .s_eth_dest_mac(0),
        .s_eth_src_mac(0),
        .s_eth_type(0),
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
        .m_eth_dest_mac(),
        .m_eth_src_mac(),
        .m_eth_type(),
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
      .ADDER_STEPS(max(4, (2**$clog2(DATA_WIDTH/64)))),
      .PAYLOAD_FIFO_DEPTH(CHECKSUM_PAYLOAD_FIFO_DEPTH),
      .HEADER_FIFO_DEPTH (CHECKSUM_HEADER_FIFO_DEPTH)
      ) icmp_checksum_gen_test_inst (
      .clk(clk),
      .rst(rst),
      // ICMP frame input
      .s_icmp_hdr_valid(tx_icmp_hdr_valid),
      .s_icmp_hdr_ready(tx_icmp_hdr_ready),
      .s_eth_dest_mac(0),
      .s_eth_src_mac(0),
      .s_eth_type(0),
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
      .m_eth_dest_mac(),
      .m_eth_src_mac(),
      .m_eth_type(),
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

    icmp_ip_tx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) icmp_ip_tx_inst (
        .clk(clk),
        .rst(rst),
        // ICMP frame input
        .s_icmp_hdr_valid(tx_post_checksum_icmp_hdr_valid),
        .s_icmp_hdr_ready(tx_post_checksum_icmp_hdr_ready),
        .s_eth_dest_mac(0),
        .s_eth_src_mac(0),
        .s_eth_type(0),
        .s_ip_version(4'h4),
        .s_ip_ihl(4'h5),
        .s_ip_dscp(tx_post_checksum_icmp_ip_dscp),
        .s_ip_ecn(tx_post_checksum_icmp_ip_ecn),
        .s_ip_length(tx_post_checksum_icmp_ip_length),
        .s_ip_identification(tx_post_checksum_icmp_ip_identification),
        .s_ip_flags(tx_post_checksum_icmp_ip_flags),
        .s_ip_fragment_offset(tx_post_checksum_icmp_ip_fragment_offset),
        .s_ip_ttl(tx_post_checksum_icmp_ip_ttl),
        .s_ip_protocol(8'h01),
        .s_ip_header_checksum(0),
        .s_ip_source_ip(tx_post_checksum_icmp_ip_source_ip),
        .s_ip_dest_ip(tx_post_checksum_icmp_ip_dest_ip),
        .s_icmp_type(tx_post_checksum_icmp_type),
        .s_icmp_code(tx_post_checksum_icmp_code),
        .s_icmp_checksum(tx_post_checksum_icmp_checksum),
        .s_icmp_roh(tx_post_checksum_icmp_roh),
        .s_icmp_payload_axis_tdata( tx_post_checksum_icmp_payload_axis_tdata),
        .s_icmp_payload_axis_tkeep( tx_post_checksum_icmp_payload_axis_tkeep),
        .s_icmp_payload_axis_tvalid(tx_post_checksum_icmp_payload_axis_tvalid),
        .s_icmp_payload_axis_tready(tx_post_checksum_icmp_payload_axis_tready),
        .s_icmp_payload_axis_tlast( tx_post_checksum_icmp_payload_axis_tlast),
        .s_icmp_payload_axis_tuser( tx_post_checksum_icmp_payload_axis_tuser),
        // IP frame output
        .m_ip_hdr_valid(m_ip_hdr_valid),
        .m_ip_hdr_ready(m_ip_hdr_ready),
        .m_eth_dest_mac(),
        .m_eth_src_mac(),
        .m_eth_type(),
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
        .m_is_roce_packet(m_is_roce_packet),
        .m_ip_payload_axis_tdata( tx_pipeline_ip_payload_axis_tdata),
        .m_ip_payload_axis_tkeep( tx_pipeline_ip_payload_axis_tkeep),
        .m_ip_payload_axis_tvalid(tx_pipeline_ip_payload_axis_tvalid),
        .m_ip_payload_axis_tready(tx_pipeline_ip_payload_axis_tready),
        .m_ip_payload_axis_tlast( tx_pipeline_ip_payload_axis_tlast),
        .m_ip_payload_axis_tuser( tx_pipeline_ip_payload_axis_tuser),
        // Status signals
        .busy(tx_busy)
    );

   assign m_ip_payload_axis_tdata  = tx_pipeline_ip_payload_axis_tdata;
   assign m_ip_payload_axis_tkeep  = tx_pipeline_ip_payload_axis_tkeep; 
   assign m_ip_payload_axis_tvalid = tx_pipeline_ip_payload_axis_tvalid;
   assign tx_pipeline_ip_payload_axis_tready = m_ip_payload_axis_tready;
   assign m_ip_payload_axis_tlast  = tx_pipeline_ip_payload_axis_tlast; 
   assign m_ip_payload_axis_tuser  = tx_pipeline_ip_payload_axis_tuser;


endmodule

`resetall
