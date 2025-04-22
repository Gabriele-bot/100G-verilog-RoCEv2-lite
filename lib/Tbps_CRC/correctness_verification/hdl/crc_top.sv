`timescale 1ns/1ps

`ifndef SIM
    `define GET_STATE_sub1(val) (val+64'h9e3779b97f4a7c15)
    `define GET_STATE_sub2(val) ((`GET_STATE_sub1(val) ^ (`GET_STATE_sub1(val) >> 30)) * 64'hbf58476d1ce4e5b9)
    `define GET_STATE_sub3(val) ((`GET_STATE_sub2(val) ^ (`GET_STATE_sub2(val) >> 27)) * 64'h94d049bb133111eb)
    `define GET_STATE(val) (`GET_STATE_sub3(val) ^ (`GET_STATE_sub3(val) >> 31))
    `define A 64'd19911102
    `define B 64'h9e3779b97f4a7c15
`endif

`include "config.svh"

module crc_top #(
    parameter int DWIDTH = `DWIDTH,
    parameter int CRC_WIDTH = `CRC_WIDTH,
    parameter int PIPE_LVL = `PIPE_LVL,
    parameter CRC_POLY = `CRC_POLY,
    parameter INIT = `INIT,
    parameter XOR_OUT = `XOR_OUT,
    parameter bit REFIN = `REFIN,
    parameter bit REFOUT = `REFOUT,
    parameter bit [7:0] PKT_LIMIT = `PKT_LIMIT,
    parameter int BYTE_BITS = `BYTE_BITS
) (
`ifdef SIM
    input logic clk,
    input logic rst,
    input logic [DWIDTH-1:0] din,
    input logic dlast,
    input logic flitEn,
    output logic [CRC_WIDTH-1:0] crc_out,
    output logic crc_out_vld
`else
    input logic clk_p,
    input logic clk_n    
`endif
);

`ifndef SIM
    logic clk;
    logic rst;
    logic start;
    logic [DWIDTH-1:0] din;
    logic dlast = 1'b0;
    logic flitEn = 1'b0;
    logic [CRC_WIDTH-1:0] crc_out;
    logic crc_out_vld;
    logic done = 1'b0;

    logic [7:0] pkt_cnt = 8'b0;
    logic [BYTE_BITS-1:0] pkt_byte_cnt = {BYTE_BITS{1'b0}};
    logic [((DWIDTH-1)/64+1)*64-1:0] din_tmp;

    logic [15:0] rand16;
    logic gen_new_pkt;

    IBUFDS ibufds_inst (
        .I(clk_p),
        .IB(clk_n),
        .O(clk)
    );
`endif

    crc_gen #(
        .DWIDTH           (DWIDTH           ),
        .CRC_WIDTH        (CRC_WIDTH        ),
        .PIPE_LVL         (PIPE_LVL         ),
        .CRC_POLY         (CRC_POLY         ),
        .INIT             (INIT             ),
        .XOR_OUT          (XOR_OUT          ),
        .REFIN            (REFIN            ),
        .REFOUT           (REFOUT           )
    ) u_crc_gen(.*);

`ifndef SIM
    vio_0 vio_inst (
        .clk(clk),
        .probe_out0(start)
    );

    ila_0 ila_inst (
        .clk(clk),
        .probe0(start),
        .probe1(done),
        .probe2(din),
        .probe3(dlast),
        .probe4(flitEn),
        .probe5(crc_out),
        .probe6(crc_out_vld)
    );

    genvar i;
    for (i = 0; i < (DWIDTH-1)/64+1; i++) begin
        xoshiro128ss_simple #(
            .S0 (`GET_STATE(`A+`B*i*2)),
            .S1 (`GET_STATE(`A+`B*(i*2+1)))
        ) rand_din (
        	.clk    (clk    ),
            .enable (start  ),
            .rand64 (din_tmp[(i+1)*64-1-:64])
        );
    end

    xoshiro32pp_simple #(
        .S0 (16'h1991),
        .S1 (16'h1102)
    ) rand_pkt_len(
    	.clk    (clk),
        .enable (gen_new_pkt),
        .rand16 (rand16)
    );

    always_ff @(posedge clk) begin
        if (~start) begin
            pkt_cnt <= 8'b0;
            done <= 1'b0;
        end
        else if (flitEn&dlast) begin
            pkt_cnt <= pkt_cnt + 1'b1;
            if (pkt_cnt + 1'b1 == PKT_LIMIT)
                done <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (pkt_byte_cnt > DWIDTH/8)
            pkt_byte_cnt <= pkt_byte_cnt - DWIDTH/8;
        else if (start & ~done)
            pkt_byte_cnt <= rand16[15-:BYTE_BITS];
        else
            pkt_byte_cnt <= {BYTE_BITS{1'b0}};            

        flitEn <= pkt_byte_cnt != {BYTE_BITS{1'b0}};
        dlast <= pkt_byte_cnt <= DWIDTH/8 && pkt_byte_cnt != {BYTE_BITS{1'b0}};
    end    

    assign rst = ~start;
    assign din = din_tmp[DWIDTH-1:0];
    assign gen_new_pkt = start & ~done & (pkt_byte_cnt <= DWIDTH/8);
`endif
endmodule