`resetall `timescale 1ns / 1ps `default_nettype none


module axis_data_generator #(
    parameter DATA_WIDTH = 64
) (

    input wire clk,
    input wire rst,

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

    integer i;
    reg [DATA_WIDTH/8 - 1:0] count2keep_reg [DATA_WIDTH/8 - 1:0];

    //initial begin
    //    for (i = 0; i <= DATA_WIDTH/8 - 1; i = i + 1) begin
    //        count2keep_reg[i] = 0;
    //    end
    //end

    generate
        for (genvar j = 0; j <= DATA_WIDTH/8 - 1; j = j + 1) begin
            if (j == 0) begin
                initial count2keep_reg[j] = {(DATA_WIDTH/8){1'b0}};
            end else begin
                initial count2keep_reg[j] = {{(DATA_WIDTH/8-j){1'b0}}, {(j){1'b1}}};
            end
        end
    endgenerate

    function [$clog2(DATA_WIDTH/8):0] keep2count;
        input [DATA_WIDTH/8 - 1:0] k;
        for (i = DATA_WIDTH/8 - 1; i >= 0; i = i - 1) begin
            if (i == DATA_WIDTH/8 - 1) begin
                if (k[DATA_WIDTH/8 -1]) keep2count = DATA_WIDTH/8;
            end else begin
                if (k[i +: 2] == 2'b01) keep2count = i+1;
                else if (k[i +: 2] == 2'b00) keep2count = 0;
            end
        end
    endfunction

    function [DATA_WIDTH/8 - 1:0] count2keep;
        input [$clog2(DATA_WIDTH/8):0] k;
        if (k < DATA_WIDTH/8) count2keep = count2keep_reg[k];
        else count2keep = {DATA_WIDTH/8{1'b1}};
    endfunction

    parameter SLICES_32BIT = DATA_WIDTH/32;
    parameter WORD_WIDTH   = DATA_WIDTH/8;

    reg [31:0] length_reg;
    reg start_1;
    reg start_2;

    reg [31:0] word_counter = {32{1'b1}} - WORD_WIDTH;
    reg [63:0] remaining_words;

    reg  stop_transfer_reg;

    wire [DATA_WIDTH   - 1 :0] s_output_reg_axis_tdata;
    wire [DATA_WIDTH/8 - 1 :0] s_output_reg_axis_tkeep;
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
            length_reg        <= 32'd0;
            remaining_words   <= 64'd0;
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
                    remaining_words <= 64'd0;
                end else if (s_output_reg_axis_tvalid && s_output_reg_axis_tready) begin // trasnfer on going
                    word_counter <= length_reg;
                    remaining_words <= 64'd0;
                end else begin
                    word_counter <= length_reg - WORD_WIDTH;
                    remaining_words <= WORD_WIDTH;
                end
            end else if (s_output_reg_axis_tvalid && s_output_reg_axis_tready) begin
                if ((word_counter <= length)) begin
                    word_counter <= word_counter + WORD_WIDTH;
                end
                remaining_words <= length_reg - word_counter - WORD_WIDTH;
                if (s_output_reg_axis_tlast) begin
                    word_counter      <= {32{1'b1}} - WORD_WIDTH;
                    length_reg        <= 32'd0;
                    remaining_words   <= 64'd0;
                    stop_transfer_reg <= 1'b0;
                end
            end else if (~start_1 && start) begin
                stop_transfer_reg <= 1'b0;
                length_reg <= length;
                word_counter <= {32{1'b1}} - WORD_WIDTH;
                remaining_words <= length;
            end else if (~start_2 && start_1) begin
                stop_transfer_reg <= 1'b0;
                word_counter <= 0;
                remaining_words <= length_reg;
            end
            if (s_output_reg_axis_tvalid && s_output_reg_axis_tready && s_output_reg_axis_tlast) begin
                stop_transfer_reg <= 1'b0;
            end
        end
    end

    // TDATA
    generate
        assign s_output_reg_axis_tdata[31:0] = word_counter[31:0];
        if (SLICES_32BIT >= 2) begin
            assign s_output_reg_axis_tdata[63:32] = ~word_counter[31:0];
        end
        if (SLICES_32BIT > 2) begin
            assign s_output_reg_axis_tdata[DATA_WIDTH-1:64] = {(SLICES_32BIT-2){32'hDEADBEEF}};
        end
    endgenerate

    // TKEEP
    assign s_output_reg_axis_tkeep = s_output_reg_axis_tlast ? (count2keep(remaining_words)) : {(DATA_WIDTH/8){1'b1}};

    assign s_output_reg_axis_tvalid = ((word_counter < length_reg) ? 1'b1 : 1'b0);
    assign s_output_reg_axis_tlast = ((word_counter + WORD_WIDTH >= length_reg) ? 1'b1 : 1'b0);
    assign s_output_reg_axis_tuser = stop_transfer_reg & s_output_reg_axis_tvalid;


    axis_register #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_ENABLE(1),
        .USER_WIDTH(1)
    ) axis_register_instance (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_output_reg_axis_tdata ),
        .s_axis_tkeep (s_output_reg_axis_tkeep ),
        .s_axis_tvalid(s_output_reg_axis_tvalid),
        .s_axis_tready(s_output_reg_axis_tready),
        .s_axis_tlast (s_output_reg_axis_tlast ),
        .s_axis_tuser (s_output_reg_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_axis_tdata ),
        .m_axis_tkeep (m_axis_tkeep ),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast ),
        .m_axis_tuser (m_axis_tuser )
    );

endmodule

`resetall