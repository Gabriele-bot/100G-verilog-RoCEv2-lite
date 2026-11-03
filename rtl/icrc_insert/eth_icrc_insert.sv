`resetall `timescale 1ns / 1ps `default_nettype none

module eth_icrc_insert #
  (
    parameter DATA_WIDTH             = 256,
    parameter KEEP_ENABLE            = DATA_WIDTH>7,
    parameter KEEP_WIDTH             = DATA_WIDTH/8,
    parameter CRC_COMP_TYPE          = 1, // 0 VHDL implementation, 1 SV implementation
    parameter ENABLE_TIMING_OPT_REGS = 1,
    parameter N_PIPE                 = 3 // pipeline reg within SV CRC module 
) (
    input wire clk,
    input wire rst,

    /*
    ETH frame input
    */
    input  wire                      s_eth_hdr_valid,
    output wire                      s_eth_hdr_ready,
    input  wire [47:0]               s_eth_dest_mac,
    input  wire [47:0]               s_eth_src_mac,
    input  wire [15:0]               s_eth_type,
    // AXIS payload
    input  wire [DATA_WIDTH - 1 : 0] s_eth_payload_axis_tdata,
    input  wire [KEEP_WIDTH - 1 : 0] s_eth_payload_axis_tkeep,
    input  wire                      s_eth_payload_axis_tvalid,
    output wire                      s_eth_payload_axis_tready,
    input  wire                      s_eth_payload_axis_tlast,
    input  wire [1:0]                s_eth_payload_axis_tuser, // bit 0 malformed packet, bit 1 RoCE id

    /*
    ETH frame output with ICRC at the end (if tuser[1] is asserted)
    */
    output  wire                     m_eth_hdr_valid,
    input wire                       m_eth_hdr_ready,
    output  wire [47:0]              m_eth_dest_mac,
    output  wire [47:0]              m_eth_src_mac,
    output  wire [15:0]              m_eth_type,
    // AXIS payload
    output wire [DATA_WIDTH - 1 : 0] m_eth_payload_axis_tdata,
    output wire [KEEP_WIDTH - 1 : 0] m_eth_payload_axis_tkeep,
    output wire                      m_eth_payload_axis_tvalid,
    input  wire                      m_eth_payload_axis_tready,
    output wire                      m_eth_payload_axis_tlast,
    output wire                      m_eth_payload_axis_tuser,

    /*
     * Status
     */
    output wire busy
);

    localparam CRC_COMP_LATENCY = CRC_COMP_TYPE ? ($clog2(DATA_WIDTH/8) + N_PIPE + 2)  : DATA_WIDTH / 32;

    wire [DATA_WIDTH - 1 : 0] m_eth_payload_reg_axis_tdata;
    wire [KEEP_WIDTH - 1 : 0] m_eth_payload_reg_axis_tkeep;
    wire                      m_eth_payload_reg_axis_tvalid;
    wire                      m_eth_payload_reg_axis_tlast;
    wire                      m_eth_payload_reg_axis_tuser;
    wire                      m_eth_payload_reg_axis_tready;

    axis_fifo #(
        .DEPTH      (CRC_COMP_LATENCY+1),
        .DATA_WIDTH (14*8),
        .KEEP_ENABLE(0),
        .KEEP_WIDTH (1),
        .LAST_ENABLE(0),
        .ID_ENABLE  (0),
        .ID_WIDTH   (1),
        .DEST_ENABLE(0),
        .DEST_WIDTH (1),
        .USER_ENABLE(0),
        .USER_WIDTH (1),
        .RAM_PIPELINE(1)
    ) eth_hdr_fifo_instance (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata({s_eth_dest_mac, s_eth_src_mac, s_eth_type}),
        .s_axis_tvalid(s_eth_hdr_valid),
        .s_axis_tready(s_eth_hdr_ready),
        .s_axis_tkeep(0),
        .s_axis_tlast(0),
        .s_axis_tid  (0),
        .s_axis_tdest(0),
        .s_axis_tuser(0),

        .m_axis_tdata({m_eth_dest_mac, m_eth_src_mac, m_eth_type}),
        .m_axis_tvalid(m_eth_hdr_valid),
        .m_axis_tready(m_eth_hdr_ready)
    );


    // Insert ICRC
    axis_RoCE_icrc_insert #(
        .DATA_WIDTH   (DATA_WIDTH),
        .CRC_COMP_TYPE(CRC_COMP_TYPE), // 0 VHDL implementation, 1 SV implementation
        .N_PIPE       (N_PIPE)
    ) axis_RoCE_icrc_insert_instance (
        .clk(clk),
        .rst(rst),

        .s_eth_payload_axis_tdata (s_eth_payload_axis_tdata),
        .s_eth_payload_axis_tkeep (s_eth_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(s_eth_payload_axis_tvalid),
        .s_eth_payload_axis_tready(s_eth_payload_axis_tready),
        .s_eth_payload_axis_tlast (s_eth_payload_axis_tlast),
        .s_eth_payload_axis_tuser (s_eth_payload_axis_tuser),

        .m_eth_payload_axis_tdata (m_eth_payload_reg_axis_tdata),
        .m_eth_payload_axis_tkeep (m_eth_payload_reg_axis_tkeep),
        .m_eth_payload_axis_tvalid(m_eth_payload_reg_axis_tvalid),
        .m_eth_payload_axis_tready(m_eth_payload_reg_axis_tready),
        .m_eth_payload_axis_tlast (m_eth_payload_reg_axis_tlast),
        .m_eth_payload_axis_tuser (m_eth_payload_reg_axis_tuser),

        .busy                     (busy)
    );

    generate
        if (ENABLE_TIMING_OPT_REGS) begin
            axis_register #(
                .DATA_WIDTH (DATA_WIDTH),
                .KEEP_ENABLE(KEEP_ENABLE),
                .KEEP_WIDTH (KEEP_WIDTH),
                .ID_ENABLE  (0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH (1),
                .REG_TYPE   (2)
            ) axis_register_icrc_out_inst (
                .clk(clk),
                .rst(rst),

                .s_axis_tdata (m_eth_payload_reg_axis_tdata),
                .s_axis_tkeep (m_eth_payload_reg_axis_tkeep),
                .s_axis_tvalid(m_eth_payload_reg_axis_tvalid),
                .s_axis_tready(m_eth_payload_reg_axis_tready),
                .s_axis_tlast (m_eth_payload_reg_axis_tlast),
                .s_axis_tuser (m_eth_payload_reg_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                .m_axis_tdata (m_eth_payload_axis_tdata),
                .m_axis_tkeep (m_eth_payload_axis_tkeep),
                .m_axis_tvalid(m_eth_payload_axis_tvalid),
                .m_axis_tready(m_eth_payload_axis_tready),
                .m_axis_tlast (m_eth_payload_axis_tlast),
                .m_axis_tuser (m_eth_payload_axis_tuser),
                .m_axis_tid   (),
                .m_axis_tdest ()
            );

        end else begin
            assign m_eth_payload_axis_tdata      = m_eth_payload_reg_axis_tdata;
            assign m_eth_payload_axis_tkeep      = m_eth_payload_reg_axis_tkeep;
            assign m_eth_payload_axis_tvalid     = m_eth_payload_reg_axis_tvalid;
            assign m_eth_payload_reg_axis_tready = m_eth_payload_axis_tready;
            assign m_eth_payload_axis_tlast      = m_eth_payload_reg_axis_tlast;
            assign m_eth_payload_axis_tuser      = m_eth_payload_reg_axis_tuser;
        end

    endgenerate


endmodule

`resetall