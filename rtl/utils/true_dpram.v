`resetall `timescale 1ns / 1ps `default_nettype none

module true_dpram #
    (
    parameter ADDR_WIDTH     = 16,
    parameter DATA_WIDTH     = 128,
    parameter STRB_WIDTH     = DATA_WIDTH/8,
    parameter SIZE           = 1 << ADDR_WIDTH,
    parameter NPIPES         = 1,
    parameter INIT_VALUE     = {DATA_WIDTH{1'b0}},
    parameter STYLE          = "bram"
)
(
    // Port A

    input wire clka,
    input wire rsta,

    
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output wire [DATA_WIDTH-1:0] douta,
    input  wire [STRB_WIDTH-1:0] strba,

    input wire ena,
    input wire rea,
    input wire wea,

    // Port B
    input wire clkb,
    input wire rstb,

    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output wire [DATA_WIDTH-1:0] doutb,
    input  wire [STRB_WIDTH-1:0] strbb,

    input wire enb,
    input wire reb,
    input wire web
);

    parameter WORD_WIDTH = STRB_WIDTH;
    parameter WORD_SIZE = DATA_WIDTH/WORD_WIDTH;

    reg [DATA_WIDTH-1:0] ramouta, ramoutb;
    reg [DATA_WIDTH-1:0] douta_reg, doutb_reg;

    reg [DATA_WIDTH-1: 0] data_a_pipes, data_b_pipes [NPIPES-1:0] ; // N Stage  Data Pipe line
    reg [NPIPES:0] ena_pipes, enb_pipes  ; // N+1  Stage enable pipe. +1 for the last stage (fabric)

    integer i;
    genvar m;

    (*ram_style=STYLE*) reg [DATA_WIDTH-1:0] mem [SIZE-1:0];

    initial begin
        for(i = 0; i < SIZE ; i = i + 1) begin
            mem[i] = INIT_VALUE;
        end
    end
    
    always @(posedge clka) begin
        if (ena) begin
            if (rea) begin
                ramouta <= mem[addra];
            end

            for (i = 0; i < WORD_WIDTH; i = i + 1) begin
                if (wea && strba[i]) begin
                    mem[addra][WORD_SIZE*i +: WORD_SIZE] <= dina[WORD_SIZE*i +: WORD_SIZE];
                end
            end
        end
    end


    //pipeline

    generate
        always @(posedge clka) begin
            ena_pipes[0] <= ena & rea;
        end

        if (NPIPES > 0) begin
            // First Stage of Pipeline
            always @(posedge clka) begin
                if (ena_pipes[0])
                    data_a_pipes[0] <= ramouta;
            end

            // Middle Stages of pipeline
            if (NPIPES >= 1) begin
                for (m = 1 ; m <= NPIPES; m = m+1) begin
                    always @(posedge clka) begin
                        ena_pipes[m] <= ena_pipes[m-1];
                    end
                end

                for (m = 1 ; m < NPIPES; m = m+1) begin
                    always @(posedge clka) begin
                        if (ena_pipes[m])
                            data_a_pipes[m] <= data_a_pipes[m-1];
                    end
                end
            end

            // Last stage (outside pipeline, in fabric register)
            always @(posedge clka) begin
                if (rsta)
                    douta_reg <= 0;
                else if (ena_pipes[NPIPES]) begin
                    douta_reg <= data_a_pipes[NPIPES-1];
                end
            end
        end else if (NPIPES == 0) begin // No PipeLine, Latency = 2
            always @(posedge clka) begin
                if (rsta)
                    douta_reg <= 0;
                else if (ena_pipes[NPIPES] ) begin
                    douta_reg <= ramouta;
                end
            end
        end else begin // No Pipeline, Latency=1
            always @(*) begin
                douta_reg <= ramouta;
            end
        end
    endgenerate

    assign douta = douta_reg;

    //port B

    always @(posedge clkb) begin
        if (enb) begin
            if (reb) begin
                ramoutb <= mem[addrb];
            end

            for (i = 0; i < WORD_WIDTH; i = i + 1) begin
                if (web && strbb[i]) begin
                    mem[addrb][WORD_SIZE*i +: WORD_SIZE] <= dinb[WORD_SIZE*i +: WORD_SIZE];
                end
            end
        end
    end


    //pipeline

    generate
        always @(posedge clkb) begin
            enb_pipes[0] <= enb & reb;
        end

        if (NPIPES > 0) begin
            // First Stage of Pipeline
            always @(posedge clkb) begin
                if (enb_pipes[0])
                    data_b_pipes[0] <= ramoutb;
            end

            // Middle Stages of pipeline
            if (NPIPES >= 1) begin
                for (m = 1 ; m <= NPIPES; m = m+1) begin
                    always @(posedge clkb) begin
                        enb_pipes[m] <= enb_pipes[m-1];
                    end
                end

                for (m = 1 ; m < NPIPES; m = m+1) begin
                    always @(posedge clkb) begin
                        if (enb_pipes[m])
                            data_b_pipes[m] <= data_b_pipes[m-1];
                    end
                end
            end

            // Last stage (outside pipeline, in fabric register)
            always @(posedge clkb) begin
                if (rstb)
                    doutb_reg <= 0;
                else if (enb_pipes[NPIPES]) begin
                    doutb_reg <= data_b_pipes[NPIPES-1];
                end
            end
        end else if (NPIPES == 0) begin // No PipeLine, Latency = 2
            always @(posedge clkb) begin
                if (rstb)
                    doutb_reg <= 0;
                else if (enb_pipes[NPIPES] ) begin
                    doutb_reg <= ramoutb;
                end
            end
        end else begin // No Pipeline, Latency=1
            always @(*) begin
                doutb_reg <= ramoutb;
            end
        end
    endgenerate

    assign doutb = doutb_reg;

endmodule

`resetall 