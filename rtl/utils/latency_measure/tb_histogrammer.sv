`timescale 1ns / 1ps

module tb_histogrammer;

    // Parameters
    parameter BRAM_SIZE        = 2048;
    parameter INPUT_DATA_WIDTH = 32;
    parameter HISTO_DATA_WIDTH = 24;
    parameter INPUT_VALUE_LSB  = 5;

    parameter CLOCK_PERIOD = 5ns;

    parameter N_TEST_VALUES = 200;
    parameter MAX_BIN_COUNT_TEST = 256;


    // Testbench signals
    reg clk;
    reg rst;
    reg valid, valid_reg;
    reg [INPUT_DATA_WIDTH-1:0] data_in, data_in_reg;
    wire histo_dout_valid;
    wire [$clog2(BRAM_SIZE)-1:0] histo_index_out;
    wire [HISTO_DATA_WIDTH-1:0] histo_dout;
    wire rst_done;

    reg trigger_read_mem, trigger_read_mem_reg;

    int test_values_counts [0:N_TEST_VALUES-1];
    int test_values_counts_temp [0:N_TEST_VALUES-1];
    int random_index;
    int test_count;

    histogrammer #(
        .BRAM_SIZE(BRAM_SIZE),
        .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH),
        .HISTO_DATA_WIDTH(HISTO_DATA_WIDTH),
        .INPUT_VALUE_LSB(INPUT_VALUE_LSB)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid(valid_reg),
        .data_in(data_in_reg),
        .trigger_read_mem(trigger_read_mem_reg),
        .histo_dout_valid(histo_dout_valid),
        .histo_dout(histo_dout),
        .histo_index_out(histo_index_out),
        .rst_done(rst_done)
    );

    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk; // 100 MHz clock
    end

    initial begin
        for (int i = 0; i < N_TEST_VALUES; i++) begin
            test_values_counts[i] = $urandom % MAX_BIN_COUNT_TEST;
        end
        test_values_counts_temp = test_values_counts;
    end

    always @(posedge clk) begin
        valid_reg <= valid;
        data_in_reg <= data_in;

        trigger_read_mem_reg <= trigger_read_mem;
    end

    
    initial begin
        rst = 1;
        valid = 0;
        data_in = 0;

        // Reset the histogrammer
        #10;
        rst = 0;

        

        // Stimulus: Write values to the histogram
        
        wait (rst_done == 1'b1);
        while (1) begin
            
            random_index = $urandom_range(0, N_TEST_VALUES);
            // check if there is a value to insert
            if (test_values_counts_temp[random_index] > 0) begin
                #(3*CLOCK_PERIOD)
                data_in = random_index << INPUT_VALUE_LSB; // Shift to align with input value LSB
                valid = 1;
                #CLOCK_PERIOD
                valid = 0;
                // reduce by one
                test_values_counts_temp[random_index]  = test_values_counts_temp[random_index] - 1;
            end
            // check if all test numbers are sent
            test_count = 0;
            for (int i = 0; i < N_TEST_VALUES; i++) begin
                test_count = test_count + test_values_counts_temp[i];
            end

            if (test_count == 0) begin
                break;
            end 
        end

        #(10*CLOCK_PERIOD)
        trigger_read_mem = 1'b1;
        #CLOCK_PERIOD
        trigger_read_mem = 1'b0;
        // Read back the histogram
        wait(histo_dout_valid == 1'b1);
        for (int i = 0; i < N_TEST_VALUES; i++) begin
            #(CLOCK_PERIOD/2)
            if (histo_dout == test_values_counts[i]) begin
                $display("Histogram[%0d]: %0d", i, histo_dout);
            end else begin
                $error("[%t] Mismatch found on histogramm entry %0d\n", $time, i);
            end
            #(CLOCK_PERIOD/2)
            $display("Histogram[%0d]: %0d", i, histo_dout);
        end

        // End simulation
        #50;
        $finish;
    end

    

endmodule