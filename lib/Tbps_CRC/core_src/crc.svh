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

function bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] gen_unified_table();
    static bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] table_old = {CRC_WIDTH{{(DWIDTH+CRC_WIDTH){1'b0}}}};
    static bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table = {CRC_WIDTH{{(DWIDTH+CRC_WIDTH){1'b0}}}};
    for (int i = 0; i < CRC_WIDTH; i++)
        table_old[i][i] = 1'b1;
    for (int i = 0; i < DWIDTH; i++) begin
        /* - crc_out[0] = crc_in[CRC_WIDTH-1] ^ din[DWIDTH-1-i]; */
        unified_table[0] = table_old[CRC_WIDTH-1];
        unified_table[0][CRC_WIDTH+DWIDTH-1-i] = ~unified_table[0][CRC_WIDTH+DWIDTH-1-i];
        /////////////////////////////////////////////////////////////
        for (int j = 1; j < CRC_WIDTH; j++) begin
            if (CRC_POLY[j])
                unified_table[j] = table_old[j-1] ^ unified_table[0];
            else
                unified_table[j] = table_old[j-1];
        end
        table_old = unified_table;
    end    
    return unified_table;
endfunction

function bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] gen_crc_table(
    input bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table
);
    static bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] crc_table;
    for (int i = 0; i < CRC_WIDTH; i++) begin
        for (int j = 0; j < CRC_WIDTH; j++)
            crc_table[i][j] = unified_table[i][j];
    end
    return crc_table;   
endfunction

function bit [CRC_WIDTH-1:0][DWIDTH-1:0] gen_data_table(
    input bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table
);
    static bit [CRC_WIDTH-1:0][DWIDTH-1:0] data_table;
    for (int i = 0; i < CRC_WIDTH; i++) begin
        for (int j = 0; j < DWIDTH; j++)
            data_table[i][j] = unified_table[i][j+CRC_WIDTH];
    end
    return data_table;   
endfunction

function int get_div_per_lvl();
    int divider_per_lvl;
    int n_last_lvl;
    int j;
    if (PIPE_LVL == 0)
        divider_per_lvl = DWIDTH;
    else begin
        j = 0;
        n_last_lvl = 1;
        while (1) begin
            while (1) begin
                if (n_last_lvl*(j**PIPE_LVL) >= DWIDTH)
                    break;
                else
                    j++;
            end
            if (n_last_lvl+CRC_WIDTH >= j)
                break;
            else begin
                n_last_lvl++;
                j = 0;
            end
        end
        divider_per_lvl = j;
    end
    return divider_per_lvl;
endfunction

function bit [PIPE_LVL:0][31:0] get_n_terms(
    input int divider_per_lvl
);
    static bit [PIPE_LVL:0][31:0] n_terms;
    n_terms[0] = DWIDTH;
    for (int i = 1; i <= PIPE_LVL; i++) begin
        n_terms[i] = (n_terms[i-1]-1)/divider_per_lvl+1;
    end
    return n_terms;
endfunction

function bit [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] get_branch_enable_table(
    input [CRC_WIDTH-1:0][DWIDTH-1:0] data_table,
    input int divider_per_lvl,
    input bit [PIPE_LVL:0][31:0] n_terms
);
    static bit [PIPE_LVL:0][CRC_WIDTH-1:0][(DWIDTH-1)/DIV_PER_LVL:0] branch_enable_table = {(PIPE_LVL+1){{CRC_WIDTH{{((DWIDTH-1)/DIV_PER_LVL+1){1'b0}}}}}};
    int n_terms_int;
    if (PIPE_LVL != 0) begin
        n_terms_int = int'(n_terms[0]);
        for (int i = 0; i < CRC_WIDTH; i++) begin
            for (int j = 0; j <= (n_terms_int-1)/divider_per_lvl; j++) begin
                for (int k = j*divider_per_lvl; k < (j+1)*divider_per_lvl && k < n_terms_int; k++) begin
                    if (data_table[i][k]) begin
                        branch_enable_table[0][i][j] = 1'b1;
                        break;
                    end
                end
            end
        end
        for (int i = 1; i < PIPE_LVL; i++) begin
            n_terms_int = int'(n_terms[i]);
            for (int j = 0; j < CRC_WIDTH; j++) begin
                for (int k = 0; k <= (n_terms_int-1)/divider_per_lvl; k++) begin
                    for (int m = k*divider_per_lvl; m < (k+1)*divider_per_lvl && m < n_terms_int; m++) begin
                        if (branch_enable_table[i-1][j][m]) begin
                            branch_enable_table[i][j][k] = 1'b1;
                            break;
                        end
                    end
                end
            end
        end
    end
    return branch_enable_table;
endfunction

function bit [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] get_revert_table();
    static bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] table_old;
    static bit [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] revert_table = {$clog2(DWIDTH/8){{CRC_WIDTH{{CRC_WIDTH{1'b0}}}}}};
    for (int i = 0; i < $clog2(DWIDTH/8); i++) begin
        table_old = {CRC_WIDTH{{CRC_WIDTH{1'b0}}}};
        for (int j = 0; j < CRC_WIDTH; j++) begin
            table_old[j][j] = 1'b1;
        end
        for (int j = 0; j < 8*2**($clog2(DWIDTH/8)-1-i); j++) begin
            revert_table[i][CRC_WIDTH-1] = table_old[0];
            for (int k = 0; k < CRC_WIDTH-1; k++) begin
                if (CRC_POLY[k+1])
                    revert_table[i][k] = table_old[k+1] ^ table_old[0];
                else
                    revert_table[i][k] = table_old[k+1];
            end
            table_old = revert_table[i];
        end 
    end
    return revert_table;
endfunction
