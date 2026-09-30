
`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * RoCE CNP receiver (BTH payload in, CNP frame out)
 *
 * Consumes the BTH payload stream for a Congestion Notification Packet
 * (CNP, opcode 0x81).  After the BTH the payload contains 8 reserved
 * bytes followed by the 4-byte ICRC.  No further payload stream is produced.
 *
 * CNP BTH-payload layout (12 bytes):
 *  Bytes 0-7 : Reserved (must be zero)
 *  Bytes 8-11: ICRC
 */
module RoCE_cnp_bth_rx #(
    parameter DATA_WIDTH  = 256,
    parameter KEEP_ENABLE = (DATA_WIDTH > 8),
    parameter KEEP_WIDTH  = (DATA_WIDTH / 8)
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE BTH frame input  (BTH fields + BTH payload stream)
     */
    input  wire        s_roce_bth_hdr_valid,
    output wire        s_roce_bth_hdr_ready,
    input  wire [ 7:0] s_roce_bth_op_code,
    input  wire        s_roce_bth_sol_event,
    input  wire        s_roce_bth_mig_req,
    input  wire [ 1:0] s_roce_bth_pad_count,
    input  wire [ 3:0] s_roce_bth_hdr_version,
    input  wire [15:0] s_roce_bth_p_key,
    input  wire        s_roce_bth_fecn,
    input  wire        s_roce_bth_becn,
    input  wire [23:0] s_roce_bth_dest_qp,
    input  wire        s_roce_bth_ack_req,
    input  wire [23:0] s_roce_bth_psn,
    // BTH payload = Reserved (8 B) + ICRC (4 B)
    input  wire [DATA_WIDTH-1:0] s_roce_bth_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_roce_bth_payload_axis_tkeep,
    input  wire                  s_roce_bth_payload_axis_tvalid,
    output wire                  s_roce_bth_payload_axis_tready,
    input  wire                  s_roce_bth_payload_axis_tlast,
    input  wire                  s_roce_bth_payload_axis_tuser,

    /*
     * CNP frame output  (header fields only – no payload stream)
     */
    output wire        m_roce_cnp_hdr_valid,
    input  wire        m_roce_cnp_hdr_ready,
    // pass-through BTH fields
    output wire [ 7:0] m_roce_bth_op_code,
    output wire        m_roce_bth_sol_event,
    output wire        m_roce_bth_mig_req,
    output wire [ 1:0] m_roce_bth_pad_count,
    output wire [ 3:0] m_roce_bth_hdr_version,
    output wire [15:0] m_roce_bth_p_key,
    output wire        m_roce_bth_fecn,
    output wire        m_roce_bth_becn,
    output wire [23:0] m_roce_bth_dest_qp,
    output wire        m_roce_bth_ack_req,
    output wire [23:0] m_roce_bth_psn,
    // ICRC
    output wire [31:0] m_roce_icrc,

    /*
     * Status
     */
    output wire busy,
    output wire error_header_early_termination
);
    /* 
    +--------------------------------------+
    |               CNP (ignered)          |
    +--------------------------------------+
    Field                       Length
    Ignored                    8 octets
    +--------------------------------------+
    |               ICRC                   |
    +--------------------------------------+
    Field                       Length
    ICRC field                  4 octets
    */

    parameter BYTE_LANES  = KEEP_ENABLE ? KEEP_WIDTH : 1;
    parameter HDR_SIZE    = 12; // Reserved 8 B + ICRC 4 B
    parameter CYCLE_COUNT = (HDR_SIZE + BYTE_LANES - 1) / BYTE_LANES;
    parameter PTR_WIDTH   = $clog2(CYCLE_COUNT > 1 ? CYCLE_COUNT : 2);

    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end

    reg active_reg = 1'b0, active_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg store_bth_hdr;

    reg s_roce_bth_hdr_ready_reg             = 1'b0, s_roce_bth_hdr_ready_next;
    reg s_roce_bth_payload_axis_tready_reg   = 1'b0, s_roce_bth_payload_axis_tready_next;

    reg m_roce_cnp_hdr_valid_reg = 1'b0, m_roce_cnp_hdr_valid_next;

    reg [ 7:0] m_roce_bth_op_code_reg      = 8'd0;
    reg        m_roce_bth_sol_event_reg    = 1'b0;
    reg        m_roce_bth_mig_req_reg      = 1'b0;
    reg [ 1:0] m_roce_bth_pad_count_reg   = 2'd0;
    reg [ 3:0] m_roce_bth_hdr_version_reg = 4'd0;
    reg [15:0] m_roce_bth_p_key_reg       = 16'd0;
    reg        m_roce_bth_fecn_reg        = 1'b0;
    reg        m_roce_bth_becn_reg        = 1'b0;
    reg [23:0] m_roce_bth_dest_qp_reg    = 24'd0;
    reg        m_roce_bth_ack_req_reg     = 1'b0;
    reg [23:0] m_roce_bth_psn_reg        = 24'd0;

    reg [31:0] m_roce_icrc_reg = 32'd0, m_roce_icrc_next;

    reg busy_reg                           = 1'b0;
    reg error_header_early_termination_reg = 1'b0, error_header_early_termination_next;

    assign s_roce_bth_hdr_ready            = s_roce_bth_hdr_ready_reg;
    assign s_roce_bth_payload_axis_tready  = s_roce_bth_payload_axis_tready_reg;
    assign m_roce_cnp_hdr_valid            = m_roce_cnp_hdr_valid_reg;

    assign m_roce_bth_op_code              = m_roce_bth_op_code_reg;
    assign m_roce_bth_sol_event            = m_roce_bth_sol_event_reg;
    assign m_roce_bth_mig_req              = m_roce_bth_mig_req_reg;
    assign m_roce_bth_pad_count            = m_roce_bth_pad_count_reg;
    assign m_roce_bth_hdr_version          = m_roce_bth_hdr_version_reg;
    assign m_roce_bth_p_key                = m_roce_bth_p_key_reg;
    assign m_roce_bth_fecn                 = m_roce_bth_fecn_reg;
    assign m_roce_bth_becn                 = m_roce_bth_becn_reg;
    assign m_roce_bth_dest_qp              = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req              = m_roce_bth_ack_req_reg;
    assign m_roce_bth_psn                  = m_roce_bth_psn_reg;
    assign m_roce_icrc                     = m_roce_icrc_reg;
    assign busy                            = busy_reg;
    assign error_header_early_termination  = error_header_early_termination_reg;

    always @* begin
        active_next = active_reg;
        ptr_next    = ptr_reg;

        m_roce_cnp_hdr_valid_next = m_roce_cnp_hdr_valid_reg && !m_roce_cnp_hdr_ready;

        s_roce_bth_hdr_ready_next           = !m_roce_cnp_hdr_valid_next && !active_reg;
        s_roce_bth_payload_axis_tready_next = active_reg;

        store_bth_hdr                       = 1'b0;
        error_header_early_termination_next = 1'b0;

        m_roce_icrc_next = m_roce_icrc_reg;

        if (s_roce_bth_hdr_valid && s_roce_bth_hdr_ready) begin
            store_bth_hdr                       = 1'b1;
            active_next                         = 1'b1;
            ptr_next                            = 0;
            s_roce_bth_hdr_ready_next           = 1'b0;
            s_roce_bth_payload_axis_tready_next = 1'b1;
        end

        if (s_roce_bth_payload_axis_tvalid && s_roce_bth_payload_axis_tready) begin
            ptr_next = ptr_reg + 1;

            // bytes 0-7 are ignerd by the receiver
        `define _HEADER_FIELD_(offset, field) \
            if (ptr_reg == offset/BYTE_LANES && \
                (!KEEP_ENABLE || s_roce_bth_payload_axis_tkeep[offset % BYTE_LANES])) begin \
                field = s_roce_bth_payload_axis_tdata[(offset % BYTE_LANES)*8 +: 8]; \
            end

            `_HEADER_FIELD_( 8, m_roce_icrc_next[3*8 +: 8])
            `_HEADER_FIELD_( 9, m_roce_icrc_next[2*8 +: 8])
            `_HEADER_FIELD_(10, m_roce_icrc_next[1*8 +: 8])
            `_HEADER_FIELD_(11, m_roce_icrc_next[0*8 +: 8])

        `undef _HEADER_FIELD_

            if (s_roce_bth_payload_axis_tlast) begin
                active_next                         = 1'b0;
                ptr_next                            = 0;
                s_roce_bth_payload_axis_tready_next = 1'b0;

                if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES) begin
                    m_roce_cnp_hdr_valid_next = 1'b1;
                end else begin
                    error_header_early_termination_next = 1'b1;
                end
            end
        end
    end

    
    always @(posedge clk) begin
        active_reg <= active_next;
        ptr_reg    <= ptr_next;

        s_roce_bth_hdr_ready_reg           <= s_roce_bth_hdr_ready_next;
        s_roce_bth_payload_axis_tready_reg <= s_roce_bth_payload_axis_tready_next;
        m_roce_cnp_hdr_valid_reg           <= m_roce_cnp_hdr_valid_next;

        if (store_bth_hdr) begin
            m_roce_bth_op_code_reg      <= s_roce_bth_op_code;
            m_roce_bth_sol_event_reg    <= s_roce_bth_sol_event;
            m_roce_bth_mig_req_reg      <= s_roce_bth_mig_req;
            m_roce_bth_pad_count_reg    <= s_roce_bth_pad_count;
            m_roce_bth_hdr_version_reg  <= s_roce_bth_hdr_version;
            m_roce_bth_p_key_reg        <= s_roce_bth_p_key;
            m_roce_bth_fecn_reg         <= s_roce_bth_fecn;
            m_roce_bth_becn_reg         <= s_roce_bth_becn;
            m_roce_bth_dest_qp_reg      <= s_roce_bth_dest_qp;
            m_roce_bth_ack_req_reg      <= s_roce_bth_ack_req;
            m_roce_bth_psn_reg          <= s_roce_bth_psn;
        end

        m_roce_icrc_reg <= m_roce_icrc_next;

        error_header_early_termination_reg <= error_header_early_termination_next;
        busy_reg <= active_next;

        if (rst) begin
            active_reg                         <= 1'b0;
            ptr_reg                            <= 0;
            s_roce_bth_hdr_ready_reg           <= 1'b0;
            s_roce_bth_payload_axis_tready_reg <= 1'b0;
            m_roce_cnp_hdr_valid_reg           <= 1'b0;
            busy_reg                           <= 1'b0;
            error_header_early_termination_reg <= 1'b0;
        end
    end

endmodule

`resetall
