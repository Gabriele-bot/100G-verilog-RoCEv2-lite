`resetall `timescale 1ns / 1ps `default_nettype none

//Random Access Memory
module ram_block #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 16
) (
    input wire clk,
    input wire rst,
    input wire write_enable,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [DATA_WIDTH-1:0] data_in,
    output reg [DATA_WIDTH-1:0]            data_out
);

    reg [DATA_WIDTH-1:0]ram_block[0:2**ADDR_WIDTH - 1];

    always @(posedge clk) begin
        if (rst) begin
            data_out <= 0;
        end else begin
            if (write_enable) begin
                ram_block[address] <= data_in;
            end else begin
                data_out <= ram_block[address];
            end
        end
    end
endmodule

`resetall