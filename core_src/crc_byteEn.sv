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
module crc_gen_byteEn #
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
    input logic [DWIDTH/8-1:0] byteEn,
    input logic dlast,
    input logic flitEn,
    (* keep = "true" *) output logic [CRC_WIDTH-1:0] crc_out = {CRC_WIDTH{1'b0}},
    (* keep = "true" *) output logic crc_out_vld = 1'b0
);
    generate
        if (DWIDTH % 8 != 0) $fatal(0,"DWIDTH has to be a multiple of 8");
        if (DWIDTH <= 8) $fatal(0,"DWIDTH is not larger than 1 byte. You don't really need this byte enable version");
    endgenerate
    `include "crc.svh"
    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH+DWIDTH-1:0] UNI_TABLE = gen_unified_table();
    localparam bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] CRC_TABLE = gen_crc_table(UNI_TABLE);
    localparam bit [CRC_WIDTH-1:0][DWIDTH-1:0] DATA_TABLE = gen_data_table(UNI_TABLE);
    localparam int DIV_PER_LVL = get_div_per_lvl();
    localparam bit [PIPE_LVL:0][31:0] N_TERMS = get_n_terms(DIV_PER_LVL);
    localparam bit [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] BRANCH_ENABLE_TABLE = get_branch_enable_table(DATA_TABLE,DIV_PER_LVL,N_TERMS);
    localparam bit [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] REVERT_TABLE = get_revert_table();

    //input registers
    logic [$clog2(DWIDTH/8)-1:0] crc_rev_en_pipe_wire;
    logic [PIPE_LVL:0][$clog2(DWIDTH/8)-1:0] crc_rev_en_pipe_reg = {(PIPE_LVL+1){{$clog2(DWIDTH/8){1'b0}}}};
    logic [PIPE_LVL:0] dlast_reg = {(PIPE_LVL+1){1'b0}};
    logic [PIPE_LVL:0] flitEn_reg = {(PIPE_LVL+1){1'b0}};
    logic [DWIDTH-1:0] din_reg = {DWIDTH{1'b0}};

    //input mask
    logic [DWIDTH-1:0] mask_in_byte;

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

    //crc revert
    logic [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0] crc_rev_wire = {$clog2(DWIDTH/8){{CRC_WIDTH{1'b0}}}};
    logic [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0] crc_rev_reg = {$clog2(DWIDTH/8){{CRC_WIDTH{1'b0}}}};
    logic [$clog2(DWIDTH/8)-1:0][$clog2(DWIDTH/8)-1:0] crc_rev_en_reg = {$clog2(DWIDTH/8){{$clog2(DWIDTH/8){1'b0}}}};
    logic [$clog2(DWIDTH/8)-1:0] crc_vld_rev_reg = {$clog2(DWIDTH/8){1'b0}};

//input regs
    always_comb begin
        for (int i = 0; i < DWIDTH/8; i++)
            mask_in_byte[(i+1)*8-1-:8] = byteEn[i] ? 8'hff : 8'h00;
    end            

    always_ff @(posedge clk) begin
        if (rst)
            din_reg <= {DWIDTH{1'b0}};
        else if (flitEn) begin
            din_reg <= din & mask_in_byte;
        end
    end

    always_comb begin
    //REFIN logic
        if (REFIN) begin
            din_refin = {<<{din_reg}};
            din_refin = {<<8{din_refin}};
        end
        else
            din_refin = din_reg;

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
        crc_rev_en_pipe_wire = {$clog2(DWIDTH/8){1'b0}};

        for (int i = 0; i < DWIDTH/8; i++) begin
            crc_rev_en_pipe_wire = crc_rev_en_pipe_wire + {~byteEn[i]};
        end
    end
    always_ff @(posedge clk) begin
        crc_rev_en_pipe_reg[0] <= {<<{crc_rev_en_pipe_wire}};
        dlast_reg[0] <= dlast;
        flitEn_reg[0] <= flitEn;
        for (int i = 1; i <= PIPE_LVL; i++) begin
            crc_rev_en_pipe_reg[i] <= crc_rev_en_pipe_reg[i-1];
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

//do crc revert to cancel the padding zeros
    always_comb begin
        crc_rev_wire = {($clog2(DWIDTH/8)){{CRC_WIDTH{1'b0}}}};
        for (int i = 0; i < $clog2(DWIDTH/8); i++) begin
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k < CRC_WIDTH; k++) begin
                    if (REVERT_TABLE[i][j][k])
                        crc_rev_wire[i][j] = crc_rev_wire[i][j] ^ crc_rev_reg[i][k];
                end
            end
        end
    end
    always_ff @(posedge clk) begin
        crc_rev_reg[0] <= crc_int;
        crc_vld_rev_reg[0] <= flitEn_reg[PIPE_LVL] & dlast_reg[PIPE_LVL];
        crc_rev_en_reg[0] <= crc_rev_en_pipe_reg[PIPE_LVL];
        for (int i = 1; i < $clog2(DWIDTH/8); i++) begin
            crc_rev_en_reg[i] <= crc_rev_en_reg[i-1];
            if (crc_rev_en_reg[i-1][i-1])
                crc_rev_reg[i] <= crc_rev_wire[i-1];
            else
                crc_rev_reg[i] <= crc_rev_reg[i-1];
        end
        for (int i = 1; i < $clog2(DWIDTH/8); i++) begin
            crc_vld_rev_reg[i] <= crc_vld_rev_reg[i-1];
        end
    end

//refout logic
    always_comb begin
        if (crc_rev_en_reg[$clog2(DWIDTH/8)-1][$clog2(DWIDTH/8)-1])
            crc_refout = crc_rev_wire[$clog2(DWIDTH/8)-1];
        else
            crc_refout = crc_rev_reg[$clog2(DWIDTH/8)-1];

        if (REFOUT)
            crc_refout = {<<{crc_refout}};
    end

//output the result
    always_ff @(posedge clk) begin
        if (rst) begin
            crc_out <= {CRC_WIDTH{1'b0}};
            crc_out_vld <= 1'b0;
        end
        else begin
            if (crc_vld_rev_reg[$clog2(DWIDTH/8)-1])
                crc_out <= crc_refout ^ XOR_OUT;
            crc_out_vld <= crc_vld_rev_reg[$clog2(DWIDTH/8)-1];
        end
    end
endmodule
