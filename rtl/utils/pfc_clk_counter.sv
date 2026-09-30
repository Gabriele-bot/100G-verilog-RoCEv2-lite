`resetall `timescale 1ns / 1ps `default_nettype none

module pfc_clk_counter #(
    parameter COUNTER_WIDTH = 32
) (
    input  wire clk,
    input  wire rst,
    input  wire [8:0] pfc_req_i,
    output wire [COUNTER_WIDTH-1:0] count_o [8:0]
);

    reg [COUNTER_WIDTH-1:0] count_reg [8:0];

    genvar i;
    generate
        for (i = 0; i < 9; i = i + 1) begin : gen_counter
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    count_reg[i] <= {COUNTER_WIDTH{1'b0}};
                end else if (pfc_req_i[i]) begin
                    count_reg[i] <= count_reg[i] + 1;
                end
            end

            assign count_o[i] = count_reg[i];
        end
    endgenerate

endmodule