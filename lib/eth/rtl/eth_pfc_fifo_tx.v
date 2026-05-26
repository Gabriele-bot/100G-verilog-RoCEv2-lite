`resetall
`timescale 1ns / 1ps
`default_nettype none

module eth_pfc_fifo_tx#
(
    // Width of AXI stream interfaces in bits
    parameter DATA_WIDTH = 8,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // Flow control fifo depth
    parameter FIFO_DEPTH = 1024,
    // output srl register
    parameter OUTPUT_SRL_REG = 0
)
(
    input  wire                  clk,
    input  wire                  rst,

    /*
     * AXIS inputs
     */
    input  wire [DATA_WIDTH-1:0] s_priority_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_priority_axis_tkeep,
    input  wire                  s_priority_axis_tvalid,
    output wire                  s_priority_axis_tready,
    input  wire                  s_priority_axis_tlast,
    input  wire                  s_priority_axis_tuser,

    /*
     * AXIS output
     */
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire                  m_axis_tuser,

    /*
    Pause signals
    */
    input  wire [7:0]             pause_req,
    output wire [7:0]             pause_ack,

    /*
     * Configuration signals
     */
    input wire   [2:0]            priority_tag,

    /*
     * Status signals
     */
    output wire                  busy
);

    wire [DATA_WIDTH-1:0] m_reg_axis_tdata;
    wire [KEEP_WIDTH-1:0] m_reg_axis_tkeep;
    wire                  m_reg_axis_tvalid;
    wire                  m_reg_axis_tready;
    wire                  m_reg_axis_tlast;
    wire                  m_reg_axis_tuser;

    reg [2:0] priority_tag_reg;
    reg [7:0] pause_ack_reg;

    reg  pause_req_fifo;
    wire pause_ack_fifo;

    always @(clk) begin
        priority_tag_reg <= priority_tag;
        pause_req_fifo   <= pause_req[priority_tag_reg];
        case (priority_tag_reg)
            3'd0 : begin
                pause_ack_reg[0]   <= pause_ack_fifo;
                pause_ack_reg[7:1] <= 7'h7f;
            end
            3'd1 : begin
                pause_ack_reg[0]   <= 1'h1;
                pause_ack_reg[1]   <= pause_ack_fifo;
                pause_ack_reg[7:2] <= 6'h3f;
            end
            3'd2 : begin
                pause_ack_reg[1:0] <= 2'h3;
                pause_ack_reg[2]   <= pause_ack_fifo;
                pause_ack_reg[7:3] <= 5'h1f;
            end
            3'd3 : begin
                pause_ack_reg[2:0] <= 3'h7;
                pause_ack_reg[3]   <= pause_ack_fifo;
                pause_ack_reg[7:4] <= 4'hf;
            end
            3'd4 : begin
                pause_ack_reg[3:0] <= 4'hf;
                pause_ack_reg[4]   <= pause_ack_fifo;
                pause_ack_reg[7:5] <= 3'h7;
            end
            3'd5 : begin
                pause_ack_reg[4:0] <= 5'h1f;
                pause_ack_reg[5]   <= pause_ack_fifo;
                pause_ack_reg[7:6] <= 2'h3;
            end
            3'd6 : begin
                pause_ack_reg[5:0] <= 6'h3f;
                pause_ack_reg[6]   <= pause_ack_fifo;
                pause_ack_reg[7:7] <= 1'h1;
            end
            3'd7 : begin
                pause_ack_reg[6:0] <= 7'h7f;
                pause_ack_reg[7]   <= pause_ack_fifo;
            end
        endcase
    end


    axis_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .RAM_PIPELINE(2),
        .FRAME_FIFO(1),
        .PAUSE_ENABLE(1),
        .FRAME_PAUSE(1)
    ) tx_pfc_priority_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_priority_axis_tdata ),
        .s_axis_tkeep (s_priority_axis_tkeep ),
        .s_axis_tvalid(s_priority_axis_tvalid),
        .s_axis_tready(s_priority_axis_tready),
        .s_axis_tlast (s_priority_axis_tlast ),
        .s_axis_tuser (s_priority_axis_tuser ),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_reg_axis_tdata ),
        .m_axis_tkeep (m_reg_axis_tkeep ),
        .m_axis_tvalid(m_reg_axis_tvalid),
        .m_axis_tready(m_reg_axis_tready),
        .m_axis_tlast (m_reg_axis_tlast ),
        .m_axis_tuser (m_reg_axis_tuser ),
        // pause 
        .pause_req(pause_req_fifo),
        .pause_ack(pause_ack_fifo)
    );

    generate
        if (OUTPUT_SRL_REG) begin

            axis_srl_register #(
                .DATA_WIDTH(DATA_WIDTH),
                .KEEP_ENABLE(1),
                .ID_ENABLE(0),
                .DEST_ENABLE(0),
                .USER_ENABLE(1),
                .USER_WIDTH(1)
            ) tx_srl_register_inst(
                .clk(clk),
                .rst(rst),

                // AXI input
                .s_axis_tdata (m_reg_axis_tdata ),
                .s_axis_tkeep (m_reg_axis_tkeep ),
                .s_axis_tvalid(m_reg_axis_tvalid),
                .s_axis_tready(m_reg_axis_tready),
                .s_axis_tlast (m_reg_axis_tlast ),
                .s_axis_tuser (m_reg_axis_tuser ),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_axis_tdata ),
                .m_axis_tkeep (m_axis_tkeep ),
                .m_axis_tvalid(m_axis_tvalid),
                .m_axis_tready(m_axis_tready),
                .m_axis_tlast (m_axis_tlast ),
                .m_axis_tuser (m_axis_tuser )
            );
        end else begin
            assign m_axis_tdata      = m_reg_axis_tdata; 
            assign m_axis_tkeep      = m_reg_axis_tkeep; 
            assign m_axis_tvalid     = m_reg_axis_tvalid;
            assign m_reg_axis_tready = m_axis_tready;
            assign m_axis_tlast      = m_reg_axis_tlast; 
            assign m_axis_tuser      = m_reg_axis_tuser; 
        end
    endgenerate


    assign pause_ack = pause_ack_reg;




endmodule