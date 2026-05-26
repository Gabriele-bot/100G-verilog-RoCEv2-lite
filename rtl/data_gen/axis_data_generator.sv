`resetall
`timescale 1ns / 1ps
`default_nettype none


module axis_data_generator #(
    parameter DATA_WIDTH = 64
) (
    input  wire clk,
    input  wire rst,

    input  wire rst_word_ctr,

    input  wire start,
    input  wire stop,

    
    output wire [DATA_WIDTH   - 1 : 0] m_axis_tdata,
    output wire [DATA_WIDTH/8 - 1 : 0] m_axis_tkeep,
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire                         m_axis_tlast,
    output wire                         m_axis_tuser,

    // config
    input  wire [31:0] length
);

    localparam KEEP_WIDTH       = DATA_WIDTH / 8;
    localparam COUNT_KEEP_WIDTH = $clog2(KEEP_WIDTH);
    localparam SLICES_32BIT     = DATA_WIDTH / 32;
    localparam WORD_WIDTH       = KEEP_WIDTH;  

    integer i;

    function [KEEP_WIDTH - 1 : 0] count2keep;
        input [$clog2(KEEP_WIDTH) : 0] k;
        reg [2*KEEP_WIDTH - 1 : 0] temp_ones;
        reg [2*KEEP_WIDTH - 1 : 0] temp_srl;
        begin
            temp_ones = {{KEEP_WIDTH{1'b0}}, {KEEP_WIDTH{1'b1}}};
            if (k < KEEP_WIDTH) begin
                temp_srl  = temp_ones << k;
                count2keep = temp_srl[KEEP_WIDTH +: KEEP_WIDTH];
            end else begin
                count2keep = {KEEP_WIDTH{1'b1}};
            end
        end
    endfunction

    reg start_1, start_2;

    reg [31:0] length_reg;

    reg [31:0] word_counter;

    reg [33:0] word_counter_out;
    reg [31:0] tot_word_ctr;

    reg [KEEP_WIDTH - 1 : 0] tkeep_reg;
    reg                       tlast_reg;

    reg tvalid_reg;

    reg stop_transfer_reg;

    reg approaching_last;

    function [KEEP_WIDTH - 1 : 0] last_beat_tkeep;
        input [31:0] len;
        begin
            if (len[COUNT_KEEP_WIDTH - 1 : 0] == {COUNT_KEEP_WIDTH{1'b0}} && |(len[31:COUNT_KEEP_WIDTH]))
                last_beat_tkeep = {KEEP_WIDTH{1'b1}};
            else
                last_beat_tkeep = count2keep(len[COUNT_KEEP_WIDTH - 1 : 0]);
        end
    endfunction

    wire [DATA_WIDTH   - 1 : 0] s_output_reg_axis_tdata;
    wire [KEEP_WIDTH   - 1 : 0] s_output_reg_axis_tkeep;
    wire                         s_output_reg_axis_tvalid;
    wire                         s_output_reg_axis_tready;
    wire                         s_output_reg_axis_tlast;
    wire                         s_output_reg_axis_tuser;

    
    reg [31:0] both_up_input,  both_up_output;
    reg [31:0] valid_input,    valid_output;

    always @(posedge clk) begin
        if (rst || (~start_1 && start)) begin
            both_up_input  <= 0;
            both_up_output <= 0;
            valid_input    <= 0;
            valid_output   <= 0;
        end else begin
            if (s_output_reg_axis_tvalid && s_output_reg_axis_tready)
                both_up_input <= both_up_input + 1;
            if (s_output_reg_axis_tvalid)
                valid_input <= valid_input + 1;
            if (m_axis_tvalid && m_axis_tready)
                both_up_output <= both_up_output + 1;
            if (m_axis_tvalid)
                valid_output <= valid_output + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            word_counter      <= 32'd0;
            word_counter_out  <= 34'd0;
            tot_word_ctr      <= 32'd0;
            length_reg        <= 32'd0;
            tkeep_reg         <= {KEEP_WIDTH{1'b0}};
            tlast_reg         <= 1'b0;
            tvalid_reg        <= 1'b0;          
            stop_transfer_reg <= 1'b0;
            approaching_last  <= 1'b0;
            start_1           <= 1'b0;
            start_2           <= 1'b0;
        end else begin
            start_1 <= start;
            start_2 <= start_1;

            if (rst_word_ctr) begin
                word_counter_out <= 34'd0;
                tot_word_ctr     <= 32'd0;
            end

            if (stop) begin
                stop_transfer_reg <= 1'b1;
                if (length_reg == 0) begin
                    
                    tvalid_reg <= 1'b0;
                    tkeep_reg  <= {KEEP_WIDTH{1'b0}};
                    tlast_reg  <= 1'b0;
                end else begin
                    
                    tkeep_reg <= {KEEP_WIDTH{1'b1}};
                    tlast_reg <= 1'b1;
                end
            end

            else if (s_output_reg_axis_tvalid && s_output_reg_axis_tready) begin

                word_counter     <= word_counter + WORD_WIDTH;
                word_counter_out <= word_counter_out + WORD_WIDTH;

                if (s_output_reg_axis_tlast) begin
                    
                    tvalid_reg        <= 1'b0;
                    tkeep_reg         <= {KEEP_WIDTH{1'b0}};
                    tlast_reg         <= 1'b0;
                    approaching_last  <= 1'b0;
                    stop_transfer_reg <= 1'b0;
                    word_counter      <= 32'd0;
                    tot_word_ctr      <= tot_word_ctr + length_reg;
                    length_reg        <= 32'd0;

                end else begin
                    
                    if (approaching_last) begin
                        tkeep_reg <= last_beat_tkeep(length_reg);
                        tlast_reg <= 1'b1;
                    end else begin
                        tkeep_reg <= {KEEP_WIDTH{1'b1}};
                        tlast_reg <= 1'b0;
                    end

                    approaching_last <= ((word_counter + 3*WORD_WIDTH) >= length_reg);
                end
            end

            else if (~start_1 && start) begin
                stop_transfer_reg <= 1'b0;
                length_reg        <= length;
                word_counter      <= 32'd0;

                tvalid_reg       <= 1'b0;

                approaching_last <= (length <= WORD_WIDTH);
            end

            else if (~start_2 && start_1) begin
                stop_transfer_reg <= 1'b0;
                word_counter      <= 32'd0;
                word_counter_out  <= (!rst_word_ctr) ? tot_word_ctr : 34'd0;
                tvalid_reg        <= 1'b1;   

                if (length_reg == WORD_WIDTH) begin
                    
                    tkeep_reg        <= {KEEP_WIDTH{1'b1}};
                    tlast_reg        <= 1'b1;
                    approaching_last <= 1'b0;
                end else if (length_reg < WORD_WIDTH) begin
                    
                    tkeep_reg        <= count2keep(length_reg[COUNT_KEEP_WIDTH - 1 : 0]);
                    tlast_reg        <= 1'b1;
                    approaching_last <= 1'b0;
                end else begin
                    
                    tkeep_reg        <= {KEEP_WIDTH{1'b1}};
                    tlast_reg        <= 1'b0;
                    
                    approaching_last <= (WORD_WIDTH + WORD_WIDTH >= length_reg);
                end
            end

            if (s_output_reg_axis_tvalid && s_output_reg_axis_tready &&
                s_output_reg_axis_tlast) begin
                stop_transfer_reg <= 1'b0;
            end

        end
    end 

    generate
        assign s_output_reg_axis_tdata[31:0] = word_counter_out[33:2];
        for (genvar j = 1; j < SLICES_32BIT; j = j + 1) begin : gen_tdata
            assign s_output_reg_axis_tdata[j*32 +: 32] = word_counter_out[33:2] + j;
            // each valid transfer the word counter signal is increased by WORD_WIDTH
            // The value in the tdata field is defined as the following:
            // divide word counter by 4 (to count the single 32bit slice) and add the slice number
            // e.g. in a 512b axis frame there are 16 slices -- WORD_WIDTH = 16
            //the structure is the following 
            // [31 :0  ] : 32'h0000_0000
            // [63 :32 ] : 32'h0000_0001
            // [95 :64 ] : 32'h0000_0002
            // [XX :XX ] : 32'h----_----
            // [511:480] : 32'h0000_000F
            // then the next frame
            // [31 :0  ] : 32'h0000_0010 and so on

        end
    endgenerate

    assign s_output_reg_axis_tkeep  = tkeep_reg;
    assign s_output_reg_axis_tvalid = tvalid_reg;  
    assign s_output_reg_axis_tlast  = tlast_reg;
    assign s_output_reg_axis_tuser  = stop_transfer_reg & tvalid_reg;

    reg                  s_axis_tready_reg;

    reg [DATA_WIDTH-1:0] m_axis_tdata_reg;
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg;
    reg                  m_axis_tvalid_reg,      m_axis_tvalid_next;
    reg                  m_axis_tlast_reg;
    reg                  m_axis_tuser_reg;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg;
    reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg;
    reg                  temp_m_axis_tvalid_reg, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg;
    reg                  temp_m_axis_tuser_reg;

    reg store_axis_input_to_output;
    reg store_axis_input_to_temp;
    reg store_axis_temp_to_output;

    assign s_output_reg_axis_tready = s_axis_tready_reg;

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tkeep  = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tlast_reg;
    assign m_axis_tuser  = m_axis_tuser_reg;

    wire s_axis_tready_early =
        m_axis_tready ||
        (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !s_output_reg_axis_tvalid));

    always @* begin
        m_axis_tvalid_next      = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_input_to_output = 1'b0;
        store_axis_input_to_temp   = 1'b0;
        store_axis_temp_to_output  = 1'b0;

        if (s_axis_tready_reg) begin
            if (m_axis_tready || !m_axis_tvalid_reg) begin
                // Output slot free — send directly
                m_axis_tvalid_next         = s_output_reg_axis_tvalid;
                store_axis_input_to_output = 1'b1;
            end else begin
                // Output busy — stash in temp
                temp_m_axis_tvalid_next  = s_output_reg_axis_tvalid;
                store_axis_input_to_temp = 1'b1;
            end
        end else if (m_axis_tready) begin
            // Input not ready but downstream drained — promote temp to output
            m_axis_tvalid_next      = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        s_axis_tready_reg      <= s_axis_tready_early;
        m_axis_tvalid_reg      <= m_axis_tvalid_next;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

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
            s_axis_tready_reg      <= 1'b0;
            m_axis_tvalid_reg      <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall