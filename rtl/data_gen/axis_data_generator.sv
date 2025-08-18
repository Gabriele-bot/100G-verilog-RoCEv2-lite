`resetall `timescale 1ns / 1ps `default_nettype none


module axis_data_generator #(
    parameter DATA_WIDTH = 64
) (

    input wire clk,
    input wire rst,

    input wire rst_word_ctr,

    input wire start,
    input wire stop,

    // axis stream
    output  wire [DATA_WIDTH   - 1 :0] m_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_axis_tkeep,
    output  wire                       m_axis_tvalid,
    input   wire                       m_axis_tready,
    output  wire                       m_axis_tlast,
    output  wire                       m_axis_tuser,

    // config
    input wire [31:0] length
);

    localparam KEEP_WIDTH = DATA_WIDTH/8;
    localparam COUNT_KEEP_WIDTH = $clog2(KEEP_WIDTH);


    integer i;

    function [$clog2(KEEP_WIDTH):0] keep2count;
        input [KEEP_WIDTH - 1:0] k;
        for (i = KEEP_WIDTH - 1; i >= 0; i = i - 1) begin
            if (i == KEEP_WIDTH - 1) begin
                if (k[KEEP_WIDTH -1]) keep2count = KEEP_WIDTH;
            end else begin
                if (k[i +: 2] == 2'b01) keep2count = i+1;
                else if (k[i +: 2] == 2'b00) keep2count = 0;
            end
        end
    endfunction

    function [KEEP_WIDTH - 1:0] count2keep;
        input [$clog2(KEEP_WIDTH):0] k;
        reg [2*KEEP_WIDTH - 1:0] temp_ones = {{KEEP_WIDTH{1'b0}}, {KEEP_WIDTH{1'b1}}};
        reg [2*KEEP_WIDTH - 1:0] temp_srl;
        if (k < KEEP_WIDTH) begin
            temp_srl = temp_ones << k;
            count2keep = temp_srl[KEEP_WIDTH +: KEEP_WIDTH];
        end else begin
            count2keep = {KEEP_WIDTH{1'b1}};
        end
    endfunction

    parameter SLICES_32BIT = DATA_WIDTH/32;
    parameter WORD_WIDTH   = KEEP_WIDTH;

    reg [31:0] length_reg;
    reg start_1;
    reg start_2;

    reg [31:0] word_counter = {32{1'b1}} - WORD_WIDTH;
    reg [33:0] word_counter_out;
    reg [31:0] tot_word_ctr;
    reg [KEEP_WIDTH-1:0] tkeep_reg;
    reg                  tlast_reg;

    reg  stop_transfer_reg;

    wire [DATA_WIDTH   - 1 :0] s_output_reg_axis_tdata;
    wire [KEEP_WIDTH - 1 :0] s_output_reg_axis_tkeep;
    wire                       s_output_reg_axis_tvalid;
    wire                       s_output_reg_axis_tready;
    wire                       s_output_reg_axis_tlast;
    wire                       s_output_reg_axis_tuser;

    reg [31:0] both_up_input, both_up_output;
    reg [31:0] valid_input,  valid_output;

    always @(posedge clk) begin
        if (rst || (~start_1 && start)) begin
            both_up_input <= 0;
            both_up_output <= 0;

            valid_input <= 0;
            valid_output <= 0;
        end else begin
            if (s_output_reg_axis_tvalid && s_output_reg_axis_tready) begin
                both_up_input <= both_up_input + 1;
            end

            if (s_output_reg_axis_tvalid) begin
                valid_input <= valid_input + 1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                both_up_output <= both_up_output + 1;
            end

            if (m_axis_tvalid) begin
                valid_output <= valid_output + 1;
            end
        end
    end

    /*
     * Generate payolad data
     */

    always @(posedge clk) begin
        if (rst) begin
            word_counter      <= {32{1'b1}} - WORD_WIDTH;
            word_counter_out  <= 34'd0;
            tot_word_ctr      <= 32'd0;
            length_reg        <= 32'd0;
            stop_transfer_reg <= 1'b0;
            start_1 <= 1'b0;
            start_2 <= 1'b0;
        end else begin
            start_1 <= start;
            start_2 <= start_1;
            if (stop) begin
                stop_transfer_reg <= 1'b1;
                if (length_reg == 0) begin // no transfer on going
                    word_counter <= {32{1 'b1}} - WORD_WIDTH;
                    word_counter_out <= word_counter_out;
                    tkeep_reg <= {KEEP_WIDTH{1'b0}};
                    tlast_reg <= 1'b0;
                end else begin
                    word_counter <= length_reg - WORD_WIDTH;
                    word_counter_out <= word_counter_out;
                    tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b1;
                end
            end else if (s_output_reg_axis_tvalid && s_output_reg_axis_tready) begin
                if ((word_counter <= length)) begin
                    word_counter <= word_counter + WORD_WIDTH;
                    word_counter_out <= word_counter_out + WORD_WIDTH;
                end
                if (word_counter + WORD_WIDTH + WORD_WIDTH >= length_reg) begin
                    if (length_reg[COUNT_KEEP_WIDTH-1:0] == 12'd0 && |(length_reg[31:COUNT_KEEP_WIDTH])) begin
                        tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    end else begin
                        tkeep_reg <= count2keep(length_reg[COUNT_KEEP_WIDTH-1:0]);
                    end
                    tlast_reg <= 1'b1;
                end else begin
                    tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b0;
                end
                if (s_output_reg_axis_tlast) begin
                    word_counter      <= {32{1'b1}} - WORD_WIDTH;
                    word_counter_out <= word_counter_out;
                    length_reg        <= 32'd0;
                    tkeep_reg <= {KEEP_WIDTH{1'b0}};
                    stop_transfer_reg <= 1'b0;
                    tot_word_ctr <= tot_word_ctr + length_reg;
                end
            end else if (~start_1 && start) begin //start of transfer
                stop_transfer_reg <= 1'b0;
                length_reg <= length;
                word_counter <= {32{1'b1}} - WORD_WIDTH;
                word_counter_out <= word_counter_out;
                // generate teep only for the last frame
                if (length == WORD_WIDTH) begin
                    tkeep_reg  <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b1;
                end else if (length < WORD_WIDTH) begin
                    tkeep_reg <= count2keep(length[COUNT_KEEP_WIDTH-1:0]);
                    tlast_reg <= 1'b1;
                end else begin
                    tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b0;
                end
            end else if (~start_2 && start_1) begin
                stop_transfer_reg <= 1'b0;
                word_counter <= 0;
                word_counter_out <= tot_word_ctr;
                // generate teep only for the last frame
                if (length_reg == WORD_WIDTH) begin
                    tkeep_reg  <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b1;
                end else if (length_reg < WORD_WIDTH) begin
                    tkeep_reg <= count2keep(length_reg[COUNT_KEEP_WIDTH-1:0]);
                    tlast_reg <= 1'b1;
                end else begin
                    tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b0;
                end
            end
            if (s_output_reg_axis_tvalid && s_output_reg_axis_tready && s_output_reg_axis_tlast) begin
                stop_transfer_reg <= 1'b0;
            end
            if (rst_word_ctr) begin
                word_counter_out <= 34'd0;
                tot_word_ctr     <= 32'd0;
            end
        end
    end

    // TDATA
    generate
        assign s_output_reg_axis_tdata[31:0] = word_counter_out[33:2];
        for (genvar j=1; j<SLICES_32BIT; j=j+1) begin
            assign s_output_reg_axis_tdata[j*32+:32] = word_counter_out[33:2] + j;
        end
    endgenerate

    // TKEEP
    assign s_output_reg_axis_tkeep  = tkeep_reg;
    assign s_output_reg_axis_tvalid = ((word_counter < length_reg) ? 1'b1 : 1'b0);
    assign s_output_reg_axis_tlast  = tlast_reg ;
    assign s_output_reg_axis_tuser  = stop_transfer_reg & s_output_reg_axis_tvalid;



    // datapath registers
    reg                  s_axis_tready_reg = 1'b0;

    reg [DATA_WIDTH-1:0] m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                  m_axis_tlast_reg  = 1'b0;
    reg                  m_axis_tuser_reg  = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg  = 1'b0;
    reg                  temp_m_axis_tuser_reg  = 1'b0;

    // datapath control
    reg store_axis_input_to_output;
    reg store_axis_input_to_temp;
    reg store_axis_temp_to_output;

    assign s_output_reg_axis_tready = s_axis_tready_reg;

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tkeep  = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tlast_reg ;
    assign m_axis_tuser  = m_axis_tuser_reg ;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    wire s_axis_tready_early = m_axis_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !s_output_reg_axis_tvalid));

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_input_to_output = 1'b0;
        store_axis_input_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (s_axis_tready_reg) begin
            // input is ready
            if (m_axis_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = s_output_reg_axis_tvalid;
                store_axis_input_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = s_output_reg_axis_tvalid;
                store_axis_input_to_temp = 1'b1;
            end
        end else if (m_axis_tready) begin
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
            m_axis_tdata_reg <= s_output_reg_axis_tdata;
            m_axis_tkeep_reg <= s_output_reg_axis_tkeep;
            m_axis_tlast_reg <= s_output_reg_axis_tlast;
            m_axis_tuser_reg <= s_output_reg_axis_tuser;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
            m_axis_tuser_reg <= temp_m_axis_tuser_reg;
        end

        if (store_axis_input_to_temp) begin
            temp_m_axis_tdata_reg <= s_output_reg_axis_tdata;
            temp_m_axis_tkeep_reg <= s_output_reg_axis_tkeep;
            temp_m_axis_tlast_reg <= s_output_reg_axis_tlast;
            temp_m_axis_tuser_reg <= s_output_reg_axis_tuser;
        end

        if (rst) begin
            s_axis_tready_reg <= 1'b0;
            m_axis_tvalid_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end



endmodule

`resetall