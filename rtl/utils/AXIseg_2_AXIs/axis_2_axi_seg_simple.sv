`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module axis_2_axi_seg_simple #(
    // input axis register
    parameter INPUT_REGS = 1
)(
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

    wire [1023:0]    m_axis_input_reg_tdata;
    wire [127 :0]    m_axis_input_reg_tkeep;
    wire             m_axis_input_reg_tvalid;
    wire             m_axis_input_reg_tready;
    wire             m_axis_input_reg_tlast;
    wire             m_axis_input_reg_tuser;

    reg [7:0]  sop_next;
    reg [7:0]  eop_next;
    reg [7:0]  ena_next;
    reg [7:0]  err_next;
    wire [4*8-1:0] mty_next;

    reg last_eop;

    generate


        if (INPUT_REGS > 0) begin

            axis_pipeline_register #(
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(1),
                .KEEP_WIDTH(128),
                .LAST_ENABLE(1),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .REG_TYPE(2),
                .LENGTH(INPUT_REGS)
            ) axis_pipeline_register_instance (
                .clk(clk),
                .rst(rst),
                .s_axis_tdata (s_axis_tdata),
                .s_axis_tkeep (s_axis_tkeep),
                .s_axis_tvalid(s_axis_tvalid),
                .s_axis_tready(s_axis_tready),
                .s_axis_tlast (s_axis_tlast),
                .s_axis_tid   (0),
                .s_axis_tdest (0),
                .s_axis_tuser(s_axis_tuser),
                .m_axis_tdata (m_axis_input_reg_tdata),
                .m_axis_tkeep (m_axis_input_reg_tkeep),
                .m_axis_tvalid(m_axis_input_reg_tvalid),
                .m_axis_tready(m_axis_input_reg_tready),
                .m_axis_tlast (m_axis_input_reg_tlast),
                .m_axis_tuser (m_axis_input_reg_tuser)
            );
        end else begin

            assign m_axis_input_reg_tdata  = s_axis_tdata;
            assign m_axis_input_reg_tkeep  = s_axis_tkeep;
            assign m_axis_input_reg_tvalid = s_axis_tvalid;
            assign s_axis_tready           = m_axis_input_reg_tready;
            assign m_axis_input_reg_tlast  = s_axis_tlast;
            assign m_axis_input_reg_tuser  = s_axis_tuser;

        end
    endgenerate

    always @(*) begin


        if (m_axis_input_reg_tvalid  && m_axis_input_reg_tready && m_axis_input_reg_tlast) begin
            eop_next = 1 << (keep2seg(m_axis_input_reg_tkeep));
        end else begin
            eop_next = 8'd0;
        end

        if (m_axis_input_reg_tvalid && m_axis_input_reg_tready) begin
            if (last_eop) begin
                sop_next =8'h01;
            end else begin
                sop_next = 8'd0;
            end
        end else begin
            sop_next = 8'd0;
        end

        if (m_axis_input_reg_tvalid && m_axis_input_reg_tready && !m_axis_input_reg_tlast) begin
            ena_next = 8'hff;
        end else if (m_axis_input_reg_tvalid && m_axis_input_reg_tready && m_axis_input_reg_tlast) begin
            ena_next = keep2ena(m_axis_input_reg_tkeep);
        end else begin
            ena_next = 8'h00;
        end
        

    end


    always @(posedge clk) begin
        if (rst) begin
            last_eop   <= 1'b1;

        end else begin
            if (m_axis_input_reg_tvalid && m_axis_input_reg_tready) begin
                last_eop <= m_axis_input_reg_tlast;
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
                .s_axis_tkeep(m_axis_input_reg_tkeep[i*16+:16] & {16{m_axis_input_reg_tvalid}}),
                .m_mty(mty_next[4*i+:4])
            );
        end
    endgenerate


    // skid buffer, no bubble cycles

    // datapath registers
    reg                  m_axis_input_reg_tready_reg = 1'b0;

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

    // datapath control
    reg store_axis_input_to_output;
    reg store_axis_input_to_temp;
    reg store_axis_temp_to_output;

    assign m_axis_input_reg_tready = m_axis_input_reg_tready_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    wire m_axis_input_reg_tready_early = m_axis_seg_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_input_reg_tvalid));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_input_to_output = 1'b0;
        store_axis_input_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_input_reg_tready_reg) begin
            // input is ready
            if (m_axis_seg_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = m_axis_input_reg_tvalid;
                store_axis_input_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_input_reg_tvalid;
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
        m_axis_input_reg_tready_reg <= m_axis_input_reg_tready_early;
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_input_to_output) begin
            m_axis_seg_tdata_reg <= m_axis_input_reg_tdata;

            m_ena_reg <= ena_next;
            m_sop_reg <= sop_next;
            m_eop_reg <= eop_next;
            m_err_reg <= eop_next & {8{m_axis_input_reg_tuser}};

            m_mty_reg <= mty_next;

        end else if (store_axis_temp_to_output) begin
            m_axis_seg_tdata_reg <= temp_m_axis_seg_tdata_reg;
            m_ena_reg <= temp_m_ena_reg;
            m_sop_reg <= temp_m_sop_reg;
            m_eop_reg <= temp_m_eop_reg;
            m_err_reg <= temp_m_err_reg;
            m_mty_reg <= temp_m_mty_reg;

        end

        if (store_axis_input_to_temp) begin
            temp_m_axis_seg_tdata_reg <= m_axis_input_reg_tdata;

            temp_m_ena_reg <= ena_next;
            temp_m_sop_reg <= sop_next;
            temp_m_eop_reg <= eop_next;
            temp_m_err_reg <= eop_next & {8{m_axis_input_reg_tuser}};

            temp_m_mty_reg <= mty_next;

        end

        if (rst) begin
            m_axis_input_reg_tready_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end

    assign m_axis_seg_tvalid = m_axis_tvalid_reg;

    // reorder the segments accordingly
    assign m_axis_seg_tdata = m_axis_seg_tdata_reg;

    assign m_axis_seg_tuser_mty = m_mty_reg;

    assign m_axis_seg_tuser_ena = m_ena_reg;
    assign m_axis_seg_tuser_sop = m_sop_reg;
    assign m_axis_seg_tuser_eop = m_eop_reg;
    assign m_axis_seg_tuser_err = m_err_reg;


endmodule