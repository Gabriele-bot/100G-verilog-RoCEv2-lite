`resetall `timescale 1ns / 1ps `default_nettype none

module test_ram #
    (
    parameter ADDR_WIDTH     = 16,
    parameter DATA_WIDTH     = 128,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter SIZE = 1 << ADDR_WIDTH,
    parameter NPIPES = 1,
    parameter STYLE  = "bram"
)
(
    input wire clk,
    input wire rst,

    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [ADDR_WIDTH-1:0] raddr,
    input  wire [DATA_WIDTH-1:0] din,
    output wire [DATA_WIDTH-1:0] dout,
    input  wire [STRB_WIDTH-1:0] strb,

    input wire ena,
    input wire ren,
    input wire wen
);

    parameter WORD_WIDTH = STRB_WIDTH;
    parameter WORD_SIZE = DATA_WIDTH/WORD_WIDTH;

    reg [DATA_WIDTH-1:0] ramout;
    reg [DATA_WIDTH-1:0] dout_reg;

    reg [DATA_WIDTH-1: 0] data_pipes [NPIPES-1:0] ; // N Stage  Data Pipe line
    reg                   ena_pipes [NPIPES:0] ; // N+1  Stage enable pipe. +1 for the last stage (fabric)

    integer i;

    (*ram_style=STYLE*) reg [DATA_WIDTH-1:0] mem [SIZE-1:0];
    always @(posedge clk) begin
        if (ena) begin
            if (ren) begin
                ramout <= mem[raddr];
            end

            for (i = 0; i < WORD_WIDTH; i = i + 1) begin
                if (wen && strb[i]) begin
                    mem[waddr][WORD_SIZE*i +: WORD_SIZE] <= din[WORD_SIZE*i +: WORD_SIZE];
                end
            end
        end
    end


    //pipeline

    generate
        always @(posedge clk) begin
            ena_pipes[0] <= ena & ren;
        end

        if (NPIPES > 0) begin
            // First Stage of Pipeline
            always @(posedge clk) begin
                if (ena_pipes[0])
                    data_pipes[0] <= ramout;
            end

            // Middle Stages of pipeline
            if (NPIPES >= 1) begin
                for (genvar i = 1 ; i <= NPIPES; i = i+1) begin
                    always @(posedge clk) begin
                        ena_pipes[i] <= ena_pipes[i-1];
                    end
                end

                for (genvar i = 1 ; i < NPIPES; i = i+1) begin
                    always @(posedge clk) begin
                        if (ena_pipes[i])
                            data_pipes[i] <= data_pipes[i-1];
                    end
                end
            end

            // Last stage (outside pipeline, in fabric register)
            always @(posedge clk) begin
                if (rst)
                    dout_reg <= 0;
                else if (ena_pipes[NPIPES]) begin
                    dout_reg <= data_pipes[NPIPES-1];
                end
            end
        end else if (NPIPES == 0) begin // No PipeLine, Latency = 2
            always @(posedge clk) begin
                if (rst)
                    dout_reg <= 0;
                else if (ena_pipes[NPIPES] ) begin
                    dout_reg <= ramout;
                end
            end
        end else begin // No Pipeline, Latency=1
            always @(*) begin
                dout_reg <= ramout;
            end
        end
    endgenerate

    assign dout = dout_reg;

endmodule

`resetall 