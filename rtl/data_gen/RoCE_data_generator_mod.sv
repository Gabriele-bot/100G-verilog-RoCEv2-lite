`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_data_generator #(
    parameter DATA_WIDTH = 64
) (

    input wire clk,
    input wire rst,

    input wire rst_word_ctr,

    input wire stop,

    input wire        txmeta_valid,
    input wire        txmeta_start_transfer,
    input wire [23:0] txmeta_loc_qpn,
    input wire        txmeta_is_immediate,
    input wire        txmeta_tx_type,
    input wire [31:0] txmeta_dma_transfer,
    input wire [31:0] txmeta_n_transfers,
    input wire [31:0] txmeta_frequency,

    // axis stream (merged: metadata in tuser/tdest on first beat of each packet)
    // tuser layout: [0]=bad_frame, [32:1]=dma_length, [96:33]=addr_offset,
    //               [128:97]=immediate_data, [129]=is_immediate, [130]=tx_type
    // tdest layout: [23:0]=loc_qp
    output  wire [DATA_WIDTH   - 1 :0] m_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_axis_tkeep,
    output  wire                       m_axis_tvalid,
    input   wire                       m_axis_tready,
    output  wire                       m_axis_tlast,
    output  wire [130              :0] m_axis_tuser,
    output  wire [23               :0] m_axis_tdest,

    input wire        wr_error_qp_not_rts,
    input wire [23:0] wr_error_loc_qpn
);

    reg wr_req_valid_reg = 1'b0, wr_req_valid_next;
    reg [31:0] txmeta_frequency_reg;
    reg [63:0] transmit_wait_ctnr; // wait counter trasnfering at a given frequency
    reg [31:0] freq_counter_reg;

    reg [23:0] wr_req_loc_qp;
    reg [31:0] wr_req_dma_length;
    reg        wr_req_is_immediate;
    reg        wr_req_tx_type;
    reg [31:0] messages_to_transfer;
    reg [15:0] address_offset;

    reg transfer_ongoing;
    reg first_beat_pending_reg;  // set when start fires, cleared when first beat is accepted

    wire m_axis_tuser_bad_frame;
    wire first_beat_accepted = m_axis_tvalid && m_axis_tready && first_beat_pending_reg;

    // Pulse wr_req_valid_reg when downstream tready is high and conditions are met.
    // This also fires start for the data generator (one cycle pulse).
    always @* begin
        wr_req_valid_next = 1'b0;
        if (m_axis_tready && ~wr_req_valid_reg && ~first_beat_pending_reg) begin
            if (messages_to_transfer > 0 && transmit_wait_ctnr == 0) begin
                wr_req_valid_next = 1'b1;
            end
        end
    end



    always @(posedge clk) begin

        if (rst)  begin
            transmit_wait_ctnr    <= {64{1'b1}};
            wr_req_loc_qp         <= 0;
            wr_req_is_immediate   <= 0;
            wr_req_tx_type        <= 0;
            wr_req_dma_length     <= 0;
            messages_to_transfer  <= {32{1'b0}};
            txmeta_frequency_reg  <= 0;
            address_offset        <= 0;
            transfer_ongoing      <= 0;
            wr_req_valid_reg      <= 0;
            first_beat_pending_reg <= 0;

        end else begin
            // load request only
            if (txmeta_valid && txmeta_start_transfer && ~transfer_ongoing) begin
                wr_req_loc_qp         <= txmeta_loc_qpn;
                wr_req_is_immediate   <= txmeta_is_immediate;
                wr_req_tx_type        <= txmeta_tx_type;
                wr_req_dma_length     <= txmeta_dma_transfer;
                messages_to_transfer  <= txmeta_n_transfers;
                txmeta_frequency_reg  <= txmeta_frequency;
                address_offset        <= 16'd0;
                transfer_ongoing      <= 1'b1;
            end

            if (txmeta_valid && txmeta_start_transfer && ~transfer_ongoing) begin
                //transmit_wait_ctnr    <= FREQ_CLK_COUNTER_VALUES[txmeta_frequency[4:0]];
                transmit_wait_ctnr    <= txmeta_frequency;
                freq_counter_reg      <= txmeta_frequency;
            end else if (transmit_wait_ctnr == 64'd0) begin
                if (wr_req_valid_reg) begin
                    //transmit_wait_ctnr    <= FREQ_CLK_COUNTER_VALUES[txmeta_frequency_reg[4:0]];
                    transmit_wait_ctnr    <= txmeta_frequency_reg;
                end
            end else if (messages_to_transfer > 0) begin
                transmit_wait_ctnr <= transmit_wait_ctnr - 64'd1;
            end

            // Track first-beat window: set when start fires, clear when first beat accepted
            if (wr_req_valid_reg) begin
                first_beat_pending_reg <= 1'b1;
            end else if (first_beat_accepted) begin
                first_beat_pending_reg <= 1'b0;
            end

            // Count transfers on first-beat acceptance (metadata captured by downstream)
            if (messages_to_transfer > 0) begin
                if (first_beat_accepted) begin
                    messages_to_transfer <= messages_to_transfer - 32'd1;
                    if (wr_req_dma_length <= 32'h10000000) begin
                        address_offset <= address_offset + wr_req_dma_length[15:0];
                    end else begin
                        address_offset <= 16'd0;
                    end
                end
            end else if (txmeta_valid && txmeta_start_transfer && ~transfer_ongoing) begin
                transfer_ongoing    <= 1'b1;
            end else begin
                transfer_ongoing    <= 1'b0;
            end

            wr_req_valid_reg <= wr_req_valid_next;

            if ((wr_error_qp_not_rts && wr_req_loc_qp == wr_error_loc_qpn) || stop) begin // if qp is not in RTS stops the wr generation
                messages_to_transfer <= 32'd0;
            end
        end
    end

    /*
     * Generate payolad data
     */
    axis_data_generator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) axis_data_generator_instance (
        .clk(clk),
        .rst(rst),

        .rst_word_ctr(rst_word_ctr),

        .start(wr_req_valid_reg),
        .stop(stop),

        .m_axis_tdata (m_axis_tdata ),
        .m_axis_tkeep (m_axis_tkeep ),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast ),
        .m_axis_tuser (m_axis_tuser_bad_frame),

        .length(wr_req_dma_length)
    );

    assign m_axis_tuser = {
        wr_req_tx_type,               // [130]
        wr_req_is_immediate,          // [129]
        32'd012345678,                // [128:97] immediate_data
        {48'd0, address_offset},      // [96:33]  addr_offset
        wr_req_dma_length,            // [32:1]   dma_length
        m_axis_tuser_bad_frame        // [0]      bad_frame
    };
    assign m_axis_tdest = wr_req_loc_qp;



endmodule

`resetall