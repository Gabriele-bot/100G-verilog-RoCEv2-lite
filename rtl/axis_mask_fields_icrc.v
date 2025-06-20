
`resetall `timescale 1ns / 1ps `default_nettype none


module axis_mask_fields_icrc #(
    parameter DATA_WIDTH = 64,
    parameter USER_WIDTH = 1,
    parameter OUT_REG    = 1 // Output axis register to aid timings
) (
    input wire clk,
    input wire rst,

    /*
     * AXI input
     */
    input  wire [  DATA_WIDTH - 1:0] s_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1:0] s_axis_tkeep,
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire                      s_axis_tlast,
    input  wire  [ USER_WIDTH - 1:0] s_axis_tuser,

    /*
     * AXI output masked
     */
    output wire [  DATA_WIDTH - 1:0] m_axis_masked_tdata,
    output wire [DATA_WIDTH/8 - 1:0] m_axis_masked_tkeep,
    output wire                      m_axis_masked_tvalid,
    input  wire                      m_axis_masked_tready,
    output wire                      m_axis_masked_tlast,
    output wire  [ USER_WIDTH - 1:0] m_axis_masked_tuser,

    /*
     * AXI output not masked (data only. Tkeep, tvalid, tready, tlast and tuser are the same as the masked stream)
     */
    output wire [DATA_WIDTH - 1:0] m_axis_not_masked_tdata
);


    localparam [4095:0] MASK_FIELDS = {
    {3832{1'b0}}, 264'hff00000000ffff0000000000000000000000000000ffff00ff000000000000ff00
    };
    localparam [6:0] STEPS = 4096 / DATA_WIDTH;


    reg [6:0] steps_reg, steps_next;

    reg     [    DATA_WIDTH-1:0] test_vector;

    integer                      upper_index;

    // internal datapath
    reg     [  DATA_WIDTH - 1:0] m_axis_tdata_int;
    reg     [DATA_WIDTH/8 - 1:0] m_axis_tkeep_int;
    reg                          m_axis_tvalid_int;
    reg                          m_axis_tready_int_reg = 1'b0;
    reg                          m_axis_tlast_int;
    reg  [ USER_WIDTH - 1:0]     m_axis_tuser_int;
    wire                         m_axis_tready_int_early;

    reg     [  DATA_WIDTH - 1:0] m_axis_not_masked_tdata_int;

    reg                          s_axis_tready_next;
    reg                          s_axis_tready_reg;

    wire [DATA_WIDTH   - 1 : 0] s_output_reg_axis_tdata;
    wire [DATA_WIDTH/8 - 1 : 0] s_output_reg_axis_tkeep;
    wire                        s_output_reg_axis_tvalid;
    wire                        s_output_reg_axis_tready;
    wire                        s_output_reg_axis_tlast;

    wire [DATA_WIDTH+USER_WIDTH - 1 : 0] s_output_reg_axis_tuser; // to accomodate not masked data

    assign s_axis_tready = s_axis_tready_reg;


    always @* begin

        steps_next  = steps_reg;

        upper_index = DATA_WIDTH * (steps_reg + 1);

        if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            steps_next = 7'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (steps_reg <= STEPS) begin
                steps_next = steps_reg + 1;
            end
        end

        if (STEPS > steps_reg) begin
            m_axis_tdata_int[DATA_WIDTH - 1:0] = s_axis_tdata[DATA_WIDTH - 1:0] |  MASK_FIELDS [(upper_index-1)-:DATA_WIDTH];
            test_vector = MASK_FIELDS[(upper_index-1)-:DATA_WIDTH];
        end else begin
            m_axis_tdata_int = s_axis_tdata;
        end
        m_axis_not_masked_tdata_int <= s_axis_tdata;
        s_axis_tready_next = m_axis_tready_int_early;
        m_axis_tkeep_int   = s_axis_tkeep;
        m_axis_tvalid_int  = s_axis_tvalid;
        m_axis_tlast_int   = s_axis_tlast;
        m_axis_tuser_int   = s_axis_tuser;

    end

    always @(posedge clk) begin

        if (rst) begin
            steps_reg <= 7'b0;

        end else begin
            s_axis_tready_reg <= s_axis_tready_next;
            steps_reg <= steps_next;
        end
    end


    // output datapath logic
    reg [   DATA_WIDTH - 1:0] m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] m_axis_tkeep_reg = 8'd0;
    reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                       m_axis_tlast_reg = 1'b0;
    reg [  USER_WIDTH - 1:0]  m_axis_tuser_reg = {USER_WIDTH{1'b0}};

    reg [   DATA_WIDTH - 1:0] m_axis_not_masked_tdata_reg = 64'd0;

    reg [   DATA_WIDTH - 1:0] temp_m_axis_tdata_reg = 64'd0;
    reg [DATA_WIDTH / 8 -1:0] temp_m_axis_tkeep_reg = 8'd0;
    reg temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg temp_m_axis_tlast_reg = 1'b0;
    reg [   USER_WIDTH - 1:0] temp_m_axis_tuser_reg = {USER_WIDTH{1'b0}};

    reg [   DATA_WIDTH - 1:0] temp_m_axis_not_masked_tdata_reg = 64'd0;

    // datapath control
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    assign s_output_reg_axis_tdata = m_axis_tdata_reg;
    assign s_output_reg_axis_tkeep = m_axis_tkeep_reg;
    assign s_output_reg_axis_tvalid = m_axis_tvalid_reg;
    assign s_output_reg_axis_tlast = m_axis_tlast_reg;
    assign s_output_reg_axis_tuser = {m_axis_tuser_reg, m_axis_not_masked_tdata_reg};

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_axis_tready_int_early = s_output_reg_axis_tready || (!temp_m_axis_tvalid_reg && !m_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_axis_tvalid_next = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_int_to_output = 1'b0;
        store_axis_int_to_temp = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_axis_tready_int_reg) begin
            // input is ready
            if (s_output_reg_axis_tready || !m_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axis_tvalid_next = m_axis_tvalid_int;
                store_axis_int_to_temp  = 1'b1;
            end
        end else if (s_output_reg_axis_tready) begin
            // input is not ready, but output is ready
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_axis_tvalid_reg <= m_axis_tvalid_next;
        m_axis_tready_int_reg <= m_axis_tready_int_early;
        temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

        // datapath
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= m_axis_tdata_int;
            m_axis_tkeep_reg <= m_axis_tkeep_int;
            m_axis_tlast_reg <= m_axis_tlast_int;
            m_axis_tuser_reg <= m_axis_tuser_int;

            m_axis_not_masked_tdata_reg <= m_axis_not_masked_tdata_int;

        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
            m_axis_tuser_reg <= temp_m_axis_tuser_reg;

            m_axis_not_masked_tdata_reg <= temp_m_axis_not_masked_tdata_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= m_axis_tdata_int;
            temp_m_axis_tkeep_reg <= m_axis_tkeep_int;
            temp_m_axis_tlast_reg <= m_axis_tlast_int;
            temp_m_axis_tuser_reg <= m_axis_tuser_int;

            temp_m_axis_not_masked_tdata_reg <= m_axis_not_masked_tdata_int;
        end

        if (rst) begin
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tready_int_reg <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end
    end
    
    generate
        if (OUT_REG) begin

            // to aid timings
            axis_srl_register #(
                .DATA_WIDTH(DATA_WIDTH),
                .USER_ENABLE(1),
                .USER_WIDTH(USER_WIDTH+DATA_WIDTH)
            ) rx_axis_srl_fifo (
                .clk(clk),
                .rst(rst),

                // AXI input
                .s_axis_tdata (s_output_reg_axis_tdata ),
                .s_axis_tkeep (s_output_reg_axis_tkeep ),
                .s_axis_tvalid(s_output_reg_axis_tvalid),
                .s_axis_tready(s_output_reg_axis_tready),
                .s_axis_tlast (s_output_reg_axis_tlast ),
                .s_axis_tuser (s_output_reg_axis_tuser),
                .s_axis_tid   (0),
                .s_axis_tdest (0),

                // AXI output
                .m_axis_tdata (m_axis_masked_tdata ),
                .m_axis_tkeep (m_axis_masked_tkeep ),
                .m_axis_tvalid(m_axis_masked_tvalid),
                .m_axis_tready(m_axis_masked_tready),
                .m_axis_tlast (m_axis_masked_tlast ),
                .m_axis_tuser ({m_axis_masked_tuser, m_axis_not_masked_tdata})
            );
        end else begin

            assign m_axis_masked_tdata      = s_output_reg_axis_tdata ;
            assign m_axis_masked_tkeep      = s_output_reg_axis_tkeep ;
            assign m_axis_masked_tvalid     = s_output_reg_axis_tvalid;
            assign s_output_reg_axis_tready = m_axis_masked_tready;
            assign m_axis_masked_tlast      = s_output_reg_axis_tlast ;
            assign {m_axis_masked_tuser, m_axis_not_masked_tdata}      = s_output_reg_axis_tuser;

        end
    endgenerate

endmodule

`resetall