`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * AXI4-Stream RoCEv2 ICRC inserter (512 bit datapath)
 */
module axis_RoCE_icrc_insert_512 #
  (
    parameter PIPELINED_COMPUTATION = 1 
  ) (
    input wire clk,
    input wire rst,

    /*
     * AXI frame input
     */
    input  wire [511:0] s_eth_payload_axis_tdata,
    input  wire [ 63:0] s_eth_payload_axis_tkeep,
    input  wire         s_eth_payload_axis_tvalid,
    output wire         s_eth_payload_axis_tready,
    input  wire         s_eth_payload_axis_tlast,
    input  wire [1:0]   s_eth_payload_axis_tuser, // bit 0 malformed packet, bit 1 RoCE id

    /*
     * AXI frame output with ICRC at the end
    */
    output wire [511:0] m_eth_payload_axis_tdata,
    output wire [ 63:0] m_eth_payload_axis_tkeep,
    output wire         m_eth_payload_axis_tvalid,
    input  wire         m_eth_payload_axis_tready,
    output wire         m_eth_payload_axis_tlast,
    output wire         m_eth_payload_axis_tuser,

    /*
     * Status
     */
    output wire busy
);

  localparam [1:0] STATE_IDLE = 2'd0, STATE_PAYLOAD = 2'd1, STATE_ICRC = 2'd2;

  localparam CRC_COMP_LATENCY = PIPELINED_COMPUTATION ? 16 : 3;

  reg [1:0] state_reg = STATE_IDLE, state_next;

  wire [511:0] axis_to_mask_tdata;
  wire [ 63:0] axis_to_mask_tkeep;
  wire         axis_to_mask_tvalid;
  wire         axis_to_mask_tlast;
  wire [1:0]   axis_to_mask_tuser;
  wire         axis_to_mask_tready;

  wire [511:0] axis_masked_tdata;
  wire [ 63:0] axis_masked_tkeep;
  wire         axis_masked_tvalid;
  wire         axis_masked_tlast;
  wire [1:0]   axis_masked_tuser;
  wire         axis_masked_tready;

  wire [511:0] axis_not_masked_tdata;

  wire [511:0] axis_not_masked_fifo_in_tdata;
  wire [ 63:0] axis_not_masked_fifo_in_tkeep;
  wire         axis_not_masked_fifo_in_tvalid;
  wire         axis_not_masked_fifo_in_tlast;
  wire [1:0]   axis_not_masked_fifo_in_tuser;
  wire         axis_not_masked_fifo_in_tready;

  wire [511:0] axis_not_masked_fifo_out_tdata;
  wire [ 63:0] axis_not_masked_fifo_out_tkeep;
  wire         axis_not_masked_fifo_out_tvalid;
  wire         axis_not_masked_fifo_out_tlast;
  wire [1:0]   axis_not_masked_fifo_out_tuser;
  wire         axis_not_masked_fifo_out_tready;

  wire [511:0] axis_to_icrc_tdata;
  wire [ 63:0] axis_to_icrc_tkeep;
  wire         axis_to_icrc_tvalid;
  wire         axis_to_icrc_tlast;
  wire [1:0]   axis_to_icrc_tuser;
  wire         axis_to_icrc_tready;

  // datapath control signals
  reg          update_crc_request_next;
  reg          update_crc_request_reg;

  reg  [511:0] icrc_s_tdata;
  reg  [ 63:0] icrc_s_tkeep;

  reg  [511:0] icrc_m_tdata_0;
  reg  [511:0] icrc_m_tdata_1;
  reg  [ 63:0] icrc_m_tkeep_0;
  reg  [ 63:0] icrc_m_tkeep_1;

  reg [15:0] frame_ptr_reg = 16'd0, frame_ptr_next;

  reg [511:0] last_cycle_tdata_reg = 512'd0, last_cycle_tdata_next;
  reg [63:0] last_cycle_tkeep_reg = 64'd0, last_cycle_tkeep_next;

  reg busy_reg = 1'b0;

  reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

  reg  [ 31:0] crc_state = 32'hDEBB20E3;

  // internal datapath
  reg  [511:0] m_eth_payload_axis_tdata_int;
  reg  [ 63:0] m_eth_payload_axis_tkeep_int;
  reg          m_eth_payload_axis_tvalid_int;
  reg          m_eth_payload_axis_tready_int_reg = 1'b0;
  reg          m_eth_payload_axis_tlast_int;
  reg          m_eth_payload_axis_tuser_int;
  wire         m_eth_payload_axis_tready_int_early;

  wire [ 31:0] crc_out;
  wire         crc_valid_out;
  wire [ 31:0] crc_out_1;
  wire         crc_valid_out_1;
  reg  [ 31:0] icrc_value;

  wire [ 31:0] icrc_to_fifo;
  wire         icrc_to_fifo_valid;

  reg  [ 31:0] icrc_to_output;
  reg          icrc_to_output_valid;


  reg  [511:0] s_axis_tdata_shreg                       [CRC_COMP_LATENCY-1:0];
  reg  [ 63:0] s_axis_tkeep_shreg                       [CRC_COMP_LATENCY-1:0];
  reg          s_axis_tvalid_shreg                      [CRC_COMP_LATENCY-1:0];
  reg          s_axis_tready_shreg                      [CRC_COMP_LATENCY-1:0];
  reg          s_axis_tlast_shreg                       [CRC_COMP_LATENCY-1:0];
  reg [1:0]    s_axis_tuser_shreg                       [CRC_COMP_LATENCY-1:0];

  reg          rst_crc_shreg                            [CRC_COMP_LATENCY-1:0];

  integer i;


  assign busy                      = busy_reg;


  assign axis_to_mask_tdata        = s_eth_payload_axis_tdata;
  assign axis_to_mask_tkeep        = s_eth_payload_axis_tkeep;
  assign axis_to_mask_tvalid       = s_eth_payload_axis_tvalid;
  assign axis_to_mask_tlast        = s_eth_payload_axis_tlast;
  assign axis_to_mask_tuser        = s_eth_payload_axis_tuser;
  assign s_eth_payload_axis_tready = axis_to_mask_tready;

  axis_mask_fields_icrc #(
      .DATA_WIDTH(512),
      .USER_WIDTH(2)
  ) axis_mask_fields_icrc_instance (
      .clk(clk),
      .rst(rst),
      .s_axis_tdata(axis_to_mask_tdata),
      .s_axis_tkeep(axis_to_mask_tkeep),
      .s_axis_tvalid(axis_to_mask_tvalid),
      .s_axis_tready(axis_to_mask_tready),
      .s_axis_tlast(axis_to_mask_tlast),
      .s_axis_tuser(axis_to_mask_tuser),
      .m_axis_masked_tdata(axis_masked_tdata),
      .m_axis_masked_tkeep(axis_masked_tkeep),
      .m_axis_masked_tvalid(axis_masked_tvalid),
      .m_axis_masked_tready(axis_masked_tready),
      .m_axis_masked_tlast(axis_masked_tlast),
      .m_axis_masked_tuser(axis_masked_tuser),
      .m_axis_not_masked_tdata(axis_not_masked_tdata)
  );

  always @(posedge clk) begin
    if (axis_masked_tready) begin
      s_axis_tdata_shreg[0]  <= axis_not_masked_tdata;
      s_axis_tkeep_shreg[0]  <= axis_masked_tkeep;
      s_axis_tvalid_shreg[0] <= axis_masked_tvalid;
      s_axis_tlast_shreg[0]  <= axis_masked_tlast;
      s_axis_tuser_shreg[0]  <= axis_masked_tuser;

      for (i = 1; i < CRC_COMP_LATENCY; i = i + 1) begin
        s_axis_tdata_shreg [i]  <= s_axis_tdata_shreg [i-1];
        s_axis_tkeep_shreg [i]  <= s_axis_tkeep_shreg [i-1];
        s_axis_tvalid_shreg[i]  <= s_axis_tvalid_shreg[i-1];
        s_axis_tlast_shreg [i]  <= s_axis_tlast_shreg [i-1];
        s_axis_tuser_shreg [i]  <= s_axis_tuser_shreg [i-1];
      end
    end

  end

  assign axis_not_masked_fifo_in_tdata = s_axis_tdata_shreg  [CRC_COMP_LATENCY-1];
  assign axis_not_masked_fifo_in_tkeep = s_axis_tkeep_shreg  [CRC_COMP_LATENCY-1];
  assign axis_not_masked_fifo_in_tvalid = s_axis_tvalid_shreg[CRC_COMP_LATENCY-1];
  assign axis_not_masked_fifo_in_tlast = s_axis_tlast_shreg  [CRC_COMP_LATENCY-1];
  assign axis_not_masked_fifo_in_tuser = s_axis_tuser_shreg  [CRC_COMP_LATENCY-1];
  assign axis_masked_tready = axis_not_masked_fifo_in_tready;



  axis_fifo #(
      .DEPTH(512),
      .DATA_WIDTH(512),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(64),
      .ID_ENABLE(0),
      .DEST_ENABLE(0),
      .USER_ENABLE(1),
      .USER_WIDTH(2),
      .FRAME_FIFO(0)
  ) masked_axis_fifo (
      .clk(clk),
      .rst(rst),

      // AXI input
      .s_axis_tdata(axis_not_masked_fifo_in_tdata),
      .s_axis_tkeep(axis_not_masked_fifo_in_tkeep),
      .s_axis_tvalid(axis_not_masked_fifo_in_tvalid),
      .s_axis_tready(axis_not_masked_fifo_in_tready),
      .s_axis_tlast(axis_not_masked_fifo_in_tlast),
      .s_axis_tid(0),
      .s_axis_tdest(0),
      .s_axis_tuser(axis_not_masked_fifo_in_tuser),

      // AXI output
      .m_axis_tdata(axis_not_masked_fifo_out_tdata),
      .m_axis_tkeep(axis_not_masked_fifo_out_tkeep),
      .m_axis_tvalid(axis_not_masked_fifo_out_tvalid),
      .m_axis_tready(axis_not_masked_fifo_out_tready),
      .m_axis_tlast(axis_not_masked_fifo_out_tlast),
      .m_axis_tid(),
      .m_axis_tdest(),
      .m_axis_tuser(axis_not_masked_fifo_out_tuser),

      // Status
      .status_overflow  (),
      .status_bad_frame (),
      .status_good_frame()
  );

  assign axis_to_icrc_tdata = axis_not_masked_fifo_out_tdata;
  assign axis_to_icrc_tkeep = axis_not_masked_fifo_out_tkeep;
  assign axis_to_icrc_tvalid = axis_not_masked_fifo_out_tvalid;
  assign axis_not_masked_fifo_out_tready = axis_to_icrc_tready;
  assign axis_to_icrc_tlast = axis_not_masked_fifo_out_tlast;
  assign axis_to_icrc_tuser = axis_not_masked_fifo_out_tuser;

  assign axis_to_icrc_tready = s_axis_tready_reg;

  always @(posedge clk) begin

    rst_crc_shreg[0] <= axis_masked_tlast & axis_masked_tready & axis_masked_tvalid;

    for (i = 1; i < CRC_COMP_LATENCY; i = i + 1) begin
      rst_crc_shreg[i] <= rst_crc_shreg[i-1];
    end

  end

  
  generate
    if (PIPELINED_COMPUTATION) begin
      //PIPELINED 16 CLOCKS LATENCY!!! EASIER ROUTING
      // 16 clocks latency, pipelined!
      CRC32_D512_matrix_pipeline #(
          .crc_poly(32'h04C11DB7),
          .crc_init(32'hDEBB20E3),
          .reverse_result(1'b0),
          .finxor(32'h00000000)
      ) CRC32_D512_matrix_pipeline_instance (
          .clk(clk),
          .rst(rst),
          .rst_crc(rst_crc_shreg[CRC_COMP_LATENCY-1]),
          .data_in(axis_masked_tdata),
          .keep_in(axis_masked_tkeep),
          .valid_in(axis_masked_tvalid && axis_masked_tready),
          .crcout(crc_out),
          .valid_crc_out(crc_valid_out)  // crc is valid after 16 clocks upon axis valid  reception 
      );
    end else begin
      //NOT PIPELINED 3 CLOCKS LATENCY!!! LOT OF RESOURCES!
      // 3 clocks latency, pipelined!
      CRC32_D512_matrix #(
          .crc_poly(32'h04C11DB7),
          .crc_init(32'hDEBB20E3),
          .reverse_result(1'b0),
          .finxor(32'h00000000)
      ) CRC32_D512_matrix_instance (
          .clk(clk),
          .rst(rst),
          .rst_crc(rst_crc_shreg[CRC_COMP_LATENCY-1]),
          .data_in(axis_masked_tdata),
          .keep_in(axis_masked_tkeep),
          .valid_in(axis_masked_tvalid && axis_masked_tready),
          .crcout(crc_out),
          .valid_crc_out(crc_valid_out)  // crc is valid after 3 clocks upon axis valid  reception 
      );
    end
  endgenerate
  
  assign icrc_to_fifo = crc_out;
  //assign icrc_to_fifo_valid = rst_crc_shreg[2] & crc_valid_out;
  assign icrc_to_fifo_valid = rst_crc_shreg[CRC_COMP_LATENCY-1];


  always @* begin
    update_crc_request_next = update_crc_request_reg;
    if (rst_crc_shreg[CRC_COMP_LATENCY-1]) begin
      update_crc_request_next = 1'b0;
    end else if (m_eth_payload_axis_tlast_int) begin
      update_crc_request_next = 1'b1;
    end
  end

  always @(posedge clk) begin

    if (rst) begin

      icrc_value     <= 32'hDEADBEEF;
      icrc_to_output <= 32'hDEADBEEF;

    end else begin
      icrc_value <= icrc_to_fifo_valid ? icrc_to_fifo : icrc_value;

      if (update_crc_request_reg | m_eth_payload_axis_tlast_int) begin
        if (icrc_to_fifo_valid) begin
          // new crc value is passed through if an update is requested and a new CRC value is ready  
          icrc_to_output <= icrc_to_fifo;
        end else if (icrc_to_output != icrc_value) begin
          // triggers if the two values are not equal, a crc update happened
          icrc_to_output <= icrc_value;
        end
        //end else begin
        //icrc_to_output <= icrc_value;
      end
    end
  end


  function [15:0] keep2count;
    input [63:0] k;
    casez (k)
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0: keep2count = 16'd0;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01: keep2count = 16'd1;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011: keep2count = 16'd2;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111: keep2count = 16'd3;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111: keep2count = 16'd4;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111: keep2count = 16'd5;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111: keep2count = 16'd6;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111: keep2count = 16'd7;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111: keep2count = 16'd8;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111: keep2count = 16'd9;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111: keep2count = 16'd10;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111: keep2count = 16'd11;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111: keep2count = 16'd12;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111: keep2count = 16'd13;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111: keep2count = 16'd14;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111: keep2count = 16'd15;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111: keep2count = 16'd16;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111: keep2count = 16'd17;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111: keep2count = 16'd18;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111: keep2count = 16'd19;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111: keep2count = 16'd20;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111: keep2count = 16'd21;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111: keep2count = 16'd22;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111: keep2count = 16'd23;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111: keep2count = 16'd24;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111: keep2count = 16'd25;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111: keep2count = 16'd26;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111: keep2count = 16'd27;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111: keep2count = 16'd28;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111: keep2count = 16'd29;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111: keep2count = 16'd30;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111: keep2count = 16'd31;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111: keep2count = 16'd32;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111: keep2count = 16'd33;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111: keep2count = 16'd34;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111: keep2count = 16'd35;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111: keep2count = 16'd36;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111: keep2count = 16'd37;
      64'bzzzzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111: keep2count = 16'd38;
      64'bzzzzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111: keep2count = 16'd39;
      64'bzzzzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111: keep2count = 16'd40;
      64'bzzzzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111: keep2count = 16'd41;
      64'bzzzzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111: keep2count = 16'd42;
      64'bzzzzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111: keep2count = 16'd43;
      64'bzzzzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111: keep2count = 16'd44;
      64'bzzzzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111: keep2count = 16'd45;
      64'bzzzzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111: keep2count = 16'd46;
      64'bzzzzzzzzzzzzzzzz011111111111111111111111111111111111111111111111: keep2count = 16'd47;
      64'bzzzzzzzzzzzzzzz0111111111111111111111111111111111111111111111111: keep2count = 16'd48;
      64'bzzzzzzzzzzzzzz01111111111111111111111111111111111111111111111111: keep2count = 16'd49;
      64'bzzzzzzzzzzzzz011111111111111111111111111111111111111111111111111: keep2count = 16'd50;
      64'bzzzzzzzzzzzz0111111111111111111111111111111111111111111111111111: keep2count = 16'd51;
      64'bzzzzzzzzzzz01111111111111111111111111111111111111111111111111111: keep2count = 16'd52;
      64'bzzzzzzzzzz011111111111111111111111111111111111111111111111111111: keep2count = 16'd53;
      64'bzzzzzzzzz0111111111111111111111111111111111111111111111111111111: keep2count = 16'd54;
      64'bzzzzzzzz01111111111111111111111111111111111111111111111111111111: keep2count = 16'd55;
      64'bzzzzzzz011111111111111111111111111111111111111111111111111111111: keep2count = 16'd56;
      64'bzzzzzz0111111111111111111111111111111111111111111111111111111111: keep2count = 16'd57;
      64'bzzzzz01111111111111111111111111111111111111111111111111111111111: keep2count = 16'd58;
      64'bzzzz011111111111111111111111111111111111111111111111111111111111: keep2count = 16'd59;
      64'bzzz0111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd60;
      64'bzz01111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd61;
      64'bz011111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd62;
      64'b0111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd63;
      64'b1111111111111111111111111111111111111111111111111111111111111111: keep2count = 16'd64;
    endcase
  endfunction

  function [63:0] count2keep;
    input [6:0] k;
    case (k)
      7'd0:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000000;
      7'd1:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000001;
      7'd2:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000011;
      7'd3:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000000111;
      7'd4:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000001111;
      7'd5:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000011111;
      7'd6:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000000111111;
      7'd7:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000001111111;
      7'd8:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000011111111;
      7'd9:    count2keep = 64'b0000000000000000000000000000000000000000000000000000000111111111;
      7'd10:   count2keep = 64'b0000000000000000000000000000000000000000000000000000001111111111;
      7'd11:   count2keep = 64'b0000000000000000000000000000000000000000000000000000011111111111;
      7'd12:   count2keep = 64'b0000000000000000000000000000000000000000000000000000111111111111;
      7'd13:   count2keep = 64'b0000000000000000000000000000000000000000000000000001111111111111;
      7'd14:   count2keep = 64'b0000000000000000000000000000000000000000000000000011111111111111;
      7'd15:   count2keep = 64'b0000000000000000000000000000000000000000000000000111111111111111;
      7'd16:   count2keep = 64'b0000000000000000000000000000000000000000000000001111111111111111;
      7'd17:   count2keep = 64'b0000000000000000000000000000000000000000000000011111111111111111;
      7'd18:   count2keep = 64'b0000000000000000000000000000000000000000000000111111111111111111;
      7'd19:   count2keep = 64'b0000000000000000000000000000000000000000000001111111111111111111;
      7'd20:   count2keep = 64'b0000000000000000000000000000000000000000000011111111111111111111;
      7'd21:   count2keep = 64'b0000000000000000000000000000000000000000000111111111111111111111;
      7'd22:   count2keep = 64'b0000000000000000000000000000000000000000001111111111111111111111;
      7'd23:   count2keep = 64'b0000000000000000000000000000000000000000011111111111111111111111;
      7'd24:   count2keep = 64'b0000000000000000000000000000000000000000111111111111111111111111;
      7'd25:   count2keep = 64'b0000000000000000000000000000000000000001111111111111111111111111;
      7'd26:   count2keep = 64'b0000000000000000000000000000000000000011111111111111111111111111;
      7'd27:   count2keep = 64'b0000000000000000000000000000000000000111111111111111111111111111;
      7'd28:   count2keep = 64'b0000000000000000000000000000000000001111111111111111111111111111;
      7'd29:   count2keep = 64'b0000000000000000000000000000000000011111111111111111111111111111;
      7'd30:   count2keep = 64'b0000000000000000000000000000000000111111111111111111111111111111;
      7'd31:   count2keep = 64'b0000000000000000000000000000000001111111111111111111111111111111;
      7'd32:   count2keep = 64'b0000000000000000000000000000000011111111111111111111111111111111;
      7'd33:   count2keep = 64'b0000000000000000000000000000000111111111111111111111111111111111;
      7'd34:   count2keep = 64'b0000000000000000000000000000001111111111111111111111111111111111;
      7'd35:   count2keep = 64'b0000000000000000000000000000011111111111111111111111111111111111;
      7'd36:   count2keep = 64'b0000000000000000000000000000111111111111111111111111111111111111;
      7'd37:   count2keep = 64'b0000000000000000000000000001111111111111111111111111111111111111;
      7'd38:   count2keep = 64'b0000000000000000000000000011111111111111111111111111111111111111;
      7'd39:   count2keep = 64'b0000000000000000000000000111111111111111111111111111111111111111;
      7'd40:   count2keep = 64'b0000000000000000000000001111111111111111111111111111111111111111;
      7'd41:   count2keep = 64'b0000000000000000000000011111111111111111111111111111111111111111;
      7'd42:   count2keep = 64'b0000000000000000000000111111111111111111111111111111111111111111;
      7'd43:   count2keep = 64'b0000000000000000000001111111111111111111111111111111111111111111;
      7'd44:   count2keep = 64'b0000000000000000000011111111111111111111111111111111111111111111;
      7'd45:   count2keep = 64'b0000000000000000000111111111111111111111111111111111111111111111;
      7'd46:   count2keep = 64'b0000000000000000001111111111111111111111111111111111111111111111;
      7'd47:   count2keep = 64'b0000000000000000011111111111111111111111111111111111111111111111;
      7'd48:   count2keep = 64'b0000000000000000111111111111111111111111111111111111111111111111;
      7'd49:   count2keep = 64'b0000000000000001111111111111111111111111111111111111111111111111;
      7'd50:   count2keep = 64'b0000000000000011111111111111111111111111111111111111111111111111;
      7'd51:   count2keep = 64'b0000000000000111111111111111111111111111111111111111111111111111;
      7'd52:   count2keep = 64'b0000000000001111111111111111111111111111111111111111111111111111;
      7'd53:   count2keep = 64'b0000000000011111111111111111111111111111111111111111111111111111;
      7'd54:   count2keep = 64'b0000000000111111111111111111111111111111111111111111111111111111;
      7'd55:   count2keep = 64'b0000000001111111111111111111111111111111111111111111111111111111;
      7'd56:   count2keep = 64'b0000000011111111111111111111111111111111111111111111111111111111;
      7'd57:   count2keep = 64'b0000000111111111111111111111111111111111111111111111111111111111;
      7'd58:   count2keep = 64'b0000001111111111111111111111111111111111111111111111111111111111;
      7'd59:   count2keep = 64'b0000011111111111111111111111111111111111111111111111111111111111;
      7'd60:   count2keep = 64'b0000111111111111111111111111111111111111111111111111111111111111;
      7'd61:   count2keep = 64'b0001111111111111111111111111111111111111111111111111111111111111;
      7'd62:   count2keep = 64'b0011111111111111111111111111111111111111111111111111111111111111;
      7'd63:   count2keep = 64'b0111111111111111111111111111111111111111111111111111111111111111;
      7'd64:   count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
      default: count2keep = 64'b1111111111111111111111111111111111111111111111111111111111111111;
    endcase
  endfunction


  // ICRC cycle calculation
  always @* begin
    casez (icrc_s_tkeep)
      64'hzzzzzzzzzzzzzz0F: begin
        icrc_m_tdata_0 = {448'd0, ~icrc_to_output, icrc_s_tdata[31:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h00000000000000FF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzzzzzzz0FF: begin
        icrc_m_tdata_0 = {416'd0, ~icrc_to_output, icrc_s_tdata[63:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h0000000000000FFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzzzzzz0FFF: begin
        icrc_m_tdata_0 = {384'd0, ~icrc_to_output, icrc_s_tdata[95:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h000000000000FFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzzzzz0FFFF: begin
        icrc_m_tdata_0 = {352'd0, ~icrc_to_output, icrc_s_tdata[127:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h00000000000FFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzzzz0FFFFF: begin
        icrc_m_tdata_0 = {320'd0, ~icrc_to_output, icrc_s_tdata[159:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h0000000000FFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzzz0FFFFFF: begin
        icrc_m_tdata_0 = {288'd0, ~icrc_to_output, icrc_s_tdata[191:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h000000000FFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzzz0FFFFFFF: begin
        icrc_m_tdata_0 = {256'd0, ~icrc_to_output, icrc_s_tdata[223:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h00000000FFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzzz0FFFFFFFF: begin
        icrc_m_tdata_0 = {224'd0, ~icrc_to_output, icrc_s_tdata[255:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h0000000FFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzzz0FFFFFFFFF: begin
        icrc_m_tdata_0 = {192'd0, ~icrc_to_output, icrc_s_tdata[287:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h000000FFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzzz0FFFFFFFFFF: begin
        icrc_m_tdata_0 = {160'd0, ~icrc_to_output, icrc_s_tdata[319:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h00000FFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzzz0FFFFFFFFFFF: begin
        icrc_m_tdata_0 = {128'd0, ~icrc_to_output, icrc_s_tdata[351:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h0000FFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzzz0FFFFFFFFFFFF: begin
        icrc_m_tdata_0 = {96'd0, ~icrc_to_output, icrc_s_tdata[383:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h000FFFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hzz0FFFFFFFFFFFFF: begin
        icrc_m_tdata_0 = {64'd0, ~icrc_to_output, icrc_s_tdata[415:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h00FFFFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hz0FFFFFFFFFFFFFF: begin
        icrc_m_tdata_0 = {32'd0, ~icrc_to_output, icrc_s_tdata[447:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'h0FFFFFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'h0FFFFFFFFFFFFFFF: begin
        icrc_m_tdata_0 = {~icrc_to_output, icrc_s_tdata[479:0]};
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'hFFFFFFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h0000000000000000;
      end
      64'hFFFFFFFFFFFFFFFF: begin
        icrc_m_tdata_0 = icrc_s_tdata;
        icrc_m_tdata_1 = {480'd0, ~icrc_to_output};
        icrc_m_tkeep_0 = 64'hFFFFFFFFFFFFFFFF;
        icrc_m_tkeep_1 = 64'h000000000000000F;
      end
      default: begin
        icrc_m_tdata_0 = 512'd0;
        icrc_m_tdata_1 = 512'd0;
        icrc_m_tkeep_0 = 64'd0;
        icrc_m_tkeep_1 = 64'd0;
      end
    endcase
  end

  always @* begin
    state_next                    = STATE_IDLE;


    last_cycle_tdata_next         = last_cycle_tdata_reg;
    last_cycle_tkeep_next         = last_cycle_tkeep_reg;

    s_axis_tready_next            = 1'b0;

    icrc_s_tdata                  = 512'd0;
    icrc_s_tkeep                  = 64'd0;

    m_eth_payload_axis_tdata_int  = 512'd0;
    m_eth_payload_axis_tkeep_int  = 64'd0;
    m_eth_payload_axis_tvalid_int = 1'b0;
    m_eth_payload_axis_tlast_int  = 1'b0;
    m_eth_payload_axis_tuser_int  = 2'd0;

    case (state_reg)
      STATE_IDLE: begin
        // idle state - wait for data
        s_axis_tready_next = m_eth_payload_axis_tready_int_early;

        //m_axis_tdata_int = s_axis_tdata_masked;
        //m_axis_tkeep_int = s_axis_tkeep;
        //m_axis_tvalid_int = s_axis_tvalid;
        m_eth_payload_axis_tdata_int = axis_to_icrc_tdata;
        m_eth_payload_axis_tkeep_int = axis_to_icrc_tkeep;
        m_eth_payload_axis_tvalid_int = axis_to_icrc_tvalid;
        m_eth_payload_axis_tlast_int = 1'b0;
        m_eth_payload_axis_tuser_int = 2'd0;

        icrc_s_tdata = axis_to_icrc_tdata;
        icrc_s_tkeep = axis_to_icrc_tkeep;

        if (axis_to_icrc_tready && axis_to_icrc_tvalid) begin
          if (axis_to_icrc_tlast) begin
            if (axis_to_icrc_tuser[0]) begin
              m_eth_payload_axis_tlast_int = 1'b1;
              m_eth_payload_axis_tuser_int = 1'b1;
              state_next = STATE_IDLE;
            end else begin
              if(axis_to_icrc_tuser[1])  begin
                m_eth_payload_axis_tdata_int = icrc_m_tdata_0;
                last_cycle_tdata_next = icrc_m_tdata_1;
                m_eth_payload_axis_tkeep_int = icrc_m_tkeep_0;
                last_cycle_tkeep_next = icrc_m_tkeep_1;
              
                if (icrc_m_tkeep_1 == 64'd0) begin
                  m_eth_payload_axis_tlast_int = 1'b1;
                  s_axis_tready_next = m_eth_payload_axis_tready_int_early;
                  state_next = STATE_IDLE;
                end else begin
                  s_axis_tready_next = 1'b0;
                  state_next = STATE_ICRC;
                end
              end else begin
                m_eth_payload_axis_tdata_int  = axis_to_icrc_tdata;
                m_eth_payload_axis_tkeep_int  = axis_to_icrc_tkeep;
                m_eth_payload_axis_tvalid_int = axis_to_icrc_tvalid;
                m_eth_payload_axis_tlast_int  = axis_to_icrc_tlast;
                m_eth_payload_axis_tuser_int  = axis_to_icrc_tuser;

                state_next = STATE_IDLE;
              end
            end
          end else begin
            state_next = STATE_PAYLOAD;
          end
        end else begin
          state_next = STATE_IDLE;
        end
      end
      STATE_PAYLOAD: begin
        // transfer payload
        s_axis_tready_next = m_eth_payload_axis_tready_int_early;

        m_eth_payload_axis_tdata_int = axis_to_icrc_tdata;
        m_eth_payload_axis_tkeep_int = axis_to_icrc_tkeep;
        m_eth_payload_axis_tvalid_int = axis_to_icrc_tvalid;
        m_eth_payload_axis_tlast_int = 1'b0;
        m_eth_payload_axis_tuser_int = 2'd0;

        icrc_s_tdata = axis_to_icrc_tdata;
        icrc_s_tkeep = axis_to_icrc_tkeep;

        if (axis_to_icrc_tready && axis_to_icrc_tvalid) begin
          //if (axis_masked_tready && s_axis_tvalid_shreg[2]) begin
          if (axis_to_icrc_tlast) begin
            if (axis_to_icrc_tuser[0]) begin
              m_eth_payload_axis_tlast_int = 1'b1;
              m_eth_payload_axis_tuser_int = 1'b1;
              state_next = STATE_IDLE;
            end else begin
              if(axis_to_icrc_tuser[1])  begin
                m_eth_payload_axis_tdata_int = icrc_m_tdata_0;
                last_cycle_tdata_next = icrc_m_tdata_1;
                m_eth_payload_axis_tkeep_int = icrc_m_tkeep_0;
                last_cycle_tkeep_next = icrc_m_tkeep_1;



                if (icrc_m_tkeep_1 == 64'd0) begin
                  m_eth_payload_axis_tlast_int = 1'b1;
                  s_axis_tready_next = m_eth_payload_axis_tready_int_early;
                  state_next = STATE_IDLE;
                end else begin
                  s_axis_tready_next = 1'b0;
                  state_next = STATE_ICRC;
                end
              end else begin
                m_eth_payload_axis_tdata_int  = axis_to_icrc_tdata;
                m_eth_payload_axis_tkeep_int  = axis_to_icrc_tkeep;
                m_eth_payload_axis_tvalid_int = axis_to_icrc_tvalid;
                m_eth_payload_axis_tlast_int  = axis_to_icrc_tlast;
                m_eth_payload_axis_tuser_int  = axis_to_icrc_tuser;

                state_next = STATE_IDLE;
              end
            end

          end else begin
            state_next = STATE_PAYLOAD;
          end
        end else begin
          state_next = STATE_PAYLOAD;
        end
      end
      STATE_ICRC: begin
        // last cycle
        s_axis_tready_next = 1'b0;

        m_eth_payload_axis_tdata_int = last_cycle_tdata_reg;
        m_eth_payload_axis_tkeep_int = last_cycle_tkeep_reg;
        m_eth_payload_axis_tvalid_int = 1'b1;
        m_eth_payload_axis_tlast_int = 1'b1;
        m_eth_payload_axis_tuser_int = 1'b0;

        if (m_eth_payload_axis_tready_int_reg) begin
          s_axis_tready_next = m_eth_payload_axis_tready_int_early;
          state_next = STATE_IDLE;
        end else begin
          state_next = STATE_ICRC;
        end
      end
    endcase
  end



  always @(posedge clk) begin
    if (rst) begin
      state_reg <= STATE_IDLE;

      s_axis_tready_reg <= 1'b0;

      update_crc_request_reg <= 1'b1;

      busy_reg <= 1'b0;

      crc_state <= 32'hDEBB20E3;
    end else begin
      state_reg <= state_next;


      s_axis_tready_reg <= s_axis_tready_next;

      update_crc_request_reg <= update_crc_request_next;

      busy_reg <= state_next != STATE_IDLE;

    end

    last_cycle_tdata_reg <= last_cycle_tdata_next;
    last_cycle_tkeep_reg <= last_cycle_tkeep_next;
  end

  // output datapath logic
  reg [511:0] m_eth_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] m_eth_payload_axis_tkeep_reg = 64'd0;
  reg m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
  reg         m_eth_payload_axis_tlast_reg = 1'b0;
  reg         m_eth_payload_axis_tuser_reg = 1'b0;

  reg [511:0] temp_m_eth_payload_axis_tdata_reg = 512'd0;
  reg [ 63:0] temp_m_eth_payload_axis_tkeep_reg = 64'd0;
  reg temp_m_eth_payload_axis_tvalid_reg = 1'b0, temp_m_eth_payload_axis_tvalid_next;
  reg temp_m_eth_payload_axis_tlast_reg = 1'b0;
  reg temp_m_eth_payload_axis_tuser_reg = 1'b0;

  // datapath control
  reg store_axis_int_to_output;
  reg store_axis_int_to_temp;
  reg store_axis_temp_to_output;

  reg [2:0] store_axis_int_to_output_shreg;
  reg [2:0] store_axis_int_to_temp_shreg;
  reg [2:0] store_axis_temp_to_output_shreg;

  assign m_eth_payload_axis_tdata = m_eth_payload_axis_tdata_reg;
  assign m_eth_payload_axis_tkeep = m_eth_payload_axis_tkeep_reg;
  assign m_eth_payload_axis_tvalid = m_eth_payload_axis_tvalid_reg;
  assign m_eth_payload_axis_tlast = m_eth_payload_axis_tlast_reg;
  assign m_eth_payload_axis_tuser = m_eth_payload_axis_tuser_reg;

  // enable ready input next cycle if output is ready or if both output registers are empty
  assign m_eth_payload_axis_tready_int_early = m_eth_payload_axis_tready || (!temp_m_eth_payload_axis_tvalid_reg && !m_eth_payload_axis_tvalid_reg);

  always @* begin
    // transfer sink ready state to source
    m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_reg;
    temp_m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_eth_payload_axis_tready_int_reg) begin
      // input is ready
      if (m_eth_payload_axis_tready || !m_eth_payload_axis_tvalid_reg) begin
        // output is ready or currently not valid, transfer data to output
        m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
        store_axis_int_to_output = 1'b1;
      end else begin
        // output is not ready, store input in temp
        temp_m_eth_payload_axis_tvalid_next = m_eth_payload_axis_tvalid_int;
        store_axis_int_to_temp = 1'b1;
      end
    end else if (m_eth_payload_axis_tready) begin
      // input is not ready, but output is ready
      m_eth_payload_axis_tvalid_next = temp_m_eth_payload_axis_tvalid_reg;
      temp_m_eth_payload_axis_tvalid_next = 1'b0;
      store_axis_temp_to_output = 1'b1;
    end
  end

  always @(posedge clk) begin
    m_eth_payload_axis_tvalid_reg <= m_eth_payload_axis_tvalid_next;
    m_eth_payload_axis_tready_int_reg <= m_eth_payload_axis_tready_int_early;
    temp_m_eth_payload_axis_tvalid_reg <= temp_m_eth_payload_axis_tvalid_next;

    //store_axis_int_to_output_shreg <= {
    //  store_axis_int_to_output_shreg[1:0], store_axis_int_to_output
    //};
    store_axis_int_to_temp_shreg <= {store_axis_int_to_temp_shreg[1:0], store_axis_int_to_temp};
    store_axis_temp_to_output_shreg <= {
      store_axis_temp_to_output_shreg[1:0], store_axis_temp_to_output
    };

    // datapath
    if (store_axis_int_to_output) begin
      m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
      m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
      m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
      m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
      m_eth_payload_axis_tdata_reg <= temp_m_eth_payload_axis_tdata_reg;
      m_eth_payload_axis_tkeep_reg <= temp_m_eth_payload_axis_tkeep_reg;
      m_eth_payload_axis_tlast_reg <= temp_m_eth_payload_axis_tlast_reg;
      m_eth_payload_axis_tuser_reg <= temp_m_eth_payload_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
      temp_m_eth_payload_axis_tdata_reg <= m_eth_payload_axis_tdata_int;
      temp_m_eth_payload_axis_tkeep_reg <= m_eth_payload_axis_tkeep_int;
      temp_m_eth_payload_axis_tlast_reg <= m_eth_payload_axis_tlast_int;
      temp_m_eth_payload_axis_tuser_reg <= m_eth_payload_axis_tuser_int;
    end

    if (rst) begin
      m_eth_payload_axis_tvalid_reg <= 1'b0;
      m_eth_payload_axis_tready_int_reg <= 1'b0;
      temp_m_eth_payload_axis_tvalid_reg <= 1'b0;
    end
  end

endmodule

`resetall