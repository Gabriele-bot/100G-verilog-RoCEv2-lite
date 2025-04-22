`timescale 1ns / 1ps
`define ROTL64(X,K) ({X << K} | {X >> (64-K)})
module xoshiro128ss_simple #
(
    parameter bit [63:0] S0 = 64'd1,
    parameter bit [63:0] S1 = 64'd2
)
(
    input logic clk,
    input logic enable,
    output logic [63:0] rand64 = `ROTL64({S0*5},7)*9
);
    logic [63:0] s0 = S0;
    logic [63:0] s1 = S1;

    logic [63:0] s0_new, s1_new;

    always_comb begin
        s0_new = s0;
        s1_new = s1;
        s1_new = s1_new ^ s0;
        s0_new = `ROTL64(s0_new, 24) ^ s1_new ^ (s1_new << 16);
        s1_new = `ROTL64(s1_new, 37);
    end

    always_ff @(posedge clk) begin
        if (enable) begin
            s0 <= s0_new;
            s1 <= s1_new;
            rand64 <= `ROTL64({s0*5},7)*9;
        end
    end
endmodule
