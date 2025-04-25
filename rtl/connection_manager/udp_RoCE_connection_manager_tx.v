`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * Connection manager over UDP, TX path
 * L_key, loc base addr and loc psn not really used, as the qp is not receiveing anithing other then ACKs
 */

/*
 * Structure
 * +---------+-------------+--------------------------+
 * | OCTETS  |  BIT RANGE  |       Field              |
 * +---------+-------------+--------------------------+
 * |   0     |  [0  :0  ]  |  QP_info_valid           |
 * |   0     |  [7  :1  ]  |  QP_req_type             |
 * | [3:1]   |  [32 :8  ]  |  QP_info_loc_qpn         |
 * |   4     |  [39 :33 ]  |  ZERO_PADD               |
 * | [7:5]   |  [63 :40 ]  |  QP_info_loc_psn         |
 * |   8     |  [71 :64 ]  |  ZERO_PADD               |
 * | [12:9]  |  [103 :72]  |  QP_info_loc_r_key       |
 * | [20:13] |  [167:104]  |  QP_info_loc_base_addr   |
 * | [24:21] |  [199:168]  |  QP_info_loc_ip_addr     |
 * | [27:25] |  [223:200]  |  QP_info_rem_qpn         |
 * |   28    |  [231:224]  |  ZERO_PADD               |
 * | [31:29] |  [255:232]  |  QP_info_rem_psn         |
 * |   32    |  [263:256]  |  ZERO_PADD               |
 * | [36:33] |  [295:264]  |  QP_info_rem_r_key       |
 * | [44:37] |  [359:296]  |  QP_info_rem_base_addr   |
 * | [48:45] |  [391:360]  |  QP_info_rem_ip_addr     |
 * +---------+-------------+--------------------------+
 * |   49    |  [392:392]  |  txmeta_valid            |
 * |   49    |  [394:393]  |  txmeta_start            |
 * |   49    |  [394:394]  |  txmeta_is_immediate     |
 * |   49    |  [395:395]  |  txmeta_tx_type          |
 * |   49    |  [399:396]  |  txmeta_reserved         |
 * | [57:50] |  [463:400]  |  txmeta_rem_addr_offset  |
 * | [61:58] |  [495:464]  |  txmeta_dma_length       |
 * | [63:62] |  [511:496]  |  txmeta_rem_udp_port     |
 * +---------+-------------+--------------------------+
 * TOTAL length 512 bits, 64 bytes
 */

module udp_RoCE_connection_manager_tx #(
    parameter DATA_WIDTH      = 256
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE QP parameters
     */
    input wire        s_qp_context_valid,
    output wire       s_qp_context_ready,

    input wire [6 :0] s_qp_context_req_type,
    input wire [23:0] s_qp_context_loc_qpn,
    input wire [23:0] s_qp_context_loc_psn,
    input wire [31:0] s_qp_context_loc_r_key,
    input wire [31:0] s_qp_context_loc_ip_addr,
    input wire [63:0] s_qp_context_loc_base_addr,
    input wire [23:0] s_qp_context_rem_qpn,
    input wire [23:0] s_qp_context_rem_psn,
    input wire [31:0] s_qp_context_rem_r_key,
    input wire [31:0] s_qp_context_rem_ip_addr,
    input wire [63:0] s_qp_context_rem_base_addr,

    /*
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    input  wire         m_udp_hdr_ready,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [ 15:0] m_udp_source_port,
    output wire [ 15:0] m_udp_dest_port,
    output wire [ 15:0] m_udp_length,
    output wire [ 15:0] m_udp_checksum,
    output wire [DATA_WIDTH-1   : 0] m_udp_payload_axis_tdata,
    output wire [DATA_WIDTH/8-1 : 0] m_udp_payload_axis_tkeep,
    output wire         m_udp_payload_axis_tvalid,
    input  wire         m_udp_payload_axis_tready,
    output wire         m_udp_payload_axis_tlast,
    output wire         m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    /*
     * Configuration
     */
    input wire [15:0] cfg_udp_source_port,
    input wire [15:0] cfg_udp_dest_port
);

    parameter KEEP_ENABLE = 1;
    parameter KEEP_WIDTH  = DATA_WIDTH/8;

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    parameter QP_CONTEXT_SIZE = 64;

    parameter CYCLE_COUNT = (QP_CONTEXT_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_COUNT);

    parameter OFFSET = QP_CONTEXT_SIZE % BYTE_LANES;

    // datapath control signals
    reg store_qp_context;

    reg send_qp_context_reg = 1'b0, send_qp_context_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg flush_save;
    reg transfer_in_save;

    reg        qp_context_valid_reg;
    reg [6 :0] qp_context_req_type_reg;

    reg [23:0] qp_context_loc_qpn_reg;
    reg [23:0] qp_context_loc_psn_reg;
    reg [31:0] qp_context_loc_r_key_reg;
    reg [63:0] qp_context_loc_base_addr_reg;
    reg [31:0] qp_context_loc_ip_addr_reg;
    
    reg [23:0] qp_context_rem_qpn_reg;
    reg [23:0] qp_context_rem_psn_reg;
    reg [31:0] qp_context_rem_r_key_reg;
    reg [63:0] qp_context_rem_base_addr_reg;
    reg [31:0] qp_context_rem_ip_addr_reg;

    reg s_qp_context_ready_reg = 1'b0, s_qp_context_ready_next;

    reg s_qp_context_valid_del;

    reg        m_udp_hdr_valid_reg = 1'b0, m_udp_hdr_valid_next;
    reg [31:0] m_ip_source_ip_reg = 32'd0;
    reg [31:0] m_ip_dest_ip_reg = 32'd0;
    reg [15:0] m_udp_source_port_reg = 16'd0;
    reg [15:0] m_udp_dest_port_reg = 16'd0;
    reg [15:0] m_udp_length_reg = 16'd0;
    reg [15:0] m_udp_checksum_reg = 16'd0;

    reg busy_reg = 1'b0;

    // internal datapath
    reg  [DATA_WIDTH-1:0] m_udp_payload_axis_tdata_int;
    reg  [KEEP_WIDTH-1:0] m_udp_payload_axis_tkeep_int;
    reg                   m_udp_payload_axis_tvalid_int;
    reg                   m_udp_payload_axis_tready_int_reg = 1'b0;
    reg                   m_udp_payload_axis_tlast_int;
    reg                   m_udp_payload_axis_tuser_int;
    wire                  m_udp_payload_axis_tready_int_early;

    assign s_qp_context_ready = s_qp_context_ready_reg;

    assign m_udp_hdr_valid = m_udp_hdr_valid_reg;
    assign m_ip_source_ip = m_ip_source_ip_reg;
    assign m_ip_dest_ip = m_ip_dest_ip_reg;
    assign m_udp_source_port = m_udp_source_port_reg;
    assign m_udp_dest_port = m_udp_dest_port_reg;
    assign m_udp_length = m_udp_length_reg;
    assign m_udp_checksum = m_udp_checksum_reg;


    assign busy = busy_reg;

    always @* begin
        send_qp_context_next = send_qp_context_reg;
        ptr_next = ptr_reg;

        s_qp_context_ready_next = 1'b0;

        m_udp_hdr_valid_next = m_udp_hdr_valid_reg && !m_udp_hdr_ready;

        store_qp_context = 1'b0;

        flush_save = 1'b0;
        transfer_in_save = 1'b0;

        m_udp_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
        m_udp_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
        m_udp_payload_axis_tvalid_int = 1'b0;
        m_udp_payload_axis_tlast_int = 1'b0;
        m_udp_payload_axis_tuser_int = 1'b0;


        if (s_qp_context_ready && s_qp_context_valid) begin
            store_qp_context = 1'b1;
            ptr_next = 0;

            m_udp_hdr_valid_next = 1'b1;

            send_qp_context_next = 1'b1;
        end

        //if (s_qp_open_valid_del) begin
        //    m_ip_hdr_valid_next = 1'b1;
        //end

        if (m_udp_payload_axis_tready_int_reg && (!OFFSET || m_udp_payload_axis_tvalid_int)) begin
            if (send_qp_context_reg) begin
                ptr_next = ptr_reg + 1;

                m_udp_payload_axis_tvalid_int = 1'b1;

            `define _HEADER_FIELD_(offset, field) \
                if (ptr_reg == offset/BYTE_LANES) begin \
                    m_udp_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                    m_udp_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                end
                `_HEADER_FIELD_(0 ,  {qp_context_req_type_reg, qp_context_valid_reg})
                `_HEADER_FIELD_(1 ,  qp_context_loc_qpn_reg[0*8 +: 8])
                `_HEADER_FIELD_(2 ,  qp_context_loc_qpn_reg[1*8 +: 8])
                `_HEADER_FIELD_(3 ,  qp_context_loc_qpn_reg[2*8 +: 8])
                `_HEADER_FIELD_(4 ,  8'h00)
                `_HEADER_FIELD_(5 ,  qp_context_loc_psn_reg[0*8 +: 8])
                `_HEADER_FIELD_(6 ,  qp_context_loc_psn_reg[1*8 +: 8])
                `_HEADER_FIELD_(7 ,  qp_context_loc_psn_reg[2*8 +: 8])
                `_HEADER_FIELD_(8 ,  8'h00)
                `_HEADER_FIELD_(9 ,  qp_context_loc_r_key_reg[0*8 +: 8])
                `_HEADER_FIELD_(10,  qp_context_loc_r_key_reg[1*8 +: 8])
                `_HEADER_FIELD_(11,  qp_context_loc_r_key_reg[2*8 +: 8])
                `_HEADER_FIELD_(12,  qp_context_loc_r_key_reg[3*8 +: 8])
                `_HEADER_FIELD_(13,  qp_context_loc_base_addr_reg[0*8 +: 8])
                `_HEADER_FIELD_(14,  qp_context_loc_base_addr_reg[1*8 +: 8])
                `_HEADER_FIELD_(15,  qp_context_loc_base_addr_reg[2*8 +: 8])
                `_HEADER_FIELD_(16,  qp_context_loc_base_addr_reg[3*8 +: 8])
                `_HEADER_FIELD_(17,  qp_context_loc_base_addr_reg[4*8 +: 8])
                `_HEADER_FIELD_(18,  qp_context_loc_base_addr_reg[5*8 +: 8])
                `_HEADER_FIELD_(19,  qp_context_loc_base_addr_reg[6*8 +: 8])
                `_HEADER_FIELD_(20,  qp_context_loc_base_addr_reg[7*8 +: 8])
                `_HEADER_FIELD_(21,  qp_context_loc_ip_addr_reg[0*8 +: 8])
                `_HEADER_FIELD_(22,  qp_context_loc_ip_addr_reg[1*8 +: 8])
                `_HEADER_FIELD_(23,  qp_context_loc_ip_addr_reg[2*8 +: 8])
                `_HEADER_FIELD_(24,  qp_context_loc_ip_addr_reg[3*8 +: 8])
                `_HEADER_FIELD_(25,  qp_context_rem_qpn_reg[0*8 +: 8])
                `_HEADER_FIELD_(26,  qp_context_rem_qpn_reg[1*8 +: 8])
                `_HEADER_FIELD_(27,  qp_context_rem_qpn_reg[2*8 +: 8])
                `_HEADER_FIELD_(28 ,  8'h00)
                `_HEADER_FIELD_(29,  qp_context_rem_psn_reg[0*8 +: 8])
                `_HEADER_FIELD_(30,  qp_context_rem_psn_reg[1*8 +: 8])
                `_HEADER_FIELD_(31,  qp_context_rem_psn_reg[2*8 +: 8])
                `_HEADER_FIELD_(32 ,  8'h00)
                `_HEADER_FIELD_(33,  qp_context_rem_r_key_reg[0*8 +: 8])
                `_HEADER_FIELD_(34,  qp_context_rem_r_key_reg[1*8 +: 8])
                `_HEADER_FIELD_(35,  qp_context_rem_r_key_reg[2*8 +: 8])
                `_HEADER_FIELD_(36,  qp_context_rem_r_key_reg[3*8 +: 8])
                `_HEADER_FIELD_(37,  qp_context_rem_base_addr_reg[0*8 +: 8])
                `_HEADER_FIELD_(38,  qp_context_rem_base_addr_reg[1*8 +: 8])
                `_HEADER_FIELD_(39,  qp_context_rem_base_addr_reg[2*8 +: 8])
                `_HEADER_FIELD_(40,  qp_context_rem_base_addr_reg[3*8 +: 8])
                `_HEADER_FIELD_(41,  qp_context_rem_base_addr_reg[4*8 +: 8])
                `_HEADER_FIELD_(42,  qp_context_rem_base_addr_reg[5*8 +: 8])
                `_HEADER_FIELD_(43,  qp_context_rem_base_addr_reg[6*8 +: 8])
                `_HEADER_FIELD_(44,  qp_context_rem_base_addr_reg[7*8 +: 8])
                `_HEADER_FIELD_(45,  qp_context_rem_ip_addr_reg[0*8 +: 8])
                `_HEADER_FIELD_(46,  qp_context_rem_ip_addr_reg[1*8 +: 8])
                `_HEADER_FIELD_(47,  qp_context_rem_ip_addr_reg[2*8 +: 8])
                `_HEADER_FIELD_(48,  qp_context_rem_ip_addr_reg[3*8 +: 8])
                `_HEADER_FIELD_(49,  8'h00)
                `_HEADER_FIELD_(50,  8'h00)
                `_HEADER_FIELD_(51,  8'h00)
                `_HEADER_FIELD_(52,  8'h00)
                `_HEADER_FIELD_(53,  8'h00)
                `_HEADER_FIELD_(54,  8'h00)
                `_HEADER_FIELD_(55,  8'h00)
                `_HEADER_FIELD_(56,  8'h00)
                `_HEADER_FIELD_(57,  8'h00)
                `_HEADER_FIELD_(58,  8'h00)
                `_HEADER_FIELD_(59,  8'h00)
                `_HEADER_FIELD_(60,  8'h00)
                `_HEADER_FIELD_(61,  8'h00)
                `_HEADER_FIELD_(62,  8'h00)
                `_HEADER_FIELD_(63,  8'h00)

                if (ptr_reg == (QP_CONTEXT_SIZE-1)/BYTE_LANES) begin
                    send_qp_context_next = 1'b0;
                    m_udp_payload_axis_tlast_int = 1'b1;
                end

            `undef _HEADER_FIELD_
        end
        end

        s_qp_context_ready_next = !m_udp_hdr_valid_next && !(send_qp_context_next);
    end

    always @(posedge clk) begin
        send_qp_context_reg <= send_qp_context_next;
        ptr_reg <= ptr_next;

        s_qp_context_ready_reg <= s_qp_context_ready_next;

        m_udp_hdr_valid_reg <= m_udp_hdr_valid_next;

        busy_reg <= send_qp_context_next;

        s_qp_context_valid_del <= s_qp_context_valid && s_qp_context_ready_reg;

        if (store_qp_context) begin
            qp_context_valid_reg         <= 1'b1; 
            qp_context_req_type_reg      <= s_qp_context_req_type; 
            qp_context_loc_qpn_reg       <= s_qp_context_loc_qpn;
            qp_context_loc_psn_reg       <= s_qp_context_loc_psn; 
            qp_context_loc_r_key_reg     <= s_qp_context_loc_r_key;
            qp_context_loc_base_addr_reg <= s_qp_context_loc_base_addr;
            qp_context_loc_ip_addr_reg   <= s_qp_context_loc_ip_addr;

            qp_context_rem_qpn_reg       <= s_qp_context_rem_qpn;
            qp_context_rem_psn_reg       <= s_qp_context_rem_psn;
            qp_context_rem_r_key_reg     <= s_qp_context_rem_r_key;
            qp_context_rem_base_addr_reg <= s_qp_context_rem_base_addr;
            qp_context_rem_ip_addr_reg   <= s_qp_context_rem_ip_addr;

            m_ip_source_ip_reg    <= s_qp_context_loc_ip_addr;
            m_ip_dest_ip_reg      <= s_qp_context_rem_ip_addr;
            m_udp_source_port_reg <= cfg_udp_source_port;
            m_udp_dest_port_reg   <= cfg_udp_dest_port;
            m_udp_length_reg      <= QP_CONTEXT_SIZE+16'd8;
            m_udp_checksum_reg    <= 16'd0;
        end

        if (rst) begin
            send_qp_context_reg <= 1'b0;
            ptr_reg <= 0;
            s_qp_context_ready_reg <= 1'b0;
            m_udp_hdr_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
        end
    end

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_udp_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_udp_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
    reg                  m_udp_payload_axis_tvalid_reg = 1'b0, m_udp_payload_axis_tvalid_next;
    reg                  m_udp_payload_axis_tlast_reg = 1'b0;
    reg                  m_udp_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_udp_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_udp_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
    reg                  temp_m_udp_payload_axis_tvalid_reg = 1'b0, temp_m_udp_payload_axis_tvalid_next;
    reg                  temp_m_udp_payload_axis_tlast_reg = 1'b0;
    reg                  temp_m_udp_payload_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_udp_payload_axis_int_to_output;
    reg store_udp_payload_axis_int_to_temp;
    reg store_udp_payload_axis_temp_to_output;

    assign m_udp_payload_axis_tdata = m_udp_payload_axis_tdata_reg;
    assign m_udp_payload_axis_tkeep = KEEP_ENABLE ? m_udp_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_udp_payload_axis_tvalid = m_udp_payload_axis_tvalid_reg;
    assign m_udp_payload_axis_tlast =  m_udp_payload_axis_tlast_reg;
    assign m_udp_payload_axis_tuser =  m_udp_payload_axis_tuser_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_udp_payload_axis_tready_int_early = m_udp_payload_axis_tready || (!temp_m_udp_payload_axis_tvalid_reg && !m_udp_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_reg;
        temp_m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;

        store_udp_payload_axis_int_to_output = 1'b0;
        store_udp_payload_axis_int_to_temp = 1'b0;
        store_udp_payload_axis_temp_to_output = 1'b0;

        if (m_udp_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_udp_payload_axis_tready || !m_udp_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
                store_udp_payload_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
                store_udp_payload_axis_int_to_temp = 1'b1;
            end
        end else if (m_udp_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;
            temp_m_udp_payload_axis_tvalid_next = 1'b0;
            store_udp_payload_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_udp_payload_axis_tvalid_reg <= m_udp_payload_axis_tvalid_next;
        m_udp_payload_axis_tready_int_reg <= m_udp_payload_axis_tready_int_early;
        temp_m_udp_payload_axis_tvalid_reg <= temp_m_udp_payload_axis_tvalid_next;

        // datapath
        if (store_udp_payload_axis_int_to_output) begin
            m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
            m_udp_payload_axis_tkeep_reg <= m_udp_payload_axis_tkeep_int;
            m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
            m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
        end else if (store_udp_payload_axis_temp_to_output) begin
            m_udp_payload_axis_tdata_reg <= temp_m_udp_payload_axis_tdata_reg;
            m_udp_payload_axis_tkeep_reg <= temp_m_udp_payload_axis_tkeep_reg;
            m_udp_payload_axis_tlast_reg <= temp_m_udp_payload_axis_tlast_reg;
            m_udp_payload_axis_tuser_reg <= temp_m_udp_payload_axis_tuser_reg;
        end

        if (store_udp_payload_axis_int_to_temp) begin
            temp_m_udp_payload_axis_tdata_reg <= m_udp_payload_axis_tdata_int;
            temp_m_udp_payload_axis_tkeep_reg <= m_udp_payload_axis_tkeep_int;
            temp_m_udp_payload_axis_tlast_reg <= m_udp_payload_axis_tlast_int;
            temp_m_udp_payload_axis_tuser_reg <= m_udp_payload_axis_tuser_int;
        end

        if (rst) begin
            m_udp_payload_axis_tvalid_reg <= 1'b0;
            m_udp_payload_axis_tready_int_reg <= 1'b0;
            temp_m_udp_payload_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall