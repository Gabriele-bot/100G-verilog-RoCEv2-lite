// Language: Verilog 2001


`resetall 
`timescale 1ns / 1ps 
`default_nettype none

/*
 * UDP ethernet frame transmitter (UDP frame in, IP frame out, 64-bit datapath)
 */
module RoCE_udp_tx_512_tb();

    parameter C_CLK_PERIOD = 10 ; // Clock period (100 Mhz).    


    // ==========================================================================
    // ==                                Signals                               ==
    // ==========================================================================
    // Simulation (DUT inputs and outputs).
    reg clk;
    reg resetn;

    wire [511:0] m_udp_payload_axis_tdata;
    wire [63:0] m_udp_payload_axis_tkeep;
    wire m_udp_payload_axis_tvalid;
    wire m_udp_payload_axis_tlast;
    wire m_udp_payload_axis_tuser;
    wire m_udp_payload_axis_tready;

    wire [511:0] s_roce_payload_axis_tdata;
    wire [63:0] s_roce_payload_axis_tkeep;
    wire s_roce_payload_axis_tvalid;
    wire s_roce_payload_axis_tlast;
    wire s_roce_payload_axis_tuser;
    wire s_roce_payload_axis_tready;

    reg [511:0] s_axis_tdata;
    reg [63:0] s_axis_tkeep;
    reg s_axis_tvalid;
    reg s_axis_tlast;
    reg s_axis_tuser;

    reg m_axis_tready;

    wire s_roce_bth_valid;
    wire s_roce_reth_valid;

    reg s_roce_bth_valid_reg;
    wire s_roce_bth_ready;
    reg s_roce_reth_valid_reg;
    wire s_roce_reth_ready;

    reg [ 7:0] s_roce_bth_op_code = 8'd2;
    reg [15:0] s_roce_bth_p_key = 16'd4552;
    reg [23:0] s_roce_bth_psn = 24'd200;
    reg [23:0] s_roce_bth_dest_qp = 24'd16;
    reg        s_roce_bth_ack_req = 1'd1;

    reg [63:0] s_roce_reth_v_addr = 63'd12435;
    reg [31:0] s_roce_reth_r_key = 32'd233;
    reg [31:0] s_roce_reth_length = 32'd444;

    reg [47:0] s_eth_dest_mac = 48'd12452112311;
    reg [47:0] s_eth_src_mac = 48'd231876543;
    reg [15:0] s_eth_type = 16'd123;
    reg [ 3:0] s_ip_version = 4'd2;
    reg [ 3:0] s_ip_ihl = 4'd2;
    reg [ 5:0] s_ip_dscp = 6'd3;
    reg [ 1:0] s_ip_ecn = 2'd3;
    reg [15:0] s_ip_identification = 16'd44;
    reg [ 2:0] s_ip_flags = 3'd3;
    reg [12:0] s_ip_fragment_offset = 13'd21;
    reg [ 7:0] s_ip_ttl = 8'd42;
    reg [ 7:0] s_ip_protocol = 8'd23;
    reg [15:0] s_ip_header_checksum = 16'd312;
    reg [31:0] s_ip_source_ip = 32'd232;
    reg [31:0] s_ip_dest_ip = 32'd3214;
    reg [15:0] s_udp_source_port = 16'd2321;
    reg [15:0] s_udp_dest_port = 16'd123;
    reg [15:0] s_udp_length = 16'd2052;
    reg [15:0] s_udp_checksum = 16'd0;

    reg[63:0] word_counter = 64'd0;
    reg[32:0] random_value = 32'd0;

    wire busy;
    wire error_payload_early_termination;

    integer i;
    integer j;
    integer k;

    // ==========================================================================
    // ==                                  DUT                                 ==
    // ==========================================================================

    // Instantiate the DUT.
    RoCE_udp_tx_512 RoCE_udp_tx_512_instance(
        .clk(clk),
        .rst(~resetn),
        .s_roce_bth_valid(s_roce_bth_valid),
        .s_roce_bth_ready(s_roce_bth_ready),
        .s_roce_bth_op_code(s_roce_bth_op_code),
        .s_roce_bth_p_key(s_roce_bth_p_key),
        .s_roce_bth_psn(s_roce_bth_psn),
        .s_roce_bth_dest_qp(s_roce_bth_dest_qp),
        .s_roce_bth_ack_req(s_roce_bth_ack_req),
        .s_roce_reth_valid(s_roce_reth_valid),
        .s_roce_reth_ready(s_roce_reth_ready),
        .s_roce_reth_v_addr(s_roce_reth_v_addr),
        .s_roce_reth_r_key(s_roce_reth_r_key),
        .s_roce_reth_length(s_roce_reth_length),
        .s_eth_dest_mac(s_eth_dest_mac),
        .s_eth_src_mac(s_eth_src_mac),
        .s_eth_type(s_eth_type),
        .s_ip_version(s_ip_version),
        .s_ip_ihl(s_ip_ihl),
        .s_ip_dscp(s_ip_dscp),
        .s_ip_ecn(s_ip_ecn),
        .s_ip_identification(s_ip_identification),
        .s_ip_flags(s_ip_flags),
        .s_ip_fragment_offset(s_ip_fragment_offset),
        .s_ip_ttl(s_ip_ttl),
        .s_ip_protocol(s_ip_protocol),
        .s_ip_header_checksum(s_ip_header_checksum),
        .s_ip_source_ip(s_ip_source_ip),
        .s_ip_dest_ip(s_ip_dest_ip),
        .s_udp_source_port(s_udp_source_port),
        .s_udp_dest_port(s_udp_dest_port),
        .s_udp_length(s_udp_length),
        .s_udp_checksum(s_udp_checksum),
        .s_roce_payload_axis_tdata(s_roce_payload_axis_tdata),
        .s_roce_payload_axis_tkeep(s_roce_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(s_roce_payload_axis_tvalid),
        .s_roce_payload_axis_tready(s_roce_payload_axis_tready),
        .s_roce_payload_axis_tlast(s_roce_payload_axis_tlast),
        .s_roce_payload_axis_tuser(1'b0),
        .m_udp_hdr_valid(),
        .m_udp_hdr_ready(),
        .m_eth_dest_mac(),
        .m_eth_src_mac(),
        .m_eth_type(),
        .m_ip_version(),
        .m_ip_ihl(),
        .m_ip_dscp(),
        .m_ip_ecn(),
        .m_ip_length(),
        .m_ip_identification(),
        .m_ip_flags(),
        .m_ip_fragment_offset(),
        .m_ip_ttl(),
        .m_ip_protocol(),
        .m_ip_header_checksum(),
        .m_ip_source_ip(),
        .m_ip_dest_ip(),
        .m_udp_source_port(),
        .m_udp_dest_port(),
        .m_udp_length(),
        .m_udp_checksum(),
        .m_udp_payload_axis_tdata(m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep(m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast(m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser(m_udp_payload_axis_tuser),
        .busy(busy),
        .error_payload_early_termination(error_payload_early_termination)
    );


    //assign s_roce_payload_axis_tdata = s_axis_tdata;
    assign s_roce_payload_axis_tkeep = s_axis_tkeep;
    assign s_roce_payload_axis_tvalid = s_axis_tvalid;
    assign s_roce_payload_axis_tlast = s_axis_tlast;
    assign s_roce_payload_axis_tuser = s_axis_tuser;

    assign s_roce_bth_valid = s_roce_bth_valid_reg;
    assign s_roce_reth_valid = s_roce_reth_valid_reg;

    assign m_udp_payload_axis_tready = m_axis_tready;

    // Clock generation.
    always begin
        #(C_CLK_PERIOD / 2) clk = ! clk;
    end

    initial begin
        clk = 1'b1;
        resetn = 1'b1;

        s_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
        s_axis_tuser <= 1'b0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;

        m_axis_tready <= 1'b0;

        s_roce_bth_valid_reg <= 1'b0;
        s_roce_reth_valid_reg <= 1'b0;




        // Generate first reset.
        #(2 * C_CLK_PERIOD) resetn <= 1'b0;
        #(50 * C_CLK_PERIOD) resetn <= 1'b1;
        #(50 * C_CLK_PERIOD) resetn <= 1'b1;


        #(1 * C_CLK_PERIOD) begin
            s_roce_bth_valid_reg <= 1'b1;
            s_roce_reth_valid_reg <= 1'b1;
            s_axis_tvalid <= 1'b1;
        end

        //#(1 * C_CLK_PERIOD) begin
        //    s_axis_tvalid <= 1'b0;
        //end


        for (i = 0; i < 50; i = i + 1) begin
            for (j = 0; j < 2; j = j + 1) begin
                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b0;
                end

                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b1;
                end

                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b0;
                    m_axis_tready <= 1'b1;
                end

                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
                    s_axis_tvalid <= 1'b1;
                    m_axis_tready <= 1'b1;
                end

                //#(1 * C_CLK_PERIOD) begin
                //    s_axis_tvalid <= 1'b1;
                //    s_axis_tlast <= 1'b0;
                //end
            end
            for (i = 0; i < 18; i = i + 1) begin
                #(1 * C_CLK_PERIOD) begin
                    s_roce_bth_valid_reg <= 1'b0;
                    s_roce_reth_valid_reg <= 1'b0;
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
        if (s_roce_payload_axis_tvalid && s_roce_payload_axis_tready )begin
            word_counter <= word_counter + 64;
            random_value <= $random;
            if (word_counter[63:6]+1 == 32) begin
                s_axis_tlast <= 1'b1;
                s_axis_tkeep <= 64'h000000FFFFFFFFFF;
            end else begin
                s_axis_tlast <= 1'b0;
                s_axis_tkeep <= 64'hFFFFFFFFFFFFFFFF;
            end
        end
    end

    assign s_roce_payload_axis_tdata[63:0] = word_counter;
    assign s_roce_payload_axis_tdata[255:64]  = 196'h0;
    assign s_roce_payload_axis_tdata[287:256] = 32'h02230223;
    assign s_roce_payload_axis_tdata[319:288] = 32'hF224F224;
    assign s_roce_payload_axis_tdata[479:320] = 160'h0;
    assign s_roce_payload_axis_tdata[511:480] = random_value;

endmodule
    
    
    