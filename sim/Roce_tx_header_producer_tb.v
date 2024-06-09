// Language: Verilog 2001


`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * UDP ethernet frame transmitter (UDP frame in, IP frame out, 64-bit datapath)
 */
module Roce_tx_header_producer_tb ();

  parameter C_CLK_PERIOD = 10;  // Clock period (100 Mhz).    


  // ==========================================================================
  // ==                                Signals                               ==
  // ==========================================================================
  // Simulation (DUT inputs and outputs).
  reg                                    clk;
  reg                                    resetn;

  wire                            [63:0] s_payload_axis_tdata;
  wire                            [ 7:0] s_payload_axis_tkeep;
  wire                                   s_payload_axis_tvalid;
  wire                                   s_payload_axis_tlast;
  wire                                   s_payload_axis_tuser;
  wire                                   s_payload_axis_tready;

  wire                            [63:0] m_udp_payload_axis_tdata;
  wire                            [ 7:0] m_udp_payload_axis_tkeep;
  wire                                   m_udp_payload_axis_tvalid;
  wire                                   m_udp_payload_axis_tlast;
  wire                                   m_udp_payload_axis_tuser;
  wire                                   m_udp_payload_axis_tready;

  wire                            [63:0] m_udp_payload_axis_masked_tdata;
  wire                            [ 7:0] m_udp_payload_axis_masked_tkeep;
  wire                                   m_udp_payload_axis_masked_tvalid;
  wire                                   m_udp_payload_axis_masked_tlast;
  wire                                   m_udp_payload_axis_masked_tuser;
  wire                                   m_udp_payload_axis_masked_tready;

  wire                            [63:0] m_udp_payload_axis_icrc_tdata;
  wire                            [ 7:0] m_udp_payload_axis_icrc_tkeep;
  wire                                   m_udp_payload_axis_icrc_tvalid;
  wire                                   m_udp_payload_axis_icrc_tlast;
  wire                                   m_udp_payload_axis_icrc_tuser;
  wire                                   m_udp_payload_axis_icrc_tready;

  wire                            [63:0] m_roce_payload_axis_tdata;
  wire                            [ 7:0] m_roce_payload_axis_tkeep;
  wire                                   m_roce_payload_axis_tvalid;
  wire                                   m_roce_payload_axis_tlast;
  wire                                   m_roce_payload_axis_tuser;
  wire                                   m_roce_payload_axis_tready;

  wire                                   s_roce_payload_axis_tvalid_1;
  reg                                    s_roce_payload_axis_tvalid_2;

  reg                             [63:0] s_axis_tdata;
  reg                             [ 7:0] s_axis_tkeep;
  reg                                    s_axis_tvalid;
  reg                                    s_axis_tlast;
  reg                                    s_axis_tuser;

  reg                                    m_axis_tready;

  wire                                   m_roce_bth_valid;
  wire                                   m_roce_reth_valid;
  wire                                   m_roce_immdh_valid;
  wire m_roce_bth_ready = 1'b1;
  wire m_roce_reth_ready = 1'b1;
  wire m_roce_immdh_ready = 1'b1;

  wire                            [ 7:0] m_roce_bth_op_code;
  wire                            [15:0] m_roce_bth_p_key;
  wire                            [23:0] m_roce_bth_psn;
  wire                            [23:0] m_roce_bth_dest_qp;
  wire                                   m_roce_bth_ack_req;

  wire                            [63:0] m_roce_reth_v_addr;
  wire                            [31:0] m_roce_reth_r_key;
  wire                            [31:0] m_roce_reth_length;

  wire                            [31:0] m_roce_immdh_data;

  wire                            [47:0] m_eth_dest_mac;
  wire                            [47:0] m_eth_src_mac;
  wire                            [15:0] m_eth_type;
  wire                            [ 3:0] m_ip_version;
  wire                            [ 3:0] m_ip_ihl;
  wire                            [ 5:0] m_ip_dscp;
  wire                            [ 1:0] m_ip_ecn;
  wire                            [15:0] m_ip_identification;
  wire                            [ 2:0] m_ip_flags;
  wire                            [12:0] m_ip_fragment_offset;
  wire                            [ 7:0] m_ip_ttl;
  wire                            [ 7:0] m_ip_protocol;
  wire                            [15:0] m_ip_header_checksum;
  wire                            [31:0] m_ip_source_ip;
  wire                            [31:0] m_ip_dest_ip;
  wire                            [15:0] m_udp_source_port;
  wire                            [15:0] m_udp_dest_port;
  wire                            [15:0] m_udp_length;
  wire                            [15:0] m_udp_checksum;

  reg                             [63:0] word_counter = 64'd0;
  reg                             [32:0] random_value = 32'd0;

  reg                             [31:0] dma_length = 32'd32000;

  reg                                    enable_input;

  wire                                   busy;
  wire                                   error_payload_early_termination;

  integer                                i;
  integer                                j;
  integer                                k;

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


  // ==========================================================================
  // ==                                  DUT                                 ==
  // ==========================================================================

  // Instantiate the DUT.
  Roce_tx_header_producer #(
      .DATA_WIDTH(64)
  ) Roce_tx_header_producer_instance (
      .clk(clk),
      .rst(~resetn),
      .s_dma_length(dma_length),
      .s_rem_qpn(24'd16),
      .s_rem_psn(24'd123456),
      .s_r_key(32'hFEEDBEEF),
      .s_rem_ip_addr(32'h0BD40116),
      .s_rem_addr(48'h12345678),
      .s_axis_tdata(s_payload_axis_tdata),
      .s_axis_tkeep(s_payload_axis_tkeep),
      .s_axis_tvalid(s_payload_axis_tvalid),
      .s_axis_tready(s_payload_axis_tready),
      .s_axis_tlast(s_payload_axis_tlast),
      .s_axis_tuser(s_payload_axis_tuser),
      .m_roce_bth_valid(m_roce_bth_valid),
      .m_roce_bth_ready(m_roce_bth_ready),
      .m_roce_bth_op_code(m_roce_bth_op_code),
      .m_roce_bth_p_key(m_roce_bth_p_key),
      .m_roce_bth_psn(m_roce_bth_psn),
      .m_roce_bth_dest_qp(m_roce_bth_dest_qp),
      .m_roce_bth_ack_req(m_roce_bth_ack_req),
      .m_roce_reth_valid(m_roce_reth_valid),
      .m_roce_reth_ready(m_roce_reth_ready),
      .m_roce_reth_v_addr(m_roce_reth_v_addr),
      .m_roce_reth_r_key(m_roce_reth_r_key),
      .m_roce_reth_length(m_roce_reth_length),
      .m_roce_immdh_valid(m_roce_immdh_valid),
      .m_roce_immdh_ready(m_roce_immdh_ready),
      .m_roce_immdh_data(m_roce_immdh_data),
      .m_eth_dest_mac(m_eth_dest_mac),
      .m_eth_src_mac(m_eth_src_mac),
      .m_eth_type(m_eth_type),
      .m_ip_version(m_ip_version),
      .m_ip_ihl(m_ip_ihl),
      .m_ip_dscp(m_ip_dscp),
      .m_ip_ecn(m_ip_ecn),
      .m_ip_identification(m_ip_identification),
      .m_ip_flags(m_ip_flags),
      .m_ip_fragment_offset(m_ip_fragment_offset),
      .m_ip_ttl(m_ip_ttl),
      .m_ip_protocol(m_ip_protocol),
      .m_ip_header_checksum(m_ip_header_checksum),
      .m_ip_source_ip(m_ip_source_ip),
      .m_ip_dest_ip(m_ip_dest_ip),
      .m_udp_source_port(m_udp_source_port),
      .m_udp_dest_port(m_udp_dest_port),
      .m_udp_length(m_udp_length),
      .m_udp_checksum(m_udp_checksum),
      .m_roce_payload_axis_tdata(m_roce_payload_axis_tdata),
      .m_roce_payload_axis_tkeep(m_roce_payload_axis_tkeep),
      .m_roce_payload_axis_tvalid(m_roce_payload_axis_tvalid),
      .m_roce_payload_axis_tready(1'b1),
      .m_roce_payload_axis_tlast(m_roce_payload_axis_tlast),
      .m_roce_payload_axis_tuser(m_roce_payload_axis_tuser)
  );


  //assign s_roce_payload_axis_tdata = s_axis_tdata;
  assign s_payload_axis_tkeep  = s_payload_axis_tlast ? count2keep(word_counter) : {8{1'b1}};
  assign s_payload_axis_tvalid = ((word_counter + 8  <= dma_length) ? 1'b1 : 1'b0) && enable_input;
  assign s_payload_axis_tlast  = (word_counter + 8 >= dma_length) ? 1'b1 : 1'b0;
  assign s_payload_axis_tuser  = s_axis_tuser;





  // Clock generation.
  always begin
    #(C_CLK_PERIOD / 2) clk = !clk;
  end

  initial begin
    clk = 1'b1;
    resetn = 1'b1;

    s_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
    s_axis_tuser <= 1'b0;
    s_axis_tvalid <= 1'b0;
    s_axis_tlast <= 1'b0;

    enable_input <= 1'b0;




    // Generate first reset.
    #(2 * C_CLK_PERIOD) resetn <= 1'b0;
    #(50 * C_CLK_PERIOD) resetn <= 1'b1;
    #(50 * C_CLK_PERIOD) resetn <= 1'b1;


    #(1 * C_CLK_PERIOD) begin
      s_axis_tvalid <= 1'b1;
      enable_input <= 1'b1;
    end

    //#(1 * C_CLK_PERIOD) begin
    //    s_axis_tvalid <= 1'b0;
    //end


    for (i = 0; i < 50; i = i + 1) begin
      for (j = 0; j < 2; j = j + 1) begin
        #(1 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b1;
          m_axis_tready <= 1'b1;
        end

        #(1 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b1;
          m_axis_tready <= 1'b0;
        end

        #(1 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b0;
          m_axis_tready <= 1'b0;
        end

        #(1 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b1;
          m_axis_tready <= 1'b1;
        end

        #(4 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b1;
          m_axis_tready <= 1'b0;
        end

        //#(1 * C_CLK_PERIOD) begin
        //    s_axis_tvalid <= 1'b1;
        //    s_axis_tlast <= 1'b0;
        //end
      end
      for (i = 0; i < 18; i = i + 1) begin
        #(1 * C_CLK_PERIOD) begin
          s_axis_tvalid <= 1'b1;
          m_axis_tready <= 1'b1;
        end

        //#(1 * C_CLK_PERIOD) begin
        //    s_axis_tvalid <= 1'b1;
        //    s_axis_tlast <= 1'b0;
        //end
      end
      #(1 * C_CLK_PERIOD) begin
        s_axis_tvalid <= 1'b1;
      end

      //#(1 * C_CLK_PERIOD) begin
      //s_axis_tvalid <= 1'b1;
      //s_axis_tlast  <= 1'b1;
      //end

      #(1 * C_CLK_PERIOD) begin
        s_axis_tvalid <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if (~resetn) begin
      word_counter <= 0;
    end
    if (s_payload_axis_tvalid && s_payload_axis_tready) begin
      if ((word_counter <= dma_length)) begin
        word_counter <= word_counter + 8;
        random_value <= $random;
      end
    end else if (word_counter >= dma_length) begin
      word_counter <= 0;
      random_value <= $random;
    end
  end

  assign s_payload_axis_tdata[31:0]  = word_counter;
  assign s_payload_axis_tdata[63:32] = random_value;

endmodule
