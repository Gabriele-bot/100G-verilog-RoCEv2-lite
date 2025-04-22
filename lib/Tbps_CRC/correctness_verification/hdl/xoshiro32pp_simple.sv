`timescale 1ns / 1ps
`define ROTL16(X,K) ({X << K} | {X >> (16-K)})
module xoshiro32pp_simple #
(
    parameter bit [15:0] S0 = 16'd1,
    parameter bit [15:0] S1 = 16'd2
)
(
    input logic clk,
    input logic enable,
    output logic [15:0] rand16 = `ROTL16({S0+S1},9)+S0
);
    logic [15:0] s0 = S0;
    logic [15:0] s1 = S1;

    logic [15:0] s0_new, s1_new;

    always_comb begin
        s0_new = (`ROTL16(s0,13) ^ (s0 ^ s1)) ^ ((s0 ^ s1) <<< 5);
        s1_new = `ROTL16((s0^s1),10);
    end

    always_ff @(posedge clk) begin
        if (enable) begin
            s0 <= s0_new;
            s1 <= s1_new;
            rand16 <= `ROTL16((s0+s1),9) +s0;
        end
    end
    assign s0s1 = s0 ^ s1;
endmodule