`timescale 1ns / 1ps

`include "config.svh"

module crc_byteEn_top(
    input logic clk,
    input logic rst,
    input logic [`DWIDTH-1:0] din,
    input logic [`DWIDTH/8-1:0] byteEn,
    input logic dlast,
    input logic flitEn,
    output logic [`CRC_WIDTH-1:0] crc_out,
    output logic crc_out_vld
);
    logic rst_reg;
    logic [`DWIDTH-1:0] din_reg;
    logic [`DWIDTH/8-1:0] byteEn_reg;
    logic dlast_reg;
    logic flitEn_reg;
    logic [`CRC_WIDTH-1:0] crc_out_wire;
    logic crc_out_vld_wire;

    crc_gen_byteEn #(
        .DWIDTH       (`DWIDTH       ),
        .CRC_WIDTH    (`CRC_WIDTH    ),
        .PIPE_LVL     (`PIPE_LVL     ),
        .CRC_POLY     (`CRC_POLY     ),
        .INIT         (`INIT         ),
        .XOR_OUT      (`XOR_OUT      ),
        .REFIN        (`REFIN        ),
        .REFOUT       (`REFOUT       )
    ) u_crc_gen (
    	.clk         (clk             ),
        .rst         (rst_reg         ),
        .din         (din_reg         ),
        .byteEn      (byteEn_reg      ),
        .dlast       (dlast_reg       ),
        .flitEn      (flitEn_reg      ),
        .crc_out     (crc_out_wire    ),
        .crc_out_vld (crc_out_vld_wire) 
    );

    always_ff @(posedge clk) begin
        rst_reg <= rst;
        din_reg <= din;
        byteEn_reg <= byteEn;
        dlast_reg <= dlast;
        flitEn_reg <= flitEn;
        crc_out <= crc_out_wire;
        crc_out_vld <= crc_out_vld_wire;
    end
endmodule
