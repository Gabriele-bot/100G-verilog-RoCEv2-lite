/*

Copyright (c) 2016-2018 Alex Forencich

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

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * ICMP checksum calculation module
 */
module ip_fifo #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 64,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),

    parameter PAYLOAD_FIFO_DEPTH  = 2048,
    parameter HEADER_FIFO_DEPTH   = 8
)
(
    input  wire        clk,
    input  wire        rst,

    input  wire                  s_ip_hdr_valid,
    output wire                  s_ip_hdr_ready,
    input  wire [47:0]           s_eth_dest_mac,
    input  wire [47:0]           s_eth_src_mac,
    input  wire [15:0]           s_eth_type,
    input  wire [ 3:0]           s_ip_version,
    input  wire [ 3:0]           s_ip_ihl,
    input  wire [ 5:0]           s_ip_dscp,
    input  wire [ 1:0]           s_ip_ecn,
    input  wire [15:0]           s_ip_length,
    input  wire [15:0]           s_ip_identification,
    input  wire [ 2:0]           s_ip_flags,
    input  wire [12:0]           s_ip_fragment_offset,
    input  wire [ 7:0]           s_ip_ttl,
    input  wire [ 7:0]           s_ip_protocol,
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
     * ICMP frame output
     */
    output wire                  m_ip_hdr_valid,
    input  wire                  m_ip_hdr_ready,
    output wire [47:0]           m_eth_dest_mac,
    output wire [47:0]           m_eth_src_mac,
    output wire [15:0]           m_eth_type,
    output wire [3:0]            m_ip_version,
    output wire [3:0]            m_ip_ihl,
    output wire [5:0]            m_ip_dscp,
    output wire [1:0]            m_ip_ecn,
    output wire [15:0]           m_ip_length,
    output wire [15:0]           m_ip_identification,
    output wire [2:0]            m_ip_flags,
    output wire [12:0]           m_ip_fragment_offset,
    output wire [7:0]            m_ip_ttl,
    output wire [7:0]            m_ip_protocol,
    output wire [15:0]           m_ip_header_checksum,
    output wire [31:0]           m_ip_source_ip,
    output wire [31:0]           m_ip_dest_ip,
    output wire [DATA_WIDTH-1:0] m_ip_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep,
    output wire                  m_ip_payload_axis_tvalid,
    input  wire                  m_ip_payload_axis_tready,
    output wire                  m_ip_payload_axis_tlast,
    output wire                  m_ip_payload_axis_tuser,

    /*
     * Status signals
     */
    output wire        busy
);

    /*

ICMP Frame

 Field                       Length
 Destination MAC address     6 octets
 Source MAC address          6 octets
 Ethertype (0x0800)          2 octets
 Version (4)                 4 bits
 IHL (5-15)                  4 bits
 DSCP (0)                    6 bits
 ECN (0)                     2 bits
 length                      2 octets
 identification (0?)         2 octets
 flags (010)                 3 bits
 fragment offset (0)         13 bits
 time to live (64?)          1 octet
 protocol                    1 octet
 header checksum             2 octets
 source IP                   4 octets
 destination IP              4 octets
 options                     (IHL-5)*4 octets

 payload                     length octets

This module receives a icmp frame with header fields in parallel along with the
payload in an AXI stream, combines the header with the payload, passes through
the IP headers, and transmits the complete IP payload on an AXI interface.

*/

    // bus width assertions
    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    initial begin
        if (DATA_WIDTH < 64) begin
            $error("Error: AXIS data with too small, minimum value is 64 bits");
            $finish;
        end
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end

    parameter HEADER_FIFO_ADDR_WIDTH = $clog2(HEADER_FIFO_DEPTH);

    localparam [2:0]
    STATE_IDLE         = 1'd0,
    STATE_WAIT_PAYLOAD = 1'b1;

    reg [0:0] state_reg = STATE_IDLE, state_next;

    // datapath control signals
    reg store_ip_hdr;

    reg [47:0] eth_dest_mac_reg = 48'd0;
    reg [47:0] eth_src_mac_reg = 48'd0;
    reg [15:0] eth_type_reg = 16'd0;
    reg [3:0]  ip_version_reg = 4'd0;
    reg [3:0]  ip_ihl_reg = 4'd0;
    reg [5:0]  ip_dscp_reg = 6'd0;
    reg [1:0]  ip_ecn_reg = 2'd0;
    reg [15:0] ip_length_reg = 16'd0;
    reg [15:0] ip_identification_reg = 16'd0;
    reg [2:0]  ip_flags_reg = 3'd0;
    reg [12:0] ip_fragment_offset_reg = 13'd0;
    reg [7:0]  ip_ttl_reg = 8'd0;
    reg [7:0]  ip_protocol_reg = 8'd0;
    reg [15:0] ip_header_checksum_reg = 16'd0;
    reg [31:0] ip_source_ip_reg = 32'd0;
    reg [31:0] ip_dest_ip_reg = 32'd0;

    reg hdr_valid_reg = 0, hdr_valid_next;

    reg s_ip_hdr_ready_reg = 1'b0, s_ip_hdr_ready_next;
    reg s_ip_payload_axis_tready_reg = 1'b0, s_ip_payload_axis_tready_next;

    reg busy_reg = 1'b0;

    /*
     * icmp Payload FIFO
     */
    wire [DATA_WIDTH-1:0] s_ip_payload_fifo_tdata;
    wire [KEEP_WIDTH-1:0] s_ip_payload_fifo_tkeep;
    wire                  s_ip_payload_fifo_tvalid;
    wire                  s_ip_payload_fifo_tready;
    wire                  s_ip_payload_fifo_tlast;
    wire                  s_ip_payload_fifo_tuser;

    wire [DATA_WIDTH-1:0] m_ip_payload_fifo_tdata;
    wire [KEEP_WIDTH-1:0] m_ip_payload_fifo_tkeep;
    wire                  m_ip_payload_fifo_tvalid;
    wire                  m_ip_payload_fifo_tready;
    wire                  m_ip_payload_fifo_tlast;
    wire                  m_ip_payload_fifo_tuser;

    axis_fifo #(
        .DEPTH(PAYLOAD_FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    )
    payload_fifo (
        .clk(clk),
        .rst(rst),
        // AXI input
        .s_axis_tdata (s_ip_payload_fifo_tdata),
        .s_axis_tkeep (s_ip_payload_fifo_tkeep),
        .s_axis_tvalid(s_ip_payload_fifo_tvalid),
        .s_axis_tready(s_ip_payload_fifo_tready),
        .s_axis_tlast (s_ip_payload_fifo_tlast),
        .s_axis_tid   (0),
        .s_axis_tdest (0),
        .s_axis_tuser (s_ip_payload_fifo_tuser),
        // AXI output
        .m_axis_tdata (m_ip_payload_fifo_tdata),
        .m_axis_tkeep (m_ip_payload_fifo_tkeep),
        .m_axis_tvalid(m_ip_payload_fifo_tvalid),
        .m_axis_tready(m_ip_payload_fifo_tready),
        .m_axis_tlast (m_ip_payload_fifo_tlast),
        .m_axis_tuser (m_ip_payload_fifo_tuser),
        // Status
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

    assign s_ip_payload_fifo_tdata  = s_ip_payload_axis_tdata;
    assign s_ip_payload_fifo_tkeep  = s_ip_payload_axis_tkeep;
    assign s_ip_payload_fifo_tvalid = s_ip_payload_axis_tvalid;
    assign s_ip_payload_axis_tready = s_ip_payload_fifo_tready;
    assign s_ip_payload_fifo_tlast  = s_ip_payload_axis_tlast;
    assign s_ip_payload_fifo_tuser  = s_ip_payload_axis_tuser;

    assign m_ip_payload_axis_tdata  = m_ip_payload_fifo_tdata;
    assign m_ip_payload_axis_tkeep  = m_ip_payload_fifo_tkeep;
    assign m_ip_payload_axis_tvalid = m_ip_payload_fifo_tvalid;
    assign m_ip_payload_fifo_tready = m_ip_payload_axis_tready;
    assign m_ip_payload_axis_tlast  = m_ip_payload_fifo_tlast;
    assign m_ip_payload_axis_tuser  = m_ip_payload_fifo_tuser;

    /*
     * icmp Header FIFO
     */
    reg [HEADER_FIFO_ADDR_WIDTH:0] header_fifo_wr_ptr_reg = {HEADER_FIFO_ADDR_WIDTH+1{1'b0}}, header_fifo_wr_ptr_next;
    reg [HEADER_FIFO_ADDR_WIDTH:0] header_fifo_rd_ptr_reg = {HEADER_FIFO_ADDR_WIDTH+1{1'b0}}, header_fifo_rd_ptr_next;

    reg [47:0] eth_dest_mac_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [47:0] eth_src_mac_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [15:0] eth_type_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [3:0]  ip_version_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [3:0]  ip_ihl_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [5:0]  ip_dscp_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [1:0]  ip_ecn_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [15:0] ip_length_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [15:0] ip_identification_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [2:0]  ip_flags_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [12:0] ip_fragment_offset_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [7:0]  ip_ttl_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [7:0]  ip_protocol_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [15:0] ip_header_checksum_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [31:0] ip_source_ip_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];
    reg [31:0] ip_dest_ip_mem[(2**HEADER_FIFO_ADDR_WIDTH)-1:0];

    reg [47:0] m_eth_dest_mac_reg = 48'd0;
    reg [47:0] m_eth_src_mac_reg = 48'd0;
    reg [15:0] m_eth_type_reg = 16'd0;
    reg [3:0]  m_ip_version_reg = 4'd0;
    reg [3:0]  m_ip_ihl_reg = 4'd0;
    reg [5:0]  m_ip_dscp_reg = 6'd0;
    reg [1:0]  m_ip_ecn_reg = 2'd0;
    reg [15:0] m_ip_length_reg = 16'd0;
    reg [15:0] m_ip_identification_reg = 16'd0;
    reg [2:0]  m_ip_flags_reg = 3'd0;
    reg [12:0] m_ip_fragment_offset_reg = 13'd0;
    reg [7:0]  m_ip_ttl_reg = 8'd0;
    reg [7:0]  m_ip_protocol_reg = 8'd0;
    reg [15:0] m_ip_header_checksum_reg = 16'd0;
    reg [31:0] m_ip_source_ip_reg = 32'd0;
    reg [31:0] m_ip_dest_ip_reg = 32'd0;

    reg m_ip_hdr_valid_reg = 1'b0, m_ip_hdr_valid_next;

    // full when first MSB different but rest same
    wire header_fifo_full = ((header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH] != header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH]) &&
    (header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0] == header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]));
    // empty when pointers match exactly
    wire header_fifo_empty = header_fifo_wr_ptr_reg == header_fifo_rd_ptr_reg;

    // control signals
    reg header_fifo_write;
    reg header_fifo_read;

    wire header_fifo_ready = !header_fifo_full;

    assign m_ip_hdr_valid = m_ip_hdr_valid_reg;

    assign m_eth_dest_mac = m_eth_dest_mac_reg;
    assign m_eth_src_mac = m_eth_src_mac_reg;
    assign m_eth_type = m_eth_type_reg;
    assign m_ip_version = m_ip_version_reg;
    assign m_ip_ihl = m_ip_ihl_reg;
    assign m_ip_dscp = m_ip_dscp_reg;
    assign m_ip_ecn = m_ip_ecn_reg;
    assign m_ip_length = m_ip_length_reg;
    assign m_ip_identification = m_ip_identification_reg;
    assign m_ip_flags = m_ip_flags_reg;
    assign m_ip_fragment_offset = m_ip_fragment_offset_reg;
    assign m_ip_ttl = m_ip_ttl_reg;
    assign m_ip_protocol = m_ip_protocol_reg;
    assign m_ip_header_checksum = m_ip_header_checksum_reg;
    assign m_ip_source_ip = m_ip_source_ip_reg;
    assign m_ip_dest_ip = m_ip_dest_ip_reg;

    // Write logic
    always @* begin
        header_fifo_write = 1'b0;

        header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg;

        if (hdr_valid_reg) begin
            // input data valid
            if (~header_fifo_full) begin
                // not full, perform write
                header_fifo_write = 1'b1;
                header_fifo_wr_ptr_next = header_fifo_wr_ptr_reg + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            header_fifo_wr_ptr_reg <= {HEADER_FIFO_ADDR_WIDTH+1{1'b0}};
        end else begin
            header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_next;
        end

        if (header_fifo_write) begin
            eth_dest_mac_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_dest_mac_reg;
            eth_src_mac_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_src_mac_reg;
            eth_type_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= eth_type_reg;
            ip_version_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_version_reg;
            ip_ihl_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ihl_reg;
            ip_dscp_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_dscp_reg;
            ip_ecn_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ecn_reg;
            ip_length_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_length_reg;
            ip_identification_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_identification_reg;
            ip_flags_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_flags_reg;
            ip_fragment_offset_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_fragment_offset_reg;
            ip_ttl_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_ttl_reg;
            ip_protocol_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_protocol_reg;
            ip_header_checksum_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_header_checksum_reg;
            ip_source_ip_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_source_ip_reg;
            ip_dest_ip_mem[header_fifo_wr_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]] <= ip_dest_ip_reg;
        end
    end

    // Read logic
    always @* begin
        header_fifo_read = 1'b0;

        header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg;

        m_ip_hdr_valid_next = m_ip_hdr_valid_reg;

        if (m_ip_hdr_ready || !m_ip_hdr_valid) begin
            // output data not valid OR currently being transferred
            if (!header_fifo_empty) begin
                // not empty, perform read
                header_fifo_read = 1'b1;
                m_ip_hdr_valid_next = 1'b1;
                header_fifo_rd_ptr_next = header_fifo_rd_ptr_reg + 1;
            end else begin
                // empty, invalidate
                m_ip_hdr_valid_next = 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            header_fifo_rd_ptr_reg <= {HEADER_FIFO_ADDR_WIDTH+1{1'b0}};
            m_ip_hdr_valid_reg <= 1'b0;
        end else begin
            header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_next;
            m_ip_hdr_valid_reg <= m_ip_hdr_valid_next;
        end

        if (header_fifo_read) begin
            m_eth_dest_mac_reg <= eth_dest_mac_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_eth_src_mac_reg <= eth_src_mac_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_eth_type_reg <= eth_type_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_version_reg <= ip_version_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_ihl_reg <= ip_ihl_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_dscp_reg <= ip_dscp_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_ecn_reg <= ip_ecn_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_length_reg <= ip_length_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_identification_reg <= ip_identification_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_flags_reg <= ip_flags_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_fragment_offset_reg <= ip_fragment_offset_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_ttl_reg <= ip_ttl_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_protocol_reg <= ip_protocol_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_header_checksum_reg <= ip_header_checksum_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_source_ip_reg <= ip_source_ip_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
            m_ip_dest_ip_reg <= ip_dest_ip_mem[header_fifo_rd_ptr_reg[HEADER_FIFO_ADDR_WIDTH-1:0]];
        end
    end

    assign s_ip_hdr_ready = s_ip_hdr_ready_reg;

    assign busy = busy_reg;

    always @* begin

        state_next = STATE_IDLE;

        s_ip_hdr_ready_next = 1'b0;
        s_ip_payload_axis_tready_next = 1'b0;

        store_ip_hdr = 1'b0;

        hdr_valid_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state
                s_ip_hdr_ready_next = header_fifo_ready;

                if (s_ip_hdr_ready && s_ip_hdr_valid) begin
                    store_ip_hdr = 1'b1;

                    s_ip_hdr_ready_next = 1'b0;
                    if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid && s_ip_payload_axis_tlast) begin
                        hdr_valid_next = 1;
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_WAIT_PAYLOAD;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_WAIT_PAYLOAD: begin
                if (s_ip_payload_axis_tready && s_ip_payload_axis_tvalid && s_ip_payload_axis_tlast) begin
                    hdr_valid_next = 1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_PAYLOAD;
                end
            end
        endcase


    end

    always @(posedge clk) begin
        if (rst) begin
            s_ip_hdr_ready_reg <= 1'b0;
            s_ip_payload_axis_tready_reg <= 1'b0;
            hdr_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
        end else begin
            s_ip_hdr_ready_reg <= s_ip_hdr_ready_next;
            s_ip_payload_axis_tready_reg <= s_ip_payload_axis_tready_next;

            hdr_valid_reg <= hdr_valid_next;
        end
        // datapath
        if (store_ip_hdr) begin
            eth_dest_mac_reg <= s_eth_dest_mac;
            eth_src_mac_reg <= s_eth_src_mac;
            eth_type_reg <= s_eth_type;
            ip_version_reg <= s_ip_version;
            ip_ihl_reg <= s_ip_ihl;
            ip_dscp_reg <= s_ip_dscp;
            ip_ecn_reg <= s_ip_ecn;
            ip_length_reg <= s_ip_length;
            ip_identification_reg <= s_ip_identification;
            ip_flags_reg <= s_ip_flags;
            ip_fragment_offset_reg <= s_ip_fragment_offset;
            ip_ttl_reg <= s_ip_ttl;
            ip_protocol_reg <= s_ip_protocol;
            ip_header_checksum_reg <= s_ip_header_checksum;
            ip_source_ip_reg <= s_ip_source_ip;
            ip_dest_ip_reg <= s_ip_dest_ip;
        end
    end

endmodule

`resetall
