

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Ethernet multiplexer
 */
module generic_mux #
(
    parameter S_COUNT = 4,
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter ID_ENABLE = 0,
    parameter ID_WIDTH = 8,
    parameter DEST_ENABLE = 0,
    parameter DEST_WIDTH = 8,
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    // header width in bytes
    parameter HEADER_WIDTH = 12
)
(
    input  wire                          clk,
    input  wire                          rst,

    
    input  wire [           S_COUNT-1:0]           s_hdr_valid,
    output wire [           S_COUNT-1:0]           s_hdr_ready,
    input  wire [        S_COUNT*HEADER_WIDTH*8-1:0] s_hdr,
    input  wire [S_COUNT*DATA_WIDTH-1:0] s_payload_axis_tdata,
    input  wire [S_COUNT*KEEP_WIDTH-1:0] s_payload_axis_tkeep,
    input  wire [S_COUNT-1:0]            s_payload_axis_tvalid,
    output wire [S_COUNT-1:0]            s_payload_axis_tready,
    input  wire [S_COUNT-1:0]            s_payload_axis_tlast,
    input  wire [S_COUNT*ID_WIDTH-1:0]   s_payload_axis_tid,
    input  wire [S_COUNT*DEST_WIDTH-1:0] s_payload_axis_tdest,
    input  wire [S_COUNT*USER_WIDTH-1:0] s_payload_axis_tuser,

    output wire                                      m_hdr_valid,
    input  wire                                      m_hdr_ready,
    output wire [HEADER_WIDTH*8-1:0] m_hdr,
    output wire [DATA_WIDTH-1:0]         m_payload_axis_tdata,
    output wire [KEEP_WIDTH-1:0]         m_payload_axis_tkeep,
    output wire                          m_payload_axis_tvalid,
    input  wire                          m_payload_axis_tready,
    output wire                          m_payload_axis_tlast,
    output wire [ID_WIDTH-1:0]           m_payload_axis_tid,
    output wire [DEST_WIDTH-1:0]         m_payload_axis_tdest,
    output wire [USER_WIDTH-1:0]         m_payload_axis_tuser,

    /*
     * Control
     */
    input  wire                          enable,
    input  wire [$clog2(S_COUNT)-1:0]    select
);

parameter CL_S_COUNT = $clog2(S_COUNT);

reg [CL_S_COUNT-1:0] select_reg = 2'd0, select_next;
reg frame_reg = 1'b0, frame_next;
reg single_frame_pkt_reg = 1'b0, single_frame_pkt_next;

  reg [S_COUNT-1:0] s_hdr_ready_reg = {S_COUNT{1'b0}}, s_hdr_ready_next;


reg [S_COUNT-1:0] s_payload_axis_tready_reg = 0, s_payload_axis_tready_next;

  reg m_hdr_valid_reg = 1'b0, m_hdr_valid_next;
  reg [HEADER_WIDTH*8-1:0] m_hdr_reg = 0, m_hdr_next;

// internal datapath
reg  [DATA_WIDTH-1:0] m_payload_axis_tdata_int;
reg  [KEEP_WIDTH-1:0] m_payload_axis_tkeep_int;
reg                   m_payload_axis_tvalid_int;
reg                   m_payload_axis_tready_int_reg = 1'b0;
reg                   m_payload_axis_tlast_int;
reg  [ID_WIDTH-1:0]   m_payload_axis_tid_int;
reg  [DEST_WIDTH-1:0] m_payload_axis_tdest_int;
reg  [USER_WIDTH-1:0] m_payload_axis_tuser_int;
wire                  m_payload_axis_tready_int_early;

assign s_hdr_ready = s_hdr_ready_reg;

assign s_payload_axis_tready = s_payload_axis_tready_reg;

assign m_hdr_valid = m_hdr_valid_reg;
assign m_hdr = m_hdr_reg;

// mux for incoming packet
wire [DATA_WIDTH-1:0] current_s_tdata  = s_payload_axis_tdata[select_reg*DATA_WIDTH +: DATA_WIDTH];
wire [KEEP_WIDTH-1:0] current_s_tkeep  = s_payload_axis_tkeep[select_reg*KEEP_WIDTH +: KEEP_WIDTH];
wire                  current_s_tvalid = s_payload_axis_tvalid[select_reg];
wire                  current_s_tready = s_payload_axis_tready[select_reg];
wire                  current_s_tlast  = s_payload_axis_tlast[select_reg];
wire [ID_WIDTH-1:0]   current_s_tid    = s_payload_axis_tid[select_reg*ID_WIDTH +: ID_WIDTH];
wire [DEST_WIDTH-1:0] current_s_tdest  = s_payload_axis_tdest[select_reg*DEST_WIDTH +: DEST_WIDTH];
wire [USER_WIDTH-1:0] current_s_tuser  = s_payload_axis_tuser[select_reg*USER_WIDTH +: USER_WIDTH];

always @* begin
    select_next = select_reg;
    frame_next = frame_reg;

    s_hdr_ready_next = 0;

    s_payload_axis_tready_next = 0;

    m_hdr_valid_next = m_hdr_valid_reg && !m_hdr_ready;
    m_hdr_next = m_hdr_reg;

    if (current_s_tvalid & current_s_tready) begin
        // end of frame detection
        if (current_s_tlast) begin
            frame_next = 1'b0;
        end
    end

    if (!frame_reg && enable && !m_hdr_valid && (s_hdr_valid & (1 << select))) begin
        // start of frame, grab select value
        frame_next = 1'b1;
        select_next = select;

        s_hdr_ready_next = (1 << select);

        m_hdr_valid_next = 1'b1;
        m_hdr_next = s_hdr;
    end

    // generate ready signal on selected port
    s_payload_axis_tready_next = (m_payload_axis_tready_int_early && frame_next) << select_next;

    // pass through selected packet data
    m_payload_axis_tdata_int  = current_s_tdata;
    m_payload_axis_tkeep_int  = current_s_tkeep;
    m_payload_axis_tvalid_int = current_s_tvalid && current_s_tready && frame_reg;
    m_payload_axis_tlast_int  = current_s_tlast;
    m_payload_axis_tid_int    = current_s_tid;
    m_payload_axis_tdest_int  = current_s_tdest;
    m_payload_axis_tuser_int  = current_s_tuser;
end

always @(posedge clk) begin
    if (rst) begin
        select_reg <= 0;
        frame_reg <= 1'b0;
        s_hdr_ready_reg <= 0;
        s_payload_axis_tready_reg <= 0;
        m_hdr_valid_reg <= 1'b0;
    end else begin
        select_reg <= select_next;
        frame_reg <= frame_next;
        s_hdr_ready_reg <= s_hdr_ready_next;
        s_payload_axis_tready_reg <= s_payload_axis_tready_next;
        m_hdr_valid_reg <= m_hdr_valid_next;
    end

    m_hdr_reg <= m_hdr_next;
end

// output datapath logic
reg [DATA_WIDTH-1:0] m_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] m_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  m_payload_axis_tvalid_reg = 1'b0, m_payload_axis_tvalid_next;
reg                  m_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   m_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] m_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] m_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

reg [DATA_WIDTH-1:0] temp_m_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
reg [KEEP_WIDTH-1:0] temp_m_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
reg                  temp_m_payload_axis_tvalid_reg = 1'b0, temp_m_payload_axis_tvalid_next;
reg                  temp_m_payload_axis_tlast_reg  = 1'b0;
reg [ID_WIDTH-1:0]   temp_m_payload_axis_tid_reg    = {ID_WIDTH{1'b0}};
reg [DEST_WIDTH-1:0] temp_m_payload_axis_tdest_reg  = {DEST_WIDTH{1'b0}};
reg [USER_WIDTH-1:0] temp_m_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_payload_axis_tdata  = m_payload_axis_tdata_reg;
assign m_payload_axis_tkeep  = KEEP_ENABLE ? m_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
assign m_payload_axis_tvalid = m_payload_axis_tvalid_reg;
assign m_payload_axis_tlast  = m_payload_axis_tlast_reg;
assign m_payload_axis_tid    = ID_ENABLE   ? m_payload_axis_tid_reg   : {ID_WIDTH{1'b0}};
assign m_payload_axis_tdest  = DEST_ENABLE ? m_payload_axis_tdest_reg : {DEST_WIDTH{1'b0}};
assign m_payload_axis_tuser  = USER_ENABLE ? m_payload_axis_tuser_reg : {USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_payload_axis_tready_int_early = m_payload_axis_tready || (!temp_m_payload_axis_tvalid_reg && !m_payload_axis_tvalid_reg);

always @* begin
    // transfer sink ready state to source
    m_payload_axis_tvalid_next = m_payload_axis_tvalid_reg;
    temp_m_payload_axis_tvalid_next = temp_m_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_payload_axis_tready_int_reg) begin
        // input is ready
        if (m_payload_axis_tready || !m_payload_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_payload_axis_tvalid_next = m_payload_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_payload_axis_tvalid_next = m_payload_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_payload_axis_tready) begin
        // input is not ready, but output is ready
        m_payload_axis_tvalid_next = temp_m_payload_axis_tvalid_reg;
        temp_m_payload_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    m_payload_axis_tvalid_reg <= m_payload_axis_tvalid_next;
    m_payload_axis_tready_int_reg <= m_payload_axis_tready_int_early;
    temp_m_payload_axis_tvalid_reg <= temp_m_payload_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_payload_axis_tdata_reg <= m_payload_axis_tdata_int;
        m_payload_axis_tkeep_reg <= m_payload_axis_tkeep_int;
        m_payload_axis_tlast_reg <= m_payload_axis_tlast_int;
        m_payload_axis_tid_reg   <= m_payload_axis_tid_int;
        m_payload_axis_tdest_reg <= m_payload_axis_tdest_int;
        m_payload_axis_tuser_reg <= m_payload_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_payload_axis_tdata_reg <= temp_m_payload_axis_tdata_reg;
        m_payload_axis_tkeep_reg <= temp_m_payload_axis_tkeep_reg;
        m_payload_axis_tlast_reg <= temp_m_payload_axis_tlast_reg;
        m_payload_axis_tid_reg   <= temp_m_payload_axis_tid_reg;
        m_payload_axis_tdest_reg <= temp_m_payload_axis_tdest_reg;
        m_payload_axis_tuser_reg <= temp_m_payload_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_payload_axis_tdata_reg <= m_payload_axis_tdata_int;
        temp_m_payload_axis_tkeep_reg <= m_payload_axis_tkeep_int;
        temp_m_payload_axis_tlast_reg <= m_payload_axis_tlast_int;
        temp_m_payload_axis_tid_reg   <= m_payload_axis_tid_int;
        temp_m_payload_axis_tdest_reg <= m_payload_axis_tdest_int;
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