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

    // Data out
    output wire         m_wr_req_valid,
    input  wire         m_wr_req_ready,
    output wire         m_wr_req_tx_type,
    output wire         m_wr_req_is_immediate,
    output wire [31:0]  m_wr_req_immediate_data,
    output wire [23:0]  m_wr_req_loc_qp,
    output wire [63:0]  m_wr_req_addr_offset,
    output wire [31:0]  m_wr_req_dma_length,

    output  wire [DATA_WIDTH   - 1 :0] m_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_axis_tkeep,
    output  wire                       m_axis_tvalid,
    input   wire                       m_axis_tready,
    output  wire                       m_axis_tlast,
    output  wire                       m_axis_tuser,

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



    // Dummy work request producer
    always @* begin

        wr_req_valid_next = wr_req_valid_reg && !m_wr_req_ready;

        // loop over until all requests are sent
        if (m_wr_req_ready && ~wr_req_valid_reg) begin
            if (messages_to_transfer > 0 && transmit_wait_ctnr == 0) begin
                wr_req_valid_next  = 1'b1;
            end else begin
                wr_req_valid_next = 1'b0;
            end
        end else begin
            wr_req_valid_next = 1'b0;
        end
    end



    always @(posedge clk) begin

        if (rst)  begin
            transmit_wait_ctnr    <= {64{1'b1}};
            wr_req_loc_qp         <= 0;
            wr_req_is_immediate   <= 0;
            wr_req_tx_type        <= 0;
            wr_req_dma_length     <= 0;
            messages_to_transfer  <= {32{1'b1}};
            txmeta_frequency_reg  <= 0;
            address_offset        <= 0;
            transfer_ongoing      <= 0;
            wr_req_valid_reg      <= 0;

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
                if (m_wr_req_ready) begin
                    //transmit_wait_ctnr    <= FREQ_CLK_COUNTER_VALUES[txmeta_frequency_reg[4:0]];
                    transmit_wait_ctnr    <= txmeta_frequency_reg;
                end else begin
                    transmit_wait_ctnr <= transmit_wait_ctnr;
                end
            end else if (messages_to_transfer > 0) begin
                transmit_wait_ctnr <= transmit_wait_ctnr - 64'd1;
            end else begin
                transmit_wait_ctnr <= transmit_wait_ctnr;
            end

            // loop over until all requests are sent
            if (messages_to_transfer > 0) begin
                if (m_wr_req_valid && m_wr_req_ready) begin
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

            if (wr_error_qp_not_rts && wr_req_loc_qp == wr_error_loc_qpn) begin // if qp is not in RTS stops the wr genration
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

        .start(m_wr_req_valid && m_wr_req_ready),
        .stop(stop),

        .m_axis_tdata (m_axis_tdata ),
        .m_axis_tkeep (m_axis_tkeep ),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast ),
        .m_axis_tuser (m_axis_tuser ),

        .length(m_wr_req_dma_length)
    );


    assign m_wr_req_valid = wr_req_valid_reg;
    assign m_wr_req_tx_type = wr_req_tx_type;
    assign m_wr_req_is_immediate = wr_req_is_immediate;
    assign m_wr_req_immediate_data = 32'd012345678;
    assign m_wr_req_loc_qp = wr_req_loc_qp;
    assign m_wr_req_addr_offset = address_offset;
    assign m_wr_req_dma_length = wr_req_dma_length; 



endmodule

`resetall