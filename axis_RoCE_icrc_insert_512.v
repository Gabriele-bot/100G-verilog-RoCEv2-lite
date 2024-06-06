/*

Copyright (c) 2015-2018 Alex Forencich

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
 * AXI4-Stream Ethernet FCS inserter (64 bit datapath)
 */
module axis_RoCE_icrc_insert_512 #
(
    parameter ENABLE_PADDING = 0,
    parameter MIN_FRAME_LENGTH = 32
)
(
    input  wire        clk,
    input  wire        rst,

    /*
     * AXI input
     */
    input  wire [511:0] s_axis_tdata,
    input  wire [63:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    /*
     * AXI output
     */
    output wire [511:0] m_axis_tdata,
    output wire [63:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire        m_axis_tuser,

    /*
     * Status
     */
    output wire        busy
);

    localparam [1:0]
    STATE_IDLE = 2'd0,
    STATE_PAYLOAD = 2'd1,
    STATE_PAD = 2'd2,
    STATE_ICRC = 2'd3;

    reg [1:0] state_reg = STATE_IDLE, state_next;

    // datapath control signals
    reg reset_crc;
    reg update_crc;

    reg [511:0] s_axis_tdata_masked;

    reg [511:0] icrc_s_tdata;
    reg [63:0]  icrc_s_tkeep;

    reg [511:0] icrc_m_tdata_0;
    reg [511:0] icrc_m_tdata_1;
    reg [63:0]  icrc_m_tkeep_0;
    reg [63:0]  icrc_m_tkeep_1;

    reg [15:0] frame_ptr_reg = 16'd0, frame_ptr_next;

    reg [511:0] last_cycle_tdata_reg = 512'd0, last_cycle_tdata_next;
    reg [63:0]  last_cycle_tkeep_reg = 64'd0, last_cycle_tkeep_next;

    reg busy_reg = 1'b0;

    reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

    reg [31:0] crc_state = 32'hDEBB20E3;

    wire [31:0] crc_next0;
    wire [31:0] crc_next1;
    wire [31:0] crc_next2;
    wire [31:0] crc_next3;
    wire [31:0] crc_next4;
    wire [31:0] crc_next5;
    wire [31:0] crc_next6;
    wire [31:0] crc_next7;

    // internal datapath
    reg [511:0] m_axis_tdata_int;
    reg [63:0]  m_axis_tkeep_int;
    reg         m_axis_tvalid_int;
    reg         m_axis_tready_int_reg = 1'b0;
    reg         m_axis_tlast_int;
    reg         m_axis_tuser_int;
    wire        m_axis_tready_int_early;

    reg [31:0] crc_in = 32'hFFFFFFFF;
    wire [31:0] crc_out;

    reg last_frame;
    reg [2:0] last_frame_shreg;

    reg reset_crc_seed;
    reg [2:0] reset_crc_seed_shreg;

    reg [511:0] s_axis_tdata_shreg [2:0];
    reg [63:0] s_axis_tkeep_shreg [2:0];
    reg s_axis_tvalid_shreg [2:0];
    reg s_axis_tready_shreg [2:0];
    reg s_axis_tlast_shreg [2:0];
    reg s_axis_tuser_shreg [2:0];

    reg crc_out_packet_valid;
    wire valid_crc_out;

    assign s_axis_tready = s_axis_tready_reg;

    assign busy = busy_reg;

    CRC32_D512_matrix #(
        .crc_poly(32'h04C11DB7),
        .crc_init(32'hDEBB20E3),
        .reverse_result(1'b0),
        .finxor(32'h00000000)
    ) CRC32_D512_matrix_instance(
        .clk(clk),
        .rst(rst),
        .rst_crc(reset_crc),
        .data_in(s_axis_tdata),
        .keep_in(s_axis_tkeep),
        .valid_in(s_axis_tvalid && s_axis_tready),
        .crcout(crc_out),
        .valid_crc_out(valid_crc_out)
    );

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

    // Mask input data
    integer j;

    always @* begin
        for (j = 0; j < 64; j = j + 1) begin
            s_axis_tdata_masked[j*8 +: 8] = s_axis_tkeep[j] ? s_axis_tdata[j*8 +: 8] : 8'd0;
        end
    end

    // ICRC cycle calculation
    always @* begin
        casez (icrc_s_tkeep)
            64'hzzzzzzzzzzzzzz0F: begin
                icrc_m_tdata_0 = {448'd0, ~crc_out, icrc_s_tdata[31:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h00000000000000FF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzzzzzzz0FF: begin
                icrc_m_tdata_0 = {416'd0, ~crc_out, icrc_s_tdata[63:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h0000000000000FFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzzzzzz0FFF: begin
                icrc_m_tdata_0 = {384'd0, ~crc_out, icrc_s_tdata[95:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h000000000000FFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzzzzz0FFFF: begin
                icrc_m_tdata_0 = {352'd0, ~crc_out, icrc_s_tdata[127:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h00000000000FFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzzzz0FFFFF: begin
                icrc_m_tdata_0 = {320'd0, ~crc_out, icrc_s_tdata[159:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h0000000000FFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzzz0FFFFFF: begin
                icrc_m_tdata_0 = {288'd0, ~crc_out, icrc_s_tdata[191:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h000000000FFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzzz0FFFFFFF: begin
                icrc_m_tdata_0 = {256'd0, ~crc_out, icrc_s_tdata[223:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h00000000FFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzzz0FFFFFFFF: begin
                icrc_m_tdata_0 = {224'd0, ~crc_out, icrc_s_tdata[255:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h0000000FFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzzz0FFFFFFFFF: begin
                icrc_m_tdata_0 = {192'd0, ~crc_out, icrc_s_tdata[287:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h000000FFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzzz0FFFFFFFFFF: begin
                icrc_m_tdata_0 = {160'd0, ~crc_out, icrc_s_tdata[319:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h00000FFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzzz0FFFFFFFFFFF: begin
                icrc_m_tdata_0 = {128'd0, ~crc_out, icrc_s_tdata[351:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h0000FFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzzz0FFFFFFFFFFFF: begin
                icrc_m_tdata_0 = {96'd0, ~crc_out, icrc_s_tdata[383:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h000FFFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hzz0FFFFFFFFFFFFF: begin
                icrc_m_tdata_0 = {64'd0, ~crc_out, icrc_s_tdata[415:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h00FFFFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hz0FFFFFFFFFFFFFF: begin
                icrc_m_tdata_0 = {32'd0, ~crc_out, icrc_s_tdata[447:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'h0FFFFFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'h0FFFFFFFFFFFFFFF: begin
                icrc_m_tdata_0 = {~crc_out, icrc_s_tdata[479:0]};
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'hFFFFFFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h0000000000000000;
            end
            64'hFFFFFFFFFFFFFFFF: begin
                icrc_m_tdata_0 = icrc_s_tdata;
                icrc_m_tdata_1 = {480'd0, ~crc_out};
                icrc_m_tkeep_0 = 64'hFFFFFFFFFFFFFFFF;
                icrc_m_tkeep_1 = 64'h000000000000000F;
            end
            default: begin
                icrc_m_tdata_0 = 512'd0;
                icrc_m_tdata_1 = 512'd0;
                icrc_m_tkeep_0 = 64'd0;
                icrc_m_tkeep_1 = 64'd0;
            end
        endcase
    end

    always @* begin
        state_next = STATE_IDLE;

        reset_crc = 1'b0;
        update_crc = 1'b0;

        frame_ptr_next = frame_ptr_reg;

        last_cycle_tdata_next = last_cycle_tdata_reg;
        last_cycle_tkeep_next = last_cycle_tkeep_reg;

        s_axis_tready_next = 1'b0;

        icrc_s_tdata = 512'd0;
        icrc_s_tkeep = 64'd0;

        m_axis_tdata_int = 512'd0;
        m_axis_tkeep_int = 64'd0;
        m_axis_tvalid_int = 1'b0;
        m_axis_tlast_int = 1'b0;
        m_axis_tuser_int = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state - wait for data
                s_axis_tready_next = m_axis_tready_int_early;
                frame_ptr_next = 16'd0;
                reset_crc = 1'b1;

                //m_axis_tdata_int = s_axis_tdata_masked;
                //m_axis_tkeep_int = s_axis_tkeep;
                //m_axis_tvalid_int = s_axis_tvalid;
                m_axis_tdata_int = s_axis_tdata_shreg[2];
                m_axis_tkeep_int = s_axis_tkeep_shreg[2];
                m_axis_tvalid_int = s_axis_tvalid_shreg[2];
                m_axis_tlast_int = 1'b0;
                m_axis_tuser_int = 1'b0;

                icrc_s_tdata = s_axis_tdata_shreg[2];
                icrc_s_tkeep = s_axis_tkeep_shreg[2];

                if (s_axis_tready_shreg[2] && s_axis_tvalid_shreg[2]) begin
                    reset_crc = 1'b0;
                    update_crc = 1'b1;
                    frame_ptr_next = keep2count(s_axis_tkeep_shreg[2]);
                    if (s_axis_tlast_shreg[2]) begin
                        if (s_axis_tuser_shreg[2]) begin
                            m_axis_tlast_int = 1'b1;
                            m_axis_tuser_int = 1'b1;
                            reset_crc = 1'b1;
                            frame_ptr_next = 16'd0;
                            state_next = STATE_IDLE;
                        end else begin
                            m_axis_tdata_int = icrc_m_tdata_0;
                            last_cycle_tdata_next = icrc_m_tdata_1;
                            m_axis_tkeep_int = icrc_m_tkeep_0;
                            last_cycle_tkeep_next = icrc_m_tkeep_1;

                            reset_crc = 1'b1;

                            if (icrc_m_tkeep_1 == 8'd0) begin
                                m_axis_tlast_int = 1'b1;
                                s_axis_tready_next = m_axis_tready_int_early;
                                frame_ptr_next = 16'd0;
                                state_next = STATE_IDLE;
                            end else begin
                                s_axis_tready_next = 1'b0;
                                state_next = STATE_ICRC;
                            end
                        end
                    end else begin
                        state_next = STATE_PAYLOAD;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_PAYLOAD: begin
                // transfer payload
                s_axis_tready_next = m_axis_tready_int_early;

                m_axis_tdata_int = s_axis_tdata_shreg[2];
                m_axis_tkeep_int = s_axis_tkeep_shreg[2];
                m_axis_tvalid_int = s_axis_tvalid_shreg[2];
                m_axis_tlast_int = 1'b0;
                m_axis_tuser_int = 1'b0;

                icrc_s_tdata = s_axis_tdata_shreg[2];
                icrc_s_tkeep = s_axis_tkeep_shreg[2];

                if (s_axis_tready_shreg[2] && s_axis_tvalid_shreg[2]) begin
                    update_crc = 1'b1;
                    frame_ptr_next = frame_ptr_reg + keep2count(s_axis_tkeep_shreg[2]);
                    if (s_axis_tlast_shreg[2]) begin
                        if (s_axis_tuser_shreg[2]) begin
                            m_axis_tlast_int = 1'b1;
                            m_axis_tuser_int = 1'b1;
                            reset_crc = 1'b1;
                            frame_ptr_next = 16'd0;
                            state_next = STATE_IDLE;
                        end else begin

                            m_axis_tdata_int = icrc_m_tdata_0;
                            last_cycle_tdata_next = icrc_m_tdata_1;
                            m_axis_tkeep_int = icrc_m_tkeep_0;
                            last_cycle_tkeep_next = icrc_m_tkeep_1;

                            reset_crc = 1'b1;

                            if (icrc_m_tkeep_1 == 8'd0) begin
                                m_axis_tlast_int = 1'b1;
                                s_axis_tready_next = m_axis_tready_int_early;
                                frame_ptr_next = 16'd0;
                                state_next = STATE_IDLE;
                            end else begin
                                s_axis_tready_next = 1'b0;
                                state_next = STATE_ICRC;
                            end
                        end

                    end else begin
                        state_next = STATE_PAYLOAD;
                    end
                end else begin
                    state_next = STATE_PAYLOAD;
                end
            end
            STATE_ICRC: begin
                // last cycle
                s_axis_tready_next = 1'b0;

                m_axis_tdata_int = last_cycle_tdata_reg;
                m_axis_tkeep_int = last_cycle_tkeep_reg;
                m_axis_tvalid_int = 1'b1;
                m_axis_tlast_int = 1'b1;
                m_axis_tuser_int = 1'b0;

                if (m_axis_tready_int_reg) begin
                    reset_crc = 1'b1;
                    s_axis_tready_next = m_axis_tready_int_early;
                    frame_ptr_next = 1'b0;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_ICRC;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        s_axis_tdata_shreg[0] <= s_axis_tdata;
        s_axis_tkeep_shreg[0] <= s_axis_tkeep;
        s_axis_tvalid_shreg[0] <= s_axis_tvalid;
        s_axis_tlast_shreg[0] <= s_axis_tlast;
        s_axis_tuser_shreg[0] <= s_axis_tuser;
        s_axis_tready_shreg[0] <= s_axis_tready;

        s_axis_tdata_shreg [1] <= s_axis_tdata_shreg [0];
        s_axis_tkeep_shreg [1] <= s_axis_tkeep_shreg [0];
        s_axis_tvalid_shreg[1] <= s_axis_tvalid_shreg[0];
        s_axis_tlast_shreg [1] <= s_axis_tlast_shreg [0];
        s_axis_tuser_shreg [1] <= s_axis_tuser_shreg [0];
        s_axis_tready_shreg[1] <= s_axis_tready_shreg[0];

        s_axis_tdata_shreg [2] <= s_axis_tdata_shreg [1];
        s_axis_tkeep_shreg [2] <= s_axis_tkeep_shreg [1];
        s_axis_tvalid_shreg[2] <= s_axis_tvalid_shreg[1];
        s_axis_tlast_shreg [2] <= s_axis_tlast_shreg [1];
        s_axis_tuser_shreg [2] <= s_axis_tuser_shreg [1];
        s_axis_tready_shreg[2] <= s_axis_tready_shreg[1];

    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            frame_ptr_reg <= 1'b0;

            s_axis_tready_reg <= 1'b0;

            busy_reg <= 1'b0;

            crc_state <= 32'hDEBB20E3;
        end else begin
            state_reg <= state_next;

            frame_ptr_reg <= frame_ptr_next;

            s_axis_tready_reg <= s_axis_tready_next;

            busy_reg <= state_next != STATE_IDLE;

        end

        last_cycle_tdata_reg <= last_cycle_tdata_next;
        last_cycle_tkeep_reg <= last_cycle_tkeep_next;
    end

    // output datapath logic
    reg [511:0] m_axis_tdata_reg = 512'd0;
    reg [63:0]  m_axis_tkeep_reg = 64'd0;
    reg        m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg        m_axis_tlast_reg = 1'b0;
    reg        m_axis_tuser_reg = 1'b0;

    reg [511:0] temp_m_axis_tdata_reg = 512'd0;
    reg [63:0]  temp_m_axis_tkeep_reg = 64'd0;
    reg        temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg        temp_m_axis_tlast_reg = 1'b0;
    reg        temp_m_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    assign m_axis_tdata = m_axis_tdata_reg;
    assign m_axis_tkeep = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast = m_axis_tlast_reg;
    assign m_axis_tuser = m_axis_tuser_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_axis_tready_int_early = m_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_int_to_output = 1'b0;
        store_axis_int_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_tready_int_reg) begin
            // input is ready
            if (m_axis_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_temp = 1'b1;
            end
        end else if (m_axis_tready) begin
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

`resetall