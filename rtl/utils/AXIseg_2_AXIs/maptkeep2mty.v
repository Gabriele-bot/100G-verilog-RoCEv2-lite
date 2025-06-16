`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module maptkeep2mty #(
    parameter REGISTER=1'b0
)(
    input  wire clk,
    input  wire rst,

    input  wire [15 :0]  s_axis_tkeep,

    output wire  [3:0]    m_mty

);

    reg [3:0] mty_reg;

    generate
        if (REGISTER) begin
            always @(posedge clk) begin
                case (s_axis_tkeep)
                    16'hffff: mty_reg <= 4'd0;
                    16'h7fff: mty_reg <= 4'd1;
                    16'h3fff: mty_reg <= 4'd2;
                    16'h1fff: mty_reg <= 4'd3;
                    16'h0fff: mty_reg <= 4'd4;
                    16'h07ff: mty_reg <= 4'd5;
                    16'h03ff: mty_reg <= 4'd6;
                    16'h01ff: mty_reg <= 4'd7;
                    16'h00ff: mty_reg <= 4'd8;
                    16'h007f: mty_reg <= 4'd9;
                    16'h003f: mty_reg <= 4'd10;
                    16'h001f: mty_reg <= 4'd11;
                    16'h000f: mty_reg <= 4'd12;
                    16'h0007: mty_reg <= 4'd13;
                    16'h0003: mty_reg <= 4'd14;
                    16'h0001: mty_reg <= 4'd15;
                    16'h0000: mty_reg <= 4'd0;
                    default : mty_reg <= 4'd0;
                endcase
            end
        end else begin
            always @(*) begin
                case (s_axis_tkeep)
                    16'hffff: mty_reg = 4'd0;
                    16'h7fff: mty_reg = 4'd1;
                    16'h3fff: mty_reg = 4'd2;
                    16'h1fff: mty_reg = 4'd3;
                    16'h0fff: mty_reg = 4'd4;
                    16'h07ff: mty_reg = 4'd5;
                    16'h03ff: mty_reg = 4'd6;
                    16'h01ff: mty_reg = 4'd7;
                    16'h00ff: mty_reg = 4'd8;
                    16'h007f: mty_reg = 4'd9;
                    16'h003f: mty_reg = 4'd10;
                    16'h001f: mty_reg = 4'd11;
                    16'h000f: mty_reg = 4'd12;
                    16'h0007: mty_reg = 4'd13;
                    16'h0003: mty_reg = 4'd14;
                    16'h0001: mty_reg = 4'd15;
                    16'h0000: mty_reg = 4'd0;
                    default : mty_reg = 4'd0;
                endcase
            end
        end
    endgenerate

    assign m_mty = mty_reg;


endmodule