`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * IP ethernet frame receiver (IP frame in, UDP frame out)
 */
module header_stripper #
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // header width in bytes
    parameter OUT_HEADER_WIDTH = 12,
    // header width to pass to next module
    parameter IN_HEADER_WIDTH= 16
)
(
    input  wire                  clk,
    input  wire                  rst,
    /*
     * UDP frame input
     */
    // BTH
    input  wire                           s_hdr_valid,
    output wire                           s_hdr_ready,
    input  wire [IN_HEADER_WIDTH*8  -1:0] s_hdr_in,
    // payload
    input  wire [DATA_WIDTH-1   : 0] s_payload_axis_tdata,
    input  wire [DATA_WIDTH/8-1 : 0] s_payload_axis_tkeep,
    input  wire                      s_payload_axis_tvalid,
    output wire                      s_payload_axis_tready,
    input  wire                      s_payload_axis_tlast,
    input  wire                      s_payload_axis_tuser,

    /*
     * UDP frame output
     */
    output wire                           m_hdr_valid,
    input  wire                           m_hdr_ready,
    output wire [IN_HEADER_WIDTH*8  -1:0] m_hdr_pt, //passthrough
    output wire [OUT_HEADER_WIDTH*8 -1:0] m_hdr_out,

    output wire [DATA_WIDTH-1   : 0] m_payload_axis_tdata,
    output wire [DATA_WIDTH/8-1 : 0] m_payload_axis_tkeep,
    output wire                      m_payload_axis_tvalid,
    input  wire                      m_payload_axis_tready,
    output wire                      m_payload_axis_tlast,
    output wire                      m_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    output wire        error_header_early_termination,
    output wire        error_payload_early_termination
);

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    parameter HDR_SIZE = OUT_HEADER_WIDTH;

    parameter CYCLE_COUNT = (HDR_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

    parameter OFFSET = HDR_SIZE % BYTE_LANES;

    // bus width assertions
    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end

    reg read_header_reg = 1'b1, read_header_next;
    reg read_payload_reg = 1'b0, read_payload_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    // datapath control signals
    reg store_hdr;

    reg flush_save;
    reg transfer_in_save;

    reg s_hdr_ready_reg = 1'b0, s_hdr_ready_next;
    reg s_payload_axis_tready_reg = 1'b0, s_payload_axis_tready_next;

    reg [15:0] word_count_reg = 16'd0, word_count_next;

    reg m_hdr_valid_reg = 1'b0, m_hdr_valid_next;
    reg [IN_HEADER_WIDTH*8  -1:0] m_hdr_pt_reg, m_hdr_pt_next;
    reg [OUT_HEADER_WIDTH*8  -1:0] m_hdr_out_reg, m_hdr_out_next;

    reg busy_reg = 1'b0;
    reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;
    reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

    reg [DATA_WIDTH-1:0] save_payload_axis_tdata_reg = 64'd0;
    reg [KEEP_WIDTH-1:0] save_payload_axis_tkeep_reg = 8'd0;
    reg save_payload_axis_tlast_reg = 1'b0;
    reg save_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH-1:0] shift_payload_axis_tdata;
    reg [KEEP_WIDTH-1:0] shift_payload_axis_tkeep;
    reg shift_payload_axis_tvalid;
    reg shift_payload_axis_tlast;
    reg shift_payload_axis_tuser;
    reg shift_payload_axis_input_tready;
    reg shift_payload_axis_extra_cycle_reg = 1'b0;

    // internal datapath
    reg [DATA_WIDTH-1:0] m_payload_axis_tdata_int;
    reg [KEEP_WIDTH-1:0] m_payload_axis_tkeep_int;
    reg                  m_payload_axis_tvalid_int;
    reg                  m_payload_axis_tready_int_reg = 1'b0;
    reg                  m_payload_axis_tlast_int;
    reg                  m_payload_axis_tuser_int;
    wire                 m_payload_axis_tready_int_early;

    integer i;

    assign s_hdr_ready = s_hdr_ready_reg;
    assign s_payload_axis_tready = s_payload_axis_tready_reg;

    assign m_hdr_valid = m_hdr_valid_reg;
    assign m_hdr_pt = m_hdr_pt_reg;
    assign m_hdr_out = m_hdr_out_reg;

    assign busy = busy_reg;
    assign error_header_early_termination = error_header_early_termination_reg;
    assign error_payload_early_termination = error_payload_early_termination_reg;

    always @* begin
        if (OFFSET == 0) begin
            // passthrough if no overlap
            shift_payload_axis_tdata  = s_payload_axis_tdata;
            shift_payload_axis_tkeep  = s_payload_axis_tkeep;
            shift_payload_axis_tvalid = s_payload_axis_tvalid;
            shift_payload_axis_tlast  = s_payload_axis_tlast;
            shift_payload_axis_tuser  = s_payload_axis_tuser;
            shift_payload_axis_input_tready = 1'b1;
        end else if (shift_payload_axis_extra_cycle_reg) begin
            shift_payload_axis_tdata = {s_payload_axis_tdata, save_payload_axis_tdata_reg} >> (OFFSET*8);
            shift_payload_axis_tkeep = {{KEEP_WIDTH{1'b0}}, save_payload_axis_tkeep_reg} >> OFFSET;
            shift_payload_axis_tvalid = 1'b1;
            shift_payload_axis_tlast = save_payload_axis_tlast_reg;
            shift_payload_axis_tuser = save_payload_axis_tuser_reg;
            shift_payload_axis_input_tready = flush_save;
        end else begin
            shift_payload_axis_tdata = {s_payload_axis_tdata, save_payload_axis_tdata_reg} >> (OFFSET*8);
            shift_payload_axis_tkeep = {s_payload_axis_tkeep, save_payload_axis_tkeep_reg} >> OFFSET;
            shift_payload_axis_tvalid = s_payload_axis_tvalid;
            shift_payload_axis_tlast = (s_payload_axis_tlast && ((s_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
            shift_payload_axis_tuser = (s_payload_axis_tuser && ((s_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0));
            shift_payload_axis_input_tready = !(s_payload_axis_tlast && s_payload_axis_tready && s_payload_axis_tvalid);
        end
    end

    always @* begin
        read_header_next = read_header_reg;
        read_payload_next = read_payload_reg;
        ptr_next = ptr_reg;

        word_count_next = word_count_reg;

        m_hdr_valid_next = m_hdr_valid_reg && !m_hdr_ready;

        // TODO check this shit
        s_hdr_ready_next = !m_hdr_valid_next;
        store_hdr = 1'b0;

        s_payload_axis_tready_next = m_payload_axis_tready_int_early && shift_payload_axis_input_tready && (!m_hdr_valid || m_hdr_ready);

        flush_save = 1'b0;
        transfer_in_save = 1'b0;

        if (s_hdr_ready && s_hdr_valid) begin
            s_hdr_ready_next = 1'b0;
            s_payload_axis_tready_next = 1'b1;
            store_hdr = 1'b1;
        end

        m_hdr_pt_next = m_hdr_pt_reg;
        m_hdr_out_next = m_hdr_out_reg;

        error_header_early_termination_next = 1'b0;
        error_payload_early_termination_next = 1'b0;

        m_payload_axis_tdata_int = shift_payload_axis_tdata;
        m_payload_axis_tkeep_int = shift_payload_axis_tkeep;
        m_payload_axis_tvalid_int = 1'b0;
        m_payload_axis_tlast_int = shift_payload_axis_tlast;
        m_payload_axis_tuser_int = shift_payload_axis_tuser;

        if ((s_payload_axis_tready && s_payload_axis_tvalid) || (m_payload_axis_tready_int_reg && shift_payload_axis_extra_cycle_reg)) begin
            transfer_in_save = 1'b1;

            if (read_header_reg) begin
                // word transfer in - store it
                ptr_next = ptr_reg + 1; 

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && (!KEEP_ENABLE || s_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

                for (i = 0; i < HDR_SIZE; i = i+1) begin
                    `_HEADER_FIELD_(i,  m_hdr_out_next[i*8 +: 8]);
                end

                if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES && (!KEEP_ENABLE || s_payload_axis_tkeep[(HDR_SIZE-1)%BYTE_LANES])) begin
                    if (!shift_payload_axis_tlast) begin
                        m_hdr_valid_next = 1'b1;
                        read_header_next = 1'b0;
                        read_payload_next = 1'b1;
                    end
                end

            `undef _HEADER_FIELD_
        end

            if (read_payload_reg) begin
                // transfer payload
                m_payload_axis_tdata_int = shift_payload_axis_tdata;
                m_payload_axis_tkeep_int = shift_payload_axis_tkeep;
                m_payload_axis_tvalid_int = 1'b1;
                m_payload_axis_tlast_int = shift_payload_axis_tlast;
                m_payload_axis_tuser_int = shift_payload_axis_tuser;

                word_count_next = word_count_reg - DATA_WIDTH/8;
            end

            if (shift_payload_axis_tlast) begin
                if (read_header_next) begin
                    // don't have the whole header
                    error_header_early_termination_next = 1'b1;
                end
                if (read_payload_next) begin
                    if (word_count_reg >= DATA_WIDTH/4) begin // 2 times the data width in bytes
                        error_payload_early_termination_next = 1'b1;
                    end
                end

                flush_save = 1'b1;
                ptr_next = 1'b0;
                read_header_next = 1'b1;
                read_payload_next = 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        read_header_reg <= read_header_next;
        read_payload_reg <= read_payload_next;
        ptr_reg <= ptr_next;

        word_count_reg <= word_count_next;

        s_hdr_ready_reg <= s_hdr_ready_next;

        s_payload_axis_tready_reg <= s_payload_axis_tready_next;

        m_hdr_valid_reg <= m_hdr_valid_next;

        if (store_hdr) begin
            m_hdr_pt_reg <= s_hdr_in;
        end

        m_hdr_out_reg <= m_hdr_out_next;

        error_header_early_termination_reg  <= error_header_early_termination_next;
        error_payload_early_termination_reg <= error_payload_early_termination_next;

        busy_reg <= (read_payload_next || ptr_next != 0);

        if (transfer_in_save) begin
            save_payload_axis_tdata_reg <= s_payload_axis_tdata;
            save_payload_axis_tkeep_reg <= s_payload_axis_tkeep;
            save_payload_axis_tuser_reg <= s_payload_axis_tuser;
        end

        if (flush_save) begin
            save_payload_axis_tlast_reg <= 1'b0;
            shift_payload_axis_extra_cycle_reg <= 1'b0;
        end else if (transfer_in_save) begin
            save_payload_axis_tlast_reg <= s_payload_axis_tlast;
            shift_payload_axis_extra_cycle_reg <= OFFSET ? s_payload_axis_tlast && ((s_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) != 0) : 1'b0;
        end


        if (rst) begin
            read_header_reg <= 1'b1;
            read_payload_reg <= 1'b0;
            ptr_reg <= 0;
            word_count_reg <= 16'd0;
            s_payload_axis_tready_reg <= 1'b0;
            m_hdr_valid_reg <= 1'b0;
            save_payload_axis_tlast_reg <= 1'b0;
            shift_payload_axis_extra_cycle_reg <= 1'b0;
            busy_reg <= 1'b0;
            error_header_early_termination_reg  <= 1'b0;
            error_payload_early_termination_reg <= 1'b0;
        end
    end

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
    reg                  m_payload_axis_tvalid_reg = 1'b0, m_payload_axis_tvalid_next;
    reg                  m_payload_axis_tlast_reg = 1'b0;
    reg                  m_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
    reg                  temp_m_payload_axis_tvalid_reg = 1'b0, temp_m_payload_axis_tvalid_next;
    reg                  temp_m_payload_axis_tlast_reg = 1'b0;
    reg                  temp_m_payload_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_payload_int_to_output;
    reg store_payload_int_to_temp;
    reg store_payload_axis_temp_to_output;

    assign m_payload_axis_tdata = m_payload_axis_tdata_reg;
    assign m_payload_axis_tkeep = KEEP_ENABLE ? m_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_payload_axis_tvalid = m_payload_axis_tvalid_reg;
    assign m_payload_axis_tlast = m_payload_axis_tlast_reg;
    assign m_payload_axis_tuser = m_payload_axis_tuser_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_payload_axis_tready_int_early = m_payload_axis_tready || (!temp_m_payload_axis_tvalid_reg && !m_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_payload_axis_tvalid_next = m_payload_axis_tvalid_reg;
        temp_m_payload_axis_tvalid_next = temp_m_payload_axis_tvalid_reg;

        store_payload_int_to_output = 1'b0;
        store_payload_int_to_temp = 1'b0;
        store_payload_axis_temp_to_output = 1'b0;

        if (m_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_payload_axis_tready || !m_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_payload_axis_tvalid_next = m_payload_axis_tvalid_int;
                store_payload_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_payload_axis_tvalid_next = m_payload_axis_tvalid_int;
                store_payload_int_to_temp = 1'b1;
            end
        end else if (m_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_payload_axis_tvalid_next = temp_m_payload_axis_tvalid_reg;
            temp_m_payload_axis_tvalid_next = 1'b0;
            store_payload_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_payload_axis_tvalid_reg <= m_payload_axis_tvalid_next;
        m_payload_axis_tready_int_reg <= m_payload_axis_tready_int_early;
        temp_m_payload_axis_tvalid_reg <= temp_m_payload_axis_tvalid_next;

        // datapath
        if (store_payload_int_to_output) begin
            m_payload_axis_tdata_reg <= m_payload_axis_tdata_int;
            m_payload_axis_tkeep_reg <= m_payload_axis_tkeep_int;
            m_payload_axis_tlast_reg <= m_payload_axis_tlast_int;
            m_payload_axis_tuser_reg <= m_payload_axis_tuser_int;
        end else if (store_payload_axis_temp_to_output) begin
            m_payload_axis_tdata_reg <= temp_m_payload_axis_tdata_reg;
            m_payload_axis_tkeep_reg <= temp_m_payload_axis_tkeep_reg;
            m_payload_axis_tlast_reg <= temp_m_payload_axis_tlast_reg;
            m_payload_axis_tuser_reg <= temp_m_payload_axis_tuser_reg;
        end

        if (store_payload_int_to_temp) begin
            temp_m_payload_axis_tdata_reg <= m_payload_axis_tdata_int;
            temp_m_payload_axis_tkeep_reg <= m_payload_axis_tkeep_int;
            temp_m_payload_axis_tlast_reg <= m_payload_axis_tlast_int;
            temp_m_payload_axis_tuser_reg <= m_payload_axis_tuser_int;
        end

        if (rst) begin
            m_payload_axis_tvalid_reg <= 1'b0;
            m_payload_axis_tready_int_reg <= 1'b0;
            temp_m_payload_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall