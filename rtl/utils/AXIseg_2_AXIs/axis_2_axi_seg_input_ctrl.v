`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module axis_2_axi_seg_input_ctrl (
    input  wire clk,
    input  wire rst,

    input  wire [1023:0]  s_axis_tdata,
    input  wire [127 :0]  s_axis_tkeep,
    input  wire           s_axis_tvalid,
    output wire           s_axis_tready,
    input  wire           s_axis_tlast,
    input  wire           s_axis_tuser,


    output wire [128*8-1:0] m_axis_seg_tdata,
    output wire             m_axis_seg_tvalid,
    input  wire             m_axis_seg_tready,
    output wire [7:0]       m_axis_seg_tuser_ena,
    output wire [7:0]       m_axis_seg_tuser_sop,
    output wire [7:0]       m_axis_seg_tuser_eop,
    output wire [7:0]       m_axis_seg_tuser_err,
    output wire [4*8-1:0]   m_axis_seg_tuser_mty

);

    function[2:0] keep2seg;
        input [127:0] keep_in;
        if (keep_in[127:16] == 112'd0) begin
            keep2seg = 0;
        end else if (keep_in[127:32] == 96'd0) begin
            keep2seg =  1;
        end else if (keep_in[127:48] == 80'd0) begin
            keep2seg = 2;
        end else if (keep_in[127:64] == 64'd0) begin
            keep2seg = 3;
        end else if (keep_in[127:80] == 48'd0) begin
            keep2seg = 4;
        end else if (keep_in[127:96] == 32'd0) begin
            keep2seg = 5;
        end else if (keep_in[127:112] == 16'd0) begin
            keep2seg = 6;
        end else begin
            keep2seg = 7;
        end
    endfunction

    function[7:0] keep2ena;
        input [127:0] keep_in;
        integer i;
        for (i=0; i<8; i=i+1) begin
            keep2ena[i] = |keep_in[i*16+:16];
        end
    endfunction

    function [7:0] count2ena;
        input [2:0] count;
        case (count)
            3'd0: count2ena = 8'h01;
            3'd1: count2ena = 8'h03;
            3'd2: count2ena = 8'h07;
            3'd3: count2ena = 8'h0F;
            3'd4: count2ena = 8'h1F;
            3'd5: count2ena = 8'h3F;
            3'd6: count2ena = 8'h7F;
            3'd7: count2ena = 8'hFF;
            default: count2ena =8'h00;
        endcase
    endfunction


    reg [2:0]  offest_reg, offest_next;
    reg [7:0]  sop_reg, sop_next;
    reg [7:0]  eop_reg, eop_next;
    reg [15:0] eop_temp;
    reg [7:0]  ena_reg, ena_next;
    reg [7:0]  err_reg, err_next;
    reg [15:0] ena_temp;

    wire [4*8-1:0] mty_next;

    reg [7:0][2:0] in_index_reg, in_index_next;

    reg [7:0][127:0] tdata_seg_reg, tdata_seg_next;
    reg [7:0][15:0] tkeep_seg_reg, tkeep_seg_next;

    reg sof_reg, sof_next; // start of frame
    reg last_eop;
    reg         tvalid_reg;
    reg         tlast_reg;
    reg         tuser_reg;
    reg [1023:0]tdata_reg;

    wire             tlast;
    wire             tuser;
    wire [7:0][127:0] tdata;

    

    wire [7:0] fifo_tready;
    reg        fifo_tready_reg;


    wire [7:0] sop, eop, ena, err;
    wire [7:0][3:0] mty;

    reg [7:0] out_offset_reg,  out_offset_next;
    reg [7:0][2:0] out_index_reg, out_index_next;

    integer k;

    always @(*) begin

        offest_next = offest_reg;

        if (s_axis_tvalid  && s_axis_tready && s_axis_tlast) begin
            offest_next = offest_reg + keep2seg(s_axis_tkeep) + 3'd1;
            eop_temp = 1 << (offest_reg + keep2seg(s_axis_tkeep));
            eop_next = (eop_temp[15:8] | eop_temp[7:0]);
        end else begin
            eop_next = 8'd0;
        end

        if (s_axis_tvalid && s_axis_tready) begin
            if (last_eop) begin
                case (offest_reg)
                    3'd0: sop_next = 8'h01;
                    3'd1: sop_next = 8'h02;
                    3'd2: sop_next = 8'h04;
                    3'd3: sop_next = 8'h08;
                    3'd4: sop_next = 8'h10;
                    3'd5: sop_next = 8'h20;
                    3'd6: sop_next = 8'h40;
                    3'd7: sop_next = 8'h80;
                    default: sop_next =8'h01;
                endcase
            end else begin
                sop_next = 8'd0;
            end
        end else begin
            sop_next = 8'd0;
        end

        if (s_axis_tvalid && s_axis_tready && !s_axis_tlast) begin
            ena_next = 8'hff;
        end else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            ena_temp = keep2ena(s_axis_tkeep) << (offest_reg);
            ena_next = ena_temp[15:8] | ena_temp[7:0];
        end else begin
            ena_next = 8'h00;
        end

        for (k=0; k<8; k=k+1) begin
            in_index_next[k] = k - offest_reg;
        end
        

    end


    always @(posedge clk) begin
        if (rst) begin
            offest_reg <= 3'd0;
            last_eop   <= 1'b1;

        end else begin
            offest_reg <= offest_next;

            if (s_axis_tvalid && s_axis_tready) begin
                last_eop <= s_axis_tlast;
            end
        end
    end


    generate

        for (genvar i=0; i<8; i=i+1) begin

            maptkeep2mty #(
                .REGISTER(1'b0)
            ) maptkeep2mty_instance (
                .clk(clk),
                .rst(rst),
                .s_axis_tkeep(s_axis_tkeep[i*16+:16] & {16{s_axis_tvalid}}),
                .m_mty(mty_next[4*i+:4])
            );
        end
    endgenerate


    // skid buffer, no bubble cycles

    // datapath registers
    reg                  s_axis_tready_reg = 1'b0;

    reg [7:0][127:0]     m_axis_seg_tdata_reg = {{128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;

    reg [7:0]            m_ena_reg = 8'h0;
    reg [7:0]            m_sop_reg = 8'h0;
    reg [7:0]            m_eop_reg = 8'h0;
    reg [7:0]            m_err_reg = 8'h0;
    reg [7:0][3:0]       m_mty_reg = {4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0};


    reg [7:0][127:0] temp_m_axis_seg_tdata_reg = {{128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}, {128{1'b0}}};
    reg              temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg [7:0]        temp_m_ena_reg  = 8'h0;
    reg [7:0]        temp_m_sop_reg  = 8'h0;
    reg [7:0]        temp_m_eop_reg  = 8'h0;
    reg [7:0]        temp_m_err_reg  = 8'h0;
    reg [7:0][3:0]   temp_m_mty_reg  = {4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0};
    reg [7:0][2:0]   temp_in_index_reg = {3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0};

    // datapath control
    reg store_axis_input_to_output;
    reg store_axis_input_to_temp;
    reg store_axis_temp_to_output;

    assign s_axis_tready = s_axis_tready_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    wire s_axis_tready_early = m_axis_seg_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !s_axis_tvalid));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_input_to_output = 1'b0;
        store_axis_input_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (s_axis_tready_reg) begin
            // input is ready
            if (m_axis_seg_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = s_axis_tvalid;
                store_axis_input_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = s_axis_tvalid;
                store_axis_input_to_temp = 1'b1;
            end
        end else if (m_axis_seg_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        s_axis_tready_reg <= s_axis_tready_early;
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_input_to_output) begin
            m_axis_seg_tdata_reg[0] <= s_axis_tdata[0*128+:128];
            m_axis_seg_tdata_reg[1] <= s_axis_tdata[1*128+:128];
            m_axis_seg_tdata_reg[2] <= s_axis_tdata[2*128+:128];
            m_axis_seg_tdata_reg[3] <= s_axis_tdata[3*128+:128];
            m_axis_seg_tdata_reg[4] <= s_axis_tdata[4*128+:128];
            m_axis_seg_tdata_reg[5] <= s_axis_tdata[5*128+:128];
            m_axis_seg_tdata_reg[6] <= s_axis_tdata[6*128+:128];
            m_axis_seg_tdata_reg[7] <= s_axis_tdata[7*128+:128];

            m_ena_reg <= ena_next;
            m_sop_reg <= sop_next;
            m_eop_reg <= eop_next;
            m_err_reg <= eop_next & {8{s_axis_tuser}};

            m_mty_reg[0] <= mty_next[0*4+:4];
            m_mty_reg[1] <= mty_next[1*4+:4];
            m_mty_reg[2] <= mty_next[2*4+:4];
            m_mty_reg[3] <= mty_next[3*4+:4];
            m_mty_reg[4] <= mty_next[4*4+:4];
            m_mty_reg[5] <= mty_next[5*4+:4];
            m_mty_reg[6] <= mty_next[6*4+:4];
            m_mty_reg[7] <= mty_next[7*4+:4];

            in_index_reg <= in_index_next;
        end else if (store_axis_temp_to_output) begin
            m_axis_seg_tdata_reg <= temp_m_axis_seg_tdata_reg;
            m_ena_reg <= temp_m_ena_reg;
            m_sop_reg <= temp_m_sop_reg;
            m_eop_reg <= temp_m_eop_reg;
            m_err_reg <= temp_m_err_reg;
            m_mty_reg <= temp_m_mty_reg;

            in_index_reg <= temp_in_index_reg;
        end

        if (store_axis_input_to_temp) begin
            temp_m_axis_seg_tdata_reg[0] <= s_axis_tdata[0*128+:128];
            temp_m_axis_seg_tdata_reg[1] <= s_axis_tdata[1*128+:128];
            temp_m_axis_seg_tdata_reg[2] <= s_axis_tdata[2*128+:128];
            temp_m_axis_seg_tdata_reg[3] <= s_axis_tdata[3*128+:128];
            temp_m_axis_seg_tdata_reg[4] <= s_axis_tdata[4*128+:128];
            temp_m_axis_seg_tdata_reg[5] <= s_axis_tdata[5*128+:128];
            temp_m_axis_seg_tdata_reg[6] <= s_axis_tdata[6*128+:128];
            temp_m_axis_seg_tdata_reg[7] <= s_axis_tdata[7*128+:128];

            temp_m_ena_reg <= ena_next;
            temp_m_sop_reg <= sop_next;
            temp_m_eop_reg <= eop_next;
            temp_m_err_reg <= eop_next & {8{s_axis_tuser}};

            temp_m_mty_reg[0] <= mty_next[0*4+:4];
            temp_m_mty_reg[1] <= mty_next[1*4+:4];
            temp_m_mty_reg[2] <= mty_next[2*4+:4];
            temp_m_mty_reg[3] <= mty_next[3*4+:4];
            temp_m_mty_reg[4] <= mty_next[4*4+:4];
            temp_m_mty_reg[5] <= mty_next[5*4+:4];
            temp_m_mty_reg[6] <= mty_next[6*4+:4];
            temp_m_mty_reg[7] <= mty_next[7*4+:4];

            temp_in_index_reg <= in_index_next;
        end

        if (rst) begin
            s_axis_tready_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end

    assign m_axis_seg_tvalid = m_axis_tvalid_reg;

    // reorder the segments accordingly
    assign m_axis_seg_tdata[0*128+:128] = m_axis_seg_tdata_reg[in_index_reg[0]];
    assign m_axis_seg_tdata[1*128+:128] = m_axis_seg_tdata_reg[in_index_reg[1]];
    assign m_axis_seg_tdata[2*128+:128] = m_axis_seg_tdata_reg[in_index_reg[2]];
    assign m_axis_seg_tdata[3*128+:128] = m_axis_seg_tdata_reg[in_index_reg[3]];
    assign m_axis_seg_tdata[4*128+:128] = m_axis_seg_tdata_reg[in_index_reg[4]];
    assign m_axis_seg_tdata[5*128+:128] = m_axis_seg_tdata_reg[in_index_reg[5]];
    assign m_axis_seg_tdata[6*128+:128] = m_axis_seg_tdata_reg[in_index_reg[6]];
    assign m_axis_seg_tdata[7*128+:128] = m_axis_seg_tdata_reg[in_index_reg[7]];

    assign m_axis_seg_tuser_mty[0*4+:4] = m_mty_reg[in_index_reg[0]];
    assign m_axis_seg_tuser_mty[1*4+:4] = m_mty_reg[in_index_reg[1]];
    assign m_axis_seg_tuser_mty[2*4+:4] = m_mty_reg[in_index_reg[2]];
    assign m_axis_seg_tuser_mty[3*4+:4] = m_mty_reg[in_index_reg[3]];
    assign m_axis_seg_tuser_mty[4*4+:4] = m_mty_reg[in_index_reg[4]];
    assign m_axis_seg_tuser_mty[5*4+:4] = m_mty_reg[in_index_reg[5]];
    assign m_axis_seg_tuser_mty[6*4+:4] = m_mty_reg[in_index_reg[6]];
    assign m_axis_seg_tuser_mty[7*4+:4] = m_mty_reg[in_index_reg[7]];

    assign m_axis_seg_tuser_ena = m_ena_reg;
    assign m_axis_seg_tuser_sop = m_sop_reg;
    assign m_axis_seg_tuser_eop = m_eop_reg;
    assign m_axis_seg_tuser_err = m_err_reg;


endmodule