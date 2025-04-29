`resetall `timescale 1ns / 1ps `default_nettype none

/*
 * AXI4-Stream RoCEv2 ICRC inserter (512 bit datapath)
 */
module axis_RoCE_icrc_insert #
  (
    parameter DATA_WIDTH   = 256,
    parameter CRC_COMP_TYPE = 1, // 0 My implementation, 1 SV implementation
    parameter N_PIPE        = 2 // pipeline reg within SV CRC module 
) (
    input wire clk,
    input wire rst,

    /*
     * AXI frame input
     */
    input  wire [DATA_WIDTH   - 1 : 0] s_eth_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 : 0] s_eth_payload_axis_tkeep,
    input  wire         s_eth_payload_axis_tvalid,
    output wire         s_eth_payload_axis_tready,
    input  wire         s_eth_payload_axis_tlast,
    input  wire [1:0]   s_eth_payload_axis_tuser, // bit 0 malformed packet, bit 1 RoCE id

    /*
     * AXI frame output with ICRC at the end
     */
    output wire [DATA_WIDTH   - 1 : 0] m_eth_payload_axis_tdata,
    output wire [DATA_WIDTH/8 - 1 : 0] m_eth_payload_axis_tkeep,
    output wire         m_eth_payload_axis_tvalid,
    input  wire         m_eth_payload_axis_tready,
    output wire         m_eth_payload_axis_tlast,
    output wire         m_eth_payload_axis_tuser,

    /*
     * Status
     */
    output wire busy
);

    localparam [1:0]
    STATE_IDLE = 2'd0,
    STATE_PAYLOAD = 2'd1,
    STATE_ICRC = 2'd2;

    localparam CRC_COMP_LATENCY = CRC_COMP_TYPE ? ($clog2(DATA_WIDTH/8) + N_PIPE + 2)  : DATA_WIDTH / 32;

    reg [1:0] state_reg = STATE_IDLE, state_next;

    wire [DATA_WIDTH   - 1 : 0] axis_to_mask_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] axis_to_mask_tkeep;
    wire         axis_to_mask_tvalid;
    wire         axis_to_mask_tlast;
    wire [1:0]   axis_to_mask_tuser;
    wire         axis_to_mask_tready;

    wire [DATA_WIDTH   - 1 : 0] axis_masked_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] axis_masked_tkeep;
    wire         axis_masked_tvalid;
    wire         axis_masked_tlast;
    wire [1:0]   axis_masked_tuser;
    wire         axis_masked_tready;

    wire [DATA_WIDTH   - 1 : 0] axis_not_masked_tdata;

    wire [DATA_WIDTH   - 1 : 0]  axis_not_masked_fifo_in_tdata;
    wire [DATA_WIDTH/8 - 1 : 0]  axis_not_masked_fifo_in_tkeep;
    wire         axis_not_masked_fifo_in_tvalid;
    wire         axis_not_masked_fifo_in_tlast;
    wire [1:0]   axis_not_masked_fifo_in_tuser;
    wire         axis_not_masked_fifo_in_tready;

    wire [DATA_WIDTH   - 1 : 0]  axis_not_masked_fifo_out_tdata;
    wire [DATA_WIDTH/8 - 1 : 0]  axis_not_masked_fifo_out_tkeep;
    wire         axis_not_masked_fifo_out_tvalid;
    wire         axis_not_masked_fifo_out_tlast;
    wire [1:0]   axis_not_masked_fifo_out_tuser;
    wire         axis_not_masked_fifo_out_tready;

    wire [DATA_WIDTH   - 1 : 0]  axis_to_icrc_tdata;
    wire [DATA_WIDTH/8 - 1 : 0]  axis_to_icrc_tkeep;
    wire         axis_to_icrc_tvalid;
    wire         axis_to_icrc_tlast;
    wire [1:0]   axis_to_icrc_tuser;
    wire         axis_to_icrc_tready;

    // datapath control signals
    reg          update_crc_request_next;
    reg          update_crc_request_reg;

    reg  [DATA_WIDTH   - 1 : 0]  icrc_s_tdata;
    reg  [DATA_WIDTH/8 - 1 : 0]  icrc_s_tkeep;

    reg  [DATA_WIDTH   - 1 : 0]  icrc_m_tdata_0;
    reg  [DATA_WIDTH   - 1 : 0]  icrc_m_tdata_1;
    reg  [DATA_WIDTH/8 - 1 : 0] icrc_m_tkeep_0;
    reg  [DATA_WIDTH/8 - 1 : 0] icrc_m_tkeep_1;

    reg  [DATA_WIDTH   - 1 : 0]  icrc_m_tdata_temp [DATA_WIDTH / 32 - 1:0];
    reg  [DATA_WIDTH/8 - 1 : 0]  icrc_m_tkeep_temp [DATA_WIDTH / 32 - 1:0];

    reg [15:0] frame_ptr_reg = 16'd0, frame_ptr_next;

    reg [DATA_WIDTH   - 1 : 0] last_cycle_tdata_reg = 0, last_cycle_tdata_next;
    reg [DATA_WIDTH/8 - 1 : 0] last_cycle_tkeep_reg = 0, last_cycle_tkeep_next;

    reg busy_reg = 1'b0;

    reg s_axis_tready_reg = 1'b0, s_axis_tready_next;

    reg  [ 31:0] crc_state = 32'hDEBB20E3;

    // internal datapath
    reg  [DATA_WIDTH   - 1 : 0] m_eth_payload_axis_tdata_int;
    reg  [DATA_WIDTH/8 - 1 : 0] m_eth_payload_axis_tkeep_int;
    reg          m_eth_payload_axis_tvalid_int;
    reg          m_eth_payload_axis_tready_int_reg = 1'b0;
    reg          m_eth_payload_axis_tlast_int;
    reg          m_eth_payload_axis_tuser_int;
    wire         m_eth_payload_axis_tready_int_early;

    wire [DATA_WIDTH/8-1:0] byte_en;
    wire [DATA_WIDTH/8-1:0] byte_en_rev;
    wire [DATA_WIDTH-1:0 ]  din_rev;

    wire [ 31:0] crc_out;
    wire         crc_valid_out;
    wire [ 31:0] crc_out_1;
    wire         crc_valid_out_1;
    reg  [ 31:0] icrc_value;

    wire [ 31:0] icrc_to_fifo;
    wire         icrc_to_fifo_valid;

    reg  [ 31:0] icrc_to_output;
    reg          icrc_to_output_valid;


    reg  [DATA_WIDTH   - 1 : 0] s_axis_tdata_shreg                       [CRC_COMP_LATENCY-1:0];
    reg  [DATA_WIDTH/8 - 1 : 0] s_axis_tkeep_shreg                       [CRC_COMP_LATENCY-1:0];
    reg          s_axis_tvalid_shreg                      [CRC_COMP_LATENCY-1:0];
    reg          s_axis_tready_shreg                      [CRC_COMP_LATENCY-1:0];
    reg          s_axis_tlast_shreg                       [CRC_COMP_LATENCY-1:0];
    reg [1:0]    s_axis_tuser_shreg                       [CRC_COMP_LATENCY-1:0];

    reg          rst_crc_shreg                            [CRC_COMP_LATENCY:0];

    integer i;

    assign byte_en = (axis_masked_tready & axis_masked_tvalid) ? axis_masked_tkeep : 0;


    for (genvar j = 0; j < DATA_WIDTH/8; j = j + 1) begin
        assign byte_en_rev[j] =  byte_en[DATA_WIDTH/8-1-j];
        assign din_rev[j*8 +: 8]     =  axis_masked_tdata[DATA_WIDTH-1-j*8 -: 8];
    end


    assign busy                      = busy_reg;


    assign axis_to_mask_tdata        = s_eth_payload_axis_tdata;
    assign axis_to_mask_tkeep        = s_eth_payload_axis_tkeep;
    assign axis_to_mask_tvalid       = s_eth_payload_axis_tvalid;
    assign axis_to_mask_tlast        = s_eth_payload_axis_tlast;
    assign axis_to_mask_tuser        = s_eth_payload_axis_tuser;
    assign s_eth_payload_axis_tready = axis_to_mask_tready;

    axis_mask_fields_icrc #(
        .DATA_WIDTH(DATA_WIDTH),
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
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
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

        rst_crc_shreg[0] <= axis_masked_tlast & axis_masked_tready & axis_masked_tvalid & axis_masked_tuser[1];

        for (i = 1; i <= CRC_COMP_LATENCY; i = i + 1) begin
            rst_crc_shreg[i] <= rst_crc_shreg[i-1];
        end

    end

    generate

        if (CRC_COMP_TYPE) begin

            crc_gen_byteEn #(
                .DWIDTH(DATA_WIDTH),
                .CRC_WIDTH(32),
                .PIPE_LVL(N_PIPE),
                .CRC_POLY(32'h04C11DB7),
                .INIT(32'hC704DD7B), //  32'hDEBB20E3 reversed 
                .XOR_OUT(32'h00000000),
                .REFIN(1'b1),
                .REFOUT(1'b1)
            ) crc_gen_byteEn_instance (
                .clk(clk),
                .rst(rst),
                .din(din_rev),
                .byteEn(byte_en_rev),
                .dlast(axis_masked_tlast & axis_masked_tready & axis_masked_tvalid),
                .flitEn(axis_masked_tvalid && axis_masked_tready),
                .crc_out(crc_out),
                .crc_out_vld(crc_valid_out)
            );

        end else begin

            CRC32_matrix_pipeline #(
                .DATA_WIDTH(DATA_WIDTH),
                .crc_poly(32'h04C11DB7),
                .crc_init(32'hDEBB20E3),
                .reverse_result(1'b0),
                .finxor(32'h00000000)
            ) CRC32_matrix_pipeline_instance (
                .clk(clk),
                .rst(rst),
                .data_in(axis_masked_tdata),
                .keep_in(axis_masked_tkeep),
                .valid_in(axis_masked_tvalid && axis_masked_tready),
                .last_in(axis_masked_tvalid && axis_masked_tlast && axis_masked_tready),
                .crcout(crc_out),
                .valid_crc_out(crc_valid_out)
            );

        end
    endgenerate

    wire [31:0] crc_out_fifo;
    wire        crc_out_fifo_valid;
    wire        crc_out_fifo_re;

    axis_fifo #(
        .DEPTH(32), // store up to 8 values
        .DATA_WIDTH(32),
        .KEEP_ENABLE(0),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .LAST_ENABLE(0),
        .USER_ENABLE(0)
    ) crc_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata(crc_out),
        .s_axis_tkeep(0),
        .s_axis_tvalid(crc_valid_out),
        .s_axis_tready(), // this fifo shuld be always ready to get data
        .s_axis_tlast(0),
        .s_axis_tid(0),
        .s_axis_tdest(0),
        .s_axis_tuser(0),

        // AXI output
        .m_axis_tdata(crc_out_fifo),
        .m_axis_tkeep(),
        .m_axis_tvalid(crc_out_fifo_valid),
        .m_axis_tready(crc_out_fifo_re),
        .m_axis_tlast(),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );

    assign crc_out_fifo_re = axis_to_icrc_tlast & axis_to_icrc_tvalid & axis_to_icrc_tready;

    assign icrc_to_fifo = crc_out;
    //assign icrc_to_fifo_valid = rst_crc_shreg[2] & crc_valid_out;
    assign icrc_to_fifo_valid = crc_valid_out;


    always @* begin
        update_crc_request_next = update_crc_request_reg;
        if (rst_crc_shreg[CRC_COMP_LATENCY]) begin
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

    generate
        for (genvar j = 0; j <= DATA_WIDTH / 32 - 2; j = j + 1) begin
            always @* begin
                //icrc_m_tdata_temp[j] = {~icrc_to_output, icrc_s_tdata[(j+1)*32-1 : 0]};
                icrc_m_tdata_temp[j] = {~crc_out_fifo, icrc_s_tdata[(j+1)*32-1 : 0]};
                icrc_m_tkeep_temp[j] = {4'hF, {(j+1){4'hF}}};
            end
        end
    endgenerate


    // Append ICRC
    always @* begin
        icrc_m_tdata_0 = 0;
        icrc_m_tdata_1 = 0;
        icrc_m_tkeep_0 = 0;
        icrc_m_tkeep_1 = 0;
        for (i = DATA_WIDTH / 32 - 1; i >= 0; i = i - 1) begin
            if (i == DATA_WIDTH / 32 - 1) begin
                if (icrc_s_tkeep[i*4 +: 4] == 4'hF) begin // Need a new cycle to accomodate the ICRC
                    icrc_m_tdata_0 = icrc_s_tdata;
                    //icrc_m_tdata_1[31:0] =  ~icrc_to_output;
                    icrc_m_tdata_1[31:0] =  ~crc_out_fifo;
                    icrc_m_tkeep_0 = {DATA_WIDTH/32{4'hF}};
                    icrc_m_tkeep_1[3:0] = 4'hF;
                end
            end else begin
                if (icrc_s_tkeep[i*4 +: 8] == 8'h0F) begin // append ~icrc on the next 32 bits
                    icrc_m_tdata_0 = icrc_m_tdata_temp[i];
                    icrc_m_tkeep_0 = icrc_m_tkeep_temp[i];
                end else if (icrc_s_tkeep[i*4 +: 8] == 8'h00) begin // This one shuld not happen (with tvalid asserted)
                    icrc_m_tdata_0 = 0;
                    icrc_m_tdata_1 = 0;
                    icrc_m_tkeep_0 = 0;
                    icrc_m_tkeep_1 = 0;
                end
            end
        end

    end

    always @* begin
        state_next                    = STATE_IDLE;


        last_cycle_tdata_next         = last_cycle_tdata_reg;
        last_cycle_tkeep_next         = last_cycle_tkeep_reg;

        s_axis_tready_next            = 1'b0;

        icrc_s_tdata                  = 0;
        icrc_s_tkeep                  = 0;

        m_eth_payload_axis_tdata_int  = 0;
        m_eth_payload_axis_tkeep_int  = 0;
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

                                if (icrc_m_tkeep_1 == 0) begin
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



                                if (icrc_m_tkeep_1 == 0) begin
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
    reg [DATA_WIDTH   - 1 : 0] m_eth_payload_axis_tdata_reg = 0;
    reg [DATA_WIDTH/8 - 1 : 0] m_eth_payload_axis_tkeep_reg = 0;
    reg m_eth_payload_axis_tvalid_reg = 1'b0, m_eth_payload_axis_tvalid_next;
    reg         m_eth_payload_axis_tlast_reg = 1'b0;
    reg         m_eth_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH   - 1 : 0] temp_m_eth_payload_axis_tdata_reg = 0;
    reg [DATA_WIDTH/8 - 1 : 0] temp_m_eth_payload_axis_tkeep_reg = 0;
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
