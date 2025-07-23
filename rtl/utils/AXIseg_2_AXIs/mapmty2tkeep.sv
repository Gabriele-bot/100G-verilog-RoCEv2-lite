`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module mapmty2tkeep #(
    parameter REGISTER=1'b0
)(
    input  wire clk,
    input  wire rst,

    input wire  [3:0]    s_mty,
    input wire           s_ena,

    output wire [15 :0]  m_axis_tkeep

);

    reg [15:0] tkeep_reg;

    generate
        if (REGISTER) begin
            always @(posedge clk) begin
                if (s_ena) begin
                    case (s_mty)
                        4'd0 : tkeep_reg <= 16'hffff;
                        4'd1 : tkeep_reg <= 16'h7fff;
                        4'd2 : tkeep_reg <= 16'h3fff;
                        4'd3 : tkeep_reg <= 16'h1fff;
                        4'd4 : tkeep_reg <= 16'h0fff;
                        4'd5 : tkeep_reg <= 16'h07ff;
                        4'd6 : tkeep_reg <= 16'h03ff;
                        4'd7 : tkeep_reg <= 16'h01ff;
                        4'd8 : tkeep_reg <= 16'h00ff;
                        4'd9 : tkeep_reg <= 16'h007f;
                        4'd10: tkeep_reg <= 16'h003f;
                        4'd11: tkeep_reg <= 16'h001f;
                        4'd12: tkeep_reg <= 16'h000f;
                        4'd13: tkeep_reg <= 16'h0007;
                        4'd14: tkeep_reg <= 16'h0003;
                        4'd15: tkeep_reg <= 16'h0001;
                        default : tkeep_reg <= 16'h0000;
                    endcase
                end else begin
                    tkeep_reg <= 16'h0000;
                end
            end
        end else begin
            always @(*) begin
                if (s_ena) begin
                    case (s_mty)
                        4'd0 : tkeep_reg = 16'hffff;
                        4'd1 : tkeep_reg = 16'h7fff;
                        4'd2 : tkeep_reg = 16'h3fff;
                        4'd3 : tkeep_reg = 16'h1fff;
                        4'd4 : tkeep_reg = 16'h0fff;
                        4'd5 : tkeep_reg = 16'h07ff;
                        4'd6 : tkeep_reg = 16'h03ff;
                        4'd7 : tkeep_reg = 16'h01ff;
                        4'd8 : tkeep_reg = 16'h00ff;
                        4'd9 : tkeep_reg = 16'h007f;
                        4'd10: tkeep_reg = 16'h003f;
                        4'd11: tkeep_reg = 16'h001f;
                        4'd12: tkeep_reg = 16'h000f;
                        4'd13: tkeep_reg = 16'h0007;
                        4'd14: tkeep_reg = 16'h0003;
                        4'd15: tkeep_reg = 16'h0001;
                        default : tkeep_reg = 16'h0000;
                    endcase
                end else begin
                    tkeep_reg = 16'h0000;
                end
            end
        end
    endgenerate

    assign m_axis_tkeep = tkeep_reg;


endmodule