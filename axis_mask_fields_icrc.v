
`resetall
`timescale 1ns / 1ps
`default_nettype none


module axis_mask_fields_icrc #
(
    parameter DATA_WIDTH = 64
)
(
    input  wire        clk,
    input  wire        rst,

    /*
     * AXI input
     */
    input  wire [DATA_WIDTH - 1:0] s_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    /*
     * AXI output
     */
    output wire [DATA_WIDTH - 1:0] m_axis_tdata,
    output wire [DATA_WIDTH/8 - 1:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire        m_axis_tuser
);


    localparam [511:0] MASK_FIELDS = {{248{1'b0}}, 264'hff00000000ffff0000000000000000000000000000ffff00ff000000000000ff00};
    localparam [6:0]   STEPS       = 512/DATA_WIDTH;


    reg [6:0] steps_reg = 7'b0, steps_next;

    reg[DATA_WIDTH-1:0] test_vector;

    integer  upper_index;

    reg [DATA_WIDTH - 1:0] m_axis_tdata_int;
    reg [DATA_WIDTH/8 - 1:0]  m_axis_tkeep_int;
    reg         m_axis_tvalid_int;
    reg         m_axis_tready_int = 1'b0;
    reg         m_axis_tlast_int;
    reg         m_axis_tuser_int;

    reg [DATA_WIDTH - 1:0] m_axis_tdata_reg;
    reg [DATA_WIDTH/8 - 1:0]  m_axis_tkeep_reg;
    reg         m_axis_tvalid_reg;
    reg         m_axis_tready_reg = 1'b0;
    reg         m_axis_tlast_reg;
    reg         m_axis_tuser_reg;


    always @* begin

        steps_next = steps_reg;
        
        upper_index = DATA_WIDTH*(steps_reg+1);

        if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
            steps_next = 7'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (STEPS >= steps_reg) begin
                steps_next = steps_reg + 1;
            end
        end

        if (STEPS > steps_reg) begin
            m_axis_tdata_int[DATA_WIDTH - 1:0] = s_axis_tdata[DATA_WIDTH - 1:0] |  MASK_FIELDS [(upper_index-1)-:DATA_WIDTH];
            test_vector = MASK_FIELDS [(upper_index-1)-:DATA_WIDTH];
        end else begin
            m_axis_tdata_int = s_axis_tdata;
        end
        m_axis_tkeep_int  = s_axis_tkeep;
        m_axis_tvalid_int = s_axis_tvalid;
        m_axis_tready_int = m_axis_tready;
        m_axis_tlast_int  = s_axis_tlast;
        m_axis_tuser_int  = s_axis_tuser;

    end

    always @(posedge clk) begin

        if (rst) begin
            steps_reg <= 7'b0;

            m_axis_tdata_reg  <=  {DATA_WIDTH{1'b0}};
            m_axis_tkeep_reg  <=  {DATA_WIDTH/8{1'b0}};
            m_axis_tvalid_reg <=  1'b0;
            //m_axis_tready_reg <=  m_axis_tready_int;
            m_axis_tlast_reg  <=  1'b0;
            m_axis_tuser_reg  <=  1'b0;
        end else begin
            steps_reg <= steps_next;
            if (m_axis_tready_int) begin
                m_axis_tdata_reg  <=  m_axis_tdata_int;
                m_axis_tkeep_reg  <=  m_axis_tkeep_int;
                m_axis_tvalid_reg <=  m_axis_tvalid_int;
                //m_axis_tready_reg <=  m_axis_tready_int;
                m_axis_tlast_reg  <=  m_axis_tlast_int;
                m_axis_tuser_reg  <=  m_axis_tuser_int;
            end
        end


    end

    assign m_axis_tdata  =  m_axis_tdata_reg;
    assign m_axis_tkeep  =  m_axis_tkeep_reg;
    assign m_axis_tvalid =  m_axis_tvalid_reg;
    assign s_axis_tready =  m_axis_tready_int;
    assign m_axis_tlast  =  m_axis_tlast_reg;
    assign m_axis_tuser  =  m_axis_tuser_reg;

endmodule

`resetall