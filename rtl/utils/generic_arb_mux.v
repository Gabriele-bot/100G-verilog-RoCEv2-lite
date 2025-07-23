`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * arbitrated multiplexer
 */
module generic_arb_mux #(
  parameter S_COUNT = 4,
  parameter DATA_WIDTH = 8,
  parameter KEEP_ENABLE = (DATA_WIDTH > 8),
  parameter KEEP_WIDTH = (DATA_WIDTH / 8),
  parameter ID_ENABLE = 0,
  parameter ID_WIDTH = 8,
  parameter DEST_ENABLE = 0,
  parameter DEST_WIDTH = 8,
  parameter USER_ENABLE = 1,
  parameter USER_WIDTH = 1,
  // select round robin arbitration
  parameter ARB_TYPE_ROUND_ROBIN = 0,
  // LSB priority selection
  parameter ARB_LSB_HIGH_PRIORITY = 1,
  // header width in bytes
  parameter HEADER_WIDTH = 12
) (
  input wire clk,
  input wire rst,

  
  input  wire [           S_COUNT-1:0]           s_hdr_valid,
  output wire [           S_COUNT-1:0]           s_hdr_ready,
  input  wire [        S_COUNT*HEADER_WIDTH*8-1:0] s_hdr,
  input  wire [S_COUNT*DATA_WIDTH-1:0]           s_payload_axis_tdata,
  input  wire [S_COUNT*KEEP_WIDTH-1:0]           s_payload_axis_tkeep,
  input  wire [           S_COUNT-1:0]           s_payload_axis_tvalid,
  output wire [           S_COUNT-1:0]           s_payload_axis_tready,
  input  wire [           S_COUNT-1:0]           s_payload_axis_tlast,
  input  wire [  S_COUNT*ID_WIDTH-1:0]           s_payload_axis_tid,
  input  wire [S_COUNT*DEST_WIDTH-1:0]           s_payload_axis_tdest,
  input  wire [S_COUNT*USER_WIDTH-1:0]           s_payload_axis_tuser,

  
  output wire                       m_hdr_valid,
  input  wire                       m_hdr_ready,
  output wire [HEADER_WIDTH*8-1:0]  m_hdr,
  output wire [DATA_WIDTH-1:0]      m_payload_axis_tdata,
  output wire [KEEP_WIDTH-1:0]      m_payload_axis_tkeep,
  output wire                       m_payload_axis_tvalid,
  input  wire                       m_payload_axis_tready,
  output wire                       m_payload_axis_tlast,
  output wire [  ID_WIDTH-1:0]      m_payload_axis_tid,
  output wire [DEST_WIDTH-1:0]      m_payload_axis_tdest,
  output wire [USER_WIDTH-1:0]      m_payload_axis_tuser
);

  parameter CL_S_COUNT = $clog2(S_COUNT);

  reg frame_reg = 1'b0, frame_next;
  reg single_frame_pkt_reg = 1'b0, single_frame_pkt_next;

  reg [S_COUNT-1:0] s_hdr_ready_reg = {S_COUNT{1'b0}}, s_hdr_ready_next;

  reg m_hdr_valid_reg = 1'b0, m_hdr_valid_next;
  reg [HEADER_WIDTH*8-1:0] m_hdr_reg = 0, m_hdr_next;

  wire [   S_COUNT-1:0] request;
  wire [   S_COUNT-1:0] acknowledge;
  wire [   S_COUNT-1:0] grant;
  reg  [   S_COUNT-1:0] grant_del;
  wire                  grant_valid;
  reg                   grant_valid_del;
  wire [CL_S_COUNT-1:0] grant_encoded;

  // internal datapath
  reg  [DATA_WIDTH-1:0] m_payload_axis_tdata_int;
  reg  [KEEP_WIDTH-1:0] m_payload_axis_tkeep_int;
  reg                   m_payload_axis_tvalid_int;
  reg                   m_payload_axis_tready_int_reg = 1'b0;
  reg                   m_payload_axis_tlast_int;
  reg  [  ID_WIDTH-1:0] m_payload_axis_tid_int;
  reg  [DEST_WIDTH-1:0] m_payload_axis_tdest_int;
  reg  [USER_WIDTH-1:0] m_payload_axis_tuser_int;
  wire                  m_payload_axis_tready_int_early;

  wire [S_COUNT-1:0] ack_hdr;
  reg  [S_COUNT-1:0] ack_hdr_reg;
  wire [S_COUNT-1:0] ack_payload;
  reg  [S_COUNT-1:0] ack_payload_reg;

  reg hdr_first;
  reg payload_first;

  assign s_hdr_ready = s_hdr_ready_reg;

  assign s_payload_axis_tready = (m_payload_axis_tready_int_reg && grant_valid) << grant_encoded;
  //assign s_payload_axis_tready = m_payload_axis_tready_int_reg << grant_encoded;

  assign m_hdr_valid = m_hdr_valid_reg;
  assign m_hdr = m_hdr_reg;

  // mux for incoming packet
  wire [DATA_WIDTH-1:0] current_s_tdata  = s_payload_axis_tdata[grant_encoded*DATA_WIDTH +: DATA_WIDTH];
  wire [KEEP_WIDTH-1:0] current_s_tkeep  = s_payload_axis_tkeep[grant_encoded*KEEP_WIDTH +: KEEP_WIDTH];
  wire current_s_tvalid = s_payload_axis_tvalid[grant_encoded];
  wire current_s_tready = s_payload_axis_tready[grant_encoded];
  wire current_s_tlast = s_payload_axis_tlast[grant_encoded];
  wire [ID_WIDTH-1:0] current_s_tid = s_payload_axis_tid[grant_encoded*ID_WIDTH+:ID_WIDTH];
  wire [DEST_WIDTH-1:0] current_s_tdest  = s_payload_axis_tdest[grant_encoded*DEST_WIDTH +: DEST_WIDTH];
  wire [USER_WIDTH-1:0] current_s_tuser  = s_payload_axis_tuser[grant_encoded*USER_WIDTH +: USER_WIDTH];

  // arbiter instance
  arbiter #(
    .PORTS(S_COUNT),
    .ARB_TYPE_ROUND_ROBIN(ARB_TYPE_ROUND_ROBIN),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .ARB_LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
  ) arb_inst (
    .clk(clk),
    .rst(rst),
    .request(request),
    .acknowledge(acknowledge),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_encoded(grant_encoded)
  );

  always @(posedge clk) begin
    grant_del <= grant;
    grant_valid_del <= grant_valid;
  end

  // case if tlast comes before hdr_ready
  assign ack_hdr     = grant & s_hdr_valid & s_hdr_ready;
  assign ack_payload = grant & s_payload_axis_tvalid & s_payload_axis_tready & s_payload_axis_tlast;

  always @(posedge clk) begin

    if (rst) begin
      ack_hdr_reg <= 0;
      ack_payload_reg <= 0;
      hdr_first <= 1'b0;
      payload_first <= 1'b0;
    end else begin
      // case if hdr comes before tlast (usual case)
      if (ack_hdr != 0) begin
        if (ack_hdr != ack_payload && ~payload_first) begin
          ack_hdr_reg <= ack_hdr;
          hdr_first <= 1'b1;
        end
      end
      if (ack_hdr_reg != 0) begin
        if (ack_hdr_reg == ack_payload && hdr_first) begin
          ack_hdr_reg <= 0;
          hdr_first <= 1'b0;
        end
      end

      // case if tlast comes before hdr (happens if payload is only 1 frame)
      if (ack_payload != 0) begin
        if (ack_payload != ack_hdr && ~hdr_first) begin
          ack_payload_reg <= ack_payload;
          payload_first <= 1'b1;
        end
      end
      if (ack_payload_reg != 0) begin
        if (ack_payload_reg == ack_hdr && payload_first) begin
          ack_payload_reg <= 0;
          payload_first <= 1'b0;
        end
      end
    end
  end



  //assign request = (s_hdr_valid & ~s_hdr_valid_del) & ~grant;
  assign request = s_hdr_valid & ~grant & ~grant_del;
  //assign acknowledge = grant & s_payload_axis_tvalid & s_payload_axis_tready & s_payload_axis_tlast;
  assign acknowledge = hdr_first ? ack_hdr_reg & ack_payload : (payload_first ? ack_hdr & ack_payload_reg : ack_hdr & ack_payload);

  always @* begin
    frame_next = frame_reg;
    single_frame_pkt_next = single_frame_pkt_reg;

    s_hdr_ready_next = {S_COUNT{1'b0}};

    m_hdr_valid_next = m_hdr_valid_reg && !m_hdr_ready;
    m_hdr_next = m_hdr_reg;

    if (s_payload_axis_tvalid[grant_encoded] && s_payload_axis_tready[grant_encoded]) begin
      // end of frame detection
      if (s_payload_axis_tlast[grant_encoded]) begin
        frame_next = 1'b0;
      end
    //end else if (single_frame_pkt_reg) begin
      //frame_next = 1'b0;
    end

    // case if frame_next is stuck to 1'b1
    if (frame_reg && acknowledge != 0) begin
      frame_next = 1'b0;
    end

    if (!frame_reg && grant_valid && (m_hdr_ready || !m_hdr_valid)) begin
      // start of frame
      frame_next = 1'b1;

      s_hdr_ready_next = grant;

      single_frame_pkt_next = s_payload_axis_tvalid[grant_encoded] & s_payload_axis_tlast[grant_encoded];

      m_hdr_valid_next = 1'b1;
      m_hdr_next = s_hdr[grant_encoded*HEADER_WIDTH*8+:HEADER_WIDTH*8];
    end

    if (single_frame_pkt_reg) begin
      single_frame_pkt_next = 1'b0;
    end



    // pass through selected packet data
    m_payload_axis_tdata_int = current_s_tdata;
    m_payload_axis_tkeep_int = current_s_tkeep;
    m_payload_axis_tvalid_int = current_s_tvalid && m_payload_axis_tready_int_reg && grant_valid;
    //m_payload_axis_tvalid_int = current_s_tvalid && m_payload_axis_tready_int_reg;
    m_payload_axis_tlast_int = current_s_tlast;
    m_payload_axis_tid_int = current_s_tid;
    m_payload_axis_tdest_int = current_s_tdest;
    m_payload_axis_tuser_int = current_s_tuser;
  end

  always @(posedge clk) begin
    frame_reg <= frame_next;
    single_frame_pkt_reg <= single_frame_pkt_next;

    s_hdr_ready_reg <= s_hdr_ready_next;

    m_hdr_valid_reg <= m_hdr_valid_next;
    m_hdr_reg <= m_hdr_next;

    if (rst) begin
      frame_reg <= 1'b0;
      single_frame_pkt_reg <= 1'b0;
      s_hdr_ready_reg <= {S_COUNT{1'b0}};
      m_hdr_valid_reg <= 1'b0;
      m_hdr_reg       <= {HEADER_WIDTH*8{1'b0}};
    end
  end

  // output datapath logic
  reg [DATA_WIDTH-1:0] m_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] m_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
  reg m_payload_axis_tvalid_reg = 1'b0, m_payload_axis_tvalid_next;
  reg                  m_payload_axis_tlast_reg = 1'b0;
  reg [  ID_WIDTH-1:0] m_payload_axis_tid_reg = {ID_WIDTH{1'b0}};
  reg [DEST_WIDTH-1:0] m_payload_axis_tdest_reg = {DEST_WIDTH{1'b0}};
  reg [USER_WIDTH-1:0] m_payload_axis_tuser_reg = {USER_WIDTH{1'b0}};

  reg [DATA_WIDTH-1:0] temp_m_payload_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] temp_m_payload_axis_tkeep_reg = {KEEP_WIDTH{1'b0}};
  reg temp_m_payload_axis_tvalid_reg = 1'b0, temp_m_payload_axis_tvalid_next;
  reg                  temp_m_payload_axis_tlast_reg = 1'b0;
  reg [  ID_WIDTH-1:0] temp_m_payload_axis_tid_reg = {ID_WIDTH{1'b0}};
  reg [DEST_WIDTH-1:0] temp_m_payload_axis_tdest_reg = {DEST_WIDTH{1'b0}};
  reg [USER_WIDTH-1:0] temp_m_payload_axis_tuser_reg = {USER_WIDTH{1'b0}};

  // datapath control
  reg                  store_axis_int_to_output;
  reg                  store_axis_int_to_temp;
  reg                  store_payload_axis_temp_to_output;

  assign m_payload_axis_tdata = m_payload_axis_tdata_reg;
  assign m_payload_axis_tkeep = KEEP_ENABLE ? m_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
  assign m_payload_axis_tvalid = m_payload_axis_tvalid_reg;
  assign m_payload_axis_tlast = m_payload_axis_tlast_reg;
  assign m_payload_axis_tid = ID_ENABLE ? m_payload_axis_tid_reg : {ID_WIDTH{1'b0}};
  assign m_payload_axis_tdest = DEST_ENABLE ? m_payload_axis_tdest_reg : {DEST_WIDTH{1'b0}};
  assign m_payload_axis_tuser = USER_ENABLE ? m_payload_axis_tuser_reg : {USER_WIDTH{1'b0}};

  // enable ready input next cycle if output is ready or if both output registers are empty
  //assign m_payload_axis_tready_int_early = m_payload_axis_tready || (!temp_m_payload_axis_tvalid_reg && !m_payload_axis_tvalid_reg)
  assign m_payload_axis_tready_int_early = (m_payload_axis_tready || (!temp_m_payload_axis_tvalid_reg && !m_payload_axis_tvalid_reg)) && grant_valid;

  always @* begin
    // transfer sink ready state to source
    m_payload_axis_tvalid_next = m_payload_axis_tvalid_reg;
    temp_m_payload_axis_tvalid_next = temp_m_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_payload_axis_temp_to_output = 1'b0;

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
      store_payload_axis_temp_to_output = 1'b1;
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
    end else if (store_payload_axis_temp_to_output) begin
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