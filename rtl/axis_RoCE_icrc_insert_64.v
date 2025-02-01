`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * AXI4-Stream RoCEv2 ICRC inserter (512 bit datapath)
 */
module axis_RoCE_icrc_insert_64 (
    input wire clk,
    input wire rst,

    /*
     * AXI frame input
     */
    input  wire [63:0] s_eth_payload_axis_tdata,
    input  wire [ 7:0] s_eth_payload_axis_tkeep,
    input  wire        s_eth_payload_axis_tvalid,
    output wire        s_eth_payload_axis_tready,
    input  wire        s_eth_payload_axis_tlast,
    input  wire [1:0]  s_eth_payload_axis_tuser, // bit 0 malformed packet, bit 1 RoCE id

    /*
     * AXI frame output with ICRC at the end
    */
    output wire [63:0] m_eth_payload_axis_tdata,
    output wire [ 7:0] m_eth_payload_axis_tkeep,
    output wire        m_eth_payload_axis_tvalid,
    input  wire        m_eth_payload_axis_tready,
    output wire        m_eth_payload_axis_tlast,
    output wire        m_eth_payload_axis_tuser,

    /*
     * Status
     */
    output wire busy
);

  localparam [1:0] STATE_IDLE = 2'd0, STATE_PAYLOAD = 2'd1, STATE_ICRC = 2'd2;

  localparam CRC_COMP_LATENCY = 2;

  reg [1:0] state_reg = STATE_IDLE, state_next;

  wire [63:0] axis_to_mask_tdata;
  wire [ 7:0] axis_to_mask_tkeep;
  wire        axis_to_mask_tvalid;
  wire        axis_to_mask_tlast;
  wire [1:0]  axis_to_mask_tuser;
  wire        axis_to_mask_tready;

  wire [63:0] axis_masked_tdata;
  wire [ 7:0] axis_masked_tkeep;
  wire        axis_masked_tvalid;
  wire        axis_masked_tlast;
  wire [1:0]  axis_masked_tuser;
  wire        axis_masked_tready;

  wire [63:0] axis_not_masked_tdata;

  wire [63:0] axis_not_masked_fifo_in_tdata;
  wire [ 7:0] axis_not_masked_fifo_in_tkeep;
  wire        axis_not_masked_fifo_in_tvalid;
  wire        axis_not_masked_fifo_in_tlast;
  wire [1:0]  axis_not_masked_fifo_in_tuser;
  wire        axis_not_masked_fifo_in_tready;

  wire [63:0] axis_not_masked_fifo_out_tdata;
  wire [ 7:0] axis_not_masked_fifo_out_tkeep;
  wire        axis_not_masked_fifo_out_tvalid;
  wire        axis_not_masked_fifo_out_tlast;
  wire [1:0]  axis_not_masked_fifo_out_tuser;
  wire        axis_not_masked_fifo_out_tready;

  wire [63:0] axis_to_icrc_tdata;
  wire [ 7:0] axis_to_icrc_tkeep;
  wire        axis_to_icrc_tvalid;
  wire        axis_to_icrc_tlast;
  wire [1:0]  axis_to_icrc_tuser;
  wire        axis_to_icrc_tready;

  // datapath control signals
  reg          update_crc_request_next;
  reg          update_crc_request_reg;

  reg  [63:0] icrc_s_tdata;
  reg  [ 7:0] icrc_s_tkeep;

  reg  [63:0] icrc_m_tdata_0;
  reg  [63:0] icrc_m_tdata_1;
  reg  [ 7:0] icrc_m_tkeep_0;
  reg  [ 7:0] icrc_m_tkeep_1;

  reg [63:0] last_cycle_tdata_reg = 512'd0, last_cycle_tdata_next;
  reg [7:0] last_cycle_tkeep_reg = 64'd0, last_cycle_tkeep_next;

  reg busy_reg = 1'b0;

  reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

  reg  [ 31:0] crc_state = 32'hDEBB20E3;

  // internal datapath
  reg  [63:0] m_eth_payload_axis_tdata_int;
  reg  [ 7:0] m_eth_payload_axis_tkeep_int;
  reg         m_eth_payload_axis_tvalid_int;
  reg         m_eth_payload_axis_tready_int_reg = 1'b0;
  reg         m_eth_payload_axis_tlast_int;
  reg         m_eth_payload_axis_tuser_int;
  wire        m_eth_payload_axis_tready_int_early;

  wire [ 31:0] crc_out;
  wire         crc_valid_out;
  wire [ 31:0] crc_out_1;
  wire         crc_valid_out_1;
  reg  [ 31:0] icrc_value;

  wire [ 31:0] icrc_to_fifo;
  wire         icrc_to_fifo_valid;

  reg  [ 31:0] icrc_to_output;
  reg          icrc_to_output_valid;


  reg  [63:0] s_axis_tdata_shreg                       [CRC_COMP_LATENCY-1:0];
  reg  [ 7:0] s_axis_tkeep_shreg                       [CRC_COMP_LATENCY-1:0];
  reg         s_axis_tvalid_shreg                      [CRC_COMP_LATENCY-1:0];
  reg         s_axis_tready_shreg                      [CRC_COMP_LATENCY-1:0];
  reg         s_axis_tlast_shreg                       [CRC_COMP_LATENCY-1:0];
  reg [1:0]   s_axis_tuser_shreg                       [CRC_COMP_LATENCY-1:0];

  reg         rst_crc_shreg                            [CRC_COMP_LATENCY-1:0];

  integer i;


  assign busy                      = busy_reg;


  assign axis_to_mask_tdata        = s_eth_payload_axis_tdata;
  assign axis_to_mask_tkeep        = s_eth_payload_axis_tkeep;
  assign axis_to_mask_tvalid       = s_eth_payload_axis_tvalid;
  assign axis_to_mask_tlast        = s_eth_payload_axis_tlast;
  assign axis_to_mask_tuser        = s_eth_payload_axis_tuser;
  assign s_eth_payload_axis_tready = axis_to_mask_tready;

  axis_mask_fields_icrc #(
      .DATA_WIDTH(64),
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
      .DEPTH(64),
      .DATA_WIDTH(64),
      .KEEP_ENABLE(1),
      .KEEP_WIDTH(8),
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

  //PIPELINED 16 CLOCKS LATENCY!!! EASIER ROUTING
  // 16 clocks latency, pipelined!
  CRC32_matrix_pipeline #(
      .DATA_WIDTH(64),
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


  function [3:0] keep2count;
    input [7:0] k;
    casez (k)
      8'bzzzzzzz0: keep2count = 4'd0;
      8'bzzzzzz01: keep2count = 4'd1;
      8'bzzzzz011: keep2count = 4'd2;
      8'bzzzz0111: keep2count = 4'd3;
      8'bzzz01111: keep2count = 4'd4;
      8'bzz011111: keep2count = 4'd5;
      8'bz0111111: keep2count = 4'd6;
      8'b01111111: keep2count = 4'd7;
      8'b11111111: keep2count = 4'd8;
    endcase
  endfunction

  function [7:0] count2keep;
    input [3:0] k;
    case (k)
      4'd0:    count2keep = 8'b00000000;
      4'd1:    count2keep = 8'b00000001;
      4'd2:    count2keep = 8'b00000011;
      4'd3:    count2keep = 8'b00000111;
      4'd4:    count2keep = 8'b00001111;
      4'd5:    count2keep = 8'b00011111;
      4'd6:    count2keep = 8'b00111111;
      4'd7:    count2keep = 8'b01111111;
      4'd8:    count2keep = 8'b11111111;
      default: count2keep = 8'b11111111;
    endcase
  endfunction


  // ICRC cycle calculation
  always @* begin
    casez (icrc_s_tkeep)
      8'h0F: begin
        icrc_m_tdata_0 = {~icrc_to_output, icrc_s_tdata[31:0]};
        icrc_m_tdata_1 = 64'd0;
        icrc_m_tkeep_0 = 8'hFF;
        icrc_m_tkeep_1 = 8'h00;
      end
      8'hFF: begin
        icrc_m_tdata_0 = icrc_s_tdata;
        icrc_m_tdata_1 = {32'd0, ~icrc_to_output};
        icrc_m_tkeep_0 = 64'hFF;
        icrc_m_tkeep_1 = 64'h0F;
      end
      default: begin
        icrc_m_tdata_0 = 64'd0;
        icrc_m_tdata_1 = 64'd0;
        icrc_m_tkeep_0 = 8'd0;
        icrc_m_tkeep_1 = 8'd0;
      end
    endcase
  end

  always @* begin
    state_next                    = STATE_IDLE;


    last_cycle_tdata_next         = last_cycle_tdata_reg;
    last_cycle_tkeep_next         = last_cycle_tkeep_reg;

    s_axis_tready_next            = 1'b0;

    icrc_s_tdata                  = 64'd0;
    icrc_s_tkeep                  = 8'd0;

    m_eth_payload_axis_tdata_int  = 64'd0;
    m_eth_payload_axis_tkeep_int  = 8'd0;
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
              
                if (icrc_m_tkeep_1 == 8'd0) begin
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



                if (icrc_m_tkeep_1 == 8'd0) begin
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
  reg [63:0]  m_eth_payload_axis_tdata_reg = 64'd0;
  reg [ 7:0]  m_eth_payload_axis_tkeep_reg = 8'd0;
  reg m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
  reg         m_eth_payload_axis_tlast_reg = 1'b0;
  reg         m_eth_payload_axis_tuser_reg = 1'b0;

  reg [63:0]  temp_m_eth_payload_axis_tdata_reg = 64'd0;
  reg [ 7:0]  temp_m_eth_payload_axis_tkeep_reg = 8'd0;
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