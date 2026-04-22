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
    output wire                         histo_dout_valid,
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
    reg [$clog2(BRAM_SIZE)-1:0] histo_index_out_pipes [2:0];
    reg [1:0] histo_dout_valid_pipes;


    // pipeline write and read
    reg [HISTO_DATA_WIDTH-1:0] histo_new_val;

    reg [INDEX_WIDTH     -1:0] histo_wr_idx_pipes [2:0];


    reg [2:0]                  input_valid_pipe;

    reg read_mem;
    reg [$clog2(BRAM_SIZE)  :0] raddr_counter;
    reg [$clog2(BRAM_SIZE)-1:0] raddr;

    wire [$clog2(BRAM_SIZE)-1:0] addra;
    wire [$clog2(BRAM_SIZE)-1:0] addrb;

    wire [HISTO_DATA_WIDTH-1:0] dinb;

    wire [HISTO_DATA_WIDTH-1:0] douta;
    wire [HISTO_DATA_WIDTH-1:0] doutb;

    wire web, reb;

    // !! WARNING!!
    // Histrogrammer not able to update the ram properly if valids are not spread by 3 clock cycles!!!


    // Port A
    /*
    READ
    Read counts stored in the RAM, use data_in as address
    WRITE
    Used to reset the memory
    */    

    // Port B
    /*
    READ
    Read counts stored in the RAM when read mem is triggered
    WRITE
    Write histogram updated value
    */ 


    // 2 clycles latency
    true_dpram #(
        .ADDR_WIDTH($clog2(BRAM_SIZE)),
        .DATA_WIDTH(HISTO_DATA_WIDTH),
        .STRB_WIDTH(1),
        .NPIPES(0),
        .INIT_VALUE(0),
        .STYLE("auto")
    ) true_dpram_instance (
        .clka (clk),
        .rsta (rst),
        .addra(addra),
        .dina ('d0),
        .douta(douta),
        .strba(1'b1),
        .ena  (1),
        .rea  (valid),
        .wea  (reset_index < BRAM_SIZE),

        .clkb (clk),
        .rstb (rst),
        .addrb(addrb),
        .dinb (dinb),
        .doutb(doutb),
        .strbb(1'b1),
        .enb  (reset_done_reg), // disable port b if in reset phase
        .reb  (reb),
        .web  (web)
    );

    always @(posedge clk) begin
        if (rst) begin
            reset_index         <= 0;
            reset_done_reg      <= 1'b0;
            input_valid_pipe[0] <= 1'b0;
            input_valid_pipe[1] <= 1'b0;
            raddr_counter <= BRAM_SIZE;
            histo_index_out_pipes <= {'d0,'d0,'d0};
            histo_wr_idx_pipes    <= {'d0,'d0,'d0};
            histo_dout_valid_pipes <= 2'b00;
        end else begin
            if (reset_index < BRAM_SIZE) begin
                reset_index         <= reset_index + 1;
                reset_done_reg      <= 1'b0;
                input_valid_pipe[0] <= 1'b0;
                input_valid_pipe[1] <= 1'b0;
                input_valid_pipe[2] <= 1'b0;
            end else begin
                reset_done_reg <= 1'b1;
                if (raddr_counter >= BRAM_SIZE) begin // if not reading the mem, continously updating the histo
                    input_valid_pipe   <= {input_valid_pipe[1:0], valid};
                    histo_wr_idx_pipes <= {histo_wr_idx_pipes[1:0], data_in[INPUT_VALUE_LSB+:INDEX_WIDTH]};
                    if (input_valid_pipe[1]) begin
                        histo_new_val <= douta + 1;
                    end

                    histo_dout_valid_pipes[0]  <= 1'b0;
                end else begin // reading the mem
                    raddr_counter              <= raddr_counter + 1;
                    raddr                      = raddr_counter[$clog2(BRAM_SIZE)-1:0]; // variable
                    dout_reg                   <= histogram[raddr];
                    histo_index_out_pipes[2:0] <= {histo_index_out_pipes[1:0], raddr};
                    histo_dout_valid_pipes[0]  <= 1'b1;
                end
                histo_dout_valid_pipes[1]  <= histo_dout_valid_pipes[0];

                // if read mem is triggered
                if (trigger_read_mem) begin
                    raddr_counter <= 'd0;
                end
            end

        end
    end

    // if reset on going write zero everywhere
    // if not use data_in as address
    assign addra = reset_index < BRAM_SIZE ? reset_index : data_in[INPUT_VALUE_LSB+:INDEX_WIDTH];

    assign addrb = raddr_counter >= BRAM_SIZE ? histo_wr_idx_pipes[2] : raddr_counter[$clog2(BRAM_SIZE)-1:0];
    assign web = input_valid_pipe[2] && raddr_counter >= BRAM_SIZE;
    assign reb = raddr_counter < BRAM_SIZE;
    assign dinb = histo_new_val;

    assign histo_dout_valid = histo_dout_valid_pipes[1];
    assign histo_dout = doutb;
    assign histo_index_out = histo_index_out_pipes[1];
    assign rst_done = reset_done_reg;

endmodule

`resetall