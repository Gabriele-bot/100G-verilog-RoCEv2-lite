`resetall `timescale 1ns / 1ps `default_nettype none

module histogrammer #(
    parameter BRAM_SIZE        = 2048, // corresponding to 2**INPUT_VALUE_LSB*CLOCK_PERIOD MAX value
    parameter INPUT_DATA_WIDTH = 32,
    parameter HISTO_DATA_WIDTH = 24,
    parameter INPUT_VALUE_LSB  = 5 // with 3.1us clock means ~0.1us of granularity
) (
    input  wire clk,
    input  wire rst,
    input  wire valid,
    input  wire [INPUT_DATA_WIDTH-1:0] data_in,

    input  wire trigger_read_mem,
    output wire [HISTO_DATA_WIDTH-1 :0] histo_dout,
    output wire [$clog2(BRAM_SIZE)-1:0] histo_index_out,
    output wire rst_done
);

    localparam INDEX_WIDTH = $clog2(BRAM_SIZE);


    reg [HISTO_DATA_WIDTH-1:0] histogram [BRAM_SIZE-1:0];
    reg [INDEX_WIDTH-1:0] index;
    reg [INDEX_WIDTH  :0] reset_index;
    reg reset_done_reg;
    reg [HISTO_DATA_WIDTH -1:0] dout_reg;
    reg [$clog2(BRAM_SIZE)-1:0] histo_index_out_reg;


    // pipelien write and read
    reg [HISTO_DATA_WIDTH-1:0] histo_previous_val;
    reg [INDEX_WIDTH     -1:0] histo_previous_idx;
    reg [HISTO_DATA_WIDTH-1:0] histo_new_val;
    reg [INDEX_WIDTH     -1:0] histo_new_idx;
    reg [1:0]                  input_valid_pipe;
    
    reg read_mem;
    reg [$clog2(BRAM_SIZE)  :0] raddr_counter;
    reg [$clog2(BRAM_SIZE)-1:0] raddr;

    wire [HISTO_DATA_WIDTH-1:0] douta;
    wire [HISTO_DATA_WIDTH-1:0] doutb;

    true_dpram #(
        .ADDR_WIDTH($clog2(BRAM_SIZE)),
        .DATA_WIDTH(HISTO_DATA_WIDTH),
        .STRB_WIDTH(1),
        .NPIPES(0),
        .INIT_VALUE(0),
        .STYLE("bram")
    ) true_dpram_instance (
        .clka (clk),
        .rsta (rst),
        .addra(data_in[INPUT_VALUE_LSB+:INDEX_WIDTH]),
        .dina (),
        .douta(douta),
        .strba(1'b1),
        .ena  (1),
        .rea  (valid),
        .wea  (0),

        .clkb (clk),
        .rstb (rst),
        .addrb(raddr_counter[$clog2(BRAM_SIZE)-1:0]),
        .dinb (0),
        .doutb(doutb),
        .strbb(0),
        .enb  (1),
        .reb  (1),
        .web  (0)
    );

    // write logic

    always @(posedge clk) begin
        if (rst) begin
            reset_index <= 0;
            reset_done_reg <= 1'b0;
            input_valid_pipe[0] <= 1'b0;
            input_valid_pipe[1] <= 1'b0;
            raddr_counter <= BRAM_SIZE;
        end else begin
            if (reset_index < BRAM_SIZE) begin
                histogram[reset_index] <= 'd0;
                reset_index <= reset_index + 1;
                reset_done_reg <= 1'b0;
            end else begin
                reset_done_reg <= 1'b1;
                if (raddr_counter >= BRAM_SIZE) begin // if not reading the mem, continously updating the histo
                    input_valid_pipe[0] <= valid;
                    input_valid_pipe[1] <= input_valid_pipe[0];
                    // first read the memory
                    if (valid) begin
                        index = data_in[INPUT_VALUE_LSB+:INDEX_WIDTH];
                        histo_previous_val <= histogram[index];
                        // keep track of the index
                        histo_previous_idx <= data_in[INPUT_VALUE_LSB+:INDEX_WIDTH];
                    end
                    //add one
                    if (input_valid_pipe[0]) begin
                        histo_new_val <= histo_previous_val + 1;
                        histo_new_idx <= histo_previous_idx;
                    end
                    // now write
                    if (input_valid_pipe[1]) begin
                        histogram[histo_new_idx] <= histo_new_val;
                    end
                end else begin // reading the mem
                    raddr_counter       <= raddr_counter + 1;
                    raddr               = raddr_counter[$clog2(BRAM_SIZE)-1:0]; // variable
                    dout_reg            <= histogram[raddr];
                    histo_index_out_reg <= raddr;
                end

                // if read mem is triggered
                if (trigger_read_mem) begin
                    raddr_counter <= 'd0;
                end
            end

        end
    end

    assign read_mem = raddr_counter < BRAM_SIZE;

    assign histo_dout = dout_reg;
    assign histo_index_out = histo_index_out_reg;
    assign rst_done = reset_done_reg;

endmodule

`resetall