`resetall
`timescale 1ns / 1ps
`default_nettype none

module sync_bit_array #
(
    // depth of synchronizer
    parameter N = 2,
    parameter BUS_WIDTH = 2
)
(
    input  wire src_clk,
    input  wire src_rst,
    input  wire dest_clk,

    input wire  [BUS_WIDTH-1:0] data_in,
    output wire [BUS_WIDTH-1:0] data_out
);

    reg  [BUS_WIDTH-1:0] data_in_reg;

    (* srl_style = "register" *) (* ASYNC_REG = "TRUE" *)  (* SHREG_EXTRACT = "NO" *)
    reg  [BUS_WIDTH-1:0] sync_reg [N-1:0];

    integer i;

    assign data_out = sync_reg[N-1];

    always @(posedge src_clk) begin
        if (src_rst) begin
            data_in_reg <= {BUS_WIDTH{1'b0}};
        end else begin
            data_in_reg <= data_in;
        end
    end

    always @(posedge dest_clk) begin
        sync_reg[0] <= data_in_reg;
        for (i=1; i<N; i=i+1) begin
            sync_reg[i] <= sync_reg[i-1];
        end
    end

endmodule

`resetall