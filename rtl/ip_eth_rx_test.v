/*

Copyright (c) 2014-2020 Alex Forencich

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
* IP ethernet frame receiver (Ethernet frame in, IP frame out)
 */
module ip_eth_rx_test #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                  clk,
    input  wire                  rst,

     /*
     * Ethernet frame input
     */
     input  wire                  s_eth_hdr_valid,
     output wire                  s_eth_hdr_ready,
     input  wire [47:0]           s_eth_dest_mac,
     input  wire [47:0]           s_eth_src_mac,
     input  wire [15:0]           s_eth_type,
     input  wire [DATA_WIDTH-1:0] s_eth_payload_axis_tdata,
     input  wire [KEEP_WIDTH-1:0] s_eth_payload_axis_tkeep,
     input  wire                  s_eth_payload_axis_tvalid,
     output wire                  s_eth_payload_axis_tready,
     input  wire                  s_eth_payload_axis_tlast,
     input  wire                  s_eth_payload_axis_tuser,
 
     /*
      * IP frame output
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
     output wire        busy,
     output wire        error_header_early_termination,
     output wire        error_payload_early_termination,
     output wire        error_invalid_header,
     output wire        error_invalid_checksum
);

parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

parameter HDR_SIZE = 20;

parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

parameter OFFSET = HDR_SIZE % BYTE_LANES;

// bus width assertions
initial begin
    if (BYTE_LANES * 8 != DATA_WIDTH) begin
        $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

/*

IP Frame

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

This module receives an Ethernet frame with header fields in parallel and
payload on an AXI stream interface, decodes and strips the IP header fields,
then produces the header fields in parallel along with the IP payload in a
separate AXI stream.

*/

reg read_ip_header_reg = 1'b1, read_ip_header_next;
reg read_ip_payload_reg = 1'b0, read_ip_payload_next;
reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

// datapath control signals
reg store_eth_hdr;

reg flush_save;
reg transfer_in_save;

reg s_eth_hdr_ready_reg = 1'b0, s_eth_hdr_ready_next;
reg s_eth_payload_axis_tready_reg = 1'b0, s_eth_payload_axis_tready_next;

reg [15:0] word_count_reg = 16'd0, word_count_next;

reg m_ip_hdr_valid_reg = 1'b0, m_ip_hdr_valid_next;
reg [47:0] m_eth_dest_mac_reg = 48'd0, m_eth_dest_mac_next;
reg [47:0] m_eth_src_mac_reg = 48'd0, m_eth_src_mac_next;
reg [15:0] m_eth_type_reg = 16'd0, m_eth_type_next;
reg [3:0]  m_ip_version_reg = 4'd0, m_ip_version_next;
reg [3:0]  m_ip_ihl_reg = 4'd0, m_ip_ihl_next;
reg [5:0]  m_ip_dscp_reg = 6'd0, m_ip_dscp_next;
reg [1:0]  m_ip_ecn_reg = 2'd0, m_ip_ecn_next;
reg [15:0] m_ip_length_reg = 16'd0, m_ip_length_next;
reg [15:0] m_ip_identification_reg = 16'd0, m_ip_identification_next;
reg [2:0]  m_ip_flags_reg = 3'd0, m_ip_flags_next;
reg [12:0] m_ip_fragment_offset_reg = 13'd0, m_ip_fragment_offset_next;
reg [7:0]  m_ip_ttl_reg = 8'd0, m_ip_ttl_next;
reg [7:0]  m_ip_protocol_reg = 8'd0, m_ip_protocol_next;
reg [15:0] m_ip_header_checksum_reg = 16'd0, m_ip_header_checksum_next;
reg [31:0] m_ip_source_ip_reg = 32'd0, m_ip_source_ip_next;
reg [31:0] m_ip_dest_ip_reg = 32'd0, m_ip_dest_ip_next;

reg busy_reg = 1'b0;
reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;
reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;
reg error_invalid_header_reg = 1'b0, error_invalid_header_next;
reg error_invalid_checksum_reg = 1'b0, error_invalid_checksum_next;

reg [DATA_WIDTH-1:0] save_eth_payload_axis_tdata_reg = 64'd0;
reg [KEEP_WIDTH-1:0] save_eth_payload_axis_tkeep_reg = 8'd0;
reg save_eth_payload_axis_tlast_reg = 1'b0;
reg save_eth_payload_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] shift_eth_payload_axis_tdata;
reg [KEEP_WIDTH-1:0] shift_eth_payload_axis_tkeep;
reg shift_eth_payload_axis_tvalid;
reg shift_eth_payload_axis_tlast;
reg shift_eth_payload_axis_tuser;
reg shift_eth_payload_axis_input_tready;
reg shift_eth_payload_axis_extra_cycle_reg = 1'b0;

// internal datapath
reg [DATA_WIDTH-1:0] m_ip_payload_axis_tdata_int;
reg [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep_int;
reg                  m_ip_payload_axis_tvalid_int;
reg                  m_ip_payload_axis_tready_int_reg = 1'b0;
reg                  m_ip_payload_axis_tlast_int;
reg                  m_ip_payload_axis_tuser_int;
wire                 m_ip_payload_axis_tready_int_early;

assign s_eth_hdr_ready = s_eth_hdr_ready_reg;
assign s_eth_payload_axis_tready = s_eth_payload_axis_tready_reg;

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

assign busy = busy_reg;
assign error_header_early_termination = error_header_early_termination_reg;
assign error_payload_early_termination = error_payload_early_termination_reg;
assign error_invalid_header = error_invalid_header_reg;
assign error_invalid_checksum = error_invalid_checksum_reg;

always @* begin
    if (OFFSET == 0) begin
        // passthrough if no overlap
        shift_eth_payload_axis_tdata  = s_eth_payload_axis_tdata;
        shift_eth_payload_axis_tkeep  = s_eth_payload_axis_tkeep;
        shift_eth_payload_axis_tvalid = s_eth_payload_axis_tvalid;
        shift_eth_payload_axis_tlast  = s_eth_payload_axis_tlast;
        shift_eth_payload_axis_tuser  = s_eth_payload_axis_tuser;
        shift_eth_payload_axis_input_tready = 1'b1;
    end else if (shift_eth_payload_axis_extra_cycle_reg) begin
        shift_eth_payload_axis_tdata = {s_eth_payload_axis_tdata, save_eth_payload_axis_tdata_reg} >> (OFFSET*8);
        shift_eth_payload_axis_tkeep = {{KEEP_WIDTH{1'b0}}, save_eth_payload_axis_tkeep_reg} >> OFFSET;
        shift_eth_payload_axis_tvalid = 1'b1;
        shift_eth_payload_axis_tlast = save_eth_payload_axis_tlast_reg;
        shift_eth_payload_axis_tuser = save_eth_payload_axis_tuser_reg;
        shift_eth_payload_axis_input_tready = flush_save;
    end else begin
        shift_eth_payload_axis_tdata = {s_eth_payload_axis_tdata, save_eth_payload_axis_tdata_reg} >> (OFFSET*8);
        shift_eth_payload_axis_tkeep = {s_eth_payload_axis_tkeep, save_eth_payload_axis_tkeep_reg} >> OFFSET;
        shift_eth_payload_axis_tvalid = s_eth_payload_axis_tvalid;
        shift_eth_payload_axis_tlast = (s_eth_payload_axis_tlast && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
        shift_eth_payload_axis_tuser = (s_eth_payload_axis_tuser && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
        shift_eth_payload_axis_input_tready = !(s_eth_payload_axis_tlast && s_eth_payload_axis_tready && s_eth_payload_axis_tvalid);
    end
end

always @* begin
    read_ip_header_next = read_ip_header_reg;
    read_ip_payload_next = read_ip_payload_reg;
    ptr_next = ptr_reg;

    word_count_next = word_count_reg;

    m_ip_hdr_valid_next = m_ip_hdr_valid_reg && !m_ip_hdr_ready;

    // TODO check this shit
    s_eth_hdr_ready_next = !m_ip_hdr_valid_next;
    store_eth_hdr = 1'b0;

    s_eth_payload_axis_tready_next = m_ip_payload_axis_tready_int_early && shift_eth_payload_axis_input_tready && (!m_ip_hdr_valid || m_ip_hdr_ready);

    flush_save = 1'b0;
    transfer_in_save = 1'b0;

    if (s_eth_hdr_ready && s_eth_hdr_valid) begin
        s_eth_hdr_ready_next = 1'b0;
        s_eth_payload_axis_tready_next = 1'b1;
        store_eth_hdr = 1'b1;
    end

    m_eth_dest_mac_next = m_eth_dest_mac_reg;
    m_eth_src_mac_next = m_eth_src_mac_reg;
    m_eth_type_next = m_eth_type_reg;
    m_ip_version_next = m_ip_version_reg;
    m_ip_ihl_next = m_ip_ihl_reg;
    m_ip_dscp_next = m_ip_dscp_reg;
    m_ip_ecn_next = m_ip_ecn_reg;
    m_ip_length_next = m_ip_length_reg;
    m_ip_identification_next = m_ip_identification_reg;
    m_ip_flags_next = m_ip_flags_reg;
    m_ip_fragment_offset_next = m_ip_fragment_offset_reg;
    m_ip_ttl_next = m_ip_ttl_reg;
    m_ip_protocol_next = m_ip_protocol_reg;
    m_ip_header_checksum_next = m_ip_header_checksum_reg;
    m_ip_source_ip_next = m_ip_source_ip_reg;
    m_ip_dest_ip_next = m_ip_dest_ip_reg;

    error_header_early_termination_next = 1'b0;
    error_payload_early_termination_next = 1'b0;
    error_invalid_header_next = 1'b0;
    error_invalid_checksum_next = 1'b0;

    m_ip_payload_axis_tdata_int = shift_eth_payload_axis_tdata;
    m_ip_payload_axis_tkeep_int = shift_eth_payload_axis_tkeep;
    m_ip_payload_axis_tvalid_int = 1'b0;
    m_ip_payload_axis_tlast_int = shift_eth_payload_axis_tlast;
    m_ip_payload_axis_tuser_int = shift_eth_payload_axis_tuser;

    if ((s_eth_payload_axis_tready && s_eth_payload_axis_tvalid) || (m_ip_payload_axis_tready_int_reg && shift_eth_payload_axis_extra_cycle_reg)) begin
        transfer_in_save = 1'b1;

        if (read_ip_header_reg) begin
            // word transfer in - store it
            ptr_next = ptr_reg + 1; 

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_eth_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_eth_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end
            
            `_HEADER_FIELD_(0,  {m_ip_version_next, m_ip_ihl_next}) 
            `_HEADER_FIELD_(1,  {m_ip_dscp_next, m_ip_ecn_next})
            `_HEADER_FIELD_(2,  m_ip_length_next[1*8 +: 8])
            `_HEADER_FIELD_(3,  m_ip_length_next[0*8 +: 8])
            `_HEADER_FIELD_(4,  m_ip_identification_next[1*8 +: 8])
            `_HEADER_FIELD_(5,  m_ip_identification_next[0*8 +: 8])
            `_HEADER_FIELD_(6,  {m_ip_flags_next, m_ip_fragment_offset_next[1*8 +: 5]})
            `_HEADER_FIELD_(7,  m_ip_fragment_offset_next[0*8 +: 8])
            `_HEADER_FIELD_(8,  m_ip_ttl_next)
            `_HEADER_FIELD_(9,  m_ip_protocol_next)
            `_HEADER_FIELD_(10, m_ip_header_checksum_next[1*8 +: 8])
            `_HEADER_FIELD_(11, m_ip_header_checksum_next[0*8 +: 8])
            `_HEADER_FIELD_(12, m_ip_source_ip_next[3*8 +: 8])
            `_HEADER_FIELD_(13, m_ip_source_ip_next[2*8 +: 8])
            `_HEADER_FIELD_(14, m_ip_source_ip_next[1*8 +: 8])
            `_HEADER_FIELD_(15, m_ip_source_ip_next[0*8 +: 8])
            `_HEADER_FIELD_(16, m_ip_dest_ip_next[3*8 +: 8])
            `_HEADER_FIELD_(17, m_ip_dest_ip_next[2*8 +: 8])
            `_HEADER_FIELD_(18, m_ip_dest_ip_next[1*8 +: 8])
            `_HEADER_FIELD_(19, m_ip_dest_ip_next[0*8 +: 8])

            `_HEADER_FIELD_(2,  word_count_next[1*8 +: 8])
            `_HEADER_FIELD_(3,  word_count_next[0*8 +: 8])

            if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES && (!KEEP_ENABLE || s_eth_payload_axis_tkeep[(HDR_SIZE-1)%BYTE_LANES])) begin
                if (!shift_eth_payload_axis_tlast) begin
                    m_ip_hdr_valid_next = 1'b1;
                    read_ip_header_next = 1'b0;
                    read_ip_payload_next = 1'b1;
                end
            end

            `undef _HEADER_FIELD_
        end

        if (read_ip_payload_reg) begin
            // transfer payload
            m_ip_payload_axis_tdata_int = shift_eth_payload_axis_tdata;
            m_ip_payload_axis_tkeep_int = shift_eth_payload_axis_tkeep;
            m_ip_payload_axis_tvalid_int = 1'b1;
            m_ip_payload_axis_tlast_int = shift_eth_payload_axis_tlast;
            m_ip_payload_axis_tuser_int = shift_eth_payload_axis_tuser;

            word_count_next = word_count_reg - DATA_WIDTH/8;
        end

        if (s_eth_payload_axis_tvalid) begin
            if (read_ip_payload_reg) begin
                if (m_ip_version_reg != 4'd4 || m_ip_ihl_reg != 4'd5) begin
                    error_invalid_header_next = 1'b1;
                    //s_eth_payload_axis_tready_next = shift_eth_payload_s_tready;
                end else begin
                    //s_eth_payload_axis_tready_next = m_ip_payload_axis_tready_int_early && shift_eth_payload_s_tready;
                end
            end
        end

        // TODO Header checksum check haha
        error_invalid_checksum_next = 1'b0;

        if (shift_eth_payload_axis_tlast) begin
            if (read_ip_header_next) begin
                // don't have the whole header
                error_header_early_termination_next = 1'b1;
            end
            if (read_ip_payload_next) begin
                if (word_count_reg >= DATA_WIDTH/4) begin // 2 times the data width in bytes
                    error_payload_early_termination_next = 1'b1;
                end
            end

            flush_save = 1'b1;
            ptr_next = 1'b0;
            read_ip_header_next = 1'b1;
            read_ip_payload_next = 1'b0;
        end
    end
end

always @(posedge clk) begin
    read_ip_header_reg <= read_ip_header_next;
    read_ip_payload_reg <= read_ip_payload_next;
    ptr_reg <= ptr_next;

    word_count_reg <= word_count_next;

    s_eth_hdr_ready_reg <= s_eth_hdr_ready_next;

    s_eth_payload_axis_tready_reg <= s_eth_payload_axis_tready_next;

    m_ip_hdr_valid_reg <= m_ip_hdr_valid_next;
    if (store_eth_hdr) begin
        m_eth_dest_mac_reg <= s_eth_dest_mac;
        m_eth_src_mac_reg <= s_eth_src_mac;
        m_eth_type_reg <= s_eth_type;
    end
    
    m_ip_version_reg         <=  m_ip_version_next;
    m_ip_ihl_reg             <= m_ip_ihl_next;
    m_ip_dscp_reg            <= m_ip_dscp_next;
    m_ip_ecn_reg             <= m_ip_ecn_next;
    m_ip_length_reg          <= m_ip_length_next;
    m_ip_identification_reg  <= m_ip_identification_next;
    m_ip_flags_reg           <= m_ip_flags_next;
    m_ip_fragment_offset_reg <= m_ip_fragment_offset_next;
    m_ip_ttl_reg             <= m_ip_ttl_next;
    m_ip_protocol_reg        <= m_ip_protocol_next;
    m_ip_header_checksum_reg <= m_ip_header_checksum_next;
    m_ip_source_ip_reg       <= m_ip_source_ip_next;
    m_ip_dest_ip_reg         <= m_ip_dest_ip_next;

    error_header_early_termination_reg  <= error_header_early_termination_next;
    error_payload_early_termination_reg <= error_payload_early_termination_next;
    error_invalid_header_reg            <= error_invalid_header_next;
    error_invalid_checksum_reg          <= error_invalid_checksum_next;

    busy_reg <= (read_ip_payload_next || ptr_next != 0);

    if (transfer_in_save) begin
        save_eth_payload_axis_tdata_reg <= s_eth_payload_axis_tdata;
        save_eth_payload_axis_tkeep_reg <= s_eth_payload_axis_tkeep;
        save_eth_payload_axis_tuser_reg <= s_eth_payload_axis_tuser;
    end

    if (flush_save) begin
        save_eth_payload_axis_tlast_reg <= 1'b0;
        shift_eth_payload_axis_extra_cycle_reg <= 1'b0;
    end else if (transfer_in_save) begin
        save_eth_payload_axis_tlast_reg <= s_eth_payload_axis_tlast;
        shift_eth_payload_axis_extra_cycle_reg <= OFFSET ? s_eth_payload_axis_tlast && ((s_eth_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) != 0) : 1'b0;
    end
    

    if (rst) begin
        read_ip_header_reg <= 1'b1;
        read_ip_payload_reg <= 1'b0;
        ptr_reg <= 0;
        word_count_reg <= 16'd0;
        s_eth_payload_axis_tready_reg <= 1'b0;
        m_ip_hdr_valid_reg <= 1'b0;
        save_eth_payload_axis_tlast_reg <= 1'b0;
        shift_eth_payload_axis_extra_cycle_reg <= 1'b0;
        busy_reg <= 1'b0;
        error_header_early_termination_reg  <= 1'b0;
        error_payload_early_termination_reg <= 1'b0;
        error_invalid_header_reg            <= 1'b0;
        error_invalid_checksum_reg          <= 1'b0;
    end
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_ip_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  m_ip_payload_axis_tvalid_reg = 1'b0, m_ip_payload_axis_tvalid_next;
reg                  m_ip_payload_axis_tlast_reg = 1'b0;
reg                  m_ip_payload_axis_tuser_reg = 1'b0;

reg [DATA_WIDTH-1:0] temp_m_ip_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_ip_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
reg                  temp_m_ip_payload_axis_tvalid_reg = 1'b0, temp_m_ip_payload_axis_tvalid_next;
reg                  temp_m_ip_payload_axis_tlast_reg = 1'b0;
reg                  temp_m_ip_payload_axis_tuser_reg = 1'b0;

// datapath control
reg store_ip_payload_int_to_output;
reg store_ip_payload_int_to_temp;
reg store_ip_payload_axis_temp_to_output;

assign m_ip_payload_axis_tdata = m_ip_payload_axis_tdata_reg;
assign m_ip_payload_axis_tkeep = KEEP_ENABLE ? m_ip_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_ip_payload_axis_tvalid = m_ip_payload_axis_tvalid_reg;
assign m_ip_payload_axis_tlast = m_ip_payload_axis_tlast_reg;
assign m_ip_payload_axis_tuser = m_ip_payload_axis_tuser_reg;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_ip_payload_axis_tready_int_early = m_ip_payload_axis_tready || (!temp_m_ip_payload_axis_tvalid_reg && !m_ip_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_reg;
    temp_m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;

    store_ip_payload_int_to_output = 1'b0;
    store_ip_payload_int_to_temp = 1'b0;
    store_ip_payload_axis_temp_to_output = 1'b0;
    
    if (m_ip_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_ip_payload_axis_tready || !m_ip_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_ip_payload_axis_tvalid_next = m_ip_payload_axis_tvalid_int;
            store_ip_payload_int_to_temp = 1'b1;
        end
    end else if (m_ip_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_ip_payload_axis_tvalid_next = temp_m_ip_payload_axis_tvalid_reg;
        temp_m_ip_payload_axis_tvalid_next = 1'b0;
        store_ip_payload_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_ip_payload_axis_tvalid_reg <= m_ip_payload_axis_tvalid_next;
    m_ip_payload_axis_tready_int_reg <= m_ip_payload_axis_tready_int_early;
    temp_m_ip_payload_axis_tvalid_reg <= temp_m_ip_payload_axis_tvalid_next;

    // datapath
    if (store_ip_payload_int_to_output) begin
        m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        m_ip_payload_axis_tkeep_reg <= m_ip_payload_axis_tkeep_int;
        m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end else if (store_ip_payload_axis_temp_to_output) begin
        m_ip_payload_axis_tdata_reg <= temp_m_ip_payload_axis_tdata_reg;
        m_ip_payload_axis_tkeep_reg <= temp_m_ip_payload_axis_tkeep_reg;
        m_ip_payload_axis_tlast_reg <= temp_m_ip_payload_axis_tlast_reg;
        m_ip_payload_axis_tuser_reg <= temp_m_ip_payload_axis_tuser_reg;
    end

    if (store_ip_payload_int_to_temp) begin
        temp_m_ip_payload_axis_tdata_reg <= m_ip_payload_axis_tdata_int;
        temp_m_ip_payload_axis_tkeep_reg <= m_ip_payload_axis_tkeep_int;
        temp_m_ip_payload_axis_tlast_reg <= m_ip_payload_axis_tlast_int;
        temp_m_ip_payload_axis_tuser_reg <= m_ip_payload_axis_tuser_int;
    end

    if (rst) begin
        m_ip_payload_axis_tvalid_reg <= 1'b0;
        m_ip_payload_axis_tready_int_reg <= 1'b0;
        temp_m_ip_payload_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
