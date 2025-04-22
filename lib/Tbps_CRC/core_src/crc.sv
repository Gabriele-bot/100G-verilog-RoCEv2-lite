/**
Copyright (c) 2022, Qianfeng (Clark) Shen
All rights reserved.

This source code is licensed under the BSD-style license found in the
LICENSE file in the root directory of this source tree. 
 * @author Qianfeng (Clark) Shen
 * @email qianfeng.shen@gmail.com
 * @create date 2022-03-18 13:57:54
 * @modify date 2022-03-18 13:57:54
 */

`timescale 1ns / 1ps
module crc_gen #
(
    parameter int DWIDTH = 512,
    parameter int CRC_WIDTH = 16,
    parameter int PIPE_LVL = 0,
    parameter CRC_POLY = 16'hda5f,
    parameter INIT = 16'b0,
    parameter XOR_OUT = 16'b0,
    parameter bit REFIN = 1'b0,
    parameter bit REFOUT = 1'b0
)
(
    input logic clk,
    input logic rst,
    input logic [DWIDTH-1:0] din,
    input logic dlast,
    input logic flitEn,
    (* keep = "true" *) output logic [CRC_WIDTH-1:0] crc_out = {CRC_WIDTH{1'b0}},
    (* keep = "true" *) output logic crc_out_vld = 1'b0
);
    `include "crc.svh"
    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH+DWIDTH-1:0] UNI_TABLE = gen_unified_table();
    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] CRC_TABLE = gen_crc_table(UNI_TABLE);
    localparam bit [CRC_WIDTH-1:0][DWIDTH-1:0] DATA_TABLE = gen_data_table(UNI_TABLE);
    localparam int DIV_PER_LVL = get_div_per_lvl();
    localparam bit [PIPE_LVL:0][31:0] N_TERMS = get_n_terms(DIV_PER_LVL);
    localparam bit [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] BRANCH_ENABLE_TABLE = get_branch_enable_table(DATA_TABLE,DIV_PER_LVL,N_TERMS);

    //input registers
    logic [PIPE_LVL:0] dlast_reg = {(PIPE_LVL+1){1'b0}};
    logic [PIPE_LVL:0] flitEn_reg = {(PIPE_LVL+1){1'b0}};

    //internal wire
    logic [CRC_WIDTH-1:0] crc_int;

    //refin-refout convertion
    logic [DWIDTH-1:0] din_refin;
    logic [CRC_WIDTH-1:0] crc_refout;

    //pipeline logic
    logic [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] data_pipe;
    logic [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] data_pipe_reg = {(PIPE_LVL+1){{CRC_WIDTH{{((DWIDTH-1)/DIV_PER_LVL+1){1'b0}}}}}};

    //crc feedback
    (* keep = "true" *) logic [CRC_WIDTH-1:0] crc_previous = INIT;

    always_comb begin
    //REFIN logic
        if (REFIN) begin
            din_refin = {<<{din}};
            din_refin = {<<8{din_refin}};
        end
        else
            din_refin = din;

    //generate the first level
        data_pipe = {(PIPE_LVL+1){{CRC_WIDTH{{((DWIDTH-1)/DIV_PER_LVL+1){1'b0}}}}}};
        for (int i = 0; i < CRC_WIDTH; i++) begin
            for (int j = 0; j < (DWIDTH-1)/DIV_PER_LVL+1; j++) begin
                for (int k = 0; k < DIV_PER_LVL && j*DIV_PER_LVL+k < DWIDTH; k++) begin
                    if (DATA_TABLE[i][j*DIV_PER_LVL+k])
                        data_pipe[0][i][j] = data_pipe[0][i][j] ^ din_refin[j*DIV_PER_LVL+k];
                end
            end
        end
    //level 2 -> aggregate data chain into 1 bit per crc bit
        for (int i = 1; i <= PIPE_LVL; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < (N_TERMS[i]-1)/DIV_PER_LVL+1; k++) begin
                    for (int m = k*DIV_PER_LVL; m < (k+1)*DIV_PER_LVL && m < N_TERMS[i]; m++) begin
                        if (BRANCH_ENABLE_TABLE[i-1][j][m])
                            data_pipe[i][j][k] = data_pipe[i][j][k] ^ data_pipe_reg[i-1][j][m];
                    end
                end
            end
        end
    //the last level
        crc_int = {CRC_WIDTH{1'b0}};
        for (int i = 0; i < CRC_WIDTH; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                if (CRC_TABLE[i][j])
                    crc_int[i] = crc_int[i] ^ crc_previous[j];
            end
            crc_int[i] = crc_int[i] ^ data_pipe[PIPE_LVL][i][0];
        end        
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < PIPE_LVL; i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < N_TERMS[i+1]; k++) begin
                    if (BRANCH_ENABLE_TABLE[i][j][k])
                        data_pipe_reg[i][j][k] <= data_pipe[i][j][k];
                end
            end
        end
    end

//input signal pipelining logic
    always_comb begin
        dlast_reg[0] = dlast;
        flitEn_reg[0] = flitEn;
    end
    always_ff @(posedge clk) begin
        for (int i = 1; i <= PIPE_LVL; i++) begin
            dlast_reg[i] <= dlast_reg[i-1];
            flitEn_reg[i] <= flitEn_reg[i-1];
        end
    end

//register intermidate crc result
    always_ff @(posedge clk) begin
        if (rst)
            crc_previous <= INIT;
        else if (flitEn_reg[PIPE_LVL] & dlast_reg[PIPE_LVL])
            crc_previous <= INIT;
        else if (flitEn_reg[PIPE_LVL])
            crc_previous <= crc_int;
    end

//refout logic
    always_comb begin
        if (REFOUT)
            crc_refout = {<<{crc_int}};
        else
            crc_refout = crc_int;
    end    

//output the result
    always_ff @(posedge clk) begin
        if (rst) begin
            crc_out <= {CRC_WIDTH{1'b0}};
            crc_out_vld <= 1'b0;
        end
        else begin
            if (flitEn_reg[PIPE_LVL] & dlast_reg[PIPE_LVL])
                crc_out <= crc_refout ^ XOR_OUT;
            crc_out_vld <= flitEn_reg[PIPE_LVL] & dlast_reg[PIPE_LVL];
        end
    end
endmodule
