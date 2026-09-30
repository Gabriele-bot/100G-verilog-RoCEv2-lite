
`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * RoCE BTH receiver (UDP payload in, RoCE BTH frame out)
 */
module RoCE_bth_udp_rx #(
    parameter DATA_WIDTH  = 256,
    parameter KEEP_ENABLE = (DATA_WIDTH > 8),
    parameter KEEP_WIDTH  = (DATA_WIDTH / 8)
) (
    input wire clk,
    input wire rst,

    /*
     * UDP frame input
     */
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [47:0] s_eth_dest_mac,
    input  wire [47:0] s_eth_src_mac,
    input  wire [15:0] s_eth_type,
    input  wire [ 3:0] s_ip_version,
    input  wire [ 3:0] s_ip_ihl,
    input  wire [ 5:0] s_ip_dscp,
    input  wire [ 1:0] s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [15:0] s_ip_identification,
    input  wire [ 2:0] s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [ 7:0] s_ip_ttl,
    input  wire [ 7:0] s_ip_protocol,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [15:0] s_udp_length,
    input  wire [15:0] s_udp_checksum,
    input  wire [DATA_WIDTH-1:0] s_udp_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_udp_payload_axis_tkeep,
    input  wire                  s_udp_payload_axis_tvalid,
    output wire                  s_udp_payload_axis_tready,
    input  wire                  s_udp_payload_axis_tlast,
    input  wire                  s_udp_payload_axis_tuser,

    /*
     * RoCE BTH frame output
     */
    output wire        m_roce_bth_hdr_valid,
    input  wire        m_roce_bth_hdr_ready,
    output wire [47:0] m_eth_dest_mac,
    output wire [47:0] m_eth_src_mac,
    output wire [15:0] m_eth_type,
    output wire [ 3:0] m_ip_version,
    output wire [ 3:0] m_ip_ihl,
    output wire [ 5:0] m_ip_dscp,
    output wire [ 1:0] m_ip_ecn,
    output wire [15:0] m_ip_length,
    output wire [15:0] m_ip_identification,
    output wire [ 2:0] m_ip_flags,
    output wire [12:0] m_ip_fragment_offset,
    output wire [ 7:0] m_ip_ttl,
    output wire [ 7:0] m_ip_protocol,
    output wire [15:0] m_ip_header_checksum,
    output wire [31:0] m_ip_source_ip,
    output wire [31:0] m_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    // BTH fields
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
    // BTH payload
    output wire [DATA_WIDTH-1:0] m_roce_bth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_roce_bth_payload_axis_tkeep,
    output wire                  m_roce_bth_payload_axis_tvalid,
    input  wire                  m_roce_bth_payload_axis_tready,
    output wire                  m_roce_bth_payload_axis_tlast,
    output wire                  m_roce_bth_payload_axis_tuser,

    /*
     * Status
     */
    output wire busy,
    output wire error_header_early_termination,
    output wire error_payload_early_termination
);

    /* 
    +--------------------------------------+
    |                BTH                   |
    +--------------------------------------+
    Field                       Length
    OP code                     1 octet
    Solicited Event             1 bit
    Mig request                 1 bit
    Pad count                   2 bits
    Header version              4 bits
    Partition key               2 octets
    Reserved                    1 octet
    Queue Pair Number           3 octets
    Ack request                 1 bit
    Reserved                    7 bits
    Packet Sequence Number      3 octets
    */

    parameter BYTE_LANES  = KEEP_ENABLE ? KEEP_WIDTH : 1;
    parameter HDR_SIZE    = 12;
    parameter CYCLE_COUNT = (HDR_SIZE + BYTE_LANES - 1) / BYTE_LANES;
    parameter PTR_WIDTH   = $clog2(CYCLE_COUNT > 1 ? CYCLE_COUNT : 2);
    parameter OFFSET      = HDR_SIZE % BYTE_LANES;

    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end


    reg read_bth_header_reg  = 1'b1, read_bth_header_next;
    reg read_bth_payload_reg = 1'b0, read_bth_payload_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg store_udp_hdr;
    reg flush_save;
    reg transfer_in_save;

    reg s_udp_hdr_ready_reg                = 1'b0, s_udp_hdr_ready_next;
    reg s_udp_payload_axis_tready_reg      = 1'b0, s_udp_payload_axis_tready_next;

    reg [15:0] word_count_reg = 16'd0, word_count_next;


    reg m_roce_bth_hdr_valid_reg = 1'b0, m_roce_bth_hdr_valid_next;

    reg [47:0] m_eth_dest_mac_reg        = 48'd0;
    reg [47:0] m_eth_src_mac_reg         = 48'd0;
    reg [15:0] m_eth_type_reg            = 16'd0;
    reg [ 3:0] m_ip_version_reg          = 4'd0;
    reg [ 3:0] m_ip_ihl_reg              = 4'd0;
    reg [ 5:0] m_ip_dscp_reg             = 6'd0;
    reg [ 1:0] m_ip_ecn_reg              = 2'd0;
    reg [15:0] m_ip_length_reg           = 16'd0;
    reg [15:0] m_ip_identification_reg   = 16'd0;
    reg [ 2:0] m_ip_flags_reg            = 3'd0;
    reg [12:0] m_ip_fragment_offset_reg  = 13'd0;
    reg [ 7:0] m_ip_ttl_reg              = 8'd0;
    reg [ 7:0] m_ip_protocol_reg         = 8'd0;
    reg [15:0] m_ip_header_checksum_reg  = 16'd0;
    reg [31:0] m_ip_source_ip_reg        = 32'd0;
    reg [31:0] m_ip_dest_ip_reg          = 32'd0;
    reg [15:0] m_udp_source_port_reg     = 16'd0;
    reg [15:0] m_udp_dest_port_reg       = 16'd0;
    reg [15:0] m_udp_length_reg          = 16'd0;
    reg [15:0] m_udp_checksum_reg        = 16'd0;

    reg [ 7:0] m_roce_bth_op_code_reg     = 8'd0,  m_roce_bth_op_code_next;
    reg        m_roce_bth_sol_event_reg   = 1'b0,  m_roce_bth_sol_event_next;
    reg        m_roce_bth_mig_req_reg     = 1'b0,  m_roce_bth_mig_req_next;
    reg [ 1:0] m_roce_bth_pad_count_reg  = 2'd0,  m_roce_bth_pad_count_next;
    reg [ 3:0] m_roce_bth_hdr_version_reg= 4'd0,  m_roce_bth_hdr_version_next;
    reg [15:0] m_roce_bth_p_key_reg      = 16'd0, m_roce_bth_p_key_next;
    reg        m_roce_bth_fecn_reg       = 1'b0,  m_roce_bth_fecn_next;
    reg        m_roce_bth_becn_reg       = 1'b0,  m_roce_bth_becn_next;
    reg [23:0] m_roce_bth_dest_qp_reg   = 24'd0, m_roce_bth_dest_qp_next;
    reg        m_roce_bth_ack_req_reg    = 1'b0,  m_roce_bth_ack_req_next;
    reg [23:0] m_roce_bth_psn_reg       = 24'd0, m_roce_bth_psn_next;

    reg [7:0] temp_fecn_becn, temp_ack_req;


    reg busy_reg                                = 1'b0;
    reg error_header_early_termination_reg      = 1'b0, error_header_early_termination_next;
    reg error_payload_early_termination_reg     = 1'b0, error_payload_early_termination_next;



    reg [DATA_WIDTH-1:0] save_udp_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] save_udp_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  save_udp_payload_axis_tlast_reg  = 1'b0;
    reg                  save_udp_payload_axis_tuser_reg  = 1'b0;

    reg [DATA_WIDTH-1:0] shift_udp_payload_axis_tdata;
    reg [KEEP_WIDTH-1:0] shift_udp_payload_axis_tkeep;
    reg                  shift_udp_payload_axis_tvalid;
    reg                  shift_udp_payload_axis_tlast;
    reg                  shift_udp_payload_axis_tuser;
    reg                  shift_udp_payload_axis_input_tready;
    reg                  shift_udp_payload_axis_extra_cycle_reg = 1'b0;


    reg [DATA_WIDTH-1:0] m_roce_bth_payload_axis_tdata_int;
    reg [KEEP_WIDTH-1:0] m_roce_bth_payload_axis_tkeep_int;
    reg                  m_roce_bth_payload_axis_tvalid_int;
    reg                  m_roce_bth_payload_axis_tready_int_reg = 1'b0;
    reg                  m_roce_bth_payload_axis_tlast_int;
    reg                  m_roce_bth_payload_axis_tuser_int;
    wire                 m_roce_bth_payload_axis_tready_int_early;


    assign s_udp_hdr_ready             = s_udp_hdr_ready_reg;
    assign s_udp_payload_axis_tready   = s_udp_payload_axis_tready_reg;

    assign m_roce_bth_hdr_valid        = m_roce_bth_hdr_valid_reg;
    assign m_eth_dest_mac              = m_eth_dest_mac_reg;
    assign m_eth_src_mac               = m_eth_src_mac_reg;
    assign m_eth_type                  = m_eth_type_reg;
    assign m_ip_version                = m_ip_version_reg;
    assign m_ip_ihl                    = m_ip_ihl_reg;
    assign m_ip_dscp                   = m_ip_dscp_reg;
    assign m_ip_ecn                    = m_ip_ecn_reg;
    assign m_ip_length                 = m_ip_length_reg;
    assign m_ip_identification         = m_ip_identification_reg;
    assign m_ip_flags                  = m_ip_flags_reg;
    assign m_ip_fragment_offset        = m_ip_fragment_offset_reg;
    assign m_ip_ttl                    = m_ip_ttl_reg;
    assign m_ip_protocol               = m_ip_protocol_reg;
    assign m_ip_header_checksum        = m_ip_header_checksum_reg;
    assign m_ip_source_ip              = m_ip_source_ip_reg;
    assign m_ip_dest_ip                = m_ip_dest_ip_reg;
    assign m_udp_source_port           = m_udp_source_port_reg;
    assign m_udp_dest_port             = m_udp_dest_port_reg;
    assign m_udp_length                = m_udp_length_reg;
    assign m_udp_checksum              = m_udp_checksum_reg;
    assign m_roce_bth_op_code          = m_roce_bth_op_code_reg;
    assign m_roce_bth_sol_event        = m_roce_bth_sol_event_reg;
    assign m_roce_bth_mig_req          = m_roce_bth_mig_req_reg;
    assign m_roce_bth_pad_count        = m_roce_bth_pad_count_reg;
    assign m_roce_bth_hdr_version      = m_roce_bth_hdr_version_reg;
    assign m_roce_bth_p_key            = m_roce_bth_p_key_reg;
    assign m_roce_bth_fecn             = m_roce_bth_fecn_reg;
    assign m_roce_bth_becn             = m_roce_bth_becn_reg;
    assign m_roce_bth_dest_qp          = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req          = m_roce_bth_ack_req_reg;
    assign m_roce_bth_psn              = m_roce_bth_psn_reg;
    assign busy                        = busy_reg;
    assign error_header_early_termination  = error_header_early_termination_reg;
    assign error_payload_early_termination = error_payload_early_termination_reg;


    always @* begin
        if (OFFSET == 0) begin
            shift_udp_payload_axis_tdata        = s_udp_payload_axis_tdata;
            shift_udp_payload_axis_tkeep        = s_udp_payload_axis_tkeep;
            shift_udp_payload_axis_tvalid       = s_udp_payload_axis_tvalid;
            shift_udp_payload_axis_tlast        = s_udp_payload_axis_tlast;
            shift_udp_payload_axis_tuser        = s_udp_payload_axis_tuser;
            shift_udp_payload_axis_input_tready = 1'b1;
        end else if (shift_udp_payload_axis_extra_cycle_reg) begin
            shift_udp_payload_axis_tdata  = {{DATA_WIDTH{1'b0}}, save_udp_payload_axis_tdata_reg} >> (OFFSET*8);
            shift_udp_payload_axis_tkeep  = {{KEEP_WIDTH{1'b0}}, save_udp_payload_axis_tkeep_reg} >> OFFSET;
            shift_udp_payload_axis_tvalid = 1'b1;
            shift_udp_payload_axis_tlast  = save_udp_payload_axis_tlast_reg;
            shift_udp_payload_axis_tuser  = save_udp_payload_axis_tuser_reg;
            shift_udp_payload_axis_input_tready = flush_save;
        end else begin
            shift_udp_payload_axis_tdata  = {s_udp_payload_axis_tdata, save_udp_payload_axis_tdata_reg} >> (OFFSET*8);
            shift_udp_payload_axis_tkeep  = {s_udp_payload_axis_tkeep, save_udp_payload_axis_tkeep_reg} >> OFFSET;
            shift_udp_payload_axis_tvalid = s_udp_payload_axis_tvalid;
            shift_udp_payload_axis_tlast  = s_udp_payload_axis_tlast &&
            ((s_udp_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0);
            shift_udp_payload_axis_tuser  = s_udp_payload_axis_tuser &&
            ((s_udp_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) == 0);
            shift_udp_payload_axis_input_tready =
            !(s_udp_payload_axis_tlast && s_udp_payload_axis_tready && s_udp_payload_axis_tvalid);
        end
    end


    always @* begin
        read_bth_header_next  = read_bth_header_reg;
        read_bth_payload_next = read_bth_payload_reg;
        ptr_next              = ptr_reg;
        word_count_next       = word_count_reg;

        temp_fecn_becn = 8'h00;
        temp_ack_req = 8'h00;

        m_roce_bth_hdr_valid_next = m_roce_bth_hdr_valid_reg && !m_roce_bth_hdr_ready;

        s_udp_hdr_ready_next            = !m_roce_bth_hdr_valid_next;
        store_udp_hdr                   = 1'b0;
        flush_save                      = 1'b0;
        transfer_in_save                = 1'b0;

        s_udp_payload_axis_tready_next =
        m_roce_bth_payload_axis_tready_int_early &&
        shift_udp_payload_axis_input_tready &&
        (!m_roce_bth_hdr_valid || m_roce_bth_hdr_ready);

        if (s_udp_hdr_ready && s_udp_hdr_valid) begin
            s_udp_hdr_ready_next           = 1'b0;
            s_udp_payload_axis_tready_next = 1'b1;
            store_udp_hdr                  = 1'b1;
            word_count_next                = s_udp_length - 16'd20; // UDP hdr 8B + BTH 12B
        end

        m_roce_bth_op_code_next     = m_roce_bth_op_code_reg;
        m_roce_bth_sol_event_next   = m_roce_bth_sol_event_reg;
        m_roce_bth_mig_req_next     = m_roce_bth_mig_req_reg;
        m_roce_bth_pad_count_next   = m_roce_bth_pad_count_reg;
        m_roce_bth_hdr_version_next = m_roce_bth_hdr_version_reg;
        m_roce_bth_p_key_next       = m_roce_bth_p_key_reg;
        m_roce_bth_fecn_next        = m_roce_bth_fecn_reg;
        m_roce_bth_becn_next        = m_roce_bth_becn_reg;
        m_roce_bth_dest_qp_next     = m_roce_bth_dest_qp_reg;
        m_roce_bth_ack_req_next     = m_roce_bth_ack_req_reg;
        m_roce_bth_psn_next         = m_roce_bth_psn_reg;

        error_header_early_termination_next  = 1'b0;
        error_payload_early_termination_next = 1'b0;

        m_roce_bth_payload_axis_tdata_int  = shift_udp_payload_axis_tdata;
        m_roce_bth_payload_axis_tkeep_int  = shift_udp_payload_axis_tkeep;
        m_roce_bth_payload_axis_tvalid_int = 1'b0;
        m_roce_bth_payload_axis_tlast_int  = shift_udp_payload_axis_tlast;
        m_roce_bth_payload_axis_tuser_int  = shift_udp_payload_axis_tuser;

        if ((s_udp_payload_axis_tready && s_udp_payload_axis_tvalid) ||
        (m_roce_bth_payload_axis_tready_int_reg && shift_udp_payload_axis_extra_cycle_reg)) begin

            transfer_in_save = 1'b1;

            if (read_bth_header_reg) begin
                ptr_next = ptr_reg + 1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES && \
                    (!KEEP_ENABLE || s_udp_payload_axis_tkeep[offset%BYTE_LANES])) begin \
                    field = s_udp_payload_axis_tdata[(offset%BYTE_LANES)*8 +: 8]; \
                end

                `_HEADER_FIELD_(0,  m_roce_bth_op_code_next[7:0])
                // byte 1: SE | MigReq | PadCount[1:0] | HdrVersion[3:0]
                `_HEADER_FIELD_(1,  {m_roce_bth_sol_event_next,
                                  m_roce_bth_mig_req_next,
                                  m_roce_bth_pad_count_next,
                                  m_roce_bth_hdr_version_next})
                `_HEADER_FIELD_(2,  m_roce_bth_p_key_next[1*8 +: 8])
                `_HEADER_FIELD_(3,  m_roce_bth_p_key_next[0*8 +: 8])
                // byte 4: FECN | BECN | Reserved[5:0]
                `_HEADER_FIELD_(4,  temp_fecn_becn[7:0])
                m_roce_bth_fecn_next = temp_fecn_becn[7];
                m_roce_bth_becn_next = temp_fecn_becn[6];
                `_HEADER_FIELD_(5,  m_roce_bth_dest_qp_next[2*8 +: 8])
                `_HEADER_FIELD_(6,  m_roce_bth_dest_qp_next[1*8 +: 8])
                `_HEADER_FIELD_(7,  m_roce_bth_dest_qp_next[0*8 +: 8])
                // byte 8: AckReq | Reserved[6:0]
                `_HEADER_FIELD_(8,  temp_ack_req[7:0])
                m_roce_bth_ack_req_next = temp_ack_req[7];
                `_HEADER_FIELD_(9,  m_roce_bth_psn_next[2*8 +: 8])
                `_HEADER_FIELD_(10, m_roce_bth_psn_next[1*8 +: 8])
                `_HEADER_FIELD_(11, m_roce_bth_psn_next[0*8 +: 8])

            `undef _HEADER_FIELD_



                if (ptr_reg == (HDR_SIZE-1)/BYTE_LANES &&
                (!KEEP_ENABLE || s_udp_payload_axis_tkeep[(HDR_SIZE-1)%BYTE_LANES])) begin
                    if (!shift_udp_payload_axis_tlast) begin
                        m_roce_bth_hdr_valid_next = 1'b1;
                        read_bth_header_next      = 1'b0;
                        read_bth_payload_next     = 1'b1;
                    end
                end
            end

            if (read_bth_payload_reg) begin
                m_roce_bth_payload_axis_tdata_int  = shift_udp_payload_axis_tdata;
                m_roce_bth_payload_axis_tkeep_int  = shift_udp_payload_axis_tkeep;
                m_roce_bth_payload_axis_tvalid_int = 1'b1;
                m_roce_bth_payload_axis_tlast_int  = shift_udp_payload_axis_tlast;
                m_roce_bth_payload_axis_tuser_int  = shift_udp_payload_axis_tuser;

                if (s_udp_hdr_ready && s_udp_hdr_valid) begin
                    word_count_next = s_udp_length - 16'd20 - DATA_WIDTH/8;
                end else begin
                    word_count_next = word_count_reg - DATA_WIDTH/8;
                end

            end

            if (shift_udp_payload_axis_tlast) begin
                if (read_bth_header_next) begin
                    error_header_early_termination_next = 1'b1;
                end
                if (read_bth_payload_next) begin
                    if (word_count_reg >= DATA_WIDTH/4) begin
                        error_payload_early_termination_next = 1'b1;
                    end
                end
                flush_save            = 1'b1;
                ptr_next              = 0;
                read_bth_header_next  = 1'b1;
                read_bth_payload_next = 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        read_bth_header_reg  <= read_bth_header_next;
        read_bth_payload_reg <= read_bth_payload_next;
        ptr_reg              <= ptr_next;
        word_count_reg       <= word_count_next;

        s_udp_hdr_ready_reg           <= s_udp_hdr_ready_next;
        s_udp_payload_axis_tready_reg <= s_udp_payload_axis_tready_next;
        m_roce_bth_hdr_valid_reg      <= m_roce_bth_hdr_valid_next;

        if (store_udp_hdr) begin
            m_eth_dest_mac_reg           <= s_eth_dest_mac;
            m_eth_src_mac_reg            <= s_eth_src_mac;
            m_eth_type_reg               <= s_eth_type;
            m_ip_version_reg             <= s_ip_version;
            m_ip_ihl_reg                 <= s_ip_ihl;
            m_ip_dscp_reg                <= s_ip_dscp;
            m_ip_ecn_reg                 <= s_ip_ecn;
            m_ip_length_reg              <= s_ip_length;
            m_ip_identification_reg      <= s_ip_identification;
            m_ip_flags_reg               <= s_ip_flags;
            m_ip_fragment_offset_reg     <= s_ip_fragment_offset;
            m_ip_ttl_reg                 <= s_ip_ttl;
            m_ip_protocol_reg            <= s_ip_protocol;
            m_ip_header_checksum_reg     <= s_ip_header_checksum;
            m_ip_source_ip_reg           <= s_ip_source_ip;
            m_ip_dest_ip_reg             <= s_ip_dest_ip;
            m_udp_source_port_reg        <= s_udp_source_port;
            m_udp_dest_port_reg          <= s_udp_dest_port;
            m_udp_length_reg             <= s_udp_length;
            m_udp_checksum_reg           <= s_udp_checksum;
        end

        m_roce_bth_op_code_reg     <= m_roce_bth_op_code_next;
        m_roce_bth_sol_event_reg   <= m_roce_bth_sol_event_next;
        m_roce_bth_mig_req_reg     <= m_roce_bth_mig_req_next;
        m_roce_bth_pad_count_reg   <= m_roce_bth_pad_count_next;
        m_roce_bth_hdr_version_reg <= m_roce_bth_hdr_version_next;
        m_roce_bth_p_key_reg       <= m_roce_bth_p_key_next;
        m_roce_bth_fecn_reg        <= m_roce_bth_fecn_next;
        m_roce_bth_becn_reg        <= m_roce_bth_becn_next;
        m_roce_bth_dest_qp_reg     <= m_roce_bth_dest_qp_next;
        m_roce_bth_ack_req_reg     <= m_roce_bth_ack_req_next;
        m_roce_bth_psn_reg         <= m_roce_bth_psn_next;

        error_header_early_termination_reg  <= error_header_early_termination_next;
        error_payload_early_termination_reg <= error_payload_early_termination_next;

        busy_reg <= read_bth_payload_next || (ptr_next != 0);

        if (transfer_in_save) begin
            save_udp_payload_axis_tdata_reg <= s_udp_payload_axis_tdata;
            save_udp_payload_axis_tkeep_reg <= s_udp_payload_axis_tkeep;
            save_udp_payload_axis_tuser_reg <= s_udp_payload_axis_tuser;
        end

        if (flush_save) begin
            save_udp_payload_axis_tlast_reg        <= 1'b0;
            shift_udp_payload_axis_extra_cycle_reg <= 1'b0;
        end else if (transfer_in_save) begin
            save_udp_payload_axis_tlast_reg        <= s_udp_payload_axis_tlast;
            shift_udp_payload_axis_extra_cycle_reg <=
            OFFSET ? (s_udp_payload_axis_tlast &&
            ((s_udp_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << OFFSET)) != 0))
            : 1'b0;
        end

        if (rst) begin
            read_bth_header_reg                    <= 1'b1;
            read_bth_payload_reg                   <= 1'b0;
            ptr_reg                                <= 0;
            word_count_reg                         <= 16'd0;
            s_udp_hdr_ready_reg                    <= 1'b0;
            s_udp_payload_axis_tready_reg          <= 1'b0;
            m_roce_bth_hdr_valid_reg               <= 1'b0;
            save_udp_payload_axis_tlast_reg        <= 1'b0;
            shift_udp_payload_axis_extra_cycle_reg <= 1'b0;
            busy_reg                               <= 1'b0;
            error_header_early_termination_reg     <= 1'b0;
            error_payload_early_termination_reg    <= 1'b0;
        end
    end

    reg [DATA_WIDTH-1:0] m_roce_bth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_roce_bth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_roce_bth_payload_axis_tvalid_reg = 1'b0, m_roce_bth_payload_axis_tvalid_next;
    reg                  m_roce_bth_payload_axis_tlast_reg  = 1'b0;
    reg                  m_roce_bth_payload_axis_tuser_reg  = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_roce_bth_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_roce_bth_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  temp_m_roce_bth_payload_axis_tvalid_reg = 1'b0, temp_m_roce_bth_payload_axis_tvalid_next;
    reg                  temp_m_roce_bth_payload_axis_tlast_reg  = 1'b0;
    reg                  temp_m_roce_bth_payload_axis_tuser_reg  = 1'b0;

    reg store_payload_int_to_output;
    reg store_payload_int_to_temp;
    reg store_payload_temp_to_output;

    assign m_roce_bth_payload_axis_tdata  = m_roce_bth_payload_axis_tdata_reg;
    assign m_roce_bth_payload_axis_tkeep  = KEEP_ENABLE ? m_roce_bth_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_roce_bth_payload_axis_tvalid = m_roce_bth_payload_axis_tvalid_reg;
    assign m_roce_bth_payload_axis_tlast  = m_roce_bth_payload_axis_tlast_reg;
    assign m_roce_bth_payload_axis_tuser  = m_roce_bth_payload_axis_tuser_reg;

    assign m_roce_bth_payload_axis_tready_int_early =
    m_roce_bth_payload_axis_tready ||
    (!temp_m_roce_bth_payload_axis_tvalid_reg && !m_roce_bth_payload_axis_tvalid_reg);

    always @* begin
        m_roce_bth_payload_axis_tvalid_next      = m_roce_bth_payload_axis_tvalid_reg;
        temp_m_roce_bth_payload_axis_tvalid_next = temp_m_roce_bth_payload_axis_tvalid_reg;

        store_payload_int_to_output  = 1'b0;
        store_payload_int_to_temp    = 1'b0;
        store_payload_temp_to_output = 1'b0;

        if (m_roce_bth_payload_axis_tready_int_reg) begin
            if (m_roce_bth_payload_axis_tready || !m_roce_bth_payload_axis_tvalid_reg) begin
                m_roce_bth_payload_axis_tvalid_next = m_roce_bth_payload_axis_tvalid_int;
                store_payload_int_to_output         = 1'b1;
            end else begin
                temp_m_roce_bth_payload_axis_tvalid_next = m_roce_bth_payload_axis_tvalid_int;
                store_payload_int_to_temp                = 1'b1;
            end
        end else if (m_roce_bth_payload_axis_tready) begin
            m_roce_bth_payload_axis_tvalid_next      = temp_m_roce_bth_payload_axis_tvalid_reg;
            temp_m_roce_bth_payload_axis_tvalid_next = 1'b0;
            store_payload_temp_to_output             = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_roce_bth_payload_axis_tvalid_reg      <= m_roce_bth_payload_axis_tvalid_next;
        m_roce_bth_payload_axis_tready_int_reg  <= m_roce_bth_payload_axis_tready_int_early;
        temp_m_roce_bth_payload_axis_tvalid_reg <= temp_m_roce_bth_payload_axis_tvalid_next;

        if (store_payload_int_to_output) begin
            m_roce_bth_payload_axis_tdata_reg <= m_roce_bth_payload_axis_tdata_int;
            m_roce_bth_payload_axis_tkeep_reg <= m_roce_bth_payload_axis_tkeep_int;
            m_roce_bth_payload_axis_tlast_reg <= m_roce_bth_payload_axis_tlast_int;
            m_roce_bth_payload_axis_tuser_reg <= m_roce_bth_payload_axis_tuser_int;
        end else if (store_payload_temp_to_output) begin
            m_roce_bth_payload_axis_tdata_reg <= temp_m_roce_bth_payload_axis_tdata_reg;
            m_roce_bth_payload_axis_tkeep_reg <= temp_m_roce_bth_payload_axis_tkeep_reg;
            m_roce_bth_payload_axis_tlast_reg <= temp_m_roce_bth_payload_axis_tlast_reg;
            m_roce_bth_payload_axis_tuser_reg <= temp_m_roce_bth_payload_axis_tuser_reg;
        end

        if (store_payload_int_to_temp) begin
            temp_m_roce_bth_payload_axis_tdata_reg <= m_roce_bth_payload_axis_tdata_int;
            temp_m_roce_bth_payload_axis_tkeep_reg <= m_roce_bth_payload_axis_tkeep_int;
            temp_m_roce_bth_payload_axis_tlast_reg <= m_roce_bth_payload_axis_tlast_int;
            temp_m_roce_bth_payload_axis_tuser_reg <= m_roce_bth_payload_axis_tuser_int;
        end

        if (rst) begin
            m_roce_bth_payload_axis_tvalid_reg      <= 1'b0;
            m_roce_bth_payload_axis_tready_int_reg  <= 1'b0;
            temp_m_roce_bth_payload_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall
