`resetall
`timescale 1ns / 1ps
`default_nettype none

module qpn_fifo_init #
    (
    parameter MAX_QUEUE_PAIRS = 4
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * QPN fifo in, filled if a qp is closed
     */
    input  wire                  s_qpn_fifo_valid,
    output wire                  s_qpn_fifo_ready,
    input  wire [23:0]           s_qpn,
    /*
     * QPN fifo out, read when qp open request 
     */
    output wire                  m_qpn_fifo_valid,
    input  wire                  m_qpn_fifo_ready,
    output wire [23:0]           m_qpn
);

    /*
  Local QP number starts from 2**8 and goes up to 2**8 + 2**(MAX_QUEUE_PAIRS)
  */

    localparam MAX_QUEUE_PAIRS_WIDTH = $clog2(MAX_QUEUE_PAIRS);

    localparam [0:0]
    STATE_IDLE = 1'd0,
    STATE_PASSTHROUGH = 1'b1;

    reg [0:0] state_reg = STATE_IDLE, state_next;

    reg store_qpn;

    reg [23:0] qpn_reg = 24'd0;

    reg qpn_valid_reg = 0, qpn_valid_next;

    reg s_qpn_ready_reg = 1'b0, s_qpn_ready_next;

    reg [MAX_QUEUE_PAIRS_WIDTH:0] fifo_wr_ptr_reg = {MAX_QUEUE_PAIRS_WIDTH+1{1'b0}}, fifo_wr_ptr_next;
    reg [MAX_QUEUE_PAIRS_WIDTH:0] fifo_rd_ptr_reg = {MAX_QUEUE_PAIRS_WIDTH+1{1'b0}}, fifo_rd_ptr_next;

    reg [23:0] qpn_mem[(2**MAX_QUEUE_PAIRS_WIDTH)-1:0];

    reg [23:0] m_qpn_reg = 24'd0;
    reg m_qpn_valid_reg = 1'b0, m_qpn_valid_next;

    // full when first MSB different but rest same
    wire fifo_full = ((fifo_wr_ptr_reg[MAX_QUEUE_PAIRS_WIDTH] != fifo_rd_ptr_reg[MAX_QUEUE_PAIRS_WIDTH]) &&
    (fifo_wr_ptr_reg[MAX_QUEUE_PAIRS_WIDTH-1:0] == fifo_rd_ptr_reg[MAX_QUEUE_PAIRS_WIDTH-1:0]));
    // empty when pointers match exactly
    wire fifo_empty = fifo_wr_ptr_reg == fifo_rd_ptr_reg;

    // control signals
    reg fifo_write;
    reg fifo_read;

    wire fifo_ready = !fifo_full;

    integer i;

    assign m_qpn_fifo_valid = m_qpn_valid_reg;

    assign m_qpn = m_qpn_reg;
    

    // Write logic
    always @* begin
        fifo_write = 1'b0;

        fifo_wr_ptr_next = fifo_wr_ptr_reg;

        if (qpn_valid_reg) begin
            // input data valid
            if (~fifo_full) begin
                // not full, perform write
                fifo_write = 1'b1;
                fifo_wr_ptr_next = fifo_wr_ptr_reg + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < MAX_QUEUE_PAIRS; i = i + 1) begin
                qpn_mem[i] <= 24'd256 + i;
            end
            fifo_wr_ptr_reg <= {1'b1, {MAX_QUEUE_PAIRS_WIDTH{1'b0}}}; // initialize fifo full
        end else begin
            fifo_wr_ptr_reg <= fifo_wr_ptr_next;
        end

        if (fifo_write) begin
            qpn_mem[fifo_wr_ptr_reg[MAX_QUEUE_PAIRS_WIDTH-1:0]] <= qpn_reg;
        end
    end


    // Read logic
    always @* begin
        fifo_read = 1'b0;

        fifo_rd_ptr_next = fifo_rd_ptr_reg;

        m_qpn_valid_next = m_qpn_valid_reg;

        if (m_qpn_fifo_ready || !m_qpn_fifo_valid) begin
            // output data not valid OR currently being transferred
            if (!fifo_empty) begin
                // not empty, perform read
                fifo_read = 1'b1;
                m_qpn_valid_next = 1'b1;
                fifo_rd_ptr_next = fifo_rd_ptr_reg + 1;
            end else begin
                // empty, invalidate
                m_qpn_valid_next = 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            fifo_rd_ptr_reg <= {MAX_QUEUE_PAIRS_WIDTH+1{1'b0}};
            m_qpn_valid_reg <= 1'b0;
        end else begin
            fifo_rd_ptr_reg <= fifo_rd_ptr_next;
            m_qpn_valid_reg    <= m_qpn_valid_next;
        end

        if (fifo_read) begin
            m_qpn_reg <= qpn_mem[fifo_rd_ptr_reg[MAX_QUEUE_PAIRS_WIDTH-1:0]];
        end
    end

    assign s_qpn_fifo_ready = s_qpn_ready_reg;

    always @* begin
        state_next = STATE_IDLE;

        s_qpn_ready_next = 1'b0;
        store_qpn = 1'b0;

        qpn_valid_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state
                s_qpn_ready_next = fifo_ready;

                if (s_qpn_fifo_ready && s_qpn_fifo_valid) begin
                    store_qpn = 1'b1;

                    s_qpn_ready_next = 1'b0;
                    state_next = STATE_PASSTHROUGH;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_PASSTHROUGH: begin
                qpn_valid_next = 1;
                state_next = STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;
            s_qpn_ready_reg <= 1'b0;
            qpn_valid_reg <= 1'b0;
        end else begin
            state_reg <= state_next;

            s_qpn_ready_reg <= s_qpn_ready_next;

            qpn_valid_reg <= qpn_valid_next;
        end

        // datapath
        if (store_qpn) begin
            qpn_reg <= s_qpn;
        end
    end

endmodule

`resetall