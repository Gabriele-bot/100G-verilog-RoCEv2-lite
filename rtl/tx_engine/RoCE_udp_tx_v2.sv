
`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_udp_tx_v2  #(
    parameter DATA_WIDTH          = 256,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire         s_roce_reth_valid,
    output wire         s_roce_reth_ready,
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire         s_roce_immdh_valid,
    output wire         s_roce_immdh_ready,
    input  wire [ 31:0] s_roce_immdh_data,
    // udp, ip, eth
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_identification,
    input  wire [  2:0] s_ip_flags,
    input  wire [ 12:0] s_ip_fragment_offset,
    input  wire [  7:0] s_ip_ttl,
    input  wire [  7:0] s_ip_protocol,
    input  wire [ 15:0] s_ip_header_checksum,
    input  wire [ 31:0] s_ip_source_ip,
    input  wire [ 31:0] s_ip_dest_ip,
    input  wire [ 15:0] s_udp_source_port,
    input  wire [ 15:0] s_udp_dest_port,
    input  wire [ 15:0] s_udp_length,
    input  wire [ 15:0] s_udp_checksum,
    // payload
    input  wire [DATA_WIDTH-1   : 0] s_roce_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1 : 0] s_roce_payload_axis_tkeep,
    input  wire         s_roce_payload_axis_tvalid,
    output wire         s_roce_payload_axis_tready,
    input  wire         s_roce_payload_axis_tlast,
    input  wire         s_roce_payload_axis_tuser,
    /*
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    input  wire         m_udp_hdr_ready,
    output wire [ 47:0] m_eth_dest_mac,
    output wire [ 47:0] m_eth_src_mac,
    output wire [ 15:0] m_eth_type,
    output wire [  3:0] m_ip_version,
    output wire [  3:0] m_ip_ihl,
    output wire [  5:0] m_ip_dscp,
    output wire [  1:0] m_ip_ecn,
    output wire [ 15:0] m_ip_length,
    output wire [ 15:0] m_ip_identification,
    output wire [  2:0] m_ip_flags,
    output wire [ 12:0] m_ip_fragment_offset,
    output wire [  7:0] m_ip_ttl,
    output wire [  7:0] m_ip_protocol,
    output wire [ 15:0] m_ip_header_checksum,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [ 15:0] m_udp_source_port,
    output wire [ 15:0] m_udp_dest_port,
    output wire [ 15:0] m_udp_length,
    output wire [ 15:0] m_udp_checksum,
    output wire [DATA_WIDTH-1   : 0] m_udp_payload_axis_tdata,
    output wire [KEEP_WIDTH-1 : 0] m_udp_payload_axis_tkeep,
    output wire         m_udp_payload_axis_tvalid,
    input  wire         m_udp_payload_axis_tready,
    output wire         m_udp_payload_axis_tlast,
    output wire         m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    output wire         error_payload_early_termination,
    /*
     * Config
     */
    input  wire [              15:0] RoCE_udp_port
);

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    parameter HDR_BTH_SIZE = 12;
    parameter HDR_RETH_SIZE = 16;
    parameter HDR_IMMDH_SIZE = 4;

    parameter HDR_BTH_ONLY_SIZE = HDR_BTH_SIZE;
    parameter HDR_BTH_RETH_SIZE = HDR_BTH_SIZE + HDR_RETH_SIZE;
    parameter HDR_BTH_RETH_IMMDH_SIZE = HDR_BTH_SIZE + HDR_RETH_SIZE + HDR_IMMDH_SIZE;
    parameter HDR_BTH_IMMDH_SIZE = HDR_BTH_SIZE + HDR_IMMDH_SIZE;

    parameter CYCLE_BTH_ONLY_COUNT = (HDR_BTH_ONLY_SIZE+BYTE_LANES-1)/BYTE_LANES;
    parameter CYCLE_BTH_RETH_COUNT = (HDR_BTH_RETH_SIZE+BYTE_LANES-1)/BYTE_LANES;
    parameter CYCLE_BTH_RETH_IMMDH_COUNT = (HDR_BTH_RETH_IMMDH_SIZE+BYTE_LANES-1)/BYTE_LANES;
    parameter CYCLE_BTH_IMMDH_COUNT = (HDR_BTH_IMMDH_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_BTH_RETH_IMMDH_COUNT);

    parameter OFFSET_BTH_ONLY = HDR_BTH_ONLY_SIZE % BYTE_LANES;
    parameter OFFSET_BTH_RETH = HDR_BTH_RETH_SIZE % BYTE_LANES;
    parameter OFFSET_BTH_RETH_IMMDH = HDR_BTH_RETH_IMMDH_SIZE % BYTE_LANES;
    parameter OFFSET_BTH_IMMDH = HDR_BTH_IMMDH_SIZE % BYTE_LANES;


    // bus width assertions
    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end


    /*

RoCE RDMA WRITE Frame.

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
+--------------------------------------+
|               RETH                   |
+--------------------------------------+
 Field                       Length
 Remote Address              8 octets
 R key                       4 octets
 DMA length                  4 octets
+--------------------------------------+
|               IMMD                   |
+--------------------------------------+
 Field                       Length
 Immediate data              4 octets
+--------------------------------------+
|               AETH                   |
+--------------------------------------+
 Field                       Length
 Syndrome                    1 octet
 Message Sequence Number     3 octets
 
 payload                     length octets
+--------------------------------------+
|               ICRC                   |
+--------------------------------------+
 Field                       Length
 ICRC field                  4 octets

This module receives a RoCEv2 frame with headers fields along side the
payload as AXI streams, combines the headers with the payload, passes through
the UDP headers, and transmits the complete UDP payload as AXI stream interface.

*/

    import RoCE_params::*; // Imports RoCE parameters

    // bus width assertions
    initial begin
        if (DATA_WIDTH > 2048) begin
            $error("Error: AXIS data width must be smaller than 2048 (instance %m)");
            $finish;
        end
    end

    // datapath control signals
    // datapath control signals
    reg store_roce_hdrs;
    reg store_udp;
    reg store_last_word;

    reg solicited_event_reg;

    // 0 --> dont send
    // 1 --> send bth
    // 2 --> send bth reth
    // 3 --> send bth reth immdh
    // 4 --> send bth immdh
    reg [2:0] send_roce_header_reg = 3'd0, send_roce_header_next;
    reg [2:0] send_roce_payload_reg = 3'd0, send_roce_payload_next;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg flush_save;
    reg transfer_in_save;

    //reg [15:0] word_count_reg = 16'd0, word_count_next;

    reg [DATA_WIDTH-1   : 0] last_word_data_reg = 0;
    reg [KEEP_WIDTH-1 : 0] last_word_keep_reg = 0;

    reg [  7:0] roce_bth_op_code_reg = 8'd0;
    reg [ 15:0] roce_bth_p_key_reg = 16'd0;
    reg [ 23:0] roce_bth_psn_reg = 24'd0;
    reg [ 23:0] roce_bth_dest_qp_reg = 24'd0;
    reg         roce_bth_ack_req_reg = 1'd0;

    reg [ 63:0] roce_reth_v_addr_reg = 64'd0;
    reg [ 31:0] roce_reth_r_key_reg = 32'd0;
    reg [ 31:0] roce_reth_length_reg = 32'd0;

    reg [ 31:0] roce_immdh_data_reg = 32'd0;

    reg [15:0] udp_source_port_reg = 16'd0;
    reg [15:0] udp_dest_port_reg   = 16'd0;
    reg [15:0] udp_length_reg      = 16'd0;
    reg [15:0] udp_checksum_reg    = 16'd0;

    reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;
    reg s_roce_payload_axis_tready_reg = 1'b0, s_roce_payload_axis_tready_next;

    reg        busy_reg = 1'b0;
    reg error_payload_early_termination_reg = 1'b0, error_payload_early_termination_next;

    reg [DATA_WIDTH-1 : 0] save_roce_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH-1 : 0] save_roce_payload_axis_tkeep_reg = 0;
    reg         save_roce_payload_axis_tlast_reg = 1'b0;
    reg         save_roce_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH-1 : 0] shift_roce_payload_96_axis_tdata;
    reg [KEEP_WIDTH-1 : 0] shift_roce_payload_96_axis_tkeep;
    reg [DATA_WIDTH-1 : 0] shift_roce_payload_128_axis_tdata;
    reg [KEEP_WIDTH-1 : 0] shift_roce_payload_128_axis_tkeep;
    reg [DATA_WIDTH-1 : 0] shift_roce_payload_224_axis_tdata;
    reg [KEEP_WIDTH-1 : 0] shift_roce_payload_224_axis_tkeep;
    reg [DATA_WIDTH-1 : 0] shift_roce_payload_256_axis_tdata;
    reg [KEEP_WIDTH-1 : 0] shift_roce_payload_256_axis_tkeep;
    reg                    shift_roce_payload_96_axis_tvalid;
    reg                    shift_roce_payload_128_axis_tvalid;
    reg                    shift_roce_payload_224_axis_tvalid;
    reg                    shift_roce_payload_256_axis_tvalid;
    reg                    shift_roce_payload_96_axis_tlast;
    reg                    shift_roce_payload_96_axis_tuser;
    reg                    shift_roce_payload_128_axis_tlast;
    reg                    shift_roce_payload_128_axis_tuser;
    reg                    shift_roce_payload_224_axis_tlast;
    reg                    shift_roce_payload_224_axis_tuser;
    reg                    shift_roce_payload_256_axis_tlast;
    reg                    shift_roce_payload_256_axis_tuser;
    reg                    shift_roce_payload_96_axis_input_tready;
    reg                    shift_roce_payload_128_axis_input_tready;
    reg                    shift_roce_payload_224_axis_input_tready;
    reg                    shift_roce_payload_256_axis_input_tready;
    reg                    shift_roce_payload_96_extra_cycle_reg = 1'b0;
    reg                    shift_roce_payload_128_extra_cycle_reg = 1'b0;
    reg                    shift_roce_payload_224_extra_cycle_reg = 1'b0;
    reg                    shift_roce_payload_256_extra_cycle_reg = 1'b0;

    // internal datapath
    reg  [DATA_WIDTH-1 : 0] m_udp_payload_axis_tdata_int;
    reg  [KEEP_WIDTH-1 : 0] m_udp_payload_axis_tkeep_int;
    reg          m_udp_payload_axis_tvalid_int;
    reg          m_udp_payload_axis_tready_int_reg = 1'b0;
    reg          m_udp_payload_axis_tlast_int;
    reg          m_udp_payload_axis_tuser_int;
    wire         m_udp_payload_axis_tready_int_early;

    wire s_hdr_fifo_ready;

    wire [(14+20+8)*8-1:0] s_hdr_in;
    wire [(14+20+8)*8-1:0] m_hdr_out;

    assign s_roce_bth_ready                = s_roce_bth_ready_reg && s_hdr_fifo_ready;
    assign s_roce_reth_ready               = s_roce_bth_ready_reg && s_hdr_fifo_ready;
    assign s_roce_immdh_ready              = s_roce_bth_ready_reg && s_hdr_fifo_ready;
    assign s_roce_payload_axis_tready      = s_roce_payload_axis_tready_reg;

    assign busy                            = busy_reg;
    assign error_payload_early_termination = error_payload_early_termination_reg;

    

    

    assign s_hdr_in = {                
        s_eth_dest_mac,                  
        s_eth_src_mac,                   
        s_eth_type,                      
        s_ip_version,                  
        s_ip_ihl,                        
        s_ip_dscp,                       
        s_ip_ecn,                        
        s_udp_length+16'd20,                     
        s_ip_identification,             
        s_ip_flags,                      
        s_ip_fragment_offset,            
        s_ip_ttl,                        
        s_ip_protocol,                   
        s_ip_header_checksum,            
        s_ip_source_ip,                  
        s_ip_dest_ip,                    
        s_udp_source_port,               
        s_udp_dest_port,                 
        s_udp_length,                    
        s_udp_checksum                  
    };

    // pass through header
    axis_fifo #(
        .DEPTH(2),
        .DATA_WIDTH((14+20+8)*8),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) input_hdr_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_hdr_in),
        .s_axis_tvalid(s_roce_bth_valid && s_roce_bth_ready),
        .s_axis_tready(s_hdr_fifo_ready),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tuser (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_hdr_out),
        .m_axis_tvalid(m_udp_hdr_valid),
        .m_axis_tready(m_udp_hdr_ready)
    );

                    
    assign m_eth_dest_mac       = m_hdr_out[288 +:48];                  
    assign m_eth_src_mac        = m_hdr_out[240 +:48];                   
    assign m_eth_type           = m_hdr_out[224 +:16];                      
    assign m_ip_version         = m_hdr_out[220 +:4];                   
    assign m_ip_ihl             = m_hdr_out[216 +:4];                        
    assign m_ip_dscp            = m_hdr_out[210 +:6];                       
    assign m_ip_ecn             = m_hdr_out[208 +:2];                        
    assign m_ip_length          = m_hdr_out[192 +:16];                     
    assign m_ip_identification  = m_hdr_out[176 +:16];             
    assign m_ip_flags           = m_hdr_out[173 +:3];                      
    assign m_ip_fragment_offset = m_hdr_out[160 +:13];            
    assign m_ip_ttl             = m_hdr_out[152 +:8];                        
    assign m_ip_protocol        = m_hdr_out[144 +:8];                   
    assign m_ip_header_checksum = m_hdr_out[128 +:16];            
    assign m_ip_source_ip       = m_hdr_out[96 +:32];                  
    assign m_ip_dest_ip         = m_hdr_out[64 +:32];                    
    assign m_udp_source_port    = m_hdr_out[48 +:16];               
    assign m_udp_dest_port      = m_hdr_out[32 +:16];                 
    assign m_udp_length         = m_hdr_out[16 +:16];                    
    assign m_udp_checksum       = m_hdr_out[0 +:16];  
    
    
    // BTH only
    always @* begin
        if (OFFSET_BTH_ONLY == 0) begin
            // passthrough if no overlap
            shift_roce_payload_96_axis_tdata  = s_roce_payload_axis_tdata;
            shift_roce_payload_96_axis_tkeep  = s_roce_payload_axis_tkeep;
            shift_roce_payload_96_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_96_axis_tlast  = s_roce_payload_axis_tlast;
            shift_roce_payload_96_axis_tuser  = s_roce_payload_axis_tuser;
            shift_roce_payload_96_axis_input_tready = 1'b1;
        end else if (shift_roce_payload_96_extra_cycle_reg) begin
            shift_roce_payload_96_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_ONLY)*8);
            shift_roce_payload_96_axis_tkeep = {{KEEP_WIDTH{1'b0}}       , save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_ONLY);
            shift_roce_payload_96_axis_tvalid = 1'b1;
            shift_roce_payload_96_axis_tlast = save_roce_payload_axis_tlast_reg;
            shift_roce_payload_96_axis_tuser = save_roce_payload_axis_tuser_reg;
            shift_roce_payload_96_axis_input_tready = flush_save;
        end else begin
            shift_roce_payload_96_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_ONLY)*8);
            shift_roce_payload_96_axis_tkeep = {s_roce_payload_axis_tkeep, save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_ONLY);
            shift_roce_payload_96_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_96_axis_tlast = (s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_ONLY))) == 0));
            shift_roce_payload_96_axis_tuser = (s_roce_payload_axis_tuser && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_ONLY))) == 0));
            shift_roce_payload_96_axis_input_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tready && s_roce_payload_axis_tvalid);
        end
    end

    // BTH and RETH
    always @* begin
        if (OFFSET_BTH_RETH == 0) begin
            // passthrough if no overlap
            shift_roce_payload_224_axis_tdata  = s_roce_payload_axis_tdata;
            shift_roce_payload_224_axis_tkeep  = s_roce_payload_axis_tkeep;
            shift_roce_payload_224_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_224_axis_tlast  = s_roce_payload_axis_tlast;
            shift_roce_payload_224_axis_tuser  = s_roce_payload_axis_tuser;
            shift_roce_payload_224_axis_input_tready = 1'b1;
        end else if (shift_roce_payload_224_extra_cycle_reg) begin
            shift_roce_payload_224_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_RETH)*8);
            shift_roce_payload_224_axis_tkeep = {{KEEP_WIDTH{1'b0}}       , save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_RETH);
            shift_roce_payload_224_axis_tvalid = 1'b1;
            shift_roce_payload_224_axis_tlast = save_roce_payload_axis_tlast_reg;
            shift_roce_payload_224_axis_tuser = save_roce_payload_axis_tuser_reg;
            shift_roce_payload_224_axis_input_tready = flush_save;
        end else begin
            shift_roce_payload_224_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_RETH)*8);
            shift_roce_payload_224_axis_tkeep = {s_roce_payload_axis_tkeep, save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_RETH);
            shift_roce_payload_224_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_224_axis_tlast = (s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH))) == 0));
            shift_roce_payload_224_axis_tuser = (s_roce_payload_axis_tuser && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH))) == 0));
            shift_roce_payload_224_axis_input_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tready && s_roce_payload_axis_tvalid);
        end
    end

    // BTH, RETH and IMMDH
    always @* begin
        if (OFFSET_BTH_RETH_IMMDH == 0) begin
            // passthrough if no overlap
            shift_roce_payload_256_axis_tdata  = s_roce_payload_axis_tdata;
            shift_roce_payload_256_axis_tkeep  = s_roce_payload_axis_tkeep;
            shift_roce_payload_256_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_256_axis_tlast  = s_roce_payload_axis_tlast;
            shift_roce_payload_256_axis_tuser  = s_roce_payload_axis_tuser;
            shift_roce_payload_256_axis_input_tready = 1'b1;
        end else if (shift_roce_payload_256_extra_cycle_reg) begin
            shift_roce_payload_256_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH)*8);
            shift_roce_payload_256_axis_tkeep = {{KEEP_WIDTH{1'b0}}       , save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH);
            shift_roce_payload_256_axis_tvalid = 1'b1;
            shift_roce_payload_256_axis_tlast = save_roce_payload_axis_tlast_reg;
            shift_roce_payload_256_axis_tuser = save_roce_payload_axis_tuser_reg;
            shift_roce_payload_256_axis_input_tready = flush_save;
        end else begin
            shift_roce_payload_256_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH)*8);
            shift_roce_payload_256_axis_tkeep = {s_roce_payload_axis_tkeep, save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH);
            shift_roce_payload_256_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_256_axis_tlast = (s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH))) == 0));
            shift_roce_payload_256_axis_tuser = (s_roce_payload_axis_tuser && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH))) == 0));
            shift_roce_payload_256_axis_input_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tready && s_roce_payload_axis_tvalid);
        end
    end

    // BTH and IMMDH
    always @* begin
        if (OFFSET_BTH_IMMDH == 0) begin
            // passthrough if no overlap
            shift_roce_payload_128_axis_tdata  = s_roce_payload_axis_tdata;
            shift_roce_payload_128_axis_tkeep  = s_roce_payload_axis_tkeep;
            shift_roce_payload_128_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_128_axis_tlast  = s_roce_payload_axis_tlast;
            shift_roce_payload_128_axis_tuser  = s_roce_payload_axis_tuser;
            shift_roce_payload_128_axis_input_tready = 1'b1;
        end else if (shift_roce_payload_128_extra_cycle_reg) begin
            shift_roce_payload_128_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_IMMDH)*8);
            shift_roce_payload_128_axis_tkeep = {{KEEP_WIDTH{1'b0}}       , save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_IMMDH);
            shift_roce_payload_128_axis_tvalid = 1'b1;
            shift_roce_payload_128_axis_tlast = save_roce_payload_axis_tlast_reg;
            shift_roce_payload_128_axis_tuser = save_roce_payload_axis_tuser_reg;
            shift_roce_payload_128_axis_input_tready = flush_save;
        end else begin
            shift_roce_payload_128_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_BTH_IMMDH)*8);
            shift_roce_payload_128_axis_tkeep = {s_roce_payload_axis_tkeep, save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_BTH_IMMDH);
            shift_roce_payload_128_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_128_axis_tlast = (s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_IMMDH))) == 0));
            shift_roce_payload_128_axis_tuser = (s_roce_payload_axis_tuser && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_IMMDH))) == 0));
            shift_roce_payload_128_axis_input_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tready && s_roce_payload_axis_tvalid);
        end
    end


    always @* begin
        send_roce_header_next = send_roce_header_reg;
        send_roce_payload_next = send_roce_payload_reg;
        ptr_next = ptr_reg;

        s_roce_bth_ready_next = 1'b0;
        s_roce_payload_axis_tready_next = 1'b0;

        store_roce_hdrs = 1'b0;

        flush_save = 1'b0;
        transfer_in_save = 1'b0;

        m_udp_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
        m_udp_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
        m_udp_payload_axis_tvalid_int = 1'b0;
        m_udp_payload_axis_tlast_int = 1'b0;
        m_udp_payload_axis_tuser_int = 1'b0;

        if (s_roce_bth_ready && s_roce_bth_valid) begin
            store_roce_hdrs = 1'b1;
            ptr_next = 0;
            if (!s_roce_reth_valid && !s_roce_immdh_valid) begin
                send_roce_header_next = 3'd1;
                send_roce_payload_next = (OFFSET_BTH_ONLY != 0) && (CYCLE_BTH_ONLY_COUNT == 1) ? 3'd1 : 3'd0;
                s_roce_payload_axis_tready_next = (send_roce_payload_next == 3'd1) && m_udp_payload_axis_tready_int_early;
            end else if (s_roce_reth_valid && s_roce_reth_ready && !s_roce_immdh_valid) begin
                send_roce_header_next = 3'd2;
                send_roce_payload_next = (OFFSET_BTH_RETH != 0) && (CYCLE_BTH_RETH_COUNT == 1) ? 3'd2 : 3'd0;
                s_roce_payload_axis_tready_next = (send_roce_payload_next == 3'd2) && m_udp_payload_axis_tready_int_early;
            end else if (s_roce_reth_valid && s_roce_reth_ready && s_roce_immdh_valid && s_roce_immdh_ready) begin
                send_roce_header_next = 3'd3;
                send_roce_payload_next = (OFFSET_BTH_RETH_IMMDH != 0) && (CYCLE_BTH_RETH_IMMDH_COUNT == 1) ? 3'd3 : 3'd0;
                s_roce_payload_axis_tready_next = (send_roce_payload_next == 3'd3) && m_udp_payload_axis_tready_int_early;
            end else if (s_roce_immdh_valid && s_roce_immdh_ready && ~s_roce_reth_valid) begin
                send_roce_header_next = 3'd4;
                send_roce_payload_next = (OFFSET_BTH_IMMDH != 0) && (CYCLE_BTH_IMMDH_COUNT == 1) ? 3'd4 : 3'd0;
                s_roce_payload_axis_tready_next = (send_roce_payload_next == 3'd4) && m_udp_payload_axis_tready_int_early;
            end 
        end

        if (send_roce_payload_reg == 3'd1) begin
            s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_96_axis_input_tready;

            m_udp_payload_axis_tdata_int = shift_roce_payload_96_axis_tdata;
            m_udp_payload_axis_tkeep_int = shift_roce_payload_96_axis_tkeep;
            m_udp_payload_axis_tlast_int = shift_roce_payload_96_axis_tlast;
            m_udp_payload_axis_tuser_int = shift_roce_payload_96_axis_tuser;

            if ((s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) || (m_udp_payload_axis_tready_int_reg && shift_roce_payload_96_extra_cycle_reg)) begin
                transfer_in_save = 1'b1;

                m_udp_payload_axis_tvalid_int = 1'b1;

                if (shift_roce_payload_96_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 3'd0;
                end
            end
        end else if (send_roce_payload_reg == 3'd2) begin
            s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_224_axis_input_tready;

            m_udp_payload_axis_tdata_int = shift_roce_payload_224_axis_tdata;
            m_udp_payload_axis_tkeep_int = shift_roce_payload_224_axis_tkeep;
            m_udp_payload_axis_tlast_int = shift_roce_payload_224_axis_tlast;
            m_udp_payload_axis_tuser_int = shift_roce_payload_224_axis_tuser;

            if ((s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) || (m_udp_payload_axis_tready_int_reg && shift_roce_payload_224_extra_cycle_reg)) begin
                transfer_in_save = 1'b1;

                m_udp_payload_axis_tvalid_int = 1'b1;

                if (shift_roce_payload_224_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 3'd0;
                end
            end
        end else if (send_roce_payload_reg == 3'd3) begin
            s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_256_axis_input_tready;

            m_udp_payload_axis_tdata_int = shift_roce_payload_256_axis_tdata;
            m_udp_payload_axis_tkeep_int = shift_roce_payload_256_axis_tkeep;
            m_udp_payload_axis_tlast_int = shift_roce_payload_256_axis_tlast;
            m_udp_payload_axis_tuser_int = shift_roce_payload_256_axis_tuser;

            if ((s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) || (m_udp_payload_axis_tready_int_reg && shift_roce_payload_256_extra_cycle_reg)) begin
                transfer_in_save = 1'b1;

                m_udp_payload_axis_tvalid_int = 1'b1;

                if (shift_roce_payload_256_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 3'd0;
                end
            end
        end else if (send_roce_payload_reg == 3'd4) begin
            s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_128_axis_input_tready;

            m_udp_payload_axis_tdata_int = shift_roce_payload_128_axis_tdata;
            m_udp_payload_axis_tkeep_int = shift_roce_payload_128_axis_tkeep;
            m_udp_payload_axis_tlast_int = shift_roce_payload_128_axis_tlast;
            m_udp_payload_axis_tuser_int = shift_roce_payload_128_axis_tuser;

            if ((s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) || (m_udp_payload_axis_tready_int_reg && shift_roce_payload_128_extra_cycle_reg)) begin
                transfer_in_save = 1'b1;

                m_udp_payload_axis_tvalid_int = 1'b1;

                if (shift_roce_payload_128_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 3'd0;
                end
            end
        end


        if (m_udp_payload_axis_tready_int_reg && (!OFFSET_BTH_ONLY || (send_roce_payload_reg == 3'd0) || m_udp_payload_axis_tvalid_int)) begin
            if (send_roce_header_reg == 3'd1) begin
                ptr_next = ptr_reg + 1;

                if ((OFFSET_BTH_ONLY != 0) && (CYCLE_BTH_ONLY_COUNT == 1 || ptr_next == CYCLE_BTH_ONLY_COUNT-1) && (send_roce_payload_reg == 3'd0)) begin
                    send_roce_payload_next = 3'd1;
                    s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_96_axis_input_tready;
                end

                m_udp_payload_axis_tvalid_int = 1'b1;
    
                `define _HEADER_BTH_FIELD_(offset, field) \
                    if (ptr_reg == offset/BYTE_LANES) begin \
                        m_udp_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                        m_udp_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                    end

                `_HEADER_BTH_FIELD_(0,  roce_bth_op_code_reg[0*8 +: 8])
                `_HEADER_BTH_FIELD_(1,  {solicited_event_reg, 1'b1, 2'd0, 4'd0}) // sol event, mig request, pad_count, header version
                `_HEADER_BTH_FIELD_(2,  roce_bth_p_key_reg[1*8 +: 8])
                `_HEADER_BTH_FIELD_(3,  roce_bth_p_key_reg[0*8 +: 8])
                `_HEADER_BTH_FIELD_(4,  {8'd0}) //reserved
                `_HEADER_BTH_FIELD_(5,  roce_bth_dest_qp_reg[2*8 +: 8])
                `_HEADER_BTH_FIELD_(6,  roce_bth_dest_qp_reg[1*8 +: 8])
                `_HEADER_BTH_FIELD_(7,  roce_bth_dest_qp_reg[0*8 +: 8])
                `_HEADER_BTH_FIELD_(8,  {s_roce_bth_ack_req, 7'd0}) //reserved
                `_HEADER_BTH_FIELD_(9,  roce_bth_psn_reg[2*8 +: 8])
                `_HEADER_BTH_FIELD_(10, roce_bth_psn_reg[1*8 +: 8])
                `_HEADER_BTH_FIELD_(11, roce_bth_psn_reg[0*8 +: 8])

                if (ptr_reg == (HDR_BTH_ONLY_SIZE-1)/BYTE_LANES) begin
                    if (send_roce_payload_reg == 3'd0) begin
                        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
                        send_roce_payload_next = 3'd1;
                    end
                    send_roce_header_next = 3'd0;
                end
    
                `undef _HEADER_BTH_FIELD_
            end
        end

        if (m_udp_payload_axis_tready_int_reg && (!OFFSET_BTH_RETH || (send_roce_payload_reg == 3'd0) || m_udp_payload_axis_tvalid_int)) begin
            if (send_roce_header_reg == 3'd2) begin
                ptr_next = ptr_reg + 1;

                if ((OFFSET_BTH_RETH != 0) && (CYCLE_BTH_RETH_COUNT == 1 || ptr_next == CYCLE_BTH_RETH_COUNT-1) && (send_roce_payload_reg == 3'd0)) begin
                    send_roce_payload_next = 3'd2;
                    s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_224_axis_input_tready;
                end

                m_udp_payload_axis_tvalid_int = 1'b1;
    
                `define _HEADER_BTH_RETH_FIELD_(offset, field) \
                    if (ptr_reg == offset/BYTE_LANES) begin \
                        m_udp_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                        m_udp_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                    end

                `_HEADER_BTH_RETH_FIELD_(0,  roce_bth_op_code_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(1,  {solicited_event_reg, 1'b1, 2'd0, 4'd0}) // sol event, mig request, pad_count, header version
                `_HEADER_BTH_RETH_FIELD_(2,  roce_bth_p_key_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(3,  roce_bth_p_key_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(4,  {8'd0}) //reserved
                `_HEADER_BTH_RETH_FIELD_(5,  roce_bth_dest_qp_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(6,  roce_bth_dest_qp_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(7,  roce_bth_dest_qp_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(8,  {s_roce_bth_ack_req, 7'd0}) //reserved
                `_HEADER_BTH_RETH_FIELD_(9,  roce_bth_psn_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(10, roce_bth_psn_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(11, roce_bth_psn_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(12, roce_reth_v_addr_reg[7*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(13, roce_reth_v_addr_reg[6*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(14, roce_reth_v_addr_reg[5*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(15, roce_reth_v_addr_reg[4*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(16, roce_reth_v_addr_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(17, roce_reth_v_addr_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(18, roce_reth_v_addr_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(19, roce_reth_v_addr_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(20, roce_reth_r_key_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(21, roce_reth_r_key_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(22, roce_reth_r_key_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(23, roce_reth_r_key_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(24, roce_reth_length_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(25, roce_reth_length_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(26, roce_reth_length_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_FIELD_(27, roce_reth_length_reg[0*8 +: 8])

                if (ptr_reg == (HDR_BTH_RETH_SIZE-1)/BYTE_LANES) begin
                    if (send_roce_payload_reg == 3'd0) begin
                        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
                        send_roce_payload_next = 3'd2;
                    end
                    send_roce_header_next = 3'd0;
                end
    
                `undef _HEADER_BTH_RETH_FIELD_
            end
        end

        if (m_udp_payload_axis_tready_int_reg && (!OFFSET_BTH_RETH_IMMDH || (send_roce_payload_reg == 3'd0) || m_udp_payload_axis_tvalid_int)) begin
            if (send_roce_header_reg == 3'd3) begin
                ptr_next = ptr_reg + 1;

                if ((OFFSET_BTH_RETH_IMMDH != 0) && (CYCLE_BTH_RETH_IMMDH_COUNT == 1 || ptr_next == CYCLE_BTH_RETH_IMMDH_COUNT-1) && (send_roce_payload_reg == 3'd0)) begin
                    send_roce_payload_next = 3'd3;
                    s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_256_axis_input_tready;
                end

                m_udp_payload_axis_tvalid_int = 1'b1;
    
                `define _HEADER_BTH_RETH_IMMDH_FIELD_(offset, field) \
                    if (ptr_reg == offset/BYTE_LANES) begin \
                        m_udp_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                        m_udp_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                    end

                `_HEADER_BTH_RETH_IMMDH_FIELD_(0,  roce_bth_op_code_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(1,  {solicited_event_reg, 1'b1, 2'd0, 4'd0}) // sol event, mig request, pad_count, header version
                `_HEADER_BTH_RETH_IMMDH_FIELD_(2,  roce_bth_p_key_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(3,  roce_bth_p_key_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(4,  {8'd0}) //reserved
                `_HEADER_BTH_RETH_IMMDH_FIELD_(5,  roce_bth_dest_qp_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(6,  roce_bth_dest_qp_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(7,  roce_bth_dest_qp_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(8,  {s_roce_bth_ack_req, 7'd0}) //reserved
                `_HEADER_BTH_RETH_IMMDH_FIELD_(9,  roce_bth_psn_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(10, roce_bth_psn_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(11, roce_bth_psn_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(12, roce_reth_v_addr_reg[7*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(13, roce_reth_v_addr_reg[6*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(14, roce_reth_v_addr_reg[5*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(15, roce_reth_v_addr_reg[4*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(16, roce_reth_v_addr_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(17, roce_reth_v_addr_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(18, roce_reth_v_addr_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(19, roce_reth_v_addr_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(20, roce_reth_r_key_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(21, roce_reth_r_key_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(22, roce_reth_r_key_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(23, roce_reth_r_key_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(24, roce_reth_length_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(25, roce_reth_length_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(26, roce_reth_length_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(27, roce_reth_length_reg[0*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(28, roce_immdh_data_reg[3*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(29, roce_immdh_data_reg[2*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(30, roce_immdh_data_reg[1*8 +: 8])
                `_HEADER_BTH_RETH_IMMDH_FIELD_(31, roce_immdh_data_reg[0*8 +: 8])

                if (ptr_reg == (HDR_BTH_RETH_IMMDH_SIZE-1)/BYTE_LANES) begin
                    if (send_roce_payload_reg == 3'd0) begin
                        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
                        send_roce_payload_next = 3'd3;
                    end
                    send_roce_header_next = 3'd0;
                end
    
                `undef _HEADER_BTH_RETH_IMMDH_FIELD_
            end
        end

        if (m_udp_payload_axis_tready_int_reg && (!OFFSET_BTH_IMMDH || (send_roce_payload_reg == 3'd0) || m_udp_payload_axis_tvalid_int)) begin
            if (send_roce_header_reg == 3'd4) begin
                ptr_next = ptr_reg + 1;

                if ((OFFSET_BTH_IMMDH != 0) && (CYCLE_BTH_IMMDH_COUNT == 1 || ptr_next == CYCLE_BTH_IMMDH_COUNT-1) && (send_roce_payload_reg == 3'd0)) begin
                    send_roce_payload_next = 3'd4;
                    s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early && shift_roce_payload_128_axis_input_tready;
                end

                m_udp_payload_axis_tvalid_int = 1'b1;
    
                `define _HEADER_BTH_IMMDH_FIELD_(offset, field) \
                    if (ptr_reg == offset/BYTE_LANES) begin \
                        m_udp_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                        m_udp_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                    end

                `_HEADER_BTH_IMMDH_FIELD_(0,  roce_bth_op_code_reg[0*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(1,  {solicited_event_reg, 1'b1, 2'd0, 4'd0}) // sol event, mig request, pad_count, header version
                `_HEADER_BTH_IMMDH_FIELD_(2,  roce_bth_p_key_reg[1*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(3,  roce_bth_p_key_reg[0*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(4,  {8'd0}) //reserved
                `_HEADER_BTH_IMMDH_FIELD_(5,  roce_bth_dest_qp_reg[2*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(6,  roce_bth_dest_qp_reg[1*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(7,  roce_bth_dest_qp_reg[0*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(8,  {s_roce_bth_ack_req, 7'd0}) //reserved
                `_HEADER_BTH_IMMDH_FIELD_(9,  roce_bth_psn_reg[2*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(10, roce_bth_psn_reg[1*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(11, roce_bth_psn_reg[0*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(12, roce_immdh_data_reg[3*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(13, roce_immdh_data_reg[2*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(14, roce_immdh_data_reg[1*8 +: 8])
                `_HEADER_BTH_IMMDH_FIELD_(15, roce_immdh_data_reg[0*8 +: 8])

                if (ptr_reg == (HDR_BTH_IMMDH_SIZE-1)/BYTE_LANES) begin
                    if (send_roce_payload_reg == 3'd0) begin
                        s_roce_payload_axis_tready_next = m_udp_payload_axis_tready_int_early;
                        send_roce_payload_next = 3'd4;
                    end
                    send_roce_header_next = 3'd0;
                end
    
                `undef _HEADER_BTH_IMMDH_FIELD_
            end
        end

        s_roce_bth_ready_next = !((send_roce_header_next != 3'd0) || (send_roce_payload_next != 3'd0));
    end

    always @(posedge clk) begin
        send_roce_header_reg <= send_roce_header_next;
        send_roce_payload_reg <= send_roce_payload_next;
        ptr_reg <= ptr_next;

        s_roce_bth_ready_reg <= s_roce_bth_ready_next;
        s_roce_payload_axis_tready_reg <= s_roce_payload_axis_tready_next;


        busy_reg <= (send_roce_header_next != 3'd0) || (send_roce_payload_next != 3'd0);

        if (store_roce_hdrs) begin

            udp_source_port_reg <= s_udp_source_port;
            udp_dest_port_reg <= RoCE_udp_port;
            udp_length_reg <= s_udp_length;
            udp_checksum_reg <= 16'h0000;

            roce_bth_op_code_reg <= s_roce_bth_op_code;
            roce_bth_p_key_reg   <= s_roce_bth_p_key;
            roce_bth_psn_reg     <= s_roce_bth_psn;
            roce_bth_dest_qp_reg <= s_roce_bth_dest_qp;
            roce_bth_ack_req_reg <= s_roce_bth_ack_req;

            if (s_roce_bth_op_code == RC_SEND_LAST || s_roce_bth_op_code == RC_SEND_LAST_IMD || s_roce_bth_op_code == RC_SEND_ONLY || s_roce_bth_op_code == RC_SEND_ONLY_IMD) begin
                // SEND operation
                solicited_event_reg  <= 1'b1;
            end else if (s_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD || s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD) begin
                // WRITE with IMMD
                solicited_event_reg  <= 1'b1;
            end else begin
                // WRITE operation
                solicited_event_reg  <= 1'b0;
            end
            if (s_roce_reth_valid) begin
                roce_reth_v_addr_reg = s_roce_reth_v_addr;
                roce_reth_r_key_reg  = s_roce_reth_r_key;
                roce_reth_length_reg = s_roce_reth_length;
            end
            if (s_roce_immdh_valid) begin
                roce_immdh_data_reg = s_roce_immdh_data;
            end
        end

        if (transfer_in_save) begin
            save_roce_payload_axis_tdata_reg <= s_roce_payload_axis_tdata;
            save_roce_payload_axis_tkeep_reg <= s_roce_payload_axis_tkeep;
            save_roce_payload_axis_tuser_reg <= s_roce_payload_axis_tuser;
        end

        if (flush_save) begin
            save_roce_payload_axis_tlast_reg <= 1'b0;
            shift_roce_payload_96_extra_cycle_reg <= 1'b0;
            shift_roce_payload_224_extra_cycle_reg <= 1'b0;
            shift_roce_payload_256_extra_cycle_reg <= 1'b0;
            shift_roce_payload_128_extra_cycle_reg <= 1'b0;
        end else if (transfer_in_save) begin
            save_roce_payload_axis_tlast_reg <= s_roce_payload_axis_tlast;
            shift_roce_payload_96_extra_cycle_reg <= OFFSET_BTH_ONLY ? s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_ONLY))) != 0) : 1'b0;
            shift_roce_payload_224_extra_cycle_reg <= OFFSET_BTH_RETH ? s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH))) != 0) : 1'b0;
            shift_roce_payload_256_extra_cycle_reg <= OFFSET_BTH_RETH_IMMDH ? s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_RETH_IMMDH))) != 0) : 1'b0;
            shift_roce_payload_128_extra_cycle_reg <= OFFSET_BTH_IMMDH ? s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_BTH_IMMDH))) != 0) : 1'b0;
        end

        if (rst) begin
            send_roce_header_reg <= 3'd0;
            send_roce_payload_reg <= 3'd0;
            ptr_reg <= 0;
            s_roce_bth_ready_reg <= 1'b0;
            s_roce_payload_axis_tready_reg <= 1'b0;
            busy_reg <= 1'b0;
        end
    end

    // output datapath logic
    reg [DATA_WIDTH   - 1 :0] m_udp_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] m_udp_payload_axis_tkeep_reg = 0;
    reg m_udp_payload_axis_tvalid_reg = 1'b0, m_udp_payload_axis_tvalid_next;
    reg         m_udp_payload_axis_tlast_reg = 1'b0;
    reg         m_udp_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH   - 1 :0] temp_m_udp_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] temp_m_udp_payload_axis_tkeep_reg = 0;
    reg temp_m_udp_payload_axis_tvalid_reg = 1'b0, temp_m_udp_payload_axis_tvalid_next;
    reg temp_m_udp_payload_axis_tlast_reg = 1'b0;
    reg temp_m_udp_payload_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_udp_payload_int_to_output;
    reg store_udp_payload_int_to_temp;
    reg store_udp_payload_axis_temp_to_output;

    assign m_udp_payload_axis_tdata = m_udp_payload_axis_tdata_reg;
    assign m_udp_payload_axis_tkeep = m_udp_payload_axis_tkeep_reg;
    assign m_udp_payload_axis_tvalid = m_udp_payload_axis_tvalid_reg;
    assign m_udp_payload_axis_tlast = m_udp_payload_axis_tlast_reg;
    assign m_udp_payload_axis_tuser = m_udp_payload_axis_tuser_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_udp_payload_axis_tready_int_early = m_udp_payload_axis_tready || (!temp_m_udp_payload_axis_tvalid_reg && !m_udp_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_reg;
        temp_m_udp_payload_axis_tvalid_next = temp_m_udp_payload_axis_tvalid_reg;

        store_udp_payload_int_to_output = 1'b0;
        store_udp_payload_int_to_temp = 1'b0;
        store_udp_payload_axis_temp_to_output = 1'b0;

        if (m_udp_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_udp_payload_axis_tready | !m_udp_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_udp_payload_axis_tvalid_next  = m_udp_payload_axis_tvalid_int;
                store_udp_payload_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_udp_payload_axis_tvalid_next = m_udp_payload_axis_tvalid_int;
                store_udp_payload_int_to_temp = 1'b1;
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
        if (store_udp_payload_int_to_output) begin
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

        if (store_udp_payload_int_to_temp) begin
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
