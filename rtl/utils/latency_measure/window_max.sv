`resetall `timescale 1ns / 1ps `default_nettype none

module window_max #(
    VALUE_WIDTH = 32,
    N_CLOCKS_WINDOW = 1_000_000_000
) (
    input wire clk,
    input wire rst,

    input wire rst_counter,

    input wire [VALUE_WIDTH-1:0] value_in,
    input wire value_in_valid,

    output wire [VALUE_WIDTH-1:0] max_value_out,
    output wire max_value_out_valid
);

    reg [48:0] counter;
    reg [VALUE_WIDTH-1:0] max_value_reg;
    reg [VALUE_WIDTH-1:0] max_value_out_reg;
    reg max_value_out_valid_reg;


    always @(posedge clk) begin
        if (rst) begin
            counter <= 'd0;
            max_value_reg <= 0;
        end else if (rst_counter) begin
            counter <= 'd0;
            max_value_reg <= 0;
        end else begin
            if (value_in_valid) begin
                if (value_in > max_value_reg) begin
                    max_value_reg <= value_in;
                end
            end

            if (counter < N_CLOCKS_WINDOW - 1) begin
                counter <= counter + 1;
                max_value_out_valid_reg <= 1'b0;
            end else begin
                counter <= 'd0;
                max_value_reg <= 0;
                max_value_out_reg <= max_value_reg;
                max_value_out_valid_reg <= 1'b1;
            end
        end
    end

    assign max_value_out = max_value_out_reg;
    assign max_value_out_valid = max_value_out_valid_reg;

endmodule

`resetall